//
//  TableTitleRowTests.swift
//  OpenIntelligenceTests
//
//  A table title Vision reads as one cell over every column is the caption, not the header (5.8).
//

import XCTest

@testable import OpenIntelligence

final class TableTitleRowTests: XCTestCase {
    /// KBIE_13_2100863.pdf page 6, as the 2026-11-10 import check stored it before the fix: the title row became the
    /// header ("<title> | Column 2 | Column 3") and the real header became ROW 1.
    private let kbieRows: [[String]] = [
        ["Arthrospira platensis Biochemical Composition Profile", "", ""],
        ["Content", "Amount/Value", "Unit"],
        ["Carbohydrates", "15.0-25.0", "%"],
        ["Lysine", "4.4-26.2", "mg/g"],
    ]

    func testTitleRowJoinsTheCaptionAndTheHeaderRowLeads() throws {
        let lifted = try XCTUnwrap(
            StructuredDocumentParser.liftingSpanningTitle(
                "Arthrospira platensis Biochemical Composition Profile", from: kbieRows,
                caption: "Table 1: Critical biochemical composition profile analysis of"))
        XCTAssertEqual(lifted.rows.first, ["Content", "Amount/Value", "Unit"])
        XCTAssertEqual(lifted.rows.count, 3)
        XCTAssertEqual(
            lifted.caption,
            "Table 1: Critical biochemical composition profile analysis of Arthrospira platensis Biochemical Composition Profile"
        )
    }

    func testCaptionThatAlreadyHoldsTheTitleIsKept() throws {
        let lifted = try XCTUnwrap(
            StructuredDocumentParser.liftingSpanningTitle(
                "Arthrospira platensis Biochemical Composition Profile", from: kbieRows,
                caption: "Table 1. Arthrospira platensis biochemical composition profile"))
        XCTAssertEqual(lifted.caption, "Table 1. Arthrospira platensis biochemical composition profile")
    }

    func testNoCaptionTakesTheTitle() throws {
        let lifted = try XCTUnwrap(
            StructuredDocumentParser.liftingSpanningTitle(
                "Arthrospira platensis Biochemical Composition Profile", from: kbieRows, caption: nil))
        XCTAssertEqual(lifted.caption, "Arthrospira platensis Biochemical Composition Profile")
    }

    /// A first row with any other filled cell is a header or data, and stays.
    func testRowWithOtherCellsFilledStays() {
        let rows = [["Arthrospira platensis", "Amount", ""], ["Content", "Amount/Value", "Unit"]]
        XCTAssertNil(StructuredDocumentParser.liftingSpanningTitle("Arthrospira platensis", from: rows, caption: nil))
    }

    /// A first row whose text is not the spanning cell's stays.
    func testDifferentFirstCellStays() {
        XCTAssertNil(StructuredDocumentParser.liftingSpanningTitle("Some other title", from: kbieRows, caption: nil))
    }

    /// A one-column table has no columns to name; its first row stays.
    func testOneColumnTableStays() {
        XCTAssertNil(
            StructuredDocumentParser.liftingSpanningTitle("Notes", from: [["Notes"], ["First item"]], caption: nil))
    }
}
