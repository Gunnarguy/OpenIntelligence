//
//  GroundedAnswerView.swift
//  OpenIntelligence
//

import SwiftUI

struct GroundedAnswerView: View {
    let answer: StructuredAnswer
    let retrievedChunks: [RetrievedChunk]
    let modeName: String?
    
    @State private var expandedClaimIndex: Int? = nil
    @State private var selectedCitationChunk: RetrievedChunk? = nil
    
    private var modeColor: Color {
        let mode = modeName?.lowercased() ?? ""
        if mode.contains("max") { return .orange }
        if mode.contains("deep") { return .purple }
        return DSColors.accent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main answer text with interactive citations
            let linkedAnswer = answer.answer.replacingOccurrences(
                of: "\\[(\\d+)\\]",
                with: "[[$$1]](citation://$$1)",
                options: .regularExpression
            )
            
            MarkdownText(
                linkedAnswer,
                font: .system(size: 14, weight: .regular),
                foregroundColor: DSColors.primaryText
            )
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "citation", let host = url.host, let idx = Int(host) {
                    let arrayIdx = idx - 1
                    if arrayIdx >= 0 && arrayIdx < retrievedChunks.count {
                        selectedCitationChunk = retrievedChunks[arrayIdx]
                        return .handled
                    }
                }
                return .systemAction
            })
            .sheet(item: Binding(
                get: { selectedCitationChunk.map { IdentifiableChunk(chunk: $0) } },
                set: { selectedCitationChunk = $0?.chunk }
            )) { identifiableChunk in
                NavigationView {
                    DocumentDetailsView(
                        document: Document(
                            id: identifiableChunk.chunk.chunk.documentId,
                            filename: identifiableChunk.chunk.sourceDocument,
                            fileURL: URL(fileURLWithPath: identifiableChunk.chunk.sourceDocument),
                            contentType: .unknown
                        ),
                        embeddingProviderId: nil,
                        highlightedChunk: identifiableChunk.chunk
                    )
                }
            }

            
            if !answer.claims.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("FACT CHECK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 9))
                            Text("\(answer.claims.count) Verified")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(modeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(modeColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 2)
                    
                    ForEach(Array(answer.claims.enumerated()), id: \.offset) { index, claim in
                        ClaimCard(
                            claim: claim,
                            evidence: answer.evidence,
                            isExpanded: expandedClaimIndex == index,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if expandedClaimIndex == index {
                                        expandedClaimIndex = nil
                                    } else {
                                        expandedClaimIndex = index
                                    }
                                }
                                DSHaptics.selection()
                            }
                        )
                    }
                }
                .padding(.top, 8)
            }
            
            if !answer.missing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("Information Gaps")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    
                    ForEach(answer.missing, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }
}

private struct ClaimCard: View {
    let claim: StructuredAnswer.Claim
    let evidence: [StructuredAnswer.Evidence]
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    // Verdict Icon
                    ZStack {
                        Circle()
                            .fill(verdictColor.opacity(0.15))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: verdictIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(verdictColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(claim.claim)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DSColors.primaryText)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        
                        if !isExpanded {
                            HStack(spacing: 3) {
                                Text(verdictTitle)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(verdictColor)
                                
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                                
                                Text("\(Int(claim.confidence * 100))% Conf.")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                
                                if claim.evidenceIds.count > 0 {
                                    Text("•")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                    
                                    Text("\(claim.evidenceIds.count) Sources")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        if let details = claim.verificationDetails {
                            Text(details)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(verdictColor.opacity(0.05))
                                .cornerRadius(6)
                                .padding(.leading, 28)
                        }
                        
                        // Supporting Evidence Quotes
                        let relevantEvidence = matchingEvidence
                        if !relevantEvidence.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SUPPORTING EVIDENCE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 28)
                                
                                ForEach(relevantEvidence, id: \.evidenceId) { ev in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\"\(ev.quote)\"")
                                            .font(.system(size: 10, weight: .medium, design: .serif))
                                            .foregroundStyle(DSColors.primaryText.opacity(0.9))
                                            .italic()
                                        
                                        HStack(spacing: 3) {
                                            Image(systemName: "doc.fill")
                                                .font(.system(size: 7))
                                            Text(ev.documentName ?? "Unknown")
                                            if let page = ev.page {
                                                Text("• P.\(page)")
                                            }
                                        }
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(DSColors.accent)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(DSColors.background.opacity(0.5))
                                    .cornerRadius(6)
                                    .padding(.leading, 28)
                                }
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Spacer().frame(width: 20)
                            
                            Text("CONFIDENCE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                            
                            ProgressView(value: claim.confidence)
                                .progressViewStyle(.linear)
                                .tint(verdictColor)
                                .frame(width: 50)
                            
                            Text("\(Int(claim.confidence * 100))%")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(verdictColor)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.surface)
                    .shadow(color: .black.opacity(isExpanded ? 0.08 : 0.02), radius: isExpanded ? 4 : 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(verdictColor.opacity(isExpanded ? 0.3 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var matchingEvidence: [StructuredAnswer.Evidence] {
        evidence.filter { claim.evidenceIds.contains($0.evidenceId) }
    }
    
    private var verdictColor: Color {
        switch claim.verificationVerdict {
        case .supported: return .green
        case .partial: return .orange
        case .unsupported: return .red
        case nil: return .blue
        }
    }
    
    private var verdictIcon: String {
        switch claim.verificationVerdict {
        case .supported: return "checkmark"
        case .partial: return "exclamationmark"
        case .unsupported: return "xmark"
        case nil: return "info"
        }
    }
    
    private var verdictTitle: String {
        switch claim.verificationVerdict {
        case .supported: return "SUPPORTED"
        case .partial: return "PARTIAL"
        case .unsupported: return "UNSUPPORTED"
        case nil: return "VERIFYING"
        }
    }
}

private struct IdentifiableChunk: Identifiable {
    let chunk: RetrievedChunk
    var id: UUID { chunk.chunk.id }
}
