//
//  WorkspaceSyncService+FileCoordination.swift
//  OpenIntelligence
//
//  Part of WorkspaceSyncService, moved from WorkspaceSyncService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//
import Combine
import CryptoKit
@preconcurrency import Foundation
import os

extension WorkspaceSyncService {
    /// `@concurrent` (5.7): with approachable concurrency a `nonisolated async` method runs on its caller's actor,
    /// so this walk of the whole iCloud library folder (a `startDownloadingUbiquitousItem` and its extended-attribute
    /// reads for every file) ran on the main thread. On the owner's iPhone (Instruments, 2026-10-21) it froze the app
    /// for 2.72, 2.15 and 1.84 s in the first 12 s after launch, once for each reconfigure pass.
    @concurrent nonisolated func prepareWorkspaceDownloads(root: URL) async {
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

    /// Off the main actor for the same reason as `prepareWorkspaceDownloads(root:)` (5.7).
    @concurrent nonisolated func prepareWorkspaceDownloads(from metadataItems: [NSMetadataItem]) async {
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

    func startObservingSharedWorkspace(at root: URL) {
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

    func stopObservingSharedWorkspace() {
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

    nonisolated func copyItem(at source: URL, to destination: URL) async throws {
        try ensureDirectory(destination.deletingLastPathComponent())
        if source.hasDirectoryPath {
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        try await Task.detached {
            try Self.coordinatedCopyItem(at: source, to: destination)
        }.value
    }

    nonisolated func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    nonisolated func nextAvailableImportedDocumentURL(in sharedRoot: URL, preferredFileName: String) -> URL {
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

    nonisolated func relativePath(from root: URL, to fileURL: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(rootPrefix) else { return nil }
        return String(filePath.dropFirst(rootPrefix.count))
    }

    /// The small lists a sync pass reads and rewrites on the main actor (5.8, `waitUntilSyncFilesAreFree`), which every
    /// device rewrites and iCloud holds while it uploads them. Not the vector stores: the pass reads those only when
    /// their signature changed, and through `ensureItemsAvailableLocally`, which has its own limit; a wait on one could
    /// last a whole download. Not iCloud's conflict copies ("documents_metadata 3.json"), which the pass never reads.
    nonisolated static func syncFilesToWaitFor(in root: URL, fileManager: FileManager = .default) -> [URL] {
        let lists: Set<String> = [
            "containers.json", "documents_metadata.json", "deleted_documents.json", "deleted_containers.json",
            "ingestion_queue.json", EvidenceThreadStore.deletedThreadsFileName,
        ]
        guard let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.filter { lists.contains($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Waits, off the main thread, until no other process holds the lists a pass is about to read, before the pass
    /// reads them on the main actor as it always has (5.8). Gives up after `timeout` and lets the pass go on.
    ///
    /// Why: on the owner's Mac on 2026-11-03 the window froze at launch while the pass waited in `NSFileCoordinator`
    /// for iCloud to release `deleted_documents.json` (`sample`: the main thread in `_blockOnAccessClaim` for all 4 s,
    /// at about 1% CPU). Moving the pass itself off the main thread was tried and taken back the same day: a refuting
    /// review showed the pass's read-merge-write steps, which run with no `await` on the main actor, would then let the
    /// app's own writes land between a read and its write, so a deletion could be overwritten and come back on every
    /// device. So the pass is unchanged and this runs first, at the `await` that already followed
    /// `prepareWorkspaceDownloads`: one coordinated read of every list, granted once iCloud has finished with all of
    /// them, so the pass's own reads find them free. iCloud can take a file again in the moment between, which this
    /// narrows and doesn't close. A list iCloud has evicted is listed as ".name.icloud" and isn't waited for.
    ///
    /// The limit: a claim nobody releases would otherwise hold every later pass, since a pass that hasn't finished
    /// makes the next one wait its turn. After `timeout` the pass reads as it did before 5.8, which can block the main
    /// thread again but can't hang sync for good.
    @concurrent nonisolated static func waitUntilSyncFilesAreFree(
        in roots: [URL], timeout: Duration = .seconds(20)
    ) async {
        let files = roots.flatMap { syncFilesToWaitFor(in: $0) }
        guard !files.isEmpty else { return }
        let started = Date()
        let intents = files.map { NSFileAccessIntent.readingIntent(with: $0, options: []) }
        nonisolated(unsafe) let coordinator = NSFileCoordinator(filePresenter: nil)
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { coordinator.cancel() }
        }
        let error: Error? = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            coordinator.coordinate(with: intents, queue: OperationQueue()) { continuation.resume(returning: $0) }
        }
        timer.cancel()
        let waitedMs = Date().timeIntervalSince(started) * 1000
        if let error {
            VerificationJournal.record(
                "sync.waitForFiles", .failed, durationMs: waitedMs,
                ["files": "\(files.count)", "error": (error as NSError).code == NSUserCancelledError ? "timeout" : "\(error)"])
            Log.warning(
                "[WorkspaceSync] iCloud still held \(files.count) list(s) after \(Int(waitedMs)) ms; the pass reads them anyway: \(error.localizedDescription)",
                category: .vectorDB)
            return
        }
        VerificationJournal.record(
            "sync.waitForFiles", .ok, durationMs: waitedMs, ["files": "\(files.count)", "roots": "\(roots.count)"])
        if waitedMs > 500 {
            Log.info(
                "[WorkspaceSync] Waited \(Int(waitedMs)) ms off the main thread for iCloud to release \(files.count) file(s) before the pass",
                category: .vectorDB)
        }
    }

    /// iCloud's numbered copies of the app's own files that belong to no library and have no original beside them
    /// (5.8): `transcript_<library id> 2.json`, `vector_database_<library id>_vectors 3.bin` and the like.
    ///
    /// Why: on the owner's iCloud on 2026-11-03 there were 497, every one for a library in neither device's list and
    /// none with an original, so nothing could read them. Earlier versions wrote these files without coordination, so
    /// two devices writing at once left a copy (the newest was from 2026-09-10, since that was fixed), and deleting a
    /// library removed its files but never their copies. A copy whose library still exists, or whose original is still
    /// there, could hold something the original lacks and is kept.
    nonisolated static func orphanedConflictCopies(
        in root: URL, libraryIds: Set<UUID>, fileManager: FileManager = .default
    ) -> [URL] {
        // With no library known on either side the lists weren't read, and every library would look deleted.
        guard !libraryIds.isEmpty,
            let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else {
            return []
        }
        let pattern = #"^(chat_history|transcript|conversation_memory|vector_database)_([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})(_meta|_vectors|_norms)? [0-9]+\.(json|bin)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return items.filter { url in
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            guard let match = regex.firstMatch(in: name, range: range),
                let idRange = Range(match.range(at: 2), in: name), let id = UUID(uuidString: String(name[idRange])),
                !libraryIds.contains(id)
            else { return false }
            // The original is the name without iCloud's number: "transcript_<id>.json".
            let original = name.replacingOccurrences(of: #" [0-9]+\.(json|bin)$"#, with: ".$1", options: .regularExpression)
            // An original iCloud has evicted is still there, as its placeholder ".transcript_<id>.json.icloud".
            return !fileManager.fileExists(atPath: root.appendingPathComponent(original).path)
                && !fileManager.fileExists(atPath: root.appendingPathComponent(".\(original).icloud").path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Removes `orphanedConflictCopies` from the iCloud workspace, off the main thread (5.8). Nothing in the app reads
    /// or writes a file with iCloud's number in its name, so this can't race the app's own writes. Each run's count
    /// goes to the trace and, in a development build, the event journal.
    @concurrent nonisolated static func removeOrphanedConflictCopies(in root: URL, libraryIds: Set<UUID>) async {
        let copies = orphanedConflictCopies(in: root, libraryIds: libraryIds)
        guard !copies.isEmpty else { return }
        var removed = 0
        var failed = 0
        for url in copies {
            do {
                try coordinatedRemoveItem(at: url)
                removed += 1
            } catch {
                failed += 1
            }
        }
        VerificationJournal.record(
            "sync.orphanedCopiesRemoved", failed == 0 ? .ok : .failed, ["removed": "\(removed)", "failed": "\(failed)"])
        Log.info(
            "[WorkspaceSync] Removed \(removed) of iCloud's numbered copies of files from libraries that no longer exist"
                + (failed > 0 ? "; \(failed) could not be removed and are tried again next pass" : ""),
            category: .vectorDB)
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

        var wrote = false

        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSourceURL, coordinatedDestinationURL in
            do {
                wrote = try replaceItemIfDifferent(at: coordinatedDestinationURL, withCopyOf: coordinatedSourceURL)
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

        if wrote,
           destination.path.hasPrefix(OpenIntelligenceRuntimePaths.applicationSupportRoot().path),
           !WorkspaceSyncService.isSyncWriteInProgress {
            NotificationCenter.default.post(name: .localWorkspaceDidChange, object: nil)
        }
    }

    /// Puts a copy of `source` at `destination` unless `destination` already holds the same bytes,
    /// and says whether it wrote (5.7). Call it inside a coordinated write of `destination`.
    ///
    /// Through 5.6 every sync pass deleted the destination and copied the source in again, whether
    /// or not anything had changed, so each library's chat history, transcript and conversation
    /// memory went up to iCloud again on every pass from every device. Two devices doing that at
    /// once is how iCloud ends up keeping both versions as "chat_history_<id> 2.json": on
    /// 2026-10-14 the owner's container held 500 such copies, all in the six per-library file
    /// families. An unchanged file is now left alone, and a changed one is replaced in place
    /// (`replaceItemAt`), so it keeps its identity instead of being deleted and created again. The
    /// result keeps the source's modification date, as the old delete-and-copy did (measured
    /// 2026-10-14 with a probe of both), so every newest-wins choice that reads it decides as before.
    nonisolated static func replaceItemIfDifferent(at destination: URL, withCopyOf source: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.copyItem(at: source, to: destination)
            return true
        }
        if fileManager.contentsEqual(atPath: source.path, andPath: destination.path) {
            return false
        }
        let staging: URL
        do {
            staging = try fileManager.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        } catch {
            // No replacement folder on this volume: fall back to what every earlier build did.
            try fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: source, to: destination)
            return true
        }
        defer { try? fileManager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(destination.lastPathComponent)
        try fileManager.copyItem(at: source, to: staged)
        _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        return true
    }

    /// Replaces a vector store's files in iCloud with the ones in `staged`, under one coordinated
    /// claim on all of them (5.7), so neither iCloud nor another reader on this device sees a mix
    /// of old and new files. A file missing from `staged` is removed. `destinations[i]` takes
    /// `staged[i]`.
    ///
    /// Through 5.6 sync wrote a store into iCloud by opening it there, clearing it (which deletes
    /// its files) and writing new ones, with no coordination, so iCloud could upload a store whose
    /// vectors and passages came from different moments, and a device that read it got a store
    /// that loads empty.
    nonisolated static func coordinatedReplaceItems(at destinations: [URL], with staged: [URL]) async throws {
        precondition(destinations.count == staged.count)
        let intents = destinations.map { NSFileAccessIntent.writingIntent(with: $0, options: .forReplacing) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let queue = OperationQueue()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(with: intents, queue: queue) { coordinationError in
                if let coordinationError {
                    continuation.resume(throwing: coordinationError)
                    return
                }
                let fileManager = FileManager.default
                do {
                    for (intent, source) in zip(intents, staged) {
                        let destination = intent.url
                        if fileManager.fileExists(atPath: source.path) {
                            if fileManager.fileExists(atPath: destination.path) {
                                _ = try fileManager.replaceItemAt(destination, withItemAt: source)
                            } else {
                                try fileManager.moveItem(at: source, to: destination)
                            }
                        } else if fileManager.fileExists(atPath: destination.path) {
                            try fileManager.removeItem(at: destination)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// How many iCloud conflict copies of the per-library files sit in `root`: names such as
    /// "chat_history_<id> 2.json" or "vector_database_<id>_vectors 3.bin", which iCloud makes when
    /// two devices change one file at the same time. The app reads none of them. Logged once a pass
    /// so a device session can show whether a build still adds them (5.7).
    nonisolated static func conflictCopyCount(in root: URL) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return 0 }
        return names.filter(isConflictCopyName).count
    }

    nonisolated static func isConflictCopyName(_ name: String) -> Bool {
        let families = ["chat_history_", "transcript_", "conversation_memory_", "vector_database_"]
        guard families.contains(where: { name.hasPrefix($0) }) else { return false }
        let stem = (name as NSString).deletingPathExtension
        guard let space = stem.lastIndex(of: " ") else { return false }
        let suffix = stem[stem.index(after: space)...]
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    nonisolated static func readJSONIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try coordinatedReadData(from: url)
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try coordinatedWriteData(data, to: url)
    }

    nonisolated static func resolveUbiquityContainerURL() async -> URL? {
        await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
    }

    nonisolated static func ensureDeviceIdentifier(in defaults: UserDefaults) {
        if defaults.string(forKey: deviceIdentifierDefaultsKey) == nil {
            defaults.set(UUID().uuidString, forKey: deviceIdentifierDefaultsKey)
        }
    }
}
