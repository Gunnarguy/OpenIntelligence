---
name: ui-change
description: Use before changing anything the owner will see on a screen of OpenIntelligence (a layout, a control, spacing, colour, a text size, wording in the app, a Settings page, the Mac window) and before installing such a change on his phone. Gives his recorded UI rulings and the command that photographs every main screen before and after the change, so he sees it first. Triggers on "redesign", "clean up the UI", "make it look", "move this", "rename this", "tacky", "ugly", "jumps around", "looks the same", "spacing", "bubble", "chip", "pill", and on any edit under OpenIntelligence/Features or OpenIntelligence/UI that changes what is drawn.
---

# UI change

During 5.8 about 35 of the owner's messages rejected a UI change after it was already on his phone
(`Docs/ai/RETRO_5.8.md`, gap 7). Two things prevent that: his rulings in one place, and the change shown to him
before it is installed.

## 1. Read his rulings first

`Docs/ai/DESIGN.md`: each ruling in his own words with its date. A change that goes against one needs his word
first; say which ruling and ask once. Where the sheet is silent, match the app's own controls (`DSColors`,
`DSSpacing`, the chips and pills already there) before reaching for a system default.

## 2. Show him before and after

```bash
python3 scripts/ui_shots.py pair --before HEAD
```

It builds the last commit and the working tree, photographs every main screen of each on a new iPhone simulator
(Chat, Documents and its sheets, every Settings page, Plans, Database, Atlas), and writes the screens that changed
side by side with the changed area outlined. Send him `sheet.png` from the folder it prints (SendUserFile) with one
line saying what changed and why. About 40 minutes for the pair (20 a side, measured 2026-11-20); run it in the background. `--before <tag or commit>`
compares against something older; `compare <folder> <folder>` re-compares two sets already taken.

If it reports no screen changed, the change is not visible on those screens: say so, and do not claim he will see a
difference.

## 3. Install only after he has seen it

Then `python3 scripts/install_to_phone.py`, and tell him the build number.

## What the shots do not show

Motion (something that "jumps around" needs a screen recording), the Mac, iPad, Dark Mode and larger text sizes, and
any screen the screenshot tests do not open (`OpenIntelligenceUITests/FiveChecksUITests`, tests named
`testShotsOf...`; add one there for a new screen). Chat's answers in the shots come from the screenshot stand-in
model. For the SwiftUI itself, the `swiftui-pro` skill reviews the code.
