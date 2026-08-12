import SwiftUI
import DustEaterCore

struct HealthGaugeView: View {
    let title: String
    let value: Double?
    let status: DiskHealthStatus

    var gaugeColor: Color {
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
        VStack(spacing: 12) {
            if let value = value {
                Gauge(value: value / 100.0) {
                    Text("")
                } currentValueLabel: {
                    Text("\(Int(value))%")
                        .font(.title2.bold())
                        .foregroundStyle(gaugeColor)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(gaugeColor)
                .scaleEffect(1.8)
                .frame(height: 140)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "dash.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(nsColor: .systemGray))
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 140)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            HealthGaugeView(title: "Wear Level", value: 75, status: .passed)
            HealthGaugeView(title: "Wear Level", value: 45, status: .warning)
        }
        HStack(spacing: 16) {
            HealthGaugeView(title: "Storage Used", value: nil, status: .unknown)
            HealthGaugeView(title: "Wear Level", value: 20, status: .critical)
        }
    }
    .padding()
}
