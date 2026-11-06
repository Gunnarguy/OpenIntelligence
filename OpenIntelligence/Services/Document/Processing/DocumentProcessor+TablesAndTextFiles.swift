//
//  DocumentProcessor+TablesAndTextFiles.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved from DocumentProcessor.swift on 2026-11-05 (5.8 split); only access keywords changed.
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
    // MARK: - Table Detection

    /// Detected table structure from OCR observations
    struct DetectedTable: Sendable {
        let rows: [[String]]
        let boundingBox: CGRect
        let confidence: Float

        /// Convert table to readable text format
        func toText() -> String {
            guard !rows.isEmpty else { return "" }

            var output = "[Table]\n"

            // Header row
            if let header = rows.first {
                output += "| " + header.joined(separator: " | ") + " |\n"
                output += "|" + header.map { _ in "---" }.joined(separator: "|") + "|\n"
            }

            // Data rows
            for row in rows.dropFirst() {
                output += "| " + row.joined(separator: " | ") + " |\n"
            }

            output += "[/Table]\n"
            return output
        }
    }

    /// Detect tables in OCR observations using grid alignment analysis
    /// Returns detected tables and remaining non-table observations
    func detectTables(from observations: [VNRecognizedTextObservation]) -> (tables: [DetectedTable], remaining: [VNRecognizedTextObservation]) {
        guard observations.count >= 4 else {
            return ([], observations)
        }

        // Group observations by Y position (rows)
        let lineThreshold: CGFloat = 0.02 // 2% of page height = same row
        var rows: [[VNRecognizedTextObservation]] = []
        var currentRow: [VNRecognizedTextObservation] = []
        var lastY: CGFloat = -1

        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        for obs in sorted {
            let y = obs.boundingBox.midY
            if lastY < 0 || abs(y - lastY) < lineThreshold {
                currentRow.append(obs)
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
                }
                currentRow = [obs]
            }
            lastY = y
        }
        if !currentRow.isEmpty {
            rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
        }

        // Detect table regions: multiple rows with consistent column count
        var tables: [DetectedTable] = []
        var tableObservations: Set<UUID> = []
        var i = 0

        while i < rows.count {
            let columnCount = rows[i].count

            // Need at least 2 columns and 2 rows for a table
            if columnCount >= 2 {
                var tableRows: [[VNRecognizedTextObservation]] = [rows[i]]
                var j = i + 1

                // Find consecutive rows with similar column count (±1)
                while j < rows.count {
                    let nextColCount = rows[j].count
                    if abs(nextColCount - columnCount) <= 1, nextColCount >= 2 {
                        tableRows.append(rows[j])
                        j += 1
                    } else {
                        break
                    }
                }

                // If we found 2+ rows with consistent columns, it's likely a table
                if tableRows.count >= 2 {
                    // Check X-alignment consistency (column structure)
                    if hasConsistentColumnAlignment(tableRows) {
                        // CRITICAL: Use confidence-verified text for table cells
                        // Tables contain numeric data where OCR errors cause wrong answers
                        let textRows = tableRows.map { row in
                            row.compactMap { cell -> String? in
                                let analysis = ConfidenceVerifier.analyze(cell)
                                if analysis.isUncertain && analysis.containsNumericData {
                                    Log.warning("[DocumentProcessor] ⚠️ Uncertain table value: '\(analysis.text)' (conf: \(String(format: "%.0f%%", analysis.confidence * 100))). Alternatives: \(analysis.alternatives.map { "\($0.text)(\(String(format: "%.0f%%", $0.confidence * 100)))" }.joined(separator: ", "))", category: .ingestion)
                                }
                                return analysis.text.isEmpty ? nil : analysis.text
                            }
                        }

                        // Calculate bounding box
                        let allObs = tableRows.flatMap { $0 }
                        let minX = allObs.map { $0.boundingBox.minX }.min() ?? 0
                        let maxX = allObs.map { $0.boundingBox.maxX }.max() ?? 1
                        let minY = allObs.map { $0.boundingBox.minY }.min() ?? 0
                        let maxY = allObs.map { $0.boundingBox.maxY }.max() ?? 1

                        tables.append(DetectedTable(
                            rows: textRows,
                            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                            confidence: Float(tableRows.count) / Float(max(1, rows.count))
                        ))

                        // Mark these observations as table content
                        for row in tableRows {
                            for obs in row {
                                tableObservations.insert(obs.uuid)
                            }
                        }

                        Log.debug("[DocumentProcessor] Detected table: \(tableRows.count) rows × \(columnCount) columns", category: .ingestion)
                    }
                }

                i = j
            } else {
                i += 1
            }
        }

        // Return non-table observations
        let remaining = observations.filter { !tableObservations.contains($0.uuid) }

        return (tables, remaining)
    }

    /// Check if rows have consistent column X-alignment (suggesting table structure)
    private func hasConsistentColumnAlignment(_ rows: [[VNRecognizedTextObservation]]) -> Bool {
        guard rows.count >= 2 else { return false }

        // Get X positions of first row as reference
        let referenceXs = rows[0].map { $0.boundingBox.midX }
        let alignmentThreshold: CGFloat = 0.05 // 5% tolerance

        for row in rows.dropFirst() {
            let rowXs = row.map { $0.boundingBox.midX }

            // Check if this row's X positions roughly align with reference
            var alignedCount = 0
            for x in rowXs {
                for refX in referenceXs {
                    if abs(x - refX) < alignmentThreshold {
                        alignedCount += 1
                        break
                    }
                }
            }

            // Require at least 50% of columns to align
            if alignedCount < row.count / 2 {
                return false
            }
        }

        return true
    }

    func normalizationProfile(for documentType: DocumentType) -> OCRConfiguration.TextNormalizationProfile {
        switch documentType {
        case .text, .markdown, .rtf,
             .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code,
             .csv,
               .word, .excel, .powerpoint, .pages, .numbers, .keynote,
             .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            return .authoredText

        default:
            return .extractedDocument
        }
    }

    func readTextFileWithFallbackEncodings(url: URL, purpose: String) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let decoded = Self.decodeTextFile(data) else {
            throw DocumentProcessingError.unsupportedEncoding
        }
        if decoded.encodingName != "UTF-8" {
            Log.info(
                "[DocumentProcessor] The \(purpose) is not UTF-8; read as \(decoded.encodingName)",
                category: .ingestion)
        }
        return decoded.text
    }

    /// The text of a file whose encoding is not stated, and the name of the encoding it was read
    /// as. Nil for an empty file.
    ///
    /// Through 5.6 a file that was not UTF-8 was read as Latin-1. Latin-1 gives every byte a
    /// character, so that read never failed and the two encodings tried after it were never
    /// reached: a Shift-JIS, GB 18030, Windows-1251 or UTF-16 file was imported as rows of
    /// accented Latin letters and control characters, with no error. Now Foundation's own
    /// detection (`NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`)
    /// reads what is not UTF-8, lossless results only; measured on 2026-10-10 it returned the
    /// exact text for UTF-16 with a byte-order mark, Shift-JIS, EUC-JP, Windows-1251,
    /// Windows-1252 and GB 18030, and the wrong encoding for Mac Roman. UTF-16 with no
    /// byte-order mark can be valid UTF-8 full of control codes, so it is caught before the
    /// UTF-8 read by its zero bytes. A leading byte-order mark is not part of the text.
    nonisolated static func decodeTextFile(_ data: Data) -> (text: String, encodingName: String)? {
        guard !data.isEmpty else { return nil }
        let probe = [UInt8](data.prefix(4_096))

        func accepted(_ text: String?, _ name: String) -> (text: String, encodingName: String)? {
            guard var text, !text.isEmpty else { return nil }
            if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
            return text.isEmpty ? nil : (text, name)
        }

        let hasUTF16Mark =
            probe.count >= 2 && ((probe[0] == 0xFF && probe[1] == 0xFE) || (probe[0] == 0xFE && probe[1] == 0xFF))
        if hasUTF16Mark, let result = accepted(String(data: data, encoding: .utf16), "UTF-16") {
            return result
        }

        var zerosAtEven = 0
        var zerosAtOdd = 0
        var controlBytes = 0
        for (offset, byte) in probe.enumerated() where byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D {
            controlBytes += 1
            if byte == 0 {
                if offset.isMultiple(of: 2) { zerosAtEven += 1 } else { zerosAtOdd += 1 }
            }
        }
        let utf8Text = String(data: data, encoding: .utf8)
        if zerosAtEven + zerosAtOdd > 0, utf8Text == nil || controlBytes * 10 >= probe.count {
            // Zero bytes, and either the bytes are not UTF-8 or a tenth of them are control
            // codes: two-byte text with no mark, not UTF-8 with a stray zero in it. The zeros are
            // the high bytes of its spaces, digits and line ends, which come second in
            // little-endian. A run of zero padding reads as U+0000 and is turned away.
            let littleEndian = zerosAtOdd >= zerosAtEven
            let encoding: String.Encoding = littleEndian ? .utf16LittleEndian : .utf16BigEndian
            if let result = accepted(String(data: data, encoding: encoding), "UTF-16"),
                !result.text.unicodeScalars.prefix(1_000).contains("\u{0}") {
                return result
            }
        }
        // Bytes that are UTF-8 are read as UTF-8; nothing below is asked.
        if let result = accepted(utf8Text, "UTF-8") { return result }

        var converted: NSString?
        var usedLossyConversion: ObjCBool = false
        let detected = NSString.stringEncoding(
            for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted,
            usedLossyConversion: &usedLossyConversion)
        if detected != 0, !usedLossyConversion.boolValue,
            let result = accepted(
                converted as String?, String.localizedName(of: String.Encoding(rawValue: detected))) {
            return result
        }

        // What is left is bytes nothing recognised. Windows-1252 and then Latin-1, which gives
        // every byte a character, keep the file readable where it is plain text.
        return accepted(String(data: data, encoding: .windowsCP1252), "Windows-1252")
            ?? accepted(String(data: data, encoding: .isoLatin1), "Latin-1")
    }

    /// Reads a `.json`, `.jsonl` or `.ndjson` file as records. Returns nil when the file is not
    /// JSON records (comments in a `.jsonc`, a broken file), and the caller imports it as text.
    func extractJSONRecords(
        url: URL, numbering: JSONRecordExtractor.Numbering = .init()
    ) throws -> JSONRecordExtractor.Extraction? {
        let contents = try readTextFileWithFallbackEncodings(url: url, purpose: "JSON file")
        guard
            let extraction = JSONRecordExtractor.extract(
                from: contents, fileExtension: url.pathExtension.lowercased(), numbering: numbering)
        else {
            Log.info(
                "[DocumentProcessor] \(url.lastPathComponent) did not parse as JSON records; importing it as text",
                category: .ingestion)
            return nil
        }
        Log.info(
            "[DocumentProcessor] JSON records: \(extraction.records.count) from \(url.lastPathComponent)"
                + (extraction.unparsedLineCount > 0
                    ? ", \(extraction.unparsedLineCount) line(s) were not valid JSON and are kept as written" : ""),
            category: .ingestion)
        return extraction
    }

    /// One chunk per JSON record, or per run of short records when `packsRecords` is set. The
    /// passages are cut from `text`, so positions are character offsets into it, as the semantic
    /// chunker's are.
    ///
    /// A file read whole gives each record its own chunk. A file read in pieces is packed
    /// (`JSONRecordExtractor.packedRanges`): one measured on 2026-10-09 held 189,579 records with
    /// a median of 251 bytes. Each record in a packed chunk keeps its own header line.
    ///
    /// Each record's tokens are counted once, here, and the count is what packs it and what
    /// decides whether it needs cutting. A packed chunk is not counted again: its records' counts
    /// each include the tokenizer's own start and end marks and two more are allowed for every
    /// join, so the joined text cannot count more than the sum, and `enforceTokenLimitOnChunks`
    /// checks every chunk afterwards in any case. A 2 MB piece of that file is 4,610 records, so
    /// the loops let the main actor go every `tokenizerCallsBetweenYields` records.
    func makeJSONRecordChunks(
        _ passages: [(range: Range<String.Index>, text: String)],
        in text: String,
        documentCategory: DocumentSemanticCategory?,
        firstRecordNumber: Int = 1,
        packsRecords: Bool = false
    ) async -> [ProcessedChunk] {
        let partLimit = Self.safeTokenLimit - 10

        var tokenCounts: [Int] = []
        tokenCounts.reserveCapacity(passages.count)
        for (index, passage) in passages.enumerated() {
            if index > 0, index % Self.tokenizerCallsBetweenYields == 0 { await Task.yield() }
            tokenCounts.append(countTokens(passage.text))
        }

        let groups: [Range<Int>]
        if packsRecords {
            groups = JSONRecordExtractor.packedRanges(tokenCounts: tokenCounts, maxTokens: partLimit)
        } else {
            groups = passages.indices.map { $0..<($0 + 1) }
        }

        var chunks: [ProcessedChunk] = []
        chunks.reserveCapacity(groups.count)
        var cursor = text.startIndex
        var offset = 0
        for (groupNumber, group) in groups.enumerated() {
            guard let firstPassage = passages[group].first, let lastPassage = passages[group].last else { continue }
            if groupNumber > 0, groupNumber % Self.tokenizerCallsBetweenYields == 0 { await Task.yield() }
            offset += text.distance(from: cursor, to: firstPassage.range.lowerBound)
            let start = offset
            offset += text.distance(from: firstPassage.range.lowerBound, to: lastPassage.range.upperBound)
            cursor = lastPassage.range.upperBound

            let firstNumber = firstRecordNumber + group.lowerBound
            if group.count > 1 {
                let lastNumber = firstRecordNumber + group.upperBound - 1
                let title = "Records \(firstNumber) to \(lastNumber)"
                let joined = passages[group].map(\.text).joined(separator: "\n\n")
                let metadata = ChunkMetadata(
                    chunkIndex: chunks.count,
                    startPosition: start,
                    endPosition: offset,
                    pageNumber: nil,
                    sectionTitle: title,
                    hasNumericData: passages[group].contains { Self.recordBodyHoldsNumbers($0.text) },
                    wordCount: countWords(joined),
                    characterCount: joined.count,
                    sectionPath: [title],
                    documentCategory: documentCategory
                )
                chunks.append(ProcessedChunk(text: joined, parentText: nil, metadata: metadata))
                continue
            }

            let title = "Record \(firstNumber)"
            // A record over the embedding limit is cut here, at its own field lines, so the generic
            // splitter never sees it and every part keeps the record's header.
            let parts: [String]
            if tokenCounts[group.lowerBound] <= partLimit {
                parts = [firstPassage.text]
            } else {
                parts = JSONRecordExtractor.parts(
                    of: firstPassage.text, maxTokens: partLimit, countTokens: countTokens)
                if parts.count > 1, !packsRecords {
                    Log.info(
                        "[DocumentProcessor] JSON record \(firstNumber) is over the embedding limit; stored as \(parts.count) parts",
                        category: .ingestion)
                }
                let overLimit = parts.filter { countTokens($0) > Self.safeTokenLimit }.count
                if overLimit > 0 {
                    Log.warning(
                        "[DocumentProcessor] JSON record \(firstNumber): \(overLimit) part(s) are still over the embedding limit and will be cut by the general splitter",
                        category: .ingestion)
                }
            }
            for part in parts {
                let metadata = ChunkMetadata(
                    chunkIndex: chunks.count,
                    startPosition: start,
                    endPosition: offset,
                    pageNumber: nil,
                    sectionTitle: title,
                    hasNumericData: Self.recordBodyHoldsNumbers(part),
                    wordCount: countWords(part),
                    characterCount: part.count,
                    sectionPath: [title],
                    documentCategory: documentCategory
                )
                chunks.append(ProcessedChunk(text: part, parentText: nil, metadata: metadata))
            }
        }
        return chunks
    }

    /// Tokenizer calls a loop makes before it lets the main actor go. A call on a full passage
    /// is on the order of a millisecond, so this is a hold of a fraction of a second.
    static let tokenizerCallsBetweenYields = 100

    /// Whether a record, or one part of a record, holds a digit in its own data. Its first line
    /// is the header, which always holds digits ("Record 12 of 400") and says nothing about that.
    nonisolated static func recordBodyHoldsNumbers(_ record: String) -> Bool {
        let body = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first ?? ""
        return body.contains(where: \.isNumber)
    }

    /// Extract text from code files - preserve syntax and structure
    func extractTextFromCode(url: URL) throws -> String {
        try readTextFileWithFallbackEncodings(url: url, purpose: "code file")
    }

    /// Extract text from CSV - RFC 4180 compliant parser
    /// Handles: quoted fields, embedded delimiters, embedded newlines,
    /// escaped quotes (""), multiple delimiter types (comma, tab, semicolon, pipe)
    func extractTextFromCSV(url: URL) throws -> String {
        // Try multiple encodings for robustness
        let csvContent: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            csvContent = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            Log.info("[DocumentProcessor] CSV: Using Latin-1 encoding (UTF-8 failed)", category: .ingestion)
            csvContent = latin1
        } else if let win1252 = try? String(contentsOf: url, encoding: .windowsCP1252) {
            Log.info("[DocumentProcessor] CSV: Using Windows-1252 encoding", category: .ingestion)
            csvContent = win1252
        } else {
            throw DocumentProcessingError.unsupportedEncoding
        }

        guard !csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        // Detect delimiter from first line (tab > semicolon > pipe > comma)
        let delimiter = detectCSVDelimiter(csvContent)
        Log.debug("[DocumentProcessor] CSV delimiter detected: '\(delimiter == "\t" ? "TAB" : String(delimiter))'", category: .ingestion)

        // Parse using RFC 4180 state machine
        let rows = parseCSVRows(csvContent, delimiter: delimiter)

        guard !rows.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        let totalRows = rows.count - 1
        if totalRows > 1000 {
            Log.info("[DocumentProcessor] Processing large CSV: \(totalRows) rows", category: .ingestion)
        }

        return formattedPipeTableText(from: rows)
    }

    /// Detect CSV delimiter by analyzing the first few lines
    /// Priority: tab > semicolon > pipe > comma (avoids false positives from commas in text)
    private func detectCSVDelimiter(_ content: String) -> Character {
        // Take first 5 lines (not parsed, just split by raw newline for detection)
        let sampleLines = content.components(separatedBy: .newlines).prefix(5)
        let sample = sampleLines.joined(separator: "\n")

        let tabCount = sample.filter { $0 == "\t" }.count
        let semiCount = sample.filter { $0 == ";" }.count
        let pipeCount = sample.filter { $0 == "|" }.count
        let commaCount = sample.filter { $0 == "," }.count

        // Tab is unambiguous — if present, it's almost always the delimiter
        if tabCount >= sampleLines.count - 1 && tabCount > 0 {
            return "\t"
        }

        // Pick the most frequent delimiter that appears consistently across lines
        let candidates: [(Character, Int)] = [
            ("\t", tabCount),
            (";", semiCount),
            ("|", pipeCount),
            (",", commaCount)
        ]

        // Delimiter should appear at least once per line — pick the one with most consistent count
        if let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }

        return "," // Default
    }

    /// RFC 4180 CSV parser — handles quoted fields, embedded delimiters, embedded newlines, escaped quotes
    /// Returns array of rows, each row is an array of field values
    private func parseCSVRows(_ content: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            if inQuotes {
                if char == "\"" {
                    // Look ahead: is this an escaped quote ("") or end of quoted field?
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        // Escaped quote — add literal quote and skip both
                        currentField.append("\"")
                        i = content.index(after: next)
                        continue
                    } else {
                        // End of quoted field
                        inQuotes = false
                        i = content.index(after: i)
                        continue
                    }
                } else {
                    // Inside quotes — everything is literal (including delimiters and newlines)
                    currentField.append(char)
                    i = content.index(after: i)
                    continue
                }
            }

            // Not in quotes
            if char == "\"" {
                // Start of quoted field (should be at field start, but be permissive)
                inQuotes = true
                i = content.index(after: i)
                continue
            }

            if char == delimiter {
                // End of field
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                i = content.index(after: i)
                continue
            }

            if char == "\r" {
                // Handle \r\n and bare \r
                let next = content.index(after: i)
                if next < content.endIndex && content[next] == "\n" {
                    i = content.index(after: next)
                } else {
                    i = content.index(after: i)
                }
                // End of row
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
                continue
            }

            if char == "\n" {
                // End of row
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
                i = content.index(after: i)
                continue
            }

            // Regular character
            currentField.append(char)
            i = content.index(after: i)
        }

        // Don't forget the last field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

}
