//
//  PlaceholderCitationTests.swift
//  OpenIntelligenceTests
//
//  "[S#]" is the prompts' placeholder, never a citation (5.8, 2026-11-19): a Deep Think answer on the owner's iPhone
//  showed "as documented in [S#], [S#], and [S#]" and ran on into hundreds of them.
//

import XCTest

@testable import OpenIntelligence

final class PlaceholderCitationTests: XCTestCase {
    private func clean(_ s: String) -> String { AgenticOrchestrator.removingPlaceholderCitations(s) }

    func testALeadInAndItsPlaceholdersGo() {
        XCTAssertEqual(
            clean("Scanned pages go through Vision, as documented in [S#], [S#], and [S#]."),
            "Scanned pages go through Vision.")
    }

    func testARunOffTheEndGoes() {
        XCTAssertEqual(
            clean("The passages are trimmed to fit the window, as outlined in [S#], [S#], [S#], [S#], ["),
            "The passages are trimmed to fit the window")
    }

    func testRealLabelsStay() {
        XCTAssertEqual(clean("Standard uses 0.28 [S2]."), "Standard uses 0.28 [S2].")
        XCTAssertEqual(clean("It reads both [S1] [S#]."), "It reads both [S1].")
    }

    func testTextWithoutPlaceholdersIsUntouched() {
        let text = "Line one.\n\n- item  with two spaces"
        XCTAssertEqual(clean(text), text)
    }
}
