import Foundation

/// A single file's stat-derived facts, gathered on demand for the duplicate
/// and large-file inspectors. Deliberately separate from `FileNode`, which
/// only carries what a full disk scan can cheaply batch via
/// `getattrlistbulk` - see `FileStatReader` for why this is `lstat`-backed
/// instead.
public struct InspectedFile: Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let name: String
    /// Logical size (`st_size`) - the file's actual byte count, as opposed to
    /// `FileNode.size`, which is on-disk *allocated* size. Duplicate
    /// detection and large-file thresholds both need the logical size: two
    /// byte-identical files can have different allocated sizes depending on
    /// filesystem compression, and a threshold like ">1 GB" means logical
    /// bytes, not blocks consumed.
    public let logicalSize: Int64
    /// On-disk allocated size (`st_blocks * 512`), kept alongside for parity
    /// with the rest of the app's size reporting where useful.
    public let allocatedSize: Int64
    public let modifiedAt: Date
    public let accessedAt: Date
    public let createdAt: Date
    /// Device and inode together identify a unique piece of storage. Two
    /// `InspectedFile`s sharing both are hard-link aliases of the same
    /// bytes, not independent copies - see `DuplicateDetector`'s hard-link
    /// collapse stage.
    public let deviceID: UInt64
    public let inode: UInt64

    public init(
        path: String,
        name: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        modifiedAt: Date,
        accessedAt: Date,
        createdAt: Date,
        deviceID: UInt64,
        inode: UInt64
    ) {
        self.path = path
        self.name = name
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.modifiedAt = modifiedAt
        self.accessedAt = accessedAt
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.inode = inode
    }
}

extension InspectedFile: Equatable, Hashable {
    /// Deliberately *not* synthesized, matching `FileNode`'s reasoning
    /// (`FileNode.swift`): `path` already uniquely identifies a file within a
    /// given scan, so equality and hashing only need it.
    public static func == (lhs: InspectedFile, rhs: InspectedFile) -> Bool {
        lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

extension InspectedFile {
    /// True when this file and `other` are hard-link aliases of the same
    /// underlying storage (same device and inode). Aliases don't waste extra
    /// disk space, so they must never be reported as duplicates.
    public func isHardLinkAlias(of other: InspectedFile) -> Bool {
        deviceID == other.deviceID && inode == other.inode
    }
}
