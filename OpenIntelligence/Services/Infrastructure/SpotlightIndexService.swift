//
//  SpotlightIndexService.swift
//  OpenIntelligence
//
//  CoreSpotlight integration — indexes ingested documents and containers
//  for Spotlight, Siri, and system-wide search discoverability.
//

@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

// MARK: - Spotlight Index Service

/// Indexes documents and containers into CoreSpotlight for system-wide search.
/// Documents become searchable from Spotlight, Siri, and Shortcuts.
@MainActor
final class SpotlightIndexService {

    // MARK: - Singleton

    static let shared = SpotlightIndexService()

    private let searchableIndex = CSSearchableIndex.default()
    private let domainIdentifier = "com.openintelligence.documents"

    private init() {}

    // MARK: - Container Indexing

    /// Index a container (library) for Spotlight search
    func indexContainer(_ container: KnowledgeContainer) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .folder)
        attributeSet.title = container.name
        attributeSet.contentDescription = container.description ?? "Knowledge library with \(container.totalDocuments) documents"
        attributeSet.keywords = ["library", "knowledge base", "documents", container.name.lowercased()]
        attributeSet.thumbnailData = nil // Could generate from container icon
        attributeSet.containerTitle = "OpenIntelligence"
        attributeSet.containerDisplayName = "Libraries"

        let item = CSSearchableItem(
            uniqueIdentifier: "container-\(container.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        // Containers don't expire
        item.expirationDate = .distantFuture

        HardwareTelemetryState.shared.pulse(.dataDecoding, intensity: 0.5, duration: 0.2)
        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to index container '\(container.name)': \(error.localizedDescription)", category: .initialization)
            } else {
                Log.debug("[Spotlight] Indexed container '\(container.name)'", category: .initialization)
                Task { @MainActor in DSHaptics.soft() }
            }
        }
    }

    /// Remove a container from Spotlight index
    func deindexContainer(id: UUID) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["container-\(id.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex container \(id): \(error.localizedDescription)", category: .initialization)
            }
        }
    }

    // MARK: - Document Indexing

    /// Index an ingested document for Spotlight search
    /// - Parameters:
    ///   - document: The ingested document metadata
    ///   - containerId: The container this document belongs to
    ///   - textPreview: First ~500 chars of document text for Spotlight preview
    func indexDocument(
        id: UUID,
        filename: String,
        containerId: UUID,
        containerName: String,
        textPreview: String,
        pageCount: Int? = nil,
        chunkCount: Int? = nil,
        fileSize: Int64? = nil,
        keywords: [String]? = nil,
        contentType: UTType = .plainText
    ) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: contentType)
        attributeSet.title = filename
        attributeSet.contentDescription = String(textPreview.prefix(500))
        attributeSet.containerTitle = containerName
        attributeSet.containerDisplayName = "OpenIntelligence"

        // Rich metadata
        if let pageCount = pageCount {
            attributeSet.pageCount = pageCount as NSNumber
        }
        if let chunkCount = chunkCount {
            attributeSet.keywords = (keywords ?? []) + ["chunks: \(chunkCount)"]
        } else {
            attributeSet.keywords = keywords
        }

        // Document-specific attributes
        attributeSet.metadataModificationDate = Date()
        attributeSet.addedDate = Date()
        attributeSet.kind = "Ingested Document"

        let item = CSSearchableItem(
            uniqueIdentifier: "document-\(id.uuidString)",
            domainIdentifier: "\(domainIdentifier).\(containerId.uuidString)",
            attributeSet: attributeSet
        )
        // Documents expire after 30 days if not re-indexed
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to index document '\(filename)': \(error.localizedDescription)", category: .ingestion)
            } else {
                Log.debug("[Spotlight] Indexed document '\(filename)' in container '\(containerName)'", category: .ingestion)
            }
        }
    }

    /// Remove a document from Spotlight index
    func deindexDocument(id: UUID) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["document-\(id.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex document \(id): \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    /// Remove all documents in a container from Spotlight index
    func deindexAllDocuments(in containerId: UUID) {
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: ["\(domainIdentifier).\(containerId.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex documents in container \(containerId): \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    // MARK: - Batch Operations

    /// Re-index all containers and their documents
    /// Useful for background refresh tasks
    func reindexAll(containers: [KnowledgeContainer], documents: [(id: UUID, filename: String, containerId: UUID, textPreview: String)]) {
        let domainId = self.domainIdentifier
        let index = self.searchableIndex
        // First, clear all existing items — use async/await to avoid @Sendable closure issues
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await index.deleteAllSearchableItems()
            } catch {
                Log.error("[Spotlight] Failed to clear index: \(error.localizedDescription)", category: .initialization)
                return
            }

            // Re-index containers
            for container in containers {
                self.indexContainer(container)
            }

            // Re-index documents in batches
            let batchSize = 50
            for batch in stride(from: 0, to: documents.count, by: batchSize) {
                let end = min(batch + batchSize, documents.count)
                let batchDocs = documents[batch..<end]

                var items: [CSSearchableItem] = []
                for doc in batchDocs {
                    let containerName = containers.first(where: { $0.id == doc.containerId })?.name ?? "Unknown"
                    let attributeSet = CSSearchableItemAttributeSet(contentType: .plainText)
                    attributeSet.title = doc.filename
                    attributeSet.contentDescription = String(doc.textPreview.prefix(500))
                    attributeSet.containerTitle = containerName
                    attributeSet.containerDisplayName = "OpenIntelligence"
                    attributeSet.addedDate = Date()

                    let item = CSSearchableItem(
                        uniqueIdentifier: "document-\(doc.id.uuidString)",
                        domainIdentifier: "\(domainId).\(doc.containerId.uuidString)",
                        attributeSet: attributeSet
                    )
                    item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
                    items.append(item)
                }

                try? await index.indexSearchableItems(items)
            }

            DSHaptics.success()
            HardwareTelemetryState.shared.reportRAGPipeline(stage: "Spotlight Reindex")
            Log.info("[Spotlight] Re-indexed \(containers.count) containers and \(documents.count) documents", category: .initialization)
        }
    }

    // MARK: - Search Continuation

    /// Handle a Spotlight search continuation — user tapped a result in Spotlight
    /// Returns the container ID and document ID to navigate to
    static func parseSpotlightIdentifier(_ identifier: String) -> (type: String, id: UUID)? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let uuid = UUID(uuidString: String(parts[1]))
        else { return nil }

        return (type: String(parts[0]), id: uuid)
    }
}
