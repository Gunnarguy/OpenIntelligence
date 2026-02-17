//
//  EntityIndexService.swift
//  OpenIntelligence
//
//  Global Entity Index for cross-document correlation and GraphRAG-lite expansion.
//
//  ## Overview
//
//  This service maintains a global inverted index mapping entity names to the chunks
//  that contain them. This enables:
//
//  1. **Cross-Document Correlation**: Find all chunks mentioning "URLSession" across
//     different documents to build comprehensive context.
//
//  2. **GraphRAG-Lite Expansion**: When initial retrieval finds a chunk mentioning
//     "CoreData", the entity index quickly finds related chunks about "CoreData"
//     in other documents without additional vector search.
//
//  3. **Entity-Based Navigation**: Power "see also" suggestions and entity-centric views.
//
//  ## Architecture
//
//  - **Index Structure**: `Dict<String, Set<UUID>>` maps normalized entity names to chunk IDs
//  - **Normalization**: Entities are lowercased for case-insensitive lookup
//  - **Thread Safety**: Uses actor isolation for concurrent access
//  - **Persistence**: JSON serialization to app container for cold-start performance
//
//  ## Integration
//
//  - `SemanticChunker.extractEntities()` populates `ChunkMetadata.entities`
//  - `RAGService.ingestDocument()` calls `EntityIndexService.indexChunk()`
//  - `AgenticOrchestrator.executeGraphExpansion()` uses `chunksForEntity()` for 2-hop retrieval
//
//  See also:
//  - SemanticChunker.swift (entity extraction)
//  - AgenticOrchestrator.swift (GraphRAG-lite expansion)
//  - DocumentChunk.swift (ChunkMetadata.entities field)
//

import Foundation

/// Global entity index for cross-document correlation
/// Maps entity names → chunk IDs for O(1) lookup
actor EntityIndexService {
    // MARK: - Singleton

    /// Shared instance (lazy-initialized with persistence loading)
    static let shared = EntityIndexService()

    // MARK: - Index Storage

    /// Primary index: normalized entity name → set of chunk IDs
    private var entityToChunks: [String: Set<UUID>] = [:]

    /// Reverse index: chunk ID → entities (for efficient removal)
    private var chunkToEntities: [UUID: Set<String>] = [:]

    /// Document → chunks mapping for bulk deletion
    private var documentToChunks: [UUID: Set<UUID>] = [:]

    /// Statistics
    private(set) var totalEntities: Int = 0
    private(set) var totalIndexedChunks: Int = 0
    private(set) var lastUpdated: Date = .init()

    // MARK: - Persistence

    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenIntelligence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("entity_index.json")
    }()

    // MARK: - Initialization

    private init() {
        // Load persisted index asynchronously after init
        Task { [weak self] in
            await self?.loadFromDisk()
        }
    }

    // MARK: - Indexing

    /// Index a single chunk's entities
    /// - Parameters:
    ///   - chunk: The document chunk with extracted entities in metadata
    func indexChunk(_ chunk: DocumentChunk) {
        guard !chunk.metadata.entities.isEmpty else { return }

        let chunkId = chunk.id
        let documentId = chunk.documentId
        var normalizedEntities = Set<String>()

        for entity in chunk.metadata.entities {
            let normalized = normalizeEntity(entity)
            guard !normalized.isEmpty else { continue }

            normalizedEntities.insert(normalized)

            // Add to forward index
            if entityToChunks[normalized] == nil {
                entityToChunks[normalized] = Set()
            }
            entityToChunks[normalized]?.insert(chunkId)
        }

        // Update reverse index
        chunkToEntities[chunkId] = normalizedEntities

        // Update document index
        if documentToChunks[documentId] == nil {
            documentToChunks[documentId] = Set()
        }
        documentToChunks[documentId]?.insert(chunkId)

        // Update statistics
        totalEntities = entityToChunks.count
        totalIndexedChunks = chunkToEntities.count
        lastUpdated = Date()

        Log.debug("[EntityIndex] Indexed chunk \(chunkId.uuidString.prefix(8)) with \(normalizedEntities.count) entities", category: .retrieval)
    }

    /// Index multiple chunks (batch operation)
    func indexChunks(_ chunks: [DocumentChunk]) {
        for chunk in chunks {
            indexChunk(chunk)
        }
        Log.info("[EntityIndex] Batch indexed \(chunks.count) chunks", category: .retrieval)
    }

    // MARK: - Lookup

    /// Find all chunk IDs containing a given entity
    /// - Parameter entity: The entity name to search for (case-insensitive)
    /// - Returns: Set of chunk UUIDs containing this entity
    func chunksForEntity(_ entity: String) -> Set<UUID> {
        let normalized = normalizeEntity(entity)
        return entityToChunks[normalized] ?? Set()
    }

    /// Find all chunk IDs containing any of the given entities
    /// - Parameter entities: Array of entity names to search for
    /// - Returns: Set of chunk UUIDs containing any of these entities
    func chunksForEntities(_ entities: [String]) -> Set<UUID> {
        var result = Set<UUID>()
        for entity in entities {
            result.formUnion(chunksForEntity(entity))
        }
        return result
    }

    /// Find entities shared between multiple chunks (for relatedness scoring)
    /// - Parameters:
    ///   - chunkIds: The chunk IDs to analyze
    /// - Returns: Dictionary of entity → count across the provided chunks
    func sharedEntities(among chunkIds: [UUID]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for chunkId in chunkIds {
            guard let entities = chunkToEntities[chunkId] else { continue }
            for entity in entities {
                counts[entity, default: 0] += 1
            }
        }
        // Only return entities appearing in multiple chunks
        return counts.filter { $0.value > 1 }
    }

    /// Get all entities for a chunk
    func entitiesForChunk(_ chunkId: UUID) -> Set<String> {
        return chunkToEntities[chunkId] ?? Set()
    }

    /// Get top entities by chunk count (for debugging/UI)
    func topEntities(limit: Int = 20) -> [(entity: String, chunkCount: Int)] {
        return entityToChunks
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Deletion

    /// Remove all entities for a specific chunk
    func removeChunk(_ chunkId: UUID) {
        guard let entities = chunkToEntities[chunkId] else { return }

        // Remove from forward index
        for entity in entities {
            entityToChunks[entity]?.remove(chunkId)
            // Clean up empty sets
            if entityToChunks[entity]?.isEmpty == true {
                entityToChunks.removeValue(forKey: entity)
            }
        }

        // Remove from reverse index
        chunkToEntities.removeValue(forKey: chunkId)

        // Update statistics
        totalEntities = entityToChunks.count
        totalIndexedChunks = chunkToEntities.count
        lastUpdated = Date()
    }

    /// Remove all chunks for a document
    func removeDocument(_ documentId: UUID) {
        guard let chunkIds = documentToChunks[documentId] else { return }

        for chunkId in chunkIds {
            removeChunk(chunkId)
        }

        documentToChunks.removeValue(forKey: documentId)
        Log.info("[EntityIndex] Removed \(chunkIds.count) chunks for document \(documentId.uuidString.prefix(8))", category: .retrieval)
    }

    /// Clear the entire index
    func clear() {
        entityToChunks.removeAll()
        chunkToEntities.removeAll()
        documentToChunks.removeAll()
        totalEntities = 0
        totalIndexedChunks = 0
        lastUpdated = Date()
        Log.info("[EntityIndex] Cleared entire index", category: .retrieval)
    }

    // MARK: - Persistence

    /// Save index to disk
    func saveToDisk() async {
        // Create snapshot data on actor
        let snapshotData = EntityIndexSnapshotData(
            entityToChunks: entityToChunks.mapValues { Array($0) },
            documentToChunks: documentToChunks.mapValues { Array($0) },
            lastUpdated: lastUpdated
        )
        let url = persistenceURL

        // Encode off-actor with nonisolated helper
        let result = await Self.encodeSnapshot(snapshotData, to: url)
        if result {
            Log.debug("[EntityIndex] Saved index to disk (\(snapshotData.entityToChunks.count) entities)", category: .retrieval)
        }
    }

    /// Nonisolated helper for encoding (avoids actor isolation of Codable)
    private nonisolated static func encodeSnapshot(_ data: EntityIndexSnapshotData, to url: URL) async -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: url, options: .atomic)
            return true
        } catch {
            Log.error("[EntityIndex] Failed to save: \(error.localizedDescription)", category: .retrieval)
            return false
        }
    }

    /// Nonisolated helper for decoding
    private nonisolated static func decodeSnapshot(from url: URL) -> EntityIndexSnapshotData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(EntityIndexSnapshotData.self, from: data)
        } catch {
            Log.error("[EntityIndex] Failed to load: \(error.localizedDescription)", category: .retrieval)
            return nil
        }
    }

    /// Load index from disk
    private func loadFromDisk() async {
        guard let snapshot = Self.decodeSnapshot(from: persistenceURL) else {
            Log.debug("[EntityIndex] No persisted index found or failed to load", category: .retrieval)
            return
        }

        // Rebuild indices from snapshot
        entityToChunks = snapshot.entityToChunks.mapValues { Set($0) }
        documentToChunks = snapshot.documentToChunks.mapValues { Set($0) }

        // Rebuild reverse index
        chunkToEntities.removeAll()
        for (entity, chunkIds) in entityToChunks {
            for chunkId in chunkIds {
                if chunkToEntities[chunkId] == nil {
                    chunkToEntities[chunkId] = Set()
                }
                chunkToEntities[chunkId]?.insert(entity)
            }
        }

        totalEntities = entityToChunks.count
        totalIndexedChunks = chunkToEntities.count
        lastUpdated = snapshot.lastUpdated

        Log.info("[EntityIndex] Loaded index from disk (\(entityToChunks.count) entities, \(chunkToEntities.count) chunks)", category: .retrieval)
    }

    // MARK: - Helpers

    /// Normalize entity text for consistent matching across representations.
    /// Handles abbreviations ("U.S.A." → "usa"), spacing variants ("Core Data" → "coredata"),
    /// punctuation ("Dr." → "dr"), and case.
    private func normalizeEntity(_ entity: String) -> String {
        var normalized = entity
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove periods (handles abbreviations: "U.S.A." → "usa", "Dr." → "dr")
        normalized = normalized.replacingOccurrences(of: ".", with: "")

        // Remove hyphens for compound matching ("co-pilot" → "copilot")
        normalized = normalized.replacingOccurrences(of: "-", with: "")

        // Collapse all whitespace to single space, then remove for canonical form
        // "Core Data" → "coredata", "New York" → "newyork"
        let components = normalized.split(separator: " ", omittingEmptySubsequences: true)
        normalized = components.joined()

        return normalized
    }

    // MARK: - Statistics

    /// Get current index statistics
    func statistics() -> EntityIndexStatistics {
        return EntityIndexStatistics(
            totalEntities: totalEntities,
            totalIndexedChunks: totalIndexedChunks,
            totalDocuments: documentToChunks.count,
            averageEntitiesPerChunk: totalIndexedChunks > 0
                ? Float(chunkToEntities.values.map { $0.count }.reduce(0, +)) / Float(totalIndexedChunks)
                : 0,
            lastUpdated: lastUpdated
        )
    }
}

// MARK: - Supporting Types

/// Snapshot for persistence (explicitly nonisolated from MainActor for Codable)
struct EntityIndexSnapshotData: Sendable {
    let entityToChunks: [String: [UUID]]
    let documentToChunks: [UUID: [UUID]]
    let lastUpdated: Date
}

extension EntityIndexSnapshotData: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityToChunks = try container.decode([String: [UUID]].self, forKey: .entityToChunks)
        documentToChunks = try container.decode([UUID: [UUID]].self, forKey: .documentToChunks)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entityToChunks, forKey: .entityToChunks)
        try container.encode(documentToChunks, forKey: .documentToChunks)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }

    private enum CodingKeys: String, CodingKey {
        case entityToChunks, documentToChunks, lastUpdated
    }
}

/// Statistics for diagnostics/UI
struct EntityIndexStatistics {
    let totalEntities: Int
    let totalIndexedChunks: Int
    let totalDocuments: Int
    let averageEntitiesPerChunk: Float
    let lastUpdated: Date
}
