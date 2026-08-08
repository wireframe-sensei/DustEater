import SwiftUI
import AppKit
import DustEaterCore

struct TreemapView: View {
    let rects: [TreemapRect]
    let rootPath: String
    let onSelectNode: (FileNode) -> Void
    let theme: ColorTheme
    @State private var hoveredId: String?
    @State private var previousHoveredId: String?
    @State private var mouseLocation: CGPoint = .zero
    @State private var showTooltip = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Canvas for rectangles
            Canvas { context, size in
                for rect in rects {
                    drawRect(rect, isHovered: rect.id == hoveredId, in: &context)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { location in
                if let tapped = rects.first(where: { $0.contains(point: location) }) {
                    onSelectNode(tapped.node)
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    mouseLocation = location
                    let newHoveredId = rects.first { $0.contains(point: location) }?.id

                    // Only trigger animation when tile changes
                    if newHoveredId != hoveredId {
                        previousHoveredId = hoveredId
                        hoveredId = newHoveredId

                        if newHoveredId != nil {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTooltip = true
                            }
                            NSCursor.pointingHand.set()
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTooltip = false
                            }
                            NSCursor.arrow.set()
                        }
                    }
                } else {
                    hoveredId = nil
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                    NSCursor.arrow.set()
                }
            }

            // Text labels overlay for larger rectangles
            ForEach(rects, id: \.id) { rect in
                let minDim = min(rect.frame.width, rect.frame.height)
                if minDim > 60 {  // Only show text for large enough rectangles
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rect.node.name)
                            .font(.system(size: minDim > 120 ? 12 : 10, weight: .semibold, design: .default))
                            .lineLimit(2)
                            .truncationMode(.tail)

                        if minDim > 100 {
                            Text(ByteFormatter.string(fromBytes: rect.node.size))
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(4)
                    .frame(maxWidth: rect.frame.width - 8, alignment: .topLeading)
                    .position(x: rect.frame.midX, y: rect.frame.midY)
                }
            }

            // Tooltip for hovered item with smooth animation
            if showTooltip, let hoveredId, let hovered = rects.first(where: { $0.id == hoveredId }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hovered.node.name)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .lineLimit(1)

                    Divider()
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: hovered.node.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(ByteFormatter.string(fromBytes: hovered.node.size))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if hovered.node.isDirectory {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("\(hovered.node.itemCount) items")
                                    .font(.system(size: 11, design: .default))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(width: 200, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                .offset(x: 20, y: -50)
                .position(x: mouseLocation.x, y: mouseLocation.y)
                .opacity(showTooltip ? 1.0 : 0.0)
            }
        }
    }

    private func drawRect(_ rect: TreemapRect, isHovered: Bool, in context: inout GraphicsContext) {
        let depth = TreemapColors.depth(fromPath: rect.node.path, relativeTo: rootPath)
        let baseColor = TreemapColors.colorForNode(rect.node, depth: depth, theme: theme)

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
