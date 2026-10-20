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
import Vision
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

    /// The import itself, not only the decoder: a Shift-JIS text file goes through `processDocument` and its
    /// passages read as the file's own text. Through 5.6 a text file that was not UTF-8 was read with a
    /// single-byte guess and imported as garbage, with no error.
    func testATextFileInShiftJISImportsAsReadableText() async throws {
        let text = "四半期報告書：第2四半期の純収益は4％増加しました。\nこれは二行目のテキストです。\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shift-jis-\(UUID().uuidString).txt")
        try XCTUnwrap(text.data(using: .shiftJIS)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (_, chunks) = try await DocumentProcessor().processDocument(at: url)
        let imported = chunks.map(\.text).joined(separator: "\n")
        XCTAssertTrue(imported.contains("四半期報告書"), imported)
        XCTAssertTrue(imported.contains("二行目のテキスト"), imported)
    }

    /// The import itself: a text-layer PDF page of Greek lines keeps them in its passages. Through 5.6 the
    /// garbage filter counted Latin letters and digits only, so a line in Greek, Chinese or Arabic was deleted
    /// from the page as garbage.
    func testAPDFPageOfGreekLinesImportsWithItsLines() async throws {
        let lines = [
            "Η εγγύηση επιστρέφεται μέσα σε εξήντα ημέρες από τη λήξη της μίσθωσης.",
            "Ο ενοικιαστής πληρώνει το ενοίκιο έως την πέμπτη ημέρα κάθε μήνα.",
            "Τα κατοικίδια επιτρέπονται μόνο με γραπτή άδεια του ιδιοκτήτη.",
            "Οι ώρες ησυχίας αρχίζουν στις δέκα το βράδυ κάθε ημέρα.",
        ]
        let url = try textPDF(pages: [lines])
        defer { try? FileManager.default.removeItem(at: url) }

        let (_, chunks) = try await DocumentProcessor().processDocument(at: url)
        let imported = chunks.map(\.text).joined(separator: "\n").precomposedStringWithCanonicalMapping
        for line in lines {
            XCTAssertTrue(imported.contains(line.precomposedStringWithCanonicalMapping), "\(line) is missing from: \(imported)")
        }
        // What Vision makes of a Greek page is Cyrillic and Latin look-alikes ("катокіба" for "κατοικίδια").
        XCTAssertFalse(imported.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "OCR text: \(imported)")
    }

    /// The same for Hebrew, which also reads right to left: the page keeps its words in reading order. The spatial
    /// reading orders a line's words left to right, so a right-to-left page keeps PDFKit's order.
    func testAPDFPageOfHebrewLinesImportsWithItsLinesInOrder() async throws {
        let lines = [
            "הפיקדון מוחזר תוך שישים יום מתום חוזה השכירות.",
            "חיות מחמד דורשות אישור בכתב מבעל הדירה.",
            "שעות השקט מתחילות בעשר בלילה בכל יום.",
        ]
        let url = try textPDF(pages: [lines])
        defer { try? FileManager.default.removeItem(at: url) }

        let (_, chunks) = try await DocumentProcessor().processDocument(at: url)
        let imported = chunks.map(\.text).joined(separator: "\n")
        for phrase in ["הפיקדון מוחזר תוך", "חיות מחמד דורשות", "שעות השקט מתחילות"] {
            XCTAssertTrue(imported.contains(phrase), "\(phrase) is missing or out of order in: \(imported)")
        }
    }

    /// A scanned English page whose text layer holds only a Greek line, such as a stamp: the scanned body is still
    /// read by Vision. Reading such a page from its text layer alone would keep the stamp and lose the page (review,
    /// 2026-10-19), so a page the classifier marks as a scan with a text layer over part of it is not.
    func testAScannedPageWithAGreekLineInItsTextLayerStillHasItsScannedTextRead() async throws {
        let body = [
            "The dishwasher warranty covers parts and labour for two years.",
            "Register the appliance within thirty days of delivery.",
            "Keep the receipt with the serial number from the door.",
            "The filter should be cleaned once a month with warm water.",
            "Do not use washing-up liquid in the detergent drawer.",
            "Call the service line if the drain light stays on.",
            "Load plates facing the centre of the lower basket.",
            "Glasses go in the upper basket, away from the spray arm.",
            "Run the machine empty on the hottest cycle every month.",
            "The rinse aid light means the reservoir needs a refill.",
            "Unplug the machine before you take the filter out.",
            "A full load uses less water than washing by hand.",
        ]
        let width = 1700, height = 2200
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmap = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        for (row, text) in body.enumerated() {
            let attributed = NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): bodyFont])
            bitmap.textPosition = CGPoint(x: 80, y: CGFloat(height) - 200 - CGFloat(row) * 120)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), bitmap)
        }
        let scan = try XCTUnwrap(bitmap.makeImage())

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.draw(scan, in: CGRect(x: 36, y: 36, width: 540, height: 699))
        let stamp = NSAttributedString(
            string: "ΑΚΡΙΒΕΣ ΑΝΤΙΓΡΑΦΟ ΑΠΟ ΤΟ ΠΡΩΤΟΤΥΠΟ ΤΟΥ ΠΙΣΤΟΠΟΙΗΤΙΚΟΥ ΕΓΓΥΗΣΗΣ",
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 9, nil)])
        context.textPosition = CGPoint(x: 54, y: 760)
        CTLineDraw(CTLineCreateWithAttributedString(stamp), context)
        context.endPDFPage()
        context.closePDF()

        let (_, chunks) = try await DocumentProcessor().processDocument(at: url)
        let imported = chunks.map(\.text).joined(separator: "\n").lowercased()
        for word in ["dishwasher", "warranty", "detergent", "receipt"] {
            XCTAssertTrue(imported.contains(word), "\(word) from the scanned body is missing from: \(imported)")
        }
    }


    /// Whether OCR can check a PDF's text layer: only when most of its letters are in a script Vision reads. Vision has
    /// no model for Greek or Hebrew (measured 2026-10-19), and comparing such a text layer with what OCR makes of the
    /// page judged a correct one a cipher.
    func testOCRChecksATextLayerOnlyInAScriptVisionReads() throws {
        // Read from Vision here as the app does, so a failure that left the app on its fallback set shows.
        let request = VNRecognizeTextRequest()
        OCRConfiguration.configureRequest(request)
        let languages = try request.supportedRecognitionLanguages()
        let scripts = Set(languages.compactMap {
            Locale.Language(identifier: Locale.Language(identifier: $0).maximalIdentifier).script?.identifier
        })
        XCTAssertEqual(OCRConfiguration.scriptsVisionCanRead, scripts, "\(languages)")
        XCTAssertTrue(OCRConfiguration.scriptsVisionCanRead.contains("Latn"))
        XCTAssertFalse(OCRConfiguration.scriptsVisionCanRead.contains("Grek"), "Vision now reads Greek: this test's premise has changed")
        XCTAssertTrue(OCRConfiguration.isMostlyRightToLeft("הפיקדון מוחזר תוך שישים יום מתום חוזה השכירות."))
        XCTAssertTrue(OCRConfiguration.isMostlyRightToLeft("يتم رد التأمين خلال ستين يوما من انتهاء عقد الإيجار."))
        XCTAssertFalse(OCRConfiguration.isMostlyRightToLeft("The security deposit is refunded within sixty days."))
        XCTAssertFalse(OCRConfiguration.isMostlyRightToLeft("Η εγγύηση επιστρέφεται μέσα σε εξήντα ημέρες."))
        let readable = [
            "The security deposit is refunded within sixty days of the end of the lease.",
            "Залог возвращается в течение шестидесяти дней после окончания аренды.",
            "敷金は賃貸契約の終了から六十日以内に返還されます。ペットは許可が必要です。",
            "보증금은 임대 계약 종료 후 육십 일 이내에 반환됩니다. 애완동물은 허가가 필요합니다.",
            "押金在租约结束后六十天内退还。养宠物需要房东的书面许可，安静时间从晚上十点开始。",
            "يتم رد التأمين خلال ستين يوما من انتهاء عقد الإيجار والحيوانات تحتاج إلى إذن.",
            "Η εγγύηση is refunded within sixty days of the end of the lease, as the lease says.",
            "Η εγγύηση",
        ]
        for text in readable { XCTAssertTrue(OCRConfiguration.visionCanReadMostOf(text), text) }
        let unreadable = [
            "Η εγγύηση επιστρέφεται μέσα σε εξήντα ημέρες από τη λήξη της μίσθωσης.",
            "הפיקדון מוחזר תוך שישים יום מתום חוזה השכירות, וחיות מחמד דורשות אישור.",
        ]
        for text in unreadable { XCTAssertFalse(OCRConfiguration.visionCanReadMostOf(text), text) }
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
