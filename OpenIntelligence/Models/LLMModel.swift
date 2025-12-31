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
    case openAI = "OpenAI (Cloud)"
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
/// **Parameter Support by Provider:**
/// | Parameter | Apple FM (iOS 26) | OpenAI |
/// |-----------|-------------------|--------|
/// | maxTokens | ✅ `maximumResponseTokens` | ✅ `max_tokens` |
/// | temperature | ✅ 0.0-2.0 | ✅ 0.0-2.0 |
/// | topP | ✅ `SamplingMode.random(probabilityThreshold:)` | ✅ `top_p` |
/// | topK | ✅ `SamplingMode.random(top:)` | ❌ Not supported |
/// | frequencyPenalty | ❌ Not supported | ✅ `frequency_penalty` |
/// | presencePenalty | ❌ Not supported | ✅ `presence_penalty` |
/// | stopSequences | ❌ Not supported | ✅ `stop` |
struct InferenceConfig {
    // MARK: - Universal Parameters (supported by both FM and OpenAI)
    var maxTokens: Int = 512
    var temperature: Float = 0.7
    var topP: Float = 0.9
    var topK: Int = 40

    // MARK: - Legacy/OpenAI-Only Parameters

    // These are NOT used by Apple FoundationModels but kept for OpenAI compatibility
    var useKVCache: Bool = true // Not applicable to FM
    var systemPrompt: String? // FM uses Instructions(...) instead
    var contextLength: Int? // FM context is fixed at 4096 tokens (TN3193)

    // ⚠️ OpenAI-Only: These parameters have NO effect on Apple Foundation Models
    var frequencyPenalty: Float = 0.0 // OpenAI: 0.0-2.0, FM: Not supported
    var presencePenalty: Float = 0.0 // OpenAI: 0.0-2.0, FM: Not supported
    var repetitionPenalty: Float = 1.0 // OpenAI-compatible: Not in official API
    var stopSequences: [String] = [] // OpenAI: `stop`, FM: Not supported

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
enum ExecutionContext {
    case automatic      // Let system decide (on-device → PCC fallback)
    case onDeviceOnly   // Force on-device only (will fail if too complex)
    case preferCloud    // Prefer Private Cloud Compute for better quality
    case cloudOnly      // Force PCC (requires network)

    var description: String {
        switch self {
        case .automatic:
            return "Automatic (Hybrid)"
        case .onDeviceOnly:
            return "On-Device Only"
        case .preferCloud:
            return "Prefer Cloud"
        case .cloudOnly:
            return "Cloud Only"
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
}
