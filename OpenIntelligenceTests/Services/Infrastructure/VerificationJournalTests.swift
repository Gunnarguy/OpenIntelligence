//
//  VerificationJournalTests.swift
//  OpenIntelligenceTests
//
//  The development build's event journal (5.8), which `scripts/phone_evidence.py` reads off a device to close
//  roadmap rows. These pin its line format, its spans and its rotation, since the checker parses all three.
//

import XCTest

@testable import OpenIntelligence

final class VerificationJournalTests: XCTestCase {
    private var folder: URL!
    private var original: (() -> URL?)!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        original = VerificationJournal.fileURL
        let url = folder.appendingPathComponent("verification_events.jsonl")
        VerificationJournal.fileURL = { url }
    }

    override func tearDown() {
        VerificationJournal.flush()
        VerificationJournal.fileURL = original
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testAnEventIsOneJSONLineWithItsFields() {
        VerificationJournal.record("nav.post", ["to": "chat"])
        let lines = VerificationJournal.readAll()
        XCTAssertEqual(lines.count, 1)
        let line = lines[0]
        XCTAssertEqual(line["e"] as? String, "nav.post")
        XCTAssertEqual(line["o"] as? String, "info")
        XCTAssertEqual((line["f"] as? [String: String])?["to"], "chat")
        XCTAssertNotNil(line["t"] as? String)
        XCTAssertNotNil(line["v"] as? String)
        XCTAssertNil(line["ms"])
    }

    func testASpanRecordsStartedThenOkWithADuration() {
        let span = VerificationJournal.Span("intent.Test", ["k": "v"])
        span.end(["extra": "1"])
        span.end()
        let lines = VerificationJournal.readAll()
        XCTAssertEqual(lines.map { $0["o"] as? String }, ["started", "ok"])
        XCTAssertNotNil(lines[1]["ms"] as? Double)
        XCTAssertEqual((lines[1]["f"] as? [String: String])?["extra"], "1")
        XCTAssertEqual((lines[1]["f"] as? [String: String])?["k"], "v")
    }

    func testAFailedSpanNamesTheErrorTypeAndIsNotAlsoRecordedOk() {
        struct Broken: Error {}
        let span = VerificationJournal.Span("intent.Test")
        span.fail(Broken())
        span.end()
        let lines = VerificationJournal.readAll()
        XCTAssertEqual(lines.map { $0["o"] as? String }, ["started", "failed"])
        XCTAssertEqual((lines[1]["f"] as? [String: String])?["error"], "Broken")
    }

    func testACancelledSpanIsRecordedCancelled() {
        let span = VerificationJournal.Span("intent.Test")
        span.fail(CancellationError())
        XCTAssertEqual(VerificationJournal.readAll().last?["o"] as? String, "cancelled")
    }

    func testRunRecordsTheOutcomeOfItsBody() async throws {
        struct Broken: Error {}
        let value = await VerificationJournal.run("work") { 7 }
        XCTAssertEqual(value, 7)
        do {
            _ = try await VerificationJournal.run("work") { () async throws -> Int in throw Broken() }
            XCTFail("should have thrown")
        } catch {}
        XCTAssertEqual(
            VerificationJournal.readAll().map { $0["o"] as? String }, ["started", "ok", "started", "failed"])
    }

    func testAnIdIsShortenedToEightCharacters() {
        let id = UUID()
        XCTAssertEqual(VerificationJournal.anon(id), String(id.uuidString.prefix(8)))
        XCTAssertEqual(VerificationJournal.anon(nil), "none")
    }

    /// A destination's case name only: a search term or a question it carries never reaches the journal.
    func testANavigationEventNamesTheCaseNotWhatItCarries() {
        XCTAssertEqual(AppNavigationRequest.caseName(.searchFor("my secret lease")), "searchFor")
        XCTAssertEqual(AppNavigationRequest.caseName(.ask("what is my rent?")), "ask")
        XCTAssertEqual(AppNavigationRequest.caseName(.chat), "chat")
    }

    func testAFileOverTheLimitIsMovedAsideOnce() throws {
        let url = VerificationJournal.fileURL()!
        try Data(count: Int(VerificationJournal.maxFileSize) + 1).write(to: url)
        VerificationJournal.record("after.rotation")
        let lines = VerificationJournal.readAll()
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["e"] as? String, "after.rotation")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: url.deletingPathExtension().appendingPathExtension("prev.jsonl").path))
    }
}
