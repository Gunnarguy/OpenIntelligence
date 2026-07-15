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
    var qualityMode: RAGQualityMode = .standard
    var fmPreference: FoundationModelPreference = .automatic

    /// Retrieval-informed execution decision. Nil preserves compatibility for
    /// direct callers that have not passed through the RAG planner.
    var modelExecutionPlan: ModelExecutionPlan?


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

    /// Disable agentic tools for this generation (pure LLM mode)
    /// Use this for reasoning chain sessions where we want pure reasoning, not tool calls
    var disableTools: Bool = false

    /// Skip automatic continuation for incomplete responses
    /// Use this for summarization where we want concise output, not extended responses
    var skipContinuation: Bool = false

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

/// Settings for Private Cloud Compute usage
enum PCCSettings: String, CaseIterable, Sendable, Codable {
    case never = "Never use"
    case ask = "Ask when needed"
    case allow = "Allow for Deep Think and Maximum"
}

struct DeviceHardware {
    static var supportsAdvancedOnDeviceModel: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let twelveGigabytes: UInt64 = 11_500_000_000
        return ProcessInfo.processInfo.physicalMemory >= twelveGigabytes
        #endif
    }
}

/// Defines where Apple Foundation Models should execute
enum FoundationModelPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case core3B = "3B Core"
    case advanced20B = "20B Advanced"
    case privateCloudCompute = "Private Cloud Compute"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .automatic: return "Automatic (Local + PCC)"
        case .core3B, .advanced20B: return "📱 On-Device"
        case .privateCloudCompute: return "☁️ Private Cloud Compute"
        }
    }

    /// Maps persisted legacy model-size choices to public runtime capabilities.
    var canonical: FoundationModelPreference {
        self == .advanced20B ? .core3B : self
    }
    
    static var availableCases: [FoundationModelPreference] {
        if #available(iOS 27.0, macOS 27.0, *) {
            return [.automatic, .core3B, .privateCloudCompute]
        } else {
            return [.automatic, .core3B]
        }
    }
}

enum ExecutionContext: CaseIterable, Sendable {
    /// Let system decide based on policy.
    case automatic

    /// Force on-device only.
    case onDeviceOnly

    /// Prefer Private Cloud Compute.
    case preferCloud

    /// Force Private Cloud Compute.
    case cloudOnly

    var description: String {
        switch self {
        case .automatic:
            return "Automatic (Hybrid)"
        case .onDeviceOnly:
            return "On-Device Only (4K tokens)"
        case .preferCloud:
            return "Prefer Cloud (Complex queries)"
        case .cloudOnly:
            return "Cloud Only (Complex queries)"
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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch self {
            case .cloudOnly, .preferCloud:
                return FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false)
            case .onDeviceOnly:
                return FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
            case .automatic:
                return FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: false)
            }
        }
        #endif
        switch self {
        case .cloudOnly, .preferCloud:
            return 4096 // Per-session limit applies to PCC too (TN3193)
        case .onDeviceOnly:
            return 4096 // On-device hard limit (TN3193)
        case .automatic:
            return 4096 // Session context limit is 4K regardless of routing
        }
    }
}
