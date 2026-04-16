//  ProjectionCache.swift
//  OpenIntelligence
//
//  Lightweight in-memory cache for projected coordinates used by visualization.
//  Keys by (containerId, method, sampleLimit, seed). Invalidated on ingestion/removal.

import Foundation

struct ProjectionCacheKey: Hashable {
    let containerId: UUID
    let method: String
    let sampleLimit: Int
    let seed: UInt64
}

struct ProjectionCacheEntry {
    // 3D coordinates (aligned with docIds order)
    let coords: [SIMD3<Float>]
    // Document IDs for each point (used for coloring/filtering/legend)
    let docIds: [UUID]
    // Snapshot counts for quick contribution computation
    let totalPoints: Int
    let perDocCounts: [UUID: Int]
    // Timestamp (optional future eviction policy)
    let timestamp: Date
}

final class ProjectionCache {
    static let shared = ProjectionCache()
    private init() {}

    private var store: [ProjectionCacheKey: ProjectionCacheEntry] = [:]
    private let lock = NSLock()

    func get(_ key: ProjectionCacheKey) -> ProjectionCacheEntry? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }

    func set(_ entry: ProjectionCacheEntry, for key: ProjectionCacheKey) {
        lock.lock(); defer { lock.unlock() }
        store[key] = entry
    }

    func invalidate(forContainer id: UUID) {
        lock.lock(); defer { lock.unlock() }
        store.keys.filter { $0.containerId == id }.forEach { store.removeValue(forKey: $0) }
    }

    func clearAll() {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
}
