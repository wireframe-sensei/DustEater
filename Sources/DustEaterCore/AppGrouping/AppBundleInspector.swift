import Foundation

/// Reads the handful of `Info.plist` keys needed to identify an `.app`
/// bundle and cross-reference it against `~/Library`.
enum AppBundleInspector {
    struct Info: Sendable {
        let bundleIdentifier: String?
        let displayName: String
    }

    /// Parses `<appPath>/Contents/Info.plist`. Falls back to deriving a
    /// display name from the bundle's filename if the plist is missing or
    /// malformed - a corrupt/partial app shouldn't abort the whole scan.
    static func inspect(appPath: String) async -> Info {
        let fallbackName = (appPath as NSString)
            .lastPathComponent
            .replacingOccurrences(of: ".app", with: "")

        let parsed = try? await BlockingIO.run { () -> Info in
            let plistPath = appPath + "/Contents/Info.plist"
            guard
                let data = FileManager.default.contents(atPath: plistPath),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else {
                return Info(bundleIdentifier: nil, displayName: fallbackName)
            }

            let bundleIdentifier = plist["CFBundleIdentifier"] as? String
            let displayName = (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? fallbackName

            return Info(bundleIdentifier: bundleIdentifier, displayName: displayName)
        }

        return parsed ?? Info(bundleIdentifier: nil, displayName: fallbackName)
    }
}
