import Testing
@testable import DustEaterCore

struct PhysicalDiskHealthTests {
    private func health(
        smartStatus: SMARTStatus = .notReported,
        wearLevelPercent: Double? = nil,
        temperatureCelsius: Double? = nil
    ) -> PhysicalDiskHealth {
        PhysicalDiskHealth(
            bsdName: "disk0",
            displayName: "Test Disk",
            isSystemDisk: false,
            mediumType: .solidState,
            interconnect: .internal,
            smartStatus: smartStatus,
            temperatureCelsius: temperatureCelsius,
            wearLevelPercent: wearLevelPercent,
            totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            purgeableBytes: 0,
            localSnapshotCount: 0,
            isAPFS: true
        )
    }

    @Test func failingSMARTStatusCritical() {
        let disk = health(smartStatus: .failing)
        #expect(disk.overallHealthStatus == .critical)
    }

    @Test func lowWearLevelCritical() {
        let disk = health(wearLevelPercent: 40)
        #expect(disk.overallHealthStatus == .critical)
    }

    @Test func moderateWearLevelWarning() {
        let disk = health(wearLevelPercent: 70)
        #expect(disk.overallHealthStatus == .warning)
    }

    @Test func highWearLevelCritical() {
        let disk = health(wearLevelPercent: 45)
        #expect(disk.overallHealthStatus == .critical)
    }

    @Test func highTemperatureWarning() {
        let disk = health(temperatureCelsius: 70)
        #expect(disk.overallHealthStatus == .warning)
    }

    @Test func normalTemperaturePassed() {
        let disk = health(temperatureCelsius: 45)
        #expect(disk.overallHealthStatus == .passed)
    }

    @Test func allSignalsAbsentUnknown() {
        let disk = health(smartStatus: .notReported, wearLevelPercent: nil, temperatureCelsius: nil)
        #expect(disk.overallHealthStatus == .unknown)
    }

    @Test func goodStatesPassed() {
        let disk = health(smartStatus: .verified, wearLevelPercent: 90, temperatureCelsius: 40)
        #expect(disk.overallHealthStatus == .passed)
    }

    @Test func verifiedSMARTWithNoOtherDataPassed() {
        let disk = health(smartStatus: .verified)
        #expect(disk.overallHealthStatus == .passed)
    }

    @Test func failingSMARTOverridseGoodTemp() {
        let disk = health(smartStatus: .failing, temperatureCelsius: 40)
        #expect(disk.overallHealthStatus == .critical)
    }
}
