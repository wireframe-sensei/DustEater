import Foundation
import Testing
@testable import DustEaterCore

@Suite("OrphanFinder")
struct OrphanFinderTests {
    @Test
    func findOrphansDetectsLibraryDataWithNoMatchingInstalledApp() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let containersPath = (libraryPath as NSString).appendingPathComponent("Containers")
        let cachesPath = (libraryPath as NSString).appendingPathComponent("Caches")
        let appSupportPath = (libraryPath as NSString).appendingPathComponent("Application Support")

        try FileManager.default.createDirectory(atPath: containersPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: cachesPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: appSupportPath, withIntermediateDirectories: true)

        let orphanID = "com.orphan.app"
        let orphanContainersPath = (containersPath as NSString).appendingPathComponent(orphanID)
        let orphanCachesPath = (cachesPath as NSString).appendingPathComponent(orphanID)

        try FileManager.default.createDirectory(atPath: orphanContainersPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: orphanCachesPath, withIntermediateDirectories: true)

        let testFile1 = (orphanContainersPath as NSString).appendingPathComponent("test1.txt")
        try "container test data".write(toFile: testFile1, atomically: true, encoding: .utf8)

        let testFile2 = (orphanCachesPath as NSString).appendingPathComponent("test2.txt")
        try "cache test data".write(toFile: testFile2, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = [
            AppDiskEntity(
                displayName: "Keep Me",
                bundleIdentifier: "com.keep.me",
                appPath: "/Applications/KeepMe.app",
                appBundleSize: 1024,
                relatedItems: []
            )
        ]

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        #expect(result.apps.count == 1)
        #expect(result.apps[0].inferredIdentifier == orphanID)
        #expect(result.apps[0].items.count == 2)

        let hasContainers = result.apps[0].items.contains { $0.category == .containers }
        let hasCaches = result.apps[0].items.contains { $0.category == .caches }
        #expect(hasContainers)
        #expect(hasCaches)
    }

    @Test
    func findOrphansIgnoresInstalledApps() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let cachesPath = (libraryPath as NSString).appendingPathComponent("Caches")

        try FileManager.default.createDirectory(atPath: cachesPath, withIntermediateDirectories: true)

        let installedID = "com.installed.app"
        let installedCachesPath = (cachesPath as NSString).appendingPathComponent(installedID)
        try FileManager.default.createDirectory(atPath: installedCachesPath, withIntermediateDirectories: true)

        let testFile = (installedCachesPath as NSString).appendingPathComponent("test.txt")
        try "test data".write(toFile: testFile, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = [
            AppDiskEntity(
                displayName: "Installed",
                bundleIdentifier: installedID,
                appPath: "/Applications/Installed.app",
                appBundleSize: 1024,
                relatedItems: []
            )
        ]

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        #expect(result.apps.isEmpty && result.developerTools.isEmpty)
    }

    @Test
    func findOrphansMatchesByDisplayNameForApplicationSupport() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let appSupportPath = (libraryPath as NSString).appendingPathComponent("Application Support")

        try FileManager.default.createDirectory(atPath: appSupportPath, withIntermediateDirectories: true)

        let displayName = "MyApp"
        let appSupportDataPath = (appSupportPath as NSString).appendingPathComponent(displayName)
        try FileManager.default.createDirectory(atPath: appSupportDataPath, withIntermediateDirectories: true)

        let testFile = (appSupportDataPath as NSString).appendingPathComponent("data.txt")
        try "test data".write(toFile: testFile, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = [
            AppDiskEntity(
                displayName: displayName,
                bundleIdentifier: nil,
                appPath: "/Applications/MyApp.app",
                appBundleSize: 1024,
                relatedItems: []
            )
        ]

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        #expect(result.apps.isEmpty && result.developerTools.isEmpty)
    }

    @Test
    func ignoresLiveAppDataInVendorFolderWhileReportingOrphanSiblings() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let appSupportPath = (libraryPath as NSString).appendingPathComponent("Application Support")
        let acmePath = (appSupportPath as NSString).appendingPathComponent("acme")

        try FileManager.default.createDirectory(atPath: acmePath, withIntermediateDirectories: true)

        let widgetPath = (acmePath as NSString).appendingPathComponent("Widget")
        let oldToolPath = (acmePath as NSString).appendingPathComponent("OldTool")

        try FileManager.default.createDirectory(atPath: widgetPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: oldToolPath, withIntermediateDirectories: true)

        let widgetFile = (widgetPath as NSString).appendingPathComponent("config.json")
        try "widget data".write(toFile: widgetFile, atomically: true, encoding: .utf8)

        let oldToolFile = (oldToolPath as NSString).appendingPathComponent("legacy.dat")
        try "old tool data".write(toFile: oldToolFile, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = [
            AppDiskEntity(
                displayName: "Widget",
                bundleIdentifier: "com.acme.widget",
                appPath: "/Applications/Widget.app",
                appBundleSize: 1024,
                relatedItems: []
            )
        ]

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        #expect(result.apps.count == 1, "Should have exactly one orphan (OldTool)")
        #expect(result.apps[0].inferredIdentifier == "OldTool")
        #expect(!result.apps[0].items.isEmpty)

        let vendorFolderOrphan = result.apps.first { $0.inferredIdentifier == "acme" }
        #expect(vendorFolderOrphan == nil, "Vendor folder 'acme' should not be flagged as orphan")

        let widgetOrphan = result.apps.first { $0.inferredIdentifier == "widget" }
        #expect(widgetOrphan == nil, "Live Widget data should not be flagged as orphan")
    }

    @Test
    func excludesAppleSystemServices() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let cachesPath = (libraryPath as NSString).appendingPathComponent("Caches")

        try FileManager.default.createDirectory(atPath: cachesPath, withIntermediateDirectories: true)

        let appleDaemonPath = (cachesPath as NSString).appendingPathComponent("com.apple.somedaemon")
        let siriTTSPath = (cachesPath as NSString).appendingPathComponent("SiriTTS")

        try FileManager.default.createDirectory(atPath: appleDaemonPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: siriTTSPath, withIntermediateDirectories: true)

        let daemonFile = (appleDaemonPath as NSString).appendingPathComponent("cache.dat")
        try "apple daemon cache".write(toFile: daemonFile, atomically: true, encoding: .utf8)

        let ttsFile = (siriTTSPath as NSString).appendingPathComponent("voices.dat")
        try "siri tts cache".write(toFile: ttsFile, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = []

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        #expect(result.apps.isEmpty, "Apple system services should not appear in orphaned apps")
        #expect(result.developerTools.isEmpty, "Apple system services should not appear in developer tools")
    }

    @Test
    func flagsVendorSiblingEntriesAsUncertain() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let libraryPath = tempDir.appendingPathComponent("Library").path
        let appSupportPath = (libraryPath as NSString).appendingPathComponent("Application Support")
        let adobePath = (appSupportPath as NSString).appendingPathComponent("Adobe")

        try FileManager.default.createDirectory(atPath: adobePath, withIntermediateDirectories: true)

        let lightoomPath = (adobePath as NSString).appendingPathComponent("Lightroom CC")
        let adobeUpdaterPath = (adobePath as NSString).appendingPathComponent("AdobeUpdater")
        let topLevelOrphanPath = (appSupportPath as NSString).appendingPathComponent("StandaloneApp")

        try FileManager.default.createDirectory(atPath: lightoomPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: adobeUpdaterPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: topLevelOrphanPath, withIntermediateDirectories: true)

        let lightoomFile = (lightoomPath as NSString).appendingPathComponent("config.json")
        try "lightroom config".write(toFile: lightoomFile, atomically: true, encoding: .utf8)

        let updaterFile = (adobeUpdaterPath as NSString).appendingPathComponent("service.dat")
        try "adobe updater".write(toFile: updaterFile, atomically: true, encoding: .utf8)

        let standaloneFile = (topLevelOrphanPath as NSString).appendingPathComponent("data.txt")
        try "standalone app".write(toFile: standaloneFile, atomically: true, encoding: .utf8)

        let installedApps: [AppDiskEntity] = [
            AppDiskEntity(
                displayName: "Lightroom CC",
                bundleIdentifier: "com.adobe.lightroom",
                appPath: "/Applications/Lightroom CC.app",
                appBundleSize: 1024,
                relatedItems: []
            )
        ]

        let result = await OrphanFinder.findOrphanedData(installedApps: installedApps, homeDirectory: tempDir.path)

        let adobeUpdater = result.apps.first { $0.inferredIdentifier == "AdobeUpdater" }
        #expect(adobeUpdater != nil, "AdobeUpdater should be detected as orphan")
        #expect(adobeUpdater?.isVendorSibling == true, "AdobeUpdater should be flagged as vendor sibling (uncertain)")

        let standalone = result.apps.first { $0.inferredIdentifier == "StandaloneApp" }
        #expect(standalone != nil, "StandaloneApp should be detected as orphan")
        #expect(standalone?.isVendorSibling == false, "StandaloneApp should not be flagged as vendor sibling (it's top-level)")
    }
}
