import SwiftUI
import AppKit
import DustEaterCore

struct ContentView: View {
    @State private var coordinator = ScanCoordinator()
    @State private var selectedPath: String?
    @State private var showSidebar = true
    @State private var sortedRoot: FileNode?
    @State private var isSortingInProgress = false
    @State private var selectedTheme: ColorTheme = .weighted
    @State private var isOnHome = true

    private var selectedNode: FileNode? {
        guard let selectedPath, case .finished(let root) = coordinator.state else { return nil }
        return root.find(path: selectedPath)
    }

    private func treemapRects(for size: CGSize) -> [TreemapRect] {
        guard case .finished(let root) = coordinator.state else { return [] }

        // Queue async sort if not already done, but don't block on it
        if sortedRoot == nil && !isSortingInProgress {
            print("📊 Starting background sort...")
            isSortingInProgress = true
            let sortStart = DispatchTime.now()
            Task.detached(priority: .userInitiated) {
                let sorted = root.sortedBySize()
                let sortElapsed = Double(DispatchTime.now().uptimeNanoseconds - sortStart.uptimeNanoseconds) / 1_000_000_000
                print("📊 Background sort completed: \(String(format: "%.3f", sortElapsed))s")
                await MainActor.run { [self] in
                    self.sortedRoot = sorted
                    self.isSortingInProgress = false
                }
            }
        }

        let baseNode = sortedRoot ?? root
        let displayNode = coordinator.zoomNode ?? baseNode

        // Use YMTreeMap for treemap layout
        let children = displayNode.children
        guard !children.isEmpty else { return [] }

        let sizes = children.map { Double($0.size) }
        let treeMap = YMTreeMap(withValues: sizes)
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let cgRects = treeMap.tessellate(inRect: bounds)

        // Map YMTreeMap results back to TreemapRects with FileNodes
        return zip(children, cgRects).map { child, cgRect in
            TreemapRect(node: child, frame: cgRect)
        }
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
                            .scaleEffect(1.2)
                        Text("Preparing scan...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanning(let progress):
                    ScanningStateView(progress: progress, onCancel: coordinator.cancelScan)
                case .finished(let root):
                    MainContentView(
                        root: root,
                        sortedRoot: sortedRoot,
                        selectedPath: $selectedPath,
                        coordinator: coordinator,
                        treemapRects: treemapRects(for:),
                        showSidebar: $showSidebar,
                        selectedTheme: $selectedTheme,
                        onBackToHome: {
                            isOnHome = true
                            sortedRoot = nil
                            isSortingInProgress = false
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
        .frame(minWidth: 900, minHeight: 600)
    }

    private func startScan(path: String) {
        isOnHome = false
        selectedPath = nil
        coordinator.zoomNode = nil
        sortedRoot = nil
        isSortingInProgress = false
        coordinator.startScan(path: path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedPath = nil
        coordinator.zoomNode = nil
        sortedRoot = nil
        isSortingInProgress = false
        coordinator.startScan(path: url.path)
    }
}

// MARK: - Idle State
struct IdleStateView: View {
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.xl) {
            Image(systemName: "folder.badge.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.6))

            VStack(spacing: DustEaterTheme.Spacing.md) {
                Text("Analyze Disk Usage")
                    .font(DustEaterTheme.Typography.title1)

                Text("Choose a folder to see how much space it's using")
                    .font(DustEaterTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onChooseFolder()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
                    .font(DustEaterTheme.Typography.headline)
                    .frame(width: 200, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Text("Keyboard shortcut: ⌘O")
                    .font(DustEaterTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Scanning State
struct ScanningStateView: View {
    let progress: ScanProgressSnapshot
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DustEaterTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.3)

            VStack(spacing: DustEaterTheme.Spacing.md) {
                Text("\(progress.itemsScanned) items scanned")
                    .font(DustEaterTheme.Typography.headline)

                Text(ByteFormatter.string(fromBytes: progress.bytesScanned))
                    .font(DustEaterTheme.Typography.title3)
                    .foregroundStyle(.blue)

                Text(progress.currentPath)
                    .font(DustEaterTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .padding(.top, DustEaterTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
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
                    .font(DustEaterTheme.Typography.headline)
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
    let sortedRoot: FileNode?
    @Binding var selectedPath: String?
    let coordinator: ScanCoordinator
    let treemapRects: (CGSize) -> [TreemapRect]
    @Binding var showSidebar: Bool
    @Binding var selectedTheme: ColorTheme
    let onBackToHome: () -> Void

    private var displayRoot: FileNode {
        sortedRoot ?? root
    }

    var body: some View {
        HStack(spacing: 0) {
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
                                    .help("Folder sizes may exceed total disk usage due to hard links")
                            }

                            Text(root.name)
                                .font(DustEaterTheme.Typography.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .padding(DustEaterTheme.Spacing.md)
                .background(.ultraThinMaterial)

                Divider()

                FileTreeListView(root: displayRoot, selectedPath: $selectedPath)
            }
            .frame(minWidth: 280, maxWidth: 350)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main treemap with hierarchical levels
            VStack(spacing: 0) {
                // Header
                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    HStack {
                        if coordinator.zoomNode != nil {
                            Button {
                                coordinator.zoomNode = nil
                                selectedPath = root.path
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .keyboardShortcut(.escape)
                            .help("Back to overview")
                            .onHover { isHovered in
                                if isHovered {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
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
                                    .font(.caption)
                            }
                        }
                        .help("Change color theme")
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }

                        Button {
                            onBackToHome()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "house")
                                Text("Home")
                                    .font(.caption)
                            }
                        }
                        .help("Back to home screen")
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                    }
                }
                .padding(DustEaterTheme.Spacing.md)
                .background(.ultraThinMaterial)

                Divider()

                // Hierarchical treemap
                GeometryReader { geometry in
                    TreemapView(
                        rects: treemapRects(geometry.size),
                        rootPath: (coordinator.zoomNode ?? root).path,
                        onSelectNode: { node in
                            if node.isDirectory {
                                coordinator.zoomNode = node
                                selectedPath = node.path
                            }
                        },
                        theme: selectedTheme
                    )
                }
            }
        }
    }
}

private extension FileNode {
    func find(path: String) -> FileNode? {
        if self.path == path { return self }
        for child in children {
            if let found = child.find(path: path) {
                return found
            }
        }
        return nil
    }
}
