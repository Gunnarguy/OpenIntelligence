//
//  Theme.swift
//  OpenIntelligence
//
//  Design System tokens and lightweight utilities for ChatV2
//  Platform-safe (iOS + macOS)
//  Created by Cline on 10/28/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Colors (Semantic)

public enum DSColors {
    // Surfaces
    public static var background: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        #endif
    }
    public static var surface: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(.sRGB, red: 0.95, green: 0.95, blue: 0.95, opacity: 1)
        #endif
    }
    public static var surfaceElevated: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(.sRGB, red: 0.92, green: 0.92, blue: 0.92, opacity: 1)
        #endif
    }

    // Content
    public static var primaryText: Color {
        Color.primary
    }
    public static var secondaryText: Color {
        Color.secondary
    }

    // Accents
    public static var accent: Color {
        Color.accentColor
    }
    public static var userBubbleGradientStart: Color {
        Color.accentColor
    }
    public static var userBubbleGradientEnd: Color {
        Color.accentColor.opacity(0.85)
    }

    // Feedback
    public static var info: Color { Color.blue }
    public static var success: Color { Color.green }
    public static var warning: Color { Color.orange }
    public static var danger: Color { Color.red }

    // Chips (10-15% bg opacity)
    public static func chipBackground(for color: Color) -> Color {
        color.opacity(0.12)
    }
}

// MARK: - Typography

public enum DSTypography {
    public static var title: Font { .title3.weight(.semibold) }
    public static var body: Font { .body }
    public static var meta: Font { .caption2 }
    public static var chip: Font { .caption2.weight(.semibold) }
    public static var code: Font { .system(.footnote, design: .monospaced) }
}

// MARK: - Spacing

public enum DSSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

// MARK: - Corners

public enum DSCorners {
    public static let chip: CGFloat = 8
    public static let bubble: CGFloat = 20
    public static let sheet: CGFloat = 24
    public static let control: CGFloat = 12
}

// MARK: - Shadows / Elevation

public enum DSShadows {
    public static func bubble(_ color: Color = .black, opacity: Double = 0.06) -> some ViewModifier {
        ShadowModifier(color: color.opacity(opacity), radius: 2, x: 0, y: 1)
    }
    public static func fab(_ color: Color = .black, opacity: Double = 0.12) -> some ViewModifier {
        ShadowModifier(color: color.opacity(opacity), radius: 6, x: 0, y: 4)
    }

    struct ShadowModifier: ViewModifier {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        func body(content: Content) -> some View {
            content.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
}

public extension View {
    func bubbleShadow() -> some View { modifier(DSShadows.bubble()) }
    func fabShadow() -> some View { modifier(DSShadows.fab()) }
}

// MARK: - Animations

public enum DSAnimations {
    public static let bubbleAppear: Animation = .spring(response: 0.35, dampingFraction: 0.8)
    public static let fastEase: Animation = .easeInOut(duration: 0.2)
    public static let stagePulse: Animation = .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
}

// MARK: - Modifiers

public struct RoundedSectionModifier: ViewModifier {
    let background: Color
    public init(background: Color = DSColors.surface) {
        self.background = background
    }
    public func body(content: Content) -> some View {
        content
            .padding(DSSpacing.md)
            .background(background)
            .cornerRadius(DSCorners.sheet)
    }
}

public struct ChipModifier: ViewModifier {
    let tint: Color
    public init(tint: Color) { self.tint = tint }
    public func body(content: Content) -> some View {
        content
            .font(DSTypography.chip)
            .foregroundColor(tint)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 4)
            .background(DSColors.chipBackground(for: tint))
            .cornerRadius(DSCorners.chip)
    }
}

public extension View {
    func roundedSection(background: Color = DSColors.surface) -> some View {
        modifier(RoundedSectionModifier(background: background))
    }
    func chipStyle(tint: Color) -> some View {
        modifier(ChipModifier(tint: tint))
    }
}

// MARK: - Haptics (safe, no-op on macOS)

public enum DSHaptics {
    public static func selection() {
        #if canImport(UIKit)
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
        #endif
    }
    public static func success() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        #endif
    }
    public static func warning() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
        #endif
    }
}

// MARK: - Utility styles

public struct BubbleBackground: View {
    let isUser: Bool
    public init(isUser: Bool) { self.isUser = isUser }
    public var body: some View {
        Group {
            if isUser {
                LinearGradient(
                    colors: [DSColors.userBubbleGradientStart, DSColors.userBubbleGradientEnd],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                DSColors.surface
            }
        }
        .cornerRadius(DSCorners.bubble)
    }
}
