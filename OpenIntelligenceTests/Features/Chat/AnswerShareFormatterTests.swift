//
//  AnswerShareFormatterTests.swift
//  OpenIntelligenceTests
//
//  Through 5.6, Share on an answer sent its text alone: the `[S2]` labels went out and what they
//  pointed at stayed behind. These pin what leaves the app now: the answer, each cited document
//  with its page, and the app's name with the tagged App Store link.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class AnswerShareFormatterTests: XCTestCase {
    private let link = URL(string: "https://example.com/app")!

    private func chunk(_ text: String, _ document: String, page: Int?) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: page,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: false,
            hasListStructure: false,
            wordCount: text.split(separator: " ").count,
            characterCount: text.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9,
            rank: 1,
            sourceDocument: document,
            pageNumber: page
        )
    }

    private func evidence(_ chunk: RetrievedChunk) -> StructuredAnswer.Evidence {
        StructuredAnswer.Evidence(
            evidenceId: chunk.chunk.id.uuidString,
            page: chunk.pageNumber,
            quote: String(chunk.chunk.content.prefix(240)),
            documentName: chunk.sourceDocument,
            sectionPath: nil
        )
    }

    func testCitedAnswerListsEachLabelWithItsDocumentAndPage() {
        let chunks = [
            chunk("Rent is late after 11:59 p.m. on the 5th.", "Lease.pdf", page: 3),
            chunk("Quiet hours are 10:00 p.m. to 7:00 a.m. every day.", "Rules.pdf", page: 12),
        ]
        let text = AnswerShareFormatter.shareText(
            answer: "Quiet hours start at 10:00 p.m. [S2]. Rent is late after the 5th [S1].",
            evidence: chunks.map(evidence),
            retrievedChunks: chunks,
            appLink: link
        )
        XCTAssertEqual(
            text,
            """
            Quiet hours start at 10:00 p.m. [S2]. Rent is late after the 5th [S1].

            Sources:
            [S2] Rules.pdf, page 12
            [S1] Lease.pdf, page 3

            Answered with OpenIntelligence
            https://example.com/app
            """
        )
    }

    func testALabelCitedTwiceIsListedOnce() {
        let chunks = [chunk("Rent is late after the 5th. A late charge of $75.00 applies.", "Lease.pdf", page: 3)]
        let sources = AnswerShareFormatter.sources(
            answer: "Rent is late after the 5th [S1]. The late charge is $75.00 [S1].",
            evidence: chunks.map(evidence),
            retrievedChunks: chunks
        )
        XCTAssertEqual(sources, [AnswerShareFormatter.Source(label: "S1", document: "Lease.pdf", pages: [3])])
    }

    func testAnswerWithoutLabelsListsItsDocumentsOnceWithTheirPages() {
        let chunks = [
            chunk("Rent is late after the 5th.", "Lease.pdf", page: 7),
            chunk("Quiet hours are 10:00 p.m. to 7:00 a.m.", "Rules.pdf", page: nil),
            chunk("A late charge of $75.00 applies on the 6th.", "Lease.pdf", page: 3),
        ]
        let sources = AnswerShareFormatter.sources(
            answer: "Rent is late after the 5th and a $75.00 charge applies.",
            evidence: [],
            retrievedChunks: chunks
        )
        XCTAssertEqual(
            sources,
            [
                AnswerShareFormatter.Source(label: nil, document: "Lease.pdf", pages: [3, 7]),
                AnswerShareFormatter.Source(label: nil, document: "Rules.pdf", pages: []),
            ]
        )
        XCTAssertEqual(AnswerShareFormatter.line(for: sources[0]), "- Lease.pdf, pages 3, 7")
        XCTAssertEqual(AnswerShareFormatter.line(for: sources[1]), "- Rules.pdf")
    }

    func testAnswerWithNoPassagesCarriesOnlyTheAttribution() {
        let text = AnswerShareFormatter.shareText(
            answer: "I could not find that in your documents.\n",
            evidence: [],
            retrievedChunks: [],
            appLink: link
        )
        XCTAssertEqual(
            text, "I could not find that in your documents.\n\nAnswered with OpenIntelligence\nhttps://example.com/app")
    }

    func testAQuestionIsSharedAsTyped() {
        let question = ChatMessage(role: .user, content: "When is rent late?")
        XCTAssertEqual(AnswerShareFormatter.shareText(for: question), "When is rent late?")
    }

    func testAnAnswerMessageUsesTheTaggedAppStoreLink() {
        let answer = ChatMessage(role: .assistant, content: "Rent is late after the 5th.")
        let text = AnswerShareFormatter.shareText(for: answer)
        XCTAssertTrue(text.hasSuffix(OpenIntelligenceLinks.sharedAppStoreURL.absoluteString), text)
    }
}
