import SwiftUI

/// Theme for treemap colors
public enum ColorTheme: String, CaseIterable {
    case vibrant = "Vibrant"
    case pastel = "Pastel"
    case dark = "Dark"
    case heatmap = "Heatmap"
    case ocean = "Ocean"
    case forest = "Forest"

    public var displayName: String {
        self.rawValue
    }

    /// Get directory colors for this theme
    func directoryColors() -> [Color] {
        switch self {
        case .vibrant:
            return [
                Color(red: 0.2, green: 0.6, blue: 1.0),
                Color(red: 0.2, green: 0.8, blue: 0.6),
                Color(red: 0.4, green: 0.8, blue: 0.2),
                Color(red: 1.0, green: 0.8, blue: 0.2),
                Color(red: 1.0, green: 0.6, blue: 0.2),
            ]
        case .pastel:
            return [
                Color(red: 0.7, green: 0.8, blue: 1.0),
                Color(red: 0.7, green: 0.95, blue: 0.85),
                Color(red: 0.8, green: 0.95, blue: 0.6),
                Color(red: 1.0, green: 0.95, blue: 0.6),
                Color(red: 1.0, green: 0.85, blue: 0.7),
            ]
        case .dark:
            return [
                Color(red: 0.2, green: 0.4, blue: 0.8),
                Color(red: 0.1, green: 0.6, blue: 0.5),
                Color(red: 0.3, green: 0.6, blue: 0.1),
                Color(red: 0.8, green: 0.6, blue: 0.1),
                Color(red: 0.8, green: 0.4, blue: 0.1),
            ]
        case .heatmap:
            return [
                Color(red: 0.2, green: 0.2, blue: 0.8),
                Color(red: 0.2, green: 0.6, blue: 0.8),
                Color(red: 0.2, green: 0.8, blue: 0.2),
                Color(red: 0.8, green: 0.8, blue: 0.2),
                Color(red: 0.8, green: 0.2, blue: 0.2),
            ]
        case .ocean:
            return [
                Color(red: 0.0, green: 0.3, blue: 0.6),
                Color(red: 0.0, green: 0.5, blue: 0.7),
                Color(red: 0.0, green: 0.7, blue: 0.6),
                Color(red: 0.2, green: 0.8, blue: 0.5),
                Color(red: 0.5, green: 0.8, blue: 0.2),
            ]
        case .forest:
            return [
                Color(red: 0.1, green: 0.4, blue: 0.2),
                Color(red: 0.2, green: 0.5, blue: 0.3),
                Color(red: 0.3, green: 0.6, blue: 0.2),
                Color(red: 0.5, green: 0.7, blue: 0.2),
                Color(red: 0.7, green: 0.6, blue: 0.1),
            ]
        }
    }

    /// Get file colors for this theme
    func fileColors() -> [String: Color] {
        switch self {
        case .vibrant:
            return [
                "app": Color(red: 0.8, green: 0.2, blue: 0.8),
                "archive": Color(red: 0.8, green: 0.4, blue: 0.2),
                "video": Color(red: 0.9, green: 0.3, blue: 0.3),
                "audio": Color(red: 0.7, green: 0.3, blue: 0.7),
                "image": Color(red: 0.3, green: 0.6, blue: 0.9),
                "document": Color(red: 0.6, green: 0.6, blue: 0.6),
                "other": Color(red: 0.5, green: 0.5, blue: 0.5),
            ]
        case .pastel:
            return [
                "app": Color(red: 0.95, green: 0.7, blue: 0.95),
                "archive": Color(red: 0.95, green: 0.8, blue: 0.7),
                "video": Color(red: 0.95, green: 0.75, blue: 0.75),
                "audio": Color(red: 0.9, green: 0.75, blue: 0.9),
                "image": Color(red: 0.75, green: 0.85, blue: 0.95),
                "document": Color(red: 0.85, green: 0.85, blue: 0.85),
                "other": Color(red: 0.8, green: 0.8, blue: 0.8),
            ]
        case .dark:
            return [
                "app": Color(red: 0.6, green: 0.1, blue: 0.6),
                "archive": Color(red: 0.6, green: 0.3, blue: 0.1),
                "video": Color(red: 0.7, green: 0.2, blue: 0.2),
                "audio": Color(red: 0.5, green: 0.2, blue: 0.5),
                "image": Color(red: 0.2, green: 0.4, blue: 0.7),
                "document": Color(red: 0.4, green: 0.4, blue: 0.4),
                "other": Color(red: 0.3, green: 0.3, blue: 0.3),
            ]
        case .heatmap:
            return [
                "app": Color(red: 0.8, green: 0.1, blue: 0.8),
                "archive": Color(red: 0.8, green: 0.5, blue: 0.1),
                "video": Color(red: 0.9, green: 0.2, blue: 0.2),
                "audio": Color(red: 0.7, green: 0.2, blue: 0.7),
                "image": Color(red: 0.2, green: 0.5, blue: 0.9),
                "document": Color(red: 0.5, green: 0.5, blue: 0.5),
                "other": Color(red: 0.4, green: 0.4, blue: 0.4),
            ]
        case .ocean:
            return [
                "app": Color(red: 0.0, green: 0.4, blue: 0.8),
                "archive": Color(red: 0.0, green: 0.6, blue: 0.8),
                "video": Color(red: 0.2, green: 0.7, blue: 0.6),
                "audio": Color(red: 0.0, green: 0.5, blue: 0.6),
                "image": Color(red: 0.0, green: 0.8, blue: 0.8),
                "document": Color(red: 0.4, green: 0.5, blue: 0.6),
                "other": Color(red: 0.3, green: 0.4, blue: 0.5),
            ]
        case .forest:
            return [
                "app": Color(red: 0.2, green: 0.5, blue: 0.3),
                "archive": Color(red: 0.4, green: 0.5, blue: 0.2),
                "video": Color(red: 0.5, green: 0.4, blue: 0.2),
                "audio": Color(red: 0.3, green: 0.4, blue: 0.2),
                "image": Color(red: 0.2, green: 0.6, blue: 0.5),
                "document": Color(red: 0.5, green: 0.5, blue: 0.4),
                "other": Color(red: 0.4, green: 0.4, blue: 0.3),
            ]
        }
    }
}
