import Foundation
import Testing
@testable import DustEaterCore

@Suite("XcodeArchiveLister")
struct XcodeArchiveListerTests {
    private func writeInfoPlist(name: String, creationDate: Date, at archiveURL: URL) throws {
        try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "ArchiveVersion": 2,
            "Name": name,
            "CreationDate": creationDate,
            "SchemeName": name,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: archiveURL.appendingPathComponent("Info.plist"))
    }

    private func dir(_ name: String, path: String, size: Int64, children: [FileNode] = []) -> FileNode {
        FileNode(name: name, path: path, size: size, isDirectory: true, children: children)
    }

    @Test func listsArchivesWithNameAndDateFromInfoPlist() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let archivesRoot = tempDir.appendingPathComponent("Library/Developer/Xcode/Archives")
        let dateFolder = archivesRoot.appendingPathComponent("2024-01-15")
        let archiveURL = dateFolder.appendingPathComponent("MyApp 1-15-24, 3.30 PM.xcarchive")
        let creationDate = Date(timeIntervalSince1970: 1_705_329_000)
        try writeInfoPlist(name: "MyApp", creationDate: creationDate, at: archiveURL)

        let archiveNode = dir(archiveURL.lastPathComponent, path: archiveURL.path, size: 500_000_000)
        let dateFolderNode = dir(dateFolder.lastPathComponent, path: dateFolder.path, size: 500_000_000, children: [archiveNode])
        let archivesNode = dir("Archives", path: archivesRoot.path, size: 500_000_000, children: [dateFolderNode])
        let developerNode = dir("Xcode", path: archivesRoot.deletingLastPathComponent().path, size: 500_000_000, children: [archivesNode])
        let libraryDeveloperNode = dir("Developer", path: developerNode.path.replacingOccurrences(of: "/Xcode", with: ""), size: 500_000_000, children: [developerNode])
        let libraryNode = dir("Library", path: tempDir.appendingPathComponent("Library").path, size: 500_000_000, children: [libraryDeveloperNode])
        let root = dir(tempDir.lastPathComponent, path: tempDir.path, size: 500_000_000, children: [libraryNode])

        let archives = await XcodeArchiveLister.listArchives(in: root, homeDirectory: tempDir.path)

        #expect(archives.count == 1)
        let archive = try #require(archives.first)
        #expect(archive.appName == "MyApp")
        #expect(archive.creationDate == creationDate)
        #expect(archive.sizeBytes == 500_000_000)
        #expect(archive.path == archiveURL.path)
    }

    @Test func returnsEmptyWhenArchivesFolderWasNotInTheScannedTree() async {
        let root = dir("x", path: "/Users/x", size: 0)

        let archives = await XcodeArchiveLister.listArchives(in: root, homeDirectory: "/Users/x")

        #expect(archives.isEmpty)
    }

    @Test func fallsBackToFolderNameWhenInfoPlistIsMissing() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // No Info.plist written at this path - listArchives must still
        // return a usable row rather than silently dropping the archive.
        let archivesRoot = tempDir.appendingPathComponent("Library/Developer/Xcode/Archives")
        let dateFolder = archivesRoot.appendingPathComponent("2024-01-15")
        let archiveURL = dateFolder.appendingPathComponent("Untitled.xcarchive")

        let archiveNode = dir(archiveURL.lastPathComponent, path: archiveURL.path, size: 100)
        let dateFolderNode = dir(dateFolder.lastPathComponent, path: dateFolder.path, size: 100, children: [archiveNode])
        let archivesNode = dir("Archives", path: archivesRoot.path, size: 100, children: [dateFolderNode])
        let root = dir("x", path: tempDir.path, size: 100, children: [
            dir("Library", path: tempDir.appendingPathComponent("Library").path, size: 100, children: [
                dir("Developer", path: tempDir.appendingPathComponent("Library/Developer").path, size: 100, children: [
                    dir("Xcode", path: tempDir.appendingPathComponent("Library/Developer/Xcode").path, size: 100, children: [archivesNode]),
                ]),
            ]),
        ])

        let archives = await XcodeArchiveLister.listArchives(in: root, homeDirectory: tempDir.path)

        #expect(archives.count == 1)
        #expect(archives.first?.appName == "Untitled")
        #expect(archives.first?.creationDate == nil)
    }
}
