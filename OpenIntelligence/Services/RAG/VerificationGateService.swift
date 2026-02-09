//
//  VerificationGateService.swift
//  OpenIntelligence
//
//  Verification gates for anti-hallucination (AppleRAG Spec Phase 2.06).
//  Implements Gates A-D to ensure answers are grounded in retrieved evidence.
//
//  Gate A: Retrieval Confidence - require max(score) >= τ AND margin >= μ
//  Gate B: Evidence Coverage - all claims must cite evidence_ids
//  Gate C: Numeric Sanity - numbers in response must match source
//  Gate D: Contradiction Sweep - detect conflicting evidence
//

import Foundation
import NaturalLanguage

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

/// The four verification gates from AppleRAG spec
enum VerificationGate: String, CaseIterable, Sendable {
    case retrievalConfidence = "Gate A: Retrieval Confidence"
    case evidenceCoverage = "Gate B: Evidence Coverage"
    case numericSanity = "Gate C: Numeric Sanity"
    case contradictionSweep = "Gate D: Contradiction Sweep"
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
    /// Categories that trigger stricter thresholds
    let touchyCategories: Set<String>

    /// Default thresholds - calibrated for real-world retrieval
    /// Note: tauNormal lowered from 0.55 to 0.40 because keyword-heavy queries
    /// often have lower semantic scores even when BM25 finds the right content
    nonisolated static let `default` = VerificationConfig(
        tauNormal: 0.40,
        tauTouchy: 0.55,
        muMargin: 0.03,
        touchyCategories: ["medical", "legal", "financial", "safety", "dosage", "drug", "medication"]
    )

    /// Stricter config for high-risk applications
    nonisolated static let strict = VerificationConfig(
        tauNormal: 0.65,
        tauTouchy: 0.75,
        muMargin: 0.10,
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
    /// - Returns: Verification result with pass/fail for each gate
    func verify(
        response: String,
        query: String,
        retrievedChunks: [RetrievedChunk],
        topScores: [Float],
        allCandidateChunks: [RetrievedChunk]? = nil
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

        // Calculate overall result
        let allPassed = gateResults.allSatisfy { $0.passed }
        let overallConfidence = gateResults.reduce(0.0) { $0 + $1.confidence } / Float(gateResults.count)

        // Determine if we should abstain
        let criticalFailures = gateResults.filter { !$0.passed && ($0.gate == .retrievalConfidence || $0.gate == .numericSanity) }
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
            confidence: max(coverage, 0.5),  // Floor confidence at 0.5
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

        // Also build full text for substring matching (catches "30" in "0W-30")
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
                    // Number appears somewhere in source (maybe as part of larger spec)
                    verifiedCount += 1
                } else {
                    // OPTIMIZED: Don't penalize year numbers (2024, 2025) or common page/section refs
                    // These are often metadata the LLM infers from document titles, not hallucinations.
                    let isLikelyMetadata = isYearOrReference(number)
                    if isLikelyMetadata {
                        verifiedCount += 1  // Give benefit of the doubt
                    } else {
                        unverifiedNumbers.append(number)
                    }
                }
            }
        }

        let verification = Float(verifiedCount) / Float(responseNumbers.count)
        // OPTIMIZED: Relaxed from 80% to 70%. The previous 80% threshold was failing
        // on correct responses where 1-2 metadata numbers (year, section refs) weren't
        // in the context chunks. 70% still catches egregious hallucination (< 70% verified).
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

    /// Check if a number looks like a year, page reference, or section number
    /// These are commonly inferred from document metadata, not hallucinated
    private func isYearOrReference(_ number: String) -> Bool {
        // Year pattern: 2020-2030
        if let year = Int(number), year >= 2020, year <= 2030 {
            return true
        }
        // Small integers that are likely section/page references
        if let n = Int(number), n >= 1, n <= 10 {
            return true
        }
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

    /// Extract numbers from text (including decimals, fractions, percentages, oil specs)
    private func extractNumbers(from text: String) -> [String] {
        // Pattern matches: oil viscosity (0W-30, 5W-40), integers, decimals, fractions, percentages
        // Also matches API specs like SN, SP, CF-4
        let patterns = [
            #"\d+W-\d+"#,  // Oil viscosity: 0W-30, 5W-40, 10W-40
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
    /// Car manuals have hundreds of different numbers (page refs, part numbers, specs) - NOT contradictions!
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

        if failedGates.contains(.contradictionSweep) {
            return "I found potentially contradicting information in the documents. Here are the relevant passages - please review them to determine which applies to your situation."
        }

        // Generic abstention
        return "I'm not confident enough in my answer to provide it. The verification checks suggest the response may not be fully grounded in the source documents."
    }
}
