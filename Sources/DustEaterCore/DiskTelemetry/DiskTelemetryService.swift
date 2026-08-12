import Foundation
import Observation

@Observable
@MainActor
public final class DiskTelemetryService {
    public enum State {
        case idle
        case scanning
        case loaded([PhysicalDiskHealth])
        case failed(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.scanning, .scanning):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            case (.loaded, .loaded):
                return true
            default:
                return false
            }
        }
    }

    public enum ReclaimState: Equatable {
        case idle
        case reclaiming
        case succeeded(bytesFreed: Int64)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var reclaimState: ReclaimState = .idle

    private var refreshTask: Task<Void, Never>?
    private var reclaimTask: Task<Void, Never>?

    public init() {}

    public func refresh() {
        refreshTask?.cancel()

        state = .scanning
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let disks = try await self.gatherDiskHealth()
                guard !Task.isCancelled else { return }
                self.state = .loaded(disks)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    public func reclaimPurgeableSpace(forVolumeAt path: String) {
        reclaimTask?.cancel()

        reclaimState = .reclaiming
        reclaimTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let freed = try await PurgeableSpaceReclaimer.reclaim(volumePath: path)
                guard !Task.isCancelled else { return }

                self.reclaimState = .succeeded(bytesFreed: freed)

                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                self.refresh()
            } catch let error as DiskTelemetryError {
                guard !Task.isCancelled else { return }
                self.reclaimState = .failed(error.errorDescription ?? "Unknown error")
            } catch {
                guard !Task.isCancelled else { return }
                self.reclaimState = .failed(error.localizedDescription)
            }
        }
    }

    private func gatherDiskHealth() async throws -> [PhysicalDiskHealth] {
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) else {
            return []
        }

        var disksByBSDName: [String: PhysicalDiskHealth] = [:]

        for url in urls {
            let path = url.path

            if path.contains("/System/Volumes/") ||
               path.contains("/.") ||
               path.contains("/Library/Developer/CoreSimulator/") ||
               path.contains("SimRuntimeBundle") ||
               path.contains("iOS_") ||
               path.contains("watchOS_") ||
               path.contains("tvOS_") {
                continue
            }

            guard let bsdName = PhysicalDiskResolver.wholeDiskBSDName(forVolumeAt: path) else {
                continue
            }

            if disksByBSDName[bsdName] != nil {
                continue
            }

            let characteristics = IORegistryDiskReader.deviceCharacteristics(forBSDName: bsdName)
            let temperature = SMCTemperatureReader.ssdTemperatureCelsius()
            let capacitySnapshot = APFSVolumeMetrics.capacitySnapshot(atPath: path)
            let fileSystemType = APFSVolumeMetrics.fileSystemType(atPath: path)
            let snapshotCount = APFSVolumeMetrics.localSnapshotCount(forVolumeAt: path)

            let displayName = characteristics?.productName ?? url.lastPathComponent
            let mediumType = characteristics?.mediumType ?? .unknown
            let interconnect = characteristics?.interconnect ?? .unknown
            let interconnectProtocol = characteristics?.interconnectProtocol
            let smartStatus = characteristics?.smartStatus ?? .notReported
            let isAPFS = fileSystemType == "apfs"
            let isSystemDisk = IORegistryDiskReader.isSystemDisk(bsdName: bsdName, forPath: path)

            let totalCapacity = capacitySnapshot?.totalCapacity ?? 0
            let availableCapacity = capacitySnapshot?.availableCapacity ?? 0
            let purgeableBytes = capacitySnapshot.map { APFSVolumeMetrics.purgeableBytes(from: $0) } ?? 0

            let health = PhysicalDiskHealth(
                bsdName: bsdName,
                displayName: displayName,
                isSystemDisk: isSystemDisk,
                mediumType: mediumType,
                interconnect: interconnect,
                interconnectProtocol: interconnectProtocol,
                smartStatus: smartStatus,
                temperatureCelsius: temperature,
                wearLevelPercent: nil,
                totalBytesWritten: nil,
                totalCapacity: totalCapacity,
                availableCapacity: availableCapacity,
                purgeableBytes: purgeableBytes,
                localSnapshotCount: snapshotCount,
                isAPFS: isAPFS
            )

            disksByBSDName[bsdName] = health
        }

        return disksByBSDName.values.sorted { $0.displayName < $1.displayName }
    }
}
