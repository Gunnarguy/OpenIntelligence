//
//  VerificationGateService.swift
//  OpenIntelligence
//
//  Verification gates for anti-hallucination (AppleRAG Spec Phase 2.06).
//  Implements Gates A-G to ensure answers are grounded in retrieved evidence.
//
//  Gate A: Retrieval Confidence - require max(score) >= τ AND margin >= μ
//  Gate B: Evidence Coverage - all claims must cite evidence_ids
//  Gate C: Numeric Sanity - numbers in response must match source
//  Gate D: Contradiction Sweep - detect conflicting evidence
//

import Foundation
import NaturalLanguage
import Accelerate

// MARK: - Verification Result

/// Result of running verification gates on a response
/// Named RAGVerificationResult to avoid collision with StoreKit's VerificationResult<T>
struct RAGVerificationResult: Sendable {
    let passed: Bool
    let gateResults: [GateResult]
    let overallConfidence: Float
    let shouldAbstain: Bool
    let abstainReason: String?

    /// Individual gate result
    struct GateResult: Sendable {
        let gate: VerificationGate
        let passed: Bool
        let confidence: Float
        let details: String
    }

    /// Which gates failed (for logging/debugging)
    nonisolated var failedGates: [VerificationGate] {
        gateResults.filter { !$0.passed }.map { $0.gate }
    }
}

/// The seven verification gates from AppleRAG spec
enum VerificationGate: String, CaseIterable, Sendable {
    case retrievalConfidence = "Gate A: Retrieval Confidence"
    case evidenceCoverage = "Gate B: Evidence Coverage"
    case numericSanity = "Gate C: Numeric Sanity"
    case contradictionSweep = "Gate D: Contradiction Sweep"
    case semanticGrounding = "Gate E: Semantic Grounding"
    case quoteFaithfulness = "Gate F: Quote Faithfulness"
    case generationQuality = "Gate G: Generation Quality"
}

// MARK: - Verification Configuration

/// Thresholds for verification gates (calibrate based on eval set)
struct VerificationConfig: Sendable {
    /// Minimum top rerank score to pass Gate A
    let tauNormal: Float
    /// Stricter threshold for "touchy" queries (medical, legal, financial)
    let tauTouchy: Float
    /// Minimum margin between top-1 and top-2 scores
    let muMargin: Float
    /// Minimum cosine similarity between response embedding and best-matching source chunk
    /// Below this threshold, the response is semantically ungrounded = likely hallucination
    let semanticGroundingThreshold: Float

    /// Categories that trigger stricter thresholds
    let touchyCategories: Set<String>

    /// Default thresholds - calibrated for real-world retrieval
    /// Note: tauNormal lowered from 0.55 to 0.40 because keyword-heavy queries
    /// often have lower semantic scores even when BM25 finds the right content
    nonisolated static let `default` = VerificationConfig(
        tauNormal: 0.40,
        tauTouchy: 0.55,
        muMargin: 0.03,
        semanticGroundingThreshold: 0.50,
        touchyCategories: ["medical", "legal", "financial", "safety", "dosage", "drug", "medication"]
    )

    /// Stricter config for high-risk applications
    nonisolated static let strict = VerificationConfig(
        tauNormal: 0.65,
        tauTouchy: 0.75,
        muMargin: 0.10,
        semanticGroundingThreshold: 0.60,
        touchyCategories: ["medical", "legal", "financial", "safety", "dosage", "drug", "medication", "regulatory", "compliance"]
    )
}

// MARK: - Verification Gate Service

/// Service that runs verification gates to ensure response quality
/// Implements the "nuclear option" anti-hallucination checks from AppleRAG spec
actor VerificationGateService {

    static let shared = VerificationGateService()

    private let config: VerificationConfig

    init(config: VerificationConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Run all verification gates on a response
    /// - Parameters:
    ///   - response: The generated response text
    ///   - query: The original user query
    ///   - retrievedChunks: Chunks used to generate the response (context-budget subset)
    ///   - topScores: Relevance scores from reranking (sorted descending)
    ///   - allCandidateChunks: ALL retrieved chunks before context-budget truncation.
    ///     Gate C uses this wider set for numeric verification since the LLM may reference
    ///     numbers from chunks that were truncated from context but visible in spec scans.
    ///   - responseEmbedding: 384-dim embedding of the LLM response (computed by caller
    ///     since EmbeddingService isn't available inside this actor). When provided, enables
    ///     Gate E (Semantic Grounding) — the strongest hallucination detector.
    ///   - queryEmbedding: 384-dim embedding of the original query. Used for relative
    ///     grounding — comparing how close the response is to chunks vs how close the
    ///     query is to chunks. If the response drifts far from what the query matched,
    ///     it's fabricating content.
    ///   - chunkEmbeddings: Raw 384-dim embeddings for each chunk in retrievedChunks,
    ///     loaded from the VectorDatabase mmap file. Needed because RetrievedChunk.chunk.embedding
    ///     is always [] to save memory during search.
    /// - Returns: Verification result with pass/fail for each gate
    func verify(
        response: String,
        query: String,
        retrievedChunks: [RetrievedChunk],
        topScores: [Float],
        allCandidateChunks: [RetrievedChunk]? = nil,
        responseEmbedding: [Float]? = nil,
        queryEmbedding: [Float]? = nil,
        chunkEmbeddings: [[Float]]? = nil
    ) async -> RAGVerificationResult {

        let isTouchy = detectTouchyQuery(query)
        let tau = isTouchy ? config.tauTouchy : config.tauNormal

        var gateResults: [RAGVerificationResult.GateResult] = []

        // Gate A: Retrieval Confidence
        let gateA = await runGateA(topScores: topScores, tau: tau)
        gateResults.append(gateA)

        // Gate B: Evidence Coverage
        let gateB = await runGateB(response: response, chunks: retrievedChunks)
        gateResults.append(gateB)

        // Gate C: Numeric Sanity — uses ALL candidate chunks for wider verification scope
        // The LLM might reference numbers from spec chunks that were truncated from context
        let gateCChunks = allCandidateChunks ?? retrievedChunks
        let gateC = await runGateC(response: response, chunks: gateCChunks)
        gateResults.append(gateC)

        // Gate D: Contradiction Sweep
        let gateD = await runGateD(response: response, chunks: retrievedChunks)
        gateResults.append(gateD)

        // Gate E: Semantic Grounding — the real hallucination killer
        // Uses EMBEDDINGS to check if the response MEANING is grounded in source chunks.
        // Requires: responseEmbedding (LLM output embedded), chunkEmbeddings (source chunk
        // vectors loaded from mmap), and queryEmbedding (for relative grounding check).
        if let responseVec = responseEmbedding,
           let chunkVecs = chunkEmbeddings,
           !responseVec.isEmpty,
           !chunkVecs.isEmpty {
            let gateE = runGateE(
                responseEmbedding: responseVec,
                queryEmbedding: queryEmbedding,
                chunkEmbeddings: chunkVecs,
                response: response
            )
            gateResults.append(gateE)
        }

        // Gate F: Quote Faithfulness — catch abbreviation cross-contamination
        // Verifies that abbreviation expansions in the response match document definitions.
        // Example: If document defines "ED = Emotional Dysregulation" but LLM writes
        // "oppositional defiant disorder (ED)", Gate F catches this fabrication.
        let gateF = runGateF(response: response, chunks: retrievedChunks)
        gateResults.append(gateF)

        // Gate G: Generation Quality — information-theoretic degeneration detector
        // Catches repetition loops, low-entropy output, and lexical poverty that
        // slip through all upstream defenses. Uses Shannon entropy, unique-word
        // ratio, and n-gram dominance — zero regex needed.
        let gateG = runGateG(response: response)
        gateResults.append(gateG)

        // Calculate overall result
        let allPassed = gateResults.allSatisfy { $0.passed }
        let overallConfidence = gateResults.reduce(0.0) { $0 + $1.confidence } / Float(gateResults.count)

        // Determine if we should abstain
        // Gate E (semantic grounding) is critical — if the response is semantically ungrounded,
        // it's almost certainly hallucinated regardless of what other gates say
        let criticalGates: Set<VerificationGate> = [.retrievalConfidence, .numericSanity, .semanticGrounding]
        let criticalFailures = gateResults.filter { !$0.passed && criticalGates.contains($0.gate) }
        let shouldAbstain = !criticalFailures.isEmpty

        let abstainReason: String? = {
            if shouldAbstain {
                let failedGateNames = criticalFailures.map { $0.gate.rawValue }.joined(separator: ", ")
                return "Verification failed: \(failedGateNames)"
            }
            return nil
        }()

        let result = RAGVerificationResult(
            passed: allPassed,
            gateResults: gateResults,
            overallConfidence: overallConfidence,
            shouldAbstain: shouldAbstain,
            abstainReason: abstainReason
        )

        Log.debug("[VerificationGates] Result: \(allPassed ? "PASS" : "FAIL") (confidence: \(String(format: "%.2f", overallConfidence)), touchy: \(isTouchy))", category: .retrieval)

        return result
    }

    /// Quick check for retrieval confidence only (use before generation)
    func checkRetrievalConfidence(topScores: [Float], isTouchy: Bool = false) -> Bool {
        let tau = isTouchy ? config.tauTouchy : config.tauNormal
        guard let maxScore = topScores.first, maxScore >= tau else { return false }

        if topScores.count >= 2 {
            let margin = topScores[0] - topScores[1]
            return margin >= config.muMargin
        }
        return true
    }

    // MARK: - Gate Implementations

    /// Gate A: Retrieval Confidence
    /// Require max(chunk_scores) >= τ
    /// NOTE: Margin requirement removed - multiple high-scoring chunks is GOOD, not bad
    private func runGateA(topScores: [Float], tau: Float) async -> RAGVerificationResult.GateResult {
        guard let maxScore = topScores.first else {
            return RAGVerificationResult.GateResult(
                gate: .retrievalConfidence,
                passed: false,
                confidence: 0,
                details: "No retrieval scores available"
            )
        }

        // Simply check if top score meets threshold
        // Having multiple good matches (low margin) is actually BETTER for retrieval
        let passed = maxScore >= tau

        // Calculate margin for informational purposes only
        let margin: Float = topScores.count >= 2 ? topScores[0] - topScores[1] : 1.0
        let details = "maxScore=\(String(format: "%.3f", maxScore)) (τ=\(String(format: "%.2f", tau))), margin=\(String(format: "%.3f", margin)) (info only)"

        return RAGVerificationResult.GateResult(
            gate: .retrievalConfidence,
            passed: passed,
            confidence: min(maxScore, 1.0),
            details: details
        )
    }

    /// Gate B: Evidence Coverage
    /// Check that key claims in response can be traced to retrieved chunks
    /// CONSERVATIVE: Only fail for egregious cases, not normal extractive lookups
    private func runGateB(response: String, chunks: [RetrievedChunk]) async -> RAGVerificationResult.GateResult {
        // Extract key claims/facts from response
        let claims = extractClaims(from: response)
        guard !claims.isEmpty else {
            return RAGVerificationResult.GateResult(
                gate: .evidenceCoverage,
                passed: true,
                confidence: 1.0,
                details: "No extractable claims in response"
            )
        }

        // Build corpus from chunks - include parent content for expanded chunks
        let corpus = chunks.map { chunk -> String in
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            return content.lowercased()
        }.joined(separator: " ")

        // Check coverage of each claim
        var coveredCount = 0
        for claim in claims {
            if isClaimCovered(claim: claim, inCorpus: corpus) {
                coveredCount += 1
            }
        }

        let coverage = Float(coveredCount) / Float(claims.count)
        // RELAXED: Require only 40% of claims to be grounded (was 70%)
        // Many valid responses include phrasing not verbatim in source
        let passed = coverage >= 0.40

        return RAGVerificationResult.GateResult(
            gate: .evidenceCoverage,
            passed: passed,
            confidence: coverage,  // Report actual coverage — no artificial floor
            details: "\(coveredCount)/\(claims.count) claims covered (\(Int(coverage * 100))%)"
        )
    }

    /// Gate C: Numeric Sanity
    /// If response contains numbers, verify they appear in source documents
    /// This gate catches HALLUCINATED numbers - keep it strict!
    private func runGateC(response: String, chunks: [RetrievedChunk]) async -> RAGVerificationResult.GateResult {
        // Extract numbers from response
        let responseNumbers = extractNumbers(from: response)
        guard !responseNumbers.isEmpty else {
            return RAGVerificationResult.GateResult(
                gate: .numericSanity,
                passed: true,
                confidence: 1.0,
                details: "No numeric values in response"
            )
        }

        // Extract numbers from source chunks (include parent content)
        let sourceNumbers = Set(chunks.flatMap { chunk -> [String] in
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            return extractNumbers(from: content)
        })

        // Build full text for word-boundary matching
        let sourceText = chunks.map { $0.chunk.parentContent ?? $0.chunk.content }.joined(separator: " ")

        // Check if response numbers appear in source
        var verifiedCount = 0
        var unverifiedNumbers: [String] = []

        for number in responseNumbers {
            if sourceNumbers.contains(number) {
                verifiedCount += 1
            } else {
                // Allow small variations (e.g., "5" matching "5.0")
                let normalized = normalizeNumber(number)
                if sourceNumbers.contains(where: { normalizeNumber($0) == normalized }) {
                    verifiedCount += 1
                } else if sourceText.contains(number) {
                    // Number appears somewhere in source text (may be part of a larger value)
                    verifiedCount += 1
                } else {
                    // Don't penalize year numbers (2024, 2025) or common page/section refs
                    let isLikelyMetadata = isYearOrReference(number)
                    if isLikelyMetadata {
                        verifiedCount += 1
                    } else {
                        unverifiedNumbers.append(number)
                    }
                }
            }
        }

        let verification = Float(verifiedCount) / Float(responseNumbers.count)
        let passed = verification >= 0.70

        let details: String
        if unverifiedNumbers.isEmpty {
            details = "All \(responseNumbers.count) numbers verified in source"
        } else {
            details = "\(verifiedCount)/\(responseNumbers.count) verified. Unverified: \(unverifiedNumbers.prefix(3).joined(separator: ", "))"
        }

        return RAGVerificationResult.GateResult(
            gate: .numericSanity,
            passed: passed,
            confidence: verification,
            details: details
        )
    }

    /// Check if a number looks like a year, page reference, or section number.
    /// These are commonly inferred from document metadata, not hallucinated.
    ///
    /// IMPORTANT: We deliberately do NOT auto-verify small integers (1-50) because
    /// real document data like temperatures (32°F), pressures (35 psi), volumes
    /// (18 gallons), or doses (25 mg) fall in this range. Auto-verifying them
    /// would let hallucinated measurement values pass Gate C unchecked.
    /// Only years and explicit "Section X.Y" / "Figure N" patterns get a pass.
    private func isYearOrReference(_ number: String) -> Bool {
        // Year pattern: 1900-2100 (covers historical through future documents)
        if let year = Int(number), year >= 1900, year <= 2100 {
            return true
        }
        // Section/figure references are typically formatted as "X.Y" — handled elsewhere.
        // Single integers 1-50 are NOT auto-verified because they could be real data.
        return false
    }

    /// Gate D: Contradiction Sweep
    /// Check for contradicting evidence in retrieved chunks
    private func runGateD(response: String, chunks: [RetrievedChunk]) async -> RAGVerificationResult.GateResult {
        // Look for contradiction indicators in chunks
        let contradictions = detectContradictions(in: chunks)

        if contradictions.isEmpty {
            return RAGVerificationResult.GateResult(
                gate: .contradictionSweep,
                passed: true,
                confidence: 1.0,
                details: "No contradictions detected in evidence"
            )
        }

        // We found potential contradictions - this doesn't fail the gate,
        // but lowers confidence and flags for user attention
        let confidence: Float = max(0.3, 1.0 - Float(contradictions.count) * 0.2)

        return RAGVerificationResult.GateResult(
            gate: .contradictionSweep,
            passed: confidence >= 0.5,  // Fail if too many contradictions
            confidence: confidence,
            details: "Found \(contradictions.count) potential contradiction(s): \(contradictions.first ?? "")"
        )
    }

    // MARK: - Gate E: Semantic Grounding

    /// Gate E: Semantic Grounding — the real hallucination killer.
    ///
    /// Instead of string-matching numbers or keywords, this gate checks whether the
    /// MEANING of the LLM's response is grounded in the source chunks. It does this by
    /// computing cosine similarity between the response embedding and each source chunk's
    /// embedding vector. If the response is semantically distant from ALL source chunks,
    /// it's fabricated — regardless of whether individual words or numbers happen to appear
    /// in the source text.
    ///
    /// Example: "The car can hold 12567 miles of gasoline" has ~0.15 cosine similarity
    /// to any chunk about fuel specifications → FAIL. A real answer like "The fuel tank
    /// capacity is 18.5 gallons" would have ~0.65 similarity to the fuel specs chunk → PASS.
    ///
    /// - Parameters:
    ///   - responseEmbedding: 384-dim embedding of the LLM response
    ///   - responseEmbedding: 384-dim L2-normalized embedding of the LLM response
    ///   - queryEmbedding: 384-dim L2-normalized embedding of the original query (nil = absolute mode)
    ///   - chunkEmbeddings: Raw 384-dim embeddings loaded from VectorDatabase mmap file.
    ///     These are the ACTUAL chunk vectors — not from RetrievedChunk.chunk.embedding which
    ///     is always [] in production (BNNSVectorDatabase strips them to save memory).
    ///   - response: Raw response text (for logging)
    /// - Returns: Gate result with grounding confidence
    ///
    /// ## Relative Grounding (when queryEmbedding is provided)
    ///
    /// Instead of comparing response-chunk similarity against a fixed threshold,
    /// we compare it against query-chunk similarity. The query IS grounded because
    /// the search system selected these chunks as relevant to it. If the response
    /// drifts FURTHER from the chunks than the query was, it's fabricating content.
    ///
    /// The key insight: MiniLM-L6-v2 measures TOPIC similarity, not factual accuracy.
    /// A hallucinated "12567 miles of gasoline" scores 0.38-0.52 against fuel spec chunks
    /// because it's the same TOPIC (fuel). But the query "how much gasoline" scores
    /// 0.55-0.70 against those same chunks. The response DROPPED — that's the signal.
    ///
    /// Ratio = maxSim(response, chunks) / maxSim(query, chunks)
    /// - Ratio ≥ 0.85: Response is at least as grounded as the query → PASS
    /// - Ratio < 0.85: Response drifted from source material → FAIL
    ///
    /// ## Absolute Mode (when queryEmbedding is nil)
    /// Falls back to fixed threshold comparison.
    private func runGateE(
        responseEmbedding: [Float],
        queryEmbedding: [Float]?,
        chunkEmbeddings: [[Float]],
        response: String
    ) -> RAGVerificationResult.GateResult {

        guard !chunkEmbeddings.isEmpty else {
            return RAGVerificationResult.GateResult(
                gate: .semanticGrounding,
                passed: true,
                confidence: 1.0,
                details: "No chunk embeddings to ground against"
            )
        }

        // ── Step 1: Compute response ↔ chunk similarities ──────────────────
        var responseMaxSim: Float = 0.0
        var responseAvgSim: Float = 0.0
        var bestChunkIndex = 0

        for (i, chunkVec) in chunkEmbeddings.enumerated() {
            guard chunkVec.count == responseEmbedding.count else { continue }
            let sim = vectorCosineSimilarity(responseEmbedding, chunkVec)
            responseAvgSim += sim
            if sim > responseMaxSim {
                responseMaxSim = sim
                bestChunkIndex = i
            }
        }
        responseAvgSim /= Float(max(chunkEmbeddings.count, 1))

        // ── Step 2: Relative grounding (preferred) or absolute threshold ───
        if let queryVec = queryEmbedding, !queryVec.isEmpty {
            // Compute query ↔ chunk similarities for comparison baseline
            var queryMaxSim: Float = 0.0
            for chunkVec in chunkEmbeddings {
                guard chunkVec.count == queryVec.count else { continue }
                let sim = vectorCosineSimilarity(queryVec, chunkVec)
                if sim > queryMaxSim {
                    queryMaxSim = sim
                }
            }

            // Relative grounding ratio
            // If query matched chunks at 0.65 and response matches at 0.60, ratio = 0.92 → PASS
            // If query matched at 0.65 and response matches at 0.40, ratio = 0.62 → FAIL (drifted)
            let ratio: Float = queryMaxSim > 0.01 ? (responseMaxSim / queryMaxSim) : 0.0

            // Also apply a floor — even with good ratio, if the absolute similarity
            // is extremely low, the embeddings might be unreliable
            let absoluteFloor: Float = 0.25
            let relativeThreshold: Float = 0.80  // Response should be ≥80% as similar as query

            let passed = ratio >= relativeThreshold && responseMaxSim >= absoluteFloor

            let details: String
            if passed {
                details = "Grounded (ratio=\(String(format: "%.3f", ratio)), " +
                    "respMax=\(String(format: "%.3f", responseMaxSim)), " +
                    "qryMax=\(String(format: "%.3f", queryMaxSim)), " +
                    "avgSim=\(String(format: "%.3f", responseAvgSim)), " +
                    "bestChunk=\(bestChunkIndex))"
            } else {
                details = "UNGROUNDED (ratio=\(String(format: "%.3f", ratio)) < \(String(format: "%.2f", relativeThreshold)), " +
                    "respMax=\(String(format: "%.3f", responseMaxSim)), " +
                    "qryMax=\(String(format: "%.3f", queryMaxSim))). " +
                    "Response meaning drifted from source chunks."
                Log.warning("[VerificationGates] Gate E: Relative grounding FAIL — " +
                    "response drifted from sources (ratio=\(String(format: "%.3f", ratio)), " +
                    "respMax=\(String(format: "%.3f", responseMaxSim)), " +
                    "qryMax=\(String(format: "%.3f", queryMaxSim)))", category: .pipeline)
            }

            return RAGVerificationResult.GateResult(
                gate: .semanticGrounding,
                passed: passed,
                confidence: responseMaxSim,
                details: details
            )
        }

        // ── Step 3: Absolute fallback (no query embedding available) ───────
        let passed = responseMaxSim >= config.semanticGroundingThreshold

        let details: String
        if passed {
            details = "Grounded-absolute (max=\(String(format: "%.3f", responseMaxSim)), avg=\(String(format: "%.3f", responseAvgSim)), bestChunk=\(bestChunkIndex))"
        } else {
            details = "UNGROUNDED (max=\(String(format: "%.3f", responseMaxSim)) < \(String(format: "%.2f", config.semanticGroundingThreshold)), avg=\(String(format: "%.3f", responseAvgSim))). Response meaning does not match any source chunk."
            Log.warning("[VerificationGates] Gate E: Absolute grounding FAIL (max cosine=\(String(format: "%.3f", responseMaxSim)))", category: .pipeline)
        }

        return RAGVerificationResult.GateResult(
            gate: .semanticGrounding,
            passed: passed,
            confidence: responseMaxSim,
            details: details
        )
    }

    // MARK: - Gate F: Quote Faithfulness (Abbreviation Cross-Contamination Detection)

    /// Pre-compiled regex matching "Full Term (ABBR)" patterns in LLM responses.
    /// Detects when the LLM expands an abbreviation inline, e.g., "emotional dysregulation (ED)".
    /// We then verify the expansion matches what the source documents define.
    private static let responseAbbreviationRegex: NSRegularExpression? = {
        // Matches: "some words (XX)" where XX is 2-8 uppercase letters
        try? NSRegularExpression(
            pattern: #"((?:\b[a-zA-Z]+\s+){1,5})\(([A-Z]{2,8})\)"#,
            options: []
        )
    }()

    /// Gate F: Quote Faithfulness — catch abbreviation cross-contamination hallucinations.
    ///
    /// When the LLM writes "oppositional defiant disorder (ED)", this gate checks if the
    /// source documents define "ED" as "Oppositional Defiant Disorder". If documents define
    /// "ED" as "Emotional Dysregulation", the expansion is a hallucination — the LLM
    /// cross-contaminated two different abbreviations from the same paper.
    ///
    /// This is ADVISORY (not critical) because:
    /// - Missing abbreviation data (old chunks) shouldn't cause abstention
    /// - It's better to warn and slightly lower confidence than to block the response
    ///
    /// - Parameters:
    ///   - response: The LLM-generated response text
    ///   - chunks: Retrieved source chunks with abbreviation metadata
    /// - Returns: Gate result with confidence reflecting abbreviation faithfulness
    private func runGateF(response: String, chunks: [RetrievedChunk]) -> RAGVerificationResult.GateResult {

        // Step 1: Collect all abbreviation definitions from source chunks
        var sourceAbbreviations: [String: String] = [:]
        for chunk in chunks {
            for (abbr, expansion) in chunk.chunk.metadata.abbreviations {
                if sourceAbbreviations[abbr] == nil {
                    sourceAbbreviations[abbr] = expansion
                }
            }
        }

        // If no abbreviation data available, pass with full confidence
        // (old chunks won't have this metadata — don't penalize)
        guard !sourceAbbreviations.isEmpty else {
            return RAGVerificationResult.GateResult(
                gate: .quoteFaithfulness,
                passed: true,
                confidence: 1.0,
                details: "No abbreviation definitions in source chunks"
            )
        }

        // Step 2: Find abbreviation expansions in the LLM response
        guard let regex = Self.responseAbbreviationRegex else {
            return RAGVerificationResult.GateResult(
                gate: .quoteFaithfulness,
                passed: true,
                confidence: 1.0,
                details: "Regex unavailable"
            )
        }

        let nsResponse = response as NSString
        let fullRange = NSRange(location: 0, length: nsResponse.length)
        let matches = regex.matches(in: response, options: [], range: fullRange)

        var checkedCount = 0
        var faithfulCount = 0
        var violations: [String] = []

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let expansionRange = match.range(at: 1)
            let abbrRange = match.range(at: 2)
            guard expansionRange.location != NSNotFound, abbrRange.location != NSNotFound else { continue }

            let responseExpansion = nsResponse.substring(with: expansionRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let abbr = nsResponse.substring(with: abbrRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            // Check if this abbreviation has a definition in source
            guard let sourceExpansion = sourceAbbreviations[abbr] else { continue }

            checkedCount += 1

            // Compare: do the response's expansion words match the source's expansion words?
            let responseWords = Set(responseExpansion.split(separator: " ").map { String($0).lowercased() }
                .filter { $0.count > 2 })
            let sourceWords = Set(sourceExpansion.lowercased().split(separator: " ").map { String($0) }
                .filter { $0.count > 2 })

            // Calculate Jaccard similarity between expansion word sets
            let intersection = responseWords.intersection(sourceWords)
            let union = responseWords.union(sourceWords)
            let jaccard = union.isEmpty ? 0.0 : Float(intersection.count) / Float(union.count)

            if jaccard >= 0.5 {
                // Good: response expansion matches source definition
                faithfulCount += 1
            } else {
                // BAD: LLM expanded this abbreviation differently than the source defines it
                violations.append("\(abbr): response=\"\(responseExpansion)\" vs source=\"\(sourceExpansion.lowercased())\"")
                Log.warning("[VerificationGates] Gate F: Abbreviation cross-contamination — \(abbr) expanded as \"\(responseExpansion)\" but source defines it as \"\(sourceExpansion)\"", category: .pipeline)
            }
        }

        // No abbreviation expansions found in response — pass
        guard checkedCount > 0 else {
            return RAGVerificationResult.GateResult(
                gate: .quoteFaithfulness,
                passed: true,
                confidence: 1.0,
                details: "No abbreviation expansions in response to verify (\(sourceAbbreviations.count) definitions available)"
            )
        }

        let faithfulness = Float(faithfulCount) / Float(checkedCount)
        // Advisory: only fail if MOST abbreviations are wrong (>50% unfaithful)
        let passed = faithfulness >= 0.50

        let details: String
        if violations.isEmpty {
            details = "All \(checkedCount) abbreviation expansions match source definitions"
        } else {
            details = "\(faithfulCount)/\(checkedCount) faithful. Violations: \(violations.prefix(3).joined(separator: "; "))"
        }

        return RAGVerificationResult.GateResult(
            gate: .quoteFaithfulness,
            passed: passed,
            confidence: faithfulness,
            details: details
        )
    }
    // MARK: - Gate G: Generation Quality

    /// Gate G: Generation Quality — information-theoretic degeneration detector.
    ///
    /// Three sub-checks:
    ///   1. **Bigram Entropy**: Shannon entropy of word bigrams. English prose ~4-6 bits;
    ///      degenerate repetition drops <2.0 bits. Catches ALL repetition universally.
    ///   2. **Unique Word Ratio**: Fraction of distinct words. Quality prose ~40-70%;
    ///      repetitive output drops <25%. Compression-ratio proxy without gzip overhead.
    ///   3. **Trigram Dominance**: Most-frequent 3-word sequence share. If any trigram
    ///      exceeds 15% of all positions AND appears ≥5 times, the text is looping.
    ///
    /// Advisory gate: lowers confidence by up to 0.3 but never triggers abstention.
    /// The LLM may intentionally repeat key terms (e.g. product codes in comparisons),
    /// so we use conservative thresholds.
    private func runGateG(response: String) -> RAGVerificationResult.GateResult {
        let words = response.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        // Short responses pass trivially — not enough signal
        guard words.count >= 25 else {
            return RAGVerificationResult.GateResult(
                gate: .generationQuality,
                passed: true,
                confidence: 1.0,
                details: "Response too short for quality analysis (\(words.count) words)"
            )
        }

        var penalties: [String] = []
        var confidencePenalty: Float = 0.0

        // ── Sub-check 1: Bigram Entropy ──────────────────────────────
        var bigramCounts: [String: Int] = [:]
        var totalBigrams = 0
        for i in 0..<(words.count - 1) {
            let bigram = "\(words[i]) \(words[i + 1])"
            bigramCounts[bigram, default: 0] += 1
            totalBigrams += 1
        }

        if totalBigrams > 0 {
            var entropy: Double = 0.0
            let total = Double(totalBigrams)
            for (_, count) in bigramCounts {
                let p = Double(count) / total
                if p > 0 { entropy -= p * log2(p) }
            }
            // Scale threshold for short responses
            let threshold: Double = words.count < 60 ? 1.5 : 2.0
            if entropy < threshold {
                penalties.append("low_entropy(\(String(format: "%.2f", entropy))bits)")
                confidencePenalty += 0.15
            }
        }

        // ── Sub-check 2: Unique Word Ratio ───────────────────────────
        let uniqueRatio = Float(Set(words).count) / Float(words.count)
        if uniqueRatio < 0.25 {
            penalties.append("low_diversity(\(String(format: "%.0f", uniqueRatio * 100))%)")
            confidencePenalty += 0.10
        }

        // ── Sub-check 3: Trigram Dominance ───────────────────────────
        if words.count >= 20 {
            var trigramCounts: [String: Int] = [:]
            for i in 0..<(words.count - 2) {
                let trigram = "\(words[i]) \(words[i + 1]) \(words[i + 2])"
                trigramCounts[trigram, default: 0] += 1
            }
            let totalTrigrams = words.count - 2
            if let topCount = trigramCounts.values.max(),
               topCount >= 5,
               Float(topCount) / Float(totalTrigrams) > 0.15 {
                penalties.append("trigram_dominance(\(topCount)/\(totalTrigrams))")
                confidencePenalty += 0.10
            }
        }

        let confidence = max(0.0, 1.0 - confidencePenalty)
        // Pass if total penalty < 0.20 (single mild issue is OK)
        let passed = confidencePenalty < 0.20

        let details: String
        if penalties.isEmpty {
            details = "Generation quality OK: entropy=\(String(format: "%.1f", { () -> Double in var e: Double = 0; let t = Double(totalBigrams); for (_, c) in bigramCounts { let p = Double(c)/t; if p > 0 { e -= p*log2(p) } }; return e }()))bits, unique=\(String(format: "%.0f", uniqueRatio * 100))%"
        } else {
            details = "Quality issues: \(penalties.joined(separator: ", "))"
        }

        if !passed {
            Log.warning("[VerificationGates] Gate G FAILED: \(details)", category: .pipeline)
        }

        return RAGVerificationResult.GateResult(
            gate: .generationQuality,
            passed: passed,
            confidence: confidence,
            details: details
        )
    }

    /// Hardware-accelerated via vDSP — ~10x faster than scalar loop for 384-dim vectors.
    /// Matches the Accelerate-based implementation used in RAGEngine and HybridSearchService.
    private func vectorCosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &magA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &magB, vDSP_Length(b.count))

        let magnitude = sqrt(magA) * sqrt(magB)
        guard magnitude > 1e-9 else { return 0.0 }
        return dot / magnitude
    }

    // MARK: - Helper Methods

    /// Detect if query is about a "touchy" topic requiring stricter thresholds
    private func detectTouchyQuery(_ query: String) -> Bool {
        let queryLower = query.lowercased()
        return config.touchyCategories.contains { queryLower.contains($0) }
    }

    /// Extract factual claims from response text
    private func extractClaims(from text: String) -> [String] {
        // Split into sentences
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var claims: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Filter to sentences that contain facts (numbers, proper nouns, specific terms)
            if containsFactualContent(sentence) {
                claims.append(sentence)
            }
            return true
        }

        return claims
    }

    /// Check if sentence contains factual content worth verifying
    private func containsFactualContent(_ sentence: String) -> Bool {
        // Contains numbers
        if sentence.rangeOfCharacter(from: .decimalDigits) != nil { return true }

        // Contains measurement units
        let units = ["mg", "kg", "ml", "L", "mm", "cm", "m", "%", "psi", "kPa", "°"]
        if units.contains(where: { sentence.contains($0) }) { return true }

        // Contains specific patterns (codes, versions, etc.)
        let specificPatterns = ["version", "model", "type", "grade", "class", "level"]
        if specificPatterns.contains(where: { sentence.lowercased().contains($0) }) { return true }

        return false
    }

    /// Check if claim text appears in corpus (fuzzy matching)
    private func isClaimCovered(claim: String, inCorpus corpus: String) -> Bool {
        // Extract key terms from claim (nouns, numbers, codes)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = claim

        var keyTerms: [String] = []
        tagger.enumerateTags(in: claim.startIndex..<claim.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, tag == .noun || tag == .number {
                let word = String(claim[range]).lowercased()
                if word.count >= 3 {
                    keyTerms.append(word)
                }
            }
            return true
        }

        // Also extract numbers
        keyTerms.append(contentsOf: extractNumbers(from: claim))

        guard !keyTerms.isEmpty else { return true }  // No key terms = vacuously covered

        // Require majority of key terms to appear in corpus
        let foundCount = keyTerms.filter { corpus.contains($0) }.count
        return Float(foundCount) / Float(keyTerms.count) >= 0.5
    }

    /// Extract numbers from text (including decimals, fractions, percentages, spec codes)
    private func extractNumbers(from text: String) -> [String] {
        // Pattern matches: grade codes (0W-30, A2-70), integers, decimals, fractions, percentages
        let patterns = [
            #"[A-Z0-9]+[-][A-Z0-9]+"#,  // Grade/spec codes: 0W-30, ISO-9001, A2-70
            #"\b\d+(?:\.\d+)?(?:/\d+)?(?:\s*%)?(?:\s*(?:mg|kg|ml|L|mm|cm|m|psi|kPa))?\b"#  // Numbers with units
        ]

        var allMatches: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    allMatches.append(String(text[range]))
                }
            }
        }
        return allMatches
    }

    /// Normalize number for comparison (strip units, standardize format)
    private func normalizeNumber(_ number: String) -> String {
        // Remove units and whitespace
        let cleaned = number.replacingOccurrences(of: #"\s*(mg|kg|ml|L|mm|cm|m|psi|kPa|%)"#, with: "", options: .regularExpression)
        // Normalize decimal format
        if let doubleValue = Double(cleaned) {
            return String(format: "%.2f", doubleValue)
        }
        return cleaned
    }

    /// Detect contradictions in retrieved chunks
    /// ULTRA CONSERVATIVE: Only flag when SAME measurement type has conflicting values
    /// Documents have hundreds of different numbers (page refs, part numbers, specs) - NOT contradictions!
    private func detectContradictions(in chunks: [RetrievedChunk]) -> [String] {
        var contradictions: [String] = []

        // Look for negation patterns near similar content
        let negationIndicators = ["not", "never", "no longer", "unlike", "instead of", "rather than", "contrary to"]

        // ULTRA CONSERVATIVE: Only look for explicit "X is Y" vs "X is not Y" patterns
        // Do NOT flag different numbers as contradictions - car manuals have MANY different specs
        // Examples that are NOT contradictions:
        //   - MS-12991 (standard) vs 2.4L (engine size) vs 532 (page number)
        //   - 5W-40 (1.4L engine) vs 0W-20 (2.4L engine) - different engines!
        //   - Front tire 35 PSI vs Rear tire 32 PSI - different locations!

        // Only flag when negation DIRECTLY contradicts a previous positive claim
        for i in 0..<chunks.count {
            for j in (i+1)..<chunks.count {
                let content1 = chunks[i].chunk.content.lowercased()
                let content2 = chunks[j].chunk.content.lowercased()

                for indicator in negationIndicators {
                    // Check for pattern: "X is Y" in chunk1 vs "X is not Y" in chunk2
                    if content2.contains(indicator) {
                        // Extract the negated claim context (5 words around negation)
                        if let negRange = content2.range(of: indicator) {
                            let startIdx = content2.index(negRange.lowerBound, offsetBy: -30, limitedBy: content2.startIndex) ?? content2.startIndex
                            let endIdx = content2.index(negRange.upperBound, offsetBy: 30, limitedBy: content2.endIndex) ?? content2.endIndex
                            let negContext = String(content2[startIdx..<endIdx])

                            // Check if chunk1 has the opposite claim (same subject, no negation)
                            let negatedTerms = Set(negContext.split(separator: " ").map { String($0) }.filter { $0.count > 5 && $0 != indicator })
                            let terms1 = Set(content1.split(separator: " ").map { String($0) }.filter { $0.count > 5 })
                            let overlap = negatedTerms.intersection(terms1)

                            // Require VERY high overlap (7+ shared terms) AND no negation in chunk1
                            let hasNegationInChunk1 = negationIndicators.contains { content1.contains($0) }
                            if overlap.count >= 7 && !hasNegationInChunk1 {
                                contradictions.append("Possible contradiction near '\(indicator)'")
                                break
                            }
                        }
                    }
                }
            }
        }

        // REMOVED: The numeric comparison logic that caused false positives
        // Different numbers for different specs are NOT contradictions.
        // Only explicit negation patterns ("is" vs "is not") warrant contradiction flags.

        return Array(Set(contradictions))  // Deduplicate
    }

    /// Find keywords shared across multiple contexts
    private func findSharedKeywords(_ contexts: [String]) -> Set<String> {
        guard contexts.count >= 2 else { return [] }
        let wordSets = contexts.map { context -> Set<String> in
            Set(context.lowercased().split(separator: " ")
                .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 4 })
        }
        return wordSets.reduce(wordSets[0]) { $0.intersection($1) }
    }
}

// MARK: - Abstention Response

extension VerificationGateService {

    /// Generate an abstention response when verification fails
    nonisolated func generateAbstentionResponse(
        query: String,
        verificationResult: RAGVerificationResult,
        retrievedChunks: [RetrievedChunk]
    ) -> String {
        let failedGates = verificationResult.failedGates

        if failedGates.contains(.retrievalConfidence) {
            return "I couldn't find sufficiently relevant information in the documents to answer this question confidently. The retrieved content may not directly address your query about: \"\(query.prefix(50))...\""
        }

        if failedGates.contains(.numericSanity) {
            return "I found some relevant information, but I'm not confident about the specific numbers or values. Please verify the following information directly in the source documents."
        }

        if failedGates.contains(.semanticGrounding) {
            return "My response doesn't appear to be well-supported by the source documents. The answer to your question may not be present in the available materials. Please try rephrasing or check the documents directly."
        }

        if failedGates.contains(.quoteFaithfulness) {
            return "I found potential inaccuracies in how I expanded abbreviations or attributed information to source documents. The response may mix up similar terms. Please verify abbreviation definitions against the original documents."
        }

        if failedGates.contains(.generationQuality) {
            return "The generated response appears to contain repetitive or low-quality output. This may happen when source documents contain many similar entries. Please try rephrasing your question to get a more focused answer."
        }

        if failedGates.contains(.contradictionSweep) {
            return "I found potentially contradicting information in the documents. Here are the relevant passages - please review them to determine which applies to your situation."
        }

        // Generic abstention
        return "I'm not confident enough in my answer to provide it. The verification checks suggest the response may not be fully grounded in the source documents."
    }
}
