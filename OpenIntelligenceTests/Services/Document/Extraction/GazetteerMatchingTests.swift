//
//  GazetteerMatchingTests.swift
//  OpenIntelligenceTests
//
//  Gazetteer terms match a question as whole words (5.7). A substring match put "RE PA DO ARE TWO" on the end of a
//  Deep Think keyword search for "Compare the two documents in this library" on the owner's iPhone.
//

@testable import OpenIntelligence
import XCTest

final class GazetteerMatchingTests: XCTestCase {
    private let question = GazetteerService.words(in: "Compare the two documents in this library")

    func testFragmentsInsideWordsDoNotMatch() {
        for fragment in ["PA", "RE", "DO", "TW", "MP", "RA"] {
            XCTAssertFalse(GazetteerService.term(fragment, matches: question), fragment)
        }
    }

    func testAnAllCapsTermIsAnAbbreviationAndNeedsTheSameCapitals() {
        XCTAssertFalse(GazetteerService.term("THIS", matches: question))
        XCTAssertFalse(GazetteerService.term("TWO", matches: question))
        XCTAssertTrue(GazetteerService.term("MCI", matches: GazetteerService.words(in: "What raises MCI risk?")))
    }

    func testOrdinaryTermsMatchWholeWordsAndPhrasesIgnoringCase() {
        XCTAssertTrue(GazetteerService.term("library", matches: question))
        XCTAssertTrue(GazetteerService.term("Mild cognitive impairment",
            matches: GazetteerService.words(in: "Does mild cognitive impairment progress?")))
        XCTAssertFalse(GazetteerService.term("cognitive mild",
            matches: GazetteerService.words(in: "Does mild cognitive impairment progress?")))
    }
}
