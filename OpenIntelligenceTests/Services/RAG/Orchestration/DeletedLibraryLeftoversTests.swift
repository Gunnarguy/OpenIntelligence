//
//  DeletedLibraryLeftoversTests.swift
//  OpenIntelligenceTests
//
//  Nothing lands in the open library because the library it named was deleted (5.8). Through the first 5.8 builds
//  `resolveImportLibrary` gave an import for a library that was no longer listed to the open library, with nothing
//  logged; on the owner's Mac the sample guides asked for deleted library BDB0BCA5 went to General on 2026-11-14 and to
//  Library 4 on 2026-11-18. A deleted library's document records and queued imports also outlived it. These run on an
//  engine of their own, in the app the suite runs in, on a paid plan for the length of the test (the free plan allows
//  one library), like `ImportTargetLibraryTests`, with the journal written to a file of the test's own. The suite's
//  queue file is put back after the test that writes it.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class DeletedLibraryLeftoversTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?
    private var savedJournalURL: (() -> URL?)?
    private var journalURL: URL!

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        savedJournalURL = VerificationJournal.fileURL
        journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deleted-library-leftovers-\(UUID().uuidString).jsonl")
        let url = journalURL
        VerificationJournal.fileURL = { url }
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
        if let savedJournalURL { VerificationJournal.fileURL = savedJournalURL }
        VerificationJournal.fileURLIsReplaced = false
        try? FileManager.default.removeItem(at: journalURL)
    }

    // MARK: - Helpers

    /// An engine whose documents have been read from disk.
    private func loadedEngine() async throws -> RAGService {
        let engine = RAGService()
        for _ in 0..<100 where !engine.hasAppliedLoadedDocuments {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(engine.hasAppliedLoadedDocuments, "the engine read its documents within ten seconds")
        return engine
    }

    /// A library made and then deleted on this device: its id is in `ContainerService.deletedContainerIds`.
    private func deletedLibrary(in engine: RAGService) throws -> UUID {
        let library = try engine.containerService.createContainer(
            name: "Deleted leftovers \(UUID().uuidString.prefix(8))")
        engine.containerService.deleteContainer(id: library.id)
        XCTAssertFalse(engine.containerService.containers.contains { $0.id == library.id })
        XCTAssertTrue(ContainerService.deletedContainerIds().contains(library.id))
        return library.id
    }

    private func note(_ text: String) throws -> (url: URL, name: String) {
        let name = "deleted-leftovers-\(UUID().uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data(text.utf8).write(to: url)
        return (url, name)
    }

    private func journalled(_ event: String) -> [[String: Any]] {
        VerificationJournal.readAll().filter { $0["e"] as? String == event }
    }

    private func record(in library: UUID?) -> Document {
        let name = "leftover-record-\(UUID().uuidString.prefix(8)).txt"
        return Document(
            filename: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), contentType: .text, containerId: library)
    }

    private static var localDeletedDocumentsURL: URL {
        AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
    }

    private static func localDeletedDocumentIds() -> Set<String> {
        guard let data = try? Data(contentsOf: localDeletedDocumentsURL),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private static func savedDocumentIds() -> Set<UUID> {
        guard let data = try? Data(contentsOf: AppSupportPaths.documentsMetadataURL()),
            let documents = try? JSONDecoder().decode([Document].self, from: data)
        else { return [] }
        return Set(documents.map(\.id))
    }

    // MARK: - (a) An import for a library that is gone

    func testAnImportQueuedForADeletedLibraryFailsAndTheOpenLibraryGetsNothing() async throws {
        let engine = try await loadedEngine()
        let open = engine.containerService.activeContainerId
        let gone = try deletedLibrary(in: engine)
        let openBefore = engine.documentsForContainer(open).count
        let (url, name) = try note("The quillberry lease for the deleted test library ends in April.")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.filename.hasPrefix(name) {
                try? await engine.removeDocument(document)
            }
        }

        let result = await engine.ingestDocuments([url], containerId: gone)

        XCTAssertEqual(result.successCount, 0, "nothing was imported")
        XCTAssertEqual(result.failureCount, 1, "the import failed")
        XCTAssertFalse(engine.documents.contains { $0.filename.hasPrefix(name) }, "the note is in no library")
        XCTAssertEqual(engine.documentsForContainer(open).count, openBefore, "the open library got nothing")
        XCTAssertEqual(engine.containerService.activeContainerId, open, "the open library did not change")
        let gones = journalled("import.libraryGone")
        XCTAssertEqual(gones.count, 1, "the refusal is journalled")
        let fields = gones.first?["f"] as? [String: String]
        XCTAssertEqual(fields?["library"], VerificationJournal.anon(gone), "with the library anonymised")
        XCTAssertEqual(fields?["knownDeleted"], "true")
        XCTAssertFalse(
            engine.ingestionItems.contains { $0.containerId == gone && !$0.stage.isTerminal },
            "the queue does not keep or retry it")
    }

    /// Unchanged by the fix (a regression guard, so it passes before it too): no library named means the open one.
    func testANilLibraryStillMeansTheOpenOne() async throws {
        let engine = try await loadedEngine()
        let expected = try XCTUnwrap(
            engine.containerService.libraryForOwnFiles(requested: engine.containerService.activeContainerId))
        let (url, name) = try note("The quillberry porch light for the test flat is on a timer.")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.filename.hasPrefix(name) {
                try? await engine.removeDocument(document)
            }
        }

        let result = await engine.ingestDocuments([url], containerId: nil)

        XCTAssertEqual(result.successCount, 1)
        let imported = engine.documents.filter { $0.filename.hasPrefix(name) }
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.containerId, expected, "the note is in the open library")
    }

    /// A rebuild whose library is deleted while it runs (`reembedDocuments`, the full re-import path): it stops before
    /// the next document's passages are cleared, the documents from there on keep their passages, their items say the
    /// library was deleted, and the open library gets none of them.
    func testARebuildStopsWhenItsLibraryIsDeletedPartWay() async throws {
        let engine = try await loadedEngine()
        let open = engine.containerService.activeContainerId
        let library = try engine.containerService.createContainer(
            name: "Rebuild then delete \(UUID().uuidString.prefix(8))")
        let notes = try [
            note("The quillberry first rebuild note lists the boiler service in March."),
            note("The quillberry second rebuild note lists the window cleaning in May."),
            note("The quillberry third rebuild note lists the gutter check in October."),
        ]
        addTeardownBlock { @MainActor in
            for document in engine.documents where notes.contains(where: { document.filename.hasPrefix($0.name) }) {
                try? await engine.removeDocument(document)
            }
            engine.ingestionItems.removeAll { $0.containerId == library.id }
            engine.containerService.deleteContainer(id: library.id)
        }
        let imported = await engine.ingestDocuments(notes.map(\.url), containerId: library.id)
        XCTAssertEqual(imported.successCount, 3)
        engine.clearPendingReembeds()
        let documents = engine.documents.filter { $0.containerId == library.id }
        XCTAssertEqual(documents.count, 3)
        // Another chunking window than the one the notes were imported with, so each is read and imported again (the
        // path that clears a document's passages before re-adding it).
        var changed = try XCTUnwrap(engine.containerService.containers.first { $0.id == library.id })
        changed.chunkingDirective = ChunkingDirective(
            source: .manual, strategy: "balanced", targetWordWindow: 97, overlapWords: 11)
        engine.containerService.updateContainer(changed)
        let store = await engine.dbFor(library.id)
        var passagesBefore: [UUID: Int] = [:]
        for document in documents {
            passagesBefore[document.id] = try await store.chunks(forDocument: document.id).count
            XCTAssertGreaterThan(passagesBefore[document.id] ?? 0, 0)
        }
        let openBefore = engine.documentsForContainer(open).count

        // Deleted as the second document's rebuild starts.
        try await engine.reembedDocuments(in: library.id, reason: "Deleted while rebuilding (test)") { progress in
            if progress.completed == 1, progress.total == 3 {
                engine.containerService.deleteContainer(id: library.id)
            }
        }

        let items = engine.ingestionItems.filter { $0.containerId == library.id && $0.metrics.isRebuild }
        XCTAssertEqual(items.filter { $0.stage == .complete }.count, 1, "the first document was rebuilt")
        let stopped = items.filter { $0.stage == .failed }
        XCTAssertEqual(stopped.count, 2, "the second and third are marked")
        XCTAssertTrue(stopped.allSatisfy { $0.detail == "Library deleted" })
        var untouched = 0
        for document in documents where stopped.contains(where: { $0.url == document.fileURL }) {
            let now = try await store.chunks(forDocument: document.id).count
            if now == passagesBefore[document.id] { untouched += 1 }
        }
        XCTAssertEqual(untouched, 2, "both documents after the deletion kept every passage")
        XCTAssertEqual(engine.documentsForContainer(open).count, openBefore, "the open library got nothing")
        XCTAssertFalse(
            engine.librariesNeedingIndexRebuild.contains(library.id), "a library deleted here is not offered a rebuild")
        XCTAssertEqual(journalled("rebuild.libraryGone").count, 1)
    }

    func testAddToLibraryNamingADeletedLibraryIsRefused() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let engine = IntentSupport.engine()
        let library = try engine.containerService.createContainer(name: "Add to deleted \(UUID().uuidString.prefix(8))")
        let entity = OILibraryEntityQuery.entity(for: library)
        engine.containerService.deleteContainer(id: library.id)
        let queuedBefore = engine.ingestionItems.count

        let add = AddToLibraryIntent()
        add.text = "The quillberry note for a library deleted before the shortcut ran."
        add.library = entity
        do {
            _ = try await add.perform()
            XCTFail("the action added to a library that no longer exists")
        } catch let error as OIIntentError {
            XCTAssertEqual(error.kind, .itemNotFound)
        }
        XCTAssertEqual(engine.ingestionItems.count, queuedBefore, "nothing was queued")
    }

    // MARK: - (b) Records of deleted libraries

    func testRecordsOfADeletedLibraryAreRemovedOnThisDeviceOnlyAndOthersAreKept() async throws {
        let engine = try await loadedEngine()
        let gone = try deletedLibrary(in: engine)
        let unknown = UUID()  // Not listed and not deleted here: a library that may not have arrived yet.
        let doomed = record(in: gone)
        let stranger = record(in: unknown)
        let homeless = record(in: nil)
        addTeardownBlock { @MainActor in
            for document in engine.documents where [stranger.id, homeless.id].contains(document.id) {
                try? await engine.removeDocument(document)
            }
        }
        engine.documents.append(contentsOf: [doomed, stranger, homeless])
        await engine.saveDocumentsToDisk()
        XCTAssertTrue(Self.savedDocumentIds().contains(doomed.id))

        let applied = await engine.reloadWorkspaceData().value

        XCTAssertTrue(applied, "the reload applied what it read")
        XCTAssertFalse(engine.documents.contains { $0.id == doomed.id }, "the deleted library's record is removed")
        XCTAssertTrue(engine.documents.contains { $0.id == stranger.id }, "an unknown library's record is kept")
        XCTAssertEqual(
            engine.documents.first { $0.id == stranger.id }?.containerId, unknown, "and keeps its library")
        XCTAssertTrue(engine.documents.contains { $0.id == homeless.id }, "a record with no library is untouched")
        XCTAssertNil(engine.documents.first { $0.id == homeless.id }?.containerId)
        let fields = journalled("library.orphanRecords").last?["f"] as? [String: String]
        XCTAssertNotNil(fields, "the leftovers are journalled")
        XCTAssertGreaterThanOrEqual(Int(fields?["removed"] ?? "") ?? 0, 1)
        XCTAssertGreaterThanOrEqual(Int(fields?["kept"] ?? "") ?? 0, 1)

        // Off this device's list on disk, and not recorded as deleted: `deleted_documents.json` is merged into the
        // shared folder, which would delete the document on every device.
        for _ in 0..<50 where Self.savedDocumentIds().contains(doomed.id) {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(Self.savedDocumentIds().contains(doomed.id), "the record is gone from this device's list")
        XCTAssertFalse(
            Self.localDeletedDocumentIds().contains(doomed.id.uuidString), "the record is not recorded as deleted")
    }

    // MARK: - (c) Queued imports of deleted libraries

    func testAWaitingItemOfADeletedLibraryIsPurgedAtReloadAndAFinishedOneStays() async throws {
        let engine = try await loadedEngine()
        let gone = try deletedLibrary(in: engine)
        let device = WorkspaceSyncService.currentDeviceID()
        let (url, _) = try note("The quillberry note queued for a library deleted before it ran.")
        // This device's, its lease run out (an import a relaunch interrupted).
        let waiting = IngestionItem(
            url: url, containerId: gone, leaseOwnerDeviceId: device, leaseExpiresAt: Date().addingTimeInterval(-60),
            stage: .paused, detail: "Paused after app restart")
        var failed = IngestionItem(
            url: url, containerId: gone, stage: .failed, detail: "Failed",
            errorMessage: RAGServiceError.importLibraryGone.localizedDescription)
        failed.finishedAt = Date()
        // Not this device's to retire: a tombstone would reach every device.
        let othersExpired = IngestionItem(
            url: url, containerId: gone, leaseOwnerDeviceId: "another-device-\(UUID().uuidString)",
            leaseExpiresAt: Date().addingTimeInterval(-60), stage: .paused, detail: "Paused")
        let neverLeased = IngestionItem(url: url, containerId: gone, stage: .paused, detail: "Paused")
        let ids = [waiting.id, failed.id, othersExpired.id, neverLeased.id]
        addTeardownBlock { @MainActor in
            engine.ingestionItems.removeAll { ids.contains($0.id) }
            engine.ingestionQueueTombstones.removeAll { ids.contains($0.id) }
        }
        engine.ingestionItems.append(contentsOf: [waiting, failed, othersExpired, neverLeased])

        engine.reloadWorkspaceData()
        for _ in 0..<100 where engine.ingestionItems.contains(where: { $0.id == waiting.id }) {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(
            engine.ingestionItems.contains { $0.id == waiting.id }, "this device's waiting item is gone from the queue")
        let tombstoned = Set(engine.ingestionQueueTombstones.map(\.id))
        XCTAssertTrue(tombstoned.contains(waiting.id), "with a tombstone, so iCloud loses it too")
        XCTAssertTrue(
            engine.ingestionItems.contains { $0.id == failed.id }, "the failed row stays on screen until it is pruned")
        for item in [othersExpired, neverLeased] {
            XCTAssertTrue(engine.ingestionItems.contains { $0.id == item.id }, "another device's or an unleased item stays")
            XCTAssertFalse(tombstoned.contains(item.id), "and gets no tombstone")
        }
    }

    /// An import named a library that is not listed and not deleted here: it waits, queued, and is not called deleted.
    func testAnImportForALibraryNotHereYetWaitsQueued() async throws {
        let engine = try await loadedEngine()
        let notYet = UUID()
        XCTAssertFalse(ContainerService.deletedContainerIds().contains(notYet))
        let (url, name) = try note("The quillberry note for a library still on its way from another device.")
        let ids = engine.enqueueDocuments([url], containerId: notYet)
        addTeardownBlock { @MainActor in
            for id in ids { engine.cancelIngestionItem(id) }
            engine.ingestionItems.removeAll { ids.contains($0.id) }
        }
        var item: IngestionItem?
        for _ in 0..<100 {
            item = engine.ingestionItems.first { ids.contains($0.id) }
            if item?.detail == RAGService.waitingForLibraryDetail, engine.ingestionTask == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertEqual(item?.stage, .queued, "the item stays queued")
        XCTAssertEqual(item?.detail, RAGService.waitingForLibraryDetail)
        XCTAssertNil(item?.leaseOwnerDeviceId, "and unleased")
        XCTAssertNil(engine.ingestionTask, "the queue doesn't take it again and again")
        XCTAssertFalse(engine.documents.contains { $0.filename.hasPrefix(name) }, "nothing was imported anywhere")
        XCTAssertEqual(journalled("import.libraryNotHereYet").count, 1)
        XCTAssertTrue(journalled("import.libraryGone").isEmpty, "it is not called deleted")
    }

    func testAddToLibraryNamingALibraryNotHereYetSaysSo() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let notYet = KnowledgeContainer(name: "Not here yet \(UUID().uuidString.prefix(8))")
        let add = AddToLibraryIntent()
        add.text = "The quillberry note for a library still on its way."
        add.library = OILibraryEntityQuery.entity(for: notYet)
        do {
            _ = try await add.perform()
            XCTFail("the action added to a library this device doesn't have")
        } catch let error as OIIntentError {
            XCTAssertEqual(error.kind, .itemNotFound)
            XCTAssertTrue(error.message.contains("isn't on this device yet"), error.message)
        }
    }

    /// The restore path: a saved queue holding items of a library deleted here, read with an empty queue in memory.
    func testRestoreTombstonesOnlyThisDevicesLeasedItemOfADeletedLibrary() async throws {
        let engine = try await loadedEngine()
        let gone = try deletedLibrary(in: engine)
        let queueURL = AppSupportPaths.ingestionQueueURL()
        let savedQueue = try? Data(contentsOf: queueURL)
        let savedItems = engine.ingestionItems
        let savedTombstones = engine.ingestionQueueTombstones
        addTeardownBlock { @MainActor in
            if let savedQueue {
                try? savedQueue.write(to: queueURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: queueURL)
            }
            engine.ingestionItems = savedItems
            engine.ingestionQueueTombstones = savedTombstones
        }
        XCTAssertNil(engine.ingestionTask, "no import is running on the test's engine")
        let (url, _) = try note("The quillberry note saved in the queue for a library deleted here.")
        let ours = IngestionItem(
            url: url, containerId: gone, leaseOwnerDeviceId: WorkspaceSyncService.currentDeviceID(),
            leaseExpiresAt: Date().addingTimeInterval(-60), stage: .queued)
        let neverLeased = IngestionItem(url: url, containerId: gone, stage: .queued)
        let theirs = IngestionItem(
            url: url, containerId: gone, leaseOwnerDeviceId: "another-device-\(UUID().uuidString)",
            leaseExpiresAt: Date().addingTimeInterval(3_600), stage: .embedding, detail: "Embedding")
        let state = RAGService.PersistedIngestionQueueState(
            items: [ours, neverLeased, theirs],
            contexts: [
                RAGService.PersistedIngestionContext(id: ours.id, context: .userInitiated),
                RAGService.PersistedIngestionContext(id: neverLeased.id, context: .userInitiated),
                RAGService.PersistedIngestionContext(id: theirs.id, context: .userInitiated),
            ],
            tombstones: [], updatedAt: Date())
        try JSONEncoder().encode(state).write(to: queueURL, options: .atomic)
        engine.ingestionItems = []

        await engine.restorePersistedIngestionQueueIfNeeded()

        let tombstoned = Set(engine.ingestionQueueTombstones.map(\.id))
        XCTAssertTrue(tombstoned.contains(ours.id), "this device's item of the deleted library is retired for good")
        XCTAssertFalse(tombstoned.contains(theirs.id), "an item another device holds a live lease on is not")
        XCTAssertFalse(tombstoned.contains(neverLeased.id), "nor one never leased")
        XCTAssertFalse(engine.ingestionItems.contains { [ours.id, theirs.id].contains($0.id) }, "neither is restored")
    }

    // MARK: - (d) Deleting a library already gone from the list

    func testALibraryAlreadyGoneFromTheListIsStillCleanedUpAndRemembered() async throws {
        let engine = try await loadedEngine()
        // A library this device's list no longer holds (an iCloud pass rewrote the list without it) and has not
        // recorded as deleted.
        let unlisted = KnowledgeContainer(name: "Unlisted \(UUID().uuidString.prefix(8))")
        XCTAssertFalse(engine.containerService.containers.contains { $0.id == unlisted.id })
        XCTAssertFalse(ContainerService.deletedContainerIds().contains(unlisted.id))
        let leftover = record(in: unlisted.id)
        let (url, _) = try note("The quillberry note queued for a library that is already gone.")
        let item = IngestionItem(url: url, containerId: unlisted.id, stage: .paused, detail: "Paused")
        addTeardownBlock { @MainActor in
            engine.ingestionItems.removeAll { $0.id == item.id }
            for document in engine.documents where document.id == leftover.id {
                try? await engine.removeDocument(document)
            }
        }
        engine.documents.append(leftover)
        engine.ingestionItems.append(item)

        let suite = "DeletedLibraryLeftoversTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outcome = await LibraryDeletion.delete(
            unlisted, ragService: engine, containerService: engine.containerService,
            workspaceSyncService: WorkspaceSyncService(defaults: defaults))

        XCTAssertEqual(outcome, .deleted)
        XCTAssertTrue(
            ContainerService.deletedContainerIds().contains(unlisted.id), "the library is remembered as deleted")
        XCTAssertFalse(engine.documents.contains { $0.id == leftover.id }, "its record is removed")
        XCTAssertFalse(engine.ingestionItems.contains { $0.id == item.id }, "its queued import is removed")
        let fields = journalled("library.deleteLocal").last?["f"] as? [String: String]
        XCTAssertEqual(fields?["listed"], "false")
        XCTAssertEqual(fields?["library"], VerificationJournal.anon(unlisted.id))
    }

    /// The rule `deleteContainer` and `LibraryDeletion` share, for the one-own-library case. Arranging that on the
    /// suite's host would mean deleting the libraries the test simulator holds, so the rule is checked as the function
    /// both call. Through the first 5.8 builds an unlisted library with one own library listed was not remembered, and
    /// `LibraryDeletion` emptied a listed own library that `deleteContainer` then kept.
    func testTheDeleteRuleForOneOwnLibrary() {
        // One own library and the guide library: an unlisted library may go (and is remembered).
        XCTAssertTrue(ContainerService.mayDelete(listed: false, libraries: 2, isGuide: false, ownLibraries: 1))
        // The own library itself may not, so `LibraryDeletion` refuses before emptying it.
        XCTAssertFalse(ContainerService.mayDelete(listed: true, libraries: 2, isGuide: false, ownLibraries: 1))
        // The guide library may.
        XCTAssertTrue(ContainerService.mayDelete(listed: true, libraries: 2, isGuide: true, ownLibraries: 1))
        // The last library of all may not.
        XCTAssertFalse(ContainerService.mayDelete(listed: true, libraries: 1, isGuide: false, ownLibraries: 1))
        // Two own libraries: either may go.
        XCTAssertTrue(ContainerService.mayDelete(listed: true, libraries: 2, isGuide: false, ownLibraries: 2))
    }
}
