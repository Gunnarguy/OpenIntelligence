//
//  PageComplexityAnalyzer.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  ADAPTIVE PAGE COMPLEXITY DETECTION - THE HEART OF INTELLIGENT OCR
//  ═══════════════════════════════════════════════════════════════════════════
//
//  This is the MOST CRITICAL component of the ingestion pipeline.
//  It must accurately classify EVERY page's complexity to route it to the
//  correct processing path. A misclassification wastes time (OCR on simple text)
//  or loses data (skipping OCR on complex pages with embedded images).
//
//  DETECTION TARGETS:
//  ──────────────────
//  • Images (photos, diagrams, illustrations, logos, watermarks)
//  • Figures (scientific figures, medical imaging, screenshots)
//  • Charts (bar, line, pie, scatter, area, radar)
//  • Graphs (mathematical functions, network graphs, flow charts)
//  • Tables (data tables, comparison tables, pricing grids)
//  • Markdown-style formatting (code blocks, bullet lists, headers)
//  • Multi-column layouts (newspapers, academic papers, magazines)
//  • Scanned documents (no native text layer, uniform noise)
//  • Mixed content (text + images interleaved)
//  • Forms (input fields, checkboxes, signatures)
//
//  DETECTION METHODS:
//  ──────────────────
//  1. PDF Structure Analysis - Embedded images, annotations, XObjects
//  2. Vision Rectangle Detection - Fast shape detection for tables/charts
//  3. Vision Contour Detection - Complex shapes indicating diagrams
//  4. Text Distribution Analysis - Clustering, whitespace patterns
//  5. Numeric Density Analysis - Tables/charts have high number ratios
//  6. Pattern Recognition - Table delimiters, list markers, headers
//  7. Aspect Ratio Analysis - Wide images, tall charts, square diagrams
//  8. Color Complexity - Grayscale vs color, gradient presence
//
//  PERFORMANCE TARGET: <15ms per page analysis
//  ACCURACY TARGET: >95% correct classification
//

import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics

// MARK: - Page Complexity Classification

/// Complexity level determines OCR strategy - this MUST be accurate
enum PageComplexity: Int, Comparable, Sendable {
    case trivial = 0    // Pure text, clean formatting - skip OCR entirely
    case simple = 1     // Mostly text, minor formatting - fast text extraction
    case moderate = 2   // Some visual elements - basic OCR sufficient
    case complex = 3    // Heavy graphics, tables, multi-column - enhanced OCR
    case visual = 4     // Image-heavy, charts, diagrams - full Vision analysis
    case scanned = 5    // No text layer, must OCR everything from scratch

    static func < (lhs: PageComplexity, rhs: PageComplexity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .trivial: return "trivial (direct text)"
        case .simple: return "simple (spatial text)"
        case .moderate: return "moderate (basic OCR)"
        case .complex: return "complex (enhanced OCR)"
        case .visual: return "visual (full Vision)"
        case .scanned: return "scanned (maximum OCR)"
        }
    }

    /// Whether this page needs Vision OCR at all
    var requiresVisionOCR: Bool {
        switch self {
        case .trivial, .simple: return false
        case .moderate, .complex, .visual, .scanned: return true
        }
    }

    /// Whether to use enhanced spatial OCR vs basic OCR
    var useEnhancedOCR: Bool {
        switch self {
        case .trivial, .simple, .moderate: return false
        case .complex, .visual, .scanned: return true
        }
    }

    /// Whether to run additional Vision analysis (object detection, etc.)
    var useFullVisionAnalysis: Bool {
        switch self {
        case .trivial, .simple, .moderate, .complex: return false
        case .visual, .scanned: return true
        }
    }
}

/// Comprehensive complexity analysis for a single page
struct PageComplexityAnalysis: Sendable {
    let pageNumber: Int
    let complexity: PageComplexity

    // ═══════════════════════════════════════════════════════════════════════
    // DETECTION SIGNALS (0.0-1.0 normalized confidence)
    // ═══════════════════════════════════════════════════════════════════════

    // Text Analysis
    let textCoverage: Double            // Text area / total page area
    let textQuality: Double             // 0=garbled, 1=perfect readable text
    let fineTextRisk: Double            // 0=normal text, 1=ultra-fine text needing extra DPI
    let hasNativeTextLayer: Bool        // PDF has extractable text

    // Visual Element Detection
    let imagePresence: Double           // Embedded images, photos, diagrams
    let figurePresence: Double          // Scientific figures, labeled diagrams
    let chartPresence: Double           // Bar, line, pie charts
    let tablePresence: Double           // Data tables, grids
    let formPresence: Double            // Input fields, checkboxes

    // Layout Complexity
    let columnCount: Int                // Detected text columns (1-4+)
    let layoutComplexity: Double        // Non-linear text flow
    let whitespaceRatio: Double         // Empty space indicating visual elements

    // Content Patterns
    let numericDensity: Double          // High = likely tables/charts
    let listPatternStrength: Double     // Bullet points, numbered lists
    let headerPatternStrength: Double   // Section headers, titles
    let codeBlockPresence: Double       // Monospace/code formatting

    // PDF-Specific
    let embeddedObjectCount: Int        // XObjects, embedded streams
    let annotationComplexity: Double    // Links, highlights, comments

    // Timing
    let analysisTimeMs: Double

    var summary: String {
        let signals = [
            textCoverage > 0.5 ? "text:\(Int(textCoverage*100))%" : nil,
            fineTextRisk > 0.45 ? "fine:\(Int(fineTextRisk*100))%" : nil,
            imagePresence > 0.2 ? "img:\(Int(imagePresence*100))%" : nil,
            tablePresence > 0.2 ? "tbl:\(Int(tablePresence*100))%" : nil,
            chartPresence > 0.2 ? "chart:\(Int(chartPresence*100))%" : nil,
            columnCount > 1 ? "cols:\(columnCount)" : nil,
        ].compactMap { $0 }.joined(separator: ", ")

        return "Page \(pageNumber): \(complexity.description) [\(signals)] (\(String(format: "%.1f", analysisTimeMs))ms)"
    }
}

// MARK: - Page Complexity Analyzer

/// The brain of adaptive OCR - must accurately classify every page type
/// Uses multiple detection methods for maximum accuracy
final class PageComplexityAnalyzer: @unchecked Sendable {

    /// Shared instance for document processing
    static let shared = PageComplexityAnalyzer()

    /// GPU context for fast image analysis
    private let ciContext: CIContext

    /// Metal device for GPU-accelerated analysis
    private let metalDevice: MTLDevice?

    /// Serial queue for GPU operations
    private let gpuQueue = DispatchQueue(label: "com.openintelligence.complexity-gpu", qos: .userInitiated)

    private init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        if let device = metalDevice {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: true])
        }
    }

    // MARK: - Main Analysis Entry Point

    /// Comprehensively analyze a PDF page to determine its complexity
    /// Uses multiple detection methods for maximum accuracy
    /// Target: <15ms per page, >95% accuracy
    ///
    /// - Parameters:
    ///   - page: The PDF page to analyze
    ///   - pageNumber: 1-based page number for logging
    ///   - pageImage: Optional pre-rendered image (reuses if available)
    /// - Returns: Comprehensive complexity analysis
    func analyze(page: PDFPage, pageNumber: Int, pageImage: CIImage? = nil) async -> PageComplexityAnalysis {
        let startTime = Date()

        // Get page dimensions
        let bounds = page.bounds(for: .mediaBox)
        let pageArea = bounds.width * bounds.height

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 1: Native Text Layer Analysis (instant, ~0.5ms)
        // ═══════════════════════════════════════════════════════════════════
        let pageString = page.string
        let hasNativeTextLayer = pageString != nil && !pageString!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let textLength = pageString?.count ?? 0

        var textCoverage = 0.0
        var textQuality = 0.0
        var fineTextRisk = 0.0
        var columnCount = 1
        var numericDensity = 0.0
        var listPatternStrength = 0.0
        var headerPatternStrength = 0.0
        var codeBlockPresence = 0.0

        if hasNativeTextLayer, let text = pageString {
            // Estimate text coverage
            let expectedChars = Double(pageArea) / 140.0  // ~140 sq pts per char at 12pt
            textCoverage = min(1.0, Double(textLength) / max(1, expectedChars))

            // Analyze text quality
            textQuality = analyzeTextQuality(text)

            // Detect columns
            columnCount = detectColumnCount(text, pageWidth: bounds.width)

            // Estimate whether the page is densely packed with tiny text
            fineTextRisk = analyzeFineTextRisk(text, pageBounds: bounds, columnCount: columnCount)

            // Analyze content patterns
            let patterns = analyzeTextPatterns(text)
            numericDensity = patterns.numericDensity
            listPatternStrength = patterns.listStrength
            headerPatternStrength = patterns.headerStrength
            codeBlockPresence = patterns.codeBlockStrength
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 2: PDF Structure Analysis (fast, ~1-2ms)
        // ═══════════════════════════════════════════════════════════════════
        let pdfAnalysis = analyzePDFStructure(page)
        let embeddedObjectCount = pdfAnalysis.objectCount
        let annotationComplexity = pdfAnalysis.annotationComplexity
        var imagePresence = pdfAnalysis.imageSignals
        var figurePresence = pdfAnalysis.figureSignals
        let formPresence = pdfAnalysis.formSignals

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 3: Text Pattern Analysis for Tables/Charts (~1ms)
        // ═══════════════════════════════════════════════════════════════════
        var tablePresence = 0.0
        var chartPresence = 0.0
        var whitespaceRatio = 0.0
        var layoutComplexity = 0.0

        if hasNativeTextLayer, let text = pageString {
            let visualPatterns = analyzeVisualPatterns(text, pageArea: pageArea)
            tablePresence = visualPatterns.tableSignature
            chartPresence = visualPatterns.chartSignature
            whitespaceRatio = visualPatterns.whitespaceRatio
            layoutComplexity = visualPatterns.layoutComplexity
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 4: Vision-Based Detection (if image available, ~5-8ms)
        // Only run if we have ambiguous signals or suspect visual content
        // IMPORTANT: Don't trigger Vision just for whitespace (columns have gutters)
        // or just for multi-column layouts (PDFKit handles those fine)
        // ═══════════════════════════════════════════════════════════════════
        let hasStrongVisualSignal = imagePresence > 0.2 || chartPresence > 0.2
        let hasSuspiciousTable = tablePresence > 0.3
        let hasNoText = !hasNativeTextLayer
        let hasLowTextCoverage = textCoverage < 0.2  // Very low, suggests images

        // Only run Vision if there's a STRONG reason - it's expensive!
        let needsVisionAnalysis = hasStrongVisualSignal || hasSuspiciousTable || hasNoText || hasLowTextCoverage

        if needsVisionAnalysis, let image = pageImage ?? renderPageForAnalysis(page) {
            let visionResults = await analyzeWithVision(image)

            // Merge Vision results with heuristic signals (Vision takes precedence)
            imagePresence = max(imagePresence, visionResults.imageConfidence)
            tablePresence = max(tablePresence, visionResults.tableConfidence)
            chartPresence = max(chartPresence, visionResults.chartConfidence)
            figurePresence = max(figurePresence, visionResults.figureConfidence)
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 5: Final Complexity Calculation
        // ═══════════════════════════════════════════════════════════════════
        let complexity = calculateFinalComplexity(
            hasNativeTextLayer: hasNativeTextLayer,
            textCoverage: textCoverage,
            textQuality: textQuality,
            imagePresence: imagePresence,
            figurePresence: figurePresence,
            chartPresence: chartPresence,
            tablePresence: tablePresence,
            formPresence: formPresence,
            columnCount: columnCount,
            layoutComplexity: layoutComplexity,
            whitespaceRatio: whitespaceRatio,
            numericDensity: numericDensity,
            embeddedObjectCount: embeddedObjectCount
        )

        let analysisTime = Date().timeIntervalSince(startTime) * 1000

        return PageComplexityAnalysis(
            pageNumber: pageNumber,
            complexity: complexity,
            textCoverage: textCoverage,
            textQuality: textQuality,
            fineTextRisk: fineTextRisk,
            hasNativeTextLayer: hasNativeTextLayer,
            imagePresence: imagePresence,
            figurePresence: figurePresence,
            chartPresence: chartPresence,
            tablePresence: tablePresence,
            formPresence: formPresence,
            columnCount: columnCount,
            layoutComplexity: layoutComplexity,
            whitespaceRatio: whitespaceRatio,
            numericDensity: numericDensity,
            listPatternStrength: listPatternStrength,
            headerPatternStrength: headerPatternStrength,
            codeBlockPresence: codeBlockPresence,
            embeddedObjectCount: embeddedObjectCount,
            annotationComplexity: annotationComplexity,
            analysisTimeMs: analysisTime
        )
    }

    /// Batch analyze multiple pages concurrently
    func analyzeBatch(pages: [(PDFPage, Int)]) async -> [PageComplexityAnalysis] {
        await withTaskGroup(of: (Int, PageComplexityAnalysis).self) { group in
            for (page, pageNumber) in pages {
                group.addTask {
                    let analysis = await self.analyze(page: page, pageNumber: pageNumber)
                    return (pageNumber, analysis)
                }
            }

            var results: [(Int, PageComplexityAnalysis)] = []
            for await result in group {
                results.append(result)
            }

            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Text Quality Analysis

    /// Analyze if extracted text is readable vs garbled/corrupted
    private func analyzeTextQuality(_ text: String) -> Double {
        guard text.count > 20 else { return text.isEmpty ? 0.0 : 0.8 }

        let sample = String(text.prefix(1000))
        var qualityScore = 1.0

        // Check ASCII ratio (garbled text has lots of non-printable chars)
        let printableCount = sample.filter { $0.isPrintableASCII || $0.isWhitespace || $0.isNewline }.count
        let printableRatio = Double(printableCount) / Double(sample.count)
        if printableRatio < 0.85 {
            qualityScore -= (0.85 - printableRatio) * 2  // Penalize heavily
        }

        // Check word-like patterns
        let words = sample.split(whereSeparator: { !$0.isLetter })
        if !words.isEmpty {
            let avgWordLength = Double(words.map { $0.count }.reduce(0, +)) / Double(words.count)
            // Normal words are 2-15 chars
            if avgWordLength < 2 || avgWordLength > 15 {
                qualityScore -= 0.3
            }
        }

        // Check for excessive punctuation (OCR artifacts)
        let punctCount = sample.filter { $0.isPunctuation && $0 != "." && $0 != "," }.count
        let punctRatio = Double(punctCount) / Double(sample.count)
        if punctRatio > 0.15 {
            qualityScore -= (punctRatio - 0.15) * 3
        }

        // Check for repeated characters (encoding issues)
        let repeatedPattern = sample.contains("....") || sample.contains("____") ||
                              sample.contains("####") || sample.contains("****")
        if repeatedPattern {
            qualityScore -= 0.2
        }

        return max(0, min(1, qualityScore))
    }

    /// Estimate whether a page contains unusually small text that benefits from
    /// a higher OCR render scale. This is intentionally cheap and uses only the
    /// native text layer geometry proxy: line density and character density.
    private func analyzeFineTextRisk(_ text: String, pageBounds: CGRect, columnCount: Int) -> Double {
        let nonEmptyLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard nonEmptyLines.count >= 20 else { return 0.0 }

        let columns = max(1, columnCount)
        let effectiveLineCount = Double(nonEmptyLines.count) / Double(columns)
        let estimatedLineHeight = Double(pageBounds.height) / max(effectiveLineCount, 1)

        let characterCount = nonEmptyLines.reduce(0) { $0 + $1.count }
        let pageAreaSquareInches = Double(pageBounds.width * pageBounds.height) / (72.0 * 72.0)
        let charactersPerSquareInch = Double(characterCount) / max(pageAreaSquareInches, 1.0)
        let averageCharactersPerLine = Double(characterCount) / Double(max(nonEmptyLines.count, 1))

        let lineHeightRisk: Double = {
            guard estimatedLineHeight < 11 else { return 0.0 }
            return min(1.0, (11.0 - estimatedLineHeight) / 4.0)
        }()

        let densityRisk: Double = {
            guard charactersPerSquareInch > 55 else { return 0.0 }
            return min(1.0, (charactersPerSquareInch - 55.0) / 25.0)
        }()

        let lineLengthRisk: Double = {
            guard averageCharactersPerLine > 95 else { return 0.0 }
            return min(0.25, (averageCharactersPerLine - 95.0) / 80.0)
        }()

        return min(1.0, lineHeightRisk * 0.55 + densityRisk * 0.35 + lineLengthRisk)
    }

    // MARK: - Column Detection

    /// Detect number of text columns from line patterns
    private func detectColumnCount(_ text: String, pageWidth: CGFloat) -> Int {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 15 else { return 1 }

        // Analyze line length distribution
        let lineLengths = lines.map { $0.count }
        let avgLength = Double(lineLengths.reduce(0, +)) / Double(lineLengths.count)

        // Multi-column layouts have many lines significantly shorter than max
        var shortLineCount = 0
        for length in lineLengths {
            if Double(length) < avgLength * 0.6 && length > 15 {
                shortLineCount += 1
            }
        }

        let shortLineRatio = Double(shortLineCount) / Double(lines.count)

        // Also check for mid-line breaks (columns often have consistent break points)
        var midBreakCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Look for large gaps (2+ spaces) mid-line
            if trimmed.contains("  ") || trimmed.contains("\t\t") {
                midBreakCount += 1
            }
        }
        let midBreakRatio = Double(midBreakCount) / Double(lines.count)

        // Determine column count
        if shortLineRatio > 0.5 && midBreakRatio > 0.3 {
            return 3  // Strong multi-column signal
        } else if shortLineRatio > 0.3 || midBreakRatio > 0.2 {
            return 2  // Likely 2 columns
        }

        return 1
    }

    // MARK: - Text Pattern Analysis

    private struct TextPatterns {
        let numericDensity: Double
        let listStrength: Double
        let headerStrength: Double
        let codeBlockStrength: Double
    }

    /// Analyze text for common document patterns
    private func analyzeTextPatterns(_ text: String) -> TextPatterns {
        let sample = String(text.prefix(3000))

        // Numeric density (tables/charts are number-heavy)
        let digits = sample.filter { $0.isNumber }.count
        let numericDensity = min(1.0, Double(digits) / Double(sample.count) * 5)

        // List patterns (bullets, numbers, dashes)
        let lines = sample.components(separatedBy: .newlines)
        var listLines = 0
        var headerLines = 0
        var codeLines = 0

        let listPatterns = ["• ", "- ", "* ", "· ", "○ ", "► ", "▪ "]
        let numberedPattern = try? NSRegularExpression(pattern: "^\\s*\\d+[\\.\\)\\:]\\s", options: [])
        let headerPattern = try? NSRegularExpression(pattern: "^[A-Z][A-Z\\s]{3,}$|^#{1,6}\\s|^\\*\\*.*\\*\\*$", options: [])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check list patterns
            if listPatterns.contains(where: { trimmed.hasPrefix($0) }) ||
               (numberedPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil) {
                listLines += 1
            }

            // Check header patterns
            if headerPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                headerLines += 1
            }

            // Check code patterns (consistent indentation, special chars)
            if trimmed.hasPrefix("    ") || trimmed.hasPrefix("\t") ||
               trimmed.contains("```") || trimmed.contains("def ") ||
               trimmed.contains("func ") || trimmed.contains("class ") {
                codeLines += 1
            }
        }

        let totalLines = max(1, lines.count)

        return TextPatterns(
            numericDensity: numericDensity,
            listStrength: min(1.0, Double(listLines) / Double(totalLines) * 3),
            headerStrength: min(1.0, Double(headerLines) / Double(totalLines) * 10),
            codeBlockStrength: min(1.0, Double(codeLines) / Double(totalLines) * 5)
        )
    }

    // MARK: - PDF Structure Analysis

    private struct PDFStructureAnalysis {
        let objectCount: Int
        let annotationComplexity: Double
        let imageSignals: Double
        let figureSignals: Double
        let formSignals: Double
    }

    /// Analyze PDF page structure for embedded objects
    private func analyzePDFStructure(_ page: PDFPage) -> PDFStructureAnalysis {
        var objectCount = 0
        var imageSignals = 0.0
        var figureSignals = 0.0
        var formSignals = 0.0
        var annotationComplexity = 0.0

        // Analyze annotations
        let annotations = page.annotations
        var linkCount = 0
        var widgetCount = 0
        var otherCount = 0

        for annotation in annotations {
            let type = annotation.type ?? ""
            switch type {
            case "Link":
                linkCount += 1
            case "Widget":
                widgetCount += 1
                formSignals += 0.2  // Form field detected
            case "Stamp", "FileAttachment":
                imageSignals += 0.3  // Likely embedded image
                objectCount += 1
            case "Ink", "Line", "Square", "Circle", "Polygon", "PolyLine":
                figureSignals += 0.2  // Drawing annotations
                objectCount += 1
            default:
                otherCount += 1
            }
        }

        // Widget annotations indicate forms
        if widgetCount > 3 {
            formSignals = min(1.0, Double(widgetCount) / 10.0)
        }

        // Many annotations suggest complex page
        annotationComplexity = min(1.0, Double(annotations.count) / 20.0)

        // Check page dictionary for image XObjects (if accessible)
        // This is a heuristic based on page content size
        if let pageRef = page.pageRef {
            // Larger page data often indicates embedded images
            // This is approximate but fast
            let dataSizeHint = pageRef.getBoxRect(.mediaBox)
            if dataSizeHint.width * dataSizeHint.height > 400000 {
                // Large page often has images
                imageSignals += 0.1
            }
        }

        return PDFStructureAnalysis(
            objectCount: objectCount,
            annotationComplexity: annotationComplexity,
            imageSignals: imageSignals,
            figureSignals: figureSignals,
            formSignals: formSignals
        )
    }

    // MARK: - Visual Pattern Analysis (from text)

    private struct VisualPatternAnalysis {
        let tableSignature: Double
        let chartSignature: Double
        let whitespaceRatio: Double
        let layoutComplexity: Double
    }

    /// Analyze text patterns that indicate visual elements
    private func analyzeVisualPatterns(_ text: String, pageArea: CGFloat) -> VisualPatternAnalysis {
        var tableSignature = 0.0
        var chartSignature = 0.0
        var layoutComplexity = 0.0

        // ═══════════════════════════════════════════════════════════════════
        // TABLE DETECTION
        // ═══════════════════════════════════════════════════════════════════

        // Pipe delimiters (markdown tables, ASCII tables)
        let pipeCount = text.filter { $0 == "|" }.count
        if pipeCount > 10 {
            tableSignature += min(0.5, Double(pipeCount) / 50.0)
        }

        // Tab characters (TSV-like structure)
        let tabCount = text.filter { $0 == "\t" }.count
        if tabCount > 20 {
            tableSignature += min(0.3, Double(tabCount) / 100.0)
        }

        // Horizontal rules (table separators)
        let dashSequences = text.components(separatedBy: "---").count - 1
        let equalSequences = text.components(separatedBy: "===").count - 1
        if dashSequences > 2 || equalSequences > 1 {
            tableSignature += 0.3
        }

        // Aligned numeric columns (detect repeated spacing with numbers)
        let lines = text.components(separatedBy: .newlines)
        var alignedNumericLines = 0
        for line in lines {
            // Lines with multiple number groups separated by spaces
            let numberGroups = line.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "," && $0 != "-" })
                                   .filter { $0.count > 0 && $0.first?.isNumber == true }
            if numberGroups.count >= 3 {
                alignedNumericLines += 1
            }
        }
        if alignedNumericLines > 5 {
            tableSignature += min(0.4, Double(alignedNumericLines) / 20.0)
        }

        // ═══════════════════════════════════════════════════════════════════
        // CHART/GRAPH DETECTION
        // ═══════════════════════════════════════════════════════════════════

        // Axis labels (common in charts)
        let axisPatterns = ["x-axis", "y-axis", "X-Axis", "Y-Axis", "xlabel", "ylabel"]
        for pattern in axisPatterns {
            if text.contains(pattern) {
                chartSignature += 0.3
                break
            }
        }

        // Legend indicators
        if text.contains("Legend") || text.contains("legend:") || text.contains("■") || text.contains("●") {
            chartSignature += 0.2
        }

        // Percentage labels (pie charts)
        let percentPattern = try? NSRegularExpression(pattern: "\\d+\\.?\\d*\\s*%", options: [])
        let percentMatches = percentPattern?.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? 0
        if percentMatches > 5 {
            chartSignature += min(0.3, Double(percentMatches) / 20.0)
        }

        // ═══════════════════════════════════════════════════════════════════
        // WHITESPACE & LAYOUT ANALYSIS
        // ═══════════════════════════════════════════════════════════════════

        // Calculate whitespace ratio
        let whitespaceCount = text.filter { $0.isWhitespace }.count
        let whitespaceRatio = Double(whitespaceCount) / Double(max(1, text.count))

        // High whitespace with low text coverage = likely images/figures
        if whitespaceRatio > 0.5 {
            layoutComplexity += 0.3
        }

        // Very short lines mixed with long lines = complex layout
        let lineLengths = lines.map { $0.count }
        if !lineLengths.isEmpty {
            let avgLength = lineLengths.reduce(0, +) / lineLengths.count
            var varianceSum = 0.0
            for length in lineLengths {
                varianceSum += pow(Double(length - avgLength), 2)
            }
            let variance = varianceSum / Double(lineLengths.count)
            let stdDev = sqrt(variance)

            // High variance = complex layout
            if stdDev > Double(avgLength) * 0.5 {
                layoutComplexity += 0.3
            }
        }

        return VisualPatternAnalysis(
            tableSignature: min(1.0, tableSignature),
            chartSignature: min(1.0, chartSignature),
            whitespaceRatio: whitespaceRatio,
            layoutComplexity: min(1.0, layoutComplexity)
        )
    }

    // MARK: - Vision-Based Analysis

    private struct VisionAnalysisResults {
        let imageConfidence: Double
        let tableConfidence: Double
        let chartConfidence: Double
        let figureConfidence: Double
    }

    /// Use Vision framework for fast visual element detection
    private func analyzeWithVision(_ image: CIImage) async -> VisionAnalysisResults {
        var imageConfidence = 0.0
        var tableConfidence = 0.0
        var chartConfidence = 0.0
        var figureConfidence = 0.0

        // Convert CIImage to CGImage for Vision (CIContext is thread-safe)
        let cgImage = ciContext.createCGImage(image, from: image.extent)

        guard let cgImg = cgImage else {
            return VisionAnalysisResults(imageConfidence: 0, tableConfidence: 0, chartConfidence: 0, figureConfidence: 0)
        }

        // ═══════════════════════════════════════════════════════════════════
        // RECTANGLE DETECTION (Tables, Charts, Images)
        // ═══════════════════════════════════════════════════════════════════
        let rectangles = await detectRectangles(cgImg)

        // Many aligned rectangles = table
        if rectangles.count > 10 {
            // Check if rectangles are grid-aligned
            let xPositions = rectangles.map { $0.origin.x }
            let yPositions = rectangles.map { $0.origin.y }

            // Count how many share similar x or y positions
            var alignedX = 0
            var alignedY = 0
            let tolerance: CGFloat = 0.02  // 2% tolerance

            for i in 0..<min(20, rectangles.count) {
                for j in (i+1)..<min(20, rectangles.count) {
                    if abs(xPositions[i] - xPositions[j]) < tolerance {
                        alignedX += 1
                    }
                    if abs(yPositions[i] - yPositions[j]) < tolerance {
                        alignedY += 1
                    }
                }
            }

            if alignedX > 5 && alignedY > 5 {
                tableConfidence = 0.8  // Strong table signal
            } else if alignedX > 3 || alignedY > 3 {
                tableConfidence = 0.5
            }
        }

        // Large rectangles = images or figures
        let pageArea = image.extent.width * image.extent.height
        for rect in rectangles {
            let rectArea = rect.width * rect.height * pageArea
            let areaRatio = rectArea / pageArea

            if areaRatio > 0.1 && areaRatio < 0.8 {
                // Significant non-full-page rectangle = likely image/figure
                imageConfidence = max(imageConfidence, min(1.0, areaRatio * 3))
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // TEXT BOUNDING BOX ANALYSIS
        // ═══════════════════════════════════════════════════════════════════
        let textRegions = await detectTextRegions(cgImg)

        // Analyze text region distribution
        if textRegions.count > 0 {
            // Calculate coverage
            var totalTextArea: CGFloat = 0
            for region in textRegions {
                totalTextArea += region.width * region.height
            }
            let textAreaRatio = totalTextArea / 1.0  // Normalized coordinates

            // Low text coverage with rectangles = figures/charts
            if textAreaRatio < 0.3 && rectangles.count > 3 {
                figureConfidence = max(figureConfidence, 0.6)
            }

            // Scattered small text regions = charts with labels
            if textRegions.count > 10 {
                let avgRegionSize = totalTextArea / CGFloat(textRegions.count)
                if avgRegionSize < 0.02 {  // Small scattered labels
                    chartConfidence = max(chartConfidence, 0.5)
                }
            }
        }

        return VisionAnalysisResults(
            imageConfidence: imageConfidence,
            tableConfidence: tableConfidence,
            chartConfidence: chartConfidence,
            figureConfidence: figureConfidence
        )
    }

    /// Fast rectangle detection using Vision
    private func detectRectangles(_ image: CGImage) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let rects = observations.map { $0.boundingBox }
                continuation.resume(returning: rects)
            }

            request.minimumAspectRatio = 0.1
            request.maximumAspectRatio = 10.0
            request.minimumSize = 0.02  // At least 2% of image
            request.maximumObservations = 50  // Limit for speed
            request.quadratureTolerance = 30  // Allow some skew

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Fast text region detection using Vision
    private func detectTextRegions(_ image: CGImage) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            let request = VNDetectTextRectanglesRequest { request, error in
                guard let observations = request.results as? [VNTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let rects = observations.map { $0.boundingBox }
                continuation.resume(returning: rects)
            }

            request.reportCharacterBoxes = false  // Faster without character-level

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Page Rendering for Analysis

    /// Render page at moderate resolution for reliable visual pattern analysis.
    /// 144 DPI (2×) provides enough detail to detect table grid lines, chart axes,
    /// and figure boundaries while keeping analysis fast. The previous 72 DPI (1×)
    /// missed fine table structures, causing table pages to be classified as "simple"
    /// and skip Vision OCR — the #1 cause of wrong numeric data in RAG answers.
    private func renderPageForAnalysis(_ page: PDFPage) -> CIImage? {
        let bounds = page.bounds(for: .mediaBox)

        // Render at 144 DPI (2x) for reliable pattern detection
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)

        page.draw(with: .mediaBox, to: context)

        guard let uiImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = uiImage.cgImage else { return nil }

        return CIImage(cgImage: cgImage)
        #else
        return nil
        #endif
    }

    // MARK: - Final Complexity Calculation

    /// Calculate final complexity from all signals
    /// This is the CRITICAL decision point - must be accurate
    private func calculateFinalComplexity(
        hasNativeTextLayer: Bool,
        textCoverage: Double,
        textQuality: Double,
        imagePresence: Double,
        figurePresence: Double,
        chartPresence: Double,
        tablePresence: Double,
        formPresence: Double,
        columnCount: Int,
        layoutComplexity: Double,
        whitespaceRatio: Double,
        numericDensity: Double,
        embeddedObjectCount: Int
    ) -> PageComplexity {

        // ═══════════════════════════════════════════════════════════════════
        // RULE 1: No native text = must be scanned
        // ═══════════════════════════════════════════════════════════════════
        if !hasNativeTextLayer {
            return .scanned
        }

        // ═══════════════════════════════════════════════════════════════════
        // RULE 2: Poor text quality = treat as scanned
        // ═══════════════════════════════════════════════════════════════════
        if textQuality < 0.4 {
            return .scanned
        }

        // ═══════════════════════════════════════════════════════════════════
        // RULE 3: Strong visual element signals = visual complexity
        // ═══════════════════════════════════════════════════════════════════
        let maxVisualSignal = max(imagePresence, figurePresence, chartPresence)
        if maxVisualSignal > 0.7 {
            return .visual
        }

        // ═══════════════════════════════════════════════════════════════════
        // RULE 4: Calculate weighted complexity score
        // ═══════════════════════════════════════════════════════════════════
        var score = 0.0

        // Visual elements (highest weight)
        score += imagePresence * 4.0
        score += figurePresence * 3.5
        score += chartPresence * 3.0

        // Tables need careful handling
        score += tablePresence * 2.5

        // Forms need OCR for field content
        score += formPresence * 2.0

        // Multi-column: ONLY adds complexity if text quality is poor
        // Good text quality + multi-column = use spatialText (PDFKit handles column ordering)
        // Poor text quality + multi-column = need OCR to get correct reading order
        // This is THE KEY OPTIMIZATION: most 2-column PDFs have good native text!
        if textQuality < 0.6 {
            // Poor text quality - columns make it worse, need OCR
            if columnCount > 2 {
                score += 2.0
            } else if columnCount > 1 {
                score += 1.0
            }
        }
        // else: Good text quality - PDFKit spatial extraction handles column ordering, no OCR penalty

        // Layout complexity (only matters with poor text)
        if textQuality < 0.7 {
            score += layoutComplexity * 1.5
        }

        // High whitespace with embedded objects = figures
        if whitespaceRatio > 0.5 && embeddedObjectCount > 0 {
            score += 1.5
        }

        // Low text coverage suggests visual content
        if textCoverage < 0.2 {
            score += 2.0
        } else if textCoverage < 0.4 {
            score += 1.0
        }

        // ═══════════════════════════════════════════════════════════════════
        // RULE 4.5: TABLE PRESENCE OVERRIDE — NEVER skip OCR for table pages
        // PDFKit text extraction DESTROYS table structure and scrambles numeric
        // values. Vision OCR + RecognizeDocumentsRequest preserves cell alignment
        // and exact numbers. This is the #1 cause of wrong data in RAG answers.
        // ═══════════════════════════════════════════════════════════════════
        if tablePresence > 0.2 || numericDensity > 0.3 {
            // Tables and dense numeric content REQUIRE Vision OCR for accuracy
            // Even with a perfect native text layer, PDFKit mangles table cell values
            if tablePresence > 0.5 || numericDensity > 0.5 {
                return .complex     // Heavy table → enhancedOCR
            } else {
                return .moderate    // Some table signals → basicOCR (minimum)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // RULE 5: Classify based on score
        // ═══════════════════════════════════════════════════════════════════

        // FAST PATH: High-quality text with good coverage = use spatial extraction, skip OCR
        // IMPORTANT: Only skip Vision if text covers most of the page (>40%)
        // Pages with diagrams + captions have low text coverage and NEED Vision
        // to extract text from image annotations, warning icons, etc.
        if textQuality > 0.6 && textCoverage > 0.40 && hasNativeTextLayer {
            let hasHeavyVisuals = imagePresence > 0.3 || figurePresence > 0.3 || chartPresence > 0.2
            if !hasHeavyVisuals {
                // High text coverage, no heavy visuals → PDFKit can handle it
                if columnCount > 1 {
                    return .simple  // Multi-column with good text → spatialText
                } else if textQuality > 0.8 {
                    return .trivial  // Single column, great text → directText
                }
            }
        }

        if score < 0.5 && textCoverage > 0.5 && textQuality > 0.8 {
            return .trivial  // Pure clean text
        } else if score < 2.0 && textQuality > 0.65 && textCoverage > 0.35 {
            return .simple   // Mostly text with minor elements
        } else if score < 3.5 {
            return .moderate // Some visual elements
        } else if score < 5.5 {
            return .complex  // Significant visual complexity
        } else {
            return .visual   // Heavy visual content
        }
    }
}

// MARK: - Processing Strategy Extension

extension PageComplexityAnalysis {

    /// Get recommended processing strategy based on complexity
    var processingStrategy: PageProcessingStrategy {
        switch complexity {
        case .trivial:
            return .directText
        case .simple:
            return .spatialText
        case .moderate:
            return .basicOCR
        case .complex:
            return .enhancedOCR
        case .visual, .scanned:
            return .fullOCR
        }
    }
}

/// Processing strategy for a page
enum PageProcessingStrategy: Sendable {
    case directText     // Use page.string directly (fastest)
    case spatialText    // Use spatial text extraction from PDFKit
    case basicOCR       // Simple Vision OCR
    case enhancedOCR    // Spatial OCR with layout analysis
    case fullOCR        // Maximum OCR with image enhancement + Vision analysis

    var description: String {
        switch self {
        case .directText: return "direct"
        case .spatialText: return "spatial"
        case .basicOCR: return "basicOCR"
        case .enhancedOCR: return "enhancedOCR"
        case .fullOCR: return "fullOCR"
        }
    }

    /// Relative processing time multiplier (1.0 = baseline)
    var timeMultiplier: Double {
        switch self {
        case .directText: return 0.05   // 20x faster
        case .spatialText: return 0.2   // 5x faster
        case .basicOCR: return 1.0      // Baseline
        case .enhancedOCR: return 1.5   // 50% slower
        case .fullOCR: return 2.5       // 2.5x slower
        }
    }
}

// MARK: - Batch Processing Utilities

extension PageComplexityAnalyzer {

    /// Group pages by strategy for optimized batch processing
    func groupByStrategy(_ analyses: [PageComplexityAnalysis]) -> [PageProcessingStrategy: [Int]] {
        var groups: [PageProcessingStrategy: [Int]] = [:]

        for analysis in analyses {
            let strategy = analysis.processingStrategy
            groups[strategy, default: []].append(analysis.pageNumber)
        }

        return groups
    }

    /// Log comprehensive batch summary
    func logBatchSummary(_ analyses: [PageComplexityAnalysis]) {
        let groups = groupByStrategy(analyses)
        let totalPages = analyses.count
        let totalAnalysisTime = analyses.map { $0.analysisTimeMs }.reduce(0, +)

        var summary = "[PageComplexityAnalyzer] Batch analysis complete:\n"
        summary += "  Total pages: \(totalPages) | Analysis time: \(String(format: "%.1f", totalAnalysisTime))ms (\(String(format: "%.2f", totalAnalysisTime/Double(totalPages)))ms/page)\n"

        for strategy in [PageProcessingStrategy.directText, .spatialText, .basicOCR, .enhancedOCR, .fullOCR] {
            if let pages = groups[strategy], !pages.isEmpty {
                let percent = Int(Double(pages.count) / Double(totalPages) * 100)
                summary += "  • \(strategy.description): \(pages.count) pages (\(percent)%)\n"
            }
        }

        // Estimate time savings
        let skipPages = (groups[.directText]?.count ?? 0) + (groups[.spatialText]?.count ?? 0)
        let estimatedSavings = Int(Double(skipPages) / Double(max(1, totalPages)) * 100)

        summary += "  → Estimated OCR skip rate: \(estimatedSavings)% (\(skipPages) of \(totalPages) pages)"

        #if DEBUG
        print("ℹ️  \(summary)")
        #endif
    }
}

// MARK: - Character Extensions

private extension Character {
    var isPrintableASCII: Bool {
        guard let ascii = asciiValue else { return false }
        return ascii >= 32 && ascii <= 126
    }
}
