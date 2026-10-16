//
//  AtlasContentCategoryTests.swift
//  OpenIntelligenceTests
//
//  The Atlas's content categories (5.7, `ContentCategory.of(terms:keywords:)`): whole words from the passage's word
//  list, worked out off the main actor. Through 5.6 each word was searched for inside the passage's text, so "api"
//  matched "capital" and "code" matched "barcode".
//

import XCTest

@testable import OpenIntelligence

final class AtlasContentCategoryTests: XCTestCase {
    private func category(_ text: String, keywords: [String] = []) -> ContentCategory {
        ContentCategory.of(terms: AtlasLabeling.terms(in: text), keywords: keywords)
    }

    func testAWordInsideAnotherWordIsNotThatWord() {
        XCTAssertEqual(category("The capital gains were reported on time."), .mixed, "api is not in capital")
        XCTAssertEqual(category("Scan the barcode on the label."), .mixed, "code is not in barcode")
        XCTAssertEqual(category("The metadata panel opens on the left."), .mixed, "data is not in metadata")
    }

    func testEachCategoryIsFoundByItsWords() {
        XCTAssertEqual(category("The API returns the result as JSON."), .technical)
        XCTAssertEqual(category("Both contracts were signed in March."), .legal, "a plural counts")
        XCTAssertEqual(category("Our findings support the hypothesis."), .academic)
        XCTAssertEqual(category("Revenue grew in the third quarter."), .business)
        XCTAssertEqual(category("Water the fern twice a week."), .mixed)
    }

    func testThePluralsAndLongerWordsTheOldSearchCaughtStillCount() {
        XCTAssertEqual(category("The database schema stores each record."), .technical)
        XCTAssertEqual(category("Error codes are listed in the appendix."), .technical)
        XCTAssertEqual(category("Our researchers ran it twice."), .academic)
        XCTAssertEqual(category("The marketing plan starts in May."), .business)
        XCTAssertEqual(category("Both abstracts were short."), .academic)
    }

    func testAKeywordCountsForTechnicalAndTheOrderHolds() {
        XCTAssertEqual(category("Plain words about the garden.", keywords: ["Software"]), .technical)
        XCTAssertEqual(category("The software contract was signed."), .technical, "technical is tried first")
    }
}
