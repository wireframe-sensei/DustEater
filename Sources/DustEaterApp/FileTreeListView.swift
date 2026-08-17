import SwiftUI
import DustEaterCore

struct FileTreeListView: View {
    let root: FileNode
    @Binding var selectedPath: String?
    let onSelectNode: (FileNode) -> Void
    // Owned by `CleanupShellView` now, not here - the delete alert (and the
    // toolbar actions that trigger it) live at that level, and `deleteItem`
    // there needs to prune this set. See Cleanup/CleanupShellView.swift.
    @Binding var expandedPaths: Set<String>

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedPath) {
                ForEach(root.outlineChildren ?? [], id: \.path) { node in
                    FileOutlineRow(
                        node: node,
                        parentSize: root.size,
                        expandedPaths: $expandedPaths
                    )
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPath) { oldPath, newPath in
                guard let newPath else { return }
                if let node = root.node(atPath: newPath) {
                    onSelectNode(node)
                }
                reveal(newPath, proxy: proxy)
            }
        }
    }

    /// Expands every ancestor branch of `path` that isn't already open, then
    /// scrolls the row into view. `scrollTo` is a silent no-op for a row
    /// inside a branch that was just expanded - the `List` hasn't rebuilt to
    /// materialize it yet - so when expansion was actually needed, this
    /// yields a runloop turn before scrolling. When the row was already
    /// visible, it scrolls immediately with no delay.
    private func reveal(_ path: String, proxy: ScrollViewProxy) {
        let needed = Set(root.ancestorPaths(toDescendantAtPath: path))
        let alreadyOpen = needed.isSubset(of: expandedPaths)

        if !alreadyOpen {
            withAnimation { expandedPaths.formUnion(needed) }
        }

        guard !alreadyOpen else {
            withAnimation { proxy.scrollTo(path, anchor: .center) }
            return
        }

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation { proxy.scrollTo(path, anchor: .center) }
        }
    }
}

/// Recursive sidebar row, replacing `OutlineGroup`. `OutlineGroup` owns its
/// disclosure state internally with no way to open a branch from code, which
/// makes "select this node and reveal it in the tree" impossible to build on
/// top of it. This owns expansion via `expandedPaths` instead, so a selection
/// change can expand exactly the branches it needs.
struct FileOutlineRow: View {
    let node: FileNode
    let parentSize: Int64
    @Binding var expandedPaths: Set<String>

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(node.path) },
            set: { isOpen in
                if isOpen {
                    expandedPaths.insert(node.path)
                } else {
                    expandedPaths.remove(node.path)
                }
            }
        )
    }

    var body: some View {
        if let children = node.outlineChildren {
            DisclosureGroup(isExpanded: isExpanded) {
                // Load-bearing, not defensive: without this guard the
                // recursion builds (and sorts) every level of the subtree as
                // soon as it exists, even while collapsed. This restores the
                // one-level-at-a-time laziness `OutlineGroup` gave for free -
                // see the comment on `outlineChildren` below.
                if expandedPaths.contains(node.path) {
                    ForEach(children, id: \.path) { child in
                        FileOutlineRow(
                            node: child,
                            parentSize: parentSize,
                            expandedPaths: $expandedPaths
                        )
                    }
                }
            } label: {
                FileRowView(node: node, parentSize: parentSize)
            }
            .tag(node.path)
        } else {
            FileRowView(node: node, parentSize: parentSize)
                .tag(node.path)
        }
    }
}

private extension FileNode {
    /// Sorted lazily, one directory level at a time - `OutlineGroup` only
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
        // No per-row menu here - a macOS `Menu` always renders as a bordered
        // pull-down button with a menu indicator, regardless of the frame
        // it's given, and at sidebar width that button alone crushed every
        // name down to two or three characters. Actions for the selected
        // item live in the window toolbar instead (see CleanupShellView) -
        // a genuinely native pattern (Finder, Mail, Photos all work this
        // way), and it costs this row nothing.
        HStack(spacing: DustEaterTheme.Spacing.sm) {
            // Icon
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.control)
                .imageScale(.small)
                .foregroundStyle(node.isDirectory ? Color.accentColor : .gray)
                .frame(width: 16)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.control)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .help(node.name)

                Capsule()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
                    .frame(height: 3)
            }

            Spacer(minLength: DustEaterTheme.Spacing.sm)

            // Size - no fixed width column: it can't align across varying
            // disclosure indentation anyway, so a fixed frame only cost
            // width the name needed more.
            Text(displaySize)
                .font(DustEaterTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .padding(.vertical, DustEaterTheme.Spacing.xs)
    }
}
