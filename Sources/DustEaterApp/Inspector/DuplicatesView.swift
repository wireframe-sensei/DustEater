import SwiftUI
import DustEaterCore

/// Duplicate size floor presets exposed in the Filters menu. 1 MB is the
/// default per the module's design decision - well below it dominates file
/// *count* on a typical disk but almost none of its space.
private enum DuplicateSizePreset: Int64, CaseIterable, Identifiable {
    case oneHundredKB = 102_400
    case oneMB = 1_048_576
    case tenMB = 10_485_760
    case oneHundredMB = 104_857_600

    var id: Int64 { rawValue }
    var label: String { "\(ByteFormatter.string(fromBytes: rawValue)) or larger" }
}

/// Large-file threshold presets, matching the brief's ">100 MB, >1 GB,
/// >5 GB" examples.
private enum LargeFileThresholdPreset: Int64, CaseIterable, Identifiable {
    case oneHundredMB = 104_857_600
    case fiveHundredMB = 524_288_000
    case oneGB = 1_073_741_824
    case fiveGB = 5_368_709_120

    var id: Int64 { rawValue }
    var label: String { "\(ByteFormatter.string(fromBytes: rawValue)) or larger" }
}

/// "Not opened since" presets - backed by `LargeFileEntry.lastUsedDate`
/// (Spotlight `kMDItemLastUsedDate`, not raw `st_atime`; see that type's
/// doc comment).
private enum IdlePreset: CaseIterable, Identifiable {
    case any, sixMonths, oneYear

    var id: Self { self }

    var label: String {
        switch self {
        case .any: return "Any"
        case .sixMonths: return "Not opened in 6 months"
        case .oneYear: return "Not opened in 1 year"
        }
    }

    func cutoffDate(from now: Date = Date()) -> Date? {
        switch self {
        case .any: return nil
        case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: now)
        case .oneYear: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        }
    }
}

/// Screen root for the duplicate and large-file inspectors. Reads the
/// already-scanned `FileNode` tree passed in from `MainContentView` - runs
/// no directory scan of its own and needs no additional permission prompt.
struct DuplicatesView: View {
    private enum Mode: String, CaseIterable {
        case duplicates = "Duplicates"
        case largeFiles = "Large Files"
    }

    let root: FileNode
    let onBackToHome: () -> Void
    let onBackToScan: () -> Void
    /// Notifies the caller which paths were actually deleted, so
    /// `ContentView` can fold them out of the live scan tree via
    /// `removingNode` + `coordinator.updateTree` without a rescan. This
    /// view's own `root` is a snapshot taken when it opened and is *not*
    /// live-updated after a delete - the same "detected, not reconciled
    /// live" trade-off `FileSystemWatcher` already documents elsewhere in
    /// this codebase. A stale root is harmless here: re-analyzing simply
    /// fails to `lstat` the now-missing paths and they drop out on their
    /// own, the same as any file removed externally mid-scan.
    let onDeleted: (Set<String>) -> Void

    @State private var service = FileInspectorService()
    @State private var mode: Mode = .duplicates

    @State private var duplicateSelection = DuplicateSelectionState()
    @State private var largeFileSelectedPaths: Set<String> = []
    @State private var detailFocus: InspectorDetailFocus = .none
    /// Drive the sidebar `List`s' native `selection:` binding - full-row
    /// hit target, native highlight, hover state, and keyboard up/down
    /// navigation all come for free this way, unlike the manual
    /// `.onTapGesture` + hand-drawn background the row views used before.
    /// Kept as two separate optionals (one per tab) rather than folding
    /// into `detailFocus` directly, since `List(selection:)` needs a
    /// binding whose type matches that specific list's row id - each
    /// `.onChange` below is what keeps `detailFocus` (which the detail
    /// pane actually reads) in sync with whichever list is active.
    @State private var selectedDuplicateSetID: String?
    @State private var selectedLargeFilePath: String?
    @State private var showPreview = true

    @State private var showConfirmSheet = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    /// The exact files the open confirmation sheet will act on - set
    /// explicitly by whichever "Review & Clean" was clicked, rather than
    /// always recomputed from the full tab selection. Two different
    /// buttons write to this: the floating action bar's (the whole tab's
    /// selection, across every set) and each overview's scoped one (just
    /// that set's or file's selection) - see `DuplicateSetOverview`'s
    /// `onReviewAndClean` and the large-files facts panel below. Without
    /// this, "Review & Clean" from inside one set's overview would
    /// silently include selections left over in other sets the user isn't
    /// even looking at, which is exactly the confusing behavior this
    /// exists to avoid.
    @State private var pendingDeleteFiles: [InspectedFile] = []

    @State private var duplicateMinimumSize: Int64 = 1 << 20
    @State private var largeFileThreshold: Int64 = 100 * 1024 * 1024
    @State private var idlePreset: IdlePreset = .any
    /// Off by default: files inside `node_modules`, `.git`, package-manager
    /// caches, and build output (see `DeveloperArtifactFolders`) are
    /// hidden from both lists. The scan itself always examines these
    /// directories - `runFullAnalysis` hardcodes
    /// `includeDeveloperArtifacts: true` at the Core level regardless of
    /// this toggle - so this only filters what `duplicateSets` /
    /// `largeFileEntries` display. That's a deliberate choice over
    /// excluding at scan time: it makes toggling instant (no re-scan
    /// needed), at the cost of every scan paying to hash
    /// `node_modules`/`.git` trees whether or not they end up visible. The
    /// same package installed identically across a dozen projects is the
    /// single biggest source of noisy, low-value duplicate reports, and a
    /// duplicate found inside a project-local `node_modules` isn't safe to
    /// delete piecemeal anyway - this toggle only changes what's visible,
    /// it doesn't make anything safer to select.
    @State private var includeDeveloperArtifacts = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                sidebarContent
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 500)
        } detail: {
            VStack(spacing: 0) {
                if showPreview {
                    detailPaneContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: DustEaterTheme.Spacing.sm) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("Preview hidden")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if currentSelectionCount > 0 {
                    DuplicateActionBar(
                        selectedCount: currentSelectionCount,
                        reclaimableBytes: currentReclaimableBytes,
                        onClear: clearCurrentSelection,
                        onReviewAndClean: {
                            pendingDeleteFiles = currentSelectedFiles
                            showConfirmSheet = true
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentSelectionCount > 0)
            .navigationTitle("Duplicates & Large Files")
            .toolbar { toolbarContent }
        }
        // Switching tabs makes a `.set(...)` focus meaningless (large files
        // aren't duplicate sets) and a stale `.file(...)` focus confusing
        // (it'd keep showing a duplicate's preview while browsing large
        // files), so each tab starts its detail pane fresh - including
        // clearing both `List` selections, or returning to a tab would
        // silently resurrect whatever was selected there last time.
        .onChange(of: mode) { _, _ in
            detailFocus = .none
            selectedDuplicateSetID = nil
            selectedLargeFilePath = nil
        }
        // The two sidebar `List`s each own their native selection
        // (`selectedDuplicateSetID` / `selectedLargeFilePath`); these keep
        // `detailFocus` - what the detail pane actually reads - in sync
        // with whichever one is currently active. Deselecting (clicking
        // empty space, or `List` clearing selection on data reload) sends
        // `nil`, which correctly falls through to `.none`.
        .onChange(of: selectedDuplicateSetID) { _, newValue in
            detailFocus = newValue.map { .set($0) } ?? .none
        }
        .onChange(of: selectedLargeFilePath) { _, newValue in
            detailFocus = newValue.map { .file($0) } ?? .none
        }
        // Changing a filter is already the user's explicit request for
        // different results - re-running immediately means the Filters
        // menu behaves like a live filter, not a setting that silently
        // does nothing until a separate "Run Again" click. Each of these
        // is a plain value type change, so `.onChange` fires once per
        // click; rapid clicks through several presets in a row are safe
        // since `FileInspectorService.findDuplicates`/`findLargeFiles`
        // each cancel their own prior task before starting the next one.
        .onChange(of: duplicateMinimumSize) { _, _ in runFullAnalysis() }
        .onChange(of: largeFileThreshold) { _, _ in runFullAnalysis() }
        .onChange(of: idlePreset) { _, _ in runFullAnalysis() }
        // Deliberately no `.onChange(of: includeDeveloperArtifacts)` - see
        // that property's doc comment. The scan already always examines
        // these directories, so toggling only needs to re-filter
        // `duplicateSets`/`largeFileEntries`, which happens for free on
        // the next body evaluation since they're computed properties.
        // Clicking "Find Duplicates" in the toolbar is already the user's
        // explicit request to analyze this scan - making them click
        // "Analyze" again on the very next screen is pure redundant
        // friction, not a meaningful confirmation step. `.task` fires once
        // per view identity, so this doesn't refire on every body
        // re-evaluation, and it doesn't fight Cancel: `cancelDuplicateScan`/
        // `cancelLargeFileScan` reset state back to `.idle`, but that's a
        // state change `.task` has no reason to react to - the idle card
        // (with its manual "Analyze" button) still resurfaces correctly
        // after a cancel, exactly as it did before, since this only ever
        // runs once on first appearance.
        .task { runFullAnalysis() }
        .sheet(isPresented: $showConfirmSheet) {
            DuplicateCleanConfirmationSheet(
                filesToDelete: pendingDeleteFiles,
                totalBytesToReclaim: pendingDeleteFiles.reduce(Int64(0)) { $0 + $1.logicalSize },
                fullyDeletedFileNames: fullyDeletedFileNames(among: pendingDeleteFiles),
                isDeleting: $isDeleting,
                errorMessage: $deleteErrorMessage,
                onConfirm: performDelete
            )
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        switch mode {
        case .duplicates:
            duplicatesSidebar
        case .largeFiles:
            largeFilesSidebar
        }
    }

    @ViewBuilder
    private var duplicatesSidebar: some View {
        switch service.duplicateState {
        case .idle:
            InspectorStateCard(
                systemImage: "doc.on.doc",
                title: "Ready to Analyze",
                message: "Finds byte-identical duplicates (at or above \(ByteFormatter.string(fromBytes: duplicateMinimumSize))) and large files together, in one pass.\(includeDeveloperArtifacts ? "" : " Developer tool folders (node_modules, .git, caches) are hidden - see Filters.")",
                primaryActionTitle: "Analyze",
                primaryAction: runFullAnalysis
            )
        case .scanning(let progress):
            DuplicateScanProgressCard(progress: progress, onCancel: { service.cancelDuplicateScan() })
        case .loaded where duplicateSets.isEmpty:
            InspectorStateCard(
                systemImage: "checkmark.circle",
                title: "No Duplicates Found",
                message: "No duplicate files at or above \(ByteFormatter.string(fromBytes: duplicateMinimumSize)) were found.",
                primaryActionTitle: "Run Again",
                primaryAction: runFullAnalysis
            )
        case .loaded:
            List(duplicateSets, selection: $selectedDuplicateSetID) { set in
                DuplicateSetRow(duplicateSet: set, selection: duplicateSelection)
            }
            .listStyle(.plain)
        case .failed(let message):
            InspectorStateCard(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't Scan for Duplicates",
                message: message,
                primaryActionTitle: "Retry",
                primaryAction: runFullAnalysis
            )
        }
    }

    @ViewBuilder
    private var largeFilesSidebar: some View {
        switch service.largeFileState {
        case .idle:
            InspectorStateCard(
                systemImage: "doc.badge.gearshape",
                title: "Ready to Analyze",
                message: "Finds large files (at or above \(ByteFormatter.string(fromBytes: largeFileThreshold))\(idlePreset == .any ? "" : ", \(idlePreset.label.lowercased())")) and duplicates together, in one pass.",
                primaryActionTitle: "Analyze",
                primaryAction: runFullAnalysis
            )
        case .scanning:
            LargeFileScanProgressCard(onCancel: { service.cancelLargeFileScan() })
        case .loaded where largeFileEntries.isEmpty:
            InspectorStateCard(
                systemImage: "checkmark.circle",
                title: "No Large Files Found",
                message: "No files matched the current threshold and filters.",
                primaryActionTitle: "Run Again",
                primaryAction: runFullAnalysis
            )
        case .loaded:
            List(largeFileEntries, selection: $selectedLargeFilePath) { entry in
                LargeFileRow(entry: entry, isSelected: largeFileSelectedPaths.contains(entry.file.path))
            }
            .listStyle(.plain)
        case .failed(let message):
            InspectorStateCard(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't Scan for Large Files",
                message: message,
                primaryActionTitle: "Retry",
                primaryAction: runFullAnalysis
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onBackToScan) {
                Label("Back to Scan", systemImage: "chevron.backward")
            }
            .help("Back to the treemap")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: onBackToHome) {
                Label("Home", systemImage: "house")
            }
            .help("Back to home screen")
        }

        if mode == .duplicates {
            ToolbarItem(placement: .primaryAction) {
                SmartSelectMenu(
                    isEnabled: !duplicateSets.isEmpty,
                    onApply: { rule in
                        duplicateSelection.apply(rule, to: duplicateSets, downloadsPaths: FileInspectorService.defaultDownloadsPaths())
                    },
                    onClear: { duplicateSelection.clear() }
                )
            }
        }

        ToolbarItem(placement: .primaryAction) {
            filtersMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showPreview) {
                Label("Preview", systemImage: "eye")
            }
            .help("Show or hide the Quick Look preview pane")
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: runFullAnalysis) {
                Label("Run Again", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Re-analyze this scan for both duplicates and large files")
        }
    }

    @ViewBuilder
    private var filtersMenu: some View {
        Menu {
            Section("Duplicate Minimum Size") {
                ForEach(DuplicateSizePreset.allCases) { preset in
                    Button {
                        duplicateMinimumSize = preset.rawValue
                    } label: {
                        if duplicateMinimumSize == preset.rawValue {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            }

            Section("Large File Threshold") {
                ForEach(LargeFileThresholdPreset.allCases) { preset in
                    Button {
                        largeFileThreshold = preset.rawValue
                    } label: {
                        if largeFileThreshold == preset.rawValue {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            }

            Section("Not Opened Since") {
                ForEach(IdlePreset.allCases) { preset in
                    Button {
                        idlePreset = preset
                    } label: {
                        if idlePreset == preset {
                            Label(preset.label, systemImage: "checkmark")
                        } else {
                            Text(preset.label)
                        }
                    }
                }
            }

            Divider()

            Button {
                includeDeveloperArtifacts.toggle()
            } label: {
                if includeDeveloperArtifacts {
                    Label("Show Developer Tool Folders", systemImage: "checkmark")
                } else {
                    Text("Show Developer Tool Folders")
                }
            }
            .help("node_modules, .git, package-manager caches, and build output are hidden by default - toggling this is instant and doesn't make them any safer to delete")
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Adjust size and age thresholds - re-analyzes automatically")
    }

    // MARK: - Detail pane

    /// Routes `detailFocus` to the right detail-pane content: a single
    /// file's Quick Look preview, a duplicate group's side-by-side facts
    /// comparison, or (for large files specifically) Quick Look plus a full
    /// facts card underneath.
    @ViewBuilder
    private var detailPaneContent: some View {
        switch detailFocus {
        case .none:
            QuickLookPreviewPane(path: nil, onRunAgain: runFullAnalysis)

        case .file(let path):
            if mode == .largeFiles, let entry = largeFileEntry(for: path) {
                VStack(spacing: 0) {
                    QuickLookPreviewPane(path: path, onRunAgain: runFullAnalysis)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.sm) {
                            FileFactsCard(
                                file: entry.file,
                                lastUsedDate: entry.lastUsedDate,
                                isSelected: largeFileSelectedPaths.contains(path),
                                onToggle: { toggleLargeFileSelection(path) }
                            )

                            // Scoped to just this one file, distinct from
                            // the floating action bar's whole-tab "Review &
                            // Clean" - only shows once this file is
                            // actually selected, so it's never a no-op
                            // click.
                            if largeFileSelectedPaths.contains(path) {
                                Button {
                                    pendingDeleteFiles = [entry.file]
                                    showConfirmSheet = true
                                } label: {
                                    Label("Review & Delete This File", systemImage: "trash")
                                }
                                .font(.control)
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                        .padding(DustEaterTheme.Spacing.md)
                    }
                    .frame(height: 140)
                }
            } else {
                QuickLookPreviewPane(path: path, onRunAgain: runFullAnalysis)
            }

        case .set(let setID):
            // The set may no longer exist (e.g. Run Again re-scanned, or a
            // delete collapsed it below 2 files) - fall back to the empty
            // preview state rather than showing stale content.
            if let set = duplicateSets.first(where: { $0.id == setID }) {
                DuplicateSetOverview(
                    duplicateSet: set,
                    selection: $duplicateSelection,
                    onReviewAndClean: { selectedFiles in
                        pendingDeleteFiles = selectedFiles
                        showConfirmSheet = true
                    }
                )
            } else {
                QuickLookPreviewPane(path: nil, onRunAgain: runFullAnalysis)
            }
        }
    }

    private func largeFileEntry(for path: String) -> LargeFileEntry? {
        largeFileEntries.first { $0.file.path == path }
    }

    private func toggleLargeFileSelection(_ path: String) {
        if largeFileSelectedPaths.contains(path) {
            largeFileSelectedPaths.remove(path)
        } else {
            largeFileSelectedPaths.insert(path)
        }
    }

    // MARK: - Mode-derived state

    /// Duplicate sets currently visible, honoring "Show Developer Tool
    /// Folders". The scan itself always runs with
    /// `includeDeveloperArtifacts: true` (`runFullAnalysis`) - filtering
    /// here, at display time, is what makes the toggle instant instead of
    /// needing a re-scan. When the toggle is off, files inside a
    /// developer-artifact directory are removed from each set, and the set
    /// itself drops out entirely once fewer than 2 files remain -
    /// mirroring exactly what excluding them at scan time used to do.
    private var duplicateSets: [DuplicateSet] {
        guard case .loaded(let sets) = service.duplicateState else { return [] }
        guard !includeDeveloperArtifacts else { return sets }
        return sets.compactMap { set in
            let visibleFiles = set.files.filter { !DeveloperArtifactFolders.pathContainsDeveloperArtifact($0.path) }
            guard visibleFiles.count > 1 else { return nil }
            return DuplicateSet(contentHash: set.contentHash, files: visibleFiles)
        }
    }

    /// Large-file entries currently visible, honoring "Show Developer Tool
    /// Folders" - same reasoning as `duplicateSets` above.
    private var largeFileEntries: [LargeFileEntry] {
        guard case .loaded(let entries) = service.largeFileState else { return [] }
        guard !includeDeveloperArtifacts else { return entries }
        return entries.filter { !DeveloperArtifactFolders.pathContainsDeveloperArtifact($0.file.path) }
    }

    private var currentSelectionCount: Int {
        switch mode {
        case .duplicates: return duplicateSelection.count
        case .largeFiles: return largeFileSelectedPaths.count
        }
    }

    private var currentReclaimableBytes: Int64 {
        switch mode {
        case .duplicates:
            return duplicateSelection.reclaimableBytes(across: duplicateSets)
        case .largeFiles:
            return largeFileEntries
                .filter { largeFileSelectedPaths.contains($0.file.path) }
                .reduce(Int64(0)) { $0 + $1.file.logicalSize }
        }
    }

    private var currentSelectedFiles: [InspectedFile] {
        switch mode {
        case .duplicates:
            return duplicateSets.flatMap(\.files).filter { duplicateSelection.isSelected($0.path) }
        case .largeFiles:
            return largeFileEntries.map(\.file).filter { largeFileSelectedPaths.contains($0.path) }
        }
    }

    /// Names of files where *every* copy is present in `files` - i.e.
    /// deleting `files` would leave zero copies of that file anywhere, not
    /// just reclaim duplicate storage. Takes the pending delete list rather
    /// than reading the full tab selection directly, so it gives the right
    /// answer for both the whole-tab "Review & Clean" and a single set's
    /// scoped one. Empty in Large Files mode, where there's no such thing
    /// as "every copy" to begin with. Surfaced in the confirmation sheet as
    /// an explicit warning, since this is a meaningfully more consequential
    /// outcome than the usual duplicate cleanup and deserves to be called
    /// out before the delete happens, not discovered after.
    private func fullyDeletedFileNames(among files: [InspectedFile]) -> [String] {
        guard mode == .duplicates else { return [] }
        let pendingPaths = Set(files.map(\.path))
        return duplicateSets
            .filter { set in !set.files.isEmpty && set.files.allSatisfy { pendingPaths.contains($0.path) } }
            .compactMap { $0.files.first?.name }
    }

    private func clearCurrentSelection() {
        switch mode {
        case .duplicates: duplicateSelection.clear()
        case .largeFiles: largeFileSelectedPaths.removeAll()
        }
    }

    /// Runs both scans together - `DuplicateDetector` and `LargeFileFinder`
    /// are already independent `Task`s inside `FileInspectorService`, each
    /// with its own internal concurrency cap, so there's no resource
    /// contention from starting them side by side instead of one after the
    /// other. One "Analyze" (or "Run Again") click populates both tabs, so
    /// switching between Duplicates and Large Files never requires a
    /// second, separate scan.
    ///
    /// Always passes `includeDeveloperArtifacts: true` to Core, regardless
    /// of the `includeDeveloperArtifacts` display toggle - this deliberately
    /// makes every scan examine `node_modules`/`.git`/etc. so the toggle
    /// can filter `duplicateSets`/`largeFileEntries` instantly rather than
    /// needing to re-run this. The cost is that scans always pay to hash
    /// those directories even when the toggle is off and they end up
    /// hidden - a conscious tradeoff favoring instant toggling over faster
    /// default scans.
    private func runFullAnalysis() {
        service.findDuplicates(
            in: root,
            options: DuplicateScanOptions(minimumFileSize: duplicateMinimumSize, includeDeveloperArtifacts: true)
        )
        service.findLargeFiles(
            in: root,
            filter: LargeFileFilter(
                minimumSize: largeFileThreshold,
                notOpenedSince: idlePreset.cutoffDate(),
                includeDeveloperArtifacts: true
            )
        )
    }

    // MARK: - Delete

    private func performDelete(permanently: Bool) {
        isDeleting = true
        deleteErrorMessage = nil
        let filesSnapshot = pendingDeleteFiles

        Task {
            var deletedPaths: Set<String> = []
            var errors: [String] = []

            for file in filesSnapshot {
                // TOCTOU guard: the filesystem can change in the window
                // between analysis and this confirmation, so re-check the
                // file is still there before acting on it rather than
                // trusting the snapshot blindly.
                guard FileManager.default.fileExists(atPath: file.path) else {
                    errors.append("\(file.name): no longer exists, skipped")
                    continue
                }
                guard FileOperations.canDelete(at: file.path) else {
                    errors.append("\(file.name): protected, skipped")
                    continue
                }
                do {
                    try FileOperations.delete(at: file.path, permanently: permanently)
                    deletedPaths.insert(file.path)
                } catch {
                    errors.append("\(file.name): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isDeleting = false

                if !deletedPaths.isEmpty {
                    service.removeDeletedPaths(deletedPaths)
                    duplicateSelection.removePaths(deletedPaths)
                    largeFileSelectedPaths.subtract(deletedPaths)
                    onDeleted(deletedPaths)
                }

                if errors.isEmpty {
                    showConfirmSheet = false
                } else {
                    // Sheet stays open with Cancel still enabled, so a
                    // partial failure is inspectable rather than silently
                    // dismissed - matching `AppDetailInspector`'s
                    // `proceedWithUninstall`.
                    deleteErrorMessage = errors.joined(separator: "\n")
                }
            }
        }
    }
}

// MARK: - Shared state cards

/// Generic full-pane state card for the inspector's idle/empty/failed
/// states - icon, title, message, one action. Named distinctly from
/// `ContentView.swift`'s `ScanningStateView` to avoid a same-module name
/// collision; this is a different, simpler component with no determinate
/// progress ring.
private struct InspectorStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(DustEaterTheme.Typography.headline)
            Text(message)
                .font(DustEaterTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button(primaryActionTitle, action: primaryAction)
                .font(.control)
                .buttonStyle(.borderedProminent)
                .padding(.top, DustEaterTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct DuplicateScanProgressCard: View {
    let progress: DuplicateScanProgress
    let onCancel: () -> Void

    private var phaseLabel: String {
        switch progress.phase {
        case .collecting: return "Collecting candidates..."
        case .quickHashing: return "Comparing files..."
        case .fullHashing: return "Verifying matches..."
        }
    }

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.sm) {
            ProgressView()
            Text(phaseLabel)
                .font(DustEaterTheme.Typography.headline)
            if progress.totalFiles > 0 {
                Text("\(progress.filesProcessed) of \(progress.totalFiles) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(progress.currentPath)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 280)

            Button("Cancel", action: onCancel)
                .font(.control)
                .buttonStyle(.bordered)
                .padding(.top, DustEaterTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct LargeFileScanProgressCard: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.sm) {
            ProgressView()
            Text("Scanning for large files...")
                .foregroundStyle(.secondary)
            Button("Cancel", action: onCancel)
                .font(.control)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
