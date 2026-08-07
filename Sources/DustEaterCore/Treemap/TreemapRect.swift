import Foundation
import CoreGraphics

/// One rectangle in a computed treemap layout, tied to a `FileNode`.
public struct TreemapRect: Sendable, Identifiable {
    public let id: String
    public let node: FileNode
    /// The rectangle's bounds in the treemap coordinate space (0...width, 0...height).
    public let frame: CGRect

    public init(node: FileNode, frame: CGRect) {
        self.id = node.id
        self.node = node
        self.frame = frame
    }

    /// Whether a point in the treemap coordinate space hits this rectangle.
    public func contains(point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

/// Computes a Squarified Treemap layout for a given `FileNode` and container size.
/// Returns a flat list of `TreemapRect`s (one per node in the tree, recursively).
///
/// Squarified Treemap minimizes aspect ratios (rectangles trend toward square)
/// by iteratively partitioning into rows and trying to keep each row's aspect
/// ratio close to 1. This produces visually balanced layouts even with highly
/// skewed size distributions.
public enum TreemapLayout {
    public static func compute(node: FileNode, size: CGSize) -> [TreemapRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        var rects: [TreemapRect] = []
        layoutNode(node, frame: CGRect(origin: .zero, size: size), rects: &rects)
        return rects
    }

    private static func layoutNode(_ node: FileNode, frame: CGRect, rects: inout [TreemapRect]) {
        guard frame.width > 0, frame.height > 0 else { return }
        guard node.size > 0 else { return }

        rects.append(TreemapRect(node: node, frame: frame))

        guard !node.children.isEmpty else { return }

        // Recursively layout children in this node's frame, leaving a tiny margin
        // so labels won't visually overlap at level boundaries.
        let inset = frame.insetBy(dx: 1, dy: 1)
        guard inset.width > 2, inset.height > 2 else { return }

        layoutChildren(node.children, in: inset, rects: &rects)
    }

    private static func layoutChildren(_ children: [FileNode], in rect: CGRect, rects: inout [TreemapRect]) {
        guard !children.isEmpty else { return }

        let totalSize = children.reduce(into: Int64(0)) { $0 += $1.size }
        guard totalSize > 0 else { return }

        // Squarified algorithm: partition into rows, minimizing aspect ratios.
        var remaining = children
        var currentRect = rect

        while !remaining.isEmpty {
            // Try to fit items into a horizontal or vertical strip, depending on
            // the current container's aspect ratio. If the container is wider than
            // tall, use horizontal strips; otherwise vertical.
            let (row, rest) = squarify(
                items: remaining,
                container: currentRect,
                totalSize: totalSize
            )
            remaining = rest

            // Layout the row along one edge of the container.
            let rowFrame = layoutRow(row, along: currentRect, totalSize: totalSize)
            for (childNode, childFrame) in rowFrame {
                layoutNode(childNode, frame: childFrame, rects: &rects)
            }

            // Shrink the container by removing the area we just used.
            currentRect = remainingFrame(after: rowFrame, in: currentRect)
        }
    }

    private typealias Item = FileNode

    /// Greedily partitions `items` into a single row, trying to minimize the
    /// worst aspect ratio. Returns the items that fit in this row and the
    /// remaining items. Uses mid-point improvement heuristic to prefer more
    /// square-like rectangles.
    private static func squarify(items: [Item], container: CGRect, totalSize: Int64) -> ([Item], [Item]) {
        guard !items.isEmpty else { return ([], []) }

        let isHorizontal = container.width >= container.height
        let stripLength = isHorizontal ? container.width : container.height

        var row: [Item] = []
        var worstRatio: Double = .infinity
        var bestI = 0

        for i in items.indices {
            let candidate = Array(items[0...i])
            let ratio = rowAspectRatio(candidate, stripLength: stripLength, totalSize: totalSize, isHorizontal: isHorizontal)

            // For the first item, always include it
            if row.isEmpty {
                row = candidate
                worstRatio = ratio
                bestI = i
                continue
            }

            // For subsequent items, check if adding it improves the ratio
            if ratio < worstRatio {
                // Improvement found; remember this point
                worstRatio = ratio
                bestI = i
            } else {
                // Ratio got worse; return the best row we found
                break
            }
        }

        let finalRow = Array(items[0...bestI])
        let remaining = bestI + 1 < items.count ? Array(items[(bestI + 1)...]) : []
        return (finalRow, remaining)
    }

    /// Computes the worst (maximum) aspect ratio for a given row.
    /// Uses a bias toward square shapes by penalizing extreme aspect ratios.
    private static func rowAspectRatio(_ items: [Item], stripLength: Double, totalSize: Int64, isHorizontal: Bool) -> Double {
        let rowSize = items.reduce(into: Int64(0)) { $0 += $1.size }
        let stripThickness = Double(rowSize) / Double(totalSize) * (isHorizontal ? 600 : 400)

        guard stripThickness > 0 else { return .infinity }

        // Compute aspect ratios for each item in the row.
        // Use power of 1.5 to heavily penalize elongated rectangles
        return items.map { item in
            let itemLength = Double(item.size) / Double(rowSize) * stripLength
            let ratio = max(itemLength / stripThickness, stripThickness / itemLength)
            // Power bias: 1.0 = perfect square, > 1.5 = penalized heavily
            return pow(ratio, 1.5)
        }.max() ?? 1
    }

    /// Layouts a row of items along one edge of the container, returning
    /// a list of (node, frame) pairs.
    private static func layoutRow(_ items: [Item], along container: CGRect, totalSize: Int64) -> [(Item, CGRect)] {
        guard !items.isEmpty else { return [] }

        let rowSize = items.reduce(into: Int64(0)) { $0 += $1.size }
        let isHorizontal = container.width >= container.height

        var results: [(Item, CGRect)] = []
        var offset: CGFloat = 0

        if isHorizontal {
            // Horizontal strip: items laid out left-to-right.
            let stripHeight = container.height * CGFloat(rowSize) / CGFloat(totalSize)
            for item in items {
                let itemWidth = container.width * CGFloat(item.size) / CGFloat(rowSize)
                let itemFrame = CGRect(
                    x: container.minX + offset,
                    y: container.minY,
                    width: itemWidth,
                    height: stripHeight
                )
                results.append((item, itemFrame))
                offset += itemWidth
            }
        } else {
            // Vertical strip: items laid out top-to-bottom.
            let stripWidth = container.width * CGFloat(rowSize) / CGFloat(totalSize)
            for item in items {
                let itemHeight = container.height * CGFloat(item.size) / CGFloat(rowSize)
                let itemFrame = CGRect(
                    x: container.minX,
                    y: container.minY + offset,
                    width: stripWidth,
                    height: itemHeight
                )
                results.append((item, itemFrame))
                offset += itemHeight
            }
        }

        return results
    }

    /// Removes the area occupied by `row` from the `container` and returns
    /// the remaining rectangle.
    private static func remainingFrame(after row: [(Item, CGRect)], in container: CGRect) -> CGRect {
        guard !row.isEmpty else { return container }

        let isHorizontal = container.width >= container.height
        let rowHeight = row[0].1.height

        if isHorizontal {
            return CGRect(
                x: container.minX,
                y: container.minY + rowHeight,
                width: container.width,
                height: container.height - rowHeight
            )
        } else {
            let rowWidth = row[0].1.width
            return CGRect(
                x: container.minX + rowWidth,
                y: container.minY,
                width: container.width - rowWidth,
                height: container.height
            )
        }
    }
}
