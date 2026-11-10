//
//  PassageFinderTests.swift
//  OpenIntelligenceTests
//
//  Where a cited passage is highlighted, whatever the file's dashes, spacing, ligatures and table layout (5.8).
//

import XCTest

@testable import OpenIntelligence

final class PassageFinderTests: XCTestCase {
    private func highlighted(_ passage: String, in text: String) -> String? {
        PassageFinder.locate(passage, in: text).map { (text as NSString).substring(with: $0.range) }
    }

    /// The owner's iPhone, 2026-11-10: page 2 of the morin paper as PDFKit reads it, and the stored passage.
    func testEmDashAndASymbolRunIntoTheNextWord() throws {
        let page =
            "(3) Ischemia — in which after the surgical preparation\n(4) Ischemia +Morin \u{2014} in which the condition was similar to the\nischemia group except that the hearts were perfused with a KHB"
        let passage =
            "(4) Ischemia + Morin - in which the condition was similar to the ischemia group except that the hearts were perfused"
        let found = try XCTUnwrap(PassageFinder.locate(passage, in: page))
        XCTAssertEqual(found.method, .whole)
        let text = (page as NSString).substring(with: found.range)
        XCTAssertTrue(text.hasPrefix("(4) Ischemia +Morin"), text)
        XCTAssertTrue(text.hasSuffix("perfused"), text)
    }

    func testLigatureCurlyQuotesAndALineBreakHyphen() throws {
        let page =
            "The \u{FB01}nal analysis showed \u{201C}signi\u{00AD}\nficant\u{201D} gains in mito-\nchondrial function."
        let passage = "The final analysis showed \"significant\" gains in mitochondrial function."
        XCTAssertEqual(highlighted(passage, in: page), page, "the closing period too")
    }

    func testATablePassageIsFoundWithoutItsImportLabels() throws {
        let page = "Table 1\nContent Amount/Value Unit\nCarbohydrates 15.0-25.0 %\nLysine 4.4-26.2 mg/g\nFootnote."
        let passage =
            "TABLE: Table 1\nHEADERS: Content | Amount/Value | Unit\nROW 1: Carbohydrates | 15.0-25.0 | %\nROW 2: Lysine | 4.4-26.2 | mg/g"
        let text = try XCTUnwrap(highlighted(passage, in: page))
        XCTAssertTrue(text.contains("Carbohydrates") && text.contains("26.2"), text)
    }

    /// A passage whose middle the page does not hold, found by its sentences from first to last.
    func testSentencesInOrderWhenTheMiddleDiffers() throws {
        let page =
            "Intro text. The first finding was large and clear in every group. A sentence the import read differently. The second finding held up in the replication cohort as well. Other text."
        let passage =
            "The first finding was large and clear in every group. Something the page does not hold at all here. The second finding held up in the replication cohort as well."
        let found = try XCTUnwrap(PassageFinder.locate(passage, in: page))
        XCTAssertEqual(found.method, .sentences)
        let text = (page as NSString).substring(with: found.range)
        XCTAssertTrue(text.hasPrefix("The first finding") && text.hasSuffix("as well."), text)
    }

    /// A sentence a page repeats far away (a running header) does not stretch the highlight to it.
    func testARepeatedSentenceFarAwayDoesNotStretchTheHighlight() throws {
        let filler = String(repeating: "Unrelated words fill this column of the page. ", count: 40)
        let page =
            "The cohort was followed for ten years in total. The outcome was dementia diagnosed by a clinician. "
            + filler + "The outcome was dementia diagnosed by a clinician."
        let passage =
            "The cohort was followed for ten years in total. The outcome was dementia diagnosed by a clinician. A sentence not on the page at all, here."
        let text = try XCTUnwrap(highlighted(passage, in: page))
        XCTAssertLessThan(text.count, 200, "the highlight stays on the passage, not the repeat")
    }

    /// Text read by OCR, where letters differ here and there.
    func testApproximatePlaceForOCRText() throws {
        let page =
            "Header line.\nThe patients were randornly assigned to recieve either the drug or a placeb0 for twelve weeks, and outcomes were rneasured at baseline and at the end.\nFooter."
        let passage =
            "The patients were randomly assigned to receive either the drug or a placebo for twelve weeks, and outcomes were measured at baseline and at the end."
        let found = try XCTUnwrap(PassageFinder.locate(passage, in: page))
        XCTAssertEqual(found.method, .approximate)
        let text = (page as NSString).substring(with: found.range)
        XCTAssertTrue(text.contains("assigned") && text.contains("baseline"), text)
    }

    func testAPassageThePageDoesNotHoldIsNotFound() {
        XCTAssertNil(
            PassageFinder.locate(
                "A sentence about something else entirely, nowhere here.",
                in: "The page talks about mitochondria and morin."))
    }

    /// Table cells in another order than the passage's rows are highlighted one by one, near the passage's place.
    func testTableCellsAreHighlightedAsPieces() {
        let page =
            "Table 2 Characteristics\nAge, y 45 (12)\nFemale, No. (%) 1200 (51)\nSmoker, No. (%) 300 (13)\nStudy text follows here and goes on."
        let passage = "Table 2 Characteristics\nAge, y\nFemale, No. (%)\nSmoker, No. (%)\n45 (12)\n1200 (51)\n300 (13)"
        let ranges = PassageFinder.places(passage, in: page)
        XCTAssertFalse(ranges.isEmpty)
        let lit = ranges.map { (page as NSString).substring(with: $0) }.joined(separator: " ")
        XCTAssertTrue(lit.contains("1200 (51)") && lit.contains("Smoker"), lit)
        XCTAssertFalse(lit.contains("Study text"), lit)
    }
}
