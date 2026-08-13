import SwiftUI
import DustEaterCore

/// One row of the duplicates list: a flat summary of the whole set (icon,
/// representative name, per-copy size, copy count, selection status, and
/// reclaimable bytes) - not an expandable disclosure. Selecting the row
/// (native `List(selection:)`, not a manual tap gesture - see
/// `DuplicatesView`) opens `DuplicateSetOverview`, which already lists
/// every file with its own full path, so there's nothing a per-file row
/// here would add that the overview doesn't already show.
///
/// This view owns no selection mechanism itself. An earlier version drove
/// row focus with `.onTapGesture` scoped to just the icon/name area plus a
/// manually-drawn background highlight - a hand-rolled approximation of
/// what `List(selection:)` already does correctly (full-row hit target,
/// native highlight, hover state, keyboard up/down navigation), and the
/// approximation's scoped tap area was exactly the kind of "clicking the
/// size column does nothing" mismatch that gave it away as not-quite-native.
/// `AppManagerView`'s row list already establishes the correct pattern in
/// this codebase; this now follows it.
///
/// Purely a picker - selecting files for *deletion* happens in the
/// overview, not here, so this view only ever *reads* `DuplicateSelectionState`
/// for the "N selected" badge and never mutates it.
///
/// The row shows the *newest* copy's name (`duplicateSet.files.first`,
/// since `DuplicateSet.files` is sorted newest-first) as a representative
/// label - files in a set are byte-identical, not necessarily identically
/// named, but literal copies overwhelmingly share the same or a
/// near-identical name, and the full path of every copy is always one tap
/// away in the overview regardless.
///
/// The property is named `duplicateSet`, not `set` - `set` is a contextual
/// keyword Swift's parser reaches for whenever it's the first token inside
/// a computed property body (as in `selectedCount` below), so using it as
/// a stored property name is a real footgun, not just a style preference.
struct DuplicateSetRow: View {
    let duplicateSet: DuplicateSet
    let selection: DuplicateSelectionState

    private var selectedCount: Int {
        duplicateSet.files.filter { selection.isSelected($0.path) }.count
    }

    /// True when every copy, including the original, is marked - a
    /// meaningfully different outcome from the usual "keep the newest,
    /// delete the rest" case, so it gets a distinct warning color rather
    /// than blending into the normal accent-colored selection badge.
    private var isFullyMarkedForDeletion: Bool {
        selectedCount > 0 && selectedCount == duplicateSet.files.count
    }

    var body: some View {
        HStack(spacing: DustEaterTheme.Spacing.sm) {
            ThumbnailImageView(path: duplicateSet.files.first?.path ?? "", size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(duplicateSet.files.first?.name ?? "Unknown")
                    .font(.control)
                    .lineLimit(1)
                Text("\(ByteFormatter.string(fromBytes: duplicateSet.fileSize)) \u{00B7} \(duplicateSet.files.count) copies")
                    .font(DustEaterTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedCount > 0 {
                Text(isFullyMarkedForDeletion ? "All \(selectedCount) marked" : "\(selectedCount) selected")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isFullyMarkedForDeletion ? Color.orange : Color.accentColor).opacity(0.15))
                    .foregroundStyle(isFullyMarkedForDeletion ? .orange : Color.accentColor)
                    .clipShape(Capsule())
            }

            Text(ByteFormatter.string(fromBytes: duplicateSet.wastedBytes))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
