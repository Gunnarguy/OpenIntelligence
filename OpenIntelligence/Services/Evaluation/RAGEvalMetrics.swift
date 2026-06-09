//
//  RAGEvalMetrics.swift
//  OpenIntelligence
//
//  Defines the target metrics for RAG pipeline evaluation.
//  Metrics align with WWDC26.md quality gates.
//

import Foundation

// MARK: - Aggregate Metrics

/// Aggregate metrics computed across an entire evaluation run.
///
/// These map directly to the quality gates defined in WWDC26.md:
///
/// | Metric                    | Target  |
/// |:--------------------------|:--------|
/// | Retrieval recall@5        | ≥ 0.85  |
/// | Citation precision        | ≥ 0.90  |
/// | Exact-value accuracy      | ≥ 0.95  |
/// | Unsupported-claim rate    | ≤ 0.05  |
/// | Correct abstention rate   | ≥ 0.85  |
/// | Context overflow rate     | ≤ 0.02  |
/// | Visual OCR evidence use   | ≥ 0.90  |
struct RAGEvalMetrics: Codable, Sendable {

    // -- Core Metrics --

    /// Fraction of ground-truth chunks that appeared in the top-5 retrieval results
    let retrievalRecallAt5: Double

    /// Fraction of cited sources that are correct
    let citationPrecision: Double

    /// Fraction of exact-value queries answered correctly
    let exactValueAccuracy: Double

    /// Fraction of responses that contained unsupported claims
    let unsupportedClaimRate: Double

    /// Fraction of abstention cases correctly handled
    let correctAbstentionRate: Double

    /// Fraction of queries that hit context overflow
    let contextOverflowRate: Double

    /// Fraction of visual evidence queries that used OCR evidence
    let visualOCREvidenceUseRate: Double

    // -- Latency Metrics --

    /// Mean response latency in seconds
    let meanLatencySeconds: Double

    /// P95 response latency in seconds
    let p95LatencySeconds: Double

    /// Mean tokens per second
    let meanTokensPerSecond: Double

    // -- Summary --

    /// Total number of cases evaluated
    let totalCases: Int

    /// Number of cases that passed all applicable quality gates
    let passedCases: Int

    /// Number of cases that failed at least one quality gate
    let failedCases: Int

    /// Overall pass rate
    var passRate: Double {
        guard totalCases > 0 else { return 0 }
        return Double(passedCases) / Double(totalCases)
    }

    // MARK: - Quality Gate Check

    /// Check whether this eval run meets all WWDC26 quality gates.
    var meetsQualityGates: Bool {
        retrievalRecallAt5 >= 0.85
            && citationPrecision >= 0.90
            && exactValueAccuracy >= 0.95
            && unsupportedClaimRate <= 0.05
            && correctAbstentionRate >= 0.85
            && contextOverflowRate <= 0.02
            && visualOCREvidenceUseRate >= 0.90
    }

    /// Individual gate results for reporting
    var gateResults: [(name: String, target: String, actual: String, passed: Bool)] {
        [
            ("Retrieval recall@5", "≥ 0.85", String(format: "%.3f", retrievalRecallAt5), retrievalRecallAt5 >= 0.85),
            ("Citation precision", "≥ 0.90", String(format: "%.3f", citationPrecision), citationPrecision >= 0.90),
            ("Exact-value accuracy", "≥ 0.95", String(format: "%.3f", exactValueAccuracy), exactValueAccuracy >= 0.95),
            ("Unsupported-claim rate", "≤ 0.05", String(format: "%.3f", unsupportedClaimRate), unsupportedClaimRate <= 0.05),
            ("Correct abstention rate", "≥ 0.85", String(format: "%.3f", correctAbstentionRate), correctAbstentionRate >= 0.85),
            ("Context overflow rate", "≤ 0.02", String(format: "%.3f", contextOverflowRate), contextOverflowRate <= 0.02),
            ("Visual OCR evidence use", "≥ 0.90", String(format: "%.3f", visualOCREvidenceUseRate), visualOCREvidenceUseRate >= 0.90),
        ]
    }
}

// MARK: - Metrics Computation

extension RAGEvalMetrics {

    /// Compute aggregate metrics from a set of individual eval results.
    static func compute(from results: [RAGEvalResult]) -> RAGEvalMetrics {
        guard !results.isEmpty else {
            return .empty
        }

        let total = results.count

        // Retrieval recall@5
        let recallValues = results.compactMap(\.retrievalRecall)
        let avgRecall = recallValues.isEmpty ? 0.0 : recallValues.reduce(0, +) / Double(recallValues.count)

        // Citation precision
        let citationValues = results.compactMap(\.citationPrecision)
        let avgCitation = citationValues.isEmpty ? 0.0 : citationValues.reduce(0, +) / Double(citationValues.count)

        // Exact-value accuracy (only for cases with answer matching)
        let exactValues = results.filter(\.answerMatch)
        let exactAccuracy = Double(exactValues.count) / Double(total)

        // Unsupported claim rate
        let unsupportedClaims = results.filter { !$0.answerMatch && !$0.abstentionCorrect }
        let claimRate = Double(unsupportedClaims.count) / Double(total)

        // Correct abstention rate
        let abstentionCases = results.filter { _ in true } // All cases checked for abstention
        let correctAbstentions = results.filter(\.abstentionCorrect)
        let abstentionRate = abstentionCases.isEmpty ? 1.0 : Double(correctAbstentions.count) / Double(abstentionCases.count)

        // Context overflow rate
        let overflows = results.filter(\.contextOverflow)
        let overflowRate = Double(overflows.count) / Double(total)

        // Visual OCR evidence use
        let visualCases = results.filter { $0.usedVisualEvidence != nil }
        let visualUsed = visualCases.filter { $0.usedVisualEvidence == true }
        let visualRate = visualCases.isEmpty ? 1.0 : Double(visualUsed.count) / Double(visualCases.count)

        // Latency
        let latencies = results.map(\.latencySeconds).sorted()
        let meanLatency = latencies.reduce(0, +) / Double(latencies.count)
        let p95Index = Int(Double(latencies.count) * 0.95)
        let p95Latency = latencies.indices.contains(p95Index) ? latencies[p95Index] : latencies.last ?? 0

        // Tokens per second
        let tokensPerSec = results.compactMap { result -> Double? in
            guard let tokens = result.tokensGenerated, result.latencySeconds > 0 else { return nil }
            return Double(tokens) / result.latencySeconds
        }
        let meanTPS = tokensPerSec.isEmpty ? 0.0 : tokensPerSec.reduce(0, +) / Double(tokensPerSec.count)

        // Pass/fail
        let passed = results.filter { $0.answerMatch || $0.abstentionCorrect }

        return RAGEvalMetrics(
            retrievalRecallAt5: avgRecall,
            citationPrecision: avgCitation,
            exactValueAccuracy: exactAccuracy,
            unsupportedClaimRate: claimRate,
            correctAbstentionRate: abstentionRate,
            contextOverflowRate: overflowRate,
            visualOCREvidenceUseRate: visualRate,
            meanLatencySeconds: meanLatency,
            p95LatencySeconds: p95Latency,
            meanTokensPerSecond: meanTPS,
            totalCases: total,
            passedCases: passed.count,
            failedCases: total - passed.count
        )
    }

    /// Empty metrics (no data)
    static let empty = RAGEvalMetrics(
        retrievalRecallAt5: 0,
        citationPrecision: 0,
        exactValueAccuracy: 0,
        unsupportedClaimRate: 1,
        correctAbstentionRate: 0,
        contextOverflowRate: 1,
        visualOCREvidenceUseRate: 0,
        meanLatencySeconds: 0,
        p95LatencySeconds: 0,
        meanTokensPerSecond: 0,
        totalCases: 0,
        passedCases: 0,
        failedCases: 0
    )
}
