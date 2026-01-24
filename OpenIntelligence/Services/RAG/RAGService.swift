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
    let qualityModeName: String // Changed from RAGQualityMode enum to String
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

    // Recursive RAG metrics (for Deep Think / agentic mode)
    /// Whether this used recursive RAG (multiple small calls instead of one large call)
    let isRecursiveRAG: Bool
    /// Total tokens used across ALL LLM calls in recursive mode
    let totalTokensAcrossCalls: Int
    /// Number of individual LLM calls made
    let llmCallCount: Int

    // Default values for non-recursive mode
    init(
        timestamp: Date,
        query: String,
        containerId: UUID,
        containerName: String,
        embeddingProviderId: String,
        embeddingDim: Int,
        vectorDBKind: VectorDBKind,
        chunkingTargetWords: Int,
        chunkingOverlapWords: Int,
        chunkingSource: String,
        qualityModeName: String,
        retrievalConfig: RetrievalConfig,
        lenientRetrieval: Bool,
        dynamicMin: Float,
        topSim: Float,
        secondSim: Float,
        avgTop5: Float,
        acceptanceOverride: Bool,
        totalStoredChunks: Int,
        candidatesCount: Int,
        rerankedCount: Int,
        filteredCount: Int,
        droppedCount: Int,
        mmrSelectedCount: Int,
        uniqueDocCount: Int,
        contextStrategy: String,
        contextChars: Int,
        contextWords: Int,
        contextChunksUsed: Int,
        maxContextChars: Int,
        baseWindowTokens: Int,
        safetyTokens: Int,
        promptOverheadTokens: Int,
        questionTokens: Int,
        reservedOutputTokens: Int,
        availableContextTokens: Int,
        executionContext: ExecutionContext,
        allowPrivateCloudCompute: Bool,
        networkConnected: Bool,
        wantsCloudContext: Bool,
        reliabilityModeEnabled: Bool,
        allowUngroundedFallback: Bool,
        modelName: String,
        isRecursiveRAG: Bool = false,
        totalTokensAcrossCalls: Int = 0,
        llmCallCount: Int = 1
    ) {
        self.timestamp = timestamp
        self.query = query
        self.containerId = containerId
        self.containerName = containerName
        self.embeddingProviderId = embeddingProviderId
        self.embeddingDim = embeddingDim
        self.vectorDBKind = vectorDBKind
        self.chunkingTargetWords = chunkingTargetWords
        self.chunkingOverlapWords = chunkingOverlapWords
        self.chunkingSource = chunkingSource
        self.qualityModeName = qualityModeName
        self.retrievalConfig = retrievalConfig
        self.lenientRetrieval = lenientRetrieval
        self.dynamicMin = dynamicMin
        self.topSim = topSim
        self.secondSim = secondSim
        self.avgTop5 = avgTop5
        self.acceptanceOverride = acceptanceOverride
        self.totalStoredChunks = totalStoredChunks
        self.candidatesCount = candidatesCount
        self.rerankedCount = rerankedCount
        self.filteredCount = filteredCount
        self.droppedCount = droppedCount
        self.mmrSelectedCount = mmrSelectedCount
        self.uniqueDocCount = uniqueDocCount
        self.contextStrategy = contextStrategy
        self.contextChars = contextChars
        self.contextWords = contextWords
        self.contextChunksUsed = contextChunksUsed
        self.maxContextChars = maxContextChars
        self.baseWindowTokens = baseWindowTokens
        self.safetyTokens = safetyTokens
        self.promptOverheadTokens = promptOverheadTokens
        self.questionTokens = questionTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.availableContextTokens = availableContextTokens
        self.executionContext = executionContext
        self.allowPrivateCloudCompute = allowPrivateCloudCompute
        self.networkConnected = networkConnected
        self.wantsCloudContext = wantsCloudContext
        self.reliabilityModeEnabled = reliabilityModeEnabled
        self.allowUngroundedFallback = allowUngroundedFallback
        self.modelName = modelName
        self.isRecursiveRAG = isRecursiveRAG
        self.totalTokensAcrossCalls = totalTokensAcrossCalls
        self.llmCallCount = llmCallCount
    }
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
    case onboarding // Initial sample import - skip self-tuning

    var allowsSelfTuningScheduling: Bool {
        switch self {
        case .userInitiated:
            return true
        case .autoRebuild, .onboarding:
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
    private let documentSummaryService: DocumentSummaryService
    private let queryRouter = QueryRouterService()
    private let verificationGateService = VerificationGateService()
    private let graphIndexService = GraphIndexService()
    private let contextPackingService: ContextPackingService
    private let confidenceCalibrationService = ConfidenceCalibrationService()
    private let extractiveSummarizationService: ExtractiveSummarizationService
    private let specificationExtractor = SpecificationExtractor()
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
        corpusVocabularyCache.removeValue(forKey: containerId)
        Log.info("[RAGService] Cleared intelligence and vocabulary cache for container \(containerId)", category: .retrieval)
    }

    /// Recompute the intelligence snapshot for a container on demand.
    @discardableResult
    func refreshIntelligence(for containerId: UUID? = nil, force: Bool = false) -> Task<Void, Never> {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            // Invalidate vocabulary cache when refreshing intelligence (documents may have changed)
            await MainActor.run {
                let targetId = containerId ?? self.containerService.activeContainerId
                self.corpusVocabularyCache.removeValue(forKey: targetId)
            }
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

    /// Maximum messages to retain per container to prevent unbounded memory/disk growth.
    /// With an average of ~500 chars per message, 200 messages ≈ 100KB per container.
    private static let maxMessagesPerContainer = 200

    /// Persists chat history for a container and updates the in-memory cache.
    /// Automatically trims to `maxMessagesPerContainer` to prevent runaway growth.
    @MainActor
    func persistChatHistory(_ messages: [ChatMessage], for containerId: UUID?) {
        let resolvedId = containerId ?? containerService.activeContainerId
        // Trim to max capacity, keeping most recent messages
        let trimmedMessages = messages.count > Self.maxMessagesPerContainer
            ? Array(messages.suffix(Self.maxMessagesPerContainer))
            : messages
        chatHistories[resolvedId] = trimmedMessages
        saveChatHistory(trimmedMessages, for: resolvedId)
    }

    /// Clears chat history for a container both in memory and on disk.
    @MainActor
    func clearChatHistory(for containerId: UUID?) {
        let resolvedId = containerId ?? containerService.activeContainerId
        chatHistories[resolvedId] = []
        saveChatHistory([], for: resolvedId)

        // Reset Deep Think / Maximum mode live metrics to avoid stale UI
        resetDeepThinkLiveMetrics()

        // Also clear the persisted transcript and conversation memory when clearing chat history
        if #available(iOS 26.0, *) {
            TranscriptPersistenceService.shared.deleteTranscript(for: resolvedId)
            ConversationMemoryService.shared.clearMemory(for: resolvedId)
            Log.debug("[RAGService] Cleared chat history, transcript, memory, and live metrics for container \(resolvedId)", category: .initialization)
        }
    }

    /// Resets Deep Think / Maximum mode live metrics to prevent stale state in UI.
    /// Call this when:
    /// - Chat is cleared
    /// - Mode is switched between Standard / Deep Think / Maximum
    /// - Container is changed
    @MainActor
    func resetDeepThinkLiveMetrics() {
        deepThinkLiveTokens = 0
        deepThinkLiveSteps = 0
        deepThinkLiveConfidence = 0
        lastAuditSnapshot = nil
        thinkingEvents.removeAll()
        Log.debug("[RAGService] Reset Deep Think live metrics and audit snapshot", category: .llm)
    }

    // MARK: - Transcript Persistence (iOS 26+)

    /// Save the current LLM session transcript to disk for later restoration.
    ///
    /// Call this when:
    /// - App enters background
    /// - User switches containers
    /// - After completing a conversation turn
    ///
    /// - Parameter containerId: The container to save transcript for (defaults to active container)
    @MainActor
    func saveSessionTranscript(for containerId: UUID? = nil) {
        guard #available(iOS 26.0, *) else { return }

        let resolvedId = containerId ?? containerService.activeContainerId

        // Get the current LLM service - must be AppleFoundationLLMService
        guard let appleFMService = llmService as? AppleFoundationLLMService,
              let transcript = appleFMService.transcript
        else {
            Log.debug("[RAGService] No transcript to save (service unavailable or no session)", category: .llm)
            return
        }

        TranscriptPersistenceService.shared.saveTranscriptTrimmed(transcript, for: resolvedId)
    }

    /// Restore a previously saved transcript to enable conversation continuity.
    ///
    /// Call this when:
    /// - App enters foreground
    /// - User switches to a container
    /// - At app launch for the active container
    ///
    /// - Parameter containerId: The container to restore transcript for (defaults to active container)
    /// - Returns: `true` if a transcript was restored successfully
    @MainActor
    @discardableResult
    func restoreSessionTranscript(for containerId: UUID? = nil) -> Bool {
        guard #available(iOS 26.0, *) else { return false }

        let resolvedId = containerId ?? containerService.activeContainerId

        // Get the current LLM service - must be AppleFoundationLLMService
        guard let appleFMService = llmService as? AppleFoundationLLMService else {
            Log.debug("[RAGService] Cannot restore transcript (AppleFMService unavailable)", category: .llm)
            return false
        }

        // Load saved transcript
        guard let savedTranscript = TranscriptPersistenceService.shared.loadTranscript(for: resolvedId) else {
            return false
        }

        // Queue the transcript for restoration on next session creation
        return appleFMService.restoreFromTranscript(savedTranscript)
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

    /// Tracks whether the last query used agentic (deep) mode or single-pass.
    /// Used by UI to show "Go Deeper" button when single-pass was used.
    @MainActor @Published private(set) var lastQueryUsedAgentic: Bool = false

    /// The last query text, for re-querying with forced agentic mode.
    @MainActor private(set) var lastQueryText: String? = nil

    /// Forces the next query to use agentic mode regardless of complexity detection.
    @MainActor var forceAgenticOnNextQuery: Bool = false

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

    /// Live token counter for Deep Think mode - updates in real-time as each step completes
    @MainActor @Published private(set) var deepThinkLiveTokens: Int = 0
    /// Live step counter for Deep Think mode - updates in real-time
    @MainActor @Published private(set) var deepThinkLiveSteps: Int = 0
    /// Live confidence meter for Maximum mode - updates as reasoning progresses toward 98%
    @MainActor @Published private(set) var deepThinkLiveConfidence: Float = 0

    /// Cached corpus vocabulary per container to avoid expensive rebuilds on each query
    @MainActor private var corpusVocabularyCache: [UUID: CorpusVocabulary] = [:]

    /// Published model name for UI binding - updates when LLM service changes
    @MainActor @Published private(set) var activeModelName: String = "Loading..."
    @MainActor private var selfTuningInFlight: Set<UUID> = []

    // MARK: - Real-time Generation State (iOS 26+)

    /// Whether the LLM session is currently generating a response.
    ///
    /// This reflects the actual FoundationModels `session.isResponding` state,
    /// providing real-time feedback for UI indicators during streaming.
    ///
    /// Use this for:
    /// - Showing accurate "typing" indicators in chat
    /// - Disabling input controls during active generation
    /// - Real-time progress animations
    ///
    /// Falls back to `false` on pre-iOS 26 devices or when using non-Apple LLM services.
    @MainActor
    var isLLMResponding: Bool {
        guard #available(iOS 26.0, *) else { return false }
        guard let appleFMService = llmService as? AppleFoundationLLMService else { return false }
        return appleFMService.isResponding
    }

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
        static let targetWindow = 350 // Larger chunks = more context per chunk
        static let overlap = 60 // ~17% overlap - sufficient without redundancy
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

        // Initialize document summary service for RAPTOR-lite
        self.documentSummaryService = DocumentSummaryService()

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

        // Initialize context packing with graph index
        self.contextPackingService = ContextPackingService(graphIndex: self.graphIndexService)

        // Initialize extractive summarization with embedding service
        self.extractiveSummarizationService = ExtractiveSummarizationService(embeddingService: self.embeddingService)

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
                // No LLM available - check for screenshot mode first
                #if targetEnvironment(simulator)
                if ScreenshotMockLLMService.isScreenshotMode {
                    Log.info("📸 Screenshot mode: Using mock LLM for demo", category: .initialization)
                    resolvedService = ScreenshotMockLLMService()
                } else {
                    Log.error(
                        "No configured LLM available; Apple Intelligence is REQUIRED",
                        category: .initialization
                    )
                    lastError = "⚠️ Running in Simulator: Apple Intelligence requires Apple Silicon (A17 Pro+ iPhone, M1+ iPad/Mac)."
                    resolvedService = AppleFoundationLLMServiceUnavailable()
                }
                #else
                Log.error(
                    "No configured LLM available; Apple Intelligence is REQUIRED",
                    category: .initialization
                )
                lastError = "⚠️ Apple Intelligence is required but unavailable. Enable it in Settings → Apple Intelligence & Siri."
                // Still need a service instance to avoid nil crashes, but it will always throw
                resolvedService = AppleFoundationLLMServiceUnavailable()
                #endif
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

            // After loading consent states, prewarm consent popup if needed
            // This shows the PCC consent popup during startup rather than mid-query
            // Delay slightly to let the UI fully render before showing popup
            try? await Task.sleep(for: .seconds(2))
            self.prewarmCloudConsentIfNeeded()
        }
        loadDocumentsFromDisk()

        // Connect document summary service to self for LLM access
        Task {
            await self.documentSummaryService.setRAGService(self)
        }

        // Observe container switches to save/restore transcripts
        observeContainerChanges()
    }

    // MARK: - Container Change Observer

    /// Previous container ID to detect when the active container changes.
    @MainActor private var previousContainerId: UUID?

    /// Observe changes to the active container and handle transcript persistence.
    ///
    /// When the user switches containers:
    /// 1. Save the current transcript for the old container
    /// 2. Restore any saved transcript for the new container
    private func observeContainerChanges() {
        // Initialize previous container ID
        Task { @MainActor in
            self.previousContainerId = self.containerService.activeContainerId
        }

        // Subscribe to container ID changes
        containerService.$activeContainerId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newContainerId in
                guard let self = self else { return }

                Task { @MainActor in
                    let oldContainerId = self.previousContainerId

                    // Skip if container hasn't actually changed
                    guard oldContainerId != newContainerId else { return }

                    Log.debug("[RAGService] Container changed: \(oldContainerId?.uuidString.prefix(8) ?? "nil") → \(newContainerId.uuidString.prefix(8))", category: .initialization)

                    // Save transcript for the old container (if any)
                    if let oldId = oldContainerId {
                        self.saveSessionTranscript(for: oldId)
                    }

                    // Restore transcript for the new container
                    self.restoreSessionTranscript(for: newContainerId)

                    // Update tracking
                    self.previousContainerId = newContainerId
                }
            }
            .store(in: &cancellables)
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

    // MARK: - Consent Prewarm

    /// Prewarm cloud consent by showing the popup during app startup (if needed)
    /// This prevents the consent popup from appearing mid-query and disrupting the pipeline.
    /// Called after model warmup completes so the user sees the popup once before their first query.
    @MainActor
    func prewarmCloudConsentIfNeeded() {
        // Only prewarm for PCC if consent is not yet determined
        guard cloudConsent[.applePCC] == nil || cloudConsent[.applePCC] == .notDetermined else {
            Log.debug("[Consent Prewarm] PCC consent already determined: \(cloudConsent[.applePCC]?.rawValue ?? "nil")", category: .initialization)
            return
        }

        // Only prewarm if using Apple Foundation Models (PCC)
        guard llmService is AppleFoundationLLMService else {
            Log.debug("[Consent Prewarm] Not using Apple Foundation Models, skipping", category: .initialization)
            return
        }

        Log.info("[Consent Prewarm] Showing PCC consent popup proactively", category: .initialization)

        // Create a minimal consent record to trigger the popup
        let prewarmRecord = CloudTransmissionRecord(
            provider: .applePCC,
            modelName: "Apple Foundation Model (On-Device)",
            promptPreview: "[Consent prewarm - no actual data transmitted]",
            promptCharacterCount: 0,
            contextChunkCount: 0,
            contextHashes: [],
            estimatedBytes: 0
        )

        // This will trigger the consent popup UI
        pendingCloudConsent = prewarmRecord
    }

    // MARK: - Universal Pipeline Tracing

    /// Log chunk content previews at each pipeline stage for debugging
    /// Shows first 100 chars of each chunk with score and page info
    private func logChunkTrace(_ chunks: [RetrievedChunk], stage: String, query: String) {
        guard Log.pipelineTraceEnabled else { return }

        let separator = String(repeating: "─", count: 60)
        print("\n\(separator)")
        print("📊 CHUNK TRACE: \(stage) (\(chunks.count) chunks)")
        print("   Query: \(query.prefix(50))\(query.count > 50 ? "..." : "")")
        print(separator)

        // Extract key terms from query for highlighting
        let queryTerms = extractQueryTerms(query)

        for (idx, chunk) in chunks.prefix(10).enumerated() {
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            let preview = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            let score = String(format: "%.3f", chunk.similarityScore)
            let page = chunk.pageNumber.map { "p.\($0)" } ?? "?"
            let section = chunk.chunk.metadata.sectionTitle ?? "—"

            // Check if chunk contains any query terms
            let contentLower = content.lowercased()
            let matchedTerms = queryTerms.filter { contentLower.contains($0) }
            let termMatch = matchedTerms.isEmpty ? "" : " ✓[\(matchedTerms.joined(separator: ","))]"

            print("  [\(idx)] score=\(score) \(page) §\(section.prefix(20))\(termMatch)")
            print("       \"\(preview)...\"")
        }

        if chunks.count > 10 {
            print("  ... and \(chunks.count - 10) more chunks")
        }
        print(separator)
    }

    /// Log final assembled context with keyword analysis
    private func logFinalContext(_ context: String, actualChunksUsed: Int, query: String) {
        guard Log.pipelineTraceEnabled else { return }

        let separator = String(repeating: "═", count: 60)
        print("\n\(separator)")
        print("📝 FINAL CONTEXT SENT TO LLM")
        print("   Query: \(query)")
        print("   Context: \(context.count) chars, \(actualChunksUsed) chunks")
        print(separator)

        // Extract key terms and check coverage
        let queryTerms = extractQueryTerms(query)
        let contextLower = context.lowercased()

        var foundTerms: [String] = []
        var missingTerms: [String] = []

        for term in queryTerms {
            if contextLower.contains(term) {
                foundTerms.append(term)
            } else {
                missingTerms.append(term)
            }
        }

        print("   Query terms found: \(foundTerms.joined(separator: ", "))")
        if !missingTerms.isEmpty {
            print("   ⚠️ Missing terms: \(missingTerms.joined(separator: ", "))")
        }

        // Show first 500 chars preview
        let preview = String(context.prefix(500)).replacingOccurrences(of: "\n", with: "↵")
        print("   Preview: \"\(preview)...\"")
        print(separator)
    }

    /// Scan all chunks for viscosity patterns and report findings
    /// This helps diagnose whether oil specs are present in the corpus
    private func runViscosityScan(_ allChunks: [DocumentChunk], query: String) async {
        guard Log.pipelineTraceEnabled else { return }

        // Only run for oil-related queries to avoid noise
        let queryLower = query.lowercased()
        _ = queryLower.contains("oil") || queryLower.contains("fluid") ||
            queryLower.contains("lubricant") || queryLower.contains("viscosity")

        let separator = String(repeating: "═", count: 60)
        print("\n\(separator)")
        print("🔍 CORPUS SPECIFICATION SCAN")
        print("   Query: \(query)")
        print("   Total chunks: \(allChunks.count)")
        print(separator)

        // Scan for viscosity patterns
        let viscosityPattern = #"\d+[Ww]-\d+"#
        var viscosityChunks: [(idx: Int, page: Int?, match: String, preview: String)] = []

        for (idx, chunk) in allChunks.enumerated() {
            let content = chunk.content
            if let range = content.range(of: viscosityPattern, options: .regularExpression) {
                let match = String(content[range])
                let preview = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                viscosityChunks.append((idx, chunk.metadata.pageNumber, match, preview))
            }
        }

        if viscosityChunks.isEmpty {
            print("   ⚠️ NO VISCOSITY PATTERNS FOUND (0W-20, 5W-30, etc.)")
            print("   This means the oil specification may be:")
            print("   • In an image/table not extracted as text")
            print("   • Split across chunk boundaries")
            print("   • Using non-standard formatting")

            // Search for related terms to help diagnose
            var oilMentions = 0
            var saeMatches: [String] = []
            for chunk in allChunks {
                let content = chunk.content.lowercased()
                if content.contains("engine oil") { oilMentions += 1 }
                if let range = content.range(of: #"sae\s*\d+"#, options: .regularExpression) {
                    saeMatches.append(String(chunk.content[range]))
                }
            }
            print("   Related: \(oilMentions) chunks mention 'engine oil'")
            if !saeMatches.isEmpty {
                print("   SAE mentions: \(Set(saeMatches).joined(separator: ", "))")
            }
        } else {
            print("   ✅ Found \(viscosityChunks.count) chunks with viscosity specs:")
            for vc in viscosityChunks.prefix(8) {
                let section = allChunks[vc.idx].metadata.sectionTitle ?? "—"
                print("   [\(vc.idx)] p.\(vc.page ?? 0) §\(section.prefix(25))")
                print("       Match: \(vc.match)")
                print("       \"\(vc.preview)...\"")
            }
            if viscosityChunks.count > 8 {
                print("   ... and \(viscosityChunks.count - 8) more")
            }
        }
        print(separator)
    }

    /// Count specification-like patterns in content (numbers, measurements, codes)
    /// Used to prioritize chunks with actual specs for lookup queries
    private func countSpecPatterns(_ content: String) -> Int {
        var score = 0

        // Oil viscosity patterns: 0W-20, 5W-30, etc.
        let viscosityPattern = #"\d+W-\d+"#
        if let regex = try? NSRegularExpression(pattern: viscosityPattern, options: []) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 3  // High weight for oil specs
        }

        // Measurement patterns: 3.5L, 100mm, 32psi, etc.
        let measurementPattern = #"\d+(?:\.\d+)?\s*(?:L|ml|mm|cm|m|kg|g|psi|kPa|°[CF]|ft|in|lbs?)\b"#
        if let regex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 2
        }

        // Table/list indicators (specs often in tables)
        if content.contains(":") && content.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 2
        }

        // API/spec codes: API SN, SAE, ACEA, etc.
        let specCodePattern = #"\b(?:API|SAE|ACEA|ILSAC|JASO)\s*[A-Z0-9-]+"#
        if let regex = try? NSRegularExpression(pattern: specCodePattern, options: []) {
            score += regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) * 3
        }

        // General numbers (lower weight)
        let numberPattern = #"\b\d+(?:\.\d+)?\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            score += min(5, regex.numberOfMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content)))  // Cap at 5
        }

        return score
    }

    // MARK: - Lexical Relevance Check

    /// Stop words to exclude from keyword matching
    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "through", "during", "before", "after", "above", "below", "between",
        "under", "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "each", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
        "too", "very", "just", "also", "now", "what", "which", "who", "whom",
        "this", "that", "these", "those", "am", "it", "its", "i", "me", "my",
        "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "he", "him", "his", "she", "her", "hers", "they", "them", "their"
    ]

    /// Check if query keywords appear in retrieved chunks (simple but effective)
    /// Returns 0.0-1.0 representing what fraction of query keywords appear in chunks
    private func checkLexicalRelevance(query: String, chunks: [RetrievedChunk]) -> Float {
        // Extract meaningful keywords from query (non-stopwords, 3+ chars)
        let queryWords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }

        guard !queryWords.isEmpty else { return 0.5 } // Can't evaluate, assume ok

        // Build combined chunk text
        let chunkText = chunks.prefix(5)
            .map { ($0.chunk.parentContent ?? $0.chunk.content).lowercased() }
            .joined(separator: " ")

        // Count how many query keywords appear in chunks
        var matchCount = 0
        for word in queryWords {
            if chunkText.contains(word) {
                matchCount += 1
            }
        }

        let relevance = Float(matchCount) / Float(queryWords.count)
        Log.debug("[LexicalRelevance] \(matchCount)/\(queryWords.count) keywords found = \(String(format: "%.0f%%", relevance * 100))", category: .retrieval)

        return relevance
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

    /// Public wrapper for Deep Think consent checking
    /// Allows AgenticOrchestrator to trigger the same consent flow as Standard mode
    func ensureConsentForDeepThink(
        service: LLMService,
        prompt: String,
        context: String?,
        sourceChunks: [DocumentChunk],
        allowPrivateCloudCompute: Bool
    ) async throws {
        try await ensureCloudConsentIfNeeded(
            service: service,
            prompt: prompt,
            context: context,
            sourceChunks: sourceChunks,
            allowPrivateCloudCompute: allowPrivateCloudCompute
        )
    }

    /// Check if PCC is currently suppressed (exposed for Deep Think)
    @MainActor
    func isPCCSuppressedForDeepThink() -> Bool {
        isPCCSuppressed()
    }

    /// Check if there's a transient consent grant for PCC (exposed for Deep Think)
    @MainActor
    func hasTransientPCCGrant() -> Bool {
        transientConsentGrants.contains(.applePCC)
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
            // Sync active container to router for memory pressure handling
            self.vectorRouter.activeContainerId = container?.id
            // ContainerService guarantees at least one container
            return self.vectorRouter.db(for: container!)
        }
    }

    /// Return a database for a specific container id (falls back to active on miss)
    private func dbFor(_ containerId: UUID) async -> VectorDatabase {
        return await MainActor.run {
            // Sync active container to router for memory pressure handling
            self.vectorRouter.activeContainerId = self.containerService.activeContainerId
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
            let engine = RAGEngine.shared
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

    /// Clear any pending reembed operations (used after onboarding to prevent unnecessary rebuilds)
    @MainActor
    func clearPendingReembeds() {
        pendingReembedContainerIds.removeAll()
        pendingReembedTask?.cancel()
        pendingReembedTask = nil
        Log.info("[RAGService] Cleared pending reembed queue", category: .ingestion)
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
        errorMessage: String? = nil,
        metricsUpdate: ((inout PipelineMetrics) -> Void)? = nil
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
            if let startedAt = item.startedAt {
                item.metrics.totalTimeMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            }
        }
        if let errorMessage {
            item.errorMessage = errorMessage
        }
        if let metricsUpdate {
            metricsUpdate(&item.metrics)
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

        // Set up progress handler for real-time updates (legacy string-based)
        documentProcessor.progressHandler = { [weak self] progress in
            Task { @MainActor in
                // Use transcribing stage for audio/video files
                let stage: IngestionStage = progress.contains("transcribing") ? .transcribing : .extracting
                let detail = progress.contains("transcribing") ? "Transcribing audio" : "Extracting (\(progress))"
                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: stage,
                    detail: detail
                )
            }
        }

        // Set up RICH progress handler for live metrics during extraction
        documentProcessor.richProgressHandler = { [weak self] progress in
            Task { @MainActor in
                let stage: IngestionStage = progress.stage == "transcribing" ? .transcribing : .extracting
                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: stage,
                    detail: progress.detail
                ) { metrics in
                    // Update live metrics from extraction progress
                    metrics.usedStructuredParsing = progress.usingVision
                    metrics.tablesExtracted = progress.tablesFound
                    metrics.listsExtracted = progress.listsFound
                    metrics.titlesDetected = progress.headersFound
                    metrics.ocrPagesCount = progress.ocrPagesUsed
                    if let totalPages = progress.totalPages {
                        metrics.pageCount = totalPages
                    }
                }
            }
        }

        do {
            // Step 1: Parse document and extract chunks
            let extractionStartTime = Date()
            let (document, processedChunks) = try await documentProcessor.processDocument(
                at: url,
                chunkOverride: chunkOverride,
                containerId: activeContainerId  // FTS5 storage with container isolation
            )
            let extractionTime = Date().timeIntervalSince(extractionStartTime)
            let totalChars = processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
            let totalWords = processedChunks.reduce(0) { $0 + $1.metadata.wordCount }

            // Calculate chunk word stats
            let chunkWordCounts = processedChunks.map { $0.metadata.wordCount }
            let avgChunkWords = chunkWordCounts.isEmpty ? 0 : chunkWordCounts.reduce(0, +) / chunkWordCounts.count
            let minChunkWords = chunkWordCounts.min() ?? 0
            let maxChunkWords = chunkWordCounts.max() ?? 0

            // Get file metadata
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSizeMB = Double((fileAttrs?[.size] as? Int64) ?? 0) / 1_048_576.0

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
                    detail: "\(processedChunks.count) chunks • \(totalWords) words • avg \(avgChunkWords)w/chunk"
                ) { metrics in
                    metrics.fileSizeMB = fileSizeMB
                    metrics.totalCharacters = totalChars
                    metrics.totalWords = totalWords
                    metrics.pageCount = document.processingMetadata?.pagesProcessed ?? 0
                    metrics.ocrPagesCount = document.processingMetadata?.ocrPagesCount ?? 0
                    metrics.chunkCount = processedChunks.count
                    metrics.avgChunkWords = avgChunkWords
                    metrics.minChunkWords = minChunkWords
                    metrics.maxChunkWords = maxChunkWords
                    metrics.extractionTimeMs = Int(extractionTime * 1000)

                    // === STRUCTURED PARSING TRANSPARENCY ===
                    if let meta = document.processingMetadata {
                        metrics.usedStructuredParsing = meta.usedStructuredParsing
                        metrics.structuredParsingQuality = meta.structuredParsingQuality
                        metrics.tablesExtracted = meta.tablesExtracted
                        metrics.tableRowsTotal = meta.tableRowsTotal
                        metrics.tableColumnsMax = meta.tableColumnsMax
                        metrics.listsExtracted = meta.listsExtracted
                        metrics.listItemsTotal = meta.listItemsTotal
                        metrics.titlesDetected = meta.titlesDetected
                        metrics.figureReferences = meta.figureReferences
                        metrics.visionEntitiesDetected = meta.visionEntitiesDetected
                        metrics.sectionPathDepth = meta.sectionPathDepth
                        metrics.structuredParsingTimeMs = Int(meta.structuredParsingTimeSeconds * 1000)
                        metrics.atomicTableChunks = meta.atomicTableChunks
                        metrics.atomicListChunks = meta.atomicListChunks
                    }
                }
            }

            // Small delay to show the chunking message
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

            // Step 1.5: Auto-adapt configuration if enabled
            if context.allowsSelfTuningScheduling,
               let autoContainer = container,
               autoContainer.autoAdaptDimension
            {
                let analysisStartTime = Date()
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Profiling corpus vocabulary and complexity..."
                    ) { metrics in
                        metrics.isAutoAdaptive = true
                    }
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
                        parentContent: chunk.parentText,
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

                let analysisTime = Date().timeIntervalSince(analysisStartTime)

                // Update metrics with analysis results
                let detectedLangs = report.corpus.languageHypotheses.sorted { $0.value > $1.value }.prefix(3).map { $0.key.rawValue }
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Vocab richness \(String(format: "%.0f%%", report.corpus.vocabularyRichness * 100)) • Tech density \(String(format: "%.0f%%", report.corpus.technicalDensity * 100))"
                    ) { metrics in
                        metrics.vocabularyRichness = report.corpus.vocabularyRichness
                        metrics.technicalDensity = report.corpus.technicalDensity
                        metrics.semanticComplexity = report.corpus.semanticComplexity
                        metrics.multilingualScore = report.corpus.multilingualScore
                        metrics.hasCode = report.corpus.hasCode
                        metrics.hasMath = report.corpus.hasMath
                        metrics.detectedLanguages = detectedLangs
                        metrics.chunkingStrategy = report.chunking.strategy.rawValue
                        metrics.targetWordWindow = report.chunking.targetWordWindow
                        metrics.overlapWords = report.chunking.overlapWords
                        metrics.analysisTimeMs = Int(analysisTime * 1000)
                    }
                }


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
            // Implements Anthropic's Contextual Retrieval: prepend document context to chunks
            // BEFORE embedding, so the embedding captures document-level semantics.
            // This reduces retrieval failures by 35-67% according to Anthropic's research.
            var embeddings: [[Float]] = []
            var contextualPrefixes: [String] = []
            let embeddingStartTime = Date()

            // Get embedding dimension from provider
            let embeddingDim = container?.embeddingDim ?? 384
            let embeddingProviderName = Self.shortProviderName(for: providerId)

            // Build contextual prefix once (reused for all chunks in this document)
            let docContext = buildContextualPrefix(filename: filename)
            Log.info("[Contextual] Document prefix: '\(docContext)'", category: .ingestion)

            // HYPERCHARGE: Build all texts to embed upfront, then batch embed
            // This uses parallel embedding (TaskGroup) in the provider layer
            var textsToEmbed: [String] = []
            textsToEmbed.reserveCapacity(processedChunks.count)

            // Get token limits from the embedding service
            let maxTokens = containerEmbeddingService.maxSafeTokens  // 510 for CoreML

            for chunk in processedChunks {
                // Build chunk-specific contextual prefix with section info
                let sectionContext = chunk.metadata.sectionTitle.map { " [\($0)]" } ?? ""
                let contextualPrefix = docContext + sectionContext + " "
                contextualPrefixes.append(contextualPrefix)

                // Embed with contextual prefix prepended (Anthropic's key insight)
                var textForEmbedding = contextualPrefix + chunk.text

                // CRITICAL: Validate token count using ACTUAL tokenizer
                // NLTokenizer word count != BPE/WordPiece token count!
                let tokenCount = containerEmbeddingService.countTokens(textForEmbedding)
                if tokenCount > maxTokens {
                    // Truncate text to fit within token limit
                    // This should rarely happen if DocumentProcessor limits are set correctly
                    Log.warning(
                        "[RAGService] ⚠️ Chunk exceeds token limit: \(tokenCount)/\(maxTokens) tokens. " +
                        "Truncating to prevent embedding data loss.",
                        category: .ingestion
                    )

                    // Binary search for safe truncation point
                    var low = 0
                    var high = textForEmbedding.count
                    while low < high {
                        let mid = (low + high + 1) / 2
                        let truncated = String(textForEmbedding.prefix(mid))
                        if containerEmbeddingService.countTokens(truncated) <= maxTokens {
                            low = mid
                        } else {
                            high = mid - 1
                        }
                    }
                    textForEmbedding = String(textForEmbedding.prefix(low))

                    let newTokenCount = containerEmbeddingService.countTokens(textForEmbedding)
                    Log.info("[RAGService] Truncated to \(newTokenCount) tokens (\(textForEmbedding.count) chars)", category: .ingestion)
                }

                textsToEmbed.append(textForEmbedding)
            }

            // Show initial progress
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .embedding,
                    detail: "Vectorizing \(processedChunks.count) chunks → \(embeddingDim)D",
                    progress: 0.0
                ) { metrics in
                    metrics.embeddingDimension = embeddingDim
                    metrics.embeddingProvider = embeddingProviderName
                }
            }

            // Capture variables for closure
            _ = processedChunks.count  // totalChunks used indirectly via embeddings
            let trackingIdForProgress = trackingId
            let filenameForProgress = filename

            // Batch embed with progress callback for live UI updates
            embeddings = try await containerEmbeddingService.generateEmbeddings(
                for: textsToEmbed,
                progressHandler: { [weak self] completed, total in
                    Task { @MainActor in
                        let progress = Double(completed) / Double(max(1, total))
                        self?.updateIngestionItem(
                            id: trackingIdForProgress,
                            filename: filenameForProgress,
                            stage: .embedding,
                            detail: "Embedding \(completed)/\(total) chunks...",
                            progress: progress
                        ) { metrics in
                            metrics.embeddingsGenerated = completed
                            metrics.embeddingBatchProgress = progress
                        }
                    }
                }
            )

            let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

            // Update with final embedding stats
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .indexing,
                    detail: "Building vector + BM25 indexes...",
                    progress: 1.0
                ) { metrics in
                    metrics.embeddingTimeMs = Int(embeddingTime * 1000)
                    metrics.embeddingsGenerated = embeddings.count
                }
            }

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
                    detail: "Persisting \(processedChunks.count) chunks to vector database..."
                )
            }

            // Step 3: Create DocumentChunk objects with embeddings and contextual prefixes
            let chunkingStartTime = Date()
            let documentChunks = zip(zip(processedChunks, embeddings), contextualPrefixes).enumerated().map { index, pair in
                let ((chunk, embedding), prefix) = pair
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
                    parentContent: chunk.parentText,
                    contextualPrefix: prefix,
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

            // Step 4.1: Learn vocabulary from chunks for per-container domain adaptation
            // Extracts domain terms, spec codes, and technical phrases to improve future retrieval
            for chunk in documentChunks {
                await ContainerVocabularyService.shared.learnFromChunk(
                    chunk.content,
                    containerId: activeContainerId
                )
            }

            // Step 4.1b: Learn from Vision-detected entities (emails, phones, dates, URLs, etc.)
            // These are automatically extracted during structured document parsing
            let visionEntities = documentProcessor.lastDetectedEntities
            if !visionEntities.isEmpty {
                await ContainerVocabularyService.shared.learnFromDetectedEntities(
                    visionEntities,
                    containerId: activeContainerId
                )
                Log.debug("[RAGService] Learned \(visionEntities.count) Vision-detected entities", category: .ingestion)
            }

            await ContainerVocabularyService.shared.documentIngested(
                filename,
                containerId: activeContainerId
            )
            TelemetryCenter.emit(
                .ingestion,
                title: "Vocabulary learned",
                metadata: [
                    "file": filename,
                    "container": activeContainerId.uuidString,
                    "visionEntities": "\(visionEntities.count)",
                ]
            )

            // Step 4.5: Generate document summary (RAPTOR-lite)
            // Creates a level-1 summary chunk for efficient overview queries
            // Controlled by settings.enableDocumentSummaries
            let summariesEnabled = await MainActor.run { self.settingsStore?.enableDocumentSummaries ?? true }

            if summariesEnabled {
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .storing,
                        detail: "Generating summary..."
                    )
                }

                do {
                    let summaryChunk = try await documentSummaryService.generateDocumentSummary(
                        documentId: document.id,
                        documentName: filename,
                        chunks: documentChunks,
                        embeddingService: containerEmbeddingService
                    )

                    // Store the summary chunk alongside detail chunks
                    try await db.storeBatch(chunks: [summaryChunk])

                    TelemetryCenter.emit(
                        .ingestion,
                        title: "Document summary generated",
                        metadata: [
                            "file": filename,
                            "summaryWords": "\(summaryChunk.metadata.wordCount)",
                            "abstractionLevel": "L1",
                        ]
                    )

                    Log.info("[RAGService] RAPTOR-lite: Generated L1 summary for '\(filename)'", category: .ingestion)
                } catch {
                    // Summary generation is optional - log but don't fail ingestion
                    Log.warning("[RAGService] Summary generation failed for '\(filename)': \(error)", category: .ingestion)
                    TelemetryCenter.emit(
                        .ingestion,
                        severity: .warning,
                        title: "Summary generation skipped",
                        metadata: [
                            "file": filename,
                            "error": error.localizedDescription,
                        ]
                    )
                }
            } else {
                Log.debug("[RAGService] Document summaries disabled in settings, skipping", category: .ingestion)
            }

            // Step 5: Generate content tags using Apple's content tagging model (iOS 26+)
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .storing,
                    detail: "Generating tags..."
                )
            }

            var generatedContentTags: [String]?
            if #available(iOS 26.0, *) {
                let taggingService = ContentTaggingService.shared
                if taggingService.isAvailable {
                    do {
                        let chunkTexts = processedChunks.map { $0.text }
                        let tags = try await taggingService.generateTagsForDocument(
                            chunks: chunkTexts,
                            documentName: filename
                        )
                        if !tags.displayTags.isEmpty {
                            generatedContentTags = tags.displayTags
                            TelemetryCenter.emit(
                                .generation,
                                title: "Content tags generated",
                                metadata: [
                                    "file": filename,
                                    "tags": tags.displayTags.joined(separator: ", "),
                                    "count": "\(tags.displayTags.count)",
                                ]
                            )
                        }
                    } catch {
                        Log.warning("[RAGService] Content tagging failed for \(filename): \(error)", category: .llm)
                    }
                }
            }

            // Calculate total pipeline time
            let totalTime = Date().timeIntervalSince(pipelineStartTime)

            // Calculate chunk statistics
            let chunkSizes = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkSizes.isEmpty ? 0 : chunkSizes.reduce(0, +) / chunkSizes.count
            let minChunkSize = chunkSizes.min() ?? 0
            let maxChunkSize = chunkSizes.max() ?? 0

            // Format file size string from existing fileSizeMB
            let fileSizeStr: String
            if fileSizeMB < 0.001 {
                fileSizeStr = String(format: "%.0f B", fileSizeMB * 1_048_576)
            } else if fileSizeMB < 1.0 {
                fileSizeStr = String(format: "%.2f KB", fileSizeMB * 1024.0)
            } else {
                fileSizeStr = String(format: "%.2f MB", fileSizeMB)
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
                    processingMetadata: completeMetadata,
                    contentTags: generatedContentTags
                )
            }

            // Ensure document is associated with the active container and has content tags
            let docWithContainer = Document(
                id: updatedDocument.id,
                filename: updatedDocument.filename,
                fileURL: updatedDocument.fileURL,
                contentType: updatedDocument.contentType,
                addedAt: updatedDocument.addedAt,
                totalChunks: updatedDocument.totalChunks,
                processingMetadata: updatedDocument.processingMetadata,
                containerId: activeContainerId,
                contentTags: generatedContentTags ?? updatedDocument.contentTags
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

                // Auto-tune retrieval config based on document types in container
                self.autoTuneRetrievalConfigIfNeeded()
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

    // MARK: - Contextual Retrieval Helper

    /// Build contextual prefix for Anthropic's Contextual Retrieval technique.
    /// Prepending document context to chunks BEFORE embedding improves retrieval by 35-67%.
    /// The prefix captures document-level semantics that help the embedding model understand
    /// what the chunk is about, even when the chunk content itself is generic.
    ///
    /// Example: A chunk "Long-press the Record Button" becomes embedded as
    /// "[PLAUD_NOTE_Manual.pdf] Long-press the Record Button" - the embedding now captures
    /// that this is about a PLAUD device, making queries like "button on this device" match better.
    private func buildContextualPrefix(filename: String) -> String {
        // Clean filename for embedding (remove extension, clean underscores)
        let cleanName = filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let baseName = (cleanName as NSString).deletingPathExtension

        // Keep prefix concise - embeddings have limited context windows
        // Format: "[Document: Filename]" - simple but effective
        return "[\(baseName)]"
    }

    /// Remove a document from the knowledge base
    func removeDocument(_ document: Document) async throws {
        let db = await dbForActiveContainer()
        try await db.deleteChunks(forDocument: document.id)

        // Delete full text storage for ZERO data orphans (both FTS5 and legacy file storage)
        await SQLiteFullTextService.shared.delete(for: document.id)
        await FullTextStorageService.shared.delete(for: document.id)

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

        // Delete full text storage for all documents being cleared (both FTS5 and legacy)
        // FTS5: Single bulk operation for entire container (most efficient)
        await SQLiteFullTextService.shared.deleteContainer(containerId: activeId)

        // Legacy file storage: Delete individual documents
        let docsToDelete = await MainActor.run {
            self.documents.filter { $0.containerId == activeId }
        }
        for doc in docsToDelete {
            await FullTextStorageService.shared.delete(for: doc.id)
        }

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

        // Get the reason for rebuild (from container's pending directive or generic)
        let rebuildReason = await MainActor.run {
            containerService.activeContainer?.chunkingDirective.map {
                "\($0.strategy.capitalized) strategy, \($0.targetWordWindow)w window"
            } ?? "Configuration changed"
        }

        TelemetryCenter.emit(
            .ingestion,
            title: "Library rebuild started",
            metadata: [
                "container": targetContainerId.uuidString,
                "documents": "\(documentsToRebuild.count)",
                "reason": rebuildReason,
            ]
        )

        // Create ingestion items for all documents in the rebuild batch
        let rebuildItems = documentsToRebuild.map { doc in
            var metrics = PipelineMetrics()
            metrics.isRebuild = true
            metrics.rebuildReason = rebuildReason
            metrics.isAutoAdaptive = true
            return IngestionItem(
                id: UUID(),
                url: doc.fileURL,
                stage: .queued,
                detail: "Queued for rebuild",
                metrics: metrics
            )
        }

        await MainActor.run {
            // Add all rebuild items to the queue so they're visible
            ingestionItems.append(contentsOf: rebuildItems)
        }

        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingStatus = ""
                self.isProcessing = false
                if originalContainerId != targetContainerId {
                    self.containerService.setActive(originalContainerId)
                }
                // Prune completed items after a delay
                self.pruneCompletedIngestionItems(delay: 5.0)
            }
        }

        for (index, document) in documentsToRebuild.enumerated() {
            if Task.isCancelled { break }

            let trackingId = rebuildItems[index].id

            // Guard: Skip documents whose source files no longer exist (e.g. temp sample files)
            guard FileManager.default.fileExists(atPath: document.fileURL.path) else {
                Log.warning(
                    "[RAGService] Skipping rebuild for '\(document.filename)' - source file no longer exists at \(document.fileURL.path)"
                )
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: document.filename,
                        stage: .complete,
                        detail: "Skipped (source file missing)",
                        progress: 1.0
                    )
                }
                continue
            }

            await MainActor.run {
                self.processingStatus = "Rebuilding \(document.filename) (\(index + 1)/\(documentsToRebuild.count))"
                self.isProcessing = true
                progressHandler?(ReembedProgress(
                    completed: index,
                    total: documentsToRebuild.count,
                    currentFilename: document.filename
                ))

                // Mark as reindexing in the queue
                updateIngestionItem(
                    id: trackingId,
                    filename: document.filename,
                    stage: .reindexing,
                    detail: "Removing old index..."
                ) { metrics in
                    metrics.isRebuild = true
                    metrics.rebuildReason = rebuildReason
                }
            }

            try await removeDocument(document)

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: document.filename,
                    stage: .reindexing,
                    detail: "Re-processing with new config..."
                )
            }

            // Re-add with autoRebuild context (prevents recursive self-tuning)
            try await addDocument(at: document.fileURL, context: .autoRebuild)

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: document.filename,
                    stage: .complete,
                    detail: "Rebuilt",
                    progress: 1.0
                )
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

        TelemetryCenter.emit(
            .ingestion,
            title: "Library rebuild complete",
            metadata: [
                "container": targetContainerId.uuidString,
                "documents": "\(documentsToRebuild.count)",
            ]
        )
    }

    // MARK: - Self-Tuning

    /// Auto-tunes retrieval configuration based on document types in the active container.
    /// Called after successful document ingestion to optimize search weights.
    @MainActor
    private func autoTuneRetrievalConfigIfNeeded() {
        guard let container = containerService.activeContainer else { return }

        // Collect document types from all documents in this container
        let containerDocs = documents.filter { $0.containerId == container.id }
        let documentTypes = containerDocs.map { $0.contentType }

        guard !documentTypes.isEmpty else { return }

        // Get recommended config based on document types
        let recommended = RetrievalConfig.recommended(forDocumentTypes: documentTypes)

        // Only update if the recommended config differs from current
        // and the user hasn't manually customized (check if it matches a known preset)
        let current = container.retrievalConfig

        // Skip if user has a high-accuracy or custom config (likely intentional)
        if current.minSimilarity >= 0.5 || current.requireExplicitCitations {
            Log.debug(
                "[RAGService] Skipping auto-tune: user has high-accuracy or custom config",
                category: .retrieval
            )
            return
        }

        // Apply if recommended differs significantly
        if recommended.vectorWeight != current.vectorWeight ||
            recommended.lexicalWeight != current.lexicalWeight ||
            abs(recommended.minSimilarity - current.minSimilarity) > 0.05
        {
            var updatedContainer = container
            updatedContainer.retrievalConfig = recommended

            containerService.updateContainer(updatedContainer)
            Log.info(
                "[RAGService] Auto-tuned retrieval config to '\(recommended.summary)' based on \(documentTypes.count) documents",
                category: .retrieval
            )

            TelemetryCenter.emit(
                .system,
                title: "Retrieval config auto-tuned",
                metadata: [
                    "config": recommended.summary,
                    "documents": "\(documentTypes.count)",
                    "vectorWeight": String(format: "%.2f", recommended.vectorWeight),
                    "keywordWeight": String(format: "%.2f", recommended.lexicalWeight),
                ]
            )
        }
    }

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

    // Increased from 24 to 150 for Maximum mode which can generate 100+ pipeline events
    private static let thinkingEventLimit = 150

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

    // MARK: - Agentic Query Execution

    /// Execute a multi-session agentic query for complex reasoning
    /// This bypasses the single-session 4K limit by orchestrating multiple focused LLM calls
    private func executeAgenticQuery(
        question: String,
        containerId: UUID,
        config: InferenceConfig?,
        qualityMode: RAGQualityMode
    ) async throws -> RAGResponse {
        // Check if user selected Maximum (unlimited) mode
        let isUnlimitedMode = qualityMode.isUnlimitedMode
        let modeLabel = isUnlimitedMode ? "MAXIMUM REASONING MODE" : "AGENTIC REASONING MODE"

        // Pipeline Trace: Agentic mode header
        let raptorSummariesEnabled = await MainActor.run { settingsStore?.enableDocumentSummaries ?? true }
        let raptorRoutingEnabled = await MainActor.run { settingsStore?.enableQueryRouting ?? true }
        Log.pipelineHeader(
            mode: isUnlimitedMode ? "Maximum" : "Deep Think",
            raptorSummaries: raptorSummariesEnabled,
            raptorRouting: raptorRoutingEnabled
        )

        // Pipeline Trace: Agentic orchestration step
        Log.pipelineStep("A", title: "Agentic Orchestration", details: [
            ("type", isUnlimitedMode ? "unlimited" : "multi-session"),
            ("confTarget", isUnlimitedMode ? "98%" : "75%")
        ])

        Log.box(
            modeLabel,
            level: .info,
            category: .pipeline,
            content: [
                "📝 Query: \(question)",
                "🧠 Multi-session orchestration active",
                isUnlimitedMode ? "🔥 Unlimited reasoning until 98% confident" : "⚡ Bypassing 4K single-session limit",
            ]
        )

        // Use unlimited config for Maximum mode, otherwise device-optimized
        let deviceService = DeviceCapabilityService.shared
        let optimizedConfig: AgenticConfig
        if isUnlimitedMode {
            optimizedConfig = qualityMode.agenticConfig // .unlimited config
            Log.info("[Pipeline] Using MAXIMUM mode (unlimited reasoning, 98% confidence threshold)", category: .pipeline)
        } else {
            optimizedConfig = deviceService.optimizedAgenticConfig()
        }

        let modeTitle = isUnlimitedMode ? "Maximum Mode" : "Deep Think Mode"
        let modeDetail = isUnlimitedMode
            ? "Unlimited reasoning until 98% confident (up to \(optimizedConfig.maxSteps) steps)"
            : "Starting multi-step reasoning (\(deviceService.tier.displayName) mode, up to \(optimizedConfig.maxSteps) steps)"

        emitThinkingEvent(
            .planning,
            title: modeTitle,
            detail: modeDetail
        )

        let orchestrator = AgenticOrchestrator(ragService: self, config: optimizedConfig)
        let startTime = Date()

        // Reset live counters at start of Deep Think / Maximum
        await MainActor.run {
            self.deepThinkLiveTokens = 0
            self.deepThinkLiveSteps = 0
            self.deepThinkLiveConfidence = 0
        }

        do {
            let result = try await orchestrator.execute(
                query: question,
                initialContext: "",
                onStep: { [weak self] step in
                    // Stream thinking steps to UI AND update live counters
                    await MainActor.run {
                        // Update live token counter for real-time UI
                        self?.deepThinkLiveTokens += step.tokensUsed

                        // Only count actual LLM reasoning sessions, NOT pipeline events
                        // Pipeline events have tokensUsed == 0 (they're just status updates)
                        // Retrieval steps (.searching, .expanding) don't count as reasoning sessions
                        let isLLMReasoningSession: Bool = {
                            switch step.type {
                            case .planning, .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                                return step.tokensUsed > 0  // Must have actual tokens to count
                            case .searching, .expanding:
                                return false  // Retrieval, not reasoning
                            }
                        }()

                        if isLLMReasoningSession {
                            self?.deepThinkLiveSteps += 1
                        }

                        // Update live confidence for Maximum mode
                        if let confidence = step.confidence {
                            self?.deepThinkLiveConfidence = confidence
                        }

                        // Check if this is a detailed sub-step (0 tokens = pipeline internals)
                        // Detailed steps from makeDetailedEventForwarder use format: "KIND|Title: Detail"
                        // This preserves the original ThinkingEvent.Kind (e.g., .vectorSearch, .bm25, .mmr)
                        if step.tokensUsed == 0 && step.output.contains("|") {
                            // Parse the encoded format: "kindRawValue|Title: Detail"
                            let pipeIndex = step.output.firstIndex(of: "|")!
                            let kindRaw = String(step.output[..<pipeIndex])
                            let rest = String(step.output[step.output.index(after: pipeIndex)...])

                            // Parse title and detail from "Title: Detail" format
                            let parts = rest.split(separator: ":", maxSplits: 1)
                            let title = String(parts.first ?? "Processing")
                            let detail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

                            // Recover the original ThinkingEvent.Kind for proper UI display
                            let eventKind = ThinkingEvent.Kind(rawValue: kindRaw) ?? step.type.thinkingKind
                            self?.emitThinkingEvent(eventKind, title: title, detail: detail)
                        } else if step.tokensUsed == 0 && step.output.contains(": ") {
                            // Legacy format without kind encoding (fallback)
                            let parts = step.output.split(separator: ":", maxSplits: 1)
                            let title = String(parts.first ?? "Processing")
                            let detail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: title,
                                detail: detail
                            )
                        } else if step.input.hasPrefix("Session ") {
                            // This is a reasoning session from Maximum mode - show session details
                            let sessionInfo = step.input // e.g., "Session 5/25"
                            let confidence = step.confidence ?? 0
                            let saturation = step.tokensUsed > 300 ? "deep" : "scanning"
                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: sessionInfo,
                                detail: "\(Int(confidence * 100))% confident • \(step.tokensUsed) tokens • \(saturation)"
                            )
                        } else {
                            // Regular reasoning step - use standard format
                            let detail: String
                            if let confidence = step.confidence {
                                detail = "Confidence: \(Int(confidence * 100))% • Tokens: \(step.tokensUsed)"
                            } else {
                                detail = "Tokens: \(step.tokensUsed), Duration: \(String(format: "%.1f", step.duration))s"
                            }

                            self?.emitThinkingEvent(
                                step.type.thinkingKind,
                                title: step.type.displayName,
                                detail: detail
                            )
                        }
                    }
                }
            )

            let totalTime = Date().timeIntervalSince(startTime)

            Log.info("[Agentic] Complete: \(result.steps.count) steps, \(result.totalTokens) tokens, \(String(format: "%.1f", totalTime))s", category: .pipeline)

            // Pipeline Trace: Agentic completion
            Log.pipelineComplete(
                totalDuration: totalTime,
                chunksRetrieved: result.steps.count, // Steps as "chunks" for agentic
                tokensUsed: result.totalTokens,
                confidence: Double(result.confidence)
            )

            emitThinkingEvent(
                .generation,
                title: "Synthesis complete",
                detail: "\(result.steps.count) reasoning steps, confidence: \(String(format: "%.0f%%", result.confidence * 100))"
            )

            // Set audit snapshot for UI with agentic-appropriate values
            // Agentic mode uses multiple small calls - show TOTAL usage across all calls
            // This makes the UI reflect the true "thinking" capacity used
            let totalTokensUsed = result.totalTokens
            let estimatedContextChars = totalTokensUsed * 3 // ~3 chars per token

            // Count LLM calls from step types (each non-search step = 1 LLM call)
            let llmCallCount = result.steps.filter { step in
                switch step.type {
                case .planning, .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                    return true
                case .searching, .expanding:
                    return false // These are retrieval, not LLM calls
                }
            }.count

            let agenticAudit = RAGAuditSnapshot(
                timestamp: Date(),
                query: question,
                containerId: containerId,
                containerName: "Agentic",
                embeddingProviderId: "agentic",
                embeddingDim: 512,
                vectorDBKind: .persistentJSON,
                chunkingTargetWords: 300,
                chunkingOverlapWords: 50,
                chunkingSource: "agentic",
                qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                retrievalConfig: .default,
                lenientRetrieval: true,
                dynamicMin: 0.3,
                topSim: 0.7,
                secondSim: 0.5,
                avgTop5: 0.5,
                acceptanceOverride: false,
                totalStoredChunks: result.retrievedChunks.count,
                candidatesCount: result.retrievedChunks.count,
                rerankedCount: result.retrievedChunks.count,
                filteredCount: 0,
                droppedCount: 0,
                mmrSelectedCount: result.retrievedChunks.count,
                uniqueDocCount: Set(result.retrievedChunks.map { $0.chunk.documentId }).count,
                contextStrategy: "recursive_rag",
                contextChars: estimatedContextChars, // Total chars across all calls
                contextWords: totalTokensUsed / 2,
                contextChunksUsed: result.retrievedChunks.count,
                maxContextChars: 0, // Not meaningful for recursive RAG
                baseWindowTokens: 4096, // Per-call limit (for reference)
                safetyTokens: 200,
                promptOverheadTokens: 100,
                questionTokens: question.count / 4,
                reservedOutputTokens: 800,
                availableContextTokens: 4096, // Per-call available (for reference)
                executionContext: .automatic,
                allowPrivateCloudCompute: true,
                networkConnected: NetworkMonitor.shared.isConnected,
                wantsCloudContext: true,
                reliabilityModeEnabled: true,
                allowUngroundedFallback: false,
                modelName: "Apple Foundation Model (Agentic)",
                isRecursiveRAG: true, // This tells UI to show tokens, not percentage
                totalTokensAcrossCalls: totalTokensUsed,
                llmCallCount: max(1, llmCallCount)
            )
            await MainActor.run {
                self.lastAuditSnapshot = agenticAudit
            }

            // Build RAGResponse from agentic result - include collected chunks for UI
            // Extract reasoning trace from steps for UI display (like Standard mode does)
            let reasoningTrace: [String]? = {
                // Filter to analysis/synthesis steps (not searching/expanding)
                let reasoningSteps = result.steps.filter { step in
                    switch step.type {
                    case .analyzing, .synthesizing, .refining, .reformulating, .verifying:
                        return true
                    case .planning, .searching, .expanding:
                        return false // Skip retrieval steps
                    }
                }

                guard reasoningSteps.count > 1 else { return nil }

                // Format with session labels (matching Standard mode style)
                let sessionLabels = ["🔍 Analyzing Evidence", "🧠 Finding Patterns", "💡 Refining", "✨ Synthesis"]
                return reasoningSteps.dropLast().enumerated().map { idx, step in
                    let label = idx < sessionLabels.count ? sessionLabels[idx] : "Session \(idx + 1)"
                    let cleanInsight = step.output
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "INSIGHT:", with: "")
                        .replacingOccurrences(of: "REASONING:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return "\(label): \(cleanInsight)"
                }
            }()

            return RAGResponse(
                queryId: UUID(),
                retrievedChunks: result.retrievedChunks,
                generatedResponse: result.finalAnswer,
                metadata: ResponseMetadata(
                    timeToFirstToken: totalTime / Double(max(1, result.steps.count)), // Estimate TTFT per step
                    totalGenerationTime: totalTime,
                    tokensGenerated: result.totalTokens,
                    tokensPerSecond: Float(result.totalTokens) / Float(totalTime),
                    modelUsed: "Apple Foundation Model (Agentic)",
                    retrievalTime: 0,
                    retrievalConfigSummary: "Agentic",
                    toolCallsMade: result.steps.filter { $0.type == .searching }.count,
                    usedAgenticMode: true, // Agentic (deep) mode was used
                    qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                    originalQuery: question,
                    reasoningTrace: reasoningTrace // Now includes the thinking steps!
                ),
                confidenceScore: result.confidence
            )
        } catch {
            Log.error("[Agentic] Failed: \(error.localizedDescription)", category: .pipeline)
            throw error
        }
    }

    // MARK: - RAG Query Pipeline

    /// Re-query the last question using forced agentic (deep reasoning) mode.
    /// Called by UI when user taps "Go Deeper" after a single-pass response.
    /// - Parameter streamHandler: Optional stream handler for live token updates
    /// - Returns: The RAG response with deeper analysis, or nil if no previous query exists
    func reQueryWithAgenticMode(streamHandler: LLMStreamHandler? = nil) async throws -> RAGResponse? {
        guard let query = await MainActor.run(body: { self.lastQueryText }) else {
            Log.warning("[RAG] No previous query to re-run with agentic mode", category: .pipeline)
            return nil
        }

        // Set the force flag before querying
        await MainActor.run { self.forceAgenticOnNextQuery = true }

        Log.info("[RAG] Re-querying with forced agentic mode: \(query.prefix(50))...", category: .pipeline)
        return try await self.query(query, streamHandler: streamHandler)
    }

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
        // Reliability mode always enabled — UI toggle removed for simplicity
        let reliabilityModeEnabled = true
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

        // Check user's quality mode setting to determine pipeline behavior
        // If user selected "deepThink" (Deep Think), use agentic orchestrator
        // Otherwise, use single-pass retrieval based on quality mode parameters
        let qualityMode = await MainActor.run {
            self.settingsStore?.ragQualityMode ?? .standard
        }

        // Also check for manual override via forceAgenticOnNextQuery
        let forceAgentic = await MainActor.run {
            let forced = self.forceAgenticOnNextQuery
            self.forceAgenticOnNextQuery = false // Reset after checking
            return forced
        }

        let useAgentic = forceAgentic || qualityMode.usesAgenticOrchestrator

        // Track query context for potential "Go Deeper" re-query
        await MainActor.run {
            self.lastQueryUsedAgentic = useAgentic
            self.lastQueryText = question
        }

        if forceAgentic {
            Log.info("[Pipeline] Query FORCED to agentic mode by user request", category: .pipeline)
        } else if qualityMode.isUnlimitedMode {
            Log.info("[Pipeline] Using Maximum mode (user selected)", category: .pipeline)
        } else if useAgentic {
            Log.info("[Pipeline] Using Deep Think mode (user selected)", category: .pipeline)
        } else {
            Log.info("[Pipeline] Using Standard mode", category: .pipeline)
        }

        // Pipeline Trace: Emit header with mode and RAPTOR-lite status
        let raptorSummariesEnabled = await MainActor.run { settingsStore?.enableDocumentSummaries ?? true }
        let raptorRoutingEnabled = await MainActor.run { settingsStore?.enableQueryRouting ?? true }
        let modeDisplayName = qualityMode.displayName
        Log.pipelineHeader(
            mode: modeDisplayName,
            raptorSummaries: raptorSummariesEnabled,
            raptorRouting: raptorRoutingEnabled
        )

        // Get adaptive pipeline config based on current device state (thermal, battery, memory)
        // This dynamically adjusts feature usage to prevent thermal throttling and save battery
        let queryComplexity = QueryComplexity.estimate(from: question)
        let adaptiveConfig = AdaptivePipelineOptimizer.shared.configForQuery(complexity: queryComplexity)
        let adaptiveOptLevel = AdaptivePipelineOptimizer.shared.currentOptimizationLevel
        if adaptiveOptLevel != .full {
            Log.info("[Adaptive] Pipeline adjusted to \(adaptiveOptLevel.rawValue) mode", category: .pipeline)
        }

        // Resolve embedding context first (needed for both agentic and standard paths)
        let embeddingContext = await resolveEmbeddingContext(preferredContainerId: containerId)
        let embeddingProviderId = embeddingContext.providerId
        let queryEmbeddingService = embeddingContext.service
        let selectedId = embeddingContext.containerId
        let selectedName = embeddingContext.containerName
        let selectedDim = embeddingContext.dimension

        // AGENTIC MODE: Use multi-session orchestrator for Deep Think mode
        // Triggered by user selecting Deep Think mode, or via "Go Deeper" re-query
        if useAgentic {
            return try await executeAgenticQuery(
                question: question,
                containerId: selectedId,
                config: config,
                qualityMode: qualityMode
            )
        }

        // Quality mode parameters from user settings
        let qualityModeDisplayName = qualityMode.displayName
        let qualityModeInitialTopK = qualityMode.initialTopK
        let qualityModeMinSimilarity = qualityMode.minSimilarity
        let qualityModeTemperature = qualityMode.temperature
        let qualityModeUsesQueryRewriting = qualityMode.usesQueryRewriting
        let qualityModeUsesIterativeRetrieval = qualityMode.usesIterativeRetrieval
        let qualityModeRequiresCitations = qualityMode.requiresCitations

        // NEW: Comprehensive quality mode feature toggles
        let qualityModeUsesHyDE = qualityMode.usesHyDE
        let qualityModeUsesReRanking = qualityMode.usesReRanking
        let qualityModeUsesMMR = qualityMode.usesMMR
        let qualityModeMMRLambda = qualityMode.mmrLambda
        let qualityModeUsesVerificationGates = qualityMode.usesVerificationGates
        let qualityModeVerificationThreshold = qualityMode.verificationConfidenceThreshold
        let qualityModeUsesQueryExpansion = qualityMode.usesQueryExpansion
        let qualityModeMaxQueryExpansions = qualityMode.maxQueryExpansions
        let qualityModeUsesContainerVocabulary = qualityMode.usesContainerVocabulary
        let qualityModeUsesParentDocRetrieval = qualityMode.usesParentDocumentRetrieval
        let qualityModeMaxSiblingChunks = qualityMode.maxSiblingChunks
        let qualityModeUsesContextualCompression = qualityMode.usesContextualCompression
        let _ = qualityMode.specificationBoostWeight  // Reserved for future spec-table boosting
        let qualityModeUsesConversationMemory = qualityMode.usesConversationMemory
        let qualityModeMaxConversationTurns = qualityMode.maxConversationTurns

        // Log feature toggles for this quality mode
        Log.debug("[RAGService] Quality mode '\(qualityModeDisplayName)' features: HyDE=\(qualityModeUsesHyDE), ReRank=\(qualityModeUsesReRanking), MMR=\(qualityModeUsesMMR), Verification=\(qualityModeUsesVerificationGates), QueryExpand=\(qualityModeUsesQueryExpansion), ContainerVocab=\(qualityModeUsesContainerVocabulary), ParentDoc=\(qualityModeUsesParentDocRetrieval), Compression=\(qualityModeUsesContextualCompression)", category: .pipeline)

        let developerTuningEnabled: Bool = await MainActor.run {
            settingsStore?.developerRAGTuningEnabled ?? false
        }

        let allowUngroundedFallback = reliabilityModeEnabled || developerTuningEnabled

        // Always use default retrieval config — per-container presets removed for simplicity
        // AdaptivePipelineOptimizer handles auto-tuning based on query patterns
        let retrievalConfig: RetrievalConfig = .default

        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == selectedId }
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

        // Fetch current stored chunk count from vector database (fallback to cached total)
        let totalStored = (try? await vdb.count()) ?? totalChunksStored

        // CRITICAL: Dynamic topK scaling based on corpus size
        // For large documents (1000+ pages = 10,000+ chunks), fixed topK of 20 samples only 0.2%
        // This scaling ensures we sample a meaningful percentage regardless of corpus size
        //
        // Scaling strategy:
        // - Small corpus (<100 chunks): topK = 15-20 (15-20% sample)
        // - Medium corpus (100-1000): topK = 20-40 (4-20% sample)
        // - Large corpus (1000-5000): topK = 40-80 (1.5-8% sample)
        // - Huge corpus (5000-15000): topK = 80-150 (1-3% sample)
        // - Massive corpus (15000+): topK = 150-250 (1-2% sample, capped for memory)
        let corpusSizeAdjustedTopK: Int = {
            switch totalStored {
            case 0..<100:
                return max(15, min(totalStored, 20))  // Small: up to 20
            case 100..<500:
                return 25  // Medium-small
            case 500..<1000:
                return 35  // Medium
            case 1000..<2500:
                return 50  // Large
            case 2500..<5000:
                return 75  // Very large
            case 5000..<10000:
                return 100  // Huge (1000-page dense doc)
            case 10000..<20000:
                return 150  // Massive
            default:
                return 200  // Cap at 200 for memory safety
            }
        }()

        // Adjust topK based on adaptive mode parameters AND corpus size
        let requestedTopK = max(topK, qualityModeInitialTopK)
        let baseTopK = max(requestedTopK, corpusSizeAdjustedTopK)

        let queryWords = question.split(separator: " ").count
        let isTrivial = isTrivialQuery(question)
        let applyTrivialTopKCap = isTrivial && !initialWantsCloudContext

        // Apply adaptive pipeline limit (thermal/battery/memory aware)
        // Caps retrieval when device is under pressure to prevent throttling
        let adaptiveMaxTopK = adaptiveConfig.maxRetrievalCandidates
        let uncappedEffectiveTopK = initialWantsCloudContext
            ? max(baseTopK, 50) // PCC mode: even more context since we have headroom
            : max(1, applyTrivialTopKCap ? min(baseTopK, 15) : baseTopK)
        let effectiveTopK = min(uncappedEffectiveTopK, adaptiveMaxTopK)

        if corpusSizeAdjustedTopK > requestedTopK {
            Log.info("[RAG] Corpus-size scaling: \(totalStored) chunks → topK boosted from \(requestedTopK) to \(corpusSizeAdjustedTopK)", category: .retrieval)
        }
        if effectiveTopK < uncappedEffectiveTopK {
            Log.info("[Adaptive] TopK capped: \(uncappedEffectiveTopK) → \(effectiveTopK) (device pressure)", category: .pipeline)
        }
        if isTrivial {
            let detail = applyTrivialTopKCap
                ? "fast topK cap (\(effectiveTopK))"
                : "cloud context available - keeping full topK"
            Log.info("[RAG] Trivial query detected - \(detail)", category: .retrieval)
        }

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
                "⚙️ Quality Mode: \(qualityModeDisplayName)",
            ]
        )

        // Build quality mode feature summary for thinking stream
        var enabledFeatures: [String] = []
        if qualityModeUsesHyDE { enabledFeatures.append("HyDE") }
        if qualityModeUsesReRanking { enabledFeatures.append("ReRank") }
        if qualityModeUsesMMR { enabledFeatures.append("MMR") }
        if qualityModeUsesVerificationGates { enabledFeatures.append("Verify") }
        if qualityModeUsesQueryExpansion { enabledFeatures.append("Expand") }
        if qualityModeUsesContainerVocabulary { enabledFeatures.append("Vocab") }
        if qualityModeUsesParentDocRetrieval { enabledFeatures.append("Parent") }
        if qualityModeUsesContextualCompression { enabledFeatures.append("Compress") }
        let featureSummary = enabledFeatures.joined(separator: " • ")

        emitThinkingEvent(
            .planning,
            title: "\(qualityModeDisplayName) mode",
            detail: featureSummary.isEmpty ? "Minimal features" : featureSummary
        )

        emitThinkingEvent(
            .planning,
            title: "Scoping query",
            detail: "Top \(effectiveTopK) • \(selectedName)"
        )

        TelemetryCenter.emit(
            .system,
            title: "Query received",
            metadata: [
                "question": String(question.prefix(80)),
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "qualityMode": qualityModeDisplayName,
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
                // ENHANCED RAG pipeline with LLM query understanding + iterative retrieval

                // Step 0: Build or retrieve cached Corpus Vocabulary (for context-aware understanding)
                Log.section("Step 0: Corpus Analysis", level: .info, category: .pipeline)
                let corpusStartTime = Date()

                // Pipeline Trace: Step 0
                Log.pipelineStep("0", title: "Corpus Analysis", details: [
                    ("chunks", "\(totalStored)"),
                    ("container", selectedName)
                ])

                // Use cached vocabulary if available to avoid expensive rebuilds
                let corpusVocabulary: CorpusVocabulary = await MainActor.run {
                    if let cached = self.corpusVocabularyCache[selectedId] {
                        Log.debug("[RAGService] Using cached corpus vocabulary for container \(selectedId)", category: .pipeline)
                        return cached
                    }
                    return CorpusVocabulary.empty
                }

                // Only build if not cached; also cache allChunks for lexical recall
                let finalCorpusVocabulary: CorpusVocabulary
                var cachedAllChunks: [DocumentChunk]?
                if corpusVocabulary.keywords.isEmpty {
                    let allChunks = try await vdb.allChunks()
                    cachedAllChunks = allChunks // Store for HybridSearchService lexical recall

                    // Run viscosity scan when building vocabulary (first query)
                    await runViscosityScan(allChunks, query: question)

                    let built = CorpusVocabulary.build(from: allChunks)
                    // Cache for future queries
                    await MainActor.run {
                        self.corpusVocabularyCache[selectedId] = built
                    }
                    finalCorpusVocabulary = built
                    let corpusTime = Date().timeIntervalSince(corpusStartTime)
                    Log.debug("Built corpus vocabulary in \(String(format: "%.0f", corpusTime * 1000))ms", category: .pipeline)
                } else {
                    finalCorpusVocabulary = corpusVocabulary
                    Log.debug("Using cached corpus vocabulary (0ms)", category: .pipeline)

                    // Even with cached vocabulary, run viscosity scan if pipeline trace is on
                    // This helps diagnose retrieval issues
                    if Log.pipelineTraceEnabled {
                        let allChunks = try await vdb.allChunks()
                        cachedAllChunks = allChunks
                        await runViscosityScan(allChunks, query: question)
                    }
                }

                // DIAGNOSTIC: For oil queries, ALWAYS scan corpus for viscosity specs
                // This helps debug retrieval issues without needing Pipeline Trace enabled
                let queryLower = question.lowercased()
                if queryLower.contains("oil") || queryLower.contains("viscosity") || queryLower.contains("0w") || queryLower.contains("5w") {
                    let scanChunks: [DocumentChunk]
                    if let cached = cachedAllChunks {
                        scanChunks = cached
                    } else {
                        scanChunks = try await vdb.allChunks()
                    }
                    let viscosityPattern = #"\d+[Ww]-\d+"#
                    var viscosityChunks: [(idx: Int, page: Int?, section: String?, match: String, preview: String)] = []
                    for (idx, chunk) in scanChunks.enumerated() {
                        let content = chunk.content
                        if let range = content.range(of: viscosityPattern, options: .regularExpression) {
                            let match = String(content[range])
                            let preview = String(content.prefix(150)).replacingOccurrences(of: "\n", with: " ")
                            viscosityChunks.append((idx, chunk.metadata.pageNumber, chunk.metadata.sectionTitle, match, preview))
                        }
                    }

                    Log.info("🔍 [OIL-DIAGNOSTIC] Query: '\(question)'", category: .retrieval)
                    Log.info("🔍 [OIL-DIAGNOSTIC] Scanned \(scanChunks.count) chunks for viscosity patterns", category: .retrieval)

                    if viscosityChunks.isEmpty {
                        Log.warning("🔍 [OIL-DIAGNOSTIC] ⚠️ NO CHUNKS contain viscosity specs (0W-20, 5W-30, etc.)", category: .retrieval)
                        Log.warning("🔍 [OIL-DIAGNOSTIC] The oil specification may be in an image/table that wasn't extracted as text", category: .retrieval)

                        // Look for related terms to help debug
                        var relatedChunks: [(idx: Int, keyword: String)] = []
                        let keywords = ["SAE", "synthetic", "motor oil", "engine oil capacity", "oil grade", "API"]
                        for (idx, chunk) in scanChunks.enumerated() {
                            for keyword in keywords {
                                if chunk.content.localizedCaseInsensitiveContains(keyword) {
                                    relatedChunks.append((idx, keyword))
                                    break
                                }
                            }
                        }
                        Log.info("🔍 [OIL-DIAGNOSTIC] Found \(relatedChunks.count) chunks with related oil keywords", category: .retrieval)
                        for rc in relatedChunks.prefix(3) {
                            let chunk = scanChunks[rc.idx]
                            let preview = String(chunk.content.prefix(100)).replacingOccurrences(of: "\n", with: " ")
                            Log.info("🔍 [OIL-DIAGNOSTIC] Chunk[\(rc.idx)] '\(rc.keyword)': \(preview)...", category: .retrieval)
                        }
                    } else {
                        Log.info("🔍 [OIL-DIAGNOSTIC] ✅ Found \(viscosityChunks.count) chunks with viscosity specs:", category: .retrieval)
                        for vc in viscosityChunks.prefix(5) {
                            Log.info("🔍 [OIL-DIAGNOSTIC] Chunk[\(vc.idx)] p.\(vc.page ?? 0) [\(vc.section ?? "?")] \(vc.match): \(vc.preview)", category: .retrieval)
                        }
                    }
                }

                // Check advanced RAG settings
                let useQueryRewriting = settingsStore?.enableQueryRewriting ?? qualityModeUsesQueryRewriting
                // Note: Iterative retrieval is a future enhancement, capturing setting for later use
                _ = settingsStore?.enableIterativeRetrieval ?? qualityModeUsesIterativeRetrieval

                // Step 1: LLM-Powered Query Understanding (if enabled)
                var effectiveQuery = question
                var queryWasRewritten = false
                var rewriteTime: TimeInterval = 0

                if useQueryRewriting {
                    Log.section("Step 1: Query Understanding", level: .info, category: .pipeline)
                    let rewriteStartTime = Date()

                    // Pipeline Trace: Step 1
                    Log.pipelineStep("1", title: "Query Understanding", details: [
                        ("rewriting", "enabled")
                    ])
                    let documentNames = await snapshotDocuments().map { $0.filename }
                    let queryRewriter = QueryRewriterService(
                        corpusVocabulary: finalCorpusVocabulary,
                        documentSummaries: nil
                    )

                    // Build conversation context for pronoun resolution
                    // Use ConversationMemoryService for enhanced entity-aware context if available
                    // Respect both quality mode toggle and user settings
                    let conversationMemoryEnabled = qualityModeUsesConversationMemory && (settingsStore?.enableConversationMemory ?? true)
                    var recentTurns: [ConversationTurn] = []

                    if #available(iOS 26.0, *), conversationMemoryEnabled {
                        // Get memory-enhanced context with tracked entities
                        // ONLY use actual conversation turns - NOT synthetic context from memory entities
                        // Synthetic context causes false-positive rewrites (e.g., "this button" → "the button you mentioned")
                        let memory = ConversationMemoryService.shared.memory(for: selectedId)
                        let maxTurns = min(qualityModeMaxConversationTurns, 3) // Use quality mode limit for rewriting
                        recentTurns = memory.recentTurns.suffix(maxTurns).map { turn in
                            ConversationTurn(
                                role: "user",
                                content: turn.userQuery,
                                entities: turn.extractedFacts.prefix(3).map { String($0.prefix(50)) }
                            )
                        }
                        // Note: Intentionally NOT creating synthetic turns from memory.entities
                        // Memory entities persist across sessions and don't provide reliable pronoun referents
                        Log.debug("[ConversationMemory] Using memory for query rewriting (\(recentTurns.count) turns, \(memory.entities.count) entities)", category: .retrieval)
                    }

                    // Fallback to raw chat history if memory didn't provide context
                    if recentTurns.isEmpty {
                        let conversationHistory = chatHistory(for: selectedId)
                        recentTurns = conversationHistory
                            .filter { $0.role != .system }
                            .suffix(4) // Last 4 messages
                            .map { msg in
                                ConversationTurn(
                                    role: msg.role == .user ? "user" : "assistant",
                                    content: String(msg.content.prefix(300)),
                                    entities: [] // Will be extracted by the service
                                )
                            }
                    }

                    do {
                        let rewriteResult = try await queryRewriter.rewrite(
                            query: question,
                            documentNames: documentNames,
                            conversationContext: recentTurns
                        )
                        effectiveQuery = rewriteResult.rewritten
                        queryWasRewritten = rewriteResult.wasRewritten

                        if rewriteResult.wasRewritten {
                            var detail = "Intent: \(rewriteResult.intent.rawValue)"
                            if !rewriteResult.resolvedEntities.isEmpty {
                                detail += " • Resolved: \(rewriteResult.resolvedEntities.prefix(2).joined(separator: ", "))"
                            } else {
                                detail += " • \(rewriteResult.entities.prefix(3).joined(separator: ", "))"
                            }
                            Log.info(
                                "✓ Query rewritten: \"\(question.prefix(40))...\" → \"\(rewriteResult.rewritten.prefix(60))...\"",
                                category: .retrieval
                            )
                            emitThinkingEvent(
                                .planning,
                                title: "Query understood",
                                detail: detail
                            )
                        }
                    } catch {
                        Log.warning("[RAGService] Query rewriting failed, using original: \(error)", category: .retrieval)
                    }

                    rewriteTime = Date().timeIntervalSince(rewriteStartTime)
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Query understanding",
                        metadata: [
                            "rewritten": queryWasRewritten ? "true" : "false",
                            "originalLength": "\(question.count)",
                            "rewrittenLength": "\(effectiveQuery.count)",
                        ],
                        duration: rewriteTime
                    )
                } else {
                    Log.debug("[RAGService] Query rewriting disabled, using original query", category: .pipeline)
                }

                // Step 1.5: Corpus-Aware Query Expansion
                // QUALITY MODE: Check if query expansion is enabled
                var expandedQueries: [String] = []
                var expansionTime: TimeInterval = 0

                // Create QueryEnhancementService at outer scope (used by expansion AND intent classification)
                let queryEnhancer = QueryEnhancementService(corpusVocabulary: finalCorpusVocabulary)

                if qualityModeUsesQueryExpansion {
                    Log.section("Step 1.5: Query Expansion", level: .info, category: .pipeline)
                    let expansionStartTime = Date()
                    expandedQueries = queryEnhancer.expandQuery(effectiveQuery)

                    // Limit to quality mode maximum
                    if expandedQueries.count > qualityModeMaxQueryExpansions {
                        expandedQueries = Array(expandedQueries.prefix(qualityModeMaxQueryExpansions))
                        Log.debug("[RAGService] Capped query expansions to \(qualityModeMaxQueryExpansions) (quality mode: \(qualityModeDisplayName))", category: .retrieval)
                    }

                    // Step 1.5b: Per-Container Vocabulary Expansion (if enabled)
                    if qualityModeUsesContainerVocabulary {
                        let vocabExpansions = await ContainerVocabularyService.shared.expandQuery(
                            effectiveQuery,
                            containerId: selectedId
                        )
                        if !vocabExpansions.isEmpty {
                            let uniqueVocabTerms = vocabExpansions.filter { !expandedQueries.contains($0) }
                            // Respect max expansions limit
                            let spaceRemaining = qualityModeMaxQueryExpansions - expandedQueries.count
                            let termsToAdd = Array(uniqueVocabTerms.prefix(max(0, spaceRemaining)))
                            expandedQueries.append(contentsOf: termsToAdd)
                            Log.debug(
                                "[RAGService] Container vocabulary added \(termsToAdd.count) terms",
                                category: .retrieval
                            )
                        }
                    } else {
                        Log.debug("[RAGService] Container vocabulary expansion skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
                    }

                    expansionTime = Date().timeIntervalSince(expansionStartTime)
                    Log.info(
                        "✓ Expanded to \(expandedQueries.count) query variations in \(String(format: "%.0f", expansionTime * 1000))ms",
                        category: .pipeline
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Query expanded",
                        metadata: [
                            "variants": "\(expandedQueries.count)",
                            "maxAllowed": "\(qualityModeMaxQueryExpansions)",
                        ],
                        duration: expansionTime
                    )

                    if !expandedQueries.isEmpty {
                        emitThinkingEvent(
                            .queryRewrite,
                            title: "Query expansion",
                            detail: "\(expandedQueries.count) variants generated"
                        )
                    }
                } else {
                    Log.info("[RAG] Query expansion skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
                    emitThinkingEvent(
                        .queryRewrite,
                        title: "Query expansion skipped",
                        detail: "Quality mode: \(qualityModeDisplayName)"
                    )
                }

                // Step 1.6: Answer Intent Classification (AppleRAG §6)
                // Classify query intent to optimize retrieval and answering strategy
                let answerIntent = queryEnhancer.classifyAnswerIntent(effectiveQuery)
                Log.info(
                    "✓ Answer intent: \(answerIntent.rawValue) (extractive-first: \(answerIntent.isExtractiveFirst), multi-hop: \(answerIntent.benefitsFromMultiHop))",
                    category: .pipeline
                )
                emitThinkingEvent(
                    .intentRoute,
                    title: "Intent: \(answerIntent.rawValue)",
                    detail: answerIntent.isExtractiveFirst ? "Extractive-first" : (answerIntent.benefitsFromMultiHop ? "Multi-hop enabled" : "Standard")
                )

                // Step 2: Embed the user's query
                Log.section("Step 2: Query Embedding", level: .info, category: .pipeline)
                let embeddingStartTime = Date()

                // HyDE: Combine quality mode toggle with user settings and service availability
                let hydeEnabledBySettings = settingsStore?.enableHyDE ?? true
                let hydeEnabledForMode = qualityModeUsesHyDE && hydeEnabledBySettings && HyDEService.isAvailable

                // CRITICAL: Disable HyDE for extractive/lookup queries to avoid hallucinated specifics biasing retrieval
                // HyDE can guess wrong values (e.g., "5W-40" when answer is "0W-20") and pull wrong chunks
                // Extractive-first intents (lookup, tableLookup, procedure) work better with keyword matching
                let hydeDisabledForIntent = answerIntent.isExtractiveFirst
                if hydeDisabledForIntent && hydeEnabledForMode {
                    Log.debug("[HyDE] Disabled for extractive intent '\(answerIntent.rawValue)' - keyword matching preferred", category: .retrieval)
                }

                // Pipeline Trace: Step 2
                Log.pipelineStep("2", title: "Query Embedding", details: [
                    ("provider", embeddingProviderId),
                    ("dim", "\(selectedDim)"),
                    ("HyDE", (hydeEnabledForMode && !hydeDisabledForIntent) ? "enabled" : "off")
                ])

                // HyDE (Hypothetical Document Embeddings) - Gao et al. 2022
                // Generates a hypothetical answer for better retrieval when question vocab differs from answer vocab
                // Only used for factual queries where this vocabulary gap is significant
                // DISABLED for extractive/lookup intents where specific values matter
                let useHyDE = hydeEnabledForMode && !hydeDisabledForIntent && HyDEService.shouldUseHyDE(for: effectiveQuery)
                var hydeText: String?

                if hydeDisabledForIntent && hydeEnabledForMode {
                    // HyDE was enabled but skipped due to extractive intent
                    emitThinkingEvent(
                        .hyde,
                        title: "HyDE skipped",
                        detail: "Extractive intent '\(answerIntent.rawValue)' - using direct keyword matching"
                    )
                }

                if useHyDE {
                    let hydeService = HyDEService()
                    do {
                        let hydeResult = try await hydeService.generateHyDEQuery(for: effectiveQuery)
                        hydeText = hydeResult.hypotheticalDocument
                        Log.info("[HyDE] Generated hypothetical doc: \"\(hydeText?.prefix(80) ?? "")...\"", category: .retrieval)
                        emitThinkingEvent(
                            .hyde,
                            title: "HyDE generation",
                            detail: "Hypothetical doc for vocabulary bridging"
                        )
                    } catch {
                        Log.warning("[HyDE] Failed to generate hypothetical doc: \(error.localizedDescription)", category: .retrieval)
                        // Fall back to regular query embedding
                    }
                }

                // Use HyDE text if available, otherwise use the rewritten query
                let textToEmbed = hydeText ?? effectiveQuery

                let queryEmbedding = try await queryEmbeddingService.generateEmbedding(for: textToEmbed)
                let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

                let embeddingMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
                let hydeStatus = hydeText != nil ? " [HyDE]" : ""
                Log.info(
                    "✓ Generated \(queryEmbedding.count)-dimensional embedding\(hydeStatus)",
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
                // With optional iterative retrieval for multi-pass refinement
                let useIterative = settingsStore?.enableIterativeRetrieval ?? false
                let iterativeConfig = IterativeRetrievalConfig.default

                let retrievalStartTime = Date()
                let retrievedChunks: [RetrievedChunk]
                var iterativeMetadata: (iterations: Int, confidence: Float, queries: Int)?

                // Classify query intent for adaptive weight tuning (used in both paths)
                let queryIntent = queryEnhancer.classifyIntent(effectiveQuery)
                let adjustment = queryIntent.weightAdjustment
                let adjustedVectorWeight = max(0.1, min(0.9, retrievalConfig.vectorWeight + adjustment.vectorDelta))
                let adjustedKeywordWeight = max(0.1, min(0.9, retrievalConfig.lexicalWeight + adjustment.keywordDelta))

                // Step 2.5: Query Classification for RAPTOR-lite (summary-first retrieval)
                // Determines whether to search document summaries (L1) or detail chunks (L0)
                // Controlled by settings.enableQueryRouting
                // HYPERCHARGE: Run RAPTOR classification in parallel with retrieval setup
                // (query classification is independent of embedding results)
                let queryRoutingEnabled = settingsStore?.enableQueryRouting ?? true
                // Capture effectiveQuery to avoid concurrent access to var
                let queryForRouting = effectiveQuery
                async let asyncQueryClassification = queryRouter.classifyQuery(queryForRouting)
                let queryClassification = await asyncQueryClassification

                // Pipeline Trace: Step 2.5 (RAPTOR-lite)
                if queryRoutingEnabled {
                    Log.pipelineStep("2.5", title: "RAPTOR-lite Query Routing", details: [
                        ("type", queryClassification.queryType.rawValue),
                        ("confidence", String(format: "%.0f%%", queryClassification.confidence * 100))
                    ])
                }
                let searchLevels = await queryRouter.abstractionLevelsToSearch(for: queryClassification)

                if queryRoutingEnabled {
                    Log.info(
                        "[RAPTOR-lite] Query type: \(queryClassification.queryType.rawValue) " +
                        "(confidence: \(String(format: "%.0f", queryClassification.confidence * 100))%) " +
                        "→ search \(searchLevels.map { $0.description }.joined(separator: ", "))",
                        category: .retrieval
                    )
                }

                // Filter cached chunks by abstraction level if we have summaries AND routing is enabled
                var filteredCachedChunks: [DocumentChunk]? = cachedAllChunks
                if queryRoutingEnabled, let allChunks = cachedAllChunks {
                    let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }
                    if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                        // For overview queries, prioritize summary chunks
                        filteredCachedChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                        Log.info(
                            "[RAPTOR-lite] Filtered to \(filteredCachedChunks?.count ?? 0) chunks (from \(allChunks.count)) for overview query",
                            category: .retrieval
                        )
                        emitThinkingEvent(
                            .planning,
                            title: "Using document summaries",
                            detail: "Overview query → searching L1 summaries first"
                        )
                    }
                }

                if useIterative {
                    // Multi-pass iterative retrieval with self-correction
                    Log.section(
                        "Step 3: Iterative Retrieval (\(iterativeConfig.maxIterations) max passes)",
                        level: .info,
                        category: .pipeline
                    )

                    // Pipeline Trace: Step 3 (Iterative)
                    Log.pipelineStep("3", title: "Iterative Retrieval", details: [
                        ("maxPasses", "\(iterativeConfig.maxIterations)"),
                        ("targetConf", String(format: "%.0f%%", iterativeConfig.confidenceThreshold * 100))
                    ])
                    emitThinkingEvent(
                        .retrieval,
                        title: "Multi-pass retrieval",
                        detail: "Up to \(iterativeConfig.maxIterations) iterations for confidence ≥\(Int(iterativeConfig.confidenceThreshold * 100))%"
                    )

                    let iterativeService = IterativeRetrievalService(
                        hybridSearchFactory: { db in
                            HybridSearchService(
                                vectorDatabase: db,
                                vectorWeight: adjustedVectorWeight,
                                keywordWeight: adjustedKeywordWeight
                            )
                        },
                        embeddingService: queryEmbeddingService
                    )

                    // Pass cached chunks to avoid redundant allChunks() calls in iterative retrieval
                    let iterativeResult = try await iterativeService.retrieve(
                        query: expandedQueries.joined(separator: " "),
                        vectorDatabase: vdb,
                        config: iterativeConfig,
                        topK: effectiveTopK,
                        cachedChunks: filteredCachedChunks
                    )

                    retrievedChunks = iterativeResult.allChunks
                    iterativeMetadata = (
                        iterations: iterativeResult.iterations,
                        confidence: iterativeResult.confidence,
                        queries: iterativeResult.queriesUsed.count
                    )

                    Log.info(
                        "✓ Iterative retrieval complete: \(iterativeResult.iterations) passes, " +
                            "\(retrievedChunks.count) chunks, confidence \(String(format: "%.0f", iterativeResult.confidence * 100))%",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Iterative retrieval complete",
                        metadata: [
                            "iterations": "\(iterativeResult.iterations)",
                            "chunks": "\(retrievedChunks.count)",
                            "confidence": String(format: "%.2f", iterativeResult.confidence),
                            "queries": "\(iterativeResult.queriesUsed.count)",
                            "hitMax": "\(iterativeResult.hitMaxIterations)",
                        ],
                        duration: iterativeResult.totalTime
                    )
                    emitThinkingEvent(
                        .retrieval,
                        title: "Retrieval complete",
                        detail: "\(iterativeResult.iterations) passes → \(retrievedChunks.count) chunks (\(Int(iterativeResult.confidence * 100))% confidence)"
                    )
                } else {
                    // Single-pass hybrid search (original behavior)
                    Log.section(
                        "Step 3: Hybrid Search (Vector + BM25)", level: .info, category: .pipeline
                    )

                    // Pipeline Trace: Step 3 (Single-pass)
                    Log.pipelineStep("3", title: "Hybrid Search", details: [
                        ("vector", String(format: "%.0f%%", adjustedVectorWeight * 100)),
                        ("BM25", String(format: "%.0f%%", adjustedKeywordWeight * 100)),
                        ("topK", "\(effectiveTopK * 3)")
                    ])

                    Log.debug(
                        "[RAGService] Query intent: \(queryIntent.rawValue) → weights adjusted to vector=\(String(format: "%.2f", adjustedVectorWeight)), keyword=\(String(format: "%.2f", adjustedKeywordWeight))",
                        category: .retrieval
                    )

                    let hybridSearch = HybridSearchService(
                        vectorDatabase: vdb,
                        vectorWeight: adjustedVectorWeight,
                        keywordWeight: adjustedKeywordWeight
                    )
                    // Use expanded queries for keyword search (original for vector)
                    // Pass cached chunks to avoid redundant allChunks() call in lexical recall
                    // For RAPTOR-lite: filteredCachedChunks may be limited to summaries for overview queries
                    // Pass containerId to enable FTS5-accelerated BM25 (10-100X faster than in-memory)
                    retrievedChunks = try await hybridSearch.search(
                        query: expandedQueries.joined(separator: " "), // Combine expansions
                        embedding: queryEmbedding,
                        topK: effectiveTopK * 3, // Retrieve 3x for better coverage on large docs
                        cachedChunks: filteredCachedChunks,
                        containerId: selectedId // Enable SQLite FTS5 for this container
                    )
                }

                // Measure retrieval time before any MainActor work
                var retrievalTime = Date().timeIntervalSince(retrievalStartTime)
                recoveryRetrievalTime = retrievalTime

                // Log iterative metadata if applicable
                if let meta = iterativeMetadata {
                    Log.debug(
                        "[RAGService] Iterative retrieval used \(meta.iterations) iterations, \(meta.queries) query variants",
                        category: .retrieval
                    )
                }

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

                // Emit detailed technique events for full transparency
                emitThinkingEvent(
                    .vectorSearch,
                    title: "Vector search",
                    detail: "Semantic similarity • \(Int(adjustedVectorWeight * 100))% weight"
                )
                emitThinkingEvent(
                    .bm25,
                    title: "BM25 search",
                    detail: "Keyword matching • \(Int(adjustedKeywordWeight * 100))% weight"
                )
                emitThinkingEvent(
                    .rrf,
                    title: "RRF fusion",
                    detail: "\(chunksWithSources.count) candidates merged"
                )

                Log.info(
                    "✓ Retrieved \(chunksWithSources.count) chunks with hybrid fusion",
                    category: .retrieval
                )

                // Universal pipeline trace: log chunks after hybrid search
                if Log.pipelineTraceEnabled {
                    logChunkTrace(chunksWithSources, stage: "Post-HybridSearch", query: question)
                }

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
                // QUALITY MODE: Check if re-ranking is enabled
                let engine = RAGEngine.shared
                let rerankStartTime = Date()
                var rerankedChunks: [RetrievedChunk]
                var rerankTime: TimeInterval = 0

                if qualityModeUsesReRanking {
                    Log.section("Step 4: Multi-Signal Re-ranking", level: .info, category: .pipeline)

                    // Pipeline Trace: Step 4
                    Log.pipelineStep("4", title: "Multi-Signal Reranking", details: [
                        ("candidates", "\(chunksWithSources.count)")
                    ])

                    rerankedChunks = await engine.rerank(
                        chunks: chunksWithSources,
                        query: question,
                        topK: effectiveTopK * 3 // Get more candidates for MMR diversification (clamped)
                    )
                    auditRerankedCount = rerankedChunks.count
                    rerankTime = Date().timeIntervalSince(rerankStartTime)
                    Log.info(
                        "✓ Re-ranked to top \(rerankedChunks.count) in \(String(format: "%.0f", rerankTime * 1000))ms",
                        category: .retrieval
                    )

                    // Universal pipeline trace: log chunks after re-ranking
                    if Log.pipelineTraceEnabled {
                        logChunkTrace(rerankedChunks, stage: "Post-Rerank", query: question)
                    }

                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Re-ranking complete",
                        metadata: [
                            "candidates": "\(rerankedChunks.count)",
                        ],
                        duration: rerankTime
                    )
                    emitThinkingEvent(
                        .rerank,
                        title: "Cross-encoder rerank",
                        detail: "\(rerankedChunks.count) candidates scored"
                    )
                } else {
                    Log.info("[RAG] Re-ranking skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
                    // Use chunks as-is, sorted by existing scores
                    rerankedChunks = chunksWithSources.sorted { $0.similarityScore > $1.similarityScore }
                    rerankedChunks = Array(rerankedChunks.prefix(effectiveTopK * 3))
                    auditRerankedCount = rerankedChunks.count
                    rerankTime = Date().timeIntervalSince(rerankStartTime)
                    emitThinkingEvent(
                        .rerank,
                        title: "Re-ranking skipped",
                        detail: "Quality mode: \(qualityModeDisplayName)"
                    )
                }

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

                // Use adaptive mode's minSimilarity, adjusted for lenient/trivial
                let qualityMinSim = qualityModeMinSimilarity
                let baseMin: Float
                if retrievalConfig == .highAccuracy {
                    baseMin = retrievalConfig.minSimilarity
                } else {
                    // Simplified: use quality mode threshold directly
                    baseMin = qualityMinSim
                }

                var dynamicMin: Float = lenient ? min(baseMin, 0.35) : baseMin

                // Vocabulary mismatch detection: When ALL scores are low but we have a corpus,
                // the problem is likely conversational-vs-technical language mismatch, not irrelevant docs.
                // In this case, trust relative ranking over absolute thresholds.
                let vocabularyMismatch = rerankedChunks.count >= 5 && topSim < 0.25 && avgTop5 < 0.20

                if vocabularyMismatch {
                    // Adaptive floor: use the corpus's natural score distribution
                    // Keep chunks that are in the top tier relative to this corpus
                    let scoreSpread = topSim - avgTop5
                    dynamicMin = max(0.10, avgTop5 - scoreSpread)
                    Log.info(
                        "[RAG] Vocabulary mismatch detected (topSim=\(String(format: "%.2f", topSim)), avgTop5=\(String(format: "%.2f", avgTop5))) - using adaptive floor \(String(format: "%.2f", dynamicMin))",
                        category: .retrieval
                    )
                } else if !lenient, avgTop5 > 0, avgTop5 < baseMin {
                    // Standard case: lower floor to preserve procedural/technical chunks
                    dynamicMin = max(0.15, avgTop5 - 0.05)
                }

                // Procedural document detection: procedural queries need HIGHER quality evidence
                // Wrong order in procedures is worse than no answer at all
                let proceduralTerms = ["how to", "steps", "procedure", "process", "reprocess", "instructions", "guide", "workflow"]
                let isProceduralQuery = proceduralTerms.contains { question.lowercased().contains($0) }
                if isProceduralQuery {
                    // Procedural queries require HIGHER thresholds, not lower
                    // If evidence is weak, we should abstain rather than guess steps
                    dynamicMin = max(dynamicMin, 0.25)
                    Log.info("[RAG] Procedural query detected - requiring higher evidence threshold \(dynamicMin)", category: .retrieval)
                }

                auditDynamicMin = dynamicMin
                var filteredChunks = await engine.filterBySimilarity(
                    chunks: rerankedChunks,
                    min: dynamicMin
                )

                // Acceptance override if relative signals are strong even with modest absolute scores
                // Also override for vocabulary mismatch scenarios where we trust relative ranking
                let acceptanceOverride: Bool =
                    vocabularyMismatch // Trust relative ranking when all scores are low
                        || (topSim >= 0.50)
                        || (topSim >= 0.38 && (topSim - avgTop5) >= 0.05)
                        || ((topSim - secondSim) >= 0.07)
                    || (topSim >= 0.15 && rerankedChunks.count >= 10) // Have corpus, use it
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

                    // SPEC PRESERVATION: For extractive queries, rescue chunks with actual specification values
                    // Cross-encoders often score table/spec chunks lower (sparse text, dense data)
                    // But these are exactly the chunks that contain the answer (e.g., "0W-20")
                    if answerIntent.isExtractiveFirst {
                        let filteredIds = Set(filteredChunks.map { $0.chunk.id })
                        let droppedChunks = rerankedChunks.filter { !filteredIds.contains($0.chunk.id) }

                        // Find dropped chunks with high spec scores
                        var rescuedChunks: [RetrievedChunk] = []
                        let specThreshold = 5  // Minimum spec pattern score to rescue

                        // Also scan ALL candidates for viscosity patterns (critical for oil queries)
                        let viscosityPattern = #"\d+[Ww]-\d+"#
                        var foundViscosityChunk = false

                        for chunk in rerankedChunks {
                            let content = chunk.chunk.parentContent ?? chunk.chunk.content
                            if let _ = content.range(of: viscosityPattern, options: .regularExpression) {
                                foundViscosityChunk = true
                                // If this chunk was filtered out, force rescue it
                                if !filteredIds.contains(chunk.chunk.id) {
                                    Log.info("   🔧 Viscosity spec found in filtered chunk: \(String(content.prefix(80)))...", category: .retrieval)
                                    rescuedChunks.insert(chunk, at: 0)  // Priority position
                                }
                            }
                        }

                        if !foundViscosityChunk && Log.pipelineTraceEnabled {
                            Log.warning("   ⚠️ No viscosity specs (e.g., 0W-20) found in ANY of \(rerankedChunks.count) reranked chunks!", category: .retrieval)
                        }

                        for chunk in droppedChunks {
                            let content = chunk.chunk.parentContent ?? chunk.chunk.content
                            let specScore = countSpecPatterns(content)

                            // Also check for table structure (specs often in tables)
                            let isTableChunk = chunk.chunk.metadata.structureType == "table" ||
                                               content.contains("|") && content.components(separatedBy: "|").count >= 4

                            // Rescue if high spec score OR table chunk with decent spec score
                            if specScore >= specThreshold || (isTableChunk && specScore >= 3) {
                                rescuedChunks.append(chunk)
                            }
                        }

                        if !rescuedChunks.isEmpty {
                            // Limit rescued chunks to prevent flooding
                            let maxRescue = min(5, rescuedChunks.count)
                            let topRescued = rescuedChunks.prefix(maxRescue)
                            filteredChunks.append(contentsOf: topRescued)

                            Log.info(
                                "   🔧 Spec preservation: rescued \(topRescued.count) spec-containing chunks for extractive query",
                                category: .retrieval
                            )
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Spec preservation",
                                metadata: [
                                    "rescued": "\(topRescued.count)",
                                    "intent": answerIntent.rawValue
                                ]
                            )
                        }
                    }
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
                var mmrTime: TimeInterval = 0 // Defined at outer scope for final logging

                var diverseChunks: [RetrievedChunk] = []
                var mmrLambda: Float = qualityModeMMRLambda // Default to quality mode value

                // Check if MMR is enabled for this quality mode
                if !qualityModeUsesMMR {
                    Log.info("[RAG] MMR diversification skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
                    diverseChunks = Array(filteredChunks.prefix(effectiveTopK))
                    auditMMRSelectedCount = diverseChunks.count
                    mmrTime = Date().timeIntervalSince(mmrStartTime)
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "MMR skipped",
                        metadata: ["reason": "quality_mode", "passed": "\(diverseChunks.count)"],
                        duration: mmrTime
                    )
                } else {
                    // Pipeline Trace: Step 4.5
                    Log.pipelineStep("4.5", title: "MMR Diversification", details: [
                        ("candidates", "\(filteredChunks.count)"),
                        ("targetK", "\(effectiveTopK)")
                    ])

                    // Procedural query override: favor relevance over diversity for step-by-step content
                    // Consecutive chunks from same document are valuable context, not redundant
                    // Note: isProceduralQuery already defined in Step 4.3
                    // Use quality mode lambda as base, override for procedural queries
                    mmrLambda = isProceduralQuery ? max(qualityModeMMRLambda, 0.85) : qualityModeMMRLambda
                    if isProceduralQuery {
                        Log.info("[RAG] Procedural query - boosting MMR lambda to \(mmrLambda) (favor sequential chunks)", category: .retrieval)
                    }

                    diverseChunks = await engine.applyMMR(
                        candidates: filteredChunks,
                        queryEmbedding: queryEmbedding,
                        topK: effectiveTopK, // Clamped for short queries
                        lambda: mmrLambda
                    )
                    auditMMRSelectedCount = diverseChunks.count
                    mmrTime = Date().timeIntervalSince(mmrStartTime)
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
                        .mmr,
                        title: "MMR diversity",
                        detail: "λ=\(String(format: "%.1f", mmrLambda)) • \(diverseChunks.count) selected"
                    )
                }

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

                // ═══════════════════════════════════════════════════════════════════════════════
                // 🔥 GOD MODE: Intelligent Document-Level Context for Research/Findings Queries
                // ═══════════════════════════════════════════════════════════════════════════════
                // When user asks "What did X find?", we need BOTH:
                // 1. Document summary (L1) for high-level context
                // 2. Most relevant detail chunks (L0) for specific findings
                //
                // Strategy:
                // - Reserve ~25% of token budget for summary (provides roadmap)
                // - Use remaining 75% for highest-relevance detail chunks
                // - Smart deduplication to avoid redundant content
                // - Dynamic chunk count based on available tokens
                // ═══════════════════════════════════════════════════════════════════════════════
                if answerIntent.requiresDocumentSummary, let allChunks = cachedAllChunks {
                    let summaryChunks = allChunks.filter { $0.metadata.abstractionLevel == .documentSummary }
                    let existingIds = Set(contextCandidates.map { $0.chunk.id })

                    // Get relevant document IDs from top candidates
                    let relevantDocIds = Set(contextCandidates.prefix(5).map { $0.chunk.documentId })

                    // Prioritize summaries from documents that appear in top results
                    let prioritizedSummaries = summaryChunks
                        .filter { !existingIds.contains($0.id) }
                        .sorted { chunk1, chunk2 in
                            let score1 = relevantDocIds.contains(chunk1.documentId) ? 1 : 0
                            let score2 = relevantDocIds.contains(chunk2.documentId) ? 1 : 0
                            return score1 > score2
                        }

                    if !prioritizedSummaries.isEmpty {
                        // Calculate token budget for summaries (~25% of total context)
                        // Average summary is ~150 words ≈ 200 tokens ≈ 600 chars
                        let estimatedContextBudget = 4000 // Conservative estimate for on-device
                        let summaryBudgetChars = estimatedContextBudget / 4 // 25% for summaries

                        // Select summaries that fit in budget, prioritizing relevant docs
                        var selectedSummaries: [RetrievedChunk] = []
                        var summaryCharsUsed = 0

                        for (index, chunk) in prioritizedSummaries.enumerated() {
                            let chunkChars = chunk.content.count
                            if summaryCharsUsed + chunkChars <= summaryBudgetChars || selectedSummaries.isEmpty {
                                // Assign high scores with decay for ordering
                                let score = Float(0.98 - (Double(index) * 0.02)) // 0.98, 0.96, 0.94...
                                // Look up document name from documents array
                                let docName = getDocumentName(for: chunk.documentId)
                                selectedSummaries.append(RetrievedChunk(
                                    chunk: chunk,
                                    similarityScore: score,
                                    rank: index,
                                    sourceDocument: docName,
                                    pageNumber: nil
                                ))
                                summaryCharsUsed += chunkChars
                            }
                            // Limit to max 3 summaries to leave room for detail chunks
                            if selectedSummaries.count >= 3 { break }
                        }

                        // Calculate how many detail chunks we can keep
                        let remainingBudgetChars = estimatedContextBudget - summaryCharsUsed
                        let avgDetailChunkChars = contextCandidates.isEmpty ? 400 :
                            contextCandidates.prefix(10).reduce(0) { $0 + $1.chunk.content.count } / min(10, contextCandidates.count)
                        let maxDetailChunks = max(3, remainingBudgetChars / max(avgDetailChunkChars, 200))

                        // Filter detail chunks to remove any that are substantially covered by summaries
                        // (Avoid redundant content - summaries already capture key points)
                        var detailCandidates = contextCandidates.filter { retrieved in
                            // Keep chunk if it's NOT a summary (L0 detail chunks)
                            retrieved.chunk.metadata.abstractionLevel != .documentSummary
                        }

                        // ═══════════════════════════════════════════════════════════════════
                        // 🔥 GOD MODE ENHANCEMENT: Author-Name Cross-Reference Boost
                        // If query contains a name, boost chunks from matching document
                        // ═══════════════════════════════════════════════════════════════════
                        let queryWords = question.split(separator: " ").map { String($0).lowercased() }
                        let potentialAuthorNames = queryWords.filter { word in
                            // Capitalized in original query, >2 chars, not common words
                            let originalWord = question.split(separator: " ").first { String($0).lowercased() == word }
                            let commonWords = Set(["what", "did", "does", "find", "show", "the", "and", "for", "how", "why"])
                            return originalWord?.first?.isUppercase == true &&
                                   word.count > 2 &&
                                   !commonWords.contains(word)
                        }

                        if !potentialAuthorNames.isEmpty {
                            // Boost chunks from documents that match author name in filename
                            detailCandidates = detailCandidates.sorted { a, b in
                                let aFile = a.sourceDocument.lowercased()
                                let bFile = b.sourceDocument.lowercased()
                                let aMatchCount = potentialAuthorNames.filter { aFile.contains($0) }.count
                                let bMatchCount = potentialAuthorNames.filter { bFile.contains($0) }.count

                                if aMatchCount != bMatchCount {
                                    return aMatchCount > bMatchCount // More matches = higher priority
                                }
                                return a.similarityScore > b.similarityScore // Fall back to similarity
                            }

                            let boostedCount = detailCandidates.prefix(maxDetailChunks).filter { chunk in
                                potentialAuthorNames.contains { chunk.sourceDocument.lowercased().contains($0) }
                            }.count

                            if boostedCount > 0 {
                                Log.debug("[GOD MODE] Author boost: \(boostedCount) chunks from '\(potentialAuthorNames.joined(separator: ", "))' documents", category: .retrieval)
                            }
                        }

                        // Take top N detail chunks by relevance score (now potentially author-boosted)
                        let topDetailChunks = Array(detailCandidates.prefix(maxDetailChunks))

                        // Merge: Summaries FIRST (high-level roadmap), then detail chunks
                        contextCandidates = selectedSummaries + topDetailChunks
                        contextStrategy = "god_mode_hybrid"

                        let totalChars = summaryCharsUsed + topDetailChunks.reduce(0) { $0 + $1.chunk.content.count }
                        Log.info(
                            "🔥 [GOD MODE] Hybrid context: \(selectedSummaries.count) summaries (\(summaryCharsUsed) chars) + " +
                            "\(topDetailChunks.count) detail chunks → \(totalChars) total chars",
                            category: .retrieval
                        )
                        emitThinkingEvent(
                            .context,
                            title: "GOD MODE: Hybrid Context",
                            detail: "\(selectedSummaries.count) summaries + \(topDetailChunks.count) details = comprehensive coverage"
                        )

                        if Log.pipelineTraceEnabled {
                            Log.debug("[GOD MODE] Summary budget: \(summaryBudgetChars) chars, used: \(summaryCharsUsed)", category: .retrieval)
                            Log.debug("[GOD MODE] Detail budget: \(remainingBudgetChars) chars, chunks: \(topDetailChunks.count)", category: .retrieval)
                            Log.debug("[GOD MODE] Avg detail chunk: \(avgDetailChunkChars) chars", category: .retrieval)
                        }
                    } else if !summaryChunks.isEmpty {
                        Log.debug("[GOD MODE] Summary chunks already in candidates - no injection needed", category: .retrieval)
                    } else {
                        Log.info("[GOD MODE] No summary chunks available - using detail-only retrieval", category: .retrieval)
                        emitThinkingEvent(
                            .context,
                            title: "GOD MODE: No summaries",
                            detail: "Re-ingest documents to enable summary-enhanced retrieval"
                        )
                    }
                }

                // Universal pipeline trace: log chunk content previews at each stage
                if Log.pipelineTraceEnabled {
                    logChunkTrace(diverseChunks, stage: "Post-MMR", query: question)
                }

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

                        if Log.pipelineTraceEnabled {
                            logChunkTrace(focused, stage: "Post-FocusedWindow", query: question)
                        }
                    }
                }

                // Step 4.6: Parent Document Retrieval (optional)
                // Expand matched chunks to include sibling context from same section/page
                // Respect quality mode toggle, user settings, AND adaptive pipeline (thermal/battery aware)
                let parentDocEnabledBySettings = settingsStore?.enableParentDocumentRetrieval ?? true
                let useParentDocRetrieval = qualityModeUsesParentDocRetrieval && parentDocEnabledBySettings && adaptiveConfig.enableParentDocumentRetrieval

                if useParentDocRetrieval, contextCandidates.count > 0, let allChunks = cachedAllChunks {
                    // Select parent config based on query type and quality mode
                    // Procedural queries get maximum expansion to capture full procedure sections
                    let proceduralTerms = ["how to", "steps", "procedure", "process", "reprocess", "instructions", "guide", "workflow"]
                    let isProceduralQuery = proceduralTerms.contains { question.lowercased().contains($0) }

                    // Create custom config with quality mode sibling limit
                    var parentConfig: ParentDocumentService.Config
                    if isProceduralQuery {
                        parentConfig = .procedural // 8 siblings, 6000 tokens, very permissive
                        Log.info("[RAG] Procedural query - using maximum parent expansion (8 siblings)", category: .retrieval)
                    } else if useAgentic {
                        parentConfig = .thorough
                    } else {
                        // Use quality mode sibling limit
                        parentConfig = ParentDocumentService.Config(
                            maxSiblingsPerSide: qualityModeMaxSiblingChunks,
                            maxExpandedTokens: 2000,
                            allowCrossPageExpansion: false,
                            minRelevanceForExpansion: 0.15
                        )
                    }
                    let parentService = ParentDocumentService(config: parentConfig)

                    let expansionResult = await parentService.expandWithSiblings(
                        retrievedChunks: contextCandidates,
                        allChunks: allChunks,
                        query: question
                    )

                    if expansionResult.addedSiblings > 0 {
                        contextCandidates = expansionResult.expandedChunks
                        contextStrategy = "parent_expanded"

                        TelemetryCenter.emit(
                            .retrieval,
                            title: "Parent document expansion",
                            metadata: [
                                "original": "\(expansionResult.originalChunks.count)",
                                "expanded": "\(expansionResult.expandedChunks.count)",
                                "siblings": "\(expansionResult.addedSiblings)",
                                "ratio": String(format: "%.2f", expansionResult.expansionRatio),
                            ]
                        )

                        emitThinkingEvent(
                            .context,
                            title: "Parent context expanded",
                            detail: "+\(expansionResult.addedSiblings) siblings • \(expansionResult.expandedChunks.count) total chunks"
                        )

                        Log.info(
                            "📚 Parent document expansion: \(expansionResult.originalChunks.count) → \(expansionResult.expandedChunks.count) chunks (+\(expansionResult.addedSiblings) siblings)",
                            category: .retrieval
                        )

                        if Log.pipelineTraceEnabled {
                            logChunkTrace(expansionResult.expandedChunks, stage: "Post-ParentExpansion", query: question)
                        }
                    }
                }

                // Step 4.7: Contextual Compression (optional)
                // Extract only query-relevant sentences from chunks to maximize signal and save tokens
                // Respect quality mode toggle, user settings, AND adaptive pipeline (thermal/battery aware)
                // CRITICAL: Skip compression for procedural queries - compression destroys step ordering
                // (e.g., 335→27 tokens = 8% retention loses critical procedural constraints)
                // CRITICAL: Skip compression for vocabulary mismatch - compressor can't judge relevance
                // when query terms don't match document vocabulary (conversational vs technical)
                // CRITICAL: Skip compression for parent-expanded content - parent chunks are too large
                // for compression model (exceed context window) AND compression defeats hierarchical purpose
                let compressionEnabledBySettings = settingsStore?.enableContextualCompression ?? true
                let skipCompressionForProcedural = isProceduralQuery // Preserve contiguous spans
                let skipCompressionForVocabMismatch = vocabularyMismatch // Compressor will destroy content
                let skipCompressionForParentExpansion = contextStrategy == "parent_expanded" // Chunks too large + defeats purpose
                let useContextualCompression = qualityModeUsesContextualCompression && compressionEnabledBySettings && adaptiveConfig.enableContextualCompression && !skipCompressionForProcedural && !skipCompressionForVocabMismatch && !skipCompressionForParentExpansion
                var compressionSavings = 0

                if skipCompressionForProcedural {
                    Log.info("[RAG] Skipping compression for procedural query - preserving contiguous spans", category: .retrieval)
                }

                if skipCompressionForVocabMismatch {
                    Log.info("[RAG] Skipping compression for vocabulary mismatch - compressor can't judge relevance", category: .retrieval)
                }

                if skipCompressionForParentExpansion {
                    Log.info("[RAG] Skipping compression for parent-expanded content - chunks exceed compression model capacity", category: .retrieval)
                }

                if useContextualCompression, HyDEService.isAvailable, contextCandidates.count > 0 {
                    let compressionService = ContextualCompressionService()
                    let chunkTexts = contextCandidates.map { $0.chunk.text }

                    // Select compression config based on query type
                    // "exactly", "detail", "comprehensive", "all about" → verbose (minimal compression)
                    // Simple factual lookups → default (moderate compression)
                    let queryLower = question.lowercased()
                    let wantsComprehensiveAnswer = queryLower.contains("exactly") ||
                        queryLower.contains("detail") ||
                        queryLower.contains("comprehensive") ||
                        queryLower.contains("everything about") ||
                        queryLower.contains("all about") ||
                        queryLower.contains("explain") ||
                        queryLower.contains("tell me about") ||
                        answerIntent == .investigate ||
                        answerIntent == .compare

                    let compressionConfig: ContextualCompressionService.Config = wantsComprehensiveAnswer ? .verbose : .default

                    if wantsComprehensiveAnswer {
                        Log.info("[RAG] Using verbose compression for comprehensive query", category: .retrieval)
                    }

                    do {
                        let compressionStartTime = Date()
                        let compressionResults = try await compressionService.compressChunks(
                            chunkTexts,
                            forQuery: question,
                            config: compressionConfig
                        )
                        let compressionTime = Date().timeIntervalSince(compressionStartTime)

                        // Update chunk texts with compressed content
                        var updatedCandidates: [RetrievedChunk] = []
                        for (index, result) in compressionResults.enumerated() where index < contextCandidates.count {
                            let original = contextCandidates[index]
                            let effectiveText = result.effectiveContent

                            // Log if compression marked chunk as low-relevance (but we keep a fallback)
                            if result.wasMarkedIrrelevant {
                                Log.debug("[Compression] Chunk marked low-relevance, keeping truncated fallback: \(original.chunk.text.prefix(50))...", category: .retrieval)
                            }

                            // Create updated chunk with compressed text
                            var compressedChunk = original.chunk
                            compressedChunk.text = effectiveText
                            updatedCandidates.append(RetrievedChunk(
                                chunk: compressedChunk,
                                similarityScore: original.similarityScore,
                                rank: original.rank,
                                sourceDocument: original.sourceDocument,
                                pageNumber: original.pageNumber
                            ))
                        }

                        let originalTokens = compressionResults.reduce(0) { $0 + $1.originalTokens }
                        let compressedTokens = compressionResults.reduce(0) { $0 + $1.compressedTokens }
                        let lowRelevanceCount = compressionResults.filter { $0.wasMarkedIrrelevant }.count
                        compressionSavings = originalTokens - compressedTokens

                        if updatedCandidates.count > 0 {
                            contextCandidates = updatedCandidates
                            let lowRelNote = lowRelevanceCount > 0 ? " (\(lowRelevanceCount) fallback)" : ""
                            Log.info("[Compression] \(originalTokens)→\(compressedTokens) tokens saved \(compressionSavings) in \(String(format: "%.0f", compressionTime * 1000))ms\(lowRelNote)", category: .retrieval)
                            emitThinkingEvent(
                                .context,
                                title: "Context compressed",
                                detail: "Saved \(compressionSavings) tokens • \(contextCandidates.count) chunks"
                            )
                        }
                    } catch {
                        // Safety filter or other compression failures - keep ALL original chunks intact
                        // This is critical for procedural content that may trigger false positives
                        Log.warning("[Compression] Failed, using original chunks: \(error.localizedDescription)", category: .retrieval)
                        Log.info("[Compression] Preserving all \(contextCandidates.count) original chunks for procedural safety", category: .retrieval)
                    }
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 4.9: Graph-Based Context Packing (AppleRAG §5)
                // pack(R + parents(R) + neighbors(R,±1) + graphHops(R,1))
                // Expands retrieved chunks with graph context for richer LLM input
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                // Universal pipeline trace: log chunk content before graph packing
                if Log.pipelineTraceEnabled {
                    logChunkTrace(contextCandidates, stage: "Pre-GraphPack", query: question)
                }

                if answerIntent.benefitsFromMultiHop, let allChunks = cachedAllChunks {
                    let graphPackingStart = Date()

                    // Build graph edges for document traversal
                    let graphEdges = graphIndexService.buildDocumentGraph(chunks: allChunks)

                    // Build lookup table
                    var chunkLookup: [UUID: DocumentChunk] = [:]
                    for chunk in allChunks {
                        chunkLookup[chunk.id] = chunk
                    }

                    // Extract core chunks from candidates
                    let coreChunks = contextCandidates.map { $0.chunk }

                    // Calculate token budget based on model context (conservative for Apple FM)
                    let graphTokenBudget = isAppleFMOnDevice ? 3000 : 6000

                    // Pack with graph context
                    let packedContext = await contextPackingService.pack(
                        retrievedChunks: coreChunks,
                        graphEdges: graphEdges,
                        allChunks: chunkLookup,
                        tokenBudget: graphTokenBudget,
                        neighborDistance: answerIntent.benefitsFromMultiHop ? 1 : 0,
                        graphHopDistance: answerIntent.benefitsFromMultiHop ? 1 : 0
                    )

                    let graphPackingTime = Date().timeIntervalSince(graphPackingStart)

                    // Update candidates with packed chunks (convert back to RetrievedChunk)
                    if packedContext.contextChunkCount > 0 {
                        var packedCandidates: [RetrievedChunk] = []
                        for (index, chunk) in packedContext.chunks.enumerated() {
                            // Find original score if this was a core chunk, else assign lower score
                            let originalScore = contextCandidates.first { $0.chunk.id == chunk.id }?.similarityScore ?? 0.3
                            packedCandidates.append(RetrievedChunk(
                                chunk: chunk,
                                similarityScore: originalScore,
                                rank: index,
                                sourceDocument: contextCandidates.first { $0.chunk.id == chunk.id }?.sourceDocument ?? "",
                                pageNumber: chunk.metadata.pageNumber
                            ))
                        }
                        contextCandidates = packedCandidates

                        Log.info(
                            "[GraphPack] \(packedContext.coreChunkCount) core + \(packedContext.contextChunkCount) context chunks (\(packedContext.estimatedTokens) tokens) in \(String(format: "%.0f", graphPackingTime * 1000))ms\(packedContext.wasTruncated ? " [truncated]" : "")",
                            category: .retrieval
                        )

                        // Universal pipeline trace: log chunks after graph packing
                        if Log.pipelineTraceEnabled {
                            logChunkTrace(packedCandidates, stage: "Post-GraphPack", query: question)
                        }

                        emitThinkingEvent(
                            .graphPack,
                            title: "Graph context packed",
                            detail: "+\(packedContext.contextChunkCount) neighbors/refs"
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

                // CRITICAL: Token estimation was off by ~2x (estimated 3056, actual 5994)
                // Apple FM tokenizer is more aggressive than typical 2.5 chars/token
                // Using 1.4 chars/token for Apple FM (empirically observed ratio)
                // Safety is applied ONCE at the end, not per-component (avoids compound paranoia)
                let conservativeCharsPerToken: Double = isAppleFMOnDevice ? 1.4 : 2.5

                func estimateTokens(chars: Int) -> Int {
                    max(1, Int(ceil(Double(chars) / conservativeCharsPerToken)))
                }

                // CRITICAL: Apple FM (both on-device AND PCC) has a hard 4096 token limit.
                // Despite documentation suggesting PCC supports 65k, real-world testing shows
                // PCC fails with "Context length of 4096 was exceeded" when input exceeds 4096 tokens.
                // ALWAYS use 4096 as the base window to avoid overflow-then-retry loops.
                let baseWindowTokens: Int = {
                    if llmService is AppleFoundationLLMService {
                        // Always use 4096 - PCC does NOT reliably support larger contexts
                        return 4096
                    }
                    return inferenceConfig.contextLength ?? 4096
                }()

                // Token estimation for budget calculation (no compound safety factors)
                func estimateTokensConservative(chars: Int) -> Int {
                    max(1, Int(ceil(Double(chars) / conservativeCharsPerToken)))
                }

                // Single safety margin: 15% of window + 200 flat buffer
                // This replaces the previous compound safety (1.6x factor + 800 buffer)
                let safetyTokens = isAppleFMOnDevice ? 400 : 300
                let systemPromptTokens = estimateTokensConservative(chars: (inferenceConfig.systemPrompt ?? "").count)
                let promptOverheadTokens = 120 + systemPromptTokens // Template overhead
                let questionTokens = estimateTokensConservative(chars: question.count)

                // Reserve room for output
                let reservedOutputTokens = max(150, min(inferenceConfig.maxTokens, 300))

                // Calculate available tokens, then apply ONE 15% safety haircut at the end
                let rawAvailableTokens = baseWindowTokens - promptOverheadTokens - questionTokens - reservedOutputTokens
                let globalSafetyFactor: Double = isAppleFMOnDevice ? 0.85 : 0.90 // 15% or 10% safety margin
                let availableForContextTokens = max(
                    0,
                    Int(Double(rawAvailableTokens) * globalSafetyFactor) - safetyTokens
                )
                let cappedContextTokens = applyTrivialCaps
                    ? min(availableForContextTokens, 2600)
                    : availableForContextTokens
                // Char limits: with 1.4 chars/token and 15% safety, we can use more context
                // Target: ~2800 tokens * 1.4 = ~3900 chars (non-trivial)
                // Trivial cap: ~1800 tokens * 1.4 = ~2500 chars
                let maxContextCharsCap = isAppleFMOnDevice
                    ? (applyTrivialCaps ? 2500 : 5500):
                        applyTrivialCaps ? 6000 : 10000
                let maxContextChars = min(
                    max(800, Int(Double(cappedContextTokens) * conservativeCharsPerToken)),
                    maxContextCharsCap
                )

                // Use compact mode for Apple FM to maximize content in limited space
                let useCompactMode = isAppleFMOnDevice

                #if targetEnvironment(simulator)
                    Log.info("[RAG] Simulator mode: using on-device context budget (4096 tokens, \(maxContextChars) chars)", category: .pipeline)
                #endif

                Log.debug("Context budget: base=\(baseWindowTokens), question=\(questionTokens), available=\(availableForContextTokens) tokens → \(maxContextChars) chars, compact=\(useCompactMode)", category: .pipeline)

                // For procedural queries, preserve document order instead of relevance order
                // This prevents sequence inversions (e.g., "dry before disinfect" errors)
                let orderedCandidates: [RetrievedChunk]
                if isProceduralQuery {
                    // Sort by document ID then chunk index to preserve original document sequence
                    orderedCandidates = contextCandidates.sorted(by: { (a: RetrievedChunk, b: RetrievedChunk) -> Bool in
                        if a.chunk.documentId == b.chunk.documentId {
                            return a.chunk.metadata.chunkIndex < b.chunk.metadata.chunkIndex
                        }
                        // Group by document, then by first appearance order
                        return a.rank < b.rank
                    })
                    Log.info("[RAG] Procedural query - preserving document order for sequence fidelity", category: .retrieval)
                } else if answerIntent.isExtractiveFirst {
                    // For lookup/table queries, prioritize chunks containing specifications
                    // This ensures the actual answer (e.g., "0W-20") is included even if context is truncated
                    orderedCandidates = contextCandidates.sorted(by: { (a: RetrievedChunk, b: RetrievedChunk) -> Bool in
                        let aContent = a.chunk.parentContent ?? a.chunk.content
                        let bContent = b.chunk.parentContent ?? b.chunk.content

                        // Count spec-like patterns: numbers, measurements, codes
                        let aSpecScore = countSpecPatterns(aContent)
                        let bSpecScore = countSpecPatterns(bContent)

                        // ENHANCED: Also heavily weight table structure for spec queries
                        // Tables are prime locations for specification data
                        let aIsTable = a.chunk.metadata.structureType == "table" ||
                                       (aContent.contains("|") && aContent.components(separatedBy: "|").count >= 4)
                        let bIsTable = b.chunk.metadata.structureType == "table" ||
                                       (bContent.contains("|") && bContent.components(separatedBy: "|").count >= 4)

                        // Compute composite priority score
                        // Tables with specs are highest priority, then high spec count, then relevance
                        let aTableBonus = aIsTable ? 10 : 0
                        let bTableBonus = bIsTable ? 10 : 0
                        let aPriority = aSpecScore + aTableBonus
                        let bPriority = bSpecScore + bTableBonus

                        // If one has clear spec/table advantage, prioritize it
                        // Lower threshold (2 instead of 3) to be more aggressive
                        if abs(aPriority - bPriority) >= 2 {
                            return aPriority > bPriority
                        }
                        // Otherwise, maintain relevance order
                        return a.similarityScore > b.similarityScore
                    })
                    Log.info("[RAG] Extractive query - prioritizing chunks with specifications", category: .retrieval)
                } else {
                    orderedCandidates = contextCandidates
                }

                // For procedural queries, disable "Lost in Middle" reordering to preserve sequence
                let useLostInMiddleMitigation = !isProceduralQuery

                let (context, actualChunksUsed) = await engine.assembleContext(
                    chunks: orderedCandidates,
                    maxChars: maxContextChars,
                    compact: useCompactMode,
                    useLostInMiddleMitigation: useLostInMiddleMitigation
                )

                // Universal pipeline trace: log final assembled context
                if Log.pipelineTraceEnabled {
                    logFinalContext(context, actualChunksUsed: actualChunksUsed, query: question)
                }

                // Emit lost-in-middle event if it was applied
                if useLostInMiddleMitigation && orderedCandidates.count >= 4 {
                    emitThinkingEvent(
                        .lostInMiddle,
                        title: "Position reorder",
                        detail: "Attention-optimal placement"
                    )
                }

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

                // Pipeline Trace: Step 5
                Log.pipelineStep("5", title: "Context Assembly", details: [
                    ("chunks", "\(actualChunksUsed)"),
                    ("words", "\(contextWords)"),
                    ("chars", "\(contextSize)")
                ])

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
                    qualityModeName: qualityModeDisplayName,
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

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // HARD RELEVANCE GATE: Check if retrieved content is actually relevant
                // Prevents hallucination when retrieval returns garbage
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let lexicalRelevance = checkLexicalRelevance(query: effectiveQuery, chunks: includedRetrievedChunks)
                let bestSimilarity = includedRetrievedChunks.first?.similarityScore ?? 0

                if lexicalRelevance < 0.1 && bestSimilarity < 0.3 {
                    Log.warning("[RAG] Hard exit: Retrieved content is irrelevant (lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), similarity=\(String(format: "%.2f", bestSimilarity)))", category: .retrieval)

                    emitThinkingEvent(
                        .warning,
                        title: "Content not found",
                        detail: "Retrieved content doesn't match query"
                    )

                    let notFoundMetadata = ResponseMetadata(
                        timeToFirstToken: nil,
                        totalGenerationTime: 0,
                        tokensGenerated: 0,
                        tokensPerSecond: nil,
                        modelUsed: "none",
                        retrievalTime: retrievalTime,
                        retrievalConfigSummary: retrievalConfig.summary,
                        gatingDecision: "relevance_gate_failed",
                        toolCallsMade: 0,
                        embeddingProvider: embeddingProviderId
                    )

                    let notFoundResponse = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: [],
                        generatedResponse: "I couldn't find relevant information about this topic in your documents. The retrieved content was about different subjects.",
                        metadata: notFoundMetadata,
                        confidenceScore: 0.0,
                        qualityWarnings: ["Relevance gate failed: retrieved content doesn't match query"]
                    )

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: notFoundResponse
                    )
                }

                // EVIDENCE-FIRST GATE: Check retrieval quality BEFORE generation
                // If evidence is weak, switch to Evidence-First mode instead of generating verbosely
                // Key insight: P(all claims correct) = p^N where N = number of claims
                // With weak evidence (p=0.92) and N=50 claims: 0.92^50 ≈ 1.5% chance of being fully correct
                let bestRetrievalSim = includedRetrievedChunks.first?.similarityScore ?? 0
                let avgRetrievalSim = includedRetrievedChunks.isEmpty ? 0 :
                    includedRetrievedChunks.map { $0.similarityScore }.reduce(0, +) / Float(includedRetrievedChunks.count)
                let uniqueSourceDocs = Set(includedRetrievedChunks.map { $0.chunk.documentId }).count

                // Pre-generation confidence estimate
                let preGenConfidence: Float = {
                    var score: Float = 0.5
                    if bestRetrievalSim >= 0.35 { score += 0.15 }
                    if avgRetrievalSim >= 0.28 { score += 0.10 }
                    if uniqueSourceDocs >= 2 { score += 0.10 }
                    if actualChunksUsed >= 5 { score += 0.10 }
                    return min(1.0, score)
                }()

                // Evidence-First mode triggers:
                // 1. Best similarity below threshold
                // 2. Low pre-generation confidence
                // 3. Average top-5 similarity below the dynamic minimum (key insight: if avgTop5 < dynamicMin, evidence is weak)
                let avgTop5BelowThreshold = auditAvgTop5 < auditDynamicMin
                let evidenceIsWeak = bestRetrievalSim < 0.25 || preGenConfidence < 0.70 || avgTop5BelowThreshold
                let useEvidenceFirstMode = evidenceIsWeak && isProceduralQuery

                if useEvidenceFirstMode {
                    let triggerReason: String
                    if avgTop5BelowThreshold {
                        triggerReason = "avgTop5 (\(String(format: "%.2f", auditAvgTop5))) < dynamicMin (\(String(format: "%.2f", auditDynamicMin)))"
                    } else if bestRetrievalSim < 0.25 {
                        triggerReason = "bestSim (\(String(format: "%.2f", bestRetrievalSim))) < 0.25"
                    } else {
                        triggerReason = "preGenConf (\(String(format: "%.2f", preGenConfidence))) < 0.70"
                    }
                    Log.warning("[RAG] Evidence-First mode triggered: \(triggerReason)", category: .retrieval)
                    emitThinkingEvent(
                        .warning,
                        title: "Evidence-First mode",
                        detail: "Low confidence (\(String(format: "%.0f", preGenConfidence * 100))%) - \(triggerReason)"
                    )
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 5.9: Extractive Summarization (AppleRAG §6)
                // For .summarize intent, use extractive selection to minimize hallucination
                // This bypasses LLM generation entirely for pure summarization queries
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                if answerIntent == .summarize && answerIntent.isExtractiveFirst {
                    Log.section("Step 5.9: Extractive Summarization", level: .info, category: .pipeline)
                    let extractiveStart = Date()

                    do {
                        let summary = try await extractiveSummarizationService.summarize(
                            query: effectiveQuery,
                            chunks: includedRetrievedChunks,
                            maxWords: 300
                        )

                        let extractiveTime = Date().timeIntervalSince(extractiveStart)

                        Log.info(
                            "[Extractive] \(summary.sentences.count) sentences, \(summary.wordCount) words, coverage: \(String(format: "%.0f", summary.coverageScore * 100))% in \(String(format: "%.0f", extractiveTime * 1000))ms",
                            category: .retrieval
                        )

                        emitThinkingEvent(
                            .extractive,
                            title: "Extractive summary",
                            detail: "\(summary.sentences.count) sentences • \(summary.wordCount) words"
                        )

                        // Build response directly from extractive summary
                        let extractiveMetadata = ResponseMetadata(
                            timeToFirstToken: nil,
                            totalGenerationTime: extractiveTime,
                            tokensGenerated: summary.wordCount,
                            tokensPerSecond: nil,
                            modelUsed: "extractive",
                            retrievalTime: retrievalTime,
                            retrievalConfigSummary: "extractive_summarization",
                            gatingDecision: "extractive_intent",
                            toolCallsMade: nil
                        )

                        let extractiveResponse = RAGResponse(
                            queryId: ragQueryValue.id,
                            retrievedChunks: includedRetrievedChunks,
                            generatedResponse: summary.summaryText,
                            metadata: extractiveMetadata,
                            confidenceScore: summary.coverageScore,
                            qualityWarnings: []
                        )

                        Log.info("✓ Extractive summary complete (\(summary.wordCount) words)", category: .pipeline)

                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: extractiveResponse
                        )
                    } catch {
                        Log.warning("[Extractive] Summarization failed, falling back to LLM: \(error.localizedDescription)", category: .retrieval)
                        // Fall through to LLM generation
                    }
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 5.10: Extractive QA for Lookup Queries (AppleRAG §6b)
                // For .lookup and .tableLookup intents, extract answer directly from text
                // This prevents LLM hallucination for factual specifications
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                if (answerIntent == .lookup || answerIntent == .tableLookup) && answerIntent.isExtractiveFirst {
                    Log.section("Step 5.10: Extractive QA", level: .info, category: .pipeline)
                    let extractiveQAStart = Date()

                    let extractionResult = await specificationExtractor.extract(
                        query: effectiveQuery,
                        chunks: includedRetrievedChunks,
                        answerIntent: answerIntent
                    )

                    switch extractionResult {
                    case .success(let extraction):
                        let extractiveQATime = Date().timeIntervalSince(extractiveQAStart)

                        Log.info(
                            "[ExtractiveQA] Found: '\(extraction.answerSpan)' (confidence: \(String(format: "%.0f", extraction.confidence * 100))%, type: \(extraction.specificationType)) in \(String(format: "%.0f", extractiveQATime * 1000))ms",
                            category: .retrieval
                        )

                        emitThinkingEvent(
                            .extractive,
                            title: "Extracted specification",
                            detail: "'\(extraction.answerSpan)' • \(String(format: "%.0f", extraction.confidence * 100))% confidence"
                        )

                        // Build response directly from extraction with citation
                        let extractiveQAMetadata = ResponseMetadata(
                            timeToFirstToken: nil,
                            totalGenerationTime: extractiveQATime,
                            tokensGenerated: extraction.answerSpan.split(separator: " ").count,
                            tokensPerSecond: nil,
                            modelUsed: "extractive_qa",
                            retrievalTime: retrievalTime,
                            retrievalConfigSummary: "extractive_lookup",
                            gatingDecision: "extractive_qa_success",
                            toolCallsMade: nil
                        )

                        // Format the extracted answer with citation
                        let formattedAnswer = "**\(extraction.answerSpan)**\n\n_\(extraction.citation)_"

                        let extractiveQAResponse = RAGResponse(
                            queryId: ragQueryValue.id,
                            retrievedChunks: includedRetrievedChunks,
                            generatedResponse: formattedAnswer,
                            metadata: extractiveQAMetadata,
                            confidenceScore: extraction.confidence,
                            qualityWarnings: []
                        )

                        Log.info("✓ Extractive QA complete: '\(extraction.answerSpan)'", category: .pipeline)

                        return await finalizeResponse(
                            query: question,
                            containerId: selectedId,
                            containerName: selectedName,
                            response: extractiveQAResponse
                        )

                    case .failure(let failure):
                        // Log the failure reason but fall through to LLM
                        let failureReason: String
                        switch failure {
                        case .noSpecsFound:
                            failureReason = "no specifications found in chunks"
                        case .noKeywordMatch:
                            failureReason = "no query keyword matches found"
                        case .lowConfidence(let bestMatch, let confidence):
                            failureReason = "low confidence (\(String(format: "%.0f", confidence * 100))%) for '\(bestMatch)'"
                        case .ambiguousMultiple(let candidates):
                            failureReason = "ambiguous - \(candidates.count) candidates: \(candidates.joined(separator: ", "))"
                        case .notLookupQuery:
                            failureReason = "not a lookup-style query"
                        }
                        Log.warning("[ExtractiveQA] Falling back to LLM: \(failureReason)", category: .retrieval)
                        emitThinkingEvent(
                            .intentRoute,
                            title: "Extractive QA fallback",
                            detail: failureReason
                        )
                        // Fall through to constrained LLM generation
                    }
                }

                // Step 6: Generate response using LLM with augmented context
                Log.section("Step 6: LLM Generation", level: .info, category: .pipeline)

                // Pipeline Trace: Step 6
                let llmModelName = llmService.modelName
                Log.pipelineStep("6", title: "LLM Generation", details: [
                    ("model", llmModelName),
                    ("context", "\(contextWords)w")
                ])

                // Apply thermal cooldown before heavy LLM generation if device is under pressure
                // This prevents throttling and improves generation quality on hot devices
                await AdaptivePipelineOptimizer.shared.applyCooldown()

                let generationStartTime = Date()

                var genConfig = inferenceConfig

                // Set explicit system prompt for RAG to ensure comprehensive, ACCURATE answers
                // Keep concise to maximize context budget (every 100 chars = ~70 tokens)

                // Customize prompt based on answer intent (AppleRAG §3)
                let intentSpecificInstructions: String
                switch answerIntent {
                case .lookup, .tableLookup:
                    intentSpecificInstructions = """
                    EXTRACTION MODE: The user wants a specific value, specification, or fact.
                    - Extract the EXACT value (numbers, units, product names, specifications)
                    - Example: If asked "what oil?" answer "5W-30 synthetic" NOT "engine oil"
                    - Include the specific measurement, rating, or identifier from the source
                    """
                case .procedure:
                    intentSpecificInstructions = """
                    PROCEDURE MODE: The user wants step-by-step instructions.
                    - List ALL steps in the EXACT order from the source
                    - Include warnings, prerequisites, and tools needed
                    - Number each step clearly
                    """
                case .compare:
                    intentSpecificInstructions = """
                    COMPARISON MODE: The user wants to compare options.
                    - Create a clear comparison of the options found
                    - Highlight differences and similarities
                    - Use a structured format (bullets or table-style)
                    """
                case .summarize:
                    intentSpecificInstructions = """
                    SUMMARY MODE: Provide a comprehensive overview.
                    - Cover all major points from the excerpts
                    - Organize by theme or importance
                    """
                case .investigate, .compute:
                    intentSpecificInstructions = """
                    ANALYSIS MODE: The user needs deeper investigation.
                    - Synthesize information across sources
                    - Show your reasoning and connections
                    """
                case .findings:
                    intentSpecificInstructions = """
                    RESEARCH FINDINGS MODE: The user wants to understand what a researcher/author discovered.
                    - Summarize the KEY FINDINGS, conclusions, and contributions
                    - Explain the main thesis, arguments, and evidence presented
                    - Include methodology and results if relevant
                    - Connect specific claims to the document summary and detail excerpts
                    - Name the researchers and their specific contributions
                    """
                }

                genConfig.systemPrompt = """
                You are an expert research analyst. Answer using the provided document excerpts labeled [S1], [S2], etc.

                \(intentSpecificInstructions)

                Rules:
                1. Base answers on the excerpts provided
                2. Cite sources: [S1], [S2] (cite at least one)
                3. Connect user terms to related concepts in excerpts (e.g., "button" may mean switch, toggle, control)
                4. For procedures: preserve the exact sequence and include all steps
                5. Be thorough - provide as much relevant detail as excerpts contain
                6. If the question is vague, INTERPRET it based on document topics and provide relevant findings
                7. NEVER say "I don't have information" or "documents don't contain" - always provide what IS there
                """

                // Evidence-First mode: use detailed cautious prompt with full procedural rules
                if useEvidenceFirstMode {
                    genConfig.systemPrompt = """
                    You are an expert research analyst in EVIDENCE-FIRST MODE due to low retrieval confidence.

                        CRITICAL: Use ONLY the provided excerpts labeled[S1], [S2], etc.
                        Do NOT search for additional information.

                        EVIDENCE RULES:
                        1.ONLY state what is DIRECTLY quoted or clearly supported by excerpts
                    2.Cite every claim with[S1], [S2], etc.
                        3.Explicitly list what excerpts do NOT contain(gaps in evidence)
                    4.Do NOT fill gaps with assumptions or general knowledge
                    5.Keep response focused - only supported facts, not speculation

                        FOR PROCEDURES:
                            - NEVER INVERT TEMPORAL ORDER: If source says "A then B then C", output A → B → C
                            - PRESERVE PHASE BOUNDARIES: Don't merge distinct phases
                            - NEVER OMIT MAJOR STEPS: Include every action verb(clean, disinfect, rinse, etc.)
                            - DISTINGUISH PRECONDITIONS FROM STEPS

                    FORMAT:
                    ## What the sources show:
                    [Cite only directly supported information]

                    ## What appears to be missing:
                    [List gaps in the evidence]

                    ## Confidence note:
                    [Brief statement about evidence quality]
                    """
                    // Lower temperature for more conservative output
                    genConfig.temperature = min(genConfig.temperature, 0.2)
                    Log.info("[RAG] Using Evidence-First prompt (cautious mode)", category: .llm)
                }

                // Use adaptive mode's temperature
                genConfig.temperature = min(genConfig.temperature, qualityModeTemperature)

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

                // For procedural queries, ensure adequate tokens to avoid continuation chains
                // Continuations increase hallucination risk as second pass "fills gaps" creatively
                if isProceduralQuery, genConfig.maxTokens < 600 {
                    let boosted = min(availableForOutput, 600)
                    if boosted > genConfig.maxTokens {
                        Log.info("[RAG] Procedural query - boosting maxTokens \(genConfig.maxTokens) → \(boosted) to avoid continuations", category: .llm)
                        genConfig.maxTokens = boosted
                    }
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

                // Inject conversational history to support follow-up questions
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

                // Use ConversationMemoryService for enhanced context if enabled
                let useConversationMemory = settingsStore?.enableConversationMemory ?? true
                var historyContext = ""

                if #available(iOS 26.0, *), useConversationMemory {
                    // Get intelligent memory context with summarization
                    // DYNAMIC: Pass question for semantic relevance scoring and adaptive budgeting
                    let memoryContext = ConversationMemoryService.shared.contextInjection(for: selectedId, query: question)
                    if !memoryContext.isEmpty {
                        historyContext = memoryContext + "\nCURRENT QUESTION: "
                        Log.debug("[ConversationMemory] Injected memory context (\(memoryContext.count) chars)", category: .retrieval)
                    }
                }

                // Fallback to simple history if memory service didn't provide context
                if historyContext.isEmpty, !previousMessages.isEmpty {
                    historyContext = "PREVIOUS CONVERSATION:\n" + previousMessages.map {
                        let role = $0.role == .user ? "User" : "Assistant"
                        // Truncate long history items to preserve token budget for RAG context
                        let content = $0.content.replacingOccurrences(of: "\n", with: " ")
                        let truncated = content.count > 300 ? String(content.prefix(300)) + "..." : content
                        return "\(role): \(truncated)"
                    }.joined(separator: "\n") + "\n\nCURRENT QUESTION: "
                }

                let requiresCitations = retrievalConfig.requireExplicitCitations
                    || qualityModeRequiresCitations
                // System prompt already contains citation and format instructions
                // Don't add conflicting instructions that cause overly brief responses
                let promptForGeneration: String = historyContext + question

                // Attempt generation with retry on context-overflow
                var llmResponse: LLMResponse
                var generationContext = context
                var generationChunks = includedChunks
                var generationRetrievedChunks = includedRetrievedChunks
                var usedOverflowRetry = false

                // Track reasoning trace from chained sessions (for UI display)
                var reasoningTraceForMetadata: [String]? = nil

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // REASONING CHAIN: Reserved for Deep Think and Maximum modes
                // Standard mode uses single-session generation for speed
                // Deep Think: 3 sessions (Fact → Analysis → Synthesis)
                // Maximum: 8-20+ sessions until 98% confident
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let forceChain = settingsStore?.forceReasoningChain ?? false
                let useReasoningChain: Bool = {
                    // Only use for Apple Foundation Models (reasoning chain uses FM-specific features)
                    guard llmService is AppleFoundationLLMService else { return false }

                    // If force enabled in settings, skip other checks
                    if forceChain {
                        Log.info("[RAG] Reasoning chain FORCED via settings", category: .pipeline)
                        return true
                    }

                    // CRITICAL: Standard mode does NOT use reasoning chain
                    // Users must select Deep Think or Maximum for multi-session reasoning
                    guard qualityMode.usesAgenticOrchestrator else {
                        return false
                    }

                    // Skip if evidence is weak (Evidence-First mode handles this)
                    guard !useEvidenceFirstMode else { return false }

                    // Skip trivial queries - they don't benefit from multi-session
                    guard !isTrivial else { return false }

                    // Need some retrieval quality
                    guard bestRetrievalSim >= 0.25 else { return false }

                    // Need some context to benefit from chaining
                    guard contextSize > 500 else { return false }

                    // Need at least 2 chunks to distribute across sessions
                    guard includedRetrievedChunks.count >= 2 else { return false }

                    return true
                }()

                if useReasoningChain {
                    Log.info("[RAG] ✨ REASONING CHAIN ACTIVATED (3 sessions × 4096 = 12K+ effective tokens)", category: .pipeline)
                    Log.info("[RAG]   - bestRetrievalSim: \(bestRetrievalSim)", category: .pipeline)
                    Log.info("[RAG]   - contextSize: \(contextSize)", category: .pipeline)
                    Log.info("[RAG]   - chunks: \(includedRetrievedChunks.count)", category: .pipeline)
                    emitThinkingEvent(
                        .planning,
                        title: "🔗 Reasoning chain",
                        detail: "3 sessions × 4K = 12K+ effective context"
                    )

                    // Track reasoning trace for UI display
                    var chainReasoningTrace: [String]? = nil

                    // Execute reasoning chain with live thinking updates
                    do {
                        let chainResult = try await executeStandardReasoningChain(
                            query: question,
                            chunks: includedRetrievedChunks,
                            onProgress: { [weak self] title, detail in
                                // Show each reasoning phase with what it discovered
                                self?.emitThinkingEvent(
                                    .generation,
                                    title: title,
                                    detail: detail
                                )
                            }
                        )

                        // Store reasoning trace for metadata (separate from answer text)
                        // Format each insight nicely for UI display
                        if chainResult.chainInsights.count > 1 {
                            let sessionLabels = ["🔍 Analyzing Evidence", "🧠 Finding Patterns", "✨ Synthesis"]
                            chainReasoningTrace = chainResult.chainInsights.dropLast().enumerated().map { idx, insight in
                                let label = idx < sessionLabels.count ? sessionLabels[idx] : "Session \(idx + 1)"
                                let cleanInsight = insight
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "INSIGHT:", with: "")
                                    .replacingOccurrences(of: "REASONING:", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return "\(label): \(cleanInsight)"
                            }
                        }

                        // Build LLMResponse - answer only, reasoning trace stored separately
                        llmResponse = LLMResponse(
                            text: chainResult.finalAnswer,
                            tokensGenerated: chainResult.totalTokens,
                            timeToFirstToken: nil,
                            totalTime: 0, // Not tracked per-session
                            modelName: "Apple Foundation Model (Chained)",
                            toolCallsMade: 0
                        )

                        // Store trace in a way that can be passed to metadata later
                        // We'll use a capture variable
                        reasoningTraceForMetadata = chainReasoningTrace

                        Log.info("[RAG] Reasoning chain complete: \(chainResult.sessionCount) sessions, \(chainResult.totalTokens) tokens, confidence: \(String(format: "%.0f%%", chainResult.confidence * 100))", category: .pipeline)

                    } catch {
                        // Fall back to single-session generation if chain fails
                        Log.warning("[RAG] Reasoning chain failed, falling back to single session: \(error.localizedDescription)", category: .pipeline)
                        emitThinkingEvent(
                            .warning,
                            title: "Chain fallback",
                            detail: "Using single session"
                        )
                        // Continue to normal generation below
                        llmResponse = try await generateWithFallback(
                            prompt: promptForGeneration,
                            context: generationContext,
                            config: genConfig,
                            sourceChunks: generationChunks
                        )
                    }
                } else {
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
                } // End of else (non-reasoning-chain path)

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

                    // Pipeline Trace: Step 7
                    Log.pipelineStep("7", title: "Quality Assessment", details: [
                        ("sources", "\(generationRetrievedChunks.count)")
                    ])
                    let totalDocsCount = await snapshotDocumentsCount()
                    let (confidenceScore, qualityWarnings) = await engine.assessResponseQuality(
                        chunks: generationRetrievedChunks,
                        query: question,
                        totalDocs: totalDocsCount,
                        topScoreOverride: auditTopSim > 0 ? auditTopSim : nil  // Use actual reranked score
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

                    // Step 7.5: Verification Gates (AppleRAG Anti-Hallucination)
                    // Run Gates A-D to validate response against source evidence
                    // Respect quality mode toggle for verification
                    let runVerificationGates = qualityModeUsesVerificationGates

                    var verificationResult: RAGVerificationResult?
                    var verificationTime: TimeInterval = 0

                    if runVerificationGates {
                        Log.section("Step 7.5: Verification Gates", level: .info, category: .pipeline)

                        let verificationStartTime = Date()
                        // Use the TOP reranked scores from the pipeline (auditTopSim, auditSecondSim, etc.)
                        // NOT the scores from generationRetrievedChunks which may be sibling chunks with discounted scores
                        let topScores = [auditTopSim, auditSecondSim, auditAvgTop5].filter { $0 > 0 }

                        verificationResult = await verificationGateService.verify(
                            response: responseText,
                            query: question,
                            retrievedChunks: generationRetrievedChunks,
                            topScores: topScores
                        )
                        verificationTime = Date().timeIntervalSince(verificationStartTime)

                        Log.pipelineStep("7.5", title: "Verification Gates", details: [
                            ("passed", verificationResult!.passed ? "✓" : "✗"),
                            ("confidence", String(format: "%.2f", verificationResult!.overallConfidence)),
                            ("gates", verificationResult!.gateResults.map { "\($0.gate.rawValue):\($0.passed ? "✓" : "✗")" }.joined(separator: " "))
                        ])

                        // Emit verification thinking event
                        emitThinkingEvent(
                            .verification,
                            title: verificationResult!.passed ? "Gates passed ✓" : "Gates failed ✗",
                            detail: "Confidence: \(String(format: "%.0f", verificationResult!.overallConfidence * 100))%"
                        )

                        if !verificationResult!.passed {
                            Log.warning("⚠️ Verification gates failed - response may contain unsupported claims", category: .pipeline)
                            for gateResult in verificationResult!.gateResults where !gateResult.passed {
                                Log.warning("   • Gate \(gateResult.gate.rawValue): \(gateResult.details)", category: .pipeline)
                            }

                            // Intent-aware threshold adjustment:
                            // For extractive/lookup intents, answers are directly from source - lower threshold acceptable
                            // For synthesized answers (summarize, investigate), require higher confidence
                            let effectiveThreshold: Float
                            if answerIntent.isExtractiveFirst {
                                // Extractive intents: halve the threshold (e.g., 50% → 25%)
                                // Direct lookups from source don't need same rigor as synthesized answers
                                effectiveThreshold = qualityModeVerificationThreshold * 0.5
                                Log.debug("[Verification] Extractive intent '\(answerIntent.rawValue)' - using relaxed threshold \(String(format: "%.0f", effectiveThreshold * 100))%", category: .pipeline)
                            } else {
                                effectiveThreshold = qualityModeVerificationThreshold
                            }

                            // Check if confidence is below quality mode threshold (Maximum mode requires 98%)
                            let belowConfidenceThreshold = verificationResult!.overallConfidence < effectiveThreshold

                            // If grounded-only mode and verification fails, abstain
                            if !allowUngroundedFallback || belowConfidenceThreshold {
                                let thresholdDisplay = answerIntent.isExtractiveFirst
                                    ? "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))% (relaxed for extractive)"
                                    : "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))%"
                                let reason = belowConfidenceThreshold
                                    ? "confidence \(String(format: "%.0f", verificationResult!.overallConfidence * 100))% below \(thresholdDisplay)"
                                    : "grounded-only mode"
                                Log.info("🛑 Abstaining: \(reason)", category: .pipeline)
                                let abstainResponse = verificationGateService.generateAbstentionResponse(
                                    query: question,
                                    verificationResult: verificationResult!,
                                    retrievedChunks: generationRetrievedChunks
                                )
                                let response = await makeGroundedAbstainResponse(
                                    question: question,
                                    ragQuery: ragQueryValue,
                                    retrievedChunks: generationRetrievedChunks,
                                    retrievalTime: retrievalTime,
                                    retrievalConfig: retrievalConfig,
                                    embeddingProviderId: embeddingProviderId,
                                    reason: abstainResponse,
                                    gatingDecision: "verification_gates_failed:\(verificationResult!.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: ","))"
                                )
                                return await finalizeResponse(
                                    query: question,
                                    containerId: selectedId,
                                    containerName: selectedName,
                                    response: response
                                )
                            }
                        } else {
                            Log.info("✓ All verification gates passed (confidence: \(String(format: "%.0f", verificationResult!.overallConfidence * 100))%)", category: .pipeline)
                        }
                    } else {
                        Log.info("[RAG] Verification gates skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
                        emitThinkingEvent(
                            .verification,
                            title: "Verification skipped",
                            detail: "\(qualityModeDisplayName) mode"
                        )
                    }

                    // Emit telemetry for verification (only if gates were run)
                    if let vResult = verificationResult {
                        TelemetryCenter.emit(
                            .system,
                            title: "Verification complete",
                            metadata: [
                                "passed": vResult.passed ? "true" : "false",
                                "confidence": String(format: "%.2f", vResult.overallConfidence),
                                "failedGates": vResult.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: ",")
                            ],
                            duration: verificationTime
                        )
                    }

                    // Step 8: Package results
                    let pipelineTotalTime = Date().timeIntervalSince(pipelineStartTime)

                    // Step 8.1: Calibrated Confidence (AppleRAG §7)
                    // P(correct) = σ(α*s_max + β*m + γ*log(1+n_evidence) - δ)
                    let isTouchyQuery = question.lowercased().contains(["safety", "warning", "danger", "pressure", "temperature", "voltage", "maximum", "minimum", "limit"].first(where: { question.lowercased().contains($0) }) ?? "___never___")
                    let calibratedConfidence = confidenceCalibrationService.calibrate(
                        chunks: generationRetrievedChunks,
                        verification: verificationResult,
                        isTouchyQuery: isTouchyQuery
                    )
                    Log.info(
                        "📊 Calibrated confidence: \(String(format: "%.1f", calibratedConfidence.probability * 100))% (\(calibratedConfidence.level.rawValue))",
                        category: .pipeline
                    )

                    // Emit calibrated confidence thinking event
                    emitThinkingEvent(
                        .confidence,
                        title: "Confidence: \(calibratedConfidence.level.rawValue)",
                        detail: "\(String(format: "%.0f", calibratedConfidence.probability * 100))% P(correct)"
                    )

                    // Pipeline Trace: Completion summary
                    Log.pipelineComplete(
                        totalDuration: pipelineTotalTime,
                        chunksRetrieved: generationRetrievedChunks.count,
                        tokensUsed: nil,
                        confidence: Double(confidenceScore)
                    )

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
                            "  - Verification Gates: \(String(format: "%.0f", verificationTime * 1000))ms",
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
                    var gatingSummary: String? =
                        acceptanceOverride
                            ? "acceptance_override" : lenient ? "lenient" : nil

                    // Append verification result to gating summary (only if gates were run)
                    if let vResult = verificationResult {
                        if vResult.passed {
                            let verifySummary = "verified:\(String(format: "%.0f", vResult.overallConfidence * 100))%"
                            gatingSummary = gatingSummary.map { "\($0),\(verifySummary)" } ?? verifySummary
                        } else {
                            let failedGates = vResult.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: "+")
                            let verifySummary = "unverified:\(failedGates)"
                            gatingSummary = gatingSummary.map { "\($0),\(verifySummary)" } ?? verifySummary
                        }
                    } else {
                        // Verification gates were skipped
                        gatingSummary = gatingSummary.map { "\($0),verification_skipped" } ?? "verification_skipped"
                    }

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
                        embeddingProvider: embeddingProviderId,
                        usedAgenticMode: false, // Single-pass mode
                        originalQuery: question, // For "Go Deeper" re-query
                        reasoningTrace: reasoningTraceForMetadata // Chained session insights
                    )

                    // Include verification warnings in quality warnings (only if gates were run)
                    var finalWarnings = qualityWarnings
                    if let vResult = verificationResult, !vResult.passed {
                        for gateResult in vResult.gateResults where !gateResult.passed {
                            finalWarnings.append("Verification \(gateResult.gate.rawValue): \(gateResult.details)")
                        }
                    }

                    // Generate structured answer for rich UI rendering (AppleRAG §6)
                    let structuredAnswer = StructuredAnswer.from(
                        response: responseText,
                        retrievedChunks: generationRetrievedChunks,
                        answerIntent: answerIntent,
                        verificationResult: verificationResult,
                        loops: reasoningTraceForMetadata?.count ?? 1
                    )

                    // Log structured answer summary
                    Log.debug(
                        "[StructuredAnswer] type=\(structuredAnswer.answerType.rawValue), claims=\(structuredAnswer.claims.count), evidence=\(structuredAnswer.evidence.count), gaps=\(structuredAnswer.missing.count)",
                        category: .pipeline
                    )

                    let response = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: generationRetrievedChunks,
                        generatedResponse: responseText,
                        metadata: metadata,
                        confidenceScore: confidenceScore,
                        qualityWarnings: finalWarnings,
                        structuredAnswer: structuredAnswer
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
                // No documents case
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

                // Pipeline Trace: No documents - direct LLM
                Log.pipelineStep("D", title: "Direct LLM (No Docs)", details: [
                    ("reason", "empty library"),
                    ("container", selectedName)
                ])

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

    // MARK: - Provider Display Names

    /// Maps embedding provider IDs to concise, SWE-accurate display names.
    /// These shorthand names maintain technical precision while fitting in pill UI elements.
    static func shortProviderName(for providerId: String) -> String {
        switch providerId.lowercased() {
        case "coreml_sentence_embedding", "coreml_sentence":
            return "CoreML"  // MiniLM-L6-v2 sentence transformer
        case "nl_embedding", "nlembedding":
            return "NL"  // NaturalLanguage.framework
        case "apple_foundation", "apple_fm":
            return "FM"  // Foundation Models (Apple Intelligence)
        case "openai_embedding", "openai":
            return "OpenAI"  // text-embedding-3-small/large
        case "nl_contextual", "contextual":
            return "NLCtx"  // NLContextualEmbedding
        default:
            // Fallback: first word capitalized, or abbreviate long names
            let parts = providerId.split(separator: "_")
            if parts.count >= 2 {
                // Take first letters of each word for long providers
                return parts.prefix(2).map { $0.prefix(4).capitalized }.joined()
            }
            return String(providerId.prefix(8)).capitalized
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
            // on_device_analysis is now handled by Apple Intelligence; silent fallthrough
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
        default:
            // Unknown model type - try Apple Intelligence
            Log.warning("Unknown model type: \(modelKey); trying Apple Intelligence", category: .initialization)
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
        // Clean up the response text (remove verbose markdown that can't render)
        let cleanedResponse = cleanupResponseText(response.generatedResponse)
        var finalResponse = response
        finalResponse = RAGResponse(
            queryId: response.queryId,
            retrievedChunks: response.retrievedChunks,
            generatedResponse: cleanedResponse,
            metadata: response.metadata,
            confidenceScore: response.confidenceScore,
            qualityWarnings: response.qualityWarnings
        )

        await MainActor.run {
            self.recordRetrievalHistory(
                query: query,
                containerId: containerId,
                containerName: containerName,
                chunks: finalResponse.retrievedChunks
            )
        }

        // Record conversation turn for memory service (enables multi-turn context)
        // IMPORTANT: Fire-and-forget to avoid blocking response delivery
        let useConversationMemory = await MainActor.run { settingsStore?.enableConversationMemory ?? true }
        if #available(iOS 26.0, *), useConversationMemory {
            // Detached task prevents blocking the response return
            Task.detached(priority: .utility) {
                await ConversationMemoryService.shared.addTurn(
                    userQuery: query,
                    assistantResponse: finalResponse.generatedResponse,
                    for: containerId
                )
            }
        }

        await logQueryStats(query: query, response: finalResponse)
        return finalResponse
    }

    /// Clean up response text by removing verbose markdown that can't be rendered
    private nonisolated func cleanupResponseText(_ text: String) -> String {
        var result = text

        // Strip markdown headers (##, ###, etc.) - convert to plain text
        result = result.components(separatedBy: .newlines)
            .map { line in
                var cleaned = line
                // Remove markdown headers - convert "## Title" to "Title"
                if let headerMatch = cleaned.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                    cleaned = String(cleaned[headerMatch.upperBound...])
                }
                return cleaned
            }
            .joined(separator: "\n")

        // Convert bullet points and numbered lists to cleaner format
        // NOTE: Preserve inline formatting like **bold** and *italic* - only strip list bullets
        result = result.components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Convert "- text" to just the text (dash bullets)
                if trimmed.hasPrefix("- ") && trimmed.count > 2 {
                    return String(trimmed.dropFirst(2))
                }
                // Convert "• text" to just the text (unicode bullets)
                if trimmed.hasPrefix("• ") && trimmed.count > 2 {
                    return String(trimmed.dropFirst(2))
                }
                // Only strip "* text" if it's clearly a bullet (no closing * for italic)
                // List bullet: "* some text" vs Italic: "*emphasized*"
                if trimmed.hasPrefix("* ") && trimmed.count > 2 && !trimmed.dropFirst(2).contains("*") {
                    return String(trimmed.dropFirst(2))
                }
                // Convert numbered lists "1. text" or "1) text" to just text
                if let numMatch = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                    return String(trimmed[numMatch.upperBound...])
                }
                return line
            }
            .joined(separator: "\n")

        // Collapse multiple blank lines into single
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
                parentContent: nil,
                contextualPrefix: retrieved.chunk.contextualPrefix,
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

        let engine = RAGEngine.shared
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
    /// - Returns 4,096 tokens per session (same limit applies on-device and via PCC per TN3193)
    var appleIntelligenceContextTokens: Int {
        if supportsFoundationModels {
            return 4096
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
                "4,096 token context window. Private Cloud Compute handles complex queries that benefit from server-side processing."
        } else if supportsAppleIntelligence {
            return
                "4,096 tokens handled fully on-device while Foundation Models finish downloading."
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

    /// Callback type for emitting detailed thinking events during retrieval
    /// Used by AgenticOrchestrator to stream verbose pipeline events to ThinkingView
    typealias DetailedThinkingCallback = @Sendable (ThinkingEvent.Kind, String, String) async -> Void

    /// Execute the FULL retrieval pipeline (HyDE, hybrid search, AI re-ranking, MMR)
    /// This gives Deep Think mode the same quality retrieval as Standard mode
    /// Used by AgenticOrchestrator for high-quality chunk retrieval with reasoning on top
    /// - Parameter onDetailedEvent: Optional callback for verbose thinking events (for Deep Think/Maximum)
    func executeFullRetrievalPipeline(
        query: String,
        topK: Int = 20,
        minSimilarity: Float = 0.08,
        onDetailedEvent: DetailedThinkingCallback? = nil
    ) async throws -> [RetrievedChunk] {
        let embeddingContext = await resolveEmbeddingContext()
        let db = await dbFor(embeddingContext.containerId)
        let allChunks = try await db.allChunks()

        // Skip if no chunks
        guard !allChunks.isEmpty else { return [] }

        // Emit: Starting retrieval pipeline
        await onDetailedEvent?(.planning, "Query analysis", "Analyzing: \"\(query.prefix(50))...\"")

        // RAPTOR-lite: Query routing for summary-first retrieval
        // Only filter chunks if query routing is enabled AND we have summaries
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = await queryRouter.classifyQuery(query)
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                // For overview queries in agentic mode, use summaries first
                let searchLevels = await queryRouter.abstractionLevelsToSearch(for: queryClassification)
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info("[RAPTOR-lite] Agentic retrieval using \(effectiveChunks.count) summary chunks for overview query", category: .retrieval)
                await onDetailedEvent?(.retrieval, "RAPTOR-lite routing", "Using \(effectiveChunks.count) summary chunks")
            }
        }

        // Step 1: Use original query for embedding
        // NOTE: HyDE disabled in Deep Think - it hallucinates without document context
        // and poisons retrieval with irrelevant content (e.g., "serial numbers" for "button" queries)
        let textToEmbed = query

        // Step 2: Generate query embedding
        await onDetailedEvent?(.embedding, "Encoding query", "384-dim neural embedding")
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: textToEmbed)
        await onDetailedEvent?(.vectorSearch, "Vector ready", "Query encoded for semantic search")

        // Step 3: Classify query intent for adaptive weights AND expand query
        let queryEnhancer = QueryEnhancementService()
        let queryIntent = queryEnhancer.classifyIntent(query)
        let adjustment = queryIntent.weightAdjustment
        let vectorWeight = max(0.1, min(0.9, 0.5 + adjustment.vectorDelta))
        let keywordWeight = max(0.1, min(0.9, 0.5 + adjustment.keywordDelta))

        // Emit: Query expansion
        await onDetailedEvent?(.queryRewrite, "Query expansion", "Intent: \(queryIntent.rawValue) → Vector \(Int(vectorWeight * 100))% / Keyword \(Int(keywordWeight * 100))%")

        // EXPAND query with synonyms for better keyword matching
        // e.g., "button" → "button switch toggle control key trigger"
        let expandedQueries = queryEnhancer.expandQuery(query)
        let expandedQueryString = expandedQueries.joined(separator: " ")
        Log.debug("[FullRetrieval] Expanded query: \(expandedQueryString.prefix(100))...", category: .retrieval)

        if expandedQueries.count > 1 {
            await onDetailedEvent?(.queryRewrite, "Synonym expansion", "+\(expandedQueries.count - 1) terms added")
        }

        // Step 4: Hybrid search (vector + BM25) with EXPANDED query for keywords
        await onDetailedEvent?(.retrieval, "Hybrid search", "Vector + BM25 on \(effectiveChunks.count) chunks")

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        var retrievedChunks = try await hybridSearch.search(
            query: expandedQueryString, // Use expanded query for better keyword matching
            embedding: queryEmbedding,
            topK: topK * 2, // Get extra for re-ranking
            cachedChunks: effectiveChunks, // Use RAPTOR-lite filtered chunks
            containerId: embeddingContext.containerId // Enable SQLite FTS5 acceleration
        )

        await onDetailedEvent?(.rrf, "RRF fusion", "\(retrievedChunks.count) candidates from hybrid search")

        // Step 5: AI Re-ranking with ReRanker model
        await onDetailedEvent?(.rerank, "AI re-ranking", "Scoring \(retrievedChunks.count) chunks with neural model")

        let engine = RAGEngine.shared
        retrievedChunks = await engine.rerank(chunks: retrievedChunks, query: query, topK: topK * 2)

        await onDetailedEvent?(.rerank, "Re-ranking complete", "Top scores: \(retrievedChunks.prefix(3).map { String(format: "%.0f%%", $0.similarityScore * 100) }.joined(separator: ", "))")

        // Step 6: MMR Diversification
        await onDetailedEvent?(.mmr, "MMR diversification", "Optimizing for coverage (λ=0.6)")

        let mmrLambda: Float = 0.6
        retrievedChunks = await engine.applyMMR(
            candidates: retrievedChunks,
            queryEmbedding: queryEmbedding,
            topK: topK,
            lambda: mmrLambda
        )

        await onDetailedEvent?(.mmr, "Diversity optimized", "\(retrievedChunks.count) chunks after MMR")

        // Step 7: Filter by similarity
        let preFilterCount = retrievedChunks.count
        retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: minSimilarity)

        if preFilterCount > retrievedChunks.count {
            await onDetailedEvent?(.context, "Quality filter", "Kept \(retrievedChunks.count)/\(preFilterCount) (≥\(Int(minSimilarity * 100))% threshold)")
        }

        // Enrich with document names
        var enrichedChunks: [RetrievedChunk] = []
        for (rank, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            enrichedChunks.append(RetrievedChunk(
                chunk: retrieved.chunk,
                similarityScore: retrieved.similarityScore,
                rank: rank + 1,
                sourceDocument: docName,
                pageNumber: retrieved.chunk.metadata.pageNumber
            ))
        }

        // Final retrieval summary
        await onDetailedEvent?(.retrieval, "Retrieval complete", "\(enrichedChunks.count) chunks ready for synthesis")

        return enrichedChunks
    }

    /// Search and return raw chunks for agentic orchestrator (not just formatted string)
    /// Uses hybrid search (vector + BM25) for better retrieval quality on technical documents.
    /// Used internally by AgenticOrchestrator to collect chunks for UnifiedMetricsBar
    func searchDocumentsRaw(query: String, topK: Int = 10, minSimilarity: Float = 0.25) async throws -> [RetrievedChunk] {
        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: query)

        let db = await dbFor(embeddingContext.containerId)

        // Use hybrid search (vector + BM25) for better keyword matching on technical terms
        // Critical for car manuals, technical docs where exact terms like "5W-30" matter
        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: 0.5, // Balance vector and keyword for technical queries
            keywordWeight: 0.5
        )

        // Index BM25 with available chunks (for lexical recall)
        let allChunks = try await db.allChunks()

        // RAPTOR-lite: Query routing for summary-first retrieval
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = await queryRouter.classifyQuery(query)
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                let searchLevels = await queryRouter.abstractionLevelsToSearch(for: queryClassification)
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info("[RAPTOR-lite] Raw search using \(effectiveChunks.count) summary chunks", category: .retrieval)
            }
        }

        let bm25Scorer = BM25Scorer()
        bm25Scorer.indexDocuments(effectiveChunks)

        // Request more candidates for better coverage
        let effectiveTopK = max(topK, 15)
        var retrievedChunks = try await hybridSearch.search(
            query: query,
            embedding: queryEmbedding,
            topK: effectiveTopK,
            cachedChunks: effectiveChunks,
            containerId: embeddingContext.containerId // Enable SQLite FTS5 acceleration
        )

        let engine = RAGEngine.shared
        retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: minSimilarity)

        // Enrich with source document names
        var enrichedChunks: [RetrievedChunk] = []
        for (rank, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            enrichedChunks.append(RetrievedChunk(
                chunk: retrieved.chunk,
                similarityScore: retrieved.similarityScore,
                rank: rank + 1,
                sourceDocument: docName,
                pageNumber: retrieved.chunk.metadata.pageNumber
            ))
        }

        return enrichedChunks
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
            let engine = RAGEngine.shared
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

    /// Count occurrences of a pattern across ALL documents (exact matching)
    /// This uses full-text storage, not semantic search - ZERO data loss counting
    /// FTS5 path is 10-100X faster than legacy file-based storage
    func countPatternInCorpus(pattern: String) async throws -> String {
        Log.debug(" [Tool Call] count_pattern_in_corpus(pattern: \"\(pattern)\")")

        let activeId = await MainActor.run { self.containerService.activeContainerId }

        // Try FTS5 first (10-100X faster), fall back to legacy file storage
        let fts5Available = await SQLiteFullTextService.shared.documentCount(for: activeId) > 0

        let counts: [UUID: Int]
        if fts5Available {
            // FTS5 path: Use container-scoped search with native bm25()
            counts = await SQLiteFullTextService.shared.countPatternInCorpus(
                pattern: pattern,
                containerId: activeId
            )
            Log.debug("[RAGService] Using FTS5 for pattern count (container: \(activeId))", category: .retrieval)
        } else {
            // Legacy path: File-based storage (no container isolation)
            counts = await FullTextStorageService.shared.countPatternInCorpus(pattern: pattern)
            Log.debug("[RAGService] Using legacy file storage for pattern count", category: .retrieval)
        }

        if counts.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        let totalOccurrences = counts.values.reduce(0, +)
        var result = "Pattern '\(pattern)' found \(totalOccurrences) times across \(counts.count) documents:\n\n"

        // Sort by count descending
        let sortedCounts = counts.sorted { $0.value > $1.value }

        for (docId, count) in sortedCounts.prefix(20) { // Limit to top 20 for token budget
            let docName = await documentName(for: docId)
            result += "- \(docName): \(count) occurrences\n"
        }

        if sortedCounts.count > 20 {
            result += "... and \(sortedCounts.count - 20) more documents\n"
        }

        Log.info(" [Tool Call] Pattern '\(pattern)' found \(totalOccurrences) times in \(counts.count) docs")
        return result
    }

    /// Search for exact text pattern across ALL documents
    /// Returns documents containing the pattern with context
    /// FTS5 path is 10-100X faster with native snippet() support
    func searchExactPattern(pattern: String) async throws -> String {
        Log.debug(" [Tool Call] search_exact_pattern(pattern: \"\(pattern)\")")

        let activeId = await MainActor.run { self.containerService.activeContainerId }

        // Try FTS5 first (10-100X faster with native snippets), fall back to legacy
        let fts5Available = await SQLiteFullTextService.shared.documentCount(for: activeId) > 0

        let matches: [FullTextStorageService.SearchMatch]
        if fts5Available {
            // FTS5 path: Use container-scoped search with native snippet()
            let fts5Matches = await SQLiteFullTextService.shared.searchCorpus(
                pattern: pattern,
                containerId: activeId,
                maxResults: 10,
                contextChars: 150
            )
            // Convert to legacy SearchMatch format for compatibility
            matches = fts5Matches.map { m in
                FullTextStorageService.SearchMatch(
                    documentId: m.documentId,
                    occurrences: m.count,
                    contextSnippet: m.context
                )
            }
            Log.debug("[RAGService] Using FTS5 for exact search (container: \(activeId))", category: .retrieval)
        } else {
            // Legacy path: File-based storage (no container isolation)
            matches = await FullTextStorageService.shared.searchCorpus(pattern: pattern, maxResults: 10)
            Log.debug("[RAGService] Using legacy file storage for exact search", category: .retrieval)
        }

        if matches.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        var result = "Found pattern '\(pattern)' in \(matches.count) documents:\n\n"

        for match in matches {
            let docName = await documentName(for: match.documentId)
            result += "**\(docName)** (\(match.occurrences) occurrences):\n"
            result += "  \"\(match.contextSnippet)\"\n\n"
        }

        Log.info(" [Tool Call] Pattern '\(pattern)' found in \(matches.count) docs with context")
        return result
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Cross-Container Search (Unified RAG)

    /// Search ALL knowledge containers simultaneously using Reciprocal Rank Fusion.
    ///
    /// This enables the LLM to synthesize knowledge from multiple knowledge bases,
    /// e.g., combining legal documents, technical manuals, and internal policies
    /// into a unified answer.
    ///
    /// - Parameters:
    ///   - query: Natural language search query
    ///   - globalTopK: Maximum results after cross-container fusion
    ///
    /// - Returns: Formatted string with fused results and container source attribution
    func searchAllContainers(query: String, globalTopK: Int = 10) async throws -> String {
        Log.debug(" [Tool Call] search_all_containers(query: \"\(query)\", globalTopK: \(globalTopK))")

        // Get all containers (MainActor - no await needed)
        let allContainers = containerService.containers

        guard !allContainers.isEmpty else {
            return "No knowledge containers available."
        }

        // Embed the query - use the active container's embedding service
        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: query)

        // Perform cross-container search with RRF
        let results = await vectorRouter.searchAll(
            embedding: queryEmbedding,
            containers: allContainers,
            topK: 10,
            globalTopK: globalTopK
        )

        if results.isEmpty {
            return "No relevant information found across all containers for: \(query)"
        }

        // Format results with container attribution
        var output = "Found \(results.count) results across \(allContainers.count) knowledge containers:\n\n"

        for result in results {
            let docName = await documentName(for: result.chunk.documentId)
            output += "[\(result.fusedRank)] From \(docName) [📁 \(result.containerName)]"
            if let page = result.chunk.metadata.pageNumber {
                output += " (Page \(page))"
            }
            output += " (Relevance: \(String(format: "%.1f%%", result.similarityScore * 100))):\n"

            let fullText = result.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 500 ? String(fullText.prefix(500)) + " [...]" : fullText
            output += preview
            output += "\n\n"
        }

        Log.info(" [Tool Call] Cross-container search returned \(results.count) fused results")
        return output
    }

    /// Raw cross-container search returning structured results (for agentic orchestrator).
    /// Returns enriched results with container metadata for UI display.
    func searchAllContainersRaw(
        query: String,
        globalTopK: Int = 10,
        minSimilarity: Float = 0.3
    ) async throws -> [VectorStoreRouter.CrossContainerResult] {
        // MainActor - no await needed for containerService access
        let allContainers = containerService.containers
        guard !allContainers.isEmpty else { return [] }

        let embeddingContext = await resolveEmbeddingContext()
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: query)

        var results = await vectorRouter.searchAll(
            embedding: queryEmbedding,
            containers: allContainers,
            topK: 10,
            globalTopK: globalTopK
        )

        // Filter by minimum similarity
        results = results.filter { $0.similarityScore >= minSimilarity }

        return results
    }
}
