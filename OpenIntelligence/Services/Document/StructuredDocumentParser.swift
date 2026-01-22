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
    nonisolated var textRepresentation: String {
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
    nonisolated var keyValuePairs: [(key: String, value: String)]? {
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
    var effectiveContent: [StructuredElement] {
        // If structured parsing captured less than 50% of raw text, use raw text instead
        if qualityScore < 0.5 && !rawText.isEmpty {
            return [.paragraph(text: rawText, pageNumber: pageNumber)]
        }
        return elements
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
            // RecognizeDocumentsRequest found no document structure
            // Fall back to RecognizeTextRequest for plain text extraction
            Log.info("[StructuredDocumentParser] No document structure on page \(pageNumber), trying RecognizeTextRequest", category: .ingestion)
            do {
                let fallbackText = try await performTextRecognitionFallback(on: imageData)
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

        // Extract structured elements
        var elements: [StructuredElement] = []
        var figureReferences: [String] = []

        // 1. Extract title if present (with OCR quality validation)
        var pageTitle: String? = nil
        if let title = document.title {
            let rawTitle = title.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // Clean and validate title - flag but don't discard
            let (cleanedTitle, isLowQuality) = validateAndCleanOCR(rawTitle)
            if !cleanedTitle.isEmpty {
                let finalTitle = isLowQuality ? "[OCR unclear] \(cleanedTitle)" : cleanedTitle
                pageTitle = finalTitle
                elements.append(.title(text: finalTitle, pageNumber: pageNumber))
                Log.debug("[StructuredDocumentParser] Found title: \(cleanedTitle.prefix(50))...\(isLowQuality ? " (low quality)" : "")", category: .ingestion)
            }
        }

        // Collect figure/diagram references from paragraphs
        // These help users understand what visual content exists even if we can't describe it
        let figurePatterns = [
            #"(?i)(?:see\s+)?(?:figure|fig\.?|diagram|illustration|image|photo|picture)\s*\d*\s*[:\-]?\s*[^.]*"#,
            #"(?i)as\s+shown\s+(?:in\s+)?(?:the\s+)?(?:figure|diagram|image)"#,
            #"(?i)refer\s+to\s+(?:the\s+)?(?:figure|diagram|image)"#
        ]

        // 2. Extract tables - preserves structured data (specs, schedules, comparisons)
        // Trust Vision's table detection - these are REAL tables
        for (_, table) in document.tables.enumerated() {
            let tableData = parseTable(table, pageNumber: pageNumber, caption: pageTitle)
            elements.append(.table(tableData))
            Log.debug("[StructuredDocumentParser] Found table with \(tableData.rows.count) rows on page \(pageNumber)", category: .ingestion)
        }

        // 3. Extract lists (bullet points, numbered items)
        for list in document.lists {
            let items = parseList(list)
            if !items.isEmpty {
                elements.append(.list(items: items, pageNumber: pageNumber))
                Log.debug("[StructuredDocumentParser] Found list with \(items.count) items on page \(pageNumber)", category: .ingestion)
            }
        }

        // 4. Extract paragraphs - TRUST Vision's classification, don't re-parse
        // The key insight: Vision already determined what's a paragraph vs table
        // Re-parsing as "spec blocks" was FRAGMENTING content unnecessarily
        for paragraph in document.paragraphs {
            let rawText = paragraph.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate and clean, but FLAG don't discard
            let (cleanedText, isLowQuality) = validateAndCleanOCR(rawText)

            if !cleanedText.isEmpty && cleanedText.count > 10 {
                // Check for figure references
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

                // Add paragraph with quality flag if needed
                let finalText = isLowQuality ? "[OCR quality: low] \(cleanedText)" : cleanedText
                elements.append(.paragraph(text: finalText, pageNumber: pageNumber))
            }
        }

        // Get raw text from structured parsing
        var rawText = document.text.transcript

        // Calculate quality score: how much content did structured parsing capture?
        // If structured elements have significantly fewer words than raw text, quality is low
        let structuredWordCount = elements.reduce(0) { $0 + $1.textForEmbedding.split(separator: " ").count }
        var rawWordCount = rawText.split(separator: " ").count
        var qualityScore: Double = rawWordCount > 0 ? min(1.0, Double(structuredWordCount) / Double(rawWordCount)) : 1.0

        // ENHANCEMENT: Use RecognizeTextRequest fallback for very low quality parsing
        // This is more robust for low-DPI scans, unusual layouts, etc.
        if qualityScore < 0.3 || (rawWordCount < 10 && elements.isEmpty) {
            Log.info("[StructuredDocumentParser] Quality too low (\(Int(qualityScore * 100))%), trying RecognizeTextRequest fallback", category: .ingestion)
            do {
                let fallbackText = try await performTextRecognitionFallback(on: imageData)
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
        Log.info("[StructuredDocumentParser] Parsed page \(pageNumber): \(elements.count) elements (\(document.tables.count) tables, \(document.lists.count) lists) quality=\(Int(qualityScore * 100))% in \(String(format: "%.2f", elapsed))s", category: .ingestion)

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
    private func performTextRecognitionFallback(on imageData: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate  // Prioritize accuracy over speed
        request.usesLanguageCorrection = true // Apply language model corrections
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: imageData)

        // Combine all recognized text observations
        let recognizedText = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        Log.debug("[StructuredDocumentParser] RecognizeTextRequest fallback captured \(recognizedText.count) chars", category: .ingestion)
        return recognizedText
    }

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
