//
//  ToolCallBadge.swift
//  OpenIntelligence
//
//  Displays the number of tool/function calls made during a response.
//  Shows when the LLM used agentic capabilities (e.g., Apple Foundation Models tools).
//  Polished with design system tokens and subtle animations.
//

import SwiftUI

/// Inline micro-badge variant for tight spaces (e.g., inside message bubble footer)
struct MicroToolCallBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "wrench.fill")
                    .scaledFont(size: 7, weight: .bold)
                Text("\(count)")
                    .scaledFont(size: 8, weight: .bold, design: .rounded)
                    .monospacedDigit()
            }
            .foregroundStyle(.purple.opacity(0.8))
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.1))
            )
        }
    }
}

// MARK: - Preview

#Preview("Tool Call Badges") {
    VStack(spacing: DSSpacing.md) {
        Text("Micro Badge").font(DSTypography.meta)
        HStack(spacing: DSSpacing.sm) {
            MicroToolCallBadge(count: 0)
            MicroToolCallBadge(count: 1)
            MicroToolCallBadge(count: 5)
        }
    }
    .padding()
    .background(DSColors.background)
}
