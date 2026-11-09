//
//  DocumentProcessor+TextExtraction.swift
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
    // MARK: - Text Extraction

    /// Maps page numbers to their corresponding text range in the concatenated document string
    typealias PageTextMapping = [Int: Range<String.Index>]

    /// Holds page information from document extraction
    struct PageInfo {
        let totalPages: Int
        let ocrPagesUsed: Int
        let pageNumbers: [Int]           // Array of page numbers corresponding to text chunks
        let pageTextRanges: PageTextMapping  // Maps page numbers to text ranges (for citations)

        init(totalPages: Int, ocrPagesUsed: Int, pageNumbers: [Int], pageTextRanges: PageTextMapping = [:]) {
            self.totalPages = totalPages
            self.ocrPagesUsed = ocrPagesUsed
            self.pageNumbers = pageNumbers
            self.pageTextRanges = pageTextRanges
        }
    }

    /// Extract text with page information for semantic chunking
    func extractTextWithPageInfo(from url: URL, type: DocumentType) async throws -> (text: String, pageInfo: PageInfo) {
        let text: String
        var pageInfo = PageInfo(totalPages: 0, ocrPagesUsed: 0, pageNumbers: [], pageTextRanges: [:])

        switch type {
        case .pdf:
            let (extractedText, pdfPageInfo) = try await extractTextFromPDFWithPages(url: url)
            text = extractedText
            pageInfo = pdfPageInfo

        case .text, .markdown:
            text = try readTextFileWithFallbackEncodings(url: url, purpose: "text document")
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .rtf:
            text = try extractTextFromRTF(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Images - Use OCR
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            Log.debug("[DocumentProcessor] Image detected; applying OCR", category: .ingestion)
            text = try await extractTextFromImage(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 1, pageNumbers: [1])

        // Code files - Preserve as-is with syntax
        // NOTE: .xml is handled separately above for large files (streaming path)
        // Small XML files (<50 MB) still go through extractTextFromCode here.
        // A web page saved as a file is read as its text, as a fetched page is (5.8): through 5.7 it was kept as markup,
        // tags and undecoded entities included, so a search for its words met "&amp;" and "<td>".
        case .html:
            let html = try extractTextFromCode(url: url)
            let readable = WebPageFetchService.readableText(fromHTML: html)
            let pageText = [readable.title, readable.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            text = pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? html : pageText
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .css, .json, .xml, .yaml, .sql, .shell, .code:
            Log.debug("[DocumentProcessor] Code file detected; preserving syntax", category: .ingestion)
            text = try extractTextFromCode(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // CSV - Convert to structured text
        case .csv:
            Log.debug("[DocumentProcessor] CSV detected; converting to structured text", category: .ingestion)
            text = try extractTextFromCSV(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Office documents - Attempt extraction
        case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
            Log.debug("[DocumentProcessor] Office document detected; attempting extraction", category: .ingestion)
            text = try await extractTextFromOfficeDocument(url: url, type: type)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Audio/Video - Use Speech transcription
        case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            Log.debug("[DocumentProcessor] Audio/Video detected; transcribing with Speech.framework", category: .ingestion)
        text = try await extractTextFromAudioVideo(url: url)
        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .unknown:
            // Last resort: try treating as plain text
            Log.warning("[DocumentProcessor] Unknown format; attempting plain text extraction", category: .ingestion)
            if let attemptedText = try? readTextFileWithFallbackEncodings(url: url, purpose: "unknown document"), !attemptedText.isEmpty {
                text = attemptedText
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                Log.debug("[DocumentProcessor] Extracted as plain text", category: .ingestion)
            } else {
                Log.error("[DocumentProcessor] Unsupported format: \(url.pathExtension)", category: .ingestion)
                throw DocumentProcessingError.unsupportedFormat
            }
        }

        // Edge case: Empty or whitespace-only document
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Log.error("[DocumentProcessor] Document is empty or contains only whitespace", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        // Edge case: Very short document
        if trimmedText.count < 50 {
            Log.warning("[DocumentProcessor] Very short document (\(trimmedText.count) chars)", category: .ingestion)
        }

        // Edge case: Suspiciously long document (possible issue)
        if text.count > 10_000_000 { // 10MB of text
            Log.warning("[DocumentProcessor] Very large document (\(text.count) chars)", category: .ingestion)
        }

        return (text, pageInfo)
    }

    func detectStructuredElementsInExtractedText(
        _ text: String,
        pageInfo: PageInfo,
        documentType: DocumentType
    ) -> (elements: [StructuredElementWrapper], usedStructuredParsing: Bool) {
        guard shouldInferStructureFromExtractedText(for: documentType) else {
            return ([], false)
        }

        let pageTexts: [String]
        if text.contains(Self.pageBreakSentinel) {
            pageTexts = text
                .components(separatedBy: Self.pageBreakSentinel)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            pageTexts = [text]
        }

        var allElements: [StructuredElementWrapper] = []
        var foundStructuredContent = false

        for (index, pageText) in pageTexts.enumerated() {
            let pageNumber: Int
            if index < pageInfo.pageNumbers.count {
                pageNumber = pageInfo.pageNumbers[index]
            } else {
                pageNumber = index + 1
            }

            let pageElements = detectStructuredElementsInPageText(pageText, pageNumber: pageNumber)
            if pageElements.contains(where: { $0.elementType != "paragraph" }) {
                foundStructuredContent = true
            }
            allElements.append(contentsOf: pageElements)
        }

        return (allElements, foundStructuredContent)
    }

    private func shouldInferStructureFromExtractedText(for documentType: DocumentType) -> Bool {
        switch documentType {
        case .pdf,
             .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code,
             .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            return false
        default:
            return true
        }
    }

    private nonisolated func detectStructuredElementsInPageText(_ pageText: String, pageNumber: Int) -> [StructuredElementWrapper] {
        let lines = pageText.components(separatedBy: .newlines)
        var elements: [StructuredElementWrapper] = []
        var paragraphBuffer: [String] = []
        var lineIndex = 0

        func flushParagraphBuffer() {
            guard !paragraphBuffer.isEmpty else { return }
            let paragraphText = paragraphBuffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraphText.isEmpty {
                elements.append(StructuredElementWrapper(
                    text: paragraphText,
                    elementType: "paragraph",
                    pageNumber: pageNumber,
                    isAtomicChunk: false
                ))
            }
            paragraphBuffer.removeAll()
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushParagraphBuffer()
                lineIndex += 1
                continue
            }

            if trimmed == "[Table]" || trimmed == "[/Table]" {
                flushParagraphBuffer()
                lineIndex += 1
                continue
            }

            if let tableEnd = markdownTableBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<tableEnd])
                if let tableData = parseMarkdownTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = tableEnd
                    continue
                }
            }

            if let blockEnd = keyValueBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<blockEnd])
                if let tableData = parseKeyValueTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = blockEnd
                    continue
                }
            }

            if let blockEnd = parallelListTableBlockEnd(in: lines, startIndex: lineIndex) {
                var captionSource = paragraphBuffer
                let caption = consumeCaptionCandidate(from: &captionSource)
                paragraphBuffer = captionSource
                flushParagraphBuffer()

                let blockLines = Array(lines[lineIndex..<blockEnd])
                if let tableData = parseParallelListTable(lines: blockLines, pageNumber: pageNumber, caption: caption) {
                    elements.append(StructuredElementWrapper(
                        text: tableData.textRepresentation,
                        elementType: "table",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: tableData.detectedEntities.map { ($0.type.rawValue, $0.value) },
                        tableData: tableData,
                        extractionSource: "text_inferred",
                        qualityScore: tableQualityScore(tableData)
                    ))
                    lineIndex = blockEnd
                    continue
                }
            }

            paragraphBuffer.append(line)
            lineIndex += 1
        }

        flushParagraphBuffer()
        return elements
    }

    nonisolated func inferredStructuredElementsForPDFPageText(_ pageText: String, pageNumber: Int) -> [StructuredElementWrapper] {
        let normalizedText = pageText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return [] }
        guard shouldAttemptStructuredRecoveryFromPDFPageText(normalizedText) else { return [] }

        let inferredElements = detectStructuredElementsInPageText(normalizedText, pageNumber: pageNumber)
        guard inferredElements.contains(where: { $0.elementType == "table" || $0.elementType == "list" }) else {
            return []
        }

        return inferredElements
    }

    nonisolated func structuredElementMetrics(in elements: [StructuredElementWrapper]) -> (tables: Int, lists: Int, headers: Int) {
        (
            tables: elements.filter { $0.elementType == "table" }.count,
            lists: elements.filter { $0.elementType == "list" }.count,
            headers: elements.filter { $0.elementType == "title" }.count
        )
    }

    nonisolated func preferredElementsWithLayoutTables(
        existingElements: [StructuredElementWrapper],
        layoutTables: [TableRegion],
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], didPromote: Bool) {
        let promotedTables = promotedLayoutTableElements(from: layoutTables, pageNumber: pageNumber)
        guard !promotedTables.isEmpty else {
            return (existingElements, false)
        }

        let existingTableData = existingElements.compactMap(\.tableData)
        let bestExistingScore = existingTableData.map(tableQualityScore).max() ?? 0
        let bestPromotedScore = promotedTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0
        let existingTablesLookDegraded = existingTableData.contains { tableData in
            let rowCount = max(1, dataRows(for: tableData).count)
            let degradedRowRatio = Double(lowQualityRowIndices(for: tableData).count) / Double(rowCount)
            return tableQualityScore(tableData) < 0.72 || degradedRowRatio >= 0.25
        }

        guard existingTableData.isEmpty
                || bestPromotedScore > bestExistingScore + 0.05
                || (existingTablesLookDegraded && bestPromotedScore >= bestExistingScore - 0.02)
                || bestExistingScore < 0.60
        else {
            return (existingElements, false)
        }

        let preservedElements = existingElements.filter { $0.elementType != "table" }
        return (preservedElements + promotedTables, true)
    }

    private nonisolated func promotedLayoutTableElements(
        from layoutTables: [TableRegion],
        pageNumber: Int
    ) -> [StructuredElementWrapper] {
        layoutTables.compactMap { layoutTable in
            let normalizedRows = layoutTable.rows.map { row in
                row.map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
            }

            guard normalizedRows.count >= 2 else { return nil }
            guard tableQualityScore(rows: normalizedRows) >= 0.45 else { return nil }

            let headerRow = inferredHeaderRow(from: normalizedRows)
            let tableData = TableData(
                pageNumber: pageNumber,
                rows: normalizedRows,
                headerRow: headerRow,
                caption: nil,
                detectedEntities: []
            )

            return StructuredElementWrapper(
                text: tableData.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: tableData,
                listItems: nil,
                extractionSource: "layout_table",
                qualityScore: tableQualityScore(tableData)
            )
        }
    }

    private nonisolated func inferredHeaderRow(from rows: [[String]]) -> [String]? {
        guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }

        let visibleCells = firstRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard visibleCells.count >= 2 else { return nil }

        let shortHeaderRatio = Double(visibleCells.filter { $0.count <= 32 }.count) / Double(visibleCells.count)
        let digitRatio = Double(visibleCells.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }.count) / Double(visibleCells.count)
        let punctuationHeavyRatio = Double(visibleCells.filter {
            let punctuationCount = $0.unicodeScalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count
            return punctuationCount > max(2, $0.count / 3)
        }.count) / Double(visibleCells.count)

        if shortHeaderRatio >= 0.6 && digitRatio <= 0.4 && punctuationHeavyRatio <= 0.4 {
            return firstRow
        }

        return nil
    }

    nonisolated func tableQualityScore(_ tableData: TableData) -> Double {
        tableQualityScore(rows: tableData.rows)
    }

    private nonisolated func tableQualityScore(rows: [[String]]) -> Double {
        let normalizedRows = rows.map { row in
            row.map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let nonEmptyCells = normalizedRows.flatMap { $0 }.filter { !$0.isEmpty }
        guard !nonEmptyCells.isEmpty else { return 0 }

        let rowCount = normalizedRows.count
        let maxColumns = normalizedRows.map(\.count).max() ?? 0
        let visibleCellCount = Double(nonEmptyCells.count)
        let totalCellSlots = Double(max(1, rowCount * max(1, maxColumns)))
        let fillRatio = visibleCellCount / totalCellSlots
        let readableRatio = nonEmptyCells.map(tableCellReadabilityScore).reduce(0, +) / visibleCellCount

        let headerBonus: Double = inferredHeaderRow(from: normalizedRows) == nil ? 0 : 0.10
        let shapeBonus: Double = maxColumns >= 2 ? 0.15 : 0
        let rowBonus = min(0.15, Double(rowCount) / 8.0 * 0.15)

        let score = (readableRatio * 0.45) + (fillRatio * 0.15) + shapeBonus + rowBonus + headerBonus
        return min(1.0, max(0.0, score))
    }

    nonisolated func tableCellReadabilityScore(_ text: String) -> Double {
        let trimmed = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let scalarCount = trimmed.unicodeScalars.count
        guard scalarCount > 0 else { return 0 }

        let printableCount = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) ||
            CharacterSet.whitespacesAndNewlines.contains($0) ||
            CharacterSet.punctuationCharacters.contains($0) ||
            CharacterSet.symbols.contains($0)
        }.count
        let printableRatio = Double(printableCount) / Double(scalarCount)

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let alphaNumericRatio = Double(letters + digits) / Double(scalarCount)

        var score = printableRatio * 0.45 + alphaNumericRatio * 0.25

        if letters >= 8 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            let confidence = recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
            score += min(0.20, confidence * 0.20)
            if confidence < 0.15 {
                score -= 0.20
            }
        } else if digits > 0 {
            score += 0.10
        }

        return min(1.0, max(0.0, score))
    }

    private nonisolated func tableRowQualityScore(headers: [String], row: [String]) -> Double {
        let normalizedCells = row.map {
            OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let visibleCells = normalizedCells.filter { !$0.isEmpty }
        guard !visibleCells.isEmpty else { return 0 }

        let readability = visibleCells.map(tableCellReadabilityScore).reduce(0, +) / Double(visibleCells.count)
        let fillRatio = Double(visibleCells.count) / Double(max(1, max(headers.count, row.count)))
        let longValueBonus = visibleCells.contains { $0.count >= 18 } ? 0.08 : 0
        let repeatedNoisePenalty = visibleCells.contains {
            $0.range(of: #"^[^A-Za-z0-9]{3,}$"#, options: .regularExpression) != nil
        } ? 0.20 : 0

        return min(1.0, max(0.0, readability * 0.70 + fillRatio * 0.22 + longValueBonus - repeatedNoisePenalty))
    }

    nonisolated func lowQualityRowIndices(for tableData: TableData) -> [Int] {
        let headers = inferredHeaders(for: tableData)
        return dataRows(for: tableData).enumerated().compactMap { rowIndex, row in
            let score = tableRowQualityScore(headers: headers, row: row)
            return score < 0.38 ? rowIndex : nil
        }
    }

    nonisolated func shouldAttemptRegionCropRescue(
        analysis: PageComplexityAnalysis?,
        structuredContent: StructuredPageContent,
        hasRecoveredStructure: Bool,
        layoutTables: [TableRegion],
        pageText: String
    ) -> Bool {
        let tableSignal = (analysis?.tablePresence ?? 0) > 0.14 || !layoutTables.isEmpty
        let listSignal = (analysis?.listPatternStrength ?? 0) > 0.18
        let visualSignal = (analysis?.figurePresence ?? 0) > 0.12
            || (analysis?.chartPresence ?? 0) > 0.10
            || (analysis?.imagePresence ?? 0) > 0.22
        let degradedText = (analysis?.textQuality ?? 1.0) < 0.58 || (analysis?.fineTextRisk ?? 0) > 0.48
        let sparseText = pageText.trimmingCharacters(in: .whitespacesAndNewlines).count < 180
        let weakStructuredCapture = structuredContent.qualityScore < 0.68
        let missingExpectedStructure = !hasRecoveredStructure && (tableSignal || listSignal || visualSignal)

        return missingExpectedStructure
            || (weakStructuredCapture && (tableSignal || listSignal || visualSignal))
            || (degradedText && sparseText && (tableSignal || visualSignal))
    }

    nonisolated func regionRescuePayload(
        from rescue: RegionRescueResult,
        pageNumber: Int
    ) -> RegionCropRescuePayload? {
        var elements: [StructuredElementWrapper] = []
        var tableCount = 0
        var listCount = 0
        var figureCount = 0

        for table in rescue.content.tables {
            let normalizedRows = table.rows.map { row in
                row.map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
            }

            guard normalizedRows.count >= 2 else { continue }
            guard tableQualityScore(rows: normalizedRows) >= 0.42 else { continue }

            let tableData = TableData(
                pageNumber: pageNumber,
                rows: normalizedRows,
                headerRow: table.hasHeader ? inferredHeaderRow(from: normalizedRows) : nil,
                caption: table.caption,
                detectedEntities: []
            )

            elements.append(StructuredElementWrapper(
                text: tableData.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: tableData,
                listItems: nil,
                extractionSource: "crop_rescue",
                qualityScore: tableQualityScore(tableData)
            ))
            tableCount += 1
        }

        for list in rescue.content.lists {
            let normalizedItems = list.items
                .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard normalizedItems.count >= 2 else { continue }

            elements.append(StructuredElementWrapper(
                text: normalizedItems.map { "• \($0)" }.joined(separator: "\n"),
                elementType: "list",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: nil,
                listItems: normalizedItems
            ))
            listCount += 1
        }

        for figure in rescue.content.figures {
            var figureParts: [String] = []
            if let caption = figure.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                figureParts.append(caption)
            }
            if let classification = figure.classification?.trimmingCharacters(in: .whitespacesAndNewlines), !classification.isEmpty {
                figureParts.append("Figure: \(classification)")
            }
            if let description = figure.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                figureParts.append(description)
            }

            let figureText = figureParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !figureText.isEmpty else { continue }

            elements.append(StructuredElementWrapper(
                text: figureText,
                elementType: "figure",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: nil,
                listItems: nil
            ))
            figureCount += 1
        }

        let paragraphText = regionRescueParagraphText(from: rescue)
        if !paragraphText.isEmpty {
            elements.append(StructuredElementWrapper(
                text: paragraphText,
                elementType: "paragraph",
                pageNumber: pageNumber,
                isAtomicChunk: false,
                detectedEntities: [],
                tableData: nil,
                listItems: nil
            ))
        }

        let pageText = rescue.readingOrderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !elements.isEmpty || !pageText.isEmpty else { return nil }

        return RegionCropRescuePayload(
            elements: elements,
            pageText: pageText,
            tableCount: tableCount,
            listCount: listCount,
            figureCount: figureCount
        )
    }

    private nonisolated func regionRescueParagraphText(from rescue: RegionRescueResult) -> String {
        rescue.content.textBlocks
            .filter { !$0.isFooter }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.03 {
                    return lhs.boundingBox.maxY > rhs.boundingBox.maxY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .map { OCRConfiguration.normalizeExtractedText($0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private nonisolated func regionTextQualityScore(_ text: String) -> Double {
        let trimmed = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let baseScore = tableCellReadabilityScore(trimmed)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let lengthBonus = trimmed.count > 140 ? 0.10 : (trimmed.count > 70 ? 0.05 : 0)
        let densityBonus = min(0.15, Double(wordCount) / 80.0 * 0.15)
        let delimiterPenalty = trimmed.filter { $0 == "|" }.count > 8 ? 0.05 : 0

        return min(1.0, max(0.0, baseScore + lengthBonus + densityBonus - delimiterPenalty))
    }

    nonisolated func preferredElementsWithRegionCropRescue(
        existingElements: [StructuredElementWrapper],
        rescuePayload: RegionCropRescuePayload,
        existingPageText: String,
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], pageText: String?, didPromote: Bool) {
        var mergedElements = existingElements
        var didPromote = false

        let rescueTables = rescuePayload.elements.filter { $0.elementType == "table" }
        let rescueLists = rescuePayload.elements.filter { $0.elementType == "list" }
        let rescueFigures = rescuePayload.elements.filter { $0.elementType == "figure" }
        let rescueParagraphText = rescuePayload.elements.first { $0.elementType == "paragraph" }?.text ?? ""

        let existingTables = mergedElements.filter { $0.elementType == "table" }
        let existingLists = mergedElements.filter { $0.elementType == "list" }
        let existingFigures = mergedElements.filter { $0.elementType == "figure" }

        if !rescueTables.isEmpty {
            let rescueBestScore = rescueTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0
            let existingBestScore = existingTables.compactMap(\.tableData).map(tableQualityScore).max() ?? 0

            if existingTables.isEmpty || rescueBestScore > existingBestScore + 0.08 || existingBestScore < 0.42 {
                mergedElements.removeAll { $0.elementType == "table" }
                mergedElements.append(contentsOf: rescueTables)
                didPromote = true
            }
        }

        if !rescueLists.isEmpty && existingLists.isEmpty {
            mergedElements.append(contentsOf: rescueLists)
            didPromote = true
        }

        if !rescueFigures.isEmpty && existingFigures.isEmpty {
            mergedElements.append(contentsOf: rescueFigures)
            didPromote = true
        }

        var pageTextOverride: String? = nil
        if !rescueParagraphText.isEmpty {
            let existingParagraphText = mergedElements
                .filter { $0.elementType == "paragraph" }
                .map(\.text)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let baselineText = existingParagraphText.isEmpty ? existingPageText : existingParagraphText
            let rescueScore = regionTextQualityScore(rescueParagraphText)
            let baselineScore = regionTextQualityScore(baselineText)

            if baselineText.isEmpty || rescueScore > baselineScore + 0.12 {
                mergedElements.removeAll { $0.elementType == "paragraph" }
                mergedElements.append(StructuredElementWrapper(
                    text: rescueParagraphText,
                    elementType: "paragraph",
                    pageNumber: pageNumber,
                    isAtomicChunk: false,
                    detectedEntities: [],
                    tableData: nil,
                    listItems: nil
                ))
                pageTextOverride = rescuePayload.pageText
                didPromote = true
            }
        } else if didPromote && existingPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pageTextOverride = rescuePayload.pageText
        }

        return (mergedElements, pageTextOverride, didPromote)
    }

    private nonisolated func markdownTableBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count, isPipeTableLine(lines[startIndex]) else { return nil }

        var lineIndex = startIndex
        var visibleLineCount = 0
        var dataLineCount = 0

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { break }
            guard isPipeTableLine(trimmed) || isPipeTableSeparatorLine(trimmed) else { break }
            visibleLineCount += 1
            if !isPipeTableSeparatorLine(trimmed) {
                dataLineCount += 1
            }
            lineIndex += 1
        }

        guard visibleLineCount >= 2, dataLineCount >= 2 else { return nil }
        return lineIndex
    }

    private nonisolated func isPipeTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pipeCount = trimmed.filter { $0 == "|" }.count
        return pipeCount >= 2
    }

    private nonisolated func isPipeTableSeparatorLine(_ line: String) -> Bool {
        let cells = splitPipeTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.allSatisfy { character in
                character == "-" || character == ":"
            }
        }
    }

    private nonisolated func splitPipeTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed.splitOnUnescapedPipes()
            .map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private nonisolated func parseMarkdownTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        let normalizedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedLines.count >= 2 else { return nil }

        var rows: [[String]] = []
        var sawSeparator = false

        for line in normalizedLines {
            if isPipeTableSeparatorLine(line) {
                sawSeparator = true
                continue
            }

            let cells = splitPipeTableCells(line)
            guard cells.count >= 2 else { continue }
            rows.append(cells)
        }

        guard rows.count >= 2 else { return nil }

        let headerRow = sawSeparator ? rows.first : nil
        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: headerRow,
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func keyValueBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count, isKeyValueTableLine(lines[startIndex]) else { return nil }

        var lineIndex = startIndex
        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isKeyValueTableLine(trimmed) else { break }
            lineIndex += 1
        }

        guard lineIndex - startIndex >= 2 else { return nil }
        return lineIndex
    }

    private nonisolated func isKeyValueTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("|") else { return false }

        if trimmed.contains("\t") {
            let cells = trimmed.components(separatedBy: "\t").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return cells.count >= 2
        }

        return trimmed.range(
            of: #"^.{1,90}?(?:\s+-\s+|\s+[–—]\s+|:\s+).{1,}$"#,
            options: .regularExpression
        ) != nil
    }

    private nonisolated func parseKeyValueTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        var rows: [[String]] = []

        for line in lines {
            guard let (key, value) = parseKeyValueLine(line) else { continue }
            rows.append([key, value])
        }

        guard rows.count >= 2 else { return nil }
        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: nil,
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func parseKeyValueLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("\t") {
            let cells = trimmed
                .components(separatedBy: "\t")
                .map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { return nil }
            return (cells[0], cells.dropFirst().joined(separator: " | "))
        }

        let separators = [" - ", " – ", " — ", ": "]
        for separator in separators {
            let parts = trimmed.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }

            let key = OCRConfiguration.normalizeExtractedText(parts[0], profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = OCRConfiguration.normalizeExtractedText(parts.dropFirst().joined(separator: separator), profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            return (key, value)
        }

        return nil
    }

    private nonisolated func parallelListTableBlockEnd(in lines: [String], startIndex: Int) -> Int? {
        guard startIndex < lines.count else { return nil }

        let firstHeader = lines[startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isParallelListHeaderLine(firstHeader) else { return nil }

        var lineIndex = startIndex + 1
        var firstColumnLines: [String] = []

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard !isDocumentSectionHeadingLine(trimmed) else { return nil }

            if isParallelListHeaderLine(trimmed), firstColumnLines.count >= 2 {
                break
            }

            firstColumnLines.append(trimmed)
            lineIndex += 1
        }

        guard lineIndex < lines.count else { return nil }
        let secondHeader = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isParallelListHeaderLine(secondHeader), normalizeParallelListHeader(firstHeader) != normalizeParallelListHeader(secondHeader) else {
            return nil
        }

        lineIndex += 1
        var secondColumnLines: [String] = []

        while lineIndex < lines.count {
            let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || isDocumentSectionHeadingLine(trimmed) {
                break
            }

            if isParallelListHeaderLine(trimmed), secondColumnLines.count >= 2 {
                break
            }

            secondColumnLines.append(trimmed)
            lineIndex += 1
        }

        let leftItems = collapseParallelListItems(firstColumnLines, preferStateLabels: true)
        let rightItems = collapseParallelListItems(secondColumnLines, preferStateLabels: false)

        guard leftItems.count >= 3, rightItems.count >= 3 else { return nil }
        guard abs(leftItems.count - rightItems.count) <= 1 else { return nil }

        return lineIndex
    }

    private nonisolated func parseParallelListTable(lines: [String], pageNumber: Int, caption: String?) -> TableData? {
        let normalizedLines = lines
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedLines.count >= 8 else { return nil }
        guard let splitIndex = parallelListSplitIndex(in: normalizedLines) else { return nil }

        let firstHeader = normalizedLines[0]
        let secondHeader = normalizedLines[splitIndex]
        let leftItems = collapseParallelListItems(Array(normalizedLines[1..<splitIndex]), preferStateLabels: true)
        let rightItems = collapseParallelListItems(Array(normalizedLines[(splitIndex + 1)...]), preferStateLabels: false)

        let pairCount = min(leftItems.count, rightItems.count)
        guard pairCount >= 3 else { return nil }

        let rows = (0..<pairCount).map { index in
            [leftItems[index], rightItems[index]]
        }

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: [firstHeader, secondHeader],
            caption: caption,
            detectedEntities: []
        )
    }

    private nonisolated func parallelListSplitIndex(in lines: [String]) -> Int? {
        guard lines.count >= 5 else { return nil }

        for index in 2..<(lines.count - 2) {
            let candidate = lines[index]
            guard isParallelListHeaderLine(candidate) else { continue }

            let leftItems = collapseParallelListItems(Array(lines[1..<index]), preferStateLabels: true)
            let rightItems = collapseParallelListItems(Array(lines[(index + 1)...]), preferStateLabels: false)

            guard leftItems.count >= 3, rightItems.count >= 3 else { continue }
            guard abs(leftItems.count - rightItems.count) <= 1 else { continue }

            return index
        }

        return nil
    }

    private nonisolated func collapseParallelListItems(_ lines: [String], preferStateLabels: Bool) -> [String] {
        var items: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let startsNew = current.isEmpty || parallelListLineStartsNewItem(
                trimmed,
                currentItem: current,
                preferStateLabels: preferStateLabels
            )

            if startsNew {
                if !current.isEmpty {
                    items.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                current = trimmed
            } else {
                current += " " + trimmed
            }
        }

        if !current.isEmpty {
            items.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return items
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated func parallelListLineStartsNewItem(
        _ line: String,
        currentItem: String,
        preferStateLabels: Bool
    ) -> Bool {
        if preferStateLabels,
           line.range(of: #"^(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") {
            return true
        }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return false
        }

        if let first = line.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first) {
            return false
        }

        if line.count <= 10 && currentItem.count <= 40 {
            return false
        }

        if preferStateLabels {
            return line.count <= 40
        }

        return line.count >= 6
    }

    private nonisolated func isParallelListHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= 4, trimmed.count <= 40 else { return false }
        guard !trimmed.contains("|") else { return false }
        guard !trimmed.hasSuffix(".") else { return false }
        guard trimmed.range(of: #"^\d+(?:\.\d+)*"#, options: .regularExpression) == nil else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard words.count >= 1, words.count <= 5 else { return false }

        let hasLetters = trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        guard hasLetters else { return false }

        let uppercaseRatio = Double(trimmed.filter(\.isUppercase).count) / Double(max(1, trimmed.filter(\.isLetter).count))
        return uppercaseRatio >= 0.2 || trimmed == trimmed.uppercased()
    }

    private nonisolated func normalizeParallelListHeader(_ line: String) -> String {
        OCRConfiguration.normalizeExtractedText(line)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func preferredElementsWithRecoveredParallelKeyValueTable(
        existingElements: [StructuredElementWrapper],
        pageText: String,
        pageNumber: Int
    ) -> (elements: [StructuredElementWrapper], didPromote: Bool) {
        guard shouldAttemptStructuredRecoveryFromPDFPageText(pageText) else {
            return (existingElements, false)
        }

        guard let recoveredElement = recoveredParallelKeyValueTableElement(from: pageText, pageNumber: pageNumber) else {
            return (existingElements, false)
        }

        let candidateTables = existingElements.filter(looksLikeParallelKeyValueTableCandidate)
        let bestExistingScore = candidateTables.compactMap { element in
            element.qualityScore ?? element.tableData.map(tableQualityScore)
        }.max() ?? 0
        let recoveredScore = recoveredElement.qualityScore ?? 0
        let existingTablesLookDegraded = candidateTables.compactMap(\.tableData).contains { tableData in
            let rowCount = max(1, dataRows(for: tableData).count)
            let degradedRowRatio = Double(lowQualityRowIndices(for: tableData).count) / Double(rowCount)
            return tableQualityScore(tableData) < 0.74
                || degradedRowRatio >= 0.20
                || looksLikeMispairedIndicatorStateTable(tableData)
        }

        guard candidateTables.isEmpty
                || recoveredScore > bestExistingScore + 0.05
                || (existingTablesLookDegraded && recoveredScore >= bestExistingScore - 0.02)
                || bestExistingScore < 0.76
        else {
            return (existingElements, false)
        }

        let preserved = existingElements.filter { !looksLikeParallelKeyValueTableCandidate($0) }
        return (preserved + [recoveredElement], true)
    }

    private nonisolated func recoveredParallelKeyValueTableElement(from pageText: String, pageNumber: Int) -> StructuredElementWrapper? {
        if let indicatorTable = recoveredIndicatorStateTable(from: pageText, pageNumber: pageNumber) {
            let quality = max(0.94, tableQualityScore(indicatorTable))
            return StructuredElementWrapper(
                text: indicatorTable.textRepresentation,
                elementType: "table",
                pageNumber: pageNumber,
                isAtomicChunk: true,
                detectedEntities: [],
                tableData: indicatorTable,
                listItems: nil,
                extractionSource: "indicator_state_recovery",
                qualityScore: quality
            )
        }

        guard let tableData = recoveredParallelKeyValueTable(from: pageText, pageNumber: pageNumber) else {
            return nil
        }

        let quality = max(0.88, tableQualityScore(tableData))
        return StructuredElementWrapper(
            text: tableData.textRepresentation,
            elementType: "table",
            pageNumber: pageNumber,
            isAtomicChunk: true,
            detectedEntities: [],
            tableData: tableData,
            listItems: nil,
            extractionSource: "parallel_key_value_recovery",
            qualityScore: quality
        )
    }

    private nonisolated func recoveredIndicatorStateTable(from pageText: String, pageNumber: Int) -> TableData? {
        let normalizedLines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let labelHeaderIndex = normalizedLines.firstIndex(where: isIndicatorStateLabelHeaderLine(_:)) else {
            return nil
        }
        guard let statusHeaderIndex = normalizedLines[(labelHeaderIndex + 1)...].firstIndex(where: isIndicatorStateValueHeaderLine(_:)) else {
            return nil
        }

        let sectionEndIndex = normalizedLines[(statusHeaderIndex + 1)...].firstIndex(where: isDocumentSectionHeadingLine(_:))
            ?? normalizedLines.endIndex

        let stateItems = extractIndicatorStateLabels(from: Array(normalizedLines[(labelHeaderIndex + 1)..<statusHeaderIndex]))
        var statusRecovery = extractIndicatorStatusItems(from: Array(normalizedLines[(statusHeaderIndex + 1)..<sectionEndIndex]))

        if let trailingStateLabel = statusRecovery.trailingStateLabel,
           let trailingStatus = statusRecovery.trailingStatus
        {
            statusRecovery.statusItems.append(trailingStatus)
            if !stateItems.contains(where: { $0.caseInsensitiveCompare(trailingStateLabel) == .orderedSame }) {
                var recoveredStates = stateItems
                recoveredStates.append(trailingStateLabel)
                return buildRecoveredIndicatorStateTable(
                    stateItems: recoveredStates,
                    statusItems: statusRecovery.statusItems,
                    pageNumber: pageNumber
                )
            }
        }

        return buildRecoveredIndicatorStateTable(
            stateItems: stateItems,
            statusItems: statusRecovery.statusItems,
            pageNumber: pageNumber
        )
    }

    private nonisolated func buildRecoveredIndicatorStateTable(
        stateItems: [String],
        statusItems: [String],
        pageNumber: Int
    ) -> TableData? {
        guard stateItems.count >= 5, statusItems.count >= 5 else { return nil }
        guard abs(stateItems.count - statusItems.count) <= 1 else { return nil }

        let pairCount = min(stateItems.count, statusItems.count)
        let rows = (0..<pairCount).map { index in
            [stateItems[index], statusItems[index]]
        }

        guard tableQualityScore(rows: rows) >= 0.72 else { return nil }

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: ["Color of Light", "PLAUD Status"],
            caption: "Indicator Light",
            detectedEntities: []
        )
    }

    private nonisolated func recoveredParallelKeyValueTable(from pageText: String, pageNumber: Int) -> TableData? {
        let normalizedLines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let splitIndex = parallelListSplitIndex(in: normalizedLines) else {
            return nil
        }

        let leftItems = collapseParallelListItems(Array(normalizedLines[..<splitIndex]), preferStateLabels: true)
        let rightItems = collapseParallelListItems(Array(normalizedLines[(splitIndex + 1)...]), preferStateLabels: false)
        let pairCount = min(leftItems.count, rightItems.count)

        guard pairCount >= 3 else { return nil }

        let rows = (0..<pairCount).map { index in
            [leftItems[index], rightItems[index]]
        }

        guard tableQualityScore(rows: rows) >= 0.72 else { return nil }

        let headerCells = splitParallelListHeader(normalizedLines[splitIndex])
        let normalizedHeaderRow = headerCells.count == 2 ? headerCells : nil

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: normalizedHeaderRow,
            caption: normalizedHeaderRow?.joined(separator: " / "),
            detectedEntities: []
        )
    }

    private nonisolated func extractIndicatorStateLabels(from lines: [String]) -> [String] {
        var labels: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !isIndicatorStateLabelHeaderLine(trimmed), !isIndicatorStateValueHeaderLine(trimmed) else { continue }
            guard !isDocumentSectionHeadingLine(trimmed) else { continue }

            if startsNewIndicatorStateLabel(trimmed) {
                if let normalized = normalizeIndicatorStateLabel(current) {
                    labels.append(normalized)
                }
                current = trimmed
            } else if shouldAppendIndicatorStateContinuation(trimmed, currentItem: current) {
                current += " " + trimmed
            }
        }

        if let normalized = normalizeIndicatorStateLabel(current) {
            labels.append(normalized)
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for label in labels {
            let key = label.lowercased()
            if seen.insert(key).inserted {
                deduped.append(label)
            }
        }
        return deduped
    }

    private nonisolated func extractIndicatorStatusItems(from lines: [String]) -> (statusItems: [String], trailingStateLabel: String?, trailingStatus: String?) {
        var statusItems: [String] = []
        var current = ""
        var trailingStateLabel: String?
        var trailingStatus: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !isDocumentSectionHeadingLine(trimmed) else { break }

            if let splitPair = splitIndicatorStateAndStatusIfNeeded(trimmed) {
                if !current.isEmpty {
                    statusItems.append(normalizeIndicatorStatusText(current))
                    current = ""
                }
                trailingStateLabel = splitPair.label
                trailingStatus = splitPair.status
                continue
            }

            if current.isEmpty {
                current = trimmed
            } else if shouldAppendIndicatorStatusContinuation(trimmed, currentItem: current) {
                current += " " + trimmed
            } else {
                statusItems.append(normalizeIndicatorStatusText(current))
                current = trimmed
            }
        }

        if !current.isEmpty {
            statusItems.append(normalizeIndicatorStatusText(current))
        }

        return (
            statusItems.filter { !$0.isEmpty },
            trailingStateLabel,
            trailingStatus.map(normalizeIndicatorStatusText(_:))
        )
    }

    private nonisolated func splitIndicatorStateAndStatusIfNeeded(_ line: String) -> (label: String, status: String)? {
        let normalized = OCRConfiguration.normalizeExtractedText(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard startsNewIndicatorStateLabel(normalized) else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"^((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z-]+(?:\s+[A-Za-z-]+)?(?:\s*\(\s*\d+(?:\s*(?:secs?|seconds?)\)?)?)?)\s+([A-Z].+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              let labelRange = Range(match.range(at: 1), in: normalized),
              let statusRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        guard let label = normalizeIndicatorStateLabel(String(normalized[labelRange])) else {
            return nil
        }

        let status = normalizeIndicatorStatusText(String(normalized[statusRange]))
        guard !status.isEmpty else { return nil }
        return (label, status)
    }

    private nonisolated func startsNewIndicatorStateLabel(_ line: String) -> Bool {
        line.range(
            of: #"^(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private nonisolated func shouldAppendIndicatorStateContinuation(_ line: String, currentItem: String) -> Bool {
        guard !currentItem.isEmpty else { return false }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return true
        }

        if line.range(of: #"^\d+\s*(?:secs?|seconds?)\)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           currentItem.contains("(")
        {
            return true
        }

        return false
    }

    private nonisolated func shouldAppendIndicatorStatusContinuation(_ line: String, currentItem: String) -> Bool {
        guard !currentItem.isEmpty else { return false }

        if currentItem.contains("(") && !currentItem.contains(")") {
            return true
        }

        if let first = line.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first)
        {
            return true
        }

        let lowered = line.lowercased()
        let continuationPrefixes = ["and ", "or ", "to ", "for ", "with ", "without ", "of ", "the ", "over-", "under-"]
        return continuationPrefixes.contains(where: { lowered.hasPrefix($0) })
    }

    private nonisolated func normalizeIndicatorStateLabel(_ raw: String) -> String? {
        let normalized = OCRConfiguration.normalizeExtractedText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"^((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow))\s+(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              let stateRange = Range(match.range(at: 1), in: normalized),
              let descriptorRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        let state = canonicalIndicatorStateToken(String(normalized[stateRange]))
        let descriptor = normalizeIndicatorDescriptor(String(normalized[descriptorRange]))
        guard !descriptor.isEmpty else { return nil }
        return "\(state) \(descriptor)"
    }

    private nonisolated func normalizeIndicatorDescriptor(_ descriptor: String) -> String {
        var normalized = OCRConfiguration.normalizeExtractedText(descriptor)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "cyanblue", with: "Cyan-blue", options: [.caseInsensitive])
            .replacingOccurrences(of: "cyan blue", with: "Cyan-blue", options: [.caseInsensitive])
            .replacingOccurrences(of: "secs", with: "secs", options: [.caseInsensitive])

        if normalized.range(of: #"\(\s*\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let digits = normalized.filter(\.isNumber)
            if !digits.isEmpty {
                normalized = normalized.replacingOccurrences(
                    of: #"\(\s*\d+\s*$"#,
                    with: "(\(digits) secs)",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        let parts = normalized
            .split(whereSeparator: \.isWhitespace)
            .map { part -> String in
                let token = String(part)
                if token.hasPrefix("(") || token.range(of: #"^\d+$"#, options: [.regularExpression]) != nil {
                    return token
                }
                if token.lowercased() == "secs)" || token.lowercased() == "seconds)" {
                    return "secs)"
                }
                return token
                    .split(separator: "-")
                    .map { $0.capitalized }
                    .joined(separator: "-")
            }

        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func normalizeIndicatorStatusText(_ text: String) -> String {
        OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func isIndicatorStateLabelHeaderLine(_ line: String) -> Bool {
        let normalized = normalizeParallelListHeader(line)
        return normalized == "color of light" || normalized == "indicator light"
    }

    private nonisolated func isIndicatorStateValueHeaderLine(_ line: String) -> Bool {
        let normalized = normalizeParallelListHeader(line)
        return normalized == "plaud status" || normalized == "status" || normalized.contains("status")
    }

    private nonisolated func looksLikeIndicatorStateLabel(_ text: String) -> Bool {
        let normalized = OCRConfiguration.normalizeExtractedText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return startsNewIndicatorStateLabel(normalized)
    }

    private nonisolated func looksLikeMispairedIndicatorStateTable(_ tableData: TableData) -> Bool {
        let rows = dataRows(for: tableData)
        guard !rows.isEmpty else { return false }

        let tableSignals = [
            tableData.caption?.lowercased() ?? "",
            tableData.headerRow?.joined(separator: " ").lowercased() ?? "",
            rows.prefix(2).flatMap { $0 }.joined(separator: " ").lowercased()
        ].joined(separator: " ")

        let indicatorSignal = tableSignals.contains("color of light")
            || tableSignals.contains("plaud status")
            || tableSignals.contains("indicator light")
            || rows.contains { looksLikeIndicatorStateLabel($0.first ?? "") }

        guard indicatorSignal else { return false }

        let mismatchedRows = rows.filter { row in
            let left = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let right = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

            guard !left.isEmpty, !right.isEmpty else { return true }
            if !looksLikeIndicatorStateLabel(left) { return true }
            if looksLikeIndicatorStateLabel(right) { return true }
            if isDocumentSectionHeadingLine(right) { return true }
            if right.count > 140 { return true }
            return false
        }.count

        return mismatchedRows > 0
    }

    private nonisolated func splitParallelListHeader(_ line: String) -> [String] {
        let normalized = OCRConfiguration.normalizeExtractedText(line)
        let separators = ["|", ":", " / ", " - ", " – ", " — "]

        for separator in separators {
            let components = normalized.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if components.count == 2 {
                return components
            }
        }

        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 4 else { return [] }
        let midpoint = words.count / 2
        let left = words[..<midpoint].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = words[midpoint...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return [] }
        return [left, right]
    }

    private nonisolated func looksLikeParallelKeyValueTableCandidate(_ element: StructuredElementWrapper) -> Bool {
        guard element.elementType == "table" else { return false }

        if let tableData = element.tableData {
            let visibleRows = tableData.rows.filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            guard visibleRows.count >= 3 else { return false }
            let maxColumns = visibleRows.map(\.count).max() ?? 0
            return maxColumns <= 3
        }

        let tableText = element.text.lowercased()
        let rowCount = tableText.components(separatedBy: "Row ").count - 1
        let keyValueMarkers = tableText.components(separatedBy: "=").count - 1
        return rowCount >= 3 && keyValueMarkers >= rowCount
    }

    nonisolated func isRecoveredHeuristicTable(_ element: StructuredElementWrapper) -> Bool {
        guard element.elementType == "table" else { return false }

        switch element.extractionSource {
        case "parallel_key_value_recovery", "indicator_state_recovery", "text_inferred":
            return true
        default:
            return false
        }
    }

    private nonisolated func scientificNarrativeSignalCount(in text: String) -> Int {
        let lower = text.lowercased()
        let signals = [
            "abstract", "introduction", "methods", "materials", "results",
            "discussion", "conclusion", "references", "bibliography", "doi",
            "confidence interval", "randomized", "participants", "study"
        ]

        return signals.reduce(into: 0) { count, signal in
            if lower.contains(signal) {
                count += 1
            }
        }
    }

    nonisolated func isLikelyScientificNarrativeSample(_ text: String) -> Bool {
        let lower = text.lowercased()
        let signalCount = scientificNarrativeSignalCount(in: lower)

        if signalCount >= 3 {
            return true
        }

        return signalCount >= 2 && (
            lower.contains("abstract")
            || lower.contains("references")
            || lower.contains("doi")
        )
    }

    private nonisolated func isLikelyScientificReferenceLine(_ line: String) -> Bool {
        let normalized = OCRConfiguration.normalizeExtractedText(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()

        guard normalized.count >= 24 else { return false }

        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count >= 6 else { return false }

        let punctuationCount = normalized.unicodeScalars.filter {
            CharacterSet.punctuationCharacters.contains($0)
        }.count
        let punctuationRatio = Double(punctuationCount) / Double(max(1, normalized.count))
        let hasYear = lower.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) != nil
        let citationPatternMatches = [
            #"^\[?\d+\]?\s+[A-Z]"#,
            #"\bet al\b"#,
            #"\bdoi(?::|\s)"#,
            #"\bpmid\b"#,
            #"\b\d{4}\s*;\s*\d"#
        ].contains { pattern in
            normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        return citationPatternMatches || (hasYear && punctuationRatio >= 0.08 && (lower.contains("doi") || lower.contains("et al") || lower.contains(";")))
    }

    private nonisolated func isLikelyScientificReferencePage(_ pageText: String) -> Bool {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 4 else { return false }

        let leadingHeading = lines.prefix(3).contains { line in
            let lower = line.lowercased()
            return lower == "references" || lower == "bibliography" || lower.hasPrefix("references ")
        }
        let referenceLineCount = lines.filter(isLikelyScientificReferenceLine(_:)).count
        let referenceLineRatio = Double(referenceLineCount) / Double(max(1, lines.count))

        if leadingHeading {
            return referenceLineCount >= 2 || lines.count >= 8
        }

        return referenceLineCount >= 4 && referenceLineRatio >= 0.28
    }

    private nonisolated func isNarrativeDominantPageText(_ pageText: String) -> Bool {
        let lines = pageText
            .components(separatedBy: .newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 4 else { return false }

        let sentenceLikeLines = lines.filter { line in
            let wordCount = line.split(whereSeparator: \.isWhitespace).count
            return wordCount >= 8 && (line.count >= 60 || line.contains(".") || line.contains(";"))
        }.count
        let shortLabelLikeLines = lines.filter { line in
            let wordCount = line.split(whereSeparator: \.isWhitespace).count
            return wordCount <= 5 && line.count <= 42 && !line.hasSuffix(".")
        }.count

        let sentenceRatio = Double(sentenceLikeLines) / Double(max(1, lines.count))
        let shortLabelRatio = Double(shortLabelLikeLines) / Double(max(1, lines.count))
        return sentenceRatio >= 0.45 && shortLabelRatio <= 0.35
    }

    private nonisolated func shouldAttemptStructuredRecoveryFromPDFPageText(_ pageText: String) -> Bool {
        let normalized = pageText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        guard !isLikelyScientificReferencePage(normalized) else { return false }

        if isLikelyScientificNarrativeSample(normalized) && isNarrativeDominantPageText(normalized) {
            return false
        }

        return true
    }

    private nonisolated func normalizedHeadingMatchText(_ text: String) -> String {
        OCRConfiguration.normalizeExtractedText(text)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func titleMatchesTrustedPageText(_ title: String, pageText: String) -> Bool {
        let normalizedTitle = normalizedHeadingMatchText(title)
        let normalizedPageText = normalizedHeadingMatchText(pageText)

        guard !normalizedTitle.isEmpty else { return false }
        guard !normalizedPageText.isEmpty else { return true }

        if normalizedPageText.contains(normalizedTitle) {
            return true
        }

        let preservedShortTerms: Set<String> = ["ifu", "faq", "ocr", "doi", "fda", "iec"]
        let significantTerms = normalizedTitle
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count >= 4 || preservedShortTerms.contains($0) }

        guard !significantTerms.isEmpty else { return true }

        let matchedTermCount = significantTerms.filter { normalizedPageText.contains($0) }.count
        if significantTerms.count == 1 {
            return matchedTermCount == 1
        }

        return matchedTermCount >= max(2, significantTerms.count - 1)
    }

    private nonisolated func canonicalIndicatorStateToken(_ token: String) -> String {
        let lower = token.lowercased()
        if lower.hasPrefix("flash") { return "Flashing" }
        if lower.hasPrefix("blink") { return "Blinking" }
        if lower.hasPrefix("puls") { return "Pulsing" }
        if lower == "solid" { return "Solid" }
        if lower == "steady" { return "Steady" }
        if lower == "rapid" { return "Rapid" }
        if lower == "slow" { return "Slow" }
        return token.capitalized
    }

    private nonisolated func isDocumentSectionHeadingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: #"^\d+(?:\.\d+)*\.?[A-Z]"#, options: .regularExpression) != nil
            || trimmed.range(of: #"^\d+(?:\.\d+)*\.?\s"#, options: .regularExpression) != nil
    }

    private nonisolated func consumeCaptionCandidate(from paragraphBuffer: inout [String]) -> String? {
        guard let last = paragraphBuffer.last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 90 else { return nil }
        guard !trimmed.hasSuffix(".") else { return nil }
        guard !trimmed.contains("|") else { return nil }
        guard !trimmed.contains(":") else { return nil }
        guard trimmed.range(of: #"[.!?]{2,}"#, options: .regularExpression) == nil else { return nil }

        paragraphBuffer.removeLast()
        return trimmed
    }

}

extension String {
    /// The cells of a pipe-table row: split at "|" not preceded by a backslash, with "\|" turned back into "|" (5.8:
    /// table writers escape a pipe inside a cell, so "A|B" in a cell no longer splits the row).
    nonisolated func splitOnUnescapedPipes() -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in self {
            if escaped {
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current)
        return cells
    }
}
