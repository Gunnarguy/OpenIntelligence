//
//  WordCountTests.swift
//  OpenIntelligenceTests
//
//  The Words figure and what the passages hold, for one file whose words are known (5.7, roadmap row
//  "Word counts look wrong and ingested text may be truncated"). The row asks for four counts: the
//  words in the file, in the text as it was read, in the stored passages, and the figure the app shows.
//  The import queue shows the document's own count (`ProcessingMetadata.totalWords`) since 5.7.
//

import XCTest

@testable import OpenIntelligenceEngine

final class WordCountTests: XCTestCase {
    /// 600 different words, ten to a line and fifty to a paragraph, so a word lost at a line break, a
    /// paragraph break or a passage's edge shows by name.
    private static let text: String = (0..<12).map { paragraph in
        (0..<5).map { line in
            (0..<10).map { "word\(paragraph * 50 + line * 10 + $0)" }.joined(separator: " ")
        }.joined(separator: "\n")
    }.joined(separator: "\n\n")

    func testWordsAreSplitAtLineBreaksToo() {
        XCTAssertEqual(DocumentProcessor.wordCount(of: Self.text), 600)
        XCTAssertEqual(DocumentProcessor.wordCount(of: "one\ntwo\tthree  four\r\nfive"), 5)
    }

    @MainActor
    func testAPlainTextFileIsCountedOnceAndNoWordIsLost() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wordcount-\(UUID().uuidString).txt")
        try Self.text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let (document, chunks) = try await DocumentProcessor().processDocument(at: url)

        XCTAssertEqual(document.processingMetadata?.totalWords, 600, "the figure the app shows counts each word once")
        let stored = Set(chunks.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) })
        let missing = (0..<600).map { "word\($0)" }.filter { !stored.contains($0) }
        XCTAssertTrue(missing.isEmpty, "every word is in a passage; missing \(missing.count): \(missing.prefix(10))")
        let passageWords = chunks.reduce(0) { $0 + DocumentProcessor.wordCount(of: $1.text) }
        XCTAssertGreaterThanOrEqual(passageWords, 600, "the passages hold every word, the ones two passages share twice")
    }
}
