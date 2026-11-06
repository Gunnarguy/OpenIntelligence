//
//  AgenticOrchestrator+Types.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

/// Represents one step in the agentic reasoning loop
struct ThinkingStep: Identifiable, Sendable {
    let id: UUID
    let type: StepType
    let input: String
    let output: String
    let tokensUsed: Int
    let duration: TimeInterval
    let timestamp: Date
    /// Live confidence level (0-1) for Maximum mode progress tracking
    var confidence: Float? = nil

    enum StepType: String, Sendable {
        case planning = "🎯 Planning approach"
        case searching = "🔍 Searching documents"
        case expanding = "🕸️ Expanding context"
        case analyzing = "🧠 Analyzing results"
        case synthesizing = "✨ Synthesizing answer"
        case refining = "🔧 Refining response"
        case reformulating = "🔄 Trying different angle"
        case verifying = "✅ Verifying answer"

        /// Display name for UI
        var displayName: String { rawValue }

        /// Map to ThinkingEvent.Kind for UI integration
        /// Every step type here maps to the kind that describes what it actually
        /// does. It previously collapsed eight step types onto four kinds, and two
        /// of those collapses were wrong in a user-visible way:
        ///
        ///   - `.analyzing` is a multi-session reasoning pass, and it mapped to
        ///     `.rerank`. Device traces and the live UI therefore showed
        ///     "RE-RANKING · Session 6/50" for work that never touched the reranker,
        ///     fifteen or twenty rows in a row.
        ///   - `.verifying` is the verification gate, and it mapped to `.rerank` too,
        ///     which is why `.verification` never appeared in any trace despite the
        ///     gates running on every query.
        ///
        /// `.reformulating` and `.expanding` were also folded into plain `.retrieval`,
        /// hiding query rewriting and iterative expansion as undifferentiated
        /// "Retrieval". Each now reports itself.
        var thinkingKind: ThinkingEvent.Kind {
            switch self {
            case .planning: return .planning
            case .searching: return .retrieval
            case .reformulating: return .queryRewrite
            case .expanding: return .iterative
            case .analyzing: return .reasoning
            case .verifying: return .verification
            case .synthesizing: return .generation
            case .refining: return .selfRag
            }
        }
    }
}

/// Extension to map ThinkingEvent.Kind back to ThinkingStep.StepType for verbose pipeline events
extension ThinkingEvent.Kind {
    /// Convert ThinkingEvent.Kind to ThinkingStep.StepType for detailed event forwarding
    nonisolated var toStepType: ThinkingStep.StepType {
        switch self {
        case .planning, .agentic:
            return .planning
        case .embedding, .retrieval, .hyde, .queryRewrite, .bm25, .vectorSearch, .parentDoc, .iterative:
            return .searching
        case .rerank, .rrf, .mmr:
            return .analyzing
        case .gating, .grounding, .selfRag, .factBank, .verification, .confidence, .reasoning:
            return .analyzing
        case .context, .compression, .lostInMiddle, .graphPack:
            return .expanding
        case .generation, .toolCall, .extractive:
            return .synthesizing
        case .fallback, .warning:
            return .refining
        case .intentRoute:
            return .planning
        case .imagePlayground:
            return .synthesizing
        }
    }
}

/// Configuration for the agentic loop
struct AgenticConfig: Sendable {
    /// Maximum thinking steps before forcing synthesis (use Int.max for "unlimited")
    let maxSteps: Int

    /// Maximum total tokens across all steps (use Int.max for "unlimited")
    let maxTotalTokens: Int

    /// Whether to stream intermediate results
    let streamIntermediateResults: Bool

    /// Minimum confidence threshold to stop early (high = good enough to answer)
    let confidenceThreshold: Float

    /// Similarity threshold below which we escalate to deeper retrieval
    let escalationThreshold: Float

    /// Whether this is an "unlimited" configuration (keep going until confident)
    var isUnlimited: Bool {
        maxSteps >= 50  // Practical "unlimited" - 50+ steps is extreme
    }

    nonisolated static let defaultConfig = AgenticConfig(
        maxSteps: 5,
        maxTotalTokens: 16000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.85,
        escalationThreshold: 0.35  // If top result < 35% similarity, try harder
    )

    nonisolated static let fast = AgenticConfig(
        maxSteps: 2,
        maxTotalTokens: 8000,
        streamIntermediateResults: false,
        confidenceThreshold: 0.7,
        escalationThreshold: 0.25
    )

    nonisolated static let thorough = AgenticConfig(
        maxSteps: 8,
        maxTotalTokens: 32000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.95,
        escalationThreshold: 0.45  // Higher bar = more likely to escalate
    )

    /// Unlimited Deep Think - keeps reasoning until 98% confident or thermal limit
    /// Since Neural Engine uses disk-backed weights (not RAM), we can go much deeper
    /// Only thermal throttling and user patience are the real limits
    nonisolated static let unlimited = AgenticConfig(
        maxSteps: 50,  // Realistically 5-15 minutes - thermal will stop us first
        maxTotalTokens: 200_000,  // 50 sessions × 4K = 200K+ effective tokens
        streamIntermediateResults: true,
        confidenceThreshold: 0.98,  // Only stop when VERY confident
        escalationThreshold: 0.50  // Aggressive escalation - always try harder
    )
}

/// Result of the agentic reasoning loop
struct AgenticResult: Sendable {
    let finalAnswer: String
    let steps: [ThinkingStep]
    let totalTokens: Int
    let totalDuration: TimeInterval
    let confidence: Float
    let sourcesUsed: Int
    /// All chunks retrieved across tool calls (for UnifiedMetricsBar)
    let retrievedChunks: [RetrievedChunk]

    /// Compressed summary of the reasoning chain (for UI display)
    var reasoningSummary: String {
        steps.map { "• \($0.type.rawValue): \($0.output.prefix(100))..." }.joined(separator: "\n")
    }
}


// MARK: - Errors

enum AgenticError: LocalizedError {
    case serviceUnavailable
    case maxStepsExceeded
    case tokenLimitReached
    case planningFailed

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "RAG service unavailable"
        case .maxStepsExceeded:
            return "Maximum reasoning steps exceeded"
        case .tokenLimitReached:
            return "Token limit reached across sessions"
        case .planningFailed:
            return "Failed to decompose query into sub-questions"
        }
    }
}

// MARK: - Reasoning Chain Architecture

/// Configuration for chained reasoning sessions
/// Each session gets its own 4096 token budget, chained together for 16K+ effective context
struct ReasoningChainConfig: Sendable {
    /// Number of chained sessions (each has 4096 tokens)
    let sessionCount: Int

    /// Maximum context chars per session (~2800 tokens safe for 4096 limit)
    let maxContextPerSession: Int

    /// Maximum insight chars to pass between sessions
    let maxInsightLength: Int

    /// Light config for Standard mode - faster with 3 sessions
    /// 3 × 4096 = 12K+ effective tokens (vs single 4K)
    nonisolated static let light = ReasoningChainConfig(
        sessionCount: 3,  // 3 × 4096 = 12K+ effective tokens
        maxContextPerSession: 3200,
        maxInsightLength: 1500  // Keep full findings, not snippets
    )

    nonisolated static let standard = ReasoningChainConfig(
        sessionCount: 4,  // 4 × 4096 = 16K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 2000  // Keep full findings, not snippets
    )

    nonisolated static let deep = ReasoningChainConfig(
        sessionCount: 5,  // 5 × 4096 = 20K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 2500  // Keep full findings, not snippets
    )

    /// Unlimited config - Maximum mode: up to 50 sessions until 98% confident
    /// Since Neural Engine is disk-backed, memory isn't the limit - thermal/user patience is
    /// 50 sessions × 4K = 200K+ effective tokens (realistically takes 5-15 minutes)
    nonisolated static let unlimited = ReasoningChainConfig(
        sessionCount: 50,  // 50 × 4096 = 200K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 3000  // Preserve maximum detail between sessions
    )

    /// Per-cluster config for multi-chain Maximum mode
    /// Each cluster gets its own chain with focused context
    nonisolated static let clusterChain = ReasoningChainConfig(
        sessionCount: 8,  // 8 sessions per cluster
        maxContextPerSession: 3200,
        maxInsightLength: 2000
    )
}

// MARK: - Multi-Chain Configuration

/// Configuration for parallel multi-chain reasoning
/// Splits documents into clusters, runs parallel chains, synthesizes results
struct MultiChainConfig: Sendable {
    /// Maximum number of parallel document clusters
    let maxClusters: Int

    /// Minimum documents per cluster (avoid tiny clusters)
    let minDocsPerCluster: Int

    /// Sessions per cluster chain
    let sessionsPerCluster: Int

    /// Sessions for final synthesis chain
    let synthesisSessions: Int

    /// Maximum parallel chains (thermal/CPU limit)
    let maxParallelChains: Int

    /// Default for Maximum mode: 4 clusters × 8 sessions + 3 synthesis = 35 chains
    nonisolated static let maximum = MultiChainConfig(
        maxClusters: 5,
        minDocsPerCluster: 2,
        sessionsPerCluster: 8,
        synthesisSessions: 4,
        maxParallelChains: 3  // Run 3 at a time to avoid thermal throttling
    )

    /// Light multi-chain for faster exploration
    nonisolated static let light = MultiChainConfig(
        maxClusters: 3,
        minDocsPerCluster: 2,
        sessionsPerCluster: 4,
        synthesisSessions: 2,
        maxParallelChains: 2
    )
}

/// Result from a multi-chain execution
struct MultiChainResult: Sendable {
    let finalAnswer: String
    let clusterInsights: [ClusterInsight]
    let totalTokens: Int
    let totalSessions: Int
    let totalDuration: TimeInterval
    let confidence: Float

    struct ClusterInsight: Sendable {
        let clusterName: String
        let documents: [String]
        let insight: String
        let chainInsights: [String]  // Individual session insights for reasoning trace
        let tokensUsed: Int
        let sessionsRun: Int
    }
}

/// A cluster of documents for parallel processing
struct DocumentCluster {
    let name: String
    var documents: [String]
    var chunks: [RetrievedChunk]
}

struct DocumentSemanticProfile {
    let documentName: String
    let chunks: [RetrievedChunk]
    let totalScore: Float
    let weightedTerms: [String: Int]
}

/// Result from a reasoning chain
struct ReasoningChainResult: Sendable {
    let finalAnswer: String
    let chainInsights: [String]  // Insights from each session
    let totalTokens: Int
    let sessionCount: Int
    let confidence: Float
    let sources: [String]

    /// Fraction of the query's sub-questions the chain actually answered, from `FactBank`.
    ///
    /// Carried out of the chain because the decision about whether to research further was being
    /// made by reading the final answer's prose for phrases like "do not specify", while this
    /// measured figure was computed, used for the chain's own early-stop check, and then discarded.
    let evidenceCoverage: Float

    /// The coverage the chain was aiming for, from `AgenticPolicyService.evidenceCoverageTarget`.
    ///
    /// Carried alongside the achieved figure so the comparison needs no second threshold. Finishing
    /// below your own target is the definition of not having finished, and it is a measurement
    /// rather than a guess about wording.
    let evidenceCoverageTarget: Float

    /// Sub-questions still unanswered when the chain stopped.
    ///
    /// These are what recursive research should go and look for. Re-running the original query
    /// searches for what was already found; searching the gaps searches for what is missing.
    let unansweredQuestions: [String]

    /// The chunks in the exact order the chain labelled them `[S1]...[Sn]`.
    ///
    /// Citations were resolved against the wrong array for as long as the chain has existed. The
    /// chain labels sources over `routeChunksByTitle`'s output, which is a **reordering** of the
    /// caller's array, and it labels them per rotating window. `runVerificationLoop` then resolved
    /// `[Sn]` against `allRetrievedChunks`, the pre-sort, pre-routing order. Two independent
    /// mismatches, so `verifyCitations` graded nearly every citation against an unrelated chunk,
    /// drove `groundingScore` toward zero, and tripped the retry that discards the answer.
    ///
    /// `allRetrievedChunks -> sorted -> routed` are all permutations of one set with nothing
    /// dropped, so handing this back is a reordering of what the caller already had, not a
    /// different or smaller set of sources.
    let routedChunks: [RetrievedChunk]
}
