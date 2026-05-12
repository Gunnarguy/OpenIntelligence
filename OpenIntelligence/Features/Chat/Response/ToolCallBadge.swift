//
//  ToolCallBadge.swift
//  OpenIntelligence
//
//  Displays the number of tool/function calls made during a response.
//  Shows when the LLM used agentic capabilities (e.g., Apple Foundation Models tools).
//  Polished with design system tokens and subtle animations.
//

import SwiftUI

/// Compact badge showing tool/function call count with animated appearance
struct ToolCallBadge: View {
    let count: Int
    
    /// Optional: animate in when count changes
    @State private var isVisible: Bool = false
    
    private var badgeColor: Color {
        count >= 5 ? .orange : .purple
    }
    
    var body: some View {
        if count > 0 {
            HStack(spacing: DSSpacing.xxs) {
                // Animated icon with subtle pulse for high counts
                Image(systemName: count >= 3 ? "gearshape.2.fill" : "wrench.and.screwdriver")
                    .font(.system(size: 9, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: count >= 5)
                
                Text("\(count) tool\(count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundColor(badgeColor)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DSColors.chipBackground(for: badgeColor))
            )
            .overlay(
                Capsule()
                    .strokeBorder(badgeColor.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(DSAnimations.snappySpring) {
                    isVisible = true
                }
            }
            .accessibilityLabel("\(count) tool call\(count == 1 ? "" : "s") made")
        }
    }
}

/// Inline micro-badge variant for tight spaces (e.g., inside message bubble footer)
struct MicroToolCallBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 7, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundColor(.purple.opacity(0.8))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
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
        Text("Standard Badge").font(DSTypography.meta)
        HStack(spacing: DSSpacing.sm) {
            ToolCallBadge(count: 0)
            ToolCallBadge(count: 1)
            ToolCallBadge(count: 3)
            ToolCallBadge(count: 7)
        }
        
        Divider()
        
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
