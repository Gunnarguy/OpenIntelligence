//
//  OversizedChunkSplitterTests.swift
//  OpenIntelligenceTests
//
//  A passage over the embedding token limit is cut into parts at import. Through 5.6 the cut split
//  at every ".", "!", "?" and line break and joined the pieces with ". ", so the stored passage read
//  "$75. 50" and "Lease. pdf". These pin that the parts are the passage's own text.
//

import XCTest

@testable import OpenIntelligenceEngine

final class OversizedChunkSplitterTests: XCTestCase {
    /// Counts words, which is enough to exercise the cutting; the app passes its real tokenizer.
    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }

    private let opening = "The fee is $75.50. Is Lease.pdf signed? Yes! It was signed at 6:50 p.m. on the 5th."

    func testAmountsFileNamesTimesAndQuestionMarksSurviveTheCut() {
        let passage =
            opening + "\n"
            + String(repeating: "Rent is late after 11:59 p.m. on the 5th and a charge of $75.50 applies. ", count: 30)
        let parts = OversizedChunkSplitter.parts(of: passage, maxTokens: 60, countTokens: wordCount)

        XCTAssertGreaterThan(parts.count, 1)
        for part in parts {
            XCTAssertLessThanOrEqual(wordCount(part), 60)
        }
        let joined = parts.joined(separator: " ")
        XCTAssertFalse(joined.contains("75. 50"))
        XCTAssertFalse(joined.contains("Lease. pdf"))
        XCTAssertTrue(joined.contains("Is Lease.pdf signed? Yes!"))
        XCTAssertEqual(joined.filter { !$0.isWhitespace }, passage.filter { !$0.isWhitespace }, "no character was added or lost")
    }

    func testLinesKeepTheirLineBreaks() {
        let rows = (1...40).map { "Row \($0) | torque 12.5 Nm | check every 500 hours" }
        let parts = OversizedChunkSplitter.parts(of: rows.joined(separator: "\n"), maxTokens: 50, countTokens: wordCount)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.flatMap { $0.components(separatedBy: "\n") }, rows)
    }

    func testASentenceLongerThanAPartIsCutBetweenWords() {
        let sentence = (1...200).map { "word\($0)" }.joined(separator: " ") + "."
        let parts = OversizedChunkSplitter.parts(of: sentence, maxTokens: 40, countTokens: wordCount)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.joined(separator: " "), sentence)
    }

    /// Text with no spaces (Chinese or Japanese prose, a base64 block) has no word to cut at. It is
    /// cut by characters, so no part is left over the limit for the embedding to truncate.
    func testARunWithNoSpacesIsCutByCharacters() {
        let run = String(repeating: "\u{6F22}\u{5B57}", count: 400)
        // One token per character here, as a tokenizer roughly gives for such text.
        let parts = OversizedChunkSplitter.parts(of: run, maxTokens: 100, countTokens: { $0.count })
        XCTAssertGreaterThan(parts.count, 1)
        for part in parts { XCTAssertLessThanOrEqual(part.count, 100) }
        XCTAssertEqual(parts.joined().filter { !$0.isWhitespace }, run)
    }

    func testAPassageUnderTheLimitIsReturnedAsItIs() {
        XCTAssertEqual(OversizedChunkSplitter.parts(of: opening, maxTokens: 60, countTokens: wordCount), [opening])
    }
}
