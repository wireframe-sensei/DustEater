import SwiftUI
import DustEaterCore

/// The menu bar item's dropdown - shown in an `NSPopover`, not a plain
/// `NSMenu`: the header's live figures, colored finding dots, and a filled
/// prominent button aren't representable in a system menu's plain-text
/// items, the same reasoning `ScanningCardView`'s hand-drawn ring already
/// established for custom-drawn-when-the-system-control-can't-do-it.
struct MenuBarDropdownView: View {
    let volumeName: String
    let freeBytes: Int64
    let purgeableBytes: Int64
    let result: MonitoringCheckResult?
    let isPaused: Bool
    let onReview: () -> Void
    let onRescan: () -> Void
    let onTogglePause: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var reclaimableBytes: Int64 { result?.reclaimableBytes ?? 0 }
    private var topFindings: [CleanupFinding] { result?.topFindingsForMenu ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            Text("RECLAIMABLE — \(ByteFormatter.string(fromBytes: reclaimableBytes))")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            ForEach(topFindings) { finding in
                findingRow(finding)
            }
            if topFindings.isEmpty {
                Text("Nothing found yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }

            Button(action: onReview) {
                Text("Review in DustEater")
                    .font(.control)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().padding(.vertical, 6)

            MenuRow(title: "Rescan Now", shortcut: "⌘R", action: onRescan)
            MenuRow(title: isPaused ? "Resume Monitoring" : "Pause Monitoring", shortcut: nil, action: onTogglePause)
            MenuRow(title: "Monitoring Settings…", shortcut: nil, action: onOpenSettings)

            Divider().padding(.vertical, 6)

            MenuRow(title: "Quit DustEater", shortcut: "⌘Q", action: onQuit)

            Text("Last checked \(lastCheckedText) · fast checks only")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
        .padding(.vertical, 10)
        .frame(width: 268)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(volumeName)
                .font(.system(size: 13, weight: .semibold))
            Text("\(ByteFormatter.string(fromBytes: freeBytes)) free · \(ByteFormatter.string(fromBytes: purgeableBytes)) purgeable")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }

    private func findingRow(_ finding: CleanupFinding) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor(for: finding.id)).frame(width: 6, height: 6)
            Text(finding.id.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ByteFormatter.string(fromBytes: finding.reclaimableBytes))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
    }

    private func dotColor(for id: CleanupFindingID) -> Color {
        switch id {
        case .packageManagerCaches: Color(nsColor: .systemTeal)
        case .unusedApplications: Color(nsColor: .systemOrange)
        case .oldDownloads: Color(nsColor: .systemGreen)
        case .xcodeBuildArtifacts: Color(nsColor: .systemBlue)
        case .duplicateFiles: Color(nsColor: .systemPurple)
        case .simulatorRuntimes: Color(nsColor: .systemGray)
        }
    }

    private var lastCheckedText: String {
        guard let checkedAt = result?.checkedAt else { return "never" }
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(checkedAt) ? .none : .short
        formatter.timeStyle = .short
        let time = formatter.string(from: checkedAt)
        return Calendar.current.isDateInToday(checkedAt) ? "Today \(time)" : time
    }
}

/// A plain-text row with hover highlight - the dropdown's non-header,
/// non-button actions (Rescan Now, Pause Monitoring, Monitoring Settings…,
/// Quit), styled closer to a real `NSMenu` item than a bordered button.
private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(isHovering ? Color.opaqueTertiaryFill : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
