# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Developer & Creative Power-User Clean Up Kit**: New feature to find and
  safely reclaim developer and creative-app caches and build artifacts
  - Catalog of known Xcode, package-manager, Docker, and Adobe cache
    locations, sized against the current scan with no extra permission
    prompt, plus project-local artifacts (`node_modules`, Cargo `target`,
    `.build`, `Pods`) discovered from the same scanned tree
  - Every target is labeled Safe, Rebuildable, Caution, or Report Only,
    with the exact rebuild command shown for anything rebuildable
  - Docker's disk image, iOS Simulator runtimes, and Final Cut Pro/Logic
    Pro library contents are Report Only - sized and explained, but never
    offered for direct deletion, since none of them can be safely removed
    from outside their owning app
  - Xcode Archives get their own drill-in list rather than a bulk toggle -
    delete one specific old archive, not "Archives (14 GB)" at once, since
    an archive holds the only dSYM for a build that may have shipped
  - Batched purge with a confirmation sheet, per-item progress, and Trash
    or permanent deletion

### Removed
- **System Cache Clearing** (Tools > Clear Cache): removed in favor of the
  Developer Kit above. The old implementation deleted every direct child of
  both `~/Library/Caches` *and* `~/Library/Application Support` - the
  latter holds real application data (login state, licenses, local
  databases), not a cache - bypassed the app's own protected-path checks,
  deleted permanently with no confirmation, and silently swallowed
  per-item failures.

### Fixed
- **Bundle Protection**: `.fcpbundle`, `.imovielibrary`, `.theater`,
  `.tvlibrary`, `.logicx`, and `.band` library packages are now protected
  the same way `.app`/`.framework` already were. Previously the duplicate
  and large-file inspectors could offer individual files inside a Final
  Cut, iMovie, TV, Logic, or GarageBand library for deletion.

## [0.3.0] - 2026-08-11

### Added
- **App Manager**: New feature to identify and uninstall leftover app data
  - Detects installed apps and scans their associated data folders
  - Shows storage usage per app including cache, support files, and preferences
  - Identifies orphaned app folders (leftover data from uninstalled apps)
  - Vendor-nested folder detection for Google, Microsoft, Adobe, JetBrains patterns
  - Launch history integration to identify recently used apps
- **Settings Panel**: New preferences UI for managing app removal
  - Protected apps list - select apps to exclude from removal
  - Settings persist across app sessions
- **UI Improvements**
  - Home screen heading now correctly displays "Dust Eater" (was "Disk Analyzer")
  - App Manager card now matches disk/folder card sizing and is fully clickable

### Fixed
- **UI Dead Ends**: Multiple navigation dead ends fixed
  - Error state and permission banner now have back-to-home buttons
  - Idle scan state now has a cancel button
  - Delete and cache clear failures now show user-facing alerts (previously silent)
- **Sidebar Navigation**: Select a node from treemap and sidebar auto-expands to show it
- **Toolbar Actions**: Per-item actions (Reveal in Finder, Copy Path, Delete) moved to toolbar for better sidebar space

## [0.2.0] - 2026-08-09

### Added
- **Live Disk Capacity Refresh**: Disk usage updates automatically every 5 seconds
- **Filesystem Change Detection**: FSEvents-based monitoring with "Rescan" prompt
- **File Deletion**: Delete individual files with confirmation and protected-path safety checks
- **System Cache Clearing**: Clear application caches with protected-path safety checks
- **Retry State**: Home screen shows retry button when disk loading fails

### Fixed
- **Sidebar Navigation Rework**: Replaced OutlineGroup with hand-rolled FileOutlineRow
  - Enables selecting nodes from treemap and auto-expanding sidebar to reveal them
  - Fixes sidebar names rendering as "n...", "p...", "C..." at real depths
- **Toolbar Navigation**: Real browser-style back/forward history replaces simple back button
- **Dead End Prevention**: Added explicit navigation out of error, permission, and idle scan states

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
