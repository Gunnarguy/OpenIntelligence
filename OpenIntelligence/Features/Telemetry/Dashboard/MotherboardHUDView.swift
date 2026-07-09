//
//  MotherboardHUDView.swift
//  OpenIntelligence
//
//  Full-screen X-Ray overlay showing where Apple Silicon SoC physically
//  sits behind the iPhone screen. ONE border at the ACTUAL chip location.
//
//  CRITICAL: The CPU, GPU, and Neural Engine are ALL ON ONE ~10mm DIE.
//  They are NOT spread across the screen - they're one tiny chip.
//
//  Physical SoC positions from iFixit teardowns:
//  - iPhone 15 Pro/Max: A17 Pro @ ~38% from left, ~30% from top
//  - iPhone 16/Plus: A18 @ ~40% from left, ~32% from top
//  - iPhone 16 Pro/Max: A18 Pro @ ~45% from left, ~27% from top (centralized)
//  - iPhone 17 Pro/Max: A19 Pro @ similar to 16 Pro
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Combine

// MARK: - Device Layout Configuration

/// Physical SoC position for each Apple Intelligence-capable device.
/// Position normalized (0-1) relative to screen dimensions.
/// Die size ~10mm = ~6-8% of screen width, made slightly larger for visibility.
enum DeviceComponentLayout {

    case iPhone15Pro
    case iPhone15ProMax
    case iPhone16
    case iPhone16Plus
    case iPhone16Pro
    case iPhone16ProMax
    case iPhone17Pro
    case iPhone17ProMax
    case iPadMini
    case iPadAir
    case iPadPro
    case unknown

    /// Detect the current device via utsname()
    @MainActor
    static var current: DeviceComponentLayout {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        switch identifier {
        case "iPhone16,1": return .iPhone15Pro
        case "iPhone16,2": return .iPhone15ProMax
        case "iPhone17,3": return .iPhone16
        case "iPhone17,4": return .iPhone16Plus
        case "iPhone17,1": return .iPhone16Pro
        case "iPhone17,2": return .iPhone16ProMax
        case "iPhone18,1", "iPhone18,3": return .iPhone17Pro
        case "iPhone18,2", "iPhone18,4": return .iPhone17ProMax
        default:
            if identifier.hasPrefix("iPad") {
                let numbers = identifier.replacingOccurrences(of: "iPad", with: "")
                    .split(separator: ",")
                    .compactMap { Int($0) }
                if let major = numbers.first {
                    if major == 13 { return .iPadPro } // iPad Pro M1
                    if major == 14 {
                        let minor = numbers.count > 1 ? numbers[1] : 0
                        if minor <= 2 { return .iPadMini } // iPad mini 6
                        if minor >= 3 && minor <= 6 { return .iPadPro } // iPad Pro M2
                        if minor >= 8 { return .iPadAir } // iPad Air M2
                    }
                    if major == 15 { return .iPadAir } // iPad Air M3
                    if major == 16 {
                        let minor = numbers.count > 1 ? numbers[1] : 0
                        if minor <= 2 { return .iPadMini } // iPad mini 7 (A17 Pro)
                        return .iPadPro // iPad Pro M4
                    }
                    if major >= 17 { return .iPadPro }
                }
                return .iPadPro
            }

            #if targetEnvironment(simulator)
            let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
            if simModel.hasPrefix("iPhone") {
                let screenHeight = simulatorNativeScreenHeight()
                if screenHeight >= 2796 { return .iPhone16ProMax }
                else if screenHeight >= 2556 { return .iPhone16Pro }
            } else if simModel.hasPrefix("iPad") {
                if simModel.contains("mini") { return .iPadMini }
                if simModel.contains("Air") { return .iPadAir }
                return .iPadPro
            }
            #endif
            return .unknown
        }
    }

    @MainActor
    private static func simulatorNativeScreenHeight() -> CGFloat {
#if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
        return screen?.nativeBounds.height ?? 0
#else
        return 0
#endif
    }

    var displayName: String {
        switch self {
        case .iPhone15Pro: return "iPhone 15 Pro"
        case .iPhone15ProMax: return "iPhone 15 Pro Max"
        case .iPhone16: return "iPhone 16"
        case .iPhone16Plus: return "iPhone 16 Plus"
        case .iPhone16Pro: return "iPhone 16 Pro"
        case .iPhone16ProMax: return "iPhone 16 Pro Max"
        case .iPhone17Pro: return "iPhone 17 Pro"
        case .iPhone17ProMax: return "iPhone 17 Pro Max"
        case .iPadMini: return "iPad mini"
        case .iPadAir: return "iPad Air"
        case .iPadPro: return "iPad Pro"
        case .unknown: return "Unknown Device"
        }
    }

    var chipName: String {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax: return "A17 Pro"
        case .iPhone16, .iPhone16Plus: return "A18"
        case .iPhone16Pro, .iPhone16ProMax: return "A18 Pro"
        case .iPhone17Pro, .iPhone17ProMax: return "A19 Pro"
        case .iPadMini: return "A17 Pro"
        case .iPadAir: return "Apple M2"
        case .iPadPro: return "Apple M4"
        case .unknown: return "Apple Silicon"
        }
    }

    // MARK: - SoC Position (ONE chip, ONE location)

    /// The actual position of the SoC die behind the screen.
    /// VERIFIED via Vision AI analysis of X-ray images (Feb 2026):
    /// - iPhone 15 Pro Max: A17 @ x:17%, y:37%
    /// - iPhone 16 Pro: A18 @ x:13%, y:32%
    /// - iPhone 16 Pro Max: A18 @ x:14%, y:35%
    /// - iPhone 17 Pro Max: A19 @ x:38%, y:31% (MORE CENTERED!)
    var socRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // Vision AI: A17 label at x:17.3%, y:36.6%
            // Rectangle [6]: x:8.2%, y:33.7%, w:28.3%, h:13.7%
            return CGRect(x: 0.08, y: 0.33, width: 0.28, height: 0.12)

        case .iPhone16, .iPhone16Plus:
            // A18: Similar to 16 Pro
            return CGRect(x: 0.08, y: 0.30, width: 0.26, height: 0.10)

        case .iPhone16Pro:
            // Vision AI: A18 label at x:13.3%, y:32.0%
            return CGRect(x: 0.08, y: 0.30, width: 0.26, height: 0.10)

        case .iPhone16ProMax:
            // Vision AI: A18 label at x:14.3%, y:34.9%
            // Rectangle [6]: x:8.2%, y:32.9%, w:22.8%, h:8.6%
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)

        case .iPhone17Pro, .iPhone17ProMax:
            // Vision AI: A19 label at x:37.5%, y:30.7% - DIFFERENT LAYOUT!
            // Rectangle [5]: x:35.5%, y:27.5%, w:14.8%, h:9.6%
            // SoC moved to CENTER of device
            return CGRect(x: 0.32, y: 0.26, width: 0.20, height: 0.12)

        case .iPadMini:
            return CGRect(x: 0.12, y: 0.35, width: 0.16, height: 0.12)

        case .iPadAir:
            return CGRect(x: 0.40, y: 0.44, width: 0.20, height: 0.12)

        case .iPadPro:
            return CGRect(x: 0.42, y: 0.44, width: 0.16, height: 0.12)

        case .unknown:
            // Default to iPhone 16 Pro Max position
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)
        }
    }

    // MARK: - Taptic Engine Position

    /// The Taptic Engine (haptic motor) position at the bottom of the device.
    /// VERIFIED via Vision AI X-ray analysis:
    /// - iPhone 15/16: LEFT side (x:14-18%, y:90-91%)
    /// - iPhone 17: RIGHT side (x:63%, y:91%) - ARCHITECTURE CHANGE!
    var tapticRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // Vision AI: "TAPTIC ENGINE" at x:13.8%, y:90.7%
            return CGRect(x: 0.10, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone16, .iPhone16Plus:
            // Similar to 16 Pro
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone16Pro:
            // Vision AI: "TAPTIC ENGINE" at x:17.9%, y:91.0%
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone16ProMax:
            // Vision AI: "TAPTIC ENGINE" at x:15.9%, y:89.9%
            return CGRect(x: 0.12, y: 0.87, width: 0.24, height: 0.06)

        case .iPhone17Pro, .iPhone17ProMax:
            // Vision AI: "TAPTIC ENGINE" at x:62.8%, y:90.7% - MOVED TO RIGHT!
            // Rectangle [6]: x:61.0%, y:88.5%, w:26.6%, h:4.7%
            return CGRect(x: 0.58, y: 0.87, width: 0.28, height: 0.06)

        case .iPadMini, .iPadAir, .iPadPro:
            return CGRect(x: 0.38, y: 0.92, width: 0.24, height: 0.04)

        case .unknown:
            // Default to left-side position
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)
        }
    }
}

// MARK: - Keyboard Height Observer

/// Tracks keyboard height for floating indicator positioning
#if canImport(UIKit)
final class KeyboardHeightObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.keyboardHeight = frame.height
                    self.isKeyboardVisible = true
                }
            }
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                self.keyboardHeight = 0
                self.isKeyboardVisible = false
            }
        }
    }
}
#else
/// macOS stub — keyboard height is always zero on macOS.
final class KeyboardHeightObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false
}
#endif

// MARK: - Full-Screen X-Ray Overlay

/// Transparent overlay showing ONE glowing border at the actual SoC position.
/// DESIGN: Ultra-subtle background visualization - present but not distracting.
/// Color blends based on which components are active (CPU/GPU/ANE).
struct HardwareXRayOverlay: View {
    private var telemetry = HardwareTelemetryState.shared
    @StateObject private var keyboardObserver = KeyboardHeightObserver()
    @EnvironmentObject private var settings: SettingsStore

    private let layout = DeviceComponentLayout.current
    var showDeviceInfo: Bool = false
    var showSidebar: Bool = false

    /// Combined intensity from all active components
    private var totalIntensity: Double {
        max(telemetry.cpuIntensity, telemetry.gpuIntensity, telemetry.aneIntensity)
    }

    /// Dominant color based on which component is most active
    private var dominantColor: Color {
        let cpu = telemetry.cpuIntensity
        let gpu = telemetry.gpuIntensity
        let ane = telemetry.aneIntensity

        if ane >= gpu && ane >= cpu {
            return HardwareComponent.neuralEngine.color // Purple
        } else if gpu >= cpu {
            return HardwareComponent.gpu.color // Cyan
        } else {
            return HardwareComponent.cpu.color // Orange
        }
    }

    /// Active component labels
    private var activeComponents: [String] {
        var components: [String] = []
        if telemetry.aneIntensity > 0.01 { components.append("ANE") }
        if telemetry.gpuIntensity > 0.01 { components.append("GPU") }
        if telemetry.cpuIntensity > 0.01 { components.append("CPU") }
        return components
    }

    #if canImport(UIKit)
    private var currentOrientation: UIInterfaceOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .portrait
        }
        return scene.effectiveGeometry.interfaceOrientation
    }
    #endif

    private func orientRect(_ rect: CGRect) -> CGRect {
        #if canImport(UIKit)
        let orientation = currentOrientation
        switch orientation {
        case .landscapeLeft:
            return CGRect(
                x: rect.minY,
                y: 1 - rect.minX - rect.width,
                width: rect.height,
                height: rect.width
            )
        case .landscapeRight:
            return CGRect(
                x: 1 - rect.minY - rect.height,
                y: rect.minX,
                width: rect.height,
                height: rect.width
            )
        case .portraitUpsideDown:
            return CGRect(
                x: 1 - rect.minX - rect.width,
                y: 1 - rect.minY - rect.height,
                width: rect.width,
                height: rect.height
            )
        default:
            return rect
        }
        #else
        return rect
        #endif
    }

    private var isMac: Bool {
        #if os(macOS)
        return true
        #elseif targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    var body: some View {
        if isMac {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let screenWidth = geometry.size.width
                let screenHeight = geometry.size.height
            
            let orientedSoc = orientRect(layout.socRect)
            let orientedTaptic = orientRect(layout.tapticRect)
            
            let socFrame = rectToScreen(orientedSoc, width: screenWidth, height: screenHeight)
            let tapticFrame = rectToScreen(orientedTaptic, width: screenWidth, height: screenHeight)

            let showVisualBorders: Bool = {
                #if os(macOS)
                return false
                #elseif targetEnvironment(macCatalyst)
                return false
                #else
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    return false
                }
                return true
                #endif
            }()

            ZStack {
                // Show SoC border when any compute component is active
                // DESIGN: Ultra-subtle background presence - not distracting
                if showVisualBorders && totalIntensity > 0.01 {
                    GlowingSoCBorder(
                        frame: socFrame,
                        color: dominantColor,
                        intensity: totalIntensity,
                        glowMultiplier: settings.hudGlowIntensity, // User-controlled
                        chipName: layout.chipName,
                        activeComponents: activeComponents,
                        cpuIntensity: telemetry.cpuIntensity,
                        gpuIntensity: telemetry.gpuIntensity,
                        aneIntensity: telemetry.aneIntensity
                    )
                }

                // Show Taptic Engine border when haptics fire (if enabled)
                // Shows at the physical Taptic Engine location
                if showVisualBorders && settings.hudShowTaptic && telemetry.hapticIntensity > 0.01 {
                    GlowingTapticBorder(
                        frame: tapticFrame,
                        intensity: telemetry.hapticIntensity,
                        glowMultiplier: settings.hudGlowIntensity
                    )
                }

                // REMOVED: FloatingTapticIndicator - users want Taptic in HUD legend only

                // REMOVED: Activity label - too distracting

                // Mini legend on LEFT side, below nav bar area
                // Persists as long as HUD is enabled; shows triggered components
                // COMPACT: Positioned tighter to corner to minimize interference
                if isMac {
                    SiliconLegend(
                        chipName: layout.chipName,
                        intensity: max(totalIntensity, telemetry.hapticIntensity),
                        metricsSummary: settings.hudShowMetrics ? telemetry.compactMetricsSummary : "",
                        activities: settings.hudShowMetrics ? telemetry.componentActivities : []
                    )
                    .scaleEffect(1.4, anchor: .bottomLeading)
                    .padding(.bottom, 130)
                    .padding(.leading, 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                } else {
                    SiliconLegend(
                        chipName: layout.chipName,
                        intensity: max(totalIntensity, telemetry.hapticIntensity),
                        metricsSummary: settings.hudShowMetrics ? telemetry.compactMetricsSummary : "",
                        activities: settings.hudShowMetrics ? telemetry.componentActivities : []
                    )
                    .position(x: showSidebar ? 345 : 45, y: geometry.safeAreaInsets.top + 85)
                }

                // Device info (for debugging only)
                if showDeviceInfo && showVisualBorders {
                    Text("\(layout.displayName)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.3))
                        .position(x: screenWidth / 2, y: screenHeight * 0.02)
                }
            }
            .ignoresSafeArea()
        }
    }
    }

    private func rectToScreen(_ rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * width,
            y: rect.minY * height,
            width: rect.width * width,
            height: rect.height * height
        )
    }
}

// MARK: - Glowing SoC Border

/// ULTRA-SUBTLE border showing the actual SoC location.
/// Design principles:
/// - Thin, barely-visible border (background presence, not distracting)
/// - Minimal glow (just enough to notice if you're looking)
/// - NO text labels inside (clean, unobtrusive)
/// - Color-coded by dominant component
/// - Should NOT take over screen real estate
private struct GlowingSoCBorder: View {
    let frame: CGRect
    let color: Color
    let intensity: Double
    var glowMultiplier: Double = 0.6
    let chipName: String
    let activeComponents: [String]
    let cpuIntensity: Double
    let gpuIntensity: Double
    let aneIntensity: Double

    // MORE VISIBLE: Increased glow for better visibility
    private var glowRadius: CGFloat { CGFloat((4 + 8 * intensity) * glowMultiplier) }
    // MORE VISIBLE: Thicker borders
    private var borderWidth: CGFloat { CGFloat((1.0 + 2.0 * intensity) * max(0.5, glowMultiplier)) }
    // MORE VISIBLE: Higher base opacity so users can actually see it
    private var baseOpacity: Double { (0.35 + 0.45 * intensity) * glowMultiplier }

    var body: some View {
        ZStack {
            // Single soft glow layer (not 3 separate ones)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(baseOpacity * 0.3), lineWidth: borderWidth + 2)
                .blur(radius: glowRadius)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Main border - more visible
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(baseOpacity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Inner tint - more visible fill
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.05 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Corner activity dots (instead of labels)
            // Three tiny dots at top-right showing which components are active
            HStack(spacing: 3) {
                if cpuIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.cpu.color.opacity(0.7 + 0.3 * cpuIntensity))
                        .frame(width: 6, height: 6)
                }
                if gpuIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.gpu.color.opacity(0.7 + 0.3 * gpuIntensity))
                        .frame(width: 6, height: 6)
                }
                if aneIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.neuralEngine.color.opacity(0.7 + 0.3 * aneIntensity))
                        .frame(width: 6, height: 6)
                }
            }
            .position(x: frame.maxX - 14, y: frame.minY + 10)
        }
        // FAST animation for real-time profiler feel
        .animation(.linear(duration: 0.03), value: intensity)
    }
}

// MARK: - Glowing Taptic Engine Border

/// ULTRA-SUBTLE border for the Taptic Engine.
/// Appears briefly when haptics fire, then fades.
private struct GlowingTapticBorder: View {
    let frame: CGRect
    let intensity: Double
    var glowMultiplier: Double = 0.6

    private let hapticColor = HardwareComponent.haptic.color

    // Glow scaled by user preference — boosted so it's actually visible
    private var glowRadius: CGFloat { CGFloat((6 + 14 * intensity) * max(0.5, glowMultiplier)) }
    private var borderWidth: CGFloat { CGFloat((1.5 + 2.0 * intensity) * max(0.5, glowMultiplier)) }
    private var baseOpacity: Double { (0.5 + 0.5 * intensity) * max(0.5, glowMultiplier) }

    var body: some View {
        ZStack {
            // Single soft glow
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(hapticColor.opacity(baseOpacity * 0.5), lineWidth: borderWidth + 2)
                .blur(radius: glowRadius)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Main border - thin
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(hapticColor.opacity(baseOpacity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Inner fill — visible flash on fire
            RoundedRectangle(cornerRadius: 4)
                .fill(hapticColor.opacity(0.08 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Center indicator dot — bright so it's unmissable
            Circle()
                .fill(hapticColor.opacity(0.8 + 0.2 * intensity))
                .frame(width: 5, height: 5)
                .position(x: frame.midX, y: frame.midY)
        }
        // FAST animation for real-time profiler feel
        .animation(.linear(duration: 0.02), value: intensity)
    }
}

// MARK: - Floating Taptic Indicator (Above Keyboard)

/// Compact floating indicator that appears above the keyboard when typing.
/// Shows Taptic Engine activity without being blocked by keyboard.
private struct FloatingTapticIndicator: View {
    let intensity: Double
    var glowMultiplier: Double = 0.6

    private let hapticColor = HardwareComponent.haptic.color

    var body: some View {
        HStack(spacing: 6) {
            // Pulsing dot
            Circle()
                .fill(hapticColor.opacity(0.6 + 0.4 * intensity))
                .frame(width: 6, height: 6)
                .scaleEffect(0.8 + 0.4 * intensity)

            // Label
            Text("Taptic")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(hapticColor.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(
                    Capsule()
                        .strokeBorder(hapticColor.opacity(0.3 * glowMultiplier), lineWidth: 1)
                )
        )
        .shadow(color: hapticColor.opacity(0.3 * intensity * glowMultiplier), radius: 8)
        // FAST animation for real-time profiler feel
        .animation(.linear(duration: 0.02), value: intensity)
    }
}

// MARK: - Silicon Legend

/// Tiny, unobtrusive indicator showing users what the HUD represents.
/// Shows each triggered component with % contribution bar.
/// COMPACT: Minimal footprint to avoid interfering with app content.
private struct SiliconLegend: View {
    let chipName: String
    let intensity: Double
    let metricsSummary: String
    var activities: [HardwareTelemetryState.ComponentActivity] = []

    private var opacity: Double { 0.45 + 0.15 * min(intensity, 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Chip header - compact single line
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 7, weight: .medium))
                Text(chipName)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(opacity))

            // Per-component breakdown with % contribution bars
            if !activities.isEmpty {
                // Compute components (ANE/GPU/CPU) — show % contribution
                ForEach(activities.filter { $0.percentage >= 0 }, id: \.name) { activity in
                    HStack(spacing: 3) {
                        // Active indicator dot (glows when firing)
                        Circle()
                            .fill(componentColor(activity.color).opacity(activity.isActive ? 0.85 : 0.3))
                            .frame(width: 3, height: 3)

                        // Component name — compact fixed width
                        Text(activity.name)
                            .font(.system(size: 6, weight: .semibold, design: .monospaced))
                            .foregroundColor(componentColor(activity.color).opacity(0.65))
                            .frame(width: 24, alignment: .leading)

                        // Mini percentage bar - narrower
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 2)

                                // Fill
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(componentColor(activity.color).opacity(activity.isActive ? 0.65 : 0.35))
                                    .frame(width: max(1, geo.size.width * CGFloat(activity.percentage / 100.0)), height: 2)
                            }
                            .frame(height: geo.size.height)
                        }
                        .frame(width: 22, height: 4)

                        // Percentage text
                        Text("\(Int(activity.percentage))%")
                            .font(.system(size: 6, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(width: 18, alignment: .trailing)
                    }
                }

                // Taptic Engine — separate indicator, not competing with compute %
                if let taptic = activities.first(where: { $0.name == "Taptic" }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(componentColor(taptic.color).opacity(taptic.isActive ? 0.85 : 0.3))
                            .frame(width: 3, height: 3)

                        Text("Tap")
                            .font(.system(size: 6, weight: .semibold, design: .monospaced))
                            .foregroundColor(componentColor(taptic.color).opacity(0.65))
                            .frame(width: 24, alignment: .leading)

                        // Show fire count instead of % — it's an output device
                        Text("×\(taptic.opsCount)")
                            .font(.system(size: 6, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } else if !metricsSummary.isEmpty {
                // Fallback to compact summary
                Text(metricsSummary)
                    .font(.system(size: 6, weight: .regular, design: .monospaced))
                    .foregroundColor(.cyan.opacity(opacity * 0.7))
                    .lineLimit(2)
            } else {
                Text("idle")
                    .font(.system(size: 6, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.25))
        )
        // Only animate structural changes (new rows appearing), not every tick
        .animation(.easeOut(duration: 0.4), value: activities.count)
    }

    private func componentColor(_ name: String) -> Color {
        switch name {
        case "purple": return HardwareComponent.neuralEngine.color
        case "cyan": return HardwareComponent.gpu.color
        case "orange": return HardwareComponent.cpu.color
        case "pink": return HardwareComponent.haptic.color
        default: return .white
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("SoC Hardware X-Ray") {
    ZStack {
        Color.black.opacity(0.95)
        HardwareXRayOverlay()
    }
    .ignoresSafeArea()
    .onAppear {
        // Simulate activity for preview using public API
        HardwareTelemetryState.shared.sustain(.embeddingGeneration, active: true, intensity: 0.8)
        HardwareTelemetryState.shared.sustain(.vectorSimilarity, active: true, intensity: 0.4)
        HardwareTelemetryState.shared.sustain(.ragOrchestration, active: true, intensity: 0.3)
        HardwareTelemetryState.shared.reportHaptic(style: "preview")
    }
}
#endif
