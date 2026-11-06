import Combine
import CryptoKit
@preconcurrency import Foundation
import os

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
    /// Libraries with an import this device had not finished when the inventory was read.
    /// The import queue is read before `documents`, so an import that finishes while a pass
    /// runs is still listed here even when its document is missing from `documents`.
    var librariesWithUnfinishedImports: Set<UUID> = []
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

    /// Signature of a container's vector artifacts at the moment a sync pass proved both
    /// its local and shared stores already matched the merged content.
    ///
    /// Why this exists. `synchronizeVectorStore` reads **every chunk of every library out of
    /// both roots** before it can decide whether a write is needed, and a sync pass runs on
    /// every `.localWorkspaceDidChange`. A device capture on 2026-08-24 measured the result:
    /// **128 store opens and 43,164 chunk records deserialised in one session, against zero
    /// writes** — and 64 of those opens, 21,582 records, happened before the app had drawn a
    /// screen. The decision to do nothing was costing a full read of the corpus, repeatedly,
    /// on the main actor.
    ///
    /// The comparison itself is deliberately exact and stays that way; the note above
    /// `vectorChunksAreIdentical` records why a count-only or id-only check is unsafe here and
    /// that reasoning is untouched. This only avoids *reaching* that comparison when nothing
    /// the comparison reads has changed.
    ///
    /// Correctness rests on the signature being conservative in the right direction: it is
    /// recorded **only** when a pass concluded both stores were already current, and any
    /// difference in file size, modification date, document set or source-container set
    /// invalidates it. An unreadable attribute yields `nil`, which never matches, so doubt
    /// always takes the full path. A cold start has an empty cache and behaves exactly as
    /// before.
    ///
    /// Since 2026-10-10 the record is kept across launches (as a digest, in `UserDefaults`). A
    /// cold start used to begin empty, so every launch decoded both copies of every synced
    /// library and compared them passage by passage: two 3 s decodes, every vector copied to
    /// the heap twice and a 144,247-passage comparison for the owner's largest library, to
    /// conclude nothing had changed. The rule above is unchanged and holds across a launch as
    /// it does within one: the same sizes, dates, documents, aliases and strategy.
    nonisolated let vectorStoreSyncSignatures = OSAllocatedUnfairLock<[UUID: String]>(
        initialState: WorkspaceSyncService.savedVectorStoreSignatureDigests())

    nonisolated static let vectorStoreSignatureDigestsKey = "workspaceSync.vectorStoreSignatureDigests.v1"

    nonisolated static func vectorStoreSignatureDigest(_ signature: String) -> String {
        SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func savedVectorStoreSignatureDigests(defaults: UserDefaults = .standard) -> [UUID: String] {
        guard let saved = defaults.dictionary(forKey: vectorStoreSignatureDigestsKey) as? [String: String] else {
            return [:]
        }
        var digests: [UUID: String] = [:]
        for (key, value) in saved {
            if let id = UUID(uuidString: key) { digests[id] = value }
        }
        return digests
    }

    nonisolated static func saveVectorStoreSignatureDigests(
        _ digests: [UUID: String], defaults: UserDefaults = .standard
    ) {
        var saved: [String: String] = [:]
        for (id, digest) in digests { saved[id.uuidString] = digest }
        defaults.set(saved, forKey: vectorStoreSignatureDigestsKey)
    }
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

    nonisolated static let workspaceFolderName = "OpenIntelligenceWorkspace"
    nonisolated static let importedDocumentsFolderName = "ImportedDocuments"
    nonisolated static let criticalMetadataFileNames: Set<String> = [
        "containers.json",
        "documents_metadata.json",
        "ingestion_queue.json"
    ]
    nonisolated static let localOnlyEntryNames: Set<String> = [
        "FTS5",
        "LocalCache",
        "continued_ingestion_status.json",
        "continued_query_state.json",
        "continued_query_status.json"
    ]

    @Published var isUsingSharedWorkspace = false
    @Published var statusMessage = "All libraries are local only."
    @Published var activeWorkspaceRoot: URL?
    @Published var lastErrorMessage: String?
    @Published var lastSyncAttemptAt: Date?
    @Published var lastSuccessfulSyncAt: Date?
    @Published var observedWorkspaceChangeCount: Int = 0
    @Published var pendingBootstrapConflict: PendingBootstrapConflict?
    @Published var unsupportedSyncContainerNames: [String] = []

    nonisolated(unsafe) let defaults: UserDefaults
    nonisolated(unsafe) let fileManager: FileManager
    private var ubiquityIdentityObserver: NSObjectProtocol?
    var metadataQuery: NSMetadataQuery?
    var metadataQueryObservers: [NSObjectProtocol] = []
    var monitoredWorkspaceRoot: URL?
    var lastObservedWorkspaceSignature: Int?
    var pendingBootstrapPlan: PendingBootstrapPlan?
    var isReconfigureInProgress = false
    var needsReconfigurePass = false
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

}
