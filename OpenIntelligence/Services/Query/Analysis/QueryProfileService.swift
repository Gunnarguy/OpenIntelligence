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
    func adjustedHybridWeights(from retrievalConfig: RetrievalConfig) -> (vectorWeight: Float, keywordWeight: Float) {
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
