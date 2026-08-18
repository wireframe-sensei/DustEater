import Foundation
import Testing
@testable import DustEaterCore

struct FileTypeBrowserTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DustEaterFileTypeBrowserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadDetailsReturnsLogicalSizeAndSortsDescending() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let smallURL = dir.appendingPathComponent("small.mp4")
        let bigURL = dir.appendingPathComponent("big.mp4")
        try Data(repeating: 0, count: 10).write(to: smallURL)
        try Data(repeating: 0, count: 1_000).write(to: bigURL)

        let entries = [
            FileTypeIndexEntry(path: smallURL.path, name: "small.mp4", sizeBytes: 10, isPhotosManaged: false),
            FileTypeIndexEntry(path: bigURL.path, name: "big.mp4", sizeBytes: 1_000, isPhotosManaged: false),
        ]

        let details = await FileTypeBrowser.loadDetails(for: entries, lastUsedDateProvider: { _ in nil })

        #expect(details.map(\.name) == ["big.mp4", "small.mp4"])
        #expect(details.first?.logicalSize == 1_000)
    }

    @Test func loadDetailsSkipsEntriesNoLongerOnDisk() async throws {
        let entries = [
            FileTypeIndexEntry(path: "/nonexistent-\(UUID().uuidString).mp4", name: "gone.mp4", sizeBytes: 100, isPhotosManaged: false),
        ]

        let details = await FileTypeBrowser.loadDetails(for: entries, lastUsedDateProvider: { _ in nil })

        #expect(details.isEmpty)
    }

    @Test func loadDetailsCarriesPhotosManagedFlagThrough() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("original.heic")
        try Data(repeating: 0, count: 10).write(to: fileURL)

        let entries = [
            FileTypeIndexEntry(path: fileURL.path, name: "original.heic", sizeBytes: 10, isPhotosManaged: true),
        ]

        let details = await FileTypeBrowser.loadDetails(for: entries, lastUsedDateProvider: { _ in nil })

        #expect(details.first?.isPhotosManaged == true)
    }

    @Test func loadDetailsUsesProvidedLastUsedDateProvider() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("file.mp4")
        try Data(repeating: 0, count: 10).write(to: fileURL)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [FileTypeIndexEntry(path: fileURL.path, name: "file.mp4", sizeBytes: 10, isPhotosManaged: false)]

        let details = await FileTypeBrowser.loadDetails(for: entries, lastUsedDateProvider: { _ in fixedDate })

        #expect(details.first?.lastUsedDate == fixedDate)
    }

    // MARK: - makeCleanupItem

    @Test func makeCleanupItemIsAlwaysUserContent() {
        let detail = ExploreFileDetail(path: "/x/video.mp4", name: "video.mp4", logicalSize: 100, lastUsedDate: nil, isPhotosManaged: false, isiCloudSynced: false)
        let item = detail.makeCleanupItem(category: .videos)

        #expect(item.isUserContent == true)
        #expect(item.source == .fileType(.videos))
        #expect(item.deletablePaths == ["/x/video.mp4"])
        #expect(item.safety == .safe)
    }

    @Test func makeCleanupItemLocksPhotosManagedOriginals() {
        let detail = ExploreFileDetail(path: "/x/original.heic", name: "original.heic", logicalSize: 100, lastUsedDate: nil, isPhotosManaged: true, isiCloudSynced: false)
        let item = detail.makeCleanupItem(category: .photos)

        #expect(item.isReportOnly == true)
        #expect(item.deletablePaths.isEmpty)
        #expect(item.hint == "Managed by Photos - delete it in the Photos app.")
        // isUserContent is unconditional even for a locked item - the
        // moment it's *shown* selectable-adjacent in Explore, it should
        // never silently reopen the permanent-delete option for the rest
        // of the selection were it somehow included.
        #expect(item.isUserContent == true)
    }

    @Test func makeCleanupItemCarriesiCloudFlag() {
        let detail = ExploreFileDetail(path: "/x/doc.pdf", name: "doc.pdf", logicalSize: 100, lastUsedDate: nil, isPhotosManaged: false, isiCloudSynced: true)
        let item = detail.makeCleanupItem(category: .documents)

        #expect(item.isiCloudSynced == true)
    }
}
