import Combine
import Foundation

@MainActor
final class WorkspaceSyncService: ObservableObject {
    static let syncEnabledDefaultsKey = "enableSharedWorkspaceSync"
    static let deviceIdentifierDefaultsKey = "openIntelligence.workspaceSync.deviceID"

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

    @Published private(set) var isUsingSharedWorkspace = false
    @Published private(set) var statusMessage = "Shared workspace sync is off."
    @Published private(set) var activeWorkspaceRoot: URL?
    @Published private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var ubiquityIdentityObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        Self.ensureDeviceIdentifier(in: defaults)
        activateLocalWorkspace(reason: "Shared workspace sync is off.")

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
        if let ubiquityIdentityObserver {
            NotificationCenter.default.removeObserver(ubiquityIdentityObserver)
        }
    }

    var isSyncEnabled: Bool {
        defaults.object(forKey: Self.syncEnabledDefaultsKey) as? Bool ?? false
    }

    var workspaceRootDescription: String? {
        activeWorkspaceRoot?.path
    }

    @discardableResult
    func reconfigureIfNeeded() async -> Bool {
        guard isSyncEnabled else {
            lastErrorMessage = nil
            return activateLocalWorkspace(reason: "Shared workspace sync is off.")
        }

        guard fileManager.ubiquityIdentityToken != nil else {
            lastErrorMessage = "iCloud Drive is unavailable for the current Apple account."
            return activateLocalWorkspace(reason: "iCloud Drive is unavailable on this device.")
        }

        statusMessage = "Preparing shared workspace..."
        lastErrorMessage = nil

        guard let containerURL = await Self.resolveUbiquityContainerURL() else {
            lastErrorMessage = "The iCloud ubiquity container could not be resolved."
            return activateLocalWorkspace(reason: "Unable to reach the iCloud workspace right now.")
        }

        let sharedWorkspaceRoot = sharedWorkspaceRootURL(for: containerURL)
        let localWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        let localCacheRoot = OpenIntelligenceRuntimePaths.localCacheDirectory()
        let didChange = activeWorkspaceRoot != sharedWorkspaceRoot || !isUsingSharedWorkspace

        do {
            try ensureDirectory(sharedWorkspaceRoot)
            try migrateCanonicalWorkspaceIfNeeded(from: localWorkspaceRoot, to: sharedWorkspaceRoot)

            AppSupportPaths.configureBaseDir(sharedWorkspaceRoot)
            AppSupportPaths.configureLocalCacheDir(localCacheRoot)
            activeWorkspaceRoot = sharedWorkspaceRoot
            isUsingSharedWorkspace = true
            statusMessage = "Syncing through iCloud Drive."

            await prepareWorkspaceDownloads(root: sharedWorkspaceRoot)
            return didChange
        } catch {
            lastErrorMessage = error.localizedDescription
            return activateLocalWorkspace(reason: "Shared workspace setup failed. Using local storage.")
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

    private func activateLocalWorkspace(reason: String) -> Bool {
        let previousRoot = activeWorkspaceRoot
        let wasUsingSharedWorkspace = isUsingSharedWorkspace

        AppSupportPaths.configureBaseDir(nil)
        AppSupportPaths.configureLocalCacheDir(nil)
        activeWorkspaceRoot = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        isUsingSharedWorkspace = false
        statusMessage = reason

        return previousRoot != activeWorkspaceRoot || wasUsingSharedWorkspace
    }

    private func sharedWorkspaceRootURL(for containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.workspaceFolderName, isDirectory: true)
    }

    private func migrateCanonicalWorkspaceIfNeeded(from localRoot: URL, to sharedRoot: URL) throws {
        guard fileManager.fileExists(atPath: localRoot.path) else { return }

        let localContents = try fileManager.contentsOfDirectory(
            at: localRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for entry in localContents {
            let name = entry.lastPathComponent
            guard !Self.localOnlyEntryNames.contains(name) else { continue }

            let destination = sharedRoot.appendingPathComponent(name, isDirectory: entry.hasDirectoryPath)
            if fileManager.fileExists(atPath: destination.path) {
                continue
            }

            try copyItem(at: entry, to: destination)
        }

        try migrateDocumentMetadataIfNeeded(from: localRoot, to: sharedRoot)
    }

    private func migrateDocumentMetadataIfNeeded(from localRoot: URL, to sharedRoot: URL) throws {
        let localDocumentsURL = localRoot.appendingPathComponent("documents_metadata.json")
        let sharedDocumentsURL = sharedRoot.appendingPathComponent("documents_metadata.json")
        let sourceURL = fileManager.fileExists(atPath: sharedDocumentsURL.path) ? sharedDocumentsURL : localDocumentsURL

        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        let documents = try decoder.decode([Document].self, from: data)
        let importedDocumentsRoot = sharedRoot.appendingPathComponent(Self.importedDocumentsFolderName, isDirectory: true)
        try ensureDirectory(importedDocumentsRoot)

        var migratedDocuments: [Document] = []
        migratedDocuments.reserveCapacity(documents.count)

        for document in documents {
            var migratedDocument = document

            if let relativePath = document.storageRelativePath {
                let sharedDocumentURL = sharedRoot.appendingPathComponent(relativePath)
                if !fileManager.fileExists(atPath: sharedDocumentURL.path) {
                    let localDocumentURL = localRoot.appendingPathComponent(relativePath)
                    if fileManager.fileExists(atPath: localDocumentURL.path) {
                        try copyItem(at: localDocumentURL, to: sharedDocumentURL)
                    }
                }
            } else if fileManager.fileExists(atPath: document.fileURL.path) {
                let destinationURL = nextAvailableImportedDocumentURL(
                    in: sharedRoot,
                    preferredFileName: document.filename
                )
                if !fileManager.fileExists(atPath: destinationURL.path) {
                    try copyItem(at: document.fileURL, to: destinationURL)
                }

                migratedDocument = Document(
                    id: document.id,
                    filename: document.filename,
                    fileURL: destinationURL,
                    storageRelativePath: relativePath(from: sharedRoot, to: destinationURL),
                    fileHash: document.fileHash,
                    contentType: document.contentType,
                    addedAt: document.addedAt,
                    totalChunks: document.totalChunks,
                    processingMetadata: document.processingMetadata,
                    containerId: document.containerId,
                    contentTags: document.contentTags
                )
            }

            migratedDocuments.append(migratedDocument)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let migratedData = try encoder.encode(migratedDocuments)
        try migratedData.write(to: sharedDocumentsURL, options: .atomic)
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

    private func copyItem(at source: URL, to destination: URL) throws {
        try ensureDirectory(destination.deletingLastPathComponent())
        try fileManager.copyItem(at: source, to: destination)
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
