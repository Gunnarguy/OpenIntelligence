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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(level.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: level.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(level.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(level.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                    
                    if let score = score, score > 0 {
                        Text(String(format: "(%.0f%% fidelity)", score * 100))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(level.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DSColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(level.color.opacity(0.25), lineWidth: 1)
        )
    }
}
