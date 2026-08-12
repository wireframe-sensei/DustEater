import Foundation

enum PurgeableSpaceReclaimer {
    static func reclaim(volumePath: String) async throws -> Int64 {
        let escapeForAppleScript = { (str: String) -> String in
            str.replacingOccurrences(of: "'", with: "'\\''")
        }

        let escapedPath = escapeForAppleScript(volumePath)

        let appleScript = """
        do shell script "/usr/bin/tmutil thinlocalsnapshots \(escapedPath) 999999999999 4" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            let beforeSnapshot = APFSVolumeMetrics.capacitySnapshot(atPath: volumePath)

            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                if errorOutput.lowercased().contains("user canceled") {
                    throw DiskTelemetryError.reclaimCancelled
                } else {
                    throw DiskTelemetryError.reclaimFailed(errorOutput.isEmpty ? "Unknown error" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            let afterSnapshot = APFSVolumeMetrics.capacitySnapshot(atPath: volumePath)

            guard let before = beforeSnapshot, let after = afterSnapshot else {
                return 0
            }

            let beforePurgeable = APFSVolumeMetrics.purgeableBytes(from: before)
            let afterPurgeable = APFSVolumeMetrics.purgeableBytes(from: after)
            let freed = max(0, beforePurgeable - afterPurgeable)

            return freed
        } catch let error as DiskTelemetryError {
            throw error
        } catch {
            throw DiskTelemetryError.reclaimFailed(error.localizedDescription)
        }
    }
}
