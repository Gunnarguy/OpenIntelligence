//
//  StructuredKeywordOrderTests.swift
//  OpenIntelligenceTests
//
//  A table passage keeps at most 20 keywords. Through 5.7 they were `Array(Set(keywords)).prefix(20)`, a different 20
//  on each import because a Set's order is seeded per process. They are now the first 20 in the order they appear.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class StructuredKeywordOrderTests: XCTestCase {
    func testTheFirstTwentyCodesAreKeptInTheOrderTheyAppear() {
        let codes = (1...30).map { "ABC-\(100 + $0)" }
        let keywords = DocumentProcessor().extractKeywordsFromStructuredElement(codes.joined(separator: " "), type: "table")
        XCTAssertEqual(keywords.count, 20)
        XCTAssertEqual(Array(keywords.filter { $0.hasPrefix("ABC-") }.prefix(5)), Array(codes.prefix(5)))
        XCTAssertEqual(Set(keywords).count, keywords.count)
    }
}
