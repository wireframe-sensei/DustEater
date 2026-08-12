# CLAUDE.md

Guidance for Claude Code (or any agent) working in this repository. This
file records conventions and procedures established through actual work on
the project - not aspirational rules, but what this codebase actually does
and why.

## Writing style

**Never use em dashes (—) or en dashes (–) in anything written for this
repo** - commit messages, code comments, markdown docs, everything. Use a
plain hyphen (`-`) instead, or restructure the sentence. This applies to
new writing and to edits of existing text.

## Project overview

DustEater is a native macOS disk-usage analyzer: SwiftUI + AppKit GUI, no
external dependencies, distributed as a Swift package (no `.xcodeproj`).

- `Sources/DustEaterCore` - scanning (`getattrlistbulk` + `TaskGroup`), the
  squarified treemap layout algorithm, app-bundle grouping, byte formatting.
  No SwiftUI/AppKit dependency - keep it that way, it's what makes the logic
  unit-testable.
- `Sources/DustEaterApp` - the GUI.
- `Sources/dustbench`, `Sources/appsizes` - CLI tools on top of `DustEaterCore`.
- `Tests/DustEaterCoreTests` - tests for the core library.
- `.claude/skills/macos-hig-design-system/` - the design-system skill this
  project's UI work is built from (`SKILL.md`, `references/swift.md`,
  `references/color-tokens.md`, `references/sizing-tokens.md`,
  `references/components.md`, `references/materials-and-effects.md`,
  `assets/MacOSDesignTokens.swift`). Load it before UI/design work - see below.

## Build & test

```sh
swift build              # debug
swift build -c release   # release
swift test
swift run DustEaterApp
```

Always run `swift build` after any change before considering it done. For
UI-visible changes, be explicit that you can't see/run the GUI yourself -
state what's verified (build succeeds) vs. what's an untested visual guess,
and ask the user to confirm before committing when genuinely uncertain
about the result. Don't claim something is "confirmed working" based only
on a build succeeding on this one local machine - see the SDK/toolchain
gotcha below for why that bit us once already.

## Design system conventions

This app was migrated from ad-hoc SwiftUI styling to the macOS HIG design
system skill. The established conventions:

- **Never hardcode colors.** Use `Color.accentColor` (never a literal blue),
  `Color(nsColor: .separatorColor)` / `.controlBackgroundColor` /
  `.windowBackgroundColor` / `.systemRed` etc., or a token from
  `Design/MacOSDesignTokens.swift` if there's genuinely no system
  equivalent (e.g. `Color.progressTrack`).
- **Typography**: `Font.control` (`.system(size: 13, weight: .medium)`,
  defined in `Design/MacOSDesignTokens.swift`) for interface chrome - button
  labels, menu items, sidebar rows, table rows. Real semantic fonts
  (`.body`, `.headline`, `.title2`, `.callout`, etc.) for content text.
  `DustEaterTheme.Typography` (in `Design/DustEaterTheme.swift`) aliases
  onto real semantic `Font` values, not fixed point sizes - keep it that way.
- **Control sizing**: set `.controlSize()` once at a container level, never
  thread a size parameter through the view tree by hand. Custom-drawn
  controls read `@Environment(\.controlMetrics)` (also in
  `MacOSDesignTokens.swift`) rather than hardcoding radii/heights.
  - `ControlMetrics.isCapsule` is `true` at `.large`/`.extraLarge` per the
    kit's `Button/Radius` token (large buttons become full capsules). This
    is **only for controls actually drawing themselves as a compact
    button.** `DiskCardView`/`CustomFolderCardView` in `DiskHomeView.swift`
    are wide custom cards, not pill buttons - they deliberately read only
    `metrics.cornerRadius` and ignore `isCapsule`, documented inline. Don't
    "fix" that to use `isCapsule` - it would turn them into giant pills.
- **Materials**: sidebars/toolbars get `.bar` or `.regularMaterial`;
  `.ultraThinMaterial` for content-area panels/cards. Real system chrome
  (`NavigationSplitView`, `.toolbar`) gets its material from the OS
  automatically - don't add explicit `.background(material)` there, it's
  redundant and can actually defeat the system chrome's own vibrancy.
- **`controlActiveState`**: custom-drawn (non-system) "this is highlighted"
  indicators must desaturate toward `Color(nsColor: .systemGray)` when the
  window isn't key, matching how real selection highlighting works. System
  controls (`List(selection:)`, `Menu`) already do this for free.
  `TreemapView`'s hover highlight is the one hand-drawn example - see
  `highlightColor` there for the pattern.
- **Prefer real system APIs over hand-rolled approximations.** The chrome
  rewrite (`MainContentView` in `ContentView.swift`) replaced a hand-rolled
  `HStack` "sidebar" + fake "toolbar" `VStack`s (styled with `.background(.bar)`
  to *look* like chrome) with a real `NavigationSplitView` + `.toolbar`.
  Visually similar modifiers on plain views do not reproduce real toolbar
  button hover states, unified-titlebar blending, or the native
  sidebar-toggle button - those are behaviors the system control implements,
  not styling you can fake. When something "doesn't look native" despite
  correct colors/fonts/materials, suspect the underlying container/control
  choice before reaching for more styling.
- **`Design/MacOSDesignTokens.swift` should contain only what has no system
  equivalent** - `Font.control`, `ControlMetrics`, `Color.progressTrack`,
  `TreemapMetrics`, `TooltipMetrics`, `glassBackground(_:cornerRadius:)`.
  Don't add something here that a real system API already resolves.

Load the `macos-hig-design-system` skill before any UI/design work, even if
the request doesn't say "design system" explicitly - it covers colors,
sizing, typography, materials, and the component inventory this app is
built against.

## Check for dead ends when building any new screen or state

A dead end is any screen, state, alert, or error condition the user can land
on with no way to proceed, retry, or get back to a known-good screen (usually
`DiskHomeView`, reached via `isOnHome = true`). This app has hit this bug
class repeatedly - `ErrorStateView` and `PermissionBannerView` both shipped
with no way back to home, the `.idle` scan state had no cancel button, and
`DiskHomeView`'s "Loading disks..." spinner had no retry or empty-state
fallback - so treat it as a standing checklist, not a one-time cleanup:

- **Every new `ScanState` case, loading/error/empty view, or full-screen
  state needs an explicit exit**: a button back to home, a retry, or a cancel
  - not just "the previous screen's button still technically works." If a
  view can be reached with `isOnHome == false` and has no navigation
  chrome of its own, assume it's a dead end until proven otherwise.
- **Reuse `ContentView.backToHome()`** rather than re-deriving
  `isOnHome = true; selectedPath = nil` at a new call site - it exists
  specifically so every exit point stays in sync as more are added.
- **A loading state needs a way to tell "still loading" apart from "loaded
  and found nothing."** A bare spinner with no timeout and no distinguishing
  state silently becomes a permanent dead end the moment the thing it's
  waiting for returns zero results instead of erroring - see
  `DiskHomeView.hasLoadedOnce`.
- **A destructive or write action's `catch` block needs user-facing
  feedback, not just `print()`.** A silent failure isn't a navigation dead
  end, but it's the same experience for the user: they took an action, got
  no response, and have no way to know whether to retry, and no idea why it
  didn't work.
- When adding a feature, ask "if this fails, or is still loading, or the
  user changes their mind - what do they click?" before considering it done.

## SDK/toolchain gotcha - verify against CI, not just locally

This machine may have a newer Xcode/SDK installed than GitHub's hosted
runners. `swift --version` here currently reports Xcode 26 / Swift 6.3 with
the macOS 26 SDK - new enough for `.glassEffect` and other Liquid Glass
APIs. GitHub's `macos-15` runner (used by `.github/workflows/ci.yml` and
`release.yml`) is on an older Xcode that does **not** declare those symbols
at all.

**`#available(macOS 26, *)` only gates runtime behavior - it does not help
if the symbol doesn't exist in the SDK you're compiling against.** Code
that references a macOS-26-only API needs an *additional* compile-time
guard, e.g.:

```swift
#if compiler(>=6.2)
if #available(macOS 26, *) {
    self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
} else {
    // fallback
}
#else
// fallback
#endif
```

This actually broke CI once (silently, for two pushes, until a release run
surfaced it) - see `glassBackground(_:cornerRadius:)` in
`MacOSDesignTokens.swift` for the real fix. **Before considering any
bleeding-edge API change "done," check that CI actually passes** -
`gh run watch <run-id> --exit-status` after pushing, don't assume a local
build result generalizes.

## Git & commit conventions

- Never commit unless explicitly asked. Never push unless explicitly asked.
- Before starting a multi-stage change, check `git status`. If the tree is
  dirty, stop and ask how to proceed rather than guessing - don't fold
  unrelated pending work into a new change's commits without saying so.
- For staged/multi-part work: one commit per logical stage, not one per
  file, with a descriptive message. If working from a written audit/plan
  with finding IDs, reference them in the commit message.
- Never commit build artifacts or binaries into the tree (see Releases,
  below, for how binaries actually get distributed).
- Don't rewrite history (rebase/amend) on commits already pushed, even to
  fix a mistake - create a new commit, or in the specific case of a tag
  that was pushed moments ago and never produced a real published artifact,
  it's fine to delete and re-push that tag (this happened once, to move
  `v0.1.0` off a commit whose release build had failed before publishing
  anything).

## Releases

Distribution is DMGs attached to GitHub Releases - not committed binaries.

- `Packaging/Info.plist` - template bundle Info.plist, `__VERSION__`
  placeholder substituted by the release workflow. DustEater has no
  Info.plist for local development (`swift run` uses a bare executable);
  this is packaging-only and doesn't affect the dev workflow.
- `.github/workflows/release.yml` - triggered by pushing a tag matching
  `v*.*.*`. Uses a hybrid build strategy:
  - arm64 builds on `xcode-27` runner (macOS 26 SDK) - includes real Liquid
    Glass support (`.glassEffect`).
  - x86_64 builds on `macos-15` runner (older SDK) - uses Material fallback
    for Liquid Glass effects.
  - Both binaries are combined into a universal binary via `lipo`, then
    assembled as `DustEater.app`, ad-hoc codesigned (no Developer ID
    certificate), packaged as a DMG, and published via GitHub Release.
  - Releasing is `git tag vX.Y.Z && git push origin vX.Y.Z` - no manual
    steps otherwise.
- **Limitation for x86_64 (Intel Mac) users**: The x86_64 binary uses the
  Material fallback for Liquid Glass effects since the `macos-15` runner
  doesn't have the macOS 26 SDK. On arm64 Macs (the vast majority of
  modern hardware), the app runs with full Liquid Glass support.
- Builds are unsigned/ad-hoc-signed (no Apple Developer Program membership
  behind this project). Gatekeeper will warn on first launch - the
  workaround (`xattr -cr` or right-click → Open) is documented in the
  release notes and README's Download section. This was a deliberate
  choice, not an oversight - revisit only if the project gets a Developer
  ID certificate.

## Licensing

MIT for DustEater's own code (`LICENSE`). One exception:
`Sources/DustEaterCore/Treemap/YMTreeMap.swift` is Yahoo's squarified-treemap
algorithm (`Copyright 2017 Yahoo Holdings Inc.`), used under its original
Apache License 2.0 terms - its copyright header must stay intact, and
`NOTICE` carries the full attribution and license text per Apache 2.0 §4(a).
Don't relicense or strip that file's header.

## Recording non-obvious decisions

When you make a choice during development that isn't obvious from reading the
code alone - an unusual trade-off, a constraint that forced a particular
approach, a deferred improvement, or a deliberate rejection of a "natural"
solution - add it to the "Deliberately deferred / intentional exceptions"
section below.

Include:
- **The decision** - what choice was made
- **Why** - the reasoning, constraint, or trade-off (not obvious from code alone)
- **Where** - file/function names if specific, or the area of the codebase
- **When to revisit** - if applicable (e.g. "after SDK X is available", "if Y
  becomes a bottleneck", "large enough to be its own task")

This prevents future developers (or the user in future sessions) from
"fixing" deliberate decisions as if they were bugs, and documents the
accumulated architectural reasoning of the project.

## Deliberately deferred / intentional exceptions

Things that look like they might need fixing but are actual decisions, not
oversights - don't "fix" these without the user asking:

- The Pastel color theme's white tile-label text has a real contrast issue
  against light tiles (`TreemapView.swift`'s labels) - explicitly deferred,
  not yet addressed.
- Per-appearance (light/dark) variants of the treemap color themes in
  `ColorTheme.swift`/`TreemapColors.swift` - the 6 fixed palettes are not
  yet appearance-aware. Explicitly deferred; large enough to be its own task.
- `DiskCardView`/`CustomFolderCardView` not using `ControlMetrics.isCapsule`
  - see Design system conventions above, this is correct as-is.
- Sidebar/toolbar icons are plain monochrome SF Symbols (Finder-style), not
  colored rounded-square icon-tile badges (App Store/Settings-style) - an
  explicit choice, since this app is a file/disk browser closer to Finder's
  category than a hub-style app.
- `FileTreeListView.swift` uses a hand-rolled recursive `FileOutlineRow`
  (`DisclosureGroup` + an owned `expandedPaths: Set<String>`, passed in as a
  `@Binding` and actually held by `MainContentView` in `ContentView.swift` -
  see below for why) instead of `OutlineGroup`. This looks like reinventing a
  system control, but `OutlineGroup` owns its disclosure state internally with
  no way to open a branch from code - it can't support "select a node (e.g.
  from a treemap click) and auto-expand/scroll the sidebar to reveal it,"
  which is exactly what `reveal(_:proxy:)` does. The
  `if expandedPaths.contains(node.path)` guard inside `FileOutlineRow`'s
  `DisclosureGroup` content is load-bearing, not redundant - it restores the
  one-level-at-a-time lazy sort that `OutlineGroup` gave for free (see the
  comment on `outlineChildren`); without it the recursion eagerly
  builds/sorts collapsed subtrees.
- The delay before `proxy.scrollTo` in `reveal(_:proxy:)` (a `Task.yield()`
  then a 50ms sleep) is required, not superstition: `scrollTo` is a silent
  no-op for a row inside a branch that was expanded in the same update - the
  `List` hasn't rebuilt to materialize that row yet. Only taken when the
  target branch actually needed expanding; an already-visible row scrolls
  immediately with no delay.
- There is no per-row `Menu`/ellipsis button and no `.contextMenu` in the
  sidebar (`FileRowView` in `FileTreeListView.swift`). A macOS `Menu` always
  renders as a bordered pull-down button with a menu indicator regardless of
  the frame it's given, and at sidebar width that button alone was crushing
  every row's name down to two or three characters. Actions for the selected
  item (Reveal in Finder, Copy Path, Delete) live in `MainContentView`'s
  toolbar instead (`ContentView.swift`), acting on `selectedNode` - a
  genuinely native macOS pattern (Finder, Mail, Photos). They're `.disabled`
  rather than conditionally hidden when nothing is selected, so the toolbar
  doesn't reflow on every selection change. `expandedPaths` and the delete
  alert moved from `FileTreeListView` to `MainContentView` along with this,
  since `deleteItem` needs to prune expansion state and the alert is now
  triggered from the toolbar rather than a row. Note `.contextMenu` costs no
  horizontal width and pairs naturally with a selection toolbar - adding one
  later is a deliberate scope choice being deferred, not a gap to "fix."
- Filesystem changes made while the app is open are **detected but not
  reconciled live** into the scanned tree. `FileSystemWatcher`
  (`Sources/DustEaterCore/Scanner/FileSystemWatcher.swift`) uses FSEvents to
  cheaply notice that something changed under the scanned root - kernel-level
  subtree monitoring, the same mechanism Spotlight/Time Machine use, no
  polling - but it only flips `ScanCoordinator.hasDetectedChanges` to `true`,
  surfaced as an orange "Rescan" toolbar button that reuses the existing full
  `startScan(path:)` path. It deliberately does **not** try to merge the
  change into the live `FileNode` tree: FSEvents reports "this directory
  changed," not a diff, `FileNode` has no insert/replace method (only
  `removingNode(atPath:)`), and correctly propagating a partial re-scan's
  size/itemCount deltas up every ancestor while keeping the treemap cache and
  sidebar expansion state consistent is real, error-prone work - the same
  reason DaisyDisk/GrandPerspective/OmniDiskSweeper don't live-update either,
  they expect a manual re-scan. `FileSystemWatcher` is also the app's first
  continuously-running background component (previously every `Task` in the
  codebase was one-shot); it follows `ScanCoordinator.scanTask`'s existing
  own-and-cancel-on-replace shape. `kFSEventStreamCreateFlagIgnoreSelf` is
  load-bearing, not incidental: without it, an in-app delete (already
  reconciled into the tree via `removingNode(atPath:)`) would immediately
  re-trigger a spurious "files changed, rescan?" prompt about a change the
  app already knows about - verified directly against real FSEvents (not
  just reasoned about) during implementation. No automated test covers
  `FileSystemWatcher` itself - real FSEvents delivery is OS-scheduled and
  asynchronous, on the order of seconds, which isn't practical to assert on
  in `swift test` without adding real wall-clock delay to every run.
- `FileOperations.isSystemProtected` (`Sources/DustEaterCore/FileOperations.swift`)
  protects `/Users`, every account's home directory (`/Users/<name>`), and
  the default folders macOS creates in each one (Desktop, Documents,
  Downloads, Movies, Music, Pictures, Public, Library) - none of these were
  in the protected list before, so the app would let you delete an entire
  home directory or someone's whole Downloads folder. Protection for these
  is deliberately by **exact path**, not prefix like `systemPaths` above:
  the point of the app is cleaning individual clutter out of Downloads, so
  only the folder itself is blocked, not its contents.
  `defaultUserFolderNames`/`isProtectedUserFolder` are path-shape-based
  (component count under `/Users/...`) rather than keyed to
  `NSHomeDirectory()`, so a full-disk scan protects every account it can
  see, not just the one running DustEater.
  **Gotcha found while adding this**: `NSString.standardizingPath` silently
  collapses `/private/tmp` → `/tmp` (and `/private/var` → `/var`,
  `/private/etc` → `/etc`) before `isSystemProtected` ever compares it -
  confirmed directly against the real API, not assumed. The list used to
  contain `/private/tmp` with no corresponding plain `/tmp` entry, so `/tmp`
  was never actually protected despite looking like it was; fixed by
  listing the public form only. Don't re-add a `/private/...` entry here -
  it will silently never match.
- **Vendor-shared data folders (Google/Chrome case).** Apps from companies
  like Google, Microsoft, Adobe, and JetBrains often nest their per-app data
  one level deeper inside a shared company folder - e.g.
  `~/Library/Application Support/Google/Chrome` rather than
  `~/Library/Application Support/com.google.Chrome`. `AppGrouper` and
  `OrphanFinder` both use a vendor-name heuristic derived from the bundle
  identifier's second dot-component (`com.google.Chrome` → `"google"`) to
  detect and recurse into these folders when building related-item lists or
  deciding whether a folder is orphaned. This heuristic is not perfect (a
  third-party app could coincidentally match a vendor name) but is safe -
  recursion only triggers for folders whose name matches a known installed
  app's vendor. See `VendorFolderExpander.swift` and the test fixtures
  `findRelatedStorageInVendorNestedFolders` / `ignoresLiveAppDataInVendorFolderWhileReportingOrphanSiblings`
  for the full logic and examples.
  **Known limitation:** The heuristic assumes the filesystem is case-insensitive
  (the macOS default APFS/HFS+, not an opt-in case-sensitive APFS volume).
  On a case-sensitive volume, a folder named `"Google"` would not match the
  lowercased guess `"google"`. This is an accepted gap, not a bug - revisit
  only if case-sensitive APFS volumes become common enough to matter.
- **Disk Health & System Telemetry module (`Sources/DustEaterCore/DiskTelemetry/`):**
  - **Raw IOKit/DiskArbitration/SMC calls are not unit tested.** These APIs touch
    hardware, depend on real device presence and OS state, and are synchronous
    blocking calls from an `@MainActor` service. The pattern matches the
    existing `FileSystemWatcher` precedent (documented above): integration
    testing at `swift run` time is practical and done manually; automated
    unit tests don't mock these APIs. Pure logic around them - purgeable-space
    arithmetic, health-status rollup evaluator - *is* unit-tested via
    dependency injection (see `APFSVolumeMetricsTests.swift`,
    `PhysicalDiskHealthTests.swift`).
  - **Wear-level % and total bytes written show "Not Available on This Mac"**
    rather than blank/nil/guessed numbers on virtually all Apple Silicon Macs
    and most external/USB drives. This is not a bug or a missing feature - it
    reflects Apple's platform restriction: no public non-entitled API exposes
    these metrics. The few tools that claim to read them (like smartctl) are
    also blocked on Apple Silicon. DustEater is ad-hoc signed with no path to
    the private entitlements that would be required. When revisit: only if
    Apple opens up a public API, or if the app ships with a Developer ID
    certificate and the accompanying privileged helper infrastructure.
  - **Purgeable-space reclaim uses an AppleScript admin-password prompt,** not
    a privileged-helper daemon (SMJobBless/SMAppService). DustEater has no
    Developer ID cert (CLAUDE.md:213-218), so a persistent daemon isn't
    shippable. The shipped mechanism shells out to `tmutil
    thinlocalsnapshots` wrapped in `do shell script ... with administrator
    privileges` - standard macOS password dialog UX, same as Disk Utility's
    "Repair Disk". Real forced reclaim happens on each action. When revisit:
    if the app ever gets a Developer ID cert, consider a proper privileged
    helper for smoother UX (no password prompt per action).
  - **SMC temperature sensor key probing is best-effort.** The open-source
    technique used here (iStat Menus/TG Pro pattern, IOKit calls + struct
    definitions from community documentation) works on most Macs but has no
    official Apple blessing. It may fail silently on models where Apple chose
    a different sensor key name or sensor hierarchy. All failures fall through
    to "Unavailable" gracefully. When revisit: only if/when Apple publishes
    an official temperature API.
