import SwiftUI
import DustEaterCore

/// Pinned to the bottom of the content area whenever the selection is
/// non-empty - answers "how much have I freed so far?" without arithmetic.
/// `.regularMaterial` since the tray is chrome floating over content, not
/// content itself.
struct SelectionTray: View {
    let selection: SelectionStore
    let onClear: () -> Void
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormatter.string(fromBytes: selection.totalBytes))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text("\(selection.count) item\(selection.count == 1 ? "" : "s") selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if selection.containsCaution {
                Label("Includes items marked Caution", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .background(Color(nsColor: .systemOrange).opacity(0.15), in: Capsule())
            }

            Spacer()

            Button("Clear", action: onClear)
                .font(.control)
                .buttonStyle(.bordered)

            Button("Review...", action: onReview)
                .font(.control)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(nsColor: .separatorColor)), alignment: .top)
    }
}
