import SwiftUI
import DustEaterCore

struct PurgeableSpaceSection: View {
    let disk: PhysicalDiskHealth
    let reclaimState: DiskTelemetryService.ReclaimState
    let onReclaimTap: () -> Void
    @State private var showConfirmation = false

    var canReclaim: Bool {
        disk.purgeableBytes > 10_000_000_000 && disk.isAPFS
    }

    var body: some View {
        if disk.isAPFS && disk.purgeableBytes > 100_000_000 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Purgeable Space")
                            .font(.headline)
                        Text("Local Time Machine snapshots and iCloud shadow copies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteFormatter.string(fromBytes: disk.purgeableBytes))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text("\(disk.localSnapshotCount) snapshots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if canReclaim {
                    Button(action: { showConfirmation = true }) {
                        HStack {
                            if case .reclaiming = reclaimState {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text("Reclaim Space Now")
                        }
                    }
                    .font(.control)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(reclaimState == .reclaiming)
                    .sheet(isPresented: $showConfirmation) {
                        ReclaimConfirmationSheet(
                            disk: disk,
                            reclaimState: reclaimState,
                            isPresented: $showConfirmation,
                            onConfirm: onReclaimTap
                        )
                    }
                } else if disk.purgeableBytes > 100_000_000 {
                    Text("Reclaim becomes available when purgeable space exceeds 10 GB")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if case .failed(let message) = reclaimState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }

                if case .succeeded(let bytesFreed) = reclaimState {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Freed \(ByteFormatter.string(fromBytes: bytesFreed))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PurgeableSpaceSection(
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
            onReclaimTap: {}
        )
    }
    .padding()
}
