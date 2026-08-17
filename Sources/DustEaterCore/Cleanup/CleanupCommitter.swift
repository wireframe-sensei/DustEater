import Foundation

/// One item successfully moved to the Trash during a commit - the pairing
/// `putBack` needs to restore it. Never produced for a permanent delete,
/// since there is nothing to put back.
public struct TrashedItem: Sendable, Equatable {
    public let originalPath: String
    public let trashedURL: URL

    public init(originalPath: String, trashedURL: URL) {
        self.originalPath = originalPath
        self.trashedURL = trashedURL
    }
}

public struct CommitResult: Sendable {
    public let deletedItemIDs: Set<String>
    /// Every underlying path actually removed, across every committed item -
    /// what the caller folds out of the live scan tree via
    /// `FileNode.removingNode(atPath:)`.
    public let deletedPaths: Set<String>
    public let trashedItems: [TrashedItem]
    public let errors: [String]
    public let reclaimedBytes: Int64
}

/// The single commit path for the Cleanup -> Review -> Receipt flow,
/// replacing the three near-identical per-path delete loops that used to
/// live in `DeveloperKitView.performPurge`, `DuplicatesView.performDelete`,
/// and `AppDetailInspector.proceedWithUninstall` - all three are gone now
/// that Developer Kit and the Duplicates inspector are no longer
/// destinations, so this is consolidating a pattern that was proven
/// triplicated, not introducing a new abstraction ahead of need.
///
/// Runs off the main actor: `FileOperations.delete` for something like a
/// large `DerivedData` folder can take real wall-clock seconds, and this
/// must never freeze the window it's committing from.
public enum CleanupCommitter {
    /// Deletes every `deletablePath` (and, for an app item, the bundle
    /// itself via `deleteAppBundle`) across `items`. Every guard lives here,
    /// once, per path: existence (the window between analysis and
    /// confirmation is real - the filesystem can change), `canDelete`,
    /// `PurgeCatalog.isDenied`, `.reportOnly` refusal, and a running-app
    /// check for items that name a `blockingAppBundleID`. A failure on one
    /// path never aborts the rest - errors accumulate in `CommitResult.errors`.
    public static func commit(_ items: [CleanupItem], permanently: Bool) async -> CommitResult {
        var deletedItemIDs: Set<String> = []
        var deletedPaths: Set<String> = []
        var trashedItems: [TrashedItem] = []
        var errors: [String] = []
        var reclaimedBytes: Int64 = 0

        for item in items {
            guard !item.isReportOnly else {
                errors.append("\(item.name): not deletable, skipped")
                continue
            }
            if let bundleID = item.blockingAppBundleID, FileOperations.isAppRunning(bundleIdentifier: bundleID) {
                errors.append("\(item.name): the owning app is running, skipped")
                continue
            }

            // Counted as deleted only if at least one path was actually
            // removed and none failed - a `deletablePaths` list that turned
            // out to be entirely stale (nothing on disk any more) is a
            // benign no-op, not a success worth crediting bytes for.
            var pathsDeleted = 0
            var itemHadFailure = false
            for path in item.deletablePaths {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                guard FileOperations.canDelete(at: path), !PurgeCatalog.isDenied(path: path) else {
                    errors.append("\(item.name): \(path) is protected, skipped")
                    itemHadFailure = true
                    continue
                }

                do {
                    let trashedURL = path == item.appBundlePath
                        ? try FileOperations.deleteAppBundle(at: path, permanently: permanently)
                        : try FileOperations.delete(at: path, permanently: permanently)
                    deletedPaths.insert(path)
                    pathsDeleted += 1
                    if let trashedURL {
                        trashedItems.append(TrashedItem(originalPath: path, trashedURL: trashedURL))
                    }
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                    itemHadFailure = true
                }
            }

            if pathsDeleted > 0 && !itemHadFailure {
                deletedItemIDs.insert(item.id)
                reclaimedBytes += item.sizeBytes
            }
        }

        return CommitResult(
            deletedItemIDs: deletedItemIDs,
            deletedPaths: deletedPaths,
            trashedItems: trashedItems,
            errors: errors,
            reclaimedBytes: reclaimedBytes
        )
    }

    /// Restores every trashed item to its original location. Best-effort,
    /// same as `commit`: one item failing (e.g. something new was already
    /// created at the original path) doesn't stop the rest from being put
    /// back. Returns a human-readable error per failure, empty on full success.
    public static func putBack(_ items: [TrashedItem]) async -> [String] {
        var errors: [String] = []
        for item in items {
            do {
                try FileOperations.putBack(from: item.trashedURL, to: item.originalPath)
            } catch {
                errors.append("\(item.originalPath): \(error.localizedDescription)")
            }
        }
        return errors
    }
}
