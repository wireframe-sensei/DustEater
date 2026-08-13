import Foundation
import Testing
@testable import DustEaterCore

struct SmartSelectorTests {
    private let downloads = "/Users/test/Downloads"

    private func makeFile(path: String, modifiedAt: Date) -> InspectedFile {
        InspectedFile(
            path: path,
            name: (path as NSString).lastPathComponent,
            logicalSize: 1000,
            allocatedSize: 1000,
            modifiedAt: modifiedAt,
            accessedAt: modifiedAt,
            createdAt: modifiedAt,
            deviceID: 1,
            inode: UInt64(abs(path.hashValue))
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: offset)
    }

    // MARK: allExceptNewest / allExceptOldest

    @Test func allExceptNewestKeepsOnlyNewestUnselected() {
        let old = makeFile(path: "/a/old.bin", modifiedAt: date(100))
        let mid = makeFile(path: "/a/mid.bin", modifiedAt: date(200))
        let newFile = makeFile(path: "/a/new.bin", modifiedAt: date(300))
        let set = DuplicateSet(contentHash: "h", files: [old, mid, newFile])

        let selected = SmartSelector.apply(.allExceptNewest, to: [set], downloadsPaths: [])

        #expect(selected == [old.path, mid.path])
        #expect(!selected.contains(newFile.path))
    }

    @Test func allExceptOldestKeepsOnlyOldestUnselected() {
        let old = makeFile(path: "/a/old.bin", modifiedAt: date(100))
        let mid = makeFile(path: "/a/mid.bin", modifiedAt: date(200))
        let newFile = makeFile(path: "/a/new.bin", modifiedAt: date(300))
        let set = DuplicateSet(contentHash: "h", files: [old, mid, newFile])

        let selected = SmartSelector.apply(.allExceptOldest, to: [set], downloadsPaths: [])

        #expect(selected == [mid.path, newFile.path])
        #expect(!selected.contains(old.path))
    }

    @Test func tiedModifiedDatesBreakDeterministicallyOnPath() {
        // Both files share the same mtime - "newest" must still resolve to
        // exactly one of them, consistently, rather than being ambiguous.
        let sameDate = date(100)
        let fileA = makeFile(path: "/a/aaa.bin", modifiedAt: sameDate)
        let fileB = makeFile(path: "/a/bbb.bin", modifiedAt: sameDate)
        let set = DuplicateSet(contentHash: "h", files: [fileA, fileB])

        let firstRun = SmartSelector.apply(.allExceptNewest, to: [set], downloadsPaths: [])
        let secondRun = SmartSelector.apply(.allExceptNewest, to: [set], downloadsPaths: [])

        #expect(firstRun == secondRun)
        #expect(firstRun.count == 1)
    }

    // MARK: allInDownloads

    @Test func allInDownloadsSelectsOnlyFilesUnderDownloads() {
        let inDownloads = makeFile(path: downloads + "/copy.bin", modifiedAt: date(100))
        let elsewhere = makeFile(path: "/Users/test/Documents/copy.bin", modifiedAt: date(200))
        let set = DuplicateSet(contentHash: "h", files: [inDownloads, elsewhere])

        let selected = SmartSelector.apply(.allInDownloads, to: [set], downloadsPaths: [downloads])

        #expect(selected == [inDownloads.path])
    }

    @Test func allInDownloadsWithEveryCopyInDownloadsKeepsNewest() {
        let old = makeFile(path: downloads + "/old.bin", modifiedAt: date(100))
        let newFile = makeFile(path: downloads + "/new.bin", modifiedAt: date(200))
        let set = DuplicateSet(contentHash: "h", files: [old, newFile])

        let selected = SmartSelector.apply(.allInDownloads, to: [set], downloadsPaths: [downloads])

        // Must not select every copy - the newest is always kept.
        #expect(selected == [old.path])
        #expect(!selected.contains(newFile.path))
    }

    @Test func allInDownloadsWithNoCopiesInDownloadsSelectsNothing() {
        let fileA = makeFile(path: "/Users/test/Documents/a.bin", modifiedAt: date(100))
        let fileB = makeFile(path: "/Users/test/Movies/b.bin", modifiedAt: date(200))
        let set = DuplicateSet(contentHash: "h", files: [fileA, fileB])

        let selected = SmartSelector.apply(.allInDownloads, to: [set], downloadsPaths: [downloads])

        #expect(selected.isEmpty)
    }

    @Test func allInDownloadsRespectsPathComponentBoundary() {
        // "/Users/test/Downloads2" must not be treated as inside
        // "/Users/test/Downloads".
        let lookalike = makeFile(path: "/Users/test/Downloads2/copy.bin", modifiedAt: date(100))
        let real = makeFile(path: downloads + "/copy.bin", modifiedAt: date(200))
        let set = DuplicateSet(contentHash: "h", files: [lookalike, real])

        let selected = SmartSelector.apply(.allInDownloads, to: [set], downloadsPaths: [downloads])

        #expect(selected == [real.path])
    }

    // MARK: cross-cutting invariant

    @Test func noRuleEverSelectsEveryFileInASet() {
        let files = [
            makeFile(path: downloads + "/a.bin", modifiedAt: date(100)),
            makeFile(path: downloads + "/b.bin", modifiedAt: date(200)),
            makeFile(path: downloads + "/c.bin", modifiedAt: date(300)),
        ]
        let set = DuplicateSet(contentHash: "h", files: files)
        let allPaths = Set(files.map(\.path))

        for rule in SmartSelectionRule.allCases {
            let selected = SmartSelector.apply(rule, to: [set], downloadsPaths: [downloads])
            #expect(selected != allPaths, "rule \(rule) selected every file in the set")
            #expect(selected.count < files.count, "rule \(rule) left no survivor")
        }
    }

    @Test func multipleSetsEachRetainASurvivor() {
        let setA = DuplicateSet(contentHash: "a", files: [
            makeFile(path: "/a/1.bin", modifiedAt: date(100)),
            makeFile(path: "/a/2.bin", modifiedAt: date(200)),
        ])
        let setB = DuplicateSet(contentHash: "b", files: [
            makeFile(path: downloads + "/1.bin", modifiedAt: date(100)),
            makeFile(path: downloads + "/2.bin", modifiedAt: date(200)),
            makeFile(path: downloads + "/3.bin", modifiedAt: date(300)),
        ])

        for rule in SmartSelectionRule.allCases {
            let selected = SmartSelector.apply(rule, to: [setA, setB], downloadsPaths: [downloads])
            let setASurvivors = setA.files.filter { !selected.contains($0.path) }
            let setBSurvivors = setB.files.filter { !selected.contains($0.path) }
            #expect(!setASurvivors.isEmpty, "rule \(rule) left set A with no survivor")
            #expect(!setBSurvivors.isEmpty, "rule \(rule) left set B with no survivor")
        }
    }
}
