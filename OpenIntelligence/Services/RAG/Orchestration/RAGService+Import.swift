//
//  RAGService+Import.swift
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
    // MARK: - Document Management

    /// Add a document to the knowledge base
    /// This performs the full ingestion pipeline: parse → chunk → embed → store
    /// - Parameter containerId: the library to import into. `nil`, or a library that no longer exists,
    ///   means the active one.
    func addDocument(
        at url: URL,
        context: IngestionContext = .userInitiated,
        trackingId: UUID? = nil,
        manageProcessingState: Bool = true,
        containerId: UUID? = nil,
        documentId reusedDocumentId: UUID? = nil
    ) async throws {
        let managedURL = try prepareManagedDocumentURL(from: url)
        try await WorkspaceSyncService.ensureItemAvailableLocally(at: managedURL)
        let filename = managedURL.lastPathComponent
        let managedRelativePath = AppSupportPaths.relativePath(for: managedURL)
        let activeContainerId = await resolveImportLibrary(containerId: containerId, context: context)

        let documentHash = await hashAndRecordDocument(managedURL: managedURL, filename: filename, trackingId: trackingId, managedRelativePath: managedRelativePath)

        // A rebuild's document is the one being replaced (5.8): a sync pass while it ran can have put its record back.
        if reusedDocumentId == nil, let existingDocument = await MainActor.run(
            resultType: Document?.self,
            body: {
                self.existingImportedDocument(
                    in: activeContainerId,
                    storageRelativePath: managedRelativePath,
                    fileHash: documentHash
                )
            })
        {
            Log.info(
                "[RAGService] Skipping already imported document '\(filename)' (existing id: \(existingDocument.id.uuidString))",
                category: .ingestion
            )

            // The user asked for this file. If a previous deletion tombstoned this id,
            // skipping here without clearing it would leave the record to be erased by
            // the next sync, with nothing left to recreate it.
            await MainActor.run {
                self.clearDeletionTombstones(for: [existingDocument.id])
            }

            await MainActor.run {
                if let trackingId {
                    self.updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .complete,
                        detail: "Already imported",
                        progress: 1.0,
                        errorMessage: nil
                    ) { metrics in
                        if let meta = existingDocument.processingMetadata {
                            metrics.fileSizeMB = meta.fileSizeMB
                            metrics.totalCharacters = meta.totalCharacters
                            metrics.totalWords = meta.totalWords
                            metrics.pageCount = meta.pagesProcessed ?? 0
                            metrics.ocrPagesCount = meta.ocrPagesCount ?? 0
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

                            metrics.chunkCount = existingDocument.totalChunks
                            metrics.embeddingsGenerated = existingDocument.totalChunks

                            metrics.extractionTimeMs = Int(meta.extractionTimeSeconds * 1000)
                            metrics.chunkingTimeMs = Int(meta.chunkingTimeSeconds * 1000)
                            metrics.embeddingTimeMs = Int(meta.embeddingTimeSeconds * 1000)
                            metrics.totalTimeMs = Int(meta.totalProcessingTimeSeconds * 1000)
                            metrics.documentDomain = meta.documentCategory?.rawValue ?? ""
                        } else {
                            metrics.chunkCount = existingDocument.totalChunks
                            metrics.embeddingsGenerated = existingDocument.totalChunks
                        }
                    }
                }

                if manageProcessingState { self.isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    self.processingStatus = ""
                }
                self.lastError = nil
                self.kickPendingReembedIfNeeded()
            }
            return
        }

        // Onboarding sample docs bypass quota — they're educational material
        // that ships with the app, not user-generated content
        // A rebuild re-imports a document already counted (5.8): its record stays listed, so at the plan's limit the
        // check refused it and left it with no passages (review, 2026-11-03).
        let skipQuota = (context == .onboarding) || reusedDocumentId != nil

        let gating = await MainActor.run { () -> (limit: Int, canAdd: Bool, tier: WorkspaceTier, count: Int) in
            let count = self.countedDocumentCount
            if let store = self.entitlementStore {
                return (
                    store.documentLimit, skipQuota || store.canAddDocument(currentCount: count), store.activeTier, count
                )
            } else {
                // No entitlement store: an engine a Shortcuts or Siri action built while the app is closed
                // (`IntentSupport.engine`). Until 5.7 this used the free plan's limit, so Add to Library refused
                // a Pro or Lifetime library of five documents or more; it reads the plan and the document packs
                // the app's store last saved (`EntitlementStore.savedDocumentAllowance`).
                let saved = EntitlementStore.savedDocumentAllowance()
                return (saved.limit, skipQuota || saved.isUnlimited || count < saved.limit, saved.tier, count)
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
        let preExistingDocumentsInContainerCount = await MainActor.run {
            self.documentsForContainer(activeContainerId).count
        }

        let __resolveEmbeddingServiceResult = await resolveEmbeddingService(activeContainerId: activeContainerId)
        var containerEmbeddingService = __resolveEmbeddingServiceResult.containerEmbeddingService
        var providerId = __resolveEmbeddingServiceResult.providerId
        let chunkOverride = __resolveEmbeddingServiceResult.chunkOverride
        var container = __resolveEmbeddingServiceResult.container
        let initialDimension = __resolveEmbeddingServiceResult.initialDimension

        let pipelineStartTime = Date()

        // Imports can overlap (a file attached in Chat while the queue imports), and the Core ML and Core AI
        // providers are each one object shared by every service (5.8), so the first import to finish used to
        // switch the other's provider back mid-import. Only the last import using a provider switches it back.
        let ingestionModeKey = containerEmbeddingService.actualProviderId
        ingestionModeHolders[ingestionModeKey, default: 0] += 1
        containerEmbeddingService.enableIngestionMode()
        defer {
            let remaining = (ingestionModeHolders[ingestionModeKey] ?? 1) - 1
            ingestionModeHolders[ingestionModeKey] = remaining > 0 ? remaining : nil
            if remaining <= 0 { containerEmbeddingService.disableIngestionMode() }
        }

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

        installProgressHandlers(trackingId: trackingId, filename: filename)
        // The document's Spotlight entry, once written, so an import that fails or is cancelled
        // after it removes it (5.7: entries no longer expire).
        var listedInSpotlight: UUID?
        do {
            // Step 1: Parse document and extract chunks
            let documentType = documentProcessor.detectDocumentType(url: managedURL)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: managedURL.path)
            let fileSizeMB = Double((fileAttrs?[.size] as? Int64) ?? 0) / 1_048_576.0

            let activeChunkOverride = await prescanChunkingPlan(chunkOverride: chunkOverride, container: &container, documentType: documentType, managedURL: managedURL, filename: filename)
            let isLargePDF = documentType == .pdf && fileSizeMB > 10
            if isLargePDF {
                try await importLargePDFStreamed(
                    at: managedURL,
                    trackingId: trackingId ?? UUID(),
                    filename: filename,
                    activeContainerId: activeContainerId,
                    chunkOverride: activeChunkOverride,
                    providerId: providerId,
                    embeddingDim: initialDimension,
                    containerEmbeddingService: containerEmbeddingService,
                    documentId: reusedDocumentId
                )
                // The refresh every other import ends with (the rest of what a whole-file
                // import does at its end is not done here). Without it the analysis and the
                // vocabulary held for the library, in memory and on disk, stayed those of the
                // library before this document until the app was opened again.
                refreshIntelligence(for: activeContainerId, force: true)
                return  // Streaming method handles the full end-to-end pipeline
            }

            // A large text or JSON Lines file, a piece at a time. Read whole, an 88 MB file held
            // 2.8 GB on an iPhone and never finished (2026-10-09).
            let fileBytes = (fileAttrs?[.size] as? Int64).map { Int($0) } ?? 0
            if DocumentProcessor.importsInPieces(
                fileExtension: managedURL.pathExtension, documentType: documentType, fileBytes: fileBytes),
                (try? TextPieceReader(url: managedURL))?.canBeCutAtLineFeeds == true
            {
                try await importLargeTextStreamed(
                    at: managedURL,
                    trackingId: trackingId ?? UUID(),
                    filename: filename,
                    activeContainerId: activeContainerId,
                    documentType: documentType,
                    chunkOverride: activeChunkOverride,
                    providerId: providerId,
                    containerEmbeddingService: containerEmbeddingService,
                    documentId: reusedDocumentId
                )
                refreshIntelligence(for: activeContainerId, force: true)
                return  // It handles the whole import, like the streamed PDF above.
            }

            let (document, extractionStartTime, processedChunks) = try await parseDocumentForImport(managedURL: managedURL, activeChunkOverride: activeChunkOverride, activeContainerId: activeContainerId, reusedDocumentId: reusedDocumentId)
            try Task.checkCancellation()
            let (avgChunkWords, extractionTime, maxChunkWords, minChunkWords, totalChars, totalWords) = measureExtraction(extractionStartTime: extractionStartTime, document: document, processedChunks: processedChunks, filename: filename)

            // Build domain vocabulary from extracted text for improved entity recognition
            let combinedText = processedChunks.map { $0.text }.joined(separator: " ")
            await GazetteerService.shared.extractAndAddTerms(from: combinedText, source: filename)
            try Task.checkCancellation()

            await indexDocumentInSpotlight(activeContainerId: activeContainerId, document: document, combinedText: combinedText, processedChunks: processedChunks, listedInSpotlight: &listedInSpotlight)
            try Task.checkCancellation()

            await showChunkingStage(trackingId: trackingId, filename: filename, avgChunkWords: avgChunkWords, processedChunks: processedChunks, totalWords: totalWords, fileSizeMB: fileSizeMB, totalChars: totalChars, document: document, minChunkWords: minChunkWords, maxChunkWords: maxChunkWords, extractionTime: extractionTime)

            await autoAdaptConfigurationIfEnabled(context: context, container: &container, trackingId: trackingId, filename: filename, processedChunks: processedChunks, activeContainerId: activeContainerId, document: document, preExistingDocumentsInContainerCount: preExistingDocumentsInContainerCount, providerId: &providerId, containerEmbeddingService: &containerEmbeddingService, pendingSelfTuneReasons: &pendingSelfTuneReasons)
            try Task.checkCancellation()

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

            let textsToEmbed = await buildEmbeddingInputs(filename: filename, processedChunks: processedChunks, container: container, containerEmbeddingService: containerEmbeddingService, contextualPrefixes: &contextualPrefixes)

            try await generateChunkEmbeddings(trackingId: trackingId, filename: filename, embeddingDim: embeddingDim, processedChunks: processedChunks, embeddingProviderName: embeddingProviderName, url: url, containerEmbeddingService: containerEmbeddingService, embeddings: &embeddings, textsToEmbed: textsToEmbed)
            try Task.checkCancellation()
            try EmbeddingVectorCheck.requireUsable(embeddings, of: filename)

            let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

            await reportEmbeddingStats(trackingId: trackingId, filename: filename, embeddingTime: embeddingTime, embeddings: embeddings, processedChunks: processedChunks, providerId: providerId)

            let (documentChunks, chunkingTime) = buildDocumentChunks(contextualPrefixes: contextualPrefixes, embeddings: embeddings, processedChunks: processedChunks, document: document, filename: filename)

            // Step 4: Store chunks in the vector database for the container this import targets.
            //
            // `dbForActiveContainer()` here was a live read, while every other write in this
            // function uses the `activeContainerId` captured at the top. Switching libraries during
            // a long import therefore split the document: metadata and FTS5 to the captured
            // container, vectors to whichever one was on screen. See `dbForContainer`.
            try Task.checkCancellation()
            let db = try await dbForContainer(activeContainerId)

            // A store that is empty *before* this batch will afterwards hold nothing but chunks
            // written by the pipeline running right now, so its fingerprint is knowable rather
            // than assumed. Recording it here is what makes a nil fingerprint mean "predates the
            // field" instead of "nobody has looked yet".
            //
            // Without this, `91ea045` mis-fired on its first device run: a library deleted and
            // recreated on v5.0, whose 193 chunks were embedded by the corrected pipeline at
            // 19ms/chunk, was offered a rebuild it did not need — because the fingerprint is
            // otherwise only ever written by the staleness check itself, so a freshly built
            // library reads nil until that check runs. Every new library would have seen a
            // spurious rebuild prompt, which is worse than the silence it replaced: a prompt
            // that cries wolf teaches the owner to dismiss the one that matters.
            let chunksBeforeThisImport = (try? await db.count()) ?? -1
            try await db.storeBatch(chunks: documentChunks)
            try await db.persist()
            if chunksBeforeThisImport == 0 {
                await MainActor.run { self.stampEmbeddingFingerprintIfAbsent(for: activeContainerId) }
            }
            // Invalidate visualization cache for this container after data change
            ProjectionCache.shared.invalidate(forContainer: activeContainerId)

            await indexChunksInSpotlight(trackingId: trackingId, filename: filename, activeContainerId: activeContainerId, document: document, documentChunks: documentChunks)

            await storeChunksInFullTextIndex(trackingId: trackingId, filename: filename, documentChunks: documentChunks, processedChunks: processedChunks, document: document, activeContainerId: activeContainerId)

            await learnImportVocabulary(trackingId: trackingId, filename: filename, documentChunks: documentChunks, activeContainerId: activeContainerId)

            // Step 4.9: Persist vector store to disk (single write after all batch stores). Before the
            // model work in `enrichImportedDocument`, which comes after the document is saved (5.7).
            // Deferred persistence avoids redundant JSON serialization after each storeBatch call
            try await db.persist()

            // Calculate total pipeline time
            let totalTime = Date().timeIntervalSince(pipelineStartTime)

            // Calculate chunk statistics
            let chunkSizes = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkSizes.isEmpty ? 0 : chunkSizes.reduce(0, +) / chunkSizes.count
            let minChunkSize = chunkSizes.min() ?? 0
            let maxChunkSize = chunkSizes.max() ?? 0

            let fileSizeStr = formatImportFileSize(fileSizeMB: fileSizeMB)

            let updatedDocument = buildCompletedDocument(document: document, fileSizeMB: fileSizeMB, embeddingTime: embeddingTime, totalTime: totalTime, documentHash: documentHash, activeContainerId: activeContainerId)

            let summary = makeProcessingSummary(activeContainerId: activeContainerId, filename: filename, fileSizeStr: fileSizeStr, document: document, totalChars: totalChars, totalWords: totalWords, processedChunks: processedChunks, extractionTime: extractionTime, chunkingTime: chunkingTime, embeddingTime: embeddingTime, totalTime: totalTime, avgChunkSize: avgChunkSize, minChunkSize: minChunkSize, maxChunkSize: maxChunkSize)

            await recordIndexedDocument(updatedDocument: updatedDocument, documentChunks: documentChunks, activeContainerId: activeContainerId, summary: summary, manageProcessingState: manageProcessingState, trackingId: trackingId, filename: filename, fileSizeStr: fileSizeStr, totalTime: totalTime)

            // Save documents metadata to disk
            await saveDocumentsToDisk()

            await enrichOrDeferImportedDocument(trackingId: trackingId, context: context, activeContainerId: activeContainerId, updatedDocument: updatedDocument, filename: filename, container: container, documentChunks: documentChunks, containerEmbeddingService: containerEmbeddingService, db: db)

            await finishImport(trackingId: trackingId, filename: filename, manageProcessingState: manageProcessingState, activeContainerId: activeContainerId, context: context, managedURL: managedURL, pendingSelfTuneReasons: pendingSelfTuneReasons)

        } catch {
            if let listedInSpotlight {
                await MainActor.run {
                    SpotlightIndexService.shared.deindexDocument(id: listedInSpotlight, containerId: activeContainerId)
                }
            }
            if error is CancellationError {
                await MainActor.run {
                    if manageProcessingState { isProcessing = false }
                    if manageProcessingState, trackingId == nil {
                        processingStatus = ""
                    }
                    if let trackingId,
                        requestedIngestionCancellationIds.contains(trackingId),
                        let item = ingestionItems.first(where: { $0.id == trackingId && !$0.stage.isTerminal })
                    {
                        updateIngestionItem(
                            id: trackingId,
                            filename: item.filename,
                            stage: .cancelled,
                            detail: "Cancelled"
                        )
                    }
                    self.kickPendingReembedIfNeeded()
                }

                Log.info("[RAGService] Ingestion cancelled for \(filename)", category: .ingestion)
                throw error
            }

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

    /// Step B: resolves the library this import goes to: the one it was queued for if it still exists, redirected to the person's own library unless it is onboarding or a rebuild.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func resolveImportLibrary(containerId: UUID?, context: IngestionContext) async -> UUID {
        // The library the file was queued for (5.7). Through 5.6 every import went to the library that
        // was active when the queue reached it, so "Add to Library" naming another library, or a file
        // queued before the person switched libraries, landed in the open one. The name stays: the
        // rest of this function and the large-file paths take it as the import's library.
        let activeContainerId = await MainActor.run { () -> UUID in
            if let containerId, self.containerService.containers.contains(where: { $0.id == containerId }) {
                // The guide library takes the app's guides only (5.8): anything else goes to the person's own. A rebuild
                // puts each document back where it was, the guides included.
                if context != .onboarding, context != .autoRebuild, let own = self.containerService.libraryForOwnFiles(requested: containerId) {
                    return own
                }
                return containerId
            }
            if context != .onboarding, context != .autoRebuild,
                let own = self.containerService.libraryForOwnFiles(requested: self.containerService.activeContainerId)
            {
                return own
            }
            return self.containerService.activeContainerId
        }
        return activeContainerId
    }

    /// Step C: computes the file's hash (nil when it cannot be read) and records it with the storage path on the tracked item.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func hashAndRecordDocument(managedURL: URL, filename: String, trackingId: UUID?, managedRelativePath: String?) async -> String? {
        let documentHash: String?
        do {
            documentHash = try computeDocumentHash(for: managedURL)
        } catch {
            Log.warning(
                "[RAGService] Failed to compute document hash for \(filename): \(error.localizedDescription)",
                category: .ingestion)
            documentHash = nil
        }

        await MainActor.run {
            self.updateIngestionItemMetadata(
                id: trackingId,
                documentHash: documentHash,
                storageRelativePath: managedRelativePath
            )
        }
        return documentHash
    }

    /// Step G: picks the library and its embedding service and, when the provider resolves to another one or another dimension, saves the corrected settings and clears the library's vectors.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func resolveEmbeddingService(activeContainerId: UUID) async -> (containerEmbeddingService: EmbeddingService, providerId: String, chunkOverride: DocumentProcessor.ChunkingOverride?, container: KnowledgeContainer?, initialDimension: Int) {
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
        return (containerEmbeddingService: containerEmbeddingService, providerId: providerId, chunkOverride: chunkOverride, container: container, initialDimension: initialDimension)
    }

    /// Step J: installs the document processor's text and rich progress handlers, which move the tracked item through its extraction stages.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func installProgressHandlers(trackingId: UUID?, filename: String) {
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
                let stage: IngestionStage
                switch progress.stage {
                case "transcribing":
                    stage = .transcribing
                case "chunking":
                    stage = .chunking
                case "analyzing":
                    stage = .analyzing
                default:
                    stage = .extracting
                }

                var progressFraction: Double? = nil
                if let base = stage.pipelineBaseFraction {
                    let weight = stage.pipelineWeightFraction ?? 0.0
                    if let current = progress.currentPage, let total = progress.totalPages, total > 0 {
                        let stageProgress = Double(current) / Double(total)
                        progressFraction = base + (stageProgress * weight)
                    } else {
                        progressFraction = base
                    }
                }

                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: stage,
                    detail: progress.detail,
                    progress: progressFraction
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

    }

    /// Step L: when the library adapts itself, pre-scans the document's text and stores the chunking plan it recommends before the import uses it.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func prescanChunkingPlan(chunkOverride: DocumentProcessor.ChunkingOverride?, container: inout KnowledgeContainer?, documentType: DocumentType, managedURL: URL, filename: String) async -> DocumentProcessor.ChunkingOverride? {
        // Pre-scan document and auto-tune container settings before ingestion starts (predictive self-tuning)
        var activeChunkOverride = chunkOverride
        if let currentContainer = container, currentContainer.autoAdaptDimension {
            let previewText = await extractPreviewText(from: managedURL, documentType: documentType)
            if !previewText.isEmpty {
                let plan = await intelligenceCenter.recommendChunkingPlan(
                    forPreviewText: previewText, contentType: documentType)

                var updated = currentContainer
                let directive = ChunkingDirective(
                    source: .auto,
                    strategy: plan.strategy.rawValue,
                    targetWordWindow: plan.targetWordWindow,
                    overlapWords: plan.overlapWords,
                    rationale: plan.rationales
                )
                updated.chunkingDirective = directive

                if updated != currentContainer {
                    await MainActor.run {
                        self.containerService.updateContainer(updated)
                    }
                    container = updated
                    activeChunkOverride = chunkingOverride(for: updated)
                    Log.info(
                        "[SelfTuning] Predictive pre-scan auto-tuned configuration for \(filename): Chunk strategy → \(plan.strategy.rawValue.capitalized) • Window \(plan.targetWordWindow) (Rationale: \(plan.rationales.joined(separator: " | "))). Ingesting with optimized settings.",
                        category: .ingestion
                    )
                }
            }
        }

        return activeChunkOverride
    }

    /// Step N: reads and cuts the document into passages and journals how long the main thread went unanswered meanwhile.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func parseDocumentForImport(managedURL: URL, activeChunkOverride: DocumentProcessor.ChunkingOverride?, activeContainerId: UUID, reusedDocumentId: UUID?) async throws -> (document: Document, extractionStartTime: Date, processedChunks: [DocumentProcessor.ProcessedChunk]) {
        let extractionStartTime = Date()
        let (document, processedChunks) = try await documentProcessor.processDocument(
            at: managedURL,
            chunkOverride: activeChunkOverride,
            containerId: activeContainerId,  // FTS5 storage with container isolation
            documentId: reusedDocumentId
        )
        // How long the main thread went unanswered while the document was read and cut into passages (5.8), from
        // the development build's watchdog: row "Import still runs whole-document passes on the main thread".
        if VerificationJournal.isEnabled, MainThreadWatchdog.shared.isRunning {
            let lagMs = MainThreadWatchdog.shared.longestStall(since: extractionStartTime)
            VerificationJournal.record(
                "import.mainThreadLag", .ok,
                durationMs: Date().timeIntervalSince(extractionStartTime) * 1000,
                ["type": managedURL.pathExtension.lowercased(),
                    "bytes": "\(VerificationJournal.fileBytes(managedURL))",
                    "maxLagMs": "\(Int(lagMs))", "responsive": "\(lagMs < MainThreadWatchdog.stallThresholdMs)",
                    "chunks": "\(processedChunks.count)"])
        }
        return (document: document, extractionStartTime: extractionStartTime, processedChunks: processedChunks)
    }

    /// Step O: counts the document's characters, words and per-passage word statistics and emits Extraction complete.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func measureExtraction(extractionStartTime: Date, document: Document, processedChunks: [DocumentProcessor.ProcessedChunk], filename: String) -> (avgChunkWords: Int, extractionTime: TimeInterval, maxChunkWords: Int, minChunkWords: Int, totalChars: Int, totalWords: Int) {
        let extractionTime = Date().timeIntervalSince(extractionStartTime)
        // The document's own counts, of its text as it was read (5.7). Summing the passages counted
        // the words two neighbours share twice (row "Word counts look wrong").
        let totalChars =
            document.processingMetadata?.totalCharacters
            ?? processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
        let totalWords =
            document.processingMetadata?.totalWords
            ?? processedChunks.reduce(0) { $0 + $1.metadata.wordCount }

        // Calculate chunk word stats
        let chunkWordCounts = processedChunks.map { $0.metadata.wordCount }
        let avgChunkWords = chunkWordCounts.isEmpty ? 0 : chunkWordCounts.reduce(0, +) / chunkWordCounts.count
        let minChunkWords = chunkWordCounts.min() ?? 0
        let maxChunkWords = chunkWordCounts.max() ?? 0

        // Get file metadata (already parsed above)

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
        return (avgChunkWords: avgChunkWords, extractionTime: extractionTime, maxChunkWords: maxChunkWords, minChunkWords: minChunkWords, totalChars: totalChars, totalWords: totalWords)
    }

    /// Step P: lists the document in Spotlight when the setting allows it and records that it did, so a failed import removes the entry.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func indexDocumentInSpotlight(activeContainerId: UUID, document: Document, combinedText: String, processedChunks: [DocumentProcessor.ProcessedChunk], listedInSpotlight: inout UUID?) async {
        // Index document in Spotlight for system-wide search
        let spotlightEnabled = await MainActor.run { self.settingsStore?.enableSpotlightIndexing ?? true }
        if spotlightEnabled {
            let cid = activeContainerId
            let containerName = await MainActor.run {
                self.containerService.containers.first(where: { $0.id == cid })?.name ?? "Library"
            }
            SpotlightIndexService.shared.indexDocument(
                id: document.id,
                filename: document.filename,
                containerId: activeContainerId,
                containerName: containerName,
                textPreview: String(combinedText.prefix(500)),
                chunkCount: processedChunks.count
            )
            listedInSpotlight = document.id
        }
    }

    /// Step Q: shows the chunking stage with the extraction's live metrics and yields so the interface can draw it.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func showChunkingStage(trackingId: UUID?, filename: String, avgChunkWords: Int, processedChunks: [DocumentProcessor.ProcessedChunk], totalWords: Int, fileSizeMB: Double, totalChars: Int, document: Document, minChunkWords: Int, maxChunkWords: Int, extractionTime: TimeInterval) async {
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
    }

    /// Step R (Step 1.5): the self-tune corpus analysis, which can change the library's chunking and embedding settings; it does not run today because allowsSelfTuningScheduling is false for every import.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func autoAdaptConfigurationIfEnabled(context: IngestionContext, container: inout KnowledgeContainer?, trackingId: UUID?, filename: String, processedChunks: [DocumentProcessor.ProcessedChunk], activeContainerId: UUID, document: Document, preExistingDocumentsInContainerCount: Int, providerId: inout String, containerEmbeddingService: inout EmbeddingService, pendingSelfTuneReasons: inout [String]) async {
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

            // This block does not run in any build so far: `allowsSelfTuningScheduling` is
            // false for every kind of import. It is kept in step with the launch analysis so
            // that turning it on would not bring back a read of every passage.
            // The library as it is, counted. Its passages are read by `libraryAnalysisInput`
            // below, all of them or a sample.
            let db = await dbForActiveContainer()
            let existingPassageCount = (try? await db.count()) ?? 0

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .analyzing,
                    detail:
                        "Analyzing \(existingPassageCount + processedChunks.count) chunks for vocabulary patterns...",
                    progress: 0.3
                )
            }

            // Analyze combined corpus (existing + new document)
            let allDocumentsForAnalysis = await MainActor.run {
                self.documents.filter { $0.containerId == activeContainerId } + [document]
            }
            let newDocumentChunks =
                processedChunks.enumerated().map { index, chunk in
                    DocumentChunk(
                        documentId: document.id,
                        content: chunk.text,
                        parentContent: chunk.parentText,
                        embedding: [],  // Empty for analysis
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

            let analysisInput = await Self.libraryAnalysisInput(from: db, adding: newDocumentChunks)
            let report = await intelligenceCenter.analyzeLibrary(
                documents: allDocumentsForAnalysis,
                chunks: analysisInput.chunks,
                library: analysisInput.size
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
            let detectedLangs = report.corpus.languageHypotheses.sorted { $0.value > $1.value }.prefix(3).map {
                $0.key.rawValue
            }

            // Classify document domain from filename and content signals
            let domain = Self.classifyDocumentDomain(
                filename: filename, signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
            let descriptor = Self.buildContentDescriptor(
                signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
            let categories = Self.extractContentCategories(
                entities: report.documents.flatMap { $0.keyTopics }, signals: report.corpus)
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
                // This report is of the library with the document being imported added to
                // it, which no signature of the library on disk describes yet.
                self.containerIntelligence[activeContainerId] = report
                self.containerIntelligenceSignature.removeValue(forKey: activeContainerId)
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

            // A library with no documents yet is choosing its settings for this first
            // import, which nothing has been embedded under, so its embedding model may come
            // from a sample of a long document. A library that has documents does not get
            // another model from a sample.
            let (updatedContainer, autoReasons) = Self.resolveAutoAdjustments(
                for: autoContainer,
                report: report,
                allowingEstimate: preExistingDocumentsInContainerCount == 0
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
                    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms flash
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
                if preExistingDocumentsInContainerCount > 0, !report.corpus.isEstimate {
                    // Never from a sample: its reason can only be the chunking, and a
                    // rebuild embeds every document again.
                    pendingSelfTuneReasons = autoReasons
                } else if preExistingDocumentsInContainerCount > 0 {
                    Log.info(
                        "Skipping self-tuning rebuild: the analysis read a sample of the library.",
                        category: .ingestion)
                } else {
                    Log.info(
                        "Skipping self-tuning rebuild: config updated during first ingest and there are no prior documents to rebuild.",
                        category: .ingestion
                    )
                }
            }
        }

    }

    /// Step S (vectors): shows the embedding stage and generates every passage's vector with live progress, using the import's checkpoint folder as cache.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func generateChunkEmbeddings(trackingId: UUID?, filename: String, embeddingDim: Int, processedChunks: [DocumentProcessor.ProcessedChunk], embeddingProviderName: String, url: URL, containerEmbeddingService: EmbeddingService, embeddings: inout [[Float]], textsToEmbed: [String]) async throws {
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
        // Kept in the import's checkpoint folder, which is removed when the import finishes (5.7).
        let embeddingCache = documentProcessor.checkpointDirectoryURL(
            for: documentProcessor.computeDocumentFingerprint(at: url))
        embeddings = try await containerEmbeddingService.generateEmbeddings(
            for: textsToEmbed,
            cacheDirectory: embeddingCache,
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
    }

    /// Step T: shows the indexing and storing stages with the embedding figures and emits Embeddings generated.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func reportEmbeddingStats(trackingId: UUID?, filename: String, embeddingTime: TimeInterval, embeddings: [[Float]], processedChunks: [DocumentProcessor.ProcessedChunk], providerId: String) async {
        // Update with final embedding stats
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .indexing,
                detail: "Building vector + BM25 indexes...",
                progress: 0.94
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
                detail: "Persisting \(processedChunks.count) chunks to vector database...",
                progress: 0.94
            )
        }
    }

    /// Step W: indexes every passage in Spotlight when the setting allows it, then emits Chunks stored.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func indexChunksInSpotlight(trackingId: UUID?, filename: String, activeContainerId: UUID, document: Document, documentChunks: [DocumentChunk]) async {
        // Step 4.0.0: Index individual document chunks in Spotlight for fine-grained search
        let chunkSpotlightEnabled = await MainActor.run { self.settingsStore?.enableSpotlightIndexing ?? true }
        if chunkSpotlightEnabled {
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .indexing,
                    detail: "Indexing Spotlight search...",
                    progress: 0.95
                )
            }
            let cid = activeContainerId
            let containerName = await MainActor.run {
                self.containerService.containers.first(where: { $0.id == cid })?.name ?? "Library"
            }
            SpotlightIndexService.shared.indexDocumentChunks(
                documentId: document.id,
                documentName: document.filename,
                chunks: documentChunks,
                containerId: activeContainerId,
                containerName: containerName
            )
        }

        TelemetryCenter.emit(
            .storage,
            title: "Chunks stored",
            metadata: [
                "file": filename,
                "count": "\(documentChunks.count)",
            ]
        )
    }

    /// Step X: builds the FTS5 rows (with structured table metadata) for every passage and stores them in the chunk-level full-text index.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func storeChunksInFullTextIndex(trackingId: UUID?, filename: String, documentChunks: [DocumentChunk], processedChunks: [DocumentProcessor.ProcessedChunk], document: Document, activeContainerId: UUID) async {
        // Step 4.0.1: Store chunks in chunk-level FTS5 for section-aware BM25 search
        // This enables chunk-level BM25 scoring with section heading boosts:
        // "oil" matching in sectionTitle="Engine Oil" gets 10x the score of body text
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .indexing,
                detail: "Indexing text search...",
                progress: 0.96
            )
        }
        let fts5ChunkData:
            [(
                chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                sectionPath: String?, structureType: String?, chunkType: String?,
                tableTitle: String?, content: String,
                structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?
            )] =
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
    }

    /// Step Y: teaches the library's vocabulary every passage and the Vision-detected entities, records the document, and emits Vocabulary learned.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func learnImportVocabulary(trackingId: UUID?, filename: String, documentChunks: [DocumentChunk], activeContainerId: UUID) async {
        // Step 4.1: Learn vocabulary from chunks for per-container domain adaptation
        // Extracts domain terms, spec codes, and technical phrases to improve future retrieval
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .analyzing,
                detail: "Learning vocabulary...",
                progress: 0.97
            )
        }
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
    }

    /// Step AC: lists the document in its library, updates the chunk count, library stats and processing summary on the main actor, and emits Document indexed.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func recordIndexedDocument(updatedDocument: Document, documentChunks: [DocumentChunk], activeContainerId: UUID, summary: ProcessingSummary, manageProcessingState: Bool, trackingId: UUID?, filename: String, fileSizeStr: String, totalTime: TimeInterval) async {
        // Step 5: Update state
        await MainActor.run {
            let replacedChunks = listImportedDocument(updatedDocument)
            totalChunksStored += documentChunks.count - replacedChunks
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
    }

    /// Step AE: defers the document's overview, tags and suggested questions when the app is in the background or more files are queued, and otherwise runs them now.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func enrichOrDeferImportedDocument(trackingId: UUID?, context: IngestionContext, activeContainerId: UUID, updatedDocument: Document, filename: String, container: KnowledgeContainer?, documentChunks: [DocumentChunk], containerEmbeddingService: EmbeddingService, db: any VectorDatabase) async {
        // The document is saved and can be searched. What follows is model work that improves it
        // and is not needed to answer from it (5.7). In the background it waits for the app to be
        // in front: on 2026-10-15 iOS ended a background import 53 s in, during this work, and the Lock
        // Screen said "Task failed"; the overview and the tags then came before the save, so an earlier
        // end would have stopped the import before its document was recorded.
        //
        // From 5.8 it also waits while more files are queued, so the queue moves to the next file at once and
        // the work runs when it empties (`runDeferredEnrichmentsIfNeeded`, called at the end of the loop). The
        // work is the same and so is what it writes; through 5.7 each file held the next one for it, up to 20 s
        // a document on an A18 Pro (the note in `enrichImportedDocument`). The last file of an import, or a
        // single file, is still enriched here.
        let (inBackground, filesWaiting) = await MainActor.run {
            (
                Self.appIsInBackground,
                self.ingestionItems.contains { $0.stage == .queued && $0.id != trackingId }
            )
        }
        if Self.shouldDeferEnrichment(
            appIsInBackground: inBackground, otherFilesQueued: filesWaiting, isOnboarding: context == .onboarding,
            managedByQueue: trackingId != nil)
        {
            Self.deferEnrichment(of: updatedDocument.id, in: activeContainerId)
            VerificationJournal.record(
                "import.enrichmentDeferred",
                ["document": VerificationJournal.anon(updatedDocument.id),
                    "reason": inBackground ? "background" : (filesWaiting ? "queue" : "afterComplete"), "context": "\(context)"])
            Log.info(
                inBackground
                    ? "[RAGService] Saved '\(filename)'; its overview, tags and suggested questions wait until the app is in front"
                    : "[RAGService] Saved '\(filename)'; its overview, tags and suggested questions run when the import queue empties",
                category: .ingestion)
        } else {
            await enrichImportedDocument(
                updatedDocument, chunks: documentChunks, container: container,
                embeddingService: containerEmbeddingService, db: db, context: context,
                trackingId: trackingId, containerId: activeContainerId)
        }
    }

    /// Step AF: marks the item complete, records the completion time, kicks pending re-embeds and retrieval auto-tune, refreshes the library's intelligence, cleans checkpoints and schedules a self-tune rebuild if one was asked for.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func finishImport(trackingId: UUID?, filename: String, manageProcessingState: Bool, activeContainerId: UUID, context: IngestionContext, managedURL: URL, pendingSelfTuneReasons: [String]) async {
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
            self.autoTuneRetrievalConfigIfNeeded(for: activeContainerId)
        }

        refreshIntelligence(
            for: activeContainerId,
            force: true,
            allowSelfTuningScheduling: context.allowsSelfTuningScheduling
        )

        // Clean up temporary page checkpoints on successful ingestion completion
        documentProcessor.cleanCheckpoints(for: managedURL)

        if context.allowsSelfTuningScheduling, !pendingSelfTuneReasons.isEmpty {
            scheduleSelfTuningRebuild(for: activeContainerId, reasons: pendingSelfTuneReasons)
        }
    }

    /// Step S (inputs): builds each passage's contextual prefix and the token-limited text to embed, translating first when the library asks for it.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func buildEmbeddingInputs(filename: String, processedChunks: [DocumentProcessor.ProcessedChunk], container: KnowledgeContainer?, containerEmbeddingService: EmbeddingService, contextualPrefixes: inout [String]) async -> [String] {
        // Build contextual prefix once (reused for all chunks in this document)
        let docContext = buildContextualPrefix(filename: filename)
        Log.info("[Contextual] Document prefix: '\(docContext)'", category: .ingestion)

        // HYPERCHARGE: Build all texts to embed upfront, then batch embed
        // This uses parallel embedding (TaskGroup) in the provider layer
        var textsToEmbed: [String] = []
        textsToEmbed.reserveCapacity(processedChunks.count)
        let translatedChunkTexts = await translatedTextsForEmbedding(
            processedChunks.map(\.text),
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
                    "[RAGService] ⚠️ Chunk exceeds token limit: \(tokenCount)/\(maxTokens) tokens. "
                        + "Truncating to prevent embedding data loss.",
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
                Log.info(
                    "[RAGService] Truncated to \(newTokenCount) tokens (\(textForEmbedding.count) chars)",
                    category: .ingestion)
            }

            textsToEmbed.append(textForEmbedding)
        }
        return textsToEmbed
    }

    /// Step U: pairs each passage with its vector and contextual prefix into DocumentChunk records and emits the Chunks prepared event.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func buildDocumentChunks(contextualPrefixes: [String], embeddings: [[Float]], processedChunks: [DocumentProcessor.ProcessedChunk], document: Document, filename: String) -> (documentChunks: [DocumentChunk], chunkingTime: TimeInterval) {
        // Step 3: Create DocumentChunk objects with embeddings and contextual prefixes
        let chunkingStartTime = Date()
        let documentChunks = zip(zip(processedChunks, embeddings), contextualPrefixes).enumerated().map {
            (index: Int, pair: ((DocumentProcessor.ProcessedChunk, [Float]), String)) in
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
        return (documentChunks: documentChunks, chunkingTime: chunkingTime)
    }

    /// Step AA (size): formats the file's size in MB as the B, KB or MB string the summary and telemetry show.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func formatImportFileSize(fileSizeMB: Double) -> String {
        // Format file size string from existing fileSizeMB
        let fileSizeStr: String
        if fileSizeMB < 0.001 {
            fileSizeStr = String(format: "%.0f B", fileSizeMB * 1_048_576)
        } else if fileSizeMB < 1.0 {
            fileSizeStr = String(format: "%.2f KB", fileSizeMB * 1024.0)
        } else {
            fileSizeStr = String(format: "%.2f MB", fileSizeMB)
        }
        return fileSizeStr
    }

    /// Step AA (document): rebuilds the imported Document with its complete processing metadata, the file hash and the import's library.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func buildCompletedDocument(document: Document, fileSizeMB: Double, embeddingTime: TimeInterval, totalTime: TimeInterval, documentHash: String?, activeContainerId: UUID) -> Document {
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
                fileHash: documentHash ?? document.fileHash,
                contentType: document.contentType,
                addedAt: document.addedAt,
                totalChunks: document.totalChunks,
                processingMetadata: completeMetadata,
                containerId: document.containerId,
                contentTags: nil
            )
        }

        // Ensure document is associated with the active container and has content tags
        let docWithContainer = Document(
            id: updatedDocument.id,
            filename: updatedDocument.filename,
            fileURL: updatedDocument.fileURL,
            storageRelativePath: updatedDocument.storageRelativePath,
            fileHash: documentHash ?? updatedDocument.fileHash,
            contentType: updatedDocument.contentType,
            addedAt: updatedDocument.addedAt,
            totalChunks: updatedDocument.totalChunks,
            processingMetadata: updatedDocument.processingMetadata,
            containerId: activeContainerId,
            contentTags: updatedDocument.contentTags
        )
        updatedDocument = docWithContainer
        return updatedDocument
    }

    /// Step AB: builds the import's ProcessingSummary from its timings, counts and chunk statistics, with the library's embedding provider.
    /// Moved unchanged from `addDocument` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func makeProcessingSummary(activeContainerId: UUID, filename: String, fileSizeStr: String, document: Document, totalChars: Int, totalWords: Int, processedChunks: [DocumentProcessor.ProcessedChunk], extractionTime: TimeInterval, chunkingTime: TimeInterval, embeddingTime: TimeInterval, totalTime: TimeInterval, avgChunkSize: Int, minChunkSize: Int, maxChunkSize: Int) -> ProcessingSummary {
        // Create processing summary with embedding provider info
        let activeProviderId =
            containerService.containers.first { $0.id == activeContainerId }?.embeddingProviderId
            ?? "coreml_sentence_embedding"
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
        return summary
    }

    private func prepareManagedDocumentURL(from url: URL) throws -> URL {
        if let relativePath = AppSupportPaths.relativePath(for: url) {
            return AppSupportPaths.documentURL(forRelativePath: relativePath)
        }

        let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(preferredFileName: url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
        }
        return destinationURL
    }

}
