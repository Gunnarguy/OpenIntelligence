import Combine
@preconcurrency import Foundation

extension Notification.Name {
    nonisolated static let localWorkspaceDidChange = Notification.Name("openIntelligence.workspaceSync.localWorkspaceDidChange")
}


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

/// Failures that must abort a sync pass rather than be absorbed into a merge.
///
/// The merge in `synchronizeVectorStore` is destructive by design: whatever it
/// resolves to becomes the new truth on both roots, and an empty resolution
/// deletes the stores. That is only safe when every input was genuinely read.
/// A shared store that exists in iCloud but has not been materialized on this
/// device reads as zero chunks, which is indistinguishable from "the library is
/// empty" unless we refuse to continue — so we refuse.
enum WorkspaceSyncError: LocalizedError {
    /// A shared vector store exists in iCloud but its contents did not download in time.
    case sharedVectorStoreUnavailable(containerIDs: [UUID])

    var errorDescription: String? {
        switch self {
        case let .sharedVectorStoreUnavailable(containerIDs):
            return "iCloud has not finished downloading the search index for \(containerIDs.count) library(s). Sync was stopped so the existing index is not overwritten."
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

struct IngestionQueueTombstone: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let containerId: UUID?
    let discardedAt: Date

    nonisolated init(id: UUID, containerId: UUID?, discardedAt: Date = Date()) {
        self.id = id
        self.containerId = containerId
        self.discardedAt = discardedAt
    }
}

enum IngestionQueueTombstonePolicy {
    nonisolated static let maximumRetainedTombstones = 512

    nonisolated static func merged(
        _ first: [IngestionQueueTombstone],
        _ second: [IngestionQueueTombstone]
    ) -> [IngestionQueueTombstone] {
        var byID: [UUID: IngestionQueueTombstone] = [:]
        for tombstone in first + second {
            if let existing = byID[tombstone.id], existing.discardedAt >= tombstone.discardedAt {
                continue
            }
            byID[tombstone.id] = tombstone
        }
        return byID.values
            .sorted { $0.discardedAt > $1.discardedAt }
            .prefix(maximumRetainedTombstones)
            .map { $0 }
    }

    nonisolated static func removingTombstonedItems(
        _ items: [IngestionItem],
        tombstones: [IngestionQueueTombstone]
    ) -> [IngestionItem] {
        let discardedIDs = Set(tombstones.map(\.id))
        return items.filter { !discardedIDs.contains($0.id) }
    }
}

struct PersistedIngestionQueueStateRecord: Codable, Sendable {
    let items: [IngestionItem]
    let contexts: [PersistedIngestionContextRecord]
    let tombstones: [IngestionQueueTombstone]
    let updatedAt: Date

    nonisolated var isEmpty: Bool {
        items.isEmpty && tombstones.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case items
        case contexts
        case tombstones
        case updatedAt
    }

    nonisolated init(
        items: [IngestionItem],
        contexts: [PersistedIngestionContextRecord],
        tombstones: [IngestionQueueTombstone] = [],
        updatedAt: Date
    ) {
        self.items = items
        self.contexts = contexts
        self.tombstones = tombstones
        self.updatedAt = updatedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode([IngestionItem].self, forKey: .items)
        self.contexts = try container.decode([PersistedIngestionContextRecord].self, forKey: .contexts)
        self.tombstones = try container.decodeIfPresent([IngestionQueueTombstone].self, forKey: .tombstones) ?? []
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(contexts, forKey: .contexts)
        try container.encode(tombstones, forKey: .tombstones)
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

    nonisolated(unsafe) private let defaults: UserDefaults
    nonisolated(unsafe) private let fileManager: FileManager
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

    nonisolated private func workspaceInventory(at root: URL) async throws -> WorkspaceInventory {
        try await Task.detached {
            try self.readWorkspaceInventorySync(at: root)
        }.value
    }

    nonisolated private func readWorkspaceInventorySync(at root: URL) throws -> WorkspaceInventory {
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
            let mergedChunks = mergeVectorChunks(
                shared: sharedChunks,
                local: localChunks,
                allowedDocumentIds: canonicalDocumentIds
            )

            storeOpens += 1
            let mergedDatabase = await MainActor.run {
                BNNSVectorDatabase(dimension: container.embeddingDim, storageURL: sharedVectorURL)
            }
            try await mergedDatabase.clear()
            if !mergedChunks.isEmpty {
                storeWrites += 1
                try await mergedDatabase.storeBatch(chunks: mergedChunks)
                try await mergedDatabase.persist()
            }
        }
    }

    nonisolated private func loadVectorChunks(from storageURL: URL, dimension: Int) async throws -> [DocumentChunk] {
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
            resolvedChunks = mergeVectorChunks(shared: sharedChunks, local: localChunks, allowedDocumentIds: allowedDocumentIds)
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
                    Log.error(
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
                Log.error(
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
            try await persistVectorChunks(resolvedChunks, dimension: container.embeddingDim, to: sharedVectorURL)
        }

        for sourceContainerID in sourceContainerIDs where sourceContainerID != container.id {
            removeVectorStoreArtifacts(for: sourceContainerID, in: localRoot, reason: "chunks merged into the destination library")
            removeVectorStoreArtifacts(for: sourceContainerID, in: sharedRoot, reason: "chunks merged into the destination library")
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

    nonisolated private func vectorStoreBaseURL(for containerId: UUID, in root: URL) -> URL {
        root.appendingPathComponent("vector_database_\(containerId.uuidString).json")
    }

    nonisolated private func vectorStoreArtifactURLs(for containerId: UUID, in root: URL) -> [URL] {
        BNNSVectorDatabase.binaryFileURLs(from: vectorStoreBaseURL(for: containerId, in: root))
    }

    /// True when a vector store exists at `root`, including one that lives in
    /// iCloud but has not been downloaded to this device yet.
    nonisolated private func vectorStoreExists(for containerId: UUID, in root: URL) -> Bool {
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
    nonisolated private func removeVectorStoreArtifacts(for containerId: UUID, in root: URL, reason: String) {
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
        Log.error(
            "[WorkspaceSync] Deleted vector store for container \(containerId) (\(removed) artifact(s), root \(root.lastPathComponent)): \(reason).",
            category: .ingestion
        )
    }

    nonisolated private func repairWorkspaceMetadataIfNeeded(
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
    nonisolated private func ensureItemsAvailableLocally(_ urls: [URL], timeout: TimeInterval = 20) async -> [URL] {
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

    nonisolated private func ubiquitousPlaceholderExists(for url: URL) -> Bool {
        fileManager.fileExists(atPath: ubiquitousPlaceholderURL(for: url).path)
    }

    /// True when the item exists in iCloud, whether or not its contents are on this device.
    ///
    /// `FileManager.fileExists` alone answers "are the bytes here", which is a
    /// different question and the wrong one for deciding whether data exists.
    nonisolated private func ubiquitousItemExists(at url: URL) -> Bool {
        if ubiquitousPlaceholderExists(for: url) { return true }
        return fileManager.fileExists(atPath: url.path)
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

        try await Task.detached {
            try Self.coordinatedCopyItem(at: source, to: destination)
        }.value
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

    /// Read, transform and write a file under a **single** `NSFileCoordinator`
    /// write claim, so no other reader or writer can land between the read and
    /// the write.
    ///
    /// This is the piece the workspace was missing. `coordinatedReadData` and
    /// `coordinatedWriteData` each coordinate their own access, which makes an
    /// individual read or write atomic — but a read-modify-write built from the
    /// two is not. A sync pass read the document list, spent seconds merging
    /// containers and awaiting iCloud downloads, then wrote back a set computed
    /// before a concurrent ingestion had finished. Both accesses were correctly
    /// coordinated; the data was destroyed anyway, because the *sequence* was
    /// never atomic.
    ///
    /// `.forMerging` is the documented option for exactly this shape: it tells
    /// the coordinator (and any file presenter, including the iCloud daemon)
    /// that the accessor intends to read the current contents and write a
    /// combined result.
    ///
    /// Keep `transform` cheap and free of I/O or `await`. Anything slow belongs
    /// outside, computed optimistically and reconciled here.
    nonisolated static func coordinatedMergeData(
        at url: URL,
        transform: (Data?) throws -> Data
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var accessorError: Error?

        var didChangeBytes = false

        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                let existing = FileManager.default.fileExists(atPath: coordinatedURL.path)
                    ? try Data(contentsOf: coordinatedURL)
                    : nil
                let merged = try transform(existing)

                // Writing identical bytes is not free here, it is the thing that keeps the sync
                // running. Every pass rewrote the shared `containers.json` and
                // `documents_metadata.json` whether or not the merge changed anything, and
                // `workspaceSignature` hashes `NSMetadataItemFSContentChangeDateKey`, so an
                // identical-bytes rewrite still moved the content date, still incremented
                // `observedWorkspaceChangeCount`, and still triggered the next pass. A device
                // capture on 2026-08-18 shows six full passes from one scene change and zero
                // container changes.
                //
                // Byte equality is the correct predicate rather than a conservative one: all four
                // transforms serialise with `.prettyPrinted` and `.sortedKeys`, so identical
                // content really does produce identical bytes and this fires in practice instead
                // of merely existing. A first write, where `existing` is nil, always proceeds.
                guard merged != existing else { return }

                try merged.write(to: coordinatedURL, options: .atomic)
                didChangeBytes = true
            } catch {
                accessorError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let accessorError { throw accessorError }

        // The notification is gated on the same condition. Announcing a change that did not
        // happen is the other half of the loop: it feeds the debounced reconfigure directly.
        if didChangeBytes,
           url.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
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
