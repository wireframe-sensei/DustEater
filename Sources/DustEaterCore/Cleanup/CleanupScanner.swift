import Foundation
import Observation

public enum CleanupFindingsState: Sendable {
    case idle
    /// Findings appear here as each underlying source finishes, so the
    /// Cleanup screen can render groups incrementally instead of blocking on
    /// the slowest one (duplicate hashing is by far the longest-running
    /// piece). Not partial-item streaming within a finding - that's item 5,
    /// out of scope here - just "don't show a bare spinner while duplicates
    /// hash."
    case scanning(measured: [CleanupFinding])
    /// A real, distinct state from `.scanning` - an empty array here means
    /// this Mac genuinely has nothing to clean up, not that scanning is
    /// still running. See CLAUDE.md's "a loading state needs a way to tell
    /// still-loading apart from loaded-and-found-nothing."
    case loaded([CleanupFinding])
    case failed(String)
}

/// Drives every source `CleanupFindingsBuilder` needs (`PurgeScanner`,
/// `AppManagerScanner`, `LargeFileFinder`, `DuplicateDetector`) and
/// assembles the ranked `[CleanupFinding]` the Cleanup screen shows.
///
/// Follows the house `@Observable @MainActor` service pattern already used
/// by `PurgeScanner` and `AppManagerScanner`: one cancel-and-replace `Task`,
/// a synchronous void entry point, `guard !Task.isCancelled` after every
/// await.
@Observable
@MainActor
public final class CleanupScanner {
    public private(set) var state: CleanupFindingsState = .idle

    private var task: Task<Void, Never>?
    private let duplicateDetector = DuplicateDetector()

    public init() {}

    public func scan(root: FileNode) {
        task?.cancel()
        state = .scanning(measured: [])

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var findings: [CleanupFinding] = []

            @MainActor func publish() {
                self.state = .scanning(measured: CleanupFindingsBuilder.rank(findings.map { $0 }))
            }

            // Purge-catalog-derived findings (package caches, Xcode build
            // artifacts, simulator runtimes) all read from one
            // `PurgeScanner.categories` pass over the same measured targets.
            let categories = await PurgeScanner.categories(in: root)
            guard !Task.isCancelled else { return }
            if let f = CleanupFindingsBuilder.packageManagerCaches(from: categories) { findings.append(f) }
            if let f = CleanupFindingsBuilder.xcodeBuildArtifacts(from: categories) { findings.append(f) }
            if let f = CleanupFindingsBuilder.simulatorRuntimes(from: categories) { findings.append(f) }
            publish()

            guard !Task.isCancelled else { return }
            let installedApps = await AppManagerScanner.scanInstalledApps()
            guard !Task.isCancelled else { return }
            if let f = CleanupFindingsBuilder.unusedApplications(installed: installedApps) { findings.append(f) }
            publish()

            guard !Task.isCancelled else { return }
            if let f = await CleanupFindingsBuilder.oldDownloads(in: root) {
                findings.append(f)
                publish()
            }

            guard !Task.isCancelled else { return }
            let duplicateSets = await self.duplicateDetector.findDuplicates(in: root)
            guard !Task.isCancelled else { return }
            if let f = CleanupFindingsBuilder.duplicateFiles(from: duplicateSets) { findings.append(f) }

            guard !Task.isCancelled else { return }
            self.state = .loaded(CleanupFindingsBuilder.rank(findings.map { $0 }))
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// Folds a commit's deleted paths out of the loaded findings without a
    /// rescan - mirrors `PurgeScanner.removeDeletedPaths`. Drops an item
    /// entirely if *any* of its paths were deleted (rather than trying to
    /// patch its size), since a partially-deleted item's remaining size is
    /// no longer trustworthy without re-measuring. A no-op in any state
    /// other than `.loaded`.
    public func removeDeletedPaths(_ paths: Set<String>) {
        guard case .loaded(let findings) = state else { return }
        let updated = findings.compactMap { finding -> CleanupFinding? in
            let remainingItems = finding.items.filter { item in
                item.deletablePaths.allSatisfy { !paths.contains($0) }
            }
            guard !remainingItems.isEmpty else { return nil }
            return CleanupFinding(id: finding.id, items: remainingItems)
        }
        state = .loaded(updated)
    }
}
