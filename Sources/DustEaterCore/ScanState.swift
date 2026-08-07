import Foundation

/// A lightweight, frequently-updated snapshot of in-progress scan progress.
/// Kept separate from `ScanProgress` (the scanner's own callback payload)
/// so `ScanCoordinator` can throttle how often the UI-facing state actually
/// changes without touching the scanner itself.
public struct ScanProgressSnapshot: Sendable, Equatable {
    public let itemsScanned: Int
    public let bytesScanned: Int64
    public let currentPath: String
}

/// The state of a directory scan, as observed by the UI.
public enum ScanState: Sendable, Equatable {
    case idle
    case scanning(ScanProgressSnapshot)
    case finished(FileNode)
    /// The root path itself couldn't be opened due to a permission/TCC
    /// denial — the scan never started. Surfaced separately from `.failed`
    /// so the UI can offer a "grant Full Disk Access" call to action
    /// instead of a generic error message.
    case needsFullDiskAccess(path: String)
    case failed(String)
}
