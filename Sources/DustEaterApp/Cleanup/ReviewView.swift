import SwiftUI
import DustEaterCore

/// The only commit point in the app - everything about to leave the disk,
/// grouped by finding, with a per-item remove and a Trash/Permanent choice.
struct ReviewView: View {
    let selection: SelectionStore
    let onBack: () -> Void
    let onCommit: (_ permanently: Bool) -> Void

    private enum Destination { case trash, permanent }
    @State private var destination: Destination = .trash

    /// Findings first (in their fixed order), then file types selected from
    /// Explore - two different sources feeding one review list, per "do not
    /// create a second, parallel delete path."
    private var groupedItems: [(source: CleanupItemSource, items: [CleanupItem])] {
        let grouped = Dictionary(grouping: selection.items, by: \.source)

        let findingGroups: [(CleanupItemSource, [CleanupItem])] = CleanupFindingID.allCases.compactMap { id in
            let source = CleanupItemSource.finding(id)
            guard let items = grouped[source], !items.isEmpty else { return nil }
            return (source, items.sorted { $0.sizeBytes > $1.sizeBytes })
        }
        let fileTypeGroups: [(CleanupItemSource, [CleanupItem])] = FileTypeCategory.allCases.compactMap { category in
            let source = CleanupItemSource.fileType(category)
            guard let items = grouped[source], !items.isEmpty else { return nil }
            return (source, items.sorted { $0.sizeBytes > $1.sizeBytes })
        }
        return findingGroups + fileTypeGroups
    }

    private var rebuildCommands: [String] {
        Array(Set(selection.items.compactMap(\.rebuildCommand))).sorted()
    }

    private var effectivePermanently: Bool {
        selection.containsUserContent ? false : destination == .permanent
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ForEach(groupedItems, id: \.source) { group in
                        groupSection(source: group.source, items: group.items)
                    }
                    if !rebuildCommands.isEmpty {
                        rebuildCard
                    }
                    destinationPicker
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .navigationTitle("Review")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Review before deleting")
                .font(.system(size: 26, weight: .bold))
            Text("\(selection.count) item\(selection.count == 1 ? "" : "s") selected · \(ByteFormatter.string(fromBytes: selection.totalBytes)) will be reclaimed")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func groupSection(source: CleanupItemSource, items: [CleanupItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(source.reviewGroupTitle.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(ByteFormatter.string(fromBytes: items.reduce(0) { $0 + $1.sizeBytes }))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(item.name).font(.system(size: 13))
                                if item.isiCloudSynced {
                                    Image(systemName: "icloud")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(nsColor: .systemCyan))
                                        .help("Stored in iCloud - deleting it removes it from every device.")
                                }
                            }
                            Text(item.detail)
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(ByteFormatter.string(fromBytes: item.sizeBytes))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            selection.remove(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if item.id != items.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.rowCardRadius))
            .hairlineRing(cornerRadius: CleanupMetrics.rowCardRadius)
        }
    }

    private var rebuildCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rebuild afterward with")
                .font(.system(size: 12, weight: .semibold))
            ForEach(rebuildCommands, id: \.self) { command in
                Text(command)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.panelCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.panelCardRadius)
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            destinationOption(
                title: "Move to Trash",
                detail: "Recoverable until you empty the Trash. Recommended.",
                isSelected: destination == .trash,
                action: { destination = .trash }
            )
            if selection.containsUserContent {
                Text("Your selection includes your own files, so only the Trash is offered - there is no way to rebuild a document or a video.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                destinationOption(
                    title: "Delete permanently",
                    detail: "Frees space immediately. You can't undo this action.",
                    isSelected: destination == .permanent,
                    action: { destination = .permanent }
                )
            }
        }
    }

    private func destinationOption(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onBack)
                .font(.control)
                .buttonStyle(.bordered)

            Spacer()

            Button {
                onCommit(effectivePermanently)
            } label: {
                Text(effectivePermanently
                    ? "Delete \(selection.count) Item\(selection.count == 1 ? "" : "s") Permanently"
                    : "Move \(selection.count) Item\(selection.count == 1 ? "" : "s") to Trash")
                    .font(.control)
            }
            .buttonStyle(.borderedProminent)
            .tint(effectivePermanently ? .red : .accentColor)
            .disabled(selection.count == 0)
        }
        .padding(16)
    }
}
