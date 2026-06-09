//
//  ModelResolutionState.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

/// Represents the resolved execution state of the LLM pipeline
struct ModelResolutionState: Equatable {
    let selectedType: LLMModelType
    let activeModelName: String
    let resolutionReason: ResolutionReason
    let executionPath: ExecutionPath
    let status: ModelStatus
    let localModelInfo: LocalModelInfo?
    let activeParameters: ActiveParameters
    
    enum ResolutionReason: Equatable {
        case systemDefault
        case autoSelected(reason: String)
        case fallback(from: LLMModelType, reason: String)
        case userSelected
        
        var displayText: String {
            switch self {
            case .systemDefault:
                return "System Default"
            case .autoSelected(let reason):
                return "Auto-Selected: \(reason)"
            case .fallback(let from, let reason):
                return "Fallback from \(from.displayName): \(reason)"
            case .userSelected:
                return "User Selected"
            }
        }
    }
    
    enum ExecutionPath: Equatable {
        case onDevice
        case privateCloudCompute
        case hybridAutomatic
        case localServer(endpoint: String)
        case cloudAPI(provider: String)
        
        var emoji: String {
            switch self {
            case .onDevice: return "📱"
            case .privateCloudCompute: return "☁️"
            case .hybridAutomatic: return "🔄"
            case .localServer: return "🖥️"
            case .cloudAPI: return "🌐"
            }
        }
        
        var displayName: String {
            switch self {
            case .onDevice: return "On-Device"
            case .privateCloudCompute: return "Private Cloud Compute"
            case .hybridAutomatic: return "Hybrid (Automatic)"
            case .localServer(let ep): return "Local Server (\(ep))"
            case .cloudAPI(let prov): return "Cloud API (\(prov))"
            }
        }
    }
    
    enum ModelStatus: Equatable {
        case loading(progress: Double?)
        case ready
        case unavailable(reason: String)
    }
    
    struct LocalModelInfo: Equatable {
        let fileName: String
        let fileSize: Int64
        let quantization: String?
        let backend: ModelBackendType
        
        enum ModelBackendType: Equatable {
            case gguf
            case coreML
        }
    }
    
    struct ActiveParameters: Equatable {
        let temperature: Float
        let maxTokens: Int
        let topP: Float
        let contextLength: Int
    }
}

enum ModelBackend: String, Codable, Sendable {
    case appleFM = "apple_fm"
    case gguf = "gguf"
    case coreML = "coreml"
    case mlx = "mlx"
    case openai = "openai"
    case extractive = "extractive"
}

struct ModelAutoSelectionPayload {
    static let backend = "backend"
}

extension Notification.Name {
    static var installedModelAutoSelected: Notification.Name {
        Notification.Name("installedModelAutoSelected")
    }
}
