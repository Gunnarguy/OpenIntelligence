//
//  DocumentProcessor+StructureText.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved from DocumentProcessor+StructuredParsing.swift on 2026-11-07 (5.8 split); only access keywords changed.
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
    func classifyDocumentCategory(
        text: String,
        filename: String,
        documentType: DocumentType,
        structuredElements: [StructuredElementWrapper]
    ) -> DocumentSemanticCategory {
        let lowerFilename = filename.lowercased()
        let sampleLength = max(200, min(text.count / 10, 12000))
        let sample = String(text.prefix(sampleLength)).lowercased()

        var scores: [DocumentSemanticCategory: Double] = [
            .technicalManual: 0,
            .scientificPaper: 0,
            .referenceTable: 0,
            .regulatory: 0,
            .general: 0.25,
        ]

        func add(_ category: DocumentSemanticCategory, _ amount: Double) {
            scores[category, default: 0] += amount
        }

        let strongTechnicalTerms = ["manual", "user guide", "owner", "instructions for use", "ifu", "installation", "troubleshooting", "service manual", "operating instructions"]
        let technicalTerms = ["specifications", "maintenance", "calibration", "setup", "configuration", "controls", "reference manual"]
        let scientificTerms = ["abstract", "introduction", "methods", "materials", "results", "discussion", "conclusion", "references", "doi", "p <", "confidence interval", "randomized", "study"]
        let regulatoryTerms = ["compliance", "regulatory", "iec", "fda", "emc", "warning", "contraindications", "adverse", "authorized representative", "labeling"]
        let referenceTerms = ["table", "specification", "capacity", "dimensions", "part number", "model number", "sku", "compatibility", "matrix", "requirements"]
        let scientificNarrativeSample = isLikelyScientificNarrativeSample(sample)

        for term in strongTechnicalTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.technicalManual, lowerFilename.contains(term) ? 1.2 : 0.7)
        }

        for term in technicalTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.technicalManual, lowerFilename.contains(term) ? 0.8 : 0.45)
        }

        for term in scientificTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.scientificPaper, lowerFilename.contains(term) ? 1.4 : 0.8)
        }

        for term in regulatoryTerms where sample.contains(term) || lowerFilename.contains(term) {
            add(.regulatory, lowerFilename.contains(term) ? 1.6 : 0.9)
        }

        for term in referenceTerms where sample.contains(term) || lowerFilename.contains(term) {
            if scientificNarrativeSample && term == "table" {
                continue
            }
            add(.referenceTable, lowerFilename.contains(term) ? 1.2 : 0.7)
        }

        let tableCount = structuredElements.filter { $0.elementType == "table" }.count
        let trustedTableCount = structuredElements.filter { $0.elementType == "table" && !isRecoveredHeuristicTable($0) }.count
        let listCount = structuredElements.filter { $0.elementType == "list" }.count
        if trustedTableCount >= 3 {
            add(.referenceTable, 0.9)
        } else if tableCount >= 3 && scientificNarrativeSample {
            add(.scientificPaper, 0.2)
        }
        if listCount >= 3 {
            add(.regulatory, 0.25)
        }

        let numericDensity = Double(sample.filter { $0.isNumber }.count) / Double(max(sample.count, 1))
        if numericDensity > 0.08 {
            if !scientificNarrativeSample {
                add(.referenceTable, 0.35)
            }
            add(.scientificPaper, 0.15)
        }

        if scientificNarrativeSample {
            add(.scientificPaper, 0.45)
        }

        if sample.contains("table ") && sample.contains("figure ") {
            add(.scientificPaper, 0.7)
        }

        if sample.contains("error code") || sample.contains("troubleshooting") {
            add(.technicalManual, 0.55)
        }

        let rankedScores = scores.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value > rhs.value
        }

        guard let best = rankedScores.first else { return .general }
        let runnerUp = rankedScores.dropFirst().first?.value ?? 0
        guard best.value >= 0.9, (best.value - runnerUp) >= 0.2 else {
            return .general
        }

        return best.key
    }

    func makeChunkMetadata(
        chunkIndex: Int,
        text: String,
        pageNumber: Int?,
        sectionTitle: String?,
        structureType: String,
        chunkType: ChunkSemanticType,
        documentCategory: DocumentSemanticCategory,
        sectionPath: [String],
        semanticDensity: Float,
        hasNumericData: Bool,
        hasListStructure: Bool,
        entities: [String] = [],
        abbreviations: [String: String] = [:],
        tableTitle: String? = nil,
        siblingGroupId: String? = nil,
        bbox: CGRect? = nil,
        imageContentType: String? = nil,
        imageCaption: String? = nil,
        imageDescription: String? = nil,
        imageExtractedText: String? = nil,
        imageClassifications: [String] = []
    ) -> ChunkMetadata {
        let references = GraphIndexService.extractReferenceTargets(from: text)
        return ChunkMetadata(
            chunkIndex: chunkIndex,
            startPosition: 0,
            endPosition: text.count,
            pageNumber: pageNumber,
            sectionTitle: sectionTitle,
            keywords: extractKeywordsFromStructuredElement(text, type: structureType),
            semanticDensity: semanticDensity,
            hasNumericData: hasNumericData,
            hasListStructure: hasListStructure,
            wordCount: countWords(text),
            characterCount: text.count,
            structureType: structureType,
            siblingGroupId: siblingGroupId,
            entities: entities,
            abbreviations: abbreviations,
            sectionPath: sectionPath.isEmpty ? nil : sectionPath,
            bboxArray: bbox.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] },
            documentCategory: documentCategory,
            chunkType: chunkType,
            tableTitle: tableTitle,
            imageContentType: imageContentType,
            imageCaption: imageCaption,
            imageDescription: imageDescription,
            imageExtractedText: imageExtractedText,
            imageClassifications: imageClassifications,
            hasCrossReferences: !references.isEmpty,
            resolvedReferences: references
        )
    }

    nonisolated func imageClassificationLabels(from analyzed: AnalyzedImage) -> [String] {
        analyzed.classifications
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    nonisolated func resolveFigureTitle(from analyzed: AnalyzedImage) -> String {
        if let caption = normalizedImageContextText(analyzed.associatedCaption, maxLength: 90) {
            return caption
        }

        let typeLabel = analyzed.contentType == .unknown ? "Figure" : analyzed.contentType.rawValue.capitalized
        return "\(typeLabel) on page \(analyzed.pageNumber)"
    }

    private nonisolated func normalizedImageContextText(_ raw: String?, maxLength: Int) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maxLength))
    }

    func buildFigureChunkText(
        analyzed: AnalyzedImage,
        filename: String,
        sectionPath: [String]
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        var lines: [String] = []

        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        }

        lines.append("FIGURE: \(resolveFigureTitle(from: analyzed))")
        lines.append("TYPE: \((analyzed.contentType == .unknown ? "Image" : analyzed.contentType.rawValue.capitalized))")

        let topLabels = imageClassificationLabels(from: analyzed)
        if !topLabels.isEmpty {
            lines.append("CLASSIFICATIONS: \(topLabels.joined(separator: ", "))")
        }

        if let caption = normalizedImageContextText(analyzed.associatedCaption, maxLength: 220) {
            lines.append("CAPTION: \(caption)")
        }

        if let description = normalizedImageContextText(analyzed.description, maxLength: 320) {
            lines.append("SUMMARY: \(description)")
        }

        if let extractedText = normalizedImageContextText(analyzed.extractedText, maxLength: 280) {
            lines.append("LABELS: \(extractedText)")
        }

        if let precedingContext = normalizedImageContextText(analyzed.precedingContext, maxLength: 220) {
            lines.append("NEARBY BEFORE: \(precedingContext)")
        }

        if let followingContext = normalizedImageContextText(analyzed.followingContext, maxLength: 220) {
            lines.append("NEARBY AFTER: \(followingContext)")
        }

        lines.append("SOURCE: \(filename), page \(analyzed.pageNumber)")
        return lines.joined(separator: "\n")
    }

    func resolveTableTitle(tableData: TableData, sectionTitle: String?) -> String {
        if let caption = sanitizeStructuredLabel(tableData.caption ?? "") {
            return caption
        }
        if let sectionTitle, let cleanSection = sanitizeStructuredLabel(sectionTitle) {
            return cleanSection
        }
        return "Table"
    }

    func structuredTablePayload(
        from tableData: TableData,
        tableTitle: String,
        extractionQuality: Double? = nil,
        extractionSource: String? = nil
    ) -> StructuredTablePayload {
        let lowQualityRows = lowQualityRowIndices(for: tableData)
        return StructuredTablePayload(
            title: tableTitle,
            headers: inferredHeaders(for: tableData),
            rows: dataRows(for: tableData),
            extractionQuality: extractionQuality ?? tableQualityScore(tableData),
            extractionSource: extractionSource ?? "vision_document",
            lowQualityRowIndices: lowQualityRows
        )
    }

    func siblingGroupIdentifier(prefix: String, pageNumber: Int, title: String) -> String {
        let normalizedTitle = title.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(prefix)-p\(pageNumber)-\(normalizedTitle)"
    }

    func normalizedListItems(from element: StructuredElementWrapper) -> [String] {
        if let listItems = element.listItems, !listItems.isEmpty {
            return listItems
                .map { OCRConfiguration.normalizeExtractedText($0, profile: .tableCell).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return element.text
            .components(separatedBy: CharacterSet.newlines)
            .map { OCRConfiguration.normalizeExtractedText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^(?:[-*•]\s*|\d+[\.)]\s*)"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
    }

    func buildListItemText(item: String, sectionPath: [String], sectionTitle: String?) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let resolvedSectionTitle = sectionTitle.flatMap { sanitizeStructuredLabel($0) }
        var lines: [String] = []
        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        } else if let resolvedSectionTitle {
            lines.append("Section: \(resolvedSectionTitle)")
        }
        lines.append(item)
        return lines.joined(separator: "\n")
    }

    func isWarningLikeListItem(_ item: String, sectionTitle: String?) -> Bool {
        let combined = [sectionTitle, item].compactMap { $0?.lowercased() }.joined(separator: " ")
        let warningTerms = ["warning", "caution", "danger", "important", "notice", "precaution"]
        return warningTerms.contains(where: { combined.contains($0) })
    }

    func buildStructuralTableText(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String]
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        let rows = dataRows(for: tableData)

        var lines: [String] = []
        if !resolvedSectionPath.isEmpty {
            lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
        }
        lines.append("TABLE: \(tableTitle)")
        lines.append("HEADERS: \(headers.joined(separator: " | "))")

        for (index, row) in rows.enumerated() {
            let normalizedRow = normalizedRow(row, columnCount: headers.count)
            lines.append("ROW \(index + 1): \(normalizedRow.joined(separator: " | "))")
        }

        if let keyValuePairs = tableData.keyValuePairs, !keyValuePairs.isEmpty {
            lines.append("[Specifications]")
            for (key, value) in keyValuePairs {
                lines.append("\(key): \(value)")
            }
        }

        lines.append("SOURCE: \(filename), page \(tableData.pageNumber)")
        return lines.joined(separator: "\n")
    }

    func buildSemanticTableSummary(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String],
        documentCategory: DocumentSemanticCategory
    ) -> String {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        let rows = dataRows(for: tableData)
        let categoryDescriptor: String = {
            switch documentCategory {
            case .technicalManual: return "technical reference"
            case .scientificPaper: return "research data"
            case .referenceTable: return "reference table"
            case .regulatory: return "regulatory table"
            case .general: return "document table"
            }
        }()

        var sentences: [String] = []
        sentences.append("This \(categoryDescriptor) from \(filename) page \(tableData.pageNumber) describes \(tableTitle.lowercased()).")

        if !resolvedSectionPath.isEmpty {
            sentences.append("It appears under \(resolvedSectionPath.joined(separator: " > ")).")
        }

        if !headers.isEmpty {
            let displayedHeaders = headers.prefix(5).joined(separator: ", ")
            sentences.append("Columns include \(displayedHeaders).")
        }

        if let keyValuePairs = tableData.keyValuePairs, !keyValuePairs.isEmpty {
            let preview = keyValuePairs.prefix(4).map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            sentences.append("Key values include \(preview).")
        } else if !rows.isEmpty {
            let preview = rows.prefix(2)
                .map { normalizedRow($0, columnCount: headers.count).filter { !$0.isEmpty }.joined(separator: " | ") }
                .filter { !$0.isEmpty }
                .joined(separator: " || ")
            if !preview.isEmpty {
                sentences.append("Representative rows: \(preview).")
            }
        }

        return sentences.joined(separator: " ")
    }

    func shouldEmitCompatibilityRowChunks(
        tableData: TableData,
        tableTitle: String,
        extractionSource: String?
    ) -> Bool {
        let trustedSources: Set<String> = ["vision_document", "layout_table", "crop_rescue"]
        if let extractionSource, !trustedSources.contains(extractionSource) {
            return false
        }

        let headers = inferredHeaders(for: tableData).map { $0.lowercased() }
        let lowerTitle = tableTitle.lowercased()
        let signals = ["compat", "requirement", "supported", "model", "camera", "head", "coupler"]
        let headerSignal = headers.contains { header in signals.contains(where: { header.contains($0) }) }
        let titleSignal = signals.contains { lowerTitle.contains($0) }
        return (titleSignal || headerSignal) && headers.count >= 3 && dataRows(for: tableData).count >= 2
    }

    func buildCompatibilityRowTexts(
        tableData: TableData,
        tableTitle: String,
        filename: String,
        sectionPath: [String]
    ) -> [String] {
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let headers = inferredHeaders(for: tableData)
        return dataRows(for: tableData).compactMap { row in
            let normalized = normalizedRow(row, columnCount: headers.count)
            let visiblePairs = zip(headers, normalized).filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !visiblePairs.isEmpty else { return nil }

            var lines: [String] = []
            if !resolvedSectionPath.isEmpty {
                lines.append("Section Path: \(resolvedSectionPath.joined(separator: " > "))")
            }
            lines.append("COMPATIBILITY ROW: \(tableTitle)")
            lines.append("CATEGORY: \(visiblePairs.first?.1 ?? "Item")")
            lines.append("VALUES: \(visiblePairs.map { "\($0.0)=\($0.1)" }.joined(separator: " | "))")
            lines.append("SOURCE: \(filename), page \(tableData.pageNumber)")
            return lines.joined(separator: "\n")
        }
    }

    nonisolated func inferredHeaders(for tableData: TableData) -> [String] {
        let columnCount = tableData.rows.map(\ .count).max() ?? 0
        guard columnCount > 0 else { return [] }

        if let headerRow = tableData.headerRow, !headerRow.isEmpty {
            return (0..<columnCount).map { index in
                if index < headerRow.count {
                    let trimmed = headerRow[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
                }
                return "Column \(index + 1)"
            }
        }

        return (0..<columnCount).map { "Column \($0 + 1)" }
    }

    nonisolated func dataRows(for tableData: TableData) -> [[String]] {
        if tableData.headerRow != nil && tableData.rows.count > 1 {
            return Array(tableData.rows.dropFirst())
        }
        return tableData.rows
    }

    private func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        } else if normalized.count > columnCount {
            normalized = Array(normalized.prefix(columnCount))
        }
        return normalized
    }

    /// Sanitizes potential section labels/titles used for section context.
    /// Returns nil when the label appears OCR-garbled and unsafe to propagate.
    func sanitizeStructuredLabel(_ raw: String) -> String? {
        let normalized = OCRConfiguration
            .normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard !normalized.hasPrefix("[OCR unclear]"),
              !normalized.hasPrefix("[OCR quality: low]")
        else {
            return nil
        }

        // Filter line-level OCR garbage and re-evaluate
        let (cleaned, _) = OCRConfiguration.filterGarbageText(normalized)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 2 else { return nil }

        // Reject labels that are symbol-heavy / mostly non-alphanumeric
        let scalars = candidate.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let ratio = Double(alnumCount) / Double(max(1, scalars.count))
        if scalars.count >= 8, ratio < 0.45 {
            return nil
        }

        // Reject long labels that fail global text quality checks
        if candidate.count >= 24, !isTextQualityAcceptable(candidate) {
            return nil
        }

        guard isLikelyStructuredHeading(candidate) else { return nil }

        return candidate
    }

    func sanitizedSectionPath(_ rawPath: [String]) -> [String] {
        rawPath.reduce(into: [String]()) { result, component in
            guard let cleaned = sanitizeStructuredLabel(component) else { return }
            guard result.last?.caseInsensitiveCompare(cleaned) != .orderedSame else { return }
            result.append(cleaned)
        }
    }

    /// Cleans each chunk's section title and path. A label is cleaned once and remembered for
    /// the rest of the call: the chunks of one section carry the same title and path, and
    /// cleaning one runs text cleanup, language detection and the heading test. The loop lets
    /// the main actor go every 50 chunks. As one uninterrupted `map`, with a new language
    /// recognizer for every label, this held the main actor for 14 s on a 2 MB piece of a JSON
    /// Lines file (3,019 chunks; a sample of the run on 2026-10-09 showed all of it here).
    func sanitizeProcessedChunkMetadata(_ chunks: [ProcessedChunk]) async -> [ProcessedChunk] {
        var cleanedLabels: [String: String?] = [:]
        func cleanedLabel(_ raw: String) -> String? {
            if let known = cleanedLabels[raw] { return known }
            let cleaned = sanitizeStructuredLabel(raw)
            cleanedLabels[raw] = cleaned
            return cleaned
        }

        var result: [ProcessedChunk] = []
        result.reserveCapacity(chunks.count)
        for (offset, chunk) in chunks.enumerated() {
            if offset > 0, offset % 50 == 0 { await Task.yield() }
            result.append(sanitizedChunk(chunk, cleanedLabel: cleanedLabel))
        }
        return result
    }

    private func sanitizedChunk(_ chunk: ProcessedChunk, cleanedLabel: (String) -> String?) -> ProcessedChunk {
        let cleanedSectionTitle = chunk.metadata.sectionTitle.flatMap { cleanedLabel($0) }
        // As `sanitizedSectionPath`, with the remembered labels.
        let cleanedSectionPath = (chunk.metadata.sectionPath ?? []).reduce(into: [String]()) { path, component in
            guard let cleaned = cleanedLabel(component) else { return }
            guard path.last?.caseInsensitiveCompare(cleaned) != .orderedSame else { return }
            path.append(cleaned)
        }

        guard cleanedSectionTitle != chunk.metadata.sectionTitle
            || cleanedSectionPath != (chunk.metadata.sectionPath ?? [])
        else {
            return chunk
        }

        let base = chunk.metadata
        let metadata = ChunkMetadata(
            chunkIndex: base.chunkIndex,
            startPosition: base.startPosition,
            endPosition: base.endPosition,
            pageNumber: base.pageNumber,
            sectionTitle: cleanedSectionTitle,
            keywords: base.keywords,
            semanticDensity: base.semanticDensity,
            hasNumericData: base.hasNumericData,
            hasListStructure: base.hasListStructure,
            wordCount: base.wordCount,
            characterCount: base.characterCount,
            createdAt: base.createdAt,
            structureType: base.structureType,
            siblingGroupId: base.siblingGroupId,
            siblingCount: base.siblingCount,
            entities: base.entities,
            abbreviations: base.abbreviations,
            abstractionLevel: base.abstractionLevel,
            sectionPath: cleanedSectionPath.isEmpty ? nil : cleanedSectionPath,
            bboxArray: base.bboxArray,
            documentCategory: base.documentCategory,
            chunkType: base.chunkType,
            tableTitle: base.tableTitle,
            imageContentType: base.imageContentType,
            imageCaption: base.imageCaption,
            imageDescription: base.imageDescription,
            imageExtractedText: base.imageExtractedText,
            imageClassifications: base.imageClassifications,
            hasCrossReferences: base.hasCrossReferences,
            resolvedReferences: base.resolvedReferences
        )

        return ProcessedChunk(
            text: chunk.text,
            parentText: chunk.parentText,
            metadata: metadata,
            structuredTable: chunk.structuredTable
        )
    }

    /// Keep retrieval metadata conservative: a bad heading hurts ranking more than a missing one.
    private func isLikelyStructuredHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("_"), !trimmed.contains("|") else { return false }
        guard trimmed.range(of: #"(?i)^row\s+\d+$"#, options: .regularExpression) == nil else { return false }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty, words.count <= 12 else { return false }

        let scalars = trimmed.unicodeScalars
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = scalars.filter { CharacterSet.punctuationCharacters.contains($0) }.count

        guard letterCount >= 2 else { return false }

        let alnumRatio = Double(letterCount + digitCount) / Double(max(1, scalars.count))
        if scalars.count >= 8, alnumRatio < 0.55 {
            return false
        }

        if punctuationCount > max(4, scalars.count / 4) {
            return false
        }

        if hasMixedLatinAndCyrillicScalars(trimmed) {
            return false
        }

        if isLikelyLatinSectionHint(trimmed) {
            if OCRConfiguration.isGarbageText(trimmed, isLatinDocument: true) {
                return false
            }

            if letterCount >= 8 {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(trimmed)
                let confidence = recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
                if confidence < 0.24 {
                    return false
                }
            }
        }

        if words.count == 1, trimmed.count > 24, !trimmed.contains("-"), !trimmed.contains("/") {
            return false
        }

        return true
    }

    private func hasMixedLatinAndCyrillicScalars(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        guard latinCount > 0, cyrillicCount > 0 else { return false }
        let mixedRatio = Double(min(latinCount, cyrillicCount)) / Double(max(latinCount, cyrillicCount))
        return mixedRatio >= 0.15
    }

    private func isLikelyLatinSectionHint(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if latinCount > 0 || cyrillicCount > 0 {
            return latinCount >= cyrillicCount
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominantLanguage = recognizer.dominantLanguage else { return false }

        let latinLanguages: Set<NLLanguage> = [
            .english, .french, .german, .spanish, .portuguese,
            .italian, .dutch, .swedish, .danish, .norwegian,
            .finnish, .polish, .czech, .romanian, .hungarian,
            .turkish, .indonesian, .malay, .vietnamese,
            .catalan, .croatian, .slovak
        ]
        return latinLanguages.contains(dominantLanguage)
    }

    /// Sanitizes narrative structured text used for chunking/storage.
    /// Reject low-confidence OCR wrappers and text that collapses to garbage after cleanup.
    func sanitizeStructuredNarrativeText(_ raw: String, pageHasTables: Bool = false) -> String? {
        let normalized = OCRConfiguration
            .normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard !normalized.hasPrefix("[OCR unclear]"),
              !normalized.hasPrefix("[OCR quality: low]")
        else {
            return nil
        }

        let (cleaned, _) = OCRConfiguration.filterGarbageText(normalized, revertIfTooAggressive: false)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 3 else { return nil }

        let scalars = candidate.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let ratio = Double(alnumCount) / Double(max(1, scalars.count))
        if scalars.count >= 12, ratio < 0.45 {
            return nil
        }

        if pageHasTables, isLikelyTableLeakageNarrative(candidate) {
            return nil
        }

        return candidate
    }

    private func isLikelyTableLeakageNarrative(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 80 else { return false }

        let lower = trimmed.lowercased()
        if trimmed.contains("|") {
            return true
        }
        if lower.range(of: #"\b(?:row|column)\s+\d+\b"#, options: .regularExpression) != nil {
            return true
        }

        let scalars = trimmed.unicodeScalars
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let digitRatio = Double(digitCount) / Double(max(1, scalars.count))
        let sentenceStopCount = trimmed.filter { ".!?".contains($0) }.count
        let trademarkCount = trimmed.filter { $0 == "®" || $0 == "™" || $0 == "©" }.count

        let fragmentCount = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count

        let citationClusterCount: Int = {
            guard let regex = try? NSRegularExpression(
                pattern: #"\b\d{1,3}(?:,\d{1,3}){1,}\b|\b\d{1,3}-\d{1,3}\b"#,
                options: []
            ) else {
                return 0
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.numberOfMatches(in: trimmed, options: [], range: range)
        }()

        if digitRatio >= 0.08 && sentenceStopCount == 0 && (fragmentCount >= 4 || trademarkCount >= 1 || citationClusterCount >= 2) {
            return true
        }

        if trademarkCount >= 2 && fragmentCount >= 3 {
            return true
        }

        return false
    }

}
