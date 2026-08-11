import SwiftUI
import AppKit
import DustEaterCore

struct ContentView: View {
    @State private var coordinator = ScanCoordinator()
    @State private var selectedPath: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTheme: ColorTheme = .weighted
    @State private var isOnHome = true
    @State private var totalDiskSize: Int64 = 0
    // Plain reference type held for stable identity across body
    // re-evaluations (same pattern as `coordinator` above) - its internal
    // cache writes are not `@State`, so they're invisible to SwiftUI's
    // dependency tracking and don't trigger re-renders or risk the
    // "modifying state during view update" hazard a `@State`-backed cache
    // would.
    @State private var treemapCache = TreemapCache()

    private func treemapRects(for size: CGSize) -> [TreemapRect] {
        guard case .finished(let root) = coordinator.state else { return [] }
        let displayNode = coordinator.zoomNode ?? root
        return treemapCache.rects(for: displayNode, size: size, theme: selectedTheme)
    }

    var body: some View {
        ZStack {
            if isOnHome {
                DiskHomeView(
                    onSelectDisk: { path in
                        startScan(path: path)
                    },
                    onSelectCustomFolder: {
                        chooseFolder()
                    }
                )
            } else {
                switch coordinator.state {
                case .idle:
                    // Normally brief (probing access before the real scan
                    // starts) and paired with `isOnHome` flipping back to
                    // true wherever `.idle` gets set today, so this Cancel
                    // is a safety net rather than something expected to be
                    // pressed - but nothing in the types enforces that
                    // pairing, so a future code path that lands here without
                    // also resetting `isOnHome` must not strand the user on
                    // a bare spinner with no way out.
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing scan...")
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            coordinator.cancelScan()
                            backToHome()
                        }
                        .font(.control)
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanning(let progress):
                    ScanningStateView(progress: progress, totalDiskSize: totalDiskSize, onCancel: {
                        coordinator.cancelScan()
                        backToHome()
                    })
                case .finished(let root):
                    MainContentView(
                        root: root,
                        selectedPath: $selectedPath,
                        coordinator: coordinator,
                        treemapRects: treemapRects(for:),
                        columnVisibility: $columnVisibility,
                        selectedTheme: $selectedTheme,
                        treemapCache: treemapCache,
                        onBackToHome: backToHome,
                        onRescan: { startScan(path: root.path) }
                    )
                case .needsFullDiskAccess(let path):
                    PermissionBannerView(path: path, onBackToHome: backToHome)
                case .failed(let message):
                    ErrorStateView(message: message, onBackToHome: backToHome)
                }
            }
        }
    }

    /// Shared by every "leave this scan and return to the disk picker" exit
    /// point - `MainContentView`'s toolbar, and the two terminal failure
    /// screens below, which previously had no way back at all.
    private func backToHome() {
        isOnHome = true
        selectedPath = nil
    }

    private func startScan(path: String) {
        isOnHome = false
        selectedPath = nil
        coordinator.zoomNode = nil

        // Get total disk size
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let totalCapacity = values.volumeTotalCapacity {
            totalDiskSize = Int64(totalCapacity)
        }

        treemapCache.invalidate()
        coordinator.startScan(path: path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isOnHome = false
        selectedPath = nil
        coordinator.zoomNode = nil

        // Get total disk size
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
           let totalCapacity = values.volumeTotalCapacity {
            totalDiskSize = Int64(totalCapacity)
        }

        treemapCache.invalidate()
        coordinator.startScan(path: url.path)
    }
}

/// Memoized squarified-treemap layout, keyed on which node is displayed and
/// at what size. `treemapRects(for:)` used to redo the full sort + `YMTreeMap`
/// tessellation on *every* `MainContentView` body evaluation - including ones
/// triggered by something as unrelated as a sidebar selection change - even
/// though the layout only actually changes when the displayed node or the
/// available size changes. A plain (non-`Observable`) class rather than
/// `@State` itself: its cache writes are invisible to SwiftUI's dependency
/// tracking, so they can't trigger the "modifying state during view update"
/// hazard a `@State`-backed cache would risk when written from inside a
/// `GeometryReader` closure.
final class TreemapCache {
    private struct Key: Equatable {
        let path: String
        let size: CGSize
        let childCount: Int
        let theme: ColorTheme
    }

    private var key: Key?
    private var cachedRects: [TreemapRect] = []

    func rects(for displayNode: FileNode, size: CGSize, theme: ColorTheme) -> [TreemapRect] {
        let requestedKey = Key(path: displayNode.path, size: size, childCount: displayNode.children.count, theme: theme)
        if key == requestedKey {
            return cachedRects
        }

        // Sorting is scoped to this one node's immediate children, not the
        // whole tree, so it's cheap enough to redo on every cache miss -
        // no need to precompute a sorted copy of the entire scan up front.
        let children = displayNode.children.sorted { $0.size > $1.size }
        let computed: [TreemapRect]
        if children.isEmpty {
            computed = []
        } else {
            let sizes = children.map { Double($0.size) }
            let treeMap = YMTreeMap(withValues: sizes)
            let bounds = CGRect(origin: .zero, size: size)
            let cgRects = treeMap.tessellate(inRect: bounds)

            // Every rect here is a direct child of `displayNode`, so they
            // all share the same depth relative to it - resolve it once
            // rather than re-deriving it (a string prefix-strip + full scan
            // for "/" characters) per rect, per redraw.
            let depth = children.first.map {
                TreemapColors.depth(fromPath: $0.path, relativeTo: displayNode.path)
            } ?? 0

            computed = zip(children, cgRects).map { child, cgRect in
                let color = TreemapColors.colorForNode(child, depth: depth, theme: theme)
                return TreemapRect(node: child, frame: cgRect, color: color)
            }
        }

        key = requestedKey
        cachedRects = computed
        return computed
    }

    /// Called when a new scan starts. Necessary - not just tidy - because
    /// the cache key doesn't include scan identity: re-scanning the exact
    /// same path at the exact same window size would otherwise match the
    /// previous scan's cache entry and silently serve stale rects.
    func invalidate() {
        key = nil
        cachedRects = []
    }
}

// MARK: - Scanning State
struct ScanningStateView: View {
    let progress: ScanProgressSnapshot
    let totalDiskSize: Int64
    let onCancel: () -> Void

    var progressRatio: Double {
        // Calculate progress based on bytes scanned vs total disk size
        guard totalDiskSize > 0 else { return 0.01 }
        let ratio = Double(progress.bytesScanned) / Double(totalDiskSize)
        return min(0.99, max(0.01, ratio))  // Cap at 99% until scan completes
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    // Doughnut progress ring background
                    Circle()
                        .stroke(Color.progressTrack, lineWidth: 12)
                        .frame(width: 280, height: 280)

                    // Doughnut progress ring (animated to progress)
                    Circle()
                        .trim(from: 0, to: progressRatio)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 280, height: 280)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: progressRatio)

                    // Center content
                    VStack(spacing: DustEaterTheme.Spacing.md) {
                        ProgressView()

                        VStack(spacing: 8) {
                            Text("\(progress.itemsScanned) items scanned")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(ByteFormatter.string(fromBytes: progress.bytesScanned))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)

                            Text(progress.currentPath)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 300)
                        }
                    }
                    .frame(width: 240)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .font(.control)
                    .buttonStyle(.bordered)
                    .padding(.bottom, DustEaterTheme.Spacing.lg)
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Permission Banner
struct PermissionBannerView: View {
    let path: String
    let onBackToHome: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            VStack(spacing: DustEaterTheme.Spacing.md) {
                Text("Full Disk Access Required")
                    .font(DustEaterTheme.Typography.title2)

                Text("Grant DustEater access in System Settings to analyze this folder.")
                    .font(DustEaterTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: DustEaterTheme.Spacing.md) {
                Button {
                    onBackToHome()
                } label: {
                    Label("Back to Home", systemImage: "house")
                        .font(.control)
                }
                .buttonStyle(.bordered)

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                        .font(.control)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Error State
struct ErrorStateView: View {
    let message: String
    let onBackToHome: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Text("Scan Failed")
                    .font(DustEaterTheme.Typography.title2)

                Text(message)
                    .font(DustEaterTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                onBackToHome()
            } label: {
                Label("Back to Home", systemImage: "house")
                    .font(.control)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Main Content
struct MainContentView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let coordinator: ScanCoordinator
    let treemapRects: (CGSize) -> [TreemapRect]
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var selectedTheme: ColorTheme
    let treemapCache: TreemapCache
    let onBackToHome: () -> Void
    let onRescan: () -> Void

    // Owned here rather than in `FileTreeListView`: the delete alert below is
    // triggered from the toolbar (acting on `selectedNode`), not from a
    // per-row control, so the state it mutates - including pruning
    // `expandedPaths` - has to live where the toolbar does. Scoped to
    // `MainContentView` rather than hoisted further up to `ContentView`: it
    // only matters in the `.finished` state, and letting it die when that
    // case is left is exactly the "new scan starts collapsed" behavior we want.
    @State private var expandedPaths: Set<String> = []
    @State private var showDeleteAlert = false
    @State private var itemToDelete: FileNode?
    // Both delete and Clear Cache used to fail (or succeed) completely
    // silently - `print()` to a console the user never sees, tree/UI
    // otherwise unchanged, so a failed action looked identical to one that
    // just hadn't been clicked. These surface the actual outcome.
    @State private var deleteErrorMessage: String?
    @State private var cacheClearAlertMessage: String?
    @State private var cacheClearSucceeded = false
    // Browser-style zoom history, like Finder/Safari/Xcode's Back/Forward -
    // not a strict "go to parent" stack, since a jump can come from the
    // sidebar (any directory, any depth) as well as drilling into the
    // treemap. `nil` represents the unzoomed overview. Scoped here for the
    // same reason as `expandedPaths` above: it should reset when a new scan
    // replaces this view's subtree, not persist across scans.
    @State private var backStack: [FileNode?] = []
    @State private var forwardStack: [FileNode?] = []

    private var selectedNode: FileNode? {
        guard let selectedPath else { return nil }
        return root.node(atPath: selectedPath)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: File tree for navigation
            FileTreeListView(root: root, selectedPath: $selectedPath, onSelectNode: { node in
                // Only zoom into directories, not files
                if node.isDirectory {
                    navigate(to: node)
                }
                // Files just get highlighted in the current view
            }, expandedPaths: $expandedPaths)
            .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 350)
        } detail: {
            // Main treemap with hierarchical levels
            VStack(spacing: 0) {
                // Hierarchical treemap or file details
                if let selectedNode = selectedNode, !selectedNode.isDirectory {
                    // Show file details when a file is selected
                    FileDetailsView(node: selectedNode, root: root)
                } else {
                    // Show treemap for directories and overview
                    GeometryReader { geometry in
                        TreemapView(
                            rects: treemapRects(geometry.size),
                            onSelectNode: { node in
                                if node.isDirectory {
                                    navigate(to: node)
                                } else {
                                    // Selection is recorded for any node so
                                    // the sidebar can reveal it; zooming
                                    // stays folders-only.
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
                        onBackToHome()
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .help("Back to home screen")
                }

                // Jumps straight to the unzoomed overview, regardless of how
                // deep the current zoom is - distinct from Home (which leaves
                // this scan entirely) and from Back (which retraces history
                // one step at a time). Goes through `navigate(to:)` like any
                // other zoom change, so it's still undoable with Back - this
                // is exactly what the Back button itself used to do before
                // Back/Forward became real history.
                ToolbarItem(placement: .navigation) {
                    Button {
                        navigate(to: nil)
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .disabled(coordinator.zoomNode == nil)
                    .help("Go to overview")
                }

                // Back/Forward through zoom history, grouped together as one
                // unit - the same shape Finder, Safari, and Xcode use, kept
                // separate from the Home button above (Home always returns
                // to the disk picker; these move through folder history).
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

                // Only appears when `FileSystemWatcher` (owned by
                // `ScanCoordinator`) detects a filesystem change under the
                // scanned root - external changes are rare, unlike selection
                // changes below, so a small conditional pop-in here is the
                // right trade-off rather than a permanently-disabled button.
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

                // Actions for the current selection. Disabled rather than
                // hidden when nothing is selected, so the toolbar doesn't
                // reflow every time selection changes - the same failure mode
                // this pattern replaced (a per-row `Menu`, which is what
                // crushed sidebar names down to a few characters; see
                // FileTreeListView.swift).
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        revealInFinder()
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .disabled(selectedNode == nil)
                    .help("Reveal the selected item in Finder")

                    Button {
                        copyPath()
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    .disabled(selectedNode == nil)
                    .help("Copy the selected item's full path")

                    Button(role: .destructive) {
                        itemToDelete = selectedNode
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedNode.map { !FileOperations.canDelete(at: $0.path) } ?? true)
                    .help("Move the selected item to the Trash, or delete it permanently")
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(ColorTheme.allCases, id: \.self) { theme in
                            Button {
                                selectedTheme = theme
                            } label: {
                                HStack {
                                    Text(theme.displayName)
                                        .font(.control)
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

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: clearSystemCaches) {
                            Label("Clear Cache", systemImage: "trash")
                        }
                    } label: {
                        Label("Tools", systemImage: "ellipsis.circle")
                    }
                    .help("Utility options")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }
                    .help("Folder sizes are approximate. Hard-linked files and deduplication mean the sum will exceed actual disk usage. True usage is shown on home screen.")
                }
            }
        }
        .alert("Delete Item", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                if let node = itemToDelete {
                    deleteItem(node, permanently: false)
                }
            }
            Button("Delete Permanently", role: .destructive) {
                if let node = itemToDelete {
                    deleteItem(node, permanently: true)
                }
            }
        } message: {
            if let node = itemToDelete {
                Text("Are you sure you want to delete \"\(node.name)\"?")
            }
        }
        .alert("Couldn't Delete Item", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in if !isPresented { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(cacheClearSucceeded ? "Cache Cleared" : "Couldn't Clear Cache", isPresented: Binding(
            get: { cacheClearAlertMessage != nil },
            set: { isPresented in if !isPresented { cacheClearAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(cacheClearAlertMessage ?? "")
        }
    }

    /// Zooms to `node` (or `nil` for the overview) and records the *current*
    /// zoom on the back stack first - the shared entry point every
    /// zoom-triggering gesture (treemap click, sidebar click) should call,
    /// so history stays consistent regardless of where the navigation came
    /// from. Starting a new path forward from here invalidates whatever was
    /// in `forwardStack`, same as a browser: it only replays a `navigate`
    /// that was itself undone by `navigateBack()`.
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
        // `activateFileViewerSelecting` reveals *and* selects the item. The
        // old per-row menu called `selectFile(nil, inFileViewerRootedAtPath:)`,
        // which only opens the parent folder without selecting anything -
        // fixed here, not just relocated.
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

    private func clearSystemCaches() {
        do {
            try FileOperations.clearSystemCaches()
            cacheClearSucceeded = true
            cacheClearAlertMessage = "System caches were cleared."
        } catch {
            cacheClearSucceeded = false
            cacheClearAlertMessage = error.localizedDescription
        }
    }

    private func handleItemDeleted(_ deletedPath: String) {
        guard case .finished(let currentRoot) = coordinator.state else { return }

        if let updatedRoot = currentRoot.removingNode(atPath: deletedPath) {
            coordinator.updateTree(updatedRoot)
            treemapCache.invalidate()

            if let zoomNode = coordinator.zoomNode, deletedPath == zoomNode.path {
                coordinator.zoomNode = nil
                selectedPath = nil
            }

            if selectedPath == deletedPath {
                selectedPath = nil
            }

            // Drop the deleted subtree from expansion state so a later
            // re-scan can't resurrect stale open branches for paths that no
            // longer exist in the tree.
            expandedPaths = expandedPaths.filter { !$0.hasPrefix(deletedPath) }

            // Same idea for zoom history: Back/Forward must never be able to
            // land on a node that no longer exists.
            backStack = backStack.filter { $0.map { !$0.path.hasPrefix(deletedPath) } ?? true }
            forwardStack = forwardStack.filter { $0.map { !$0.path.hasPrefix(deletedPath) } ?? true }
        }
    }
}
