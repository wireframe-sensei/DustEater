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
    let onSelectDisk: (String) -> Void
    let onSelectCustomFolder: () -> Void

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
                            Text("Disk Analyzer")
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
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding(20)

                if disks.isEmpty {
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
    }

    private func loadDisks() {
        var diskList: [DiskInfo] = []
        let fileManager = FileManager.default

        guard let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil) else {
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

/// A custom-drawn card, not a system button style — it draws its own
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
            .background(.ultraThinMaterial)
            .cornerRadius(metrics.cornerRadius)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// See `CustomFolderCardView` above — same reasoning: a custom-drawn card,
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
                            .fill(Color(nsColor: .quaternaryLabelColor))

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
            .background(.ultraThinMaterial)
            .cornerRadius(metrics.cornerRadius)
            .foregroundStyle(.primary)
            .opacity(isHovered ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
        onSelectCustomFolder: {}
    )
}
