import Foundation
import Testing
@testable import DustEaterCore

@Suite("DuplicateDetector")
struct DuplicateDetectorTests {
    @Test
    func findDuplicatesGroupsByteIdenticalFilesAndIgnoresHardLinks() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Content well above the 1 KB minimum used below, so nothing here
        // gets filtered out by the size floor.
        let sharedContent = Data(repeating: 0xAB, count: 8192)
        let differentContent = Data(repeating: 0xCD, count: 8192)

        let copyAPath = tempDir.appendingPathComponent("copyA.bin").path
        let copyBPath = tempDir.appendingPathComponent("copyB.bin").path
        let hardLinkPath = tempDir.appendingPathComponent("hardlink.bin").path
        let differentPath = tempDir.appendingPathComponent("different.bin").path

        try sharedContent.write(to: URL(fileURLWithPath: copyAPath))
        try sharedContent.write(to: URL(fileURLWithPath: copyBPath))
        try differentContent.write(to: URL(fileURLWithPath: differentPath))
        try FileManager.default.linkItem(atPath: copyAPath, toPath: hardLinkPath)

        func node(_ path: String, size: Int64) -> FileNode {
            FileNode(name: (path as NSString).lastPathComponent, path: path, size: size, isDirectory: false)
        }

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 8192 * 4,
            isDirectory: true,
            children: [
                node(copyAPath, size: 8192),
                node(copyBPath, size: 8192),
                node(hardLinkPath, size: 8192),
                node(differentPath, size: 8192),
            ],
            itemCount: 5
        )

        let detector = DuplicateDetector()
        let sets = await detector.findDuplicates(
            in: root,
            options: DuplicateScanOptions(minimumFileSize: 1024)
        )

        #expect(sets.count == 1)
        let onlySet = try #require(sets.first)
        // copyA.bin and hardlink.bin share one inode, so hard-link collapse
        // keeps exactly one of them (which one is an implementation detail
        // of dictionary iteration order, not something this test should
        // pin down) - the set must end up with exactly the two genuinely
        // independent copies: copyB, plus whichever of {copyA, hardlink}
        // survived collapse.
        #expect(onlySet.files.count == 2)
        let resultPaths = Set(onlySet.files.map(\.path))
        #expect(resultPaths.contains(copyBPath))
        let aliasSurvivorCount = [copyAPath, hardLinkPath].filter { resultPaths.contains($0) }.count
        #expect(aliasSurvivorCount == 1)
        #expect(onlySet.wastedBytes == 8192)
    }

    @Test
    func findDuplicatesReturnsEmptyWhenNoFilesMatch() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let onlyFilePath = tempDir.appendingPathComponent("solo.bin").path
        try Data(repeating: 0x11, count: 8192).write(to: URL(fileURLWithPath: onlyFilePath))

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 8192,
            isDirectory: true,
            children: [FileNode(name: "solo.bin", path: onlyFilePath, size: 8192, isDirectory: false)],
            itemCount: 2
        )

        let detector = DuplicateDetector()
        let sets = await detector.findDuplicates(in: root, options: DuplicateScanOptions(minimumFileSize: 1024))

        #expect(sets.isEmpty)
    }

    @Test
    func findDuplicatesSkipsFilesInsideAppBundles() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sharedContent = Data(repeating: 0xEF, count: 8192)
        let bundlePath = tempDir.appendingPathComponent("Some.app").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)

        let insideBundlePath = (bundlePath as NSString).appendingPathComponent("payload.bin")
        let outsideBundlePath = tempDir.appendingPathComponent("payload.bin").path
        try sharedContent.write(to: URL(fileURLWithPath: insideBundlePath))
        try sharedContent.write(to: URL(fileURLWithPath: outsideBundlePath))

        let root = FileNode(
            name: tempDir.lastPathComponent,
            path: tempDir.path,
            size: 8192 * 2,
            isDirectory: true,
            children: [
                FileNode(
                    name: "Some.app",
                    path: bundlePath,
                    size: 8192,
                    isDirectory: true,
                    children: [FileNode(name: "payload.bin", path: insideBundlePath, size: 8192, isDirectory: false)],
                    itemCount: 2
                ),
                FileNode(name: "payload.bin", path: outsideBundlePath, size: 8192, isDirectory: false),
            ],
            itemCount: 4
        )

        let detector = DuplicateDetector()
        let sets = await detector.findDuplicates(in: root, options: DuplicateScanOptions(minimumFileSize: 1024))

        // The bundle interior is excluded, so the outside copy has nothing
        // left to match - no set should be reported at all.
        #expect(sets.isEmpty)
    }

    @Test
    func findDuplicatesSkipsNodeModulesByDefaultButCanIncludeThem() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulates the real-world case this exclusion targets: the same
        // package installed byte-identically in two unrelated projects'
        // node_modules trees.
        let sharedContent = Data(repeating: 0x42, count: 8192)
        let projectAModules = tempDir.appendingPathComponent("ProjectA/node_modules").path
        let projectBModules = tempDir.appendingPathComponent("ProjectB/node_modules").path
        try FileManager.default.createDirectory(atPath: projectAModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: projectBModules, withIntermediateDirectories: true)

        let fileAPath = (projectAModules as NSString).appendingPathComponent("lodash.js")
        let fileBPath = (projectBModules as NSString).appendingPathComponent("lodash.js")
        try sharedContent.write(to: URL(fileURLWithPath: fileAPath))
        try sharedContent.write(to: URL(fileURLWithPath: fileBPath))

        func directory(_ name: String, path: String, children: [FileNode]) -> FileNode {
            FileNode(name: name, path: path, size: 8192, isDirectory: true, children: children, itemCount: children.count + 1)
        }

        let root = directory(
            tempDir.lastPathComponent, path: tempDir.path,
            children: [
                directory("ProjectA", path: (tempDir.path as NSString).appendingPathComponent("ProjectA"), children: [
                    directory("node_modules", path: projectAModules, children: [
                        FileNode(name: "lodash.js", path: fileAPath, size: 8192, isDirectory: false),
                    ]),
                ]),
                directory("ProjectB", path: (tempDir.path as NSString).appendingPathComponent("ProjectB"), children: [
                    directory("node_modules", path: projectBModules, children: [
                        FileNode(name: "lodash.js", path: fileBPath, size: 8192, isDirectory: false),
                    ]),
                ]),
            ]
        )

        let detector = DuplicateDetector()

        let defaultResult = await detector.findDuplicates(in: root, options: DuplicateScanOptions(minimumFileSize: 1024))
        #expect(defaultResult.isEmpty)

        let includedResult = await detector.findDuplicates(
            in: root,
            options: DuplicateScanOptions(minimumFileSize: 1024, includeDeveloperArtifacts: true)
        )
        #expect(includedResult.count == 1)
        #expect(includedResult.first?.files.count == 2)
    }
}
