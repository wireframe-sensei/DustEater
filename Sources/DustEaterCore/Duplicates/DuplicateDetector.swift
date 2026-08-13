import Foundation

/// Configuration for a duplicate scan.
public struct DuplicateScanOptions: Sendable {
    /// Files smaller than this (by logical size) are skipped entirely.
    /// Files well below this floor dominate file *count* on a typical disk
    /// but almost none of its space, so scanning them costs far more than
    /// it's worth. 1 MB by default; exposed to the user as an adjustable
    /// control.
    public var minimumFileSize: Int64
    /// When `false` (the default), files under a developer-tool directory
    /// (`node_modules`, `.git`, package-manager caches, build output - see
    /// `DeveloperArtifactFolders`) never become candidates. These are
    /// excluded specifically because the same package is routinely
    /// installed byte-identically across many unrelated projects, making
    /// them the single biggest source of noisy, low-value duplicate
    /// reports, and because a duplicate inside a project-local
    /// `node_modules` isn't safe to delete piecemeal the way a duplicate
    /// found elsewhere is - doing so can break that project's build.
    public var includeDeveloperArtifacts: Bool

    public init(minimumFileSize: Int64 = 1 << 20, includeDeveloperArtifacts: Bool = false) {
        self.minimumFileSize = minimumFileSize
        self.includeDeveloperArtifacts = includeDeveloperArtifacts
    }
}

/// Reports incremental progress while a duplicate scan is in-flight.
public struct DuplicateScanProgress: Sendable {
    public enum Phase: Sendable {
        case collecting
        case quickHashing
        case fullHashing
    }

    public let phase: Phase
    public let filesProcessed: Int
    public let totalFiles: Int
    public let currentPath: String
}

/// Finds byte-accurate duplicate files within an already-scanned tree.
///
/// Runs entirely over an in-memory `FileNode` tree produced by a prior
/// `DiskScanner` pass - this does no directory walk of its own and triggers
/// no additional permission prompt. See `FileStatReader`'s doc comment for
/// why timestamps and logical size are gathered here via on-demand `lstat`
/// rather than being added to `FileNode` itself.
///
/// Pipeline: group candidates by exact logical size, collapse hard-link
/// aliases (they share storage, not waste it), quick-hash the first 4 KB of
/// what's left to cheaply split apart near-misses, then full SHA-256 hash
/// only files that survived the quick pass. Every result is byte-identical
/// by construction, so a batch delete built from this output is always safe.
public actor DuplicateDetector {
    private var lastProgressEmitNanos: UInt64 = 0
    private let progressIntervalNanos: UInt64 = 100_000_000
    private var itemsProcessed = 0

    /// Runs `transform` over `items` with up to `maxConcurrent` in flight at
    /// once - a sliding window: as soon as one finishes, the next queued
    /// item starts, rather than either launching everything up front or
    /// waiting for a fixed-size wave to fully complete. `onEach` runs once
    /// per completed item, synchronously on this actor's isolation (this
    /// method is only ever called from within `DuplicateDetector`), so it's
    /// safe to mutate actor-local state from it directly.
    ///
    /// Bounding concurrency here is *not* a contradiction of
    /// `DiskScanner`'s deliberately unbounded directory fan-out: these are
    /// leaf tasks that read one file and return, never needing to acquire a
    /// further permit from this same window to make progress, so there is
    /// no circular wait the way an unbounded *recursive* fan-out could
    /// create.
    private func withConcurrentTasks<Item: Sendable, Output: Sendable>(
        over items: [Item],
        maxConcurrent: Int,
        transform: @escaping @Sendable (Item) async -> Output,
        onEach: (Output, Item) -> Void
    ) async {
        guard !items.isEmpty else { return }
        var iterator = items.makeIterator()

        await withTaskGroup(of: (Output, Item).self) { group in
            for _ in 0..<maxConcurrent {
                guard let item = iterator.next() else { break }
                group.addTask { (await transform(item), item) }
            }
            while let (output, item) = await group.next() {
                onEach(output, item)
                guard !Task.isCancelled else { break }
                if let next = iterator.next() {
                    group.addTask { (await transform(next), next) }
                }
            }
        }
    }

    public init() {}

    public func findDuplicates(
        in root: FileNode,
        options: DuplicateScanOptions = DuplicateScanOptions(),
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async -> [DuplicateSet] {
        itemsProcessed = 0
        lastProgressEmitNanos = 0

        let candidatePaths = Self.collectCandidatePaths(
            from: root,
            minimumSize: options.minimumFileSize,
            includeDeveloperArtifacts: options.includeDeveloperArtifacts
        )
        guard !candidatePaths.isEmpty, !Task.isCancelled else { return [] }

        let statted = await statAll(candidatePaths, onProgress: onProgress)
        guard !Task.isCancelled else { return [] }

        let sizeGroups = DuplicatePartitioner.groupBySize(statted, minimumSize: options.minimumFileSize)
            .map(DuplicatePartitioner.collapsingHardLinks)
            .filter { $0.count > 1 }
        guard !sizeGroups.isEmpty else { return [] }

        var finalSets: [DuplicateSet] = []

        for group in sizeGroups {
            guard !Task.isCancelled else { return [] }

            let quickDigests = await hashAll(group, phase: .quickHashing, onProgress: onProgress) { file in
                await FileHasher.headDigest(atPath: file.path)
            }
            let quickGroups = DuplicatePartitioner.partition(group) { quickDigests[$0.path] }
            guard !quickGroups.isEmpty else { continue }

            for quickGroup in quickGroups {
                guard !Task.isCancelled else { return [] }

                // Files at or under the quick-hash sample size are already
                // fully hashed - the head digest *is* the full digest, so a
                // second read here would be pure waste. Every member of
                // `quickGroup` shares the same `logicalSize` (it descends
                // from one `groupBySize` bucket), so checking one is enough.
                if let representativeSize = quickGroup.first?.logicalSize, representativeSize <= 4096 {
                    if let digest = quickDigests[quickGroup[0].path] {
                        finalSets.append(makeSet(contentHash: digest, files: quickGroup))
                    }
                    continue
                }

                let fullDigests = await hashAll(quickGroup, phase: .fullHashing, onProgress: onProgress) { file in
                    await FileHasher.fullDigest(atPath: file.path)
                }
                let fullGroups = DuplicatePartitioner.partition(quickGroup) { fullDigests[$0.path] }
                for fullGroup in fullGroups {
                    guard let digest = fullDigests[fullGroup[0].path] else { continue }
                    finalSets.append(makeSet(contentHash: digest, files: fullGroup))
                }
            }
        }

        return finalSets.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private func makeSet(contentHash: String, files: [InspectedFile]) -> DuplicateSet {
        DuplicateSet(contentHash: contentHash, files: files.sorted { $0.modifiedAt > $1.modifiedAt })
    }

    /// Iterative (explicit-stack) walk of the tree collecting candidate
    /// paths - not recursive, so a very deep tree can't blow the call stack,
    /// and not actor-isolated, since it touches no shared state.
    ///
    /// Carries "am I inside a protected bundle" and "am I inside a
    /// developer-tool directory" down the walk as it descends, rather than
    /// checking every file's full ancestor chain individually - each check
    /// only costs one comparison per directory, at the point a boundary is
    /// actually crossed.
    private static func collectCandidatePaths(
        from root: FileNode,
        minimumSize: Int64,
        includeDeveloperArtifacts: Bool
    ) -> [String] {
        // Loosened relative to the real floor: `FileNode.size` is
        // *allocated* size, but the real floor applies to *logical* size
        // (enforced later, after `lstat`, in `DuplicatePartitioner.
        // groupBySize`). A heavily APFS-compressed file can have an
        // allocated size well under its logical size, so filtering
        // candidates at the full floor here would silently miss compressed
        // duplicates. Filtering at a quarter of the floor keeps the
        // candidate set small without discarding anything the real,
        // logical-size floor would otherwise have kept.
        let prefilterFloor = max(Int64(1), minimumSize / 4)

        var paths: [String] = []
        var stack: [(node: FileNode, insideBundle: Bool, insideDeveloperArtifact: Bool)] = [(root, false, false)]

        while let (node, insideBundle, insideDeveloperArtifact) = stack.popLast() {
            if node.isDirectory {
                let stillInsideBundle = insideBundle || BundleProtection.isBundleLikeDirectory(node.name)
                let stillInsideDeveloperArtifact = insideDeveloperArtifact
                    || (!includeDeveloperArtifacts && DeveloperArtifactFolders.isDeveloperArtifactDirectory(node.name))
                for child in node.children {
                    stack.append((child, stillInsideBundle, stillInsideDeveloperArtifact))
                }
                continue
            }

            guard !insideBundle, !insideDeveloperArtifact else { continue }
            guard !node.isSymlink, !node.isSyntheticGroupingNode else { continue }
            guard node.size > 0, node.size >= prefilterFloor else { continue }
            paths.append(node.path)
        }

        return paths
    }

    private func statAll(
        _ paths: [String],
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?
    ) async -> [InspectedFile] {
        var results: [InspectedFile] = []
        results.reserveCapacity(paths.count)

        await withConcurrentTasks(over: paths, maxConcurrent: Self.concurrencyLimit, transform: { path in
            (try? await BlockingIO.run { FileStatReader.facts(atPath: path) }) ?? nil
        }, onEach: { file, path in
            if let file { results.append(file) }
            recordProgress(phase: .collecting, total: paths.count, path: path, onProgress: onProgress)
        })

        return results
    }

    private func hashAll(
        _ files: [InspectedFile],
        phase: DuplicateScanProgress.Phase,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?,
        hash: @escaping @Sendable (InspectedFile) async -> String?
    ) async -> [String: String] {
        var digests: [String: String] = [:]
        digests.reserveCapacity(files.count)

        await withConcurrentTasks(over: files, maxConcurrent: Self.concurrencyLimit, transform: hash, onEach: { digest, file in
            if let digest { digests[file.path] = digest }
            recordProgress(phase: phase, total: files.count, path: file.path, onProgress: onProgress)
        })

        return digests
    }

    private func recordProgress(
        phase: DuplicateScanProgress.Phase,
        total: Int,
        path: String,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?
    ) {
        itemsProcessed += 1
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastProgressEmitNanos > progressIntervalNanos else { return }
        lastProgressEmitNanos = now
        onProgress?(DuplicateScanProgress(phase: phase, filesProcessed: itemsProcessed, totalFiles: total, currentPath: path))
    }

    private static let concurrencyLimit = ProcessInfo.processInfo.activeProcessorCount * 4
}
