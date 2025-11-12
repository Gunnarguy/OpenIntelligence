import Foundation

enum CloudProvider: String, Codable, CaseIterable, Sendable {
    case applePCC
    case openAI

    var displayName: String {
        switch self {
        case .applePCC:
            return "Apple Private Cloud Compute"
        case .openAI:
            return "OpenAI Direct"
        }
    }

    var shortName: String {
        switch self {
        case .applePCC: return "Apple PCC"
        case .openAI: return "OpenAI"
        }
    }
}

enum CloudConsentState: String, Codable, CaseIterable, Sendable {
    case notDetermined
    case allowed
    case denied

    var displayName: String {
        switch self {
        case .notDetermined: return "Ask Each Time"
        case .allowed: return "Always Allow"
        case .denied: return "Never Allow"
        }
    }
}

enum CloudConsentDecision: Sendable {
    case allowOnce
    case allowAndRemember
    case deny
}

struct CloudTransmissionRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let provider: CloudProvider
    let modelName: String
    let timestamp: Date
    let promptPreview: String
    let promptCharacterCount: Int
    let contextChunkCount: Int
    let contextHashes: [String]
    let estimatedBytes: Int

    init(
        id: UUID = UUID(),
        provider: CloudProvider,
        modelName: String,
        timestamp: Date = Date(),
        promptPreview: String,
        promptCharacterCount: Int,
        contextChunkCount: Int,
        contextHashes: [String],
        estimatedBytes: Int
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.timestamp = timestamp
        self.promptPreview = promptPreview
        self.promptCharacterCount = promptCharacterCount
        self.contextChunkCount = contextChunkCount
        self.contextHashes = contextHashes
        self.estimatedBytes = estimatedBytes
    }
}
