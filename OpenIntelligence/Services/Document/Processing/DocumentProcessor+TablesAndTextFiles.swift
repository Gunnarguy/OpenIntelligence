//
//  DocumentProcessor+TablesAndTextFiles.swift
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
    func detectTables(
        from observations: [VNRecognizedTextObservation]
    ) -> (tables: [DetectedTable], remaining: [VNRecognizedTextObservation]) {
        guard observations.count >= 4 else {
            return ([], observations)
        }

        // Group observations by Y position (rows)
        let lineThreshold: CGFloat = 0.02  // 2% of page height = same row
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
                                    Log.warning(
                                        "[DocumentProcessor] ⚠️ Uncertain table value: '\(analysis.text)' (conf: \(String(format: "%.0f%%", analysis.confidence * 100))). Alternatives: \(analysis.alternatives.map { "\($0.text)(\(String(format: "%.0f%%", $0.confidence * 100)))" }.joined(separator: ", "))",
                                        category: .ingestion)
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

                        tables.append(
                            DetectedTable(
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

                        Log.debug(
                            "[DocumentProcessor] Detected table: \(tableRows.count) rows × \(columnCount) columns",
                            category: .ingestion)
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
        let alignmentThreshold: CGFloat = 0.05  // 5% tolerance

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
                !result.text.unicodeScalars.prefix(1_000).contains("\u{0}")
            {
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
                converted as String?, String.localizedName(of: String.Encoding(rawValue: detected)))
        {
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
        // The encoding is found the way every other text file's is (5.8). A file that was not UTF-8 was read as
        // Latin-1, which never fails, so a Windows-1252 "€5" was stored with a control character for the euro sign
        // and a UTF-16 export was read as Latin-1 letters with zero bytes between them.
        if (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize == 0 {
            throw DocumentProcessingError.emptyDocument
        }
        let csvContent = try readTextFileWithFallbackEncodings(url: url, purpose: "CSV file")

        guard !csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        let delimiter = Self.csvDelimiter(csvContent)
        Log.debug(
            "[DocumentProcessor] CSV delimiter detected: '\(delimiter == "\t" ? "TAB" : String(delimiter))'",
            category: .ingestion)

        // Parse using RFC 4180 state machine
        let rows = Self.csvRows(csvContent, delimiter: delimiter)

        guard !rows.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        let totalRows = rows.count - 1
        if totalRows > 1000 {
            Log.info("[DocumentProcessor] Processing large CSV: \(totalRows) rows", category: .ingestion)
        }

        return formattedPipeTableText(from: rows)
    }

    /// The delimiter a CSV file uses: of comma, semicolon, tab and pipe, the one that splits the most of the first 20
    /// records into the same number of fields (more than one), counting only delimiters outside quoted fields; a tie
    /// goes to more fields, then to the order above (5.8). The character found most often in the first five lines
    /// won before, quotes or not, so a semicolon file with decimal commas ("Price;Qty\n1,50;2\n2,75;3") or a comma
    /// file whose notes held tabs was split on the wrong character.
    nonisolated static func csvDelimiter(_ content: String) -> Character {
        let sample = String(content.prefix(65_536))
        var best: (delimiter: Character, records: Int, fields: Int) = (",", 0, 0)
        for delimiter in [",", ";", "\t", "|"] as [Character] {
            var frequency: [Int: Int] = [:]
            for row in csvRows(sample, delimiter: delimiter, maxRecords: 20) { frequency[row.count, default: 0] += 1 }
            guard let mode = frequency.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }), mode.key > 1 else {
                continue
            }
            if (mode.value, mode.key) > (best.records, best.fields) { best = (delimiter, mode.value, mode.key) }
        }
        return best.delimiter
    }

    /// RFC 4180 CSV parser — handles quoted fields, embedded delimiters, embedded newlines, escaped quotes
    /// Returns array of rows, each row is an array of field values, at most `maxRecords` of them.
    ///
    /// A quote opens a quoted field only where the field starts (after spaces at most), as RFC 4180 has it (5.8). A
    /// quote anywhere opened one, so in `TV,55" screen,499` every delimiter and line end after the inch mark, up to
    /// the next quote in the file, was read as text and the rows between became one cell. The text is read by
    /// Unicode scalar: Swift reads "\r\n" as one Character, equal to neither "\r" nor "\n", so every row of a file
    /// with Windows line ends ran into the next.
    nonisolated static func csvRows(_ content: String, delimiter: Character, maxRecords: Int = .max) -> [[String]] {
        guard let separator = delimiter.unicodeScalars.first else { return [] }
        let scalars = content.unicodeScalars
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = String.UnicodeScalarView()
        var inQuotes = false

        func endField() {
            currentRow.append(String(currentField).trimmingCharacters(in: .whitespaces))
            currentField = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }
            currentRow = []
        }

        var i = scalars.startIndex
        while i < scalars.endIndex, rows.count < maxRecords {
            let scalar = scalars[i]
            let next = scalars.index(after: i)

            if inQuotes {
                if scalar == "\"" {
                    if next < scalars.endIndex && scalars[next] == "\"" {
                        // Escaped quote — add literal quote and skip both
                        currentField.append("\"")
                        i = scalars.index(after: next)
                    } else {
                        // End of quoted field; anything up to the delimiter is kept as written
                        inQuotes = false
                        i = next
                    }
                } else {
                    // Inside quotes — everything is literal (including delimiters and newlines)
                    currentField.append(scalar)
                    i = next
                }
                continue
            }

            if scalar == "\"" && currentField.allSatisfy({ $0 == " " || ($0 == "\t" && separator != "\t") }) {
                // Start of quoted field
                currentField = String.UnicodeScalarView()
                inQuotes = true
            } else if scalar == separator {
                endField()
            } else if scalar == "\r" {
                // \r\n or a bare \r ends the row
                endRow()
                if next < scalars.endIndex && scalars[next] == "\n" {
                    i = scalars.index(after: next)
                    continue
                }
            } else if scalar == "\n" {
                endRow()
            } else {
                currentField.append(scalar)
            }
            i = next
        }

        // Don't forget the last field/row
        if rows.count < maxRecords && (!currentField.isEmpty || !currentRow.isEmpty) {
            endRow()
        }

        return rows
    }

}
