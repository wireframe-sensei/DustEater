import Foundation
import Observation

/// Progress payload for the `.measuring` phase of `PurgeScanner.measure`.
/// There is no percentage here on purpose: at most ~30 catalog entries ever
/// need a fallback scan, so a running "N of M" count plus the item currently
/// being measured is more honest than a smoothed progress bar would be.
public struct PurgeScanProgress: Sendable {
    public enum Phase: Sendable {
        /// Matching project-local build artifacts against the scanned tree.
        case discoveringProjects
        /// Reading sizes straight off the scanned tree for catalog paths it
        /// already contains - no disk I/O.
        case resolvingFromTree
        /// Falling back to a targeted scan for catalog paths the tree
        /// missed (outside the scanned root, or the scan didn't cover it).
        case measuring
    }

    public let phase: Phase
    public let targetsCompleted: Int
    public let totalTargets: Int
    public let currentTitle: String

    public init(phase: Phase, targetsCompleted: Int, totalTargets: Int, currentTitle: String) {
        self.phase = phase
        self.targetsCompleted = targetsCompleted
        self.totalTargets = totalTargets
        self.currentTitle = currentTitle
    }
}

public enum PurgeScanState: Sendable {
    case idle
    case scanning(measured: [PurgeTarget], progress: PurgeScanProgress)
    /// A real, distinct state from `.scanning` - an empty array here means
    /// nothing on this Mac matched the catalog, not that measuring is still
    /// running. See CLAUDE.md's "a loading state needs a way to tell
    /// still-loading apart from loaded-and-found-nothing."
    case loaded([PurgeCategory])
    case failed(String)
}

/// Sizes the developer/creative purge catalog against an already-scanned
/// tree, falling back to bounded targeted scans for the catalog paths that
/// tree doesn't already contain.
///
/// Follows the house `@Observable @MainActor` service pattern used by
/// `AppManagerScanner`, `FileInspectorService`, and `DiskTelemetryService`:
/// one cancel-and-replace `Task`, a synchronous void entry point, and
/// `guard !Task.isCancelled` after every await.
@Observable
@MainActor
public final class PurgeScanner {
    public private(set) var state: PurgeScanState = .idle

    private var task: Task<Void, Never>?

    public init() {}

    public func measure(in root: FileNode) {
        task?.cancel()
        state = .scanning(
            measured: [],
            progress: PurgeScanProgress(phase: .discoveringProjects, targetsCompleted: 0, totalTargets: 0, currentTitle: "")
        )

        task = Task { @MainActor [weak self] in
            guard let self else { return }

            // Phase 1a: project-local targets, discovered entirely in
            // memory from the tree already in hand.
            var measured = PurgeCatalog.discover(in: root)
            guard !Task.isCancelled else { return }

            // Phase 1b: fixed catalog paths the scanned tree already
            // contains - free, zero I/O, since the size is already on the
            // node.
            let definitions = PurgeCatalog.definitions()
            var misses: [PurgeTargetDefinition] = []
            for definition in definitions {
                if let node = root.node(atPath: definition.path) {
                    measured.append(PurgeTarget(definition: definition, sizeBytes: node.size))
                } else {
                    misses.append(definition)
                }
            }

            let totalTargets = measured.count + misses.count
            guard !Task.isCancelled else { return }
            self.state = .scanning(
                measured: measured,
                progress: PurgeScanProgress(
                    phase: .resolvingFromTree,
                    targetsCompleted: measured.count,
                    totalTargets: totalTargets,
                    currentTitle: ""
                )
            )

            guard !misses.isEmpty else {
                self.state = .loaded(Self.grouped(measured))
                return
            }

            // Phase 2: bounded fallback scans for everything the tree
            // missed - a home or whole-disk scan already resolves most of
            // the catalog in phase 1, so this is typically under 10 items.
            measured = await self.measure(misses, addingTo: measured, totalTargets: totalTargets)

            guard !Task.isCancelled else { return }
            self.state = .loaded(Self.grouped(measured))
        }
    }

    /// Filters a target out of the loaded categories after it's been
    /// deleted, recomputing each affected category's totals - mirrors
    /// `FileInspectorService.removeDeletedPaths`. A no-op in any state other
    /// than `.loaded`.
    public func removeDeletedPaths(_ paths: Set<String>) {
        guard case .loaded(let categories) = state else { return }
        let updated = categories.compactMap { category -> PurgeCategory? in
            let remaining = category.targets.filter { !paths.contains($0.path) }
            guard !remaining.isEmpty else { return nil }
            return PurgeCategory(categoryID: category.categoryID, targets: remaining)
        }
        state = .loaded(updated)
    }

    /// A ~4-wide sliding window over the misses, chosen inline here rather
    /// than promoting `DuplicateDetector.withConcurrentTasks` to shared
    /// infrastructure on its second use (CLAUDE.md's Rule of Three). The
    /// shapes differ anyway: that one slides across tens of thousands of
    /// leaf file reads, while this handles at most a couple dozen misses,
    /// each of which may itself launch an unbounded `DiskScanner` fan-out -
    /// ten of those running at once would be ten unbounded fan-outs at
    /// once, so the window still needs a real cap, just a small one.
    private func measure(
        _ misses: [PurgeTargetDefinition],
        addingTo alreadyMeasured: [PurgeTarget],
        totalTargets: Int
    ) async -> [PurgeTarget] {
        var measured = alreadyMeasured
        let maxConcurrent = 4

        await withTaskGroup(of: PurgeTarget?.self) { group in
            var iterator = misses.makeIterator()

            func addNext() {
                guard let definition = iterator.next() else { return }
                group.addTask { await Self.measureOne(definition) }
            }

            for _ in 0..<maxConcurrent { addNext() }

            while let result = await group.next() {
                guard !Task.isCancelled else { break }

                if let target = result {
                    measured.append(target)
                }
                self.state = .scanning(
                    measured: measured,
                    progress: PurgeScanProgress(
                        phase: .measuring,
                        targetsCompleted: measured.count,
                        totalTargets: totalTargets,
                        currentTitle: result?.definition.title ?? ""
                    )
                )
                addNext()
            }
        }

        return measured
    }

    /// Cheapest-check-first: `fileExists` (most catalog misses on a
    /// non-developer Mac simply don't exist) and a symlink check share one
    /// `BlockingIO.run` call, so a genuine miss never reaches `DiskScanner`
    /// at all. Homebrew's cache is the concrete symlink case - some setups
    /// point it at `/opt/homebrew`, which `FileOperations.isSystemProtected`
    /// blocks by prefix, so scanning through the link would report a size
    /// nothing here could ever actually delete.
    private static func measureOne(_ definition: PurgeTargetDefinition) async -> PurgeTarget? {
        let shouldScan = (try? await BlockingIO.run {
            let path = definition.path
            guard FileManager.default.fileExists(atPath: path) else { return false }
            let isSymlink = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            return !isSymlink
        }) ?? false
        guard shouldScan else { return nil }

        let node = await DiskScanner().scan(rootPath: definition.path)
        guard !Task.isCancelled else { return nil }
        return PurgeTarget(definition: definition, sizeBytes: node.size)
    }

    private static func grouped(_ targets: [PurgeTarget]) -> [PurgeCategory] {
        PurgeCategoryID.allCases.compactMap { categoryID in
            let categoryTargets = targets.filter { $0.definition.categoryID == categoryID }
            guard !categoryTargets.isEmpty else { return nil }
            return PurgeCategory(categoryID: categoryID, targets: categoryTargets.sorted { $0.sizeBytes > $1.sizeBytes })
        }
    }
}
