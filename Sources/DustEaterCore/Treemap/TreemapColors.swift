import SwiftUI

/// Assigns colors to treemap rectangles based on file type, depth, and theme.
/// Colors are chosen to be distinct enough for visual scanning while
/// remaining pleasant and accessible.
public enum TreemapColors {
    /// Color for a directory node with variation for siblings at same depth.
    public static func colorForDirectory(depth: Int, name: String = "", theme: ColorTheme) -> Color {
        let colors = theme.directoryColors()
        guard !colors.isEmpty else { return .gray }

        // A single treemap render only ever shows one flat level of
        // siblings (the currently zoomed node's direct children), so
        // `depth` is the same constant for every rect in it — it can't
        // distinguish siblings on its own. Cycle through the *entire*
        // palette by name hash instead of just alternating between two
        // colors, so a folder full of subfolders doesn't collapse to one
        // or two shades.
        let hash = abs(name.hashValue)
        let colorIndex = (depth + hash) % colors.count
        return colors[colorIndex]
    }

    /// Color for a file node, based on its extension or type.
    public static func colorForFile(name: String, depth: Int, theme: ColorTheme) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        let fileColors = theme.fileColors()

        // Common file type groupings with distinct colors.
        switch ext {
        case "app": return fileColors["app"] ?? .gray
        case "dmg", "iso": return fileColors["archive"] ?? .gray
        case "zip", "tar", "gz", "7z", "rar": return fileColors["archive"] ?? .gray
        case "mov", "mp4", "mkv", "avi": return fileColors["video"] ?? .gray
        case "mp3", "m4a", "flac", "wav": return fileColors["audio"] ?? .gray
        case "jpg", "jpeg", "png", "gif", "webp": return fileColors["image"] ?? .gray
        case "pdf", "doc", "docx", "xls", "xlsx": return fileColors["document"] ?? .gray
        default: return fileColors["other"] ?? .gray
        }
    }

    /// Determines color based on whether the node is a directory or file.
    public static func colorForNode(_ node: FileNode, depth: Int, theme: ColorTheme) -> Color {
        // Weighted theme uses size-based hue (green→red) — already varies
        // continuously per node, so it's left alone below.
        if theme == .weighted {
            return colorBySize(node.size)
        }

        let baseColor: Color
        if node.isDirectory {
            // `name:` matters here — omitting it (as this used to) makes
            // every directory resolve to the exact same hash bucket, since
            // it silently falls back to the same `name: ""` default every
            // time. Combined with `depth` being constant per render (see
            // `colorForDirectory`), that meant every folder in the app
            // rendered as one single flat color, in every theme.
            baseColor = colorForDirectory(depth: depth, name: node.name, theme: theme)
        } else {
            baseColor = colorForFile(name: node.name, depth: depth, theme: theme)
        }

        // `colorForFile` intentionally keys color to file-*type* (so every
        // "other" or "document" file shares a hue), and `colorForDirectory`
        // only has 5ish hues to spread across potentially many siblings —
        // both mean real hash collisions in an ordinary folder. Nudge
        // brightness deterministically per node on top of the base hue so
        // same-category siblings still read as separate tiles instead of
        // fusing into one solid block, without losing the type/depth
        // signal the hue itself conveys.
        return siblingNudged(baseColor, seed: node.name)
    }

    /// Deterministic per-node brightness nudge, layered on top of a base
    /// color via opacity (the same mechanism `TreemapView` already uses to
    /// distinguish hovered from resting tiles) rather than decomposing into
    /// HSB — keeps this a pure, cheap function with no color-space math.
    private static func siblingNudged(_ color: Color, seed: String) -> Color {
        let bucket = abs(seed.hashValue) % 5
        let opacityAdjustment = 1.0 - Double(bucket) * 0.06 // 1.00, 0.94, 0.88, 0.82, 0.76
        return color.opacity(opacityAdjustment)
    }

    /// Map size to a hue from green (small) to red (large) using relative scaling
    private static func colorBySize(_ size: Int64) -> Color {
        // Use relative sizing: normalize size within typical file size ranges
        // This makes coloring relative rather than absolute
        // Small files/folders (< 100MB) → green
        // Medium (100MB - 10GB) → yellow
        // Large (> 10GB) → red

        let logSize = log2(Double(max(1, size)))

        // Typical range: 1KB (log≈10) to 100GB (log≈36)
        // Normalize to 0-1 for relative sizing
        let normalizedLog = (logSize - 10.0) / 26.0  // 0 at 1KB (log10), 1 at 64GB (log36)
        let relativeSize = min(1.0, max(0.0, normalizedLog))  // Clamp to 0-1

        // Map relative size to hue: green (120°) → yellow (60°) → red (0°)
        let hue = (120.0 - (relativeSize * 120.0)) / 360.0

        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }

    /// Helper to compute depth from a path string (slash count).
    public static func depth(fromPath path: String, relativeTo root: String) -> Int {
        let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
        return relative.filter { $0 == "/" }.count
    }
}
