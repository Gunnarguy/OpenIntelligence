//
//  RAGService+SelfTuning.swift
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
    // MARK: - Self-Tuning

    /// Auto-tunes retrieval configuration based on document types in the active container.
    /// Called after successful document ingestion to optimize search weights.
    /// The library is the import's (5.8), which a rebuild no longer opens on screen.
    @MainActor
    func autoTuneRetrievalConfigIfNeeded(for libraryId: UUID? = nil) {
        guard
            let container = libraryId.flatMap({ id in containerService.containers.first { $0.id == id } })
                ?? containerService.activeContainer
        else { return }

        // Collect document types from all documents in this container
        let containerDocs = documents.filter { $0.containerId == container.id }
        let documentTypes = containerDocs.map { $0.contentType }

        guard !documentTypes.isEmpty else { return }

        // Get recommended config based on document types
        let recommended = RetrievalConfig.recommended(forDocumentTypes: documentTypes)

        // Values the person chose in Library Settings are left alone (`RetrievalConfig.autoTuned`).
        let current = container.retrievalConfig
        if current.isChosenByPerson {
            Log.debug("[RAGService] Skipping auto-tune: the person chose this library's search settings", category: .retrieval)
        }

        if let tuned = RetrievalConfig.autoTuned(current: current, recommended: recommended) {
            var updatedContainer = container
            updatedContainer.retrievalConfig = tuned

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

    func chunkingOverride(for container: KnowledgeContainer?) -> DocumentProcessor.ChunkingOverride? {
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

    func extractPreviewText(from url: URL, documentType: DocumentType) async -> String {
        guard documentType == .pdf else {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return String(content.prefix(10000))
            }
            return ""
        }

        return await Task.detached(priority: .userInitiated) {
            guard let pdfDoc = PDFDocument(url: url) else { return "" }
            var sampleText = ""
            let pageCount = min(pdfDoc.pageCount, 10)
            for i in 0..<pageCount {
                if let pageText = pdfDoc.page(at: i)?.string {
                    sampleText += pageText + "\n"
                }
            }
            return sampleText
        }.value
    }

    /// What a self-tuning library changes about itself after an analysis: the library as it
    /// would be, and why. No reasons means no change.
    ///
    /// The chunking settings follow any report, as they did through 5.6. They cost nothing to
    /// change: they are used the next time something is cut into passages, they are not part of
    /// a library's embedding fingerprint when the app sets them (`EmbeddingFingerprint.chunkerRecipe`),
    /// and each import sets them again from the file it reads.
    ///
    /// The embedding model does not follow a report made from a sample of the library
    /// (`CorpusSignals.isEstimate`, which is what a library past `analysisPassageLimit` gets),
    /// unless `allowingEstimate` is set. A sample's measures are not the library's (vocabulary
    /// reads richer in a sample, and whether code or math is found depends on which passages
    /// were drawn), and another model means embedding every document again. Today nothing
    /// applies an embedding change on its own for any report: the one place that would
    /// (`scheduleSelfTuningRebuild`) is behind `IngestionContext.allowsSelfTuningScheduling`,
    /// which is false for every kind of import, and its other caller, `handleSelfTuning`, is
    /// called from nowhere. Both of them queue a rebuild for any reason, the chunking included,
    /// so each also refuses a sampled report by itself. With that and this rule, turning the
    /// switch on cannot make a sample start a rebuild. `allowingEstimate` is for a library with
    /// no documents yet, where there is nothing to embed again.
    static func resolveAutoAdjustments(
        for container: KnowledgeContainer,
        report: LibraryIntelligenceCenter.IntelligenceReport,
        allowingEstimate: Bool = false
    ) -> (KnowledgeContainer, [String]) {
        var updated = container
        var reasons: [String] = []

        if !report.corpus.isEstimate || allowingEstimate,
            let embeddingAction = evaluateEmbeddingShift(container: container, plan: report.embedding)
        {
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

    static func evaluateEmbeddingShift(
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

        // Core ML and Core AI are two copies of one sentence model. A plan that names the other
        // copy is not a reason to clear a library and embed it again.
        let providerChanged =
            plan.providerId != container.embeddingProviderId
            && !EmbeddingProviderDefaults.areCopiesOfOneModel(plan.providerId, container.embeddingProviderId)
        let dimensionDelta = abs(plan.dimension - container.embeddingDim)
        guard providerChanged || dimensionDelta >= 64 else { return nil }

        // Require higher confidence to override user settings
        let confident = plan.confidence >= 0.50
        guard confident else {
            Log.debug(
                "[AutoAdapt] Skipping embedding shift - confidence \(plan.confidence) below threshold",
                category: .ingestion)
            return nil
        }

        let friendlyProvider: String
        switch plan.providerId {
        case "coreml_sentence_embedding":
            friendlyProvider = "Core ML Sentence"
        case "coreai_sentence_embedding":
            friendlyProvider = "Core AI Sentence"
        case "apple_fm_embed":
            friendlyProvider = "Apple FM"
        case "nl_contextual_embedding":
            friendlyProvider = "Contextual Embeddings"
        default:
            friendlyProvider = "Natural Language"
        }

        let reason =
            "Embeddings shifted to \(friendlyProvider) • \(plan.dimension)D (confidence \(String(format: "%.0f%%", plan.confidence * 100)))"
        return EmbeddingAutoAction(providerId: plan.providerId, dimension: plan.dimension, reason: reason)
    }

    private static func evaluateChunkShift(
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
    static let thinkingEventLimit = 150

    func scheduleSelfTuningRebuild(for containerId: UUID, reasons: [String]) {
        // VISIBLE LOGGING: Make self-tuning decisions obvious in console (not ghost process)
        Log.warning(
            "⚠️ [SelfTuning] AUTO-REBUILD SCHEDULED for container \(containerId)\n"
                + "   Reasons: \(reasons.joined(separator: " | "))\n"
                + "   This will re-embed ALL documents in the container!",
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

}
