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

        // Persist BEFORE evicting, and only evict what disk now holds.
        //
        // This used to remove stores from the cache unconditionally. A store whose writes were
        // still buffered (`storeBatch` defers persistence) lost those chunks with nothing ever
        // reaching disk — while document metadata, saved eagerly elsewhere, survived. That is the
        // exact "documents present, 0 chunks" phantom this app has produced repeatedly, and
        // on-device generation is precisely when memory warnings fire, so a fresh import queried
        // under Deep Think was the likeliest store to die. Observed end to end on 2026-08-20:
        // 197 searchable chunks answering queries, then `no vector store yet` after relaunch.
        //
        // `persist()` no-ops on clean stores, so the extra cost lands only on dirty ones — the
        // ones that must not be dropped. On a persist failure the store stays cached: keeping
        // memory over losing data is the whole point of this cache existing.
        Log.warning("[VectorStoreRouter] Memory pressure - persisting then evicting \(evictableIds.count) inactive container stores", category: .vectorDB)
        for id in evictableIds {
            guard let store = stores[id] else { continue }
            Task { @MainActor [weak self] in
                do {
                    try await store.persist()
                    self?.stores.removeValue(forKey: id)
                } catch {
                    Log.error(
                        "[VectorStoreRouter] Refusing to evict container \(id): persist failed (\(error.localizedDescription)). Keeping it in memory rather than losing buffered chunks.",
                        category: .vectorDB
                    )
                }
            }
        }
    }

    /// Persist every cached store that has pending data. `persist()` no-ops on clean stores.
    ///
    /// Called when the app leaves the foreground: buffered chunks must not depend on the process
    /// surviving until the next explicit persist. See `handleMemoryPressure` for the data-loss
    /// history behind this.
    func persistAll() async {
        for (id, store) in stores {
            do { try await store.persist() } catch {
                Log.error(
                    "[VectorStoreRouter] Terminal persist failed for container \(id): \(error.localizedDescription)",
                    category: .vectorDB
                )
            }
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

            // Config mismatch - invalidate and recreate. Persist the outgoing store first: a
            // dimension or kind change arriving while writes are still buffered (SelfTuning can
            // adjust configuration right after an import) otherwise drops those chunks silently —
            // the same loss class as the eviction path above. The persist task holds its own
            // strong reference, so the data survives the cache removal below; the recreated
            // store's lazy load can in principle race the persist, which is loud in the log and
            // strictly better than the guaranteed loss this replaces.
            let outgoing = existing
            Task { @MainActor in
                do { try await outgoing.persist() } catch {
                    Log.error(
                        "[VectorStoreRouter] Persist of outgoing mismatched store \(container.id) failed: \(error.localizedDescription)",
                        category: .vectorDB
                    )
                }
            }
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
        // Drop the remembered signature too. Keeping it would let a later re-add be compared
        // against the pre-deletion state and skip a reload it genuinely needs.
        lastSeenDiskSignature.removeValue(forKey: containerId)

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

    /// On-disk signature of a store's backing files, used to skip reloads that would be no-ops.
    /// Size and modification date together: mtime alone misses a same-second rewrite, size alone
    /// misses an in-place edit that preserves length.
    private var lastSeenDiskSignature: [UUID: [String: String]] = [:]

    /// Number of consecutive `clearAll()` calls that found nothing changed. Logged when it becomes
    /// large, because a silent no-op repeated hundreds of times is indistinguishable from a working
    /// cache until someone reads a trace.
    private var consecutiveNoOpSweeps: Int = 0

    /// Current on-disk signature for a container's vector files, or `nil` if none exist yet.
    private func diskSignature(for containerId: UUID) -> [String: String] {
        let legacyURL = AppSupportPaths.vectorsFileURL(containerId: containerId)
        var signature: [String: String] = [:]
        for fileURL in BNNSVectorDatabase.binaryFileURLs(from: legacyURL) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { continue }
            let size = (attrs[.size] as? Int64) ?? -1
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
            signature[fileURL.lastPathComponent] = "\(size)@\(modified)"
        }
        return signature
    }

    /// Refresh cached stores from disk.
    ///
    /// **Reloads only the stores whose files actually changed.** The instances themselves are never
    /// evicted: `BNNSVectorDatabase` is memory-mapped, and dropping one while a caller still holds a
    /// reference would allow two live instances mapping the same file. That invariant is why this
    /// method reloads in place rather than clearing the dictionary, and it must be preserved.
    ///
    /// The check exists because this is called from `reloadWorkspaceData()`, which on 2026-08-29 was
    /// observed firing every 1.68 seconds indefinitely while the app sat idle — a workspace timer
    /// meeting a container whose orphaned state never resolves. Each call reloaded *every* cached
    /// store unconditionally, producing 2,848 vector loads in 164 idle seconds with the same store
    /// re-read 288 times. Comparing the on-disk signature first makes the idle case free while a
    /// genuine sync-driven change still reloads immediately.
    ///
    /// This bounds the damage; it does not fix the cause. The 1.68s trigger lives in
    /// `WorkspaceSyncService`.
    func clearAll() {
        var reloaded = 0
        for (containerId, db) in stores {
            let signature = diskSignature(for: containerId)
            guard lastSeenDiskSignature[containerId] != signature else { continue }
            lastSeenDiskSignature[containerId] = signature
            reloaded += 1
            Task {
                try? await db.reload()
            }
        }

        if reloaded == 0 {
            consecutiveNoOpSweeps += 1
            // Powers of two, so a runaway caller is visible in the log without the log becoming the
            // new source of churn.
            if consecutiveNoOpSweeps > 8, consecutiveNoOpSweeps & (consecutiveNoOpSweeps - 1) == 0 {
                Log.info(
                    "[VectorStoreRouter] \(consecutiveNoOpSweeps) consecutive refreshes found no on-disk change across \(stores.count) store(s); something is calling clearAll() repeatedly",
                    category: .vectorDB
                )
            }
        } else {
            if consecutiveNoOpSweeps > 0 {
                Log.debug("[VectorStoreRouter] Refreshed \(reloaded)/\(stores.count) store(s) after \(consecutiveNoOpSweeps) no-op sweep(s)", category: .vectorDB)
            }
            consecutiveNoOpSweeps = 0
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
