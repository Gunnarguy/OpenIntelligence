//
//  RAGService+ImportEnrichment.swift
//  OpenIntelligence
//
//  Part of RAGService, moved from RAGService+Import.swift on 2026-11-07 (5.8 split); only access keywords changed.
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
    /// The model work an import does after its document is saved (5.7): the RAPTOR-lite overview, the
    /// content tags and the suggested questions. None of it is needed to search or answer from the
    /// document. Through 5.6 the overview and the tags ran before the save, so iOS ending a background
    /// import during them stopped it before its document was recorded.
    func enrichImportedDocument(
        _ document: Document,
        chunks documentChunks: [DocumentChunk],
        container: KnowledgeContainer?,
        embeddingService containerEmbeddingService: EmbeddingService,
        db: VectorDatabase,
        context: IngestionContext,
        trackingId: UUID?,
        containerId activeContainerId: UUID
    ) async {
        let filename = document.filename
        let chunkTexts = documentChunks.map(\.content)

        // Step 4.5: Generate document summary (RAPTOR-lite)
        // Creates a level-1 summary chunk for efficient overview queries
        // Controlled by settings.enableDocumentSummaries
        // Skipped for onboarding samples. This is a language-model call with a 12s
        // timeout (`DocumentSummaryService.summaryGenerationTimeoutSeconds`) and it
        // runs once per document. Together with content tagging below, it was the
        // reason importing three small curated markdown files took **1.3 minutes** on
        // an A18 Pro: 3,168 words and 38 chunks, of which the embedding work is a
        // fraction of a second and the enrichment is up to 20s per document.
        //
        // The samples exist to demonstrate the pipeline, and the theater the user is
        // watching shows Extract, Chunk, Embed and Index. An auto-generated overview
        // of a document the app itself wrote adds nothing to that, and a first
        // impression that takes over a minute costs more than the summary is worth.
        // Anything the user imports themselves is unaffected.
        let summariesEnabled =
            await MainActor.run { self.settingsStore?.enableDocumentSummaries ?? true }
            && context != .onboarding

        if summariesEnabled {
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .storing,
                    detail: "Optimizing overview...",
                    progress: 0.98
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

                // The overview takes up to 12 s to write, and the document can be deleted meanwhile
                // (`enrichmentTargetState`, 5.7).
                if await enrichmentTargetState(document.id) != .listed {
                    Log.info(
                        "[RAGService] Not storing the overview of '\(filename)': the document was deleted while it was written",
                        category: .ingestion)
                } else {
                    // Store the summary chunk alongside detail chunks
                    try await db.storeBatch(chunks: [summaryChunk])
                    try await db.persist()

                    if await enrichmentTargetState(document.id) == .removalStarted {
                        // The deletion began while the overview was stored and may have taken the document's
                        // passages out before it, so the overview is taken out here.
                        do {
                            try await db.deleteChunks(forDocument: document.id)
                            Log.info(
                                "[RAGService] Took out the overview of '\(filename)': the document was deleted while it was stored",
                                category: .ingestion)
                        } catch {
                            Log.error(
                                "[RAGService] Could not take out the overview of '\(filename)', whose document was deleted while it was stored: \(error.localizedDescription)",
                                category: .ingestion)
                        }
                    } else {
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
                    }
                }
            } catch {
                // Summary generation is optional - log but don't fail ingestion
                Log.warning(
                    "[RAGService] Summary generation failed for '\(filename)': \(error)", category: .ingestion)
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
                detail: "Generating tags...",
                progress: 0.99
            )
        }

        var generatedContentTags: [String]?
        // Skipped for onboarding samples, same reasoning as the summary above: this is
        // a language-model call with an 8s timeout, once per document.
        let contentTaggingEnabled =
            await contentTaggingEnabled(for: container)
            && context != .onboarding
        if #available(iOS 26.0, *), contentTaggingEnabled {
            let taggingService = ContentTaggingService.shared
            if taggingService.isAvailable {
                do {
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

        if let tags = generatedContentTags {
            await MainActor.run {
                if let index = documents.firstIndex(where: { $0.id == document.id }) {
                    let saved = documents[index]
                    documents[index] = Document(
                        id: saved.id,
                        filename: saved.filename,
                        fileURL: saved.fileURL,
                        storageRelativePath: saved.storageRelativePath,
                        fileHash: saved.fileHash,
                        contentType: saved.contentType,
                        addedAt: saved.addedAt,
                        totalChunks: saved.totalChunks,
                        processingMetadata: saved.processingMetadata,
                        containerId: saved.containerId,
                        contentTags: tags
                    )
                }
            }
            await saveDocumentsToDisk()
        }

        // Generate suggested questions for the document
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .storing,
                detail: "Generating suggested questions...",
                progress: 0.99
            )
        }
        guard await enrichmentTargetState(document.id) == .listed else {
            Log.info(
                "[RAGService] No suggested questions for '\(filename)': the document was deleted after its import",
                category: .ingestion)
            return
        }
        await SuggestedQuestionsService.shared.generateQuestionsForIngestedDocument(
            document,
            chunks: documentChunks,
            in: activeContainerId
        )
        if await enrichmentTargetState(document.id) == .removalStarted {
            await SuggestedQuestionsService.shared.removeQuestions(for: document.id, in: activeContainerId)
        }
    }

    /// Where a document stands for the model work that follows its import (5.7), which takes seconds per step:
    /// listed (in the list, or out of it for its undo seconds), recorded as deleted, which `removeDocument` and
    /// `clearAllDocuments` do before they take anything out, or neither. Since that work moved after the document
    /// is saved (2026-10-15, during 5.7), a document deleted while its overview was written kept that overview as
    /// a passage of no document, and later answers cited it as "Unknown Document Summary" (seen in the iOS 27
    /// Simulator on 2026-10-19, `ShortcutsActionTests`); no release had it. What a step makes is stored only for a
    /// listed document, and taken out again when the deletion began while it was stored. A document in its undo
    /// seconds gets its overview and questions: an Undo brings it back with them, and a removal that runs takes them
    /// out with the rest (review, 2026-10-19).
    enum EnrichmentTargetState: Equatable { case listed, unlisted, removalStarted }

    private func enrichmentTargetState(_ id: UUID) async -> EnrichmentTargetState {
        let url = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        if let data = try? Data(contentsOf: url), let ids = try? JSONDecoder().decode([String].self, from: data),
            ids.contains(id.uuidString)
        {
            return .removalStarted
        }
        let listed = await MainActor.run { self.documents.contains { $0.id == id } || self.isRemovalPending(id) }
        return listed ? .listed : .unlisted
    }

    /// Whether a saved document's overview, tags and suggested questions wait instead of running before the next
    /// file (5.7 in the background; 5.8 also while other files are queued). An onboarding sample never waits: its
    /// overview is skipped altogether.
    nonisolated static func shouldDeferEnrichment(
        appIsInBackground: Bool, otherFilesQueued: Bool, isOnboarding: Bool
    ) -> Bool {
        !isOnboarding && (appIsInBackground || otherFilesQueued)
    }

    /// Waits while the app is in the background, and returns how long it waited (5.8). A model call that
    /// iOS refuses there goes on when the app is opened; a suspended app's wait simply pauses. Waiters are
    /// counted, so the answer reads as paused until the last of them goes on.
    @MainActor static func waitWhileAppIsInBackground() async -> TimeInterval {
        let started = Date()
        guard appIsInBackground else { return 0 }
        backgroundWaiters += 1
        if backgroundWaiters == 1 {
            // The answer's Live Activity and the system's task card say "Paused, tap to resume" while it waits.
            NotificationCenter.default.post(name: answerPausedNotification, object: nil, userInfo: ["paused": true])
        }
        while appIsInBackground, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
        backgroundWaiters -= 1
        if backgroundWaiters == 0 {
            NotificationCenter.default.post(name: answerPausedNotification, object: nil, userInfo: ["paused": false])
        }
        return Date().timeIntervalSince(started)
    }

    @MainActor private static var backgroundWaiters = 0

    /// Posted with `["paused": Bool]` when an answer starts and stops waiting for the app to come back (5.8).
    nonisolated static let answerPausedNotification = Notification.Name("OpenIntelligence.answerPausedForBackground")

    /// Whether the app is in the background, where iOS ends an import that stalls (5.7).
    @MainActor static var appIsInBackground: Bool {
        #if canImport(UIKit)
            UIApplication.shared.applicationState == .background
        #else
            false
        #endif
    }

    /// Documents whose overview, tags and suggested questions wait for the app to be in front (5.7),
    /// each as "<library id> <document id>".
    nonisolated static let deferredEnrichmentKey = "deferredDocumentEnrichment"

    nonisolated static func deferredEnrichments(defaults: UserDefaults = .standard) -> [(document: UUID, library: UUID)] {
        (defaults.stringArray(forKey: deferredEnrichmentKey) ?? []).compactMap { entry in
            let parts = entry.split(separator: " ")
            guard parts.count == 2, let library = UUID(uuidString: String(parts[0])),
                let document = UUID(uuidString: String(parts[1]))
            else { return nil }
            return (document, library)
        }
    }

    nonisolated static func deferEnrichment(
        of document: UUID, in library: UUID, defaults: UserDefaults = .standard
    ) {
        let entry = "\(library.uuidString) \(document.uuidString)"
        var entries = defaults.stringArray(forKey: deferredEnrichmentKey) ?? []
        guard !entries.contains(entry) else { return }
        entries.append(entry)
        defaults.set(entries, forKey: deferredEnrichmentKey)
    }

    nonisolated static func finishDeferredEnrichment(of document: UUID, defaults: UserDefaults = .standard) {
        let entries = (defaults.stringArray(forKey: deferredEnrichmentKey) ?? []).filter {
            !$0.hasSuffix(document.uuidString)
        }
        defaults.set(entries, forKey: deferredEnrichmentKey)
    }

    /// Runs the model work background imports left for later, one document at a time, while the app
    /// is in front and no import is running (5.7). Called when the app comes to the front and when the
    /// import queue empties. A document deleted in the meantime is dropped from the list.
    @MainActor
    func runDeferredEnrichmentsIfNeeded() {
        guard !deferredEnrichmentIsRunning, !isProcessing, !Self.appIsInBackground else { return }
        let pending = Self.deferredEnrichments()
        guard !pending.isEmpty else { return }
        deferredEnrichmentIsRunning = true
        Task { @MainActor in
            defer {
                deferredEnrichmentIsRunning = false
                if !isProcessing { processingStatus = "" }
            }
            for item in pending {
                guard !Self.appIsInBackground, !isProcessing else { return }
                guard let document = documents.first(where: { $0.id == item.document }) else {
                    Self.finishDeferredEnrichment(of: item.document)
                    continue
                }
                let container = containerService.containers.first { $0.id == item.library }
                guard let db = try? await dbForContainer(item.library),
                    let stored = try? await db.chunks(forDocument: document.id), !stored.isEmpty
                else { continue }
                let chunks = stored.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
                let service = EmbeddingService.forProvider(
                    id: container?.embeddingProviderId ?? "coreml_sentence_embedding",
                    targetDimension: container?.embeddingDim ?? 384,
                    allowFallback: true)
                Log.info(
                    "[RAGService] Adding the overview, tags and suggested questions that waited for '\(document.filename)'",
                    category: .ingestion)
                let enrichmentStarted = Date()
                VerificationJournal.record(
                    "import.deferredEnrichment", .started, ["document": VerificationJournal.anon(document.id)])
                await enrichImportedDocument(
                    document, chunks: chunks, container: container, embeddingService: service, db: db,
                    context: .userInitiated, trackingId: nil, containerId: item.library)
                Self.finishDeferredEnrichment(of: document.id)
                VerificationJournal.record(
                    "import.deferredEnrichment", .ok, durationMs: Date().timeIntervalSince(enrichmentStarted) * 1000,
                    ["document": VerificationJournal.anon(document.id),
                        "tags": "\(documents.first { $0.id == document.id }?.contentTags?.count ?? 0)"])
            }
        }
    }

}
