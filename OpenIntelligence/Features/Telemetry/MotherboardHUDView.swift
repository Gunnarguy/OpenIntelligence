//
//  MotherboardHUDView.swift
//  OpenIntelligence
//
//  Full-screen X-Ray overlay showing where Apple Silicon components physically
//  sit behind the iPhone screen. Borders glow at the ACTUAL positions.
//
//  Device-specific layouts based on teardown analysis:
//  - iPhone 15 Pro/Max: A17 Pro, older internal architecture
//  - iPhone 16/Plus: A18, reengineered thermal design
//  - iPhone 16 Pro/Max: A18 Pro, CENTRALIZED chip placement
//  - iPhone 17 Pro/Max: A19 Pro, anticipated similar to 16 Pro
//
//  All Apple Intelligence-capable devices have their SoC in the upper
//  portion of the device, but exact positioning varies by model.
//

import SwiftUI
import UIKit

// MARK: - Device Layout Configuration

/// Physical component positions for each Apple Intelligence-capable device.
/// Positions are normalized (0-1) relative to screen dimensions.
/// Based on iFixit teardowns and Apple technical documentation.
enum DeviceComponentLayout {
    
    // MARK: - iPhone 15 Pro (A17 Pro) - Original AI-capable layout
    // Internals behind screen, older thermal architecture
    case iPhone15Pro
    case iPhone15ProMax
    
    // MARK: - iPhone 16 (A18) - Reengineered internal design
    // New thermal management, larger battery
    case iPhone16
    case iPhone16Plus
    
    // MARK: - iPhone 16 Pro (A18 Pro) - CENTRALIZED chip placement
    // New thermal architecture with machined aluminum chassis
    case iPhone16Pro
    case iPhone16ProMax
    
    // MARK: - iPhone 17 Pro (A19 Pro) - Expected similar to 16 Pro
    case iPhone17Pro
    case iPhone17ProMax
    
    // MARK: - Fallback for unknown devices
    case unknown
    
    /// Detect the current device and return appropriate layout
    static var current: DeviceComponentLayout {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // iPhone identifiers: https://www.theiphonewiki.com/wiki/Models
        switch identifier {
        // iPhone 15 Pro
        case "iPhone16,1":
            return .iPhone15Pro
        case "iPhone16,2":
            return .iPhone15ProMax
        // iPhone 16
        case "iPhone17,3":
            return .iPhone16
        case "iPhone17,4":
            return .iPhone16Plus
        // iPhone 16 Pro
        case "iPhone17,1":
            return .iPhone16Pro
        case "iPhone17,2":
            return .iPhone16ProMax
        // iPhone 17 series (predicted identifiers)
        case "iPhone18,1", "iPhone18,3":
            return .iPhone17Pro
        case "iPhone18,2", "iPhone18,4":
            return .iPhone17ProMax
        default:
            // Simulator or unknown device - use 16 Pro Max as default
            #if targetEnvironment(simulator)
            // In simulator, check screen size to guess device
            let screenHeight = UIScreen.main.nativeBounds.height
            if screenHeight >= 2796 { // Pro Max size
                return .iPhone16ProMax
            } else if screenHeight >= 2556 { // Pro size
                return .iPhone16Pro
            }
            #endif
            return .unknown
        }
    }
    
    /// Human-readable device name for display
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
    
    /// SoC chip name
    var chipName: String {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            return "A17 Pro"
        case .iPhone16, .iPhone16Plus:
            return "A18"
        case .iPhone16Pro, .iPhone16ProMax:
            return "A18 Pro"
        case .iPhone17Pro, .iPhone17ProMax:
            return "A19 Pro"
        case .unknown:
            return "Apple Silicon"
        }
    }
    
    // MARK: - Component Positions (normalized 0-1)
    
    /// CPU region position and size
    /// Based on teardown die shots - CPU cores are typically on the left/top of the die
    var cpuRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            // iPhone 15 Pro: SoC positioned slightly higher, offset left
            return CGRect(x: 0.08, y: 0.055, width: 0.24, height: 0.085)
            
        case .iPhone16, .iPhone16Plus:
            // iPhone 16: Reengineered layout, slightly more centered
            return CGRect(x: 0.10, y: 0.06, width: 0.22, height: 0.08)
            
        case .iPhone16Pro, .iPhone16ProMax:
            // iPhone 16 Pro: CENTRALIZED chip placement - more centered overall
            return CGRect(x: 0.12, y: 0.055, width: 0.22, height: 0.09)
            
        case .iPhone17Pro, .iPhone17ProMax:
            // iPhone 17 Pro: Expected similar to 16 Pro
            return CGRect(x: 0.12, y: 0.055, width: 0.22, height: 0.09)
            
        case .unknown:
            return CGRect(x: 0.10, y: 0.06, width: 0.22, height: 0.09)
        }
    }
    
    /// GPU region position and size
    /// GPU cores are typically in the center of the SoC die
    var gpuRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            return CGRect(x: 0.35, y: 0.055, width: 0.24, height: 0.085)
            
        case .iPhone16, .iPhone16Plus:
            return CGRect(x: 0.35, y: 0.06, width: 0.22, height: 0.08)
            
        case .iPhone16Pro, .iPhone16ProMax:
            // Centralized: GPU more towards center of device
            return CGRect(x: 0.37, y: 0.055, width: 0.22, height: 0.09)
            
        case .iPhone17Pro, .iPhone17ProMax:
            return CGRect(x: 0.37, y: 0.055, width: 0.22, height: 0.09)
            
        case .unknown:
            return CGRect(x: 0.35, y: 0.06, width: 0.22, height: 0.09)
        }
    }
    
    /// Neural Engine (ANE) region position and size
    /// ANE is typically on the right side of the die
    var aneRect: CGRect {
        switch self {
        case .iPhone15Pro, .iPhone15ProMax:
            return CGRect(x: 0.62, y: 0.055, width: 0.28, height: 0.085)
            
        case .iPhone16, .iPhone16Plus:
            return CGRect(x: 0.60, y: 0.06, width: 0.28, height: 0.08)
            
        case .iPhone16Pro, .iPhone16ProMax:
            // Centralized: ANE still on right but tighter overall
            return CGRect(x: 0.62, y: 0.055, width: 0.26, height: 0.09)
            
        case .iPhone17Pro, .iPhone17ProMax:
            return CGRect(x: 0.62, y: 0.055, width: 0.26, height: 0.09)
            
        case .unknown:
            return CGRect(x: 0.60, y: 0.06, width: 0.28, height: 0.09)
        }
    }
}

// MARK: - Full-Screen X-Ray Overlay

/// Transparent full-screen overlay that shows glowing borders at the actual
/// physical locations where hardware components sit behind the screen
struct HardwareXRayOverlay: View {
    @ObservedObject private var telemetry = HardwareTelemetryState.shared
    
    /// The detected device layout
    private let layout = DeviceComponentLayout.current
    
    /// Show device/chip info label
    var showDeviceInfo: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ZStack {
                // CPU Border
                if telemetry.cpuIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: rectToScreen(layout.cpuRect, width: screenWidth, height: screenHeight),
                        color: HardwareComponent.cpu.color,
                        intensity: telemetry.cpuIntensity,
                        label: "CPU"
                    )
                }

                // GPU Border
                if telemetry.gpuIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: rectToScreen(layout.gpuRect, width: screenWidth, height: screenHeight),
                        color: HardwareComponent.gpu.color,
                        intensity: telemetry.gpuIntensity,
                        label: "GPU"
                    )
                }

                // Neural Engine Border
                if telemetry.aneIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: rectToScreen(layout.aneRect, width: screenWidth, height: screenHeight),
                        color: HardwareComponent.neuralEngine.color,
                        intensity: telemetry.aneIntensity,
                        label: "Neural Engine"
                    )
                }

                // Activity label
                if !telemetry.currentActivityLabel.isEmpty {
                    Text(telemetry.currentActivityLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                        )
                        .position(x: screenWidth / 2, y: screenHeight * 0.20)
                }
                
                // Device info label (optional, for debugging)
                if showDeviceInfo {
                    VStack(spacing: 2) {
                        Text(layout.displayName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                        Text(layout.chipName)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                    }
                    .foregroundColor(.gray.opacity(0.6))
                    .position(x: screenWidth / 2, y: screenHeight * 0.025)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    /// Convert normalized rect (0-1) to screen coordinates
    private func rectToScreen(_ rect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * width,
            y: rect.minY * height,
            width: rect.width * width,
            height: rect.height * height
        )
    }
}

// MARK: - Glowing Component Border

/// A border that glows at a specific screen position
private struct GlowingComponentBorder: View {
    let frame: CGRect
    let color: Color
    let intensity: Double
    let label: String

    private var glowRadius: CGFloat {
        CGFloat(4 + 12 * intensity)
    }

    private var borderWidth: CGFloat {
        CGFloat(1.5 + 2.5 * intensity)
    }

    var body: some View {
        ZStack {
            // Outer glow (large, diffuse)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.4 * intensity), lineWidth: borderWidth + 4)
                .blur(radius: glowRadius)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Main border
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.6 + 0.4 * intensity), lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Inner fill (subtle)
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.08 * intensity))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Label
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.7 + 0.3 * intensity))
                .shadow(color: color.opacity(0.6), radius: 3)
                .position(x: frame.midX, y: frame.midY)
        }
        .animation(.easeOut(duration: 0.1), value: intensity)
    }
}

// MARK: - Preview

#if DEBUG
struct HardwareXRayOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Simulate chat screen background
            Color.black.opacity(0.95)

            // The overlay with device info shown
            HardwareXRayOverlay(showDeviceInfo: true)
        }
        .ignoresSafeArea()
        .previewDisplayName("X-Ray Overlay (\(DeviceComponentLayout.current.displayName))")
    }
}
#endif
