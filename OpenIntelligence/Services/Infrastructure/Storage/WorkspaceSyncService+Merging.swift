//
//  WorkspaceSyncService+Merging.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    nonisolated private func migrateCanonicalWorkspaceIfNeeded(from localRoot: URL, to sharedRoot: URL) async throws {
        guard fileManager.fileExists(atPath: localRoot.path) else { return }

        let mergedContainers = try mergeContainersIfNeeded(from: localRoot, to: sharedRoot)
        let mergedDocuments = try await mergeDocumentMetadataIfNeeded(from: localRoot, to: sharedRoot)
        try mergeIngestionQueueIfNeeded(from: localRoot, to: sharedRoot)

        let localContents = try fileManager.contentsOfDirectory(
            at: localRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for entry in localContents {
            let name = entry.lastPathComponent
            guard !Self.localOnlyEntryNames.contains(name) else { continue }
            guard !Self.criticalMetadataFileNames.contains(name) else { continue }
            guard name != Self.importedDocumentsFolderName else { continue }

            let destination = sharedRoot.appendingPathComponent(name, isDirectory: entry.hasDirectoryPath)
            if fileManager.fileExists(atPath: destination.path) {
                continue
            }

            try await copyItem(at: entry, to: destination)
        }

        try await mergeVectorStoresIfNeeded(
            from: localRoot,
            to: sharedRoot,
            containers: mergedContainers,
            documents: mergedDocuments
        )
    }

    nonisolated private func mergeContainersIfNeeded(from localRoot: URL, to sharedRoot: URL) throws -> [KnowledgeContainer] {
        let localURL = localRoot.appendingPathComponent("containers.json")
        let sharedURL = sharedRoot.appendingPathComponent("containers.json")
        let localContainers = try Self.readJSONIfPresent([KnowledgeContainer].self, from: localURL) ?? []
        let sharedContainers = try Self.readJSONIfPresent([KnowledgeContainer].self, from: sharedURL) ?? []

        guard !localContainers.isEmpty || !sharedContainers.isEmpty else { return [] }

        let mergedContainers = mergeContainers(shared: sharedContainers, local: localContainers).containers
        try Self.writeJSON(mergedContainers, to: sharedURL)
        return mergedContainers
    }

    nonisolated private func mergeDocumentMetadataIfNeeded(from localRoot: URL, to sharedRoot: URL) async throws -> [Document] {
        let localDocumentsURL = localRoot.appendingPathComponent("documents_metadata.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")
        let localDocuments = try Self.readJSONIfPresent([Document].self, from: localDocumentsURL) ?? []
        let sharedDocuments = try Self.readJSONIfPresent([Document].self, from: sharedDocumentsURL) ?? []

        guard !localDocuments.isEmpty || !sharedDocuments.isEmpty else { return [] }

        let mergedDocuments = try await mergeDocuments(
            sharedDocuments.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) }
                + localDocuments.map { SourcedDocument(document: $0, sourceRoot: localRoot) },
            into: sharedRoot
        )

        try Self.writeJSON(mergedDocuments, to: sharedDocumentsURL)
        return mergedDocuments
    }

    nonisolated private func mergeIngestionQueueIfNeeded(from localRoot: URL, to sharedRoot: URL) throws {
        // Stand down entirely while a benchmark holds the runtime directories.
        //
        // `localRoot` here resolves through `applicationSupportRoot()`, which does not consult the
        // storage override, so every benchmark run merged its fixture documents into the owner's
        // real ingestion queue. The visible symptom was a "Resume interrupted upload?" prompt
        // listing fixture files on every launch, which survived being discarded because the next
        // run wrote it again.
        //
        // Fixed here rather than in `applicationSupportRoot()` on purpose. That function is also
        // resolved by four `coordinated*` iCloud primitives and by `BNNSVectorDatabase`, so making
        // it honour the override would silently redirect live iCloud sync into a temporary
        // directory. A caller that should not run during a benchmark asks; the path does not lie to
        // everyone else.
        //
        // The pin is only ever engaged by `DebugRAGValidationHarness`, so this cannot fire in a
        // shipping app.
        guard !OpenIntelligenceRuntimePaths.areOverridesPinned else {
            return
        }

        let localQueueURL = localRoot.appendingPathComponent("ingestion_queue.json")
        let sharedQueueURL = sharedRoot.appendingPathComponent("ingestion_queue.json")
        let localQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: localQueueURL)
        let sharedQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: sharedQueueURL)

        guard localQueue != nil || sharedQueue != nil else { return }

        let mergedQueue = mergeIngestionQueue(shared: sharedQueue, local: localQueue)
        guard !mergedQueue.isEmpty else {
            try? Self.coordinatedRemoveItem(at: sharedQueueURL)
            return
        }

        try Self.writeJSON(mergedQueue, to: sharedQueueURL)
    }

    nonisolated func mergeContainers(shared: [KnowledgeContainer], local: [KnowledgeContainer]) -> ContainerMergeResult {
        var orderedCanonicalIDs: [UUID] = []
        var canonicalById: [UUID: KnowledgeContainer] = [:]
        var mergeKeyToCanonicalID: [String: UUID] = [:]
        var sourceToCanonical: [UUID: UUID] = [:]
        var canonicalToSources: [UUID: [UUID]] = [:]

        func register(_ container: KnowledgeContainer) {
            if let existing = canonicalById[container.id] {
                canonicalById[container.id] = mergeContainer(primary: existing, secondary: container)
                sourceToCanonical[container.id] = container.id
                canonicalToSources[container.id] = uniqueContainerIDs(canonicalToSources[container.id] ?? [container.id])
                if let mergeKey = containerMergeKey(for: canonicalById[container.id] ?? container) {
                    mergeKeyToCanonicalID[mergeKey] = container.id
                }
                return
            }

            if let mergeKey = containerMergeKey(for: container),
               let canonicalID = mergeKeyToCanonicalID[mergeKey],
               let existing = canonicalById[canonicalID] {
                canonicalById[canonicalID] = mergeContainer(primary: existing, secondary: container)
                sourceToCanonical[container.id] = canonicalID
                canonicalToSources[canonicalID] = uniqueContainerIDs((canonicalToSources[canonicalID] ?? [canonicalID]) + [container.id])
                return
            }

            orderedCanonicalIDs.append(container.id)
            canonicalById[container.id] = container
            sourceToCanonical[container.id] = container.id
            canonicalToSources[container.id] = [container.id]
            if let mergeKey = containerMergeKey(for: container) {
                mergeKeyToCanonicalID[mergeKey] = container.id
            }
        }

        for container in sortedContainers(shared) {
            register(container)
        }

        for container in sortedContainers(local) {
            register(container)
        }

        return ContainerMergeResult(
            containers: sortedContainers(orderedCanonicalIDs.compactMap { canonicalById[$0] }),
            sourceToCanonical: sourceToCanonical,
            canonicalToSources: canonicalToSources.mapValues(uniqueContainerIDs)
        )
    }

    nonisolated private func mergeContainer(primary: KnowledgeContainer, secondary: KnowledgeContainer) -> KnowledgeContainer {
        var merged = primary
        if secondary.syncMode == .iCloudShared {
            merged.syncMode = .iCloudShared
        }
        if merged.description?.isEmpty != false {
            merged.description = secondary.description
        }
        merged.totalDocuments = max(primary.totalDocuments, secondary.totalDocuments)
        merged.totalChunks = max(primary.totalChunks, secondary.totalChunks)
        merged.dbSizeBytes = max(primary.dbSizeBytes, secondary.dbSizeBytes)
        merged.lastIndexedAt = [primary.lastIndexedAt, secondary.lastIndexedAt].compactMap { $0 }.max()
        if merged.autoTagOnIngestion == nil {
            merged.autoTagOnIngestion = secondary.autoTagOnIngestion
        }
        if merged.preferredTranslationLanguage == nil {
            merged.preferredTranslationLanguage = secondary.preferredTranslationLanguage
        }
        if merged.chunkingDirective == nil {
            merged.chunkingDirective = secondary.chunkingDirective
        }
        merged.lastSelfTuneAt = [primary.lastSelfTuneAt, secondary.lastSelfTuneAt].compactMap { $0 }.max()
        return merged
    }

    nonisolated func mergeDocuments(_ sourcedDocuments: [SourcedDocument], into sharedRoot: URL) async throws -> [Document] {
        try await mergeDocumentsWithAliases(sourcedDocuments, into: sharedRoot).documents
    }

    nonisolated func mergeDocumentsWithAliases(_ sourcedDocuments: [SourcedDocument], into sharedRoot: URL) async throws -> DocumentMergeResult {
        var orderedIds: [UUID] = []
        var byId: [UUID: Document] = [:]
        var duplicateKeyToId: [String: UUID] = [:]
        var sourceToCanonical: [UUID: UUID] = [:]

        for sourcedDocument in sourcedDocuments {
            let existingDocument: Document?
            if let current = byId[sourcedDocument.document.id] {
                existingDocument = current
            } else if let duplicateKey = documentDuplicateKey(for: sourcedDocument.document),
                      let existingId = duplicateKeyToId[duplicateKey] {
                existingDocument = byId[existingId]
            } else {
                existingDocument = nil
            }

            let materialized = try await materializeDocument(
                sourcedDocument.document,
                from: sourcedDocument.sourceRoot,
                into: sharedRoot,
                reusing: existingDocument
            )

            if let existingDocument {
                let merged = mergeDocument(primary: existingDocument, secondary: materialized)
                byId[existingDocument.id] = merged
                if let duplicateKey = documentDuplicateKey(for: merged) {
                    duplicateKeyToId[duplicateKey] = existingDocument.id
                }
                sourceToCanonical[sourcedDocument.document.id] = existingDocument.id
            } else {
                orderedIds.append(materialized.id)
                byId[materialized.id] = materialized
                if let duplicateKey = documentDuplicateKey(for: materialized) {
                    duplicateKeyToId[duplicateKey] = materialized.id
                }
                sourceToCanonical[sourcedDocument.document.id] = materialized.id
            }
        }

        let mergedDocuments = orderedIds.compactMap { byId[$0] }.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt < rhs.addedAt
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }

        for document in mergedDocuments {
            sourceToCanonical[document.id] = document.id
        }

        return DocumentMergeResult(documents: mergedDocuments, sourceToCanonical: sourceToCanonical)
    }

    nonisolated private func mergeVectorStoresIfNeeded(
        from localRoot: URL,
        to sharedRoot: URL,
        containers: [KnowledgeContainer],
        documents: [Document]
    ) async throws {
        let defaultContainerId = containers.first?.id
        let documentIdsByContainer = Dictionary(grouping: documents, by: { $0.containerId ?? defaultContainerId })
            .mapValues { Set($0.map(\.id)) }

        // Instrumentation only, added 2026-08-18. No behaviour change.
        //
        // A device capture recorded 432 `[BNNS] Loaded` and 210 `[BNNS] Persisted` lines in a
        // single boot, for three stores holding 26, 182 and 1451 chunks. Each pass of the loop
        // below opens three databases (two in `loadVectorChunks`, one for the merge) and writes
        // one, and `BNNSVectorDatabase.init` reads from disk. These constructions bypass
        // `VectorStoreRouter`, which is the only thing that caches them, so nothing here is
        // reused across passes.
        //
        // This file previously carried three log statements in total, so its absence from a log
        // was not evidence it had not run. That is the reason the churn went unattributed, and
        // it is the same silent-stage failure the rest of this pipeline keeps producing.
        let mergeCandidates = containers.filter { $0.vectorDBKind == .persistentJSON }
        var storeOpens = 0
        var storeWrites = 0
        Log.info(
            "[WorkspaceSyncService] Vector merge pass starting: \(mergeCandidates.count) candidate container(s)",
            category: .vectorDB
        )
        defer {
            Log.info(
                "[WorkspaceSyncService] Vector merge pass complete: \(storeOpens) store open(s), \(storeWrites) write(s)",
                category: .vectorDB
            )
        }

        for container in containers where container.vectorDBKind == .persistentJSON {
            let localVectorURL = vectorStoreBaseURL(for: container.id, in: localRoot)
            let sharedVectorURL = vectorStoreBaseURL(for: container.id, in: sharedRoot)

            guard vectorStoreExists(for: container.id, in: localRoot),
                  vectorStoreExists(for: container.id, in: sharedRoot)
            else {
                continue
            }

            await ensureItemsAvailableLocally(vectorStoreArtifactURLs(for: container.id, in: sharedRoot))

            let canonicalDocumentIds = documentIdsByContainer[container.id] ?? []
            guard !canonicalDocumentIds.isEmpty else { continue }

            storeOpens += 2
            let localChunks = try await loadVectorChunks(from: localVectorURL, dimension: container.embeddingDim)
            let sharedChunks = try await loadVectorChunks(from: sharedVectorURL, dimension: container.embeddingDim)
            let mergedChunks = Self.mergeVectorChunks(
                shared: sharedChunks,
                local: localChunks,
                allowedDocumentIds: canonicalDocumentIds
            )

            storeOpens += 1
            if !mergedChunks.isEmpty {
                storeWrites += 1
            }
            try await persistVectorChunksIntoICloud(mergedChunks, dimension: container.embeddingDim, to: sharedVectorURL)
        }
    }

    nonisolated func loadVectorChunks(from storageURL: URL, dimension: Int) async throws -> [DocumentChunk] {
        // Instrumentation only. Every call constructs a database, and construction reads from
        // disk; see the note in `mergeVectorStoresIfNeeded`.
        Log.debug(
            "[WorkspaceSyncService] loadVectorChunks opening \(storageURL.lastPathComponent)",
            category: .vectorDB
        )
        let database = await MainActor.run {
            BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        }
        let storedChunks = try await database.allChunks()
        let embeddings = await database.getEmbeddings(forIndices: Array(storedChunks.indices))

        return zip(storedChunks, embeddings).compactMap { chunk, embedding in
            guard embedding.count == dimension else { return nil }
            return DocumentChunk(
                id: chunk.id,
                documentId: chunk.documentId,
                content: chunk.content,
                parentContent: chunk.parentContent,
                contextualPrefix: chunk.contextualPrefix,
                embedding: embedding,
                metadata: chunk.metadata
            )
        }
    }

    nonisolated static func mergeVectorChunks(
        shared: [DocumentChunk],
        local: [DocumentChunk],
        allowedDocumentIds: Set<UUID>
    ) -> [DocumentChunk] {
        var orderedIds: [UUID] = []
        var byId: [UUID: DocumentChunk] = [:]
        var duplicateKeyToId: [String: UUID] = [:]

        func ingest(_ chunks: [DocumentChunk]) {
            for chunk in chunks where allowedDocumentIds.contains(chunk.documentId) {
                if byId[chunk.id] != nil {
                    continue
                }

                let duplicateKey = vectorChunkDuplicateKey(for: chunk)
                if let existingId = duplicateKeyToId[duplicateKey], byId[existingId] != nil {
                    continue
                }

                orderedIds.append(chunk.id)
                byId[chunk.id] = chunk
                duplicateKeyToId[duplicateKey] = chunk.id
            }
        }

        ingest(shared)
        ingest(local)

        return orderedIds.compactMap { byId[$0] }.sorted { lhs, rhs in
            if lhs.documentId != rhs.documentId {
                return lhs.documentId.uuidString < rhs.documentId.uuidString
            }
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
    }

    nonisolated private static func vectorChunkDuplicateKey(for chunk: DocumentChunk) -> String {
        "\(chunk.documentId.uuidString)|\(chunk.metadata.chunkIndex)|\(chunk.content)"
    }

    nonisolated func applyingDocumentAliases(to chunks: [DocumentChunk], aliases: [UUID: UUID]) -> [DocumentChunk] {
        chunks.map { chunk in
            guard let canonicalDocumentId = aliases[chunk.documentId], canonicalDocumentId != chunk.documentId else {
                return chunk
            }

            return DocumentChunk(
                id: chunk.id,
                documentId: canonicalDocumentId,
                content: chunk.content,
                parentContent: chunk.parentContent,
                contextualPrefix: chunk.contextualPrefix,
                embedding: chunk.embedding,
                metadata: chunk.metadata
            )
        }
    }

    nonisolated private func materializeDocument(
        _ document: Document,
        from sourceRoot: URL,
        into sharedRoot: URL,
        reusing existingDocument: Document?
    ) async throws -> Document {
        let sourceURL = resolvedDocumentSourceURL(for: document, sourceRoot: sourceRoot)

        let destinationURL: URL
        if let existingRelativePath = existingDocument?.storageRelativePath {
            destinationURL = sharedRoot.appendingPathComponent(existingRelativePath)
        } else if let relativePath = document.storageRelativePath {
            destinationURL = sharedRoot.appendingPathComponent(relativePath)
        } else if sourceURL != nil {
            destinationURL = nextAvailableImportedDocumentURL(in: sharedRoot, preferredFileName: document.filename)
        } else {
            return document
        }

        if let sourceURL,
           sourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
           !fileManager.fileExists(atPath: destinationURL.path) {
            try await copyItem(at: sourceURL, to: destinationURL)
        }

        return Document(
            id: existingDocument?.id ?? document.id,
            filename: document.filename,
            fileURL: destinationURL,
            storageRelativePath: relativePath(from: sharedRoot, to: destinationURL),
            fileHash: document.fileHash ?? existingDocument?.fileHash,
            contentType: document.contentType,
            addedAt: document.addedAt,
            totalChunks: document.totalChunks,
            processingMetadata: document.processingMetadata,
            containerId: document.containerId ?? existingDocument?.containerId,
            contentTags: document.contentTags
        )
    }

    nonisolated func resolvedDocumentSourceURL(for document: Document, sourceRoot: URL) -> URL? {
        if let relativePath = document.storageRelativePath {
            let rootRelativeURL = sourceRoot.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: rootRelativeURL.path) {
                return rootRelativeURL
            }
        }

        let resolvedURL = document.fileURL
        if fileManager.fileExists(atPath: resolvedURL.path) {
            return resolvedURL
        }

        return nil
    }

    nonisolated func mergeDocument(primary: Document, secondary: Document) -> Document {
        let primaryScore = documentQualityScore(primary)
        let secondaryScore = documentQualityScore(secondary)
        let preferred = secondaryScore > primaryScore ? secondary : primary
        let fallback = preferred.id == primary.id ? secondary : primary

        return Document(
            id: primary.id,
            filename: preferred.filename,
            fileURL: preferred.fileURL,
            storageRelativePath: preferred.storageRelativePath ?? fallback.storageRelativePath,
            fileHash: preferred.fileHash ?? fallback.fileHash,
            contentType: preferred.contentType,
            addedAt: min(primary.addedAt, secondary.addedAt),
            totalChunks: max(primary.totalChunks, secondary.totalChunks),
            processingMetadata: preferred.processingMetadata ?? fallback.processingMetadata,
            containerId: primary.containerId ?? secondary.containerId,
            contentTags: mergeContentTags(primary.contentTags, secondary.contentTags)
        )
    }

    nonisolated private func documentQualityScore(_ document: Document) -> Int {
        var score = document.totalChunks * 100
        if document.processingMetadata != nil { score += 40 }
        if document.storageRelativePath != nil { score += 20 }
        if document.fileHash != nil { score += 10 }
        score += document.contentTags?.count ?? 0
        return score
    }

    nonisolated private func mergeContentTags(_ lhs: [String]?, _ rhs: [String]?) -> [String]? {
        let merged = Array(Set((lhs ?? []) + (rhs ?? []))).sorted()
        return merged.isEmpty ? nil : merged
    }

    nonisolated func documentDuplicateKey(for document: Document) -> String? {
        if let fileHash = document.fileHash {
            return "hash:\(document.containerId?.uuidString ?? "global"):\(fileHash)"
        }

        if let relativePath = document.storageRelativePath {
            return "path:\(relativePath)"
        }

        return nil
    }

    nonisolated func mergeIngestionQueue(
        shared: PersistedIngestionQueueStateRecord?,
        local: PersistedIngestionQueueStateRecord?,
        includeLocalItems: Bool = true
    ) -> PersistedIngestionQueueStateRecord {
        let now = Date()
        let mergedTombstones = IngestionQueueTombstonePolicy.merged(
            shared?.tombstones ?? [],
            local?.tombstones ?? []
        )
        let tombstonedIDs = Set(mergedTombstones.map(\.id))
        var orderedIds: [UUID] = []
        var itemsById: [UUID: IngestionItem] = [:]
        var itemKeyToId: [String: UUID] = [:]
        var contextById: [UUID: IngestionContext] = [:]

        func ingest(_ state: PersistedIngestionQueueStateRecord?) {
            guard let state else { return }
            let stateContextMap = Dictionary(state.contexts.map { ($0.id, $0.context) }, uniquingKeysWith: { first, _ in first })

            for item in state.items {
                guard !tombstonedIDs.contains(item.id) else { continue }
                if item.stage.isTerminal {
                    if let finishedAt = item.finishedAt, now.timeIntervalSince(finishedAt) > 900 {
                        continue
                    }
                }
                let itemKey = ingestionDuplicateKey(for: item)
                if let existingId = itemKeyToId[itemKey], let existingItem = itemsById[existingId] {
                    let preferred = preferredIngestionItem(primary: existingItem, secondary: item, now: now)
                    itemsById[existingId] = preferredIngestionItemMaterialized(primaryId: existingId, preferred: preferred)
                    contextById[existingId] = stateContextMap[preferred.id] ?? contextById[existingId] ?? .userInitiated
                } else {
                    orderedIds.append(item.id)
                    itemsById[item.id] = item
                    itemKeyToId[itemKey] = item.id
                    contextById[item.id] = stateContextMap[item.id] ?? .userInitiated
                }
            }
        }

        ingest(shared)
        if includeLocalItems {
            ingest(local)
        }

        let mergedItems = orderedIds.compactMap { itemsById[$0] }
        let mergedContexts = mergedItems.map {
            PersistedIngestionContextRecord(id: $0.id, context: contextById[$0.id] ?? .userInitiated)
        }

        return PersistedIngestionQueueStateRecord(
            items: mergedItems,
            contexts: mergedContexts,
            tombstones: mergedTombstones,
            updatedAt: max(shared?.updatedAt ?? .distantPast, local?.updatedAt ?? .distantPast)
        )
    }

    nonisolated func synchronizeIngestionQueue(
        localRoot: URL,
        sharedRoot: URL,
        syncedContainerIDs: Set<UUID>,
        containerAliases: [UUID: UUID],
        strategy: SyncResolutionStrategy
    ) throws {
        let localQueueURL = localRoot.appendingPathComponent("ingestion_queue.json")
        let sharedQueueURL = sharedRoot.appendingPathComponent("ingestion_queue.json")
        let localQueue = applyingContainerAliases(
            to: try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: localQueueURL),
            aliases: containerAliases
        )
        let sharedQueue = applyingContainerAliases(
            to: try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: sharedQueueURL),
            aliases: containerAliases
        )

        let localOnlyQueue = filterIngestionQueue(localQueue, mode: .excluding(syncedContainerIDs))
        let localSyncedQueue = filterIngestionQueue(localQueue, mode: .including(syncedContainerIDs))
        let sharedSyncedQueue = filterIngestionQueue(sharedQueue, mode: .including(syncedContainerIDs))

        let mergedSyncedQueue: PersistedIngestionQueueStateRecord?
        switch strategy {
        case .mergeLibraries:
            let merged = mergeIngestionQueue(shared: sharedSyncedQueue, local: localSyncedQueue)
            mergedSyncedQueue = merged.isEmpty ? nil : merged
        case .useICloudWorkspace, .importExistingICloudLibraries:
            let merged = mergeIngestionQueue(
                shared: sharedSyncedQueue,
                local: localSyncedQueue,
                includeLocalItems: false
            )
            mergedSyncedQueue = merged.isEmpty ? nil : merged
        }

        let finalLocalQueue = mergeIngestionQueue(shared: localOnlyQueue, local: mergedSyncedQueue)

        if finalLocalQueue.isEmpty {
            try? Self.coordinatedRemoveItem(at: localQueueURL)
        } else {
            try Self.writeJSON(finalLocalQueue, to: localQueueURL)
        }

        if let mergedSyncedQueue {
            try Self.writeJSON(mergedSyncedQueue, to: sharedQueueURL)
        } else {
            try? Self.coordinatedRemoveItem(at: sharedQueueURL)
        }
    }


    nonisolated private func filterIngestionQueue(
        _ state: PersistedIngestionQueueStateRecord?,
        mode: QueueFilterMode
    ) -> PersistedIngestionQueueStateRecord? {
        guard let state else { return nil }

        let filteredItems = state.items.filter { item in
            guard let containerId = item.containerId else {
                switch mode {
                case .including:
                    return false
                case .excluding:
                    return true
                }
            }

            switch mode {
            case let .including(containerIDs):
                return containerIDs.contains(containerId)
            case let .excluding(containerIDs):
                return !containerIDs.contains(containerId)
            }
        }

        let filteredContexts = state.contexts.filter { context in
            filteredItems.contains(where: { $0.id == context.id })
        }
        let filteredTombstones = state.tombstones.filter { tombstone in
            guard let containerId = tombstone.containerId else {
                switch mode {
                case .including:
                    return false
                case .excluding:
                    return true
                }
            }

            switch mode {
            case let .including(containerIDs):
                return containerIDs.contains(containerId)
            case let .excluding(containerIDs):
                return !containerIDs.contains(containerId)
            }
        }

        let filteredState = PersistedIngestionQueueStateRecord(
            items: filteredItems,
            contexts: filteredContexts,
            tombstones: filteredTombstones,
            updatedAt: state.updatedAt
        )
        return filteredState.isEmpty ? nil : filteredState
    }

    nonisolated func filterIngestionQueueExcludingContainers(
        _ state: PersistedIngestionQueueStateRecord?,
        containerIDs: Set<UUID>,
        defaultContainerId: UUID?
    ) -> PersistedIngestionQueueStateRecord? {
        guard let state else { return nil }

        let filteredItems = state.items.filter { item in
            guard let resolvedContainerId = item.containerId ?? defaultContainerId else {
                return true
            }

            return !containerIDs.contains(resolvedContainerId)
        }

        let filteredContexts = state.contexts.filter { context in
            filteredItems.contains(where: { $0.id == context.id })
        }
        let filteredTombstones = state.tombstones.filter { tombstone in
            guard let resolvedContainerId = tombstone.containerId ?? defaultContainerId else {
                return true
            }
            return !containerIDs.contains(resolvedContainerId)
        }

        let filteredState = PersistedIngestionQueueStateRecord(
            items: filteredItems,
            contexts: filteredContexts,
            tombstones: filteredTombstones,
            updatedAt: state.updatedAt
        )
        return filteredState.isEmpty ? nil : filteredState
    }

    /// Libraries with an import this device has not finished: running, paused, or waiting to
    /// be continued after the app was ended.
    ///
    /// While an import is unfinished its passages are already in the library's vector store
    /// and its document is not in `documents_metadata.json` (`RAGService` saves the record
    /// last). `synchronizeVectorStore` works from the documents: it reads every passage of the
    /// store, keeps the ones whose document it knows, and writes the store back when that
    /// differs from what is on disk. So a pass during an import decodes the whole store to
    /// decide nothing (a device trace of 2026-10-10 holds 135 such reads of one store growing
    /// to 144,247 passages, 381 MB on disk), and in a library that has other documents it
    /// writes the store back without the passages being imported.
    ///
    /// An item another device holds the lease on is that device's import and its passages are
    /// in that device's store, so it is not listed.
    nonisolated static func librariesWithUnfinishedImports(
        in queue: PersistedIngestionQueueStateRecord?,
        deviceID: String,
        defaultContainerId: UUID?
    ) -> Set<UUID> {
        guard let queue else { return [] }
        var libraries = Set<UUID>()
        for item in queue.items where !item.stage.isTerminal {
            if let owner = item.leaseOwnerDeviceId, owner != deviceID { continue }
            if let library = item.containerId ?? defaultContainerId {
                libraries.insert(library)
            }
        }
        return libraries
    }

}
