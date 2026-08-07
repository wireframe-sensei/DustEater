import Foundation

/// Human-readable byte size formatting shared across the CLI tools and the app UI.
public enum ByteFormatter {
    public static func string(fromBytes bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return String(format: "%.2f %@", value, units[unitIndex])
    }
}
