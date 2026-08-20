import SwiftUI
import DustEaterCore

/// Apps - one of the three destinations inside `CleanupShellView`'s single
/// window, not a screen with chrome of its own. Deliberately a plain
/// `HStack` (list column + detail column), not a nested `NavigationSplitView`
/// - an earlier version embedded its own `NavigationSplitView` with its own
/// toolbar and Home button inside the shell's one real detail pane, which
/// read as a floating panel sitting inside the window rather than content
/// sitting inside it (confirmed live via screenshot: a second toolbar, a
/// second Home button, and a list column narrow enough that app names wrapped
/// onto three lines). `scanner` and `selection` are both owned by
/// `CleanupShellView`, not by this view - the scanner so switching to Apps
/// and back doesn't re-trigger a full app rescan every time, and the
/// selection because uninstalling an app now flows through the exact same
/// `SelectionStore` -> Review -> `CleanupCommitter` pipeline every other
/// deletable thing in the app uses. No separate delete path.
struct AppManagerView: View {
    enum AppManagerMode: String, CaseIterable {
        case installed = "Installed"
        case unused = "Unused"
        case developerTools = "Developer Tools"
    }

    let scanner: AppManagerScanner
    let selection: SelectionStore

    @State private var mode: AppManagerMode = .installed
    @State private var focusedID: String?
    @State private var protectedAppsStore = ProtectedAppsStore()

    var rows: [AppRowItem] {
        switch scanner.state {
        case .loaded(let installed, let unused, let developerTools):
            switch mode {
            case .installed:
                return installed.map { entity in
                    AppRowItem(
                        id: entity.id,
                        displayName: entity.displayName,
                        iconPath: entity.appPath,
                        lastOpenedDate: entity.lastOpenedDate,
                        trueFootprint: entity.trueTotalSize,
                        source: .installed(entity)
                    )
                }.sorted { $0.trueFootprint > $1.trueFootprint }
            case .unused:
                return unused.map { orphan in
                    AppRowItem(
                        id: orphan.id,
                        displayName: orphan.inferredDisplayName,
                        iconPath: nil,
                        lastOpenedDate: nil,
                        trueFootprint: orphan.totalSize,
                        source: .orphaned(orphan)
                    )
                }.sorted { $0.trueFootprint > $1.trueFootprint }
            case .developerTools:
                return developerTools.map { tool in
                    AppRowItem(
                        id: tool.id,
                        displayName: tool.inferredDisplayName,
                        iconPath: nil,
                        lastOpenedDate: nil,
                        trueFootprint: tool.totalSize,
                        source: .developerTool(tool)
                    )
                }.sorted { $0.trueFootprint > $1.trueFootprint }
            }
        default:
            return []
        }
    }

    private var focusedRow: AppRowItem? {
        guard let focusedID else { return nil }
        return rows.first { $0.id == focusedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(minWidth: 320)
                .layoutPriority(1)
            Divider()
            detailColumn
                .frame(width: 320)
        }
        .task {
            // Guarded, not unconditional: `scanner` is owned by
            // `CleanupShellView` and persists across destination switches,
            // so re-appearing here after visiting Cleanup or Explore must
            // not silently re-trigger a full app rescan.
            if case .idle = scanner.state {
                scanner.scan()
            }
        }
    }

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(AppManagerMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button(action: { scanner.scan() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Rescan for apps")
            }
            .padding(12)

            if mode == .unused, case .loaded = scanner.state {
                bestEffortBanner
            }

            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch scanner.state {
        case .idle, .scanning:
            VStack(spacing: 16) {
                ProgressView()
                Text("Scanning for apps...")
                    .foregroundStyle(.secondary)
            }
        case .loaded:
            if rows.isEmpty {
                emptyModeState
            } else {
                rowList
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Couldn't scan apps")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Retry", action: { scanner.scan() })
                    .font(.control)
                    .buttonStyle(.bordered)
            }
            .padding()
        case .needsFullDiskAccess:
            VStack(spacing: 12) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Full Disk Access required")
                    .font(.headline)
                Text("The app needs Full Disk Access to scan your applications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .font(.control)
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    /// Verbatim from the design handoff, with the required disclosure
    /// appended: "Nothing here is selected for you - review each one
    /// first." The heuristic-detection sentence was already true before
    /// checkboxes existed on these rows at all; it's just as true now that
    /// checking one joins the shared selection instead of opening App
    /// Manager's own uninstall sheet.
    private var bestEffortBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Best-Effort Detection")
                    .font(.system(size: 12, weight: .medium))
            }
            Text("This is a heuristic. Items marked with a warning triangle share a folder with a currently-installed app and may still be in use. Review carefully before deleting. Nothing here is selected for you - review each one first.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .systemOrange).opacity(0.1), in: RoundedRectangle(cornerRadius: CleanupMetrics.rowCardRadius))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var emptyModeState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Nothing here")
                .font(.system(size: 13, weight: .semibold))
            Text("This scan didn't find anything for this tab.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var rowList: some View {
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
                    ForEach(rows) { row in
                        AppRowView(
                            row: row,
                            isSelected: selection.contains(row.id),
                            isFocused: focusedID == row.id,
                            isProtected: isProtected(row),
                            onToggleSelect: { selection.toggle(row.makeCleanupItem()) },
                            onFocus: { focusedID = row.id }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollEdgeEffect(.hard, for: .top)
        }
    }

    private func isProtected(_ row: AppRowItem) -> Bool {
        guard case .installed(let entity) = row.source, let bundleID = entity.bundleIdentifier else { return false }
        return protectedAppsStore.isProtected(bundleIdentifier: bundleID)
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if let focusedRow {
            AppDetailInspector(row: focusedRow)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "app.badge.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select an app")
                    .font(.system(size: 13, weight: .semibold))
                Text("Choose an app from the list to see what an uninstall would remove.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - AppRowItem

struct AppRowItem: Identifiable {
    let id: String
    let displayName: String
    let iconPath: String?
    let lastOpenedDate: Date?
    let trueFootprint: Int64
    let source: AppRowItemSource

    enum AppRowItemSource {
        case installed(AppDiskEntity)
        case orphaned(OrphanedAppData)
        case developerTool(OrphanedAppData)
    }

    /// What checking this row's checkbox adds to the shared `SelectionStore`
    /// - the same shape Cleanup's own "Applications unopened in over a
    /// year" finding already builds for installed apps, reused via
    /// `CleanupFindingsBuilder.appCleanupItem` rather than re-derived here.
    func makeCleanupItem() -> CleanupItem {
        switch source {
        case .installed(let entity):
            CleanupFindingsBuilder.appCleanupItem(for: entity, source: .app)
        case .orphaned(let orphan), .developerTool(let orphan):
            CleanupFindingsBuilder.appCleanupItem(for: orphan, source: .app)
        }
    }
}

/// One 24pt row - name, last opened, size, per the design system's table
/// row token. A fixed height and a single-line, tail-truncating name are
/// load-bearing, not styling: the previous native `List` row let long names
/// wrap onto multiple lines instead of truncating, which is what actually
/// caused the reported layout bug. Row click focuses (drives the detail
/// pane); the checkbox selects. Separate gestures, same pattern
/// `TypeDetailView`'s `TypeFileRow` already established for Explore.
private struct AppRowView: View {
    let row: AppRowItem
    let isSelected: Bool
    let isFocused: Bool
    let isProtected: Bool
    let onToggleSelect: () -> Void
    let onFocus: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            if isProtected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .help("Protected in Settings - remove protection there to select it for uninstall")
            } else {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggleSelect() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            if let iconPath = row.iconPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "questionmark.app")
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }

            HStack(spacing: 4) {
                Text(row.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if case .orphaned(let orphan) = row.source, orphan.isVendorSibling {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.lastOpenedDate.map { Self.dateFormatter.string(from: $0) } ?? "-")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ExploreMetrics.lastOpenedColumnWidth, alignment: .trailing)

            Text(ByteFormatter.string(fromBytes: row.trueFootprint))
                .font(.system(size: 13).monospacedDigit())
                .frame(width: ExploreMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : (isFocused ? Color.primary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: ExploreMetrics.rowRadius)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
    }
}

#Preview {
    AppManagerView(scanner: AppManagerScanner(), selection: SelectionStore())
        .frame(width: 900, height: 600)
}
