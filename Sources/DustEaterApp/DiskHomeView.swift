import SwiftUI
import AppKit
import DustEaterCore

struct DiskInfo: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let totalSize: Int64
    let availableSize: Int64
    let isInternal: Bool
    /// "Internal · APFS" / "External · USB" - already formatted, since the
    /// two cases pull from genuinely different sources (filesystem name vs
    /// IOKit's interconnect protocol) and there's only one caller.
    let kindLabel: String

    var usedSize: Int64 { totalSize - availableSize }

    var usagePercentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize) * 100
    }
}

/// Home - safety rule 13: a scan is never started for the user, and the
/// expected duration is stated before it begins. Always shown, on every
/// launch, regardless of volume count (reversed 18 Aug - see the design
/// handoff's section 11 for why auto-skipping a single volume was wrong).
/// Replaces the whole window, like the welcome flow: no sidebar, since the
/// three destinations are empty until something has been scanned.
struct DiskHomeView: View {
    @State private var disks: [DiskInfo] = []
    // Distinguishes "still loading" from "loaded, found nothing" - without
    // this, a machine where `mountedVolumeURLs` returns nil or every volume
    // gets filtered out shows a spinner forever with no retry and no way
    // to reach the folder-scan card, which must stay reachable regardless.
    @State private var hasLoadedOnce = false

    /// Non-nil only when this session already has results to show -
    /// `ContentView` derives it from `coordinator`, never from anything
    /// persisted across launches, since the actual scanned tree isn't
    /// persisted either. Landing here must never force a rescan to reach
    /// findings the app already has, so "View Results" only ever appears
    /// when it can be honored without one.
    let lastScanSummary: (finishedAt: Date, reclaimableBytes: Int64)?
    let onSelectVolume: (String) -> Void
    let onChooseFolder: () -> Void
    let onSelectFolder: (String) -> Void
    let onViewResults: () -> Void

    private var volumePaths: Set<String> { Set(disks.map(\.path)) }

    var body: some View {
        // Same centering approach as `WelcomeView`, and the same reason:
        // a bare `Spacer` inside a `ScrollView` has no extra room to
        // expand into unless the content is told it must be at least the
        // viewport's size first.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    VStack(alignment: .leading, spacing: 22) {
                        if let lastScanSummary {
                            returningUserStrip(lastScanSummary)
                        }
                        heading

                        if !hasLoadedOnce {
                            ProgressView()
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else if disks.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(disks) { disk in
                                    VolumeCardView(disk: disk, onTap: { onSelectVolume(disk.path) })
                                }
                            }
                            Text("You can stop a scan at any time and keep whatever it has already found.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        folderDivider

                        FolderScanCardView(
                            recentFolders: HomeMemory.recentFolders(excluding: volumePaths, limit: 3),
                            onChooseFolder: onChooseFolder,
                            onSelectFolder: onSelectFolder
                        )
                    }
                    .frame(width: 600)
                    Spacer(minLength: 32)
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadDisks()
        }
        // Structured concurrency, not a `Timer`: this loop starts when
        // `DiskHomeView` appears and is cancelled automatically the moment
        // it leaves the view hierarchy.
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

    private func returningUserStrip(_ summary: (finishedAt: Date, reclaimableBytes: Int64)) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last scanned \(Self.relativeTimeText(summary.finishedAt))")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(ByteFormatter.string(fromBytes: summary.reclaimableBytes)) reclaimable was found. Those results are still here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("View Results", action: onViewResults)
                .font(.control)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.panelCardRadius)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose what to scan")
                .font(.system(size: 26, weight: .bold))
            Text("A full disk scan reads every file once. That is thorough, and on a large disk it takes a few minutes. Scanning a single folder takes seconds.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No disks found")
                .font(.system(size: 13, weight: .semibold))
            Text("You can still scan a folder below, or try again.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Retry", action: loadDisks)
                .font(.control)
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var folderDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            Text("or scan one folder")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }

    private static func relativeTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        return Calendar.current.isDateInToday(date) ? "Today \(time)" : time
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
                let values = try url.resourceValues(forKeys: [
                    .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .nameKey, .volumeLocalizedFormatDescriptionKey
                ])

                guard let totalSize = values.volumeTotalCapacity,
                      let availableSize = values.volumeAvailableCapacity,
                      let name = values.name else { continue }

                let interconnect = DiskTelemetryService.interconnectKind(atPath: path)
                let isInternal = interconnect?.isInternal ?? true
                let kindLabel = isInternal
                    ? "Internal · \(values.volumeLocalizedFormatDescription ?? "APFS")"
                    : "External · \(interconnect?.protocolName ?? "External")"

                diskList.append(
                    DiskInfo(
                        name: name,
                        path: path,
                        totalSize: Int64(totalSize),
                        availableSize: Int64(availableSize),
                        isInternal: isInternal,
                        kindLabel: kindLabel
                    )
                )
            } catch {
                continue
            }
        }

        diskList.sort { $0.usedSize > $1.usedSize }
        self.disks = diskList
    }
}

/// The scan target itself, per the design handoff: "the whole card is the
/// click target... there is no arrow or button glyph on the card - the
/// heading already says 'Choose what to scan'." Deliberately reads
/// `metrics.cornerRadius` only, not `isCapsule`, the same reasoning
/// `SafetyBadge` documents for its own corner-radius choice - this is a
/// wide card, not a compact pill button.
private struct VolumeCardView: View {
    let disk: DiskInfo
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(disk.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(disk.kindLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.progressTrack)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(barGradient)
                            .frame(width: geometry.size.width * max(0, min(1, disk.usagePercentage / 100)))
                    }
                }
                .frame(height: 5)
                .padding(.top, 2)

                Text("\(ByteFormatter.string(fromBytes: disk.availableSize)) free of \(ByteFormatter.string(fromBytes: disk.totalSize))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)

                estimateRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isHovering ? Color.accentColor.opacity(0.08) : Color.opaqueTertiaryFill,
                in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius)
                    .strokeBorder(isHovering ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isHovering ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }

    private var barGradient: LinearGradient {
        disk.usagePercentage > 80
            ? LinearGradient(colors: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [Color.accentColor], startPoint: .leading, endPoint: .trailing)
    }

    private var estimateRow: some View {
        let estimate = ScanEstimate.forVolume(disk)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(estimate.figure)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(estimate.basis)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

/// The three cases in the design handoff's estimate table. Deliberately a
/// range with its basis always stated, never a single confident number -
/// "macOS gives no cheap file count, so a first-run figure is extrapolated
/// from used bytes and will sometimes be wrong by a factor. A range that
/// names its own basis survives being wrong."
private enum ScanEstimate {
    static func forVolume(_ disk: DiskInfo) -> (figure: String, basis: String) {
        guard disk.isInternal else {
            return ("Time unknown", "external volume - speed depends on the connection, so DustEater will not guess")
        }
        if let remembered = HomeMemory.scan(atPath: disk.path) {
            return (
                minuteRange(forItemCount: remembered.itemCount),
                "\(formattedItemCount(remembered.itemCount)) items last time - a scan of this disk reads every one of them"
            )
        } else {
            let estimatedItems = Int(Double(disk.usedSize) / 1_000_000_000 * itemsPerUsedGB)
            return (
                "Usually \(minuteRange(forItemCount: estimatedItems))",
                "for a disk this size; DustEater will know precisely after the first scan"
            )
        }
    }

    /// A rough real-world throughput range for the main scan walk, not a
    /// measured constant - the fast end assumes an unloaded SSD with
    /// nothing else contending for `BlockingIO`, the slow end assumes real
    /// contention. Picked so a 10.2M-item disk (the design handoff's own
    /// worked example) lands on exactly "2-4 minutes"; recorded here so a
    /// future session can recalibrate against real benchmark data rather
    /// than guessing why these particular numbers were chosen.
    private static let fastItemsPerMinute: Double = 85_000 * 60
    private static let slowItemsPerMinute: Double = 42_500 * 60
    /// Items-per-used-GB for the first-run case, where there is no
    /// remembered item count to extrapolate from at all - a coarse stand-in
    /// for "macOS gives no cheap file count."
    private static let itemsPerUsedGB: Double = 20_000

    private static func minuteRange(forItemCount itemCount: Int) -> String {
        guard itemCount > 0 else { return "under a minute" }
        let lowRaw = Double(itemCount) / fastItemsPerMinute
        let highRaw = Double(itemCount) / slowItemsPerMinute
        guard highRaw >= 1 else { return "under a minute" }
        let lowMinutes = max(1, Int(lowRaw.rounded()))
        let highMinutes = max(lowMinutes, Int(highRaw.rounded()))
        return lowMinutes == highMinutes ? "\(lowMinutes) minutes" : "\(lowMinutes)-\(highMinutes) minutes"
    }

    private static func formattedItemCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

/// "Useful when you already know where the space went - Downloads, a
/// project directory, an old backup." The recents are what make this path
/// fast to re-use; without them it's a file dialog nobody opens twice.
private struct FolderScanCardView: View {
    let recentFolders: [(path: String, scan: RecordedScan)]
    let onChooseFolder: () -> Void
    let onSelectFolder: (String) -> Void

    /// On a first run there are no recents - a size is only known for a
    /// folder already scanned - so these show bare, with no size, rather
    /// than leaving an empty row that reads as a broken card.
    private static let bareDefaults = ["~/Downloads", "~/Desktop", "~/Documents"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scan a folder instead")
                    .font(.system(size: 15, weight: .semibold))
                Text("Useful when you already know where the space went - Downloads, a project directory, an old backup. Finishes in seconds.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button("Choose Folder…", action: onChooseFolder)
                .font(.control)
                .buttonStyle(.bordered)

            pillsRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.panelCardRadius)
    }

    @ViewBuilder
    private var pillsRow: some View {
        if recentFolders.isEmpty {
            HStack(spacing: 8) {
                ForEach(Self.bareDefaults, id: \.self) { path in
                    folderPill(label: path, sizeText: nil, fullPath: (path as NSString).expandingTildeInPath)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(recentFolders, id: \.path) { entry in
                    folderPill(
                        label: (entry.path as NSString).abbreviatingWithTildeInPath,
                        sizeText: ByteFormatter.string(fromBytes: entry.scan.sizeBytes),
                        fullPath: entry.path
                    )
                }
            }
        }
    }

    private func folderPill(label: String, sizeText: String?, fullPath: String) -> some View {
        Button(action: { onSelectFolder(fullPath) }) {
            HStack(spacing: 6) {
                Text(label)
                if let sizeText {
                    Text(sizeText).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11).monospaced())
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(Color.opaqueTertiaryFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

#Preview {
    DiskHomeView(
        lastScanSummary: nil,
        onSelectVolume: { _ in },
        onChooseFolder: {},
        onSelectFolder: { _ in },
        onViewResults: {}
    )
}
