//
//  AppStateReportingTests.swift
//  OpenIntelligenceTests
//
//  The answer state the system's diagnostics see is one of three fixed labels (5.7).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class AppStateReportingTests: XCTestCase {
    func testTheAnswerStateIsOneOfThreeLabels() {
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "standard"), "Standard")
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "deepThink"), "Deep Think")
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "maximum"), "Maximum")
        // Older stored values map as the app maps them, and anything else is Standard.
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "agentic"), "Deep Think")
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "balanced"), "Standard")
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: nil), "Standard")
        XCTAssertEqual(AppStateReporting.answerLabel(storedMode: "something else"), "Standard")
    }

    func testTheDomainsAreFixed() {
        // Changing a domain starts a new series in the system's reports; these stay as they are.
        XCTAssertEqual(AppStateReporting.importDomain, "com.openintelligence.import")
        XCTAssertEqual(AppStateReporting.answerDomain, "com.openintelligence.answer")
    }
}
