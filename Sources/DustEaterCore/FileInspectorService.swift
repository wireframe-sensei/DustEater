import Foundation
import Observation

/// State of a duplicate scan.
public enum DuplicateState: Sendable {
    case idle
    case scanning(DuplicateScanProgress)
    /// A real, distinct state from `.scanning` - an empty array here means
    /// the scan finished and genuinely found nothing, not that it's still
    /// running. See CLAUDE.md's "a loading state needs a way to tell
    /// still-loading apart from loaded-and-found-nothing."
    case loaded([DuplicateSet])
    case failed(String)
}

/// State of a large-file scan. No progress payload on `.scanning`: unlike
/// duplicate hashing, this is bounded by candidate count and stat/Spotlight
/// lookups rather than multi-gigabyte reads, so it stays fast enough that a
/// plain indeterminate state is honest rather than misleading.
public enum LargeFileState: Sendable {
    case idle
    case scanning
    case loaded([LargeFileEntry])
    case failed(String)
}

/// Drives the duplicate and large-file inspectors over an already-scanned
/// `FileNode` tree, and exposes their state for SwiftUI to observe.
///
/// Follows the same shape as `ScanCoordinator` and `DiskTelemetryService`:
/// one cancellable `Task` owned per operation, so starting a new scan (or
/// explicitly cancelling) supersedes whatever was in flight.
@Observable
@MainActor
public final class FileInspectorService {
    public private(set) var duplicateState: DuplicateState = .idle
    public private(set) var largeFileState: LargeFileState = .idle

    private var duplicateTask: Task<Void, Never>?
    private var largeFileTask: Task<Void, Never>?

    public init() {}

    public func findDuplicates(in root: FileNode, options: DuplicateScanOptions = DuplicateScanOptions()) {
        duplicateTask?.cancel()
        duplicateState = .scanning(DuplicateScanProgress(phase: .collecting, filesProcessed: 0, totalFiles: 0, currentPath: root.path))

        duplicateTask = Task { @MainActor [weak self] in
            let detector = DuplicateDetector()
            let sets = await detector.findDuplicates(in: root, options: options) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.applyDuplicateProgress(progress)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.duplicateState = .loaded(sets)
        }
    }

    public func cancelDuplicateScan() {
        duplicateTask?.cancel()
        duplicateTask = nil
        duplicateState = .idle
    }

    public func findLargeFiles(in root: FileNode, filter: LargeFileFilter) {
        largeFileTask?.cancel()
        largeFileState = .scanning

        largeFileTask = Task { @MainActor [weak self] in
            let entries = await LargeFileFinder.find(in: root, filter: filter)
            guard let self, !Task.isCancelled else { return }
            self.largeFileState = .loaded(entries)
        }
    }

    public func cancelLargeFileScan() {
        largeFileTask?.cancel()
        largeFileTask = nil
        largeFileState = .idle
    }

    /// Filters deleted paths out of both loaded lists in place, so a batch
    /// delete reconciles the inspector's own lists without a rescan -
    /// mirroring `AppManagerScanner`'s `reconcile*` methods and
    /// `ScanCoordinator.updateTree`. A no-op in any state other than
    /// `.loaded`.
    public func removeDeletedPaths(_ paths: Set<String>) {
        if case .loaded(let sets) = duplicateState {
            let updatedSets = sets.compactMap { set -> DuplicateSet? in
                let remaining = set.files.filter { !paths.contains($0.path) }
                // A set of one file is no longer a duplicate of anything.
                guard remaining.count > 1 else { return nil }
                return DuplicateSet(contentHash: set.contentHash, files: remaining)
            }
            duplicateState = .loaded(updatedSets)
        }

        if case .loaded(let entries) = largeFileState {
            largeFileState = .loaded(entries.filter { !paths.contains($0.file.path) })
        }
    }

    /// The current user's Downloads folder, plus a best-effort scan of
    /// every other visible account's Downloads folder under `/Users` - a
    /// full-disk scan can see other accounts' home directories, and
    /// "Select All in Downloads" should recognize all of them, not just the
    /// current user's.
    public static func defaultDownloadsPaths() -> [String] {
        var paths: [String] = []

        if let current = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            paths.append(current.path)
        }

        if let accountNames = try? FileManager.default.contentsOfDirectory(atPath: "/Users") {
            for name in accountNames {
                let downloadsPath = "/Users/\(name)/Downloads"
                guard !paths.contains(downloadsPath) else { continue }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: downloadsPath, isDirectory: &isDirectory), isDirectory.boolValue {
                    paths.append(downloadsPath)
                }
            }
        }

        return paths
    }

    private func applyDuplicateProgress(_ progress: DuplicateScanProgress) {
        // A cancel/new-scan may have raced ahead of this stale update.
        guard case .scanning = duplicateState else { return }
        duplicateState = .scanning(progress)
    }
}
