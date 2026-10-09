//
//  JSONRecordExtractorTests.swift
//  OpenIntelligenceTests
//
//  The record reader on its own: what counts as a record, what a record's text looks like, and
//  that cutting the passages back out of the document's text never invents or loses one.
//

import XCTest

@testable import OpenIntelligenceEngine

final class JSONRecordExtractorTests: XCTestCase {

    // MARK: - What counts as a record

    func testEachLineOfJSONLinesIsARecordAndBlankLinesAreNot() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(
                from: "{\"a\": 1}\n\n   \n{\"a\": 2}\r\n{\"a\": 3}\n", fileExtension: "jsonl"))
        XCTAssertEqual(
            extraction.records,
            ["Record 1 of 3\na: 1", "Record 2 of 3\na: 2", "Record 3 of 3\na: 3"])
        XCTAssertEqual(extraction.unparsedLineCount, 0)
        XCTAssertEqual(extraction.text, "Record 1 of 3\na: 1\n\nRecord 2 of 3\na: 2\n\nRecord 3 of 3\na: 3")
    }

    func testALineThatIsNotJSONIsKeptAndCounted() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "{\"a\": 1}\nplain words\n", fileExtension: "ndjson"))
        XCTAssertEqual(extraction.records, ["Record 1 of 2\na: 1", "Record 2 of 2\nplain words"])
        XCTAssertEqual(extraction.unparsedLineCount, 1)
    }

    func testAFileWithNoJSONLineAtAllIsNotRecords() {
        XCTAssertNil(JSONRecordExtractor.extract(from: "plain words\nmore words\n", fileExtension: "jsonl"))
        XCTAssertNil(JSONRecordExtractor.extract(from: "  \n", fileExtension: "jsonl"))
    }

    func testAnObjectGivesItsPlainValuesFirstThenEachListElementAndEachNestedObject() throws {
        let json = """
            {
              "title": "Lease questions",
              "messages": [
                {"role": "user", "content": "When is rent late?"},
                {"role": "assistant", "content": "After the 5th."}
              ],
              "owner": {"name": "Sam", "unit": 12},
              "count": 2
            }
            """
        let extraction = try XCTUnwrap(JSONRecordExtractor.extract(from: json, fileExtension: "json"))
        XCTAssertEqual(
            extraction.records,
            [
                "Record 1 of 4\ntitle: Lease questions\ncount: 2",
                "Record 2 of 4\nmessages[1].role: user\nmessages[1].content: When is rent late?",
                "Record 3 of 4\nmessages[2].role: assistant\nmessages[2].content: After the 5th.",
                "Record 4 of 4\nowner.name: Sam\nowner.unit: 12",
            ])
    }

    /// JSON allows U+2028 raw inside a string. A line reader that treats it as a line end would cut
    /// one record into two broken ones and renumber every record after it.
    func testASeparatorCharacterInsideAStringDoesNotCutTheRecord() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(
                from: "{\"t\": \"a\u{2028}b\"}\n{\"t\": \"c\"}\n", fileExtension: "jsonl"))
        XCTAssertEqual(extraction.records, ["Record 1 of 2\nt: a\u{2028}b", "Record 2 of 2\nt: c"])
        XCTAssertEqual(extraction.unparsedLineCount, 0)
    }

    func testAByteOrderMarkIsNotTakenForBrokenJSON() throws {
        let lines = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "\u{FEFF}{\"a\": 1}\n{\"a\": 2}\n", fileExtension: "jsonl"))
        XCTAssertEqual(lines.unparsedLineCount, 0)
        XCTAssertEqual(lines.records.first, "Record 1 of 2\na: 1")
        XCTAssertNotNil(JSONRecordExtractor.extract(from: "\u{FEFF}[{\"a\": 1}]", fileExtension: "json"))
    }

    func testAJSONFileHoldingOneObjectPerLineIsReadAsLines() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "{\"a\": 1}\n{\"a\": 2}\n", fileExtension: "json"))
        XCTAssertEqual(extraction.records.count, 2)
    }

    func testBrokenJSONIsNotRecords() {
        XCTAssertNil(JSONRecordExtractor.extract(from: "{\"a\": 1,\n// note\n}", fileExtension: "json"))
        XCTAssertNil(JSONRecordExtractor.extract(from: "{\"a\": 1}\nnot json\n", fileExtension: "json"))
    }

    // MARK: - What a record's text looks like

    /// The file's own text is what gets stored: members in the file's order, a number with the
    /// digits the file has, and a null or empty member written out so its name is not lost.
    func testMembersKeepTheirOrderNumbersTheirDigitsAndEmptyOnesTheirNames() throws {
        let line = #"{"total": 12.50, "rate": 75.0, "big": 1e3, "on": true, "none": null, "blank": "", "list": [], "obj": {}, "deep": {"a": {"b": "c"}}, "rows": [[1, 2], [3]], "dup": 1, "dup": 2}"#
        let extraction = try XCTUnwrap(JSONRecordExtractor.extract(from: line, fileExtension: "jsonl"))
        XCTAssertEqual(
            extraction.records,
            [
                """
                Record 1 of 1
                total: 12.50
                rate: 75.0
                big: 1e3
                on: true
                none: null
                blank: ""
                list: []
                obj: {}
                deep.a.b: c
                rows[1]: 1, 2
                rows[2]: 3
                dup: 1
                dup: 2
                """
            ])
    }

    func testEscapesAreResolvedAndBadJSONIsRefused() {
        XCTAssertEqual(
            JSONValue.parse(#"{"u": "caf\u00e9 \ud83d\ude00", "q": "a \"b\" \/ c\td"}"#),
            .object([("u", .string("caf\u{00E9} \u{1F600}")), ("q", .string("a \"b\" / c\td"))]))
        for bad in [#"{"a":1,}"#, "[1 2]", #"{"a":01}"#, #""\x""#, #"{"a":1} x"#, "nul", "{'a':1}", #""\ud83d""#, ""] {
            XCTAssertNil(JSONValue.parse(bad), "\(bad) is not JSON and must not parse")
        }
    }

    /// A value's own line breaks stay, and its later lines are indented, so a line of a value that
    /// reads like the next record's header cannot move the cut.
    func testALineOfAValueThatReadsLikeAHeaderDoesNotMoveTheCut() throws {
        let line = #"{"content": "First line.\nRecord 2 of 2\nThird line."}"#
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: line + "\n{\"content\": \"Second\"}\n", fileExtension: "jsonl"))
        XCTAssertEqual(extraction.records[0], "Record 1 of 2\ncontent: First line.\n  Record 2 of 2\n  Third line.")
        let passages = try XCTUnwrap(JSONRecordExtractor.passages(in: extraction.text, expectedCount: 2))
        XCTAssertEqual(passages.map(\.text), extraction.records)
    }

    // MARK: - A record over the embedding limit

    /// Counts words, which is enough to exercise the cutting; the app passes its real tokenizer.
    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }

    func testARecordOverTheLimitIsCutAtItsLinesAndEveryPartNamesTheRecord() {
        let fields = (1...120).map { "field_\($0): value \($0) costs $75.50 per Lease.pdf page?" }
        let record = (["Record 7 of 9"] + fields).joined(separator: "\n")
        let parts = JSONRecordExtractor.parts(of: record, maxTokens: 100, countTokens: wordCount)

        XCTAssertGreaterThan(parts.count, 1)
        for (index, part) in parts.enumerated() {
            XCTAssertTrue(
                part.hasPrefix("Record 7 of 9, part \(index + 1) of \(parts.count)\n"),
                "part \(index + 1) does not start with the record's header: \(part.prefix(60))")
            XCTAssertLessThanOrEqual(wordCount(part), 100)
        }
        // Nothing is retyped: without the added header lines, the parts are the record's own lines.
        let body = parts.flatMap { $0.components(separatedBy: "\n").dropFirst() }
        XCTAssertEqual(body, fields)
    }

    func testARecordUnderTheLimitIsLeftAsItIs() {
        let record = "Record 1 of 1\nrole: user\ncontent: When is rent late?"
        XCTAssertEqual(JSONRecordExtractor.parts(of: record, maxTokens: 100, countTokens: wordCount), [record])
    }

    // MARK: - Cutting passages back out

    func testPassagesAreTheRecordsAndCoverTheWholeText() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "{\"a\": 1}\n{\"a\": 2}\n{\"a\": 3}\n", fileExtension: "jsonl"))
        let text = extraction.text
        let passages = try XCTUnwrap(JSONRecordExtractor.passages(in: text, expectedCount: 3))
        XCTAssertEqual(passages.map(\.text), extraction.records)
        XCTAssertEqual(passages.first?.range.lowerBound, text.startIndex)
        XCTAssertEqual(passages.last?.range.upperBound, text.endIndex)
        for (earlier, later) in zip(passages, passages.dropFirst()) {
            XCTAssertEqual(earlier.range.upperBound, later.range.lowerBound)
        }
    }

    func testAMissingHeaderMeansNoCutAtAll() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "{\"a\": 1}\n{\"a\": 2}\n{\"a\": 3}\n", fileExtension: "jsonl"))
        let damaged = extraction.text.replacingOccurrences(of: "Record 2 of 3", with: "Record 2 of3")
        XCTAssertNil(JSONRecordExtractor.passages(in: damaged, expectedCount: 3))
        XCTAssertNil(JSONRecordExtractor.passages(in: "preface\n" + extraction.text, expectedCount: 3))
        XCTAssertNil(JSONRecordExtractor.passages(in: extraction.text, expectedCount: 0))
    }
}
