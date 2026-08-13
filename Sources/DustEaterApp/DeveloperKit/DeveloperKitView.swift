import SwiftUI
import DustEaterCore

/// Screen root for the Developer & Creative Power-User Clean Up Kit. Reads
/// the already-scanned `FileNode` tree passed in from `MainContentView` -
/// runs no directory scan of its own and needs no additional permission
/// prompt, the same "reuse the scan" contract `DuplicatesView` uses.
///
/// Read-only for now: sizes, safety badges, toggles, and Reveal in Finder,
/// but no delete action yet. Selecting targets and watching the running
/// total is genuinely useful review material on its own, and shipping it
/// without an attached delete action keeps this screen fully reviewable in
/// isolation before the destructive path lands.
struct DeveloperKitView: View {
    let root: FileNode
    let onBackToHome: () -> Void
    let onBackToScan: () -> Void

    @State private var scanner = PurgeScanner()
    @State private var selection = PurgeSelection()
    // Listed independently of `scanner`/`PurgeScanState`: an archive never
    // becomes a `PurgeTarget` (see `ArchivesSummaryCardView`'s doc comment),
    // so it has no reason to share the main measure pipeline's state shape.
    @State private var archives: [XcodeArchive] = []
    @State private var showArchivesList = false

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16)]

    private var loadedCategories: [PurgeCategory]? {
        if case .loaded(let categories) = scanner.state { return categories }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Developer Kit")
        .toolbar { toolbarContent }
        .task { scanner.measure(in: root) }
        .task { archives = await XcodeArchiveLister.listArchives(in: root) }
        .sheet(isPresented: $showArchivesList) {
            XcodeArchivesListView(archives: archives)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer & Creative Clean Up Kit")
                    .font(DustEaterTheme.Typography.headline)
                if let loadedCategories {
                    let reclaimable = loadedCategories.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
                    Text("\(ByteFormatter.string(fromBytes: reclaimable)) reclaimable across \(loadedCategories.count) categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selection.count > 0, let loadedCategories {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(selection.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.string(fromBytes: selection.reclaimableBytes(across: loadedCategories)))
                        .font(.control)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch scanner.state {
        case .idle:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .scanning(let measured, let progress):
            if measured.isEmpty {
                VStack(spacing: DustEaterTheme.Spacing.sm) {
                    ProgressView()
                    Text(phaseLabel(progress.phase))
                        .foregroundStyle(.secondary)
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid(for: PurgeCategory.grouped(measured))
            }

        case .loaded(let categories) where categories.isEmpty:
            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Nothing Found")
                    .font(DustEaterTheme.Typography.headline)
                Text("No known developer or creative-app caches were found in this scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .loaded(let categories):
            grid(for: categories)

        case .failed(let message):
            VStack(spacing: DustEaterTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Couldn't Measure Caches")
                    .font(DustEaterTheme.Typography.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { scanner.measure(in: root) }
                    .font(.control)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, DustEaterTheme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // A `DisclosureGroup` per card was rejected here: a disclosure inside a
    // fixed-height card inside a `LazyVGrid` reflows the whole grid on every
    // expand, and this stays a flat grid of per-target cards under a plain
    // section header instead, per CLAUDE.md's "Flat and Direct."
    private func grid(for categories: [PurgeCategory]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !archives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(Color.accentColor)
                            Text("Xcode Archives")
                                .font(DustEaterTheme.Typography.headline)
                            Spacer()
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ArchivesSummaryCardView(
                                archiveCount: archives.count,
                                totalBytes: archives.reduce(0) { $0 + $1.sizeBytes },
                                onBrowse: { showArchivesList = true }
                            )
                        }
                    }
                }

                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: category.systemImage)
                                .foregroundStyle(Color.accentColor)
                            Text(category.title)
                                .font(DustEaterTheme.Typography.headline)
                            Spacer()
                            Text("\(ByteFormatter.string(fromBytes: category.reclaimableBytes)) reclaimable of \(ByteFormatter.string(fromBytes: category.totalBytes)) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Cards measuring 0 bytes (e.g. an empty simulator
                        // cache) carry no useful information, so they're
                        // filtered here rather than rendered as a blank tile.
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(category.targets.filter { $0.sizeBytes > 0 }) { target in
                                TargetCardView(
                                    target: target,
                                    isSelected: selection.isSelected(target),
                                    onToggle: { selection.toggle(target) }
                                )
                            }
                        }
                    }
                }
            }
            .controlSize(.large)
            .padding(20)
        }
    }

    private func phaseLabel(_ phase: PurgeScanProgress.Phase) -> String {
        switch phase {
        case .discoveringProjects: return "Finding project build artifacts..."
        case .resolvingFromTree: return "Reading sizes from this scan..."
        case .measuring: return "Measuring caches outside this scan..."
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: onBackToScan) {
                Label("Back to Scan", systemImage: "chevron.backward")
            }
            .help("Back to the treemap")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: onBackToHome) {
                Label("Home", systemImage: "house")
            }
            .help("Back to home screen")
        }

        ToolbarItem(placement: .primaryAction) {
            selectMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                scanner.measure(in: root)
            } label: {
                Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Re-measure every target against this scan")
        }
    }

    @ViewBuilder
    private var selectMenu: some View {
        Menu {
            Button("Select Safe") {
                if let loadedCategories { selection.selectAll(upTo: .safe, in: loadedCategories) }
            }
            Button("Select Safe and Rebuildable") {
                if let loadedCategories { selection.selectAll(upTo: .rebuildable, in: loadedCategories) }
            }
            Divider()
            Button("Deselect All") {
                selection.deselectAll()
            }
        } label: {
            Label("Select", systemImage: "checklist")
        }
        .disabled(loadedCategories?.isEmpty ?? true)
        .help("Bulk-select targets by safety level. Caution-level targets are never bulk-selected.")
    }
}
