//
//  VisualDocumentSearchTests.swift
//  OpenIntelligenceTests
//
//  Visual Intelligence searches the libraries for the words in a picture (5.7). The query itself
//  needs the Visual Intelligence framework, which the iOS Simulator's SDK does not have; the words
//  it searches for are picked here, where the suite can run them.
//

import XCTest

@testable import OpenIntelligence

final class VisualDocumentSearchTests: XCTestCase {
    func testModelNumbersComeFirstThenLongWordsThenLabels() {
        let terms = VisualSearchTerms.from(
            text: "Philips IntelliVue MX450 patient monitor. Model MX450, serial SN-77A1. Use with the cable.",
            labels: ["monitor", "medical device"])
        XCTAssertEqual(Array(terms.prefix(3)), ["mx450", "sn-77a1", "intellivue"])
        XCTAssertEqual(Array(terms.suffix(2)), ["medical", "device"], "a label word the text already gave is not repeated")
        XCTAssertFalse(terms.contains("the"))
        XCTAssertFalse(terms.contains("use"))
        XCTAssertEqual(terms.filter { $0 == "mx450" }.count, 1)
    }

    func testANameMatchesWholeWordsAndNotItsExtension() {
        let terms = ["pdf", "mx450", "sn-77a1"]
        XCTAssertFalse(VisualSearchTerms.nameMatches("a.pdf", terms: terms), "a screenshot's \"PDF\" matches no file by its type")
        XCTAssertFalse(VisualSearchTerms.nameMatches("Lease.pdf", terms: terms))
        XCTAssertTrue(VisualSearchTerms.nameMatches("MX450-service-manual.pdf", terms: terms))
        XCTAssertTrue(VisualSearchTerms.nameMatches("Notes on SN-77A1.txt", terms: terms))
        XCTAssertFalse(VisualSearchTerms.nameMatches("MX4500 manual.pdf", terms: terms), "a longer model number is another model")
    }

    func testAtMostTwelveWords() {
        let words = (1...30).map { "part\($0)x" }
        XCTAssertEqual(VisualSearchTerms.from(text: words.joined(separator: " "), labels: []).count, 12)
        XCTAssertTrue(VisualSearchTerms.from(text: "", labels: []).isEmpty)
    }
}
