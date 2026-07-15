import Foundation

enum ModelExecutionTarget: String, Codable, Sendable, Equatable {
    case deterministic
    case onDevice
    case privateCloudCompute
    case abstain
}

enum ModelExecutionStageRole: String, Codable, Sendable, Equatable {
    case retrieve
    case synthesize
    case verify
    case repair
}

enum ModelRouteReason: String, Codable, Sendable, Equatable {
    case exactAnswerAvailable
    case privacyRequiredLocal
    case userRequiredLocal
    case userRequiredCloud
    case insufficientEvidence
    case localContextFits
    case localContextExceeded
    case complexSynthesis
    case pccUnavailable
    case pccQuotaReached
    case consentUnavailable
    case networkUnavailable
    case fallback
}

enum ModelPrivacyBoundary: String, Codable, Sendable, Equatable {
    case localOnly
    case pccEligibleAfterConsent
    case pccProhibited
}

enum PCCQuotaState: String, Codable, Sendable, Equatable {
    case unsupported
    case unknown
    case belowLimit
    case approachingLimit
    case limitReached
}

enum CapabilityEvidenceSource: String, Codable, Sendable, Equatable {
    case sdkExact
    case sdkPartial
    case conservativeFallback
}

struct PreRetrievalConstraints: Codable, Sendable, Equatable {
    let allowsPCC: Bool
    let requiresOnDevice: Bool
    let requiresPCC: Bool
    let networkAvailable: Bool
    let consentGranted: Bool
    let isForegroundInteractive: Bool
    let qualityMode: String
}

struct PostRetrievalEvidence: Codable, Sendable, Equatable {
    let chunkCount: Int
    let topScore: Float
    let meanScore: Float
    let estimatedEvidenceTokens: Int
    let hasContradictions: Bool
    let requiresExactExtraction: Bool
    let requiresMultiDocumentSynthesis: Bool

    var isSufficient: Bool {
        chunkCount > 0 && topScore >= 0.20
    }
}

struct ContextBudgetSnapshot: Codable, Sendable, Equatable {
    let contextSize: Int
    let instructions: Int
    let tools: Int
    let schema: Int
    let history: Int
    let evidence: Int
    let output: Int
    let reasoning: Int
    let safety: Int
    let source: CapabilityEvidenceSource

    var used: Int {
        instructions + tools + schema + history + evidence + output + reasoning + safety
    }

    var remaining: Int {
        max(0, contextSize - used)
    }

    var fits: Bool {
        used <= contextSize
    }
}

struct FoundationModelCapabilitySnapshot: Codable, Sendable, Equatable {
    let supportsOnDevice: Bool
    let onDeviceAvailable: Bool
    let onDeviceContextSize: Int
    let supportsPCC: Bool
    let hasPCCEntitlement: Bool
    let pccAvailable: Bool
    let pccQuota: PCCQuotaState
    let pccContextSize: Int?
    let source: CapabilityEvidenceSource
    let unavailabilityReason: String?

    var canUsePCC: Bool {
        supportsPCC && hasPCCEntitlement && pccAvailable && pccQuota != .limitReached
    }
}

struct ModelFallbackPlan: Codable, Sendable, Equatable {
    let target: ModelExecutionTarget?
    let reason: ModelRouteReason
    let mayRetryPCC: Bool
}

struct ModelVerificationPlan: Codable, Sendable, Equatable {
    let verifyCitations: Bool
    let verifyEvidenceCoverage: Bool
    let maximumRepairAttempts: Int
}

struct ModelExecutionStage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let role: ModelExecutionStageRole
    let target: ModelExecutionTarget
    let reason: ModelRouteReason

    init(
        id: UUID = UUID(),
        role: ModelExecutionStageRole,
        target: ModelExecutionTarget,
        reason: ModelRouteReason
    ) {
        self.id = id
        self.role = role
        self.target = target
        self.reason = reason
    }
}

struct ModelExecutionPlan: Identifiable, Codable, Sendable, Equatable {
    static let policyVersion = "pcc-dynamic-router-v1"

    let id: UUID
    let policyVersion: String
    let createdAt: Date
    let constraints: PreRetrievalConstraints
    let evidence: PostRetrievalEvidence
    let privacyBoundary: ModelPrivacyBoundary
    let stages: [ModelExecutionStage]
    let fallback: ModelFallbackPlan
    let verification: ModelVerificationPlan
    let contextBudget: ContextBudgetSnapshot
    let pccQuotaAtPlanning: PCCQuotaState

    init(
        id: UUID = UUID(),
        policyVersion: String = Self.policyVersion,
        createdAt: Date = Date(),
        constraints: PreRetrievalConstraints,
        evidence: PostRetrievalEvidence,
        privacyBoundary: ModelPrivacyBoundary,
        stages: [ModelExecutionStage],
        fallback: ModelFallbackPlan,
        verification: ModelVerificationPlan,
        contextBudget: ContextBudgetSnapshot,
        pccQuotaAtPlanning: PCCQuotaState = .unknown
    ) {
        self.id = id
        self.policyVersion = policyVersion
        self.createdAt = createdAt
        self.constraints = constraints
        self.evidence = evidence
        self.privacyBoundary = privacyBoundary
        self.stages = stages
        self.fallback = fallback
        self.verification = verification
        self.contextBudget = contextBudget
        self.pccQuotaAtPlanning = pccQuotaAtPlanning
    }

    var synthesisTarget: ModelExecutionTarget {
        stages.first(where: { $0.role == .synthesize })?.target ?? .abstain
    }

    var requiresCloudConsent: Bool {
        synthesisTarget == .privateCloudCompute
    }
}

struct CloudEvidenceItem: Codable, Sendable, Equatable {
    let sourceID: String
    let documentName: String
    let pageNumber: Int?
    let text: String
}

struct CloudEvidenceEnvelope: Codable, Sendable, Equatable {
    let planID: UUID
    let query: String
    let evidence: [CloudEvidenceItem]
    let omittedChunkCount: Int
    let characterCount: Int
}

enum ModelRoutingFeatureFlags {
    static var plannerV1Enabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "modelExecutionPlannerV1Enabled") == nil {
            return true
        }
        return defaults.bool(forKey: "modelExecutionPlannerV1Enabled")
    }
}
