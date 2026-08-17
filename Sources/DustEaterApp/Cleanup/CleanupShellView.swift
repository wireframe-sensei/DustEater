import SwiftUI
import AppKit
import DustEaterCore

/// The persistent post-scan shell: a disk-context block plus a three-item
/// sidebar (Cleanup / Explore / Apps) around whichever destination is
/// active. Replaces the old `MainContentView`, which only ever showed the
/// treemap - that content now lives here as the `.explore` destination,
/// alongside the new Cleanup -> Review -> Receipt flow. Cleanup is the
/// default landing destination, per the design handoff.
struct CleanupShellView: View {
    enum Destination: Hashable { case cleanup, explore, apps }
    enum CleanupStage { case findings, review, receipt }

    struct ReceiptData: Identifiable {
        let id = UUID()
        let reclaimedBytes: Int64
        let freeBefore: Int64
        let freeAfter: Int64
        let permanently: Bool
        var trashedItems: [TrashedItem]
        var canUndo: Bool { !permanently && !trashedItems.isEmpty }
    }

    let root: FileNode
    let coordinator: ScanCoordinator
    let treemapRects: (CGSize) -> [TreemapRect]
    let treemapCache: TreemapCache
    @Binding var selectedTheme: ColorTheme
    let onBackToHome: () -> Void
    let onScanFolder: () -> Void
    let onRescan: () -> Void

    @State private var destination: Destination = .cleanup
    @State private var cleanupStage: CleanupStage = .findings

    // Cleanup
    @State private var cleanupScanner = CleanupScanner()
    @State private var selection = SelectionStore()
    // Package manager caches expanded on first run, per the design's State table.
    @State private var expandedFindings: Set<CleanupFindingID> = [.packageManagerCaches]
    @State private var scrollToFindingID: CleanupFindingID?
    @State private var xcodeArchives: [XcodeArchive] = []
    @State private var showXcodeArchives = false
    @State private var isCommitting = false
    @State private var commitErrorMessage: String?
    @State private var receipt: ReceiptData?

    // Disk context block
    @State private var diskCapacity: (total: Int64, available: Int64) = (0, 0)
    @State private var purgeableBytes: Int64 = 0

    // Explore - moved here from the old `MainContentView`, unchanged.
    @State private var selectedPath: String?
    @State private var expandedPaths: Set<String> = []
    @State private var showDeleteAlert = false
    @State private var itemToDelete: FileNode?
    @State private var deleteErrorMessage: String?
    @State private var backStack: [FileNode?] = []
    @State private var forwardStack: [FileNode?] = []

    private var selectedNode: FileNode? {
        guard let selectedPath else { return nil }
        return root.node(atPath: selectedPath)
    }

    private var findings: [CleanupFinding] {
        switch cleanupScanner.state {
        case .scanning(let measured): measured
        case .loaded(let loaded): loaded
        default: []
        }
    }

    private var totalReclaimable: Int64 {
        findings.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch destination {
                case .cleanup: cleanupDetail
                case .explore: exploreDetail
                case .apps: AppManagerView(onBackToHome: onBackToHome)
                }
            }
        }
        .task {
            cleanupScanner.scan(root: root)
            loadDiskContext()
        }
        .task {
            xcodeArchives = await XcodeArchiveLister.listArchives(in: root)
        }
        .sheet(isPresented: $showXcodeArchives) {
            XcodeArchivesListView(archives: $xcodeArchives, onDeleted: { path in handleItemDeleted(path) })
        }
        .alert("Delete Item", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let node = itemToDelete { deleteItem(node, permanently: false) }
            }
            Button("Delete Permanently", role: .destructive) {
                if let node = itemToDelete { deleteItem(node, permanently: true) }
            }
        } message: {
            if let itemToDelete {
                Text("Are you sure you want to delete \"\(itemToDelete.name)\"?")
            }
        }
        .alert("Couldn't Delete Item", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in if !isPresented { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert("Some Items Couldn't Be Deleted", isPresented: Binding(
            get: { commitErrorMessage != nil },
            set: { isPresented in if !isPresented { commitErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(commitErrorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            diskContextBlock
            Divider()
            navRows
            Divider()
            contextualSection
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .navigationSplitViewColumnWidth(min: 240, ideal: 246, max: 320)
    }

    private var diskContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.secondary)
                Text(root.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.progressTrack)
                GeometryReader { geometry in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * usageFraction)
                }
            }
            .frame(height: 5)

            if diskCapacity.total > 0 {
                Text("\(ByteFormatter.string(fromBytes: diskCapacity.available)) free of \(ByteFormatter.string(fromBytes: diskCapacity.total))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Required, not decorative - see the design handoff: without this
            // line, users conclude the app's numbers are wrong when they
            // don't match Finder's.
            if purgeableBytes > 0 {
                Text("\(ByteFormatter.string(fromBytes: purgeableBytes)) is purgeable - macOS releases it on demand, so Finder and DustEater may disagree.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var usageFraction: Double {
        guard diskCapacity.total > 0 else { return 0 }
        return Double(diskCapacity.total - diskCapacity.available) / Double(diskCapacity.total)
    }

    private var navRows: some View {
        VStack(spacing: 2) {
            navRow(.cleanup, label: "Cleanup", systemImage: "sparkles", trailing: totalReclaimable > 0 ? ByteFormatter.string(fromBytes: totalReclaimable) : nil)
            navRow(.explore, label: "Explore", systemImage: "square.grid.2x2", trailing: nil)
            navRow(.apps, label: "Apps", systemImage: "app.badge.checkmark", trailing: nil)
        }
    }

    private func navRow(_ target: Destination, label: String, systemImage: String, trailing: String?) -> some View {
        // Cleanup stays the highlighted row through Review and Receipt too -
        // those are stages of the same task, not a different destination.
        let isSelected = destination == target
        return Button {
            guard destination != target else { return }
            destination = target
            if target == .cleanup { cleanupStage = .findings }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                Text(label).font(.control)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contextualSection: some View {
        switch destination {
        case .cleanup:
            if !findings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FINDINGS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                    ForEach(findings) { finding in
                        Button {
                            cleanupStage = .findings
                            scrollToFindingID = finding.id
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(dotColor(for: finding.id)).frame(width: 6, height: 6)
                                Text(finding.id.displayName)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(ByteFormatter.string(fromBytes: finding.reclaimableBytes))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .explore:
            FileTreeListView(root: root, selectedPath: $selectedPath, onSelectNode: { node in
                if node.isDirectory { navigate(to: node) }
            }, expandedPaths: $expandedPaths)
        case .apps:
            EmptyView()
        }
    }

    private func dotColor(for id: CleanupFindingID) -> Color {
        switch id {
        case .packageManagerCaches: Color(nsColor: .systemTeal)
        case .unusedApplications: Color(nsColor: .systemOrange)
        case .oldDownloads: Color(nsColor: .systemGreen)
        case .xcodeBuildArtifacts: Color(nsColor: .systemBlue)
        case .duplicateFiles: Color(nsColor: .systemPurple)
        case .simulatorRuntimes: Color(nsColor: .systemGray)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Last scanned")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(String(format: "%.2fs", coordinator.scanDuration))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rescan", action: onRescan)
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            Menu {
                Button("Scan Another Disk...", action: onBackToHome)
                Button("Scan Folder...", action: onScanFolder)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
    }

    // MARK: - Cleanup detail

    @ViewBuilder
    private var cleanupDetail: some View {
        switch cleanupStage {
        case .findings:
            ZStack(alignment: .bottom) {
                CleanupView(
                    findings: findings,
                    selection: selection,
                    expandedFindings: $expandedFindings,
                    scrollToFindingID: $scrollToFindingID,
                    onOpenAppManager: { destination = .apps },
                    onOpenXcodeArchives: { showXcodeArchives = true },
                    canUndo: receipt?.canUndo ?? false,
                    onReviewShortcut: { if selection.count > 0 { cleanupStage = .review } },
                    onUndoShortcut: performUndo,
                    onRescanShortcut: onRescan
                )
                .padding(.bottom, selection.count > 0 ? 60 : 0)

                if selection.count > 0 {
                    SelectionTray(selection: selection, onClear: { selection.clear() }, onReview: { cleanupStage = .review })
                }
            }
            .navigationTitle("Cleanup")

        case .review:
            ReviewView(
                selection: selection,
                onBack: { cleanupStage = .findings },
                onCommit: { permanently in performCommit(permanently: permanently) }
            )
            .navigationTitle("Review")
            .disabled(isCommitting)

        case .receipt:
            if let receipt {
                ReceiptView(
                    reclaimedBytes: receipt.reclaimedBytes,
                    freeBefore: receipt.freeBefore,
                    freeAfter: receipt.freeAfter,
                    permanently: receipt.permanently,
                    canUndo: receipt.canUndo,
                    onUndo: performUndo,
                    onBackToCleanup: {
                        cleanupStage = .findings
                        self.receipt = nil
                    }
                )
            } else {
                // Dead-end guard: `.receipt` should only ever be reached
                // right after `performCommit` sets `receipt`, but nothing in
                // the types enforces that pairing.
                ErrorStateView(message: "There's nothing to show here yet.", onBackToHome: { cleanupStage = .findings })
            }
        }
    }

    private func loadDiskContext() {
        let url = URL(fileURLWithPath: root.path)
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity {
            diskCapacity = (Int64(total), Int64(available))
        }
        purgeableBytes = DiskTelemetryService.purgeableBytes(atPath: root.path)
    }

    private func currentAvailableCapacity() -> Int64 {
        let url = URL(fileURLWithPath: root.path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let available = values.volumeAvailableCapacity else {
            return diskCapacity.available
        }
        return Int64(available)
    }

    /// The only commit point in the app. Runs off the main actor via
    /// `CleanupCommitter`, then reconciles both `cleanupScanner`'s findings
    /// and the live scan tree (`coordinator`) so Explore and the sidebar
    /// total stay correct without a rescan.
    private func performCommit(permanently: Bool) {
        isCommitting = true
        commitErrorMessage = nil
        let items = selection.items
        let freeBefore = currentAvailableCapacity()

        Task {
            let result = await CleanupCommitter.commit(items, permanently: permanently)
            await MainActor.run {
                isCommitting = false
                cleanupScanner.removeDeletedPaths(result.deletedPaths)
                reconcileScanTree(result.deletedPaths)
                selection.clear()

                receipt = ReceiptData(
                    reclaimedBytes: result.reclaimedBytes,
                    freeBefore: freeBefore,
                    freeAfter: currentAvailableCapacity(),
                    permanently: permanently,
                    trashedItems: result.trashedItems
                )
                cleanupStage = .receipt

                if !result.errors.isEmpty {
                    commitErrorMessage = result.errors.joined(separator: "\n")
                }
            }
        }
    }

    /// Restores every trashed item from the last commit. Simplified relative
    /// to the design's "restores the selection" wording: this brings the
    /// files back and returns to Cleanup via a full rescan (the simplest
    /// correct way to get their sizes back into both the tree and the
    /// findings), but does not attempt to re-select the same items
    /// afterward - carrying forward `CleanupItem` references across a
    /// rescan, whose ids may not even still match, isn't worth the
    /// complexity for an undo path.
    private func performUndo() {
        guard let receipt, receipt.canUndo else { return }
        isCommitting = true
        Task {
            let errors = await CleanupCommitter.putBack(receipt.trashedItems)
            await MainActor.run {
                isCommitting = false
                self.receipt = nil
                cleanupStage = .findings
                onRescan()
                if !errors.isEmpty {
                    commitErrorMessage = errors.joined(separator: "\n")
                }
            }
        }
    }

    // MARK: - Explore detail (moved from the old `MainContentView`)

    @ViewBuilder
    private var exploreDetail: some View {
        VStack(spacing: 0) {
            if let selectedNode, !selectedNode.isDirectory {
                FileDetailsView(node: selectedNode, root: root)
            } else {
                GeometryReader { geometry in
                    TreemapView(
                        rects: treemapRects(geometry.size),
                        onSelectNode: { node in
                            if node.isDirectory {
                                navigate(to: node)
                            } else {
                                selectedPath = node.path
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle(coordinator.zoomNode?.name ?? root.name)
        .navigationSubtitle("Scanned in \(String(format: "%.2f", coordinator.scanDuration))s")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    navigate(to: nil)
                } label: {
                    Image(systemName: "arrow.up.to.line")
                }
                .disabled(coordinator.zoomNode == nil)
                .help("Go to overview")
            }

            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigateBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(backStack.isEmpty)
                .keyboardShortcut("[", modifiers: .command)
                .help("Go back")

                Button {
                    navigateForward()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(forwardStack.isEmpty)
                .keyboardShortcut("]", modifiers: .command)
                .help("Go forward")
            }

            if coordinator.hasDetectedChanges {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onRescan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tint(.orange)
                    .help("Files on disk have changed since this scan - click to rescan")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .disabled(selectedNode == nil || (selectedNode?.isSyntheticGroupingNode ?? false))
                .help("Reveal the selected item in Finder")

                Button {
                    copyPath()
                } label: {
                    Label("Copy Path", systemImage: "square.on.square")
                }
                .disabled(selectedNode == nil || (selectedNode?.isSyntheticGroupingNode ?? false))
                .help("Copy the selected item's full path")

                Button(role: .destructive) {
                    itemToDelete = selectedNode
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled((selectedNode?.isSyntheticGroupingNode ?? false) || selectedNode.map { !FileOperations.canDelete(at: $0.path) } ?? true)
                .help("Move the selected item to the Trash, or delete it permanently")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ColorTheme.allCases, id: \.self) { theme in
                        Button {
                            selectedTheme = theme
                        } label: {
                            HStack {
                                Text(theme.displayName).font(.control)
                                if theme == selectedTheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(selectedTheme.displayName, systemImage: "paintpalette")
                }
                .help("Change color theme")
            }
        }
    }

    private func navigate(to node: FileNode?) {
        guard node?.path != coordinator.zoomNode?.path else { return }
        backStack.append(coordinator.zoomNode)
        forwardStack.removeAll()
        coordinator.zoomNode = node
        selectedPath = node?.path
    }

    private func navigateBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(coordinator.zoomNode)
        coordinator.zoomNode = previous
        selectedPath = previous?.path
    }

    private func navigateForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(coordinator.zoomNode)
        coordinator.zoomNode = next
        selectedPath = next?.path
    }

    private func revealInFinder() {
        guard let selectedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectedNode.path)])
    }

    private func copyPath() {
        guard let selectedNode else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedNode.path, forType: .string)
    }

    private func deleteItem(_ node: FileNode, permanently: Bool) {
        do {
            try FileOperations.delete(at: node.path, permanently: permanently)
            handleItemDeleted(node.path)
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func handleItemDeleted(_ deletedPath: String) {
        reconcileScanTree([deletedPath])
        cleanupScanner.removeDeletedPaths([deletedPath])

        if let zoomNode = coordinator.zoomNode, deletedPath == zoomNode.path {
            coordinator.zoomNode = nil
        }
    }

    /// Shared by every path that removes something from the live scan tree -
    /// `performCommit` and `handleItemDeleted` - so the treemap cache,
    /// selection path, expansion state, and zoom history all stay in sync
    /// regardless of which flow triggered the delete. Mirrors the old
    /// `ContentView.handleInspectorDeleted`.
    private func reconcileScanTree(_ deletedPaths: Set<String>) {
        guard case .finished(var currentRoot) = coordinator.state else { return }

        for path in deletedPaths {
            if let updated = currentRoot.removingNode(atPath: path) {
                currentRoot = updated
            }
        }

        coordinator.updateTree(currentRoot)
        treemapCache.invalidate()

        if let selectedPath, deletedPaths.contains(selectedPath) {
            self.selectedPath = nil
        }

        expandedPaths = expandedPaths.filter { expandedPath in
            !deletedPaths.contains { expandedPath.hasPrefix($0) }
        }
        backStack = backStack.filter { node in
            node.map { candidate in !deletedPaths.contains { candidate.path.hasPrefix($0) } } ?? true
        }
        forwardStack = forwardStack.filter { node in
            node.map { candidate in !deletedPaths.contains { candidate.path.hasPrefix($0) } } ?? true
        }
    }
}
