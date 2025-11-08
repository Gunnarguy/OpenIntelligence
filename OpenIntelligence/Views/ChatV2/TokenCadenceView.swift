//
//  TokenCadenceView.swift
//  OpenIntelligence
//
//  Subtle animated "cadence ticks" that reflect streaming rhythm.
//  Driven by tokensPerSecond to adjust wave speed.
//
//  Created by Cline on 10/29/25.
//

import SwiftUI

struct TokenCadenceView: View {
    let tokensApprox: Int
    let tokensPerSecond: Double
    
    @State private var phase: Double = 0
    
    // Faster tok/s = shorter duration; clamp to reasonable bounds
    private var duration: Double {
        let s = max(tokensPerSecond, 0.1)
        return max(0.35, min(1.2, 1.0 / s))
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { i in
                let base: CGFloat = 8
                let amp: CGFloat = 6
                let value = base + amp * CGFloat( (sin(phase + Double(i) * 0.6) + 1.0) * 0.5 )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DSColors.accent.opacity(0.6))
                    .frame(width: 3, height: value)
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 6)
        .background(DSColors.surface)
        .cornerRadius(DSCorners.chip)
        .onAppear {
            phase = 0
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onChange(of: tokensPerSecond) { _, _ in
            // Restart animation with updated duration when speed changes noticeably
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                phase += .pi // nudge phase to avoid visible reset
            }
        }
        .accessibilityLabel("Token cadence")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        TokenCadenceView(tokensApprox: 120, tokensPerSecond: 1.0)
        TokenCadenceView(tokensApprox: 120, tokensPerSecond: 4.0)
    }
    .padding()
    .background(DSColors.background)
}
