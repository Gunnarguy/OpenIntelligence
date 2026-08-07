//
//  RetrievalStageMetricsTests.swift
//  OpenIntelligenceTests
//
//  Hand-worked checks for the ranking metrics that gate the embedding and reranking work.
//
//  Every expected value below is computed by hand in the comment above it rather than captured
//  from a run, because these functions are about to be used to decide whether a model swap is a
//  win. A metric that silently agrees with itself is worse than no metric.
//

import XCTest
@testable import OpenIntelligence

final class RetrievalStageMetricsTests: XCTestCase {

    private let accuracy = 0.0001

    // MARK: - Recall

    func testRecallCountsHitsWithinCutoff() {
        // Relevant item sits at rank 2. One relevant item exists in total.
        let relevance = [false, true, false]

        XCTAssertEqual(RankedRelevance.recall(at: 1, relevance: relevance, totalRelevant: 1), 0.0)
        XCTAssertEqual(RankedRelevance.recall(at: 2, relevance: relevance, totalRelevant: 1), 1.0)
        XCTAssertEqual(RankedRelevance.recall(at: 3, relevance: relevance, totalRelevant: 1), 1.0)
    }

    /// The denominator has to be ground truth, not what was retrieved. Two relevant documents
    /// exist and only one was returned, so recall is 0.5 rather than 1.0.
    func testRecallDenominatorIsGroundTruthNotRetrieved() {
        let relevance = [true, false, false]
        XCTAssertEqual(RankedRelevance.recall(at: 5, relevance: relevance, totalRelevant: 2), 0.5)
    }

    func testRecallIsZeroWhenNothingIsRelevant() {
        XCTAssertEqual(RankedRelevance.recall(at: 5, relevance: [false, false], totalRelevant: 1), 0.0)
    }

    func testRecallGuardsDegenerateInput() {
        XCTAssertEqual(RankedRelevance.recall(at: 0, relevance: [true], totalRelevant: 1), 0.0)
        XCTAssertEqual(RankedRelevance.recall(at: 5, relevance: [true], totalRelevant: 0), 0.0)
    }

    // MARK: - Precision

    /// 2 relevant in a 5-result window: 2/5.
    func testPrecisionOverFullWindow() {
        let relevance = [true, false, true, false, false]
        XCTAssertEqual(RankedRelevance.precision(at: 5, relevance: relevance), 0.4, accuracy: accuracy)
    }

    /// A stage that returned only 3 results is scored against 3, not against k.
    func testPrecisionDoesNotPenaliseShortResultSets() {
        let relevance = [true, false, true]
        XCTAssertEqual(RankedRelevance.precision(at: 5, relevance: relevance), 2.0 / 3.0, accuracy: accuracy)
    }

    func testPrecisionOfEmptyResultsIsZero() {
        XCTAssertEqual(RankedRelevance.precision(at: 5, relevance: []), 0.0)
    }

    // MARK: - Reciprocal rank

    func testReciprocalRankUsesFirstRelevantPosition() {
        XCTAssertEqual(RankedRelevance.reciprocalRank([true, true]), 1.0)
        XCTAssertEqual(RankedRelevance.reciprocalRank([false, true, true]), 0.5)
        XCTAssertEqual(RankedRelevance.reciprocalRank([false, false, true]), 1.0 / 3.0, accuracy: accuracy)
    }

    func testReciprocalRankIsZeroWhenNothingRelevant() {
        XCTAssertEqual(RankedRelevance.reciprocalRank([false, false]), 0.0)
    }

    // MARK: - DCG and nDCG

    /// gains [1, 0, 1] at k=3:
    ///   1/log2(2) + 0/log2(3) + 1/log2(4)
    /// = 1/1        + 0         + 1/2
    /// = 1.5
    func testDCGAppliesLog2PositionalDiscount() {
        XCTAssertEqual(RankedRelevance.dcg(at: 3, gains: [1, 0, 1]), 1.5, accuracy: accuracy)
    }

    func testDCGRespectsCutoff() {
        // Only the first gain counts at k=1.
        XCTAssertEqual(RankedRelevance.dcg(at: 1, gains: [1, 1, 1]), 1.0, accuracy: accuracy)
    }

    /// One relevant document, returned at rank 1. DCG = 1, IDCG = 1, nDCG = 1.
    func testNDCGIsOneForAPerfectRanking() {
        XCTAssertEqual(
            RankedRelevance.ndcg(at: 5, relevance: [true, false], totalRelevant: 1),
            1.0,
            accuracy: accuracy
        )
    }

    /// One relevant document, returned at rank 2.
    ///   DCG  = 0/log2(2) + 1/log2(3) = 1/1.584962... = 0.630929...
    ///   IDCG = 1/log2(2)                             = 1.0
    ///   nDCG = 0.630929...
    func testNDCGDiscountsALateHit() {
        XCTAssertEqual(
            RankedRelevance.ndcg(at: 5, relevance: [false, true], totalRelevant: 1),
            0.630929,
            accuracy: accuracy
        )
    }

    /// A query with no achievable gain scores 0, never 1. Guards the divide-by-zero that would
    /// otherwise report a perfect score for a query with no relevant documents.
    func testNDCGIsZeroWhenNoGainIsAchievable() {
        XCTAssertEqual(RankedRelevance.ndcg(at: 5, relevance: [false], totalRelevant: 0), 0.0)
        XCTAssertEqual(RankedRelevance.ndcg(at: 5, gains: [0, 0], idealGains: [0]), 0.0)
    }

    /// Ideal gains are sorted descending internally, so an unsorted ground truth still produces
    /// the correct ceiling.
    func testNDCGSortsIdealGains() {
        let sorted = RankedRelevance.ndcg(at: 3, gains: [3, 2], idealGains: [3, 2])
        let unsorted = RankedRelevance.ndcg(at: 3, gains: [3, 2], idealGains: [2, 3])
        XCTAssertEqual(sorted, unsorted, accuracy: accuracy)
    }

    // MARK: - Relevance judging

    func testNormalizeStripsSeparatorsAndCase() {
        XCTAssertEqual(RetrievalRelevanceJudge.normalize("Vehicle_Specs.md"), "vehiclespecsmd")
        XCTAssertEqual(RetrievalRelevanceJudge.normalize("vehicle specs.md"), "vehiclespecsmd")
        XCTAssertEqual(RetrievalRelevanceJudge.normalize("vehicle-specs-MD"), "vehiclespecsmd")
    }

    /// The committed fixtures name ground truth by filename, so matching must run against the
    /// source document. This is the case that reads 0.0 under the shipped runner.
    func testMatchesOnSourceDocumentFilename() {
        let chunk = Self.makeChunk(sourceDocument: "vehicle_specs.md")
        XCTAssertTrue(RetrievalRelevanceJudge.matches(chunk, expected: "vehicle_specs.md"))
        XCTAssertTrue(RetrievalRelevanceJudge.matches(chunk, expected: "Vehicle Specs.md"))
        XCTAssertFalse(RetrievalRelevanceJudge.matches(chunk, expected: "finance_cash_flow.md"))
    }

    func testMatchesOnDocumentIdentifier() {
        let documentId = UUID()
        let chunk = Self.makeChunk(sourceDocument: "", documentId: documentId)
        XCTAssertTrue(RetrievalRelevanceJudge.matches(chunk, expected: documentId.uuidString))
    }

    func testEmptyExpectedSourceNeverMatches() {
        let chunk = Self.makeChunk(sourceDocument: "vehicle_specs.md")
        XCTAssertFalse(RetrievalRelevanceJudge.matches(chunk, expected: ""))
    }

    // MARK: - Stage scoring

    func testStageScoringPlacesHitAtSecondRank() {
        let results = [
            Self.makeChunk(sourceDocument: "unrelated.md"),
            Self.makeChunk(sourceDocument: "vehicle_specs.md"),
        ]

        let metrics = RetrievalStageMetrics.score(
            stage: "vector",
            results: results,
            expectedSources: ["vehicle_specs.md"]
        )

        XCTAssertEqual(metrics.stage, "vector")
        XCTAssertEqual(metrics.recallAt1, 0.0)
        XCTAssertEqual(metrics.recallAt3, 1.0)
        XCTAssertEqual(metrics.reciprocalRank, 0.5, accuracy: accuracy)
        XCTAssertEqual(metrics.ndcgAt5, 0.630929, accuracy: accuracy)
        XCTAssertEqual(metrics.resultCount, 2)
        XCTAssertEqual(metrics.relevantCount, 1)
    }

    func testEmptyStageScoresAsCompleteMiss() {
        let metrics = RetrievalStageMetrics.score(
            stage: "bm25",
            results: [],
            expectedSources: ["vehicle_specs.md"]
        )

        XCTAssertEqual(metrics.recallAt5, 0.0)
        XCTAssertEqual(metrics.reciprocalRank, 0.0)
        XCTAssertEqual(metrics.ndcgAt5, 0.0)
        XCTAssertEqual(metrics.resultCount, 0)
    }

    // MARK: - Aggregation

    func testAggregateAveragesAcrossQueriesAndPreservesStageOrder() {
        let hit = RetrievalStageMetrics.score(
            stage: "rerank",
            results: [Self.makeChunk(sourceDocument: "a.md")],
            expectedSources: ["a.md"]
        )
        let miss = RetrievalStageMetrics.score(
            stage: "rerank",
            results: [Self.makeChunk(sourceDocument: "b.md")],
            expectedSources: ["a.md"]
        )
        let vectorStage = RetrievalStageMetrics.score(
            stage: "vector",
            results: [Self.makeChunk(sourceDocument: "a.md")],
            expectedSources: ["a.md"]
        )

        // Stage order follows first appearance: vector was seen first in query one.
        let aggregates = RetrievalStageEvaluator.aggregate(perQuery: [[vectorStage, hit], [miss]])

        XCTAssertEqual(aggregates.map(\.stage), ["vector", "rerank"])

        let rerank = try! XCTUnwrap(aggregates.first { $0.stage == "rerank" })
        XCTAssertEqual(rerank.queryCount, 2)
        XCTAssertEqual(rerank.recallAt5, 0.5, accuracy: accuracy)
        XCTAssertEqual(rerank.mrr, 0.5, accuracy: accuracy)
    }

    func testAggregateCountsEmptyStages() {
        let empty = RetrievalStageMetrics.score(stage: "bm25", results: [], expectedSources: ["a.md"])
        let aggregate = AggregateStageMetrics.aggregate(stage: "bm25", perQuery: [empty, empty])
        XCTAssertEqual(aggregate.emptyResultQueries, 2)
        XCTAssertEqual(aggregate.queryCount, 2)
    }

    func testAggregateOfNothingIsZeroNotCrash() {
        let aggregate = AggregateStageMetrics.aggregate(stage: "vector", perQuery: [])
        XCTAssertEqual(aggregate.queryCount, 0)
        XCTAssertEqual(aggregate.mrr, 0.0)
    }

    // MARK: - Helpers

    private static func makeChunk(
        sourceDocument: String,
        documentId: UUID = UUID()
    ) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: documentId,
                content: "content",
                embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0)
            ),
            similarityScore: 0.5,
            rank: 0,
            sourceDocument: sourceDocument
        )
    }
}
