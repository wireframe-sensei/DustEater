import Foundation

/// The outermost directory that owns a dependency/build directory - the
/// unit Code & Projects' folder rows actually group around. See
/// `ProjectDetector.projectRoot(forDirectoryContaining:in:)`.
public struct ProjectRoot: Sendable, Equatable, Hashable {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// Finds the project a dependency/build directory belongs to, entirely
/// in memory against the already-scanned tree - no second directory walk,
/// no second permission prompt, the same reasoning `PurgeCatalog.discover`
/// already documents for reading sizes straight off scanned `FileNode`s.
public enum ProjectDetector {
    /// A `.git` directory, or a top-level manifest naming this directory as
    /// a package/project root. Any one is sufficient. `*.xcodeproj` is
    /// matched by suffix (its name isn't fixed), everything else by exact
    /// name.
    private static let markerNames: Set<String> = [
        ".git", "package.json", "Cargo.toml", "go.mod", "Package.swift", "pyproject.toml",
    ]

    private static func hasMarker(_ node: FileNode) -> Bool {
        node.children.contains { child in
            markerNames.contains(child.name) || child.name.hasSuffix(".xcodeproj")
        }
    }

    /// Walks from `root` down toward `directoryPath`, returning the
    /// *outermost* ancestor (closest to `root`) that carries a project
    /// marker - so a monorepo's own root (marked by `.git`, say) always
    /// wins over an individual package's own nested `package.json`, since
    /// the walk checks `root` and each descendant in order and stops at
    /// the first match. `nil` when no directory from `root` down to
    /// `directoryPath` itself carries a marker - the caller decides the
    /// fallback (see `ProjectBrowser.loadProjectSummaries`).
    ///
    /// - Parameter directoryPath: a directory *containing* the dependency
    ///   directory in question (its parent), not the dependency directory
    ///   itself - a dependency tree's own contents are never checked for
    ///   markers, only its ancestors.
    public static func projectRoot(forDirectoryContaining directoryPath: String, in root: FileNode) -> ProjectRoot? {
        guard directoryPath == root.path || directoryPath.hasPrefix(root.path + "/") else { return nil }

        if hasMarker(root) {
            return ProjectRoot(path: root.path, name: root.name)
        }
        guard directoryPath != root.path else { return nil }

        var relative = directoryPath.dropFirst(root.path.count)
        if relative.first == "/" { relative = relative.dropFirst() }

        var current = root
        for component in relative.split(separator: "/") {
            guard let next = current.children.first(where: { $0.name == component }) else { return nil }
            current = next
            if hasMarker(current) {
                return ProjectRoot(path: current.path, name: current.name)
            }
        }
        return nil
    }
}
