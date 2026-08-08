# Sizing Tokens

From the Figma variable collection `Sizes`. Every control in this system is defined across
**five control sizes**: Mini, Small, Medium (the default), Large, XL.
Pick one size for a given surface and drive every control on it from that column.

`ALIAS->X` means the value is an alias to another token, resolve it in the same column.


## Global

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size` | 10.0 | 11.0 | 13.0 | 13.0 | 13.0 |
| `Height` | 16.0 | 20.0 | 24.0 | 28.0 | 36.0 |
| `Radius` | 4.0 | 5.0 | 6.0 | 7.0 | 9.0 |

## Button

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Padding - Horizontal` | 7.0 | 10.0 | 16.0 | 16.0 | 16.0 |
| `Radius` | ALIAS->Global/Radius | ALIAS->Global/Radius | ALIAS->Global/Radius | 1000.0 | 1000.0 |
| `Vertical Padding` | 2.0 | 3.0 | 4.0 | 6.0 | 10.0 |

## Combo Button

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size - Chevron` | 9.0 | 10.0 | 11.0 | 12.5 | 13.0 |
| `Inset` | 2.0 | 2.0 | 2.0 | 2.0 | 3.0 |
| `Radius - Button` | 2.5 | 3.5 | 4.5 | 5.5 | 6.5 |
| `Text - Inset - Right` | 20.0 | 24.0 | 28.0 | 28.0 | 34.0 |
| `Width - Button` | 16.0 | 20.0 | 24.0 | 24.0 | 30.0 |

## Fields

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size - Search Glyph` | 11.0 | 13.0 | 13.0 | 13.0 | 13.0 |
| `Inset - Left` | 6.0 | 6.0 | 8.0 | 8.0 | 10.0 |
| `Inset - Right` | 6.0 | 6.0 | 8.0 | 8.0 | 10.0 |
| `Leading - Search Glyph` | 13.0 | 15.0 | 15.0 | 15.0 | 15.0 |

## Checkboxes

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height - Checkmark` | 7.55 | 8.93 | 8.93 | 11.3 | 11.3 |
| `Radius` | 3.5 | 4.5 | 5.5 | 6.5 | 6.5 |
| `Width` | ALIAS->Radio Button/Width | ALIAS->Radio Button/Width | ALIAS->Radio Button/Width | ALIAS->Radio Button/Width | ALIAS->Radio Button/Width |
| `Width - Checkmark` | 7.78 | 9.31 | 9.31 | 11.72 | 11.72 |

## Radio Button

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height - Dash` | 1.7 | 2.0 | 2.0 | 2.0 | 2.0 |
| `Spacing` | 3.0 | 3.0 | 3.0 | 5.0 | 7.0 |
| `Width` | 12.0 | 14.0 | 16.0 | 18.0 | 18.0 |
| `Width - Dash` | 5.5 | 6.5 | 6.5 | 8.0 | 8.0 |
| `Width - Dot` | 4.0 | 4.8 | 4.8 | 5.0 | 5.0 |

## Toggle (Switch)

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Knob - Clicked - Height` | 20.0 | 26.0 | 31.0 | 37.0 | 46.0 |
| `Knob - Clicked - Width` | 33.0 | 40.0 | 50.0 | 59.0 | 73.0 |
| `Knob - Height` | 13.0 | 16.0 | 20.0 | 24.0 | 30.0 |
| `Knob - Inset` | 1.5 | 2.0 | 2.0 | 2.0 | 3.0 |
| `Knob - Width` | 21.0 | 26.0 | 32.0 | 38.0 | 47.0 |
| `Track - Height` | ALIAS->Global/Height | ALIAS->Global/Height | ALIAS->Global/Height | ALIAS->Global/Height | ALIAS->Global/Height |
| `Track - Width` | 36.0 | 44.0 | 54.0 | 64.0 | 80.0 |

## Slider

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Knob - Non-ticked Slider/Height` | 12.0 | 14.0 | 16.0 | 20.0 | 20.0 |
| `Knob - Non-ticked Slider/Height - Clicked` | 15.0 | 18.0 | 20.0 | 25.0 | 25.0 |
| `Knob - Non-ticked Slider/Inset` | 2.0 | 1.0 | 0.0 | -2.0 | -2.0 |
| `Knob - Non-ticked Slider/Width` | 16.0 | 18.0 | 20.0 | 24.0 | 24.0 |
| `Knob - Non-ticked Slider/Width - Clicked` | 20.0 | 23.0 | 25.0 | 30.0 | 30.0 |
| `Knob - Ticked Slider/Height` | 16.0 | 18.0 | 16.0 | 20.0 | 20.0 |
| `Knob - Ticked Slider/Height - Clicked` | 20.0 | 23.0 | 20.0 | 25.0 | 25.0 |
| `Knob - Ticked Slider/Width` | 8.0 | 10.0 | 20.0 | 24.0 | 24.0 |
| `Knob - Ticked Slider/Width - Clicked` | 10.0 | 13.0 | 25.0 | 30.0 | 30.0 |
| `Track/Inset - Horizontal` | 1.0 | 1.0 | 1.0 | 0.0 | 0.0 |
| `Track/Inset - Vertical` | 1.0 | 1.0 | 1.0 | 0.0 | 0.0 |
| `Track/Tick Spacing` | 2.0 | 2.0 | 2.0 | 3.0 | 3.0 |

## Dial

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height - Knob` | 4.0 | 5.0 | 6.0 | 6.0 | 7.0 |
| `Inset - Knob` | 2.0 | 2.5 | 3.0 | 3.0 | 3.0 |

## Stepper

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size` | 8.0 | 9.0 | 12.0 | 12.0 | 12.0 |
| `Radius` | 4.0 | 5.0 | 6.0 | 7.0 | 9.0 |
| `Width` | 13.0 | 17.0 | 20.0 | 23.0 | 30.0 |
| `Width - Separator` | 9.0 | 11.0 | 14.0 | 15.0 | 20.0 |

## Segmented Control

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height - Separator` | 10.0 | 12.0 | 14.0 | 18.0 | 20.0 |
| `Margins` | 6.0 | 8.0 | 10.0 | 12.0 | 14.0 |

## Popup

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size - Chevron` | 10.0 | 11.0 | 11.0 | 13.0 | 13.0 |
| `Inset - Left` | 7.0 | 10.0 | 12.0 | 14.0 | 18.0 |

## Menu

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size` | 10.0 | 11.0 | 13.0 | 13.0 | 13.0 |
| `Font Size - Symbol` | 11.0 | 11.0 | 13.0 | 13.0 | 13.0 |
| `Height` | 19.0 | 22.0 | 24.0 | 24.0 | 24.0 |
| `Inset - Bottom - Header` | 2.0 | 3.0 | 4.0 | 4.0 | 4.0 |
| `Inset - Left - Header` | 14.0 | 18.0 | 20.0 | 20.0 | 20.0 |
| `Inset - Top - Header` | 3.0 | 4.0 | 5.0 | 5.0 | 5.0 |
| `Width - Symbol` | 6.0 | 10.0 | 12.0 | 12.0 | 12.0 |

## Disclosure

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size` | 10.0 | 10.0 | 13.0 | 13.0 | 13.0 |
| `Height - Symbol` | 16.0 | 21.0 | 25.0 | 29.0 | 38.0 |
| `Radius` | 4.0 | 5.0 | 6.0 | 1000.0 | 1000.0 |

## Color Well

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height` | 16.0 | 20.0 | 24.0 | 28.0 | 36.0 |
| `Width` | 32.0 | 40.0 | 48.0 | 56.0 | 72.0 |

## Arrow Button

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Font Size` | 11.0 | 13.0 | 13.0 | 13.0 | 13.0 |

## Cursor

| Token | Mini | Small | Medium | Large | XL |
|---|---|---|---|---|---|
| `Height` | 14.0 | 16.0 | 18.0 | 18.0 | 18.0 |

## Kit / Liquid Glass parameters

| Parameter | Value |
|---|---|
| `Component Fill` | #000000 @10% |
| `Component Stroke` | #C399FF |
| `Link` | #98CCFF |
| `Liquid Glass/Depth - Medium and Large` | 30.0 |
| `Liquid Glass/Depth - Regular` | 30.0 |
| `Liquid Glass/Dispersion` | 20.0 |
| `Liquid Glass/Frost - Large` | 16.0 |
| `Liquid Glass/Frost - Medium` | 16.0 |
| `Liquid Glass/Frost - Regular` | 6.0 |
| `Liquid Glass/Light Angle` | 0.0 |
| `Liquid Glass/Opacity` | 25.0 |
| `Liquid Glass/Refraction` | 70.0 |
| `Liquid Glass/Splay - Medium and Large` | 20.0 |
| `Liquid Glass/Splay - Regular` | 20.0 |
| `Section Fill` | #000000 @10% |
| `Section Stroke` | #000000 @40% |
| `Subcomponent Fill` | #000000 @10% |
| `Subcomponent Stroke` | #000000 @40% |