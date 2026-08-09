import SwiftUI
import DustEaterCore

struct FileTreeListView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void

    var body: some View {
        List(selection: $selectedPath) {
            OutlineGroup(root.children.sorted { $0.size > $1.size }, id: \.path, children: \.outlineChildren) { node in
                FileRowView(node: node, parentSize: root.size)
                    .tag(node.path)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPath) { oldPath, newPath in
            // When selection changes, look up the node and notify
            if let newPath, let node = root.node(atPath: newPath) {
                onSelectNode(node)
            }
        }
    }
}

private extension FileNode {
    /// Sorted lazily, one directory level at a time — `OutlineGroup` only
    /// evaluates this for nodes it's actually displaying (visible rows, plus
    /// whatever's needed to know if a collapsed row is expandable), so this
    /// never sorts more of the tree than what's on screen.
    var outlineChildren: [FileNode]? {
        children.isEmpty ? nil : children.sorted { $0.size > $1.size }
    }
}

struct FileRowView: View {
    let node: FileNode
    let parentSize: Int64

    private var fraction: Double {
        guard parentSize > 0 else { return 0 }
        return min(1, Double(node.size) / Double(parentSize))
    }

    private var displaySize: String {
        ByteFormatter.string(fromBytes: node.size)
    }

    var body: some View {
        HStack(spacing: DustEaterTheme.Spacing.md) {
            // Icon
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(node.isDirectory ? Color.accentColor : .gray)
                .frame(width: 16)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.control)
                    .lineLimit(1)

                // Mini bar chart. A `scaleEffect` transform (same pattern as
                // the disk usage bar in DiskHomeView) rather than
                // `GeometryReader`: `GeometryReader` is greedy and forces an
                // extra layout pass, which is a well-known scroll-perf cost
                // when it's inside every row of a list. `scaleEffect` is a
                // render-only transform, so it doesn't participate in
                // layout negotiation at all.
                RoundedRectangle(cornerRadius: DustEaterTheme.Radius.sm)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
                    .frame(height: 3)
            }

            Spacer(minLength: 8)

            // Size
            Text(displaySize)
                .font(DustEaterTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, DustEaterTheme.Spacing.xs)
    }
}
