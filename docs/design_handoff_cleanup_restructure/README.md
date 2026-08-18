# Handoff: Cleanup restructure + browse by file type

## Overview

Two changes to DustEater (`wireframe-sensei/DustEater`, branch `master`), a SwiftUI macOS disk-space app:

1. **Restructure the app around a scan → ranked findings → review → receipt flow.** The current build presents five sidebar destinations as equal peers (Disks & Folders, Overview, Duplicates & Large Files, Developer Kit, App Manager), which makes the user work out where their wasted space is. The redesign reduces the sidebar to three items and makes a ranked Cleanup screen the post-scan landing. Duplicates and Developer Kit become *sections of a result*, not destinations.
2. **Add a browse-by-file-type lens** inside Explore, so users can look at only Videos, Photos, Documents and so on while deciding what to do.

The unifying idea, which the implementation should preserve: **Cleanup is system junk the app may rank and recommend. Explore is the user's own content, which the app must never recommend deleting — only help them find and judge.** Every safety rule below follows from that split.

> **A note on the prototypes this document used to reference.** The interactive HTML prototypes (`Dust Eater Glass v2.dc.html` and its predecessors) load a design-system asset bundle from a `_ds/` path that lives in the design project, not this repo — checked out here, they render unstyled, which is worse than not having them, so they were deliberately left out. This README is self-contained (every type size, radius, colour token and copy string referenced below is written out in place), and now that all eight items are shipped, the SwiftUI source under `Sources/DustEaterApp/` is the more accurate visual reference regardless. The prototypes still exist in the design project if you need the original interactive version.

## Implementation status — updated 17 Aug 2026

**All eight items are shipped.** The screen specs below are now built reference, not open work — read the as-built notes on each before changing anything. Read this section before treating anything below as open work — the screen specs for shipped items remain as built reference, not as a to-do list.

| # | Item | Status |
| --- | --- | --- |
| 1 | Ranked Cleanup screen as the post-scan default | Shipped |
| 2 | App-wide selection + tray + Review screen | Shipped |
| 3 | Trash-by-default, undo, no pre-selection | Shipped |
| 4 | Receipt with before/after free space | Shipped |
| 5 | Streaming scan with actionable partials | Shipped |
| 6 | Browse by type in Explore, with QuickLook thumbnails | Shipped |
| 7 | Permission onboarding and the purgeable-space explanation | Shipped |
| 8 | Menu bar monitoring | Shipped |

### Decisions taken during implementation that differ from the plan below

- **`DuplicatesView` and `DeveloperKitView` were removed outright**, not retained alongside the findings sections. Their content lives in Cleanup as findings.
- **`isUserContent` is now live.** Item 6 put user files into the selection, so Review genuinely drops the permanent-delete option once any Explore file is selected.
- **`CleanupScanner` was absorbed into `ScanCoordinator`** and the standalone file deleted. Findings must be live in both the Scanning card and the Cleanup screen across overlapping timelines; a second observable object gated behind `.finished` could not represent that without the views reconciling two feeds. `ScanCoordinator.findings` / `.inFlightFindingIDs` are the single source both read, and they persist unchanged across cancel.
- **`ScanState` gained a `.cancelled` case.** Cancelling before the tree completes cannot honestly report `.finished`, and `.idle` would imply findings reset — which they must not. Cancelling *after* the tree finishes (cutting short only duplicate hashing) stays `.finished`, since the tree is still legitimate.
- **Most findings do not need the assembled tree.** Package manager caches, Xcode's fixed cache paths, simulator runtimes (`PurgeScanner.fixedPathCategories`), unused applications (`AppManagerScanner.scanInstalledApps`) and old downloads run as independent scans from the moment `startScan` is called. Only project-local build-artifact discovery and duplicate detection need the finished tree, and they run after `.finished`, so Explore is never held up by duplicate hashing.
- **Removed as superseded:** the bare-spinner `ScanningStateView` and `totalDiskSize` tracking.

### Known limitation — I/O queue fairness

Fast-path finding scans and the main tree scan share `BlockingIO`'s single global I/O queue. On a full `/` scan of 10M+ items, no findings appear for the first ~30–40 seconds, because the ~30 fast-path requests queue behind work the unbounded main scan already submitted. This is later than the Scanning screen's copy promises. `BlockingIO` was deliberately not touched — it is a shared primitive every scan depends on, and tuning its fairness is separately-riskable surgery. Recorded in `CLAUDE.md`.

Design guidance if this is revisited: the fast-path scans are the ones producing the user-visible payoff in the first seconds, so they should be the ones that jump the queue — the tree walk only matters once Explore is open. Until then, the in-flight row should name what it is waiting on rather than staying generic, so a user sitting for 40 seconds is told what is happening. That copy change carries no `BlockingIO` risk.

### What item 6 shipped, and what it decided

- **The type index folds into the existing `DiskScanner` walk** as a value-type accumulator, the same pattern the walk already uses for size and item count — not a seventh scan. Benchmarked cache-warmed in alternating order: 107K files / 22 GB came out -3.2%, and an 8,500-file node_modules-heavy tree (worst case for the classifier) +0.1%. Both are noise. No measurable cost to the walk.
- **Photos-managed originals reuse the existing `.reportOnly` + hint mechanism** rather than introducing a second lock concept. iCloud files are badged.
- **Selections route through the same `SelectionStore` → `ReviewView` → `CleanupCommitter` pipeline as Cleanup.** There is no second delete path, which is what safety rule 10 depends on.
- **`.app` bundles are detected structurally**, and the file list caps at 2,000 entries per type. `CleanupItemSource` was not generalised, and the preview pane's Details table was deferred — both recorded in `CLAUDE.md`.
- **Known quirk:** a segmented `Picker` in the filter bar needs `.frame(height: 24)` to size correctly; root cause unresolved, documented in `CLAUDE.md`.

---

## About the design files

The files in this bundle are **design references created in HTML** — prototypes showing intended look, structure and behaviour. They are not production code to copy.

The task is to **recreate these designs in DustEater's existing SwiftUI environment**, using its established patterns: `MacOSDesignTokens.swift` for colours and spacing, the existing `SafetyBadge`, `DuplicateSelectionState`, `PurgeCatalog` and `AppManagerView` types, and native SwiftUI controls (`Toggle`, `Picker`, `List`, `Table`). Do not port HTML/CSS or introduce a web view. Where the prototype uses a `<div>` with a box-shadow ring, the SwiftUI equivalent is a `RoundedRectangle` overlay stroke; where it uses a checkbox from the macOS UI kit, use a native `Toggle(style: .checkbox)`.

The prototypes were built on a community macOS 27 UI kit, so their visual values are already native-accurate. Prefer real system materials (`.regularMaterial`, `.thickMaterial`) and semantic colours over the literal rgba values where SwiftUI offers an equivalent.

## Fidelity

**High-fidelity.** Colours, type sizes, weights, control heights, radii and copy are all final and should be matched. Layout proportions (sidebar 246 pt, toolbar 52 pt, control heights 20/24/28 pt) are deliberate and come from the macOS 27 size scale.

The one exception: the prototype's decorative desktop wallpaper gradient exists only to give the window's translucency something to blur over. It is not part of the app.

---

## Screens / views

### 1. Window shell

**Purpose:** one document window, three-item sidebar, 52 pt toolbar, and a selection tray that spans the content area.

**Layout**
- Window corner radius 16. Active shadow `0 0 1px rgba(0,0,0,0.8), 0 18px 54px rgba(0,0,0,0.3)`; inactive `0 7px 21px rgba(0,0,0,0.2)`. In dark mode add `inset 0 0 0 1px rgba(255,255,255,0.2)` as a rim light.
- **Sidebar**: width 246, padding 14 horizontal / 12 vertical, `.thickMaterial`, 1 pt trailing separator. Row height 28, corner radius 7, 9 pt gap between icon and label, 8 pt horizontal inset.
- **Content area**: flat window background, never a material.
- **Toolbar**: height 52, padding `8 8 8 18`, 8 pt gaps, 1 pt bottom separator. Left: back chevron (28×28 circle, only on Review and Receipt) then a two-line title/subtitle stack (13 pt semibold 590 / 11 pt secondary). Right: a 28 pt pill segmented icon group (search, sort) and a "Watch Disk / Watching" pill with a 7 pt status dot (green when on).

**Sidebar contents, top to bottom**
1. Window controls (stoplights), 14 pt each.
2. **Disk context block** — not a navigable row. Volume name 13 pt semibold with a drive glyph; a 5 pt capacity bar (`linear-gradient(90deg, orange, red)` at 83%); `77.05 GB free of 460.43 GB` in 11 pt monospace tabular; then a purgeable explanation in 11 pt tertiary: *"4.21 GB is purgeable — macOS releases it on demand, so Finder and DustEater may disagree."* This line is required. Without it users conclude the app's numbers are wrong.
3. Separator.
4. **Nav, three rows only**: Cleanup (with the total reclaimable figure right-aligned in 11 pt mono), Explore, Apps. Selected row background = `--selection-active` `rgb(1,101,226)`; grey `rgba(0,0,0,0.14)` when the window is not key.
5. Separator.
6. **Contextual section** — on Cleanup, a "Findings" jump list (one row per finding: 6 pt colour dot, name, size; clicking scrolls to and expands that finding). On Explore, the existing Documents file tree.
7. **Footer**: "Last scanned / Today 10:43 · 2.20s" plus a 20 pt Rescan button.

### 2. Scanning

**Purpose:** make partial findings actionable before the scan completes. A blocking progress bar wastes the user's most attentive thirty seconds.

- A 14 pt-radius card, `fills-opaque-tertiary` with a 1 pt inset hairline: 34 pt indeterminate ring (2.6 s linear rotation), "Scanning Macintosh HD — 599,597 items so far" 13 pt semibold, current path in 11 pt mono tertiary truncated, right-aligned "Found so far / 8.42 GB" in 17 pt mono blue, and a filled blue **Review Findings** button that is enabled throughout.
- Below: "Findings are ready to act on as they arrive — you don't have to wait for the scan to finish."
- Then findings appear one at a time as 12 pt-radius rows (colour dot, name, plain-language reason, size), followed by a 42%-opacity row with a spinning 8-spoke indicator: "Still looking for duplicates and unused applications…"
- A subdued **Cancel Scan** button at the bottom left.

### 3. Cleanup — the post-scan default

**Purpose:** tell the user where their space went, ranked by how much they get back.

**Header row**
- Left: "RECLAIM UP TO" (11 pt semibold 590, 0.04 em tracking, uppercase, tertiary), then the total in 44 pt bold display type with tabular numerals, then "across 6 findings, largest first" 13 pt secondary.
- Right, max width 330: a `.thinMaterial` card with a green check glyph, "Never touched", and *"Documents, your Photos library, iCloud Drive files and anything in Time Machine backups are excluded from every scan."* Stating what is excluded buys more trust than any reassuring copy.

**Finding groups** — 14 pt radius, `fills-opaque-tertiary`, 1 pt inset hairline, 10 pt apart. Header row (padding 15/16):
- Group checkbox (large, 18 pt) — selects every actionable item in the group. **Never checked by default.**
- Disclosure chevron 10 pt, rotates 0°→90° over 120 ms ease.
- Name 14 pt semibold, then a safety pill, then a blue "N selected" pill when any are selected.
- Plain-language reason, 11 pt secondary, `text-wrap: pretty`.
- Right: size 17 pt mono tabular, item count 11 pt tertiary.

Expanded rows (padding `10 16 10 18`, 1 pt bottom hairline, selected background `rgba(0,136,255,0.12)`): checkbox or lock glyph, name 13 pt, path 11 pt mono secondary, optional age note, size 13 pt mono, then two 24 pt square buttons — Quick Look and Reveal in Finder. **Reveal in Finder must be on every row.** It is the most reassuring command in a file utility.

Optional group footer, 11 pt secondary, for caveats plus an action link (e.g. "Open App Manager").

Bottom of screen: a keyboard hint strip, 11 pt tertiary — `Space to preview · ⌘⌫ to Trash · ⌘Z to undo · ⌘R to rescan`. All four must actually work.

**The six findings, in order, with the exact copy used**

| Finding | Safety | Reason line |
| --- | --- | --- |
| Package manager caches | Rebuildable | Downloaded dependencies. Each one is fetched again the next time you install or build. |
| Applications unopened in over a year | Caution | The app bundle plus its caches, preferences and application support files. Uninstalling removes all of them. |
| Downloads older than 12 months | Safe | Installers and archives in your Downloads folder. Nothing here is used by an installed app. |
| Xcode build artifacts | Rebuildable | Xcode regenerates these the next time you build. Nothing in your projects is touched. |
| Duplicate files | Safe | Identical file contents in more than one place. The newest copy of every file is always kept. |
| iOS Simulator runtimes | Report only | Found, but DustEater will not delete these — removing them by hand breaks the simulators Xcode has installed. |

Item-level contents (per-item paths, byte sizes, safety levels and rebuild commands) are in the shipped implementation now — `CleanupFindingID`/`CleanupFinding`/`CleanupItem` in `Sources/DustEaterCore/Cleanup/CleanupFinding.swift`, and the mapping from each underlying scanner's output in `CleanupFindingsBuilder.swift`.

**Report-only is a first-class state.** Simulator runtimes are found, sized and shown, with a lock glyph instead of a checkbox and a footer naming the real remedy: *"Remove runtimes in Xcode → Settings → Platforms, then rescan."* Reporting something you refuse to delete is what an honest tool does; hiding it makes the totals wrong.

### 4. Explore

**Purpose:** the browse lens, for the minority (often developers) who want to see where every gigabyte went. Not the default.

Top row: a large segmented control `Treemap · By Type` (By Type is the default), followed by 11 pt secondary text: *"Your own files. Nothing here is recommended for deletion — anything you select joins the same review list as Cleanup."*

**4a. Treemap** — unchanged from the current build: squarified rects, 2 pt gutters, translucent warm fills with a `rgba(255,255,255,0.16)` inset hairline, name 13 pt bold white and size 11 pt mono `rgba(255,255,255,0.82)`.

**4b. Type board — tiles**

A 4-column grid, 12 pt gaps, tiles min-height 168, radius 14, `fills-opaque-tertiary` with a 1 pt inset hairline. Each tile: a 34 pt rounded-9 icon square in the type's 16%-alpha tint; name 14 pt semibold; file count 11 pt secondary; then pushed to the bottom, total size in 22 pt mono tabular, a 4 pt share-of-total bar in the type's accent, and an 11 pt tertiary affordance line with a chevron.

Eight types, ranked by total size — **not alphabetical**:

| Type | Size | Files | Accent |
| --- | --- | --- | --- |
| Applications | 61.20 GB | 48 | blue |
| Code & Projects | 51.20 GB | 128,442 | teal |
| Videos | 42.18 GB | 214 | purple |
| Photos | 28.64 GB | 6,142 | pink |
| Audio | 9.87 GB | 1,208 | orange |
| Documents | 6.42 GB | 3,455 | green |
| Archives & Installers | 5.11 GB | 88 | yellow |
| Other | 3.44 GB | 9,120 | grey |

**Applications does not drill in.** Its tile reads "Manage in App Manager" and navigates there, because App Manager already does true-footprint uninstall. Do not build a second uninstaller.

**4c. Type detail**

- Header: 24 pt back circle, a 10 pt type colour dot, type name 14 pt semibold, and "214 files · 42.18 GB total" 11 pt secondary.
- **Filter bar** (10 pt radius card): two small segmented controls — **Size** (`All sizes · Over 100 MB · Over 500 MB · Over 1 GB`) and **Not opened in** (`Any time · 6 months+ · 1 year+ · 2 years+`) — with a right-aligned 11 pt mono count of what matches. The real user query is "videos over 500 MB I haven't opened in a year"; type alone is too coarse, so both axes are required.
- **File list**: uppercase 10 pt column headers (Name / Last Opened / Size), rows 8 pt radius: checkbox or lock, name 13 pt with an optional cyan badge, path 11 pt mono secondary, last opened 11 pt right-aligned in a 96 pt column, size 13 pt mono tabular in an 88 pt column. Default sort is size descending — that is why the user came. Clicking a row focuses it (`--selection-active` background); the checkbox selects it. Those are separate gestures.
- **Preview pane — revealed on selection**, not always open. 268 pt wide, `.thinMaterial`, 12 pt radius: "PREVIEW" label with a close button; a 168 pt preview area tinted in the type colour carrying "Press Space for Quick Look"; file name and full path; a Size / Last opened / Details table (details being `3840 × 2160 · 18:42` for video, `48 kHz · 24-bit · 52:10` for audio, `6000 × 4000` for images, `184 pages` for documents); any badge or lock explanation; then Reveal and Select buttons.

  In production the preview area should show a **real thumbnail** via QuickLookThumbnailing (`QLThumbnailGenerator`), with the tinted placeholder only as the fallback while it loads or when generation fails. Nobody deletes a video they cannot see — this pane removes more hesitation than any explanatory copy.
- **Empty state**: "Nothing this large or this old" / "Loosen a filter to see the rest of this category." A filtered-to-nothing category is good news, not a dead view.

### 8. Welcome — onboarding, before the first scan

**Purpose:** ask for Full Disk Access before the first scan, because a scan without it silently under-reports and the user has no way to know.

The welcome flow **replaces the whole window** — no sidebar, no toolbar, only the stoplights in a 52 pt strip. There is no disk data yet, so there is nothing for a sidebar to hold. Content is a single centred 580 pt column.

**Step indicator:** three equal columns across the top, each a 3 pt bar over a 10 pt semibold uppercase label — `What it does · Full Disk Access · Purgeable space`. Completed and current steps use `--accents-blue` and primary label colour; upcoming steps `fills-opaque-quaternary` and tertiary.

**Step 1 — what it does.** Title "DustEater finds space you can safely reclaim" in 26 pt display bold; body "It reads your disk, ranks what is taking up room, and explains what each item is before you decide. Three things hold for every scan." Then a 12 pt radius card of three rows, each a green check glyph plus title and body:

| Title | Body |
| --- | --- |
| Nothing is selected for you | Every checkbox starts empty. DustEater ranks and explains; you decide what goes. |
| The Trash is the default destination | Deletions are recoverable until you empty it, and undo puts them back. |
| Your own files are never recommended | Documents, your Photos library, iCloud Drive files and Time Machine backups are excluded from every scan. |

These are the three safety rules stated as promises up front, so the Cleanup screen does not have to re-argue them.

**Step 2 — Full Disk Access.** Title "Give DustEater Full Disk Access"; body: *"macOS hides system caches and sandboxed app data from every app by default. Without access DustEater still scans and still reports real totals — it just tells you which locations it could not read."* Saying what still works is what makes declining safe.

Then a **3-column numbered diagram**, each column a 12 pt radius card with an 18 pt blue numbered circle, one line of instruction, and a small literal picture of the thing to click pinned to the bottom:

1. "In Privacy & Security, choose Full Disk Access." — three stacked 10 pt rows with the middle one filled `--selection-active`.
2. "Find DustEater in the list." — a 20 pt app-icon square and the app name.
3. "Turn its switch on." — a real small `Switch`, on.

Actions: a filled blue **Open Full Disk Access** (deep link to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`) and a plain **Continue without it**.

**Access is detected, never relaunched.** After the deep link, the step shows a waiting row — spinner plus *"Waiting for access. Leave DustEater open — it notices the moment you grant it."* On grant it becomes a green row: *"Access granted. No relaunch needed — DustEater picked it up on its own."* Implementation: poll readability of one known-protected path (e.g. `~/Library/Containers`) on a timer while this step is visible, and stop polling when it leaves. Do not print the usual "quit and reopen" instruction — the whole point of the polling is that the user never sees it.

**Continue without it** jumps straight to step 3 and puts the app in limited-access mode (below).

**Step 3 — purgeable space.** Title "Why DustEater and Finder disagree"; body: *"Part of your used space is purgeable: files macOS keeps only while there is room, and releases the moment something needs it. Finder counts it as free. DustEater counts it as used, and names it."*

A 14 pt radius card holds a 10 pt capacity bar — 82% used in the orange→red gradient, then a 1% diagonally-hatched yellow purgeable segment — over three figures in 17 pt mono tabular: Used 383.38 GB / **Purgeable 4.21 GB** (label in `--accents-yellow`) / Free 77.05 GB. Footer: *"You never need to reclaim purgeable space yourself. It is here so the numbers on the next screen make sense — the sidebar repeats this line for the volume you are scanning."*

The sidebar's purgeable line **stays** as a reminder; this step is where it gets explained once.

**Footer:** Back on the left from step 2 on; the primary button on the right reads "Continue", and "Start Scan" on the last step — which goes straight to Scanning, not to Cleanup.

### 9. Limited access — what Cleanup shows when access was declined

Above the finding groups, a 12 pt radius card in `rgba(255,141,40,0.10)` with a `rgba(255,141,40,0.20)` inset hairline and an orange warning triangle:

- Title "Scanned without Full Disk Access".
- Body: *"Every figure above is real and measured. These four locations were skipped, so there is more to find than 24.65 GB."* — the figure interpolates the live total.
- A 24 pt **Grant Access** pill on the right, returning to welcome step 2.
- Then the skipped locations, one per row, path in 11 pt mono and reason in 11 pt tertiary:

| Path | Reason |
| --- | --- |
| `/Library/Caches` | System-wide caches, usually the largest single finding |
| `~/Library/Containers` | Sandboxed app data — Mail, Messages, News |
| `~/Library/Group Containers` | Data shared between apps from one developer |
| `/private/var/folders` | Temporary files macOS keeps per session |

**Totals stay honest, not hedged.** The figures are what was actually measured, so they are shown plainly — no "at least" prefix, no asterisk on the 44 pt number. The incompleteness is stated once, in words, next to the list of exactly what is missing. A qualified number invites the user to distrust every number; a plain number plus a named gap does not.

### 10. Menu bar monitoring

**Purpose:** keep the disk figure visible without keeping the app open, and say something only when there is something to say.

**Menu bar item.** A 13 pt capacity ring plus the free-space figure in mono tabular. The ring is always drawn; the figure is what drops when the bar is crowded (a setting, defaulting to keeping it). Clicking fills the item with `--selection-active` while the menu is open, per platform behaviour.

**Dropdown** — 268 pt wide, 10 pt radius, `--surface-menu` with the menu shadow `0 5px 20px rgba(0,0,0,0.3)`, 24 pt rows, 5 pt row radius:

1. Header block: volume name 13 pt semibold, then `77.05 GB free · 4.21 GB purgeable` in 11 pt mono — the same wording as the sidebar, so the two never look like different claims.
2. Separator, then a `RECLAIMABLE — 24.65 GB` section header.
3. The top three findings, each a 6 pt colour dot, name and size. Report-only findings are excluded here: the menu is a call to action and a locked item is not one.
4. **Review in DustEater**, filled with the selection colour — the one primary action.
5. Separator, then `Rescan Now ⌘R`, `Pause Monitoring`, `Monitoring Settings…`.
6. Separator, then `Quit DustEater ⌘Q`.
7. Footer, 11 pt tertiary: "Last checked Today 10:43 · fast checks only".

That footer is load-bearing. The menu's numbers are from the last check, and saying so is what keeps them from reading as live.

**What monitoring actually runs.** Only the fast-path scans — package caches, downloads, unused apps — on a 6-hour timer. **Never the tree walk.** Two reasons: a background `/` walk contends with the same `BlockingIO` queue that already delays foreground findings, and nothing in the menu needs the tree. Explore's data comes from the last manual scan and is not refreshed in the background.

**Notifications** — two independent settings, both off until turned on, neither firing more than once a day:

- **Free space drops below a threshold** — disk pressure, about the volume. Default 10% free. *"Macintosh HD is running low / 38.2 GB free, under your 10% threshold. DustEater found 24.65 GB it can reclaim."*
- **Reclaimable caches pass a threshold** — the growth case the receipt promises. Default 5 GB. *"Caches have built up again / 6.84 GB of rebuildable caches since you last cleaned up. Nothing of yours is included."*

The second counts **only rebuildable findings**, so a growing Photos library or a new video project can never trigger a notification about the user's own content. That is safety rule 10 applied to notifications.

Presentation follows the kit's notification: 16 pt radius, ultra-thick material, 38 pt icon square in the accent's 16% tint, title 13 pt semibold with a "now" timestamp, body 11 pt secondary, then two 24 pt pills — **Review** (vibrant blue, since it sits on a material) and **Notify Less**, which opens the settings rather than silently muting.

**Settings** live in a **separate 520 pt window** (⌘,), not a fourth sidebar item — the sidebar is three items and stays three. One pane, titled Monitoring:

- Show DustEater in the menu bar `Switch`, with "A capacity gauge and the free-space figure."
- "When the bar is crowded" — small segmented `Keep the figure · Gauge only`.
- Separator, then a `TELL ME WHEN` section: the two checkboxes above, each with its threshold as a small mono pop-up pill (`10% · 46.0 GB`, `5 GB`) — the default-with-override answer. Both thresholds show their absolute value next to the percentage, because a percentage alone is not a size anyone can picture.
- Footer note: "Both are off until you turn them on, and never fire more than once a day. The defaults are 10% free and 5 GB — change them only if DustEater is too quiet or too noisy."
- Separator, then "Check every" with a `6 hours` pill and the explicit promise: "Monitoring re-runs only the fast checks — caches, downloads and unused apps. It never walks your whole disk in the background."
- Bottom row: "Findings shown in the menu bar come from the last check, not live." and a Done button.

The receipt's existing "Keep watching this disk" card is the other entry point and needs no change.

### As built — where items 7–8 diverge from the specs above

Four differences, all decided during implementation and all kept:

- **Re-requesting access is a sheet, not a return to the welcome flow.** The Cleanup card's Grant Access button opens the access-request UI as a sheet on the main window rather than replacing the window again. Once the app has scanned, throwing the user back to a full-screen onboarding step loses their results-in-progress context for no gain.
- **Access detection polls a canary path once a second** while the request UI is visible. Same contract as specified — no relaunch instruction ever shown.
- **Monitoring settings are a Monitoring tab in the existing Settings window**, not a new 520 pt window. Cheaper and more conventional; the sidebar still stays three items, which was the actual constraint.
- **`UNUserNotificationCenter` crashes outright outside a packaged `.app` bundle**, so every call site is guarded. This matters for anyone running the app from a build directory — the guard is not optional defensiveness. Recorded in `CLAUDE.md`.

Two `NSPopover` sizing fixes were needed for the dropdown; see `CLAUDE.md`.

### 5. Apps

Largely the current `AppManagerView`, with three changes: rows gain a checkbox that feeds the shared selection; the modes are `Installed · Unused · Developer Tools`; and the detail panel becomes a **breakdown of what an uninstall would remove** — application bundle, caches, application support, preferences and logs, each with its path and size. The best-effort warning stays, with "Nothing here is selected for you — review each one first" appended.

### 6. Review

**Purpose:** one place to see everything about to leave the disk, and the only commit point in the app.

- Title "Review before deleting" 26 pt bold display; subtitle "14 items selected · 12.42 GB will be reclaimed".
- Selected items grouped by their finding or type, each group with an uppercase 10 pt header and its subtotal, rows in a 10 pt radius card. Every row has a 22 pt circular ✕ that removes just that item.
- When rebuildable items are included, a "Rebuild afterward with" card listing the de-duplicated commands (`pnpm install`, `cargo fetch`, `swift package resolve`, `./gradlew build (per project)`, `xcodebuild build (per project)`).
- **Destination** — radio, not a segmented control:
  - *Move to Trash* — "Recoverable until you empty the Trash. Recommended." Default, always.
  - *Delete permanently* — "Frees space immediately. You can't undo this action."
- **The permanent option is removed entirely when the selection contains any of the user's own files**, replaced by: *"Your selection includes your own files, so only the Trash is offered — there is no way to rebuild a document or a video."*
- Footer: Back on the left; on the right a prominent button labelled from the destination — "Move 14 Items to Trash" (blue) or "Delete 14 Items Permanently" (red).

### 7. Receipt

**Purpose:** the payoff. Most utilities underplay this; it is the moment the user decides the app was worth it.

Centred: a 52 pt green check circle; "RECLAIMED" label; the amount in **62 pt bold display type** with tabular numerals; then "Moved to the Trash. Space is fully released when you empty it." A before/after card shows "Free before 77.05 GB → Free now 89.47 GB" with the after figure in green. Then **Undo — Put Back** and Back to Cleanup. Finally, if monitoring is off, a `.thinMaterial` card offering it: "Keep watching this disk / Show free space in the menu bar and tell you when caches build up again," with a switch.

The reclaimed figure is the one place in the app worth animating — count it up over roughly 600 ms. Everything else follows the platform: no spring, no bounce, no entrance animation.

---

## Interactions & behaviour

- **Navigation**: sidebar selects Cleanup / Explore / Apps. Cleanup stays highlighted through Scanning, Review and Receipt, since those are stages of the same task.
- **Selection is app-wide.** One selection set spans Cleanup findings, Explore type files and Apps rows. Selecting in Explore must not create a second, parallel delete path.
- **The selection tray** is pinned to the bottom of the content area whenever the selection is non-empty: total size 17 pt mono, item count, an orange "Includes items marked Caution" pill when applicable, then Clear and a prominent Review button. It answers "how much have I freed so far?" without arithmetic.
- **Group checkbox** selects/deselects every actionable (non-report-only) item in that group.
- **Disclosure** state is per-group and persists while the app is open; the sidebar jump list expands a group and scrolls to it.
- **Row click vs checkbox click** are distinct in the type detail list: the row focuses and opens the preview, the checkbox selects.
- **Commit** moves to the receipt, records the reclaimed byte count, and clears the selection.
- **Undo** restores the selection and the previous free-space figure. For a Trash operation this is a real "Put Back"; for a permanent delete the option is not offered at all.
- **Hover**: essentially none. macOS controls reveal on press. Sidebar and list rows are the only exceptions.
- **Motion**: 120 ms disclosure rotation, 160 ms switch, 200 ms progress fills, 1.4 s `cubic-bezier(0.4,0,0.2,1)` indeterminate bar, ~600 ms count-up on the receipt figure. Nothing else.

## State

| State | Type | Notes |
| --- | --- | --- |
| `screen` | enum | `scanning`, `cleanup`, `explore`, `apps`, `review`, `receipt` |
| `selection` | `Set<ItemID>` | App-wide. **Starts empty and is never seeded.** |
| `expandedGroups` | `Set<GroupID>` | Package manager caches expanded on first run |
| `exploreMode` | enum | `treemap` / `byType`; `byType` is the default |
| `typeID` | optional | nil = type board, set = drilled in |
| `focusedFile` | optional | drives the preview pane |
| `sizeFilter` / `ageFilter` | index | into the threshold tables |
| `destination` | enum | `trash` / `permanent`; forced to `trash` when the selection contains user content |
| `reclaimedBytes` | Int64 | set on commit, drives the receipt and the free-space figure |
| `appMode` / `selectedApp` | index / optional | App Manager |
| `monitoring` | Bool | menu bar presence |
| `onboardingStep` | index | 0–2 within the welcome flow; the flow itself is `screen == welcome` |
| `menuBarOpen` / `settingsOpen` | Bool | dropdown and the Monitoring window |
| `glanceMode` | enum | `figureAndGauge` / `gaugeOnly` |
| `notifyLowSpace` / `notifyJunk` | Bool | the two independent notification settings |
| `lowSpaceThreshold` / `junkThreshold` | value | 10% and 5 GB by default |
| `lastCheck` | date | drives the dropdown footer; monitoring checks run every 6 hours |
| `accessState` | enum | `idle` / `waiting` / `granted` / `skipped`; `skipped` and a real denied check both drive limited-access mode |

Derived, never stored: group subtotals, total reclaimable, selection size, whether the selection contains Caution or user-content items, the filtered file list.

## Safety rules — non-negotiable

1. Nothing destructive is ever pre-selected. Duplicates may *suggest* keeping the newest copy; the user confirms.
2. Trash is the default destination, with a working undo. Permanent deletion is a separate, explicitly worded opt-in.
3. Permanent deletion is withheld entirely for the user's own files.
4. Every item states, in plain language, what it is and what happens without it.
5. Report-only items are shown, sized and locked, with the real remedy named.
6. Photos-library managed originals are locked: "Managed by Photos — delete it in the Photos app."
7. iCloud files are badged and warn that deletion removes them from every device.
8. What is never touched is stated on the Cleanup screen.
9. If a size is an estimate, say so. Users check against Finder, and an unexplained mismatch costs the app its credibility.
10. No recommendation, ranking or auto-selection ever appears on the user's own content.
11. When access is limited, totals are reported as measured — never hedged — and the skipped locations are named on the Cleanup screen.
12. Notifications about growth count rebuildable findings only. A growing Photos library or video project must never produce a notification.

## Design tokens

**Accents** (content-area controls): blue `rgb(0,136,255)`, red `rgb(255,56,60)`, orange `rgb(255,141,40)`, yellow `rgb(255,204,0)`, green `rgb(52,199,89)`, teal `rgb(48,176,199)`, cyan `rgb(50,173,230)`, purple `rgb(175,82,222)`, pink `rgb(255,55,95)`. Use the *vibrant* variants (each ~5% darker and less saturated, e.g. blue `rgb(0,120,240)`) for anything sitting on a blurred material.

**Neutrals are alpha levels of black (white in dark mode), not a grey ramp**: labels primary 85%, secondary 50% (55% dark), tertiary 25%, quaternary 10%, quinary 5%. Control fills run in parallel: opaque primary 10% down to quinary 2%. This is why the UI reads as tinted-transparent rather than painted grey.

**Selection**: `rgb(1,101,226)` when the window is key, `rgba(0,0,0,0.14)` when not. Alternating table rows `rgba(0,0,0,0.05)`.

**Materials**: thin `rgba(246,246,246,0.48)` through ultra-thick `rgba(246,246,246,0.84)`, 20–50 px blur. Sidebars, menu bars, popovers and the tray are materials; windows and content areas never are.

**Type**: SF Pro throughout, weights 400 / 510 / 590 / 700. 13 pt Medium on 16 pt line is the workhorse; 11 pt for secondary text and pills; 10 pt Semibold uppercase with 0.04 em tracking for section headers; 14 pt for group titles; 17 pt for group sizes and stat figures; 22 / 26 / 44 / 62 pt for the display figures noted above. Always tabular numerals for sizes, and always a space before the unit — `2.4 MB`, not `2.4MB`.

**Geometry**: control heights 20 / 24 / 28; radii 5 / 6 / 7 for controls, 8 / 10 / 12 / 14 for cards, 16 for the window, fully round (1000) for pills and large buttons. Sidebar 246 wide, 14 pt side inset, 28 pt rows. Toolbar 52 tall, padding `8 8 8 18`. Table rows 24. Scrollbar gutter 12 with a 6 pt thumb.

**Elevation**: controls carry no drop shadow — they are defined by a 1 pt `rgba(0,0,0,0.08)` ring. Only windows, menus, popovers and tooltips have shadows; the four recipes are listed under the window shell above.

## Assets

None to import. All glyphs in the prototype are hand-cut inline SVG at 11–14 pt sized to SF Symbols' stroke weights; in the app **use the real SF Symbols** — `internaldrive`, `trash`, `square.grid.2x2`, `app.badge.checkmark`, `folder`, `lock`, `magnifyingglass`, `arrow.uturn.backward`, `exclamationmark.triangle.fill`, `checkmark.circle.fill`, `chevron.right`. File thumbnails come from QuickLookThumbnailing. App icons come from `NSWorkspace.icon(forFile:)`. No icon font, no third-party icon set, no emoji anywhere.

## Files in this bundle

Just this README. The interactive HTML prototypes it was written alongside (`Dust Eater Glass v2.dc.html`, `Dust Eater Glass.dc.html`, `Dust Eater UX Review.dc.html`, plus their `support.js`/`doc-page.js`) live in the design project, not this repo — see the note near the top of this document for why.

## Suggested order of work

Items 1–4 are one coherent change and should ship together; a ranked findings screen without a review-and-receipt ending is only half of it.

1. ~~Ranked Cleanup screen as the post-scan default~~ — shipped
2. ~~App-wide selection + tray + Review screen~~ — shipped
3. ~~Trash-by-default, undo, no pre-selection~~ — shipped
4. ~~Receipt with before/after free space~~ — shipped
5. ~~Streaming scan with actionable partials~~ — shipped
6. ~~Browse by type in Explore, with QuickLook thumbnails~~ — shipped
7. ~~Permission onboarding and the purgeable-space explanation~~ — shipped; spec in "8. Welcome" and "9. Limited access"
8. ~~Menu bar monitoring~~ — shipped; spec in "10. Menu bar monitoring"

See "Implementation status" at the top for what shipped differently from this plan.

## Existing files this touches

From the project's screen map:

- `Sources/DustEaterApp/DiskHomeView.swift` — the disk picker collapses into the sidebar context block; skip the screen entirely when there is one volume.
- `Sources/DustEaterApp/DiskHealth/PurgeableSpaceSection.swift` — becomes the sidebar purgeable line.
- `Sources/DustEaterCore/ScanState.swift` — must publish partial findings, not just progress.
- `Sources/DustEaterApp/TreemapView.swift`, `FileTreeListView.swift` — move under Explore's Treemap mode.
- `Sources/DustEaterApp/Inspector/DuplicateSetRow.swift`, `DuplicateSetOverview.swift`, `DuplicateSelectionState.swift`, `DuplicateActionBar.swift` — the action bar is replaced by the app-wide tray; the selection state generalises to all item kinds.
- `Sources/DustEaterApp/DeveloperKit/TargetCardView.swift`, `SafetyBadge.swift`, `PurgeConfirmationSheet.swift` — cards become finding rows; the confirmation sheet is replaced by the Review screen.
- `Sources/DustEaterApp/AppManager/AppManagerView.swift` — gains row checkboxes and the uninstall breakdown panel.
- `Sources/DustEaterApp/Design/MacOSDesignTokens.swift` — check the tokens above against it and extend rather than hard-coding values.
- New: a findings model, an app-wide `SelectionStore`, a file-type index, and the Review/Receipt views.

For items 7–8 specifically:

- `Sources/DustEaterApp/DiskHealth/PurgeableSpaceSection.swift` — its explanation moves into welcome step 3; the sidebar line stays as the reminder.
- `Sources/DustEaterCore/ScanCoordinator.swift` — the 6-hour monitoring check re-runs its fast-path jobs only (`PurgeScanner.fixedPathCategories`, `AppManagerScanner.scanInstalledApps`, old downloads) with no `DiskScanner` walk. That path already exists; monitoring is a second caller, not new scan code.
- New: a welcome/onboarding flow with the three steps, an access-state observable that polls a known-protected path while step 2 is visible, an `NSStatusItem` controller, a Monitoring settings scene (`Settings { }`), and `UNUserNotificationCenter` wiring for the two triggers.
- Notifications need the user's permission. Ask for it **when the first trigger is enabled in settings**, not during onboarding — onboarding asks for Full Disk Access only, and stacking two prompts costs both.
