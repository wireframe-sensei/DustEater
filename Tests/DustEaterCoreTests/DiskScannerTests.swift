import Testing
import Foundation
@testable import DustEaterCore

struct DiskScannerTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DustEaterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ bytes: Int, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    @Test func scanFindsAllFilesAndSumsSizes() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(100, to: "file1.bin", in: root)
        try write(50, to: "sub1/file2.bin", in: root)
        try write(20, to: "sub1/subsub1/file3.bin", in: root)
        try write(30, to: "sub2/file4.bin", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.path)

        // Allocated size is block-rounded, so it's >= logical size, never less.
        #expect(node.size >= 200)
        #expect(node.isDirectory)

        // root + sub1 + sub2 + subsub1 + 4 files = 8
        #expect(node.itemCount == 8)

        let names = Set(node.children.map(\.name))
        #expect(names == ["file1.bin", "sub1", "sub2"])
    }

    @Test func emptyDirectoryScansToZero() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.path)

        #expect(node.size == 0)
        #expect(node.children.isEmpty)
        #expect(node.itemCount == 1)
    }

    @Test func sortedBySizeOrdersDescending() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(10, to: "small.bin", in: root)
        try write(1000, to: "big.bin", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.path)
        let sorted = node.sortedBySize()

        #expect(sorted.children.first?.name == "big.bin")
        #expect(sorted.children.last?.name == "small.bin")
    }

    /// Regression test: an earlier version of DiskScanner used a shared
    /// bounded semaphore to gate TaskGroup fan-out, which deadlocked on
    /// trees wide and deep enough that an entire "generation" of
    /// concurrently-running directory tasks simultaneously needed more
    /// permits (from the same exhausted pool) to recurse into their own
    /// children. This tree is shaped like that (wide branching at every
    /// level); the test's real assertion is simply that it completes.
    @Test func deeplyNestedAndWideTreeDoesNotDeadlock() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        for a in 0..<6 {
            for b in 0..<6 {
                try write(1, to: "\(a)/\(b)/leaf.bin", in: root)
            }
        }

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.path)

        // root + 6 "a" dirs + 36 "b" dirs + 36 leaf files
        #expect(node.itemCount == 1 + 6 + 36 + 36)
        #expect(node.size > 0)
    }

    // MARK: - scanWithTypeIndex

    @Test func scanWithTypeIndexClassifiesFilesByExtension() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(100, to: "movie.mp4", in: root)
        try write(200, to: "photo.jpg", in: root)
        try write(300, to: "src/main.swift", in: root)
        try write(50, to: "notes.unknownext", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        #expect(index.total(for: .videos).fileCount == 1)
        #expect(index.total(for: .photos).fileCount == 1)
        #expect(index.total(for: .codeAndProjects).fileCount == 1)
        // No extension - falls into .other, not silently dropped.
        #expect(index.total(for: .other).fileCount == 1)
    }

    /// A whole `.app` bundle becomes exactly one `.applications` entry
    /// carrying its full recursive size - individual files inside (an
    /// Info.plist, a .png icon, a compiled binary) must never separately
    /// appear under `.documents`/`.photos`/`.other`, which would both
    /// double-count bytes and clutter those categories with app internals.
    @Test func appBundleBecomesOneApplicationsEntryNotIndividualFiles() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "MyApp.app/Contents/Info.plist", in: root)
        try write(2000, to: "MyApp.app/Contents/Resources/icon.png", in: root)
        try write(3000, to: "MyApp.app/Contents/MacOS/MyApp", in: root)
        try write(500, to: "standalone.png", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        #expect(index.total(for: .applications).fileCount == 1)
        #expect(index.entries(for: .applications).first?.name == "MyApp.app")
        #expect(index.total(for: .applications).totalBytes >= 6000)

        // Only the standalone file outside the bundle counts as .photos -
        // the bundle's own icon.png must not also appear there.
        #expect(index.total(for: .photos).fileCount == 1)
        #expect(index.entries(for: .photos).first?.name == "standalone.png")
    }

    /// A helper `.app` nested inside another `.app` (Xcode ships several)
    /// must not become its own second `.applications` entry - it's already
    /// counted as part of the outer bundle's recursive size.
    @Test func nestedAppBundleIsNotDoubleRecorded() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "Outer.app/Contents/MacOS/Outer", in: root)
        try write(500, to: "Outer.app/Contents/XPCServices/Helper.app/Contents/MacOS/Helper", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        #expect(index.total(for: .applications).fileCount == 1)
        #expect(index.entries(for: .applications).first?.name == "Outer.app")
    }

    @Test func photosLibraryMembershipIsDetectedByPath() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "Photos Library.photoslibrary/originals/1/x.heic", in: root)
        try write(1000, to: "not-a-library/y.heic", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let photoEntries = index.entries(for: .photos)
        #expect(photoEntries.count == 2)
        #expect(photoEntries.first { $0.name == "x.heic" }?.isPhotosManaged == true)
        #expect(photoEntries.first { $0.name == "y.heic" }?.isPhotosManaged == false)
    }

    /// A `node_modules` tree becomes exactly one `.codeAndProjects` entry
    /// carrying its full recursive size, flagged `isDependencyDirectory` -
    /// individual files inside (a `.js` file, a stray `.png` icon asset a
    /// package ships) must never separately appear under
    /// `.codeAndProjects`/`.photos`, the same "a folder is the natural
    /// unit" reasoning `appBundleBecomesOneApplicationsEntryNotIndividualFiles`
    /// already establishes for `.app` bundles.
    @Test func dependencyDirectoryBecomesOneEntryNotIndividualFiles() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "myproject/node_modules/typescript/lib/typescript.js", in: root)
        try write(2000, to: "myproject/node_modules/.pnpm/lodash@4/index.js", in: root)
        try write(500, to: "myproject/node_modules/icons/logo.png", in: root)
        try write(300, to: "myproject/src/main.ts", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let codeEntries = index.entries(for: .codeAndProjects)
        let nodeModulesEntry = codeEntries.first { $0.name == "node_modules" }
        #expect(nodeModulesEntry != nil)
        #expect(nodeModulesEntry?.isDependencyDirectory == true)
        #expect(nodeModulesEntry?.sizeBytes ?? 0 >= 3500)

        // Only the loose source file, not the dependency tree's own icon,
        // appears as an individual .codeAndProjects entry.
        #expect(codeEntries.contains { $0.name == "main.ts" })
        #expect(!codeEntries.contains { $0.name == "logo.png" })
        #expect(index.total(for: .photos).fileCount == 0)
    }

    /// A dependency directory nested inside another (pnpm's own storage
    /// layout does this) must not become its own second entry - it's
    /// already counted as part of the outer directory's recursive size,
    /// mirroring `nestedAppBundleIsNotDoubleRecorded`.
    @Test func nestedDependencyDirectoryIsNotDoubleRecorded() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "myproject/node_modules/.pnpm/pkg@1/node_modules/pkg/index.js", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let nodeModulesEntries = index.entries(for: .codeAndProjects).filter { $0.name == "node_modules" }
        #expect(nodeModulesEntries.count == 1)
    }

    /// A Final Cut Pro library becomes one `.videos` entry, flagged
    /// `isProtectedBundle` - its internal render files and project assets
    /// must not scatter across `.videos`/`.other` individually.
    @Test func creativeSuiteLibraryBecomesOneEntryNotIndividualFiles() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "Wedding.fcpbundle/CurrentVersion.fcpevent/render.mov", in: root)
        try write(500, to: "Wedding.fcpbundle/project.json", in: root)
        try write(200, to: "standalone.mov", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let videoEntries = index.entries(for: .videos)
        let bundleEntry = videoEntries.first { $0.name == "Wedding.fcpbundle" }
        #expect(bundleEntry != nil)
        #expect(bundleEntry?.isProtectedBundle == true)
        #expect(bundleEntry?.sizeBytes ?? 0 >= 1500)

        // Only the standalone file, not the bundle's own render.mov, is
        // individually recorded - and the bundle's project.json (a
        // recognized code/project extension) must not leak into
        // .codeAndProjects either, since it's inside a protected bundle.
        #expect(videoEntries.contains { $0.name == "standalone.mov" })
        #expect(!videoEntries.contains { $0.name == "render.mov" })
        #expect(index.total(for: .codeAndProjects).fileCount == 0)
    }

    /// Regression test: an earlier version tracked "inside a `.app`
    /// bundle" and "inside a protected bundle" as two independent flags,
    /// so a `.framework` sitting inside a `.app` (the routine case - most
    /// frameworks live inside the apps that ship them) was both correctly
    /// folded into the app's `.applications` total *and* incorrectly
    /// recorded a second time as its own `.other` entry, double-counting
    /// its bytes. Only the outermost container - the `.app` here - may
    /// ever aggregate.
    @Test func protectedBundleNestedInsideAppBundleIsNotDoubleRecorded() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1000, to: "MyApp.app/Contents/MacOS/MyApp", in: root)
        try write(2000, to: "MyApp.app/Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle", in: root)

        let scanner = DiskScanner()
        let (_, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        #expect(index.total(for: .applications).fileCount == 1)
        #expect(index.entries(for: .applications).first?.sizeBytes ?? 0 >= 3000)
        // The framework must not also appear as its own .other entry.
        #expect(index.total(for: .other).fileCount == 0)
    }

    @Test func scanIgnoringTypeIndexStillWorksUnchanged() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(100, to: "file.bin", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.path)

        #expect(node.size >= 100)
    }
}
