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

        // Extract claims from response (simplified - would use NLP in production)
        // For now, treat the whole response as one claim
        let evidenceIds = retrievedChunks.prefix(3).map { $0.chunk.id.uuidString }
        _ = builder.addClaim(
            response,
            evidenceIds: evidenceIds,
            confidence: topScore,
            isExtracted: answerIntent.isExtractiveFirst
        )

        return builder.build()
    }
}
