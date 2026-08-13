import Foundation

/// Configuration for a large-file scan.
public struct LargeFileFilter: Sendable {
    /// Only files at or above this logical size are considered. Typical
    /// presets are 100 MB, 1 GB, and 5 GB.
    public var minimumSize: Int64
    /// When set, only files not modified since this date are kept. `nil`
    /// disables the filter.
    public var notModifiedSince: Date?
    /// When set, only files not opened since this date are kept, using
    /// `LargeFileEntry.lastUsedDate`. `nil` disables the filter. A file
    /// whose last-used date is unknown always passes this filter - see
    /// `LargeFileEntry.lastUsedDate`.
    public var notOpenedSince: Date?
    /// When `false` (the default), files under a developer-tool directory
    /// (`node_modules`, `.git`, package-manager caches, build output - see
    /// `DeveloperArtifactFolders`) never become candidates. See
    /// `DuplicateScanOptions.includeDeveloperArtifacts` for why - the same
    /// reasoning applies here.
    public var includeDeveloperArtifacts: Bool

    public init(
        minimumSize: Int64,
        notModifiedSince: Date? = nil,
        notOpenedSince: Date? = nil,
        includeDeveloperArtifacts: Bool = false
    ) {
        self.minimumSize = minimumSize
        self.notModifiedSince = notModifiedSince
        self.notOpenedSince = notOpenedSince
        self.includeDeveloperArtifacts = includeDeveloperArtifacts
    }
}

/// Finds files at or above a size threshold within an already-scanned tree,
/// optionally narrowed by how long they've gone unmodified or unopened.
///
/// Like `DuplicateDetector`, this runs entirely over an in-memory `FileNode`
/// tree and gathers per-file facts via on-demand `lstat` (`FileStatReader`)
/// rather than adding them to `FileNode` itself - see that type's doc
/// comment for why.
public enum LargeFileFinder {
    /// Reuses `AppLastUsedDateProvider` (Spotlight `kMDItemLastUsedDate`
    /// with a filesystem-mtime fallback) as the default last-used source.
    /// Despite the "App" in its name it isn't app-specific internally - it
    /// just looks up metadata for whatever path it's given - so it applies
    /// equally well here.
    ///
    /// A thin public wrapper, not a direct reference to
    /// `AppLastUsedDateProvider.lastUsedDate(forAppAtPath:)`: that type is
    /// `internal`, and a public API's default parameter value must be at
    /// least as visible as the API itself.
    public static func defaultLastUsedDateProvider(_ path: String) async -> Date? {
        await AppLastUsedDateProvider.lastUsedDate(forAppAtPath: path)
    }

    /// Overridable `lastUsedDateProvider` for testing.
    public static func find(
        in root: FileNode,
        filter: LargeFileFilter,
        lastUsedDateProvider: @Sendable (String) async -> Date? = LargeFileFinder.defaultLastUsedDateProvider
    ) async -> [LargeFileEntry] {
        let candidatePaths = collectCandidatePaths(
            from: root,
            minimumSize: filter.minimumSize,
            includeDeveloperArtifacts: filter.includeDeveloperArtifacts
        )
        guard !candidatePaths.isEmpty else { return [] }

        var results: [LargeFileEntry] = []
        results.reserveCapacity(candidatePaths.count)

        for path in candidatePaths {
            guard !Task.isCancelled else { break }

            guard let stats = (try? await BlockingIO.run { FileStatReader.facts(atPath: path) }) ?? nil else { continue }
            guard stats.logicalSize >= filter.minimumSize else { continue }

            let lastUsed = await lastUsedDateProvider(path)
            let entry = LargeFileEntry(file: stats, lastUsedDate: lastUsed)
            if matches(entry, filter: filter) {
                results.append(entry)
            }
        }

        return results.sorted { $0.file.logicalSize > $1.file.logicalSize }
    }

    /// Pure predicate, no I/O - the entire filtering decision for one
    /// already-gathered entry, kept separate from `find` so it's unit
    /// testable without touching the filesystem.
    static func matches(_ entry: LargeFileEntry, filter: LargeFileFilter) -> Bool {
        guard entry.file.logicalSize >= filter.minimumSize else { return false }

        if let cutoff = filter.notModifiedSince, entry.file.modifiedAt >= cutoff {
            return false
        }

        if let cutoff = filter.notOpenedSince, let lastUsed = entry.lastUsedDate, lastUsed >= cutoff {
            return false
        }

        return true
    }

    /// Same shape as `DuplicateDetector.collectCandidatePaths`: an iterative
    /// walk that skips directories, symlinks, synthetic grouping nodes,
    /// anything inside a structured bundle (see `BundleProtection`), and -
    /// unless `includeDeveloperArtifacts` is set - anything inside a
    /// developer-tool directory (see `DeveloperArtifactFolders`). A
    /// giant file surfaced here that can't safely be deleted afterward
    /// would just be a dead end.
    ///
    /// The floor applied here is loosened to a quarter of the real
    /// threshold, for the same reason `DuplicateDetector` loosens its
    /// prefilter: `FileNode.size` is on-disk *allocated* size, and a
    /// heavily APFS-compressed file can have a much smaller allocated size
    /// than its logical size. `find` re-applies the real threshold against
    /// `stats.logicalSize` after `lstat`, so this only widens the candidate
    /// set, never the final result.
    private static func collectCandidatePaths(
        from root: FileNode,
        minimumSize: Int64,
        includeDeveloperArtifacts: Bool
    ) -> [String] {
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
            guard node.size >= prefilterFloor else { continue }
            paths.append(node.path)
        }

        return paths
    }
}
