//
//  WorkspaceSyncService+Artifacts.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    nonisolated func synchronizeContainerArtifacts(
        localRoot: URL,
        sharedRoot: URL,
        syncedContainers: [KnowledgeContainer],
        syncedDocuments: [Document],
        documentAliases: [UUID: UUID],
        sourceContainerIDsByCanonicalID: [UUID: [UUID]],
        librariesImportingAtPassStart: Set<UUID>,
        strategy: SyncResolutionStrategy
    ) async throws {
        let defaultContainerId = syncedContainers.first?.id
        let documentIdsByContainer = Dictionary(grouping: syncedDocuments, by: { resolvedContainerID(for: $0, defaultContainerId: defaultContainerId) })
            .mapValues { Set($0.map(\.id)) }

        // Two readings of the import queue, joined. The one from the start of the pass covers
        // an import that finished while the pass ran: its document was not in the pass's
        // snapshot, so `syncedDocuments` does not know it. The one taken here covers an import
        // that started since. A queue that cannot be read is treated as every library
        // importing, because the cost of waiting one pass is nothing and the cost of guessing
        // wrong is a store written back without an import's passages.
        var librariesImporting = librariesImportingAtPassStart
        var importQueueIsReadable = true
        do {
            librariesImporting.formUnion(Self.librariesWithUnfinishedImports(
                in: try Self.readJSONIfPresent(
                    PersistedIngestionQueueStateRecord.self,
                    from: localRoot.appendingPathComponent("ingestion_queue.json")
                ),
                deviceID: Self.currentDeviceID(defaults: defaults),
                defaultContainerId: defaultContainerId
            ))
        } catch {
            importQueueIsReadable = false
            Log.warning(
                "[WorkspaceSync] The import queue could not be read (\(error.localizedDescription)); leaving every vector store alone this pass.",
                category: .ingestion
            )
        }

        let conflictCopies = Self.conflictCopyCount(in: sharedRoot)
        if conflictCopies > 0 {
            Log.info(
                "[WorkspaceSync] The iCloud folder holds \(conflictCopies) conflict copies of library files (\"<name> 2.json\" and the like); the app reads none of them.",
                category: .ingestion
            )
        }

        for container in syncedContainers {
            let allowedDocumentIds = documentIdsByContainer[container.id] ?? []
            let sourceContainerIDs = Set(sourceContainerIDsByCanonicalID[container.id] ?? [container.id])
            if !importQueueIsReadable || !sourceContainerIDs.isDisjoint(with: librariesImporting) {
                Log.debug(
                    "[WorkspaceSyncService] Vector store for \(container.id) left alone this pass: an import into it has not finished",
                    category: .vectorDB
                )
            } else {
                try await synchronizeVectorStore(
                    for: container,
                    localRoot: localRoot,
                    sharedRoot: sharedRoot,
                    sourceContainerIDs: sourceContainerIDs,
                    allowedDocumentIds: allowedDocumentIds,
                    documentAliases: documentAliases,
                    strategy: strategy
                )
            }

            try await synchronizeAuxiliaryFile(
                filePrefix: "chat_history_",
                canonicalContainerID: container.id,
                sourceContainerIDs: sourceContainerIDs,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                strategy: strategy
            )
            try await synchronizeAuxiliaryFile(
                filePrefix: "transcript_",
                canonicalContainerID: container.id,
                sourceContainerIDs: sourceContainerIDs,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                strategy: strategy
            )
            try await synchronizeAuxiliaryFile(
                filePrefix: "conversation_memory_",
                canonicalContainerID: container.id,
                sourceContainerIDs: sourceContainerIDs,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                strategy: strategy
            )
            try await synchronizeEvidenceThreads(
                canonicalContainerID: container.id,
                sourceContainerIDs: sourceContainerIDs,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                strategy: strategy
            )
        }
    }

    nonisolated private func synchronizeVectorStore(
        for container: KnowledgeContainer,
        localRoot: URL,
        sharedRoot: URL,
        sourceContainerIDs: Set<UUID>,
        allowedDocumentIds: Set<UUID>,
        documentAliases: [UUID: UUID],
        strategy: SyncResolutionStrategy
    ) async throws {
        let localVectorURL = vectorStoreBaseURL(for: container.id, in: localRoot)
        let sharedVectorURL = vectorStoreBaseURL(for: container.id, in: sharedRoot)

        guard container.vectorDBKind == .persistentJSON else {
            removeVectorStoreArtifacts(for: container.id, in: sharedRoot, reason: "library does not use the persistent JSON vector store")
            removeVectorStoreArtifacts(for: container.id, in: localRoot, reason: "library does not use the persistent JSON vector store")
            for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
                removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot, reason: "merge source of a non-JSON vector store")
                removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot, reason: "merge source of a non-JSON vector store")
            }
            return
        }

        // Fast path: nothing this pass reads has changed since a pass that concluded there
        // was nothing to write. Skipping here avoids two full store reads per container per
        // sync pass, which is where 43,164 chunk deserialisations for zero writes came from.
        //
        // Placed after the `vectorDBKind` guard on purpose — that branch performs cleanup and
        // must not be skipped — and before the loads, which are the cost being avoided.
        let currentSignature = vectorStoreSignature(
            for: container.id,
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            sourceContainerIDs: sourceContainerIDs,
            allowedDocumentIds: allowedDocumentIds,
            documentAliases: documentAliases,
            strategy: strategy
        )
        if let currentSignature,
           vectorStoreSyncSignatures.withLock({ $0[container.id] }) == Self.vectorStoreSignatureDigest(currentSignature) {
            Log.debug(
                "[WorkspaceSyncService] Vector stores for \(container.id) unchanged since the last "
                    + "pass found them current; skipping read of both roots",
                category: .vectorDB
            )
            return
        }

        var localChunks: [DocumentChunk] = []
        for sourceContainerID in sourceContainerIDs where vectorStoreExists(for: sourceContainerID, in: localRoot) {
            localChunks += try await loadVectorChunks(
                from: vectorStoreBaseURL(for: sourceContainerID, in: localRoot),
                dimension: container.embeddingDim
            )
        }
        localChunks = applyingDocumentAliases(to: localChunks, aliases: documentAliases)

        let sharedArtifactURLs = sourceContainerIDs.flatMap { vectorStoreArtifactURLs(for: $0, in: sharedRoot) }
        await ensureItemsAvailableLocally(sharedArtifactURLs)

        // Fail closed. Everything below merges the shared and local stores and
        // writes the result over both, deleting them outright when the merge is
        // empty. A shared store we could not download reads as zero chunks, so
        // continuing here would delete another device's index and tell the user
        // to re-import documents that were never lost.
        let unmaterialized = sourceContainerIDs
            .filter { vectorStoreIsUnmaterialized(for: $0, in: sharedRoot) }
            .sorted { $0.uuidString < $1.uuidString }
        if !unmaterialized.isEmpty {
            Log.warning(
                "[WorkspaceSync] Shared vector store not downloaded for \(unmaterialized.count) container(s); aborting merge to avoid destroying it. Containers: \(unmaterialized.map(\.uuidString).joined(separator: ", "))",
                category: .vectorDB
            )
            throw WorkspaceSyncError.sharedVectorStoreUnavailable(containerIDs: unmaterialized)
        }

        var sharedChunks: [DocumentChunk] = []
        for sourceContainerID in sourceContainerIDs where vectorStoreExists(for: sourceContainerID, in: sharedRoot) {
            sharedChunks += try await loadVectorChunks(
                from: vectorStoreBaseURL(for: sourceContainerID, in: sharedRoot),
                dimension: container.embeddingDim
            )
        }
        sharedChunks = applyingDocumentAliases(to: sharedChunks, aliases: documentAliases)

        let resolvedChunks: [DocumentChunk]
        switch strategy {
        case .mergeLibraries:
            resolvedChunks = Self.mergeVectorChunks(shared: sharedChunks, local: localChunks, allowedDocumentIds: allowedDocumentIds)
        case .useICloudWorkspace, .importExistingICloudLibraries:
            resolvedChunks = sharedChunks.filter { allowedDocumentIds.contains($0.documentId) }
        }

        if resolvedChunks.isEmpty {
            // An empty resolution for a library that still has documents means we
            // failed to read an index, not that the index should not exist.
            // Deleting here is what turned a slow download into missing documents
            // and a phantom "resume interrupted import?" prompt. Leave both stores
            // alone; a stale index is recoverable, a deleted one is not.
            //
            // Three very different situations reach this point and they were all
            // reported the same way, which made the log unactionable. Separate
            // them, because only one is a defect:
            //
            //   1. Nothing is indexed yet. Benign — ingestion has not run.
            //   2. Stores exist but read as empty. A read failure; keep them.
            //   3. Chunks loaded but none belong to this library's documents.
            //      The index is orphaned from the metadata, so re-ingesting is
            //      genuinely required. Still not ours to delete.
            guard allowedDocumentIds.isEmpty else {
                let loadedChunkCount = localChunks.count + sharedChunks.count
                let anyStoreExists = sourceContainerIDs.contains {
                    vectorStoreExists(for: $0, in: localRoot) || vectorStoreExists(for: $0, in: sharedRoot)
                }

                if loadedChunkCount > 0 {
                    // Case 3. Name the mismatch so the next device log identifies
                    // which documents the orphaned chunks actually belong to.
                    let chunkDocumentIDs = Set((localChunks + sharedChunks).map(\.documentId))
                    Log.error(
                        """
                        [WorkspaceSync] Orphaned index for container \(container.id): \
                        loaded \(loadedChunkCount) chunk(s) spanning \(chunkDocumentIDs.count) document id(s), \
                        none of which are among this library's \(allowedDocumentIds.count) document(s). \
                        Chunk docs: \(chunkDocumentIDs.map(\.uuidString).sorted().prefix(5).joined(separator: ", ")). \
                        Library docs: \(allowedDocumentIds.map(\.uuidString).sorted().prefix(5).joined(separator: ", ")). \
                        Leaving both stores untouched.
                        """,
                        category: .vectorDB
                    )
                } else if anyStoreExists {
                    // Case 2.
                    Log.warning(
                        "[WorkspaceSync] Vector store for container \(container.id) exists but read as empty while the library still has \(allowedDocumentIds.count) document(s). Treating as a failed read and leaving it untouched.",
                        category: .vectorDB
                    )
                } else {
                    // Case 1 — not a defect, and not worth an error every sync pass.
                    Log.debug(
                        "[WorkspaceSync] Container \(container.id) has \(allowedDocumentIds.count) document(s) and no vector store yet; nothing to merge.",
                        category: .vectorDB
                    )
                }
                return
            }

            // `allowedDocumentIds` is empty. Usually that is a genuinely emptied
            // library whose store should go with it. It is also exactly what an
            // in-flight import looks like: `RAGService` persists vectors as soon
            // as embedding finishes and saves the document record only later, so
            // for the whole span between those two writes the library reads as
            // having no documents while its store is being filled.
            //
            // A device capture on 2026-08-24 caught this deleting a just-written
            // store twice — at log lines 6685 and 6881, for a document that had
            // embedded 196 chunks seconds earlier — leaving the library holding
            // the document, its chunk count and its FTS5 rows with no semantic
            // retrieval at all. Three sessions read that as a failure to write,
            // because the deletion below logged nothing. Switching libraries
            // mid-import widens the window but is not required to hit it.
            //
            // So chunks on disk with no documents in metadata is not proof the
            // index is garbage; during an import it is proof the metadata has not
            // caught up yet. Apply the rule the branch above already states: a
            // stale index is recoverable, a deleted one is not. The residual cost
            // is a store left behind by a genuinely empty library after a partial
            // chunk-removal failure, which leaks disk rather than losing work, and
            // which the error below makes visible instead of silent.
            //
            // Logged under `.ingestion` rather than `.vectorDB` on purpose: only
            // the categories in `LoggingConfiguration.fileLogCategories` reach the
            // trace a user can share, `.vectorDB` is not one of them, and
            // `writeToFile` has no level filter — so adding `.vectorDB` wholesale
            // would put 1,311 `loadVectorChunks` debug lines per session into a
            // 500 KB rotating file and push out the evidence this line exists to
            // provide. The reader who needs this is looking at an ingestion trace
            // because an import lost its vectors.
            let unreferencedChunkCount = localChunks.count + sharedChunks.count
            guard unreferencedChunkCount == 0 else {
                Log.info(
                    "[WorkspaceSync] Container \(container.id) has no documents in metadata but its vector store holds \(unreferencedChunkCount) chunk(s); refusing to delete. An import may still be writing.",
                    category: .ingestion
                )
                return
            }

            removeVectorStoreArtifacts(for: container.id, in: sharedRoot, reason: "library has no documents and no indexed chunks")
            removeVectorStoreArtifacts(for: container.id, in: localRoot, reason: "library has no documents and no indexed chunks")
            for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
                removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot, reason: "merge source of an empty library")
                removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot, reason: "merge source of an empty library")
            }
            return
        }

        // Skip a write whose destination already holds exactly this content.
        //
        // Both stores were just read into `localChunks` and `sharedChunks` a few lines above, so
        // the comparison is free: no extra I/O, and it is exact rather than a heuristic. A device
        // capture on 2026-08-18 recorded 96 store opens and 48 rewrites in one boot, ~200 MB
        // written for zero content change, roughly half of it queued to iCloud as replacement
        // uploads. Each `persistVectorChunks` call does `clear()` then `storeBatch()` then
        // `persist()`, so an unchanged pass was deleting and rewriting three real files per store
        // per destination.
        //
        // The predicate is deliberately strict. It compares every field that gets persisted,
        // including the full embedding, so a re-embed that keeps chunk ids still writes — that is
        // the case an id-only or count-only check would silently skip, and this subsystem's own
        // comments record a past incident of exactly that shape. ~557k float comparisons for the
        // largest store here costs far less than the 4 MB write it avoids.
        //
        // Consolidation is excluded outright: when `sourceContainerIDs` names more than this
        // container, `localChunks` is a union gathered from several stores and is not the content
        // of `localVectorURL`, so the comparison would not mean what it says. Those passes write
        // unconditionally, as before.
        let isSingleSourceMerge = sourceContainerIDs == [container.id]

        let localAlreadyCurrent = isSingleSourceMerge
            && vectorStoreExists(for: container.id, in: localRoot)
            && vectorChunksAreIdentical(resolvedChunks, localChunks)
        if localAlreadyCurrent {
            Log.debug(
                "[WorkspaceSyncService] Local vector store already current for \(container.id); skipping rewrite of \(resolvedChunks.count) chunk(s)",
                category: .vectorDB
            )
        } else {
            try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: localVectorURL)
        }

        let sharedAlreadyCurrent = isSingleSourceMerge
            && vectorStoreExists(for: container.id, in: sharedRoot)
            && vectorChunksAreIdentical(resolvedChunks, sharedChunks)
        if sharedAlreadyCurrent {
            Log.debug(
                "[WorkspaceSyncService] Shared vector store already current for \(container.id); skipping rewrite of \(resolvedChunks.count) chunk(s)",
                category: .vectorDB
            )
        } else {
            try await persistVectorChunksIntoICloud(resolvedChunks, dimension: container.embeddingDim, to: sharedVectorURL)
        }

        for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
            removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot, reason: "chunks merged into the destination library")
            removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot, reason: "chunks merged into the destination library")
        }

        // Only a pass that wrote nothing may license skipping the next one. If either store
        // was rewritten, its size and modification date have just changed, so the signature
        // taken at the top of this call no longer describes what is on disk — recording it
        // would authorise skipping a pass whose input had moved. Recompute instead of reusing
        // it, and drop the entry entirely if that recomputation is not readable.
        if localAlreadyCurrent && sharedAlreadyCurrent {
            let settled = vectorStoreSignature(
                for: container.id,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                sourceContainerIDs: sourceContainerIDs,
                allowedDocumentIds: allowedDocumentIds,
                documentAliases: documentAliases,
                strategy: strategy
            )
            let digest = settled.map(Self.vectorStoreSignatureDigest)
            let all = vectorStoreSyncSignatures.withLock { state -> [UUID: String] in
                state[container.id] = digest
                return state
            }
            Self.saveVectorStoreSignatureDigests(all, defaults: defaults)
        } else {
            let all = vectorStoreSyncSignatures.withLock { state -> [UUID: String] in
                state[container.id] = nil
                return state
            }
            Self.saveVectorStoreSignatureDigests(all, defaults: defaults)
        }
    }

    /// Whether two chunk lists are identical in every field that gets written to disk.
    ///
    /// `DocumentChunk` is `Codable` but not `Equatable`, and adding a synthesised conformance
    /// would compare `metadata` too, which carries timestamps that legitimately differ between
    /// devices without the vectors differing. This compares exactly what `persistVectorChunks`
    /// stores, so a true result means the write would be a no-op.
    ///
    /// Order matters and is not sorted away: the persisted order is the order supplied, so two
    /// lists holding the same chunks in a different sequence are genuinely different files.
    nonisolated private func vectorChunksAreIdentical(_ lhs: [DocumentChunk], _ rhs: [DocumentChunk]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        // Identity and sizes first, across the whole array, before touching any payload.
        //
        // The original version walked one chunk at a time comparing id, documentId, content,
        // parentContent, contextualPrefix and the full 384-float embedding. That is correct and it
        // was catastrophically slow at scale: a benchmark case with a 40-document pool went from
        // 269-414s to over 1800s, a 4-7x regression, because the comparison is O(chunks x 384)
        // element-wise plus full string equality on every chunk body, and it runs on every sync
        // pass. It looked free when written because both sides were already in memory — the cost
        // is CPU, not I/O, and the unoptimised Debug build the benchmark uses makes element-wise
        // Swift loops far more expensive than the Release app the device runs.
        //
        // A device library of 26-1451 chunks never showed it. Forty documents did. That is the
        // "some libraries are going to be massive" case, so the cheap version is the correct one
        // even for production.
        for (a, b) in zip(lhs, rhs) {
            guard a.id == b.id,
                  a.documentId == b.documentId,
                  a.embedding.count == b.embedding.count,
                  a.content.utf8.count == b.content.utf8.count
            else { return false }
        }

        // Only then the expensive payload, and the embeddings by raw memory rather than
        // element-wise. Same semantics for IEEE bit patterns, one memcmp per chunk instead of 384
        // Float comparisons through a generic ==.
        for (a, b) in zip(lhs, rhs) {
            guard a.content == b.content,
                  a.parentContent == b.parentContent,
                  a.contextualPrefix == b.contextualPrefix
            else { return false }

            let same = a.embedding.withUnsafeBytes { ab in
                b.embedding.withUnsafeBytes { bb in
                    ab.count == bb.count && memcmp(ab.baseAddress, bb.baseAddress, ab.count) == 0
                }
            }
            guard same else { return false }
        }
        return true
    }

    nonisolated private func persistVectorChunks(_ chunks: [DocumentChunk], dimension: Int, to url: URL) async throws {
        // Instrumentation only. Opens a database and writes it; see `mergeVectorStoresIfNeeded`.
        Log.debug(
            "[WorkspaceSyncService] persistVectorChunks writing \(chunks.count) chunk(s) to \(url.lastPathComponent)",
            category: .vectorDB
        )
        let database = await MainActor.run {
            BNNSVectorDatabase(dimension: dimension, storageURL: url)
        }
        try await database.clear()
        if !chunks.isEmpty {
            try await database.storeBatch(chunks: chunks)
            try await database.persist()
        }
    }

    /// Writes a vector store that lives in iCloud (5.7): the store is written in a replacement folder
    /// on the same volume, then its files take the place of the ones in iCloud in one coordinated
    /// step (`coordinatedReplaceItems`). An empty `chunks` removes the store's files, as the
    /// `clear()` this replaces did.
    nonisolated func persistVectorChunksIntoICloud(_ chunks: [DocumentChunk], dimension: Int, to url: URL) async throws {
        let staging = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: staging) }
        let stagedURL = staging.appendingPathComponent(url.lastPathComponent)
        try await persistVectorChunks(chunks, dimension: dimension, to: stagedURL)
        // The three files `clear()` removes and a save writes; the legacy single-file store, if one
        // is still there, is left alone, as before.
        try await Self.coordinatedReplaceItems(
            at: BNNSVectorDatabase.binaryFileURLs(from: url).filter { $0 != url },
            with: BNNSVectorDatabase.binaryFileURLs(from: stagedURL).filter { $0 != stagedURL })
    }

    nonisolated private func synchronizeAuxiliaryFile(
        filePrefix: String,
        canonicalContainerID: UUID,
        sourceContainerIDs: Set<UUID>,
        localRoot: URL,
        sharedRoot: URL,
        strategy: SyncResolutionStrategy
    ) async throws {
        let localURL = localRoot.appendingPathComponent("\(filePrefix)\(canonicalContainerID.uuidString).json")
        let sharedURL = sharedRoot.appendingPathComponent("\(filePrefix)\(canonicalContainerID.uuidString).json")

        let localCandidates = sourceContainerIDs.map {
            localRoot.appendingPathComponent("\(filePrefix)\($0.uuidString).json")
        }
        let sharedCandidates = sourceContainerIDs.map {
            sharedRoot.appendingPathComponent("\(filePrefix)\($0.uuidString).json")
        }

        let preferredSource: URL?
        switch strategy {
        case .mergeLibraries:
            preferredSource = (localCandidates + sharedCandidates)
                .filter { fileManager.fileExists(atPath: $0.path) }
                .max(by: { modificationDate(for: $0) < modificationDate(for: $1) })

        case .useICloudWorkspace, .importExistingICloudLibraries:
            preferredSource = sharedCandidates
                .filter { fileManager.fileExists(atPath: $0.path) }
                .max(by: { modificationDate(for: $0) < modificationDate(for: $1) })
        }

        guard let preferredSource else {
            if strategy != .mergeLibraries {
                try? Self.coordinatedRemoveItem(at: sharedURL)
            }

            for sourceContainerID in sourceContainerIDs where sourceContainerID != canonicalContainerID {
                try? Self.coordinatedRemoveItem(at: localRoot.appendingPathComponent("\(filePrefix)\(sourceContainerID.uuidString).json"))
                try? Self.coordinatedRemoveItem(at: sharedRoot.appendingPathComponent("\(filePrefix)\(sourceContainerID.uuidString).json"))
            }
            return
        }

        if preferredSource.standardizedFileURL != localURL.standardizedFileURL {
            try await copyItem(at: preferredSource, to: localURL)
        }
        if preferredSource.standardizedFileURL != sharedURL.standardizedFileURL {
            try await copyItem(at: preferredSource, to: sharedURL)
        }

        for sourceContainerID in sourceContainerIDs where sourceContainerID != canonicalContainerID {
            try? Self.coordinatedRemoveItem(at: localRoot.appendingPathComponent("\(filePrefix)\(sourceContainerID.uuidString).json"))
            try? Self.coordinatedRemoveItem(at: sharedRoot.appendingPathComponent("\(filePrefix)\(sourceContainerID.uuidString).json"))
        }
    }

    nonisolated private func synchronizeEvidenceThreads(
        canonicalContainerID: UUID,
        sourceContainerIDs: Set<UUID>,
        localRoot: URL,
        sharedRoot: URL,
        strategy: SyncResolutionStrategy
    ) async throws {
        let localThreadDir = localRoot.appendingPathComponent("EvidenceThreads/\(canonicalContainerID.uuidString)", isDirectory: true)
        let sharedThreadDir = sharedRoot.appendingPathComponent("EvidenceThreads/\(canonicalContainerID.uuidString)", isDirectory: true)

        let localSourceDirs = sourceContainerIDs.map {
            localRoot.appendingPathComponent("EvidenceThreads/\($0.uuidString)", isDirectory: true)
        }
        let sharedSourceDirs = sourceContainerIDs.map {
            sharedRoot.appendingPathComponent("EvidenceThreads/\($0.uuidString)", isDirectory: true)
        }

        var allThreadFilenames: Set<String> = []
        for dir in (localSourceDirs + sharedSourceDirs) {
            if let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                for fileURL in files where fileURL.pathExtension == "json" {
                    allThreadFilenames.insert(fileURL.lastPathComponent)
                }
            }
        }

        guard !allThreadFilenames.isEmpty else {
            return
        }

        // Conversations deleted on any device (`deleted_threads.json`, written by
        // `EvidenceThreadStore.deleteThread`, 5.7) are removed on both sides and never copied back:
        // without this list a conversation deleted here came back from iCloud on the next pass.
        let deletedThreads = Self.mergeDeletedThreads(localRoot: localRoot, sharedRoot: sharedRoot)

        try? ensureDirectory(localThreadDir)
        try? ensureDirectory(sharedThreadDir)

        for filename in allThreadFilenames {
            let localTargetURL = localThreadDir.appendingPathComponent(filename)
            let sharedTargetURL = sharedThreadDir.appendingPathComponent(filename)

            let localCandidates = sourceContainerIDs.map {
                localRoot.appendingPathComponent("EvidenceThreads/\($0.uuidString)/\(filename)")
            }
            let sharedCandidates = sourceContainerIDs.map {
                sharedRoot.appendingPathComponent("EvidenceThreads/\($0.uuidString)/\(filename)")
            }

            if deletedThreads.contains((filename as NSString).deletingPathExtension) {
                for url in localCandidates + sharedCandidates + [localTargetURL, sharedTargetURL]
                where fileManager.fileExists(atPath: url.path) {
                    try? Self.coordinatedRemoveItem(at: url)
                }
                continue
            }

            let preferredSource: URL?
            switch strategy {
            case .mergeLibraries:
                preferredSource = (localCandidates + sharedCandidates)
                    .filter { fileManager.fileExists(atPath: $0.path) }
                    .max(by: { modificationDate(for: $0) < modificationDate(for: $1) })

            case .useICloudWorkspace, .importExistingICloudLibraries:
                preferredSource = sharedCandidates
                    .filter { fileManager.fileExists(atPath: $0.path) }
                    .max(by: { modificationDate(for: $0) < modificationDate(for: $1) })
            }

            guard let preferredSource else { continue }

            if !fileManager.fileExists(atPath: localTargetURL.path) || modificationDate(for: preferredSource) > modificationDate(for: localTargetURL) {
                try? await copyItem(at: preferredSource, to: localTargetURL)
            }
            if !fileManager.fileExists(atPath: sharedTargetURL.path) || modificationDate(for: preferredSource) > modificationDate(for: sharedTargetURL) {
                try? await copyItem(at: preferredSource, to: sharedTargetURL)
            }
        }

        for sourceContainerID in sourceContainerIDs where sourceContainerID != canonicalContainerID {
            let localOldDir = localRoot.appendingPathComponent("EvidenceThreads/\(sourceContainerID.uuidString)", isDirectory: true)
            let sharedOldDir = sharedRoot.appendingPathComponent("EvidenceThreads/\(sourceContainerID.uuidString)", isDirectory: true)
            try? Self.coordinatedRemoveItem(at: localOldDir)
            try? Self.coordinatedRemoveItem(at: sharedOldDir)
        }
    }

    /// The ids in `deleted_threads.json` on both sides, written back to a side that lacks some (5.7).
    nonisolated static func mergeDeletedThreads(localRoot: URL, sharedRoot: URL) -> Set<String> {
        let localURL = localRoot.appendingPathComponent(EvidenceThreadStore.deletedThreadsFileName)
        let sharedURL = sharedRoot.appendingPathComponent(EvidenceThreadStore.deletedThreadsFileName)
        let local = Set((try? readJSONIfPresent([String].self, from: localURL)) ?? [])
        let shared = Set((try? readJSONIfPresent([String].self, from: sharedURL)) ?? [])
        let merged = local.union(shared)
        let sorted = merged.sorted()
        if merged != local { try? writeJSON(sorted, to: localURL) }
        if merged != shared { try? writeJSON(sorted, to: sharedURL) }
        return merged
    }

    nonisolated func vectorStoreBaseURL(for containerId: UUID, in root: URL) -> URL {
        root.appendingPathComponent("vector_database_\(containerId.uuidString).json")
    }

    nonisolated func vectorStoreArtifactURLs(for containerId: UUID, in root: URL) -> [URL] {
        BNNSVectorDatabase.binaryFileURLs(from: vectorStoreBaseURL(for: containerId, in: root))
    }

    /// True when a vector store exists at `root`, including one that lives in
    /// iCloud but has not been downloaded to this device yet.
    nonisolated func vectorStoreExists(for containerId: UUID, in root: URL) -> Bool {
        vectorStoreArtifactURLs(for: containerId, in: root)
            .contains { ubiquitousItemExists(at: $0) }
    }

    /// True when a vector store exists but its bytes are not on this device, so
    /// reading it would report zero chunks for a library that is not empty.
    nonisolated private func vectorStoreIsUnmaterialized(for containerId: UUID, in root: URL) -> Bool {
        vectorStoreArtifactURLs(for: containerId, in: root)
            .contains { ubiquitousPlaceholderExists(for: $0) }
    }

    /// Deletes a container's vector store from one root.
    ///
    /// `reason` is not optional on purpose. Every non-destructive operation in
    /// this file logs and, until 2026-08-24, this one did not, so a device
    /// capture of a real vector-store loss contained no evidence of the loss.
    /// That silence is what made the same defect read as a phantom across three
    /// sessions. A deletion that leaves no trace is not cheaper than one that
    /// does; it is only harder to find.
    /// A cheap stand-in for "these stores have not changed since we last looked".
    ///
    /// Size and modification date of every artifact in both roots, plus the document set and
    /// the source-container set, because a change in either of those changes what the merge
    /// would produce even when no file has moved. Returns `nil` if any attribute cannot be
    /// read — an iCloud placeholder, a file mid-write — so an unreadable state can never be
    /// mistaken for an unchanged one.
    nonisolated private func vectorStoreSignature(
        for containerId: UUID,
        localRoot: URL,
        sharedRoot: URL,
        sourceContainerIDs: Set<UUID>,
        allowedDocumentIds: Set<UUID>,
        documentAliases: [UUID: UUID],
        strategy: SyncResolutionStrategy
    ) -> String? {
        var parts: [String] = []

        for root in [localRoot, sharedRoot] {
            for sourceContainerID in sourceContainerIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                for url in vectorStoreArtifactURLs(for: sourceContainerID, in: root) {
                    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                        // Absent is a legitimate, stable state and is recorded as such; only an
                        // unreadable one is disqualifying, and that is handled by the throw above.
                        parts.append("\(url.lastPathComponent):absent")
                        continue
                    }
                    let size = (attributes[.size] as? NSNumber)?.int64Value
                    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
                    guard let size, let modified else { return nil }
                    parts.append("\(url.lastPathComponent):\(size):\(modified)")
                }
            }
        }

        parts.append("docs:" + allowedDocumentIds.map(\.uuidString).sorted().joined(separator: ","))
        parts.append("sources:" + sourceContainerIDs.map(\.uuidString).sorted().joined(separator: ","))

        // `documentAliases` and `strategy` are inputs to the merge too. Two passes over
        // byte-identical files with the same document set can still resolve differently if an
        // alias was added or the resolution strategy changed, so leaving them out would license
        // skipping a pass whose result would not have been the same.
        parts.append("aliases:" + documentAliases
            .map { "\($0.key.uuidString)>\($0.value.uuidString)" }
            .sorted()
            .joined(separator: ","))
        parts.append("strategy:\(strategy)")
        return parts.joined(separator: "|")
    }

    nonisolated func removeVectorStoreArtifacts(for containerId: UUID, in root: URL, reason: String) {
        var removed = 0
        for url in vectorStoreArtifactURLs(for: containerId, in: root) {
            guard ubiquitousItemExists(at: url) else { continue }
            do {
                try Self.coordinatedRemoveItem(at: url)
                removed += 1
            } catch {
                Log.error(
                    "[WorkspaceSync] Failed to remove vector artifact \(url.lastPathComponent) for container \(containerId): \(error.localizedDescription)",
                    category: .ingestion
                )
            }
        }
        guard removed > 0 else { return }
        Log.info(
            "[WorkspaceSync] Deleted vector store for container \(containerId) (\(removed) artifact(s), root \(root.lastPathComponent)): \(reason).",
            category: .ingestion
        )
    }

    nonisolated func repairWorkspaceMetadataIfNeeded(
        at root: URL,
        containers: [KnowledgeContainer],
        documents: [Document],
        ingestionQueue: PersistedIngestionQueueStateRecord?
    ) throws -> (containers: [KnowledgeContainer], documents: [Document]) {
        let mergeResult = mergeContainers(shared: containers, local: [])
        let repairedDocuments = deduplicatedDocuments(
            applyingContainerAliases(to: documents, aliases: mergeResult.sourceToCanonical)
        )
        let repairedQueue = applyingContainerAliases(to: ingestionQueue, aliases: mergeResult.sourceToCanonical)

        let didRepairContainers = mergeResult.containers != containers
        let didRepairDocuments = !jsonEncodedValuesMatch(repairedDocuments, documents)
        let didRepairQueue = !jsonEncodedValuesMatch(repairedQueue, ingestionQueue)

        if didRepairContainers {
            try Self.writeJSON(mergeResult.containers, to: root.appendingPathComponent("containers.json"))
        }

        if didRepairDocuments {
            try Self.writeJSON(repairedDocuments, to: root.appendingPathComponent("documents_metadata.json"))
        }

        if didRepairQueue {
            let queueURL = root.appendingPathComponent("ingestion_queue.json")
            if let repairedQueue, repairedQueue.isEmpty == false {
                try Self.writeJSON(repairedQueue, to: queueURL)
            } else {
                try? Self.coordinatedRemoveItem(at: queueURL)
            }
        }

        return (mergeResult.containers, repairedDocuments)
    }

}
