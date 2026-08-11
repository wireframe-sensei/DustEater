import SwiftUI

struct AppManagerCardView: View {
    let onTap: () -> Void
    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor.opacity(0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("App Manager")
                        .font(.control)
                        .foregroundStyle(.primary)
                    Text("Find and remove leftover app data")
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
    AppManagerCardView(onTap: {})
        .frame(width: 320, height: 160)
}
