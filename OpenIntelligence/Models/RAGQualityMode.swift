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
        case .standard: return "Comprehensive search with HyDE, compression & citations"
        case .deepThink: return "Multi-step reasoning for complex questions"
        case .maximum: return "Unlimited reasoning until 98% confident"
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

    /// Initial number of chunks to retrieve
    var initialTopK: Int {
        switch canonical {
        case .standard: return 20 // Generous retrieval
        case .deepThink: return 20 // Per-step retrieval
        case .maximum: return 25 // Even more context
        default: return 20
        }
    }

    /// Minimum similarity threshold for retrieval
    var minSimilarity: Float {
        switch canonical {
        case .standard: return 0.32 // Balanced threshold
        case .deepThink: return 0.30 // Slightly broader to catch more context
        case .maximum: return 0.25 // Very broad - catch everything
        default: return 0.32
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
}
