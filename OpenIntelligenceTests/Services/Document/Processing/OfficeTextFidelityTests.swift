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
        let text = DocumentProcessor().extractTextFromExcelSheet(
            sheet, sharedStrings: ["Name", "Dose", "DHA &amp; EPA"])
        XCTAssertTrue(text.contains("Dose"), text)
        XCTAssertFalse(text.contains("| 1 |"), text)
        XCTAssertTrue(text.contains("DHA & EPA"), text)
        XCTAssertEqual(DocumentProcessor.spreadsheetColumnIndex("A"), 0)
        XCTAssertEqual(DocumentProcessor.spreadsheetColumnIndex("AA"), 26)
    }

    // MARK: - Word and PowerPoint line breaks and table cells

    /// A line break, a page break and a carriage return in Word are line breaks; "123 Main StSpringfield" was stored.
    func testWordBreaksSeparateWords() {
        let xml = """
            <w:body><w:p><w:r><w:t>123 Main St</w:t><w:br/><w:t>Springfield</w:t></w:r></w:p>\
            <w:p><w:r><w:t>A</w:t><w:br w:type="page"/><w:t>B</w:t><w:cr/><w:t>C</w:t></w:r></w:p></w:body>
            """
        let text = DocumentProcessor().extractTextFromWordXML(xml)
        XCTAssertTrue(text.contains("123 Main St\nSpringfield"), text)
        XCTAssertTrue(text.contains("A\nB\nC"), text)
        XCTAssertFalse(text.contains("StSpringfield"), text)
    }

    /// `<a:br/>`, and the `<a:br><a:rPr/></a:br>` form PowerPoint writes, are line breaks; "Q3 Revenue$4.2M" was stored.
    func testSlideBreaksSeparateWords() {
        let xml = """
            <p:sld><a:p><a:r><a:t>Q3 Revenue</a:t></a:r><a:br><a:rPr lang="en-US"/></a:br><a:r><a:t>$4.2M</a:t></a:r></a:p>\
            <a:p><a:r><a:t>x</a:t></a:r><a:br/><a:r><a:t>y</a:t></a:r></a:p></p:sld>
            """
        let text = DocumentProcessor().extractTextFromPowerPointSlide(xml)
        XCTAssertTrue(text.contains("Q3 Revenue\n$4.2M"), text)
        XCTAssertTrue(text.contains("x\ny"), text)
    }

    /// A Word cell's paragraphs are joined with " <br> " ("Check sealReplace filter" was stored), and a "|" or line
    /// break inside a cell is escaped so the row stays one row.
    func testWordTableCellsKeepParagraphsAndEscapePipes() {
        let xml = """
            <w:body><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Step</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Action</w:t></w:r></w:p></w:tc></w:tr>\
            <w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Check seal</w:t></w:r></w:p>\
            <w:p><w:r><w:t>Replace filter</w:t></w:r></w:p></w:tc></w:tr>\
            <w:tr><w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>A | B</w:t><w:br/><w:t>line two</w:t></w:r></w:p></w:tc></w:tr>\
            </w:tbl></w:body>
            """
        let text = DocumentProcessor().extractTextFromWordXML(xml)
        XCTAssertTrue(text.contains("| 1 | Check seal <br> Replace filter |"), text)
        XCTAssertTrue(text.contains("| 2 | A \\| B<br>line two |"), text)
    }

    /// A slide's table cells are entity-decoded ("R&amp;D" was stored), keep their paragraphs apart and escape "|".
    func testSlideTableCellsAreDecodedAndKeepParagraphs() {
        let xml = """
            <p:sld><a:tbl><a:tr><a:tc><a:txBody><a:p><a:r><a:t>Dept</a:t></a:r></a:p></a:txBody></a:tc>\
            <a:tc><a:txBody><a:p><a:r><a:t>Note</a:t></a:r></a:p></a:txBody></a:tc></a:tr>\
            <a:tr><a:tc><a:txBody><a:p><a:r><a:t>R&amp;D</a:t></a:r></a:p></a:txBody></a:tc>\
            <a:tc><a:txBody><a:p><a:r><a:t>Check seal</a:t></a:r></a:p><a:p><a:r><a:t>a|b</a:t></a:r><a:br/><a:r><a:t>c</a:t></a:r></a:p></a:txBody></a:tc></a:tr>\
            </a:tbl></p:sld>
            """
        let text = DocumentProcessor().extractTextFromPowerPointSlide(xml)
        XCTAssertTrue(text.contains("| R&D | Check seal <br> a\\|b<br>c |"), text)
    }

    /// A "|" or a line break in a spreadsheet or CSV cell is escaped instead of ending the cell or the row.
    func testPipeTableCellsEscapePipesAndLineBreaks() {
        let text = DocumentProcessor().formattedPipeTableText(from: [
            ["Model", "Size"], ["TV 55\" | OLED", "line1\nline2"],
        ])
        XCTAssertEqual(text, "| Model | Size |\n| --- | --- |\n| TV 55\" \\| OLED | line1<br>line2 |")
    }

    // MARK: - Word text boxes, tracked moves, headings and list numbers

    /// A text box's text is kept once, after the paragraph that anchors it, and the anchor's own text after the box is
    /// kept; text moved with tracked changes is kept once, at its new place.
    func testWordTextBoxesAndMovedTextAppearOnce() {
        let xml = """
            <w:body><w:p><w:r><w:t>Before box.</w:t></w:r><w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing>\
            <wps:txbx><w:txbxContent><w:p><w:r><w:t>Inside box.</w:t></w:r></w:p></w:txbxContent></wps:txbx></w:drawing></mc:Choice>\
            <mc:Fallback><w:pict><v:textbox><w:txbxContent><w:p><w:r><w:t>Inside box.</w:t></w:r></w:p></w:txbxContent></v:textbox></w:pict></mc:Fallback>\
            </mc:AlternateContent></w:r><w:r><w:t> After box.</w:t></w:r></w:p>\
            <w:p><w:moveFrom w:id="1"><w:r><w:t>Moved text.</w:t></w:r></w:moveFrom><w:r><w:t>Stays.</w:t></w:r></w:p>\
            <w:p><w:moveTo w:id="2"><w:r><w:t>Moved text.</w:t></w:r></w:moveTo></w:p><w:p/><w:p><w:r><w:t>Last.</w:t></w:r></w:p></w:body>
            """
        let text = DocumentProcessor().extractTextFromWordXML(xml)
        XCTAssertEqual(text.components(separatedBy: "Inside box.").count, 2, text)
        XCTAssertTrue(text.contains("Before box. After box.\nInside box."), text)
        XCTAssertEqual(text.components(separatedBy: "Moved text.").count, 2, text)
        XCTAssertTrue(text.contains("Stays."), text)
        XCTAssertTrue(text.contains("Last."), text)
    }

    /// Heading styles become "#" per level (by name, outline level or the style a style is based on) and list items
    /// carry the number Word shows ("1.1.", "(b)"), counted per list; without numbering.xml an item is "• ".
    func testWordHeadingsAndListNumbers() {
        let styles = DocumentProcessor.wordParagraphStyles(
            stylesXML: """
                <w:styles><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr></w:style>\
                <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>\
                <w:style w:type="paragraph" w:styleId="ClauseHeading"><w:name w:val="Clause Heading"/><w:basedOn w:val="Heading2"/></w:style>\
                <w:style w:type="paragraph" w:styleId="ListNumber"><w:name w:val="List Number"/><w:pPr><w:numPr><w:numId w:val="2"/></w:numPr></w:pPr></w:style></w:styles>
                """,
            numberingXML: """
                <w:numbering><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>\
                <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2."/></w:lvl></w:abstractNum>\
                <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="(%1)"/></w:lvl></w:abstractNum>\
                <w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/></w:lvl></w:abstractNum>\
                <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>\
                <w:num w:numId="3"><w:abstractNumId w:val="2"/></w:num></w:numbering>
                """)
        func paragraph(_ text: String, _ properties: String) -> String {
            "<w:p><w:pPr>\(properties)</w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }
        func item(_ level: Int, _ list: Int) -> String {
            "<w:numPr><w:ilvl w:val=\"\(level)\"/><w:numId w:val=\"\(list)\"/></w:numPr>"
        }
        let body = [
            paragraph("Scope", "<w:pStyle w:val=\"Heading1\"/>"),
            paragraph("Terms", "<w:pStyle w:val=\"ClauseHeading\"/>"),
            paragraph("First", item(0, 1)), paragraph("Sub one", item(1, 1)), paragraph("Sub two", item(1, 1)),
            paragraph("Second", item(0, 1)), paragraph("Sub again", item(1, 1)),
            paragraph("Lettered", "<w:pStyle w:val=\"ListNumber\"/>"),
            paragraph("Lettered two", "<w:pStyle w:val=\"ListNumber\"/>"),
            paragraph("Dot", item(0, 3)), paragraph("Off", item(0, 0)),
        ].joined()
        let text = DocumentProcessor().extractTextFromWordXML("<w:body>\(body)</w:body>", styles: styles)
        XCTAssertEqual(
            text,
            "# Scope\n## Terms\n1. First\n  1.1. Sub one\n  1.2. Sub two\n2. Second\n  2.1. Sub again\n(a) Lettered\n(b) Lettered two\n• Dot\nOff\n"
        )
        XCTAssertEqual(DocumentProcessor.wordListNumber(14, format: "upperRoman"), "XIV")
        XCTAssertEqual(DocumentProcessor.wordListNumber(27, format: "lowerLetter"), "aa")
        XCTAssertEqual(
            DocumentProcessor().extractTextFromWordXML("<w:body>\(paragraph("Item", item(0, 5)))</w:body>"), "• Item\n")
    }

    // MARK: - Spreadsheet values, strings and sheets

    /// A formula's cached text (`t="str"`) is entity-decoded; "R&amp;D &lt;2&gt;" was stored.
    func testSpreadsheetFormulaTextIsDecoded() {
        let sheet = #"<sheetData><row r="1"><c r="A1" t="str"><f>A2</f><v>R&amp;D &lt;2&gt;</v></c></row></sheetData>"#
        let text = DocumentProcessor().extractTextFromExcelSheet(sheet, sharedStrings: [])
        XCTAssertTrue(text.contains("R&D <2>"), text)
    }

    /// Date-formatted cells are ISO dates (45292 was stored for 2024-01-01), a duration format is hours, and a number
    /// is written to Excel's 15 significant digits ("1234.5600000000001" was stored).
    func testSpreadsheetDatesAndNumbersReadAsShown() {
        let styles = DocumentProcessor.spreadsheetNumberStyles(
            stylesXML: """
                <styleSheet><numFmts count="5"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/><numFmt numFmtId="165" formatCode="0.0 &quot;days&quot;"/>\
                <numFmt numFmtId="166" formatCode="[h]:mm:ss"/><numFmt numFmtId="167" formatCode="[$-409]mmmm d, yyyy;@"/>\
                <numFmt numFmtId="168" formatCode="#,##0.00 [$€-1]"/></numFmts><cellStyleXfs count="1"><xf numFmtId="14"/></cellStyleXfs>\
                <cellXfs count="8"><xf numFmtId="0"/><xf numFmtId="14" applyNumberFormat="1"/><xf numFmtId="164"/><xf numFmtId="165"/>\
                <xf numFmtId="22"/><xf numFmtId="166"/><xf numFmtId="167"/><xf numFmtId="168"><alignment/></xf></cellXfs></styleSheet>
                """,
            workbookXML: "<workbook><workbookPr/></workbook>")
        XCTAssertEqual(styles.kinds[1], .date)
        XCTAssertEqual(styles.kinds[2], .date)
        XCTAssertNil(styles.kinds[3], "a quoted \"days\" is not a date")
        XCTAssertEqual(styles.kinds[5], .duration)
        XCTAssertEqual(styles.kinds[6], .date)
        XCTAssertNil(styles.kinds[7], "a bracketed currency code is not a date")
        let sheet = """
            <sheetData><row r="1"><c r="A1" s="1"><v>45292</v></c><c r="B1" s="4"><v>45292.4375</v></c>\
            <c r="C1"><v>1234.5600000000001</v></c><c r="D1" s="5"><v>1.5</v></c><c r="E1" s="3"><v>7</v></c>\
            <c r="F1" s="1"><v>1</v></c><c r="G1" s="1"><v>61</v></c><c r="H1"><v>0.30000000000000004</v></c></row></sheetData>
            """
        let text = DocumentProcessor().extractTextFromExcelSheet(sheet, sharedStrings: [], styles: styles)
        XCTAssertTrue(
            text.contains(
                "| 2024-01-01 | 2024-01-01 10:30:00 | 1234.56 | 36:00:00 | 7 | 1900-01-01 | 1900-03-01 | 0.3 |"),
            text)
        let workbook1904 = DocumentProcessor.spreadsheetNumberStyles(
            stylesXML: nil, workbookXML: #"<workbook><workbookPr date1904="1"/></workbook>"#)
        XCTAssertTrue(workbook1904.date1904)
        XCTAssertEqual(DocumentProcessor.spreadsheetDateText(serial: 43_830, date1904: true), "2024-01-01")
        XCTAssertEqual(DocumentProcessor.spreadsheetNumberText("1E2"), "100")
        XCTAssertEqual(DocumentProcessor.spreadsheetNumberText("12345678901234567890"), "12345678901234567890")
    }

    /// An empty shared string (`<si/>`) keeps its index, phonetic runs are left out, and `_xHHHH_` escapes are decoded.
    func testSharedStringsKeepTheirIndicesAndDecodeEscapes() {
        let strings = DocumentProcessor.sharedStringsFromExcel(
            """
            <sst><si><t>A_x000D_B</t></si><si/><si><r><t>東京</t></r><rPh sb="0" eb="2"><t>トウキョウ</t></rPh><phoneticPr fontId="1"/></si>\
            <si><t xml:space="preserve">x_x005F_x000D_y</t></si><si><t>Last</t></si></sst>
            """)
        XCTAssertEqual(strings.count, 5, "\(strings)")
        XCTAssertEqual(strings.last, "Last")
        XCTAssertEqual(strings.map(DocumentProcessor.decodingSpreadsheetText), ["A\rB", "", "東京", "x_x000D_y", "Last"])
    }

    /// Sheets are read in the workbook's order under their names, a hidden sheet is marked, a chart sheet is skipped,
    /// and a workbook without sheet1.xml is still read.
    func testWorkbookSheetsAreReadInOrderUnderTheirNames() async throws {
        let sheets = DocumentProcessor.spreadsheetSheets(
            workbookXML: """
                <workbook xmlns:r="r"><sheets><sheet name="Summary &amp; Notes" sheetId="3" r:id="rId3"/>\
                <sheet state="hidden" name="Data" sheetId="1" r:id="rId1"/><sheet name="Chart1" sheetId="4" r:id="rId4"/></sheets></workbook>
                """,
            relationshipsXML: """
                <Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
                <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet7.xml"/>\
                <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet" Target="chartsheets/sheet1.xml"/></Relationships>
                """)
        XCTAssertEqual(sheets.map(\.name), ["Summary & Notes", "Data"])
        XCTAssertEqual(sheets.map(\.path), ["xl/worksheets/sheet7.xml", "xl/worksheets/sheet1.xml"])
        XCTAssertEqual(sheets.map(\.hidden), [false, true])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sheets-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        func sheet(_ label: String) -> String {
            """
            <worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>\(label)</t></is></c>\
            <c r="B1" s="1"><v>45292</v></c></row></sheetData></worksheet>
            """
        }
        try StoredZipWriter.write(
            entries: [
                .init(
                    path: "xl/workbook.xml",
                    contents: """
                        <workbook><sheets><sheet name="Second" sheetId="2" r:id="rId2"/>\
                        <sheet name="Secret" sheetId="3" state="veryHidden" r:id="rId3"/></sheets></workbook>
                        """),
                .init(
                    path: "xl/_rels/workbook.xml.rels",
                    contents: """
                        <Relationships><Relationship Id="rId2" Type="x/worksheet" Target="worksheets/sheet2.xml"/>\
                        <Relationship Id="rId3" Type="x/worksheet" Target="worksheets/sheet3.xml"/></Relationships>
                        """),
                .init(
                    path: "xl/styles.xml",
                    contents: #"<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>"#),
                .init(path: "xl/worksheets/sheet2.xml", contents: sheet("Two")),
                .init(path: "xl/worksheets/sheet3.xml", contents: sheet("Three")),
            ],
            to: url)
        let text = try await DocumentProcessor().extractTextFromOfficeDocument(url: url, type: .excel)
        XCTAssertTrue(text.contains("## Sheet: Second\n\n| Two | 2024-01-01 |"), text)
        XCTAssertTrue(text.contains("## Sheet: Secret (hidden)"), text)
        XCTAssertTrue(text.contains("| Three |"), text)
    }

    // MARK: - CSV

    private func csvFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("csv-\(UUID().uuidString).csv")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A CSV is read in its own encoding: Windows-1252 "€5" and a UTF-16 export.
    func testCSVIsReadInItsOwnEncoding() throws {
        var bytes = Array("Item,Price\nCoffee,".utf8)
        bytes.append(0x80)  // "€" in Windows-1252, not valid UTF-8
        bytes += Array("5\nTea,".utf8)
        bytes.append(0x80)
        bytes += Array("3\n".utf8)
        let windows = try DocumentProcessor().extractTextFromCSV(url: csvFile(Data(bytes)))
        XCTAssertTrue(windows.contains("| Coffee | €5 |"), windows)
        let utf16 = try DocumentProcessor().extractTextFromCSV(
            url: csvFile(try XCTUnwrap("Name,City\nAnn,Zürich\n".data(using: .utf16))))
        XCTAssertTrue(utf16.contains("| Ann | Zürich |"), utf16)
    }

    /// A quote inside a field (an inch mark) is text and does not swallow the rows after it; a quoted field still holds
    /// its delimiter and line break; Windows line ends end rows.
    func testCSVQuotesOnlyOpenAtAFieldStart() throws {
        let inches = try DocumentProcessor().extractTextFromCSV(
            url: csvFile(Data("Item,Size,Price\nTV,55\" screen,499\nRadio,small,20\nLamp,\"tall, white\",35\n".utf8)))
        XCTAssertTrue(inches.contains("| TV | 55\" screen | 499 |"), inches)
        XCTAssertTrue(inches.contains("| Radio | small | 20 |"), inches)
        XCTAssertTrue(inches.contains("| Lamp | tall, white | 35 |"), inches)
        let crlf = try DocumentProcessor().extractTextFromCSV(url: csvFile(Data("a,b\r\n1,2\r\n3,4\r\n".utf8)))
        XCTAssertEqual(crlf, "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        let address = try DocumentProcessor().extractTextFromCSV(
            url: csvFile(Data("Name,Address\nAnn,\"1 Main St\nSpringfield\"\n".utf8)))
        XCTAssertTrue(address.contains("| Ann | 1 Main St<br>Springfield |"), address)
    }

    /// The delimiter is the one that splits the first records into the same number of fields.
    func testCSVDelimiterIsTheConsistentOne() {
        XCTAssertEqual(DocumentProcessor.csvDelimiter("Price;Qty;Note\n1,50;2;a, b\n2,75;3;c\n"), ";")
        XCTAssertEqual(DocumentProcessor.csvDelimiter("name,notes,qty\nA,\"x\ty\",1\nB,z\tw,2\nC,q,3\n"), ",")
        XCTAssertEqual(DocumentProcessor.csvDelimiter("a\tb\tc\n1,5\t2\t3\n"), "\t")
        XCTAssertEqual(DocumentProcessor.csvDelimiter("a|b\n1|2\n"), "|")
    }

    // MARK: - HTML

    /// A table keeps its caption, a header separator, a cell's paragraphs on its row, an escaped "|" and a spanned cell.
    func testHTMLTablesKeepTheirRowsWhole() {
        let html = """
            <table><caption>Table 2. Codes</caption><thead><tr><th>Code</th><th>Steps</th><th>Note</th></tr></thead>\
            <tbody><tr><td>E1</td><td><p>Check seal</p><p>Replace filter</p></td><td>a | b</td></tr>\
            <tr><td colspan="2">Merged</td><td>z</td></tr></tbody></table>
            """
        XCTAssertEqual(
            WebPageFetchService.readableText(fromHTML: html).text,
            """
            Table 2. Codes
            | Code | Steps | Note |
            | --- | --- | --- |
            | E1 | Check seal <br> Replace filter | a \\| b |
            | Merged | Merged | z |
            """)
    }

    /// An ordered list counts from its start and an item's value; a nested list is indented under its item, also when
    /// it is written straight inside the outer list.
    func testHTMLListsKeepNumbersAndNesting() {
        let html = """
            <ol start="3"><li><p>Third</p></li><li>Fourth<ul><li>Sub a</li><li>Sub <b>b</b></li></ul></li><li value="10">Tenth</li></ol>\
            <ul><li>A</li><ul><li>Nested direct</li></ul></ul>
            """
        XCTAssertEqual(
            WebPageFetchService.readableText(fromHTML: html).text,
            "3. Third\n4. Fourth\n   - Sub a\n   - Sub b\n10. Tenth\n\n- A\n  - Nested direct")
    }

    /// Preformatted text keeps its line breaks; superscripts, subscripts and numeric references 128 to 159 read as
    /// shown; a ">" in a quoted attribute does not end its tag; button and summary text is kept.
    func testHTMLPreformattedScriptsReferencesAndAttributes() {
        XCTAssertEqual(
            WebPageFetchService.readableText(
                fromHTML: "<p>Run:</p><pre><code>if x &lt; 3 {\n    print(x)\n}</code></pre><p>Done.</p>"
            ).text,
            "Run:\n\n```\nif x < 3 {\n    print(x)\n}\n```\n\nDone.")
        XCTAssertEqual(
            WebPageFetchService.readableText(
                fromHTML: "<p>10<sup>3</sup> cells, H<sub>2</sub>O, &#150; &#128;5 &#x97;</p>"
            ).text,
            "10^3 cells, H_2O, \u{2013} \u{20AC}5 \u{2014}")
        XCTAssertEqual(
            WebPageFetchService.readableText(
                fromHTML: """
                    <p><a title="a > b" href='x'>Link</a> text</p><button>Add to cart</button>\
                    <details><summary>More info</summary><p>Body</p></details>
                    """
            ).text,
            "Link text\n\nAdd to cart\n\nMore info\n\nBody")
    }

    /// Elements marked hidden, aria-hidden or display:none are left out with what they hold; a hidden input's type
    /// and a class named "hidden-xs" do not hide anything.
    func testHTMLHiddenElementsAreLeftOut() {
        let html = """
            <p>Shown.</p><div hidden><p>Hidden <div>nested</div> still hidden</p></div><span aria-hidden="true">★</span>\
            <div style="color:red; display: none">gone</div><input type="hidden" value="x"><p class="hidden-xs">Visible too.</p>
            """
        XCTAssertEqual(WebPageFetchService.readableText(fromHTML: html).text, "Shown.\n\nVisible too.")
    }
}
