//
//  AskControlTests.swift
//  OpenIntelligenceTests
//
//  The system can stop an ask action, and on 27 the action reports progress (5.7).
//

import XCTest

@testable import OpenIntelligence

final class AskControlTests: XCTestCase {
    func testAStopRunsEveryHandlerOnceAndKeepsTheFirstReason() {
        let control = AskControl(progress: nil)
        let counter = Counter()
        control.whenCancelled { counter.add() }
        control.whenCancelled { counter.add() }
        XCTAssertNil(control.cancellationReason)

        control.cancel(because: "timeout")
        control.cancel(because: "cancelled")
        XCTAssertEqual(control.cancellationReason, "timeout")
        XCTAssertEqual(counter.value, 2)

        // A handler added after the stop runs at once.
        control.whenCancelled { counter.add() }
        XCTAssertEqual(counter.value, 3)
    }

    func testProgressKeepsMovingAndIsFullOnlyWithTheAnswer() {
        let progress = Progress()
        let control = AskControl(progress: progress)
        XCTAssertEqual(progress.totalUnitCount, 100)
        control.report("Searching your documents")
        XCTAssertEqual(progress.completedUnitCount, 5)
        XCTAssertEqual(progress.localizedDescription, "Searching your documents")
        // Ten minutes of two-second ticks: the count changes every time and the bar never fills.
        var last = progress.completedUnitCount
        for _ in 0..<300 {
            control.tick()
            XCTAssertGreaterThan(progress.completedUnitCount, last)
            last = progress.completedUnitCount
            XCTAssertLessThan(progress.fractionCompleted, 1)
        }
        control.report("   ")
        XCTAssertEqual(progress.localizedDescription, "Searching your documents", "an empty status keeps the last one")
        control.finish()
        XCTAssertEqual(progress.fractionCompleted, 1)
    }

    func testAFinishedBarStaysFull() {
        let progress = Progress()
        let control = AskControl(progress: progress)
        for _ in 0..<40 { control.tick() }
        control.finish()
        // The heartbeat's last tick and a status that arrives late used to grow the total again.
        control.tick()
        control.report("Writing the answer")
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertNotEqual(progress.localizedDescription, "Writing the answer")
    }

    /// Siri's card shows the answer as plain text, cut at a word to fit the card (5.7).
    func testTheAnswerCardShowsPlainTextCutAtAWord() {
        XCTAssertEqual(AnswerCardSnippetView.shown("**Rent** is due on the *5th*."), "Rent is due on the 5th.")
        let long = String(repeating: "lease ", count: 150)
        let shown = AnswerCardSnippetView.shown(long)
        XCTAssertTrue(shown.hasSuffix("lease…"), String(shown.suffix(12)))
        XCTAssertLessThanOrEqual(shown.count, 601)
    }

    /// The card's buttons follow the answer's evidence list, and fall back to the retrieved
    /// passages when it has none (5.7).
    @MainActor
    func testTheCardOpensTheDocumentsTheEvidenceNames() {
        let lease = UUID()
        let notes = UUID()
        let manual = UUID()
        func passage(of document: UUID) -> RetrievedChunk {
            RetrievedChunk(
                chunk: DocumentChunk(
                    documentId: document, content: "Rent is due on the 5th.", embedding: [],
                    metadata: ChunkMetadata(chunkIndex: 0, wordCount: 6, characterCount: 23)),
                similarityScore: 0.5, rank: 0, sourceDocument: "", pageNumber: nil)
        }
        let first = passage(of: lease)
        let second = passage(of: notes)
        let third = passage(of: manual)
        let fourth = passage(of: lease)
        let passages = [first, second, third, fourth]
        XCTAssertEqual(
            AskActionRunner.sourceDocumentIds(
                evidenceIds: [third, first, fourth].map(\.chunk.id.uuidString), passages: passages),
            [manual, lease])
        XCTAssertEqual(AskActionRunner.sourceDocumentIds(evidenceIds: [], passages: passages), [lease, notes, manual])
        XCTAssertEqual(
            AskActionRunner.sourceDocumentIds(evidenceIds: ["not a passage"], passages: passages),
            [lease, notes, manual], "evidence that names no retrieved passage falls back the same way")
    }

    func testTheReasonIsSaidPlainly() {
        XCTAssertTrue(AskControl.describe("timeout").contains("too long"))
        XCTAssertEqual(AskControl.describe("cancelled"), "The question was stopped.")
    }

    func testASearchFromSiriPutsNoTextInALink() {
        XCTAssertEqual(AppLink.url(for: .searchFor("pet deposit")).absoluteString, "openintelligence://documents/search")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }
}
