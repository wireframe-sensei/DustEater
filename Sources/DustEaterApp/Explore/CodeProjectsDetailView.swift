import SwiftUI
import DustEaterCore

/// Code & Projects' own detail screen - structurally different from
/// `TypeDetailView` because a project, not a file or even a package
/// folder, is this category's natural unit. `DiskScanner` collapses every
/// recognized dependency/build directory (`node_modules`, `.next`, `dist`,
/// `build`, `target`, `.venv`/`venv`, `Pods`, `DerivedData`) into one
/// `.codeAndProjects` entry per directory (`FileTypeIndexEntry.
/// isDependencyDirectory`); this screen then groups those entries by the
/// project each belongs to (`ProjectDetector`/`ProjectBrowser`) rather than
/// listing them as top-level rows, since a monorepo routinely has one such
/// directory per package - `~/Documents/test/gdp-portal` alone has four -
/// and a row per *package* just re-creates the original clutter one level
/// up.
///
/// A project row's total size is read straight off the scanned tree for
/// that exact path - the same node the sidebar treemap renders from, not a
/// sum of anything - so it always matches the treemap. Its dependency
/// directories are expandable children, still `.reportOnly` (a lock, not
/// a checkbox) with the exact rebuild-command copy Developer Kit's own
/// per-project grouping uses (`DependencyDirectoryCatalog`) - the correct
/// action is a rebuild, not a Trash move, and there is still only the one
/// mechanism for saying so. A file that's part of a project but not inside
/// one of its dependency directories (a loose source file) isn't itemized
/// anywhere - it's part of the project's total, not a row of its own, the
/// same way a Finder folder's size includes files you're not looking at
/// individually. A file that isn't inside any detected project at all
/// still lists in the flat Files section below, unaffected.
struct CodeProjectsDetailView: View {
    let index: FileTypeIndex
    let root: FileNode
    let selection: SelectionStore
    let onBack: () -> Void

    @State private var projects: [ProjectSummary] = []
    @State private var looseFiles: [ExploreFileDetail] = []
    @State private var isLoading = true
    @State private var expandedProjectIDs: Set<String> = []
    @State private var focusedFile: ExploreFileDetail?
    @State private var quickLookPath: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    /// "Projects plus loose files" - what the list actually shows - not
    /// `index.total(for:).fileCount`, which counts every dependency
    /// directory and every loose code file individually, including the
    /// internal folders a user never sees as a row here.
    private var itemCount: Int {
        projects.count + looseFiles.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty && looseFiles.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    listContent
                    if let focusedFile {
                        Divider()
                        TypeFilePreviewPane(
                            detail: focusedFile,
                            category: .codeAndProjects,
                            isSelected: selection.contains(focusedFile.id),
                            onClose: { self.focusedFile = nil },
                            onToggleSelect: { selection.toggle(focusedFile.makeCleanupItem(category: .codeAndProjects)) }
                        )
                        .frame(width: ExploreMetrics.previewPaneWidth)
                    }
                }
            }
        }
        .task {
            isLoading = true
            focusedFile = nil
            let entries = index.entries(for: .codeAndProjects)
            async let loadedProjects = ProjectBrowser.loadProjectSummaries(for: entries, root: root)
            projects = await loadedProjects

            let projectRootPaths = projects.map(\.rootPath)
            let looseEntries = entries.filter { entry in
                guard !entry.isDependencyDirectory else { return false }
                return !projectRootPaths.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") }
            }
            looseFiles = await FileTypeBrowser.loadDetails(for: looseEntries)
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

            Circle().fill(FileTypeCategory.codeAndProjects.accentColor).frame(width: 10, height: 10)
            Text(FileTypeCategory.codeAndProjects.displayName)
                .font(.system(size: 14, weight: .semibold))

            let total = index.total(for: .codeAndProjects)
            Text("\(itemCount.formatted()) item\(itemCount == 1 ? "" : "s") · \(ByteFormatter.string(fromBytes: total.totalBytes)) total")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !projects.isEmpty {
                    sectionHeader("PROJECTS", count: projects.count)
                    LazyVStack(spacing: 8) {
                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                dateFormatter: Self.dateFormatter,
                                isExpanded: expandedProjectIDs.contains(project.id),
                                onToggleExpanded: {
                                    if expandedProjectIDs.contains(project.id) {
                                        expandedProjectIDs.remove(project.id)
                                    } else {
                                        expandedProjectIDs.insert(project.id)
                                    }
                                }
                            )
                        }
                    }
                }
                if !looseFiles.isEmpty {
                    sectionHeader("FILES", count: looseFiles.count)
                    VStack(spacing: 0) {
                        HStack {
                            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                            Text("LAST OPENED").frame(width: ExploreMetrics.lastOpenedColumnWidth, alignment: .trailing)
                            Text("SIZE").frame(width: ExploreMetrics.sizeColumnWidth, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 6)

                        LazyVStack(spacing: 2) {
                            ForEach(looseFiles) { file in
                                CodeProjectFileRow(
                                    detail: file,
                                    dateFormatter: Self.dateFormatter,
                                    isSelected: selection.contains(file.id),
                                    isFocused: focusedFile?.id == file.id,
                                    onToggle: { selection.toggle(file.makeCleanupItem(category: .codeAndProjects)) },
                                    onFocus: { focusedFile = file }
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count.formatted())")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.tertiary)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing Here")
                .font(.system(size: 15, weight: .semibold))
            Text("No code, projects, or dependency folders were found.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One project card: a disclosure header (name, path, reclaimable summary,
/// total size, last-opened) that expands to show its dependency/build
/// directories - each still `.reportOnly`, a lock instead of a checkbox,
/// exactly like `FindingGroupView`'s report-only findings.
private struct ProjectRowView: View {
    let project: ProjectSummary
    let dateFormatter: DateFormatter
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.5)
                VStack(spacing: 2) {
                    ForEach(project.children) { child in
                        DependencyFolderRow(folder: child, dateFormatter: dateFormatter)
                    }
                }
                .padding(10)
            }
        }
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: CleanupMetrics.findingCardRadius))
        .hairlineRing(cornerRadius: CleanupMetrics.findingCardRadius)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16)

            Image(systemName: "shippingbox")
                .font(.system(size: 13))
                .foregroundStyle(FileTypeCategory.codeAndProjects.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                Text((project.rootPath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(project.reclaimableSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.string(fromBytes: project.totalSizeBytes))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                Text(project.lastOpenedDate.map(dateFormatter.string(from:)) ?? "-")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
    }
}

/// One dependency/build directory row, nested inside a project card - a
/// lock glyph instead of a checkbox (report-only, never selectable), its
/// rebuild command as the reason a delete action isn't offered, its own
/// path (which package inside the project, when there's more than one),
/// last-opened date, size, and Reveal in Finder. No Quick Look - a folder
/// has nothing meaningful to preview.
private struct DependencyFolderRow: View {
    let folder: DependencyDirectoryDetail
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
                .help("Report only - rebuild it instead of deleting it: \(folder.rebuildCommand)")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(folder.rebuildCommand)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(folder.lastOpenedDate.map(dateFormatter.string(from:)) ?? "-")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ExploreMetrics.lastOpenedColumnWidth, alignment: .trailing)

            Text(ByteFormatter.string(fromBytes: folder.sizeBytes))
                .font(.system(size: 13).monospacedDigit())
                .frame(width: ExploreMetrics.sizeColumnWidth, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.opaqueTertiaryFill, in: RoundedRectangle(cornerRadius: ExploreMetrics.rowRadius))
    }
}

/// A loose file row, identical in shape to `TypeDetailView`'s own
/// `TypeFileRow` - duplicated rather than shared because the two screens'
/// row models (`ExploreFileDetail` here, unchanged there) are the same
/// type but the surrounding list (projects-plus-files here, a flat
/// filtered list there) is different enough that threading one shared row
/// view through both would need as many parameters as just having two.
private struct CodeProjectFileRow: View {
    let detail: ExploreFileDetail
    let dateFormatter: DateFormatter
    let isSelected: Bool
    let isFocused: Bool
    let onToggle: () -> Void
    let onFocus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if detail.isPhotosManaged {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .help("Managed by Photos - delete it in the Photos app.")
            } else if detail.isProtectedBundle {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .help("A package, not a single file - open it in the app that created it instead of deleting pieces of it.")
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
                Text((detail.path as NSString).deletingLastPathComponent.abbreviatingWithTildeInPath)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(detail.lastUsedDate.map(dateFormatter.string(from:)) ?? "-")
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
    var abbreviatingWithTildeInPath: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
