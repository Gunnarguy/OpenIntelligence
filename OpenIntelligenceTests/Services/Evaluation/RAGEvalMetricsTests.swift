//
//  RAGEvalMetricsTests.swift
//  OpenIntelligenceTests
//
//  Latency aggregation tests for RAGEvalMetrics.compute(from:).
//

import XCTest
@testable import OpenIntelligence

final class RAGEvalMetricsTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal result; only fields relevant to latency aggregation vary.
    private func makeResult(
        latencySeconds: Double,
        answerMatch: Bool = true,
        tokensGenerated: Int? = nil
    ) -> RAGEvalResult {
        RAGEvalResult(
            id: UUID().uuidString,
            query: "query",
            generatedResponse: "response",
            answerMatch: answerMatch,
            retrievalRecall: nil,
            citationPrecision: nil,
            abstentionCorrect: false,
            latencySeconds: latencySeconds,
            tokensGenerated: tokensGenerated,
            qualityModeUsed: "balanced",
            contextOverflow: false,
            usedVisualEvidence: nil,
            warnings: [],
            timestamp: Date()
        )
    }

    // MARK: - Empty Input

    func testComputeWithEmptyResultsReturnsEmptyMetrics() {
        let metrics = RAGEvalMetrics.compute(from: [])

        XCTAssertEqual(metrics.totalCases, 0)
        // The empty-input early return must yield 0, never NaN from a 0/0 division.
        XCTAssertEqual(metrics.meanLatencySeconds, 0)
        XCTAssertEqual(metrics.p95LatencySeconds, 0)
        XCTAssertEqual(metrics.meanTokensPerSecond, 0)
        XCTAssertEqual(metrics.unsupportedClaimRate, 1)
        XCTAssertEqual(metrics.contextOverflowRate, 1)
    }

    // MARK: - Single Result

    func testComputeWithSingleResult() {
        let metrics = RAGEvalMetrics.compute(from: [makeResult(latencySeconds: 2.5)])

        XCTAssertEqual(metrics.totalCases, 1)
        // 2.5 is exactly representable in binary; a one-element mean must be exact.
        XCTAssertEqual(metrics.meanLatencySeconds, 2.5)
        XCTAssertEqual(metrics.p95LatencySeconds, 2.5)
    }

    // MARK: - Many Results

    func testComputeWithManyResults() {
        let results = (1...20).map { makeResult(latencySeconds: Double($0)) }
        let metrics = RAGEvalMetrics.compute(from: results)

        XCTAssertEqual(metrics.totalCases, 20)
        // Integer-valued doubles accumulate without rounding: 210 / 20 == 10.5 exactly.
        XCTAssertEqual(metrics.meanLatencySeconds, 10.5)
        // p95 index for 20 sorted latencies is Int(20 * 0.95) == 19, the largest value.
        XCTAssertEqual(metrics.p95LatencySeconds, 20.0)
    }

    // MARK: - Exact Mean Value

    func testMeanLatencyExactValueIsOrderIndependent() {
        // All values exactly representable in binary: sum 8.0, mean exactly 2.0.
        let ascending = [0.5, 1.5, 2.0, 4.0].map { makeResult(latencySeconds: $0) }
        let shuffled = [4.0, 0.5, 2.0, 1.5].map { makeResult(latencySeconds: $0) }

        XCTAssertEqual(RAGEvalMetrics.compute(from: ascending).meanLatencySeconds, 2.0)
        XCTAssertEqual(RAGEvalMetrics.compute(from: shuffled).meanLatencySeconds, 2.0)
    }
}
