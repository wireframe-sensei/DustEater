# DustEater

[![CI](https://github.com/wireframe-sensei/DustEater/actions/workflows/ci.yml/badge.svg)](https://github.com/wireframe-sensei/DustEater/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native macOS disk usage analyzer. Scan a volume or folder and see where the
space went in an interactive treemap — zoom into folders, inspect individual
files, and see app bundles rolled up with the data they leave behind in
`~/Library`.

Built with SwiftUI and AppKit, no external dependencies, distributed as a
Swift package.

## Features

- **Fast recursive scanning** — uses `getattrlistbulk` with concurrent
  `TaskGroup`s rather than `FileManager` enumeration, so large volumes scan
  quickly.
- **Interactive treemap** — squarified treemap layout, click to zoom into a
  folder, hover for details, seven color themes (including a size-weighted
  green→red gradient).
- **App bundle grouping** — `.app` bundles are shown as one unit, with their
  actual footprint (caches, application support, logs, etc. in `~/Library`)
  cross-referenced and rolled into the bundle's true size rather than
  appearing as unexplained space elsewhere.
- **File details view** — click any file in the sidebar tree to see its type,
  size, and full path.
- **Native chrome** — real `NavigationSplitView` sidebar and unified toolbar,
  semantic system colors and materials throughout, and genuine Liquid Glass
  on macOS 26+ (falls back to a Material-based approximation on earlier
  systems — no separate build required).

## Requirements

- macOS 14 or later to build and run.
- Swift 6 toolchain (Xcode 16+).
- macOS 26+ if you want the real Liquid Glass rendering; everything works
  on earlier systems too, just with a Material approximation instead.
- **Full Disk Access.** DustEater runs unsandboxed so it can read arbitrary
  user directories; without Full Disk Access (System Settings → Privacy &
  Security → Full Disk Access) it can only scan folders the OS grants
  ordinary access to. The app will prompt you and link straight to the
  right settings pane if it hits a folder it can't read.

## Building and running

```sh
git clone https://github.com/wireframe-sensei/DustEater.git
cd DustEater
swift run DustEaterApp
```

Or open the folder in Xcode (`File → Open…`, select the package folder) and
run the `DustEaterApp` scheme.

### Other targets

The package also builds two command-line tools on top of the same scanning
engine, useful for benchmarking or scripting without the GUI:

```sh
swift run dustbench ~/Documents   # scan + report timing and top entries
swift run appsizes                # true install footprint of every app in /Applications
```

### Tests

```sh
swift test
```

## Project layout

```
Sources/
  DustEaterCore/   Scanning, the treemap layout algorithm, app-bundle
                    grouping, and byte formatting — no UI dependencies.
  DustEaterApp/     The SwiftUI/AppKit GUI.
  dustbench/        CLI: scan a path and report timing.
  appsizes/         CLI: true per-app disk footprint across /Applications.
Tests/
  DustEaterCoreTests/
```

`DustEaterCore` is a plain library target with no dependency on SwiftUI or
AppKit, so the scanning/layout logic is testable and reusable independent of
the GUI.

## License

MIT — see [LICENSE](LICENSE). One file
(`Sources/DustEaterCore/Treemap/YMTreeMap.swift`, Yahoo's squarified-treemap
algorithm) is used under its original Apache License 2.0 terms; see
[NOTICE](NOTICE) for the full text and attribution.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md)
for setup, project layout, and PR guidelines. This project follows the
[Code of Conduct](CODE_OF_CONDUCT.md).
