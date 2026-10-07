//
//  AnswerSentenceSplitterTests.swift
//  OpenIntelligenceTests
//
//  On 5.5 an answer that quoted "$300.00" showed "$300. 00", and "10:00 p.m." showed "10:00 p."
//  The answer cleanup split on every period and joined the pieces back with ". ". These pin the
//  splitter that replaced that, and the one property the cleanup now rests on: the sentences are
//  runs of the original text, unchanged, with only whitespace between them.
//

import XCTest

@testable import OpenIntelligenceEngine

final class AnswerSentenceSplitterTests: XCTestCase {
    /// The sentences are consecutive runs of the text, unchanged, with only whitespace between them.
    private func assertRoundTrips(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for sentence in AnswerSentenceSplitter.sentences(in: text) {
            guard let range = text.range(of: sentence, range: cursor..<text.endIndex) else {
                XCTFail("\"\(sentence)\" is not a run of the original text", file: file, line: line)
                return
            }
            XCTAssertTrue(
                text[cursor..<range.lowerBound].allSatisfy(\.isWhitespace),
                "text was skipped before \"\(sentence)\"", file: file, line: line)
            cursor = range.upperBound
        }
        XCTAssertTrue(text[cursor...].allSatisfy(\.isWhitespace), "text was dropped at the end", file: file, line: line)
    }

    func testMoneyAndTimesAreNeverCut() {
        let text = "The pet deposit is $300.00. Quiet hours are 10:00 p.m. every day. The late charge is $75.00!"
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: text),
            [
                "The pet deposit is $300.00.",
                "Quiet hours are 10:00 p.m. every day.",
                "The late charge is $75.00!",
            ]
        )
        assertRoundTrips(text)
    }

    func testTheThreeValuesTheRoadmapRowNames() {
        // "Closes when an answer quoting $300.00, 6:50 p.m. and Section 16. shows all three unchanged."
        let text =
            "The deposit is $300.00 and the gate closes at 6:50 p.m. on weekdays. See Section 16. It caps the fee at $150.00."
        let sentences = AnswerSentenceSplitter.sentences(in: text)
        XCTAssertEqual(sentences.count, 3)
        XCTAssertTrue(sentences[0].contains("$300.00"))
        XCTAssertTrue(sentences[0].contains("6:50 p.m."))
        XCTAssertEqual(sentences[1], "See Section 16.")
        assertRoundTrips(text)
    }

    func testDecimalsAbbreviationsAndDomains() {
        let text =
            "Bake at **350°F** for 60 to 65 minutes, e.g. in a loaf pan. It holds 4.5 L. See Dr. Smith at example.com for more."
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: text),
            [
                "Bake at **350°F** for 60 to 65 minutes, e.g. in a loaf pan.",
                "It holds 4.5 L.",
                "See Dr. Smith at example.com for more.",
            ]
        )
        assertRoundTrips(text)
    }

    func testQuestionsShortSentencesAndQuotes() {
        let text = "Is a burst pipe covered? Yes. He said \"stop.\" Then he left."
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: text),
            ["Is a burst pipe covered?", "Yes.", "He said \"stop.\"", "Then he left."]
        )
        assertRoundTrips(text)
    }

    func testTextWithoutAClosingMarkIsOneSentence() {
        XCTAssertEqual(AnswerSentenceSplitter.sentences(in: "No terminator at all"), ["No terminator at all"])
        XCTAssertEqual(AnswerSentenceSplitter.sentences(in: ""), [])
        XCTAssertEqual(AnswerSentenceSplitter.sentences(in: "  \n "), [])
    }

    func testAWrongSplitStillRoundTrips() {
        // "Oct." is not in the abbreviation list and a digit follows, so this splits where a
        // reader would not. And "p.m." never ends a sentence, so the line break after it stays
        // inside one. The pieces are still the original text, which is why a wrong split cannot
        // change an answer unless one of its pieces is dropped as a duplicate.
        let text = "J. Smith signed on Oct. 9 at 6:50 p.m.\nThe gate closes at 7."
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: text),
            ["J. Smith signed on Oct.", "9 at 6:50 p.m.\nThe gate closes at 7."]
        )
        assertRoundTrips(text)
    }

    func testASingleLetterIsAnInitialUnlessItFollowsANumber() {
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: "The lease names J. Smith as agent. He signed it."),
            ["The lease names J. Smith as agent.", "He signed it."]
        )
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: "The tank holds 4.5 L. Fill it to the line."),
            ["The tank holds 4.5 L.", "Fill it to the line."]
        )
        // A lowercase word after the unit continues the sentence.
        XCTAssertEqual(
            AnswerSentenceSplitter.sentences(in: "Add 250 g. of flour and stir."),
            ["Add 250 g. of flour and stir."]
        )
    }

    // MARK: - Numbers and codes mark different facts

    func testSentencesThatDifferOnlyInACodeCarryDifferentIdentifiers() {
        // The air fryer manual: the near-duplicate pass saw these as one sentence said twice.
        let e1 = AnswerSentenceSplitter.identifierTokens(in: "**E1** indicates a temperature sensor open circuit.")
        let e2 = AnswerSentenceSplitter.identifierTokens(in: "**E2** indicates a temperature sensor short circuit.")
        XCTAssertEqual(e1, ["e1"])
        XCTAssertEqual(e2, ["e2"])
        XCTAssertNotEqual(e1, e2)
    }

    func testAmountsDatesAndTimesAreIdentifiers() {
        XCTAssertEqual(
            AnswerSentenceSplitter.identifierTokens(in: "A late charge of $75.00 applies on the 6th, after 11:59 p.m."),
            ["$75.00", "6th", "11:59"]
        )
        XCTAssertTrue(AnswerSentenceSplitter.identifierTokens(in: "Quiet hours apply every day.").isEmpty)
    }
}
