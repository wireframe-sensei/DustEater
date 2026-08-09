# Contributing to DustEater

Thanks for considering a contribution.

## Getting started

```sh
git clone https://github.com/wireframe-sensei/DustEater.git
cd DustEater
swift build
swift test
swift run DustEaterApp
```

You'll need macOS 14+ and a Swift 6 toolchain (Xcode 16+). No external
dependencies to install — it's a plain Swift package.

## Project layout

- `Sources/DustEaterCore` — scanning, the treemap layout algorithm, app-bundle
  grouping, byte formatting. No SwiftUI/AppKit dependency, so it's the right
  place for logic that should be unit-testable in isolation.
- `Sources/DustEaterApp` — the SwiftUI/AppKit GUI.
- `Sources/dustbench`, `Sources/appsizes` — CLI tools built on `DustEaterCore`,
  useful for exercising scanner changes without the GUI.
- `Tests/DustEaterCoreTests` — tests for the core library.

## Before opening a PR

- For anything beyond a small fix (new features, behavior changes,
  refactors), please open an issue first to discuss the approach — saves
  everyone rework if the direction needs adjusting.
- Run `swift build` and `swift test` locally; CI runs the same on every PR.
- Keep PRs focused. A PR that does one thing is much easier to review than
  one that mixes a fix with an unrelated cleanup.
- Add or update tests in `DustEaterCoreTests` for changes to `DustEaterCore`.
- Match the existing code style — see the codebase itself for conventions
  (this project favors semantic system colors/fonts/materials over hardcoded
  values in the UI layer, and keeps `DustEaterCore` free of UI dependencies).

## Reporting bugs

Open an issue with:
- macOS version and whether you're on Apple Silicon or Intel.
- Steps to reproduce.
- What you expected vs. what happened.

If it's a scanning issue, the path/volume you were scanning (or its rough
size/structure, if you'd rather not share the exact path) is helpful context.

## Releasing (maintainers)

Releases are fully automated. Pushing a tag matching `v*.*.*` triggers
`.github/workflows/release.yml`, which builds a universal (arm64 + x86_64)
release binary, packages it as `DustEater.app` using the `Packaging/Info.plist`
template, ad-hoc codesigns it, wraps it in a DMG, and publishes it as a
GitHub Release with auto-generated notes:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The version number in the tag (without the `v`) becomes both
`CFBundleShortVersionString` and `CFBundleVersion` in the shipped app. No
manual build step, no local signing — the whole thing runs on
`macos-15` GitHub-hosted runners.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you're expected to uphold it.
