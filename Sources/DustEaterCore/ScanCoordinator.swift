import Foundation
import Observation
import Darwin

/// Drives a single directory scan and exposes its state for SwiftUI to
/// observe. Owns the running scan `Task` so a new scan (or explicit cancel)
/// can supersede an in-flight one.
@Observable
@MainActor
public final class ScanCoordinator {
    public private(set) var state: ScanState = .idle
    /// The node currently displayed in the treemap (can zoom into any folder).
    /// Synced with the list view's selection so they stay coordinated.
    public var zoomNode: FileNode?
    /// Duration of the completed scan in seconds
    public private(set) var scanDuration: Double = 0

    private var scanTask: Task<Void, Never>?
    private var scanStartTime: DispatchTime?

    public init() {}

    public func startScan(path: String) {
        scanTask?.cancel()
        scanStartTime = DispatchTime.now()
        scanDuration = 0
        state = .scanning(ScanProgressSnapshot(itemsScanned: 0, bytesScanned: 0, currentPath: path))

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
            let node = await scanner.scan(rootPath: path) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.applyProgress(progress)
                }
            }
            let scanElapsed = Double(DispatchTime.now().uptimeNanoseconds - scanStartTime.uptimeNanoseconds) / 1_000_000_000
            debugLog("📊 Filesystem scan: \(String(format: "%.3f", scanElapsed))s")

            guard !Task.isCancelled else { return }

            // Calculate scan duration
            if let startTime = self.scanStartTime {
                let endTime = DispatchTime.now()
                self.scanDuration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                debugLog("📊 Total scan time: \(String(format: "%.3f", self.scanDuration))s")
                debugLog("📊 Items found: \(node.itemCount)")
                debugLog("📊 Total size: \(ByteFormatter.string(fromBytes: node.size))")
            }

            self.state = .finished(node)
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
    }

    private func applyProgress(_ progress: ScanProgress) {
        // A cancel/new-scan may have raced ahead of this stale update.
        guard case .scanning = state else { return }

        state = .scanning(ScanProgressSnapshot(
            itemsScanned: progress.itemsScanned,
            bytesScanned: progress.bytesScanned,
            currentPath: progress.currentPath
        ))
    }
}

/// Timing/diagnostic logging, compiled out entirely in Release builds.
private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
