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
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.12)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header section with glass panel
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.blue)

                        VStack(spacing: 6) {
                            Text("Disk Analyzer")
                                .font(.system(size: 28, weight: .semibold, design: .default))
                            Text("Choose a disk or folder to analyze")
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Info panel with glass effect
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("About disk usage")
                                    .font(.system(size: 13, weight: .semibold, design: .default))
                                Text("Folder sizes may differ slightly due to APFS snapshots and system overhead")
                                    .font(.system(size: 12, weight: .regular, design: .default))
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
                            .scaleEffect(1.3)
                        Text("Loading disks...")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14, weight: .regular))
                    }
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

                                // Custom folder card
                                Button {
                                    onSelectCustomFolder()
                                } label: {
                                    VStack(alignment: .leading, spacing: 16) {
                                        Image(systemName: "folder.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.blue.opacity(0.8))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Browse Custom Folder")
                                                .font(.system(size: 15, weight: .semibold, design: .default))
                                                .foregroundStyle(.primary)
                                            Text("Select any folder")
                                                .font(.system(size: 12, weight: .regular, design: .default))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: 160)
                                    .padding(16)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
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
            VStack(alignment: .leading, spacing: 14) {
                // Top section with icon
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.blue.opacity(0.8))
                    Spacer()
                }

                // Disk info
                VStack(alignment: .leading, spacing: 3) {
                    Text(disk.name)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                    Text(disk.path)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
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
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", disk.usagePercentage))%")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(usageColor)
                    }

                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
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
            .cornerRadius(14)
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
            return Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A - macOS red
        } else if percentage > 60 {
            return Color(red: 1.0, green: 0.8, blue: 0.0) // #FFD60A - macOS yellow
        } else {
            return Color(red: 0.3, green: 0.84, blue: 0.4) // #34C759 - macOS green
        }
    }
}

#Preview {
    DiskHomeView(
        onSelectDisk: { _ in },
        onSelectCustomFolder: {}
    )
}
