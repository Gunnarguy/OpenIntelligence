//
//  ReleaseFinishTests.swift
//  OpenIntelligenceTests
//
//  Pins the 5.8 finishing fixes of 2026-11-10: Quotes only writes no model text, a lost answer is asked again once,
//  a skipped step gets no tick, and a library keeps one live vector store.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ReleaseFinishTests: XCTestCase {
    private func retrieved(_ text: String, section: String? = nil) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: text, embedding: [0],
                metadata: ChunkMetadata(
                    chunkIndex: 0, pageNumber: 1, sectionTitle: section, keywords: [], hasNumericData: false,
                    hasListStructure: false, wordCount: text.split(separator: " ").count, characterCount: text.count)),
            similarityScore: 0.9, rank: 1, sourceDocument: "Lease.pdf")
    }

    // MARK: Quotes only

    func testQuotesOnlyAnswerIsTheDocumentsOwnWordsWithNoModel() {
        let engine = RAGService()
        let passage = "The tenant must give sixty (60) days written notice before moving out of the premises."
        let response = engine.quotesOnlyResponse(
            question: "How much notice must the tenant give?", passages: [retrieved(passage, section: "Notice")],
            queryId: UUID(), retrievalTime: 0.1, retrievalConfig: .default, embeddingProviderId: "test")

        XCTAssertTrue(response.generatedResponse.contains("sixty (60) days written notice"), response.generatedResponse)
        XCTAssertTrue(response.generatedResponse.contains("[S1: Lease.pdf]"))
        XCTAssertTrue(response.generatedResponse.hasSuffix(RAGService.quotesOnlyClosing))
        XCTAssertEqual(response.metadata.modelUsed, "Quotes only")
        XCTAssertEqual(response.metadata.tokensGenerated, 0)
        XCTAssertEqual(response.metadata.gatingDecision, "excerpts_only", "no check ran, so it reads Not Checked")
    }

    func testQuotesOnlyWithNoMatchingWordsSaysSo() {
        let engine = RAGService()
        let response = engine.quotesOnlyResponse(
            question: "What is the pet policy?", passages: [], queryId: UUID(), retrievalTime: 0,
            retrievalConfig: .default, embeddingProviderId: "test")
        XCTAssertTrue(response.generatedResponse.hasPrefix("I couldn't find words in your documents"))
    }

    // MARK: A lost answer is asked again once

    private func record(
        resumed: Bool = false, askedAt: Date = Date(), mode: RAGQualityMode = .deepThink, library: UUID
    )
        -> PendingAnswerStore.Record
    {
        PendingAnswerStore.Record(
            messageId: messageId, question: "What changed in section 4?", mode: mode.rawValue, containerId: library,
            askedAt: askedAt, resumed: resumed)
    }
    private let messageId = UUID()

    func testUnansweredQuestionFromTheLastRunIsResumed() {
        let library = UUID()
        XCTAssertNotNil(
            PendingAnswerStore.resumable(
                record(library: library), lastMessageId: messageId, lastMessageIsQuestion: true, containerId: library,
                mode: .deepThink))
    }

    func testResumeNeedsTheSameQuestionLibraryModeAndOneTry() {
        let library = UUID()
        let cases: [(PendingAnswerStore.Record, UUID?, Bool, UUID, RAGQualityMode, String)] = [
            (record(library: library), UUID(), true, library, .deepThink, "another message is last"),
            (record(library: library), messageId, false, library, .deepThink, "the last message is an answer"),
            (record(library: library), messageId, true, UUID(), .deepThink, "another library is open"),
            (record(library: library), messageId, true, library, .standard, "another mode is chosen"),
            (record(resumed: true, library: library), messageId, true, library, .deepThink, "already asked again once"),
            (
                record(askedAt: Date(timeIntervalSinceNow: -PendingAnswerStore.resumeWindow - 1), library: library),
                messageId, true, library, .deepThink, "asked more than a day ago"
            ),
        ]
        for (pending, lastId, isQuestion, open, mode, why) in cases {
            XCTAssertNil(
                PendingAnswerStore.resumable(
                    pending, lastMessageId: lastId, lastMessageIsQuestion: isQuestion, containerId: open, mode: mode),
                why)
        }
    }

    // MARK: Deep Think panel

    func testASkippedStepIsNotTicked() {
        XCTAssertTrue(VerificationGatesOverlayView.saysSkipped("Query expansion skipped"))
        XCTAssertTrue(VerificationGatesOverlayView.saysSkipped("HyDE disabled in Deep Think"))
        XCTAssertFalse(VerificationGatesOverlayView.saysSkipped("Synonym expansion"))
    }

    // MARK: One live store per library

    func testALibraryDroppedFromTheCacheGetsItsLiveStoreBack() {
        // A library value only: nothing is saved, so the plan's library limit does not apply (it refused
        // `createContainer` on the free-plan Simulator, 2026-11-10).
        let library = KnowledgeContainer(name: "Live store \(UUID().uuidString.prefix(8))")
        let router = VectorStoreRouter()
        let first = router.db(for: library)
        router.invalidate(containerId: library.id)
        let second = router.db(for: library)
        XCTAssertTrue(
            (first as AnyObject) === (second as AnyObject),
            "a store still alive is used again, so two stores never replace one library's files")
    }

    // MARK: New Chat survives a relaunch

    func testANewChatWithNothingAskedIsKeptUntilItIsSaved() {
        let library = UUID()
        let fresh = UUID()
        let key = RAGService.unsavedNewThreadKey(library)
        UserDefaults.standard.set(fresh.uuidString, forKey: key)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }

        let older = UUID()
        XCTAssertEqual(
            RAGService.unsavedNewThread(for: library, savedThreadIds: [older]), fresh,
            "the new chat, not the older conversation, opens after a relaunch")
        XCTAssertNil(
            RAGService.unsavedNewThread(for: library, savedThreadIds: [fresh, older]),
            "once saved it is an ordinary conversation")
        XCTAssertNil(UserDefaults.standard.string(forKey: key), "and its record is dropped")
    }
}
