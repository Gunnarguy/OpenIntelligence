//
//  RetrievalTraceCollector.swift
//  OpenIntelligence
//
//  Captures the rank-ordered output of each retrieval stage so the evaluation layer has something
//  to score.
//
//  ## Why this lives in Services/RAG rather than Services/Evaluation
//
//  `OpenIntelligenceEngine` is a separate target whose synchronized root groups include
//  `Services/RAG` but **not** `Services/Evaluation`. `HybridSearchService` compiles into that
//  target, so anything it references must live in a folder the Engine target also builds.
//  Capture therefore sits beside retrieval, and scoring stays in `Services/Evaluation`
//  (`RetrievalStageMetrics.swift`), which is app-target only.
//
//  That constraint happens to match the right layering. Retrieval should know how to report what
//  it did; it should not know how that report is graded. This file deliberately has no dependency
//  on the metric types.
//
//  ## Why the existing audit is not enough
//
//  `RAGAuditSnapshot` already reports `candidatesCount`, `rerankedCount`, `filteredCount`,
//  `droppedCount` and `mmrSelectedCount`. Those are **cardinalities**. They answer "how many
//  survived each stage" and cannot answer "did the relevant chunk survive", which is the only
//  question recall asks. A stage that drops the one correct chunk and keeps forty wrong ones
//  reports an identical count to a stage that does the opposite.
//
//  ## Why a collector rather than a wider return type
//
//  `HybridSearchService.search` returns `[RetrievedChunk]` and has many call sites. Widening the
//  return type would touch every one of them for the benefit of a code path that only runs during
//  evaluation. An optional collector threaded as a defaulted parameter changes no existing call
//  site, and when it is `nil` the only cost is a nil check per stage.
//
//  This deliberately avoids a task-local or a shared singleton. Retrieval runs concurrent child
//  tasks: the FTS5 path awaits a vector task, an FTS5 task, and a structured-row task in parallel.
//  A process-wide sink would interleave stages from overlapping queries with no way to separate
//  them afterwards. One collector per query, passed explicitly, keeps attribution exact.
//

import Foundation

/// Rank-ordered output of one named retrieval stage for one query.
struct RetrievalStageTrace: Sendable {
    let stage: String
    let results: [RetrievedChunk]

    init(stage: String, results: [RetrievedChunk]) {
        self.stage = stage
        self.results = results
    }
}

/// Accumulates per-stage retrieval output for a single query.
///
/// Thread-safe because retrieval stages complete across concurrent child tasks. Recording order is
/// arrival order, so `stages` is not guaranteed to be in pipeline order; use `stages(inOrder:)`
/// when a report needs pipeline order.
///
/// Create one per query and discard it after scoring. Reusing one across queries mixes their
/// stages together, which is exactly the attribution loss this type exists to prevent.
final class RetrievalTraceCollector: @unchecked Sendable {

    /// Canonical stage names.
    ///
    /// The two search paths compute the same logical stages under different local variable names:
    /// `search` produces `keywordResults` from BM25 while `searchWithFTS5` produces
    /// `fts5KeywordResults` from FTS5 plus structured rows. Both record as `.lexical` so a report
    /// has stable columns regardless of which path ran.
    enum Stage: String, CaseIterable {
        /// Dense vector similarity, after the overview filter and before fusion.
        case vector
        /// Lexical scoring: BM25 via `RAGEngine.bm25Scores`, or FTS5 when accelerated.
        case lexical
        /// Reciprocal Rank Fusion of the vector and lexical rankings.
        case fusion
        /// After keyword-match, structure-aware, and anchor boosts.
        case boosted
        /// What hybrid search hands to the reranker: after top-K truncation, sanitising and
        /// reindexing.
        ///
        /// This is a distinct measurement point from `.boosted`, because the truncation between
        /// them can drop the relevant chunk, and distinct from `.final`, because reranking runs
        /// afterwards in `RAGService` and reorders what survives. A recall drop from `.boosted` to
        /// `.candidates` means top-K is too tight; a drop from `.candidates` to `.rerank` means the
        /// cross-encoder demoted the right chunk.
        case candidates
        /// Cross-encoder reranking, in `RAGEngine.rerank`. Recorded by `RAGService`, not by
        /// `HybridSearchService`, because that is where it runs.
        case rerank
        /// What retrieval finally handed downstream: the chunks on the response.
        case final
    }

    private let lock = NSLock()
    private var recorded: [RetrievalStageTrace] = []

    init() {}

    /// Record one stage's rank-ordered output.
    ///
    /// Results must be passed in the order the stage produced them, best-first. Sorting or
    /// deduplicating here would hide the ordering defect that ranking metrics exist to detect.
    func record(_ stage: Stage, results: [RetrievedChunk]) {
        record(stage.rawValue, results: results)
    }

    /// Record a stage under a custom name, for stages outside the canonical set.
    func record(_ stage: String, results: [RetrievedChunk]) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(RetrievalStageTrace(stage: stage, results: results))
    }

    /// Every recorded stage, in arrival order.
    var stages: [RetrievalStageTrace] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Recorded stages sorted into canonical pipeline order.
    ///
    /// Stages not in `Stage` are appended afterwards in arrival order rather than dropped, so an
    /// unrecognised stage name shows up in the report instead of silently disappearing.
    func stages(inOrder order: [Stage] = Stage.allCases) -> [RetrievalStageTrace] {
        let snapshot = stages
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element.rawValue, $0.offset) })

        let known = snapshot
            .filter { rank[$0.stage] != nil }
            .sorted { (rank[$0.stage] ?? 0) < (rank[$1.stage] ?? 0) }
        let unknown = snapshot.filter { rank[$0.stage] == nil }

        return known + unknown
    }
}
