//  ContainerService.swift
//  OpenIntelligence
//
//  Manages KnowledgeContainer list, active selection, and persistence.
//  Ensures a default "General" container exists and provides CRUD operations.
//

import Foundation
import Combine
import CoreSpotlight

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
            containers = Self.restoringLocalFingerprints(in: loaded)
            // Restore last active container if saved; otherwise use first
            if let savedActive = UserDefaults.standard.string(forKey: "activeContainerId"),
               let uuid = UUID(uuidString: savedActive),
               loaded.contains(where: { $0.id == uuid }) {
                activeContainerId = uuid
            } else {
                activeContainerId = loaded[0].id
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
        let wasChanged = activeContainerId != id
        activeContainerId = id
        UserDefaults.standard.set(id.uuidString, forKey: "activeContainerId")
        // Haptic feedback when switching containers
        if wasChanged {
            DSHaptics.selection()
        }
    }

    func reloadFromDisk() {
        let loaded = Self.loadContainers()
        if loaded.isEmpty {
            let def = Self.defaultContainer()
            containers = [def]
            activeContainerId = def.id
            Self.saveContainers(containers)
        } else {
            containers = Self.restoringLocalFingerprints(in: loaded)
            if !containers.contains(where: { $0.id == activeContainerId }) {
                if let savedActive = UserDefaults.standard.string(forKey: "activeContainerId"),
                   let uuid = UUID(uuidString: savedActive),
                   loaded.contains(where: { $0.id == uuid }) {
                    activeContainerId = uuid
                } else if let first = loaded.first {
                    activeContainerId = first.id
                }
            }
        }

        UserDefaults.standard.set(activeContainerId.uuidString, forKey: "activeContainerId")
    }

    /// The next unused default library name.
    ///
    /// Counting is not the same as numbering, and the difference is permanent once a library is
    /// deleted. The previous suggestion was `"Library \(containers.count + 1)"`, so a workspace
    /// holding General, Library 2, 3, 5 and 6 has a count of 5 and proposed "Library 6" — a name
    /// already in use, because Library 4 had been deleted. Nothing downstream rejected it, so
    /// accepting the suggestion produced two libraries with the same name, distinguishable only
    /// by UUID.
    ///
    /// This takes the highest existing `Library N` suffix rather than the count, then scans
    /// forward until the name is genuinely free, so it stays correct even for names typed by
    /// hand. Case- and whitespace-insensitive, because "library 6" collides for a reader even
    /// though it does not collide for `==`.
    func nextAvailableLibraryName() -> String {
        let taken = Set(containers.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        var candidate = containers
            .compactMap { container -> Int? in
                let name = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.lowercased().hasPrefix("library ") else { return nil }
                return Int(name.dropFirst("library ".count))
            }
            .max()
            .map { $0 + 1 } ?? (containers.count + 1)

        while taken.contains("library \(candidate)") {
            candidate += 1
        }
        return "Library \(candidate)"
    }

    func createContainer(
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#4F46E5",
        description: String? = nil,
        embeddingProviderId: String = "coreml_sentence_embedding",
        embeddingDim: Int = 384,
        vectorDBKind: VectorDBKind = .persistentJSON,
        autoAdaptDimension: Bool = true,  // Enabled by default for optimal chunking
        syncMode: LibrarySyncMode = .localOnly,
        retrievalConfig: RetrievalConfig? = nil
    ) throws -> KnowledgeContainer {
        let limit = EntitlementStore.currentLibraryLimit()
        let tier = EntitlementStore.currentEffectiveTier()
        guard containers.count < limit else {
            throw LibraryQuotaError(limit: limit, attemptedCount: containers.count + 1, tier: tier)
        }

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
            retrievalConfig: effectiveRetrievalConfig,
            syncMode: syncMode
        )
        containers.append(container)
        Self.saveContainers(containers)
        if UserDefaults.standard.object(forKey: "enableSpotlightIndexing") as? Bool ?? true {
            SpotlightIndexService.shared.indexContainer(container)
        }
        return container
    }

    func updateContainer(_ updated: KnowledgeContainer) {
        guard let idx = containers.firstIndex(where: { $0.id == updated.id }) else { return }
        containers[idx] = updated
        Self.saveContainers(containers)
        if UserDefaults.standard.object(forKey: "enableSpotlightIndexing") as? Bool ?? true {
            SpotlightIndexService.shared.indexContainer(updated)
        }
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
        Self.forgetLocalFingerprint(for: id)
        // Always deindex on delete regardless of setting
        SpotlightIndexService.shared.deindexAllDocuments(in: id)
        SpotlightIndexService.shared.deindexContainer(id: id)

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
        let current = containers[idx]

        var hasChanges = false
        if let d = totalDocuments, d != current.totalDocuments {
            hasChanges = true
        }
        if let t = totalChunks, t != current.totalChunks {
            hasChanges = true
        }
        if let s = dbSizeBytes, s != current.dbSizeBytes {
            hasChanges = true
        }
        if let li = lastIndexedAt {
            if current.lastIndexedAt == nil {
                hasChanges = true
            } else if let currentLi = current.lastIndexedAt {
                let indexedAtDelta: TimeInterval = li.timeIntervalSince(currentLi)
                if indexedAtDelta.magnitude > 0.001 {
                    hasChanges = true
                }
            }
        }

        guard hasChanges else { return }

        var c = current
        if let d = totalDocuments { c.totalDocuments = d }
        if let t = totalChunks { c.totalChunks = t }
        if let s = dbSizeBytes { c.dbSizeBytes = s }
        if let li = lastIndexedAt { c.lastIndexedAt = li }

        containers[idx] = c
        Self.saveContainers(containers)
    }

    // MARK: - Persistence

    // MARK: - Embedding fingerprints, kept on this device

    /// A library's embedding fingerprint says which pipeline wrote the vectors on this device. It
    /// lives in the library list, which is rewritten by every save and by workspace sync, and it
    /// was lost there: on the owner's iPhone on 2026-10-07 a fingerprint recorded at 16:08:32 was
    /// gone after the list was reloaded at 16:10:02, and the next question flagged a library built
    /// three minutes earlier for a rebuild. This record is the same value kept where neither a
    /// stale list nor a merged one can drop it.
    private static let localFingerprintsKey = "containerEmbeddingFingerprints.v1"

    /// The record's entry for a library: the fingerprint with the provider and dimension it was
    /// recorded under, so it is never restored onto a library whose embedder has since changed.
    nonisolated static func localFingerprintEntry(for container: KnowledgeContainer) -> String? {
        guard let fingerprint = container.embeddingFingerprint, !fingerprint.isEmpty else { return nil }
        return "\(container.embeddingProviderId)|\(container.embeddingDim)|\(fingerprint)"
    }

    /// `containers` with a missing fingerprint filled from `record` where the provider and dimension
    /// still match. A library that has a fingerprint keeps it.
    nonisolated static func restoringLocalFingerprints(
        in containers: [KnowledgeContainer], record: [String: String]
    ) -> [KnowledgeContainer] {
        containers.map { container in
            guard container.embeddingFingerprint == nil, let entry = record[container.id.uuidString] else {
                return container
            }
            let parts = entry.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, parts[0] == container.embeddingProviderId,
                Int(parts[1]) == container.embeddingDim, !parts[2].isEmpty
            else { return container }
            var restored = container
            restored.embeddingFingerprint = parts[2]
            return restored
        }
    }

    /// `record` with an entry for every library in `containers` that has a fingerprint. Entries of
    /// libraries without one are kept: keeping them is the point.
    nonisolated static func updatingLocalFingerprintRecord(
        _ record: [String: String], with containers: [KnowledgeContainer]
    ) -> [String: String] {
        var updated = record
        for container in containers {
            if let entry = localFingerprintEntry(for: container) {
                updated[container.id.uuidString] = entry
            }
        }
        return updated
    }

    private static func restoringLocalFingerprints(in containers: [KnowledgeContainer]) -> [KnowledgeContainer] {
        let record = UserDefaults.standard.dictionary(forKey: localFingerprintsKey) as? [String: String] ?? [:]
        let restored = restoringLocalFingerprints(in: containers, record: record)
        let count = zip(containers, restored).filter { $0.embeddingFingerprint != $1.embeddingFingerprint }.count
        if count > 0 {
            Log.info(
                "[ContainerService] Restored the embedding fingerprint of \(count) library(ies) from this device's record; "
                    + "the library list on disk did not carry it.",
                category: .initialization)
        }
        return restored
    }

    private static func recordLocalFingerprints(of containers: [KnowledgeContainer]) {
        let record = UserDefaults.standard.dictionary(forKey: localFingerprintsKey) as? [String: String] ?? [:]
        let updated = updatingLocalFingerprintRecord(record, with: containers)
        if updated != record {
            UserDefaults.standard.set(updated, forKey: localFingerprintsKey)
        }
    }

    private static func forgetLocalFingerprint(for id: UUID) {
        var record = UserDefaults.standard.dictionary(forKey: localFingerprintsKey) as? [String: String] ?? [:]
        if record.removeValue(forKey: id.uuidString) != nil {
            UserDefaults.standard.set(record, forKey: localFingerprintsKey)
        }
    }

    private static func loadContainers() -> [KnowledgeContainer] {
        let url = AppSupportPaths.containersListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try WorkspaceSyncService.coordinatedReadData(from: url)
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

    /// Writes of the library list land in the order they were asked for.
    ///
    /// Each save used to start its own detached task. An import saves the list many times in a
    /// few seconds, and nothing ordered those tasks, so an older list could be written after a
    /// newer one. `reloadFromDisk`, which the Documents tab calls before every workspace reload,
    /// then replaced the libraries in memory with that older list.
    private static let listWriteQueue = DispatchQueue(
        label: "Gunndamental.OpenIntelligence.container-list-write", qos: .utility)

    private static func saveContainers(_ containers: [KnowledgeContainer]) {
        let url = AppSupportPaths.containersListURL()
        recordLocalFingerprints(of: containers)
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(containers)
            listWriteQueue.async {
                do {
                    try WorkspaceSyncService.coordinatedWriteData(data, to: url)
                } catch {
                    Log.error("[ContainerService] Failed to write containers: \(error.localizedDescription)", category: .initialization)
                }
            }
        } catch {
            Log.error("[ContainerService] Failed to encode containers: \(error.localizedDescription)", category: .initialization)
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
        let defaultProviderId: String
        #if canImport(CoreAI)
        if #available(iOS 27.0, macOS 27.0, *) {
            defaultProviderId = "coreai_sentence_embedding"
        } else {
            defaultProviderId = "coreml_sentence_embedding"
        }
        #else
        defaultProviderId = "coreml_sentence_embedding"
        #endif

        return KnowledgeContainer(
            name: "General",
            icon: "folder.fill",
            colorHex: "#4F46E5",
            description: "Default library",
            embeddingProviderId: defaultProviderId,
            embeddingDim: 384,
            vectorDBKind: .persistentJSON,
            autoAdaptDimension: true,  // Enabled by default for optimal chunking
            retrievalConfig: .default
        )
    }
}
