//
//  StatusPillV2.swift
//  OpenIntelligence
//
//  Minimal status indicator that replaces the large stage progress bar
//  Shows current stage as a single compact pill with animated states
//

import SwiftUI

struct StatusPillV2: View {
    let stage: ChatProcessingStage
    let execution: ChatExecutionLocation
    let ttft: TimeInterval?
    let embeddingElapsed: TimeInterval?
    let searchingElapsed: TimeInterval?
    let generatingElapsed: TimeInterval?

    @State private var pulsePhase: CGFloat = 0

    private var isActive: Bool {
        stage != .idle && stage != .complete
    }

    private var statusInfo: (icon: String, label: String, color: Color) {
        switch stage {
        case .idle:
            return ("checkmark.circle", "Ready", .secondary)
        case .embedding:
            return ("brain.head.profile", "Embedding", .purple)
        case .searching:
            return ("magnifyingglass", "Searching", .blue)
        case .generating:
            return ("sparkles", "Generating", DSColors.accent)
        case .complete:
            return ("checkmark.circle.fill", "Done", .green)
        }
    }

    private var elapsedTime: TimeInterval? {
        switch stage {
        case .idle, .complete: return nil
        case .embedding: return embeddingElapsed
        case .searching: return searchingElapsed
        case .generating: return generatingElapsed
        }
    }

    var body: some View {
        if isActive {
            HStack(spacing: 0) {
                // Main status pill
                HStack(spacing: 6) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(statusInfo.color.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .scaleEffect(pulsePhase)
                            .opacity(Double(1.0 - pulsePhase * 0.5))

                        Image(systemName: statusInfo.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(statusInfo.color)
                    }

                    Text(statusInfo.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusInfo.color)

                    if let elapsed = elapsedTime {
                        Text(formatElapsed(elapsed))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }

                    // Stage dots
                    HStack(spacing: 3) {
                        StageDot(active: stage == .embedding || stage == .searching || stage == .generating, color: .purple)
                        StageDot(active: stage == .searching || stage == .generating, color: .blue)
                        StageDot(active: stage == .generating, color: DSColors.accent)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(statusInfo.color.opacity(0.3))
                        )
                )

                Spacer()

                // Execution location (compact)
                if stage == .generating {
                    ExecutionChip(execution: execution, ttft: ttft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsePhase = 1.0
                }
            }
        }
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        } else {
            return String(format: "%.1fs", t)
        }
    }
}

private struct StageDot: View {
    let active: Bool
    let color: Color

    var body: some View {
        Circle()
            .fill(active ? color : Color.secondary.opacity(0.2))
            .frame(width: 5, height: 5)
    }
}

private struct ExecutionChip: View {
    let execution: ChatExecutionLocation
    let ttft: TimeInterval?

    private var info: (icon: String, label: String, color: Color) {
        switch execution {
        case .onDevice:
            return ("iphone", "Device", .blue)
        case .privateCloudCompute:
            return ("cloud", "PCC", .green)
        case .mlxLocal:
            return ("desktopcomputer", "MLX", .indigo)
        case .unknown:
            if let ttft = ttft {
                return ttft < 0.5 ? ("iphone", "Device", .blue) : ("cloud", "PCC", .green)
            }
            return ("sparkles", "AI", .purple)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(info.label)
                .font(.system(size: 11, weight: .medium))
            if let ttft = ttft {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                Text(String(format: "%.2fs", ttft))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .foregroundStyle(info.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(info.color.opacity(0.12))
        )
    }
}

#Preview("Active") {
    VStack(spacing: 20) {
        StatusPillV2(stage: .embedding, execution: .unknown, ttft: nil, embeddingElapsed: 0.032, searchingElapsed: nil, generatingElapsed: nil)
        StatusPillV2(stage: .searching, execution: .unknown, ttft: nil, embeddingElapsed: 0.032, searchingElapsed: 0.145, generatingElapsed: nil)
        StatusPillV2(stage: .generating, execution: .privateCloudCompute, ttft: 1.24, embeddingElapsed: 0.032, searchingElapsed: 0.145, generatingElapsed: 2.5)
    }
    .padding()
    .background(DSColors.background)
}
