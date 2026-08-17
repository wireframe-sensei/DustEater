import Testing
import Foundation
@testable import DustEaterCore

@MainActor
struct ScanCoordinatorTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DustEaterScanCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Polls `coordinator.state` until it stops being `.idle`/`.scanning`,
    /// or `timeout` elapses. Test directories are tiny, so the *tree* scan
    /// finishes near-instantly in practice - this only waits for `state`
    /// itself to reach a terminal case, not for the tree-dependent finding
    /// work (which continues after `.finished` and touches real system
    /// paths like `/Applications`, so isn't bounded here). The timeout
    /// just guards against a hang.
    private func waitForTerminalState(_ coordinator: ScanCoordinator, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            switch coordinator.state {
            case .idle, .scanning:
                try? await Task.sleep(for: .milliseconds(10))
            case .finished, .cancelled, .failed, .needsFullDiskAccess:
                return
            }
        }
    }

    @Test func scanningValidDirectoryReachesFinishedState() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xAB, count: 100).write(to: root.appendingPathComponent("file.bin"))

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)
        await waitForTerminalState(coordinator)

        guard case .finished(let node) = coordinator.state else {
            Issue.record("Expected .finished, got \(coordinator.state)")
            return
        }
        #expect(node.size >= 100)
    }

    @Test func scanningNonexistentPathFails() async throws {
        let coordinator = ScanCoordinator()
        coordinator.startScan(path: "/this/path/does/not/exist/\(UUID().uuidString)")
        await waitForTerminalState(coordinator)

        guard case .failed = coordinator.state else {
            Issue.record("Expected .failed, got \(coordinator.state)")
            return
        }
    }

    @Test func scanningPermissionDeniedRootReportsNeedsFullDiskAccess() async throws {
        let root = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)
        await waitForTerminalState(coordinator)

        guard case .needsFullDiskAccess(let path) = coordinator.state else {
            Issue.record("Expected .needsFullDiskAccess, got \(coordinator.state)")
            return
        }
        #expect(path == root.path)
    }

    /// Cancelling in the same tick `startScan` was called, before the scan
    /// task has had any chance to run, must never produce `.finished` from
    /// what would be a completely empty, untrustworthy tree - `.cancelled`
    /// is the honest result.
    @Test func cancelBeforeTreeFinishesReachesCancelledNotFinished() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)
        coordinator.cancelScan()

        #expect(coordinator.state == .cancelled)
    }

    /// Cancelling *after* the tree already finished only cuts short the
    /// slower tree-dependent finding work (duplicate hashing) - the tree
    /// itself is legitimately complete by then, so `state` must not be
    /// downgraded away from `.finished`.
    @Test func cancelAfterTreeFinishesLeavesStateFinished() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0xAB, count: 100).write(to: root.appendingPathComponent("file.bin"))

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)
        await waitForTerminalState(coordinator)
        guard case .finished = coordinator.state else {
            Issue.record("Expected .finished before cancelling, got \(coordinator.state)")
            return
        }

        coordinator.cancelScan()

        guard case .finished = coordinator.state else {
            Issue.record("Expected state to stay .finished after cancel, got \(coordinator.state)")
            return
        }
    }

    /// `inFlightFindingIDs` starts as every finding category the moment a
    /// scan begins - deterministic and immediate, unlike the categories
    /// actually clearing (which depends on real system paths like
    /// `/Applications` and isn't bounded in a test environment).
    @Test func inFlightFindingIDsStartsAsEveryFindingID() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)

        #expect(coordinator.inFlightFindingIDs == Set(CleanupFindingID.allCases))
        #expect(coordinator.findings.isEmpty)
    }

    /// A second `startScan` call resets both `findings` and
    /// `inFlightFindingIDs` - a rescan shouldn't carry over stale findings
    /// from whatever the previous scan of a (possibly different) path found.
    @Test func startingANewScanResetsFindingsAndInFlightIDs() async throws {
        let rootA = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootA) }
        let rootB = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: rootB) }

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: rootA.path)
        coordinator.cancelScan()

        coordinator.startScan(path: rootB.path)

        #expect(coordinator.rootPath == rootB.path)
        #expect(coordinator.inFlightFindingIDs == Set(CleanupFindingID.allCases))
    }
}
