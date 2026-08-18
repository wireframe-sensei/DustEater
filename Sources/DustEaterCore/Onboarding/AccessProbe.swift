import Foundation

/// Detects Full Disk Access without ever telling the user to relaunch.
/// `ScanCoordinator` already probes a specific scan root the same way
/// (`AttrListBulkReader.probeAccess`, used to distinguish "doesn't exist"
/// from "access denied" before starting a scan) - this is the same
/// technique aimed at a fixed, always-present canary path instead of
/// whatever the user chose to scan, so it can be polled from the welcome
/// flow before any scan has happened at all.
public enum AccessProbe {
    /// `~/Library/Containers` - present on every Mac, and blocked for a
    /// non-FDA process regardless of which volume or folder the user later
    /// chooses to scan. Not itself something DustEater has any reason to
    /// read; it exists purely as a canary.
    public static let defaultProtectedPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Containers")

    /// `true` the instant TCC grants access - no relaunch needed, since this
    /// is a live syscall each time, not a cached value from launch.
    public static func hasFullDiskAccess(checking path: String = defaultProtectedPath) -> Bool {
        AttrListBulkReader.probeAccess(atPath: path) == 0
    }
}
