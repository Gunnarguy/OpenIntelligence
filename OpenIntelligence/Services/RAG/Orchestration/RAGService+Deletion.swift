//
//  RAGService+Deletion.swift
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
    // MARK: - Deleting with undo (5.7)

    /// Takes documents out of the list now and removes them for good after `window`, unless `undoRemoval` puts
    /// them back first (5.7, `PendingDocumentRemoval`). `beforeRemoving` runs for each document just before its
    /// removal, as deleting a shared document's file from iCloud does. With an `undoManager`, its Undo (Edit,
    /// Undo on the Mac, shaking the iPhone) puts them back too, until the removal runs. Returns the removal's
    /// id, or nil when none of the documents is in the list.
    @MainActor
    @discardableResult
    func scheduleRemoval(
        of documentsToRemove: [Document],
        window: Duration = PendingDocumentRemoval.undoWindow,
        undoManager: UndoManager? = nil,
        actionName: String = "Delete Document",
        beforeRemoving: (@MainActor (Document) async -> Void)? = nil
    ) -> UUID? {
        let wanted = Set(documentsToRemove.map(\.id))
        var taken: [Document] = []
        var positions: [Int] = []
        for (position, document) in documents.enumerated() where wanted.contains(document.id) {
            taken.append(document)
            positions.append(position)
        }
        guard !taken.isEmpty else { return nil }
        let removal = PendingDocumentRemoval(
            id: UUID(), documents: taken, positions: positions,
            deadline: Date().addingTimeInterval(window / .seconds(1)))
        let takenIds = Set(taken.map(\.id))
        documents.removeAll { takenIds.contains($0.id) }
        totalChunksStored -= taken.reduce(0) { $0 + $1.totalChunks }
        syncContainerStats(forLibrariesOf: taken)
        PendingDocumentRemovalLedger.add(takenIds)

        let work = PendingDocumentRemovalWork(beforeRemoving: beforeRemoving, undoManager: undoManager)
        if let undoManager {
            let removalId = removal.id
            let target = work.undoTarget
            // An undo manager does not keep its target alive, so the entry holds it (`[target]`): the work
            // record that also holds it goes when the removal runs or is undone.
            undoManager.registerUndo(withTarget: target) { [weak self, target] _ in
                withExtendedLifetime(target) { _ = self?.undoRemoval(removalId) }
            }
            undoManager.setActionName(actionName)
        }
        pendingRemovals.append(removal)
        pendingRemovalWork[removal.id] = work
        // The timer keeps the engine until it fires, so a Mac window closed in those seconds still has its
        // removal run, rather than at the next launch.
        work.timer = Task { @MainActor in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            await self.commitRemoval(removal.id)
        }
        Log.info(
            "[RAGService] Took \(taken.count) document(s) out of the list; removed in \(window) unless undone",
            category: .ingestion)
        return removal.id
    }

    /// Puts back the documents of a removal that has not run, where they were in the list (5.7). Returns false
    /// when it has run already, or was undone.
    @MainActor
    @discardableResult
    func undoRemoval(_ id: UUID) -> Bool {
        guard let index = pendingRemovals.firstIndex(where: { $0.id == id }) else { return false }
        let removal = pendingRemovals.remove(at: index)
        if let work = pendingRemovalWork.removeValue(forKey: id) {
            work.timer?.cancel()
            // Not while the undo manager is running this undo itself.
            if let undoManager = work.undoManager, !undoManager.isUndoing {
                undoManager.removeAllActions(withTarget: work.undoTarget)
            }
        }
        // A document already back in the list, from a reload, is not added twice.
        var listed = Set(documents.map(\.id))
        for (document, position) in zip(removal.documents, removal.positions) where !listed.contains(document.id) {
            documents.insert(document, at: min(position, documents.count))
            totalChunksStored += document.totalChunks
            listed.insert(document.id)
        }
        syncContainerStats(forLibrariesOf: removal.documents)
        PendingDocumentRemovalLedger.remove(Set(removal.documents.map(\.id)))
        Log.info("[RAGService] Put back \(removal.documents.count) document(s): the deletion was undone", category: .ingestion)
        return true
    }


    /// Runs a pending removal now, and returns when it has finished (5.7). Returns false when there is none by
    /// that id to start: it was undone, it has run, or it is running, in which case this waits for it.
    @MainActor
    @discardableResult
    func commitRemoval(_ id: UUID) async -> Bool {
        if let running = removalsRunning[id] {
            await running.task.value
            return false
        }
        guard let index = pendingRemovals.firstIndex(where: { $0.id == id }) else { return false }
        let removal = pendingRemovals.remove(at: index)
        // The timer is not cancelled here: this can be the timer's own call.
        let work = pendingRemovalWork.removeValue(forKey: id)
        if let work, let undoManager = work.undoManager {
            undoManager.removeAllActions(withTarget: work.undoTarget)
        }
        // A task of its own: no caller's cancellation stops it halfway, and a caller that must wait for every
        // removal can (`commitPendingRemovals`).
        let task = Task { @MainActor in
            for document in removal.documents {
                await work?.beforeRemoving?(document)
                do {
                    try await self.removeDocument(document)
                } catch {
                    Log.error(
                        "[RAGService] Could not remove \(document.filename): \(error.localizedDescription)",
                        category: .ingestion)
                }
            }
            PendingDocumentRemovalLedger.remove(Set(removal.documents.map(\.id)))
            // Cleared by the removal itself, so whoever awaits it finds it gone; a caller clearing it after its
            // own wait could resume after another waiter (`PendingDocumentRemovalTests`, 2026-10-15).
            self.removalsRunning[id] = nil
        }
        // Set before the task can start: it waits for the main actor, which this holds until the await below.
        removalsRunning[id] = (task, Set(removal.documents.map(\.id)))
        await task.value
        return true
    }

    /// Whether a removal is waiting or running (5.7).
    @MainActor
    var hasUnfinishedRemovals: Bool { !pendingRemovals.isEmpty || !removalsRunning.isEmpty }

    /// Whether this document's removal is waiting or running (5.7).
    @MainActor
    func isRemovalPending(_ documentId: UUID) -> Bool {
        pendingRemovals.contains { $0.documents.contains { $0.id == documentId } }
            || removalsRunning.values.contains { $0.documentIds.contains(documentId) }
    }

    /// Runs every waiting removal now and waits for those already running (5.7): when the app goes to the
    /// background, before a library is deleted or emptied, and before Clear All.
    @MainActor
    func commitPendingRemovals() async {
        for removal in pendingRemovals {
            pendingRemovalWork[removal.id]?.timer?.cancel()
            await commitRemoval(removal.id)
        }
        for running in removalsRunning.values {
            await running.task.value
        }
    }

    /// Whether this launch has run the removals an earlier run of the app left pending.
    @MainActor private static var removalsLeftPendingChecked = false

    /// Runs, once a launch, the removals an earlier run of the app scheduled and did not live to run (5.7):
    /// the app was closed, or ended, in a deletion's undo seconds. Their deletion was asked for and never
    /// undone, and the documents are out of the list already (`applyLoadedDocuments`). `force` runs it again,
    /// for a test.
    @MainActor
    func removeDocumentsLeftPending(
        ledgerURL: URL = PendingDocumentRemovalLedger.defaultURL, force: Bool = false
    ) async {
        guard force || !Self.removalsLeftPendingChecked else { return }
        Self.removalsLeftPendingChecked = true
        let leftOver = PendingDocumentRemovalLedger.earlierRunIds(at: ledgerURL)
        guard !leftOver.isEmpty, let listed = loadDocumentsSnapshotFromDisk() else { return }
        let documentsToRemove = listed.filter { leftOver.contains($0.id) }
        for document in documentsToRemove {
            do {
                try await removeDocument(document)
            } catch {
                Log.error(
                    "[RAGService] Could not remove \(document.filename): \(error.localizedDescription)",
                    category: .ingestion)
            }
        }
        PendingDocumentRemovalLedger.remove(leftOver, at: ledgerURL)
        Log.info(
            "[RAGService] Removed \(documentsToRemove.count) document(s) deleted just before the app last closed",
            category: .ingestion)
    }

    @MainActor
    private func syncContainerStats(forLibrariesOf affected: [Document]) {
        let firstLibrary = containerService.containers.first?.id
        for containerId in Set(affected.compactMap { $0.containerId ?? firstLibrary }) {
            syncContainerStats(for: containerId)
        }
    }

    /// Puts an imported document in the list, in place of a record with its id, and returns that record's passage count
    /// (5.8). Only a rebuild finds one: it keeps the document's id, and a sync pass while it ran can have put the old
    /// record back.
    ///
    /// The replaced record's date added, place in the list, and its hash, tags and processing details where the
    /// re-import has none, are kept: a streamed import's record carries no tags or details, and a rebuild must not move
    /// a document to the end of the list or make it look newly added.
    /// `adjustingStoredCount` is the streamed imports': they don't add their passages to `totalChunksStored` themselves,
    /// so a replaced record's count is swapped for the new one here.
    @MainActor @discardableResult func listImportedDocument(_ document: Document, adjustingStoredCount: Bool = false) -> Int {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else {
            documents.append(document)
            return 0
        }
        let old = documents[index]
        let replacedChunks = documents.filter { $0.id == document.id }.reduce(0) { $0 + $1.totalChunks }
        documents.removeAll { $0.id == document.id }
        documents.insert(
            Document(
                id: document.id,
                filename: document.filename,
                fileURL: document.fileURL,
                storageRelativePath: document.storageRelativePath ?? old.storageRelativePath,
                fileHash: document.fileHash ?? old.fileHash,
                contentType: document.contentType,
                addedAt: old.addedAt,
                totalChunks: document.totalChunks,
                processingMetadata: document.processingMetadata ?? old.processingMetadata,
                containerId: document.containerId,
                contentTags: document.contentTags ?? old.contentTags
            ),
            at: min(index, documents.count))
        if adjustingStoredCount { totalChunksStored += document.totalChunks - replacedChunks }
        return replacedChunks
    }

    /// Remove a document from the knowledge base
    ///
    /// `forRebuild` is a rebuild's (5.8): the document's passages and index entries go, and its record, its file and
    /// its id stay, because it comes straight back under the same id (`addDocument(documentId:)`). Through 5.7 a
    /// rebuild removed the document like a deletion: its id was recorded as deleted and it came back under a new one, so
    /// another device wiped its passages, found the library empty, rebuilt it the same way and sent the deletions back
    /// (the owner's iPhone and Mac, 2026-11-03: 5,165, 1,888 and 403 passages in one pass). And with the record gone a
    /// sync pass took the kept file for an orphan and deleted it (`Deleted local orphaned document file`, 13:58:49 that
    /// day), so the document could not come back at all.
    func removeDocument(_ document: Document, keepPhysicalFile: Bool = false, forRebuild: Bool = false) async throws {
        if !forRebuild { registerDeletedDocuments([document]) }
        let targetContainerId = await MainActor.run {
            document.containerId ?? self.containerService.containers.first?.id
                ?? self.containerService.activeContainerId
        }
        let db = await dbFor(targetContainerId)
        try await db.deleteChunks(forDocument: document.id)

        // Delete full text storage for ZERO data orphans (both FTS5 and legacy file storage)
        await SQLiteFullTextService.shared.delete(for: document.id)
        await SQLiteFullTextService.shared.deleteChunks(for: document.id)
        await FullTextStorageService.shared.delete(for: document.id)

        // Remove from Spotlight index, with the document's passages (5.7)
        SpotlightIndexService.shared.deindexDocument(id: document.id, containerId: targetContainerId)

        // Remove entity index entries to prevent ghost entities from deleted documents
        await EntityIndexService.shared.removeDocument(document.id)

        // Delete physical file if it's in our internal storage
        if !keepPhysicalFile, !forRebuild {
            let fileURL = document.fileURL
            if fileURL.path.contains("ImportedDocuments") {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        // Invalidate visualization cache for the document's library after removal
        ProjectionCache.shared.invalidate(forContainer: targetContainerId)

        // Remove from suggested questions bank
        await SuggestedQuestionsService.shared.removeQuestions(for: document.id, in: targetContainerId)

        if forRebuild {
            Log.info(" Cleared the index of \(document.filename) to rebuild it", category: .ingestion)
            return
        }

        await MainActor.run {
            let listedBefore = documents.count
            documents.removeAll { $0.id == document.id }
            // A document a pending removal took out of the list had its passages subtracted then (5.7).
            if documents.count < listedBefore {
                totalChunksStored -= document.totalChunks
            }
            syncContainerStats(for: targetContainerId)
        }

        await saveDocumentsToDisk()

        Log.info(" Removed document: \(document.filename)")

        refreshIntelligence(for: targetContainerId, force: true)
    }

    /// Clear all documents from the knowledge base
    func clearAllDocuments() async throws {
        // A deletion still in its undo seconds runs first (5.7): its document is out of the list, so this would
        // empty its stores without recording it as deleted, and an Undo would bring back an empty document.
        await commitPendingRemovals()
        let activeId = await MainActor.run { self.containerService.activeContainerId }
        let docsToDelete = await MainActor.run {
            self.documents.filter { $0.containerId == activeId }
        }
        // Recorded as deleted before anything is removed, as `removeDocument` does (5.7): the model work that follows
        // an import reads the record to know its document is going (`enrichmentTargetState`), and through 5.6 this
        // wrote it after the store was emptied (review, 2026-10-19). A store that cannot be emptied leaves the
        // documents as they were, record included.
        registerDeletedDocuments(docsToDelete)
        let db = await dbForActiveContainer()
        do {
            try await db.clear()
        } catch {
            clearDeletionTombstones(for: docsToDelete.map(\.id))
            throw error
        }

        // Invalidate visualization cache for the cleared container
        ProjectionCache.shared.invalidate(forContainer: activeId)

        // Delete full text storage for all documents being cleared (both FTS5 and legacy)
        // FTS5: Single bulk operation for entire container (most efficient)
        await SQLiteFullTextService.shared.deleteContainer(containerId: activeId)
        await SQLiteFullTextService.shared.deleteChunksForContainer(containerId: activeId)

        // Legacy file storage: Delete individual documents
        for doc in docsToDelete {
            await FullTextStorageService.shared.delete(for: doc.id)
        }

        // Remove all documents in this container from Spotlight.
        //
        // `deindexContainer` deletes one identifier, `container-<uuid>`, which is the library's
        // own Spotlight entry. It does not touch the documents, which are indexed under the
        // domain `\(domainIdentifier).<containerId>` and removed by `deindexAllDocuments`. Only
        // the first was called, so wiping a library left every one of its documents searchable
        // in Spotlight while removing the library they pointed at. `ContainerService`
        // `deleteContainer` has always called both.
        SpotlightIndexService.shared.deindexContainer(id: activeId)
        SpotlightIndexService.shared.deindexAllDocuments(in: activeId)

        // Entity index entries, for the same reason `removeDocument` clears them per document:
        // without this, entities extracted from wiped documents keep resolving.
        for doc in docsToDelete {
            await EntityIndexService.shared.removeDocument(doc.id)
        }

        // The imported copies on disk. `removeDocument` deletes these one at a time under the
        // same `ImportedDocuments` guard; this function never did, so a wiped library kept its
        // full disk footprint. The only sweep that would eventually collect them lives inside
        // `synchronizeConfiguredLibraries`, which never runs for a Local Only library, so on
        // that path the bytes stayed forever.
        for doc in docsToDelete where doc.fileURL.path.contains("ImportedDocuments") {
            try? FileManager.default.removeItem(at: doc.fileURL)
        }

        // Clear suggested questions bank
        await SuggestedQuestionsService.shared.clearQuestionBank(for: activeId)

        await MainActor.run {
            documents.removeAll { $0.containerId == activeId }
            totalChunksStored = documents.reduce(0) { $0 + $1.totalChunks }
            syncContainerStats(for: activeId)
        }

        await saveDocumentsToDisk()

        Log.info(" Cleared all documents from knowledge base")

        refreshIntelligence(for: activeId, force: true)
    }

    /// Rebuild embeddings for every document in the specified container
    func reembedDocuments(
        in containerId: UUID? = nil,
        reason: String? = nil,
        onlyDocumentIds: Set<UUID>? = nil,
        progressHandler: (@MainActor (ReembedProgress) -> Void)? = nil
    ) async throws {
        let targetContainerId: UUID
        if let containerId {
            targetContainerId = containerId
        } else {
            targetContainerId = await MainActor.run { self.containerService.activeContainerId }
        }
        let isAutomaticSelfHealing =
            reason?.localizedCaseInsensitiveContains("self-healing") == true
            || reason?.localizedCaseInsensitiveContains("empty vector store") == true
        let shouldProceed = await MainActor.run {
            if isAutomaticSelfHealing {
                return !isSelfHealingSuppressed(for: targetContainerId)
            }
            clearSelfHealingSuppression(for: targetContainerId)
            return true
        }
        guard shouldProceed else {
            Log.info(
                "[RAGService] Skipping user-suppressed self-healing rebuild for container \(targetContainerId)",
                category: .ingestion
            )
            return
        }
        // Only *active* queue items may veto a rebuild.
        //
        // This set was built from every element of `ingestionItems` with no stage filter, so a
        // finished `.complete` item vetoed its own document forever. `pruneCompletedIngestionItems`
        // bails whenever any item is non-terminal, so one stuck `.paused` entry pinned every
        // completed entry in the array and each pinned entry blocked its document's repair.
        //
        // The comment below states the intent — items "already queued or paused" — and terminal
        // items are neither. There is also an everyday trigger with no stuck item involved:
        // `pruneCompletedIngestionItems()` defers four seconds while `kickPendingReembedIfNeeded()`
        // fires immediately after, so freshly imported documents vetoed their own re-embed.
        let documentsToRebuild = await MainActor.run {
            Self.documentsEligibleForRebuild(
                in: self.documents,
                targetContainerId: targetContainerId,
                blockingURLs: Self.blockingIngestionURLs(in: self.ingestionItems),
                fallbackContainerId: self.containerService.containers.first?.id
            )
            .filter { onlyDocumentIds?.contains($0.id) ?? true }
        }

        guard !documentsToRebuild.isEmpty else {
            await MainActor.run {
                progressHandler?(ReembedProgress(completed: 0, total: 0, currentFilename: ""))
            }

            // An empty rebuild has two very different causes and they were reported identically.
            // A library with no documents is a genuine no-op. A library that HAS documents and
            // still produced nothing was vetoed by the queue filter above, and returning normally
            // told the caller the repair had succeeded — so it logged success and took the rebuild
            // banner down having rebuilt nothing, and the next health check re-flagged it. That
            // cycle does not terminate, and deleting the library was the only way out of it.
            let libraryDocumentCount = await MainActor.run {
                self.documentsForContainer(targetContainerId).count
            }

            // The classification is made by `classifyRebuild` rather than inline, so the branch
            // that ships is the branch the unit tests cover. A test over a parallel copy of this
            // decision would prove nothing about what actually runs.
            switch Self.classifyRebuild(eligible: documentsToRebuild, documentsInLibrary: libraryDocumentCount) {
            case .blockedByQueue(let blocked):
                Log.warning(
                    "[RAGService] Rebuild for container \(targetContainerId) was blocked: all "
                        + "\(blocked) document(s) are excluded by active ingestion queue items. "
                        + "Nothing was rebuilt.",
                    category: .ingestion
                )
                throw RAGServiceError.rebuildBlockedByQueue(blocked: blocked)
            case .libraryEmpty, .rebuild:
                return
            }
        }

        VerificationJournal.record(
            "rebuild.start", .started,
            ["library": VerificationJournal.anon(targetContainerId), "documents": "\(documentsToRebuild.count)",
                "selfHealing": "\(Self.isAutomaticSelfHealingReason(reason ?? ""))", "engines": "\(Self.liveEngineCount)"])
        // VISIBLE LOGGING: Make rebuild starts obvious in console
        Log.warning(
            "🔄 [Reembed] STARTING FULL REBUILD of \(documentsToRebuild.count) documents in container \(targetContainerId)\n"
                + "   Documents: \(documentsToRebuild.map { $0.filename }.joined(separator: ", "))",
            category: .ingestion
        )

        // The library on screen stays as it is (5.8). A rebuild used to open the library it rebuilt and go back at the end,
        // from before an import could name its library: on the owner's iPhone on 2026-11-03 a self-healing rebuild moved
        // the Chat tab to another library while he was tapping through them, and the screen went blank until the app was
        // closed. Each document now goes back to `targetContainerId` by name (`addDocument(containerId:)`).

        let rebuildReason: String
        if let reason {
            rebuildReason = reason
        } else {
            rebuildReason = await MainActor.run {
                containerService.containers.first { $0.id == targetContainerId }?.chunkingDirective.map {
                    "\($0.strategy.capitalized) strategy, \($0.targetWordWindow)w window"
                } ?? "Configuration changed"
            }
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
            for item in rebuildItems {
                ingestionContexts[item.id] = .autoRebuild
            }
            savePersistedIngestionQueueState()
            // On the Lock Screen and with the system's background time, as an import is (5.8). Through the first 5.8
            // builds a rebuild had neither: leaving the app stopped it within about 30 seconds and nothing showed it
            // (the owner's iPhone, 2026-11-03 16:03, a 21-document rebuild).
            if !rebuildItems.isEmpty {
                liveActivityTrackedIngestionIds.formUnion(rebuildItems.map(\.id))
                IngestionRuntimeBridge.shared.beginUserInitiatedIngestion(
                    title: "Rebuilding a library",
                    subtitle: rebuildItems.count == 1 ? rebuildItems[0].filename : "\(rebuildItems.count) documents")
                syncIngestionLiveActivity()
            }
        }

        defer {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingStatus = ""
                self.isProcessing = false
                if self.libraryRebuildProgress?.libraryId == targetContainerId { self.libraryRebuildProgress = nil }
                // Prune completed items after a delay
                self.pruneCompletedIngestionItems(delay: 5.0)
            }
        }

        let container = await MainActor.run {
            self.containerService.containers.first { $0.id == targetContainerId }
        }
        let providerId = container?.embeddingProviderId ?? "coreml_sentence_embedding"
        let initialDimension = container?.embeddingDim ?? 384

        let containerEmbeddingService = EmbeddingService.forProvider(
            id: providerId,
            targetDimension: initialDimension
        )

        var wasStoppedByUser = false
        for (index, document) in documentsToRebuild.enumerated() {
            if Task.isCancelled { break }
            if isAutomaticSelfHealing,
                await MainActor.run(body: { self.isSelfHealingSuppressed(for: targetContainerId) })
            {
                wasStoppedByUser = true
                break
            }

            let trackingId = rebuildItems[index].id

            // A document deleted while the rebuild runs is waiting out its undo seconds with its file still
            // there, and rebuilding it would import it again under a new id (5.7, `scheduleRemoval`).
            if await MainActor.run(body: { self.isRemovalPending(document.id) }) {
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: document.filename,
                        stage: .complete,
                        detail: "Skipped (deleted)",
                        progress: 1.0
                    )
                }
                continue
            }

            let targetWindow = container?.chunkingDirective?.targetWordWindow ?? ChunkingDefaults.targetWindow
            let targetOverlap = container?.chunkingDirective?.overlapWords ?? ChunkingDefaults.overlap
            let targetStrategy = container?.chunkingDirective?.strategy ?? "balanced"

            var chunkingConfigHasNotChanged = false
            if let docMetadata = document.processingMetadata,
                let docWindow = docMetadata.targetWordWindow,
                let docOverlap = docMetadata.overlapWords
            {
                chunkingConfigHasNotChanged =
                    (docWindow == targetWindow && docOverlap == targetOverlap
                        && docMetadata.chunkingStrategy == targetStrategy)
            } else if rebuildReason.contains("Self-healing") || rebuildReason.contains("empty vector store") {
                chunkingConfigHasNotChanged = true
            }

            // Try to get existing chunks from vector database first
            let db = await dbFor(targetContainerId)
            var chunksToReembed = try await db.chunks(forDocument: document.id)

            // If empty in vector DB, try to retrieve from FTS5
            if chunksToReembed.isEmpty {
                let ftsChunks = await SQLiteFullTextService.shared.retrieveChunks(for: document.id)
                if !ftsChunks.isEmpty {
                    chunksToReembed = ftsChunks.map { ftsChunk in
                        let pathComponents = ftsChunk.sectionPath?.components(separatedBy: " > ")
                        let metadata = ChunkMetadata(
                            chunkIndex: ftsChunk.chunkIndex,
                            startPosition: 0,
                            endPosition: ftsChunk.content.count,
                            pageNumber: ftsChunk.pageNumber,
                            sectionTitle: ftsChunk.sectionTitle,
                            keywords: [],
                            semanticDensity: 0.5,
                            hasNumericData: ftsChunk.content.rangeOfCharacter(from: .decimalDigits) != nil,
                            hasListStructure: ftsChunk.content.contains("\n•") || ftsChunk.content.contains("\n-"),
                            wordCount: ftsChunk.content.split(separator: " ").count,
                            characterCount: ftsChunk.content.count,
                            structureType: ftsChunk.structureType,
                            sectionPath: pathComponents
                        )
                        return DocumentChunk(
                            id: UUID.deterministic(from: "\(document.id.uuidString)_\(ftsChunk.chunkIndex)"),
                            documentId: document.id,
                            content: ftsChunk.content,
                            parentContent: nil,
                            contextualPrefix: nil,
                            embedding: [],
                            metadata: metadata
                        )
                    }
                }
            }

            let canOptimize = chunkingConfigHasNotChanged && !chunksToReembed.isEmpty

            if canOptimize {
                Log.info(
                    "[Reembed] Running optimized re-embedding path for '\(document.filename)' (\(chunksToReembed.count) chunks)...",
                    category: .ingestion)

                await MainActor.run {
                    self.processingStatus =
                        "Re-embedding \(document.filename) (optimized) (\(index + 1)/\(documentsToRebuild.count))"
                    self.libraryRebuildProgress = LibraryRebuildProgress(
                        libraryId: targetContainerId, done: index, total: documentsToRebuild.count,
                        filename: document.filename)
                    self.isProcessing = true
                    progressHandler?(
                        ReembedProgress(
                            completed: index,
                            total: documentsToRebuild.count,
                            currentFilename: document.filename
                        ))

                    updateIngestionItem(
                        id: trackingId,
                        filename: document.filename,
                        stage: .embedding,
                        detail: "Re-embedding \(chunksToReembed.count) chunks (optimized)...",
                        progress: 0.0
                    ) { metrics in
                        metrics.isRebuild = true
                        metrics.rebuildReason = rebuildReason
                        metrics.embeddingDimension = initialDimension
                        metrics.embeddingProvider = Self.shortProviderName(for: providerId)
                    }
                }

                // 1. Build contextual prefixes and prep texts to embed
                let docContext = buildContextualPrefix(filename: document.filename)
                var textsToEmbed: [String] = []
                var updatedChunks: [DocumentChunk] = []
                let maxTokens = containerEmbeddingService.maxSafeTokens

                let translatedChunkTexts = await translatedTextsForEmbedding(
                    chunksToReembed.map { $0.content },
                    container: container
                )

                for (idx, chunk) in chunksToReembed.enumerated() {
                    let sectionContext: String
                    if let path = Self.trustedSectionDisplayPath(chunk.metadata.sectionPath), !path.isEmpty {
                        sectionContext = " [\(path.joined(separator: " > "))]"
                    } else if let title = Self.trustedSectionDisplayLabel(chunk.metadata.sectionTitle) {
                        sectionContext = " [\(title)]"
                    } else {
                        sectionContext = ""
                    }
                    let contextualPrefix = docContext + sectionContext + " "
                    var textForEmbedding = contextualPrefix + translatedChunkTexts[idx]

                    let tokenCount = containerEmbeddingService.countTokens(textForEmbedding)
                    if tokenCount > maxTokens {
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
                    }

                    textsToEmbed.append(textForEmbedding)

                    let updatedChunk = DocumentChunk(
                        id: chunk.id,
                        documentId: chunk.documentId,
                        content: chunk.content,
                        parentContent: chunk.parentContent,
                        contextualPrefix: contextualPrefix,
                        embedding: [],
                        metadata: chunk.metadata
                    )
                    updatedChunks.append(updatedChunk)
                }

                // 2. Generate embeddings
                let trackingIdForProgress = trackingId
                let filenameForProgress = document.filename
                let embeddings = try await containerEmbeddingService.generateEmbeddings(
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
                try EmbeddingVectorCheck.requireUsable(embeddings, of: document.filename)

                if isAutomaticSelfHealing,
                    await MainActor.run(body: { self.isSelfHealingSuppressed(for: targetContainerId) })
                {
                    wasStoppedByUser = true
                    break
                }

                let finalChunks = zip(updatedChunks, embeddings).map { chunk, embedding in
                    DocumentChunk(
                        id: chunk.id,
                        documentId: chunk.documentId,
                        content: chunk.content,
                        parentContent: chunk.parentContent,
                        contextualPrefix: chunk.contextualPrefix,
                        embedding: embedding,
                        metadata: chunk.metadata
                    )
                }

                // 3. Delete old chunks from vector DB, store new chunks, and persist
                try await db.deleteChunks(forDocument: document.id)
                try await db.storeBatch(chunks: finalChunks)
                try await db.persist()

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: document.filename,
                        stage: .complete,
                        detail: "Re-embedded (optimized)",
                        progress: 1.0
                    )
                    self.isProcessing = true
                }
            } else {
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
                    self.libraryRebuildProgress = LibraryRebuildProgress(
                        libraryId: targetContainerId, done: index, total: documentsToRebuild.count,
                        filename: document.filename)
                    self.isProcessing = true
                    progressHandler?(
                        ReembedProgress(
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

                if isAutomaticSelfHealing,
                    await MainActor.run(body: { self.isSelfHealingSuppressed(for: targetContainerId) })
                {
                    wasStoppedByUser = true
                    break
                }

                // Once the index is cleared, the matching re-add is intentionally atomic from the cancellation
                // policy's perspective. The record stays listed throughout (5.8), so a re-add that fails leaves the
                // document listed without passages, which the banner offers to rebuild, and the rest go on.
                try await removeDocument(document, keepPhysicalFile: true, forRebuild: true)

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: document.filename,
                        stage: .reindexing,
                        detail: "Re-processing with new config..."
                    )
                }

                // Re-add with autoRebuild context (prevents recursive self-tuning), under the document's own id and into
                // its own library (5.8): see `removeDocument(_:keepPhysicalFile:forRebuild:)`.
                do {
                    try await addDocument(
                        at: document.fileURL, context: .autoRebuild, trackingId: trackingId,
                        containerId: targetContainerId, documentId: document.id)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Log.error(
                        "[Reembed] Could not rebuild \(document.filename); it stays listed without passages: \(error.localizedDescription)",
                        category: .ingestion)
                    await MainActor.run {
                        updateIngestionItem(
                            id: trackingId, filename: document.filename, stage: .failed,
                            detail: "Couldn't be rebuilt", progress: 1.0, errorMessage: error.localizedDescription)
                        self.librariesNeedingIndexRebuild.insert(targetContainerId)
                    }
                    continue
                }

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
        }

        if wasStoppedByUser {
            await MainActor.run {
                let remainingItems = self.ingestionItems.filter { item in
                    item.containerId == targetContainerId && Self.isAutomaticSelfHealingItem(item)
                }
                self.recordIngestionQueueTombstones(for: remainingItems)
                let remainingIds = Set(remainingItems.map(\.id))
                self.ingestionItems.removeAll { remainingIds.contains($0.id) }
                self.ingestionContexts = self.ingestionContexts.filter { id, _ in !remainingIds.contains(id) }
                self.savePersistedIngestionQueueState()
            }
            TelemetryCenter.emit(
                .ingestion,
                title: "Library rebuild stopped",
                metadata: [
                    "container": targetContainerId.uuidString,
                    "reason": "userDismissedAutomaticSelfHealing",
                ]
            )
            return
        }

        await MainActor.run {
            self.clearIntelligence(for: targetContainerId)
        }
        self.refreshIntelligence(for: targetContainerId, force: false)

        await MainActor.run {
            progressHandler?(
                ReembedProgress(
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

}
