//
//  WorkspaceSyncService+Bootstrap.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    @discardableResult
    func reconfigureIfNeeded() async -> Bool {
        await reconfigureIfNeeded(bootstrapBehavior: .promptUser)
    }

    @discardableResult
    func reconfigureForExplicitICloudOptIn() async -> Bool {
        await reconfigureIfNeeded(bootstrapBehavior: .autoMergeLibraries)
    }

    @discardableResult
    func reconfigureIfNeeded(bootstrapBehavior: BootstrapBehavior) async -> Bool {
        if isReconfigureInProgress {
            needsReconfigurePass = true
            return false
        }

        Self.isSyncWriteInProgress = true
        isReconfigureInProgress = true
        defer {
            isReconfigureInProgress = false
            Self.isSyncWriteInProgress = false
        }

        var anyWorkspaceChange = false

        repeat {
            needsReconfigurePass = false
            let didChange = await performReconfigureIfNeeded(bootstrapBehavior: bootstrapBehavior)
            anyWorkspaceChange = anyWorkspaceChange || didChange
        } while needsReconfigurePass

        return anyWorkspaceChange
    }

    @discardableResult
    private func performReconfigureIfNeeded(bootstrapBehavior: BootstrapBehavior) async -> Bool {
        let localWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()

        let localInventory: WorkspaceInventory
        do {
            localInventory = try await workspaceInventory(at: localWorkspaceRoot)
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "Could not load local libraries for iCloud sync.")
        }

        // Entitlement Demotion Check: iCloud sync requires at least Pro status.
        let effectiveTier = EntitlementStore.currentEffectiveTier(defaults: self.defaults)
        guard effectiveTier.isAtLeast(.pro) else {
            let hasSyncedLibraries = localInventory.containers.contains(where: { $0.syncMode == .iCloudShared })
            if hasSyncedLibraries || isUsingSharedWorkspace {
                var demotedContainers = localInventory.containers
                for idx in 0..<demotedContainers.count {
                    if demotedContainers[idx].syncMode == .iCloudShared {
                        demotedContainers[idx].syncMode = .localOnly
                    }
                }
                
                // Write demoted containers back to local containers.json
                do {
                    try Self.writeJSON(demotedContainers, to: localWorkspaceRoot.appendingPathComponent("containers.json"))
                } catch {
                    // Fail silently to avoid breaking local usage if writing fails.
                }
                
                defaults.removeObject(forKey: Self.hasBootstrappedSharedWorkspaceDefaultsKey)
                clearPendingBootstrapState()
                unsupportedSyncContainerNames = []
                lastErrorMessage = nil
                
                return activateLocalWorkspace(reason: "iCloud sync requires a Pro subscription.")
            }
            
            clearPendingBootstrapState()
            unsupportedSyncContainerNames = []
            return activateLocalWorkspace(reason: "All libraries are local only.")
        }

        let localSyncedInventory = syncedInventory(from: localInventory)

        guard !localSyncedInventory.containers.isEmpty else {
            lastErrorMessage = nil
            clearPendingBootstrapState()
            unsupportedSyncContainerNames = []
            defaults.removeObject(forKey: Self.hasBootstrappedSharedWorkspaceDefaultsKey)
            return activateLocalWorkspace(reason: "All libraries are local only.")
        }

        recordSyncAttempt()

        guard fileManager.ubiquityIdentityToken != nil else {
            lastErrorMessage = "iCloud Sync is unavailable for the current Apple account."
            return activateLocalWorkspace(reason: "iCloud Sync is unavailable on this device.")
        }

        statusMessage = "Preparing iCloud libraries..."
        lastErrorMessage = nil

        guard let containerURL = await Self.resolveUbiquityContainerURL() else {
            lastErrorMessage = "The iCloud ubiquity container could not be resolved."
            return activateLocalWorkspace(reason: "Unable to reach the iCloud workspace right now.")
        }

        let sharedWorkspaceRoot = sharedWorkspaceRootURL(for: containerURL)

        do {
            try ensureDirectory(sharedWorkspaceRoot)
            await prepareWorkspaceDownloads(root: sharedWorkspaceRoot)
            // Before the folder is read (5.8): see `waitUntilSyncFilesAreFree`.
            await Self.waitUntilSyncFilesAreFree(in: [sharedWorkspaceRoot])

            let sharedInventory = try await workspaceInventory(at: sharedWorkspaceRoot)
            let unsupportedContainers = unsupportedSyncContainerNames(
                localInventory: localSyncedInventory,
                sharedInventory: sharedInventory
            )

            guard unsupportedContainers.isEmpty else {
                unsupportedSyncContainerNames = unsupportedContainers
                clearPendingBootstrapState()
                lastErrorMessage = syncCompatibilityMessage
                return activateLocalWorkspace(reason: "iCloud library sync needs Standard Vector Store libraries.")
            }

            unsupportedSyncContainerNames = []

            if let bootstrapPlan = pendingBootstrapPlan(
                localRoot: localWorkspaceRoot,
                sharedRoot: sharedWorkspaceRoot,
                localInventory: localSyncedInventory,
                sharedInventory: sharedInventory
            ) {
                let effectiveBehavior: BootstrapBehavior
                if bootstrapBehavior == .promptUser && (isUsingSharedWorkspace || defaults.bool(forKey: Self.hasBootstrappedSharedWorkspaceDefaultsKey)) {
                    effectiveBehavior = .autoMergeLibraries
                } else {
                    effectiveBehavior = bootstrapBehavior
                }

                switch effectiveBehavior {
                case .promptUser:
                    pendingBootstrapPlan = bootstrapPlan
                    pendingBootstrapConflict = makePendingBootstrapConflict(from: bootstrapPlan)
                    lastErrorMessage = nil
                    return activateLocalWorkspace(reason: "Choose how to connect this device's iCloud libraries. Local Only libraries stay local.")

                case .autoMergeLibraries:
                    clearPendingBootstrapState()
                    try await resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)
                    try await synchronizeConfiguredLibraries(
                        localRoot: localWorkspaceRoot,
                        sharedRoot: sharedWorkspaceRoot,
                        localInventory: localInventory,
                        sharedInventory: sharedInventory,
                        strategy: .mergeLibraries
                    )
                    recordResolvedBootstrap(for: localSyncedInventory, sharedInventory: sharedInventory)
                    lastErrorMessage = nil
                    return activateSharedWorkspace(root: sharedWorkspaceRoot, reason: "Syncing selected iCloud libraries through iCloud Sync.")
                }
            }

            clearPendingBootstrapState()
            try await resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)
            try await synchronizeConfiguredLibraries(
                localRoot: localWorkspaceRoot,
                sharedRoot: sharedWorkspaceRoot,
                localInventory: localInventory,
                sharedInventory: sharedInventory,
                strategy: .mergeLibraries
            )
            lastErrorMessage = nil
            return activateSharedWorkspace(root: sharedWorkspaceRoot, reason: "Syncing selected iCloud libraries through iCloud Sync.")
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "iCloud library sync failed. Local libraries are unchanged.")
        }
    }

    @discardableResult
    func resolvePendingBootstrap(using choice: BootstrapChoice) async -> Bool {
        guard isSyncEnabled else { return false }
        guard EntitlementStore.currentEffectiveTier(defaults: self.defaults).isAtLeast(.pro) else { return false }
        guard let pendingBootstrapPlan else {
            return await reconfigureIfNeeded()
        }

        Self.isSyncWriteInProgress = true
        defer {
            Self.isSyncWriteInProgress = false
        }

        do {
            try await createRecoverySnapshot(at: pendingBootstrapPlan.localRoot, label: "local")
            try await createRecoverySnapshot(at: pendingBootstrapPlan.sharedRoot, label: "icloud")
            await prepareWorkspaceDownloads(root: pendingBootstrapPlan.sharedRoot)
            // Before the folder is read (5.8): see `waitUntilSyncFilesAreFree`.
            await Self.waitUntilSyncFilesAreFree(in: [pendingBootstrapPlan.sharedRoot])
            try await resolveSharedMetadataConflictsIfNeeded(in: pendingBootstrapPlan.sharedRoot)

            let localInventory = try await workspaceInventory(at: pendingBootstrapPlan.localRoot)
            let sharedInventory = try await workspaceInventory(at: pendingBootstrapPlan.sharedRoot)

            switch choice {
            case .mergeLibraries:
                try await synchronizeConfiguredLibraries(
                    localRoot: pendingBootstrapPlan.localRoot,
                    sharedRoot: pendingBootstrapPlan.sharedRoot,
                    localInventory: localInventory,
                    sharedInventory: sharedInventory,
                    strategy: .mergeLibraries
                )
                lastErrorMessage = nil
                recordResolvedBootstrap(for: pendingBootstrapPlan.localInventory, sharedInventory: pendingBootstrapPlan.sharedInventory)
                clearPendingBootstrapState()
                return activateSharedWorkspace(root: pendingBootstrapPlan.sharedRoot, reason: "Kept both sets of iCloud libraries in iCloud Sync.")

            case .useICloudWorkspace:
                try await synchronizeConfiguredLibraries(
                    localRoot: pendingBootstrapPlan.localRoot,
                    sharedRoot: pendingBootstrapPlan.sharedRoot,
                    localInventory: localInventory,
                    sharedInventory: sharedInventory,
                    strategy: .useICloudWorkspace
                )
                lastErrorMessage = nil
                recordResolvedBootstrap(for: pendingBootstrapPlan.localInventory, sharedInventory: pendingBootstrapPlan.sharedInventory)
                clearPendingBootstrapState()
                return activateSharedWorkspace(root: pendingBootstrapPlan.sharedRoot, reason: "Using the existing set of iCloud libraries from iCloud Sync.")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "iCloud library sync failed. Local libraries are unchanged.")
        }
    }

    @discardableResult
    func connectExistingICloudLibraries() async -> Bool {
        guard EntitlementStore.currentEffectiveTier(defaults: self.defaults).isAtLeast(.pro) else { return false }
        let localWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()

        Self.isSyncWriteInProgress = true
        defer {
            Self.isSyncWriteInProgress = false
        }

        do {
            let localInventory = try await workspaceInventory(at: localWorkspaceRoot)
            recordSyncAttempt()

            guard fileManager.ubiquityIdentityToken != nil else {
                lastErrorMessage = "iCloud Sync is unavailable for the current Apple account."
                return activateLocalWorkspace(reason: "iCloud Sync is unavailable on this device.")
            }

            statusMessage = "Looking for existing iCloud libraries..."
            lastErrorMessage = nil

            guard let containerURL = await Self.resolveUbiquityContainerURL() else {
                lastErrorMessage = "The iCloud ubiquity container could not be resolved."
                return activateLocalWorkspace(reason: "Unable to reach iCloud Sync right now.")
            }

            let sharedWorkspaceRoot = sharedWorkspaceRootURL(for: containerURL)
            try ensureDirectory(sharedWorkspaceRoot)
            await prepareWorkspaceDownloads(root: sharedWorkspaceRoot)
            // Before the folder is read (5.8): see `waitUntilSyncFilesAreFree`.
            await Self.waitUntilSyncFilesAreFree(in: [sharedWorkspaceRoot])
            try await resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)

            let sharedInventory = try await workspaceInventory(at: sharedWorkspaceRoot)
            guard !sharedInventory.containers.isEmpty else {
                lastErrorMessage = "No existing iCloud libraries were found for this Apple account."
                return activateLocalWorkspace(reason: "No existing iCloud libraries were found.")
            }

            let unsupportedContainers = unsupportedSyncContainerNames(
                localInventory: WorkspaceInventory(containers: [], documents: []),
                sharedInventory: sharedInventory
            )

            guard unsupportedContainers.isEmpty else {
                unsupportedSyncContainerNames = unsupportedContainers
                lastErrorMessage = syncCompatibilityMessage
                return activateLocalWorkspace(reason: "Existing iCloud libraries need the Standard Vector Store before they can be connected.")
            }

            unsupportedSyncContainerNames = []
            clearPendingBootstrapState()

            try await synchronizeConfiguredLibraries(
                localRoot: localWorkspaceRoot,
                sharedRoot: sharedWorkspaceRoot,
                localInventory: localInventory,
                sharedInventory: sharedInventory,
                strategy: .importExistingICloudLibraries
            )

            lastErrorMessage = nil
            return activateSharedWorkspace(root: sharedWorkspaceRoot, reason: "Connected existing iCloud libraries to this device.")
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "Could not connect existing iCloud libraries.")
        }
    }

    func deleteDocumentFromICloud(_ document: Document) async throws {
        guard isSyncEnabled else { return }

        Self.isSyncWriteInProgress = true
        defer {
            Self.isSyncWriteInProgress = false
        }

        recordSyncAttempt()

        guard fileManager.ubiquityIdentityToken != nil else {
            throw NSError(
                domain: "WorkspaceSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud Sync is unavailable on this device. The document was not deleted from iCloud."]
            )
        }

        guard let containerURL = await Self.resolveUbiquityContainerURL() else {
            throw NSError(
                domain: "WorkspaceSyncService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not reach the iCloud workspace. The document was not deleted from iCloud."]
            )
        }

        let sharedRoot = sharedWorkspaceRootURL(for: containerURL)

        let shouldResumeObservation = isUsingSharedWorkspace
        if shouldResumeObservation {
            stopObservingSharedWorkspace()
        }

        defer {
            if shouldResumeObservation {
                startObservingSharedWorkspace(at: sharedRoot)
            }
        }

        try ensureDirectory(sharedRoot)
        await prepareWorkspaceDownloads(root: sharedRoot)
        // Before the folder is read (5.8): see `waitUntilSyncFilesAreFree`.
        await Self.waitUntilSyncFilesAreFree(in: [sharedRoot])
        try await resolveSharedMetadataConflictsIfNeeded(in: sharedRoot)

        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")
        var sharedDocuments = try Self.readJSONIfPresent([Document].self, from: sharedDocumentsURL) ?? []
        
        let initialCount = sharedDocuments.count
        sharedDocuments.removeAll { $0.id == document.id }
        
        if sharedDocuments.count < initialCount {
            try Self.writeJSON(sharedDocuments, to: sharedDocumentsURL)
            
            // Also cleanup physical file if it exists in the shared ImportedDocuments folder
            if let relativePath = document.storageRelativePath {
                let sharedFileURL = sharedRoot.appendingPathComponent(relativePath)
                if fileManager.fileExists(atPath: sharedFileURL.path) {
                    try? Self.coordinatedRemoveItem(at: sharedFileURL)
                }
            }
            
            Log.info("[WorkspaceSyncService] Deleted document from iCloud: \(document.filename)")
            recordSuccessfulSync()
        }
    }

    func deleteSharedLibrary(_ container: KnowledgeContainer) async throws {
        guard container.syncMode == .iCloudShared else { return }

        Self.isSyncWriteInProgress = true
        defer {
            Self.isSyncWriteInProgress = false
        }

        recordSyncAttempt()

        guard fileManager.ubiquityIdentityToken != nil else {
            throw NSError(
                domain: "WorkspaceSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud Sync is unavailable on this device. The shared library was not deleted."]
            )
        }

        guard let containerURL = await Self.resolveUbiquityContainerURL() else {
            throw NSError(
                domain: "WorkspaceSyncService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not reach the iCloud workspace. The shared library was not deleted."]
            )
        }

        let sharedRoot = sharedWorkspaceRootURL(for: containerURL)

        let shouldResumeObservation = isUsingSharedWorkspace
        if shouldResumeObservation {
            stopObservingSharedWorkspace()
        }

        defer {
            if shouldResumeObservation {
                startObservingSharedWorkspace(at: sharedRoot)
            }
        }

        try ensureDirectory(sharedRoot)
        await prepareWorkspaceDownloads(root: sharedRoot)
        // Before the folder is read (5.8): see `waitUntilSyncFilesAreFree`.
        await Self.waitUntilSyncFilesAreFree(in: [sharedRoot])
        try await resolveSharedMetadataConflictsIfNeeded(in: sharedRoot)

        let sharedInventory = try await workspaceInventory(at: sharedRoot)
        let targetContainerIDs = matchingSharedContainerIDs(for: container, in: sharedInventory.containers)

        guard !targetContainerIDs.isEmpty else {
            lastErrorMessage = nil
            recordSuccessfulSync()
            return
        }

        let sharedDefaultContainerId = sortedContainers(sharedInventory.containers).first?.id
        let remainingContainers = sortedContainers(sharedInventory.containers.filter { !targetContainerIDs.contains($0.id) })
        let remainingDocuments = sortedDocuments(sharedInventory.documents.filter { document in
            guard let containerId = resolvedContainerID(for: document, defaultContainerId: sharedDefaultContainerId) else {
                return true
            }

            return !targetContainerIDs.contains(containerId)
        })

        let sharedQueueURL = sharedRoot.appendingPathComponent("ingestion_queue.json")
        let sharedQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: sharedQueueURL)
        let remainingQueue = filterIngestionQueueExcludingContainers(
            sharedQueue,
            containerIDs: targetContainerIDs,
            defaultContainerId: sharedDefaultContainerId
        )

        let sharedContainersURL = sharedRoot.appendingPathComponent("containers.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")

        if remainingContainers.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedContainersURL)
        } else {
            try Self.writeJSON(remainingContainers, to: sharedContainersURL)
        }

        if remainingDocuments.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedDocumentsURL)
        } else {
            try Self.writeJSON(remainingDocuments, to: sharedDocumentsURL)
        }

        if let remainingQueue, !remainingQueue.isEmpty {
            try Self.writeJSON(remainingQueue, to: sharedQueueURL)
        } else {
            try? Self.coordinatedRemoveItem(at: sharedQueueURL)
        }

        let deletedContainersURL = sharedRoot.appendingPathComponent("deleted_containers.json")
        var deletedContainerIDs = (try? Self.readJSONIfPresent([String].self, from: deletedContainersURL)) ?? []
        for targetId in targetContainerIDs {
            let idStr = targetId.uuidString
            if !deletedContainerIDs.contains(idStr) {
                deletedContainerIDs.append(idStr)
            }
        }
        try Self.writeJSON(deletedContainerIDs, to: deletedContainersURL)

        try await cleanupSharedWorkspace(
            sharedRoot: sharedRoot,
            syncedContainerIDs: Set(remainingContainers.map(\.id)),
            referencedRelativePaths: Set(remainingDocuments.compactMap(\.storageRelativePath))
        )

        clearPendingBootstrapState()
        lastErrorMessage = nil
        statusMessage = remainingContainers.isEmpty
            ? "All iCloud libraries were removed from iCloud Sync."
            : "Removed \(container.name) from iCloud Sync."
        recordSuccessfulSync()
    }

    nonisolated static func currentDeviceID(defaults: UserDefaults = .standard) -> String {
        ensureDeviceIdentifier(in: defaults)
        return defaults.string(forKey: deviceIdentifierDefaultsKey) ?? UUID().uuidString
    }

    nonisolated static func ensureItemAvailableLocally(at url: URL, timeout: TimeInterval = 20) async throws {
        let fileManager = FileManager.default
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        let hasPlaceholder = fileManager.fileExists(atPath: placeholder.path)

        // An evicted item is not reported as ubiquitous at its own path, because
        // nothing is there — only the placeholder beside it. Treat either signal
        // as "this item exists in iCloud and may need downloading".
        guard hasPlaceholder || fileManager.isUbiquitousItem(at: url) else { return }

        try? fileManager.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // `resourceValues` throws while the item is still a placeholder, which
            // is the normal state for most of this loop. Keep polling instead of
            // surfacing that as the failure.
            if let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey
            ]), values.ubiquitousItemDownloadingStatus == .current {
                return
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw CocoaError(.fileReadUnknown)
    }

    @discardableResult
    func activateLocalWorkspace(reason: String) -> Bool {
        let previousRoot = activeWorkspaceRoot
        let wasUsingSharedWorkspace = isUsingSharedWorkspace

        stopObservingSharedWorkspace()
        AppSupportPaths.configureBaseDir(nil)
        AppSupportPaths.configureLocalCacheDir(nil)
        activeWorkspaceRoot = nil
        isUsingSharedWorkspace = false
        statusMessage = reason

        return previousRoot != activeWorkspaceRoot || wasUsingSharedWorkspace
    }

    @discardableResult
    private func activateSharedWorkspace(root: URL, reason: String) -> Bool {
        let didChange = activeWorkspaceRoot != root || !isUsingSharedWorkspace

        AppSupportPaths.configureBaseDir(nil)
        AppSupportPaths.configureLocalCacheDir(nil)
        activeWorkspaceRoot = root
        isUsingSharedWorkspace = true
        statusMessage = reason

        startObservingSharedWorkspace(at: root)
        recordSuccessfulSync()
        defaults.set(true, forKey: Self.hasBootstrappedSharedWorkspaceDefaultsKey)
        return didChange
    }

    private func recordSyncAttempt() {
        let now = Date()
        lastSyncAttemptAt = now
        defaults.set(now, forKey: Self.lastSyncAttemptDefaultsKey)
    }

    func recordSuccessfulSync() {
        let now = Date()
        lastSuccessfulSyncAt = now
        defaults.set(now, forKey: Self.lastSuccessfulSyncDefaultsKey)
    }

    private func sharedWorkspaceRootURL(for containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.workspaceFolderName, isDirectory: true)
    }

    private func clearPendingBootstrapState() {
        pendingBootstrapPlan = nil
        pendingBootstrapConflict = nil
    }

    private func recordResolvedBootstrap(for localInventory: WorkspaceInventory, sharedInventory: WorkspaceInventory) {
        defaults.set(inventorySignature(for: localInventory), forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey)
        defaults.set(inventorySignature(for: sharedInventory), forKey: Self.lastResolvedBootstrapSharedSignatureDefaultsKey)
    }

    nonisolated func resolvedBootstrapLocalSignature() -> Int? {
        defaults.object(forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey) as? Int
    }

    nonisolated func resolvedBootstrapSharedSignature() -> Int? {
        defaults.object(forKey: Self.lastResolvedBootstrapSharedSignatureDefaultsKey) as? Int
    }

    nonisolated private func workspaceInventory(at root: URL) async throws -> WorkspaceInventory {
        try await Task.detached {
            try self.readWorkspaceInventorySync(at: root)
        }.value
    }

    nonisolated private func readWorkspaceInventorySync(at root: URL) throws -> WorkspaceInventory {
        guard fileManager.fileExists(atPath: root.path) else {
            return WorkspaceInventory(containers: [], documents: [])
        }

        // The import queue is read before the documents on purpose; see
        // `WorkspaceInventory.librariesWithUnfinishedImports`.
        let ingestionQueue = try Self.readJSONIfPresent(
            PersistedIngestionQueueStateRecord.self,
            from: root.appendingPathComponent("ingestion_queue.json")
        )

        let containers = try Self.readJSONIfPresent(
            [KnowledgeContainer].self,
            from: root.appendingPathComponent("containers.json")
        ) ?? []

        let documents = try Self.readJSONIfPresent(
            [Document].self,
            from: root.appendingPathComponent("documents_metadata.json")
        ) ?? []

        let repairResult = try repairWorkspaceMetadataIfNeeded(
            at: root,
            containers: containers,
            documents: documents,
            ingestionQueue: ingestionQueue
        )

        return WorkspaceInventory(
            containers: repairResult.containers,
            documents: repairResult.documents,
            librariesWithUnfinishedImports: Self.librariesWithUnfinishedImports(
                in: ingestionQueue,
                deviceID: Self.currentDeviceID(defaults: defaults),
                defaultContainerId: repairResult.containers.first?.id
            )
        )
    }

    func configuredSyncedContainerIDs() -> Set<UUID> {
        let localRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        guard let containers = try? readWorkspaceInventorySync(at: localRoot).containers else {
            return []
        }

        return Set(containers.filter { $0.syncMode == .iCloudShared }.map(\.id))
    }

    private func syncedInventory(from inventory: WorkspaceInventory) -> WorkspaceInventory {
        let syncedContainers = sortedContainers(inventory.containers.filter { $0.syncMode == .iCloudShared })
        let syncedContainerIDs = Set(syncedContainers.map(\.id))
        let defaultContainerId = sortedContainers(inventory.containers).first?.id
        let syncedDocuments = inventory.documents.filter { document in
            guard let containerId = resolvedContainerID(for: document, defaultContainerId: defaultContainerId) else {
                return false
            }
            return syncedContainerIDs.contains(containerId)
        }

        return WorkspaceInventory(containers: syncedContainers, documents: syncedDocuments)
    }

    nonisolated func sortedContainers(_ containers: [KnowledgeContainer]) -> [KnowledgeContainer] {
        containers.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated func sortedDocuments(_ documents: [Document]) -> [Document] {
        documents.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt < rhs.addedAt
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
    }

    nonisolated func resolvedContainerID(for document: Document, defaultContainerId: UUID?) -> UUID? {
        document.containerId ?? defaultContainerId
    }

    nonisolated func normalizeSharedContainer(_ container: KnowledgeContainer) -> KnowledgeContainer {
        var normalized = container
        normalized.syncMode = .iCloudShared
        return normalized
    }

}
