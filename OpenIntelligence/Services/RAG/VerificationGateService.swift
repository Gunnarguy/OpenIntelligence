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
    var failedGates: [VerificationGate] {
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

    /// Default thresholds from AppleRAG spec
    nonisolated static let `default` = VerificationConfig(
        tauNormal: 0.55,
        tauTouchy: 0.65,
        muMargin: 0.05,
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
    ///   - retrievedChunks: Chunks used to generate the response
    ///   - topScores: Relevance scores from reranking (sorted descending)
    /// - Returns: Verification result with pass/fail for each gate
    func verify(
        response: String,
        query: String,
        retrievedChunks: [RetrievedChunk],
        topScores: [Float]
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

        // Gate C: Numeric Sanity
        let gateC = await runGateC(response: response, chunks: retrievedChunks)
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
    /// Require max(chunk_scores) >= τ AND margin between top-1 and top-2 >= μ
    private func runGateA(topScores: [Float], tau: Float) async -> RAGVerificationResult.GateResult {
        guard let maxScore = topScores.first else {
            return RAGVerificationResult.GateResult(
                gate: .retrievalConfidence,
                passed: false,
                confidence: 0,
                details: "No retrieval scores available"
            )
        }

        let passesThreshold = maxScore >= tau

        // Check margin if we have at least 2 scores
        let passesMargin: Bool
        let margin: Float
        if topScores.count >= 2 {
            margin = topScores[0] - topScores[1]
            passesMargin = margin >= config.muMargin
        } else {
            margin = 1.0  // Single result, maximum margin
            passesMargin = true
        }

        let passed = passesThreshold && passesMargin
        let details = "maxScore=\(String(format: "%.3f", maxScore)) (τ=\(String(format: "%.2f", tau))), margin=\(String(format: "%.3f", margin)) (μ=\(String(format: "%.2f", config.muMargin)))"

        return RAGVerificationResult.GateResult(
            gate: .retrievalConfidence,
            passed: passed,
            confidence: min(maxScore, 1.0),
            details: details
        )
    }

    /// Gate B: Evidence Coverage
    /// Check that key claims in response can be traced to retrieved chunks
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

        // Build corpus from chunks
        let corpus = chunks.map { $0.chunk.content.lowercased() }.joined(separator: " ")

        // Check coverage of each claim
        var coveredCount = 0
        for claim in claims {
            if isClaimCovered(claim: claim, inCorpus: corpus) {
                coveredCount += 1
            }
        }

        let coverage = Float(coveredCount) / Float(claims.count)
        let passed = coverage >= 0.7  // Require 70% of claims to be grounded

        return RAGVerificationResult.GateResult(
            gate: .evidenceCoverage,
            passed: passed,
            confidence: coverage,
            details: "\(coveredCount)/\(claims.count) claims covered (\(Int(coverage * 100))%)"
        )
    }

    /// Gate C: Numeric Sanity
    /// If response contains numbers, verify they appear in source documents
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

        // Extract numbers from source chunks
        let sourceNumbers = Set(chunks.flatMap { extractNumbers(from: $0.chunk.content) })

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
                } else {
                    unverifiedNumbers.append(number)
                }
            }
        }

        let verification = Float(verifiedCount) / Float(responseNumbers.count)
        let passed = verification >= 0.8  // Require 80% of numbers to be verified

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

    /// Extract numbers from text (including decimals, fractions, percentages)
    private func extractNumbers(from text: String) -> [String] {
        // Pattern matches: integers, decimals, fractions, percentages
        let pattern = #"\b\d+(?:\.\d+)?(?:/\d+)?(?:\s*%)?(?:\s*(?:mg|kg|ml|L|mm|cm|m|psi|kPa))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
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
    private func detectContradictions(in chunks: [RetrievedChunk]) -> [String] {
        var contradictions: [String] = []

        // Look for negation patterns near similar content
        let negationIndicators = ["not", "never", "no longer", "unlike", "however", "but", "instead", "rather than", "contrary"]

        // Build a simple keyword→value map from chunks
        var factMap: [String: Set<String>] = [:]

        for chunk in chunks {
            let sentences = chunk.chunk.content.components(separatedBy: ". ")
            for sentence in sentences {
                // Extract subject-value patterns (simplified)
                let numbers = extractNumbers(from: sentence)
                for number in numbers {
                    // Use first noun as key
                    let tagger = NLTagger(tagSchemes: [.lexicalClass])
                    tagger.string = sentence
                    var firstNoun: String?
                    tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
                        if let tag = tag, tag == .noun, firstNoun == nil {
                            firstNoun = String(sentence[range]).lowercased()
                            return false
                        }
                        return true
                    }

                    if let key = firstNoun {
                        factMap[key, default: []].insert(number)
                    }
                }
            }
        }

        // Check for keys with multiple different values
        for (key, values) in factMap {
            if values.count > 1 {
                // Normalize and compare
                let normalizedValues = Set(values.map { normalizeNumber($0) })
                if normalizedValues.count > 1 {
                    contradictions.append("\(key): \(values.joined(separator: " vs "))")
                }
            }
        }

        // Also check for explicit negation patterns
        for i in 0..<chunks.count {
            for j in (i+1)..<chunks.count {
                let content1 = chunks[i].chunk.content.lowercased()
                let content2 = chunks[j].chunk.content.lowercased()

                for indicator in negationIndicators {
                    if content2.contains(indicator) {
                        // Very rough check - if they share key terms but one has negation
                        let terms1 = Set(content1.split(separator: " ").map { String($0) }.filter { $0.count > 4 })
                        let terms2 = Set(content2.split(separator: " ").map { String($0) }.filter { $0.count > 4 })
                        let overlap = terms1.intersection(terms2)
                        if overlap.count >= 3 {
                            contradictions.append("Possible contradiction near '\(indicator)' in chunks \(i) and \(j)")
                            break
                        }
                    }
                }
            }
        }

        return Array(Set(contradictions))  // Deduplicate
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
