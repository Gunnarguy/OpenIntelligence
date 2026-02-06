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
import UIKit

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
    case unknown

    /// Detect the current device via utsname()
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
            #if targetEnvironment(simulator)
            let screenHeight = UIScreen.main.nativeBounds.height
            if screenHeight >= 2796 { return .iPhone16ProMax }
            else if screenHeight >= 2556 { return .iPhone16Pro }
            #endif
            return .unknown
        }
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
        case .unknown: return "Unknown Device"
        }
    }

    var chipName: String {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax: return "A17 Pro"
        case .iPhone16, .iPhone16Plus: return "A18"
        case .iPhone16Pro, .iPhone16ProMax: return "A18 Pro"
        case .iPhone17Pro, .iPhone17ProMax: return "A19 Pro"
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

        case .unknown:
            // Default to left-side position
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)
        }
    }
}

// MARK: - Full-Screen X-Ray Overlay

/// Transparent overlay showing ONE glowing border at the actual SoC position.
/// Color blends based on which components are active (CPU/GPU/ANE).
struct HardwareXRayOverlay: View {
    @ObservedObject private var telemetry = HardwareTelemetryState.shared

    private let layout = DeviceComponentLayout.current
    var showDeviceInfo: Bool = false

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

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let socFrame = rectToScreen(layout.socRect, width: screenWidth, height: screenHeight)
            let tapticFrame = rectToScreen(layout.tapticRect, width: screenWidth, height: screenHeight)

            ZStack {
                // Show SoC border when any compute component is active
                if totalIntensity > 0.01 {
                    GlowingSoCBorder(
                        frame: socFrame,
                        color: dominantColor,
                        intensity: totalIntensity,
                        chipName: layout.chipName,
                        activeComponents: activeComponents,
                        cpuIntensity: telemetry.cpuIntensity,
                        gpuIntensity: telemetry.gpuIntensity,
                        aneIntensity: telemetry.aneIntensity
                    )
                }

                // Show Taptic Engine border when haptics fire
                if telemetry.hapticIntensity > 0.01 {
                    GlowingTapticBorder(
                        frame: tapticFrame,
                        intensity: telemetry.hapticIntensity
                    )
                }

                // REMOVED: Activity label - too distracting

                // Mini legend in top-right safe area (unobtrusive)
                // Only shows when HUD is active, fades with activity
                if totalIntensity > 0.01 || telemetry.hapticIntensity > 0.01 {
                    SiliconLegend(
                        chipName: layout.chipName,
                        intensity: max(totalIntensity, telemetry.hapticIntensity)
                    )
                    .position(x: screenWidth - 50, y: geometry.safeAreaInsets.top + 50)
                }

                // Device info (for debugging only)
                if showDeviceInfo {
                    Text("\(layout.displayName)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.3))
                        .position(x: screenWidth / 2, y: screenHeight * 0.02)
                }
            }
        }
        .ignoresSafeArea()
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
/// - Thin, barely-visible border (not distracting)
/// - Minimal glow (just enough to notice)
/// - NO text labels inside (clean, unobtrusive)
/// - Color-coded by dominant component
private struct GlowingSoCBorder: View {
    let frame: CGRect
    let color: Color
    let intensity: Double
    let chipName: String
    let activeComponents: [String]
    let cpuIntensity: Double
    let gpuIntensity: Double
    let aneIntensity: Double

    // SUBTLE: Much smaller glow radius
    private var glowRadius: CGFloat { CGFloat(3 + 6 * intensity) }
    // SUBTLE: Thinner borders
    private var borderWidth: CGFloat { CGFloat(1 + 1.5 * intensity) }
    // SUBTLE: Lower base opacity
    private var baseOpacity: Double { 0.25 + 0.35 * intensity }

    var body: some View {
        ZStack {
            // Single soft glow layer (not 3 separate ones)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(baseOpacity * 0.4), lineWidth: borderWidth + 3)
                .blur(radius: glowRadius)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Main border - thin and subtle
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(baseOpacity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Very subtle inner tint
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.02 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Corner activity dots (instead of labels)
            // Three tiny dots at top-right showing which components are active
            HStack(spacing: 2) {
                if cpuIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.cpu.color.opacity(0.6 + 0.4 * cpuIntensity))
                        .frame(width: 4, height: 4)
                }
                if gpuIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.gpu.color.opacity(0.6 + 0.4 * gpuIntensity))
                        .frame(width: 4, height: 4)
                }
                if aneIntensity > 0.01 {
                    Circle()
                        .fill(HardwareComponent.neuralEngine.color.opacity(0.6 + 0.4 * aneIntensity))
                        .frame(width: 4, height: 4)
                }
            }
            .position(x: frame.maxX - 12, y: frame.minY + 8)
        }
        .animation(.easeOut(duration: 0.2), value: intensity)
    }
}

// MARK: - Glowing Taptic Engine Border

/// ULTRA-SUBTLE border for the Taptic Engine.
/// Appears briefly when haptics fire, then fades.
private struct GlowingTapticBorder: View {
    let frame: CGRect
    let intensity: Double

    private let hapticColor = HardwareComponent.haptic.color

    // SUBTLE: Much smaller glow
    private var glowRadius: CGFloat { CGFloat(4 + 8 * intensity) }
    private var borderWidth: CGFloat { CGFloat(1 + 1.5 * intensity) }
    private var baseOpacity: Double { 0.3 + 0.4 * intensity }

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

            // Subtle inner fill
            RoundedRectangle(cornerRadius: 4)
                .fill(hapticColor.opacity(0.03 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // No text label - just a tiny indicator dot
            Circle()
                .fill(hapticColor.opacity(0.7 + 0.3 * intensity))
                .frame(width: 4, height: 4)
                .position(x: frame.midX, y: frame.midY)
        }
        .animation(.easeOut(duration: 0.1), value: intensity)
    }
}

// MARK: - Silicon Legend

/// Tiny, unobtrusive indicator showing users what the HUD represents.
/// Positioned in a corner, ultra-minimal, helps answer "wtf is this?"
private struct SiliconLegend: View {
    let chipName: String
    let intensity: Double

    private var opacity: Double { 0.4 + 0.3 * intensity }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Tiny chip icon + name
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 8, weight: .medium))
                Text(chipName)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(opacity))

            // "Silicon Activity" hint
            Text("activity")
                .font(.system(size: 7, weight: .regular, design: .monospaced))
                .foregroundColor(.gray.opacity(opacity * 0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.3))
        )
        .animation(.easeOut(duration: 0.3), value: intensity)
    }
}

// MARK: - Preview

#if DEBUG
struct HardwareXRayOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.95)
            HardwareXRayOverlay(showDeviceInfo: true)
        }
        .ignoresSafeArea()
        .onAppear {
            // Simulate activity for preview using public API
            HardwareTelemetryState.shared.sustain(.embeddingGeneration, active: true, intensity: 0.8)
            HardwareTelemetryState.shared.sustain(.vectorSimilarity, active: true, intensity: 0.4)
            HardwareTelemetryState.shared.sustain(.ragOrchestration, active: true, intensity: 0.3)
            HardwareTelemetryState.shared.reportHaptic(style: "preview")
        }
        .previewDisplayName("SoC @ \(DeviceComponentLayout.current.displayName)")
    }
}
#endif
