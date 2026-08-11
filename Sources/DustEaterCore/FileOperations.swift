import Foundation

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

    public static func delete(at path: String, permanently: Bool = false) throws {
        guard canDelete(at: path) else {
            throw FileOperationError.systemProtected
        }

        if permanently {
            try FileManager.default.removeItem(atPath: path)
        } else {
            try moveToTrash(at: path)
        }
    }

    private static func moveToTrash(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public static func clearSystemCaches() throws {
        let cacheURLs: [URL] = [
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        ]

        for cacheURL in cacheURLs {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: nil
            )

            for itemURL in contents {
                do {
                    try FileManager.default.removeItem(at: itemURL)
                } catch {
                    continue
                }
            }
        }
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
