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

#if canImport(UIKit)
import UIKit
#endif

/// Represents a structured element extracted from a document
enum StructuredElement: Sendable {
    case paragraph(text: String, pageNumber: Int)
    case table(TableData)
    case list(items: [String], pageNumber: Int)
    case title(text: String, pageNumber: Int)

    /// The raw text content, formatted for embedding/retrieval
    var textForEmbedding: String {
        switch self {
        case .paragraph(let text, _):
            return text
        case .table(let data):
            return data.textRepresentation
        case .list(let items, _):
            return items.joined(separator: "\n• ")
        case .title(let text, _):
            return text
        }
    }

    var pageNumber: Int {
        switch self {
        case .paragraph(_, let page), .list(_, let page), .title(_, let page):
            return page
        case .table(let data):
            return data.pageNumber
        }
    }

    var elementType: String {
        switch self {
        case .paragraph: return "paragraph"
        case .table: return "table"
        case .list: return "list"
        case .title: return "title"
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
    var searchableText: String {
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

/// Represents a parsed table with row/column structure preserved
struct TableData: Sendable {
    let pageNumber: Int
    let rows: [[String]]  // rows[rowIndex][colIndex] = cell text
    let headerRow: [String]?  // First row if detected as header
    let caption: String?  // Table caption if detected nearby
    let detectedEntities: [DetectedEntity]  // Auto-detected data (emails, phones, dates, etc.)

    /// Convert table to a text representation that preserves structure for retrieval
    /// Format includes both table format AND key-value pairs for better searchability
    /// Example: "Table: Oil Specifications\nEngine Oil: 0W-20\nCapacity: 4.5L\n| Engine Oil | 0W-20 |..."
    var textRepresentation: String {
        var lines: [String] = []

        if let caption = caption, !caption.isEmpty {
            lines.append("Table: \(caption)")
        } else {
            lines.append("Table:")
        }

        // ENHANCEMENT: For 2-column tables, add key-value pairs for better retrieval
        // This helps queries like "what oil" match "Engine Oil: 0W-20"
        if let kvPairs = keyValuePairs, !kvPairs.isEmpty {
            for (key, value) in kvPairs {
                lines.append("\(key): \(value)")
            }
            lines.append("")  // Blank line before table format
        }

        // ENHANCEMENT: Add detected entities for better searchability
        // Vision automatically extracts emails, phones, dates, URLs, etc.
        if !detectedEntities.isEmpty {
            lines.append("[Detected Data]")
            for entity in detectedEntities {
                lines.append(entity.searchableText)
            }
            lines.append("")
        }

        for (index, row) in rows.enumerated() {
            let formattedRow = "| " + row.joined(separator: " | ") + " |"
            lines.append(formattedRow)

            // Add separator after header row
            if index == 0 && headerRow != nil {
                let separator = "|" + row.map { _ in "---" }.joined(separator: "|") + "|"
                lines.append(separator)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Key-value representation for specs tables (e.g., "Dosage: 500mg", "Part #: API-1234")
    /// Useful when table has 2 columns: property name and value
    var keyValuePairs: [(key: String, value: String)]? {
        guard let firstRow = rows.first, firstRow.count == 2 else { return nil }

        return rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            let key = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty && !value.isEmpty else { return nil }
            return (key: key, value: value)
        }
    }
}

/// Result of parsing a document page with structure
struct StructuredPageContent: Sendable {
    let pageNumber: Int
    let elements: [StructuredElement]
    let rawText: String  // Fallback plain text

    var hasStructuredContent: Bool {
        elements.contains { element in
            switch element {
            case .table, .list: return true
            default: return false
            }
        }
    }
}

/// Service for structure-aware document parsing using iOS 26+ Vision APIs
@available(iOS 26.0, *)
actor StructuredDocumentParser {

    static let shared = StructuredDocumentParser()

    private init() {}

    // MARK: - Public API

    /// Parse a PDF page image and extract structured elements (tables, paragraphs, lists)
    /// - Parameters:
    ///   - image: CIImage of the rendered PDF page
    ///   - pageNumber: 1-indexed page number for metadata
    /// - Returns: Structured content with separated elements
    func parsePageImage(_ image: CIImage, pageNumber: Int) async throws -> StructuredPageContent {
        let startTime = Date()

        // Convert CIImage to Data for Vision request
        guard let imageData = imageToData(image) else {
            Log.warning("[StructuredDocumentParser] Failed to convert image to data, falling back to OCR", category: .ingestion)
            throw StructuredParsingError.imageConversionFailed
        }

        // Create and configure the request
        // RecognizeDocumentsRequest is simpler in iOS 26 - it handles text recognition internally
        let request = RecognizeDocumentsRequest()

        // Perform the structured document recognition
        let observations = try await request.perform(on: imageData)

        guard let document = observations.first?.document else {
            Log.debug("[StructuredDocumentParser] No document detected on page \(pageNumber)", category: .ingestion)
            throw StructuredParsingError.noDocumentDetected
        }

        // Extract structured elements
        var elements: [StructuredElement] = []

        // 1. Extract title if present
        var pageTitle: String? = nil
        if let title = document.title {
            let titleText = title.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleText.isEmpty {
                pageTitle = titleText
                elements.append(.title(text: titleText, pageNumber: pageNumber))
                Log.debug("[StructuredDocumentParser] Found title: \(titleText.prefix(50))...", category: .ingestion)
            }
        }

        // Collect short paragraphs that might be table captions (e.g., "Table 1: Oil Specifications")
        // These are typically short (< 100 chars) and contain keywords like "table", "figure", etc.
        let potentialCaptions = document.paragraphs.compactMap { para -> String? in
            let text = para.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count < 100 && text.count > 5 {
                let lower = text.lowercased()
                if lower.contains("table") || lower.contains("figure") || lower.contains("specification") ||
                   lower.contains("schedule") || lower.contains("summary") || text.hasSuffix(":") {
                    return text
                }
            }
            return nil
        }

        // 2. Extract tables - preserves structured data (specs, schedules, comparisons)
        for (tableIndex, table) in document.tables.enumerated() {
            // Try to find a caption for this table
            let caption: String? = {
                if tableIndex < potentialCaptions.count {
                    return potentialCaptions[tableIndex]
                }
                // Fall back to page title if no caption found
                return pageTitle
            }()

            let tableData = parseTable(table, pageNumber: pageNumber, caption: caption)
            elements.append(.table(tableData))
            Log.debug("[StructuredDocumentParser] Found table with \(tableData.rows.count) rows on page \(pageNumber), caption: \(caption ?? "none")", category: .ingestion)
        }

        // 3. Extract lists (bullet points, numbered items)
        for list in document.lists {
            let items = parseList(list)
            if !items.isEmpty {
                elements.append(.list(items: items, pageNumber: pageNumber))
                Log.debug("[StructuredDocumentParser] Found list with \(items.count) items on page \(pageNumber)", category: .ingestion)
            }
        }

        // 4. Extract paragraphs (body text) - exclude those used as captions
        // ENHANCED: Detect definition lists/spec blocks within paragraph text
        let captionSet = Set(potentialCaptions)
        for paragraph in document.paragraphs {
            let text = paragraph.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && text.count > 20 && !captionSet.contains(text) {
                // Check if this "paragraph" is actually a definition list or spec block
                if let specTable = detectSpecificationBlock(text, pageNumber: pageNumber) {
                    elements.append(.table(specTable))
                    Log.debug("[StructuredDocumentParser] Detected spec block in paragraph: \(text.prefix(50))...", category: .ingestion)
                } else {
                    elements.append(.paragraph(text: text, pageNumber: pageNumber))
                }
            }
        }

        // Get raw text as fallback
        let rawText = document.text.transcript

        let elapsed = Date().timeIntervalSince(startTime)
        Log.info("[StructuredDocumentParser] Parsed page \(pageNumber): \(elements.count) elements (\(document.tables.count) tables, \(document.lists.count) lists) in \(String(format: "%.2f", elapsed))s", category: .ingestion)

        return StructuredPageContent(
            pageNumber: pageNumber,
            elements: elements,
            rawText: rawText
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

        for row in table.rows {
            var cellTexts: [String] = []
            for cell in row {
                let text = cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                cellTexts.append(text)

                // ENHANCEMENT: Extract detected data from Vision's DataDetection
                // This automatically finds emails, phone numbers, dates, URLs, etc.
                let cellEntities = extractDetectedData(from: cell.content.text)
                detectedEntities.append(contentsOf: cellEntities)
            }
            rows.append(cellTexts)
        }

        // Detect if first row looks like a header (often bold/larger, or contains common header words)
        let headerRow: [String]? = {
            guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }
            let headerKeywords = ["specification", "description", "type", "value", "name", "capacity", "grade", "viscosity", "quantity", "unit", "item", "part", "number"]
            let looksLikeHeader = firstRow.contains { cell in
                headerKeywords.contains { cell.lowercased().contains($0) }
            }
            return looksLikeHeader ? firstRow : nil
        }()

        // Deduplicate entities
        let uniqueEntities = Array(Set(detectedEntities))

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

    private func parseList(_ list: DocumentObservation.Container.List) -> [String] {
        var items: [String] = []

        for item in list.items {
            let text = item.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(text)
            }
        }

        return items
    }

    // MARK: - Specification Block Detection (Definition Lists in Paragraph Text)

    /// Detect if a paragraph contains a specification block pattern
    /// Uses shared SpecificationDetector for consistent pattern matching
    /// Returns TableData if detected, allowing it to be chunked with key-value format
    private func detectSpecificationBlock(_ text: String, pageNumber: Int) -> TableData? {
        // Use shared detector to find specifications
        let specs = SpecificationDetector.detectSpecifications(in: text)

        // Need at least 2 spec values to be considered a spec block
        guard specs.count >= 2 else { return nil }

        // Try to detect a heading for this spec block
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var heading: String? = nil

        for line in lines.prefix(3) {  // Check first 3 lines for heading
            if SpecificationDetector.isSpecificationHeading(line) {
                heading = line.trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
                break
            }
        }

        // Build a synthetic table from the spec matches
        var rows: [[String]] = []

        // Add heading as first row if found
        if let heading = heading {
            rows.append(["Specification", heading])
        }

        // Add spec values as key-value rows
        // Group by category to avoid duplicates
        var seenValues = Set<String>()
        for spec in specs {
            let normalizedValue = spec.value.trimmingCharacters(in: .whitespaces)
            if !seenValues.contains(normalizedValue) {
                seenValues.insert(normalizedValue)
                rows.append([spec.category, normalizedValue])
            }
        }

        // Only create table if we have meaningful content
        guard rows.count >= 2 else { return nil }

        Log.info("[StructuredDocumentParser] Detected spec block: \(specs.count) specs, heading=\(heading ?? "none")", category: .ingestion)

        return TableData(
            pageNumber: pageNumber,
            rows: rows,
            headerRow: rows.first,
            caption: heading ?? "Specifications",
            detectedEntities: []  // Spec blocks don't have Vision-detected entities
        )
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

    // Note: Full Vision DataDetection API integration placeholder
    // When Apple's API stabilizes, this can be expanded:
    // for detectedMatch in text.detectedData {
    //     switch detectedMatch.match { ... }
    // }

    nonisolated private func imageToData(_ ciImage: CIImage) -> Data? {
        #if canImport(UIKit)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.9)
        #else
        return nil
        #endif
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
