import SwiftUI
import DustEaterCore

struct FileTreeListView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void
    @State private var expandedPaths: Set<String> = []

    var body: some View {
        List(selection: $selectedPath) {
            TreeNodeView(
                node: root,
                isRoot: true,
                selectedPath: $selectedPath,
                expandedPaths: $expandedPaths,
                onSelectNode: onSelectNode,
                rootSize: root.size
            )
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPath) { oldPath, newPath in
            // When selection changes, expand all parent folders
            if let newPath {
                print("🔍 FileTreeListView selection changed to: \(newPath)")

                // Add all parent paths to expandedPaths
                let pathComponents = newPath.split(separator: "/", omittingEmptySubsequences: true)
                var currentPath = ""
                for component in pathComponents.dropLast() {
                    currentPath.append("/")
                    currentPath.append(contentsOf: component)
                    expandedPaths.insert(currentPath)
                }

                // Find and notify the node
                if let node = root.find(path: newPath) {
                    print("🔍 Found node, calling onSelectNode")
                    onSelectNode(node)
                } else {
                    print("🔍 Node not found for path: \(newPath)")
                }
            }
        }
    }
}

// Recursive tree node view with expansion control
struct TreeNodeView: View {
    let node: FileNode
    let isRoot: Bool
    @Binding var selectedPath: String?
    @Binding var expandedPaths: Set<String>
    let onSelectNode: (FileNode) -> Void
    let rootSize: Int64

    var body: some View {
        if isRoot {
            // Root node: show children directly
            ForEach(node.children, id: \.path) { child in
                TreeNodeView(
                    node: child,
                    isRoot: false,
                    selectedPath: $selectedPath,
                    expandedPaths: $expandedPaths,
                    onSelectNode: onSelectNode,
                    rootSize: rootSize
                )
            }
        } else if node.isDirectory && !node.children.isEmpty {
            // Directory with children: use DisclosureGroup
            let isExpanded = Binding(
                get: { expandedPaths.contains(node.path) },
                set: { newValue in
                    if newValue {
                        expandedPaths.insert(node.path)
                    } else {
                        expandedPaths.remove(node.path)
                    }
                }
            )

            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children, id: \.path) { child in
                    TreeNodeView(
                        node: child,
                        isRoot: false,
                        selectedPath: $selectedPath,
                        expandedPaths: $expandedPaths,
                        onSelectNode: onSelectNode,
                        rootSize: rootSize
                    )
                }
            } label: {
                FileRowView(node: node, parentSize: rootSize)
                    .tag(node.path)
            }
        } else {
            // Leaf node or file
            FileRowView(node: node, parentSize: rootSize)
                .tag(node.path)
        }
    }
}

private extension FileNode {
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
