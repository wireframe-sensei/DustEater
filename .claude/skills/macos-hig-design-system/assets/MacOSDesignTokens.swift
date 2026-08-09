// MacOSDesignTokens.swift
// Generated from the Apple Design Resources macOS UI kit.
//
// IMPORTANT — read before using this file.
//
// This file deliberately does NOT redefine colors that AppKit already provides
// semantically. NSColor.labelColor, .secondaryLabelColor, .controlAccentColor and
// friends are exact matches for the kit's tokens AND additionally track the user's
// accent choice, Increase Contrast, Reduce Transparency, and window focus. Hardcoding
// the kit's hex values over them would make the app less native, not more.
//
// Use this file only for: control metrics, Liquid Glass parameters, structural
// dimensions, and the handful of colors with no AppKit equivalent.
// See references/swift.md for the full mapping.

import SwiftUI

// MARK: - Control sizing
// The kit defines every control across five sizes. These map 1:1 onto SwiftUI's
// ControlSize, so read metrics from the current environment rather than passing
// a size around manually.

public struct ControlMetrics: Sendable {
    public let height: CGFloat
    public let cornerRadius: CGFloat
    public let fontSize: CGFloat
    public let paddingHorizontal: CGFloat
    public let paddingVertical: CGFloat
    public let fieldInsetLeading: CGFloat
    public let fieldInsetTrailing: CGFloat
    public let checkboxWidth: CGFloat
    public let checkboxRadius: CGFloat
    public let radioWidth: CGFloat
    public let switchTrackWidth: CGFloat
    public let switchTrackHeight: CGFloat
    public let switchKnobWidth: CGFloat
    public let switchKnobHeight: CGFloat
    public let switchKnobInset: CGFloat
    public let stepperWidth: CGFloat
    public let menuItemHeight: CGFloat

    /// `true` for Large and XL, where buttons become fully rounded capsules.
    public var isCapsule: Bool { cornerRadius >= 999 }
}

public extension ControlMetrics {
    static let mini = ControlMetrics(
        height: 16.0, cornerRadius: 4.0, fontSize: 10.0,
        paddingHorizontal: 7.0, paddingVertical: 2.0,
        fieldInsetLeading: 6.0, fieldInsetTrailing: 6.0,
        checkboxWidth: 12.0, checkboxRadius: 3.5, radioWidth: 12.0,
        switchTrackWidth: 36.0, switchTrackHeight: 16.0,
        switchKnobWidth: 21.0, switchKnobHeight: 13.0, switchKnobInset: 1.5,
        stepperWidth: 13.0, menuItemHeight: 19.0)
    static let small = ControlMetrics(
        height: 20.0, cornerRadius: 5.0, fontSize: 11.0,
        paddingHorizontal: 10.0, paddingVertical: 3.0,
        fieldInsetLeading: 6.0, fieldInsetTrailing: 6.0,
        checkboxWidth: 14.0, checkboxRadius: 4.5, radioWidth: 14.0,
        switchTrackWidth: 44.0, switchTrackHeight: 20.0,
        switchKnobWidth: 26.0, switchKnobHeight: 16.0, switchKnobInset: 2.0,
        stepperWidth: 17.0, menuItemHeight: 22.0)
    static let medium = ControlMetrics(
        height: 24.0, cornerRadius: 6.0, fontSize: 13.0,
        paddingHorizontal: 16.0, paddingVertical: 4.0,
        fieldInsetLeading: 8.0, fieldInsetTrailing: 8.0,
        checkboxWidth: 16.0, checkboxRadius: 5.5, radioWidth: 16.0,
        switchTrackWidth: 54.0, switchTrackHeight: 24.0,
        switchKnobWidth: 32.0, switchKnobHeight: 20.0, switchKnobInset: 2.0,
        stepperWidth: 20.0, menuItemHeight: 24.0)
    static let large = ControlMetrics(
        height: 28.0, cornerRadius: 1000.0, fontSize: 13.0,
        paddingHorizontal: 16.0, paddingVertical: 6.0,
        fieldInsetLeading: 8.0, fieldInsetTrailing: 8.0,
        checkboxWidth: 18.0, checkboxRadius: 6.5, radioWidth: 18.0,
        switchTrackWidth: 64.0, switchTrackHeight: 28.0,
        switchKnobWidth: 38.0, switchKnobHeight: 24.0, switchKnobInset: 2.0,
        stepperWidth: 23.0, menuItemHeight: 24.0)
    static let extraLarge = ControlMetrics(
        height: 36.0, cornerRadius: 1000.0, fontSize: 13.0,
        paddingHorizontal: 16.0, paddingVertical: 10.0,
        fieldInsetLeading: 10.0, fieldInsetTrailing: 10.0,
        checkboxWidth: 18.0, checkboxRadius: 6.5, radioWidth: 18.0,
        switchTrackWidth: 80.0, switchTrackHeight: 36.0,
        switchKnobWidth: 47.0, switchKnobHeight: 30.0, switchKnobInset: 3.0,
        stepperWidth: 30.0, menuItemHeight: 24.0)

    /// Metrics for a SwiftUI ControlSize.
    static func metrics(for size: ControlSize) -> ControlMetrics {
        switch size {
        case .mini: return .mini
        case .small: return .small
        case .regular: return .medium
        case .large: return .large
        case .extraLarge: return .extraLarge
        @unknown default: return .medium
        }
    }
}

/// Read control metrics straight from the environment:
///     @Environment(\.controlSize) private var controlSize
///     var metrics: ControlMetrics { .metrics(for: controlSize) }
public extension EnvironmentValues {
    var controlMetrics: ControlMetrics { .metrics(for: controlSize) }
}

// MARK: - Colors without an AppKit equivalent
//
// Everything omitted here has a system counterpart — see references/swift.md.
// These are defined as adaptive NSColors so they still respond to appearance changes.

private func adaptive(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                      dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    })
}

public extension Color {
    // Accent hues adjusted for use on glass and materials. Prefer Color.accentColor on opaque surfaces.
    static let vibrantBlue = adaptive(light: (0.0000, 0.4706, 0.9412, 1.000), dark: (0.0392, 0.6000, 1.0000, 1.000))
    static let vibrantBrown = adaptive(light: (0.6196, 0.4510, 0.3294, 1.000), dark: (0.7608, 0.5882, 0.4471, 1.000))
    static let vibrantCyan = adaptive(light: (0.0000, 0.6706, 0.8118, 1.000), dark: (0.2784, 0.8471, 0.9882, 1.000))
    static let vibrantGreen = adaptive(light: (0.1490, 0.7490, 0.3020, 1.000), dark: (0.2314, 0.8588, 0.3882, 1.000))
    static let vibrantIndigo = adaptive(light: (0.3608, 0.3137, 0.9020, 1.000), dark: (0.4431, 0.3882, 1.0000, 1.000))
    static let vibrantMint = adaptive(light: (0.0000, 0.7412, 0.6627, 1.000), dark: (0.1765, 0.8784, 0.8039, 1.000))
    static let vibrantOrange = adaptive(light: (0.9608, 0.5255, 0.1451, 1.000), dark: (1.0000, 0.6196, 0.2000, 1.000))
    static let vibrantPink = adaptive(light: (0.9608, 0.1373, 0.2941, 1.000), dark: (1.0000, 0.2549, 0.4118, 1.000))
    static let vibrantPurple = adaptive(light: (0.7176, 0.1686, 0.7882, 1.000), dark: (0.9020, 0.2784, 0.9882, 1.000))
    static let vibrantRed = adaptive(light: (0.9608, 0.1843, 0.1961, 1.000), dark: (1.0000, 0.2784, 0.2784, 1.000))
    static let vibrantTeal = adaptive(light: (0.0000, 0.7020, 0.7490, 1.000), dark: (0.1765, 0.8431, 0.8784, 1.000))
    static let vibrantYellow = adaptive(light: (0.9608, 0.7608, 0.0000, 1.000), dark: (1.0000, 0.8784, 0.0784, 1.000))
}

public extension Color {
    // Component-specific values Apple exposes internally but does not vend publicly.
    static let miscAlertsOverlay = adaptive(light: (0.6706, 0.6706, 0.6706, 0.600), dark: (0.0902, 0.0902, 0.0902, 0.620))
    static let miscProgressBarsTrackStroke = adaptive(light: (0.0000, 0.0000, 0.0000, 0.070), dark: (1.0000, 1.0000, 1.0000, 0.040))
    static let miscScrollbar = adaptive(light: (0.0000, 0.0000, 0.0000, 0.500), dark: (1.0000, 1.0000, 1.0000, 0.550))
    static let miscSidebarLabelInactive = adaptive(light: (0.5294, 0.5294, 0.5294, 1.000), dark: (0.4000, 0.4000, 0.4000, 1.000))
    static let miscTablesAlternatingRowColor = adaptive(light: (0.0000, 0.0000, 0.0000, 0.050), dark: (1.0000, 1.0000, 1.0000, 0.050))
    static let miscTablesBgSelectedActive = adaptive(light: (0.0039, 0.3961, 0.8863, 1.000), dark: (0.0039, 0.3451, 0.8235, 1.000))
    static let miscTablesBgSelectedInactive = adaptive(light: (0.0000, 0.0000, 0.0000, 0.140), dark: (1.0000, 1.0000, 1.0000, 0.180))
    static let miscTablesColumnSeparator = adaptive(light: (0.0000, 0.0000, 0.0000, 0.100), dark: (1.0000, 1.0000, 1.0000, 0.100))
    static let miscTooltipsInnerStroke = adaptive(light: (1.0000, 1.0000, 1.0000, 0.000), dark: (1.0000, 1.0000, 1.0000, 0.150))
    static let miscTooltipsSidebarBgActive = adaptive(light: (0.8549, 0.9020, 0.9490, 1.000), dark: (0.0784, 0.0824, 0.0902, 1.000))
    static let miscTooltipsSidebarBgInactive = adaptive(light: (0.9294, 0.9569, 0.9804, 1.000), dark: (0.0745, 0.0784, 0.0784, 1.000))
}

public extension Color {
    // Fill ramp. AppKit has no public macOS equivalent to the iOS systemFill ladder.
    static let fillPrimary = adaptive(light: (0.0000, 0.0000, 0.0000, 0.100), dark: (1.0000, 1.0000, 1.0000, 0.100))
    static let fillQuaternary = adaptive(light: (0.0000, 0.0000, 0.0000, 0.030), dark: (1.0000, 1.0000, 1.0000, 0.030))
    static let fillQuinary = adaptive(light: (0.0000, 0.0000, 0.0000, 0.020), dark: (1.0000, 1.0000, 1.0000, 0.020))
    static let fillSecondary = adaptive(light: (0.0000, 0.0000, 0.0000, 0.080), dark: (1.0000, 1.0000, 1.0000, 0.080))
    static let fillTertiary = adaptive(light: (0.0000, 0.0000, 0.0000, 0.050), dark: (1.0000, 1.0000, 1.0000, 0.050))
}

// MARK: - Liquid Glass
// Authored parameters from the kit. On macOS 26+ prefer SwiftUI's built-in
// `.glassEffect(...)`, which implements this properly; use these values only when
// hand-rolling a custom material or verifying a result.

public enum LiquidGlass {
    public static let depthMediumAndLarge: CGFloat = 30.0
    public static let depthRegular: CGFloat = 30.0
    public static let dispersion: CGFloat = 20.0
    public static let frostLarge: CGFloat = 16.0
    public static let frostMedium: CGFloat = 16.0
    public static let frostRegular: CGFloat = 6.0
    public static let lightAngle: CGFloat = 0.0
    public static let opacity: CGFloat = 25.0
    public static let refraction: CGFloat = 70.0
    public static let splayMediumAndLarge: CGFloat = 20.0
    public static let splayRegular: CGFloat = 20.0
}

// MARK: - Structural dimensions

public enum Structure {
    public static let windowCornerRadius: CGFloat = 16
    public static let toolbarHeightUnifiedCompact: CGFloat = 40
    public static let toolbarHeightDefault: CGFloat = 44
    public static let toolbarHeightExpanded: CGFloat = 52
    public static let sidebarItemHeightSmall: CGFloat = 24
    public static let sidebarItemHeightMedium: CGFloat = 32
    public static let sidebarItemHeightLarge: CGFloat = 36
    public static let sidebarItemRadius: CGFloat = 5
    public static let sidebarItemRadiusLarge: CGFloat = 8
    public static let menuItemRadius: CGFloat = 8
    public static let groupBoxRadius: CGFloat = 12
    public static let scrollbarThickness: CGFloat = 6
}

// MARK: - Elevation
// Match the kit's shadow stacks. SwiftUI applies one shadow per modifier, so
// multi-layer shadows chain.

public extension View {
    func controlShadow() -> some View {
        shadow(color: .black.opacity(0.20), radius: 0.75, x: 0, y: 0.5)
    }
    func knobShadow() -> some View {
        shadow(color: .black.opacity(0.30), radius: 1.25, x: 0, y: 0.5)
    }
    func popoverShadow() -> some View {
        shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
            .shadow(color: .black.opacity(0.18), radius: 7.5, x: 0, y: 8)
    }
    /// Window shadow. Pass the current controlActiveState so an unfocused
    /// window drops to the much shallower inactive shadow, as the kit specifies.
    func windowShadow(active: Bool) -> some View {
        shadow(color: .black.opacity(active ? 0.30 : 0.05),
               radius: active ? 27 : 18, x: 0, y: active ? 18 : 3)
    }
}

// MARK: - Typography
// SwiftUI's semantic fonts already match the kit's scale on macOS (body is 13pt).
// Use Font.body, .title2, .caption and so on rather than fixed point sizes so
// Dynamic Type and accessibility settings keep working.
//
// The one thing to override: interface chrome is Medium (500), not Regular.
// 108 of 111 button labels in the kit are SF Pro Medium 13.

public extension Font {
    /// Control chrome: buttons, menus, toolbars, sidebars, table rows, fields.
    static var control: Font { .system(.body).weight(.medium) }
    /// Body and content text.
    static var content: Font { .system(.body) }
}

