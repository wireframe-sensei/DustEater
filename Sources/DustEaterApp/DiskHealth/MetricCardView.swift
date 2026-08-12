import SwiftUI
import DustEaterCore

struct MetricCardView: View {
    let icon: String
    let title: String
    let value: String?
    let status: DiskHealthStatus

    var statusColor: Color {
        switch status {
        case .passed:
            return Color(nsColor: .systemGreen)
        case .warning:
            return Color(nsColor: .systemYellow)
        case .critical:
            return Color(nsColor: .systemRed)
        case .unknown:
            return Color(nsColor: .systemGray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                if status != .unknown && status != .passed {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
            }

            if let value = value {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Not Available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .separatorColor).opacity(0.1))
        .cornerRadius(6)
    }
}

#Preview {
    VStack(spacing: 12) {
        MetricCardView(icon: "thermometer", title: "Temperature", value: "52°C", status: .passed)
        MetricCardView(icon: "square.and.arrow.up", title: "TBW", value: "2.3 TB", status: .warning)
        MetricCardView(icon: "heart.circle", title: "SMART Status", value: "Verified", status: .passed)
        MetricCardView(icon: "clock.circle", title: "Snapshots", value: "12", status: .unknown)
        MetricCardView(icon: "exclamationmark.triangle", title: "Status", value: nil, status: .unknown)
    }
    .padding()
}
