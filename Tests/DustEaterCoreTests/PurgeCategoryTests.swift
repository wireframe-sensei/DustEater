import Testing
@testable import DustEaterCore

struct PurgeCategoryTests {
    private func definition(
        path: String = "/Users/x/Library/Developer/Xcode/DerivedData",
        safety: PurgeSafetyLevel = .rebuildable
    ) -> PurgeTargetDefinition {
        PurgeTargetDefinition(
            path: path,
            title: "DerivedData",
            detail: "Build intermediates.",
            categoryID: .xcode,
            safety: safety,
            rebuildCommand: safety == .rebuildable ? "swift build" : nil,
            hint: safety == .reportOnly ? "Manage elsewhere." : nil
        )
    }

    @Test func reclaimableBytesExcludesReportOnlyWhileTotalBytesIncludesIt() {
        let safeTarget = PurgeTarget(definition: definition(path: "/a", safety: .safe), sizeBytes: 100)
        let reportOnlyTarget = PurgeTarget(definition: definition(path: "/b", safety: .reportOnly), sizeBytes: 5000)
        let category = PurgeCategory(categoryID: .xcode, targets: [safeTarget, reportOnlyTarget])

        #expect(category.totalBytes == 5100)
        #expect(category.reclaimableBytes == 100)
    }

    @Test func purgeTargetEqualityIsPathAndSizeAndIgnoresEditorialStrings() {
        let a = PurgeTarget(definition: definition(path: "/a"), sizeBytes: 100)
        let differentTitleSameSizeAndPath = PurgeTarget(
            definition: PurgeTargetDefinition(
                path: "/a",
                title: "A completely different title",
                detail: "A completely different detail.",
                categoryID: .packageManagers,
                safety: .safe
            ),
            sizeBytes: 100
        )
        let differentSize = PurgeTarget(definition: definition(path: "/a"), sizeBytes: 200)

        #expect(a == differentTitleSameSizeAndPath)
        #expect(a != differentSize)
    }
}
