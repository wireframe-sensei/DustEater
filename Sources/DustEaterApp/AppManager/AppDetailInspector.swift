import SwiftUI
import DustEaterCore

struct AppDetailInspector: View {
    let row: AppRowItem
    let protectedAppsStore: ProtectedAppsStore
    let onUninstalled: (_ removedItemPaths: Set<String>, _ bundleRemoved: Bool) -> Void

    @State private var selection: AppUninstallSelection
    @State private var showConfirmationSheet = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showRunningAppAlert = false
    @State private var isAppRunning = false
    @Environment(\.controlMetrics) private var metrics

    init(row: AppRowItem, protectedAppsStore: ProtectedAppsStore, onUninstalled: @escaping (_ removedItemPaths: Set<String>, _ bundleRemoved: Bool) -> Void) {
        self.row = row
        self.protectedAppsStore = protectedAppsStore
        self.onUninstalled = onUninstalled

        switch row.source {
        case .installed(let entity):
            _selection = State(initialValue: AppUninstallSelection(entity: entity))
        case .orphaned(let orphan):
            _selection = State(initialValue: AppUninstallSelection(orphan: orphan))
        case .developerTool(let tool):
            _selection = State(initialValue: AppUninstallSelection(orphan: tool))
        }
    }

    var bundleIdentifier: String? {
        switch row.source {
        case .installed(let entity):
            return entity.bundleIdentifier
        case .orphaned, .developerTool:
            return nil
        }
    }

    var isProtected: Bool {
        if let bundleID = bundleIdentifier {
            return protectedAppsStore.isProtected(bundleIdentifier: bundleID)
        }
        return false
    }

    var relatedItems: [RelatedStorageItem] {
        switch row.source {
        case .installed(let entity):
            return entity.relatedItems
        case .orphaned(let orphan):
            return orphan.items
        case .developerTool(let tool):
            return tool.items
        }
    }

    var selectAllState: AppUninstallSelection.SelectAllState {
        selection.selectAllState(totalRelatedCount: relatedItems.count, includesBundle: selection.includeAppBundle)
    }

    var totalBytesToRecover: Int64 {
        var total: Int64 = 0
        if selection.includeAppBundle {
            switch row.source {
            case .installed(let entity):
                total += entity.appBundleSize
            case .orphaned, .developerTool:
                break
            }
        }
        for item in relatedItems {
            if selection.includedItemPaths.contains(item.path) {
                total += item.size
            }
        }
        return total
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            if case .installed(let entity) = row.source {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entity.appPath))
                                    .resizable()
                                    .frame(width: 64, height: 64)
                            } else {
                                Image(systemName: "questionmark.app")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(row.displayName)
                                        .font(.headline)
                                    if case .orphaned(let orphan) = row.source, orphan.isVendorSibling {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                if case .installed(let entity) = row.source,
                                   let bundleID = entity.bundleIdentifier {
                                    Text(bundleID)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }

                            HStack(spacing: 16) {
                                VStack(spacing: 4) {
                                    Text("Total Size")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(ByteFormatter.string(fromBytes: row.trueFootprint))
                                        .font(.system(.headline, design: .monospaced))
                                }

                                Divider()

                                VStack(spacing: 4) {
                                    Text("Last Opened")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let date = row.lastOpenedDate {
                                        Text(date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(.headline, design: .monospaced))
                                    } else {
                                        Text("-")
                                            .font(.system(.headline, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .padding(20)

                        VStack(spacing: 0) {
                            // Select All checkbox
                            if !relatedItems.isEmpty {
                                HStack(spacing: 12) {
                                    MixedStateCheckbox(
                                        state: selectAllState.nsControlState,
                                        action: {
                                            if selectAllState == .all {
                                                selection.includedItemPaths.removeAll()
                                            } else {
                                                selection.includedItemPaths = Set(relatedItems.map(\.path))
                                            }
                                        }
                                    )

                                    Text("Select All")
                                        .font(.control)

                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))

                                Divider()
                                    .padding(0)
                            }

                            // App bundle row (installed only)
                            if case .installed(let entity) = row.source {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: $selection.includeAppBundle)
                                        .toggleStyle(.checkbox)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Application Bundle")
                                            .font(.control)
                                        Text(entity.appPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(ByteFormatter.string(fromBytes: entity.appBundleSize))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))

                                if !relatedItems.isEmpty {
                                    Divider()
                                        .padding(0)
                                }
                            }

                            // Related storage items
                            ForEach(relatedItems) { item in
                                HStack(spacing: 12) {
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { selection.includedItemPaths.contains(item.path) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selection.includedItemPaths.insert(item.path)
                                                } else {
                                                    selection.includedItemPaths.remove(item.path)
                                                }
                                            }
                                        )
                                    )
                                    .toggleStyle(.checkbox)

                                    Image(systemName: categoryIcon(item.category))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.category.rawValue)
                                            .font(.control)
                                        Text(item.path)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(ByteFormatter.string(fromBytes: item.size))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))

                                if item.id != relatedItems.last?.id {
                                    Divider()
                                        .padding(0)
                                }
                            }
                        }
                        .padding(20)
                    }
                }

                // Footer
                VStack(spacing: 12) {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            switch row.source {
                            case .installed(let entity):
                                selection = AppUninstallSelection(entity: entity)
                            case .orphaned(let orphan):
                                selection = AppUninstallSelection(orphan: orphan)
                            case .developerTool(let tool):
                                selection = AppUninstallSelection(orphan: tool)
                            }
                        }) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .font(.control)
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(action: { showConfirmationSheet = true }) {
                            Label("Uninstall Selected", systemImage: "trash")
                        }
                        .font(.control)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isProtected || (totalBytesToRecover == 0))
                        .help(isProtected ? "This app is protected in settings" : totalBytesToRecover == 0 ? "Select items to uninstall" : "")
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .sheet(isPresented: $showConfirmationSheet) {
            UninstallConfirmationSheet(
                displayName: row.displayName,
                selection: selection,
                appSource: row.source,
                totalBytesToRecover: totalBytesToRecover,
                isDeleting: $isDeleting,
                errorMessage: $errorMessage,
                onConfirm: { performUninstall() }
            )
        }
        .alert("App is Running", isPresented: $showRunningAppAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Quit and Uninstall", action: quitAndUninstall)
        } message: {
            Text("\(row.displayName) is currently running. It must be quit before the app can be uninstalled.")
        }
        .id(row.id)
    }

    private func performUninstall() {
        if selection.includeAppBundle, let bundleID = bundleIdentifier {
            isAppRunning = FileOperations.isAppRunning(bundleIdentifier: bundleID)
            if isAppRunning {
                showRunningAppAlert = true
                return
            }
        }

        proceedWithUninstall()
    }

    private func proceedWithUninstall() {
        isDeleting = true
        errorMessage = nil

        Task {
            var errors: [String] = []

            for path in selection.includedItemPaths {
                do {
                    try FileOperations.delete(at: path, permanently: false)
                } catch {
                    errors.append("\(path): \(error.localizedDescription)")
                }
            }

            if selection.includeAppBundle {
                if case .installed(let entity) = row.source {
                    do {
                        try FileOperations.deleteAppBundle(at: entity.appPath, permanently: false)
                    } catch {
                        errors.append("\(entity.appPath): \(error.localizedDescription)")
                    }
                }
            }

            await MainActor.run {
                isDeleting = false
                if errors.isEmpty {
                    showConfirmationSheet = false
                    onUninstalled(selection.includedItemPaths, selection.includeAppBundle)
                } else {
                    errorMessage = errors.joined(separator: "\n")
                }
            }
        }
    }

    private func quitAndUninstall() {
        if let bundleID = bundleIdentifier {
            _ = FileOperations.terminateApp(bundleIdentifier: bundleID)
            Task {
                try await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    proceedWithUninstall()
                }
            }
        }
    }

    private func categoryIcon(_ category: RelatedStorageCategory) -> String {
        switch category {
        case .applicationSupport:
            return "folder"
        case .caches:
            return "trash"
        case .containers:
            return "square.stack.3d.down.forward"
        case .savedState:
            return "doc.text"
        case .preferences:
            return "gearshape"
        }
    }
}

#Preview {
    @Previewable @State var store = ProtectedAppsStore()

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
        ),
        protectedAppsStore: store,
        onUninstalled: { _, _ in }
    )
}
