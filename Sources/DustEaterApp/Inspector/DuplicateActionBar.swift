import SwiftUI
import DustEaterCore

/// Selection action bar, pinned to the bottom of the detail column with a
/// top `Divider` and `.bar` material - the native macOS shape (Mail,
/// Photos) for a persistent selection toolbar, not a floating rounded pill.
/// A floating action button is an iOS convention; see the macOS HIG design
/// system skill.
struct DuplicateActionBar: View {
    let selectedCount: Int
    let reclaimableBytes: Int64
    let onClear: () -> Void
    let onReviewAndClean: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: DustEaterTheme.Spacing.md) {
                Text("\(selectedCount) file\(selectedCount == 1 ? "" : "s") selected")
                    .font(.control)

                Text(ByteFormatter.string(fromBytes: reclaimableBytes))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                Spacer()

                Button("Clear", action: onClear)
                    .font(.control)
                    .buttonStyle(.bordered)

                Button {
                    onReviewAndClean()
                } label: {
                    Label("Review & Clean", systemImage: "trash")
                }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(DustEaterTheme.Spacing.md)
        }
        .background(.bar)
    }
}

#Preview {
    DuplicateActionBar(selectedCount: 12, reclaimableBytes: 1_200_000_000, onClear: {}, onReviewAndClean: {})
}
