//
//  QueryProfileService.swift
//  OpenIntelligence
//
//  Canonical per-query profile used to keep routing, retrieval, and reasoning
//  decisions aligned across the pipeline.
//

import Foundation

/// Shared query understanding state for a single question.
struct QueryProfile: Sendable {
    let query: String
    let wordCount: Int
    let isTrivial: Bool
    let adaptiveComplexity: QueryComplexity
    let reasoningComplexity: QueryComplexityResult
    let answerIntent: AnswerIntent
    let searchIntent: QueryIntent
    let routingClassification: QueryClassification
    let abstractionLevelsToSearch: [ChunkAbstractionLevel]

    /// Literal manual/spec lookups should stay close to the user's original wording.
    var isSimpleGroundedLookup: Bool {
        answerIntent.isExtractiveFirst || (isTrivial && wordCount <= 8)
    }

    /// Apply the shared hybrid-weight policy once per query.
    ///
    /// The 0.35 floor is the interesting number here. It guarantees the dense arm at least 35% of
    /// the fusion no matter how badly it is performing. That is a sound default when both arms are
    /// comparable, which is what the RRF literature assumes. On the 2026-08-12 benchmark they were
    /// not comparable: `vector` scored MRR@10 0.28 against `lexical` 0.65, and fusion came out
    /// measurably *worse* than the lexical arm alone (26 wins to 6 over 72 paired cases, exact sign
    /// test p=0.0005). The floor is what prevents the policy from correcting for that.
    ///
    /// Changing the floor is a product decision and is deliberately not made here. The benchmark
    /// override below exists so the question can be answered with a measurement first.
    func adjustedHybridWeights(from retrievalConfig: RetrievalConfig) -> (vectorWeight: Float, keywordWeight: Float) {
        #if DEBUG
        // Benchmark-only override, seeded by DebugRAGValidationHarness from
        // --rag-validation-vector-weight. Absent in every normal run, including the test suite,
        // because nothing else writes this key. Bypasses the clamp on purpose: the clamp is the
        // hypothesis under test.
        if let override = BenchmarkHybridWeightOverride.current {
            return (override, 1 - override)
        }
        #endif
        let adjustment = searchIntent.weightAdjustment
        let vectorWeight = max(0.35, min(0.65, retrievalConfig.vectorWeight + adjustment.vectorDelta))
        let keywordWeight = max(0.35, min(0.65, retrievalConfig.lexicalWeight + adjustment.keywordDelta))
        return (vectorWeight, keywordWeight)
    }
}

/// Builds a canonical profile so query intent, routing, and complexity are evaluated once.
final class QueryProfileService {
    static let shared = QueryProfileService()

    func buildProfile(
        for query: String,
        queryEnhancer: QueryEnhancementService? = nil,
        queryRouter: QueryRouterService? = nil,
        routingEnabled: Bool = true
    ) async -> QueryProfile {
        let enhancer = queryEnhancer ?? QueryEnhancementService()
        let answerIntent = enhancer.classifyAnswerIntent(query)
        let searchIntent = enhancer.classifyIntent(query)
        let reasoningComplexity = QueryComplexityAnalyzer.shared.analyze(query)
        let adaptiveComplexity = QueryComplexity.estimate(from: query)
        let wordCount = Self.wordCount(of: query)
        let isTrivial = Self.isTrivialQuery(query)

        let routingClassification: QueryClassification
        let abstractionLevelsToSearch: [ChunkAbstractionLevel]
        if routingEnabled, let queryRouter {
            let classification = await queryRouter.classifyQuery(query)
            routingClassification = classification
            abstractionLevelsToSearch = await queryRouter.abstractionLevelsToSearch(for: classification)
        } else {
            routingClassification = QueryClassification(
                queryType: .detail,
                confidence: 0.3,
                reasoning: routingEnabled
                    ? "Query router unavailable; defaulting to detail search"
                    : "Query routing disabled"
            )
            abstractionLevelsToSearch = [.detail]
        }

        return QueryProfile(
            query: query,
            wordCount: wordCount,
            isTrivial: isTrivial,
            adaptiveComplexity: adaptiveComplexity,
            reasoningComplexity: reasoningComplexity,
            answerIntent: answerIntent,
            searchIntent: searchIntent,
            routingClassification: routingClassification,
            abstractionLevelsToSearch: abstractionLevelsToSearch
        )
    }

    nonisolated static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    nonisolated static func isTrivialQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let tokenCount = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if tokenCount <= 1 {
            return true
        }

        let lower = trimmed.lowercased()
        let trivialSet: Set<String> = [
            "test",
            "help",
            "hello",
            "hi",
            "hey",
            "ok",
            "okay",
            "thanks",
            "thank you",
            "yes",
            "yep",
            "yeah",
        ]
        return trivialSet.contains(lower)
    }
}


#if DEBUG
/// Reads the benchmark's fusion-weight override once.
///
/// Separate from the harness so `QueryProfileService` does not depend on it, and cached so the
/// lookup does not repeat per query. `nil` unless a benchmark run set it, which means shipped
/// behaviour is unchanged and the value cannot leak into a normal launch.
enum BenchmarkHybridWeightOverride {
    static let current: Float? = {
        guard UserDefaults.standard.object(forKey: "benchmarkVectorWeight") != nil else { return nil }
        let value = Float(UserDefaults.standard.double(forKey: "benchmarkVectorWeight"))
        guard value >= 0, value <= 1 else { return nil }
        return value
    }()
}
#endif
