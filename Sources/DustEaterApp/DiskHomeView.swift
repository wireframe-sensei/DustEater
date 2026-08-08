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
            // Header
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

            if disks.isEmpty {
                VStack(spacing: DustEaterTheme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading disks...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Card grid
                ScrollView {
                    VStack(spacing: DustEaterTheme.Spacing.lg) {
                        // Disks cards
                        let columns = [
                            GridItem(.adaptive(minimum: 300), spacing: DustEaterTheme.Spacing.lg)
                        ]
                        LazyVGrid(columns: columns, spacing: DustEaterTheme.Spacing.lg) {
                            ForEach(disks) { disk in
                                DiskCardView(disk: disk) {
                                    onSelectDisk(disk.path)
                                }
                            }
                        }

                        // Custom folder card
                        LazyVGrid(columns: columns, spacing: DustEaterTheme.Spacing.lg) {
                            Button {
                                onSelectCustomFolder()
                            } label: {
                                VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                                    HStack {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.blue.opacity(0.7))
                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Browse Custom Folder")
                                            .font(DustEaterTheme.Typography.headline)
                                            .foregroundStyle(.primary)
                                        Text("Select any folder on your system")
                                            .font(DustEaterTheme.Typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 150)
                                .padding(DustEaterTheme.Spacing.md)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(12)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }
                    .padding(DustEaterTheme.Spacing.lg)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct DiskCardView: View {
    let disk: DiskInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                // Top section with icon and size
                HStack(alignment: .top, spacing: DustEaterTheme.Spacing.md) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue.opacity(0.7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(disk.name)
                            .font(DustEaterTheme.Typography.headline)
                        Text(disk.path)
                            .font(DustEaterTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                Divider()

                // Usage stats
                VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            Text(ByteFormatter.string(fromBytes: disk.usedSize))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("used")
                                .font(DustEaterTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                            .font(DustEaterTheme.Typography.caption)
                            .foregroundStyle(.secondary)
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
                    .frame(height: 8)

                    Text("\(String(format: "%.1f", disk.usagePercentage))% used")
                        .font(DustEaterTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(usageColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 180)
            .padding(DustEaterTheme.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHandCursor()
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
