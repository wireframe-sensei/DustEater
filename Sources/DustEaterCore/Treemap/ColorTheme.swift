import SwiftUI

/// Theme for treemap colors with truly distinct palettes
public enum ColorTheme: String, CaseIterable {
    case vibrant = "Vibrant"
    case pastel = "Pastel"
    case neon = "Neon"
    case warm = "Warm"
    case cool = "Cool"
    case rainbow = "Rainbow"

    public var displayName: String {
        self.rawValue
    }

    /// Get directory colors for this theme
    func directoryColors() -> [Color] {
        switch self {
        case .vibrant:
            return [
                Color(red: 0.2, green: 0.6, blue: 1.0),   // Bright Blue
                Color(red: 0.2, green: 0.8, blue: 0.6),   // Teal
                Color(red: 0.4, green: 0.8, blue: 0.2),   // Lime Green
                Color(red: 1.0, green: 0.8, blue: 0.2),   // Bright Yellow
                Color(red: 1.0, green: 0.6, blue: 0.2),   // Bright Orange
            ]
        case .pastel:
            return [
                Color(red: 1.0, green: 0.7, blue: 0.7),   // Pastel Pink
                Color(red: 1.0, green: 0.9, blue: 0.6),   // Pastel Peach
                Color(red: 0.7, green: 1.0, blue: 0.7),   // Pastel Green
                Color(red: 0.7, green: 0.9, blue: 1.0),   // Pastel Blue
                Color(red: 0.95, green: 0.8, blue: 1.0),  // Pastel Lavender
            ]
        case .neon:
            return [
                Color(red: 0.0, green: 1.0, blue: 1.0),   // Neon Cyan
                Color(red: 0.0, green: 1.0, blue: 0.5),   // Neon Green
                Color(red: 1.0, green: 0.0, blue: 1.0),   // Neon Magenta
                Color(red: 1.0, green: 1.0, blue: 0.0),   // Neon Yellow
                Color(red: 1.0, green: 0.5, blue: 0.0),   // Neon Orange
            ]
        case .warm:
            return [
                Color(red: 1.0, green: 0.4, blue: 0.2),   // Warm Red-Orange
                Color(red: 1.0, green: 0.6, blue: 0.1),   // Warm Orange
                Color(red: 1.0, green: 0.8, blue: 0.1),   // Warm Gold
                Color(red: 0.9, green: 0.7, blue: 0.3),   // Warm Yellow
                Color(red: 0.8, green: 0.5, blue: 0.2),   // Warm Brown
            ]
        case .cool:
            return [
                Color(red: 0.1, green: 0.3, blue: 0.8),   // Cool Dark Blue
                Color(red: 0.2, green: 0.5, blue: 1.0),   // Cool Blue
                Color(red: 0.0, green: 0.7, blue: 0.8),   // Cool Cyan
                Color(red: 0.2, green: 0.8, blue: 0.7),   // Cool Teal
                Color(red: 0.3, green: 0.9, blue: 0.6),   // Cool Green
            ]
        case .rainbow:
            return [
                Color(red: 1.0, green: 0.0, blue: 0.0),   // Red
                Color(red: 1.0, green: 0.5, blue: 0.0),   // Orange
                Color(red: 1.0, green: 1.0, blue: 0.0),   // Yellow
                Color(red: 0.0, green: 0.8, blue: 0.0),   // Green
                Color(red: 0.0, green: 0.0, blue: 1.0),   // Blue
            ]
        }
    }

    /// Get file colors for this theme
    func fileColors() -> [String: Color] {
        switch self {
        case .vibrant:
            return [
                "app": Color(red: 0.8, green: 0.2, blue: 0.8),      // Magenta
                "archive": Color(red: 0.8, green: 0.4, blue: 0.2),  // Brown
                "video": Color(red: 0.9, green: 0.3, blue: 0.3),    // Red
                "audio": Color(red: 0.7, green: 0.3, blue: 0.7),    // Purple
                "image": Color(red: 0.3, green: 0.6, blue: 0.9),    // Light Blue
                "document": Color(red: 0.6, green: 0.6, blue: 0.6),  // Gray
                "other": Color(red: 0.5, green: 0.5, blue: 0.5),    // Dark Gray
            ]
        case .pastel:
            return [
                "app": Color(red: 1.0, green: 0.85, blue: 0.95),    // Lavender
                "archive": Color(red: 1.0, green: 0.9, blue: 0.8),  // Peach
                "video": Color(red: 1.0, green: 0.85, blue: 0.85),  // Light Pink
                "audio": Color(red: 0.9, green: 0.85, blue: 1.0),   // Light Purple
                "image": Color(red: 0.85, green: 0.95, blue: 1.0),  // Light Blue
                "document": Color(red: 0.9, green: 0.9, blue: 0.9), // Light Gray
                "other": Color(red: 0.85, green: 0.85, blue: 0.85), // Medium Gray
            ]
        case .neon:
            return [
                "app": Color(red: 1.0, green: 0.0, blue: 0.8),      // Neon Pink
                "archive": Color(red: 1.0, green: 0.65, blue: 0.0), // Neon Orange
                "video": Color(red: 1.0, green: 0.0, blue: 0.0),    // Neon Red
                "audio": Color(red: 1.0, green: 0.0, blue: 1.0),    // Neon Magenta
                "image": Color(red: 0.0, green: 1.0, blue: 1.0),    // Neon Cyan
                "document": Color(red: 0.5, green: 0.5, blue: 0.5), // Gray
                "other": Color(red: 0.4, green: 0.4, blue: 0.4),    // Dark Gray
            ]
        case .warm:
            return [
                "app": Color(red: 1.0, green: 0.3, blue: 0.4),      // Warm Red
                "archive": Color(red: 1.0, green: 0.5, blue: 0.2),  // Warm Orange
                "video": Color(red: 0.9, green: 0.2, blue: 0.3),    // Warm Dark Red
                "audio": Color(red: 1.0, green: 0.6, blue: 0.5),    // Warm Salmon
                "image": Color(red: 0.8, green: 0.6, blue: 0.4),    // Warm Tan
                "document": Color(red: 0.7, green: 0.7, blue: 0.7), // Gray
                "other": Color(red: 0.6, green: 0.6, blue: 0.6),    // Dark Gray
            ]
        case .cool:
            return [
                "app": Color(red: 0.2, green: 0.5, blue: 1.0),      // Cool Blue
                "archive": Color(red: 0.0, green: 0.7, blue: 0.8),  // Cool Cyan
                "video": Color(red: 0.1, green: 0.4, blue: 0.9),    // Cool Dark Blue
                "audio": Color(red: 0.3, green: 0.8, blue: 0.8),    // Cool Teal
                "image": Color(red: 0.2, green: 0.9, blue: 0.6),    // Cool Green
                "document": Color(red: 0.5, green: 0.5, blue: 0.5), // Gray
                "other": Color(red: 0.4, green: 0.4, blue: 0.4),    // Dark Gray
            ]
        case .rainbow:
            return [
                "app": Color(red: 1.0, green: 0.0, blue: 1.0),      // Magenta
                "archive": Color(red: 1.0, green: 0.65, blue: 0.0), // Orange
                "video": Color(red: 1.0, green: 0.0, blue: 0.0),    // Red
                "audio": Color(red: 0.5, green: 0.0, blue: 1.0),    // Purple
                "image": Color(red: 0.0, green: 0.5, blue: 1.0),    // Blue
                "document": Color(red: 0.5, green: 0.5, blue: 0.5), // Gray
                "other": Color(red: 0.4, green: 0.4, blue: 0.4),    // Dark Gray
            ]
        }
    }
}
