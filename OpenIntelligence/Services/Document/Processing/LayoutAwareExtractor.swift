//
//  LayoutAwareExtractor.swift
//  OpenIntelligence
//
//  Layout-aware PDF text extraction using spatial clustering.
//  Properly handles multi-column layouts by detecting columns algorithmically
//  and reading in correct order (left→right within rows, top→bottom within columns).
//
//  Key insight: PDF text is stored spatially, not in reading order. We must
//  reconstruct reading order from bounding box positions using clustering.
//

import Foundation
import os
import Vision
import PDFKit
import CoreImage

// MARK: - Text Block with Spatial Info

/// A text block with its bounding box for spatial analysis
struct TextBlock: Sendable {
    let text: String
    let boundingBox: CGRect  // Normalized 0-1 coordinates
    let confidence: Float
    let pageNumber: Int
    let id = UUID()

    /// Center X coordinate for column detection
    nonisolated var centerX: CGFloat { boundingBox.midX }

    /// Left edge for line-level ordering
    nonisolated var minX: CGFloat { boundingBox.minX }

    /// Top Y coordinate for vertical ordering (Vision uses bottom-left origin)
    nonisolated var topY: CGFloat { boundingBox.maxY }

    /// Height for line grouping
    nonisolated var height: CGFloat { boundingBox.height }
}

// MARK: - Column Detection

/// Detected column in a document
struct DetectedColumn: Sendable {
    let index: Int
    let xRange: ClosedRange<CGFloat>  // X coordinate range
    var blocks: [TextBlock]

    /// Sort blocks top-to-bottom within this column
    mutating func sortByReadingOrder() {
        blocks.sort { $0.topY > $1.topY }  // Higher Y = higher on page
    }
}

// MARK: - Layout Analysis Result

struct LayoutAnalysisResult: Sendable {
    let pageNumber: Int
    let columns: [DetectedColumn]
    let tables: [TableRegion]
    let readingOrderText: String
    let rawBlocks: [TextBlock]

    /// Number of columns detected
    nonisolated var columnCount: Int { columns.count }

    /// Whether this is a multi-column layout
    nonisolated var isMultiColumn: Bool { columns.count > 1 }
}

/// A detected table region (for special handling)
struct TableRegion: Sendable {
    let boundingBox: CGRect
    let rows: [[String]]
    let pageNumber: Int

    nonisolated var topY: CGFloat { boundingBox.maxY }
    nonisolated var minX: CGFloat { boundingBox.minX }
}

// MARK: - Layout-Aware Extractor

/// Extracts text from PDFs using spatial analysis for correct reading order
actor LayoutAwareExtractor {

    static let shared = LayoutAwareExtractor()
    private nonisolated static let visionRenderContext = CIContext(options: [.cacheIntermediates: false])
    private nonisolated static let renderLock = OSAllocatedUnfairLock()

    private init() {}

    // MARK: - Configuration

    /// Minimum gap between columns (as fraction of page width)
    private let columnGapThreshold: CGFloat = 0.03

    /// Minimum column width (as fraction of page width)
    private let minColumnWidth: CGFloat = 0.15

    /// Vertical tolerance for grouping text on same line
    private let lineToleranceRatio: CGFloat = 0.5  // % of average line height

    /// Minimum confidence for text recognition
    private let minConfidence: Float = 0.5

    private struct ReadingElement: Sendable {
        let text: String
        let topY: CGFloat
        let minX: CGFloat
    }

    // MARK: - Public API

    /// Extract text from a PDF page with layout awareness
    /// - Parameters:
    ///   - image: Rendered page image
    ///   - pageNumber: 1-indexed page number
    /// - Returns: Layout analysis with proper reading order
    func extractWithLayout(from image: CIImage, pageNumber: Int) async throws -> LayoutAnalysisResult {
        Log.info("[LayoutAwareExtractor] 🔍 Analyzing page \(pageNumber) layout (image: \(Int(image.extent.width))×\(Int(image.extent.height)))", category: .ingestion)

        // Report ANE activity to HUD (Vision uses Neural Engine for text recognition)
        Task { @MainActor in
            HardwareTelemetryState.shared.pulse(.reranking, intensity: 0.7, duration: 0.4)
        }

        // Step 1: Get all text blocks with bounding boxes using Vision
        let blocks = try await recognizeTextBlocks(in: image, pageNumber: pageNumber)

        Log.debug("[LayoutAwareExtractor] Page \(pageNumber): Vision returned \(blocks.count) text blocks", category: .ingestion)

        // Log some sample block positions for debugging
        if blocks.count > 0 {
            let sampleBlocks = Array(blocks.prefix(5))
            for (i, block) in sampleBlocks.enumerated() {
                Log.debug("[LayoutAwareExtractor] Block \(i): X=\(String(format: "%.2f", block.boundingBox.minX))-\(String(format: "%.2f", block.boundingBox.maxX)), text='\(block.text.prefix(30))'", category: .ingestion)
            }
        }

        guard !blocks.isEmpty else {
            return LayoutAnalysisResult(
                pageNumber: pageNumber,
                columns: [],
                tables: [],
                readingOrderText: "",
                rawBlocks: []
            )
        }

        // Step 2: Detect tables (they need special handling)
        let (tableRegions, nonTableBlocks) = detectAndSeparateTables(blocks: blocks, pageNumber: pageNumber)

        // Step 3: Detect columns using spatial clustering
        var columns = detectColumns(from: nonTableBlocks)

        // Step 4: Sort blocks within each column by reading order (top to bottom)
        for i in columns.indices {
            columns[i].blocks.sort { $0.topY > $1.topY }  // Higher Y = higher on page
        }

        // Step 5: Build reading order text
        let readingOrderText = buildReadingOrderText(columns: columns, tables: tableRegions)

        Log.info("[LayoutAwareExtractor] Page \(pageNumber): \(columns.count) columns detected, \(blocks.count) blocks, \(tableRegions.count) tables", category: .ingestion)

        return LayoutAnalysisResult(
            pageNumber: pageNumber,
            columns: columns,
            tables: tableRegions,
            readingOrderText: readingOrderText,
            rawBlocks: blocks
        )
    }

    /// Extract text from a PDFPage using native PDFKit with layout enhancement
    func extractWithLayout(from page: PDFPage, pageNumber: Int) async throws -> LayoutAnalysisResult {
        // Get text with selection for bounding boxes
        let blocks = extractBlocksFromPDFPage(page, pageNumber: pageNumber)

        guard !blocks.isEmpty else {
            // Fallback to simple string if no blocks detected
            let simpleText = page.string ?? ""
            return LayoutAnalysisResult(
                pageNumber: pageNumber,
                columns: [DetectedColumn(index: 0, xRange: 0...1, blocks: [])],
                tables: [],
                readingOrderText: simpleText,
                rawBlocks: []
            )
        }

        // Same column detection as Vision path
        let (tableRegions, nonTableBlocks) = detectAndSeparateTables(blocks: blocks, pageNumber: pageNumber)
        var columns = detectColumns(from: nonTableBlocks)

        // Sort blocks within each column by reading order (top to bottom)
        for i in columns.indices {
            columns[i].blocks.sort { $0.topY > $1.topY }  // Higher Y = higher on page
        }

        let readingOrderText = buildReadingOrderText(columns: columns, tables: tableRegions)

        return LayoutAnalysisResult(
            pageNumber: pageNumber,
            columns: columns,
            tables: tableRegions,
            readingOrderText: readingOrderText,
            rawBlocks: blocks
        )
    }

    // MARK: - Vision Text Recognition

    private func recognizeTextBlocks(in image: CIImage, pageNumber: Int) async throws -> [TextBlock] {
        // Capture actor-isolated value before entering nonisolated context
        let minConf = self.minConfidence
        let renderedCG = Self.renderLock.withLock {
            let img = Self.visionRenderContext.createCGImage(image, from: image.extent)
            _ = img?.dataProvider?.data
            return img
        }

        guard let cgImage = renderedCG else {
            throw NSError(
                domain: "LayoutAwareExtractor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to materialize page image for layout OCR"]
            )
        }

        // Use actor-based async throttle to avoid priority inversion warnings
        // VisionOCRThrottle.perform uses AsyncSemaphore internally
        return try await VisionOCRThrottle.perform {
            // Use autoreleasepool to force Vision object cleanup within throttle window
            // This prevents cross-thread deallocation races on Mac
            try autoreleasepool { () -> [TextBlock] in
                let request = VNRecognizeTextRequest()

                // === GPU/ANE OPTIMIZED CONFIGURATION ===
                request.revision = VNRecognizeTextRequestRevision3
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE"]
                request.minimumTextHeight = 0.0

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                guard let observations = request.results else {
                    return []
                }

                // Extract ALL data from observations NOW before they're released
                return observations.compactMap { observation -> TextBlock? in
                    guard observation.confidence >= minConf,
                          let text = observation.topCandidates(1).first?.string,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }

                    return TextBlock(
                        text: String(text),  // Force copy
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        pageNumber: pageNumber
                    )
                }
            }
        }
    }

    // MARK: - PDFKit Block Extraction

    private func extractBlocksFromPDFPage(_ page: PDFPage, pageNumber: Int) -> [TextBlock] {
        guard let pageText = page.string, !pageText.isEmpty else {
            return []
        }

        var blocks: [TextBlock] = []
        let pageBounds = page.bounds(for: .mediaBox)

        // Use PDFPage's selection API to get character positions
        // We'll build blocks by finding continuous text regions

        // Strategy: Get selections for each line and use their bounds
        let lines = pageText.components(separatedBy: .newlines)
        var searchStart = pageText.startIndex

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }

            // Find this line in the page
            if let range = pageText.range(of: trimmedLine, range: searchStart..<pageText.endIndex),
               let selection = page.selection(for: NSRange(range, in: pageText)) {

                let bounds = selection.bounds(for: page)

                // Normalize to 0-1 coordinates
                let normalizedBounds = CGRect(
                    x: bounds.minX / pageBounds.width,
                    y: bounds.minY / pageBounds.height,
                    width: bounds.width / pageBounds.width,
                    height: bounds.height / pageBounds.height
                )

                blocks.append(TextBlock(
                    text: trimmedLine,
                    boundingBox: normalizedBounds,
                    confidence: 1.0,  // Native text is high confidence
                    pageNumber: pageNumber
                ))

                searchStart = range.upperBound
            }
        }

        return blocks
    }

    // MARK: - Column Detection Algorithm

    /// Detect columns using X-coordinate histogram clustering
    /// Uses LEFT EDGE of bounding boxes for more reliable column detection
    private func detectColumns(from blocks: [TextBlock]) -> [DetectedColumn] {
        guard !blocks.isEmpty else { return [] }

        // Use LEFT EDGE (minX) not center - more reliable for column detection
        // because left-aligned text in columns has consistent left edges
        let leftEdges = blocks.map { $0.boundingBox.minX }.sorted()

        // Build histogram of left edges to find column starts
        // Columns show up as peaks in the histogram
        let binWidth: CGFloat = 0.02  // 2% of page width per bin
        var histogram: [Int: Int] = [:]  // bin -> count

        for edge in leftEdges {
            let bin = Int(edge / binWidth)
            histogram[bin, default: 0] += 1
        }

        // Find peaks (bins with significant counts)
        let threshold = max(3, blocks.count / 20)  // At least 3 blocks or 5% of total
        let peaks = histogram.filter { $0.value >= threshold }
            .keys.sorted()
            .map { CGFloat($0) * binWidth }

        Log.debug("[LayoutAwareExtractor] Found \(peaks.count) column left-edge peaks at X: \(peaks.map { String(format: "%.2f", $0) })", category: .ingestion)

        // If we found clear column starts, use them as boundaries
        if peaks.count >= 2 {
            // Check if peaks are sufficiently separated (>20% page width apart)
            var columnStarts: [CGFloat] = [peaks[0]]
            for peak in peaks.dropFirst() {
                if peak - columnStarts.last! > 0.20 {
                    columnStarts.append(peak)
                }
            }

            if columnStarts.count >= 2 {
                // Create columns from detected starts
                var columns: [DetectedColumn] = []
                for (idx, start) in columnStarts.enumerated() {
                    let end: CGFloat = idx + 1 < columnStarts.count ? columnStarts[idx + 1] - 0.01 : 1.0

                    let columnBlocks = blocks.filter { block in
                        let leftEdge = block.boundingBox.minX
                        return leftEdge >= start - 0.02 && leftEdge < end
                    }

                    if !columnBlocks.isEmpty {
                        columns.append(DetectedColumn(
                            index: columns.count,
                            xRange: start...end,
                            blocks: columnBlocks
                        ))
                    }
                }

                if columns.count >= 2 {
                    Log.info("[LayoutAwareExtractor] ✅ Detected \(columns.count)-column layout", category: .ingestion)
                    return columns
                }
            }
        }

        // Fallback: gap-based detection using centers
        let xCenters = blocks.map { $0.centerX }.sorted()

        // Find gaps in X distribution that indicate column boundaries
        var gaps: [(position: CGFloat, size: CGFloat)] = []
        for i in 1..<xCenters.count {
            let gap = xCenters[i] - xCenters[i-1]
            if gap > columnGapThreshold {
                let gapCenter = (xCenters[i] + xCenters[i-1]) / 2
                gaps.append((position: gapCenter, size: gap))
            }
        }

        // Sort gaps by size (largest gaps are most likely column boundaries)
        let significantGaps = gaps
            .filter { $0.size > columnGapThreshold }
            .sorted { $0.size > $1.size }

        // Create column boundaries
        var boundaries: [CGFloat] = [0.0]
        for gap in significantGaps.prefix(3) {  // Max 4 columns
            boundaries.append(gap.position)
        }
        boundaries.append(1.0)
        boundaries.sort()

        // Remove columns that are too narrow
        var validBoundaries: [CGFloat] = [boundaries[0]]
        for i in 1..<boundaries.count {
            if boundaries[i] - validBoundaries.last! >= minColumnWidth {
                validBoundaries.append(boundaries[i])
            }
        }
        if validBoundaries.last! < 1.0 {
            validBoundaries.append(1.0)
        }

        // Assign blocks to columns
        var columns: [DetectedColumn] = []
        for i in 0..<(validBoundaries.count - 1) {
            let xMin = validBoundaries[i]
            let xMax = validBoundaries[i + 1]

            let columnBlocks = blocks.filter { block in
                block.centerX >= xMin && block.centerX < xMax
            }

            if !columnBlocks.isEmpty {
                columns.append(DetectedColumn(
                    index: columns.count,
                    xRange: xMin...xMax,
                    blocks: columnBlocks
                ))
            }
        }

        // If no columns detected (single column layout), use all blocks
        if columns.isEmpty {
            columns.append(DetectedColumn(
                index: 0,
                xRange: 0...1,
                blocks: blocks
            ))
        }

        return columns
    }

    // MARK: - Table Detection

    /// Detect table regions and separate from regular text
    private func detectAndSeparateTables(blocks: [TextBlock], pageNumber: Int) -> ([TableRegion], [TextBlock]) {
        guard blocks.count >= 4 else { return ([], blocks) }

        let avgHeight = blocks.map { $0.height }.reduce(0, +) / CGFloat(blocks.count)
        let lineThreshold = max(0.015, avgHeight * lineToleranceRatio)
        let sortedBlocks = blocks.sorted { lhs, rhs in
            if abs(lhs.topY - rhs.topY) > lineThreshold {
                return lhs.topY > rhs.topY
            }
            return lhs.minX < rhs.minX
        }

        var rows: [[TextBlock]] = []
        var currentRow: [TextBlock] = []
        var currentY: CGFloat?

        func flushRow() {
            guard !currentRow.isEmpty else { return }
            rows.append(currentRow.sorted { $0.minX < $1.minX })
            currentRow.removeAll(keepingCapacity: true)
        }

        for block in sortedBlocks {
            if let previousY = currentY, abs(block.topY - previousY) >= lineThreshold {
                flushRow()
            }
            currentRow.append(block)
            currentY = block.topY
        }
        flushRow()

        var tables: [TableRegion] = []
        var tableBlockIDs: Set<UUID> = []
        var rowIndex = 0

        while rowIndex < rows.count {
            let columnCount = rows[rowIndex].count

            guard columnCount >= 2 else {
                rowIndex += 1
                continue
            }

            var tableRows: [[TextBlock]] = [rows[rowIndex]]
            var nextIndex = rowIndex + 1

            while nextIndex < rows.count {
                let nextColumnCount = rows[nextIndex].count
                if nextColumnCount >= 2 && abs(nextColumnCount - columnCount) <= 1 {
                    tableRows.append(rows[nextIndex])
                    nextIndex += 1
                } else {
                    break
                }
            }

            if tableRows.count >= 2,
               hasConsistentColumnAlignment(tableRows),
               shouldTreatAsTable(tableRows, totalBlockCount: blocks.count)
            {
                let allTableBlocks = tableRows.flatMap { $0 }
                let minX = allTableBlocks.map(\.minX).min() ?? 0
                let maxX = allTableBlocks.map { $0.boundingBox.maxX }.max() ?? 1
                let minY = allTableBlocks.map { $0.boundingBox.minY }.min() ?? 0
                let maxY = allTableBlocks.map(\.topY).max() ?? 1

                tables.append(TableRegion(
                    boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                    rows: tableRows.map { $0.map(\.text) },
                    pageNumber: pageNumber
                ))

                for block in allTableBlocks {
                    tableBlockIDs.insert(block.id)
                }

                Log.debug(
                    "[LayoutAwareExtractor] Page \(pageNumber): detected table with \(tableRows.count) rows × \(columnCount) columns",
                    category: .ingestion
                )
            }

            rowIndex = nextIndex
        }

        let remaining = blocks.filter { !tableBlockIDs.contains($0.id) }
        return (tables, remaining)
    }

    // MARK: - Reading Order Construction

    /// Build text in proper reading order from detected columns
    private func buildReadingOrderText(columns: [DetectedColumn], tables: [TableRegion]) -> String {
        let sortedColumns = columns.sorted { $0.xRange.lowerBound < $1.xRange.lowerBound }
        guard !sortedColumns.isEmpty else {
            return tables
                .sorted { lhs, rhs in
                    if abs(lhs.topY - rhs.topY) > 0.02 {
                        return lhs.topY > rhs.topY
                    }
                    return lhs.minX < rhs.minX
                }
                .map(renderTableText)
                .joined(separator: "\n\n")
        }

        var renderedSections: [String] = []
        var assignedTableIndexes = Set<Int>()

        // In true multi-column layouts, prose should stay within each column's reading flow.
        // Only order elements vertically inside a column, then move to the next column.
        for column in sortedColumns {
            var elements: [ReadingElement] = []

            // Group blocks by approximate Y position (same line)
            let lineGroups = groupBlocksByLine(column.blocks)

            // Sort line groups top-to-bottom
            let sortedLines = lineGroups.sorted { $0.key > $1.key }  // Higher Y = top

            for (_, lineBlocks) in sortedLines {
                // Sort blocks within line left-to-right
                let sortedLineBlocks = lineBlocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                let lineText = sortedLineBlocks.map { $0.text }.joined(separator: " ")
                let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else { continue }

                elements.append(ReadingElement(
                    text: trimmedLine,
                    topY: sortedLineBlocks.map(\.topY).max() ?? 0,
                    minX: sortedLineBlocks.map(\.minX).min() ?? 0
                ))
            }

            for (tableIndex, table) in tables.enumerated() where assignedColumnIndex(for: table, columns: sortedColumns) == column.index {
                assignedTableIndexes.insert(tableIndex)
                elements.append(ReadingElement(
                    text: renderTableText(table),
                    topY: table.topY,
                    minX: table.minX
                ))
            }

            let orderedElements = elements.sorted { lhs, rhs in
                if abs(lhs.topY - rhs.topY) > 0.02 {
                    return lhs.topY > rhs.topY
                }
                return lhs.minX < rhs.minX
            }

            let columnText = orderedElements
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !columnText.isEmpty {
                renderedSections.append(columnText)
            }
        }

        let orphanTables = tables.enumerated()
            .filter { !assignedTableIndexes.contains($0.offset) }
            .sorted { lhs, rhs in
                if abs(lhs.element.topY - rhs.element.topY) > 0.02 {
                    return lhs.element.topY > rhs.element.topY
                }
                return lhs.element.minX < rhs.element.minX
            }
            .map { renderTableText($0.element) }

        renderedSections.append(contentsOf: orphanTables)
        return renderedSections.joined(separator: "\n\n")
    }

    private func assignedColumnIndex(for table: TableRegion, columns: [DetectedColumn]) -> Int? {
        guard !columns.isEmpty else { return nil }

        // Wide tables often span the page and shouldn't be forced into a single column flow.
        if columns.count > 1 && table.boundingBox.width >= 0.7 {
            return nil
        }

        let overlappingColumns = columns.compactMap { column -> (index: Int, overlap: CGFloat, distance: CGFloat)? in
            let overlap = horizontalOverlapWidth(between: table.boundingBox, and: column.xRange)
            guard overlap > 0 else { return nil }

            let columnMidX = (column.xRange.lowerBound + column.xRange.upperBound) / 2
            let distance = abs(table.boundingBox.midX - columnMidX)
            return (index: column.index, overlap: overlap, distance: distance)
        }

        if let bestOverlap = overlappingColumns.max(by: { lhs, rhs in
            if abs(lhs.overlap - rhs.overlap) > 0.001 {
                return lhs.overlap < rhs.overlap
            }
            return lhs.distance > rhs.distance
        }) {
            return bestOverlap.index
        }

        return columns.min(by: { lhs, rhs in
            let lhsMidX = (lhs.xRange.lowerBound + lhs.xRange.upperBound) / 2
            let rhsMidX = (rhs.xRange.lowerBound + rhs.xRange.upperBound) / 2
            return abs(table.boundingBox.midX - lhsMidX) < abs(table.boundingBox.midX - rhsMidX)
        })?.index
    }

    private func horizontalOverlapWidth(between rect: CGRect, and range: ClosedRange<CGFloat>) -> CGFloat {
        let overlapMin = max(rect.minX, range.lowerBound)
        let overlapMax = min(rect.maxX, range.upperBound)
        return max(0, overlapMax - overlapMin)
    }

    /// Group blocks that appear on the same line based on Y position
    private func groupBlocksByLine(_ blocks: [TextBlock]) -> [CGFloat: [TextBlock]] {
        guard !blocks.isEmpty else { return [:] }

        // Calculate average line height
        let avgHeight = blocks.map { $0.height }.reduce(0, +) / CGFloat(blocks.count)
        let lineTolerance = avgHeight * lineToleranceRatio

        var groups: [CGFloat: [TextBlock]] = [:]

        for block in blocks {
            // Find existing group within tolerance
            let matchingKey = groups.keys.first { abs($0 - block.topY) < lineTolerance }

            if let key = matchingKey {
                groups[key]?.append(block)
            } else {
                groups[block.topY] = [block]
            }
        }

        return groups
    }

    private func hasConsistentColumnAlignment(_ rows: [[TextBlock]]) -> Bool {
        guard rows.count >= 2 else { return false }

        let referenceXs = rows[0].map(\.centerX)
        let alignmentThreshold: CGFloat = 0.05

        for row in rows.dropFirst() {
            let rowXs = row.map(\.centerX)
            var alignedCount = 0

            for x in rowXs {
                if referenceXs.contains(where: { abs($0 - x) < alignmentThreshold }) {
                    alignedCount += 1
                }
            }

            if alignedCount < max(1, row.count / 2) {
                return false
            }
        }

        return true
    }

    private func shouldTreatAsTable(_ rows: [[TextBlock]], totalBlockCount: Int) -> Bool {
        let cellTexts = rows
            .flatMap { $0 }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cellTexts.isEmpty else { return false }

        let maxColumns = rows.map(\.count).max() ?? 0
        let headerCells = rows.first?
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let headerLikeFirstRow = !headerCells.isEmpty && headerCells.allSatisfy {
            isShortTableCell($0) && $0.rangeOfCharacter(from: .decimalDigits) == nil
        }

        let numericCellRatio = Double(cellTexts.filter {
            $0.rangeOfCharacter(from: .decimalDigits) != nil
        }.count) / Double(cellTexts.count)
        let shortCellRatio = Double(cellTexts.filter(isShortTableCell).count) / Double(cellTexts.count)
        let narrativeCellRatio = Double(cellTexts.filter(isNarrativeTableCell).count) / Double(cellTexts.count)
        let tableCoverage = Double(rows.flatMap { $0 }.count) / Double(max(1, totalBlockCount))

        let looksNarrativeColumns = maxColumns == 2
            && numericCellRatio < 0.15
            && narrativeCellRatio >= 0.5
            && !headerLikeFirstRow
        let looksTabular = maxColumns >= 3
            || numericCellRatio >= 0.2
            || headerLikeFirstRow
            || (shortCellRatio >= 0.7 && narrativeCellRatio <= 0.35)

        return looksTabular && !looksNarrativeColumns && tableCoverage >= 0.55
    }

    private func renderTableText(_ table: TableRegion) -> String {
        guard !table.rows.isEmpty else { return "" }

        var output = "[Table]\n"
        let firstRow = table.rows[0]
        output += "| " + firstRow.joined(separator: " | ") + " |\n"
        output += "|" + firstRow.map { _ in "---" }.joined(separator: "|") + "|\n"

        for row in table.rows.dropFirst() {
            output += "| " + row.joined(separator: " | ") + " |\n"
        }

        output += "[/Table]"
        return output
    }

    private func isShortTableCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 4 && text.count <= 36
    }

    private func isNarrativeTableCell(_ text: String) -> Bool {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        let punctuationCount = text.unicodeScalars.filter {
            CharacterSet(charactersIn: ".,;:!?").contains($0)
        }.count
        return wordCount >= 8 || punctuationCount >= 2
    }
}

// MARK: - Integration with DocumentProcessor

extension LayoutAwareExtractor {

    /// High-level extraction that combines layout analysis with structure detection
    /// Returns text optimized for RAG chunking
    func extractForRAG(from image: CIImage, nativeText: String?, pageNumber: Int) async throws -> String {
        // Try layout-aware extraction
        let layoutResult = try await extractWithLayout(from: image, pageNumber: pageNumber)

        Log.debug("[LayoutAwareExtractor] Page \(pageNumber): \(layoutResult.rawBlocks.count) blocks, \(layoutResult.columnCount) columns detected", category: .ingestion)

        if !layoutResult.tables.isEmpty {
            Log.info(
                "[LayoutAwareExtractor] Page \(pageNumber): detected \(layoutResult.tables.count) table region(s), preserving layout-aware table reconstruction",
                category: .ingestion
            )
            return layoutResult.readingOrderText
        }

        // If we detected multiple columns, use our reading order
        if layoutResult.isMultiColumn {
            Log.info("[LayoutAwareExtractor] Page \(pageNumber): ✅ Multi-column detected (\(layoutResult.columnCount) cols), using layout-aware order", category: .ingestion)
            // Log first 200 chars of reading order text for debugging
            let preview = String(layoutResult.readingOrderText.prefix(200))
            Log.debug("[LayoutAwareExtractor] Page \(pageNumber) layout text preview: \(preview)...", category: .ingestion)
            return layoutResult.readingOrderText
        }

        // Single column - native text is probably fine
        if let native = nativeText, !native.isEmpty {
            Log.debug("[LayoutAwareExtractor] Page \(pageNumber): Single column, using native text", category: .ingestion)
            return native
        }

        // Fall back to layout result
        return layoutResult.readingOrderText
    }
}
