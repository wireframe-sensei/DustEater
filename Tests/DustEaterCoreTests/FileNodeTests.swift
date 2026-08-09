import Testing
@testable import DustEaterCore

struct FileNodeTests {
    /// Builds:
    /// /root
    ///   /root/sub1
    ///     /root/sub1/leaf.bin
    ///   /root/sub2
    ///   /root/file.bin
    private func makeTree() -> FileNode {
        let leaf = FileNode(name: "leaf.bin", path: "/root/sub1/leaf.bin", size: 10, isDirectory: false)
        let sub1 = FileNode(name: "sub1", path: "/root/sub1", size: 10, isDirectory: true, children: [leaf])
        let sub2 = FileNode(name: "sub2", path: "/root/sub2", size: 0, isDirectory: true)
        let file = FileNode(name: "file.bin", path: "/root/file.bin", size: 5, isDirectory: false)
        return FileNode(name: "root", path: "/root", size: 15, isDirectory: true, children: [sub1, sub2, file])
    }

    /// Replaces the old `find(path:)` this app used to walk the whole tree
    /// with on every selection change — `node(atPath:)` descends by path
    /// component instead, so this pins down its three basic behaviors:
    /// finding the root itself, finding a nested descendant, and correctly
    /// reporting a miss instead of crashing or matching the wrong node.
    @Test func findsSelfByOwnPath() {
        let root = makeTree()
        #expect(root.node(atPath: "/root")?.path == "/root")
    }

    @Test func findsNestedDescendant() {
        let root = makeTree()
        #expect(root.node(atPath: "/root/sub1/leaf.bin")?.name == "leaf.bin")
        #expect(root.node(atPath: "/root/sub2")?.name == "sub2")
        #expect(root.node(atPath: "/root/file.bin")?.name == "file.bin")
    }

    @Test func returnsNilForMissingOrUnrelatedPaths() {
        let root = makeTree()
        #expect(root.node(atPath: "/root/nonexistent") == nil)
        #expect(root.node(atPath: "/root/sub1/nonexistent.bin") == nil)
        #expect(root.node(atPath: "/elsewhere") == nil)
        #expect(root.node(atPath: "/root/") == nil)
    }
}
