import SwiftUI
import DustEaterCore

struct DiskHealthView: View {
    let onBackToHome: () -> Void

    @State private var service = DiskTelemetryService()
    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                switch service.state {
                case .idle:
                    EmptyView()

                case .scanning:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Scanning disks...")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                    .controlSize(.large)
                    .frame(maxHeight: .infinity)

                case .loaded(let disks):
                    if disks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "internaldrive.slash")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No Disks Found")
                                .font(.headline)
                            Text("Unable to detect any disks")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Retry", action: { service.refresh() })
                                .font(.control)
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 20) {
                                ForEach(disks) { disk in
                                    diskSection(for: disk)
                                }
                            }
                            .padding(20)
                        }
                    }

                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Couldn't Scan Disks")
                            .font(.headline)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Retry", action: { service.refresh() })
                            .font(.control)
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Disk Health")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onBackToHome) {
                        Label("Home", systemImage: "house")
                    }
                    .help("Back to home screen")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { service.refresh() }) {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Refresh disk health data")
                    .disabled(service.state == .scanning)
                }
            }
        }
        .task {
            service.refresh()
        }
    }

    private func diskSection(for disk: PhysicalDiskHealth) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(disk.displayName)
                            .font(.headline)
                        if disk.isSystemDisk {
                            Text("System Disk")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 16) {
                        Text(disk.mediumType.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let interconnectProtocol = disk.interconnectProtocol {
                            Text(interconnectProtocol)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(disk.interconnect.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ByteFormatter.string(fromBytes: disk.totalCapacity))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Text("Total Capacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    HealthGaugeView(
                        title: "Wear Level",
                        value: disk.wearLevelPercent,
                        status: disk.overallHealthStatus
                    )

                    HealthGaugeView(
                        title: "Storage Used",
                        value: disk.totalCapacity > 0 ? Double(disk.totalCapacity - disk.availableCapacity) / Double(disk.totalCapacity) * 100 : nil,
                        status: disk.purgeableBytes > 100_000_000 ? .warning : .passed
                    )
                }

                VStack(spacing: 8) {
                    MetricCardView(
                        icon: "thermometer",
                        title: "Temperature",
                        value: disk.temperatureCelsius.map { String(format: "%.1f°C", $0) },
                        status: disk.temperatureCelsius.map { $0 >= 65 ? .warning : .passed } ?? .unknown
                    )

                    MetricCardView(
                        icon: "square.and.arrow.up",
                        title: "Total Bytes Written",
                        value: disk.totalBytesWritten.map { ByteFormatter.string(fromBytes: $0) },
                        status: .passed
                    )

                    MetricCardView(
                        icon: "heart.circle",
                        title: "SMART Status",
                        value: {
                            switch disk.smartStatus {
                            case .verified:
                                return "Verified"
                            case .failing:
                                return "Failing"
                            case .notReported:
                                return nil
                            }
                        }(),
                        status: disk.smartStatus == .failing ? .critical : (disk.smartStatus == .verified ? .passed : .unknown)
                    )

                    MetricCardView(
                        icon: "clock.circle",
                        title: "Local Snapshots",
                        value: disk.localSnapshotCount > 0 ? "\(disk.localSnapshotCount)" : nil,
                        status: .passed
                    )
                }

                PurgeableSpaceSection(
                    disk: disk,
                    reclaimState: service.reclaimState,
                    onReclaimTap: { service.reclaimPurgeableSpace(forVolumeAt: disk.bsdName) }
                )
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    DiskHealthView(onBackToHome: {})
}
