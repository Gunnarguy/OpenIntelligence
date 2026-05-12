//
//  RetrievalPolicyService.swift
//  OpenIntelligence
//
//  Centralized retrieval thresholds and fallback policy so Standard, Deep Think,
//  and Maximum do not drift into contradictory search behavior.
//

import Foundation

struct RetrievalMetrics: Sendable {
    let topSimilarity: Float
    let secondSimilarity: Float
    let averageTopFive: Float
    let candidateCount: Int
}

struct RetrievalFilteringDecision: Sendable {
    let baseMinSimilarity: Float
    let dynamicMinSimilarity: Float
    let vocabularyMismatch: Bool
    let acceptanceOverride: Bool
}

struct RetrievalCascadeDecision: Sendable {
    let triggerThreshold: Float
    let lexicalWeight: Float
    let vectorWeight: Float
    let topK: Int
}

enum AgenticRetrievalStage: Sendable {
    case search
    case focusedSubquery
    case crossReference
    case graphExpansion
    case coverageExpansion
    case queryVariation
    case fallback
}

enum RetrievalPolicyService {
    static func filteringDecision(
        for profile: QueryProfile,
        qualityMode: RAGQualityMode,
        retrievalConfig: RetrievalConfig,
        lenient: Bool,
        metrics: RetrievalMetrics
    ) -> RetrievalFilteringDecision {
        let baseMin = baseMinSimilarity(for: qualityMode, retrievalConfig: retrievalConfig)
        var dynamicMin = lenient ? min(baseMin, 0.35) : baseMin

        let vocabularyMismatch = metrics.candidateCount >= 5
            && metrics.topSimilarity < 0.25
            && metrics.averageTopFive < 0.20

        if vocabularyMismatch {
            let scoreSpread = metrics.topSimilarity - metrics.averageTopFive
            dynamicMin = max(0.10, metrics.averageTopFive - scoreSpread)
        } else if !lenient, metrics.averageTopFive > 0, metrics.averageTopFive < baseMin {
            dynamicMin = max(0.15, metrics.averageTopFive - 0.05)
        }

        if profile.answerIntent == .procedure {
            dynamicMin = max(dynamicMin, 0.25)
        } else if profile.answerIntent.isExtractiveFirst || profile.searchIntent == .keyword {
            dynamicMin = min(dynamicMin, max(0.18, baseMin - 0.04))
        }

        var acceptanceOverride = vocabularyMismatch
            || metrics.topSimilarity >= 0.50
            || (metrics.topSimilarity >= 0.38 && (metrics.topSimilarity - metrics.averageTopFive) >= 0.05)
            || ((metrics.topSimilarity - metrics.secondSimilarity) >= 0.07)
            || (metrics.topSimilarity >= 0.15 && metrics.candidateCount >= 10)

        if profile.answerIntent.isExtractiveFirst {
            acceptanceOverride = acceptanceOverride || metrics.topSimilarity >= max(0.18, dynamicMin - 0.03)
        }

        return RetrievalFilteringDecision(
            baseMinSimilarity: baseMin,
            dynamicMinSimilarity: dynamicMin,
            vocabularyMismatch: vocabularyMismatch,
            acceptanceOverride: acceptanceOverride
        )
    }

    static func cascadeDecision(
        for profile: QueryProfile,
        qualityMode: RAGQualityMode,
        retrievalConfig: RetrievalConfig,
        effectiveTopK: Int,
        totalStored: Int,
        metrics: RetrievalMetrics,
        usedRetrievalCascade: Bool
    ) -> RetrievalCascadeDecision? {
        guard !usedRetrievalCascade, !profile.isTrivial else { return nil }

        let allowLookupCascade = profile.answerIntent.isExtractiveFirst
            && (profile.wordCount <= 8 || profile.searchIntent == .keyword)

        guard !profile.answerIntent.isExtractiveFirst || allowLookupCascade else {
            return nil
        }

        let baseMin = baseMinSimilarity(for: qualityMode, retrievalConfig: retrievalConfig)
        let triggerFloor: Float = profile.answerIntent.isExtractiveFirst ? 0.28 : 0.30
        let triggerBoost: Float = profile.answerIntent.isExtractiveFirst ? 0.02 : 0.05
        let triggerThreshold = min(0.45, max(triggerFloor, baseMin + triggerBoost))

        let needsMoreCandidates = metrics.candidateCount < max(4, effectiveTopK / 2)
        let weakTopResult = metrics.topSimilarity < triggerThreshold
        let weakBreadth = metrics.averageTopFive < max(triggerFloor - 0.05, baseMin)

        guard weakTopResult || needsMoreCandidates || weakBreadth else {
            return nil
        }

        let lexicalBoost: Float
        if profile.answerIntent.isExtractiveFirst || profile.searchIntent == .keyword || profile.wordCount <= 6 {
            lexicalBoost = 0.20
        } else {
            lexicalBoost = 0.12
        }

        var cascadeLexical = min(0.65, retrievalConfig.lexicalWeight + lexicalBoost)
        var cascadeVector = max(0.35, 1.0 - cascadeLexical)
        let total = cascadeLexical + cascadeVector
        cascadeLexical /= total
        cascadeVector /= total

        return RetrievalCascadeDecision(
            triggerThreshold: triggerThreshold,
            lexicalWeight: cascadeLexical,
            vectorWeight: cascadeVector,
            topK: min(max(effectiveTopK * 4, effectiveTopK * 3), max(1, totalStored))
        )
    }

    static func parentDocumentConfig(
        for profile: QueryProfile,
        qualityMode: RAGQualityMode,
        maxSiblingChunks: Int,
        useAgentic: Bool
    ) -> ParentDocumentService.Config {
        if profile.answerIntent == .procedure {
            return .procedural
        }

        if useAgentic || profile.routingClassification.queryType == .crossTopic {
            return .thorough
        }

        return ParentDocumentService.Config(
            maxSiblingsPerSide: maxSiblingChunks,
            maxExpandedTokens: profile.answerIntent.isExtractiveFirst ? 1600 : 2000,
            allowCrossPageExpansion: false,
            minRelevanceForExpansion: profile.answerIntent.isExtractiveFirst ? 0.12 : 0.15
        )
    }

    static func agenticMinSimilarity(
        for qualityMode: RAGQualityMode,
        stage: AgenticRetrievalStage
    ) -> Float {
        let base = max(0.08, qualityMode.minSimilarity * 0.5)

        switch stage {
        case .search:
            return min(0.18, max(0.10, base))
        case .focusedSubquery:
            return 0.25
        case .crossReference:
            return 0.10
        case .graphExpansion:
            return 0.20
        case .coverageExpansion:
            return 0.20
        case .queryVariation:
            return 0.25
        case .fallback:
            return max(0.08, min(0.15, base - 0.03))
        }
    }

    private static func baseMinSimilarity(
        for qualityMode: RAGQualityMode,
        retrievalConfig: RetrievalConfig
    ) -> Float {
        if retrievalConfig.minSimilarity >= 0.45 || retrievalConfig.requireExplicitCitations {
            return retrievalConfig.minSimilarity
        }

        return min(retrievalConfig.minSimilarity, qualityMode.minSimilarity)
    }
}
