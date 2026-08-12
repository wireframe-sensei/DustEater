import SwiftUI

struct DiskHealthCardView: View {
    let onTap: () -> Void
    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Health")
                        .font(.control)
                        .foregroundStyle(.primary)
                    Text("SSD wear, temperature & purgeable space")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 160)
            .padding(16)
            .contentShape(Rectangle())
            .glassBackground(.ultraThinMaterial, cornerRadius: metrics.cornerRadius)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

#Preview {
    DiskHealthCardView(onTap: {})
        .frame(width: 320, height: 160)
}
