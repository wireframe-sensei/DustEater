import SwiftUI

/// Apple-inspired design system for DustEater.
enum DustEaterTheme {
    // MARK: - Colors
    enum Colors {
        static let accent = Color(red: 0.0, green: 0.48, blue: 1.0) // Apple blue
        static let directory = Color(red: 0.2, green: 0.6, blue: 1.0)
        static let file = Color.secondary
        static let divider = Color(nsColor: .separatorColor)
        static let background = Color(nsColor: .controlBackgroundColor)
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Typography
    enum Typography {
        static let title1 = Font.system(size: 28, weight: .bold)
        static let title2 = Font.system(size: 22, weight: .bold)
        static let title3 = Font.system(size: 20, weight: .semibold)
        static let headline = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .regular)
    }
}
