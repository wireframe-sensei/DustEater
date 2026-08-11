import SwiftUI
import AppKit
import DustEaterCore

struct DiskInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let totalSize: Int64
    let availableSize: Int64

    var usedSize: Int64 {
        totalSize - availableSize
    }

    var usagePercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize) * 100
    }
}

struct DiskHomeView: View {
    @State private var disks: [DiskInfo] = []
    // Distinguishes "still loading" from "loaded, found nothing" - without
    // this, a machine where `mountedVolumeURLs` returns nil or every volume
    // gets filtered out shows "Loading disks..." forever with no retry and
    // no way to reach `CustomFolderCardView`, which used to live inside the
    // same `else` branch as the disk grid and so was unreachable too.
    @State private var hasLoadedOnce = false
    let onSelectDisk: (String) -> Void
    let onSelectCustomFolder: () -> Void
    let onOpenAppManager: () -> Void

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header section with glass panel
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.accentColor)

                        VStack(spacing: 6) {
                            Text("Dust Eater")
                                .font(.largeTitle.bold())
                            Text("Choose a disk or folder to analyze")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Info panel with glass effect
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("About disk usage")
                                    .font(.headline)
                                Text("Folder sizes may differ slightly due to APFS snapshots and system overhead")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(14)
                    .glassBackground(.ultraThinMaterial, cornerRadius: 12)
                }
                .padding(24)
                .glassBackground(.ultraThinMaterial, cornerRadius: 16)
                .padding(20)

                if !hasLoadedOnce {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading disks...")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    .controlSize(.large)
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if disks.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.secondary)
                                    Text("No disks found")
                                        .font(.headline)
                                    Text("You can still browse a specific folder below, or try again.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Button("Retry", action: loadDisks)
                                        .font(.control)
                                        .buttonStyle(.bordered)
                                        .padding(.top, 4)
                                }
                                .padding(.top, 20)
                            }

                            // `CustomFolderCardView` deliberately sits outside
                            // the `disks.isEmpty` branch above: it doesn't
                            // depend on volume enumeration at all, so it must
                            // stay reachable even when no disks were found -
                            // otherwise a machine with zero visible volumes
                            // would have no way to proceed past this screen.
                            let columns = [
                                GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16)
                            ]

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(disks) { disk in
                                    DiskCardView(disk: disk) {
                                        onSelectDisk(disk.path)
                                    }
                                }

                                CustomFolderCardView(onTap: onSelectCustomFolder)
                                AppManagerCardView(onTap: onOpenAppManager)
                            }
                            .controlSize(.extraLarge)
                            .padding(20)
                        }
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            loadDisks()
        }
        // Structured concurrency, not a `Timer`: this loop starts when
        // `DiskHomeView` appears and is cancelled automatically the moment
        // it leaves the view hierarchy (when `isOnHome` flips to `false` in
        // `ContentView`, the `if isOnHome { DiskHomeView(...) }` branch is
        // torn down, not just hidden) - so it never runs while a scan is
        // showing.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                loadDisks()
            }
        }
        // Mount/unmount/rename fire immediately, so plugging in or ejecting
        // a drive feels instant rather than waiting for the next poll.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            loadDisks()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            loadDisks()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            loadDisks()
        }
    }

    private func loadDisks() {
        defer { hasLoadedOnce = true }

        var diskList: [DiskInfo] = []
        let fileManager = FileManager.default

        guard let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil) else {
            disks = []
            return
        }

        for url in urls {
            let path = url.path

            // Filter out system volumes, simulator disks, and development volumes
            if path.contains("/System/Volumes/") ||
               path.contains("/.") ||
               path.contains("/Library/Developer/CoreSimulator/") ||
               path.contains("SimRuntimeBundle") ||
               path.contains("iOS_") ||
               path.contains("watchOS_") ||
               path.contains("tvOS_") {
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .nameKey])

                if let totalSize = values.volumeTotalCapacity,
                   let availableSize = values.volumeAvailableCapacity,
                   let name = values.name {
                    diskList.append(
                        DiskInfo(
                            name: name,
                            path: path,
                            totalSize: Int64(totalSize),
                            availableSize: Int64(availableSize)
                        )
                    )
                }
            } catch {
                continue
            }
        }

        diskList.sort { $0.usedSize > $1.usedSize }
        self.disks = diskList
    }
}

/// A custom-drawn card, not a system button style - it draws its own
/// background rather than delegating to `.borderedProminent`/`.bordered`,
/// so unlike those it has to read its corner radius from `ControlMetrics`
/// itself. Deliberately reads `cornerRadius` only, not `isCapsule`: this is
/// a wide card, not a compact pill button, so it should never collapse into
/// a capsule the way a real Large/XL button would.
struct CustomFolderCardView: View {
    let onTap: () -> Void
    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "folder.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Browse Custom Folder")
                        .font(.control)
                        .foregroundStyle(.primary)
                    Text("Select any folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 160)
            .padding(16)
            .contentShape(Rectangle())
            .glassBackground(.ultraThinMaterial, cornerRadius: metrics.cornerRadius)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// See `CustomFolderCardView` above - same reasoning: a custom-drawn card,
// so it reads its own corner radius from `ControlMetrics.cornerRadius`
// rather than `isCapsule`.
struct DiskCardView: View {
    let disk: DiskInfo
    let onTap: () -> Void
    @State private var isHovered = false
    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Top section with icon
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    Spacer()
                }

                // Disk info
                VStack(alignment: .leading, spacing: 3) {
                    Text(disk.name)
                        .font(.control)
                        .foregroundStyle(.primary)
                    Text(disk.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Usage section
                VStack(alignment: .leading, spacing: 10) {
                    // Size display
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ByteFormatter.string(fromBytes: disk.usedSize))
                                .font(.body.weight(.semibold).monospaced())
                                .foregroundStyle(.primary)
                            Text("of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", disk.usagePercentage))%")
                            .font(.body.weight(.semibold).monospaced())
                            .foregroundStyle(usageColor)
                    }

                    // Progress bar
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.progressTrack)

                        Capsule()
                            .fill(usageColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: disk.usagePercentage / 100.0, y: 1, anchor: .leading)
                    }
                    .frame(height: 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 160)
            .padding(16)
            .contentShape(Rectangle())
            .glassBackground(.ultraThinMaterial, cornerRadius: metrics.cornerRadius)
            .foregroundStyle(.primary)
            .opacity(isHovered ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onContinuousHover { phase in
            if case .active = phase {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = false
                }
            }
        }
    }

    private var usageColor: Color {
        let percentage = disk.usagePercentage
        if percentage > 80 {
            return Color(nsColor: .systemRed)
        } else if percentage > 60 {
            return Color(nsColor: .systemYellow)
        } else {
            return Color(nsColor: .systemGreen)
        }
    }
}

#Preview {
    DiskHomeView(
        onSelectDisk: { _ in },
        onSelectCustomFolder: {},
        onOpenAppManager: {}
    )
}
