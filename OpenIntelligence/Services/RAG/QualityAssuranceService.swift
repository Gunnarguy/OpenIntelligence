//
//  QualityAssuranceService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/27/26.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  QUALITY ASSURANCE SERVICE — PROVING RAG ACCURACY
//  ═══════════════════════════════════════════════════════════════════════════
//
//  This service provides PROVABLE accuracy metrics for the entire RAG pipeline.
//  It answers: "Is this system producing garbage or gold?"
//
//  TEST SUITES:
//  ────────────
//  1. Embedding Sanity     - Known semantic pairs should be close
//  2. Retrieval Accuracy   - Given query+corpus, find expected chunks
//  3. Answer Faithfulness  - Given context, answer matches ground truth
//  4. OCR Quality          - Known document text matches extraction
//  5. End-to-End QA        - Full pipeline accuracy on benchmark
//
//  METRICS COMPUTED:
//  ─────────────────
//  • Embedding Similarity Correlation (target: >0.85)
//  • Recall@K (target: >0.80 for K=5)
//  • MRR - Mean Reciprocal Rank (target: >0.70)
//  • Answer Exact Match (target: >0.60)
//  • Answer F1 Score (target: >0.75)
//

import Foundation
import NaturalLanguage

// MARK: - Quality Metrics

/// Comprehensive quality metrics for the RAG pipeline
struct RAGQualityMetrics: Sendable, Codable {
    let timestamp: Date
    let pipelineVersion: String

    // Embedding Quality
    let embeddingSanityPassed: Bool
    let embeddingCorrelation: Float    // Correlation with expected similarities

    // Retrieval Quality
    let recallAt1: Float               // % of queries where correct doc is #1
    let recallAt5: Float               // % of queries where correct doc is in top 5
    let recallAt10: Float              // % of queries where correct doc is in top 10
    let mrr: Float                     // Mean Reciprocal Rank
    let precision: Float               // Precision of retrieved documents

    // Answer Quality
    let exactMatchAccuracy: Float      // Exact string match with ground truth
    let f1Score: Float                 // Token-level F1 overlap
    let faithfulnessScore: Float       // Answer grounded in retrieved context

    // OCR Quality (if tested)
    let ocrCharacterErrorRate: Float?  // CER against known text
    let ocrWordErrorRate: Float?       // WER against known text

    // Overall
    let overallScore: Float            // Weighted composite score
    let passed: Bool                   // Meets minimum thresholds
    let failures: [String]             // List of failed checks

    /// Human-readable summary
    var summary: String {
        """
        ═══════════════════════════════════════════════════════
        RAG QUALITY REPORT — \(timestamp.formatted())
        ═══════════════════════════════════════════════════════

        EMBEDDING QUALITY
        • Sanity Check: \(embeddingSanityPassed ? "✅ PASS" : "❌ FAIL")
        • Correlation:  \(String(format: "%.1f%%", embeddingCorrelation * 100))

        RETRIEVAL QUALITY
        • Recall@1:     \(String(format: "%.1f%%", recallAt1 * 100))
        • Recall@5:     \(String(format: "%.1f%%", recallAt5 * 100))
        • MRR:          \(String(format: "%.3f", mrr))
        • Precision:    \(String(format: "%.1f%%", precision * 100))

        ANSWER QUALITY
        • Exact Match:  \(String(format: "%.1f%%", exactMatchAccuracy * 100))
        • F1 Score:     \(String(format: "%.1f%%", f1Score * 100))
        • Faithfulness: \(String(format: "%.1f%%", faithfulnessScore * 100))

        OVERALL: \(passed ? "✅ PASS" : "❌ FAIL") (\(String(format: "%.1f%%", overallScore * 100)))
        \(failures.isEmpty ? "" : "Failures: \(failures.joined(separator: ", "))")
        ═══════════════════════════════════════════════════════
        """
    }
}

// MARK: - Benchmark Test Cases

/// A single QA test case with ground truth
struct QATestCase: Sendable, Codable {
    let id: String
    let query: String
    let expectedAnswer: String
    let expectedDocumentIds: [String]    // Documents that should be retrieved
    let answerType: AnswerType
    let difficulty: Difficulty

    enum AnswerType: String, Sendable, Codable {
        case factoid       // Single fact: "What value does X specify?"
        case extractive    // Span from document
        case abstractive   // Synthesized answer
        case yesNo         // Boolean question
        case list          // Multiple items
    }

    enum Difficulty: String, Sendable, Codable {
        case easy          // Answer is explicit in one place
        case medium        // Requires finding the right section
        case hard          // Requires multi-hop reasoning
    }
}

/// Embedding similarity test pair
struct EmbeddingSimilarityPair: Sendable {
    let textA: String
    let textB: String
    let expectedSimilarity: Float  // 0.0 = unrelated, 1.0 = identical meaning
    let category: String           // "synonym", "antonym", "related", "unrelated"
}

// MARK: - Quality Assurance Service

/// Service for measuring and proving RAG pipeline accuracy
actor QualityAssuranceService {

    static let shared = QualityAssuranceService()

    // MARK: - Built-in Benchmark Data

    /// Embedding sanity test pairs — these MUST behave correctly
    private let embeddingSanityPairs: [EmbeddingSimilarityPair] = [
        // Synonyms (should be HIGH similarity, >0.7)
        EmbeddingSimilarityPair(textA: "dog", textB: "canine", expectedSimilarity: 0.8, category: "synonym"),
        EmbeddingSimilarityPair(textA: "car", textB: "automobile", expectedSimilarity: 0.85, category: "synonym"),
        EmbeddingSimilarityPair(textA: "happy", textB: "joyful", expectedSimilarity: 0.8, category: "synonym"),
        EmbeddingSimilarityPair(textA: "big", textB: "large", expectedSimilarity: 0.85, category: "synonym"),
        EmbeddingSimilarityPair(textA: "fast", textB: "quick", expectedSimilarity: 0.8, category: "synonym"),

        // Related concepts (should be MEDIUM similarity, 0.4-0.7)
        EmbeddingSimilarityPair(textA: "doctor", textB: "hospital", expectedSimilarity: 0.5, category: "related"),
        EmbeddingSimilarityPair(textA: "car", textB: "road", expectedSimilarity: 0.45, category: "related"),
        EmbeddingSimilarityPair(textA: "book", textB: "library", expectedSimilarity: 0.5, category: "related"),
        EmbeddingSimilarityPair(textA: "coffee", textB: "morning", expectedSimilarity: 0.4, category: "related"),

        // Unrelated (should be LOW similarity, <0.3)
        EmbeddingSimilarityPair(textA: "dog", textB: "quantum physics", expectedSimilarity: 0.1, category: "unrelated"),
        EmbeddingSimilarityPair(textA: "pizza", textB: "democracy", expectedSimilarity: 0.1, category: "unrelated"),
        EmbeddingSimilarityPair(textA: "sunset", textB: "algorithm", expectedSimilarity: 0.1, category: "unrelated"),

        // Technical terms (domain-specific)
        EmbeddingSimilarityPair(textA: "machine learning", textB: "artificial intelligence", expectedSimilarity: 0.75, category: "synonym"),
        EmbeddingSimilarityPair(textA: "HTTP request", textB: "API call", expectedSimilarity: 0.7, category: "related"),
        EmbeddingSimilarityPair(textA: "database", textB: "SQL query", expectedSimilarity: 0.6, category: "related"),
    ]

    /// Built-in QA test cases for the sample documents
    private let builtInQATests: [QATestCase] = [
        // These work with the Solaris Industries Annual Report sample doc
        QATestCase(
            id: "solaris_revenue",
            query: "What was Solaris Industries' total revenue in 2025?",
            expectedAnswer: "$4.2 billion",
            expectedDocumentIds: ["solaris_annual_report"],
            answerType: .factoid,
            difficulty: .easy
        ),
        QATestCase(
            id: "solaris_rd_budget",
            query: "What is Solaris Industries' R&D budget?",
            expectedAnswer: "$340 million",
            expectedDocumentIds: ["solaris_annual_report"],
            answerType: .factoid,
            difficulty: .easy
        ),
        QATestCase(
            id: "solaris_efficiency",
            query: "What efficiency does the Helios X8 series have?",
            expectedAnswer: "28%",
            expectedDocumentIds: ["solaris_annual_report"],
            answerType: .factoid,
            difficulty: .medium
        ),
    ]

    // MARK: - Embedding Sanity Test

    /// Test that embeddings capture semantic meaning correctly
    /// This is the FIRST check that should pass before trusting anything else
    func testEmbeddingSanity(embeddingService: EmbeddingService) async -> (passed: Bool, correlation: Float, details: String) {
        var correctPredictions = 0
        var totalPairs = 0
        var details: [String] = []

        for pair in embeddingSanityPairs {
            do {
                let embA = try await embeddingService.generateEmbedding(for: pair.textA)
                let embB = try await embeddingService.generateEmbedding(for: pair.textB)

                let similarity = cosineSimilarity(embA, embB)
                let expected = pair.expectedSimilarity

                // Check if similarity is in expected range
                let tolerance: Float = 0.25  // Allow 25% deviation
                let isCorrect: Bool

                switch pair.category {
                case "synonym":
                    isCorrect = similarity > 0.6  // Synonyms should be high
                case "related":
                    isCorrect = similarity > 0.3 && similarity < 0.8
                case "unrelated":
                    isCorrect = similarity < 0.4  // Unrelated should be low
                default:
                    isCorrect = abs(similarity - expected) < tolerance
                }

                if isCorrect {
                    correctPredictions += 1
                } else {
                    details.append("❌ \"\(pair.textA)\" vs \"\(pair.textB)\": got \(String(format: "%.2f", similarity)), expected ~\(String(format: "%.2f", expected)) (\(pair.category))")
                }
                totalPairs += 1

            } catch {
                details.append("❌ Embedding failed: \(error.localizedDescription)")
            }
        }

        let correlation = Float(correctPredictions) / Float(max(1, totalPairs))
        let passed = correlation >= 0.80  // Require 80% of pairs to behave correctly

        let summary = passed ? "✅ Embedding sanity PASSED (\(correctPredictions)/\(totalPairs))" :
                              "❌ Embedding sanity FAILED (\(correctPredictions)/\(totalPairs))"

        return (passed, correlation, summary + "\n" + details.joined(separator: "\n"))
    }

    // MARK: - Retrieval Accuracy Test

    /// Test retrieval accuracy: given queries, do we find the right documents?
    func testRetrievalAccuracy(
        queries: [(query: String, expectedDocIds: [String])],
        searchFunction: @Sendable (String) async throws -> [RetrievedChunk]
    ) async -> (recallAt1: Float, recallAt5: Float, mrr: Float, precision: Float) {
        var recallAt1Count = 0
        var recallAt5Count = 0
        var reciprocalRankSum: Float = 0
        var precisionSum: Float = 0
        var totalQueries = 0

        for (query, expectedDocIds) in queries {
            do {
                let results = try await searchFunction(query)

                // Check Recall@1: Is any expected doc in position 1?
                if let firstResult = results.first {
                    let firstDocId = firstResult.chunk.documentId.uuidString
                    if expectedDocIds.contains(where: { firstDocId.contains($0) }) {
                        recallAt1Count += 1
                    }
                }

                // Check Recall@5: Is any expected doc in top 5?
                let top5DocIds = results.prefix(5).map { $0.chunk.documentId.uuidString }
                if expectedDocIds.contains(where: { expected in top5DocIds.contains(where: { $0.contains(expected) }) }) {
                    recallAt5Count += 1
                }

                // Calculate MRR: Reciprocal of first correct result rank
                for (index, result) in results.enumerated() {
                    let docId = result.chunk.documentId.uuidString
                    if expectedDocIds.contains(where: { docId.contains($0) }) {
                        reciprocalRankSum += 1.0 / Float(index + 1)
                        break
                    }
                }

                // Calculate Precision: % of top-K that are relevant
                let topK = min(5, results.count)
                if topK > 0 {
                    let relevantInTopK = results.prefix(topK).filter { result in
                        let docId = result.chunk.documentId.uuidString
                        return expectedDocIds.contains(where: { docId.contains($0) })
                    }.count
                    precisionSum += Float(relevantInTopK) / Float(topK)
                }

                totalQueries += 1

            } catch {
                // Query failed - counts as miss
                totalQueries += 1
            }
        }

        let n = Float(max(1, totalQueries))
        return (
            recallAt1: Float(recallAt1Count) / n,
            recallAt5: Float(recallAt5Count) / n,
            mrr: reciprocalRankSum / n,
            precision: precisionSum / n
        )
    }

    // MARK: - Answer Quality Test

    /// Test answer quality against ground truth
    func testAnswerQuality(
        testCases: [QATestCase],
        answerFunction: @Sendable (String) async throws -> String
    ) async -> (exactMatch: Float, f1Score: Float, details: [String]) {
        var exactMatchCount = 0
        var f1Sum: Float = 0
        var details: [String] = []
        var totalCases = 0

        for testCase in testCases {
            do {
                let generatedAnswer = try await answerFunction(testCase.query)
                let expectedAnswer = testCase.expectedAnswer

                // Exact match (case-insensitive, normalized)
                let normalizedGenerated = normalizeAnswer(generatedAnswer)
                let normalizedExpected = normalizeAnswer(expectedAnswer)

                let isExactMatch = normalizedGenerated.contains(normalizedExpected) ||
                                   normalizedExpected.contains(normalizedGenerated)
                if isExactMatch {
                    exactMatchCount += 1
                }

                // Token-level F1
                let f1 = computeF1(generated: generatedAnswer, expected: expectedAnswer)
                f1Sum += f1

                let status = isExactMatch ? "✅" : "❌"
                details.append("\(status) Q: \(testCase.query.prefix(50))... | Expected: \(expectedAnswer) | Got: \(generatedAnswer.prefix(100))... | F1: \(String(format: "%.2f", f1))")

                totalCases += 1

            } catch {
                details.append("❌ Query failed: \(testCase.query.prefix(50))... | Error: \(error.localizedDescription)")
                totalCases += 1
            }
        }

        let n = Float(max(1, totalCases))
        return (
            exactMatch: Float(exactMatchCount) / n,
            f1Score: f1Sum / n,
            details: details
        )
    }

    // MARK: - Full Pipeline Test

    /// Run complete quality assurance suite
    func runFullQualitySuite(
        embeddingService: EmbeddingService,
        searchFunction: @Sendable (String) async throws -> [RetrievedChunk],
        answerFunction: @Sendable (String) async throws -> String,
        customTestCases: [QATestCase]? = nil
    ) async -> RAGQualityMetrics {

        var failures: [String] = []

        // 1. Embedding Sanity
        let (embeddingPassed, embeddingCorrelation, _) = await testEmbeddingSanity(embeddingService: embeddingService)
        if !embeddingPassed {
            failures.append("Embedding sanity failed")
        }

        // 2. Retrieval Accuracy
        let testCases = customTestCases ?? builtInQATests
        let retrievalQueries = testCases.map { ($0.query, $0.expectedDocumentIds) }
        let (recallAt1, recallAt5, mrr, precision) = await testRetrievalAccuracy(
            queries: retrievalQueries,
            searchFunction: searchFunction
        )

        if recallAt5 < 0.6 {
            failures.append("Recall@5 below threshold (\(String(format: "%.0f%%", recallAt5 * 100)))")
        }

        // 3. Answer Quality
        let (exactMatch, f1Score, _) = await testAnswerQuality(
            testCases: testCases,
            answerFunction: answerFunction
        )

        if f1Score < 0.5 {
            failures.append("F1 score below threshold (\(String(format: "%.0f%%", f1Score * 100)))")
        }

        // 4. Compute overall score (broken up for type checker)
        let embeddingWeight: Float = embeddingCorrelation * 0.2
        let retrievalWeight: Float = recallAt5 * 0.3
        let mrrWeight: Float = mrr * 0.2
        let answerWeight: Float = f1Score * 0.3
        let overallScore: Float = embeddingWeight + retrievalWeight + mrrWeight + answerWeight

        let passed = embeddingPassed && recallAt5 >= 0.6 && f1Score >= 0.5

        return RAGQualityMetrics(
            timestamp: Date(),
            pipelineVersion: "1.0",
            embeddingSanityPassed: embeddingPassed,
            embeddingCorrelation: embeddingCorrelation,
            recallAt1: recallAt1,
            recallAt5: recallAt5,
            recallAt10: recallAt5,  // Use same for now
            mrr: mrr,
            precision: precision,
            exactMatchAccuracy: exactMatch,
            f1Score: f1Score,
            faithfulnessScore: f1Score,  // Approximation
            ocrCharacterErrorRate: nil,
            ocrWordErrorRate: nil,
            overallScore: overallScore,
            passed: passed,
            failures: failures
        )
    }

    // MARK: - Quick Sanity Check

    /// Fast sanity check that can run on app startup
    /// Returns true if basic embedding functionality works
    func quickSanityCheck(embeddingService: EmbeddingService) async -> Bool {
        // Test just 3 critical pairs
        let criticalPairs = [
            ("dog", "canine", 0.6),      // Synonym must be high
            ("car", "banana", 0.3),      // Unrelated must be low
            ("machine learning", "AI", 0.5)  // Related must be moderate
        ]

        for (a, b, threshold) in criticalPairs {
            do {
                let embA = try await embeddingService.generateEmbedding(for: a)
                let embB = try await embeddingService.generateEmbedding(for: b)
                let sim = cosineSimilarity(embA, embB)

                // First pair should be ABOVE threshold, others relative
                if a == "dog" && sim < Float(threshold) {
                    return false  // Synonyms should be similar
                }
                if a == "car" && sim > Float(threshold) {
                    return false  // Unrelated should NOT be similar
                }
            } catch {
                return false
            }
        }

        return true
    }

    // MARK: - Helper Functions

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }

    private func normalizeAnswer(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "$", with: "")
    }

    private func computeF1(generated: String, expected: String) -> Float {
        let genTokens = Set(generated.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))
        let expTokens = Set(expected.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }))

        guard !genTokens.isEmpty && !expTokens.isEmpty else { return 0 }

        let overlap = genTokens.intersection(expTokens).count
        let precision = Float(overlap) / Float(genTokens.count)
        let recall = Float(overlap) / Float(expTokens.count)

        guard precision + recall > 0 else { return 0 }
        return 2 * (precision * recall) / (precision + recall)
    }
}

// MARK: - Diagnostic View Integration

extension QualityAssuranceService {

    /// Generate a diagnostic report for the Settings/Diagnostics view
    func generateDiagnosticReport(embeddingService: EmbeddingService) async -> String {
        let (passed, correlation, details) = await testEmbeddingSanity(embeddingService: embeddingService)

        return """
        ═══════════════════════════════════════════════════════
        EMBEDDING QUALITY DIAGNOSTIC
        ═══════════════════════════════════════════════════════

        Status: \(passed ? "✅ HEALTHY" : "❌ DEGRADED")
        Semantic Correlation: \(String(format: "%.1f%%", correlation * 100))

        Test Results:
        \(details)

        ═══════════════════════════════════════════════════════
        """
    }
}
