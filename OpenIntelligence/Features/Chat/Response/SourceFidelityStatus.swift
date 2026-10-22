//
//  SourceFidelityStatus.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import SwiftUI

struct SourceFidelityStatus: View {
    enum FidelityLevel {
        case sourceLocked
        case partiallySupported
        case insufficientEvidence
        
        var title: String {
            switch self {
            case .sourceLocked: return "Source-Locked"
            case .partiallySupported: return "Partially Supported"
            case .insufficientEvidence: return "Not Enough Evidence"
            }
        }
        
        var description: String {
            switch self {
            case .sourceLocked: return "All claims are fully verified and grounded in cited sources."
            case .partiallySupported: return "Most claims are grounded, but some details could not be fully verified."
            case .insufficientEvidence: return "Retrieved evidence was insufficient to safely verify the answer."
            }
        }
        
        var icon: String {
            switch self {
            case .sourceLocked: return "lock.shield.fill"
            case .partiallySupported: return "shield.lefthalf.filled"
            case .insufficientEvidence: return "exclamationmark.shield.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .sourceLocked: return .green
            case .partiallySupported: return .orange
            case .insufficientEvidence: return .red
            }
        }
    }
    
    let level: FidelityLevel
    let score: Float?
    
    init(level: FidelityLevel, score: Float? = nil) {
        self.level = level
        self.score = score
    }
    
    init(fidelityScore: Float, shouldAbstain: Bool) {
        if shouldAbstain {
            self.level = .insufficientEvidence
            self.score = 0
        } else if fidelityScore >= 0.88 {
            self.level = .sourceLocked
            self.score = fidelityScore
        } else {
            self.level = .partiallySupported
            self.score = fidelityScore
        }
    }
    
    var body: some View {
        HStack(spacing: DSSpacing.md) {
            ZStack {
                Circle()
                    .fill(level.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: level.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(level.color)
            }
            
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(level.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColors.primaryText)
                    
                    if let score = score, score > 0 {
                        Text(String(format: "(%.0f%% fidelity)", score * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                
                Text(level.description)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .stroke(level.color.opacity(0.25), lineWidth: 1)
        )
    }
}
