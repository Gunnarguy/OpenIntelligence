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
    @Environment(\.libraryDocumentLookup) private var libraryDocumentLookup
    
    private var modeColor: Color {
        let mode = modeName?.lowercased() ?? ""
        if mode.contains("max") { return .orange }
        if mode.contains("deep") { return .purple }
        return DSColors.accent
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main answer text with interactive citations. `CitationLinker` resolves each label
            // to a chunk when it builds the link: before 5.6 only a bare `[3]` became a link, and
            // the answer prompt asks for `[S3]`, so no citation in a real answer could be tapped.
            let linkedAnswer = CitationLinker.linkedMarkdown(
                answer.answer,
                evidence: answer.evidence,
                retrievedChunks: retrievedChunks
            )
            
            // 14 points at the default text size, scaled with Dynamic Type on iPhone and iPad (5.7).
            MarkdownText(
                linkedAnswer,
                scaledSize: 14,
                foregroundColor: DSColors.primaryText
            )
            .environment(\.openURL, OpenURLAction { url in
                if let chunk = CitationLinker.chunk(for: url, in: retrievedChunks) {
                    selectedCitationChunk = chunk
                    return .handled
                }
                // A citation link that resolves to nothing is ours to swallow: handing it to the
                // system logs "Failed to open URL citation://..." and does nothing.
                return url.scheme == CitationLinker.scheme ? .handled : .systemAction
            })
            .sheet(item: Binding(
                get: { selectedCitationChunk.map { IdentifiableChunk(chunk: $0) } },
                set: { selectedCitationChunk = $0?.chunk }
            )) { identifiableChunk in
                NavigationStack {
                    DocumentDetailsView(
                        document: CitationSourceDocument.resolve(
                            identifiableChunk.chunk, found: libraryDocumentLookup?.document(identifiableChunk.chunk.chunk.documentId)),
                        embeddingProviderId: nil,
                        highlightedChunk: identifiableChunk.chunk
                    )
                }
            }

            
            if !answer.claims.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("FACT CHECK")
                            .scaledFont(size: 9, weight: .bold)
                            .foregroundStyle(DSColors.secondaryText)
                            .tracking(1)
                        
                        Spacer()
                        
                        // The words in the label color and the mode's color in the icon and the tint, as on the
                        // other tinted chips (5.7).
                        HStack(spacing: 3) {
                            Image(systemName: "shield.checkered")
                                .scaledFont(size: 9)
                                .foregroundStyle(DSColors.readable(modeColor))
                            Text(Self.factCheckSummary(for: answer.claims))
                                .scaledFont(size: 9, weight: .medium)
                        }
                        .foregroundStyle(DSColors.primaryText)
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
                            .scaledFont(size: 12)
                            .foregroundStyle(DSColors.readable(.orange))
                        Text("Information Gaps")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(DSColors.readable(.orange))
                    }
                    
                    ForEach(answer.missing, id: \.self) { item in
                        Text("• \(item)")
                            .scaledFont(size: 12)
                            .foregroundStyle(DSColors.secondaryText)
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

extension GroundedAnswerView {
    /// "3 Verified" was printed for any three claims. Count the verdicts instead.
    nonisolated static func factCheckSummary(for claims: [StructuredAnswer.Claim]) -> String {
        let supported = claims.filter { $0.verificationVerdict == .supported }.count
        let checked = claims.filter { $0.verificationVerdict != nil }.count
        if checked == 0 { return "\(claims.count) Not Checked" }
        if supported == claims.count { return "\(supported) Verified" }
        return "\(supported) of \(claims.count) Verified"
    }

    /// A claim's text can carry the model's inline markdown (`**350°F**`). `Text` made from a
    /// String shows the asterisks, so parse the inline syntax and fall back to the plain string.
    nonisolated static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct ClaimCard: View {
    let claim: StructuredAnswer.Claim
    let evidence: [StructuredAnswer.Evidence]
    let isExpanded: Bool
    let onTap: () -> Void

    /// " • 1 Source", " • 3 Sources", or nothing when no source backs the claim.
    private var sourcesSuffix: String {
        switch claim.evidenceIds.count {
        case 0: return ""
        case 1: return " • 1 Source"
        default: return " • \(claim.evidenceIds.count) Sources"
        }
    }
    
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
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(verdictColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GroundedAnswerView.inlineMarkdown(claim.claim))
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(DSColors.primaryText)
                            // The whole claim, open or closed: opening adds the evidence, and two lines cut a
                            // claim off at the larger text sizes (5.7).
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        
                        if !isExpanded {
                            // One text, so that at the largest sizes it wraps between words: as five texts side by
                            // side it was squeezed until "SUPPORTED" broke into "SUPP / ORTE / D" (5.7). The word is
                            // in the label color, the verdict's color in the icon: Apple's high-contrast green
                            // measured 4.07 to 1 on the card's gray.
                            Text(
                                "\(Text(verdictTitle).fontWeight(.bold).foregroundStyle(DSColors.primaryText)) • \(Int(claim.confidence * 100))% Conf.\(sourcesSuffix)"
                            )
                            .scaledFont(size: 8)
                            .foregroundStyle(DSColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 9, weight: .bold)
                        .foregroundStyle(DSColors.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        if let details = claim.verificationDetails {
                            Text(details)
                                .scaledFont(size: 11)
                                .foregroundStyle(DSColors.secondaryText)
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
                                    .scaledFont(size: 8, weight: .bold)
                                    .foregroundStyle(DSColors.secondaryText)
                                    .padding(.leading, 28)
                                
                                ForEach(relevantEvidence, id: \.evidenceId) { ev in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\"\(ev.quote)\"")
                                            .scaledFont(size: 10, weight: .medium, design: .serif)
                                            .foregroundStyle(DSColors.primaryText.opacity(0.9))
                                            .italic()
                                        
                                        HStack(spacing: 3) {
                                            Image(systemName: "doc.fill")
                                                .scaledFont(size: 7)
                                            Text(ev.documentName ?? "Unknown")
                                            if let page = ev.page {
                                                Text("• P.\(page)")
                                            }
                                        }
                                        .scaledFont(size: 8, weight: .bold)
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
                                .scaledFont(size: 8, weight: .bold)
                                .foregroundStyle(DSColors.secondaryText)
                            
                            ProgressView(value: claim.confidence)
                                .progressViewStyle(.linear)
                                .tint(verdictColor)
                                .frame(width: 50)
                            
                            Text("\(Int(claim.confidence * 100))%")
                                .scaledFont(size: 9, weight: .bold, design: .rounded)
                                .foregroundStyle(DSColors.primaryText)
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
    
    /// The readable variants (5.7), for the verdict's icon and tints. Its word ("SUPPORTED") is in the label color:
    /// Apple's high-contrast green measured 4.07 to 1 on the card.
    private var verdictColor: Color {
        switch claim.verificationVerdict {
        case .supported: return DSColors.readable(.green)
        case .partial: return DSColors.readable(.orange)
        case .unsupported: return DSColors.readable(.red)
        case nil: return DSColors.readable(.blue)
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
        // A claim with no verdict was never checked. The answer is attached after generation
        // and nothing fills the verdict in later, so "VERIFYING" never finished.
        case nil: return "NOT CHECKED"
        }
    }
}

private struct IdentifiableChunk: Identifiable {
    let chunk: RetrievedChunk
    var id: UUID { chunk.chunk.id }
}
