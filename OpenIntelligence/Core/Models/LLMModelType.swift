//
//  LLMModelType.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
//

import Foundation

/// Supported high-level LLM integrations that can power the chat experience.
/// NOTE: Local downloadable models (GGUF, CoreML, MLX) have been removed.
/// The app now uses Apple Intelligence (with PCC), On-Device Analysis, and Open Protocol Layer third-party models.
enum LLMModelType: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple_intelligence" // On-device + PCC automatic
    case onDeviceAnalysis = "on_device_analysis" // Extractive QA, always available

    var id: String { rawValue }

    /// Returns true if this is a deprecated/removed model type that should migrate
    static func isDeprecatedRawValue(_ raw: String) -> Bool {
        let deprecated = ["gguf_local", "coreml_local", "mlx_local", "chatgpt_extension", "openai"]
        return deprecated.contains(raw)
    }

    /// Migrates deprecated model selections to the best available option
    static func migrate(from raw: String) -> LLMModelType {
        if isDeprecatedRawValue(raw) {
            return .appleIntelligence
        }
        return LLMModelType(rawValue: raw) ?? .appleIntelligence
    }
}

// MARK: - Model capability card metadata

/// Compact stats surfaced in the comparison sheet ("Pokémon card" style).
struct ModelCapabilityCardInfo {
    let emoji: String
    let nickname: String
    let tagline: String
    let chips: [ModelCapabilityChipInfo]
    let stats: [ModelCapabilityStatInfo]
    let footer: String
}

/// Visual chips for supported modalities or behaviors.
struct ModelCapabilityChipInfo: Identifiable, Hashable {
    enum Tone: String {
        case accent
        case info
        case success
        case warning
        case neutral
    }

    let id = UUID()
    let icon: String
    let label: String
    let detail: String?
    let tone: Tone
}

/// Key stats rendered inside the capability grid.
struct ModelCapabilityStatInfo: Identifiable, Hashable {
    enum Accent: String {
        case accent
        case success
        case warning
        case info
        case neutral
    }

    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let detail: String
    let accent: Accent
}

extension LLMModelType {
    /// User-facing name surfaced inside pickers and diagnostics.
    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "AFM 3 Core Advanced"
        case .onDeviceAnalysis:
            return "On-Device Analysis"
        }
    }

    /// Detailed description of the model for preview/comparison views
    var description: String {
        switch self {
        case .appleIntelligence:
            return
                "On-device Apple Foundation Models with automatic Private Cloud Compute fallback for complex queries. Zero data retention, end-to-end encrypted."
        case .onDeviceAnalysis:
            return
                "Extractive question answering using NaturalLanguage framework. No generative AI, purely extractive from your documents. Always available offline."
        }
    }

    /// SF Symbol identifier used when rendering this model inside pickers.
    var iconName: String {
        switch self {
        case .appleIntelligence:
            return "sparkles"
        case .onDeviceAnalysis:
            return "doc.text.magnifyingglass"
        }
    }

    var category: String {
        switch self {
        case .appleIntelligence:
            return "Hybrid"
        case .onDeviceAnalysis:
            return "Local"
        }
    }

    var privacyLevel: String {
        switch self {
        case .appleIntelligence:
            return "End-to-end encrypted"
        case .onDeviceAnalysis:
            return "On-device"
        }
    }

    var requiresNetwork: Bool {
        switch self {
        case .onDeviceAnalysis:
            return false
        case .appleIntelligence:
            return false // Works on-device, PCC is optional
        }
    }

    /// Context window size description for UI display.
    /// Per TN3193: On-device context is 4,096 tokens. PCC may expand this.
    ///
    /// The public Foundation Models SDK exposes no separately selectable
    /// on-device model identities, so this description does not assert a
    /// parameter count. See `Docs/LIMITATIONS.md`.
    var contextDescription: String {
        switch self {
        case .appleIntelligence:
            return "4K on-device, expanded via Private Cloud Compute"
        case .onDeviceAnalysis:
            return "No generation context"
        }
    }

    var capabilities: [String] {
        switch self {
        case .appleIntelligence:
            return [
                "Function calling",
                "Private Cloud Compute",
                "Low latency",
                "Zero retention",
            ]
        case .onDeviceAnalysis:
            return [
                "Extractive QA",
                "Deterministic",
                "Instant answers",
                "Always available",
            ]
        }
    }

    var isLocal: Bool {
        switch self {
        case .onDeviceAnalysis:
            return true
        case .appleIntelligence:
            return true // Primarily on-device
        }
    }

    var isPrivate: Bool {
        switch self {
        case .appleIntelligence, .onDeviceAnalysis:
            return true
        }
    }

    var isFast: Bool {
        return true // All options are fast
    }

    var quality: Bool {
        switch self {
        case .appleIntelligence:
            return true
        case .onDeviceAnalysis:
            return false // Extractive only, no generation
        }
    }

    /// Pokémon card style metadata surfaced in ModelComparisonSheet.
    var capabilityCard: ModelCapabilityCardInfo {
        switch self {
        case .appleIntelligence:
            return ModelCapabilityCardInfo(
                emoji: "🍎",
                nickname: "AFM 3 Ecosystem",
                tagline: "Evidence-first routing between Apple's on-device model and Private Cloud Compute.",
                chips: [
                    .init(icon: "cpu", label: "On-Device", detail: "Apple Intelligence", tone: .accent),
                    .init(icon: "cloud.fill", label: "PCC", detail: "Private Cloud", tone: .info),
                    .init(icon: "wand.and.stars", label: "Actions", detail: "App tools", tone: .success),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "< 0.8 s", detail: "Median TTFT", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "≈65 tok/s", detail: "Neural Engine streaming", accent: .accent),
                    .init(icon: "square.stack.3d.down.right.fill", label: "Context", value: "4K+", detail: "On-device, more via PCC", accent: .info),
                    .init(icon: "lock.shield.fill", label: "Privacy", value: "Zero-retention", detail: "Encrypted PCC hops", accent: .success),
                    .init(icon: "hammer", label: "Tools", value: "App Intents", detail: "Auto tool routing", accent: .accent),
                ],
                footer: "Retrieval, verification, and normal work stay on this device. Longer evidence-backed synthesis can use Private Cloud Compute."
            )
        case .onDeviceAnalysis:
            return ModelCapabilityCardInfo(
                emoji: "📑",
                nickname: "Citation Scout",
                tagline: "Deterministic, extractive answers pulled straight from retrieved chunks.",
                chips: [
                    .init(icon: "doc.text", label: "Extractive", detail: "No generation", tone: .accent),
                    .init(icon: "bolt", label: "Instant", detail: "Sub-200 ms", tone: .success),
                    .init(icon: "lock.fill", label: "Offline", detail: "Never leaves device", tone: .success),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "<0.2 s", detail: "NL framework", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "N/A", detail: "Returns highlighted spans", accent: .neutral),
                    .init(icon: "square.stack", label: "Context", value: "Direct cite", detail: "No synthetic context", accent: .info),
                    .init(icon: "scope", label: "Best for", value: "Audits", detail: "When you only trust verbatim quotes", accent: .warning),
                ],
                footer: "Use when you must show word-for-word citations without hallucinations."
            )
        }
    }
}
