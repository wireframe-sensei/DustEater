---
name: macos-hig-design-system
description: Build UI using the macOS 27 / Apple Human Interface Guidelines design system — the official Apple Design Resources kit, with its exact color tokens, five-tier control sizing, SF Pro type scale, Liquid Glass materials, and full component inventory. Use this skill whenever the user asks for a macOS-style, Mac-native, Apple-style, or "looks like a real Mac app" interface; whenever they mention macOS controls by name (sidebar, toolbar, popover, sheet, segmented control, disclosure, pull-down button, window controls, menu bar); and whenever they are designing or coding an app that should feel native to macOS, even if they don't say "design system." Also use it when reviewing existing UI for HIG compliance.
---

# macOS HIG Design System

This skill encodes the Apple Design Resources macOS UI kit — every color token, size token,
type style, material, and component variant, extracted directly from the source Figma file.

Use it to design and implement interfaces that are genuinely native-feeling, not
approximations. The difference between "kind of Mac-like" and correct is almost entirely in
the numbers, and the numbers are all here.

## Before you build anything

Work through these four decisions in order. They cascade — later decisions depend on earlier
ones, and getting the order wrong produces inconsistent UI.

1. **Appearance**: Light or Dark. Every color token has both. Never hardcode one.
2. **Control size**: Mini, Small, **Medium** (default), Large, or XL. This picks an entire
   column of the sizing table. One size per surface — do not mix Medium buttons with Small fields.
3. **Context**: `Content Area` or `Over-Glass`. Controls sitting on an opaque window body use
   the Content Area treatment; controls floating over media or glass use Over-Glass, which is
   more translucent and carries stronger edge highlights.
4. **Window state**: Active or Inactive. Affects accents, selection, and shadows.

If the user hasn't specified, default to: Light + Dark both supported, Medium, Content Area, Active.

## Reference files

Read the one you need — do not try to hold all of it in context at once.

| File | Read it when |
|---|---|
| `references/color-tokens.md` | Choosing any color. 71 tokens, Light + Dark. |
| `references/sizing-tokens.md` | Sizing any control. 68 tokens across 5 size columns. |
| `references/components.md` | Building a specific component — gives its exact variant axes. |
| `references/materials-and-effects.md` | Any floating surface, shadow, blur, or Liquid Glass. |
| `references/swift.md` | **Implementing in Swift. Read this first — it changes the rules.** |
| `assets/MacOSDesignTokens.swift` | Swift: control metrics, glass params, non-system colors. |
| `assets/tokens.css` | Implementing on web. Drop-in CSS custom properties, light + dark. |

## Non-negotiable rules

These are the rules that separate correct macOS UI from generic UI. Violating any one of them
is immediately visible to anyone who uses a Mac.

**Use semantic colors, never raw hex.** The system defines `Labels/Primary` as `#000 @85%`,
not `#262626`. The alpha is load-bearing — it lets text composite correctly over materials,
selections, and accent fills. Flattening it to opaque hex breaks every translucent surface
underneath. The same applies to every `Fills/*` and `Labels/*` token.

**Label hierarchy is four levels, and you use them in order.** Primary (85%) for content,
Secondary (50% / 55% dark) for supporting text, Tertiary (25%) for disabled and placeholder,
Quaternary (10%) for the faintest separators. Do not skip levels or invent a fifth.

**Type comes from the scale.** SF Pro, eleven styles, listed below. Body is 13px — not 14, not
16. macOS is a denser type environment than iOS or the web, and using web-scale type is the
single most common way a Mac app looks wrong.

**Accent color is user-configurable.** Blue is the default, but the system ships twelve accents
and the user picks one in System Settings. Never hardcode blue. Route every accent through one
token so it can be swapped. The `Accents - Vibrant` set is the same hues adjusted for use on
glass and materials — use those when the control is Over-Glass.

**Corner radii scale with control size.** `Global/Radius` is 4 / 5 / 6 / 7 / 9 across
Mini→XL. Large and XL buttons go fully rounded (`1000`), which is the macOS 26+ capsule shape.
A 6px radius on an XL button is wrong.

**Controls have four states, always.** Idle, Clicked, Disabled, and — where the control holds
a value — On/Off/Mixed. Checkboxes and radio buttons have a genuine Mixed state; do not
implement it as a visual hack.

**Every floating surface gets a material, not a solid fill.** Sidebars, toolbars, menus,
popovers, and notifications are translucent with a backdrop blur. A solid gray sidebar is the
second most common tell of a non-native app.

**Respect window focus.** See `materials-and-effects.md`.

## Type scale

SF Pro — the **unified** family (PostScript `SFPro-Regular`, `SFPro-Medium`, …), not the older
`SF Pro Text` / `SF Pro Display` split. Modern SF Pro carries a variable optical size axis and
switches automatically, so specify `"SF Pro"` and let the font handle it. Sizes in px,
line-heights fixed (not multipliers).

### Weight is the thing most people get wrong

The type-scale page of the kit documents styles in Regular and Semibold, but that is the
*abstract* scale for content text. Every actual control in the kit uses **Medium (500)**:

| Surface | Weight used | Count in kit |
|---|---|---|
| Button labels | Medium 13 | 108 of 111 |
| Menu items | Medium 13 | 88 |
| Toolbar labels | Medium 13 | 126 |
| Sidebar items | Medium 11 / 13 / 15 | 192 |
| Table rows | Medium 13 | 80 |
| Text fields | Medium 13 | all |

So: **Medium for interface chrome, Regular for body and content text, Bold for section headers
and the emphasized button in an alert.** Setting control labels to Regular is the most common
way a Mac UI looks subtly thin and wrong, and it is invisible until you put it next to a real
window. Medium is the single most-used style in the entire file (1,418 text nodes).

Semibold appears mainly at 10px in toolbars (small captions), and Heavy only in the Headline
style. SF Pro Rounded appears three times — it is not part of the core system.

| Style | Size / Line | Weights available |
|---|---|---|
| Large Title | 26 / 32 | Regular, Bold |
| Title 1 | 22 / 26 | Regular, Bold |
| Title 2 | 17 / 22 | Regular, Bold |
| Title 3 | 15 / 20 | Regular, Semibold |
| Headline | 13 / 16 | Bold, Heavy |
| **Body** | **13 / 16** | Regular, Semibold |
| Callout | 12 / 15 | Regular, Semibold |
| Subheadline | 11 / 14 | Regular, Semibold |
| Footnote | 10 / 13 | Regular, Semibold |
| Caption 1 | 10 / 13 | Regular, Semibold |
| Caption 2 | 10 / 13 | Regular, Semibold |

Letter spacing is 0 throughout. Body (13px) is the default size for all control labels at
Medium control size.

Font stack: `"SF Pro", -apple-system, BlinkMacSystemFont, sans-serif`. The fallbacks resolve to
the system SF on any Apple device, so they are not a downgrade there — they only matter for
non-Apple platforms. See the licensing note at the end before shipping SF Pro on the web.

## Control metrics at a glance (Medium)

The full table across all five sizes is in `references/sizing-tokens.md`. Medium is the default:

| Property | Value |
|---|---|
| Control height | 24px |
| Corner radius | 6px |
| Font size | 13px |
| Button padding — horizontal | 16px |
| Button padding — vertical | 4px |
| Field inset — left/right | 8px |
| Checkbox / radio width | 16px |
| Checkbox radius | 5.5px |
| Switch track | 54 × 24px, knob 32 × 20px, inset 2px |
| Slider knob (non-ticked) | 20 × 16px |
| Stepper width | 20px |

## Button styles

Six styles, each with Idle / Clicked / Disabled and both Context values:

- **Bordered** — the default. Neutral fill, hairline border, subtle shadow.
- **Bordered Prominent (Default)** — accent-filled. The default action in a dialog. One per view.
- **Bordered Tinted** — accent-tinted fill with accent label. A middle weight.
- **Bordered Destructive** — red. For destructive actions that aren't the default.
- **Bordered Prominent Destructive** — red-filled. Destructive *and* default.
- **Borderless** — label only, no chrome. For toolbars and dense layouts.

Toggle buttons add an `On` axis. Arrow buttons are a separate component with their own sizing.

## Working through a design task

**Designing a screen from scratch:** Start with the window chrome — pick a window type from the
twelve `Windows - Composed` variants (with/without sidebar, toolbar style, title). Establish
appearance and control size. Then lay out content using the real components rather than
inventing new ones. Check `references/components.md` before building anything custom; the kit
almost certainly already has it.

**Implementing on web:** Copy `assets/tokens.css` into the project and build from the custom
properties. It ships light and dark, plus `[data-appearance]` hooks for explicit override.
Set `-webkit-font-smoothing: antialiased`.

**Implementing in SwiftUI or AppKit:** Read `references/swift.md` before writing anything. The
guidance genuinely inverts there: AppKit already implements most of this system, so the correct
move is to use semantic `NSColor` values, `ControlSize`, `Material`, and system controls rather
than the raw tokens. Hardcoding the extracted hex values produces an app that screenshots
identically and behaves less natively — it breaks the user's accent choice, Increase Contrast,
Reduce Transparency, and focus states. Use `assets/MacOSDesignTokens.swift` for the parts with
no system equivalent: control metrics, Liquid Glass parameters, structural dimensions.

**Reviewing existing UI:** Check in this order — type scale, label alpha values, control heights,
corner radii, accent hardcoding, material vs. solid fills, focus state. That ordering finds the
most impactful problems first.

## When the kit doesn't have it

If you need a component that isn't in `references/components.md`, build it from the primitives
rather than importing a pattern from iOS or the web. Match the control height and radius for
the current size, use `Fills/*` for the background, `Labels/*` for text, and the standard
control shadow. A new component that follows the metrics will sit correctly next to real ones.

Some patterns simply don't belong on macOS — floating action buttons, bottom tab bars, pull-to-
refresh, and hamburger menus are iOS or Android conventions. The macOS equivalents are toolbar
buttons, sidebars, and menu bar commands. Say so if the user asks for one.

## Provenance and licensing

These values are extracted from the Apple Design Resources macOS UI kit
(© Apple Inc., distributed via the Figma Community). The kit's own license governs use of the
original file and its assets. Design tokens and metrics are used here as functional
specifications for building HIG-conformant interfaces.

**SF Pro and SF Symbols are assumed installed locally.** They are licensed separately and are
not bundled with this skill. Two constraints follow from Apple's font license, and they bite at
different moments:

- **Design and native app development — fine.** Rendering SF Pro in mockups, and using it in
  apps built for Apple platforms, is exactly what the license covers.
- **Web embedding — not permitted.** Apple's license does not allow self-hosting SF Pro as a
  webfont or bundling the files with a site. A locally installed copy will render correctly in
  the browser during development, which makes this easy to miss: the design looks right on the
  build machine and silently falls back for everyone else. For shipped web work, rely on
  `-apple-system` / `BlinkMacSystemFont`, which resolve to the system SF on Apple devices with
  no bundling, and pick a deliberate fallback (Inter is the closest metric-compatible option)
  for other platforms.

**SF Symbols is an app, not a webfont.** In SwiftUI and AppKit, reference symbols by name.
Everywhere else, export the specific symbols needed as SVG from the SF Symbols app rather than
loading a symbol font. Match the symbol's weight to the adjacent text weight — Medium for
control chrome — and use the matching optical variant, since SF Symbols ships per-weight
designs rather than scaling one outline.

For guidance beyond metrics — behavior, interaction patterns, platform conventions — consult
Apple's Human Interface Guidelines directly.
