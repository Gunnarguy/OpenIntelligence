//
//  DayOrdinalsTests.swift
//  OpenIntelligenceTests
//
//  A day written as an ordinal beside a month is searched as its number (5.7). On 2026-10-15 "What happened on
//  September 30th" missed notes that head the day "September 30", and the same question without "th" found it.
//

import XCTest

@testable import OpenIntelligence

final class DayOrdinalsTests: XCTestCase {
    func testADayBesideAMonthIsReadAsItsNumber() {
        XCTAssertEqual(DayOrdinals.cardinal("What happened on September 30th"), "What happened on September 30")
        XCTAssertEqual(DayOrdinals.cardinal("What happened on September 30th?"), "What happened on September 30?")
        XCTAssertEqual(DayOrdinals.cardinal("sept. 30th and oct 1st"), "sept. 30 and oct 1")
        XCTAssertEqual(DayOrdinals.cardinal("September the 22nd"), "September the 22")
        XCTAssertEqual(DayOrdinals.cardinal("Due May 2nd, 2026"), "Due May 2, 2026")
        XCTAssertEqual(DayOrdinals.cardinal("march 3rd"), "march 3")
    }

    func testADayBeforeAMonthIsReadAsItsNumber() {
        XCTAssertEqual(DayOrdinals.cardinal("the 1st of May"), "the 1 of May")
        XCTAssertEqual(DayOrdinals.cardinal("30th September"), "30 September")
    }

    func testOrdinalsThatAreNotDaysStayAsWritten() {
        XCTAssertEqual(DayOrdinals.cardinal("the 21st century"), "the 21st century")
        XCTAssertEqual(DayOrdinals.cardinal("5th generation iPad"), "5th generation iPad")
        XCTAssertEqual(DayOrdinals.cardinal("what happened on the 3rd"), "what happened on the 3rd")
        XCTAssertEqual(DayOrdinals.cardinal("What happened on September 30"), "What happened on September 30")
        XCTAssertEqual(DayOrdinals.cardinal("Version 5.7"), "Version 5.7")
        XCTAssertEqual(DayOrdinals.cardinal(""), "")
    }
}
