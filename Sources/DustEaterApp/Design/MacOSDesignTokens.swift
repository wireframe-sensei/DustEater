import SwiftUI

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
