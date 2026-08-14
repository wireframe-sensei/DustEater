import SwiftUI
import DustEaterCore

/// Screen root for the Developer & Creative Power-User Clean Up Kit. Reads
/// the already-scanned `FileNode` tree passed in from `MainContentView` -
/// runs no directory scan of its own and needs no additional permission
/// prompt, the same "reuse the scan" contract `DuplicatesView` uses.
///
/// Sizes, safety badges, toggles, and Reveal in Finder for browsing; a
/// batched purge with a confirmation sheet and per-item progress for
/// actually reclaiming space.
struct DeveloperKitView: View {
    let root: FileNode
    let onBackToHome: () -> Void
    let onBackToScan: () -> Void
    /// Notifies the caller which paths were actually deleted, so
    /// `ContentView` can fold them out of the live scan tree via
    /// `removingNode` + `coordinator.updateTree` without a rescan - the
    /// exact same contract `DuplicatesView.onDeleted` uses, reusing
    /// `ContentView.handleInspectorDeleted` on the other end.
    let onDeleted: (Set<String>) -> Void

    /// Both sheets this screen can present, unified behind one
    /// `.sheet(item:)`. `confirmPurge` carries its target list *inside the
    /// case itself* rather than through a separate `@State
    /// pendingDeleteTargets` read from the closure - the latter shape was
    /// tried first and is a real, confirmed SwiftUI trap: a `.sheet`
    /// content closure can read a stale value for a *sibling* `@State` var
    /// even when that var was set correctly, in the same synchronous
    /// action, one line before the item itself became non-nil. Verified by
    /// instrumenting both the toggle and the button action - the sibling
    /// state held the right value at the moment it was set, but the sheet's
    /// content closure still saw the array as empty. Putting the payload on
    /// the `item` itself removes the race entirely: SwiftUI hands the
    /// closure the exact value bound to `$activeSheet`, not a second,
    /// independently-tracked variable it has to catch up to.
    private enum ActiveSheet: Identifiable {
        case archives
        case confirmPurge(targets: [PurgeTarget])

        var id: String {
            switch self {
            case .archives: return "archives"
            case .confirmPurge: return "confirmPurge"
            }
        }
    }

    @State private var scanner = PurgeScanner()
    @State private var selection = PurgeSelection()
    // Listed independently of `scanner`/`PurgeScanState`: an archive never
    // becomes a `PurgeTarget` (see `ArchivesSummaryCardView`'s doc comment),
    // so it has no reason to share the main measure pipeline's state shape.
    @State private var archives: [XcodeArchive] = []
    @State private var activeSheet: ActiveSheet?

    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    @State private var deletionProgress: PurgeDeletionProgress?

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16)]

    @Environment(\.controlMetrics) private var metrics

    private var loadedCategories: [PurgeCategory]? {
        if case .loaded(let categories) = scanner.state { return categories }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Developer Kit")
        .toolbar { toolbarContent }
        .task { scanner.measure(in: root) }
        .task { archives = await XcodeArchiveLister.listArchives(in: root) }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .archives:
                XcodeArchivesListView(archives: $archives, onDeleted: { path in onDeleted([path]) })
            case .confirmPurge(let targets):
                PurgeConfirmationSheet(
                    targets: targets,
                    totalBytesToReclaim: targets.reduce(Int64(0)) { $0 + $1.sizeBytes },
                    deletionProgress: deletionProgress,
                    isDeleting: $isDeleting,
                    errorMessage: $deleteErrorMessage,
                    onConfirm: { permanently in performPurge(targets, permanently: permanently) }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer & Creative Clean Up Kit")
                    .font(DustEaterTheme.Typography.headline)
                if let loadedCategories {
                    let reclaimable = loadedCategories.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
                    Text("\(ByteFormatter.string(fromBytes: reclaimable)) reclaimable across \(loadedCategories.count) categories")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selection.count > 0, let loadedCategories {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(selection.count) selected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.string(fromBytes: selection.reclaimableBytes(across: loadedCategories)))
                            .font(.control)
                            .foregroundStyle(.primary)
                    }

                    Button {
                        activeSheet = .confirmPurge(targets: selectedTargets(in: loadedCategories))
                    } label: {
                        Label("Purge Selected", systemImage: "trash")
                    }
                    .font(.control)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .glassBackground(.regularMaterial, cornerRadius: metrics.cornerRadius)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch scanner.state {
        case .idle:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .scanning(let measured, let progress):
            if measured.isEmpty {
                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    ProgressView()
                    Text(phaseLabel(progress.phase))
                        .foregroundStyle(.secondary)
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid(for: PurgeCategory.grouped(measured))
            }

        case .loaded(let categories) where categories.isEmpty:
            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Nothing Found")
                    .font(DustEaterTheme.Typography.headline)
                Text("No known developer or creative-app caches were found in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .loaded(let categories):
            grid(for: categories)

        case .failed(let message):
            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Couldn't Measure Caches")
                    .font(DustEaterTheme.Typography.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { scanner.measure(in: root) }
                    .font(.control)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, DustEaterTheme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // A `DisclosureGroup` per card was rejected here: a disclosure inside a
    // fixed-height card inside a `LazyVGrid` reflows the whole grid on every
    // expand, and this stays a flat grid of per-target cards under a plain
    // section header instead, per CLAUDE.md's "Flat and Direct."
    private func grid(for categories: [PurgeCategory]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !archives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(Color.accentColor)
                            Text("Xcode Archives")
                                .font(DustEaterTheme.Typography.headline)
                            Spacer()
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ArchivesSummaryCardView(
                                archiveCount: archives.count,
                                totalBytes: archives.reduce(0) { $0 + $1.sizeBytes },
                                onBrowse: { activeSheet = .archives }
                            )
                        }
                    }
                }

                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: category.systemImage)
                                .foregroundStyle(Color.accentColor)
                            Text(category.title)
                                .font(DustEaterTheme.Typography.headline)
                            Spacer()
                            Text("\(ByteFormatter.string(fromBytes: category.reclaimableBytes)) reclaimable of \(ByteFormatter.string(fromBytes: category.totalBytes)) found")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        // Cards measuring 0 bytes (e.g. an empty simulator
                        // cache) carry no useful information, so they're
                        // filtered here rather than rendered as a blank tile.
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(category.targets.filter { $0.sizeBytes > 0 }) { target in
                                TargetCardView(
                                    target: target,
                                    isSelected: selection.isSelected(target),
                                    onToggle: { selection.toggle(target) }
                                )
                            }
                        }
                    }
                }
            }
            .controlSize(.large)
            .padding(20)
        }
    }

    private func phaseLabel(_ phase: PurgeScanProgress.Phase) -> String {
        switch phase {
        case .discoveringProjects: return "Finding project build artifacts..."
        case .resolvingFromTree: return "Reading sizes from this scan..."
        case .measuring: return "Measuring caches outside this scan..."
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

        ToolbarItem(placement: .primaryAction) {
            selectMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                scanner.measure(in: root)
            } label: {
                Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Re-measure every target against this scan")
        }
    }

    @ViewBuilder
    private var selectMenu: some View {
        Menu {
            Button("Select Safe") {
                if let loadedCategories { selection.selectAll(upTo: .safe, in: loadedCategories) }
            }
            Button("Select Safe and Rebuildable") {
                if let loadedCategories { selection.selectAll(upTo: .rebuildable, in: loadedCategories) }
            }
            Divider()
            Button("Deselect All") {
                selection.deselectAll()
            }
        } label: {
            Label("Select", systemImage: "checklist")
        }
        .disabled(loadedCategories?.isEmpty ?? true)
        .help("Bulk-select targets by safety level. Caution-level targets are never bulk-selected.")
    }

    private func selectedTargets(in categories: [PurgeCategory]) -> [PurgeTarget] {
        categories.flatMap(\.targets).filter { selection.isSelected($0) }
    }

    // MARK: - Purge

    /// Mirrors `DuplicatesView.performDelete`: a plain (non-`@MainActor`)
    /// `Task`, so the loop - including `FileOperations.delete`, which for a
    /// large `DerivedData` can run for real wall-clock seconds - runs off
    /// the main actor and never freezes the window. Each iteration hops
    /// back via `MainActor.run` only to report progress and, at the end, to
    /// reconcile state.
    private func performPurge(_ targets: [PurgeTarget], permanently: Bool) {
        isDeleting = true
        deleteErrorMessage = nil
        let snapshot = targets
        let total = snapshot.count

        Task {
            var deletedPaths: Set<String> = []
            var errors: [String] = []

            for (index, target) in snapshot.enumerated() {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    deletionProgress = PurgeDeletionProgress(completed: index, total: total, currentTitle: target.definition.title)
                }

                // TOCTOU guard, same as `DuplicatesView.performDelete`: the
                // filesystem can change in the window between measuring and
                // this confirmation.
                guard FileManager.default.fileExists(atPath: target.path) else {
                    errors.append("\(target.definition.title): no longer exists, skipped")
                    continue
                }
                // Belt and braces - `PurgeSelection.toggle` already refuses
                // `.reportOnly` targets, so this should never actually fire.
                guard target.safety != .reportOnly else {
                    errors.append("\(target.definition.title): not deletable, skipped")
                    continue
                }
                guard !PurgeCatalog.isDenied(path: target.path) else {
                    errors.append("\(target.definition.title): protected, skipped")
                    continue
                }
                guard FileOperations.canDelete(at: target.path) else {
                    errors.append("\(target.definition.title): protected, skipped")
                    continue
                }
                if let bundleID = target.definition.blockingAppBundleID, FileOperations.isAppRunning(bundleIdentifier: bundleID) {
                    errors.append("\(target.definition.title): the owning app is running, skipped")
                    continue
                }

                do {
                    try FileOperations.delete(at: target.path, permanently: permanently)
                    deletedPaths.insert(target.path)
                } catch {
                    errors.append("\(target.definition.title): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isDeleting = false
                deletionProgress = nil

                if !deletedPaths.isEmpty {
                    scanner.removeDeletedPaths(deletedPaths)
                    selection.removePaths(deletedPaths)
                    onDeleted(deletedPaths)
                }

                if errors.isEmpty {
                    activeSheet = nil
                } else {
                    // Sheet stays open with Cancel still enabled, so a
                    // partial failure is inspectable rather than silently
                    // dismissed - matching `DuplicatesView.performDelete`.
                    deleteErrorMessage = errors.joined(separator: "\n")
                }
            }
        }
    }
}
