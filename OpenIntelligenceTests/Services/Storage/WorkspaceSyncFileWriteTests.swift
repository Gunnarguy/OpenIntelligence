//
//  WorkspaceSyncFileWriteTests.swift
//  OpenIntelligenceTests
//
//  How sync writes a library's files into iCloud (5.7). Through 5.6 every pass deleted each
//  library's chat history, transcript and conversation memory in iCloud and copied them in again,
//  changed or not, and wrote a library's vector store there by clearing it and writing three new
//  files with no coordination. On 2026-10-14 the owner's iCloud container held 500 conflict copies
//  ("chat_history_<id> 2.json" and the like), all in those six file families. These tests hold the
//  three pieces that change that: an unchanged file is left alone, a changed one is replaced in
//  place and keeps its source's modification date (which the newest-wins choices read), and a
//  store's files are replaced together. Not covered: two devices writing at once, which needs both.
//
//  2026-11-18: the tests from `testWritingTheSameJSONLeavesTheFileAlone` on hold the end of the
//  Mac's iCloud self-echo loop. Every pass rewrote `deleted_documents.json` and `ingestion_queue.json`
//  in both roots. The two in the iCloud root counted (the metadata query watches only that root):
//  each rewrite moved a content-change date the workspace signature hashes, so the next pass and a
//  library reload followed about every 5 s. A pass that
//  changed nothing now writes nothing, and a new tombstone, item or deleted document still writes.
//

import XCTest

@testable import OpenIntelligence

final class WorkspaceSyncFileWriteTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSyncFileWriteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ text: String, modified: Date? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private func modified(_ url: URL) throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    func testAnUnchangedFileIsLeftAlone() throws {
        let source = try file("source.json", "[1,2,3]", modified: Date(timeIntervalSince1970: 1_800_000_000))
        let destination = try file("chat_history.json", "[1,2,3]", modified: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertFalse(try WorkspaceSyncService.replaceItemIfDifferent(at: destination, withCopyOf: source))
        XCTAssertEqual(try modified(destination), Date(timeIntervalSince1970: 1_700_000_000), "nothing was written")
    }

    func testAChangedFileIsReplacedAndKeepsTheSourcesDate() throws {
        let sourceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let source = try file("source.json", "[1,2,3,4]", modified: sourceDate)
        let destination = try file("chat_history.json", "[1,2,3]")

        XCTAssertTrue(try WorkspaceSyncService.replaceItemIfDifferent(at: destination, withCopyOf: source))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "[1,2,3,4]")
        XCTAssertEqual(try modified(destination), sourceDate, "the newest-wins choices read this date")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the source stays where it was")
    }

    func testAMissingFileIsCopied() throws {
        let source = try file("source.json", "[1]")
        let destination = folder.appendingPathComponent("transcript.json")

        XCTAssertTrue(try WorkspaceSyncService.replaceItemIfDifferent(at: destination, withCopyOf: source))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "[1]")
    }

    func testAStoresFilesAreReplacedTogether() async throws {
        let staged = folder.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let destinations = ["meta.json", "vectors.bin", "norms.bin"].map { folder.appendingPathComponent($0) }
        try Data("old meta".utf8).write(to: destinations[0])
        try Data("old vectors".utf8).write(to: destinations[1])
        try Data("old norms".utf8).write(to: destinations[2])
        let sources = ["meta.json", "vectors.bin", "norms.bin"].map { staged.appendingPathComponent($0) }
        try Data("new meta".utf8).write(to: sources[0])
        try Data("new vectors".utf8).write(to: sources[1])
        // No staged norms: the store's file is removed, as clearing it did.

        try await WorkspaceSyncService.coordinatedReplaceItems(at: destinations, with: sources)

        XCTAssertEqual(try String(contentsOf: destinations[0], encoding: .utf8), "new meta")
        XCTAssertEqual(try String(contentsOf: destinations[1], encoding: .utf8), "new vectors")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinations[2].path))
    }

    func testAStoreWrittenWhereNoneWasIsMovedIntoPlace() async throws {
        let staged = folder.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let source = staged.appendingPathComponent("meta.json")
        try Data("meta".utf8).write(to: source)
        let destination = folder.appendingPathComponent("meta.json")

        try await WorkspaceSyncService.coordinatedReplaceItems(at: [destination], with: [source])

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "meta")
    }

    func testConflictCopiesAreToldApartFromTheFilesTheAppReads() {
        let id = UUID().uuidString
        XCTAssertTrue(WorkspaceSyncService.isConflictCopyName("chat_history_\(id) 2.json"))
        XCTAssertTrue(WorkspaceSyncService.isConflictCopyName("transcript_\(id) 17.json"))
        XCTAssertTrue(WorkspaceSyncService.isConflictCopyName("vector_database_\(id)_vectors 3.bin"))
        XCTAssertTrue(WorkspaceSyncService.isConflictCopyName("conversation_memory_\(id) 8.json"))
        XCTAssertFalse(WorkspaceSyncService.isConflictCopyName("chat_history_\(id).json"))
        XCTAssertFalse(WorkspaceSyncService.isConflictCopyName("vector_database_\(id)_meta.json"))
        XCTAssertFalse(WorkspaceSyncService.isConflictCopyName("Lease 2.pdf"), "a document is not a library file")
        XCTAssertFalse(WorkspaceSyncService.isConflictCopyName("transcript_\(id) 2a.json"))
    }

    // MARK: - A pass that changed nothing writes nothing (2026-11-18)

    private let oldDate = Date(timeIntervalSince1970: 1_600_000_000)

    private func age(_ urls: URL...) throws {
        for url in urls {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }
    }

    private func wasWritten(_ url: URL) throws -> Bool {
        try modified(url) != oldDate
    }

    func testWritingTheSameJSONLeavesTheFileAlone() throws {
        let url = folder.appendingPathComponent("deleted_documents.json")
        try WorkspaceSyncService.writeJSON(["A", "B"], to: url)
        try age(url)

        try WorkspaceSyncService.writeJSON(["A", "B"], to: url)

        XCTAssertFalse(try wasWritten(url), "identical bytes must not move the content date the sync signature hashes")
    }

    func testWritingANewDeletedDocumentWritesTheFile() throws {
        let url = folder.appendingPathComponent("deleted_documents.json")
        try WorkspaceSyncService.writeJSON(["A"], to: url)
        try age(url)

        try WorkspaceSyncService.writeJSON(["A", "B"], to: url)

        XCTAssertTrue(try wasWritten(url))
        XCTAssertEqual(try WorkspaceSyncService.readJSONIfPresent([String].self, from: url), ["A", "B"])
    }

    func testWritingJSONWhereNoFileWasCreatesIt() throws {
        let url = folder.appendingPathComponent("deleted_documents.json")
        try WorkspaceSyncService.writeJSON(["A"], to: url)
        XCTAssertEqual(try WorkspaceSyncService.readJSONIfPresent([String].self, from: url), ["A"])
    }

    private struct QueueRoots {
        let local: URL
        let shared: URL
        var localQueue: URL { local.appendingPathComponent("ingestion_queue.json") }
        var sharedQueue: URL { shared.appendingPathComponent("ingestion_queue.json") }
    }

    private func queueRoots() throws -> QueueRoots {
        let roots = QueueRoots(
            local: folder.appendingPathComponent("local", isDirectory: true),
            shared: folder.appendingPathComponent("shared", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: roots.local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: roots.shared, withIntermediateDirectories: true)
        return roots
    }

    private func queueState(
        items: [IngestionItem],
        tombstones: [IngestionQueueTombstone],
        updatedAt: Date
    ) -> PersistedIngestionQueueStateRecord {
        PersistedIngestionQueueStateRecord(
            items: items,
            contexts: items.map { PersistedIngestionContextRecord(id: $0.id, context: .userInitiated) },
            tombstones: tombstones,
            updatedAt: updatedAt
        )
    }

    @MainActor
    private func runQueuePass(_ roots: QueueRoots, library: UUID, aliases: [UUID: UUID] = [:]) throws {
        let suite = "WorkspaceSyncFileWriteTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try WorkspaceSyncService(defaults: defaults).synchronizeIngestionQueue(
            localRoot: roots.local,
            sharedRoot: roots.shared,
            syncedContainerIDs: [library],
            containerAliases: aliases,
            strategy: .mergeLibraries
        )
    }

    /// The owner's case: both copies hold the same work, but `updatedAt` differs (a reload saved
    /// the local copy) and tombstones that share one `discardedAt` are in another order.
    @MainActor
    func testAQueuePassThatChangedNothingWritesNeitherCopy() throws {
        let roots = try queueRoots()
        let library = UUID()
        let item = IngestionItem(url: URL(fileURLWithPath: "/tmp/queued.pdf"), containerId: library)
        let discardedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let tombstones = (0..<5).map { _ in
            IngestionQueueTombstone(id: UUID(), containerId: library, discardedAt: discardedAt)
        }
        try WorkspaceSyncService.writeJSON(
            queueState(items: [item], tombstones: tombstones, updatedAt: Date(timeIntervalSince1970: 1_700_000_100)),
            to: roots.sharedQueue)
        try WorkspaceSyncService.writeJSON(
            queueState(items: [item], tombstones: tombstones.reversed(), updatedAt: Date()),
            to: roots.localQueue)
        try age(roots.localQueue, roots.sharedQueue)

        try runQueuePass(roots, library: library)
        try runQueuePass(roots, library: library)

        XCTAssertFalse(try wasWritten(roots.localQueue), "the local queue held the same work")
        XCTAssertFalse(try wasWritten(roots.sharedQueue), "the iCloud queue held the same work")
    }

    @MainActor
    func testAQueuePassWritesANewTombstoneToICloud() throws {
        let roots = try queueRoots()
        let library = UUID()
        let discardedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let kept = IngestionQueueTombstone(id: UUID(), containerId: library, discardedAt: discardedAt)
        let discardedHere = IngestionQueueTombstone(id: UUID(), containerId: library, discardedAt: discardedAt)
        try WorkspaceSyncService.writeJSON(
            queueState(items: [], tombstones: [kept], updatedAt: discardedAt), to: roots.sharedQueue)
        try WorkspaceSyncService.writeJSON(
            queueState(items: [], tombstones: [kept, discardedHere], updatedAt: Date()), to: roots.localQueue)
        try age(roots.localQueue, roots.sharedQueue)

        try runQueuePass(roots, library: library)

        XCTAssertTrue(try wasWritten(roots.sharedQueue))
        let shared = try XCTUnwrap(
            WorkspaceSyncService.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: roots.sharedQueue))
        XCTAssertEqual(Set(shared.tombstones.map(\.id)), [kept.id, discardedHere.id])
        XCTAssertFalse(try wasWritten(roots.localQueue), "the local copy already held both tombstones")
    }

    @MainActor
    func testAQueuePassWritesANewItemToICloud() throws {
        let roots = try queueRoots()
        let library = UUID()
        let existing = IngestionItem(url: URL(fileURLWithPath: "/tmp/existing.pdf"), containerId: library)
        let added = IngestionItem(url: URL(fileURLWithPath: "/tmp/added.pdf"), containerId: library)
        try WorkspaceSyncService.writeJSON(
            queueState(items: [existing], tombstones: [], updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            to: roots.sharedQueue)
        try WorkspaceSyncService.writeJSON(
            queueState(items: [existing, added], tombstones: [], updatedAt: Date()), to: roots.localQueue)
        try age(roots.localQueue, roots.sharedQueue)

        try runQueuePass(roots, library: library)

        XCTAssertTrue(try wasWritten(roots.sharedQueue))
        let shared = try XCTUnwrap(
            WorkspaceSyncService.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: roots.sharedQueue))
        XCTAssertEqual(Set(shared.items.map(\.id)), [existing.id, added.id])
    }

    /// Both copies hold the same item, in library A, and a library merge maps A to B. After the
    /// aliases the two copies agree with the result, so the comparison has to be with what was read
    /// from disk, or the remap would never be written.
    @MainActor
    func testAQueuePassWritesAContainerAliasToBothCopies() throws {
        let roots = try queueRoots()
        let merged = UUID()
        let canonical = UUID()
        let item = IngestionItem(url: URL(fileURLWithPath: "/tmp/aliased.pdf"), containerId: merged)
        let state = queueState(items: [item], tombstones: [], updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try WorkspaceSyncService.writeJSON(state, to: roots.sharedQueue)
        try WorkspaceSyncService.writeJSON(state, to: roots.localQueue)
        try age(roots.localQueue, roots.sharedQueue)

        try runQueuePass(roots, library: canonical, aliases: [merged: canonical])

        XCTAssertTrue(try wasWritten(roots.sharedQueue))
        let shared = try XCTUnwrap(
            WorkspaceSyncService.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: roots.sharedQueue))
        XCTAssertEqual(shared.items.map(\.id), [item.id])
        XCTAssertEqual(shared.items.map(\.containerId), [canonical])
        XCTAssertTrue(try wasWritten(roots.localQueue))
        let local = try XCTUnwrap(
            WorkspaceSyncService.readJSONIfPresent(PersistedIngestionQueueStateRecord.self, from: roots.localQueue))
        XCTAssertEqual(local.items.map(\.containerId), [canonical])
    }

    func testQueueStatesWithTheSameWorkMatchAndADifferentStageDoesNot() {
        let library = UUID()
        let item = IngestionItem(url: URL(fileURLWithPath: "/tmp/queued.pdf"), containerId: library)
        var running = item
        running.stage = .embedding
        let a = queueState(items: [item], tombstones: [], updatedAt: Date(timeIntervalSince1970: 1))
        let b = queueState(items: [item], tombstones: [], updatedAt: Date(timeIntervalSince1970: 2))
        let c = queueState(items: [running], tombstones: [], updatedAt: Date(timeIntervalSince1970: 1))

        XCTAssertTrue(WorkspaceSyncService.ingestionQueueStatesHoldTheSameWork(a, b), "updatedAt alone is not a change")
        XCTAssertFalse(WorkspaceSyncService.ingestionQueueStatesHoldTheSameWork(a, c), "a new stage is a change")
        XCTAssertFalse(WorkspaceSyncService.ingestionQueueStatesHoldTheSameWork(a, nil), "a missing file is written")
    }

    func testTheConflictCopiesInAFolderAreCounted() throws {
        let id = UUID().uuidString
        _ = try file("chat_history_\(id).json", "[]")
        _ = try file("chat_history_\(id) 2.json", "[]")
        _ = try file("transcript_\(id) 3.json", "[]")
        _ = try file("Lease 2.pdf", "%PDF")
        XCTAssertEqual(WorkspaceSyncService.conflictCopyCount(in: folder), 2)
    }
}
