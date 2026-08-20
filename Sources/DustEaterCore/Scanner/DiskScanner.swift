import Foundation
import os

/// Reports incremental progress while a scan is in-flight.
public struct ScanProgress: Sendable {
    public let itemsScanned: Int
    public let bytesScanned: Int64
    public let currentPath: String
}

/// High-speed recursive directory scanner built on `getattrlistbulk`.
///
/// Traversal is parallelized with `TaskGroup`: each subdirectory is scanned
/// in its own child task, and results are combined functionally as tasks
/// complete (`for await`), so there is no shared mutable state and thus no
/// locking is needed to accumulate sizes - each level simply sums the sizes
/// its children returned. The file-type index (`FileTypeIndexPartial`) rides
/// along the same fold for the same reason - see `scanWithTypeIndex`.
///
/// Task fan-out itself is intentionally *unbounded* - Swift tasks are cheap
/// (they multiplex over the cooperative pool at suspension points rather
/// than consuming an OS thread each) - so gating task creation with a
/// shared permit pool is both unnecessary and dangerous here: a whole
/// generation of sibling directories could simultaneously hold the last
/// free permits while each waits to acquire one more permit to recurse into
/// its own children, with no task left running to ever release one. That
/// exact scenario deadlocked an earlier version of this scanner on wide,
/// deep trees (e.g. npm's hashed cache directories). The only genuinely
/// scarce resource - OS threads doing blocking syscalls - is bounded
/// separately and non-recursively by `BlockingIO`'s dispatch queue, which
/// has no such circular dependency.
public actor DiskScanner {
    private var itemsScanned = 0
    private var bytesScanned: Int64 = 0
    /// Guarded by a raw lock rather than actor isolation: dedup is checked
    /// once per *file* (not per directory), so it sits on the hottest path
    /// in the whole scan. Actor isolation would force every one of those
    /// checks - across every concurrently-running directory task - to funnel
    /// through this actor's single serial executor, capping the CPU-bound
    /// part of the scan (as opposed to the I/O, which genuinely parallelizes
    /// via `BlockingIO`) to one core. `OSAllocatedUnfairLock` is a plain
    /// spinlock/futex with none of an actor hop's job-scheduling overhead,
    /// so contention here stays cheap even at high fan-out.
    private let seenInodes = OSAllocatedUnfairLock<Set<UInt64>>(initialState: [])
    private var lastProgressEmitNanos: UInt64 = 0
    /// Throttled here, inside the actor, rather than after crossing to the
    /// main thread: `onEntries` fires once per directory, which can be
    /// hundreds of thousands of times on a large tree. Checking the interval
    /// before ever invoking the handler avoids scheduling that many
    /// `DispatchQueue.main.async` blocks just to have almost all of them
    /// no-op once they land.
    private let progressIntervalNanos: UInt64 = 100_000_000

    public init() {}

    /// Scans `rootPath` recursively and returns the resulting tree.
    /// - Parameter onProgress: called periodically with a running total of
    ///   items/bytes scanned. May be invoked from arbitrary tasks; keep it cheap.
    public func scan(
        rootPath: String,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> FileNode {
        let (node, _) = await scanWithTypeIndex(rootPath: rootPath, onProgress: onProgress)
        return node
    }

    /// Same walk as `scan(rootPath:onProgress:)`, but also returns a
    /// `FileTypeIndex` classifying every file encountered - built for free
    /// alongside the existing tree construction (each directory task
    /// classifies its own files and folds the result into its return value,
    /// exactly how `FileNode.size`/`itemCount` are already combined), not as
    /// a second pass or a separate scan - deliberately, so the file-type
    /// browser doesn't become a seventh consumer of the already-contended
    /// `BlockingIO` queue.
    ///
    /// Only `ScanCoordinator`'s main scan actually uses the index; every
    /// other `DiskScanner` caller (the small per-path fallback scans in
    /// `PurgeScanner`, `AppManagerScanner`'s `/Applications` scan, etc.)
    /// keeps calling `scan(rootPath:onProgress:)` above and simply discards
    /// it - those scans are bounded to a few thousand files at most, so the
    /// classify-and-discard cost there is negligible.
    public func scanWithTypeIndex(
        rootPath: String,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> (FileNode, FileTypeIndex) {
        let name = (rootPath as NSString).lastPathComponent
        seenInodes.withLock { $0.removeAll() }
        let (node, partial) = await Self.scanDirectory(
            path: rootPath,
            name: name,
            seenInodes: seenInodes,
            insideAggregatedContainer: false,
            onEntries: { [weak self] items, bytes, path in
                await self?.reportProgress(addedItems: items, addedBytes: bytes, path: path, handler: onProgress)
            }
        )
        return (node, partial.finalize())
    }

    private func reportProgress(
        addedItems: Int,
        addedBytes: Int64,
        path: String,
        handler: (@Sendable (ScanProgress) -> Void)?
    ) {
        itemsScanned += addedItems
        bytesScanned += addedBytes

        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastProgressEmitNanos > progressIntervalNanos else { return }
        lastProgressEmitNanos = now

        handler?(ScanProgress(itemsScanned: itemsScanned, bytesScanned: bytesScanned, currentPath: path))
    }

    /// Recursively scans one directory. Files are summed directly; each
    /// subdirectory is scanned in its own child task, and results are
    /// folded together as they complete. Uses inode tracking to deduplicate
    /// hard-linked files so they're only counted once.
    ///
    /// `static`, not an instance method - this keeps the CPU-bound tree
    /// construction (as opposed to `reportProgress`'s bookkeeping) off the
    /// actor's serial executor entirely, so sibling directory tasks in the
    /// `TaskGroup` below can genuinely run concurrently instead of each
    /// needing to acquire `self`'s isolation just to build a `FileNode`.
    ///
    /// - Parameter insideAggregatedContainer: true once recursion has
    ///   entered any directory whose *whole subtree* becomes one type-index
    ///   entry instead of many individual ones - a `.app` bundle, a
    ///   `DependencyDirectoryCatalog` directory (`node_modules`, `.next`,
    ///   `dist`, `build`, `target`, `.venv`/`venv`, `Pods`, `DerivedData`),
    ///   or a `BundleProtection`-recognized creative-suite library
    ///   (`.fcpbundle`, `.imovielibrary`, `.theater`, `.tvlibrary`,
    ///   `.logicx`, `.band`) or app-adjacent bundle (`.framework`,
    ///   `.bundle`, `.xpc`, `.plugin`, `.appex`, `.sparsebundle`). Files
    ///   inside are never individually classified into the type index -
    ///   their bytes are attributed to the one aggregate entry instead,
    ///   recorded once the container's own recursive size is known.
    ///
    ///   Deliberately a single flag, not one per container kind: a
    ///   `.framework` sitting inside a `.app` bundle (routine - most
    ///   frameworks live inside the apps that ship them) must never
    ///   become its own second aggregate entry on top of the app's - the
    ///   *outermost* recognized container wins and nothing nested inside
    ///   it, of any kind, starts a new aggregation. An earlier version
    ///   used three independent flags and got exactly this wrong: a
    ///   `.framework` nested inside a `.app` was both correctly folded
    ///   into the app's `.applications` total *and* incorrectly recorded a
    ///   second time as its own `.other` entry, double-counting its bytes
    ///   and showing a confusing duplicate row - caught by inspecting a
    ///   real scan live, not by reasoning about the code in the abstract.
    ///
    ///   `.photoslibrary` is deliberately not a container here (unlike
    ///   `BundleProtection`'s own, broader suffix list) - its individual
    ///   originals are meant to stay individually browsable, just locked
    ///   (`isPhotosManaged`), not aggregated.
    private static func scanDirectory(
        path: String,
        name: String,
        seenInodes: OSAllocatedUnfairLock<Set<UInt64>>,
        insideAggregatedContainer: Bool,
        onEntries: @escaping @Sendable (Int, Int64, String) async -> Void
    ) async -> (FileNode, FileTypeIndexPartial) {
        guard !Task.isCancelled else {
            return (FileNode(name: name, path: path, size: 0, isDirectory: true), FileTypeIndexPartial())
        }

        let entries: [RawDirEntry]
        do {
            entries = try await BlockingIO.run { try AttrListBulkReader.listDirectory(atPath: path) }
        } catch {
            // Permission denied or the entry vanished mid-scan; treat as an
            // empty leaf rather than aborting the whole scan.
            return (FileNode(name: name, path: path, size: 0, isDirectory: true), FileTypeIndexPartial())
        }

        var fileTotal: Int64 = 0
        var fileChildren: [FileNode] = []
        var subdirEntries: [RawDirEntry] = []
        var typeIndex = FileTypeIndexPartial()
        fileChildren.reserveCapacity(entries.count)
        subdirEntries.reserveCapacity(entries.count)

        for entry in entries where !entry.isSymlink {
            if entry.isDirectory {
                subdirEntries.append(entry)
            } else {
                // Only count each inode once (deduplicate hard links)
                let shouldCount = seenInodes.withLock { inodes in
                    inodes.insert(entry.inode).inserted
                }

                let countedSize = shouldCount ? entry.allocSize : 0
                fileTotal += countedSize
                var childPath = path
                childPath.append("/")
                childPath.append(entry.name)
                fileChildren.append(
                    FileNode(
                        name: entry.name,
                        path: childPath,
                        size: countedSize,
                        isDirectory: false
                    )
                )

                if shouldCount, countedSize > 0, !insideAggregatedContainer {
                    let category = FileTypeClassifier.category(forFileName: entry.name)
                    typeIndex.record(
                        FileTypeIndexEntry(
                            path: childPath,
                            name: entry.name,
                            sizeBytes: countedSize,
                            isPhotosManaged: childPath.contains(".photoslibrary/")
                        ),
                        category: category
                    )
                }
            }
        }

        guard !Task.isCancelled else {
            return (
                FileNode(
                    name: name,
                    path: path,
                    size: fileTotal,
                    isDirectory: true,
                    children: fileChildren,
                    itemCount: fileChildren.count + 1
                ),
                typeIndex
            )
        }

        await onEntries(fileChildren.count, fileTotal, path)

        guard !subdirEntries.isEmpty else {
            return (
                FileNode(
                    name: name,
                    path: path,
                    size: fileTotal,
                    isDirectory: true,
                    children: fileChildren,
                    itemCount: fileChildren.count + 1
                ),
                typeIndex
            )
        }

        var subdirChildren: [FileNode] = []
        subdirChildren.reserveCapacity(subdirEntries.count)

        await withTaskGroup(of: (FileNode, FileTypeIndexPartial).self) { group in
            for entry in subdirEntries {
                guard !Task.isCancelled else { break }

                var childPath = path
                childPath.append("/")
                childPath.append(entry.name)
                let childInsideAggregatedContainer = insideAggregatedContainer
                    || entry.name.hasSuffix(".app")
                    || DependencyDirectoryCatalog.editorialInfo(forName: entry.name) != nil
                    || Self.protectedBundleCategory(forName: entry.name) != nil
                group.addTask {
                    await Self.scanDirectory(
                        path: childPath,
                        name: entry.name,
                        seenInodes: seenInodes,
                        insideAggregatedContainer: childInsideAggregatedContainer,
                        onEntries: onEntries
                    )
                }
            }
            for await (child, childTypeIndex) in group {
                subdirChildren.append(child)
                typeIndex.merge(childTypeIndex)
            }
        }

        // Whole aggregated containers (`.app` bundles, dependency/build
        // directories, protected creative-suite/app-adjacent bundles)
        // become one type-index entry each, recorded here rather than at
        // classification time - only now, after each child's subtree has
        // fully returned, is its complete recursive size known. Skipped
        // entirely when this directory is itself already inside one of
        // any kind, so nothing nested inside an aggregated container is
        // ever separately or doubly recorded - see
        // `insideAggregatedContainer`'s doc comment.
        if !insideAggregatedContainer {
            for child in subdirChildren where child.name.hasSuffix(".app") {
                typeIndex.record(
                    FileTypeIndexEntry(path: child.path, name: child.name, sizeBytes: child.size, isPhotosManaged: false),
                    category: .applications
                )
            }
            for child in subdirChildren where DependencyDirectoryCatalog.editorialInfo(forName: child.name) != nil {
                typeIndex.record(
                    FileTypeIndexEntry(
                        path: child.path,
                        name: child.name,
                        sizeBytes: child.size,
                        isPhotosManaged: false,
                        isDependencyDirectory: true
                    ),
                    category: .codeAndProjects
                )
            }
            for child in subdirChildren {
                guard let category = Self.protectedBundleCategory(forName: child.name) else { continue }
                typeIndex.record(
                    FileTypeIndexEntry(
                        path: child.path,
                        name: child.name,
                        sizeBytes: child.size,
                        isPhotosManaged: false,
                        isProtectedBundle: true
                    ),
                    category: category
                )
            }
        }

        let subdirTotal = subdirChildren.reduce(into: Int64(0)) { $0 += $1.size }
        let subdirItems = subdirChildren.reduce(into: 0) { $0 += $1.itemCount }

        return (
            FileNode(
                name: name,
                path: path,
                size: fileTotal + subdirTotal,
                isDirectory: true,
                children: fileChildren + subdirChildren,
                itemCount: fileChildren.count + subdirItems + 1
            ),
            typeIndex
        )
    }

    /// The `FileTypeCategory` a `BundleProtection`-recognized creative-suite
    /// library or app-adjacent bundle aggregates into, or `nil` if `name`
    /// isn't one. `.photoslibrary` is deliberately not here - see
    /// `insideProtectedBundle`'s doc comment on why its contents stay
    /// individually classified.
    private static func protectedBundleCategory(forName name: String) -> FileTypeCategory? {
        let videoSuffixes = [".fcpbundle", ".imovielibrary", ".theater", ".tvlibrary"]
        let audioSuffixes = [".logicx", ".band"]
        let otherSuffixes = [".framework", ".bundle", ".xpc", ".plugin", ".appex", ".sparsebundle"]

        if videoSuffixes.contains(where: { name.hasSuffix($0) }) { return .videos }
        if audioSuffixes.contains(where: { name.hasSuffix($0) }) { return .audio }
        if otherSuffixes.contains(where: { name.hasSuffix($0) }) { return .other }
        return nil
    }
}
