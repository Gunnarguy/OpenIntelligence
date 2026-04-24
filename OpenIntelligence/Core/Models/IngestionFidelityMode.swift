//
//  IngestionFidelityMode.swift
//  OpenIntelligence
//

import Foundation

/// Controls how aggressively document ingestion preserves full-resolution source fidelity.
enum IngestionFidelityMode: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case high
    case maximum

    static let storageKey = "ingestionFidelityMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }

    var shortDescription: String {
        switch self {
        case .balanced:
            return "Adaptive heuristics with full-res escalation only on high-risk pages"
        case .high:
            return "More aggressive full-res parsing for small text, tables, and columns"
        case .maximum:
            return "Bias toward maximum source preservation before chunking and retrieval"
        }
    }

    var uiBadgeText: String {
        switch self {
        case .balanced: return "Default"
        case .high: return "Accuracy"
        case .maximum: return "Full Power"
        }
    }

    var fineTextRiskThreshold: Double {
        switch self {
        case .balanced: return 0.60
        case .high: return 0.45
        case .maximum: return 0.30
        }
    }

    static var current: IngestionFidelityMode {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let mode = IngestionFidelityMode(rawValue: raw)
        {
            return mode
        }

        return .balanced
    }
}
