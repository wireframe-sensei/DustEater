# Changelog

All notable changes to this project will be documented in this file.

## [0.1.2] - 2026-08-09

### Fixed
- **Scan Cancellation**: Fixed cancellation to stop directory traversal immediately instead of continuing to scan in the background. Previously, cancelling a scan would update the UI but the filesystem scan would continue, causing incorrect progress and strange behavior when starting a new scan.
- **Card Clickability**: Fixed entire home screen cards now being fully clickable. Previously, only the text/icon areas were clickable and empty space on the cards was not responsive. Both disk cards and custom folder card now have their entire surface clickable.
- **App Icon**: Updated app icon with properly rounded corners to match macOS conventions. The icon now displays correctly in the dock with rounded corners like other native macOS apps.

## [0.1.1] - 2026-08-09

### Changed
- **App Icon**: Updated app icon with rounded corners to match macOS design conventions.

## [0.1.0] - 2026-08-09

### Added
- Initial release of DustEater - a native macOS disk usage analyzer
- Recursive directory scanning with parallel TaskGroup for fast analysis
- Interactive treemap visualization with color themes
- Support for macOS Liquid Glass (Material fallback on older systems)
- Built-in disk selection and custom folder browsing
- Real-time progress updates during scanning
- App bundle detection and grouping by bundle identifier
