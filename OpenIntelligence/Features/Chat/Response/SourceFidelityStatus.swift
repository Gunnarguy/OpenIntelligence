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
        /// No check ran on the answer: it was written without passages, or its checks were skipped.
        case notChecked
        
        var title: String {
            switch self {
            case .sourceLocked: return "Source-Locked"
            case .partiallySupported: return "Partially Supported"
            case .insufficientEvidence: return "Not Enough Evidence"
            case .notChecked: return "Not Checked"
            }
        }
        
        var description: String {
            switch self {
            case .sourceLocked: return "All claims are fully verified and grounded in cited sources."
            case .partiallySupported: return "Most claims are grounded, but some details could not be fully verified."
            case .insufficientEvidence: return "Retrieved evidence was insufficient to safely verify the answer."
            case .notChecked: return "No check ran against your documents for this answer."
            }
        }
        
        var icon: String {
            switch self {
            case .sourceLocked: return "lock.shield.fill"
            case .partiallySupported: return "shield.lefthalf.filled"
            case .insufficientEvidence: return "exclamationmark.shield.fill"
            case .notChecked: return "shield"
            }
        }
        
        var color: Color {
            switch self {
            case .sourceLocked: return .green
            case .partiallySupported: return .orange
            case .insufficientEvidence: return .red
            case .notChecked: return .secondary
            }
        }

        /// The card's level for an answer, read from the same outcome as the chat badge (5.8). Until then the card read
        /// the gating string on its own and called everything Source-Locked unless the string held "failed",
        /// "missing_citations", "abstain", "low_confidence" or "fallback": an answer whose gates failed
        /// (`unverified:<gates>`) and an answer written with no passages (no string) both read "All claims are fully
        /// verified".
        static func from(_ outcome: VerificationOutcome) -> FidelityLevel {
            switch outcome {
            case .supported: return .sourceLocked
            case .partial, .lowConfidence: return .partiallySupported
            case .notSupported, .noSources: return .insufficientEvidence
            case .notChecked: return .notChecked
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
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundStyle(level.color)
            }
            
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(level.title)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                    
                    if let score = score, score > 0 {
                        Text(String(format: "(%.0f%% fidelity)", score * 100))
                            .scaledFont(size: 11)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
                
                Text(level.description)
                    .scaledFont(size: 11)
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
