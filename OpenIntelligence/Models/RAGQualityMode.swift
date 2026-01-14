//
//  RAGQualityMode.swift
//  OpenIntelligence
//
//  Controls the accuracy/speed tradeoff for RAG queries.
//  Simplified to 2 user-visible modes: Standard and Deep Think
//

import Foundation

/// Quality mode that controls the accuracy/speed tradeoff
/// User sees only 2 options; internal cases preserved for backward compatibility
enum RAGQualityMode: String, Identifiable, Sendable {
    // User-visible modes
    case standard // All features ON, single-pass (replaces balanced)
    case deepThink // Multi-session agentic reasoning (replaces agentic)

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
        }
    }

    /// Cases visible in UI picker
    static var userVisibleCases: [RAGQualityMode] {
        [.standard, .deepThink]
    }

    var displayName: String {
        switch canonical {
        case .standard: return "Standard"
        case .deepThink: return "Deep Think"
        default: return "Standard"
        }
    }

    var description: String {
        switch canonical {
        case .standard: return "Comprehensive search with HyDE, compression & citations"
        case .deepThink: return "Multi-step reasoning for complex questions"
        default: return "Comprehensive search"
        }
    }

    /// Icon for UI display
    var icon: String {
        switch canonical {
        case .standard: return "sparkles"
        case .deepThink: return "brain.head.profile"
        default: return "sparkles"
        }
    }

    // MARK: - Pipeline Parameters

    /// Initial number of chunks to retrieve
    var initialTopK: Int {
        switch canonical {
        case .standard: return 20 // Generous retrieval
        case .deepThink: return 20 // Per-step retrieval
        default: return 20
        }
    }

    /// Minimum similarity threshold for retrieval
    var minSimilarity: Float {
        switch canonical {
        case .standard: return 0.32 // Balanced threshold
        case .deepThink: return 0.30 // Slightly broader to catch more context
        default: return 0.32
        }
    }

    /// Temperature for generation (lower = more deterministic)
    var temperature: Float {
        switch canonical {
        case .standard: return 0.4 // Slightly deterministic for accuracy
        case .deepThink: return 0.4 // Consistent quality
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
        default: return false
        }
    }

    /// Configuration for iterative retrieval
    var iterativeRetrievalConfig: IterativeRetrievalConfig {
        switch canonical {
        case .standard: return .thorough // High quality
        case .deepThink: return .thorough // Max quality per step
        default: return .thorough
        }
    }

    /// Maximum iterations for iterative retrieval
    var maxRetrievalIterations: Int {
        switch canonical {
        case .standard: return 2
        case .deepThink: return 5 // Orchestrator controls overall flow
        default: return 2
        }
    }

    /// Whether to use the AgenticOrchestrator for multi-session reasoning
    var usesAgenticOrchestrator: Bool {
        canonical == .deepThink
    }

    /// Agentic orchestrator configuration
    var agenticConfig: AgenticConfig {
        .thorough // Always use high quality config
    }
}
