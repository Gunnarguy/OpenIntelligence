//
//  MotherboardHUDView.swift
//  OpenIntelligence
//
//  A visual "Heads-Up Display" that shows real-time Apple Silicon SoC activity.
//  Overlays a stylized logic board image with glowing regions for:
//  - Neural Engine (ANE): Purple glow - Embeddings, LLM inference
//  - GPU: Cyan glow - Vector similarity, MMR computations
//  - CPU: Orange glow - RAG orchestration, text processing
//
//  Design Philosophy:
//  This makes AI "visible" - users can literally see their device thinking.
//  The visualization provides intuitive feedback during processing without
//  being intrusive or blocking interaction.
//

import SwiftUI

// MARK: - Main HUD View

/// Miniature motherboard visualization showing real-time SoC activity
struct MotherboardHUDView: View {
    @ObservedObject private var telemetry = HardwareTelemetryState.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Size of the HUD (compact by default for non-intrusive overlay)
    var size: CGSize = CGSize(width: 140, height: 90)

    /// Whether to show the activity label
    var showActivityLabel: Bool = true

    /// Whether to show component legends
    var showLegend: Bool = false

    /// Opacity when idle (set to 0 to hide completely when inactive)
    var idleOpacity: Double = 0.4

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // LAYER 1: Darkened Logic Board Base
                LogicBoardBaseView(size: size)

                // LAYER 2: SoC Chip Boundary
                SoCChipOutline(size: size)

                // LAYER 3: Component Glow Overlays
                ComponentGlowsView(
                    size: size,
                    aneIntensity: telemetry.aneIntensity,
                    gpuIntensity: telemetry.gpuIntensity,
                    cpuIntensity: telemetry.cpuIntensity
                )

                // LAYER 4: Activity Label
                if showActivityLabel && !telemetry.currentActivityLabel.isEmpty {
                    ActivityLabelView(label: telemetry.currentActivityLabel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                }

                // LAYER 5: Component Legend (optional)
                if showLegend {
                    ComponentLegendView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(4)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .opacity(telemetry.isActive ? 1.0 : idleOpacity)
        .animation(.easeInOut(duration: 0.3), value: telemetry.isActive)
    }
}

// MARK: - Logic Board Base Layer

/// The base image of the logic board (darkened for contrast)
private struct LogicBoardBaseView: View {
    let size: CGSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Try to load the actual logic board image
            // Falls back to a stylized placeholder if not available
            if let _ = UIImage(named: "LogicBoard_A18Pro") {
                Image("LogicBoard_A18Pro")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .colorMultiply(Color.black.opacity(0.75))
                    .saturation(0.3)
                    .blur(radius: 0.5)
            } else {
                // Stylized fallback with circuit board pattern
                StylizedCircuitBoardView(size: size)
            }

            // Dark overlay for better glow visibility
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.5),
                            Color.black.opacity(0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

/// Stylized circuit board pattern as a fallback
private struct StylizedCircuitBoardView: View {
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let gridSize: CGFloat = 8
            let lineWidth: CGFloat = 0.5

            // Draw subtle grid pattern
            for x in stride(from: 0, to: canvasSize.width, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: lineWidth)
            }

            for y in stride(from: 0, to: canvasSize.height, by: gridSize) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: lineWidth)
            }

            // Draw some "traces" - diagonal and curved lines
            let tracePaths = generateTraces(in: canvasSize)
            for tracePath in tracePaths {
                context.stroke(tracePath, with: .color(.green.opacity(0.2)), lineWidth: 1)
            }

            // Draw some "component pads"
            let padPositions = generatePadPositions(in: canvasSize)
            for pos in padPositions {
                let padRect = CGRect(x: pos.x - 2, y: pos.y - 2, width: 4, height: 4)
                context.fill(Path(roundedRect: padRect, cornerRadius: 1), with: .color(.gray.opacity(0.3)))
            }
        }
        .background(Color(white: 0.08))
    }

    private func generateTraces(in size: CGSize) -> [Path] {
        var paths: [Path] = []

        // Horizontal traces
        for i in 0..<5 {
            var path = Path()
            let y = CGFloat(i + 1) * size.height / 6
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width * 0.3, y: y))
            path.addLine(to: CGPoint(x: size.width * 0.4, y: y + 5))
            path.addLine(to: CGPoint(x: size.width, y: y + 5))
            paths.append(path)
        }

        // Diagonal traces around SoC area
        var diagPath = Path()
        diagPath.move(to: CGPoint(x: size.width * 0.3, y: size.height * 0.2))
        diagPath.addLine(to: CGPoint(x: size.width * 0.7, y: size.height * 0.2))
        diagPath.addLine(to: CGPoint(x: size.width * 0.8, y: size.height * 0.3))
        paths.append(diagPath)

        return paths
    }

    private func generatePadPositions(in size: CGSize) -> [CGPoint] {
        var positions: [CGPoint] = []

        // Edge pads
        for i in 0..<8 {
            positions.append(CGPoint(x: 4, y: CGFloat(i + 1) * size.height / 9))
            positions.append(CGPoint(x: size.width - 4, y: CGFloat(i + 1) * size.height / 9))
        }

        // Random internal components
        let seed: [CGPoint] = [
            CGPoint(x: 0.15, y: 0.3),
            CGPoint(x: 0.85, y: 0.4),
            CGPoint(x: 0.2, y: 0.7),
            CGPoint(x: 0.8, y: 0.75),
        ]
        for pt in seed {
            positions.append(CGPoint(x: pt.x * size.width, y: pt.y * size.height))
        }

        return positions
    }
}

// MARK: - SoC Chip Outline

/// Visual outline of the A-series SoC chip
private struct SoCChipOutline: View {
    let size: CGSize

    // SoC position and size relative to the board
    private let socCenterX: CGFloat = 0.5
    private let socCenterY: CGFloat = 0.45
    private let socWidth: CGFloat = 0.45
    private let socHeight: CGFloat = 0.55

    var body: some View {
        let socRect = CGRect(
            x: size.width * (socCenterX - socWidth / 2),
            y: size.height * (socCenterY - socHeight / 2),
            width: size.width * socWidth,
            height: size.height * socHeight
        )

        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.4),
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .frame(width: socRect.width, height: socRect.height)
            .position(x: socRect.midX, y: socRect.midY)
    }
}

// MARK: - Component Glows

/// Animated glow overlays for each hardware component
private struct ComponentGlowsView: View {
    let size: CGSize
    let aneIntensity: Double
    let gpuIntensity: Double
    let cpuIntensity: Double

    var body: some View {
        ZStack {
            // Neural Engine (ANE) Glow - Purple
            if aneIntensity > 0.01 {
                ComponentGlow(
                    component: .neuralEngine,
                    intensity: aneIntensity,
                    size: size
                )
            }

            // GPU Glow - Cyan
            if gpuIntensity > 0.01 {
                ComponentGlow(
                    component: .gpu,
                    intensity: gpuIntensity,
                    size: size
                )
            }

            // CPU Glow - Orange
            if cpuIntensity > 0.01 {
                ComponentGlow(
                    component: .cpu,
                    intensity: cpuIntensity,
                    size: size
                )
            }
        }
    }
}

/// Individual component glow effect
private struct ComponentGlow: View {
    let component: HardwareComponent
    let intensity: Double
    let size: CGSize

    var body: some View {
        let position = CGPoint(
            x: component.relativePosition.x * size.width,
            y: component.relativePosition.y * size.height
        )

        let baseRadius: CGFloat = 25
        let glowRadius = baseRadius * (0.7 + 0.3 * intensity)

        ZStack {
            // Outer glow (larger, more diffuse)
            RadialGradient(
                gradient: Gradient(colors: [
                    component.color.opacity(0.6 * intensity),
                    component.color.opacity(0.2 * intensity),
                    Color.clear
                ]),
                center: .center,
                startRadius: 0,
                endRadius: glowRadius * 1.5
            )
            .blendMode(.plusLighter)

            // Inner glow (brighter core)
            RadialGradient(
                gradient: Gradient(colors: [
                    component.color.opacity(0.9 * intensity),
                    component.color.opacity(0.4 * intensity),
                    Color.clear
                ]),
                center: .center,
                startRadius: 0,
                endRadius: glowRadius * 0.8
            )
            .blendMode(.screen)

            // Hot spot (very bright center)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.8 * intensity),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .blendMode(.plusLighter)
        }
        .frame(width: glowRadius * 3, height: glowRadius * 3)
        .position(position)
        .animation(.easeOut(duration: 0.1), value: intensity)
    }
}

// MARK: - Activity Label

/// Shows current activity name at the bottom of the HUD
private struct ActivityLabelView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeInOut(duration: 0.15), value: label)
    }
}

// MARK: - Legend View

/// Optional legend showing component colors
private struct ComponentLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LegendItem(color: HardwareComponent.neuralEngine.color, label: "ANE")
            LegendItem(color: HardwareComponent.gpu.color, label: "GPU")
            LegendItem(color: HardwareComponent.cpu.color, label: "CPU")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.5))
        )
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Expanded HUD Variant

/// Larger version of the HUD for detailed viewing
struct MotherboardHUDExpandedView: View {
    @ObservedObject private var telemetry = HardwareTelemetryState.shared

    var body: some View {
        VStack(spacing: 12) {
            // Main HUD at larger size
            MotherboardHUDView(
                size: CGSize(width: 280, height: 180),
                showActivityLabel: true,
                showLegend: true,
                idleOpacity: 0.6
            )

            // Activity history sparklines
            HStack(spacing: 16) {
                SparklineView(
                    data: telemetry.aneHistory,
                    color: HardwareComponent.neuralEngine.color,
                    label: "ANE"
                )
                SparklineView(
                    data: telemetry.gpuHistory,
                    color: HardwareComponent.gpu.color,
                    label: "GPU"
                )
                SparklineView(
                    data: telemetry.cpuHistory,
                    color: HardwareComponent.cpu.color,
                    label: "CPU"
                )
            }
            .frame(height: 32)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))
        )
    }
}

/// Sparkline visualization for activity history
private struct SparklineView: View {
    let data: [Double]
    let color: Color
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(color.opacity(0.8))

            GeometryReader { geometry in
                if data.count > 1 {
                    Path { path in
                        let stepX = geometry.size.width / CGFloat(data.count - 1)
                        let maxY = geometry.size.height

                        for (index, value) in data.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = maxY - (CGFloat(value) * maxY)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, lineWidth: 1.5)
                }
            }
        }
        .frame(width: 60)
    }
}

// MARK: - Floating HUD Container

/// A draggable floating container for the HUD
struct FloatingMotherboardHUD: View {
    @State private var position: CGPoint = CGPoint(x: 100, y: 100)
    @State private var isDragging: Bool = false
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        MotherboardHUDView(idleOpacity: 0.3)
            .offset(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        position.x += value.translation.width
                        position.y += value.translation.height
                    }
            )
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
    }
}

// MARK: - Preview

#if DEBUG
struct MotherboardHUDView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Standard HUD
            MotherboardHUDView()
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("Standard")

            // With legend
            MotherboardHUDView(showLegend: true)
                .padding()
                .background(Color.gray.opacity(0.3))
                .previewDisplayName("With Legend")

            // Expanded view
            MotherboardHUDExpandedView()
                .padding()
                .previewDisplayName("Expanded")

            // In-context (simulated chat screen position)
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.9)
                MotherboardHUDView()
                    .padding(12)
            }
            .frame(width: 390, height: 300)
            .previewDisplayName("In Context")
        }
    }
}
#endif
