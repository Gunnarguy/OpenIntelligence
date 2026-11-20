# Design rulings

The owner's rulings on how OpenIntelligence looks, reads and behaves on screen, each in his own words with the local date of the message.
Read it before any change to a screen, a control, text size, colour, spacing, or wording the user reads.

## Before a UI change reaches his phone

1. Read this sheet. A change that goes against a ruling needs his word first, with the ruling named.
2. Run `python3 scripts/ui_shots.py` (its docstring lists the subcommands; `pair --before HEAD` compares the last commit with the working tree). It captures every main screen in the Simulator before and after the change and builds one side-by-side page of the screens that changed. Send him that page.
3. Install on his phone only after he has seen it.

Why: during 5.8 about 35 of his messages rejected UI that was already installed (`Docs/ai/RETRO_5.8.md`, gap 7). The page shows still iPhone screens only: movement (rulings 6 and 3), the Mac, iPad, Dark Mode and larger text sizes need their own recording or screenshot.

## Where the design tokens live

- `OpenIntelligence/UI/DesignSystem/Theme.swift`: `DSColors`, `DSTypography` (its doc comment is the type scale), `DSSpacing`, `DSCorners`, `DSShadows`, `DSAnimations`, `DSHaptics`, `scaledFont` and the glass helpers.
- `OpenIntelligence/UI/DesignSystem/SurfaceCard.swift`: `SurfaceCard` and `SectionHeader`, the one card.
- `OpenIntelligence/Features/Settings/SettingsStatusPanel.swift`: the status panel at the top of a Settings page.
- `OpenIntelligence/App/MacShell.swift`: the Mac window's sidebar and `macAreaIsActive`.

## Rulings

"Memory note" means a file in the agent's auto memory for this repository; it is cited where the ruling was recorded without a quote.

### The whole app

| # | Rule | His words | Applies to |
|---|---|---|---|
| 1 | A pass over existing UI may change spacing, corners, alignment and layout defects. It keeps every font, bubble and colour. | memory note `ui-taste-keep-bubbles-colours-sizes`, 2026-10-22 | every screen |
| 2 | One look across the app: one type scale, one card, the same elements on sibling pages. | "Ubiquity and uniformity all across" (2026-11-15); "same kinds of elements, same kind of dots and what not" (2026-11-10) | Settings, Database tab, every tab |
| 3 | A one-off style or an abrupt change is a defect, because inconsistency is what makes the app look generated. | "inconsistency is the thing" (2026-11-04); "its like sudden and looks vibecoded" (2026-11-10) | every screen; showing and hiding the Silicon HUD |
| 4 | The look has to be worth paying for. | "it has to look like genuinely premium level good because people aren't gonna wanna pay for tacky" (2026-11-16) | panels, setup cards, paid surfaces |
| 5 | A redesign he asked for has to change the design. The same layout made smaller or renamed is rejected. | "That looks like the exact same lol did you just make it smaller?" (2026-11-15); "looks the exact same just renamed" (2026-11-10) | any requested redesign |

### Layout and spacing

| # | Rule | His words | Applies to |
|---|---|---|---|
| 6 | Content does not move when a control is tapped or a label wraps. | "I don't want it to jump around" (2026-11-16); "it jumps around when I tap each different mode and it makes it hard to follow what’s actually changing" (2026-11-10) | pickers, mode cards, Settings panels |
| 7 | A card of options fits on one iPhone screen. | "this needs to all be pretty much like viewable in one screen" (2026-11-10); "I want it to all fit on one screen" (2026-11-10) | Compute Profile, Intelligence Mode and cards like them |
| 8 | The processing console shows one line per row at its small size, never wrapped and never cut off (it scrolls sideways). Lines are coloured by process. | "having two lines in the console wrapping is gonna look even worse" (2026-10-22); "cut off on the right like it would be truncated before which I also didn’t like" (2026-10-22); "show different colors for different processes" (2026-11-07) | import and processing console |
| 9 | A floating overlay stays small and never covers a banner or content. | "that silicon hub is kinda…in the way…I love it" (2026-11-04); "its blocking the banner for search set up" (2026-11-10) | Silicon HUD, X-Ray, banners |
| 10 | A destination is as few taps away as possible. | "seem like too many taps deep" (2026-11-15) | Settings, plans (the Mac: ruling 29) |
| 11 | A row or a button responds to the first tap. | "I have to like spam tap or tap very deliberately" (2026-11-04); "Tapping the X on the tip takes spam tapping" (2026-11-04) | Settings rows, tip close buttons |
| 12 | iPhone is portrait only. iPad rotates. | "its always portrait for iphone - okay well for ipad then the rotate thing matters" (2026-11-10) | orientation |
| 13 | The Settings list uses compact rows and no added colour. | "it doesnt need colorizing or anything but it does need to look premium and not have such large pill like page taps" (2026-11-15) | Settings list |
| 14 | An answer that is streaming sits in the same grey box as the finished answer. | "I also kind of hate how the streams not in a box" (2026-11-17); "I do like the gray box though" (2026-11-17) | Chat |

### Colour and bubbles

| # | Rule | His words | Applies to |
|---|---|---|---|
| 15 | Chat bubbles stay, and so does the colour on the message action row. | "The chat boxes are gone. The colors are gone from the very bottom part" (2026-10-22) | Chat |
| 16 | Colour that marks background work follows the accent colour the user picked in Settings. | "if I change my app colorizing to cyan or red or whatever, it should change these too" (2026-11-10) | Live Activity, Dynamic Island, widgets |
| 17 | Not everything is dark. A dark panel has a light counterpart. | "I want to not make everything dark mode so like there should be a light component to it as well" (2026-11-16) | status panels, setup cards |

### Text and sizes

| # | Rule | His words | Applies to |
|---|---|---|---|
| 18 | Text sizes do not change in a UI pass. | "I really don’t like that it changed the text size." (2026-10-22) | every screen; compact readouts keep `scaledFont(size:)` |
| 19 | One font and one scale. A line that looks different from the rest is fixed. | "this text isn’t really similar to the rest of the app is it a different font?" (2026-11-04); "uniform with the rest of the app, font wise" (2026-11-15) | every screen |
| 20 | In an answer, a bold line that acts as a header is drawn larger, and lists keep their structure. | "Bold should just be larger text bc they're like headers right?" (2026-11-18); "Presentation is so important" (2026-11-18) | answer rendering |

### Controls and native components

| # | Rule | His words | Applies to |
|---|---|---|---|
| 21 | A new control looks exactly like the app's existing ones. A system-drawn control that cannot be matched is named in the report. | "it needs to basically be like full-blown visually matching the rest of the app" (2026-10-09) | any new button, row, toggle or card |
| 22 | Anything that can be tapped shows that it can. | "people might not know they can tap on each of the different options?" (2026-11-16) | option chips, mode pickers |
| 23 | Haptics stay wherever an action lands, without excess. | "I love haptics bc it makes the app feel alive but not overkill" (2026-11-16); "It feels like you just removed a ton of haptics" (2026-11-16) | `DSHaptics` call sites |
| 24 | Tips are paced, and each one points at its control and says what it does and why. | "kind of invasive and it's popping up at Random" (2026-11-13); "both points at and describes exactly what each thing is and why it does what it does" (2026-11-03) | TipKit |
| 25 | A wait shows progress in the app's own style, and the progress keeps moving. | "there should be a little integrator bar so that users aren't confused" (2026-11-09); "obviously matching the rest of the app" (2026-11-09); "it seems to stop at 90% or whatever and kinda just sits there" (2026-11-13) | model setup, search setup, imports |
| 26 | The Atlas keeps the scene with labels at the axis ends. A label sits at the end of its axis and no line ends at nothing. | "I want the old one back for sure" (2026-10-20); "isn’t low enough/at the end of the line, it’s like in the middle" (2026-11-03); "Lines that lead to nothing." (2026-11-18) | Atlas; the chart stays a choice |
| 27 | The X-Ray and the HUD are quiet and exact: real chip positions and sizes, nothing estimated. | "less of an in your face type thing" (2026-11-10); "no approximations" (2026-11-10) | X-Ray, Silicon HUD |

### The Mac

| # | Rule | His words | Applies to |
|---|---|---|---|
| 28 | The Mac app is laid out as a Mac app, not as the iPhone layout in a window. | "the entire macos app looks kinda like its not optimized at all for mac" (2026-11-18); "macosified" (2026-11-18) | every Mac window |
| 29 | One click reaches a chat and the answer-route selector. | "i dont like that i need to click a library then hit chat, it feels weird and clunky and not intuitive" (2026-11-19); "not two clicks deep" (2026-11-17) | Mac sidebar, Chat toolbar |
| 30 | Where a control, a colour or a name exists on both platforms, the Mac matches the iPhone. | "match the macos one to the ios one bc i like how the ios one is colored for each component" (2026-11-14); "the ios side does it so much more intuitively too" (2026-11-14) | Device & Performance, dot rows, sidebar names (he flagged Conversations against Evidence Threads on 2026-11-19; the Mac sidebar now reads Evidence Threads) |
| 31 | In a Mac area, toolbar items, inspectors and appear-work are gated on `macAreaIsActive`, no area uses `.searchable`, and a Mac change never alters iPhone or iPad layouts. | memory note `mac-redesign-in-5-8`, 2026-11-18 | `App/MacShell.swift`, `ContentView.macWindowContent` |

### Words on screen

| # | Rule | His words | Applies to |
|---|---|---|---|
| 32 | Every figure, capability and device fact on screen is true to the code and to the device. Nothing is estimated. | "this literally needs to be as a matter of fact, correct true to code" (2026-11-13); "None of it can be wrong or inferred or fabricated." (2026-11-10) | Settings, Library Settings, About, guide documents (memory note `settings-ui-claims-drift`; run `oi-claim-audit` before removing a claim) |
| 33 | Wording is plain enough for anyone, without being reduced to something vague. | "I'm not looking for you to dilute this or distill it down to sound stupid" (2026-11-13) | labels, captions, explanations |
| 34 | Sibling items use parallel wording and the same fields. | "I want them unified across all quality modes" (2026-11-13); "I don’t like how inconsistent these are" (2026-11-10) | quality-mode cards, spec tiles |
| 35 | No long explanation under a control. | "The explanation below it all also kind of…seems excessive" (2026-11-10); "Remember, this is already a production app" (2026-11-10) | Settings cards |
| 36 | User-facing copy says a thing once and has no em dashes. | "it seemed veeeeery overworded in the sense of almost mansplaining" (2026-07-31); "it definitely needs to be digestible to all crowds" (2026-07-31); memory note `gunnar-writing-voice` | in-app text, What's New, store copy |
| 37 | Release notes lead with percentages (the count beside each), use bullets, and read for any audience. | "I like percentages" (2026-11-20); "I love bullet points" (2026-11-20); "it's not explained in a way that every crowd would understand" (2026-11-20) | What's New, promo text, description |
| 38 | When a change alters what the app says about itself, the strings inside the app change in the same turn. | memory note `docs-sync-means-in-app-text-too`, 2026-10-12 | strings under `OpenIntelligence/`, docs |

### Screenshots and store art

| # | Rule | His words | Applies to |
|---|---|---|---|
| 39 | Store screenshots have to sell the app and show it as it is, the Atlas and the Database tab included. He sees a contact sheet before any upload. | "compelling anyone would wanna download it" (2026-09-23); "isnt even like showing the app for what it is" (2026-09-23); "wheres the 3d vector graph and the database tab showing" (2026-09-23) | App Store screenshots, `scripts/compose_store_screenshots.py` (contact sheet: memory note `store-screenshots-bar`, 2026-09-23) |
| 40 | New UI gets new screenshots on both platforms. | "I need new screenshots regarding the new UI... for both iOS and macOS exactly how you did before" (2026-11-17) | iOS and macOS sets |

## Known traps behind these rulings

- Silicon HUD legend: fixed sizes and fixed gaps only inside `SiliconLegend`; a `Spacer` or an infinite frame froze the app at launch on his phone (memory note `hud-legend-window-sizes-to-content`, 2026-11-04).
- Reorderable rows: no branch or `AnyView` around a whole row, and no drop target on an ancestor (memory note `swiftui-reorderable-traps`, 2026-10-19).

## Not decided

He voiced each of these and named no target, or put it as a question. Ask; do not read a ruling into it.

- How much more Liquid Glass: "unless we've already put enough of that in the app" (2026-11-16). Read Apple's current Materials guidance before proposing any.
- The palette of the status panels: "maybe we can just make it all pastel" (2026-11-16). No later message names the palette he settled on.
- The unified bar's expanded panel: "It’s formatted strangely and I kinda don’t like it." (2026-11-07).
- The Mac window's size at first launch: "i feel like it should be like 60% or 70% of the overall screen?" (2026-11-14). The code sets a fixed 1100 by 760 (`OpenIntelligenceApp.swift`).
- A mostly verified answer that ends on a red line: "unverified and red at the very bottom" (2026-11-18).
- The How It Works and Siri & Shortcuts pages: he disliked both on 2026-11-14; no verdict on the later restyle was found.

The sources hold his side of the conversation only, so questions an agent asked that he left unanswered are not listed here.

[evidence_level: measured (owner messages 2026-10-23 to 2026-11-20 in the extracted set, earlier and queued messages read from the session transcripts, and the memory notes named above), confidence: high for quoted rulings, medium for rows 1, 31 and 38, which rest on a memory note alone; the code paths named were checked on 2026-11-20]
