import Foundation
import Testing
@testable import DustEaterCore

struct LargeFileFinderTests {
    private func makeEntry(
        path: String = "/a",
        size: Int64,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_000_000),
        lastUsedDate: Date?
    ) -> LargeFileEntry {
        let file = InspectedFile(
            path: path,
            name: (path as NSString).lastPathComponent,
            logicalSize: size,
            allocatedSize: size,
            modifiedAt: modifiedAt,
            accessedAt: modifiedAt,
            createdAt: modifiedAt,
            deviceID: 1,
            inode: 1
        )
        return LargeFileEntry(file: file, lastUsedDate: lastUsedDate)
    }

    // MARK: matches - size

    @Test func matchesRejectsFilesBelowMinimumSize() {
        let entry = makeEntry(size: 99, lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100)
        #expect(!LargeFileFinder.matches(entry, filter: filter))
    }

    @Test func matchesAcceptsFilesAtExactlyMinimumSize() {
        let entry = makeEntry(size: 100, lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100)
        #expect(LargeFileFinder.matches(entry, filter: filter))
    }

    // MARK: matches - modification date

    @Test func matchesRejectsRecentlyModifiedFiles() {
        let cutoff = Date(timeIntervalSince1970: 500_000)
        let entry = makeEntry(size: 1000, modifiedAt: Date(timeIntervalSince1970: 600_000), lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100, notModifiedSince: cutoff)
        #expect(!LargeFileFinder.matches(entry, filter: filter))
    }

    @Test func matchesAcceptsFilesModifiedBeforeCutoff() {
        let cutoff = Date(timeIntervalSince1970: 500_000)
        let entry = makeEntry(size: 1000, modifiedAt: Date(timeIntervalSince1970: 400_000), lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100, notModifiedSince: cutoff)
        #expect(LargeFileFinder.matches(entry, filter: filter))
    }

    // MARK: matches - last-used date

    @Test func matchesRejectsRecentlyOpenedFiles() {
        let cutoff = Date(timeIntervalSince1970: 500_000)
        let entry = makeEntry(size: 1000, lastUsedDate: Date(timeIntervalSince1970: 600_000))
        let filter = LargeFileFilter(minimumSize: 100, notOpenedSince: cutoff)
        #expect(!LargeFileFinder.matches(entry, filter: filter))
    }

    @Test func matchesAcceptsFilesOpenedBeforeCutoff() {
        let cutoff = Date(timeIntervalSince1970: 500_000)
        let entry = makeEntry(size: 1000, lastUsedDate: Date(timeIntervalSince1970: 400_000))
        let filter = LargeFileFilter(minimumSize: 100, notOpenedSince: cutoff)
        #expect(LargeFileFinder.matches(entry, filter: filter))
    }

    @Test func matchesNeverTreatsUnknownLastUsedDateAsStale() {
        let cutoff = Date(timeIntervalSince1970: 500_000)
        let entry = makeEntry(size: 1000, lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100, notOpenedSince: cutoff)
        // An unknown last-used date can't be proven stale, so it must not
        // be excluded by the "not opened since" filter.
        #expect(LargeFileFinder.matches(entry, filter: filter))
    }

    @Test func matchesWithNoDateFiltersOnlyChecksSize() {
        let entry = makeEntry(size: 1000, lastUsedDate: nil)
        let filter = LargeFileFilter(minimumSize: 100)
        #expect(LargeFileFinder.matches(entry, filter: filter))
    }

    // MARK: find - tree walking

    @Test func findExcludesDirectoriesSymlinksAndSyntheticNodes() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bigFilePath = tempDir.appendingPathComponent("big.bin").path
        try Data(repeating: 0x1, count: 10_000).write(to: URL(fileURLWithPath: bigFilePath))

        let symlinkNode = FileNode(name: "link", path: tempDir.appendingPathComponent("link").path, size: 10_000, isDirectory: false, isSymlink: true)
        let syntheticNode = FileNode(name: "synthetic", path: tempDir.path + "/\u{0}synthetic", size: 10_000, isDirectory: false)

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 30_000,
            isDirectory: true,
            children: [
                FileNode(name: "big.bin", path: bigFilePath, size: 10_000, isDirectory: false),
                symlinkNode,
                syntheticNode,
            ],
            itemCount: 4
        )

        let results = await LargeFileFinder.find(
            in: root,
            filter: LargeFileFilter(minimumSize: 5_000),
            lastUsedDateProvider: { _ in nil }
        )

        #expect(results.count == 1)
        #expect(results.first?.file.path == bigFilePath)
    }

    @Test func findExcludesFilesInsideBundles() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundlePath = tempDir.appendingPathComponent("Some.app").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let insideBundlePath = (bundlePath as NSString).appendingPathComponent("payload.bin")
        try Data(repeating: 0x1, count: 10_000).write(to: URL(fileURLWithPath: insideBundlePath))

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 10_000,
            isDirectory: true,
            children: [
                FileNode(
                    name: "Some.app",
                    path: bundlePath,
                    size: 10_000,
                    isDirectory: true,
                    children: [FileNode(name: "payload.bin", path: insideBundlePath, size: 10_000, isDirectory: false)],
                    itemCount: 2
                ),
            ],
            itemCount: 3
        )

        let results = await LargeFileFinder.find(
            in: root,
            filter: LargeFileFilter(minimumSize: 5_000),
            lastUsedDateProvider: { _ in nil }
        )

        #expect(results.isEmpty)
    }

    @Test func findSortsBySizeDescending() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let smallPath = tempDir.appendingPathComponent("small.bin").path
        let bigPath = tempDir.appendingPathComponent("big.bin").path
        try Data(repeating: 0x1, count: 6_000).write(to: URL(fileURLWithPath: smallPath))
        try Data(repeating: 0x2, count: 12_000).write(to: URL(fileURLWithPath: bigPath))

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 18_000,
            isDirectory: true,
            children: [
                FileNode(name: "small.bin", path: smallPath, size: 6_000, isDirectory: false),
                FileNode(name: "big.bin", path: bigPath, size: 12_000, isDirectory: false),
            ],
            itemCount: 3
        )

        let results = await LargeFileFinder.find(
            in: root,
            filter: LargeFileFilter(minimumSize: 5_000),
            lastUsedDateProvider: { _ in nil }
        )

        #expect(results.map(\.file.path) == [bigPath, smallPath])
    }

    @Test func findExcludesNodeModulesByDefaultButCanIncludeThem() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modulesPath = tempDir.appendingPathComponent("node_modules").path
        try FileManager.default.createDirectory(atPath: modulesPath, withIntermediateDirectories: true)
        let bigFilePath = (modulesPath as NSString).appendingPathComponent("bundle.js")
        try Data(repeating: 0x1, count: 10_000).write(to: URL(fileURLWithPath: bigFilePath))

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 10_000,
            isDirectory: true,
            children: [
                FileNode(
                    name: "node_modules",
                    path: modulesPath,
                    size: 10_000,
                    isDirectory: true,
                    children: [FileNode(name: "bundle.js", path: bigFilePath, size: 10_000, isDirectory: false)],
                    itemCount: 2
                ),
            ],
            itemCount: 3
        )

        let defaultResults = await LargeFileFinder.find(
            in: root,
            filter: LargeFileFilter(minimumSize: 5_000),
            lastUsedDateProvider: { _ in nil }
        )
        #expect(defaultResults.isEmpty)

        let includedResults = await LargeFileFinder.find(
            in: root,
            filter: LargeFileFilter(minimumSize: 5_000, includeDeveloperArtifacts: true),
            lastUsedDateProvider: { _ in nil }
        )
        #expect(includedResults.count == 1)
        #expect(includedResults.first?.file.path == bigFilePath)
    }
}
