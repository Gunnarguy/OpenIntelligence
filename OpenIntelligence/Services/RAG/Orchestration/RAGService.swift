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
#if canImport(UIKit)
import UIKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

// NOTE: Local model support (GGUF, CoreML, MLX) has been removed.
// The app now uses Apple Intelligence and On-Device Analysis only.

// MARK: - Async Collection Helpers

extension Array {
    /// Filter array with async predicate
    func asyncFilter(_ isIncluded: @escaping (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
        }
        return result
    }
}

struct RetrievalLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let containerId: UUID
    let containerName: String
    let chunks: [RetrievedChunk]
}

struct RAGAuditFeatureFlags: Sendable {
    let answerIntent: String
    let queryWasRewritten: Bool
    let queryExpansionCount: Int
    let usedHyDE: Bool
    let usedIterativeRetrieval: Bool
    let iterativePassCount: Int
    let usedQueryRouting: Bool
    let usedSummaryRouting: Bool
    let usedParentDocumentRetrieval: Bool
    let usedCorrectiveRetrieval: Bool
    let usedContextualCompression: Bool
    let usedGraphPacking: Bool
    let usedRetrievalCascade: Bool
    let usedSupplementaryVectorSearch: Bool
    let usedFullUnlimitedReasoning: Bool

    nonisolated static let empty = RAGAuditFeatureFlags(
        answerIntent: "unknown",
        queryWasRewritten: false,
        queryExpansionCount: 0,
        usedHyDE: false,
        usedIterativeRetrieval: false,
        iterativePassCount: 0,
        usedQueryRouting: false,
        usedSummaryRouting: false,
        usedParentDocumentRetrieval: false,
        usedCorrectiveRetrieval: false,
        usedContextualCompression: false,
        usedGraphPacking: false,
        usedRetrievalCascade: false,
        usedSupplementaryVectorSearch: false,
        usedFullUnlimitedReasoning: false
    )

    var enabledFeatures: [String] {
        var features: [String] = []
        if queryWasRewritten { features.append("Rewrite") }
        if queryExpansionCount > 0 { features.append("Expand \(queryExpansionCount)") }
        if usedHyDE { features.append("HyDE") }
        if usedIterativeRetrieval {
            let label = iterativePassCount > 0 ? "Iterative \(iterativePassCount)x" : "Iterative"
            features.append(label)
        }
        if usedQueryRouting { features.append("Routing") }
        if usedSummaryRouting { features.append("Summaries") }
        if usedParentDocumentRetrieval { features.append("Parent") }
        if usedCorrectiveRetrieval { features.append("Corrective") }
        if usedContextualCompression { features.append("Compression") }
        if usedGraphPacking { features.append("GraphPack") }
        if usedRetrievalCascade { features.append("Cascade") }
        if usedSupplementaryVectorSearch { features.append("MultiVector") }
        if usedFullUnlimitedReasoning { features.append("Unlimited") }
        return features
    }
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
    let featureFlags: RAGAuditFeatureFlags

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
        featureFlags: RAGAuditFeatureFlags = .empty,
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
        self.featureFlags = featureFlags
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

enum IngestionContext: String, Codable, Sendable {
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
    nonisolated private static let maxPersistedChatHistoryBytes = 4 * 1024 * 1024
    nonisolated private static let ingestionLeaseDuration: TimeInterval = 120

    // MARK: - Dependencies

    private let documentProcessor: DocumentProcessor
    private let embeddingService: EmbeddingService
    private let embeddingServiceWasInjected: Bool
    let containerService: ContainerService
    private let vectorRouter: VectorStoreRouter
    private let intelligenceCenter = LibraryIntelligenceCenter()
    private let documentSummaryService: DocumentSummaryService
    private let queryRouter = QueryRouterService()
    private let graphIndexService = GraphIndexService()
    private let contextPackingService: ContextPackingService
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
    @MainActor private var liveActivityTrackedIngestionIds: Set<UUID> = []
    @MainActor private var lastLocalIndexSyncFingerprint: String?

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

    /// Preloads chat history without blocking the main actor on disk IO or JSON decoding.
    func preloadChatHistory(for containerId: UUID?) async -> [ChatMessage] {
        let resolvedId = await MainActor.run { containerId ?? self.containerService.activeContainerId }

        if let cached = await MainActor.run(body: { self.chatHistories[resolvedId] }) {
            return cached
        }

        let url = AppSupportPaths.chatHistoryURL(containerId: resolvedId)
        let loaded = await Task.detached(priority: .utility) {
            Self.readChatHistoryFromDisk(at: url, containerId: resolvedId)
        }.value

        return await MainActor.run {
            self.chatHistories[resolvedId] = loaded
            return loaded
        }
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
        saveChatHistory(trimmedMessages.map { $0.sanitizedForPersistence() }, for: resolvedId)
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

        // Reset the LLM session to clear transcript from memory
        resetLLMSession()
    }

    /// Resets the LLM session to clear accumulated transcript and free up context budget.
    /// Call after onboarding, when starting fresh, or when context budget is exhausted.
    @MainActor
    func resetLLMSession() {
        if let appleFMService = _llmService as? AppleFoundationLLMService {
            appleFMService.resetSession(clearTools: false)
            Log.info("[RAGService] Reset LLM session - context budget restored", category: .llm)
        }
    }

    /// Cancels any active long-running generation work and clears shared agentic state.
    /// This prevents back-to-back Deep Think runs from contending for the same FM session.
    @MainActor
    func cancelActiveGeneration(resetSession: Bool = true) {
        if let activeAgenticTask {
            Log.info("[RAGService] Cancelling active agentic generation", category: .llm)
            activeAgenticTask.cancel()
            self.activeAgenticTask = nil
        }

        forceAgenticOnNextQuery = false
        resetDeepThinkLiveMetrics()

        if resetSession {
            resetLLMSession()
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
        return Self.readChatHistoryFromDisk(at: url, containerId: containerId)
    }

    private nonisolated static func readChatHistoryFromDisk(at url: URL, containerId: UUID) -> [ChatMessage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        if let fileSize = chatHistoryFileSize(at: url), fileSize > maxPersistedChatHistoryBytes {
            quarantineOversizedChatHistory(at: url, containerId: containerId, fileSize: fileSize)
            return []
        }

        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: url)
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            return messages.map { $0.sanitizedForPersistence() }
        } catch {
            Log.error("[RAGService] Failed to load chat history for container \(containerId): \(error.localizedDescription)", category: .initialization)
            return []
        }
    }

    private nonisolated static func chatHistoryFileSize(at url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.size] as? Int
    }

    private nonisolated static func quarantineOversizedChatHistory(at url: URL, containerId: UUID, fileSize: Int) {
        let quarantineURL = AppSupportPaths.baseDir().appendingPathComponent(
            "chat_history_\(containerId.uuidString).oversized_\(Int(Date().timeIntervalSince1970)).json"
        )

        do {
            try? WorkspaceSyncService.coordinatedRemoveItem(at: quarantineURL)
            try FileManager.default.moveItem(at: url, to: quarantineURL)
            Log.warning(
                "[RAGService] Quarantined oversized chat history for container \(containerId) (\(fileSize) bytes)",
                category: .initialization
            )
        } catch {
            try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
            Log.warning(
                "[RAGService] Removed oversized chat history for container \(containerId) after quarantine failed: \(error.localizedDescription)",
                category: .initialization
            )
        }
    }

    @MainActor
    private func syncContainerStats(for containerId: UUID, lastIndexedAt: Date? = nil) {
        let containerDocuments = documentsForContainer(containerId)
        let totalChunks = containerDocuments.reduce(0) { $0 + $1.totalChunks }
        containerService.updateStats(
            for: containerId,
            totalDocuments: containerDocuments.count,
            totalChunks: totalChunks,
            lastIndexedAt: lastIndexedAt
        )
    }

    @MainActor
    private func syncAllContainerStats() {
        let containerIds = containerService.containers.map(\.id)
        for containerId in containerIds {
            syncContainerStats(for: containerId)
        }
    }

    @MainActor
    private func saveChatHistory(_ messages: [ChatMessage], for containerId: UUID) {
        let url = AppSupportPaths.chatHistoryURL(containerId: containerId)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(messages)
            try WorkspaceSyncService.coordinatedWriteData(data, to: url)
        } catch {
            Log.error("[RAGService] Failed to save chat history for container \(containerId): \(error.localizedDescription)", category: .initialization)
        }
    }

    @MainActor
    func persistIngestionQueueState() {
        savePersistedIngestionQueueState()
    }

    @MainActor
    func restoreIngestionQueueIfNeeded() {
        restorePersistedIngestionQueueIfNeeded()
    }

    @MainActor
    private func savePersistedIngestionQueueState() {
        let url = AppSupportPaths.ingestionQueueURL()
        let activeItems = ingestionItems.filter { !$0.stage.isTerminal }

        guard !activeItems.isEmpty else {
            try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
            return
        }

        let state = PersistedIngestionQueueState(
            items: activeItems,
            contexts: activeItems.map { PersistedIngestionContext(id: $0.id, context: ingestionContexts[$0.id] ?? .userInitiated) },
            updatedAt: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try WorkspaceSyncService.coordinatedWriteData(data, to: url)
        } catch {
            Log.error("[RAGService] Failed to persist ingestion queue: \(error.localizedDescription)", category: .ingestion)
        }
    }

    @MainActor
    private func restorePersistedIngestionQueueIfNeeded() {
        let url = AppSupportPaths.ingestionQueueURL()
        guard let data = try? WorkspaceSyncService.coordinatedReadData(from: url) else { return }

        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(PersistedIngestionQueueState.self, from: data)
            var restoredItems: [IngestionItem] = []
            var restoredContexts: [UUID: IngestionContext] = [:]
            let currentDeviceID = WorkspaceSyncService.currentDeviceID()
            let now = Date()

            for item in state.items {
                if item.url.isFileURL {
                    if FileManager.default.isUbiquitousItem(at: item.url) {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
                    } else if !FileManager.default.fileExists(atPath: item.url.path) {
                        Log.warning("[RAGService] Skipping persisted ingestion item because file is missing: \(item.url.lastPathComponent)", category: .ingestion)
                        continue
                    }
                }

                var resumedItem = item

                if item.isLeased(to: currentDeviceID, at: now) || !item.hasActiveLease(at: now) {
                    resumedItem.stage = .queued
                    resumedItem.detail = item.stage == .queued ? "Queued" : "Queued for pickup"
                    resumedItem.progress = nil
                    resumedItem.startedAt = nil
                    resumedItem.finishedAt = nil
                    resumedItem.errorMessage = nil
                    resumedItem.clearLease()
                } else {
                    resumedItem.detail = "Processing on another device"
                }

                restoredItems.append(resumedItem)
            }

            guard !restoredItems.isEmpty else {
                try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
                return
            }

            let validIds = Set(restoredItems.map(\.id))
            for entry in state.contexts where validIds.contains(entry.id) {
                restoredContexts[entry.id] = entry.context
            }

            liveActivityTrackedIngestionIds = Set(
                restoredContexts.compactMap { id, context in
                    context == .userInitiated ? id : nil
                }
            )

            ingestionItems = restoredItems
            ingestionContexts = restoredContexts
            Log.info("[RAGService] Restored \(restoredItems.count) queued ingestion item(s) after interruption", category: .ingestion)
            savePersistedIngestionQueueState()
            syncIngestionLiveActivity()
            resumeUserInitiatedIngestionBackgroundSupportIfNeeded(restoredItems: restoredItems)
            startIngestionTaskIfNeeded()
        } catch {
            Log.error("[RAGService] Failed to restore persisted ingestion queue: \(error.localizedDescription)", category: .ingestion)
            try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
        }
    }

    @MainActor
    private func handleContinuedIngestionExpiration() {
        let activeIndices = ingestionItems.indices.filter { !ingestionItems[$0].stage.isTerminal }
        guard !activeIndices.isEmpty else {
            savePersistedIngestionQueueState()
            return
        }

        ingestionTask?.cancel()
        ingestionTask = nil
        isProcessing = false
        processingStatus = ""

        for index in activeIndices {
            ingestionItems[index].stage = .queued
            ingestionItems[index].detail = "Queued for resume"
            ingestionItems[index].progress = nil
            ingestionItems[index].startedAt = nil
            ingestionItems[index].finishedAt = nil
            ingestionItems[index].errorMessage = nil
            ingestionItems[index].metrics = .init()
            ingestionItems[index].clearLease()
        }

        Log.warning("[RAGService] Continued ingestion expired; queued \(activeIndices.count) item(s) for resume", category: .ingestion)
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    @MainActor
    private func resumeUserInitiatedIngestionBackgroundSupportIfNeeded(restoredItems: [IngestionItem]) {
#if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return }
#endif

        let resumedUserInitiatedItems = restoredItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        guard !resumedUserInitiatedItems.isEmpty else { return }

        let subtitle = resumedUserInitiatedItems.count == 1
            ? resumedUserInitiatedItems[0].filename
            : "\(resumedUserInitiatedItems.count) documents"
        IngestionRuntimeBridge.shared.beginUserInitiatedIngestion(
            title: "Importing documents",
            subtitle: subtitle
        )
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

    /// Tracks the active agentic query task so it can be cancelled when a new query arrives.
    /// Without this, sending a second Deep Think/Maximum query while one is running causes
    /// both orchestrators to compete for the Apple FM model, freezing the app.
    @MainActor private var activeAgenticTask: Task<RAGResponse, Error>? = nil

    /// Cached corpus vocabulary per container to avoid expensive rebuilds on each query
    @MainActor private var corpusVocabularyCache: [UUID: CorpusVocabulary] = [:]

    /// Memory warning observer — evicts corpus vocabulary cache under pressure
    @MainActor private var memoryWarningObserver: (any NSObjectProtocol)?

    /// Published model name for UI binding - updates when LLM service changes
    @MainActor @Published private(set) var activeModelName: String = "Loading..."
    @MainActor private var selfTuningInFlight: Set<UUID> = []

    /// Track when containers last completed ingestion to prevent immediate self-tuning rebuilds.
    /// Self-tuning should analyze library content AFTER all documents are ingested, not after each one.
    /// This prevents the scenario where a large PDF finishes and immediately triggers re-embedding
    /// of ALL documents (including the one just processed).
    @MainActor private var lastIngestionCompletionTime: [UUID: Date] = [:]

    /// Minimum cooldown (in seconds) after ingestion before allowing self-tuning rebuilds.
    /// This gives time for the batch to complete and prevents wasteful immediate rebuilds.
    private static let selfTuningCooldownSeconds: TimeInterval = 30.0

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
    /// When true, suppress automatic reembed kicks (used during onboarding batch import)
    @MainActor private var suppressReembedKicks: Bool = false

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

    private struct PersistedIngestionContext: Codable, Sendable {
        let id: UUID
        let context: IngestionContext
    }

    private struct PersistedIngestionQueueState: Codable, Sendable {
        let items: [IngestionItem]
        let contexts: [PersistedIngestionContext]
        let updatedAt: Date
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

        Task { @MainActor in
            IngestionRuntimeBridge.shared.configureContinuedIngestion(
                run: { [weak self] in
                    guard let self else { return false }
                    return await self.runPendingIngestionQueue()
                },
                expiration: { [weak self] in
                    self?.handleContinuedIngestionExpiration()
                }
            )
            IngestionRuntimeBridge.shared.restoreLiveActivityIfNeeded()
            self.restorePersistedIngestionQueueIfNeeded()
        }

        // Connect document summary service to self for LLM access
        Task {
            await self.documentSummaryService.setRAGService(self)
        }

        // Log GPU acceleration status at startup
        Task {
            let gpuService = GPUComputeService.shared
            if gpuService.isGPUAvailable {
                Log.info("🚀 GPU Compute: \(gpuService.deviceName) ready for vector operations", category: .initialization)
            } else {
                Log.warning("⚠️ GPU unavailable, using Accelerate (CPU SIMD) for vector math", category: .initialization)
            }

            if DocumentProcessor.isGPUAccelerated {
                Log.info("🚀 GPU Image Processing: Metal context ready for OCR", category: .initialization)
            }
        }

        // Observe container switches to save/restore transcripts
        observeContainerChanges()

        // MEMORY FIX: Evict caches on memory pressure to prevent OOM jetsam kills
        #if canImport(UIKit)
        Task { @MainActor in
            self.memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let count = self.corpusVocabularyCache.count
                    self.corpusVocabularyCache.removeAll()
                    if count > 0 {
                        Log.warning("[RAGService] ⚠️ Memory warning — evicted \(count) corpus vocabulary caches", category: .retrieval)
                    }
                }
            }
        }
        #endif
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
            .sink { [weak self] (newContainerId: UUID) in
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
        // Force immediate sync to disk - important for dev builds where Xcode may kill app quickly
        defaults.synchronize()
        Log.info("[Consent] Persisted \(provider.shortName) = \(state.rawValue)", category: .initialization)
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
        // Check UserDefaults DIRECTLY to ensure we're reading persisted value
        // This avoids race conditions with SettingsStore initialization
        let key = ConsentDefaults.key(for: .applePCC)
        let persistedRaw = UserDefaults.standard.string(forKey: key)
        Log.info("[Consent Prewarm] Checking key '\(key)' = '\(persistedRaw ?? "nil")'", category: .initialization)

        if let persistedRaw,
           let persisted = CloudConsentState(rawValue: persistedRaw),
           persisted != .notDetermined {
            Log.info("[Consent Prewarm] PCC consent already determined (persisted): \(persisted.rawValue)", category: .initialization)
            // Also ensure in-memory state matches persisted state
            if cloudConsent[.applePCC] != persisted {
                cloudConsent[.applePCC] = persisted
            }
            return
        }

        // Also check in-memory state as backup
        if let state = cloudConsent[.applePCC], state != .notDetermined {
            Log.debug("[Consent Prewarm] PCC consent already determined (memory): \(state.rawValue)", category: .initialization)
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
        #if DEBUG
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
        #endif
    }

    /// Log final assembled context with keyword analysis
    private func logFinalContext(_ context: String, actualChunksUsed: Int, query: String) {
        #if DEBUG
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
        #endif
    }

    /// Scan all chunks for specification patterns and report findings
    /// This helps diagnose whether specs are present in the corpus
    private func runViscosityScan(_ allChunks: [DocumentChunk], query: String) async {
        #if DEBUG
        guard Log.pipelineTraceEnabled else { return }

        let separator = String(repeating: "═", count: 60)
        print("\n\(separator)")
        print("🔍 CORPUS SPECIFICATION SCAN")
        print("   Query: \(query)")
        print("   Total chunks: \(allChunks.count)")
        print(separator)

        // Scan for specification patterns (numbers with units, codes, grades)
        let specPattern = #"\b\d+(?:\.\d+)?\s*(?:W-\d+|L|ml|mm|cm|kg|g|psi|kPa|°[CF])\b"#
        var specChunks: [(idx: Int, page: Int?, match: String, preview: String)] = []

        for (idx, chunk) in allChunks.enumerated() {
            let content = chunk.content
            if let range = content.range(of: specPattern, options: .regularExpression) {
                let match = String(content[range])
                let preview = String(content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                specChunks.append((idx, chunk.metadata.pageNumber, match, preview))
            }
        }

        if specChunks.isEmpty {
            print("   ⚠️ NO SPECIFICATION PATTERNS FOUND")
            print("   Specifications may be in images/tables not extracted as text")
        } else {
            print("   ✅ Found \(specChunks.count) chunks with specification patterns:")
            for sc in specChunks.prefix(8) {
                let section = allChunks[sc.idx].metadata.sectionTitle ?? "—"
                print("   [\(sc.idx)] p.\(sc.page ?? 0) §\(section.prefix(25))")
                print("       Match: \(sc.match)")
                print("       \"\(sc.preview)...\"")
            }
            if specChunks.count > 8 {
                print("   ... and \(specChunks.count - 8) more")
            }
        }
        print(separator)
        #endif
    }

    // MARK: - Cross-Reference Resolution (Standard Pipeline)

    /// Lightweight cross-reference resolution for Standard mode.
    /// Scans retrieved chunks for patterns like "given in 'Section Name' on page X" and
    /// searches the full chunk pool for chunks from that section.
    ///
    /// Unlike the AgenticOrchestrator version (which runs a full retrieval pipeline per reference),
    /// this uses the already-loaded `allChunks` array for zero-latency lookups.
    /// This is safe because the Standard pipeline already has all chunks in memory.
    private func resolveCrossReferencesStandard(
        chunks: [RetrievedChunk],
        query: String,
        allChunks: [DocumentChunk]
    ) async -> [RetrievedChunk] {
        // Cross-reference patterns common in technical documents
        let patterns: [(regex: NSRegularExpression, group: Int)] = {
            var result: [(NSRegularExpression, Int)] = []
            // QUOTED: "given in 'Recommended lubricants and capacities' on page 9-7"
            // NOTE: In raw strings #"..."#, \u{} is literal text, NOT a Unicode escape.
            // ICU regex uses \x{HHHH} for Unicode code points.
            if let r = try? NSRegularExpression(
                pattern: #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: .caseInsensitive) { result.append((r, 1)) }
            // QUOTED: "see 'Section Name'" or "refer to 'Section Name'"
            if let r = try? NSRegularExpression(
                pattern: #"(?:see|refer\s+to|check|consult)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: .caseInsensitive) { result.append((r, 1)) }
            // UNQUOTED: "given in Recommended lubricants and capacities on page 9-7"
            // Case-insensitive to handle OCR variations. Optional "the" article.
            if let r = try? NSRegularExpression(
                pattern: #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive) { result.append((r, 1)) }
            // UNQUOTED: "see Recommended Lubricants on page X" or "refer to Section on page X"
            if let r = try? NSRegularExpression(
                pattern: #"(?:see|refer\s+to|check|consult)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive) { result.append((r, 1)) }
            // CATCH-ALL UNQUOTED: "given in <any text> on page" — most permissive fallback
            // Handles OCR artifacts, mixed case, special characters in section names
            if let r = try? NSRegularExpression(
                pattern: #"(?:given|found|listed|shown|described|specified|provided)\s+(?:in|under|at)\s+(?:the\s+)?(.{5,80})\s+on\s+page"#,
                options: .caseInsensitive) { result.append((r, 1)) }
            return result
        }()

        // Page reference pattern — directly resolve "page X-Y" or "page X"
        let pagePattern = try? NSRegularExpression(
            pattern: #"(?:on|see|,)\s+page\s+(\d+[-–]\d+|\d+)"#,
            options: .caseInsensitive
        )

        var referencedSections: Set<String> = []
        var referencedPages: Set<Int> = []

        // Scan top chunks for cross-references
        for chunk in chunks.prefix(10) {
            let content = chunk.chunk.content
            let range = NSRange(content.startIndex..., in: content)

            for target in chunk.chunk.metadata.resolvedReferences {
                let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "page":
                    let pageParts = parts[1].components(separatedBy: CharacterSet(charactersIn: "-–"))
                    for pagePart in pageParts {
                        if let pageNum = Int(pagePart.trimmingCharacters(in: .whitespaces)) {
                            referencedPages.insert(pageNum)
                        }
                    }
                case "section", "chapter", "appendix":
                    referencedSections.insert(parts[1])
                default:
                    break
                }
            }

            // Check section name patterns
            for (regex, group) in patterns {
                let matches = regex.matches(in: content, range: range)
                for match in matches {
                    guard match.numberOfRanges > group,
                          let captureRange = Range(match.range(at: group), in: content) else { continue }
                    let reference = String(content[captureRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if reference.count >= 5,
                       reference.range(of: #"^\d+[-–]?\d*$"#, options: .regularExpression) == nil {
                        referencedSections.insert(reference)
                    }
                }
            }

            // Check page number patterns ("on page 9-7", "see page 42")
            if let pageRegex = pagePattern {
                let pageMatches = pageRegex.matches(in: content, range: range)
                for match in pageMatches {
                    guard match.numberOfRanges > 1,
                          let captureRange = Range(match.range(at: 1), in: content) else { continue }
                    let pageStr = String(content[captureRange])
                    // Handle "9-7" format (chapter-page) — extract both numbers
                    let parts = pageStr.components(separatedBy: CharacterSet(charactersIn: "-–"))
                    for part in parts {
                        if let pageNum = Int(part.trimmingCharacters(in: .whitespaces)) {
                            referencedPages.insert(pageNum)
                        }
                    }
                }
            }
        }

        guard !referencedSections.isEmpty || !referencedPages.isEmpty else { return [] }

        Log.info("[CrossRef-Std] Found \(referencedSections.count) section refs: [\(referencedSections.joined(separator: ", "))], \(referencedPages.count) page refs: \(referencedPages.sorted())", category: .retrieval)

        let existingIds = Set(chunks.map { $0.chunk.id })
        var additionalChunks: [RetrievedChunk] = []

        // Search the in-memory chunk pool for referenced sections
        // This is fast — just string matching against already-loaded chunks
        for section in referencedSections.prefix(3) {
            let sectionLower = section.lowercased()
            let sectionWords = Set(sectionLower.split(separator: " ").map(String.init).filter { $0.count > 3 })

            // Find chunks whose content mentions the section name OR whose section header matches
            var matchingChunks: [(chunk: DocumentChunk, score: Float)] = []

            for chunk in allChunks where !existingIds.contains(chunk.id) {
                let contentLower = chunk.content.lowercased()
                let isSpecificationHeavy = chunk.metadata.documentCategory?.isSpecificationHeavy ?? false

                // Medium match: content contains most of the section name words (handles line breaks/OCR)
                let matchingWords = sectionWords.filter { contentLower.contains($0) }
                if let score = EvidenceScoringPolicyService.crossReferenceSectionScore(
                    content: chunk.content,
                    structureType: chunk.metadata.structureType,
                    hasNumericData: chunk.metadata.hasNumericData,
                    isSpecificationHeavy: isSpecificationHeavy,
                    matchesFullSection: contentLower.contains(sectionLower),
                    matchingWordCount: matchingWords.count,
                    totalSectionWordCount: sectionWords.count
                ) {
                    matchingChunks.append((chunk, score))
                }
            }

            // Sort by score, take top 3 per section
            matchingChunks.sort { $0.score > $1.score }
            for (matchChunk, score) in matchingChunks.prefix(3) {
                let docName = getDocumentName(for: matchChunk.documentId)
                additionalChunks.append(RetrievedChunk(
                    chunk: matchChunk,
                    similarityScore: score,
                    rank: 1,
                    sourceDocument: docName,
                    pageNumber: matchChunk.metadata.pageNumber
                ))
            }

            Log.info("[CrossRef-Std] '\(section.prefix(40))': found \(min(3, matchingChunks.count)) matching chunks", category: .retrieval)
        }

        // Phase 2: Page-number resolution — fetch chunks from referenced pages
        // This is the most robust approach: "page 9-7" → find chunks with pageNumber matching
        for pageNum in referencedPages.sorted().prefix(3) {
            let pageChunks = allChunks.filter { chunk in
                !existingIds.contains(chunk.id) &&
                !additionalChunks.contains(where: { $0.chunk.id == chunk.id }) &&
                chunk.metadata.pageNumber == pageNum
            }

            // Prioritize table/spec chunks from the referenced page
            let scored: [(chunk: DocumentChunk, score: Float)] = pageChunks.map { chunk in
                let queryWords = Set(query.lowercased().split(separator: " ").map(String.init).filter { $0.count > 3 })
                let contentLower = chunk.content.lowercased()
                let overlap = queryWords.filter { contentLower.contains($0) }.count
                let score = EvidenceScoringPolicyService.crossReferencePageScore(
                    content: chunk.content,
                    structureType: chunk.metadata.structureType,
                    hasNumericData: chunk.metadata.hasNumericData,
                    isSpecificationHeavy: chunk.metadata.documentCategory?.isSpecificationHeavy ?? false,
                    queryWordOverlap: overlap
                )
                return (chunk, score)
            }
            .sorted { $0.score > $1.score }

            for (matchChunk, score) in scored.prefix(3) {
                let docName = getDocumentName(for: matchChunk.documentId)
                additionalChunks.append(RetrievedChunk(
                    chunk: matchChunk,
                    similarityScore: score,
                    rank: 1,
                    sourceDocument: docName,
                    pageNumber: matchChunk.metadata.pageNumber
                ))
            }

            Log.info("[CrossRef-Std] Page \(pageNum): found \(min(3, pageChunks.count))/\(pageChunks.count) chunks", category: .retrieval)
        }

        return additionalChunks
    }

    // MARK: - Spec Table Sniper

    /// "Spec Table Sniper" — targeted search for chunks containing query keywords + numeric data.
    /// Bypasses semantic similarity and reranker scoring entirely.
    ///
    /// The reranker has an inherent prose bias (~0.78 for prose vs ~0.30 for tables).
    /// This method searches ALL chunks for co-occurrence of discriminative query keywords
    /// and numeric/structured data — the signature of specification tables, dosage charts,
    /// legal statute numbers, financial figures, or any factual lookup target.
    ///
    /// Universal: works for technical manuals, medical papers, legal documents, research data.
    private func specTableSniper(
        query: String,
        allChunks: [DocumentChunk],
        excludeIds: Set<UUID>
    ) -> [RetrievedChunk] {
        let queryLower = query.lowercased()

        // Extract meaningful query words (skip stopwords and short words)
        let precisionStopWords = Self.stopWords.union(["many", "much"])
        let queryWords = queryLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !precisionStopWords.contains($0) }
        let queryConcepts = buildSpecSearchConcepts(from: queryWords)

        // Need at least 2 meaningful keywords for targeted search
        guard queryConcepts.count >= 2 else { return [] }

        let conceptAliases = queryConcepts.map(\.aliases)

        var candidates: [(chunk: DocumentChunk, score: Float, matchCount: Int)] = []

        for chunk in allChunks where !excludeIds.contains(chunk.id) {
            guard let candidate = EvidenceScoringPolicyService.specSniperScore(
                content: chunk.content,
                structureType: chunk.metadata.structureType,
                queryConceptAliases: conceptAliases
            ) else {
                continue
            }

            candidates.append((chunk, candidate.score, candidate.matchCount))
        }

        // Sort by score, then by keyword match count for ties
        candidates.sort {
            if abs($0.score - $1.score) < 0.01 { return $0.matchCount > $1.matchCount }
            return $0.score > $1.score
        }

        // Take top 3 candidates
        return candidates.prefix(3).map { (chunk, score, _) in
            RetrievedChunk(
                chunk: chunk,
                similarityScore: score,
                rank: 1,
                sourceDocument: getDocumentName(for: chunk.documentId),
                pageNumber: chunk.metadata.pageNumber
            )
        }
    }

    private struct SpecSearchConcept {
        let aliases: [String]
    }

    private nonisolated func buildSpecSearchConcepts(from terms: [String]) -> [SpecSearchConcept] {
        var seen = Set<String>()
        var concepts: [SpecSearchConcept] = []

        for rawTerm in terms {
            let term = rawTerm.lowercased()
            guard seen.insert(term).inserted else { continue }

            var aliases = [term]
            switch term {
            case "gas":
                aliases.append(contentsOf: ["gasoline", "fuel"])
            case "gasoline":
                aliases.append(contentsOf: ["gas", "fuel"])
            case "fuel":
                aliases.append(contentsOf: ["gas", "gasoline"])
            case "gallon", "gallons", "gal":
                aliases.append(contentsOf: ["gal", "gallon", "gallons", "galon", "galons", "us gal"])
            case "liter", "liters", "litre", "litres":
                aliases.append(contentsOf: ["liter", "liters", "litre", "litres"])
            case "capacity", "capacities":
                aliases.append(contentsOf: ["capacity", "capacities", "volume"])
            case "hold", "holds", "holding":
                aliases.append(contentsOf: ["capacity", "capacities", "volume"])
            case "vehicle":
                aliases.append("car")
            case "car":
                aliases.append("vehicle")
            default:
                break
            }

            let uniqueAliases = Array(Set(aliases)).filter { $0.count > 1 }
            concepts.append(SpecSearchConcept(aliases: uniqueAliases))
        }

        return concepts
    }

    /// Demote chunks that merely contain cross-references to other sections.
    /// These chunks say "the answer is in Section X on page Y" but don't contain the actual answer.
    /// After the spec sniper has found actual data chunks, these pointer chunks should be deprioritized.
    private func demoteCrossReferenceChunks(_ chunks: inout [RetrievedChunk]) {
        let crossRefVerbs = ["given in", "refer to", "found in", "listed in",
                             "shown in", "specified in", "provided in", "described in"]

        for i in chunks.indices {
            let contentLower = chunks[i].chunk.content.lowercased()
            // Only demote if chunk has BOTH a cross-ref verb AND a page reference
            let hasCrossRef = crossRefVerbs.contains { contentLower.contains($0) }
            let hasPageRef = contentLower.contains("page")
            if hasCrossRef && hasPageRef {
                // Halve the score so cross-ref chunks sort below actual data chunks
                let demotedScore = chunks[i].similarityScore * 0.5
                chunks[i] = RetrievedChunk(
                    chunk: chunks[i].chunk,
                    similarityScore: demotedScore,
                    rank: chunks[i].rank,
                    sourceDocument: chunks[i].sourceDocument,
                    pageNumber: chunks[i].pageNumber
                )
            }
        }
    }

    private func countSpecPatterns(_ content: String) -> Int {
        EvidenceScoringPolicyService.specPatternCount(in: content)
    }

    // MARK: - Section Metadata Boost

    /// Boost retrieval scores for chunks whose sectionTitle/sectionPath match query keywords.
    ///
    /// **Why this matters**: Embeddings for "Engine Oil: SAE 0W-20" and "Gear Oil: SAE 75W/85"
    /// have nearly identical vector similarity to "what oil does this car take".
    /// But `sectionTitle = "Engine Oil"` vs `sectionTitle = "Differential Gear Oil"` is
    /// the disambiguating signal. This method boosts chunks whose section context
    /// matches the query's discriminative keywords.
    ///
    /// - Parameters:
    ///   - chunks: Retrieved chunks from hybrid search
    ///   - query: The user's original query
    /// - Returns: Chunks with boosted scores, re-sorted. Nil if no boost applied.
    static func applyMetadataBoost(
        chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk]? {
        // Extract keywords from query (lowercase, no stopwords)
        // UNIVERSAL: Only pure English function words — no domain-specific terms
        let stopwords: Set<String> = [
            "what", "whats", "which", "how", "much", "many", "does", "this", "that", "the",
            "a", "an", "is", "are", "was", "were", "do", "did", "can", "will",
            "should", "would", "could", "for", "with", "from", "into", "have", "has",
            "been", "be", "it", "its", "my", "your", "our", "their", "of", "in", "on",
            "at", "to", "and", "or", "not", "no", "about", "tell", "me", "explain",
            "describe", "show", "find", "get", "give", "list", "where", "when", "why",
            "there", "here", "also", "just", "some", "any", "all", "each", "every",
            "than", "then", "so", "if", "but", "up", "out", "by", "re"
        ]
        let queryWords = query.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
        let queryKeywords = Set(queryWords)

        guard !queryKeywords.isEmpty else { return nil }

        // IDF-awareness: count how many chunks have each keyword in their section title
        // Keywords appearing in >30% of sections are non-discriminative for boosting
        var sectionKeywordFreq: [String: Int] = [:]
        let chunksWithSections = chunks.filter { !trustedSectionKeywordSet(title: $0.chunk.metadata.sectionTitle, path: $0.chunk.metadata.sectionPath).isEmpty }
        for chunk in chunksWithSections {
            let titleWords = trustedSectionKeywordSet(title: chunk.chunk.metadata.sectionTitle, path: nil)
            for word in titleWords where queryKeywords.contains(word) {
                sectionKeywordFreq[word, default: 0] += 1
            }
        }
        let sectionCount = max(chunksWithSections.count, 1)
        let discriminativeKeywords = queryKeywords.filter { kw in
            let freq = sectionKeywordFreq[kw] ?? 0
            return Float(freq) / Float(sectionCount) < 0.30
        }

        // If ALL keywords are non-discriminative in sections, skip boosting entirely
        guard !discriminativeKeywords.isEmpty else {
            Log.debug("[MetadataBoost] All keywords non-discriminative in sections — skipping", category: .retrieval)
            return nil
        }

        // For multi-word queries, require at least 2 keyword matches (compound concept)
        // "smart mode" should NOT boost sections with just "smart" (Smart Cruise Control)
        // or just "mode" (Drive Mode) — only sections containing BOTH
        let requireMultiMatch = discriminativeKeywords.count >= 2

        var anyBoosted = false
        var boosted: [RetrievedChunk] = []

        for chunk in chunks {
            var boost: Float = 0.0

            // Check sectionTitle for keyword matches
            let titleSet = trustedSectionKeywordSet(title: chunk.chunk.metadata.sectionTitle, path: nil)
            if !titleSet.isEmpty {
                let titleMatches = discriminativeKeywords.intersection(titleSet)

                // For compound queries: require 2+ keyword matches in the section title
                // "smart mode" → only boost if title contains BOTH "smart" AND "mode"
                if requireMultiMatch && titleMatches.count < 2 {
                    // Single keyword match in a multi-keyword query — skip
                    // (prevents "Smart Cruise Control" from being boosted for "smart mode")
                } else {
                    // +0.08 per keyword match in sectionTitle
                    boost += Float(titleMatches.count) * 0.08
                }
            }

            // Check sectionPath (only if title didn't already match)
            if boost == 0 {
                let pathSet = trustedSectionKeywordSet(title: nil, path: chunk.chunk.metadata.sectionPath)
                let pathMatches = discriminativeKeywords.intersection(pathSet)

                if requireMultiMatch && pathMatches.count < 2 {
                    // Skip single-keyword path matches for compound queries
                } else {
                    boost += Float(pathMatches.count) * 0.04
                }
            }

            if boost > 0 {
                anyBoosted = true
                let cappedBoost = min(boost, 0.20)
                let newScore = min(chunk.similarityScore + cappedBoost, 1.0)

                boosted.append(RetrievedChunk(
                    chunk: chunk.chunk,
                    similarityScore: newScore,
                    rank: chunk.rank,
                    sourceDocument: chunk.sourceDocument,
                    pageNumber: chunk.pageNumber
                ))

                Log.debug(
                    "[MetadataBoost] Chunk \(chunk.chunk.metadata.chunkIndex) " +
                    "section='\(chunk.chunk.metadata.sectionTitle ?? "nil")' " +
                    "boosted \(String(format: "%.3f", chunk.similarityScore))→\(String(format: "%.3f", newScore))",
                    category: .retrieval
                )
            } else {
                boosted.append(chunk)
            }
        }

        guard anyBoosted else { return nil }

        // Re-sort by boosted scores (descending)
        boosted.sort { $0.similarityScore > $1.similarityScore }

        // Re-assign ranks
        return boosted.enumerated().map { idx, chunk in
            RetrievedChunk(
                chunk: chunk.chunk,
                similarityScore: chunk.similarityScore,
                rank: idx + 1,
                sourceDocument: chunk.sourceDocument,
                pageNumber: chunk.pageNumber
            )
        }
    }

    private func applyContextualDefinitionBoost(
        chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk]? {
        let queryTerms = Array(Set(extractQueryTerms(query)))
        guard !queryTerms.isEmpty else { return nil }

        var adjustedAny = false

        let boosted = chunks.map { candidate -> (chunk: RetrievedChunk, structured: Bool) in
            let content = candidate.chunk.parentContent ?? candidate.chunk.content
            let lowerContent = content.lowercased()
            let metadata = candidate.chunk.metadata
            let sectionKeywords = Self.trustedSectionKeywordSet(
                title: metadata.sectionTitle,
                path: metadata.sectionPath
            )
            let sectionMatchCount = queryTerms.reduce(into: 0) { result, term in
                if sectionKeywords.contains(term) {
                    result += 1
                }
            }
            let contentMatchCount = queryTerms.reduce(into: 0) { result, term in
                if lowerContent.contains(term) {
                    result += 1
                }
            }

            let hasDefinitionCue = lowerContent.range(
                of: #"\b(?:is|are|refers to|means|known as|called|defined as|first used in)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil || lowerContent.contains(" or ")
            let hasAliasCue = lowerContent.contains("(") && lowerContent.contains(")")
            let structuredText = looksTableLike(text: content, structureType: metadata.structureType)
                || lowerContent.contains("cell r")
                || lowerContent.contains("row ")
                || lowerContent.contains("column ")
                || content.contains("|")
            let paragraphLike = metadata.structureType == nil || metadata.structureType == "paragraph"

            var adjustedScore = candidate.similarityScore

            if metadata.abstractionLevel.isSummary {
                adjustedScore += 0.12
            }
            if metadata.chunkType == .prose || paragraphLike {
                adjustedScore += 0.05
            }
            if sectionMatchCount > 0 {
                adjustedScore += min(Float(sectionMatchCount) * 0.04, 0.12)
            }
            if contentMatchCount > 0 {
                adjustedScore += min(Float(contentMatchCount) * 0.03, 0.10)
            }
            if hasDefinitionCue {
                adjustedScore += 0.08
            }
            if hasAliasCue {
                adjustedScore += 0.04
            }

            if structuredText {
                adjustedScore -= 0.16
            }
            if metadata.chunkType == .tableStructural || metadata.chunkType == .tableSemantic {
                adjustedScore -= 0.10
            }
            if let tableTitle = metadata.tableTitle,
               !tableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                adjustedScore -= 0.06
            }
            if metadata.hasNumericData && !hasDefinitionCue && !metadata.abstractionLevel.isSummary {
                adjustedScore -= 0.03
            }

            adjustedScore = max(0.0, min(adjustedScore, 1.0))
            if abs(adjustedScore - candidate.similarityScore) >= 0.01 {
                adjustedAny = true
            }

            return (
                RetrievedChunk(
                    chunk: candidate.chunk,
                    similarityScore: adjustedScore,
                    rank: candidate.rank,
                    sourceDocument: candidate.sourceDocument,
                    pageNumber: candidate.pageNumber
                ),
                structuredText
            )
        }

        guard adjustedAny else { return nil }

        return boosted
            .sorted { lhs, rhs in
                if abs(lhs.chunk.similarityScore - rhs.chunk.similarityScore) >= 0.01 {
                    return lhs.chunk.similarityScore > rhs.chunk.similarityScore
                }
                if lhs.structured != rhs.structured {
                    return !lhs.structured
                }
                return lhs.chunk.rank < rhs.chunk.rank
            }
            .enumerated()
            .map { index, element in
                RetrievedChunk(
                    chunk: element.chunk.chunk,
                    similarityScore: element.chunk.similarityScore,
                    rank: index + 1,
                    sourceDocument: element.chunk.sourceDocument,
                    pageNumber: element.chunk.pageNumber
                )
            }
    }

    private static func trustedSectionKeywordSet(title: String?, path: [String]?) -> Set<String> {
        var keywords = Set<String>()

        if let titleKeywords = trustedSectionTokens(from: title) {
            keywords.formUnion(titleKeywords)
        }

        for component in path ?? [] {
            if let componentKeywords = trustedSectionTokens(from: component) {
                keywords.formUnion(componentKeywords)
            }
        }

        return keywords
    }

    private nonisolated static func trustedSectionDisplayPath(_ rawPath: [String]?) -> [String]? {
        let cleaned = (rawPath ?? []).compactMap(trustedSectionDisplayLabel)
        guard !cleaned.isEmpty else { return nil }

        return cleaned.reduce(into: [String]()) { result, component in
            if result.last?.caseInsensitiveCompare(component) != .orderedSame {
                result.append(component)
            }
        }
    }

    private nonisolated static func trustedSectionDisplayLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }

        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        return normalized
    }

    private static func trustedSectionTokens(from raw: String?) -> Set<String>? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }

        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        let tokens = normalized.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 }

        return tokens.isEmpty ? nil : Set(tokens)
    }

    // MARK: - Sentence-Level Extraction for Lookup Queries

    /// Result from sentence-level extraction
    struct SentenceExtractionResult: Sendable {
        let context: String
        let sourcesUsed: Int
        let sentencesIncluded: Int

        nonisolated static let empty = SentenceExtractionResult(context: "", sourcesUsed: 0, sentencesIncluded: 0)
    }

    /// Extracts query-relevant sentences from ALL candidate chunks and packs them
    /// into the context budget.  Instead of fitting 3 whole chunks (and hoping
    /// the answer is in one of them), this fits targeted lines from 10-15+ chunks.
    ///
    /// Universal across all domains — works for any document type.  Uses simple
    /// keyword + spec-pattern matching to score individual sentences.
    func extractRelevantSentences(
        from candidates: [RetrievedChunk],
        query: String,
        maxChars: Int,
        compact: Bool,
        isExtractiveFirst: Bool = false
    ) async -> SentenceExtractionResult {
        let extractionTask = Task.detached(priority: .utility) {
            Self.extractRelevantSentencesOffMain(
                from: candidates,
                query: query,
                maxChars: maxChars,
                compact: compact,
                isExtractiveFirst: isExtractiveFirst
            )
        }

        return await withTaskCancellationHandler {
            await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }

    private nonisolated static func extractRelevantSentencesOffMain(
        from candidates: [RetrievedChunk],
        query: String,
        maxChars: Int,
        compact: Bool,
        isExtractiveFirst: Bool
    ) -> SentenceExtractionResult {
        if Task.isCancelled {
            return .empty
        }

        // Keep sentence-scoring resources local to this detached task.
        // Shared static Set/regex storage has proven crash-prone on the utility queue.
        let lexicalStopWords: Set<String> = [
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
        let sentenceUnitRegex = try? NSRegularExpression(
            pattern: #"\d+(?:\.\d+)?\s*(?:qt|quart|gal|gallon|L|liter|litre|ml|oz|fl|kg|g|lb|lbs|mg|mcg|ug|mm|cm|m|km|in|ft|yd|mi|psi|kPa|MPa|bar|atm|rpm|hp|kW|MW|GW|Hz|kHz|MHz|GHz|TB|GB|MB|KB|V|mV|A|mA|W|kWh|MWh|Ah|mAh|cal|kcal|kJ|MJ|BTU|dB|dBm|lux|lm|cd|mol|IU|%)\b"#,
            options: .caseInsensitive
        )
        let sentenceSpecCodeRegex = try? NSRegularExpression(
            pattern: #"\b(?:API|ISO|SAE|ACEA|ASTM|IEEE|ANSI|IEC|NIST|OSHA|EPA|FDA|WHO|USP|NF|BP|JP|MIL-|SPEC-|UL|CE|FCC|RoHS|REACH|GMP|HACCP|NFPA|ASHRAE|ACI|AISI|AISC|AWS|ASME|DOT|FMVSS|ECE|JIS|DIN|EN|BS|AS|NZS|CSA|CAN|GB|GB/T)\s*[A-Z0-9./-]+"#
        )
        let sentenceStructuredCodeRegex = try? NSRegularExpression(
            pattern: #"\b[A-Z0-9]{1,6}[-./][A-Z0-9]{1,6}(?:[-./][A-Z0-9]{1,6})?\b"#
        )

        func meaningfulSentenceTokens(from lowercasedText: String) -> Set<String> {
            var tokens = Set<String>()
            tokens.reserveCapacity(16)

            for rawToken in lowercasedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                guard rawToken.count > 2 else { continue }

                let token = String(rawToken)
                guard !lexicalStopWords.contains(token) else { continue }
                tokens.insert(token)
            }

            return tokens
        }

        // Extract discriminative query keywords
        let queryLower = query.lowercased()
        let queryKeywords = queryLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !lexicalStopWords.contains($0) }

        guard !queryKeywords.isEmpty else {
            // Fallback: no usable keywords, return empty
            return .empty
        }
        let queryWordSet = Set(queryKeywords)

        func sentenceScore(
            line: String,
            headingContext: String,
            chunkIndex: Int,
            isExtractiveFirst: Bool
        ) -> Double? {
            let lineLower = line.lowercased()
            let headingLower = headingContext.lowercased()
            let lineWords = meaningfulSentenceTokens(from: lineLower)

            if !lineWords.isEmpty && !queryWordSet.isEmpty {
                let overlap = lineWords.intersection(queryWordSet).count
                let lineUnique = lineWords.subtracting(queryWordSet).count
                if overlap >= queryWordSet.count && lineUnique <= 1 {
                    return nil
                }
            }

            var directHits = 0
            for keyword in queryKeywords where lineLower.contains(keyword) {
                directHits += 1
            }

            var headingHits = 0
            for keyword in queryKeywords where headingLower.contains(keyword) {
                headingHits += 1
            }

            let totalKeywordHits = directHits + headingHits
            guard totalKeywordHits > 0 else { return nil }

            let specBoostMultiplier: Double = isExtractiveFirst ? 2.5 : 1.0
            let hasNumbers = line.rangeOfCharacter(from: .decimalDigits) != nil
            let numberBonus: Double = hasNumbers ? 2.0 : 0.0

            let unitHits = sentenceUnitRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let unitBonus = Double(min(unitHits, 3)) * 1.5 * specBoostMultiplier

            let specHits = sentenceSpecCodeRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let specBonus = Double(min(specHits, 3)) * 2.0 * specBoostMultiplier

            let keyValueBonus: Double = (line.contains(":") && hasNumbers) ? 1.5 * specBoostMultiplier : 0.0

            let codeHits = sentenceStructuredCodeRegex?
                .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
            let codeBonus = Double(min(codeHits, 3)) * 1.5 * specBoostMultiplier

            let rankBonus = max(0.0, 1.0 - Double(chunkIndex) * 0.05)
            let keywordScore = Double(directHits) * 3.0 + Double(headingHits) * 2.0
            let coverageFraction = Double(totalKeywordHits) / Double(max(1, queryKeywords.count))
            let coveragePenalty: Double = (queryKeywords.count >= 2 && coverageFraction < 0.5) ? 0.4 : 1.0

            return (keywordScore + numberBonus + unitBonus + specBonus + keyValueBonus + codeBonus + rankBonus)
                * coveragePenalty
        }

        // Score every sentence across all candidates
        struct ScoredSentence {
            let text: String          // The sentence/line itself
            let headingContext: String // The heading above this line (if any)
            let score: Double
            let sourceIndex: Int  // which chunk it came from
            let sourceDoc: String
            let pageNumber: Int?
        }

        var scoredSentences: [ScoredSentence] = []

        for (chunkIdx, candidate) in candidates.enumerated() {
            if Task.isCancelled {
                return .empty
            }

            let content = candidate.chunk.parentContent ?? candidate.chunk.content
            let source = candidate.sourceDocument
            let page = candidate.pageNumber

            // Split into individual lines first (preserve line order for heading tracking)
            let rawLines = content
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 3 }

            // Track the most recent heading-like line for context inheritance.
            // A "heading" is a short line (≤80 chars) without numbers that acts
            // as a section label in spec tables.  Universal across all documents.
            var currentHeading = ""

            for (lineIdx, rawLine) in rawLines.enumerated() {
                // Detect heading lines: short, no trailing numbers, typically labels
                let isHeading = rawLine.count <= 80
                    && rawLine.rangeOfCharacter(from: .decimalDigits) == nil
                    && !rawLine.contains("|")
                    && !rawLine.hasSuffix(".")

                if isHeading {
                    currentHeading = rawLine
                }

                // Split line into sub-sentences if it's prose (not table/spec data)
                let subLines: [String]
                if rawLine.contains("\t") || rawLine.contains("  ") || rawLine.contains("|") {
                    subLines = [rawLine]  // Table row — keep whole
                } else {
                    let parts = rawLine.components(separatedBy: ". ")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.count > 5 }
                    subLines = parts.isEmpty ? [rawLine] : parts
                }

                for subLine in subLines {
                    if Task.isCancelled {
                        return .empty
                    }

                    guard subLine.count > 5 else { continue }
                    var headingContext = ""
                    if !isHeading {
                        headingContext = currentHeading
                        if headingContext.isEmpty && lineIdx > 0 {
                            headingContext = rawLines[lineIdx - 1]
                        }
                    }

                    guard let totalScore = sentenceScore(
                        line: subLine,
                        headingContext: headingContext,
                        chunkIndex: chunkIdx,
                        isExtractiveFirst: isExtractiveFirst
                    ) else { continue }

                    let subLineLower = subLine.lowercased()
                    let headingLower = headingContext.lowercased()
                    let directHits = queryKeywords.reduce(0) { partialResult, keyword in
                        partialResult + (subLineLower.contains(keyword) ? 1 : 0)
                    }
                    let headingHits = queryKeywords.reduce(0) { partialResult, keyword in
                        partialResult + (headingLower.contains(keyword) ? 1 : 0)
                    }

                    // Determine heading context to include when packing
                    let effectiveHeading: String
                    if directHits == 0 && headingHits > 0 && !currentHeading.isEmpty {
                        // Line only matches via heading — include heading for context
                        effectiveHeading = currentHeading
                    } else {
                        effectiveHeading = ""
                    }

                    scoredSentences.append(ScoredSentence(
                        text: subLine,
                        headingContext: effectiveHeading,
                        score: totalScore,
                        sourceIndex: chunkIdx,
                        sourceDoc: source,
                        pageNumber: page
                    ))
                }
            }
        }

        // Sort by score descending
        scoredSentences.sort { $0.score > $1.score }

        // Deduplicate: remove near-identical sentences (same text, different chunks)
        // Phase 1: Exact-match dedup (fast, O(n))
        var seen: Set<String> = []
        scoredSentences = scoredSentences.filter { s in
            let key = s.text.lowercased().filter { $0.isLetter || $0.isNumber }
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // Phase 2: Fuzzy dedup using Jaccard word-set similarity
        // Catches near-duplicate sentences like "activated when the driver presses the Mode button"
        // vs "activated by pressing the Mode button" that share >70% of meaningful words.
        // O(n*m) where n=candidates, m=kept — acceptable since n is typically <100 after Phase 1.
        do {
            var keptSentences: [ScoredSentence] = []
            // Pre-compute word sets for kept sentences to avoid recomputation
            var keptWordSets: [Set<String>] = []

            for sentence in scoredSentences {
                if Task.isCancelled {
                    return .empty
                }

                let words = Set(
                    sentence.text.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 && !lexicalStopWords.contains($0) }
                )
                // Very short sentences: skip fuzzy dedup (not enough signal)
                guard words.count >= 3 else {
                    keptSentences.append(sentence)
                    keptWordSets.append(words)
                    continue
                }

                var isDuplicate = false
                for (idx, keptWords) in keptWordSets.enumerated() {
                    guard keptWords.count >= 3 else { continue }
                    let intersection = words.intersection(keptWords).count
                    let union = words.union(keptWords).count
                    let jaccard = Double(intersection) / Double(max(1, union))
                    if jaccard > 0.70 {
                        if Self.shouldKeepBothExactSentences(sentence.text, keptSentences[idx].text) {
                            continue
                        }
                        // Keep the higher-scoring one
                        if sentence.score > keptSentences[idx].score {
                            keptSentences[idx] = sentence
                            keptWordSets[idx] = words
                        }
                        isDuplicate = true
                        break
                    }
                }
                if !isDuplicate {
                    keptSentences.append(sentence)
                    keptWordSets.append(words)
                }
            }
            scoredSentences = keptSentences
        }

        // Pack into context budget
        var builder = String()
        builder.reserveCapacity(min(maxChars, 5000))
        var sourcesUsed: Set<Int> = []
        var sentenceCount = 0
        let headerOverhead = compact ? 30 : 80
        let separatorSize = compact ? 5 : 7

        // Group sentences by source into prose paragraphs (not one-per-line lists).
        // When each sentence is its own line, the FM regurgitates them as bullet lists.
        // Joining them with ". " creates natural paragraphs the FM will synthesize from.
        // Track per-source sentence buffers so same-source sentences merge into one block.
        var sourceBuffers: [Int: [String]] = [:]  // sourceIndex → [sentences]
        var sourceOrder: [Int] = []  // Track order of first appearance
        var sourceLabels: [Int: String] = [:]  // sourceIndex → label

        for sentence in scoredSentences {
            if Task.isCancelled {
                return .empty
            }

            let displayText = sentence.headingContext.isEmpty
                ? sentence.text
                : "\(sentence.headingContext) > \(sentence.text)"

            if sourceBuffers[sentence.sourceIndex] == nil {
                sourceOrder.append(sentence.sourceIndex)
                // Build source label — include section title so the LLM knows
                // what topic/metric each source covers. Critical for health data
                // and structured documents where compression strips headers,
                // leaving decontextualized data lines like "2024: 1,821 records,
                // avg 71.6 ms" with no indication of which metric they belong to.
                let sectionTag: String
                if sentence.sourceIndex < candidates.count,
                   let section = candidates[sentence.sourceIndex].chunk.metadata.sectionTitle,
                   !section.isEmpty {
                    sectionTag = " \(section) —"
                } else {
                    sectionTag = ""
                }
                if compact {
                    let filename = URL(fileURLWithPath: sentence.sourceDoc).lastPathComponent
                    sourceLabels[sentence.sourceIndex] = "[S\(sentence.sourceIndex + 1)]\(sectionTag) (\(filename))"
                } else {
                    let page = sentence.pageNumber.map { " p.\($0)" } ?? ""
                    sourceLabels[sentence.sourceIndex] = "[S\(sentence.sourceIndex + 1)]\(sectionTag) \(sentence.sourceDoc)\(page)"
                }
            }
            sourceBuffers[sentence.sourceIndex, default: []].append(displayText)
        }

        // Pack source paragraphs into budget
        for srcIdx in sourceOrder {
            if Task.isCancelled {
                return .empty
            }

            guard let sentences = sourceBuffers[srcIdx],
                  let label = sourceLabels[srcIdx] else { continue }

            // Join sentences into a prose paragraph
            let paragraph = sentences.map { sent in
                // Ensure sentence ends with period for natural flow
                let trimmed = sent.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || trimmed.hasSuffix(":") {
                    return trimmed
                }
                return trimmed + "."
            }.joined(separator: " ")

            let entry = label + "\n" + paragraph + "\n"
            let overhead = headerOverhead + separatorSize

            if builder.count + entry.count + overhead <= maxChars {
                if !sourcesUsed.isEmpty {
                    builder += compact ? "\n---\n" : "\n\n---\n\n"
                }
                builder += entry
                sourcesUsed.insert(srcIdx)
                sentenceCount += sentences.count
            } else {
                // Try fitting partial sentences from this source
                let remaining = maxChars - builder.count - overhead - label.count - 2
                if remaining > 50 && sourcesUsed.isEmpty || remaining > 100 {
                    var partial: [String] = []
                    var partialLen = 0
                    for sent in sentences {
                        if partialLen + sent.count + 2 > remaining { break }
                        partial.append(sent)
                        partialLen += sent.count + 2
                    }
                    if !partial.isEmpty {
                        let partialParagraph = partial.joined(separator: " ")
                        if !sourcesUsed.isEmpty {
                            builder += compact ? "\n---\n" : "\n\n---\n\n"
                        }
                        builder += label + "\n" + partialParagraph + "\n"
                        sourcesUsed.insert(srcIdx)
                        sentenceCount += partial.count
                    }
                }
                break
            }
        }

        return SentenceExtractionResult(
            context: builder,
            sourcesUsed: sourcesUsed.count,
            sentencesIncluded: sentenceCount
        )
    }

    private nonisolated static func exactSentenceAnchorTokens(from text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()
        let pattern = #"\b(?:\d+(?:[.,]\d+)?(?:\s*[-~/]\s*\d+(?:[.,]\d+)?)?(?:\s*(?:us\s*)?(?:gal(?:lon)?s?|l(?:iter)?s?|qt|quarts?|ml|kg|g|lb?s?|oz|mm|cm|m|km|mi|mph|km/h|psi|kpa|bar|°c|°f|%))?|[0o]w-\d{2}|75w/\d{2}|level\s*[123]|full open|user height setting|auto open|api\s+[a-z0-9 +/\-]+|ilsac\s+[a-z0-9\-]+|dot-4|gl-5)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(lower.startIndex ..< lower.endIndex, in: lower)
            for match in regex.matches(in: lower, options: [], range: range) {
                guard let tokenRange = Range(match.range, in: lower) else { continue }
                tokens.insert(String(lower[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return tokens
    }

    private nonisolated static func shouldKeepBothExactSentences(_ lhs: String, _ rhs: String) -> Bool {
        let lhsTokens = exactSentenceAnchorTokens(from: lhs)
        let rhsTokens = exactSentenceAnchorTokens(from: rhs)

        guard !lhsTokens.isEmpty || !rhsTokens.isEmpty else { return false }
        return lhsTokens != rhsTokens
    }

    // MARK: - Lexical Relevance Check

    /// Stop words to exclude from keyword matching
    private nonisolated static let stopWords: Set<String> = [
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
        let queryWords = extractQueryTerms(query)

        guard !queryWords.isEmpty else { return 0.5 } // Can't evaluate, assume ok

        // Prefer the focused chunk span, but include parent context when available so
        // table rows and rescued snippets still contribute lexical evidence.
        let chunkText = chunks.prefix(5)
            .map { chunk -> String in
                let content = chunk.chunk.content.lowercased()
                guard let parent = chunk.chunk.parentContent?.lowercased(), !parent.isEmpty, parent != content else {
                    return content
                }
                return content + " " + parent
            }
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
        AppSupportPaths.documentsMetadataURL()
    }

    private func loadDocumentsFromDisk() {
        let loadedDocuments = loadDocumentsSnapshotFromDisk()
        Task { @MainActor [weak self] in
            self?.applyLoadedDocuments(loadedDocuments)
        }
    }

    private func loadDocumentsSnapshotFromDisk() -> [Document] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documentsStorageURL.path) else {
            Log.info("  [RAGService] No existing documents metadata found")
            return []
        }

        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: documentsStorageURL)
            return try JSONDecoder().decode([Document].self, from: data)
        } catch {
            Log.error(" [RAGService] Failed to load documents metadata: \(error.localizedDescription)")
            return []
        }
    }

    @MainActor
    private func applyLoadedDocuments(_ loadedDocuments: [Document]) {
        documents = loadedDocuments
        totalChunksStored = loadedDocuments.reduce(0) { $0 + $1.totalChunks }
        syncAllContainerStats()
        Log.info("[RAGService] Loaded \(loadedDocuments.count) documents (\(totalChunksStored) chunks)")
        if !loadedDocuments.isEmpty {
            refreshIntelligence(for: nil)
        }
    }

    @MainActor
    func reloadWorkspaceData() {
        vectorRouter.clearAll()

        let loadedDocuments = loadDocumentsSnapshotFromDisk()
        applyLoadedDocuments(loadedDocuments)
        restorePersistedIngestionQueueIfNeeded()

        let fingerprint = localIndexSyncFingerprint(for: loadedDocuments)
        guard fingerprint != lastLocalIndexSyncFingerprint else {
            return
        }

        lastLocalIndexSyncFingerprint = fingerprint
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.rebuildLocalSearchIndexesFromCanonicalState(documents: loadedDocuments)
            if !succeeded {
                await MainActor.run {
                    self.lastLocalIndexSyncFingerprint = nil
                }
            }
        }
    }

    private func saveDocumentsToDisk() {
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(documents)
                try WorkspaceSyncService.coordinatedWriteData(data, to: documentsStorageURL)
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
            let chunks = try await db.allChunks()
            guard !chunks.isEmpty else { return [] }

            // Compatibility hydration for mmap-backed stores:
            // BNNSVectorDatabase intentionally stores metadata-only chunks (embedding: [])
            // to keep memory low during retrieval. Visualization views require embeddings,
            // so we fetch them explicitly for this call.
            if chunks.allSatisfy({ $0.embedding.isEmpty }) {
                let indices = Array(0..<chunks.count)
                let embeddings = await db.getEmbeddings(forIndices: indices)

                guard embeddings.count == chunks.count else {
                    Log.warning("[RAGService] Embedding hydration mismatch for visualization: chunks=\(chunks.count), embeddings=\(embeddings.count)")
                    return chunks
                }

                var hydrated: [DocumentChunk] = []
                hydrated.reserveCapacity(chunks.count)
                for i in 0..<chunks.count {
                    let chunk = chunks[i]
                    hydrated.append(
                        DocumentChunk(
                            id: chunk.id,
                            documentId: chunk.documentId,
                            content: chunk.content,
                            parentContent: chunk.parentContent,
                            contextualPrefix: chunk.contextualPrefix,
                            embedding: embeddings[i],
                            metadata: chunk.metadata
                        )
                    )
                }
                return hydrated
            }

            return chunks
        } catch {
            Log.error("[RAGService] Failed to load all chunks: \(error.localizedDescription)")
            return []
        }
    }

    /// Return a sample of chunks for content analysis (used by SuggestedQuestionsService)
    /// - Parameters:
    ///   - containerId: The container to sample from
    ///   - limit: Maximum number of chunks to return
    /// - Returns: Array of sample chunks for analysis
    func getSampleChunks(for containerId: UUID, limit: Int = 50) async throws -> [DocumentChunk] {
        guard let container = containerService.containers.first(where: { $0.id == containerId }) else {
            return []
        }
        let db = vectorRouter.db(for: container)
        let allChunks = try await db.allChunks()
        let detailChunks = allChunks.filter { $0.metadata.abstractionLevel == .detail }
        let summaryChunks = allChunks.filter { $0.metadata.abstractionLevel == .documentSummary }

        guard !allChunks.isEmpty else { return [] }

        if detailChunks.isEmpty {
            let sampleSource = summaryChunks.isEmpty ? allChunks : summaryChunks
            return prioritizedSuggestedQuestionSample(
                from: sampleSource,
                limit: min(limit, sampleSource.count)
            )
        }

        let summaryLimit = min(summaryChunks.count, max(1, min(3, limit / 4)))
        let detailLimit = min(detailChunks.count, max(0, limit - summaryLimit))

        let detailSample = detailLimit > 0
            ? prioritizedSuggestedQuestionSample(from: detailChunks, limit: detailLimit)
            : []

        guard summaryLimit > 0 else {
            return Array(detailSample.prefix(limit))
        }

        let summarySample = prioritizedSuggestedQuestionSample(
            from: summaryChunks,
            limit: min(summaryLimit, max(0, limit - detailSample.count))
        )

        guard !summarySample.isEmpty else {
            return Array(detailSample.prefix(limit))
        }

        return interleaveSuggestedQuestionSamples(
            primary: detailSample,
            secondary: summarySample,
            limit: limit
        )
    }

    private func interleaveSuggestedQuestionSamples(
        primary: [DocumentChunk],
        secondary: [DocumentChunk],
        limit: Int
    ) -> [DocumentChunk] {
        guard limit > 0 else { return [] }

        var result: [DocumentChunk] = []
        var primaryIndex = 0
        var secondaryIndex = 0

        if secondaryIndex < secondary.count {
            result.append(secondary[secondaryIndex])
            secondaryIndex += 1
        }

        while result.count < limit && (primaryIndex < primary.count || secondaryIndex < secondary.count) {
            for _ in 0..<2 {
                guard result.count < limit, primaryIndex < primary.count else { break }
                result.append(primary[primaryIndex])
                primaryIndex += 1
            }

            if result.count < limit, secondaryIndex < secondary.count {
                result.append(secondary[secondaryIndex])
                secondaryIndex += 1
            }
        }

        return result
    }

    private func prioritizedSuggestedQuestionSample(
        from chunks: [DocumentChunk],
        limit: Int
    ) -> [DocumentChunk] {
        guard !chunks.isEmpty else { return [] }

        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDocument[chunk.documentId, default: []].append(chunk)
        }

        for docId in byDocument.keys {
            byDocument[docId]?.sort { lhs, rhs in
                suggestedQuestionSampleScore(lhs) > suggestedQuestionSampleScore(rhs)
            }
        }

        let orderedDocumentIds = byDocument.keys.sorted { lhs, rhs in
            suggestedQuestionDocumentScore(byDocument[lhs] ?? []) > suggestedQuestionDocumentScore(byDocument[rhs] ?? [])
        }

        var selected: [DocumentChunk] = []
        var selectedIds: Set<UUID> = []
        var usedSections: Set<String> = []
        var round = 0

        while selected.count < limit {
            var addedThisRound = false

            for docId in orderedDocumentIds {
                guard selected.count < limit else { break }
                guard let docChunks = byDocument[docId], round < docChunks.count else { continue }

                let candidate = docChunks[round]
                guard selectedIds.insert(candidate.id).inserted else { continue }

                let section = suggestedQuestionSampleSection(for: candidate) ?? "default_\(candidate.id.uuidString.prefix(4))"
                let sectionKey = "\(docId.uuidString)::\(section.lowercased())"

                if usedSections.contains(sectionKey), selected.count >= orderedDocumentIds.count {
                    continue
                }

                selected.append(candidate)
                usedSections.insert(sectionKey)
                addedThisRound = true
            }

            if !addedThisRound {
                break
            }

            round += 1
        }

        if selected.count < limit {
            let remainder = orderedDocumentIds
                .flatMap { byDocument[$0] ?? [] }
                .sorted { lhs, rhs in
                    suggestedQuestionSampleScore(lhs) > suggestedQuestionSampleScore(rhs)
                }

            for candidate in remainder {
                guard selected.count < limit else { break }
                guard selectedIds.insert(candidate.id).inserted else { continue }
                selected.append(candidate)
            }
        }

        return selected
    }

    private func suggestedQuestionDocumentScore(_ chunks: [DocumentChunk]) -> Double {
        guard !chunks.isEmpty else { return 0 }

        let topChunkScore = chunks
            .map(suggestedQuestionSampleScore)
            .sorted(by: >)
            .prefix(3)
            .reduce(0, +)

        let uniqueSections = Set(chunks.compactMap { suggestedQuestionSampleSection(for: $0)?.lowercased() }).count
        let structuredChunks = chunks.filter { chunk in
            (chunk.metadata.structureType?.isEmpty == false) && chunk.metadata.structureType != "paragraph"
        }.count

        return topChunkScore
            + Double(min(uniqueSections, 5)) * 1.25
            + Double(min(structuredChunks, 4)) * 0.75
    }

    private func suggestedQuestionSampleScore(_ chunk: DocumentChunk) -> Double {
        var score = 0.0
        let wordCount = chunk.metadata.wordCount

        if wordCount >= 50 && wordCount <= 220 {
            score += 3.0
        } else if wordCount >= 30 && wordCount <= 320 {
            score += 2.0
        } else if wordCount >= 15 {
            score += 1.0
        }

        if chunk.metadata.hasNumericData {
            score += 2.5
        }

        if chunk.metadata.hasListStructure {
            score += 1.5
        }

        if chunk.metadata.sectionTitle != nil || chunk.metadata.sectionPath?.isEmpty == false {
            score += 1.0
        }

        if let structureType = chunk.metadata.structureType, structureType != "paragraph" {
            score += 2.0
        }

        if let imageDescription = chunk.metadata.imageDescription,
           !imageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1.0
        }

        if chunk.metadata.hasCrossReferences {
            score += 0.75
        }

        score += min(Double(chunk.metadata.entities.count), 3.0)
        score += min(Double(chunk.metadata.abbreviations.count) * 1.25, 2.5)

        if wordCount < 15 {
            score -= 5.0
        }

        score += suggestedQuestionSampleFrontMatterAdjustment(for: chunk)
        return score
    }

    private func suggestedQuestionSampleFrontMatterAdjustment(for chunk: DocumentChunk) -> Double {
        if let section = suggestedQuestionSampleSection(for: chunk),
           suggestedQuestionSampleUsesGenericSection(section) {
            return -5.0
        }

        let lower = suggestedQuestionSampleContent(for: chunk).lowercased()
        if suggestedQuestionSampleContainsFrontMatterSignal(lower) {
            return -4.0
        }

        return 0
    }

    private func suggestedQuestionSampleSection(for chunk: DocumentChunk) -> String? {
        if let section = chunk.metadata.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !section.isEmpty {
            return section
        }

        if let lastSection = chunk.metadata.sectionPath?.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastSection.isEmpty {
            return lastSection
        }

        if let tableTitle = chunk.metadata.tableTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tableTitle.isEmpty {
            return tableTitle
        }

        return nil
    }

    private func suggestedQuestionSampleContent(for chunk: DocumentChunk) -> String {
        let combined = [chunk.contextualPrefix, chunk.parentContent ?? chunk.content]
            .compactMap { value -> String? in
                let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return cleaned.isEmpty ? nil : cleaned
            }
            .joined(separator: "\n")

        return combined.isEmpty ? chunk.content : combined
    }

    private func suggestedQuestionSampleUsesGenericSection(_ title: String) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let genericSections: Set<String> = [
            "abstract", "acknowledgements", "about", "appendix", "author manuscript",
            "author contributions", "bibliography", "conflict of interest", "conclusion",
            "contents", "copyright", "disclaimer", "foreword", "funding", "glossary",
            "index", "introduction", "keywords", "notes", "overview", "preface",
            "references", "summary", "table of contents"
        ]

        return genericSections.contains(normalized) || suggestedQuestionSampleContainsFrontMatterSignal(normalized)
    }

    private func suggestedQuestionSampleContainsFrontMatterSignal(_ text: String) -> Bool {
        let signals: [String] = [
            "accepted for publication", "all rights reserved", "author contributions",
            "author manuscript", "competing interests", "conflict of interest",
            "conflicts of interest", "copyright", "corresponding author", "doi",
            "funding", "keywords", "published online", "rights reserved"
        ]

        return signals.contains { text.contains($0) }
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

                // If the library already has docs, schedule reindex so retrieval works again.
                // ALWAYS use the pending queue (not a direct Task) so onboarding can cancel it
                // via clearPendingReembeds() after sample import completes.
                let hasDocs = !self.documentsForContainer(container.id).isEmpty
                guard hasDocs else { return }

                self.enqueuePendingReembed(containerId: container.id)
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

    private func containerForId(_ containerId: UUID) async -> KnowledgeContainer? {
        await MainActor.run {
            self.containerService.containers.first { $0.id == containerId }
        }
    }

    private func contentTaggingEnabled(for container: KnowledgeContainer?) async -> Bool {
        if let override = container?.autoTagOnIngestion {
            return override
        }

        return await MainActor.run {
            self.settingsStore?.enableContentTagging ?? true
        }
    }

    private func translationTargetLanguage(for container: KnowledgeContainer?) -> Locale.Language? {
        guard let code = container?.preferredTranslationLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty
        else {
            return nil
        }

        return Locale.Language(identifier: code)
    }

    private func translatedQueryForEmbedding(
        _ query: String,
        container: KnowledgeContainer?
    ) async -> (text: String, wasTranslated: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let targetLanguage = translationTargetLanguage(for: container)
        else {
            return (trimmed, false)
        }

        do {
            let result = try await TranslationService.shared.translate(trimmed, to: targetLanguage)
            if result.isTranslated {
                let targetCode = targetLanguage.languageCode?.identifier ?? "?"
                Log.info("[Translation] Prepared translated retrieval query for target \(targetCode)", category: .retrieval)
            }
            return (result.translatedText, result.isTranslated)
        } catch {
            Log.warning("[Translation] Query translation failed, using original query: \(error)", category: .retrieval)
            return (trimmed, false)
        }
    }

    private func translatedTextsForEmbedding(
        _ texts: [String],
        container: KnowledgeContainer?
    ) async -> [String] {
        guard !texts.isEmpty,
              let targetLanguage = translationTargetLanguage(for: container)
        else {
            return texts
        }

        do {
            let results = try await TranslationService.shared.translateBatch(texts, to: targetLanguage)
            let translatedCount = results.reduce(into: 0) { partialResult, result in
                if result.isTranslated {
                    partialResult += 1
                }
            }
            if translatedCount > 0 {
                let targetCode = targetLanguage.languageCode?.identifier ?? "?"
                Log.info("[Translation] Prepared translated embeddings for \(translatedCount)/\(texts.count) chunks (target: \(targetCode))", category: .ingestion)
            }
            return results.map(\ .translatedText)
        } catch {
            Log.warning("[Translation] Chunk translation failed, embedding original text: \(error)", category: .ingestion)
            return texts
        }
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
        let container = await containerForId(embeddingContext.containerId)
        let translatedQuery = await translatedQueryForEmbedding(trimmed, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuery.text)
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
        let activeContainerId = containerService.activeContainerId
        let newItems = urls.map { url in
            let item = IngestionItem(
                url: url,
                containerId: activeContainerId,
                stage: .queued,
                detail: "Queued"
            )
            ingestionContexts[item.id] = context
            return item
        }
        ingestionItems.append(contentsOf: newItems)
        if ingestionItems.count > 1 {
            suppressProcessingSummary = true
        }
        savePersistedIngestionQueueState()
        if context == .userInitiated {
            liveActivityTrackedIngestionIds.formUnion(newItems.map(\.id))
            let subtitle = newItems.count == 1
                ? newItems[0].filename
                : "\(newItems.count) documents"
            IngestionRuntimeBridge.shared.beginUserInitiatedIngestion(
                title: "Importing documents",
                subtitle: subtitle
            )
            syncIngestionLiveActivity()
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

    @MainActor
    func runPendingIngestionQueue() async -> Bool {
        let ids = ingestionItems
            .filter { !$0.stage.isTerminal }
            .map(\.id)

        guard !ids.isEmpty else { return true }
        startIngestionTaskIfNeeded()
        let result = await waitForIngestionCompletion(ids: ids)
        return result.failureCount == 0 && result.completedIds.count == ids.count
    }

    private func runIngestionLoop() async {
        await MainActor.run { self.isProcessing = true }

        // Enable GPU embeddings to free ANE for Vision OCR (true parallelism)
        embeddingService.enableIngestionMode()
        Log.info("[RAGService] ⚡ Ingestion mode: GPU embeddings + ANE Vision OCR", category: .ingestion)

        while let next = await MainActor.run(body: { self.nextQueuedIngestionItem() }) {
            if Task.isCancelled { break }
            let context = await MainActor.run { self.ingestionContexts[next.id] ?? .userInitiated }
            do {
                try await addDocument(
                    at: next.url,
                    context: context,
                    trackingId: next.id,
                    manageProcessingState: false
                )
                if Task.isCancelled { break }
            } catch is CancellationError {
                await MainActor.run {
                    self.handleContinuedIngestionExpiration()
                }
                break
            } catch {
                await MainActor.run {
                    self.markIngestionFailed(id: next.id, error: error)
                }
            }
        }

        // Return to default compute mode
        embeddingService.disableIngestionMode()

        await MainActor.run {
            self.isProcessing = false
            self.processingStatus = ""
            self.ingestionTask = nil
            self.suppressProcessingSummary = false
            self.savePersistedIngestionQueueState()
            self.syncIngestionLiveActivity()
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
        guard !suppressReembedKicks else { return }  // Suppress during onboarding
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

    /// Start suppressing automatic reembed kicks (call before batch onboarding import)
    @MainActor
    func beginOnboardingBatch() {
        suppressReembedKicks = true
        Log.info("[RAGService] Suppressing reembed kicks for onboarding batch", category: .ingestion)
    }

    /// Clear any pending reembed operations (used after onboarding to prevent unnecessary rebuilds)
    @MainActor
    func clearPendingReembeds() {
        suppressReembedKicks = false  // Re-enable kicks
        pendingReembedContainerIds.removeAll()
        pendingReembedTask?.cancel()
        pendingReembedTask = nil
        Log.info("[RAGService] Cleared pending reembed queue", category: .ingestion)
    }

    @MainActor
    private func nextQueuedIngestionItem() -> IngestionItem? {
        let now = Date()
        let currentDeviceID = WorkspaceSyncService.currentDeviceID()
        guard let index = ingestionItems.firstIndex(where: { item in
            guard item.stage == .queued else { return false }
            return !item.hasActiveLease(at: now) || item.isLeased(to: currentDeviceID, at: now)
        }) else {
            return nil
        }

        var item = ingestionItems[index]
        item.claimLease(ownerDeviceId: currentDeviceID, duration: Self.ingestionLeaseDuration, now: now)
        ingestionItems[index] = item
        savePersistedIngestionQueueState()
        return item
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

        // Haptic feedback for stage transitions
        let oldStage = ingestionItems[index].stage
        if oldStage != stage {
            triggerIngestionHaptic(for: stage)
        }

        var item = ingestionItems[index]
        let currentDeviceID = WorkspaceSyncService.currentDeviceID()
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
            item.clearLease()
        } else if stage == .queued {
            item.clearLease()
        } else {
            item.claimLease(ownerDeviceId: currentDeviceID, duration: Self.ingestionLeaseDuration)
        }
        if let errorMessage {
            item.errorMessage = errorMessage
        }
        if let metricsUpdate {
            metricsUpdate(&item.metrics)
        }
        ingestionItems[index] = item
        savePersistedIngestionQueueState()
        IngestionRuntimeBridge.shared.updateContinuedIngestionProgress(
            title: "Importing documents",
            subtitle: "\(filename) • \(stage.displayName)",
            fraction: overallIngestionProgressFraction(currentItemId: item.id)
        )
        syncIngestionLiveActivity()
    }

    @MainActor
    private func overallIngestionProgressFraction(currentItemId: UUID?) -> Double {
        guard !ingestionItems.isEmpty else { return 0 }

        let completedCount = ingestionItems.filter { $0.stage == .complete }.count
        let activeContribution: Double
        if let currentItemId,
           let activeItem = ingestionItems.first(where: { $0.id == currentItemId }) {
            if let explicitProgress = activeItem.progress {
                activeContribution = explicitProgress
            } else if activeItem.stage.isTerminal {
                activeContribution = activeItem.stage == .complete ? 1 : 0
            } else if let pipelineIndex = activeItem.stage.pipelineIndex {
                activeContribution = Double(pipelineIndex + 1) / Double(max(1, IngestionStage.pipelineStages.count))
            } else {
                activeContribution = 0
            }
        } else {
            activeContribution = 0
        }

        let aggregate = Double(completedCount) + activeContribution
        return aggregate / Double(max(1, ingestionItems.count))
    }

    /// Haptic feedback based on ingestion stage
    @MainActor
    private func triggerIngestionHaptic(for stage: IngestionStage) {
        switch stage {
        case .loading, .extracting:
            DSHaptics.soft() // Just starting
        case .transcribing:
            DSHaptics.processingPulse() // Audio/video processing
        case .chunking, .analyzing, .adapting:
            DSHaptics.tick() // Processing ticks
        case .embedding:
            DSHaptics.processingPulse() // Neural processing
        case .indexing:
            DSHaptics.tick()
        case .storing:
            DSHaptics.soft()
        case .complete:
            DSHaptics.documentIngested() // Success!
        case .cancelled:
            break
        case .failed:
            DSHaptics.warning() // Something went wrong
        case .reindexing, .queued:
            break // No haptic for these
        }
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
            if Task.isCancelled {
                let snapshot = await MainActor.run {
                    ingestionItems.filter { ids.contains($0.id) }
                }
                return IngestionBatchResult(
                    successCount: snapshot.filter { $0.stage == .complete }.count,
                    failureCount: snapshot.filter { !$0.stage.isTerminal }.count,
                    totalCount: snapshot.count,
                    completedIds: snapshot.filter { $0.stage.isTerminal }.map(\.id)
                )
            }
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
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll interval (was 200ms)
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
                self.liveActivityTrackedIngestionIds = self.liveActivityTrackedIngestionIds.filter { trackedId in
                    self.ingestionItems.contains(where: { $0.id == trackedId })
                }
                self.syncIngestionLiveActivity()
                self.savePersistedIngestionQueueState()
            }
        }
    }

    @MainActor
    private func syncIngestionLiveActivity() {
        let trackedSnapshot = ingestionItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        let containerName = containerService.activeContainer?.name
        if !trackedSnapshot.isEmpty, trackedSnapshot.allSatisfy({ $0.stage.isTerminal }) {
            let success = trackedSnapshot.allSatisfy { $0.stage == .complete }
            IngestionRuntimeBridge.shared.finishLiveActivity(items: trackedSnapshot, containerName: containerName)
            IngestionRuntimeBridge.shared.completeUserInitiatedIngestion(success: success)
            liveActivityTrackedIngestionIds.removeAll()
            return
        }

        liveActivityTrackedIngestionIds = liveActivityTrackedIngestionIds.filter { trackedId in
            guard let item = ingestionItems.first(where: { $0.id == trackedId }) else { return false }
            return !item.stage.isTerminal
        }

        let trackedItems = ingestionItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        if trackedItems.isEmpty {
            IngestionRuntimeBridge.shared.endLiveActivity()
        } else {
            IngestionRuntimeBridge.shared.syncLiveActivity(items: trackedItems, containerName: containerName)
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
        let managedURL = try prepareManagedDocumentURL(from: url)
        try await WorkspaceSyncService.ensureItemAvailableLocally(at: managedURL)
        let filename = managedURL.lastPathComponent

        // Onboarding sample docs bypass quota — they're educational material
        // that ships with the app, not user-generated content
        let skipQuota = (context == .onboarding)

        let gating = await MainActor.run { () -> (limit: Int, canAdd: Bool, tier: WorkspaceTier, count: Int) in
            let count = self.documents.count
            if let store = self.entitlementStore {
                return (store.documentLimit, skipQuota || store.canAddDocument(currentCount: count), store.activeTier, count)
            } else {
                let limit = QuotaPolicy.documentLimit()
                return (limit, skipQuota || count < limit, .free, count)
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

        // Yield to let SwiftUI render the overlay (@Published updates propagate on next run loop)
        await Task.yield()

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
                at: managedURL,
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
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: managedURL.path)
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

            // Build domain vocabulary from extracted text for improved entity recognition
            let combinedText = processedChunks.map { $0.text }.joined(separator: " ")
            await GazetteerService.shared.extractAndAddTerms(from: combinedText, source: filename)

            // Index document in Spotlight for system-wide search
            let spotlightEnabled = await MainActor.run { self.settingsStore?.enableSpotlightIndexing ?? true }
            if spotlightEnabled {
                let cid = activeContainerId
                let containerName = await MainActor.run { self.containerService.containers.first(where: { $0.id == cid })?.name ?? "Library" }
                SpotlightIndexService.shared.indexDocument(
                    id: document.id,
                    filename: document.filename,
                    containerId: activeContainerId,
                    containerName: containerName,
                    textPreview: String(combinedText.prefix(500)),
                    chunkCount: processedChunks.count
                )
            }

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

            // Yield to let SwiftUI render chunking status
            await Task.yield()

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
                        detail: "Loading existing chunks for corpus analysis...",
                        progress: 0.1
                    ) { metrics in
                        metrics.isAutoAdaptive = true
                    }
                }

                // Get ALL existing chunks in this container for comprehensive analysis
                let db = await dbForActiveContainer()
                let existingChunks = try await db.allChunks()

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Analyzing \(existingChunks.count + processedChunks.count) chunks for vocabulary patterns...",
                        progress: 0.3
                    )
                }

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
                            createdAt: chunk.metadata.createdAt,
                            structureType: chunk.metadata.structureType,
                            siblingGroupId: chunk.metadata.siblingGroupId,
                            siblingCount: chunk.metadata.siblingCount,
                            entities: chunk.metadata.entities,
                            abbreviations: chunk.metadata.abbreviations,
                            abstractionLevel: chunk.metadata.abstractionLevel,
                            sectionPath: chunk.metadata.sectionPath,
                            bboxArray: chunk.metadata.bboxArray,
                            documentCategory: chunk.metadata.documentCategory,
                            chunkType: chunk.metadata.chunkType,
                            tableTitle: chunk.metadata.tableTitle,
                            imageContentType: chunk.metadata.imageContentType,
                            imageCaption: chunk.metadata.imageCaption,
                            imageDescription: chunk.metadata.imageDescription,
                            imageExtractedText: chunk.metadata.imageExtractedText,
                            imageClassifications: chunk.metadata.imageClassifications,
                            hasCrossReferences: chunk.metadata.hasCrossReferences,
                            resolvedReferences: chunk.metadata.resolvedReferences
                        )
                    )
                }

                // Update progress before analysis
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Detecting languages, code patterns, and domain signals...",
                        progress: 0.5
                    )
                }

                let report = await intelligenceCenter.analyzeLibrary(
                    documents: allDocumentsForAnalysis,
                    chunks: combinedChunks
                )

                // Update progress after analysis
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Computing optimal chunking and embedding strategy...",
                        progress: 0.8
                    )
                }

                let analysisTime = Date().timeIntervalSince(analysisStartTime)

                // Update metrics with analysis results
                let detectedLangs = report.corpus.languageHypotheses.sorted { $0.value > $1.value }.prefix(3).map { $0.key.rawValue }

                // Classify document domain from filename and content signals
                let domain = Self.classifyDocumentDomain(filename: filename, signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
                let descriptor = Self.buildContentDescriptor(signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
                let categories = Self.extractContentCategories(entities: report.documents.flatMap { $0.keyTopics }, signals: report.corpus)
                let primaryLang = detectedLangs.first.flatMap { Self.languageDisplayName($0) } ?? ""

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: domain.isEmpty ? "Analyzing content structure..." : "\(domain) • \(descriptor)",
                        progress: 1.0
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

                        // Document content profile (displayed in UI instead of raw ratios)
                        metrics.documentDomain = domain
                        metrics.contentDescriptor = descriptor
                        metrics.contentCategories = categories
                        metrics.documentLanguage = primaryLang
                        // extractionCoverage is set during extraction phase
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
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms flash
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
            let translatedChunkTexts = await translatedTextsForEmbedding(
                processedChunks.map(\ .text),
                container: container
            )

            // Get token limits from the embedding service
            let maxTokens = containerEmbeddingService.maxSafeTokens  // 510 for CoreML

            for (chunk, translatedChunkText) in zip(processedChunks, translatedChunkTexts) {
                // Build chunk-specific contextual prefix with FULL section hierarchy
                // Uses sectionPath (e.g. ["SPECIFICATIONS", "Engine Oil"]) for maximum
                // heading context in the embedding. This is THE key to making embeddings
                // discriminative — "[CarManual] [SPECIFICATIONS > Engine Oil] SAE 0W-20"
                // vs "[CarManual] [SPECIFICATIONS > Differential Gear Oil] SAE 75W/85"
                let sectionContext: String
                if let path = Self.trustedSectionDisplayPath(chunk.metadata.sectionPath), !path.isEmpty {
                    // Full hierarchical path: " [SPECIFICATIONS > Engine Oil]"
                    sectionContext = " [\(path.joined(separator: " > "))]"
                } else if let title = Self.trustedSectionDisplayLabel(chunk.metadata.sectionTitle) {
                    // Fallback to just title
                    sectionContext = " [\(title)]"
                } else {
                    sectionContext = ""
                }
                let contextualPrefix = docContext + sectionContext + " "
                contextualPrefixes.append(contextualPrefix)

                // Embed with contextual prefix prepended (Anthropic's key insight)
                var textForEmbedding = contextualPrefix + translatedChunkText

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
                progressHandler: { [weak self] (completed: Int, total: Int) in
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
            let documentChunks = zip(zip(processedChunks, embeddings), contextualPrefixes).enumerated().map { (index: Int, pair: ((DocumentProcessor.ProcessedChunk, [Float]), String)) in
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
                    createdAt: base.createdAt,
                    structureType: base.structureType,
                    siblingGroupId: base.siblingGroupId,
                    siblingCount: base.siblingCount,
                    entities: base.entities,
                    abbreviations: base.abbreviations,
                    abstractionLevel: base.abstractionLevel,
                    sectionPath: base.sectionPath,
                    bboxArray: base.bboxArray,
                    documentCategory: base.documentCategory,
                    chunkType: base.chunkType,
                    tableTitle: base.tableTitle,
                    imageContentType: base.imageContentType,
                    imageCaption: base.imageCaption,
                    imageDescription: base.imageDescription,
                    imageExtractedText: base.imageExtractedText,
                    imageClassifications: base.imageClassifications,
                    hasCrossReferences: base.hasCrossReferences,
                    resolvedReferences: base.resolvedReferences
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

            // Step 4.0.1: Store chunks in chunk-level FTS5 for section-aware BM25 search
            // This enables chunk-level BM25 scoring with section heading boosts:
            // "oil" matching in sectionTitle="Engine Oil" gets 10x the score of body text
            let fts5ChunkData: [(chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                                 sectionPath: String?, structureType: String?, chunkType: String?,
                                 tableTitle: String?, content: String,
                                 structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?)] =
                zip(documentChunks, processedChunks).map { chunk, processedChunk in
                    let pathStr = chunk.metadata.sectionPath?.joined(separator: " > ")
                    let structuredMetadata = processedChunk.structuredTable.map { table in
                        SQLiteFullTextService.StructuredChunkMetadata(
                            chunkType: chunk.metadata.chunkType?.rawValue,
                            tableTitle: table.title,
                            headers: table.headers,
                            rows: table.rows,
                            searchText: table.searchText,
                            extractionQuality: table.extractionQuality,
                            extractionSource: table.extractionSource,
                            lowQualityRowIndices: table.lowQualityRowIndices
                        )
                    }
                    return (
                        chunkIndex: chunk.metadata.chunkIndex,
                        pageNumber: chunk.metadata.pageNumber,
                        sectionTitle: chunk.metadata.sectionTitle,
                        sectionPath: pathStr,
                        structureType: chunk.metadata.structureType,
                        chunkType: chunk.metadata.chunkType?.rawValue,
                        tableTitle: chunk.metadata.tableTitle,
                        content: chunk.content,
                        structuredMetadata: structuredMetadata
                    )
                }
            await SQLiteFullTextService.shared.storeChunks(
                documentId: document.id,
                containerId: activeContainerId,
                chunks: fts5ChunkData
            )
            Log.info("[RAGService] Stored \(documentChunks.count) chunks in FTS5 chunk index", category: .ingestion)

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
                        embeddingService: containerEmbeddingService,
                        embeddingTranslationTarget: translationTargetLanguage(for: container)
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

            // Step 4.9: Persist vector store to disk (single write after all batch stores)
            // Deferred persistence avoids redundant JSON serialization after each storeBatch call
            try await db.persist()

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
            let contentTaggingEnabled = await contentTaggingEnabled(for: container)
            if #available(iOS 26.0, *), contentTaggingEnabled {
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
                var completeMetadata = ProcessingMetadata(
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
                completeMetadata.usedStructuredParsing = existingMetadata.usedStructuredParsing
                completeMetadata.structuredParsingQuality = existingMetadata.structuredParsingQuality
                completeMetadata.tablesExtracted = existingMetadata.tablesExtracted
                completeMetadata.tableRowsTotal = existingMetadata.tableRowsTotal
                completeMetadata.tableColumnsMax = existingMetadata.tableColumnsMax
                completeMetadata.listsExtracted = existingMetadata.listsExtracted
                completeMetadata.listItemsTotal = existingMetadata.listItemsTotal
                completeMetadata.titlesDetected = existingMetadata.titlesDetected
                completeMetadata.figureReferences = existingMetadata.figureReferences
                completeMetadata.visionEntitiesDetected = existingMetadata.visionEntitiesDetected
                completeMetadata.sectionPathDepth = existingMetadata.sectionPathDepth
                completeMetadata.structuredParsingTimeSeconds = existingMetadata.structuredParsingTimeSeconds
                completeMetadata.atomicTableChunks = existingMetadata.atomicTableChunks
                completeMetadata.atomicListChunks = existingMetadata.atomicListChunks
                completeMetadata.documentCategory = existingMetadata.documentCategory

                updatedDocument = Document(
                    id: document.id,
                    filename: document.filename,
                    fileURL: document.fileURL,
                    storageRelativePath: document.storageRelativePath,
                    fileHash: document.fileHash,
                    contentType: document.contentType,
                    addedAt: document.addedAt,
                    totalChunks: document.totalChunks,
                    processingMetadata: completeMetadata,
                    containerId: document.containerId,
                    contentTags: generatedContentTags
                )
            }

            // Ensure document is associated with the active container and has content tags
            let docWithContainer = Document(
                id: updatedDocument.id,
                filename: updatedDocument.filename,
                fileURL: updatedDocument.fileURL,
                storageRelativePath: updatedDocument.storageRelativePath,
                fileHash: updatedDocument.fileHash,
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
                syncContainerStats(for: activeContainerId, lastIndexedAt: Date())
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

            // Brief yield for UI to catch up before marking complete
            await Task.yield()

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

                // Record ingestion completion time to prevent immediate self-tuning rebuilds.
                // This stops the bug where adding a large PDF triggers re-embedding of ALL docs.
                self.lastIngestionCompletionTime[activeContainerId] = Date()

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

    private func prepareManagedDocumentURL(from url: URL) throws -> URL {
        if let relativePath = AppSupportPaths.relativePath(for: url) {
            return AppSupportPaths.documentURL(forRelativePath: relativePath)
        }

        let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(preferredFileName: url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: url, to: destinationURL)
        }
        return destinationURL
    }

    @MainActor
    private func localIndexSyncFingerprint(for documents: [Document]) -> String {
        documents
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { document in
                let containerComponent = document.containerId?.uuidString ?? "none"
                let pathComponent = document.storageRelativePath ?? document.fileURL.path
                return "\(document.id.uuidString)|\(containerComponent)|\(document.totalChunks)|\(pathComponent)"
            }
            .joined(separator: ";")
    }

    private func rebuildLocalSearchIndexesFromCanonicalState(documents: [Document]) async -> Bool {
        let snapshot = await MainActor.run {
            (self.containerService.containers, self.containerService.containers.first?.id)
        }
        let containers = snapshot.0
        let defaultContainerId = snapshot.1

        do {
            for container in containers {
                await SQLiteFullTextService.shared.deleteContainer(containerId: container.id)
                await SQLiteFullTextService.shared.deleteChunksForContainer(containerId: container.id)

                let containerDocuments = documents.filter { document in
                    (document.containerId ?? defaultContainerId) == container.id
                }
                guard !containerDocuments.isEmpty else { continue }

                let database = await MainActor.run { self.vectorRouter.db(for: container) }
                let allChunks = try await database.allChunks()
                let chunksByDocument = Dictionary(grouping: allChunks, by: \ .documentId)

                for document in containerDocuments {
                    guard let unsortedChunks = chunksByDocument[document.id], !unsortedChunks.isEmpty else {
                        continue
                    }

                    let documentChunks = unsortedChunks.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
                    let fullText = documentChunks.map(\ .content).joined(separator: "\n\n")
                    await SQLiteFullTextService.shared.store(text: fullText, for: document.id, containerId: container.id)

                    let chunkPayload = documentChunks.map { chunk in
                        (
                            chunkIndex: chunk.metadata.chunkIndex,
                            pageNumber: chunk.metadata.pageNumber,
                            sectionTitle: chunk.metadata.sectionTitle,
                            sectionPath: chunk.metadata.sectionPath?.joined(separator: " > "),
                            structureType: chunk.metadata.structureType,
                            chunkType: chunk.metadata.chunkType?.rawValue,
                            tableTitle: chunk.metadata.tableTitle,
                            content: chunk.content,
                            structuredMetadata: Optional<SQLiteFullTextService.StructuredChunkMetadata>.none
                        )
                    }
                    await SQLiteFullTextService.shared.storeChunks(
                        documentId: document.id,
                        containerId: container.id,
                        chunks: chunkPayload
                    )

                    let pages = Dictionary(grouping: documentChunks.compactMap { chunk -> (Int, String)? in
                        guard let pageNumber = chunk.metadata.pageNumber else { return nil }
                        return (pageNumber, chunk.content)
                    }, by: { $0.0 })
                        .map { pageNumber, contentPairs in
                            (
                                pageNumber: pageNumber,
                                content: contentPairs
                                    .sorted { $0.0 < $1.0 }
                                    .map(\ .1)
                                    .joined(separator: "\n\n")
                            )
                        }
                        .sorted { $0.pageNumber < $1.pageNumber }

                    if !pages.isEmpty {
                        await SQLiteFullTextService.shared.storePages(
                            pages: pages,
                            for: document.id,
                            containerId: container.id
                        )
                    }
                }
            }

            return true
        } catch {
            Log.error("[RAGService] Failed to rebuild local indexes from shared workspace: \(error.localizedDescription)", category: .ingestion)
            return false
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
        await SQLiteFullTextService.shared.deleteChunks(for: document.id)
        await FullTextStorageService.shared.delete(for: document.id)

        // Remove from Spotlight index
        SpotlightIndexService.shared.deindexDocument(id: document.id)

        // Remove entity index entries to prevent ghost entities from deleted documents
        await EntityIndexService.shared.removeDocument(document.id)

        // Invalidate visualization cache for active container after removal
        let activeId = await MainActor.run { self.containerService.activeContainerId }
        ProjectionCache.shared.invalidate(forContainer: activeId)

        await MainActor.run {
            documents.removeAll { $0.id == document.id }
            totalChunksStored -= document.totalChunks
            syncContainerStats(for: activeId)
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
        await SQLiteFullTextService.shared.deleteChunksForContainer(containerId: activeId)

        // Legacy file storage: Delete individual documents
        let docsToDelete = await MainActor.run {
            self.documents.filter { $0.containerId == activeId }
        }
        for doc in docsToDelete {
            await FullTextStorageService.shared.delete(for: doc.id)
        }

        // Remove all documents in this container from Spotlight
        SpotlightIndexService.shared.deindexContainer(id: activeId)

        await MainActor.run {
            documents.removeAll { $0.containerId == activeId }
            totalChunksStored = documents.reduce(0) { $0 + $1.totalChunks }
            syncContainerStats(for: activeId)
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

        // VISIBLE LOGGING: Make rebuild starts obvious in console
        Log.warning(
            "🔄 [Reembed] STARTING FULL REBUILD of \(documentsToRebuild.count) documents in container \(targetContainerId)\n" +
            "   Documents: \(documentsToRebuild.map { $0.filename }.joined(separator: ", "))",
            category: .ingestion
        )

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
                containerId: doc.containerId ?? targetContainerId,
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
        guard let container, let directive = container.chunkingDirective else { return nil }
        if container.autoAdaptDimension, directive.source != .auto {
            return nil
        }
        return DocumentProcessor.ChunkingOverride(
            strategy: directive.strategy,
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
        // VISIBLE LOGGING: Make self-tuning decisions obvious in console (not ghost process)
        Log.warning(
            "⚠️ [SelfTuning] AUTO-REBUILD SCHEDULED for container \(containerId)\n" +
            "   Reasons: \(reasons.joined(separator: " | "))\n" +
            "   This will re-embed ALL documents in the container!",
            category: .ingestion
        )

        // Log the scheduling intent for telemetry
        TelemetryCenter.emit(
            .ingestion,
            title: "Self-tuning rebuild scheduled",
            metadata: [
                "container": containerId.uuidString,
                "reasons": reasons.joined(separator: " | "),
            ]
        )

        // Use the pending reembed queue instead of a direct Task.
        // This allows onboarding to cancel pending rebuilds via clearPendingReembeds(),
        // preventing the wasteful delete-and-reimport cycle during first-run setup.
        enqueuePendingReembed(containerId: containerId)
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

        // CRITICAL FIX: Skip self-tuning if we just finished ingesting documents.
        // This prevents the scenario where processing a large PDF completes and then
        // immediately triggers re-embedding of ALL documents including what was just processed.
        // Self-tuning should wait until the user's batch is fully complete.
        let isInCooldown = await MainActor.run { () -> Bool in
            if let lastCompletion = self.lastIngestionCompletionTime[containerId] {
                let elapsed = Date().timeIntervalSince(lastCompletion)
                if elapsed < Self.selfTuningCooldownSeconds {
                    Log.info(
                        "[SelfTuning] Skipping auto-rebuild for container \(containerId) - " +
                        "in cooldown period (\(String(format: "%.1f", elapsed))s < \(Self.selfTuningCooldownSeconds)s)",
                        category: .ingestion
                    )
                    return true
                }
            }
            return false
        }
        if isInCooldown {
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

    private func executeAgenticPrecisionLookupIfAvailable(
        question: String,
        containerId: UUID,
        qualityMode: RAGQualityMode,
        startTime: Date
    ) async throws -> RAGResponse? {
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
        guard !isConceptualLookupQuery(question),
              (answerIntent.isExtractiveFirst || isPrecisionValueQuery(question)) else {
            return nil
        }

        emitThinkingEvent(
            .retrieval,
            title: "Precision lookup",
            detail: "Checking exact source values before multi-session reasoning"
        )

        func buildPrecisionResponse(
            directAnswer: String,
            precisionChunks: [RetrievedChunk],
            retrievalTime: TimeInterval,
            strategy: String
        ) async -> RAGResponse {
            emitThinkingEvent(
                .generation,
                title: "Direct answer locked",
                detail: "Exact value extracted from retrieved source"
            )
            let precisionConfidence = max(0.90, precisionChunks.first?.similarityScore ?? 0.0)
            emitThinkingEvent(
                .confidence,
                title: "Confidence: very high",
                detail: "\(String(format: "%.0f%%", precisionConfidence * 100)) source-locked"
            )

            var precisionAnswer = directAnswer
            var precisionWarnings: [String] = []
            var gatingDecision = "agentic_precision_extractive_override"
            var finalConfidence = precisionConfidence
            var structuredAnswer = StructuredAnswer.from(
                response: directAnswer,
                retrievedChunks: precisionChunks,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1
            )

#if canImport(FoundationModels)
            if #available(iOS 26.0, *),
               let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                   query: question,
                   candidateAnswer: directAnswer,
                   retrievedChunks: precisionChunks,
                   answerIntent: answerIntent,
                   verificationResult: nil,
                   isSourceLocked: true
               )
            {
                precisionAnswer = sourceOnlyOutcome.finalAnswer
                structuredAnswer = sourceOnlyOutcome.structuredAnswer
                gatingDecision = appendedGatingDecision(
                    gatingDecision,
                    sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                )
                precisionWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                if sourceOnlyOutcome.shouldAbstain,
                   let abstentionReason = sourceOnlyOutcome.abstentionReason
                {
                    precisionWarnings.append(abstentionReason)
                }
                finalConfidence = sourceOnlyOutcome.shouldAbstain
                    ? min(precisionConfidence, 0.35)
                    : min(precisionConfidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
            }
#endif

            let metadata = ResponseMetadata(
                timeToFirstToken: retrievalTime,
                totalGenerationTime: Date().timeIntervalSince(startTime),
                tokensGenerated: 0,
                tokensPerSecond: nil,
                modelUsed: "Direct Source Extraction (\(qualityMode.displayName))",
                retrievalTime: retrievalTime,
                retrievalConfigSummary: strategy,
                gatingDecision: gatingDecision,
                toolCallsMade: 0,
                usedAgenticMode: true,
                qualityModeName: qualityMode.displayName,
                originalQuery: question,
                reasoningTrace: [
                    "Precision lookup: found a high-confidence numeric source span and skipped multi-session synthesis."
                ]
            )

            await MainActor.run {
                self.deepThinkLiveSteps = 1
                self.deepThinkLiveConfidence = precisionConfidence
                self.deepThinkLiveTokens = 0
            }

            return RAGResponse(
                queryId: UUID(),
                retrievedChunks: precisionChunks,
                generatedResponse: resolvedDisplayResponse(
                    fallback: precisionAnswer,
                    structuredAnswer: structuredAnswer
                ),
                metadata: metadata,
                confidenceScore: finalConfidence,
                qualityWarnings: precisionWarnings,
                structuredAnswer: structuredAnswer
            )
        }

        let retrievalStart = Date()

        let embeddingContext = await resolveEmbeddingContext()
        let db = await dbFor(embeddingContext.containerId)
        let allChunks = try await db.allChunks()
        let sniperChunks = specTableSniper(
            query: question,
            allChunks: allChunks,
            excludeIds: []
        )
        if let directAnswer = await highPrecisionLookupOverrideAnswer(
            question: question,
            answerIntent: answerIntent,
            retrievedChunks: sniperChunks
        ) {
            let retrievalTime = Date().timeIntervalSince(retrievalStart)
            emitThinkingEvent(
                .retrieval,
                title: "Spec sniper",
                detail: "+\(sniperChunks.count) targeted chunks via keyword+number co-occurrence"
            )
            return await buildPrecisionResponse(
                directAnswer: directAnswer,
                precisionChunks: sniperChunks,
                retrievalTime: retrievalTime,
                strategy: "Agentic precision lookup"
            )
        }

        let precisionChunks = try await executeFullRetrievalPipeline(
            query: question,
            topK: max(24, qualityMode.initialTopK),
            minSimilarity: 0.03,
            qualityMode: qualityMode,
            onDetailedEvent: nil
        )
        let retrievalTime = Date().timeIntervalSince(retrievalStart)

        guard let directAnswer = await highPrecisionLookupOverrideAnswer(
            question: question,
            answerIntent: answerIntent,
            retrievedChunks: precisionChunks
        ) else {
            emitThinkingEvent(
                .verification,
                title: "Precision lookup",
                detail: "No high-confidence source span locked"
            )
            return nil
        }

        return await buildPrecisionResponse(
            directAnswer: directAnswer,
            precisionChunks: precisionChunks,
            retrievalTime: retrievalTime,
            strategy: "Agentic precision lookup"
        )
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
        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == containerId }
        }
        let selectedContainerName = selectedContainer?.name ?? "Library"
        let selectedRetrievalConfig = selectedContainer?.retrievalConfig ?? .default

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
            ("confTarget", isUnlimitedMode ? "98%" : "85%")
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

        let startTime = Date()

        // Always start agentic work from a clean FM session.
        // Reusing transcript state across Go Deeper or repeated Deep Think queries
        // is what causes the visible freezes in chat.
        await MainActor.run {
            self.cancelActiveGeneration(resetSession: true)
        }

        do {
            if let precisionResponse = try await executeAgenticPrecisionLookupIfAvailable(
                question: question,
                containerId: containerId,
                qualityMode: qualityMode,
                startTime: startTime
            ) {
                return precisionResponse
            }
        } catch {
            Log.warning("[AgenticPrecision] Direct lookup failed, continuing with agentic reasoning: \(error.localizedDescription)", category: .retrieval)
            emitThinkingEvent(.warning, title: "Precision lookup fallback", detail: "Continuing with Deep Think")
        }

        let orchestrator = AgenticOrchestrator(ragService: self, config: optimizedConfig, qualityMode: qualityMode)

        // Wrap execution in a tracked task so it can be cancelled by subsequent queries
        let agenticTask = Task<RAGResponse, Error> {
            try Task.checkCancellation()

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
                            guard let pipeIndex = step.output.firstIndex(of: "|") else { return }
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
                containerName: selectedContainerName,
                embeddingProviderId: "agentic",
                embeddingDim: 512,
                vectorDBKind: .persistentJSON,
                chunkingTargetWords: 300,
                chunkingOverlapWords: 50,
                chunkingSource: "agentic",
                qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                retrievalConfig: selectedRetrievalConfig,
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
                featureFlags: RAGAuditFeatureFlags(
                    answerIntent: isUnlimitedMode ? "maximum_agentic" : "deep_think_agentic",
                    queryWasRewritten: result.steps.contains { $0.type == .reformulating },
                    queryExpansionCount: 0,
                    usedHyDE: false,
                    usedIterativeRetrieval: false,
                    iterativePassCount: 0,
                    usedQueryRouting: raptorRoutingEnabled,
                    usedSummaryRouting: false,
                    usedParentDocumentRetrieval: false,
                    usedCorrectiveRetrieval: false,
                    usedContextualCompression: false,
                    usedGraphPacking: result.steps.contains { $0.type == .expanding },
                    usedRetrievalCascade: result.steps.contains { $0.type == .reformulating },
                    usedSupplementaryVectorSearch: false,
                    usedFullUnlimitedReasoning: isUnlimitedMode && llmCallCount >= 8
                ),
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

            let agenticAnswerIntent = QueryEnhancementService().classifyAnswerIntent(question)
            let generatedAgenticAnswer = repairMalformedURLs(cleanupResponseText(result.finalAnswer))
            let extractiveAgenticAnswer = await highPrecisionLookupOverrideAnswer(
                question: question,
                answerIntent: agenticAnswerIntent,
                retrievedChunks: result.retrievedChunks
            )
            let baseAgenticAnswer = extractiveAgenticAnswer ?? generatedAgenticAnswer
            var agenticAnswer = baseAgenticAnswer
            var agenticWarnings: [String] = []
            var agenticConfidence = result.confidence
            var gatingDecision: String?
            var structuredAnswer = StructuredAnswer.from(
                response: baseAgenticAnswer,
                retrievedChunks: result.retrievedChunks,
                answerIntent: agenticAnswerIntent,
                verificationResult: nil,
                loops: max(1, result.steps.count)
            )

#if canImport(FoundationModels)
            if #available(iOS 26.0, *),
               let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                   query: question,
                   candidateAnswer: baseAgenticAnswer,
                   retrievedChunks: result.retrievedChunks,
                   answerIntent: agenticAnswerIntent,
                   verificationResult: nil,
                   isSourceLocked: extractiveAgenticAnswer != nil
               )
            {
                agenticAnswer = sourceOnlyOutcome.finalAnswer
                structuredAnswer = sourceOnlyOutcome.structuredAnswer
                gatingDecision = sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                agenticWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                if sourceOnlyOutcome.shouldAbstain,
                   let abstentionReason = sourceOnlyOutcome.abstentionReason
                {
                    agenticWarnings.append(abstentionReason)
                }
                agenticConfidence = sourceOnlyOutcome.shouldAbstain
                    ? min(result.confidence, 0.35)
                    : min(result.confidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
            }
#endif

            let displayResponseText = resolvedDisplayResponse(
                fallback: agenticAnswer,
                structuredAnswer: structuredAnswer
            )

            return RAGResponse(
                queryId: UUID(),
                retrievedChunks: result.retrievedChunks,
                generatedResponse: displayResponseText,
                metadata: ResponseMetadata(
                    timeToFirstToken: totalTime / Double(max(1, result.steps.count)), // Estimate TTFT per step
                    totalGenerationTime: totalTime,
                    tokensGenerated: result.totalTokens,
                    tokensPerSecond: Float(result.totalTokens) / Float(totalTime),
                    modelUsed: "Apple Foundation Model (Agentic)",
                    retrievalTime: 0,
                    retrievalConfigSummary: "Agentic",
                    gatingDecision: gatingDecision,
                    toolCallsMade: result.steps.filter { $0.type == .searching }.count,
                    usedAgenticMode: true, // Agentic (deep) mode was used
                    qualityModeName: isUnlimitedMode ? "Maximum" : "Deep Think",
                    originalQuery: question,
                    reasoningTrace: reasoningTrace // Now includes the thinking steps!
                ),
                confidenceScore: agenticConfidence,
                qualityWarnings: agenticWarnings,
                structuredAnswer: structuredAnswer
            )
        }

        // Track this task so subsequent queries can cancel it
        await MainActor.run {
            self.activeAgenticTask = agenticTask
        }

        do {
            let response = try await withTaskCancellationHandler {
                try await agenticTask.value
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelActiveGeneration(resetSession: true)
                }
            }
            await MainActor.run { self.activeAgenticTask = nil }

            if response.metadata.usedAgenticMode {
                return await finalizeResponse(
                    query: question,
                    containerId: containerId,
                    containerName: selectedContainerName,
                    response: response
                )
            }

            return response
        } catch is CancellationError {
            await MainActor.run {
                self.cancelActiveGeneration(resetSession: true)
            }
            Log.info("[Agentic] Query cancelled (user sent new message)", category: .pipeline)
            throw CancellationError()
        } catch {
            await MainActor.run { self.activeAgenticTask = nil }
            if shouldFallbackAgenticPrecisionQuery(error: error, question: question) {
                Log.warning("[Agentic] Precision lookup fallback: rerouting to standard retrieval pipeline", category: .pipeline)
                await MainActor.run {
                    self.resetThinkingTimeline()
                }
                return try await self.queryInternal(
                    question,
                    topK: 3,
                    config: config,
                    containerId: containerId,
                    qualityModeOverride: .standard
                )
            }
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
        qualityModeOverride: RAGQualityMode? = nil,
        streamHandler: LLMStreamHandler? = nil
    ) async throws -> RAGResponse {
        resetThinkingTimeline()
        return try await LLMStreamingContext.$handler.withValue(streamHandler) {
            try await self.queryInternal(
                question,
                topK: topK,
                config: config,
                containerId: containerId,
                qualityModeOverride: qualityModeOverride
            )
        }
    }

    func queryWithAudit(
        _ question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        qualityModeOverride: RAGQualityMode? = nil,
        streamHandler: LLMStreamHandler? = nil
    ) async throws -> (response: RAGResponse, auditSnapshot: RAGAuditSnapshot?) {
        let response = try await query(
            question,
            topK: topK,
            config: config,
            containerId: containerId,
            qualityModeOverride: qualityModeOverride,
            streamHandler: streamHandler
        )
        return (response, lastAuditSnapshot)
    }

    private func queryInternal(
        _ question: String,
        topK: Int,
        config: InferenceConfig?,
        containerId: UUID?,
        qualityModeOverride: RAGQualityMode?
    ) async throws -> RAGResponse {
        // Mark query start in trace file for pipeline debugging
        Log.traceQueryStart(question)
        let queryStartTime = CFAbsoluteTimeGetCurrent()

        // Flush trace on exit regardless of how the function returns
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - queryStartTime
            Log.traceQueryEnd(responseLength: 0, duration: duration)
            Log.flushTraceLog()
        }

        // Report CPU activity for RAG pipeline orchestration
        await MainActor.run {
            HardwareTelemetryState.shared.reportRAGPipeline(stage: "Query Processing")
        }

        var inferenceConfig = config ?? InferenceConfig()
        let networkAvailable = NetworkMonitor.shared.isConnected
        let reliabilityModeEnabled = await MainActor.run {
            self.settingsStore?.reliabilityModeEnabled ?? true
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

        // Check user's quality mode setting to determine pipeline behavior
        // If user selected "deepThink" (Deep Think), use agentic orchestrator
        // Otherwise, use single-pass retrieval based on quality mode parameters
        let qualityMode = await MainActor.run {
            qualityModeOverride ?? self.settingsStore?.ragQualityMode ?? .standard
        }

        let initialQueryProfile = await QueryProfileService.shared.buildProfile(
            for: question,
            routingEnabled: false
        )

        let initialQueryPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: question,
            profile: initialQueryProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: qualityMode.usesAgenticOrchestrator
        )

        // Also check for manual override via forceAgenticOnNextQuery
        let forceAgentic = await MainActor.run {
            let forced = self.forceAgenticOnNextQuery
            self.forceAgenticOnNextQuery = false // Reset after checking
            return forced
        }

        let plannerEscalatedToAgentic = qualityMode.canonical == .standard && initialQueryPlan.shouldAutoEscalateToAgentic
        let useAgentic = forceAgentic || qualityMode.usesAgenticOrchestrator || plannerEscalatedToAgentic

        // Track query context for potential "Go Deeper" re-query
        await MainActor.run {
            self.lastQueryUsedAgentic = useAgentic
            self.lastQueryText = question
        }

        if forceAgentic {
            Log.info("[Pipeline] Query FORCED to agentic mode by user request", category: .pipeline)
        } else if plannerEscalatedToAgentic {
            Log.info("[Pipeline] Planner escalated Standard query to agentic execution: \(initialQueryPlan.reasoning)", category: .pipeline)
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

        emitThinkingEvent(
            .planning,
            title: "Execution plan: \(initialQueryPlan.executionMode.displayName)",
            detail: initialQueryPlan.reasoning
        )

        // Get adaptive pipeline config based on current device state (thermal, battery, memory)
        // This dynamically adjusts feature usage to prevent thermal throttling and save battery
        let queryComplexity = initialQueryProfile.adaptiveComplexity
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
        let qualityModeTemperature = qualityMode.temperature
        let qualityModeUsesQueryRewriting = qualityMode.usesQueryRewriting
        let qualityModeUsesIterativeRetrieval = qualityMode.usesIterativeRetrieval
        let qualityModeRequiresCitations = qualityMode.requiresCitations

        // NEW: Comprehensive quality mode feature toggles
        let qualityModeUsesHyDE = qualityMode.usesHyDE
        let qualityModeUsesReRanking = qualityMode.usesReRanking
        let qualityModeUsesMMR = qualityMode.usesMMR
        let qualityModeUsesVerificationGates = qualityMode.usesVerificationGates
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

        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == selectedId }
        }

        // OPTIMIZED: Use container's retrievalConfig if available, otherwise default.
        // Previous behavior hardcoded `.default` ignoring user-customized per-container weights.
        // Container settings UI lets users tune vector vs lexical weight — now those actually propagate.
        let retrievalConfig: RetrievalConfig = selectedContainer?.retrievalConfig ?? .default

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

        let queryWords = initialQueryProfile.wordCount
        let isTrivial = initialQueryProfile.isTrivial
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
        var auditAnswerIntent = "unknown"
        var auditQueryWasRewritten = false
        var auditQueryExpansionCount = 0
        var auditUsedHyDE = false
        var auditUsedIterativeRetrieval = false
        var auditIterativePassCount = 0
        var auditUsedQueryRouting = false
        var auditUsedSummaryRouting = false
        var auditUsedParentDocumentRetrieval = false
        var auditUsedCorrectiveRetrieval = false
        var auditUsedContextualCompression = false
        var auditUsedGraphPacking = false
        var auditUsedSupplementaryVectorSearch = false

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
                HardwareTelemetryState.shared.reportRAGPipeline(stage: "Corpus Analysis")
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

                    // Always load allChunks — needed for parent doc expansion, lexical recall,
                    // document summary, and multi-hop even when vocabulary is cached.
                    // Previously only loaded when pipelineTraceEnabled, which silently broke
                    // parent doc expansion on repeat queries to the same container.
                    let allChunks = try await vdb.allChunks()
                    cachedAllChunks = allChunks
                    if Log.pipelineTraceEnabled {
                        await runViscosityScan(allChunks, query: question)
                    }
                }

                let queryEnhancer = QueryEnhancementService(corpusVocabulary: finalCorpusVocabulary)
                let simpleGroundedLookup = initialQueryPlan.preferLiteralQuery
                let translatedInitialQuery = await translatedQueryForEmbedding(question, container: selectedContainer)
                let originalKeywordQuery = translatedInitialQuery.wasTranslated ? question : nil

                // Check advanced RAG settings
                let rewriteEnabledBySettings = settingsStore?.enableQueryRewriting ?? qualityModeUsesQueryRewriting
                let useQueryRewriting = rewriteEnabledBySettings && !simpleGroundedLookup
                // Note: Iterative retrieval is auto-enabled for multi-hop intents (investigate/compare/findings)
                // and can be force-enabled via settings toggle. See Step 3 below.

                // Step 1: LLM-Powered Query Understanding (if enabled)
                var effectiveQuery = translatedInitialQuery.text
                var queryWasRewritten = false
                var rewriteTime: TimeInterval = 0

                if useQueryRewriting {
                    Log.section("Step 1: Query Understanding", level: .info, category: .pipeline)
                    HardwareTelemetryState.shared.reportRAGPipeline(stage: "Query Understanding")
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
                            query: effectiveQuery,
                            documentNames: documentNames,
                            conversationContext: recentTurns
                        )
                        effectiveQuery = rewriteResult.rewritten
                        queryWasRewritten = rewriteResult.wasRewritten
                        auditQueryWasRewritten = rewriteResult.wasRewritten

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
                    if rewriteEnabledBySettings && simpleGroundedLookup {
                        Log.info("[RAGService] Query rewriting bypassed for simple grounded lookup", category: .retrieval)
                        emitThinkingEvent(
                            .planning,
                            title: "Keeping query literal",
                            detail: "Simple grounded lookup — skipping rewrite"
                        )
                    } else {
                        Log.debug("[RAGService] Query rewriting disabled, using original query", category: .pipeline)
                    }
                }

                // Step 1.5: Corpus-Aware Query Expansion
                // QUALITY MODE: Check if query expansion is enabled
                var expandedQueries: [String] = []
                var expansionTime: TimeInterval = 0

                if qualityModeUsesQueryExpansion {
                    Log.section("Step 1.5: Query Expansion", level: .info, category: .pipeline)
                    let expansionStartTime = Date()

                    let effectivePlanningProfile = await QueryProfileService.shared.buildProfile(
                        for: effectiveQuery,
                        queryEnhancer: queryEnhancer,
                        routingEnabled: false
                    )
                    let effectiveQueryPlan = await QueryExecutionPlannerService.shared.buildPlan(
                        for: effectiveQuery,
                        profile: effectivePlanningProfile,
                        requestedQualityMode: qualityMode,
                        allowToolCalling: false
                    )

                    expandedQueries = effectiveQueryPlan.searchQueries.filter {
                        $0.caseInsensitiveCompare(effectiveQuery) != .orderedSame
                    }

                    let heuristicExpansions = queryEnhancer.expandQuery(effectiveQuery)
                    for candidate in heuristicExpansions {
                        guard expandedQueries.count < qualityModeMaxQueryExpansions else { break }
                        guard !expandedQueries.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) else { continue }
                        expandedQueries.append(candidate)
                    }

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

                    // Step 1.5c: Gazetteer Domain Vocabulary Enrichment
                    // Adds domain-specific terms learned during ingestion (NLGazetteer)
                    let gazetteerMatches = await GazetteerService.shared.matchingTerms(for: effectiveQuery)
                    if !gazetteerMatches.isEmpty {
                        let gazetteerTerms = gazetteerMatches.map { $0.term }
                        let uniqueGazetteerTerms = gazetteerTerms.filter { !expandedQueries.contains($0) }
                        let gazetteerSpace = qualityModeMaxQueryExpansions - expandedQueries.count
                        let gazetteerToAdd = Array(uniqueGazetteerTerms.prefix(max(0, gazetteerSpace)))
                        expandedQueries.append(contentsOf: gazetteerToAdd)
                        if !gazetteerToAdd.isEmpty {
                            Log.debug("[RAGService] Gazetteer added \(gazetteerToAdd.count) domain terms", category: .retrieval)
                        }
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
                        auditQueryExpansionCount = expandedQueries.count
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

                let queryRoutingEnabled = settingsStore?.enableQueryRouting ?? true
                let effectiveQueryProfile = await QueryProfileService.shared.buildProfile(
                    for: effectiveQuery,
                    queryEnhancer: queryEnhancer,
                    queryRouter: queryRouter,
                    routingEnabled: queryRoutingEnabled
                )

                // Step 1.6: Answer Intent Classification (AppleRAG §6)
                // Classify query intent to optimize retrieval and answering strategy
                let answerIntent = effectiveQueryProfile.answerIntent
                let isProceduralQuery = answerIntent == .procedure
                let hasSummaryChunks = cachedAllChunks?.contains { $0.metadata.abstractionLevel == .documentSummary } ?? false
                let contextualDefinitionLookup = shouldUseContextualDefinitionLookupMode(
                    query: effectiveQuery,
                    answerIntent: answerIntent,
                    qualityMode: qualityMode,
                    hasSummaryChunks: hasSummaryChunks
                )
                let answerIntentIsExtractive = answerIntent.isExtractiveFirst && !contextualDefinitionLookup
                let answerNeedsDocumentSummary = answerIntent.requiresDocumentSummary || contextualDefinitionLookup
                auditAnswerIntent = answerIntent.rawValue
                Log.info(
                    "✓ Answer intent: \(answerIntent.rawValue) (extractive-first: \(answerIntentIsExtractive), multi-hop: \(answerIntent.benefitsFromMultiHop)\(contextualDefinitionLookup ? ", contextual-definition: true" : ""))",
                    category: .pipeline
                )
                emitThinkingEvent(
                    .intentRoute,
                    title: "Intent: \(answerIntent.rawValue)",
                    detail: contextualDefinitionLookup ? "Contextual definition lookup" : (answerIntentIsExtractive ? "Extractive-first" : (answerIntent.benefitsFromMultiHop ? "Multi-hop enabled" : "Standard"))
                )
                if contextualDefinitionLookup {
                    Log.info(
                        "[RAG] Standard contextual lookup: definition-style query will use summary + detail evidence",
                        category: .pipeline
                    )
                    emitThinkingEvent(
                        .planning,
                        title: "Contextual lookup",
                        detail: "Definition-style query → summary + detail grounding"
                    )
                }

                // Step 2: Embed the user's query
                Log.section("Step 2: Query Embedding", level: .info, category: .pipeline)
                let embeddingStartTime = Date()

                // HyDE: Combine quality mode toggle with user settings and service availability
                let hydeEnabledBySettings = settingsStore?.enableHyDE ?? true
                let hydeIsAvailable = HyDEService.isAvailable
                let hydeEnabledForMode = qualityModeUsesHyDE && hydeEnabledBySettings && hydeIsAvailable
                // ALWAYS log HyDE gate status so we can diagnose silent failures
                Log.info("[HyDE] Gates: qualityMode=\(qualityModeUsesHyDE), settings=\(hydeEnabledBySettings), available=\(hydeIsAvailable) → enabled=\(hydeEnabledForMode)", category: .retrieval)

                // CRITICAL: Disable HyDE for extractive/lookup queries to avoid hallucinated specifics biasing retrieval
                // HyDE can guess wrong values (e.g., "5W-40" when answer is "0W-20") and pull wrong chunks
                // Extractive-first intents (lookup, tableLookup) work better with keyword matching
                // Procedure intents need HyDE for semantic behavioral matching ("what does the button do?")
                let hydeDisabledForIntent = answerIntentIsExtractive
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
                        auditUsedHyDE = true
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
                HardwareTelemetryState.shared.reportRAGPipeline(stage: "Hybrid Search")
                // UPGRADED: Auto-enable iterative retrieval for multi-hop intents
                // (compare, investigate, findings) even if user hasn't toggled the setting.
                // The infrastructure is fully built — this just activates it where it matters.
                let userEnabledIterative = settingsStore?.enableIterativeRetrieval ?? false
                let iterativeAllowedForIntent = !answerIntentIsExtractive
                let useIterative = iterativeAllowedForIntent && (userEnabledIterative || (answerIntent.benefitsFromMultiHop && qualityModeUsesIterativeRetrieval))
                let iterativeConfig = IterativeRetrievalConfig.default

                if !iterativeAllowedForIntent && userEnabledIterative {
                    Log.info("[RAGService] Iterative retrieval bypassed for extractive intent '\(answerIntent.rawValue)'", category: .retrieval)
                    emitThinkingEvent(
                        .iterative,
                        title: "Iterative retrieval skipped",
                        detail: "Extractive intent — prefer direct grounded lookup"
                    )
                }

                let retrievalStartTime = Date()
                var retrievedChunks: [RetrievedChunk]
                var iterativeMetadata: (iterations: Int, confidence: Float, queries: Int)?

                // Classify query intent for adaptive weight tuning (used in both paths)
                let queryIntent = effectiveQueryProfile.searchIntent
                let adjustedWeights = effectiveQueryProfile.adjustedHybridWeights(from: retrievalConfig)
                let adjustedVectorWeight = adjustedWeights.vectorWeight
                let adjustedKeywordWeight = adjustedWeights.keywordWeight

                // Step 2.5: Query Classification for RAPTOR-lite (summary-first retrieval)
                // Determines whether to search document summaries (L1) or detail chunks (L0)
                // Controlled by settings.enableQueryRouting
                auditUsedQueryRouting = queryRoutingEnabled
                let queryClassification = effectiveQueryProfile.routingClassification

                // Pipeline Trace: Step 2.5 (RAPTOR-lite)
                if queryRoutingEnabled {
                    Log.pipelineStep("2.5", title: "RAPTOR-lite Query Routing", details: [
                        ("type", queryClassification.queryType.rawValue),
                        ("confidence", String(format: "%.0f%%", queryClassification.confidence * 100))
                    ])
                }
                var searchLevels = effectiveQueryProfile.abstractionLevelsToSearch
                if contextualDefinitionLookup && !searchLevels.contains(.documentSummary) {
                    searchLevels.insert(.documentSummary, at: 0)
                }

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
                    if hasSummaryChunks && (contextualDefinitionLookup || (queryClassification.queryType == .overview && queryClassification.confidence >= 0.5)) {
                        // For overview queries, prioritize summary chunks
                        filteredCachedChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                        if contextualDefinitionLookup {
                            Log.info(
                                "[RAPTOR-lite] Filtered to \(filteredCachedChunks?.count ?? 0) chunks (from \(allChunks.count)) for contextual definition lookup",
                                category: .retrieval
                            )
                            emitThinkingEvent(
                                .planning,
                                title: "Using summaries + details",
                                detail: "Definition query → blend document summaries with detail chunks"
                            )
                        } else {
                            auditUsedSummaryRouting = true
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
                        originalQuery: originalKeywordQuery ?? effectiveQuery,
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
                    auditUsedIterativeRetrieval = true
                    auditIterativePassCount = iterativeResult.iterations

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
                        query: expandedQueries.joined(separator: " "),
                        originalQuery: originalKeywordQuery ?? effectiveQuery,
                        embedding: queryEmbedding,
                        topK: effectiveTopK * 3,
                        cachedChunks: filteredCachedChunks,
                        containerId: selectedId
                    )

                    // UNIVERSAL FIX 9: Multi-vector supplementary retrieval.
                    // The primary search uses ONE embedding (HyDE or rewritten query).
                    // Query expansion generates ~12 variations but only uses them for BM25 text.
                    // Problem: if the primary embedding misses a needle due to vocabulary mismatch,
                    // it's invisible forever. Fix: embed top-2 unique expansion variations, run
                    // supplementary vector-only searches, merge any NEW chunks into results.
                    // This catches needles that exist in a different embedding neighborhood.
                    //
                    // CRITICAL: Only use APPENDED expansions (contain original query as substring),
                    // NOT replacement expansions. Synonym replacement queries like
                    // "What vehicle of oil does this automobile takes" embed into a completely
                    // different semantic neighborhood and pull in irrelevant chunks.
                    // Appended queries like "oil type specification SAE" stay on-topic.
                    let allowSupplementaryVectorSearch = !answerIntentIsExtractive && !isTrivial
                    if allowSupplementaryVectorSearch && expandedQueries.count > 1 {
                        let existingChunkIds = Set(retrievedChunks.map { $0.chunk.id })
                        let effectiveQueryLower = effectiveQuery.lowercased()
                        // Pick up to 2 expansions that:
                        // 1. Differ from the primary embedding text
                        // 2. Are sufficiently long
                        // 3. CONTAIN the original query (appended terms, not replacements)
                        //    OR are corpus phrase expansions (short focused phrases)
                        let supplementaryQueries = expandedQueries
                            .filter { expansion in
                                expansion != textToEmbed &&
                                expansion != effectiveQuery &&
                                expansion.count >= 10 &&
                                (expansion.lowercased().hasPrefix(effectiveQueryLower) ||
                                 expansion.count < effectiveQuery.count)  // Corpus phrases are shorter
                            }
                            .prefix(2)

                        if !supplementaryQueries.isEmpty {
                            Log.debug("[MultiVector] Running \(supplementaryQueries.count) supplementary vector searches", category: .retrieval)
                            for suppQuery in supplementaryQueries {
                                do {
                                    let translatedSupplementaryQuery = await translatedQueryForEmbedding(suppQuery, container: selectedContainer)
                                    let suppEmbedding = try await queryEmbeddingService.generateEmbedding(for: translatedSupplementaryQuery.text)
                                    let suppResults = try await vdb.search(embedding: suppEmbedding, topK: effectiveTopK)
                                    let newChunks = suppResults.filter { !existingChunkIds.contains($0.chunk.id) }
                                    if !newChunks.isEmpty {
                                        auditUsedSupplementaryVectorSearch = true
                                        retrievedChunks.append(contentsOf: newChunks)
                                        Log.debug("[MultiVector] +\(newChunks.count) new chunks from expansion: \"\(suppQuery.prefix(50))...\"", category: .retrieval)
                                    }
                                } catch {
                                    Log.debug("[MultiVector] Supplementary search failed: \(error.localizedDescription)", category: .retrieval)
                                }
                            }
                        }
                    } else if answerIntentIsExtractive && expandedQueries.count > 1 {
                        Log.debug("[MultiVector] Supplementary vector search skipped for extractive intent '\(answerIntent.rawValue)'", category: .retrieval)
                    }
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
                var chunksWithSources: [RetrievedChunk] = retrievedChunks.map { retrieved in
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

                // Step 3.5: Section Metadata Boost
                // Boost chunks whose sectionTitle/sectionPath match query keywords.
                // This is THE key signal that distinguishes "Engine Oil" chunks from "Gear Oil" chunks
                // when both contain oil specs with similar embeddings.
                // Requires Fix 1 (Title Case detection) and Fix 2 (.first→.last) to populate sectionTitle correctly.
                let sectionBoostedChunks = Self.applyMetadataBoost(
                    chunks: chunksWithSources,
                    query: question
                )

                if let boosted = sectionBoostedChunks {
                    chunksWithSources = boosted
                    Log.debug("[RAGService] Applied section metadata boost to \(chunksWithSources.count) chunks", category: .retrieval)
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
                let cascadeMetrics = RetrievalMetrics(
                    topSimilarity: cascadeTopSim,
                    secondSimilarity: 0,
                    averageTopFive: cascadeAvgTop5,
                    candidateCount: rerankedChunks.count
                )

                if let cascadeDecision = RetrievalPolicyService.cascadeDecision(
                    for: effectiveQueryProfile,
                    qualityMode: qualityMode,
                    retrievalConfig: retrievalConfig,
                    effectiveTopK: effectiveTopK,
                    totalStored: totalStored,
                    metrics: cascadeMetrics,
                    usedRetrievalCascade: usedRetrievalCascade
                ) {
                    let baseCandidateCount = rerankedChunks.count
                    let cascadeStartTime = Date()
                    let cascadeQuery = (expandedQueries + [question]).joined(separator: " ")
                    let cascadeHybrid = HybridSearchService(
                        vectorDatabase: vdb,
                        vectorWeight: cascadeDecision.vectorWeight,
                        keywordWeight: cascadeDecision.lexicalWeight
                    )
                    let cascadeRetrieved = try await cascadeHybrid.search(
                        query: cascadeQuery,
                        originalQuery: originalKeywordQuery ?? question,
                        embedding: queryEmbedding,
                        topK: cascadeDecision.topK
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
                                "🔁 Retrieval cascade added \(addedCount) candidates (lexical \(String(format: "%.2f", cascadeDecision.lexicalWeight)))",
                                category: .retrieval
                            )
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Retrieval cascade",
                                metadata: [
                                    "candidates": "\(mergedCandidates.count)",
                                    "lexicalWeight": String(format: "%.2f", cascadeDecision.lexicalWeight),
                                    "vectorWeight": String(format: "%.2f", cascadeDecision.vectorWeight),
                                ],
                                duration: cascadeTime
                            )
                            emitThinkingEvent(
                                .retrieval,
                                title: "Retrieval cascade",
                                detail: "\(mergedCandidates.count) candidates • lex \(String(format: "%.2f", cascadeDecision.lexicalWeight))"
                            )
                        }
                    }
                }

                if contextualDefinitionLookup,
                   let boostedDefinitionChunks = applyContextualDefinitionBoost(
                    chunks: rerankedChunks,
                    query: question
                   ) {
                    rerankedChunks = boostedDefinitionChunks
                    Log.info(
                        "[RAG] Contextual definition ranking applied: preferring summary/prose evidence over structured comparison fragments",
                        category: .retrieval
                    )
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
                let lenient = await MainActor.run {
                    self.settingsStore?.lenientRetrievalMode ?? false
                }
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

                let filteringMetrics = RetrievalMetrics(
                    topSimilarity: topSim,
                    secondSimilarity: secondSim,
                    averageTopFive: avgTop5,
                    candidateCount: rerankedChunks.count
                )
                let filteringDecision = RetrievalPolicyService.filteringDecision(
                    for: effectiveQueryProfile,
                    qualityMode: qualityMode,
                    retrievalConfig: retrievalConfig,
                    lenient: lenient,
                    metrics: filteringMetrics
                )
                let dynamicMin = filteringDecision.dynamicMinSimilarity
                let vocabularyMismatch = filteringDecision.vocabularyMismatch

                if vocabularyMismatch {
                    Log.info(
                        "[RAG] Vocabulary mismatch detected (topSim=\(String(format: "%.2f", topSim)), avgTop5=\(String(format: "%.2f", avgTop5))) - using adaptive floor \(String(format: "%.2f", dynamicMin))",
                        category: .retrieval
                    )
                } else if effectiveQueryProfile.answerIntent == .procedure {
                    Log.info("[RAG] Procedural query detected - requiring higher evidence threshold \(dynamicMin)", category: .retrieval)
                }

                auditDynamicMin = dynamicMin
                var filteredChunks = await engine.filterBySimilarity(
                    chunks: rerankedChunks,
                    min: dynamicMin
                )

                // Acceptance override if relative signals are strong even with modest absolute scores
                // Also override for vocabulary mismatch scenarios where we trust relative ranking
                let acceptanceOverride = filteringDecision.acceptanceOverride
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

                    // SPEC PRESERVATION: For extractive queries, rescue chunks with actual specification values.
                    // Cross-encoders often score table/spec chunks lower (sparse text, dense data)
                    // but these are exactly the chunks that contain the answer.
                    if answerIntentIsExtractive {
                        let filteredIds = Set(filteredChunks.map { $0.chunk.id })
                        let droppedChunks = rerankedChunks.filter { !filteredIds.contains($0.chunk.id) }

                        // Find dropped chunks with high spec scores
                        var rescuedChunks: [RetrievedChunk] = []
                        let specThreshold = 5  // Minimum spec pattern score to rescue

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
                            let maxRescue = min(5, rescuedChunks.count)
                            let topRescued = Array(rescuedChunks.prefix(maxRescue))

                            // OPTIMIZED: Boost rescued chunks to topScore - 0.02 instead of + 0.05.
                            // Previous behavior made rescued chunks rank HIGHER than the best RRF result,
                            // which could pollute results if spec detection misfires.
                            // Now: rescued chunks rank just below the top result — included in context
                            // but won't displace genuinely high-relevance content.
                            let topScore = filteredChunks.first?.similarityScore ?? 0.8
                            let rescueScore = max(topScore - 0.02, 0.5)  // Floor at 0.5 to ensure inclusion
                            let boostedRescued = topRescued.map { chunk -> RetrievedChunk in
                                RetrievedChunk(
                                    chunk: chunk.chunk,
                                    similarityScore: rescueScore,
                                    rank: 1,
                                    sourceDocument: chunk.sourceDocument,
                                    pageNumber: chunk.pageNumber
                                )
                            }

                            // Insert at front so they're available for MMR selection
                            filteredChunks.insert(contentsOf: boostedRescued, at: 0)

                            Log.info(
                                "   🔧 Spec preservation: rescued \(topRescued.count) spec chunks (score=\(String(format: "%.2f", rescueScore)))",
                                category: .retrieval
                            )
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Spec preservation",
                                metadata: [
                                    "rescued": "\(topRescued.count)",
                                    "intent": answerIntent.rawValue,
                                    "boostedScore": String(format: "%.2f", rescueScore)
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
                var mmrLambda: Float = retrievalConfig.mmrLambda

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
                    // Note: isProceduralQuery already defined in Step 4.3.
                    // Use the library's retrieval config as the base, override for procedural queries.
                    mmrLambda = isProceduralQuery ? max(retrievalConfig.mmrLambda, 0.85) : retrievalConfig.mmrLambda
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
                            qualityWarnings: ["High Accuracy mode: insufficient supporting evidence"],
                            structuredAnswer: StructuredAnswer.refusal(
                                reason: caution,
                                missing: ["High Accuracy mode blocked the answer because the retrieved evidence was too weak."],
                                topScore: diverseChunks.first?.similarityScore ?? 0,
                                loops: 1,
                                retrievedChunks: diverseChunks
                            )
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

                // Enumeration queries need ALL chunk slots for detail —
                // RAPTOR summaries waste 25% of context on generic overviews.
                // Covers: "how many X", "list all X", "what are all the X", "show every X", etc.
                let isEnumerationQuery: Bool = {
                    let lq = question.lowercased()
                    let quickTriggers = [
                        "how many", "list all", "list every", "list the", "list each",
                        "name all", "name every", "show all", "show every",
                        "what are all", "give me all", "give me every", "enumerate",
                        "how many kinds", "how many categories",
                        "count the", "count all", "total number of",
                    ]
                    return quickTriggers.contains { lq.contains($0) }
                }()

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
                if answerNeedsDocumentSummary && !isEnumerationQuery, let allChunks = cachedAllChunks {
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

                // ═══════════════════════════════════════════════════════════════════
                // ITERATIVE RETRIEVAL: BM25 second-pass for enumeration queries
                // ═══════════════════════════════════════════════════════════════════
                // When asking "how many X are available", vector search retrieves
                // chunks ABOUT the topic but misses the actual enumerated list page
                // (sparse, low semantic density). A targeted BM25 keyword scan over
                // ALL chunks in the container finds it.
                // ═══════════════════════════════════════════════════════════════════
                if isEnumerationQuery, let allChunks = cachedAllChunks, !allChunks.isEmpty {
                    let existingIds = Set(contextCandidates.map { $0.chunk.id })

                    // Extract subject noun from enumeration query patterns:
                    // "how many [NOUN] are available" → NOUN
                    // "list all [NOUN]"               → NOUN
                    // "what are all the [NOUN]"       → NOUN
                    // "show every [NOUN]"             → NOUN
                    // "total number of [NOUN]"        → NOUN
                    let lq = question.lowercased()
                    let stopWords: Set<String> = [
                        "are", "is", "does", "do", "can", "will", "were", "was",
                        "have", "has", "for", "the", "in", "on", "at", "to", "of",
                        "available", "there", "exist", "supported", "included",
                        "a", "an", "this", "that", "it", "its", "my", "your",
                    ]
                    let subjectNoun: String = {
                        // Try each trigger phrase, extract noun after it
                        let triggers = [
                            "how many ", "list all ", "list every ", "list the ", "list each ",
                            "name all ", "name every ", "show all ", "show every ",
                            "what are all the ", "what are all ", "what are the ",
                            "give me all ", "give me every ",
                            "total number of ", "count the ", "count all ",
                            "enumerate ",
                        ]
                        for trigger in triggers {
                            if let range = lq.range(of: trigger) {
                                let afterTrigger = String(lq[range.upperBound...])
                                let words = afterTrigger.split(separator: " ")
                                let nouns = words.prefix(4).filter { !stopWords.contains(String($0)) }
                                if !nouns.isEmpty {
                                    return nouns.map(String.init).joined(separator: " ")
                                }
                            }
                        }
                        return ""
                    }()

                    if !subjectNoun.isEmpty {
                        let bm25 = BM25Scorer()
                        bm25.indexDocuments(allChunks)
                        let queryTerms = bm25.tokenize(subjectNoun)

                        // Score ALL chunks by BM25 keyword match
                        var scored: [(chunk: DocumentChunk, score: Float)] = []
                        for chunk in allChunks {
                            let s = bm25.score(queryTerms: queryTerms, document: chunk.content)
                            if s > 0 { scored.append((chunk, s)) }
                        }
                        scored.sort { $0.score > $1.score }

                        // Inject top BM25 results not already in candidates
                        var added = 0
                        for (chunk, bm25Score) in scored.prefix(15) {
                            guard !existingIds.contains(chunk.id), added < 5 else { continue }
                            let docName = getDocumentName(for: chunk.documentId)
                            contextCandidates.append(RetrievedChunk(
                                chunk: chunk,
                                similarityScore: min(bm25Score / 10.0, 0.85),
                                rank: contextCandidates.count,
                                sourceDocument: docName,
                                pageNumber: chunk.metadata.pageNumber
                            ))
                            added += 1
                        }

                        if added > 0 {
                            contextStrategy = "enumeration_iterative"
                            Log.info(
                                "[Iterative Retrieval] Enumeration 2nd pass: +\(added) BM25 chunks for '\(subjectNoun)'",
                                category: .retrieval
                            )
                            emitThinkingEvent(
                                .retrieval,
                                title: "Iterative Retrieval",
                                detail: "BM25 2nd pass: +\(added) chunks targeting '\(subjectNoun)' list"
                            )

                            if Log.pipelineTraceEnabled {
                                logChunkTrace(contextCandidates, stage: "Post-EnumerationIterative", query: question)
                            }
                        }
                    }
                }

                // Step 4.6: Parent Document Retrieval (optional)
                // Expand matched chunks to include sibling context from same section/page
                // Respect quality mode toggle, user settings, AND adaptive pipeline (thermal/battery aware)
                let parentDocEnabledBySettings = settingsStore?.enableParentDocumentRetrieval ?? true
                let useParentDocRetrieval = qualityModeUsesParentDocRetrieval && parentDocEnabledBySettings && adaptiveConfig.enableParentDocumentRetrieval

                if useParentDocRetrieval, contextCandidates.count > 0, let allChunks = cachedAllChunks {
                    auditUsedParentDocumentRetrieval = true
                    let parentConfig = RetrievalPolicyService.parentDocumentConfig(
                        for: effectiveQueryProfile,
                        qualityMode: qualityMode,
                        maxSiblingChunks: qualityModeMaxSiblingChunks,
                        useAgentic: useAgentic
                    )
                    if effectiveQueryProfile.answerIntent == .procedure {
                        Log.info("[RAG] Procedural query - using maximum parent expansion (8 siblings)", category: .retrieval)
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
                            .parentDoc,
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

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 4.6: Cross-Reference Resolution
                // Technical documents often say "see Section X on page Y". The actual
                // data (spec tables, values) lives in the referenced section but the
                // reranker scores prose cross-references higher than the actual table.
                // Scan retrieved chunks for cross-refs and fetch the referenced content.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                if answerIntentIsExtractive {
                    let crossRefChunks = await resolveCrossReferencesStandard(
                        chunks: contextCandidates,
                        query: question,
                        allChunks: cachedAllChunks ?? []
                    )
                    if !crossRefChunks.isEmpty {
                        // Insert cross-referenced chunks near the top so they survive context assembly
                        let existingIds = Set(contextCandidates.map { $0.chunk.id })
                        let newChunks = crossRefChunks.filter { !existingIds.contains($0.chunk.id) }
                        contextCandidates.insert(contentsOf: newChunks, at: 0)
                        Log.info("[RAG] Cross-reference resolution: +\(newChunks.count) chunks from referenced sections", category: .retrieval)
                        emitThinkingEvent(.retrieval, title: "Cross-ref resolved", detail: "+\(newChunks.count) chunks from referenced sections")
                    }
                }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 4.8: Targeted Spec Retrieval ("Spec Table Sniper")
                // The reranker has an inherent prose bias: prose scores ~0.78 while
                // tables/specs score ~0.30. For lookup/extractive queries, bypass
                // semantic scoring entirely and search ALL chunks for co-occurrence
                // of query keywords + numeric data.
                //
                // This is the "needle in a haystack" sniper — universal across domains:
                // medical dosages, legal statute numbers, technical specs, financial data.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                if answerIntentIsExtractive, let allChunks = cachedAllChunks {
                    let existingIds = Set(contextCandidates.map { $0.chunk.id })
                    let sniperResults = specTableSniper(
                        query: question,
                        allChunks: allChunks,
                        excludeIds: existingIds
                    )
                    if !sniperResults.isEmpty {
                        // Insert at position 0 — these targeted results should survive
                        // context assembly budget cuts ahead of prose chunks
                        contextCandidates.insert(contentsOf: sniperResults, at: 0)

                        // Demote chunks that merely CITE other sections ("given in X on page Y")
                        // now that we have the actual data they were pointing to
                        demoteCrossReferenceChunks(&contextCandidates)

                        Log.info("[RAG] Spec sniper: +\(sniperResults.count) targeted chunks from \(allChunks.count) total (keyword+number co-occurrence)", category: .retrieval)
                        emitThinkingEvent(.retrieval, title: "Spec sniper", detail: "+\(sniperResults.count) targeted chunks via keyword+number co-occurrence")
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
                    emitThinkingEvent(.compression, title: "Compression skipped", detail: "Procedural query — preserving step ordering")
                }

                if skipCompressionForVocabMismatch {
                    Log.info("[RAG] Skipping compression for vocabulary mismatch - compressor can't judge relevance", category: .retrieval)
                    emitThinkingEvent(.compression, title: "Compression skipped", detail: "Vocabulary mismatch — compressor can't judge relevance")
                }

                if skipCompressionForParentExpansion {
                    Log.info("[RAG] Skipping compression for parent-expanded content - chunks exceed compression model capacity", category: .retrieval)
                    emitThinkingEvent(.compression, title: "Compression skipped", detail: "Parent-expanded chunks exceed model capacity")
                }

                if useContextualCompression, HyDEService.isAvailable, contextCandidates.count > 0 {
                    auditUsedContextualCompression = true
                    // SMART COMPRESSION BUDGET: Estimate how many chunks will fit in context
                    // before wasting time compressing all candidates. Context budget typically
                    // fits 3-5 chunks, so compressing 18 at ~3s each = 54s wasted.
                    // Only compress top-N where N = estimated fit + small buffer.
                    // Use conservative inline estimates (exact budget is computed later):
                    //   4096 window - ~1500 overhead/prompt - ~50 question - 300 output = ~2246 tokens
                    let estQuestionTokens = max(20, question.count / 4)
                    let estimatedAvailableTokens = 4096 - 1500 - estQuestionTokens - 300
                    let estimatedCharsAvailable = Int(Double(estimatedAvailableTokens) * 1.4 * 0.88)
                    var totalChars = 0
                    var estimatedFit = 0
                    for candidate in contextCandidates {
                        totalChars += candidate.chunk.text.count
                        if totalChars <= max(estimatedCharsAvailable, 3500) {
                            estimatedFit += 1
                        }
                    }
                    // Add buffer of 2 so compression can potentially include slightly more
                    let compressionLimit = min(contextCandidates.count, max(estimatedFit + 2, 5))

                    // Cap compression to max 5 chunks (~15s) to preserve LLM rate-limit
                    // budget for the actual generation step. Without this cap, 10+ chunks
                    // at ~3s each = 30s+ of sequential LLM calls that exhaust Apple FM
                    // rate limits before the main generation even starts.
                    let maxCompressionChunks = 5
                    let cappedCompressionLimit = min(compressionLimit, maxCompressionChunks)

                    // Skip compression entirely if only 3 or fewer chunks fit — ROI is negative
                    // (3 chunks × 3s = 9s for negligible token savings)
                    if cappedCompressionLimit <= 3 {
                        Log.info("[RAG] Skipping compression - only \(estimatedFit) chunks fit in context budget (ROI negative)", category: .retrieval)
                        emitThinkingEvent(.compression, title: "Compression skipped", detail: "Only \(estimatedFit) chunks fit — ROI negative")
                    } else if compressionLimit > maxCompressionChunks {
                        Log.info("[RAG] Capping compression from \(compressionLimit) to \(maxCompressionChunks) chunks to preserve LLM rate budget for generation", category: .retrieval)
                        emitThinkingEvent(.compression, title: "Compression capped", detail: "\(compressionLimit)→\(maxCompressionChunks) chunks — protecting generation budget")
                    }

                    let chunksToCompress = cappedCompressionLimit <= 3 ? [] : Array(contextCandidates.prefix(cappedCompressionLimit))
                    let compressionService = ContextualCompressionService()
                    let chunkTexts = chunksToCompress.map { $0.chunk.text }
                    // Pass section titles so compression LLM understands chunk topics.
                    // Without this, abbreviation queries like "HRV" get 319→2 token compression
                    // because the chunk body has only raw stats without the full metric name.
                    let sectionTitles = chunksToCompress.map { $0.chunk.metadata.sectionTitle }

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
                            sectionTitles: sectionTitles,
                            config: compressionConfig
                        )
                        let compressionTime = Date().timeIntervalSince(compressionStartTime)

                        // Update only the compressed chunks; leave remaining candidates untouched
                        var updatedCandidates: [RetrievedChunk] = []
                        var droppedIrrelevantCount = 0
                        for (index, result) in compressionResults.enumerated() where index < chunksToCompress.count {
                            let original = chunksToCompress[index]

                            // CRITICAL: If compression LLM says NO_RELEVANT_CONTENT, REMOVE the chunk entirely.
                            // Keeping 400-char stubs wastes precious context budget (only 3 chunks fit!)
                            // and those stubs compete with actually relevant chunks in spec sort.
                            // The compression LLM already proved it can distinguish topics accurately.
                            if result.wasMarkedIrrelevant {
                                droppedIrrelevantCount += 1
                                Log.debug("[Compression] Dropping irrelevant chunk: \(original.chunk.text.prefix(50))...", category: .retrieval)
                                continue  // Skip — don't add to candidates
                            }

                            let effectiveText = result.effectiveContent

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
                        if droppedIrrelevantCount > 0 {
                            Log.info("[Compression] Removed \(droppedIrrelevantCount) irrelevant chunks — freeing context space", category: .retrieval)
                        }

                        let originalTokens = compressionResults.reduce(0) { $0 + $1.originalTokens }
                        let compressedTokens = compressionResults.reduce(0) { $0 + $1.compressedTokens }
                        let lowRelevanceCount = compressionResults.filter { $0.wasMarkedIrrelevant }.count
                        compressionSavings = originalTokens - compressedTokens

                        if updatedCandidates.count > 0 {
                            // Merge: compressed chunks replace front, uncompressed remain at tail
                            let remaining = Array(contextCandidates.dropFirst(updatedCandidates.count))
                            contextCandidates = updatedCandidates + remaining
                            let lowRelNote = lowRelevanceCount > 0 ? " (\(lowRelevanceCount) fallback)" : ""
                            Log.info("[Compression] \(originalTokens)→\(compressedTokens) tokens saved \(compressionSavings) in \(String(format: "%.0f", compressionTime * 1000))ms\(lowRelNote)", category: .retrieval)
                            emitThinkingEvent(
                                .compression,
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

                    // Cooldown: let Apple FM rate limits recover after sequential compression
                    // calls before the main generation step. Without this pause, generation
                    // frequently hits .rateLimited immediately after 5 compression calls.
                    if compressionSavings > 0 {
                        Log.debug("[RAG] Post-compression cooldown (1s) to recover FM rate budget", category: .retrieval)
                        try? await Task.sleep(for: .seconds(1))
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
                        auditUsedGraphPacking = true
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

                let shouldAttemptCorrective = shouldAttemptCorrectiveRetrieval(
                    query: effectiveQuery,
                    candidates: contextCandidates,
                    answerIntentIsExtractive: answerIntentIsExtractive,
                    targetCount: effectiveTopK
                )

                if shouldAttemptCorrective {
                    let correctiveStartTime = Date()
                    let preCorrectiveLexical = checkLexicalRelevance(
                        query: effectiveQuery,
                        chunks: Array(contextCandidates.prefix(5))
                    )
                    let preCorrectiveTopSim = contextCandidates.first?.similarityScore ?? 0
                    let hadStructuredEvidence = contextCandidates.prefix(5).contains { candidate in
                        looksTableLike(
                            text: candidate.chunk.parentContent ?? candidate.chunk.content,
                            structureType: candidate.chunk.metadata.structureType
                        )
                    }

                    let correctiveCandidates = await performCorrectiveRetrieval(
                        query: effectiveQuery,
                        containerId: selectedId,
                        allChunks: cachedAllChunks,
                        existingCandidates: contextCandidates,
                        answerIntent: answerIntent,
                        targetCount: max(effectiveTopK, 4)
                    )

                    if !correctiveCandidates.isEmpty {
                        let mergedCandidates = mergeUniqueChunks(contextCandidates, correctiveCandidates)
                        if mergedCandidates.count > contextCandidates.count {
                            let rerankLimit = min(max(effectiveTopK * 3, 10), mergedCandidates.count)
                            let correctiveRerankStart = Date()
                            let correctedCandidates: [RetrievedChunk]

                            if qualityModeUsesReRanking {
                                correctedCandidates = await engine.rerank(
                                    chunks: mergedCandidates,
                                    query: question,
                                    topK: rerankLimit
                                )
                                rerankTime += Date().timeIntervalSince(correctiveRerankStart)
                            } else {
                                correctedCandidates = Array(
                                    mergedCandidates
                                        .sorted { $0.similarityScore > $1.similarityScore }
                                        .prefix(rerankLimit)
                                )
                            }

                            let postCorrectiveLexical = checkLexicalRelevance(
                                query: effectiveQuery,
                                chunks: Array(correctedCandidates.prefix(5))
                            )
                            let postCorrectiveTopSim = correctedCandidates.first?.similarityScore ?? 0
                            let hasStructuredEvidence = correctedCandidates.prefix(5).contains { candidate in
                                looksTableLike(
                                    text: candidate.chunk.parentContent ?? candidate.chunk.content,
                                    structureType: candidate.chunk.metadata.structureType
                                )
                            }

                            let shouldAdoptCorrective =
                                postCorrectiveLexical > preCorrectiveLexical + 0.08
                                || postCorrectiveTopSim > preCorrectiveTopSim + 0.04
                                || (answerIntentIsExtractive
                                    && postCorrectiveLexical >= preCorrectiveLexical
                                    && hasStructuredEvidence
                                    && !hadStructuredEvidence)
                                || (answerIntentIsExtractive
                                    && preCorrectiveLexical < 0.55
                                    && postCorrectiveLexical >= preCorrectiveLexical)

                            if shouldAdoptCorrective {
                                contextCandidates = correctedCandidates
                                contextStrategy = "corrective_fts"
                                auditUsedCorrectiveRetrieval = true

                                let correctiveTime = Date().timeIntervalSince(correctiveStartTime)
                                retrievalTime += correctiveTime
                                recoveryRetrievalTime = retrievalTime
                                let preLexicalPercent = String(format: "%.0f%%", preCorrectiveLexical * 100)
                                let postLexicalPercent = String(format: "%.0f%%", postCorrectiveLexical * 100)

                                Log.info(
                                    "[Corrective] Adopted lexical corrective retrieval: +\(correctiveCandidates.count) hits, lexical \(preLexicalPercent)->\(postLexicalPercent)",
                                    category: .retrieval
                                )
                                TelemetryCenter.emit(
                                    .retrieval,
                                    title: "Corrective retrieval",
                                    metadata: [
                                        "added": "\(correctiveCandidates.count)",
                                        "preLexical": String(format: "%.2f", preCorrectiveLexical),
                                        "postLexical": String(format: "%.2f", postCorrectiveLexical),
                                        "preTop": String(format: "%.2f", preCorrectiveTopSim),
                                        "postTop": String(format: "%.2f", postCorrectiveTopSim),
                                    ],
                                    duration: correctiveTime
                                )
                                emitThinkingEvent(
                                    .retrieval,
                                    title: "Corrective retrieval",
                                    detail: "+\(correctiveCandidates.count) lexical/page hits"
                                )

                                if Log.pipelineTraceEnabled {
                                    logChunkTrace(contextCandidates, stage: "Post-CorrectiveRetrieval", query: question)
                                }
                            } else {
                                let preLexicalPercent = String(format: "%.0f%%", preCorrectiveLexical * 100)
                                let postLexicalPercent = String(format: "%.0f%%", postCorrectiveLexical * 100)
                                Log.info(
                                    "[Corrective] Rejected corrective retrieval: lexical \(preLexicalPercent)->\(postLexicalPercent)",
                                    category: .retrieval
                                )
                            }
                        }
                    }
                }

                // Step 5: Construct context from retrieved chunks (off-main)
                // Note: rawContext assembly is handled via engine.assembleContext with size limits
                HardwareTelemetryState.shared.reportRAGPipeline(stage: "Context Assembly")

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

                // CRITICAL OPTIMIZATION: Disable tools when the RAG pipeline has already
                // retrieved and assembled context. Tool schemas eat ~1000 tokens (24% of
                // the 4096 window). When context is pre-assembled, the LLM prompt already
                // says "don't use tools" — so we're burning 1000 tokens on dead weight.
                // Reclaiming these tokens means MORE document context = BETTER answers.
                // Tools are only needed for agentic/conversational mode (no pre-assembled context).
                if !inferenceConfig.disableTools && contextCandidates.count > 0 {
                    inferenceConfig.disableTools = true
                    Log.info("[RAG] Auto-disabled tools: context pre-assembled (\(contextCandidates.count) chunks). Reclaimed ~1000 tokens for context.", category: .pipeline)
                }

                // Apple FM tokenizer ratio: empirically ~1.4 chars/token (observed 3056 estimated → 5994 actual)
                // This is conservative — compound safety removed; single 12% haircut applied at end
                let conservativeCharsPerToken: Double = isAppleFMOnDevice ? 1.4 : 2.5

                func estimateTokensConservative(chars: Int) -> Int {
                    max(1, Int(ceil(Double(chars) / conservativeCharsPerToken)))
                }

                // CRITICAL: Apple FM (both on-device AND PCC) has a hard 4096 token limit.
                // PCC fails with "Context length of 4096 was exceeded" when input exceeds 4096 tokens.
                let baseWindowTokens: Int = {
                    if llmService is AppleFoundationLLMService {
                        return 4096
                    }
                    return inferenceConfig.contextLength ?? 4096
                }()

                // Only reserve tool schema tokens when tools are actually attached.
                // With auto-disable above, this is 0 for all RAG pipeline queries,
                // reclaiming ~1000 tokens (24% of window) for document context.
                let toolSchemaTokens: Int = {
                    if inferenceConfig.disableTools {
                        return 0  // No tools → no schema overhead
                    }
                    return isAppleFMOnDevice ? 1000 : 800
                }()

                let systemPromptTokens = estimateTokensConservative(chars: (inferenceConfig.systemPrompt ?? "").count)
                let promptOverheadTokens = 120 + systemPromptTokens + toolSchemaTokens
                let questionTokens = estimateTokensConservative(chars: question.count)

                // Transcript tokens NO LONGER deducted from context budget.
                // Context gets FULL priority — document chunks are the most important input.
                // Instead, LLMService.generate() auto-trims the transcript to fit whatever
                // space remains after context + prompt + overhead. This means:
                //   - Short conversations: full transcript preserved
                //   - Long conversations: oldest turns trimmed, context never starved
                // This eliminates the failure mode where transcript > window → 0 context.
                let rawTranscriptTokens: Int
                if let appleFMService = llmService as? AppleFoundationLLMService {
                    rawTranscriptTokens = appleFMService.estimatedTranscriptTokens
                } else {
                    rawTranscriptTokens = 0
                }
                if rawTranscriptTokens > 0 {
                    Log.debug("[RAG] Transcript history: ~\(rawTranscriptTokens) tokens (auto-trimmed by LLM service, not deducted from context)", category: .pipeline)
                }

                // Reserve room for output
                let reservedOutputTokens = max(150, min(inferenceConfig.maxTokens, 300))

                // OPTIMIZED: Single 12% safety margin replaces compound (15% × factor + 400 flat).
                // Previous: rawAvailable × 0.85 - 400 → effective ~28% waste
                // Now:      rawAvailable × 0.88       → 12% safety, reclaims ~650 tokens
                let rawAvailableTokens = baseWindowTokens - promptOverheadTokens - questionTokens - reservedOutputTokens
                let globalSafetyFactor: Double = isAppleFMOnDevice ? 0.88 : 0.90
                let availableForContextTokens = max(
                    0,
                    Int(Double(rawAvailableTokens) * globalSafetyFactor)
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

                Log.debug("Context budget: base=\(baseWindowTokens), question=\(questionTokens), transcript=\(rawTranscriptTokens)(not deducted), available=\(availableForContextTokens) tokens → \(maxContextChars) chars, compact=\(useCompactMode)", category: .pipeline)

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
                } else if answerIntentIsExtractive {
                    // For lookup/table queries, prioritize chunks containing specifications
                    // that MATCH the query topic — not just any specs
                    let queryKeywords = extractQueryTerms(question)

                    // CORPUS-AWARE KEYWORD DISCOUNTING:
                    // Keywords that appear in >40% of candidates are corpus-generic and should
                    // NOT get bonus weight.  e.g. "car" in a car manual matches everything,
                    // diluting the signal from discriminative keywords like "oil".
                    // This is the same principle as IDF in BM25 — universal, domain-agnostic.
                    let candidateCount = max(1, contextCandidates.count)
                    let keywordDocFreq: [String: Int] = {
                        var freq: [String: Int] = [:]
                        for kw in queryKeywords {
                            var count = 0
                            for c in contextCandidates {
                                let text = (c.chunk.parentContent ?? c.chunk.content).lowercased()
                                if text.contains(kw) { count += 1 }
                            }
                            freq[kw] = count
                        }
                        return freq
                    }()
                    let discriminativeKeywords = queryKeywords.filter { kw in
                        let df = keywordDocFreq[kw] ?? 0
                        return Double(df) / Double(candidateCount) <= 0.40
                    }
                    let discardedKeywords = queryKeywords.filter { !discriminativeKeywords.contains($0) }
                    if !discardedKeywords.isEmpty {
                        Log.info("[RAG] Corpus-aware: discounted generic keywords \(discardedKeywords) (>40% of chunks)", category: .retrieval)
                    }

                    orderedCandidates = contextCandidates.sorted(by: { (a: RetrievedChunk, b: RetrievedChunk) -> Bool in
                        let aContent = a.chunk.parentContent ?? a.chunk.content
                        let bContent = b.chunk.parentContent ?? b.chunk.content
                        let aPriority = EvidenceScoringPolicyService.extractivePriorityScore(
                            content: aContent,
                            queryKeywords: discriminativeKeywords,
                            structureType: a.chunk.metadata.structureType
                        )
                        let bPriority = EvidenceScoringPolicyService.extractivePriorityScore(
                            content: bContent,
                            queryKeywords: discriminativeKeywords,
                            structureType: b.chunk.metadata.structureType
                        )

                        // If one has clear advantage, prioritize it
                        if abs(aPriority - bPriority) >= 2 {
                            return aPriority > bPriority
                        }
                        // Otherwise, maintain relevance order
                        return a.similarityScore > b.similarityScore
                    })
                    Log.info("[RAG] Extractive query - prioritizing specs (discriminative: [\(discriminativeKeywords.joined(separator: ", "))])", category: .retrieval)
                } else {
                    orderedCandidates = contextCandidates
                }

                // For procedural queries, disable "Lost in Middle" reordering to preserve sequence
                let useLostInMiddleMitigation = !isProceduralQuery

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SENTENCE-LEVEL EXTRACTION (lookup intent only)
                // Instead of packing 3 whole chunks into 4475 chars, extract
                // only query-relevant sentences from ALL candidates.
                // This fits targeted data from 10-15+ chunks vs 3 whole ones —
                // the difference between finding "Engine oil: 5.1 qt" and missing it.
                // Universal across all domains: medical, legal, automotive, etc.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let context: String
                let actualChunksUsed: Int

                if answerIntentIsExtractive && !isProceduralQuery {
                    let extractionResult = await extractRelevantSentences(
                        from: orderedCandidates,
                        query: question,
                        maxChars: maxContextChars,
                        compact: useCompactMode,
                        isExtractiveFirst: answerIntentIsExtractive
                    )
                    context = extractionResult.context
                    actualChunksUsed = extractionResult.sourcesUsed
                    Log.info("[RAG] Sentence extraction: \(extractionResult.sentencesIncluded) sentences from \(extractionResult.sourcesUsed) sources (\(context.count) chars)", category: .retrieval)
                } else {
                    let assembled = await engine.assembleContext(
                        chunks: orderedCandidates,
                        maxChars: maxContextChars,
                        compact: useCompactMode,
                        useLostInMiddleMitigation: useLostInMiddleMitigation
                    )
                    var assembledContext = assembled.context
                    actualChunksUsed = assembled.used

                    // UNIVERSAL FIX 10: Needle rescue from dropped chunks.
                    // When assembleContext runs out of budget, chunks at positions 4+ are dropped
                    // entirely. But a keyword-matching needle sentence in chunk #7 is now invisible
                    // to the LLM. Fix: run sentence extraction on the DROPPED chunks only,
                    // appending high-value sentences into any remaining budget.
                    // This catches needles across ALL intents (summarize, procedure, compare, etc.)
                    // without replacing whole-chunk packing for the primary chunks.
                    let droppedChunks = Array(orderedCandidates.dropFirst(assembled.used))
                    let remainingBudget = maxContextChars - assembledContext.count
                    let rescueBudgetFloor = (answerIntentIsExtractive || isPrecisionValueQuery(question)) ? 80 : 160

                    if !droppedChunks.isEmpty && remainingBudget > rescueBudgetFloor {
                        let rescueResult = await extractRelevantSentences(
                            from: droppedChunks,
                            query: question,
                            maxChars: remainingBudget,
                            compact: true,  // Always compact for rescue sentences to maximize density
                            isExtractiveFirst: answerIntentIsExtractive
                        )
                        if rescueResult.sentencesIncluded > 0 {
                            assembledContext += "\n---\n" + rescueResult.context
                            Log.info("[RAG] Needle rescue: +\(rescueResult.sentencesIncluded) sentences from \(rescueResult.sourcesUsed) dropped chunks (\(rescueResult.context.count) chars)", category: .retrieval)
                        }
                    }

                    context = assembledContext
                }

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
                // BUGFIX: Use orderedCandidates (post-sort) not contextCandidates (pre-sort).
                // Previously, spec prioritization sorted candidates but the slicing used the
                // original unsorted array, so fuse-box tables could be selected over oil specs.
                let includedRetrievedChunks = Array(orderedCandidates.prefix(actualChunksUsed))
                let precisionLookupCandidates = buildPrecisionLookupCandidates(
                    included: includedRetrievedChunks,
                    ordered: orderedCandidates,
                    desiredCount: max(actualChunksUsed + 6, 16)
                )
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
                    safetyTokens: 0,  // Unified into globalSafetyFactor (no separate flat buffer)
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
                    modelName: llmService.modelName,
                    featureFlags: RAGAuditFeatureFlags(
                        answerIntent: auditAnswerIntent,
                        queryWasRewritten: auditQueryWasRewritten,
                        queryExpansionCount: auditQueryExpansionCount,
                        usedHyDE: auditUsedHyDE,
                        usedIterativeRetrieval: auditUsedIterativeRetrieval,
                        iterativePassCount: auditIterativePassCount,
                        usedQueryRouting: auditUsedQueryRouting,
                        usedSummaryRouting: auditUsedSummaryRouting,
                        usedParentDocumentRetrieval: auditUsedParentDocumentRetrieval,
                        usedCorrectiveRetrieval: auditUsedCorrectiveRetrieval,
                        usedContextualCompression: auditUsedContextualCompression,
                        usedGraphPacking: auditUsedGraphPacking,
                        usedRetrievalCascade: usedRetrievalCascade,
                        usedSupplementaryVectorSearch: auditUsedSupplementaryVectorSearch,
                        usedFullUnlimitedReasoning: false
                    )
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
                        qualityWarnings: ["Relevance gate failed: retrieved content doesn't match query"],
                        structuredAnswer: StructuredAnswer.refusal(
                            reason: "I couldn't find relevant information about this topic in your documents. The retrieved content was about different subjects.",
                            missing: ["No relevant information matched the query in the selected library."],
                            topScore: bestSimilarity,
                            loops: 1
                        )
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
                let topicalMismatch = lexicalRelevance < 0.20
                let evidenceIsWeak = bestRetrievalSim < 0.25 || preGenConfidence < 0.70 || avgTop5BelowThreshold || topicalMismatch
                let useEvidenceFirstMode = evidenceIsWeak && (isProceduralQuery || topicalMismatch)

                if useEvidenceFirstMode {
                    let triggerReason: String
                    if topicalMismatch {
                        triggerReason = "topical mismatch (lexical relevance \(String(format: "%.0f%%", lexicalRelevance * 100)) < 20%)"
                    } else if avgTop5BelowThreshold {
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
                            generatedResponse: resolvedDisplayResponse(
                                fallback: summary.summaryText,
                                structuredAnswer: StructuredAnswer.from(
                                    response: summary.summaryText,
                                    retrievedChunks: includedRetrievedChunks,
                                    answerIntent: answerIntent,
                                    verificationResult: nil,
                                    loops: 1
                                )
                            ),
                            metadata: extractiveMetadata,
                            confidenceScore: summary.coverageScore,
                            qualityWarnings: [],
                            structuredAnswer: StructuredAnswer.from(
                                response: summary.summaryText,
                                retrievedChunks: includedRetrievedChunks,
                                answerIntent: answerIntent,
                                verificationResult: nil,
                                loops: 1
                            )
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
                // Step 5.10: Extractive QA disabled — always use LLM generation.
                // Heuristic extraction produced false positives (e.g., "three-quarters"
                // for "fuel tank capacity") and skipped LLM entirely. All queries now
                // proceed to LLM generation for reliable answers.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                if answerIntentIsExtractive || isPrecisionValueQuery(question),
                   let extractiveOverride = await highPrecisionLookupOverrideAnswer(
                       question: question,
                       answerIntent: answerIntent,
                       retrievedChunks: precisionLookupCandidates
                   ) {
                    Log.info("[ExtractiveQA] Returning direct source extraction before LLM generation", category: .retrieval)

                    var extractiveAnswer = extractiveOverride
                    var extractiveWarnings: [String] = []
                    var extractiveConfidence = max(precisionLookupCandidates.first?.similarityScore ?? 0.0, 0.85)
                    var gatingDecision = "extractive_override_pre_generation"
                    var structuredAnswer = StructuredAnswer.from(
                        response: extractiveOverride,
                        retrievedChunks: precisionLookupCandidates,
                        answerIntent: answerIntent,
                        verificationResult: nil,
                        loops: 1
                    )

#if canImport(FoundationModels)
                    if #available(iOS 26.0, *),
                       let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                           query: question,
                           candidateAnswer: extractiveOverride,
                           retrievedChunks: precisionLookupCandidates,
                           answerIntent: answerIntent,
                           verificationResult: nil,
                           isSourceLocked: true
                       )
                    {
                        extractiveAnswer = sourceOnlyOutcome.finalAnswer
                        structuredAnswer = sourceOnlyOutcome.structuredAnswer
                        gatingDecision = appendedGatingDecision(
                            gatingDecision,
                            sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                        )
                        extractiveWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                        if sourceOnlyOutcome.shouldAbstain,
                           let abstentionReason = sourceOnlyOutcome.abstentionReason
                        {
                            extractiveWarnings.append(abstentionReason)
                        }
                        extractiveConfidence = sourceOnlyOutcome.shouldAbstain
                            ? min(extractiveConfidence, 0.35)
                            : min(extractiveConfidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
                    }
#endif

                    let extractiveMetadata = ResponseMetadata(
                        timeToFirstToken: nil,
                        totalGenerationTime: 0,
                        tokensGenerated: 0,
                        tokensPerSecond: nil,
                        modelUsed: "Direct Source Extraction",
                        retrievalTime: retrievalTime,
                        retrievalConfigSummary: retrievalConfig.summary,
                        gatingDecision: gatingDecision,
                        toolCallsMade: nil,
                        embeddingProvider: embeddingProviderId,
                        usedAgenticMode: false,
                        qualityModeName: qualityModeDisplayName,
                        originalQuery: question,
                        reasoningTrace: nil
                    )
                    let extractiveResponse = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: precisionLookupCandidates,
                        generatedResponse: resolvedDisplayResponse(
                            fallback: extractiveAnswer,
                            structuredAnswer: structuredAnswer
                        ),
                        metadata: extractiveMetadata,
                        confidenceScore: extractiveConfidence,
                        qualityWarnings: extractiveWarnings,
                        structuredAnswer: structuredAnswer
                    )

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: extractiveResponse
                    )
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

                // ═══════════════════════════════════════════════════════════════
                // Context Homogeneity Detection
                // ═══════════════════════════════════════════════════════════════
                // If retrieved chunks are >55% similar to each other (Jaccard),
                // the source content is repetitive (e.g., inspection reports with
                // repeated dates/entries). Inject synthesis-focused instructions
                // into the system prompt to prevent the LLM from enumerating
                // each chunk separately (which causes repetition loops).
                let contextIsHomogeneous = detectContextHomogeneity(chunks: includedChunks)

                // Set explicit system prompt for RAG to ensure comprehensive, ACCURATE answers
                // Keep concise to maximize context budget (every 100 chars = ~70 tokens)

                // Customize system prompt based on answer intent (AppleRAG §3)
                // BUDGET-CONSCIOUS: Every 100 chars ≈ 70 tokens. Keep prompts tight.
                let lowerQuestion = question.lowercased()
                let isBehavioralOutcomeQuery =
                    lowerQuestion.contains("happens if")
                    || lowerQuestion.contains("happens when")
                    || lowerQuestion.contains("what does")
                    || lowerQuestion.contains("what do")
                    || lowerQuestion.contains("do when")

                let intentSpecificInstructions: String
                switch answerIntent {
                case .lookup, .tableLookup:
                    // Detect count/enumeration queries that slipped through to lookup
                    // (e.g., "how many quarts" — single-value with unit)
                    let isCountQuery = lowerQuestion.contains("how many") || lowerQuestion.contains("how much")
                    if isCountQuery {
                        intentSpecificInstructions = """
                        State the exact count FIRST, then list only the directly relevant items by name.
                        Keep each bullet brief. Copy names, labels, and values VERBATIM from the excerpts.
                        Count carefully — only include items explicitly mentioned in the excerpts. Never duplicate items. Never invent items not in the source.
                        Use only the minimum citations needed for the count sentence or for bullets that come from different sources.
                        """
                    } else if contextualDefinitionLookup {
                        intentSpecificInstructions = """
                        Define the subject directly in the first sentence.
                        Then explain the most relevant grounded context or significance from the excerpts.
                        Use concise prose, but allow 2-4 sentences when the excerpts support a fuller explanation.
                        Do not collapse a research concept into a nearby product, delivery form, or adjacent therapy unless the excerpts explicitly equate them.
                        If the excerpts distinguish the subject from similar items, state that distinction clearly.
                        Use the minimum citations needed — usually one citation cluster at the end of a sentence or short paragraph.
                        """
                    } else {
                        intentSpecificInstructions = """
                        Answer only the exact question being asked.
                        Start with the direct answer in the first sentence.
                        If the excerpts support additional details that materially answer the question, include them instead of collapsing everything into a one-line reply.
                        Use concise prose by default, but allow 2-4 sentences when needed for a complete grounded answer.
                        Keep it to one short paragraph unless bullets materially improve clarity.
                        Copy numbers, units, and codes VERBATIM.
                        Use the minimum citations needed — usually one citation cluster at the end of the sentence or paragraph. Do not repeat citations after every clause or restated fact.
                        Many excerpts say similar things in different words — combine them into one cohesive explanation. Never repeat the same fact twice.
                        If the question assumes a mapping or condition that the excerpts contradict, correct the premise explicitly using the exact source mapping instead of accepting the user's wording.
                        """
                    }
                case .procedure:
                    if isBehavioralOutcomeQuery {
                        intentSpecificInstructions = """
                        Answer with the direct outcome FIRST in 1-2 clear sentences. If excerpts include explicit steps, include only the relevant steps in source order.
                        Do NOT force a long numbered list when the question asks what happens.
                        """
                    } else {
                        intentSpecificInstructions = """
                        List relevant steps in source order. Number steps only when explicit ordered steps exist in the excerpts.
                        Include warnings and prerequisites when present in source text.
                        """
                    }
                case .compare:
                    intentSpecificInstructions = """
                    Compare the options found. Use a structured format. Copy exact product codes and specs from excerpts.
                    """
                case .summarize:
                    // Detect enumeration queries routed here ("how many X are available")
                    let isSummarizeEnumeration = lowerQuestion.contains("how many")
                    if isSummarizeEnumeration {
                        intentSpecificInstructions = """
                        The user asked for a COUNT and LIST. Follow these rules STRICTLY:
                        1. Count ONLY items explicitly named in the excerpts below.
                        2. List EVERY distinct item by name using bullets — copy names VERBATIM.
                        3. Include a brief description for each item when available.
                        4. State the count as "There are N [items]" where N is YOUR count of the bullets below it.
                        5. If the excerpts don't contain a complete list, say "The excerpts mention N of the following" — NEVER guess the total.
                        6. NEVER state a number larger than the items you actually list.
                        """
                    } else {
                        intentSpecificInstructions = """
                        Provide a comprehensive overview covering all major points. Organize by theme.
                        """
                    }
                case .investigate, .compute:
                    intentSpecificInstructions = """
                    Synthesize across sources. Show reasoning and connections. Copy specific values VERBATIM.
                    """
                case .findings:
                    intentSpecificInstructions = """
                    Summarize key findings, thesis, evidence, and methodology. Name researchers and contributions.
                    """
                }

                genConfig.systemPrompt = """
                Answer using document excerpts [S1], [S2], etc.
                \(intentSpecificInstructions)
                Rules: Cite sources [S1]/[S2] using the minimum citations needed to support the answer. Copy values VERBATIM. Answer exactly what was asked; be complete for the request, not exhaustive. If the excerpts do not address the user's question, say so clearly — briefly state what the excerpts cover and that the requested topic is not in the documents. Do NOT fabricate answers from unrelated context. If the question is vague, interpret it from document topics.
                CRITICAL: NEVER invent numbers, measurements, or values. Use ONLY values that appear in the excerpts. If a specific value is not in the excerpts, state that clearly.
                ABBREVIATIONS: If an [Abbreviations] glossary appears in the context, use those EXACT definitions when expanding abbreviations. Never expand an abbreviation differently than the glossary defines it. Example: if glossary says "ED = Emotional Dysregulation", NEVER write "oppositional defiant disorder (ED)".
                Format: Write naturally and match format to the question. Use ### headers only for multi-topic answers or explicit summaries. Use **bold** sparingly for key terms only. Use bullets only for actual lists, sequential steps, or specifications the user asked to enumerate. Write prose paragraphs for direct explanations and factual lookups. Combine overlapping excerpts into unified sentences — never repeat the same fact. For direct factual questions, prefer concise prose over sections or lists, but include all materially supported details. When multiple grounded facts are needed, use 2-4 sentences rather than a one-line reply.
                \(contextIsHomogeneous ? "IMPORTANT: The source excerpts contain highly repetitive or redundant entries. SYNTHESIZE across all excerpts into a SINGLE unified answer. Do NOT list or enumerate each excerpt separately. Mention each unique fact, date, or value ONCE. Combine similar entries." : "")
                """

                // Evidence-First mode: cautious prompt for low retrieval confidence
                if useEvidenceFirstMode {
                    genConfig.systemPrompt = """
                    EVIDENCE-FIRST MODE (low confidence retrieval). Use ONLY excerpts [S1], [S2], etc.
                    \(intentSpecificInstructions)
                    Rules: Cite only the minimum supporting sources needed for each grounded point. Copy values VERBATIM. Answer exactly what was asked. Do NOT fill gaps with assumptions. NEVER invent numbers.
                    ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT definitions. Never expand abbreviations differently.
                    For procedures: preserve exact order, never omit steps, include feedback indicators.
                    Format: Write naturally. Use ### headers only for multi-topic answers. Use **bold** sparingly for key terms only. Use bullets only for actual lists or sequential steps. Write prose paragraphs for explanations and direct factual answers. Merge overlapping excerpts into unified sentences. For direct factual questions, stay concise but include all materially supported details. Do not force a one-line answer when the evidence supports a fuller grounded explanation.
                    \(contextIsHomogeneous ? "IMPORTANT: Excerpts contain repetitive entries. SYNTHESIZE into ONE answer. Mention each fact ONCE." : "")
                    End with: What sources show → What's missing → Confidence note.
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
                    Int(Double(baseWindowTokens - promptOverheadTokens - questionTokens - contextTokens) * globalSafetyFactor)
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
                // REASONING CHAIN: Developer override only in Standard pipeline.
                // Deep Think/Maximum use the agentic path (returned early at L4022).
                // This code path is only reachable when forceReasoningChain is ON,
                // which lets developers test multi-session reasoning from Standard mode.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let forceChain = settingsStore?.forceReasoningChain ?? false
                let standardComplexity = initialQueryProfile.reasoningComplexity
                let useReasoningChain: Bool = {
                    // Only use for Apple Foundation Models (reasoning chain uses FM-specific features)
                    guard llmService is AppleFoundationLLMService else { return false }

                    // Standard stays single-pass unless a developer explicitly forces chaining.
                    guard forceChain else { return false }
                    guard qualityMode.canonical == .standard else { return false }

                    Log.info("[RAG] Reasoning chain FORCED via settings", category: .pipeline)

                    // Skip if evidence is weak (Evidence-First mode handles this)
                    guard !useEvidenceFirstMode else { return false }

                    // Skip trivial queries - they don't benefit from multi-session
                    guard !isTrivial else { return false }

                    guard standardComplexity.complexity != .simple else { return false }

                    // Need some retrieval quality
                    guard bestRetrievalSim >= 0.30 else { return false }

                    // Need some context to benefit from chaining
                    guard contextSize > 900 else { return false }

                    // Need enough evidence to distribute across sessions
                    guard includedRetrievedChunks.count >= 3 else { return false }

                    return true
                }()

                if useReasoningChain {
                    Log.info("[RAG] ✨ REASONING CHAIN ACTIVATED for Standard mode (developer override)", category: .pipeline)
                    Log.info("[RAG]   - bestRetrievalSim: \(bestRetrievalSim)", category: .pipeline)
                    Log.info("[RAG]   - contextSize: \(contextSize)", category: .pipeline)
                    Log.info("[RAG]   - chunks: \(includedRetrievedChunks.count)", category: .pipeline)
                    emitThinkingEvent(
                        .planning,
                        title: "🔗 Reasoning chain",
                        detail: "\(standardComplexity.complexity == .complex ? 4 : 3) sessions × 4K = expanded Standard reasoning"
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
                            sourceChunks: generationChunks,
                            allowStructuredRAG: true
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
                            sourceChunks: generationChunks,
                            allowStructuredRAG: true
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
                                sourceChunks: generationChunks,
                                allowStructuredRAG: true
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
                            retryConfig.systemPrompt = "Answer questions using ONLY the provided context. Be concise but complete. Cite sources as [S1], [S2] etc. Use **bold** sparingly for key terms. Use bullets only for actual lists."

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
                                sourceChunks: generationChunks,
                                allowStructuredRAG: true
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

                // Universal output integrity gate:
                // Detect malformed generation artifacts (placeholder lists, repetition loops,
                // dangling markdown) and attempt one grounded repair pass.
                var integrityIssues = responseIntegrityIssues(responseText)
                if !integrityIssues.isEmpty {
                    Log.warning(
                        "[RAG] Output integrity issues detected: \(integrityIssues.joined(separator: ", "))",
                        category: .llm
                    )
                    emitThinkingEvent(
                        .warning,
                        title: "Output integrity repair",
                        detail: "Detected malformed answer shape; repairing"
                    )

                    // Deterministic cleanup first (cheap, no extra model call)
                    var cleanedResponse = normalizeMalformedResponseArtifacts(responseText)
                    cleanedResponse = compactDegenerateResponse(
                        cleanedResponse,
                        question: question,
                        answerIntent: answerIntent
                    )
                    let cleanedIssues = responseIntegrityIssues(cleanedResponse)

                    // If still malformed, perform a grounded one-shot repair ONLY for non-repetition issues.
                    // Repetition loops are handled better by deterministic compaction than another model pass.
                    let shouldTryModelRepair = !cleanedIssues.isEmpty
                        && cleanedIssues.contains { $0 != "dominant_repetition" }

                    if shouldTryModelRepair {
                        var repairConfig = genConfig
                        repairConfig.temperature = min(repairConfig.temperature, 0.15)
                        repairConfig.skipContinuation = true
                        repairConfig.maxTokens = min(max(repairConfig.maxTokens, 192), 420)

                        let repairPrompt = buildIntegrityRepairPrompt(
                            question: question,
                            issueLabels: cleanedIssues,
                            answerIntent: answerIntent,
                            requiresCitations: requiresCitations
                        )

                        if let repaired = try? await generateWithFallback(
                            prompt: repairPrompt,
                            context: generationContext,
                            config: repairConfig,
                            sourceChunks: generationChunks
                        ) {
                            let candidate = compactDegenerateResponse(
                                normalizeMalformedResponseArtifacts(repaired.text),
                                question: question,
                                answerIntent: answerIntent
                            )
                            if isResponseIntegrityImproved(original: responseText, candidate: candidate) {
                                llmResponse = repaired
                                responseText = candidate
                                integrityIssues = responseIntegrityIssues(responseText)
                                Log.info("[RAG] Integrity repair succeeded", category: .llm)
                            } else {
                                Log.warning("[RAG] Integrity repair candidate rejected (no improvement)", category: .llm)
                                responseText = cleanedResponse
                                integrityIssues = cleanedIssues
                            }
                        } else {
                            responseText = cleanedResponse
                            integrityIssues = cleanedIssues
                        }
                    } else {
                        responseText = cleanedResponse
                        integrityIssues = cleanedIssues
                    }

                    // Hard stop: if repetition still remains, deterministically compact once more
                    // and accept that output rather than spinning another expensive model pass.
                    if integrityIssues.contains("dominant_repetition") {
                        let compacted = compactDegenerateResponse(
                            responseText,
                            question: question,
                            answerIntent: answerIntent
                        )
                        if isResponseIntegrityImproved(original: responseText, candidate: compacted) {
                            responseText = compacted
                            integrityIssues = responseIntegrityIssues(responseText)
                        }
                    }

                    if !integrityIssues.isEmpty {
                        Log.warning("[RAG] Residual integrity issues after repair: \(integrityIssues.joined(separator: ", "))", category: .llm)
                    }
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

                    // Verify we got a response — if empty, route to reliability fallback
                    // instead of throwing modelNotAvailable (which skips fallback entirely)
                    if responseText.isEmpty {
                        Log.warning("⚠️  LLM returned empty response (0 tokens) — routing to reliability fallback", category: .llm)
                        if !recoveryRetrievedChunks.isEmpty {
                            let emptyFallback = await buildReliabilityFallbackResponse(
                                question: question,
                                ragQuery: ragQuery ?? RAGQuery(query: question, topK: effectiveTopK),
                                inferenceConfig: inferenceConfig,
                                retrievalConfig: retrievalConfig,
                                embeddingProviderId: embeddingProviderId,
                                retrievedChunks: recoveryRetrievedChunks,
                                retrievalTime: recoveryRetrievalTime,
                                reason: "LLM returned empty response"
                            )
                            return await finalizeResponse(
                                query: question,
                                containerId: selectedId,
                                containerName: selectedName,
                                response: emptyFallback
                            )
                        }
                        throw RAGServiceError.modelNotAvailable
                    }

                    var sourceLockedFinalResponse = false
                    if (answerIntentIsExtractive || isPrecisionValueQuery(question)),
                       let extractiveOverride = await highPrecisionLookupOverrideAnswer(
                           question: question,
                           answerIntent: answerIntent,
                           retrievedChunks: generationRetrievedChunks
                       )
                    {
                        sourceLockedFinalResponse = true
                        let normalizedLLM = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedOverride = extractiveOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                        if normalizedLLM != normalizedOverride {
                            Log.info("[ExtractiveQA] Overriding lookup response with direct source extraction", category: .retrieval)
                            responseText = normalizedOverride
                        }
                    }

                    // Step 7: Calculate confidence score and quality warnings
                    Log.section("Step 7: Quality Assessment", level: .info, category: .pipeline)
                    HardwareTelemetryState.shared.reportRAGPipeline(stage: "Quality Assessment")

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
                    // Run Gates A-G to validate response against source evidence
                    // Respect quality mode toggle for verification
                    let runVerificationGates = qualityModeUsesVerificationGates

                    var verificationResult: RAGVerificationResult?
                    var verificationTime: TimeInterval = 0

                    if runVerificationGates {
                        Log.section("Step 7.5: Verification Gates", level: .info, category: .pipeline)

                        let confidencePolicy = ConfidencePolicyService.policy(
                            for: question,
                            answerIntent: answerIntent,
                            qualityMode: qualityMode
                        )
                        let verificationService = VerificationGateService(config: confidencePolicy.verificationConfig)

                        let verificationStartTime = Date()
                        // Use the TOP reranked scores from the pipeline (auditTopSim, auditSecondSim, etc.)
                        // NOT the scores from generationRetrievedChunks which may be sibling chunks with discounted scores
                        let topScores = [auditTopSim, auditSecondSim, auditAvgTop5].filter { $0 > 0 }

                        // SEMANTIC GROUNDING: Embed the LLM response to check if its meaning
                        // is actually grounded in source chunk embeddings. This is the primary
                        // hallucination detector — catches fabricated content that string-matching
                        // (number checks, keyword overlap) would miss.
                        let responseEmbedding: [Float]?
                        let responseForEmbedding = boundedVerificationResponseText(
                            responseText,
                            answerIntent: answerIntent
                        )
                        do {
                            responseEmbedding = try await queryEmbeddingService.generateEmbedding(for: responseForEmbedding)
                        } catch {
                            Log.warning("[RAG] Could not embed response for grounding check: \(error.localizedDescription)", category: .pipeline)
                            responseEmbedding = nil
                        }

                        // Fetch ACTUAL chunk embeddings from the vector database mmap file.
                        // BNNSVectorDatabase returns embedding: [] in search results to save memory,
                        // so Gate E must load them explicitly for cosine similarity grounding checks.
                        let chunkIDs = generationRetrievedChunks.map { $0.chunk.id }
                        let chunkEmbeddings = await vdb.getEmbeddings(forChunkIDs: chunkIDs)
                        let validChunkEmbeddings = chunkEmbeddings.filter { !$0.isEmpty }

                        if validChunkEmbeddings.isEmpty && responseEmbedding != nil {
                            Log.warning("[RAG] Gate E: No chunk embeddings loaded — vector DB may not support getEmbeddings. Gate E will be skipped.", category: .pipeline)
                        }

                        verificationResult = await verificationService.verify(
                            response: responseText,
                            query: question,
                            retrievedChunks: generationRetrievedChunks,
                            topScores: topScores,
                            allCandidateChunks: contextCandidates,
                            responseEmbedding: responseEmbedding,
                            queryEmbedding: queryEmbedding,
                            chunkEmbeddings: validChunkEmbeddings.isEmpty ? nil : chunkEmbeddings,
                            structuredClaims: llmResponse.structuredRAGGeneration?.claims
                        )
                        verificationTime = Date().timeIntervalSince(verificationStartTime)

                        if let vr = verificationResult {
                        Log.pipelineStep("7.5", title: "Verification Gates", details: [
                            ("passed", vr.passed ? "✓" : "✗"),
                            ("confidence", String(format: "%.2f", vr.overallConfidence)),
                            ("gates", vr.gateResults.map { "\($0.gate.rawValue):\($0.passed ? "✓" : "✗")" }.joined(separator: " "))
                        ])

                        // Emit verification thinking event
                        emitThinkingEvent(
                            .verification,
                            title: vr.passed ? "Gates passed ✓" : "Gates failed ✗",
                            detail: "Confidence: \(String(format: "%.0f", vr.overallConfidence * 100))%"
                        )

                        if !vr.passed {
                            Log.warning("⚠️ Verification gates failed - response may contain unsupported claims", category: .pipeline)
                            for gateResult in vr.gateResults where !gateResult.passed {
                                Log.warning("   • Gate \(gateResult.gate.rawValue): \(gateResult.details)", category: .pipeline)
                            }

                            let effectiveThreshold = confidencePolicy.verificationPassThreshold
                            if answerIntentIsExtractive {
                                Log.debug("[Verification] Extractive intent '\(answerIntent.rawValue)' - using relaxed threshold \(String(format: "%.0f", effectiveThreshold * 100))%", category: .pipeline)
                            }

                            // Check if confidence is below quality mode threshold (Maximum mode requires 98%)
                            let belowConfidenceThreshold = vr.overallConfidence < effectiveThreshold

                            // If grounded-only mode and verification fails, abstain
                            if !allowUngroundedFallback || belowConfidenceThreshold {
                                let thresholdDisplay = answerIntentIsExtractive
                                    ? "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))% (relaxed for extractive)"
                                    : "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))%"
                                let reason = belowConfidenceThreshold
                                    ? "confidence \(String(format: "%.0f", vr.overallConfidence * 100))% below \(thresholdDisplay)"
                                    : "grounded-only mode"
                                Log.info("🛑 Abstaining: \(reason)", category: .pipeline)
                                let abstainResponse = verificationService.generateAbstentionResponse(
                                    query: question,
                                    verificationResult: vr,
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
                                    gatingDecision: "verification_gates_failed:\(vr.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: ","))"
                                )
                                return await finalizeResponse(
                                    query: question,
                                    containerId: selectedId,
                                    containerName: selectedName,
                                    response: response
                                )
                            }
                        } else {
                            Log.info("✓ All verification gates passed (confidence: \(String(format: "%.0f", vr.overallConfidence * 100))%)", category: .pipeline)
                        }
                        } // end if let vr
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
                    let confidencePolicy = ConfidencePolicyService.policy(
                        for: question,
                        answerIntent: answerIntent,
                        qualityMode: qualityMode
                    )
                    let calibrationService = ConfidenceCalibrationService(
                        params: confidencePolicy.calibrationParameters,
                        abstentionThreshold: confidencePolicy.calibrationAbstentionThreshold,
                        touchyThreshold: confidencePolicy.calibrationTouchyThreshold
                    )
                    let calibratedConfidence = calibrationService.calibrate(
                        chunks: generationRetrievedChunks,
                        verification: verificationResult,
                        isTouchyQuery: confidencePolicy.isTouchyQuery
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

                    // Include verification warnings in quality warnings (only if gates were run)
                    var finalWarnings = qualityWarnings
                    if let vResult = verificationResult, !vResult.passed {
                        for gateResult in vResult.gateResults where !gateResult.passed {
                            finalWarnings.append("Verification \(gateResult.gate.rawValue): \(gateResult.details)")
                        }
                    }

                    // Generate structured answer for rich UI rendering (AppleRAG §6)
                    var finalResponseText = responseText
                    var finalConfidenceScore = confidenceScore
                    var structuredAnswer = StructuredAnswer.from(
                        response: responseText,
                        retrievedChunks: generationRetrievedChunks,
                        answerIntent: answerIntent,
                        verificationResult: verificationResult,
                        structuredGeneration: llmResponse.structuredRAGGeneration,
                        loops: reasoningTraceForMetadata?.count ?? 1
                    )

#if canImport(FoundationModels)
                    if #available(iOS 26.0, *),
                       (answerIntentIsExtractive || isPrecisionValueQuery(question)),
                       let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                           query: question,
                           candidateAnswer: responseText,
                           retrievedChunks: generationRetrievedChunks,
                           answerIntent: answerIntent,
                           verificationResult: verificationResult,
                           isSourceLocked: sourceLockedFinalResponse
                       )
                    {
                        finalResponseText = sourceOnlyOutcome.finalAnswer
                        structuredAnswer = sourceOnlyOutcome.structuredAnswer
                        gatingSummary = appendedGatingDecision(
                            gatingSummary,
                            sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                        )
                        finalWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                        if sourceOnlyOutcome.shouldAbstain,
                           let abstentionReason = sourceOnlyOutcome.abstentionReason
                        {
                            finalWarnings.append(abstentionReason)
                        }
                        finalConfidenceScore = sourceOnlyOutcome.shouldAbstain
                            ? min(confidenceScore, 0.35)
                            : min(confidenceScore, max(sourceOnlyOutcome.fidelityScore, 0.75))
                    }
#endif

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
                        qualityModeName: qualityMode.displayName,
                        originalQuery: question, // For "Go Deeper" re-query
                        reasoningTrace: reasoningTraceForMetadata // Chained session insights
                    )

                    let displayResponseText = resolvedDisplayResponse(
                        fallback: finalResponseText,
                        structuredAnswer: structuredAnswer
                    )

                    // Log structured answer summary
                    Log.debug(
                        "[StructuredAnswer] type=\(structuredAnswer.answerType.rawValue), claims=\(structuredAnswer.claims.count), evidence=\(structuredAnswer.evidence.count), gaps=\(structuredAnswer.missing.count)",
                        category: .pipeline
                    )

                    let response = RAGResponse(
                        queryId: ragQueryValue.id,
                        retrievedChunks: generationRetrievedChunks,
                        generatedResponse: displayResponseText,
                        metadata: metadata,
                        confidenceScore: finalConfidenceScore,
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
                    let recoveredText = llmResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let recoveredResponse = recoveredText.isEmpty ? "Error processing response" : recoveredText
                    let recoveredStructuredAnswer: StructuredAnswer
                    if recoveredText.isEmpty {
                        recoveredStructuredAnswer = StructuredAnswer.refusal(
                            reason: "Error processing response",
                            missing: ["The response could not be processed safely."],
                            topScore: generationRetrievedChunks.first?.similarityScore ?? 0,
                            loops: 1,
                            retrievedChunks: generationRetrievedChunks
                        )
                    } else {
                        recoveredStructuredAnswer = StructuredAnswer.from(
                            response: recoveredResponse,
                            retrievedChunks: generationRetrievedChunks,
                            answerIntent: answerIntent,
                            verificationResult: nil,
                            structuredGeneration: llmResponse.structuredRAGGeneration,
                            loops: reasoningTraceForMetadata?.count ?? 1
                        )
                    }

                    let recoveredDisplayText = resolvedDisplayResponse(
                        fallback: recoveredResponse,
                        structuredAnswer: recoveredStructuredAnswer
                    )

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
                        generatedResponse: recoveredDisplayText,
                        metadata: metadata,
                        confidenceScore: 0.0,
                        qualityWarnings: ["Response processing recovery: \(error.localizedDescription)"],
                        structuredAnswer: recoveredStructuredAnswer
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
                let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
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

                let structuredAnswer = StructuredAnswer.from(
                    response: llmResponse.text,
                    retrievedChunks: [],
                    answerIntent: answerIntent,
                    verificationResult: nil,
                    structuredGeneration: llmResponse.structuredRAGGeneration,
                    loops: 1
                )
                let response = RAGResponse(
                    queryId: ragQueryValue.id,
                    retrievedChunks: [], // No chunks in direct chat mode
                    generatedResponse: resolvedDisplayResponse(
                        fallback: llmResponse.text,
                        structuredAnswer: structuredAnswer
                    ),
                    metadata: metadata,
                    structuredAnswer: structuredAnswer
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

        let structuredAnswer = StructuredAnswer.refusal(
            reason: responseText,
            missing: [reason],
            topScore: retrievedChunks.first?.similarityScore ?? 0,
            loops: 1,
            retrievedChunks: retrievedChunks
        )

        return RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: retrievedChunks,
            generatedResponse: responseText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: ["Grounded-only: \(reason)"],
            structuredAnswer: structuredAnswer
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
        var warnings = ["Reliability fallback: \(reason)"]
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)

        if let extractiveOverride = await highPrecisionLookupOverrideAnswer(
            question: question,
            answerIntent: answerIntent,
            retrievedChunks: retrievedChunks
        ) {
            let structuredAnswer = StructuredAnswer.from(
                response: extractiveOverride,
                retrievedChunks: retrievedChunks,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1
            )
            return RAGResponse(
                queryId: ragQuery.id,
                retrievedChunks: retrievedChunks,
                generatedResponse: resolvedDisplayResponse(
                    fallback: extractiveOverride,
                    structuredAnswer: structuredAnswer
                ),
                metadata: ResponseMetadata(
                    timeToFirstToken: nil,
                    totalGenerationTime: 0,
                    tokensGenerated: 0,
                    tokensPerSecond: nil,
                    modelUsed: "Direct Source Extraction",
                    retrievalTime: retrievalTime,
                    retrievalConfigSummary: retrievalConfig.summary,
                    gatingDecision: "reliability_extractive_override",
                    toolCallsMade: 0,
                    embeddingProvider: embeddingProviderId
                ),
                confidenceScore: max(retrievedChunks.first?.similarityScore ?? 0.0, 0.85),
                qualityWarnings: warnings,
                structuredAnswer: structuredAnswer
            )
        }

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

        do {
            let llmResponse = try await generateWithFallback(
                prompt: fallbackPrompt,
                context: fallbackContext.isEmpty ? nil : fallbackContext,
                config: fallbackConfig,
                sourceChunks: sourceChunks
            )

            let topScores = usedRetrieved.map(\.similarityScore).filter { $0 > 0 }
            let verificationResult: RAGVerificationResult?
            if !usedRetrieved.isEmpty, !topScores.isEmpty {
                let fallbackQualityMode = await MainActor.run {
                    self.settingsStore?.ragQualityMode ?? .standard
                }
                let confidencePolicy = ConfidencePolicyService.policy(
                    for: question,
                    answerIntent: answerIntent,
                    qualityMode: fallbackQualityMode
                )
                let verificationService = VerificationGateService(config: confidencePolicy.verificationConfig)

                let preferredContainerId = await MainActor.run {
                    self.currentQueryContainerId ?? self.containerService.activeContainerId
                }
                let embeddingContext = await resolveEmbeddingContext(preferredContainerId: preferredContainerId)
                let verificationContainer = await containerForId(embeddingContext.containerId)

                let responseEmbedding: [Float]?
                let queryEmbedding: [Float]?
                let responseForEmbedding = boundedVerificationResponseText(
                    llmResponse.text,
                    answerIntent: answerIntent
                )
                let translatedResponseForEmbedding = await translatedQueryForEmbedding(
                    responseForEmbedding,
                    container: verificationContainer
                )
                let translatedQuestionForEmbedding = await translatedQueryForEmbedding(
                    question,
                    container: verificationContainer
                )

                do {
                    responseEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedResponseForEmbedding.text)
                } catch {
                    Log.warning("[RAG] Reliability fallback could not embed response for grounding check: \(error.localizedDescription)", category: .pipeline)
                    responseEmbedding = nil
                }

                do {
                    queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuestionForEmbedding.text)
                } catch {
                    Log.warning("[RAG] Reliability fallback could not embed query for grounding check: \(error.localizedDescription)", category: .pipeline)
                    queryEmbedding = nil
                }

                let fallbackDB = await dbFor(embeddingContext.containerId)
                let chunkIDs = usedRetrieved.map { $0.chunk.id }
                let chunkEmbeddings = await fallbackDB.getEmbeddings(forChunkIDs: chunkIDs)
                let validChunkEmbeddings = chunkEmbeddings.filter { !$0.isEmpty }

                if validChunkEmbeddings.isEmpty && responseEmbedding != nil {
                    Log.warning("[RAG] Reliability fallback grounding skipped: no chunk embeddings loaded for fallback evidence", category: .pipeline)
                }

                verificationResult = await verificationService.verify(
                    response: llmResponse.text,
                    query: question,
                    retrievedChunks: usedRetrieved,
                    topScores: topScores,
                    allCandidateChunks: retrievedChunks,
                    responseEmbedding: responseEmbedding,
                    queryEmbedding: queryEmbedding,
                    chunkEmbeddings: validChunkEmbeddings.isEmpty ? nil : chunkEmbeddings,
                    structuredClaims: llmResponse.structuredRAGGeneration?.claims
                )
            } else {
                verificationResult = nil
            }

            if let verificationResult, !verificationResult.passed {
                for gateResult in verificationResult.gateResults where !gateResult.passed {
                    warnings.append("Reliability fallback verification \(gateResult.gate.rawValue): \(gateResult.details)")
                }
            }

            let rejectingGates: Set<VerificationGate> = [
                .retrievalConfidence,
                .evidenceCoverage,
                .numericSanity,
                .semanticGrounding,
                .quoteFaithfulness,
            ]
            let shouldUseExtractiveFallback = verificationResult?.failedGates.contains {
                rejectingGates.contains($0)
            } ?? false

            if shouldUseExtractiveFallback {
                warnings.append("Best-effort synthesis failed verification; showing excerpts instead.")
                Log.warning("[RAG] Reliability fallback answer failed verification — using extractive fallback", category: .pipeline)
            } else {
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
            let structuredAnswer = StructuredAnswer.from(
                response: llmResponse.text,
                retrievedChunks: usedRetrieved,
                answerIntent: answerIntent,
                verificationResult: verificationResult,
                structuredGeneration: llmResponse.structuredRAGGeneration,
                loops: 1
            )
            return RAGResponse(
                queryId: ragQuery.id,
                retrievedChunks: usedRetrieved,
                generatedResponse: resolvedDisplayResponse(
                    fallback: llmResponse.text,
                    structuredAnswer: structuredAnswer
                ),
                metadata: metadata,
                confidenceScore: verificationResult?.overallConfidence ?? 0.0,
                qualityWarnings: warnings,
                structuredAnswer: structuredAnswer
            )
            }
        } catch {
            Log.error("[RAG] Reliability fallback LLM also failed: \(error.localizedDescription) — falling through to extractive Path B", category: .pipeline)
        }

        let terms = extractQueryTerms(question)
        let snippetBullets = usedRetrieved.prefix(6).enumerated().map { idx, retrieved in
            let sectionLabel = retrieved.chunk.metadata.sectionTitle.flatMap { $0.isEmpty ? nil : "**\($0)**: " } ?? ""
            let sourceName = retrieved.sourceDocument.isEmpty ? "Document" : retrieved.sourceDocument
            let snippet = extractSnippet(
                from: retrieved.chunk.content,
                queryTerms: terms,
                maxChars: 500
            )
            return "• \(sectionLabel)\(snippet) [S\(idx + 1): \(sourceName)]"
        }
        let responseText: String
        if snippetBullets.isEmpty {
            responseText = "I can't reach the model right now, but your documents are still available. Please try again in a moment."
        } else {
            responseText = """
            I wasn’t able to synthesize a full answer right now. Here are the most relevant excerpts from your documents:

            \(snippetBullets.joined(separator: "\n\n"))

            Try asking again — the model may be temporarily rate-limited.
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
            qualityWarnings: warnings + ["Extractive fallback"],
            structuredAnswer: StructuredAnswer.from(
                response: responseText,
                retrievedChunks: usedRetrieved,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1
            )
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
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
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

        let structuredAnswer = StructuredAnswer.from(
            response: llmResponse.text,
            retrievedChunks: [],
            answerIntent: answerIntent,
            verificationResult: nil,
            structuredGeneration: llmResponse.structuredRAGGeneration,
            loops: 1
        )
        let response = RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: [],
            generatedResponse: resolvedDisplayResponse(
                fallback: llmResponse.text,
                structuredAnswer: structuredAnswer
            ),
            metadata: metadata,
            confidenceScore: 1.0,
            qualityWarnings: warnings,
            structuredAnswer: structuredAnswer
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
    /// Matches lines that consist ONLY of a number + period (empty numbered list items).
    /// Uses multiline mode ((?m)) so ^ and $ anchor to line boundaries.
    /// Previous pattern `\b\d+\.\s*(\.)?(?=\s|$)` falsely matched decimal numbers
    /// at sentence boundaries in health/numeric data (e.g. "avg 71.6" → "71." matched),
    /// triggering unnecessary integrity repair cycles (+3-4s per query).
    private static let emptyListItemRegex = try? NSRegularExpression(pattern: #"(?m)^\s*\d+\.\s*\.?\s*$"#)
    private static let malformedInlineListRunRegex = try? NSRegularExpression(pattern: #"(?:\b\d+\.\s*\.\s*){2,}"#)
    private static let danglingMarkdownRegex = try? NSRegularExpression(pattern: #"\*\*[A-Za-z][A-Za-z\s]{0,30}$"#)

    private func responseHasCitations(_ text: String) -> Bool {
        guard let regex = Self.citationRegex else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Context Homogeneity Detection
    // ═══════════════════════════════════════════════════════════════════════
    /// Detects whether retrieved chunks are highly repetitive/homogeneous.
    /// Uses pairwise Jaccard word similarity with O(n) sampling for large sets.
    /// Returns `true` if chunks are homogeneous (>55% avg similarity) —
    /// triggers synthesis-focused system prompt to prevent LLM enumeration loops.
    ///
    /// Theory: Inspection reports, repeated forms, and log files produce near-
    /// identical chunks (same dates, headers, boilerplate). If the LLM sees
    /// 8 chunks all saying "02/23/2024 inspection passed", it enumerates them
    /// 8 times. Detecting this BEFORE generation lets us inject a synthesis
    /// directive: "mention each fact ONCE."
    private nonisolated func detectContextHomogeneity(chunks: [DocumentChunk]) -> Bool {
        guard chunks.count >= 3 else { return false }

        // Build word sets for each chunk (lowercased, alpha-only, min 3 chars)
        let wordSets: [Set<String>] = chunks.map { chunk in
            Set(
                chunk.content.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 3 }
            )
        }

        // Pairwise Jaccard similarity with sampling for large chunk sets.
        // Full pairwise is O(n²) — for >10 chunks, sample up to 30 random pairs.
        var totalSimilarity: Double = 0
        var pairCount = 0
        var highPairCount = 0  // pairs with >0.60 similarity

        let n = wordSets.count
        if n <= 10 {
            // Full pairwise comparison
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let intersection = wordSets[i].intersection(wordSets[j]).count
                    let union = wordSets[i].union(wordSets[j]).count
                    guard union > 0 else { continue }
                    let jaccard = Double(intersection) / Double(union)
                    totalSimilarity += jaccard
                    pairCount += 1
                    if jaccard > 0.60 { highPairCount += 1 }
                }
            }
        } else {
            // Sampled comparison: sequential neighbors + random pairs
            // (1) Adjacent pairs (capture local repetition)
            for i in 0..<(n - 1) {
                let intersection = wordSets[i].intersection(wordSets[i + 1]).count
                let union = wordSets[i].union(wordSets[i + 1]).count
                guard union > 0 else { continue }
                let jaccard = Double(intersection) / Double(union)
                totalSimilarity += jaccard
                pairCount += 1
                if jaccard > 0.60 { highPairCount += 1 }
            }
            // (2) Strided pairs for coverage across distant chunks
            let step = max(2, n / 6)
            for i in Swift.stride(from: 0, to: n - step, by: step) {
                let j = i + step
                let intersection = wordSets[i].intersection(wordSets[j]).count
                let union = wordSets[i].union(wordSets[j]).count
                guard union > 0 else { continue }
                let jaccard = Double(intersection) / Double(union)
                totalSimilarity += jaccard
                pairCount += 1
                if jaccard > 0.60 { highPairCount += 1 }
            }
        }

        guard pairCount > 0 else { return false }

        let avgSimilarity = totalSimilarity / Double(pairCount)

        // Dual threshold: average >0.55 OR >50% of pairs are highly similar
        let isHomogeneous = avgSimilarity > 0.55 || Double(highPairCount) / Double(pairCount) > 0.50

        if isHomogeneous {
            Log.info("[RAG] Context homogeneity detected: avg Jaccard=\(String(format: "%.2f", avgSimilarity)), high pairs=\(highPairCount)/\(pairCount) — injecting synthesis prompt", category: .retrieval)
        }

        return isHomogeneous
    }

    private func responseIntegrityIssues(_ text: String) -> [String] {
        var issues: [String] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)

        if let regex = Self.emptyListItemRegex {
            let matches = regex.matches(in: text, options: [], range: range)
            if matches.count >= 3 {
                issues.append("empty_numbered_items")
            }
        }

        if let regex = Self.malformedInlineListRunRegex,
           regex.firstMatch(in: text, options: [], range: range) != nil
        {
            issues.append("inline_placeholder_list")
        }

        if let regex = Self.danglingMarkdownRegex,
           regex.firstMatch(in: text, options: [], range: range) != nil
        {
            issues.append("dangling_markdown")
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 1: Sentence-level repetition dominance detector
        // ═══════════════════════════════════════════════════════════════
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 20 }

        if sentences.count >= 4 {
            var counts: [String: Int] = [:]
            for sentence in sentences {
                let key = sentence
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                    .split(separator: " ")
                    .joined(separator: " ")
                counts[key, default: 0] += 1
            }
            if let dominant = counts.values.max(), Double(dominant) / Double(sentences.count) >= 0.45, dominant >= 3 {
                issues.append("dominant_repetition")
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 2: Intra-sentence / phrase-level repetition detector
        // ═══════════════════════════════════════════════════════════════
        // Catches "02/23/2024, 02/23/2024, 02/23/2024..." within a single bullet
        let commaSegments = text.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 4 && $0.count <= 40 }
        if commaSegments.count >= 6 {
            var segFreq: [String: Int] = [:]
            for seg in commaSegments {
                let key = seg.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard !key.isEmpty else { continue }
                segFreq[key, default: 0] += 1
            }
            if let topCount = segFreq.values.max(),
               topCount >= 4,
               Double(topCount) / Double(commaSegments.count) >= 0.35 {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 3: N-gram entropy — information-theoretic quality gate
        // ═══════════════════════════════════════════════════════════════
        // Calculates Shannon entropy of word bigrams. Low entropy = degenerate
        // repetition regardless of surface pattern. This catches ALL forms of
        // repetition universally — including patterns we haven't hard-coded for.
        //
        // Theory: English prose has bigram entropy ~4-6 bits.
        // Repetitive text drops <2.0 bits. Threshold: 2.0 bits.
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if words.count >= 30 {
            var bigramCounts: [String: Int] = [:]
            var totalBigrams = 0
            for i in 0..<(words.count - 1) {
                let bigram = "\(words[i]) \(words[i + 1])"
                bigramCounts[bigram, default: 0] += 1
                totalBigrams += 1
            }

            if totalBigrams > 0 {
                var entropy: Double = 0.0
                let total = Double(totalBigrams)
                for (_, count) in bigramCounts {
                    let p = Double(count) / total
                    if p > 0 {
                        entropy -= p * log2(p)
                    }
                }

                // Very short responses naturally have lower entropy, scale threshold
                let entropyThreshold: Double = words.count < 60 ? 1.5 : 2.0

                if entropy < entropyThreshold {
                    if !issues.contains("dominant_repetition") {
                        issues.append("dominant_repetition")
                    }
                    issues.append("low_entropy")
                    Log.debug("[IntegrityCheck] Low bigram entropy: \(String(format: "%.2f", entropy)) bits (threshold: \(entropyThreshold))", category: .llm)
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 4: Unique word ratio — redundancy proxy
        // ═══════════════════════════════════════════════════════════════
        // High-quality prose has ~40-70% unique words. Repetitive text drops <25%.
        // This is a compression-ratio proxy: if gzip would compress 4:1, it's junk.
        if words.count >= 20 {
            let uniqueWords = Set(words)
            let uniqueRatio = Double(uniqueWords.count) / Double(words.count)
            if uniqueRatio < 0.20 {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
                issues.append("low_lexical_diversity")
                Log.debug("[IntegrityCheck] Low unique word ratio: \(String(format: "%.1f%%", uniqueRatio * 100)) (\(uniqueWords.count)/\(words.count))", category: .llm)
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 5: Sliding window substring repetition
        // ═══════════════════════════════════════════════════════════════
        // Catches non-delimited repetition: "the datadata datadata" etc.
        // Uses a sliding window of 3-word sequences.
        if words.count >= 20 {
            var trigramCounts: [String: Int] = [:]
            for i in 0..<(words.count - 2) {
                let trigram = "\(words[i]) \(words[i + 1]) \(words[i + 2])"
                trigramCounts[trigram, default: 0] += 1
            }
            let totalTrigrams = words.count - 2
            if let topTrigram = trigramCounts.values.max(),
               topTrigram >= 5,
               Double(topTrigram) / Double(totalTrigrams) > 0.20 {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
            }
        }

        return issues
    }

    private func normalizeMalformedResponseArtifacts(_ text: String) -> String {
        var output = text

        // Collapse intra-sentence phrase repetition FIRST (before sentence-level dedup)
        // This handles "02/23/2024, 02/23/2024, 02/23/2024..." within a single bullet
        output = collapseIntraLineRepetition(output)

        // Remove standalone empty numbered lines such as "2." or "2. ."
        let lines = output.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            return trimmed.range(of: #"^\d+\.\s*(\.)?$"#, options: .regularExpression) == nil
        }
        output = filteredLines.joined(separator: "\n")

        output = output.replacingOccurrences(
            of: #"(?:\b\d+\.\s*\.\s*){2,}"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\*\*[A-Za-z][A-Za-z\s]{0,30}$"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)

        var trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private func buildIntegrityRepairPrompt(
        question: String,
        issueLabels: [String],
        answerIntent: AnswerIntent,
        requiresCitations: Bool
    ) -> String {
        let formatHint: String = switch answerIntent {
        case .procedure:
            "Answer with direct outcome first. Use numbered steps only if complete explicit steps exist in excerpts."
        case .lookup, .tableLookup:
            "Answer with the specific value first, then 1-2 short support sentences. Keep under 120 words."
        case .compare:
            "Answer in concise compare format with only grounded differences."
        default:
            "Answer in concise paragraphs with no placeholder bullets or numbering artifacts. Keep under 180 words."
        }

        let citationHint = requiresCitations
            ? "Include citations like [S1], [S2] for factual claims when available in excerpts."
            : "Citations optional."

        let issueHint = issueLabels.joined(separator: ", ")

        return """
        Produce a clean, grounded final answer for the question.
        Constraints:
        - Use ONLY facts present in the provided context excerpts.
        - Fix these output issues: \(issueHint)
        - Remove repetition, placeholder numbering, and malformed fragments.
        - Do not add new facts.
        - \(formatHint)
        - \(citationHint)
        - Write in detailed prose with complete sentences. Use ### section headers and **bold** sparingly for key terms only.
        - Use bullet points only for actual sequential steps or specification values.
        - Separate paragraphs and sections with blank lines for readability.

        QUESTION:
        \(question)
        """
    }

    private func compactDegenerateResponse(
        _ text: String,
        question: String,
        answerIntent: AnswerIntent
    ) -> String {
        let normalized = normalizeMalformedResponseArtifacts(text)
        let questionTerms = Set(
            question.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )

        let sentenceRegex = try? NSRegularExpression(pattern: #"[^.!?\n]+[.!?]?"#)
        guard let sentenceRegex else { return normalized }

        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = sentenceRegex.matches(in: normalized, options: [], range: fullRange)
        guard !matches.isEmpty else { return normalized }

        struct Candidate {
            let text: String
            let key: String
            let score: Int
            let order: Int
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(matches.count)

        for (idx, match) in matches.enumerated() {
            guard let range = Range(match.range, in: normalized) else { continue }
            let sentence = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sentence.count >= 10 else { continue }

            let key = sentence
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                .split(separator: " ")
                .joined(separator: " ")
            guard !key.isEmpty else { continue }

            let lower = sentence.lowercased()
            let overlap = questionTerms.reduce(0) { partial, term in
                partial + (lower.contains(term) ? 1 : 0)
            }
            let digitBoost = lower.rangeOfCharacter(from: .decimalDigits) != nil ? 1 : 0
            let score = overlap * 3 + digitBoost

            candidates.append(Candidate(text: sentence, key: key, score: score, order: idx))
        }

        guard !candidates.isEmpty else { return normalized }

        // Deduplicate by normalized sentence key, keeping best-scoring earliest occurrence.
        var byKey: [String: Candidate] = [:]
        for candidate in candidates {
            if let existing = byKey[candidate.key] {
                if candidate.score > existing.score || (candidate.score == existing.score && candidate.order < existing.order) {
                    byKey[candidate.key] = candidate
                }
            } else {
                byKey[candidate.key] = candidate
            }
        }

        let ordered = byKey.values.sorted {
            if $0.score == $1.score { return $0.order < $1.order }
            return $0.score > $1.score
        }

        let maxSentences: Int
        let maxWords: Int
        switch answerIntent {
        case .lookup, .tableLookup:
            maxSentences = 3
            maxWords = 120
        case .procedure:
            maxSentences = 6
            maxWords = 220
        default:
            maxSentences = 6
            maxWords = 220
        }

        var chosen: [String] = []
        var totalWords = 0
        for candidate in ordered.prefix(max(6, maxSentences * 2)) {
            let sentenceWords = candidate.text.split(separator: " ").count
            if totalWords + sentenceWords > maxWords, !chosen.isEmpty { continue }
            chosen.append(candidate.text)
            totalWords += sentenceWords
            if chosen.count >= maxSentences || totalWords >= maxWords { break }
        }

        guard !chosen.isEmpty else { return normalized }
        // Preserve paragraph structure: use double-newline between sentences
        // so downstream Markdown rendering can format them properly
        let compacted = chosen.joined(separator: "\n\n")
        return normalizeMalformedResponseArtifacts(compacted)
    }

    private func boundedVerificationResponseText(
        _ responseText: String,
        answerIntent: AnswerIntent
    ) -> String {
        let wordCap: Int = switch answerIntent {
        case .lookup, .tableLookup:
            140
        case .procedure:
            220
        default:
            220
        }

        let charCap = 1400
        let sentences = responseText
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var output: [String] = []
        var words = 0
        var chars = 0
        for sentence in sentences {
            let w = sentence.split(separator: " ").count
            let c = sentence.count
            if (words + w > wordCap || chars + c > charCap), !output.isEmpty { break }
            output.append(sentence)
            words += w
            chars += c
        }

        let bounded = output.isEmpty ? String(responseText.prefix(charCap)) : output.joined(separator: ". ")
        return bounded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isResponseIntegrityImproved(original: String, candidate: String) -> Bool {
        let originalIssues = responseIntegrityIssues(original)
        let candidateIssues = responseIntegrityIssues(candidate)

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard candidate.count >= min(40, max(10, original.count / 6)) else { return false }

        // Clear win: fewer issues
        if candidateIssues.count < originalIssues.count {
            return true
        }

        // If issue counts tie, use lexical diversity as tiebreaker.
        // Higher unique-word ratio = more informative, less repetitive.
        if candidateIssues.count == originalIssues.count {
            let origRatio = uniqueWordRatio(original)
            let candRatio = uniqueWordRatio(candidate)

            // Candidate has meaningfully better diversity (≥5% improvement)
            if candRatio > origRatio + 0.05 {
                return true
            }

            // Equal diversity: prefer shorter (more concise = synthesized better)
            let ratioDiff: Double = candRatio - origRatio
            if Swift.abs(ratioDiff) < 0.05, candidate.count <= original.count {
                return true
            }
        }

        return false
    }

    /// Fraction of unique words in text (0.0–1.0). Higher = more diverse/informative.
    private nonisolated func uniqueWordRatio(_ text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard words.count >= 5 else { return 1.0 }
        return Double(Set(words).count) / Double(words.count)
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
        sourceChunks: [DocumentChunk] = [],
        allowStructuredRAG: Bool = false,
        structuredRAGMode: StructuredRAGMode = .direct
    ) async throws -> LLMResponse {
        let upstreamHandler = LLMStreamingContext.handler

        func attempt(service: LLMService) async throws -> LLMResponse {
            let attemptStart = Date()

            // ═══════════════════════════════════════════════════════════════
            // StreamCapture with LIVE repetition loop detection
            // ═══════════════════════════════════════════════════════════════
            // Monitors tokens as they arrive. If the same n-gram appears
            // >N times in a sliding window, sets a flag that the generation
            // task checks on each iteration — aborting generation mid-stream
            // instead of waiting for full output and cleaning up after.
            actor StreamCapture {
                private var captured = ""
                private var firstChunkTime: TimeInterval?

                // Repetition detection state
                private var recentTokens: [String] = []
                private var repetitionDetected = false
                private var cleanPrefixLength = 0 // chars before repetition started

                /// Sliding window size for repetition detection (in tokens/words)
                private let windowSize = 60

                func record(_ event: LLMStreamEvent, since start: Date) {
                    guard !event.text.isEmpty else { return }
                    if firstChunkTime == nil {
                        firstChunkTime = Date().timeIntervalSince(start)
                    }
                    let previousLength = captured.count
                    captured += event.text

                    // Don't keep checking after we've already flagged
                    guard !repetitionDetected else { return }

                    // Tokenize new content into words for n-gram analysis
                    let newWords = event.text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                        .map { String($0).lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
                        .filter { !$0.isEmpty }
                    recentTokens.append(contentsOf: newWords)

                    // Only check every 20 words (amortize cost)
                    guard recentTokens.count >= 40, recentTokens.count % 20 < newWords.count else { return }

                    // Keep a bounded window
                    if recentTokens.count > windowSize * 2 {
                        recentTokens = Array(recentTokens.suffix(windowSize * 2))
                    }

                    // Check for repeated n-grams (bigrams, trigrams, 4-grams)
                    for n in 2...4 {
                        guard recentTokens.count >= n * 4 else { continue }
                        let window = Array(recentTokens.suffix(windowSize))
                        guard window.count >= n * 4 else { continue }

                        var ngramCounts: [String: Int] = [:]
                        for i in 0...(window.count - n) {
                            let gram = window[i..<(i + n)].joined(separator: " ")
                            ngramCounts[gram, default: 0] += 1
                        }

                        // If any n-gram appears >30% of possible positions, it's a loop
                        let maxPositions = window.count - n + 1
                        if let (_, topCount) = ngramCounts.max(by: { $0.value < $1.value }),
                           topCount >= 6,
                           Double(topCount) / Double(maxPositions) > 0.30 {
                            repetitionDetected = true
                            cleanPrefixLength = previousLength
                            Log.warning("[StreamCapture] Live repetition loop detected after \(captured.count) chars (\(n)-gram repeated \(topCount)×)", category: .llm)
                            return
                        }
                    }
                }

                func snapshot() -> (text: String, firstChunkTime: TimeInterval?) {
                    (captured, firstChunkTime)
                }

                func isRepetitionDetected() -> Bool {
                    repetitionDetected
                }

                /// Returns text up to where repetition started (the "clean" prefix)
                func cleanPrefix() -> String {
                    if repetitionDetected, cleanPrefixLength > 0 {
                        return String(captured.prefix(cleanPrefixLength))
                    }
                    return captured
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

                    let response: LLMResponse
                    if allowStructuredRAG,
                       #available(iOS 26.0, *),
                       let appleService = service as? AppleFoundationLLMService,
                       let context,
                       !context.isEmpty,
                       !sourceChunks.isEmpty {
                        let systemChars = (config.systemPrompt ?? "").count
                        let estimatedInputTokens = Int(ceil(Double(context.count + prompt.count + systemChars + 180) / 1.4))
                        let structuredSchemaTokens = structuredRAGMode == .reasoned ? 220 : 160
                        let structuredOutputReserve = min(max(config.maxTokens, 180), 360)
                        let withinStructuredBudget = estimatedInputTokens + structuredSchemaTokens + structuredOutputReserve <= 3600

                        if withinStructuredBudget {
                            let modeLabel = structuredRAGMode == .reasoned ? "reasoned" : "direct"
                            Log.info("[RAG] Using constrained structured answer generation (\(modeLabel))", category: .llm)
                            response = try await appleService.generateStructuredRAGAnswer(
                                prompt: prompt,
                                context: context,
                                config: config,
                                sourceCount: sourceChunks.count,
                                mode: structuredRAGMode
                            )
                        } else {
                            Log.debug("[RAG] Structured answer generation skipped due to token budget (~\(estimatedInputTokens) input tokens)", category: .llm)
                            response = try await service.generate(
                                prompt: prompt,
                                context: context,
                                config: config
                            )
                        }
                    } else {
                        response = try await service.generate(
                            prompt: prompt,
                            context: context,
                            config: config
                        )
                    }

                    // ── Post-generation: check if StreamCapture detected a loop ──
                    if await streamCapture.isRepetitionDetected() {
                        Log.warning("[RAG] Streaming repetition detected — using clean prefix instead of full response", category: .llm)
                        let cleanText = await streamCapture.cleanPrefix()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let (_, firstChunkTime) = await streamCapture.snapshot()

                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }

                        if cleanText.count >= 10 {
                            return LLMResponse(
                                text: cleanText,
                                tokensGenerated: cleanText.split(whereSeparator: { $0.isWhitespace }).count,
                                timeToFirstToken: response.timeToFirstToken ?? firstChunkTime,
                                totalTime: max(response.totalTime, Date().timeIntervalSince(attemptStart)),
                                modelName: response.modelName ?? service.modelName,
                                toolCallsMade: response.toolCallsMade
                            )
                        }
                        // If clean prefix is too short, fall through to normal response
                        // (integrity pipeline will catch it downstream)
                    }

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
                    if capturedTrimmed.count >= 10 {
                        // If we already streamed a meaningful partial answer, do not replace it
                        // with a fallback provider. Lowered from 24→10 to salvage more partial output.
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

            // Rate-limit retry: Apple FM on-device model can hit transient rate limits
            // after heavy compression. Wait briefly and retry once before falling through
            // to fallback services.
            let isRateLimited: Bool
            if let llmErr = error as? LLMError {
                switch llmErr {
                case .rateLimited, .concurrentRequests: isRateLimited = true
                default: isRateLimited = errorDesc.lowercased().contains("rate") || errorDesc.contains("concurrent")
                }
            } else {
                isRateLimited = errorDesc.lowercased().contains("rate") || errorDesc.contains("concurrent")
            }
            if isRateLimited {
                Log.info("[RAG] Primary LLM rate-limited — waiting 2s before retry", category: .llm)
                try? await Task.sleep(for: .seconds(2))
                do {
                    let retryResponse = try await attempt(service: _llmService)
                    Log.info("[RAG] Primary LLM retry succeeded after rate-limit backoff", category: .llm)
                    return retryResponse
                } catch {
                    Log.warning("[RAG] Primary LLM retry also failed after backoff: \(error.localizedDescription)", category: .llm)
                }
            }

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

    // MARK: - Document Content Classification

    /// Classify document domain from filename patterns and corpus signals.
    /// Returns a short human-readable domain like "Vehicle Manual" or "Technical Report".
    static func classifyDocumentDomain(
        filename: String,
        signals: LibraryIntelligenceCenter.CorpusSignals,
        entities: [String]
    ) -> String {
        let lower = filename.lowercased()
        let joinedEntities = entities.joined(separator: " ").lowercased()
        let combined = lower + " " + joinedEntities

        // Filename-based quick matches
        let domainPatterns: [(keywords: [String], domain: String)] = [
            (["owner", "manual", "vehicle", "car", "truck", "suv", "sedan", "automotive", "motor"], "Vehicle Manual"),
            (["study", "protocol", "cohort", "assay", "sample", "specimen", "pharma"], "Life Sciences Document"),
            (["legal", "contract", "agreement", "statute", "law", "regulation", "compliance"], "Legal Document"),
            (["financial", "accounting", "balance sheet", "income statement", "revenue", "fiscal"], "Financial Document"),
            (["recipe", "cooking", "ingredient", "culinary", "baking"], "Recipe Collection"),
            (["syllabus", "curriculum", "course", "lecture", "education", "textbook", "exam"], "Educational Material"),
            (["api", "sdk", "documentation", "reference", "developer", "programming"], "API Documentation"),
            (["research", "abstract", "methodology", "hypothesis", "findings", "journal"], "Research Paper"),
            (["resume", "cv", "curriculum vitae", "experience", "qualifications"], "Resume / CV"),
            (["invoice", "receipt", "purchase", "order", "billing", "payment"], "Invoice / Receipt"),
            (["patent", "invention", "claims", "prior art"], "Patent Document"),
            (["blueprint", "schematic", "wiring", "circuit", "engineering", "cad"], "Engineering Drawing"),
            (["safety", "msds", "hazard", "sds", "material safety"], "Safety Data Sheet"),
            (["report", "analysis", "summary", "overview", "assessment"], "Report"),
            (["manual", "guide", "handbook", "instructions", "procedure"], "Reference Manual"),
            (["specification", "spec", "requirements", "standard"], "Specification"),
            (["presentation", "slide", "deck"], "Presentation"),
            (["memo", "memorandum", "circular", "notice"], "Memo / Notice"),
        ]

        for pattern in domainPatterns {
            let matchCount = pattern.keywords.filter { combined.contains($0) }.count
            if matchCount >= 2 { return pattern.domain }
        }

        // Single keyword fallback with high confidence
        for pattern in domainPatterns.prefix(10) {
            if pattern.keywords.contains(where: { lower.contains($0) }) {
                return pattern.domain
            }
        }

        // Signal-based fallback
        if signals.hasCode && signals.technicalDensity > 0.3 {
            return "Source Code"
        }
        if signals.hasMath {
            return "Technical Document"
        }
        if signals.technicalDensity > 0.4 {
            return "Technical Document"
        }

        return "Document"
    }

    /// Build a short content descriptor from document profiles.
    static func buildContentDescriptor(
        signals: LibraryIntelligenceCenter.CorpusSignals,
        entities: [String]
    ) -> String {
        // Use top entities to describe what the content is about
        let uniqueTopics = Array(Set(entities.map { $0.lowercased().capitalized })).prefix(4)
        if !uniqueTopics.isEmpty {
            return uniqueTopics.joined(separator: ", ")
        }

        // Fallback: describe by content characteristics
        var traits: [String] = []
        if signals.hasCode { traits.append("code") }
        if signals.hasMath { traits.append("formulas") }
        if signals.technicalDensity > 0.3 { traits.append("technical") }
        if signals.multilingualScore > 0.3 { traits.append("multilingual") }
        if signals.structuredRatio > 0.5 { traits.append("structured data") }
        return traits.isEmpty ? "General content" : traits.joined(separator: " & ")
    }

    /// Extract meaningful content categories from entities and signals.
    static func extractContentCategories(
        entities: [String],
        signals: LibraryIntelligenceCenter.CorpusSignals
    ) -> [String] {
        var categories: [String] = []

        // Use entity topics
        let uniqueEntities = Array(Set(entities.map { $0.capitalized }))
        categories.append(contentsOf: uniqueEntities.prefix(5))

        // Add signal-derived categories
        if signals.hasCode { categories.append("Code") }
        if signals.hasMath { categories.append("Mathematics") }
        if signals.multilingualScore > 0.3 { categories.append("Multilingual") }

        return Array(Set(categories)).sorted()
    }

    /// Map raw NLLanguage code to human-readable name.
    static func languageDisplayName(_ code: String) -> String {
        let map: [String: String] = [
            "en": "English", "es": "Spanish", "fr": "French",
            "de": "German", "it": "Italian", "pt": "Portuguese",
            "nl": "Dutch", "pl": "Polish", "ja": "Japanese",
            "ko": "Korean", "zh-Hans": "Chinese (Simplified)",
            "zh-Hant": "Chinese (Traditional)", "ar": "Arabic",
            "ru": "Russian", "hi": "Hindi", "sv": "Swedish",
            "da": "Danish", "fi": "Finnish", "nb": "Norwegian",
            "tr": "Turkish", "th": "Thai", "vi": "Vietnamese",
        ]
        return map[code] ?? code.uppercased()
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
        // Clean up the response text (normalize whitespace, preserve markdown formatting)
        let cleanedResponse = cleanupResponseText(response.generatedResponse)
        let stabilizedResponse = trimIncompleteResponseTail(cleanedResponse)
        let repairedResponse = repairMalformedURLs(stabilizedResponse)
        let finalizedStructuredAnswer = response.structuredAnswer?.updatingAnswer(repairedResponse)
        let fallbackReasoningTrace = await MainActor.run {
            self.thinkingEvents.compactReasoningTrace()
        }
        let finalizedMetadata = response.metadata.withReasoningTrace(fallbackReasoningTrace)
        var finalResponse = response
        finalResponse = RAGResponse(
            queryId: response.queryId,
            retrievedChunks: response.retrievedChunks,
            generatedResponse: repairedResponse,
            metadata: finalizedMetadata,
            confidenceScore: response.confidenceScore,
            qualityWarnings: response.qualityWarnings,
            structuredAnswer: finalizedStructuredAnswer
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

    private nonisolated func appendedGatingDecision(_ existing: String?, _ decision: String) -> String {
        existing.map { "\($0),\(decision)" } ?? decision
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func sourceOnlyOutcomeIfNeeded(
        query: String,
        candidateAnswer: String,
        retrievedChunks: [RetrievedChunk],
        answerIntent: AnswerIntent,
        verificationResult: RAGVerificationResult?,
        isSourceLocked: Bool = false
    ) async -> SourceOnlyAnswerOutcome? {
        let trimmedAnswer = candidateAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty, !retrievedChunks.isEmpty else { return nil }
        guard answerIntent.isExtractiveFirst else { return nil }
        guard !isSourceLocked else { return nil }

        guard let outcome = await SourceOnlyAnswerService.shared.verifyAndRender(
            query: query,
            candidateAnswer: trimmedAnswer,
            retrievedChunks: retrievedChunks,
            answerIntent: answerIntent,
            verificationResult: verificationResult
        ) else {
            return nil
        }

        let preserveAbstention = (Self.isStateLookupQuery(query) || isPrecisionValueQuery(query)) && !isSourceLocked

        // Keep this conservative for user-facing quality.
        // Use source-only when it strengthens a grounded lookup answer, not when it
        // downgrades a plausible answer into a brittle abstention or ultra-thin rewrite.
        // Direct source-locked extractions are already pinned to retrieved evidence.
        if outcome.shouldAbstain {
            return preserveAbstention ? outcome : nil
        }

        guard outcome.supportedClaims.count > 0 else {
            return preserveAbstention ? outcome : nil
        }
        guard outcome.fidelityScore >= 0.72 else { return nil }

        return outcome
    }
#endif

    /// Repair malformed URLs in LLM output so links are tappable and correct.
    /// Fixes: spaces within URLs, missing percent-encoding, whitespace before TLDs.
    /// Preserves valid markdown links and bare URLs — only repairs, never removes.
    private nonisolated func repairMalformedURLs(_ text: String) -> String {
        var result = text

        // 1. Fix markdown links [text](broken url) — repair the URL portion
        if let markdownLinkRegex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\((https?://[^\)]*)\)"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = markdownLinkRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let labelRange = Range(match.range(at: 1), in: result),
                      let urlRange = Range(match.range(at: 2), in: result) else { continue }
                let label = String(result[labelRange])
                let rawURL = String(result[urlRange])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(fullRange, with: "[\(label)](\(fixed))")
            }
        }

        // 2. Fix bare URLs (not inside markdown link parens)
        if let bareURLRegex = try? NSRegularExpression(
            pattern: #"(?<!\()https?://\S+"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = bareURLRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let rawURL = String(result[range])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(range, with: fixed)
            }
        }

        return result
    }

    /// Repair a single URL string: remove internal spaces, fix encoding.
    private nonisolated static func repairURL(_ url: String) -> String {
        var fixed = url
        // Remove spaces (LLM inserts spaces like "github .com" or "blob/ main")
        fixed = fixed.replacingOccurrences(of: " ", with: "")
        // Remove trailing punctuation the LLM may have appended
        while fixed.hasSuffix(".") || fixed.hasSuffix(",") || fixed.hasSuffix(";") || fixed.hasSuffix(")") {
            fixed = String(fixed.dropLast())
        }
        return fixed
    }

    /// Clean up response text — normalize whitespace while preserving markdown formatting
    /// Headers, bullet lists, numbered lists, code fences, and block quotes are kept intact
    /// for rendering by the block-level MarkdownText view (v1.2+)
    private nonisolated func cleanupResponseText(_ text: String) -> String {
        var result = text

        // NOTE: Markdown formatting (headers, lists, code fences, block quotes) is now preserved.
        // MarkdownText renders full block-level markdown as of v1.2.
        // Only whitespace normalization and orphan cleanup remain here.

        // ═══════════════════════════════════════════════════════════════
        // PHASE 0: Intra-sentence repetition loop detection
        // ═══════════════════════════════════════════════════════════════
        // Catches degenerate LLM output like:
        //   "02/23/2024, 02/23/2024, 02/23/2024, 02/23/2024, ..."
        // where a phrase repeats >3 times consecutively within a single
        // sentence or bullet point. The sentence-level dedup in
        // compactDegenerateResponse can't catch this because it's ONE
        // long sentence, not repeated sentences.
        result = collapseIntraLineRepetition(result)

        // Remove orphaned list markers with no content (just "-" or "•" or "1." alone on a line)
        result = result.components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Remove empty bullet markers
                if trimmed == "-" || trimmed == "*" || trimmed == "•" {
                    return ""
                }
                // Remove empty numbered markers (e.g., "2." or "3)" with nothing after)
                if trimmed.range(of: #"^\d+[.)]?\s*$"#, options: .regularExpression) != nil {
                    return ""
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

    /// Detects and collapses intra-line/intra-sentence phrase repetition loops.
    /// e.g. "02/23/2024, 02/23/2024, 02/23/2024, ..." → "02/23/2024."
    /// Works on comma-separated, space-separated, and semicolon-separated repetition.
    private nonisolated func collapseIntraLineRepetition(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var changed = false

        for lineIdx in 0..<lines.count {
            let line = lines[lineIdx]
            guard line.count > 60 else { continue } // Short lines can't have meaningful repetition

            // Strategy 1: Comma/semicolon-separated repetition
            // Split on ", " or "; " and check for dominant phrase
            for separator in [", ", "; "] {
                let parts = line.components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard parts.count >= 4 else { continue }

                var freq: [String: Int] = [:]
                for part in parts {
                    let normalized = part.lowercased()
                        .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    guard !normalized.isEmpty else { continue }
                    freq[normalized, default: 0] += 1
                }

                if let (dominant, count) = freq.max(by: { $0.value < $1.value }),
                   count >= 3, Double(count) / Double(parts.count) >= 0.4 {
                    // Find the actual (non-normalized) first occurrence
                    let firstOccurrence = parts.first {
                        $0.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) == dominant
                    } ?? dominant

                    // Keep everything before the first repetition starts, then one occurrence
                    let uniqueParts = parts.filter {
                        $0.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) != dominant
                    }

                    var replacement: String
                    if uniqueParts.isEmpty {
                        // Entire line was repetition — keep just one
                        // Preserve any leading markdown/bullet prefix
                        let prefix = extractLeadingPrefix(from: line)
                        replacement = prefix + firstOccurrence + "."
                    } else {
                        // Mix of unique + repeated — keep uniques + one occurrence of repeated
                        var kept = uniqueParts
                        kept.append(firstOccurrence)
                        replacement = kept.joined(separator: separator)
                    }

                    lines[lineIdx] = replacement
                    changed = true
                    Log.info("[RepetitionFilter] Collapsed \(count)× repetition of '\(dominant.prefix(30))' on line \(lineIdx + 1)", category: .llm)
                    break // Only apply one separator strategy per line
                }
            }

            // Strategy 2: Word-level repetition (same word/token 5+ times in a row)
            // Catches: "the the the the the" or "data data data data"
            if !changed || lines[lineIdx].count > 200 {
                let words = lines[lineIdx].split(separator: " ")
                guard words.count >= 6 else { continue }

                var collapsed: [Substring] = []
                var consecutiveCount = 1

                for i in 0..<words.count {
                    if i > 0, words[i].lowercased() == words[i - 1].lowercased() {
                        consecutiveCount += 1
                    } else {
                        consecutiveCount = 1
                    }

                    if consecutiveCount <= 2 { // Allow max 2 consecutive same words
                        collapsed.append(words[i])
                    } else if consecutiveCount == 3 {
                        // On 3rd+ repetition, don't add
                        changed = true
                    }
                }

                if changed {
                    lines[lineIdx] = collapsed.joined(separator: " ")
                    Log.info("[RepetitionFilter] Collapsed word-level repetition on line \(lineIdx + 1)", category: .llm)
                }
            }
        }

        return changed ? lines.joined(separator: "\n") : text
    }

    /// Extracts leading markdown prefix (bullet, number, header) from a line
    private nonisolated func extractLeadingPrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Match: "* ", "- ", "• ", "1. ", "### ", etc.
        if let match = trimmed.range(of: #"^(\s*(?:[*•\-]|\d+[.)]|#{1,4})\s+)"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return ""
    }

    /// Replace cryptic [S1], [S2] citations with human-readable source references
    /// e.g., [S1] → [📄 Manual.pdf, p.12] or [Source 1] if chunks unavailable
    private nonisolated func humanizeCitations(_ text: String, chunks: [RetrievedChunk]) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Match [S1], [S2], [S3], etc. (also handles [S1][S2] adjacent and [S1, S2] combined)
        // First handle combined citations like [S1, S2]
        let combinedPattern = #"\[S(\d+)(?:\s*,\s*S(\d+))*\]"#
        if let combinedRegex = try? NSRegularExpression(pattern: combinedPattern, options: []) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = combinedRegex.matches(in: result, options: [], range: nsRange)

            // Process in reverse to preserve string indices
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }
                let matchText = String(result[matchRange])

                // Extract all S-numbers from this match
                let numPattern = #"S(\d+)"#
                guard let numRegex = try? NSRegularExpression(pattern: numPattern, options: []) else { continue }
                let numMatches = numRegex.matches(in: matchText, options: [], range: NSRange(matchText.startIndex..., in: matchText))

                var refs: [String] = []
                for numMatch in numMatches {
                    if let numRange = Range(numMatch.range(at: 1), in: matchText),
                       let idx = Int(matchText[numRange]) {
                        let chunkIndex = idx - 1 // [S1] = chunks[0]
                        if chunkIndex >= 0 && chunkIndex < chunks.count {
                            let chunk = chunks[chunkIndex]
                            let filename = chunk.sourceDocument.isEmpty
                                ? "Document"
                                : URL(fileURLWithPath: chunk.sourceDocument).lastPathComponent
                            if let page = chunk.pageNumber {
                                refs.append("📄 \(filename), p.\(page)")
                            } else {
                                refs.append("📄 \(filename)")
                            }
                        } else {
                            refs.append("Source \(idx)")
                        }
                    }
                }

                if !refs.isEmpty {
                    let replacement = "[" + refs.joined(separator: "; ") + "]"
                    result.replaceSubrange(matchRange, with: replacement)
                }
            }
        }

        return result
    }

    private nonisolated func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private nonisolated func isTrivialQuery(_ query: String) -> Bool {
        QueryProfileService.isTrivialQuery(query)
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

    private func buildPrecisionLookupCandidates(
        included: [RetrievedChunk],
        ordered: [RetrievedChunk],
        desiredCount: Int
    ) -> [RetrievedChunk] {
        guard !ordered.isEmpty else { return included }

        let expandedCount = min(ordered.count, max(included.count, desiredCount))
        let expanded = Array(ordered.prefix(expandedCount))
        return mergeUniqueChunks(included, expanded)
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

    private func resolvedDisplayResponse(
        fallback: String,
        structuredAnswer: StructuredAnswer?
    ) -> String {
        let fallbackText = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = structuredAnswer?.answer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !candidate.isEmpty else { return fallbackText }
        guard !fallbackText.isEmpty else { return candidate }

        if let structuredAnswer,
           shouldPreferFallbackDisplay(
                fallback: fallbackText,
                candidate: candidate,
                answerType: structuredAnswer.answerType
           ) {
            return fallbackText
        }

        return candidate
    }

    private func shouldPreferFallbackDisplay(
        fallback: String,
        candidate: String,
        answerType: StructuredAnswer.AnswerType
    ) -> Bool {
        let candidateIssues = responseIntegrityIssues(candidate)
        let fallbackIssues = responseIntegrityIssues(fallback)

        if !candidateIssues.isEmpty && fallbackIssues.isEmpty {
            return true
        }

        if looksFragmentaryDisplayText(candidate) && !looksFragmentaryDisplayText(fallback) {
            return true
        }

        if shouldPreserveStructuredExactDisplay(candidate: candidate, answerType: answerType) {
            return false
        }

        switch answerType {
        case .lookup, .tableLookup, .compute:
            let fallbackWords = fallback.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let candidateWords = candidate.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let fallbackCitations = citationCount(in: fallback)
            let candidateCitations = citationCount(in: candidate)
            let fallbackLooksList = fallback.contains("\n• ") || fallback.contains("\n1. ")
            let candidateLooksList = candidate.contains("\n• ") || candidate.contains("\n1. ")
            let fallbackLooksCompact = fallbackWords > 0 && fallbackWords <= 90

            if fallbackLooksCompact {
                if candidateLooksList && !fallbackLooksList {
                    return true
                }
                if candidateCitations > max(2, fallbackCitations + 1) {
                    return true
                }
                if candidateWords > 120 && candidateWords > fallbackWords + 40 {
                    return true
                }
            }

            return false
        default:
            return false
        }
    }

    private func shouldPreserveStructuredExactDisplay(
        candidate: String,
        answerType: StructuredAnswer.AnswerType
    ) -> Bool {
        switch answerType {
        case .lookup, .tableLookup, .compute:
            break
        default:
            return false
        }

        let candidateWords = candidate.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lower = candidate.lowercased()
        let hasQuotedValue = candidate.contains("'") || candidate.contains("\"")
        let hasLabelValue = candidate.contains(":") && candidateWords <= 60
        let hasCitation = citationCount(in: candidate) > 0
        let hasSpecificationCue = lower.range(
            of: #"\b(?:sae|api|ilsac|dot-4|gl-5|sp4|[0o]w-20|5w-30|75w/85|full open|user height setting|auto open|level\s*[123])\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        return hasQuantitativeAnswerSignal(candidate)
            || (hasCitation && (hasQuotedValue || hasLabelValue || hasSpecificationCue))
    }

    private func looksFragmentaryDisplayText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let nonEmptyLines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let incompleteMarkers: Set<String> = ["and", "or", "but", "the", "a", "an", "to", "of", "in", "for", "with"]
        let lastWord = String(trimmed.split(separator: " ").last ?? "").lowercased()
        let endsCleanly = Self.hasResponseTerminalBoundary(trimmed)

        if !endsCleanly && incompleteMarkers.contains(lastWord) {
            return true
        }

        let fragmentLines = nonEmptyLines.filter { line in
            let wordCount = line.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let looksListLine = line.range(of: #"^(?:[-•*]|\d+[.)])\s+"#, options: .regularExpression) != nil
            return !looksListLine && wordCount >= 3 && wordCount <= 8 && !Self.hasResponseTerminalBoundary(line)
        }

        return nonEmptyLines.count >= 2 && fragmentLines.count * 2 >= nonEmptyLines.count
    }

    private nonisolated func trimIncompleteResponseTail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if Self.hasResponseTerminalBoundary(trimmed) {
            return trimmed
        }

        if Self.looksLikeStandaloneValueResponse(trimmed) {
            return trimmed
        }

        let incompleteMarkers: Set<String> = ["and", "or", "but", "the", "a", "an", "to", "of", "in", "for", "with", "if", "when", "because", "that", "which"]
        let lastWord = String(trimmed.split(separator: " ").last ?? "").lowercased()
        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let lastLine = nonEmptyLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lastLineWordCount = lastLine.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let looksShortDanglingLine = lastLineWordCount > 0 && lastLineWordCount <= 6
            let looksBullet = lastLine.range(of: #"^(?:[-•*]|\d+[.)])\s+"#, options: .regularExpression) != nil

            if (looksShortDanglingLine || incompleteMarkers.contains(lastWord)) && nonEmptyLines.count > 1 {
                let droppedLastLine = nonEmptyLines.dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !droppedLastLine.isEmpty && (Self.hasResponseTerminalBoundary(droppedLastLine) || !looksBullet) {
                    return droppedLastLine
                }
            }
        }

        if let boundaryIndex = Self.lastCompleteSentenceBoundary(in: trimmed) {
            let candidate = String(trimmed[...boundaryIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= max(24, trimmed.count / 3) {
                return candidate
            }
        }

        return trimmed
    }

    private nonisolated static func hasResponseTerminalBoundary(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return [".", "!", "?", "]", ")", "}", "\"", "'"] .contains(last)
    }

    private nonisolated static func looksLikeStandaloneValueResponse(_ text: String) -> Bool {
        text.range(
            of: #"^\s*(?:\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,4}|[A-Za-z][A-Za-z0-9 /_-]{0,24}:\s*\d+(?:[.,]\d+)?(?:\s*[A-Za-z%/.-]+){0,4})(?:\s*\[[^\]]+\])?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated static func lastCompleteSentenceBoundary(in text: String) -> String.Index? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for index in trimmed.indices.reversed() {
            let character = trimmed[index]
            if character == "." || character == "!" || character == "?" {
                return index
            }
        }

        return nil
    }

    private func citationCount(in text: String) -> Int {
        guard let regex = Self.citationRegex else { return 0 }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func highPrecisionLookupOverrideAnswer(
        question: String,
        answerIntent: AnswerIntent,
        retrievedChunks: [RetrievedChunk]
    ) async -> String? {
        guard !retrievedChunks.isEmpty else { return nil }
        guard !isConceptualLookupQuery(question) else { return nil }

        // Universal behavior: if intent classification misses but the query is clearly
        // asking for a precise value/spec, still attempt extractive locking with a stricter threshold.
        let forceExtractiveAttempt = !answerIntent.isExtractiveFirst && isPrecisionValueQuery(question)
        guard answerIntent.isExtractiveFirst || forceExtractiveAttempt else { return nil }

        let candidateChunks: [RetrievedChunk]
        if EvidenceScoringPolicyService.isStateLookupQuery(question) {
            candidateChunks = prioritizedStateLookupCandidates(from: Array(retrievedChunks.prefix(18)), query: question)
        } else {
            candidateChunks = Array(retrievedChunks.prefix(18))
        }
        let extractorIntent: AnswerIntent = answerIntent.isExtractiveFirst ? answerIntent : .lookup
        let extraction = await specificationExtractor.extract(
            query: question,
            chunks: candidateChunks,
            answerIntent: extractorIntent
        )

        let confidenceThreshold = EvidenceScoringPolicyService.precisionLockThreshold(
            forceExtractiveAttempt: forceExtractiveAttempt
        )
        guard case let .success(result) = extraction,
              result.confidence >= confidenceThreshold else {
            return nil
        }

        // For forced attempts, only lock if the extracted span looks like a concrete
        // measurement/value (prevents accidental override for open-ended prompts).
        if forceExtractiveAttempt,
           !hasQuantitativeAnswerSignal(result.answerSpan)
        {
            return nil
        }

        let answerSpan = enrichedPrecisionAnswerSpan(for: result)

        if let label = result.matchedLabel, !label.isEmpty {
            return "\(label): \(answerSpan). \(result.citation)"
        }

        if isPrecisionValueQuery(question) || result.specificationType == "Measurement" {
            return "\(answerSpan). \(result.citation)"
        }

        return result.formattedAnswer
    }

    private func prioritizedStateLookupCandidates(
        from chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk] {
        chunks.sorted { lhs, rhs in
            let lhsScore = stateLookupCandidatePriority(lhs, query: query)
            let rhsScore = stateLookupCandidatePriority(rhs, query: query)
            if lhsScore == rhsScore {
                if lhs.similarityScore == rhs.similarityScore {
                    return lhs.rank < rhs.rank
                }
                return lhs.similarityScore > rhs.similarityScore
            }
            return lhsScore > rhsScore
        }
    }

    private func stateLookupCandidatePriority(_ chunk: RetrievedChunk, query: String) -> Int {
        let content = (chunk.chunk.parentContent ?? chunk.chunk.content).lowercased()
        var score = 0

        if EvidenceScoringPolicyService.satisfiesStateLookupAnchors(query: query, content: content) {
            score += 6
        }

        if content.contains("table:") || content.contains("[rows]") || content.contains("row 1:") {
            score += 4
        }

        if content.contains("[summary]") || content.contains("this reference table") || content.contains("this technical reference") {
            score += 2
        }

        if content.contains("[cells]") || content.contains("cell r") {
            score -= 5
        }

        if content.contains("column 1") || content.contains("column 2") {
            score -= 2
        }

        return score
    }

    private func enrichedPrecisionAnswerSpan(for result: SpecificationExtractionResult) -> String {
        let base = result.answerSpan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("(") else { return base }

        let content = result.sourceChunk.chunk.parentContent ?? result.sourceChunk.chunk.content
        guard let baseRange = content.range(of: base) else { return base }

        let suffix = String(content[baseRange.upperBound...].prefix(40))
        guard let equivalentRange = suffix.range(
            of: #"^\s*\(\s*\d+(?:[.,]\d+)?\s*(?:L|l|liter|liters|litre|litres|gal|gallon|gallons|qt|quart|quarts|ml|mL)\s*\)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return base
        }

        let equivalent = String(suffix[equivalentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base) \(equivalent)"
    }

    private func shouldFallbackAgenticPrecisionQuery(error: Error, question: String) -> Bool {
        guard isPrecisionValueQuery(question) else { return false }
        if error is CancellationError { return false }

        if let llmError = error as? LLMError {
            switch llmError {
            case .modelUnavailable, .rateLimited, .concurrentRequests, .generationFailed:
                return true
            default:
                break
            }
        }

        let description = error.localizedDescription.lowercased()
        let indicators = [
            "foundationmodels.languagemodelsession.generationerror",
            "generationerror",
            "apple intelligence",
            "physical device",
            "model unavailable",
            "concurrent request",
            "rate-limited",
            "temporarily rate-limited",
        ]
        return indicators.contains { description.contains($0) }
    }

    /// Detects lookup questions that are really asking for a conceptual explanation,
    /// even when they contain values like “4,096” that might otherwise look extractive.
    private nonisolated func isConceptualLookupQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        let normalized = lower.trimmingCharacters(in: .punctuationCharacters)
        let conceptualOpeners = [
            "what is ", "what are ", "what's ", "how does ", "how do ",
            "why is ", "why does ", "explain ", "tell me about ", "walk me through ",
        ]
        let hasConceptualOpener = conceptualOpeners.contains { normalized.hasPrefix($0) }
        guard hasConceptualOpener else { return false }

        let conceptualMarkers = [
            "token limit", "context window", "private cloud compute", "apple intelligence",
            "foundation model", "hybrid search", "rag pipeline", "retrieval augmented generation",
            "retrieval-augmented generation", "architecture", "workflow", "quality mode",
            "on-device", "on device", "citation", "source card", "file format", "supported format",
            "document import", "sample workspace", "grounded answer", "grounded response", "4,096", "4096",
        ]
        guard conceptualMarkers.contains(where: { normalized.contains($0) }) else { return false }

        let strongValueMarkers = [
            "capacity", "size", "amount", "value", "rating", "weight", "length", "width", "height",
            "volume", "pressure", "temperature", "speed", "torque", "power", "voltage", "current",
            "frequency", "dose", "dosage", "price", "cost", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku",
        ]
        guard !strongValueMarkers.contains(where: { normalized.contains($0) }) else { return false }

        return true
    }

    /// Detects queries that ask for a concrete numeric/measurement value.
    /// This is domain-agnostic and intentionally conservative.
    private nonisolated func isPrecisionValueQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        guard !isConceptualLookupQuery(lower) else { return false }

        let strongNumericIntentMarkers = [
            "how many", "how much", "give me the", "exact", "spec", "specification",
        ]
        let weakNumericIntentMarkers = ["what is", "what's"]
        let strongValueMarkers = [
            "capacity", "size", "amount", "value", "rating", "weight", "length", "width", "height",
            "volume", "pressure", "temperature", "speed", "torque", "power", "voltage", "current", "frequency",
            "dose", "dosage", "price", "cost", "count", "number", "total", "date", "deadline", "fee",
            "part number", "model number", "serial number", "catalog number", "item number", "product code", "sku",
        ]
        let ambiguousValueMarkers = [
            "limit", "range", "setting", "mode", "level", "interval", "threshold",
        ]

        let hasStrongNumericIntent = strongNumericIntentMarkers.contains { lower.contains($0) }
        let hasWeakNumericIntent = weakNumericIntentMarkers.contains { lower.contains($0) }
        let hasStrongValueTarget = strongValueMarkers.contains { lower.contains($0) }
        let hasAmbiguousValueTarget = ambiguousValueMarkers.contains { lower.contains($0) }

        // Unit-like tokens in the question are a strong indicator of precision lookup.
        let unitPattern = #"\b(?:gal(?:lon)?s?|l(?:iter)?s?|ml|kg|g|lb?s?|oz|mm|cm|m|km|mi|mph|km/h|psi|kpa|bar|v|a|w|kw|hz|mhz|ghz|°c|°f|%)\b"#
        let hasUnits = lower.range(of: unitPattern, options: .regularExpression) != nil

        if hasStrongNumericIntent && (hasStrongValueTarget || hasAmbiguousValueTarget || hasUnits) {
            return true
        }

        if hasWeakNumericIntent && (hasStrongValueTarget || hasUnits) {
            return true
        }

        return false
    }

    /// Ensures we only force-lock answers that contain concrete values.
    private nonisolated func hasQuantitativeAnswerSignal(_ text: String) -> Bool {
        EvidenceScoringPolicyService.hasQuantitativeSignal(text)
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

    private func shouldAttemptCorrectiveRetrieval(
        query: String,
        candidates: [RetrievedChunk],
        answerIntentIsExtractive: Bool,
        targetCount: Int
    ) -> Bool {
        if answerIntentIsExtractive {
            return true
        }

        let lexical = checkLexicalRelevance(query: query, chunks: Array(candidates.prefix(5)))
        let topSimilarity = candidates.first?.similarityScore ?? 0
        let minimumCandidateCount = max(3, min(targetCount, 5))

        return candidates.count < minimumCandidateCount
            || lexical < 0.45
            || topSimilarity < 0.52
    }

    private func buildCorrectiveRetrievalQueries(from question: String) -> [String] {
        var seen = Set<String>()
        let orderedTerms = extractQueryTerms(question).filter { seen.insert($0).inserted }

        var queries: [String] = [question]
        if !orderedTerms.isEmpty {
            queries.append(orderedTerms.prefix(4).joined(separator: " "))
        }
        if orderedTerms.count >= 2 {
            queries.append(orderedTerms.prefix(2).joined(separator: " "))
        }
        if orderedTerms.count >= 3 {
            queries.append(Array(orderedTerms.suffix(3)).joined(separator: " "))
        }

        var dedupedSeen = Set<String>()
        return queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && dedupedSeen.insert($0).inserted }
    }

    private nonisolated static func isStateLookupQuery(_ query: String) -> Bool {
        EvidenceScoringPolicyService.isStateLookupQuery(query)
    }

    private nonisolated static func isDefinitionStyleLookupQuery(_ query: String) -> Bool {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        let normalized = lower.trimmingCharacters(in: .punctuationCharacters)
        let definitionPatterns = [
            "what is ", "what are ", "what's ", "define ",
            "definition of ", "meaning of ", "what does ",
        ]
        let hasDefinitionCue = definitionPatterns.contains { normalized.hasPrefix($0) }
            || normalized.contains(" definition of ")
            || normalized.contains(" meaning of ")

        guard hasDefinitionCue else { return false }

        let exactValueSignals = [
            "capacity", "spec", "specification", "torque", "pressure", "temperature", "speed",
            "voltage", "current", "frequency", "power", "weight", "height", "width", "length",
            "dimensions", "size", "setting", "mode", "level", "schedule", "interval", "dose",
            "dosage", "reference number", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku", "recommended", "maximum", "minimum"
        ]
        if exactValueSignals.contains(where: { normalized.contains($0) }) {
            return false
        }

        let numericUnitPattern = #"\b\d+(?:[.,]\d+)?\s*(?:%|mg|g|kg|mcg|ug|ml|l|qt|gal|mm|cm|m|km|in|ft|psi|kpa|bar|v|a|w|kw|hz|mhz|ghz|°c|°f)\b"#
        if normalized.range(of: numericUnitPattern, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private nonisolated func isStandardEquivalentQualityMode(_ qualityMode: RAGQualityMode) -> Bool {
        switch qualityMode {
        case .standard, .balanced, .fast, .thorough:
            return true
        case .deepThink, .agentic, .maximum:
            return false
        }
    }

    private nonisolated func shouldUseContextualDefinitionLookupMode(
        query: String,
        answerIntent: AnswerIntent,
        qualityMode: RAGQualityMode,
        hasSummaryChunks: Bool
    ) -> Bool {
        guard isStandardEquivalentQualityMode(qualityMode) else { return false }
        guard answerIntent == .lookup else { return false }
        guard hasSummaryChunks else { return false }
        if isConceptualLookupQuery(query) { return true }
        guard !isPrecisionValueQuery(query) else { return false }
        return Self.isDefinitionStyleLookupQuery(query)
    }

    private func looksTableLike(text: String, structureType: String?) -> Bool {
        EvidenceScoringPolicyService.isStructuredEvidence(text: text, structureType: structureType)
    }

    private func correctiveRetrievalScore(
        content: String,
        queryTerms: [String],
        structureType: String?,
        baseScore: Float
    ) -> Float {
        EvidenceScoringPolicyService.correctiveRetrievalScore(
            content: content,
            queryTerms: queryTerms,
            structureType: structureType,
            baseScore: baseScore
        )
    }

    private func performCorrectiveRetrieval(
        query: String,
        containerId: UUID,
        allChunks: [DocumentChunk]?,
        existingCandidates: [RetrievedChunk],
        answerIntent: AnswerIntent,
        targetCount: Int
    ) async -> [RetrievedChunk] {
        var seenTerms = Set<String>()
        let queryTerms = extractQueryTerms(query).filter { seenTerms.insert($0).inserted }
        guard !queryTerms.isEmpty else { return [] }

        let queryVariants = buildCorrectiveRetrievalQueries(from: query)
        let useStateAnchorGuard = Self.isStateLookupQuery(query)
        let useStructuredRowRescue = answerIntent.isExtractiveFirst || isPrecisionValueQuery(query)
        let chunkLookup: [String: DocumentChunk] = {
            guard let allChunks else { return [:] }
            var lookup: [String: DocumentChunk] = [:]
            lookup.reserveCapacity(allChunks.count)
            for chunk in allChunks {
                lookup["\(chunk.documentId.uuidString)_\(chunk.metadata.chunkIndex)"] = chunk
            }
            return lookup
        }()

        var seenChunkIds = Set(existingCandidates.map { $0.chunk.id })
        var seenPageKeys = Set(existingCandidates.compactMap { candidate -> String? in
            guard let pageNumber = candidate.pageNumber else { return nil }
            return "\(candidate.chunk.documentId.uuidString)_page_\(pageNumber)"
        })
        var scoredHits: [(chunk: RetrievedChunk, score: Float, structured: Bool)] = []

        for variant in queryVariants {
            let chunkHits = await SQLiteFullTextService.shared.searchChunks(
                query: variant,
                containerId: containerId,
                limit: max(6, targetCount * 2)
            )

            for hit in chunkHits {
                let lookupKey = "\(hit.documentId.uuidString)_\(hit.chunkIndex)"
                guard let docChunk = chunkLookup[lookupKey], !seenChunkIds.contains(docChunk.id) else { continue }

                var score = correctiveRetrievalScore(
                    content: docChunk.content,
                    queryTerms: queryTerms,
                    structureType: docChunk.metadata.structureType,
                    baseScore: 0.50
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: docChunk.content,
                        structureType: docChunk.metadata.structureType
                    )
                }
                guard score >= 0.48 else { continue }

                let docName = await documentName(for: docChunk.documentId)
                let retrieved = RetrievedChunk(
                    chunk: docChunk,
                    similarityScore: score,
                    rank: scoredHits.count,
                    sourceDocument: docName,
                    pageNumber: docChunk.metadata.pageNumber
                )
                scoredHits.append((
                    chunk: retrieved,
                    score: score,
                    structured: looksTableLike(text: docChunk.content, structureType: docChunk.metadata.structureType)
                ))
                seenChunkIds.insert(docChunk.id)
            }

            let pageHits = await SQLiteFullTextService.shared.searchPages(
                query: variant,
                containerId: containerId,
                limit: max(4, targetCount)
            )

            for hit in pageHits {
                let pageKey = "\(hit.documentId.uuidString)_page_\(hit.pageNumber)"
                guard seenPageKeys.insert(pageKey).inserted else { continue }

                let snippet = extractSnippet(
                    from: hit.content,
                    queryTerms: queryTerms,
                    maxChars: 1200
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !snippet.isEmpty else { continue }

                let structureType = looksTableLike(text: hit.content, structureType: nil) ? "table" : nil
                var score = correctiveRetrievalScore(
                    content: snippet,
                    queryTerms: queryTerms,
                    structureType: structureType,
                    baseScore: 0.56
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: snippet,
                        structureType: structureType
                    )
                }
                guard score >= 0.50 else { continue }

                let syntheticChunk = DocumentChunk(
                    documentId: hit.documentId,
                    content: snippet,
                    parentContent: nil,
                    contextualPrefix: nil,
                    embedding: [],
                    metadata: ChunkMetadata(
                        chunkIndex: max(0, hit.pageNumber * 1000),
                        pageNumber: hit.pageNumber,
                        keywords: queryTerms,
                        hasNumericData: snippet.rangeOfCharacter(from: .decimalDigits) != nil,
                        wordCount: wordCount(of: snippet),
                        characterCount: snippet.count,
                        structureType: structureType
                    )
                )

                let docName = await documentName(for: hit.documentId)
                let retrieved = RetrievedChunk(
                    chunk: syntheticChunk,
                    similarityScore: score,
                    rank: scoredHits.count,
                    sourceDocument: docName,
                    pageNumber: hit.pageNumber
                )
                scoredHits.append((
                    chunk: retrieved,
                    score: score,
                    structured: structureType == "table"
                ))
            }
        }

        if useStructuredRowRescue {
            let rowHits = await SQLiteFullTextService.shared.searchStructuredRows(
                query: query,
                containerId: containerId,
                limit: max(6, targetCount * 2)
            )

            for hit in rowHits {
                if useStateAnchorGuard,
                   !EvidenceScoringPolicyService.satisfiesStateLookupAnchors(query: query, content: hit.content)
                {
                    continue
                }

                let lookupKey = "\(hit.documentId.uuidString)_\(hit.chunkIndex)"
                let contentForScore = hit.content.isEmpty ? (chunkLookup[lookupKey]?.content ?? "") : hit.content
                var score = correctiveRetrievalScore(
                    content: contentForScore,
                    queryTerms: queryTerms,
                    structureType: "table",
                    baseScore: 0.64
                )
                if useStateAnchorGuard {
                    score += EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                        query: query,
                        content: contentForScore,
                        structureType: "table"
                    )
                }
                guard score >= 0.56 else { continue }

                let docName = await documentName(for: hit.documentId)

                if let docChunk = chunkLookup[lookupKey] {
                    guard !seenChunkIds.contains(docChunk.id) else { continue }

                    let retrieved = RetrievedChunk(
                        chunk: docChunk,
                        similarityScore: score,
                        rank: scoredHits.count,
                        sourceDocument: docName,
                        pageNumber: docChunk.metadata.pageNumber
                    )
                    scoredHits.append((chunk: retrieved, score: score, structured: true))
                    seenChunkIds.insert(docChunk.id)
                } else {
                    let syntheticChunk = DocumentChunk(
                        documentId: hit.documentId,
                        content: hit.content,
                        parentContent: nil,
                        contextualPrefix: nil,
                        embedding: [],
                        metadata: ChunkMetadata(
                            chunkIndex: hit.chunkIndex,
                            pageNumber: hit.pageNumber,
                            keywords: queryTerms,
                            hasNumericData: hit.content.rangeOfCharacter(from: .decimalDigits) != nil,
                            wordCount: wordCount(of: hit.content),
                            characterCount: hit.content.count,
                            structureType: "table"
                        )
                    )

                    let retrieved = RetrievedChunk(
                        chunk: syntheticChunk,
                        similarityScore: score,
                        rank: scoredHits.count,
                        sourceDocument: docName,
                        pageNumber: hit.pageNumber
                    )
                    scoredHits.append((chunk: retrieved, score: score, structured: true))
                }
            }
        }

        scoredHits.sort {
            if abs($0.score - $1.score) < 0.01 {
                return $0.structured && !$1.structured
            }
            return $0.score > $1.score
        }

        let limited = scoredHits.prefix(max(targetCount, 6))
        return limited.enumerated().map { index, entry in
            RetrievedChunk(
                chunk: entry.chunk.chunk,
                similarityScore: entry.score,
                rank: index,
                sourceDocument: entry.chunk.sourceDocument,
                pageNumber: entry.chunk.pageNumber
            )
        }
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
    case maximumModeQuotaReached(limit: Int)
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
        case let .maximumModeQuotaReached(limit):
            return "Maximum mode is limited to \(limit) uses per day on the free tier"
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
        let container = await containerForId(embeddingContext.containerId)
        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuery.text)

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
    /// - Parameter qualityMode: Controls retrieval parameters (mmrLambda, parent doc, etc.)
    /// - Parameter onDetailedEvent: Optional callback for verbose thinking events (for Deep Think/Maximum)
    func executeFullRetrievalPipeline(
        query: String,
        topK: Int = 20,
        minSimilarity: Float? = nil,
        qualityMode: RAGQualityMode? = nil,
        onDetailedEvent: DetailedThinkingCallback? = nil
    ) async throws -> [RetrievedChunk] {
        // Resolve quality mode from parameter or settings
        let mode: RAGQualityMode
        if let explicit = qualityMode {
            mode = explicit
        } else {
            mode = await MainActor.run { self.settingsStore?.ragQualityMode ?? .standard }
        }
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let resolvedRetrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig ?? .default
        }
        let effectiveMinSimilarity = minSimilarity ?? resolvedRetrievalConfig.minSimilarity
        let db = await dbFor(embeddingContext.containerId)
        let allChunks = try await db.allChunks()

        // Skip if no chunks
        guard !allChunks.isEmpty else { return [] }

        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let semanticQuery = translatedQuery.text
        let originalKeywordQuery = translatedQuery.wasTranslated ? query : semanticQuery

        // Emit: Starting retrieval pipeline
        await onDetailedEvent?(.planning, "Query analysis", "Analyzing: \"\(query.prefix(50))...\"")

        // RAPTOR-lite: Query routing for summary-first retrieval
        // Only filter chunks if query routing is enabled AND we have summaries
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: semanticQuery,
            queryRouter: queryRouter,
            routingEnabled: queryRoutingEnabled
        )
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = queryProfile.routingClassification
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                // For overview queries in agentic mode, use summaries first
                let searchLevels = queryProfile.abstractionLevelsToSearch
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info("[RAPTOR-lite] Agentic retrieval using \(effectiveChunks.count) summary chunks for overview query", category: .retrieval)
                await onDetailedEvent?(.retrieval, "RAPTOR-lite routing", "Using \(effectiveChunks.count) summary chunks")
            }
        }

        // Step 1: Use the semantic retrieval query for embedding
        // NOTE: HyDE disabled in Deep Think - it hallucinates without document context
        // and poisons retrieval with irrelevant content (e.g., "serial numbers" for "button" queries)
        let textToEmbed = semanticQuery

        // Step 2: Generate query embedding
        await onDetailedEvent?(.embedding, "Encoding query", "384-dim neural embedding")
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: textToEmbed)
        await onDetailedEvent?(.vectorSearch, "Vector ready", "Query encoded for semantic search")

        // Step 3: Classify query intent for adaptive weights AND expand query
        // Fetch corpus vocabulary from cache (built during Standard mode or prior queries)
        let cachedVocab: CorpusVocabulary? = await MainActor.run {
            self.corpusVocabularyCache[embeddingContext.containerId]
        }
        // If not cached yet, build it now from available chunks (ensures DT/Max gets corpus-aware expansion)
        let agenticVocab: CorpusVocabulary?
        if let cached = cachedVocab {
            agenticVocab = cached
        } else if !allChunks.isEmpty {
            let built = CorpusVocabulary.build(from: allChunks)
            await MainActor.run { self.corpusVocabularyCache[embeddingContext.containerId] = built }
            agenticVocab = built
        } else {
            agenticVocab = nil
        }

        let queryEnhancer = QueryEnhancementService(corpusVocabulary: agenticVocab)
        let queryIntent = queryProfile.searchIntent
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: resolvedRetrievalConfig)
        let vectorWeight = adjustedWeights.vectorWeight
        let keywordWeight = adjustedWeights.keywordWeight

        // Emit: Query expansion
        await onDetailedEvent?(.queryRewrite, "Query expansion", "Intent: \(queryIntent.rawValue) → Vector \(Int(vectorWeight * 100))% / Keyword \(Int(keywordWeight * 100))%")

        // EXPAND query with synonyms for better keyword matching
        // e.g., "button" → "button switch toggle control key trigger"
        var expandedQueries = queryEnhancer.expandQuery(semanticQuery)

        // Gazetteer domain vocabulary enrichment
        let gazetteerMatchesFR = await GazetteerService.shared.matchingTerms(for: semanticQuery)
        if !gazetteerMatchesFR.isEmpty {
            let uniqueGazetteer = gazetteerMatchesFR.map { $0.term }.filter { !expandedQueries.contains($0) }
            expandedQueries.append(contentsOf: uniqueGazetteer.prefix(5))
            if !uniqueGazetteer.isEmpty {
                Log.debug("[FullRetrieval] Gazetteer added \(min(uniqueGazetteer.count, 5)) domain terms", category: .retrieval)
            }
        }

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
            originalQuery: originalKeywordQuery,
            embedding: queryEmbedding,
            topK: topK * 2, // Get extra for re-ranking
            cachedChunks: effectiveChunks, // Use RAPTOR-lite filtered chunks
            containerId: embeddingContext.containerId // Enable SQLite FTS5 acceleration
        )

        await onDetailedEvent?(.rrf, "RRF fusion", "\(retrievedChunks.count) candidates from hybrid search")

        // Step 5: AI Re-ranking with ReRanker model
        await onDetailedEvent?(.rerank, "AI re-ranking", "Scoring \(retrievedChunks.count) chunks with neural model")

        let engine = RAGEngine.shared
        retrievedChunks = await engine.rerank(chunks: retrievedChunks, query: semanticQuery, topK: topK * 2)

        await onDetailedEvent?(.rerank, "Re-ranking complete", "Top scores: \(retrievedChunks.prefix(3).map { String(format: "%.0f%%", $0.similarityScore * 100) }.joined(separator: ", "))")

        // Step 6: MMR Diversification (uses quality mode lambda)
        let mmrLambda: Float = resolvedRetrievalConfig.mmrLambda
        await onDetailedEvent?(.mmr, "MMR diversification", "Optimizing for coverage (λ=\(String(format: "%.2f", mmrLambda)))")
        retrievedChunks = await engine.applyMMR(
            candidates: retrievedChunks,
            queryEmbedding: queryEmbedding,
            topK: topK,
            lambda: mmrLambda
        )

        await onDetailedEvent?(.mmr, "Diversity optimized", "\(retrievedChunks.count) chunks after MMR")

        // Step 7: Filter by similarity
        let preFilterCount = retrievedChunks.count
        retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: effectiveMinSimilarity)

        if preFilterCount > retrievedChunks.count {
            await onDetailedEvent?(.context, "Quality filter", "Kept \(retrievedChunks.count)/\(preFilterCount) (≥\(Int(effectiveMinSimilarity * 100))% threshold)")
        }

        // Precision/spec lookups need the same rescue path in Deep Think that
        // Standard mode uses. Rerankers often prefer prose around a spec table
        // over the actual row containing the value.
        let fullPipelineAnswerIntent = queryProfile.answerIntent
        if fullPipelineAnswerIntent.isExtractiveFirst || isPrecisionValueQuery(query) {
            let existingIds = Set(retrievedChunks.map { $0.chunk.id })
            let sniperResults = specTableSniper(
                query: query,
                allChunks: allChunks,
                excludeIds: existingIds
            )
            if !sniperResults.isEmpty {
                retrievedChunks.insert(contentsOf: sniperResults, at: 0)
                demoteCrossReferenceChunks(&retrievedChunks)
                await onDetailedEvent?(.retrieval, "Spec sniper", "+\(sniperResults.count) targeted chunks via keyword+number co-occurrence")
                Log.info("[FullRetrieval] Spec sniper added \(sniperResults.count) targeted chunks", category: .retrieval)
            }
        }

        // Step 7.5: Parent Document Retrieval (expand with sibling chunks for context)
        if mode.usesParentDocumentRetrieval && !retrievedChunks.isEmpty {
            let maxSiblings = mode.maxSiblingChunks
            await onDetailedEvent?(.parentDoc, "Parent doc retrieval", "Expanding with ±\(maxSiblings) sibling chunks")

            var expandedChunks: [RetrievedChunk] = []
            var seenChunkIds = Set<UUID>()

            for chunk in retrievedChunks {
                // Add the original chunk
                if seenChunkIds.insert(chunk.chunk.id).inserted {
                    expandedChunks.append(chunk)
                }

                // Find sibling chunks from the same document
                let siblings = allChunks.filter { candidate in
                    candidate.documentId == chunk.chunk.documentId &&
                    candidate.id != chunk.chunk.id &&
                    abs(candidate.metadata.chunkIndex - chunk.chunk.metadata.chunkIndex) <= maxSiblings
                }.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }

                for sibling in siblings {
                    if seenChunkIds.insert(sibling.id).inserted {
                        // Siblings get a discounted score
                        expandedChunks.append(RetrievedChunk(
                            chunk: sibling,
                            similarityScore: chunk.similarityScore * 0.85,
                            rank: expandedChunks.count + 1,
                            sourceDocument: chunk.sourceDocument,
                            pageNumber: sibling.metadata.pageNumber
                        ))
                    }
                }
            }

            if expandedChunks.count > retrievedChunks.count {
                await onDetailedEvent?(.parentDoc, "Context expanded", "\(retrievedChunks.count) → \(expandedChunks.count) chunks with siblings")
                retrievedChunks = expandedChunks
            }
        }

        // Step 8: Lost-in-Middle reorder (place best chunks at start and end)
        if retrievedChunks.count >= 4 {
            var reordered: [RetrievedChunk] = []
            let sorted = retrievedChunks.sorted { $0.similarityScore > $1.similarityScore }
            for (index, chunk) in sorted.enumerated() {
                if index % 2 == 0 {
                    reordered.append(chunk) // Even indices go to front
                } else {
                    reordered.insert(chunk, at: reordered.count / 2) // Odd go to middle
                }
            }
            retrievedChunks = reordered
            await onDetailedEvent?(.lostInMiddle, "Lost-in-Middle reorder", "Best evidence at start/end of context")
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
    func searchDocumentsRaw(query: String, topK: Int = 10, minSimilarity: Float? = nil) async throws -> [RetrievedChunk] {
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuery.text)

        let db = await dbFor(embeddingContext.containerId)
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: translatedQuery.text,
            queryRouter: queryRouter,
            routingEnabled: queryRoutingEnabled
        )
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig ?? .default
        }
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        // Use hybrid search (vector + BM25) for better keyword matching on technical terms
        // Critical for technical docs where exact terms like codes and specs matter
        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let allChunks = try await db.allChunks()

        // RAPTOR-lite: Query routing for summary-first retrieval
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = queryProfile.routingClassification
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                let searchLevels = queryProfile.abstractionLevelsToSearch
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info("[RAPTOR-lite] Raw search using \(effectiveChunks.count) summary chunks", category: .retrieval)
            }
        }

        // Request more candidates for better coverage
        let effectiveTopK = max(topK, 15)
        var retrievedChunks = try await hybridSearch.search(
            query: translatedQuery.text,
            originalQuery: translatedQuery.wasTranslated ? query : translatedQuery.text,
            embedding: queryEmbedding,
            topK: effectiveTopK,
            cachedChunks: effectiveChunks,
            containerId: embeddingContext.containerId // Enable SQLite FTS5 acceleration
        )

        let engine = RAGEngine.shared
        retrievedChunks = await engine.filterBySimilarity(
            chunks: retrievedChunks,
            min: minSimilarity ?? retrievalConfig.minSimilarity
        )

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

        let k = max(1, topK ?? 3)
        let retrievedChunks = try await searchDocumentsRaw(
            query: query,
            topK: k,
            minSimilarity: minSimilarity
        )

        // Edge case: No results
        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Step 4: Format retrieved chunks for LLM consumption (citations + preview)
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"
        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = retrieved.sourceDocument
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
    /// Token-budget aware: max ~600 chars output (15 docs × ~40 chars each)
    func countPatternInCorpus(pattern: String) async throws -> String {
        Log.debug("🔧 [Tool Call] count_pattern_in_corpus(pattern: \"\(pattern)\")")

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
            // Legacy path: File-based storage — scope to active container's documents
            let containerDocs = await MainActor.run {
                documents.filter { doc in
                    if let cid = doc.containerId { return cid == activeId }
                    return activeId == containerService.containers.first?.id
                }
            }
            let docIds = containerDocs.map { $0.id }
            counts = await FullTextStorageService.shared.countPatternInCorpus(pattern: pattern, documentIds: docIds)
            Log.debug("[RAGService] Using legacy file storage for pattern count (scoped to \(docIds.count) docs)", category: .retrieval)
        }

        if counts.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        let totalOccurrences = counts.values.reduce(0, +)

        // Compact format for token budget
        var result = "**'\(pattern)':** \(totalOccurrences) total in \(counts.count) docs\n"

        // Sort by count descending, limit to 15 for token budget (~600 chars max)
        let sortedCounts = counts.sorted { $0.value > $1.value }
        let maxDocs = 15

        for (docId, count) in sortedCounts.prefix(maxDocs) {
            let docName = await documentName(for: docId)
            // Truncate long names
            let truncName = docName.count > 35 ? String(docName.prefix(32)) + "..." : docName
            result += "- \(truncName): \(count)\n"
        }

        if sortedCounts.count > maxDocs {
            result += "... +\(sortedCounts.count - maxDocs) more\n"
        }

        Log.info("🔧 [Tool Call] Pattern '\(pattern)' found \(totalOccurrences) times in \(counts.count) docs")
        return result
    }

    /// Search for exact text pattern across ALL documents
    /// Returns documents containing the pattern with context
    /// FTS5 path is 10-100X faster with native snippet() support
    /// Token-budget aware: max ~800 chars (8 matches × ~100 chars each)
    func searchExactPattern(pattern: String) async throws -> String {
        Log.debug("🔧 [Tool Call] search_exact_pattern(pattern: \"\(pattern)\")")

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
                contextChars: 300
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
            // Legacy path: File-based storage — scope to active container's documents
            let containerDocs = await MainActor.run {
                documents.filter { doc in
                    if let cid = doc.containerId { return cid == activeId }
                    return activeId == containerService.containers.first?.id
                }
            }
            let docIds = containerDocs.map { $0.id }
            matches = await FullTextStorageService.shared.searchCorpus(pattern: pattern, documentIds: docIds, maxResults: 10)
            Log.debug("[RAGService] Using legacy file storage for exact search (scoped to \(docIds.count) docs)", category: .retrieval)
        }

        if matches.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        // Context budget: enough to show actual values, not just cross-references
        // 200 chars per snippet ensures spec table values are visible
        let maxMatches = 8
        let maxSnippetChars = 200

        var result = "**'\(pattern)'** in \(matches.count) docs:\n"

        for match in matches.prefix(maxMatches) {
            let docName = await documentName(for: match.documentId)
            let truncName = docName.count > 30 ? String(docName.prefix(27)) + "..." : docName
            let truncSnippet = match.contextSnippet.count > maxSnippetChars
                ? String(match.contextSnippet.prefix(maxSnippetChars)) + "..."
                : match.contextSnippet
            result += "**\(truncName)** (\(match.occurrences)x): \"\(truncSnippet)\"\n"
        }

        if matches.count > maxMatches {
            result += "... +\(matches.count - maxMatches) more\n"
        }

        Log.info("🔧 [Tool Call] Pattern '\(pattern)' found in \(matches.count) docs with context")
        return result
    }

    /// Get corpus-wide statistics
    /// Token-budget aware: returns compact stats (~200-400 chars)
    func getCorpusStats() async throws -> String {
        Log.debug("🔧 [Tool Call] get_corpus_stats()")

        let activeId = await MainActor.run { self.containerService.activeContainerId }
        let docs = await MainActor.run { self.documents }

        guard !docs.isEmpty else {
            return "No documents in the current container."
        }

        // Calculate statistics
        let totalDocs = docs.count
        let totalPages = docs.reduce(0) { $0 + ($1.processingMetadata?.pagesProcessed ?? 1) }
        let totalChunks = docs.reduce(0) { $0 + $1.totalChunks }

        // Document type breakdown (top 5 only to save tokens)
        var typeBreakdown: [String: Int] = [:]
        for doc in docs {
            let ext = doc.contentType.rawValue.uppercased()
            typeBreakdown[ext, default: 0] += 1
        }

        // FTS5 stats
        let fts5DocCount = await SQLiteFullTextService.shared.documentCount(for: activeId)
        let fts5TotalChars = await SQLiteFullTextService.shared.totalCharacterCount(for: activeId)

        // Compact format to respect 4096 token budget
        var result = "📊 **Corpus:** \(totalDocs) docs, \(totalPages) pages, \(totalChunks) chunks\n"
        result += "**FTS5:** \(fts5DocCount) indexed (\(formatByteCount(fts5TotalChars)))\n"
        result += "**Types:** "
        result += typeBreakdown.sorted(by: { $0.value > $1.value })
            .prefix(5)
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ", ")

        Log.info("🔧 [Tool Call] Corpus stats: \(totalDocs) docs, \(totalPages) pages")
        return result
    }

    /// Find documents semantically related to a topic
    /// Token-budget aware: returns compact list (~50 chars per doc, max 10 docs = ~500 chars)
    func findRelatedDocuments(topic: String, maxResults: Int) async throws -> String {
        Log.debug("🔧 [Tool Call] find_related_documents(topic: \"\(topic)\", max: \(maxResults))")

        // Clamp maxResults to avoid token overflow (10 docs × ~50 chars = ~500 chars)
        let safeMaxResults = min(maxResults, 10)

        // Get semantic search results using HybridSearchService
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedTopic = await translatedQueryForEmbedding(topic, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedTopic.text)
        let db = await dbFor(embeddingContext.containerId)
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig ?? .default
        }
        let queryProfile = await QueryProfileService.shared.buildProfile(for: translatedTopic.text, routingEnabled: false)
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let results = try await hybridSearch.search(
            query: translatedTopic.text,
            originalQuery: translatedTopic.wasTranslated ? topic : translatedTopic.text,
            embedding: queryEmbedding,
            topK: safeMaxResults * 3,
            cachedChunks: nil as [DocumentChunk]?,
            containerId: embeddingContext.containerId
        )

        if results.isEmpty {
            return "No documents found related to '\(topic)'."
        }

        // Group by document and score by average relevance
        var docScores: [UUID: (name: String, avgScore: Float, chunkCount: Int)] = [:]

        for result in results {
            let docId = result.chunk.documentId
            let docName = await documentName(for: docId)

            if var existing = docScores[docId] {
                existing.avgScore = (existing.avgScore * Float(existing.chunkCount) + result.similarityScore) / Float(existing.chunkCount + 1)
                existing.chunkCount += 1
                docScores[docId] = existing
            } else {
                docScores[docId] = (name: docName, avgScore: result.similarityScore, chunkCount: 1)
            }
        }

        // Sort by score, limit to safe max
        let sortedDocs = docScores.sorted { $0.value.avgScore > $1.value.avgScore }
            .prefix(safeMaxResults)

        // Compact format
        var result = "**Related to '\(topic)':** \(sortedDocs.count) docs\n"

        for (index, (_, info)) in sortedDocs.enumerated() {
            let relevance = String(format: "%.0f%%", info.avgScore * 100)
            // Truncate long names to 40 chars
            let truncatedName = info.name.count > 40 ? String(info.name.prefix(37)) + "..." : info.name
            result += "\(index + 1). \(truncatedName) (\(relevance))\n"
        }

        Log.info("🔧 [Tool Call] Found \(sortedDocs.count) documents related to '\(topic)'")
        return result
    }

    /// Compare how multiple documents discuss a topic
    /// Token-budget aware: max 1500 chars total (~600 tokens) to leave room for synthesis
    func compareDocumentsOnTopic(topic: String, documentNames: [String]?) async throws -> String {
        Log.debug("🔧 [Tool Call] compare_documents(topic: \"\(topic)\")")

        // Token budget: ~1500 chars max for comparison output
        let maxTotalChars = 1500
        let maxSnippetChars = 200  // Per snippet
        let maxDocsToCompare = 5   // Max documents
        let maxSnippetsPerDoc = 2  // Max snippets per doc

        // Search for the topic using HybridSearchService
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedTopic = await translatedQueryForEmbedding(topic, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedTopic.text)
        let db = await dbFor(embeddingContext.containerId)
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig ?? .default
        }
        let queryProfile = await QueryProfileService.shared.buildProfile(for: translatedTopic.text, routingEnabled: false)
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let results = try await hybridSearch.search(
            query: translatedTopic.text,
            originalQuery: translatedTopic.wasTranslated ? topic : translatedTopic.text,
            embedding: queryEmbedding,
            topK: 20,
            cachedChunks: nil as [DocumentChunk]?,
            containerId: embeddingContext.containerId
        )

        if results.isEmpty {
            return "No content found about '\(topic)' in the document library."
        }

        // Filter by specific documents if provided
        let filteredResults: [RetrievedChunk]
        if let names = documentNames, !names.isEmpty {
            let lowercaseNames = Set(names.map { $0.lowercased() })
            filteredResults = await results.asyncFilter { result in
                let docName = await self.documentName(for: result.chunk.documentId)
                return lowercaseNames.contains(docName.lowercased())
            }
        } else {
            filteredResults = results
        }

        if filteredResults.isEmpty {
            return "Specified documents don't contain content about '\(topic)'."
        }

        // Group by document
        var docContent: [String: [String]] = [:]

        for result in filteredResults.prefix(15) {
            let docName = await documentName(for: result.chunk.documentId)
            let content = result.chunk.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // Strict snippet limit
            let snippet = content.count > maxSnippetChars ? String(content.prefix(maxSnippetChars)) + "..." : content

            if (docContent[docName]?.count ?? 0) < maxSnippetsPerDoc {
                docContent[docName, default: []].append(snippet)
            }
        }

        // Build result with char budget tracking
        var result = "**Compare '\(topic)':**\n"
        var currentChars = result.count

        for (docName, snippets) in docContent.sorted(by: { $0.key < $1.key }).prefix(maxDocsToCompare) {
            let truncatedName = docName.count > 30 ? String(docName.prefix(27)) + "..." : docName
            let header = "**\(truncatedName):** "

            if currentChars + header.count > maxTotalChars { break }
            result += header
            currentChars += header.count

            for snippet in snippets.prefix(maxSnippetsPerDoc) {
                let quotedSnippet = "\"\(snippet)\" "
                if currentChars + quotedSnippet.count > maxTotalChars { break }
                result += quotedSnippet
                currentChars += quotedSnippet.count
            }
            result += "\n"
        }

        Log.info("🔧 [Tool Call] Compared '\(topic)' across \(docContent.count) documents (\(result.count) chars)")
        return result
    }

    private func formatByteCount(_ chars: Int) -> String {
        if chars < 1000 {
            return "\(chars) chars"
        } else if chars < 1_000_000 {
            return String(format: "%.1fK chars", Float(chars) / 1000)
        } else {
            return String(format: "%.1fM chars", Float(chars) / 1_000_000)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
