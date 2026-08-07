//
//  RetrievalStageMetrics.swift
//  OpenIntelligence
//
//  Per-stage retrieval quality metrics: recall@k, MRR, nDCG, precision@k.
//
//  Why this exists separately from `RAGEvalMetrics`:
//
//  `RAGEvalMetrics` carries `retrievalRecallAt5` as a single end-to-end figure computed after the
//  whole pipeline has run. That cannot answer the question the embedding and reranking work
//  actually needs answered, which is *where* recall is lost. Reranking cannot recover a chunk the
//  first stage never returned, so a first-stage number and a post-rerank number have to be
//  reported separately or a regression in one can be masked by the other.
//
//  The metric math below is deliberately free of every RAG type. It operates on a rank-ordered
//  relevance vector, which makes it unit-testable against hand-worked examples with no pipeline,
//  no fixtures, and no I/O. Deciding *which* results are relevant is a separate concern and lives
//  in `RetrievalRelevanceJudge`.
//

import Foundation

// MARK: - Rank-ordered metric math

/// Pure ranking metrics over a rank-ordered relevance vector.
///
/// Every function takes results already sorted best-first. Index 0 is rank 1.
enum RankedRelevance {

    /// Recall@k: what fraction of all known-relevant documents appear in the top `k`.
    ///
    /// - Parameters:
    ///   - k: cutoff rank, 1-based. Values below 1 return 0.
    ///   - relevance: rank-ordered flags, `true` where the result at that rank is relevant.
    ///   - totalRelevant: size of the full relevant set, including items that were never
    ///     retrieved. This is the denominator, so it must come from ground truth rather than
    ///     from `relevance`, otherwise unretrieved items silently vanish and recall reads 1.0.
    static func recall(at k: Int, relevance: [Bool], totalRelevant: Int) -> Double {
        guard k > 0, totalRelevant > 0 else { return 0 }
        let hits = relevance.prefix(k).filter { $0 }.count
        return min(1.0, Double(hits) / Double(totalRelevant))
    }

    /// Precision@k: what fraction of the top `k` returned results are relevant.
    ///
    /// The denominator is the number of results actually present, capped at `k`, so a stage that
    /// returned only 3 results is not penalised against a `k` of 5.
    static func precision(at k: Int, relevance: [Bool]) -> Double {
        guard k > 0 else { return 0 }
        let window = relevance.prefix(k)
        guard !window.isEmpty else { return 0 }
        return Double(window.filter { $0 }.count) / Double(window.count)
    }

    /// Reciprocal rank: `1 / rank` of the first relevant result, or 0 if none is relevant.
    ///
    /// Averaging this across queries gives MRR.
    static func reciprocalRank(_ relevance: [Bool]) -> Double {
        guard let index = relevance.firstIndex(of: true) else { return 0 }
        return 1.0 / Double(index + 1)
    }

    /// Discounted cumulative gain at `k`.
    ///
    /// Uses the standard log2 positional discount: rank 1 is undiscounted, rank 2 is divided by
    /// log2(3), and so on.
    static func dcg(at k: Int, gains: [Double]) -> Double {
        guard k > 0 else { return 0 }
        return gains.prefix(k).enumerated().reduce(0.0) { total, entry in
            let (index, gain) = entry
            return total + gain / log2(Double(index) + 2.0)
        }
    }

    /// Normalised discounted cumulative gain at `k`.
    ///
    /// - Parameters:
    ///   - gains: rank-ordered relevance gains as actually returned.
    ///   - idealGains: every known gain for this query, including items that were never
    ///     retrieved. Sorted descending internally to form the ideal ranking.
    ///
    /// Returns 0 when no gain is achievable, which keeps a query with no relevant documents from
    /// reporting a perfect score.
    static func ndcg(at k: Int, gains: [Double], idealGains: [Double]) -> Double {
        let ideal = dcg(at: k, gains: idealGains.sorted(by: >))
        guard ideal > 0 else { return 0 }
        return dcg(at: k, gains: gains) / ideal
    }

    /// Convenience for the binary-relevance case, which is what the committed fixtures provide.
    static func ndcg(at k: Int, relevance: [Bool], totalRelevant: Int) -> Double {
        guard totalRelevant > 0 else { return 0 }
        return ndcg(
            at: k,
            gains: relevance.map { $0 ? 1.0 : 0.0 },
            idealGains: Array(repeating: 1.0, count: totalRelevant)
        )
    }
}

// MARK: - Relevance judging

/// Decides whether a retrieved chunk satisfies a ground-truth reference.
///
/// The committed fixtures identify ground truth by **filename** (`expectedCitations`, e.g.
/// `vehicle_specs.md`), not by chunk UUID. Matching therefore has to run against the source
/// document, and matching on `chunk.id` scores every case zero. See the note in
/// `RetrievalStageEvaluator`.
enum RetrievalRelevanceJudge {

    /// Lowercases and strips everything except alphanumerics so that `Vehicle_Specs.md`,
    /// `vehicle specs.md`, and `vehicle-specs` all compare equal.
    static func normalize(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// True when `chunk` came from a document the ground truth names.
    ///
    /// Compares against both the document UUID and the citation filename, in both containment
    /// directions, because fixtures may name a bare stem while the pipeline reports a full
    /// filename with extension.
    static func matches(_ chunk: RetrievedChunk, expected: String) -> Bool {
        let target = normalize(expected)
        guard !target.isEmpty else { return false }

        let documentId = normalize(chunk.chunk.documentId.uuidString)
        let documentName = normalize(chunk.sourceDocument)

        if documentId.contains(target) { return true }
        if documentName.isEmpty { return false }
        return documentName.contains(target) || target.contains(documentName)
    }

    /// Rank-ordered relevance flags for one stage's output.
    static func relevanceVector(
        results: [RetrievedChunk],
        expectedSources: [String]
    ) -> [Bool] {
        results.map { result in
            expectedSources.contains { matches(result, expected: $0) }
        }
    }
}

// MARK: - Per-stage metrics

/// Metrics for a single named retrieval stage on a single query.
struct RetrievalStageMetrics: Codable, Sendable, Equatable {

    /// Stage label, e.g. `vector`, `bm25`, `fusion`, `rerank`.
    let stage: String

    let recallAt1: Double
    let recallAt3: Double
    let recallAt5: Double
    let recallAt10: Double

    /// Reciprocal rank for this query. Average across queries to get MRR.
    let reciprocalRank: Double

    let ndcgAt5: Double
    let ndcgAt10: Double

    let precisionAt5: Double

    /// How many results this stage actually returned.
    let resultCount: Int

    /// Size of the ground-truth relevant set for the query.
    let relevantCount: Int

    /// Score a single stage against the ground-truth sources for one query.
    ///
    /// `results` must be rank-ordered best-first, which is the order every stage in
    /// `HybridSearchService` already produces.
    static func score(
        stage: String,
        results: [RetrievedChunk],
        expectedSources: [String]
    ) -> RetrievalStageMetrics {
        let relevance = RetrievalRelevanceJudge.relevanceVector(
            results: results,
            expectedSources: expectedSources
        )
        let total = expectedSources.count

        return RetrievalStageMetrics(
            stage: stage,
            recallAt1: RankedRelevance.recall(at: 1, relevance: relevance, totalRelevant: total),
            recallAt3: RankedRelevance.recall(at: 3, relevance: relevance, totalRelevant: total),
            recallAt5: RankedRelevance.recall(at: 5, relevance: relevance, totalRelevant: total),
            recallAt10: RankedRelevance.recall(at: 10, relevance: relevance, totalRelevant: total),
            reciprocalRank: RankedRelevance.reciprocalRank(relevance),
            ndcgAt5: RankedRelevance.ndcg(at: 5, relevance: relevance, totalRelevant: total),
            ndcgAt10: RankedRelevance.ndcg(at: 10, relevance: relevance, totalRelevant: total),
            precisionAt5: RankedRelevance.precision(at: 5, relevance: relevance),
            resultCount: results.count,
            relevantCount: total
        )
    }
}

// MARK: - Aggregation

/// Mean metrics for one stage across a whole evaluation run.
///
/// `reciprocalRank` averaged across queries is MRR, which is why the aggregate exposes it under
/// that name while the per-query type does not.
struct AggregateStageMetrics: Codable, Sendable, Equatable {

    let stage: String

    let recallAt1: Double
    let recallAt3: Double
    let recallAt5: Double
    let recallAt10: Double

    /// Mean reciprocal rank across every scored query.
    let mrr: Double

    let ndcgAt5: Double
    let ndcgAt10: Double
    let precisionAt5: Double

    /// Number of queries contributing to these means.
    let queryCount: Int

    /// Queries where the stage returned nothing at all. These are scored as complete misses
    /// rather than skipped, because dropping them would flatter a stage that fails to run.
    let emptyResultQueries: Int

    static func aggregate(stage: String, perQuery: [RetrievalStageMetrics]) -> AggregateStageMetrics {
        guard !perQuery.isEmpty else {
            return AggregateStageMetrics(
                stage: stage,
                recallAt1: 0, recallAt3: 0, recallAt5: 0, recallAt10: 0,
                mrr: 0, ndcgAt5: 0, ndcgAt10: 0, precisionAt5: 0,
                queryCount: 0, emptyResultQueries: 0
            )
        }

        let n = Double(perQuery.count)
        func mean(_ keyPath: KeyPath<RetrievalStageMetrics, Double>) -> Double {
            perQuery.reduce(0.0) { $0 + $1[keyPath: keyPath] } / n
        }

        return AggregateStageMetrics(
            stage: stage,
            recallAt1: mean(\.recallAt1),
            recallAt3: mean(\.recallAt3),
            recallAt5: mean(\.recallAt5),
            recallAt10: mean(\.recallAt10),
            mrr: mean(\.reciprocalRank),
            ndcgAt5: mean(\.ndcgAt5),
            ndcgAt10: mean(\.ndcgAt10),
            precisionAt5: mean(\.precisionAt5),
            queryCount: perQuery.count,
            emptyResultQueries: perQuery.filter { $0.resultCount == 0 }.count
        )
    }
}

// MARK: - Stage capture

/// Rank-ordered output of one named retrieval stage for one query.
struct RetrievalStageTrace: Sendable {
    let stage: String
    let results: [RetrievedChunk]

    init(stage: String, results: [RetrievedChunk]) {
        self.stage = stage
        self.results = results
    }
}

/// Scores a full multi-stage retrieval trace for one query, then rolls traces up across queries.
///
/// ## The bug this replaces
///
/// `RAGEvalRunner.evaluate` computes retrieval recall only when `evalCase.groundTruthChunkIds` is
/// non-empty, and matches those against `chunk.id.uuidString`. Every case in the committed
/// `Benchmarks/rag_eval_v1.jsonl` has `groundTruthChunkIds: null`; ground truth is carried in
/// `expectedCitations` as a filename. So `retrievalRecall` is `nil` for every case,
/// `RAGEvalMetrics.compute` sees an empty array, and `retrievalRecallAt5` is reported as exactly
/// `0.0` on every run no matter how retrieval performs. The `>= 0.85` quality gate can therefore
/// never pass. Scoring here goes through `RetrievalRelevanceJudge`, which matches on the source
/// document instead.
enum RetrievalStageEvaluator {

    /// Score every stage of one query's trace.
    static func score(
        traces: [RetrievalStageTrace],
        expectedSources: [String]
    ) -> [RetrievalStageMetrics] {
        traces.map { trace in
            RetrievalStageMetrics.score(
                stage: trace.stage,
                results: trace.results,
                expectedSources: expectedSources
            )
        }
    }

    /// Roll per-query stage metrics up into one aggregate per stage.
    ///
    /// Stage order is preserved from first appearance so a report reads in pipeline order rather
    /// than alphabetically.
    static func aggregate(perQuery: [[RetrievalStageMetrics]]) -> [AggregateStageMetrics] {
        var order: [String] = []
        var grouped: [String: [RetrievalStageMetrics]] = [:]

        for query in perQuery {
            for metric in query {
                if grouped[metric.stage] == nil {
                    order.append(metric.stage)
                    grouped[metric.stage] = []
                }
                grouped[metric.stage]?.append(metric)
            }
        }

        return order.map { stage in
            AggregateStageMetrics.aggregate(stage: stage, perQuery: grouped[stage] ?? [])
        }
    }
}
