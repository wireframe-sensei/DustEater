import SwiftUI
import DustEaterCore

/// One type's file list: a Size + "Not opened in" filter bar (both axes
/// required - "the real user query is videos over 500 MB I haven't opened
/// in a year"), the list itself (default sort size-descending), and a
/// preview pane revealed only once a row is focused.
struct TypeDetailView: View {
    let category: FileTypeCategory
    let index: FileTypeIndex
    let selection: SelectionStore
    let onBack: () -> Void

    enum SizeFilter: String, CaseIterable, Identifiable {
        case all = "All sizes", over100MB = "Over 100 MB", over500MB = "Over 500 MB", over1GB = "Over 1 GB"
        var id: String { rawValue }
        var minimumBytes: Int64 {
            switch self {
            case .all: return 0
            case .over100MB: return 100_000_000
            case .over500MB: return 500_000_000
            case .over1GB: return 1_000_000_000
            }
        }
    }

    enum AgeFilter: String, CaseIterable, Identifiable {
        case any = "Any time", sixMonths = "6 months+", oneYear = "1 year+", twoYears = "2 years+"
        var id: String { rawValue }
        var minimumMonthsAgo: Int? {
            switch self {
            case .any: return nil
            case .sixMonths: return 6
            case .oneYear: return 12
            case .twoYears: return 24
            }
        }
    }

    @State private var details: [ExploreFileDetail] = []
    @State private var isLoading = true
    @State private var sizeFilter: SizeFilter = .all
    @State private var ageFilter: AgeFilter = .any
    @State private var focusedFile: ExploreFileDetail?
    @State private var quickLookPath: String?

    /// Files whose last-used date is unknown are always kept, never treated
    /// as evidence of staleness - the same rule `LargeFileFinder.matches`
    /// already applies, for the same reason: Spotlight not having an
    /// answer isn't evidence the file was never opened.
    private var filteredDetails: [ExploreFileDetail] {
        details.filter { detail in
            guard detail.logicalSize >= sizeFilter.minimumBytes else { return false }
            if let months = ageFilter.minimumMonthsAgo,
               let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()),
               let lastUsed = detail.lastUsedDate {
                guard lastUsed < cutoff else { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar

            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredDetails.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    fileList
                    if let focusedFile {
                        Divider()
                        TypeFilePreviewPane(
                            detail: focusedFile,
                            category: category,
                            isSelected: selection.contains(focusedFile.id),
                            onClose: { self.focusedFile = nil },
                            onToggleSelect: { selection.toggle(focusedFile.makeCleanupItem(category: category)) }
                        )
                        .frame(width: ExploreMetrics.previewPaneWidth)
                    }
                }
            }
        }
        .task(id: category) {
            isLoading = true
            focusedFile = nil
            details = await FileTypeBrowser.loadDetails(for: index.entries(for: category))
            isLoading = false
        }
        .onKeyPress(.space) {
            guard let focusedFile else { return .ignored }
            quickLookPath = focusedFile.path
            return .handled
        }
        .sheet(isPresented: Binding(
            get: { quickLookPath != nil },
            set: { isPresented in if !isPresented { quickLookPath = nil } }
        )) {
            QuickLookPreviewPane(path: quickLookPath, onRunAgain: {})
                .frame(width: 480, height: 360)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: ExploreMetrics.backButtonSize, height: ExploreMetrics.backButtonSize)
                    .background(Color.opaqueTertiaryFill, in: Circle())
            }
            .buttonStyle(.plain)

            Circle().fill(category.accentColor).frame(width: 10, height: 10)
            Text(category.displayName)
                .font(.system(size: 14, weight: .semibold))

            let total = index.total(for: category)
            Text("\(total.fileCount.formatted()) file\(total.fileCount == 1 ? "" : "s") · \(ByteFormatter.string(fromBytes: total.totalBytes)) total")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack(spacing: 18) {
            Picker("Size", selection: $sizeFilter) {
                ForEach(SizeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Picker("Not opened in", selection: $ageFilter) {
                ForEach(AgeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            Text("\(filteredDetails.count.formatted()) match\(filteredDetails.count == 1 ? "" : "es")")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .controlSize(.regular)
        // A hard height, not an inferred one: something about a segmented
        // Picker's intrinsic size inside this hierarchy reports much taller
        // than it ever renders, and `.fixedSize()` alone doesn't correct
        // it - pin the bar to its real, visual height directly instead of
        // continuing to fight where that intrinsic size comes from.
        .frame(height: 24)
        .padding(14)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: ExploreMetrics.filterBarRadius))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                Text("LAST OPENED").frame(width: ExploreMetrics.lastOpenedColumnWidth, alignment: .trailing)
                Text("SIZE").frame(width: ExploreMetrics.sizeColumnWidth, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredDetails) { detail in
                        TypeFileRow(
                            detail: detail,
                            isSelected: selection.contains(detail.id),
                            isFocused: focusedFile?.id == detail.id,
                            onToggle: { selection.toggle(detail.makeCleanupItem(category: category)) },
                            onFocus: { focusedFile = detail }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing this large or this old")
                .font(.system(size: 15, weight: .semibold))
            Text("Loosen a filter to see the rest of this category.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TypeFileRow: View {
    let detail: ExploreFileDetail
    let isSelected: Bool
    let isFocused: Bool
    let onToggle: () -> Void
    let onFocus: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            if detail.isPhotosManaged {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .help("Managed by Photos - delete it in the Photos app.")
            } else {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(detail.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if detail.isiCloudSynced {
                        Image(systemName: "icloud")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .systemCyan))
                            .help("Stored in iCloud - deleting it removes it from every device.")
                    }
                }
                Text((detail.path as NSString).deletingLastPathComponent.abbreviatingWithTilde)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(detail.lastUsedDate.map(Self.dateFormatter.string(from:)) ?? "-")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ExploreMetrics.lastOpenedColumnWidth, alignment: .trailing)

            Text(ByteFormatter.string(fromBytes: detail.logicalSize))
                .font(.system(size: 13).monospacedDigit())
                .frame(width: ExploreMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : (isFocused ? Color.primary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: ExploreMetrics.rowRadius)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
    }
}

private extension String {
    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
