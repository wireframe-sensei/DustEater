import SwiftUI
import DustEaterCore

/// The Scanning stage of the Cleanup task - shown while `coordinator.state
/// == .scanning`, before the user has tapped Review Findings. Per the
/// design handoff: "make partial findings actionable before the scan
/// completes. A blocking progress bar wastes the user's most attentive
/// thirty seconds." Review Findings is enabled throughout, findings stream
/// in as they're discovered, and Cancel Scan keeps whatever was already
/// found rather than discarding it.
struct ScanningCardView: View {
    let volumeName: String
    let snapshot: ScanProgressSnapshot
    let onReviewFindings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                Text("Findings are ready to act on as they arrive - you don't have to wait for the scan to finish.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.findings) { finding in
                    ScanningFindingRow(finding: finding)
                }
                if !snapshot.inFlightFindingIDs.isEmpty {
                    inFlightRow
                }

                Button("Cancel Scan", action: onCancel)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 20) {
            IndeterminateRing()
                .frame(width: CleanupMetrics.scanningRingDiameter, height: CleanupMetrics.scanningRingDiameter)

            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning \(volumeName) - \(snapshot.itemsScanned.formatted()) items so far")
                    .font(.system(size: 13, weight: .semibold))
                Text(snapshot.currentPath)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Found so far")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(ByteFormatter.string(fromBytes: snapshot.reclaimableBytesFound))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: CleanupMetrics.progressFillDuration), value: snapshot.reclaimableBytesFound)
            }

            Button("Review Findings", action: onReviewFindings)
                .font(.control)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.findingCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.findingCardRadius)
    }

    private var inFlightRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Still looking for \(inFlightDescription)…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(0.42)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.rowCardRadius))
    }

    /// A plain-language list of what's still in flight, e.g. "duplicates
    /// and unused applications" or "duplicates, unused applications, and
    /// Xcode build artifacts" - matches the design handoff's example copy
    /// for the two-item case and extends the same join pattern beyond it.
    private var inFlightDescription: String {
        let names = CleanupFindingID.allCases
            .filter { snapshot.inFlightFindingIDs.contains($0) }
            .map(\.inFlightLabel)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }
}

private extension CleanupFindingID {
    /// Short, lowercase, plain-language form for the in-flight row - the
    /// full `displayName` ("Applications unopened in over a year") reads
    /// as a sentence fragment when joined into "Still looking for
    /// Applications unopened in over a year…".
    var inFlightLabel: String {
        switch self {
        case .packageManagerCaches: "package manager caches"
        case .unusedApplications: "unused applications"
        case .oldDownloads: "old downloads"
        case .xcodeBuildArtifacts: "Xcode build artifacts"
        case .duplicateFiles: "duplicates"
        case .simulatorRuntimes: "simulator runtimes"
        }
    }
}

/// One read-only row for a finding still being shown on the Scanning card -
/// deliberately lighter than `FindingGroupView` (no checkbox, no
/// disclosure, no per-item rows): the real interactive selection UI is
/// what Review Findings navigates to.
private struct ScanningFindingRow: View {
    let finding: CleanupFinding

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.id.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(finding.id.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Text(ByteFormatter.string(fromBytes: finding.reclaimableBytes))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.rowCardRadius))
    }

    private var dotColor: Color {
        switch finding.id {
        case .packageManagerCaches: Color(nsColor: .systemTeal)
        case .unusedApplications: Color(nsColor: .systemOrange)
        case .oldDownloads: Color(nsColor: .systemGreen)
        case .xcodeBuildArtifacts: Color(nsColor: .systemBlue)
        case .duplicateFiles: Color(nsColor: .systemPurple)
        case .simulatorRuntimes: Color(nsColor: .systemGray)
        }
    }
}

/// A continuously rotating arc - the design handoff's "34pt indeterminate
/// ring". A custom shape, not a system `ProgressView`: macOS's own
/// indeterminate `ProgressView` renders as the small multi-dot activity
/// spinner regardless of frame size, not a rotating ring with a visible
/// gap, so there's no system control to defer to here (the small in-flight
/// row's spinner below *does* use a real `ProgressView`, where the system
/// spinner is exactly what's wanted).
private struct IndeterminateRing: View {
    @State private var isRotating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                withAnimation(.scanningRingRotation) {
                    isRotating = true
                }
            }
    }
}
