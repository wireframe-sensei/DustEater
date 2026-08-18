import SwiftUI
import DustEaterCore

/// Revealed only once a row is focused, never always open. A real
/// `QLThumbnailGenerator` thumbnail fills the preview area
/// (`ThumbnailImageView`), with the type-tinted placeholder as the
/// fallback while it loads or on failure - "nobody deletes a video they
/// cannot see."
struct TypeFilePreviewPane: View {
    let detail: ExploreFileDetail
    let category: FileTypeCategory
    let isSelected: Bool
    let onClose: () -> Void
    let onToggleSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(Color.opaqueTertiaryFill, in: Circle())
                }
                .buttonStyle(.plain)
            }

            ThumbnailImageView(path: detail.path, size: ExploreMetrics.previewThumbnailHeight) {
                ZStack {
                    RoundedRectangle(cornerRadius: DustEaterTheme.Radius.md)
                        .fill(category.accentColor.opacity(0.16))
                    VStack(spacing: 6) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 28))
                            .foregroundStyle(category.accentColor)
                        Text("Press Space for Quick Look")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: ExploreMetrics.previewThumbnailHeight)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(detail.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            factsTable

            if detail.isPhotosManaged {
                Label("Managed by Photos - delete it in the Photos app.", systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if detail.isiCloudSynced {
                Label("Stored in iCloud - deleting it removes it from every device.", systemImage: "icloud")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: detail.path)])
                } label: {
                    Label("Reveal", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !detail.isPhotosManaged {
                    Button(action: onToggleSelect) {
                        Label(isSelected ? "Selected" : "Select", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.control)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ExploreMetrics.previewPaneRadius))
        .padding(10)
    }

    private var factsTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            factRow("Size", ByteFormatter.string(fromBytes: detail.logicalSize))
            factRow("Last opened", detail.lastUsedDate.map(Self.dateFormatter.string(from:)) ?? "Unknown")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: ExploreMetrics.rowRadius))
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11).monospacedDigit())
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
