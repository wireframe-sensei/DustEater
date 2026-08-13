import Foundation
import Testing
@testable import DustEaterCore

struct DuplicateSetTests {
    private func makeFile(path: String, size: Int64, modifiedAt: Date = Date()) -> InspectedFile {
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

    @Test func wastedBytesIsZeroForSingleFile() {
        let set = DuplicateSet(contentHash: "abc", files: [makeFile(path: "/a", size: 1_000)])
        #expect(set.wastedBytes == 0)
    }

    @Test func wastedBytesCountsAllButOneCopy() {
        let files = [
            makeFile(path: "/a", size: 1_000),
            makeFile(path: "/b", size: 1_000),
            makeFile(path: "/c", size: 1_000),
        ]
        let set = DuplicateSet(contentHash: "abc", files: files)
        #expect(set.wastedBytes == 2_000)
    }

    @Test func fileSizeReadsFromFirstFile() {
        let files = [makeFile(path: "/a", size: 5_000), makeFile(path: "/b", size: 5_000)]
        let set = DuplicateSet(contentHash: "abc", files: files)
        #expect(set.fileSize == 5_000)
    }

    @Test func wastedBytesIsZeroForEmptySet() {
        let set = DuplicateSet(contentHash: "abc", files: [])
        #expect(set.wastedBytes == 0)
        #expect(set.fileSize == 0)
    }

    @Test func hardLinkAliasDetection() {
        let a = InspectedFile(
            path: "/a", name: "a", logicalSize: 100, allocatedSize: 100,
            modifiedAt: Date(), accessedAt: Date(), createdAt: Date(),
            deviceID: 1, inode: 42
        )
        let b = InspectedFile(
            path: "/b", name: "b", logicalSize: 100, allocatedSize: 100,
            modifiedAt: Date(), accessedAt: Date(), createdAt: Date(),
            deviceID: 1, inode: 42
        )
        let c = InspectedFile(
            path: "/c", name: "c", logicalSize: 100, allocatedSize: 100,
            modifiedAt: Date(), accessedAt: Date(), createdAt: Date(),
            deviceID: 1, inode: 43
        )
        #expect(a.isHardLinkAlias(of: b))
        #expect(!a.isHardLinkAlias(of: c))
    }
}
