import SwiftUI
import AppKit
import DustEaterCore

struct ContentView: View {
    private enum TopLevelScreen: Equatable {
        case home
        case scanFlow
        case appManager
    }

    @State private var screen: TopLevelScreen = .home
    @State private var coordinator = ScanCoordinator()
    @State private var selectedTheme: ColorTheme = .weighted
    // Plain reference type held for stable identity across body
    // re-evaluations (same pattern as `coordinator` above) - its internal
    // cache writes are not `@State`, so they're invisible to SwiftUI's
    // dependency tracking and don't trigger re-renders or risk the
    // "modifying state during view update" hazard a `@State`-backed cache
    // would.
    @State private var treemapCache = TreemapCache()
    // Set once, the first time `.home` would otherwise be shown, so a
    // rescan or a return from a scan never re-triggers the auto-skip.
    @State private var hasCheckedAutoSkip = false

    private func treemapRects(for size: CGSize) -> [TreemapRect] {
        guard case .finished(let root) = coordinator.state else { return [] }
        let displayNode = coordinator.zoomNode ?? root
        return treemapCache.rects(for: displayNode, size: size, theme: selectedTheme)
    }

    var body: some View {
        switch screen {
        case .home:
            DiskHomeView(
                onSelectDisk: { path in
                    startScan(path: path)
                },
                onSelectCustomFolder: {
                    chooseFolder()
                },
                onOpenAppManager: {
                    screen = .appManager
                }
            )
            .task {
                guard !hasCheckedAutoSkip else { return }
                hasCheckedAutoSkip = true
                if let onlyVolumePath = Self.onlyEligibleVolumePath() {
                    startScan(path: onlyVolumePath)
                }
            }
        case .scanFlow:
            switch coordinator.state {
            case .idle:
                // Normally brief (probing access before the real scan
                // starts) and paired with `screen` flipping back to
                // `.home` wherever `.idle` gets set today, so this Cancel
                // is a safety net rather than something expected to be
                // pressed - but nothing in the types enforces that
                // pairing, so a future code path that lands here without
                // also resetting `screen` must not strand the user on
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
            case .scanning, .finished, .cancelled:
                // Scanning is a stage of the Cleanup task now, not a
                // separate screen - CleanupShellView shows the live
                // Scanning card while `coordinator.state == .scanning`,
                // streaming findings in as they're discovered, and carries
                // straight through to `.finished`/`.cancelled` without
                // being torn down and rebuilt.
                CleanupShellView(
                    coordinator: coordinator,
                    treemapRects: treemapRects(for:),
                    treemapCache: treemapCache,
                    selectedTheme: $selectedTheme,
                    onBackToHome: backToHome,
                    onScanFolder: chooseFolder,
                    onRescan: {
                        guard let path = coordinator.rootPath else { return }
                        startScan(path: path)
                    }
                )
            case .needsFullDiskAccess(let path):
                PermissionBannerView(path: path, onBackToHome: backToHome)
            case .failed(let message):
                ErrorStateView(message: message, onBackToHome: backToHome)
            }
        case .appManager:
            AppManagerView(onBackToHome: backToHome)
        }
    }

    /// The design handoff's disk picker collapses into the sidebar and is
    /// skipped entirely when there's only one volume to scan. Duplicates
    /// `DiskHomeView.loadDisks`'s volume filter rather than sharing it - two
    /// call sites, and CLAUDE.md's Rule of Three says wait for a third
    /// before extracting.
    private static func onlyEligibleVolumePath() -> String? {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) else {
            return nil
        }

        let eligiblePaths = urls.map(\.path).filter { path in
            !path.contains("/System/Volumes/") &&
            !path.contains("/.") &&
            !path.contains("/Library/Developer/CoreSimulator/") &&
            !path.contains("SimRuntimeBundle") &&
            !path.contains("iOS_") &&
            !path.contains("watchOS_") &&
            !path.contains("tvOS_")
        }

        return eligiblePaths.count == 1 ? eligiblePaths.first : nil
    }

    /// Shared by every "leave this scan and return to the disk picker" exit
    /// point - the shell's sidebar footer, and the two terminal failure
    /// screens below, which previously had no way back at all.
    private func backToHome() {
        screen = .home
    }

    private func startScan(path: String) {
        screen = .scanFlow
        coordinator.zoomNode = nil
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

        screen = .scanFlow
        coordinator.zoomNode = nil
        treemapCache.invalidate()
        coordinator.startScan(path: url.path)
    }
}

/// Memoized squarified-treemap layout, keyed on which node is displayed and
/// at what size. `treemapRects(for:)` used to redo the full sort + `YMTreeMap`
/// tessellation on *every* `CleanupShellView` body evaluation - including ones
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

