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
    // re-evaluations (same pattern as `coordinator` above) — its internal
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
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing scan...")
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanning(let progress):
                    ScanningStateView(progress: progress, totalDiskSize: totalDiskSize, onCancel: {
                        coordinator.cancelScan()
                        isOnHome = true
                    })
                case .finished(let root):
                    MainContentView(
                        root: root,
                        selectedPath: $selectedPath,
                        coordinator: coordinator,
                        treemapRects: treemapRects(for:),
                        columnVisibility: $columnVisibility,
                        selectedTheme: $selectedTheme,
                        onBackToHome: {
                            isOnHome = true
                            selectedPath = nil
                        }
                    )
                case .needsFullDiskAccess(let path):
                    PermissionBannerView(path: path)
                case .failed(let message):
                    ErrorStateView(message: message)
                }
            }
        }
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
/// tessellation on *every* `MainContentView` body evaluation — including ones
/// triggered by something as unrelated as a sidebar selection change — even
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
        // whole tree, so it's cheap enough to redo on every cache miss —
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
            // all share the same depth relative to it — resolve it once
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

    /// Called when a new scan starts. Necessary — not just tidy — because
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Error State
struct ErrorStateView: View {
    let message: String

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
    let onBackToHome: () -> Void

    private var selectedNode: FileNode? {
        guard let selectedPath else { return nil }
        return root.node(atPath: selectedPath)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: File tree for navigation
            VStack(spacing: 0) {
                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Files & Folders")
                                    .font(DustEaterTheme.Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .help("Folder sizes are approximate. Hard-linked files and deduplication mean the sum will exceed actual disk usage. True usage is shown on home screen.")
                            }

                            Text(root.name)
                                .font(DustEaterTheme.Typography.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .padding(DustEaterTheme.Spacing.md)
                .background(.bar)

                Divider()

                FileTreeListView(root: root, selectedPath: $selectedPath) { node in
                    // Only zoom into directories, not files
                    if node.isDirectory {
                        coordinator.zoomNode = node
                    }
                    // Files just get highlighted in the current view
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 350)
        } detail: {
            // Main treemap with hierarchical levels
            VStack(spacing: 0) {
                // Header
                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    HStack {
                        if coordinator.zoomNode != nil {
                            Button {
                                coordinator.zoomNode = nil
                                selectedPath = nil
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .keyboardShortcut(.escape)
                            .help("Back to overview")
                            .pointingHandCursor()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hierarchy View")
                                .font(DustEaterTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            if let zoomNode = coordinator.zoomNode {
                                Text(zoomNode.name)
                                    .font(DustEaterTheme.Typography.headline)
                                    .lineLimit(1)
                            } else {
                                HStack(spacing: DustEaterTheme.Spacing.sm) {
                                    Text("Overview")
                                        .font(DustEaterTheme.Typography.headline)
                                    Text("• Scanned in \(String(format: "%.2f", coordinator.scanDuration))s")
                                        .font(DustEaterTheme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()

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
                            HStack(spacing: 6) {
                                Image(systemName: "paintpalette")
                                Text(selectedTheme.displayName)
                                    .font(.control)
                            }
                        }
                        .help("Change color theme")
                        .pointingHandCursor()

                        Button {
                            onBackToHome()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "house")
                                Text("Home")
                                    .font(.control)
                            }
                        }
                        .help("Back to home screen")
                        .pointingHandCursor()
                    }
                }
                .padding(DustEaterTheme.Spacing.md)
                .background(.bar)

                Divider()

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
                                    coordinator.zoomNode = node
                                    selectedPath = node.path
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
