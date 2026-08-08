# Component Inventory

Every component in the kit, with its real variant axes as authored in Figma.
Names beginning with `_` are internal subcomponents — build them as private helpers, not public API.

Treat each axis as a required prop on your implementation. If an axis is listed here,
your component must support every listed value.


## Alerts

**Alert**

- `Type`: Side-by-side, Stacked

**_Buttons**

- `Mode`: Dark, Light
- `Type`: Destructive, Primary, Secondary


## Buttons

**Arrow Buttons**

- `State`: Clicked, Disabled, Idle

**Buttons**

- `Active`: False, True
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
- `Style`: Bordered, Bordered - Destructive, Bordered - Prominent (Default) D, Bordered - Prominent (Default) Destructive, Bordered - Tinted, Borderless
- `On`: False

**Buttons - Toggle**

- `Active`: False, True
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
- `On`: False, True

**_Label**

- `Mode`: Dark, Light
- `Active`: Active
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
- `Style`: Bordered
- `On`: False

**_Labels - Borderless**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**_Labels - Destructive**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**_Labels - Preferred**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**_Labels - Tinted**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
- `Window State`: Active

**_Labels - Toggle**

- `Mode`: Dark, Light
- `Active`: False, True
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
- `On`: False, True


## Color Wells

**Color Picker**

- `Mode`: Light
- `State`: Disabled, Idle, Selected

**Color Picker - Wheel**

- `Color Selected`: False, True


## Combo Boxes

**Combo Box**

- `State`: Button Clicked, Disabled, Field Clicked, Idle


## Disclosure Controls

**Disclosure Button**

- `State`: Clicked, Disabled, Idle
- `Disclosed`: False, True


## Forms

**Leading Accessories**

- `Content`: Button, Checkbox + Large Icon, Checkbox + Small Icon, Disclosure + Large Icon, Disclosure + Small Icon, Radio Buttons, Symbol, Title and Subtitle

**Trailing Accessories**

- `Type`: Button, Checkboxes, Combo Box, Detail Disclosure, Label, Label + Info Button, More Button, Pop-Up Button, Radio Buttons, Stepper, Switch, Text Field

**_Chevron**

- `Disclosed`: False, True

**_Left Accessory Icons / 24pt**

- `Color`: Black, Blue, Brown, Cyan, Dark Gray, Green, Indigo, Light Gray, Mint, Orange, Pink, Purple, Red, Teal, White, Yellow

**_Left Accessory Icons / 32pt**

- `Color`: Black, Blue, Brown, Cyan, Dark Gray, Green, Indigo, Light Gray, Mint, Orange, Pink, Purple, Red, Teal, White, Yellow


## Image Wells

**Image Well**

- `Enabled`: False, True


## Lists and Tables

**Sort Order Indicator**

- `Order`: Ascending, Descending

**Table Rows**

- `Level`: 0, 1, 2, 3, 4
- `Type`: Alternating Row Color, Default, Selected + Active, Selected + Inactive

**Table Rows - Blank**

- `Alternating Row`: False, True

**_BG**

- `State`: Alternating Row Color, Selected + Active, Selected + Inactive

**_Column Headers**

- `First Column`: False, True
- `Selected`: False, True

**_Disclosure - Selected**

- `Expanded`: False, True

**_Disclosure - Unselected**

- `Expanded`: False, True

**_Icon**

- `Type`: Custom, Folder, Thumbnail


## Materials

**Liquid Glass - Large**

- `Mode`: Dark, Light

**Liquid Glass - Medium**

- `Mode`: Dark, Light

**Liquid Glass - Small**

- `Mode`: Dark, Light
- `Active`: False, True
- `State`: Default, Primary

**Materials**

- `Mode`: Dark, Light
- `Type`: Medium, Thick, Thin, Ultra Thick, Ultra Thin

**Scroll Edge Effect - Hard**

- `Mode`: Dark, Light
- `Edge`: Bottom, Top

**Scroll Edge Effect - Soft**

- `Edge`: Bottom, Top


## Menu Bar and Dock

**Desktop Template**

- `Color Mode`: Dark, Light

**Desktop Wallpaper**

- `Color Mode`: Dark, Light

**Dock**

- `Mode`: Dark, Light

**Dock Icon**

- `Mode`: Dark, Light

**Menu Bar**

- `Color Mode`: Over Dark, Over Light

**_Menu Bar/App Name / Dark**

- `Selected`: False, True

**_Menu Bar/App Name / Light**

- `Selected`: False, True

**_Menu Bar/Apple Menu/Dark**

- `Selected`: False, True

**_Menu Bar/Apple Menu/Light**

- `Selected`: False, True

**_Menu Bar/Menu Item / Dark**

- `Selected`: False, True

**_Menu Bar/Menu Item / Light**

- `Selected`: False, True

**_System App Icon**

- `Mode`: Dark, Light
- `App Icon`: App Store, Apple TV, Apps, Books, Calculator, Calendar, Contacts, Custom, FaceTime, Final Cut Pro, Find My, Finder, Folder, Freeform, Games, Home, Keynote, Mail, Maps, Messages, Music, News, Notes, Numbers, Pages, Passwords, Phone, Photo Booth, Photos, Podcasts, Preview, Quicktime Player, Reminders, Safari, Settings, Shortcuts, Siri, Stocks, Terminal, TextEdit, Trash Empty, Trash Full, Voice Memos, Weather, Xcode, iPhone Mirroring


## Menus

**Headers**

- `Mode`: Dark, Light
- `Inset`: False, True

**Menu Background**

- `Mode`: Dark, Light

**Menu Items**

- `Mode`: Dark, Light
- `State`: Disabled, Hover, Hover + Key, Idle
- `Menu has Selection`: False, True
- `Type`: Action, Submenu

**Separators**

- `Mode`: Dark, Light

**_Shortcuts**

- `Mode`: Dark, Light
- `Hover + Key`: False, True


## Notifications

**Notification**

- `Mode`: Dark, Light
- `Stack`: False, True


## Pointers

**Pointers**

- `Type`: Beachball, Cross, Default, Default with Menu Badge, Hand (Grabbing), Hand (Open), Hand (Pointing), Move, Resize (Down), Resize (Left), Resize (Left-Right), Resize (Right), Resize (Up), Resize (Up-Down), Resize North-East South-West, Resize North-South, Resize North-West South-East, Resize West-East, Text Cursor, Zoom In, Zoom Out


## Pop-up and Pull-down Buttons

**Pop-Up Button**

- `State`: Clicked, Disabled, Idle
- `Show Label`: False, True

**Pulldown Button**

- `State`: Clicked, Disabled, Idle


## Popovers

**Popover**

- `Mode`: Dark, Light
- `Edge`: Bottom (Center), Bottom (Leading), Bottom (Trailing), Leading (Bottom), Leading (Middle), Leading (Top), Top (Center), Top (Leading), Top (Trailing), Trailing (Bottom), Trailing (Middle), Trailing (Top)


## Progress Indicators

**Circular - Determinate**

- `Size`: Large, Small
- `Active`: False, True
- `Progress`: 0%, 100%, 25%, 50%, 75%

**Circular - Indeterminate ("Spinner")**

- `Size`: Large, Small

**Linear - Determinate**

- `Size`: Medium, Small
- `Active`: False, True
- `Percentage`: 0%, 100%, 25%, 50%, 75%

**Linear - Indeterminate**

- `Size`: Medium, Small
- `Active`: False, True


## Scrollbar

**Scrollbar - Horizontal**

- `Page`: 200%, 400%, 800%
- `Position`: Center, Leading, Trailing

**Scrollbar - Vertical**

- `Page Height`: x 2, x 4, x 8
- `Position`: Bottom, Middle, Top


## Search Fields

**Search Field**

- `State`: Disabled, Focused, Idle
- `Text`: False, True

**_Clear**

- `State`: Clicked, Idle


## Segmented Controls

**Segmented Control**

- `Active`: False, True
- `Selectable`: False, True

**_Segment - Not selectable**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle

**_Segment - Selectable**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle
- `Selected`: False, True

**_Separator**

- `Show`: False, True


## Sheets

**Sheet**

- `Mode`: Dark, Light


## Sidebars

**BG**

- `Active`: False, True

**Item**

- `Size`: Large, Medium, Small
- `State`: Disabled, Idle, Selected
- `Active`: False, True
- `Level`: 0, 1, 2, 3, 4

**Section Header**

- `Mode`: Dark, Light
- `Size`: Large, Medium, Small
- `First Section`: False, True
- `Active`: False, True

**Sidebars - Composed**

- `Size`: Large, Medium, Small

**Window Controls**

- `Toolbar Style`: Compact, Default

**_Detail**

- `Mode`: Dark, Light
- `Size`: Large, Medium, Small
- `Active`: False, True
- `Enabled`: False, True

**_Disclosure - Folder**

- `Mode`: Dark, Light
- `Expanded`: False, True

**_Disclosure - Header**

- `Mode`: Dark, Light
- `Expanded`: False, True

**_Leading**

- `Mode`: Dark, Light
- `Size`: Large, Medium, Small
- `Active`: False, True
- `Icon`: Image, Symbol
- `Enabled`: False, True
- `Level`: 0, 1-4

**_Selection**

- `Mode`: Dark, Light
- `Active`: False, True


## Sliders and Dials

**Dial (Circular Slider)**

- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**Slider**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle
- `Ticks`: False, True
- `Value`: 0%, 100%, 25%, 50%, 75%
- `Center-biased`: False

**Slider - Center-biased**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle
- `Ticks`: False, True
- `Value`: 0%, 100%, 25%, 50%, 75%

**_Knob**

- `State`: Clicked, Disabled, Idle
- `Style`: Non-Ticked, Ticked

**_Slider Midline**

- `Mode`: Dark, Light
- `Active`: False, True

**_Track Filled**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle

**_Track Unfilled**

- `State`: Clicked, Disabled, Idle

**_Track Unfilled - Center-biased**

- `State`: Clicked, Disabled, Idle


## Steppers

**Stepper/Inside Field**

- `State`: Clicked - Down, Clicked - Up, Default, Disabled

**Stepper/No Field**

- `State`: Clicked - Down, Clicked - Up, Default, Disabled

**Stepper/Outside Field**

- `State`: Clicked - Down, Clicked - Up, Default, Disabled


## Text Fields

**Text Field**

- `State`: Disabled, Focused, Idle
- `Show Text`: False, True

**_Input Fields**

- `Mode`: Dark, Light
- `State`: Disabled, Focused, Idle


## Toggles

**Toggles - Checkboxes**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle
- `Selection`: Mixed, Off, On

**Toggles - Radio Buttons**

- `Active`: False, True
- `State`: Clicked, Disabled, Idle
- `Selection`: Mixed, Off, On

**Toggles - Switches**

- `Active`: False, True
- `State`: Clicked, Disabeld, Idle
- `Selection`: Off, On

**_Glyphs - Checkboxes**

- `Mode`: Dark, Light
- `Active`: False, True
- `State`: Mixed, Selected
- `Is Enabled`: False, True

**_Glyphs - Radio Buttons**

- `Mode`: Dark, Light
- `Active`: False, True
- `State`: Mixed, Selected
- `Is Enabled`: False, True

**_Knob**

- `Size`: Large, Medium, Mini, Small, XL
- `State`: Clicked, Disabled, Idle
- `Selection`: False, True


## Toolbars

**Button**

- `Mode`: Dark, Light
- `Active`: False, True
- `Size`: Medium, XL
- `State`: Disabled, Idle

**Button Group**

- `Mode`: Dark, Light
- `Size`: Medium, XL
- `Active`: False, True

**Pop-Up Button**

- `Mode`: Dark, Light
- `State`: Disabled, Idle
- `Size`: Medium, XL
- `Active`: False, True

**Pull Down Button**

- `Mode`: Dark, Light
- `State`: Disabled, Idle
- `Size`: Medium, XL
- `Active`: False, True

**Search**

- `Mode`: Dark, Light
- `Size`: Medium, XL
- `State`: Focused, Placeholder, Placeholder + Disabled, Typing, Value, Value + Disabled
- `Active`: False, True

**Segmented Control**

- `Mode`: Dark, Light
- `Size`: Medium, XL
- `Active`: False, True

**_Button - Utility Panel Tab Bar**

- `Selected`: False, True

**_Buttons/Medium**

- `Mode`: Dark, Light
- `State`: Disabled, Idle, Selected

**_Buttons/XL**

- `Mode`: Dark, Light
- `State`: Disabled, Idle, Selected

**_Separator**

- `Mode`: Dark, Light
- `Size`: Medium, XL
- `Next to Selected`: False, True


## Tooltips

**_Text**

- `Mode`: Dark, Light


## Windows

**Utility Panel**

- `Mode`: Dark, Light

**Window BG**

- `Mode`: Dark, Light
- `Active`: False, True

**Window Controls/Standard**

- `Mode`: Dark, Light
- `Active`: False, True

**Window Controls/Utility**

- `Mode`: Dark, Light
- `Active`: False, True

**Window Titles/Window**

- `Mode`: Dark, Light
- `With Sidebar`: False, True

**Windows - Composed**

- `Window Type`: Default + Title, Default + Title + Sidebar, Default without Title, Expanded Toolbar + Title, Expanded Toolbar + Title + Sidebar, Expanded Toolbar without Title, Unified Compact Toolbar + Title, Unified Compact Toolbar + Title + Sidebar, Unified Compact Toolbar without Title, Unified Toolbar + Title, Unified Toolbar + Title + Sidebar, Unified Toolbar without Title
- `Active`: False, True
- `Mode`: Dark, Light


## _Kit

**Glyphs**

- `Mode`: Dark, Light
- `State`: Disabled, Idle
- `Style`: Colored, Neutral, Primary

**Knobs**

- `Property 1`: Content Area, Over-Glass
- `Property 2`: Dark, Light
- `Property 3`: Knobs - Toggle
- `Property 4`: 01 - Idle, 03 - Clicked, 03 - Clicked - Glow, 03 - Clicked - Shadow, 04 - Disabled

**Segmented Control**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**_Control BG/Bordered**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-glass
- `State`: Clicked, Disabled, Idle
- `On`: False, True

**_Control BG/Bordered - Destructive**

- `Mode`: Dark, Light
- `State`: Clicked, Disabled, Idle

**_Control BG/Bordered - Prominent**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-glass
- `State`: Clicked, Disabled, Idle

**_Control BG/Bordered - Prominent - Destructive**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-glass
- `State`: Clicked, Disabled, Idle

**_Control BG/Bordered - Tinted**

- `Mode`: Dark, Light
- `State`: Clicked, Disabled, Idle

**_Control BG/Bordered - Toggle**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-glass
- `State`: Clicked, Disabled, Idle
- `On`: False, True
- `Window Active`: False, True

**_Control BG/Controls**

- `Mode`: Dark, Light
- `Active`: False, True
- `Context`: Content Area, Over-glass
- `State`: Clicked, Disabled, Idle
- `On`: False, True

**_Ticks**

- `Mode`: Dark, Light
- `Context`: Content Area, Over-Glass
- `State`: Disabled, Idle
- `Type`: Centerpoint, Tick

**_Tracks - Filled**

- `Mode`: Dark, Light
- `Active`: False, True
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle

**_Tracks - Unfilled**

- `Mode`: Dark, Light
- `Active`: False, True
- `Context`: Content Area, Over-Glass
- `State`: Clicked, Disabled, Idle
