//
//  PendingDocumentRemovalTests.swift
//  OpenIntelligenceTests
//
//  A deletion made in the app can be undone for a few seconds (5.7): the documents leave the list at once, an
//  undo puts them back where they were, and the removal runs when the seconds end, when the app goes to the
//  background, or at the next launch if the app ended first. Runs on an engine of its own, in the app the suite
//  runs in, with documents that are only in that engine's list. Not covered here: going to the background, Delete
//  Everywhere's iCloud step, the Delete Documents action, and a rebuild reaching a pending document.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class PendingDocumentRemovalTests: XCTestCase {
    private var engine: RAGService!
    private var library: UUID!

    override func setUp() async throws {
        engine = RAGService()
        // The engine applies the list it read from disk in a task of its own. Waiting lets that happen first,
        // so it does not replace the documents a test adds.
        try await Task.sleep(for: .milliseconds(300))
        library = engine.containerService.activeContainerId
    }

    override func tearDown() async throws {
        await engine.commitPendingRemovals()
        engine = nil
    }

    private func addDocuments(_ names: [String]) -> [Document] {
        let added = names.map { name in
            Document(
                filename: "\(name)-\(UUID().uuidString.prefix(6)).txt",
                fileURL: URL(fileURLWithPath: "/tmp/\(name).txt"), contentType: .text, totalChunks: 3,
                containerId: library)
        }
        engine.documents.append(contentsOf: added)
        return added
    }

    /// Takes documents a test added and left in the list out of it again.
    private func forget(_ added: [Document]) {
        let ids = Set(added.map(\.id))
        engine.documents.removeAll { ids.contains($0.id) }
        engine.syncContainerStats(for: library)
    }

    private func tombstoned(_ id: UUID) -> Bool {
        let url = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        guard let data = try? Data(contentsOf: url), let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return false }
        return ids.contains(id.uuidString)
    }

    func testADeletionLeavesTheListAtOnceAndUndoPutsItBackInPlace() throws {
        let added = addDocuments(["lease", "deposit", "keys"])
        addTeardownBlock { @MainActor in self.forget(added) }
        let order = engine.documents.map(\.id)
        let passages = engine.totalChunksStored

        let id = try XCTUnwrap(engine.scheduleRemoval(of: [added[1]], window: .seconds(60)))

        XCTAssertFalse(engine.documents.contains { $0.id == added[1].id }, "out of the list at once")
        XCTAssertEqual(engine.pendingRemovals.map(\.id), [id])
        XCTAssertEqual(engine.pendingRemovals.first?.summary, "Deleted “\(added[1].filename)”")
        XCTAssertEqual(engine.totalChunksStored, passages - 3)
        XCTAssertTrue(PendingDocumentRemovalLedger.allIds().contains(added[1].id), "recorded in case the app ends")

        XCTAssertTrue(engine.undoRemoval(id))
        XCTAssertEqual(engine.documents.map(\.id), order, "back where it was")
        XCTAssertEqual(engine.totalChunksStored, passages)
        XCTAssertTrue(engine.pendingRemovals.isEmpty)
        XCTAssertFalse(PendingDocumentRemovalLedger.allIds().contains(added[1].id))
        XCTAssertFalse(engine.undoRemoval(id), "an undo is done once")
        XCTAssertFalse(tombstoned(added[1].id), "nothing was removed")
    }

    func testTheRemovalRunsWhenItsSecondsEnd() async throws {
        let added = addDocuments(["warranty"])
        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .milliseconds(200)))

        // Until it has finished, not only left the waiting list: the removal runs in a task of its own.
        let deadline = Date().addingTimeInterval(5)
        while engine.hasUnfinishedRemovals, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        XCTAssertFalse(engine.hasUnfinishedRemovals, "the removal ran")
        XCTAssertTrue(tombstoned(added[0].id), "removed for good")
        XCTAssertFalse(engine.undoRemoval(id), "too late to undo")
        XCTAssertFalse(engine.documents.contains { $0.id == added[0].id })
    }

    func testRunningARemovalSubtractsItsPassagesOnceAndEndsTheAppsUndo() async throws {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let added = addDocuments(["manual"])
        let passages = engine.totalChunksStored

        undoManager.beginUndoGrouping()
        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .seconds(60), undoManager: undoManager))
        undoManager.endUndoGrouping()
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(undoManager.undoActionName, "Delete Document")

        let ran = await engine.commitRemoval(id)

        XCTAssertTrue(ran)
        XCTAssertTrue(tombstoned(added[0].id))
        XCTAssertEqual(engine.totalChunksStored, passages - 3, "subtracted when it left the list, and not again")
        XCTAssertFalse(undoManager.canUndo, "the app's Undo no longer offers a deletion that has run")
        let ranAgain = await engine.commitRemoval(id)
        XCTAssertFalse(ranAgain)
    }

    func testTheAppsUndoPutsTheDocumentBack() throws {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let added = addDocuments(["receipt"])
        addTeardownBlock { @MainActor in self.forget(added) }

        undoManager.beginUndoGrouping()
        engine.scheduleRemoval(of: added, window: .seconds(60), undoManager: undoManager)
        undoManager.endUndoGrouping()
        undoManager.undo()

        XCTAssertTrue(engine.documents.contains { $0.id == added[0].id })
        XCTAssertTrue(engine.pendingRemovals.isEmpty)
        XCTAssertFalse(tombstoned(added[0].id))
    }

    func testGoingToTheBackgroundRunsEveryPendingRemoval() async throws {
        let added = addDocuments(["first", "second"])
        engine.scheduleRemoval(of: [added[0]], window: .seconds(60))
        engine.scheduleRemoval(of: [added[1]], window: .seconds(60))
        XCTAssertEqual(engine.pendingRemovals.count, 2)
        XCTAssertEqual(engine.pendingRemovals.last?.summary, "Deleted “\(added[1].filename)”")

        await engine.commitPendingRemovals()

        XCTAssertTrue(engine.pendingRemovals.isEmpty)
        XCTAssertTrue(tombstoned(added[0].id))
        XCTAssertTrue(tombstoned(added[1].id))
    }

    func testAReloadInTheUndoSecondsLeavesTheDocumentOut() async throws {
        let added = addDocuments(["reload"])
        await engine.saveDocumentsToDisk()
        let engine = self.engine!
        addTeardownBlock { @MainActor in try? await engine.removeDocument(added[0]) }
        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .seconds(60)))

        engine.reloadWorkspaceData()

        XCTAssertFalse(engine.documents.contains { $0.id == added[0].id }, "a reload does not show it again")
        XCTAssertTrue(engine.undoRemoval(id))
        XCTAssertEqual(engine.documents.filter { $0.id == added[0].id }.count, 1, "back, once")
    }

    func testARemovalAlreadyRunningIsWaitedFor() async throws {
        let added = addDocuments(["running"])
        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .seconds(60)))
        let engine = self.engine!
        let started = Task { @MainActor in await engine.commitRemoval(id) }
        await Task.yield()

        await engine.commitPendingRemovals()

        XCTAssertFalse(engine.isRemovalPending(added[0].id), "the removal had finished when this returned")
        XCTAssertFalse(engine.hasUnfinishedRemovals)
        _ = await started.value
        XCTAssertTrue(tombstoned(added[0].id))
    }

    func testAWaitingRemovalCountsAsPendingUntilItRunsOrIsUndone() throws {
        let added = addDocuments(["pending"])
        addTeardownBlock { @MainActor in self.forget(added) }
        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .seconds(60)))
        XCTAssertTrue(engine.isRemovalPending(added[0].id), "a rebuild skips it (`reembedDocuments`)")
        XCTAssertTrue(engine.undoRemoval(id))
        XCTAssertFalse(engine.isRemovalPending(added[0].id))
    }

    func testShortcutsNoLongerListAPendingDocument() async throws {
        let added = addDocuments(["listed"])
        await engine.saveDocumentsToDisk()
        let engine = self.engine!
        addTeardownBlock { @MainActor in try? await engine.removeDocument(added[0]) }
        XCTAssertTrue(OIDocumentEntityQuery.loadDocumentRecords().contains { $0.id == added[0].id })

        let id = try XCTUnwrap(engine.scheduleRemoval(of: added, window: .seconds(60)))
        XCTAssertFalse(OIDocumentEntityQuery.loadDocumentRecords().contains { $0.id == added[0].id })

        XCTAssertTrue(engine.undoRemoval(id))
        XCTAssertTrue(OIDocumentEntityQuery.loadDocumentRecords().contains { $0.id == added[0].id })
    }

    func testLaunchRemovesWhatAnEarlierRunLeftPending() async throws {
        let added = addDocuments(["left-pending"])
        await engine.saveDocumentsToDisk()
        engine.documents.removeAll { $0.id == added[0].id }
        let ledger = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: ledger) }
        try JSONEncoder().encode(["an earlier run": [added[0].id.uuidString]]).write(to: ledger)

        await engine.removeDocumentsLeftPending(ledgerURL: ledger, force: true)

        XCTAssertTrue(tombstoned(added[0].id), "removed for good")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledger.path), "and forgotten")
    }

    func testALedgerThatCannotBeWrittenIsDeleted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let undone = UUID()
        let other = UUID()
        PendingDocumentRemovalLedger.add([undone, other], at: url)

        PendingDocumentRemovalLedger.remove([undone], at: url, writer: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "an id left in it would hide a document that was put back")
    }

    func testNothingIsScheduledForADocumentNotInTheList() {
        let gone = Document(filename: "gone.txt", fileURL: URL(fileURLWithPath: "/tmp/gone.txt"), contentType: .text)
        XCTAssertNil(engine.scheduleRemoval(of: [gone]))
        XCTAssertTrue(engine.pendingRemovals.isEmpty)
    }

    func testTheLedgerKeepsEachRunsRemovalsApart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let mine = UUID()
        let earlier = UUID()
        PendingDocumentRemovalLedger.add([mine], at: url)
        // An earlier run's entry, as that run wrote it.
        var runs = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
        runs["an earlier run"] = [earlier.uuidString]
        try JSONEncoder().encode(runs).write(to: url)

        XCTAssertEqual(PendingDocumentRemovalLedger.allIds(at: url), [mine, earlier])
        XCTAssertEqual(PendingDocumentRemovalLedger.earlierRunIds(at: url), [earlier])
        PendingDocumentRemovalLedger.remove([mine, earlier], at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an empty ledger is no file")
    }
}
