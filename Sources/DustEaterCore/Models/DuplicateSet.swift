import Foundation

/// A group of files that are byte-identical to one another, as established
/// by `DuplicateDetector`'s size -> quick-hash -> full-hash pipeline.
public struct DuplicateSet: Sendable, Identifiable {
    public var id: String { contentHash }

    /// Full SHA-256 hex digest of the shared content.
    public let contentHash: String
    /// Every file sharing `contentHash`, newest `modifiedAt` first. Ordering
    /// here is what "except newest" / "except oldest" smart-selection reads
    /// without re-sorting.
    public let files: [InspectedFile]

    public init(contentHash: String, files: [InspectedFile]) {
        self.contentHash = contentHash
        self.files = files
    }

    /// The logical size shared by every file in the set. All files here are
    /// byte-identical, so any member's size is representative.
    public var fileSize: Int64 {
        files.first?.logicalSize ?? 0
    }

    /// Disk space reclaimable by keeping exactly one copy and deleting the
    /// rest. A single-file set (which the detector never actually produces,
    /// but which is worth being correct about) wastes nothing.
    public var wastedBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }
}
