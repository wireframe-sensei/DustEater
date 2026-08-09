import Foundation

/// Folds each `AppDiskEntity`'s hidden storage back into a scanned tree.
///
/// Rather than silently inflating a `.app` node's `size` (which would break
/// the invariant that a directory's size equals the sum of its children's
/// sizes - something both the list view and the treemap in later phases
/// rely on), this adds one synthetic "Associated App Data" child per app,
/// broken down by category. The `.app` node's `size` still grows to the
/// true total, but it stays honest about where the extra bytes come from.
public enum AppSizeMerger {
    public static func mergeTrueSizes(into root: FileNode, using apps: [AppDiskEntity]) -> FileNode {
        guard !apps.isEmpty else { return root }
        let entitiesByAppPath = Dictionary(uniqueKeysWithValues: apps.map { ($0.appPath, $0) })
        return rewrite(root, entitiesByAppPath: entitiesByAppPath)
    }

    private static func rewrite(_ node: FileNode, entitiesByAppPath: [String: AppDiskEntity]) -> FileNode {
        var updated = node
        updated.children = node.children.map { rewrite($0, entitiesByAppPath: entitiesByAppPath) }

        guard let entity = entitiesByAppPath[node.path], !entity.relatedItems.isEmpty else {
            return updated
        }

        let associatedDataNode = FileNode(
            name: "Associated App Data",
            path: node.path + "/\u{0}associated-app-data",
            size: entity.relatedTotalSize,
            isDirectory: true,
            children: entity.relatedItems.map { item in
                FileNode(name: item.category.rawValue, path: item.path, size: item.size, isDirectory: true)
            },
            itemCount: entity.relatedItems.count + 1
        )

        updated.children.append(associatedDataNode)
        updated.size = entity.trueTotalSize
        updated.itemCount += associatedDataNode.itemCount
        return updated
    }
}
