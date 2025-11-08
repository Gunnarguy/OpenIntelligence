//
//  LLMModelType.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
//

import Foundation

/// Supported high-level LLM integrations that can power the chat experience.
enum LLMModelType: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple_intelligence"  // On-device + PCC automatic
    case chatGPTExtension = "chatgpt_extension"  // Apple Intelligence ChatGPT (iOS 18.1+)
    case onDeviceAnalysis = "on_device_analysis"  // Extractive QA, always available
    case openAIDirect = "openai"  // User-provided OpenAI API key
    case ggufLocal = "gguf_local"  // iOS-only local GGUF via llama.cpp (in-process)
    case coreMLLocal = "coreml_local"  // Custom Core ML model

    var id: String { self.rawValue }
}

extension LLMModelType {
    /// User-facing name surfaced inside pickers and diagnostics.
    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .chatGPTExtension:
            return "ChatGPT Extension"
        case .onDeviceAnalysis:
            return "On-Device Analysis"
        case .openAIDirect:
            return "OpenAI Direct"
        case .ggufLocal:
            return "GGUF Local (iOS)"
        case .coreMLLocal:
            return "Core ML Local"
        }
    }

    /// Detailed description of the model for preview/comparison views
    var description: String {
        switch self {
        case .appleIntelligence:
            return
                "On-device Apple Foundation Models with automatic Private Cloud Compute fallback for complex queries. Zero data retention, end-to-end encrypted."
        case .chatGPTExtension:
            return
                "System-level ChatGPT integration powered by Apple Intelligence. User consent required per query, routes through Private Cloud Compute."
        case .onDeviceAnalysis:
            return
                "Extractive question answering using NaturalLanguage framework. No generative AI, purely extractive from your documents. Always available offline."
        case .openAIDirect:
            return
                "Direct OpenAI API access using your API key. Supports GPT-4o, GPT-5, and latest models. Usage billed by OpenAI under your account."
        case .ggufLocal:
            return
                "Embedded GGUF model running in-process on iOS using llama.cpp. Fully offline, no network needed. Requires A17 Pro or newer for best performance."
        case .coreMLLocal:
            return
                "Custom Core ML model package optimized for Apple Silicon. Uses Neural Engine acceleration for efficient on-device inference."
        }
    }

    /// SF Symbol identifier used when rendering this model inside pickers.
    var iconName: String {
        switch self {
        case .appleIntelligence:
            return "sparkles"
        case .chatGPTExtension:
            return "bubble.left.and.bubble.right.fill"
        case .onDeviceAnalysis:
            return "doc.text.magnifyingglass"
        case .openAIDirect:
            return "key.fill"
        case .ggufLocal:
            return "doc.badge.gearshape"
        case .coreMLLocal:
            return "cpu"
        }
    }

    var category: String {
        switch self {
        case .appleIntelligence, .chatGPTExtension:
            return "Hybrid"
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return "Local"
        case .openAIDirect:
            return "Cloud"
        }
    }

    var privacyLevel: String {
        switch self {
        case .appleIntelligence:
            return "End-to-end encrypted"
        case .chatGPTExtension:
            return "Apple mediated"
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return "On-device"
        default:
            return "User managed"
        }
    }

    var requiresNetwork: Bool {
        switch self {
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return false
        case .appleIntelligence, .chatGPTExtension:
            return false
        default:
            return true
        }
    }

    var contextDescription: String {
        switch self {
        case .appleIntelligence:
            return "~8K tokens (PCC expands)"
        case .chatGPTExtension:
            return "System managed"
        case .ggufLocal:
            return "Model dependent (2K-32K)"
        case .coreMLLocal:
            return "Model dependent"
        case .onDeviceAnalysis:
            return "No generation context"
        default:
            return "Depends on backend"
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
        case .chatGPTExtension:
            return [
                "Latest GPT models",
                "User consent",
                "Apple Intelligence integration",
                "Private Cloud Compute",
            ]
        case .ggufLocal:
            return [
                "Offline",
                "Custom quantization",
                "Neural Engine friendly",
                "Fast warm starts",
            ]
        case .coreMLLocal:
            return [
                "Neural Engine",
                "Optimised for Apple Silicon",
                "No network",
                "Battery friendly",
            ]
        case .onDeviceAnalysis:
            return [
                "Extractive QA",
                "Deterministic",
                "Instant answers",
                "Always available",
            ]
        default:
            return []
        }
    }

    var isLocal: Bool {
        switch self {
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return true
        default:
            return false
        }
    }

    var isPrivate: Bool {
        switch self {
        case .appleIntelligence, .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return true
        default:
            return false
        }
    }

    var isFast: Bool {
        switch self {
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis, .appleIntelligence:
            return true
        default:
            return false
        }
    }

    var quality: Bool {
        switch self {
        case .appleIntelligence, .chatGPTExtension, .ggufLocal, .coreMLLocal:
            return true
        case .onDeviceAnalysis:
            return false
        default:
            return true
        }
    }
}
