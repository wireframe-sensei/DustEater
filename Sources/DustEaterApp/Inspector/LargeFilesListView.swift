import SwiftUI
import DustEaterCore

/// One row of the large-files list. Row focus is driven by
/// `List(selection:)` in `DuplicatesView`, not a manual `.onTapGesture` -
/// see `DuplicateSetRow`'s doc comment for why that's a deliberate switch
/// away from a hand-rolled approximation, and why the `List` itself is
/// built directly in `DuplicatesView` rather than wrapped in an
/// intermediate view here (nesting `List(selection:)`'s `ForEach` behind
/// another custom view is an unnecessary risk to its selection tracking
/// for no benefit).
///
/// `isSelected` is a plain value, not tied to row focus - it reflects
/// whether this file is marked for *deletion* in the detail pane's
/// `FileFactsCard`, a different concept from which row is currently open.
struct LargeFileRow: View {
    let entry: LargeFileEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DustEaterTheme.Spacing.sm) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.file.path))
                .resizable()
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.file.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? .secondary : .primary)
                    .strikethrough(isSelected)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Deliberately "Last used", not "Last accessed" - see
                // `LargeFileEntry.lastUsedDate`'s doc comment for why raw
                // filesystem access time isn't trustworthy on macOS.
                if let lastUsed = entry.lastUsedDate {
                    Text("Last used \(lastUsed.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Last used: Unknown")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isSelected {
                Text("Marked")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(ByteFormatter.string(fromBytes: entry.file.logicalSize))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
