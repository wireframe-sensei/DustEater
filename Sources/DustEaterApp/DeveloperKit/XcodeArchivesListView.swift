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

/// Per-archive drill-in list, read-only for now (Reveal in Finder only) -
/// the same "sizes and browsing first, delete action later" staging as
/// `DeveloperKitView` itself.
struct XcodeArchivesListView: View {
    let archives: [XcodeArchive]

    @Environment(\.dismiss) private var dismiss

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
    }
}
