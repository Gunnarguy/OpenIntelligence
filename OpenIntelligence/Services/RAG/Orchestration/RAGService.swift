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

// NOTE: Local model support (GGUF, CoreML, MLX) has been removed.
// The app now uses Apple Intelligence and On-Device Analysis only.

/// Main orchestrator for the RAG (Retrieval-Augmented Generation) pipeline
/// Coordinates document processing, embedding, retrieval, and generation
class RAGService: ObservableObject {
    @MainActor public static weak var activePresentedInstance: RAGService? = nil
    nonisolated static let maxPersistedChatHistoryBytes = 4 * 1024 * 1024
    nonisolated static let ingestionLeaseDuration: TimeInterval = 120
    nonisolated static let selfHealingSuppressedContainersDefaultsKey =
        "openIntelligence.ingestion.selfHealingSuppressedContainers"

    // MARK: - Dependencies

    let documentProcessor: DocumentProcessor
    let embeddingService: EmbeddingService
    let embeddingServiceWasInjected: Bool
    let containerService: ContainerService
    let vectorRouter: VectorStoreRouter
    let intelligenceCenter = LibraryIntelligenceCenter()
    let documentSummaryService: DocumentSummaryService
    let queryRouter = QueryRouterService()
    let graphIndexService = GraphIndexService()
    let contextPackingService: ContextPackingService
    let extractiveSummarizationService: ExtractiveSummarizationService
    let specificationExtractor = SpecificationExtractor()
    let threadStore = EvidenceThreadStore()
    weak var entitlementStore: EntitlementStore?
    private var cancellables = Set<AnyCancellable>()
    @MainActor weak var settingsStore: SettingsStore?
    @MainActor var queryRuntimeCoordinator: QueryRuntimeCoordinator?
    @MainActor var pendingConsentContinuation: CheckedContinuation<CloudConsentDecision, Never>?
    /// Brings the app forward so the consent sheet can be shown: set on the engine an action builds
    /// for its question, when the system lets that action come forward (`AskActionRunner`, 5.7).
    /// Nil on the app's own engine.
    @MainActor var bringAppForwardForConsent: (@Sendable () async throws -> Void)?
    /// Set when a consent sheet was given up because no window showed it (`CloudConsentRelay`).
    @MainActor var consentRequestWentUnseen = false
    /// Set on the engine an action builds for its question (`AskActionRunner`): its consent requests
    /// go to `CloudConsentRelay`, which the app's root view shows, because no chat shows this engine.
    /// Through the first 5.7 builds the relay was chosen by `activePresentedInstance !== self`, and that
    /// weak pointer can be nil or another window's engine, which sent a chat's own request to the relay
    /// and left an action's with nothing to show it.
    @MainActor var asksThroughRelay = false
    /// True on the engine the app's window shows (`ContentView`). `activePresentedInstance` is not that: an
    /// engine an action builds with the app closed registers there too, when nothing holds the place (5.7).
    @MainActor var isTheAppsEngine = false
    /// Set once a sheet for this engine went unseen: its later steps go on without Private Cloud
    /// Compute instead of bringing the app forward and waiting again. An action's engine serves one
    /// question, so this lasts for that question.
    @MainActor var consentUnavailableForThisEngine = false
    @MainActor var transientConsentGrants: Set<CloudProvider> = []
    @MainActor var pccSuppressedUntil: Date?

    /// The routing preferences the user actually chose for the in-flight query.
    ///
    /// `ChatScreen` builds a full `InferenceConfig` carrying `fmPreference`,
    /// `executionContext`, and `allowPrivateCloudCompute`, and Standard honours it:
    /// it derives `pccEligible` from those fields and sizes the packed context to
    /// match. The agentic path did neither — `generateWithProperConsent` built a
    /// fresh `InferenceConfig` from only maxTokens/temperature/systemPrompt, so
    /// every field above fell back to its default (`.automatic`, `.automatic`,
    /// `true`). The model picker was therefore inert in Deep Think and Maximum:
    /// device logs for On-Device, Hybrid, and PCC selections were identical, and
    /// an On-Device selection still sent 16 KB of evidence to Apple PCC while the
    /// UI reported "Apple Intelligence (PCC) (User Selected)".
    ///
    /// Captured per query in `executeAgenticQuery` and read back in
    /// `generateWithProperConsent`.
    @MainActor var activeUserRoutingPreference: UserRoutingPreference = .init()

    /// The adaptive generation profile for the query currently running, or nil when the feature is
    /// off or the query is not agentic.
    ///
    /// Held here for the same reason `activeUserRoutingPreference` is: the agentic path generates
    /// across many sessions through `generateWithProperConsent`, and threading a value down through
    /// `AgenticOrchestrator` and out the other side to every call site would be a much larger change
    /// than the fact it carries. That precedent was set when the model picker turned out to be inert
    /// in Deep Think and Maximum for exactly this reason.
    ///
    /// **Why this exists at all.** The first version of adaptive profiles ran only on the Standard
    /// path, because the gate sat below the `if useAgentic` return and Deep Think and Maximum leave
    /// before it. That was the honest fix at the time, since the alternative was a log line claiming
    /// a change that never reached generation, but it left the feature absent from the two modes
    /// where a per-intent temperature would matter most.
    @MainActor var activeAdaptiveProfile: FoundationModelGenerationProfile?

    /// The subset of `InferenceConfig` that expresses the user's routing intent.
    struct UserRoutingPreference: Sendable {
        var fmPreference: FoundationModelPreference = .automatic
        var executionContext: ExecutionContext = .automatic
        var allowPrivateCloudCompute: Bool = true

        /// True when the user asked for local-only execution by any available
        /// control. On-Device must mean on-device for *every* call in the query,
        /// synthesis included — not just the reasoning sessions.
        var requiresOnDevice: Bool {
            fmPreference.canonical == .core3B
                || executionContext == .onDeviceOnly
                || !allowPrivateCloudCompute
        }

        /// True when the user explicitly asked for PCC rather than leaving it to
        /// the app. An explicit choice outranks internal budget heuristics.
        var explicitlyPrefersPCC: Bool {
            fmPreference.canonical == .privateCloudCompute
        }

        init() {}

        init(config: InferenceConfig?) {
            guard let config else { return }
            fmPreference = config.fmPreference
            executionContext = config.executionContext
            allowPrivateCloudCompute = config.allowPrivateCloudCompute
        }
    }
    @MainActor var suppressProcessingSummary: Bool = false
    @MainActor var ingestionTask: Task<Void, Never>?
    /// Set when a background window ran out and the queue was stopped for it. The person did not
    /// stop the import, so the queue starts again by itself when the app is next in front
    /// (`resumeIngestionStoppedInBackgroundIfNeeded`).
    @MainActor var ingestionStoppedByBackgroundExpiry = false
    /// A queue task that was cancelled and set aside. It is still unwinding for a moment after
    /// it is cancelled (an import checks for cancellation between steps, not inside one), and the
    /// next queue task waits for it to end before it runs, so two loops are never on one file.
    @MainActor var ingestionTaskUnwinding: Task<Void, Never>?
    /// Counts the queue loops started. A loop that finds a later one has been started leaves the
    /// queue's task and its items alone on its way out: they are the later loop's by then.
    @MainActor var ingestionLoopID = 0
    /// Whether the person paused the import queue (`pauseIngestionQueue`, 5.7). While it is set, the
    /// queue waits for Continue or Discard, and the end of the stopped import doesn't queue it again.
    @MainActor @Published var ingestionPausedByPerson = false
    @MainActor var ingestionContexts: [UUID: IngestionContext] = [:]
    @MainActor var ingestionQueueTombstones: [IngestionQueueTombstone] = []
    @MainActor var selfHealingRebuildTask: Task<Void, Never>?
    @MainActor var pendingSelfHealingContainerIds: [UUID] = [] {
        didSet { librariesWaitingForRebuild = pendingSelfHealingContainerIds }
    }
    /// The libraries whose rebuild waits behind another's, in order (5.8). A rebuild runs one library at a time, and the
    /// library's Rebuild button only queued it: the banner went away and nothing said it was waiting (the owner's
    /// iPhone, 2026-11-03, behind a 5,164-passage PDF).
    @MainActor @Published private(set) var librariesWaitingForRebuild: [UUID] = []
    /// The rebuild running now, document by document (5.8), for the library's own banner.
    @MainActor @Published var libraryRebuildProgress: LibraryRebuildProgress?
    /// The documents a pending self-healing rebuild is limited to, by library (5.7). A library with
    /// no entry is rebuilt whole, as before.
    @MainActor var selfHealingDocumentIds: [UUID: Set<UUID>] = [:]
    /// Repairs `evaluateSemanticIndexHealth` started this launch, so one that can't succeed (a source
    /// file that is gone, a model that keeps failing) is tried once and then left as a banner instead
    /// of starting again at every library switch (5.7).
    @MainActor var indexRepairsTriedThisLaunch: Set<String> = []
    @MainActor var requestedIngestionCancellationIds: Set<UUID> = []
    @MainActor var liveActivityTrackedIngestionIds: Set<UUID> = []
    @MainActor var lastLocalIndexSyncFingerprint: String? {
        get {
            UserDefaults.standard.string(forKey: "lastLocalIndexSyncFingerprint")
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "lastLocalIndexSyncFingerprint")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastLocalIndexSyncFingerprint")
            }
            UserDefaults.standard.synchronize()
        }
    }

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
        containerIntelligenceSignature.removeValue(forKey: containerId)
        corpusVocabularyCache.removeValue(forKey: containerId)
        Log.info(
            "[RAGService] Cleared intelligence and vocabulary cache for container \(containerId)", category: .retrieval)
    }

    /// Recompute the intelligence snapshot for a container on demand.
    ///
    /// One library has one refresh running at a time (5.8). Every request used to start its own task, and an
    /// import asks for one after each document, so two analyses of the same library ran at once (on his iPhone on
    /// 2026-11-03 and 04: 16:35:40 and :44, 06:39:49 and :51, 06:40:40 and :44), and five runs of 10 to 45 s
    /// were thrown away as "the library changed meanwhile". Requests made while a refresh runs are merged into
    /// one more run after it, with the strongest `force` and `allowSelfTuningScheduling` asked for, so the last
    /// run always sees the library as it is after the last request. The task returned finishes only once every
    /// request made up to that point has been analysed. The library is the one active when the request is made.
    @discardableResult
    func refreshIntelligence(
        for containerId: UUID? = nil,
        force: Bool = false,
        allowSelfTuningScheduling: Bool = false
    ) -> Task<Void, Never> {
        let key = containerId ?? containerService.activeContainerId
        // At every request, not only when a pass starts, so a deleted document's vocabulary and kept analysis do
        // not wait for the pass already running to finish.
        corpusVocabularyCache.removeValue(forKey: key)
        removeStaleKeptAnalysis(for: key)
        let pending = intelligenceRefreshPending[key] ?? (force: false, selfTuning: false)
        intelligenceRefreshPending[key] = (pending.force || force, pending.selfTuning || allowSelfTuningScheduling)
        if let running = intelligenceRefreshWorkers[key] { return running }
        let worker = Task(priority: .utility) { @MainActor [weak self] in
            // Everything here runs on the main actor between awaits, so a request cannot land between the
            // last `removeValue` and the worker being cleared below.
            while let self, let flags = self.intelligenceRefreshPending.removeValue(forKey: key) {
                // Invalidate vocabulary cache when refreshing intelligence (documents may have changed)
                self.corpusVocabularyCache.removeValue(forKey: key)
                // A refresh a screen asked for, with the library unchanged, removes nothing.
                self.removeStaleKeptAnalysis(for: key)
                await self.generateIntelligenceSnapshot(
                    for: key,
                    force: flags.force,
                    allowSelfTuningScheduling: flags.selfTuning
                )
            }
            self?.intelligenceRefreshWorkers[key] = nil
        }
        intelligenceRefreshWorkers[key] = worker
        return worker
    }

    /// The refresh running for each library, and the merged flags of the requests it has still to analyse
    /// (`refreshIntelligence`).
    @MainActor private var intelligenceRefreshWorkers: [UUID: Task<Void, Never>] = [:]
    @MainActor private var intelligenceRefreshPending: [UUID: (force: Bool, selfTuning: Bool)] = [:]

    /// The imports running per embedding provider id (`addDocument`), so ingestion mode is switched back only when
    /// the last one ends.
    @MainActor var ingestionModeHolders: [String: Int] = [:]

    /// Removes what is kept on disk for a library (its analysis, with a preview of each document,
    /// and its vocabulary, with snippets of its text) and was made from other documents than the
    /// library holds now: everything, when it holds none or is gone. It runs at the start of
    /// every refresh, so nothing of a deleted document waits for the next analysis or question
    /// to replace it, and again after each file is written, because the files are written off
    /// the main actor and the library can change while one is.
    @MainActor
    private func removeStaleKeptAnalysis(for containerId: UUID) {
        // Until the documents have been loaded the list is empty for every library, which is
        // not the same as a library having none. A refresh that runs that early removes nothing.
        guard hasAppliedLoadedDocuments else { return }
        let documentsNow =
            containerService.containers.contains { $0.id == containerId } ? documentsForContainer(containerId) : []
        if documentsNow.isEmpty {
            LibraryIntelligenceCache.remove(containerId: containerId)
        } else {
            LibraryIntelligenceCache.removeStale(
                containerId: containerId, documents: LibraryIntelligenceCache.documentsSignature(documentsNow))
        }
    }

    /// The audit's figures for one store: how many vectors are another length than the library
    /// expects, and the average, least and most words in a passage.
    ///
    /// A store keeps vectors of one length, its own, and `BNNSVectorDatabase` hands passages back
    /// without them. Through 5.6 the audit compared the (empty) vector on each passage with the
    /// library's setting, so every passage of every library on that store was counted as a
    /// mismatch. A passage that does carry a vector is still compared; one that does not is a
    /// mismatch only when the store's length differs from the library's.
    ///
    /// The words are counted a batch of passages at a time, read by id, so a large library is
    /// not all held in memory for the count, and on the concurrent pool: through 5.6 every
    /// passage's words were counted on the main actor when the audit screen opened.
    @concurrent
    nonisolated static func vectorAuditFigures(
        of database: VectorDatabase, records: [PassageRecord], storeDimension: Int, expectedDimension: Int
    ) async -> (mismatched: Int, averageWords: Double, minimumWords: Int, maximumWords: Int) {
        let storeMatches = storeDimension == expectedDimension
        var mismatched = 0
        var counted = 0
        var totalWords = 0
        var minimumWords = Int.max
        var maximumWords = 0
        var start = 0
        while start < records.count {
            let end = min(records.count, start + 2_048)
            let batch = (try? await database.chunks(withIDs: records[start..<end].map(\.id))) ?? []
            // A passage that could not be read is not in the batch. Its vector is the store's.
            mismatched += storeMatches ? 0 : (end - start) - batch.count
            for chunk in batch {
                if chunk.embedding.isEmpty {
                    mismatched += storeMatches ? 0 : 1
                } else if chunk.embedding.count != expectedDimension {
                    mismatched += 1
                }
                let words = chunk.content.split(whereSeparator: { $0.isWhitespace }).count
                totalWords += words
                minimumWords = min(minimumWords, words)
                maximumWords = max(maximumWords, words)
                counted += 1
            }
            start = end
        }
        return (
            mismatched,
            counted == 0 ? 0 : Double(totalWords) / Double(counted),
            counted == 0 ? 0 : minimumWords,
            maximumWords
        )
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
        let expectedDim = container.embeddingDim
        let records = (try? await db.passageRecords()) ?? []
        let figures = await Self.vectorAuditFigures(
            of: db, records: records, storeDimension: db.dimension, expectedDimension: expectedDim)
        let mismatched = figures.mismatched
        let avgWords = figures.averageWords
        let minWords = figures.minimumWords
        let maxWords = figures.maximumWords
        let uniqueDocs = Set(records.map(\.documentId)).count

        let audit = VectorStoreAudit(
            timestamp: Date(),
            containerId: targetId,
            containerName: container.name,
            expectedDimension: expectedDim,
            totalChunks: records.count,
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

    /// `CorpusVocabulary.build` on the concurrent pool, with the documents the passages belong
    /// to. The build runs a part-of-speech tagger over up to 4,000 passages (2.6 to 2.7 s for a
    /// library past that size, on a Mac, `LibraryAnalysisScaleBenchmarkTests`), and through 5.6
    /// it ran on the main actor in the middle of the first question after every launch.
    @concurrent
    nonisolated private static func buildVocabularyOffMainActor(
        from chunks: [DocumentChunk]
    ) async -> (vocabulary: CorpusVocabulary, documents: Set<UUID>) {
        (CorpusVocabulary.build(from: chunks), Set(chunks.map(\.documentId)))
    }

    /// Whether a vocabulary may be kept on disk for a library: only when it was built from every
    /// passage in the library's store (`passagesUsed` of `passagesStored`) and every one of them
    /// belongs to a document the library lists. A store can hold passages of a document that is
    /// not listed: one being imported in pieces (its passages are stored as each piece finishes
    /// and it is listed at the end), and one removed on another device whose passages have not
    /// been cleared here yet. A vocabulary built then holds words and snippets of that document,
    /// and nothing that removes kept files by the library's documents would ever name it.
    nonisolated static func vocabularyMayBeKept(
        passageDocuments: Set<UUID>, passagesUsed: Int, passagesStored: Int, listedDocuments: [Document]
    ) -> Bool {
        !listedDocuments.isEmpty && passagesUsed == passagesStored
            && passageDocuments.isSubset(of: Set(listedDocuments.map(\.id)))
    }

    /// A library's vocabulary for query expansion, for the first question since the library
    /// changed or the app was opened: the one kept on disk when the library is what it was when
    /// that was built, and otherwise built from `allChunks` off the main actor. Through 5.6 it
    /// was built again, on the main actor, for the first question after every launch.
    ///
    /// The caller gets a vocabulary for its own question either way. What is done with it
    /// beyond that question depends on what it is of:
    /// - It is held in memory for the library's later questions only when it is of the whole
    ///   library (`isWholeLibrary`: a question limited to named documents hands in only their
    ///   passages) and the library's documents are still the ones it was made from. The read
    ///   and the build run off the main actor, so a document can be added or deleted while they
    ///   do; the refresh that follows such a change empties the memory cache, and a vocabulary
    ///   of the library as it was must not be put back after it.
    /// - It is written to disk only when `vocabularyMayBeKept` holds as well.
    func libraryVocabulary(
        for containerId: UUID, from allChunks: [DocumentChunk], isWholeLibrary: Bool
    ) async -> CorpusVocabulary {
        let database = await dbFor(containerId)
        let passagesStored = (try? await database.count()) ?? -1
        let documents = await MainActor.run { self.documentsForContainer(containerId) }
        let signature = LibraryIntelligenceCache.signature(documents: documents, passages: passagesStored)

        var vocabulary: CorpusVocabulary?
        var mayBeKept = false
        // The kept file is of every passage in the store, so it answers only a caller that has
        // every passage. (A store with a passage it cannot read hands back fewer than it counts;
        // its vocabulary is built each launch and never kept.)
        if isWholeLibrary, !documents.isEmpty, passagesStored == allChunks.count {
            vocabulary = await LibraryIntelligenceCache.loadVocabulary(containerId: containerId, signature: signature)
        }
        if vocabulary == nil {
            let built = await Self.buildVocabularyOffMainActor(from: allChunks)
            vocabulary = built.vocabulary
            mayBeKept =
                isWholeLibrary
                && Self.vocabularyMayBeKept(
                    passageDocuments: built.documents, passagesUsed: allChunks.count, passagesStored: passagesStored,
                    listedDocuments: documents)
        }
        let result = vocabulary ?? .empty

        // One step on the main actor, so that a refresh cannot empty the cache between the check
        // and the write.
        let libraryIsUnchanged = await MainActor.run { () -> Bool in
            let unchanged =
                LibraryIntelligenceCache.documentsSignature(self.documentsForContainer(containerId))
                == signature.documents
            if unchanged, isWholeLibrary { self.corpusVocabularyCache[containerId] = result }
            return unchanged
        }
        if libraryIsUnchanged, mayBeKept {
            await LibraryIntelligenceCache.saveVocabulary(result, containerId: containerId, signature: signature)
            // Written off the main actor: see `removeStaleKeptAnalysis`.
            await MainActor.run { self.removeStaleKeptAnalysis(for: containerId) }
        }
        return result
    }

    /// Whether any passage of the store can be read: true at the first batch that hands one
    /// back. A store's records list every passage, including one whose text cannot be decoded.
    nonisolated static func holdsAReadablePassage(
        _ database: VectorDatabase, records: [PassageRecord], batch: Int = 64
    ) async throws -> Bool {
        var start = 0
        while start < records.count {
            let end = min(records.count, start + max(1, batch))
            let read = try await database.chunks(withIDs: records[start..<end].map(\.id))
            if !read.isEmpty { return true }
            start = end
        }
        return false
    }

    /// The passages a library analysis reads: every passage of the library and `newChunks`
    /// together when they fit `LibraryIntelligenceCenter.analysisPassageLimit`, and otherwise an
    /// even sample of both, read by id, with the size the sample stands for. On the concurrent
    /// pool: picking the sample walks every record of the library.
    @concurrent
    nonisolated static func libraryAnalysisInput(
        from database: VectorDatabase, adding newChunks: [DocumentChunk] = []
    ) async -> (chunks: [DocumentChunk], size: LibraryIntelligenceCenter.LibrarySize?) {
        let records = (try? await database.passageRecords()) ?? []
        guard
            let sample = LibraryIntelligenceCenter.samplePositions(
                records: records, newCount: newChunks.count,
                limit: LibraryIntelligenceCenter.analysisPassageLimit)
        else {
            let existing = (try? await database.readableChunks()) ?? []
            return (existing + newChunks, nil)
        }
        let existing = (try? await database.chunks(withIDs: sample.existing.map { records[$0].id })) ?? []
        var passagesByDocument: [UUID: Int] = [:]
        for record in records { passagesByDocument[record.documentId, default: 0] += 1 }
        for chunk in newChunks { passagesByDocument[chunk.documentId, default: 0] += 1 }
        return (
            existing + sample.new.map { newChunks[$0] },
            LibraryIntelligenceCenter.LibrarySize(
                passages: records.count + newChunks.count, passagesByDocument: passagesByDocument)
        )
    }

    private func generateIntelligenceSnapshot(
        for containerId: UUID?,
        force: Bool,
        allowSelfTuningScheduling: Bool
    ) async {
        let resolvedId: UUID? = await MainActor.run {
            containerId ?? self.containerService.activeContainerId
        }
        guard let targetId = resolvedId else { return }

        // A library that is gone has nothing to analyse. (Deleting a library removes its
        // documents one at a time, and each removal asks for a refresh that runs after the
        // library has left the list. `dbFor` answers with the active library's store for an id
        // it does not know, so that refresh used to analyse another library under this id.)
        let libraryExists = await MainActor.run {
            self.containerService.containers.contains { $0.id == targetId }
        }
        guard libraryExists else {
            LibraryIntelligenceCache.remove(containerId: targetId)
            await MainActor.run {
                self.containerIntelligence.removeValue(forKey: targetId)
                self.containerIntelligenceSignature.removeValue(forKey: targetId)
            }
            return
        }

        let docs = await MainActor.run { self.documentsForContainer(targetId) }
        let database = await dbFor(targetId)
        // Through 5.6 this read every passage and analysed all of the text each time a library
        // was opened and after each import: 199 s, and 1,054 MB over what the app held, for
        // 144,247 passages on a Mac. The analysis is now kept on disk under a signature of the
        // library it was made from and read back while the library is unchanged, and a large
        // library is analysed from a sample of its passages (`libraryAnalysisInput`).
        let passageCount = (try? await database.count()) ?? 0
        let signature = LibraryIntelligenceCache.signature(documents: docs, passages: passageCount)

        // A report made earlier this session stands while it is still about this library. It
        // used to stand until a forced refresh, so a library changed underneath by sync went on
        // showing, and being tuned from, the report of what it had been.
        let shouldSkip = await MainActor.run { () -> Bool in
            if force { return false }
            return self.containerIntelligence[targetId] != nil
                && self.containerIntelligenceSignature[targetId] == signature
        }
        if shouldSkip { return }

        // Whether the library is still the one `signature` describes. Asked after anything that
        // ran off the main actor, during which a document can have been added or deleted.
        func libraryIsUnchanged() async -> Bool {
            let passagesNow = (try? await database.count()) ?? -1
            let documentsNow = await MainActor.run { () -> [Document]? in
                self.containerService.containers.contains { $0.id == targetId }
                    ? self.documentsForContainer(targetId) : nil
            }
            return documentsNow.map { LibraryIntelligenceCache.signature(documents: $0, passages: passagesNow) }
                == signature
        }

        let report: LibraryIntelligenceCenter.IntelligenceReport
        var reportIsCurrent = true
        var kept: LibraryIntelligenceCenter.IntelligenceReport?
        if !force {
            kept = await LibraryIntelligenceCache.loadReport(containerId: targetId, signature: signature)
        }
        if let kept {
            report = kept
            reportIsCurrent = await libraryIsUnchanged()
            Log.info(
                "[Intelligence] Library \(targetId): using the analysis kept on disk "
                    + "(\(passageCount) passages, unchanged since it was made)"
                    + (reportIsCurrent ? "" : "; the library changed while it was read"),
                category: .pipeline)
        } else {
            let started = Date()
            let input = await Self.libraryAnalysisInput(from: database)
            report = await intelligenceCenter.analyzeLibrary(
                documents: docs,
                chunks: input.chunks,
                library: input.size
            )
            // The analysis takes seconds, and a document can be deleted or added while it runs.
            // A report of the library as it was is not kept: it would hold a preview of a
            // document that may just have been deleted, under a name nothing would replace.
            reportIsCurrent = await libraryIsUnchanged()
            if reportIsCurrent, !docs.isEmpty {
                await LibraryIntelligenceCache.saveReport(report, containerId: targetId, signature: signature)
                // The file was written off the main actor. If the library's documents changed
                // while it was, the refresh that follows that change may already have looked
                // for stale files, so they are looked for again now that this one exists.
                await MainActor.run { self.removeStaleKeptAnalysis(for: targetId) }
            }
            Log.info(
                "[Intelligence] Library \(targetId): analysed \(report.corpus.analysedChunkCount) of "
                    + "\(report.corpus.chunkCount) passages in "
                    + "\(String(format: "%.0f", Date().timeIntervalSince(started) * 1000))ms"
                    + (reportIsCurrent ? "" : "; the library changed meanwhile, so the report is not kept"),
                category: .pipeline)
        }

        await MainActor.run {
            self.containerIntelligence[targetId] = report
            // Without a signature the next refresh, forced or not, makes the report again.
            self.containerIntelligenceSignature[targetId] = reportIsCurrent ? signature : nil
        }

        // Nothing is tuned from a report of what the library was a moment ago; the refresh that
        // follows the change decides. The library is read again here because its settings can
        // have been edited while the analysis ran.
        guard reportIsCurrent else { return }
        guard
            let container = await MainActor.run(
                resultType: KnowledgeContainer?.self,
                body: {
                    self.containerService.containers.first { $0.id == targetId }
                }
            )
        else { return }
        guard container.autoAdaptDimension else { return }

        // A report made from a sample can move the chunking settings, as any report can, and
        // never asks for another embedding model (see `resolveAutoAdjustments`).
        let (updated, reasons) = Self.resolveAutoAdjustments(for: container, report: report)
        guard !reasons.isEmpty else { return }

        let requiresRebuild =
            !report.corpus.isEstimate
            && Self.evaluateEmbeddingShift(container: container, plan: report.embedding) != nil

        if !requiresRebuild {
            // Chunking strategy/window shifts DO NOT require a full database rebuild.
            // We can dynamically apply them directly to the container configuration.
            if updated != container {
                await MainActor.run {
                    self.containerService.updateContainer(updated)
                }
                Log.info(
                    "[SelfTuning] Dynamically adjusted chunking configuration for container \(targetId): \(reasons.joined(separator: " | ")). No rebuild required.",
                    category: .ingestion
                )
            }
            return
        }

        if !allowSelfTuningScheduling {
            Log.info(
                "[SelfTuning] Skipping automatic rebuild/config change during standard ingestion for container \(targetId). Explicit rebuild required for: \(reasons.joined(separator: " | "))",
                category: .ingestion
            )
            return
        }

        if updated != container {
            await MainActor.run {
                self.containerService.updateContainer(updated)
            }
        }

        scheduleSelfTuningRebuild(for: targetId, reasons: reasons)
    }

    @MainActor
    func documentsForContainer(_ containerId: UUID) -> [Document] {
        let defaultContainerId = containerService.containers.first?.id
        return documents.filter { document in
            if let docContainer = document.containerId {
                return docContainer == containerId
            } else {
                return containerId == defaultContainerId
            }
        }
    }

    // MARK: - Published State (MainActor-isolated for SwiftUI)

    /// The container context for the currently executing query (if any).
    /// Used to scope agentic tool calls and document listings during an in-flight query.
    @MainActor var currentQueryContainerId: UUID? = nil

    /// Tracks whether the last query used agentic (deep) mode or single-pass.
    /// Used by UI to show "Go Deeper" button when single-pass was used.
    @MainActor @Published var lastQueryUsedAgentic: Bool = false

    /// The last query text, for re-querying with forced agentic mode.
    @MainActor var lastQueryText: String? = nil

    /// Forces the next query to use agentic mode regardless of complexity detection.
    @MainActor var forceAgenticOnNextQuery: Bool = false

    /// Documents the plan's document limit counts (5.8): not those in the guide library, nor the app's own guides
    /// anywhere (`isAppGuide`, which the app sets), so the guides someone imported into General before 5.8 don't use
    /// three of a free plan's five.
    @MainActor var countedDocumentCount: Int {
        documents.filter { !containerService.isGuideLibrary($0.containerId) && !isAppGuide($0) }.count
    }

    /// Whether a document is one of the app's guides. The app sets it (`SampleDocumentManager`), which the engine
    /// can't see.
    @MainActor var isAppGuide: (Document) -> Bool = { _ in false }

    @MainActor @Published var documents: [Document] = [] {
        // What each library's count shows (5.8, `ContainerService.documentCount`).
        didSet {
            documentsChangeCount &+= 1
            containerService.setListedDocumentCounts(
                ContainerService.documentCounts(
                    of: documents.map(\.containerId), defaultLibrary: containerService.containers.first?.id))
        }
    }
    /// Counts every change to `documents`. A workspace reload reads the list off the main thread and applies
    /// it only if this has not moved since it started, so an edit, a deletion or an import made during the
    /// read is never replaced by the older copy it read (5.8).
    @MainActor var documentsChangeCount = 0
    /// The newest workspace reload asked of this engine; an older one still reading is dropped (5.8).
    @MainActor var latestWorkspaceReload = 0
    /// Deletions made in the app that can still be undone (5.7, `PendingDocumentRemoval`): their documents are
    /// out of `documents` and not removed yet.
    @MainActor @Published var pendingRemovals: [PendingDocumentRemoval] = []
    /// Each pending removal's timer, what runs before it, and its entry in an undo manager.
    @MainActor var pendingRemovalWork: [UUID: PendingDocumentRemovalWork] = [:]
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var processingStatus: String = ""
    @MainActor @Published var lastError: String? = nil  // User-facing error message
    @MainActor @Published var lastProcessingSummary: ProcessingSummary? = nil  // Detailed completion stats
    @MainActor @Published var ingestionItems: [IngestionItem] = []
    @MainActor @Published var retrievalHistory: [RetrievalLogEntry] = []
    @MainActor @Published var pendingCloudConsent: CloudTransmissionRecord?
    @MainActor @Published var lastCloudTransmission: CloudTransmissionRecord?
    @MainActor @Published var cloudConsent: [CloudProvider: CloudConsentState] = [:]
    /// The signature of the library each report in `containerIntelligence` was made from
    /// (`LibraryIntelligenceCache.signature`). None for a report that is not of the library as
    /// it is on disk.
    @MainActor var containerIntelligenceSignature: [UUID: LibraryIntelligenceCache.Signature] = [:]
    /// False from the service's creation until the documents read from disk have been applied.
    @MainActor var hasAppliedLoadedDocuments = false
    /// Whether the stored documents have been read and applied since this engine started (5.7). Until then
    /// `documents` is not the catalog, so nothing that asks "does a document name this file" may act on it.
    @MainActor var hasLoadedDocumentsFromDisk: Bool { hasAppliedLoadedDocuments }
    @MainActor @Published var containerIntelligence: [UUID: LibraryIntelligenceCenter.IntelligenceReport] =
        [:]
    @MainActor @Published var chatHistories: [UUID: [ChatMessage]] = [:]
    @MainActor @Published var activeThreadId: UUID? = nil
    @MainActor @Published var activeThreadIds: [UUID: UUID] = [:]
    @MainActor @Published var thinkingEvents: [ThinkingEvent] = []

    /// Libraries that hold documents but cannot answer semantically, because
    /// their vector store is missing or empty and automatic repair is suppressed.
    ///
    /// Drives a visible rebuild action. Without this the state is invisible: the
    /// library lists its documents, keyword search still works, and semantic
    /// retrieval silently returns nothing — which reads to the user as "the app
    /// says my document doesn't mention this."
    @MainActor @Published var librariesNeedingIndexRebuild: Set<UUID> = []
    @MainActor @Published var lastAuditSnapshot: RAGAuditSnapshot?
    @MainActor @Published private(set) var lastVectorAudit: VectorStoreAudit?

    /// Live token counter for Deep Think mode - updates in real-time as each step completes
    @MainActor @Published var deepThinkLiveTokens: Int = 0
    /// Live step counter for Deep Think mode - updates in real-time
    @MainActor @Published var deepThinkLiveSteps: Int = 0
    /// Live confidence meter for Maximum mode - updates as reasoning progresses toward 98%
    @MainActor @Published var deepThinkLiveConfidence: Float = 0

    /// Tracks the active agentic query task so it can be cancelled when a new query arrives.
    /// Without this, sending a second Deep Think/Maximum query while one is running causes
    /// both orchestrators to compete for the Apple FM model, freezing the app.
    @MainActor var activeAgenticTask: Task<RAGResponse, Error>? = nil

    /// Cached corpus vocabulary per container to avoid expensive rebuilds on each query
    @MainActor var corpusVocabularyCache: [UUID: CorpusVocabulary] = [:]

    /// Memory warning observer — evicts corpus vocabulary cache under pressure
    @MainActor private var memoryWarningObserver: (any NSObjectProtocol)?

    /// Published model name for UI binding - updates when LLM service changes
    @MainActor @Published private(set) var activeModelName: String = "Loading..."
    @MainActor var selfTuningInFlight: Set<UUID> = []

    /// Track when containers last completed ingestion to prevent immediate self-tuning rebuilds.
    /// Self-tuning should analyze library content AFTER all documents are ingested, not after each one.
    /// This prevents the scenario where a large PDF finishes and immediately triggers re-embedding
    /// of ALL documents (including the one just processed).
    @MainActor var lastIngestionCompletionTime: [UUID: Date] = [:]

    /// Minimum cooldown (in seconds) after ingestion before allowing self-tuning rebuilds.
    /// This gives time for the batch to complete and prevents wasteful immediate rebuilds.
    static let selfTuningCooldownSeconds: TimeInterval = 30.0

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
    @MainActor var pendingReembedContainerIds: Set<UUID> = []
    @MainActor var pendingReembedTask: Task<Void, Never>?
    /// When true, suppress automatic reembed kicks (used during onboarding batch import)
    @MainActor var suppressReembedKicks: Bool = false

    var totalChunksStored: Int = 0
    let retrievalHistoryLimit = 50

    // MARK: - Public Access (for Settings)

    var llmService: LLMService {
        return _llmService
    }

    var _llmService: LLMService
    var _fallbackServices: [LLMService] = []

    enum ChunkingDefaults {
        static let targetWindow = 350  // Larger chunks = more context per chunk
        static let overlap = 60  // ~17% overlap - sufficient without redundancy
    }

    struct EmbeddingAutoAction {
        let providerId: String
        let dimension: Int
        let reason: String
    }

    /// Snapshot of the embedding configuration for the active query/document scope
    struct EmbeddingContext {
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

    struct ChunkAutoAction {
        let directive: ChunkingDirective
        let reason: String
    }

    enum ConsentDefaults {
        static func key(for provider: CloudProvider) -> String {
            switch provider {
            case .applePCC: return "cloudConsent.applePCC"
            }
        }
    }

    struct PersistedIngestionContext: Codable, Sendable {
        let id: UUID
        let context: IngestionContext
    }

    struct PersistedIngestionQueueState: Codable, Sendable {
        let items: [IngestionItem]
        let contexts: [PersistedIngestionContext]
        let tombstones: [IngestionQueueTombstone]
        let updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case items
            case contexts
            case tombstones
            case updatedAt
        }

        init(
            items: [IngestionItem],
            contexts: [PersistedIngestionContext],
            tombstones: [IngestionQueueTombstone],
            updatedAt: Date
        ) {
            self.items = items
            self.contexts = contexts
            self.tombstones = tombstones
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([IngestionItem].self, forKey: .items)
            contexts = try container.decode([PersistedIngestionContext].self, forKey: .contexts)
            tombstones = try container.decodeIfPresent([IngestionQueueTombstone].self, forKey: .tombstones) ?? []
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }
    }

    // MARK: - Initialization

    /// Engines alive in this process, for the development journal's `engines` field (5.8): the app's own, plus any an
    /// action builds for one question. Two windows on the Mac used to make one each (row "Every Mac window runs its
    /// own engine and sync").
    nonisolated static var liveEngineCount: Int { engineCountLock.withLock { engineCountValue } }
    nonisolated private static let engineCountLock = NSLock()
    nonisolated(unsafe) private static var engineCountValue = 0

    deinit {
        RAGService.engineCountLock.withLock { RAGService.engineCountValue -= 1 }
    }

    init(
        documentProcessor: DocumentProcessor? = nil,
        embeddingService: EmbeddingService? = nil,
        vectorDatabase _: VectorDatabase? = nil,
        llmService: LLMService? = nil,
        containerService: ContainerService? = nil,
        vectorRouter: VectorStoreRouter? = nil,
        entitlementStore: EntitlementStore? = nil
    ) {
        RAGService.engineCountLock.withLock { RAGService.engineCountValue += 1 }
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

            // Try to instantiate the user's selected model first
            let primaryService = Self.instantiateService(
                for: selectedModelRaw,
                entitlementStore: entitlementStore
            )
            var fallbackServices = Self.buildFallbackChain(excluding: selectedModelRaw)

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
                // No LLM available - check for screenshot mode first.
                //
                // Nothing goes into `lastError` here (5.7). The Documents screen shows `lastError` as
                // "Error Processing Document", and through 5.6 an engine started without the model put
                // "Apple Intelligence is required but unavailable. Enable it in Settings" there, also on
                // devices that can never run it, while documents import and search without it. The empty
                // chat's notice and the mode chip say it by reason (`AppleIntelligenceCopy`).
                #if targetEnvironment(simulator)
                    if ScreenshotMockLLMService.isScreenshotMode {
                        Log.info("📸 Screenshot mode: Using mock LLM for demo", category: .initialization)
                        resolvedService = ScreenshotMockLLMService()
                    } else {
                        Log.error(
                            "No configured LLM available; Apple Intelligence is REQUIRED",
                            category: .initialization
                        )
                        resolvedService = AppleFoundationLLMServiceUnavailable()
                    }
                #else
                    Log.error(
                        "No configured LLM available; Apple Intelligence is REQUIRED",
                        category: .initialization
                    )
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
            var states = self.loadPersistedConsentStates()
            if let validationConsent = self.getLaunchArgumentValue(for: "rag-validation-pcc-consent") {
                let normalized = validationConsent.lowercased().starts(with: "allow") ? "allowed" : "denied"
                if let state = CloudConsentState(rawValue: normalized) {
                    states[.applePCC] = state
                    Log.info("[Consent] Applying launch-argument override: \(normalized)", category: .initialization)
                }
            }
            self.cloudConsent = states
        }
        loadDocumentsFromDisk()

        Task { @MainActor [weak self] in
            guard let self else { return }
            IngestionRuntimeBridge.shared.configureContinuedIngestion(
                run: { [weak self] in
                    guard let self else { return false }
                    return await self.runPendingIngestionQueue()
                },
                expiration: { [weak self] in
                    self?.handleContinuedIngestionExpiration(backgroundTimeRanOut: true)
                }
            )
            IngestionRuntimeBridge.shared.restoreLiveActivityIfNeeded()
            await self.restorePersistedIngestionQueueIfNeeded()
        }

        // Connect document summary service to self for LLM access
        Task {
            await self.documentSummaryService.setRAGService(self)
        }

        // Log GPU acceleration status at startup
        Task {
            let gpuService = GPUComputeService.shared
            if gpuService.isGPUAvailable {
                Log.info(
                    "🚀 GPU Compute: \(gpuService.deviceName) ready for vector operations", category: .initialization)
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
            Task { @MainActor [weak self] in
                guard let self else { return }
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
                            Log.warning(
                                "[RAGService] ⚠️ Memory warning — evicted \(count) corpus vocabulary caches",
                                category: .retrieval)
                        }
                    }
                }
            }
        #endif

        // Observe active model route changes to update activeModelName in real-time
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ActiveModelRouteResolved"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let modelName = notification.userInfo?["modelName"] as? String {
                Task { @MainActor in
                    self.activeModelName = modelName
                }
            }
        }

        // Register active presented instance now that all properties are initialized
        // Only when no engine holds the place: an engine an action builds for one question must
        // not take over from the app's own. `ContentView` sets the app's engine itself.
        let currentInstance = self
        Task { @MainActor in
            if RAGService.activePresentedInstance == nil {
                RAGService.activePresentedInstance = currentInstance
            }
        }
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

                    Log.debug(
                        "[RAGService] Container changed: \(oldContainerId?.uuidString.prefix(8) ?? "nil") → \(newContainerId.uuidString.prefix(8))",
                        category: .initialization)

                    // Save transcript for the old container (if any)
                    if let oldId = oldContainerId {
                        self.saveSessionTranscript(for: oldId)
                    }

                    // Restore transcript for the new container
                    self.restoreSessionTranscript(for: newContainerId)

                    // Check the library can actually answer before the user asks.
                    Task { @MainActor [weak self] in
                        await self?.evaluateSemanticIndexHealth(for: newContainerId)
                    }

                    // Update tracking
                    self.previousContainerId = newContainerId
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - LLM Service Management

    /// Dynamically updates the LLM service (called from Settings)
    func updateLLMService(_ newService: LLMService) async {
        await MainActor.run {
            self._llmService = newService
            self.activeModelName = newService.modelName  // Update published property for UI
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

        let docsSnapshot = await snapshotDocuments()
        // Passages whose document is in no library are left out (5.7, `passagesFromKnownDocuments`), before the
        // list is cut to `topK`, so the screen still shows up to `topK` and numbers them without gaps.
        let named = candidates.map { chunk in
            RetrievedChunk(
                chunk: chunk.chunk,
                similarityScore: chunk.similarityScore,
                rank: chunk.rank,
                sourceDocument: docsSnapshot.first(where: { $0.id == chunk.chunk.documentId })?.filename ?? "Unknown",
                pageNumber: chunk.chunk.metadata.pageNumber
            )
        }
        let enriched = Self.passagesFromKnownDocuments(named, knownDocumentIds: Set(docsSnapshot.map(\.id))).kept
            .prefix(topK).enumerated().map { index, chunk in
                RetrievedChunk(
                    chunk: chunk.chunk,
                    similarityScore: chunk.similarityScore,
                    rank: index + 1,
                    sourceDocument: chunk.sourceDocument,
                    pageNumber: chunk.pageNumber
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

    // MARK: - MainActor snapshot helpers (async to avoid superfluous await warnings)

    nonisolated func snapshotDocuments() async -> [Document] {
        await MainActor.run { self.documents }
    }

    nonisolated func snapshotDocumentsCount() async -> Int {
        await MainActor.run { self.documents.count }
    }

    nonisolated func documentName(for documentId: UUID) async -> String {
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

    // MARK: - MMR (Maximal Marginal Relevance) for Diversity

    // MARK: - Stored properties of the extension files (5.8 split: a property must stay in the class)
    /// Set by `finishAnswerNow()`, cleared when the next query starts.
    @MainActor var finishAnswerNowRequested = false
    /// The source-only check in flight, held so `finishAnswerNow()` can cancel it.
    @MainActor var activeSourceOnlyCheck: Task<SourceOnlyAnswerOutcome?, Never>?
    /// Cancels the finishable stage in flight, and any it was started inside.
    @MainActor var cancelFinishableStage: (() -> Void)?
    /// Removals that have started and not finished, each with its documents (5.7).
    @MainActor var removalsRunning: [UUID: (task: Task<Void, Never>, documentIds: Set<UUID>)] = [:]
    /// The collector in force for the current `queryWithAudit`, or nil. See that method for why
    /// this is a property rather than a parameter, and for the concurrency caveat.
    var activeRetrievalTrace: RetrievalTraceCollector?
}
