import Foundation
import AppKit

public struct FileOperations {
    // `/var`, `/etc`, and `/tmp` are the public symlinks to `/private/var`,
    // `/private/etc`, `/private/tmp` - listed here in their public form
    // because `NSString.standardizingPath` (used below) collapses the
    // `/private/...` form down to this one before the comparison runs, so a
    // `/private/...` entry here would never actually match anything.
    private static let systemPaths = [
        "/System",
        "/Library",
        "/Applications",
        "/usr",
        "/var",
        "/etc",
        "/tmp",
        "/bin",
        "/sbin",
        "/opt",
    ]

    /// Default per-user folders macOS creates automatically. Deleting one of
    /// these wholesale is almost always a mistake - a cluttered Downloads
    /// folder should be emptied file by file, not removed as a unit - so
    /// these are protected by *exact* path below, not by prefix like
    /// `systemPaths` above: individual items inside them stay deletable,
    /// only the folder itself is blocked.
    private static let defaultUserFolderNames = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Library",
    ]

    public static func isSystemProtected(path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        let isUnderSystemPath = systemPaths.contains { systemPath in
            normalizedPath.hasPrefix(systemPath + "/") || normalizedPath == systemPath
        }
        if isUnderSystemPath { return true }

        return isProtectedUserFolder(normalizedPath)
    }

    /// True for `/Users` itself, for any account's home directory directly
    /// under it (`/Users/<name>`), and for that account's default folders
    /// one level below (`/Users/<name>/Documents`, etc.). Deliberately
    /// path-shaped rather than keyed off `NSHomeDirectory()`, so a full-disk
    /// scan that can see other accounts' home folders protects those too,
    /// not just the current user's.
    private static func isProtectedUserFolder(_ path: String) -> Bool {
        if path == "/Users" { return true }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.first == "Users" else { return false }

        if components.count == 2 { return true } // /Users/<name>
        if components.count == 3, defaultUserFolderNames.contains(String(components[2])) {
            return true // /Users/<name>/Documents, /Users/<name>/Downloads, ...
        }
        return false
    }

    public static func canDelete(at path: String) -> Bool {
        !isSystemProtected(path: path)
    }

    /// Returns the item's new location in the Trash, or `nil` for a
    /// permanent delete - the handle a caller needs to offer "Put Back"
    /// later. `@discardableResult` so every existing call site that only
    /// cared about the throw keeps compiling unchanged.
    @discardableResult
    public static func delete(at path: String, permanently: Bool = false) throws -> URL? {
        guard canDelete(at: path) else {
            throw FileOperationError.systemProtected
        }

        if permanently {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } else {
            return try moveToTrash(at: path)
        }
    }

    @discardableResult
    private static func moveToTrash(at path: String) throws -> URL {
        let url = URL(fileURLWithPath: path)
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        // `trashItem` always populates `resultingItemURL` on success - this
        // guard exists only because the API's type is an optional pointer,
        // not because a nil result is an expected outcome.
        guard let trashedURL = trashedURL as URL? else {
            throw FileOperationError.deletionFailed("Trashed the item but couldn't determine its new location.")
        }
        return trashedURL
    }

    /// Moves an item back from the Trash to its original location - the
    /// "Put Back" half of `delete(at:permanently: false)`. Refuses to
    /// clobber something already sitting at `originalPath` (e.g. the user
    /// recreated a file with the same name after trashing the old one) and
    /// recreates any intermediate directories the original delete removed.
    public static func putBack(from trashedURL: URL, to originalPath: String) throws {
        guard !FileManager.default.fileExists(atPath: originalPath) else {
            throw FileOperationError.deletionFailed("Something already exists at \(originalPath).")
        }

        let parent = (originalPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: trashedURL, to: URL(fileURLWithPath: originalPath))
    }

    /// True only for a direct child of `/Applications` or `~/Applications`
    /// whose name ends in `.app`. Nested bundles (e.g. helper apps inside
    /// Xcode.app) and `/System/Applications` (not a direct child of
    /// `/Applications`) are excluded by construction.
    public static func canDeleteAppBundle(at path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath
        guard normalizedPath.hasSuffix(".app") else { return false }

        let parent = (normalizedPath as NSString).deletingLastPathComponent
        let allowedParents = [
            "/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]
        return allowedParents.contains(parent)
    }

    @discardableResult
    public static func deleteAppBundle(at path: String, permanently: Bool = false) throws -> URL? {
        guard canDeleteAppBundle(at: path) else {
            throw FileOperationError.systemProtected
        }

        if permanently {
            try FileManager.default.removeItem(atPath: path)
            return nil
        } else {
            return try moveToTrash(at: path)
        }
    }

    public static func isAppRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleIdentifier
        }
    }

    public static func terminateApp(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return false
        }
        return app.terminate()
    }
}

public enum FileOperationError: LocalizedError {
    case systemProtected
    case deletionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .systemProtected:
            return "Cannot delete system-protected files or folders."
        case .deletionFailed(let message):
            return "Deletion failed: \(message)"
        }
    }
}
