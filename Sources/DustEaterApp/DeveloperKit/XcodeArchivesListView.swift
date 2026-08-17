import SwiftUI
import AppKit
import DustEaterCore

/// Per-archive drill-in list: browse, Reveal in Finder, and delete one
/// specific archive at a time - the only shape a delete action for Archives
/// takes at all, per `PurgeCatalog.definitions`'s doc comment on why Archives
/// never becomes a bulk-selectable `PurgeTarget`. Opened from the Xcode
/// build artifacts finding's footer action in `CleanupShellView`.
struct XcodeArchivesListView: View {
    @Binding var archives: [XcodeArchive]
    /// Reports the deleted archive's path back up so the caller can
    /// reconcile it out of the live scan tree and the Cleanup findings.
    let onDeleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var archiveToDelete: XcodeArchive?
    @State private var showDeleteAlert = false
    @State private var deleteErrorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List(archives) { archive in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(archive.appName)
                            .font(.control)
                        Text(archive.creationDate.map(Self.dateFormatter.string(from:)) ?? "Unknown date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(ByteFormatter.string(fromBytes: archive.sizeBytes))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: archive.path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")

                    Button(role: .destructive) {
                        archiveToDelete = archive
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this archive")
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .navigationTitle("Xcode Archives")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.control)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .alert("Delete Archive", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let archiveToDelete { delete(archiveToDelete, permanently: false) }
            }
            Button("Delete Permanently", role: .destructive) {
                if let archiveToDelete { delete(archiveToDelete, permanently: true) }
            }
        } message: {
            if let archiveToDelete {
                Text("\"\(archiveToDelete.appName)\" holds the only dSYM for that build. This can't be undone, and rebuilding won't replace it.")
            }
        }
        .alert("Couldn't Delete Archive", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in if !isPresented { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private func delete(_ archive: XcodeArchive, permanently: Bool) {
        // TOCTOU guard, same reasoning as `CleanupCommitter.commit`.
        guard FileManager.default.fileExists(atPath: archive.path) else {
            archives.removeAll { $0.path == archive.path }
            return
        }
        do {
            try FileOperations.delete(at: archive.path, permanently: permanently)
            archives.removeAll { $0.path == archive.path }
            onDeleted(archive.path)
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}
