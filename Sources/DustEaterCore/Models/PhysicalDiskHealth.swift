import Foundation

public enum MediumType: String, Sendable {
    case solidState
    case rotational
    case unknown
}

public enum Interconnect: String, Sendable {
    case `internal`
    case external
    case unknown
}

public enum SMARTStatus: String, Sendable {
    case verified
    case failing
    case notReported
}

public enum DiskHealthStatus: String, Sendable {
    case passed
    case warning
    case critical
    case unknown
}

public struct PhysicalDiskHealth: Sendable, Identifiable {
    public let id: String
    public let bsdName: String
    public let displayName: String
    public let isSystemDisk: Bool
    public let mediumType: MediumType
    public let interconnect: Interconnect
    public let interconnectProtocol: String?
    public let smartStatus: SMARTStatus
    public let temperatureCelsius: Double?
    public let wearLevelPercent: Double?
    public let totalBytesWritten: Int64?
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let purgeableBytes: Int64
    public let localSnapshotCount: Int
    public let isAPFS: Bool

    public var overallHealthStatus: DiskHealthStatus {
        if smartStatus == .failing {
            return .critical
        }

        if let wear = wearLevelPercent {
            if wear < 50 {
                return .critical
            }
            if wear < 80 {
                return .warning
            }
        }

        if let temp = temperatureCelsius, temp >= 65 {
            return .warning
        }

        if smartStatus == .notReported && wearLevelPercent == nil && temperatureCelsius == nil {
            return .unknown
        }

        return .passed
    }

    public init(
        bsdName: String,
        displayName: String,
        isSystemDisk: Bool,
        mediumType: MediumType,
        interconnect: Interconnect,
        interconnectProtocol: String? = nil,
        smartStatus: SMARTStatus,
        temperatureCelsius: Double? = nil,
        wearLevelPercent: Double? = nil,
        totalBytesWritten: Int64? = nil,
        totalCapacity: Int64,
        availableCapacity: Int64,
        purgeableBytes: Int64,
        localSnapshotCount: Int,
        isAPFS: Bool
    ) {
        self.id = bsdName
        self.bsdName = bsdName
        self.displayName = displayName
        self.isSystemDisk = isSystemDisk
        self.mediumType = mediumType
        self.interconnect = interconnect
        self.interconnectProtocol = interconnectProtocol
        self.smartStatus = smartStatus
        self.temperatureCelsius = temperatureCelsius
        self.wearLevelPercent = wearLevelPercent
        self.totalBytesWritten = totalBytesWritten
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.purgeableBytes = purgeableBytes
        self.localSnapshotCount = localSnapshotCount
        self.isAPFS = isAPFS
    }
}

public enum DiskTelemetryError: LocalizedError {
    case reclaimCancelled
    case reclaimFailed(String)
    case refreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .reclaimCancelled:
            return "Reclaim cancelled by user."
        case .reclaimFailed(let message):
            return "Failed to reclaim purgeable space: \(message)"
        case .refreshFailed(let message):
            return "Failed to refresh disk health: \(message)"
        }
    }
}
