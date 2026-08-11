# DustEater — App Context for Feature Ideation

This document is a factual snapshot of what DustEater actually does today —
every screen, every user-visible interaction, every backend capability
(including ones not yet exposed in the UI), and every explicitly-deferred
gap. It's written to be handed to another model as grounding context for
generating new feature proposals, so it favors precision over persuasion:
it describes what exists, not what should exist next.

---

## 1. What DustEater is

A native **macOS disk-usage analyzer** — scan a volume or folder, see where
the space went in an interactive treemap, zoom into folders, inspect
individual files, clean up. Comparable in spirit to DaisyDisk, GrandPerspective,
or WizTree, built as a **SwiftUI + AppKit** app with **zero external
dependencies**, distributed as a Swift package (no `.xcodeproj`).

- **Platform**: macOS 14.0+ (deployment target in `Package.swift`).
- **Distribution**: unsigned DMG via GitHub Releases (no Apple Developer
  Program membership behind the project). A single universal binary
  (Apple Silicon + Intel) detects the OS at runtime — genuine Liquid Glass
  rendering on macOS 26+, a Material-based visual equivalent on 14–25, same
  download either way.
- **Permissions model**: runs **unsandboxed** by design, specifically so it
  can read arbitrary user directories. Needs **Full Disk Access**
  (System Settings → Privacy & Security) for anything outside the ordinary
  per-app access grants; the app detects a permission denial and prompts for
  it rather than failing silently.
- **License**: MIT, except the squarified-treemap layout algorithm itself
  (`YMTreeMap.swift`), which is Yahoo's original code under Apache 2.0.

## 2. Architecture

```
Sources/
  DustEaterCore/   Scanning, treemap layout, app-bundle grouping, file
                    operations, filesystem watching, byte formatting.
                    Zero SwiftUI/AppKit dependency (mostly — see note
                    below) so this layer is independently unit-testable.
  DustEaterApp/     The SwiftUI/AppKit GUI — the only target end users run.
  dustbench/        CLI: scan a path, report timing + top entries.
  appsizes/         CLI: true per-app disk footprint across /Applications
                    (the only current consumer of app-bundle grouping —
                    see §5).
Tests/
  DustEaterCoreTests/   35 tests, swift-testing framework, core logic only.
```

*Note on the "no UI dependency" claim*: `DustEaterCore/Treemap/{ColorTheme,TreemapColors}.swift`
import `SwiftUI` for `Color` — the core isn't strictly UI-framework-free, just
free of `AppKit`/full SwiftUI view code.

### Core data model

- **`FileNode`** (struct, `Identifiable` via `path`): `name`, `path`, `size`
  (on-disk **allocated** bytes, not logical/apparent size — matches how
  WizTree-style tools report usage, so sparse/compressed files and
  filesystem block rounding are reflected accurately), `isDirectory`,
  `isSymlink`, `children`, `itemCount`. Equality/hashing deliberately shallow
  (`path` + `size` only — doesn't recurse into `children`, since a full deep
  comparison on a large scan's root would be prohibitively expensive on
  every SwiftUI diff).
  - `node(atPath:)` — descend to a specific descendant by path.
  - `removingNode(atPath:)` — returns a new tree with a node deleted and
    every ancestor's `size`/`itemCount` corrected. No corresponding
    insert/replace method exists yet (see §7 — this is why live filesystem
    changes aren't reconciled automatically).
  - `ancestorPaths(toDescendantAtPath:)` — every ancestor path between a
    node and a descendant, used to drive sidebar auto-expansion.
  - `sortedBySize()` — recursive descending sort (used by `dustbench`; the
    GUI sorts lazily per-level instead, see §4).

- **`ScanState`** (enum): `.idle` → `.scanning(progress)` →
  `.finished(FileNode)`, or one of two failure branches:
  `.needsFullDiskAccess(path:)` (the root itself couldn't be opened — a
  permission/TCC denial) vs. `.failed(message)` (anything else, e.g. path
  doesn't exist). Kept as separate cases specifically so the UI can offer a
  "grant access" call to action instead of a generic error for the
  permission case.

- **`ScanCoordinator`** (`@Observable @MainActor` class): owns the scan
  lifecycle — cancels/replaces its own `Task` on every new scan (the one
  precedent in the codebase for "own a long-lived resource, cancel-and-
  replace on demand," which the filesystem watcher below reuses the same
  shape for). Also owns `zoomNode` (which folder's children the treemap is
  currently showing — `nil` = the scan root/overview), `scanDuration`, and
  `hasDetectedChanges` (set by the FSEvents watcher, see §5).

### Scanning engine

- `getattrlistbulk` (a bulk directory-listing syscall, not `FileManager`
  enumeration) wrapped in `AttrListBulkReader`, bridged onto a bounded
  concurrent `DispatchQueue` (`BlockingIO`, semaphore-capped at
  `activeProcessorCount * 32` in-flight blocking calls) so scanning doesn't
  block Swift concurrency's cooperative thread pool.
- `DiskScanner` (an `actor`, for progress-counter isolation only — the
  actual tree-building recursion is `static`, deliberately kept off the
  actor's executor) fans out one child `Task` per subdirectory via
  `withTaskGroup`, unbounded (task count isn't throttled — only raw
  syscall concurrency is; an earlier bounded-task version deadlocked).
- Permission-denied or vanished-mid-scan directories degrade to an empty
  leaf node rather than aborting the whole scan — silently, with no UI
  indication that a folder was skipped (see §7).
- Hard-linked files are deduplicated by inode within a single scan (counted
  once, zero-sized on repeat encounters) via a lock-protected `Set<UInt64>`
  outside actor isolation for hot-path performance.

---

## 3. Screens and user-visible flows

### 3.1 Home screen (`DiskHomeView`)

The launch screen (`isOnHome == true`). Shows:

- Header: "Disk Analyzer" title/icon, subtitle, and an info panel noting
  that folder sizes may differ slightly from Finder/`du` due to APFS
  snapshots and system overhead.
- A grid of **disk cards** (`DiskCardView`), one per mounted, non-system,
  non-simulator volume: name, path, used/total size, usage percentage, and
  a colored progress bar (green <60%, yellow 60–80%, red >80% usage).
  Clicking a card starts a scan of that volume's root.
- A **"Browse Custom Folder"** card (`CustomFolderCardView`), always
  present regardless of how many disks were found — opens a native
  `NSOpenPanel` folder picker and scans whatever's chosen.
- **Live refresh**: disk cards update automatically — polling every 5
  seconds via a structured-concurrency `.task` (auto-cancelled the instant
  the user leaves this screen, so it never runs during a scan), plus an
  immediate refresh on `NSWorkspace` mount/unmount/rename notifications
  (plugging in a drive updates the grid within ~1s, not on the next poll).
- **Loading / empty states**: a spinner on first appearance
  (`hasLoadedOnce == false`); if volume enumeration comes back empty, an
  explicit "No disks found" message with a Retry button — the Custom
  Folder option stays reachable either way.

### 3.2 Scanning flow

After picking a disk or folder, `ContentView` switches on `ScanState`:

- **`.idle`** — brief "Preparing scan…" spinner while probing root
  access, with a Cancel button (safety net; normally passes through in
  well under a second).
- **`.scanning`** (`ScanningStateView`) — animated circular progress ring
  (ratio of bytes-scanned to the target volume's total capacity, capped at
  99% until actually finished), live item count, live bytes-scanned total,
  and the current path being scanned (middle-truncated), plus Cancel.
- **`.needsFullDiskAccess`** (`PermissionBannerView`) — explains the
  denial, offers **Back to Home** and **Open System Settings** (deep-links
  straight to the Full Disk Access pane via `x-apple.systempreferences:`).
- **`.failed`** (`ErrorStateView`) — shows the scan-failure message
  (e.g. "path doesn't exist") with a **Back to Home** button.

### 3.3 Main browsing screen (`MainContentView`, on `.finished`)

A `NavigationSplitView`: sidebar tree + detail pane (treemap or file
details), plus a toolbar. This is where almost all of the app's
interaction lives.

**Sidebar** (`FileTreeListView`) — a recursive, hand-rolled disclosure-tree
(not SwiftUI's `OutlineGroup`, which has no way to programmatically open a
branch — see §7 for why that mattered). Each level is lazily sorted by size,
descending, only for the branches actually expanded on screen. Each row
shows a folder/doc icon, the name (single line, truncates with a native
tooltip via `.help()` if still too long even after width fixes), a faint
accent-colored capsule bar showing that item's size as a fraction of its
parent, and the formatted size.

**Detail pane** — either:
- The **treemap** (`TreemapView`, see 3.4) for directories/the overview, or
- **`FileDetailsView`** (a full-pane file-info screen) when the sidebar
  selection is a *file*, not a folder — icon (mapped from extension), name,
  size, Type row, Size row, and a selectable monospaced full path.

**Selection vs. zoom** — clicking any node (file or folder), from either
the treemap or the sidebar, sets it as the current *selection* (drives
toolbar actions and, if it's a file, the detail-pane switch above).
Clicking a *folder* additionally *zooms* the treemap into it. Selecting any
node also auto-reveals it in the sidebar: every ancestor `DisclosureGroup`
expands and the row smooth-scrolls into view (centered), regardless of
whether the selection originated in the sidebar or the treemap.

**Toolbar**, left to right:

| Item | Behavior |
|---|---|
| **Home** | Returns to the disk-picker home screen; clears selection. |
| **Go to overview** (`arrow.up.to.line`) | Jumps straight to the unzoomed root regardless of current depth. Disabled when already at the root. Counts as a navigation step — undoable via Back. |
| **Back / Forward** (`chevron.backward` / `chevron.forward`, ⌘[ / ⌘]) | Real browser-style navigation history through zoom changes (not a strict "go up one level" — retraces exactly what was visited, in order, including sidebar jumps to arbitrary folders). Each button independently disabled when its own history stack is empty. |
| **Rescan** (`arrow.triangle.2.circlepath`, orange) | **Only appears** when the FSEvents watcher (§5) detects a filesystem change under the scanned root since the last scan. Re-runs a full scan of the same root. |
| **Reveal in Finder / Copy Path / Delete** | Act on the current selection. Disabled (not hidden) when nothing's selected, so the toolbar never reflows on click. Delete is additionally disabled for protected paths (§6). Delete opens a confirm alert (Cancel / Move to Trash / Delete Permanently); a failure surfaces its own error alert rather than failing silently. |
| **Color theme** (Menu) | 7 themes — see 3.4. |
| **Tools** (Menu) | Currently just **Clear Cache** — empties `~/Library/Caches` and `~/Library/Application Support`; result (success or failure) surfaces as an alert either way. |
| **Info** (`info.circle`) | No action — a static tooltip explaining that folder sizes are approximate (hard links/dedup can make the visible sum exceed real disk usage; true usage is on the home screen). |

### 3.4 The treemap (`TreemapView`)

A `Canvas`-based squarified treemap (the `YMTreeMap` algorithm) showing the
direct children of the current zoom level, tile area proportional to disk
usage.

- **Click** a tile → selects it; if it's a folder, also zooms in.
- **Hover** → a custom glass-material tooltip near the cursor (name, type
  icon, size, item count for directories); a hover-highlight ring on the
  tile that desaturates to system gray when the app window isn't key
  (matches how native selection highlighting dims in the background).
- Large-enough tiles render an inline label (name + size) directly on the
  tile.
- **7 color themes**: Vibrant, Pastel, Neon, Warm, Cool, Rainbow, and
  **Weighted** (the default) — Weighted uses a continuous size-based
  green→yellow→red hue gradient instead of a fixed palette (small ≈ green,
  large ≈ red, log-scaled). The other six assign colors by *file-type
  category* for files (app/archive/video/audio/image/document/other) and a
  hash-based palette-cycling scheme for directories, with a small
  deterministic per-node brightness nudge so same-category siblings still
  read as visually distinct tiles.
- Layout is memoized (`TreemapCache`, keyed on displayed node + window size
  + theme) so window resizes and unrelated state changes don't re-run the
  tessellation algorithm unnecessarily.

---

## 4. Feature inventory (current, shipped)

- Fast recursive directory scanning (`getattrlistbulk` + `TaskGroup`,
  not `FileManager` enumeration).
- Live scan progress (items, bytes, current path) with cancel.
- Interactive squarified treemap, click-to-zoom, hover tooltips, 7 color
  themes.
- Sidebar file tree with lazy per-level sort, size-proportional bars,
  auto-reveal/scroll-to-selection.
- File details pane (icon, type, size, path) for individual files.
- Delete (move to trash or permanent), with a system-protected-path
  safety net — see §6 — and confirmation + failure alerts.
- Clear system caches (with a result alert).
- Reveal-in-Finder and copy-path actions on the current selection.
- Browser-style Back/Forward zoom navigation history, plus a direct
  "jump to overview" shortcut.
- Live disk-capacity refresh on the home screen (polling + mount/unmount
  notifications).
- Filesystem-change detection (FSEvents) with a manual Rescan prompt —
  not automatic live reconciliation (see §5, §7).
- Full Disk Access detection with a direct System Settings deep link.
- Every terminal/error/loading state has an explicit way back to a known-
  good screen (this was audited and fixed explicitly — see §7 and
  `CLAUDE.md`'s "Check for dead ends" section).
- Native macOS chrome throughout: real `NavigationSplitView` + unified
  toolbar, semantic system colors/materials, genuine Liquid Glass on
  macOS 26+ with a Material-based fallback below that (same binary).

## 5. Built but not exposed in the GUI

**App-bundle "true size" grouping.** `DustEaterCore/AppGrouping/` is a
fully implemented, tested subsystem:

- `AppGrouper.findAppBundles` — finds `.app` bundles in a scanned tree
  (doesn't descend into nested bundles, e.g. embedded helper apps — those
  count as part of the parent's own footprint).
- `AppBundleInspector` — reads each bundle's `Info.plist` for its bundle
  identifier and display name.
- `AppGrouper.buildAppDiskEntities` — cross-references each bundle ID
  against the `~/Library` locations macOS uses for hidden per-app storage:
  `Containers`, `Caches`, `Application Support` (by bundle ID, with a
  fallback lookup by display name for older apps that key off that
  instead), `Saved Application State`, `Preferences`.
- `AppSizeMerger.mergeTrueSizes` — folds that hidden storage back into a
  scanned tree as a synthetic **"Associated App Data"** child node per app
  (not by silently inflating the `.app` node's own size — that would break
  the invariant that a directory's size equals the sum of its children's
  sizes, which both the treemap and sidebar rely on).

**This is currently only exercised by the `appsizes` CLI tool** — grep
confirms `ScanCoordinator`/`ContentView` never call any of
`AppGrouper`/`AppSizeMerger`/`buildAppDiskEntities`/`mergeTrueSizes`. The
README's "App bundle grouping" feature bullet describes this backend
capability, not something currently visible inside the GUI app itself.
Wiring it into the GUI (so scanning `/Applications` — or anywhere an app
lives — shows each app's *true* footprint, hidden data included) is a
fully backend-ready feature; the missing piece is entirely UI/integration
work in `ScanCoordinator`/`ContentView`.

## 6. Safety: protected paths

`FileOperations.isSystemProtected` blocks deletion in two different ways:

- **By path prefix** (the folder and everything inside it, no exceptions):
  `/System`, `/Library`, `/Applications`, `/usr`, `/var`, `/etc`, `/tmp`,
  `/bin`, `/sbin`, `/opt`.
- **By exact path only** (the folder itself is blocked, but individual
  items *inside* it stay deletable — since bulk-cleaning clutter out of
  e.g. Downloads is the whole point of the app): `/Users` itself, any
  account's home directory (`/Users/<name>`), and the default folders
  macOS creates in every home directory — Desktop, Documents, Downloads,
  Movies, Music, Pictures, Public, Library. This is path-shape-based, not
  tied to the current user, so it protects every account a full-disk scan
  can see, not just the one running DustEater.

## 7. Deliberate gaps and known inconsistencies

Things that are *not* oversights waiting to be noticed — they're
documented decisions in `CLAUDE.md`, included here so a feature proposal
doesn't accidentally re-litigate a settled trade-off without knowing why:

- **No live reconciliation of filesystem changes.** The FSEvents watcher
  only flips a boolean and offers a manual Rescan — it deliberately does
  *not* try to merge a detected change into the live tree, because
  `FileNode` has no insert/replace method (only `removingNode`), FSEvents
  reports "this directory changed" rather than a diff, and correctly
  propagating a partial re-scan's size/itemCount deltas up every ancestor
  while keeping the treemap cache and sidebar expansion state consistent
  is real, error-prone work. Same reason DaisyDisk/GrandPerspective/
  OmniDiskSweeper don't live-update either.
- **No context menu (right-click) anywhere.** All actions are toolbar-
  driven, acting on the current selection — chosen after an inline per-row
  `Menu` button was found to be the direct cause of sidebar names
  truncating to 2–3 characters (a macOS `Menu` always renders as a
  bordered pull-down regardless of the frame it's given). A `.contextMenu`
  costs zero horizontal width and could be added later as a genuinely
  additive complement, not a replacement.
- **Pastel theme's white tile-label text** has a real contrast issue
  against light tiles — not yet addressed.
- **Color themes are not appearance-aware** — the same 6 fixed palettes
  render identically in light and dark mode.
- **No export/reporting** of scan results (CSV/JSON or otherwise).
- **`FileDetailsView` never went through the HIG design-system rework**
  the rest of the app did — it still hand-draws its own header background
  (`.background(.bar)`) and card backgrounds
  (`Color(nsColor: .controlBackgroundColor)` + `.cornerRadius(12)`) instead
  of using real system materials/containers the way every other screen
  does. A visible inconsistency if you compare it side-by-side with the
  rest of the app.
- **Permission-denied subdirectories mid-scan degrade silently** to an
  empty leaf node with no UI indication that anything was skipped — a
  finished scan can under-report size for folders the app couldn't fully
  read, with no explanation shown.
- **Sidebar width** is a fixed drag range (280–350pt) — noted at one point
  as possibly too tight at deep nesting, not yet revisited.
- **No automated test covers the FSEvents watcher itself** — real FSEvents
  delivery is OS-scheduled and asynchronous (seconds-scale), not practical
  to assert on in a fast unit-test suite.

## 8. Hard constraints (non-negotiable, not just deferred)

- **No external dependencies** — pure Swift Package, `DustEaterCore` has
  zero third-party dependencies by design.
- **Unsandboxed** — required for Full Disk Access to work at all; adding
  App Sandbox entitlements would break the core use case.
- **Unsigned distribution** — no paid Apple Developer Program membership;
  Gatekeeper's first-launch warning is a known, documented, accepted
  consequence, not a bug to silently work around.
- **macOS 14.0 minimum** deployment target.
- **`YMTreeMap.swift`'s Apache 2.0 header/attribution must stay intact** —
  it's Yahoo's original code, used under its original license terms.

## 9. Design system

Built against Apple's official Design Resources macOS UI kit (HIG-
conformant, via a loaded design-system reference in this repo's tooling).
Key rules actually enforced in the codebase:

- Never a hardcoded color — always semantic `Color`/`NSColor` (accent
  color, label hierarchy, system materials) so the app respects the user's
  accent-color choice, Increase Contrast, Reduce Transparency, etc.
- `Font.control` (13pt Medium) for interface chrome (buttons, sidebar rows,
  toolbar labels); real semantic fonts (`.body`, `.headline`, etc.) for
  content text.
- Materials, not solid fills, on every floating/chrome surface — `.bar`/
  `.regularMaterial` for sidebars/toolbars, `.ultraThinMaterial` for
  content-area cards.
- Custom-drawn "this is selected/hovered" indicators must desaturate to
  system gray when the window isn't key, matching native selection
  behavior — implemented for the treemap's hover/selection ring.
- Prefer real system controls (`NavigationSplitView`, `.toolbar`,
  `DisclosureGroup`, etc.) over hand-rolled approximations wherever
  possible; the sidebar's custom disclosure-tree is the one deliberate
  exception, and only because `OutlineGroup` has no programmatic-expansion
  API.

---

## 10. Representative user journeys

**A — First scan of a whole disk**
Home screen → click a disk card → brief "Preparing scan…" → animated
scanning progress → lands on the treemap overview of that volume → click
into a large folder (zooms + sidebar reveals it) → click a file inside
(shows File Details, sidebar still highlights it) → Back button retraces
to the folder view → Home button returns to the disk picker.

**B — Cleaning up a specific folder**
Home screen → "Browse Custom Folder" → pick e.g. `~/Downloads` in the
native folder picker → scan runs → treemap shows what's taking space →
click the biggest tile to select it → Delete from the toolbar → confirm
"Move to Trash" → tree/treemap update immediately, size figures adjust up
the ancestor chain.

**C — Hitting a permission wall**
Home screen → pick a disk/folder DustEater can't fully read → scan
immediately reports `.needsFullDiskAccess` → "Open System Settings" deep-
links to the right pane → user grants access in System Settings → returns
to DustEater → **must** use Back to Home and re-pick the same target (no
in-place retry exists yet — see §7-adjacent note: this is a real gap, not
explicitly called a "deliberate" one).

**D — Noticing external changes**
Scan finishes → user deletes a large file in Terminal or another app while
DustEater is still open → within ~2 seconds, an orange Rescan button
appears in the toolbar → click it → a normal full rescan runs → button
disappears once done. (In-app deletes via DustEater's own Delete button do
*not* trigger this, by design — see §7.)

**E — A scan that fails outright**
Home screen → pick a path that doesn't exist or can't be opened for a
reason other than permissions → `.failed` state shows the specific error
message → "Back to Home" returns to the picker, no dead end.

**F — Exploring visually via the treemap alone**
Scan finishes on the overview → click through several nested folders by
clicking tiles → Back/Forward retrace exactly that click path in order →
"Go to overview" jumps straight back to the root at any point, still
undoable with Back afterward.

---

## 11. Where to look in the code

| Concern | File(s) |
|---|---|
| Scanning engine | `Sources/DustEaterCore/Scanner/` |
| Data model | `Sources/DustEaterCore/Models/FileNode.swift` |
| Scan state machine | `Sources/DustEaterCore/ScanState.swift`, `ScanCoordinator.swift` |
| Treemap layout algorithm | `Sources/DustEaterCore/Treemap/YMTreeMap.swift` |
| Treemap coloring | `Sources/DustEaterCore/Treemap/{ColorTheme,TreemapColors}.swift` |
| App-bundle grouping (unexposed) | `Sources/DustEaterCore/AppGrouping/` |
| Delete/cache/protected-paths | `Sources/DustEaterCore/FileOperations.swift` |
| Filesystem watching | `Sources/DustEaterCore/Scanner/FileSystemWatcher.swift` |
| Home screen | `Sources/DustEaterApp/DiskHomeView.swift` |
| Main browsing screen + toolbar | `Sources/DustEaterApp/ContentView.swift` |
| Sidebar tree | `Sources/DustEaterApp/FileTreeListView.swift` |
| Treemap rendering | `Sources/DustEaterApp/TreemapView.swift` |
| File details pane | `Sources/DustEaterApp/FileDetailsView.swift` |
| Design tokens | `Sources/DustEaterApp/Design/` |
| Engineering conventions & decisions | `CLAUDE.md` (repo root) |
