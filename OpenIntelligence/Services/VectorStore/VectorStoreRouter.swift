//  VectorStoreRouter.swift
//  OpenIntelligence
//
//  Provides per-container VectorDatabase instances, routing to the correct
//  backend (persistent JSON by default; Vectura when available) and honoring
//  container-specific embedding dimensions.
//
//  MainActor-isolated for safe UI state coordination and VectorDatabase creation.
//
//  Container isolation is preserved at this layer: each library gets its own
//  dimension-aware vector store, cache entry, and persistence path.
//
//  See also: https://developer.apple.com/documentation/accelerate/simd
//            https://developer.apple.com/documentation/accelerate/bnns
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Accelerate

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
        #if canImport(UIKit)
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
        #endif
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
        if let bnns = db as? BNNSVectorDatabase {
            return bnns.persistenceKind.rawValue
        } else if db is InMemoryVectorDatabase {
            return VectorDBKind.inMemory.rawValue
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

        // Delete all persisted vector database files (binary + legacy JSON)
        let legacyURL = AppSupportPaths.vectorsFileURL(containerId: containerId)
        let allFiles = BNNSVectorDatabase.binaryFileURLs(from: legacyURL)
        for fileURL in allFiles {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    Log.info("[VectorStoreRouter] Deleted vector file: \(fileURL.lastPathComponent)", category: .vectorDB)
                }
            } catch {
                Log.error("[VectorStoreRouter] Failed to delete \(fileURL.lastPathComponent): \(error.localizedDescription)", category: .vectorDB)
            }
        }
    }

    /// Clear all cached stores.
    func clearAll() {
        // Keep ALL database instances to prevent multiple instances for the same URL,
        // but reload their state from disk asynchronously to reflect any sync/file updates.
        for (_, db) in stores {
            Task {
                try? await db.reload()
            }
        }
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
