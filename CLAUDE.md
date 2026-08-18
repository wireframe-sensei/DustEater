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

## AI Assistant Coding Guidelines

### Core Philosophy: Simplicity over Cleverness
You are an expert software engineer who prioritizes simple, readable, and easily maintainable code. Your primary goal is to write code that is understandable at a glance. Do not act like a highly theoretical architect; act like a pragmatic builder. 

### 1. AHA over strict DRY (Avoid Hasty Abstractions)
- **Do not prematurely abstract.** It is strictly better to duplicate code than to create a complex, rigid abstraction that obscures the underlying logic.
- **Rule of Three:** Never extract logic into a shared helper function, generic class, or utility file until you have written the exact same logic at least three times. 

### 2. DAMP over DRY (Descriptive and Meaningful Phrases)
- Do not optimize for fewer lines of code. Optimize for readability.
- Keep the context inline. Do not hide simple operations behind layers of generalized functions. 
- Variable and function names must be explicit, even if they are slightly longer.

### 3. Flat and Direct (YAGNI)
- **You Aren't Gonna Need It:** Solve the immediate problem directly. Do not build generic, future-proof interfaces, factories, or deep inheritance trees unless explicitly instructed.
- Keep the logic flat. Write top-to-bottom, procedural code where possible. Avoid splitting a simple sequence of events into five different tiny helper functions.
- Prefer simple, standard APIs over obscure, low-level technical implementations or complex system calls unless performance absolutely dictates it.

### 4. When in Doubt, Inline
- If you are debating whether to separate logic into a new function/file or keep it inline, **keep it inline**.
- I want to be able to read a function from top to bottom without jumping around the file or opening other files.

### 5. Correction Directives
- If I tell you "this is too complex" or "de-abstract this," immediately flatten the logic, remove generics, and inline the helper functions.

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
  - **Wear-level % and total bytes written show "Not Exposed on Apple Silicon"**
    rather than blank/nil/guessed numbers on virtually all Apple Silicon Macs
    and most external/USB drives. This is not a bug or a missing feature - it
    reflects Apple's platform restriction: no public non-entitled API exposes
    these metrics. The few tools that claim to read them (like smartctl) are
    also blocked on Apple Silicon. This restriction is permanent and not
    addressable by code changes, signing, or Developer ID membership - Apple's
    entitlements check the Team ID against an internal allowlist and restrict
    them to Apple's own system binaries regardless of who signs the requesting
    process. When revisit: only if Apple opens up a public API for these
    metrics.
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
- **Duplicate & Large File Hunter, and Developer & Creative Power-User Clean
  Up Kit - both retired as standalone screens by the Cleanup restructure
  (see the section below).** `Sources/DustEaterApp/Inspector/` and most of
  `Sources/DustEaterApp/DeveloperKit/` are deleted - `DuplicatesView`,
  `DuplicateSetOverview`, `DuplicateSelectionState`, `SmartSelectMenu`,
  `ThumbnailImageView`, `DeveloperKitView`, `TargetCardView`,
  `PurgeConfirmationSheet`, `PurgeSelection`, and the `SmartSelector`/
  `ImageFileDetector` Core types that only they used, are gone. Do not go
  looking for them; do not "restore" them as a fix for a regression -
  Smart Select and the per-set duplicate image grid are real, disclosed
  capability removals (see `CHANGELOG.md`'s Unreleased section), not an
  oversight.

  The **Core** logic both screens were built on is still here, unchanged,
  and now feeds `Sources/DustEaterCore/Cleanup/` instead:
  `DuplicateDetector`, `LargeFileFinder`, `PurgeCatalog`, `PurgeCategory`,
  `BundleProtection`, `DeveloperArtifactFolders`, `XcodeArchiveLister` (and
  its one surviving app-layer view, `XcodeArchivesListView`, now opened
  from the Xcode build artifacts finding's footer action instead of a
  Developer Kit card). Everything below that's still true about *that*
  code is kept; everything that was only true about the deleted screens
  is not.

  - **`FileNode.size` is on-disk *allocated* size, the wrong key for
    byte-accurate dedup or a `>1 GB` threshold**, which need logical
    `st_size`. `DuplicateDetector`/`LargeFileFinder` gather that via
    on-demand `lstat` (`FileStatReader`) instead of adding fields to
    `FileNode` itself, which is instantiated millions of times per scan.
    Candidates are pre-filtered by `FileNode.size` first (thousands of
    files after the default floor, not millions), and only those get an
    individual `lstat`. Don't "optimize" this by extending
    `AttrListBulkReader` - that parser reads packed attributes in strict
    ascending bit order, and inserting fields there is high-risk for a
    benefit this doesn't need.
  - **Candidate prefiltering uses a quarter of the real size floor against
    `FileNode`'s allocated size, then the real floor against logical size
    after `lstat`.** A heavily APFS-compressed file can have an allocated
    size well under its logical size; filtering candidates at the full
    floor against allocated size would silently miss compressed
    duplicates and compressed large files. Both `DuplicateDetector` and
    `LargeFileFinder` apply this same `max(1, floor / 4)` prefilter,
    then re-check the real floor against `InspectedFile.logicalSize`
    after `lstat` - so the loosened prefilter only ever widens the
    candidate set, never the final result.
  - **App bundle interiors (`.app`, `.framework`, `.bundle`, `.xpc`,
    `.plugin`, `.appex`, `.photoslibrary`, `.sparsebundle`) are excluded
    from both duplicate and large-file candidates** (`BundleProtection.swift`).
    This can't be left to `FileOperations.isSystemProtected`: that only
    blocks fixed system paths like `/Applications`, not a user-writable
    bundle sitting in `~/Downloads` or `~/Desktop` - exactly where users
    keep the apps they might scan. Deleting one file out of a signed bundle
    invalidates its code signature and can silently break the app. Both
    `DuplicateDetector.collectCandidatePaths` and
    `LargeFileFinder.collectCandidatePaths` carry "am I inside a bundle"
    down their tree walk rather than checking each file's full ancestor
    chain, so the check costs one suffix comparison per directory, right
    where a bundle boundary is actually crossed.
  - **"Not opened" uses `LargeFileEntry.lastUsedDate`
    (`AppLastUsedDateProvider`'s Spotlight `kMDItemLastUsedDate`, falling
    back to filesystem mtime), not raw `st_atime`.** macOS access time is
    routinely bumped by Spotlight indexing, Time Machine, and antivirus
    scanners, and some volumes defer atime updates entirely - it reads as
    "recently used" for files nobody has actually opened.
    `AppLastUsedDateProvider` already implements exactly this signal and is
    path-generic despite the "App" in its name, so `LargeFileFinder` reuses
    it directly (via a small public wrapper,
    `LargeFileFinder.defaultLastUsedDateProvider`, needed only because
    Swift requires a public API's default parameter value to be at least
    as visible as the API itself). An unknown last-used date is always kept
    in results, never treated as evidence of staleness - see
    `LargeFileFinder.matches`.
  - **The hard-link collapse in `DuplicatePartitioner.collapsingHardLinks`
    keeps whichever alias `Dictionary(grouping:)` iterates first among
    files sharing a `(deviceID, inode)` pair - which one survives is
    unspecified, not a bug.** Both aliases point at the same on-disk bytes,
    so it doesn't matter which path is kept; `DuplicateDetectorTests`
    asserts the invariant (exactly one alias survives) rather than pinning
    down which.
  - **Full-file SHA-256 hashing (`FileHasher.fullDigest`) issues one
    `BlockingIO.run` call per 1 MB chunk, not one call for the whole file.**
    `BlockingIO.run` dispatches its closure onto a plain `DispatchQueue`,
    which does not carry Swift Concurrency's task-local cancellation state -
    a `Task.isCancelled` check placed *inside* one giant blocking closure
    would never actually fire, no matter how long the file. Checking
    between chunks, from the genuinely async calling context, is what makes
    hashing a multi-gigabyte file actually abort within about one chunk's
    read time when the user cancels.
  - **`DuplicateDetector`'s hashing concurrency is a bounded sliding window
    (`withConcurrentTasks`, capped at `activeProcessorCount * 4`), not the
    unbounded `TaskGroup` fan-out `DiskScanner` deliberately uses for
    directory recursion.** This is not a contradiction of that file's
    documented reasoning (`DiskScanner.swift`): hashing tasks are leaves
    that read one file and return, never needing to acquire a further
    permit from this same window to make progress, so there's no circular
    wait the way an unbounded *recursive* fan-out could create.
  - **Developer-tool directories (`node_modules`, `.git`, package-manager
    caches, build output) are excluded from duplicate/large-file candidates
    by default** (`DeveloperArtifactFolders.swift`,
    `DuplicateScanOptions.includeDeveloperArtifacts` /
    `LargeFileFilter.includeDeveloperArtifacts`, both still default
    `false`). Different risk category from `BundleProtection`: deleting a
    file out of a signed `.app` breaks a code signature, but deleting a
    duplicate out of a project-local `node_modules` breaks that project's
    build until it's reinstalled - and neither `DuplicateDetector` nor
    `LargeFileFinder` has any way to tell an active `node_modules` from an
    abandoned one. The same package is also routinely installed
    byte-identically across a dozen unrelated projects, making this the
    single biggest source of noisy, low-value duplicate reports on a
    developer's Mac. `CleanupFindingsBuilder` relies on this default
    staying `false` - it never overrides it.
- **Developer & Creative Power-User Clean Up Kit
  (`Sources/DustEaterCore/DeveloperKit/`, now Core-only - the App-layer
  purge UI it fed is gone, see above):**
  - **`PurgeSafetyLevel` has four cases, not the three originally briefed** -
    `.safe`, `.rebuildable`, `.caution`, and `.reportOnly`. The fourth exists
    so "a Docker card with a delete button" is unrepresentable in the type,
    not merely discouraged in the view: Docker's `Docker.raw`, mounted
    Simulator runtime volumes, and Final Cut Pro/Logic Pro library contents
    genuinely have no safe deletion path from outside their owning app, so
    they're sized and explained but never offered a delete action at all -
    `CleanupItem.isReportOnly`/`hint` (Cleanup's own type, not
    `PurgeTargetDefinition` directly) carries this forward, and
    `SelectionStore.toggle` refuses a `.reportOnly` item a second time at
    the data layer as a hard backstop independent of what the view renders.
  - **iOS Simulator runtimes are report-only, and this isn't a conservative
    default - they're not deletable at all through this app.** Verified
    directly (not assumed): downloaded runtimes are a single root-owned DMG
    under `/Library/Developer/CoreSimulator/Images`, currently mounted
    read-only as an APFS cryptex volume. That's triply blocked - prefix-
    blocked by `FileOperations.isSystemProtected` (`/Library`), root-owned,
    and an active mount `rm` can't touch even with permission. `simctl
    runtime delete` is the only real path, surfaced as the hint text.
  - **Adobe scratch-disk locations are not auto-located, and this was a
    deliberate stop, not a gap to fill in later.** Photoshop's scratch
    config lives in a binary `.psp` inside `Adobe Photoshop <version>
    Settings/`, an undocumented format not worth reverse-engineering.
    Premiere's prefs are readable XML but every verified value was the
    sentinel `SameAsProject` - meaning render files sit next to whatever
    project created them, at a path this app has no way to know. Fixed
    Adobe cache paths (Media Cache Files, Peak Files, etc.) are in
    `PurgeCatalog.definitions` as normal; project-local Premiere preview
    folders are instead *discovered* from the scanned tree by name
    (`PurgeCatalog.discoveredDefinition`), the same mechanism used for
    `node_modules`/Cargo `target`. A Photoshop `Photoshop Temp*` scratch-file
    sweep was scoped and then deliberately cut before implementation: those
    files sit at the root of whatever volume Photoshop was scratching to,
    not under one project folder, and representing "a set of loose sibling
    files matched by name prefix" doesn't fit `PurgeTargetDefinition`'s
    one-path-per-target shape without real complexity for a feature that,
    per the brief, only ever matters after a crash. Revisit as its own
    scoped feature if it turns out to matter in practice, not by bending
    `PurgeTargetDefinition` to fit it.
  - **Final Cut Pro and Logic Pro are report-only, and their exact internal
    folder names (`Render Files`, `Transcoded Media`, `Freeze Files`, `Undo
    Data`) are unverified** - neither app is installed on the machine this
    was built on. `PurgeCatalog.fcpBundleTarget`/`.logicxBundleTarget` sum
    those specific subfolder names if present and report zero if the
    guessed names don't match a real installation - a wrong guess costs a missing
    number, never an attempted deletion, since these are report-only
    regardless. Deleting Final Cut render files from outside the app is
    *roughly* what its own "Delete Generated Library Files" does, but
    `Transcoded Media` can be the only viewable copy once original camera
    media goes offline, and this app has no way to tell which case it is -
    Final Cut does. When to revisit: only after verifying folder names
    against a real Final Cut/Logic install, and even then, Final Cut's own
    render-cleanup command stays the recommended hint text over this app
    attempting the delete itself.
  - **`BundleProtection`'s suffix list gained `.fcpbundle`, `.imovielibrary`,
    `.theater`, `.tvlibrary`, `.logicx`, `.band`** as part of this module,
    not incidentally - `"Wedding.fcpbundle".hasSuffix(".bundle")` is `false`,
    so before this fix the duplicate and large-file inspectors could offer
    individual files inside a Final Cut/iMovie/TV/Logic/GarageBand library
    for deletion, the same class of risk `.app`/`.framework` protection
    already covered. This was shipped as its own standalone commit ahead of
    the rest of the module, since it's a real fix independent of everything
    else here.
  - **`SafetyBadge` draws a literal `Capsule()`, not
    `metrics.buttonShape`.** `ControlMetrics.isCapsule` (`MacOSDesignTokens.swift`)
    governs controls that draw themselves as compact buttons - at
    Large/ExtraLarge control size it becomes `true`, which would turn a
    small static badge into an oversized pill. A badge isn't a button, so it
    intentionally sits outside that system, the same way `DiskCardView`
    deliberately reads only `metrics.cornerRadius` and ignores `isCapsule`
    for its own, different reason (see the Design system conventions
    section above). Don't "fix" this to route through `ControlMetrics`.
  - **`DuplicateDetector.withConcurrentTasks` was not promoted to shared
    infrastructure for `PurgeScanner`'s fallback measuring, even though both
    need bounded concurrency.** `PurgeScanner.measure(_:addingTo:totalTargets:)`
    instead has its own ~15-line inline sliding window capped at 4. Two
    reasons, not one: promoting a `private`, carefully doc-commented method
    to `public` on its *second* use is exactly what CLAUDE.md's Rule of
    Three (see the AI Assistant Coding Guidelines section above) exists to
    prevent, and the actual shapes differ - `withConcurrentTasks` slides
    across tens of thousands of leaf file reads inside an actor, while
    `PurgeScanner`'s version bounds at most a couple dozen `DiskScanner.scan`
    calls, each of which is *itself* an unbounded recursive fan-out
    (`DiskScanner.swift`'s own documented reasoning) - ten of those running
    concurrently would be ten unbounded fan-outs at once, which is why the
    cap is a real 4, not a cosmetic one.
  - **`PurgeCategory.grouped(_:)` lives in Core and is `public`, used by both
    `PurgeScanner.measure` (progressive `@Observable` state) and
    `PurgeScanner.categories` (the headless variant `CleanupFindingsBuilder`
    reads from) - this is the one grouping helper in the module that *was*
    promoted, deliberately, unlike `withConcurrentTasks` above.** The
    difference: this one has two real call sites that need the *exact* same
    grouping, not a hypothetical third, and duplicating six lines of
    `filter`/`sort` is the kind of drift Rule of Three is meant to prevent
    once there's already a second real caller, not just a first.
  - **Xcode Archives never becomes a bulk-selectable `PurgeTarget`, on
    purpose - it's the one category with its own dedicated drill-in list**
    (`XcodeArchiveLister`, `XcodeArchivesListView`). An `.xcarchive` holds
    the dSYM needed to symbolicate a crash report from a build that may have
    shipped; once deleted there's no way back, since rebuilding produces a
    different UUID, not a replacement for the one that's gone. A `.caution`
    badge on a single bulk toggle was judged insufficient friction for a
    one-click, irreversible action with zero regeneration path - so instead
    the Xcode build artifacts finding's footer opens `XcodeArchivesListView`
    directly (see the Cleanup restructure section below), and deletion
    happens one archive at a time through the same Trash/Permanent alert
    pattern every other single-item delete in the app uses.
    `XcodeArchiveLister.listArchives` reads structure and size entirely from
    the already-scanned tree (`root.node(atPath:)` on the Archives folder,
    two levels of children) and returns empty rather than falling back to a
    fresh directory walk if Archives wasn't part of the scan - reusing
    `root` everywhere in this module exists specifically to avoid a second
    Full Disk Access prompt, and a silent fallback walk here would quietly
    defeat that. Each archive's `Info.plist` (a few hundred bytes) is still
    read from disk for its app name and creation date, since that's real
    file content `FileNode` never carries - falls back to the folder name
    if the plist is missing or unreadable, rather than dropping the archive
    from the list entirely.
  - **`PurgeCatalog.isDenied` is a hard refusal layered on top of
    `FileOperations.canDelete`, not a replacement for it** - three paths
    unprotected by anything else in the app: `~/Music/Audio Music Apps`
    (user sampler instruments, patches, and **recorded audio** - nothing in
    `FileOperations.isSystemProtected` covers this today),
    `~/Library/Developer/Xcode/UserData` (code snippets, key bindings,
    breakpoints, themes - personal configuration, not a cache), and any path
    containing an `Adobe Premiere Pro Auto-Save` component (project recovery
    data that sits one directory away from the Premiere preview caches this
    module *does* discover and delete, and was judged the single likeliest
    way this module could destroy real work if left unguarded). Checked
    independently in both `CleanupCommitter.commit` and
    `XcodeArchivesListView.delete` - defense in depth, not trusted to a
    single call site.
  - **`FileOperations.clearSystemCaches()` was removed, not fixed in
    place.** It deleted every direct child of *both* `~/Library/Caches`
    *and* `~/Library/Application Support` - the latter is real application
    data (login state, licenses, local databases), not a cache - bypassed
    `canDelete`, deleted permanently with zero confirmation, and swallowed
    every per-item failure with a bare `continue`. Its only caller was a
    Tools-menu toolbar item, removed along with the menu itself in the same
    change that introduced this module. See `CHANGELOG.md`'s Unreleased
    section for the user-facing note - this is a real behavior removal, not
    an invisible refactor.
- **Cleanup restructure (`Sources/DustEaterCore/Cleanup/`,
  `Sources/DustEaterApp/Cleanup/`, `CleanupShellView.swift`)** - implements
  items 1-4 of `docs/design_handoff_cleanup_restructure/README.md`: a
  ranked Cleanup screen as the post-scan default, app-wide selection with a
  Review screen, Trash-by-default with a real undo, and a Receipt with
  before/after free space. Items 5-8 (streaming partials, browse-by-type in
  Explore, permission onboarding, menu bar monitoring) are not built.
  - **Exactly six findings ship - package manager caches, applications
    unopened over a year, downloads older than 12 months, Xcode build
    artifacts, duplicate files, iOS Simulator runtimes - not every
    `PurgeCatalog` category.** Docker, Adobe, project-local artifacts
    (`node_modules`/Cargo/SPM/CocoaPods), and Final Cut/Logic stay in
    `PurgeCatalog` as Core data (still measured by `PurgeScanner`, still
    tested) but are never turned into a `CleanupFinding` - there is no UI
    path to them at all right now. This was an explicit scope call, not an
    oversight: revisit by adding more `CleanupFindingsBuilder` functions
    and `CleanupFindingID` cases, not by resurrecting Developer Kit.
  - **`CleanupItem.isUserContent` is always `false` for all six findings,
    on purpose.** The design's safety rule 3 ("permanent deletion withheld
    for the user's own files") reads literally in the handoff as applying
    only to Explore's browse-by-type content (item 6, not built), not to
    Downloads or duplicate files - so Review offers both Trash and
    Permanent for everything today, exactly like the old
    `DuplicatesView`/`DeveloperKitView` did. The flag and Review's
    branch on it are real and wired, just dormant until Explore sets it.
  - **`CleanupFindingsBuilder.unusedApplications` treats an unknown
    `lastOpenedDate` as stale (included), the opposite convention from
    `LargeFileFinder.matches`'s "unknown is never evidence of staleness."**
    Deliberate, not a copy-paste mismatch - the two are answering different
    questions. `LargeFileFinder` decides whether a *file's size* is worth
    surfacing at all, where wrongly hiding a huge file because Spotlight
    has no metadata for it is the worse failure. This finding decides
    whether *removing an entire app* looks abandoned, where "no signal
    macOS has ever seen this app opened" is itself the stronger evidence.
  - **The duplicate-files finding exposes only the non-newest copies as
    deletable, permanently - there is no "Include Original" override the
    way `DuplicateSetOverview` used to have.** `CleanupItem.deletablePaths`
    for a duplicate item is fixed at construction (`DuplicateSet.files`
    minus its newest member) and nothing in `SelectionStore`/`ReviewView`
    can select the survivor. A real, disclosed capability reduction (see
    `CHANGELOG.md`), traded for a much simpler item shape - no per-set
    "which copy is locked" state to track outside the `DuplicateSet` itself.
  - **Review's Trash/Permanent choice has no safety-aware prominence flip -
    Trash is always the recommended, `.borderedProminent` option**, unlike
    the old `PurgeConfirmationSheet`, which promoted Permanent by default
    and only favored Trash once a `.caution` target was selected. This
    follows the design handoff's safety rules directly ("Trash is the
    default destination... always") rather than the old screen's
    reclaim-now-over-safety-net reasoning, which was specific to a
    dev-cache-only selection Cleanup no longer guarantees.
  - **Undo (`CleanupShellView.performUndo`) puts the files back and
    triggers a full rescan; it does not restore the previous selection**,
    despite the design handoff saying Undo restores both. Carrying
    `CleanupItem` references across a rescan (whose ids may not even still
    match, if content changed) isn't worth the complexity for an undo path.
  - **`FileOperations.delete`/`deleteAppBundle` now return
    `@discardableResult ... URL?`** (previously `Void`) - the trashed
    item's real location, captured from `FileManager.trashItem`'s
    `resultingItemURL` rather than discarded. This is what makes
    `FileOperations.putBack(from:to:)` / Receipt's "Undo - Put Back"
    possible at all; every existing call site kept compiling unchanged
    because of `@discardableResult`.
  - **`CleanupCommitter.commit` is one shared batch-delete function**,
    replacing the three near-identical per-path delete loops that used to
    live in `DeveloperKitView.performPurge`, `DuplicatesView.performDelete`,
    and `AppDetailInspector.proceedWithUninstall`. The first two callers no
    longer exist; `AppDetailInspector` still has its own inline loop
    (unchanged - App Manager wasn't touched by this restructure) and was
    deliberately *not* migrated onto `CleanupCommitter`, since doing so
    wasn't asked for and App Manager's uninstall has its own
    running-app-termination flow this function doesn't replicate.
  - **The Apps destination inside `CleanupShellView` embeds `AppManagerView`
    unmodified, nesting its own `NavigationSplitView` inside the outer
    shell's detail pane** rather than flattening App Manager's
    mode-picker-plus-list sidebar into the shell's own sidebar. This reads
    roughly like Mail.app's three-pane layout in practice. `AppManagerView`
    was intentionally left untouched (row checkboxes and an uninstall
    breakdown panel are the design's item 5, not built), so its "Home"
    toolbar button still means exactly what its label says - back to
    `DiskHomeView` - not back to Cleanup. Repurposing that button to mean
    "back to Cleanup" without changing its label/icon would have been a
    real, if small, honesty bug.
  - **The persistent three-item sidebar (disk context block, Cleanup/
    Explore/Apps nav, contextual section, footer) is built from ordinary
    `NavigationSplitView` + native controls, not the design handoff's exact
    custom window chrome** (rounded window corners/shadows, the literal
    246pt/28pt/etc pixel grid, a custom stoplight-adjacent sidebar). That
    level of chrome fidelity belongs to the window-shell work implied by
    items 5-8, which are out of scope here; this restructure applies the
    handoff's colors/type/spacing to the screens actually in scope
    (Cleanup, Review, Receipt) while keeping the app's existing, working
    native-chrome pattern for navigation itself.
  - **The disk-picker auto-skip (`ContentView.onlyEligibleVolumePath`) was
    verified to correctly trigger a scan of the sole eligible volume.** A
    first attempt at verifying the resulting full-disk scan appeared to
    stall (0% CPU, no progress) inside `/System/Volumes/...` (firmlink
    territory `DiskScanner.swift` predates and wasn't touched here); a
    later session's live test of the same `/` scan (see the Cleanup
    streaming section below) showed real, if slow, progress instead - 10M+
    items scanned, non-zero CPU throughout - so the first result likely
    reflected transient conditions on that run rather than a genuine
    `DiskScanner` deadlock. Not conclusively resolved either way; if
    full-disk scans hang in practice, revisit whether auto-skip should
    apply to `/` specifically, not just whether exactly one volume exists.
- **Streaming Cleanup scan (item 5 of the design handoff) -
  `Sources/DustEaterCore/ScanState.swift`, `ScanCoordinator.swift`,
  `Sources/DustEaterApp/Cleanup/ScanningCardView.swift`:** findings now
  stream in during the scan itself, not just after it finishes. Items 6-8
  (browse-by-type, permission onboarding, menu bar monitoring) are not
  built.
  - **`CleanupScanner.swift` (the separate `@Observable` class that used to
    drive the post-scan findings pass) is deleted - `ScanCoordinator` now
    owns that work directly.** Findings need to be visible in two places at
    once (the Scanning stage and the Cleanup screen) on two different,
    overlapping timelines (during the tree scan and after it), which a
    second, separate `@Observable` object gated behind `.finished` couldn't
    represent without the shell reconciling two feeds. `ScanCoordinator.
    findings`/`.inFlightFindingIDs` are the one live source both screens
    read from.
  - **Most findings don't need the assembled tree at all, and now run as
    independent scans concurrent with the main tree walk, not gated behind
    it.** Package manager caches / Xcode's fixed cache paths / simulator
    runtimes (`PurgeScanner.fixedPathCategories`, a new headless variant
    that skips `measure(in:)`'s "is this path already in the tree" check
    entirely, since there is no tree yet), unused applications
    (`AppManagerScanner.scanInstalledApps`), and old downloads (a direct
    `DiskScanner` scan of `~/Downloads`, not `root.node(atPath:)`) each
    start the moment `startScan` is called, as genuinely independent
    top-level `Task`s - not children of the main scan's `Task`, so
    `scanTask?.cancel()` alone doesn't stop them; `ScanCoordinator` tracks
    them separately (`fastPathTasks`) and cancels both. Only project-local
    purge targets (`PurgeCatalog.discover`, walking the tree for
    `node_modules` etc.) and duplicate files (`DuplicateDetector`) actually
    need the finished tree, and run after `.finished` fires - never
    blocking Explore on duplicate hashing, which is by far the slowest
    piece.
  - **Package manager caches and Xcode build artifacts are measured twice,
    on purpose - once fast-path (fixed catalog paths only), once more
    after the tree finishes (project-local discovery only) - and
    `inFlightFindingIDs` stays inclusive of both until the second pass
    completes.** `ScanCoordinator.mergeFinding` unions items by id rather
    than replacing, so the second pass only ever adds to what the first
    already published - the sidebar total and the Scanning card's "Found
    so far" figure are structurally monotonic (never decrease) as a
    consequence of this, not because of a separate guard checking for it.
  - **`ScanState` gained a `.cancelled` case, distinct from both `.idle`
    and `.finished`.** Cancelling before the tree finishes can't produce
    `.finished` (there's no complete, trustworthy `FileNode` to hand over -
    `DiskScanner`'s own cancellation path returns real data for
    already-completed subtrees but empty stubs for interrupted ones, which
    would misrepresent an untrustworthy partial tree as a real one), and
    can't fall back to `.idle` either, since `.idle` means "nothing has
    happened yet" and would imply findings should reset - they must not
    (see the design handoff's "cancelling keeps whatever was already
    found"). Cancelling *after* `.finished` (cutting short only the
    tree-dependent finding work) deliberately does **not** produce
    `.cancelled` - the tree itself is legitimately complete by then, so
    `cancelScan()` leaves `state` as `.finished` and only clears
    `inFlightFindingIDs`.
  - **`CleanupShellView` is mounted the moment a scan starts, not once it
    finishes** - `ContentView`'s top-level switch now routes `.scanning`,
    `.finished`, and `.cancelled` to the same `CleanupShellView` branch, so
    its `@State` (selection, expanded findings, `cleanupStage`) persists
    naturally across the whole lifecycle instead of being torn down and
    rebuilt at `.finished`. `CleanupShellView.root: FileNode` (a required
    `let`) is gone; `finishedRoot: FileNode?` is computed from
    `coordinator.state` instead, `nil` throughout `.scanning` and after a
    pre-finish cancel. Explore's nav row is disabled while
    `finishedRoot == nil` (grayed out, not hidden) since it's the one
    destination that genuinely needs the tree; Apps runs its own
    independent scan and stays available throughout, matching how it
    already worked in the Cleanup restructure above.
  - **`CleanupStage` gained a `.scanning` case** (alongside `.findings`/
    `.review`/`.receipt`), shown while `coordinator.state == .scanning` and
    the user hasn't tapped Review Findings yet. `advanceStageIfNeeded`
    (an `.onChange(of: coordinator.state)` handler) leaves it automatically
    the moment the scan itself leaves `.scanning` for any reason - finished
    or cancelled - so a scan that completes while the user is still looking
    at the Scanning card doesn't strand them there.
  - **`ScanningCardView`'s big ring is a hand-drawn rotating arc, not a
    system `ProgressView`** - macOS's own indeterminate `ProgressView`
    renders as the small multi-dot activity spinner regardless of the
    frame it's given, not a rotating ring with a visible gap, so there's no
    system control to defer to for this specific look. The small in-flight
    row's spinner *is* a real `ProgressView`, where the system spinner is
    exactly what's wanted - the choice is per-element, not a blanket
    "custom-draw everything here."
  - **Real-machine testing surfaced a genuine, unresolved tension: fast-path
    finding scans and the main tree scan share `BlockingIO`'s single global
    dispatch queue and semaphore, so on the heaviest scans (a full `/`
    scan with 10M+ items) the fast-path scans can take 30-50+ seconds to
    complete even though they touch orders of magnitude fewer paths.**
    Confirmed live: on one whole-disk test scan, no findings appeared for
    roughly the first 30-40 seconds despite `AppManagerScanner`/
    `PurgeScanner.fixedPathCategories` only needing to read `/Applications`
    and ~30 fixed paths, then all four then-available findings (package
    manager caches, unused applications, Xcode build artifacts, simulator
    runtimes) appeared together shortly after, with the sidebar total and
    sidebar findings list updating live and correctly. Findings did stream
    in before the scan finished, and never appeared to shrink, matching
    the design handoff's requirements - but the *first* finding landed
    later than the handoff's "thirty seconds" framing implies for a scan
    this large, because `BlockingIO`'s queue doesn't distinguish which
    caller submitted a given blocking syscall, so a fast-path scan's ~30
    requests queue behind however many the unbounded main-scan fan-out has
    already submitted. Not fixed here - `BlockingIO` is a shared,
    process-wide primitive every scan in the app depends on, and tuning its
    fairness (e.g. task-priority-aware scheduling, or a separate small
    high-priority lane for fast-path work) is real, independently-riskable
    surgery on a hot path outside this task's scope. Revisit if this
    proves to matter in practice on real (not just pathologically large)
    disks - typical scans of a home directory or a single volume without
    `/System/Volumes` firmlink traversal are far smaller and shouldn't hit
    this contention nearly as hard.
- **Browse by type in Explore (item 6 of the design handoff) -
  `Sources/DustEaterCore/Explore/`, `Sources/DustEaterApp/Explore/`,
  `DiskScanner.scanWithTypeIndex`:** Explore gains a `Treemap · By Type`
  segmented control, By Type default. Items 7-8 (permission onboarding,
  menu bar monitoring) are not built.
  - **The type index is built inside `DiskScanner`'s existing walk, not as
    a seventh independent scan.** `scanDirectory` now returns
    `(FileNode, FileTypeIndexPartial)` and folds the index bottom-up
    exactly the way it already folds `size`/`itemCount` - a plain value
    type combined via `merge`, not a shared lock-protected object touched
    from every concurrent directory task (that would have added a second,
    different concurrency pattern to a hot path with famously delicate
    documented reasoning already, right above this note). Benchmarked
    live with `dustbench`, alternating run order across several rounds to
    cancel out disk-cache warming: against a real 107,000-file/22 GB
    directory the delta between `scan(rootPath:)` and
    `scanWithTypeIndex(rootPath:)` was -3.2% (i.e. within noise, not
    slower); against an 8,500-file `node_modules` tree (many small files,
    the classifier's worst case) it was +0.1%. Both benchmark runs were
    manual and are not preserved as an automated test - see
    `Sources/dustbench/main.swift`'s git history if this needs re-checking.
  - **`.app` bundles are classified structurally, not by extension.** Each
    subdirectory task threads an `insideAppBundle` flag through recursion
    (set the moment a `.app`-suffixed directory is entered); files inside
    are never individually classified, and the whole bundle becomes one
    `.applications` `FileTypeIndexEntry` recorded by the *parent* directory
    task once the bundle's subtree returns with its complete recursive
    size known. A nested bundle (a helper `.app` inside another) is never
    separately recorded, since its own recursion already sees
    `insideAppBundle == true` inherited from the outer one.
  - **Each category's entry list is capped at `FileTypeIndex.
    maxEntriesPerCategory` (2000) during the scan itself, not truncated
    afterward - totals are always exact regardless.** A category like
    "Code & Projects" can have well over 100,000 files on a real disk;
    holding all of them in memory for the lifetime of a scan would be a
    real regression, and the Type detail list only ever needs the largest
    ones anyway (default sort is size-descending - "the real user query is
    videos over 500 MB"). `FileTypeIndexPartial.record` only sorts/trims
    once a category's bucket grows to double the eventual cap, not on
    every insert, so most directories (which never come close) pay nothing
    for this.
  - **`FileTypeClassifier` is a hybrid, not pure `UTType` conformance.**
    Source/script/project-config extensions (`.swift`, `.json`, `.yml`,
    `.xcodeproj`, ...) are a hand-maintained list checked first, since
    precision matters most for "is this actually part of a project" and
    many everyday project files don't reliably conform to
    `UTType.sourceCode` in the system's own hierarchy. Physical-media
    buckets (video/image/audio/pdf/archive) fall back to real `UTType`
    conformance, whose system-declared hierarchies are reliable and don't
    need a maintained list. Results are cached per-extension behind a lock
    (not per-file) - a scan sees the same handful of extensions millions
    of times over, and `UTType(filenameExtension:)` does real work.
  - **`CleanupItem.findingID: CleanupFindingID` became `source:
    CleanupItemSource` (`.finding` or `.fileType`).** Explore's files
    needed to flow through the exact same `SelectionStore`/`ReviewView`/
    `CleanupCommitter` pipeline Cleanup findings already use - "selecting
    in Explore must not create a second, parallel delete path" - and
    `CleanupFindingID` has no case that means "a browsed file type."
    `CleanupItemSource.reviewGroupTitle` is what Review's group headers
    use instead of `CleanupFindingID.displayName` directly, so both
    sources render through one `groupSection` function.
  - **Photos-managed originals reuse the existing `.reportOnly`/`hint`
    mechanism (`FileTypeBrowser.ExploreFileDetail.makeCleanupItem`) rather
    than a new "locked" concept.** A managed original gets
    `safety: .reportOnly` and `hint: "Managed by Photos - delete it in the
    Photos app."` - the exact same lock-glyph-instead-of-checkbox path
    Cleanup's own report-only findings (iOS Simulator runtimes) already
    render, and `SelectionStore.toggle` already refuses `.reportOnly` items
    as a hard backstop, so a managed original genuinely cannot enter the
    selection, not just get discouraged in the view. iCloud sync status is
    a new, separate `CleanupItem.isiCloudSynced` flag - unlike Photos
    management, an iCloud file is still fully deletable, just badged with
    a warning, so it doesn't fit the report-only shape at all.
  - **`isUserContent` (dormant since the Cleanup restructure - see above)
    is now live: every `CleanupItem` Explore produces sets it
    unconditionally `true`.** This is what activates Review's Trash-only
    rule the moment any Explore file joins the selection, per the design
    handoff: "once user files can enter the selection, Review must drop
    the permanent-delete option entirely." No changes were needed in
    `ReviewView` itself to make this work - the branch has existed and
    been tested since the Cleanup restructure; item 6 is simply the first
    thing that can ever set the flag that triggers it.
  - **Photos/iCloud status and last-opened date are fetched on demand,
    only for the type a user actually opens, never eagerly for all
    eight at scan time.** `FileTypeIndexEntry` (built during the scan)
    carries only what's free - path, name, allocated size, and a cheap
    path-component check for Photos-library membership. `FileTypeBrowser.
    loadDetails` does the real I/O (`lstat` via the existing
    `FileStatReader`, `AppLastUsedDateProvider` reused as-is, and a new
    `URLResourceKey.isUbiquitousItemKey` check for iCloud) only for the
    entries a category's already-capped list contains, bounded at 2000
    regardless of the category's true file count. This is the third
    similar-but-distinct bounded-concurrency leaf-task window in the
    codebase (after `DuplicateDetector.withConcurrentTasks` and
    `PurgeScanner.measure(_:addingTo:totalTargets:)`) and deliberately
    isn't unified with either - same reasoning as those two: different
    shapes, coincidental overlap, not a proven-three-times duplication.
  - **The preview pane's "Details" table (video dimensions/duration, audio
    sample rate, image dimensions, PDF page count) described in the design
    handoff is not built - only Size and Last Opened are shown.** Getting
    real values needs per-type metadata APIs (`AVAsset` for video/audio,
    `CGImageSource` for image dimensions, `PDFKit` for page count), each
    with its own loading cost and failure modes; scoped out to keep this
    batch bounded. The thumbnail itself (the thing the handoff calls out
    as removing the most hesitation - "nobody deletes a video they cannot
    see") is fully real, via `QLThumbnailGenerator`. Revisit as a
    self-contained addition to `TypeFilePreviewPane` if wanted.
  - **`ThumbnailImageView`/`ThumbnailCache` (`Sources/DustEaterApp/
    Explore/ThumbnailImageView.swift`) is the same `QLThumbnailGenerator`
    wrapper the old, deleted `Inspector/ThumbnailImageView.swift` used
    (recovered from git history, not rewritten from scratch), generalized
    in one way: the `ImageFileDetector.isImage` gate is removed, since
    `QLThumbnailGenerator` itself already handles "can't generate a
    thumbnail for this" by returning nil, and Explore needs thumbnails for
    video/PDF/documents, not just images. The placeholder is now an
    injected `@ViewBuilder`, not a hardcoded `NSWorkspace` Finder icon,
    since Explore's placeholder is the type-tinted "Press Space for Quick
    Look" card the design calls for, not a generic icon.
  - **A segmented `Picker`'s reported intrinsic height inside
    `TypeDetailView`'s filter bar did not match its rendered height** -
    confirmed live (screenshot testing showed a ~300pt-tall card around a
    normal-height control row) and not fully root-caused; neither
    `.fixedSize()` on the pickers nor `.fixedSize(vertical: true)` on the
    containing `HStack` corrected it. Worked around with an explicit
    `.frame(height: 24)` on the filter bar's `HStack` rather than
    continuing to chase the SwiftUI layout-negotiation cause. If this
    class of bug recurs elsewhere (another segmented `Picker` in a
    constrained `HStack`), reach for the explicit height first.
  - **Applications never drills into a Type detail screen, structurally,
    not just by copy.** `TypeBoardView`'s `onSelectType` branches
    `category == .applications` before ever setting `selectedTypeCategory`
    - App Manager already does true-footprint uninstall, and building a
    second one was explicitly out of scope.
- **Permission onboarding (item 7 of the design handoff) -
  `Sources/DustEaterCore/Onboarding/`, `Sources/DustEaterApp/Onboarding/`,
  the Limited-access card in `CleanupView.swift`:** a three-step welcome
  flow before the first scan, plus a Cleanup-screen card when a scan ran
  without Full Disk Access. Item 8 (menu bar monitoring) is documented
  separately below.
  - **Access detection reuses `AttrListBulkReader.probeAccess`, the same
    probe `ScanCoordinator` already uses to distinguish "doesn't exist"
    from "access denied" before a scan.** `AccessProbe.hasFullDiskAccess(
    checking:)` (Core, new) is a thin public wrapper around that
    internal-to-the-module function, aimed at a fixed canary path
    (`~/Library/Containers`) instead of whatever the user chose to scan -
    the design handoff explicitly asks for this exact technique ("poll
    readability of one known-protected path"). No new probing logic, no
    widened visibility on `probeAccess` itself.
  - **`OnboardingStore.hasCompletedOnboarding` gates the welcome flow, and
    is deliberately *not* the thing that decides whether the Limited-access
    card shows.** Onboarding is a once-per-install flag (has the user ever
    been through the three steps); the Limited-access card checks
    `AccessProbe.hasFullDiskAccess()` live, every time `CleanupShellView`
    loads its disk context. This is what makes "skipped onboarding once,
    granted access later in System Settings" and "completed onboarding,
    then revoked access" both resolve correctly without extra state - the
    live check is the single source of truth for "is access limited right
    now," independent of how the user got there.
  - **`FullDiskAccessStepView` is one component, reused in two genuinely
    different contexts** - embedded as step 2 of `WelcomeView` (no chrome
    of its own; the shared footer's Back/Continue drives navigation), and
    presented standalone in a sheet from the Limited-access card's "Grant
    Access" button (wrapped in a `NavigationStack` with its own Done
    toolbar button). The component owns only the access-detection state
    (`.task(id: accessState)` polling once a second while `.waiting`,
    stopping automatically when the view disappears in either context);
    the embedding context decides what "leaving" means via `onSkip`.
  - **The welcome flow's centering needed `GeometryReader` +
    `.frame(minWidth:minHeight:)` on the `ScrollView` content, not just
    `.frame(maxWidth: .infinity)`.** A bare `Spacer` inside a `ScrollView`
    has no extra room to expand into - the ScrollView sizes its content to
    the content's own ideal size, so the column pinned to the top-left
    instead of centering. Confirmed live via screenshot before and after.
  - **Gotcha found because of the above fix, not before it**: once the
    centering trick proposes "up to the full window height" down through
    the view tree, `FullDiskAccessStepView`'s three diagram columns - each
    containing a `Spacer(minLength: 8)` to pin their mockup to the bottom -
    balloon to fill that entire proposal, since a `minHeight`-only frame
    doesn't cap how much larger a view can grow when its parent offers
    more room. Fixed with an explicit fixed `.frame(height: 140)` on each
    column instead of `minHeight`. Worth remembering for any other
    Spacer-containing card nested inside this same centering pattern.
  - **The Limited-access card's four skipped-location rows
    (`/Library/Caches`, `~/Library/Containers`, `~/Library/Group
    Containers`, `/private/var/folders`) are fixed, not derived from the
    scan.** They're always exactly what Full Disk Access unlocks,
    regardless of what a given scan happened to find - deriving them from
    the tree would require distinguishing "empty because nothing's there"
    from "empty because we couldn't read it," which the scanner doesn't
    currently surface per-directory.
  - **Welcome step 3's capacity figures are read from the boot volume
    (`/`), not from any particular scan target** - there is no scan target
    chosen yet at this point in a first-run flow (the multi-volume case
    hasn't reached `DiskHomeView` yet). The sidebar's own purgeable line
    (shipped in the Cleanup restructure) is what repeats this for whichever
    volume actually gets scanned, exactly as the design handoff specifies.
- **Menu bar monitoring (item 8 of the design handoff) -
  `Sources/DustEaterCore/Monitoring/MonitoringChecker.swift`,
  `Sources/DustEaterApp/Monitoring/`:** an `NSStatusItem` with a capacity
  ring + free-space figure, a custom dropdown, a 6-hour re-check of the
  fast-path findings only, and two notifications. Settings live in a
  Monitoring tab of the existing `Settings {}` scene - the sidebar stays
  three items, as specified.
  - **`MonitoringChecker.run()` calls exactly the same three static
    functions `ScanCoordinator.startFastPathFindingScans` already calls**
    (`PurgeScanner.fixedPathCategories()`, `AppManagerScanner.
    scanInstalledApps()`, a direct `DiskScanner` scan of `~/Downloads`) and
    nothing else - no tree walk, ever, in the background. It's
    intentionally independent of any live `ScanCoordinator` instance: the
    menu bar's numbers are the last check's, not whatever a foreground scan
    happens to be showing, and monitoring must keep working after the main
    window (and its `ScanCoordinator`) has been closed.
  - **`UNUserNotificationCenter.current()` crashes outright - an uncaught
    `NSInternalInconsistencyException`, "bundleProxyForCurrentProcess is
    nil" - when the running process isn't inside a real `.app` bundle.**
    Confirmed live, not assumed: `swift run`/the bare `.build/debug/
    DustEaterApp` executable used for local dev and CI hits this on the
    very first `UNUserNotificationCenter.current()` call. Every touch point
    (`StatusItemController.attach`'s delegate/category registration,
    `sendNotification`, `MonitoringSettingsPane`'s permission request) is
    guarded behind `Bundle.main.bundleURL.pathExtension == "app"`. This is
    the `UserNotifications` analogue of `DustEaterApp.setDockIcon`'s
    `Bundle.module` guard - a different framework, the same "only a
    packaged release `.app` has what this needs" shape.
  - **`StatusItemController` is an `NSObject` subclass, not a plain Swift
    class** - required for `#selector` target-action on the status item
    button and for `UNUserNotificationCenterDelegate` conformance. It
    reacts to `MonitoringSettingsStore` (an `@Observable`) via
    `withObservationTracking`, re-registering itself inside the `onChange`
    closure each time it fires - the non-View way to observe an
    `@Observable` object, since nothing in SwiftUI reads this controller's
    own state directly.
  - **`monitoringSettings` and `statusItemController` are created at the
    `DustEaterApp` level, not inside `ContentView`.** Two different
    reasons for two different objects: `monitoringSettings` needs to be the
    *same* instance passed into both the `WindowGroup` and the separate
    `Settings {}` scene, so a toggle in one window is reflected in the
    other immediately; `statusItemController` must outlive the main window
    closing entirely, since the whole point of a menu bar presence is
    working without a window open, and a `WindowGroup`'s content view (and
    everything `@State` on it) is torn down when its window closes.
  - **`NSPopover` sizing from an `NSHostingController` needed two fixes
    stacked, not one - confirmed live, each attempted fix alone still
    showed the popover at effectively zero height** (a highlighted status
    item button with no visible panel below it, verified via screenshot
    across several iterations before landing on this). `hostingController.
    sizingOptions = [.preferredContentSize]` keeps AppKit's read of the
    preferred size in sync with SwiftUI's real layout, but an explicit
    `popover.contentSize = NSSize(width: 268, height: 480)` is what
    actually made it reliable regardless of exactly when AppKit asks
    relative to SwiftUI's first layout pass. Both are kept.
  - **The two notifications use real `UNUserNotificationCenter` banners
    with registered `UNNotificationAction`s ("Review", "Notify Less"), not
    a custom-drawn overlay window matching the design handoff's literal
    16pt-radius/ultra-thick-material mockup.** Real system notifications are
    what users trust and recognize, and this app has no mechanism to draw a
    persistent custom banner outside its own window - the same "prefer real
    system APIs over hand-rolled approximations" reasoning the Cleanup
    chrome rewrite already established. The two actions still are exactly
    what the design specifies; only their pixel styling is OS-owned instead
    of app-drawn.
  - **The "reclaimable caches pass a threshold" notification is a threshold
    check against the current 6-hour snapshot, capped at once per day - not
    a true delta-since-last-cleanup computation.** The design's copy
    ("since you last cleaned up") suggests tracking growth from a baseline;
    doing that faithfully would need its own persisted baseline that resets
    on every real commit, which is meaningfully more state for a batch
    already large in scope. The simpler "did rebuildable bytes cross X,
    and have we not already said so today" still satisfies the literal
    rule as stated ("reclaimable caches pass a threshold") and safety rule
    12 (rebuildable-safety findings only, so a growing Photos library or
    video project can never trigger it) exactly as written.
  - **`ContentView` persists `lastScannedPath` to `UserDefaults`**
    (`DustEater.LastScannedPath`), independent of `coordinator.rootPath` -
    the menu bar needs a real volume to check even on a fresh launch before
    any scan has happened in this session, and "Review in DustEater"/
    "Rescan Now" from the dropdown fall back to it when `coordinator` is
    still `.idle` (e.g. the window was closed and this is the app's first
    activity since relaunch). `reviewFromMenuBar` starts a real scan in
    that case rather than pointing at a stale, non-interactive findings
    list - the monitoring check's own results have no selection/delete
    pipeline attached to them.
  - **`bringMainWindowToFront` finds the main window by title
    (`NSApp.windows.first(where: { $0.title == "DustEater" })`)** rather
    than trying to distinguish it structurally from the Settings window,
    sheets, or popovers - `WindowGroup("DustEater")` fixes that title, so
    it's a reliable, simple heuristic already available with no new state.
  - **Known limitation, not fixed here: closing the main window and later
    reopening it from the menu bar loses in-session state** (scan
    progress, findings, selection) - `WindowGroup`'s content view is torn
    down with its window, so a fresh `ContentView` starts over from
    `OnboardingStore`/`UserDefaults`-persisted state only. In the common
    case (`lastScannedPath` persisted, `coordinator.state == .idle`)
    "Review in DustEater" re-starts a real scan of the right volume rather
    than showing nothing, which covers the everyday case; full window-state
    restoration across a close/reopen cycle is real, separate scope this
    task didn't take on.
  - **Settings' `TabView` frame grew from 500x400 to 520x620** to fit the
    Monitoring tab's content - the Protected Apps tab (unrelated to this
    work) just gets more room at the same width; nothing there needed to
    change.
  - **Threshold pickers in `MonitoringSettingsPane` are preset `Menu`s (4
    fixed values each for the low-space percentage and the junk-growth
    byte count), not a slider or free-text field** - matches the design's
    "small mono pop-up pill" description functionally without building a
    custom numeric input control for a settings pane this size.
  - **The "Check every 6 hours" pill is display-only, not an editable
    control** - the design handoff's own copy treats 6 hours as fixed
    ("the 6-hour monitoring check"), unlike the two thresholds, which are
    explicitly "default-with-override."
  - **Discovered during live testing, unrelated to this feature's own
    code**: in this project's coding-agent sandbox specifically, syscalls
    against this machine's real `~/Downloads` intermittently return `EINTR`
    ("Interrupted system call") - reproduced even with a bare `ls
    ~/Downloads` at the shell, so it's an environment artifact, not
    something `DiskScanner`/`MonitoringChecker` introduced. Worth knowing
    if a future session sees `MonitoringChecker`/the old-downloads finding
    behave strangely (high CPU, a slow first check) on this specific
    machine - it is very unlikely to reproduce on a real user's Mac, and no
    code changed in response to it.
