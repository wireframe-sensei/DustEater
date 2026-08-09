import Foundation

/// Human-readable byte size formatting shared across the CLI tools and the app UI.
public enum ByteFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    public static func string(fromBytes bytes: Int64) -> String {
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        // `.formatted()` rather than `String(format: "%.2f %@", ...)`: this
        // is called per visible row and per treemap label on every render,
        // and `String(format:)` pays for parsing the format string and
        // bridging the `%@` argument through NSString on every call for
        // what's ultimately just "round to 2 decimals". Grouping is
        // disabled since `%.2f` never inserted thousands separators either
        // - `value` here is always < 1024 by the loop above.
        let formattedValue = value.formatted(.number.precision(.fractionLength(2)).grouping(.never))
        return "\(formattedValue) \(units[unitIndex])"
    }
}
