# CLAUDE.md

Guidance for Claude Code (or any agent) working in this repository. This
file records conventions and procedures established through actual work on
the project — not aspirational rules, but what this codebase actually does
and why.

## Project overview

DustEater is a native macOS disk-usage analyzer: SwiftUI + AppKit GUI, no
external dependencies, distributed as a Swift package (no `.xcodeproj`).

- `Sources/DustEaterCore` — scanning (`getattrlistbulk` + `TaskGroup`), the
  squarified treemap layout algorithm, app-bundle grouping, byte formatting.
  No SwiftUI/AppKit dependency — keep it that way, it's what makes the logic
  unit-testable.
- `Sources/DustEaterApp` — the GUI.
- `Sources/dustbench`, `Sources/appsizes` — CLI tools on top of `DustEaterCore`.
- `Tests/DustEaterCoreTests` — tests for the core library.
- `.claude/skills/macos-hig-design-system/` — the design-system skill this
  project's UI work is built from (`SKILL.md`, `references/swift.md`,
  `references/color-tokens.md`, `references/sizing-tokens.md`,
  `references/components.md`, `references/materials-and-effects.md`,
  `assets/MacOSDesignTokens.swift`). Load it before UI/design work — see below.

## Build & test

```sh
swift build              # debug
swift build -c release   # release
swift test
swift run DustEaterApp
```

Always run `swift build` after any change before considering it done. For
UI-visible changes, be explicit that you can't see/run the GUI yourself —
state what's verified (build succeeds) vs. what's an untested visual guess,
and ask the user to confirm before committing when genuinely uncertain
about the result. Don't claim something is "confirmed working" based only
on a build succeeding on this one local machine — see the SDK/toolchain
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
  defined in `Design/MacOSDesignTokens.swift`) for interface chrome — button
  labels, menu items, sidebar rows, table rows. Real semantic fonts
  (`.body`, `.headline`, `.title2`, `.callout`, etc.) for content text.
  `DustEaterTheme.Typography` (in `Design/DustEaterTheme.swift`) aliases
  onto real semantic `Font` values, not fixed point sizes — keep it that way.
- **Control sizing**: set `.controlSize()` once at a container level, never
  thread a size parameter through the view tree by hand. Custom-drawn
  controls read `@Environment(\.controlMetrics)` (also in
  `MacOSDesignTokens.swift`) rather than hardcoding radii/heights.
  - `ControlMetrics.isCapsule` is `true` at `.large`/`.extraLarge` per the
    kit's `Button/Radius` token (large buttons become full capsules). This
    is **only for controls actually drawing themselves as a compact
    button.** `DiskCardView`/`CustomFolderCardView` in `DiskHomeView.swift`
    are wide custom cards, not pill buttons — they deliberately read only
    `metrics.cornerRadius` and ignore `isCapsule`, documented inline. Don't
    "fix" that to use `isCapsule` — it would turn them into giant pills.
- **Materials**: sidebars/toolbars get `.bar` or `.regularMaterial`;
  `.ultraThinMaterial` for content-area panels/cards. Real system chrome
  (`NavigationSplitView`, `.toolbar`) gets its material from the OS
  automatically — don't add explicit `.background(material)` there, it's
  redundant and can actually defeat the system chrome's own vibrancy.
- **`controlActiveState`**: custom-drawn (non-system) "this is highlighted"
  indicators must desaturate toward `Color(nsColor: .systemGray)` when the
  window isn't key, matching how real selection highlighting works. System
  controls (`List(selection:)`, `Menu`) already do this for free.
  `TreemapView`'s hover highlight is the one hand-drawn example — see
  `highlightColor` there for the pattern.
- **Prefer real system APIs over hand-rolled approximations.** The chrome
  rewrite (`MainContentView` in `ContentView.swift`) replaced a hand-rolled
  `HStack` "sidebar" + fake "toolbar" `VStack`s (styled with `.background(.bar)`
  to *look* like chrome) with a real `NavigationSplitView` + `.toolbar`.
  Visually similar modifiers on plain views do not reproduce real toolbar
  button hover states, unified-titlebar blending, or the native
  sidebar-toggle button — those are behaviors the system control implements,
  not styling you can fake. When something "doesn't look native" despite
  correct colors/fonts/materials, suspect the underlying container/control
  choice before reaching for more styling.
- **`Design/MacOSDesignTokens.swift` should contain only what has no system
  equivalent** — `Font.control`, `ControlMetrics`, `Color.progressTrack`,
  `TreemapMetrics`, `TooltipMetrics`, `glassBackground(_:cornerRadius:)`.
  Don't add something here that a real system API already resolves.

Load the `macos-hig-design-system` skill before any UI/design work, even if
the request doesn't say "design system" explicitly — it covers colors,
sizing, typography, materials, and the component inventory this app is
built against.

## SDK/toolchain gotcha — verify against CI, not just locally

This machine may have a newer Xcode/SDK installed than GitHub's hosted
runners. `swift --version` here currently reports Xcode 26 / Swift 6.3 with
the macOS 26 SDK — new enough for `.glassEffect` and other Liquid Glass
APIs. GitHub's `macos-15` runner (used by `.github/workflows/ci.yml` and
`release.yml`) is on an older Xcode that does **not** declare those symbols
at all.

**`#available(macOS 26, *)` only gates runtime behavior — it does not help
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
surfaced it) — see `glassBackground(_:cornerRadius:)` in
`MacOSDesignTokens.swift` for the real fix. **Before considering any
bleeding-edge API change "done," check that CI actually passes** —
`gh run watch <run-id> --exit-status` after pushing, don't assume a local
build result generalizes.

## Git & commit conventions

- Never commit unless explicitly asked. Never push unless explicitly asked.
- Before starting a multi-stage change, check `git status`. If the tree is
  dirty, stop and ask how to proceed rather than guessing — don't fold
  unrelated pending work into a new change's commits without saying so.
- For staged/multi-part work: one commit per logical stage, not one per
  file, with a descriptive message. If working from a written audit/plan
  with finding IDs, reference them in the commit message.
- Never commit build artifacts or binaries into the tree (see Releases,
  below, for how binaries actually get distributed).
- Don't rewrite history (rebase/amend) on commits already pushed, even to
  fix a mistake — create a new commit, or in the specific case of a tag
  that was pushed moments ago and never produced a real published artifact,
  it's fine to delete and re-push that tag (this happened once, to move
  `v0.1.0` off a commit whose release build had failed before publishing
  anything).

## Releases

Distribution is DMGs attached to GitHub Releases — not committed binaries.

- `Packaging/Info.plist` — template bundle Info.plist, `__VERSION__`
  placeholder substituted by the release workflow. DustEater has no
  Info.plist for local development (`swift run` uses a bare executable);
  this is packaging-only and doesn't affect the dev workflow.
- `.github/workflows/release.yml` — triggered by pushing a tag matching
  `v*.*.*`. Builds arm64 and x86_64 release binaries separately, `lipo`s
  them into a universal binary, assembles `DustEater.app`, ad-hoc codesigns
  it (no Developer ID certificate is configured — `security find-identity
  -v -p codesigning` returns zero identities on record), packages as a DMG
  via `hdiutil`, and publishes a GitHub Release via `gh release create`.
  Releasing is `git tag vX.Y.Z && git push origin vX.Y.Z` — no manual steps
  otherwise.
- **Known limitation**: because of the SDK gotcha above, CI-built releases
  only get the Material fallback (no real Liquid Glass) — `.glassEffect`
  compiles out on the `macos-15` runner. For a build with genuine Liquid
  Glass, build locally on a machine with the macOS 26 SDK using the same
  steps as the workflow, then `gh release upload vX.Y.Z <path-to-dmg>
  --clobber` to replace the CI-built asset. This is a manual extra step
  after every tag push until GitHub's hosted runners get a new-enough
  Xcode, or a self-hosted runner is set up for releases.
- Builds are unsigned/ad-hoc-signed (no Apple Developer Program membership
  behind this project). Gatekeeper will warn on first launch — the
  workaround (`xattr -cr` or right-click → Open) is documented in the
  release notes and README's Download section. This was a deliberate
  choice, not an oversight — revisit only if the project gets a Developer
  ID certificate.

## Licensing

MIT for DustEater's own code (`LICENSE`). One exception:
`Sources/DustEaterCore/Treemap/YMTreeMap.swift` is Yahoo's squarified-treemap
algorithm (`Copyright 2017 Yahoo Holdings Inc.`), used under its original
Apache License 2.0 terms — its copyright header must stay intact, and
`NOTICE` carries the full attribution and license text per Apache 2.0 §4(a).
Don't relicense or strip that file's header.

## Deliberately deferred / intentional exceptions

Things that look like they might need fixing but are actual decisions, not
oversights — don't "fix" these without the user asking:

- The Pastel color theme's white tile-label text has a real contrast issue
  against light tiles (`TreemapView.swift`'s labels) — explicitly deferred,
  not yet addressed.
- Per-appearance (light/dark) variants of the treemap color themes in
  `ColorTheme.swift`/`TreemapColors.swift` — the 6 fixed palettes are not
  yet appearance-aware. Explicitly deferred; large enough to be its own task.
- `DiskCardView`/`CustomFolderCardView` not using `ControlMetrics.isCapsule`
  — see Design system conventions above, this is correct as-is.
- Sidebar/toolbar icons are plain monochrome SF Symbols (Finder-style), not
  colored rounded-square icon-tile badges (App Store/Settings-style) — an
  explicit choice, since this app is a file/disk browser closer to Finder's
  category than a hub-style app.
