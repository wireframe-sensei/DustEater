import SwiftUI
import DustEaterCore

/// A read-only breakdown of what deleting this app would remove -
/// application bundle, caches, application support, preferences and
/// (via `RelatedStorageCategory`'s existing five cases) the other related
/// storage macOS associates with it. Deliberately has no selection state,
/// no confirmation sheet, and no delete button of its own any more: an
/// uninstall is now decided by checking the row's own checkbox in the list
/// (feeding the shared `SelectionStore`) and committed from Review, the one
/// commit point in the app. This view's only job is answering "what would
/// that actually remove" before you check the box.
struct AppDetailInspector: View {
    let row: AppRowItem

    var relatedItems: [RelatedStorageItem] {
        switch row.source {
        case .installed(let entity): entity.relatedItems
        case .orphaned(let orphan): orphan.items
        case .developerTool(let tool): tool.items
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                breakdownSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(row.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if case .installed(let entity) = row.source {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entity.appPath))
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "questionmark.app")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if case .installed(let entity) = row.source, let bundleID = entity.bundleIdentifier {
                        Text(bundleID)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            HStack(spacing: 20) {
                factColumn(label: "Total Size", value: ByteFormatter.string(fromBytes: row.trueFootprint))
                factColumn(
                    label: "Last Opened",
                    value: row.lastOpenedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "-"
                )
            }
            .padding(10)
            .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.rowCardRadius))
        }
    }

    private func factColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }

    /// The primary content of this pane, per the design handoff: "the
    /// detail panel becomes a breakdown of what an uninstall would remove
    /// - application bundle, caches, application support, preferences and
    /// logs, each with its path and size. Not just app metadata." The
    /// existing `RelatedStorageCategory` cases (Application Support,
    /// Caches, Containers, Saved State, Preferences) are what the scanner
    /// actually discovers today - shown under their real labels rather
    /// than inventing a literal "Logs" category with no data behind it.
    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT WOULD BE REMOVED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                if case .installed(let entity) = row.source {
                    breakdownRow(
                        icon: "app.badge",
                        title: "Application Bundle",
                        path: entity.appPath,
                        size: entity.appBundleSize
                    )
                }
                ForEach(relatedItems) { item in
                    breakdownRow(
                        icon: categoryIcon(item.category),
                        title: item.category.rawValue,
                        path: item.path,
                        size: item.size
                    )
                }
            }

            if relatedItems.isEmpty, case .installed = row.source {
                Text("No related caches, support files, or preferences were found for this app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func breakdownRow(icon: String, title: String, path: String, size: Int64) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(path)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(ByteFormatter.string(fromBytes: size))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(10)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: ExploreMetrics.rowRadius))
    }

    private func categoryIcon(_ category: RelatedStorageCategory) -> String {
        switch category {
        case .applicationSupport: "folder"
        case .caches: "trash"
        case .containers: "square.stack.3d.down.forward"
        case .savedState: "doc.text"
        case .preferences: "gearshape"
        }
    }
}

#Preview {
    AppDetailInspector(
        row: AppRowItem(
            id: "com.example.app",
            displayName: "Example App",
            iconPath: nil,
            lastOpenedDate: Date(),
            trueFootprint: 1024 * 1024 * 500,
            source: .orphaned(OrphanedAppData(
                inferredIdentifier: "com.example.app",
                items: [
                    RelatedStorageItem(category: .caches, path: "/Library/Caches/com.example.app", size: 1024 * 1024 * 100),
                ]
            ))
        )
    )
    .frame(width: 320, height: 500)
}
