import Testing
@testable import DustEaterCore

struct FileTypeClassifierTests {
    @Test func classifiesCommonExtensionsIntoExpectedCategories() {
        #expect(FileTypeClassifier.category(forFileName: "movie.mp4") == .videos)
        #expect(FileTypeClassifier.category(forFileName: "clip.mov") == .videos)
        #expect(FileTypeClassifier.category(forFileName: "photo.jpg") == .photos)
        #expect(FileTypeClassifier.category(forFileName: "photo.heic") == .photos)
        #expect(FileTypeClassifier.category(forFileName: "song.mp3") == .audio)
        #expect(FileTypeClassifier.category(forFileName: "track.wav") == .audio)
        #expect(FileTypeClassifier.category(forFileName: "report.pdf") == .documents)
        #expect(FileTypeClassifier.category(forFileName: "budget.xlsx") == .documents)
        #expect(FileTypeClassifier.category(forFileName: "archive.zip") == .archivesAndInstallers)
        #expect(FileTypeClassifier.category(forFileName: "installer.dmg") == .archivesAndInstallers)
        #expect(FileTypeClassifier.category(forFileName: "main.swift") == .codeAndProjects)
        #expect(FileTypeClassifier.category(forFileName: "index.tsx") == .codeAndProjects)
        #expect(FileTypeClassifier.category(forFileName: "package.json") == .codeAndProjects)
    }

    @Test func extensionMatchingIsCaseInsensitive() {
        #expect(FileTypeClassifier.category(forFileName: "MOVIE.MP4") == .videos)
        #expect(FileTypeClassifier.category(forFileName: "Photo.JPG") == .photos)
    }

    @Test func unknownOrMissingExtensionFallsBackToOther() {
        #expect(FileTypeClassifier.category(forFileName: "README") == .other)
        #expect(FileTypeClassifier.category(forFileName: "data.xyzzy") == .other)
    }
}

struct FileTypeIndexPartialTests {
    private func entry(_ name: String, size: Int64) -> FileTypeIndexEntry {
        FileTypeIndexEntry(path: "/x/\(name)", name: name, sizeBytes: size, isPhotosManaged: false)
    }

    @Test func recordAccumulatesTotalsAndEntries() {
        var partial = FileTypeIndexPartial()
        partial.record(entry("a.mp4", size: 100), category: .videos)
        partial.record(entry("b.mp4", size: 200), category: .videos)

        let index = partial.finalize()
        #expect(index.total(for: .videos).totalBytes == 300)
        #expect(index.total(for: .videos).fileCount == 2)
        #expect(index.entries(for: .videos).map(\.name) == ["b.mp4", "a.mp4"])
    }

    @Test func mergeCombinesTotalsExactlyEvenWhenEntriesAreCapped() {
        var left = FileTypeIndexPartial()
        var right = FileTypeIndexPartial()
        for i in 0..<10 {
            left.record(entry("left\(i).mp4", size: Int64(i)), category: .videos)
            right.record(entry("right\(i).mp4", size: Int64(i)), category: .videos)
        }

        var merged = left
        merged.merge(right)
        let index = merged.finalize()

        // Totals are exact regardless of any entry-list cap.
        #expect(index.total(for: .videos).fileCount == 20)
        #expect(index.total(for: .videos).totalBytes == (0..<10).reduce(0, +) * 2)
    }

    @Test func entryListStaysCappedAtMaxEntriesPerCategory() {
        var partial = FileTypeIndexPartial()
        for i in 0..<(FileTypeIndex.maxEntriesPerCategory + 500) {
            partial.record(entry("f\(i).mp4", size: Int64(i)), category: .videos)
        }

        let index = partial.finalize()
        #expect(index.entries(for: .videos).count == FileTypeIndex.maxEntriesPerCategory)
        // The cap keeps the *largest* entries, not an arbitrary prefix.
        #expect(index.entries(for: .videos).first?.sizeBytes == Int64(FileTypeIndex.maxEntriesPerCategory + 499))
    }

    @Test func rankedCategoriesOrdersBySizeDescendingAndOmitsEmptyOnes() {
        var partial = FileTypeIndexPartial()
        partial.record(entry("a.jpg", size: 100), category: .photos)
        partial.record(entry("b.mp4", size: 500), category: .videos)

        let index = partial.finalize()
        #expect(index.rankedCategories == [.videos, .photos])
        #expect(!index.rankedCategories.contains(.audio))
    }
}
