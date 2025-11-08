//
//  LiveCountersStrip.swift
//  OpenIntelligence
//
//  Compact live counters displayed during generation: TTFT, tokens, tok/s, retrieved count.
//

import SwiftUI

struct LiveCountersStrip: View {
    let ttft: TimeInterval?
    let tokensApprox: Int
    let tokensPerSecondApprox: Double
    let retrievedCount: Int
    
    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            if let ttft {
                CounterChip(icon: "timer", label: "TTFT", value: ttftString(ttft))
            }
            CounterChip(icon: "number", label: "Tokens", value: "\(tokensApprox)")
            CounterChip(icon: "speedometer", label: "tok/s", value: String(format: "%.1f", tokensPerSecondApprox))
            CounterChip(icon: "doc.text.magnifyingglass", label: "chunks", value: "\(retrievedCount)")
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 6)
        .background(DSColors.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(DSColors.surface.opacity(0.6))
                .frame(height: 0.5),
            alignment: .top
        )
    }
    
    private func ttftString(_ t: TimeInterval) -> String {
        if t < 1.0 {
            return String(format: "%.0f ms", t * 1000)
        } else {
            return String(format: "%.2f s", t)
        }
    }
}

private struct CounterChip: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(DSColors.accent)
            Text(label)
                .font(DSTypography.meta)
                .foregroundColor(DSColors.secondaryText)
            Text(value)
                .font(DSTypography.meta)
                .fontWeight(.semibold)
                .foregroundColor(DSColors.primaryText)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 6)
        .background(DSColors.surface)
        .cornerRadius(DSCorners.chip)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
    }
}
