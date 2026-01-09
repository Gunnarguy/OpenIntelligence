//
//  RAGService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
    import FoundationModels
#endif

// NOTE: Local model support (GGUF, CoreML, MLX) has been removed.
// The app now uses Apple Intelligence and On-Device Analysis only.

struct RetrievalLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let containerId: UUID
    let containerName: String
    let chunks: [RetrievedChunk]
}

struct RAGAuditSnapshot: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let containerId: UUID
    let containerName: String

    let embeddingProviderId: String
    let embeddingDim: Int
    let vectorDBKind: VectorDBKind
    let chunkingTargetWords: Int
    let chunkingOverlapWords: Int
    let chunkingSource: String
    let qualityMode: RAGQualityMode
    let retrievalConfig: RetrievalConfig

    let lenientRetrieval: Bool
    let dynamicMin: Float
    let topSim: Float
    let secondSim: Float
    let avgTop5: Float
    let acceptanceOverride: Bool

    let totalStoredChunks: Int
    let candidatesCount: Int
    let rerankedCount: Int
    let filteredCount: Int
    let droppedCount: Int
    let mmrSelectedCount: Int
    let uniqueDocCount: Int

    let contextStrategy: String

    let contextChars: Int
    let contextWords: Int
    let contextChunksUsed: Int
    let maxContextChars: Int
    let baseWindowTokens: Int
    let safetyTokens: Int
    let promptOverheadTokens: Int
    let questionTokens: Int
    let reservedOutputTokens: Int
    let availableContextTokens: Int

    let executionContext: ExecutionContext
    let allowPrivateCloudCompute: Bool
    let networkConnected: Bool
    let wantsCloudContext: Bool
    let reliabilityModeEnabled: Bool
    let allowUngroundedFallback: Bool
    let modelName: String
}

struct VectorStoreAudit: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let containerId: UUID
    let containerName: String
    let expectedDimension: Int
    let totalChunks: Int
    let mismatchedDimensions: Int
    let uniqueDocuments: Int
    let averageChunkWords: Double
    let minChunkWords: Int
    let maxChunkWords: Int
}

struct ReembedProgress: Sendable {
    let completed: Int
    let total: Int
    let currentFilename: String

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum IngestionContext: Sendable {
    case userInitiated
    case autoRebuild

    var allowsSelfTuningScheduling: Bool {
        switch self {
        case .userInitiated:
            return true
        case .autoRebuild:
            return false
        }
    }
}

/// Main orchestrator for the RAG (Retrieval-Augmented Generation) pipeline
/// Coordinates document processing, embedding, retrieval, and generation
class RAGService: ObservableObject {
    // MARK: - Dependencies

    private let documentProcessor: DocumentProcessor
    private let embeddingService: EmbeddingService
    private let embeddingServiceWasInjected: Bool
    let containerService: ContainerService
    private let vectorRouter: VectorStoreRouter
    private let intelligenceCenter = LibraryIntelligenceCenter()
    private weak var entitlementStore: EntitlementStore?
    private var cancellables = Set<AnyCancellable>()
    @MainActor private weak var settingsStore: SettingsStore?
    @MainActor private var pendingConsentContinuation: CheckedContinuation<CloudConsentDecision, Never>?
    @MainActor private var transientConsentGrants: Set<CloudProvider> = []
    @MainActor private var pccSuppressedUntil: Date?
    @MainActor private var suppressProcessingSummary: Bool = false
    @MainActor private var ingestionTask: Task<Void, Never>?
    @MainActor private var ingestionContexts: [UUID: IngestionContext] = [:]

    /// Helper to get document name by ID
    @MainActor
    func getDocumentName(for documentId: UUID) -> String {
        return documents.first(where: { $0.id == documentId })?.filename ?? "Unknown"
    }

    /// Latest intelligence summary for a given container, if one exists
    @MainActor
    func intelligenceReport(for containerId: UUID?) -> LibraryIntelligenceCenter.IntelligenceReport? {
        guard let id = containerId else { return nil }
        return containerIntelligence[id]
    }

    /// Clear cached intelligence for a container (call when embedding/chunking config changes)
    @MainActor
    func clearIntelligence(for containerId: UUID) {
        containerIntelligence.removeValue(forKey: containerId)
        Log.info("[RAGService] Cleared intelligence cache for container \(containerId)", category: .retrieval)
    }

    /// Recompute the intelligence snapshot for a container on demand.
    @discardableResult
    func refreshIntelligence(for containerId: UUID? = nil, force: Bool = false) -> Task<Void, Never> {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.generateIntelligenceSnapshot(for: containerId, force: force)
        }
    }

    /// Run a storage integrity audit on the active container's vector database.
    @discardableResult
    func runVectorAudit(for containerId: UUID? = nil) async -> VectorStoreAudit? {
        let resolvedId: UUID? = await MainActor.run {
            containerId ?? self.containerService.activeContainerId
        }
        guard let targetId = resolvedId else { return nil }
        let container = await MainActor.run {
            self.containerService.containers.first { $0.id == targetId }
        }
        guard let container else { return nil }

        let db = await dbFor(targetId)
        let chunks = (try? await db.allChunks()) ?? []
        let expectedDim = container.embeddingDim
        let mismatched = chunks.filter { $0.embedding.count != expectedDim }.count
        let wordCounts = chunks.map { $0.content.split(whereSeparator: { $0.isWhitespace }).count }
        let totalWords = wordCounts.reduce(0, +)
        let avgWords = wordCounts.isEmpty ? 0.0 : Double(totalWords) / Double(wordCounts.count)
        let minWords = wordCounts.min() ?? 0
        let maxWords = wordCounts.max() ?? 0
        let uniqueDocs = Set(chunks.map { $0.documentId }).count

        let audit = VectorStoreAudit(
            timestamp: Date(),
            containerId: targetId,
            containerName: container.name,
            expectedDimension: expectedDim,
            totalChunks: chunks.count,
            mismatchedDimensions: mismatched,
            uniqueDocuments: uniqueDocs,
            averageChunkWords: avgWords,
            minChunkWords: minWords,
            maxChunkWords: maxWords
        )

        await MainActor.run {
            self.lastVectorAudit = audit
        }

        return audit
    }

    private func generateIntelligenceSnapshot(for containerId: UUID?, force: Bool) async {
        let resolvedId: UUID? = await MainActor.run {
            containerId ?? self.containerService.activeContainerId
        }
        guard let targetId = resolvedId else { return }

        let shouldSkip = await MainActor.run { () -> Bool in
            if force { return false }
            return self.containerIntelligence[targetId] != nil
        }
        if shouldSkip { return }

        let docs = await MainActor.run { self.documentsForContainer(targetId) }
        let database = await dbFor(targetId)
        let chunks = (try? await database.allChunks()) ?? []
        let report = await intelligenceCenter.analyzeLibrary(
            documents: docs,
            chunks: chunks
        )

        await MainActor.run {
            self.containerIntelligence[targetId] = report
        }

        await handleSelfTuning(
            for: targetId,
            report: report,
            triggerAllowsScheduling: force
        )
    }

    @MainActor
    private func documentsForContainer(_ containerId: UUID) -> [Document] {
        let defaultContainerId = containerService.containers.first?.id
        return documents.filter { document in
            if let docContainer = document.containerId {
                return docContainer == containerId
            } else {
                return containerId == defaultContainerId
            }
        }
    }

    // MARK: - Chat History

    /// Returns chat history scoped to a specific container, loading from disk if needed.
    @MainActor
    func chatHistory(for containerId: UUID?) -> [ChatMessage] {
        let resolvedId = containerId ?? containerService.activeContainerId
        if let cached = chatHistories[resolvedId] {
            return cached
        }
        let loaded = loadChatHistoryFromDisk(for: resolvedId)
        chatHistories[resolvedId] = loaded
        return loaded
    }

    /// Persists chat history for a container and updates the in-memory cache.
    @MainActor
    func persistChatHistory(_ messages: [ChatMessage], for containerId: UUID?) {
        let resolvedId = containerId ?? containerService.activeContainerId
        chatHistories[resolvedId] = messages
        saveChatHistory(messages, for: resolvedId)
    }

    /// Clears chat history for a container both in memory and on disk.
    @MainActor
    func clearChatHistory(for containerId: UUID?) {
        let resolvedId = containerId ?? containerService.activeContainerId
        chatHistories[resolvedId] = []
        saveChatHistory([], for: resolvedId)
    }

    @MainActor
    private func loadChatHistoryFromDisk(for containerId: UUID) -> [ChatMessage] {
        let url = AppSupportPaths.chatHistoryURL(containerId: containerId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            Log.error("[RAGService] Failed to load chat history for container \(containerId): \(error.localizedDescription)", category: .initialization)
            return []
        }
    }

    @MainActor
    private func saveChatHistory(_ messages: [ChatMessage], for containerId: UUID) {
        let url = AppSupportPaths.chatHistoryURL(containerId: containerId)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(messages)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("[RAGService] Failed to save chat history for container \(containerId): \(error.localizedDescription)", category: .initialization)
        }
    }

    // MARK: - Published State (MainActor-isolated for SwiftUI)

    /// The container context for the currently executing query (if any).
    /// Used to scope agentic tool calls and document listings during an in-flight query.
    @MainActor private var currentQueryContainerId: UUID? = nil

    @MainActor @Published var documents: [Document] = []
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var processingStatus: String = ""
    @MainActor @Published var lastError: String? = nil // User-facing error message
    @MainActor @Published var lastProcessingSummary: ProcessingSummary? = nil // Detailed completion stats
    @MainActor @Published private(set) var ingestionItems: [IngestionItem] = []
    @MainActor @Published private(set) var retrievalHistory: [RetrievalLogEntry] = []
    @MainActor @Published var pendingCloudConsent: CloudTransmissionRecord?
    @MainActor @Published private(set) var lastCloudTransmission: CloudTransmissionRecord?
    @MainActor @Published private(set) var cloudConsent: [CloudProvider: CloudConsentState] = [:]
    @MainActor @Published private(set) var containerIntelligence: [UUID: LibraryIntelligenceCenter.IntelligenceReport] = [:]
    @MainActor @Published private(set) var chatHistories: [UUID: [ChatMessage]] = [:]
    @MainActor @Published var thinkingEvents: [ThinkingEvent] = []
    @MainActor @Published private(set) var lastAuditSnapshot: RAGAuditSnapshot?
    @MainActor @Published private(set) var lastVectorAudit: VectorStoreAudit?

    /// Published model name for UI binding - updates when LLM service changes
    @MainActor @Published private(set) var activeModelName: String = "Loading..."
    @MainActor private var selfTuningInFlight: Set<UUID> = []

    // If an embedding provider/dimension changes while processing is active (e.g. ingestion),
    // defer rebuild work until processing completes to restore retrieval.
    @MainActor private var pendingReembedContainerIds: Set<UUID> = []
    @MainActor private var pendingReembedTask: Task<Void, Never>?

    private(set) var totalChunksStored: Int = 0
    private let retrievalHistoryLimit = 50

    // MARK: - Public Access (for Settings)

    var llmService: LLMService {
        return _llmService
    }

    private var _llmService: LLMService
    private var _fallbackServices: [LLMService] = []

    private enum ChunkingDefaults {
        static let targetWindow = 400
        static let overlap = 75
    }

    private struct EmbeddingAutoAction {
        let providerId: String
        let dimension: Int
        let reason: String
    }

    /// Snapshot of the embedding configuration for the active query/document scope
    private struct EmbeddingContext {
        let containerId: UUID
        let containerName: String
        let providerId: String
        let dimension: Int
        let service: EmbeddingService
    }

    struct EmbeddingDiagnosticsSnapshot: Identifiable, Sendable {
        let containerId: UUID
        let containerName: String
        let embeddingProviderId: String
        let dimension: Int
        let autoAdaptEnabled: Bool
        let retrievalConfig: RetrievalConfig
        let documentCount: Int
        let chunkCount: Int

        var id: UUID { containerId }

        func makeEmbeddingService() -> EmbeddingService {
            EmbeddingService.forProvider(id: embeddingProviderId, targetDimension: dimension)
        }
    }

    private struct ChunkAutoAction {
        let directive: ChunkingDirective
        let reason: String
    }

    private enum ConsentDefaults {
        static func key(for provider: CloudProvider) -> String {
            switch provider {
            case .applePCC: return "cloudConsent.applePCC"
            }
        }
    }

    // MARK: - Initialization

    init(
        documentProcessor: DocumentProcessor? = nil,
        embeddingService: EmbeddingService? = nil,
        vectorDatabase _: VectorDatabase? = nil,
        llmService: LLMService? = nil,
        containerService: ContainerService? = nil,
        vectorRouter: VectorStoreRouter? = nil,
        entitlementStore: EntitlementStore? = nil
    ) {
        self.documentProcessor = documentProcessor ?? DocumentProcessor()
        if let embeddingService {
            self.embeddingService = embeddingService
            embeddingServiceWasInjected = true
        } else {
            self.embeddingService = EmbeddingService()
            embeddingServiceWasInjected = false
        }
        // Container + Vector store routing
        self.containerService = containerService ?? ContainerService()
        self.vectorRouter = vectorRouter ?? VectorStoreRouter()
        self.entitlementStore = entitlementStore

        // Priority order for LLM selection:
        // 1. Custom service provided by caller
        // 2. User-selected model from Settings
        // 3. On-Device Analysis (extractive QA, always available)

        if let service = llmService {
            // User provided custom service (e.g., from Settings)
            _llmService = service
            activeModelName = service.modelName
            Log.info("✓ Using custom LLM service: \(service.modelName)", category: .initialization)
        } else {
            // Check user's selected model from Settings
            let selectedModelRaw =
                UserDefaults.standard.string(forKey: "selectedLLMModel") ?? "apple_intelligence"

            Log.info(
                "🔧 Initializing with user's selected model: \(selectedModelRaw)",
                category: .initialization
            )

            let selectedIsApple = (selectedModelRaw == "apple_intelligence")
            // Try to instantiate the user's selected model first
            let primaryService = Self.instantiateService(
                for: selectedModelRaw,
                entitlementStore: entitlementStore
            )
            var fallbackServices = Self.buildFallbackChain(excluding: selectedModelRaw)

            // If the user's primary model is available, avoid surprising runtime fallbacks to
            // On-Device Analysis. We still keep it as an initialization-time escape hatch when
            // Apple Intelligence is unavailable on the device.
            if primaryService != nil {
                fallbackServices.removeAll { $0 is OnDeviceAnalysisService }
            }

            let resolvedService: LLMService
            if let primaryService {
                resolvedService = primaryService
            } else if let fallback = fallbackServices.first {
                fallbackServices.removeFirst()
                Log.warning(
                    "Selected model \(selectedModelRaw) unavailable; falling back to \(fallback.modelName)",
                    category: .initialization
                )
                Log.info("✓ Using \(fallback.modelName) as active model", category: .initialization)
                if selectedIsApple {
                    lastError = "Apple Intelligence is unavailable or disabled on this device. Using fallback instead."
                }
                resolvedService = fallback
                #if canImport(FoundationModels)
                    if #available(iOS 26.0, *),
                       let foundationFallback = resolvedService as? AppleFoundationLLMService
                    {
                        foundationFallback.startWarmup()
                        Log.debug(
                            "🔥 Preloading model in background for instant first query",
                            category: .initialization
                        )
                    }
                #endif
            } else {
                Log.error(
                    "No configured LLM available; Apple Intelligence is REQUIRED",
                    category: .initialization
                )
                #if targetEnvironment(simulator)
                    lastError = "⚠️ Running in Simulator: Apple Intelligence requires a physical device with A17 Pro chip or later. Please run on a compatible iPhone."
                #else
                    lastError = "⚠️ Apple Intelligence is required but unavailable. Enable it in Settings → Apple Intelligence & Siri."
                #endif
                // Still need a service instance to avoid nil crashes, but it will always throw
                resolvedService = AppleFoundationLLMServiceUnavailable()
            }

            _llmService = resolvedService
            activeModelName = resolvedService.modelName
            _fallbackServices = fallbackServices

            // Connect tool handler for agentic RAG (Foundation Models only)
            _llmService.toolHandler = self
            Log.info("🔗 Tool handler connected for agentic RAG", category: .initialization)
        }

        // Load persisted documents metadata
        Task { @MainActor in
            self.cloudConsent = self.loadPersistedConsentStates()
        }
        loadDocumentsFromDisk()
    }

    // MARK: - Cloud Consent

    private func loadPersistedConsentStates() -> [CloudProvider: CloudConsentState] {
        var states: [CloudProvider: CloudConsentState] = [:]
        states.reserveCapacity(CloudProvider.allCases.count)
        for provider in CloudProvider.allCases {
            let key = ConsentDefaults.key(for: provider)
            if let raw = UserDefaults.standard.string(forKey: key),
               let state = CloudConsentState(rawValue: raw)
            {
                states[provider] = state
            } else {
                states[provider] = .notDetermined
            }
        }
        return states
    }

    private func persistConsentState(_ state: CloudConsentState, for provider: CloudProvider) {
        let defaults = UserDefaults.standard
        let key = ConsentDefaults.key(for: provider)
        if state == .notDetermined {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(state.rawValue, forKey: key)
        }
    }

    @MainActor
    func registerSettingsStore(_ store: SettingsStore) {
        settingsStore = store
        // Defer sync so SwiftUI finishes its current view update before we publish changes.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyInitialCloudConsent(from: store)
        }
    }

    /// Rebuild the active LLM service and fallback chain from the current SettingsStore.
    /// This keeps runtime routing aligned with Settings without requiring app restart.
    @MainActor
    func rebuildLLMServicesFromSettings() async {
        guard let store = settingsStore else { return }

        let primaryKey = store.selectedModel.rawValue
        var primary: LLMService = Self.instantiateService(for: primaryKey, entitlementStore: entitlementStore)
            ?? AppleFoundationLLMServiceUnavailable()

        var fallbacks: [LLMService] = []
        fallbacks.reserveCapacity(2)

        if store.enableFirstFallback {
            if let service = Self.instantiateService(for: store.firstFallback.rawValue, entitlementStore: entitlementStore),
               service.modelName != primary.modelName
            {
                fallbacks.append(service)
            }
        }

        if store.enableSecondFallback {
            if let service = Self.instantiateService(for: store.secondFallback.rawValue, entitlementStore: entitlementStore),
               service.modelName != primary.modelName,
               !fallbacks.contains(where: { $0.modelName == service.modelName })
            {
                fallbacks.append(service)
            }
        }

        // Ensure tool handler remains connected for agentic RAG.
        primary.toolHandler = self
        for i in fallbacks.indices {
            fallbacks[i].toolHandler = self
        }

        updateLLMService(primary, fallbacks: fallbacks)
    }

    @MainActor
    private func applyInitialCloudConsent(from store: SettingsStore) {
        if cloudConsent[.applePCC] != store.applePCCConsent {
            setCloudConsentState(
                store.applePCCConsent,
                for: .applePCC,
                propagateToSettings: false
            )
        }
    }

    @MainActor
    func setCloudConsentState(
        _ state: CloudConsentState,
        for provider: CloudProvider,
        propagateToSettings: Bool = true
    ) {
        cloudConsent[provider] = state
        transientConsentGrants.remove(provider)
        persistConsentState(state, for: provider)
        if propagateToSettings {
            settingsStore?.setCloudConsent(state, for: provider, propagateToRAG: false)
        }
    }

    @MainActor
    func resolveCloudConsent(decision: CloudConsentDecision) async {
        guard let record = pendingCloudConsent else {
            Log.warning("resolveCloudConsent called with no pending record", category: .pipeline)
            return
        }
        let provider = record.provider
        let continuation = pendingConsentContinuation
        pendingConsentContinuation = nil
        pendingCloudConsent = nil

        switch decision {
        case .allowOnce:
            await recordTransmission(record, grant: "allow_once")
            continuation?.resume(returning: .allowOnce)
        case .allowAndRemember:
            setCloudConsentState(.allowed, for: provider)
            await recordTransmission(record, grant: "remembered")
            continuation?.resume(returning: .allowAndRemember)
        case .deny:
            setCloudConsentState(.denied, for: provider)
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Cloud call denied",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                    "chars": "\(record.promptCharacterCount)",
                    "chunks": "\(record.contextChunkCount)",
                ]
            )
            continuation?.resume(returning: .deny)
        }
    }

    private func makeTransmissionRecord(
        provider: CloudProvider,
        modelName: String,
        prompt: String,
        context: String?,
        chunks: [DocumentChunk]
    ) -> CloudTransmissionRecord {
        let sanitizedPrompt = prompt.replacingOccurrences(of: "\n", with: " ")
        let preview = String(sanitizedPrompt.prefix(160))
        let estimatedBytes = prompt.utf8.count + (context?.utf8.count ?? 0)

        var hashes: [String] = []
        hashes.reserveCapacity(min(chunks.count, 12))
        for chunk in chunks.prefix(12) {
            let data = Data(chunk.content.utf8)
            let digest = SHA256.hash(data: data)
            hashes.append(hexString(from: digest))
        }

        return CloudTransmissionRecord(
            provider: provider,
            modelName: modelName,
            promptPreview: preview,
            promptCharacterCount: prompt.count,
            contextChunkCount: chunks.count,
            contextHashes: hashes,
            estimatedBytes: estimatedBytes
        )
    }

    private func hexString(from digest: SHA256.Digest) -> String {
        var result = String()
        result.reserveCapacity(SHA256Digest.byteCount * 2)
        for byte in digest {
            result.append(String(format: "%02x", byte))
        }
        return result
    }

    private func cloudProvider(for service: LLMService) -> CloudProvider? {
        switch service {
        #if canImport(FoundationModels)
            case is AppleFoundationLLMService:
                return .applePCC
        #endif
        default:
            return nil
        }
    }

    private func ensureCloudConsentIfNeeded(
        service: LLMService,
        prompt: String,
        context: String?,
        sourceChunks: [DocumentChunk],
        allowPrivateCloudCompute: Bool
    ) async throws {
        guard let provider = cloudProvider(for: service) else { return }
        if !allowPrivateCloudCompute, provider == .applePCC {
            return // User blocked PCC; don't prompt for consent we won't use
        }
        let record = makeTransmissionRecord(
            provider: provider,
            modelName: service.modelName,
            prompt: prompt,
            context: context,
            chunks: sourceChunks
        )

        if await hasTransientGrant(for: provider) {
            await recordTransmission(record, grant: "session")
            return
        }

        let decision = await cloudConsentDecision(for: provider, record: record)

        switch decision {
        case .allowOnce:
            await rememberTransientGrant(provider)
            return
        case .allowAndRemember:
            return
        case .deny:
            throw RAGServiceError.cloudConsentDenied(provider: provider)
        }
    }

    @MainActor
    private func cloudConsentDecision(
        for provider: CloudProvider,
        record: CloudTransmissionRecord
    ) async -> CloudConsentDecision {
        let state = cloudConsent[provider] ?? .notDetermined
        switch state {
        case .allowed:
            await recordTransmission(record, grant: "remembered")
            return .allowAndRemember
        case .denied:
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Cloud call blocked (denied)",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                ]
            )
            return .deny
        case .notDetermined:
            if let continuation = pendingConsentContinuation {
                continuation.resume(returning: .deny)
                pendingConsentContinuation = nil
            }
            pendingCloudConsent = record
            TelemetryCenter.emit(
                .system,
                title: "Cloud consent requested",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                    "chars": "\(record.promptCharacterCount)",
                    "chunks": "\(record.contextChunkCount)",
                ]
            )
            return await withCheckedContinuation { continuation in
                pendingConsentContinuation = continuation
            }
        }
    }

    @MainActor
    private func recordTransmission(_ record: CloudTransmissionRecord, grant: String) async {
        pendingCloudConsent = nil
        lastCloudTransmission = record
        TelemetryCenter.emit(
            .system,
            title: "Cloud call authorized",
            metadata: [
                "provider": record.provider.shortName,
                "model": record.modelName,
                "chars": "\(record.promptCharacterCount)",
                "chunks": "\(record.contextChunkCount)",
                "bytes": "\(record.estimatedBytes)",
                "grant": grant,
            ]
        )
    }

    @MainActor
    private func hasTransientGrant(for provider: CloudProvider) async -> Bool {
        transientConsentGrants.contains(provider)
    }

    @MainActor
    private func rememberTransientGrant(_ provider: CloudProvider) async {
        transientConsentGrants.insert(provider)
    }

    @MainActor
    private func isPCCSuppressed(now: Date = Date()) -> Bool {
        guard let until = pccSuppressedUntil else { return false }
        if until > now { return true }
        pccSuppressedUntil = nil
        return false
    }

    @MainActor
    private func suppressPCC(for duration: TimeInterval, reason: String) {
        let until = Date().addingTimeInterval(duration)
        if let existing = pccSuppressedUntil, existing > until {
            return
        }
        pccSuppressedUntil = until
        Log.warning(
            "[RAG] PCC suppression enabled for \(Int(duration))s (\(reason))",
            category: .pipeline
        )
    }

    // MARK: - Document Persistence

    private var documentsStorageURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let appDirectory = appSupportURL.appendingPathComponent("OpenIntelligence", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("documents_metadata.json")
    }

    private func loadDocumentsFromDisk() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documentsStorageURL.path) else {
            Log.info("  [RAGService] No existing documents metadata found")
            return
        }

        do {
            let data = try Data(contentsOf: documentsStorageURL)
            let decoder = JSONDecoder()
            let loadedDocuments = try decoder.decode([Document].self, from: data)

            Task { @MainActor in
                self.documents = loadedDocuments
                self.totalChunksStored = loadedDocuments.reduce(0) { $0 + $1.totalChunks }
                Log.info("[RAGService] Loaded \(loadedDocuments.count) documents (\(totalChunksStored) chunks)")
                if !loadedDocuments.isEmpty {
                    self.refreshIntelligence(for: nil)
                }
            }
        } catch {
            Log.error(" [RAGService] Failed to load documents metadata: \(error.localizedDescription)")
        }
    }

    private func saveDocumentsToDisk() {
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(documents)
                try data.write(to: documentsStorageURL, options: .atomic)
                Log.debug(" [RAGService] Saved \(documents.count) documents metadata")
            } catch {
                Log.error("[RAGService] Failed to save documents metadata: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Vector DB Access

    /// Invalidate cached vector store for a container (call when dimension/DB kind changes)
    /// Also clears persisted storage to ensure fresh start with new dimensions.
    func invalidateVectorStore(for containerId: UUID, clearStorage: Bool = true) {
        if clearStorage {
            vectorRouter.invalidateAndClearStorage(containerId: containerId)
            Log.info("[RAGService] Invalidated and cleared vector store for container \(containerId)", category: .retrieval)
        } else {
            vectorRouter.invalidate(containerId: containerId)
            Log.info("[RAGService] Invalidated vector store cache for container \(containerId)", category: .retrieval)
        }
    }

    private func dbForActiveContainer() async -> VectorDatabase {
        return await MainActor.run {
            let container = self.containerService.activeContainer
            // ContainerService guarantees at least one container
            return self.vectorRouter.db(for: container!)
        }
    }

    /// Return a database for a specific container id (falls back to active on miss)
    private func dbFor(_ containerId: UUID) async -> VectorDatabase {
        return await MainActor.run {
            if let container = self.containerService.containers.first(where: { $0.id == containerId }) {
                return self.vectorRouter.db(for: container)
            } else if let active = self.containerService.activeContainer {
                return self.vectorRouter.db(for: active)
            } else {
                // Fallback: should never happen but create temp in-memory DB
                return InMemoryVectorDatabase(dimension: 512)
            }
        }
    }

    /// Return all chunks stored for the active container.
    /// Used by visualization views to render embedding spaces and statistics.
    func allChunksForActiveContainer() async -> [DocumentChunk] {
        let db = await dbForActiveContainer()
        do {
            return try await db.allChunks()
        } catch {
            Log.error("[RAGService] Failed to load all chunks: \(error.localizedDescription)")
            return []
        }
    }

    func embeddingDiagnosticsSnapshot() async -> EmbeddingDiagnosticsSnapshot {
        let context = await resolveEmbeddingContext()
        let containerDetails = await MainActor.run {
            self.containerService.containers.first { $0.id == context.containerId }
        }

        return EmbeddingDiagnosticsSnapshot(
            containerId: context.containerId,
            containerName: containerDetails?.name ?? context.containerName,
            embeddingProviderId: containerDetails?.embeddingProviderId ?? context.providerId,
            dimension: containerDetails?.embeddingDim ?? context.dimension,
            autoAdaptEnabled: containerDetails?.autoAdaptDimension ?? false,
            retrievalConfig: containerDetails?.retrievalConfig ?? .default,
            documentCount: containerDetails?.totalDocuments ?? 0,
            chunkCount: containerDetails?.totalChunks ?? 0
        )
    }

    /// Resolve the embedding service + metadata for the current (or preferred) container context
    private func resolveEmbeddingContext(preferredContainerId: UUID? = nil) async -> EmbeddingContext {
        let container: KnowledgeContainer? = await MainActor.run {
            if let id = preferredContainerId,
               let scoped = self.containerService.containers.first(where: { $0.id == id })
            {
                return scoped
            }

            if let currentQueryId = self.currentQueryContainerId,
               let scoped = self.containerService.containers.first(where: { $0.id == currentQueryId })
            {
                return scoped
            }

            if let active = self.containerService.activeContainer {
                return active
            }

            return self.containerService.containers.first
        }

        guard let container else {
            let fallbackId = await MainActor.run { self.containerService.activeContainerId }
            Log.error("No knowledge containers available; using default embedding service", category: .embedding)
            return EmbeddingContext(
                containerId: fallbackId,
                containerName: "Unknown",
                providerId: "nl_embedding",
                dimension: embeddingService.outputDimension,
                service: embeddingService
            )
        }

        if embeddingServiceWasInjected,
           embeddingService.outputDimension == container.embeddingDim
        {
            return EmbeddingContext(
                containerId: container.id,
                containerName: container.name,
                providerId: embeddingService.actualProviderId,
                dimension: embeddingService.outputDimension,
                service: embeddingService
            )
        }

        let service = EmbeddingService.forProvider(
            id: container.embeddingProviderId,
            targetDimension: container.embeddingDim,
            allowFallback: true
        )

        let actualProviderId = service.actualProviderId
        let actualDimension = service.outputDimension

        if container.embeddingProviderId != actualProviderId || container.embeddingDim != actualDimension {
            Log.warning(
                "[RAGService] Embedding config mismatch for container \(container.id). " +
                    "Configured=\(container.embeddingProviderId) \(container.embeddingDim)D, " +
                    "Actual=\(actualProviderId) \(actualDimension)D. Reconciling and rebuilding index.",
                category: .embedding
            )

            await MainActor.run {
                var updated = container
                updated.embeddingProviderId = actualProviderId
                updated.embeddingDim = actualDimension
                self.containerService.updateContainer(updated)

                // Clear any persisted vectors created under a different dimension.
                self.invalidateVectorStore(for: container.id, clearStorage: true)

                // If the library already has docs, reindex so retrieval works again.
                let hasDocs = !self.documentsForContainer(container.id).isEmpty
                guard hasDocs else { return }

                if self.isProcessing {
                    // Defer rebuild until processing completes.
                    self.enqueuePendingReembed(containerId: container.id)
                    return
                }

                Task(priority: .utility) { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.reembedDocuments(in: container.id)
                    } catch {
                        Log.error("[RAGService] Failed to rebuild index after embedding mismatch: \(error)", category: .embedding)
                    }
                }
            }
        }

        return EmbeddingContext(
            containerId: container.id,
            containerName: container.name,
            providerId: actualProviderId,
            dimension: actualDimension,
            service: service
        )
    }

    // MARK: - LLM Service Management

    /// Dynamically updates the LLM service (called from Settings)
    func updateLLMService(_ newService: LLMService) async {
        await MainActor.run {
            self._llmService = newService
            self.activeModelName = newService.modelName // Update published property for UI
            Log.info("✓ Switched to: \(newService.modelName)", category: .initialization)
        }
    }

    /// Run a lightweight semantic search against the active container.
    /// Returns ranked chunks enriched with document metadata for UI display.
    func semanticSearch(
        query: String,
        topK: Int = 6,
        minSimilarity: Float? = nil
    ) async throws -> [RetrievedChunk] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RAGServiceError.emptyQuery }

        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: trimmed)
        let database = await dbFor(embeddingContext.containerId)
        let searchCount = max(1, min(topK * 2, topK + 4))
        var candidates = try await database.search(embedding: queryEmbedding, topK: searchCount)

        if let threshold = minSimilarity {
            let engine = RAGEngine()
            candidates = await engine.filterBySimilarity(chunks: candidates, min: threshold)
        }

        if candidates.count > topK {
            candidates = Array(candidates.prefix(topK))
        }

        let docsSnapshot = await snapshotDocuments()
        let enriched = candidates.enumerated().map { index, chunk in
            let docName = docsSnapshot.first(where: { $0.id == chunk.chunk.documentId })?.filename ?? "Unknown"
            return RetrievedChunk(
                chunk: chunk.chunk,
                similarityScore: chunk.similarityScore,
                rank: index + 1,
                sourceDocument: docName,
                pageNumber: chunk.chunk.metadata.pageNumber
            )
        }
        TelemetryCenter.emit(
            .retrieval,
            title: "Semantic search",
            metadata: [
                "query": String(trimmed.prefix(80)),
                "results": "\(enriched.count)",
                "topK": "\(topK)",
            ]
        )
        return enriched
    }

    // MARK: - Document Management

    @MainActor
    @discardableResult
    func enqueueDocuments(_ urls: [URL], context: IngestionContext = .userInitiated) -> [UUID] {
        guard !urls.isEmpty else { return [] }
        let newItems = urls.map { url in
            let item = IngestionItem(url: url, stage: .queued, detail: "Queued")
            ingestionContexts[item.id] = context
            return item
        }
        ingestionItems.append(contentsOf: newItems)
        if ingestionItems.count > 1 {
            suppressProcessingSummary = true
        }
        startIngestionTaskIfNeeded()
        return newItems.map { $0.id }
    }

    func ingestDocuments(
        _ urls: [URL],
        context: IngestionContext = .userInitiated
    ) async -> IngestionBatchResult {
        let ids = await MainActor.run { enqueueDocuments(urls, context: context) }
        return await waitForIngestionCompletion(ids: ids)
    }

    @MainActor
    private func startIngestionTaskIfNeeded() {
        guard ingestionTask == nil else { return }
        ingestionTask = Task { [weak self] in
            guard let self else { return }
            await self.runIngestionLoop()
        }
    }

    private func runIngestionLoop() async {
        await MainActor.run { self.isProcessing = true }
        while let next = await MainActor.run(body: { self.nextQueuedIngestionItem() }) {
            let context = await MainActor.run { self.ingestionContexts[next.id] ?? .userInitiated }
            do {
                try await addDocument(
                    at: next.url,
                    context: context,
                    trackingId: next.id,
                    manageProcessingState: false
                )
            } catch {
                await MainActor.run {
                    self.markIngestionFailed(id: next.id, error: error)
                }
            }
        }
        await MainActor.run {
            self.isProcessing = false
            self.processingStatus = ""
            self.ingestionTask = nil
            self.suppressProcessingSummary = false
            self.pruneCompletedIngestionItems()
            self.kickPendingReembedIfNeeded()
        }
    }

    @MainActor
    private func enqueuePendingReembed(containerId: UUID) {
        pendingReembedContainerIds.insert(containerId)
        kickPendingReembedIfNeeded()
    }

    /// If we have queued re-embed work and the app is idle, run it.
    /// This prevents leaving a library with an empty index after a provider/dimension fallback.
    @MainActor
    private func kickPendingReembedIfNeeded() {
        guard !isProcessing else { return }
        guard pendingReembedTask == nil else { return }
        guard !pendingReembedContainerIds.isEmpty else { return }

        let containerIds = Array(pendingReembedContainerIds)
        pendingReembedContainerIds.removeAll()

        pendingReembedTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            for id in containerIds {
                do {
                    try await self.reembedDocuments(in: id)
                } catch {
                    Log.error("[RAGService] Deferred re-embed failed for container \(id): \(error)", category: .embedding)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pendingReembedTask = nil
                // If anything queued up while we were running, kick again.
                self.kickPendingReembedIfNeeded()
            }
        }
    }

    @MainActor
    private func nextQueuedIngestionItem() -> IngestionItem? {
        ingestionItems.first { $0.stage == .queued }
    }

    @MainActor
    private func updateIngestionItem(
        id: UUID?,
        filename: String,
        stage: IngestionStage,
        detail: String,
        progress: Double? = nil,
        errorMessage: String? = nil
    ) {
        processingStatus = "\(filename) • \(detail)"
        guard let id, let index = ingestionItems.firstIndex(where: { $0.id == id }) else { return }
        var item = ingestionItems[index]
        item.stage = stage
        item.detail = detail
        item.progress = progress
        if item.startedAt == nil, stage != .queued {
            item.startedAt = Date()
        }
        if stage.isTerminal {
            item.finishedAt = Date()
        }
        if let errorMessage {
            item.errorMessage = errorMessage
        }
        ingestionItems[index] = item
    }

    @MainActor
    private func markIngestionFailed(id: UUID, error: Error) {
        if let item = ingestionItems.first(where: { $0.id == id }) {
            updateIngestionItem(
                id: id,
                filename: item.filename,
                stage: .failed,
                detail: "Failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    private func waitForIngestionCompletion(ids: [UUID]) async -> IngestionBatchResult {
        guard !ids.isEmpty else {
            return IngestionBatchResult(
                successCount: 0,
                failureCount: 0,
                totalCount: 0,
                completedIds: []
            )
        }
        while true {
            let snapshot = await MainActor.run {
                ingestionItems.filter { ids.contains($0.id) }
            }
            let allDone = snapshot.allSatisfy { $0.stage.isTerminal }
            if allDone {
                let successCount = snapshot.filter { $0.stage == .complete }.count
                let failureCount = snapshot.filter { $0.stage == .failed }.count
                return IngestionBatchResult(
                    successCount: successCount,
                    failureCount: failureCount,
                    totalCount: snapshot.count,
                    completedIds: snapshot.map { $0.id }
                )
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    @MainActor
    private func pruneCompletedIngestionItems(delay: TimeInterval = 4.0) {
        guard ingestionItems.contains(where: { $0.stage.isTerminal }) else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let self else { return }
                let hasActive = self.ingestionItems.contains { !$0.stage.isTerminal }
                if hasActive { return }
                self.ingestionItems.removeAll { $0.stage.isTerminal }
                self.ingestionContexts = self.ingestionContexts.filter { key, _ in
                    self.ingestionItems.contains(where: { $0.id == key })
                }
            }
        }
    }

    /// Add a document to the knowledge base
    /// This performs the full ingestion pipeline: parse → chunk → embed → store
    func addDocument(
        at url: URL,
        context: IngestionContext = .userInitiated,
        trackingId: UUID? = nil,
        manageProcessingState: Bool = true
    ) async throws {
        let filename = url.lastPathComponent
        let gating = await MainActor.run { () -> (limit: Int, canAdd: Bool, tier: WorkspaceTier, count: Int) in
            let count = self.documents.count
            if let store = self.entitlementStore {
                return (store.documentLimit, store.canAddDocument(currentCount: count), store.activeTier, count)
            } else {
                let limit = QuotaPolicy.documentLimit()
                return (limit, count < limit, .free, count)
            }
        }
        let documentLimit = gating.limit
        let currentDocumentCount = gating.count
        if !gating.canAdd {
            let quotaError = DocumentQuotaError(limit: documentLimit)
            await MainActor.run {
                self.lastError = quotaError.errorDescription
            }
            TelemetryCenter.emit(
                .ingestion,
                severity: .warning,
                title: "Document quota reached",
                metadata: [
                    "file": filename,
                    "limit": "\(documentLimit)",
                    "currentCount": "\(currentDocumentCount)",
                ]
            )
            TelemetryCenter.emitBillingEvent(
                "Quota hit",
                severity: .warning,
                metadata: [
                    "tier": gating.tier.rawValue,
                    "limit": "\(documentLimit)",
                    "currentCount": "\(currentDocumentCount)",
                    "file": filename,
                ]
            )
            throw quotaError
        }
        let activeContainerId = await MainActor.run { self.containerService.activeContainerId }
        let preExistingDocumentsInContainerCount = await MainActor.run {
            self.documentsForContainer(activeContainerId).count
        }

        // Get the active container to determine which embedding provider to use
        var container = await MainActor.run {
            self.containerService.containers.first { $0.id == activeContainerId }
        }
        // FIXED: Default to CoreML sentence embedding (better accuracy) instead of deprecated NLEmbedding
        var providerId = container?.embeddingProviderId ?? "coreml_sentence_embedding"
        var initialDimension = container?.embeddingDim ?? 384
        let chunkOverride = chunkingOverride(for: container)

        // Create container-specific embedding service
        var containerEmbeddingService = EmbeddingService.forProvider(
            id: providerId,
            targetDimension: initialDimension
        )

        // Check if we got a fallback provider and update providerId accordingly
        let actualProvider = containerEmbeddingService.actualProviderId
        let actualDimension = containerEmbeddingService.outputDimension

        if actualProvider != providerId || actualDimension != initialDimension {
            Log.warning(
                "[RAGService] Requested embedding context '\(providerId)' \(initialDimension)D resolved to '\(actualProvider)' \(actualDimension)D. Updating container + clearing index.",
                category: .ingestion
            )

            // Persist corrected config so subsequent queries/ingestion use the real dimension.
            if var current = container {
                current.embeddingProviderId = actualProvider
                current.embeddingDim = actualDimension
                await MainActor.run {
                    self.containerService.updateContainer(current)
                    self.invalidateVectorStore(for: activeContainerId, clearStorage: true)
                }
                container = current
            } else {
                await MainActor.run {
                    self.invalidateVectorStore(for: activeContainerId, clearStorage: true)
                }
            }

            providerId = actualProvider
            initialDimension = actualDimension

            // Recreate the embedding service with the reconciled dimension to keep downstream logging consistent.
            containerEmbeddingService = EmbeddingService.forProvider(
                id: providerId,
                targetDimension: initialDimension,
                allowFallback: true
            )
        }

        let pipelineStartTime = Date()
        TelemetryCenter.emit(
            .ingestion,
            title: "Ingestion started",
            metadata: [
                "file": filename,
                "embeddingProvider": providerId,
            ]
        )

        var pendingSelfTuneReasons: [String] = []

        await MainActor.run {
            if manageProcessingState { isProcessing = true }
            updateIngestionItem(id: trackingId, filename: filename, stage: .loading, detail: "Loading")
        }

        // Give UI time to show the overlay (short, user-visible)
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Set up progress handler for real-time updates
        documentProcessor.progressHandler = { [weak self] progress in
            Task { @MainActor in
                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .extracting,
                    detail: "Extracting (\(progress))"
                )
            }
        }

        do {
            // Step 1: Parse document and extract chunks
            let extractionStartTime = Date()
            let (document, processedChunks) = try await documentProcessor.processDocument(
                at: url,
                chunkOverride: chunkOverride
            )
            let extractionTime = Date().timeIntervalSince(extractionStartTime)
            let totalChars = processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
            let totalWords = processedChunks.reduce(0) { $0 + $1.metadata.wordCount }

            TelemetryCenter.emit(
                .ingestion,
                title: "Extraction complete",
                metadata: [
                    "file": filename,
                    "chunks": "\(processedChunks.count)",
                    "words": "\(totalWords)",
                ],
                duration: extractionTime
            )

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .chunking,
                    detail: "Chunking (\(processedChunks.count) chunks, \(totalWords) words)"
                )
            }

            // Small delay to show the chunking message
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

            // Step 1.5: Auto-adapt configuration if enabled
            if context.allowsSelfTuningScheduling,
               let autoContainer = container,
               autoContainer.autoAdaptDimension
            {
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Analyzing content"
                    )
                }

                // Get ALL existing chunks in this container for comprehensive analysis
                let db = await dbForActiveContainer()
                let existingChunks = try await db.allChunks()

                // Analyze combined corpus (existing + new document)
                let allDocumentsForAnalysis = await MainActor.run {
                    self.documents.filter { $0.containerId == activeContainerId } + [document]
                }
                let combinedChunks = existingChunks + processedChunks.enumerated().map { index, chunk in
                    DocumentChunk(
                        documentId: document.id,
                        content: chunk.text,
                        embedding: [], // Empty for analysis
                        metadata: ChunkMetadata(
                            chunkIndex: index,
                            startPosition: chunk.metadata.startPosition,
                            endPosition: chunk.metadata.endPosition,
                            pageNumber: chunk.metadata.pageNumber,
                            sectionTitle: chunk.metadata.sectionTitle,
                            keywords: chunk.metadata.keywords,
                            semanticDensity: chunk.metadata.semanticDensity,
                            hasNumericData: chunk.metadata.hasNumericData,
                            hasListStructure: chunk.metadata.hasListStructure,
                            wordCount: chunk.metadata.wordCount,
                            characterCount: chunk.metadata.characterCount,
                            createdAt: chunk.metadata.createdAt
                        )
                    )
                }

                let report = await intelligenceCenter.analyzeLibrary(
                    documents: allDocumentsForAnalysis,
                    chunks: combinedChunks
                )

                await MainActor.run {
                    self.containerIntelligence[activeContainerId] = report
                }

                // Log analysis results
                TelemetryCenter.emit(
                    .ingestion,
                    title: "Content analysis complete",
                    metadata: [
                        "file": filename,
                        "vocabularyRichness": String(format: "%.2f", report.corpus.vocabularyRichness),
                        "multilingualScore": String(format: "%.2f", report.corpus.multilingualScore),
                        "technicalDensity": String(format: "%.2f", report.corpus.technicalDensity),
                        "semanticComplexity": String(format: "%.2f", report.corpus.semanticComplexity),
                        "chunkingStrategy": report.chunking.strategy.rawValue,
                        "chunkWindow": "\(report.chunking.targetWordWindow)",
                        "chunkOverlap": "\(report.chunking.overlapWords)",
                        "retrievalFusion": report.retrieval.fusionStyle.rawValue,
                        "retrievalVectorWeight": String(format: "%.2f", report.retrieval.vectorWeight),
                        "retrievalLexicalWeight": String(format: "%.2f", report.retrieval.lexicalWeight),
                        "recommendedDimension": "\(report.embedding.dimension)",
                        "recommendedProvider": report.embedding.providerId,
                        "confidence": String(format: "%.1f%%", report.embedding.confidence * 100),
                        "reasoning": report.embedding.rationale,
                        "alerts": report.alerts.joined(separator: " | "),
                    ]
                )

                let (updatedContainer, autoReasons) = resolveAutoAdjustments(
                    for: autoContainer,
                    report: report
                )

                if updatedContainer != autoContainer {
                    let embeddingChanged =
                        updatedContainer.embeddingProviderId != autoContainer.embeddingProviderId
                            || updatedContainer.embeddingDim != autoContainer.embeddingDim

                    if embeddingChanged {
                        providerId = updatedContainer.embeddingProviderId
                        containerEmbeddingService = EmbeddingService.forProvider(
                            id: updatedContainer.embeddingProviderId,
                            targetDimension: updatedContainer.embeddingDim
                        )
                        await MainActor.run {
                            updateIngestionItem(
                                id: trackingId,
                                filename: filename,
                                stage: .analyzing,
                                detail: "Config adapted to \(updatedContainer.embeddingDim)D"
                            )
                        }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }

                    container = updatedContainer
                    await MainActor.run {
                        self.containerService.updateContainer(updatedContainer)
                    }
                }

                if context.allowsSelfTuningScheduling, !autoReasons.isEmpty {
                    // If this is the first document in the container, we've already applied the
                    // updated config *before* embedding, so there is nothing to rebuild yet.
                    // Without this guard, the app will immediately re-embed the just-added doc,
                    // which looks like an infinite “re-upload” loop to the user.
                    if preExistingDocumentsInContainerCount > 0 {
                        pendingSelfTuneReasons = autoReasons
                    } else {
                        Log.info(
                            "Skipping self-tuning rebuild: config updated during first ingest and there are no prior documents to rebuild.",
                            category: .ingestion
                        )
                    }
                }
            }

            // Step 2: Generate embeddings with progress updates
            var embeddings: [[Float]] = []
            let embeddingStartTime = Date()

            for (index, chunk) in processedChunks.enumerated() {
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .embedding,
                        detail: "Embedding (\(index + 1)/\(processedChunks.count))",
                        progress: Double(index + 1) / Double(max(1, processedChunks.count))
                    )
                }

                let embedding = try await containerEmbeddingService.generateEmbedding(for: chunk.text)
                embeddings.append(embedding)
            }

            let embeddingTime = Date().timeIntervalSince(embeddingStartTime)
            TelemetryCenter.emit(
                .embedding,
                title: "Embeddings generated",
                metadata: [
                    "file": filename,
                    "chunks": "\(processedChunks.count)",
                    "dimensions": "\(embeddings.first?.count ?? 0)",
                    "provider": providerId,
                ],
                duration: embeddingTime
            )

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .storing,
                    detail: "Storing"
                )
            }

            // Step 3: Create DocumentChunk objects with embeddings
            let chunkingStartTime = Date()
            let documentChunks = zip(processedChunks, embeddings).enumerated().map { index, pair in
                let (chunk, embedding) = pair
                let base = chunk.metadata
                let enrichedMetadata = ChunkMetadata(
                    chunkIndex: index,
                    startPosition: base.startPosition,
                    endPosition: base.endPosition,
                    pageNumber: base.pageNumber,
                    sectionTitle: base.sectionTitle,
                    keywords: base.keywords,
                    semanticDensity: base.semanticDensity,
                    hasNumericData: base.hasNumericData,
                    hasListStructure: base.hasListStructure,
                    wordCount: base.wordCount,
                    characterCount: base.characterCount,
                    createdAt: base.createdAt
                )
                return DocumentChunk(
                    documentId: document.id,
                    content: chunk.text,
                    embedding: embedding,
                    metadata: enrichedMetadata
                )
            }
            let chunkingTime = Date().timeIntervalSince(chunkingStartTime)
            TelemetryCenter.emit(
                .storage,
                title: "Chunks prepared",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ],
                duration: chunkingTime
            )

            // Step 4: Store chunks in vector database (per active container)
            let db = await dbForActiveContainer()
            try await db.storeBatch(chunks: documentChunks)
            // Invalidate visualization cache for this container after data change
            ProjectionCache.shared.invalidate(forContainer: activeContainerId)
            TelemetryCenter.emit(
                .storage,
                title: "Chunks stored",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ]
            )

            // Calculate total pipeline time
            let totalTime = Date().timeIntervalSince(pipelineStartTime)

            // Calculate chunk statistics
            let chunkSizes = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkSizes.isEmpty ? 0 : chunkSizes.reduce(0, +) / chunkSizes.count
            let minChunkSize = chunkSizes.min() ?? 0
            let maxChunkSize = chunkSizes.max() ?? 0

            // Get file size
            let fileSize =
                try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
            let fileSizeMB: Double
            let fileSizeStr: String
            if let size = fileSize {
                fileSizeMB = Double(size) / (1024.0 * 1024.0)
                if size < 1024 {
                    fileSizeStr = "\(size) B"
                } else if size < 1024 * 1024 {
                    fileSizeStr = String(format: "%.2f KB", Double(size) / 1024.0)
                } else {
                    fileSizeStr = String(format: "%.2f MB", fileSizeMB)
                }
            } else {
                fileSizeMB = 0
                fileSizeStr = "Unknown"
            }

            // Update document with embedding time and complete metadata
            var updatedDocument = document
            if let existingMetadata = document.processingMetadata {
                // Create new metadata with embedding time added
                let completeMetadata = ProcessingMetadata(
                    fileSizeMB: fileSizeMB,
                    totalCharacters: existingMetadata.totalCharacters,
                    totalWords: existingMetadata.totalWords,
                    extractionTimeSeconds: existingMetadata.extractionTimeSeconds,
                    chunkingTimeSeconds: existingMetadata.chunkingTimeSeconds,
                    embeddingTimeSeconds: embeddingTime,
                    totalProcessingTimeSeconds: totalTime,
                    pagesProcessed: existingMetadata.pagesProcessed,
                    ocrPagesCount: existingMetadata.ocrPagesCount,
                    chunkStats: existingMetadata.chunkStats
                )

                updatedDocument = Document(
                    id: document.id,
                    filename: document.filename,
                    fileURL: document.fileURL,
                    contentType: document.contentType,
                    addedAt: document.addedAt,
                    totalChunks: document.totalChunks,
                    processingMetadata: completeMetadata
                )
            }

            // Ensure document is associated with the active container
            let docWithContainer = Document(
                id: updatedDocument.id,
                filename: updatedDocument.filename,
                fileURL: updatedDocument.fileURL,
                contentType: updatedDocument.contentType,
                addedAt: updatedDocument.addedAt,
                totalChunks: updatedDocument.totalChunks,
                processingMetadata: updatedDocument.processingMetadata,
                containerId: activeContainerId
            )
            updatedDocument = docWithContainer

            // Create processing summary with embedding provider info
            let activeProviderId = containerService.activeContainer?.embeddingProviderId ?? "coreml_sentence_embedding"
            let summary = ProcessingSummary(
                filename: filename,
                fileSize: fileSizeStr,
                documentType: document.contentType,
                pageCount: document.processingMetadata?.pagesProcessed,
                ocrPagesUsed: document.processingMetadata?.ocrPagesCount,
                totalChars: totalChars,
                totalWords: totalWords,
                chunksCreated: processedChunks.count,
                extractionTime: extractionTime,
                chunkingTime: chunkingTime,
                embeddingTime: embeddingTime,
                totalTime: totalTime,
                chunkStats: ProcessingSummary.ChunkStatistics(
                    avgChars: avgChunkSize,
                    minChars: minChunkSize,
                    maxChars: maxChunkSize
                ),
                embeddingProviderId: activeProviderId
            )

            // Step 5: Update state
            await MainActor.run {
                documents.append(updatedDocument)
                totalChunksStored += documentChunks.count
                if !suppressProcessingSummary {
                    lastProcessingSummary = summary
                }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }
            }

            TelemetryCenter.emit(
                .ingestion,
                title: "Document indexed",
                metadata: [
                    "file": filename,
                    "chunks": "\(documentChunks.count)",
                    "size": fileSizeStr,
                ],
                duration: totalTime
            )

            // Save documents metadata to disk
            saveDocumentsToDisk()

            // Small success flash
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .complete,
                    detail: "Complete",
                    progress: 1.0
                )
                if manageProcessingState { isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }

                self.kickPendingReembedIfNeeded()
            }

            refreshIntelligence(for: activeContainerId, force: true)

            if context.allowsSelfTuningScheduling, !pendingSelfTuneReasons.isEmpty {
                scheduleSelfTuningRebuild(for: activeContainerId, reasons: pendingSelfTuneReasons)
            }

        } catch {
            // Reset processing state on error
            await MainActor.run {
                if manageProcessingState { isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }
                lastError = error.localizedDescription
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .failed,
                    detail: "Failed",
                    errorMessage: error.localizedDescription
                )
                self.kickPendingReembedIfNeeded()
            }

            // Re-throw with context
            Log.error(" [RAGService] Failed to add document: \(error.localizedDescription)")
            TelemetryCenter.emit(
                .ingestion,
                severity: .error,
                title: "Ingestion failed",
                metadata: [
                    "file": filename,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }
    }

    /// Remove a document from the knowledge base
    func removeDocument(_ document: Document) async throws {
        let db = await dbForActiveContainer()
        try await db.deleteChunks(forDocument: document.id)

        // Invalidate visualization cache for active container after removal
        let activeId = await MainActor.run { self.containerService.activeContainerId }
        ProjectionCache.shared.invalidate(forContainer: activeId)

        await MainActor.run {
            documents.removeAll { $0.id == document.id }
            totalChunksStored -= document.totalChunks
        }

        saveDocumentsToDisk()

        Log.info(" Removed document: \(document.filename)")

        refreshIntelligence(for: activeId, force: true)
    }

    /// Clear all documents from the knowledge base
    func clearAllDocuments() async throws {
        let db = await dbForActiveContainer()
        try await db.clear()

        let activeId = await MainActor.run { self.containerService.activeContainerId }
        // Invalidate visualization cache for the cleared container
        ProjectionCache.shared.invalidate(forContainer: activeId)

        await MainActor.run {
            documents.removeAll { $0.containerId == activeId }
            totalChunksStored = documents.reduce(0) { $0 + $1.totalChunks }
        }

        saveDocumentsToDisk()

        Log.info(" Cleared all documents from knowledge base")

        refreshIntelligence(for: activeId, force: true)
    }

    /// Rebuild embeddings for every document in the specified container
    func reembedDocuments(
        in containerId: UUID? = nil,
        progressHandler: (@MainActor (ReembedProgress) -> Void)? = nil
    ) async throws {
        let targetContainerId: UUID
        if let containerId {
            targetContainerId = containerId
        } else {
            targetContainerId = await MainActor.run { self.containerService.activeContainerId }
        }
        let documentsToRebuild = await MainActor.run {
            self.documents.filter { document in
                if let docContainer = document.containerId {
                    return docContainer == targetContainerId
                } else if let fallbackId = self.containerService.containers.first?.id {
                    return fallbackId == targetContainerId
                }
                return false
            }
        }

        guard !documentsToRebuild.isEmpty else {
            await MainActor.run {
                progressHandler?(ReembedProgress(completed: 0, total: 0, currentFilename: ""))
            }
            return
        }

        let originalContainerId = await MainActor.run { self.containerService.activeContainerId }
        if originalContainerId != targetContainerId {
            await MainActor.run {
                self.containerService.setActive(targetContainerId)
            }
        }

        TelemetryCenter.emit(
            .ingestion,
            title: "Re-embedding requested",
            metadata: [
                "container": targetContainerId.uuidString,
                "documents": "\(documentsToRebuild.count)",
            ]
        )

        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingStatus = ""
                self.isProcessing = false
                if originalContainerId != targetContainerId {
                    self.containerService.setActive(originalContainerId)
                }
            }
        }

        for (index, document) in documentsToRebuild.enumerated() {
            if Task.isCancelled { break }

            await MainActor.run {
                self.processingStatus = "Re-embedding \(document.filename) (\(index + 1)/\(documentsToRebuild.count))"
                self.isProcessing = true
                progressHandler?(ReembedProgress(
                    completed: index,
                    total: documentsToRebuild.count,
                    currentFilename: document.filename
                ))
            }

            try await removeDocument(document)
            try await addDocument(at: document.fileURL, context: .autoRebuild)

            await MainActor.run {
                // Keep overlay visible between documents
                self.isProcessing = true
            }
        }

        await MainActor.run {
            progressHandler?(ReembedProgress(
                completed: documentsToRebuild.count,
                total: documentsToRebuild.count,
                currentFilename: ""
            ))
        }
    }

    // MARK: - Self-Tuning

    private func chunkingOverride(for container: KnowledgeContainer?) -> DocumentProcessor.ChunkingOverride? {
        guard let directive = container?.chunkingDirective else { return nil }
        return DocumentProcessor.ChunkingOverride(
            targetWordWindow: directive.targetWordWindow,
            overlapWords: directive.overlapWords
        )
    }

    private func resolveAutoAdjustments(
        for container: KnowledgeContainer,
        report: LibraryIntelligenceCenter.IntelligenceReport
    ) -> (KnowledgeContainer, [String]) {
        var updated = container
        var reasons: [String] = []

        if let embeddingAction = evaluateEmbeddingShift(container: container, plan: report.embedding) {
            updated.embeddingProviderId = embeddingAction.providerId
            updated.embeddingDim = embeddingAction.dimension
            reasons.append(embeddingAction.reason)
        }

        if let chunkAction = evaluateChunkShift(current: container.chunkingDirective, plan: report.chunking) {
            updated.chunkingDirective = chunkAction.directive
            reasons.append(chunkAction.reason)
        }

        if !reasons.isEmpty {
            updated.lastSelfTuneAt = Date()
        }

        return (updated, reasons)
    }

    private func evaluateEmbeddingShift(
        container: KnowledgeContainer,
        plan: LibraryIntelligenceCenter.EmbeddingPlan
    ) -> EmbeddingAutoAction? {
        // Don't override if user has very recently manually configured
        // (within last 60 seconds indicates active user preference)
        if let lastTune = container.lastSelfTuneAt,
           Date().timeIntervalSince(lastTune) < 60
        {
            Log.debug("[AutoAdapt] Skipping embedding shift - user recently configured settings", category: .ingestion)
            return nil
        }

        let providerChanged = plan.providerId != container.embeddingProviderId
        let dimensionDelta = abs(plan.dimension - container.embeddingDim)
        guard providerChanged || dimensionDelta >= 64 else { return nil }

        // Require higher confidence to override user settings
        let confident = plan.confidence >= 0.50
        guard confident else {
            Log.debug("[AutoAdapt] Skipping embedding shift - confidence \(plan.confidence) below threshold", category: .ingestion)
            return nil
        }

        let friendlyProvider: String
        switch plan.providerId {
        case "coreml_sentence_embedding":
            friendlyProvider = "Core ML Sentence"
        case "apple_fm_embed":
            friendlyProvider = "Apple FM"
        case "nl_contextual_embedding":
            friendlyProvider = "Contextual Embeddings"
        default:
            friendlyProvider = "Natural Language"
        }

        let reason = "Embeddings shifted to \(friendlyProvider) • \(plan.dimension)D (confidence \(String(format: "%.0f%%", plan.confidence * 100)))"
        return EmbeddingAutoAction(providerId: plan.providerId, dimension: plan.dimension, reason: reason)
    }

    private func evaluateChunkShift(
        current: ChunkingDirective?,
        plan: LibraryIntelligenceCenter.ChunkingPlan
    ) -> ChunkAutoAction? {
        let currentStrategy = current?.strategy ?? LibraryIntelligenceCenter.ChunkingPlan.Strategy.balanced.rawValue
        let currentWindow = current?.targetWordWindow ?? ChunkingDefaults.targetWindow
        let currentOverlap = current?.overlapWords ?? ChunkingDefaults.overlap

        let strategyChanged = currentStrategy != plan.strategy.rawValue
        let windowShift = abs(currentWindow - plan.targetWordWindow) >= 40
        let overlapShift = abs(currentOverlap - plan.overlapWords) >= 15

        guard strategyChanged || windowShift || overlapShift else { return nil }

        var reasonBits: [String] = []
        if strategyChanged {
            reasonBits.append("Chunk strategy → \(plan.strategy.rawValue.capitalized)")
        }
        if windowShift {
            reasonBits.append("Window \(currentWindow)→\(plan.targetWordWindow)")
        }
        if overlapShift {
            reasonBits.append("Overlap \(currentOverlap)→\(plan.overlapWords)")
        }

        let directive = ChunkingDirective(
            source: .auto,
            strategy: plan.strategy.rawValue,
            targetWordWindow: plan.targetWordWindow,
            overlapWords: plan.overlapWords,
            rationale: plan.rationales
        )

        return ChunkAutoAction(directive: directive, reason: reasonBits.joined(separator: " • "))
    }

    private static let thinkingEventLimit = 24

    private func scheduleSelfTuningRebuild(for containerId: UUID, reasons: [String]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let canStart = await self.beginSelfTuning(for: containerId)
            guard canStart else { return }
            TelemetryCenter.emit(
                .ingestion,
                title: "Self-tuning rebuild scheduled",
                metadata: [
                    "container": containerId.uuidString,
                    "reasons": reasons.joined(separator: " | "),
                ]
            )
            do {
                try await self.reembedDocuments(in: containerId)
                TelemetryCenter.emit(
                    .ingestion,
                    title: "Self-tuning rebuild complete",
                    metadata: ["container": containerId.uuidString]
                )
            } catch {
                if Task.isCancelled { return }
                TelemetryCenter.emit(
                    .ingestion,
                    severity: .error,
                    title: "Self-tuning rebuild failed",
                    metadata: [
                        "container": containerId.uuidString,
                        "error": error.localizedDescription,
                    ]
                )
            }
            await self.finishSelfTuning(for: containerId)
        }
    }

    // MARK: - Thinking Timeline Helpers

    @MainActor
    private func resetThinkingTimeline() {
        thinkingEvents.removeAll(keepingCapacity: false)
    }

    private func emitThinkingEvent(
        _ kind: ThinkingEvent.Kind,
        title: String,
        detail: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.thinkingEvents.count >= Self.thinkingEventLimit {
                let overflow = self.thinkingEvents.count - Self.thinkingEventLimit + 1
                if overflow > 0 {
                    self.thinkingEvents.removeFirst(overflow)
                }
            }
            self.thinkingEvents.append(ThinkingEvent(kind: kind, title: title, detail: detail))
        }
    }

    @MainActor
    private func beginSelfTuning(for containerId: UUID) -> Bool {
        if selfTuningInFlight.contains(containerId) {
            return false
        }
        selfTuningInFlight.insert(containerId)
        return true
    }

    @MainActor
    private func finishSelfTuning(for containerId: UUID) {
        selfTuningInFlight.remove(containerId)
    }

    private func handleSelfTuning(
        for containerId: UUID,
        report: LibraryIntelligenceCenter.IntelligenceReport,
        triggerAllowsScheduling: Bool
    ) async {
        // IMPORTANT:
        // Self-tuning rebuilds call `reembedDocuments()`, which removes and re-adds documents.
        // `addDocument()` triggers `refreshIntelligence(force: true)`, which can re-enter this
        // method. Without a guard, we can accidentally schedule a *new* rebuild while the
        // current rebuild is still running, creating an infinite “re-upload/re-embed” loop.
        let isSelfTuningInFlight = await MainActor.run { self.selfTuningInFlight.contains(containerId) }
        if isSelfTuningInFlight {
            return
        }

        guard let container = await MainActor.run(
            resultType: KnowledgeContainer?.self,
            body: {
                self.containerService.containers.first { $0.id == containerId }
            }
        ) else { return }
        guard container.autoAdaptDimension else { return }

        let (updated, reasons) = resolveAutoAdjustments(for: container, report: report)
        if updated != container {
            await MainActor.run {
                self.containerService.updateContainer(updated)
            }
        }

        if triggerAllowsScheduling, !reasons.isEmpty {
            scheduleSelfTuningRebuild(for: containerId, reasons: reasons)
        }
    }

    // MARK: - RAG Query Pipeline

    /// Execute a RAG query: expand query → embed → hybrid search → re-rank → generate response
    func query(
        _ question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        streamHandler: LLMStreamHandler? = nil
    ) async throws -> RAGResponse {
        resetThinkingTimeline()
        return try await LLMStreamingContext.$handler.withValue(streamHandler) {
            try await self.queryInternal(
                question, topK: topK, config: config, containerId: containerId
            )
        }
    }

    private func queryInternal(
        _ question: String, topK: Int, config: InferenceConfig?, containerId: UUID?
    ) async throws -> RAGResponse {
        var inferenceConfig = config ?? InferenceConfig()
        let networkAvailable = NetworkMonitor.shared.isConnected
        let reliabilityModeEnabled: Bool = await MainActor.run {
            settingsStore?.reliabilityModeEnabled ?? true
        }
        if reliabilityModeEnabled {
            Log.info("[RAG] Reliability-first fallbacks enabled", category: .pipeline)
        }
        let isAppleFMService = _llmService is AppleFoundationLLMService
        let pccSuppressed = await MainActor.run { self.isPCCSuppressed() }
        let initialCloudConsentState: CloudConsentState = await MainActor.run {
            cloudConsent[.applePCC] ?? .notDetermined
        }

        let initialCloudConsentAllowed = initialCloudConsentState == .allowed
        let cloudEligible =
            isAppleFMService
                && networkAvailable
                && inferenceConfig.allowPrivateCloudCompute
                && inferenceConfig.executionContext != .onDeviceOnly
                && !pccSuppressed
        let initialWantsCloudContext = cloudEligible && initialCloudConsentAllowed

        // EXECUTION CONTEXT SELECTION:
        // Prefer PCC when available, otherwise fall back to on-device.
        #if targetEnvironment(simulator)
            if isAppleFMService {
                inferenceConfig.executionContext = .onDeviceOnly
                inferenceConfig.allowPrivateCloudCompute = false
                Log.info("[RAG] Simulator → onDeviceOnly (PCC unavailable)", category: .pipeline)
            }
        #else
            if isAppleFMService {
                if !networkAvailable {
                    inferenceConfig.executionContext = .onDeviceOnly
                    inferenceConfig.allowPrivateCloudCompute = false
                    Log.info("[RAG] Offline → onDeviceOnly (4096 tokens)", category: .pipeline)
                } else if pccSuppressed {
                    inferenceConfig.executionContext = .onDeviceOnly
                    inferenceConfig.allowPrivateCloudCompute = false
                    Log.info("[RAG] PCC suppressed → onDeviceOnly (context cooldown)", category: .pipeline)
                } else if !inferenceConfig.allowPrivateCloudCompute {
                    inferenceConfig.executionContext = .onDeviceOnly
                    Log.info("[RAG] PCC disabled → onDeviceOnly", category: .pipeline)
                } else {
                    if inferenceConfig.executionContext == .automatic {
                        inferenceConfig.executionContext = .preferCloud
                        Log.info("[RAG] Network available → preferCloud (PCC capable)", category: .pipeline)
                    } else if inferenceConfig.executionContext == .cloudOnly, !initialCloudConsentAllowed {
                        inferenceConfig.executionContext = .preferCloud
                        Log.info("[RAG] PCC consent pending → preferCloud (allow fallback)", category: .pipeline)
                    }
                }
            }
        #endif

        // Get quality mode from settings (affects retrieval parameters)
        let qualityMode: RAGQualityMode = await MainActor.run {
            settingsStore?.ragQualityMode ?? .balanced
        }

        let developerTuningEnabled: Bool = await MainActor.run {
            settingsStore?.developerRAGTuningEnabled ?? false
        }

        let allowUngroundedFallback = reliabilityModeEnabled || developerTuningEnabled

        let rawRetrievalConfig: RetrievalConfig = await MainActor.run {
            if let id = containerId,
               let container = self.containerService.containers.first(where: { $0.id == id })
            {
                return container.retrievalConfig
            } else {
                return self.containerService.activeContainer?.retrievalConfig ?? .default
            }
        }
        let retrievalConfig =
            rawRetrievalConfig == .highAccuracy ? .default : rawRetrievalConfig

        let embeddingContext = await resolveEmbeddingContext(preferredContainerId: containerId)
        let embeddingProviderId = embeddingContext.providerId
        let queryEmbeddingService = embeddingContext.service
        let selectedId = embeddingContext.containerId
        let selectedName = embeddingContext.containerName
        let selectedDim = embeddingContext.dimension
        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == selectedId }
        }

        if let container = selectedContainer, !container.autoAdaptDimension {
            var updated = container
            updated.autoAdaptDimension = true
            await MainActor.run {
                self.containerService.updateContainer(updated)
            }
            refreshIntelligence(for: selectedId, force: true)
        }
        let vdb = await dbFor(selectedId)

        // Establish query-scoped container context for downstream tool calls and listings
        await MainActor.run {
            self.currentQueryContainerId = selectedId
            self.transientConsentGrants.removeAll()
        }
        // Optional DB warmup to ensure the vector store is loaded (prevents first-touch latency)
        let _ = try? await vdb.count()
        // Ensure cleanup even if an error is thrown later in the pipeline
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }

        // Adjust topK based on quality mode (quality mode is the default floor)
        let requestedTopK = max(topK, qualityMode.initialTopK)
        let baseTopK = requestedTopK

        let queryWords = question.split(separator: " ").count
        let isTrivial = isTrivialQuery(question)
        let applyTrivialTopKCap = isTrivial && !initialWantsCloudContext
        let effectiveTopK = initialWantsCloudContext
            ? max(baseTopK, 25) // "Full blown" mode: 25 chunks to balance recall vs overflow risk
            : max(1, applyTrivialTopKCap ? min(baseTopK, 8) : baseTopK)
        if isTrivial {
            let detail = applyTrivialTopKCap
                ? "fast topK cap (\(effectiveTopK))"
                : "cloud context available - keeping full topK"
            Log.info("[RAG] Trivial query detected - \(detail)", category: .retrieval)
        }
        // Fetch current stored chunk count from vector database (fallback to cached total)
        let totalStored = (try? await vdb.count()) ?? totalChunksStored

        var auditCandidatesCount = 0
        var auditRerankedCount = 0
        var auditFilteredCount = 0
        var auditDroppedCount = 0
        var auditMMRSelectedCount = 0
        var auditUniqueDocCount = 0
        var auditLenient = false
        var auditDynamicMin: Float = retrievalConfig.minSimilarity
        var auditTopSim: Float = 0
        var auditSecondSim: Float = 0
        var auditAvgTop5: Float = 0
        var auditAcceptanceOverride = false
        var usedRetrievalCascade = false
        var retryCandidates: [RetrievedChunk] = []

        Log.box(
            "ENHANCED RAG QUERY PIPELINE",
            level: .info,
            category: .pipeline,
            content: [
                "📝 Query: \(question)",
                "🎯 Retrieving top \(effectiveTopK) chunks from \(totalStored) total",
                "🧬 Embeddings: \(embeddingProviderId) • \(selectedDim)D",
                "⚙️ Quality Mode: \(qualityMode.displayName)",
            ]
        )

        emitThinkingEvent(
            .planning,
            title: "Scoping query",
            detail: "Top \(effectiveTopK) • \(selectedName) • \(qualityMode.displayName) mode"
        )

        TelemetryCenter.emit(
            .system,
            title: "Query received",
            metadata: [
                "question": String(question.prefix(80)),
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "qualityMode": qualityMode.rawValue,
                "words": "\(queryWords)",
                "characters": "\(question.count)",
                "topK": "\(effectiveTopK)",
                "minSimilarity": String(format: "%.2f", retrievalConfig.minSimilarity),
                "embeddingProvider": embeddingProviderId,
                "embeddingDim": "\(selectedDim)",
            ]
        )

        var ragQuery: RAGQuery?
        var recoveryRetrievedChunks: [RetrievedChunk] = []
        var recoveryRetrievalTime: TimeInterval = 0
        do {
            // Clear any previous errors
            await MainActor.run {
                lastError = nil
            }

            // Edge case: Empty query
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.error("❌ [RAGService] Empty query string", category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    severity: .error,
                    title: "Query rejected",
                    metadata: ["reason": "Empty input"]
                )
                throw RAGServiceError.emptyQuery
            }

            let pipelineStartTime = Date()
            let ragQueryValue = RAGQuery(query: question, topK: effectiveTopK)
            ragQuery = ragQueryValue

            // Check if we have documents for RAG or just direct LLM chat (use live DB count)
            let hasDocuments = totalStored > 0

            if hasDocuments {
                // ENHANCED RAG pipeline with query expansion + hybrid search + re-ranking

                // Step 1: Query Expansion
                Log.section("Step 1: Query Expansion", level: .info, category: .pipeline)
                let expansionStartTime = Date()
                let queryEnhancer = QueryEnhancementService()
                let expandedQueries = queryEnhancer.expandQuery(question)
                let expansionTime = Date().timeIntervalSince(expansionStartTime)
                Log.info(
                    "✓ Expanded to \(expandedQueries.count) query variations in \(String(format: "%.0f", expansionTime * 1000))ms",
                    category: .pipeline
                )
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Query expanded",
                    metadata: [
                        "variants": "\(expandedQueries.count)",
                    ],
                    duration: expansionTime
                )

                if let firstVariant = expandedQueries.first {
                    let preview = expandedQueries.dropFirst().first
                        .map { " • \($0)" } ?? ""
                    emitThinkingEvent(
                        .planning,
                        title: "Expanded query",
                        detail: firstVariant + preview
                    )
                }

                // Step 2: Embed the user's query (primary query only)
                Log.section("Step 2: Query Embedding", level: .info, category: .pipeline)
                let embeddingStartTime = Date()
                let queryEmbedding = try await queryEmbeddingService.generateEmbedding(for: question)
                let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

                let embeddingMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
                Log.info(
                    "✓ Generated \(queryEmbedding.count)-dimensional embedding",
                    category: .embedding
                )
                Log.debug(
                    "  Vector magnitude: \(String(format: "%.4f", embeddingMagnitude))",
                    category: .embedding
                )
                Log.debug(
                    "  Time: \(String(format: "%.0f", embeddingTime * 1000))ms",
                    category: .performance
                )
                TelemetryCenter.emit(
                    .embedding,
                    title: "Query embedding",
                    metadata: [
                        "dimensions": "\(queryEmbedding.count)",
                        "provider": embeddingProviderId,
                    ],
                    duration: embeddingTime
                )

                // Show provider in thinking timeline (contextual = high accuracy badge)
                let providerLabel = embeddingProviderId == "nl_contextual_embedding" ? "⚡ Contextual" : embeddingProviderId
                emitThinkingEvent(
                    .embedding,
                    title: "Embedding ready",
                    detail: "\(providerLabel) • \(queryEmbedding.count)D in \(String(format: "%.0f", embeddingTime * 1000)) ms"
                )

                // Warn if embedding dimension doesn't match the selected library's index dimension
                if queryEmbedding.count != selectedDim {
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Embedding dimension mismatch",
                        metadata: [
                            "expected": "\(selectedDim)",
                            "got": "\(queryEmbedding.count)",
                            "container": selectedName,
                            "containerId": selectedId.uuidString,
                        ]
                    )
                }

                // Step 3: Hybrid Search (vector + BM25 keyword search with RRF fusion)
                Log.section(
                    "Step 3: Hybrid Search (Vector + BM25)", level: .info, category: .pipeline
                )
                let retrievalStartTime = Date()
                let hybridSearch = HybridSearchService(
                    vectorDatabase: vdb,
                    vectorWeight: retrievalConfig.vectorWeight,
                    keywordWeight: retrievalConfig.lexicalWeight
                )
                // Use expanded queries for keyword search (original for vector)
                let retrievedChunks = try await hybridSearch.search(
                    query: expandedQueries.joined(separator: " "), // Combine expansions
                    embedding: queryEmbedding,
                    topK: effectiveTopK * 3 // Retrieve 3x for better coverage on large docs
                )

                // Measure retrieval time before any MainActor work
                var retrievalTime = Date().timeIntervalSince(retrievalStartTime)
                recoveryRetrievalTime = retrievalTime

                // Edge case: No relevant chunks found
                if retrievedChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] No chunks retrieved (database may be empty)",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        severity: .warning,
                        title: "No chunks retrieved",
                        metadata: [
                            "question": String(question.prefix(60)),
                        ],
                        duration: retrievalTime
                    )
                    emitThinkingEvent(
                        .warning,
                        title: "Insufficient evidence",
                        detail: "No relevant chunks found"
                    )
                    if allowUngroundedFallback {
                        // Fallback to direct LLM chat mode
                        let response = try await generateDirectChatResponse(
                            question: question,
                            ragQuery: ragQueryValue,
                            inferenceConfig: inferenceConfig,
                            pipelineStartTime: pipelineStartTime,
                            retrievalTime: retrievalTime,
                            fallbackNote:
                            "No relevant document context found; replied without RAG context."
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: [],
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "I couldn't find relevant sources in your library for that question.",
                        gatingDecision: "no_sources"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                // Add source information for citations with a safe MainActor snapshot
                let docsSnapshot = await snapshotDocuments()
                let chunksWithSources: [RetrievedChunk] = retrievedChunks.map { retrieved in
                    let docName =
                        docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                            ?? "Unknown"
                    let pageNum = retrieved.chunk.metadata.pageNumber
                    return RetrievedChunk(
                        chunk: retrieved.chunk,
                        similarityScore: retrieved.similarityScore,
                        rank: retrieved.rank,
                        sourceDocument: docName,
                        pageNumber: pageNum
                    )
                }
                auditCandidatesCount = chunksWithSources.count
                recoveryRetrievedChunks = chunksWithSources

                let chunkWordCounts = chunksWithSources.map { wordCount(of: $0.chunk.content) }
                let totalChunkWords = chunkWordCounts.reduce(0, +)
                let topContextWords = chunkWordCounts.prefix(effectiveTopK).reduce(0, +)
                let averageChunkWords =
                    chunkWordCounts.isEmpty
                        ? 0.0
                        : Double(totalChunkWords) / Double(chunkWordCounts.count)

                TelemetryCenter.emit(
                    .retrieval,
                    title: "Hybrid retrieval",
                    metadata: [
                        "candidates": "\(chunksWithSources.count)",
                        "topK": "\(effectiveTopK * 2)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                        "totalWords": "\(totalChunkWords)",
                        "topWords": "\(topContextWords)",
                        "avgWords": String(format: "%.1f", averageChunkWords),
                    ],
                    duration: retrievalTime
                )

                let sourcePreview = chunksWithSources.prefix(3)
                    .map { $0.sourceDocument }
                    .filter { !$0.isEmpty }
                let retrievalDetail: String
                if sourcePreview.isEmpty {
                    retrievalDetail = "\(chunksWithSources.count) candidates in \(String(format: "%.0f", retrievalTime * 1000)) ms"
                } else {
                    retrievalDetail = "\(chunksWithSources.count) candidates • \(sourcePreview.joined(separator: ", "))"
                }
                emitThinkingEvent(.retrieval, title: "Hybrid retrieval", detail: retrievalDetail)

                Log.info(
                    "✓ Retrieved \(chunksWithSources.count) chunks with hybrid fusion",
                    category: .retrieval
                )
                Log.debug(
                    "  Time: \(String(format: "%.0f", retrievalTime * 1000))ms",
                    category: .performance
                )
                if let topChunk = chunksWithSources.first {
                    Log.debug(
                        "  Top semantic score: \(String(format: "%.4f", topChunk.similarityScore))",
                        category: .retrieval
                    )
                    if !topChunk.sourceDocument.isEmpty {
                        Log.debug(
                            "  Source: \(topChunk.sourceDocument)\(topChunk.pageNumber.map { " (p. \($0))" } ?? "")",
                            category: .retrieval
                        )
                    }
                    // BM25 and fusion scores would be displayed here once metadata storage is enhanced
                }

                // Step 4: Re-rank results with multiple signals
                Log.section("Step 4: Multi-Signal Re-ranking", level: .info, category: .pipeline)
                let engine = RAGEngine()
                let rerankStartTime = Date()
                var rerankedChunks = await engine.rerank(
                    chunks: chunksWithSources,
                    query: question,
                    topK: effectiveTopK * 3 // Get more candidates for MMR diversification (clamped)
                )
                auditRerankedCount = rerankedChunks.count
                var rerankTime = Date().timeIntervalSince(rerankStartTime)
                Log.info(
                    "✓ Re-ranked to top \(rerankedChunks.count) in \(String(format: "%.0f", rerankTime * 1000))ms",
                    category: .retrieval
                )
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Re-ranking complete",
                    metadata: [
                        "candidates": "\(rerankedChunks.count)",
                    ],
                    duration: rerankTime
                )

                let cascadeTopSim = rerankedChunks.first?.similarityScore ?? 0
                let cascadeAvgTop5: Float = {
                    let sims = rerankedChunks.prefix(5).map { $0.similarityScore }
                    guard !sims.isEmpty else { return 0 }
                    return sims.reduce(0, +) / Float(sims.count)
                }()
                let cascadeThreshold = max(0.32, min(0.45, retrievalConfig.minSimilarity - 0.05))
                let cascadeNeedsMore = rerankedChunks.count < max(4, effectiveTopK / 2)
                let isShortQueryForCascade = queryWords <= 6
                let shouldCascade = !usedRetrievalCascade
                    && !isTrivial
                    && (cascadeTopSim < cascadeThreshold || cascadeNeedsMore || cascadeAvgTop5 < cascadeThreshold)

                if shouldCascade {
                    let baseCandidateCount = rerankedChunks.count
                    let cascadeStartTime = Date()
                    let lexicalBoost: Float = isShortQueryForCascade ? 0.2 : 0.12
                    var cascadeLexical = min(0.55, retrievalConfig.lexicalWeight + lexicalBoost)
                    var cascadeVector = max(0.45, 1.0 - cascadeLexical)
                    let weightTotal = cascadeLexical + cascadeVector
                    cascadeLexical = cascadeLexical / weightTotal
                    cascadeVector = cascadeVector / weightTotal

                    let cascadeQuery = (expandedQueries + [question]).joined(separator: " ")
                    let cascadeTopK = min(max(effectiveTopK * 4, effectiveTopK * 3), max(1, totalStored))
                    let cascadeHybrid = HybridSearchService(
                        vectorDatabase: vdb,
                        vectorWeight: cascadeVector,
                        keywordWeight: cascadeLexical
                    )
                    let cascadeRetrieved = try await cascadeHybrid.search(
                        query: cascadeQuery,
                        embedding: queryEmbedding,
                        topK: cascadeTopK
                    )

                    let cascadeTime = Date().timeIntervalSince(cascadeStartTime)
                    if !cascadeRetrieved.isEmpty {
                        let cascadeChunksWithSources: [RetrievedChunk] = cascadeRetrieved.map { retrieved in
                            let docName =
                                docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                                    ?? "Unknown"
                            let pageNum = retrieved.chunk.metadata.pageNumber
                            return RetrievedChunk(
                                chunk: retrieved.chunk,
                                similarityScore: retrieved.similarityScore,
                                rank: retrieved.rank,
                                sourceDocument: docName,
                                pageNumber: pageNum
                            )
                        }

                        let mergedCandidates = mergeUniqueChunks(rerankedChunks, cascadeChunksWithSources)
                        if mergedCandidates.count > rerankedChunks.count {
                            let cascadeRerankStart = Date()
                            rerankedChunks = await engine.rerank(
                                chunks: mergedCandidates,
                                query: question,
                                topK: effectiveTopK * 3
                            )
                            let cascadeRerankTime = Date().timeIntervalSince(cascadeRerankStart)
                            usedRetrievalCascade = true
                            auditCandidatesCount = mergedCandidates.count
                            auditRerankedCount = rerankedChunks.count
                            retrievalTime += cascadeTime
                            rerankTime += cascadeRerankTime
                            recoveryRetrievalTime = retrievalTime

                            let addedCount = max(0, mergedCandidates.count - baseCandidateCount)
                            Log.info(
                                "🔁 Retrieval cascade added \(addedCount) candidates (lexical \(String(format: "%.2f", cascadeLexical)))",
                                category: .retrieval
                            )
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Retrieval cascade",
                                metadata: [
                                    "candidates": "\(mergedCandidates.count)",
                                    "lexicalWeight": String(format: "%.2f", cascadeLexical),
                                    "vectorWeight": String(format: "%.2f", cascadeVector),
                                ],
                                duration: cascadeTime
                            )
                            emitThinkingEvent(
                                .retrieval,
                                title: "Retrieval cascade",
                                detail: "\(mergedCandidates.count) candidates • lex \(String(format: "%.2f", cascadeLexical))"
                            )
                        }
                    }
                }

                if rerankedChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] Re-ranking yielded no candidates",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .warning,
                        title: "Re-ranking exhausted",
                        detail: "No viable candidates"
                    )
                    if allowUngroundedFallback {
                        let response = try await generateDirectChatResponse(
                            question: question,
                            ragQuery: ragQueryValue,
                            inferenceConfig: inferenceConfig,
                            pipelineStartTime: pipelineStartTime,
                            retrievalTime: retrievalTime,
                            fallbackNote: "No re-ranked candidates; replied without RAG context."
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: [],
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "I couldn't identify reliable sources after re-ranking.",
                        gatingDecision: "rerank_empty"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                // Step 4.3: Filter low-confidence chunks using container's retrieval config
                // Adaptive gating: consider "lenient" mode, quality mode, and trivial/short queries
                let lenient = UserDefaults.standard.bool(forKey: "lenientRetrievalMode")
                auditLenient = lenient

                // Relative-score metrics (computed on reranked results)
                let topSim: Float = rerankedChunks.first?.similarityScore ?? 0
                let secondSim: Float = rerankedChunks.dropFirst().first?.similarityScore ?? 0
                let avgTop5: Float = {
                    let sims = rerankedChunks.prefix(5).map { $0.similarityScore }
                    guard !sims.isEmpty else { return 0 }
                    return sims.reduce(0, +) / Float(sims.count)
                }()
                auditTopSim = topSim
                auditSecondSim = secondSim
                auditAvgTop5 = avgTop5

                // Use quality mode's minSimilarity, adjusted for lenient/trivial
                let qualityMinSim = qualityMode.minSimilarity
                let baseMin: Float
                if retrievalConfig == .highAccuracy {
                    baseMin = retrievalConfig.minSimilarity
                } else {
                    switch qualityMode {
                    case .fast:
                        baseMin = min(retrievalConfig.minSimilarity, qualityMinSim)
                    case .balanced:
                        baseMin = retrievalConfig.minSimilarity
                    case .thorough:
                        baseMin = max(retrievalConfig.minSimilarity, qualityMinSim)
                    }
                }

                var dynamicMin: Float = lenient ? min(baseMin, 0.35) : baseMin
                if !lenient, avgTop5 > 0, avgTop5 < baseMin {
                    dynamicMin = max(0.28, avgTop5 - 0.03)
                }

                auditDynamicMin = dynamicMin
                var filteredChunks = await engine.filterBySimilarity(
                    chunks: rerankedChunks,
                    min: dynamicMin
                )

                // Acceptance override if relative signals are strong even with modest absolute scores
                let acceptanceOverride: Bool =
                    (topSim >= 0.50) || (topSim >= 0.38 && (topSim - avgTop5) >= 0.05)
                        || ((topSim - secondSim) >= 0.07)
                auditAcceptanceOverride = acceptanceOverride

                TelemetryCenter.emit(
                    .retrieval,
                    title: "Gating metrics",
                    metadata: [
                        "minSimilarity": String(format: "%.2f", retrievalConfig.minSimilarity),
                        "lenient": lenient ? "true" : "false",
                        "topSim": String(format: "%.3f", topSim),
                        "secondSim": String(format: "%.3f", secondSim),
                        "avgTop5": String(format: "%.3f", avgTop5),
                        "dynamicMin": String(format: "%.2f", dynamicMin),
                        "override": acceptanceOverride ? "true" : "false",
                    ]
                )

                emitThinkingEvent(
                    .gating,
                    title: "Confidence gate (\(retrievalConfig.summary))",
                    detail: "min \(String(format: "%.2f", dynamicMin)) • top \(String(format: "%.2f", topSim))"
                )

                if filteredChunks.count < rerankedChunks.count {
                    let dropped = rerankedChunks.count - filteredChunks.count
                    auditDroppedCount = dropped
                    Log.warning(
                        "   ⚠️  Filtered out \(dropped) low-confidence chunks (< \(String(format: "%.2f", dynamicMin)))",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        severity: .warning,
                        title: "Low-confidence filtered",
                        metadata: ["dropped": "\(dropped)"]
                    )
                }

                // Edge case: No high-confidence chunks
                if filteredChunks.isEmpty {
                    if acceptanceOverride || lenient {
                        // Use top reranked results directly under override/lenient conditions
                        filteredChunks = Array(rerankedChunks.prefix(effectiveTopK * 2))
                        Log.info(
                            "   ✅ Acceptance override applied; proceeding with top reranked results",
                            category: .retrieval
                        )
                        TelemetryCenter.emit(
                            .retrieval,
                            title: "Acceptance override",
                            metadata: [
                                "topSim": String(format: "%.3f", topSim),
                                "secondSim": String(format: "%.3f", secondSim),
                                "avgTop5": String(format: "%.3f", avgTop5),
                            ]
                        )
                    } else if allowUngroundedFallback {
                        // Low-confidence retrieval: proceed with best-available reranked chunks under
                        // explicit fallback allowances.
                        Log.warning(
                            "   ⚠️  No chunks met the confidence threshold; proceeding with best-available context",
                            category: .retrieval
                        )
                        emitThinkingEvent(
                            .fallback,
                            title: "Low-confidence context",
                            detail: "Proceeding with best-available chunks"
                        )
                        TelemetryCenter.emit(
                            .retrieval,
                            severity: .warning,
                            title: "Low-confidence context (proceeding)",
                            metadata: [
                                "threshold": String(format: "%.2f", dynamicMin),
                                "topSim": String(format: "%.3f", topSim),
                            ]
                        )

                        filteredChunks = Array(rerankedChunks.prefix(max(effectiveTopK, 3)))
                    } else {
                        let response = await makeGroundedAbstainResponse(
                            question: question,
                            ragQuery: ragQueryValue,
                            retrievedChunks: rerankedChunks,
                            retrievalTime: retrievalTime,
                            retrievalConfig: retrievalConfig,
                            embeddingProviderId: embeddingProviderId,
                            reason: "I couldn't find high-confidence evidence in your library for this query.",
                            gatingDecision: "low_confidence"
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                }
                auditFilteredCount = filteredChunks.count

                // Step 4.4: Ensure multiple documents are represented before diversification
                let uniqueDocCount = Set(rerankedChunks.map { $0.chunk.documentId }).count
                auditUniqueDocCount = uniqueDocCount
                if uniqueDocCount > 1 {
                    let desiredDocCoverage = min(
                        uniqueDocCount,
                        max(2, min(effectiveTopK, 3))
                    )
                    let maxCandidates = max(effectiveTopK * 2, filteredChunks.count)
                    let (augmented, addedDocs) = ensureDocumentCoverage(
                        candidates: filteredChunks,
                        fallbackPool: rerankedChunks,
                        desiredDocuments: desiredDocCoverage,
                        maxCandidates: maxCandidates
                    )
                    if filteredChunks.count != augmented.count || addedDocs > 0 {
                        if addedDocs > 0 {
                            Log.info(
                                "   🔁 Expanded context to cover \(addedDocs) additional document(s)",
                                category: .retrieval
                            )
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Document coverage boost",
                                metadata: [
                                    "addedDocs": "\(addedDocs)",
                                    "targetDocs": "\(desiredDocCoverage)",
                                    "uniqueDocs": "\(uniqueDocCount)",
                                ]
                            )
                        } else {
                            Log.info(
                                "   🔁 Normalized candidate pool to \(augmented.count) chunks",
                                category: .retrieval
                            )
                        }
                        filteredChunks = augmented
                    }
                } else if filteredChunks.isEmpty {
                    filteredChunks = Array(rerankedChunks.prefix(max(effectiveTopK, 3)))
                }
                retryCandidates = filteredChunks.sorted {
                    $0.similarityScore > $1.similarityScore
                }

                // Step 4.5: Apply MMR for diversity using container's retrieval config
                Log.section("Step 4.5: MMR Diversification", level: .info, category: .pipeline)
                let mmrStartTime = Date()
                let mmrLambda = retrievalConfig.mmrLambda
                let diverseChunks = await engine.applyMMR(
                    candidates: filteredChunks,
                    queryEmbedding: queryEmbedding,
                    topK: effectiveTopK, // Clamped for short queries
                    lambda: mmrLambda
                )
                auditMMRSelectedCount = diverseChunks.count
                let mmrTime = Date().timeIntervalSince(mmrStartTime)
                Log.info(
                    "✓ Selected \(diverseChunks.count) diverse chunks in \(String(format: "%.0f", mmrTime * 1000))ms",
                    category: .retrieval
                )
                Log.debug("  λ=\(String(format: "%.2f", mmrLambda)) (\(Int(mmrLambda * 100))% relevance, \(Int((1 - mmrLambda) * 100))% diversity)", category: .retrieval)
                let contextWordCounts = diverseChunks.map { wordCount(of: $0.chunk.content) }
                let totalContextWords = contextWordCounts.reduce(0, +)
                let maxContextWords = contextWordCounts.max() ?? 0
                let averageContextWords =
                    contextWordCounts.isEmpty
                        ? 0.0
                        : Double(totalContextWords) / Double(contextWordCounts.count)
                TelemetryCenter.emit(
                    .retrieval,
                    title: "MMR diversification",
                    metadata: [
                        "selected": "\(diverseChunks.count)",
                        "lambda": String(format: "%.2f", mmrLambda),
                        "totalWords": "\(totalContextWords)",
                        "avgWords": String(format: "%.1f", averageContextWords),
                        "maxWords": "\(maxContextWords)",
                    ],
                    duration: mmrTime
                )

                emitThinkingEvent(
                    .rerank,
                    title: "Context diversified",
                    detail: "\(diverseChunks.count) chunks • \(uniqueDocCount) docs"
                )

                if diverseChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] MMR returned no candidates",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .warning,
                        title: "MMR exhausted",
                        detail: "No diverse candidates"
                    )
                    if allowUngroundedFallback {
                        let response = try await generateDirectChatResponse(
                            question: question,
                            ragQuery: ragQueryValue,
                            inferenceConfig: inferenceConfig,
                            pipelineStartTime: pipelineStartTime,
                            retrievalTime: retrievalTime,
                            fallbackNote:
                            "No diverse candidates after MMR; replied without RAG context."
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: [],
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "I couldn't build a diverse evidence set to answer reliably.",
                        gatingDecision: "mmr_empty"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                // High Accuracy enforcement: require sufficient high-confidence evidence
                let minConfidentChunks = retrievalConfig.minConfidentChunks
                if retrievalConfig == .highAccuracy, !(lenient || acceptanceOverride) {
                    let supporting = diverseChunks.filter { $0.similarityScore >= retrievalConfig.minSimilarity }
                    if supporting.count < minConfidentChunks {
                        // Build cautious response with citations of top candidates
                        let topSources = diverseChunks.prefix(3).enumerated().map { idx, r in
                            let src = r.sourceDocument.isEmpty ? "Unknown" : r.sourceDocument
                            let page = r.pageNumber.map { " (p.\($0))" } ?? ""
                            return "- [\(idx + 1)] \(src)\(page) — \(String(format: "%.0f%%", r.similarityScore * 100))"
                        }.joined(separator: "\n")
                        let caution = "High Accuracy mode is enabled. Not enough high-confidence evidence across the retrieved sources to answer reliably. Top sources retrieved:\n\(topSources)"

                        emitThinkingEvent(
                            .warning,
                            title: "High accuracy mode paused answer",
                            detail: "\(supporting.count) strong chunk(s) found"
                        )

                        let metadata = ResponseMetadata(
                            timeToFirstToken: nil,
                            totalGenerationTime: 0,
                            tokensGenerated: 0,
                            tokensPerSecond: nil,
                            modelUsed: llmService.modelName,
                            retrievalTime: retrievalTime,
                            retrievalConfigSummary: retrievalConfig.summary,
                            gatingDecision: "high_accuracy_blocked",
                            toolCallsMade: 0,
                            embeddingProvider: embeddingProviderId
                        )

                        let response = RAGResponse(
                            queryId: ragQueryValue.id,
                            retrievedChunks: diverseChunks,
                            generatedResponse: caution,
                            metadata: metadata,
                            confidenceScore: 0.0,
                            qualityWarnings: ["High Accuracy mode: insufficient supporting evidence"]
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                }

                let isAppleFMOnDevice = llmService is AppleFoundationLLMService
                var contextCandidates = diverseChunks
                var contextStrategy = "mmr"
                let strongTopSim =
                    auditTopSim >= 0.72 || (auditTopSim >= 0.68 && (auditTopSim - auditAvgTop5) >= 0.03)
                let shortQuery = queryWords <= 12
                let topDocId = rerankedChunks.first?.chunk.documentId
                let topDocSample = min(10, rerankedChunks.count)
                let topDocHits = rerankedChunks.prefix(topDocSample).filter { $0.chunk.documentId == topDocId }.count
                let topDocShare = topDocSample > 0 ? Double(topDocHits) / Double(topDocSample) : 0
                let focusedDocScope = uniqueDocCount <= 2 || topDocShare >= 0.6

                if isAppleFMOnDevice,
                   !initialWantsCloudContext,
                   strongTopSim,
                   shortQuery,
                   focusedDocScope,
                   let focusSeed = rerankedChunks.first
                {
                    let maxFocusedTotal = min(max(5, min(10, effectiveTopK)), rerankedChunks.count)
                    let neighborsPerSeed = min(4, max(1, (maxFocusedTotal - 1) / 2))
                    var focused = buildNeighborAwareFallback(
                        seeds: [focusSeed],
                        pool: rerankedChunks,
                        maxTotal: maxFocusedTotal,
                        neighborsPerSeed: neighborsPerSeed
                    )
                    if focused.count > 1 {
                        focused.sort {
                            if $0.chunk.documentId == $1.chunk.documentId {
                                return $0.chunk.metadata.chunkIndex < $1.chunk.metadata.chunkIndex
                            }
                            return $0.similarityScore > $1.similarityScore
                        }
                        contextCandidates = focused
                        contextStrategy = "focused_window"
                        let sourceName = focusSeed.sourceDocument.isEmpty ? "unknown" : focusSeed.sourceDocument
                        Log.info(
                            "🔎 Focused context window (\(focused.count) chunks) • topSim \(String(format: "%.3f", auditTopSim)) • source \(sourceName)",
                            category: .retrieval
                        )
                    }
                }

                // Step 5: Construct context from retrieved chunks (off-main)
                // Note: rawContext assembly is handled via engine.assembleContext with size limits

                // Smart context assembly: Use as many chunks as fit within the model's context window.
                // Apple Intelligence on-device context is 4,096 tokens (TN3193). PCC behavior may vary.
                var cloudConsentState: CloudConsentState = await MainActor.run {
                    cloudConsent[.applePCC] ?? .notDetermined
                }
                var cloudConsentAllowed = cloudConsentState == .allowed

                var hasTransientGrant: Bool = await MainActor.run {
                    transientConsentGrants.contains(.applePCC)
                }

                if isAppleFMOnDevice,
                   cloudConsentState == .denied,
                   inferenceConfig.executionContext != .onDeviceOnly
                {
                    inferenceConfig.executionContext = .onDeviceOnly
                    inferenceConfig.allowPrivateCloudCompute = false
                    Log.info("[RAG] PCC consent denied → onDeviceOnly", category: .pipeline)
                }

                if isAppleFMOnDevice,
                   networkAvailable,
                   inferenceConfig.allowPrivateCloudCompute,
                   inferenceConfig.executionContext != .onDeviceOnly,
                   !pccSuppressed,
                   cloudConsentState != .denied,
                   !cloudConsentAllowed,
                   !hasTransientGrant
                {
                    do {
                        try await ensureCloudConsentIfNeeded(
                            service: llmService,
                            prompt: question,
                            context: nil,
                            sourceChunks: contextCandidates.map { $0.chunk },
                            allowPrivateCloudCompute: inferenceConfig.allowPrivateCloudCompute
                        )
                        cloudConsentState = await MainActor.run {
                            cloudConsent[.applePCC] ?? .notDetermined
                        }
                        cloudConsentAllowed = cloudConsentState == .allowed
                        hasTransientGrant = await MainActor.run {
                            transientConsentGrants.contains(.applePCC)
                        }
                    } catch {
                        if case let RAGServiceError.cloudConsentDenied(provider) = error {
                            cloudConsentState = .denied
                            cloudConsentAllowed = false
                            hasTransientGrant = false
                            inferenceConfig.executionContext = .onDeviceOnly
                            inferenceConfig.allowPrivateCloudCompute = false
                            Log.info(
                                "[RAG] Cloud consent denied (\(provider.shortName)) → onDeviceOnly",
                                category: .pipeline
                            )
                        } else {
                            throw error
                        }
                    }
                }

                // Use PCC (65K) on real device with network, otherwise on-device (4096)
                // Simulator ALWAYS uses on-device since PCC isn't available
                #if targetEnvironment(simulator)
                    let pccEligible = false
                #else
                    let pccEligible = isAppleFMOnDevice
                        && networkAvailable
                        && inferenceConfig.allowPrivateCloudCompute
                        && inferenceConfig.executionContext != .onDeviceOnly
                        && !pccSuppressed
                #endif
                let allowLargeContext = pccEligible && (cloudConsentAllowed || hasTransientGrant)
                let applyTrivialCaps = isTrivial && !allowLargeContext
                let conservativeCharsPerToken: Double = isAppleFMOnDevice ? 2.5 : 3.5

                func estimateTokens(chars: Int) -> Int {
                    max(1, Int(ceil(Double(chars) / conservativeCharsPerToken)))
                }

                // PCC supports 65k tokens. On-device is 4k.
                // We default to 65k for Apple Intelligence unless explicitly constrained.
                let baseWindowTokens: Int = {
                    if llmService is AppleFoundationLLMService {
                        if allowLargeContext {
                            return 65536
                        } else {
                            // LOG WHY we are capping to 4096 to avoid "Simulator" confusion
                            if !networkAvailable {
                                Log.info("[RAG] Capping context to 4k (Network Unavailable)", category: .pipeline)
                            } else if inferenceConfig.executionContext == .onDeviceOnly {
                                Log.info("[RAG] Capping context to 4k (On-Device Preferred)", category: .pipeline)
                            } else if pccSuppressed {
                                Log.info("[RAG] Capping context to 4k (PCC Suppressed by previous error)", category: .pipeline)
                            } else if !inferenceConfig.allowPrivateCloudCompute {
                                Log.info("[RAG] Capping context to 4k (PCC Disabled in Settings)", category: .pipeline)
                            } else if !cloudConsentAllowed, !hasTransientGrant {
                                Log.info("[RAG] Capping context to 4k (No Cloud Consent)", category: .pipeline)
                            } else {
                                Log.warning("[RAG] Capping context to 4k (Unknown reason: pccEligible=\(pccEligible))", category: .pipeline)
                            }
                            return 4096
                        }
                    }
                    return inferenceConfig.contextLength ?? 4096
                }()

                // More conservative token budgeting for Apple Intelligence's 4096 limit
                func estimateTokensConservative(chars: Int) -> Int {
                    max(1, Int(ceil(Double(chars) / conservativeCharsPerToken)))
                }

                // Use appropriate safety margin based on context size
                let safetyTokens = isAppleFMOnDevice ? (allowLargeContext ? 2000 : 900) : 600
                let systemPromptTokens = estimateTokensConservative(chars: (inferenceConfig.systemPrompt ?? "").count)
                let promptOverheadTokens = 200 + systemPromptTokens // Template overhead
                let questionTokens = estimateTokensConservative(chars: question.count)

                // Reserve room for output - more for PCC, less for on-device
                let reservedOutputTokens = allowLargeContext
                    ? max(1024, min(inferenceConfig.maxTokens, 2048))
                    : max(256, min(inferenceConfig.maxTokens, 512))
                let availableForContextTokens = max(
                    0,
                    baseWindowTokens - safetyTokens - promptOverheadTokens - questionTokens - reservedOutputTokens
                )
                let cappedContextTokens = applyTrivialCaps
                    ? min(availableForContextTokens, allowLargeContext ? 3000 : 2600)
                    : availableForContextTokens
                // Conservative limits: modelmanagerd routing is opaque, so stay under 4096 tokens to avoid crashes
                // PCC routing is unreliable for simple queries regardless of context size
                // FIXED: PCC can fail and route to on-device (4096 limit). Be conservative initially.
                // If PCC works, we can always expand. If it fails, fallback is smoother.
                let maxContextCharsCap = isAppleFMOnDevice
                    ? (allowLargeContext ? 65000 : (applyTrivialCaps ? 3200 : 9500))
                    : (applyTrivialCaps ? 7000 : 12000)
                let maxContextChars = min(
                    max(600, Int(Double(cappedContextTokens) * conservativeCharsPerToken)),
                    maxContextCharsCap
                )

                // Use compact mode when on-device (simulator or offline) to maximize content in limited space
                let useCompactMode = isAppleFMOnDevice && !allowLargeContext

                #if targetEnvironment(simulator)
                    Log.info("[RAG] Simulator mode: using on-device context budget (4096 tokens, \(maxContextChars) chars)", category: .pipeline)
                #endif

                Log.debug("Context budget: base=\(baseWindowTokens), question=\(questionTokens), available=\(availableForContextTokens) tokens → \(maxContextChars) chars, compact=\(useCompactMode)", category: .pipeline)

                let (context, actualChunksUsed) = await engine.assembleContext(
                    chunks: contextCandidates,
                    maxChars: maxContextChars,
                    compact: useCompactMode
                )
                Log.info(
                    "   ✓ Using \(actualChunksUsed)/\(contextCandidates.count) chunks (\(context.count) chars)\(useCompactMode ? " [compact]" : "") • \(contextStrategy)",
                    category: .pipeline
                )

                let contextSize = context.count
                let contextWords = context.split(separator: " ").count
                let includedRetrievedChunks = Array(contextCandidates.prefix(actualChunksUsed))
                let includedChunks = includedRetrievedChunks.map { $0.chunk }
                recoveryRetrievedChunks = includedRetrievedChunks

                Log.section("Step 5: Context Assembly Complete", level: .info, category: .pipeline)
                Log.info(
                    "✓ Final context: \(contextSize) chars, \(contextWords) words from \(actualChunksUsed) chunks",
                    category: .pipeline
                )
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Context assembled",
                    metadata: [
                        "chunks": "\(actualChunksUsed)",
                        "chars": "\(contextSize)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ]
                )

                emitThinkingEvent(
                    .context,
                    title: "Context ready",
                    detail: "\(actualChunksUsed) chunks • \(contextWords) words"
                )

                let chunkingTarget = selectedContainer?.chunkingDirective?.targetWordWindow
                    ?? documentProcessor.targetChunkSize
                let chunkingOverlap = selectedContainer?.chunkingDirective?.overlapWords
                    ?? documentProcessor.chunkOverlap
                let chunkingSource = selectedContainer?.chunkingDirective?.source.rawValue
                    ?? "baseline"
                let vectorDBKind = selectedContainer?.vectorDBKind ?? .persistentJSON

                let auditSnapshot = RAGAuditSnapshot(
                    timestamp: Date(),
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    embeddingProviderId: embeddingProviderId,
                    embeddingDim: selectedDim,
                    vectorDBKind: vectorDBKind,
                    chunkingTargetWords: chunkingTarget,
                    chunkingOverlapWords: chunkingOverlap,
                    chunkingSource: chunkingSource,
                    qualityMode: qualityMode,
                    retrievalConfig: retrievalConfig,
                    lenientRetrieval: auditLenient,
                    dynamicMin: auditDynamicMin,
                    topSim: auditTopSim,
                    secondSim: auditSecondSim,
                    avgTop5: auditAvgTop5,
                    acceptanceOverride: auditAcceptanceOverride,
                    totalStoredChunks: totalStored,
                    candidatesCount: auditCandidatesCount,
                    rerankedCount: auditRerankedCount,
                    filteredCount: auditFilteredCount,
                    droppedCount: auditDroppedCount,
                    mmrSelectedCount: auditMMRSelectedCount,
                    uniqueDocCount: auditUniqueDocCount,
                    contextStrategy: contextStrategy,
                    contextChars: contextSize,
                    contextWords: contextWords,
                    contextChunksUsed: actualChunksUsed,
                    maxContextChars: maxContextChars,
                    baseWindowTokens: baseWindowTokens,
                    safetyTokens: safetyTokens,
                    promptOverheadTokens: promptOverheadTokens,
                    questionTokens: questionTokens,
                    reservedOutputTokens: reservedOutputTokens,
                    availableContextTokens: availableForContextTokens,
                    executionContext: inferenceConfig.executionContext,
                    allowPrivateCloudCompute: inferenceConfig.allowPrivateCloudCompute,
                    networkConnected: networkAvailable,
                    wantsCloudContext: allowLargeContext,
                    reliabilityModeEnabled: reliabilityModeEnabled,
                    allowUngroundedFallback: allowUngroundedFallback,
                    modelName: llmService.modelName
                )

                await MainActor.run {
                    self.lastAuditSnapshot = auditSnapshot
                }

                // If context is empty, fallback to direct chat to avoid downstream failures
                if actualChunksUsed == 0 || context.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] Empty context after assembly",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .warning,
                        title: "Context empty",
                        detail: "Insufficient evidence"
                    )
                    if allowUngroundedFallback {
                        let response = try await generateDirectChatResponse(
                            question: question,
                            ragQuery: ragQueryValue,
                            inferenceConfig: inferenceConfig,
                            pipelineStartTime: pipelineStartTime,
                            retrievalTime: retrievalTime,
                            fallbackNote: "Empty assembled context; replied without RAG context."
                        )
                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: response
                        )
                    }
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: [],
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "I couldn't assemble enough context to answer reliably.",
                        gatingDecision: "context_empty"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                // Step 6: Generate response using LLM with augmented context
                Log.section("Step 6: LLM Generation", level: .info, category: .pipeline)
                let generationStartTime = Date()

                var genConfig = inferenceConfig

                // Set explicit system prompt for RAG to ensure agentic behavior
                // This overrides the default generic instructions in LLMService
                genConfig.systemPrompt = """
                You are an intelligent assistant with access to the user's knowledge base.
                Synthesize the provided excerpts to answer the user's question comprehensively.
                If the excerpts cover multiple functions or contexts (e.g., different modes, actions, or settings), explain all of them to provide a complete picture.
                Connect related concepts and provide a smart, coherent summary.
                Cite sources like [S1] to ground your answer.
                """

                // Adjust temperature based on quality mode for accuracy control
                switch qualityMode {
                case .fast:
                    // Allow more creative responses
                    break
                case .balanced:
                    genConfig.temperature = min(genConfig.temperature, 0.5)
                case .thorough:
                    // Very deterministic for maximum accuracy
                    genConfig.temperature = min(genConfig.temperature, 0.3)
                }

                // High Accuracy retrieval config overrides quality mode
                if retrievalConfig == .highAccuracy {
                    genConfig.temperature = min(genConfig.temperature, 0.2)
                }

                // Provider-aware token budgeting (avoid hard 4K clamps for large-context providers).
                let contextTokens = estimateTokensConservative(chars: context.count)
                let availableForOutput = max(
                    128,
                    baseWindowTokens - safetyTokens - promptOverheadTokens - questionTokens - contextTokens
                )
                if genConfig.maxTokens > availableForOutput {
                    genConfig.maxTokens = availableForOutput
                }
                if isTrivial, !allowLargeContext {
                    let capped = min(genConfig.maxTokens, 384)
                    if capped != genConfig.maxTokens {
                        Log.info(
                            "[RAG] Trivial query detected - limiting response to \(capped) tokens",
                            category: .llm
                        )
                    }
                    genConfig.maxTokens = capped
                }

                // Inject conversational history (last 2 turns) to support follow-up questions
                // e.g. "What is it?" uses history to resolve "it"
                let history = chatHistory(for: selectedId)

                // Only drop the last message if it matches the current question (avoid duplicating)
                // or if we know for sure ChatScreen persisted it. Safest is to check content match.
                let lastMsg = history.last
                let dropsCurrent = lastMsg?.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    == question.trimmingCharacters(in: .whitespacesAndNewlines)

                let previousMessages = history
                    .filter { $0.role != .system }
                    .dropLast(dropsCurrent ? 1 : 0)
                    .suffix(4) // Keep last 4 turns (2 User, 2 Assistant)

                var historyContext = ""
                if !previousMessages.isEmpty {
                    historyContext = "PREVIOUS CONVERSATION:\n" + previousMessages.map {
                        let role = $0.role == .user ? "User" : "Assistant"
                        // Truncate long history items to preserve token budget for RAG context
                        let content = $0.content.replacingOccurrences(of: "\n", with: " ")
                        let truncated = content.count > 300 ? String(content.prefix(300)) + "..." : content
                        return "\(role): \(truncated)"
                    }.joined(separator: "\n") + "\n\nCURRENT QUESTION: "
                }

                let requiresCitations = retrievalConfig.requireExplicitCitations
                    || qualityMode.requiresCitations
                let promptForGeneration: String
                if requiresCitations {
                    promptForGeneration = historyContext + question
                        + "\n\nAnswer directly with no preamble. Cite sources using the bracket ids like [S1], [S2]. If the context is insufficient, say so."
                } else {
                    promptForGeneration = historyContext + question
                }

                // Attempt generation with retry on context-overflow
                var llmResponse: LLMResponse
                var generationContext = context
                var generationChunks = includedChunks
                var generationRetrievedChunks = includedRetrievedChunks
                var usedOverflowRetry = false
                emitThinkingEvent(
                    .generation,
                    title: "Generating answer",
                    detail: llmService.modelName
                )

                do {
                    llmResponse = try await generateWithFallback(
                        prompt: promptForGeneration,
                        context: generationContext,
                        config: genConfig,
                        sourceChunks: generationChunks
                    )
                } catch {
                    // Check if this is a context overflow error
                    let isOverflowError = isContextOverflowError(error)

                    #if targetEnvironment(simulator)
                        if isOverflowError {
                            // SIMULATOR: PCC not available, must retry with smaller context
                            Log.warning("[RAG] Simulator context overflow - building evidence pack", category: .llm)
                            let reducedMax = max(256, min(genConfig.maxTokens, 384))
                            let onDeviceMaxChars = 8500 // Increased from 3500 to utilize full 4096 token window

                            let targetChunkCount = min(
                                contextCandidates.count,
                                isTrivial ? 6 : 9
                            )
                            let maxCharsPerChunk = max(
                                220,
                                min(
                                    isTrivial ? 600 : 800,
                                    onDeviceMaxChars / max(1, targetChunkCount)
                                )
                            )
                            let (context2, usedRetryChunks) = await buildEvidencePackContext(
                                question: question,
                                candidates: contextCandidates,
                                maxContextChars: onDeviceMaxChars,
                                maxChunks: targetChunkCount,
                                maxCharsPerChunk: maxCharsPerChunk
                            )
                            let retryRetrievedChunks = usedRetryChunks
                            let retryChunks = retryRetrievedChunks.map { $0.chunk }
                            generationContext = context2
                            generationChunks = retryChunks
                            generationRetrievedChunks = retryRetrievedChunks
                            recoveryRetrievedChunks = generationRetrievedChunks
                            usedOverflowRetry = true
                            var retryConfig = genConfig
                            retryConfig.maxTokens = reducedMax
                            retryConfig.executionContext = .onDeviceOnly
                            retryConfig.allowPrivateCloudCompute = false

                            TelemetryCenter.emit(
                                .system,
                                severity: .warning,
                                title: "Simulator: evidence pack",
                                metadata: [
                                    "contextChars": "\(context2.count)",
                                    "chunksUsed": "\(retryRetrievedChunks.count)",
                                ]
                            )
                            llmResponse = try await generateWithFallback(
                                prompt: promptForGeneration,
                                context: generationContext,
                                config: retryConfig,
                                sourceChunks: generationChunks
                            )
                        } else {
                            // Other error - just rethrow
                            throw error
                        }
                    #else
                        if isOverflowError {
                            let reason = networkAvailable ? "PCC request overflowed" : "offline mode"
                            // FIX: Do NOT suppress PCC globally.
                            // Just because this specific request overflowed locally (e.g. system routed wrong)
                            // doesn't mean PCC is down. We will retry with smaller context, but keep PCC enabled.

                            Log.warning(
                                "[RAG] Context overflow (\(reason)) - building evidence pack",
                                category: .llm
                            )
                            TelemetryCenter.emit(
                                .system,
                                severity: .warning,
                                title: "Context overflow - evidence pack",
                                metadata: [
                                    "reason": reason,
                                    "chunks": "\(contextCandidates.count)",
                                ]
                            )

                            // Apple FM has hard 4096 token limit on-device
                            // Budget: 4096 - 900 (safety) - ~700 (prompt overhead) - ~20 (question) - 768 (output) = ~1700 tokens
                            // At 2.4 chars/token, that's ~4000 chars max for context
                            let reducedMax = isTrivial
                                ? max(256, min(genConfig.maxTokens, 384))
                                : max(512, min(genConfig.maxTokens, 768))
                            let onDeviceBudgetTokens = max(
                                200,
                                4096 - 1000 - promptOverheadTokens - questionTokens - reducedMax
                            )
                            // FIXED: Reduced from 8500 to 3500 chars to actually fit in 4096 token window
                            // Apple's modelmanagerd routes to PCC when context exceeds on-device capacity
                            let onDeviceMaxChars = min(
                                isTrivial ? 2400 : 3500,
                                max(800, Int(Double(onDeviceBudgetTokens) * conservativeCharsPerToken))
                            )
                            let baseCandidates = retryCandidates.isEmpty ? contextCandidates : retryCandidates
                            // Use fewer, higher-quality chunks rather than many fragmented ones
                            let fallbackChunkCap = isTrivial
                                ? min(5, baseCandidates.count)
                                : min(6, baseCandidates.count)
                            let seedLimit = isTrivial
                                ? min(2, baseCandidates.count)
                                : min(3, baseCandidates.count)
                            let seedChunks = Array(baseCandidates.prefix(seedLimit))
                            let neighborPool = rerankedChunks.isEmpty ? baseCandidates : rerankedChunks
                            let fallbackChunks = buildNeighborAwareFallback(
                                seeds: seedChunks,
                                pool: neighborPool,
                                maxTotal: fallbackChunkCap
                            )

                            // Use fewer chunks with more content each for better coherence
                            let targetChunkCount = min(
                                fallbackChunks.count,
                                isTrivial ? 4 : 5
                            )
                            // Give each chunk more room for context - better quality over quantity
                            let maxCharsPerChunk = max(
                                350,
                                min(
                                    isTrivial ? 650 : 750,
                                    onDeviceMaxChars / max(1, targetChunkCount)
                                )
                            )
                            let (context2, usedRetryChunks) = await buildEvidencePackContext(
                                question: question,
                                candidates: fallbackChunks,
                                maxContextChars: onDeviceMaxChars,
                                maxChunks: targetChunkCount,
                                maxCharsPerChunk: maxCharsPerChunk
                            )
                            let retryRetrievedChunks = usedRetryChunks
                            let retryChunks = retryRetrievedChunks.map { $0.chunk }
                            generationContext = context2
                            generationChunks = retryChunks
                            generationRetrievedChunks = retryRetrievedChunks
                            recoveryRetrievedChunks = generationRetrievedChunks
                            usedOverflowRetry = true
                            var retryConfig = genConfig
                            retryConfig.maxTokens = reducedMax
                            retryConfig.executionContext = .onDeviceOnly
                            retryConfig.allowPrivateCloudCompute = false
                            // Use minimal system prompt for on-device fallback to maximize context budget
                            retryConfig.systemPrompt = "Answer questions using ONLY the provided context. Be concise but complete. Cite sources as [S1], [S2] etc."

                            TelemetryCenter.emit(
                                .system,
                                severity: .warning,
                                title: "Evidence-pack retry",
                                metadata: [
                                    "contextChars": "\(context2.count)",
                                    "chunksUsed": "\(retryRetrievedChunks.count)",
                                ]
                            )

                            llmResponse = try await generateWithFallback(
                                prompt: promptForGeneration,
                                context: generationContext,
                                config: retryConfig,
                                sourceChunks: generationChunks
                            )
                        } else {
                            // Other error - just rethrow
                            throw error
                        }
                    #endif
                }

                var responseText = llmResponse.text

                let preserveStreamingResponse = LLMStreamingContext.handler != nil
                if requiresCitations, !responseHasCitations(responseText) {
                    let missingCitationDetail =
                        (preserveStreamingResponse || allowUngroundedFallback)
                            ? "Using best available answer"
                            : "Retrying with strict citation requirement"
                    emitThinkingEvent(
                        .warning,
                        title: "Missing citations",
                        detail: missingCitationDetail
                    )
                    TelemetryCenter.emit(
                        .generation,
                        severity: .warning,
                        title: "Missing citations",
                        metadata: [
                            "model": llmService.modelName,
                            "container": selectedName,
                        ]
                    )
                    if preserveStreamingResponse || allowUngroundedFallback {
                        Log.warning(
                            "Missing citations; preserving streamed response",
                            category: .llm
                        )
                    } else {
                        let retryPrompt = question
                            + "\n\nYou must cite sources using bracket ids like [S1], [S2]. "
                            + "If you cannot support the answer with citations, respond exactly: "
                            + "\"Insufficient evidence in provided sources.\" "
                            + "Answer directly with no preamble."
                        var retryConfig = genConfig
                        retryConfig.temperature = min(retryConfig.temperature, 0.2)
                        if usedOverflowRetry {
                            retryConfig.maxTokens = min(retryConfig.maxTokens, 1024)
                        }
                        if let retryResponse = try? await generateWithFallback(
                            prompt: retryPrompt,
                            context: generationContext,
                            config: retryConfig,
                            sourceChunks: generationChunks
                        ) {
                            llmResponse = retryResponse
                            responseText = retryResponse.text
                        }
                    }
                }

                if requiresCitations,
                   !responseHasCitations(responseText),
                   !allowUngroundedFallback,
                   !preserveStreamingResponse
                {
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: generationRetrievedChunks,
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "I couldn't produce a cited answer from the provided sources.",
                        gatingDecision: "missing_citations"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                let generationTime = Date().timeIntervalSince(generationStartTime)
                let responseWordCount = wordCount(of: responseText)
                TelemetryCenter.emit(
                    .generation,
                    title: "Response generated",
                    metadata: [
                        "model": llmService.modelName,
                        "tokens": "\(llmResponse.tokensGenerated)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                        "words": "\(responseWordCount)",
                        "characters": "\(responseText.count)",
                    ],
                    duration: generationTime
                )

                emitThinkingEvent(
                    .generation,
                    title: "Answer composed",
                    detail: "\(llmResponse.tokensGenerated) tokens in \(String(format: "%.2f", generationTime))s"
                )

                // Wrap all printing in error handling to prevent crashes
                do {
                    Log.info("✓ Response generated", category: .llm)
                    Log.info("  Model: \(llmService.modelName)", category: .llm)
                    Log.info(
                        "  Generation time: \(String(format: "%.2f", generationTime))s",
                        category: .performance
                    )

                    // Access response text safely
                    Log.debug("  Response length: \(responseText.count) chars", category: .llm)
                    Log.debug("  Words: \(responseWordCount)", category: .llm)

                    if llmResponse.tokensGenerated > 0 {
                        Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
                        if let tps = llmResponse.tokensPerSecond {
                            Log.debug(
                                "  Speed: \(String(format: "%.1f", tps)) tokens/sec",
                                category: .performance
                            )
                        }
                    }

                    // Verify we got a response
                    guard !responseText.isEmpty else {
                        Log.warning("⚠️  Warning: LLM returned empty response", category: .llm)
                        throw RAGServiceError.modelNotAvailable
                    }

                    // Step 7: Calculate confidence score and quality warnings
                    Log.section("Step 7: Quality Assessment", level: .info, category: .pipeline)
                    let totalDocsCount = await snapshotDocumentsCount()
                    let (confidenceScore, qualityWarnings) = await engine.assessResponseQuality(
                        chunks: generationRetrievedChunks,
                        query: question,
                        totalDocs: totalDocsCount
                    )

                    if !qualityWarnings.isEmpty {
                        Log.warning("⚠️  Quality Warnings:", category: .pipeline)
                        for warning in qualityWarnings {
                            Log.warning("   • \(warning)", category: .pipeline)
                        }
                    }

                    Log.info(
                        "📊 Confidence Score: \(String(format: "%.1f", confidenceScore * 100))%",
                        category: .pipeline
                    )
                    TelemetryCenter.emit(
                        .system,
                        title: "Response evaluated",
                        metadata: [
                            "confidence": String(format: "%.2f", confidenceScore),
                        ]
                    )

                    // Step 8: Package results
                    let pipelineTotalTime = Date().timeIntervalSince(pipelineStartTime)

                    Log.box(
                        "ENHANCED PIPELINE COMPLETE ✓",
                        level: .info,
                        category: .pipeline,
                        content: [
                            "Total time: \(String(format: "%.2f", pipelineTotalTime))s",
                            "  - Query Expansion: \(String(format: "%.0f", expansionTime * 1000))ms",
                            "  - Embedding: \(String(format: "%.0f", embeddingTime * 1000))ms",
                            "  - Hybrid Retrieval: \(String(format: "%.0f", retrievalTime * 1000))ms",
                            "  - Re-ranking: \(String(format: "%.0f", rerankTime * 1000))ms",
                            "  - MMR Diversification: \(String(format: "%.0f", mmrTime * 1000))ms",
                            "  - Quality Assessment: <1ms",
                            "  - Generation: \(String(format: "%.2f", generationTime))s",
                        ]
                    )
                    TelemetryCenter.emit(
                        .system,
                        title: "Query complete",
                        metadata: [
                            "duration": String(format: "%.2f", pipelineTotalTime),
                            "chunks": "\(generationRetrievedChunks.count)",
                            "container": selectedName,
                            "containerId": selectedId.uuidString,
                        ],
                        duration: pipelineTotalTime
                    )

                    // Step 9: Create response metadata
                    let gatingSummary: String? =
                        acceptanceOverride
                            ? "acceptance_override" : lenient ? "lenient" : nil
                    let metadata = ResponseMetadata(
                        timeToFirstToken: llmResponse.timeToFirstToken,
                        totalGenerationTime: llmResponse.totalTime,
                        tokensGenerated: llmResponse.tokensGenerated,
                        tokensPerSecond: llmResponse.tokensPerSecond,
                        modelUsed: llmResponse.modelName ?? llmService.modelName,
                        retrievalTime: retrievalTime,
                        retrievalConfigSummary: retrievalConfig.summary,
                        gatingDecision: gatingSummary,
                        toolCallsMade: llmResponse.toolCallsMade,
                        embeddingProvider: embeddingProviderId
                    )

                    let response = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: generationRetrievedChunks,
                        generatedResponse: responseText,
                        metadata: metadata,
                        confidenceScore: confidenceScore,
                        qualityWarnings: qualityWarnings
                    )

                    let totalTime = Date().timeIntervalSince(pipelineStartTime)
                    Log.info(
                        "✅ Enhanced RAG pipeline complete in \(String(format: "%.2f", totalTime))s",
                        category: .pipeline
                    )

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )

                } catch {
                    Log.error(" Error during response processing: \(error)")
                    // Still try to return something
                    let metadata = ResponseMetadata(
                        timeToFirstToken: nil,
                        totalGenerationTime: generationTime,
                        tokensGenerated: 0,
                        tokensPerSecond: nil,
                        modelUsed: llmResponse.modelName ?? llmService.modelName,
                        retrievalTime: retrievalTime,
                        retrievalConfigSummary: retrievalConfig.summary,
                        toolCallsMade: 0,
                        embeddingProvider: embeddingProviderId
                    )

                    let response = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: generationRetrievedChunks,
                        generatedResponse: "Error processing response",
                        metadata: metadata,
                        confidenceScore: 0.0,
                        qualityWarnings: ["Error occurred during response processing"]
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

            } else {
                if !allowUngroundedFallback {
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: [],
                        retrievalTime: 0,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: "This library has no documents yet.",
                        gatingDecision: "no_documents"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }

                // Direct LLM chat without documents
                Log.info("ℹ️  No documents loaded - using direct LLM chat mode", category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    title: "Direct chat mode",
                    metadata: [
                        "model": llmService.modelName,
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ]
                )

                emitThinkingEvent(
                    .planning,
                    title: "Direct chat",
                    detail: "No documents in \(selectedName)"
                )

                Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)
                let generationStartTime = Date()

                emitThinkingEvent(
                    .generation,
                    title: "Generating answer",
                    detail: llmService.modelName
                )
                let llmResponse = try await generateWithFallback(
                    prompt: question,
                    context: nil, // No document context
                    config: inferenceConfig,
                    sourceChunks: []
                )

                let generationTime = Date().timeIntervalSince(generationStartTime)
                TelemetryCenter.emit(
                    .generation,
                    title: "Response generated",
                    metadata: [
                        "model": llmService.modelName,
                        "tokens": "\(llmResponse.tokensGenerated)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ],
                    duration: generationTime
                )

                emitThinkingEvent(
                    .generation,
                    title: "Answer composed",
                    detail: "\(llmResponse.tokensGenerated) tokens in \(String(format: "%.2f", generationTime))s"
                )

                Log.info("✓ Response generated", category: .llm)
                Log.info("  Model: \(llmService.modelName)", category: .llm)
                Log.info(
                    "  Generation time: \(String(format: "%.2f", generationTime))s",
                    category: .performance
                )
                Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
                Log.debug(
                    "  Speed: \(String(format: "%.1f", llmResponse.tokensPerSecond ?? 0)) tokens/sec",
                    category: .performance
                )

                let metadata = ResponseMetadata(
                    timeToFirstToken: llmResponse.timeToFirstToken,
                    totalGenerationTime: llmResponse.totalTime,
                    tokensGenerated: llmResponse.tokensGenerated,
                    tokensPerSecond: llmResponse.tokensPerSecond,
                    modelUsed: llmResponse.modelName ?? llmService.modelName, // Use actual execution location if available
                    retrievalTime: 0, // No retrieval in direct chat mode
                    retrievalConfigSummary: retrievalConfig.summary,
                    toolCallsMade: llmResponse.toolCallsMade,
                    embeddingProvider: embeddingProviderId
                )

                let response = RAGResponse(
                    queryId: ragQueryValue.id,
                    retrievedChunks: [], // No chunks in direct chat mode
                    generatedResponse: llmResponse.text,
                    metadata: metadata
                )

                let totalTime = Date().timeIntervalSince(pipelineStartTime)
                Log.info(
                    "✅ [RAGService] Direct chat complete in \(String(format: "%.2f", totalTime))s",
                    category: .pipeline
                )
                TelemetryCenter.emit(
                    .system,
                    title: "Query complete",
                    metadata: [
                        "duration": String(format: "%.2f", totalTime),
                        "mode": "direct",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ],
                    duration: totalTime
                )

                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }

        } catch {
            let isContextOverflow = isContextOverflowError(error)
            let errorMessage = error.localizedDescription

            // NEW: Catch false-positive language detection errors
            let isLanguageError = errorMessage.contains("Apple Intelligence couldn't process this query")
                || errorMessage.contains("Unsupported language")
                || errorMessage.contains("context window") // Catch overflow here too

            // Trigger Reliability Mode if enabled OR if we hit a language/context error
            if reliabilityModeEnabled || isLanguageError {
                await MainActor.run { lastError = nil }

                let reason = isLanguageError ? "Language detection/Context limit triggered fallback" : errorMessage
                Log.warning("[RAGService] 🛡️ Reliability fallback engaged: \(reason)", category: .pipeline)

                // If we have retrieved chunks, use them to generate a safe answer
                if !recoveryRetrievedChunks.isEmpty {
                    let fallbackResponse = await buildReliabilityFallbackResponse(
                        question: question,
                        ragQuery: ragQuery ?? RAGQuery(query: question, topK: effectiveTopK),
                        inferenceConfig: inferenceConfig,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        retrievedChunks: recoveryRetrievedChunks,
                        retrievalTime: recoveryRetrievalTime,
                        reason: "AI System Limit: Switching to Safe Mode"
                    )

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: fallbackResponse
                    )
                }
            }

            Log.error(" [RAGService] Query execution failed: \(error.localizedDescription)", category: .pipeline)
            TelemetryCenter.emit(
                .system,
                severity: .error,
                title: "Query failed",
                metadata: [
                    "error": error.localizedDescription,
                    "model": activeModelName,
                ]
            )

            // Re-throw specific errors for UI handling
            if isContextOverflow {
                throw LLMError.contextWindowExceeded
            }
            throw error
        }
    }

    // MARK: - Direct Chat Fallback Helper

    /// Build a grounded-only abstain response when evidence is insufficient.
    private func makeGroundedAbstainResponse(
        question _: String,
        ragQuery: RAGQuery,
        retrievedChunks: [RetrievedChunk],
        retrievalTime: TimeInterval,
        retrievalConfig: RetrievalConfig,
        embeddingProviderId: String,
        reason: String,
        gatingDecision: String
    ) async -> RAGResponse {
        Log.info("ℹ️  Grounded-only abstain: \(gatingDecision)", category: .retrieval)

        let responseText = """
        I want to stay grounded in your library, but I don't have enough evidence to answer that reliably.

        \(reason)

        Try:
        • Add or select a library with relevant documents.
        • Ask about a specific document title or section.
        • Include keywords that appear in your sources.
        """

        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: 0,
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            gatingDecision: gatingDecision,
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId
        )

        return RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: retrievedChunks,
            generatedResponse: responseText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: ["Grounded-only: \(reason)"]
        )
    }

    /// Reliability-first fallback: return a best-effort answer instead of surfacing errors.
    private func buildReliabilityFallbackResponse(
        question: String,
        ragQuery: RAGQuery,
        inferenceConfig: InferenceConfig,
        retrievalConfig: RetrievalConfig,
        embeddingProviderId: String,
        retrievedChunks: [RetrievedChunk],
        retrievalTime: TimeInterval,
        reason: String
    ) async -> RAGResponse {
        Log.warning("[RAG] Reliability fallback engaged: \(reason)", category: .pipeline)
        let warnings = ["Reliability fallback: \(reason)"]

        let targetChunkCount = min(6, retrievedChunks.count)
        let maxContextChars = min(3600, max(1200, 700 * max(1, targetChunkCount)))
        let (fallbackContext, usedRetrieved) = await buildEvidencePackContext(
            question: question,
            candidates: retrievedChunks,
            maxContextChars: maxContextChars,
            maxChunks: targetChunkCount,
            maxCharsPerChunk: 800
        )
        Log.info(
            "[RAG] Reliability context: \(fallbackContext.count) chars, \(usedRetrieved.count) chunks",
            category: .pipeline
        )
        let sourceChunks = usedRetrieved.map { $0.chunk }

        var fallbackConfig = inferenceConfig
        fallbackConfig.executionContext = .onDeviceOnly
        fallbackConfig.allowPrivateCloudCompute = false
        fallbackConfig.maxTokens = min(fallbackConfig.maxTokens, 512)
        fallbackConfig.temperature = min(fallbackConfig.temperature, 0.4)

        let fallbackPrompt =
            question
                + "\n\nAnswer using any available excerpts. If evidence is thin, say so and summarize what is available. Cite sources like [S1]."

        if let llmResponse = try? await generateWithFallback(
            prompt: fallbackPrompt,
            context: fallbackContext.isEmpty ? nil : fallbackContext,
            config: fallbackConfig,
            sourceChunks: sourceChunks
        ) {
            let metadata = ResponseMetadata(
                timeToFirstToken: llmResponse.timeToFirstToken,
                totalGenerationTime: llmResponse.totalTime,
                tokensGenerated: llmResponse.tokensGenerated,
                tokensPerSecond: llmResponse.tokensPerSecond,
                modelUsed: llmResponse.modelName ?? llmService.modelName,
                retrievalTime: retrievalTime,
                retrievalConfigSummary: retrievalConfig.summary,
                gatingDecision: "reliability_fallback",
                toolCallsMade: llmResponse.toolCallsMade,
                embeddingProvider: embeddingProviderId
            )
            return RAGResponse(
                queryId: ragQuery.id,
                retrievedChunks: usedRetrieved,
                generatedResponse: llmResponse.text,
                metadata: metadata,
                confidenceScore: 0.0,
                qualityWarnings: warnings
            )
        }

        let terms = extractQueryTerms(question)
        let snippetBullets = usedRetrieved.prefix(3).enumerated().map { idx, retrieved in
            let snippet = extractSnippet(
                from: retrieved.chunk.content,
                queryTerms: terms,
                maxChars: 240
            )
            return "• \(snippet) [S\(idx + 1)]"
        }
        let responseText: String
        if snippetBullets.isEmpty {
            responseText = "I can't reach the model right now, but your documents are still available. Please try again in a moment."
        } else {
            responseText = """
            Here’s the most relevant evidence I can access right now:
            \(snippetBullets.joined(separator: "\n"))
            """
        }

        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: 0,
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            gatingDecision: "reliability_fallback",
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId
        )

        return RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: usedRetrieved,
            generatedResponse: responseText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: warnings + ["Extractive fallback"]
        )
    }

    /// Generate a direct LLM response without document context.
    /// Used as a graceful fallback when retrieval returns no results or documents are unavailable.
    private func generateDirectChatResponse(
        question: String,
        ragQuery: RAGQuery,
        inferenceConfig: InferenceConfig,
        pipelineStartTime: Date,
        retrievalTime: TimeInterval,
        fallbackNote: String? = nil
    ) async throws -> RAGResponse {
        Log.info("ℹ️  Falling back to direct LLM chat mode", category: .pipeline)
        let retrievalConfig = await MainActor.run {
            self.containerService.activeContainer?.retrievalConfig ?? .default
        }
        TelemetryCenter.emit(
            .system,
            title: "Direct chat mode",
            metadata: ["model": llmService.modelName]
        )

        Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)
        let generationStartTime = Date()

        let llmResponse = try await generateWithFallback(
            prompt: question,
            context: nil, // No document context
            config: inferenceConfig,
            sourceChunks: []
        )

        let generationTime = Date().timeIntervalSince(generationStartTime)
        TelemetryCenter.emit(
            .generation,
            title: "Response generated",
            metadata: [
                "model": llmService.modelName,
                "tokens": "\(llmResponse.tokensGenerated)",
            ],
            duration: generationTime
        )

        Log.info("✓ Response generated", category: .llm)
        Log.info("  Model: \(llmService.modelName)", category: .llm)
        Log.info(
            "  Generation time: \(String(format: "%.2f", generationTime))s", category: .performance
        )
        Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
        Log.debug(
            "  Speed: \(String(format: "%.1f", llmResponse.tokensPerSecond ?? 0)) tokens/sec",
            category: .performance
        )

        let metadata = ResponseMetadata(
            timeToFirstToken: llmResponse.timeToFirstToken,
            totalGenerationTime: llmResponse.totalTime,
            tokensGenerated: llmResponse.tokensGenerated,
            tokensPerSecond: llmResponse.tokensPerSecond,
            modelUsed: llmResponse.modelName ?? llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            toolCallsMade: llmResponse.toolCallsMade,
            embeddingProvider: nil // No embedding used in direct chat fallback
        )

        var warnings: [String] = []
        if let note = fallbackNote { warnings.append(note) }

        let response = RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: [],
            generatedResponse: llmResponse.text,
            metadata: metadata,
            confidenceScore: 1.0,
            qualityWarnings: warnings
        )

        let totalTime = Date().timeIntervalSince(pipelineStartTime)
        Log.info(
            "✅ [RAGService] Direct chat complete in \(String(format: "%.2f", totalTime))s",
            category: .pipeline
        )
        TelemetryCenter.emit(
            .system,
            title: "Query complete",
            metadata: [
                "duration": String(format: "%.2f", totalTime),
                "mode": "direct",
            ],
            duration: totalTime
        )

        return response
    }

    private func isContextOverflowError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()

        // Standard context overflow indicators
        if message.contains("context"), message.contains("window") { return true }
        if message.contains("context")
            && (message.contains("exceed") || message.contains("exceeded"))
        {
            return true
        }
        if message.contains("token"), message.contains("limit") { return true }
        if message.contains("4096"), message.contains("token") { return true }

        // PCC-related failures that indicate we should fall back to on-device with smaller context
        // These occur when the system expected to use PCC (65K tokens) but couldn't,
        // and the context we sent is too large for on-device (4096 tokens)
        if message.contains("private cloud compute") && message.contains("unavailable") { return true }
        if message.contains("pcc") && (message.contains("unavailable") || message.contains("required")) { return true }
        if message.contains("cloud") && message.contains("unavailable") { return true }

        return false
    }

    private static let citationRegex = try? NSRegularExpression(pattern: "\\[S\\d+\\]")

    private func responseHasCitations(_ text: String) -> Bool {
        guard let regex = Self.citationRegex else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // MARK: - Model Management

    /// Update LLM service with optional fallback chain
    /// - Parameters:
    ///   - primary: The primary LLM service to use
    ///   - fallbacks: Optional array of fallback services to try if primary fails
    @MainActor
    func updateLLMService(_ primary: LLMService, fallbacks: [LLMService] = []) {
        _llmService = primary
        activeModelName = primary.modelName
        _fallbackServices = fallbacks
        #if os(macOS)
            configureMLXObserver(for: primary)
        #endif
        Log.info(
            "✓ Updated model: \(primary.modelName) with \(fallbacks.count) fallback(s)",
            category: .initialization
        )
    }

    /// Switch to a different LLM implementation
    /// Note: Use updateLLMService() for async/MainActor-safe switching
    func switchModel(to service: LLMService) async {
        await MainActor.run {
            self._llmService = service
            self.activeModelName = service.modelName
            Log.info("✓ Switched to model: \(service.modelName)", category: .initialization)
        }
    }

    /// Check if the current LLM is available
    var isLLMAvailable: Bool {
        llmService.isAvailable
    }

    var currentModelName: String {
        llmService.modelName
    }

    // MARK: - Apple Intelligence Feedback (iOS 26+)

    #if canImport(FoundationModels)
        /// Submit positive feedback for the last Apple Intelligence response
        /// This helps Apple improve model quality
        @available(iOS 26.0, *)
        func submitPositiveFeedback() {
            guard let fmService = _llmService as? AppleFoundationLLMService else {
                Log.debug("Feedback skipped: not using Apple Foundation Model", category: .llm)
                return
            }
            _ = fmService.submitPositiveFeedback()
            Log.info("✓ Positive feedback submitted to Apple Intelligence", category: .llm)
        }

        /// Submit negative feedback for the last Apple Intelligence response
        @available(iOS 26.0, *)
        func submitNegativeFeedback() {
            guard let fmService = _llmService as? AppleFoundationLLMService else {
                Log.debug("Feedback skipped: not using Apple Foundation Model", category: .llm)
                return
            }
            _ = fmService.submitNegativeFeedback()
            Log.info("✓ Negative feedback submitted to Apple Intelligence", category: .llm)
        }

        /// Check if feedback is available (using Apple Intelligence)
        var canSubmitFeedback: Bool {
            if #available(iOS 26.0, *) {
                return _llmService is AppleFoundationLLMService
            }
            return false
        }
    #endif

    // MARK: - Fallback-Aware Generation

    /// Try to generate with primary service, automatically falling back to configured fallbacks on failure
    private func generateWithFallback(
        prompt: String,
        context: String?,
        config: InferenceConfig,
        sourceChunks: [DocumentChunk] = []
    ) async throws -> LLMResponse {
        let upstreamHandler = LLMStreamingContext.handler

        func attempt(service: LLMService) async throws -> LLMResponse {
            let attemptStart = Date()

            actor StreamCapture {
                private var captured = ""
                private var firstChunkTime: TimeInterval?

                func record(_ event: LLMStreamEvent, since start: Date) {
                    guard !event.text.isEmpty else { return }
                    if firstChunkTime == nil {
                        firstChunkTime = Date().timeIntervalSince(start)
                    }
                    captured += event.text
                }

                func snapshot() -> (text: String, firstChunkTime: TimeInterval?) {
                    (captured, firstChunkTime)
                }
            }

            let streamCapture = StreamCapture()

            let capturingHandler: LLMStreamHandler = { event in
                await streamCapture.record(event, since: attemptStart)
                if let upstreamHandler {
                    await upstreamHandler(event)
                }
            }

            return try await LLMStreamingContext.$handler.withValue(capturingHandler) {
                do {
                    try await ensureCloudConsentIfNeeded(
                        service: service,
                        prompt: prompt,
                        context: context,
                        sourceChunks: sourceChunks,
                        allowPrivateCloudCompute: config.allowPrivateCloudCompute
                    )

                    let response = try await service.generate(
                        prompt: prompt,
                        context: context,
                        config: config
                    )

                    let (captured, firstChunkTime) = await streamCapture.snapshot()

                    let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let capturedTrimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty, !capturedTrimmed.isEmpty {
                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }
                        return LLMResponse(
                            text: capturedTrimmed,
                            tokensGenerated: capturedTrimmed.split(whereSeparator: { $0.isWhitespace }).count,
                            timeToFirstToken: response.timeToFirstToken ?? firstChunkTime,
                            totalTime: max(response.totalTime, Date().timeIntervalSince(attemptStart)),
                            modelName: response.modelName ?? service.modelName,
                            toolCallsMade: response.toolCallsMade
                        )
                    }

                    if LLMStreamingContext.handler != nil {
                        LLMStreamingContext.emit(text: "", isFinal: true)
                    }

                    return response
                } catch {
                    let (captured, firstChunkTime) = await streamCapture.snapshot()
                    let capturedTrimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
                    if capturedTrimmed.count >= 24 {
                        // If we already streamed a meaningful partial answer, do not replace it
                        // with a fallback provider.
                        Log.warning(
                            "\(service.modelName) failed after streaming partial output; returning partial response",
                            category: .llm
                        )
                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }
                        return LLMResponse(
                            text: capturedTrimmed,
                            tokensGenerated: capturedTrimmed.split(whereSeparator: { $0.isWhitespace }).count,
                            timeToFirstToken: firstChunkTime,
                            totalTime: Date().timeIntervalSince(attemptStart),
                            modelName: service.modelName,
                            toolCallsMade: 0
                        )
                    }
                    throw error
                }
            }
        }

        do {
            return try await attempt(service: _llmService)
        } catch {
            let errorDesc = error.localizedDescription

            // Check if it's a Jinja template error (common with some GGUF models)
            let isTemplateError = errorDesc.contains("Jinja") || errorDesc.contains("template")

            if isTemplateError {
                Log.warning(
                    "⚠️  \(_llmService.modelName) has a broken chat template (Jinja error)",
                    category: .llm
                )
                Log.info(
                    "💡 Tip: Try a different GGUF model (Qwen2.5, Llama-3.2, or Phi-3)",
                    category: .llm
                )
            } else {
                Log.warning(
                    "Primary model \(_llmService.modelName) failed: \(errorDesc)",
                    category: .llm
                )
            }

            // Try fallbacks in order
            for (index, fallbackService) in _fallbackServices.enumerated() {
                Log.info(
                    "Attempting fallback #\(index + 1): \(fallbackService.modelName)",
                    category: .llm
                )
                do {
                    let response = try await attempt(service: fallbackService)
                    Log.info(
                        "✓ Fallback #\(index + 1) succeeded: \(fallbackService.modelName)",
                        category: .llm
                    )
                    return response
                } catch {
                    Log.warning(
                        "Fallback #\(index + 1) failed: \(error.localizedDescription)",
                        category: .llm
                    )
                    continue
                }
            }

            // All fallbacks exhausted - provide helpful error message
            if isTemplateError {
                throw LLMError.generationFailed("""
                Model has incompatible chat template.
                Try: Settings → Primary Model → Select "Apple Intelligence" or "On-Device Analysis"
                """)
            }

            // Rethrow original error
            throw error
        }
    }

    /// Returns a configured service for the given settings key, if available.
    /// Simplified: only Apple Intelligence and On-Device Analysis are supported.
    private static func instantiateService(
        for modelKey: String,
        entitlementStore _: EntitlementStore?
    ) -> LLMService? {
        // Migrate deprecated model keys to supported types
        let effectiveKey = LLMModelType.isDeprecatedRawValue(modelKey) ? "apple_intelligence" : modelKey

        switch effectiveKey {
        case "apple_intelligence":
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    guard foundationService.isAvailable else {
                        Log.warning(
                            "Apple Foundation Models unavailable on this device",
                            category: .initialization
                        )
                        return nil
                    }
                    foundationService.startWarmup()
                    Log.info(
                        "✓ Using Apple Foundation Models (on-device + PCC)",
                        category: .initialization
                    )
                    Log.debug(
                        "🔥 Preloading model in background for instant first query",
                        category: .initialization
                    )
                    return foundationService
                } else {
                    Log.warning(
                        "Apple Intelligence requires iOS 26.0 or later", category: .initialization
                    )
                }
            #endif
            return nil
        case "on_device_analysis":
            Log.warning("on_device_analysis is deprecated; falling through to Apple Intelligence", category: .initialization)
            fallthrough
        default:
            // Unknown or deprecated model type - try Apple Intelligence
            Log.warning("Unknown or deprecated model type: \(modelKey); trying Apple Intelligence", category: .initialization)
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        foundationService.startWarmup()
                        return foundationService
                    }
                }
            #endif
            return nil
        }
    }

    /// Builds an ordered list of fallback services, excluding the user's primary selection.
    private static func buildFallbackChain(excluding modelKey: String) -> [LLMService] {
        var fallbacks: [LLMService] = []

        let capabilities = checkDeviceCapabilities()
        let appleCapable = capabilities.supportsAppleIntelligence || capabilities.supportsFoundationModels

        // Try Apple Intelligence first (if available and not primary)
        #if canImport(FoundationModels)
            if modelKey != "apple_intelligence" {
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        fallbacks.append(foundationService)
                        Log.debug("Added Apple Intelligence to fallback chain", category: .initialization)
                    }
                }
            }
        #endif

        // No additional fallbacks - Apple Intelligence is the only supported provider
        // If Apple Intelligence is unavailable, generation will fail with a clear error
        if !appleCapable {
            Log.warning("Device does not support Apple Intelligence - no fallbacks available", category: .initialization)
        }

        return fallbacks
    }

    /// Log structured query statistics for debugging and telemetry dashboards
    @MainActor
    private func logQueryStats(query: String, response: RAGResponse) async {
        let queryWords = wordCount(of: query)
        let responseWords = wordCount(of: response.generatedResponse)
        let chunkWordCounts = response.retrievedChunks.map { wordCount(of: $0.chunk.content) }
        let chunkWordTotal = chunkWordCounts.reduce(0, +)
        let averageChunkWords =
            chunkWordCounts.isEmpty
                ? 0.0
                : Double(chunkWordTotal) / Double(chunkWordCounts.count)

        var statsContent: [String] = [
            "Query: \(String(query.prefix(50)))… (≈\(queryWords) words)",
            "Chunks: \(response.retrievedChunks.count) (≈\(Int(averageChunkWords.rounded())) words avg)",
            "Retrieval: \(String(format: "%.2f", response.metadata.retrievalTime))s",
            "Generation: \(String(format: "%.2f", response.metadata.totalGenerationTime))s",
            "Response words: \(responseWords)",
            "Model: \(response.metadata.modelUsed)",
        ]

        if let ttft = response.metadata.timeToFirstToken {
            statsContent.append("Time to first token: \(String(format: "%.2f", ttft))s")
        }
        if let tps = response.metadata.tokensPerSecond {
            statsContent.append("Tokens per second: \(String(format: "%.1f", tps))")
        }

        Log.info("📊 RAG Query Statistics", category: .pipeline)
        for line in statsContent {
            Log.info("  • \(line)", category: .pipeline)
        }

        TelemetryCenter.emit(
            .system,
            title: "Query stats",
            metadata: [
                "queryWords": "\(queryWords)",
                "responseWords": "\(responseWords)",
                "chunkWords": "\(chunkWordTotal)",
                "chunkCount": "\(response.retrievedChunks.count)",
                "retrievalTime": String(format: "%.2f", response.metadata.retrievalTime),
                "generationTime": String(format: "%.2f", response.metadata.totalGenerationTime),
                "model": response.metadata.modelUsed,
            ]
        )
    }

    @MainActor
    private func recordRetrievalHistory(
        query: String,
        containerId: UUID,
        containerName: String,
        chunks: [RetrievedChunk]
    ) {
        guard !chunks.isEmpty else { return }
        let entry = RetrievalLogEntry(
            timestamp: Date(),
            query: query,
            containerId: containerId,
            containerName: containerName,
            chunks: chunks
        )
        retrievalHistory.append(entry)
        if retrievalHistory.count > retrievalHistoryLimit {
            retrievalHistory.removeFirst(retrievalHistory.count - retrievalHistoryLimit)
        }
    }

    private func finalizeResponse(
        query: String,
        containerId: UUID,
        containerName: String,
        response: RAGResponse
    ) async -> RAGResponse {
        await MainActor.run {
            self.recordRetrievalHistory(
                query: query,
                containerId: containerId,
                containerName: containerName,
                chunks: response.retrievedChunks
            )
        }
        await logQueryStats(query: query, response: response)
        return response
    }

    private nonisolated func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private nonisolated func isTrivialQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let tokenCount = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if tokenCount <= 1 {
            return true
        }

        let lower = trimmed.lowercased()
        let trivialSet: Set<String> = [
            "test",
            "help",
            "hello",
            "hi",
            "hey",
            "ok",
            "okay",
            "thanks",
            "thank you",
            "yes",
            "yep",
            "yeah",
        ]
        return trivialSet.contains(lower)
    }

    private func buildNeighborAwareFallback(
        seeds: [RetrievedChunk],
        pool: [RetrievedChunk],
        maxTotal: Int,
        neighborsPerSeed: Int = 1
    ) -> [RetrievedChunk] {
        guard !seeds.isEmpty else { return [] }
        let limit = max(1, maxTotal)

        var byDocument: [UUID: [RetrievedChunk]] = [:]
        for chunk in pool {
            byDocument[chunk.chunk.documentId, default: []].append(chunk)
        }
        for key in byDocument.keys {
            byDocument[key]?.sort { $0.chunk.metadata.chunkIndex < $1.chunk.metadata.chunkIndex }
        }

        var selected: [RetrievedChunk] = []
        var seenIds = Set<UUID>()

        func appendIfNeeded(_ chunk: RetrievedChunk) {
            if selected.count >= limit { return }
            let chunkId = chunk.chunk.id
            if seenIds.insert(chunkId).inserted {
                selected.append(chunk)
            }
        }

        for seed in seeds {
            appendIfNeeded(seed)
            guard selected.count < limit else { break }
            guard let docChunks = byDocument[seed.chunk.documentId],
                  let seedIndex = docChunks.firstIndex(where: { $0.chunk.id == seed.chunk.id })
            else {
                continue
            }

            if neighborsPerSeed > 0 {
                for offset in 1 ... neighborsPerSeed {
                    let prev = seedIndex - offset
                    if prev >= 0 {
                        appendIfNeeded(docChunks[prev])
                    }
                    let next = seedIndex + offset
                    if next < docChunks.count {
                        appendIfNeeded(docChunks[next])
                    }
                    if selected.count >= limit { break }
                }
            }
        }

        return selected
    }

    private func mergeUniqueChunks(
        _ primary: [RetrievedChunk],
        _ secondary: [RetrievedChunk]
    ) -> [RetrievedChunk] {
        var seen = Set<UUID>()
        var merged: [RetrievedChunk] = []
        merged.reserveCapacity(primary.count + secondary.count)

        for chunk in primary + secondary {
            if seen.insert(chunk.chunk.id).inserted {
                merged.append(chunk)
            }
        }
        return merged
    }

    private func extractQueryTerms(_ question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but",
            "is", "are", "was", "were", "be", "being",
            "of", "to", "for", "in", "on", "at", "by",
            "this", "that", "these", "those",
            "what", "whats", "what's", "how", "why", "when", "where",
            "i", "you", "we", "they", "it", "my", "your", "our", "their",
        ]
        return question
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func extractSnippet(from text: String, queryTerms: [String], maxChars: Int) -> String {
        if text.count <= maxChars { return text }
        if maxChars <= 0 { return "" }
        if !queryTerms.isEmpty {
            for term in queryTerms {
                if let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let half = maxChars / 2
                    let start = text.index(range.lowerBound, offsetBy: -half, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: half, limitedBy: text.endIndex) ?? text.endIndex
                    return String(text[start ..< end])
                }
            }
        }
        return String(text.prefix(maxChars))
    }

    private func buildExtractiveChunks(
        _ chunks: [RetrievedChunk],
        question: String,
        maxCharsPerChunk: Int
    ) -> [RetrievedChunk] {
        guard maxCharsPerChunk > 0 else { return chunks }
        let terms = extractQueryTerms(question)
        return chunks.map { retrieved in
            let content = extractSnippet(
                from: retrieved.chunk.content,
                queryTerms: terms,
                maxChars: maxCharsPerChunk
            )
            if content.count == retrieved.chunk.content.count {
                return retrieved
            }
            let trimmedChunk = DocumentChunk(
                id: retrieved.chunk.id,
                documentId: retrieved.chunk.documentId,
                content: content,
                embedding: retrieved.chunk.embedding,
                metadata: retrieved.chunk.metadata
            )
            return RetrievedChunk(
                chunk: trimmedChunk,
                similarityScore: retrieved.similarityScore,
                rank: retrieved.rank,
                sourceDocument: retrieved.sourceDocument,
                pageNumber: retrieved.pageNumber
            )
        }
    }

    private func buildEvidencePackContext(
        question: String,
        candidates: [RetrievedChunk],
        maxContextChars: Int,
        maxChunks: Int,
        maxCharsPerChunk: Int? = nil
    ) async -> (context: String, usedChunks: [RetrievedChunk]) {
        guard !candidates.isEmpty else { return ("", []) }

        var seen = Set<UUID>()
        let deduped = candidates.filter { seen.insert($0.chunk.id).inserted }
        let limited = Array(deduped.prefix(max(1, min(maxChunks, deduped.count))))
        let perChunk = maxCharsPerChunk
            ?? max(220, min(900, maxContextChars / max(1, limited.count)))

        let trimmed = buildExtractiveChunks(
            limited,
            question: question,
            maxCharsPerChunk: perChunk
        )

        let engine = RAGEngine()
        let (context, used) = await engine.assembleContext(
            chunks: trimmed,
            maxChars: maxContextChars,
            compact: true
        )
        let usedChunks = Array(trimmed.prefix(used))
        return (context, usedChunks)
    }

    /// Guarantee that at least a subset of the retrieved chunks span multiple documents when available.
    private func ensureDocumentCoverage(
        candidates: [RetrievedChunk],
        fallbackPool: [RetrievedChunk],
        desiredDocuments: Int,
        maxCandidates: Int
    ) -> (chunks: [RetrievedChunk], addedDocuments: Int) {
        let limit = max(1, maxCandidates)
        if desiredDocuments <= 1 {
            let baseline = candidates.isEmpty ? fallbackPool : candidates
            return (Array(baseline.prefix(limit)), 0)
        }

        var augmented = candidates
        if augmented.count > limit {
            augmented = Array(augmented.prefix(limit))
        }

        var seenDocuments = Set(augmented.map { $0.chunk.documentId })
        var addedDocs = 0

        for candidate in fallbackPool {
            if augmented.count >= limit { break }
            let docId = candidate.chunk.documentId
            if seenDocuments.contains(docId) { continue }
            augmented.append(candidate)
            seenDocuments.insert(docId)
            addedDocs += 1
            if seenDocuments.count >= desiredDocuments { break }
        }

        if augmented.isEmpty {
            let fallback = Array(fallbackPool.prefix(limit))
            let coveredDocs = Set(fallback.map { $0.chunk.documentId }).count
            return (fallback, min(desiredDocuments, coveredDocs))
        }

        return (augmented, addedDocs)
    }

    // MARK: - MainActor snapshot helpers (async to avoid superfluous await warnings)

    private nonisolated func snapshotDocuments() async -> [Document] {
        await MainActor.run { self.documents }
    }

    private nonisolated func snapshotDocumentsCount() async -> Int {
        await MainActor.run { self.documents.count }
    }

    private nonisolated func documentName(for documentId: UUID) async -> String {
        await MainActor.run { self.getDocumentName(for: documentId) }
    }

    /// Run an async operation under a temporary query-scoped container context.
    /// Sets currentQueryContainerId for the duration of the operation so agentic tools
    /// like listDocuments/searchDocuments are scoped deterministically in diagnostics.
    func withQueryContainerContext<T>(
        containerId: UUID?,
        warmup: Bool = true,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        // Resolve selected container id (override or active)
        let selectedId: UUID = await MainActor.run {
            containerId ?? self.containerService.activeContainerId
        }
        // Establish context
        await MainActor.run { self.currentQueryContainerId = selectedId }
        // Optional warmup to ensure DB loaded (avoids first-touch latency)
        if warmup {
            let _ = try? await dbFor(selectedId).count()
        }
        // Ensure cleanup
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }
        // Execute caller's operation
        return try await operation()
    }

    // MARK: - Response Quality Assessment

    /// Calculate confidence score and identify quality warnings
    /// Critical for medical/high-stakes information retrieval
    /// - Parameters:
    ///   - chunks: Retrieved chunks for this response
    ///   - query: Original user query
    /// - Returns: Tuple of (confidence score 0-1, array of warnings)
    @MainActor
    private func assessResponseQuality(
        chunks: [RetrievedChunk],
        query: String
    ) -> (Float, [String]) {
        var warnings: [String] = []

        // Factor 1: Semantic similarity of top chunks
        let topSimilarity = chunks.first?.similarityScore ?? 0

        if topSimilarity < 0.4 {
            warnings.append(
                "Low relevance: Best match only \(String(format: "%.1f", topSimilarity * 100))% similar"
            )
        } else if topSimilarity < 0.6 {
            warnings.append("Moderate relevance: Consider rephrasing query for better results")
        }

        // Factor 2: Number of supporting chunks
        let chunkCount = chunks.count
        if chunkCount < 3 {
            warnings.append("Limited context: Only \(chunkCount) relevant chunks found")
        }

        // Factor 3: Source diversity (multiple documents = higher confidence)
        let uniqueSources = Set(chunks.map { $0.sourceDocument })
        let sourceCount = uniqueSources.count

        if sourceCount == 1, documents.count > 1 {
            warnings.append("Single source: Information from only one document")
        }

        // Factor 4: Query quality
        let queryWords = query.split(separator: " ").count
        if queryWords <= 2 {
            warnings.append("Generic query: Try more specific questions for better accuracy")
        }

        // Calculate aggregate confidence (weighted average)
        let similarityWeight: Float = 0.5
        let chunkCountWeight: Float = 0.2
        let sourceDiversityWeight: Float = 0.2
        let queryQualityWeight: Float = 0.1

        let similarityScore = min(topSimilarity / 0.8, 1.0) // Normalize: 0.8+ = full confidence
        let chunkScore = min(Float(chunkCount) / 5.0, 1.0) // 5+ chunks = full confidence
        let diversityScore = min(Float(sourceCount) / Float(max(documents.count, 1)), 1.0)
        let queryScore = min(Float(queryWords) / 5.0, 1.0) // 5+ words = full confidence

        let confidence =
            (similarityScore * similarityWeight + chunkScore * chunkCountWeight + diversityScore
                * sourceDiversityWeight + queryScore * queryQualityWeight)

        return (confidence, warnings)
    }

    // MARK: - MMR (Maximal Marginal Relevance) for Diversity
}

// MARK: - Device Capability Detection

extension RAGService {
    /// Comprehensive device capability detection for Apple Intelligence ecosystem
    @MainActor
    static func checkDeviceCapabilities() -> DeviceCapabilities {
        var capabilities = DeviceCapabilities()

        // Get iOS version
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
        capabilities.iOSVersion =
            "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        capabilities.iOSMajor = systemVersion.majorVersion
        capabilities.iOSMinor = systemVersion.minorVersion
        let hasAppleIntelligenceOS =
            (systemVersion.majorVersion > 18)
                || (systemVersion.majorVersion == 18 && systemVersion.minorVersion >= 1)

        // Detect device/chip tier based on available features
        // This is an approximation since we can't directly query chip model
        capabilities.deviceChip = detectDeviceChip()

        // Check Apple Intelligence availability (requires A17 Pro+/M-series + iOS 18.1+)
        #if canImport(FoundationModels)
            if #available(iOS 18.0, *) {
                // iOS 18.0+ with Foundation Models capability check
                #if targetEnvironment(simulator)
                    // Simulator: Foundation Models not available
                    capabilities.supportsFoundationModels = false
                    capabilities.foundationModelUnavailableReason =
                        "Foundation Models not available in Simulator"
                    capabilities.supportsAppleIntelligence = false
                    capabilities.appleIntelligenceUnavailableReason = "Not available in Simulator"
                    Log.info("  Running in Simulator - Foundation Models unavailable")
                #else
                    // Real device: Check Foundation Models availability
                    // SystemLanguageModel.default must be accessed synchronously on main thread
                    guard Thread.isMainThread else {
                        // Fallback: not on main thread
                        capabilities.supportsFoundationModels = false
                        capabilities.foundationModelUnavailableReason =
                            "Internal error: not called from main thread"
                        capabilities.supportsAppleIntelligence = false
                        capabilities.appleIntelligenceUnavailableReason =
                            "Internal error: not called from main thread"
                        Log.error(" checkDeviceCapabilities() not called from main thread")

                        // Skip Foundation Models check, continue with rest
                        capabilities.supportsPrivateCloudCompute = false
                        capabilities.supportsWritingTools = false
                        capabilities.supportsImagePlayground = false

                        // Jump to post-Foundation Models setup
                        if hasAppleIntelligenceOS {
                            capabilities.supportsAppleIntelligence =
                                capabilities.deviceChip.supportsAppleIntelligence
                            capabilities.supportsPrivateCloudCompute = true
                            capabilities.supportsWritingTools = true
                            capabilities.supportsImagePlayground =
                                capabilities.deviceChip.supportsAppleIntelligence
                            if !capabilities.supportsAppleIntelligence {
                                capabilities.appleIntelligenceUnavailableReason =
                                    "Requires A17 Pro+ or M-series"
                            }
                        }

                        // Skip to embedding check
                        capabilities.supportsEmbeddings = true
                        capabilities.supportsCoreML = true
                        capabilities.supportsAppIntents = true
                        capabilities.supportsVision = true
                        capabilities.supportsVisionKit = true
                        capabilities.deviceTier = determineDeviceTier(
                            chip: capabilities.deviceChip,
                            hasAppleIntelligence: capabilities.supportsAppleIntelligence,
                            hasEmbeddings: capabilities.supportsEmbeddings
                        )
                        return capabilities
                    }

                    let systemModel = SystemLanguageModel.default

                    switch systemModel.availability {
                    case .available:
                        capabilities.supportsFoundationModels = true
                        capabilities.foundationModelUnavailableReason = nil
                        capabilities.supportsAppleIntelligence = true
                        capabilities.appleIntelligenceUnavailableReason = nil
                        Log.info(" Foundation Models available on device")

                    case let .unavailable(reason):
                        capabilities.supportsFoundationModels = false
                        capabilities.supportsAppleIntelligence = false

                        switch reason {
                        case .deviceNotEligible:
                            let message = "Device not eligible (requires A17 Pro+ or M-series)"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            Log.error(" Device not eligible for Foundation Models")

                        case .appleIntelligenceNotEnabled:
                            let message =
                                "Apple Intelligence not enabled - go to Settings > Apple Intelligence & Siri"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            Log.warning("  Apple Intelligence not enabled in Settings")
                            Log.info("   💡 Go to Settings > Apple Intelligence & Siri to enable")

                        case .modelNotReady:
                            let message = "Model downloading or initializing - check iPhone Storage"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            Log.info(" Foundation Models not ready (downloading or initializing)")
                            Log.info("   💡 Check Settings > General > iPhone Storage for download progress")

                        @unknown default:
                            let message = "Foundation Models unavailable (unknown reason)"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            Log.error(" Foundation Models unavailable (unknown reason)")
                        }
                    }
                #endif

                // iOS 26 includes all iOS 18.1+ features
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
            } else if hasAppleIntelligenceOS {
                // iOS 18.1+ has Apple Intelligence (PCC, Writing Tools, ChatGPT)
                // but no Foundation Models yet
                capabilities.supportsAppleIntelligence =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.foundationModelUnavailableReason = "Requires iOS 26"
                if !capabilities.supportsAppleIntelligence {
                    capabilities.appleIntelligenceUnavailableReason =
                        "Requires A17 Pro+ or M-series"
                }
            } else {
                capabilities.foundationModelUnavailableReason = "Requires iOS 26"
                capabilities.appleIntelligenceUnavailableReason = "Requires iOS 18.1+"
            }
        #else
            if hasAppleIntelligenceOS {
                capabilities.supportsAppleIntelligence =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.foundationModelUnavailableReason = "Build with iOS 26 SDK to enable"
                if !capabilities.supportsAppleIntelligence {
                    capabilities.appleIntelligenceUnavailableReason =
                        "Requires A17 Pro+ or M-series"
                }
            } else {
                capabilities.foundationModelUnavailableReason = "Build with iOS 26 SDK to enable"
                capabilities.appleIntelligenceUnavailableReason = "Requires iOS 18.1+"
            }
        #endif

        // Check NaturalLanguage embedding support
        // NLEmbedding is available on iOS 13+, so we can assume it's available
        // Rather than risk crashing by initializing the model here
        capabilities.supportsEmbeddings = true

        // Core ML is always available
        capabilities.supportsCoreML = true

        // App Intents (Siri) available on all iOS versions
        capabilities.supportsAppIntents = true

        // Vision framework available on all devices
        capabilities.supportsVision = true

        // VisionKit (document scanning) available on all devices
        capabilities.supportsVisionKit = true

        // Determine device tier
        capabilities.deviceTier = determineDeviceTier(
            chip: capabilities.deviceChip,
            hasAppleIntelligence: capabilities.supportsAppleIntelligence,
            hasEmbeddings: capabilities.supportsEmbeddings
        )

        // Note: canRunRAG is a computed property based on supportsEmbeddings

        return capabilities
    }

    /// Detect device chip based on available features
    private static func detectDeviceChip() -> DeviceChip {
        // Check for Neural Engine and performance characteristics
        // This is an approximation - we can't directly query the chip model in iOS

        // Simulator gets conservative capabilities to avoid crashes
        #if targetEnvironment(simulator)
            return .a14Bionic // Don't claim Apple Intelligence support in simulator
        #else

            var systemInfo = utsname()
            guard uname(&systemInfo) == 0 else {
                // If uname fails, return conservative fallback
                return .a14Bionic
            }

            let modelCode = withUnsafeBytes(of: &systemInfo.machine) { bytes -> String? in
                guard let cString = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                    return nil
                }
                return String(cString: cString)
            }

            let identifier = modelCode ?? "unknown"

            // iPhone identifiers
            if identifier.hasPrefix("iPhone") {
                let components = identifier.split(separator: ",")
                let family = components.first.map(String.init) ?? "iPhone"
                let variant = components.count > 1 ? String(components[1]) : ""
                switch family {
                case "iPhone17":
                    // iPhone 16 line (2024) – Pro models run A18 Pro, non-Pro run A18
                    if ["1", "2"].contains(variant) {
                        return .a18Pro
                    } else {
                        return .a18
                    }
                case "iPhone16":
                    // iPhone 15 line (2023) – Pro models run A17 Pro, non-Pro run A16
                    if ["1", "2"].contains(variant) {
                        return .a17Pro
                    } else {
                        return .a16Bionic
                    }
                case "iPhone15":
                    // iPhone 14 line (2022) – Pro models run A16, standard models run A15
                    if ["2", "3"].contains(variant) {
                        return .a16Bionic
                    } else {
                        return .a15Bionic
                    }
                case "iPhone14":
                    return .a15Bionic
                case "iPhone13":
                    return .a14Bionic
                case "iPhone12":
                    return .a13Bionic
                default:
                    return .older
                }
            }

            // iPad identifiers
            if identifier.hasPrefix("iPad") {
                if identifier.contains("iPad16") || identifier.contains("iPad17") {
                    return .mSeries
                } else if identifier.contains("iPad15") {
                    return .a17Pro
                } else if identifier.contains("iPad14") || identifier.contains("iPad13") {
                    return .a16Bionic
                } else {
                    return .a14Bionic
                }
            }

            // Mac identifiers (Mac Catalyst)
            if identifier.contains("Mac") || identifier.contains("x86")
                || identifier.contains("arm64")
            {
                return .mSeries
            }

            // Conservative fallback for devices we don't recognize
            return .a14Bionic
        #endif
    }

    /// Determine device performance tier
    private static func determineDeviceTier(
        chip: DeviceChip, hasAppleIntelligence: Bool, hasEmbeddings: Bool
    ) -> DeviceCapabilities.DeviceTier {
        if hasAppleIntelligence && chip.supportsAppleIntelligence {
            return .high // A17 Pro+ or M-series with full Apple Intelligence
        } else if hasEmbeddings {
            return .medium // A13+ with embedding support
        } else {
            return .low // Older devices
        }
    }
}

// MARK: - Device Chip Detection

enum DeviceChip: String {
    case mSeries = "Apple Silicon (M1+)"
    case a18Pro = "A18 Pro"
    case a18 = "A18"
    case a17Pro = "A17 Pro"
    case a17 = "A17"
    case a16Bionic = "A16 Bionic"
    case a15Bionic = "A15 Bionic"
    case a14Bionic = "A14 Bionic"
    case a13Bionic = "A13 Bionic"
    case older = "A12 or Older"

    var supportsAppleIntelligence: Bool {
        switch self {
        case .mSeries, .a18Pro, .a18, .a17Pro:
            return true
        default:
            return false
        }
    }

    var supportsNeuralEngine: Bool {
        // A11+ has Neural Engine
        return self != .older
    }

    var performanceRating: String {
        switch self {
        case .mSeries:
            return "Exceptional"
        case .a18Pro:
            return "Elite"
        case .a18:
            return "Very Good"
        case .a17Pro:
            return "Excellent"
        case .a17:
            return "Very Good"
        case .a16Bionic:
            return "Very Good"
        case .a15Bionic, .a14Bionic:
            return "Good"
        case .a13Bionic:
            return "Moderate"
        case .older:
            return "Limited"
        }
    }

    var neuralEnginePerformance: String {
        switch self {
        case .mSeries:
            return "16-core, 15.8 TOPS"
        case .a18Pro:
            return "16-core, 45 TOPS"
        case .a18:
            return "16-core, 20 TOPS"
        case .a17Pro:
            return "16-core, 35 TOPS"
        case .a17:
            return "16-core, 18 TOPS"
        case .a16Bionic:
            return "16-core, 17 TOPS"
        case .a15Bionic:
            return "16-core, 15.8 TOPS"
        case .a14Bionic:
            return "16-core, 11 TOPS"
        case .a13Bionic:
            return "8-core, 6 TOPS"
        case .older:
            return "Not available"
        }
    }
}

// MARK: - Device Capabilities Structure

struct DeviceCapabilities {
    // Device Information
    var deviceChip: DeviceChip = .a14Bionic
    var iOSVersion: String = "Unknown"
    var iOSMajor: Int = 0
    var iOSMinor: Int = 0

    // Apple Intelligence Features (iOS 18.1+)
    var supportsAppleIntelligence = false
    var supportsPrivateCloudCompute = false
    var supportsWritingTools = false
    var supportsImagePlayground = false
    var appleIntelligenceUnavailableReason: String? = nil

    // Foundation Models (iOS 26.0+)
    var supportsFoundationModels = false
    var foundationModelUnavailableReason: String? = nil

    // Core AI Frameworks
    var supportsEmbeddings = false
    var supportsCoreML = false
    var supportsAppIntents = false
    var supportsVision = false
    var supportsVisionKit = false

    // Hardware Features
    var hasNeuralEngine: Bool {
        return deviceChip.supportsNeuralEngine
    }

    // Computed Properties
    var deviceTier: DeviceTier = .low

    /// Estimated maximum context tokens Apple Intelligence can allocate on this hardware
    /// - Returns ≈65K tokens once Foundation Models are active (PCC available)
    /// - Returns 4,096 tokens for on-device-only execution while models download
    var appleIntelligenceContextTokens: Int {
        if supportsFoundationModels {
            return 65000
        } else if supportsAppleIntelligence {
            return 4096
        } else {
            return 0
        }
    }

    /// Human-readable summary of the Apple Intelligence context behaviour for this device
    var appleIntelligenceContextDescription: String? {
        if supportsFoundationModels {
            return
                "≈4,096 tokens on-device, automatically expanding to ≈65K tokens via Private Cloud Compute when queries demand it."
        } else if supportsAppleIntelligence {
            return
                "≈4,096 tokens handled fully on-device while Foundation Models finish downloading."
        } else {
            return nil
        }
    }

    var canRunRAG: Bool { supportsEmbeddings }

    var canRunAdvancedAI: Bool { supportsAppleIntelligence || supportsFoundationModels }

    var appleIntelligenceStatus: String {
        if supportsFoundationModels {
            return "Foundation Models Available"
        } else if supportsAppleIntelligence {
            return "Apple Intelligence Available"
        } else if let reason = appleIntelligenceUnavailableReason {
            return reason
        } else if iOSMajor >= 18 {
            return "Requires A17 Pro+ or M-series"
        } else {
            return "Requires iOS 18.1+"
        }
    }

    enum DeviceTier {
        case low // Pre-A13, minimal AI support
        case medium // A13-A16, embeddings + Core ML
        case high // A17 Pro+ or M-series, full Apple Intelligence

        var description: String {
            switch self {
            case .high:
                return "Premium (Full AI Capabilities)"
            case .medium:
                return "Standard (Good AI Support)"
            case .low:
                return "Basic (Limited AI Support)"
            }
        }

        var color: String {
            switch self {
            case .high:
                return "green"
            case .medium:
                return "blue"
            case .low:
                return "orange"
            }
        }
    }
}

// MARK: - Errors

enum RAGServiceError: LocalizedError {
    case emptyQuery
    case noDocumentsAvailable
    case retrievalFailed
    case modelNotAvailable
    case noRelevantContext
    case cloudConsentDenied(provider: CloudProvider)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Query cannot be empty"
        case .noDocumentsAvailable:
            return "No documents have been added to the knowledge base"
        case .noRelevantContext:
            return "No relevant information found in documents. Try rephrasing your query."
        case .retrievalFailed:
            return "Failed to retrieve relevant chunks"
        case .modelNotAvailable:
            return "The selected LLM model is not available"
        case let .cloudConsentDenied(provider):
            return "Cloud transmission denied for \(provider.shortName)"
        }
    }
}

// MARK: - RAGService Tool Handler Implementation

// This enables agentic RAG where the LLM can decide when to search documents

extension RAGService: RAGToolHandler {
    /// Search documents for relevant information
    /// Called by the LLM when it needs information from the document library
    func searchDocuments(query: String) async throws -> String {
        Log.debug(" [Tool Call] search_documents(query: \"\(query)\")")

        // Use the existing RAG pipeline to search
        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: query)

        let db = await dbFor(embeddingContext.containerId)

        let retrievedChunks = try await db.search(
            embedding: queryEmbedding,
            topK: 3 // Return top 3 chunks for tool call
        )

        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Format retrieved chunks for LLM consumption
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"

        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview // Truncated preview to control token usage
            result += "\n\n"
        }

        Log.info(" [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// Agentic search with optional topK and minSimilarity (called by Function Calling)
    func searchDocuments(query: String, topK: Int?, minSimilarity: Float?) async throws -> String {
        Log.debug("[Tool Call] search_documents(query: \"\(query)\", topK: \(topK?.description ?? "nil"), minSimilarity: \(minSimilarity?.description ?? "nil"))")

        // Step 1: Embed the query using the container's provider/dimension
        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: query)

        // Step 2: Vector search with optional k
        let k = max(1, topK ?? 3)
        let db = await dbFor(embeddingContext.containerId)
        var retrievedChunks = try await db.search(
            embedding: queryEmbedding,
            topK: k
        )

        // Step 3: Optional similarity filtering
        if let minSim = minSimilarity {
            let engine = RAGEngine()
            retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: minSim)
        }

        // Edge case: No results
        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Step 4: Format retrieved chunks for LLM consumption (citations + preview)
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"
        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview
            result += "\n\n"
        }

        Log.info(" [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// List all available documents
    /// Called by the LLM when user asks what documents are available
    func listDocuments() async throws -> String {
        Log.debug(" [Tool Call] list_documents()")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        if scopedDocs.isEmpty {
            return "No documents available in the selected library."
        }

        var result = "Available documents (\(scopedDocs.count)):\n\n"

        for (index, doc) in scopedDocs.enumerated() {
            result += "\(index + 1). \(doc.filename)\n"
            if let pages = doc.processingMetadata?.pagesProcessed {
                result += "   - Pages: \(pages)\n"
            }
            result += "   - Chunks: \(doc.totalChunks)\n"
            result += "   - Added: \(formatDate(doc.addedAt))\n"
            result += "\n"
        }

        Log.info(" [Tool Call] Listed \(scopedDocs.count) documents (scoped)")
        return result
    }

    /// Get summary of a specific document
    /// Called by the LLM when user asks about a specific document
    func getDocumentSummary(documentName: String) async throws -> String {
        Log.debug(" [Tool Call] get_document_summary(documentName: \"\(documentName)\")")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { d in
            if let cid = d.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        guard
            let doc = scopedDocs.first(where: {
                $0.filename.lowercased().contains(documentName.lowercased())
            })
        else {
            return "Document not found in selected library: \(documentName)"
        }

        var result = "Document: \(doc.filename)\n"
        if let pages = doc.processingMetadata?.pagesProcessed {
            result += "- Pages: \(pages)\n"
        }
        result += "- Chunks: \(doc.totalChunks)\n"
        result += "- Added: \(formatDate(doc.addedAt))\n"
        result += "- File Type: \(doc.contentType.rawValue)"

        Log.info(" [Tool Call] Returned summary for \(doc.filename) (scoped)")
        return result
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
