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
#if canImport(CoreHaptics)
import CoreHaptics
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

    public static var systemGray6: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray6)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.sRGB, red: 0.92, green: 0.92, blue: 0.92, opacity: 1)
        #endif
    }

    public static var systemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.sRGB, red: 0.95, green: 0.95, blue: 0.97, opacity: 1)
        #endif
    }

    public static var secondarySystemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        #endif
    }

    public static var tertiarySystemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(.sRGB, red: 0.92, green: 0.92, blue: 0.95, opacity: 1)
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

    // Borders & Separators
    public static var border: Color {
        Color.primary.opacity(0.15)
    }
    public static var separator: Color {
        Color.primary.opacity(0.1)
    }

    // Chips (10-15% bg opacity)
    public static func chipBackground(for color: Color) -> Color {
        color.opacity(0.12)
    }
}

// MARK: - Typography

public enum DSTypography {
    public static var title: Font { .title3.weight(.semibold) }
    public static var body: Font { .body }
    public static var caption: Font { .caption }
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
    public static let control: CGFloat = 12
    public static let card: CGFloat = 16
    public static let bubble: CGFloat = 20
    public static let sheet: CGFloat = 24
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
    public static let snappySpring: Animation = .spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1)
    public static let gentleSpring: Animation = .spring(response: 0.5, dampingFraction: 0.8)
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

// MARK: - Liquid Glass (iOS 26+)

/// Liquid Glass design system integration for iOS 26
/// Applies translucent glass effects to surfaces, toolbars, and cards
public enum DSGlass {
    /// Apply glass effect to a navigation bar or toolbar
    @available(iOS 26.0, *)
    public static func toolbarMaterial() -> some ShapeStyle {
        .regularMaterial
    }

    /// Glass card background for elevated content
    public static var cardBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    /// Glass surface for floating panels
    public static var panelBackground: some ShapeStyle {
        .thinMaterial
    }
}

/// View modifier that applies Liquid Glass styling to a card/surface
public struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = DSCorners.card) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .padding(DSSpacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// View modifier for glass-style toolbar appearance
public struct GlassToolbarModifier: ViewModifier {
    public func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        content
        #endif
    }
}

/// View modifier for glass-style tab bar
public struct GlassTabBarModifier: ViewModifier {
    public func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        #else
        content
        #endif
    }
}

#if os(macOS)
public enum NavigationBarItem {
    public enum TitleDisplayMode {
        case inline
        case large
        case automatic
    }
}

public extension View {
    @inlinable
    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
}
#endif

public extension View {
    /// Apply Liquid Glass card styling
    func glassCard(cornerRadius: CGFloat = DSCorners.card) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Apply Liquid Glass toolbar styling
    func glassToolbar() -> some View {
        modifier(GlassToolbarModifier())
    }

    /// Apply Liquid Glass tab bar styling
    func glassTabBar() -> some View {
        modifier(GlassTabBarModifier())
    }

    /// Apply Liquid Glass pill styling for iOS 26+
    @ViewBuilder
    func glassEffectHelper(isSelected: Bool = false, tintColor: Color = .accentColor) -> some View {
        if #available(iOS 26.0, *) {
            if isSelected {
                self.glassEffect(.regular.tint(tintColor).interactive(), in: Capsule())
            } else {
                self.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            self
        }
    }

    /// Apply Liquid Glass circle shape effect for iOS 26+
    @ViewBuilder
    func glassCircleEffectHelper() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
    }
}

// MARK: - Haptics (safe, no-op on macOS)

public enum DSHaptics {
    #if canImport(UIKit)
    private static let isHapticCapable: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 14.0, *) {
            if ProcessInfo.processInfo.isiOSAppOnMac { return false }
        }
        #if canImport(CoreHaptics)
        if #available(iOS 13.0, *) {
            return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
        #endif
        return true
        #endif
    }()

    private static func perform(_ style: String, _ action: () -> Void) {
        guard isHapticCapable else { return }
        action()
        reportToTelemetry(style: style)
    }

    /// Report haptic to telemetry for HUD visualization
    private static func reportToTelemetry(style: String) {
        Task { @MainActor in
            HardwareTelemetryState.shared.reportHaptic(style: style)
        }
    }
    #endif

    // MARK: - Selection Feedback

    public static func selection() {
        #if canImport(UIKit)
        perform("selection") {
            let gen = UISelectionFeedbackGenerator()
            gen.prepare()
            gen.selectionChanged()
        }
        #endif
    }

    // MARK: - Impact Feedback (Physical Interactions)

    /// Very soft tap - subtle UI acknowledgment
    public static func soft() {
        #if canImport(UIKit)
        perform("soft") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Light tap - buttons, toggles
    public static func light() {
        #if canImport(UIKit)
        perform("light") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Medium tap - confirmations, selections
    public static func medium() {
        #if canImport(UIKit)
        perform("medium") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Heavy tap - important actions, completions
    public static func heavy() {
        #if canImport(UIKit)
        perform("heavy") {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    /// Rigid tap - solid mechanical feel
    public static func rigid() {
        #if canImport(UIKit)
        perform("rigid") {
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.prepare()
            gen.impactOccurred()
        }
        #endif
    }

    // MARK: - Impact with Intensity

    /// Light impact with custom intensity (0.0-1.0)
    public static func lightWithIntensity(_ intensity: CGFloat) {
        #if canImport(UIKit)
        perform("light-\(Int(intensity * 100))") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: min(1.0, max(0.0, intensity)))
        }
        #endif
    }

    /// Medium impact with custom intensity (0.0-1.0)
    public static func mediumWithIntensity(_ intensity: CGFloat) {
        #if canImport(UIKit)
        perform("medium-\(Int(intensity * 100))") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: min(1.0, max(0.0, intensity)))
        }
        #endif
    }

    // MARK: - Notification Feedback (Status Changes)

    /// Success - task completed, positive outcome
    public static func success() {
        #if canImport(UIKit)
        perform("success") {
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
        }
        #endif
    }

    /// Warning - attention needed, caution
    public static func warning() {
        #if canImport(UIKit)
        perform("warning") {
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.warning)
        }
        #endif
    }

    /// Error - something went wrong
    public static func error() {
        #if canImport(UIKit)
        perform("error") {
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.error)
        }
        #endif
    }

    // MARK: - Semantic Haptics (Contextual)

    /// Send a message
    public static func messageSent() {
        #if canImport(UIKit)
        perform("message-sent") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.7)
        }
        #endif
    }

    /// Receive a message or response
    public static func messageReceived() {
        #if canImport(UIKit)
        perform("message-received") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred(intensity: 0.5)
        }
        #endif
    }

    /// Toggle switch changed
    public static func toggle() {
        #if canImport(UIKit)
        perform("toggle") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.6)
        }
        #endif
    }

    /// Slider/progress tick
    public static func tick() {
        #if canImport(UIKit)
        perform("tick") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.3)
        }
        #endif
    }

    /// Processing pulse - repeated during long operations
    public static func processingPulse() {
        #if canImport(UIKit)
        perform("processing") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.55)
        }
        #endif
    }

    /// First token arrived from LLM — the "brain lit up" moment
    public static func generationStarted() {
        #if canImport(UIKit)
        perform("generation-start") {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred(intensity: 0.8)
        }
        #endif
    }

    /// Per-token tick during LLM streaming — noticeable but not annoying
    public static func generationTick() {
        #if canImport(UIKit)
        perform("generation-tick") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// LLM finished generating — satisfying completion tap
    public static func generationComplete() {
        #if canImport(UIKit)
        perform("generation-complete") {
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
        }
        #endif
    }

    /// Battery/thermal state change
    public static func thermalPulse(intensity: CGFloat = 0.5) {
        #if canImport(UIKit)
        perform("thermal-\(Int(intensity * 100))") {
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.prepare()
            gen.impactOccurred(intensity: min(1.0, max(0.2, intensity)))
        }
        #endif
    }

    /// Navigation/transition
    public static func navigate() {
        #if canImport(UIKit)
        perform("navigate") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// Document ingested
    public static func documentIngested() {
        #if canImport(UIKit)
        perform("ingested") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.6)
        }
        #endif
    }

    /// Chunk processed (very subtle)
    public static func chunkProcessed() {
        #if canImport(UIKit)
        perform("chunk") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred(intensity: 0.2)
        }
        #endif
    }

    // MARK: - UI Navigation Haptics

    /// Tab bar tab changed
    public static func tabChanged() {
        #if canImport(UIKit)
        perform("tab") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.5)
        }
        #endif
    }

    /// Pull-to-refresh triggered
    public static func refresh() {
        #if canImport(UIKit)
        perform("refresh") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.7)
        }
        #endif
    }

    /// Section/disclosure expanded
    public static func expand() {
        #if canImport(UIKit)
        perform("expand") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// Section/disclosure collapsed
    public static func collapse() {
        #if canImport(UIKit)
        perform("collapse") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred(intensity: 0.3)
        }
        #endif
    }

    /// Sheet/modal presented
    public static func sheetPresented() {
        #if canImport(UIKit)
        perform("sheet-present") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.5)
        }
        #endif
    }

    /// Sheet/modal dismissed
    public static func sheetDismissed() {
        #if canImport(UIKit)
        perform("sheet-dismiss") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// Long press recognized
    public static func longPress() {
        #if canImport(UIKit)
        perform("long-press") {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred(intensity: 0.8)
        }
        #endif
    }

    /// Drag operation started
    public static func dragStart() {
        #if canImport(UIKit)
        perform("drag-start") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.5)
        }
        #endif
    }

    /// Drop operation completed
    public static func drop() {
        #if canImport(UIKit)
        perform("drop") {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.prepare()
            gen.impactOccurred(intensity: 0.7)
        }
        #endif
    }

    /// Copy to clipboard
    public static func copy() {
        #if canImport(UIKit)
        perform("copy") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.5)
        }
        #endif
    }

    /// Delete/remove action
    public static func delete() {
        #if canImport(UIKit)
        perform("delete") {
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.prepare()
            gen.impactOccurred(intensity: 0.6)
        }
        #endif
    }

    /// Search/query initiated
    public static func search() {
        #if canImport(UIKit)
        perform("search") {
            let gen = UIImpactFeedbackGenerator(style: .soft)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// Filter applied
    public static func filter() {
        #if canImport(UIKit)
        perform("filter") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.4)
        }
        #endif
    }

    /// Scroll snap/page change
    public static func pageSnap() {
        #if canImport(UIKit)
        perform("page-snap") {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.prepare()
            gen.impactOccurred(intensity: 0.3)
        }
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

// MARK: - Haptic Button Styles

/// A ButtonStyle that fires haptic feedback on press
public struct HapticButtonStyle: ButtonStyle {
    public enum HapticType {
        case light, medium, soft, selection
    }

    let hapticType: HapticType

    public init(_ type: HapticType = .light) {
        self.hapticType = type
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    switch hapticType {
                    case .light: DSHaptics.light()
                    case .medium: DSHaptics.medium()
                    case .soft: DSHaptics.soft()
                    case .selection: DSHaptics.selection()
                    }
                }
            }
    }
}

// MARK: - Haptic View Modifiers

extension View {
    /// Add a light haptic tap to any view
    public func hapticTap(_ style: HapticButtonStyle.HapticType = .light) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                switch style {
                case .light: DSHaptics.light()
                case .medium: DSHaptics.medium()
                case .soft: DSHaptics.soft()
                case .selection: DSHaptics.selection()
                }
            }
        )
    }

    /// Trigger haptic when value changes
    public func hapticOnChange<V: Equatable>(of value: V, perform: @escaping (V) -> Void = { _ in }) -> some View {
        self.onChange(of: value) { oldValue, newValue in
            if oldValue != newValue {
                DSHaptics.toggle()
                perform(newValue)
            }
        }
    }
}
