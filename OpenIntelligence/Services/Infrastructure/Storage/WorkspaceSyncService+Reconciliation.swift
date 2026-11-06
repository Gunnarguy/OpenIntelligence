//
//  WorkspaceSyncService+Reconciliation.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    nonisolated func deduplicatedDocuments(_ documents: [Document]) -> [Document] {
        var orderedIDs: [UUID] = []
        var documentsByID: [UUID: Document] = [:]
        var duplicateKeyToID: [String: UUID] = [:]

        for document in documents {
            if let existing = documentsByID[document.id] {
                let merged = mergeDocument(primary: existing, secondary: document)
                documentsByID[document.id] = merged
                if let duplicateKey = documentDuplicateKey(for: merged) {
                    duplicateKeyToID[duplicateKey] = document.id
                }
                continue
            }

            if let duplicateKey = documentDuplicateKey(for: document),
               let existingID = duplicateKeyToID[duplicateKey],
               let existing = documentsByID[existingID] {
                let merged = mergeDocument(primary: existing, secondary: document)
                documentsByID[existingID] = merged
                if let mergedDuplicateKey = documentDuplicateKey(for: merged) {
                    duplicateKeyToID[mergedDuplicateKey] = existingID
                }
                continue
            }

            orderedIDs.append(document.id)
            documentsByID[document.id] = document
            if let duplicateKey = documentDuplicateKey(for: document) {
                duplicateKeyToID[duplicateKey] = document.id
            }
        }

        return sortedDocuments(orderedIDs.compactMap { documentsByID[$0] })
    }

    nonisolated func applyingContainerAliases(to documents: [Document], aliases: [UUID: UUID]) -> [Document] {
        documents.map { applyingContainerAliases(to: $0, aliases: aliases) }
    }

    nonisolated func applyingContainerAliases(to document: Document, aliases: [UUID: UUID]) -> Document {
        guard let containerId = document.containerId,
              let canonicalID = aliases[containerId],
              canonicalID != containerId
        else {
            return document
        }

        return Document(
            id: document.id,
            filename: document.filename,
            fileURL: document.fileURL,
            storageRelativePath: document.storageRelativePath,
            fileHash: document.fileHash,
            contentType: document.contentType,
            addedAt: document.addedAt,
            totalChunks: document.totalChunks,
            processingMetadata: document.processingMetadata,
            containerId: canonicalID,
            contentTags: document.contentTags
        )
    }

    nonisolated func applyingContainerAliases(
        to state: PersistedIngestionQueueStateRecord?,
        aliases: [UUID: UUID]
    ) -> PersistedIngestionQueueStateRecord? {
        guard let state else { return nil }

        let remappedItems = state.items.map { item in
            applyingContainerAliases(to: item, aliases: aliases)
        }
        let remappedTombstones = state.tombstones.map { tombstone in
            IngestionQueueTombstone(
                id: tombstone.id,
                containerId: tombstone.containerId.flatMap { aliases[$0] ?? $0 },
                discardedAt: tombstone.discardedAt
            )
        }

        let normalizedState = PersistedIngestionQueueStateRecord(
            items: remappedItems,
            contexts: state.contexts,
            tombstones: remappedTombstones,
            updatedAt: state.updatedAt
        )

        let merged = mergeIngestionQueue(shared: nil, local: normalizedState)
        return merged.isEmpty ? nil : merged
    }

    nonisolated func applyingContainerAliases(to item: IngestionItem, aliases: [UUID: UUID]) -> IngestionItem {
        guard let containerId = item.containerId,
              let canonicalID = aliases[containerId],
              canonicalID != containerId
        else {
            return item
        }

        return IngestionItem(
            id: item.id,
            url: item.url,
            storageRelativePath: item.storageRelativePath,
            containerId: canonicalID,
            documentHash: item.documentHash,
            leaseOwnerDeviceId: item.leaseOwnerDeviceId,
            leaseExpiresAt: item.leaseExpiresAt,
            lastLeaseHeartbeatAt: item.lastLeaseHeartbeatAt,
            stage: item.stage,
            detail: item.detail,
            progress: item.progress,
            startedAt: item.startedAt,
            finishedAt: item.finishedAt,
            errorMessage: item.errorMessage,
            metrics: item.metrics
        )
    }

    nonisolated func matchingSharedContainerIDs(for targetContainer: KnowledgeContainer, in containers: [KnowledgeContainer]) -> Set<UUID> {
        let normalizedTargetContainer = normalizeSharedContainer(targetContainer)

        return Set(containers.compactMap { container in
            let normalizedContainer = normalizeSharedContainer(container)

            if normalizedContainer.id == normalizedTargetContainer.id {
                return normalizedContainer.id
            }

            return nil
        })
    }

    nonisolated func containerMergeKey(for container: KnowledgeContainer) -> String? {
        guard container.syncMode == .iCloudShared else { return nil }

        // Shared-library identity must be stable and library-specific.
        // Using the display name caused unrelated libraries like "General"
        // on two devices to merge into one iCloud library.
        return container.id.uuidString.lowercased()
    }

    nonisolated func uniqueContainerIDs(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    nonisolated func jsonEncodedValuesMatch<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let lhsData = try? encoder.encode(lhs),
              let rhsData = try? encoder.encode(rhs)
        else {
            return false
        }

        return lhsData == rhsData
    }

    nonisolated func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Materialize iCloud items, returning the ones that exist in iCloud but could not be downloaded.
    ///
    /// The previous implementation guarded on `fileExists` before doing anything,
    /// which skipped precisely the files that needed downloading: an evicted or
    /// not-yet-downloaded iCloud item is represented on disk by a
    /// `.<name>.icloud` placeholder, so `fileExists` at the item's own path is
    /// `false`. Nothing was ever requested, and callers then read the item as
    /// missing. Callers that treat "missing" as "empty" must inspect the return
    /// value rather than assume success.
    @discardableResult
    nonisolated func ensureItemsAvailableLocally(_ urls: [URL], timeout: TimeInterval = 20) async -> [URL] {
        var seenPaths: Set<String> = []
        var urlsToDownload: [URL] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else { continue }
            guard ubiquitousItemExists(at: standardizedURL) else { continue }

            // Already materialized and current: nothing to wait on.
            if fileManager.fileExists(atPath: standardizedURL.path),
               !ubiquitousPlaceholderExists(for: standardizedURL),
               let values = try? standardizedURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               values.ubiquitousItemDownloadingStatus == .current {
                continue
            }

            try? fileManager.startDownloadingUbiquitousItem(at: standardizedURL)
            urlsToDownload.append(standardizedURL)
        }

        guard !urlsToDownload.isEmpty else { return [] }

        return await withTaskGroup(of: URL?.self) { group in
            for url in urlsToDownload {
                group.addTask {
                    do {
                        try await Self.ensureItemAvailableLocally(at: url, timeout: timeout)
                        return nil
                    } catch {
                        return url
                    }
                }
            }

            var unavailable: [URL] = []
            for await failure in group {
                if let failure { unavailable.append(failure) }
            }
            return unavailable
        }
    }

    /// The placeholder iCloud leaves in place of an evicted file's contents.
    nonisolated private func ubiquitousPlaceholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    nonisolated func ubiquitousPlaceholderExists(for url: URL) -> Bool {
        fileManager.fileExists(atPath: ubiquitousPlaceholderURL(for: url).path)
    }

    /// True when the item exists in iCloud, whether or not its contents are on this device.
    ///
    /// `FileManager.fileExists` alone answers "are the bytes here", which is a
    /// different question and the wrong one for deciding whether data exists.
    nonisolated func ubiquitousItemExists(at url: URL) -> Bool {
        if ubiquitousPlaceholderExists(for: url) { return true }
        return fileManager.fileExists(atPath: url.path)
    }

    nonisolated func ensureSourcedDocumentsAvailableLocally(_ sourcedDocuments: [SourcedDocument]) async {
        let urls = sourcedDocuments.compactMap { sourcedDocument in
            resolvedDocumentSourceURL(for: sourcedDocument.document, sourceRoot: sourcedDocument.sourceRoot)
        }
        await ensureItemsAvailableLocally(urls)
    }

    nonisolated func cleanupSharedWorkspace(
        sharedRoot: URL,
        syncedContainerIDs: Set<UUID>,
        referencedRelativePaths: Set<String>
    ) async throws {
        let contents = try fileManager.contentsOfDirectory(
            at: sharedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let name = item.lastPathComponent

            if name == Self.importedDocumentsFolderName {
                try await cleanupSharedImportedDocuments(at: item, referencedRelativePaths: referencedRelativePaths, sharedRoot: sharedRoot)
                continue
            }

            if let containerId = containerIdFromArtifactName(name), !syncedContainerIDs.contains(containerId) {
                try? Self.coordinatedRemoveItem(at: item)
            }
        }
    }

    nonisolated private func cleanupSharedImportedDocuments(
        at importedDocumentsDirectory: URL,
        referencedRelativePaths: Set<String>,
        sharedRoot: URL
    ) async throws {
        guard fileManager.fileExists(atPath: importedDocumentsDirectory.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: importedDocumentsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for fileURL in contents {
            guard let relativePath = relativePath(from: sharedRoot, to: fileURL) else { continue }
            guard !referencedRelativePaths.contains(relativePath) else { continue }
            try? Self.coordinatedRemoveItem(at: fileURL)
        }
    }

    nonisolated private func containerIdFromArtifactName(_ name: String) -> UUID? {
        if name.hasPrefix("vector_database_") {
            let suffixes = ["_meta.json", "_vectors.bin", "_norms.bin", ".json"]
            let remainder = String(name.dropFirst("vector_database_".count))
            for suffix in suffixes where remainder.hasSuffix(suffix) {
                let idString = String(remainder.dropLast(suffix.count))
                if let containerId = UUID(uuidString: idString) {
                    return containerId
                }
            }
        }

        let prefixes = ["chat_history_", "transcript_", "conversation_memory_"]

        for prefix in prefixes where name.hasPrefix(prefix) {
            let suffix = String(name.dropFirst(prefix.count))
            let idString = suffix.replacingOccurrences(of: ".json", with: "")
            if let containerId = UUID(uuidString: idString) {
                return containerId
            }
        }

        return nil
    }

    nonisolated func ingestionDuplicateKey(for item: IngestionItem) -> String {
        let containerKey = item.containerId?.uuidString ?? "local"

        if let documentHash = item.documentHash {
            return "hash:\(containerKey):\(documentHash)"
        }

        if let relativePath = item.storageRelativePath {
            return "path:\(containerKey):\(relativePath)"
        }

        return "id:\(containerKey):\(item.id.uuidString)"
    }

    nonisolated func preferredIngestionItem(primary: IngestionItem, secondary: IngestionItem, now: Date) -> IngestionItem {
        let primaryIsTerminal = primary.stage.isTerminal
        let secondaryIsTerminal = secondary.stage.isTerminal

        if primaryIsTerminal || secondaryIsTerminal {
            if primaryIsTerminal && !secondaryIsTerminal {
                // Same ID means they are the same ingestion attempt. Terminal wins.
                // Different IDs means the active one is a new retry attempt. Active wins.
                return primary.id == secondary.id ? primary : secondary
            } else if !primaryIsTerminal && secondaryIsTerminal {
                return primary.id == secondary.id ? secondary : primary
            } else {
                // Both are terminal. Compare finishedAt times.
                let primaryFinished = primary.finishedAt ?? .distantPast
                let secondaryFinished = secondary.finishedAt ?? .distantPast
                if primaryFinished != secondaryFinished {
                    return secondaryFinished > primaryFinished ? secondary : primary
                }
                return secondary.id.uuidString > primary.id.uuidString ? secondary : primary
            }
        }

        let primaryPriority = ingestionPriority(primary, now: now)
        let secondaryPriority = ingestionPriority(secondary, now: now)
        return secondaryPriority > primaryPriority ? secondary : primary
    }

    nonisolated func preferredIngestionItemMaterialized(primaryId: UUID, preferred: IngestionItem) -> IngestionItem {
        IngestionItem(
            id: primaryId,
            url: preferred.url,
            storageRelativePath: preferred.storageRelativePath,
            containerId: preferred.containerId,
            documentHash: preferred.documentHash,
            leaseOwnerDeviceId: preferred.leaseOwnerDeviceId,
            leaseExpiresAt: preferred.leaseExpiresAt,
            lastLeaseHeartbeatAt: preferred.lastLeaseHeartbeatAt,
            stage: preferred.stage,
            detail: preferred.detail,
            progress: preferred.progress,
            startedAt: preferred.startedAt,
            finishedAt: preferred.finishedAt,
            errorMessage: preferred.errorMessage,
            metrics: preferred.metrics
        )
    }

    nonisolated private func ingestionPriority(_ item: IngestionItem, now: Date) -> (Int, Int, Int, Int) {
        let activeLeaseScore = item.hasActiveLease(at: now) ? 1 : 0
        let stageScore: Int = {
            switch item.stage {
            case .paused: return 0
            case .queued: return 1
            case .loading: return 2
            case .transcribing: return 3
            case .extracting: return 4
            case .chunking: return 5
            case .analyzing: return 6
            case .adapting: return 7
            case .reindexing: return 8
            case .embedding: return 9
            case .indexing: return 10
            case .storing: return 11
            case .complete: return 12
            case .cancelled: return 13
            case .failed: return 14
            }
        }()
        let heartbeatScore = Int(item.lastLeaseHeartbeatAt?.timeIntervalSince1970 ?? 0)
        let progressScore = Int((item.progress ?? 0) * 1000)
        return (activeLeaseScore, stageScore, progressScore, heartbeatScore)
    }

    nonisolated func enforceLibraryLimit(for containers: [KnowledgeContainer]) throws {
        let limit = EntitlementStore.currentLibraryLimit(defaults: defaults)
        guard containers.count <= limit else {
            let tier = EntitlementStore.currentEffectiveTier(defaults: defaults)
            throw LibraryQuotaError(limit: limit, attemptedCount: containers.count, tier: tier)
        }
    }

    nonisolated func resolveSharedMetadataConflictsIfNeeded(in sharedRoot: URL) async throws {
        for fileName in Self.criticalMetadataFileNames {
            let fileURL = sharedRoot.appendingPathComponent(fileName)
            try await resolveConflictsIfNeeded(at: fileURL, sharedRoot: sharedRoot)
        }
    }

    nonisolated private func resolveConflictsIfNeeded(at url: URL, sharedRoot: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflictVersions.isEmpty else {
            return
        }

        switch url.lastPathComponent {
        case "containers.json":
            var collections: [[KnowledgeContainer]] = []
            if let current = try Self.readJSONIfPresent([KnowledgeContainer].self, from: url) {
                collections.append(current)
            }
            for version in conflictVersions where version.hasLocalContents {
                if let data = try? Data(contentsOf: version.url),
                   let decoded = try? JSONDecoder().decode([KnowledgeContainer].self, from: data) {
                    collections.append(decoded)
                }
            }
            let merged = collections.reduce(into: [KnowledgeContainer]()) { partial, next in
                partial = mergeContainers(shared: partial, local: next).containers
            }
            try Self.writeJSON(merged, to: url)

        case "documents_metadata.json":
            var sourced: [SourcedDocument] = []
            if let current = try Self.readJSONIfPresent([Document].self, from: url) {
                sourced.append(contentsOf: current.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) })
            }
            for version in conflictVersions where version.hasLocalContents {
                if let data = try? Data(contentsOf: version.url),
                   let decoded = try? JSONDecoder().decode([Document].self, from: data) {
                    sourced.append(contentsOf: decoded.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) })
                }
            }
            let merged = try await mergeDocuments(sourced, into: sharedRoot)
            try Self.writeJSON(merged, to: url)

        case "ingestion_queue.json":
            var mergedState: PersistedIngestionQueueStateRecord?
            if let current = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: url) {
                mergedState = current
            }
            for version in conflictVersions where version.hasLocalContents {
                if let data = try? Data(contentsOf: version.url),
                   let decoded = try? JSONDecoder().decode(PersistedIngestionQueueStateRecord.self, from: data) {
                    mergedState = mergeIngestionQueue(shared: mergedState, local: decoded)
                }
            }
            if let mergedState {
                try Self.writeJSON(mergedState, to: url)
            }

        default:
            break
        }

        for version in conflictVersions {
            version.isResolved = true
            try? version.remove()
        }
    }

}
