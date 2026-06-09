import Combine
import Foundation

extension Notification.Name {
    nonisolated static let localWorkspaceDidChange = Notification.Name("openIntelligence.workspaceSync.localWorkspaceDidChange")
}

extension FileManager: @retroactive @unchecked Sendable {}
extension UserDefaults: @retroactive @unchecked Sendable {}

enum SyncBootstrapChoice: Sendable {
    case mergeLibraries
    case useICloudWorkspace
}

enum BootstrapBehavior: Sendable {
    case promptUser
    case autoMergeLibraries
}

enum SyncResolutionStrategy: Sendable, Equatable {
    case mergeLibraries
    case useICloudWorkspace
    case importExistingICloudLibraries

    nonisolated static func == (lhs: SyncResolutionStrategy, rhs: SyncResolutionStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.mergeLibraries, .mergeLibraries): return true
        case (.useICloudWorkspace, .useICloudWorkspace): return true
        case (.importExistingICloudLibraries, .importExistingICloudLibraries): return true
        default: return false
        }
    }
}

struct SyncPendingBootstrapConflict: Sendable {
    let localLibraryCount: Int
    let localDocumentCount: Int
    let sharedLibraryCount: Int
    let sharedDocumentCount: Int
    let mergedLibraryCount: Int
    let mergedDocumentCount: Int
    let localOnlyLibraryIDs: [UUID]
    let localOnlyLibraryNames: [String]
    let sharedOnlyLibraryNames: [String]
}

struct WorkspaceInventory {
    let containers: [KnowledgeContainer]
    let documents: [Document]
}

struct ContainerMergeResult {
    let containers: [KnowledgeContainer]
    let sourceToCanonical: [UUID: UUID]
    let canonicalToSources: [UUID: [UUID]]
}

struct DocumentMergeResult {
    let documents: [Document]
    let sourceToCanonical: [UUID: UUID]
}

struct PendingBootstrapPlan {
    let localRoot: URL
    let sharedRoot: URL
    let localInventory: WorkspaceInventory
    let sharedInventory: WorkspaceInventory
}

struct SourcedDocument {
    let document: Document
    let sourceRoot: URL
}

struct PersistedIngestionContextRecord: Codable, Sendable {
    let id: UUID
    let context: IngestionContext

    enum CodingKeys: String, CodingKey {
        case id
        case context
    }

    nonisolated init(id: UUID, context: IngestionContext) {
        self.id = id
        self.context = context
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.context = try container.decode(IngestionContext.self, forKey: .context)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(context, forKey: .context)
    }
}

struct PersistedIngestionQueueStateRecord: Codable, Sendable {
    let items: [IngestionItem]
    let contexts: [PersistedIngestionContextRecord]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case items
        case contexts
        case updatedAt
    }

    nonisolated init(items: [IngestionItem], contexts: [PersistedIngestionContextRecord], updatedAt: Date) {
        self.items = items
        self.contexts = contexts
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode([IngestionItem].self, forKey: .items)
        self.contexts = try container.decode([PersistedIngestionContextRecord].self, forKey: .contexts)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(contexts, forKey: .contexts)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum QueueFilterMode {
    case including(Set<UUID>)
    case excluding(Set<UUID>)
}

@MainActor
final class WorkspaceSyncService: ObservableObject {
    typealias BootstrapChoice = SyncBootstrapChoice
    typealias PendingBootstrapConflict = SyncPendingBootstrapConflict

    nonisolated static let syncEnabledDefaultsKey = "enableSharedWorkspaceSync"
    nonisolated static let deviceIdentifierDefaultsKey = "openIntelligence.workspaceSync.deviceID"
    nonisolated static let lastSyncAttemptDefaultsKey = "openIntelligence.workspaceSync.lastAttemptAt"
    nonisolated static let lastSuccessfulSyncDefaultsKey = "openIntelligence.workspaceSync.lastSuccessfulSyncAt"
    nonisolated static let lastResolvedBootstrapLocalSignatureDefaultsKey = "openIntelligence.workspaceSync.lastResolvedBootstrapLocalSignature"
    nonisolated static let lastResolvedBootstrapSharedSignatureDefaultsKey = "openIntelligence.workspaceSync.lastResolvedBootstrapSharedSignature"
    nonisolated static let hasBootstrappedSharedWorkspaceDefaultsKey = "openIntelligence.workspaceSync.hasBootstrappedSharedWorkspace"

    nonisolated(unsafe) private static var _isSyncWriteInProgress = false
    nonisolated static var isSyncWriteInProgress: Bool {
        get {
            objc_sync_enter(WorkspaceSyncService.self)
            defer { objc_sync_exit(WorkspaceSyncService.self) }
            return _isSyncWriteInProgress
        }
        set {
            objc_sync_enter(WorkspaceSyncService.self)
            defer { objc_sync_exit(WorkspaceSyncService.self) }
            _isSyncWriteInProgress = newValue
        }
    }

    nonisolated private static let workspaceFolderName = "OpenIntelligenceWorkspace"
    nonisolated private static let importedDocumentsFolderName = "ImportedDocuments"
    nonisolated private static let criticalMetadataFileNames: Set<String> = [
        "containers.json",
        "documents_metadata.json",
        "ingestion_queue.json"
    ]
    nonisolated private static let localOnlyEntryNames: Set<String> = [
        "FTS5",
        "LocalCache",
        "continued_ingestion_status.json",
        "continued_query_state.json",
        "continued_query_status.json"
    ]

    @Published private(set) var isUsingSharedWorkspace = false
    @Published private(set) var statusMessage = "All libraries are local only."
    @Published private(set) var activeWorkspaceRoot: URL?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSyncAttemptAt: Date?
    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published private(set) var observedWorkspaceChangeCount: Int = 0
    @Published private(set) var pendingBootstrapConflict: PendingBootstrapConflict?
    @Published private(set) var unsupportedSyncContainerNames: [String] = []

    nonisolated private let defaults: UserDefaults
    nonisolated private let fileManager: FileManager
    private var ubiquityIdentityObserver: NSObjectProtocol?
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryObservers: [NSObjectProtocol] = []
    private var monitoredWorkspaceRoot: URL?
    private var lastObservedWorkspaceSignature: Int?
    private var pendingBootstrapPlan: PendingBootstrapPlan?
    private var isReconfigureInProgress = false
    private var needsReconfigurePass = false
    private var cancellables = Set<AnyCancellable>()

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

        NotificationCenter.default.publisher(for: .localWorkspaceDidChange)
            .debounce(for: .seconds(2.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    _ = await self?.reconfigureIfNeeded(bootstrapBehavior: .autoMergeLibraries)
                }
            }
            .store(in: &cancellables)
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
        await reconfigureIfNeeded(bootstrapBehavior: .promptUser)
    }

    @discardableResult
    func reconfigureForExplicitICloudOptIn() async -> Bool {
        await reconfigureIfNeeded(bootstrapBehavior: .autoMergeLibraries)
    }

    @discardableResult
    private func reconfigureIfNeeded(bootstrapBehavior: BootstrapBehavior) async -> Bool {
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
            localInventory = try workspaceInventory(at: localWorkspaceRoot)
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
            try await resolveSharedMetadataConflictsIfNeeded(in: pendingBootstrapPlan.sharedRoot)

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
            let localInventory = try workspaceInventory(at: localWorkspaceRoot)
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
            try await resolveSharedMetadataConflictsIfNeeded(in: sharedWorkspaceRoot)

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
        try await resolveSharedMetadataConflictsIfNeeded(in: sharedRoot)

        let sharedInventory = try workspaceInventory(at: sharedRoot)
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

        if let remainingQueue, !remainingQueue.items.isEmpty {
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
        defaults.set(true, forKey: Self.hasBootstrappedSharedWorkspaceDefaultsKey)
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

    private func recordResolvedBootstrap(for localInventory: WorkspaceInventory, sharedInventory: WorkspaceInventory) {
        defaults.set(inventorySignature(for: localInventory), forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey)
        defaults.set(inventorySignature(for: sharedInventory), forKey: Self.lastResolvedBootstrapSharedSignatureDefaultsKey)
    }

    nonisolated private func resolvedBootstrapLocalSignature() -> Int? {
        defaults.object(forKey: Self.lastResolvedBootstrapLocalSignatureDefaultsKey) as? Int
    }

    nonisolated private func resolvedBootstrapSharedSignature() -> Int? {
        defaults.object(forKey: Self.lastResolvedBootstrapSharedSignatureDefaultsKey) as? Int
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

        let ingestionQueue = try Self.readJSONIfPresent(
            PersistedIngestionQueueStateRecord.self,
            from: root.appendingPathComponent("ingestion_queue.json")
        )

        let repairResult = try repairWorkspaceMetadataIfNeeded(
            at: root,
            containers: containers,
            documents: documents,
            ingestionQueue: ingestionQueue
        )

        return WorkspaceInventory(
            containers: repairResult.containers,
            documents: repairResult.documents
        )
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

    nonisolated private func sortedContainers(_ containers: [KnowledgeContainer]) -> [KnowledgeContainer] {
        containers.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private func sortedDocuments(_ documents: [Document]) -> [Document] {
        documents.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt < rhs.addedAt
            }
            return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
    }

    nonisolated private func resolvedContainerID(for document: Document, defaultContainerId: UUID?) -> UUID? {
        document.containerId ?? defaultContainerId
    }

    nonisolated private func normalizeSharedContainer(_ container: KnowledgeContainer) -> KnowledgeContainer {
        var normalized = container
        normalized.syncMode = .iCloudShared
        return normalized
    }

    nonisolated private func synchronizeConfiguredLibraries(
        localRoot: URL,
        sharedRoot: URL,
        localInventory: WorkspaceInventory,
        sharedInventory: WorkspaceInventory,
        strategy: SyncResolutionStrategy
    ) async throws {
        let deletedContainersURL = sharedRoot.appendingPathComponent("deleted_containers.json")
        let deletedContainerIDs = Set((try? Self.readJSONIfPresent([String].self, from: deletedContainersURL))?.compactMap { UUID(uuidString: $0) } ?? [])

        let allLocalContainers = sortedContainers(localInventory.containers)
        let localContainerById = Dictionary(uniqueKeysWithValues: allLocalContainers.map { ($0.id, $0) })
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
        let canonicalContainerById = Dictionary(uniqueKeysWithValues: mergeResult.containers.map { ($0.id, $0) })
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
            guard let rawContainerId = resolvedContainerID(for: document, defaultContainerId: localDefaultContainerId) else {
                return document
            }

            let canonicalId = mergeResult.sourceToCanonical[rawContainerId] ?? rawContainerId
            guard !finalSyncedContainerIDs.contains(canonicalId) else { return nil }
            return applyingContainerAliases(to: document, aliases: mergeResult.sourceToCanonical)
        }

        let effectiveSharedDocuments = sharedInventory.documents.compactMap { document -> Document? in
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
            strategy: strategy
        )

        try await cleanupSharedWorkspace(
            sharedRoot: sharedRoot,
            syncedContainerIDs: finalSyncedContainerIDs,
            referencedRelativePaths: Set(finalSharedDocuments.compactMap(\.storageRelativePath))
        )

        let removedContainerIDs = Set(localInventory.containers.map(\.id)).subtracting(finalLocalContainers.map(\.id))
        for containerId in removedContainerIDs {
            removeVectorStoreArtifacts(for: containerId, in: localRoot)
            let prefixes = ["chat_history_", "transcript_", "conversation_memory_"]
            for prefix in prefixes {
                let localAuxURL = localRoot.appendingPathComponent("\(prefix)\(containerId.uuidString).json")
                try? Self.coordinatedRemoveItem(at: localAuxURL)
            }
        }
    }

    nonisolated private func unsupportedSyncContainerNames(
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

    nonisolated private func pendingBootstrapPlan(
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

    nonisolated private func makePendingBootstrapConflict(from plan: PendingBootstrapPlan) -> PendingBootstrapConflict {
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

    nonisolated private func inventorySignature(for inventory: WorkspaceInventory) -> Int {
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

    nonisolated private func createRecoverySnapshot(at root: URL, label: String) async throws {
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

    nonisolated private func mergeContainers(shared: [KnowledgeContainer], local: [KnowledgeContainer]) -> ContainerMergeResult {
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

    nonisolated private func mergeDocuments(_ sourcedDocuments: [SourcedDocument], into sharedRoot: URL) async throws -> [Document] {
        try await mergeDocumentsWithAliases(sourcedDocuments, into: sharedRoot).documents
    }

    nonisolated private func mergeDocumentsWithAliases(_ sourcedDocuments: [SourcedDocument], into sharedRoot: URL) async throws -> DocumentMergeResult {
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

            let localChunks = try await loadVectorChunks(from: localVectorURL, dimension: container.embeddingDim)
            let sharedChunks = try await loadVectorChunks(from: sharedVectorURL, dimension: container.embeddingDim)
            let mergedChunks = mergeVectorChunks(
                shared: sharedChunks,
                local: localChunks,
                allowedDocumentIds: canonicalDocumentIds
            )

            let mergedDatabase = await MainActor.run {
                BNNSVectorDatabase(dimension: container.embeddingDim, storageURL: sharedVectorURL)
            }
            try await mergedDatabase.clear()
            if !mergedChunks.isEmpty {
                try await mergedDatabase.storeBatch(chunks: mergedChunks)
                try await mergedDatabase.persist()
            }
        }
    }

    nonisolated private func loadVectorChunks(from storageURL: URL, dimension: Int) async throws -> [DocumentChunk] {
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

    nonisolated private func mergeVectorChunks(
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

    nonisolated private func vectorChunkDuplicateKey(for chunk: DocumentChunk) -> String {
        "\(chunk.documentId.uuidString)|\(chunk.metadata.chunkIndex)|\(chunk.content)"
    }

    nonisolated private func applyingDocumentAliases(to chunks: [DocumentChunk], aliases: [UUID: UUID]) -> [DocumentChunk] {
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

    nonisolated private func resolvedDocumentSourceURL(for document: Document, sourceRoot: URL) -> URL? {
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

    nonisolated private func mergeDocument(primary: Document, secondary: Document) -> Document {
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

    nonisolated private func documentDuplicateKey(for document: Document) -> String? {
        if let fileHash = document.fileHash {
            return "hash:\(document.containerId?.uuidString ?? "global"):\(fileHash)"
        }

        if let relativePath = document.storageRelativePath {
            return "path:\(relativePath)"
        }

        return nil
    }

    nonisolated private func mergeIngestionQueue(
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

            for item in state.items {
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

    nonisolated private func synchronizeIngestionQueue(
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

        guard !filteredItems.isEmpty else { return nil }
        return PersistedIngestionQueueStateRecord(items: filteredItems, contexts: filteredContexts, updatedAt: state.updatedAt)
    }

    nonisolated private func filterIngestionQueueExcludingContainers(
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

        guard !filteredItems.isEmpty else { return nil }
        return PersistedIngestionQueueStateRecord(items: filteredItems, contexts: filteredContexts, updatedAt: state.updatedAt)
    }

    nonisolated private func synchronizeContainerArtifacts(
        localRoot: URL,
        sharedRoot: URL,
        syncedContainers: [KnowledgeContainer],
        syncedDocuments: [Document],
        documentAliases: [UUID: UUID],
        sourceContainerIDsByCanonicalID: [UUID: [UUID]],
        strategy: SyncResolutionStrategy
    ) async throws {
        let defaultContainerId = syncedContainers.first?.id
        let documentIdsByContainer = Dictionary(grouping: syncedDocuments, by: { resolvedContainerID(for: $0, defaultContainerId: defaultContainerId) })
            .mapValues { Set($0.map(\.id)) }

        for container in syncedContainers {
            let allowedDocumentIds = documentIdsByContainer[container.id] ?? []
            let sourceContainerIDs = Set(sourceContainerIDsByCanonicalID[container.id] ?? [container.id])
            try await synchronizeVectorStore(
                for: container,
                localRoot: localRoot,
                sharedRoot: sharedRoot,
                sourceContainerIDs: sourceContainerIDs,
                allowedDocumentIds: allowedDocumentIds,
                documentAliases: documentAliases,
                strategy: strategy
            )

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
            removeVectorStoreArtifacts(for: container.id, in: sharedRoot)
            removeVectorStoreArtifacts(for: container.id, in: localRoot)
            for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
                removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot)
                removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot)
            }
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
            resolvedChunks = mergeVectorChunks(shared: sharedChunks, local: localChunks, allowedDocumentIds: allowedDocumentIds)
        case .useICloudWorkspace, .importExistingICloudLibraries:
            resolvedChunks = sharedChunks.filter { allowedDocumentIds.contains($0.documentId) }
        }

        if resolvedChunks.isEmpty {
            removeVectorStoreArtifacts(for: container.id, in: sharedRoot)
            if allowedDocumentIds.isEmpty {
                removeVectorStoreArtifacts(for: container.id, in: localRoot)
            }
            for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
                removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot)
                removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot)
            }
            return
        }

        try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: localVectorURL)
        try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: sharedVectorURL)

        for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
            removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot)
            removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot)
        }
    }

    nonisolated private func persistVectorChunks(_ chunks: [DocumentChunk], dimension: Int, to url: URL) async throws {
        let database = await MainActor.run {
            BNNSVectorDatabase(dimension: dimension, storageURL: url)
        }
        try await database.clear()
        if !chunks.isEmpty {
            try await database.storeBatch(chunks: chunks)
            try await database.persist()
        }
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

    nonisolated private func vectorStoreBaseURL(for containerId: UUID, in root: URL) -> URL {
        root.appendingPathComponent("vector_database_\(containerId.uuidString).json")
    }

    nonisolated private func vectorStoreArtifactURLs(for containerId: UUID, in root: URL) -> [URL] {
        BNNSVectorDatabase.binaryFileURLs(from: vectorStoreBaseURL(for: containerId, in: root))
    }

    nonisolated private func vectorStoreExists(for containerId: UUID, in root: URL) -> Bool {
        vectorStoreArtifactURLs(for: containerId, in: root)
            .contains { fileManager.fileExists(atPath: $0.path) }
    }

    nonisolated private func removeVectorStoreArtifacts(for containerId: UUID, in root: URL) {
        for url in vectorStoreArtifactURLs(for: containerId, in: root) {
            try? Self.coordinatedRemoveItem(at: url)
        }
    }

    private func repairWorkspaceMetadataIfNeeded(
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
            if let repairedQueue, repairedQueue.items.isEmpty == false {
                try Self.writeJSON(repairedQueue, to: queueURL)
            } else {
                try? Self.coordinatedRemoveItem(at: queueURL)
            }
        }

        return (mergeResult.containers, repairedDocuments)
    }

    nonisolated private func deduplicatedDocuments(_ documents: [Document]) -> [Document] {
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

    nonisolated private func applyingContainerAliases(to documents: [Document], aliases: [UUID: UUID]) -> [Document] {
        documents.map { applyingContainerAliases(to: $0, aliases: aliases) }
    }

    nonisolated private func applyingContainerAliases(to document: Document, aliases: [UUID: UUID]) -> Document {
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

    nonisolated private func applyingContainerAliases(
        to state: PersistedIngestionQueueStateRecord?,
        aliases: [UUID: UUID]
    ) -> PersistedIngestionQueueStateRecord? {
        guard let state else { return nil }

        let remappedItems = state.items.map { item in
            applyingContainerAliases(to: item, aliases: aliases)
        }

        let normalizedState = PersistedIngestionQueueStateRecord(
            items: remappedItems,
            contexts: state.contexts,
            updatedAt: state.updatedAt
        )

        let merged = mergeIngestionQueue(shared: nil, local: normalizedState)
        return merged.items.isEmpty ? nil : merged
    }

    nonisolated private func applyingContainerAliases(to item: IngestionItem, aliases: [UUID: UUID]) -> IngestionItem {
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

    nonisolated private func matchingSharedContainerIDs(for targetContainer: KnowledgeContainer, in containers: [KnowledgeContainer]) -> Set<UUID> {
        let normalizedTargetContainer = normalizeSharedContainer(targetContainer)

        return Set(containers.compactMap { container in
            let normalizedContainer = normalizeSharedContainer(container)

            if normalizedContainer.id == normalizedTargetContainer.id {
                return normalizedContainer.id
            }

            return nil
        })
    }

    nonisolated private func containerMergeKey(for container: KnowledgeContainer) -> String? {
        guard container.syncMode == .iCloudShared else { return nil }

        // Shared-library identity must be stable and library-specific.
        // Using the display name caused unrelated libraries like "General"
        // on two devices to merge into one iCloud library.
        return container.id.uuidString.lowercased()
    }

    nonisolated private func uniqueContainerIDs(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    nonisolated private func jsonEncodedValuesMatch<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let lhsData = try? encoder.encode(lhs),
              let rhsData = try? encoder.encode(rhs)
        else {
            return false
        }

        return lhsData == rhsData
    }

    nonisolated private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    nonisolated private func ensureItemsAvailableLocally(_ urls: [URL], timeout: TimeInterval = 20) async {
        var seenPaths: Set<String> = []
        var urlsToDownload: [URL] = []

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else { continue }
            guard fileManager.fileExists(atPath: standardizedURL.path) else { continue }
            guard fileManager.isUbiquitousItem(at: standardizedURL) else { continue }

            try? fileManager.startDownloadingUbiquitousItem(at: standardizedURL)
            urlsToDownload.append(standardizedURL)
        }

        guard !urlsToDownload.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in urlsToDownload {
                group.addTask {
                    try? await Self.ensureItemAvailableLocally(at: url, timeout: timeout)
                }
            }
        }
    }

    nonisolated private func ensureSourcedDocumentsAvailableLocally(_ sourcedDocuments: [SourcedDocument]) async {
        let urls = sourcedDocuments.compactMap { sourcedDocument in
            resolvedDocumentSourceURL(for: sourcedDocument.document, sourceRoot: sourcedDocument.sourceRoot)
        }
        await ensureItemsAvailableLocally(urls)
    }

    nonisolated private func cleanupSharedWorkspace(
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

    nonisolated private func ingestionDuplicateKey(for item: IngestionItem) -> String {
        let containerKey = item.containerId?.uuidString ?? "local"

        if let documentHash = item.documentHash {
            return "hash:\(containerKey):\(documentHash)"
        }

        if let relativePath = item.storageRelativePath {
            return "path:\(containerKey):\(relativePath)"
        }

        return "id:\(containerKey):\(item.id.uuidString)"
    }

    nonisolated private func preferredIngestionItem(primary: IngestionItem, secondary: IngestionItem, now: Date) -> IngestionItem {
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

    nonisolated private func preferredIngestionItemMaterialized(primaryId: UUID, preferred: IngestionItem) -> IngestionItem {
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
            case .cancelled: return 12
            case .failed: return 13
            }
        }()
        let heartbeatScore = Int(item.lastLeaseHeartbeatAt?.timeIntervalSince1970 ?? 0)
        let progressScore = Int((item.progress ?? 0) * 1000)
        return (activeLeaseScore, stageScore, progressScore, heartbeatScore)
    }

    nonisolated private func enforceLibraryLimit(for containers: [KnowledgeContainer]) throws {
        let limit = EntitlementStore.currentLibraryLimit(defaults: defaults)
        guard containers.count <= limit else {
            let tier = EntitlementStore.currentEffectiveTier(defaults: defaults)
            throw LibraryQuotaError(limit: limit, attemptedCount: containers.count, tier: tier)
        }
    }

    nonisolated private func resolveSharedMetadataConflictsIfNeeded(in sharedRoot: URL) async throws {
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

    nonisolated private func prepareWorkspaceDownloads(root: URL) async {
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

        await withTaskGroup(of: Void.self) { group in
            for criticalURL in criticalURLs {
                group.addTask {
                    try? await Self.ensureItemAvailableLocally(at: criticalURL, timeout: 5)
                }
            }
        }
    }

    nonisolated private func prepareWorkspaceDownloads(from metadataItems: [NSMetadataItem]) async {
        var criticalURLs: [URL] = []

        for item in metadataItems {
            guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            guard fileManager.isUbiquitousItem(at: fileURL) else { continue }

            try? fileManager.startDownloadingUbiquitousItem(at: fileURL)

            if Self.criticalMetadataFileNames.contains(fileURL.lastPathComponent) {
                criticalURLs.append(fileURL)
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for criticalURL in criticalURLs {
                group.addTask {
                    try? await Self.ensureItemAvailableLocally(at: criticalURL, timeout: 5)
                }
            }
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
            statusMessage = "Detected shared workspace changes from iCloud Sync."
        } else if isUsingSharedWorkspace {
            statusMessage = "Watching iCloud Sync for shared workspace changes."
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

        let lastComponent = standardizedURL.lastPathComponent
        if lastComponent.hasPrefix("vector_database_") {
            return false
        }

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

    nonisolated private func copyItem(at source: URL, to destination: URL) async throws {
        try ensureDirectory(destination.deletingLastPathComponent())
        if source.hasDirectoryPath {
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        try Self.coordinatedCopyItem(at: source, to: destination)
    }

    nonisolated private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    nonisolated private func nextAvailableImportedDocumentURL(in sharedRoot: URL, preferredFileName: String) -> URL {
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

    nonisolated private func relativePath(from root: URL, to fileURL: URL) -> String? {
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

        if url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
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

        if url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
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

        if destination.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
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
