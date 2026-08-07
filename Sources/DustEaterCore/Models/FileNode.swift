import Foundation

/// A node in the scanned filesystem tree.
///
/// `size` is the on-disk allocated size in bytes (blocks actually consumed),
/// not the logical/"apparent" size — this matches how tools like WizTree
/// report disk usage (sparse files, compressed files, and filesystem block
/// rounding are reflected accurately). For directories, `size` is the sum
/// of all descendant allocated sizes.
public struct FileNode: Sendable, Identifiable, Equatable, Hashable {
    public var id: String { path }

    public let name: String
    public let path: String
    public var size: Int64
    public let isDirectory: Bool
    public let isSymlink: Bool
    public var children: [FileNode]

    /// Number of filesystem entries (files + directories) contained within
    /// this node, including itself. Useful for scan progress reporting.
    public var itemCount: Int

    public init(
        name: String,
        path: String,
        size: Int64,
        isDirectory: Bool,
        isSymlink: Bool = false,
        children: [FileNode] = [],
        itemCount: Int = 1
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.children = children
        self.itemCount = itemCount
    }
}

extension FileNode {
    /// Returns a copy of this node with children sorted by size, descending.
    public func sortedBySize() -> FileNode {
        var copy = self
        copy.children = children
            .map { $0.sortedBySize() }
            .sorted { $0.size > $1.size }
        return copy
    }
}
