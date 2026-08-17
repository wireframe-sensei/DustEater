import Foundation
import Observation

@Observable
@MainActor
public final class AppManagerScanner {
    public enum State {
        case idle
        case scanning
        case loaded(installed: [AppDiskEntity], orphaned: [OrphanedAppData], developerTools: [OrphanedAppData])
        case failed(String)
        case needsFullDiskAccess(path: String)
    }

    public private(set) var state: State = .idle

    private var scanTask: Task<Void, Never>?

    public init() {}

    public func scan() {
        scanTask?.cancel()

        state = .scanning
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }

            switch AttrListBulkReader.probeAccess(atPath: "/Applications") {
            case 0:
                break
            case EACCES, EPERM:
                self.state = .needsFullDiskAccess(path: "/Applications")
                return
            case let other:
                self.state = .failed("Couldn't access '/Applications': \(String(cString: strerror(other)))")
                return
            }

            guard !Task.isCancelled else { return }

            var allAppNodes: [FileNode] = []

            let scanner = DiskScanner()
            let applicationsRoot = await scanner.scan(rootPath: "/Applications")
            guard !Task.isCancelled else { return }
            allAppNodes.append(contentsOf: AppGrouper.findAppBundles(in: applicationsRoot))

            let homeDir = NSHomeDirectory()
            let homeApplications = (homeDir as NSString).appendingPathComponent("Applications")
            if FileManager.default.fileExists(atPath: homeApplications) {
                let homeAppsRoot = await scanner.scan(rootPath: homeApplications)
                guard !Task.isCancelled else { return }
                allAppNodes.append(contentsOf: AppGrouper.findAppBundles(in: homeAppsRoot))
            }

            let installed = await AppGrouper.buildAppDiskEntities(from: allAppNodes)
            guard !Task.isCancelled else { return }

            let scanResult = await OrphanFinder.findOrphanedData(installedApps: installed)
            guard !Task.isCancelled else { return }

            self.state = .loaded(installed: installed, orphaned: scanResult.apps, developerTools: scanResult.developerTools)
        }
    }

    public func reconcileInstalledAppUninstalled(
        appID: String,
        bundleWasRemoved: Bool,
        removedItemPaths: Set<String>
    ) {
        guard case .loaded(var installed, var orphaned, let developerTools) = state,
              let index = installed.firstIndex(where: { $0.id == appID }) else { return }

        let entity = installed[index]
        let remainingItems = entity.relatedItems.filter { !removedItemPaths.contains($0.path) }

        if bundleWasRemoved {
            installed.remove(at: index)
            if !remainingItems.isEmpty {
                orphaned.append(OrphanedAppData(
                    inferredIdentifier: entity.bundleIdentifier ?? entity.id,
                    items: remainingItems
                ))
            }
        } else {
            installed[index] = AppDiskEntity(
                displayName: entity.displayName,
                bundleIdentifier: entity.bundleIdentifier,
                appPath: entity.appPath,
                appBundleSize: entity.appBundleSize,
                relatedItems: remainingItems,
                lastOpenedDate: entity.lastOpenedDate
            )
        }

        state = .loaded(installed: installed, orphaned: orphaned, developerTools: developerTools)
    }

    public func reconcileOrphanRemoved(orphanID: String, removedItemPaths: Set<String>) {
        guard case .loaded(let installed, var orphaned, let developerTools) = state,
              let index = orphaned.firstIndex(where: { $0.id == orphanID }) else { return }

        let remainingItems = orphaned[index].items.filter { !removedItemPaths.contains($0.path) }
        if remainingItems.isEmpty {
            orphaned.remove(at: index)
        } else {
            orphaned[index] = OrphanedAppData(
                inferredIdentifier: orphaned[index].inferredIdentifier,
                items: remainingItems
            )
        }

        state = .loaded(installed: installed, orphaned: orphaned, developerTools: developerTools)
    }

    public func reconcileDeveloperToolRemoved(toolID: String, removedItemPaths: Set<String>) {
        guard case .loaded(let installed, let orphaned, var developerTools) = state,
              let index = developerTools.firstIndex(where: { $0.id == toolID }) else { return }

        let remainingItems = developerTools[index].items.filter { !removedItemPaths.contains($0.path) }
        if remainingItems.isEmpty {
            developerTools.remove(at: index)
        } else {
            developerTools[index] = OrphanedAppData(
                inferredIdentifier: developerTools[index].inferredIdentifier,
                items: remainingItems
            )
        }

        state = .loaded(installed: installed, orphaned: orphaned, developerTools: developerTools)
    }
}

extension AppManagerScanner {
    /// Headless variant of `scan()`, for a caller that only wants installed
    /// apps with no `@Observable` progress to watch and no need for orphan
    /// detection - `CleanupScanner`'s "applications unopened in over a year"
    /// finding, the only current caller. Silently returns an empty list on a
    /// permission failure rather than surfacing a distinct error state: the
    /// finding just doesn't appear, matching every other finding's
    /// disappear-when-empty behavior, and permission onboarding is out of
    /// scope here (see the design handoff's item 7).
    public static func scanInstalledApps() async -> [AppDiskEntity] {
        guard AttrListBulkReader.probeAccess(atPath: "/Applications") == 0 else { return [] }

        var allAppNodes: [FileNode] = []
        let scanner = DiskScanner()
        let applicationsRoot = await scanner.scan(rootPath: "/Applications")
        allAppNodes.append(contentsOf: AppGrouper.findAppBundles(in: applicationsRoot))

        let homeApplications = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: homeApplications) {
            let homeAppsRoot = await scanner.scan(rootPath: homeApplications)
            allAppNodes.append(contentsOf: AppGrouper.findAppBundles(in: homeAppsRoot))
        }

        return await AppGrouper.buildAppDiskEntities(from: allAppNodes)
    }
}
