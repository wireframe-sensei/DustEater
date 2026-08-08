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
        VStack(spacing: 0) {
            // Header with large padding
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue.opacity(0.7))

                VStack(spacing: 8) {
                    Text("Disk Analyzer")
                        .font(.system(size: 32, weight: .bold, design: .default))
                    Text("Select a disk or folder to analyze")
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                }

                // Info note about usage differences
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue.opacity(0.7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Note about disk usage")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                            Text("Folder sizes may differ slightly from system storage due to APFS snapshots, system reserved space, and filesystem overhead.")
                                .font(.system(size: 11, weight: .regular, design: .default))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 4)
            }
            .padding(.top, 48)
            .padding(.bottom, 40)

            if disks.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading disks...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Card grid with Apple-style layout
                ScrollView {
                    VStack(spacing: 0) {
                        let columns = [
                            GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 20)
                        ]

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(disks) { disk in
                                DiskCardView(disk: disk) {
                                    onSelectDisk(disk.path)
                                }
                            }

                            // Custom folder card
                            Button {
                                onSelectCustomFolder()
                            } label: {
                                VStack(alignment: .leading, spacing: 16) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.blue.opacity(0.7))

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Browse Custom Folder")
                                            .font(.system(size: 16, weight: .semibold, design: .default))
                                            .foregroundStyle(.primary)
                                        Text("Select any folder on your system")
                                            .font(.system(size: 13, weight: .regular, design: .default))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 180)
                                .padding(20)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(18)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(28)
                    }
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
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Icon
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue.opacity(0.7))
                    Spacer()
                }

                // Disk info
                VStack(alignment: .leading, spacing: 4) {
                    Text(disk.name)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                    Text(disk.path)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Usage section
                VStack(alignment: .leading, spacing: 10) {
                    // Size text
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(ByteFormatter.string(fromBytes: disk.usedSize))
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("used")
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundStyle(.secondary)
                        }
                        Text("of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.gray.opacity(0.15))

                        RoundedRectangle(cornerRadius: 5)
                            .fill(usageColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: disk.usagePercentage / 100.0, y: 1, anchor: .leading)
                    }
                    .frame(height: 6)

                    // Percentage
                    Text("\(String(format: "%.0f", disk.usagePercentage))% used")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(usageColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 180)
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(18)
            .foregroundStyle(.primary)
            .opacity(isHovered ? 0.95 : 1.0)
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
