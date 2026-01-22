//  ContainerService.swift
//  OpenIntelligence
//
//  Manages KnowledgeContainer list, active selection, and persistence.
//  Ensures a default "General" container exists and provides CRUD operations.
//

import Foundation
import Combine

@MainActor
final class ContainerService: ObservableObject {
    @Published private(set) var containers: [KnowledgeContainer] = []
    @Published var activeContainerId: UUID

    private let fm = FileManager.default

    init() {
        // Load containers from disk, or create a default container
        let loaded = Self.loadContainers()
        if loaded.isEmpty {
            let def = Self.defaultContainer()
            containers = [def]
            activeContainerId = def.id
            Self.saveContainers(containers)
        } else {
            containers = loaded
            // Restore last active container if saved; otherwise use first
            if let savedActive = UserDefaults.standard.string(forKey: "activeContainerId"),
               let uuid = UUID(uuidString: savedActive),
               loaded.contains(where: { $0.id == uuid }) {
                activeContainerId = uuid
            } else {
                activeContainerId = loaded.first!.id
            }
        }
        // Persist active ID
        UserDefaults.standard.set(activeContainerId.uuidString, forKey: "activeContainerId")
    }

    var activeContainer: KnowledgeContainer? {
        containers.first(where: { $0.id == activeContainerId })
    }

    func setActive(_ id: UUID) {
        guard containers.contains(where: { $0.id == id }) else { return }
        activeContainerId = id
        UserDefaults.standard.set(id.uuidString, forKey: "activeContainerId")
    }

    func createContainer(
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#4F46E5",
        description: String? = nil,
        embeddingProviderId: String = "coreml_sentence_embedding",
        embeddingDim: Int = 384,
        vectorDBKind: VectorDBKind = .persistentJSON,
        autoAdaptDimension: Bool = false,  // Disabled by default to prevent re-index loops
        retrievalConfig: RetrievalConfig? = nil
    ) -> KnowledgeContainer {
        let effectiveRetrievalConfig = retrievalConfig ?? .default
        let container = KnowledgeContainer(
            name: name,
            icon: icon,
            colorHex: colorHex,
            description: description,
            embeddingProviderId: embeddingProviderId,
            embeddingDim: embeddingDim,
            vectorDBKind: vectorDBKind,
            autoAdaptDimension: autoAdaptDimension,
            retrievalConfig: effectiveRetrievalConfig
        )
        containers.append(container)
        Self.saveContainers(containers)
        return container
    }

    func updateContainer(_ updated: KnowledgeContainer) {
        guard let idx = containers.firstIndex(where: { $0.id == updated.id }) else { return }
        containers[idx] = updated
        Self.saveContainers(containers)
    }

    func deleteContainer(id: UUID) {
        // Prevent deleting the last container; ensure at least one remains
        guard containers.count > 1 else { return }
        containers.removeAll { $0.id == id }
        if activeContainerId == id, let first = containers.first {
            activeContainerId = first.id
            UserDefaults.standard.set(first.id.uuidString, forKey: "activeContainerId")
        }
        Self.saveContainers(containers)

        // Optionally, clean up per-container files (documents + vectors)
        // Leave files in place for safety unless we add a confirmed destructive action elsewhere.
    }

    // MARK: - Stats update helpers

    func updateStats(
        for containerId: UUID,
        totalDocuments: Int? = nil,
        totalChunks: Int? = nil,
        dbSizeBytes: Int64? = nil,
        lastIndexedAt: Date? = nil
    ) {
        guard let idx = containers.firstIndex(where: { $0.id == containerId }) else { return }
        var c = containers[idx]
        if let d = totalDocuments { c.totalDocuments = d }
        if let t = totalChunks { c.totalChunks = t }
        if let s = dbSizeBytes { c.dbSizeBytes = s }
        if let li = lastIndexedAt { c.lastIndexedAt = li }
        containers[idx] = c
        Self.saveContainers(containers)
    }

    // MARK: - Persistence

    private static func loadContainers() -> [KnowledgeContainer] {
        let url = AppSupportPaths.containersListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            var decoded = try JSONDecoder().decode([KnowledgeContainer].self, from: data)

            // MIGRATION: Fix containers with incorrect embedding dimensions or unsupported providers
            // nl_contextual_embedding is not a supported provider - it falls back to CoreML at runtime
            // which causes dimension mismatch rebuilds after document import
            let validDimensions: Set<Int> = [384, 512, 1024]
            var needsSave = false

            for (idx, container) in decoded.enumerated() {
                var fixed = container
                var didFix = false

                // Fix unsupported provider: nl_contextual_embedding → coreml_sentence_embedding
                if container.embeddingProviderId == "nl_contextual_embedding" {
                    Log.warning("[ContainerService] Migrating container '\(container.name)' from unsupported nl_contextual_embedding to coreml_sentence_embedding", category: .initialization)
                    fixed.embeddingProviderId = "coreml_sentence_embedding"
                    fixed.embeddingDim = 384
                    didFix = true
                }

                // Fix invalid dimensions (only if not already fixed above)
                if !didFix, !validDimensions.contains(container.embeddingDim) {
                    Log.warning("[ContainerService] Migrating container '\(container.name)' from invalid embeddingDim \(container.embeddingDim) to 384", category: .initialization)
                    fixed.embeddingDim = 384
                    didFix = true
                }

                if didFix {
                    decoded[idx] = fixed
                    needsSave = true
                }
            }

            if needsSave {
                saveContainers(decoded)
                Log.info("[ContainerService] Migration complete - saved corrected containers", category: .initialization)
            }

            return decoded
        } catch {
            Log.error("[ContainerService] Failed to load containers: \(error.localizedDescription)", category: .initialization)
            return []
        }
    }

    private static func saveContainers(_ containers: [KnowledgeContainer]) {
        let url = AppSupportPaths.containersListURL()
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(containers)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("[ContainerService] Failed to save containers: \(error.localizedDescription)", category: .initialization)
        }
    }

    // MARK: - Quick Accessors

    /// Get document count for a specific container
    func documentCount(for containerId: UUID) -> Int {
        containers.first(where: { $0.id == containerId })?.totalDocuments ?? 0
    }

    /// Get chunk count for a specific container
    func chunkCount(for containerId: UUID) -> Int {
        containers.first(where: { $0.id == containerId })?.totalChunks ?? 0
    }

    private static func defaultContainer() -> KnowledgeContainer {
        KnowledgeContainer(
            name: "General",
            icon: "folder.fill",
            colorHex: "#4F46E5",
            description: "Default library",
            embeddingProviderId: "coreml_sentence_embedding",
            embeddingDim: 384,
            vectorDBKind: .persistentJSON,
            autoAdaptDimension: false,  // Disabled by default to prevent re-index loops
            retrievalConfig: .default
        )
    }
}
