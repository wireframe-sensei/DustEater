import Foundation

/// Turns the output of existing scanners (`PurgeScanner`, `AppManagerScanner`,
/// `DuplicateDetector`, `LargeFileFinder`) into the six `CleanupFinding`s the
/// Cleanup screen shows. Pure functions - no scanning of its own, no
/// SwiftUI/AppKit - so the mapping and ranking logic is unit testable without
/// touching the filesystem.
public enum CleanupFindingsBuilder {
    /// Package manager caches - every `PurgeTarget` in `PurgeCategory
    /// .packageManagers`, already measured by `PurgeScanner.measure(in:)`.
    public static func packageManagerCaches(from categories: [PurgeCategory]) -> CleanupFinding? {
        finding(.packageManagerCaches, from: category(.packageManagers, in: categories))
    }

    /// Xcode build artifacts - `PurgeCategory.xcode` (DerivedData, device
    /// support, Xcode's own cache, the Swift Package Manager cache) plus any
    /// project-locally-discovered Xcode targets `PurgeCatalog.discover`
    /// found. Simulator *caches/logs* (rebuildable/safe) belong here too,
    /// same as the handoff's item list - only the `.reportOnly` simulator
    /// targets go to the runtimes finding below.
    public static func xcodeBuildArtifacts(from categories: [PurgeCategory]) -> CleanupFinding? {
        let xcodeTargets = category(.xcode, in: categories)?.targets ?? []
        let simulatorNonReportOnly = (category(.simulators, in: categories)?.targets ?? [])
            .filter { $0.safety != .reportOnly }
        return finding(.xcodeBuildArtifacts, fromTargets: xcodeTargets + simulatorNonReportOnly)
    }

    /// iOS Simulator runtimes - the `.reportOnly` simulator targets only
    /// (mounted runtime images, the `simctl` device set). Never has a
    /// checkbox, never contributes to the reclaimable total.
    public static func simulatorRuntimes(from categories: [PurgeCategory]) -> CleanupFinding? {
        let reportOnlyTargets = (category(.simulators, in: categories)?.targets ?? [])
            .filter { $0.safety == .reportOnly }
        return finding(.simulatorRuntimes, fromTargets: reportOnlyTargets)
    }

    /// Applications unopened in over a year. An unknown `lastOpenedDate` is
    /// treated as "never opened" (stronger evidence of staleness than a
    /// merely-old date, not weaker) rather than excluded - unlike
    /// `LargeFileFinder`'s "not opened" filter, which deliberately keeps an
    /// unknown date out of its staleness judgment because it's answering a
    /// different question (is this file's *size* worth surfacing at all).
    /// Deleting an app is always shown as `.caution` regardless of the
    /// individual app, since removing it plus every piece of its related
    /// storage is always a meaningfully consequential action.
    public static func unusedApplications(installed: [AppDiskEntity], now: Date = Date()) -> CleanupFinding? {
        guard let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: now) else { return nil }

        let items: [CleanupItem] = installed.compactMap { entity in
            let isStale = entity.lastOpenedDate.map { $0 < cutoff } ?? true
            guard isStale, entity.trueTotalSize > 0 else { return nil }
            return appCleanupItem(for: entity, source: .finding(.unusedApplications))
        }

        guard !items.isEmpty else { return nil }
        return CleanupFinding(id: .unusedApplications, items: items)
    }

    /// Builds the "delete this app entirely" item - bundle plus every piece
    /// of its related storage - for a given `source`. Shared by the
    /// `unusedApplications` finding above (pre-filtered to stale apps only)
    /// and App Manager's Installed list (every installed app, unfiltered),
    /// which both need to answer the exact same question for an
    /// `AppDiskEntity`: what would deleting this app actually remove.
    public static func appCleanupItem(for entity: AppDiskEntity, source: CleanupItemSource) -> CleanupItem {
        CleanupItem(
            id: entity.id,
            source: source,
            name: entity.displayName,
            detail: abbreviated(entity.appPath),
            sizeBytes: entity.trueTotalSize,
            safety: .caution,
            note: entity.lastOpenedDate.map(monthYear) ?? "Never opened",
            deletablePaths: entity.relatedItems.map(\.path) + [entity.appPath],
            appBundlePath: entity.appPath,
            revealPath: entity.appPath,
            blockingAppBundleID: entity.bundleIdentifier
        )
    }

    /// The same idea as `appCleanupItem(for: AppDiskEntity, ...)` above, for
    /// leftover data with no installed app attached (App Manager's Unused
    /// and Developer Tools lists) - there's no bundle to route through
    /// `deleteAppBundle`, just the related items themselves.
    public static func appCleanupItem(for orphan: OrphanedAppData, source: CleanupItemSource) -> CleanupItem {
        CleanupItem(
            id: orphan.id,
            source: source,
            name: orphan.inferredDisplayName,
            detail: orphan.items.first.map { abbreviated($0.path) } ?? "",
            sizeBytes: orphan.totalSize,
            safety: .caution,
            note: "\(orphan.items.count) item\(orphan.items.count == 1 ? "" : "s")",
            deletablePaths: orphan.items.map(\.path),
            revealPath: orphan.items.first?.path ?? ""
        )
    }

    /// Downloads older than 12 months. Scoped to `~/Downloads` by rooting
    /// `LargeFileFinder` at that subtree if the scan reached it - returns
    /// `nil` (not an error) when the scan didn't cover Downloads, e.g. a
    /// scan of a folder other than the home directory.
    public static func oldDownloads(
        in root: FileNode,
        homeDirectory: String = NSHomeDirectory(),
        now: Date = Date(),
        lastUsedDateProvider: @Sendable (String) async -> Date? = LargeFileFinder.defaultLastUsedDateProvider
    ) async -> CleanupFinding? {
        let downloadsPath = (homeDirectory as NSString).appendingPathComponent("Downloads")
        guard let downloadsNode = root.node(atPath: downloadsPath), downloadsNode.isDirectory else { return nil }
        guard let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: now) else { return nil }

        let filter = LargeFileFilter(minimumSize: 1, notOpenedSince: cutoff)
        let entries = await LargeFileFinder.find(in: downloadsNode, filter: filter, lastUsedDateProvider: lastUsedDateProvider)
        guard !entries.isEmpty else { return nil }

        let items = entries.map { entry -> CleanupItem in
            CleanupItem(
                id: entry.file.path,
                source: .finding(.oldDownloads),
                name: entry.file.name,
                detail: abbreviated(entry.file.path),
                sizeBytes: entry.file.logicalSize,
                safety: .safe,
                note: monthYear(entry.lastUsedDate ?? entry.file.modifiedAt),
                deletablePaths: [entry.file.path],
                revealPath: entry.file.path
            )
        }
        return CleanupFinding(id: .oldDownloads, items: items)
    }

    /// Duplicate files - one item per `DuplicateSet`, deletable paths always
    /// every copy *except* the newest (`DuplicateSet.files` is sorted newest
    /// first by construction), so the survivor guarantee is a property of
    /// how the item is built, not something a selection type has to enforce
    /// afterward.
    public static func duplicateFiles(from sets: [DuplicateSet]) -> CleanupFinding? {
        let items: [CleanupItem] = sets.compactMap { set in
            guard set.files.count > 1, let survivor = set.files.first else { return nil }
            let older = Array(set.files.dropFirst())
            // The oldest duplicate copy is the one Reveal/Quick Look shows -
            // it's guaranteed to actually be in `deletablePaths`, unlike the
            // kept survivor.
            guard let oldest = older.last else { return nil }

            let copyWord = older.count == 1 ? "copy" : "copies"
            return CleanupItem(
                id: set.contentHash,
                source: .finding(.duplicateFiles),
                name: survivor.name,
                detail: "\(abbreviatedParentDirectory(of: oldest.path)) - \(older.count) older \(copyWord) of \(set.files.count)",
                sizeBytes: set.wastedBytes,
                safety: .safe,
                note: "\(set.files.count) copies",
                deletablePaths: older.map(\.path),
                revealPath: oldest.path
            )
        }

        guard !items.isEmpty else { return nil }
        return CleanupFinding(id: .duplicateFiles, items: items)
    }

    /// Compacts and ranks a batch of possibly-empty findings by reclaimable
    /// bytes, largest first - "across N findings, largest first" per the
    /// Cleanup header.
    public static func rank(_ findings: [CleanupFinding?]) -> [CleanupFinding] {
        findings.compactMap { $0 }.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    // MARK: - Shared PurgeTarget mapping

    private static func category(_ id: PurgeCategoryID, in categories: [PurgeCategory]) -> PurgeCategory? {
        categories.first { $0.categoryID == id }
    }

    private static func finding(_ findingID: CleanupFindingID, from category: PurgeCategory?) -> CleanupFinding? {
        finding(findingID, fromTargets: category?.targets ?? [])
    }

    private static func finding(_ findingID: CleanupFindingID, fromTargets targets: [PurgeTarget]) -> CleanupFinding? {
        let items = targets.filter { $0.sizeBytes > 0 }.map { target in
            CleanupItem(
                id: target.path,
                source: .finding(findingID),
                name: target.definition.title,
                detail: abbreviated(target.path),
                sizeBytes: target.sizeBytes,
                safety: target.safety,
                rebuildCommand: target.definition.rebuildCommand,
                hint: target.definition.hint,
                deletablePaths: target.safety == .reportOnly ? [] : [target.path],
                revealPath: target.path,
                blockingAppBundleID: target.definition.blockingAppBundleID
            )
        }
        guard !items.isEmpty else { return nil }
        return CleanupFinding(id: findingID, items: items)
    }

    // MARK: - Display formatting

    private static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private static func abbreviatedParentDirectory(of path: String) -> String {
        abbreviated((path as NSString).deletingLastPathComponent)
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }
}
