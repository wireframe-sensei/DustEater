import SwiftUI
import DustEaterCore

struct AppManagerView: View {
    enum AppManagerMode: String, CaseIterable {
        case installed = "Installed"
        case orphaned = "Orphaned"
        case developerTools = "Developer Tools"
    }

    let onBackToHome: () -> Void

    @State private var scanner = AppManagerScanner()
    @State private var mode: AppManagerMode = .installed
    @State private var selectedID: String?
    @State private var protectedAppsStore = ProtectedAppsStore()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.controlMetrics) private var metrics

    var rows: [AppRowItem] {
        switch scanner.state {
        case .loaded(let installed, let orphaned, let developerTools):
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
            case .orphaned:
                return orphaned.map { orphan in
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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AppManagerMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                if mode == .orphaned, case .loaded = scanner.state {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Best-Effort Detection")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text("Orphan detection is a heuristic. Items marked ⚠️ share a folder with a currently-installed app and may still be in use. Review carefully before deleting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(12)
                }

                if case .loaded = scanner.state {
                    List(rows, id: \.id, selection: $selectedID) { row in
                        HStack(spacing: 12) {
                            if let iconPath = row.iconPath {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "questionmark.app")
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(row.displayName)
                                        .font(.control)
                                        .fontWeight(.medium)
                                    if case .orphaned(let orphan) = row.source, orphan.isVendorSibling {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }

                            Spacer()

                            if let date = row.lastOpenedDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("-")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(ByteFormatter.string(fromBytes: row.trueFootprint))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                } else if case .scanning = scanner.state {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Scanning for apps...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .failed(let message) = scanner.state {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .needsFullDiskAccess = scanner.state {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("App Manager")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        onBackToHome()
                    } label: {
                        Label("Home", systemImage: "house")
                    }
                    .help("Back to home screen")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { scanner.scan() }) {
                        Label("Rescan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Rescan for apps")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: { openSettings() }) {
                        Label("Settings", systemImage: "gear")
                    }
                    .help("Open settings")
                }
            }
        } detail: {
            if let selectedID = selectedID,
               let selectedRow = rows.first(where: { $0.id == selectedID }) {
                AppDetailInspector(
                    row: selectedRow,
                    protectedAppsStore: protectedAppsStore,
                    onUninstalled: { removedPaths, bundleRemoved in
                        switch selectedRow.source {
                        case .installed(let entity):
                            scanner.reconcileInstalledAppUninstalled(
                                appID: entity.id,
                                bundleWasRemoved: bundleRemoved,
                                removedItemPaths: removedPaths
                            )
                        case .orphaned(let orphan):
                            scanner.reconcileOrphanRemoved(orphanID: orphan.id, removedItemPaths: removedPaths)
                        case .developerTool(let tool):
                            scanner.reconcileDeveloperToolRemoved(toolID: tool.id, removedItemPaths: removedPaths)
                        }
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select an app")
                        .font(.headline)
                    Text("Choose an app from the list to view details")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .task {
            scanner.scan()
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
}

#Preview {
    AppManagerView(onBackToHome: {})
}
