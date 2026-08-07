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
}
