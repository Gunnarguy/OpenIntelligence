//  VectorStoreRouter.swift
//  OpenIntelligence
//
//  Provides per-container VectorDatabase instances, routing to the correct
//  backend (persistent JSON by default; Vectura when available) and honoring
//  container-specific embedding dimensions.
//
//  MainActor-isolated for safe UI state coordination and VectorDatabase creation.
//

import Foundation

/// Routes vector database access per container with type and dimension awareness.
/// MainActor-isolated since VectorDatabase implementations are also MainActor.
@MainActor
final class VectorStoreRouter {
    private var stores: [UUID: VectorDatabase] = [:]

    init() {}

    /// Get or create a VectorDatabase for the specified container.
    /// Routes based on container's vectorDBKind and dimension.
    /// If an existing cached store has mismatched dimensions/type, it will be invalidated and recreated.
    func db(for container: KnowledgeContainer) -> VectorDatabase {
        if let existing = stores[container.id] {
            // Validate cached store still matches container config
            let existingDim = existing.dimension
            let existingKind = describeKind(existing)
            let expectedKind = container.vectorDBKind.rawValue

            if existingDim == container.embeddingDim, existingKind == expectedKind { 
                return existing
            }

            // Config mismatch - invalidate and recreate
            Log.warning("[VectorStoreRouter] Cached store mismatch for container \(container.id): dim \(existingDim)->\(container.embeddingDim), kind \(existingKind)->\(expectedKind). Recreating.", category: .vectorDB)
            stores.removeValue(forKey: container.id)
        }

        let created: VectorDatabase

        switch container.vectorDBKind {
        case .persistentJSON:
            // Default: per-container JSON file (persistent)
            let url = AppSupportPaths.vectorsFileURL(containerId: container.id)
            created = PersistentVectorDatabase(storageURL: url, dimension: container.embeddingDim)

        case .inMemory:
            // Volatile in-memory database (per app session)
            created = InMemoryVectorDatabase(dimension: container.embeddingDim)

        case .vecturaHNSW:
            #if canImport(VecturaKit)
            // One Vectura index per container (dimension-aware)
            created = VecturaVectorDatabase(dimension: container.embeddingDim)
            #else
            // Fallback to persistent JSON when VecturaKit is unavailable
            let url = AppSupportPaths.vectorsFileURL(containerId: container.id)
            created = PersistentVectorDatabase(storageURL: url, dimension: container.embeddingDim)
            #endif
        }

        stores[container.id] = created
        return created
    }

    /// Describe the kind of a VectorDatabase for comparison
    private func describeKind(_ db: VectorDatabase) -> String {
        if db is InMemoryVectorDatabase {
            return VectorDBKind.inMemory.rawValue
        } else if db is PersistentVectorDatabase {
            return VectorDBKind.persistentJSON.rawValue
        }
        #if canImport(VecturaKit)
            if db is VecturaVectorDatabase {
                return VectorDBKind.vecturaHNSW.rawValue
            }
        #endif
        return "unknown"
    }

    /// Remove a cached store for a container (e.g., when deleted).
    func invalidate(containerId: UUID) {
        stores.removeValue(forKey: containerId)
    }

    /// Invalidate cache AND delete persisted vector data for a container.
    /// Call this when embedding dimension or provider changes to ensure a fresh start.
    func invalidateAndClearStorage(containerId: UUID) {
        // Remove from cache
        stores.removeValue(forKey: containerId)

        // Delete the persisted vector database file
        let url = AppSupportPaths.vectorsFileURL(containerId: containerId)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                Log.info("[VectorStoreRouter] Cleared vector storage for container \(containerId)", category: .vectorDB)
            }
        } catch {
            Log.error("[VectorStoreRouter] Failed to clear vector storage: \(error.localizedDescription)", category: .vectorDB)
        }
    }

    /// Clear all cached stores.
    func clearAll() {
        stores.removeAll()
    }

    /// Check if a store is already cached for a container.
    func hasStore(for containerId: UUID) -> Bool {
        return stores[containerId] != nil
    }

    /// Get statistics across all active stores.
    func aggregateStatistics() async -> [UUID: VectorDatabaseStats] {
        let snapshot = stores

        var results: [UUID: VectorDatabaseStats] = [:]
        for (id, db) in snapshot {
            results[id] = await db.statistics()
        }
        return results
    }
}
