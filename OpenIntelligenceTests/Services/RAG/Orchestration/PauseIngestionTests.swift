//
//  PauseIngestionTests.swift
//  OpenIntelligenceTests
//
//  The import queue's Pause (5.7, `RAGService.pauseIngestionQueue`). Waiting files are paused and
//  the queue waits for Continue, and an item says whether it continues from where it stopped or
//  starts over. Runs on an engine of its own in the app the suite runs in. Not covered: pausing a
//  large PDF part-way and continuing it on a device, which is what closes the row.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class PauseIngestionTests: XCTestCase {
    private func file(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).txt")
        try Data("A note to import.".utf8).write(to: url)
        return url
    }

    func testPausingHoldsTheQueueUntilItIsContinuedOrDiscarded() throws {
        let engine = RAGService()
        let ids = engine.enqueueDocuments([try file("Pause one"), try file("Pause two")])
        XCTAssertEqual(ids.count, 2)

        engine.pauseIngestionQueue()

        let paused = engine.ingestionItems.filter { ids.contains($0.id) }
        XCTAssertEqual(paused.count, 2)
        XCTAssertTrue(paused.allSatisfy { $0.stage == .paused })
        XCTAssertTrue(paused.allSatisfy { $0.detail == RAGService.pausedStartsOverDetail }, "small text files have no checkpoint")
        XCTAssertTrue(engine.ingestionPausedByPerson)

        engine.discardPausedIngestionQueue()
        XCTAssertFalse(engine.ingestionPausedByPerson)
        XCTAssertTrue(engine.ingestionItems.filter { ids.contains($0.id) }.isEmpty)
    }

    func testContinuingQueuesThePausedFilesAgain() throws {
        let engine = RAGService()
        let ids = engine.enqueueDocuments([try file("Continue one")])
        engine.pauseIngestionQueue()

        engine.continuePausedIngestionQueue()

        XCTAssertFalse(engine.ingestionPausedByPerson)
        let item = try XCTUnwrap(engine.ingestionItems.first { ids.contains($0.id) })
        XCTAssertNotEqual(item.stage, .paused)
        XCTAssertTrue(item.events.contains { $0.detail == "Continued after a pause" })
        engine.cancelAllIngestion()
    }

    /// The task a pause cancels runs on to its next cancellation check, so its progress can land after the pause.
    /// On 2026-10-16, in the Simulator, "Storing" replaced "Paused" on a file whose embedding had just finished, and
    /// Continue, which takes the paused files, left that one at "Storing" with nothing importing it.
    func testProgressAfterThePauseLeavesTheFilePaused() throws {
        let engine = RAGService()
        let ids = engine.enqueueDocuments([try file("Late progress")])
        let id = try XCTUnwrap(ids.first)
        engine.pauseIngestionQueue()

        engine.updateIngestionItem(
            id: id, filename: "Late progress.txt", stage: .storing,
            detail: "Persisting 13 chunks to vector database...", progress: 0.94)

        let paused = try XCTUnwrap(engine.ingestionItems.first { $0.id == id })
        XCTAssertEqual(paused.stage, .paused)
        XCTAssertEqual(paused.detail, RAGService.pausedStartsOverDetail)

        engine.continuePausedIngestionQueue()
        let continued = try XCTUnwrap(engine.ingestionItems.first { $0.id == id })
        XCTAssertNotEqual(continued.stage, .paused)
        XCTAssertTrue(continued.events.contains { $0.detail == "Continued after a pause" })
        engine.cancelAllIngestion()
    }

    /// Stopping and dismissing the queue leaves nothing paused, so the next import's end of background time is
    /// handled (`handleContinuedIngestionExpiration` returns at once while the flag is set).
    func testStoppingThePausedQueueClearsThePause() throws {
        let engine = RAGService()
        _ = engine.enqueueDocuments([try file("Stop paused")])
        engine.pauseIngestionQueue()
        XCTAssertTrue(engine.ingestionPausedByPerson)

        engine.stopAndDismissIngestionQueue()

        XCTAssertFalse(engine.ingestionPausedByPerson)
        XCTAssertFalse(engine.ingestionItems.contains { $0.stage == .paused })
    }

    /// Stop and dismiss removes the app's own copy of a stopped file, and keeps a copy a stored document names (5.7):
    /// the copy of a cancelled 8.7 MB import stayed in ImportedDocuments, and the same file chosen again came in as
    /// "Support Tickets-2.jsonl" (demo copy of 37330a9, 2026-10-20).
    func testStoppingRemovesTheCopyOfAStoppedFileAndKeepsADocumentsFile() async throws {
        let folder = AppSupportPaths.importedDocumentsDirectoryURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stopped = folder.appendingPathComponent("Stopped copy \(UUID().uuidString).txt")
        let kept = folder.appendingPathComponent("Kept copy \(UUID().uuidString).txt")
        try Data("A note to import.".utf8).write(to: stopped)
        try Data("A note to import.".utf8).write(to: kept)
        defer {
            try? FileManager.default.removeItem(at: stopped)
            try? FileManager.default.removeItem(at: kept)
        }

        let engine = RAGService()
        // The engine reads its stored documents after it starts, and that replaces `documents`.
        for _ in 0..<200 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(engine.hasLoadedDocumentsFromDisk, "the engine never read its stored documents")
        engine.documents.append(Document(id: UUID(), filename: kept.lastPathComponent, fileURL: kept, contentType: .text))
        _ = engine.enqueueDocuments([stopped, kept])
        engine.pauseIngestionQueue()
        engine.stopAndDismissIngestionQueue()

        for _ in 0..<40 where FileManager.default.fileExists(atPath: stopped.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stopped.path), "the stopped file's copy stayed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "a stored document's own file was removed")
    }

    /// An end still lands on a paused file: Cancel on a paused file ends it through the same update.
    func testCancellingAPausedFileCancelsIt() throws {
        let engine = RAGService()
        let ids = engine.enqueueDocuments([try file("Cancel paused"), try file("Stay paused")])
        let id = try XCTUnwrap(ids.first)
        engine.pauseIngestionQueue()

        engine.cancelIngestionItem(id)

        let item = engine.ingestionItems.first { $0.id == id }
        XCTAssertTrue(item == nil || item?.stage == .cancelled, "the cancelled file is gone or reads Cancelled, not Paused")
        XCTAssertEqual(engine.ingestionItems.first { $0.id == ids[1] }?.stage, .paused)
        engine.discardPausedIngestionQueue()
    }
}
