import Foundation
import Darwin

enum APFSVolumeMetrics {
    struct VolumeCapacitySnapshot: Sendable {
        let totalCapacity: Int64
        let availableCapacity: Int64
        let availableIncludingPurgeable: Int64
        let availableOpportunistic: Int64
    }

    static func capacitySnapshot(atPath path: String) -> VolumeCapacitySnapshot? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return nil
        }

        let total = values.volumeTotalCapacity ?? 0
        let available = values.volumeAvailableCapacity ?? 0
        let importantUsage = values.volumeAvailableCapacityForImportantUsage ?? 0

        return VolumeCapacitySnapshot(
            totalCapacity: Int64(total),
            availableCapacity: Int64(available),
            availableIncludingPurgeable: Int64(importantUsage),
            availableOpportunistic: Int64(importantUsage)
        )
    }

    static func purgeableBytes(from snapshot: VolumeCapacitySnapshot) -> Int64 {
        let purgeable = snapshot.availableIncludingPurgeable - snapshot.availableCapacity
        return max(0, purgeable)
    }

    static func fileSystemType(atPath path: String) -> String? {
        var statBuf = statfs()
        guard statfs(path, &statBuf) == 0 else {
            return nil
        }

        let nameArray = withUnsafeBytes(of: statBuf.f_fstypename) { bytes in
            bytes.prefix(while: { $0 != 0 }).map { $0 }
        }

        guard let fsType = String(bytes: nameArray, encoding: .utf8) else {
            return nil
        }

        return fsType.isEmpty ? nil : fsType
    }

    static func localSnapshotCount(forVolumeAt path: String) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return 0 }

            let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
            return lines.filter { $0.contains("com.apple.TimeMachine") }.count
        } catch {
            return 0
        }
    }
}
