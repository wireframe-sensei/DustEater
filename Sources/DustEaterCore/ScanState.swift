import Foundation

/// A lightweight, frequently-updated snapshot of in-progress scan progress.
/// Kept separate from `ScanProgress` (the scanner's own callback payload)
/// so `ScanCoordinator` can throttle how often the UI-facing state actually
/// changes without touching the scanner itself.
///
/// Carries the Cleanup findings discovered so far alongside the raw
/// tree-scan numbers, in the same `CleanupFinding`/`CleanupItem` shape the
/// Cleanup screen renders once the scan finishes - not a separate partial-
/// results type. Most findings don't actually need the assembled tree
/// (`ScanCoordinator` runs them as independent scans concurrently with the
/// tree walk), so there's real data to show here well before `itemsScanned`
/// approaches its final count.
public struct ScanProgressSnapshot: Sendable, Equatable {
    public let itemsScanned: Int
    public let bytesScanned: Int64
    public let currentPath: String
    /// Findings discovered so far, already ranked largest-reclaimable-first.
    /// Monotonic for the lifetime of one scan: a finding, once published,
    /// is only ever added to (more items) or joined by a new finding -
    /// never shrunk or removed - so a bound UI's total can only climb.
    public let findings: [CleanupFinding]
    /// Finding categories whose own scan hasn't completed yet - what the
    /// Scanning screen's in-flight row names.
    public let inFlightFindingIDs: Set<CleanupFindingID>

    public init(
        itemsScanned: Int,
        bytesScanned: Int64,
        currentPath: String,
        findings: [CleanupFinding],
        inFlightFindingIDs: Set<CleanupFindingID>
    ) {
        self.itemsScanned = itemsScanned
        self.bytesScanned = bytesScanned
        self.currentPath = currentPath
        self.findings = findings
        self.inFlightFindingIDs = inFlightFindingIDs
    }

    public var reclaimableBytesFound: Int64 {
        findings.reduce(0) { $0 + $1.reclaimableBytes }
    }
}

/// The state of a directory scan, as observed by the UI.
public enum ScanState: Sendable, Equatable {
    case idle
    case scanning(ScanProgressSnapshot)
    case finished(FileNode)
    /// The scan was cancelled before the tree finished, so there is no
    /// complete `FileNode` to hand over - `.finished` would misrepresent an
    /// interrupted tree as a trustworthy one. Distinct from `.idle`, which
    /// means "nothing has happened yet": a cancelled scan has real,
    /// retained findings behind it (`ScanCoordinator.findings`), and the UI
    /// should keep showing them, not reset to a blank slate. Cancelling
    /// *after* the tree already finished (during the slower tree-dependent
    /// finding work, e.g. duplicate hashing) does not produce this state -
    /// the tree is legitimately complete by then, so `state` stays
    /// `.finished` and only stops accumulating further findings.
    case cancelled
    /// The root path itself couldn't be opened due to a permission/TCC
    /// denial - the scan never started. Surfaced separately from `.failed`
    /// so the UI can offer a "grant Full Disk Access" call to action
    /// instead of a generic error message.
    case needsFullDiskAccess(path: String)
    case failed(String)
}
