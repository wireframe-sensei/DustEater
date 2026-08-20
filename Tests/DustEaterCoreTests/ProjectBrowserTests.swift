import Foundation
import Testing
@testable import DustEaterCore

struct ProjectBrowserTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DustEaterProjectBrowserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ bytes: Int, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    /// A monorepo with a `node_modules` per package (like
    /// `~/Documents/test/gdp-portal` in practice) collapses to one project
    /// row with multiple children, not one row per package.
    @Test func monorepoWithNodeModulesPerPackageBecomesOneProject() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1, to: "monorepo/.git/HEAD", in: root)
        try write(50_000, to: "monorepo/node_modules/pkg/index.js", in: root)
        try write(20_000, to: "monorepo/apps/web/node_modules/pkg/index.js", in: root)
        try write(10_000, to: "monorepo/apps/web/src/main.ts", in: root)

        let scanner = DiskScanner()
        let (node, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let projects = await ProjectBrowser.loadProjectSummaries(
            for: index.entries(for: .codeAndProjects),
            root: node,
            lastUsedDateProvider: { _ in nil }
        )

        #expect(projects.count == 1)
        #expect(projects.first?.name == "monorepo")
        #expect(projects.first?.children.count == 2)
        // The project's total size is the whole directory's real recursive
        // size (source files included), not just the sum of its
        // dependency directories.
        #expect(projects.first?.totalSizeBytes ?? 0 >= 80_000)
        #expect(projects.first?.reclaimableBytes ?? 0 >= 70_000)
    }

    @Test func projectWithoutAnyMarkerFallsBackToImmediateParent() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(5_000, to: "unmarked/node_modules/pkg/index.js", in: root)

        let scanner = DiskScanner()
        let (node, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let projects = await ProjectBrowser.loadProjectSummaries(
            for: index.entries(for: .codeAndProjects),
            root: node,
            lastUsedDateProvider: { _ in nil }
        )

        #expect(projects.count == 1)
        #expect(projects.first?.name == "unmarked")
    }

    @Test func projectsAreSortedByTotalSizeDescending() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(1, to: "small/package.json", in: root)
        try write(10_000, to: "small/node_modules/pkg/index.js", in: root)
        try write(1, to: "big/package.json", in: root)
        try write(500_000, to: "big/node_modules/pkg/index.js", in: root)

        let scanner = DiskScanner()
        let (node, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let projects = await ProjectBrowser.loadProjectSummaries(
            for: index.entries(for: .codeAndProjects),
            root: node,
            lastUsedDateProvider: { _ in nil }
        )

        #expect(projects.map(\.name) == ["big", "small"])
    }

    @Test func returnsEmptyWhenNoDependencyDirectoriesExist() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(100, to: "project/package.json", in: root)

        let scanner = DiskScanner()
        let (node, index) = await scanner.scanWithTypeIndex(rootPath: root.path)

        let projects = await ProjectBrowser.loadProjectSummaries(
            for: index.entries(for: .codeAndProjects),
            root: node,
            lastUsedDateProvider: { _ in nil }
        )

        #expect(projects.isEmpty)
    }
}
