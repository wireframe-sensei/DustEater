import Foundation

/// One `.xcarchive` bundle, named and dated from its own `Info.plist` rather
/// than its folder name (which is stable but not what a user recognizes an
/// archive by).
public struct XcodeArchive: Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let appName: String
    public let creationDate: Date?
    public let sizeBytes: Int64

    public init(path: String, appName: String, creationDate: Date?, sizeBytes: Int64) {
        self.path = path
        self.appName = appName
        self.creationDate = creationDate
        self.sizeBytes = sizeBytes
    }
}

/// Lists individual archives under Xcode's Archives folder, for the
/// drill-in list that lets a user delete one specific old archive instead of
/// a single bulk "Archives (14 GB)" toggle.
///
/// A bulk toggle isn't safe for this category: an `.xcarchive` holds the
/// dSYM needed to symbolicate a crash report from a build that may have
/// shipped, and once it's gone there's no way back - rebuilding produces a
/// different UUID, so there's no such thing as "just build it again."
/// `PurgeCatalog.definitions` deliberately excludes Archives from the bulk
/// catalog for exactly this reason; this is the only place Archives becomes
/// deletable, one archive at a time.
public enum XcodeArchiveLister {
    /// `~/Library/Developer/Xcode/Archives/<date-folder>/<Name> <date,
    /// time>.xcarchive` - two levels of folders, and only the deepest is an
    /// actual archive. Reads entirely from the already-scanned tree for
    /// structure and size (`homeDirectory` is a parameter for the same
    /// reason as `PurgeCatalog.definitions` - testable against a fake home).
    /// If the scan didn't cover the Archives folder, this returns empty
    /// rather than falling back to a fresh directory walk - the whole point
    /// of reusing `root` is to avoid a second permission prompt.
    ///
    /// Each archive's `Info.plist` is still read from disk (a few hundred
    /// bytes, not a directory scan) since a plist's contents - the app name
    /// and creation date a user actually recognizes an archive by - aren't
    /// something `FileNode` carries.
    public static func listArchives(
        in root: FileNode,
        homeDirectory: String = NSHomeDirectory()
    ) async -> [XcodeArchive] {
        let archivesPath = homeDirectory + "/Library/Developer/Xcode/Archives"
        guard let archivesNode = root.node(atPath: archivesPath) else { return [] }

        var archiveNodes: [FileNode] = []
        for dateFolder in archivesNode.children where dateFolder.isDirectory {
            for candidate in dateFolder.children where candidate.isDirectory && candidate.name.hasSuffix(".xcarchive") {
                archiveNodes.append(candidate)
            }
        }

        var archives: [XcodeArchive] = []
        archives.reserveCapacity(archiveNodes.count)
        for node in archiveNodes {
            guard !Task.isCancelled else { break }
            let info = await readInfoPlist(atArchivePath: node.path)
            archives.append(XcodeArchive(
                path: node.path,
                appName: info.appName ?? node.name.replacingOccurrences(of: ".xcarchive", with: ""),
                creationDate: info.creationDate,
                sizeBytes: node.size
            ))
        }

        return archives.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    private static func readInfoPlist(atArchivePath archivePath: String) async -> (appName: String?, creationDate: Date?) {
        let plistPath = archivePath + "/Info.plist"
        let result = try? await BlockingIO.run { () -> (String?, Date?) in
            guard let data = FileManager.default.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                return (nil, nil)
            }
            return (plist["Name"] as? String, plist["CreationDate"] as? Date)
        }
        return (result?.0, result?.1)
    }
}
