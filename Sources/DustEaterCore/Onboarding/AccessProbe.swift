import Foundation

/// Detects Full Disk Access without ever telling the user to relaunch.
/// `ScanCoordinator` already probes a specific scan root the same way
/// (`AttrListBulkReader.probeAccess`, used to distinguish "doesn't exist"
/// from "access denied" before starting a scan) - this is the same
/// technique aimed at a fixed, always-present canary path instead of
/// whatever the user chose to scan, so it can be polled from the welcome
/// flow before any scan has happened at all.
public enum AccessProbe {
    /// The real TCC database - present on every Mac, owned by root with
    /// permissions that block every process without Full Disk Access, and
    /// literally the table FDA grants are stored in. Verified live, not
    /// assumed: `open()` on this path returns `EPERM` without FDA and `0`
    /// with it, confirmed against a real non-FDA process on the machine
    /// this was fixed on.
    ///
    /// The original canary was `~/Library/Containers` - wrong, and a real
    /// bug, not a theoretical one: that directory is owned by the current
    /// user (`drwx------`), so plain Unix permissions let any process the
    /// user runs open and list it - `ls ~/Library/Containers` succeeds with
    /// zero FDA grant. TCC only protects *reading files inside* another
    /// app's container, never top-level directory listing, so probing it
    /// with a bare `open()` reported "granted" unconditionally, regardless
    /// of the real TCC state - confirmed live with `dd` against both paths
    /// from the same ungranted process before this fix.
    public static let defaultProtectedPath = "/Library/Application Support/com.apple.TCC/TCC.db"

    /// `true` the instant TCC grants access - no relaunch needed, since this
    /// is a live syscall each time, not a cached value from launch.
    public static func hasFullDiskAccess(checking path: String = defaultProtectedPath) -> Bool {
        AttrListBulkReader.probeAccess(atPath: path) == 0
    }
}
