import Foundation
import Testing
@testable import DustEaterCore

struct CleanupFindingsBuilderTests {
    private func target(
        path: String,
        title: String = "Cache",
        categoryID: PurgeCategoryID,
        safety: PurgeSafetyLevel = .safe,
        sizeBytes: Int64 = 1_000,
        hint: String? = nil
    ) -> PurgeTarget {
        PurgeTarget(
            definition: PurgeTargetDefinition(
                path: path,
                title: title,
                detail: "detail",
                categoryID: categoryID,
                safety: safety,
                hint: hint
            ),
            sizeBytes: sizeBytes
        )
    }

    private func file(path: String, size: Int64, modifiedAt: Date = Date()) -> InspectedFile {
        InspectedFile(
            path: path,
            name: (path as NSString).lastPathComponent,
            logicalSize: size,
            allocatedSize: size,
            modifiedAt: modifiedAt,
            accessedAt: modifiedAt,
            createdAt: modifiedAt,
            deviceID: 1,
            inode: UInt64(abs(path.hashValue))
        )
    }

    // MARK: - Package manager caches / Xcode / Simulator runtimes

    @Test func packageManagerCachesOnlyIncludesThatCategory() {
        let categories = [
            PurgeCategory(categoryID: .packageManagers, targets: [target(path: "/a", categoryID: .packageManagers)]),
            PurgeCategory(categoryID: .xcode, targets: [target(path: "/b", categoryID: .xcode)]),
        ]
        let finding = CleanupFindingsBuilder.packageManagerCaches(from: categories)
        #expect(finding?.items.map(\.id) == ["/a"])
    }

    @Test func simulatorRuntimesOnlyIncludesReportOnlyTargets() {
        let categories = [
            PurgeCategory(categoryID: .simulators, targets: [
                target(path: "/runtimes", categoryID: .simulators, safety: .reportOnly, hint: "Manage in Xcode"),
                target(path: "/logs", categoryID: .simulators, safety: .safe),
            ]),
        ]
        let finding = CleanupFindingsBuilder.simulatorRuntimes(from: categories)
        #expect(finding?.items.map(\.id) == ["/runtimes"])
        #expect(finding?.items.first?.deletablePaths.isEmpty == true)
        #expect(finding?.items.first?.hint == "Manage in Xcode")
    }

    @Test func xcodeBuildArtifactsIncludesNonReportOnlySimulatorTargets() {
        let categories = [
            PurgeCategory(categoryID: .xcode, targets: [target(path: "/derived", categoryID: .xcode)]),
            PurgeCategory(categoryID: .simulators, targets: [
                target(path: "/simlogs", categoryID: .simulators, safety: .safe),
                target(path: "/runtimes", categoryID: .simulators, safety: .reportOnly),
            ]),
        ]
        let finding = CleanupFindingsBuilder.xcodeBuildArtifacts(from: categories)
        #expect(Set(finding?.items.map(\.id) ?? []) == ["/derived", "/simlogs"])
    }

    @Test func zeroByteTargetsAreExcluded() {
        let categories = [
            PurgeCategory(categoryID: .packageManagers, targets: [target(path: "/empty", categoryID: .packageManagers, sizeBytes: 0)]),
        ]
        #expect(CleanupFindingsBuilder.packageManagerCaches(from: categories) == nil)
    }

    // MARK: - Applications unopened over a year

    @Test func unusedApplicationsExcludesRecentlyOpenedApps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recentlyOpened = AppDiskEntity(
            displayName: "Recent", bundleIdentifier: "com.a.recent", appPath: "/Applications/Recent.app",
            appBundleSize: 100, relatedItems: [], lastOpenedDate: now.addingTimeInterval(-60 * 60 * 24 * 30)
        )
        let staleApp = AppDiskEntity(
            displayName: "Stale", bundleIdentifier: "com.a.stale", appPath: "/Applications/Stale.app",
            appBundleSize: 100, relatedItems: [], lastOpenedDate: now.addingTimeInterval(-60 * 60 * 24 * 400)
        )
        let finding = CleanupFindingsBuilder.unusedApplications(installed: [recentlyOpened, staleApp], now: now)
        #expect(finding?.items.map(\.id) == ["com.a.stale"])
    }

    @Test func unusedApplicationsTreatsUnknownLastOpenedAsStale() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let neverOpened = AppDiskEntity(
            displayName: "Never", bundleIdentifier: "com.a.never", appPath: "/Applications/Never.app",
            appBundleSize: 100, relatedItems: [], lastOpenedDate: nil
        )
        let finding = CleanupFindingsBuilder.unusedApplications(installed: [neverOpened], now: now)
        #expect(finding?.items.first?.note == "Never opened")
        #expect(finding?.items.first?.safety == .caution)
    }

    @Test func unusedApplicationsDeletablePathsIncludeBundleAndRelatedItems() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let app = AppDiskEntity(
            displayName: "Stale", bundleIdentifier: "com.a.stale", appPath: "/Applications/Stale.app",
            appBundleSize: 100,
            relatedItems: [RelatedStorageItem(category: .caches, path: "/caches/stale", size: 50)],
            lastOpenedDate: now.addingTimeInterval(-60 * 60 * 24 * 400)
        )
        let finding = CleanupFindingsBuilder.unusedApplications(installed: [app], now: now)
        let item = finding?.items.first
        #expect(Set(item?.deletablePaths ?? []) == ["/Applications/Stale.app", "/caches/stale"])
        #expect(item?.appBundlePath == "/Applications/Stale.app")
    }

    // MARK: - Duplicate files

    @Test func duplicateFilesKeepsNewestAsSurvivorNeverInDeletablePaths() {
        let newest = file(path: "/Documents/newest.png", size: 1_000, modifiedAt: Date())
        let older = file(path: "/Downloads/older.png", size: 1_000, modifiedAt: Date().addingTimeInterval(-1_000))
        // DuplicateSet.files is documented newest-first.
        let set = DuplicateSet(contentHash: "hash1", files: [newest, older])

        let finding = CleanupFindingsBuilder.duplicateFiles(from: [set])
        let item = finding?.items.first

        #expect(item?.deletablePaths == ["/Downloads/older.png"])
        #expect(item?.deletablePaths.contains("/Documents/newest.png") == false)
        #expect(item?.sizeBytes == set.wastedBytes)
    }

    @Test func duplicateFilesExcludesSingleFileSets() {
        let set = DuplicateSet(contentHash: "hash1", files: [file(path: "/a", size: 1_000)])
        #expect(CleanupFindingsBuilder.duplicateFiles(from: [set]) == nil)
    }

    // MARK: - Ranking

    @Test func rankCompactsNilsAndSortsByReclaimableBytesDescending() {
        let small = CleanupFinding(id: .packageManagerCaches, items: [
            CleanupItem(id: "/small", findingID: .packageManagerCaches, name: "Small", detail: "d", sizeBytes: 100, safety: .safe, deletablePaths: ["/small"], revealPath: "/small"),
        ])
        let large = CleanupFinding(id: .oldDownloads, items: [
            CleanupItem(id: "/large", findingID: .oldDownloads, name: "Large", detail: "d", sizeBytes: 10_000, safety: .safe, deletablePaths: ["/large"], revealPath: "/large"),
        ])

        let ranked = CleanupFindingsBuilder.rank([small, nil, large])
        #expect(ranked.map(\.id) == [.oldDownloads, .packageManagerCaches])
    }

    @Test func reclaimableBytesExcludesReportOnlyItems() {
        let finding = CleanupFinding(id: .simulatorRuntimes, items: [
            CleanupItem(id: "/runtimes", findingID: .simulatorRuntimes, name: "Runtimes", detail: "d", sizeBytes: 5_000, safety: .reportOnly, hint: "Manage in Xcode", deletablePaths: [], revealPath: "/runtimes"),
        ])
        #expect(finding.totalBytes == 5_000)
        #expect(finding.reclaimableBytes == 0)
    }
}
