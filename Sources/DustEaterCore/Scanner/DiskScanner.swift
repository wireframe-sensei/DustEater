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
/// locking is needed to accumulate sizes — each level simply sums the sizes
/// its children returned.
///
/// Task fan-out itself is intentionally *unbounded* — Swift tasks are cheap
/// (they multiplex over the cooperative pool at suspension points rather
/// than consuming an OS thread each) — so gating task creation with a
/// shared permit pool is both unnecessary and dangerous here: a whole
/// generation of sibling directories could simultaneously hold the last
/// free permits while each waits to acquire one more permit to recurse into
/// its own children, with no task left running to ever release one. That
/// exact scenario deadlocked an earlier version of this scanner on wide,
/// deep trees (e.g. npm's hashed cache directories). The only genuinely
/// scarce resource — OS threads doing blocking syscalls — is bounded
/// separately and non-recursively by `BlockingIO`'s dispatch queue, which
/// has no such circular dependency.
public actor DiskScanner {
    private var itemsScanned = 0
    private var bytesScanned: Int64 = 0
    /// Guarded by a raw lock rather than actor isolation: dedup is checked
    /// once per *file* (not per directory), so it sits on the hottest path
    /// in the whole scan. Actor isolation would force every one of those
    /// checks — across every concurrently-running directory task — to funnel
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
        let name = (rootPath as NSString).lastPathComponent
        seenInodes.withLock { $0.removeAll() }
        return await Self.scanDirectory(
            path: rootPath,
            name: name,
            seenInodes: seenInodes,
            onEntries: { [weak self] items, bytes, path in
                await self?.reportProgress(addedItems: items, addedBytes: bytes, path: path, handler: onProgress)
            }
        )
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
    /// `static`, not an instance method — this keeps the CPU-bound tree
    /// construction (as opposed to `reportProgress`'s bookkeeping) off the
    /// actor's serial executor entirely, so sibling directory tasks in the
    /// `TaskGroup` below can genuinely run concurrently instead of each
    /// needing to acquire `self`'s isolation just to build a `FileNode`.
    private static func scanDirectory(
        path: String,
        name: String,
        seenInodes: OSAllocatedUnfairLock<Set<UInt64>>,
        onEntries: @escaping @Sendable (Int, Int64, String) async -> Void
    ) async -> FileNode {
        let entries: [RawDirEntry]
        do {
            entries = try await BlockingIO.run { try AttrListBulkReader.listDirectory(atPath: path) }
        } catch {
            // Permission denied or the entry vanished mid-scan; treat as an
            // empty leaf rather than aborting the whole scan.
            return FileNode(name: name, path: path, size: 0, isDirectory: true)
        }

        var fileTotal: Int64 = 0
        var fileChildren: [FileNode] = []
        var subdirEntries: [RawDirEntry] = []
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
            }
        }

        await onEntries(fileChildren.count, fileTotal, path)

        guard !subdirEntries.isEmpty else {
            return FileNode(
                name: name,
                path: path,
                size: fileTotal,
                isDirectory: true,
                children: fileChildren,
                itemCount: fileChildren.count + 1
            )
        }

        var subdirChildren: [FileNode] = []
        subdirChildren.reserveCapacity(subdirEntries.count)

        await withTaskGroup(of: FileNode.self) { group in
            for entry in subdirEntries {
                var childPath = path
                childPath.append("/")
                childPath.append(entry.name)
                group.addTask {
                    await Self.scanDirectory(path: childPath, name: entry.name, seenInodes: seenInodes, onEntries: onEntries)
                }
            }
            for await child in group {
                subdirChildren.append(child)
            }
        }

        let subdirTotal = subdirChildren.reduce(into: Int64(0)) { $0 += $1.size }
        let subdirItems = subdirChildren.reduce(into: 0) { $0 += $1.itemCount }

        return FileNode(
            name: name,
            path: path,
            size: fileTotal + subdirTotal,
            isDirectory: true,
            children: fileChildren + subdirChildren,
            itemCount: fileChildren.count + subdirItems + 1
        )
    }
}
