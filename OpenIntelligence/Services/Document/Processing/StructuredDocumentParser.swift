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
    ///                                → [("Component", "Motor"), ("Type", "Brushless"), ("Rating", "500W")]
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

        // Use headers as keys for each cell value
        for row in dataRows {
            for (colIndex, header) in headers.enumerated() {
                guard colIndex < row.count else { continue }
                let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
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

    nonisolated var hasStructuredContent: Bool {
        elements.contains { element in
            switch element {
            case .table, .list: return true
            default: return false
            }
        }
    }

    /// Use structured elements if quality is good, otherwise fall back to raw text
    nonisolated var effectiveContent: [StructuredElement] {
        // If structured parsing captured less than 50% of raw text, use raw text instead
        if qualityScore < 0.5 && !rawText.isEmpty && !hasStructuredContent {
            return [.paragraph(text: rawText, pageNumber: pageNumber)]
        }
        return elements
    }
}

/// Service for structure-aware document parsing using iOS 26+ Vision APIs
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
    func parsePageImage(
        _ image: CIImage,
        pageNumber: Int,
        customWords: [String],
        nativeWordCount: Int? = nil,
        preferFullResolution: Bool = false
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
        // caller as high fidelity critical.
        //
        // CIImage.transformed(by:) is lazy — no pixel allocation until createCGImage fires.
        let structureImage = preferFullResolution
            ? image
            : image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))

        // Convert scaled CIImage to Data for RecognizeDocumentsRequest (structure detection only).
        // The original full-resolution image is retained separately for the VNRecognizeTextRequest
        // fallback path, which is a pure OCR path where 360 DPI matters for fine print.
        guard let structureImageData = imageToData(structureImage) else {
            Log.warning("[StructuredDocumentParser] Failed to convert image to data, falling back to OCR", category: .ingestion)
            throw StructuredParsingError.imageConversionFailed
        }
        // Lazily produce full-res data only if the OCR fallback path is actually needed.
        // Avoids the memory cost on the happy path (structure found).
        lazy var fullResImageData: Data? = imageToData(image)

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
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.minimumTextHeightFraction = 0.0  // Detect all text sizes
        // Recognition languages in priority order - Latin first to prevent CJK misrecognition
        // of bullet symbols and other non-text glyphs
        request.textRecognitionOptions.recognitionLanguages = OCRConfiguration.recognitionLanguages.compactMap {
            Locale.Language(identifier: $0)
        }

        // Perform the structured document recognition (throttled to prevent Metal GPU races)
        let configuredRequest = request
        let structuredSnapshot: StructuredDocumentSnapshot? = try await VisionOCRThrottle.performAsync { [self] in
            let observations = try await configuredRequest.perform(on: structureImageData)
            guard let document = observations.first?.document else {
                return nil
            }

            return await self.makeStructuredDocumentSnapshot(from: document, pageNumber: pageNumber)
        }

        guard let structuredSnapshot else {
            // RecognizeDocumentsRequest found no document structure
            // Fall back to RecognizeTextRequest for plain text extraction.
            // Use full-resolution image here — VNRecognizeTextRequest is pure OCR and benefits
            // from 360 DPI for fine print, footnotes, and small table cell text.
            Log.info("[StructuredDocumentParser] No document structure on page \(pageNumber), trying RecognizeTextRequest", category: .ingestion)
            do {
                let fallbackText = try await performTextRecognitionFallback(on: fullResImageData ?? structureImageData, customWords: customWords)
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
                let fallbackText = try await performTextRecognitionFallback(on: fullResImageData ?? structureImageData, customWords: customWords)
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
        Log.info("[StructuredDocumentParser] Parsed page \(pageNumber): \(elements.count) elements (\(structuredSnapshot.tableCount) tables, \(structuredSnapshot.listCount) lists) quality=\(Int(qualityScore * 100))% in \(String(format: "%.2f", elapsed))s", category: .ingestion)

        if !figureReferences.isEmpty {
            Log.debug("[StructuredDocumentParser] Found \(figureReferences.count) figure references on page \(pageNumber)", category: .ingestion)
        }

        return StructuredPageContent(
            pageNumber: pageNumber,
            elements: elements,
            rawText: rawText,
            qualityScore: qualityScore,
            figureReferences: figureReferences
        )
    }

    private func makeStructuredDocumentSnapshot(from document: DocumentObservation.Container, pageNumber: Int) -> StructuredDocumentSnapshot {
        var elements: [StructuredElement] = []
        var figureReferences: [String] = []

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
                Log.debug("[StructuredDocumentParser] Found title: \(cleanedTitle.prefix(50))...\(isLowQuality ? " (low quality)" : "")", category: .ingestion)
            }
        }

        let figurePatterns = [
            #"(?i)(?:see\s+)?(?:figure|fig\.?|diagram|illustration|image|photo|picture)\s*\d*\s*[:\-]?\s*[^.]*"#,
            #"(?i)as\s+shown\s+(?:in\s+)?(?:the\s+)?(?:figure|diagram|image)"#,
            #"(?i)refer\s+to\s+(?:the\s+)?(?:figure|diagram|image)"#
        ]

        for table in document.tables {
            let tableData = parseTable(table, pageNumber: pageNumber, caption: pageTitle)
            elements.append(.table(tableData))
            Log.debug("[StructuredDocumentParser] Found table with \(tableData.rows.count) rows on page \(pageNumber)", category: .ingestion)
        }

        for list in document.lists {
            let items = parseList(list)
            if !items.isEmpty {
                elements.append(.list(items: items, pageNumber: pageNumber))
                Log.debug("[StructuredDocumentParser] Found list with \(items.count) items on page \(pageNumber)", category: .ingestion)
            }
        }

        for paragraph in document.paragraphs {
            var rawParagraphText = paragraph.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            rawParagraphText = deconfuseCyrillicLatin(rawParagraphText)
            rawParagraphText = fixReversedTextIfNeeded(rawParagraphText)
            let (cleanedText, isLowQuality) = validateAndCleanOCR(rawParagraphText)

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
            }
        }

        return StructuredDocumentSnapshot(
            elements: elements,
            figureReferences: figureReferences,
            rawText: document.text.transcript,
            tableCount: document.tables.count,
            listCount: document.lists.count
        )
    }

    /// Check if structured parsing is available on this device
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    // MARK: - Private Helpers

    private func parseTable(_ table: DocumentObservation.Container.Table, pageNumber: Int, caption: String? = nil) -> TableData {
        var rows: [[String]] = []
        var detectedEntities: [DetectedEntity] = []

        var garbledCellCount = 0
        var totalCellCount = 0

        for row in table.rows {
            var cellTexts: [String] = []
            for cell in row {
                var text = normalizeTableCellText(cell.content.text.transcript)
                totalCellCount += 1

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

                cellTexts.append(text)

                // ENHANCEMENT: Extract detected data from Vision's DataDetection
                // This automatically finds emails, phone numbers, dates, URLs, etc.
                let cellEntities = extractDetectedData(from: cell.content.text)
                detectedEntities.append(contentsOf: cellEntities)
            }
            rows.append(cellTexts)
        }

        rows = mergeWrappedContinuationRows(in: rows, pageNumber: pageNumber)

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

    /// Extract detected entities from Vision's automatic data detection
    /// This uses DataDetection to find emails, phones, dates, URLs, etc.
    ///
    /// NOTE: Vision's detectedData API in iOS 26 provides DataDetectorMatch objects.
    /// For now, we extract basic text-based entities using regex patterns.
    /// Full DataDetection integration requires additional API verification.
    private func extractDetectedData(from text: DocumentObservation.Container.Text) -> [DetectedEntity] {
        var entities: [DetectedEntity] = []
        let transcript = text.transcript

        // Use regex-based extraction for common entity types
        // This is more reliable than the evolving DataDetection API

        // Email pattern
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in emailRegex.matches(in: transcript, options: [], range: range) {
                if let matchRange = Range(match.range, in: transcript) {
                    let email = String(transcript[matchRange])
                    entities.append(DetectedEntity(type: .email, value: email, rawText: email))
                }
            }
        }

        // Phone pattern (US format and international)
        let phonePattern = #"(?:\+?1[-.]?)?\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}"#
        if let phoneRegex = try? NSRegularExpression(pattern: phonePattern, options: []) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in phoneRegex.matches(in: transcript, options: [], range: range) {
                if let matchRange = Range(match.range, in: transcript) {
                    let phone = String(transcript[matchRange])
                    entities.append(DetectedEntity(type: .phoneNumber, value: phone, rawText: phone))
                }
            }
        }

        // URL pattern
        let urlPattern = #"https?://[^\s<>"']+"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in urlRegex.matches(in: transcript, options: [], range: range) {
                if let matchRange = Range(match.range, in: transcript) {
                    let url = String(transcript[matchRange])
                    entities.append(DetectedEntity(type: .url, value: url, rawText: url))
                }
            }
        }

        // Money pattern (USD, EUR, GBP)
        let moneyPattern = #"(?:[$€£]\s*\d+(?:[.,]\d{2})?|\d+(?:[.,]\d{2})?\s*(?:USD|EUR|GBP))"#
        if let moneyRegex = try? NSRegularExpression(pattern: moneyPattern, options: []) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in moneyRegex.matches(in: transcript, options: [], range: range) {
                if let matchRange = Range(match.range, in: transcript) {
                    let money = String(transcript[matchRange])
                    entities.append(DetectedEntity(type: .money, value: money, rawText: money))
                }
            }
        }

        // Date patterns (common formats)
        let datePattern = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in dateRegex.matches(in: transcript, options: [], range: range) {
                if let matchRange = Range(match.range, in: transcript) {
                    let date = String(transcript[matchRange])
                    entities.append(DetectedEntity(type: .date, value: date, rawText: date))
                }
            }
        }

        return entities
    }

    // MARK: - RecognizeTextRequest Fallback (Robust OCR)

    /// Use RecognizeTextRequest as a fallback when RecognizeDocumentsRequest fails
    /// or produces low-quality results. RecognizeTextRequest is more robust for:
    /// - Low-quality scans (50-75 DPI)
    /// - Documents with unusual layouts
    /// - Images with poor lighting or contrast
    ///
    /// Available from iOS 18.0+ (not iOS 26 specific)
    private func performTextRecognitionFallback(on imageData: Data, customWords: [String]) async throws -> String {
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
            let observations = try await configuredRequest.perform(on: imageData)
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
    nonisolated private func cleanOCRText(_ text: String) -> String {
        var cleaned = text

        // Common OCR substitutions - fix obvious errors
        let substitutions: [(pattern: String, replacement: String)] = [
            // Letter-number confusion
            (#"(?<![A-Z])l(?=\d)"#, "1"),           // 'l' before digit → '1'
            (#"(?<=\d)O(?=\d)"#, "0"),              // 'O' between digits → '0'
            (#"(?<=\d)l(?=\d)"#, "1"),              // 'l' between digits → '1'
            // Common word fixes (conservative)
            (#"\bthe\s+the\b"#, "the"),             // doubled "the"
        ]

        for (pattern, replacement) in substitutions {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
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
