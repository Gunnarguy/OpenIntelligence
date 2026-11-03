//
//  WatchedFolderTests.swift
//  OpenIntelligenceTests
//
//  Watched folders (5.8): what a check decides to do, then the whole path through a real folder and the app's
//  import queue. Choosing a folder in the system picker, iCloud Drive's placeholders and a Mac's bookmark need a
//  device.
//

import XCTest

@testable import OpenIntelligence

final class WatchedFolderChangesTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private let url = URL(fileURLWithPath: "/tmp/a.txt")

    private func file(_ path: String, size: Int64 = 10, modified: Date? = nil, downloaded: Bool = true) -> WatchedFolderFile {
        WatchedFolderFile(relativePath: path, url: url, size: size, modified: modified ?? day, isDownloaded: downloaded)
    }

    private func seen(size: Int64 = 10, modified: Date? = nil) -> WatchedFolder.SeenFile {
        WatchedFolder.SeenFile(size: size, modified: modified ?? day, hash: "h", documentId: UUID())
    }

    func testAnUnchangedFileCostsNothing() {
        let result = WatchedFolderChanges.decide(found: [file("a.txt")], seen: ["a.txt": seen()], room: 5)
        XCTAssertEqual(result, .init())
    }

    func testNewAndChangedFilesAreRead() {
        let result = WatchedFolderChanges.decide(
            found: [file("new.txt"), file("bigger.txt", size: 11), file("later.txt", modified: day.addingTimeInterval(9))],
            seen: ["bigger.txt": seen(), "later.txt": seen()], room: 5)
        XCTAssertEqual(result.toRead.map(\.relativePath), ["new.txt", "bigger.txt", "later.txt"])
    }

    func testAFileDeletedFromTheFolderAsksForNothing() {
        let result = WatchedFolderChanges.decide(found: [], seen: ["gone.txt": seen()], room: 5)
        XCTAssertEqual(result, .init())
    }

    func testFilesOverThePlanLimitWaitAndAreCounted() {
        let result = WatchedFolderChanges.decide(found: [file("1"), file("2"), file("3")], seen: [:], room: 2)
        XCTAssertEqual(result.toRead.count, 2)
        XCTAssertEqual(result.overLimit, 1)
        XCTAssertEqual(WatchedFolderChanges.decide(found: [file("1")], seen: [:], room: -3).overLimit, 1)
    }

    func testAFileStillDownloadingWaitsAndTakesNoRoom() {
        let result = WatchedFolderChanges.decide(found: [file("cloud", downloaded: false), file("here")], seen: [:], room: 1)
        XCTAssertEqual(result.waitingForDownload.map(\.relativePath), ["cloud"])
        XCTAssertEqual(result.toRead.map(\.relativePath), ["here"])
    }

    func testTheNoteSaysWhatIsHeldBack() {
        XCTAssertNil(WatchedFolderChanges.note(overLimit: 0, waitingForDownload: 0))
        XCTAssertEqual(
            WatchedFolderChanges.note(overLimit: 2, waitingForDownload: 1),
            "2 files are over your plan's document limit. 1 file is still downloading.")
        XCTAssertEqual(
            WatchedFolderChanges.note(overLimit: 0, waitingForDownload: 0, failed: 2, unreadable: 1),
            "1 file can't be read right now. 2 files couldn't be imported, and will be tried again if changed.")
    }
}

@MainActor
final class WatchedFolderPathTests: XCTestCase {
    private var original: (() -> URL)!
    private var list: URL!
    private var folder: URL!
    private let folderName = "Watch test \(UUID().uuidString.prefix(8))"

    override func setUp() async throws {
        original = WatchedFolderStore.fileURL
        list = FileManager.default.temporaryDirectory.appendingPathComponent("watched-\(UUID().uuidString).json")
        let temporary = list!
        WatchedFolderStore.fileURL = { temporary }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: list)
        try? FileManager.default.removeItem(at: folder)
        WatchedFolderStore.fileURL = original
    }

    private func write(_ text: String, to file: String, modified: Date? = nil) throws {
        let url = folder.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    private func document(_ prefix: String, on engine: RAGService) -> Document? {
        engine.documents.first { $0.filename.hasPrefix(prefix) }
    }

    private func waitFor(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("\(what) did not happen within a minute")
    }

    /// New file, unchanged file, changed file, deleted file, through a real folder and the import queue.
    func testAFolderKeepsALibraryUpToDate() async throws {
        let engine = IntentSupport.engine()
        let library = engine.containerService.activeContainerId
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: library)
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.filename.hasPrefix("watch-test-") {
                try? await engine.removeDocument(document)
            }
        }

        let early = Date(timeIntervalSince1970: 1_800_000_000)
        try write("The marigold note says the gate code is 4417.", to: "watch-test-note.txt", modified: early)
        try write("The second note sits in a subfolder.", to: "inner/watch-test-inner.txt")
        try write("Not a file the app imports.", to: "watch-test-skipped.xyzzy")
        try write("A hidden file.", to: ".watch-test-hidden.txt")
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the first import") {
            self.document("watch-test-note", on: engine) != nil && self.document("watch-test-inner", on: engine) != nil
        }
        XCTAssertNil(document("watch-test-skipped", on: engine))
        XCTAssertNil(document(".watch-test-hidden", on: engine))
        let first = try XCTUnwrap(document("watch-test-note", on: engine))
        XCTAssertEqual(first.containerId, library)

        // Nothing changed: nothing is queued, and the next check ties the files to their documents.
        var queued = Set(engine.ingestionItems.map(\.id))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertEqual(watcher.folders.first?.files["watch-test-note.txt"]?.documentId, first.id)
        XCTAssertTrue(Set(engine.ingestionItems.map(\.id)).isSubset(of: queued), "nothing changed, so nothing is queued")

        // The same bytes with a new date: no second document.
        let touched = early.addingTimeInterval(60)
        try FileManager.default.setAttributes(
            [.modificationDate: touched], ofItemAtPath: folder.appendingPathComponent("watch-test-note.txt").path)
        queued = Set(engine.ingestionItems.map(\.id))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(Set(engine.ingestionItems.map(\.id)).isSubset(of: queued), "the same bytes queue nothing")
        XCTAssertEqual(engine.documents.filter { $0.filename.hasPrefix("watch-test-note") }.count, 1)

        // New bytes: the new version comes in, and only then does the old one go.
        try write("The marigold note now says the gate code is 9921.", to: "watch-test-note.txt", modified: touched.addingTimeInterval(60))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(engine.documents.contains { $0.id == first.id }, "the old version stays until the new one is in")
        try await waitFor("the new version") {
            engine.documents.filter { $0.filename.hasPrefix("watch-test-note") }.count == 2
        }
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertFalse(engine.documents.contains { $0.id == first.id }, "the old version was replaced")
        XCTAssertEqual(engine.documents.filter { $0.filename.hasPrefix("watch-test-note") }.count, 1)

        // Deleted from the folder: it stays in the library.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("inner/watch-test-inner.txt"))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertNotNil(document("watch-test-inner", on: engine))
    }

    func testAtThePlanLimitNothingIsQueuedAndTheNoteSaysSo() async throws {
        let engine = IntentSupport.engine()
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)
        try write("Over the limit.", to: "watch-test-limit.txt")
        await watcher.check(engine: engine, documentLimit: engine.documents.count)
        XCTAssertNil(document("watch-test-limit", on: engine))
        XCTAssertEqual(watcher.folders.first?.note, "1 file is over your plan's document limit.")
        XCTAssertTrue(watcher.folders.first?.files.isEmpty ?? false, "a later check takes it when there is room")
    }

    func testAFolderThatIsGoneSaysSoAndKeepsTheRecord() async throws {
        let engine = IntentSupport.engine()
        let watcher = WatchedFolderService()
        let doomed = folder.appendingPathComponent("doomed", isDirectory: true)
        try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: true)
        try watcher.watch(doomed, library: engine.containerService.activeContainerId)
        try FileManager.default.removeItem(at: doomed)
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertEqual(watcher.folders.count, 1)
        XCTAssertNotNil(watcher.folders.first?.lastCheckedAt)
        XCTAssertEqual(watcher.folders.first?.note, "This folder can't be reached. Stop watching it and choose it again.")
    }

    private func removeTestDocuments(on engine: RAGService) {
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.filename.hasPrefix("watch-test-") {
                try? await engine.removeDocument(document)
            }
        }
    }

    /// The person imported these bytes themselves. The folder never owned that document, so a change to the file
    /// must leave it alone.
    func testEditingAFileNeverRemovesADocumentThePersonImported() async throws {
        let engine = IntentSupport.engine()
        removeTestDocuments(on: engine)
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)

        let text = "The saffron note was imported by hand \(UUID())."
        let handFile = FileManager.default.temporaryDirectory.appendingPathComponent("watch-test-by-hand.txt")
        try text.write(to: handFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: handFile) }
        let staged = try IntentSupport.copyIntoImports(handFile)
        _ = engine.enqueueDocuments([staged])
        try await waitFor("the hand import") { self.document("watch-test-by-hand", on: engine) != nil }
        let byHand = try XCTUnwrap(document("watch-test-by-hand", on: engine))

        let early = Date(timeIntervalSince1970: 1_800_000_000)
        try write(text, to: "watch-test-same-bytes.txt", modified: early)
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertEqual(watcher.folders.first?.files["watch-test-same-bytes.txt"]?.documentId, byHand.id)
        XCTAssertEqual(watcher.folders.first?.files["watch-test-same-bytes.txt"]?.ownsDocument, false)

        try write("The saffron note changed \(UUID()).", to: "watch-test-same-bytes.txt", modified: early.addingTimeInterval(60))
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the new file") { self.document("watch-test-same-bytes", on: engine) != nil }
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(engine.documents.contains { $0.id == byHand.id }, "the person's own document was removed")
    }

    /// Two files with the same bytes share one document, and it stays while either still names it.
    func testADocumentTwoFilesShareStaysWhenOneChanges() async throws {
        let engine = IntentSupport.engine()
        removeTestDocuments(on: engine)
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)

        let text = "The juniper note appears twice \(UUID())."
        let early = Date(timeIntervalSince1970: 1_800_000_000)
        try write(text, to: "watch-test-one.txt", modified: early)
        try write(text, to: "watch-test-two.txt", modified: early)
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the first import") { self.document("watch-test-", on: engine) != nil }
        await watcher.check(engine: engine, documentLimit: .max)
        let files = try XCTUnwrap(watcher.folders.first?.files)
        let shared = try XCTUnwrap(files["watch-test-one.txt"]?.documentId)
        XCTAssertEqual(files["watch-test-two.txt"]?.documentId, shared, "one document, not two")

        try write("The juniper note changed \(UUID()).", to: "watch-test-one.txt", modified: early.addingTimeInterval(60))
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the new version") {
            engine.documents.filter { $0.filename.hasPrefix("watch-test-") }.count == 2
        }
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(engine.documents.contains { $0.id == shared }, "the second file still names it")
    }

    /// A file deleted from the folder stays in the library, and a later file of that name is a new file.
    func testANewFileWithADeletedFilesNameLeavesTheKeptDocumentAlone() async throws {
        let engine = IntentSupport.engine()
        removeTestDocuments(on: engine)
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)

        try write("The first report \(UUID()).", to: "watch-test-report.txt")
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the import") { self.document("watch-test-report", on: engine) != nil }
        let kept = try XCTUnwrap(document("watch-test-report", on: engine))

        try FileManager.default.removeItem(at: folder.appendingPathComponent("watch-test-report.txt"))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertNil(watcher.folders.first?.files["watch-test-report.txt"], "a path no longer there is forgotten")

        try write("A different report \(UUID()).", to: "watch-test-report.txt")
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the second import") {
            engine.documents.filter { $0.filename.hasPrefix("watch-test-report") }.count == 2
        }
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(engine.documents.contains { $0.id == kept.id }, "the kept document was removed")
    }

    func testStopWatchingDuringACheckStaysStopped() async throws {
        let engine = IntentSupport.engine()
        let watcher = WatchedFolderService()
        let library = engine.containerService.activeContainerId
        try watcher.watch(folder, library: library)
        async let checking: Void = watcher.check(engine: engine, documentLimit: .max)
        watcher.stopWatching(library: library)
        await checking
        XCTAssertTrue(watcher.folders.isEmpty, "a check wrote back a folder that was stopped")
        XCTAssertTrue(WatchedFolderStore.load().isEmpty)
    }

    func testAFreePlanChecksNothing() async throws {
        let engine = IntentSupport.engine()
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)
        try write("Not on a free plan.", to: "watch-test-free.txt")
        await watcher.check(engine: engine)  // no plan known
        XCTAssertNil(watcher.folders.first?.lastCheckedAt)
        XCTAssertNil(document("watch-test-free", on: engine))
    }

    /// A file whose import never produced a document says so, and isn't queued again every check.
    func testAFileThatCannotImportIsReportedOnceAndNotRetried() async throws {
        let engine = IntentSupport.engine()
        let watcher = WatchedFolderService()
        try watcher.watch(folder, library: engine.containerService.activeContainerId)
        try write("", to: "watch-test-empty.txt")
        await watcher.check(engine: engine, documentLimit: .max)
        try await waitFor("the queue to settle") { !engine.ingestionItems.contains { !$0.stage.isTerminal } }
        let queued = Set(engine.ingestionItems.map(\.id))
        await watcher.check(engine: engine, documentLimit: .max)
        XCTAssertTrue(Set(engine.ingestionItems.map(\.id)).isSubset(of: queued), "it was queued again")
        XCTAssertEqual(watcher.folders.first?.note, "1 file couldn't be imported, and will be tried again if changed.")
    }

    func testTheListSurvivesARestart() throws {
        let watcher = WatchedFolderService()
        let library = UUID()
        try watcher.watch(folder, library: library)
        XCTAssertEqual(WatchedFolderStore.load().first?.libraryId, library)
        watcher.stopWatching(library: library)
        XCTAssertTrue(WatchedFolderStore.load().isEmpty)
    }
}
