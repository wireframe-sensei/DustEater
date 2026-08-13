import Foundation
import Testing
@testable import DustEaterCore

struct DuplicatePartitionerTests {
    private func makeFile(
        path: String,
        size: Int64,
        deviceID: UInt64 = 1,
        inode: UInt64? = nil
    ) -> InspectedFile {
        InspectedFile(
            path: path,
            name: (path as NSString).lastPathComponent,
            logicalSize: size,
            allocatedSize: size,
            modifiedAt: Date(),
            accessedAt: Date(),
            createdAt: Date(),
            deviceID: deviceID,
            inode: inode ?? UInt64(abs(path.hashValue))
        )
    }

    // MARK: groupBySize

    @Test func groupBySizeDropsDistinctSizes() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 200)]
        let groups = DuplicatePartitioner.groupBySize(files, minimumSize: 0)
        #expect(groups.isEmpty)
    }

    @Test func groupBySizeKeepsMatchingSizes() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 100)]
        let groups = DuplicatePartitioner.groupBySize(files, minimumSize: 0)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test func groupBySizeAppliesMinimumFloor() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 100)]
        let groups = DuplicatePartitioner.groupBySize(files, minimumSize: 200)
        #expect(groups.isEmpty)
    }

    @Test func groupBySizeDropsZeroByteFiles() {
        let files = [makeFile(path: "/a", size: 0), makeFile(path: "/b", size: 0)]
        let groups = DuplicatePartitioner.groupBySize(files, minimumSize: 0)
        #expect(groups.isEmpty)
    }

    // MARK: collapsingHardLinks

    @Test func collapsingHardLinksKeepsOnePerInode() {
        let files = [
            makeFile(path: "/a", size: 100, deviceID: 1, inode: 42),
            makeFile(path: "/b", size: 100, deviceID: 1, inode: 42),
            makeFile(path: "/c", size: 100, deviceID: 1, inode: 43),
        ]
        let collapsed = DuplicatePartitioner.collapsingHardLinks(files)
        #expect(collapsed.count == 2)
    }

    @Test func collapsingHardLinksTreatsSameInodeDifferentDeviceAsDistinct() {
        let files = [
            makeFile(path: "/a", size: 100, deviceID: 1, inode: 42),
            makeFile(path: "/b", size: 100, deviceID: 2, inode: 42),
        ]
        let collapsed = DuplicatePartitioner.collapsingHardLinks(files)
        #expect(collapsed.count == 2)
    }

    // MARK: partition

    @Test func partitionSplitsOnDistinctHash() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 100)]
        let hashes: [String: String] = ["/a": "hash1", "/b": "hash2"]
        let groups = DuplicatePartitioner.partition(files) { hashes[$0.path] }
        #expect(groups.isEmpty)
    }

    @Test func partitionGroupsOnMatchingHash() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 100)]
        let hashes: [String: String] = ["/a": "same", "/b": "same"]
        let groups = DuplicatePartitioner.partition(files) { hashes[$0.path] }
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test func partitionDropsFilesWithNoDigest() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 100), makeFile(path: "/c", size: 100)]
        let hashes: [String: String] = ["/a": "same", "/b": "same"] // "/c" has no digest - read failure
        let groups = DuplicatePartitioner.partition(files) { hashes[$0.path] }
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
        #expect(!groups[0].contains { $0.path == "/c" })
    }

    @Test func partitionDropsSingletonGroups() {
        let files = [makeFile(path: "/a", size: 100), makeFile(path: "/b", size: 200)]
        let hashes: [String: String] = ["/a": "hash1", "/b": "hash2"]
        let groups = DuplicatePartitioner.partition(files) { hashes[$0.path] }
        #expect(groups.isEmpty)
    }
}
