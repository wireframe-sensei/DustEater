import Testing
import Foundation
@testable import DustEaterCore

struct AppGroupingTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DustEaterAppGroupingTests-\(UUID().uuidString)")
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

    private func writeInfoPlist(bundleIdentifier: String, displayName: String, appPath: String, in root: URL) throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = root.appendingPathComponent("\(appPath)/Contents/Info.plist")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test func findAppBundlesLocatesAppsWithoutDescendingIntoThem() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeInfoPlist(
            bundleIdentifier: "com.example.helper",
            displayName: "Helper",
            appPath: "Applications/Foo.app/Contents/XPCServices/Helper.app",
            in: root
        )
        try write(10, to: "Applications/Foo.app/Contents/MacOS/Foo", in: root)
        try write(10, to: "Applications/Bar.app/Contents/MacOS/Bar", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.appendingPathComponent("Applications").path)

        let apps = AppGrouper.findAppBundles(in: node)
        let names = Set(apps.map(\.name))

        #expect(names == ["Foo.app", "Bar.app"])
    }

    @Test func buildAppDiskEntitiesFindsRelatedStorageByBundleIdentifier() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeInfoPlist(
            bundleIdentifier: "com.example.myapp",
            displayName: "MyApp",
            appPath: "Applications/MyApp.app",
            in: root
        )
        try write(1000, to: "Applications/MyApp.app/Contents/MacOS/MyApp", in: root)
        try write(500, to: "Library/Caches/com.example.myapp/cache.db", in: root)
        try write(2000, to: "Library/Application Support/com.example.myapp/data.db", in: root)
        try write(300, to: "Library/Containers/com.example.myapp/state.plist", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.appendingPathComponent("Applications").path)
        let apps = AppGrouper.findAppBundles(in: node)

        #expect(apps.count == 1)

        let entities = await AppGrouper.buildAppDiskEntities(from: apps, homeDirectory: root.path)
        #expect(entities.count == 1)

        let entity = try #require(entities.first)
        #expect(entity.bundleIdentifier == "com.example.myapp")
        #expect(entity.displayName == "MyApp")

        let categoriesFound = Set(entity.relatedItems.map(\.category))
        #expect(categoriesFound == [.caches, .applicationSupport, .containers])
        #expect(entity.relatedTotalSize > 0)
        #expect(entity.trueTotalSize == entity.appBundleSize + entity.relatedTotalSize)
    }

    @Test func mergeTrueSizesAddsAssociatedDataNodeAndKeepsChildSumConsistent() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeInfoPlist(
            bundleIdentifier: "com.example.myapp",
            displayName: "MyApp",
            appPath: "Applications/MyApp.app",
            in: root
        )
        try write(1000, to: "Applications/MyApp.app/Contents/MacOS/MyApp", in: root)
        try write(5000, to: "Library/Caches/com.example.myapp/cache.db", in: root)

        let scanner = DiskScanner()
        let scannedRoot = await scanner.scan(rootPath: root.appendingPathComponent("Applications").path)
        let apps = AppGrouper.findAppBundles(in: scannedRoot)
        let entities = await AppGrouper.buildAppDiskEntities(from: apps, homeDirectory: root.path)

        let merged = AppSizeMerger.mergeTrueSizes(into: scannedRoot, using: entities)
        let mergedApp = try #require(merged.children.first { $0.name == "MyApp.app" })

        // The .app node's size grew to include the hidden cache...
        #expect(mergedApp.size > scannedRoot.children.first { $0.name == "MyApp.app" }!.size)

        // ...and a visible child accounts for exactly that difference, so
        // the size == sum(children.size) invariant the treemap relies on
        // still holds for the merged tree.
        let childSum = mergedApp.children.reduce(into: Int64(0)) { $0 += $1.size }
        #expect(childSum == mergedApp.size)

        #expect(mergedApp.children.contains { $0.name == "Associated App Data" })
    }

    @Test func appWithNoRelatedStorageIsUnaffectedByMerge() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeInfoPlist(
            bundleIdentifier: "com.example.lonely",
            displayName: "Lonely",
            appPath: "Applications/Lonely.app",
            in: root
        )
        try write(1000, to: "Applications/Lonely.app/Contents/MacOS/Lonely", in: root)

        let scanner = DiskScanner()
        let scannedRoot = await scanner.scan(rootPath: root.appendingPathComponent("Applications").path)
        let apps = AppGrouper.findAppBundles(in: scannedRoot)
        let entities = await AppGrouper.buildAppDiskEntities(from: apps, homeDirectory: root.path)

        let merged = AppSizeMerger.mergeTrueSizes(into: scannedRoot, using: entities)

        #expect(merged.size == scannedRoot.size)
    }

    @Test func findRelatedStorageInVendorNestedFolders() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeInfoPlist(
            bundleIdentifier: "com.acme.widget",
            displayName: "Widget",
            appPath: "Applications/Widget.app",
            in: root
        )
        try write(1000, to: "Applications/Widget.app/Contents/MacOS/Widget", in: root)
        try write(500, to: "Library/Application Support/acme/Widget/config.json", in: root)
        try write(2000, to: "Library/Caches/acme/Widget/cache.db", in: root)

        let scanner = DiskScanner()
        let node = await scanner.scan(rootPath: root.appendingPathComponent("Applications").path)
        let apps = AppGrouper.findAppBundles(in: node)

        let entities = await AppGrouper.buildAppDiskEntities(from: apps, homeDirectory: root.path)
        #expect(entities.count == 1)

        let entity = try #require(entities.first)
        #expect(entity.bundleIdentifier == "com.acme.widget")

        let categoriesFound = Set(entity.relatedItems.map(\.category))
        #expect(categoriesFound == [.applicationSupport, .caches])

        let appSupportItem = entity.relatedItems.first { $0.category == .applicationSupport }
        #expect(appSupportItem != nil, "Should find Application Support item")
        #expect(appSupportItem?.size ?? 0 > 0)

        let cachesItem = entity.relatedItems.first { $0.category == .caches }
        #expect(cachesItem != nil, "Should find Caches item")
        #expect(cachesItem?.size ?? 0 > 0)

        #expect(entity.relatedTotalSize > 0)
        #expect(entity.trueTotalSize == entity.appBundleSize + entity.relatedTotalSize)
    }
}
