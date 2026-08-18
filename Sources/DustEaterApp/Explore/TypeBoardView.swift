import SwiftUI
import DustEaterCore

/// The Type board - a 4-column grid of tiles, one per file type that
/// actually has files, ranked by total size (not alphabetical). Purely a
/// browse lens: no ranking implies a recommendation here, and there is
/// deliberately no "select all" affordance anywhere on this screen or the
/// detail it opens into - Explore is the user's own content, which this
/// app must never recommend deleting.
struct TypeBoardView: View {
    let index: FileTypeIndex
    let onSelectType: (FileTypeCategory) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var grandTotalBytes: Int64 {
        index.rankedCategories.reduce(0) { $0 + index.total(for: $1).totalBytes }
    }

    var body: some View {
        ScrollView {
            if index.rankedCategories.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(index.rankedCategories) { category in
                        TypeTileView(
                            category: category,
                            total: index.total(for: category),
                            shareOfTotal: share(of: category),
                            onTap: { onSelectType(category) }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private func share(of category: FileTypeCategory) -> Double {
        guard grandTotalBytes > 0 else { return 0 }
        return Double(index.total(for: category).totalBytes) / Double(grandTotalBytes)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing to Browse Yet")
                .font(.system(size: 15, weight: .semibold))
            Text("File types appear here as the scan finds them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct TypeTileView: View {
    let category: FileTypeCategory
    let total: FileTypeTotal
    let shareOfTotal: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(category.accentColor)
                    .frame(width: ExploreMetrics.tileIconSize, height: ExploreMetrics.tileIconSize)
                    .background(category.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: ExploreMetrics.tileIconRadius))

                Text(category.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(total.fileCount.formatted()) file\(total.fileCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(ByteFormatter.string(fromBytes: total.totalBytes))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.progressTrack)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(category.accentColor)
                            .frame(width: geometry.size.width * shareOfTotal)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 4) {
                    Text(category == .applications ? "Manage in App Manager" : "Browse files")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(minHeight: ExploreMetrics.tileMinHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: ExploreMetrics.tileRadius))
            .hairlineRing(cornerRadius: ExploreMetrics.tileRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
