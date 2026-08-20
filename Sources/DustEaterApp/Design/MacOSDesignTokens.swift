import SwiftUI
import AppKit

/// Design tokens with no SwiftUI/AppKit semantic equivalent, per the macOS
/// HIG design system kit (`.claude/skills/macos-hig-design-system`).
extension Font {
    /// Interface chrome - button labels, menu items, toolbar labels, and
    /// sidebar/table rows. The kit uses Medium 13pt for nearly all control
    /// chrome (108 of 111 button labels, 88 menu items, 126 toolbar labels,
    /// 192 sidebar items); no built-in SwiftUI semantic style provides
    /// Medium weight - `.body` is Regular, `.headline` is Bold.
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
    /// `Global/Radius` - the general control corner radius at this size.
    /// This is *not* what a bordered button uses at Large/XL - see `isCapsule`.
    let cornerRadius: CGFloat
    let fontSize: CGFloat
    /// `Button/Radius` aliases `Global/Radius` at Mini/Small/Medium, but
    /// becomes `1000` (a full capsule) at Large and ExtraLarge - the
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

    /// The shape a *button-style* custom control should draw itself with -
    /// a full capsule at Large/XL per `Button/Radius`, a rounded rect below
    /// that. Cards and panels should use `cornerRadius` directly instead.
    var buttonShape: AnyShape {
        isCapsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension EnvironmentValues {
    /// Derived from the ambient `\.controlSize` - set `.controlSize()` on a
    /// container and every custom control beneath it picks up the matching
    /// metrics automatically, the same way system controls do.
    var controlMetrics: ControlMetrics {
        ControlMetrics(controlSize)
    }
}

/// Builds a `Color` that resolves its RGBA per-appearance, the same way a
/// dynamic `NSColor` would - used below for the one color in this file that
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
    /// `Progress Bars/Track - Stroke` - #000 @7% light / #FFF @4% dark.
    /// `.quaternaryLabelColor` (10%) is the nearest semantic color but the
    /// kit specifies a fainter track than that, so this is a real gap, not
    /// laziness about reaching for the system color first (C4).
    static let progressTrack = adaptiveColor(light: (0, 0, 0, 0.07), dark: (1, 1, 1, 0.04))

    /// `Fills/Opaque Tertiary` - the Cleanup screen's card background
    /// (finding groups, the scanning card, review/receipt panels). Per the
    /// design handoff's token section, the opaque fill scale runs primary
    /// 10% down to quinary 2% in five even steps - tertiary is the middle
    /// step, 6%. No system `NSColor` sits at 6%; `.quaternarySystemFill`
    /// (nearest semantic candidate) doesn't publish a fixed percentage and
    /// visually reads lighter than this kit's card fill, so - same
    /// reasoning as `progressTrack` above - this is a real gap, not
    /// laziness about reaching for a system color first.
    static let opaqueTertiaryFill = adaptiveColor(light: (0, 0, 0, 0.06), dark: (1, 1, 1, 0.06))

    /// `Fills/Opaque Quaternary` - one step lighter than `opaqueTertiaryFill`
    /// on the same five-step 10%->2% scale (primary 10, secondary 8,
    /// tertiary 6, quaternary 4, quinary 2). Used for the welcome flow's
    /// upcoming-step indicator bars, where an unreached step needs to read
    /// as visibly fainter than the tertiary-fill cards around it.
    static let opaqueQuaternaryFill = adaptiveColor(light: (0, 0, 0, 0.04), dark: (1, 1, 1, 0.04))
}

/// Treemap tile geometry with no HIG/control-size equivalent - these are
/// data-visualization decisions (tile rounding, hover emphasis, label
/// legibility cutoffs), not control chrome, so they don't belong on the
/// `ControlMetrics` scale above (D8, D9).
enum TreemapMetrics {
    /// Corner radius for both the resting-state tile fill and the hover
    /// highlight - deliberately tiny; treemap tiles read as a dense mosaic,
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

/// Tooltip geometry with no HIG token - this app's tooltip is a custom
/// SwiftUI overlay (not `.help()`), so its size and cursor-relative offset
/// are just this component's own layout, not derived from any control size (D7).
enum TooltipMetrics {
    static let width: CGFloat = 200
    /// Offset from the mouse location so the tooltip doesn't sit directly
    /// under the pointer.
    static let offsetX: CGFloat = 20
    static let offsetY: CGFloat = -50
}

/// Card geometry for the Cleanup / Review / Receipt screens, with no HIG
/// control-size equivalent - these are surface decisions (which radius a
/// card at a given nesting level uses), not control chrome, so they
/// deliberately sit outside `ControlMetrics` the same way `TreemapMetrics`
/// does: routing a card through `ControlMetrics.isCapsule` at Large/XL would
/// turn it into a giant pill.
enum CleanupMetrics {
    /// Finding-group cards and the scanning card - the design handoff's
    /// largest card radius tier.
    static let findingCardRadius: CGFloat = 14
    /// Secondary panels: rebuild-commands card, "Never touched" card, the
    /// receipt's before/after card.
    static let panelCardRadius: CGFloat = 12
    /// Row-level cards: Review's grouped item rows, the filter bar.
    static let rowCardRadius: CGFloat = 10
    static let disclosureRotationDuration: Double = 0.12
    /// The Scanning card's indeterminate ring - diameter and one full
    /// rotation's duration, per the design handoff's Motion section.
    static let scanningRingDiameter: CGFloat = 34
    static let scanningRingRotationDuration: Double = 1.4
    /// "200ms progress fills" per the handoff's Motion section - applied
    /// here to numeric values that climb as findings stream in (the
    /// sidebar's reclaimable total, the scanning card's "Found so far"
    /// figure), not a literal progress bar.
    static let progressFillDuration: Double = 0.2
}

/// Geometry for Explore's Type board / Type detail / preview pane, per the
/// design handoff's §4b/§4c. Kept separate from `CleanupMetrics` even
/// though both are "card geometry with no `ControlMetrics` equivalent" -
/// these describe a different screen's own surfaces (tiles, a fixed-width
/// preview pane, table columns) and grouping them under the Cleanup name
/// would misdescribe what they're for.
enum ExploreMetrics {
    static let tileMinHeight: CGFloat = 168
    static let tileRadius: CGFloat = 14
    static let tileIconSize: CGFloat = 34
    static let tileIconRadius: CGFloat = 9
    static let backButtonSize: CGFloat = 24
    static let filterBarRadius: CGFloat = 10
    static let rowRadius: CGFloat = 8
    static let lastOpenedColumnWidth: CGFloat = 96
    static let sizeColumnWidth: CGFloat = 88
    static let previewPaneWidth: CGFloat = 268
    static let previewPaneRadius: CGFloat = 12
    static let previewThumbnailHeight: CGFloat = 168
}

extension Animation {
    /// The Scanning card's indeterminate ring rotation - `cubic-bezier(0.4,
    /// 0, 0.2, 1)` over `CleanupMetrics.scanningRingRotationDuration`,
    /// repeating forever, per the design handoff's Motion section
    /// verbatim. Swift's `timingCurve` takes the same four control-point
    /// values a CSS `cubic-bezier()` does.
    static let scanningRingRotation = Animation
        .timingCurve(0.4, 0, 0.2, 1, duration: CleanupMetrics.scanningRingRotationDuration)
        .repeatForever(autoreverses: false)
}

extension View {
    /// A 1pt inset stroke using `Labels/Quaternary` - the hairline ring
    /// every Cleanup/Review/Receipt card is drawn with, per the design
    /// handoff. `.quaternaryLabelColor` is already documented (see
    /// `Color.progressTrack` above) as the system color matching this kit's
    /// 10% quaternary label alpha exactly, so this reuses it directly rather
    /// than adding another custom token.
    func hairlineRing(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color(nsColor: .quaternaryLabelColor), lineWidth: 1)
        )
    }
}

extension View {
    /// Real Liquid Glass on macOS 26+, falling back to the given `Material`
    /// everywhere else. Only for surfaces this app draws itself - sidebars,
    /// toolbars, and other real system chrome already render with genuine
    /// Liquid Glass automatically on macOS 26 and need no help here (per
    /// `swift.md`: "prefer the built-in `.glassEffect(...)` over
    /// reconstructing it").
    ///
    /// `#available` only gates *runtime* behavior - `.glassEffect` still has
    /// to be a real compiled symbol, which requires building against the
    /// macOS 26 SDK (bundled with Xcode 26 / Swift 6.2+). A toolchain older
    /// than that - e.g. GitHub's `macos-15` hosted runner as of this
    /// writing, still on Xcode 16.x - doesn't declare the symbol at all, so
    /// `#available` alone isn't enough; this fails to *compile* there, not
    /// just to run. `#if compiler(>=6.2)` excludes the whole branch from
    /// being type-checked on such toolchains, leaving only the Material
    /// fallback - confirmed against a real CI failure on macos-15 runners.
    @ViewBuilder
    func glassBackground(_ material: Material, cornerRadius: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(material)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        self
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
}

/// Stable proxy for the design kit's "Scroll Edge Effect - Hard/Soft"
/// tokens. Real `ScrollEdgeEffectStyle` (SwiftUI) only exists in the macOS
/// 26 SDK - confirmed against the actual `.swiftinterface`, which marks
/// both the type and the modifier `@available(macOS 26, *)` - so, same
/// reasoning as `glassBackground` above, call sites need a stable type
/// that compiles on every toolchain; the real one is resolved only inside
/// the availability-gated branch of `scrollEdgeEffect(_:for:)` below.
enum EdgeEffectStyle {
    /// For content that scrolls under fixed, opaque-ish chrome (a toolbar,
    /// a segmented control) - a firmer fade.
    case hard
    /// For content that scrolls under floating glass.
    case soft
}

extension View {
    /// A gradient fade where scrollable content passes under fixed chrome,
    /// replacing a hard `Divider()` line - per the design handoff: "apply a
    /// gradient fade at that edge rather than a hard divider line." Falls
    /// back to a no-op on a toolchain/OS that doesn't have the real API:
    /// content still scrolls and clips correctly via the container's own
    /// bounds, it just won't fade at the edge.
    @ViewBuilder
    func scrollEdgeEffect(_ style: EdgeEffectStyle, for edges: Edge.Set) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(style == .hard ? .hard : .soft, for: edges)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
