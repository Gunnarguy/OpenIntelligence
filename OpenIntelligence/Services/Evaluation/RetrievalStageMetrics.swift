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
    ///
    /// `relevance` must be **document-credited** (see `creditedRelevanceVector`), not raw per-chunk
    /// flags. Ground truth here is a set of documents while retrieval returns chunks, so raw flags
    /// let one document score repeatedly against a denominator of one.
    ///
    /// Note for reporting: on the committed fixture 18 of 20 cases name exactly one source, so
    /// `totalRelevant == 1` and this is numerically identical to Success@k / hit rate. It carries
    /// no information beyond "did a chunk from the right file appear". MRR@10 and nDCG are the
    /// metrics that actually discriminate between stages on this corpus.
    static func recall(at k: Int, relevance: [Bool], totalRelevant: Int) -> Double {
        guard k > 0, totalRelevant > 0 else { return 0 }
        let hits = relevance.prefix(k).filter { $0 }.count
        // Deliberately unclamped. With a credited vector each relevant document contributes at most
        // once, so this cannot exceed 1.0; if it ever does, the caller passed raw chunk flags and
        // the number is wrong. A `min(1.0, ...)` here previously hid exactly that: five chunks from
        // one of two expected documents reported recall 1.0 while the other was never retrieved.
        return Double(hits) / Double(totalRelevant)
    }

    /// Precision@k: what fraction of the top `k` positions hold a relevant result.
    ///
    /// The denominator is `k`, matching `trec_eval`'s `P`, whose own source states the rule: "If
    /// the cutoff is larger than the number of docs retrieved, then it is assumed nonrelevant docs
    /// fill in the rest. Eg, if a method retrieves 15 docs of which 4 are relevant, then P20 is 0.2
    /// (4/20)."
    ///
    /// This previously divided by `min(k, results.count)` so that a short result list was "not
    /// penalised". That is `trec_eval`'s `set_P`, a different measure with a different name, and
    /// here it actively broke the thing this instrumentation exists for: `candidates`, `rerank` and
    /// `final` return fewer than `k` results after top-K truncation, so their precision was
    /// systematically inflated against `vector` and `lexical`, making the per-stage comparison
    /// misleading in a consistent direction.
    static func precision(at k: Int, relevance: [Bool]) -> Double {
        guard k > 0 else { return 0 }
        return Double(relevance.prefix(k).filter { $0 }.count) / Double(k)
    }

    /// Reciprocal rank at a cutoff: `1 / rank` of the first relevant result within the top `k`,
    /// or 0 if none is. Averaging across queries gives MRR@k.
    ///
    /// The cutoff is not optional here. `trec_eval`'s `recip_rank` is uncapped, but it scores one
    /// list per query; this compares seven stages of very different lengths side by side. Uncapped,
    /// a relevant chunk at rank 30 contributes 0.033 to `vector`, which returns 30+ candidates, and
    /// exactly 0 to `final`, which returns 10 — a difference produced by list length rather than by
    /// ranking quality. BEIR caps for the same reason.
    static func reciprocalRank(at k: Int = 10, _ relevance: [Bool]) -> Double {
        guard k > 0, let index = relevance.prefix(k).firstIndex(of: true) else { return 0 }
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

    /// Normalised document stem: extension removed, and a trailing `-<digits>` disambiguator
    /// removed before normalising.
    ///
    /// Ingestion assigns a unique filename, so the fixture `vehicle_specs.md` is stored as
    /// `vehicle_specs-6.md`. Plain normalisation turns those into `vehiclespecsmd` and
    /// `vehiclespecs6md`, and neither contains the other, so a correct retrieval scored zero.
    /// Measured on a real run before this existed: every stage of every case reported `0.0000`
    /// while the answers were verifiably correct.
    ///
    /// Only a trailing hyphen-digits group is stripped, so fixtures whose names legitimately end in
    /// a digit-bearing token, such as `case_1_part_a.md`, are untouched.
    static func documentStem(_ key: String) -> String {
        var stem = (key as NSString).deletingPathExtension
        while let range = stem.range(of: "-[0-9]+$", options: .regularExpression) {
            stem.removeSubrange(range)
        }
        return normalize(stem)
    }

    /// True when `chunk` came from a document the ground truth names.
    ///
    /// Compares against both the document UUID and the citation filename, in both containment
    /// directions, because fixtures may name a bare stem while the pipeline reports a full
    /// filename with extension.
    /// Matching runs against the document identifier first and the filename second.
    ///
    /// The identifier path is not a fallback, it is the only thing that works before reranking.
    /// `RAGService` attaches `sourceDocument` by looking `documentId` up in a documents snapshot
    /// *after* `HybridSearchService` returns, so chunks flowing through the `vector`, `lexical`,
    /// `fusion`, `boosted` and `candidates` stages carry an empty filename. Judging those stages by
    /// filename alone scores them zero no matter how good retrieval was; the harness therefore
    /// resolves the expected filenames to document UUIDs and passes both.
    static func matches(_ chunk: RetrievedChunk, expected: String) -> Bool {
        let target = normalize(expected)
        guard !target.isEmpty else { return false }

        if normalize(chunk.chunk.documentId.uuidString) == target { return true }

        let documentName = chunk.sourceDocument
        guard !normalize(documentName).isEmpty else { return false }

        // Compare stems so an ingestion-assigned `-N` disambiguator does not defeat the match.
        let expectedStem = documentStem(expected)
        let actualStem = documentStem(documentName)
        guard !expectedStem.isEmpty, !actualStem.isEmpty else { return false }
        return actualStem == expectedStem
            || actualStem.contains(expectedStem)
            || expectedStem.contains(actualStem)
    }

    /// Rank-ordered relevance flags for one stage's output, one entry per retrieved chunk.
    ///
    /// Every chunk from a ground-truth document is flagged. Correct for **precision**, whose
    /// denominator is chunks. Wrong for recall, MRR and nDCG, whose denominators are documents:
    /// use `creditedRelevanceVector` for those.
    static func relevanceVector(
        results: [RetrievedChunk],
        expectedSources: [String]
    ) -> [Bool] {
        results.map { result in
            expectedSources.contains { matches(result, expected: $0) }
        }
    }

    /// Rank-ordered relevance flags where each ground-truth **document** earns credit exactly once,
    /// at the rank of its first matching chunk.
    ///
    /// This is the vector that recall, MRR and nDCG require, and it exists because ground truth in
    /// `Benchmarks/rag_eval_v1.jsonl` is a list of filenames while retrieval returns chunks. A
    /// document routinely contributes several chunks to the top-k; crediting each of them makes the
    /// numerator count chunks against a denominator counting documents. Measured consequences of
    /// the uncredited version, both reproduced before this was fixed:
    ///
    /// - Two expected documents, five retrieved chunks all from the first: recall@5 reported `1.0`
    ///   while the second document was never retrieved at all.
    /// - One expected document, three of its chunks in the top five: **nDCG@5 reported `2.131`**,
    ///   for a metric defined on `[0, 1]`.
    ///
    /// `k` still counts chunks, which is the operationally meaningful cutoff because chunks are
    /// what reach the model. Only the relevance credit is deduplicated.
    static func creditedRelevanceVector(
        results: [RetrievedChunk],
        expectedSources: [String]
    ) -> [Bool] {
        var credited = Set<String>()
        return results.map { result in
            guard let matched = expectedSources.first(where: { matches(result, expected: $0) }) else {
                return false
            }
            // `insert` reports `inserted: false` for a document already credited at a better rank.
            return credited.insert(normalize(matched)).inserted
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

    /// Reciprocal rank for this query, **cut off at rank 10**. Average across queries for MRR@10.
    /// The cutoff keeps stages of different lengths comparable; see `RankedRelevance.reciprocalRank`.
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
        // Two vectors, deliberately. Recall, MRR and nDCG have document-shaped denominators and use
        // the credited vector; precision has a chunk-shaped denominator and uses the raw one.
        // Using one vector for all of them is the defect that let nDCG@5 report 2.131.
        let credited = RetrievalRelevanceJudge.creditedRelevanceVector(
            results: results,
            expectedSources: expectedSources
        )
        let perChunk = RetrievalRelevanceJudge.relevanceVector(
            results: results,
            expectedSources: expectedSources
        )
        // Distinct expected documents, not the raw array count, so a fixture that names the same
        // source twice cannot inflate the denominator and depress recall.
        let total = Set(expectedSources.map(RetrievalRelevanceJudge.normalize)).filter { !$0.isEmpty }.count

        return RetrievalStageMetrics(
            stage: stage,
            recallAt1: RankedRelevance.recall(at: 1, relevance: credited, totalRelevant: total),
            recallAt3: RankedRelevance.recall(at: 3, relevance: credited, totalRelevant: total),
            recallAt5: RankedRelevance.recall(at: 5, relevance: credited, totalRelevant: total),
            recallAt10: RankedRelevance.recall(at: 10, relevance: credited, totalRelevant: total),
            reciprocalRank: RankedRelevance.reciprocalRank(at: 10, credited),
            ndcgAt5: RankedRelevance.ndcg(at: 5, relevance: credited, totalRelevant: total),
            ndcgAt10: RankedRelevance.ndcg(at: 10, relevance: credited, totalRelevant: total),
            precisionAt5: RankedRelevance.precision(at: 5, relevance: perChunk),
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

// MARK: - Stage scoring

// `RetrievalStageTrace` and `RetrievalTraceCollector` deliberately live in
// `Services/RAG/Retrieval/RetrievalTraceCollector.swift` rather than here. `OpenIntelligenceEngine`
// is a separate target whose synchronized root groups include `Services/RAG` but not
// `Services/Evaluation`, so a type referenced by `HybridSearchService` cannot live in this folder.
// The split also matches the right layering: retrieval reports what it did, evaluation grades it.

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
