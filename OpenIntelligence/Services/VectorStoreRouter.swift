//  VectorStoreRouter.swift
//  OpenIntelligence
//
//  Provides per-container VectorDatabase instances, routing to the correct
//  backend (persistent JSON by default; Vectura when available) and honoring
//  container-specific embedding dimensions.
//
//  MainActor-isolated for safe UI state coordination and VectorDatabase creation.
//
//  ## Cross-Container Search (Unified RAG)
//
//  The `searchAll()` method enables searching across ALL containers simultaneously.
//  This is essential for agentic RAG where the LLM may need to synthesize knowledge
//  from multiple knowledge bases.
//
//  Implementation leverages the Accelerate-powered BNNSVectorDatabase, performing
//  parallel container searches with Reciprocal Rank Fusion (RRF) to merge results.
//
//  See also: https://developer.apple.com/documentation/accelerate/simd
//            https://developer.apple.com/documentation/accelerate/bnns
//

import Foundation
import UIKit
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

    // MARK: - Cross-Container Search (Unified RAG)

    /// Search result enriched with container source metadata
    struct CrossContainerResult: Sendable {
        let chunk: DocumentChunk
        let similarityScore: Float
        let fusedRank: Int
        let containerId: UUID
        let containerName: String
    }

    /// Search across ALL containers using parallel vector search + Reciprocal Rank Fusion.
    ///
    /// Algorithm:
    /// 1. Query each container's vector DB in parallel (TaskGroup)
    /// 2. Collect per-container ranked results
    /// 3. Fuse rankings using RRF: score = sum(1 / (k + rank)) across containers
    /// 4. Re-rank by fused score and return top-K global results
    ///
    /// - Parameters:
    ///   - embedding: Query embedding vector (must match container dimensions)
    ///   - containers: All KnowledgeContainers to search
    ///   - topK: Maximum results to return per container (before fusion)
    ///   - globalTopK: Maximum global results after fusion
    ///   - k: RRF constant (default 60, per Cormack et al. 2009)
    ///
    /// - Returns: Fused results ranked by cross-container relevance
    ///
    /// - Note: Containers with mismatched embedding dimensions are automatically skipped.
    ///         For best results, ensure all containers use the same embedding provider.
    func searchAll(
        embedding: [Float],
        containers: [KnowledgeContainer],
        topK: Int = 10,
        globalTopK: Int = 20,
        k: Float = 60
    ) async -> [CrossContainerResult] {
        guard !containers.isEmpty else { return [] }

        let queryDim = embedding.count
        let matchingContainers = containers.filter { $0.embeddingDim == queryDim }

        if matchingContainers.isEmpty {
            Log.warning("[VectorStoreRouter] No containers match query embedding dimension \(queryDim)", category: .vectorDB)
            return []
        }

        // Parallel search across all matching containers
        let perContainerResults = await withTaskGroup(
            of: (UUID, String, [RetrievedChunk]).self
        ) { group -> [(UUID, String, [RetrievedChunk])] in
            for container in matchingContainers {
                group.addTask { [self] in
                    let database = await MainActor.run { self.db(for: container) }
                    do {
                        let results = try await database.search(embedding: embedding, topK: topK)
                        return (container.id, container.name, results)
                    } catch {
                        Log.error("[VectorStoreRouter] Search failed for container \(container.name): \(error)", category: .vectorDB)
                        return (container.id, container.name, [])
                    }
                }
            }

            var collected: [(UUID, String, [RetrievedChunk])] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Flatten and track per-chunk reciprocal rank scores
        var chunkScores: [UUID: (chunk: DocumentChunk, score: Float, containerId: UUID, containerName: String, bestSimilarity: Float)] = [:]

        for (containerId, containerName, results) in perContainerResults {
            for (idx, retrieved) in results.enumerated() {
                let rank = Float(idx + 1)
                let rrfScore = 1.0 / (k + rank)

                let chunkId = retrieved.chunk.id
                if var existing = chunkScores[chunkId] {
                    // Same chunk found in multiple containers - aggregate RRF scores
                    existing.score += rrfScore
                    existing.bestSimilarity = max(existing.bestSimilarity, retrieved.similarityScore)
                    chunkScores[chunkId] = existing
                } else {
                    chunkScores[chunkId] = (retrieved.chunk, rrfScore, containerId, containerName, retrieved.similarityScore)
                }
            }
        }

        // Sort by fused RRF score (descending)
        let sorted = chunkScores.values.sorted { $0.score > $1.score }

        // Take global top-K and assign final ranks
        let topResults = sorted.prefix(globalTopK)
        var finalResults: [CrossContainerResult] = []
        finalResults.reserveCapacity(min(globalTopK, sorted.count))

        for (idx, entry) in topResults.enumerated() {
            finalResults.append(CrossContainerResult(
                chunk: entry.chunk,
                similarityScore: entry.bestSimilarity,
                fusedRank: idx + 1,
                containerId: entry.containerId,
                containerName: entry.containerName
            ))
        }

        Log.info("[VectorStoreRouter] Cross-container search: \(matchingContainers.count) containers → \(finalResults.count) fused results", category: .vectorDB)

        return finalResults
    }
}
