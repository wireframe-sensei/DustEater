import SwiftUI
import DustEaterCore

/// Destructive confirmation for a batch delete from either the duplicates
/// or large-files tab. Modeled directly on App Manager's
/// `UninstallConfirmationSheet`: animated byte counter, scrollable file
/// list, in-button progress while deleting, and errors accumulated and
/// shown rather than silently swallowed.
///
/// Offers both Move to Trash and Delete Permanently, matching the existing
/// single-item delete alert in `MainContentView` - unlike App Manager's
/// uninstall sheet, which is trash-only.
struct DuplicateCleanConfirmationSheet: View {
    let filesToDelete: [InspectedFile]
    let totalBytesToReclaim: Int64
    /// Names of files where every copy is included in this delete - see
    /// `DuplicatesView.fullyDeletedFileNames`. Empty in the common case
    /// (some duplicates removed, one kept); when non-empty, this delete
    /// would remove the file entirely, not just reclaim duplicate storage,
    /// which gets its own explicit warning banner below rather than
    /// blending into the routine "delete N files" framing.
    var fullyDeletedFileNames: [String] = []

    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onConfirm: (_ permanently: Bool) -> Void

    @State private var displayedBytes: Int64 = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red.opacity(0.7))

                Text("Review & Clean")
                    .font(.headline)

                Text("Delete \(filesToDelete.count) file\(filesToDelete.count == 1 ? "" : "s")?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            VStack(spacing: 8) {
                Text("You'll recover")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(ByteFormatter.string(fromBytes: displayedBytes))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            if !fullyDeletedFileNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No Copies Will Remain")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text("Every copy of \(fullyDeletedFileNames.count == 1 ? "\u{201C}\(fullyDeletedFileNames[0])\u{201D}" : "\(fullyDeletedFileNames.count) files") is selected. This removes the file entirely, not just duplicate copies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Files to remove:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filesToDelete) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(file.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(ByteFormatter.string(fromBytes: file.logicalSize))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(nsColor: .separatorColor).opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            .frame(maxHeight: 200)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .font(.control)
                .buttonStyle(.bordered)
                .disabled(isDeleting)

                Spacer()

                Button("Delete Permanently") {
                    onConfirm(true)
                }
                .font(.control)
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isDeleting)

                Button {
                    onConfirm(false)
                } label: {
                    if isDeleting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
                .font(.control)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
            .padding(20)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                displayedBytes = totalBytesToReclaim
            }
        }
    }
}
