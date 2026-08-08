import SwiftUI
import DustEaterCore

// Reference type to track expanded paths (better for SwiftUI state detection)
class ExpandedPathsManager: ObservableObject {
    @Published var expandedPaths: Set<String> = []

    func isExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func toggle(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func expand(_ path: String) {
        expandedPaths.insert(path)
    }

    func expandPath(_ path: String) {
        // Expand all parents of this path
        var pathComponents = path.split(separator: "/").map(String.init)
        pathComponents.removeLast()

        var currentPath = ""
        for component in pathComponents {
            currentPath.append("/")
            currentPath.append(component)
            expandedPaths.insert(currentPath)
        }
    }
}

struct FileTreeListView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void
    @StateObject private var expandedManager = ExpandedPathsManager()

    var body: some View {
        List(selection: $selectedPath) {
            TreeNodeView(
                node: root,
                isRoot: true,
                selectedPath: $selectedPath,
                expandedManager: expandedManager,
                onSelectNode: onSelectNode,
                rootSize: root.size
            )
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPath) { _, newPath in
            if let newPath {
                // Expand all parent paths
                expandedManager.expandPath(newPath)

                // Find and notify the node
                if let node = root.find(path: newPath) {
                    onSelectNode(node)
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
    @ObservedObject var expandedManager: ExpandedPathsManager
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
                    expandedManager: expandedManager,
                    onSelectNode: onSelectNode,
                    rootSize: rootSize
                )
            }
        } else if node.isDirectory && !node.children.isEmpty {
            // Directory with children: use DisclosureGroup
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedManager.isExpanded(node.path) },
                    set: { _ in expandedManager.toggle(node.path) }
                )
            ) {
                ForEach(node.children, id: \.path) { child in
                    TreeNodeView(
                        node: child,
                        isRoot: false,
                        selectedPath: $selectedPath,
                        expandedManager: expandedManager,
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
