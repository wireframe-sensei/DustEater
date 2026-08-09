import Testing
@testable import DustEaterCore

/// Locks in `ByteFormatter`'s output - added alongside the switch from
/// `String(format: "%.2f %@", ...)` to `.formatted()`, since that's a
/// different formatting code path and the whole point was to change *how*
/// the string gets built without changing *what* it says.
struct ByteFormatterTests {
    @Test func formatsAcrossUnitBoundaries() {
        #expect(ByteFormatter.string(fromBytes: 0) == "0.00 B")
        #expect(ByteFormatter.string(fromBytes: 1023) == "1023.00 B")
        #expect(ByteFormatter.string(fromBytes: 1024) == "1.00 KB")
        #expect(ByteFormatter.string(fromBytes: 1536) == "1.50 KB")
        #expect(ByteFormatter.string(fromBytes: 1_048_576) == "1.00 MB")
        #expect(ByteFormatter.string(fromBytes: 1_073_741_824) == "1.00 GB")
        #expect(ByteFormatter.string(fromBytes: 1_099_511_627_776) == "1.00 TB")
    }

    @Test func roundsToTwoDecimalPlaces() {
        // 1_000_000 bytes / 1024 = 976.5625 KB
        #expect(ByteFormatter.string(fromBytes: 1_000_000) == "976.56 KB")
    }

    @Test func neverInsertsThousandsSeparators() {
        // Largest possible whole part before crossing a unit boundary is
        // just under 1024 - must never render as "1,023.99".
        #expect(ByteFormatter.string(fromBytes: 1023) == "1023.00 B")
    }
}
