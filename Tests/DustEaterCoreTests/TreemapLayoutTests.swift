import Testing
import Foundation
import CoreGraphics
@testable import DustEaterCore

struct TreemapLayoutTests {
    @Test func computeLayoutProducesRectsForAllNodes() {
        // Create a simple tree: root with 3 children.
        let child1 = FileNode(name: "large.bin", path: "/test/large.bin", size: 8000, isDirectory: false)
        let child2 = FileNode(name: "medium.bin", path: "/test/medium.bin", size: 1500, isDirectory: false)
        let child3 = FileNode(name: "small.bin", path: "/test/small.bin", size: 500, isDirectory: false)
        let root = FileNode(
            name: "test",
            path: "/test",
            size: 10000,
            isDirectory: true,
            children: [child1, child2, child3]
        )

        let rects = TreemapLayout.compute(node: root, size: CGSize(width: 600, height: 400))

        // Should have 4 rects: 1 root + 3 children.
        #expect(rects.count == 4)

        // Root rect should be the full container.
        guard let rootRect = rects.first(where: { $0.node.path == "/test" }) else {
            Issue.record("Root rect not found")
            return
        }
        #expect(rootRect.frame.width > 0)
        #expect(rootRect.frame.height > 0)

        // All rects should fit within the container.
        for rect in rects {
            #expect(rect.frame.minX >= 0)
            #expect(rect.frame.minY >= 0)
            #expect(rect.frame.maxX <= 600 + 1)
            #expect(rect.frame.maxY <= 400 + 1)
        }
    }

    @Test func containsPointHitsCorrectRect() {
        let child1 = FileNode(name: "a.bin", path: "/test/a.bin", size: 5000, isDirectory: false)
        let child2 = FileNode(name: "b.bin", path: "/test/b.bin", size: 5000, isDirectory: false)
        let root = FileNode(
            name: "test",
            path: "/test",
            size: 10000,
            isDirectory: true,
            children: [child1, child2]
        )

        let rects = TreemapLayout.compute(node: root, size: CGSize(width: 400, height: 200))

        // Find a point that should be in child1's rect.
        guard let child1Rect = rects.first(where: { $0.node.path == "/test/a.bin" }) else {
            Issue.record("Child1 rect not found")
            return
        }
        let testPoint = CGPoint(x: child1Rect.frame.midX, y: child1Rect.frame.midY)

        #expect(child1Rect.contains(point: testPoint))
    }

    @Test func emptyTreeProducesEmptyLayout() {
        let root = FileNode(name: "empty", path: "/empty", size: 0, isDirectory: true)
        let rects = TreemapLayout.compute(node: root, size: CGSize(width: 400, height: 300))

        #expect(rects.isEmpty)
    }

    @Test func zeroSizedContainerProducesEmptyLayout() {
        let child = FileNode(name: "file.bin", path: "/test/file.bin", size: 1000, isDirectory: false)
        let root = FileNode(name: "test", path: "/test", size: 1000, isDirectory: true, children: [child])

        let rects = TreemapLayout.compute(node: root, size: CGSize(width: 0, height: 0))
        #expect(rects.isEmpty)
    }
}
