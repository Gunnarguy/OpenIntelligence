//
//  ContinuationJoinTests.swift
//  OpenIntelligenceTests
//
//  An answer's continuation is joined so a new sentence does not run into the last word (5.8, 2026-11-19): on the
//  owner's iPhone "- 1 personal item" plus "The document lists the same allowance for each traveler." read
//  "1 personal itemThe document lists".
//

import XCTest

@testable import OpenIntelligence

final class ContinuationJoinTests: XCTestCase {
    private func join(_ a: String, _ b: String) -> String {
        AppleFoundationLLMService.joiningContinuation(a, b)
    }

    func testANewSentenceAfterAListItemStartsAParagraph() {
        XCTAssertEqual(
            join("- 1 carry-on\n- 1 personal item", "The document lists the same allowance for each traveler."),
            "- 1 carry-on\n- 1 personal item\n\nThe document lists the same allowance for each traveler.")
    }

    func testANewSentenceAfterAFullStopGetsASpace() {
        XCTAssertEqual(join("Rent is $1,675.", "It is due on the 1st."), "Rent is $1,675. It is due on the 1st.")
    }

    func testAWordCarriedOnIsJoinedAsBefore() {
        XCTAssertEqual(join("The landlord may ent", "er with notice."), "The landlord may enter with notice.")
    }

    func testWhiteSpaceOrPunctuationIsJoinedAsBefore() {
        XCTAssertEqual(join("The deposit is", " $300."), "The deposit is $300.")
        XCTAssertEqual(join("The deposit is $300", "."), "The deposit is $300.")
    }

    func testASplitNumberOrAcronymIsJoinedAsBefore() {
        XCTAssertEqual(join("Rent is $1,6", "75 a month."), "Rent is $1,675 a month.")
        XCTAssertEqual(join("It runs on PC", "C."), "It runs on PCC.")
    }

    func testANewListItemGoesOnItsOwnLine() {
        XCTAssertEqual(join("- 1 checked bag", "- 1 carry-on"), "- 1 checked bag\n- 1 carry-on")
    }

    /// A record saved before 5.8's written answer still loads, and a kept answer reads back (2026-11-19).
    func testAPendingRecordKeepsItsWrittenAnswer() throws {
        let old = #"{"messageId":"9F2C1D2E-0B7A-4C5D-8E1F-1A2B3C4D5E6F","question":"Q","mode":"standard","askedAt":0,"resumed":false}"#
        let decoded = try JSONDecoder().decode(PendingAnswerStore.Record.self, from: Data(old.utf8))
        XCTAssertNil(decoded.answer)
        var record = decoded
        record.answer = "The safe internal temperature for fish is 145°F [S2]."
        let round = try JSONDecoder().decode(PendingAnswerStore.Record.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(round.answer, record.answer)
    }
}
