import SwiftUI
import AppKit
import DustEaterCore

struct TreemapView: View {
    let rects: [TreemapRect]
    let onSelectNode: (FileNode) -> Void
    @State private var hoveredId: String?
    @State private var mouseLocation: CGPoint = .zero
    @State private var showTooltip = false
    @Environment(\.controlActiveState) private var controlActiveState

    /// The hover highlight is this view's only accent-colored "this is the
    /// current selection" indicator, so it's the one that needs to track
    /// window focus — same as a table's selected-row highlight desaturating
    /// to gray the moment the window isn't key, instead of staying accent-
    /// colored while the app is in the background.
    private var highlightColor: Color {
        controlActiveState == .key ? Color.accentColor : Color(nsColor: .systemGray)
    }

    /// Rects large enough to carry a label, precomputed once per body
    /// evaluation rather than filtered inside `ForEach`'s content closure —
    /// so `ForEach` only ever diffs identities for rects that actually
    /// render something, instead of creating and immediately discarding a
    /// view per rect that's too small to label.
    private var labeledRects: [TreemapRect] {
        rects.filter { min($0.frame.width, $0.frame.height) > TreemapMetrics.labelThresholdMinimum }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base layer: every rect's resting-state fill/stroke, using each
            // rect's precomputed `color`. Deliberately doesn't read
            // `hoveredId` — moving the mouse across tiles must not
            // invalidate and re-run this full-level draw loop.
            Canvas { context, size in
                for rect in rects {
                    drawRect(rect, in: &context)
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

            // Hover highlight: a separate, tiny draw scoped to just the
            // hovered rect, so mouse movement only ever costs redrawing one
            // rect instead of the whole level (which the base Canvas above
            // is now shielded from by not depending on `hoveredId` at all).
            if let hoveredId, let hovered = rects.first(where: { $0.id == hoveredId }) {
                Canvas { context, _ in
                    drawHoverHighlight(hovered, in: &context)
                }
                .allowsHitTesting(false)
            }

            // Text labels overlay for larger rectangles
            ForEach(labeledRects, id: \.id) { rect in
                let minDim = min(rect.frame.width, rect.frame.height)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rect.node.name)
                        .font((minDim > TreemapMetrics.labelThresholdLargeFont ? Font.callout : Font.caption).weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.tail)

                    if minDim > TreemapMetrics.labelThresholdShowsSize {
                        Text(ByteFormatter.string(fromBytes: rect.node.size))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(4)
                .frame(maxWidth: rect.frame.width - 8, alignment: .topLeading)
                .position(x: rect.frame.midX, y: rect.frame.midY)
            }

            // Tooltip for hovered item with smooth animation
            if showTooltip, let hoveredId, let hovered = rects.first(where: { $0.id == hoveredId }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hovered.node.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    Divider()
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: hovered.node.isDirectory ? "folder.fill" : "doc.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(ByteFormatter.string(fromBytes: hovered.node.size))
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        if hovered.node.isDirectory {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("\(hovered.node.itemCount) items")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(width: TooltipMetrics.width, alignment: .leading)
                .background(.regularMaterial)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                .offset(x: TooltipMetrics.offsetX, y: TooltipMetrics.offsetY)
                .position(x: mouseLocation.x, y: mouseLocation.y)
                .opacity(showTooltip ? 1.0 : 0.0)
            }
        }
    }

    /// Resting-state draw. Uses the rect's precomputed `color` — no per-call
    /// depth/theme lookup — since this runs once per rect on every base
    /// `Canvas` redraw.
    private func drawRect(_ rect: TreemapRect, in context: inout GraphicsContext) {
        let path = Path(roundedRect: rect.frame, cornerRadius: TreemapMetrics.tileCornerRadius)
        context.fill(path, with: .color(rect.color.opacity(0.85)))
        context.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 0.5)
    }

    /// Hovered-state draw, used only by the small overlay `Canvas` scoped to
    /// the single currently-hovered rect.
    private func drawHoverHighlight(_ rect: TreemapRect, in context: inout GraphicsContext) {
        let shadowPath = Path(roundedRect: rect.frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: TreemapMetrics.tileCornerRadius)
        context.fill(shadowPath, with: .color(.black.opacity(TreemapMetrics.hoverShadowOpacity)))

        let path = Path(roundedRect: rect.frame, cornerRadius: TreemapMetrics.tileCornerRadius)
        context.fill(path, with: .color(rect.color.opacity(0.95)))
        context.stroke(path, with: .color(highlightColor.opacity(0.6)), lineWidth: TreemapMetrics.hoverStrokeLineWidth)
    }
}
