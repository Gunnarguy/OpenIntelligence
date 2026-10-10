//
//  IngestionAccuracyTests.swift
//  OpenIntelligenceTests
//
//  Places where import dropped or mis-read content with no error, found by a read of the whole
//  pipeline on 2026-10-10 and measured there with the same functions:
//  a table cell that holds only a number or a code was emptied, a line in a script other than
//  Latin or Cyrillic was deleted as garbage, and a recording's language was read from two
//  letters anywhere in its name.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class IngestionAccuracyTests: XCTestCase {

    // MARK: - Table cells

    func testACellThatIsOnlyANumberOrACodeKeepsItsContent() {
        for cell in ["34", "7", "2024", "10-20", "3 - 5", "4-38", "SKU10293", "INV2024001", "UA1234"] {
            XCTAssertEqual(OCRConfiguration.normalizeExtractedText(cell, profile: .tableCell), cell, cell)
        }
    }

    func testACellGetsTheSameRepairsAsPageText() {
        for cell in ["Net   rent", "ﬁnal  ofﬁce   ﬁgure", "Total\u{200B} due"] {
            XCTAssertEqual(
                OCRConfiguration.normalizeExtractedText(cell, profile: .tableCell),
                OCRConfiguration.normalizeExtractedText(cell), cell)
        }
    }

    func testAPagesOwnNumberAndCodeLinesAreStillRemovedFromPageText() {
        let page = "The lease begins in March.\n42\nONQ5011001N\nRent is due on the first."
        let lines = OCRConfiguration.normalizeExtractedText(page).components(separatedBy: "\n")
        XCTAssertEqual(lines, ["The lease begins in March.", "Rent is due on the first."])
    }

    // MARK: - Lines in other scripts

    private let otherScripts = [
        "Η συμφωνία μίσθωσης ισχύει για δώδεκα μήνες από την υπογραφή της.",
        "本协议自签署之日起生效，有效期为十二个月，期满后可以续签。",
        "تسري هذه الاتفاقية لمدة اثني عشر شهرا من تاريخ التوقيع عليها.",
        "Το ενοίκιο καταβάλλεται την πρώτη ημέρα κάθε μήνα στον εκμισθωτή.",
    ]

    func testALineInAnotherScriptIsNotGarbageInADocumentOfThatScript() {
        for line in otherScripts {
            XCTAssertFalse(OCRConfiguration.isGarbageText(line, isLatinDocument: false), line)
        }
    }

    func testAPageInAnotherScriptKeepsItsLines() {
        let greek = [otherScripts[0], otherScripts[3], "Ο μισθωτής οφείλει να διατηρεί το ακίνητο σε καλή κατάσταση.",
            "Η εγγύηση επιστρέφεται εντός τριάντα ημερών από τη λήξη."]
        let page = greek.joined(separator: "\n")
        let filtered = OCRConfiguration.filterGarbageText(page, revertIfTooAggressive: false)
        XCTAssertEqual(filtered.0.components(separatedBy: "\n"), greek)
        XCTAssertEqual(filtered.1, 0)
    }

    func testSymbolNoiseIsStillGarbage() {
        XCTAssertTrue(OCRConfiguration.isGarbageText("@@## $$ %% ^^ && ** (( )) ~~ || <<>>"))
        XCTAssertTrue(OCRConfiguration.isGarbageText("@@## $$ %% ^^ && ** (( )) ~~ || <<>>", isLatinDocument: false))
    }

    // MARK: - A recording's language

    func testARecordingsLanguageIsNotReadFromLettersInsideAWord() {
        for name in ["notes_friday.m4a", "plans_december.m4a", "taxes_january.m4a", "my_essay.mp3",
            "trip_zhangjiajie.mov", "Meeting.m4a", "voice memo 12.m4a"]
        {
            XCTAssertEqual(DocumentProcessor.speechLanguage(forFilename: name), "en-US", name)
        }
    }

    func testARecordingsLanguageIsReadFromAWordOrAClosingCode() {
        let expected = [
            "lecture_fr.m4a": "fr-FR", "talk-de.mp3": "de-DE", "interview_ja.wav": "ja-JP",
            "meeting_zh.m4a": "zh-CN", "clase 3 es.m4a": "es-ES", "Spanish lesson 4.m4a": "es-ES",
            "german_vocabulary.mp3": "de-DE", "french-notes_friday.m4a": "fr-FR",
        ]
        for (name, language) in expected {
            XCTAssertEqual(DocumentProcessor.speechLanguage(forFilename: name), language, name)
        }
    }
}
