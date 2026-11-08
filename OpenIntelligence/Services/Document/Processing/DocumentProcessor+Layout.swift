//
//  DocumentProcessor+Layout.swift
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
    // MARK: - Spatial Text Extraction (Column-Aware PDFKit)

    /// Represents a text line with its spatial position for column detection
    private struct SpatialLine {
        let text: String
        let xPosition: CGFloat  // X center of the line
        let yPosition: CGFloat  // Y position (for sorting)
        let bounds: CGRect
    }

    /// Extract text from a PDF page using spatial ordering to handle multi-column layouts
    /// This is the key 10x improvement: PDFKit's default extraction often mixes columns
    /// By using character/line bounding boxes, we can detect columns and read correctly
    /// Why a word begins a new spatial line, or that it does not.
    enum SpatialLineBreak: Equatable {
        case none
        /// The word sits on a different row.
        case verticalGap
        /// The word sits on the same row but across a horizontal discontinuity — in a
        /// multi-column page, the gutter.
        case horizontalGap
    }

    /// Decides whether `wordBounds` continues the line built so far or starts a new one.
    ///
    /// `nonisolated static` and taking only geometry so the decision is testable without a
    /// `PDFPage`. That matters here: this is the whole two-column defect, and until now the only
    /// way to exercise it was to ingest a real journal PDF on a device.
    ///
    /// **A vertical test alone cannot see a column gutter.** `page.string` on a two-column PDF
    /// emits words row by row across the gutter, so a left-column word and a right-column word at
    /// the same height arrive adjacent and at the same Y. Grouped on Y alone they become one
    /// `SpatialLine`, and that line's `xPosition` is the *mean* of both columns, landing near the
    /// page centre.
    ///
    /// Everything downstream then fails for a reason it cannot detect. `detectColumnBoundaries`
    /// looks for a gap wider than 10% of the page across those means; once every line sits at the
    /// centre there is no gap, so it returns empty, the single-column branch sorts by Y, and the
    /// columns come out interleaved. The function returns non-nil, so no caller can tell.
    ///
    /// The column signal is destroyed here, before the code that looks for it ever runs. That is
    /// why neither the earlier tie-break fix nor a smarter `detectColumnBoundaries` could have
    /// addressed this, and why that entry carries `symptom_attribution_still_open`.
    ///
    /// Observed on device 2026-08-24: a stored chunk read "…in locomotors are more diverse,
    /// consisting of Gi-coupled 5-HT, and 5-HTS. tion, reinforcement learning…" — two columns
    /// welded line for line, with "locomotion" severed across the splice.
    nonisolated static func spatialLineBreak(
        wordBounds: CGRect,
        currentLineBounds: CGRect,
        currentLineY: CGFloat
    ) -> SpatialLineBreak {
        // No line started yet.
        guard currentLineY >= 0 else { return .none }

        let yThreshold = wordBounds.height * 0.5
        if abs(wordBounds.midY - currentLineY) > yThreshold { return .verticalGap }

        guard !currentLineBounds.isEmpty else { return .none }

        // Reading order runs left to right within a line, so a move back to or past the line's own
        // left edge starts a new line whose Y moved by less than the threshold.
        if wordBounds.minX < currentLineBounds.minX { return .horizontalGap }

        // A forward jump far wider than an inter-word space is a gutter. Word spacing is a fraction
        // of the glyph height and a gutter is a multiple of it, so scaling by height keeps this
        // correct at any page size. The floor covers very small type.
        let gutterThreshold = max(wordBounds.height * 1.5, 8)
        if wordBounds.minX - currentLineBounds.maxX > gutterThreshold { return .horizontalGap }

        return .none
    }

    /// The page's text-layer words with their boxes normalized to the crop box (origin bottom left), the frame Vision's
    /// table cells use when the page is rendered by `renderPDFPageAsImage` (5.8). Empty for a rotated page, whose
    /// rendering turns the frame. Ranges come from the Substring itself, as in `extractTextWithSpatialOrdering`.
    func textLayerWords(of page: PDFPage) -> [TextLayerWord] {
        guard page.rotation == 0, let pageString = page.string, !pageString.isEmpty else { return [] }
        let crop = page.bounds(for: .cropBox)
        guard crop.width > 0, crop.height > 0 else { return [] }
        func normalized(_ bounds: CGRect) -> CGRect {
            CGRect(
                x: (bounds.minX - crop.minX) / crop.width, y: (bounds.minY - crop.minY) / crop.height,
                width: bounds.width / crop.width, height: bounds.height / crop.height)
        }
        var words: [TextLayerWord] = []
        for word in pageString.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let range = NSRange(word.startIndex..<word.endIndex, in: pageString)
            guard let selection = page.selection(for: range) else { continue }
            let bounds = selection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            // A run of digits the page string prints without a space can be several numbers set apart on the page
            // (a contents page's "11 13 13 14" came out as "11131314" on 2026-11-08). Split it where its characters
            // leave a gap of more than a quarter of their height.
            if word.count >= 4, word.allSatisfy(\.isNumber),
                let pieces = Self.digitRunPieces(word, range: range, page: page, height: bounds.height), pieces.count > 1
            {
                words.append(contentsOf: pieces.map { TextLayerWord(text: $0.text, box: normalized($0.bounds)) })
                continue
            }
            words.append(TextLayerWord(text: String(word), box: normalized(bounds)))
        }
        return words
    }

    /// A digit run cut where its characters leave a visible gap, with each piece's bounds; nil when a character has no
    /// selection.
    private static func digitRunPieces(_ word: Substring, range: NSRange, page: PDFPage, height: CGFloat)
        -> [(text: String, bounds: CGRect)]?
    {
        let characters = Array(word)
        guard characters.count == range.length else { return nil }
        var boxes: [CGRect] = []
        for offset in 0..<range.length {
            guard let selection = page.selection(for: NSRange(location: range.location + offset, length: 1)) else { return nil }
            boxes.append(selection.bounds(for: page))
        }
        var pieces: [(text: String, bounds: CGRect)] = []
        var text = String(characters[0])
        var box = boxes[0]
        for index in 1..<characters.count {
            if boxes[index].minX - boxes[index - 1].maxX > height * 0.25 {
                pieces.append((text, box))
                text = ""
                box = boxes[index]
            }
            text.append(characters[index])
            box = box.union(boxes[index])
        }
        pieces.append((text, box))
        return pieces
    }

    func extractTextWithSpatialOrdering(from page: PDFPage) -> String? {
        // Get all selections for lines on this page
        // We'll enumerate through the page character by character to find line boundaries
        guard let pageString = page.string, !pageString.isEmpty else { return nil }

        // Use word-level selection to build spatial lines
        var spatialLines: [SpatialLine] = []
        var currentLineText = ""
        var currentLineY: CGFloat = -1
        var currentLineBounds: CGRect = .zero
        var lineXPositions: [CGFloat] = []

        // Enumerate words and group into lines based on Y position.
        //
        // The range handed to `page.selection(for:)` is taken from the Substring itself rather than
        // from a hand-maintained counter. The counter version under-counted twice over and the two
        // errors compounded: `split(whereSeparator:)` omits empty subsequences, so every run of
        // whitespace collapsed to one gap while the cursor advanced by exactly `+ 1` per gap; and
        // `String.count` counts grapheme clusters while `NSRange` addresses UTF-16 code units, so
        // every ligature drifted it further. Both under-count in the same direction, which is why
        // the range stayed valid and `selection(for:)` kept returning bounds — for the wrong text.
        // The word appended was correct and the coordinates recorded against it were not.
        //
        // `Substring` indices are indices into the base string, so `word.startIndex..<word.endIndex`
        // is already the true range. `in: pageString` is load-bearing: `in: word` would produce
        // word-relative offsets and reintroduce the same defect in a new shape.
        let words = pageString.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var unresolvedWords = 0
        // Counted so a trace can distinguish a genuinely single-column page from a two-column page
        // whose gutter was never seen. Those two produced identical output and identical logs until
        // now, which is what made this defect diagnosable only by inference.
        var columnBreaks = 0

        for word in words {
            let wordString = String(word)

            // Try to find this word in the page and get its bounds
            if let selection = page.selection(for: NSRange(word.startIndex..<word.endIndex, in: pageString)),
               let firstChar = selection.selectionsByLine().first {

                let bounds = firstChar.bounds(for: page)

                let lineBreak = Self.spatialLineBreak(
                    wordBounds: bounds,
                    currentLineBounds: currentLineBounds,
                    currentLineY: currentLineY
                )
                if lineBreak == .horizontalGap { columnBreaks += 1 }
                let isNewLine = lineBreak != .none

                if isNewLine && !currentLineText.isEmpty {
                    // Save the previous line
                    let avgX = lineXPositions.isEmpty ? 0 : lineXPositions.reduce(0, +) / CGFloat(lineXPositions.count)
                    spatialLines.append(SpatialLine(
                        text: currentLineText.trimmingCharacters(in: .whitespaces),
                        xPosition: avgX,
                        yPosition: currentLineY,
                        bounds: currentLineBounds
                    ))
                    currentLineText = ""
                    lineXPositions = []
                    currentLineBounds = .zero
                }

                // Add word to current line
                currentLineText += (currentLineText.isEmpty ? "" : " ") + wordString
                currentLineY = bounds.midY
                lineXPositions.append(bounds.midX)
                currentLineBounds = currentLineBounds.isEmpty ? bounds : currentLineBounds.union(bounds)
            } else {
                // A word PDFKit cannot place. Counted rather than ignored: a page where many words
                // fail to resolve produces sparse, unreliable `spatialLines`, and until this was
                // logged there was no way to tell that from a page that simply has little text.
                unresolvedWords += 1
            }
        }

        // Don't forget the last line
        if !currentLineText.isEmpty {
            let avgX = lineXPositions.isEmpty ? 0 : lineXPositions.reduce(0, +) / CGFloat(lineXPositions.count)
            spatialLines.append(SpatialLine(
                text: currentLineText.trimmingCharacters(in: .whitespaces),
                xPosition: avgX,
                yPosition: currentLineY,
                bounds: currentLineBounds
            ))
        }

        // If we couldn't get spatial info, fall back to simple extraction.
        //
        // Returning nil sends the caller to raw `page.string`, which interleaves columns by
        // construction. That is a real quality cliff and it used to be silent — there was no way to
        // distinguish a nil return here from a success, because the call site reads
        // `extractTextWithSpatialOrdering(from: page) ?? text`.
        guard spatialLines.count > 3 else {
            Log.warning(
                "[DocumentProcessor] Spatial extraction bailed: only \(spatialLines.count) line(s) "
                    + "resolved from \(words.count) word(s), \(unresolvedWords) unplaceable. "
                    + "Falling back to raw page text, which does NOT preserve column order.",
                category: .ingestion
            )
            return nil
        }

        if unresolvedWords > 0 {
            Log.debug(
                "[DocumentProcessor] Spatial extraction: \(unresolvedWords) of \(words.count) "
                    + "word(s) could not be placed on the page",
                category: .ingestion
            )
        }

        if columnBreaks > 0 {
            Log.info(
                "[DocumentProcessor] Spatial extraction split \(columnBreaks) line(s) on a horizontal "
                    + "gap; this page's words arrive across a gutter rather than in reading order",
                category: .ingestion
            )
        }

        // Detect columns from X positions
        let xPositions = spatialLines.map { $0.xPosition }
        let pageWidth = page.bounds(for: .cropBox).width
        let columnBoundaries = detectColumnBoundaries(from: xPositions, pageWidth: pageWidth)

        if columnBoundaries.isEmpty {
            // Treated as a single column and sorted by Y alone.
            //
            // This branch is reached both by genuinely single-column pages and by multi-column pages
            // whose boundaries could not be detected, and the two are indistinguishable from here.
            // In the second case a Y-only sort interleaves the columns, because a line on the left
            // and a line on the right at the same height sort adjacent — which is exactly the
            // damage reported against two-column journal PDFs. It then returns non-nil, so nothing
            // downstream can tell. Logged rather than silently returned.
            //
            // The tiebreak on X is not cosmetic. `sorted(by:)` is not stable in Swift, so equal-Y
            // lines previously came out in arbitrary order — the same page could extract
            // differently on two runs. Ordering ties left-to-right makes the output deterministic
            // and, on an undetected two-column page, at least reading-order-correct per row.
            let sorted = spatialLines.sorted {
                $0.yPosition == $1.yPosition ? $0.xPosition < $1.xPosition : $0.yPosition > $1.yPosition
            }
            Log.debug(
                "[DocumentProcessor] Spatial extraction found no column boundaries across "
                    + "\(spatialLines.count) line(s); reading as a single column",
                category: .ingestion
            )
            return sorted.map { $0.text }.joined(separator: "\n")
        }

        // Multi-column: group lines by column, then sort each column top-to-bottom
        Log.debug("[DocumentProcessor] Spatial extraction detected \(columnBoundaries.count + 1) columns", category: .ingestion)

        var columnGroups: [[SpatialLine]] = Array(repeating: [], count: columnBoundaries.count + 1)

        for line in spatialLines {
            // Find which column this line belongs to
            var columnIndex = 0
            for (i, boundary) in columnBoundaries.enumerated() {
                if line.xPosition > boundary {
                    columnIndex = i + 1
                }
            }
            columnGroups[columnIndex].append(line)
        }

        // Process each column top-to-bottom (higher Y = higher on page in PDF coords)
        var result: [String] = []
        for (colIdx, group) in columnGroups.enumerated() {
            // Same non-stable-sort hazard as the single-column branch above.
            let sortedColumn = group.sorted {
                $0.yPosition == $1.yPosition ? $0.xPosition < $1.xPosition : $0.yPosition > $1.yPosition
            }
            let columnText = sortedColumn.map { $0.text }
            if !columnText.isEmpty {
                result.append(contentsOf: columnText)
                // Add paragraph break between columns
                if colIdx < columnGroups.count - 1 {
                    result.append("")
                }
            }
        }

        return result.joined(separator: "\n")
    }

    /// Detect column boundaries from a list of X positions
    /// Returns X coordinates that separate columns (empty = single column)
    private func detectColumnBoundaries(from xPositions: [CGFloat], pageWidth: CGFloat) -> [CGFloat] {
        guard xPositions.count > 5 else { return [] }

        let sorted = xPositions.sorted()

        // Find gaps between clusters of X positions
        var gaps: [(position: CGFloat, gapSize: CGFloat)] = []

        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i-1]
            // Normalize gap size relative to page width
            let normalizedGap = gap / pageWidth
            if normalizedGap > 0.1 { // Gap > 10% of page width
                gaps.append((position: (sorted[i] + sorted[i-1]) / 2, gapSize: gap))
            }
        }

        // Return boundary positions (sorted)
        return gaps.sorted { $0.gapSize > $1.gapSize }  // Largest gaps first
            .prefix(2)  // Max 3 columns
            .map { $0.position }
            .sorted()
    }

    // MARK: - Layout-Aware Text Extraction (OCR)

    private struct OCRReadingBlock {
        let text: String
        let topY: CGFloat
        let minX: CGFloat
    }

    /// Extract text with awareness of tables and multi-column layouts.
    /// Rebuilds table-heavy OCR pages row-by-row and otherwise reads columns top-to-bottom.
    func extractTextWithColumnAwareness(from observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        if let tableText = extractTableDominantText(from: observations) {
            return tableText
        }

        // Collect X midpoints to detect columns
        let xMidpoints = observations.map { $0.boundingBox.midX }
        let columns = detectColumns(from: xMidpoints)

        // If single column or can't detect columns, use simple reading order
        guard columns.count > 1 else {
            Log.debug("[DocumentProcessor] Single column layout detected", category: .ingestion)
            let result = ConfidenceVerifier.assembleVerifiedText(from: observations)
            if result.uncertainCount > 0 {
                Log.debug("[DocumentProcessor] ⚠️ \(result.uncertainCount) uncertain observations (avg confidence: \(String(format: "%.1f%%", result.avgConfidence * 100)))", category: .ingestion)
            }
            return result.text
        }

        Log.debug("[DocumentProcessor] Multi-column layout detected: \(columns.count) columns", category: .ingestion)

        // Group observations by column
        var columnGroups: [[VNRecognizedTextObservation]] = Array(repeating: [], count: columns.count)

        for observation in observations {
            let xMid = observation.boundingBox.midX
            // Find which column this observation belongs to
            var closestColumn = 0
            var minDistance = CGFloat.greatestFiniteMagnitude

            for (index, columnCenter) in columns.enumerated() {
                let distance = abs(xMid - columnCenter)
                if distance < minDistance {
                    minDistance = distance
                    closestColumn = index
                }
            }

            columnGroups[closestColumn].append(observation)
        }

        // Sort each column top-to-bottom and extract text with confidence verification
        var allText: [String] = []
        for (index, group) in columnGroups.enumerated() {
            let sortedGroup = group.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let result = ConfidenceVerifier.assembleVerifiedText(from: sortedGroup)

            if !result.text.isEmpty {
                let lines = result.text.components(separatedBy: "\n")
                Log.debug("[DocumentProcessor] Column \(index + 1): \(lines.count) text blocks", category: .ingestion)
                allText.append(contentsOf: lines)
                allText.append("") // Paragraph break between columns
            }
        }

        return allText.joined(separator: "\n")
    }

    /// Rebuild table-heavy OCR pages in row order instead of dumping full columns sequentially.
    private func extractTableDominantText(from observations: [VNRecognizedTextObservation]) -> String? {
        let (tables, remaining) = detectTables(from: observations)
        guard shouldPreferDetectedTables(
            tables,
            remaining: remaining,
            totalObservationCount: observations.count
        ) else {
            return nil
        }

        var blocks = tables.compactMap { table -> OCRReadingBlock? in
            let text = table.toText().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRReadingBlock(
                text: text,
                topY: table.boundingBox.maxY,
                minX: table.boundingBox.minX
            )
        }
        blocks.append(contentsOf: buildOCRReadingBlocks(from: remaining))

        let orderedBlocks = blocks.sorted { lhs, rhs in
            if abs(lhs.topY - rhs.topY) > 0.02 {
                return lhs.topY > rhs.topY
            }
            return lhs.minX < rhs.minX
        }

        guard !orderedBlocks.isEmpty else { return nil }

        Log.info(
            "[DocumentProcessor] Table-aware OCR reconstruction: \(tables.count) tables, \(remaining.count) residual observations",
            category: .ingestion
        )
        return orderedBlocks.map(\.text).joined(separator: "\n")
    }

    private func shouldPreferDetectedTables(
        _ tables: [DetectedTable],
        remaining: [VNRecognizedTextObservation],
        totalObservationCount: Int
    ) -> Bool {
        guard !tables.isEmpty else { return false }

        let cellTexts = tables
            .flatMap(\.rows)
            .flatMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cellTexts.isEmpty else { return false }

        let maxColumns = tables
            .compactMap { table in
                table.rows.map(\.count).max()
            }
            .max() ?? 0
        let headerCells = tables.first?.rows.first?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let headerLikeFirstRow = !headerCells.isEmpty && headerCells.allSatisfy {
            isShortOCRCell($0) && $0.rangeOfCharacter(from: .decimalDigits) == nil
        }

        let numericCellRatio = Double(cellTexts.filter {
            $0.rangeOfCharacter(from: .decimalDigits) != nil
        }.count) / Double(cellTexts.count)
        let shortCellRatio = Double(cellTexts.filter(isShortOCRCell).count) / Double(cellTexts.count)
        let narrativeCellRatio = Double(cellTexts.filter(isNarrativeOCRCell).count) / Double(cellTexts.count)
        let tableCoverage = Double(totalObservationCount - remaining.count) / Double(max(1, totalObservationCount))

        let looksNarrativeColumns = maxColumns == 2
            && numericCellRatio < 0.15
            && narrativeCellRatio >= 0.5
            && !headerLikeFirstRow
        let looksTabular = maxColumns >= 3
            || numericCellRatio >= 0.2
            || headerLikeFirstRow
            || (shortCellRatio >= 0.7 && narrativeCellRatio <= 0.35)

        let shouldUseTablePath = looksTabular
            && !looksNarrativeColumns
            && (tableCoverage >= 0.55 || remaining.count <= 6)

        if !shouldUseTablePath {
            Log.debug(
                "[DocumentProcessor] Table candidates resemble narrative columns; keeping column reading order",
                category: .ingestion
            )
        }

        return shouldUseTablePath
    }

    private func buildOCRReadingBlocks(from observations: [VNRecognizedTextObservation]) -> [OCRReadingBlock] {
        guard !observations.isEmpty else { return [] }

        let lineThreshold: CGFloat = 0.02
        let sorted = observations.sorted { lhs, rhs in
            let leftY = lhs.boundingBox.midY
            let rightY = rhs.boundingBox.midY

            if abs(leftY - rightY) > lineThreshold {
                return leftY > rightY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var blocks: [OCRReadingBlock] = []
        var currentLine: [VNRecognizedTextObservation] = []
        var currentY: CGFloat?

        func flushCurrentLine() {
            guard !currentLine.isEmpty else { return }

            let orderedLine = currentLine.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let result = ConfidenceVerifier.assembleVerifiedText(from: orderedLine)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                blocks.append(OCRReadingBlock(
                    text: text,
                    topY: orderedLine.map { $0.boundingBox.maxY }.max() ?? 0,
                    minX: orderedLine.map { $0.boundingBox.minX }.min() ?? 0
                ))
            }

            currentLine.removeAll(keepingCapacity: true)
        }

        for observation in sorted {
            let y = observation.boundingBox.midY

            if let previousY = currentY, abs(y - previousY) >= lineThreshold {
                flushCurrentLine()
            }

            currentLine.append(observation)
            currentY = y
        }

        flushCurrentLine()
        return blocks
    }

    private func isShortOCRCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 4 && text.count <= 36
    }

    private func isNarrativeOCRCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let punctuationCount = text.unicodeScalars.filter {
            CharacterSet(charactersIn: ".,;:!?").contains($0)
        }.count
        return wordCount >= 8 || punctuationCount >= 2
    }

    /// Detect column boundaries using X-position clustering
    /// Returns array of column center X positions
    private func detectColumns(from xMidpoints: [CGFloat]) -> [CGFloat] {
        guard xMidpoints.count > 3 else { return [] }

        // Simple clustering: find gaps in X positions
        let sorted = xMidpoints.sorted()
        var gaps: [(position: CGFloat, gap: CGFloat)] = []

        for i in 1 ..< sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            gaps.append((position: (sorted[i] + sorted[i - 1]) / 2, gap: gap))
        }

        // Find significant gaps (> 15% of page width suggests column boundary)
        let significantGapThreshold: CGFloat = 0.15
        let columnBoundaries = gaps.filter { $0.gap > significantGapThreshold }.map { $0.position }

        if columnBoundaries.isEmpty {
            // Single column
            return [sorted.reduce(0, +) / CGFloat(sorted.count)]
        }

        // Calculate column centers
        var centers: [CGFloat] = []
        var prevBoundary: CGFloat = 0

        for boundary in columnBoundaries.sorted() {
            centers.append((prevBoundary + boundary) / 2)
            prevBoundary = boundary
        }
        centers.append((prevBoundary + 1.0) / 2) // Last column extends to right edge

        return centers
    }

}
