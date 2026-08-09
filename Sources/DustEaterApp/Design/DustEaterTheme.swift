import SwiftUI

/// Apple-inspired design system for DustEater.
enum DustEaterTheme {
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
    // Content text - titles, descriptions, data values. Interface chrome
    // (buttons, menus, toolbars, sidebar/table rows) uses `Font.control`
    // instead, defined in MacOSDesignTokens.swift.
    enum Typography {
        static let title1 = Font.largeTitle.bold()
        static let title2 = Font.title.bold()
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let caption = Font.caption
    }
}
