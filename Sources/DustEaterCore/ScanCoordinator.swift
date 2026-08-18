import Foundation
import Observation
import Darwin

/// Drives a single directory scan and exposes its state for SwiftUI to
/// observe. Owns the running scan `Task` so a new scan (or explicit cancel)
/// can supersede an in-flight one.
///
/// Also drives the Cleanup findings scan alongside it, streaming results
/// into `findings` as they arrive rather than waiting for the tree to
/// finish - most findings don't actually need the assembled tree at all
/// (package manager caches, Xcode's fixed cache paths, simulator runtimes,
/// unused applications, and old downloads are each their own independent
/// scan), so there's no reason to gate them behind `DiskScanner`'s tree
/// walk completing. Only project-local purge targets (discovered by
/// walking the tree for `node_modules` etc.) and duplicate files genuinely
/// need the finished tree, and run once it's available - after `.finished`
/// fires, not before, so Explore is never held up by duplicate hashing.
@Observable
@MainActor
public final class ScanCoordinator {
    public private(set) var state: ScanState = .idle
    /// The node currently displayed in the treemap (can zoom into any folder).
    /// Synced with the list view's selection so they stay coordinated.
    public var zoomNode: FileNode?
    /// Duration of the completed scan in seconds
    public private(set) var scanDuration: Double = 0
    /// Set when `watcher` detects a filesystem change under the scanned
    /// root while `state == .finished`. Deliberately just a signal to
    /// prompt a manual rescan, not something reconciled into `state`
    /// automatically - see `FileSystemWatcher`'s doc comment for why.
    public private(set) var hasDetectedChanges = false
    /// The path passed to `startScan`, available immediately - independent
    /// of whether the tree has finished, so the UI can show which volume
    /// is being scanned before there's a `FileNode` to read a name from.
    public private(set) var rootPath: String?

    /// Findings discovered so far, live for the lifetime of one scan and
    /// beyond - populated during `.scanning`, still present (and still
    /// growing, as tree-dependent findings complete) once `state` reaches
    /// `.finished`, and left untouched by cancellation. This is the one
    /// place both the Scanning screen and the Cleanup screen read from, so
    /// neither has to reconcile a second, parallel findings feed.
    public private(set) var findings: [CleanupFinding] = []
    /// Finding categories whose scan hasn't completed yet.
    public private(set) var inFlightFindingIDs: Set<CleanupFindingID> = []
    /// Explore's browse-by-type index, built for free alongside the main
    /// tree scan (see `DiskScanner.scanWithTypeIndex`) - populated once
    /// `state` reaches `.finished`, empty before that and after a
    /// pre-finish cancel, same as `finishedRoot` elsewhere.
    public private(set) var typeIndex: FileTypeIndex = .empty

    private var scanTask: Task<Void, Never>?
    /// Every tree-independent finding scan started by
    /// `startFastPathFindingScans` - tracked separately from `scanTask`
    /// since they're genuinely independent top-level `Task`s, not children
    /// of it, and so aren't cancelled automatically by `scanTask?.cancel()`.
    private var fastPathTasks: [Task<Void, Never>] = []
    private var scanStartTime: DispatchTime?
    private var watcher: FileSystemWatcher?
    private let duplicateDetector = DuplicateDetector()

    public init() {}

    public func startScan(path: String) {
        scanTask?.cancel()
        fastPathTasks.forEach { $0.cancel() }
        fastPathTasks = []
        watcher = nil
        hasDetectedChanges = false
        scanStartTime = DispatchTime.now()
        scanDuration = 0
        rootPath = path
        findings = []
        inFlightFindingIDs = Set(CleanupFindingID.allCases)
        typeIndex = .empty
        state = .scanning(ScanProgressSnapshot(
            itemsScanned: 0,
            bytesScanned: 0,
            currentPath: path,
            findings: [],
            inFlightFindingIDs: inFlightFindingIDs
        ))

        startFastPathFindingScans()

        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let probeStartTime = DispatchTime.now()

            // Check the root itself before doing a full recursive scan, so
            // we can tell "doesn't exist" apart from "access denied" and
            // point the user at Full Disk Access specifically for the latter.
            switch AttrListBulkReader.probeAccess(atPath: path) {
            case 0:
                break
            case ENOENT:
                self.state = .failed("'\(path)' doesn't exist.")
                return
            case EACCES, EPERM:
                self.state = .needsFullDiskAccess(path: path)
                return
            case let other:
                self.state = .failed("Couldn't access '\(path)': \(String(cString: strerror(other)))")
                return
            }

            let probeElapsed = Double(DispatchTime.now().uptimeNanoseconds - probeStartTime.uptimeNanoseconds) / 1_000_000_000
            debugLog("📊 Probe access: \(String(format: "%.3f", probeElapsed))s")

            let scanStartTime = DispatchTime.now()
            let scanner = DiskScanner()
            let (node, typeIndex) = await scanner.scanWithTypeIndex(rootPath: path) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.applyProgress(progress)
                }
            }
            let scanElapsed = Double(DispatchTime.now().uptimeNanoseconds - scanStartTime.uptimeNanoseconds) / 1_000_000_000
            debugLog("📊 Filesystem scan: \(String(format: "%.3f", scanElapsed))s")
            self.typeIndex = typeIndex

            guard !Task.isCancelled else {
                self.inFlightFindingIDs = []
                self.state = .cancelled
                return
            }

            var mergedNode = node
            let appNodes = AppGrouper.findAppBundles(in: node)
            if !appNodes.isEmpty {
                let apps = await AppGrouper.buildAppDiskEntities(from: appNodes)
                guard !Task.isCancelled else {
                    self.inFlightFindingIDs = []
                    self.state = .cancelled
                    return
                }
                mergedNode = AppSizeMerger.mergeTrueSizes(into: node, using: apps)
            }

            // Calculate scan duration
            if let startTime = self.scanStartTime {
                let endTime = DispatchTime.now()
                self.scanDuration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                debugLog("📊 Total scan time: \(String(format: "%.3f", self.scanDuration))s")
                debugLog("📊 Items found: \(mergedNode.itemCount)")
                debugLog("📊 Total size: \(ByteFormatter.string(fromBytes: mergedNode.size))")
            }

            self.state = .finished(mergedNode)

            // Watch the original scan root, not `zoomNode` - the signal
            // needs to stay correct regardless of how deep the user has
            // zoomed in.
            self.watcher = FileSystemWatcher(path: path) { [weak self] in
                self?.hasDetectedChanges = true
            }

            // Tree-dependent findings, deliberately *after* `.finished` -
            // Explore becomes available the moment the tree is ready,
            // never held up by duplicate hashing (by far the longest-
            // running piece).
            await self.scanTreeDependentFindings(root: mergedNode)
        }
    }

    /// Stops the running scan. If the tree hadn't finished yet, `state`
    /// becomes `.cancelled` - there is no complete `FileNode` to hand over,
    /// so `.finished` would misrepresent an interrupted tree as trustworthy.
    /// If the tree *had* already finished (cancelling only cut short the
    /// slower tree-dependent finding work), `state` stays `.finished`,
    /// since that part is still legitimately complete. Either way,
    /// `findings` is never cleared - whatever was already found stays
    /// exactly as it was; only `inFlightFindingIDs` is cleared, since
    /// nothing is going to arrive for those categories now.
    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        fastPathTasks.forEach { $0.cancel() }
        fastPathTasks = []
        watcher = nil
        inFlightFindingIDs = []
        if case .scanning = state {
            state = .cancelled
        }
        // Otherwise `state` is already `.finished` (the tree completed;
        // only the slower tree-dependent finding work is being cut short)
        // or a terminal state cancel doesn't apply to - left as-is either way.
    }

    public func updateTree(_ newRoot: FileNode) {
        if case .finished = state {
            state = .finished(newRoot)
        }
    }

    /// Folds a commit's deleted paths out of `findings` without a rescan -
    /// drops an item entirely if *any* of its paths were deleted (rather
    /// than trying to patch its size), since a partially-deleted item's
    /// remaining size is no longer trustworthy without re-measuring.
    public func removeDeletedPaths(_ paths: Set<String>) {
        findings = findings.compactMap { finding -> CleanupFinding? in
            let remainingItems = finding.items.filter { item in
                item.deletablePaths.allSatisfy { !paths.contains($0) }
            }
            guard !remainingItems.isEmpty else { return nil }
            return CleanupFinding(id: finding.id, items: remainingItems)
        }
        refreshScanningSnapshot()
    }

    private func applyProgress(_ progress: ScanProgress) {
        // A cancel/new-scan may have raced ahead of this stale update.
        guard case .scanning = state else { return }

        state = .scanning(ScanProgressSnapshot(
            itemsScanned: progress.itemsScanned,
            bytesScanned: progress.bytesScanned,
            currentPath: progress.currentPath,
            findings: findings,
            inFlightFindingIDs: inFlightFindingIDs
        ))
    }

    // MARK: - Findings

    /// Starts every finding scan that needs nothing from the tree scan at
    /// all - package manager caches and Xcode's fixed cache paths and
    /// simulator runtimes (`PurgeScanner.fixedPathCategories`), unused
    /// applications (`AppManagerScanner.scanInstalledApps`), and old
    /// downloads (a direct scan of `~/Downloads`, rather than waiting to
    /// find it inside the main tree). Each is a genuinely independent
    /// top-level `Task` - not a child of `scanTask` - so they keep running,
    /// and keep publishing into `findings`, even while the much larger
    /// full-disk tree walk is still in progress.
    private func startFastPathFindingScans() {
        let homeDirectory = NSHomeDirectory()

        fastPathTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let categories = await PurgeScanner.fixedPathCategories()
            guard !Task.isCancelled else { return }
            if let f = CleanupFindingsBuilder.packageManagerCaches(from: categories) { self.mergeFinding(f) }
            if let f = CleanupFindingsBuilder.xcodeBuildArtifacts(from: categories) { self.mergeFinding(f) }
            if let f = CleanupFindingsBuilder.simulatorRuntimes(from: categories) { self.mergeFinding(f) }
            // Simulator runtimes are entirely fixed-path (no tree-dependent
            // component), so this pass is the whole story for that finding.
            // Package manager caches / Xcode build artifacts are
            // deliberately *not* marked complete here - `PurgeCatalog.
            // discover` (project-local artifacts) can still add more items
            // to them once the tree finishes; `scanTreeDependentFindings`
            // marks those two complete.
            self.markFindingComplete(.simulatorRuntimes)
        })

        fastPathTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let installed = await AppManagerScanner.scanInstalledApps()
            guard !Task.isCancelled else { return }
            if let f = CleanupFindingsBuilder.unusedApplications(installed: installed) { self.mergeFinding(f) }
            self.markFindingComplete(.unusedApplications)
        })

        fastPathTasks.append(Task { @MainActor [weak self] in
            guard let self else { return }
            let downloadsPath = (homeDirectory as NSString).appendingPathComponent("Downloads")
            let downloadsNode = await DiskScanner().scan(rootPath: downloadsPath)
            guard !Task.isCancelled else { return }
            if let f = await CleanupFindingsBuilder.oldDownloads(in: downloadsNode, homeDirectory: homeDirectory) {
                self.mergeFinding(f)
            }
            self.markFindingComplete(.oldDownloads)
        })
    }

    /// Runs once the tree finishes: project-local purge targets
    /// (`node_modules`, Cargo `target`, etc. - `PurgeCatalog.discover`
    /// needs the assembled tree to walk) join whatever
    /// `fixedPathCategories()` already found, and duplicate files
    /// (`DuplicateDetector`, by far the longest-running piece) run last.
    private func scanTreeDependentFindings(root: FileNode) async {
        guard !Task.isCancelled else { return }
        let discovered = PurgeScanner.projectLocalCategories(in: root)
        if let f = CleanupFindingsBuilder.packageManagerCaches(from: discovered) { mergeFinding(f) }
        if let f = CleanupFindingsBuilder.xcodeBuildArtifacts(from: discovered) { mergeFinding(f) }
        markFindingComplete(.packageManagerCaches)
        markFindingComplete(.xcodeBuildArtifacts)
        markFindingComplete(.simulatorRuntimes)

        guard !Task.isCancelled else { return }
        let duplicateSets = await duplicateDetector.findDuplicates(in: root)
        guard !Task.isCancelled else { return }
        if let f = CleanupFindingsBuilder.duplicateFiles(from: duplicateSets) { mergeFinding(f) }
        markFindingComplete(.duplicateFiles)
    }

    /// Unions `new` into `findings` by item id rather than replacing
    /// whatever's already there for the same `CleanupFindingID` - the only
    /// way two passes can touch the same finding (package manager caches/
    /// Xcode build artifacts, fixed-path then tree-discovered) is additive,
    /// never a correction, so nothing already published is ever removed.
    private func mergeFinding(_ new: CleanupFinding) {
        var byID = Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) })
        if let existing = byID[new.id] {
            var itemsByID = Dictionary(uniqueKeysWithValues: existing.items.map { ($0.id, $0) })
            for item in new.items { itemsByID[item.id] = item }
            byID[new.id] = CleanupFinding(id: new.id, items: Array(itemsByID.values))
        } else {
            byID[new.id] = new
        }
        findings = CleanupFindingsBuilder.rank(CleanupFindingID.allCases.compactMap { byID[$0] })
        refreshScanningSnapshot()
    }

    private func markFindingComplete(_ id: CleanupFindingID) {
        inFlightFindingIDs.remove(id)
        refreshScanningSnapshot()
    }

    /// Keeps the current `.scanning` snapshot's `findings`/
    /// `inFlightFindingIDs` in sync immediately, rather than waiting for
    /// `DiskScanner`'s next throttled progress tick (up to 100ms away, or
    /// never, if the tree scan already finished while finding scans are
    /// still running) - a no-op in any other state.
    private func refreshScanningSnapshot() {
        guard case .scanning(let snapshot) = state else { return }
        state = .scanning(ScanProgressSnapshot(
            itemsScanned: snapshot.itemsScanned,
            bytesScanned: snapshot.bytesScanned,
            currentPath: snapshot.currentPath,
            findings: findings,
            inFlightFindingIDs: inFlightFindingIDs
        ))
    }
}

/// Timing/diagnostic logging, compiled out entirely in Release builds.
private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
