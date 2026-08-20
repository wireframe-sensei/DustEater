import Foundation

/// One dependency/build directory, fully detailed as a child row inside a
/// `ProjectSummary` - `DiskScanner` already knows the path, name, and full
/// recursive size (`FileTypeIndexEntry`); the only thing fetched on demand
/// here is the folder's own last-used date, the same
/// `AppLastUsedDateProvider`-backed signal `LargeFileFinder`/
/// `FileTypeBrowser` already use for files, reused generically since it's
/// path-based, not file-based.
public struct DependencyDirectoryDetail: Sendable, Identifiable, Equatable {
    public var id: String { path }

    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let detail: String
    public let rebuildCommand: String
    public let lastOpenedDate: Date?

    public init(
        path: String,
        name: String,
        sizeBytes: Int64,
        detail: String,
        rebuildCommand: String,
        lastOpenedDate: Date?
    ) {
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.detail = detail
        self.rebuildCommand = rebuildCommand
        self.lastOpenedDate = lastOpenedDate
    }
}

/// One project - a `.git` repository, or a directory rooted by a top-level
/// `package.json`/`Cargo.toml`/`go.mod`/`Package.swift`/`pyproject.toml`/
/// `*.xcodeproj` (see `ProjectDetector`) - carrying every dependency/build
/// directory `DiskScanner` found underneath it. This is the row Code &
/// Projects actually shows; the dependency directories are its expandable
/// children, not top-level rows themselves - a monorepo with a
/// `node_modules` per package is one project, not one row per package.
public struct ProjectSummary: Sendable, Identifiable, Equatable {
    public var id: String { rootPath }

    public let rootPath: String
    public let name: String
    /// The project directory's own full recursive size, read directly off
    /// the same scanned `FileNode` the sidebar treemap renders from - not
    /// derived by summing `children`, so it's guaranteed to match the
    /// treemap figure for this exact path, and correctly includes
    /// whatever the project contains beyond its dependency directories
    /// (source files, assets, anything else).
    public let totalSizeBytes: Int64
    public let lastOpenedDate: Date?
    /// Dependency/build directories found inside this project, largest
    /// first. Never empty - a project with none wouldn't have been
    /// discovered in the first place (see `ProjectBrowser.loadProjectSummaries`).
    public let children: [DependencyDirectoryDetail]

    public init(
        rootPath: String,
        name: String,
        totalSizeBytes: Int64,
        lastOpenedDate: Date?,
        children: [DependencyDirectoryDetail]
    ) {
        self.rootPath = rootPath
        self.name = name
        self.totalSizeBytes = totalSizeBytes
        self.lastOpenedDate = lastOpenedDate
        self.children = children
    }

    /// Sum of just the dependency/build directories - what a rebuild would
    /// actually get back, as distinct from `totalSizeBytes` (the whole
    /// project, source files and all).
    public var reclaimableBytes: Int64 {
        children.reduce(0) { $0 + $1.sizeBytes }
    }

    /// "2.8 GB in 4 node_modules - rebuild with npm install" when every
    /// child is the same kind of directory (the common case); a shorter,
    /// less specific line when a project mixes more than one kind, since
    /// there's no single rebuild command left to name.
    public var reclaimableSummary: String {
        let byName = Dictionary(grouping: children, by: \.name)
        let bytesString = ByteFormatter.string(fromBytes: reclaimableBytes)
        if byName.count == 1, let name = byName.keys.first, let commandItems = byName[name] {
            let commands = Set(commandItems.map(\.rebuildCommand))
            if let command = commands.first, commands.count == 1 {
                return "\(bytesString) in \(commandItems.count) \(name) - rebuild with \(command)"
            }
        }
        let kinds = byName.keys.sorted().joined(separator: ", ")
        return "\(bytesString) across \(children.count) folders (\(kinds))"
    }
}

/// Groups the type index's `isDependencyDirectory` entries into one
/// `ProjectSummary` per detected project, and turns the loose, non-project
/// `.codeAndProjects` entries into the flat file list that sits alongside
/// them - the two halves of what `CodeProjectsDetailView` shows.
public enum ProjectBrowser {
    public static func loadProjectSummaries(
        for entries: [FileTypeIndexEntry],
        root: FileNode,
        lastUsedDateProvider: @escaping @Sendable (String) async -> Date? = LargeFileFinder.defaultLastUsedDateProvider
    ) async -> [ProjectSummary] {
        let dependencyEntries = entries.filter(\.isDependencyDirectory)
        guard !dependencyEntries.isEmpty else { return [] }

        // Group first, entirely synchronously - only afterward does each
        // *project* (not each dependency directory) need a last-used-date
        // lookup, which is the expensive part.
        var childrenByRoot: [ProjectRoot: [FileTypeIndexEntry]] = [:]
        for entry in dependencyEntries {
            let parentPath = (entry.path as NSString).deletingLastPathComponent
            let resolvedRoot = ProjectDetector.projectRoot(forDirectoryContaining: parentPath, in: root)
                // No marker anywhere up to the scan root - fall back to the
                // dependency directory's own parent, so it still surfaces
                // as a (single-child) project rather than silently
                // disappearing.
                ?? ProjectRoot(path: parentPath, name: (parentPath as NSString).lastPathComponent)
            childrenByRoot[resolvedRoot, default: []].append(entry)
        }

        var summaries: [ProjectSummary] = []
        for (projectRoot, entries) in childrenByRoot {
            var children: [DependencyDirectoryDetail] = []
            for entry in entries {
                guard let info = DependencyDirectoryCatalog.editorialInfo(forName: entry.name) else { continue }
                let lastOpenedDate = await lastUsedDateProvider(entry.path)
                children.append(
                    DependencyDirectoryDetail(
                        path: entry.path,
                        name: entry.name,
                        sizeBytes: entry.sizeBytes,
                        detail: info.detail,
                        rebuildCommand: info.rebuildCommand,
                        lastOpenedDate: lastOpenedDate
                    )
                )
            }
            guard !children.isEmpty else { continue }
            children.sort { $0.sizeBytes > $1.sizeBytes }

            let lastOpenedDate = await lastUsedDateProvider(projectRoot.path)
            // The project's own recursive size, read straight off the
            // scanned tree - the same node the sidebar treemap renders
            // from, not a sum of `children`, so this always matches the
            // treemap for this exact path.
            let totalSizeBytes = root.node(atPath: projectRoot.path)?.size
                ?? children.reduce(0) { $0 + $1.sizeBytes }

            summaries.append(
                ProjectSummary(
                    rootPath: projectRoot.path,
                    name: projectRoot.name,
                    totalSizeBytes: totalSizeBytes,
                    lastOpenedDate: lastOpenedDate,
                    children: children
                )
            )
        }

        return summaries.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }
}
