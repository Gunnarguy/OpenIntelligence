#if OPENINTELLIGENCE_ENGINE_SDK

import Foundation
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DSHaptics {
    static func selection() {}
    static func soft() {}
    static func light() {}
    static func medium() {}
    static func success() {}
    static func warning() {}
    static func tick() {}
    static func toggle() {}
    static func copy() {}
    static func processingPulse() {}
    static func generationStarted() {}
    static func generationTick() {}
    static func generationComplete() {}
    static func documentIngested() {}
    static func thermalPulse(intensity _: Double = 0.5) {}
}

final class SpotlightIndexService {
    static let shared = SpotlightIndexService()

    private init() {}

    func indexContainer(_: KnowledgeContainer) {}

    func deindexContainer(id _: UUID) {}

    func indexDocument(
        id _: UUID,
        filename _: String,
        containerId _: UUID,
        containerName _: String,
        textPreview _: String,
        pageCount _: Int? = nil,
        chunkCount _: Int? = nil,
        fileSize _: Int64? = nil,
        keywords _: [String]? = nil,
        contentType _: UTType = .plainText
    ) {}

    func deindexDocument(id _: UUID) {}

    func deindexAllDocuments(in _: UUID) {}

    func indexChunk(
        id: UUID,
        documentId: UUID,
        documentName: String,
        containerId: UUID,
        containerName: String,
        content: String,
        pageNumber: Int?,
        sectionTitle: String?,
        chunkIndex: Int,
        keywords: [String]?
    ) {}

    func indexDocumentChunks(
        documentId: UUID,
        documentName: String,
        chunks: [DocumentChunk],
        containerId: UUID,
        containerName: String
    ) {}
}

final class EntitlementStore {
    var documentLimit: Int { QuotaPolicy.documentLimit() }
    var activeTier: WorkspaceTier { .free }
    var effectiveTier: WorkspaceTier { activeTier }
    var currentPlanDisplayName: String { effectiveTier.displayName }
    var legacyProtectionState: LegacyProtectionState { .none }
    var isLegacyPaidProtected: Bool { false }
    var hasUnlimitedDocuments: Bool { false }
    var hasUnlimitedMaximumMode: Bool { false }
    var canUseMaximumModeNow: Bool { true }
    var maximumModeRemainingUses: Int { QuotaPolicy.freeMaximumModeDailyLimit }
    var shouldOfferDocumentPack: Bool { false }

    func canAddDocument(currentCount: Int) -> Bool {
        currentCount < documentLimit
    }

    func refreshTransientState() {}

    func consumeMaximumModeUseIfNeeded() -> MaximumModeExecutionDecision {
        .allowedUnlimited
    }

    static func currentEffectiveTier(defaults: UserDefaults = .standard) -> WorkspaceTier {
        return .free
    }

    static func currentLibraryLimit(defaults: UserDefaults = .standard) -> Int {
        return 1
    }
}

enum LegacyProtectionState: String, Codable, Sendable {
    case none
    case historicalPaidPurchase
    case legacyDocumentPackOwner
}

enum MaximumModeExecutionDecision: Sendable {
    case allowedUnlimited
    case allowedMetered(remaining: Int, dailyLimit: Int)
    case blocked(remaining: Int, dailyLimit: Int, resetsAt: Date)
}

final class ProjectionCache {
    static let shared = ProjectionCache()

    private init() {}

    func invalidate(forContainer _: UUID) {}
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class TranscriptPersistenceService {
    static let shared = TranscriptPersistenceService()

    private init() {}

    @discardableResult
    func saveTranscript(_ _: Transcript, for _: UUID) -> Bool { false }

    @discardableResult
    func saveTranscriptTrimmed(_ _: Transcript, for _: UUID) -> Bool { false }

    func loadTranscript(for _: UUID) -> Transcript? { nil }

    func deleteTranscript(for _: UUID) {}

    func hasTranscript(for _: UUID) -> Bool { false }
}
#endif

#endif
import Foundation

#if canImport(FoundationModels)
import FoundationModels

// Mocking the new WWDC26 API so it compiles.
@available(iOS 26.0, macOS 16.0, *)
public struct PrivateCloudComputeLanguageModel {
    public init() {}
    public var isAvailable: Bool { true }
    public var contextSize: Int { 32768 }
    
    public struct QuotaUsage {
        public enum Status: String {
            case belowLimit
            case approachingLimit
            case limitReached
            public var description: String { rawValue }
        }
        public var status: Status { .belowLimit }
        public var isLimitReached: Bool { false }
        public var limitIncreaseSuggestion: Bool { true }
    }
    public var quotaUsage: QuotaUsage { QuotaUsage() }
}

@available(iOS 26.0, macOS 16.0, *)
public struct ContextOptions {
    public enum ReasoningLevel: String {
        case none
        case light
        case moderate
        case deep
    }
    public var reasoningLevel: ReasoningLevel
    public init(reasoningLevel: ReasoningLevel) {
        self.reasoningLevel = reasoningLevel
    }
}

@available(iOS 26.0, macOS 16.0, *)
extension LanguageModelSession {
    public convenience init(model: PrivateCloudComputeLanguageModel, tools: [any Tool] = [], instructions: Instructions) {
        self.init(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
    }
    public convenience init(model: PrivateCloudComputeLanguageModel, tools: [any Tool] = [], transcript: Transcript) {
        self.init(model: SystemLanguageModel.default, tools: tools, transcript: transcript)
    }
    public func streamResponse(to prompt: String, options: GenerationOptions, contextOptions: ContextOptions?) -> LanguageModelSession.ResponseStream<String> {
        return self.streamResponse(to: prompt, options: options)
    }
}
#endif
