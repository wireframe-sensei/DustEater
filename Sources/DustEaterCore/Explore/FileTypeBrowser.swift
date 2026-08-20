import Foundation

/// One file, fully detailed for the Type detail screen - the facts
/// `FileTypeIndexEntry` doesn't carry (logical size, last-opened date,
/// iCloud status) fetched on demand via `FileTypeBrowser.loadDetails`, only
/// for the bounded set of entries a user actually opens a type to browse.
public struct ExploreFileDetail: Sendable, Identifiable, Equatable {
    public var id: String { path }

    public let path: String
    public let name: String
    public let logicalSize: Int64
    /// `nil` means genuinely unknown, not "never opened" - see
    /// `LargeFileEntry.lastUsedDate`, which this mirrors.
    public let lastUsedDate: Date?
    public let isPhotosManaged: Bool
    /// True for the one row that represents a whole creative-suite library
    /// or app-adjacent bundle - see `FileTypeIndexEntry.isProtectedBundle`.
    /// Locked the same way `isPhotosManaged` is, with different hint text.
    public let isProtectedBundle: Bool
    /// True if this file is iCloud-synced - badged in the UI with a
    /// warning that deletion removes it from every device.
    public let isiCloudSynced: Bool

    public init(
        path: String,
        name: String,
        logicalSize: Int64,
        lastUsedDate: Date?,
        isPhotosManaged: Bool,
        isProtectedBundle: Bool = false,
        isiCloudSynced: Bool
    ) {
        self.path = path
        self.name = name
        self.logicalSize = logicalSize
        self.lastUsedDate = lastUsedDate
        self.isPhotosManaged = isPhotosManaged
        self.isProtectedBundle = isProtectedBundle
        self.isiCloudSynced = isiCloudSynced
    }

    /// The one and only path into the app-wide selection for an Explore
    /// file - `SelectionStore`/`ReviewView`/`CleanupCommitter` all already
    /// work in terms of `CleanupItem`, so this is a conversion, not a
    /// second selection or delete mechanism.
    ///
    /// `isUserContent: true` unconditionally - this is what activates
    /// Review's Trash-only rule the moment any Explore file joins the
    /// selection. A Photos-managed original becomes `.reportOnly` with the
    /// exact required copy as its `hint`, reusing the same lock+hint
    /// mechanism Cleanup's own report-only findings (iOS Simulator
    /// runtimes) already use, rather than inventing a parallel "locked"
    /// concept - `SelectionStore.toggle` already refuses a `.reportOnly`
    /// item as a hard backstop, so a managed original genuinely cannot be
    /// selected, not just discouraged in the view.
    public func makeCleanupItem(category: FileTypeCategory) -> CleanupItem {
        let abbreviatedPath = (path as NSString).abbreviatingWithTildeInPath
        if isPhotosManaged {
            return CleanupItem(
                id: path,
                source: .fileType(category),
                name: name,
                detail: abbreviatedPath,
                sizeBytes: logicalSize,
                safety: .reportOnly,
                hint: "Managed by Photos - delete it in the Photos app.",
                deletablePaths: [],
                revealPath: path,
                isUserContent: true,
                isiCloudSynced: isiCloudSynced
            )
        }
        if isProtectedBundle {
            return CleanupItem(
                id: path,
                source: .fileType(category),
                name: name,
                detail: abbreviatedPath,
                sizeBytes: logicalSize,
                safety: .reportOnly,
                hint: "A package, not a single file - open it in the app that created it instead of deleting pieces of it.",
                deletablePaths: [],
                revealPath: path,
                isUserContent: true,
                isiCloudSynced: isiCloudSynced
            )
        }
        return CleanupItem(
            id: path,
            source: .fileType(category),
            name: name,
            detail: abbreviatedPath,
            sizeBytes: logicalSize,
            safety: .safe,
            deletablePaths: [path],
            revealPath: path,
            isUserContent: true,
            isiCloudSynced: isiCloudSynced
        )
    }
}

/// Turns the cheap `FileTypeIndexEntry` list `DiskScanner` already built
/// (path/name/allocated size only) into fully-detailed `ExploreFileDetail`s
/// for one type's browse screen - the on-demand `lstat` + iCloud check +
/// last-used lookup this needs is real I/O, so it only ever runs for the
/// bounded, already-capped set of entries one category has (at most
/// `FileTypeIndex.maxEntriesPerCategory`), and only when a user actually
/// opens that type - never eagerly for all eight at scan time.
public enum FileTypeBrowser {
    /// Overridable for testing, same shape as `LargeFileFinder.find`.
    public static func loadDetails(
        for entries: [FileTypeIndexEntry],
        lastUsedDateProvider: @escaping @Sendable (String) async -> Date? = LargeFileFinder.defaultLastUsedDateProvider
    ) async -> [ExploreFileDetail] {
        var results: [ExploreFileDetail] = []
        results.reserveCapacity(entries.count)

        await withConcurrentTasks(over: entries, maxConcurrent: concurrencyLimit, transform: { entry in
            await detail(for: entry, lastUsedDateProvider: lastUsedDateProvider)
        }, onEach: { detail in
            if let detail { results.append(detail) }
        })

        return results.sorted { $0.logicalSize > $1.logicalSize }
    }

    private static func detail(
        for entry: FileTypeIndexEntry,
        lastUsedDateProvider: @Sendable (String) async -> Date?
    ) async -> ExploreFileDetail? {
        // `entry.path` is a directory for a protected-bundle aggregate
        // (a `.fcpbundle`, a `.framework`, ...) - `lstat`ing it would
        // return the directory inode's own tiny size, not the recursive
        // total `DiskScanner` already computed and folded into
        // `sizeBytes`. Use that directly instead of re-deriving a
        // "logical size" that doesn't mean anything at the folder level.
        let logicalSize: Int64
        if entry.isProtectedBundle {
            logicalSize = entry.sizeBytes
        } else {
            guard let stats = (try? await BlockingIO.run { FileStatReader.facts(atPath: entry.path) }) ?? nil else {
                return nil
            }
            logicalSize = stats.logicalSize
        }
        let lastUsedDate = await lastUsedDateProvider(entry.path)
        let isiCloudSynced = (try? await BlockingIO.run { isiCloudItem(atPath: entry.path) }) ?? false

        return ExploreFileDetail(
            path: entry.path,
            name: entry.name,
            logicalSize: logicalSize,
            lastUsedDate: lastUsedDate,
            isPhotosManaged: entry.isPhotosManaged,
            isProtectedBundle: entry.isProtectedBundle,
            isiCloudSynced: isiCloudSynced
        )
    }

    private static func isiCloudItem(atPath path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
    }

    /// A bounded sliding window, the same shape as `DuplicateDetector.
    /// withConcurrentTasks` and `PurgeScanner.measure(_:addingTo:
    /// totalTargets:)` but not sharing either: this is now the third
    /// similar-but-distinct bounded-concurrency leaf-task loop in the
    /// codebase, and each one bounds a different kind of work for a
    /// different reason (tens of thousands of hashes, at most a couple
    /// dozen catalog paths, here up to `FileTypeIndex.maxEntriesPerCategory`
    /// `lstat`+iCloud+Spotlight lookups) - promoting one to shared
    /// infrastructure now would couple three call sites that only
    /// coincidentally share a shape.
    private static func withConcurrentTasks<Item: Sendable, Output: Sendable>(
        over items: [Item],
        maxConcurrent: Int,
        transform: @escaping @Sendable (Item) async -> Output,
        onEach: (Output) -> Void
    ) async {
        guard !items.isEmpty else { return }
        var iterator = items.makeIterator()

        await withTaskGroup(of: Output.self) { group in
            for _ in 0..<maxConcurrent {
                guard let item = iterator.next() else { break }
                group.addTask { await transform(item) }
            }
            while let output = await group.next() {
                onEach(output)
                if let next = iterator.next() {
                    group.addTask { await transform(next) }
                }
            }
        }
    }

    private static let concurrencyLimit = ProcessInfo.processInfo.activeProcessorCount * 4
}
