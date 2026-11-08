//
//  OfficeTextFidelityTests.swift
//  OpenIntelligenceTests
//
//  Word and PowerPoint text keeps what the file says (5.8): a non-breaking hyphen ("1‑2" was stored as "12"), a tab,
//  a Symbol-font ±, a superscript, XML entities, and every table on a slide (each was extracted and then dropped).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class OfficeTextFidelityTests: XCTestCase {
    func testWordRunsKeepHyphensTabsSymbolsSuperscriptsAndEntities() {
        let xml = """
            <w:body><w:p><w:r><w:t>Dose 1</w:t></w:r><w:r><w:noBreakHyphen/></w:r><w:r><w:t>2 g</w:t></w:r></w:p>\
            <w:p><w:r><w:t>Name</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>Value</w:t></w:r></w:p>\
            <w:p><w:r><w:t>5 </w:t></w:r><w:r><w:sym w:font="Symbol" w:char="F0B1"/></w:r><w:r><w:t> 1</w:t></w:r></w:p>\
            <w:p><w:r><w:t>10</w:t></w:r><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>3</w:t></w:r><w:r><w:t> cells</w:t></w:r></w:p>\
            <w:p><w:r><w:t>A &amp; B &lt; C</w:t></w:r></w:p></w:body>
            """
        let text = DocumentProcessor().extractTextFromWordXML(xml)
        XCTAssertTrue(text.contains("Dose 1-2 g"), text)
        XCTAssertTrue(text.contains("Name Value"), text)
        XCTAssertTrue(text.contains("5 ± 1"), text)
        XCTAssertTrue(text.contains("10^3 cells"), text)
        XCTAssertTrue(text.contains("A & B < C"), text)
    }

    func testASlidesTableIsKept() {
        let xml = """
            <p:sld><a:p><a:r><a:t>Doses</a:t></a:r></a:p>\
            <a:tbl><a:tr><a:tc><a:txBody><a:p><a:r><a:t>DHA</a:t></a:r></a:p></a:txBody></a:tc>\
            <a:tc><a:txBody><a:p><a:r><a:t>1-2 g</a:t></a:r></a:p></a:txBody></a:tc></a:tr></a:tbl>\
            <a:p><a:r><a:t>Two</a:t></a:r><a:r><a:t> </a:t></a:r><a:r><a:t>words</a:t></a:r></a:p></p:sld>
            """
        let text = DocumentProcessor().extractTextFromPowerPointSlide(xml)
        XCTAssertTrue(text.contains("DHA"), text)
        XCTAssertTrue(text.contains("1-2 g"), text)
        XCTAssertFalse(text.contains("[[PPTTABLE"), text)
        XCTAssertTrue(text.contains("Two words"), text)
    }

    func testEntitiesAreDecoded() {
        XCTAssertEqual(DocumentProcessor.decodingXMLEntities("&#177; &#x2265; &amp;lt;"), "± ≥ &lt;")
    }

    /// A spreadsheet keeps each cell in its column and its text, past a styled empty cell and a skipped column.
    func testSpreadsheetCellsStayInTheirColumns() {
        let sheet = """
            <sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" s="2"/><c r="C1" t="s"><v>1</v></c></row>            <row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>3</v></c></row></sheetData>
            """
        let text = DocumentProcessor().extractTextFromExcelSheet(sheet, sharedStrings: ["Name", "Dose", "DHA &amp; EPA"])
        XCTAssertTrue(text.contains("Dose"), text)
        XCTAssertFalse(text.contains("| 1 |"), text)
        XCTAssertTrue(text.contains("DHA & EPA"), text)
        XCTAssertEqual(DocumentProcessor.spreadsheetColumnIndex("A"), 0)
        XCTAssertEqual(DocumentProcessor.spreadsheetColumnIndex("AA"), 26)
    }
}
