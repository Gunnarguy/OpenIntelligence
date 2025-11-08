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
        embeddingProviderId: String = "nl_embedding",
        embeddingDim: Int = 512,
        vectorDBKind: VectorDBKind = .persistentJSON,
        strictMode: Bool = true
    ) -> KnowledgeContainer {
        let container = KnowledgeContainer(
            name: name,
            icon: icon,
            colorHex: colorHex,
            description: description,
            embeddingProviderId: embeddingProviderId,
            embeddingDim: embeddingDim,
            vectorDBKind: vectorDBKind,
            strictMode: strictMode
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
            let decoded = try JSONDecoder().decode([KnowledgeContainer].self, from: data)
            return decoded
        } catch {
            print("❌ [ContainerService] Failed to load containers: \(error.localizedDescription)")
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
            // print("💾 [ContainerService] Saved \(containers.count) containers")
        } catch {
            print("❌ [ContainerService] Failed to save containers: \(error.localizedDescription)")
        }
    }
    
    private static func defaultContainer() -> KnowledgeContainer {
        KnowledgeContainer(
            name: "General",
            icon: "folder.fill",
            colorHex: "#4F46E5",
            description: "Default library",
            embeddingProviderId: "nl_embedding",
            embeddingDim: 512,
            vectorDBKind: .persistentJSON,
            strictMode: true
        )
    }
}
