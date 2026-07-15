import Foundation

enum CloudProvider: String, Codable, CaseIterable, Sendable {
    case applePCC

    var displayName: String {
        switch self {
        case .applePCC:
            return "Apple Private Cloud Compute"
        }
    }

    var shortName: String {
        switch self {
        case .applePCC: return "Apple PCC"
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
    let contextCharacterCount: Int
    let contextChunkCount: Int
    let contextHashes: [String]
    let estimatedBytes: Int
    let planID: UUID?
    let routeReason: ModelRouteReason?

    init(
        id: UUID = UUID(),
        provider: CloudProvider,
        modelName: String,
        timestamp: Date = Date(),
        promptPreview: String,
        promptCharacterCount: Int,
        contextCharacterCount: Int = 0,
        contextChunkCount: Int,
        contextHashes: [String],
        estimatedBytes: Int,
        planID: UUID? = nil,
        routeReason: ModelRouteReason? = nil
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.timestamp = timestamp
        self.promptPreview = promptPreview
        self.promptCharacterCount = promptCharacterCount
        self.contextCharacterCount = contextCharacterCount
        self.contextChunkCount = contextChunkCount
        self.contextHashes = contextHashes
        self.estimatedBytes = estimatedBytes
        self.planID = planID
        self.routeReason = routeReason
    }
}
