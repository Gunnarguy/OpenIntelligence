//
//  DocumentProcessor+MediaAndOffice.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved from DocumentProcessor.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Compression
import CoreImage
import CryptoKit
import Foundation
import Metal
import NaturalLanguage
import PDFKit
import Tokenizers
import UniformTypeIdentifiers
import Vision
import os

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

extension DocumentProcessor {
    // MARK: - Audio/Video Transcription

    /// Extract text from audio/video files using Speech.framework
    func extractTextFromAudioVideo(url: URL) async throws -> String {
        let speechService = SpeechAnalyzerService.shared

        // Check if SpeechAnalyzer can handle this file
        guard speechService.canAnalyze(url: url) else {
            throw DocumentProcessingError.audioTranscriptionFailed("Unsupported audio/video format")
        }

        // The language the file's name states, or English
        let language = Self.speechLanguage(forFilename: url.lastPathComponent)

        progressHandler?("transcribing audio")

        do {
            let result = try await speechService.analyze(url: url, language: language)

            if result.isSuccessful {
                Log.info(
                    "[DocumentProcessor] Transcribed \(result.wordCount) words from \(url.lastPathComponent) via SpeechAnalyzer",
                    category: .ingestion)
                return speechService.analysisToDocument(result, sourceFile: url.lastPathComponent)
            } else {
                throw DocumentProcessingError.audioTranscriptionEmpty
            }
        } catch let error as SpeechAnalysisError {
            Log.error("[DocumentProcessor] Speech analysis failed: \(error.localizedDescription)", category: .ingestion)
            throw DocumentProcessingError.audioTranscriptionFailed(error.localizedDescription)
        } catch let error as TranscriptionError {
            Log.error("[DocumentProcessor] Transcription failed: \(error.localizedDescription)", category: .ingestion)
            throw DocumentProcessingError.audioTranscriptionFailed(error.localizedDescription)
        }
    }

    /// The language a recording is transcribed in: the one its name states, and "en-US" when it
    /// states none. A name states a language with the language's English name ("lecture
    /// spanish.m4a") or with its two-letter code as the last word before the extension
    /// ("lecture_fr.m4a", "talk-de.mp3"). Through 5.6 the code was matched anywhere after an
    /// underscore, so "notes_friday.m4a" was transcribed as French, "plans_december.m4a" as
    /// German and "taxes_january.m4a" as Japanese.
    nonisolated static func speechLanguage(forFilename name: String) -> String {
        let stem = (name as NSString).deletingPathExtension.lowercased()
        let lastWord = stem.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).last.map(String.init)
        let hints: [(code: String, word: String, locale: String)] = [
            ("es", "spanish", "es-ES"), ("fr", "french", "fr-FR"), ("de", "german", "de-DE"),
            ("zh", "chinese", "zh-CN"), ("ja", "japanese", "ja-JP"),
        ]
        for hint in hints where lastWord == hint.code || stem.contains(hint.word) {
            return hint.locale
        }
        return "en-US"
    }

    /// Extract text from Office documents (Word, Excel, PowerPoint, iWork)
    func extractTextFromOfficeDocument(url: URL, type: DocumentType) async throws -> String {
        // For iWork documents (.pages, .numbers, .keynote), they're actually ZIP packages
        if type == .pages || type == .numbers || type == .keynote {
            return try extractTextFromIWorkDocument(url: url)
        }

        // For Microsoft Office formats, attempt extraction
        // .docx, .xlsx, .pptx are also ZIP packages with XML
        if type == .word || type == .excel || type == .powerpoint {
            return try extractTextFromOfficeXML(url: url, type: type)
        }

        // Legacy .doc, .xls, .ppt - limited support
        Log.warning("[DocumentProcessor] Legacy Office format detected", category: .ingestion)
        Log.info(
            "[DocumentProcessor] Suggestion: Convert to .docx, .xlsx, or .pptx for better support", category: .ingestion
        )
        throw DocumentProcessingError.legacyOfficeFormat
    }

    /// Extract text from iWork documents (Pages, Numbers, Keynote)
    private func extractTextFromIWorkDocument(url: URL) throws -> String {
        // iWork documents are packages - look for index.xml or similar
        // This is a simplified implementation
        Log.warning(
            "[DocumentProcessor] iWork content is not readable: modern Pages/Numbers/Keynote store "
                + "text as compressed protobuf in Index/*.iwa, which this app does not parse",
            category: .ingestion
        )
        Log.info("[DocumentProcessor] Suggestion: Export as PDF or text for full compatibility", category: .ingestion)

        // Try to read as a package
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Look for text content in the package
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                if file.pathExtension == "xml" || file.pathExtension == "txt" {
                    if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                        // Basic XML stripping for text extraction
                        let text = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return text
                        }
                    }
                }
            }
        }

        throw DocumentProcessingError.iWorkExtractionFailed
    }

    /// Extract text from modern Office XML formats (.docx, .xlsx, .pptx)
    /// These are ZIP archives containing XML with the actual content
    private func extractTextFromOfficeXML(url: URL, type: DocumentType) throws -> String {
        // Modern Office formats are ZIP files with XML content inside
        // .docx: word/document.xml
        // .xlsx: xl/sharedStrings.xml + xl/worksheets/sheet*.xml
        // .pptx: ppt/slides/slide*.xml

        Log.info("[DocumentProcessor] Extracting Office XML: \(url.lastPathComponent)", category: .ingestion)

        // Read the file as data and extract using Archive (iOS 16+)
        guard let archive = ZIPArchive(url: url) else {
            Log.warning("[DocumentProcessor] Failed to open as ZIP archive", category: .ingestion)
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        var extractedText = ""

        switch type {
        case .word:
            // Heading styles and list numbering (5.8): a "Heading 2" paragraph was stored as plain text and a
            // numbered item "1.1." as "• ".
            let paragraphStyles = Self.wordParagraphStyles(
                stylesXML: archive.extractString(path: "word/styles.xml"),
                numberingXML: archive.extractString(path: "word/numbering.xml"))
            // Word documents: main content is in word/document.xml
            if let documentXML = archive.extractString(path: "word/document.xml") {
                extractedText = extractTextFromWordXML(documentXML, styles: paragraphStyles)
            }
            // Headers/footers (stop at first miss, don't loop to 10)
            for i in 1...20 {
                if let headerXML = archive.extractString(path: "word/header\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(headerXML, styles: paragraphStyles)
                } else if i > 3 {
                    break
                }  // At least check 1–3
                if let footerXML = archive.extractString(path: "word/footer\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(footerXML, styles: paragraphStyles)
                }
            }
            // Footnotes and endnotes — important for academic/legal documents
            if let footnotesXML = archive.extractString(path: "word/footnotes.xml") {
                let footnoteText = extractTextFromWordXML(footnotesXML, styles: paragraphStyles)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !footnoteText.isEmpty {
                    extractedText += "\n\nFootnotes:\n" + footnoteText
                }
            }
            if let endnotesXML = archive.extractString(path: "word/endnotes.xml") {
                let endnoteText = extractTextFromWordXML(endnotesXML, styles: paragraphStyles)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !endnoteText.isEmpty {
                    extractedText += "\n\nEndnotes:\n" + endnoteText
                }
            }

        case .excel:
            // Excel: shared strings + worksheet cells
            var sharedStrings: [String] = []
            if let sharedStringsXML = archive.extractString(path: "xl/sharedStrings.xml") {
                sharedStrings = Self.sharedStringsFromExcel(sharedStringsXML)
            }
            // Number formats and the date system (5.8): a date cell was stored as its serial ("45292", not
            // "2024-01-01").
            let workbookXML = archive.extractString(path: "xl/workbook.xml")
            let numberStyles = Self.spreadsheetNumberStyles(
                stylesXML: archive.extractString(path: "xl/styles.xml"), workbookXML: workbookXML)
            // Sheets in the workbook's own order, under their names (5.8): files were read as sheet1.xml,
            // sheet2.xml, ... until the first missing number, so a workbook whose first sheet was deleted lost
            // every sheet, and no passage said which sheet it came from.
            let sheets =
                workbookXML.map {
                    Self.spreadsheetSheets(
                        workbookXML: $0, relationshipsXML: archive.extractString(path: "xl/_rels/workbook.xml.rels"))
                } ?? []
            if sheets.isEmpty {
                for i in 1...100 {
                    guard let sheetXML = archive.extractString(path: "xl/worksheets/sheet\(i).xml") else { continue }
                    extractedText += extractTextFromExcelSheet(
                        sheetXML, sharedStrings: sharedStrings, styles: numberStyles)
                    extractedText += "\n\n"
                }
            } else {
                for sheet in sheets {
                    guard let sheetXML = archive.extractString(path: sheet.path) else { continue }
                    let table = extractTextFromExcelSheet(sheetXML, sharedStrings: sharedStrings, styles: numberStyles)
                    guard !table.isEmpty else { continue }
                    extractedText += "## Sheet: \(sheet.name)\(sheet.hidden ? " (hidden)" : "")\n\n" + table + "\n\n"
                }
            }

        case .powerpoint:
            // PowerPoint: slides contain text, notes contain speaker notes
            for i in 1...500 {
                if let slideXML = archive.extractString(path: "ppt/slides/slide\(i).xml") {
                    let slideText = extractTextFromPowerPointSlide(slideXML)
                    extractedText += "Slide \(i):\n" + slideText

                    // Speaker notes — often contain the most detailed information
                    if let notesXML = archive.extractString(path: "ppt/notesSlides/notesSlide\(i).xml") {
                        let notesText = extractTextFromPowerPointSlide(notesXML)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !notesText.isEmpty && notesText != "\(i)" {
                            // Skip notes that are just the slide number
                            extractedText += "\nNotes: " + notesText
                        }
                    }

                    extractedText += "\n\n---\n\n"  // Slide separator
                } else {
                    break
                }
            }

        default:
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.warning("[DocumentProcessor] No text extracted from Office document", category: .ingestion)
            throw DocumentProcessingError.officeFormatNeedsConversion
        }

        Log.info("[DocumentProcessor] Extracted \(trimmed.count) chars from Office document", category: .ingestion)
        return trimmed
    }

    /// Extract text from Word XML with table, list, and run-spacing support.
    /// Parses `<w:tbl>` → `<w:tr>` → `<w:tc>` hierarchy for tables.
    /// Joins `<w:t>` runs within a paragraph with proper whitespace.
    /// The XML's five named entities and numeric character references as characters (5.8): "&amp;" and "&lt;" were stored
    /// as written.
    nonisolated static func decodingXMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result), let codeRange = Range(match.range(at: 1), in: result)
                else { continue }
                let code = String(result[codeRange])
                let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                if let value, let scalar = Unicode.Scalar(value) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// Word run elements that stand for text, rewritten as `<w:t>` runs so the text readers below see them.
    nonisolated static func wordXMLWithInlineText(_ xml: String) -> String {
        var result = xml
        result = result.replacingOccurrences(
            of: #"<w:noBreakHyphen\s*/>"#, with: "<w:t>-</w:t>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<w:softHyphen\s*/>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"<w:tab\s*/>"#, with: "<w:t xml:space=\"preserve\"> </w:t>", options: .regularExpression)
        // A line, column or page break and a carriage return are a line break (5.8): written outside any <w:t>, the
        // break was dropped and "123 Main St<w:br/>Springfield" was stored as "123 Main StSpringfield". In a table
        // cell the line break is written "<br>" by `pipeTableCell`.
        result = result.replacingOccurrences(
            of: #"<w:br\b[^>]*/>|<w:cr\s*/>"#, with: "<w:t xml:space=\"preserve\">\n</w:t>", options: .regularExpression
        )
        // Symbol-font characters, by their Symbol encoding (the PUA code minus 0xF000).
        let symbolFont: [String: String] = [
            "B1": "±", "B3": "≥", "A3": "≤", "B0": "°", "D7": "×", "B8": "÷", "6D": "µ", "61": "α", "62": "β",
            "67": "γ",
            "64": "δ", "6C": "λ", "73": "σ", "70": "π", "57": "Ω", "AE": "→", "DE": "⇒", "BB": "≈", "B9": "≠",
            "A5": "∞",
        ]
        if let symbol = try? NSRegularExpression(pattern: #"<w:sym\b[^>]*w:char="(?:F0)?([0-9A-Fa-f]{2})"[^>]*/>"#) {
            for match in symbol.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result), let codeRange = Range(match.range(at: 1), in: result)
                else { continue }
                let character = symbolFont[result[codeRange].uppercased()] ?? ""
                result.replaceSubrange(range, with: character.isEmpty ? "" : "<w:t>\(character)</w:t>")
            }
        }
        // A superscript run's text is marked "^" so "10<sup>3</sup>" reads "10^3", not "103".
        if let superscript = try? NSRegularExpression(
            pattern: #"(<w:r\b(?:(?!</w:r>).)*?<w:vertAlign w:val="superscript"\s*/>(?:(?!</w:r>).)*?<w:t\b[^>]*>)"#,
            options: [.dotMatchesLineSeparators])
        {
            result = superscript.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1^")
        }
        return result
    }

    /// Word markup that put text in the wrong place or twice, rewritten before any text is read (5.8).
    /// - `<mc:Fallback>` is a second copy of a drawing for readers that do not know its `<mc:Choice>`; a text box
    ///   is in both, so its text was stored twice.
    /// - `<w:moveFrom>` is where tracked-changes text was moved from; the text is also at its `<w:moveTo>`, so
    ///   moved text was stored twice. `<w:pPrChange>` and `<w:rPrChange>` hold the formatting before a tracked
    ///   change, which would be read as the paragraph's own.
    /// - A text box's paragraphs (`<w:txbxContent>`) sit inside a run of the paragraph that anchors it. The
    ///   paragraph reader stopped at the box's first `</w:p>`, so the anchor's text after the box was lost. The
    ///   box's paragraphs are moved to just after the anchor paragraph, innermost box first.
    nonisolated static func wordXMLWithTextBoxesLifted(_ xml: String) -> String {
        var result = xml
        for (marker, pattern) in [
            ("mc:Fallback", #"(?s)<mc:Fallback\b[^>]*/>|<mc:Fallback\b[^>]*>.*?</mc:Fallback>"#),
            ("w:moveFrom", #"(?s)<w:moveFrom\b[^>]*/>|<w:moveFrom\b[^>]*>.*?</w:moveFrom>"#),
            ("w:pPrChange", #"(?s)<w:pPrChange\b[^>]*/>|<w:pPrChange\b[^>]*>.*?</w:pPrChange>"#),
            ("w:rPrChange", #"(?s)<w:rPrChange\b[^>]*/>|<w:rPrChange\b[^>]*>.*?</w:rPrChange>"#),
        ] where result.contains(marker) {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        guard result.contains("w:txbxContent"),
            let box = try? NSRegularExpression(
                pattern: #"<w:txbxContent\b[^>]*>((?:(?!<w:txbxContent\b).)*?)</w:txbxContent>"#,
                options: [.dotMatchesLineSeparators])
        else { return result }
        let text = NSMutableString(string: result)
        var lifted = 0
        while lifted < 1_000,
            let match = box.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
        {
            let paragraphs = text.substring(with: match.range(at: 1))
            text.deleteCharacters(in: match.range)
            let anchorEnd = text.range(
                of: "</w:p>", range: NSRange(location: match.range.location, length: text.length - match.range.location)
            )
            text.insert(paragraphs, at: anchorEnd.location == NSNotFound ? text.length : NSMaxRange(anchorEnd))
            lifted += 1
        }
        return text as String
    }

    /// What `word/styles.xml` and `word/numbering.xml` say about paragraphs: which styles are headings and how
    /// each list level is numbered. Read once per document; the reference is ECMA-376 Part 1 (17.7 styles,
    /// 17.9 numbering) and docling's msword backend, which reads the same two parts.
    nonisolated struct WordParagraphStyles: Sendable {
        nonisolated struct ListLevel: Sendable {
            var start = 1
            /// `w:numFmt`: "decimal", "lowerLetter", "upperRoman", "bullet", "none", ...
            var format = "decimal"
            /// `w:lvlText`: "%1." or "%1.%2." where %N is level N's number.
            var text = "%1."
        }
        /// Heading level 1 to 6 by style id: "Title" is 1, "heading N" is N, otherwise the style's outline level.
        var headingLevels: [String: Int] = [:]
        /// The list and level a paragraph style numbers its paragraphs with ("List Number"), by style id.
        var styleLists: [String: (list: Int, level: Int)] = [:]
        /// List levels by `w:numId`, then by `w:ilvl`.
        var lists: [Int: [Int: ListLevel]] = [:]
    }

    /// The first capture of `pattern` in `text`.
    nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    /// Every match of `pattern` in `text`, each as its captures (an empty string for a group that did not take part).
    nonisolated static func allCaptures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// An attribute's value in one XML start tag, by its qualified name ("w:val", "r:id", "name").
    nonisolated static func xmlAttribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(#"(?:^|\s)"# + escaped + #"\s*=\s*"([^"]*)""#, in: tag)
            ?? firstCapture(#"(?:^|\s)"# + escaped + #"\s*=\s*'([^']*)'"#, in: tag)
    }

    nonisolated static func wordParagraphStyles(stylesXML: String?, numberingXML: String?) -> WordParagraphStyles {
        var result = WordParagraphStyles()
        if let stylesXML {
            var styles: [String: (name: String, basedOn: String?, outline: Int?, list: (list: Int, level: Int)?)] = [:]
            for captures in allCaptures(#"<w:style\b([^>]*)>(.*?)</w:style>"#, in: stylesXML) {
                let attributes = captures[1]
                let body = captures[2]
                guard xmlAttribute("w:type", in: attributes) == "paragraph",
                    let id = xmlAttribute("w:styleId", in: attributes)
                else { continue }
                var list: (list: Int, level: Int)?
                if let number = firstCapture(#"<w:numId\b[^>]*\bw:val="([0-9]+)""#, in: body).flatMap({ Int($0) }) {
                    let level = firstCapture(#"<w:ilvl\b[^>]*\bw:val="([0-9]+)""#, in: body).flatMap { Int($0) }
                    list = (number, level ?? 0)
                }
                styles[id] = (
                    name: firstCapture(#"<w:name\b[^>]*\bw:val="([^"]*)""#, in: body)?.lowercased() ?? "",
                    basedOn: firstCapture(#"<w:basedOn\b[^>]*\bw:val="([^"]*)""#, in: body),
                    outline: firstCapture(#"<w:outlineLvl\b[^>]*\bw:val="([0-9]+)""#, in: body).flatMap { Int($0) },
                    list: list
                )
            }
            for id in styles.keys {
                // A style inherits from the style it is based on: a custom "Clause Heading" based on "Heading 2".
                var current: String? = id
                var depth = 0
                var heading: Int?
                var list: (list: Int, level: Int)?
                while let styleID = current, let style = styles[styleID], depth < 10 {
                    if heading == nil {
                        if style.name == "title" {
                            heading = 1
                        } else if let number = firstCapture(#"^heading ([1-9])$"#, in: style.name).flatMap({ Int($0) })
                        {
                            heading = number
                        } else if let outline = style.outline, outline < 9 {
                            heading = outline + 1
                        }
                    }
                    if list == nil { list = style.list }
                    current = style.basedOn
                    depth += 1
                }
                if let heading { result.headingLevels[id] = min(heading, 6) }
                if let list, list.list != 0 { result.styleLists[id] = list }
            }
        }
        if let numberingXML {
            var abstractLevels: [Int: [Int: WordParagraphStyles.ListLevel]] = [:]
            for captures in allCaptures(#"<w:abstractNum\b([^>]*)>(.*?)</w:abstractNum>"#, in: numberingXML) {
                guard let id = xmlAttribute("w:abstractNumId", in: captures[1]).flatMap({ Int($0) }) else { continue }
                var levels: [Int: WordParagraphStyles.ListLevel] = [:]
                for level in allCaptures(#"<w:lvl\b([^>]*)>(.*?)</w:lvl>"#, in: captures[2]) {
                    guard let index = xmlAttribute("w:ilvl", in: level[1]).flatMap({ Int($0) }) else { continue }
                    var definition = WordParagraphStyles.ListLevel()
                    if let start = firstCapture(#"<w:start\b[^>]*\bw:val="(-?[0-9]+)""#, in: level[2]).flatMap({
                        Int($0)
                    }) {
                        definition.start = start
                    }
                    definition.format = firstCapture(#"<w:numFmt\b[^>]*\bw:val="([^"]*)""#, in: level[2]) ?? "decimal"
                    definition.text = decodingXMLEntities(
                        firstCapture(#"<w:lvlText\b[^>]*\bw:val="([^"]*)""#, in: level[2]) ?? "")
                    levels[index] = definition
                }
                abstractLevels[id] = levels
            }
            for captures in allCaptures(#"<w:num\b([^>]*)>(.*?)</w:num>"#, in: numberingXML) {
                guard let id = xmlAttribute("w:numId", in: captures[1]).flatMap({ Int($0) }),
                    let abstract = firstCapture(#"<w:abstractNumId\b[^>]*\bw:val="([0-9]+)""#, in: captures[2])
                        .flatMap({ Int($0) })
                else { continue }
                var levels = abstractLevels[abstract] ?? [:]
                for override in allCaptures(#"<w:lvlOverride\b([^>]*)>(.*?)</w:lvlOverride>"#, in: captures[2]) {
                    guard let index = xmlAttribute("w:ilvl", in: override[1]).flatMap({ Int($0) }),
                        let start = firstCapture(#"<w:startOverride\b[^>]*\bw:val="(-?[0-9]+)""#, in: override[2])
                            .flatMap({ Int($0) })
                    else { continue }
                    levels[index, default: WordParagraphStyles.ListLevel()].start = start
                }
                result.lists[id] = levels
            }
        }
        return result
    }

    /// A list number in a `w:numFmt` format: 3 is "3", "c", "C", "iii" or "III".
    nonisolated static func wordListNumber(_ value: Int, format: String) -> String {
        switch format {
        case "lowerLetter", "upperLetter":
            guard value > 0 else { return String(value) }
            // Word repeats the letter past z: 27 is "aa", 28 "bb".
            let letter = Character(Unicode.Scalar(UInt8(97 + (value - 1) % 26)))
            let text = String(repeating: letter, count: (value - 1) / 26 + 1)
            return format == "upperLetter" ? text.uppercased() : text
        case "lowerRoman", "upperRoman":
            guard value > 0, value < 4_000 else { return String(value) }
            let numerals: [(Int, String)] = [
                (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
                (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
            ]
            var remaining = value
            var text = ""
            for (amount, numeral) in numerals {
                while remaining >= amount {
                    text += numeral
                    remaining -= amount
                }
            }
            return format == "upperRoman" ? text.uppercased() : text
        case "decimalZero":
            return value < 10 ? "0\(value)" : String(value)
        case "none":
            return ""
        default:
            return String(value)
        }
    }

    func extractTextFromWordXML(_ rawXML: String, styles: WordParagraphStyles? = nil) -> String {
        // Run elements other than <w:t> that carry text, written as text first (5.8): a non-breaking hyphen
        // ("1‑2" became "12"), a tab (words fused), a Symbol-font character (± ≥ µ were lost) and superscript runs.
        let xml = Self.wordXMLWithInlineText(Self.wordXMLWithTextBoxesLifted(rawXML))
        var result = ""
        // The number each list has reached at each level, by `w:numId`.
        var listCounters: [Int: [Int: Int]] = [:]

        // STEP 1: Extract tables separately and replace them with placeholders
        // This prevents table text from being mixed into paragraph flow
        var tableTexts: [String] = []
        var processedXML = xml

        let tablePattern = #"<w:tbl\b[^>]*>.*?</w:tbl>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..., in: xml)
            var matches: [NSTextCheckingResult] = []
            tableRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                if let match = match { matches.append(match) }
            }

            // The placeholder is wrapped in a `<w:p>` rather than left as bare text.
            //
            // Every table in every .docx was previously extracted and then silently discarded. STEP 2
            // below builds `result` exclusively from `<w:p>...</w:p>` matches, and in OOXML a `<w:tbl>`
            // is a *sibling* of `<w:p>` inside `<w:body>`, never nested inside one. So a bare
            // "[[TABLE_0]]" written where the table used to be sat outside every paragraph match, never
            // entered `result`, and STEP 3's substitution then found nothing to replace. The table text
            // was computed, held in `tableTexts`, and dropped on the floor. Wrapping the placeholder in
            // a paragraph puts it back in the one stream STEP 2 actually reads, and keeps it at the
            // table's original position in the document.
            //
            // Matches are replaced back-to-front so earlier ranges stay valid. Indexing by document
            // order rather than by append order is a readability change, not a second fix: numbering
            // by `tableTexts.count` while walking in reverse labelled the last table 0, but it also
            // stored that table's text at index 0, so the pairing was reversed and self-consistent.
            // Document order is worth having anyway, because the placeholder number now matches the
            // table's position on the page when this has to be debugged from a log.
            var orderedTableTexts = [String](repeating: "", count: matches.count)
            for (reverseOffset, match) in matches.reversed().enumerated() {
                let documentIndex = matches.count - 1 - reverseOffset
                if let matchRange = Range(match.range, in: processedXML) {
                    let tableXML = String(processedXML[matchRange])
                    orderedTableTexts[documentIndex] = extractTableFromWordXML(tableXML)
                    let placeholder = "\n<w:p><w:r><w:t>[[TABLE_\(documentIndex)]]</w:t></w:r></w:p>\n"
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
            tableTexts = orderedTableTexts
        }

        // STEP 2: Extract paragraphs with run-level text joining
        // An empty paragraph is self-closing (`<w:p/>`); matched as an opener it swallowed the next paragraph.
        let paragraphPattern = #"<w:p\b[^>]*(?<!/)>(.*?)</w:p>"#
        let runTextPattern = #"<w:t[^>]*>([^<]*)</w:t>"#
        let breakPattern = #"<w:br\s*/?\s*>"#

        if let paraRegex = try? NSRegularExpression(pattern: paragraphPattern, options: [.dotMatchesLineSeparators]),
            let runRegex = try? NSRegularExpression(pattern: runTextPattern, options: []),
            let breakRegex = try? NSRegularExpression(pattern: breakPattern, options: [])
        {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // A heading is marked "#" per level and a list item with its own number (5.8): headings were plain
                // text, and every list item, numbered or not, was "• ". The level comes from the paragraph's
                // outline level or its style; the number from its `w:numPr` or its style's, counted per list.
                // Each pattern is tried only when its element is there; most paragraphs carry none of them.
                let properties =
                    paraContent.contains("<w:pPr")
                    ? Self.firstCapture(#"<w:pPr\b[^>]*>(.*?)</w:pPr>"#, in: paraContent) ?? "" : ""
                func property(_ element: String, _ valuePattern: String) -> String? {
                    guard properties.contains("<w:\(element)") else { return nil }
                    return Self.firstCapture("<w:\(element)\\b[^>]*\\bw:val=\"(\(valuePattern))\"", in: properties)
                }
                let styleID = property("pStyle", "[^\"]*")
                var prefix = ""
                let outline = property("outlineLvl", "[0-9]+").flatMap { Int($0) }
                if let level = outline.flatMap({ $0 < 9 ? min($0 + 1, 6) : nil })
                    ?? styleID.flatMap({ styles?.headingLevels[$0] })
                {
                    prefix = String(repeating: "#", count: level) + " "
                }
                let directList = property("numId", "[0-9]+").flatMap { Int($0) }
                let directLevel = property("ilvl", "[0-9]+").flatMap { Int($0) }
                let styleList = styleID.flatMap { styles?.styleLists[$0] }
                var list: (list: Int, level: Int)?
                if let directList {
                    // A `w:numId` of 0 switches numbering off for this paragraph (ECMA-376 Part 1, numbering).
                    if directList != 0 { list = (directList, directLevel ?? styleList?.level ?? 0) }
                } else if let styleList {
                    list = (styleList.list, directLevel ?? styleList.level)
                }
                if let list {
                    if let levels = styles?.lists[list.list], let definition = levels[list.level] {
                        var counters = (listCounters[list.list] ?? [:]).filter { $0.key <= list.level }
                        counters[list.level] = (counters[list.level] ?? definition.start - 1) + 1
                        listCounters[list.list] = counters
                        var label = definition.format == "bullet" ? "•" : definition.text
                        if definition.format != "bullet" {
                            for level in 0..<9 where label.contains("%\(level + 1)") {
                                let value = counters[level] ?? levels[level]?.start ?? 1
                                label = label.replacingOccurrences(
                                    of: "%\(level + 1)",
                                    with: Self.wordListNumber(value, format: levels[level]?.format ?? "decimal"))
                            }
                        }
                        prefix +=
                            String(repeating: "  ", count: min(list.level, 8)) + (label.isEmpty ? "" : label + " ")
                    } else {
                        prefix += "• "
                    }
                }

                // Replace <w:br/> with newline
                let processed = breakRegex.stringByReplacingMatches(
                    in: paraContent, options: [],
                    range: NSRange(paraContent.startIndex..., in: paraContent), withTemplate: "\n")

                // Extract all text runs and join with space (preserves word boundaries)
                let runRange = NSRange(processed.startIndex..., in: processed)
                var runs: [String] = []
                runRegex.enumerateMatches(in: processed, options: [], range: runRange) { runMatch, _, _ in
                    if let runMatch = runMatch, let textRange = Range(runMatch.range(at: 1), in: processed) {
                        runs.append(Self.decodingXMLEntities(String(processed[textRange])))
                    }
                }

                let paragraphText = runs.joined()  // Runs within a paragraph are contiguous
                if !paragraphText.trimmingCharacters(in: .whitespaces).isEmpty {
                    result += prefix + paragraphText + "\n"
                }
            }
        }

        // STEP 3: Re-insert table text at placeholders
        for (i, tableText) in tableTexts.enumerated() {
            result = result.replacingOccurrences(of: "[[TABLE_\(i)]]", with: "\n" + tableText + "\n")
        }

        return result
    }

    /// A table cell's text as one pipe-table cell: a "|" in the text is written "\|" and a line break "<br>", so
    /// neither ends the cell or the row (5.8: "Seal | gasket" became two cells and a two-line address split its row
    /// across two lines, the second outside every column).
    nonisolated static func pipeTableCell(_ text: String) -> String {
        guard text.contains("|") || text.contains(where: \.isNewline) else { return text }
        return text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: #"[ \t]*(?:\r\n|\r|\n)[ \t]*"#, with: "<br>", options: .regularExpression)
    }

    /// The text of a Word or PowerPoint table cell: each paragraph's runs joined, the paragraphs joined with
    /// " <br> " (5.8: "Check seal" and "Replace filter" in one cell were stored as "Check sealReplace filter"),
    /// and written as one pipe-table cell.
    nonisolated static func officeTableCellText(
        _ cellXML: String, paragraphPattern: String, textRegex: NSRegularExpression
    ) -> String {
        func runText(_ xml: String) -> String {
            textRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
                Range(match.range(at: 1), in: xml).map { decodingXMLEntities(String(xml[$0])) }
            }.joined()
        }
        let paragraphs = allCaptures(paragraphPattern, in: cellXML).map { runText($0[1]) }
        let lines = (paragraphs.isEmpty ? [runText(cellXML)] : paragraphs)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.map(pipeTableCell).joined(separator: " <br> ")
    }

    /// Extract a single Word XML table as pipe-separated text
    /// Parses `<w:tbl>` → `<w:tr>` → `<w:tc>` → `<w:t>` hierarchy
    private func extractTableFromWordXML(_ tableXML: String) -> String {
        let rowPattern = #"<w:tr\b[^>]*>(.*?)</w:tr>"#
        let cellPattern = #"<w:tc\b[^>]*>(.*?)</w:tc>"#
        let textPattern = #"<w:t[^>]*>([^<]*)</w:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
            let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
            let textRegex = try? NSRegularExpression(pattern: textPattern, options: [])
        else {
            return ""
        }

        var tableRows: [[String]] = []

        let rowRange = NSRange(tableXML.startIndex..., in: tableXML)
        rowRegex.enumerateMatches(in: tableXML, options: [], range: rowRange) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContent = Range(rowMatch.range(at: 1), in: tableXML) else { return }
            let rowStr = String(tableXML[rowContent])
            var cells: [String] = []

            let cellRange = NSRange(rowStr.startIndex..., in: rowStr)
            cellRegex.enumerateMatches(in: rowStr, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else {
                    return
                }
                let cellStr = String(rowStr[cellContent])
                cells.append(
                    Self.officeTableCellText(
                        cellStr, paragraphPattern: #"<w:p\b[^>]*(?<!/)>(.*?)</w:p>"#, textRegex: textRegex))
            }

            if !cells.allSatisfy({ $0.isEmpty }) {
                tableRows.append(cells)
            }
        }

        // Format as pipe-separated table with header separator
        guard !tableRows.isEmpty else { return "" }

        var output = ""
        for (i, row) in tableRows.enumerated() {
            output += "| " + row.joined(separator: " | ") + " |\n"
            if i == 0 {
                // Add header separator after first row
                output += "|" + row.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return output
    }

    /// Extract shared strings from Excel (these are referenced by index in sheets)
    /// Handles rich text strings with multiple `<r><t>` runs within a single `<si>` element.
    /// The strings are as written in the XML; `decodingSpreadsheetText` reads them.
    /// An empty string is written `<si/>`; it was not matched, so every later index pointed one string too far
    /// (5.8). A phonetic reading (`<rPh>`, Japanese furigana) is not part of the text and is left out (5.8).
    nonisolated static func sharedStringsFromExcel(_ xml: String) -> [String] {
        var strings: [String] = []

        // Match each <si>...</si> block, then extract ALL <t> tags within it
        let siPattern = #"<si(?:\s[^>]*)?(?:/>|>(.*?)</si>)"#
        let tPattern = #"<t(?:\s[^>]*)?>([^<]*)</t>"#

        guard let siRegex = try? NSRegularExpression(pattern: siPattern, options: [.dotMatchesLineSeparators]),
            let tRegex = try? NSRegularExpression(pattern: tPattern, options: [])
        else {
            return strings
        }

        let range = NSRange(xml.startIndex..., in: xml)
        siRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            guard let contentRange = Range(match.range(at: 1), in: xml) else {
                strings.append("")
                return
            }
            var siContent = String(xml[contentRange])
            if siContent.contains("<rPh") {
                siContent = siContent.replacingOccurrences(
                    of: #"(?s)<rPh\b[^>]*/>|<rPh\b[^>]*>.*?</rPh>"#, with: "", options: .regularExpression)
            }

            // Concatenate ALL <t> fragments within this shared string
            var fragments: [String] = []
            let tRange = NSRange(siContent.startIndex..., in: siContent)
            tRegex.enumerateMatches(in: siContent, options: [], range: tRange) { tMatch, _, _ in
                if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: siContent) {
                    fragments.append(String(siContent[textRange]))
                }
            }
            strings.append(fragments.joined())
        }

        return strings
    }

    /// A spreadsheet string as its text: XML entities first, then the `_xHHHH_` escapes OOXML writes for a
    /// character XML cannot hold (ECMA-376 `ST_Xstring`): "_x000D_" is a carriage return, and "_x005F_" an
    /// underscore, so "_x005F_x000D_" is the literal "_x000D_".
    nonisolated static func decodingSpreadsheetText(_ raw: String) -> String {
        let text = decodingXMLEntities(raw)
        guard text.contains("_x"),
            let regex = try? NSRegularExpression(pattern: "_x([0-9A-Fa-f]{4})_")
        else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let code = UInt32(source.substring(with: match.range(at: 1)), radix: 16)
            result +=
                code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        return result + source.substring(from: cursor)
    }

    /// How a workbook shows its numbers, as far as text needs it: which cell formats (`s`, an index into
    /// `<cellXfs>` in `xl/styles.xml`) are dates or durations, and whether the workbook counts days from 1904.
    nonisolated struct SpreadsheetNumberStyles: Sendable {
        nonisolated enum Kind: Sendable, Equatable {
            case date
            /// An elapsed time ("[h]:mm:ss"): 1.5 is 36 hours, not 31 December 1899 at noon.
            case duration
        }
        var kinds: [Int: Kind] = [:]
        var date1904 = false
        static let plain = SpreadsheetNumberStyles()
    }

    nonisolated static func spreadsheetNumberStyles(stylesXML: String?, workbookXML: String?) -> SpreadsheetNumberStyles
    {
        var result = SpreadsheetNumberStyles()
        if let workbookXML,
            let tag = firstCapture(#"(<(?:\w+:)?workbookPr\b[^>]*>)"#, in: workbookXML),
            let flag = xmlAttribute("date1904", in: tag)
        {
            result.date1904 = flag == "1" || flag.lowercased() == "true"
        }
        guard let stylesXML else { return result }
        var customFormats: [Int: String] = [:]
        for captures in allCaptures(#"(<(?:\w+:)?numFmt\b[^>]*>)"#, in: stylesXML) {
            guard let id = xmlAttribute("numFmtId", in: captures[1]).flatMap({ Int($0) }),
                let code = xmlAttribute("formatCode", in: captures[1])
            else { continue }
            customFormats[id] = decodingXMLEntities(code)
        }
        guard let cellFormats = firstCapture(#"<(?:\w+:)?cellXfs\b[^>]*>(.*?)</(?:\w+:)?cellXfs>"#, in: stylesXML)
        else { return result }
        for (index, captures) in allCaptures(#"(<(?:\w+:)?xf\b[^>]*>)"#, in: cellFormats).enumerated() {
            let id = xmlAttribute("numFmtId", in: captures[1]).flatMap { Int($0) } ?? 0
            if let kind = spreadsheetNumberFormatKind(id: id, code: customFormats[id]) { result.kinds[index] = kind }
        }
        return result
    }

    /// Whether a number format shows a date or a duration, by openpyxl's `is_date_format` and
    /// `is_timedelta_format`: built-in formats 14 to 22 and 45 to 47 are dates and times, 46 ("[h]:mm:ss") a
    /// duration; a custom format is a date when its first section, without quoted text and bracketed locale or
    /// colour codes, has an unescaped d, m, h, y or s.
    nonisolated static func spreadsheetNumberFormatKind(id: Int, code: String?) -> SpreadsheetNumberStyles.Kind? {
        guard let code else {
            switch id {
            case 46: return .duration
            case 14...22, 45, 47: return .date
            default: return nil
            }
        }
        let firstSection = code.components(separatedBy: ";")[0]
        if firstSection.range(
            of: #"^(?:\[hh?\](?::mm(?::ss(?:\.0*)?)?)?|\[mm?\](?::ss(?:\.0*)?)?|\[ss?\](?:\.0*)?)"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        {
            return .duration
        }
        let stripped = firstSection.replacingOccurrences(
            of: #"".*?"|\[(?!hh?\]|mm?\]|ss?\])[^\]]*\]"#, with: "", options: .regularExpression)
        return stripped.range(of: #"(?<![_\\])[dmhysDMHYS]"#, options: .regularExpression) != nil ? .date : nil
    }

    /// A cell's number as text: a date as an ISO 8601 date ("2024-01-01", with " 10:30:00" when it has a time
    /// of day, and only the time when it is under one day), a duration as hours, minutes and seconds, and any other
    /// number as written, to Excel's 15 significant digits.
    nonisolated static func spreadsheetDisplayValue(
        _ raw: String, kind: SpreadsheetNumberStyles.Kind?, date1904: Bool
    ) -> String {
        guard let number = Double(raw), number.isFinite else { return raw }
        switch kind {
        case .date?:
            if let text = spreadsheetDateText(serial: number, date1904: date1904) { return text }
        case .duration?:
            let seconds = Int((abs(number) * 86_400).rounded())
            let text = String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            return number < 0 ? "-" + text : text
        case nil:
            break
        }
        return spreadsheetNumberText(raw)
    }

    /// A number as written in the sheet, without the binary noise of its last digits. Excel keeps 15 significant
    /// digits and writes up to 17, so 1234.56 is stored as "1234.5600000000001"; that is read back at 15 digits and
    /// written in its shortest form. A whole number is kept as written, and ".0" is dropped when the source had no
    /// decimal point ("1E2" is "100").
    nonisolated static func spreadsheetNumberText(_ raw: String) -> String {
        if raw.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil { return raw }
        guard let number = Double(raw), number.isFinite,
            let rounded = Double(String(format: "%.15g", number))
        else { return raw }
        var text = rounded.description
        if text.hasSuffix(".0") && !raw.contains(".") { text.removeLast(2) }
        return text
    }

    /// A date serial as an ISO 8601 date. Day 0 is 1899-12-30 and one day is added below day 60, because Excel
    /// counts Lotus 1-2-3's nonexistent 1900-02-29 as day 60: serial 1 is 1900-01-01, 59 is 1900-02-28 and 61 is
    /// 1900-03-01 (60 is written 1900-02-28). In a 1904 workbook day 0 is 1904-01-01. Nil past 9999-12-31.
    nonisolated static func spreadsheetDateText(serial: Double, date1904: Bool) -> String? {
        guard serial.isFinite, serial >= 0, serial < 2_958_466 else { return nil }
        let totalSeconds = Int((serial * 86_400).rounded())
        let wholeDays = totalSeconds / 86_400
        let secondOfDay = totalSeconds % 86_400
        let time = String(format: "%02d:%02d:%02d", secondOfDay / 3_600, secondOfDay / 60 % 60, secondOfDay % 60)
        if wholeDays == 0 { return time }
        // Days since 1970-01-01, then the civil date by Howard Hinnant's days-to-civil algorithm.
        let days = (date1904 ? -24_107 : -25_569 + (serial < 60 ? 1 : 0)) + wholeDays
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        let date = String(format: "%04d-%02d-%02d", year, month, day)
        return secondOfDay == 0 ? date : date + " " + time
    }

    /// A workbook's sheets in its own order (`<sheets>` in `xl/workbook.xml`), each with its name, the part that
    /// holds its cells (by `r:id` through `xl/_rels/workbook.xml.rels`) and whether it is hidden. Chart sheets
    /// have no cells and are left out.
    nonisolated static func spreadsheetSheets(
        workbookXML: String, relationshipsXML: String?
    ) -> [(name: String, path: String, hidden: Bool)] {
        var targets: [String: String] = [:]
        for captures in allCaptures(#"(<(?:\w+:)?Relationship\b[^>]*>)"#, in: relationshipsXML ?? "") {
            let tag = captures[1]
            guard let id = xmlAttribute("Id", in: tag), let target = xmlAttribute("Target", in: tag) else { continue }
            if let type = xmlAttribute("Type", in: tag), !type.hasSuffix("/worksheet") { continue }
            var path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            while let parent = path.range(of: #"[^/]+/\.\./"#, options: .regularExpression) {
                path.removeSubrange(parent)
            }
            targets[id] = path
        }
        var sheets: [(name: String, path: String, hidden: Bool)] = []
        for (position, captures) in allCaptures(#"(<(?:\w+:)?sheet\b[^>]*>)"#, in: workbookXML).enumerated() {
            let tag = captures[1]
            let relationship = firstCapture(#"\s\w+:id\s*=\s*"([^"]*)""#, in: tag)
            let path: String
            if let relationship, let target = targets[relationship] {
                path = target
            } else if relationshipsXML == nil {
                path = "xl/worksheets/sheet\(position + 1).xml"
            } else {
                continue  // a chart sheet, or a relationship that is not there
            }
            let name = decodingXMLEntities(xmlAttribute("name", in: tag) ?? "Sheet \(position + 1)")
            let state = xmlAttribute("state", in: tag) ?? "visible"
            sheets.append((name, path, state != "visible"))
        }
        return sheets
    }

    /// A spreadsheet column's zero-based index from its letters: "A" is 0, "Z" 25, "AA" 26.
    nonisolated static func spreadsheetColumnIndex(_ letters: String) -> Int {
        letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Extract text from Excel worksheet, using shared strings for cell values.
    /// Handles cells with formulas (`<f>` before `<v>`), inline strings (`<is><t>`),
    /// and boolean/error types.
    func extractTextFromExcelSheet(
        _ xml: String, sharedStrings: [String], styles: SpreadsheetNumberStyles = .plain
    ) -> String {
        var rows: [[String]] = []

        // An empty row is self-closing (`<row r="5" ht="20" customHeight="1"/>`).
        let rowPattern = #"<row\b[^>]*(?<!/)>(.*?)</row>"#
        // More permissive cell pattern: captures type and looks for <v> OR <is><t> anywhere in cell
        // A styled empty cell is self-closing (`<c r="A1" s="2"/>`). Matched as "<c ...>" through the next "</c>" it
        // swallowed the next cell, whose type was lost, so a shared-string index ("7") was stored instead of its text (5.8).
        let cellPattern = #"<c\b([^>]*?)(?:/>|>(.*?)</c>)"#
        let referencePattern = #"\br="([A-Z]+)[0-9]+""#
        let typePattern = #"\bt="([^"]*)""#
        let valuePattern = #"<v>([^<]*)</v>"#
        let inlinePattern = #"<t[^>]*>([^<]*)</t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
            let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
            let typeRegex = try? NSRegularExpression(pattern: typePattern, options: []),
            let valueRegex = try? NSRegularExpression(pattern: valuePattern, options: []),
            let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: []),
            let referenceRegex = try? NSRegularExpression(pattern: referencePattern, options: []),
            let styleRegex = try? NSRegularExpression(pattern: #"(?:^|\s)s="([0-9]+)""#, options: [])
        else {
            return ""
        }

        let range = NSRange(xml.startIndex..., in: xml)
        rowRegex.enumerateMatches(in: xml, options: [], range: range) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContentRange = Range(rowMatch.range(at: 1), in: xml) else { return }
            let rowContent = String(xml[rowContentRange])
            var currentRow: [String] = []

            let cellRange = NSRange(rowContent.startIndex..., in: rowContent)
            cellRegex.enumerateMatches(in: rowContent, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch else { return }
                let attrsRange = Range(cellMatch.range(at: 1), in: rowContent)
                let bodyRange = Range(cellMatch.range(at: 2), in: rowContent)

                let attrs = attrsRange.map { String(rowContent[$0]) } ?? ""
                let body = bodyRange.map { String(rowContent[$0]) } ?? ""

                // Cells Excel leaves out (empty ones) are absent from the XML; a cell goes in its own column by its
                // reference ("C5" is the third), so the next cells do not shift left under the wrong header (5.8).
                if let referenceMatch = referenceRegex.firstMatch(
                    in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                    let lettersRange = Range(referenceMatch.range(at: 1), in: attrs)
                {
                    let column = Self.spreadsheetColumnIndex(String(attrs[lettersRange]))
                    while currentRow.count < column { currentRow.append("") }
                }

                // Determine cell type
                var cellType: String? = nil
                if let typeMatch = typeRegex.firstMatch(
                    in: attrs, options: [],
                    range: NSRange(attrs.startIndex..., in: attrs)),
                    let tRange = Range(typeMatch.range(at: 1), in: attrs)
                {
                    cellType = String(attrs[tRange])
                }

                // Try to get value from <v> tag
                if let valueMatch = valueRegex.firstMatch(
                    in: body, options: [],
                    range: NSRange(body.startIndex..., in: body)),
                    let vRange = Range(valueMatch.range(at: 1), in: body)
                {
                    let value = String(body[vRange])

                    switch cellType {
                    case "s":
                        let index = Int(value) ?? -1
                        currentRow.append(
                            sharedStrings.indices.contains(index)
                                ? Self.decodingSpreadsheetText(sharedStrings[index]) : "")
                    case "b":
                        currentRow.append(value == "1" ? "TRUE" : "FALSE")
                    case "str", "inlineStr", "e", "d":
                        // A formula's cached text result (`t="str"`) is XML like any other (5.8): "R&amp;D" was stored.
                        currentRow.append(Self.decodingSpreadsheetText(value))
                    default:
                        // A number, shown as a date when its style is a date format (5.8: "45292" for 2024-01-01) and
                        // otherwise to Excel's 15 significant digits ("1234.5600000000001" for 1234.56).
                        let style = styleRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs))
                            .flatMap { Range($0.range(at: 1), in: attrs) }
                            .flatMap { Int(attrs[$0]) }
                        currentRow.append(
                            Self.spreadsheetDisplayValue(
                                value, kind: style.flatMap { styles.kinds[$0] }, date1904: styles.date1904))
                    }
                } else if cellType == "inlineStr" || cellType == "str" {
                    // Inline string: extract from <is><t> or just <t>
                    let inlineBody =
                        body.contains("<rPh")
                        ? body.replacingOccurrences(
                            of: #"(?s)<rPh\b[^>]*/>|<rPh\b[^>]*>.*?</rPh>"#, with: "", options: .regularExpression)
                        : body
                    var fragments: [String] = []
                    let bRange = NSRange(inlineBody.startIndex..., in: inlineBody)
                    inlineRegex.enumerateMatches(in: inlineBody, options: [], range: bRange) { tMatch, _, _ in
                        if let tMatch = tMatch, let tRange = Range(tMatch.range(at: 1), in: inlineBody) {
                            fragments.append(String(inlineBody[tRange]))
                        }
                    }
                    currentRow.append(Self.decodingSpreadsheetText(fragments.joined()))
                } else {
                    // Empty cell
                    currentRow.append("")
                }
            }

            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return formattedPipeTableText(from: rows)
    }

    func formattedPipeTableText(from rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let columnCount = rows.map(\.count).max() ?? 0

        func normalizedRow(_ row: [String]) -> [String] {
            // A "|" or line break inside a cell is escaped (5.8): either one ended the cell or the row.
            var cells = row.map {
                Self.pipeTableCell(
                    OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(
                        in: .whitespacesAndNewlines))
            }
            if cells.count < columnCount {
                cells.append(contentsOf: Array(repeating: "", count: columnCount - cells.count))
            }
            return cells
        }

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            let cells = normalizedRow(row)
            guard cells.contains(where: { !$0.isEmpty }) else { continue }
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 && rows.count > 1 {
                lines.append("|" + Array(repeating: " --- ", count: columnCount).joined(separator: "|") + "|")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Extract text from PowerPoint slide XML with paragraph and table awareness
    /// Preserves `<a:p>` paragraph boundaries, extracts `<a:tbl>` tables as pipe-separated
    func extractTextFromPowerPointSlide(_ rawXML: String) -> String {
        // A line break inside a paragraph (`<a:br/>`, which PowerPoint writes as `<a:br><a:rPr .../></a:br>`) is
        // a line break (5.8): it had no <a:t>, so "Q3 Revenue" and "$4.2M" on two lines were stored as
        // "Q3 Revenue$4.2M". In a table cell it is written "<br>".
        let xml =
            rawXML.contains("<a:br")
            ? rawXML.replacingOccurrences(
                of: #"(?s)<a:br\b[^>]*/>|<a:br\b[^>]*>.*?</a:br>"#, with: "<a:t>\n</a:t>", options: .regularExpression)
            : rawXML
        var result = ""

        // STEP 1: Extract tables and replace with placeholders
        var tableTexts: [String] = []
        var processedXML = xml
        let tablePattern = #"<a:tbl\b[^>]*>.*?</a:tbl>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..., in: xml)
            var matches: [NSTextCheckingResult] = []
            tableRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                if let match = match { matches.append(match) }
            }
            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: processedXML) {
                    let tableXML = String(processedXML[matchRange])
                    let tableText = extractTableFromPowerPointXML(tableXML)
                    // Inside a paragraph, as for Word (5.8): a bare placeholder sat outside every <a:p> that STEP 2
                    // reads, so every table on every slide was extracted and then dropped.
                    let placeholder = "\n<a:p><a:r><a:t>[[PPTTABLE_\(tableTexts.count)]]</a:t></a:r></a:p>\n"
                    tableTexts.append(tableText)
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
        }

        // STEP 2: Extract paragraphs — <a:p> contains <a:r><a:t> text runs
        let paraPattern = #"<a:p\b[^>]*(?<!/)>(.*?)</a:p>"#
        let textPattern = #"<a:t(?:\s[^>]*)?>([^<]*)</a:t>"#

        if let paraRegex = try? NSRegularExpression(pattern: paraPattern, options: [.dotMatchesLineSeparators]),
            let textRegex = try? NSRegularExpression(pattern: textPattern, options: [])
        {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // Extract all text runs in this paragraph
                var runs: [String] = []
                let tRange = NSRange(paraContent.startIndex..., in: paraContent)
                textRegex.enumerateMatches(in: paraContent, options: [], range: tRange) { tMatch, _, _ in
                    if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: paraContent) {
                        // A run of only spaces is kept: it is the space between two words in different runs.
                        runs.append(Self.decodingXMLEntities(String(paraContent[textRange])))
                    }
                }

                let joined = runs.joined()
                if !joined.trimmingCharacters(in: .whitespaces).isEmpty {
                    result += joined + "\n"
                }
            }
        }

        // STEP 3: Re-insert tables
        for (i, tableText) in tableTexts.enumerated() {
            result = result.replacingOccurrences(of: "[[PPTTABLE_\(i)]]", with: "\n" + tableText + "\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract a PowerPoint table as pipe-separated text
    private func extractTableFromPowerPointXML(_ tableXML: String) -> String {
        let rowPattern = #"<a:tr\b[^>]*>(.*?)</a:tr>"#
        let cellPattern = #"<a:tc\b[^>]*>(.*?)</a:tc>"#
        let textPattern = #"<a:t(?:\s[^>]*)?>([^<]*)</a:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
            let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
            let textRegex = try? NSRegularExpression(pattern: textPattern, options: [])
        else {
            return ""
        }

        var tableRows: [[String]] = []
        let rowRange = NSRange(tableXML.startIndex..., in: tableXML)

        rowRegex.enumerateMatches(in: tableXML, options: [], range: rowRange) { rowMatch, _, _ in
            guard let rowMatch = rowMatch, let rowContent = Range(rowMatch.range(at: 1), in: tableXML) else { return }
            let rowStr = String(tableXML[rowContent])
            var cells: [String] = []

            let cellRange = NSRange(rowStr.startIndex..., in: rowStr)
            cellRegex.enumerateMatches(in: rowStr, options: [], range: cellRange) { cellMatch, _, _ in
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else {
                    return
                }
                let cellStr = String(rowStr[cellContent])
                // Entities decoded (5.8): "R&amp;D" was stored as written.
                cells.append(
                    Self.officeTableCellText(
                        cellStr, paragraphPattern: #"<a:p\b[^>]*(?<!/)>(.*?)</a:p>"#, textRegex: textRegex))
            }

            if !cells.allSatisfy({ $0.isEmpty }) {
                tableRows.append(cells)
            }
        }

        guard !tableRows.isEmpty else { return "" }
        var output = ""
        for (i, row) in tableRows.enumerated() {
            output += "| " + row.joined(separator: " | ") + " |\n"
            if i == 0 {
                output += "|" + row.map { _ in " --- " }.joined(separator: "|") + "|\n"
            }
        }
        return output
    }

}
