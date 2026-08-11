import Foundation

/// A node in the scanned filesystem tree.
///
/// `size` is the on-disk allocated size in bytes (blocks actually consumed),
/// not the logical/"apparent" size - this matches how tools like WizTree
/// report disk usage (sparse files, compressed files, and filesystem block
/// rounding are reflected accurately). For directories, `size` is the sum
/// of all descendant allocated sizes.
public struct FileNode: Sendable, Identifiable {
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

extension FileNode: Equatable, Hashable {
    /// Deliberately *not* synthesized: the compiler-generated `==`/`hash`
    /// for a struct holding `children: [FileNode]` recurse into every
    /// descendant, so a single comparison on a large scan's root would walk
    /// the entire tree. `path` already uniquely identifies a node within a
    /// given scan (it's `id`), so equality only needs `path` + `size` - no
    /// caller here needs "and every descendant is byte-identical too" - and
    /// hashing only `path` keeps that O(1) while still satisfying Hashable
    /// (equal nodes necessarily share a `path`, so their hashes agree).
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.path == rhs.path && lhs.size == rhs.size
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
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

    /// Removes a node at the given path and updates parent sizes.
    /// Returns an updated tree, or nil if the path doesn't exist.
    public func removingNode(atPath pathToRemove: String) -> FileNode? {
        guard pathToRemove != self.path else { return nil }
        guard pathToRemove.hasPrefix(self.path) else { return nil }

        var updated = self
        let deletedSize = findNodeSize(atPath: pathToRemove)

        updated.children = children.compactMap { child in
            if child.path == pathToRemove {
                return nil
            }
            if pathToRemove.hasPrefix(child.path + "/") {
                return child.removingNode(atPath: pathToRemove)
            }
            return child
        }

        updated.size = max(0, updated.size - deletedSize)
        updated.itemCount = max(0, updated.itemCount - 1)

        return updated
    }

    private func findNodeSize(atPath path: String) -> Int64 {
        if self.path == path {
            return self.size
        }
        for child in children {
            if path.hasPrefix(child.path) {
                return child.findNodeSize(atPath: path)
            }
        }
        return 0
    }

    /// Looks up a descendant by its full path, descending one path component
    /// at a time and matching by `name` - rather than scanning the whole
    /// tree (the old `find(path:)`) or maintaining a separate `path → node`
    /// index (which duplicates every node's ~64-byte value just to serve an
    /// occasional click). Cost is O(depth × fan-out of each level), which on
    /// a real filesystem tree is a handful of string compares - negligible
    /// at UI-selection frequency.
    ///
    /// `path` must be `self.path` or nested under it, as produced by this
    /// same tree; returns `nil` if no such descendant exists.
    public func node(atPath path: String) -> FileNode? {
        guard path != self.path else { return self }
        guard path.hasPrefix(self.path) else { return nil }

        var relative = path.dropFirst(self.path.count)
        if relative.first == "/" { relative = relative.dropFirst() }
        guard !relative.isEmpty else { return nil }

        var current = self
        for component in relative.split(separator: "/") {
            guard let match = current.children.first(where: { $0.name == component }) else {
                return nil
            }
            current = match
        }
        return current
    }
}
