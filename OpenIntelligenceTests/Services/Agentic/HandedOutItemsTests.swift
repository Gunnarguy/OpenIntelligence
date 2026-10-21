//
//  HandedOutItemsTests.swift
//  OpenIntelligenceTests
//
//  Answers and passages an action hands to Shortcuts are kept for a day and looked up again by id
//  (5.7). Handed out whole, they stopped the next step of a shortcut in the iOS 27.0 Simulator
//  (Copy to Clipboard's runner asserted); documents, looked up by id, did not. These pin the store
//  and the look-ups the system makes.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class HandedOutItemsTests: XCTestCase {
    private var folder: URL!
    private var originalURL: (() -> URL)!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HandedOutItemsTests-\(UUID().uuidString)")
        originalURL = HandedOutItems.fileURL
        let file = folder.appendingPathComponent("handed_out_items.json")
        HandedOutItems.fileURL = { file }
        HandedOutItems.forgetCache()
    }

    override func tearDown() async throws {
        HandedOutItems.fileURL = originalURL
        HandedOutItems.forgetCache()
        try? FileManager.default.removeItem(at: folder)
    }

    private func passage(_ text: String, document: UUID? = nil, at date: Date) -> HandedOutItems.Passage {
        HandedOutItems.Passage(
            id: UUID(), documentId: document, text: text, documentName: "a.pdf", page: nil, section: nil, score: 0.5,
            createdAt: date)
    }

    /// What the file itself holds, read past the copy in memory.
    private func onDisk() throws -> HandedOutItems.Contents {
        HandedOutItems.forgetCache()
        let data = try Data(contentsOf: HandedOutItems.fileURL())
        return try JSONDecoder().decode(HandedOutItems.Contents.self, from: data)
    }

    private func chunk(_ text: String, _ document: String, page: Int?, score: Float) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: text, embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0, pageNumber: page, sectionTitle: "Pets")),
            similarityScore: score,
            rank: 1,
            sourceDocument: document,
            pageNumber: page
        )
    }

    private func response(_ answer: String, _ chunks: [RetrievedChunk]) -> RAGResponse {
        RAGResponse(
            queryId: UUID(),
            retrievedChunks: chunks,
            generatedResponse: answer,
            metadata: ResponseMetadata(
                totalGenerationTime: 0, tokensGenerated: 0, modelUsed: "Apple Intelligence", retrievalTime: 0)
        )
    }

    func testAnAnswerIsFoundAgainByItsIdWithItsPassages() async throws {
        let chunks = [
            chunk("Each pet requires a refundable pet deposit of $300.00.", "Lease.pdf", page: 4, score: 0.71),
            chunk("Tenant may keep up to two cats.", "Lease.pdf", page: 4, score: 0.52),
        ]
        let answer = OIAnswerEntity(
            question: "How much is the pet deposit?", response: response("The pet deposit is $300.00.", chunks),
            mode: .standard)

        let found = try await OIAnswerEntityQuery().entities(for: [answer.id])
        let again = try XCTUnwrap(found.first)
        XCTAssertEqual(again.id, answer.id)
        XCTAssertEqual(again.text, "The pet deposit is $300.00.")
        XCTAssertEqual(again.question, "How much is the pet deposit?")
        XCTAssertEqual(again.sourceList, "- Lease.pdf, page 4")
        XCTAssertEqual(again.mode, .standard)
        XCTAssertEqual(again.model, "Apple Intelligence")
        XCTAssertEqual(again.passages.map(\.id), answer.passages.map(\.id))
        XCTAssertEqual(again.passages.map(\.text), chunks.map(\.chunk.content))
        XCTAssertEqual(again.textWithSources, answer.textWithSources, "another app gets the same text")
    }

    func testFoundPassagesAreFoundAgainByTheirIds() async throws {
        let passages = OIPassageEntity.handedOut([
            chunk("Rent is late after the 5th.", "Lease.pdf", page: 3, score: 0.64),
            chunk("Quiet hours start at 10:00 p.m.", "Rules.pdf", page: nil, score: 0.41),
        ])
        let found = try await OIPassageEntityQuery().entities(for: passages.map(\.id).reversed())
        XCTAssertEqual(found.map(\.textWithSource), passages.reversed().map(\.textWithSource), "in the order asked")
        XCTAssertEqual(found.first?.score ?? 0, 0.41, accuracy: 0.0001)
    }

    func testAnUnknownIdFindsNothing() async throws {
        let found = try await OIAnswerEntityQuery().entities(for: [UUID()])
        XCTAssertTrue(found.isEmpty)
    }

    func testItemsOlderThanADayAreDropped() {
        let now = Date()
        let old = passage("old", at: now.addingTimeInterval(-HandedOutItems.keptFor - 1))
        let fresh = passage("fresh", at: now)
        HandedOutItems.record(passages: [old, fresh], now: now)
        XCTAssertEqual(HandedOutItems.passages([old.id, fresh.id], now: now).map(\.text), ["fresh"])
    }

    func testAnItemPastItsDayLeavesTheFileWhenTheFileIsRead() throws {
        let start = Date()
        let item = passage("Each pet requires a refundable pet deposit of $300.00.", at: start)
        HandedOutItems.record(passages: [item], now: start)
        XCTAssertEqual(try onDisk().passages.count, 1)

        let later = start.addingTimeInterval(HandedOutItems.keptFor + 60)
        XCTAssertTrue(HandedOutItems.passages([item.id], now: later).isEmpty)
        XCTAssertTrue(try onDisk().passages.isEmpty, "not only hidden: gone from the file")

        HandedOutItems.record(passages: [passage("again", at: start)], now: start)
        HandedOutItems.dropExpired(now: later)
        XCTAssertTrue(try onDisk().passages.isEmpty, "the document load's sweep removes it too")
    }

    func testAPassageOfADeletedDocumentGoesWithTheAnswersThatUsedIt() throws {
        let now = Date()
        let lease = UUID(), rules = UUID()
        let fromLease = passage("Rent is late after the 5th.", document: lease, at: now)
        let fromRules = passage("Quiet hours start at 10:00 p.m.", document: rules, at: now)
        let answer = HandedOutItems.Answer(
            id: UUID(), question: "When is rent late?", text: "After the 5th.", sourceList: "- Lease.pdf",
            mode: "standard", model: "", passageIds: [fromLease.id], createdAt: now)
        HandedOutItems.record(answer: answer, passages: [fromLease, fromRules], now: now)

        HandedOutItems.keepOnly(documents: [rules], now: now)
        let kept = try onDisk()
        XCTAssertEqual(kept.passages.map(\.text), ["Quiet hours start at 10:00 p.m."])
        XCTAssertTrue(kept.answers.isEmpty, "the answer drew on the deleted document")
    }

    func testAKeptAnswerKeepsItsPassagesPastTheLooseLimit() {
        let now = Date()
        let own = (0..<3).map { passage("answer's \($0)", at: now) }
        let answer = HandedOutItems.Answer(
            id: UUID(), question: "q", text: "a", sourceList: "", mode: "standard", model: "",
            passageIds: own.map(\.id), createdAt: now)
        HandedOutItems.record(answer: answer, passages: own, now: now)
        let loose = (0..<(HandedOutItems.maxLoosePassages + 5)).map { passage("found \($0)", at: now) }
        HandedOutItems.record(passages: loose, now: now)

        XCTAssertEqual(HandedOutItems.passages(own.map(\.id), now: now).count, 3, "the answer's passages stay")
        XCTAssertTrue(HandedOutItems.passages(Array(loose.prefix(5)).map(\.id), now: now).isEmpty, "the oldest loose ones go")
        XCTAssertEqual(HandedOutItems.passages([loose.last!.id], now: now).count, 1)
    }

    func testTheOldestAnswersGoPastTheLimit() {
        let now = Date()
        var ids: [UUID] = []
        for number in 0..<(HandedOutItems.maxAnswers + 3) {
            let answer = HandedOutItems.Answer(
                id: UUID(), question: "q\(number)", text: "a\(number)", sourceList: "", mode: "standard", model: "",
                passageIds: [], createdAt: now)
            ids.append(answer.id)
            HandedOutItems.record(answer: answer, passages: [], now: now)
        }
        XCTAssertTrue(HandedOutItems.answers(Array(ids.prefix(3)), now: now).isEmpty, "the first three were dropped")
        XCTAssertEqual(HandedOutItems.answers([ids.last!], now: now).first?.text, "a\(HandedOutItems.maxAnswers + 2)")
        XCTAssertEqual(HandedOutItems.recentAnswers(limit: 1, now: now).first?.id, ids.last, "newest first")
    }
}
