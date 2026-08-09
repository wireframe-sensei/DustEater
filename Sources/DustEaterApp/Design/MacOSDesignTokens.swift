import SwiftUI
import AppKit

/// Design tokens with no SwiftUI/AppKit semantic equivalent, per the macOS
/// HIG design system kit (`.claude/skills/macos-hig-design-system`).
extension Font {
    /// Interface chrome — button labels, menu items, toolbar labels, and
    /// sidebar/table rows. The kit uses Medium 13pt for nearly all control
    /// chrome (108 of 111 button labels, 88 menu items, 126 toolbar labels,
    /// 192 sidebar items); no built-in SwiftUI semantic style provides
    /// Medium weight — `.body` is Regular, `.headline` is Bold.
    static let control = Font.system(size: 13, weight: .medium)
}

/// Per-size metrics from the kit's `Global` and `Button` sizing tables,
/// resolved from the ambient `ControlSize`. Read it the same way any other
/// environment-derived value is read:
///
///     @Environment(\.controlMetrics) private var metrics
///
/// so a custom-drawn control automatically tracks whatever `.controlSize()`
/// its container set, the same way a real `Button` or `TextField` would.
struct ControlMetrics: Equatable {
    let height: CGFloat
    /// `Global/Radius` — the general control corner radius at this size.
    /// This is *not* what a bordered button uses at Large/XL — see `isCapsule`.
    let cornerRadius: CGFloat
    let fontSize: CGFloat
    /// `Button/Radius` aliases `Global/Radius` at Mini/Small/Medium, but
    /// becomes `1000` (a full capsule) at Large and ExtraLarge — the
    /// macOS 26+ pill button shape. Only meaningful for a control that's
    /// actually drawing itself as a compact button; a large custom card or
    /// panel sized via `.controlSize(.extraLarge)` should use `cornerRadius`
    /// directly and ignore this flag, or it'll turn into a giant pill.
    let isCapsule: Bool

    init(_ controlSize: ControlSize) {
        switch controlSize {
        case .mini:
            height = 16; cornerRadius = 4; fontSize = 10; isCapsule = false
        case .small:
            height = 20; cornerRadius = 5; fontSize = 11; isCapsule = false
        case .regular:
            height = 24; cornerRadius = 6; fontSize = 13; isCapsule = false
        case .large:
            height = 28; cornerRadius = 7; fontSize = 13; isCapsule = true
        case .extraLarge:
            height = 36; cornerRadius = 9; fontSize = 13; isCapsule = true
        @unknown default:
            height = 24; cornerRadius = 6; fontSize = 13; isCapsule = false
        }
    }

    /// The shape a *button-style* custom control should draw itself with —
    /// a full capsule at Large/XL per `Button/Radius`, a rounded rect below
    /// that. Cards and panels should use `cornerRadius` directly instead.
    var buttonShape: AnyShape {
        isCapsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension EnvironmentValues {
    /// Derived from the ambient `\.controlSize` — set `.controlSize()` on a
    /// container and every custom control beneath it picks up the matching
    /// metrics automatically, the same way system controls do.
    var controlMetrics: ControlMetrics {
        ControlMetrics(controlSize)
    }
}

/// Builds a `Color` that resolves its RGBA per-appearance, the same way a
/// dynamic `NSColor` would — used below for the one color in this file that
/// has no system equivalent to just delegate to.
private func adaptiveColor(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                            dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    })
}

extension Color {
    /// `Progress Bars/Track - Stroke` — #000 @7% light / #FFF @4% dark.
    /// `.quaternaryLabelColor` (10%) is the nearest semantic color but the
    /// kit specifies a fainter track than that, so this is a real gap, not
    /// laziness about reaching for the system color first (C4).
    static let progressTrack = adaptiveColor(light: (0, 0, 0, 0.07), dark: (1, 1, 1, 0.04))
}

/// Treemap tile geometry with no HIG/control-size equivalent — these are
/// data-visualization decisions (tile rounding, hover emphasis, label
/// legibility cutoffs), not control chrome, so they don't belong on the
/// `ControlMetrics` scale above (D8, D9).
enum TreemapMetrics {
    /// Corner radius for both the resting-state tile fill and the hover
    /// highlight — deliberately tiny; treemap tiles read as a dense mosaic,
    /// not individually rounded cards.
    static let tileCornerRadius: CGFloat = 1
    /// Stroke width of the accent/gray hover outline drawn around the
    /// currently-hovered tile.
    static let hoverStrokeLineWidth: CGFloat = 1.2
    /// Opacity of the soft drop-shadow fill drawn just inside a hovered
    /// tile, to lift it visually off its neighbors.
    static let hoverShadowOpacity: Double = 0.1
    /// Minimum tile dimension (points) before any label is drawn at all.
    static let labelThresholdMinimum: CGFloat = 60
    /// Minimum tile dimension before the byte-size sub-label also appears.
    static let labelThresholdShowsSize: CGFloat = 100
    /// Minimum tile dimension before the name label steps up from Caption
    /// to Callout.
    static let labelThresholdLargeFont: CGFloat = 120
}

/// Tooltip geometry with no HIG token — this app's tooltip is a custom
/// SwiftUI overlay (not `.help()`), so its size and cursor-relative offset
/// are just this component's own layout, not derived from any control size (D7).
enum TooltipMetrics {
    static let width: CGFloat = 200
    /// Offset from the mouse location so the tooltip doesn't sit directly
    /// under the pointer.
    static let offsetX: CGFloat = 20
    static let offsetY: CGFloat = -50
}
