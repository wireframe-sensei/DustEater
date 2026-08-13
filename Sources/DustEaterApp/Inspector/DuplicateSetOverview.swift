import SwiftUI
import DustEaterCore

/// One file's full details - a thumbnail (real image preview for image
/// files, generic Finder icon otherwise - see `ThumbnailImageView`), name,
/// full path, size, and dates - with an optional checkbox for deletion
/// selection. Used both for *non-image* duplicate sets in
/// `DuplicateSetOverview` (see `DuplicateImageCard` for the image case) and
/// the large-files detail pane (one card for the selected file, also
/// selectable).
///
/// The checkbox is entirely optional (`isSelected`/`onToggle` default to
/// `nil`): a card with neither set renders as a read-only facts panel, so
/// this same type works for both a selectable context and a purely
/// informational one without two near-duplicate view definitions.
struct FileFactsCard: View {
    let file: InspectedFile
    var lastUsedDate: Date?
    var isSelected: Bool?
    var isLockedSurvivor: Bool = false
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DustEaterTheme.Spacing.md) {
            if let isSelected, let onToggle {
                // Deliberately not `.disabled` - the last remaining copy
                // can still be selected, it's just warned about (the "Last
                // Copy" badge below and this help text) rather than
                // blocked, so someone who genuinely wants every copy of a
                // file gone can do it one explicit click at a time.
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(isLockedSurvivor
                        ? "This is the only remaining copy - selecting it deletes the file entirely"
                        : (isSelected ? "Marked for deletion" : "Not marked for deletion"))
            }

            ThumbnailImageView(path: file.path, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DustEaterTheme.Spacing.xs) {
                    Text(file.name)
                        .font(DustEaterTheme.Typography.headline)
                        .foregroundStyle((isSelected ?? false) ? .secondary : .primary)
                        .strikethrough(isSelected ?? false)
                        .lineLimit(1)

                    if isLockedSurvivor {
                        Text("Last Copy")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                Text(file.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: DustEaterTheme.Spacing.md) {
                    Label(ByteFormatter.string(fromBytes: file.logicalSize), systemImage: "internaldrive")
                    Label(file.modifiedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    if let lastUsedDate {
                        Label("Last used \(lastUsedDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "eye")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(DustEaterTheme.Spacing.md)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(DustEaterTheme.Radius.md)
    }
}

/// A selectable image tile for one duplicate copy - thumbnail-forward, with
/// the selection checkbox overlaid on the thumbnail itself (top-left) and
/// file details below, matching Photos.app's own duplicate-review grid
/// (photo tile + selection badge, not a text-first row). The whole card is
/// one tap target, not just the small badge - consistent with this app's
/// established preference for full-target hit areas over precise small
/// controls (see `DuplicateSetRow`'s move to `List(selection:)` for the
/// same reasoning).
///
/// Used only for image duplicate sets (`DuplicateSetOverview.isImageSet`).
/// Every file in a set is byte-identical, so each card showing the same
/// picture is expected, not redundant here - unlike a single hero preview
/// shown once, each card is the actual click target for selecting *that*
/// specific copy, and repeating the thumbnail is what makes every card a
/// self-sufficient selectable unit at a glance.
private struct DuplicateImageCard: View {
    let file: InspectedFile
    let isSelected: Bool
    let isLockedSurvivor: Bool
    let onToggle: () -> Void

    private static let thumbnailSize: CGFloat = 160

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.xs) {
                ThumbnailImageView(path: file.path, size: Self.thumbnailSize)
                    .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topLeading) {
                        selectionBadge
                            .padding(6)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DustEaterTheme.Radius.sm)
                                .stroke(Color.accentColor, lineWidth: 3)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DustEaterTheme.Spacing.xs) {
                        Text(file.name)
                            .font(.control)
                            .foregroundStyle(isSelected ? .secondary : .primary)
                            .strikethrough(isSelected)
                            .lineLimit(1)

                        if isLockedSurvivor {
                            Text("Last Copy")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(file.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(ByteFormatter.string(fromBytes: file.logicalSize)) \u{00B7} \(file.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.thumbnailSize, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(file.name), \(isSelected ? "marked for deletion" : "not marked for deletion")"))
        .help(isLockedSurvivor
            ? "This is the only remaining copy - selecting it deletes the file entirely"
            : (isSelected ? "Marked for deletion" : "Not marked for deletion"))
    }

    /// A circular badge, not a plain checkbox - needs to stay legible over
    /// arbitrary photo content behind it, the same problem Photos.app's own
    /// selection circle solves the same way (opaque backing regardless of
    /// what's under it, rather than relying on contrast with the image).
    ///
    /// Built manually with a `ZStack` rather than SF Symbols' `.palette`
    /// rendering mode: `checkmark.circle.fill` is multi-layer and would
    /// take two colors correctly, but the unselected state's plain `circle`
    /// is a single-layer outline symbol - palette mode has no second layer
    /// to apply a secondary color to there, so the dark backing would
    /// silently disappear behind a bright photo instead of scaling both
    /// states consistently.
    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.white : Color.black.opacity(0.35))
                .frame(width: 20, height: 20)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? Color.accentColor : Color.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

/// Detail-pane content shown when a duplicate *group* (not an individual
/// file) is selected. For image sets, a grid of `DuplicateImageCard` tiles
/// (thumbnail + overlaid checkbox + details below, one per copy); for
/// everything else, the existing stacked `FileFactsCard` list. Every file in
/// a set is byte-identical (`DuplicateDetector` hashes with SHA-256), so
/// there's nothing to visually *compare* between copies the way Photos.app's
/// near-duplicate detector needs - but each card is still the click target
/// for selecting that specific copy, which is why the grid repeats the same
/// picture per card rather than showing one shared preview: it's not a
/// comparison aid, it's what makes each tile a self-sufficient selectable
/// unit.
///
/// This is the *only* place duplicate selection happens now - the sidebar
/// list is a read-only picker (see `DuplicateSetRow`), so the selection
/// controls here are this set's sole bulk-selection entry point outside the
/// Smart Select menu.
///
/// "Review & Clean This Set" is deliberately separate from the floating
/// action bar's whole-tab "Review & Clean": selection is a single
/// `Set<String>` shared across every set, so without a scoped action, a
/// user reviewing this one set would have no way to act on just what's
/// selected *here* without also sweeping in whatever's still selected in
/// other sets they've since navigated away from - confusing precisely
/// because nothing on screen would show that a global action was about to
/// touch files outside this set.
struct DuplicateSetOverview: View {
    // Named `duplicateSet`, not `set` - see `DuplicateSetRow`'s doc comment
    // for why `set` as a stored property name is a real parser footgun
    // (Swift reaches for the `set { }` accessor keyword whenever it's the
    // first token inside a computed property body).
    let duplicateSet: DuplicateSet
    @Binding var selection: DuplicateSelectionState
    let onReviewAndClean: (_ selectedFiles: [InspectedFile]) -> Void

    private var isAllSelected: Bool {
        selection.selectAllState(for: duplicateSet) == .all
    }

    /// True only when *every* file, including the original, is already
    /// selected - once true, "Include Original" has nothing left to do, so
    /// it disappears rather than sitting there as a no-op.
    private var isEverySingleFileSelected: Bool {
        duplicateSet.files.allSatisfy { selection.isSelected($0.path) }
    }

    private var selectedFilesInSet: [InspectedFile] {
        duplicateSet.files.filter { selection.isSelected($0.path) }
    }

    private var isImageSet: Bool {
        guard let representative = duplicateSet.files.first else { return false }
        return ImageFileDetector.isImage(atPath: representative.path)
    }

    private static let imageGridColumns = [GridItem(.adaptive(minimum: 160), spacing: DustEaterTheme.Spacing.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                HStack {
                    Text("\(duplicateSet.files.count) copies \u{00B7} \(ByteFormatter.string(fromBytes: duplicateSet.fileSize)) each \u{00B7} \(ByteFormatter.string(fromBytes: duplicateSet.wastedBytes)) reclaimable")
                        .font(DustEaterTheme.Typography.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Kept as a separate, distinctly-styled button rather
                    // than folded into "Select All" as a toggle state -
                    // this removes every copy of the file, not just
                    // duplicate storage, and that's a deliberately
                    // different, more consequential action than the one
                    // "Select All" performs.
                    if !isEverySingleFileSelected {
                        Button("Include Original") {
                            selection.selectAllIncludingOriginal(in: duplicateSet)
                        }
                        .font(.control)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                        .help("Also selects the last remaining copy - no copies of this file will be left")
                    }

                    Button(isAllSelected ? "Deselect All" : "Select All") {
                        if isAllSelected {
                            selection.deselectAll(in: duplicateSet)
                        } else {
                            selection.selectAll(in: duplicateSet)
                        }
                    }
                    .font(.control)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Selects every copy except the newest")

                    if !selectedFilesInSet.isEmpty {
                        Divider().frame(height: 16)

                        Button {
                            onReviewAndClean(selectedFilesInSet)
                        } label: {
                            Label("Review & Clean This Set", systemImage: "trash")
                        }
                        .font(.control)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .help("Reviews and deletes only what's selected in this set - not the whole tab's selection")
                    }
                }

                if isImageSet {
                    LazyVGrid(columns: Self.imageGridColumns, alignment: .leading, spacing: DustEaterTheme.Spacing.md) {
                        ForEach(duplicateSet.files) { file in
                            DuplicateImageCard(
                                file: file,
                                isSelected: selection.isSelected(file.path),
                                isLockedSurvivor: selection.isLockedSurvivor(file.path, in: duplicateSet),
                                onToggle: { selection.toggle(file.path, in: duplicateSet) }
                            )
                        }
                    }
                } else {
                    ForEach(duplicateSet.files) { file in
                        FileFactsCard(
                            file: file,
                            isSelected: selection.isSelected(file.path),
                            isLockedSurvivor: selection.isLockedSurvivor(file.path, in: duplicateSet),
                            onToggle: { selection.toggle(file.path, in: duplicateSet) }
                        )
                    }
                }
            }
            .padding(DustEaterTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
