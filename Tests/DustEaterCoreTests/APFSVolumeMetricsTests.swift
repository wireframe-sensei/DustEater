import Testing
@testable import DustEaterCore

struct APFSVolumeMetricsTests {
    @Test func purgeableBytesComputesCorrectly() {
        let snapshot = APFSVolumeMetrics.VolumeCapacitySnapshot(
            totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            availableIncludingPurgeable: 600_000_000,
            availableOpportunistic: 100_000_000
        )

        let purgeable = APFSVolumeMetrics.purgeableBytes(from: snapshot)
        #expect(purgeable == 100_000_000)
    }

    @Test func purgeableBytesNeverNegative() {
        let snapshot = APFSVolumeMetrics.VolumeCapacitySnapshot(
            totalCapacity: 1_000_000_000,
            availableCapacity: 600_000_000,
            availableIncludingPurgeable: 500_000_000,
            availableOpportunistic: 0
        )

        let purgeable = APFSVolumeMetrics.purgeableBytes(from: snapshot)
        #expect(purgeable >= 0)
    }

    @Test func purgeableBytesZeroWhenEqual() {
        let snapshot = APFSVolumeMetrics.VolumeCapacitySnapshot(
            totalCapacity: 1_000_000_000,
            availableCapacity: 500_000_000,
            availableIncludingPurgeable: 500_000_000,
            availableOpportunistic: 0
        )

        let purgeable = APFSVolumeMetrics.purgeableBytes(from: snapshot)
        #expect(purgeable == 0)
    }
}
