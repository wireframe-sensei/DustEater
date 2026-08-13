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
- **Duplicate & Large File Hunter (`Sources/DustEaterCore/Duplicates/`,
  `Sources/DustEaterApp/Inspector/`):**
  - **Runs entirely over an already-scanned `FileNode` tree - no second
    directory walk, no second permission prompt.** Entry is
    `MainContentView`'s "Find Duplicates" toolbar button, reachable only
    from within `.scanFlow` once a scan has finished. There is no home-screen
    card for this feature; it deliberately has exactly one entry point.
  - **Timestamps and logical size come from on-demand `lstat`
    (`FileStatReader`), not from `FileNode` itself.** `FileNode.size` is
    on-disk *allocated* size, the wrong key for byte-accurate dedup (which
    needs logical `st_size`), and `FileNode` is instantiated millions of
    times per scan, so adding mtime/atime/birthtime there would be a real
    per-node memory regression for data almost no node needs. Candidates are
    pre-filtered by `FileNode.size` first (thousands of files after the
    default 1 MB floor, not millions), and only those get an individual
    `lstat`. Do not "optimize" this by extending `AttrListBulkReader` -
    that parser reads packed attributes in strict ascending bit order
    (`AttrListBulkReader.swift`), and inserting fields there is high-risk
    for a benefit this module doesn't need.
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
  - **Every smart-selection rule (`SmartSelector`) and the UI's own
    `DuplicateSelectionState` enforce the same invariant: at least one file
    per duplicate set is always left unselected.** A `DuplicateSet` is
    never smaller than 2 by construction, so "keep one, select the rest" is
    always well-defined. `allInDownloads` is the rule that actually needs
    this guard - when every copy in a set lives in Downloads, it keeps the
    newest rather than selecting all of them. Do not add a rule that can
    select every copy in a set.
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
  - **The confirmation sheet re-checks each file exists and is still
    deletable immediately before acting on it** (`DuplicatesView.
    performDelete`), rather than trusting the selection snapshot blindly.
    There's a real window between analysis and confirmation where the
    filesystem can change; this closes it for the cost of one
    `fileExists`/`canDelete` check per file.
  - **Deletion offers both Move to Trash and Delete Permanently**, matching
    the existing single-item delete alert in `MainContentView` - unlike App
    Manager's `UninstallConfirmationSheet`, which is trash-only. This was an
    explicit choice (not an oversight) to keep the app's delete UI
    consistent across features.
  - **`DuplicatesView`'s `root` is a snapshot, not live-updated after a
    delete made from within the inspector itself.** `ContentView.
    handleInspectorDeleted` reconciles the *main* scan tree via
    `removingNode` + `coordinator.updateTree` so the treemap and total
    stay correct, but the inspector's own `root` stays as it was when the
    screen opened. This is the same "detected, not reconciled live"
    trade-off `FileSystemWatcher` already documents elsewhere in this
    codebase. It's harmless in practice: re-analyzing against a stale root
    just fails to `lstat` the now-missing paths, which drop out on their
    own exactly like any file removed externally mid-scan.
  - **`MixedStateCheckbox` takes a plain `NSControl.StateValue`, not
    `AppUninstallSelection.SelectAllState`.** It was generalized when this
    module needed the same tri-state checkbox for a completely different
    selection type (`DuplicateSelectionState.SelectAllState`); both map
    onto `NSControl.StateValue` via a small `nsControlState` extension
    instead of coupling the shared component to either feature's selection
    type.
  - **No perceptual image hashing.** The brief asked for it as a Phase 2/
    optional item; it's deferred entirely. Approximate matches can't be
    safely auto-selected for deletion the way byte-identical matches can,
    and would need a distinctly more cautious UI (no Smart Select, probably
    a confidence indicator) rather than fitting into the existing
    `DuplicateSet`/`SmartSelector` shape. Revisit as its own scoped feature
    if wanted.
  - **Developer-tool directories (`node_modules`, `.git`, package-manager
    caches, build output) are hidden from both lists by default**
    (`DeveloperArtifactFolders.swift`), with a "Show Developer Tool
    Folders" toggle in the Filters menu to reveal them instantly. This is a
    different risk category from `BundleProtection`: deleting a file out
    of a signed `.app` breaks a code signature, but deleting a duplicate
    file out of a project-local `node_modules` breaks that specific
    project's build until it's reinstalled - and unlike a global
    package-manager cache (`~/.npm`, `~/Library/Caches/npm`), which
    regenerates cleanly, neither `DuplicateDetector` nor `LargeFileFinder`
    has any way to tell an active `node_modules` from an abandoned one.
    The same package is also routinely installed byte-identically across a
    dozen unrelated projects, making this the single biggest source of
    noisy, low-value duplicate reports on a developer's Mac. The toggle
    only changes what's *visible* for auditing total size - it doesn't
    make anything safer to select for deletion, and the help text on the
    toggle says so explicitly. App Manager's existing "Developer Tools"
    detection (`DeveloperToolFolders.swift`) was evaluated and found not
    reusable here: it's a fixed 24-name list matched only against top-level
    folders directly under `~/Library/{Caches,Containers,...}`, and never
    walks into project-local `node_modules` scattered across the disk -
    entirely different scope from what this needed.
  - **The exclusion filters at *display* time, not scan time - `DuplicatesView`
    always calls Core with `includeDeveloperArtifacts: true`, and filters
    `duplicateSets`/`largeFileEntries` (computed properties) based on the
    toggle instead.** `DuplicateScanOptions.includeDeveloperArtifacts` /
    `LargeFileFilter.includeDeveloperArtifacts` (Core) still support
    skipping these directories entirely during the tree walk - never
    stat'd or hashed - and stay covered by `DuplicateDetectorTests`/
    `LargeFileFinderTests` for callers that want that (a future CLI tool,
    for instance). The GUI deliberately doesn't use that mode: an earlier
    version did, which meant flipping the toggle required a full re-scan
    since the excluded files' sizes/hashes/dates had genuinely never been
    gathered. Filtering at display time (`DeveloperArtifactFolders.
    pathContainsDeveloperArtifact`, checking path components against the
    same name list) makes the toggle instant, at the direct cost of every
    scan always hashing `node_modules`/`.git` trees whether or not they end
    up shown - a real tradeoff, decided in favor of toggle responsiveness
    over default-scan speed. If that tradeoff ever needs revisiting (e.g.
    scans feel slow on `node_modules`-heavy machines), switch
    `runFullAnalysis`'s hardcoded `true` back to the toggle's value rather
    than re-deriving this from scratch.
  - **Deleting every copy of a duplicate file (including what would
    otherwise be the protected "last copy") is possible, but deliberately
    requires a separate, explicit action from the normal flow.**
    `DuplicateSelectionState.toggle` (`DuplicateSelectionState.swift`) no
    longer refuses to select the last unselected file in a set - the
    checkbox on that file's `FileFactsCard` is warned (an orange "Last
    Copy" badge, distinct help text) rather than disabled. A dedicated
    "Include Original" button in `DuplicateSetOverview`, styled and labeled
    distinctly from "Select All", does the same thing in one click, and
    only appears while there's still a copy left to include. Two things
    are unconditionally *not* touched by this:
    - `SmartSelector`'s automated bulk rules (`SmartSelector.swift`, Core)
      keep their hard "always keep one survivor" guarantee unconditionally,
      still enforced by `noRuleEverSelectsEveryFileInASet` and friends -
      Smart Select applies across potentially dozens of sets at once with
      far less per-file visibility than the overview gives, so that's the
      one place a full wipe must never be reachable.
    - `DuplicateCleanConfirmationSheet` detects when a delete would leave
      zero copies of a file (`DuplicatesView.fullyDeletedFileNames`) and
      shows an explicit "No Copies Will Remain" warning banner, distinct
      from the routine "delete N duplicate files" framing - this is a
      meaningfully more consequential outcome (the file is gone, not just
      decluttered) and the confirmation step says so before it happens.
  - **Image duplicate sets render as a grid of `DuplicateImageCard` tiles
    (`DuplicateSetOverview.swift`) - thumbnail, checkbox overlaid top-left,
    details below - one card per copy, not one shared preview.** This
    superseded an earlier version of the design that showed a single
    "hero" thumbnail once above a text-first row list, reasoning that since
    every copy is byte-identical there was nothing to gain from repeating
    the same picture per row. That reasoning about *comparison* was correct
    but solved the wrong problem: each row still needs to be an
    independently clickable, recognizable selection target (matching
    Photos.app's own duplicate-review grid - photo tile + selection badge,
    not a filename you have to read), and a single shared hero doesn't
    provide that. The picture repeating across cards is therefore
    intentional, not a regression to "fix" back into one preview - it is
    not there for visual comparison (every card shows the identical
    bytes), it's what makes each tile self-sufficient as a click target.
    Non-image duplicate sets keep the original `FileFactsCard` stacked-row
    layout (`DuplicateSetOverview.isImageSet` branches between the two) -
    the card grid only makes sense once there's real image content to
    show.
    `ThumbnailImageView.swift` wraps `QLThumbnailGenerator`
    (`QuickLookThumbnailing`, auto-links with no `Package.swift` change,
    same as `QuickLookUI`) behind an actor-based cache (`ThumbnailCache`)
    that de-duplicates concurrent requests for the same path/size - this is
    what makes rendering the same picture across several cards cheap rather
    than re-generating it per card. `FileFactsCard`'s smaller inline
    thumbnail (40pt, shared with the large-files detail panel) is unrelated
    to this and unchanged. `ImageFileDetector.isImage(atPath:)` (Core,
    `UniformTypeIdentifiers`, also auto-links) decides per-file whether to
    attempt a thumbnail at all; non-image files keep the plain `NSWorkspace`
    Finder icon, which is also `ThumbnailImageView`'s loading state and its
    failure fallback - there is no separate spinner. `DuplicateImageCard`'s
    selection badge is a hand-built `ZStack` (translucent circle backing +
    SF Symbol), not SF Symbols' `.palette` rendering mode - `circle` (the
    unselected symbol) is single-layer, so palette mode has no second layer
    to carry the dark backing color, which would silently vanish over a
    bright photo. Don't "simplify" it back to `.palette` without checking
    that both `circle` and `checkmark.circle.fill` actually have matching
    layer counts.
- **Developer & Creative Power-User Clean Up Kit
  (`Sources/DustEaterCore/DeveloperKit/`, `Sources/DustEaterApp/DeveloperKit/`):**
  - **`PurgeSafetyLevel` has four cases, not the three originally briefed** -
    `.safe`, `.rebuildable`, `.caution`, and `.reportOnly`. The fourth exists
    so "a Docker card with a delete button" is unrepresentable in the type,
    not merely discouraged in the view: Docker's `Docker.raw`, mounted
    Simulator runtime volumes, and Final Cut Pro/Logic Pro library contents
    genuinely have no safe deletion path from outside their owning app, so
    they're sized and explained but never offered a toggle at all -
    `TargetCardView`'s `footer` branches on `.reportOnly` to render Reveal
    in Finder plus a hint instead of a `Toggle`, and `PurgeSelection.toggle`
    refuses `.reportOnly` a second time at the data layer as a hard backstop
    independent of what the view happens to render.
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
    those specific subfolder names if present and report zero (rendering no
    card at all, per `DeveloperKitView`'s zero-byte filter) if the guessed
    names don't match a real installation - a wrong guess costs a missing
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
  - **Trash-vs-Permanent button prominence is inverted from
    `DuplicateCleanConfirmationSheet`, on purpose.** There, Move to Trash is
    the prominent default. Here, `PurgeConfirmationSheet.actionButtons`
    makes Delete Permanently prominent whenever the selection is only
    `.safe`/`.rebuildable`, and only swaps to Trash-prominent once a
    `.caution` target is included. Reasoning: moving 40 GB of DerivedData to
    the Trash frees zero bytes until the Trash is emptied, and the Trash
    sits on the *same volume* - the entire point of this screen is freeing
    space *now*, and every `.safe`/`.rebuildable` target is regenerable by
    definition, so the safety net Trash provides is worth less here than the
    friction it costs. A `.caution` target has no such regeneration
    guarantee, so it gets the same Trash-first treatment as every other
    destructive action in the app. Both buttons always exist regardless;
    only which one is `.borderedProminent` changes.
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
    `PurgeScanner` (building the final `.loaded` state) and
    `DeveloperKitView` (grouping the partial `measured` array shown mid-scan
    for streaming cards) - this is the one grouping helper in the module
    that *was* promoted, deliberately, unlike `withConcurrentTasks` above.**
    The difference: this one has two real call sites that need the *exact*
    same grouping today, not a hypothetical third, and duplicating six lines
    of `filter`/`sort` across a Core service and a SwiftUI view is the kind
    of drift Rule of Three is meant to prevent once there's already a second
    real caller, not just a first.
  - **Xcode Archives never becomes a bulk-selectable `PurgeTarget`, on
    purpose - it's the one category with its own dedicated drill-in list**
    (`XcodeArchiveLister`, `XcodeArchivesListView`). An `.xcarchive` holds
    the dSYM needed to symbolicate a crash report from a build that may have
    shipped; once deleted there's no way back, since rebuilding produces a
    different UUID, not a replacement for the one that's gone. A `.caution`
    badge on a single bulk toggle was judged insufficient friction for a
    one-click, irreversible action with zero regeneration path - so instead
    the Xcode category surfaces an `ArchivesSummaryCardView` with a "Browse
    Archives" button (not a toggle) that opens a per-archive list, and
    deletion happens one archive at a time through the same Trash/Permanent
    alert pattern `MainContentView` already uses for a single selected item.
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
    independently in both `DeveloperKitView.performPurge` and
    `XcodeArchivesListView.delete` - defense in depth, not trusted to a
    single call site.
  - **`FileOperations.clearSystemCaches()` was removed, not fixed in
    place.** It deleted every direct child of *both* `~/Library/Caches`
    *and* `~/Library/Application Support` - the latter is real application
    data (login state, licenses, local databases), not a cache - bypassed
    `canDelete`, deleted permanently with zero confirmation, and swallowed
    every per-item failure with a bare `continue`. Its only caller was the
    Tools menu's "Clear Cache" item in `MainContentView`'s toolbar, which
    this module's toolbar entry point replaced outright; the Tools menu
    itself was removed too since that item was its only content. See
    `CHANGELOG.md`'s Unreleased section for the user-facing note - this is a
    real behavior removal, not an invisible refactor.
