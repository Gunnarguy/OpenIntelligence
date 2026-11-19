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
}
