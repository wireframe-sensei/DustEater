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
        VStack(spacing: DustEaterTheme.Spacing.lg) {
            VStack(spacing: DustEaterTheme.Spacing.md) {
                Image(systemName: "externaldrive.badge.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.opacity(0.6))

                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    Text("Disk Analyzer")
                        .font(DustEaterTheme.Typography.title1)
                    Text("Select a disk or folder to analyze")
                        .font(DustEaterTheme.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, DustEaterTheme.Spacing.lg)

            // Disks list
            VStack(spacing: DustEaterTheme.Spacing.md) {
                if disks.isEmpty {
                    Text("Loading disks...")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: DustEaterTheme.Spacing.md) {
                            ForEach(disks) { disk in
                                DiskRowView(disk: disk) {
                                    onSelectDisk(disk.path)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Custom folder option
            VStack(spacing: DustEaterTheme.Spacing.md) {
                Button {
                    onSelectCustomFolder()
                } label: {
                    HStack(spacing: DustEaterTheme.Spacing.md) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse Custom Folder")
                                .font(DustEaterTheme.Typography.headline)
                            Text("Select any folder on your system")
                                .font(DustEaterTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DustEaterTheme.Spacing.md)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            }
            .padding(DustEaterTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DustEaterTheme.Spacing.xl)
        .background(Color(nsColor: .windowBackgroundColor))
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

            // Filter out system volumes (APFS snapshots, preboot, VM, etc.)
            if path.contains("/System/Volumes/") || path.contains("/.") {
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

        // Sort by used size (descending)
        diskList.sort { $0.usedSize > $1.usedSize }
        self.disks = diskList
    }
}

struct DiskRowView: View {
    let disk: DiskInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disk.name)
                            .font(DustEaterTheme.Typography.headline)
                        Text(disk.path)
                            .font(DustEaterTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.string(fromBytes: disk.usedSize))
                            .font(DustEaterTheme.Typography.body)
                        Text("of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                            .font(DustEaterTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress bar
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(usageColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: disk.usagePercentage / 100.0, y: 1, anchor: .leading)
                }
                .frame(height: 6)

                Text("\(String(format: "%.1f", disk.usagePercentage))% used")
                    .font(DustEaterTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DustEaterTheme.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private var usageColor: Color {
        let percentage = disk.usagePercentage
        if percentage > 80 {
            return .red.opacity(0.7)
        } else if percentage > 60 {
            return .orange.opacity(0.7)
        } else {
            return .green.opacity(0.7)
        }
    }
}

#Preview {
    DiskHomeView(
        onSelectDisk: { _ in },
        onSelectCustomFolder: {}
    )
}
