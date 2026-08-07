import SwiftUI
import DustEaterCore

struct TreemapView: View {
    let rects: [TreemapRect]
    let rootPath: String
    let onSelectNode: (FileNode) -> Void
    @State private var hoveredId: String?

    var body: some View {
        Canvas { context, size in
            for rect in rects {
                drawRect(rect, isHovered: rect.id == hoveredId, in: &context)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { location in
            if let tapped = rects.first(where: { $0.contains(point: location) }) {
                onSelectNode(tapped.node)
            }
        }
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                hoveredId = rects.first { $0.contains(point: location) }?.id
            } else {
                hoveredId = nil
            }
        }
    }

    private func drawRect(_ rect: TreemapRect, isHovered: Bool, in context: inout GraphicsContext) {
        let depth = TreemapColors.depth(fromPath: rect.node.path, relativeTo: rootPath)
        let baseColor = TreemapColors.colorForNode(rect.node, depth: depth)

        // Apple-inspired subtle colors with depth
        let fillColor: Color
        if isHovered {
            fillColor = baseColor.opacity(0.95)
        } else {
            fillColor = baseColor.opacity(0.85)
        }

        let strokeColor: Color = isHovered
            ? Color.black.opacity(0.3)
            : Color.black.opacity(0.08)

        let lineWidth: CGFloat = isHovered ? 1.2 : 0.5

        // Draw shadow for depth (subtle)
        if isHovered {
            let shadowPath = Path(
                roundedRect: rect.frame.insetBy(dx: 0.5, dy: 0.5),
                cornerRadius: 1
            )
            context.fill(shadowPath, with: .color(.black.opacity(0.1)))
        }

        // Draw main rectangle
        let path = Path(
            roundedRect: rect.frame,
            cornerRadius: 1
        )
        context.fill(path, with: .color(fillColor))
        context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
    }
}
