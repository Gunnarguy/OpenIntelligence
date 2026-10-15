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
}
