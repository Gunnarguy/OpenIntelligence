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
import UIKit

/// Routes vector database access per container with type and dimension awareness.
/// MainActor-isolated since VectorDatabase implementations are also MainActor.
@MainActor
final class VectorStoreRouter {
    private var stores: [UUID: VectorDatabase] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    /// Track which container is currently active to preserve it during memory pressure
    var activeContainerId: UUID?

    init() {
        setupMemoryWarningObserver()
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Listens for memory warnings and evicts non-active container caches
    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            // Dispatch directly on MainActor since we're already on .main queue
            MainActor.assumeIsolated {
                strongSelf.handleMemoryPressure()
            }
        }
    }

    /// Evict non-active container stores to free memory
    /// Persistent stores will be reloaded on next access
    private func handleMemoryPressure() {
        let evictableIds = stores.keys.filter { $0 != activeContainerId }
        if evictableIds.isEmpty { return }

        Log.warning("[VectorStoreRouter] Memory pressure - evicting \(evictableIds.count) inactive container stores", category: .vectorDB)
        for id in evictableIds {
            stores.removeValue(forKey: id)
        }
    }

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
            // Default: per-container JSON file (persistent), accelerated via BNNS
            let url = AppSupportPaths.vectorsFileURL(containerId: container.id)
            created = BNNSVectorDatabase(dimension: container.embeddingDim, storageURL: url)

        case .inMemory:
            // Volatile in-memory database (per app session), accelerated via BNNS
            created = BNNSVectorDatabase(dimension: container.embeddingDim)

        case .vecturaHNSW:
            #if canImport(VecturaKit)
            // One Vectura index per container (dimension-aware)
            created = VecturaVectorDatabase(dimension: container.embeddingDim)
            #else
            // Fallback to persistent BNNS when VecturaKit is unavailable
            let url = AppSupportPaths.vectorsFileURL(containerId: container.id)
            created = BNNSVectorDatabase(dimension: container.embeddingDim, storageURL: url)
            #endif
        }

        stores[container.id] = created
        return created
    }

    /// Describe the kind of a VectorDatabase for comparison
    private func describeKind(_ db: VectorDatabase) -> String {
        if db is BNNSVectorDatabase {
            // BNNS supports both persistent and in-memory, but we default to labeling it persistent
            // as that matches the primary usage.
            return VectorDBKind.persistentJSON.rawValue
        } else if db is InMemoryVectorDatabase {
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
