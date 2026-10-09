//
//  EvidenceLineSplitterTests.swift
//  OpenIntelligenceTests
//
//  The evidence filter chooses which sentences of a passage the model sees. Through 5.6 it cut a
//  passage at every line break and at every ". ", so "on the 5th" could be kept without "Rent is
//  late after 11:59 p.m.". These pin that a sentence stays whole and that tables, headings and
//  lists are still taken line by line.
//

import XCTest

@testable import OpenIntelligenceEngine

final class EvidenceLineSplitterTests: XCTestCase {

    // MARK: - Sentences

    func testASentenceIsNotCutAtAnAbbreviationOrAnAmount() {
        XCTAssertEqual(
            EvidenceLineSplitter.units(
                in: "Rent is late after 11:59 p.m. on the 5th. A late charge of $75.00 applies on the 6th."),
            ["Rent is late after 11:59 p.m. on the 5th.", "A late charge of $75.00 applies on the 6th."]
        )
    }

    func testATableRowIsKeptWhole() {
        let row = "E1 | Temperature sensor open circuit. Unplug the unit. | Call service"
        XCTAssertEqual(EvidenceLineSplitter.units(in: row), [row])
        let spaced = "Basket capacity  5.8 qt. Nonstick."
        XCTAssertEqual(EvidenceLineSplitter.units(in: spaced), [spaced])
    }

    func testALineWithNothingLongEnoughIsKeptWhole() {
        XCTAssertEqual(EvidenceLineSplitter.units(in: "Yes. No."), ["Yes. No."])
    }

    // MARK: - Lines

    func testASentenceWrappedOverTwoLinesIsJoined() {
        let passage = """
            Rent is due on the 1st of each month and is late after 11:59 p.m.
            on the 5th. A late charge of $75.00 applies
            on the 6th.
            """
        XCTAssertEqual(
            EvidenceLineSplitter.lines(in: passage),
            [
                "Rent is due on the 1st of each month and is late after 11:59 p.m. on the 5th. A late charge of $75.00 applies on the 6th."
            ]
        )
    }

    func testAHeadingStaysOnItsOwnLine() {
        let passage = """
            Cleaning
            hand wash the basket after every use and dry it before storing it away
            """
        XCTAssertEqual(
            EvidenceLineSplitter.lines(in: passage),
            ["Cleaning", "hand wash the basket after every use and dry it before storing it away"]
        )
    }

    func testListsTablesAndFinishedSentencesAreNotJoined() {
        let passage = """
            The basket and the drip tray can be cleaned in these ways, in order of preference:
            - hand wash with warm water
            - dishwasher, top rack only
            Code | Meaning and what to do about it when it shows up on the display panel
            e1 | sensor open circuit
            The unit must be unplugged before any cleaning is started on the heating element.
            never immerse the base.
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: passage).count, 7)
    }

    /// The fields of an imported JSON record start lowercase and can be long. Joining them would
    /// run one field into the next.
    func testTheFieldsOfARecordAreNotJoined() {
        let record = """
            Record 2 of 4
            content: Rent is late after 11:59 p.m. on the 5th of the month
            model: on-device
            role: assistant
            sources[1].document: Lease.pdf
            timestamp: 2026-10-01T09:00:00Z
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: record).count, 6)
        XCTAssertTrue(EvidenceLineSplitter.isFieldLine("model: on-device"))
        XCTAssertTrue(EvidenceLineSplitter.isFieldLine("retries = 3"))
        XCTAssertFalse(EvidenceLineSplitter.isFieldLine("on the 5th of each month."))
    }

    func testFieldNamesWithSpacesOrAccentsAndLetteredItemsAreNotJoined() {
        XCTAssertTrue(EvidenceLineSplitter.isFieldLine("monthly rent: 1200"))
        XCTAssertTrue(EvidenceLineSplitter.isFieldLine("date of birth: 1990-01-01"))
        XCTAssertTrue(EvidenceLineSplitter.isFieldLine("\u{00E9}tat: actif"))
        XCTAssertTrue(EvidenceLineSplitter.isLetteredItem("a) under $20,000"))
        XCTAssertTrue(EvidenceLineSplitter.isLetteredItem("b. pay the rent"))
        XCTAssertFalse(EvidenceLineSplitter.isLetteredItem("a neighboring unit."))

        let list = """
            The tenant qualifies for the reduced deposit when household income is,
            a) under $20,000 with one dependent, or
            b) under $30,000 with two or more
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: list).count, 3)

        let fields = """
            the lease starts on the first day of the month named below and
            monthly rent: 1200
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: fields).count, 2)
    }

    /// Rows without a table mark end in a figure, not in a word.
    func testRowsThatEndInAFigureAreNotJoined() {
        let rows = """
            monthly rent for the two bedroom apartment $1,200
            pet deposit, refundable at the end of the lease $300
            parking space, covered, one vehicle only $75
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: rows).count, 3)
    }

    func testALineThatEndsASentenceIsNotJoinedToALowercaseLine() {
        let passage = """
            The unit must be unplugged before any cleaning is started on the element.
            never immerse the base in water or any other liquid at any time
            """
        XCTAssertEqual(EvidenceLineSplitter.lines(in: passage).count, 2)
    }

    func testABlankLineAlwaysEndsALine() {
        let passage = "The tenant shall keep the premises clean and in good order throughout\n\nand shall not sublet."
        XCTAssertEqual(
            EvidenceLineSplitter.lines(in: passage),
            ["The tenant shall keep the premises clean and in good order throughout", "and shall not sublet."]
        )
    }

    func testVeryShortLinesAreStillDropped() {
        XCTAssertEqual(EvidenceLineSplitter.lines(in: "ok\n\n12\nA full line of text."), ["A full line of text."])
    }

    func testNoCharacterOfAWrappedParagraphIsLost() {
        let passage = """
            Quiet hours are 10:00 p.m. to 7:00 a.m. every day, and during those hours
            residents must keep noise below the level that carries into
            a neighboring unit.
            """
        let joined = EvidenceLineSplitter.lines(in: passage).joined(separator: " ")
        XCTAssertEqual(
            joined.filter { !$0.isWhitespace }, passage.filter { !$0.isWhitespace })
    }
}
