import Foundation

enum AppleSystemServices {
    private static let knownNames: Set<String> = ["siritts", "geoservices"]

    static func isAppleSystemService(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("com.apple.") { return true }
        return knownNames.contains(lower)
    }
}
