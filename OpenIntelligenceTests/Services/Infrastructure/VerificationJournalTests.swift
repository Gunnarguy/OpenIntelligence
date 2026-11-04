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
        // Back to the real file: in a test host the journal is off again, so no other test writes into it (5.8).
        VerificationJournal.fileURLIsReplaced = false
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

    /// A unit-test host writes nothing until a test points the journal at its own file (5.8), and a journal that is
    /// off evaluates no fields.
    func testATestHostWritesNothingUntilATestPointsTheJournalElsewhere() {
        VerificationJournal.fileURLIsReplaced = false
        XCTAssertFalse(VerificationJournal.isEnabled)
        var evaluated = false
        VerificationJournal.record("not.written", { evaluated = true; return ["k": "v"] }())
        XCTAssertFalse(evaluated, "fields are not built while the journal is off")
        VerificationJournal.fileURLIsReplaced = true
        XCTAssertTrue(VerificationJournal.isEnabled)
        XCTAssertFalse(VerificationJournal.readAll().contains { $0["e"] as? String == "not.written" })
    }

    /// Every line names its platform, so the iPhone's journal and the Mac's are told apart when read together (5.8).
    func testEveryLineNamesItsPlatform() {
        VerificationJournal.record("nav.post", ["to": "chat"])
        let line = VerificationJournal.readAll().last
        #if os(macOS)
            XCTAssertEqual(line?["os"] as? String, "macOS")
        #else
            XCTAssertEqual(line?["os"] as? String, ProcessInfo.processInfo.isiOSAppOnMac ? "macOS" : "iOS")
        #endif
        XCTAssertEqual(line?["os"] as? String, VerificationJournal.platform)
    }

    func testTheFootprintAndAFileSizeAreReadAsNumbers() throws {
        XCTAssertGreaterThan(VerificationJournal.footprintMB(), 0)
        let file = folder.appendingPathComponent("sized.bin")
        try Data(count: 1234).write(to: file)
        XCTAssertEqual(VerificationJournal.fileBytes(file), 1234)
        XCTAssertEqual(VerificationJournal.fileBytes(folder.appendingPathComponent("missing")), 0)
    }

    func testTheLaunchTimeIsInThePast() {
        XCTAssertLessThanOrEqual(VerificationJournal.launchedAt, Date())
    }

    /// The watchdog starts once, stops, and records a main-thread stall of 250 ms or more with its phase.
    func testTheWatchdogStartsStopsAndRecordsAStall() {
        let watchdog = MainThreadWatchdog()
        XCTAssertFalse(watchdog.isRunning)
        watchdog.phase = "testPhase"
        watchdog.start(interval: .milliseconds(20))
        watchdog.start(interval: .milliseconds(20))
        XCTAssertTrue(watchdog.isRunning)
        let before = Date()

        // Let a ping go out, then hold the main thread past the threshold, then let it answer.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        Thread.sleep(forTimeInterval: 0.45)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertGreaterThanOrEqual(watchdog.longestStall(since: before), MainThreadWatchdog.stallThresholdMs)
        XCTAssertFalse(watchdog.stallFree(since: before))
        XCTAssertTrue(watchdog.stallFree(since: Date().addingTimeInterval(60)))
        let stall = VerificationJournal.readAll().last { $0["e"] as? String == "mainThread.stall" }
        XCTAssertEqual((stall?["f"] as? [String: String])?["phase"], "testPhase")
        XCTAssertNotNil(stall?["ms"] as? Double)

        watchdog.stop()
        XCTAssertFalse(watchdog.isRunning)
        // Stalls only: the test host's own app writes other events into the same file meanwhile.
        func stalls() -> Int { VerificationJournal.readAll().filter { $0["e"] as? String == "mainThread.stall" }.count }
        let count = stalls()
        Thread.sleep(forTimeInterval: 0.4)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(stalls(), count, "a stopped watchdog records nothing")
    }
}
