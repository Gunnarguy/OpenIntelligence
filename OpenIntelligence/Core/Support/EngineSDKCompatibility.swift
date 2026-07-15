#if OPENINTELLIGENCE_ENGINE_SDK

import Foundation
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
import Security
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

/// Helper utility to dynamically check entitlements in the app signature at runtime.
public struct EntitlementChecker {
    public static let privateCloudComputeKey = "com.apple.developer.private-cloud-compute"

    /// Reads the entitlement from the running process's signed code object.
    /// Unlike provisioning-profile text scanning, this also works after App Store
    /// and TestFlight strip the embedded profile from the distributed bundle.
    public static func hasEntitlement(_ entitlementKey: String) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil),
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
        #endif
    }
}

#endif
