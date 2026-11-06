//
//  RAGService+Storage.swift
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
    // MARK: - Document Persistence

    private var documentsStorageURL: URL {
        AppSupportPaths.documentsMetadataURL()
    }

    func loadDocumentsFromDisk() {
        let loadedDocuments = loadDocumentsSnapshotFromDisk()
        Task { @MainActor [weak self] in
            guard let self, let loadedDocuments else { return }
            self.applyLoadedDocuments(loadedDocuments)
            // An update changes every cached search's key, as does a document another device added or
            // removed, so cached searches no question can reach are deleted at launch too (5.7).
            await Self.deleteUnreachableCachedSearches(
                documents: self.documents.map { (id: $0.id, passages: $0.totalChunks) })
            // Deletions made just before the app last closed, whose undo seconds it did not live through (5.7).
            await self.removeDocumentsLeftPending()
        }
    }

    /// The stored documents: none when there is no file yet, and nil when there is one and it
    /// could not be read or decoded. Through 5.6 a failed read gave an empty list, which emptied
    /// the library on screen and removed what was kept about every library; since 5.7 it would
    /// also remove every Spotlight entry, so a failed read now changes nothing.
    func loadDocumentsSnapshotFromDisk() -> [Document]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documentsStorageURL.path) else {
            Log.info("  [RAGService] No existing documents metadata found")
            return []
        }

        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: documentsStorageURL)
            return try JSONDecoder().decode([Document].self, from: data)
        } catch {
            Log.error(
                " [RAGService] Failed to load documents metadata: \(error.localizedDescription); the documents in memory are kept")
            return nil
        }
    }

    /// `loadDocumentsSnapshotFromDisk` for bytes already read off the main thread: none when there was no
    /// file, nil when it could not be read or decoded, so a failed read changes nothing.
    private func decodeDocumentsSnapshot(_ read: Result<Data?, Error>) -> [Document]? {
        do {
            guard let data = try read.get() else {
                Log.info("  [RAGService] No existing documents metadata found")
                return []
            }
            return try JSONDecoder().decode([Document].self, from: data)
        } catch {
            Log.error(
                " [RAGService] Failed to load documents metadata: \(error.localizedDescription); the documents in memory are kept")
            return nil
        }
    }

    /// What `LibraryIntelligenceCache.sweep` keeps for these documents: for each library that
    /// has any, the signature of its documents. A document with no library belongs to the first.
    @MainActor
    private func keptAnalysisSignatures(for loadedDocuments: [Document]) -> [UUID: String] {
        let defaultContainerId = containerService.containers.first?.id
        let known = Set(containerService.containers.map(\.id))
        var byContainer: [UUID: [Document]] = [:]
        for document in loadedDocuments {
            guard let containerId = document.containerId ?? defaultContainerId, known.contains(containerId) else {
                continue
            }
            byContainer[containerId, default: []].append(document)
        }
        return byContainer.mapValues { LibraryIntelligenceCache.documentsSignature($0) }
    }

    @MainActor
    private func applyLoadedDocuments(_ loadedDocuments: [Document]) {
        // Every load of the documents, changed or not, checks what is kept on disk about each
        // library against the documents it has now. This is where a document or a library
        // removed on another device arrives, and where a library whose last document is gone
        // is seen. The check reads file names and nothing else.
        let current = keptAnalysisSignatures(for: loadedDocuments)
        Task.detached(priority: .utility) {
            LibraryIntelligenceCache.sweep(keeping: current)
        }
        // The same goes for this device's Spotlight entries, which since 5.7 do not expire.
        SpotlightIndexService.shared.documentsLoaded(
            loadedDocuments, defaultLibraryId: containerService.containers.first?.id)
        // And for what actions handed to Shortcuts (5.7, `HandedOutItems`): kept a day, less for a passage whose
        // document is in no library now, which goes with any answer that used it. An empty list, which a read that
        // failed can give, only drops what has expired.
        let documentIds = Set(loadedDocuments.map(\.id))
        Task.detached(priority: .utility) {
            if documentIds.isEmpty {
                HandedOutItems.dropExpired()
            } else {
                HandedOutItems.keepOnly(documents: documentIds)
            }
        }
        hasAppliedLoadedDocuments = true
        // A document whose removal is waiting out its undo seconds stays out of the list (5.7): it is still on
        // disk until the removal runs, and a reload in those seconds would otherwise show it again. The
        // analysis sweep and Spotlight above are given every document, so an undo finds both as they were.
        let hidden = PendingDocumentRemovalLedger.allIds().union(pendingRemovals.flatMap { $0.documents.map(\.id) })
        let shown = hidden.isEmpty ? loadedDocuments : loadedDocuments.filter { !hidden.contains($0.id) }
        guard documents != shown else { return }
        documents = shown
        totalChunksStored = shown.reduce(0) { $0 + $1.totalChunks }
        syncAllContainerStats()
        Log.info("[RAGService] Loaded \(shown.count) documents (\(totalChunksStored) chunks)")
        if !shown.isEmpty {
            refreshIntelligence(for: nil)
        }
    }

    /// How many times `reloadWorkspaceData` has run this session. Printed with each
    /// timing line so a capture shows the call *volume*, which is the part that turns
    /// a handful of cheap operations into a visible stall.
    @MainActor private static var reloadWorkspaceDataCallCount = 0

    /// Re-reads the document list and the vector stores' file signatures, off the main thread since 5.8, and
    /// applies them on it. The timing lines below were added 2026-08-26 as instrumentation.
    ///
    /// A device capture on 2026-08-26 cleared the two things previously suspected of
    /// making the Documents tab slow: the tab-appear task runs in 21 to 62ms and each
    /// vector store load in 1 to 31ms. What the capture *showed* instead was volume:
    /// 21 store loads across 7 databases, 15 replays of the persisted ingestion queue,
    /// and a container change cascading into a sync pass over every library.
    ///
    /// This function is the common ancestor of all of it and `DocumentLibraryView`
    /// calls it from seven places. But that it is *expensive* is still an inference,
    /// not a measurement, and the last four attempts at this bug were confident
    /// inferences. Its three parts are timed separately so the next capture names the
    /// one that costs, rather than a change being made to vector code on a hunch.
    /// Returns the reload's task, true when it applied what it read, for a caller (a test) that needs the
    /// documents applied before it goes on.
    @MainActor
    @discardableResult
    func reloadWorkspaceData() -> Task<Bool, Never> {
        let reloadStarted = Date()
        Self.reloadWorkspaceDataCallCount += 1
        let callNumber = Self.reloadWorkspaceDataCallCount
        latestWorkspaceReload += 1
        let reloadNumber = latestWorkspaceReload
        let changesAtStart = documentsChangeCount
        let openStores = vectorRouter.openContainerIds
        let documentsURL = documentsStorageURL

        // The file reads go off the main thread (5.8). On the owner's iPhone on 2026-11-04 this reload ran
        // after each iCloud pass and held the main thread for seconds at a time (watchdog stalls of 5.4 and
        // 8.5 s; clearAll 1,211 ms and docsSnapshot 1,867 ms in one call), and taps in Settings were lost.
        // The coordinated read of the document list waits for iCloud, and the stores' sweep reads each
        // file's attributes. Only the decoding and what follows run on the main thread, as before.
        return Task { @MainActor [weak self] in
            let read = await Task.detached(priority: .userInitiated) {
                () -> (signatures: [UUID: [String: String]], documents: Result<Data?, Error>) in
                var signatures: [UUID: [String: String]] = [:]
                for containerId in openStores {
                    signatures[containerId] = VectorStoreRouter.diskSignature(for: containerId)
                }
                let documents: Result<Data?, Error>
                if FileManager.default.fileExists(atPath: documentsURL.path) {
                    documents = Result { try WorkspaceSyncService.coordinatedReadData(from: documentsURL) }
                } else {
                    documents = .success(nil)
                }
                return (signatures, documents)
            }.value
            guard let self else { return false }
            // A reload asked of this engine while this one read reads the files again, newer, and is the
            // one applied.
            guard reloadNumber == self.latestWorkspaceReload else {
                Log.debug("[WorkspaceReload] #\(callNumber) dropped: a newer reload is reading", category: .pipeline)
                return false
            }
            // The list changed in memory while this read: what it read may be older than what is shown, and
            // applying it would undo that change (and the next save would write the older copy back). The
            // stores' signatures still apply; the list waits for the next reload.
            let listIsCurrent = changesAtStart == self.documentsChangeCount
            if !listIsCurrent {
                Log.info(
                    "[WorkspaceReload] #\(callNumber) kept the documents in memory: they changed during the read",
                    category: .pipeline)
                VerificationJournal.record("workspace.reloadListSkipped", ["call": "\(callNumber)"])
            }
            self.applyWorkspaceReload(
                callNumber: callNumber, started: reloadStarted, signatures: read.signatures,
                documentsData: listIsCurrent ? read.documents : nil)
            return true
        }
    }

    /// The main-thread half of `reloadWorkspaceData`, given what it read from disk.
    @MainActor
    private func applyWorkspaceReload(
        callNumber: Int, started reloadStarted: Date, signatures: [UUID: [String: String]],
        documentsData: Result<Data?, Error>?
    ) {
        let readMs = Date().timeIntervalSince(reloadStarted) * 1000

        let clearStarted = Date()
        vectorRouter.clearAll(signatures: signatures)
        let clearMs = Date().timeIntervalSince(clearStarted) * 1000

        let snapshotStarted = Date()
        let readDocuments = documentsData.flatMap { decodeDocumentsSnapshot($0) }
        let loadedDocuments = readDocuments ?? documents
        if readDocuments != nil {
            applyLoadedDocuments(loadedDocuments)
        }
        let snapshotMs = Date().timeIntervalSince(snapshotStarted) * 1000

        if !FileManager.default.fileExists(atPath: AppSupportPaths.ingestionQueueURL().path), ingestionTask == nil {
            clearRuntimeIngestionQueueState()
        }
        Task {
            // Timed inside its own task because it is async and runs off the
            // synchronous part below. The coordinated read it performs is the single
            // operation here capable of a multi-second stall: NSFileCoordinator on an
            // iCloud-synced path is what CLAUDE.md opens by warning about.
            let queueStarted = Date()
            await restorePersistedIngestionQueueIfNeeded()
            Log.info(
                "[WorkspaceReload] #\(callNumber) ingestionQueue "
                    + "\(String(format: "%.0f", Date().timeIntervalSince(queueStarted) * 1000))ms",
                category: .pipeline
            )
            await removeTextOfUnfinishedImports()
        }

        let mainMs = Date().timeIntervalSince(clearStarted) * 1000
        Log.info(
            "[WorkspaceReload] #\(callNumber) read off the main thread \(String(format: "%.0f", readMs))ms, "
                + "clearAll \(String(format: "%.0f", clearMs))ms, "
                + "docsSnapshot \(String(format: "%.0f", snapshotMs))ms, "
                + "main thread \(String(format: "%.0f", mainMs))ms, "
                + "documents=\(loadedDocuments.count)",
            category: .pipeline
        )
        VerificationJournal.record(
            "workspace.reload", .ok,
            ["call": "\(callNumber)", "readMs": String(format: "%.0f", readMs),
                "mainMs": String(format: "%.0f", mainMs), "documents": "\(loadedDocuments.count)"])

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

    /// Whether this launch has looked for the text of imports that never finished.
    @MainActor private static var unfinishedImportTextChecked = false

    /// Removes, once a launch, the text of documents that never finished importing (5.7, roadmap row
    /// "Text from an unfinished import is never removed").
    ///
    /// An import stores the document's text in the keyword store before it cuts it into passages,
    /// and the document's record is saved only at the end. An app that ended in the middle of an
    /// import (closed by the person or by iOS) left that text with no document to go with it: in no
    /// search, and taking room, since nothing removed it. 5.7 already removes it when an import is
    /// cancelled or stops at the passage limit. This removes the text of every document the keyword
    /// store holds and the document list does not, using the store's own calls
    /// (`SQLiteFullTextService` is not changed). It does nothing while an import is queued or running,
    /// whose text is stored before its record, and nothing when the list read from disk is empty or
    /// could not be read; the next launch looks again. The file shrinks only when Optimize Database
    /// runs.
    @MainActor
    func removeTextOfUnfinishedImports() async {
        guard !Self.unfinishedImportTextChecked else { return }
        guard ingestionTask == nil, !ingestionItems.contains(where: { !$0.stage.isTerminal }) else { return }
        Self.unfinishedImportTextChecked = true
        guard let listed = loadDocumentsSnapshotFromDisk(), !listed.isEmpty else { return }
        let known = Set(listed.map(\.id)).union(documents.map(\.id))
        let stored = await SQLiteFullTextService.shared.getAllDocumentIds()
        let removed = await Self.removeStoredText(of: stored, notIn: known, using: SQLiteFullTextService.shared)
        if removed > 0 {
            Log.info(
                "[RAGService] Removed the stored text of \(removed) document(s) whose import never finished",
                category: .ingestion)
        }
        // The vector stores hold such a document's passages too (5.7). Searches leave them out
        // (`passagesFromKnownDocuments`), and nothing removed them: on 2026-10-15 the owner's library BDB0BCA5
        // held 27 and no document. Local Only libraries only: an iCloud library's documents can arrive after its
        // passages, and a removal there would reach the person's other devices.
        let localStores = containerService.containers
            .filter { $0.syncMode != .iCloudShared }
            .map { vectorRouter.db(for: $0) }
        let removedPassages = await Self.removePassages(notIn: known, from: localStores)
        if removedPassages > 0 {
            Log.info(
                "[RAGService] Removed the passages of \(removedPassages) document(s) in no library",
                category: .ingestion)
        }
    }

    /// Removes from each store, and from the keyword store, the passages of every document `known` does not
    /// list, and returns how many documents' passages went (5.7). The caller decides which stores and checks
    /// that `known` came from a document list that was read.
    static func removePassages(
        notIn known: Set<UUID>, from stores: [VectorDatabase], keywordStore: SQLiteFullTextService = .shared
    ) async -> Int {
        var removed = 0
        for store in stores {
            guard let records = try? await store.passageRecords() else { continue }
            for id in Set(records.map(\.documentId)).subtracting(known) {
                do {
                    try await store.deleteChunks(forDocument: id)
                    await keywordStore.deleteChunks(for: id)
                    removed += 1
                } catch {
                    Log.warning(
                        "[RAGService] Could not remove the passages of a document in no library: \(error.localizedDescription)",
                        category: .ingestion)
                }
            }
        }
        return removed
    }

    /// Removes from `store` the text of each id in `stored` that `known` does not list, and returns
    /// how many it removed.
    nonisolated static func removeStoredText(
        of stored: [UUID], notIn known: Set<UUID>, using store: SQLiteFullTextService
    ) async -> Int {
        let leftOver = Set(stored).subtracting(known)
        for id in leftOver {
            await store.delete(for: id)
        }
        return leftOver.count
    }

    func saveDocumentsToDisk() async {
        let snapshot = await MainActor.run {
            let fp = self.localIndexSyncFingerprint(for: self.documents)
            self.lastLocalIndexSyncFingerprint = fp
            return self.documents
        }

        // Merge rather than overwrite. This is the mirror of the sync-side race:
        // a sync pass can fold in a document that arrived from another device
        // between this snapshot being taken and this write landing, and a blind
        // write of the in-memory list would erase it — the same disappearance,
        // in the opposite direction. `coordinatedMergeData` holds one write claim
        // across the read and the write so nothing can land in between.
        //
        // A document present on disk but absent from the snapshot is only dropped
        // when it has actually been tombstoned; otherwise it is newer than what
        // this process knows about and is kept.
        let deletedDocsURL = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        let tombstoned: Set<String> = {
            guard let data = try? Data(contentsOf: deletedDocsURL),
                let ids = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(ids)
        }()

        // A document recorded as deleted is left out even when this engine still holds it. Two engines
        // can be alive at once (the app's and one an action made, or two Mac windows), and through 5.6
        // an engine that had read the list before a delete wrote the deleted document back at its next
        // save. A deleted document's id never comes back: a re-index adds the file under a new one (5.7).
        let liveSnapshot = snapshot.filter { !tombstoned.contains($0.id.uuidString) }
        if liveSnapshot.count != snapshot.count {
            Log.info(
                "[RAGService] Left out \(snapshot.count - liveSnapshot.count) document(s) deleted since this engine read the list",
                category: .ingestion)
        }

        do {
            try WorkspaceSyncService.coordinatedMergeData(at: documentsStorageURL) { existing in
                var result = liveSnapshot

                if let existing {
                    let snapshotIDs = Set(liveSnapshot.map(\.id))
                    let onDisk = (try? JSONDecoder().decode([Document].self, from: existing)) ?? []
                    let unknownToThisProcess = onDisk.filter {
                        !snapshotIDs.contains($0.id) && !tombstoned.contains($0.id.uuidString)
                    }

                    if !unknownToThisProcess.isEmpty {
                        Log.warning(
                            "[RAGService] Keeping \(unknownToThisProcess.count) document(s) present on disk but absent from this snapshot — they arrived after it was taken and are not tombstoned.",
                            category: .ingestion
                        )
                        result += unknownToThisProcess
                    }
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                return try encoder.encode(result)
            }
            Log.debug(" [RAGService] Saved \(snapshot.count) documents metadata")
        } catch {
            Log.error("[RAGService] Failed to save documents metadata: \(error.localizedDescription)")
        }

        // Every cached search's key names the documents (`queryCacheKey`), so after a save that changed
        // them none of the cached searches can be found again, and they are deleted (5.7).
        await Self.deleteUnreachableCachedSearches(documents: snapshot.map { (id: $0.id, passages: $0.totalChunks) })
    }

    @MainActor
    func existingImportedDocument(
        in containerId: UUID,
        storageRelativePath: String?,
        fileHash: String?
    ) -> Document? {
        let containerDocuments = documentsForContainer(containerId)

        if let fileHash,
            let matchingHash = containerDocuments.first(where: { $0.fileHash == fileHash })
        {
            return matchingHash
        }

        if let storageRelativePath,
            let matchingPath = containerDocuments.first(where: { $0.storageRelativePath == storageRelativePath })
        {
            return matchingPath
        }

        return nil
    }

    @MainActor
    func updateIngestionItemMetadata(id: UUID?, documentHash: String?, storageRelativePath: String?) {
        guard let id,
            let index = ingestionItems.firstIndex(where: { $0.id == id })
        else {
            return
        }

        var changed = false
        if let documentHash, ingestionItems[index].documentHash != documentHash {
            ingestionItems[index].documentHash = documentHash
            changed = true
        }
        if let storageRelativePath, ingestionItems[index].storageRelativePath != storageRelativePath {
            ingestionItems[index].storageRelativePath = storageRelativePath
            changed = true
        }

        if changed {
            savePersistedIngestionQueueState()
        }
    }

    func computeDocumentHash(for url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024

        while autoreleasepool(invoking: {
            let nextChunk = try? fileHandle.read(upToCount: chunkSize)
            guard let nextChunk, !nextChunk.isEmpty else {
                return false
            }

            hasher.update(data: nextChunk)
            return true
        }) {}

        return hexString(from: hasher.finalize())
    }

    // MARK: - Vector DB Access

    /// Invalidate cached vector store for a container (call when dimension/DB kind changes)
    /// Also clears persisted storage to ensure fresh start with new dimensions.
    func invalidateVectorStore(for containerId: UUID, clearStorage: Bool = true) {
        if clearStorage {
            vectorRouter.invalidateAndClearStorage(containerId: containerId)
            Log.info(
                "[RAGService] Invalidated and cleared vector store for container \(containerId)", category: .retrieval)
        } else {
            vectorRouter.invalidate(containerId: containerId)
            Log.info("[RAGService] Invalidated vector store cache for container \(containerId)", category: .retrieval)
        }
    }

    @MainActor
    func syncMode(for document: Document) -> LibrarySyncMode {
        let targetContainerId =
            document.containerId ?? containerService.containers.first?.id ?? containerService.activeContainerId
        return containerService.containers.first(where: { $0.id == targetContainerId })?.syncMode ?? .localOnly
    }

    /// Return the vector store for a specific container, by id.
    ///
    /// Ingestion must use this rather than `dbForActiveContainer()`. An import captures its target
    /// container once, at the top of `addDocument`, and then runs for as long as extraction, OCR
    /// and embedding take — minutes for a large PDF. `dbForActiveContainer()` re-reads
    /// `containerService.activeContainer` at the moment it is called, so if the user switched
    /// libraries while the import was running, the document metadata and the FTS5 rows went to the
    /// library they started in and the vectors went to the one they happened to be looking at.
    ///
    /// The result is a library holding a document, its chunk count and its full-text rows with no
    /// vector store at all: it lists in the Database tab, shows nothing in Atlas, and answers
    /// nothing in chat. Observed on device 2026-08-18 as
    /// `Container 009866A3 has 1 document(s) and no vector store yet`.
    ///
    /// Throws when the id no longer resolves, instead of the previous fallback to the active
    /// container. "There is nowhere better to put the vectors" was the old rationale — refuted on
    /// 2026-08-20: silently persisting a document's vectors into whichever library happens to be
    /// on screen is how metadata and vectors end up split across containers, which the user
    /// discovers days later as a library that answers nothing. During the delete-resurrection
    /// churn observed that night, container identity is exactly the thing that cannot be trusted
    /// mid-flight. A failed ingest is visible and retryable; a misfiled one is a phantom.
    func dbForContainer(_ containerId: UUID) async throws -> VectorDatabase {
        try await MainActor.run {
            guard let container = self.containerService.containers.first(where: { $0.id == containerId }) else {
                Log.error(
                    "[RAGService] Vector store requested for unknown container \(containerId); failing the write rather than misfiling it into the active container.",
                    category: .vectorDB
                )
                throw VectorStoreRoutingError.containerNotFound(containerId)
            }
            return self.vectorRouter.db(for: container)
        }
    }

    /// A vector-store write was addressed to a container that no longer exists.
    enum VectorStoreRoutingError: LocalizedError {
        case containerNotFound(UUID)
        var errorDescription: String? {
            switch self {
            case .containerNotFound(let id):
                return
                    "The library this import was addressed to (\(id.uuidString.prefix(8))…) no longer exists. Nothing was written; re-import into an existing library."
            }
        }
    }

    /// Persist every cached vector store with pending data. Called when the app leaves the
    /// foreground; see `VectorStoreRouter.persistAll`.
    func persistAllVectorStores() async {
        await vectorRouter.persistAll()
    }

    /// Has every open vector store let go of the passages it has decoded (5.7). A library that
    /// has answered a question holds every passage's text (333 to 345 MB for 144,247 passages in
    /// `VectorStoreScaleBenchmarkTests`), and the system ends the background apps that hold the
    /// most memory first. The text is in the store's file, and the next question reads it back.
    /// Called on iPhone and iPad when the app goes to the background, after everything that has
    /// to be saved has been. What it gives back on a device has not been measured.
    func releaseDecodedPassagesInVectorStores() async {
        await vectorRouter.releaseDecodedPassages()
    }

    func dbForActiveContainer() async -> VectorDatabase {
        return await MainActor.run {
            let container = self.containerService.activeContainer
            // Sync active container to router for memory pressure handling
            self.vectorRouter.activeContainerId = container?.id
            // ContainerService guarantees at least one container
            return self.vectorRouter.db(for: container!)
        }
    }

    /// Return a database for a specific container id (falls back to active on miss)
    func dbFor(_ containerId: UUID) async -> VectorDatabase {
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

    /// The most passages the Atlas and the other library maps read at once. Their analysis and
    /// their projections run on the main thread and take time in proportion to this, and through
    /// 5.6 they read every passage: on a library of 63,000 passages the Atlas held the main thread
    /// for more than ten seconds and iOS ended the app (watchdog `0x8BADF00D`, 2026-10-10, in the
    /// middle of an import). A sample this size puts a share within about 1.3 points of the
    /// library's (95%, at a share of one half).
    nonisolated static let visualizationPassageLimit = 6_000

    /// Which of `count` passages a map reads when it reads at most `limit`: all of them when they
    /// fit, and otherwise `limit` positions spread evenly from the first passage to the last, in
    /// order, the same ones on every call.
    nonisolated static func evenSampleIndices(count: Int, limit: Int) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        guard count > limit else { return Array(0..<count) }
        return (0..<limit).map { Int((Int64($0) * Int64(count)) / Int64(limit)) }
    }

    /// How many passages the active container holds, whatever `allChunksForActiveContainer()`
    /// returns of them.
    func passageCountForActiveContainer() async -> Int {
        let db = await dbForActiveContainer()
        // The passages a map can draw, as `chunksForVisualization` reads them (5.7): counted with every stored passage,
        // a library with a document in its undo seconds read as larger than its map and was called a sample.
        return (try? await visiblePassageRecords(db: db).count) ?? 0
    }

    /// The store's passages less those of documents deleted in the last few seconds, which keep their passages until
    /// the undo window ends (`PendingDocumentRemoval`) and are out of the document list already (5.7).
    private func visiblePassageRecords(db: VectorDatabase) async throws -> [PassageRecord] {
        let records = try await db.passageRecords()
        let hidden = PendingDocumentRemovalLedger.allIds()
            .union(pendingRemovals.flatMap { $0.documents.map(\.id) })
        return hidden.isEmpty ? records : records.filter { !hidden.contains($0.documentId) }
    }

    /// Return the active container's chunks for the visualization views: every chunk when the
    /// library holds no more than `visualizationPassageLimit`, and past that an even sample of
    /// that many (`evenSampleIndices`). Only the returned chunks get their embeddings loaded.
    /// Used by visualization views to render embedding spaces and statistics.
    func allChunksForActiveContainer() async -> [DocumentChunk] {
        let db = await dbForActiveContainer()
        return await chunksForVisualization(db: db, limit: Self.visualizationPassageLimit)
    }

    /// The embedding space a library's vectors live in, for drawing libraries together (5.7). The Core ML and Core AI
    /// providers are two copies of one model (`EmbeddingProviderDefaults.areCopiesOfOneModel`), so their vectors share
    /// a space; any other provider, or another vector size, is its own.
    nonisolated static func atlasEmbeddingSpace(providerId: String, dimension: Int) -> String {
        let model =
            EmbeddingProviderDefaults.areCopiesOfOneModel(providerId, EmbeddingProviderDefaults.coreML)
            ? "bundled-sentence-model" : providerId
        return "\(model)-\(dimension)"
    }

    /// How many passages each library gives the All Libraries map (5.7), in the order given. When every passage fits in
    /// `visualizationPassageLimit`, each library gives all of its own. Otherwise each first gets up to 300 (fewer when
    /// 300 each would pass the limit), so a small library still shows, and the rest of the limit is shared in
    /// proportion to what each has left. The total never passes the limit, because the map's analysis and projection
    /// run on the main thread (see `visualizationPassageLimit`), and no library gives more than it has.
    nonisolated static func atlasShares(passages: [Int]) -> [Int] {
        let counts = passages.map { max($0, 0) }
        let limit = visualizationPassageLimit
        let total = counts.reduce(0, +)
        guard total > limit else { return counts }
        let libraries = max(counts.filter { $0 > 0 }.count, 1)
        let floor = min(300, limit / libraries)
        let base = counts.map { min($0, floor) }
        let remaining = limit - base.reduce(0, +)
        let rest = zip(counts, base).map { $0 - $1 }
        let restTotal = rest.reduce(0, +)
        guard remaining > 0, restTotal > 0 else { return base }
        return zip(base, rest).map { b, r in b + Int(Double(remaining) * Double(r) / Double(restTotal)) }
    }

    /// Which libraries the All Libraries map draws (5.7), from each library's embedding space
    /// (`atlasEmbeddingSpace`) and passage count. Vectors from different models can't share one projection, so one
    /// space is drawn: the one with the most passages, the open library's on a tie, then the first by name, so the
    /// choice is the same on every launch. Libraries with passages in other spaces are returned as left out; a library
    /// with no passages is neither drawn nor named. A library whose vectors wait for a rebuild after a change to the
    /// bundled model (`EmbeddingFingerprint`) is drawn with the others: nothing here can tell it apart.
    nonisolated static func atlasGroupChoice(
        libraries: [(id: UUID, space: String, passages: Int)], activeId: UUID?
    ) -> (included: [UUID], excluded: [UUID]) {
        let withPassages = libraries.filter { $0.passages > 0 }
        guard !withPassages.isEmpty else { return ([], []) }
        var totals: [String: Int] = [:]
        for library in withPassages { totals[library.space, default: 0] += library.passages }
        let activeSpace = withPassages.first(where: { $0.id == activeId })?.space
        let chosen = totals.keys.sorted { a, b in
            let totalA = totals[a] ?? 0, totalB = totals[b] ?? 0
            if totalA != totalB { return totalA > totalB }
            if (a == activeSpace) != (b == activeSpace) { return a == activeSpace }
            return a < b
        }.first
        return (
            withPassages.filter { $0.space == chosen }.map(\.id),
            withPassages.filter { $0.space != chosen }.map(\.id)
        )
    }

    /// Passages from every library in the space `atlasGroupChoice` picks, for the Atlas's All Libraries view (5.7),
    /// at most `visualizationPassageLimit` across them (`atlasShares`), and the libraries left out.
    func atlasSamplesForAllLibraries() async -> (
        included: [(library: KnowledgeContainer, chunks: [DocumentChunk])], excluded: [KnowledgeContainer]
    ) {
        let (containers, activeId) = await MainActor.run {
            (self.containerService.containers, self.containerService.activeContainerId)
        }
        // `dbForContainer` fails for a library deleted since the list was read, where `dbFor` would hand back the open
        // library's store and draw its passages twice.
        var stores: [UUID: VectorDatabase] = [:]
        var rows: [(id: UUID, space: String, passages: Int)] = []
        for library in containers {
            guard let db = try? await dbForContainer(library.id) else { continue }
            stores[library.id] = db
            let space = Self.atlasEmbeddingSpace(providerId: library.embeddingProviderId, dimension: library.embeddingDim)
            rows.append((library.id, space, (try? await visiblePassageRecords(db: db).count) ?? 0))
        }
        let choice = Self.atlasGroupChoice(libraries: rows, activeId: activeId)
        let byId = Dictionary(containers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(rows.map { ($0.id, $0.passages) }, uniquingKeysWith: { first, _ in first })
        let shares = Self.atlasShares(passages: choice.included.map { counts[$0] ?? 0 })
        var samples: [(library: KnowledgeContainer, chunks: [DocumentChunk])] = []
        for (id, share) in zip(choice.included, shares) {
            guard share > 0, let library = byId[id], let db = stores[id] else { continue }
            let chunks = await chunksForVisualization(db: db, limit: share)
            if !chunks.isEmpty { samples.append((library, chunks)) }
        }
        return (samples, choice.excluded.compactMap { byId[$0] })
    }

    /// A library's passages for a map: every passage up to `limit`, past that an even sample of `limit`
    /// (`evenSampleIndices`), with their vectors loaded.
    private func chunksForVisualization(db: VectorDatabase, limit: Int) async -> [DocumentChunk] {
        do {
            // Only the sampled passages are read from the store. Through 5.6 every passage
            // was loaded and the sample taken from that. The sample is chosen by position
            // from the store's records and then read by id: an import or a delete can run
            // between these calls, and a position would then name another passage, or pair a
            // passage with another passage's vector.
            // A document deleted in the last few seconds keeps its passages until its undo window ends; a map drawn in
            // those seconds leaves them out, as the document list does, and samples from what is left (5.7).
            let records = try await visiblePassageRecords(db: db)
            guard !records.isEmpty else { return [] }
            let keptIds = Self.evenSampleIndices(
                count: records.count, limit: limit
            ).map { records[$0].id }
            let chunks = try await db.chunks(withIDs: keptIds)

            // Compatibility hydration for mmap-backed stores:
            // BNNSVectorDatabase intentionally stores metadata-only chunks (embedding: [])
            // to keep memory low during retrieval. Visualization views require embeddings,
            // so we fetch them explicitly for this call.
            if chunks.allSatisfy({ $0.embedding.isEmpty }) {
                let embeddings = await db.getEmbeddings(forChunkIDs: chunks.map(\.id))

                guard embeddings.count == chunks.count else {
                    Log.warning(
                        "[RAGService] Embedding hydration mismatch for visualization: chunks=\(chunks.count), embeddings=\(embeddings.count)"
                    )
                    return Self.passagesWithVectors(chunks, dimension: db.dimension)
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
                return Self.passagesWithVectors(hydrated, dimension: db.dimension)
            }

            return Self.passagesWithVectors(chunks, dimension: db.dimension)
        } catch {
            Log.error("[RAGService] Failed to load all chunks: \(error.localizedDescription)")
            return []
        }
    }

    /// The passages whose vector has the store's size (5.7). A passage removed between reading it and reading its
    /// vector comes back with an empty one (`getEmbeddings`), and the map's projection drops rows of another size, which
    /// pairs every later point with the wrong colour and can seed the map's clustering from an empty row.
    nonisolated static func passagesWithVectors(_ passages: [DocumentChunk], dimension: Int) -> [DocumentChunk] {
        let kept = passages.filter { $0.embedding.count == dimension }
        if kept.count < passages.count {
            Log.warning(
                "[RAGService] Map sample left out \(passages.count - kept.count) passage(s) whose vector is missing or not \(dimension) wide",
                category: .vectorDB)
        }
        return kept
    }

    /// The most passages the suggested-question sampler scores.
    nonisolated static let suggestedQuestionPoolLimit = 4_000

    /// Every passage of a small library; for a large one an even sample in order, and every
    /// document summary, which are few and are what the sampler prefers.
    static func suggestedQuestionPool(from stored: [DocumentChunk]) -> [DocumentChunk] {
        guard stored.count > suggestedQuestionPoolLimit else { return stored }
        let sampled = evenSampleIndices(count: stored.count, limit: suggestedQuestionPoolLimit)
        let inSample = Set(sampled)
        var pool = sampled.map { stored[$0] }
        for (index, chunk) in stored.enumerated()
        where chunk.metadata.abstractionLevel == .documentSummary && !inSample.contains(index) {
            pool.append(chunk)
        }
        return pool
    }

    /// The positions `suggestedQuestionPool(from:)` would keep, worked out from the store's
    /// records so that only those passages have to be read: every position of a library that
    /// fits the limit, and past that the even sample followed by each document summary the
    /// sample missed.
    static func suggestedQuestionPoolPositions(levels: [ChunkAbstractionLevel]) -> [Int] {
        guard levels.count > suggestedQuestionPoolLimit else { return Array(levels.indices) }
        let sampled = evenSampleIndices(count: levels.count, limit: suggestedQuestionPoolLimit)
        let inSample = Set(sampled)
        var positions = sampled
        for (index, level) in levels.enumerated() where level == .documentSummary && !inSample.contains(index) {
            positions.append(index)
        }
        return positions
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
        // Choosing a few dozen samples scored every passage of the library, on the main actor,
        // each time Chat was first shown. A large library now offers an even sample of its
        // passages, plus its document summaries, to choose from.
        // The pool is chosen from the store's records and read by id, for the reason given in
        // `allChunksForActiveContainer()`.
        let records = try await db.passageRecords()
        let poolPositions = Self.suggestedQuestionPoolPositions(levels: records.map(\.abstractionLevel))
        let allChunks = try await db.chunks(withIDs: poolPositions.map { records[$0].id })
        let detailChunks = allChunks.filter { $0.metadata.abstractionLevel == .detail }
        let summaryChunks = allChunks.filter { $0.metadata.abstractionLevel == .documentSummary }

        guard !allChunks.isEmpty else { return [] }
        // Scored off the main thread (5.8): on the owner's iPhone on 2026-11-04 this scoring ran over Library 6's
        // passages on the main thread when he came back to the app, and iOS ended the app (SIGKILL, the stack in
        // `suggestedQuestionSampleContainsFrontMatterSignal`). The selection is the same pure function as before.
        return await Task.detached(priority: .userInitiated) {
            Self.selectSuggestedQuestionSample(
                detailChunks: detailChunks, summaryChunks: summaryChunks, allChunks: allChunks, limit: limit)
        }.value
    }

    nonisolated private static func selectSuggestedQuestionSample(
        detailChunks: [DocumentChunk], summaryChunks: [DocumentChunk], allChunks: [DocumentChunk], limit: Int
    ) -> [DocumentChunk] {

        if detailChunks.isEmpty {
            let sampleSource = summaryChunks.isEmpty ? allChunks : summaryChunks
            return prioritizedSuggestedQuestionSample(
                from: sampleSource,
                limit: min(limit, sampleSource.count)
            )
        }

        let summaryLimit = min(summaryChunks.count, max(1, min(3, limit / 4)))
        let detailLimit = min(detailChunks.count, max(0, limit - summaryLimit))

        let detailSample =
            detailLimit > 0
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

    nonisolated private static func interleaveSuggestedQuestionSamples(
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

    nonisolated private static func prioritizedSuggestedQuestionSample(
        from chunks: [DocumentChunk],
        limit: Int
    ) -> [DocumentChunk] {
        guard !chunks.isEmpty else { return [] }

        // Precompute all scores upfront to avoid heavy O(N log N) nested string checking during sorting
        var scoreCache: [UUID: Double] = [:]
        scoreCache.reserveCapacity(chunks.count)
        for chunk in chunks {
            scoreCache[chunk.id] = suggestedQuestionSampleScore(chunk)
        }

        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDocument[chunk.documentId, default: []].append(chunk)
        }

        for docId in byDocument.keys {
            byDocument[docId]?.sort { lhs, rhs in
                (scoreCache[lhs.id] ?? 0.0) > (scoreCache[rhs.id] ?? 0.0)
            }
        }

        let orderedDocumentIds = byDocument.keys.sorted { lhs, rhs in
            let lhsScore = suggestedQuestionDocumentScore(byDocument[lhs] ?? [], scoreCache: scoreCache)
            let rhsScore = suggestedQuestionDocumentScore(byDocument[rhs] ?? [], scoreCache: scoreCache)
            return lhsScore > rhsScore
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

                let section =
                    suggestedQuestionSampleSection(for: candidate) ?? "default_\(candidate.id.uuidString.prefix(4))"
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
            let remainder =
                orderedDocumentIds
                .flatMap { byDocument[$0] ?? [] }
                .sorted { lhs, rhs in
                    (scoreCache[lhs.id] ?? 0.0) > (scoreCache[rhs.id] ?? 0.0)
                }

            for candidate in remainder {
                guard selected.count < limit else { break }
                guard selectedIds.insert(candidate.id).inserted else { continue }
                selected.append(candidate)
            }
        }

        return selected
    }

    nonisolated private static func suggestedQuestionDocumentScore(_ chunks: [DocumentChunk], scoreCache: [UUID: Double]) -> Double {
        guard !chunks.isEmpty else { return 0 }

        let topChunkScore =
            chunks
            .map { scoreCache[$0.id] ?? 0.0 }
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

    nonisolated private static func suggestedQuestionSampleScore(_ chunk: DocumentChunk) -> Double {
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
            !imageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
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

    nonisolated private static func suggestedQuestionSampleFrontMatterAdjustment(for chunk: DocumentChunk) -> Double {
        if let section = suggestedQuestionSampleSection(for: chunk),
            suggestedQuestionSampleUsesGenericSection(section)
        {
            return -5.0
        }

        let lower = suggestedQuestionSampleContent(for: chunk).lowercased()
        if suggestedQuestionSampleContainsFrontMatterSignal(lower) {
            return -4.0
        }

        return 0
    }

    nonisolated private static func suggestedQuestionSampleSection(for chunk: DocumentChunk) -> String? {
        if let section = chunk.metadata.sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            !section.isEmpty
        {
            return section
        }

        if let lastSection = chunk.metadata.sectionPath?.last?.trimmingCharacters(in: .whitespacesAndNewlines),
            !lastSection.isEmpty
        {
            return lastSection
        }

        if let tableTitle = chunk.metadata.tableTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            !tableTitle.isEmpty
        {
            return tableTitle
        }

        return nil
    }

    nonisolated private static func suggestedQuestionSampleContent(for chunk: DocumentChunk) -> String {
        let combined = [chunk.contextualPrefix, chunk.contextText]
            .compactMap { value -> String? in
                let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return cleaned.isEmpty ? nil : cleaned
            }
            .joined(separator: "\n")

        return combined.isEmpty ? chunk.content : combined
    }

    nonisolated private static func suggestedQuestionSampleUsesGenericSection(_ title: String) -> Bool {
        let normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let genericSections: Set<String> = [
            "abstract", "acknowledgements", "about", "appendix", "author manuscript",
            "author contributions", "bibliography", "conflict of interest", "conclusion",
            "contents", "copyright", "disclaimer", "foreword", "funding", "glossary",
            "index", "introduction", "keywords", "notes", "overview", "preface",
            "references", "summary", "table of contents",
        ]

        return genericSections.contains(normalized) || suggestedQuestionSampleContainsFrontMatterSignal(normalized)
    }

    nonisolated private static func suggestedQuestionSampleContainsFrontMatterSignal(_ text: String) -> Bool {
        let signals: [String] = [
            "accepted for publication", "all rights reserved", "author contributions",
            "author manuscript", "competing interests", "conflict of interest",
            "conflicts of interest", "copyright", "corresponding author", "doi",
            "funding", "keywords", "published online", "rights reserved",
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
    func resolveEmbeddingContext(preferredContainerId: UUID? = nil) async -> EmbeddingContext {
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

        // Content-only staleness: same provider, same dimension, different vectors.
        //
        // The dimension/provider check below cannot see this. Both operands there are declared
        // values — `actualProviderId` returns a string literal and `outputDimension` a number from
        // a hardcoded table — so a change to the tokenizer, the pooling recipe or the model
        // artifact moves every vector while leaving both sides equal. Commit 2753d15 did exactly
        // that and said so in its own message.
        //
        // The response is deliberately different too. A dimension change makes old vectors
        // *incompatible*, so wiping is correct. A content change makes them *stale*: still
        // 384-dimensional, still searchable, just worse. Wiping those would take a working library
        // offline until a rebuild finishes, so this flags instead and lets the user rebuild when
        // they choose — using the same banner and manual rebuild that were fixed on 2026-08-18 and
        // confirmed working on device.
        let liveFingerprint = EmbeddingFingerprint.compute(
            providerId: actualProviderId,
            dimension: actualDimension,
            maxSequenceLength: service.maxSafeTokens,
            poolingRecipe: service.poolingRecipe,
            modelRevision: service.modelRevision,
            chunkerRecipe: EmbeddingFingerprint.chunkerRecipe(for: container.chunkingDirective)
        )

        if container.embeddingProviderId == actualProviderId,
            container.embeddingDim == actualDimension
        {
            if let stored = container.embeddingFingerprint {
                // A fingerprint stored by a build through 5.5 carries the app's own tuning in its
                // chunker term (`EmbeddingFingerprint.chunkerRecipe`). When that is the only
                // difference the pipeline is the same one: record it under the current term and
                // say nothing.
                let legacyFingerprint = EmbeddingFingerprint.compute(
                    providerId: actualProviderId,
                    dimension: actualDimension,
                    maxSequenceLength: service.maxSafeTokens,
                    poolingRecipe: service.poolingRecipe,
                    modelRevision: service.modelRevision,
                    chunkerRecipe: EmbeddingFingerprint.legacyChunkerRecipe(for: container.chunkingDirective)
                )
                // Through 5.5 a new library's fingerprint was also recorded from the app's default
                // service instead of the library's own (`stampEmbeddingFingerprintIfAbsent`). A
                // stored value that equals what that stamp would have written says nothing about
                // the vectors, which the library's own service wrote.
                let misStamped = [
                    EmbeddingFingerprint.chunkerRecipe(for: container.chunkingDirective),
                    EmbeddingFingerprint.legacyChunkerRecipe(for: container.chunkingDirective),
                ].map {
                    EmbeddingFingerprint.compute(
                        providerId: embeddingService.actualProviderId,
                        dimension: embeddingService.outputDimension,
                        maxSequenceLength: embeddingService.maxSafeTokens,
                        poolingRecipe: embeddingService.poolingRecipe,
                        modelRevision: embeddingService.modelRevision,
                        chunkerRecipe: $0
                    )
                }
                if stored != liveFingerprint, stored == legacyFingerprint || misStamped.contains(stored) {
                    Log.info(
                        "[RAGService] Container \(container.id) carries a fingerprint from before 5.6 for the same pipeline; "
                            + "re-recorded as \(liveFingerprint) without flagging a rebuild.",
                        category: .embedding
                    )
                    await MainActor.run {
                        guard var current = self.containerService.containers.first(where: { $0.id == container.id })
                        else { return }
                        current.embeddingFingerprint = liveFingerprint
                        self.containerService.updateContainer(current)
                    }
                } else if stored != liveFingerprint {
                    Log.warning(
                        "[RAGService] Embedding pipeline changed for container \(container.id): fingerprint \(stored) → \(liveFingerprint). "
                            + "Existing vectors are valid but stale; surfacing a rebuild rather than wiping a working index.",
                        category: .embedding
                    )
                    await MainActor.run {
                        let hasDocs = !self.documentsForContainer(container.id).isEmpty
                        if hasDocs {
                            self.librariesNeedingIndexRebuild.insert(container.id)
                            VerificationJournal.record(
                                "index.rebuildRequested",
                                ["library": VerificationJournal.anon(container.id), "reason": "fingerprintChanged"])
                        }
                        var updated = container
                        updated.embeddingFingerprint = liveFingerprint
                        self.containerService.updateContainer(updated)
                    }
                }
            } else {
                // No fingerprint recorded. This used to adopt the live one silently, on the
                // reasoning that nil means *unknown* and flagging every existing library the day
                // the field shipped would be a worse failure than the one it catches.
                //
                // That reasoning was right on 2026-08-18 and is wrong for the 5.0 release, because
                // what nil means has changed. v5.0 is the first build to carry
                // `embeddingFingerprint` at all, so a container arriving with nil **and documents**
                // was indexed by a pre-5.0 pipeline — and this release is precisely the one that
                // fixed how text becomes a vector. Those documents were embedded with a tokenizer
                // that truncated at 128 tokens against a 512-token model, leaving 55% of library
                // content unembedded (`2753d15`), and pooled at the CLS position rather than across
                // the passage, which measured vector r@1 0.000 → 0.571 over 21 paired cases when
                // corrected (`3ea5cd9`). Silent adoption stamps those vectors "current" and the
                // owner is never told.
                //
                // So nil is no longer unknown here; on this release it is knowable and it is stale.
                //
                // Flag rather than wipe, matching the branch above: the vectors are still valid,
                // still 384-dimensional and still searchable, just worse. Wiping would take a
                // working library offline until a rebuild finished. This surfaces the same banner
                // and the same manual rebuild that were confirmed on device on 2026-08-19 —
                // detected, rebuilt and answering again in about four seconds for 196 chunks.
                //
                // An empty container is adopted silently as before: there is nothing to rebuild,
                // and anything imported from now on is embedded correctly.
                await MainActor.run {
                    let hasDocs = !self.documentsForContainer(container.id).isEmpty
                    if hasDocs {
                        Log.warning(
                            "[RAGService] Container \(container.id) has no embedding fingerprint and "
                                + "\(self.documentsForContainer(container.id).count) document(s), so its vectors cannot "
                                + "be shown to come from the current pipeline. Surfacing a rebuild rather "
                                + "than adopting \(liveFingerprint) over vectors that may be stale.",
                            category: .embedding
                        )
                        self.librariesNeedingIndexRebuild.insert(container.id)
                        VerificationJournal.record(
                            "index.rebuildRequested",
                            ["library": VerificationJournal.anon(container.id), "reason": "noFingerprint"])
                    }
                    var updated = container
                    updated.embeddingFingerprint = liveFingerprint
                    self.containerService.updateContainer(updated)
                }
            }
        }

        if container.embeddingProviderId != actualProviderId || container.embeddingDim != actualDimension {
            Log.warning(
                "[RAGService] Embedding config mismatch for container \(container.id). "
                    + "Configured=\(container.embeddingProviderId) \(container.embeddingDim)D, "
                    + "Actual=\(actualProviderId) \(actualDimension)D. Reconciling and rebuilding index.",
                category: .embedding
            )

            await MainActor.run {
                var updated = container
                updated.embeddingProviderId = actualProviderId
                updated.embeddingDim = actualDimension
                updated.embeddingFingerprint = liveFingerprint
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

    func containerForId(_ containerId: UUID) async -> KnowledgeContainer? {
        await MainActor.run {
            self.containerService.containers.first { $0.id == containerId }
        }
    }

    func contentTaggingEnabled(for container: KnowledgeContainer?) async -> Bool {
        if let override = container?.autoTagOnIngestion {
            return override
        }

        return await MainActor.run {
            self.settingsStore?.enableContentTagging ?? true
        }
    }

    func translationTargetLanguage(for container: KnowledgeContainer?) -> Locale.Language? {
        guard let code = container?.preferredTranslationLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
            !code.isEmpty
        else {
            return nil
        }

        return Locale.Language(identifier: code)
    }

    func translatedQueryForEmbedding(
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
            VerificationJournal.record(
                "translation.question", .ok,
                ["translated": "\(result.isTranslated)", "target": targetLanguage.languageCode?.identifier ?? "?"])
            if result.isTranslated {
                let targetCode = targetLanguage.languageCode?.identifier ?? "?"
                Log.info(
                    "[Translation] Prepared translated retrieval query for target \(targetCode)", category: .retrieval)
            }
            return (result.translatedText, result.isTranslated)
        } catch {
            VerificationJournal.record(
                "translation.question", .failed,
                ["error": String(describing: type(of: error)), "target": targetLanguage.languageCode?.identifier ?? "?"])
            Log.warning("[Translation] Query translation failed, using original query: \(error)", category: .retrieval)
            return (trimmed, false)
        }
    }

    func translatedTextsForEmbedding(
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
                Log.info(
                    "[Translation] Prepared translated embeddings for \(translatedCount)/\(texts.count) chunks (target: \(targetCode))",
                    category: .ingestion)
            }
            return results.map(\.translatedText)
        } catch {
            Log.warning(
                "[Translation] Chunk translation failed, embedding original text: \(error)", category: .ingestion)
            return texts
        }
    }

}
