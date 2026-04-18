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

    /// Claims that were considered but rejected or downgraded during verification
    let rejectedClaims: [RejectedClaim]

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
        /// The claim text
        let claim: String

        /// Evidence IDs supporting this claim (chunk IDs)
        let evidenceIds: [String]

        /// Confidence in this claim (0.0-1.0)
        let confidence: Float

        /// Whether this claim was directly extracted vs synthesized
        let isExtracted: Bool

        private enum CodingKeys: String, CodingKey {
            case claim
            case evidenceIds = "evidence_ids"
            case confidence
            case isExtracted = "is_extracted"
        }
    }

    /// Claim rejected during verification with reason for UI display
    struct RejectedClaim: Codable, Sendable {
        /// The rejected claim text
        let claim: String

        /// Verdict label such as unsupported, ambiguous, or contradicted
        let verdict: String

        /// Evidence IDs considered during rejection
        let evidenceIds: [String]

        /// Confidence/fidelity retained after verification
        let confidence: Float

        /// Whether this was a critical claim for answering the user
        let isCritical: Bool

        /// Optional reviewer note shown in diagnostics UI
        let notes: String?

        private enum CodingKeys: String, CodingKey {
            case claim
            case verdict
            case evidenceIds = "evidence_ids"
            case confidence
            case isCritical = "is_critical"
            case notes
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
        case rejectedClaims = "rejected_claims"
        case missing
        case debug
    }

    init(
        refuse: Bool,
        answerType: AnswerType,
        answer: String,
        claims: [Claim],
        evidence: [Evidence],
        rejectedClaims: [RejectedClaim] = [],
        missing: [String],
        debug: DebugInfo
    ) {
        self.refuse = refuse
        self.answerType = answerType
        self.answer = answer
        self.claims = claims
        self.evidence = evidence
        self.rejectedClaims = rejectedClaims
        self.missing = missing
        self.debug = debug
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refuse = try container.decode(Bool.self, forKey: .refuse)
        answerType = try container.decode(AnswerType.self, forKey: .answerType)
        answer = try container.decode(String.self, forKey: .answer)
        claims = try container.decodeIfPresent([Claim].self, forKey: .claims) ?? []
        evidence = try container.decodeIfPresent([Evidence].self, forKey: .evidence) ?? []
        rejectedClaims = try container.decodeIfPresent([RejectedClaim].self, forKey: .rejectedClaims) ?? []
        missing = try container.decodeIfPresent([String].self, forKey: .missing) ?? []
        debug = try container.decode(DebugInfo.self, forKey: .debug)
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
        private var rejectedClaims: [RejectedClaim] = []
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

        func addClaim(_ text: String, evidenceIds: [String], confidence: Float, isExtracted: Bool = true) -> Builder {
            claims.append(Claim(
                claim: text,
                evidenceIds: evidenceIds,
                confidence: confidence,
                isExtracted: isExtracted
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

        func addRejectedClaim(
            _ text: String,
            verdict: String,
            evidenceIds: [String],
            confidence: Float,
            isCritical: Bool,
            notes: String?
        ) -> Builder {
            rejectedClaims.append(RejectedClaim(
                claim: text,
                verdict: verdict,
                evidenceIds: evidenceIds,
                confidence: confidence,
                isCritical: isCritical,
                notes: notes
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
            return StructuredAnswer(
                refuse: refuse,
                answerType: answerType,
                answer: answer,
                claims: claims,
                evidence: evidence,
                rejectedClaims: rejectedClaims,
                missing: missing,
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
    static func refusal(reason: String, missing: [String] = [], topScore: Float = 0, loops: Int = 1) -> StructuredAnswer {
        return Builder()
            .setRefuse(true)
            .setAnswer(reason)
            .setTopScore(topScore)
            .setLoops(loops)
            .build()
    }
}

// MARK: - Conversion from RAGResponse

extension StructuredAnswer {
    /// Convert a RAGResponse to StructuredAnswer format
    /// This bridges the existing response format to the AppleRAG spec format
    static func from(
        response: String,
        retrievedChunks: [RetrievedChunk],
        answerIntent: AnswerIntent,
        verificationResult: RAGVerificationResult?,
        loops: Int = 1
    ) -> StructuredAnswer {
        let builder = Builder()
            .setAnswerType(AnswerType(rawValue: answerIntent.rawValue) ?? .lookup)
            .setAnswer(response)
            .setLoops(loops)

        // Add evidence from retrieved chunks
        let topScore = retrievedChunks.first?.similarityScore ?? 0
        _ = builder.setTopScore(topScore)

        for chunk in retrievedChunks.prefix(12) {  // Max 12 per spec
            _ = builder.addEvidence(
                id: chunk.chunk.id.uuidString,
                page: chunk.chunk.metadata.pageNumber,
                quote: String(chunk.chunk.content.prefix(240)),
                documentName: nil,  // Would need document lookup
                sectionPath: chunk.chunk.metadata.sectionPath
            )
        }

        // Add gate results if available
        if let verification = verificationResult {
            var gateResults: [String: Bool] = [:]
            for gate in verification.gateResults {
                gateResults[gate.gate.rawValue] = gate.passed
            }
            _ = builder.setGateResults(gateResults)
        }

        let fallbackSentences = splitFallbackClaims(from: response)
        let claimsToUse = fallbackSentences.isEmpty ? [response] : fallbackSentences

        for claimText in claimsToUse.prefix(6) {
            let citedEvidenceIds = citedEvidenceIDs(
                in: claimText,
                retrievedChunks: retrievedChunks
            )
            _ = builder.addClaim(
                claimText,
                evidenceIds: citedEvidenceIds,
                confidence: citedEvidenceIds.isEmpty ? max(0.35, topScore * 0.5) : topScore,
                isExtracted: answerIntent.isExtractiveFirst
            )
            if citedEvidenceIds.isEmpty {
                _ = builder.addMissing(claimText)
            }
        }

        return builder.build()
    }

    private static func splitFallbackClaims(from response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .flatMap { line in
                line.split(separator: ".", omittingEmptySubsequences: true).map { String($0) }
            }
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.count >= 12 }
            .map { sentence in
                if sentence.hasSuffix("?") || sentence.hasSuffix("!") || sentence.hasSuffix(".") {
                    return sentence
                }
                return sentence + "."
            }
    }

    private static func citedEvidenceIDs(
        in claimText: String,
        retrievedChunks: [RetrievedChunk]
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[S(\d+)\]"#) else { return [] }
        let range = NSRange(claimText.startIndex..<claimText.endIndex, in: claimText)
        let matches = regex.matches(in: claimText, options: [], range: range)
        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: claimText),
                  let index = Int(claimText[matchRange])
            else {
                return nil
            }

            let chunkIndex = index - 1
            guard chunkIndex >= 0, chunkIndex < retrievedChunks.count else { return nil }
            return retrievedChunks[chunkIndex].chunk.id.uuidString
        }
    }
}
