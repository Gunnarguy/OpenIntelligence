import Combine
import Foundation

@MainActor
final class WorkspaceSyncService: ObservableObject {
    nonisolated static let syncEnabledDefaultsKey = "enableSharedWorkspaceSync"
    nonisolated static let deviceIdentifierDefaultsKey = "openIntelligence.workspaceSync.deviceID"
    nonisolated static let lastSyncAttemptDefaultsKey = "openIntelligence.workspaceSync.lastAttemptAt"
    nonisolated static let lastSuccessfulSyncDefaultsKey = "openIntelligence.workspaceSync.lastSuccessfulSyncAt"
    nonisolated static let lastResolvedBootstrapLocalSignatureDefaultsKey = "openIntelligence.workspaceSync.lastResolvedBootstrapLocalSignature"

    private static let workspaceFolderName = "OpenIntelligenceWorkspace"
    private static let importedDocumentsFolderName = "ImportedDocuments"
    private static let criticalMetadataFileNames: Set<String> = [
        "containers.json",
        "documents_metadata.json",
        "ingestion_queue.json"
    ]
    private static let localOnlyEntryNames: Set<String> = [
        "FTS5",
        "LocalCache",
        "continued_ingestion_status.json",
        "continued_query_state.json",
        "continued_query_status.json"
    ]

    enum BootstrapChoice: Sendable {
        case mergeLibraries
        case useICloudWorkspace
    }

    private enum SyncResolutionStrategy: Sendable {
        case mergeLibraries
        case useICloudWorkspace
        case importExistingICloudLibraries
    }

    struct PendingBootstrapConflict: Sendable {
        let localLibraryCount: Int
        let localDocumentCount: Int
        let sharedLibraryCount: Int
        let sharedDocumentCount: Int
        let mergedLibraryCount: Int
        let mergedDocumentCount: Int
    }

    private struct WorkspaceInventory {
        let containers: [KnowledgeContainer]
        let documents: [Document]
    }

    private struct PendingBootstrapPlan {
        let localRoot: URL
        let sharedRoot: URL
        let localInventory: WorkspaceInventory
        let sharedInventory: WorkspaceInventory
    }

    private struct SourcedDocument {
        let document: Document
        let sourceRoot: URL
    }

    private struct PersistedIngestionContextRecord: Codable, Sendable {
        let id: UUID
        let context: IngestionContext
    }

    private struct PersistedIngestionQueueStateRecord: Codable, Sendable {
        let items: [IngestionItem]
        let contexts: [PersistedIngestionContextRecord]
        let updatedAt: Date
    }

    @Published private(set) var isUsingSharedWorkspace = false
    @Published private(set) var statusMessage = "All libraries are local only."
    @Published private(set) var activeWorkspaceRoot: URL?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSyncAttemptAt: Date?
    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published private(set) var observedWorkspaceChangeCount: Int = 0
    @Published private(set) var pendingBootstrapConflict: PendingBootstrapConflict?
    @Published private(set) var unsupportedSyncContainerNames: [String] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var ubiquityIdentityObserver: NSObjectProtocol?
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryObservers: [NSObjectProtocol] = []
    private var monitoredWorkspaceRoot: URL?
    private var lastObservedWorkspaceSignature: Int?
    private var pendingBootstrapPlan: PendingBootstrapPlan?

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.lastSyncAttemptAt = defaults.object(forKey: Self.lastSyncAttemptDefaultsKey) as? Date
        self.lastSuccessfulSyncAt = defaults.object(forKey: Self.lastSuccessfulSyncDefaultsKey) as? Date
        Self.ensureDeviceIdentifier(in: defaults)
        activateLocalWorkspace(reason: "All libraries are local only.")

        ubiquityIdentityObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = await self?.reconfigureIfNeeded()
            }
        }
    }

    deinit {
        if let query = metadataQuery {
            query.stop()
        }

        let center = NotificationCenter.default
        for observer in metadataQueryObservers {
            center.removeObserver(observer)
        }

        if let ubiquityIdentityObserver {
            center.removeObserver(ubiquityIdentityObserver)
        }
    }

    var isSyncEnabled: Bool {
        configuredSyncedContainerIDs().isEmpty == false
    }

    var workspaceRootDescription: String? {
        activeWorkspaceRoot?.path
    }

    var requiresBootstrapDecision: Bool {
        pendingBootstrapConflict != nil
    }

    var syncCompatibilityMessage: String? {
        guard !unsupportedSyncContainerNames.isEmpty else { return nil }

        let containerList = unsupportedSyncContainerNames.joined(separator: ", ")
        return "iCloud library sync currently supports Standard Vector Store libraries only. Update these libraries before syncing: \(containerList)."
    }

    @discardableResult
    func reconfigureIfNeeded() async -> Bool {
        let localWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()

        let localInventory: WorkspaceInventory
        do {
            localInventory = try workspaceInventory(at: localWorkspaceRoot)
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "Could not load local libraries for iCloud sync.")
        }

        let localSyncedInventory = syncedInventory(from: localInventory)

        guard !localSyncedInventory.containers.isEmpty else {
            lastErrorMessage = nil
            clearPendingBootstrapState()
            unsupportedSyncContainerNames = []
            return activateLocalWorkspace(reason: "All libraries are local only.")
        }

        recordSyncAttempt()

        guard fileManager.ubiquityIdentityToken != nil else {
            lastErrorMessage = "iCloud Drive is unavailable for the current Apple account."
            return activateLocalWorkspace(reason: "iCloud Drive is unavailable on this device.")
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

            let sharedInventory = try workspaceInventory(at: sharedWorkspaceRoot)
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
                pendingBootstrapPlan = bootstrapPlan
                pendingBootstrapConflict = makePendingBootstrapConflict(from: bootstrapPlan)
                lastErrorMessage = nil
                return activateLocalWorkspace(reason: "Choose how to connect this device's iCloud libraries. Local Only libraries stay local.")
            }

            clearPendingBootstrapState()
            try resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)
            try await synchronizeConfiguredLibraries(
                localRoot: localWorkspaceRoot,
                sharedRoot: sharedWorkspaceRoot,
                localInventory: localInventory,
                sharedInventory: sharedInventory,
                strategy: .mergeLibraries
            )
            lastErrorMessage = nil
            return activateSharedWorkspace(root: sharedWorkspaceRoot, reason: "Syncing selected iCloud libraries through iCloud Drive.")
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "iCloud library sync failed. Local libraries are unchanged.")
        }
    }

    @discardableResult
    func resolvePendingBootstrap(using choice: BootstrapChoice) async -> Bool {
        guard isSyncEnabled else { return false }
        guard let pendingBootstrapPlan else {
            return await reconfigureIfNeeded()
        }

        do {
            try createRecoverySnapshot(at: pendingBootstrapPlan.localRoot, label: "local")
            try createRecoverySnapshot(at: pendingBootstrapPlan.sharedRoot, label: "icloud")
            await prepareWorkspaceDownloads(root: pendingBootstrapPlan.sharedRoot)
            try resolveSharedMetadataConflictsIfNeeded(in: pendingBootstrapPlan.sharedRoot)

            let localInventory = try workspaceInventory(at: pendingBootstrapPlan.localRoot)
            let sharedInventory = try workspaceInventory(at: pendingBootstrapPlan.sharedRoot)

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
                recordResolvedBootstrap(for: pendingBootstrapPlan.localInventory)
                clearPendingBootstrapState()
                return activateSharedWorkspace(root: pendingBootstrapPlan.sharedRoot, reason: "Kept both sets of iCloud libraries in iCloud Drive.")

            case .useICloudWorkspace:
                try await synchronizeConfiguredLibraries(
                    localRoot: pendingBootstrapPlan.localRoot,
                    sharedRoot: pendingBootstrapPlan.sharedRoot,
                    localInventory: localInventory,
                    sharedInventory: sharedInventory,
                    strategy: .useICloudWorkspace
                )
                lastErrorMessage = nil
                recordResolvedBootstrap(for: pendingBootstrapPlan.localInventory)
                clearPendingBootstrapState()
                return activateSharedWorkspace(root: pendingBootstrapPlan.sharedRoot, reason: "Using the existing set of iCloud libraries from iCloud Drive.")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "iCloud library sync failed. Local libraries are unchanged.")
        }
    }

    @discardableResult
    func connectExistingICloudLibraries() async -> Bool {
        let localWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()

        do {
            let localInventory = try workspaceInventory(at: localWorkspaceRoot)
            recordSyncAttempt()

            guard fileManager.ubiquityIdentityToken != nil else {
                lastErrorMessage = "iCloud Drive is unavailable for the current Apple account."
                return activateLocalWorkspace(reason: "iCloud Drive is unavailable on this device.")
            }

            statusMessage = "Looking for existing iCloud libraries..."
            lastErrorMessage = nil

            guard let containerURL = await Self.resolveUbiquityContainerURL() else {
                lastErrorMessage = "The iCloud ubiquity container could not be resolved."
                return activateLocalWorkspace(reason: "Unable to reach iCloud Drive right now.")
            }

            let sharedWorkspaceRoot = sharedWorkspaceRootURL(for: containerURL)
            try ensureDirectory(sharedWorkspaceRoot)
            await prepareWorkspaceDownloads(root: sharedWorkspaceRoot)
            try resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)

            let sharedInventory = try workspaceInventory(at: sharedWorkspaceRoot)
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

    nonisolated static func currentDeviceID(defaults: UserDefaults = .standard) -> String {
        ensureDeviceIdentifier(in: defaults)
        return defaults.string(forKey: deviceIdentifierDefaultsKey) ?? UUID().uuidString
    }

    nonisolated static func ensureItemAvailableLocally(at url: URL, timeout: TimeInterval = 20) async throws {
        let fileManager = FileManager.default
        guard fileManager.isUbiquitousItem(at: url) else { return }

        try? fileManager.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let values = try url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey
            ])

            if values.ubiquitousItemDownloadingStatus == .current {
                return
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw CocoaError(.fileReadUnknown)
    }

    @discardableResult
    private func activateLocalWorkspace(reason: String) -> Bool {
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
        return didChange
    }

    private func recordSyncAttempt() {
        let now = Date()
        lastSyncAttemptAt = now
        defaults.set(now, forKey: Self.lastSyncAttemptDefaultsKey)
    }

    private func recordSuccessfulSync() {
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

    private func recordResolvedBootstrap(for localInventory: WorkspaceInventory) {
        defaults.set(inventorySignature(for: localInventory), forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey)
    }

    private func resolvedBootstrapLocalSignature() -> Int? {
        defaults.object(forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey) as? Int
    }

    private func workspaceInventory(at root: URL) throws -> WorkspaceInventory {
        guard fileManager.fileExists(atPath: root.path) else {
            return WorkspaceInventory(containers: [], documents: [])
        }

        let containers = try Self.readJSONIfPresent(
            [KnowledgeContainer].self,
            from: root.appendingPathComponent("containers.json")
        ) ?? []

        let documents = try Self.readJSONIfPresent(
            [Document].self,
            from: root.appendingPathComponent("documents_metadata.json")
        ) ?? []

        return WorkspaceInventory(containers: containers, documents: documents)
    }

    private func configuredSyncedContainerIDs() -> Set<UUID> {
        let localRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        guard let containers = try? workspaceInventory(at: localRoot).containers else {
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

    private func sortedContainers(_ containers: [KnowledgeContainer]) -> [KnowledgeContainer] {
        containers.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func sortedDocuments(_ documents: [Document]) -> [Document] {
        documents.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt < rhs.addedAt
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
    }

    private func resolvedContainerID(for document: Document, defaultContainerId: UUID?) -> UUID? {
        document.containerId ?? defaultContainerId
    }

    private func normalizeSharedContainer(_ container: KnowledgeContainer) -> KnowledgeContainer {
        var normalized = container
        normalized.syncMode = .iCloudShared
        return normalized
    }

    private func synchronizeConfiguredLibraries(
        localRoot: URL,
        sharedRoot: URL,
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory,
        strategy: SyncResolutionStrategy
    ) async throws {
        let allLocalContainers = sortedContainers(localInventory.containers)
        let localContainerById = Dictionary(uniqueKeysWithValues: allLocalContainers.map { ($0.id, $0) })
        var localOnlyContainers = sortedContainers(allLocalContainers.filter { $0.syncMode == .localOnly })
        let localSyncedContainers = sortedContainers(allLocalContainers.filter { $0.syncMode == .iCloudShared })
        let localOnlyContainerIDs = Set(localOnlyContainers.map(\.id))
        let sharedVisibleContainers = sortedContainers(
            sharedInventory.containers
                .map(normalizeSharedContainer)
                .filter { !localOnlyContainerIDs.contains($0.id) }
        )

        let finalSyncedContainers: [KnowledgeContainer]
        switch strategy {
        case .mergeLibraries:
            finalSyncedContainers = mergeContainers(
                shared: sharedVisibleContainers,
                local: localSyncedContainers.map(normalizeSharedContainer)
            )

        case .useICloudWorkspace:
            let sharedIDs = Set(sharedVisibleContainers.map(\.id))
            let demotedLocalContainers = localSyncedContainers
                .filter { !sharedIDs.contains($0.id) }
                .map { container -> KnowledgeContainer in
                    var demoted = container
                    demoted.syncMode = .localOnly
                    return demoted
                }
            localOnlyContainers = sortedContainers(localOnlyContainers + demotedLocalContainers)
            finalSyncedContainers = sharedVisibleContainers

        case .importExistingICloudLibraries:
            finalSyncedContainers = sharedVisibleContainers
        }

        let finalSyncedContainerIDs = Set(finalSyncedContainers.map(\.id))
        let localDefaultContainerId = allLocalContainers.first?.id
        let sharedDefaultContainerId = sharedVisibleContainers.first?.id

        let localSyncedDocuments = localInventory.documents.filter { document in
            guard let containerId = resolvedContainerID(for: document, defaultContainerId: localDefaultContainerId) else {
                return false
            }
            guard finalSyncedContainerIDs.contains(containerId) else { return false }
            return localContainerById[containerId]?.syncMode == .iCloudShared
        }

        let localOnlyDocuments = localInventory.documents.filter { document in
            guard let containerId = resolvedContainerID(for: document, defaultContainerId: localDefaultContainerId) else {
                return true
            }
            return !finalSyncedContainerIDs.contains(containerId)
        }

        let effectiveSharedDocuments = sharedInventory.documents.filter { document in
            guard let containerId = resolvedContainerID(for: document, defaultContainerId: sharedDefaultContainerId) else {
                return false
            }
            return finalSyncedContainerIDs.contains(containerId) && localContainerById[containerId]?.syncMode != .localOnly
        }

        let documentSources = effectiveSharedDocuments.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) }
            + (strategy == .mergeLibraries
                ? localSyncedDocuments.map { SourcedDocument(document: $0, sourceRoot: localRoot) }
                : [])

        let finalSharedDocuments = try mergeDocuments(documentSources, into: sharedRoot)
        let finalLocalSyncedDocuments = try mergeDocuments(documentSources, into: localRoot)
        let finalLocalContainers = sortedContainers(localOnlyContainers + finalSyncedContainers)
        let finalLocalDocuments = sortedDocuments(localOnlyDocuments + finalLocalSyncedDocuments)

        try Self.writeJSON(finalLocalContainers, to: localRoot.appendingPathComponent("containers.json"))
        try Self.writeJSON(finalLocalDocuments, to: localRoot.appendingPathComponent("documents_metadata.json"))

        let sharedContainersURL = sharedRoot.appendingPathComponent("containers.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")

        if finalSyncedContainers.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedContainersURL)
        } else {
            try Self.writeJSON(finalSyncedContainers, to: sharedContainersURL)
        }

        if finalSharedDocuments.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedDocumentsURL)
        } else {
            try Self.writeJSON(finalSharedDocuments, to: sharedDocumentsURL)
        }

        try synchronizeIngestionQueue(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            syncedContainerIDs: finalSyncedContainerIDs,
            strategy: strategy
        )

        try await synchronizeContainerArtifacts(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            syncedContainers: finalSyncedContainers,
            syncedDocuments: finalSharedDocuments,
            strategy: strategy
        )

        try cleanupSharedWorkspace(
            sharedRoot: sharedRoot,
            syncedContainerIDs: finalSyncedContainerIDs,
            referencedRelativePaths: Set(finalSharedDocuments.compactMap(\.storageRelativePath))
        )
    }

    private func unsupportedSyncContainerNames(
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

    private func pendingBootstrapPlan(
        localRoot: URL,
        sharedRoot: URL,
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory
    ) -> PendingBootstrapPlan? {
        let localHasContent = !localInventory.containers.isEmpty || !localInventory.documents.isEmpty
        let sharedHasContent = !sharedInventory.containers.isEmpty || !sharedInventory.documents.isEmpty

        guard localHasContent && sharedHasContent else { return nil }

        let localSignature = inventorySignature(for: localInventory)
        if resolvedBootstrapLocalSignature() == localSignature {
            return nil
        }

        let localContainerIDs = Set(localInventory.containers.map(\.id))
        let sharedContainerIDs = Set(sharedInventory.containers.map(\.id))
        let localDocumentKeys = Set(localInventory.documents.map(syncDocumentIdentity))
        let sharedDocumentKeys = Set(sharedInventory.documents.map(syncDocumentIdentity))

        guard localContainerIDs != sharedContainerIDs || localDocumentKeys != sharedDocumentKeys else {
            return nil
        }

        return PendingBootstrapPlan(
            localRoot: localRoot,
            sharedRoot: sharedRoot,
            localInventory: localInventory,
            sharedInventory: sharedInventory
        )
    }

    private func makePendingBootstrapConflict(from plan: PendingBootstrapPlan) -> PendingBootstrapConflict {
        let mergedLibraryCount = Set(
            plan.localInventory.containers.map(\.id) + plan.sharedInventory.containers.map(\.id)
        ).count
        let mergedDocumentCount = Set(
            plan.localInventory.documents.map(syncDocumentIdentity)
                + plan.sharedInventory.documents.map(syncDocumentIdentity)
        ).count

        return PendingBootstrapConflict(
            localLibraryCount: plan.localInventory.containers.count,
            localDocumentCount: plan.localInventory.documents.count,
            sharedLibraryCount: plan.sharedInventory.containers.count,
            sharedDocumentCount: plan.sharedInventory.documents.count,
            mergedLibraryCount: mergedLibraryCount,
            mergedDocumentCount: mergedDocumentCount
        )
    }

    private func syncDocumentIdentity(for document: Document) -> String {
        documentDuplicateKey(for: document) ?? "id:\(document.id.uuidString)"
    }

    private func inventorySignature(for inventory: WorkspaceInventory) -> Int {
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

    private func createRecoverySnapshot(at root: URL, label: String) throws {
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
            try copyItem(at: item, to: destination)
        }
    }

    private func migrateCanonicalWorkspaceIfNeeded(from localRoot: URL, to sharedRoot: URL) async throws {
        guard fileManager.fileExists(atPath: localRoot.path) else { return }

        let mergedContainers = try mergeContainersIfNeeded(from: localRoot, to: sharedRoot)
        let mergedDocuments = try mergeDocumentMetadataIfNeeded(from: localRoot, to: sharedRoot)
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

            try copyItem(at: entry, to: destination)
        }

        try await mergeVectorStoresIfNeeded(
            from: localRoot,
            to: sharedRoot,
            containers: mergedContainers,
            documents: mergedDocuments
        )
    }

    private func mergeContainersIfNeeded(from localRoot: URL, to sharedRoot: URL) throws -> [KnowledgeContainer] {
        let localURL = localRoot.appendingPathComponent("containers.json")
        let sharedURL = sharedRoot.appendingPathComponent("containers.json")
        let localContainers = try Self.readJSONIfPresent([KnowledgeContainer].self, from: localURL) ?? []
        let sharedContainers = try Self.readJSONIfPresent([KnowledgeContainer].self, from: sharedURL) ?? []

        guard !localContainers.isEmpty || !sharedContainers.isEmpty else { return [] }

        let mergedContainers = mergeContainers(shared: sharedContainers, local: localContainers)
        try Self.writeJSON(mergedContainers, to: sharedURL)
        return mergedContainers
    }

    private func mergeDocumentMetadataIfNeeded(from localRoot: URL, to sharedRoot: URL) throws -> [Document] {
        let localDocumentsURL = localRoot.appendingPathComponent("documents_metadata.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")
        let localDocuments = try Self.readJSONIfPresent([Document].self, from: localDocumentsURL) ?? []
        let sharedDocuments = try Self.readJSONIfPresent([Document].self, from: sharedDocumentsURL) ?? []

        guard !localDocuments.isEmpty || !sharedDocuments.isEmpty else { return [] }

        let mergedDocuments = try mergeDocuments(
            sharedDocuments.map { SourcedDocument(document: $0, sourceRoot: sharedRoot) }
                + localDocuments.map { SourcedDocument(document: $0, sourceRoot: localRoot) },
            into: sharedRoot
        )

        try Self.writeJSON(mergedDocuments, to: sharedDocumentsURL)
        return mergedDocuments
    }

    private func mergeIngestionQueueIfNeeded(from localRoot: URL, to sharedRoot: URL) throws {
        let localQueueURL = localRoot.appendingPathComponent("ingestion_queue.json")
        let sharedQueueURL = sharedRoot.appendingPathComponent("ingestion_queue.json")
        let localQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: localQueueURL)
        let sharedQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: sharedQueueURL)

        guard localQueue != nil || sharedQueue != nil else { return }

        let mergedQueue = mergeIngestionQueue(shared: sharedQueue, local: localQueue)
        guard !mergedQueue.items.isEmpty else {
            try? Self.coordinatedRemoveItem(at: sharedQueueURL)
            return
        }

        try Self.writeJSON(mergedQueue, to: sharedQueueURL)
    }

    private func mergeContainers(shared: [KnowledgeContainer], local: [KnowledgeContainer]) -> [KnowledgeContainer] {
        var orderedIds: [UUID] = []
        var byId: [UUID: KnowledgeContainer] = [:]

        for container in shared {
            if byId[container.id] == nil {
                orderedIds.append(container.id)
            }
            byId[container.id] = container
        }

        for container in local {
            if let existing = byId[container.id] {
                byId[container.id] = mergeContainer(primary: existing, secondary: container)
            } else {
                orderedIds.append(container.id)
                byId[container.id] = container
            }
        }

        return orderedIds.compactMap { byId[$0] }.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func mergeContainer(primary: KnowledgeContainer, secondary: KnowledgeContainer) -> KnowledgeContainer {
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

    private func mergeDocuments(_ sourcedDocuments: [SourcedDocument], into sharedRoot: URL) throws -> [Document] {
        var orderedIds: [UUID] = []
        var byId: [UUID: Document] = [:]
        var duplicateKeyToId: [String: UUID] = [:]

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

            let materialized = try materializeDocument(
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
            } else {
                orderedIds.append(materialized.id)
                byId[materialized.id] = materialized
                if let duplicateKey = documentDuplicateKey(for: materialized) {
                    duplicateKeyToId[duplicateKey] = materialized.id
                }
            }
        }

        return orderedIds.compactMap { byId[$0] }.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt < rhs.addedAt
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
    }

    private func mergeVectorStoresIfNeeded(
        from localRoot: URL,
        to sharedRoot: URL,
        containers: [KnowledgeContainer],
        documents: [Document]
    ) async throws {
        let defaultContainerId = containers.first?.id
        let documentIdsByContainer = Dictionary(grouping: documents, by: { $0.containerId ?? defaultContainerId })
            .mapValues { Set($0.map(\.id)) }

        for container in containers where container.vectorDBKind == .persistentJSON {
            let localVectorURL = localRoot.appendingPathComponent("vector_database_\(container.id.uuidString).json")
            let sharedVectorURL = sharedRoot.appendingPathComponent("vector_database_\(container.id.uuidString).json")

            guard fileManager.fileExists(atPath: localVectorURL.path),
                  fileManager.fileExists(atPath: sharedVectorURL.path)
            else {
                continue
            }

            let canonicalDocumentIds = documentIdsByContainer[container.id] ?? []
            guard !canonicalDocumentIds.isEmpty else { continue }

            let localChunks = try await loadVectorChunks(from: localVectorURL, dimension: container.embeddingDim)
            let sharedChunks = try await loadVectorChunks(from: sharedVectorURL, dimension: container.embeddingDim)
            let mergedChunks = mergeVectorChunks(
                shared: sharedChunks,
                local: localChunks,
                allowedDocumentIds: canonicalDocumentIds
            )

            let mergedDatabase = BNNSVectorDatabase(dimension: container.embeddingDim, storageURL: sharedVectorURL)
            try await mergedDatabase.clear()
            if !mergedChunks.isEmpty {
                try await mergedDatabase.storeBatch(chunks: mergedChunks)
                try await mergedDatabase.persist()
            }
        }
    }

    private func loadVectorChunks(from storageURL: URL, dimension: Int) async throws -> [DocumentChunk] {
        let database = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
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

    private func mergeVectorChunks(
        shared: [DocumentChunk],
        local: [DocumentChunk],
        allowedDocumentIds: Set<UUID>
    ) -> [DocumentChunk] {
        var orderedIds: [UUID] = []
        var byId: [UUID: DocumentChunk] = [:]

        for chunk in shared where allowedDocumentIds.contains(chunk.documentId) {
            orderedIds.append(chunk.id)
            byId[chunk.id] = chunk
        }

        for chunk in local where allowedDocumentIds.contains(chunk.documentId) {
            if byId[chunk.id] == nil {
                orderedIds.append(chunk.id)
                byId[chunk.id] = chunk
            }
        }

        return orderedIds.compactMap { byId[$0] }.sorted { lhs, rhs in
            if lhs.documentId != rhs.documentId {
                return lhs.documentId.uuidString < rhs.documentId.uuidString
            }
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
    }

    private func materializeDocument(
        _ document: Document,
        from sourceRoot: URL,
        into sharedRoot: URL,
        reusing existingDocument: Document?
    ) throws -> Document {
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
            try copyItem(at: sourceURL, to: destinationURL)
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

    private func resolvedDocumentSourceURL(for document: Document, sourceRoot: URL) -> URL? {
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

    private func mergeDocument(primary: Document, secondary: Document) -> Document {
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

    private func documentQualityScore(_ document: Document) -> Int {
        var score = document.totalChunks * 100
        if document.processingMetadata != nil { score += 40 }
        if document.storageRelativePath != nil { score += 20 }
        if document.fileHash != nil { score += 10 }
        score += document.contentTags?.count ?? 0
        return score
    }

    private func mergeContentTags(_ lhs: [String]?, _ rhs: [String]?) -> [String]? {
        let merged = Array(Set((lhs ?? []) + (rhs ?? []))).sorted()
        return merged.isEmpty ? nil : merged
    }

    private func documentDuplicateKey(for document: Document) -> String? {
        if let fileHash = document.fileHash {
            return "hash:\(document.containerId?.uuidString ?? "global"):\(fileHash)"
        }

        if let relativePath = document.storageRelativePath {
            return "path:\(relativePath)"
        }

        return nil
    }

    private func mergeIngestionQueue(
        shared: PersistedIngestionQueueStateRecord?,
        local: PersistedIngestionQueueStateRecord?
    ) -> PersistedIngestionQueueStateRecord {
        let now = Date()
        var orderedIds: [UUID] = []
        var itemsById: [UUID: IngestionItem] = [:]
        var itemKeyToId: [String: UUID] = [:]
        var contextById: [UUID: IngestionContext] = [:]

        func ingest(_ state: PersistedIngestionQueueStateRecord?) {
            guard let state else { return }
            let stateContextMap = Dictionary(uniqueKeysWithValues: state.contexts.map { ($0.id, $0.context) })

            for item in state.items where !item.stage.isTerminal {
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
        ingest(local)

        let mergedItems = orderedIds.compactMap { itemsById[$0] }
        let mergedContexts = mergedItems.map {
            PersistedIngestionContextRecord(id: $0.id, context: contextById[$0.id] ?? .userInitiated)
        }

        return PersistedIngestionQueueStateRecord(
            items: mergedItems,
            contexts: mergedContexts,
            updatedAt: max(shared?.updatedAt ?? .distantPast, local?.updatedAt ?? .distantPast)
        )
    }

    private func synchronizeIngestionQueue(
        localRoot: URL,
        sharedRoot: URL,
        syncedContainerIDs: Set<UUID>,
        strategy: SyncResolutionStrategy
    ) throws {
        let localQueueURL = localRoot.appendingPathComponent("ingestion_queue.json")
        let sharedQueueURL = sharedRoot.appendingPathComponent("ingestion_queue.json")
        let localQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: localQueueURL)
        let sharedQueue = try Self.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: sharedQueueURL)

        let localOnlyQueue = filterIngestionQueue(localQueue, mode: .excluding(syncedContainerIDs))
        let localSyncedQueue = filterIngestionQueue(localQueue, mode: .including(syncedContainerIDs))
        let sharedSyncedQueue = filterIngestionQueue(sharedQueue, mode: .including(syncedContainerIDs))

        let mergedSyncedQueue: PersistedIngestionQueueStateRecord?
        switch strategy {
        case .mergeLibraries:
            let merged = mergeIngestionQueue(shared: sharedSyncedQueue, local: localSyncedQueue)
            mergedSyncedQueue = merged.items.isEmpty ? nil : merged
        case .useICloudWorkspace, .importExistingICloudLibraries:
            mergedSyncedQueue = sharedSyncedQueue?.items.isEmpty == false ? sharedSyncedQueue : nil
        }

        let finalLocalQueue = mergeIngestionQueue(shared: localOnlyQueue, local: mergedSyncedQueue)

        if finalLocalQueue.items.isEmpty {
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

    private enum QueueFilterMode {
        case including(Set<UUID>)
        case excluding(Set<UUID>)
    }

    private func filterIngestionQueue(
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

        guard !filteredItems.isEmpty else { return nil }
        return PersistedIngestionQueueStateRecord(items: filteredItems, contexts: filteredContexts, updatedAt: state.updatedAt)
    }

    private func synchronizeContainerArtifacts(
        localRoot: URL,
        sharedRoot: URL,
        syncedContainers: [KnowledgeContainer],
        syncedDocuments: [Document],
        strategy: SyncResolutionStrategy
    ) async throws {
        let defaultContainerId = syncedContainers.first?.id
        let documentIdsByContainer = Dictionary(grouping: syncedDocuments, by: { resolvedContainerID(for: $0, defaultContainerId: defaultContainerId) })
            .mapValues { Set($0.map(\.id)) }

        for container in syncedContainers {
            let allowedDocumentIds = documentIdsByContainer[container.id] ?? []
            try await synchronizeVectorStore(
                for: container,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                allowedDocumentIds: allowedDocumentIds,
                strategy: strategy
            )

            try synchronizeAuxiliaryFile(
                localURL: localRoot.appendingPathComponent("chat_history_\(container.id.uuidString).json"),
                sharedURL: sharedRoot.appendingPathComponent("chat_history_\(container.id.uuidString).json"),
                strategy: strategy
            )
            try synchronizeAuxiliaryFile(
                localURL: localRoot.appendingPathComponent("transcript_\(container.id.uuidString).json"),
                sharedURL: sharedRoot.appendingPathComponent("transcript_\(container.id.uuidString).json"),
                strategy: strategy
            )
            try synchronizeAuxiliaryFile(
                localURL: localRoot.appendingPathComponent("conversation_memory_\(container.id.uuidString).json"),
                sharedURL: sharedRoot.appendingPathComponent("conversation_memory_\(container.id.uuidString).json"),
                strategy: strategy
            )
        }
    }

    private func synchronizeVectorStore(
        for container: KnowledgeContainer,
        localRoot: URL,
        sharedRoot: URL,
        allowedDocumentIds: Set<UUID>,
        strategy: SyncResolutionStrategy
    ) async throws {
        let localVectorURL = localRoot.appendingPathComponent("vector_database_\(container.id.uuidString).json")
        let sharedVectorURL = sharedRoot.appendingPathComponent("vector_database_\(container.id.uuidString).json")

        guard container.vectorDBKind == .persistentJSON else {
            try? Self.coordinatedRemoveItem(at: sharedVectorURL)
            return
        }

        let localChunks = fileManager.fileExists(atPath: localVectorURL.path)
            ? (try await loadVectorChunks(from: localVectorURL, dimension: container.embeddingDim))
            : []
        let sharedChunks = fileManager.fileExists(atPath: sharedVectorURL.path)
            ? (try await loadVectorChunks(from: sharedVectorURL, dimension: container.embeddingDim))
            : []

        let resolvedChunks: [DocumentChunk]
        switch strategy {
        case .mergeLibraries:
            resolvedChunks = mergeVectorChunks(shared: sharedChunks, local: localChunks, allowedDocumentIds: allowedDocumentIds)
        case .useICloudWorkspace, .importExistingICloudLibraries:
            resolvedChunks = sharedChunks.filter { allowedDocumentIds.contains($0.documentId) }
        }

        if resolvedChunks.isEmpty {
            try? Self.coordinatedRemoveItem(at: sharedVectorURL)
            if allowedDocumentIds.isEmpty {
                try? Self.coordinatedRemoveItem(at: localVectorURL)
            }
            return
        }

        try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: localVectorURL)
        try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: sharedVectorURL)
    }

    private func persistVectorChunks(_ chunks: [DocumentChunk], dimension: Int, to url: URL) async throws {
        let database = BNNSVectorDatabase(dimension: dimension, storageURL: url)
        try await database.clear()
        if !chunks.isEmpty {
            try await database.storeBatch(chunks: chunks)
            try await database.persist()
        }
    }

    private func synchronizeAuxiliaryFile(localURL: URL, sharedURL: URL, strategy: SyncResolutionStrategy) throws {
        let localExists = fileManager.fileExists(atPath: localURL.path)
        let sharedExists = fileManager.fileExists(atPath: sharedURL.path)

        let preferredSource: URL?
        switch strategy {
        case .mergeLibraries:
            switch (localExists, sharedExists) {
            case (true, true):
                let localDate = modificationDate(for: localURL)
                let sharedDate = modificationDate(for: sharedURL)
                preferredSource = sharedDate >= localDate ? sharedURL : localURL
            case (true, false):
                preferredSource = localURL
            case (false, true):
                preferredSource = sharedURL
            case (false, false):
                preferredSource = nil
            }

        case .useICloudWorkspace, .importExistingICloudLibraries:
            preferredSource = sharedExists ? sharedURL : nil
        }

        guard let preferredSource else {
            if strategy != .mergeLibraries {
                try? Self.coordinatedRemoveItem(at: sharedURL)
            }
            return
        }

        if preferredSource.standardizedFileURL != localURL.standardizedFileURL {
            try copyItem(at: preferredSource, to: localURL)
        }
        if preferredSource.standardizedFileURL != sharedURL.standardizedFileURL {
            try copyItem(at: preferredSource, to: sharedURL)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func cleanupSharedWorkspace(
        sharedRoot: URL,
        syncedContainerIDs: Set<UUID>,
        referencedRelativePaths: Set<String>
    ) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: sharedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let name = item.lastPathComponent

            if name == Self.importedDocumentsFolderName {
                try cleanupSharedImportedDocuments(at: item, referencedRelativePaths: referencedRelativePaths, sharedRoot: sharedRoot)
                continue
            }

            if let containerId = containerIdFromArtifactName(name), !syncedContainerIDs.contains(containerId) {
                try? Self.coordinatedRemoveItem(at: item)
            }
        }
    }

    private func cleanupSharedImportedDocuments(
        at importedDocumentsDirectory: URL,
        referencedRelativePaths: Set<String>,
        sharedRoot: URL
    ) throws {
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

    private func containerIdFromArtifactName(_ name: String) -> UUID? {
        let prefixes = [
            "vector_database_",
            "chat_history_",
            "transcript_",
            "conversation_memory_"
        ]

        for prefix in prefixes where name.hasPrefix(prefix) {
            let suffix = String(name.dropFirst(prefix.count))
            let idString = suffix.replacingOccurrences(of: ".json", with: "")
            return UUID(uuidString: idString)
        }

        return nil
    }

    private func ingestionDuplicateKey(for item: IngestionItem) -> String {
        let containerKey = item.containerId?.uuidString ?? "local"

        if let documentHash = item.documentHash {
            return "hash:\(containerKey):\(documentHash)"
        }

        if let relativePath = item.storageRelativePath {
            return "path:\(containerKey):\(relativePath)"
        }

        return "id:\(containerKey):\(item.id.uuidString)"
    }

    private func preferredIngestionItem(primary: IngestionItem, secondary: IngestionItem, now: Date) -> IngestionItem {
        let primaryPriority = ingestionPriority(primary, now: now)
        let secondaryPriority = ingestionPriority(secondary, now: now)
        return secondaryPriority > primaryPriority ? secondary : primary
    }

    private func preferredIngestionItemMaterialized(primaryId: UUID, preferred: IngestionItem) -> IngestionItem {
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

    private func ingestionPriority(_ item: IngestionItem, now: Date) -> (Int, Int, Int, Int) {
        let activeLeaseScore = item.hasActiveLease(at: now) ? 1 : 0
        let stageScore: Int = {
            switch item.stage {
            case .queued: return 0
            case .loading: return 1
            case .transcribing: return 2
            case .extracting: return 3
            case .chunking: return 4
            case .analyzing: return 5
            case .adapting: return 6
            case .reindexing: return 7
            case .embedding: return 8
            case .indexing: return 9
            case .storing: return 10
            case .complete: return 11
            case .cancelled: return -1
            case .failed: return -2
            }
        }()
        let heartbeatScore = Int(item.lastLeaseHeartbeatAt?.timeIntervalSince1970 ?? 0)
        let progressScore = Int((item.progress ?? 0) * 1000)
        return (activeLeaseScore, stageScore, progressScore, heartbeatScore)
    }

    private func resolveSharedMetadataConflictsIfNeeded(in sharedRoot: URL) throws {
        for fileName in Self.criticalMetadataFileNames {
            let fileURL = sharedRoot.appendingPathComponent(fileName)
            try resolveConflictsIfNeeded(at: fileURL, sharedRoot: sharedRoot)
        }
    }

    private func resolveConflictsIfNeeded(at url: URL, sharedRoot: URL) throws {
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
                partial = mergeContainers(shared: partial, local: next)
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
            let merged = try mergeDocuments(sourced, into: sharedRoot)
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

    private func prepareWorkspaceDownloads(root: URL) async {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .ubiquitousItemDownloadingStatusKey
            ],
            options: [.skipsHiddenFiles]
        )

        var criticalURLs: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileManager.isUbiquitousItem(at: fileURL) else { continue }
            try? fileManager.startDownloadingUbiquitousItem(at: fileURL)

            if Self.criticalMetadataFileNames.contains(fileURL.lastPathComponent) {
                criticalURLs.append(fileURL)
            }
        }

        for criticalURL in criticalURLs {
            try? await Self.ensureItemAvailableLocally(at: criticalURL, timeout: 5)
        }
    }

    private func prepareWorkspaceDownloads(from metadataItems: [NSMetadataItem]) async {
        var criticalURLs: [URL] = []

        for item in metadataItems {
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            guard fileManager.isUbiquitousItem(at: fileURL) else { continue }

            try? fileManager.startDownloadingUbiquitousItem(at: fileURL)

            if Self.criticalMetadataFileNames.contains(fileURL.lastPathComponent) {
                criticalURLs.append(fileURL)
            }
        }

        for criticalURL in criticalURLs {
            try? await Self.ensureItemAvailableLocally(at: criticalURL, timeout: 5)
        }
    }

    private func startObservingSharedWorkspace(at root: URL) {
        let standardizedRoot = root.standardizedFileURL
        guard metadataQuery == nil || monitoredWorkspaceRoot != standardizedRoot else { return }

        stopObservingSharedWorkspace()

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.notificationBatchingInterval = 0.75
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, standardizedRoot.path)

        let center = NotificationCenter.default
        metadataQueryObservers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    await self?.handleMetadataQueryResults(notification, publishObservedChange: false)
                }
            }
        )

        metadataQueryObservers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    await self?.handleMetadataQueryResults(notification, publishObservedChange: true)
                }
            }
        )

        monitoredWorkspaceRoot = standardizedRoot
        lastObservedWorkspaceSignature = nil
        metadataQuery = query
        _ = query.start()
    }

    private func stopObservingSharedWorkspace() {
        if let query = metadataQuery {
            query.stop()
        }

        let center = NotificationCenter.default
        for observer in metadataQueryObservers {
            center.removeObserver(observer)
        }

        metadataQueryObservers.removeAll()
        metadataQuery = nil
        monitoredWorkspaceRoot = nil
        lastObservedWorkspaceSignature = nil
    }

    private func handleMetadataQueryResults(_ notification: Notification, publishObservedChange: Bool) async {
        guard let query = notification.object as? NSMetadataQuery,
              query === metadataQuery
        else {
            return
        }

        query.disableUpdates()
        let workspaceItems = query.results
            .compactMap { $0 as? NSMetadataItem }
            .filter(isWorkspaceMetadataItemRelevant)
        let signature = workspaceSignature(for: workspaceItems)
        query.enableUpdates()

        guard signature != lastObservedWorkspaceSignature else { return }
        lastObservedWorkspaceSignature = signature

        await prepareWorkspaceDownloads(from: workspaceItems)

        if publishObservedChange {
            recordSuccessfulSync()
            observedWorkspaceChangeCount += 1
            statusMessage = "Detected shared workspace changes from iCloud Drive."
        } else if isUsingSharedWorkspace {
            statusMessage = "Watching iCloud Drive for shared workspace changes."
        }
    }

    private func isWorkspaceMetadataItemRelevant(_ item: NSMetadataItem) -> Bool {
        guard let workspaceRoot = monitoredWorkspaceRoot?.standardizedFileURL else { return false }
        guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return false }

        let standardizedURL = fileURL.standardizedFileURL
        let rootPath = workspaceRoot.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let filePath = standardizedURL.path

        guard filePath == rootPath || filePath.hasPrefix(rootPrefix) else { return false }

        return !standardizedURL.pathComponents.contains(where: { Self.localOnlyEntryNames.contains($0) })
    }

    private func workspaceSignature(for items: [NSMetadataItem]) -> Int {
        struct Snapshot {
            let path: String
            let modifiedAt: TimeInterval
        }

        let snapshots: [Snapshot] = items.compactMap { item in
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
            let modifiedAt = (item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970 ?? 0
            return Snapshot(path: fileURL.standardizedFileURL.path, modifiedAt: modifiedAt)
        }
        .sorted { lhs, rhs in
            lhs.path < rhs.path
        }

        var hasher = Hasher()
        hasher.combine(snapshots.count)

        for snapshot in snapshots {
            hasher.combine(snapshot.path)
            hasher.combine(snapshot.modifiedAt)
        }

        return hasher.finalize()
    }

    private func copyItem(at source: URL, to destination: URL) throws {
        try ensureDirectory(destination.deletingLastPathComponent())
        if source.hasDirectoryPath {
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        try Self.coordinatedCopyItem(at: source, to: destination)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func nextAvailableImportedDocumentURL(in sharedRoot: URL, preferredFileName: String) -> URL {
        let importedDocumentsDirectory = sharedRoot.appendingPathComponent(Self.importedDocumentsFolderName, isDirectory: true)
        try? ensureDirectory(importedDocumentsDirectory)

        let sanitizedFileName = preferredFileName.replacingOccurrences(of: "/", with: "-")
        let nsName = sanitizedFileName as NSString
        let ext = nsName.pathExtension
        let stem = nsName.deletingPathExtension.isEmpty ? "Document" : nsName.deletingPathExtension

        var candidateName = sanitizedFileName.isEmpty ? "Document" : sanitizedFileName
        var candidateURL = importedDocumentsDirectory.appendingPathComponent(candidateName)
        var counter = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidateURL = importedDocumentsDirectory.appendingPathComponent(candidateName)
            counter += 1
        }

        return candidateURL
    }

    private func relativePath(from root: URL, to fileURL: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(rootPrefix) else { return nil }
        return String(filePath.dropFirst(rootPrefix.count))
    }

    nonisolated static func coordinatedReadData(from url: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        var result: Data?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                result = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let readError {
            throw readError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return result
    }

    nonisolated static func coordinatedWriteData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    nonisolated static func coordinatedRemoveItem(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var removeError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let removeError {
            throw removeError
        }
    }

    nonisolated static func coordinatedCopyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var copyError: Error?

        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            writingItemAt: destination,
            options: [],
            error: &coordinationError
        ) { coordinatedSourceURL, coordinatedDestinationURL in
            do {
                if FileManager.default.fileExists(atPath: coordinatedDestinationURL.path) {
                    try FileManager.default.removeItem(at: coordinatedDestinationURL)
                }
                try FileManager.default.copyItem(at: coordinatedSourceURL, to: coordinatedDestinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }
    }

    nonisolated private static func readJSONIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try coordinatedReadData(from: url)
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try coordinatedWriteData(data, to: url)
    }

    nonisolated private static func resolveUbiquityContainerURL() async -> URL? {
        await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
    }

    nonisolated private static func ensureDeviceIdentifier(in defaults: UserDefaults) {
        if defaults.string(forKey: deviceIdentifierDefaultsKey) == nil {
            defaults.set(UUID().uuidString, forKey: deviceIdentifierDefaultsKey)
        }
    }
}
