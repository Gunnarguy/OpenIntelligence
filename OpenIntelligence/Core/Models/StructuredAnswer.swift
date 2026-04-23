//
//  StructuredAnswer.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Structured answer format per AppleRAG spec §6.
//  Every answer outputs a structured object with evidence tracing.
//
//  This enables:
//  - 100% evidence traceability (every claim cites evidence_ids)
//  - Explicit uncertainty (refuse flag, missing fields)
//  - Verification-friendly format (claims can be validated)
//

import Foundation
import NaturalLanguage

// MARK: - Structured Answer (AppleRAG §6)

/// Structured answer output per AppleRAG spec §6.
/// Every answer is decomposed into claims with explicit evidence citations.
struct StructuredAnswer: Codable, Sendable {
    /// Whether the system refused to answer (insufficient evidence)
    let refuse: Bool

    /// The answer intent that was detected
    let answerType: AnswerType

    /// The final answer string (may be extractive span or synthesized)
    let answer: String

    /// Individual claims with evidence citations
    let claims: [Claim]

    /// Evidence passages used to support claims
    let evidence: [Evidence]

    /// Information that was requested but not found in corpus
    let missing: [String]

    /// Debug information for diagnostics
    let debug: DebugInfo

    /// Answer types matching AppleRAG intents
    enum AnswerType: String, Codable, Sendable {
        case lookup
        case tableLookup = "table_lookup"
        case procedure
        case compare
        case summarize
        case investigate
        case compute
        case refused
        case findings  // GOD MODE: Research/author discovery queries
    }

    /// Individual claim with evidence citation
    struct Claim: Codable, Sendable {
        enum VerificationVerdict: String, Codable, Sendable {
            case supported
            case partial
            case unsupported
        }

        /// The claim text
        let claim: String

        /// Evidence IDs supporting this claim (chunk IDs)
        let evidenceIds: [String]

        /// Confidence in this claim (0.0-1.0)
        let confidence: Float

        /// Whether this claim was directly extracted vs synthesized
        let isExtracted: Bool

        /// Per-claim verification verdict from Gate B when available
        let verificationVerdict: VerificationVerdict?

        /// Short explanation of the claim-level verification outcome
        let verificationDetails: String?

        private enum CodingKeys: String, CodingKey {
            case claim
            case evidenceIds = "evidence_ids"
            case confidence
            case isExtracted = "is_extracted"
            case verificationVerdict = "verification_verdict"
            case verificationDetails = "verification_details"
        }
    }

    /// Evidence passage with source reference
    struct Evidence: Codable, Sendable {
        /// Unique evidence ID (chunk ID)
        let evidenceId: String

        /// Page number if available
        let page: Int?

        /// Quote from source (max 240 chars per spec)
        let quote: String

        /// Document name for display
        let documentName: String?

        /// Section path for context
        let sectionPath: [String]?

        private enum CodingKeys: String, CodingKey {
            case evidenceId = "evidence_id"
            case page
            case quote
            case documentName = "document_name"
            case sectionPath = "section_path"
        }
    }

    /// Debug information for diagnostics
    struct DebugInfo: Codable, Sendable {
        /// Top rerank score
        let topScore: Float

        /// Number of retrieval loops performed
        let loops: Int

        /// Answer intent detected
        let intent: String

        /// Verification gate results
        let gateResults: [String: Bool]?

        /// Time taken for answer generation (ms)
        let generationTimeMs: Int?

        private enum CodingKeys: String, CodingKey {
            case topScore = "top_score"
            case loops
            case intent
            case gateResults = "gate_results"
            case generationTimeMs = "generation_time_ms"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case refuse
        case answerType = "answer_type"
        case answer
        case claims
        case evidence
        case missing
        case debug
    }
}

// MARK: - Builder

extension StructuredAnswer {
    /// Builder for constructing structured answers incrementally
    class Builder {
        private var refuse: Bool = false
        private var answerType: AnswerType = .lookup
        private var answer: String = ""
        private var claims: [Claim] = []
        private var evidence: [Evidence] = []
        private var missing: [String] = []
        private var topScore: Float = 0
        private var loops: Int = 1
        private var intent: String = "lookup"
        private var gateResults: [String: Bool]?
        private var generationTimeMs: Int?

        func setRefuse(_ refuse: Bool) -> Builder {
            self.refuse = refuse
            if refuse { self.answerType = .refused }
            return self
        }

        func setAnswerType(_ type: AnswerType) -> Builder {
            self.answerType = type
            self.intent = type.rawValue
            return self
        }

        func setAnswer(_ answer: String) -> Builder {
            self.answer = answer
            return self
        }

        func addClaim(
            _ text: String,
            evidenceIds: [String],
            confidence: Float,
            isExtracted: Bool = true,
            verificationVerdict: Claim.VerificationVerdict? = nil,
            verificationDetails: String? = nil
        ) -> Builder {
            claims.append(Claim(
                claim: text,
                evidenceIds: evidenceIds,
                confidence: confidence,
                isExtracted: isExtracted,
                verificationVerdict: verificationVerdict,
                verificationDetails: verificationDetails
            ))
            return self
        }

        func addEvidence(id: String, page: Int?, quote: String, documentName: String?, sectionPath: [String]?) -> Builder {
            // Truncate quote to 240 chars per spec
            let truncatedQuote = quote.count > 240 ? String(quote.prefix(237)) + "..." : quote
            evidence.append(Evidence(
                evidenceId: id,
                page: page,
                quote: truncatedQuote,
                documentName: documentName,
                sectionPath: sectionPath
            ))
            return self
        }

        func addMissing(_ item: String) -> Builder {
            missing.append(item)
            return self
        }

        func setTopScore(_ score: Float) -> Builder {
            self.topScore = score
            return self
        }

        func setLoops(_ loops: Int) -> Builder {
            self.loops = loops
            return self
        }

        func setGateResults(_ results: [String: Bool]) -> Builder {
            self.gateResults = results
            return self
        }

        func setGenerationTime(_ ms: Int) -> Builder {
            self.generationTimeMs = ms
            return self
        }

        func build() -> StructuredAnswer {
            let uniqueMissing = missing.reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }

            return StructuredAnswer(
                refuse: refuse,
                answerType: answerType,
                answer: answer,
                claims: claims,
                evidence: evidence,
                missing: uniqueMissing,
                debug: DebugInfo(
                    topScore: topScore,
                    loops: loops,
                    intent: intent,
                    gateResults: gateResults,
                    generationTimeMs: generationTimeMs
                )
            )
        }
    }

    /// Create a refusal response
    static func refusal(
        reason: String,
        missing: [String] = [],
        topScore: Float = 0,
        loops: Int = 1,
        retrievedChunks: [RetrievedChunk] = [],
        verificationResult: RAGVerificationResult? = nil
    ) -> StructuredAnswer {
        let builder = Builder()
            .setRefuse(true)
            .setAnswer(reason)
            .setTopScore(topScore)
            .setLoops(loops)

        for item in missing.map(cleanClaimText).filter({ !$0.isEmpty }) {
            _ = builder.addMissing(item)
        }

        addEvidenceEntries(from: retrievedChunks, fallback: [], to: builder)
        applyVerification(verificationResult, to: builder)

        return builder.build()
    }
}

// MARK: - Conversion from RAGResponse

extension StructuredAnswer {
    func updatingAnswer(_ updatedAnswer: String) -> StructuredAnswer {
        StructuredAnswer(
            refuse: refuse,
            answerType: answerType,
            answer: updatedAnswer,
            claims: claims,
            evidence: evidence,
            missing: missing,
            debug: debug
        )
    }

    private static let claimStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "how", "in", "is", "it",
        "of", "on", "or", "that", "the", "this", "to", "was", "were", "what", "when", "where", "with"
    ]

    /// Convert a RAGResponse to StructuredAnswer format
    /// This bridges the existing response format to the AppleRAG spec format
    static func from(
        response: String,
        retrievedChunks: [RetrievedChunk],
        answerIntent: AnswerIntent,
        verificationResult: RAGVerificationResult?,
        structuredGeneration: StructuredRAGGeneration? = nil,
        loops: Int = 1
    ) -> StructuredAnswer {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else {
            return .refusal(
                reason: "The response was empty.",
                topScore: retrievedChunks.first?.similarityScore ?? 0,
                loops: loops,
                retrievedChunks: retrievedChunks,
                verificationResult: verificationResult
            )
        }

        if let structuredGeneration {
            return buildFromStructuredGeneration(
                response: trimmedResponse,
                retrievedChunks: retrievedChunks,
                answerIntent: answerIntent,
                verificationResult: verificationResult,
                structuredGeneration: structuredGeneration,
                loops: loops
            )
        }

        let answerText = trimmedResponse

        let builder = Builder()
            .setAnswerType(AnswerType(rawValue: answerIntent.rawValue) ?? .lookup)
            .setAnswer(answerText)
            .setLoops(loops)

        let topScore = retrievedChunks.first?.similarityScore ?? 0
        _ = builder.setTopScore(topScore)

        let claims: [StructuredRAGClaim]
        if let structuredGeneration, !structuredGeneration.claims.isEmpty {
            claims = Array(structuredGeneration.claims.prefix(6))
        } else {
            claims = extractClaims(from: answerText, answerIntent: answerIntent).prefix(6).map {
                StructuredRAGClaim(
                    claim: $0,
                    citations: [],
                    isExtracted: false
                )
            }
        }

        var selectedEvidence: [RetrievedChunk] = []

        for claim in claims {
            let citedChunks = citedEvidence(for: claim.citations, in: retrievedChunks)
            let supportingChunks = citedChunks.isEmpty
                ? supportingEvidence(for: claim.claim, in: retrievedChunks)
                : citedChunks
            let evidenceIds = supportingChunks.map { $0.chunk.id.uuidString }
            let extractionConfidence = confidence(for: claim.claim, evidence: supportingChunks)
            let structuredConfidence = Float(structuredGeneration?.confidence ?? 0) / 100.0
            let claimConfidence = citedChunks.isEmpty
                ? extractionConfidence
                : min(1.0, max(0.2, (extractionConfidence * 0.7) + (structuredConfidence * 0.3)))
            let isExtracted = claim.isExtracted || isExtractiveClaim(
                claim.claim,
                evidence: supportingChunks,
                answerIntent: answerIntent
            )
            let verification = claimVerification(for: claim.claim, in: verificationResult)
            let adjustedClaimConfidence = calibratedClaimConfidence(claimConfidence, verification: verification)

            if evidenceIds.isEmpty {
                _ = builder.addMissing("Support not found for: \(String(claim.claim.prefix(72)))")
            }

            _ = builder.addClaim(
                claim.claim,
                evidenceIds: evidenceIds,
                confidence: adjustedClaimConfidence,
                isExtracted: isExtracted,
                verificationVerdict: verification.map { mapVerificationVerdict($0.verdict) },
                verificationDetails: verification?.details
            )

            for chunk in supportingChunks where !selectedEvidence.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                selectedEvidence.append(chunk)
            }
        }

        if selectedEvidence.isEmpty {
            selectedEvidence = Array(retrievedChunks.prefix(3))
        }

        let evidencePool = (selectedEvidence + retrievedChunks).reduce(into: [RetrievedChunk]()) { partial, chunk in
            if !partial.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                partial.append(chunk)
            }
        }

        for chunk in evidencePool.prefix(12) {  // Max 12 per spec
            let quoteSource = chunk.chunk.parentContent ?? chunk.chunk.content
            _ = builder.addEvidence(
                id: chunk.chunk.id.uuidString,
                page: chunk.chunk.metadata.pageNumber,
                quote: String(quoteSource.prefix(240)),
                documentName: chunk.sourceDocument.isEmpty ? nil : chunk.sourceDocument,
                sectionPath: chunk.chunk.metadata.sectionPath
            )
        }

        applyVerification(verificationResult, to: builder)

        return builder.build()
    }

    private static func buildFromStructuredGeneration(
        response: String,
        retrievedChunks: [RetrievedChunk],
        answerIntent: AnswerIntent,
        verificationResult: RAGVerificationResult?,
        structuredGeneration: StructuredRAGGeneration,
        loops: Int
    ) -> StructuredAnswer {
        let preferredAnswer = structuredGeneration.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let answerText = preferredAnswer.isEmpty ? response : preferredAnswer

        let builder = Builder()
            .setAnswerType(AnswerType(rawValue: answerIntent.rawValue) ?? .lookup)
            .setAnswer(answerText)
            .setLoops(loops)

        _ = builder.setTopScore(retrievedChunks.first?.similarityScore ?? 0)

        let normalizedClaims: [StructuredRAGClaim] = {
            let claims = structuredGeneration.claims.compactMap { claim -> StructuredRAGClaim? in
                let claimText = cleanClaimText(claim.claim)
                guard !claimText.isEmpty else { return nil }
                return StructuredRAGClaim(
                    claim: claimText,
                    citations: claim.citations,
                    isExtracted: claim.isExtracted
                )
            }

            if claims.isEmpty {
                return [StructuredRAGClaim(
                    claim: answerText,
                    citations: structuredGeneration.citations,
                    isExtracted: answerIntent.isExtractiveFirst
                )]
            }

            return Array(claims.prefix(6))
        }()

        let structuredConfidence = min(1.0, max(0.0, Float(structuredGeneration.confidence) / 100.0))
        var selectedEvidence: [RetrievedChunk] = []

        appendUnique(
            citedEvidence(for: structuredGeneration.citations, in: retrievedChunks),
            to: &selectedEvidence
        )

        for claim in normalizedClaims {
            let citedChunks = citedEvidence(for: claim.citations, in: retrievedChunks)
            let supportingChunks = citedChunks.isEmpty
                ? supportingEvidence(for: claim.claim, in: retrievedChunks)
                : citedChunks
            let evidenceIds = supportingChunks.map { $0.chunk.id.uuidString }
            let evidenceConfidence = confidence(for: claim.claim, evidence: supportingChunks)

            let claimConfidence: Float
            if !claim.citations.isEmpty && !citedChunks.isEmpty {
                claimConfidence = min(1.0, max(0.25, (evidenceConfidence * 0.6) + (structuredConfidence * 0.4)))
            } else if !claim.citations.isEmpty {
                claimConfidence = min(0.55, max(0.2, evidenceConfidence))
                _ = builder.addMissing("Citation could not be resolved for: \(String(claim.claim.prefix(72)))")
            } else if !supportingChunks.isEmpty {
                claimConfidence = min(0.6, max(0.2, (evidenceConfidence * 0.7) + (structuredConfidence * 0.3)))
                _ = builder.addMissing("Claim missing citation: \(String(claim.claim.prefix(72)))")
            } else {
                claimConfidence = min(0.35, max(0.15, structuredConfidence * 0.5))
                _ = builder.addMissing("Support not found for: \(String(claim.claim.prefix(72)))")
            }

            let verification = claimVerification(for: claim.claim, in: verificationResult)
            let adjustedClaimConfidence = calibratedClaimConfidence(claimConfidence, verification: verification)

            _ = builder.addClaim(
                claim.claim,
                evidenceIds: evidenceIds,
                confidence: adjustedClaimConfidence,
                isExtracted: claim.isExtracted || isExtractiveClaim(
                    claim.claim,
                    evidence: supportingChunks,
                    answerIntent: answerIntent
                ),
                verificationVerdict: verification.map { mapVerificationVerdict($0.verdict) },
                verificationDetails: verification?.details
            )

            appendUnique(supportingChunks, to: &selectedEvidence)
        }

        if selectedEvidence.isEmpty {
            appendUnique(Array(retrievedChunks.prefix(3)), to: &selectedEvidence)
        }

        addEvidenceEntries(from: selectedEvidence, fallback: retrievedChunks, to: builder)
        applyVerification(verificationResult, to: builder)

        return builder.build()
    }

    private static func extractClaims(from response: String, answerIntent: AnswerIntent) -> [String] {
        let lines = response
            .components(separatedBy: .newlines)
            .map { cleanClaimText($0) }
            .filter { !$0.isEmpty }

        let bulletClaims = lines.compactMap { line -> String? in
            let isBullet = line.hasPrefix("- ") || line.hasPrefix("• ") || line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) != nil
            guard isBullet else { return nil }
            return cleanClaimText(line.replacingOccurrences(of: #"^([-•]\s+|\d+[\.)]\s+)"#, with: "", options: .regularExpression))
        }

        if bulletClaims.count >= 2 {
            return uniqueClaims(bulletClaims).prefix(6).map { $0 }
        }

        var tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = response
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: response.startIndex..<response.endIndex) { range, _ in
            let sentence = cleanClaimText(String(response[range]))
            if sentence.count >= minimumClaimLength(for: answerIntent) {
                sentences.append(sentence)
            }
            return true
        }

        let extracted = uniqueClaims(sentences)
        if !extracted.isEmpty {
            return Array(extracted.prefix(6))
        }

        return [cleanClaimText(response)]
    }

    private static func supportingEvidence(for claim: String, in retrievedChunks: [RetrievedChunk]) -> [RetrievedChunk] {
        let claimTokens = keywordTokens(from: claim)

        let scored = retrievedChunks.map { chunk -> (RetrievedChunk, Float) in
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            let contentTokens = keywordTokens(from: content)
            let overlapCount = claimTokens.intersection(contentTokens).count
            let overlapScore = claimTokens.isEmpty ? 0 : Float(overlapCount) / Float(max(claimTokens.count, 1))
            let normalizedClaim = normalizeForMatch(claim)
            let normalizedContent = normalizeForMatch(content)
            let directMatch = !normalizedClaim.isEmpty && normalizedContent.contains(normalizedClaim)
            let directBoost: Float = directMatch ? 1.0 : 0.0
            let score = max(directBoost, min(1.0, (chunk.similarityScore * 0.35) + (overlapScore * 0.65)))
            return (chunk, score)
        }

        let filtered = scored
            .filter { $0.1 >= 0.18 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.similarityScore > rhs.0.similarityScore
                }
                return lhs.1 > rhs.1
            }

        return Array(filtered.prefix(3).map { $0.0 })
    }

    private static func citedEvidence(for citations: [String], in retrievedChunks: [RetrievedChunk]) -> [RetrievedChunk] {
        let resolved = citations.compactMap { citation -> RetrievedChunk? in
            guard let index = citationIndex(from: citation), retrievedChunks.indices.contains(index) else {
                return nil
            }
            return retrievedChunks[index]
        }

        return resolved.reduce(into: [RetrievedChunk]()) { partial, chunk in
            if !partial.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                partial.append(chunk)
            }
        }
    }

    private static func confidence(for claim: String, evidence: [RetrievedChunk]) -> Float {
        guard !evidence.isEmpty else { return 0.15 }
        let topEvidence = evidence[0]
        let content = topEvidence.chunk.parentContent ?? topEvidence.chunk.content
        let claimTokens = keywordTokens(from: claim)
        let contentTokens = keywordTokens(from: content)
        let overlap = claimTokens.isEmpty ? 0 : Float(claimTokens.intersection(contentTokens).count) / Float(max(claimTokens.count, 1))
        return min(1.0, max(0.2, (topEvidence.similarityScore * 0.5) + (overlap * 0.5)))
    }

    private static func isExtractiveClaim(_ claim: String, evidence: [RetrievedChunk], answerIntent: AnswerIntent) -> Bool {
        guard answerIntent.isExtractiveFirst else { return false }
        let normalizedClaim = normalizeForMatch(claim)
        return evidence.contains { chunk in
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            return normalizeForMatch(content).contains(normalizedClaim)
        }
    }

    private static func minimumClaimLength(for answerIntent: AnswerIntent) -> Int {
        answerIntent.isExtractiveFirst ? 8 : 20
    }

    private static func keywordTokens(from text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !claimStopWords.contains($0) }
        )
    }

    private static func cleanClaimText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\[S\d+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func citationIndex(from citation: String) -> Int? {
        let pattern = #"S(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(citation.startIndex..<citation.endIndex, in: citation)
        guard let match = regex.firstMatch(in: citation, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: citation),
              let index = Int(citation[range]),
              index > 0
        else {
            return nil
        }

        return index - 1
    }

    private static func normalizeForMatch(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
    }

    private static func uniqueClaims(_ claims: [String]) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for claim in claims {
            let normalized = normalizeForMatch(claim)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            unique.append(claim)
        }
        return unique
    }

    private static func appendUnique(_ chunks: [RetrievedChunk], to selectedEvidence: inout [RetrievedChunk]) {
        for chunk in chunks where !selectedEvidence.contains(where: { $0.chunk.id == chunk.chunk.id }) {
            selectedEvidence.append(chunk)
        }
    }

    private static func addEvidenceEntries(from preferredChunks: [RetrievedChunk], fallback: [RetrievedChunk], to builder: Builder) {
        let evidencePool = (preferredChunks + fallback).reduce(into: [RetrievedChunk]()) { partial, chunk in
            if !partial.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                partial.append(chunk)
            }
        }

        for chunk in evidencePool.prefix(12) {
            let quoteSource = chunk.chunk.parentContent ?? chunk.chunk.content
            _ = builder.addEvidence(
                id: chunk.chunk.id.uuidString,
                page: chunk.chunk.metadata.pageNumber,
                quote: String(quoteSource.prefix(240)),
                documentName: chunk.sourceDocument.isEmpty ? nil : chunk.sourceDocument,
                sectionPath: chunk.chunk.metadata.sectionPath
            )
        }
    }

    private static func claimVerification(
        for claim: String,
        in verificationResult: RAGVerificationResult?
    ) -> RAGVerificationResult.ClaimResult? {
        guard let verificationResult else { return nil }
        let normalizedClaim = normalizeForMatch(cleanClaimText(claim))
        guard !normalizedClaim.isEmpty else { return nil }

        return verificationResult.claimResults.first {
            normalizeForMatch(cleanClaimText($0.claim)) == normalizedClaim
        }
    }

    private static func calibratedClaimConfidence(
        _ baseConfidence: Float,
        verification: RAGVerificationResult.ClaimResult?
    ) -> Float {
        guard let verification else { return baseConfidence }

        let blended = min(1.0, max(0.0, (baseConfidence * 0.65) + (verification.confidence * 0.35)))

        switch verification.verdict {
        case .supported:
            return max(0.55, blended)
        case .partial:
            return min(0.64, max(0.25, blended))
        case .unsupported:
            return min(0.35, max(0.1, blended * 0.6))
        }
    }

    private static func mapVerificationVerdict(
        _ verdict: RAGVerificationResult.ClaimResult.Verdict
    ) -> Claim.VerificationVerdict {
        switch verdict {
        case .supported:
            return .supported
        case .partial:
            return .partial
        case .unsupported:
            return .unsupported
        }
    }

    private static func applyVerification(_ verificationResult: RAGVerificationResult?, to builder: Builder) {
        guard let verificationResult else { return }

        var gateResults: [String: Bool] = [:]
        for gate in verificationResult.gateResults {
            gateResults[gate.gate.rawValue] = gate.passed
        }
        _ = builder.setGateResults(gateResults)

        if let evidenceGate = verificationResult.gateResults.first(where: { $0.gate == .evidenceCoverage }),
           !evidenceGate.passed
        {
            _ = builder.addMissing(evidenceGate.details)
        }

        for claim in verificationResult.claimResults where claim.verdict == .unsupported {
            _ = builder.addMissing("Verification could not support claim: \(String(claim.claim.prefix(72)))")
        }

        if verificationResult.shouldAbstain, let reason = verificationResult.abstainReason {
            _ = builder.addMissing(reason)
        }
    }
}
