//
//  RAGQualityMode.swift
//  OpenIntelligence
//
//  Controls the accuracy/speed tradeoff for RAG queries.
//  3 user-visible modes: Standard, Deep Think, and Maximum
//

import Foundation

/// Quality mode that controls the accuracy/speed tradeoff
/// User sees 3 options; internal cases preserved for backward compatibility
enum RAGQualityMode: String, Identifiable, Sendable {
    // User-visible modes
    case standard // All features ON, single-pass (replaces balanced)
    case deepThink // Multi-session agentic reasoning (replaces agentic)
    case maximum // Unlimited reasoning until 98% confident - "unhinged" mode

    // Legacy/internal modes (hidden from UI picker, preserved for migrations)
    case fast // Quick answers, less verification
    case balanced // Alias for standard
    case thorough // Maximum accuracy - treated as standard
    case agentic // Alias for deepThink

    var id: String { rawValue }

    /// Canonical form - maps legacy values to new modes
    var canonical: RAGQualityMode {
        switch self {
        case .standard, .balanced, .fast, .thorough: return .standard
        case .deepThink, .agentic: return .deepThink
        case .maximum: return .maximum
        }
    }

    /// Cases visible in UI picker
    static var userVisibleCases: [RAGQualityMode] {
        [.standard, .deepThink, .maximum]
    }

    var displayName: String {
        switch canonical {
        case .standard: return "Standard"
        case .deepThink: return "Deep Think"
        case .maximum: return "Maximum"
        default: return "Standard"
        }
    }

    var description: String {
        switch canonical {
        case .standard: return "Full pipeline with verification gates, graph context & extractive QA"
        case .deepThink: return "Multi-step reasoning + intent routing + calibrated confidence"
        case .maximum: return "Unlimited reasoning with verification gates until 98% confident"
        default: return "Comprehensive search"
        }
    }

    /// Icon for UI display
    var icon: String {
        switch canonical {
        case .standard: return "sparkles"
        case .deepThink: return "brain.head.profile"
        case .maximum: return "flame.fill"
        default: return "sparkles"
        }
    }

    // MARK: - Pipeline Parameters

    /// Initial number of chunks to retrieve (baseline before corpus-size scaling)
    /// Note: RAGService applies dynamic scaling based on actual corpus size
    /// These are minimums - larger corpora will get proportionally more
    var initialTopK: Int {
        switch canonical {
        case .standard: return 30 // Increased from 20 for better baseline coverage
        case .deepThink: return 35 // Per-step retrieval with more context
        case .maximum: return 50 // Maximum context gathering
        default: return 30
        }
    }

    /// Minimum similarity threshold for retrieval
    /// Lower thresholds capture more candidates for re-ranking to filter
    var minSimilarity: Float {
        switch canonical {
        case .standard: return 0.28 // Lowered from 0.32 to catch more edge cases
        case .deepThink: return 0.25 // Broader for multi-hop reasoning
        case .maximum: return 0.20 // Very broad - let re-ranking decide
        default: return 0.28
        }
    }

    /// Temperature for generation (lower = more deterministic)
    var temperature: Float {
        switch canonical {
        case .standard: return 0.4 // Slightly deterministic for accuracy
        case .deepThink: return 0.4 // Consistent quality
        case .maximum: return 0.3 // Very deterministic for precision
        default: return 0.4
        }
    }

    /// Whether to require citations in responses
    var requiresCitations: Bool {
        true // Always require for transparency
    }

    // MARK: - Advanced RAG Features (All ON for Standard)

    /// Whether to use LLM-powered query rewriting
    var usesQueryRewriting: Bool {
        true // Always use for better understanding
    }

    /// Whether to use iterative retrieval (retrieve → assess → refine → retrieve more)
    var usesIterativeRetrieval: Bool {
        switch canonical {
        case .standard: return false // Single comprehensive pass
        case .deepThink: return true // Built into the orchestration loop
        case .maximum: return true // Unlimited iterations
        default: return false
        }
    }

    /// Configuration for iterative retrieval
    var iterativeRetrievalConfig: IterativeRetrievalConfig {
        switch canonical {
        case .standard: return .thorough // High quality
        case .deepThink: return .thorough // Max quality per step
        case .maximum: return .thorough // Max quality
        default: return .thorough
        }
    }

    /// Maximum iterations for iterative retrieval
    var maxRetrievalIterations: Int {
        switch canonical {
        case .standard: return 2
        case .deepThink: return 5 // Orchestrator controls overall flow
        case .maximum: return 20 // Unlimited mode
        default: return 2
        }
    }

    /// Whether to use the AgenticOrchestrator for multi-session reasoning
    var usesAgenticOrchestrator: Bool {
        canonical == .deepThink || canonical == .maximum
    }

    /// Whether this is the unlimited "Maximum" mode
    var isUnlimitedMode: Bool {
        canonical == .maximum
    }

    /// Whether this mode benefits from RAPTOR-lite summaries
    /// Standard mode benefits most from summary-first retrieval for overview queries
    /// Deep Think/Maximum use summaries as starting points but still do deep retrieval
    var benefitsFromSummaries: Bool {
        true // All modes benefit - summaries provide faster initial context
    }

    /// Whether to suggest using summaries for overview queries in this mode
    var preferSummariesForOverview: Bool {
        switch canonical {
        case .standard: return true   // Strongly prefer summaries (massive token savings)
        case .deepThink: return true  // Use summaries as starting point
        case .maximum: return true    // Even Maximum benefits from summary context
        default: return true
        }
    }

    /// Agentic orchestrator configuration
    var agenticConfig: AgenticConfig {
        switch canonical {
        case .maximum: return .unlimited
        default: return .thorough
        }
    }

    // MARK: - Per-Feature Pipeline Toggles (NEW: Comprehensive Mode Control)

    /// Whether to use HyDE (Hypothetical Document Embeddings) for vocabulary bridging
    /// HyDE generates a hypothetical answer first, then embeds it for search
    var usesHyDE: Bool {
        true // All modes benefit from HyDE
    }

    /// Whether to use AI re-ranking after hybrid retrieval
    /// Re-ranking uses a cross-encoder model to re-score chunks for relevance
    var usesReRanking: Bool {
        true // All modes use re-ranking for quality
    }

    /// Whether to use MMR (Maximal Marginal Relevance) diversification
    /// MMR balances relevance with diversity to avoid redundant chunks
    var usesMMR: Bool {
        true // All modes benefit from diversity
    }

    /// MMR lambda parameter (0.0 = max diversity, 1.0 = max relevance)
    var mmrLambda: Float {
        switch canonical {
        case .standard: return 0.60  // Balanced relevance/diversity
        case .deepThink: return 0.55 // Slightly more diversity for multi-hop
        case .maximum: return 0.50   // Maximum diversity for comprehensive coverage
        default: return 0.60
        }
    }

    /// Whether to run verification gates after generation
    /// Gates check: retrieval confidence, numeric sanity, contradiction detection
    var usesVerificationGates: Bool {
        true // All modes verify for anti-hallucination
    }

    /// Minimum confidence to pass verification (below this triggers abstention or retry)
    var verificationConfidenceThreshold: Float {
        switch canonical {
        case .standard: return 0.50  // Standard threshold
        case .deepThink: return 0.60 // Higher bar for deep reasoning
        case .maximum: return 0.98   // 98% confidence required for Maximum
        default: return 0.50
        }
    }

    /// Whether to use corpus-aware query expansion
    /// Expands query with synonyms and domain terms from corpus vocabulary
    var usesQueryExpansion: Bool {
        true // All modes benefit from expansion
    }

    /// Maximum number of query expansion variants to generate
    var maxQueryExpansions: Int {
        switch canonical {
        case .standard: return 9     // Reasonable expansion
        case .deepThink: return 12   // More variants for thorough search
        case .maximum: return 20     // Maximum coverage
        default: return 9
        }
    }

    /// Whether to use container-specific vocabulary for query expansion
    /// Adds domain terms learned from this container's ingested documents
    var usesContainerVocabulary: Bool {
        true // All modes use learned vocabulary
    }

    /// Whether to use parent document retrieval (expand matched chunks with siblings)
    var usesParentDocumentRetrieval: Bool {
        true // All modes benefit from context expansion
    }

    /// Maximum sibling chunks to include during parent document expansion
    var maxSiblingChunks: Int {
        switch canonical {
        case .standard: return 2     // Immediate neighbors
        case .deepThink: return 3    // Broader context
        case .maximum: return 5      // Maximum context window
        default: return 2
        }
    }

    /// Whether to use contextual compression to extract relevant content
    var usesContextualCompression: Bool {
        switch canonical {
        case .standard: return true   // Compress for efficiency
        case .deepThink: return true  // Compress for focus
        case .maximum: return false   // Keep full context in Maximum mode
        default: return true
        }
    }

    /// Boost weight for specification-heavy chunks (tables, numbered lists)
    /// Higher = prefer structured/spec content for lookup queries
    var specificationBoostWeight: Float {
        switch canonical {
        case .standard: return 1.2   // Moderate boost
        case .deepThink: return 1.3  // Stronger preference for specs
        case .maximum: return 1.5    // Maximum spec preference
        default: return 1.2
        }
    }

    /// Whether to use conversation memory for multi-turn context
    var usesConversationMemory: Bool {
        true // All modes benefit from conversation context
    }

    /// Maximum conversation turns to retain in memory
    var maxConversationTurns: Int {
        switch canonical {
        case .standard: return 5     // Recent context
        case .deepThink: return 10   // Extended context
        case .maximum: return 20     // Maximum context
        default: return 5
        }
    }

    // MARK: - Feature Configuration Summary

    /// Returns a dictionary of all feature toggles for logging/debugging
    var featureToggles: [String: Any] {
        [
            "usesHyDE": usesHyDE,
            "usesReRanking": usesReRanking,
            "usesMMR": usesMMR,
            "mmrLambda": mmrLambda,
            "usesVerificationGates": usesVerificationGates,
            "verificationConfidenceThreshold": verificationConfidenceThreshold,
            "usesQueryExpansion": usesQueryExpansion,
            "maxQueryExpansions": maxQueryExpansions,
            "usesContainerVocabulary": usesContainerVocabulary,
            "usesParentDocumentRetrieval": usesParentDocumentRetrieval,
            "maxSiblingChunks": maxSiblingChunks,
            "usesContextualCompression": usesContextualCompression,
            "specificationBoostWeight": specificationBoostWeight,
            "usesConversationMemory": usesConversationMemory,
            "maxConversationTurns": maxConversationTurns,
            "usesQueryRewriting": usesQueryRewriting,
            "usesIterativeRetrieval": usesIterativeRetrieval,
            "usesAgenticOrchestrator": usesAgenticOrchestrator,
            "initialTopK": initialTopK,
            "minSimilarity": minSimilarity,
            "temperature": temperature,
        ]
    }
}
