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
    /// or `timeout` elapses. Test directories are tiny, so scans finish
    /// near-instantly in practice; the timeout just guards against a hang.
    private func waitForTerminalState(_ coordinator: ScanCoordinator, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            switch coordinator.state {
            case .idle, .scanning:
                try? await Task.sleep(for: .milliseconds(10))
            case .finished, .failed, .needsFullDiskAccess:
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

    @Test func cancelScanReturnsToIdle() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ScanCoordinator()
        coordinator.startScan(path: root.path)
        coordinator.cancelScan()

        #expect(coordinator.state == .idle)
    }
}
