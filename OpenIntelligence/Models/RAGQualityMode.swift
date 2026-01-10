//
//  RAGQualityMode.swift
//  OpenIntelligence
//
//  Controls the accuracy/speed tradeoff for RAG queries.
//

import Foundation

/// Quality mode that controls the accuracy/speed tradeoff
enum RAGQualityMode: String, CaseIterable, Identifiable, Sendable {
    case fast // Quick answers, less verification
    case balanced // Default: good accuracy, reasonable speed
    case thorough // Maximum accuracy, multiple retrieval passes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .thorough: return "Accuracy"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Quick responses with basic retrieval"
        case .balanced: return "Good accuracy with smart context selection"
        case .thorough: return "Maximum accuracy with strict gating and citations"
        }
    }

    /// Icon for UI display
    var icon: String {
        switch self {
        case .fast: return "hare"
        case .balanced: return "scale.3d"
        case .thorough: return "checkmark.seal"
        }
    }

    // MARK: - Pipeline Parameters

    /// Initial number of chunks to retrieve
    var initialTopK: Int {
        switch self {
        case .fast: return 10
        case .balanced: return 15
        case .thorough: return 25
        }
    }

    /// Minimum similarity threshold for retrieval
    var minSimilarity: Float {
        switch self {
        case .fast: return 0.28
        case .balanced: return 0.35
        case .thorough: return 0.50
        }
    }

    /// Temperature for generation (lower = more deterministic)
    var temperature: Float {
        switch self {
        case .fast: return 0.7
        case .balanced: return 0.5
        case .thorough: return 0.3
        }
    }

    /// Whether to require citations in responses
    var requiresCitations: Bool {
        switch self {
        case .fast: return false
        case .balanced: return true
        case .thorough: return true
        }
    }

    // MARK: - Advanced RAG Features (v2.0)

    /// Whether to use LLM-powered query rewriting
    var usesQueryRewriting: Bool {
        switch self {
        case .fast: return false // Skip for speed
        case .balanced: return true // Use for better understanding
        case .thorough: return true // Always use
        }
    }

    /// Whether to use iterative retrieval (retrieve → assess → refine → retrieve more)
    var usesIterativeRetrieval: Bool {
        switch self {
        case .fast: return false // Single-pass only
        case .balanced: return false // Single-pass by default (toggle available)
        case .thorough: return true // Multi-pass for accuracy
        }
    }

    /// Configuration for iterative retrieval
    var iterativeRetrievalConfig: IterativeRetrievalConfig {
        switch self {
        case .fast: return .fast
        case .balanced: return .default
        case .thorough: return .thorough
        }
    }

    /// Maximum iterations for iterative retrieval
    var maxRetrievalIterations: Int {
        switch self {
        case .fast: return 1
        case .balanced: return 2
        case .thorough: return 4
        }
    }
}
