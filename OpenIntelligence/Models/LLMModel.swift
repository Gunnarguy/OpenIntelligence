//
//  LLMModel.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation

/// Represents an available LLM that can be used for generation
struct LLMModel: Identifiable, Codable {
    let id: UUID
    let name: String
    let modelType: ModelType
    let filePath: URL?
    let parameterCount: String
    let quantization: String?
    let contextLength: Int
    let contextDescription: String?
    let availabilityNote: String?
    let isAvailable: Bool

    init(id: UUID = UUID(),
         name: String,
         modelType: ModelType,
         filePath: URL? = nil,
         parameterCount: String,
         quantization: String? = nil,
         contextLength: Int,
         contextDescription: String? = nil,
         availabilityNote: String? = nil,
         isAvailable: Bool) {
        self.id = id
        self.name = name
        self.modelType = modelType
        self.filePath = filePath
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.contextLength = contextLength
        self.contextDescription = contextDescription
        self.availabilityNote = availabilityNote
        self.isAvailable = isAvailable
    }
}

enum ModelType: String, Codable {
    case appleFoundation = "Apple Foundation"
    case appleHybrid = "Apple Intelligence (Hybrid)"
    case appleChatGPT = "Apple Intelligence ChatGPT"
    case onDeviceAnalysis = "On-Device Analysis"
    case coreMLPackage = "Core ML Package"
    case gguf = "GGUF"
}

/// Represents the execution pathway for LLM inference
enum InferencePathway {
    case foundationModels  // Pathway A: Apple's integrated solution
    case coreMLConverted   // Pathway B1: Official Core ML conversion
    case ggufDirect        // Pathway B2: Direct GGUF execution via llama.cpp
}

/// Configuration for model inference performance
///
/// **Parameter Support Notes (Apple FM):**
/// - `maxTokens` maps to `maximumResponseTokens`
/// - `temperature` maps to sampling temperature
/// - `topP` maps to `SamplingMode.random(probabilityThreshold:)`
/// - `topK` maps to `SamplingMode.random(top:)`
struct InferenceConfig {
    // MARK: - Universal Parameters
    var maxTokens: Int = 512
    var temperature: Float = 0.7
    var topP: Float = 0.9
    var topK: Int = 40

    // MARK: - Legacy Parameters

    // These are NOT used by Apple FoundationModels but kept for backward compatibility.
    var useKVCache: Bool = true // Not applicable to FM
    var systemPrompt: String? // FM uses Instructions(...) instead
    var contextLength: Int? // FM context is fixed at 4096 tokens (TN3193)

    // These have NO effect on Apple Foundation Models
    var frequencyPenalty: Float = 0.0
    var presencePenalty: Float = 0.0
    var repetitionPenalty: Float = 1.0
    var stopSequences: [String] = []

    // Apple Intelligence Execution Context (iOS 26+)
    var executionContext: ExecutionContext = .automatic
    var allowPrivateCloudCompute: Bool = true  // User-controlled PCC permission

    /// Preset for RAG queries (factual, non-repetitive, focused)
    static var ragOptimized: InferenceConfig {
        var config = InferenceConfig()
        config.temperature = 0.7        // Balanced creativity
        config.topP = 0.9              // Focused nucleus sampling
        config.topK = 40               // Limited vocabulary
        config.frequencyPenalty = 0.5  // Reduce repetition
        config.presencePenalty = 0.3   // Cover multiple document sections
        config.repetitionPenalty = 1.2 // Stronger anti-repeat
        config.stopSequences = ["</answer>", "\n\nQuestion:", "[END]"]
        return config
    }

    /// Preset for creative responses (more diverse, less constrained)
    static var creative: InferenceConfig {
        var config = InferenceConfig()
        config.temperature = 1.0
        config.topP = 0.95
        config.topK = 60
        config.frequencyPenalty = 0.3
        config.presencePenalty = 0.5
        return config
    }

    /// Preset for precise, deterministic responses
    static var precise: InferenceConfig {
        var config = InferenceConfig()
        config.temperature = 0.3
        config.topP = 0.85
        config.topK = 30
        config.frequencyPenalty = 0.7
        config.repetitionPenalty = 1.3
        return config
    }
}

/// Defines where Apple Foundation Models should execute
///
/// **Context Window Sizes:**
/// - On-device: 4,096 tokens (~10K chars) - fast but limited
/// - Private Cloud Compute (PCC): ~65,536 tokens (~160K chars) - larger context, requires internet + consent
///
/// The system automatically routes to PCC when:
/// - Context exceeds on-device capacity
/// - Complex reasoning is required
/// - User has granted PCC consent
enum ExecutionContext: CaseIterable, Sendable {
    /// Let system decide (on-device → PCC fallback). Default and recommended.
    /// Uses on-device when possible (fast), automatically escalates to PCC for complex queries.
    case automatic

    /// Force on-device only. Limited to 4,096 tokens.
    /// Use when offline or privacy is paramount. Will fail if context too large.
    case onDeviceOnly

    /// Prefer Private Cloud Compute for 65K context window.
    /// Falls back to on-device if PCC unavailable (network issues, consent denied).
    /// **RECOMMENDED for RAG queries with large document context.**
    case preferCloud

    /// Force PCC only. Requires network. Will fail if PCC unavailable.
    /// Use sparingly - preferCloud is usually better as it allows fallback.
    case cloudOnly

    var description: String {
        switch self {
        case .automatic:
            return "Automatic (Hybrid)"
        case .onDeviceOnly:
            return "On-Device Only (4K tokens)"
        case .preferCloud:
            return "Prefer Cloud (65K tokens)"
        case .cloudOnly:
            return "Cloud Only (65K tokens)"
        }
    }

    var emoji: String {
        switch self {
        case .automatic:
            return "🔄"
        case .onDeviceOnly:
            return "📱"
        case .preferCloud:
            return "☁️"
        case .cloudOnly:
            return "🌐"
        }
    }

    /// Maximum context window tokens for this execution mode
    var maxContextTokens: Int {
        switch self {
        case .cloudOnly, .preferCloud:
            return 65536 // PCC supports ~65K tokens
        case .onDeviceOnly:
            return 4096 // On-device hard limit (TN3193)
        case .automatic:
            return 65536 // Optimistic - system may fall back to 4K
        }
    }
}
