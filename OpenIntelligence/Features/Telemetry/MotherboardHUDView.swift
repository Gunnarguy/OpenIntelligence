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
    /// VERIFIED via Vision AI analysis of teardown images:
    /// - A18 Pro text label detected at x:13-14%, y:32-37%
    /// - Rectangle detected at x:8%, y:33%, w:23%, h:8.6%
    var socRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // A17 Pro: Similar left-side position to A18
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)

        case .iPhone16, .iPhone16Plus:
            // A18: Same general area
            return CGRect(x: 0.08, y: 0.33, width: 0.24, height: 0.10)

        case .iPhone16Pro, .iPhone16ProMax:
            // A18 Pro: Vision AI detected at x:8-15%, y:32-37%
            // Using rectangle [6]: x:8.2%, y:32.9%, w:22.8%, h:8.6%
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)

        case .iPhone17Pro, .iPhone17ProMax:
            // A19 Pro: Expected similar to 16 Pro
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)

        case .unknown:
            // Default to detected position
            return CGRect(x: 0.08, y: 0.32, width: 0.24, height: 0.10)
        }
    }

    // MARK: - Taptic Engine Position

    /// The Taptic Engine (haptic motor) position at the bottom of the device.
    /// VERIFIED via Vision AI: "TAPTIC ENGINE" label at x:16-18%, y:90-91%
    /// Rectangle detected at x:65%, y:88% suggests the actual component area
    var tapticRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // Vision detected label at x:18%, y:91%
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone16, .iPhone16Plus:
            // Vision detected label at x:16%, y:90%
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone16Pro, .iPhone16ProMax:
            // Vision detected: "TAPTIC ENGINE" at x:16-18%, y:90-91%
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .iPhone17Pro, .iPhone17ProMax:
            return CGRect(x: 0.12, y: 0.88, width: 0.24, height: 0.06)

        case .unknown:
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

                // Activity label below the SoC
                if !telemetry.currentActivityLabel.isEmpty {
                    Text(telemetry.currentActivityLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .position(x: socFrame.midX, y: socFrame.maxY + 40)
                }

                // Device info (for debugging)
                if showDeviceInfo {
                    Text("\(layout.displayName)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
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

/// A single glowing border representing the entire SoC with component indicators
private struct GlowingSoCBorder: View {
    let frame: CGRect
    let color: Color
    let intensity: Double
    let chipName: String
    let activeComponents: [String]
    let cpuIntensity: Double
    let gpuIntensity: Double
    let aneIntensity: Double

    private var glowRadius: CGFloat { CGFloat(6 + 18 * intensity) }
    private var borderWidth: CGFloat { CGFloat(2 + 3 * intensity) }

    var body: some View {
        ZStack {
            // Multi-color glow based on all active components
            if aneIntensity > 0.01 {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HardwareComponent.neuralEngine.color.opacity(0.3 * aneIntensity), lineWidth: borderWidth + 6)
                    .blur(radius: glowRadius * 1.2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            if gpuIntensity > 0.01 {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HardwareComponent.gpu.color.opacity(0.3 * gpuIntensity), lineWidth: borderWidth + 4)
                    .blur(radius: glowRadius)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
            if cpuIntensity > 0.01 {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HardwareComponent.cpu.color.opacity(0.3 * cpuIntensity), lineWidth: borderWidth + 2)
                    .blur(radius: glowRadius * 0.8)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            // Main border with dominant color
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.7 + 0.3 * intensity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Inner fill
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Chip name at top
            Text(chipName)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: color.opacity(0.8), radius: 4)
                .position(x: frame.midX, y: frame.minY + 16)

            // Active component indicators
            HStack(spacing: 8) {
                if cpuIntensity > 0.01 {
                    ComponentIndicator(name: "CPU", color: HardwareComponent.cpu.color, intensity: cpuIntensity)
                }
                if gpuIntensity > 0.01 {
                    ComponentIndicator(name: "GPU", color: HardwareComponent.gpu.color, intensity: gpuIntensity)
                }
                if aneIntensity > 0.01 {
                    ComponentIndicator(name: "ANE", color: HardwareComponent.neuralEngine.color, intensity: aneIntensity)
                }
            }
            .position(x: frame.midX, y: frame.midY + 8)
        }
        .animation(.easeOut(duration: 0.15), value: intensity)
    }
}

// MARK: - Glowing Taptic Engine Border

/// A border representing the Taptic Engine at the bottom of the device
private struct GlowingTapticBorder: View {
    let frame: CGRect
    let intensity: Double

    private let hapticColor = HardwareComponent.haptic.color

    private var glowRadius: CGFloat { CGFloat(8 + 20 * intensity) }
    private var borderWidth: CGFloat { CGFloat(2 + 3 * intensity) }

    var body: some View {
        ZStack {
            // Ripple effect glow (haptics create vibrations)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hapticColor.opacity(0.5 * intensity), lineWidth: borderWidth + 8)
                .blur(radius: glowRadius * 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .scaleEffect(1.0 + 0.1 * intensity) // Subtle pulse

            // Inner glow
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hapticColor.opacity(0.7 * intensity), lineWidth: borderWidth + 2)
                .blur(radius: glowRadius * 0.6)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Main border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(hapticColor.opacity(0.8 + 0.2 * intensity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Inner fill
            RoundedRectangle(cornerRadius: 6)
                .fill(hapticColor.opacity(0.1 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Label
            Text("TAPTIC")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(hapticColor.opacity(0.9))
                .shadow(color: hapticColor.opacity(0.8), radius: 4)
                .position(x: frame.midX, y: frame.midY)
        }
        .animation(.easeOut(duration: 0.08), value: intensity)
    }
}

// MARK: - Component Indicator

/// Small colored indicator showing a component's activity level
private struct ComponentIndicator: View {
    let name: String
    let color: Color
    let intensity: Double

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 3)
            Text(name)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color.opacity(0.8 + 0.2 * intensity))
        }
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
