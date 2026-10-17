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
                let chunk = identifiableChunk.chunk
                let document = CitationSourceDocument.resolve(
                    chunk, found: libraryDocumentLookup?.document(chunk.chunk.documentId))
                // The page itself when the source is a PDF on this device, with the passage highlighted (5.7);
                // anything else opens the document's details, as before.
                if let page = CitationSourceDocument.page(of: chunk, in: document) {
                    SourcePageView(
                        document: document, pageNumber: page, passage: chunk.chunk.content, chunk: chunk,
                        lookup: libraryDocumentLookup)
                } else {
                    NavigationStack {
                        DocumentDetailsView(document: document, embeddingProviderId: nil, highlightedChunk: chunk)
                    }
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
                    
                    let destinations = evidenceDestinations
                    ForEach(Array(answer.claims.enumerated()), id: \.offset) { index, claim in
                        ClaimCard(
                            claim: claim,
                            evidence: answer.evidence,
                            evidenceDestinations: destinations,
                            onOpenEvidence: { evidence in
                                selectedCitationChunk = retrievedChunks.first { $0.chunk.id.uuidString == evidence.evidenceId }
                            },
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
    /// What tapping each Fact Check quote opens, by evidence id (a passage's id): its page, for a PDF on this device
    /// with a page number, or else its document's details (5.7). A quote whose passage this answer did not retrieve
    /// opens nothing.
    private var evidenceDestinations: [String: EvidenceDestination] {
        var destinations: [String: EvidenceDestination] = [:]
        for chunk in retrievedChunks {
            let document = CitationSourceDocument.resolve(
                chunk, found: libraryDocumentLookup?.document(chunk.chunk.documentId))
            destinations[chunk.chunk.id.uuidString] =
                CitationSourceDocument.page(of: chunk, in: document).map { EvidenceDestination.page($0) } ?? .details
        }
        return destinations
    }

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

/// What a Fact Check quote opens when it is tapped (5.7).
private enum EvidenceDestination: Equatable {
    /// The quote's page in its PDF, with the passage highlighted.
    case page(Int)
    /// Its document's details.
    case details
}

private struct ClaimCard: View {
    @Environment(\.showsTechnicalDetails) private var showsTechnicalDetails
    let claim: StructuredAnswer.Claim
    let evidence: [StructuredAnswer.Evidence]
    /// What each quote opens, by evidence id; a quote with none opens nothing (5.7).
    let evidenceDestinations: [String: EvidenceDestination]
    let onOpenEvidence: (StructuredAnswer.Evidence) -> Void
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
    
    /// What VoiceOver says a quote does when it is opened (5.7).
    private static func hint(for destination: EvidenceDestination?) -> String {
        switch destination {
        case .page(let page): return "Shows page \(page) of the document, with the passage highlighted."
        case .details: return "Shows the document's details."
        case nil: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The claim is the card's button, and the card's padding is part of it, so a one-line claim is a target
            // more than 44 points tall; the quotes under it are buttons of their own (5.7).
            Button(action: onTap) {
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
                            Group {
                                if showsTechnicalDetails {
                                    Text(
                                        "\(Text(verdictTitle).fontWeight(.bold).foregroundStyle(DSColors.primaryText)) • \(Int(claim.confidence * 100))% Conf.\(sourcesSuffix)"
                                    )
                                } else {
                                    // The plain chat says where the claim was found, not a confidence (5.7).
                                    Text("\(Text(plainVerdict).fontWeight(.bold).foregroundStyle(DSColors.primaryText))\(foundWhere)")
                                }
                            }
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
                .padding([.horizontal, .top], 12)
                .padding(.bottom, isExpanded ? 0 : 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                
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
                                // Opens the page the quote is on, or its document (5.7).
                                let destination = evidenceDestinations[ev.evidenceId]
                                Button {
                                    onOpenEvidence(ev)
                                } label: {
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
                                            if destination != nil {
                                                Image(systemName: "chevron.right")
                                                    .scaledFont(size: 7, weight: .bold)
                                            }
                                        }
                                        .scaledFont(size: 8, weight: .bold)
                                        // The accent on a quote that opens something, gray on one that does not.
                                        .foregroundStyle(
                                            destination == nil ? DSColors.secondaryText : DSColors.readable(DSColors.accent))
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, minHeight: DSSpacing.tapTarget, alignment: .leading)
                                    .background(DSColors.background.opacity(0.5))
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(destination == nil)
                                .accessibilityHint(Self.hint(for: destination))
                                .padding(.leading, 28)
                            }
                        }
                    }
                    
                    // The confidence goes with the technical view (5.7).
                    if showsTechnicalDetails {
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
                }
                .padding([.horizontal, .bottom], 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(isExpanded ? 0.08 : 0.02), radius: isExpanded ? 4 : 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(verdictColor.opacity(isExpanded ? 0.3 : 0.1), lineWidth: 1)
        )
        // A tap anywhere else on the card opens or closes the claim, as the whole card did through 5.6, instead of
        // reaching the message under it, whose tap shows its actions (5.7).
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onTap)
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
    
    /// The verdict in words for the plain chat (5.7).
    private var plainVerdict: String {
        switch claim.verificationVerdict {
        case .supported: return "Found in your documents"
        case .partial: return "Partly found in your documents"
        case .unsupported: return "Not found in your documents"
        case nil: return "Not checked"
        }
    }

    /// Where the plain chat says a claim was found: " · page 23 of Handpiece IFU.pdf" from its first quote with a
    /// page, else " · 1 source" (5.7).
    private var foundWhere: String {
        if let quote = matchingEvidence.first(where: { $0.page != nil }), let page = quote.page {
            if let name = quote.documentName, !name.isEmpty { return " · page \(page) of \(name)" }
            return " · page \(page)"
        }
        return claim.evidenceIds.isEmpty ? "" : (claim.evidenceIds.count == 1 ? " · 1 source" : " · \(claim.evidenceIds.count) sources")
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
