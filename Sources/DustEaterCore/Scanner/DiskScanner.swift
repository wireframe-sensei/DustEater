import Foundation

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

    public init() {}

    /// Scans `rootPath` recursively and returns the resulting tree.
    /// - Parameter onProgress: called periodically with a running total of
    ///   items/bytes scanned. May be invoked from arbitrary tasks; keep it cheap.
    public func scan(
        rootPath: String,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> FileNode {
        let name = (rootPath as NSString).lastPathComponent
        return await Self.scanDirectory(
            path: rootPath,
            name: name,
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
        handler?(ScanProgress(itemsScanned: itemsScanned, bytesScanned: bytesScanned, currentPath: path))
    }

    /// Recursively scans one directory. Files are summed directly; each
    /// subdirectory is scanned in its own child task, and results are
    /// folded together as they complete.
    private static func scanDirectory(
        path: String,
        name: String,
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
                fileTotal += entry.allocSize
                var childPath = path
                childPath.append("/")
                childPath.append(entry.name)
                fileChildren.append(
                    FileNode(
                        name: entry.name,
                        path: childPath,
                        size: entry.allocSize,
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
                    await scanDirectory(path: childPath, name: entry.name, onEntries: onEntries)
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
