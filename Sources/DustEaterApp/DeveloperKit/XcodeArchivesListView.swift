import SwiftUI
import AppKit
import DustEaterCore

/// The Xcode category's entry point into the Archives drill-in list. Not a
/// `TargetCardView`: Archives never becomes a `PurgeTarget` at all (see
/// `PurgeCatalog.definitions`'s doc comment) since "select the whole
/// Archives folder" isn't a safe action - deleting one specific archive is,
/// and that only happens one row at a time inside `XcodeArchivesListView`.
struct ArchivesSummaryCardView: View {
    let archiveCount: Int
    let totalBytes: Int64
    let onBrowse: () -> Void

    @Environment(\.controlMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Archives")
                    .font(.control)
                    .foregroundStyle(.primary)
                Spacer()
                SafetyBadge(level: .caution)
            }

            Text(ByteFormatter.string(fromBytes: totalBytes))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)

            Text("\(archiveCount) archive\(archiveCount == 1 ? "" : "s") - each holds the dSYM needed to symbolicate crashes from that build. Deleting one is permanent; rebuilding doesn't replace it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(action: onBrowse) {
                    Label("Browse Archives", systemImage: "list.bullet")
                }
                .font(.control)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 150)
        .padding(16)
        .glassBackground(.ultraThinMaterial, cornerRadius: metrics.cornerRadius)
    }
}

/// Per-archive drill-in list: browse, Reveal in Finder, and delete one
/// specific archive at a time - the only shape a delete action for Archives
/// takes at all, per `PurgeCatalog.definitions`'s doc comment on why Archives
/// never becomes a bulk-selectable `PurgeTarget`.
struct XcodeArchivesListView: View {
    @Binding var archives: [XcodeArchive]
    /// Reports the deleted archive's path back up so `DeveloperKitView` can
    /// forward it through the same `onDeleted` contract `DuplicatesView`
    /// uses to reconcile the live scan tree.
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
        // TOCTOU guard, same reasoning as `DeveloperKitView.performPurge`.
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
