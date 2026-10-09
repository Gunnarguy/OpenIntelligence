//
//  ConversationExporterTests.swift
//  OpenIntelligenceTests
//
//  A conversation exports as Markdown, for reading, and as JSON Lines, one object per message.
//  These pin both shapes, that hidden and system messages stay out, and that every exported line of
//  JSON Lines parses back, since the app imports that format as records.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ConversationExporterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let link = URL(string: "https://example.com/app")!
    private let asked = Date(timeIntervalSince1970: 1_791_522_000)  // 2026-10-09 05:00:00 UTC

    private func chunk(_ text: String, _ document: String, page: Int) -> RetrievedChunk {
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

    private func conversation() -> [ChatMessage] {
        var hidden = ChatMessage(role: .assistant, content: "A hidden answer.", timestamp: asked)
        hidden.isHidden = true
        return [
            ChatMessage(role: .system, content: "System note.", timestamp: asked),
            ChatMessage(role: .user, content: "When is rent late?", timestamp: asked),
            ChatMessage(
                role: .assistant,
                content: "Rent is late after 11:59 p.m. on the 5th [1].",
                timestamp: asked.addingTimeInterval(60),
                retrievedChunks: [chunk("Rent is late after 11:59 p.m. on the 5th.", "Lease.pdf", page: 3)]
            ),
            hidden,
        ]
    }

    func testMarkdownCarriesEachTurnAndItsSources() {
        let text = ConversationExporter.markdown(
            messages: conversation(),
            title: "When is rent late?",
            exportedAt: asked.addingTimeInterval(120),
            timeZone: utc,
            appLink: link
        )
        XCTAssertEqual(
            text,
            """
            # When is rent late?

            Exported from OpenIntelligence on 2026-10-09 05:02. 2 messages.

            ## You, 2026-10-09 05:00

            When is rent late?

            ## OpenIntelligence, 2026-10-09 05:01

            Rent is late after 11:59 p.m. on the 5th [1].

            Sources:
            [1] Lease.pdf, page 3

            ---

            https://example.com/app

            """
        )
    }

    func testJSONLinesIsOneParsableObjectPerKeptMessage() throws {
        let text = ConversationExporter.jsonLines(messages: conversation())
        XCTAssertTrue(text.hasSuffix("\n"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)

        let records = try lines.map { line -> [String: Any] in
            try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(records[0]["role"] as? String, "user")
        XCTAssertEqual(records[0]["content"] as? String, "When is rent late?")
        XCTAssertEqual(records[0]["timestamp"] as? String, "2026-10-09T05:00:00Z")
        XCTAssertNil(records[0]["sources"])

        XCTAssertEqual(records[1]["role"] as? String, "assistant")
        let sources = try XCTUnwrap(records[1]["sources"] as? [[String: Any]])
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0]["label"] as? String, "1")
        XCTAssertEqual(sources[0]["document"] as? String, "Lease.pdf")
        XCTAssertEqual(sources[0]["pages"] as? [Int], [3])
    }

    func testAnAnswerWithLineBreaksStaysOnOneLine() {
        let messages = [ChatMessage(role: .assistant, content: "First line.\nSecond line.", timestamp: asked)]
        let text = ConversationExporter.jsonLines(messages: messages)
        XCTAssertEqual(text.split(separator: "\n", omittingEmptySubsequences: false).count, 2, text)
        XCTAssertTrue(text.contains(#"First line.\nSecond line."#), text)
    }

    func testAnEmptyConversationExportsNoLines() {
        XCTAssertEqual(ConversationExporter.jsonLines(messages: []), "")
    }

    func testFileNameDropsCharactersAFileSystemRefusesAndKeepsTheExtension() {
        XCTAssertEqual(
            ConversationExporter.fileName(
                title: "Rent: late/when?\nAnd how much", format: .markdown, date: asked, timeZone: utc),
            "Rent late when And how much 2026-10-09.md"
        )
        XCTAssertEqual(
            ConversationExporter.fileName(title: "  ", format: .jsonLines, date: asked, timeZone: utc),
            "Conversation 2026-10-09.jsonl"
        )
    }

    func testALongFirstQuestionIsCutForTheTitle() {
        let long = String(repeating: "word ", count: 40)
        let text = ConversationExporter.markdown(
            messages: [], title: long, exportedAt: asked, timeZone: utc, appLink: link)
        let heading = String(text.split(separator: "\n").first ?? "")
        XCTAssertTrue(heading.hasSuffix("..."), heading)
        XCTAssertLessThanOrEqual(heading.count, 2 + ConversationExporter.maxTitleLength + 3)
    }

    func testWritingAFileGivesAnAddressWithTheSameText() throws {
        let url = try ConversationExporter.writeTemporaryFile(
            messages: conversation(), title: "Rent", format: .jsonLines, date: asked)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "jsonl")
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), ConversationExporter.jsonLines(messages: conversation()))
    }
}
