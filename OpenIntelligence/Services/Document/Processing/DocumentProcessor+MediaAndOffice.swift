//
//  DocumentProcessor+MediaAndOffice.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved unchanged from DocumentProcessor.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os
import CryptoKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
import Metal
import Tokenizers
import Compression
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
                Log.info("[DocumentProcessor] Transcribed \(result.wordCount) words from \(url.lastPathComponent) via SpeechAnalyzer", category: .ingestion)
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
        Log.info("[DocumentProcessor] Suggestion: Convert to .docx, .xlsx, or .pptx for better support", category: .ingestion)
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
            // Word documents: main content is in word/document.xml
            if let documentXML = archive.extractString(path: "word/document.xml") {
                extractedText = extractTextFromWordXML(documentXML)
            }
            // Headers/footers (stop at first miss, don't loop to 10)
            for i in 1...20 {
                if let headerXML = archive.extractString(path: "word/header\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(headerXML)
                } else if i > 3 { break }  // At least check 1–3
                if let footerXML = archive.extractString(path: "word/footer\(i).xml") {
                    extractedText += "\n" + extractTextFromWordXML(footerXML)
                }
            }
            // Footnotes and endnotes — important for academic/legal documents
            if let footnotesXML = archive.extractString(path: "word/footnotes.xml") {
                let footnoteText = extractTextFromWordXML(footnotesXML)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !footnoteText.isEmpty {
                    extractedText += "\n\nFootnotes:\n" + footnoteText
                }
            }
            if let endnotesXML = archive.extractString(path: "word/endnotes.xml") {
                let endnoteText = extractTextFromWordXML(endnotesXML)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !endnoteText.isEmpty {
                    extractedText += "\n\nEndnotes:\n" + endnoteText
                }
            }

        case .excel:
            // Excel: shared strings + worksheet cells
            var sharedStrings: [String] = []
            if let sharedStringsXML = archive.extractString(path: "xl/sharedStrings.xml") {
                sharedStrings = extractSharedStringsFromExcel(sharedStringsXML)
            }
            // Extract each worksheet
            for i in 1...100 {
                if let sheetXML = archive.extractString(path: "xl/worksheets/sheet\(i).xml") {
                    extractedText += extractTextFromExcelSheet(sheetXML, sharedStrings: sharedStrings)
                    extractedText += "\n\n"
                } else {
                    break
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
    private func extractTextFromWordXML(_ xml: String) -> String {
        var result = ""

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
        let paragraphPattern = #"<w:p\b[^>]*>(.*?)</w:p>"#
        let runTextPattern = #"<w:t[^>]*>([^<]*)</w:t>"#
        let listPattern = #"<w:numPr>"#  // Presence indicates numbered/bullet list item
        let breakPattern = #"<w:br\s*/?\s*>"#

        if let paraRegex = try? NSRegularExpression(pattern: paragraphPattern, options: [.dotMatchesLineSeparators]),
           let runRegex = try? NSRegularExpression(pattern: runTextPattern, options: []),
           let listRegex = try? NSRegularExpression(pattern: listPattern, options: []),
           let breakRegex = try? NSRegularExpression(pattern: breakPattern, options: []) {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // Check for list item
                let isListItem = listRegex.firstMatch(in: paraContent, options: [],
                    range: NSRange(paraContent.startIndex..., in: paraContent)) != nil

                // Replace <w:br/> with newline
                let processed = breakRegex.stringByReplacingMatches(in: paraContent, options: [],
                    range: NSRange(paraContent.startIndex..., in: paraContent), withTemplate: "\n")

                // Extract all text runs and join with space (preserves word boundaries)
                let runRange = NSRange(processed.startIndex..., in: processed)
                var runs: [String] = []
                runRegex.enumerateMatches(in: processed, options: [], range: runRange) { runMatch, _, _ in
                    if let runMatch = runMatch, let textRange = Range(runMatch.range(at: 1), in: processed) {
                        runs.append(String(processed[textRange]))
                    }
                }

                let paragraphText = runs.joined() // Runs within a paragraph are contiguous
                if !paragraphText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if isListItem {
                        result += "• " + paragraphText + "\n"
                    } else {
                        result += paragraphText + "\n"
                    }
                }
            }
        }

        // STEP 3: Re-insert table text at placeholders
        for (i, tableText) in tableTexts.enumerated() {
            result = result.replacingOccurrences(of: "[[TABLE_\(i)]]", with: "\n" + tableText + "\n")
        }

        return result
    }

    /// Extract a single Word XML table as pipe-separated text
    /// Parses `<w:tbl>` → `<w:tr>` → `<w:tc>` → `<w:t>` hierarchy
    private func extractTableFromWordXML(_ tableXML: String) -> String {
        let rowPattern = #"<w:tr\b[^>]*>(.*?)</w:tr>"#
        let cellPattern = #"<w:tc\b[^>]*>(.*?)</w:tc>"#
        let textPattern = #"<w:t[^>]*>([^<]*)</w:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) else {
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
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else { return }
                let cellStr = String(rowStr[cellContent])

                // Extract all text runs within the cell
                var cellText: [String] = []
                let textRange = NSRange(cellStr.startIndex..., in: cellStr)
                textRegex.enumerateMatches(in: cellStr, options: [], range: textRange) { textMatch, _, _ in
                    if let textMatch = textMatch, let tRange = Range(textMatch.range(at: 1), in: cellStr) {
                        cellText.append(String(cellStr[tRange]))
                    }
                }
                cells.append(cellText.joined().trimmingCharacters(in: .whitespaces))
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
    /// Handles rich text strings with multiple `<r><t>` runs within a single `<si>` element
    private func extractSharedStringsFromExcel(_ xml: String) -> [String] {
        var strings: [String] = []

        // Match each <si>...</si> block, then extract ALL <t> tags within it
        let siPattern = #"<si>(.*?)</si>"#
        let tPattern = #"<t[^>]*>([^<]*)</t>"#

        guard let siRegex = try? NSRegularExpression(pattern: siPattern, options: [.dotMatchesLineSeparators]),
              let tRegex = try? NSRegularExpression(pattern: tPattern, options: []) else {
            return strings
        }

        let range = NSRange(xml.startIndex..., in: xml)
        siRegex.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let match = match, let contentRange = Range(match.range(at: 1), in: xml) else { return }
            let siContent = String(xml[contentRange])

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

    /// Extract text from Excel worksheet, using shared strings for cell values.
    /// Handles cells with formulas (`<f>` before `<v>`), inline strings (`<is><t>`),
    /// and boolean/error types.
    private func extractTextFromExcelSheet(_ xml: String, sharedStrings: [String]) -> String {
        var rows: [[String]] = []

        let rowPattern = #"<row[^>]*>(.*?)</row>"#
        // More permissive cell pattern: captures type and looks for <v> OR <is><t> anywhere in cell
        let cellPattern = #"<c\b([^>]*)>(.*?)</c>"#
        let typePattern = #"t="([^"]*)""#
        let valuePattern = #"<v>([^<]*)</v>"#
        let inlinePattern = #"<t[^>]*>([^<]*)</t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let typeRegex = try? NSRegularExpression(pattern: typePattern, options: []),
              let valueRegex = try? NSRegularExpression(pattern: valuePattern, options: []),
              let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: []) else {
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

                // Determine cell type
                var cellType: String? = nil
                if let typeMatch = typeRegex.firstMatch(in: attrs, options: [],
                    range: NSRange(attrs.startIndex..., in: attrs)),
                   let tRange = Range(typeMatch.range(at: 1), in: attrs) {
                    cellType = String(attrs[tRange])
                }

                // Try to get value from <v> tag
                if let valueMatch = valueRegex.firstMatch(in: body, options: [],
                    range: NSRange(body.startIndex..., in: body)),
                   let vRange = Range(valueMatch.range(at: 1), in: body) {
                    let value = String(body[vRange])

                    if cellType == "s", let index = Int(value), index < sharedStrings.count {
                        currentRow.append(sharedStrings[index])
                    } else if cellType == "b" {
                        currentRow.append(value == "1" ? "TRUE" : "FALSE")
                    } else {
                        currentRow.append(value)
                    }
                } else if cellType == "inlineStr" || cellType == "str" {
                    // Inline string: extract from <is><t> or just <t>
                    var fragments: [String] = []
                    let bRange = NSRange(body.startIndex..., in: body)
                    inlineRegex.enumerateMatches(in: body, options: [], range: bRange) { tMatch, _, _ in
                        if let tMatch = tMatch, let tRange = Range(tMatch.range(at: 1), in: body) {
                            fragments.append(String(body[tRange]))
                        }
                    }
                    currentRow.append(fragments.joined())
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
        let columnCount = rows.map(\ .count).max() ?? 0

        func normalizedRow(_ row: [String]) -> [String] {
            var cells = row.map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private func extractTextFromPowerPointSlide(_ xml: String) -> String {
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
                    let placeholder = "\n[[PPTTABLE_\(tableTexts.count)]]\n"
                    tableTexts.append(tableText)
                    processedXML.replaceSubrange(matchRange, with: placeholder)
                }
            }
        }

        // STEP 2: Extract paragraphs — <a:p> contains <a:r><a:t> text runs
        let paraPattern = #"<a:p\b[^>]*>(.*?)</a:p>"#
        let textPattern = #"<a:t>([^<]*)</a:t>"#

        if let paraRegex = try? NSRegularExpression(pattern: paraPattern, options: [.dotMatchesLineSeparators]),
           let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) {

            let range = NSRange(processedXML.startIndex..., in: processedXML)
            paraRegex.enumerateMatches(in: processedXML, options: [], range: range) { match, _, _ in
                guard let match = match, let contentRange = Range(match.range(at: 1), in: processedXML) else { return }
                let paraContent = String(processedXML[contentRange])

                // Extract all text runs in this paragraph
                var runs: [String] = []
                let tRange = NSRange(paraContent.startIndex..., in: paraContent)
                textRegex.enumerateMatches(in: paraContent, options: [], range: tRange) { tMatch, _, _ in
                    if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: paraContent) {
                        let content = String(paraContent[textRange])
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            runs.append(content)
                        }
                    }
                }

                if !runs.isEmpty {
                    result += runs.joined() + "\n"
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
        let textPattern = #"<a:t>([^<]*)</a:t>"#

        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]),
              let textRegex = try? NSRegularExpression(pattern: textPattern, options: []) else {
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
                guard let cellMatch = cellMatch, let cellContent = Range(cellMatch.range(at: 1), in: rowStr) else { return }
                let cellStr = String(rowStr[cellContent])

                var cellText: [String] = []
                let tRange = NSRange(cellStr.startIndex..., in: cellStr)
                textRegex.enumerateMatches(in: cellStr, options: [], range: tRange) { tMatch, _, _ in
                    if let tMatch = tMatch, let textRange = Range(tMatch.range(at: 1), in: cellStr) {
                        cellText.append(String(cellStr[textRange]))
                    }
                }
                cells.append(cellText.joined().trimmingCharacters(in: .whitespaces))
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
