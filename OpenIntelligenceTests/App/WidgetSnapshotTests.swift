//
//  WidgetSnapshotTests.swift
//  OpenIntelligenceTests
//
//  The "Your Library" widget reads what the app writes to the app group's container (5.7, `WidgetSnapshot`): the
//  open library, its document count, the last question in that library and the start of its answer. Written to a file
//  of the test's own here; the app group itself needs the App ID's capability, which this build does not carry yet.
//

import XCTest

@testable import OpenIntelligence

final class WidgetSnapshotTests: XCTestCase {
    private var url: URL!
    private let home = UUID()
    private let work = UUID()

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testThePreviewIsPlainTextCutOnAWord() {
        XCTAssertEqual(
            WidgetSnapshot.preview(of: "## Rent\n**Rent** is due on the first [S2], with a grace period [S3, S4]."),
            "Rent Rent is due on the first, with a grace period.")
        let list = "The excerpts:\n• Privacy summary: on device.\n- Storage stays local.\n2. Then it answers."
        XCTAssertEqual(
            WidgetSnapshot.preview(of: list),
            "The excerpts: Privacy summary: on device. Storage stays local. Then it answers.",
            "a list's bullets and numbers are not shown as punctuation")
        XCTAssertEqual(
            WidgetSnapshot.preview(of: "It costs 5 - 10 dollars."), "It costs 5 - 10 dollars.", "a dash inside a line stays")
        let long = String(repeating: "word ", count: 60)
        let preview = WidgetSnapshot.preview(of: long, limit: 40)
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertLessThanOrEqual(preview.count, 41)
        XCTAssertFalse(preview.dropLast().hasSuffix(" "), "cut on a word")
    }

    func testTheAnswerStaysWhileItsLibraryChanges() {
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 11, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first [S1].", libraryId: home, at: url,
            now: Date(timeIntervalSince1970: 1_800_000_000))
        WidgetSnapshot.recordLibrary(id: home, name: "Apartment", documentCount: 12, at: url)

        let snapshot = WidgetSnapshot.read(from: url)
        XCTAssertEqual(snapshot?.libraryName, "Apartment", "a rename shows")
        XCTAssertEqual(snapshot?.documentCount, 12)
        XCTAssertEqual(snapshot?.question, "When is the rent due?")
        XCTAssertEqual(snapshot?.answerPreview, "On the first.")
        XCTAssertEqual(snapshot?.answeredAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testOpeningAnotherLibraryDropsTheAnswer() {
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 12, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first.", libraryId: home, at: url)
        WidgetSnapshot.recordLibrary(id: work, name: "Work", documentCount: 40, at: url)

        let snapshot = WidgetSnapshot.read(from: url)
        XCTAssertEqual(snapshot?.libraryName, "Work")
        XCTAssertNil(snapshot?.question, "Home's question is not shown under Work")
        XCTAssertNil(snapshot?.answerPreview)
    }

    func testAnAnswerFromALibraryThatIsNotOpenIsNotWritten() {
        WidgetSnapshot.recordLibrary(id: work, name: "Work", documentCount: 40, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first.", libraryId: home, at: url)

        XCTAssertNil(WidgetSnapshot.read(from: url)?.answerPreview)
    }

    func testClearingAConversationDropsItsAnswerOnly() {
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 12, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first.", libraryId: home, at: url)

        WidgetSnapshot.forgetAnswer(inLibrary: work, at: url)
        XCTAssertEqual(WidgetSnapshot.read(from: url)?.answerPreview, "On the first.", "another library's clear")

        WidgetSnapshot.forgetAnswer(inLibrary: home, at: url)
        let snapshot = WidgetSnapshot.read(from: url)
        XCTAssertNil(snapshot?.question)
        XCTAssertNil(snapshot?.answerPreview)
        XCTAssertNil(snapshot?.answeredAt)
        XCTAssertEqual(snapshot?.libraryName, "Home", "the library stays")
    }

    func testAHiddenAnswerLeavesTheWidget() {
        let answer = UUID()
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 12, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first.", libraryId: home, messageId: answer, at: url)

        WidgetSnapshot.forgetAnswer(messageId: UUID(), at: url)
        XCTAssertEqual(WidgetSnapshot.read(from: url)?.answerPreview, "On the first.", "another message")

        WidgetSnapshot.forgetAnswer(messageId: answer, at: url)
        XCTAssertNil(WidgetSnapshot.read(from: url)?.answerPreview)
        XCTAssertNil(WidgetSnapshot.read(from: url)?.messageId)
    }

    func testAnAnswerWhoseConversationIsGoneLeavesTheWidget() {
        let conversation = UUID()
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 12, at: url)
        WidgetSnapshot.recordAnswer(
            question: "When is the rent due?", answer: "On the first.", libraryId: home, threadId: conversation,
            at: url)

        var asked: (UUID, UUID)?
        WidgetSnapshot.forgetAnswer(
            unlessConversationExists: { threadId, libraryId in
                asked = (threadId, libraryId)
                return true
            }, at: url)
        XCTAssertEqual(asked?.0, conversation)
        XCTAssertEqual(asked?.1, home)
        XCTAssertEqual(WidgetSnapshot.read(from: url)?.answerPreview, "On the first.", "still there")

        WidgetSnapshot.forgetAnswer(unlessConversationExists: { _, _ in false }, at: url)
        XCTAssertNil(WidgetSnapshot.read(from: url)?.answerPreview, "deleted on another device")
        XCTAssertNil(WidgetSnapshot.read(from: url)?.threadId)
        XCTAssertEqual(WidgetSnapshot.read(from: url)?.libraryName, "Home")
    }

    func testAnUnchangedSnapshotIsNotWrittenAgain() {
        let snapshot = WidgetSnapshot(libraryId: home, libraryName: "Home", documentCount: 3)
        XCTAssertTrue(WidgetSnapshot.write(snapshot, to: url))
        XCTAssertFalse(WidgetSnapshot.write(snapshot, to: url), "no redraw for nothing")
    }

    func testWithoutAnAppGroupNothingIsWritten() {
        XCTAssertFalse(WidgetSnapshot.write(WidgetSnapshot(libraryName: "Home", documentCount: 3), to: nil))
        XCTAssertNil(WidgetSnapshot.read(from: nil))
        WidgetSnapshot.recordLibrary(id: home, name: "Home", documentCount: 3, at: nil)
        WidgetSnapshot.recordAnswer(question: nil, answer: "On the first.", libraryId: home, at: nil)
        WidgetSnapshot.forgetAnswer(inLibrary: home, at: nil)
        WidgetSnapshot.forgetAnswer(messageId: UUID(), at: nil)
        WidgetSnapshot.forgetAnswer(unlessConversationExists: { _, _ in false }, at: nil)
    }
}
