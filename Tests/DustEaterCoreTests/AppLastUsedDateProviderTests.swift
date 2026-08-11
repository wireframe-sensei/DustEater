import Foundation
import Testing
@testable import DustEaterCore

@Suite("AppLastUsedDateProvider")
struct AppLastUsedDateProviderTests {
    @Test
    func fallsBackToFilesystemModificationDate() async throws {
        let tempDir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSHomeDirectory()),
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appPath = tempDir.appendingPathComponent("TestApp.app").path
        try FileManager.default.createDirectory(atPath: appPath, withIntermediateDirectories: true)

        let date = await AppLastUsedDateProvider.lastUsedDate(forAppAtPath: appPath)

        #expect(date != nil)

        let attributes = try FileManager.default.attributesOfItem(atPath: appPath)
        let modificationDate = attributes[.modificationDate] as? Date

        #expect(modificationDate != nil)
        if let date = date, let modificationDate = modificationDate {
            let timeDiff = abs(date.timeIntervalSince(modificationDate))
            #expect(timeDiff < 1.0)
        }
    }
}
