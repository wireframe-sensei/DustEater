# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-08-20

### Fixed
- **The Cleanup / Explore / Apps sidebar rows only responded to clicks
  directly on their icon or label** - the empty space around them, despite
  looking like part of the same clickable row, did nothing
- **Explore's Code & Projects total and file list were both quietly wrong
  in the same way**: a dependency tree's own files (a `.js` file deep
  inside `node_modules`, a stray icon it ships) were each individually
  classified by extension, so a project's true weight scattered across
  Code & Projects, Other, Photos, and more instead of counting toward the
  project. On a real ~22 GB `node_modules`-heavy folder this meant Code &
  Projects read as little as 270 MB. `node_modules`, `.next`, `dist`,
  `build`, `target`, `.venv`/`venv`, `Pods`, and `DerivedData` are now
  each counted as one folder with its real, full size
- **A Final Cut Pro/Logic Pro/GarageBand library, or a `.framework`/
  `.bundle`/`.xpc`/`.plugin`/`.appex`/`.sparsebundle` package, no longer
  scatters its internal files across Videos/Audio/Other individually** -
  the same fix as above, applied to every category, not just Code &
  Projects
- A `.framework` bundled inside a `.app` (the routine case) could be
  double-counted - folded correctly into the app's own total, then
  counted a second time as its own entry elsewhere

### Changed
- **Code & Projects lists projects, not dependency folders and not
  individual files.** A `.git` repository, or a directory rooted by a
  top-level `package.json`/`Cargo.toml`/`go.mod`/`Package.swift`/
  `pyproject.toml`/`*.xcodeproj`, is one row - its name, its path, its
  real total size (matching the sidebar treemap for that folder exactly),
  when it was last opened, and a summary of what's reclaimable inside it
  ("2.8 GB in 4 node_modules - rebuild with npm install"). A monorepo with
  a `node_modules` per package is one row, not one per package. Expanding
  a project shows its `node_modules`/`.next`/`dist`/`build`/`target`/
  `.venv`/`Pods`/`DerivedData` folders individually - still locked, still
  showing the exact rebuild command (`npm install`, `cargo build`, and so
  on - the same hints Cleanup's Developer Kit already used), never
  selectable, since the correct action is the rebuild command, not a
  Trash move. A loose file that isn't part of any detected project - a
  stray 400 MB CSV, a standalone script - still lists individually below

### Added
- **Apps**: the app list column now lives directly in the main window,
  under checkboxes wired to the same selection tray and Review screen
  every other Cleanup surface uses - uninstalling an app is no longer a
  separate delete path with its own confirmation sheet
  - Selecting the same app from here or from Cleanup's "unused
    applications" finding is the same selection either way
  - "Orphaned" is renamed to "Unused"
  - The detail pane is now a full breakdown of what an uninstall would
    remove - the application bundle, then each related item (caches,
    application support, containers, saved state, preferences) with its
    own path, size, and a Reveal in Finder button
  - Nothing is pre-selected

### Fixed
- **Apps**: the app list was rendered as its own floating panel with a
  second toolbar and Home button nested inside the main window, and app
  names could wrap onto two or three lines at the list's actual width.
  Both are fixed - the list now sits directly in the shared content area,
  and rows truncate to one line with a tail ellipsis instead of wrapping
- The selection tray (total size, item count, Review button) now appears
  on the Explore and Apps screens too, not only on Cleanup's findings
  screen - previously, selecting a file in Explore or an app in Apps gave
  no visible way to reach Review without switching back to Cleanup first

### Removed
- **Apps**: the confirmation-sheet uninstall flow, its own "Select All"
  checkbox, the per-row "quit and uninstall" convenience for a running
  app, and the in-panel Settings/Home shortcut buttons are gone, replaced
  by the shared checkbox-and-Review flow described above. A running app
  you try to uninstall from Review is now skipped with an error rather
  than offered a quit-and-retry

### Changed
- **The disk picker is shown on every launch again, regardless of how many
  volumes you have** - reversing the single-volume auto-skip shipped
  earlier. A full-disk scan can run well past two minutes, and a wait you
  never chose reads as a hang, not thoroughness. The new screen states
  what a scan will cost before it starts: each volume shows a time
  estimate (a range, with what it's based on - a remembered item count
  after the first scan, or a rough estimate before that), and external
  drives are honestly labeled "Time unknown" rather than guessed. If you
  already have results this session, a strip at the top offers to jump
  straight back to them - starting a scan is always something you choose,
  never something that happens for you
  - Scanning a folder instead is front and center too, with one-click
    pills for your three most recently scanned folders (or Downloads,
    Desktop, and Documents before you've scanned anything)

### Removed
- **The direct "App Manager" tile and the "Reclaim Purgeable Space Now"
  button are gone from the disk picker.** App Manager is still one click
  away, from the sidebar, the moment any scan starts. Reclaiming purgeable
  space manually has no replacement right now - the sidebar and onboarding
  still explain what purgeable space is, they just don't offer to act on
  it anymore

### Fixed
- Navigating to Cleanup with a scan that had already finished (e.g. "View
  Results" from the disk picker, or "Review" from the menu bar after
  switching screens) could get stuck showing a permanent "still scanning"
  placeholder instead of the real findings
- **The "Give DustEater Full Disk Access" step could report access as
  granted when it hadn't actually been - it was checking whether a folder
  could be *listed*, and that folder turns out to be readable by any app
  regardless of Full Disk Access.** It now checks a location that
  genuinely requires the real permission

### Added
- **Menu bar monitoring**: an optional menu bar item keeps an eye on your
  disk without keeping the app open
  - Off by default. Turn it on from the Receipt screen's "Keep watching
    this disk" card, or from Settings → Monitoring
  - Shows a capacity gauge and free-space figure; click it for a dropdown
    with your volume's free/purgeable space, the top reclaimable findings,
    and one-click access to Review, Rescan, Pause Monitoring, and
    Monitoring Settings
  - Every 6 hours it re-checks package manager caches, downloads, and
    unused applications only - it never walks your whole disk in the
    background
  - Two optional notifications, both off until you turn them on and never
    more than once a day: free space dropping below a threshold (default
    10%), and rebuildable caches building back up (default 5 GB) - the
    second only ever counts caches, never your own files
- **Permission onboarding**: a three-step welcome screen before your first
  scan explains what DustEater does, asks for Full Disk Access (with the
  app noticing the moment you grant it - no relaunch needed), and explains
  why DustEater and Finder disagree about free space
  - Declining is safe and explicit: DustEater still scans and still
    reports real totals, it just tells you which locations it couldn't
    read
  - If a scan ran without Full Disk Access, Cleanup shows exactly which
    four locations were skipped and why, with a one-click way to grant
    access - the totals shown are never hedged, since everything measured
    is real
- **Browse by type in Explore**: Explore gains a Treemap · By Type toggle,
  By Type as the default
  - A type board ranks your files into eight categories by total size -
    Applications, Code & Projects, Videos, Photos, Audio, Documents,
    Archives & Installers, Other - each showing its own size and share of
    the disk. Applications doesn't drill in here; it opens App Manager,
    since that's where uninstalling actually happens
  - Opening a category shows every file in it, largest first, with Size and
    "Not opened in" filters - built for the actual question, "videos over
    500 MB I haven't opened in a year"
  - Clicking a file opens a preview pane with a real thumbnail, not a
    generic icon; the checkbox next to a row is what selects it, so
    browsing and selecting are separate gestures
  - This is your own content, so there's no ranking, no recommendation,
    and no "select all" anywhere on this screen. Files still managed by
    Photos are shown locked, with a note to delete them from the Photos
    app instead. Files stored in iCloud are badged with a warning that
    deleting them removes them from every device
  - Selecting a file here joins the same selection tray and Review screen
    Cleanup uses - there's no second delete path. Because this is your own
    content rather than junk the app is recommending, Review drops the
    permanent-delete option entirely once anything from Explore is
    selected, offering only the Trash
- **Streaming Cleanup scan**: findings now appear on screen while a scan is
  still running, instead of only after it finishes
  - The Scanning stage shows a live status card (items scanned, current
    path, a running "Found so far" total) plus each finding as it's
    discovered, with a Review Findings button that's enabled the whole
    time - jumping into Cleanup doesn't stop the scan, findings and the
    sidebar total keep updating live
  - Most findings (package manager caches, Xcode's fixed cache paths,
    simulator runtimes, unused applications, old downloads) no longer wait
    for the full scan to finish at all - only duplicate files and
    project-local build artifacts (`node_modules` etc.) genuinely need the
    complete picture, and stream in once it's ready
  - Cancel Scan keeps every finding already discovered - cancelling stops
    the scan, not the results
- **Cleanup**: The app now restructures around a scan -> ranked findings ->
  review -> receipt flow, replacing the old five-way sidebar (Disks &
  Folders, Overview, Duplicates & Large Files, Developer Kit, App Manager)
  with three destinations - Cleanup, Explore, Apps
  - Post-scan lands on a ranked Cleanup screen: six findings (package
    manager caches, applications unopened over a year, downloads older
    than 12 months, Xcode build artifacts, duplicate files, iOS Simulator
    runtimes), largest first, nothing pre-selected
  - App-wide selection spans every finding into one Review screen and a
    persistent selection tray showing the running total
  - Trash is the default destination everywhere, always; permanent
    deletion is a separate, explicitly worded opt-in
  - A real Undo - Put Back on the Receipt screen, backed by the Trash
    item's actual restore location (previously discarded)
  - The disk picker is skipped automatically when only one volume is
    eligible to scan
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
- **Duplicates & Large Files inspector and the Developer Kit screen**: both
  retired as standalone destinations now that Cleanup surfaces their data
  directly. This is a real capability reduction, not just a relocation -
  Smart Select's bulk duplicate-selection rules, the per-set duplicate
  image thumbnail grid, the large-files browser, and Developer Kit's
  Docker/Adobe/project-artifact/Final Cut/Logic category cards are gone.
  Xcode Archives' per-archive drill-in list survives, now opened from the
  Xcode build artifacts finding's footer action.
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
