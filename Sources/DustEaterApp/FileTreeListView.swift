import SwiftUI
import DustEaterCore

struct FileTreeListView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void

    var body: some View {
        List(selection: $selectedPath) {
            OutlineGroup(root.children, id: \.path, children: \.outlineChildren) { node in
                FileRowView(node: node, parentSize: root.size)
                    .tag(node.path)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPath) { oldPath, newPath in
            // When selection changes, find the node and notify
            if let newPath, let node = root.find(path: newPath) {
                onSelectNode(node)
            }
        }
    }
}

private extension FileNode {
    var outlineChildren: [FileNode]? {
        children.isEmpty ? nil : children
    }

    func find(path: String) -> FileNode? {
        if self.path == path { return self }
        for child in children {
            if let found = child.find(path: path) {
                return found
            }
        }
        return nil
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
                .foregroundStyle(node.isDirectory ? .blue : .gray)
                .frame(width: 16)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(DustEaterTheme.Typography.body)
                    .lineLimit(1)

                // Mini bar chart
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: DustEaterTheme.Radius.sm)
                        .fill(.blue.opacity(0.2))
                        .frame(width: geometry.size.width * fraction, alignment: .leading)
                }
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
