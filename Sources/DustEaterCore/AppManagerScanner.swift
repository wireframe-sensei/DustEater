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

    /// Reconciles installed/unused/developer-tool entries after a batch
    /// commit (via the shared `CleanupCommitter`, from Review) removed some
    /// of their paths. The general-purpose successor to three now-unused
    /// per-entity reconcile methods this replaced: App Manager no longer
    /// has a delete path of its own that already knows exactly which single
    /// entity/orphan/tool id was affected, so this instead walks every list
    /// checking which entries had any of their paths in `deletedPaths` -
    /// works uniformly whether the commit touched one app or twenty.
    public func reconcileDeletedPaths(_ deletedPaths: Set<String>) {
        guard case .loaded(var installed, var orphaned, var developerTools) = state,
              !deletedPaths.isEmpty else { return }

        installed = installed.compactMap { entity -> AppDiskEntity? in
            let bundleRemoved = deletedPaths.contains(entity.appPath)
            let remainingItems = entity.relatedItems.filter { !deletedPaths.contains($0.path) }
            guard bundleRemoved || remainingItems.count != entity.relatedItems.count else { return entity }

            if bundleRemoved {
                // Any related storage that survived the bundle itself
                // being deleted becomes a leftover, same as the old
                // `reconcileInstalledAppUninstalled(bundleWasRemoved: true)`.
                if !remainingItems.isEmpty {
                    orphaned.append(OrphanedAppData(
                        inferredIdentifier: entity.bundleIdentifier ?? entity.id,
                        items: remainingItems
                    ))
                }
                return nil
            }
            return AppDiskEntity(
                displayName: entity.displayName,
                bundleIdentifier: entity.bundleIdentifier,
                appPath: entity.appPath,
                appBundleSize: entity.appBundleSize,
                relatedItems: remainingItems,
                lastOpenedDate: entity.lastOpenedDate
            )
        }

        func reconciled(_ list: [OrphanedAppData]) -> [OrphanedAppData] {
            list.compactMap { orphan in
                let remainingItems = orphan.items.filter { !deletedPaths.contains($0.path) }
                guard remainingItems.count != orphan.items.count else { return orphan }
                guard !remainingItems.isEmpty else { return nil }
                return OrphanedAppData(
                    inferredIdentifier: orphan.inferredIdentifier,
                    items: remainingItems,
                    isVendorSibling: orphan.isVendorSibling
                )
            }
        }
        orphaned = reconciled(orphaned)
        developerTools = reconciled(developerTools)

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
