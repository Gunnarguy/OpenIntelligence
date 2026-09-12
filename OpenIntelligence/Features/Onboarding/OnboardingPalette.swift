//
//  OnboardingPalette.swift
//  OpenIntelligence
//
//  One appearance-aware palette for the onboarding flow.
//

import SwiftUI

/// Colours for onboarding, resolved against the current appearance.
///
/// **Why this exists rather than `DSColors`.** The rest of the app uses `DSColors` in 511 places
/// and is adaptive by construction. Onboarding used it in exactly **zero**: it painted its own
/// dark navy gradient and drew about sixty-nine white and black literals on top. Nothing forced
/// dark mode, so in light mode the app around it turned white while onboarding stayed navy, and
/// the first screen anyone sees was the one screen that ignored their system setting.
///
/// The obvious repair is to replace each literal with a `DSColors` token, and it is the wrong one.
/// Onboarding carries a deliberate opacity hierarchy: `.white` for a headline, `0.75` for a
/// subtitle, `0.6` for an explainer, `0.4` for a metric label, `0.2` for a timestamp, `0.08` for a
/// hairline, `0.03` for a panel fill. `DSColors` offers three text tokens and two separators, so
/// mapping onto it would collapse seven distinct levels into three and trade the design away for
/// the adaptivity. This keeps the ramp and changes only what it is a ramp *of*.
///
/// **The status bar fixes itself.** `INFOPLIST_KEY_UIStatusBarStyle` is `UIStatusBarStyleDefault`,
/// which is adaptive: iOS draws dark glyphs in light appearance. Over the old unconditional navy
/// backdrop that put near-black glyphs on a near-black field, which is the one place onboarding was
/// genuinely broken rather than merely inconsistent. Once the backdrop follows the appearance, the
/// adaptive status bar is correct in both directions and needs no override.
struct OnboardingPalette {

    let colorScheme: ColorScheme

    init(_ colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    var isDark: Bool { colorScheme == .dark }

    // MARK: - Foreground

    /// The colour every piece of onboarding text and iconography is a fade of.
    ///
    /// Not `Color.primary`. The whole file expresses hierarchy as `ink.opacity(...)`, and
    /// `Color.primary` is already a dynamic colour whose own opacity differs per appearance, so
    /// fading it compounds two ramps and makes the light and dark hierarchies drift apart. A flat
    /// literal per appearance keeps `opacity(0.4)` meaning the same thing in both.
    var ink: Color {
        isDark ? .white : Color(red: 0.06, green: 0.08, blue: 0.14)
    }

    /// `ink` at a given strength. Call sites read `palette.ink(0.75)` where they used to read
    /// `.white.opacity(0.75)`, so the hierarchy stays legible in the code as well as on screen.
    func ink(_ opacity: Double) -> Color {
        ink.opacity(opacity)
    }

    // MARK: - Backdrop

    /// The three-stop gradient behind everything.
    ///
    /// Dark keeps the original navy exactly. Light is not that inverted, which would be a pale blue
    /// wash with no depth; it is a warm off-white falling to a faint blue-grey, so the same sense of
    /// a lit surface survives without the screen becoming a flat white rectangle.
    var backdropStops: [Color] {
        if isDark {
            return [
                Color(red: 0.03, green: 0.05, blue: 0.12),
                Color(red: 0.05, green: 0.11, blue: 0.22),
                Color(red: 0.08, green: 0.16, blue: 0.31),
            ]
        }
        return [
            Color(red: 0.98, green: 0.98, blue: 1.00),
            Color(red: 0.93, green: 0.95, blue: 0.99),
            Color(red: 0.88, green: 0.91, blue: 0.97),
        ]
    }

    /// The scrim over the glow circles.
    ///
    /// Black at 0.35 in dark mode as before. In light mode black would dirty the whole screen, so
    /// it is white, and weaker: the glows need softening, not hiding.
    var scrim: Color {
        isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.55)
    }

    /// Opacity for the blurred accent glows. They read as light sources against navy and as stains
    /// against off-white, so they are pulled back rather than removed.
    var glowOpacity: Double {
        isDark ? 1.0 : 0.45
    }

    /// The fade at the top of the pipeline log, hand-matched to the first backdrop stop.
    var logFadeTop: Color {
        (isDark
            ? Color(red: 0.04, green: 0.07, blue: 0.15)
            : Color(red: 0.96, green: 0.97, blue: 1.00))
            .opacity(0.95)
    }

    // MARK: - Primary buttons

    /// Primary buttons were black text on a white fill, which is the one pattern that is actively
    /// wrong rather than merely mismatched: in light mode a white button on a near-white backdrop
    /// disappears. Inverting against the backdrop keeps the contrast the design intended in both
    /// appearances.
    var buttonFill: Color { ink }
    var buttonLabel: Color { isDark ? Color(red: 0.03, green: 0.05, blue: 0.12) : .white }
}

extension View {
    /// Reads the current appearance and hands the view an onboarding palette.
    ///
    /// A convenience so each of the fifteen subviews in the flow declares one
    /// `@Environment(\.colorScheme)` and derives the palette, rather than the root threading a
    /// palette through fifteen initialisers.
    func onboardingPalette(_ colorScheme: ColorScheme) -> OnboardingPalette {
        OnboardingPalette(colorScheme)
    }
}
