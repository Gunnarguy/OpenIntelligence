//
//  FactCheckQuoteTests.swift
//  OpenIntelligenceTests
//
//  Fact Check quotes the sentence a claim rests on, not the start of its passage (5.7).
//

import XCTest

@testable import OpenIntelligence

final class FactCheckQuoteTests: XCTestCase {
    private let lease = """
        This Residential Lease Agreement is made between the Landlord and the Tenant named below.
        The premises are the apartment at 12 Elm Street, unit 4B, with one parking space.
        Rent of $1,850 is due on the 5th of each month. A late fee of $75 applies after 11:59 p.m. on the 5th.
        Either party may end this lease with 60 days of written notice.
        """

    func testTheQuoteStartsAtTheSentenceTheClaimRestsOn() {
        let quote = StructuredAnswer.quote(from: lease, supporting: ["The tenant must give 60 days of written notice."])
        XCTAssertTrue(quote.hasPrefix("Either party may end this lease with 60 days"), quote)
    }

    func testTheSentenceIsKeptWholeAcrossAnAbbreviation() {
        let quote = StructuredAnswer.quote(from: lease, supporting: ["The late fee is $75 after 11:59 p.m."])
        XCTAssertTrue(quote.hasPrefix("A late fee of $75 applies after 11:59 p.m. on the 5th."), quote)
    }

    func testWithoutAClaimOrACommonWordItIsTheStart() {
        XCTAssertEqual(StructuredAnswer.quote(from: lease, supporting: []), String(lease.prefix(240)))
        XCTAssertEqual(StructuredAnswer.quote(from: lease, supporting: ["Zebras graze quietly."]), String(lease.prefix(240)))
    }

    func testALongSentenceIsCutAtAWordAndMarked() {
        let long = "Notice " + Array(repeating: "provisions apply", count: 60).joined(separator: " ") + "."
        let quote = StructuredAnswer.quote(from: long, supporting: ["notice provisions"], limit: 80)
        XCTAssertLessThanOrEqual(quote.count, 81)
        XCTAssertTrue(quote.hasSuffix("…"))
        XCTAssertFalse(quote.dropLast().hasSuffix(" "))
    }
}
