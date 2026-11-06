//
//  WorkspaceSyncService+LibrarySync.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    nonisolated func synchronizeConfiguredLibraries(
        localRoot: URL,
        sharedRoot: URL,
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory,
        strategy: SyncResolutionStrategy
    ) async throws {
        let deletedContainersURL = sharedRoot.appendingPathComponent("deleted_containers.json")
        let deletedContainerIDs = Set((try? Self.readJSONIfPresent([String].self, from: deletedContainersURL))?.compactMap { UUID(uuidString: $0) } ?? [])

        let localDeletedDocsURL = localRoot.appendingPathComponent("deleted_documents.json")
        let sharedDeletedDocsURL = sharedRoot.appendingPathComponent("deleted_documents.json")
        let localDeletedDocIDs = Set((try? Self.readJSONIfPresent([String].self, from: localDeletedDocsURL)) ?? [])
        let sharedDeletedDocIDs = Set((try? Self.readJSONIfPresent([String].self, from: sharedDeletedDocsURL)) ?? [])
        let consolidatedDeletedDocIDs = localDeletedDocIDs.union(sharedDeletedDocIDs)

        if !consolidatedDeletedDocIDs.isEmpty {
            let sortedDeletedDocIDs = Array(consolidatedDeletedDocIDs).sorted()
            try? Self.writeJSON(sortedDeletedDocIDs, to: localDeletedDocsURL)
            try? Self.writeJSON(sortedDeletedDocIDs, to: sharedDeletedDocsURL)
        }

        let allLocalContainers = sortedContainers(localInventory.containers)
        let localContainerById = Dictionary(allLocalContainers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var localOnlyContainers = sortedContainers(allLocalContainers.filter { $0.syncMode == .localOnly })
        let localSyncedContainers = sortedContainers(
            allLocalContainers
                .filter { $0.syncMode == .iCloudShared }
                .filter { !deletedContainerIDs.contains($0.id) }
        )
        let localOnlyContainerIDs = Set(localOnlyContainers.map(\.id))
        let sharedVisibleContainers = sortedContainers(
            sharedInventory.containers
                .map(normalizeSharedContainer)
                .filter { !localOnlyContainerIDs.contains($0.id) }
                .filter { !deletedContainerIDs.contains($0.id) }
        )

        let mergeResult = mergeContainers(
            shared: sharedVisibleContainers,
            local: localSyncedContainers.map(normalizeSharedContainer)
        )
        let canonicalContainerById = Dictionary(mergeResult.containers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sharedCanonicalContainerIDs = Set(sharedVisibleContainers.map { mergeResult.sourceToCanonical[$0.id] ?? $0.id })

        let finalSyncedContainers: [KnowledgeContainer]
        switch strategy {
        case .mergeLibraries:
            finalSyncedContainers = mergeResult.containers

        case .useICloudWorkspace:
            let sharedIDs = sharedCanonicalContainerIDs
            let demotedLocalContainers = localSyncedContainers
                .filter {
                    let canonicalId = mergeResult.sourceToCanonical[$0.id] ?? $0.id
                    return !sharedIDs.contains(canonicalId)
                }
                .map { container -> KnowledgeContainer in
                    var demoted = container
                    demoted.syncMode = .localOnly
                    return demoted
                }
            localOnlyContainers = sortedContainers(localOnlyContainers + demotedLocalContainers)
            finalSyncedContainers = sortedContainers(sharedIDs.compactMap { canonicalContainerById[$0] })

        case .importExistingICloudLibraries:
            finalSyncedContainers = sortedContainers(sharedCanonicalContainerIDs.compactMap { canonicalContainerById[$0] })
        }

        let finalSyncedContainerIDs = Set(finalSyncedContainers.map(\.id))
        let localDefaultContainerId = allLocalContainers.first?.id
        let sharedDefaultContainerId = sharedVisibleContainers.first?.id

        let localSyncedDocuments = localInventory.documents.compactMap { document -> Document? in
            if consolidatedDeletedDocIDs.contains(document.id.uuidString) {
                return nil
            }
            guard let rawContainerId = resolvedContainerID(for: document, defaultContainerId: localDefaultContainerId) else {
                return nil
            }

            guard localContainerById[rawContainerId]?.syncMode == .iCloudShared else {
                return nil
            }

            let canonicalId = mergeResult.sourceToCanonical[rawContainerId] ?? rawContainerId
            guard finalSyncedContainerIDs.contains(canonicalId) else { return nil }
            return applyingContainerAliases(to: document, aliases: mergeResult.sourceToCanonical)
        }

        let localOnlyDocuments = localInventory.documents.compactMap { document -> Document? in
            if consolidatedDeletedDocIDs.contains(document.id.uuidString) {
                return nil
            }
            guard let rawContainerId = resolvedContainerID(for: document, defaultContainerId: localDefaultContainerId) else {
                return document
            }

            let canonicalId = mergeResult.sourceToCanonical[rawContainerId] ?? rawContainerId
            guard !finalSyncedContainerIDs.contains(canonicalId) else { return nil }
            return applyingContainerAliases(to: document, aliases: mergeResult.sourceToCanonical)
        }

        let effectiveSharedDocuments = sharedInventory.documents.compactMap { document -> Document? in
            if consolidatedDeletedDocIDs.contains(document.id.uuidString) {
                return nil
            }
            guard let rawContainerId = resolvedContainerID(for: document, defaultContainerId: sharedDefaultContainerId) else {
                return nil
            }

            let canonicalId = mergeResult.sourceToCanonical[rawContainerId] ?? rawContainerId
            guard finalSyncedContainerIDs.contains(canonicalId) else { return nil }
            return applyingContainerAliases(to: document, aliases: mergeResult.sourceToCanonical)
        }

        let documentSources = effectiveSharedDocuments.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) }
            + (strategy == .mergeLibraries
                ? localSyncedDocuments.map { SourcedDocument(document: $0, sourceRoot: localRoot) }
                : [])

        await ensureSourcedDocumentsAvailableLocally(
            documentSources.filter { $0.sourceRoot.standardizedFileURL == sharedRoot.standardizedFileURL }
        )

        let sharedDocumentMergeResult = try await mergeDocumentsWithAliases(documentSources, into: sharedRoot)
        let finalSharedDocuments = sharedDocumentMergeResult.documents
        let finalLocalSyncedDocuments = try await mergeDocuments(documentSources, into: localRoot)
        let finalLocalContainers = sortedContainers(localOnlyContainers + finalSyncedContainers)
        let finalLocalDocuments = deduplicatedDocuments(localOnlyDocuments + finalLocalSyncedDocuments)

        try enforceLibraryLimit(for: finalLocalContainers)

        // Everything above was computed from `localInventory`, a snapshot taken at
        // the start of this pass. Between that snapshot and this write we merged
        // containers, resolved aliases, and — in
        // `ensureSourcedDocumentsAvailableLocally` — awaited iCloud downloads. An
        // ingestion that finishes inside that window writes its own
        // documents_metadata.json, and this write then lands on top of it with a
        // set computed before that document existed. The document is left fully
        // present on disk (chunks, embeddings, FTS5, Spotlight) with no metadata
        // row pointing at it, so it simply disappears from the app, and because
        // the ingestion completed there is no queue item left to offer a resume.
        //
        // Commit under a single coordination claim that spans the re-read and the
        // write, and fold in anything that landed mid-pass instead of discarding
        // it. Aborting here would also work, but it throws away a completed merge
        // and — because the throw unwinds to `activateLocalWorkspace` — makes sync
        // report itself as off every time a user imports while a pass is running.
        // Merging converges on the first try instead.
        let localDocumentsURL = localRoot.appendingPathComponent("documents_metadata.json")
        let tombstoned = consolidatedDeletedDocIDs

        try Self.coordinatedMergeData(at: localDocumentsURL) { existing in
            var result = finalLocalDocuments

            if let existing {
                let computedIDs = Set(finalLocalDocuments.map(\.id))
                let onDisk = (try? JSONDecoder().decode([Document].self, from: existing)) ?? []
                let arrivedDuringPass = onDisk.filter { document in
                    !computedIDs.contains(document.id) && !tombstoned.contains(document.id.uuidString)
                }

                if !arrivedDuringPass.isEmpty {
                    Log.warning(
                        """
                        [WorkspaceSync] \(arrivedDuringPass.count) document(s) finished importing while \
                        this sync pass was running and were absent from the \(finalLocalDocuments.count) \
                        it computed. Folding them into the write instead of overwriting them. \
                        Kept: \(arrivedDuringPass.map { "\($0.id.uuidString) in \($0.containerId?.uuidString ?? "default")" }.joined(separator: ", ")).
                        """,
                        category: .vectorDB
                    )
                    result = deduplicatedDocuments(result + arrivedDuringPass)
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(result)
        }

        // Libraries get the same treatment as documents, with one extra
        // constraint: `enforceLibraryLimit` throws rather than truncating, and it
        // used to run against the computed set only. Folding a library in after
        // that check could carry a workspace past its tier limit, which is why
        // this write was left alone in the first pass.
        //
        // Resolved by enforcing against the *merged* set inside the accessor. If
        // the fold would exceed the limit we throw without writing, which leaves
        // the newly created library intact on disk for the next pass to adopt
        // through the normal path. Nothing is deleted to satisfy a quota.
        //
        // Alias-aware: a container id absent from the computed set may still be a
        // pre-merge source for one that is present, so folding on id alone would
        // resurrect a duplicate the merge had just collapsed.
        let localContainersURL = localRoot.appendingPathComponent("containers.json")
        let localLimit = EntitlementStore.currentLibraryLimit(defaults: defaults)
        let containerAliases = mergeResult.sourceToCanonical

        try Self.coordinatedMergeData(at: localContainersURL) { existing in
            var result = finalLocalContainers

            if let existing {
                let computedIDs = Set(finalLocalContainers.map(\.id))
                let onDisk = (try? JSONDecoder().decode([KnowledgeContainer].self, from: existing)) ?? []
                let arrivedDuringPass = onDisk.filter { container in
                    let canonical = containerAliases[container.id] ?? container.id
                    return !computedIDs.contains(container.id)
                        && !computedIDs.contains(canonical)
                        && !deletedContainerIDs.contains(container.id)
                }

                if !arrivedDuringPass.isEmpty {
                    guard result.count + arrivedDuringPass.count <= localLimit else {
                        Log.error(
                            "[WorkspaceSync] \(arrivedDuringPass.count) library(s) were created while this sync pass ran, and folding them in would exceed the \(localLimit)-library limit. Leaving containers.json untouched so nothing is lost; the next pass will reconcile them.",
                            category: .vectorDB
                        )
                        throw LibraryQuotaError(
                            limit: localLimit,
                            attemptedCount: result.count + arrivedDuringPass.count,
                            tier: EntitlementStore.currentEffectiveTier(defaults: defaults)
                        )
                    }

                    Log.warning(
                        "[WorkspaceSync] Keeping \(arrivedDuringPass.count) library(s) created while this pass ran, rather than overwriting them: \(arrivedDuringPass.map(\.name).joined(separator: ", ")).",
                        category: .vectorDB
                    )
                    result = sortedContainers(result + arrivedDuringPass)
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(result)
        }

        let sharedContainersURL = sharedRoot.appendingPathComponent("containers.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")

        if finalSyncedContainers.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedContainersURL)
        } else {
            // Cross-device equivalent: another device can publish a library into
            // the shared root while this pass computes. No tier check here — the
            // limit is a per-workspace rule enforced on the local write above, and
            // refusing to record a library that already exists in iCloud would
            // only hide it from this device.
            try Self.coordinatedMergeData(at: sharedContainersURL) { existing in
                var result = finalSyncedContainers

                if let existing {
                    let computedIDs = Set(finalSyncedContainers.map(\.id))
                    let onDisk = (try? JSONDecoder().decode([KnowledgeContainer].self, from: existing)) ?? []
                    let publishedByAnotherDevice = onDisk.filter { container in
                        let canonical = containerAliases[container.id] ?? container.id
                        return !computedIDs.contains(container.id)
                            && !computedIDs.contains(canonical)
                            && !deletedContainerIDs.contains(container.id)
                    }

                    if !publishedByAnotherDevice.isEmpty {
                        Log.warning(
                            "[WorkspaceSync] Keeping \(publishedByAnotherDevice.count) shared library(s) published while this pass ran, rather than overwriting them.",
                            category: .vectorDB
                        )
                        result = sortedContainers(result + publishedByAnotherDevice)
                    }
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(result)
            }
        }

        if finalSharedDocuments.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedDocumentsURL)
        } else {
            // Same race, across devices rather than across tasks. Another device
            // can publish a document into the shared root while this pass is
            // computing, and a plain write would erase it from iCloud for
            // everyone. Fold it in under one write claim instead.
            try Self.coordinatedMergeData(at: sharedDocumentsURL) { existing in
                var result = finalSharedDocuments

                if let existing {
                    let computedIDs = Set(finalSharedDocuments.map(\.id))
                    let onDisk = (try? JSONDecoder().decode([Document].self, from: existing)) ?? []
                    let publishedByAnotherDevice = onDisk.filter {
                        !computedIDs.contains($0.id) && !tombstoned.contains($0.id.uuidString)
                    }

                    if !publishedByAnotherDevice.isEmpty {
                        Log.warning(
                            "[WorkspaceSync] Keeping \(publishedByAnotherDevice.count) shared document(s) published while this pass ran, rather than overwriting them.",
                            category: .vectorDB
                        )
                        result = deduplicatedDocuments(result + publishedByAnotherDevice)
                    }
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return try encoder.encode(result)
            }
        }

        try synchronizeIngestionQueue(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            syncedContainerIDs: finalSyncedContainerIDs,
            containerAliases: mergeResult.sourceToCanonical,
            strategy: strategy
        )

        try await synchronizeContainerArtifacts(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            syncedContainers: finalSyncedContainers,
            syncedDocuments: finalSharedDocuments,
            documentAliases: sharedDocumentMergeResult.sourceToCanonical,
            sourceContainerIDsByCanonicalID: mergeResult.canonicalToSources,
            librariesImportingAtPassStart: localInventory.librariesWithUnfinishedImports,
            strategy: strategy
        )

        try await cleanupSharedWorkspace(
            sharedRoot: sharedRoot,
            syncedContainerIDs: finalSyncedContainerIDs,
            referencedRelativePaths: Set(finalSharedDocuments.compactMap(\.storageRelativePath))
        )

        // Local physical file cleanup:
        // Any file in `localRoot/ImportedDocuments` that is not referenced in finalLocalDocuments (and not in finalLocalQueue) should be deleted.
        let localImportedDocsDir = localRoot.appendingPathComponent("ImportedDocuments", isDirectory: true)
        if fileManager.fileExists(atPath: localImportedDocsDir.path) {
            let localContents = (try? fileManager.contentsOfDirectory(
                at: localImportedDocsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            
            var referencedLocalPaths = Set<String>()
            for doc in finalLocalDocuments {
                if let rel = doc.storageRelativePath {
                    referencedLocalPaths.insert(rel)
                }
            }
            
            let localQueueURL = localRoot.appendingPathComponent("ingestion_queue.json")
            if let localQueue = try? Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: localQueueURL) {
                for item in localQueue.items {
                    if let rel = item.storageRelativePath {
                        referencedLocalPaths.insert(rel)
                    }
                }
            }
            
            for fileURL in localContents {
                if let relativePath = relativePath(from: localRoot, to: fileURL) {
                    if !referencedLocalPaths.contains(relativePath) {
                        // Protect recently created/modified files to prevent race conditions during ingestion
                        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                        if let modDate = attrs?[.modificationDate] as? Date,
                           Date().timeIntervalSince(modDate) < 900 { // 15 minutes
                            Log.info("[WorkspaceSyncService] Skipping deletion of recently modified potential ingest file: \(fileURL.lastPathComponent)")
                            continue
                        }
                        try? Self.coordinatedRemoveItem(at: fileURL)
                        Log.info("[WorkspaceSyncService] Deleted local orphaned document file: \(fileURL.lastPathComponent)")
                    }
                }
            }
        }

        let removedContainerIDs = Set(localInventory.containers.map(\.id)).subtracting(finalLocalContainers.map(\.id))
        for containerId in removedContainerIDs {
            removeVectorStoreArtifacts(for: containerId, in: localRoot, reason: "library was removed from the workspace")
            let prefixes = ["chat_history_", "transcript_", "conversation_memory_"]
            for prefix in prefixes {
                let localAuxURL = localRoot.appendingPathComponent("\(prefix)\(containerId.uuidString).json")
                try? Self.coordinatedRemoveItem(at: localAuxURL)
            }
        }

        // iCloud's numbered copies of files from libraries no list holds, which nothing reads (5.8). Last, so this
        // `await` sits after every read and write above; a library in any list keeps every copy of its files.
        await Self.removeOrphanedConflictCopies(
            in: sharedRoot,
            libraryIds: Set(localInventory.containers.map(\.id))
                .union(sharedInventory.containers.map(\.id))
                .union(finalLocalContainers.map(\.id)))
    }

    nonisolated func unsupportedSyncContainerNames(
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory
    ) -> [String] {
        Array(
            Set(
                (localInventory.containers + sharedInventory.containers)
                    .filter { $0.vectorDBKind != .persistentJSON }
                    .map(\.name)
            )
        )
        .sorted()
    }

    nonisolated func pendingBootstrapPlan(
        localRoot: URL,
        sharedRoot: URL,
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory
    ) -> PendingBootstrapPlan? {
        let localHasContent = !localInventory.containers.isEmpty || !localInventory.documents.isEmpty
        let sharedHasContent = !sharedInventory.containers.isEmpty || !sharedInventory.documents.isEmpty

        guard localHasContent || sharedHasContent else { return nil }

        let localSignature = inventorySignature(for: localInventory)
        let sharedSignature = inventorySignature(for: sharedInventory)

        let mergeResult = mergeContainers(shared: sharedInventory.containers, local: localInventory.containers)
        let localContainerIDs = Set(localInventory.containers.map { mergeResult.sourceToCanonical[$0.id] ?? $0.id })
        let sharedContainerIDs = Set(sharedInventory.containers.map { mergeResult.sourceToCanonical[$0.id] ?? $0.id })
        let localDocumentKeys = Set(
            applyingContainerAliases(to: localInventory.documents, aliases: mergeResult.sourceToCanonical)
                .map(syncDocumentIdentity)
        )
        let sharedDocumentKeys = Set(
            applyingContainerAliases(to: sharedInventory.documents, aliases: mergeResult.sourceToCanonical)
                .map(syncDocumentIdentity)
        )

        guard localContainerIDs != sharedContainerIDs || localDocumentKeys != sharedDocumentKeys else {
            return nil
        }

        if resolvedBootstrapLocalSignature() == localSignature,
           resolvedBootstrapSharedSignature() == sharedSignature {
            return nil
        }

        return PendingBootstrapPlan(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            localInventory: localInventory,
            sharedInventory: sharedInventory
        )
    }

    nonisolated func makePendingBootstrapConflict(from plan: PendingBootstrapPlan) -> PendingBootstrapConflict {
        let mergeResult = mergeContainers(
            shared: plan.sharedInventory.containers,
            local: plan.localInventory.containers
        )
        let localCanonicalIDs = Set(plan.localInventory.containers.map { mergeResult.sourceToCanonical[$0.id] ?? $0.id })
        let sharedCanonicalIDs = Set(plan.sharedInventory.containers.map { mergeResult.sourceToCanonical[$0.id] ?? $0.id })
        let mergedLibraryCount = mergeResult.containers.count
        let mergedDocumentCount = Set(
            deduplicatedDocuments(
                applyingContainerAliases(to: plan.localInventory.documents, aliases: mergeResult.sourceToCanonical)
                    + applyingContainerAliases(to: plan.sharedInventory.documents, aliases: mergeResult.sourceToCanonical)
            )
            .map(syncDocumentIdentity)
        ).count

        let localOnlyContainers = sortedContainers(plan.localInventory.containers)
            .filter {
                let canonicalID = mergeResult.sourceToCanonical[$0.id] ?? $0.id
                return !sharedCanonicalIDs.contains(canonicalID)
            }
        let localOnlyLibraryNames = localOnlyContainers.map(\.name)
        let localOnlyLibraryIDs = localOnlyContainers.map(\.id)

        let sharedOnlyLibraryNames = sortedContainers(plan.sharedInventory.containers)
            .filter {
                let canonicalID = mergeResult.sourceToCanonical[$0.id] ?? $0.id
                return !localCanonicalIDs.contains(canonicalID)
            }
            .map(\.name)

        return PendingBootstrapConflict(
            localLibraryCount: plan.localInventory.containers.count,
            localDocumentCount: plan.localInventory.documents.count,
            sharedLibraryCount: plan.sharedInventory.containers.count,
            sharedDocumentCount: plan.sharedInventory.documents.count,
            mergedLibraryCount: mergedLibraryCount,
            mergedDocumentCount: mergedDocumentCount,
            localOnlyLibraryIDs: localOnlyLibraryIDs,
            localOnlyLibraryNames: localOnlyLibraryNames,
            sharedOnlyLibraryNames: sharedOnlyLibraryNames
        )
    }

    nonisolated private func syncDocumentIdentity(for document: Document) -> String {
        documentDuplicateKey(for: document) ?? "id:\(document.id.uuidString)"
    }

    nonisolated func inventorySignature(for inventory: WorkspaceInventory) -> Int {
        var hasher = Hasher()
        hasher.combine(inventory.containers.count)
        hasher.combine(inventory.documents.count)

        for container in inventory.containers.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(container.id)
            hasher.combine(container.name)
            hasher.combine(container.embeddingProviderId)
            hasher.combine(container.embeddingDim)
            hasher.combine(container.vectorDBKind.rawValue)
        }

        for identity in inventory.documents.map(syncDocumentIdentity).sorted() {
            hasher.combine(identity)
        }

        return hasher.finalize()
    }

    nonisolated func createRecoverySnapshot(at root: URL, label: String) async throws {
        guard fileManager.fileExists(atPath: root.path) else { return }

        let snapshotRoot = OpenIntelligenceRuntimePaths.localCacheDirectory()
            .appendingPathComponent("SyncRecoverySnapshots", isDirectory: true)
        try fileManager.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let snapshotDirectory = snapshotRoot.appendingPathComponent(
            "\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(label)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let name = item.lastPathComponent
            guard Self.criticalMetadataFileNames.contains(name) else {
                continue
            }

            let destination = snapshotDirectory.appendingPathComponent(name, isDirectory: item.hasDirectoryPath)
            try await copyItem(at: item, to: destination)
        }
    }

}
