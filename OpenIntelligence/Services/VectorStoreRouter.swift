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
    func db(for container: KnowledgeContainer) -> VectorDatabase {
        if let existing = stores[container.id] {
            return existing
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
    
    /// Remove a cached store for a container (e.g., when deleted).
    func invalidate(containerId: UUID) {
        stores.removeValue(forKey: containerId)
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
