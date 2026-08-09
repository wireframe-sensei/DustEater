# Implementing in Swift (SwiftUI / AppKit)

Read this before writing any Swift against this design system.

## The governing principle

**AppKit already implements most of this system. Use the system API; fall back to raw tokens
only where no equivalent exists.**

The kit's tokens and AppKit's semantic colors are the same values — `Labels/Primary` is
`#000 @85%`, which is exactly `NSColor.labelColor`. But the system colors additionally track
things a hardcoded hex cannot:

- the user's chosen accent color (System Settings → Appearance)
- Increase Contrast and Reduce Transparency accessibility settings
- window focus and key/inactive state
- appearance changes, without a view rebuild

So hardcoding `Color(hex: 0x000000).opacity(0.85)` instead of `.primary` produces an app that
looks identical in a screenshot and is *less* native in use. This is the single most important
thing to get right in a Swift implementation, and it inverts the advice you'd follow on web.

## Color mapping

| Kit token | Use in Swift | Notes |
|---|---|---|
| `Labels/Primary` | `.primary` / `NSColor.labelColor` | Exact match at 85% |
| `Labels/Secondary` | `.secondary` / `.secondaryLabelColor` | |
| `Labels/Tertiary` | `NSColor.tertiaryLabelColor` | Disabled + placeholder |
| `Labels/Quaternary` | `NSColor.quaternaryLabelColor` | |
| `Labels/Quinary` | `NSColor.quinaryLabelColor` | Verify deployment target; newer addition |
| `Labels/White` | `.white` | |
| `Grays/Gray` | `NSColor.systemGray` | Matches `#8E8E93` / `#98989F` |
| `Accents/*` | `NSColor.systemBlue`, `.systemRed`, … | Twelve system colors, all dynamic |
| Current accent | `.tint` / `NSColor.controlAccentColor` | **Never hardcode blue** |
| `Window Background` | `NSColor.windowBackgroundColor` | |
| Control background | `NSColor.controlBackgroundColor` | |
| `Material/*` | SwiftUI `Material` — see below | |
| Selection | `NSColor.selectedContentBackgroundColor` | Handles focus automatically |
| Separators | `NSColor.separatorColor` | |
| `Accents - Vibrant/*` | `Color.vibrantBlue` etc. from the tokens file | No system equivalent |
| `Fills - Opaque/*` | `Color.fillPrimary` etc. | macOS has no public `systemFill` ladder |
| `Miscellaneous/*` | `Color.misc*` | Internal Apple values |

Prefer the semantic role over the literal color: `.selectedContentBackgroundColor` rather than
reaching for the accent directly, because the system varies it by focus.

## Control size

The kit's five sizes map exactly onto SwiftUI's `ControlSize`:

| Kit | SwiftUI |
|---|---|
| Mini | `.mini` |
| Small | `.small` |
| Medium | `.regular` |
| Large | `.large` |
| XL | `.extraLarge` |

Set it once on a container and let it inherit — don't thread a size parameter through your view
tree by hand:

```swift
VStack { /* controls */ }
    .controlSize(.regular)
```

In custom controls, read metrics from the environment:

```swift
@Environment(\.controlSize) private var controlSize
private var m: ControlMetrics { .metrics(for: controlSize) }
```

Note `m.isCapsule` — at Large and XL the kit's button radius jumps to `1000`, i.e. a capsule.
Use `Capsule()` rather than `RoundedRectangle(cornerRadius: 1000)`.

## Typography

SwiftUI's semantic fonts already match the kit's scale on macOS (`.body` is 13pt). Use them
rather than fixed point sizes, so accessibility text sizing keeps working.

The one correction to apply everywhere: **interface chrome is Medium (500), not Regular.**

```swift
Text("Save").font(.control)   // .system(.body).weight(.medium)
Text(article).font(.content)  // .system(.body)
```

| Kit style | SwiftUI |
|---|---|
| Large Title | `.largeTitle` |
| Title 1 / 2 / 3 | `.title` / `.title2` / `.title3` |
| Headline | `.headline` |
| Body | `.body` |
| Callout | `.callout` |
| Subheadline | `.subheadline` |
| Footnote | `.footnote` |
| Caption 1 / 2 | `.caption` / `.caption2` |

Don't bundle SF Pro in the app — the system font *is* SF Pro. `Font.system` gets you the
correct optical sizing and the licensing question never arises.

## Materials

The kit's five material variants map directly:

| Kit | SwiftUI |
|---|---|
| Ultra Thin | `.ultraThinMaterial` |
| Thin | `.thinMaterial` |
| Medium | `.regularMaterial` |
| Thick | `.thickMaterial` |
| Ultra Thick | `.ultraThickMaterial` |

```swift
.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
```

Use these instead of the extracted blur radii and translucent fills. They handle Reduce
Transparency, which a hand-rolled `.blur()` does not. In AppKit, `NSVisualEffectView` with the
matching `.material` and `blendingMode = .behindWindow`.

For Liquid Glass on macOS 26+, prefer the built-in `.glassEffect(...)` over reconstructing it
from the parameters in `LiquidGlass`. Those values are there for verification and for
hand-rolled cases; check availability for your deployment target.

## Window focus

Nearly every component in the kit has an `Active` axis. SwiftUI exposes this:

```swift
@Environment(\.controlActiveState) private var activeState
// .key, .active, .inactive
```

System controls handle it themselves. Custom controls must opt in — desaturate accents toward
`NSColor.systemGray`, switch selection to the inactive variant, and shallow the window shadow.
This is one of the strongest native-feel signals and is invisible until you click away.

## What to build vs. what to use

**Use the system control.** `Button`, `Toggle`, `Picker`, `Slider`, `Stepper`, `TextField`,
`DisclosureGroup`, `NavigationSplitView` for sidebars, `.toolbar`, `.popover`, `.sheet`,
`.contextMenu`. These already encode every variant axis in `references/components.md` —
including states and focus behavior you would otherwise reimplement badly.

Reach for a `ButtonStyle` or `ToggleStyle` before building a control from scratch:

```swift
struct BorderedProminentDestructive: ButtonStyle { /* ... */ }
```

**Build custom only when** the kit has a component with no SwiftUI counterpart, or the design
genuinely diverges. Then use `ControlMetrics` for geometry and semantic colors for fills.

Map the kit's button styles onto what SwiftUI provides: `.bordered`, `.borderedProminent`,
`.borderless`, plus `.tint(...)` for the tinted and destructive variants and `role: .destructive`
on the `Button` itself.

## Order of work

1. Audit — inventory existing views and find hardcoded colors, fonts, and dimensions.
2. Replace hardcoded colors with semantic `NSColor`/`Color` values. Biggest win, lowest risk.
3. Fix typography — semantic fonts, Medium weight on chrome.
4. Set `.controlSize` at container level; delete manual size plumbing.
5. Replace hand-rolled blurs and translucent fills with `Material`.
6. Add `controlActiveState` handling to custom controls.
7. Only then build custom components, using `ControlMetrics`.

Steps 2–5 usually account for most of the visible gap and touch little logic.
