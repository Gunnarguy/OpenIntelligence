//
//  LLMModelType.swift
//  OpenIntelligence
//
//  Created by GitHub Copilot on 10/24/25.
//

import Foundation

/// Supported high-level LLM integrations that can power the chat experience.
enum LLMModelType: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple_intelligence" // On-device + PCC automatic
    case chatGPTExtension = "chatgpt_extension" // Apple Intelligence ChatGPT (iOS 18.1+)
    case onDeviceAnalysis = "on_device_analysis" // Extractive QA, always available
    case openAIDirect = "openai" // User-provided OpenAI API key
    case mlxLocal = "mlx_local" // macOS MLX tensor server (local HTTP transport)
    case ggufLocal = "gguf_local" // iOS-only local GGUF via llama.cpp (in-process)
    case coreMLLocal = "coreml_local" // Custom Core ML model

    var id: String { rawValue }
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
            return "Apple Intelligence"
        case .chatGPTExtension:
            return "ChatGPT Extension"
        case .onDeviceAnalysis:
            return "On-Device Analysis"
        case .openAIDirect:
            return "OpenAI Direct"
        case .mlxLocal:
            return "MLX Local (macOS)"
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
        case .mlxLocal:
            return
                "Native MLX tensor server running on your Mac. Point it at an mlx_lm endpoint and keep every token on-device with SSE streaming support."
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
        case .mlxLocal:
            return "server.rack"
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
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis, .mlxLocal:
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
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis, .mlxLocal:
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
        case .mlxLocal:
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
        case .mlxLocal:
            return "Advertised by MLX server"
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
        case .mlxLocal:
            return [
                "Runs on Mac",
                "Server-Sent Events",
                "Function calling",
                "Full tensor precision",
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
        case .mlxLocal:
            return true
        default:
            return false
        }
    }

    var isPrivate: Bool {
        switch self {
        case .appleIntelligence, .ggufLocal, .coreMLLocal, .onDeviceAnalysis:
            return true
        case .mlxLocal:
            return true
        default:
            return false
        }
    }

    var isFast: Bool {
        switch self {
        case .ggufLocal, .coreMLLocal, .onDeviceAnalysis, .appleIntelligence:
            return true
        case .mlxLocal:
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
        case .mlxLocal:
            return true
        default:
            return true
        }
    }

    /// Pokémon card style metadata surfaced in ModelComparisonSheet.
    var capabilityCard: ModelCapabilityCardInfo {
        switch self {
        case .appleIntelligence:
            return ModelCapabilityCardInfo(
                emoji: "🍎",
                nickname: "Hybrid Ace",
                tagline: "Private-first Apple FM with automatic PCC boost when prompts get long.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "Grounded chat", tone: .accent),
                    .init(icon: "eye.fill", label: "Vision", detail: "Screenshots", tone: .info),
                    .init(icon: "wand.and.stars", label: "Actions", detail: "App tools", tone: .success),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "< 0.8 s", detail: "Median TTFT on A18", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "≈65 tok/s", detail: "Neural Engine streaming", accent: .accent),
                    .init(icon: "square.stack.3d.down.right.fill", label: "Context", value: "8K ➜ 128K", detail: "Local with PCC expansion", accent: .info),
                    .init(icon: "lock.shield.fill", label: "Privacy", value: "Zero-retention", detail: "Encrypted PCC hops", accent: .success),
                    .init(icon: "hammer", label: "Tools", value: "Functions + App Intents", detail: "Auto tool routing", accent: .accent),
                ],
                footer: "Runs fully on-device until a Private Cloud Compute hop is explicitly approved."
            )
        case .chatGPTExtension:
            return ModelCapabilityCardInfo(
                emoji: "🛰️",
                nickname: "Consent Link",
                tagline: "System-level ChatGPT routed through Apple Intelligence with per-call prompts.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "GPT-4o/GPT-5", tone: .accent),
                    .init(icon: "eye.fill", label: "Vision", detail: "Image replies", tone: .info),
                    .init(icon: "link", label: "Hand-off", detail: "Responds inline", tone: .neutral),
                ],
                stats: [
                    .init(icon: "bolt.badge.a", label: "Latency", value: "~1.5 s", detail: "Depends on PCC routing", accent: .warning),
                    .init(icon: "gauge", label: "Throughput", value: "Cloud tier", detail: "Matches ChatGPT plan", accent: .neutral),
                    .init(icon: "shield.lefthalf.fill", label: "Privacy", value: "Apple brokered", detail: "Consent sheet every time", accent: .success),
                    .init(icon: "key.fill", label: "Requirements", value: "Apple ID + opt-in", detail: "Enable in Apple Intelligence settings", accent: .warning),
                ],
                footer: "Ideal when you want the latest GPT model without pasting API keys into the app."
            )
        case .openAIDirect:
            return ModelCapabilityCardInfo(
                emoji: "🌐",
                nickname: "API Power",
                tagline: "Direct GPT-4o/GPT-5 access under your OpenAI account for maximum ceiling.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "All GPT families", tone: .accent),
                    .init(icon: "eye.fill", label: "Vision", detail: "Image reasoning", tone: .info),
                    .init(icon: "waveform", label: "Audio", detail: "Via Whisper / GPT-4o mini", tone: .neutral),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "1-3 s", detail: "Depends on OpenAI region", accent: .warning),
                    .init(icon: "gauge", label: "Throughput", value: ">100 tok/s", detail: "GPT-4o streaming", accent: .accent),
                    .init(icon: "square.stack.3d.up.fill", label: "Context", value: "128K+", detail: "Model dependent", accent: .info),
                    .init(icon: "dollarsign.circle", label: "Cost", value: "Usage billed", detail: "OpenAI charges apply", accent: .warning),
                ],
                footer: "Best when you control the API key and need the absolute newest frontier models."
            )
        case .ggufLocal:
            return ModelCapabilityCardInfo(
                emoji: "🎮",
                nickname: "Cartridge",
                tagline: "Fully offline llama.cpp execution for GGUF builds you import.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "Generative", tone: .accent),
                    .init(icon: "bolt.horizontal.circle", label: "Offline", detail: "Airplane ready", tone: .success),
                    .init(icon: "cube.fill", label: "Quant", detail: "Q2–Q8", tone: .info),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "~1.2 s", detail: "TTFT on A17 Pro (8B)", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "20–35 tok/s", detail: "Depends on size/quant", accent: .accent),
                    .init(icon: "square.stack.3d.down.right", label: "Context", value: "2K–32K", detail: "Model specific", accent: .info),
                    .init(icon: "battery.100", label: "Power", value: "Neural Engine", detail: "Stays on-device", accent: .success),
                ],
                footer: "Choose smaller quantizations for mobility; larger ones demand more RAM but improve quality."
            )
        case .coreMLLocal:
            return ModelCapabilityCardInfo(
                emoji: "🧠",
                nickname: "ML Package",
                tagline: "Bring-your-own Core ML LLM with full Neural Engine acceleration.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "Converted models", tone: .accent),
                    .init(icon: "cpu", label: "Neural Engine", detail: "Core ML runtime", tone: .success),
                    .init(icon: "shippingbox", label: "BYO", detail: ".mlpackage", tone: .info),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "~1.0 s", detail: "Depends on compilation", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "30+ tok/s", detail: "A18 / M4 class", accent: .accent),
                    .init(icon: "square.stack.3d.up", label: "Context", value: "Up to 8K", detail: "Tokenizer dependent", accent: .info),
                    .init(icon: "lock.fill", label: "Privacy", value: "Offline", detail: "Never leaves device", accent: .success),
                ],
                footer: "Great for enterprises that already have a Core ML export pipeline."
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
        case .mlxLocal:
            return ModelCapabilityCardInfo(
                emoji: "🧩",
                nickname: "Tensor Dock",
                tagline: "Direct MLX tensor serving on macOS with streaming and tool calls.",
                chips: [
                    .init(icon: "text.alignleft", label: "Text", detail: "mlx_lm", tone: .accent),
                    .init(icon: "server.rack", label: "Local host", detail: "Loopback", tone: .success),
                    .init(icon: "bolt.horizontal.circle", label: "SSE", detail: "Low latency", tone: .info),
                ],
                stats: [
                    .init(icon: "bolt.fill", label: "Latency", value: "~0.9 s", detail: "Depends on model size", accent: .success),
                    .init(icon: "gauge", label: "Throughput", value: "35–80 tok/s", detail: "M4 Max tensor cores", accent: .accent),
                    .init(icon: "square.stack.3d.up", label: "Context", value: "Server advertised", detail: "Reads from metadata", accent: .info),
                    .init(icon: "lock.fill", label: "Privacy", value: "Offline", detail: "Never leaves your Mac", accent: .success),
                    .init(icon: "hammer", label: "Tools", value: "Function calling", detail: "Routes to RAG tools", accent: .accent),
                ],
                footer: "Start `python -m mlx_lm.server` and point OpenIntelligence at it for fully private desktop inference."
            )
        }
    }
}
