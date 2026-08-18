import SwiftUI
import DustEaterCore

/// The payoff screen after a commit: the reclaimed total counted up, a
/// before/after free-space card, and - for a Trash commit only - Undo/Put
/// Back. The one animated moment in the app; everything else follows the
/// platform.
struct ReceiptView: View {
    let reclaimedBytes: Int64
    let freeBefore: Int64
    let freeAfter: Int64
    let permanently: Bool
    let canUndo: Bool
    let monitoringSettings: MonitoringSettingsStore
    let onUndo: () -> Void
    let onBackToCleanup: () -> Void

    @State private var displayedBytes: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(nsColor: .systemGreen))

            VStack(spacing: 6) {
                Text("RECLAIMED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Text(ByteFormatter.string(fromBytes: Int64(displayedBytes)))
                    .font(.system(size: 62, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText(value: displayedBytes))
                Text(permanently
                    ? "Deleted permanently. Space is already free."
                    : "Moved to the Trash. Space is fully released when you empty it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Free before").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(ByteFormatter.string(fromBytes: freeBefore)).font(.system(size: 15, weight: .medium).monospacedDigit())
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                VStack(spacing: 2) {
                    Text("Free now").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(ByteFormatter.string(fromBytes: freeAfter))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(nsColor: .systemGreen))
                }
            }
            .padding(16)
            .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
            .hairlineRing(cornerRadius: CleanupMetrics.panelCardRadius)

            HStack(spacing: 12) {
                if canUndo {
                    Button {
                        onUndo()
                    } label: {
                        Label("Undo - Put Back", systemImage: "arrow.uturn.backward")
                    }
                    .font(.control)
                    .buttonStyle(.bordered)
                }

                Button("Back to Cleanup", action: onBackToCleanup)
                    .font(.control)
                    .buttonStyle(.borderedProminent)
            }

            if !monitoringSettings.showInMenuBar {
                keepWatchingCard
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                displayedBytes = Double(reclaimedBytes)
            }
        }
    }

    /// The other entry point into item 8's monitoring, alongside the
    /// Settings window - offered here because right after a cleanup is
    /// exactly when "keep watching so this doesn't build back up" reads as
    /// useful rather than as an interruption.
    private var keepWatchingCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep watching this disk")
                    .font(.system(size: 13, weight: .semibold))
                Text("Show free space in the menu bar and tell you when caches build up again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { monitoringSettings.showInMenuBar },
                set: { monitoringSettings.showInMenuBar = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
    }
}
