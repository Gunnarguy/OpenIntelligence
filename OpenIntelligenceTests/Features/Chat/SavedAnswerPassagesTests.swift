//
//  SavedAnswerPassagesTests.swift
//  OpenIntelligenceTests
//
//  A saved answer keeps every passage its labels cite (5.7). Through 5.6 it kept the first 12, so after a
//  relaunch a tap on [S13] opened nothing and Copy left that label out of its source list.
//

import XCTest

@testable import OpenIntelligence

final class SavedAnswerPassagesTests: XCTestCase {
    private func chunks(_ count: Int) -> [RetrievedChunk] {
        (1...count).map { index in
            let text = "Passage number \(index)."
            let metadata = ChunkMetadata(
                chunkIndex: index - 1,
                pageNumber: nil,
                sectionTitle: nil,
                keywords: [],
                hasNumericData: false,
                hasListStructure: false,
                wordCount: 2,
                characterCount: text.count
            )
            return RetrievedChunk(
                chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
                similarityScore: 0.9,
                rank: index,
                sourceDocument: "Manual.pdf"
            )
        }
    }

    func testAnAnswerCitingS13KeepsItsThirteenthPassage() {
        let message = ChatMessage(
            role: .assistant, content: "E1 means the sensor is open [S13].", retrievedChunks: chunks(22))
        let saved = message.sanitizedForPersistence()
        XCTAssertEqual(saved.retrievedChunks?.count, 13)
        XCTAssertEqual(saved.retrievedChunks?.last?.chunk.content, "Passage number 13.")
    }

    func testAnAnswerCitingFewKeepsTheFirstTwelve() {
        let message = ChatMessage(
            role: .assistant, content: "Rent is due on the 1st [S1].", retrievedChunks: chunks(22))
        XCTAssertEqual(message.sanitizedForPersistence().retrievedChunks?.count, 12)
    }

    func testEveryLabelFormCounts() {
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "Both say so [S2, S17].", available: 30), 17)
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "It does (S15).", available: 30), 15)
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "Both [S1, 14].", available: 30), 14)
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "From [S1] through [S16].", available: 30), 16)
        XCTAssertEqual(
            ChatMessage.persistedChunkCount(content: "Model S20 is mentioned.", available: 30), 12,
            "a model name is not a label")
    }

    func testTheCountIsBoundedByWhatTheAnswerHasAndByTheCap() {
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "See [S40].", available: 20), 20)
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "See [S900].", available: 1000), 64)
        XCTAssertEqual(ChatMessage.persistedChunkCount(content: "See [S1].", available: 5), 5)
    }
}
