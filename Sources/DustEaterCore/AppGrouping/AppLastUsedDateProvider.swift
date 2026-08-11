import Foundation
import CoreServices

enum AppLastUsedDateProvider {
    static func lastUsedDate(forAppAtPath path: String) async -> Date? {
        return await (try? BlockingIO.run {
            if let spotlightDate = spotlightLastUsedDate(forPath: path) {
                return spotlightDate
            }
            return filesystemModificationDate(forPath: path)
        }) ?? nil
    }

    private static func spotlightLastUsedDate(forPath path: String) -> Date? {
        guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            return nil
        }

        guard let dateValue = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate as CFString) as? Date else {
            return nil
        }
        return dateValue
    }

    private static func filesystemModificationDate(forPath path: String) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
}
