//
//  RAGService+ChatHistory.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Chat History

    /// Returns chat history scoped to a specific container, loading from disk if needed.
    @MainActor
    func chatHistory(for containerId: UUID?) -> [ChatMessage] {
        let resolvedId = containerId ?? containerService.activeContainerId
        if let cached = chatHistories[resolvedId] {
            if let threadId = activeThreadIds[resolvedId] {
                activeThreadId = threadId
            }
            return cached
        }

        do {
            let threads = try threadStore.listThreads(containerId: resolvedId)
            if let mostRecent = threads.first {
                activeThreadId = mostRecent.id
                activeThreadIds[resolvedId] = mostRecent.id
                let loaded = mostRecent.messages.map { $0.sanitizedForPersistence() }
                chatHistories[resolvedId] = loaded
                return loaded
            }
        } catch {
            Log.error("[RAGService] Failed to load threads: \(error.localizedDescription)", category: .initialization)
        }

        chatHistories[resolvedId] = []
        return []
    }

    /// Preloads chat history without blocking the main actor on disk IO or JSON decoding.
    func preloadChatHistory(for containerId: UUID?) async -> [ChatMessage] {
        let resolvedId = containerId ?? self.containerService.activeContainerId

        if let cached = self.chatHistories[resolvedId] {
            if let threadId = self.activeThreadIds[resolvedId] {
                self.activeThreadId = threadId
            }
            return cached
        }

        do {
            let threads = try self.threadStore.listThreads(containerId: resolvedId)
            if let mostRecent = threads.first {
                self.activeThreadId = mostRecent.id
                self.activeThreadIds[resolvedId] = mostRecent.id
                let loaded = mostRecent.messages.map { $0.sanitizedForPersistence() }
                self.chatHistories[resolvedId] = loaded
                return loaded
            }
        } catch {
            Log.error(
                "[RAGService] Failed to load threads for container \(resolvedId): \(error.localizedDescription)",
                category: .initialization)
        }
        return []
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
        let trimmedMessages =
            messages.count > Self.maxMessagesPerContainer
            ? Array(messages.suffix(Self.maxMessagesPerContainer))
            : messages
        chatHistories[resolvedId] = trimmedMessages

        let threadIdToSave = activeThreadId ?? UUID()
        activeThreadId = threadIdToSave
        activeThreadIds[resolvedId] = threadIdToSave

        let firstUserMessage = trimmedMessages.first { $0.role == .user }?.content ?? "New Thread"
        let title = String(firstUserMessage.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)

        let thread = EvidenceThread(
            id: threadIdToSave,
            containerId: resolvedId,
            title: title,
            createdAt: Date(),
            updatedAt: Date(),
            messages: trimmedMessages.map { $0.sanitizedForPersistence() },
            metadata: [:]
        )

        do {
            try threadStore.saveThread(thread)
        } catch {
            Log.error(
                "[RAGService] Failed to save thread for container \(resolvedId): \(error.localizedDescription)",
                category: .initialization)
        }
    }

    /// Clears chat history for a container both in memory and on disk.
    @MainActor
    func clearChatHistory(for containerId: UUID?) {
        let resolvedId = containerId ?? containerService.activeContainerId
        chatHistories[resolvedId] = []
        activeThreadIds[resolvedId] = nil

        if let currentThread = activeThreadId {
            do {
                try threadStore.deleteThread(id: currentThread, containerId: resolvedId)
                Log.debug("[RAGService] Deleted thread \(currentThread)", category: .initialization)
            } catch {
                Log.error(
                    "[RAGService] Failed to delete thread: \(error.localizedDescription)", category: .initialization)
            }
            activeThreadId = nil
        }

        // Reset Deep Think / Maximum mode live metrics to avoid stale UI
        resetDeepThinkLiveMetrics()

        // Also clear the persisted transcript and conversation memory when clearing chat history
        if #available(iOS 26.0, *) {
            TranscriptPersistenceService.shared.deleteTranscript(for: resolvedId)
            ConversationMemoryService.shared.clearMemory(for: resolvedId)
            Log.debug(
                "[RAGService] Cleared chat history, transcript, memory, and live metrics for container \(resolvedId)",
                category: .initialization)
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

    /// Ends the checks that run after an answer's text is complete, and keeps the answer.
    ///
    /// The chat screen calls this when the person stops, or sends the next question, while the
    /// last answer is still being checked. Cancelling the query instead would discard the finished
    /// answer's sources and metadata, because the response that carries them is built only once
    /// the checks return. This lets the pipeline return that response now, unrefined.
    ///
    /// The source-only check is the stage that listens, and it was the whole of the wait: on
    /// 2026-09-23, four Standard lookup questions on the macOS Debug build finished 19.4, 37.6,
    /// 58.3 and 163.8 seconds after their last streamed word, nearly all of it in that check, and
    /// the check changed none of the four answers. A question that skips it finished 0.12 seconds
    /// after its last word.
    @MainActor
    func finishAnswerNow() {
        finishAnswerNowRequested = true
        activeSourceOnlyCheck?.cancel()
        cancelFinishableStage?()
    }




    /// Runs a stage that can only improve an answer whose text already exists, so that
    /// `finishAnswerNow()` can end it and the caller keeps what it has.
    ///
    /// Deep Think's recursive research and verification loop, and Maximum's refinement, run after
    /// the final synthesis has streamed, and each can take minutes. Answers nil when the person
    /// asked to finish before the stage started or while it ran; every caller already treats nil as
    /// "nothing better found" and keeps its answer. Cancelling the query itself still reaches the
    /// stage through the cancellation handler, as it would a direct call, and still throws.
    @MainActor
    func runFinishableStage<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T? {
        guard !finishAnswerNowRequested else { return nil }
        // Nothing a stage generates may stream: the answer it can replace is already on screen, and
        // the chat appends what it is sent.
        let stage = Task { @MainActor in
            try await LLMStreamingContext.$finalAnswerHandler.withValue(nil) {
                try await LLMStreamingContext.$handler.withValue(nil) {
                    try await operation()
                }
            }
        }
        let enclosing = cancelFinishableStage
        cancelFinishableStage = {
            enclosing?()
            stage.cancel()
        }
        defer { cancelFinishableStage = enclosing }
        do {
            let value = try await withTaskCancellationHandler {
                try await stage.value
            } onCancel: {
                stage.cancel()
            }
            return finishAnswerNowRequested ? nil : value
        } catch {
            if finishAnswerNowRequested { return nil }
            throw error
        }
    }

    // MARK: - Evidence Threads Additions

    @MainActor
    func loadThread(_ threadId: UUID, for containerId: UUID) -> [ChatMessage] {
        do {
            let thread = try threadStore.getThread(id: threadId, containerId: containerId)
            activeThreadId = thread.id
            activeThreadIds[containerId] = thread.id
            let loaded = thread.messages.map { $0.sanitizedForPersistence() }
            chatHistories[containerId] = loaded
            return loaded
        } catch {
            Log.error(
                "[RAGService] Failed to load thread \(threadId): \(error.localizedDescription)",
                category: .initialization)
            return []
        }
    }

    func listThreads(for containerId: UUID) -> [EvidenceThread] {
        return (try? threadStore.listThreads(containerId: containerId)) ?? []
    }

    @MainActor
    func createNewThread(for containerId: UUID) throws {
        // An engine built by an action while the app is closed has no entitlement store. The plan is
        // kept in UserDefaults, so read it from there instead of treating a paying person as free.
        let tier = entitlementStore?.effectiveTier ?? EntitlementStore.currentEffectiveTier()
        let limit = QuotaPolicy.evidenceThreadLimit(for: tier)
        let currentCount = listThreads(for: containerId).count

        if currentCount >= limit {
            throw EvidenceThreadQuotaError(limit: limit, tier: tier)
        }

        let newId = UUID()
        activeThreadId = newId
        activeThreadIds[containerId] = newId
        chatHistories[containerId] = []
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

    /// The query cache's key (5.7): the normalized question, then a digest of every library's
    /// documents with their passage counts, of the embedding model and of the app's version, so an
    /// import, a deletion, a re-import, a new model or an update gives a question a fresh search.
    /// Pure, for `QueryCacheKeyTests`.
    nonisolated static func queryCacheKey(
        _ normalizedQuestion: String, documents: [(id: UUID, passages: Int)], embeddingProviderId: String,
        dimension: Int, appVersion: String = RAGService.appVersionForQueryCache
    ) -> String {
        var digest = SHA256()
        for document in documents.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            digest.update(data: Data("\(document.id.uuidString):\(document.passages)\n".utf8))
        }
        digest.update(data: Data("\(embeddingProviderId):\(dimension)\n\(appVersion)".utf8))
        let hex = digest.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(normalizedQuestion) #libraries \(hex)"
    }

    /// The app's version and build, part of the query cache's key: a search cached by an earlier
    /// version of the app is not reused after an update that changed how searching works.
    nonisolated static let appVersionForQueryCache: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    /// A cached search is used only when every passage in it is from a document still in the
    /// libraries: one that is not would bring a deleted document's text into the answer.
    nonisolated static func cachedResultsAreCurrent(_ results: [RetrievedChunk], documentIds: Set<UUID>) -> Bool {
        !results.isEmpty && results.allSatisfy { documentIds.contains($0.chunk.documentId) }
    }

    /// What every cached search's key holds besides the question and the embedding model: each library's
    /// documents with their passage counts, and the app's version (5.7). While it stays the same a cached
    /// search can be found again; once it changes, none can.
    nonisolated static func queryCacheDocumentsToken(
        _ documents: [(id: UUID, passages: Int)], appVersion: String = RAGService.appVersionForQueryCache
    ) -> String {
        var digest = SHA256()
        for document in documents.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            digest.update(data: Data("\(document.id.uuidString):\(document.passages)\n".utf8))
        }
        digest.update(data: Data(appVersion.utf8))
        return digest.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static let queryCacheTokenKey = "queryCacheDocumentsToken"

    /// Deletes the cached searches once the documents or the app's version have changed since they were
    /// last deleted, and returns how many went, or nil when nothing had changed (5.7). Runs after the
    /// documents are saved and at launch. Through 5.6 nothing deleted a cached search: they kept the
    /// questions and the passages found, a deleted library's text among them, until the app was removed,
    /// and from 5.7 every import, deletion or update left all of them unreachable.
    /// `deleteAll` stands in for the database in tests. It is not a default closure that calls the store:
    /// Swift takes such a closure as the store actor's own, an error in the Swift 6 language mode.
    @discardableResult
    static func deleteUnreachableCachedSearches(
        documents: [(id: UUID, passages: Int)], defaults: UserDefaults = .standard,
        deleteAll: (() async -> Int)? = nil
    ) async -> Int? {
        let token = queryCacheDocumentsToken(documents)
        guard defaults.string(forKey: queryCacheTokenKey) != token else { return nil }
        let deleted: Int
        if let deleteAll {
            deleted = await deleteAll()
        } else {
            deleted = await SQLiteFullTextService.shared.deleteAllCachedQueries()
        }
        defaults.set(token, forKey: queryCacheTokenKey)
        if deleted > 0 {
            Log.info(
                "[RAGService] Deleted \(deleted) cached search(es) that no question can reach any more",
                category: .pipeline)
        }
        return deleted
    }

    /// The passages of a library's store that belong to a listed document (5.7). What the later steps of a question
    /// draw on (the spec sniper, cross-references, parent expansion, lexical recall) is this list, and they add
    /// passages after `passagesFromKnownDocuments` has run: on 2026-10-19 the spec sniper put the overview of a
    /// deleted note into an answer, cited as "Unknown" (`ShortcutsActionTests.testAPassageOfNoDocumentIsNotUsedInAnAnswer`).
    func chunksOfListedDocuments(_ chunks: [DocumentChunk]) async -> [DocumentChunk] {
        let listed = await MainActor.run { Set(self.documents.map(\.id)) }
        // The usual case drops nothing and keeps the store's own array rather than copying every passage
        // (review, 2026-10-19: about 60 MB for a 144,247-passage library).
        guard !chunks.allSatisfy({ listed.contains($0.documentId) }) else { return chunks }
        let kept = chunks.filter { listed.contains($0.documentId) }
        if kept.count < chunks.count {
            Log.warning(
                "[RAGService] \(chunks.count - kept.count) stored passage(s) belong to no listed document and are not used",
                category: .retrieval)
        }
        return kept
    }

    /// Leaves out a passage from the stores whose document is in no library (5.7): its document was deleted,
    /// or an import stopped before recording it, and an answer cited it as "Unknown". A passage the pipeline
    /// made itself, such as a camera or barcode capture, carries its own name and is kept. On 2026-10-15 the
    /// owner's library BDB0BCA5 held 27 such passages and no document.
    nonisolated static func passagesFromKnownDocuments(
        _ passages: [RetrievedChunk], knownDocumentIds: Set<UUID>
    ) -> (kept: [RetrievedChunk], dropped: Int) {
        let kept = passages.filter { passage in
            knownDocumentIds.contains(passage.chunk.documentId)
                || !(passage.sourceDocument.isEmpty || passage.sourceDocument == "Unknown")
        }
        return (kept, passages.count - kept.count)
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
            Log.error(
                "[RAGService] Failed to load chat history for container \(containerId): \(error.localizedDescription)",
                category: .initialization)
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
    func syncContainerStats(for containerId: UUID, lastIndexedAt: Date? = nil) {
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
    func syncAllContainerStats() {
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
            Log.error(
                "[RAGService] Failed to save chat history for container \(containerId): \(error.localizedDescription)",
                category: .initialization)
        }
    }

    @MainActor
    func persistIngestionQueueState() {
        savePersistedIngestionQueueState()
    }

    @MainActor
    func restoreIngestionQueueIfNeeded() async {
        await restorePersistedIngestionQueueIfNeeded()
    }

    @MainActor
    func recordIngestionQueueTombstones(for items: [IngestionItem]) {
        guard !items.isEmpty else { return }
        let discardedAt = Date()
        ingestionQueueTombstones = IngestionQueueTombstonePolicy.merged(
            ingestionQueueTombstones,
            items.map {
                IngestionQueueTombstone(
                    id: $0.id,
                    containerId: $0.containerId,
                    discardedAt: discardedAt
                )
            }
        )
    }

    @MainActor
    private var selfHealingSuppressedContainerIds: Set<UUID> {
        get {
            let values =
                UserDefaults.standard.stringArray(
                    forKey: Self.selfHealingSuppressedContainersDefaultsKey
                ) ?? []
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(
                newValue.map(\.uuidString).sorted(),
                forKey: Self.selfHealingSuppressedContainersDefaultsKey
            )
        }
    }

    @MainActor
    func suppressSelfHealing(for containerIds: Set<UUID>) {
        guard !containerIds.isEmpty else { return }
        selfHealingSuppressedContainerIds.formUnion(containerIds)
        pendingSelfHealingContainerIds.removeAll { containerIds.contains($0) }
    }

    @MainActor
    func clearSelfHealingSuppression(for containerId: UUID) {
        selfHealingSuppressedContainerIds.remove(containerId)
    }

    @MainActor
    func isSelfHealingSuppressed(for containerId: UUID) -> Bool {
        selfHealingSuppressedContainerIds.contains(containerId)
    }

    nonisolated static func isAutomaticSelfHealingItem(_ item: IngestionItem) -> Bool {
        guard item.metrics.isRebuild else { return false }
        return isAutomaticSelfHealingReason(item.metrics.rebuildReason)
    }

    /// Whether a rebuild's reason is the app's own repair rather than the person's Rebuild (also the journal's
    /// `rebuild.start` `selfHealing`, 5.8).
    nonisolated static func isAutomaticSelfHealingReason(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("self-healing")
            || reason.localizedCaseInsensitiveContains("empty vector store")
    }

    @MainActor
    func savePersistedIngestionQueueState() {
        let url = AppSupportPaths.ingestionQueueURL()
        let tombstonedIds = Set(ingestionQueueTombstones.map(\.id))
        let activeItems = ingestionItems.filter { !$0.stage.isTerminal && !tombstonedIds.contains($0.id) }
        let recentTerminalItems = ingestionItems.filter { item in
            guard !tombstonedIds.contains(item.id) else { return false }
            guard item.stage.isTerminal else { return false }
            if let finishedAt = item.finishedAt {
                return Date().timeIntervalSince(finishedAt) < 900  // 15 minutes
            }
            return false
        }

        let itemsToPersist = activeItems + recentTerminalItems
        let state = PersistedIngestionQueueState(
            items: itemsToPersist,
            contexts: itemsToPersist.map {
                PersistedIngestionContext(id: $0.id, context: ingestionContexts[$0.id] ?? .userInitiated)
            },
            tombstones: ingestionQueueTombstones,
            updatedAt: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try WorkspaceSyncService.coordinatedWriteData(data, to: url)
        } catch {
            Log.error(
                "[RAGService] Failed to persist ingestion queue: \(error.localizedDescription)", category: .ingestion)
        }
    }

    @MainActor
    func restorePersistedIngestionQueueIfNeeded() async {
        // Don't let a workspace reload overwrite an in-flight runtime queue.
        // During shared-workspace sync churn, reloadWorkspaceData() can fire while the
        // current device is actively importing. Restoring the persisted snapshot in
        // that moment incorrectly demotes same-device leased items back to
        // "Queued for pickup", even though the live task is still running.
        let hasActiveRuntimeIngestion = ingestionTask != nil || ingestionItems.contains { !$0.stage.isTerminal }
        guard !hasActiveRuntimeIngestion else { return }

        let url = AppSupportPaths.ingestionQueueURL()
        guard let data = try? WorkspaceSyncService.coordinatedReadData(from: url) else {
            IngestionRuntimeBridge.shared.endLiveActivity()
            return
        }

        do {
            let decoder = JSONDecoder()
            let state = try decoder.decode(PersistedIngestionQueueState.self, from: data)
            ingestionQueueTombstones = IngestionQueueTombstonePolicy.merged(
                ingestionQueueTombstones,
                state.tombstones
            )
            let tombstonedIds = Set(ingestionQueueTombstones.map(\.id))
            var restoredItems: [IngestionItem] = []
            var restoredContexts: [UUID: IngestionContext] = [:]
            let currentDeviceID = WorkspaceSyncService.currentDeviceID()
            let now = Date()
            let validContainerIds = Set(containerService.containers.map(\.id))
            let defaultContainerId = containerService.containers.first?.id
            // Libraries with a saved rebuild item (5.8): checked below rather than dropped or rebuilt outright.
            var rebuildsToResume: [UUID: Set<UUID>] = [:]

            for item in state.items {
                guard !tombstonedIds.contains(item.id) else { continue }
                guard !item.stage.isTerminal else { continue }

                if let containerId = item.containerId, !validContainerIds.contains(containerId) {
                    Log.warning(
                        "[RAGService] Skipping persisted ingestion item for deleted library: \(item.url.lastPathComponent)",
                        category: .ingestion)
                    continue
                }

                if item.containerId == nil, defaultContainerId == nil {
                    Log.warning(
                        "[RAGService] Skipping persisted ingestion item because no default library exists: \(item.url.lastPathComponent)",
                        category: .ingestion)
                    continue
                }

                if let resolvedContainerId = item.containerId ?? defaultContainerId,
                    let container = containerService.containers.first(where: { $0.id == resolvedContainerId }),
                    let existingDoc = existingImportedDocument(
                        in: resolvedContainerId,
                        storageRelativePath: item.storageRelativePath,
                        fileHash: item.documentHash
                    )
                {
                    // Ask the metadata, not the vector store.
                    //
                    // `Document.totalChunks` is written when ingestion completes and is
                    // loaded synchronously at launch — it is the same figure the startup
                    // log reports as "Loaded 2 documents (196 chunks)". The vector store
                    // is loaded lazily per container, so querying it during queue restore
                    // asks a store that may not be open yet, and an unopened store answers
                    // "empty" without raising an error.
                    //
                    // A device log shows exactly that sequence:
                    //
                    //     16:  [RAGService] Loaded 2 documents (196 chunks)
                    //     60:  [BNNS] Loaded 182 chunks          (one container only)
                    //    106:  Retaining ... chunks are missing  (the guard, too early)
                    //    400:  [BNNS] Persisted 13 chunks        (the document's own chunks)
                    //
                    // The ingestion had completed. The store simply had not been opened
                    // for that container when the guard ran, so every relaunch resurrected
                    // a finished import and asked the user to resume it.
                    // A rebuild keeps the document listed with its count while its passages are cleared (5.8), so a
                    // listed document says nothing about whether its rebuild finished. Through the first 5.8 builds
                    // the rebuild was dropped here as "already imported" and its documents stayed without passages
                    // (the owner's iPhone, 2026-11-03 16:11: a 21-document rebuild ended by a relaunch).
                    if item.metrics.isRebuild {
                        rebuildsToResume[resolvedContainerId, default: []].insert(existingDoc.id)
                        continue
                    }
                    if existingDoc.totalChunks > 0 {
                        Log.info(
                            "[RAGService] Dropping persisted ingestion item for already imported document: "
                                + "\(item.url.lastPathComponent) (\(existingDoc.totalChunks) chunks recorded)",
                            category: .ingestion
                        )
                        continue
                    }

                    // Metadata itself reports zero chunks, which is the ambiguous case:
                    // either the ingestion truly did not finish, or the record predates
                    // chunk counting. Consult the store, and treat a read failure as
                    // "not proven missing" rather than as evidence to re-ingest.
                    let database = self.vectorRouter.db(for: container)
                    // The check needs which document each passage belongs to and nothing of
                    // its text, so it reads the store's records (5.7).
                    let allChunks: [PassageRecord]
                    do {
                        allChunks = try await database.passageRecords()
                    } catch {
                        Log.error(
                            "[RAGService] Vector store read failed while checking '\(item.url.lastPathComponent)' "
                                + "(container \(resolvedContainerId)): \(type(of: error)) — \(error.localizedDescription). "
                                + "Dropping the queued item rather than re-ingesting a document that may already be complete.",
                            category: .ingestion
                        )
                        continue
                    }

                    let documentChunks = allChunks.filter { $0.documentId == existingDoc.id }

                    if !documentChunks.isEmpty {
                        Log.info(
                            "[RAGService] Dropping persisted ingestion item for already imported document: \(item.url.lastPathComponent)",
                            category: .ingestion
                        )
                        continue
                    } else {
                        // Name what was actually inspected. Zero matches out of a store
                        // holding thousands of chunks means the lookup missed, not that
                        // the document is absent -- most likely the wrong container's
                        // database, or a document record whose id no longer matches the
                        // id its chunks carry.
                        let distinctDocs = Set(allChunks.map(\.documentId)).count
                        Log.warning(
                            "[RAGService] Retaining interrupted ingestion item for '\(item.url.lastPathComponent)': "
                                + "0 chunks matched document \(existingDoc.id) in container \(resolvedContainerId), "
                                + "which holds \(allChunks.count) chunks across \(distinctDocs) document(s). "
                                + (allChunks.isEmpty
                                    ? "The store is empty, so this ingestion genuinely did not complete."
                                    : "The store is NOT empty, so this is an id or container mismatch rather than a missing document."),
                            category: .ingestion
                        )
                    }
                }

                if item.url.isFileURL {
                    let reachable = (try? item.url.checkResourceIsReachable()) ?? false
                    if !reachable {
                        Log.warning(
                            "[RAGService] Skipping persisted ingestion item because file is unreachable: \(item.url.lastPathComponent)",
                            category: .ingestion)
                        continue
                    }
                    if FileManager.default.isUbiquitousItem(at: item.url) {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
                    }
                }

                var resumedItem = item
                if resumedItem.events.count > 100 {
                    resumedItem.events.removeFirst(resumedItem.events.count - 100)
                }

                if item.isLeased(to: currentDeviceID, at: now) || !item.hasActiveLease(at: now) {
                    resumedItem.stage = .paused
                    // A restart does not lose streamed-PDF progress: `importLargePDFStreamed` skips
                    // any batch whose `endPage <= lastCompletedPage`. Report what is preserved, so a
                    // user does not cancel a resume that would have worked — discarding a queue item
                    // deletes the checkpoint directory, whereas a restart does not.
                    //
                    // The page total comes from the interrupted run's own persisted metrics rather
                    // than from reopening the document, because this function is `@MainActor` and
                    // runs during launch. When there is no checkpoint, `restored` is nil and both
                    // assignments below are exactly what they were before.
                    let restored = documentProcessor.restoredIngestionProgress(
                        for: item.url,
                        knownPageCount: item.metrics.pageCount
                    )
                    resumedItem.detail = restored?.detail ?? "Paused after app restart"
                    resumedItem.progress = restored?.fraction
                    resumedItem.startedAt = nil
                    resumedItem.finishedAt = nil
                    resumedItem.errorMessage = nil
                    resumedItem.clearLease()
                } else {
                    resumedItem.detail = "Processing on another device"
                }

                restoredItems.append(resumedItem)
            }

            // A saved rebuild item doesn't say its document still needs one (5.8): the queue file is shared through iCloud,
            // so it can hold another device's, and the rebuild can have finished before the item was cleared. On the
            // owner's iPhone on 2026-11-03 at 17:53 a first version of this restarted 34 documents of Library 6 from the
            // Mac's unfinished rebuild, though the phone had rebuilt them at 16:35. So each library gets the check its
            // opening gets, which rebuilds only the documents with no passages in the store.
            for (libraryId, documentIds) in rebuildsToResume {
                Log.info(
                    "[RAGService] \(documentIds.count) saved rebuild item(s) for \(libraryId); checking which documents still have no passages",
                    category: .ingestion)
                VerificationJournal.record("rebuild.checkedAfterRelaunch", ["documents": "\(documentIds.count)"])
                await evaluateSemanticIndexHealth(for: libraryId)
            }

            guard !restoredItems.isEmpty else {
                if ingestionQueueTombstones.isEmpty {
                    try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
                } else {
                    savePersistedIngestionQueueState()
                }
                IngestionRuntimeBridge.shared.endLiveActivity()
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
            Log.info(
                "[RAGService] Restored \(restoredItems.count) queued ingestion item(s) after interruption; waiting for resume decision",
                category: .ingestion)
            savePersistedIngestionQueueState()
            if restoredItems.contains(where: { $0.stage == .paused }) {
                IngestionRuntimeBridge.shared.endLiveActivity()
                NotificationCenter.default.post(
                    name: NSNotification.Name("com.openintelligence.showIngestionQueue"), object: nil)

                // Retransmit after a delay to ensure view is mounted and listening
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    NotificationCenter.default.post(
                        name: NSNotification.Name("com.openintelligence.showIngestionQueue"), object: nil)
                }
            } else {
                syncIngestionLiveActivity()
            }
        } catch {
            Log.error(
                "[RAGService] Failed to restore persisted ingestion queue: \(error.localizedDescription)",
                category: .ingestion)
            try? WorkspaceSyncService.coordinatedRemoveItem(at: url)
        }
    }

    @MainActor
    func clearRuntimeIngestionQueueState() {
        guard !ingestionItems.isEmpty || !ingestionContexts.isEmpty || !liveActivityTrackedIngestionIds.isEmpty else {
            return
        }

        ingestionItems.removeAll()
        ingestionContexts.removeAll()
        liveActivityTrackedIngestionIds.removeAll()
        syncIngestionLiveActivity()
    }

    @MainActor
    func clearIngestionQueue() {
        let discardedItems = ingestionItems
        recordIngestionQueueTombstones(for: discardedItems)
        suppressSelfHealing(
            for: Set(
                discardedItems.compactMap { item in
                    Self.isAutomaticSelfHealingItem(item) ? item.containerId : nil
                }))
        if ingestionTask != nil {
            // The import that is running sees these and removes what it had stored.
            requestedIngestionCancellationIds.formUnion(
                discardedItems.filter { !$0.stage.isTerminal && $0.stage != .queued && $0.stage != .paused }.map(\.id))
        }
        for item in discardedItems where item.stage == .queued || item.stage == .paused {
            purgeStreamedTextImport(for: item.url, containerId: item.containerId ?? containerService.containers.first?.id)
        }
        cancelIngestionTaskAndSetItAside()
        isProcessing = false
        ingestionItems.removeAll()
        ingestionContexts.removeAll()
        liveActivityTrackedIngestionIds.removeAll()
        syncIngestionLiveActivity()
        savePersistedIngestionQueueState()
    }

    /// Pauses the import queue at the person's word (5.7, roadmap row "Ingestion has no pause
    /// control"). A tester three hours into a five-hour import asked for it on 2026-08-29.
    ///
    /// The file being imported stops the way it does when iOS ends the app's background time: a
    /// file imported in pieces (a PDF over 10 MB; a text, Markdown or JSON Lines file over 8 MB)
    /// keeps its checkpoint and goes on from its last saved piece, and any other file starts over,
    /// which the paused item says. Every file still waiting is paused too. The queue then waits for
    /// Continue (`continuePausedIngestionQueue`) or Discard, as it does after the app was closed in
    /// the middle of an import.
    @MainActor
    func pauseIngestionQueue() {
        let activeIndices = ingestionItems.indices.filter {
            !ingestionItems[$0].stage.isTerminal && ingestionItems[$0].stage != .paused
        }
        guard !activeIndices.isEmpty else { return }
        ingestionPausedByPerson = true
        cancelIngestionTaskAndSetItAside()
        isProcessing = false
        processingStatus = ""

        for index in activeIndices {
            let restored = documentProcessor.restoredIngestionProgress(
                for: ingestionItems[index].url, knownPageCount: ingestionItems[index].metrics.pageCount)
            ingestionItems[index].stage = .paused
            ingestionItems[index].detail = restored == nil ? Self.pausedStartsOverDetail : Self.pausedKeepsPlaceDetail
            ingestionItems[index].progress = restored?.fraction
            ingestionItems[index].startedAt = nil
            ingestionItems[index].finishedAt = nil
            ingestionItems[index].errorMessage = nil
            ingestionItems[index].clearLease()
            ingestionItems[index].events.append(
                IngestionEvent(stage: .paused, title: "Paused", detail: ingestionItems[index].detail))
        }

        Log.info("[RAGService] The person paused \(activeIndices.count) import(s)", category: .ingestion)
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    /// What a paused import says about continuing (5.7).
    static let pausedKeepsPlaceDetail = "Paused. Continues from where it stopped"
    static let pausedStartsOverDetail = "Paused. Starts over when you continue"

    @MainActor
    func handleContinuedIngestionExpiration(backgroundTimeRanOut: Bool = false) {
        // A queue the person paused stays paused: the import their pause stopped ends through here.
        guard !ingestionPausedByPerson else {
            savePersistedIngestionQueueState()
            syncIngestionLiveActivity()
            return
        }
        let activeIndices = ingestionItems.indices.filter { !ingestionItems[$0].stage.isTerminal }
        guard !activeIndices.isEmpty else {
            savePersistedIngestionQueueState()
            return
        }

        #if canImport(UIKit)
            // The system can take its background task back while the app is in front (it does
            // when the task shows no progress, and for reasons of its own). An import does not
            // need background time while the person is looking at it, so it goes on.
            if backgroundTimeRanOut, UIApplication.shared.applicationState == .active {
                Log.info(
                    "[RAGService] The system ended the import's background task with the app in front; the import goes on",
                    category: .ingestion)
                return
            }
        #endif

        // Only the call that finds a task running is the system stopping the queue. The loop's
        // own catch calls this again on its way out, and that call must not set the flag a
        // second time: the queue may already have been started again by then.
        if ingestionTask != nil {
            cancelIngestionTaskAndSetItAside()
            ingestionStoppedByBackgroundExpiry = true
        }
        isProcessing = false
        processingStatus = ""

        for index in activeIndices {
            ingestionItems[index].stage = .queued
            ingestionItems[index].detail = IngestionItem.queuedForResumeDetail
            // A file imported in pieces, or a streamed PDF, keeps what its checkpoint holds, so
            // the bar stays where the import stands instead of going back to nothing.
            ingestionItems[index].progress =
                documentProcessor.restoredIngestionProgress(
                    for: ingestionItems[index].url, knownPageCount: ingestionItems[index].metrics.pageCount
                )?.fraction
            ingestionItems[index].startedAt = nil
            ingestionItems[index].finishedAt = nil
            ingestionItems[index].errorMessage = nil
            ingestionItems[index].metrics = .init()
            ingestionItems[index].clearLease()
        }

        Log.warning(
            "[RAGService] Continued ingestion expired; queued \(activeIndices.count) item(s) for resume",
            category: .ingestion)
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    /// Starts the queue again after a background window ran out. Called when the app comes back
    /// to the front. Through 5.6 an import stopped this way sat at "Queued for resume" until the
    /// person noticed and started it again. A file imported in pieces goes on from its last
    /// committed piece; any other import starts over, as it did when started by hand.
    @MainActor
    func resumeIngestionStoppedInBackgroundIfNeeded() {
        guard ingestionStoppedByBackgroundExpiry else { return }
        ingestionStoppedByBackgroundExpiry = false
        guard ingestionTask == nil else { return }
        let waiting = ingestionItems.filter { $0.stage == .queued }
        guard !waiting.isEmpty, !ingestionItems.contains(where: { $0.stage == .paused }) else { return }
        Log.info(
            "[RAGService] Back in front: continuing \(waiting.count) import(s) that a background limit stopped",
            category: .ingestion)
        resumeUserInitiatedIngestionBackgroundSupportIfNeeded(
            restoredItems: ingestionItems.filter { !$0.stage.isTerminal })
        syncIngestionLiveActivity()
        // The new task waits for the cancelled one to end (`startIngestionTaskIfNeeded`).
        startIngestionTaskIfNeeded()
    }

    /// Cancels the queue's task and sets it aside, so the next one can wait for it to end.
    @MainActor
    func cancelIngestionTaskAndSetItAside() {
        guard let task = ingestionTask else { return }
        task.cancel()
        ingestionTaskUnwinding = task
        ingestionTask = nil
    }

    /// Whether the person asked for this queue item to be cancelled, as opposed to the system
    /// stopping the queue.
    @MainActor
    func isIngestionCancellationRequested(_ id: UUID) -> Bool {
        requestedIngestionCancellationIds.contains(id)
    }

    /// The bookkeeping a finished import in pieces shares with any other: the time is noted so
    /// that self-tuning does not answer a large new document by re-embedding the whole library.
    @MainActor
    func noteStreamedImportFinished(in containerId: UUID) {
        lastIngestionCompletionTime[containerId] = Date()
    }

    @MainActor
    func resumeUserInitiatedIngestionBackgroundSupportIfNeeded(restoredItems: [IngestionItem]) {
        #if canImport(UIKit)
            guard UIApplication.shared.applicationState == .active else { return }
        #endif

        let resumedUserInitiatedItems = restoredItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        guard !resumedUserInitiatedItems.isEmpty else { return }

        let subtitle =
            resumedUserInitiatedItems.count == 1
            ? resumedUserInitiatedItems[0].filename
            : "\(resumedUserInitiatedItems.count) documents"
        IngestionRuntimeBridge.shared.beginUserInitiatedIngestion(
            title: "Importing documents",
            subtitle: subtitle
        )
    }

}
