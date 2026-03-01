//
//  SpatialDocumentAnalyzer.swift
//  OpenIntelligence
//
//  Advanced spatial analysis for document understanding.
//  Extracts text hierarchy, font sizes, layout structure, and caption-image relationships.
//
//  Fills gaps in basic OCR:
//  1. Text size detection → hierarchy inference (headers vs body)
//  2. Font weight heuristics → emphasis detection
//  3. Complex multi-column layouts → flow detection
//  4. Table cell alignment → left/right/center
//  5. Caption-image proximity → figure association
//

import Foundation
import Vision
import CoreImage

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Data Models

/// Text element with full spatial metadata
struct SpatialTextElement: Sendable {
    let text: String
    let boundingBox: CGRect  // Normalized 0-1 coordinates
    let confidence: Float

    // Derived spatial properties
    let relativeHeight: CGFloat  // Height relative to median text height
    let estimatedFontSize: FontSizeCategory
    let isAllCaps: Bool
    let isShortLine: Bool  // Likely header or label

    // Layout context
    let columnIndex: Int
    let lineIndex: Int
    let readingOrder: Int

    enum FontSizeCategory: String, Sendable {
        case title      // > 2x median height
        case heading1   // 1.5-2x median height
        case heading2   // 1.2-1.5x median height
        case body       // 0.8-1.2x median height
        case small      // < 0.8x median height (footnotes, captions)
    }
}

/// Document hierarchy element
struct DocumentHierarchyElement: Sendable {
    let level: Int  // 0 = title, 1 = h1, 2 = h2, etc.
    let text: String
    let pageNumber: Int
    let startY: CGFloat  // For ordering
    let children: [DocumentHierarchyElement]

    nonisolated var markdown: String {
        let prefix = String(repeating: "#", count: min(level + 1, 6))
        return "\(prefix) \(text)"
    }
}

/// Detected figure/image region
struct DetectedFigure: Sendable {
    let boundingBox: CGRect
    let pageNumber: Int
    let figureIndex: Int
    let caption: String?
    let referencedBy: [String]  // Text that references this figure
}

/// Table cell with alignment info
struct AlignedTableCell: Sendable {
    let text: String
    let row: Int
    let column: Int
    let alignment: TextAlignment
    let isHeader: Bool

    enum TextAlignment: String, Sendable {
        case left
        case center
        case right
        case unknown
    }
}

/// Multi-column layout analysis result (renamed to avoid conflict with ImageUnderstandingService.ColumnLayout)
struct SpatialColumnLayout: Sendable {
    let columnCount: Int
    let columnBoundaries: [CGFloat]  // X positions of column separators
    let columnWidths: [CGFloat]
    let hasVariableWidth: Bool
    let textFlowPattern: TextFlowPattern

    enum TextFlowPattern: String, Sendable {
        case singleColumn
        case multiColumnSimple      // Standard newspaper-style
        case multiColumnComplex     // Variable widths, spanning elements
        case wrapAroundImage        // Text flows around figures
    }
}

/// Complete spatial analysis result for a page
struct SpatialPageAnalysis: Sendable {
    let pageNumber: Int
    let elements: [SpatialTextElement]
    let hierarchy: [DocumentHierarchyElement]
    let layout: SpatialColumnLayout
    let figures: [DetectedFigure]
    let captionAssociations: [(caption: String, figureIndex: Int)]

    /// Reconstructed text in reading order with hierarchy markers
    var structuredText: String {
        var lines: [String] = []

        // Add hierarchy markers
        for element in hierarchy {
            lines.append(element.markdown)
        }

        // Add body text in reading order
        let bodyElements = elements.filter { $0.estimatedFontSize == .body || $0.estimatedFontSize == .small }
        let sorted = bodyElements.sorted { $0.readingOrder < $1.readingOrder }

        var currentColumn = -1
        for element in sorted {
            if element.columnIndex != currentColumn {
                currentColumn = element.columnIndex
                if currentColumn > 0 {
                    lines.append("\n---\n")  // Column separator
                }
            }
            lines.append(element.text)
        }

        // Add figure captions
        for (caption, figIndex) in captionAssociations {
            lines.append("[Figure \(figIndex + 1): \(caption)]")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Spatial Document Analyzer

/// Advanced spatial analysis for document understanding
actor SpatialDocumentAnalyzer {

    static let shared = SpatialDocumentAnalyzer()

    private init() {}

    // MARK: - Main Analysis Entry Point

    /// Perform full spatial analysis on OCR observations
    func analyze(
        observations: [VNRecognizedTextObservation],
        pageNumber: Int,
        pageSize: CGSize
    ) -> SpatialPageAnalysis {

        // Step 1: Calculate median text height for relative sizing
        let heights = observations.map { $0.boundingBox.height }
        let medianHeight = calculateMedian(heights)

        // Step 2: Detect column layout
        let layout = detectColumnLayout(observations: observations)

        // Step 3: Convert observations to spatial elements with metadata
        let elements = observations.enumerated().map { index, obs in
            createSpatialElement(
                observation: obs,
                index: index,
                medianHeight: medianHeight,
                layout: layout
            )
        }

        // Step 4: Build document hierarchy from large/emphasized text
        let hierarchy = buildHierarchy(from: elements, pageNumber: pageNumber)

        // Step 5: Detect figures (large empty regions bounded by text)
        let figures = detectFigures(elements: elements, pageNumber: pageNumber)

        // Step 6: Associate captions with figures
        let captionAssociations = associateCaptions(
            elements: elements,
            figures: figures
        )

        Log.debug("[SpatialAnalyzer] Page \(pageNumber): \(elements.count) elements, \(hierarchy.count) headers, \(layout.columnCount) columns, \(figures.count) figures", category: .ingestion)

        return SpatialPageAnalysis(
            pageNumber: pageNumber,
            elements: elements,
            hierarchy: hierarchy,
            layout: layout,
            figures: figures,
            captionAssociations: captionAssociations
        )
    }

    // MARK: - Text Size & Hierarchy Detection

    private func createSpatialElement(
        observation: VNRecognizedTextObservation,
        index: Int,
        medianHeight: CGFloat,
        layout: SpatialColumnLayout
    ) -> SpatialTextElement {
        let box = observation.boundingBox
        let text = observation.topCandidates(1).first?.string ?? ""
        let confidence = observation.topCandidates(1).first?.confidence ?? 0

        // Calculate relative height
        let relativeHeight = medianHeight > 0 ? box.height / medianHeight : 1.0

        // Determine font size category
        let fontCategory: SpatialTextElement.FontSizeCategory = {
            if relativeHeight > 2.0 { return .title }
            if relativeHeight > 1.5 { return .heading1 }
            if relativeHeight > 1.2 { return .heading2 }
            if relativeHeight < 0.8 { return .small }
            return .body
        }()

        // Check for ALL CAPS (emphasis indicator)
        let isAllCaps = text.count > 3 && text == text.uppercased() && text.contains(where: { $0.isLetter })

        // Short lines are often headers/labels
        let isShortLine = text.count < 50 && !text.contains(".")

        // Determine column index
        let columnIndex = determineColumnIndex(x: box.midX, layout: layout)

        // Calculate reading order (column-major, top-to-bottom)
        let lineIndex = Int((1.0 - box.midY) * 100)  // Higher Y = lower line index (Vision coords)
        let readingOrder = columnIndex * 1000 + lineIndex

        return SpatialTextElement(
            text: text,
            boundingBox: box,
            confidence: Float(confidence),
            relativeHeight: relativeHeight,
            estimatedFontSize: fontCategory,
            isAllCaps: isAllCaps,
            isShortLine: isShortLine,
            columnIndex: columnIndex,
            lineIndex: lineIndex,
            readingOrder: readingOrder
        )
    }

    private func buildHierarchy(
        from elements: [SpatialTextElement],
        pageNumber: Int
    ) -> [DocumentHierarchyElement] {

        // Filter to header candidates (large text, short lines, or all caps)
        let headerCandidates = elements.filter { element in
            element.estimatedFontSize == .title ||
            element.estimatedFontSize == .heading1 ||
            element.estimatedFontSize == .heading2 ||
            (element.isAllCaps && element.isShortLine)
        }

        // Sort by vertical position (top to bottom)
        let sorted = headerCandidates.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        return sorted.map { element in
            let level: Int = {
                switch element.estimatedFontSize {
                case .title: return 0
                case .heading1: return 1
                case .heading2: return 2
                default: return element.isAllCaps ? 2 : 3
                }
            }()

            return DocumentHierarchyElement(
                level: level,
                text: element.text,
                pageNumber: pageNumber,
                startY: element.boundingBox.midY,
                children: []
            )
        }
    }

    // MARK: - Multi-Column Layout Detection

    private func detectColumnLayout(observations: [VNRecognizedTextObservation]) -> SpatialColumnLayout {
        guard observations.count > 5 else {
            return SpatialColumnLayout(
                columnCount: 1,
                columnBoundaries: [],
                columnWidths: [1.0],
                hasVariableWidth: false,
                textFlowPattern: .singleColumn
            )
        }

        // Collect X midpoints
        let xMidpoints = observations.map { $0.boundingBox.midX }

        // Use k-means style clustering to find column centers
        let clusters = clusterXPositions(xMidpoints)

        if clusters.count == 1 {
            return SpatialColumnLayout(
                columnCount: 1,
                columnBoundaries: [],
                columnWidths: [1.0],
                hasVariableWidth: false,
                textFlowPattern: .singleColumn
            )
        }

        // Calculate boundaries between clusters
        let sortedCenters = clusters.sorted()
        var boundaries: [CGFloat] = []
        for i in 0..<(sortedCenters.count - 1) {
            boundaries.append((sortedCenters[i] + sortedCenters[i + 1]) / 2)
        }

        // Calculate column widths
        var widths: [CGFloat] = []
        var prevBoundary: CGFloat = 0
        for boundary in boundaries {
            widths.append(boundary - prevBoundary)
            prevBoundary = boundary
        }
        widths.append(1.0 - prevBoundary)

        // Check for variable width columns
        let avgWidth = widths.reduce(0, +) / CGFloat(widths.count)
        let hasVariableWidth = widths.contains { abs($0 - avgWidth) > 0.1 }

        // Detect wrap-around patterns (gaps in middle of page)
        let flowPattern: SpatialColumnLayout.TextFlowPattern = {
            if clusters.count == 1 { return .singleColumn }
            if hasVariableWidth { return .multiColumnComplex }
            if detectWrapAroundPattern(observations: observations, boundaries: boundaries) {
                return .wrapAroundImage
            }
            return .multiColumnSimple
        }()

        return SpatialColumnLayout(
            columnCount: clusters.count,
            columnBoundaries: boundaries,
            columnWidths: widths,
            hasVariableWidth: hasVariableWidth,
            textFlowPattern: flowPattern
        )
    }

    /// K-means style clustering for X positions
    private func clusterXPositions(_ positions: [CGFloat]) -> [CGFloat] {
        guard !positions.isEmpty else { return [] }

        // Start with assumption of 1-3 columns
        // Find largest gaps in sorted positions
        let sorted = positions.sorted()
        var gaps: [(position: CGFloat, size: CGFloat)] = []

        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            gaps.append((position: (sorted[i] + sorted[i - 1]) / 2, size: gap))
        }

        // Significant gap threshold (15% of page width)
        let threshold: CGFloat = 0.15
        let significantGaps = gaps.filter { $0.size > threshold }.sorted { $0.size > $1.size }

        // Max 2 gaps = 3 columns
        let columnSeparators = Array(significantGaps.prefix(2)).map { $0.position }.sorted()

        if columnSeparators.isEmpty {
            // Single column - return median
            return [calculateMedian(positions)]
        }

        // Calculate cluster centers
        var clusters: [CGFloat] = []
        var prevSep: CGFloat = 0

        for sep in columnSeparators {
            let clusterPoints = positions.filter { $0 >= prevSep && $0 < sep }
            if !clusterPoints.isEmpty {
                clusters.append(clusterPoints.reduce(0, +) / CGFloat(clusterPoints.count))
            }
            prevSep = sep
        }

        // Last cluster
        let lastClusterPoints = positions.filter { $0 >= prevSep }
        if !lastClusterPoints.isEmpty {
            clusters.append(lastClusterPoints.reduce(0, +) / CGFloat(lastClusterPoints.count))
        }

        return clusters
    }

    private func detectWrapAroundPattern(
        observations: [VNRecognizedTextObservation],
        boundaries: [CGFloat]
    ) -> Bool {
        // Look for vertical bands with no text (likely image locations)
        // Check if text flows around these gaps

        guard !boundaries.isEmpty else { return false }

        // Group observations by Y position
        let yBands = Dictionary(grouping: observations) { obs in
            Int(obs.boundingBox.midY * 10)  // 10 horizontal bands
        }

        // Check if some bands skip columns (wrap-around indicator)
        var skippedColumnBands = 0
        for (_, bandObs) in yBands {
            let xPositions = bandObs.map { $0.boundingBox.midX }
            let columns = Set(xPositions.map { determineColumnIndex(x: $0, boundaries: boundaries) })

            if columns.count < boundaries.count + 1 {
                skippedColumnBands += 1
            }
        }

        // If >30% of bands skip columns, likely wrap-around
        return Double(skippedColumnBands) / Double(yBands.count) > 0.3
    }

    private func determineColumnIndex(x: CGFloat, layout: SpatialColumnLayout) -> Int {
        determineColumnIndex(x: x, boundaries: layout.columnBoundaries)
    }

    private func determineColumnIndex(x: CGFloat, boundaries: [CGFloat]) -> Int {
        for (index, boundary) in boundaries.enumerated() {
            if x < boundary { return index }
        }
        return boundaries.count
    }

    // MARK: - Figure Detection

    private func detectFigures(
        elements: [SpatialTextElement],
        pageNumber: Int
    ) -> [DetectedFigure] {
        // Find large rectangular regions with no text
        // These are likely figures, images, or diagrams

        guard elements.count > 10 else { return [] }

        // Create a grid and mark cells with text
        let gridSize = 20
        var grid = Array(repeating: Array(repeating: false, count: gridSize), count: gridSize)

        for element in elements {
            let box = element.boundingBox
            let minX = Int(box.minX * CGFloat(gridSize))
            let maxX = Int(box.maxX * CGFloat(gridSize))
            let minY = Int(box.minY * CGFloat(gridSize))
            let maxY = Int(box.maxY * CGFloat(gridSize))

            for y in max(0, minY)..<min(gridSize, maxY + 1) {
                for x in max(0, minX)..<min(gridSize, maxX + 1) {
                    grid[y][x] = true
                }
            }
        }

        // Find connected empty regions (potential figures)
        var figures: [DetectedFigure] = []
        var visited = Array(repeating: Array(repeating: false, count: gridSize), count: gridSize)
        var figureIndex = 0

        for y in 0..<gridSize {
            for x in 0..<gridSize {
                if !grid[y][x] && !visited[y][x] {
                    // Found empty cell, flood fill to find region
                    let region = floodFillEmpty(grid: grid, visited: &visited, startX: x, startY: y, gridSize: gridSize)

                    // Only consider regions that are at least 10% of page
                    if region.count > gridSize * gridSize / 10 {
                        let bounds = calculateRegionBounds(region: region, gridSize: gridSize)

                        // Look for references to this figure in nearby text
                        let references = findFigureReferences(
                            elements: elements,
                            figureBounds: bounds,
                            figureIndex: figureIndex
                        )

                        figures.append(DetectedFigure(
                            boundingBox: bounds,
                            pageNumber: pageNumber,
                            figureIndex: figureIndex,
                            caption: nil,  // Will be filled by caption association
                            referencedBy: references
                        ))

                        figureIndex += 1
                    }
                }
            }
        }

        return figures
    }

    private func floodFillEmpty(
        grid: [[Bool]],
        visited: inout [[Bool]],
        startX: Int,
        startY: Int,
        gridSize: Int
    ) -> [(x: Int, y: Int)] {
        var result: [(x: Int, y: Int)] = []
        var stack = [(startX, startY)]

        while !stack.isEmpty {
            let (x, y) = stack.removeLast()

            guard x >= 0 && x < gridSize && y >= 0 && y < gridSize else { continue }
            guard !visited[y][x] && !grid[y][x] else { continue }

            visited[y][x] = true
            result.append((x, y))

            // Add neighbors
            stack.append((x + 1, y))
            stack.append((x - 1, y))
            stack.append((x, y + 1))
            stack.append((x, y - 1))
        }

        return result
    }

    private func calculateRegionBounds(region: [(x: Int, y: Int)], gridSize: Int) -> CGRect {
        guard !region.isEmpty else { return .zero }

        guard let minX = region.map({ $0.x }).min(),
              let maxX = region.map({ $0.x }).max(),
              let minY = region.map({ $0.y }).min(),
              let maxY = region.map({ $0.y }).max() else { return .zero }

        let cellSize = 1.0 / CGFloat(gridSize)

        return CGRect(
            x: CGFloat(minX) * cellSize,
            y: CGFloat(minY) * cellSize,
            width: CGFloat(maxX - minX + 1) * cellSize,
            height: CGFloat(maxY - minY + 1) * cellSize
        )
    }

    private func findFigureReferences(
        elements: [SpatialTextElement],
        figureBounds: CGRect,
        figureIndex: Int
    ) -> [String] {
        // Look for text that references figures/images
        let patterns = [
            #"(?i)(?:see\s+)?(?:figure|fig\.?)\s*\d+"#,
            #"(?i)(?:in\s+)?(?:the\s+)?(?:diagram|illustration|image)"#,
            #"(?i)as\s+shown\s+(?:above|below|in)"#
        ]

        var references: [String] = []

        for element in elements {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let _ = regex.firstMatch(in: element.text, range: NSRange(element.text.startIndex..., in: element.text)) {
                    references.append(element.text)
                    break
                }
            }
        }

        return references
    }

    // MARK: - Caption Association

    private func associateCaptions(
        elements: [SpatialTextElement],
        figures: [DetectedFigure]
    ) -> [(caption: String, figureIndex: Int)] {
        var associations: [(caption: String, figureIndex: Int)] = []

        // Caption patterns
        let captionPatterns = [
            #"^(?:Figure|Fig\.?|Image|Diagram|Illustration)\s*\d*\s*[:\-.]?\s*"#,
            #"^(?:Photo|Picture|Chart|Graph|Table)\s*\d*\s*[:\-.]?\s*"#
        ]

        for element in elements {
            // Check if this looks like a caption
            var isCaption = false
            var cleanedCaption = element.text

            for pattern in captionPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: element.text, range: NSRange(element.text.startIndex..., in: element.text)) {
                    isCaption = true
                    // Remove the "Figure X:" prefix for cleaner caption
                    if let range = Range(match.range, in: element.text) {
                        cleanedCaption = String(element.text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    }
                    break
                }
            }

            // Also consider small text near figures
            if !isCaption && element.estimatedFontSize == .small {
                isCaption = true
            }

            if isCaption {
                // Find closest figure
                var closestFigure: Int?
                var closestDistance = CGFloat.greatestFiniteMagnitude

                for figure in figures {
                    // Calculate distance (prefer figures directly above)
                    let distance = distanceBetween(
                        textBox: element.boundingBox,
                        figureBox: figure.boundingBox
                    )

                    // Captions are typically below figures (lower Y in Vision coords)
                    let isBelow = element.boundingBox.midY < figure.boundingBox.minY
                    let adjustedDistance = isBelow ? distance : distance * 2  // Penalize above

                    if adjustedDistance < closestDistance && distance < 0.1 {  // Within 10% of page
                        closestDistance = adjustedDistance
                        closestFigure = figure.figureIndex
                    }
                }

                if let figureIndex = closestFigure {
                    associations.append((caption: cleanedCaption, figureIndex: figureIndex))
                }
            }
        }

        return associations
    }

    private func distanceBetween(textBox: CGRect, figureBox: CGRect) -> CGFloat {
        // Calculate minimum distance between rectangles
        let dx = max(0, max(textBox.minX - figureBox.maxX, figureBox.minX - textBox.maxX))
        let dy = max(0, max(textBox.minY - figureBox.maxY, figureBox.minY - textBox.maxY))
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Table Cell Alignment Detection

    /// Analyze table cells for text alignment
    func analyzeTableAlignment(cells: [[String]], cellBounds: [[CGRect]]) -> [[AlignedTableCell]] {
        guard !cells.isEmpty && cells.count == cellBounds.count else { return [] }

        var result: [[AlignedTableCell]] = []

        for (rowIndex, row) in cells.enumerated() {
            var alignedRow: [AlignedTableCell] = []

            for (colIndex, text) in row.enumerated() {
                guard colIndex < cellBounds[rowIndex].count else { continue }

                let cellBox = cellBounds[rowIndex][colIndex]
                let alignment = detectAlignment(text: text, cellBox: cellBox)
                let isHeader = rowIndex == 0 || isHeaderCell(text: text)

                alignedRow.append(AlignedTableCell(
                    text: text,
                    row: rowIndex,
                    column: colIndex,
                    alignment: alignment,
                    isHeader: isHeader
                ))
            }

            result.append(alignedRow)
        }

        return result
    }

    private func detectAlignment(text: String, cellBox: CGRect) -> AlignedTableCell.TextAlignment {
        // Heuristic: numeric values are often right-aligned
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Check if primarily numeric
        let numericChars = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "$" || $0 == "%" }
        let isNumeric = Double(numericChars.count) / Double(max(1, trimmed.count)) > 0.5

        if isNumeric {
            return .right
        }

        // Short centered text (like headers)
        if trimmed.count < 20 {
            return .center
        }

        return .left
    }

    private func isHeaderCell(text: String) -> Bool {
        let headerKeywords = ["name", "type", "description", "value", "quantity", "date", "total", "item", "specification", "category"]
        let lowered = text.lowercased()
        return headerKeywords.contains { lowered.contains($0) }
    }

    // MARK: - Utilities

    private func calculateMedian(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

// MARK: - Integration with Document Processor

extension SpatialDocumentAnalyzer {

    /// Generate enriched text from spatial analysis
    /// Includes hierarchy markers, column separators, and figure captions
    func generateEnrichedText(from analysis: SpatialPageAnalysis) -> String {
        var lines: [String] = []

        // Add hierarchical headers
        for header in analysis.hierarchy {
            lines.append(header.markdown)
        }

        lines.append("")  // Separator

        // Group elements by column
        var columnGroups: [[SpatialTextElement]] = Array(repeating: [], count: max(1, analysis.layout.columnCount))

        for element in analysis.elements {
            guard element.estimatedFontSize == .body || element.estimatedFontSize == .small else { continue }
            let colIndex = min(element.columnIndex, columnGroups.count - 1)
            columnGroups[colIndex].append(element)
        }

        // Process each column
        for (colIndex, column) in columnGroups.enumerated() {
            if colIndex > 0 && !column.isEmpty {
                lines.append("\n[Column \(colIndex + 1)]")
            }

            // Sort by line index (top to bottom)
            let sorted = column.sorted { $0.lineIndex < $1.lineIndex }

            for element in sorted {
                lines.append(element.text)
            }
        }

        // Add figure information
        if !analysis.figures.isEmpty {
            lines.append("\n[Visual Content]")
            for figure in analysis.figures {
                if let caption = analysis.captionAssociations.first(where: { $0.figureIndex == figure.figureIndex })?.caption {
                    lines.append("• Figure \(figure.figureIndex + 1): \(caption)")
                } else {
                    lines.append("• Figure \(figure.figureIndex + 1): [No caption detected]")
                }

                if !figure.referencedBy.isEmpty {
                    lines.append("  Referenced: \(figure.referencedBy.first ?? "")")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
