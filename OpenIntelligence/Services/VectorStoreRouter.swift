//  VectorStoreRouter.swift
//  OpenIntelligence
//
//  Provides per-container VectorDatabase instances, routing to the correct
//  backend (persistent JSON by default; Vectura when available) and honoring
//  container-specific embedding dimensions.
//

import Foundation

final class VectorStoreRouter {
    private var stores: [UUID: VectorDatabase] = [:]
    private let lock = NSLock()
    
    init() {}
    
    func db(for container: KnowledgeContainer) -> VectorDatabase {
        lock.lock()
        defer { lock.unlock() }
        
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
    
    func invalidate(containerId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        stores.removeValue(forKey: containerId)
    }
    
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        stores.removeAll()
    }
}
