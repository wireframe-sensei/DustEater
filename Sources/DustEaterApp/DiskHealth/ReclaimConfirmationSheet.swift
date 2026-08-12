import SwiftUI
import DustEaterCore

struct ReclaimConfirmationSheet: View {
    let disk: PhysicalDiskHealth
    let reclaimState: DiskTelemetryService.ReclaimState
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    @State private var displayedBytes: Int64 = 0
    @Environment(\.dismiss) private var dismiss

    var isReclaiming: Bool {
        if case .reclaiming = reclaimState {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue.opacity(0.7))

                Text("Reclaim Purgeable Space")
                    .font(.headline)

                Text("Remove local Time Machine snapshots?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            VStack(spacing: 8) {
                Text("You'll recover")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ByteFormatter.string(fromBytes: displayedBytes))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("About This Action")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("This will delete local Time Machine snapshots. You will be prompted for your password. This operation may take several minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
            .frame(maxWidth: .infinity)

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .font(.control)
                .buttonStyle(.bordered)
                .disabled(isReclaiming)

                Spacer()

                Button(action: onConfirm) {
                    if isReclaiming {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Reclaim Space", systemImage: "wand.and.stars")
                    }
                }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isReclaiming)
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                displayedBytes = disk.purgeableBytes
            }
        }
    }
}

#Preview {
    ReclaimConfirmationSheet(
        disk: PhysicalDiskHealth(
            bsdName: "disk0s2",
            displayName: "Macintosh HD",
            isSystemDisk: true,
            mediumType: .solidState,
            interconnect: .internal,
            smartStatus: .verified,
            totalCapacity: 1_000_000_000_000,
            purgeableBytes: 50_000_000_000,
            localSnapshotCount: 12,
            isAPFS: true
        ),
        reclaimState: .idle,
        isPresented: .constant(true),
        onConfirm: {}
    )
}
