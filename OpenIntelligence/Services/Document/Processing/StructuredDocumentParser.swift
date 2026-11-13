//
//  StructuredDocumentParser.swift
//  OpenIntelligence
//
//  iOS 26+ structured document parsing using Vision's RecognizeDocumentsRequest.
//  Extracts tables, paragraphs, and lists as separate elements with structure metadata.
//  This preserves document structure - data in one table won't mix with unrelated data.
//
//  Key insight: Technical documents have specs in TABLES. Structured parsing keeps
//  related data together (e.g., medical dosages, legal clauses, product specifications).
//

import Foundation
import DataDetection
import os
import Vision
import CoreImage
import Metal

#if canImport(UIKit)
import UIKit
#endif

// MARK: - GPU Acceleration

/// Serial queue to prevent Metal command buffer race conditions
/// when multiple threads try to render CIImages concurrently
nonisolated private let gpuRenderQueue = DispatchQueue(label: "com.openintelligence.structured-parser-gpu", qos: .userInitiated)

/// Shared Metal-backed CIContext for GPU-accelerated image processing
/// CIContext is thread-safe — safe to access from any isolation domain.
nonisolated private let sharedGPUContext: CIContext = {
    if let device = MTLCreateSystemDefaultDevice() {
        return CIContext(mtlDevice: device, options: [
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ])
    } else {
        return CIContext(options: [.useSoftwareRenderer: true])
    }
}()

nonisolated private let renderLock = OSAllocatedUnfairLock()

/// Represents a structured element extracted from a document
enum StructuredElement: Sendable {
    case paragraph(text: String, pageNumber: Int)
    case table(TableData)
    case list(items: [String], pageNumber: Int)
    case title(text: String, pageNumber: Int)
    case figure(description: String, pageNumber: Int)  // Visual content reference

    /// The raw text content, formatted for embedding/retrieval
    nonisolated var textForEmbedding: String {
        switch self {
        case .paragraph(let text, _):
            return text
        case .table(let data):
            return data.textRepresentation
        case .list(let items, _):
            return items.joined(separator: "\n• ")
        case .title(let text, _):
            return text
        case .figure(let description, _):
            return description
        }
    }

    nonisolated var pageNumber: Int {
        switch self {
        case .paragraph(_, let page), .list(_, let page), .title(_, let page), .figure(_, let page):
            return page
        case .table(let data):
            return data.pageNumber
        }
    }

    nonisolated var elementType: String {
        switch self {
        case .paragraph: return "paragraph"
        case .table: return "table"
        case .list: return "list"
        case .title: return "title"
        case .figure: return "figure"
        }
    }
}

/// Represents automatically detected entities from Vision's DataDetection
/// These are extracted from cell.content.text.detectedData
struct DetectedEntity: Sendable, Equatable, Hashable {
    enum EntityType: String, Sendable, Hashable {
        case email
        case phoneNumber
        case url
        case address
        case date
        case money
        case measurement
        // Apple's detector returns these three and the regex sweep never could. They are
        // separate cases rather than `.unknown` so a chunk's metadata says what it found.
        case flightNumber
        case shipmentTracking
        case paymentIdentifier
        case unknown
    }

    let type: EntityType
    let value: String
    let rawText: String  // Original text that was detected

    /// Formatted representation for embedding/retrieval
    nonisolated var searchableText: String {
        switch type {
        case .email: return "Email: \(value)"
        case .phoneNumber: return "Phone: \(value)"
        case .url: return "URL: \(value)"
        case .address: return "Address: \(value)"
        case .date: return "Date: \(value)"
        case .money: return "Amount: \(value)"
        case .measurement: return "Measurement: \(value)"
        case .flightNumber: return "Flight: \(value)"
        case .shipmentTracking: return "Tracking: \(value)"
        case .paymentIdentifier: return "Payment: \(value)"
        case .unknown: return value
        }
    }
}

/// Cell alignment detected from spatial analysis
enum TableCellAlignment: String, Sendable {
    case left
    case center
    case right
    case unknown
}

/// Represents a parsed table with row/column structure preserved
struct TableData: Sendable {
    let pageNumber: Int
    let rows: [[String]]  // rows[rowIndex][colIndex] = cell text
    let headerRow: [String]?  // First row if detected as header
    let caption: String?  // Table caption if detected nearby
    let detectedEntities: [DetectedEntity]  // Auto-detected data (emails, phones, dates, etc.)
    let cellAlignments: [[TableCellAlignment]]  // Alignment for each cell

    /// Initialize with default unknown alignments
    nonisolated init(pageNumber: Int, rows: [[String]], headerRow: [String]?, caption: String?, detectedEntities: [DetectedEntity], cellAlignments: [[TableCellAlignment]]? = nil) {
        self.pageNumber = pageNumber
        self.rows = rows
        self.headerRow = headerRow
        self.caption = caption
        self.detectedEntities = detectedEntities
        // Default to inferred alignments if not provided
        self.cellAlignments = cellAlignments ?? Self.inferAlignments(from: rows)
    }

    /// Infer cell alignments from content (numbers = right, short text = center, else left)
    nonisolated private static func inferAlignments(from rows: [[String]]) -> [[TableCellAlignment]] {
        rows.map { row in
            row.map { cell in
                let trimmed = cell.trimmingCharacters(in: .whitespaces)

                // Numeric content → right-aligned
                let numericChars = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "$" || $0 == "%" || $0 == "-" }
                let isNumeric = Double(numericChars.count) / Double(max(1, trimmed.count)) > 0.6
                if isNumeric && !trimmed.isEmpty { return .right }

                // Short text (likely header or label) → center
                if trimmed.count < 15 && !trimmed.contains(" ") { return .center }

                // Default to left
                return .left
            }
        }
    }

    /// Convert table to a compact text representation that preserves structure for retrieval.
    /// Keep a schema view, optional prose summary for small key-value tables, row records,
    /// compact cell anchors, and one canonical table body. Avoid repeating the same table
    /// semantics across multiple redundant sections.
    nonisolated var textRepresentation: String {
        var lines: [String] = []
        let columnCount = maxColumnCount
        let headers = normalizedHeaders(for: columnCount)
        let records = rowRecords(headers: headers)
        let cells = compactCellDescriptions(headers: headers)
        let kvPairs = compactKeyValuePairs

        // DEBUG: Log table structure
        Log.debug("[TableData] Building textRepresentation: \(rows.count) rows, \(rows.first?.count ?? 0) cols, headerRow=\(headerRow != nil)", category: .ingestion)

        // === Section 1: Caption/Title ===
        if let caption = caption, !caption.isEmpty {
            lines.append("Table: \(caption)")
        } else {
            lines.append("Table:")
        }
        lines.append("")

        if let headers, !headers.isEmpty {
            lines.append("[Schema]")
            lines.append("Columns: " + headers.joined(separator: " | "))
            lines.append("")
        }

        // === Section 2: Natural Language Summary (UNIVERSAL) ===
        // Emit only for compact key-value tables to avoid duplicating large table semantics.
        if !kvPairs.isEmpty {
            Log.debug("[TableData] Generated \(kvPairs.count) key-value pairs", category: .ingestion)
            lines.append("[Summary]")
            for (key, value) in kvPairs {
                // Generate natural language sentence
                let sentence = generateNaturalSentence(key: key, value: value)
                lines.append(sentence)
            }
            lines.append("")
        }

        // === Section 3: Row-level records (preserves cross-cell relationships) ===
        if !records.isEmpty {
            lines.append("[Rows]")
            lines.append(contentsOf: records)
            lines.append("")
        } else if rows.count > 0 {
            // Fallback for unusual row shapes when we can't build labeled records.
            lines.append("[Row Contents]")
            for (rowIndex, row) in rows.enumerated() {
                let rowContent = row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
                if !rowContent.isEmpty {
                    if rowIndex == 0 && headerRow != nil {
                        lines.append("Headers: \(rowContent)")
                    } else {
                        lines.append("Row \(rowIndex): \(rowContent)")
                    }
                }
            }
            lines.append("")
        }

        // === Section 4: Compact cell anchors (high precision lookup) ===
        if !cells.isEmpty {
            lines.append("[Cells]")
            lines.append(contentsOf: cells)
            lines.append("")
        }

        // === Section 5: Detected Entities (Vision auto-extraction) ===
        if !detectedEntities.isEmpty {
            lines.append("[Detected Data]")
            for entity in detectedEntities {
                lines.append(entity.searchableText)
            }
            lines.append("")
        }

        // === Section 6: Full Markdown Table (for LLM comprehension) ===
        lines.append("[Table Data]")
        for (index, row) in normalizedRows.enumerated() {
            let formattedRow = "| " + row.joined(separator: " | ") + " |"
            lines.append(formattedRow)

            // Add separator after header row with alignment hints
            if index == 0 && headerRow != nil {
                let alignmentMarkers = normalizedAlignmentRow(at: 0, columnCount: columnCount).map { alignment -> String in
                    switch alignment {
                    case .left: return ":---"
                    case .right: return "---:"
                    case .center: return ":---:"
                    case .unknown: return "---"
                    }
                }
                let separator = "|" + alignmentMarkers.joined(separator: "|") + "|"
                lines.append(separator)
            }
        }

        return lines.joined(separator: "\n")
    }

    nonisolated private var maxColumnCount: Int {
        rows.map(\.count).max() ?? 0
    }

    nonisolated private var totalCellCount: Int {
        normalizedRows.reduce(0) { total, row in
            total + row.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
    }

    nonisolated private var normalizedRows: [[String]] {
        let columnCount = maxColumnCount
        guard columnCount > 0 else { return rows }

        return rows.map { row in
            var normalized = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if normalized.count < columnCount {
                normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
            } else if normalized.count > columnCount {
                normalized = Array(normalized.prefix(columnCount))
            }
            return normalized
        }
    }

    nonisolated private func normalizedHeaders(for columnCount: Int) -> [String]? {
        guard columnCount > 0, let headerRow else { return nil }

        return (0..<columnCount).map { columnIndex in
            let rawHeader = columnIndex < headerRow.count ? headerRow[columnIndex] : ""
            let trimmedHeader = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedHeader.isEmpty ? "Column \(columnIndex + 1)" : trimmedHeader
        }
    }

    nonisolated private func normalizedAlignmentRow(at index: Int, columnCount: Int) -> [TableCellAlignment] {
        guard index < cellAlignments.count else {
            return Array(repeating: .unknown, count: max(0, columnCount))
        }

        var row = cellAlignments[index]
        if row.count < columnCount {
            row.append(contentsOf: Array(repeating: .unknown, count: columnCount - row.count))
        } else if row.count > columnCount {
            row = Array(row.prefix(columnCount))
        }
        return row
    }

    nonisolated private func rowRecords(headers: [String]?) -> [String] {
        let sourceRows: ArraySlice<[String]>
        if headerRow != nil && normalizedRows.count > 1 {
            sourceRows = normalizedRows.dropFirst()
        } else {
            sourceRows = ArraySlice(normalizedRows)
        }

        return sourceRows.enumerated().compactMap { offset, row in
            if headers == nil, row.count >= 2 {
                let key = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !value.isEmpty {
                    return "Row \(offset + 1): \(key)=\(value)"
                }
            }

            let visibleCells = row.enumerated().compactMap { columnIndex, cell -> String? in
                let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }

                let label = headers?[columnIndex] ?? "Column \(columnIndex + 1)"
                return "\(label)=\(value)"
            }

            guard !visibleCells.isEmpty else { return nil }
            return "Row \(offset + 1): " + visibleCells.joined(separator: "; ")
        }
    }

    nonisolated private func compactCellDescriptions(headers: [String]?) -> [String] {
        let sourceRows: ArraySlice<[String]>
        if headerRow != nil && normalizedRows.count > 1 {
            sourceRows = normalizedRows.dropFirst()
        } else {
            sourceRows = ArraySlice(normalizedRows)
        }

        let maxCellDescriptions: Int
        switch totalCellCount {
        case 0...18:
            maxCellDescriptions = totalCellCount
        case 19...40:
            maxCellDescriptions = 18
        default:
            maxCellDescriptions = 0
        }

        guard maxCellDescriptions > 0 else { return [] }

        var descriptions: [String] = []
        descriptions.reserveCapacity(maxCellDescriptions)

        for (rowOffset, row) in sourceRows.enumerated() {
            for (columnOffset, cell) in row.enumerated() {
                let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                let label = headers?[columnOffset] ?? "Column \(columnOffset + 1)"
                descriptions.append("Cell r\(rowOffset + 1)c\(columnOffset + 1) [\(label)]: \(value)")
                if descriptions.count >= maxCellDescriptions {
                    return descriptions
                }
            }
        }

        return descriptions
    }

    /// Generate a natural language sentence from a key-value pair (domain-agnostic)
    /// Examples:
    ///   - ("Dosage", "500mg") → "The dosage is 500mg."
    ///   - ("Engine Oil", "SAE 0W-20") → "The engine oil is SAE 0W-20."
    ///   - ("Price", "$49.99") → "The price is $49.99."
    private nonisolated func generateNaturalSentence(key: String, value: String) -> String {
        let normalizedKey = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle common grammatical patterns
        let article: String
        if normalizedKey.hasPrefix("a ") || normalizedKey.hasPrefix("an ") || normalizedKey.hasPrefix("the ") {
            article = ""
        } else {
            article = "The "
        }

        return "\(article)\(normalizedKey) is \(cleanValue)."
    }

    /// Key-value representation for specs tables
    /// Works for BOTH 2-column tables (key-value) AND multi-column tables (using headers)
    /// Examples:
    ///   - 2-column no header: "Material | Grade A2-70" → [("Material", "Grade A2-70")]
    ///   - 2-column with header: Headers: [Property, Value], Row: [Material, Grade A2-70]
    ///                           → [("Material", "Grade A2-70")]
    ///   - Multi-column with headers: Headers: [Component, Type, Rating]
    ///                                Row: [Motor, Brushless, 500W]
    ///                                → [("Motor Type", "Brushless"), ("Motor Rating", "500W")]
    nonisolated var keyValuePairs: [(key: String, value: String)]? {
        guard !rows.isEmpty else { return nil }

        var pairs: [(key: String, value: String)] = []

        // Determine which rows are data (skip header if present)
        let dataRows: [[String]]
        if headerRow != nil && rows.count > 1 {
            // Skip first row (it's the header)
            dataRows = Array(rows.dropFirst())
        } else {
            dataRows = rows
        }

        guard !dataRows.isEmpty else { return nil }
        let columnCount = dataRows.first?.count ?? 0
        guard columnCount >= 2 else { return nil }

        // Case 1: 2-column table (classic key-value format)
        // First column = key, second column = value
        if columnCount == 2 {
            for row in dataRows {
                guard row.count >= 2 else { continue }
                let key = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty && !value.isEmpty else { continue }
                pairs.append((key: key, value: value))
            }
            return pairs.isEmpty ? nil : pairs
        }

        // Case 2: Multi-column table - need headers to make sense of columns
        guard let headers = headerRow, headers.count >= 2 else {
            // No headers for multi-column - generate row summaries instead
            return nil
        }

        // Each later cell keyed by its row's label and its column (5.8): ("DHA Daily Dose", "1-2 g"). Keyed by the
        // column alone, every row's "Daily Dose" came out as its own pair with no row, so a table passage's
        // "[Specifications]" lines and its summary gave values without saying which row they belong to.
        for row in dataRows {
            let label = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for (colIndex, header) in headers.enumerated() where colIndex > 0 {
                guard colIndex < row.count else { continue }
                let column = header.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = [label, column].filter { !$0.isEmpty }.joined(separator: " ")
                let value = row[colIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty && !value.isEmpty else { continue }
                pairs.append((key: key, value: value))
            }
        }

        return pairs.isEmpty ? nil : pairs
    }

    nonisolated private var compactKeyValuePairs: [(key: String, value: String)] {
        guard let pairs = keyValuePairs else { return [] }
        guard pairs.count <= 8 else { return [] }
        guard maxColumnCount <= 3 else { return [] }

        let averageKeyLength = Double(pairs.reduce(0) { $0 + $1.key.count }) / Double(max(1, pairs.count))
        let averageValueLength = Double(pairs.reduce(0) { $0 + $1.value.count }) / Double(max(1, pairs.count))
        guard averageKeyLength <= 42, averageValueLength <= 140 else { return [] }

        return pairs
    }
}

/// Result of parsing a document page with structure
struct StructuredPageContent: Sendable {
    let pageNumber: Int
    let elements: [StructuredElement]
    let rawText: String  // Fallback plain text
    let qualityScore: Double  // 0.0-1.0, how much content was captured vs raw text
    let figureReferences: [String]  // Detected figure/diagram references
    /// Running headers and footers the margin rule left out of `elements` (5.8). Text read some other way for the same
    /// page (the layout text that replaces paragraphs in hybrid mode) has these lines taken out too, so a header is
    /// removed on every page or on none, and the cross-page running-line rule still sees it repeat.
    var marginalTexts: [String] = []

    nonisolated var hasStructuredContent: Bool {
        elements.contains { element in
            switch element {
            case .table, .list: return true
            default: return false
            }
        }
    }

    /// Structured elements, repaired with recovered raw text when the structured parse was thin.
    ///
    /// Merges rather than chooses. The previous version returned raw text ONLY when the parse found
    /// no table or list, so a low-quality page that happened to capture one table kept the table and
    /// silently discarded everything else — including the fallback text the parser had already gone
    /// to the trouble of re-OCRing at `performTextRecognitionFallback`.
    ///
    /// That fires on exactly the highest-value pages. A scanned datasheet where the parse nails one
    /// table but transcribes a fifth of the surrounding prose shipped with four fifths of the page
    /// missing from chunks, from FTS5 and from the vector index, and the only trace was a warning
    /// in the log. Now the structured elements are kept AND the recovered prose is appended, minus
    /// anything the elements already cover.
    nonisolated var effectiveContent: [StructuredElement] {
        guard qualityScore < 0.5, !rawText.isEmpty else { return elements }

        if !hasStructuredContent {
            return [.paragraph(text: rawText, pageNumber: pageNumber)]
        }

        // Keep the structure, add back what the structured parse missed.
        let covered = Self.normalizedForCoverage(
            elements.map(Self.plainText(of:)).joined(separator: " ")
        )
        let recovered = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard line.count > 2 else { return false }
                return !covered.contains(Self.normalizedForCoverage(line))
            }

        guard !recovered.isEmpty else { return elements }
        return elements + [.paragraph(text: recovered.joined(separator: "\n"), pageNumber: pageNumber)]
    }

    /// Lowercased alphanumerics only, so a coverage check is not defeated by whitespace or
    /// punctuation differences between the structured serialisation and the raw OCR text.
    nonisolated static func normalizedForCoverage(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The text an element carries: a paragraph's or title's words, a table's rows as text, a list's items, a figure's
    /// description (`textForEmbedding`). The coverage check above compares against it, and an image read as a document
    /// stores it (`DocumentProcessor`, a photo or screenshot). Through 5.6 a table, list or figure came back as Swift's
    /// description of the element, so a photographed receipt with a table stored
    /// "table(OpenIntelligence.TableData(pageNumber: 1, rows: ..." in its text, where search and the model read it
    /// (household sample set in the iOS 27.0 Simulator, 2026-10-20).
    nonisolated static func plainText(of element: StructuredElement) -> String {
        element.textForEmbedding
    }
}

/// Service for structure-aware document parsing using iOS 26+ Vision APIs
/// A word of a PDF page's text layer with its box in Vision's normalized coordinates (origin bottom left, 0 to 1 over
/// the page's crop box), so a table cell Vision found can be read from the page's own characters (5.8).
struct TextLayerWord: Sendable, Equatable {
    let text: String
    let box: CGRect
    /// The page's size in points (its crop box), so a tolerance stated in points (pdfplumber's 1 and 3) can be applied
    /// to the normalized box; zero when not known.
    var pageSize: CGSize = .zero
}

@available(iOS 26.0, *)
actor StructuredDocumentParser {

    static let shared = StructuredDocumentParser()

    private struct OCRFallbackReadingBlock: Sendable {
        let text: String
        let topY: CGFloat
        let minX: CGFloat
    }

    private struct StructuredDocumentSnapshot: Sendable {
        let elements: [StructuredElement]
        let figureReferences: [String]
        let rawText: String
        let tableCount: Int
        let listCount: Int
        let figureCount: Int
        var marginalTexts: [String] = []
    }

    /// Dynamic custom words for the current document being processed.
    /// Set by DocumentProcessor before structured parsing begins.
    /// Merges universal terms with document-specific vocabulary.
    private var documentCustomWords: [String] = OCRConfiguration.universalCustomWords

    /// Update the dynamic vocabulary for the current document.
    /// Called once per document, before any page parsing starts.
    func setDocumentCustomWords(_ words: [String]) {
        documentCustomWords = words
    }

    private init() {}

    // MARK: - Public API

    /// Parse a PDF page image and extract structured elements (tables, paragraphs, lists)
    /// - Parameters:
    ///   - image: CIImage of the rendered PDF page
    ///   - pageNumber: 1-indexed page number for metadata
    ///   - customWords: Document-specific vocabulary for RecognizeDocumentsRequest.
    ///     Passed explicitly per-call so concurrent documents don't clobber each other's
    ///     vocabulary via actor state (Gap 1 fix).
    ///   - nativeWordCount: PDFKit word count for this page. Used as quality score
    ///     ground truth denominator instead of Vision's own transcript word count,
    ///     which under-counts dense tables and inflates qualityScore (Gap 2 fix).
    ///     Only trusted when text layer is validated (not garbled) — caller enforces this.
    ///   - preferFullResolution: Use the original 360 DPI page image for structure parsing
    ///     instead of the default 180 DPI downscaled pass. Reserved for high-risk pages
    ///     where small table cells or degraded text layers need maximum OCR fidelity.
    /// Smallest text this pipeline intends to read, as a fraction of image height.
    ///
    /// `minimumTextHeightFraction` is relative to image height, so it is **invariant to render
    /// scale** — a 6 pt glyph on a 792 pt page is 0.0076 of the image whether that image was
    /// rasterised at 144 or 432 DPI. That makes a single constant safe across render settings.
    ///
    /// 0.004 corresponds to roughly 3 pt text on US Letter (792 pt) and 2.4 pt on A5 (595 pt) —
    /// below the smallest legible print in any real document, so nothing readable is excluded.
    ///
    /// **The previous value was `0.0`, which is not a neutral default.** Apple's header for the
    /// identically-named property on `VNRecognizeTextRequest` states that at 0.0 "the image gets
    /// processed at the highest possible resolution with no downscaling. With that the processing
    /// time will be the longest and the memory usage the highest." Raising it lets Vision downscale
    /// before recognition, which is the documented performance lever.
    ///
    /// Conservative on purpose: text below this height is not recognised at all and no later stage
    /// can tell it was there. Lower it before raising it.
    private static let minimumTextHeightFraction: Float = 0.004

    func parsePageImage(
        _ image: CIImage,
        pageNumber: Int,
        customWords: [String],
        recognitionLanguages: [String]? = nil,
        nativeWordCount: Int? = nil,
        preferFullResolution: Bool = false,
        textLayerWords: [TextLayerWord]? = nil
    ) async throws -> StructuredPageContent {
        let startTime = Date()

        // Report ANE activity to HUD (RecognizeDocumentsRequest uses Neural Engine)
        Task { @MainActor in
            HardwareTelemetryState.shared.pulse(.llmInference, intensity: 0.8, duration: 0.5)  // Use llmInference for "structure analysis"
        }

        // MEMORY: Most pages can use a 50% downscaled structure pass (180 DPI from the
        // 360 DPI source), but high-risk pages should keep the original resolution.
        // This preserves small table cells and weak text layers without forcing the
        // entire document through the expensive path.
        //
        // Memory impact per page:
        //   360 DPI: createCGImage → 274 MB + UIGraphicsImageRenderer → 137 MB = ~411 MB
        //   180 DPI: createCGImage →  68 MB + UIGraphicsImageRenderer →  34 MB = ~102 MB
        //
        // With 3-5 concurrent parsePageImage calls in the TaskGroup, the downscaled path
        // remains the default. Full resolution is only used for pages flagged by the
        // CIImage.transformed(by:) is lazy — no pixel allocation until createCGImage fires.
        let structureImage = preferFullResolution
            ? image
            : image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))

        // Convert CIImage to CGImage (structure detection only).
        // The original full-resolution image is retained separately for the VNRecognizeTextRequest
        // fallback path, which is a pure OCR path where 360 DPI matters for fine print.
        let structureImageCG = renderLock.withLock {
            let img = sharedGPUContext.createCGImage(structureImage, from: structureImage.extent)
            _ = img?.dataProvider?.data
            return img
        }
        
        guard let structureCG = structureImageCG else {
            Log.warning("[StructuredDocumentParser] Failed to convert CIImage to CGImage, falling back to OCR", category: .ingestion)
            throw StructuredParsingError.imageConversionFailed
        }
        // Lazily produce full-res CGImage only if the OCR fallback path is actually needed.
        // Avoids the memory cost on the happy path (structure found).
        let fullResImageCG = {
            renderLock.withLock {
                let img = sharedGPUContext.createCGImage(image, from: image.extent)
                _ = img?.dataProvider?.data
                return img
            }
        }

        if preferFullResolution {
            Log.info("[StructuredDocumentParser] Page \(pageNumber): using full-resolution structure parsing for maximum fidelity", category: .ingestion)
        }

        // Create and configure the request
        // RecognizeDocumentsRequest is simpler in iOS 26 - it handles text recognition internally
        var request = RecognizeDocumentsRequest()

        // Configure text recognition options for maximum accuracy
        // customWords: universal terms + document-specific vocabulary, passed in explicitly
        // per-call so concurrent document ingestion cannot clobber vocabulary via actor state.
        request.textRecognitionOptions.customWords = customWords
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.minimumTextHeightFraction = Self.minimumTextHeightFraction

        // Recognition languages in priority order - Latin first to prevent CJK misrecognition
        // of bullet symbols and other non-text glyphs.
        //
        // When the caller has detected the document's language we say so and stop asking Vision to
        // guess. Apple's guidance is explicit that this is the accuracy-preserving choice, not just
        // the cheaper one: auto-detection "cannot always guarantee the correct detection", and a
        // wrong guess applies language correction against the wrong lexicon, which corrupts
        // recognised text rather than merely slowing it down.
        let languages = recognitionLanguages ?? OCRConfiguration.recognitionLanguages
        request.textRecognitionOptions.automaticallyDetectLanguage = (recognitionLanguages == nil)
        request.textRecognitionOptions.recognitionLanguages = languages.compactMap {
            Locale.Language(identifier: $0)
        }

        // A page without a text layer (a scan) is also read in quarters, for the text the whole-page reading misses (5.8).
        let tiledLines: [TextLayerWord] =
            (textLayerWords?.isEmpty ?? true) && Self.tilesScans
            ? await tiledTextLines(on: fullResImageCG() ?? structureCG, customWords: customWords) : []

        // Perform the structured document recognition (throttled to prevent Metal GPU races)
        let configuredRequest = request
        let structuredSnapshot: StructuredDocumentSnapshot? = try await VisionOCRThrottle.performAsync { [self] in
            let observations = try await configuredRequest.perform(on: structureCG)
            guard let document = observations.first?.document else {
                return nil
            }

            return await self.makeStructuredDocumentSnapshot(from: document, pageNumber: pageNumber, sourceImage: preferFullResolution ? image : structureImage, textLayerWords: textLayerWords, tiledLines: tiledLines)
        }

        guard let structuredSnapshot else {
            // RecognizeDocumentsRequest found no document structure
            // Fall back to RecognizeTextRequest for plain text extraction.
            // Use full-resolution image here — VNRecognizeTextRequest is pure OCR and benefits
            // from 360 DPI for fine print, footnotes, and small table cell text.
            Log.info("[StructuredDocumentParser] No document structure on page \(pageNumber), trying RecognizeTextRequest", category: .ingestion)
            do {
                let fallbackCG = fullResImageCG() ?? structureCG
                let fallbackText = try await performTextRecognitionFallback(on: fallbackCG, customWords: customWords)
                if !fallbackText.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    Log.info("[StructuredDocumentParser] RecognizeTextRequest captured \(fallbackText.split(separator: " ").count) words on page \(pageNumber) in \(String(format: "%.2f", elapsed))s", category: .ingestion)
                    return StructuredPageContent(
                        pageNumber: pageNumber,
                        elements: [.paragraph(text: fallbackText, pageNumber: pageNumber)],
                        rawText: fallbackText,
                        qualityScore: 0.5, // Moderate quality since we have raw text but no structure
                        figureReferences: []
                    )
                }
            } catch {
                Log.warning("[StructuredDocumentParser] RecognizeTextRequest fallback also failed: \(error.localizedDescription)", category: .ingestion)
            }
            throw StructuredParsingError.noDocumentDetected
        }

        let elements = structuredSnapshot.elements
        let figureReferences = structuredSnapshot.figureReferences
        var rawText = structuredSnapshot.rawText

        // Calculate quality score: how much content did structured parsing capture?
        // If structured elements have significantly fewer words than raw text, quality is low
        let structuredWordCount = elements.reduce(0) { $0 + $1.textForEmbedding.split(separator: " ").count }
        var rawWordCount = rawText.split(separator: " ").count
        // Gap 2 fix: use PDFKit native word count as ground truth denominator when provided.
        // Vision's own transcript (rawWordCount) under-counts dense tables — RecognizeDocuments
        // merges or drops cell separators, so rawWordCount < actual page word count. This makes
        // qualityScore appear high (structuredWords/lowRawCount ≈ 1.0) and suppresses the
        // fallback on exactly the pages that need it (dense tables, reference lists).
        // nativeWordCount = PDFKit page.string word count passed in from DocumentProcessor;
        // only trusted when text layer is validated (not garbled) — caller enforces this.
        let groundTruthWordCount = (nativeWordCount ?? 0) > rawWordCount ? nativeWordCount! : rawWordCount
        var qualityScore: Double = groundTruthWordCount > 0 ? min(1.0, Double(structuredWordCount) / Double(groundTruthWordCount)) : 1.0

        // ENHANCEMENT: Use RecognizeTextRequest fallback for very low quality parsing
        // This is more robust for low-DPI scans, unusual layouts, etc.
        if qualityScore < 0.3 || (rawWordCount < 10 && elements.isEmpty) {
            Log.info("[StructuredDocumentParser] Quality too low (\(Int(qualityScore * 100))%), trying RecognizeTextRequest fallback", category: .ingestion)
            do {
                // Use full-res image for OCR fallback — 360 DPI preserves fine print quality
                let fallbackCG = fullResImageCG() ?? structureCG
                let fallbackText = try await performTextRecognitionFallback(on: fallbackCG, customWords: customWords)
                if fallbackText.count > rawText.count {
                    rawText = fallbackText
                    rawWordCount = rawText.split(separator: " ").count
                    // Recalculate quality with improved raw text
                    qualityScore = rawWordCount > 0 ? min(1.0, Double(structuredWordCount) / Double(rawWordCount)) : 0.0
                    Log.info("[StructuredDocumentParser] RecognizeTextRequest captured \(rawWordCount) words (better than structured parsing)", category: .ingestion)
                }
            } catch {
                Log.warning("[StructuredDocumentParser] RecognizeTextRequest fallback failed: \(error.localizedDescription)", category: .ingestion)
            }
        }

        if qualityScore < 0.5 {
            Log.warning("[StructuredDocumentParser] Low quality parsing on page \(pageNumber): captured \(structuredWordCount)/\(rawWordCount) words (\(Int(qualityScore * 100))%)", category: .ingestion)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        Log.info("[StructuredDocumentParser] Parsed page \(pageNumber): \(elements.count) elements (\(structuredSnapshot.tableCount) tables, \(structuredSnapshot.listCount) lists, \(structuredSnapshot.figureCount) figures) quality=\(Int(qualityScore * 100))% in \(String(format: "%.2f", elapsed))s", category: .ingestion)

        if !figureReferences.isEmpty {
            Log.debug("[StructuredDocumentParser] Found \(figureReferences.count) figure references on page \(pageNumber)", category: .ingestion)
        }

        return StructuredPageContent(
            pageNumber: pageNumber,
            elements: elements,
            rawText: rawText,
            qualityScore: qualityScore,
            figureReferences: figureReferences,
            marginalTexts: structuredSnapshot.marginalTexts
        )
    }

    /// The caption-anchored figure pass is off unless `OI_FIGURES=on` is in the environment. Measured 2026-11-09 on the
    /// owner's eight PDFs: it found 9 figures and every stored passage was identical with it on and off (those pages'
    /// text reaches storage through the layout text), so nothing showed it helping, and a refuting review found ways it
    /// can take a running header or a sentence about a figure into a figure passage. It stays for measurement.
    nonisolated static var detectsFigures: Bool { ProcessInfo.processInfo.environment["OI_FIGURES"] == "on" }

    /// `OI_TILE_SCANS=off` in the environment turns the quartered reading of scans off, to compare on one build.
    nonisolated static var tilesScans: Bool { ProcessInfo.processInfo.environment["OI_TILE_SCANS"] != "off" }

    private func makeStructuredDocumentSnapshot(from document: DocumentObservation.Container, pageNumber: Int, sourceImage: CIImage, textLayerWords: [TextLayerWord]? = nil, tiledLines: [TextLayerWord] = []) async -> StructuredDocumentSnapshot {
        var elements: [StructuredElement] = []
        var figureReferences: [String] = []
        var figureCount = 0

        // Each element's box, and which elements are Vision's reading-order text (the title and paragraphs), so tables,
        // lists and recovered text can be put back where they sit on the page (5.8, `inPageOrder`).
        var elementBoxes: [CGRect?] = []
        var flowElements = Set<Int>()
        var layerTableElements = Set<Int>()

        var pageTitle: String? = nil
        if let title = document.title {
            var rawTitle = title.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            rawTitle = deconfuseCyrillicLatin(rawTitle)
            rawTitle = fixReversedTextIfNeeded(rawTitle)
            let (cleanedTitle, isLowQuality) = validateAndCleanOCR(rawTitle)
            if !cleanedTitle.isEmpty {
                let finalTitle = isLowQuality ? "[OCR unclear] \(cleanedTitle)" : cleanedTitle
                pageTitle = finalTitle
                elements.append(.title(text: finalTitle, pageNumber: pageNumber))
                elementBoxes.append(title.boundingRegion.normalizedPath.boundingBox)
                flowElements.insert(elements.count - 1)
                Log.debug("[StructuredDocumentParser] Found title: \(cleanedTitle.prefix(50))...\(isLowQuality ? " (low quality)" : "")", category: .ingestion)
            }
        }

        let figurePatterns = [
            #"(?i)(?:see\s+)?(?:figure|fig\.?|diagram|illustration|image|photo|picture)\s*\d*\s*[:\-]?\s*[^.]*"#,
            #"(?i)as\s+shown\s+(?:in\s+)?(?:the\s+)?(?:figure|diagram|image)"#,
            #"(?i)refer\s+to\s+(?:the\s+)?(?:figure|diagram|image)"#
        ]

        // A table's caption is its own "Table N." line when the page has one (5.8): the page title Vision reports is
        // the page's, and a paper's tables took the journal's masthead or a section heading as their title.
        let captionCandidates: [(text: String, box: CGRect)] = document.paragraphs.map {
            ($0.transcript, $0.boundingRegion.normalizedPath.boundingBox)
        }
        // Tables from where the text layer's words sit (5.8, `TextLayerTableDetector`), on a page with a good text layer.
        // A table Vision found that holds its region (at least 70% as many cells as the word runs inside it) is kept and
        // its words are left out of the search, so a table beside it is not merged into it; one that holds a fragment
        // (JAMA Psychiatry's full-page Table 1 as two columns) is replaced by the table its words make, and paragraphs
        // and lists inside a found table are its cells read as prose, so they are dropped.
        var layerTables: [TextLayerTableDetector.Table] = []
        var replacedVisionTables = Set<Int>()
        if let words = textLayerWords, !words.isEmpty {
            var keptBoxes: [CGRect] = []
            var weakTables: [(index: Int, box: CGRect)] = []
            for (index, table) in document.tables.enumerated() {
                let box = table.boundingRegion.normalizedPath.boundingBox
                let runs = TextLayerTableDetector.segmentCount(in: box, words: words)
                let cells = Set(table.rows.flatMap { $0 }.map { "\($0.rowRange):\($0.columnRange)" }).count
                if Double(cells) >= Double(runs) * 0.7 { keptBoxes.append(box) } else { weakTables.append((index, box)) }
            }
            // Prose paragraphs are not searched either (12 or more words, under a quarter of them numbers): justified
            // text has wide word gaps, and the PAH paper's right column became four columns of a 9-column table beside
            // its Table 1 (after10, 2026-11-08). Paragraphs of numbers stay in: a table Vision read as paragraphs.
            for paragraph in document.paragraphs {
                let tokens = paragraph.transcript.split(whereSeparator: \.isWhitespace)
                let numeric = tokens.filter { $0.contains(where: \.isNumber) }.count
                if tokens.count >= 12, Double(numeric) < Double(tokens.count) * 0.25 {
                    keptBoxes.append(paragraph.boundingRegion.normalizedPath.boundingBox)
                }
            }
            let free = words.filter { word in
                !keptBoxes.contains { $0.contains(CGPoint(x: word.box.midX, y: word.box.midY)) }
            }
            layerTables = TextLayerTableDetector.tables(in: free)
            for weak in weakTables where layerTables.contains(where: { $0.box.intersects(weak.box) }) {
                replacedVisionTables.insert(weak.index)
            }
        }
        // A paragraph or list inside a found table is dropped only when the table's text has 80% of its words: then it
        // is the table's cells read as prose. Otherwise it is text beside the table and stays.
        let layerTableTokens = layerTables.map { table in
            Self.coverageTokens(((table.header ?? []) + table.rows.flatMap { $0 }).joined(separator: " "))
        }
        func insideLayerTable(_ box: CGRect, text: String) -> Bool {
            let centre = CGPoint(x: box.midX, y: box.midY)
            let tokens = Self.coverageTokens(text)
            return layerTables.indices.contains { index in
                guard layerTables[index].box.insetBy(dx: -0.004, dy: -0.004).contains(centre) else { return false }
                guard !tokens.isEmpty else { return true }
                return Double(tokens.filter(layerTableTokens[index].contains).count) >= Double(tokens.count) * 0.8
            }
        }

        for (index, table) in document.tables.enumerated() where !replacedVisionTables.contains(index) {
            let ownCaption = Self.tableCaption(
                tableBox: table.boundingRegion.normalizedPath.boundingBox, paragraphs: captionCandidates)
            let tableData = parseTable(table, pageNumber: pageNumber, caption: ownCaption ?? pageTitle, textLayerWords: textLayerWords)
            elements.append(.table(tableData))
            elementBoxes.append(table.boundingRegion.normalizedPath.boundingBox)
            Log.debug("[StructuredDocumentParser] Found table with \(tableData.rows.count) rows on page \(pageNumber)", category: .ingestion)
        }
        for found in layerTables {
            let caption = Self.tableCaption(tableBox: found.box, paragraphs: captionCandidates) ?? pageTitle
            func normalized(_ row: [String]) -> [String] {
                row.map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            let header = found.header.map(normalized)
            let rows = (header.map { [$0] } ?? []) + found.rows.map(normalized)
            elements.append(.table(TableData(pageNumber: pageNumber, rows: rows, headerRow: header, caption: caption, detectedEntities: [])))
            elementBoxes.append(found.box)
            layerTableElements.insert(elements.count - 1)
            Log.info(
                "[StructuredDocumentParser] Page \(pageNumber): table of \(found.rows.count) rows and \(found.rows.first?.count ?? 0) columns read from the text layer's word positions",
                category: .ingestion)
        }

        for list in document.lists
        where !insideLayerTable(list.boundingRegion.normalizedPath.boundingBox, text: list.items.map(\.content.text.transcript).joined(separator: " ")) {
            let items = parseList(list)
            if !items.isEmpty {
                elements.append(.list(items: items, pageNumber: pageNumber))
                elementBoxes.append(list.boundingRegion.normalizedPath.boundingBox)
                Log.debug("[StructuredDocumentParser] Found list with \(items.count) items on page \(pageNumber)", category: .ingestion)
            }
        }

        // A paragraph's text-layer reading leaves out words inside a table (5.8): a paragraph box that overlapped Table 3
        // of the PAH paper took its values into the sentence ("individual com-1.64 pound").
        let tableBoxes = document.tables.enumerated().filter { !replacedVisionTables.contains($0.offset) }
            .map { $0.element.boundingRegion.normalizedPath.boundingBox } + layerTables.map(\.box)
        let paragraphWords = textLayerWords?.filter { word in
            let centre = CGPoint(x: word.box.midX, y: word.box.midY)
            return !tableBoxes.contains { $0.contains(centre) }
        }
        // Which element each Vision paragraph became, for the figure pass below.
        var paragraphElementIndex = [Int?](repeating: nil, count: document.paragraphs.count)
        for (paragraphIndex, paragraph) in document.paragraphs.enumerated()
        where !insideLayerTable(paragraph.boundingRegion.normalizedPath.boundingBox, text: paragraph.transcript) {
            let visionText = paragraph.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // A paragraph on a page with a good text layer is the page's own text when it is the same paragraph
            // (5.8): on pages where Vision finds a table, every paragraph came from OCR at half resolution.
            let cleanedText: String
            let isLowQuality: Bool
            if let words = paragraphWords, !words.isEmpty,
                let layerText = Self.textLayerText(
                    in: paragraph.boundingRegion.normalizedPath.boundingBox, words: words, lineSeparator: "\n"),
                Self.textLayerAgreesForParagraph(layerText, withVision: visionText)
            {
                cleanedText = layerText
                isLowQuality = false
                // Words Vision read in this paragraph that the text-layer reading lacks (diagnostic, 2026-11-08: "the
                // school" went missing from a two-column page whose Vision paragraph had it).
                let layerTokens = Self.coverageTokens(layerText)
                let missing = Self.coverageTokens(visionText).subtracting(layerTokens)
                if missing.count >= 2 {
                    Log.debug(
                        "[StructuredDocumentParser] Page \(pageNumber): text-layer reading of a paragraph lacks Vision's \(missing.sorted().prefix(6).joined(separator: ", "))",
                        category: .ingestion)
                }
            } else {
                // Diagnostic (2026-11-08): on a page with a text layer, why Vision's reading was kept.
                if let words = paragraphWords, !words.isEmpty,
                    let layer = Self.textLayerText(
                        in: paragraph.boundingRegion.normalizedPath.boundingBox, words: words, lineSeparator: "\n")
                {
                    let onlyLayer = Self.coverageTokens(layer).subtracting(Self.coverageTokens(visionText))
                    let onlyVision = Self.coverageTokens(visionText).subtracting(Self.coverageTokens(layer))
                    Log.debug(
                        "[StructuredDocumentParser] Page \(pageNumber): kept Vision's paragraph over the text layer (\(layer.count) vs \(visionText.count) characters; layer only: \(onlyLayer.sorted().prefix(5).joined(separator: " ")); Vision only: \(onlyVision.sorted().prefix(5).joined(separator: " ")))",
                        category: .ingestion)
                }
                var rawParagraphText = visionText
                rawParagraphText = deconfuseCyrillicLatin(rawParagraphText)
                rawParagraphText = fixReversedTextIfNeeded(rawParagraphText)
                (cleanedText, isLowQuality) = validateAndCleanOCR(rawParagraphText)
            }

            if !cleanedText.isEmpty && cleanedText.count > 10 {
                for pattern in figurePatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(cleanedText.startIndex..., in: cleanedText)
                        for match in regex.matches(in: cleanedText, range: range) {
                            if let matchRange = Range(match.range, in: cleanedText) {
                                let figRef = String(cleanedText[matchRange]).trimmingCharacters(in: .whitespaces)
                                if !figRef.isEmpty {
                                    figureReferences.append(figRef)
                                }
                            }
                        }
                    }
                }

                let finalText = isLowQuality ? "[OCR quality: low] \(cleanedText)" : cleanedText
                elements.append(.paragraph(text: finalText, pageNumber: pageNumber))
                elementBoxes.append(paragraph.boundingRegion.normalizedPath.boundingBox)
                flowElements.insert(elements.count - 1)
                paragraphElementIndex[paragraphIndex] = elements.count - 1
            }
        }

        // Figures by their captions (5.8, `FigureRegionDetector`, ported from pdffigures2): a "Figure N." caption's
        // figure is the region between it and the nearest body text, and the labels Vision read there as paragraphs
        // ("UnSg4.73, P<.001") are the figure's own text. The caption becomes a figure passage at the caption's place,
        // its labels the text layer's lines in that region, and the paragraphs inside the region are left out.
        var droppedByFigure = Set<Int>()
        if Self.detectsFigures, let words = textLayerWords, !words.isEmpty {
            // Body also holds the page title and any block in the margin zones the margin rule uses (top 8%, bottom
            // 13%), so a figure's region stops below a running header rather than taking it in as a label (refuting
            // review, 2026-11-08).
            let marginBlocks = captionCandidates.map(\.box).filter { $0.minY >= 0.92 || $0.maxY <= 0.13 }
            let bodyBoxes = tableBoxes
                + document.lists.map { $0.boundingRegion.normalizedPath.boundingBox }
                + captionCandidates.filter { FigureRegionDetector.isProse($0.text) }.map(\.box)
                + marginBlocks
                + [document.title?.boundingRegion.normalizedPath.boundingBox].compactMap { $0 }
            let figures = FigureRegionDetector.detect(paragraphs: captionCandidates, bodyBoxes: bodyBoxes, words: words)
            for figure in figures {
                guard let captionElement = paragraphElementIndex[figure.captionParagraphIndex] else { continue }
                let captionText = elements[captionElement].textForEmbedding
                let description = figure.labels.isEmpty
                    ? captionText : "\(captionText)\nLABELS: \(figure.labels.joined(separator: " | "))"
                elements[captionElement] = .figure(description: description, pageNumber: pageNumber)
                elementBoxes[captionElement] = figure.region.union(captionCandidates[figure.captionParagraphIndex].box)
                for index in figure.paragraphIndices {
                    if let element = paragraphElementIndex[index], element != captionElement { droppedByFigure.insert(element) }
                }
                figureCount += 1
            }
            if !figures.isEmpty {
                Log.info(
                    "[StructuredDocumentParser] Page \(pageNumber): \(figures.count) figure(s) by caption, \(droppedByFigure.count) label paragraph(s) folded into them",
                    category: .ingestion)
            }
        }
        
        // Text that no title, table, list or paragraph holds (5.8). Vision's document reading can leave a region out of
        // every container: the PAH paper's borderless Table 1 (48 rows beside its own continuation on page 4) was in none,
        // so every number in it was dropped while the page scored 100%, before and after the 2026-11-08 work. Every word
        // the page prints now reaches a passage: the text layer's words on a page with a good one, else Vision's lines.
        // A word is held only when an element's box holds it and that element's stored text says it: Vision drew a
        // paragraph box over the PAH paper's whole Table 1 whose text was only the column headers, so a box test alone
        // still dropped every number in it.
        let coveredRegions: [CoveredRegion] = elements.indices.compactMap { index in
            // A paragraph folded into a figure holds nothing: a word only it said comes back as recovered text.
            guard !droppedByFigure.contains(index) else { return nil }
            let box = elementBoxes[index] ?? (index == 0 ? document.title?.boundingRegion.normalizedPath.boundingBox : nil)
            guard let box else { return nil }
            var region = CoveredRegion(box: box, words: Self.coverageTokens(elements[index].textForEmbedding))
            region.allowsMisreads = !layerTableElements.contains(index)
            return region
        }
        let residualItems: [TextLayerWord]
        if let words = textLayerWords, !words.isEmpty {
            residualItems = words
        } else if !tiledLines.isEmpty {
            residualItems = tiledLines
        } else {
            // Lines Vision is more than half sure of: on JAMA's pages without a usable text layer, the lines Vision left out
            // of every container were mostly table headers it misread ("#n= 124U41 ... ISMDIa", after11, 2026-11-08).
            residualItems = document.text.lines.compactMap { line in
                guard let best = line.topCandidates(1).first, best.confidence > 0.5 else { return nil }
                let text = best.string
                guard !text.isEmpty else { return nil }
                return TextLayerWord(text: text, box: line.boundingBox.cgRect)
            }
        }
        let fromTextLayer = textLayerWords?.isEmpty == false
        for block in Self.uncoveredBlocks(items: residualItems, regions: coveredRegions) {
            let text: String
            if fromTextLayer {
                text = block.text
            } else {
                var raw = deconfuseCyrillicLatin(block.text)
                raw = fixReversedTextIfNeeded(raw)
                text = validateAndCleanOCR(raw).0
            }
            guard text.count > 3 else { continue }
            elements.append(.paragraph(text: text, pageNumber: pageNumber))
            elementBoxes.append(block.box)
            Log.info(
                "[StructuredDocumentParser] Page \(pageNumber): kept \(text.split(whereSeparator: \.isWhitespace).count) words no container held (\(fromTextLayer ? "text layer" : "Vision lines"))",
                category: .ingestion)
        }

        // Multi-Modal Figure Extraction (OS 27)
        // Check for graphical regions/figures extracted by DocumentObservation
        // (Mocking .figures accessor for OS 27 Vision SDK update)
        #if compiler(>=6.0) // Future-proofing for WWDC26 SDKs
        // Assuming OS 27 Vision DocumentObservation provides `.figures` bounding boxes
        /*
        for figure in document.figures {
            let bbox = figure.boundingBox
            // Convert normalized bounding box to image coordinates
            let rect = CGRect(
                x: bbox.minX * sourceImage.extent.width,
                y: bbox.minY * sourceImage.extent.height,
                width: bbox.width * sourceImage.extent.width,
                height: bbox.height * sourceImage.extent.height
            )
            
            // Crop the CIImage patch
            let croppedImage = sourceImage.cropped(to: rect)
            
            // Render to CGImage for the VLM
            if let cgImage = Self.sharedGPUContext.createCGImage(croppedImage, from: rect) {
                do {
                    // Send to OS 27 Multi-Modal Captioning Service. VisualCaptioningService, which this
                    // block calls, was removed in 5.7 on 2026-10-20 because nothing referenced it, so
                    // enabling the block needs a captioning service first.
                    let semanticCaption = try await VisualCaptioningService.shared.generateCaption(for: cgImage)
                    
                    elements.append(.figure(description: "[Visual Graph/Chart] " + semanticCaption, pageNumber: pageNumber))
                    figureCount += 1
                } catch {
                    Log.error("Failed to generate multi-modal caption for figure on page \(pageNumber): \(error)", category: .ingestion)
                }
            }
        }
        */
        #endif

        // Running headers and footers by position (Marker's MarginaliaProcessor, ported): a single page has no repeats to
        // find them by.
        let marginal = Self.marginalia(elements: elements, boxes: elementBoxes)
        if !marginal.isEmpty {
            Log.info("[StructuredDocumentParser] Page \(pageNumber): left out \(marginal.count) running header or footer block(s) by position", category: .ingestion)
        }
        let keptIndices = elements.indices.filter { !marginal.contains($0) && !droppedByFigure.contains($0) }
        let keptElements = keptIndices.map { elements[$0] }
        let keptBoxes = keptIndices.map { elementBoxes[$0] }
        let keptFlow = Set(keptIndices.enumerated().filter { flowElements.contains($0.element) }.map(\.offset))
        // Vision's reading order, other elements placed by position (`inPageOrder`). A port of XY-Cut++'s geometric
        // parts was measured against it on 2026-11-08 and taken out: olmOCR-Bench multi_column 0.556 against 0.562, and
        // on the owner's eight PDFs it split a sentence that Vision's order kept whole.
        let pageOrder = Self.inPageOrderIndices(boxes: keptBoxes, flow: keptFlow)
        let ordered = Self.withFootnotesLastAndSentencesJoined(
            order: pageOrder, elements: keptElements, boxes: keptBoxes, words: textLayerWords ?? []
        ).map { keptElements[$0] }

        return StructuredDocumentSnapshot(
            elements: ordered,
            figureReferences: figureReferences,
            rawText: document.text.transcript,
            tableCount: document.tables.count,
            listCount: document.lists.count,
            figureCount: figureCount,
            marginalTexts: marginal.sorted().map { elements[$0].textForEmbedding }
        )
    }

    /// Check if structured parsing is available on this device
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// The text-layer words whose centre lies in `box` (Vision's normalized coordinates, origin bottom left), in reading
    /// order: top line first, left to right. Nil when none does.
    /// The text-layer words inside `box`, line by line; a paragraph's lines are joined by line breaks (the running-line
    /// cleanup works line by line, and a header joined to the first line by a space stayed in the passage), a cell's by
    /// spaces.
    nonisolated static func textLayerText(in box: CGRect, words: [TextLayerWord], lineSeparator: String = " ") -> String? {
        // A word belongs to the box its first characters are in: a point half its height in from its left edge, so a
        // word whose box runs past the right edge of its line still counts (5.8).
        let inside = words.filter {
            box.contains(CGPoint(x: $0.box.minX + min($0.box.width, $0.box.height) / 2, y: $0.box.midY))
        }
        guard !inside.isEmpty else { return nil }
        // Words are grouped into lines first (top to bottom, a word joining the line whose first word's middle is
        // within half the median word height of its own), then each line is read left to right. Sorting by "different
        // line, else further left" in one comparator is not a consistent order, so words near a line's edge could come
        // out in a different order on different pages; and the tallest word's height (a drop cap) merged lines.
        let heights = inside.map(\.box.height).sorted()
        let lineTolerance = heights[heights.count / 2] * 0.5
        var lines: [[TextLayerWord]] = []
        for word in inside.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = lines.last?.first, abs(first.box.midY - word.box.midY) <= lineTolerance {
                lines[lines.count - 1].append(word)
            } else {
                lines.append([word])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: lineSeparator)
    }

    /// The text of `items` (words or lines with Vision-normalized boxes, origin bottom left) whose centre lies in no box of
    /// `covered`, as blocks in reading order (5.8). Items are grouped into rows by their middle (within half the median
    /// height); a row is cut into cells where a gap exceeds 1.2 times that height, and a row of two or more cells is
    /// written "a | b | c" so a borderless table keeps each value on its row label's line. Rows join a block while they
    /// overlap it horizontally and sit within 2.5 heights of its last row. A row cell of 8 or more words is prose, so a
    /// row holding prose and anything else is split into its cells (two columns of running text side by side).
    nonisolated static func uncoveredBlocks(items: [TextLayerWord], covered: [CGRect]) -> [(text: String, box: CGRect)] {
        uncoveredBlocks(items: items, regions: covered.map { CoveredRegion(box: $0, words: nil) })
    }

    /// An element's box and the words its stored text holds (nil: everything in the box).
    struct CoveredRegion: Sendable {
        let box: CGRect
        let words: Set<String>?
        /// Whether the region's text came from Vision's reading, so a few words it lacks are misreads of words it kept.
        /// A table read from the text layer has the exact words and holds only those (2026-11-08).
        var allowsMisreads = true
    }

    /// The tokens coverage compares by: lowercased runs of letters and digits.
    nonisolated static func coverageTokens(_ text: String) -> Set<String> {
        // Folded as stored text is (`normalizeExtractedText`): a table cell stores "10³" as "10^3" and "ﬁ" as "fi", and
        // a raw word compared unfolded was counted unheld and stored a second time (refuting review, 2026-11-08).
        let folded = OCRConfiguration.markingScriptsAndFractions(text).precomposedStringWithCompatibilityMapping
        return Set(folded.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    nonisolated static func uncoveredBlocks(items: [TextLayerWord], regions: [CoveredRegion]) -> [(text: String, box: CGRect)] {
        let margin: CGFloat = 0.004
        // The point a word belongs by, as in `textLayerText`: half its height in from its left edge. A word is held when
        // a region's box holds that point and the region's text has its tokens (half of them, for a line of several).
        // A region whose text has 80% or more of the words in its box holds them all: the rest are OCR's misreads of
        // words it did keep, not text it lost.
        let items = items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        func anchor(_ item: TextLayerWord) -> CGPoint {
            CGPoint(x: item.box.minX + min(item.box.width, item.box.height) / 2, y: item.box.midY)
        }
        func says(_ region: CoveredRegion, _ item: TextLayerWord) -> Bool {
            guard let words = region.words else { return true }
            let tokens = coverageTokens(item.text)
            guard !tokens.isEmpty else { return true }
            return Double(tokens.filter(words.contains).count) >= Double(tokens.count) * 0.5
        }
        let wholeRegions: [Bool] = regions.map { region in
            let inside = items.filter { region.box.insetBy(dx: -margin, dy: -margin).contains(anchor($0)) }
            guard !inside.isEmpty else { return true }
            guard region.allowsMisreads else { return false }
            return Double(inside.filter { says(region, $0) }.count) >= Double(inside.count) * 0.8
        }
        let loose = items.filter { item in
            let point = anchor(item)
            return !regions.indices.contains { index in
                regions[index].box.insetBy(dx: -margin, dy: -margin).contains(point)
                    && (wholeRegions[index] || says(regions[index], item))
            }
        }
        guard !loose.isEmpty else { return [] }
        let heights = loose.map(\.box.height).sorted()
        let height = max(heights[heights.count / 2], 0.002)

        struct Cell { var text: String; var box: CGRect }
        var rows: [[TextLayerWord]] = []
        for item in loose.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = rows.last?.first, abs(first.box.midY - item.box.midY) <= height * 0.5 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        var cellRows: [[Cell]] = []
        for row in rows {
            var cells: [Cell] = []
            for item in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                if var last = cells.last, item.box.minX - last.box.maxX <= height * 1.2 {
                    last.text += " " + item.text
                    last.box = last.box.union(item.box)
                    cells[cells.count - 1] = last
                } else {
                    cells.append(Cell(text: item.text, box: item.box))
                }
            }
            if cells.count > 1, cells.contains(where: { $0.text.split(separator: " ").count >= 8 }) {
                cellRows.append(contentsOf: cells.map { [$0] })
            } else {
                cellRows.append(cells)
            }
        }

        struct Block { var rows: [[Cell]]; var box: CGRect }
        var blocks: [Block] = []
        for row in cellRows {
            let rowBox = row.dropFirst().reduce(row[0].box) { $0.union($1.box) }
            if let index = blocks.lastIndex(where: { block in
                block.box.minX < rowBox.maxX && rowBox.minX < block.box.maxX
                    && block.box.minY - rowBox.maxY <= height * 2.5
            }) {
                blocks[index].rows.append(row)
                blocks[index].box = blocks[index].box.union(rowBox)
            } else {
                blocks.append(Block(rows: [row], box: rowBox))
            }
        }
        return blocks.map { block in
            (block.rows.map { row in row.map(\.text).joined(separator: row.count > 1 ? " | " : "") }.joined(separator: "\n"), block.box)
        }
    }

    /// The elements that are running headers or footers by their position alone, as Marker's MarginaliaProcessor decides
    /// it (datalab-to/marker, marker/processors/marginalia.py, master 71dd5fd7, Apache-2.0; validated by its authors on
    /// olmOCR-Bench; read 2026-11-08). A paragraph or title is one when all hold: it lies entirely in the top 8% of the
    /// page and above all body text, or entirely in the bottom 13% and below all body text; it is at most 3.5% of the
    /// page tall; its text is at most 150 characters; the page has at least two text blocks and some body. Body is the
    /// text blocks (paragraphs, titles, lists) not entirely inside either zone. Tables and lists are never marginalia.
    /// `OI_MARGINALIA=off` in the environment turns it off, to compare on one build (2026-11-08).
    nonisolated static func marginalia(elements: [StructuredElement], boxes: [CGRect?]) -> Set<Int> {
        guard ProcessInfo.processInfo.environment["OI_MARGINALIA"] != "off", elements.count == boxes.count else { return [] }
        func isText(_ element: StructuredElement) -> Bool {
            switch element {
            case .paragraph, .title, .list: return true
            default: return false
            }
        }
        func isEligible(_ element: StructuredElement) -> Bool {
            switch element {
            case .paragraph, .title: return true
            default: return false
            }
        }
        // Fractions of the page from the top: (top edge, bottom edge).
        func span(_ box: CGRect) -> (top: Double, bottom: Double) { (1 - Double(box.maxY), 1 - Double(box.minY)) }
        let textBlocks = elements.indices.filter { isText(elements[$0]) && boxes[$0] != nil }
        guard textBlocks.count >= 2 else { return [] }
        let headerZone = 0.08, footerZone = 0.13
        let body = textBlocks.filter { index in
            let s = span(boxes[index]!)
            return !(s.bottom <= headerZone || s.top >= 1 - footerZone)
        }
        guard !body.isEmpty else { return [] }
        let bodyTop = body.map { span(boxes[$0]!).top }.min()!
        let bodyBottom = body.map { span(boxes[$0]!).bottom }.max()!
        var out = Set<Int>()
        for index in textBlocks where isEligible(elements[index]) {
            let s = span(boxes[index]!)
            guard s.bottom - s.top <= 0.035 else { continue }
            let text = elements[index].textForEmbedding.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 150 else { continue }
            // Body text that reaches the margin zone is not a header or footer: a block that ends mid-sentence (in a
            // comma or a hyphen) or runs to 15 words or more. A lowercase last letter is no sign: running titles end in
            // one ("Frontiers in Bioengineering and Biotechnology"). Marker labels its blocks with a layout model first;
            // this port sees every paragraph, and the last two lines of a column ("Growth of B. lactis HN019 was
            // assessed ... conditions of pH,", fbioe p7, after17) were taken for a footer.
            if text.range(of: #"[,\-\u00AD]\s*$"#, options: .regularExpression) != nil
                || text.split(whereSeparator: \.isWhitespace).count >= 15
            {
                continue
            }
            let isHeader = s.bottom <= headerZone && s.bottom <= bodyTop
            let isFooter = s.top >= 1 - footerZone && s.top >= bodyBottom
            if isHeader || isFooter { out.insert(index) }
        }
        return out
    }

    /// A page's elements in reading order (5.8). Vision's title and paragraphs come in its reading order and stay in it;
    /// every other element (a table, a list, recovered text) goes before the first of them that sits below it in a
    /// column it overlaps, or at the end when none does. They were emitted tables first, then lists, then paragraphs, so
    /// a table took the section of whatever paragraph came before it on the previous page.
    nonisolated static func inPageOrder<Element>(_ elements: [Element], boxes: [CGRect?], flow: Set<Int>) -> [Element] {
        guard elements.count == boxes.count else { return elements }
        return inPageOrderIndices(boxes: boxes, flow: flow).map { elements[$0] }
    }

    /// `inPageOrder` as indices.
    nonisolated static func inPageOrderIndices(boxes: [CGRect?], flow: Set<Int>) -> [Int] {
        let elements = boxes
        var ordered: [Int] = elements.indices.filter { flow.contains($0) }
        func sharesColumn(_ a: CGRect, _ b: CGRect) -> Bool { a.minX < b.maxX && b.minX < a.maxX }
        // Top of the page first, so two elements placed before the same paragraph keep their own order (refuting
        // review, 2026-11-08: a list above a table came out after it).
        let placed = elements.indices.filter { !flow.contains($0) }
            .sorted { (boxes[$0]?.midY ?? -1) > (boxes[$1]?.midY ?? -1) }
        for index in placed {
            guard let box = boxes[index] else {
                ordered.append(index)
                continue
            }
            if let position = ordered.firstIndex(where: { other in
                guard flow.contains(other), let otherBox = boxes[other] else { return false }
                return sharesColumn(otherBox, box) && otherBox.midY < box.midY
            }) {
                ordered.insert(index, at: position)
            } else if let position = ordered.lastIndex(where: { other in
                guard let otherBox = boxes[other] else { return false }
                return sharesColumn(otherBox, box) && otherBox.midY > box.midY
            }) {
                // Nothing below it in its column (a table at the foot of the left column): after the last element
                // above it there, not after the whole page.
                ordered.insert(index, at: position + 1)
            } else {
                ordered.append(index)
            }
        }
        return ordered
    }

    /// The page's order with footnotes after its body and a sentence that a caption, figure or table interrupts put
    /// back together (5.8, 2026-11-08). No open tool publishes a footnote detector without a trained
    /// layout model; the rule is assembled from published pieces: body font size as the most common text-layer word
    /// height when it covers over half the words (pdffigures2 `DocumentLayout`), a footnote's words smaller than that
    /// (pdffigures2 `RegionClassifier.SmallFont`; 0.9 of the body height is inferred from LaTeX's 8/10, 9/11 and 10/12
    /// pt footnote sizes), a leading note mark (GROBID's `^(\d+\.?\s)`, plus *, †, ‡, §, ¶), and the lowest text in its
    /// column; footnotes go after the page's body, as Marker (`push_footnotes_to_bottom`) and PaddleX do. A paragraph
    /// that ends mid-sentence is followed by the next body paragraph that continues it, skipping what interrupted it
    /// (docling `predict_merges`: the first ends in a lowercase letter, comma or hyphen; the next starts with a letter,
    /// widened to an opening bracket or a digit, "(CTR)").
    nonisolated static func withFootnotesLastAndSentencesJoined(
        order: [Int], elements: [StructuredElement], boxes: [CGRect?], words: [TextLayerWord]
    ) -> [Int] {
        guard elements.count == boxes.count, order.count == elements.count else { return order }
        func paragraphText(_ index: Int) -> String? {
            if case .paragraph(let text, _) = elements[index] { return text }
            return nil
        }
        // Footnotes need font sizes, which only a text layer gives.
        var footnotes = Set<Int>()
        let heights = words.map { Double($0.box.height) }
        if heights.count >= 50 {
            let rounded = heights.map { ($0 * 2000).rounded() }
            let counts = Dictionary(grouping: rounded, by: { $0 }).mapValues(\.count)
            if let (mode, count) = counts.max(by: { $0.value < $1.value }), Double(count) > Double(heights.count) / 2 {
                let body = mode / 2000
                let marker = try? NSRegularExpression(pattern: #"^\s*(\d{1,3}\.?\s|[*\u2020\u2021\u00A7\u00B6]+\s?)"#)
                for index in order {
                    guard let text = paragraphText(index), let box = boxes[index] else { continue }
                    let ns = text as NSString
                    guard marker?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
                    let inside = words.filter { box.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
                    guard inside.count >= 3 else { continue }
                    let sizes = inside.map { Double($0.box.height) }.sorted()
                    guard sizes[sizes.count / 2] <= body * 0.9 else { continue }
                    // Lowest in its column: nothing else with text sits below it there.
                    let lowest = !order.contains { other in
                        guard other != index, let otherBox = boxes[other] else { return false }
                        return otherBox.minX < box.maxX && box.minX < otherBox.maxX && otherBox.midY < box.minY
                    }
                    if lowest { footnotes.insert(index) }
                }
            }
        }
        var sequence = order.filter { !footnotes.contains($0) }

        // Join a sentence across what interrupts it.
        let unfinished = try? NSRegularExpression(pattern: #"[\p{Ll},\-\u00AD]\s*$"#)
        let continues = try? NSRegularExpression(pattern: #"^\s*[\p{L}(\[0-9]"#)
        func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
            regex?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
        }
        // A caption is an interruption too (pdffigures2 `CaptionDetector`: "Figure", "Fig.", "Table" and a number).
        let caption = try? NSRegularExpression(
            pattern: #"^\s*(Figure|FIGURE|Fig\.?|FIG\.?|Table|TABLE)\s*([1-9][0-9]*|[IVX]+|[A-D]\.[1-9][0-9]*)\b"#)
        func isBody(_ index: Int) -> Bool {
            guard let text = paragraphText(index) else { return false }
            return !matches(caption, text)
        }
        // What can interrupt a sentence: a table, a figure, a caption. A list or a title is not: a list follows the
        // sentence that introduces it ("as follows"), and a title starts a section, so a body paragraph after either
        // stays after it (refuting review, 2026-11-08).
        func isInterruption(_ index: Int) -> Bool {
            switch elements[index] {
            case .table, .figure: return true
            case .paragraph(let text, _): return matches(caption, text)
            default: return false
            }
        }
        var position = 0
        while position < sequence.count - 1 {
            let current = sequence[position]
            guard isBody(current), let text = paragraphText(current), matches(unfinished, text),
                isInterruption(sequence[position + 1])
            else {
                position += 1
                continue
            }
            // The next body paragraph after the interruption, reached across interruptions only.
            guard
                let next = sequence[(position + 1)...].firstIndex(where: { !isInterruption($0) }),
                isBody(sequence[next]),
                let nextText = paragraphText(sequence[next]), matches(continues, nextText)
            else {
                position += 1
                continue
            }
            let moved = sequence.remove(at: next)
            sequence.insert(moved, at: position + 1)
            position += 1
        }
        return sequence + order.filter { footnotes.contains($0) }
    }

    /// Characters compared by the agreement tests, as UTF-16 units: lowercased, spaces dropped, dashes as "-".
    nonisolated private static func foldedForAgreement(_ text: String) -> [UInt16] {
        Array(
            text.lowercased()
                .replacingOccurrences(of: "\u{2013}", with: "-").replacingOccurrences(of: "\u{2014}", with: "-")
                .filter { !$0.isWhitespace }.utf16)
    }

    /// Whether two folded readings are within `limit` (a share of the longer one's length) by edit distance. Banded:
    /// only cells within that distance of the diagonal are computed, which gives the same answer as the full table
    /// at a fraction of its cost (a 2,000-character paragraph at a quarter: about 2 million cells instead of 4).
    nonisolated private static func withinEditRatio(_ a: [UInt16], _ b: [UInt16], limit: Double) -> Bool {
        if a == b { return true }
        guard !a.isEmpty, !b.isEmpty else { return false }
        let k = Int(limit * Double(max(a.count, b.count)))
        guard abs(a.count - b.count) <= k else { return false }
        let big = k + 1
        var previous = [Int](repeating: big, count: b.count + 1)
        var current = previous
        for j in 0...min(b.count, k) { previous[j] = j }
        for i in 1...a.count {
            let low = max(1, i - k), high = min(b.count, i + k)
            current[0] = i <= k ? i : big
            if low > 1 { current[low - 1] = big }
            var rowMinimum = current[0]
            if low <= high {
                for j in low...high {
                    let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                    let value = min(substitution, previous[j] + 1, current[j - 1] + 1)
                    current[j] = min(value, big)
                    rowMinimum = min(rowMinimum, current[j])
                }
            }
            if high < b.count { current[high + 1] = big }
            if rowMinimum > k { return false }
            swap(&previous, &current)
        }
        return previous[b.count] <= k
    }

    /// Whether a cell's text-layer reading and Vision's reading are the same cell: their characters, case, spacing and
    /// dash forms ignored, at most half different by edit distance ("1-2g" against "1-28", "3624" against "3024").
    /// Vision's empty reading always yields to the text layer.
    nonisolated static func textLayerAgrees(_ layer: String, withVision vision: String) -> Bool {
        let a = foldedForAgreement(layer), b = foldedForAgreement(vision)
        guard !a.isEmpty else { return false }
        guard !b.isEmpty else { return true }
        return keepsTheWords(layer, of: vision) && withinEditRatio(a, b, limit: 0.5)
    }

    /// Whether a text-layer reading has at least 80% as many words as Vision's. Some PDFs space words by position and
    /// print no space characters, so their text layer reads a line as one word ("whichpermitsunrestricteduse,..."); the
    /// agreement tests ignore spacing and took it over Vision's spaced reading (measured 2026-11-08: word recall fell
    /// from 0.90 to 0.66 on one paper, 0.96 to 0.70 on another).
    nonisolated private static func keepsTheWords(_ layer: String, of vision: String) -> Bool {
        let visionWords = vision.split(whereSeparator: \.isWhitespace).count
        guard visionWords >= 3 else { return true }
        return Double(layer.split(whereSeparator: \.isWhitespace).count) >= 0.8 * Double(visionWords)
    }

    /// Whether a paragraph's or a line's text-layer reading is what Vision read, with nothing left out or reordered:
    /// their characters (case, spacing and dash forms ignored) within 15% of each other in length and a quarter apart by
    /// edit distance, so OCR's misreads ("Int. J. lest. ocl.") are corrected and a reading its box cut short, or with
    /// lines interleaved, is refused (5.8; a word-set overlap let a truncated or scrambled reading through, refuting
    /// review 2026-11-08). Over 2,000 characters, where the edit distance costs too much, an in-order word sequence of
    /// at least 85% of the longer one's words. Under four characters, the cell test.
    nonisolated static func textLayerAgreesForParagraph(_ layer: String, withVision vision: String) -> Bool {
        let a = foldedForAgreement(layer), b = foldedForAgreement(vision)
        guard a.count >= 4, b.count >= 4 else { return textLayerAgrees(layer, withVision: vision) }
        guard keepsTheWords(layer, of: vision) else { return false }
        guard Double(min(a.count, b.count)) >= 0.85 * Double(max(a.count, b.count)) else { return false }
        if max(a.count, b.count) <= 2_000 { return withinEditRatio(a, b, limit: 0.25) }
        func words(_ text: String) -> [Substring] {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        }
        let wa = words(layer), wb = words(vision)
        guard !wa.isEmpty, !wb.isEmpty, wa.count <= 1_000, wb.count <= 1_000 else { return false }
        var previous = [Int](repeating: 0, count: wb.count + 1)
        var current = previous
        for i in 1...wa.count {
            for j in 1...wb.count {
                current[j] = wa[i - 1] == wb[j - 1] ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return Double(previous[wb.count]) >= 0.85 * Double(max(wa.count, wb.count))
    }

    /// The paragraph that captions a table: a line that starts "Table N" (or "Tab. N", "TABLE IV"), the nearest one above
    /// the table, else the nearest one below, within a fifth of the page. Boxes are Vision's normalized ones, origin at the
    /// bottom left. Nil when no such line is near (5.8).
    nonisolated static func tableCaption(tableBox: CGRect, paragraphs: [(text: String, box: CGRect)]) -> String? {
        let pattern = #"^(?:Table|TABLE|Tab\.)\s*(?:[0-9]+|[IVXLC]+)[A-Za-z]?\b"#
        let maxGap: CGFloat = 0.2
        var above: (gap: CGFloat, text: String)?
        var below: (gap: CGFloat, text: String)?
        for paragraph in paragraphs {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: pattern, options: .regularExpression) != nil else { continue }
            let horizontalOverlap = min(paragraph.box.maxX, tableBox.maxX) - max(paragraph.box.minX, tableBox.minX)
            guard horizontalOverlap > 0 else { continue }
            let gapAbove = paragraph.box.minY - tableBox.maxY
            let gapBelow = tableBox.minY - paragraph.box.maxY
            if gapAbove >= -0.01, gapAbove <= maxGap, above.map({ gapAbove < $0.gap }) ?? true {
                above = (gapAbove, text)
            } else if gapBelow >= -0.01, gapBelow <= maxGap, below.map({ gapBelow < $0.gap }) ?? true {
                below = (gapBelow, text)
            }
        }
        let caption = (above ?? below)?.text.replacingOccurrences(of: "\n", with: " ")
        return caption.map { String($0.prefix(200)) }
    }

    // MARK: - Private Helpers

    private func parseTable(_ table: DocumentObservation.Container.Table, pageNumber: Int, caption: String? = nil, textLayerWords: [TextLayerWord]? = nil) -> TableData {
        var rows: [[String]] = []
        var detectedEntities: [DetectedEntity] = []

        var garbledCellCount = 0
        var totalCellCount = 0
        var cellsFromTextLayer = 0

        // Cells are placed by the row and column ranges Vision gives them, not by their order in a row (5.8). A label or
        // value that spans rows ("DBA" and "45.13" over its two ion transitions) was in the first row only, so the second
        // row's cells moved left one column each ("Retention time (min): 144" for a precursor ion of 144). A cell that
        // spans rows is written in every row it covers; one that spans columns in its first column, except in the first
        // row, whose spanning headers ("Medium" over 1, 2 and 3) name every column under them.
        var seenCells = Set<String>()
        var spanningTitle: String?
        var placedCells: [DocumentObservation.Container.Table.Cell] = []
        for row in table.rows {
            for cell in row {
                let key = "\(cell.rowRange.lowerBound)-\(cell.rowRange.upperBound):\(cell.columnRange.lowerBound)-\(cell.columnRange.upperBound)"
                if seenCells.insert(key).inserted { placedCells.append(cell) }
            }
        }
        let rowCount = (placedCells.map(\.rowRange.upperBound).max() ?? -1) + 1
        let columnCount = (placedCells.map(\.columnRange.upperBound).max() ?? -1) + 1
        var grid = Array(repeating: Array(repeating: "", count: max(columnCount, 0)), count: max(rowCount, 0))

        for cell in placedCells {
            do {
                var text = normalizeTableCellText(cell.content.text.transcript)
                totalCellCount += 1
                // A page with a good text layer gives the cell's exact characters (5.8): Vision reads them off the
                // rendered page and misreads digits ("3624" as "3024"). The text layer is used when it agrees with
                // what Vision read, or when Vision read nothing; a disagreeing read keeps Vision's.
                if let words = textLayerWords, !words.isEmpty,
                    let layerText = Self.textLayerText(in: cell.content.boundingRegion.normalizedPath.boundingBox, words: words),
                    Self.textLayerAgrees(layerText, withVision: text)
                {
                    text = normalizeTableCellText(layerText)
                    cellsFromTextLayer += 1
                }

                if !text.isEmpty {
                    // Step 1: Fix Cyrillic→Latin substitutions (common Vision OCR error)
                    text = deconfuseCyrillicLatin(text)

                    // Step 2: Detect and fix reversed text (broken PDF text layers)
                    text = fixReversedTextIfNeeded(text)

                    // Step 3: Validate OCR quality (same pipeline as paragraphs/titles)
                    let (cleaned, isLowQuality) = validateAndCleanOCR(text)
                    text = cleaned

                    if isLowQuality {
                        garbledCellCount += 1
                        Log.warning("[StructuredDocumentParser] Low quality table cell on page \(pageNumber): '\(text.prefix(60))...'", category: .ingestion)
                    }
                }

                for rowIndex in cell.rowRange where rowIndex < rowCount {
                    // A cell over every column of the first row is the table's title, not a header for each column
                    // (refuting review, 2026-11-08): it stays in its first column.
                    let spansEveryColumn = cell.columnRange.count >= columnCount && columnCount > 1
                    let columns =
                        rowIndex == 0 && !spansEveryColumn ? Array(cell.columnRange) : [cell.columnRange.lowerBound]
                    for columnIndex in columns where columnIndex < columnCount {
                        grid[rowIndex][columnIndex] = text
                    }
                }
                if cell.rowRange.lowerBound == 0, cell.columnRange.count >= columnCount, columnCount > 1, !text.isEmpty {
                    spanningTitle = text
                }

                // ENHANCEMENT: Extract detected data from Vision's DataDetection
                // This automatically finds emails, phone numbers, dates, URLs, etc.
                let cellEntities = extractDetectedData(from: cell.content.text)
                detectedEntities.append(contentsOf: cellEntities)
            }
        }
        // A row Vision returned with no cells at all is not a row of the table.
        rows = grid.filter { row in row.contains { !$0.isEmpty } }

        if cellsFromTextLayer > 0 {
            Log.info("[StructuredDocumentParser] Table on page \(pageNumber): \(cellsFromTextLayer) of \(totalCellCount) cells read from the text layer", category: .ingestion)
        }

        rows = mergeWrappedContinuationRows(in: rows, pageNumber: pageNumber)

        // A title Vision reads as one cell over every column of the first row is the table's caption, not its header
        // (5.8). Taken as the header it named the columns "<title> | Column 2 | Column 3" and stored the real header as
        // ROW 1, so no value kept its column name (KBIE_13_2100863.pdf page 6, the 2026-11-10 import check).
        var caption = caption
        if let title = spanningTitle, rows.count > 1,
            let lifted = Self.liftingSpanningTitle(title, from: rows, caption: caption)
        {
            rows = lifted.rows
            caption = lifted.caption
        }

        // Quality gate: if majority of cells are garbled, log warning
        if totalCellCount > 0 {
            let garbledRatio = Double(garbledCellCount) / Double(totalCellCount)
            if garbledRatio > 0.5 {
                Log.warning("[StructuredDocumentParser] Table on page \(pageNumber) is mostly garbled (\(Int(garbledRatio * 100))% low quality cells)", category: .ingestion)
            }
        }

        // UNIVERSAL: Detect if first row looks like a header using structural heuristics
        // These patterns work across ALL domains (medical, automotive, financial, legal, etc.)
        let headerRow: [String]? = {
            guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }
            guard rows.count > 1 else { return nil }  // Need at least 2 rows for header detection

            // Heuristic 1: First row cells are shorter than body cells (headers are usually terse)
            let firstRowAvgLength = firstRow.reduce(0) { $0 + $1.count } / max(1, firstRow.count)
            let bodyRowsAvgLength: Int = {
                let bodyRows = Array(rows.dropFirst())
                guard !bodyRows.isEmpty else { return firstRowAvgLength }
                let totalChars = bodyRows.reduce(0) { total, row in
                    total + row.reduce(0) { $0 + $1.count }
                }
                let totalCells = bodyRows.reduce(0) { $0 + $1.count }
                return totalChars / max(1, totalCells)
            }()
            let shorterThanBody = firstRowAvgLength < bodyRowsAvgLength

            // Heuristic 2: First row cells don't contain numeric data (headers are usually text labels)
            let firstRowNumericCells = firstRow.filter { cell in
                let digits = cell.filter { $0.isNumber }
                return Double(digits.count) / Double(max(1, cell.count)) > 0.5
            }.count
            let mostlyNonNumeric = firstRowNumericCells == 0

            // Heuristic 3: First row cells are different "types" than body cells
            // (e.g., headers are all-text while body has mixed alphanumeric)
            let headerPatternsDiffer: Bool = {
                guard let secondRow = rows.dropFirst().first else { return false }
                let firstRowPatterns = firstRow.map { classifyCellContent($0) }
                let secondRowPatterns = secondRow.map { classifyCellContent($0) }
                // If patterns differ (e.g., first is all .text, second has .numeric), likely header
                return firstRowPatterns != secondRowPatterns
            }()

            // If 2+ heuristics match, treat as header
            let heuristicHits = [shorterThanBody, mostlyNonNumeric, headerPatternsDiffer].filter { $0 }.count
            return heuristicHits >= 2 ? firstRow : nil
        }()

        // Deduplicate entities by value (avoid Hashable actor isolation issues)
        var seenValues = Set<String>()
        let uniqueEntities = detectedEntities.filter { entity in
            let key = "\(entity.type.rawValue):\(entity.value)"
            if seenValues.contains(key) { return false }
            seenValues.insert(key)
            return true
        }

        if !uniqueEntities.isEmpty {
            Log.debug("[StructuredDocumentParser] Extracted \(uniqueEntities.count) entities from table: \(uniqueEntities.map { $0.type.rawValue }.joined(separator: ", "))", category: .ingestion)
        }

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: headerRow,
            caption: caption,
            detectedEntities: uniqueEntities
        )
    }

    /// The rows and caption of a table whose first row holds only `title` (in its first column, every other cell
    /// empty): that row is dropped and the title joins the caption, unless the caption already holds it. Nil when the
    /// first row is anything else, so a real header row is never taken away.
    nonisolated static func liftingSpanningTitle(_ title: String, from rows: [[String]], caption: String?) -> (
        rows: [[String]], caption: String?
    )? {
        guard let first = rows.first, first.first == title, first.count > 1, first.dropFirst().allSatisfy(\.isEmpty)
        else { return nil }
        let folded: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let joined: String
        if let caption, !caption.isEmpty {
            let captionKey = folded(caption)
            let titleKey = folded(title)
            if captionKey.contains(titleKey) {
                joined = caption
            } else if titleKey.contains(captionKey) {
                joined = title
            } else {
                joined = caption + " " + title
            }
        } else {
            joined = title
        }
        return (Array(rows.dropFirst()), joined)
    }

    private func normalizeTableCellText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergeWrappedContinuationRows(in rows: [[String]], pageNumber: Int) -> [[String]] {
        guard !rows.isEmpty else { return [] }

        var mergedRows: [[String]] = []
        var mergeCount = 0

        for row in rows {
            let normalizedRow = row.map(normalizeTableCellText)
            guard normalizedRow.contains(where: { !$0.isEmpty }) else { continue }

            guard let previousRow = mergedRows.last,
                  shouldMergeContinuationRow(previous: previousRow, current: normalizedRow) else {
                mergedRows.append(normalizedRow)
                continue
            }

            mergedRows[mergedRows.count - 1] = mergeTableRows(previous: previousRow, continuation: normalizedRow)
            mergeCount += 1
        }

        if mergeCount > 0 {
            Log.info("[StructuredDocumentParser] Merged \(mergeCount) OCR continuation row(s) on page \(pageNumber)", category: .ingestion)
        }

        return mergedRows
    }

    private func shouldMergeContinuationRow(previous: [String], current: [String]) -> Bool {
        let columnCount = max(previous.count, current.count)
        let paddedPrevious = padTableRow(previous, to: columnCount)
        let paddedCurrent = padTableRow(current, to: columnCount)

        let previousNonEmptyColumns = nonEmptyColumnIndices(in: paddedPrevious)
        let currentNonEmptyColumns = nonEmptyColumnIndices(in: paddedCurrent)

        guard !previousNonEmptyColumns.isEmpty, !currentNonEmptyColumns.isEmpty else { return false }

        let maxContinuationColumns = max(1, Int(ceil(Double(columnCount) / 3.0)))
        guard currentNonEmptyColumns.count <= maxContinuationColumns else { return false }
        guard Set(currentNonEmptyColumns).isSubset(of: Set(previousNonEmptyColumns)) else { return false }

        var score = 0
        var hasStrongContinuationSignal = false

        if currentNonEmptyColumns.count == 1 {
            score += 2
        }

        if let firstColumn = currentNonEmptyColumns.first, firstColumn > 0 {
            score += 2
        }

        if columnCount > 1,
           paddedCurrent.first?.isEmpty == true,
           paddedPrevious.first?.isEmpty == false {
            score += 2
        }

        for columnIndex in currentNonEmptyColumns {
            let previousCell = paddedPrevious[columnIndex]
            let currentCell = paddedCurrent[columnIndex]
            guard !previousCell.isEmpty else { return false }

            if previousCell.hasSuffix("-") {
                score += 3
                hasStrongContinuationSignal = true
            }

            if looksLikeContinuationFragment(currentCell) {
                score += 2
                hasStrongContinuationSignal = true
            }

            if !previousCellHasTerminalStop(previousCell),
               currentCell.split(whereSeparator: \.isWhitespace).count <= 6 {
                score += 1
            }
        }

        if currentNonEmptyColumns.contains(0),
           let firstCell = paddedCurrent.first,
           looksLikeStandaloneLeadingLabel(firstCell),
           previousNonEmptyColumns.count > currentNonEmptyColumns.count {
            score -= 3
        }

        return score >= 5 && hasStrongContinuationSignal
    }

    private func mergeTableRows(previous: [String], continuation: [String]) -> [String] {
        let columnCount = max(previous.count, continuation.count)
        var mergedRow = padTableRow(previous, to: columnCount)
        let paddedContinuation = padTableRow(continuation, to: columnCount)

        for columnIndex in 0..<columnCount {
            let continuationCell = paddedContinuation[columnIndex]
            guard !continuationCell.isEmpty else { continue }

            let previousCell = mergedRow[columnIndex]
            if previousCell.isEmpty {
                mergedRow[columnIndex] = continuationCell
            } else {
                mergedRow[columnIndex] = normalizeTableCellText(joinTableCellText(previousCell, continuationCell))
            }
        }

        return mergedRow
    }

    private func padTableRow(_ row: [String], to columnCount: Int) -> [String] {
        guard row.count < columnCount else { return row }
        return row + Array(repeating: "", count: columnCount - row.count)
    }

    private func nonEmptyColumnIndices(in row: [String]) -> [Int] {
        row.enumerated().compactMap { index, cell in
            cell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : index
        }
    }

    private func looksLikeContinuationFragment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let firstScalar = trimmed.unicodeScalars.first {
            if CharacterSet.lowercaseLetters.contains(firstScalar) || CharacterSet.punctuationCharacters.contains(firstScalar) {
                return true
            }
        }

        let lowered = trimmed.lowercased()
        let continuationWords = [
            "and", "or", "to", "for", "with", "without", "of", "the", "a", "an",
            "is", "are", "was", "were", "be", "being", "been", "has", "have", "had",
            "in", "on", "at", "by", "from", "into", "over", "under"
        ]

        return continuationWords.contains { word in
            lowered == word || lowered.hasPrefix(word + " ")
        }
    }

    private func previousCellHasTerminalStop(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastCharacter = trimmed.last else { return false }
        return [".", "!", "?"].contains(String(lastCharacter))
    }

    private func looksLikeStandaloneLeadingLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !looksLikeContinuationFragment(trimmed) else { return false }

        if let firstScalar = trimmed.unicodeScalars.first,
           CharacterSet.uppercaseLetters.contains(firstScalar) || CharacterSet.decimalDigits.contains(firstScalar) {
            return trimmed.split(whereSeparator: \.isWhitespace).count <= 6
        }

        return false
    }

    private func joinTableCellText(_ previous: String, _ continuation: String) -> String {
        let left = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = continuation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }

        if left.hasSuffix("-") {
            return left + right
        }

        if let firstCharacter = right.first,
           [",", ".", ";", ":", ")", "%"].contains(String(firstCharacter)) {
            return left + right
        }

        return left + " " + right
    }

    private func parseList(_ list: DocumentObservation.Container.List) -> [String] {
        var items: [String] = []

        for item in list.items {
            var text = item.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // Apply same OCR cleanup pipeline as tables and paragraphs
                text = deconfuseCyrillicLatin(text)
                text = fixReversedTextIfNeeded(text)
                let (cleaned, _) = validateAndCleanOCR(text)
                text = cleaned
                if !text.isEmpty {
                    items.append(text)
                }
            }
        }

        return items
    }

    // MARK: - Universal Cell Content Classification

    /// Cell content type for header detection heuristics (domain-agnostic)
    private enum CellContentType: Equatable {
        case text           // Pure text (likely a label/header)
        case numeric        // Mostly numbers (likely data)
        case alphanumeric   // Mixed letters and numbers (codes, IDs)
        case empty          // Empty cell
    }

    /// Classify cell content type for universal header detection
    /// Works across ALL domains without keyword matching
    private func classifyCellContent(_ cell: String) -> CellContentType {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let digits = trimmed.filter { $0.isNumber }
        let letters = trimmed.filter { $0.isLetter }

        let digitRatio = Double(digits.count) / Double(trimmed.count)
        let letterRatio = Double(letters.count) / Double(trimmed.count)

        if digitRatio > 0.6 {
            return .numeric
        } else if letterRatio > 0.8 {
            return .text
        } else {
            return .alphanumeric
        }
    }

    // MARK: - Vision DataDetection Entity Extraction

    /// Entities in a block of recognised text, taken from Apple's own detector first.
    ///
    /// `RecognizeDocumentsRequest` runs data detection during the same pass that produces the
    /// transcript and returns the results on `Container.Text.detectedData`. This function used to
    /// ignore that property completely and re-derive entities from five hand-written regexes,
    /// under a comment saying full integration "requires additional API verification". That
    /// verification is done: `DataDetectorMatch.match.details` is a `SemanticDetails` enum with
    /// ten cases, read from the iOS 27 SDK's `DataDetection.swiftinterface` on 2026-09-11.
    ///
    /// Reading it is strictly better and costs nothing, because Vision has already done the work:
    ///
    ///   * it returns **parsed values** rather than matched substrings, so an amount arrives as a
    ///     `Decimal` with a `Locale.Currency` and an event as a `Date`, instead of as whatever
    ///     characters happened to sit between two separators
    ///   * it covers postal addresses, measurements, flight numbers, shipment tracking numbers and
    ///     payment identifiers. The regexes attempted none of those
    ///   * it is not anglocentric. The phone pattern matched US formats only and the money pattern
    ///     matched exactly three currencies, so a European invoice yielded nothing at all
    ///
    /// The regexes are kept rather than deleted, and run only for the types Apple returned nothing
    /// for. `detectedData` is empty whenever the structured parse degraded to plain text
    /// recognition, and that is exactly the low-quality scan where one email address may be the
    /// only thing on the page worth extracting.
    private func extractDetectedData(from text: DocumentObservation.Container.Text) -> [DetectedEntity] {
        let transcript = text.transcript
        var entities = text.detectedData.compactMap { Self.entity(from: $0.match, in: transcript) }
        let covered = Set(entities.map(\.type))
        entities.append(contentsOf: Self.patternEntities(in: transcript, excluding: covered))
        return entities
    }

    /// One `DetectedEntity` from one of Apple's matches, or nil when the match carries nothing
    /// worth indexing.
    ///
    /// `match.range` indexes into the transcript it was produced from, so `rawText` keeps the text
    /// as it appears on the page while `value` holds the normalised form. Both are kept because a
    /// reader may later search for either: the phone number as printed, or as Apple parsed it.
    nonisolated private static func entity(
        from match: DataDetector.Match,
        in transcript: String
    ) -> DetectedEntity? {
        let raw = match.range.map { String(transcript[$0]) } ?? ""

        func made(_ type: DetectedEntity.EntityType, _ value: String) -> DetectedEntity? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return DetectedEntity(type: type, value: trimmed, rawText: raw.isEmpty ? trimmed : raw)
        }

        switch match.details {
        case .link(let link):
            return made(.url, link.url.absoluteString)
        case .emailAddress(let email):
            return made(.email, email.emailAddress)
        case .phoneNumber(let phone):
            return made(.phoneNumber, phone.phoneNumber)
        case .postalAddress(let address):
            return made(.address, address.fullAddress)
        case .calendarEvent(let event):
            // An event with no start date is not a date anyone can search for.
            guard let start = event.startDate else { return nil }
            let formatter = event.allDay ? Self.eventDayFormatter : Self.eventInstantFormatter
            return made(.date, formatter.string(from: start))
        case .moneyAmount(let money):
            return made(.money, "\(money.amount) \(money.currency.identifier)")
        case .measurement(let measurement):
            // `possibleDimensions` is ordered by likelihood and is empty for a bare quantity.
            // A number with no unit is still worth keeping; it is what the page said.
            let symbol = measurement.possibleDimensions.first?.symbol
            let value = symbol.map { "\(measurement.value) \($0)" } ?? "\(measurement.value)"
            return made(.measurement, value)
        case .flightNumber(let flight):
            return made(.flightNumber, "\(flight.airlineCode)\(flight.flightNumber)")
        case .shipmentTrackingNumber(let shipment):
            return made(.shipmentTracking, "\(shipment.carrier) \(shipment.trackingNumber)")
        case .paymentIdentifier(let payment):
            return made(.paymentIdentifier, payment.identifier)
        @unknown default:
            // A category Apple adds later. Dropping it loses an entity; guessing at its shape
            // would put an unlabelled string into chunk metadata, which is worse.
            return nil
        }
    }

    /// Dates are written ISO 8601 so they sort, and so a query typed as `2026-09-11` matches the
    /// same characters that were indexed.
    nonisolated private static let eventDayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    nonisolated private static let eventInstantFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter
    }()

    /// Apple's detector on plain text (5.7, roadmap row "Entities come from table cells only").
    ///
    /// Vision's detection ran only on table cells (`extractDetectedData` has one caller,
    /// `parseTable`), and a page read from its text layer never reaches Vision, so the addresses,
    /// phone numbers, dates and amounts the 5.3 notes describe were found nowhere else. From iOS
    /// and macOS 26 any text can go through the same detector (`StringProtocol.dataDetectorMatches`,
    /// read from the iOS 27 SDK on 2026-10-14), with the same matches the cells give, and the regex
    /// sweep fills a type the detector found none of, as for a cell. Only the first
    /// `characterLimit` characters are read. Measured on the Mac (M3 Pro) that day: 0.7 to 1.1
    /// million characters a second, 672,860 in 0.61 s.
    @concurrent
    nonisolated static func detectedEntities(inText text: String, characterLimit: Int) async -> [DetectedEntity] {
        let read = text.count > characterLimit ? String(text.prefix(characterLimit)) : text
        guard !read.isEmpty else { return [] }
        var entities: [DetectedEntity] = []
        for await match in read.dataDetectorMatches() {
            if let entity = entity(from: match, in: read) {
                entities.append(entity)
            }
        }
        let covered = Set(entities.map(\.type))
        entities.append(contentsOf: patternEntities(in: read, excluding: covered))
        return entities
    }

    /// The original regex sweep, kept as a fallback and run per type only when Apple's detector
    /// returned nothing of that type. `extractDetectedData` records why it is not simply deleted.
    nonisolated private static func patternEntities(
        in transcript: String,
        excluding covered: Set<DetectedEntity.EntityType>
    ) -> [DetectedEntity] {
        let patterns: [(DetectedEntity.EntityType, String)] = [
            (.email, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
            (.phoneNumber, #"(?:\+?1[-.]?)?\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}"#),
            (.url, #"https?://[^\s<>"']+"#),
            (.money, #"(?:[$€£]\s*\d+(?:[.,]\d{2})?|\d+(?:[.,]\d{2})?\s*(?:USD|EUR|GBP))"#),
            (.date, #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}"#)
        ]

        var entities: [DetectedEntity] = []
        let whole = NSRange(transcript.startIndex..., in: transcript)

        for (type, pattern) in patterns where !covered.contains(type) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: transcript, range: whole) {
                guard let range = Range(match.range, in: transcript) else { continue }
                let value = String(transcript[range])
                entities.append(DetectedEntity(type: type, value: value, rawText: value))
            }
        }
        return entities
    }

    // MARK: - RecognizeTextRequest Fallback (Robust OCR)

    /// The page's text lines read in four overlapping quarters (2 x 2, 8% overlap) with no minimum text height, mapped to
    /// the page's normalized coordinates (origin bottom left), duplicates from the overlaps removed (5.8). Measured on this
    /// Mac on 2026-11-08 (synthetic pages, RecognizeDocumentsRequest revision 1): Vision reads 3 to 4.5 point print at
    /// 0 to 0.33 of its words from the whole page at any resolution, and at 0.92 to 1.00 from quarters
    /// (`BenchmarkRuns/2026-11-08-extraction-fidelity`, small-text research). SAHI's sliced inference is the published
    /// precedent (Akyon et al., ICIP 2022, arXiv 2202.06934). Used on pages without a text layer, as the coverage
    /// pass's source of lines.
    private func tiledTextLines(on image: CGImage, customWords: [String]) async -> [TextLayerWord] {
        let overlap: CGFloat = 0.08
        let half = 0.5 + overlap / 2
        let tiles = [
            NormalizedRect(x: 0, y: 0, width: half, height: half),
            NormalizedRect(x: 1 - half, y: 0, width: half, height: half),
            NormalizedRect(x: 0, y: 1 - half, width: half, height: half),
            NormalizedRect(x: 1 - half, y: 1 - half, width: half, height: half),
        ]
        var lines: [(text: String, box: CGRect, confidence: Float)] = []
        for tile in tiles {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeightFraction = 0.0
            request.recognitionLanguages = OCRConfiguration.recognitionLanguages.compactMap { Locale.Language(identifier: $0) }
            request.customWords = customWords
            request.regionOfInterest = tile
            let configured = request
            guard
                let observations = try? await VisionOCRThrottle.performAsync({
                    try await configured.perform(on: image)
                })
            else { continue }
            for observation in observations {
                guard let best = observation.topCandidates(1).first, best.confidence > 0.5, !best.string.isEmpty else { continue }
                let box = observation.boundingBox.toImageCoordinates(from: tile, imageSize: CGSize(width: 1, height: 1))
                lines.append((best.string, box, best.confidence))
            }
        }
        // A line crossing the middle is read in two pieces, one from each side's quarters: pieces on one line that meet
        // inside the overlap strip are joined, the words both read in the strip once (refuting review, 2026-11-08).
        let seam = 0.5
        var merged: [(text: String, box: CGRect, confidence: Float)] = []
        var used = Set<Int>()
        for (i, left) in lines.enumerated() where !used.contains(i) && left.box.maxX > seam && left.box.minX < seam - overlap / 2 {
            guard
                let j = lines.indices.first(where: { j in
                    let right = lines[j].box
                    return j != i && !used.contains(j) && right.minX < seam && right.maxX > seam + overlap / 2
                        && min(left.box.maxY, right.maxY) - max(left.box.minY, right.minY)
                            > 0.5 * min(left.box.height, right.height)
                })
            else { continue }
            let leftWords = left.text.split(separator: " ").map(String.init)
            let rightWords = lines[j].text.split(separator: " ").map(String.init)
            var shared = 0
            for size in stride(from: min(leftWords.count, rightWords.count), through: 1, by: -1)
            where Array(leftWords.suffix(size)) == Array(rightWords.prefix(size)) {
                shared = size
                break
            }
            let text = (leftWords + rightWords.dropFirst(shared)).joined(separator: " ")
            merged.append((text, left.box.union(lines[j].box), min(left.confidence, lines[j].confidence)))
            used.insert(i)
            used.insert(j)
        }
        lines = merged + lines.enumerated().filter { !used.contains($0.offset) }.map(\.element)
        // A line read twice where quarters overlap: the one with more characters is kept.
        var kept: [(text: String, box: CGRect, confidence: Float)] = []
        for line in lines.sorted(by: { $0.text.count > $1.text.count }) {
            let duplicate = kept.contains { other in
                let intersection = other.box.intersection(line.box)
                guard !intersection.isNull else { return false }
                return intersection.width * intersection.height >= 0.5 * line.box.width * line.box.height
            }
            if !duplicate { kept.append(line) }
        }
        return kept.map { TextLayerWord(text: $0.text, box: $0.box) }
    }

    /// Use RecognizeTextRequest as a fallback when RecognizeDocumentsRequest fails
    /// or produces low-quality results. RecognizeTextRequest is more robust for:
    /// - Low-quality scans (50-75 DPI)
    /// - Documents with unusual layouts
    /// - Images with poor lighting or contrast
    ///
    /// Available from iOS 18.0+ (not iOS 26 specific)
    private func performTextRecognitionFallback(on image: CGImage, customWords: [String]) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeightFraction = 0.0
        request.recognitionLanguages = OCRConfiguration.recognitionLanguages.compactMap {
            Locale.Language(identifier: $0)
        }
        request.customWords = customWords

        let configuredRequest = request
        let recognizedText = try await VisionOCRThrottle.performAsync { [self] in
            let observations = try await configuredRequest.perform(on: image)
            return await self.assembleSpatiallyOrderedFallbackText(from: observations)
        }

        Log.debug("[StructuredDocumentParser] RecognizeTextRequest fallback captured \(recognizedText.count) chars", category: .ingestion)
        return recognizedText
    }

    private func assembleSpatiallyOrderedFallbackText(from observations: [RecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        let xMidpoints = observations.map { $0.boundingBox.cgRect.midX }
        let columns = detectFallbackColumns(from: xMidpoints)

        guard columns.count > 1 else {
            return buildFallbackReadingBlocks(from: observations)
                .map(\.text)
                .joined(separator: "\n")
        }

        var columnGroups: [[RecognizedTextObservation]] = Array(repeating: [], count: columns.count)

        for observation in observations {
            let xMid = observation.boundingBox.cgRect.midX
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

        let columnTexts = columnGroups.compactMap { group -> String? in
            let text = buildFallbackReadingBlocks(from: group)
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        return columnTexts.joined(separator: "\n\n")
    }

    private func buildFallbackReadingBlocks(from observations: [RecognizedTextObservation]) -> [OCRFallbackReadingBlock] {
        guard !observations.isEmpty else { return [] }

        let lineThreshold: CGFloat = 0.02
        let sorted = observations.sorted { lhs, rhs in
            let leftBox = lhs.boundingBox.cgRect
            let rightBox = rhs.boundingBox.cgRect

            if abs(leftBox.midY - rightBox.midY) > lineThreshold {
                return leftBox.midY > rightBox.midY
            }
            return leftBox.minX < rightBox.minX
        }

        var blocks: [OCRFallbackReadingBlock] = []
        var currentLine: [RecognizedTextObservation] = []
        var currentY: CGFloat?

        func flushCurrentLine() {
            guard !currentLine.isEmpty else { return }

            let orderedLine = currentLine.sorted { $0.boundingBox.cgRect.minX < $1.boundingBox.cgRect.minX }
            let lineText = orderedLine
                .compactMap { fallbackCandidateText(from: $0) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !lineText.isEmpty {
                blocks.append(OCRFallbackReadingBlock(
                    text: lineText,
                    topY: orderedLine.map { $0.boundingBox.cgRect.maxY }.max() ?? 0,
                    minX: orderedLine.map { $0.boundingBox.cgRect.minX }.min() ?? 0
                ))
            }

            currentLine.removeAll(keepingCapacity: true)
        }

        for observation in sorted {
            let y = observation.boundingBox.cgRect.midY

            if let previousY = currentY, abs(y - previousY) >= lineThreshold {
                flushCurrentLine()
            }

            currentLine.append(observation)
            currentY = y
        }

        flushCurrentLine()
        return blocks.sorted { lhs, rhs in
            if abs(lhs.topY - rhs.topY) > 0.02 {
                return lhs.topY > rhs.topY
            }
            return lhs.minX < rhs.minX
        }
    }

    private func fallbackCandidateText(from observation: RecognizedTextObservation) -> String? {
        let bestText = observation.topCandidates(1).first?.string ?? observation.transcript
        let trimmed = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let deconfused = deconfuseCyrillicLatin(trimmed)
        let corrected = fixReversedTextIfNeeded(deconfused)
        let (cleaned, _) = validateAndCleanOCR(corrected)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func detectFallbackColumns(from xMidpoints: [CGFloat]) -> [CGFloat] {
        guard xMidpoints.count > 3 else { return [] }

        let sorted = xMidpoints.sorted()
        var gaps: [(position: CGFloat, gap: CGFloat)] = []

        for index in 1..<sorted.count {
            let gap = sorted[index] - sorted[index - 1]
            gaps.append((position: (sorted[index] + sorted[index - 1]) / 2, gap: gap))
        }

        let significantGapThreshold: CGFloat = 0.15
        let columnBoundaries = gaps
            .filter { $0.gap > significantGapThreshold }
            .map { $0.position }

        if columnBoundaries.isEmpty {
            return [sorted.reduce(0, +) / CGFloat(sorted.count)]
        }

        var centers: [CGFloat] = []
        var previousBoundary: CGFloat = 0

        for boundary in columnBoundaries.sorted() {
            centers.append((previousBoundary + boundary) / 2)
            previousBoundary = boundary
        }
        centers.append((previousBoundary + 1.0) / 2)

        return centers
    }

    nonisolated private func imageToData(_ ciImage: CIImage) -> Data? {
        #if canImport(UIKit)
        // CIContext is thread-safe per Apple docs — no dispatch queue needed
        guard let renderedImage = sharedGPUContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        // Convert to opaque image to avoid "AlphaPremulLast" warning
        // PDF pages are opaque - including alpha doubles memory during decode
        let width = renderedImage.width
        let height = renderedImage.height

        // Use UIGraphicsImageRenderer with opaque format for optimal memory
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1.0

        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let opaqueImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.draw(renderedImage, in: CGRect(origin: .zero, size: size))
        }

        // PNG (lossless) for Vision processing — JPEG compression degrades fine
        // details like decimal points, thin serifs, and small numbers in table cells.
        // The ~3× size increase is worth it for OCR accuracy on numeric data.
        return opaqueImage.pngData()
        #else
        return nil
        #endif
    }

    // MARK: - OCR Quality Validation

    /// Common English words for OCR quality validation
    /// Used to detect garbled text that has too few recognizable words
    private static let commonWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
        "from", "as", "is", "was", "are", "were", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall",
        "this", "that", "these", "those", "it", "its", "you", "your", "we", "our", "they", "their",
        "if", "then", "when", "where", "what", "which", "who", "how", "why", "can", "all", "each",
        "not", "no", "yes", "so", "up", "out", "about", "into", "over", "after", "before", "between",
        "under", "again", "further", "once", "here", "there", "any", "both", "few", "more", "most",
        "other", "some", "such", "only", "own", "same", "than", "too", "very", "just", "also",
        "now", "new", "first", "last", "long", "great", "little", "right", "old", "big", "high",
        "different", "small", "large", "next", "early", "young", "important", "public", "good",
        "same", "able", "use", "using", "used", "click", "press", "button", "device", "system",
        "file", "page", "user", "version", "update", "install", "download", "setup", "settings",
        "default", "password", "login", "admin", "network", "connect", "connection", "cable",
        "power", "port", "address", "follow", "step", "refer", "manual", "note", "see", "check"
    ]

    /// Validate OCR quality and clean text
    /// Returns (cleanedText, isLowQuality) - NEVER discards content, just flags it
    /// This ensures we don't lose information from low-quality scans
    nonisolated private func validateAndCleanOCR(_ text: String) -> (String, Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", false) }

        // Clean first
        let cleaned = cleanOCRText(trimmed)

        // Very short text is fine
        guard cleaned.count > 10 else { return (cleaned, false) }

        // Calculate quality metrics
        let chars = Array(cleaned)
        let totalChars = chars.count
        var unusualCharCount = 0
        var maxConsecutiveNonAlpha = 0
        var consecutiveNonAlpha = 0

        let unusualChars = CharacterSet(charactersIn: "ᅡᄀᄒ↓₹☁️✅⭕️🔍📚📦📑📝📊ℹ️⚠️💡🎯🔧🔥🔗☁️🧾თკმიცნევრუსउন")

        for char in chars {
            if char.isLetter {
                consecutiveNonAlpha = 0
            } else {
                if char.unicodeScalars.first.map({ unusualChars.contains($0) }) == true {
                    unusualCharCount += 1
                }
                consecutiveNonAlpha += 1
                maxConsecutiveNonAlpha = max(maxConsecutiveNonAlpha, consecutiveNonAlpha)
            }
        }

        // Check for recognizable words
        let words = cleaned.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        var isLowQuality = false

        // High unusual char ratio
        let unusualRatio = Double(unusualCharCount) / Double(totalChars)
        if unusualRatio > 0.05 {
            isLowQuality = true
        }

        // Very long non-alpha runs
        if maxConsecutiveNonAlpha > 20 {
            isLowQuality = true
        }

        // Low word recognition rate (but only for longer text)
        if words.count >= 8 {
            let recognizedCount = words.filter { Self.commonWords.contains($0) }.count
            let recognitionRate = Double(recognizedCount) / Double(words.count)
            if recognitionRate < 0.15 {
                isLowQuality = true
            }
        }

        return (cleaned, isLowQuality)
    }

    // MARK: - Cyrillic/Latin Deconfusion & Reversed Text Detection

    /// Fix Cyrillic characters that Vision OCR substitutes for visually-similar Latin characters
    /// Common in scanned PDFs where the text layer has encoding issues
    nonisolated private func deconfuseCyrillicLatin(_ text: String) -> String {
        // Only apply if text contains Cyrillic characters mixed with Latin
        let hasCyrillic = text.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
        guard hasCyrillic else { return text }

        // Check if it's genuinely Cyrillic text (mostly Cyrillic) vs OCR confusion (mostly Latin)
        let cyrillicCount = text.unicodeScalars.filter { $0.value >= 0x0400 && $0.value <= 0x04FF }.count
        let latinCount = text.unicodeScalars.filter { ($0.value >= 0x0041 && $0.value <= 0x005A) || ($0.value >= 0x0061 && $0.value <= 0x007A) }.count
        let totalLetters = cyrillicCount + latinCount

        // If mostly Cyrillic (>60%), it's probably real Cyrillic text — leave it alone
        guard totalLetters > 0, Double(cyrillicCount) / Double(totalLetters) < 0.6 else { return text }

        // Cyrillic → Latin lookalike map (visually similar characters Vision confuses)
        let deconfusionMap: [Character: Character] = [
            "\u{0410}": "A",  // А → A
            "\u{0412}": "B",  // В → B
            "\u{0421}": "C",  // С → C
            "\u{0415}": "E",  // Е → E
            "\u{041D}": "H",  // Н → H
            "\u{041A}": "K",  // К → K
            "\u{041C}": "M",  // М → M
            "\u{041E}": "O",  // О → O
            "\u{0420}": "P",  // Р → P
            "\u{0422}": "T",  // Т → T
            "\u{0425}": "X",  // Х → X
            "\u{042F}": "R",  // Я → R (reversed R shape)
            "\u{0430}": "a",  // а → a
            "\u{0435}": "e",  // е → e
            "\u{043E}": "o",  // о → o
            "\u{0440}": "p",  // р → p
            "\u{0441}": "c",  // с → c
            "\u{0443}": "y",  // у → y
            "\u{0445}": "x",  // х → x
            "\u{0434}": "d",  // д → d (approximate)
            "\u{0438}": "u",  // и → u (approximate, reversed N)
            "\u{043D}": "h",  // н → h
        ]

        var result = ""
        for char in text {
            if let replacement = deconfusionMap[char] {
                result.append(replacement)
            } else {
                result.append(char)
            }
        }

        if result != text {
            Log.debug("[StructuredDocumentParser] Deconfused Cyrillic→Latin: '\(text.prefix(40))' → '\(result.prefix(40))'", category: .ingestion)
        }

        return result
    }

    /// Detect and fix reversed text from broken PDF text layers
    /// Some PDFs encode text right-to-left, producing "weiv tnorf" instead of "front view"
    nonisolated private func fixReversedTextIfNeeded(_ text: String) -> String {
        // Only attempt for short-to-medium text (section titles, headers, cell values)
        // Long body text reversals are too risky to auto-fix
        guard text.count >= 3 && text.count <= 120 else { return text }

        let alphaWords: [String] = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 2 && word.allSatisfy { $0.isLetter }
            }

        // Skip abbreviation-like or symbol-heavy fragments such as table codes and
        // statistical cells. These often produce false positives like "as" or "at"
        // when reversed, even though the source text is not a reversed phrase.
        let totalAlphaChars = alphaWords.reduce(0) { $0 + $1.count }
        let alphaCharRatio = Double(totalAlphaChars) / Double(max(1, text.count))
        let hasLongAlphaWord = alphaWords.contains { $0.count >= 3 }
        guard !alphaWords.isEmpty, hasLongAlphaWord, alphaCharRatio >= 0.45 else { return text }

        // Split into alphabetic words only, then check if ANY are recognizable English
        let words = alphaWords

        guard words.count >= 1 else { return text }

        let forwardRecognized = words.filter { Self.commonWords.contains($0) }.count
        let forwardRate = Double(forwardRecognized) / Double(words.count)

        // If forward text already has decent recognition, don't reverse
        if forwardRate >= 0.3 { return text }

        // Try reversing each word (keeping word order) — "weiv tnorf" → "view front"
        let reversedWords = text.components(separatedBy: " ").map { word -> String in
            // Only reverse words that are purely alphabetic (don't reverse numbers/codes)
            let isAlphaWord = word.allSatisfy { $0.isLetter || $0 == "-" }
            return isAlphaWord ? String(word.reversed()) : word
        }
        let wordReversed = reversedWords.joined(separator: " ")

        let wordReversedWords = wordReversed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 2 && word.allSatisfy { $0.isLetter }
            }
        let wordReversedRecognized = wordReversedWords.filter { Self.commonWords.contains($0) }.count
        let wordReversedLongRecognized = wordReversedWords.filter { $0.count >= 3 && Self.commonWords.contains($0) }.count
        let wordReversedRate = Double(wordReversedRecognized) / Double(max(1, wordReversedWords.count))

        // Also try full string reversal — "tnorf weiv" → "view front"
        let fullReversed = String(text.reversed())
        let fullReversedWords = fullReversed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= 2 && word.allSatisfy { $0.isLetter }
            }
        let fullReversedRecognized = fullReversedWords.filter { Self.commonWords.contains($0) }.count
        let fullReversedLongRecognized = fullReversedWords.filter { $0.count >= 3 && Self.commonWords.contains($0) }.count
        let fullReversedRate = Double(fullReversedRecognized) / Double(max(1, fullReversedWords.count))

        // Pick the best interpretation (must be significantly better than forward)
        let bestRate = max(wordReversedRate, fullReversedRate)
        let bestRecognizedCount = max(wordReversedRecognized, fullReversedRecognized)
        let bestLongRecognizedCount = max(wordReversedLongRecognized, fullReversedLongRecognized)
        if bestRate > forwardRate
            && bestRate >= 0.25
            && (bestLongRecognizedCount > 0 || bestRecognizedCount >= 2) {
            let bestText = wordReversedRate >= fullReversedRate ? wordReversed : fullReversed
            Log.debug("[StructuredDocumentParser] Fixed reversed text: '\(text.prefix(40))' → '\(bestText.prefix(40))'", category: .ingestion)
            return bestText
        }

        return text
    }

    /// Clean up common OCR errors in text
    nonisolated func cleanOCRText(_ text: String) -> String {
        var cleaned = text

        // Common OCR substitutions - fix obvious errors. Case-sensitive, and a lone lowercase "l" only (5.8): with
        // `.caseInsensitive` the first rule also rewrote a capital L, so "L4-L5" became "14-15" and "Lot L1234" became
        // "Lot 11234", and "ml5" became "m15".
        let substitutions: [(pattern: String, replacement: String, options: NSRegularExpression.Options)] = [
            // Letter-number confusion
            (#"(?<![A-Za-z])l(?=\d)"#, "1", []),           // a lone 'l' before a digit → '1'
            (#"(?<=\d)O(?=\d)"#, "0", []),                 // 'O' between digits → '0'
            (#"(?<=\d)l(?=\d)"#, "1", []),                 // 'l' between digits → '1'
            // Common word fixes (conservative)
            (#"\bthe\s+the\b"#, "the", [.caseInsensitive]),  // doubled "the"
        ]

        for (pattern, replacement, options) in substitutions {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: replacement)
            }
        }

        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum StructuredParsingError: Error, LocalizedError {
    case imageConversionFailed
    case noDocumentDetected
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert page image for structured parsing"
        case .noDocumentDetected:
            return "No document content detected on page"
        case .parsingFailed(let reason):
            return "Structured parsing failed: \(reason)"
        }
    }
}

// MARK: - Chunk Metadata Extension

extension ChunkMetadata {
    /// Create metadata for a structured element
    static func forStructuredElement(
        _ element: StructuredElement,
        chunkIndex: Int,
        startPosition: Int,
        endPosition: Int
    ) -> ChunkMetadata {
        ChunkMetadata(
            chunkIndex: chunkIndex,
            startPosition: startPosition,
            endPosition: endPosition,
            pageNumber: element.pageNumber,
            sectionTitle: nil,
            keywords: [],
            semanticDensity: 0.5,
            hasNumericData: element.elementType == "table",
            hasListStructure: element.elementType == "list",
            wordCount: element.textForEmbedding.split(separator: " ").count,
            characterCount: element.textForEmbedding.count,
            structureType: element.elementType  // NEW: Track structure type
        )
    }
}
