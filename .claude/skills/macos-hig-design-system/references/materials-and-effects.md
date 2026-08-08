# Materials, Elevation & Liquid Glass

All values extracted from the effect stacks in the kit. Read this before building any
floating surface — window, popover, menu, sheet, notification, toolbar, or tooltip.

## The three surface tiers

macOS surfaces fall into exactly three tiers. Pick one deliberately; do not invent a fourth.

| Tier | What it is | Background | Blur | Shadow |
|---|---|---|---|---|
| **Content** | The opaque body of a window | `Window Background` (`#FFFFFF` / `#1E1E1E`) | none | none |
| **Material** | Sidebars, toolbars, menus, popovers, notifications | `Material/*` token | 60–80px backdrop | popover or window shadow |
| **Liquid Glass** | Controls floating *over* content or media | translucent + refraction | 6–16px | control shadow + inner highlight |

Content sits at the bottom. Material floats over content. Liquid Glass floats over anything.
Never stack two Liquid Glass surfaces directly on top of each other.

## Material tokens

| Material | Light | Dark |
|---|---|---|
| Thin | `#F6F6F6 @48%` | `#282828 @50%` |
| Ultra Thick | `#F6F6F6 @84%` | `#282828 @80%` |

The kit also ships `Materials` component variants: Ultra Thin, Thin, Medium, Thick, Ultra Thick.
Interpolate alpha between the Thin and Ultra Thick values above for the intermediate steps.

Every material is a **backdrop blur plus a translucent fill**. Implement as:

```css
background: var(--material-thin);
backdrop-filter: blur(80px) saturate(180%);
```

Blur radii found in the kit: `80px` and `60px` for window-level materials, `81.5px` for the
heaviest, `6px` for small glass controls, `16px` for large glass.

## Liquid Glass parameters

These are the authored values from the `Kit` variable collection. They describe Figma's
glass shader; map them onto whatever your platform offers.

| Parameter | Value | Meaning when reimplementing |
|---|---|---|
| Refraction | 70 | Strength of edge lensing |
| Depth (regular) | 30 | Thickness of the simulated slab |
| Depth (medium/large) | 30 | Same |
| Dispersion | 20 | Chromatic fringing at edges |
| Frost — regular | 6 | Backdrop blur in px |
| Frost — medium | 16 | Backdrop blur in px |
| Frost — large | 16 | Backdrop blur in px |
| Splay (regular) | 20 | Spread of the edge highlight |
| Splay (medium/large) | 20 | Same |
| Opacity | 25 | Base fill opacity % |
| Light angle | 0 | Top-lit |

CSS approximation:

```css
.glass {
  background: rgb(255 255 255 / 25%);
  backdrop-filter: blur(6px) saturate(180%);
  box-shadow:
    inset 0 0.5px 1px 0.5px rgb(255 255 255 / 50%),  /* top highlight */
    0 0.5px 1.5px rgb(0 0 0 / 20%);                   /* contact shadow */
}
```

The inner top highlight is not optional. Every glass and every bordered control in this kit
carries `inset 0 0.5px 1px 0.5px rgb(255 255 255 / 50%)`. It is what makes the surface read
as a physical slab rather than a flat translucent rectangle.

## Shadow recipes

Verbatim from the kit, most-used first.

| Name | Value | Used on |
|---|---|---|
| Hairline definition | `0 0 1px rgb(0 0 0 / 80%)` | Glyphs, tick marks |
| Control | `0 0.5px 1.5px rgb(0 0 0 / 20%)` | Buttons, segmented controls |
| Knob | `0 0.5px 2.5px rgb(0 0 0 / 30%)` | Slider and switch knobs |
| Popover | `0 8px 15px 6px rgb(0 0 0 / 18%)`, `0 2px 4px rgb(0 0 0 / 15%)` | Popovers, menus, notifications |
| Window (active) | `0 18px 54px rgb(0 0 0 / 30%)` | Focused window |
| Window (key) | `0 18px 54px rgb(0 0 0 / 57%)` | Modal / alert over dimmed content |
| Window (inactive) | `0 3px 36px rgb(0 0 0 / 5%)` | Background window |
| Sheet | `0 7px 21px rgb(0 0 0 / 20%)` | Sheets |

Inner shadows used to model recessed controls (tracks, fields):

- `inset 0 0 2px rgb(0 0 0 / 4%)` and `inset 0 0 2px rgb(0 0 0 / 3%)` — soft recess
- `inset 0 1px 2px rgb(0 0 0 / 2%)` — top-edge recess on fields
- `inset 0 -1px 0.5px -1px rgb(255 255 255 / 100%)` — bottom lip highlight
- `inset 0 1px 0.5px -1px rgb(255 255 255 / 80%)` — top lip highlight

## Structural dimensions

| Element | Value |
|---|---|
| Window corner radius | 16px |
| Toolbar height — unified compact | 40px |
| Toolbar height — default | 44px |
| Toolbar height — expanded | 52px |
| Sidebar item height | 24 / 32 / 36px (Small / Medium / Large) |
| Sidebar item radius | 5px (S, M), 8px (L) |
| Menu item height | 24px |
| Menu item radius | 8px |
| Group box radius | 12px |
| Scrollbar thickness | 6px (thumb), 12px (track region) |
| Scrollbar thumb radius | fully rounded |
| Scrollbar thumb color | `Miscellaneous/Scrollbar` — `#000 @50%` / `#FFF @55%` |

## Scroll edge effects

The kit ships `Scroll Edge Effect - Hard` and `Scroll Edge Effect - Soft`, each with Top and
Bottom variants. When content scrolls under a toolbar or over a glass edge, apply a gradient
fade at that edge rather than a hard divider line. Hard is for unified toolbars; soft is for
content that scrolls under floating glass.

## Window state matters

Nearly every component in this kit has an `Active` axis (window focused vs. not). When the
window loses focus:

- Accent-colored controls desaturate toward `Grays/Gray`
- Selection backgrounds change from `Tables/BG - Selected + Active` to `Selected + Inactive`
- Window shadow drops from 30% to 5% opacity
- Sidebar labels shift to `Miscellaneous/Sidebar/Label - Inactive`

If your platform can detect window focus, implement this. It is one of the strongest signals
that a UI is genuinely macOS-native rather than a web app in a window.
