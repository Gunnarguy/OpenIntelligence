//
//  WatchedFolderService.swift
//  OpenIntelligence
//
//  Checks watched folders and imports what is new (5.8).
//

import Combine
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Keeps libraries up with their watched folders. A check walks each folder, reads only files whose date or
/// size changed, and hands the new ones to the import queue, the same queue the Add Documents button uses.
///
/// iOS doesn't let a long import start in the background, so iPhone and iPad check when the app opens. A Mac
/// also checks every few minutes while the app runs. Files deleted from a folder stay in their library, and
/// the originals are only ever read.
@MainActor
final class WatchedFolderService: ObservableObject {
    static let shared = WatchedFolderService()

    /// How often a Mac checks while the app runs.
    static let macCheckInterval: Duration = .seconds(300)

    @Published private(set) var folders: [WatchedFolder] = WatchedFolderStore.load()
    @Published private(set) var isChecking = false

    /// One instance runs in the app; tests make their own.
    init() {}

    /// The queue's items this service put there, so the import panel can stay out of the way.
    private var ownItemIds: Set<UUID> = []

    /// Whether every import under way came from a watched folder.
    func isOnlyWatchedWork(_ items: [IngestionItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { ownItemIds.contains($0.id) }
    }

    /// Held, not weak: on a Mac each window has its own, and closing that window mustn't stop the checks.
    var entitlements: EntitlementStore?
    private var wantsAnotherCheck = false
    private var repeating: Task<Void, Never>?

    func folder(forLibrary libraryId: UUID?) -> WatchedFolder? {
        folders.first { $0.libraryId == libraryId }
    }

    // MARK: - Starting and stopping

    /// Remembers a folder for a library. `url` must be in its security scope, as the picker hands it over.
    func watch(_ url: URL, library libraryId: UUID) throws {
        let folder = WatchedFolder(
            id: UUID(), libraryId: libraryId, name: url.lastPathComponent, bookmark: try Self.bookmark(for: url))
        folders.removeAll { $0.libraryId == libraryId }
        folders.append(folder)
        WatchedFolderStore.save(folders)
    }

    /// Stops checking. What came from the folder stays in the library.
    func stopWatching(library libraryId: UUID) {
        folders.removeAll { $0.libraryId == libraryId }
        WatchedFolderStore.save(folders)
    }

    /// How many files a folder would import, to ask first about a large one. `url` must be in its scope.
    func countOfFiles(in url: URL) async -> Int {
        await Self.walk(url)?.count ?? 0
    }

    // MARK: - Checking

    /// Checks when the app comes forward, and starts a Mac's repeating check.
    func appCameForward(engine: RAGService, entitlements: EntitlementStore) {
        self.entitlements = entitlements
        Task { await check(engine: engine) }
        #if os(macOS)
            guard repeating == nil else { return }
            repeating = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.macCheckInterval)
                    guard let self, let engine = RAGService.activePresentedInstance else { continue }
                    await self.check(engine: engine)
                }
            }
        #endif
    }

    /// Checks every folder, on what the plan allows.
    func check(engine: RAGService) async {
        guard let entitlements, entitlements.effectiveTier.isAtLeast(.pro) else { return }
        await check(engine: engine, documentLimit: entitlements.documentLimit)
    }

    /// Checks every folder. Past this point a plan is no longer read: Library Settings stops new folders, and a
    /// lapsed plan never reaches here, so what was imported simply stays.
    func check(engine: RAGService, documentLimit: Int) async {
        guard !folders.isEmpty else { return }
        guard !isChecking else {
            // A folder chosen during a check, which must not wait five minutes or a relaunch.
            wantsAnotherCheck = true
            return
        }
        isChecking = true
        defer { isChecking = false }
        repeat {
            wantsAnotherCheck = false
            await settle(engine: engine)
            for id in folders.map(\.id) {
                await check(folderWithId: id, engine: engine, documentLimit: documentLimit)
            }
            WatchedFolderStore.save(folders)
        } while wantsAnotherCheck
    }

    private func check(folderWithId id: UUID, engine: RAGService, documentLimit: Int) async {
        guard var folder = folders.first(where: { $0.id == id }),
            engine.containerService.containers.contains(where: { $0.id == folder.libraryId })
        else { return }
        let checkStarted = Date()
        defer {
            VerificationJournal.record(
                "watchedFolder.check", folder.note == "This folder can't be reached. Stop watching it and choose it again." ? .failed : .ok,
                durationMs: Date().timeIntervalSince(checkStarted) * 1000,
                ["folder": VerificationJournal.anon(id), "files": "\(folder.files.count)", "note": folder.note == nil ? "none" : "yes"])
            folder.lastCheckedAt = Date()
            // By id, and only if it is still there: Stop Watching can run during the waits below.
            if let index = folders.firstIndex(where: { $0.id == id }) { folders[index] = folder }
        }
        let unreachable = "This folder can't be reached. Stop watching it and choose it again."
        guard let url = resolve(&folder) else {
            folder.note = unreachable
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let found = await Self.walk(url) else {
            folder.note = unreachable
            return
        }
        // A path no longer there is forgotten, so a later file of that name is a new file and not a new version
        // of what stayed in the library.
        let present = Set(found.map(\.relativePath))
        folder.files = folder.files.filter { present.contains($0.key) }

        // A file still importing waits: a second version queued now would leave the first with no owner.
        let active = Set(engine.ingestionItems.filter { !$0.stage.isTerminal }.map(\.id))
        let inFlight = Set(folder.files.filter { $0.value.queueItemId.map(active.contains) ?? false }.keys)
        let room =
            documentLimit == QuotaPolicy.unlimitedDocumentLimit
            ? Int.max : documentLimit - engine.countedDocumentCount - active.count
        let changes = WatchedFolderChanges.decide(
            found: found.filter { !inFlight.contains($0.relativePath) }, seen: folder.files, room: room)
        for file in changes.waitingForDownload {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file.url)
        }

        let inLibrary = Dictionary(
            documents(in: folder.libraryId, engine: engine).compactMap { document in
                document.fileHash.map { ($0, document.id) }
            }, uniquingKeysWith: { first, _ in first })
        let read = await Self.read(changes.toRead, seen: folder.files, inLibrary: inLibrary)

        for outcome in read where outcome.stagedURL == nil {
            folder.files[outcome.file.relativePath] = outcome.seen
        }
        let staged = read.filter { $0.stagedURL != nil }
        let itemIds = engine.enqueueDocuments(staged.compactMap(\.stagedURL), containerId: folder.libraryId)
        ownItemIds.formUnion(itemIds)
        for (outcome, itemId) in zip(staged, itemIds) {
            var seen = outcome.seen
            seen.queueItemId = itemId
            folder.files[outcome.file.relativePath] = seen
        }

        // A file that ended with no document: nothing retries it until it changes, so it has to be said. Said once
        // this folder's own imports have ended; until 2026-11-11 the note waited for every import in the app to end,
        // so a file importing into another library hid it (a flaky test on Xcode Cloud, runs 495 to 497).
        let waiting = active.union(itemIds)
        let ownWaiting = folder.files.values.contains { $0.queueItemId.map(waiting.contains) ?? false }
        let failed = folder.files.values.filter { seen in
            seen.documentId == nil && !(seen.queueItemId.map(waiting.contains) ?? false)
        }.count
        folder.note = WatchedFolderChanges.note(
            overLimit: changes.overLimit, waitingForDownload: changes.waitingForDownload.count,
            failed: ownWaiting ? 0 : failed, unreadable: changes.toRead.count - read.count)
        if !staged.isEmpty {
            Log.info("[WatchedFolders] \(staged.count) file(s) from \(folder.name) queued", category: .ingestion)
        }
        VerificationJournal.record(
            "watchedFolder.found",
            ["folder": VerificationJournal.anon(id), "toRead": "\(changes.toRead.count)", "queued": "\(staged.count)",
                "overLimit": "\(changes.overLimit)", "downloading": "\(changes.waitingForDownload.count)", "failed": "\(failed)"])
    }

    /// Ties finished imports to their documents, removes the versions they replaced, and continues an import a
    /// restart paused.
    ///
    /// **A document is removed only if a file here imported it, and only when no other file here names it.** The
    /// library can hold the same bytes for other reasons: the person imported them by hand, or a second file in the
    /// folder has them. `SeenFile.ownsDocument` is what tells those apart, and removing one of those would lose
    /// something the folder never gave. An old version that can't be removed stays and is tried again next time.
    private func settle(engine: RAGService) async {
        var removals: [(folder: UUID, path: String, document: Document)] = []
        for index in folders.indices {
            let documents = documents(in: folders[index].libraryId, engine: engine)
            for (path, seen) in folders[index].files where seen.documentId == nil || seen.replacesDocumentId != nil {
                var settled = seen
                if settled.documentId == nil,
                    let document = documents.first(where: { $0.fileHash == seen.hash })
                {
                    settled.documentId = document.id
                    settled.queueItemId = nil
                }
                if let current = settled.documentId, let old = settled.replacesDocumentId {
                    let namedElsewhere = folders[index].files.contains { other in
                        other.key != path && other.value.documentId == old
                    }
                    if old == current || namedElsewhere {
                        settled.replacesDocumentId = nil
                    } else if let document = documents.first(where: { $0.id == old }) {
                        removals.append((folders[index].id, path, document))
                    } else {
                        settled.replacesDocumentId = nil
                    }
                }
                folders[index].files[path] = settled
            }
        }
        for removal in removals {
            do {
                try await engine.removeDocument(removal.document)
            } catch {
                Log.warning(
                    "[WatchedFolders] The old version of \(removal.document.filename) stayed: \(error.localizedDescription)",
                    category: .ingestion)
                continue
            }
            if let index = folders.firstIndex(where: { $0.id == removal.folder }) {
                folders[index].files[removal.path]?.replacesDocumentId = nil
            }
        }

        // An item in the queue comes back paused for the person to continue, and nobody asked for these. Only when
        // every paused item is one of these, and they didn't pause the queue themselves.
        let ours = Set(folders.flatMap { $0.files.values.compactMap(\.queueItemId) })
        let paused = engine.ingestionItems.filter { $0.stage == .paused }.map(\.id)
        if !paused.isEmpty, paused.allSatisfy(ours.contains), !engine.ingestionPausedByPerson {
            engine.continuePausedIngestionQueue()
        }
    }

    /// A document stored before libraries existed has no library id and lives in the first one.
    private func documents(in library: UUID, engine: RAGService) -> [Document] {
        let first = engine.containerService.containers.first?.id
        return engine.documents.filter { ($0.containerId ?? first) == library }
    }

    // MARK: - The folder

    private static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
            try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
            try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// The folder's URL. A bookmark the system calls stale still resolves; it is made again while it does.
    private func resolve(_ folder: inout WatchedFolder) -> URL? {
        var isStale = false
        #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
            let options: URL.BookmarkResolutionOptions = []
        #endif
        guard
            let url = try? URL(
                resolvingBookmarkData: folder.bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale
            )
        else { return nil }
        if isStale {
            let scoped = url.startAccessingSecurityScopedResource()
            if let fresh = try? Self.bookmark(for: url) { folder.bookmark = fresh }
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    /// The folder's importable files, through its subfolders, or nil when the folder can't be read. Hidden files
    /// and the insides of packages are skipped, as when a folder is dropped on the app. A file iCloud Drive has
    /// taken off the device can show as a hidden `.name.icloud`, which is that file and not a hidden one.
    @concurrent private static func walk(_ folder: URL) async -> [WatchedFolderFile]? {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isHiddenKey, .contentTypeKey, .fileSizeKey,
            .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard (try? folder.checkResourceIsReachable()) == true,
            let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants])
        else { return nil }
        let root = folder.standardizedFileURL.path
        func relative(_ file: URL) -> String { String(file.standardizedFileURL.path.dropFirst(root.count + 1)) }
        func isImportable(_ type: UTType?) -> Bool {
            guard let type else { return false }
            return ImportedFileStaging.importableTypes.contains { type.conforms(to: $0) }
        }

        var found: [WatchedFolderFile] = []
        while let file = walker.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: keys) else { continue }
            let name = file.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > 8 {
                let real = file.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
                if isImportable(UTType(filenameExtension: real.pathExtension)) {
                    found.append(
                        WatchedFolderFile(
                            relativePath: relative(real), url: real, size: 0, modified: .distantPast, isDownloaded: false))
                }
                continue
            }
            if values.isHidden == true {
                if values.isDirectory == true { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                isImportable(values.contentType ?? UTType(filenameExtension: file.pathExtension))
            else { continue }
            let status = values.ubiquitousItemDownloadingStatus
            found.append(
                WatchedFolderFile(
                    relativePath: relative(file),
                    url: file,
                    size: Int64(values.fileSize ?? 0),
                    modified: values.contentModificationDate ?? .distantPast,
                    isDownloaded: status == nil || status == .current || status == .downloaded))
        }
        return found.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private struct ReadFile: Sendable {
        let file: WatchedFolderFile
        var seen: WatchedFolder.SeenFile
        /// The copy to import, or nil when the file needs no import: its contents are already in the library.
        var stagedURL: URL?
    }

    /// Hashes each file and copies what the library doesn't hold into the app. A file that can't be read is left
    /// out, and counted by the caller. Off the main actor: reading can download.
    @concurrent private static func read(
        _ files: [WatchedFolderFile], seen: [String: WatchedFolder.SeenFile], inLibrary: [String: UUID]
    ) async -> [ReadFile] {
        var result: [ReadFile] = []
        var stagedThisPass = Set<String>()
        for file in files {
            guard let hash = try? sha256(of: file.url) else { continue }
            let previous = seen[file.relativePath]
            // Touched but the same bytes: everything known about it stands, an import still finishing included.
            if var same = previous, same.hash == hash {
                same.size = file.size
                same.modified = file.modified
                result.append(ReadFile(file: file, seen: same))
                continue
            }
            var entry = WatchedFolder.SeenFile(size: file.size, modified: file.modified, hash: hash)
            // Keeps the first old version when a file changes twice before it settles. Only a document this
            // file imported is ever replaced.
            entry.replacesDocumentId =
                previous?.replacesDocumentId ?? (previous?.ownsDocument == true ? previous?.documentId : nil)
            if let existing = inLibrary[hash] {
                // The library holds these bytes already, so this file doesn't own that document.
                entry.documentId = existing
                result.append(ReadFile(file: file, seen: entry))
                continue
            }
            // A second file with the same bytes as one staged just now takes its document when it arrives.
            if stagedThisPass.contains(hash) {
                result.append(ReadFile(file: file, seen: entry))
                continue
            }
            do {
                entry.ownsDocument = true
                let staged = try IntentSupport.copyIntoImports(file.url)
                stagedThisPass.insert(hash)
                result.append(ReadFile(file: file, seen: entry, stagedURL: staged))
            } catch {
                Log.warning(
                    "[WatchedFolders] \(file.relativePath) could not be copied: \(error.localizedDescription)",
                    category: .ingestion)
            }
        }
        return result
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
