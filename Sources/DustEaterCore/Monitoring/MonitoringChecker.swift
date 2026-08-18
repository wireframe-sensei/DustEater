import Foundation

/// One 6-hour monitoring check's result: whatever the fast-path findings
/// currently look like, plus when the check ran. Deliberately independent
/// of `ScanCoordinator` - the menu bar's numbers come from the last check,
/// not from whatever a foreground scan (if one is even running) happens to
/// be showing.
public struct MonitoringCheckResult: Sendable {
    public let findings: [CleanupFinding]
    public let checkedAt: Date

    public init(findings: [CleanupFinding], checkedAt: Date) {
        self.findings = findings
        self.checkedAt = checkedAt
    }

    public var reclaimableBytes: Int64 {
        findings.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// Sum of only the `.rebuildable`-safety findings (package manager
    /// caches, Xcode build artifacts) - what the "reclaimable caches passed
    /// a threshold" notification counts. Safety rule 12: a growing Photos
    /// library or video project must never trigger this notification, so
    /// anything that isn't rebuildable-safety is excluded even though it
    /// may still show up in `findings`/`reclaimableBytes`.
    public var rebuildableBytes: Int64 {
        findings
            .filter { $0.id.safety == .rebuildable }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// Top 3 findings for the dropdown, largest first, report-only findings
    /// excluded - "the menu is a call to action and a locked item is not
    /// one." `findings` is already ranked by `CleanupFindingsBuilder.rank`,
    /// so this only needs to filter and take.
    public var topFindingsForMenu: [CleanupFinding] {
        Array(findings.filter { !$0.actionableItems.isEmpty }.prefix(3))
    }
}

/// Re-runs exactly the fast-path finding scans `ScanCoordinator.
/// startFastPathFindingScans` already starts at the top of every manual
/// scan - package manager caches, Xcode's fixed cache paths, unused
/// applications, and old downloads - with no `DiskScanner` tree walk. The
/// menu bar's 6-hour timer is a second caller of this same static path, not
/// new scan code, and deliberately never walks a tree: a background full-
/// disk walk would contend with the same `BlockingIO` queue that already
/// delays foreground findings (see CLAUDE.md's "Known limitation - I/O
/// queue fairness"), and nothing the menu bar shows needs one - Explore's
/// data keeps coming from the last manual scan, never refreshed in the
/// background.
public enum MonitoringChecker {
    public static func run() async -> MonitoringCheckResult {
        let homeDirectory = NSHomeDirectory()
        async let categoriesTask = PurgeScanner.fixedPathCategories()
        async let installedTask = AppManagerScanner.scanInstalledApps()
        async let downloadsNodeTask = DiskScanner().scan(rootPath: (homeDirectory as NSString).appendingPathComponent("Downloads"))

        let categories = await categoriesTask
        let installed = await installedTask
        let downloadsNode = await downloadsNodeTask
        let oldDownloadsFinding = await CleanupFindingsBuilder.oldDownloads(in: downloadsNode, homeDirectory: homeDirectory)

        let findings = CleanupFindingsBuilder.rank([
            CleanupFindingsBuilder.packageManagerCaches(from: categories),
            CleanupFindingsBuilder.xcodeBuildArtifacts(from: categories),
            CleanupFindingsBuilder.unusedApplications(installed: installed),
            oldDownloadsFinding
        ])

        return MonitoringCheckResult(findings: findings, checkedAt: Date())
    }
}
