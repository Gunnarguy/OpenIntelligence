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

    func testTheConflictCopiesInAFolderAreCounted() throws {
        let id = UUID().uuidString
        _ = try file("chat_history_\(id).json", "[]")
        _ = try file("chat_history_\(id) 2.json", "[]")
        _ = try file("transcript_\(id) 3.json", "[]")
        _ = try file("Lease 2.pdf", "%PDF")
        XCTAssertEqual(WorkspaceSyncService.conflictCopyCount(in: folder), 2)
    }
}
