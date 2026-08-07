import SwiftUI

/// Assigns colors to treemap rectangles based on file type and depth.
/// Colors are chosen to be distinct enough for visual scanning while
/// remaining pleasant and accessible.
public enum TreemapColors {
    /// Color for a directory node.
    public static func colorForDirectory(depth: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.2, green: 0.6, blue: 1.0),   // Blue
            Color(red: 0.2, green: 0.8, blue: 0.6),   // Teal
            Color(red: 0.4, green: 0.8, blue: 0.2),   // Green
            Color(red: 1.0, green: 0.8, blue: 0.2),   // Yellow
            Color(red: 1.0, green: 0.6, blue: 0.2),   // Orange
        ]
        return colors[depth % colors.count]
    }

    /// Color for a file node, based on its extension or type.
    public static func colorForFile(name: String, depth: Int) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()

        // Common file type groupings with distinct colors.
        switch ext {
        case "app": return Color(red: 0.8, green: 0.2, blue: 0.8) // Magenta: apps
        case "dmg", "iso": return Color(red: 0.9, green: 0.5, blue: 0.1) // Dark orange: disk images
        case "zip", "tar", "gz", "7z", "rar": return Color(red: 0.8, green: 0.4, blue: 0.2) // Burnt orange: archives
        case "mov", "mp4", "mkv", "avi": return Color(red: 0.9, green: 0.3, blue: 0.3) // Red: video
        case "mp3", "m4a", "flac", "wav": return Color(red: 0.7, green: 0.3, blue: 0.7) // Purple: audio
        case "jpg", "jpeg", "png", "gif", "webp": return Color(red: 0.3, green: 0.6, blue: 0.9) // Light blue: images
        case "pdf", "doc", "docx", "xls", "xlsx": return Color(red: 0.6, green: 0.6, blue: 0.6) // Gray: documents
        default: return Color(red: 0.5, green: 0.5, blue: 0.5) // Medium gray: other files
        }
    }

    /// Determines color based on whether the node is a directory or file.
    public static func colorForNode(_ node: FileNode, depth: Int) -> Color {
        if node.isDirectory {
            return colorForDirectory(depth: depth)
        } else {
            return colorForFile(name: node.name, depth: depth)
        }
    }

    /// Helper to compute depth from a path string (slash count).
    public static func depth(fromPath path: String, relativeTo root: String) -> Int {
        let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
        return relative.filter { $0 == "/" }.count
    }
}
