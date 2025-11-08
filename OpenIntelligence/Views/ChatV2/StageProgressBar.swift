//
//  StageProgressBar.swift
//  OpenIntelligence
//
//  Visual indicator for embedding → searching → generating stages with execution badge
//  Created by Cline on 10/28/25.
//

import SwiftUI

struct StageProgressBar: View {
    let stage: ChatProcessingStage
    let execution: ChatExecutionLocation
    let ttft: TimeInterval?
    // Per-stage elapsed timers
    let embeddingElapsed: TimeInterval?
    let searchingElapsed: TimeInterval?
    let generatingElapsed: TimeInterval?
    
    // Subtle shimmer phase (0 → 1, loops)
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.md) {
                StagePill(
                    icon: "brain.head.profile",
                    label: "Embedding",
                    active: stage == .embedding || stage == .searching || stage == .generating,
                    elapsed: embeddingElapsed,
                    shimmer: stage == .embedding || stage == .searching || stage == .generating,
                    shimmerPhase: shimmerPhase
                )
                StageConnector(
                    active: stage == .searching || stage == .generating,
                    shimmer: stage == .searching || stage == .generating,
                    shimmerPhase: shimmerPhase
                )
                StagePill(
                    icon: "magnifyingglass",
                    label: "Searching",
                    active: stage == .searching || stage == .generating,
                    elapsed: searchingElapsed,
                    shimmer: stage == .searching || stage == .generating,
                    shimmerPhase: shimmerPhase
                )
                StageConnector(
                    active: stage == .generating,
                    shimmer: stage == .generating,
                    shimmerPhase: shimmerPhase
                )
                StagePill(
                    icon: "sparkles",
                    label: "Generating",
                    active: stage == .generating,
                    elapsed: generatingElapsed,
                    shimmer: stage == .generating,
                    shimmerPhase: shimmerPhase
                )
            }
            
            HStack(spacing: DSSpacing.sm) {
                ExecutionBadge(execution: execution, ttft: ttft)
                Spacer()
                if stage == .generating {
                    TypingIndicator()
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(DSColors.surface.opacity(0.6))
                .frame(height: 0.5),
            alignment: .top
        )
        .onAppear {
            shimmerPhase = 0
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }
}

// MARK: - Stage Elements

private struct StagePill: View {
    let icon: String
    let label: String
    let active: Bool
    let elapsed: TimeInterval?
    let shimmer: Bool
    let shimmerPhase: CGFloat
    
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(active ? DSColors.accent : DSColors.secondaryText)
            Text(label)
                .font(DSTypography.meta)
                .foregroundColor(active ? DSColors.accent : DSColors.secondaryText)
            if let elapsed {
                Text(elapsedString(elapsed))
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 6)
        .background(active ? DSColors.chipBackground(for: DSColors.accent) : DSColors.surface)
        .cornerRadius(DSCorners.chip)
        .overlay {
            if shimmer && active {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 12, height: geo.size.height)
                        .offset(x: (geo.size.width + 24) * shimmerPhase - 24)
                        .blur(radius: 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip))
                .allowsHitTesting(false)
            }
        }
        .animation(DSAnimations.fastEase, value: active)
    }
    
    private func elapsedString(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0fms", t * 1000)
        } else {
            return String(format: "%.1fs", t)
        }
    }
}

private struct StageConnector: View {
    let active: Bool
    let shimmer: Bool
    let shimmerPhase: CGFloat
    var body: some View {
        Capsule()
            .fill(active ? DSColors.accent : DSColors.secondaryText.opacity(0.3))
            .frame(width: 24, height: 3)
            .overlay {
                if shimmer && active {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 6, height: geo.size.height)
                            .offset(x: (geo.size.width + 12) * shimmerPhase - 12)
                            .blur(radius: 6)
                    }
                    .clipShape(Capsule())
                }
            }
            .animation(DSAnimations.fastEase, value: active)
    }
}

// MARK: - Execution Badge

struct ExecutionBadge: View {
    let execution: ChatExecutionLocation
    let ttft: TimeInterval?
    
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: execution.icon)
                .font(.caption2)
                .foregroundColor(execution.color)
            Text(execution.displayName)
                .font(DSTypography.meta)
                .foregroundColor(execution.color)
            if let ttft {
                Text("•")
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
                Text(String(format: "%.2fs", ttft))
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 6)
        .background(execution.color.opacity(0.1))
        .cornerRadius(DSCorners.chip)
        .animation(DSAnimations.fastEase, value: execution.displayName)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        StageProgressBar(stage: .embedding, execution: .unknown, ttft: nil, embeddingElapsed: 0.42, searchingElapsed: nil, generatingElapsed: nil)
        StageProgressBar(stage: .searching, execution: .onDevice, ttft: 0.42, embeddingElapsed: 0.42, searchingElapsed: 0.17, generatingElapsed: nil)
        StageProgressBar(stage: .generating, execution: .privateCloudCompute, ttft: 1.33, embeddingElapsed: 0.42, searchingElapsed: 0.33, generatingElapsed: 1.10)
    }
    .background(DSColors.background)
}
