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

import CoreText
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

    // MARK: - A large PDF, read a batch of pages at a time

    /// A PDF with a text layer: one page for each entry, a line for each sentence.
    private func textPDF(pages: [[String]]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pages-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        for lines in pages {
            context.beginPDFPage(nil)
            for (row, text) in lines.enumerated() {
                let attributed = NSAttributedString(
                    string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 54, y: 730 - CGFloat(row) * 16)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    func testEachBatchOfPagesNumbersItsPassagesFromZeroAndTheImportCarriesThemOn() async throws {
        func page(_ topic: String) -> [String] {
            (1...30).map { "Sentence \($0) about \(topic) states one plain fact that a reader could look up later." }
        }
        let url = try textPDF(pages: [page("pump maintenance"), page("valve inspection")])
        defer { try? FileManager.default.removeItem(at: url) }
        let documentId = UUID()
        let processor = DocumentProcessor()
        let (_, first) = try await processor.processDocument(at: url, pageRange: 0...0, documentId: documentId)
        let (_, second) = try await processor.processDocument(at: url, pageRange: 1...1, documentId: documentId)
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)

        // What the processor hands back: both batches start at zero. The keyword index names a
        // row by the document and this number, so stored as they are the second batch's rows
        // would meet the first batch's names.
        XCTAssertEqual(first.first?.metadata.chunkIndex, 0)
        XCTAssertEqual(second.first?.metadata.chunkIndex, 0)

        let carriedOn = RAGService.documentNumbered(
            second.map(\.metadata), chunkBase: first.count, positionBase: 0)
        let numbers = first.map(\.metadata.chunkIndex) + carriedOn.map(\.chunkIndex)
        XCTAssertEqual(numbers, Array(0..<(first.count + second.count)))
    }

    // MARK: - A text file that is not UTF-8

    func testATextFileInAnotherEncodingIsReadAsItsOwnText() {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let files: [(String, String, String.Encoding)] = [
            ("Shift-JIS", "四半期報告書：第2四半期の純収益は4％増加しました。\nこれは二行目のテキストです。\n", .shiftJIS),
            ("EUC-JP", "四半期報告書：第2四半期の純収益は4％増加しました。\nこれは二行目のテキストです。\n", .japaneseEUC),
            (
                "Windows-1251",
                "Квартальный отчёт: чистая выручка выросла на 4% во втором квартале.\nВторая строка текста.\n",
                .windowsCP1251
            ),
            ("GB 18030", "季度报告：第二季度净收入增长了4％。\n这是第二行文字。\n", gb18030),
            (
                "Windows-1252",
                "Résumé du trimestre : le chiffre d’affaires net a augmenté de 4 %. Café, naïve, façade.\n",
                .windowsCP1252
            ),
        ]
        for (name, text, encoding) in files {
            guard let data = text.data(using: encoding) else { return XCTFail("could not write \(name)") }
            XCTAssertNil(String(data: data, encoding: .utf8), "\(name) is not UTF-8")
            XCTAssertEqual(DocumentProcessor.decodeTextFile(data)?.text, text, name)
        }
    }

    func testUTF16IsReadWithAndWithoutItsByteOrderMark() {
        let text = "Quarterly report: net revenue rose 4% in the second quarter.\nSecond line of plain text.\n"
        for encoding in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian] {
            let data = text.data(using: encoding)!
            XCTAssertEqual(DocumentProcessor.decodeTextFile(data)?.text, text, "\(encoding)")
        }
        // With no mark and few Latin letters there are few zero bytes to go on.
        let russian = "Квартальный отчёт: чистая выручка выросла на 4% во втором квартале.\nВторая строка текста.\n"
        let japanese = "四半期報告書：第2四半期の純収益は4％増加しました。\nこれは二行目のテキストです。\n"
        for text in [russian, japanese] {
            let data = text.data(using: .utf16LittleEndian)!
            XCTAssertEqual(DocumentProcessor.decodeTextFile(data)?.text, text)
        }
    }

    func testUTF8WithZeroBytesInItStaysUTF8() {
        let stray = "line one\u{0}\nline two with a stray zero byte\n"
        XCTAssertEqual(DocumentProcessor.decodeTextFile(Data(stray.utf8))?.text, stray)
        let padded = Data("name".utf8) + Data(repeating: 0, count: 60) + Data("value\n".utf8)
        XCTAssertEqual(DocumentProcessor.decodeTextFile(padded)?.encodingName, "UTF-8")
    }

    func testUTF8IsReadAsWrittenAndItsByteOrderMarkIsNotText() {
        let text = "Plain UTF-8 with an accent, café, and a symbol, ✓.\n"
        let plain = DocumentProcessor.decodeTextFile(Data(text.utf8))
        XCTAssertEqual(plain?.text, text)
        XCTAssertEqual(plain?.encodingName, "UTF-8")
        XCTAssertEqual(DocumentProcessor.decodeTextFile(Data([0xEF, 0xBB, 0xBF] + Array(text.utf8)))?.text, text)
        XCTAssertNil(DocumentProcessor.decodeTextFile(Data()))
    }

    // MARK: - A passage longer than the embedding model reads

    /// One token a word, as a stand-in for the bundled tokenizer.
    private func words(_ text: String) -> Int { text.split(separator: " ").count }

    private func passage(words count: Int) -> String {
        (0..<count).map { "word\($0)" }.joined(separator: " ")
    }

    func testAPassageThatFitsTheWindowIsEmbeddedWhole() {
        let text = passage(words: 400)
        let result = RAGService.embeddingText(prefix: "file.jsonl: ", passage: text, window: 512, countTokens: words)
        XCTAssertEqual(result.text, "file.jsonl: " + text)
        XCTAssertFalse(result.reachesWindow)
    }

    func testAPassageAFewTokensOverKeepsAllTheWindowHolds() {
        // 520 words of about eight characters: 4,500 characters. The cut this replaced kept the
        // first 1,500 of them, about 170 of these words, for a model that reads 512.
        let text = passage(words: 520)
        let result = RAGService.embeddingText(prefix: "file.jsonl: ", passage: text, window: 512, countTokens: words)
        XCTAssertTrue(result.reachesWindow)
        XCTAssertEqual(words(result.text), 512, "the longest beginning that fits")
        XCTAssertGreaterThan(result.text.count, 1_500)
        XCTAssertTrue(("file.jsonl: " + text).hasPrefix(result.text))
    }

    func testACountThatStopsAtTheWindowIsReportedAndNothingIsCutHere() {
        // The bundled tokenizer stops at the window, so a longer passage counts as exactly the
        // window. The model then reads its first 512 tokens; nothing shorter is sent.
        let text = passage(words: 900)
        let result = RAGService.embeddingText(
            prefix: "", passage: text, window: 512, countTokens: { min(self.words($0), 512) })
        XCTAssertEqual(result.text, text)
        XCTAssertTrue(result.reachesWindow)
    }
}
