//
//  MotherboardHUDView.swift
//  OpenIntelligence
//
//  Full-screen X-Ray overlay showing where Apple Silicon components physically
//  sit behind the iPhone screen. Borders glow at the ACTUAL positions.
//
//  Physical Layout (iPhone 16 Pro Max, front-facing view):
//  ┌────────────────────────────────────────┐
//  │  [Dynamic Island]                      │  ← Face ID / TrueDepth
//  │                                        │
//  │    ┌─────────────────────────┐         │
//  │    │       A18 Pro SoC       │         │  ← Upper-center logic board
//  │    │ ┌─────┐┌─────┐┌──────┐  │         │
//  │    │ │ CPU ││ GPU ││  ANE │  │         │  ← All on ONE die
//  │    │ └─────┘└─────┘└──────┘  │         │
//  │    └─────────────────────────┘         │
//  │                                        │
//  │                                        │
//  │   ┌────────────────────────────────┐   │
//  │   │            Battery             │   │  ← L-shaped battery
//  │   └────────────────────────────────┘   │
//  │                                        │
//  └────────────────────────────────────────┘
//
//  Based on iPhone 16 Pro Max teardowns: The A18 Pro SoC is centralized
//  in the upper portion of the device. CPU, GPU, and ANE are physically
//  on the same die but we show them as separate regions for visualization.
//

import SwiftUI

// MARK: - Full-Screen X-Ray Overlay

/// Transparent full-screen overlay that shows glowing borders at the actual
/// physical locations where hardware components sit behind the screen
struct HardwareXRayOverlay: View {
    @ObservedObject private var telemetry = HardwareTelemetryState.shared

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ZStack {
                // CPU Border - Upper left of SoC region
                // Physical location: ~10-25% from left, ~6-15% from top
                if telemetry.cpuIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: CGRect(
                            x: screenWidth * 0.10,
                            y: screenHeight * 0.06,
                            width: screenWidth * 0.22,
                            height: screenHeight * 0.09
                        ),
                        color: HardwareComponent.cpu.color,
                        intensity: telemetry.cpuIntensity,
                        label: "CPU"
                    )
                }

                // GPU Border - Center of SoC region
                // Physical location: ~35-57% from left, ~6-15% from top
                if telemetry.gpuIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: CGRect(
                            x: screenWidth * 0.35,
                            y: screenHeight * 0.06,
                            width: screenWidth * 0.22,
                            height: screenHeight * 0.09
                        ),
                        color: HardwareComponent.gpu.color,
                        intensity: telemetry.gpuIntensity,
                        label: "GPU"
                    )
                }

                // Neural Engine Border - Right side of SoC region
                // Physical location: ~60-82% from left, ~6-15% from top
                if telemetry.aneIntensity > 0.01 {
                    GlowingComponentBorder(
                        frame: CGRect(
                            x: screenWidth * 0.60,
                            y: screenHeight * 0.06,
                            width: screenWidth * 0.28,
                            height: screenHeight * 0.09
                        ),
                        color: HardwareComponent.neuralEngine.color,
                        intensity: telemetry.aneIntensity,
                        label: "Neural Engine"
                    )
                }

                // Activity label at bottom
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
            }
        }
        .ignoresSafeArea()
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

            // The overlay
            HardwareXRayOverlay()
        }
        .ignoresSafeArea()
        .previewDisplayName("X-Ray Overlay")
    }
}
#endif
