import Foundation
import Testing
@testable import DustEaterCore

struct CleanupCommitterTests {
    /// `/Users/<name>/Library` itself is protected by exact path (see
    /// `FileOperations.isSystemProtected`), but anything written a level
    /// deeper - like a scratch subfolder under Caches - is an ordinary
    /// user-writable location, unlike `FileManager.default.temporaryDirectory`
    /// (which resolves under `/var/...`, itself system-protected). Real
    /// permanent deletes below are scoped to files this test creates and
    /// removes itself, never the real Trash.
    private func makeScratchDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/DustEaterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func item(
        id: String = "item",
        deletablePaths: [String],
        sizeBytes: Int64 = 100,
        safety: PurgeSafetyLevel = .safe,
        blockingAppBundleID: String? = nil
    ) -> CleanupItem {
        CleanupItem(
            id: id,
            findingID: .packageManagerCaches,
            name: id,
            detail: "detail",
            sizeBytes: sizeBytes,
            safety: safety,
            hint: safety == .reportOnly ? "Manage elsewhere" : nil,
            deletablePaths: deletablePaths,
            revealPath: deletablePaths.first ?? "/",
            blockingAppBundleID: blockingAppBundleID
        )
    }

    // MARK: - commit

    @Test func commitPermanentlyDeletesRealFileAndReportsReclaimedBytes() async throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("cache.bin")
        try Data(repeating: 0xAB, count: 100).write(to: fileURL)

        let target = item(deletablePaths: [fileURL.path], sizeBytes: 100)
        let result = await CleanupCommitter.commit([target], permanently: true)

        #expect(result.deletedItemIDs == ["item"])
        #expect(result.deletedPaths == [fileURL.path])
        #expect(result.reclaimedBytes == 100)
        #expect(result.errors.isEmpty)
        #expect(result.trashedItems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func commitSkipsMissingPathWithoutError() async throws {
        let target = item(deletablePaths: ["/nonexistent/path/that/does/not/exist-\(UUID().uuidString)"])
        let result = await CleanupCommitter.commit([target], permanently: true)

        // Nothing existed to delete, so the item never counts as deleted -
        // but this is a benign no-op, not surfaced as an error either.
        #expect(result.deletedItemIDs.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(result.reclaimedBytes == 0)
    }

    @Test func commitRefusesReportOnlyItems() async throws {
        let target = item(deletablePaths: [], safety: .reportOnly)
        let result = await CleanupCommitter.commit([target], permanently: true)

        #expect(result.deletedItemIDs.isEmpty)
        #expect(result.errors.count == 1)
    }

    @Test func commitSkipsProtectedPaths() async throws {
        let target = item(deletablePaths: ["/System"])
        let result = await CleanupCommitter.commit([target], permanently: true)

        #expect(result.deletedItemIDs.isEmpty)
        #expect(result.errors.count == 1)
    }

    @Test func commitPartialFailureStillCommitsOtherItems() async throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let goodFile = dir.appendingPathComponent("good.bin")
        try Data(repeating: 0, count: 10).write(to: goodFile)

        let badItem = item(id: "bad", deletablePaths: ["/System"], sizeBytes: 999)
        let goodItem = item(id: "good", deletablePaths: [goodFile.path], sizeBytes: 10)

        let result = await CleanupCommitter.commit([badItem, goodItem], permanently: true)

        #expect(result.deletedItemIDs == ["good"])
        #expect(result.reclaimedBytes == 10)
        #expect(result.errors.count == 1)
    }

    // MARK: - putBack

    @Test func putBackMovesFileToOriginalLocationRecreatingParentDirectories() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let trashedURL = dir.appendingPathComponent("trashed/cache.bin")
        try FileManager.default.createDirectory(at: trashedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: trashedURL)

        // The original parent directory no longer exists - `putBack` must
        // recreate it, not just fail.
        let originalPath = dir.appendingPathComponent("original/nested/cache.bin").path

        try FileOperations.putBack(from: trashedURL, to: originalPath)

        #expect(FileManager.default.fileExists(atPath: originalPath))
        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))
    }

    @Test func putBackRefusesToOverwriteExistingFile() throws {
        let dir = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let trashedURL = dir.appendingPathComponent("trashed.bin")
        try Data([1]).write(to: trashedURL)

        let originalPath = dir.appendingPathComponent("original.bin").path
        try Data([2]).write(to: URL(fileURLWithPath: originalPath))

        #expect(throws: (any Error).self) {
            try FileOperations.putBack(from: trashedURL, to: originalPath)
        }
    }

    @Test func committerPutBackAccumulatesErrorsWithoutThrowing() async throws {
        let trashed = TrashedItem(
            originalPath: "/nonexistent-parent-\(UUID().uuidString)/x/y.bin",
            trashedURL: URL(fileURLWithPath: "/nonexistent-trashed-\(UUID().uuidString).bin")
        )
        let errors = await CleanupCommitter.putBack([trashed])
        #expect(errors.count == 1)
    }
}
