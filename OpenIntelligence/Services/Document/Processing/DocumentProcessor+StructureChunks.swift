//
//  DocumentProcessor+StructureChunks.swift
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
    /// Create chunks that respect document structure (tables as atomic units, paragraphs chunked normally)
    /// Tables are kept as single chunks to preserve data integrity across any domain.
    func createStructureAwareChunks(
        elements: [StructuredElementWrapper],
        fullText: String,
        config: SemanticChunker.ChunkingConfig,
        documentId: UUID,
        pageInfo: PageInfo,
        filename: String,
        documentCategory: DocumentSemanticCategory
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []
        var chunkIndex = 0

        _ = pageInfo

        // Collect all detected entities from structured elements
        collectDetectedEntities(elements: elements)

        // Group paragraphs for semantic chunking, but tables and lists become atomic chunks
        var paragraphBuffer: [(text: String, page: Int)] = []

        // Track section context for table association
        var currentSectionTitle: String? = nil
        var currentSectionPath: [String] = []

        // Running headers and footers never become a passage, a title or a section (5.8).
        let runningKeys = Self.runningLineKeys(
            in: elements.filter { $0.elementType == "paragraph" || $0.elementType == "title" }.map { ($0.pageNumber, $0.text) })
        var runningElementsDropped = 0

        for element in elements {
            if element.elementType == "paragraph" || element.elementType == "title",
                Self.isRunningElement(element.text, runningKeys: runningKeys)
            {
                runningElementsDropped += 1
                continue
            }
            // Track section titles for context association
            trackSectionTitle(element: element, currentSectionTitle: &currentSectionTitle, currentSectionPath: &currentSectionPath)

            if element.isAtomicChunk {
                // Flush any pending paragraphs first
                flushStructureParagraphs(paragraphBuffer: &paragraphBuffer, chunks: &chunks, chunkIndex: &chunkIndex, documentId: documentId, config: config, documentCategory: documentCategory)

                if element.elementType == "table", let tableData = element.tableData {
                    appendTableChunks(currentSectionTitle: currentSectionTitle, tableData: tableData, element: element, filename: filename, currentSectionPath: currentSectionPath, chunkIndex: &chunkIndex, documentCategory: documentCategory, chunks: &chunks)
                    continue
                }

                if element.elementType == "list" {
                    appendListChunks(element: element, currentSectionTitle: currentSectionTitle, currentSectionPath: currentSectionPath, chunks: &chunks, chunkIndex: &chunkIndex, documentCategory: documentCategory)
                    continue
                }

                if element.elementType == "figure", let imageAnalysis = element.imageAnalysis {
                    appendFigureChunks(imageAnalysis: imageAnalysis, element: element, filename: filename, currentSectionPath: currentSectionPath, chunkIndex: &chunkIndex, currentSectionTitle: currentSectionTitle, documentCategory: documentCategory, chunks: &chunks)

                    continue
                }

            } else if element.elementType == "paragraph" || element.elementType == "title" {
                // Buffer paragraphs for semantic chunking. A page read from its text layer arrives as one long element,
                // so its running header and footer lines are taken out line by line (5.8).
                let normalized = Self.withoutRunningLines(
                    OCRConfiguration.normalizeExtractedText(element.text), runningKeys: runningKeys)
                let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Do not feed garbled title text into paragraph chunking path
                    if element.elementType == "title", sanitizeStructuredLabel(trimmed) == nil {
                        continue
                    }
                    paragraphBuffer.append((text: trimmed, page: element.pageNumber))
                }
            } else {
                // Lists that aren't atomic get buffered too
                let normalized = OCRConfiguration.normalizeExtractedText(element.text)
                let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    paragraphBuffer.append((text: trimmed, page: element.pageNumber))
                }
            }
        }

        // Flush any remaining paragraphs
        flushStructureParagraphs(paragraphBuffer: &paragraphBuffer, chunks: &chunks, chunkIndex: &chunkIndex, documentId: documentId, config: config, documentCategory: documentCategory)

        if runningElementsDropped > 0 {
            Log.info("[DocumentProcessor] Left out \(runningElementsDropped) running header or footer element(s)", category: .ingestion)
        }

        // Log structure breakdown
        logStructureBreakdown(chunks: chunks)

        return chunks
    }

    /// Step B1: collects the entities Vision detected in the elements and keeps them for vocabulary learning.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func collectDetectedEntities(elements: [DocumentProcessor.StructuredElementWrapper]) {
        var allDetectedEntities: [(type: String, value: String)] = []
        for element in elements {
            allDetectedEntities.append(contentsOf: element.detectedEntities)
        }

        // Store entities for vocabulary learning
        self.lastDetectedEntities = allDetectedEntities
        if !allDetectedEntities.isEmpty {
            Log.info("[DocumentProcessor] Collected \(allDetectedEntities.count) Vision-detected entities for vocabulary learning", category: .ingestion)
        }
    }

    /// Step B6: a title element updates the current section title and path the following chunks carry.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func trackSectionTitle(element: DocumentProcessor.StructuredElementWrapper, currentSectionTitle: inout String?, currentSectionPath: inout [String]) {
        if element.elementType == "title" {
            let titleText = sanitizeStructuredLabel(element.text)
            if let titleText {
                currentSectionTitle = titleText
                // Structured parsing currently gives us flat page titles, not true heading levels.
                // Reusing the last few page titles as a fake hierarchy pollutes retrieval metadata.
                currentSectionPath = [titleText]
            } else {
                Log.debug("[DocumentProcessor] Dropping garbled section title from path context", category: .ingestion)
            }
        }
    }

    /// Steps B7 to B9: turns a table element into its structural chunk (split above 380 words), its semantic summary and any compatibility rows, its continue kept in the host.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func appendTableChunks(currentSectionTitle: String?, tableData: TableData, element: DocumentProcessor.StructuredElementWrapper, filename: String, currentSectionPath: [String], chunkIndex: inout Int, documentCategory: DocumentSemanticCategory, chunks: inout [DocumentProcessor.ProcessedChunk]) {
        let tableTitle = resolveTableTitle(tableData: tableData, sectionTitle: currentSectionTitle)
        let structuredTable = structuredTablePayload(
            from: tableData,
            tableTitle: tableTitle,
            extractionQuality: element.qualityScore,
            extractionSource: element.extractionSource
        )
        let siblingGroupId = siblingGroupIdentifier(
            prefix: "table",
            pageNumber: element.pageNumber,
            title: tableTitle
        )

        let structuralText = buildStructuralTableText(
            tableData: tableData,
            tableTitle: tableTitle,
            filename: filename,
            sectionPath: currentSectionPath
        )

        let structuralWords = countWords(structuralText)
        let maxAtomicWords = 380
        if structuralWords > maxAtomicWords {
            let baseMetadata = makeChunkMetadata(
                chunkIndex: chunkIndex,
                text: structuralText,
                pageNumber: element.pageNumber,
                sectionTitle: currentSectionTitle,
                structureType: "table",
                chunkType: .tableStructural,
                documentCategory: documentCategory,
                sectionPath: currentSectionPath,
                semanticDensity: 0.90,
                hasNumericData: true,
                hasListStructure: false,
                entities: element.detectedEntities.map(\ .value),
                tableTitle: tableTitle,
                siblingGroupId: siblingGroupId
            )
            let splitChunks = splitOversizedAtomicChunk(
                text: structuralText,
                contextPrefix: "",
                element: element,
                baseMetadata: baseMetadata,
                parentText: currentSectionTitle,
                structuredTable: structuredTable,
                maxWords: maxAtomicWords
            )
            chunks.append(contentsOf: splitChunks)
            chunkIndex += splitChunks.count
        } else {
            appendStructureChunk(
                chunks: &chunks,
                chunkIndex: &chunkIndex,
                documentCategory: documentCategory,
                text: structuralText,
                parentText: currentSectionTitle,
                pageNumber: element.pageNumber,
                sectionTitle: currentSectionTitle,
                structureType: "table",
                chunkType: .tableStructural,
                semanticDensity: 0.90,
                hasNumericData: true,
                hasListStructure: false,
                sectionPath: currentSectionPath,
                entities: element.detectedEntities.map(\ .value),
                tableTitle: tableTitle,
                siblingGroupId: siblingGroupId,
                structuredTable: structuredTable
            )
        }

        let semanticText = buildSemanticTableSummary(
            tableData: tableData,
            tableTitle: tableTitle,
            filename: filename,
            sectionPath: currentSectionPath,
            documentCategory: documentCategory
        )
        appendStructureChunk(
            chunks: &chunks,
            chunkIndex: &chunkIndex,
            documentCategory: documentCategory,
            text: semanticText,
            parentText: currentSectionTitle,
            pageNumber: element.pageNumber,
            sectionTitle: currentSectionTitle,
            structureType: "table",
            chunkType: .tableSemantic,
            semanticDensity: 0.82,
            hasNumericData: semanticText.rangeOfCharacter(from: .decimalDigits) != nil,
            hasListStructure: false,
            sectionPath: currentSectionPath,
            entities: element.detectedEntities.map(\ .value),
            tableTitle: tableTitle,
            siblingGroupId: siblingGroupId
        )

        if shouldEmitCompatibilityRowChunks(
            tableData: tableData,
            tableTitle: tableTitle,
            extractionSource: element.extractionSource
        ) {
            let rowTexts = buildCompatibilityRowTexts(
                tableData: tableData,
                tableTitle: tableTitle,
                filename: filename,
                sectionPath: currentSectionPath
            )
            for rowText in rowTexts {
                appendStructureChunk(
                    chunks: &chunks,
                    chunkIndex: &chunkIndex,
                    documentCategory: documentCategory,
                    text: rowText,
                    parentText: currentSectionTitle,
                    pageNumber: element.pageNumber,
                    sectionTitle: currentSectionTitle,
                    structureType: "table",
                    chunkType: .tableStructural,
                    semanticDensity: 0.88,
                    hasNumericData: rowText.rangeOfCharacter(from: .decimalDigits) != nil,
                    hasListStructure: false,
                    sectionPath: currentSectionPath,
                    entities: element.detectedEntities.map(\ .value),
                    tableTitle: tableTitle,
                    siblingGroupId: siblingGroupId
                )
            }
        }

        Log.debug("[DocumentProcessor] Created companion table chunks for page \(element.pageNumber), section: \(currentSectionTitle ?? "none")", category: .ingestion)
    }

    /// Step B11: turns a list element into one chunk per normalised item, its continue kept in the host.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func appendListChunks(element: DocumentProcessor.StructuredElementWrapper, currentSectionTitle: String?, currentSectionPath: [String], chunks: inout [DocumentProcessor.ProcessedChunk], chunkIndex: inout Int, documentCategory: DocumentSemanticCategory) {
        let siblingGroupId = siblingGroupIdentifier(
            prefix: "list",
            pageNumber: element.pageNumber,
            title: currentSectionTitle ?? "list"
        )
        let listItems = normalizedListItems(from: element)
        for item in listItems {
            let listText = buildListItemText(item: item, sectionPath: currentSectionPath, sectionTitle: currentSectionTitle)
            let itemChunkType: ChunkSemanticType = isWarningLikeListItem(item, sectionTitle: currentSectionTitle) ? .warning : .listItem
            appendStructureChunk(
                chunks: &chunks,
                chunkIndex: &chunkIndex,
                documentCategory: documentCategory,
                text: listText,
                parentText: currentSectionTitle,
                pageNumber: element.pageNumber,
                sectionTitle: currentSectionTitle,
                structureType: "list",
                chunkType: itemChunkType,
                semanticDensity: 0.72,
                hasNumericData: listText.rangeOfCharacter(from: .decimalDigits) != nil,
                hasListStructure: true,
                sectionPath: currentSectionPath,
                entities: element.detectedEntities.map(\ .value),
                siblingGroupId: siblingGroupId
            )
        }
        Log.debug("[DocumentProcessor] Created \(listItems.count) list item chunks from page \(element.pageNumber)", category: .ingestion)
    }

    /// Step B12: turns a figure element with an image analysis into its chunk (split when oversized), its continue kept in the host.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func appendFigureChunks(imageAnalysis: AnalyzedImage, element: DocumentProcessor.StructuredElementWrapper, filename: String, currentSectionPath: [String], chunkIndex: inout Int, currentSectionTitle: String?, documentCategory: DocumentSemanticCategory, chunks: inout [DocumentProcessor.ProcessedChunk]) {
        let figureTitle = resolveFigureTitle(from: imageAnalysis)
        let siblingGroupId = siblingGroupIdentifier(
            prefix: "figure",
            pageNumber: element.pageNumber,
            title: figureTitle
        )
        let figureText = buildFigureChunkText(
            analyzed: imageAnalysis,
            filename: filename,
            sectionPath: currentSectionPath
        )
        let visualMetadata = makeChunkMetadata(
            chunkIndex: chunkIndex,
            text: figureText,
            pageNumber: element.pageNumber,
            sectionTitle: currentSectionTitle,
            structureType: "figure",
            chunkType: .prose,
            documentCategory: documentCategory,
            sectionPath: currentSectionPath,
            semanticDensity: 0.78,
            hasNumericData: figureText.rangeOfCharacter(from: .decimalDigits) != nil,
            hasListStructure: false,
            entities: imageClassificationLabels(from: imageAnalysis),
            siblingGroupId: siblingGroupId,
            bbox: imageAnalysis.boundingBox,
            imageContentType: imageAnalysis.contentType.rawValue,
            imageCaption: imageAnalysis.associatedCaption,
            imageDescription: imageAnalysis.description,
            imageExtractedText: imageAnalysis.extractedText,
            imageClassifications: imageClassificationLabels(from: imageAnalysis)
        )

        let maxAtomicWords = 380
        if countWords(figureText) > maxAtomicWords {
            let splitChunks = splitOversizedAtomicChunk(
                text: figureText,
                contextPrefix: "",
                element: element,
                baseMetadata: visualMetadata,
                parentText: currentSectionTitle,
                maxWords: maxAtomicWords
            )
            chunks.append(contentsOf: splitChunks)
            chunkIndex += splitChunks.count
        } else {
            chunks.append(ProcessedChunk(
                text: figureText,
                parentText: currentSectionTitle,
                metadata: visualMetadata
            ))
            chunkIndex += 1
        }
    }

    /// Step B14: logs how many table, list and paragraph chunks the document produced.
    /// Moved unchanged from `createStructureAwareChunks` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func logStructureBreakdown(chunks: [DocumentProcessor.ProcessedChunk]) {
        let tableChunks = chunks.filter { $0.metadata.structureType == "table" }.count
        let listChunks = chunks.filter { $0.metadata.structureType == "list" }.count
        let paragraphChunks = chunks.filter { $0.metadata.structureType == "paragraph" }.count

        Log.info("[DocumentProcessor] Structure-aware chunking: \(tableChunks) tables, \(listChunks) lists, \(paragraphChunks) paragraphs", category: .ingestion)
    }

    /// The nested `appendChunk` of `createStructureAwareChunks`, lifted 2026-11-06 (step C1); its body is unchanged.
    /// The chunk list, the running index and the document's category are passed in instead of captured.
    private func appendStructureChunk(
        chunks: inout [ProcessedChunk],
        chunkIndex: inout Int,
        documentCategory: DocumentSemanticCategory,
        text: String,
        parentText: String?,
        pageNumber: Int,
        sectionTitle: String?,
        structureType: String,
        chunkType: ChunkSemanticType,
        semanticDensity: Float,
        hasNumericData: Bool,
        hasListStructure: Bool,
        sectionPath: [String],
        entities: [String] = [],
        abbreviations: [String: String] = [:],
        tableTitle: String? = nil,
        siblingGroupId: String? = nil,
        structuredTable: StructuredTablePayload? = nil
    ) {
        let resolvedSectionTitle = sectionTitle.flatMap { sanitizeStructuredLabel($0) }
        let resolvedSectionPath = sanitizedSectionPath(sectionPath)
        let metadata = makeChunkMetadata(
            chunkIndex: chunkIndex,
            text: text,
            pageNumber: pageNumber,
            sectionTitle: resolvedSectionTitle,
            structureType: structureType,
            chunkType: chunkType,
            documentCategory: documentCategory,
            sectionPath: resolvedSectionPath,
            semanticDensity: semanticDensity,
            hasNumericData: hasNumericData,
            hasListStructure: hasListStructure,
            entities: entities,
            abbreviations: abbreviations,
            tableTitle: tableTitle,
            siblingGroupId: siblingGroupId
        )
        chunks.append(ProcessedChunk(
            text: text,
            parentText: parentText,
            metadata: metadata,
            structuredTable: structuredTable
        ))
        chunkIndex += 1
    }

    /// The nested `flushParagraphBuffer` of `createStructureAwareChunks`, lifted 2026-11-06 (step C1); its body is
    /// unchanged. The buffer, the chunk list and the running index are passed in instead of captured.
    private func flushStructureParagraphs(
        paragraphBuffer: inout [(text: String, page: Int)],
        chunks: inout [ProcessedChunk],
        chunkIndex: inout Int,
        documentId: UUID,
        config: SemanticChunker.ChunkingConfig,
        documentCategory: DocumentSemanticCategory
    ) {
        guard !paragraphBuffer.isEmpty else { return }

        // Combine paragraphs for semantic chunking
        let combinedText = paragraphBuffer.map { $0.text }.joined(separator: "\n\n")

        // Build per-page text ranges from the buffer so SemanticChunker
        // can assign the correct page number to each sub-chunk.
        // Each paragraph knows its source page; we track where it lands
        // in the combined string and build a [pageNum: Range<String.Index>] map.
        var localPageRanges: [Int: Range<String.Index>] = [:]
        var currentOffset = combinedText.startIndex
        for (i, entry) in paragraphBuffer.enumerated() {
            let textEnd = combinedText.index(currentOffset, offsetBy: entry.text.count, limitedBy: combinedText.endIndex) ?? combinedText.endIndex
            let entryRange = currentOffset..<textEnd

            if let existing = localPageRanges[entry.page] {
                // Extend the range for this page (non-contiguous paragraphs on same page)
                localPageRanges[entry.page] = existing.lowerBound..<textEnd
            } else {
                localPageRanges[entry.page] = entryRange
            }

            // Skip past the "\n\n" separator between paragraphs
            if i < paragraphBuffer.count - 1 {
                currentOffset = combinedText.index(textEnd, offsetBy: 2, limitedBy: combinedText.endIndex) ?? combinedText.endIndex
            } else {
                currentOffset = textEnd
            }
        }

        let semanticChunker = SemanticChunker()
        let subChunks = semanticChunker.chunkText(
            combinedText,
            documentId: documentId,
            config: config,
            pageNumbers: localPageRanges,
            documentCategory: documentCategory
        )

        for subChunk in subChunks {
            let cleanedSectionTitle = subChunk.metadata.sectionTitle.flatMap { sanitizeStructuredLabel($0) }
            let cleanedSectionPath = sanitizedSectionPath(subChunk.metadata.sectionPath)
            let metadata = ChunkMetadata(
                chunkIndex: chunkIndex,
                startPosition: subChunk.metadata.startOffset,
                endPosition: subChunk.metadata.endOffset,
                pageNumber: subChunk.metadata.pageNumber,
                sectionTitle: cleanedSectionTitle,
                keywords: subChunk.metadata.topKeywords,
                semanticDensity: subChunk.metadata.semanticDensity,
                hasNumericData: subChunk.metadata.hasNumericData,
                hasListStructure: subChunk.metadata.hasListStructure,
                wordCount: subChunk.metadata.wordCount,
                characterCount: subChunk.metadata.characterCount,
                structureType: "paragraph",
                entities: subChunk.metadata.entities,
                abbreviations: subChunk.metadata.abbreviations,
                sectionPath: cleanedSectionPath.isEmpty ? nil : cleanedSectionPath,
                documentCategory: subChunk.metadata.documentCategory,
                chunkType: subChunk.metadata.chunkType,
                tableTitle: subChunk.metadata.tableTitle,
                hasCrossReferences: subChunk.metadata.hasCrossReferences,
                resolvedReferences: subChunk.metadata.resolvedReferences
            )
            chunks.append(ProcessedChunk(
                text: subChunk.content,
                parentText: subChunk.parentContent,
                metadata: metadata
            ))
            chunkIndex += 1
        }

        paragraphBuffer.removeAll()
    }

    /// Split an oversized atomic chunk (table/list) into multiple smaller chunks
    /// Preserves context prefix and section path on each chunk for retrieval coherence.
    /// For tables: repeats the header row at the top of each continuation chunk
    /// so that every chunk has column labels for its numeric values.
    private func splitOversizedAtomicChunk(
        text: String,
        contextPrefix: String,
        element: StructuredElementWrapper,
        baseMetadata: ChunkMetadata,
        parentText: String?,
        structuredTable: StructuredTablePayload? = nil,
        maxWords: Int
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []

        // Remove context prefix from text to split just the content
        let contentText = text.hasPrefix(contextPrefix) ? String(text.dropFirst(contextPrefix.count)) : text

        // Split by rows for tables (line-based), or by items for lists
        let allLines = contentText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // A table written by `buildStructuralTableText` opens with its Section Path, TABLE and HEADERS lines and ends with
        // its SOURCE line. Every part repeats them (5.8): the first-line header below took only "Section Path:" or
        // "TABLE:", part 1 then lost it, later parts had no TABLE or HEADERS, and SOURCE was in the last part only.
        let structuralHeader: [String] =
            element.elementType == "table"
            ? Array(allLines.prefix { $0.hasPrefix("Section Path:") || $0.hasPrefix("TABLE:") || $0.hasPrefix("HEADERS:") })
            : []
        let sourceLine: String? = structuralHeader.isEmpty ? nil : allLines.last(where: { $0.hasPrefix("SOURCE:") })
        let lines: [String] =
            structuralHeader.isEmpty
            ? allLines
            : Array(allLines.dropFirst(structuralHeader.count)).filter { $0 != sourceLine }

        // For tables: detect and preserve header row for repetition in continuation chunks
        // A header row is typically the first non-separator row (no pipes-only or dashes-only)
        let tableHeaderLine: String? = {
            guard element.elementType == "table", structuralHeader.isEmpty, lines.count > 2 else { return nil }
            // Check if first line looks like a header (not a separator like "|---|---|")
            if let first = lines.first {
                let stripped = first.replacingOccurrences(of: "|", with: "")
                                   .replacingOccurrences(of: "-", with: "")
                                   .replacingOccurrences(of: ":", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                // If there's actual text content (not just formatting), it's likely a header
                if !stripped.isEmpty {
                    return first
                }
            }
            return nil
        }()

        // Also detect markdown table separator (e.g., "|---|---|")
        let tableSeparatorLine: String? = {
            guard element.elementType == "table", structuralHeader.isEmpty, lines.count > 2 else { return nil }
            if lines.count > 1 {
                let second = lines[1]
                let stripped = second.replacingOccurrences(of: "|", with: "")
                                    .replacingOccurrences(of: "-", with: "")
                                    .replacingOccurrences(of: ":", with: "")
                                    .replacingOccurrences(of: " ", with: "")
                // If it's just dashes and pipes, it's a separator
                if stripped.isEmpty {
                    return second
                }
            }
            return nil
        }()

        // Calculate header overhead for word budget
        let headerWords = (tableHeaderLine?.split(separator: " ").count ?? 0) +
                          (tableSeparatorLine?.split(separator: " ").count ?? 0) +
                          (structuralHeader + [sourceLine].compactMap { $0 }).reduce(0) { $0 + $1.split(separator: " ").count }
        let effectiveMaxWords = maxWords - headerWords

        var currentChunkLines: [String] = []
        var currentWordCount = 0
        var chunkNumber = 0

        // Skip header lines in iteration (they'll be prepended to each chunk)
        let startIndex: Int
        if tableHeaderLine != nil && tableSeparatorLine != nil {
            startIndex = 2
        } else if tableHeaderLine != nil {
            startIndex = 1
        } else {
            startIndex = 0
        }

        for lineIndex in startIndex..<lines.count {
            let line = lines[lineIndex]
            let lineWords = line.split(separator: " ").count

            // If adding this line would exceed limit, flush current chunk
            if currentWordCount + lineWords > effectiveMaxWords && !currentChunkLines.isEmpty {
                // Build chunk with header repetition for tables
                var chunkLines: [String] = structuralHeader
                if chunkNumber > 0, let header = tableHeaderLine {
                    // Continuation chunk — prepend header for context
                    chunkLines.append(header)
                    if let separator = tableSeparatorLine {
                        chunkLines.append(separator)
                    }
                }
                chunkLines.append(contentsOf: currentChunkLines)
                if let sourceLine { chunkLines.append(sourceLine) }

                let chunkContent = contextPrefix + "[Part \(chunkNumber + 1)]\n" + chunkLines.joined(separator: "\n")
                let metadata = ChunkMetadata(
                    chunkIndex: baseMetadata.chunkIndex + chunkNumber,
                    startPosition: baseMetadata.startPosition,
                    endPosition: chunkContent.count,
                    pageNumber: baseMetadata.pageNumber,
                    sectionTitle: baseMetadata.sectionTitle,
                    keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                    semanticDensity: baseMetadata.semanticDensity,
                    hasNumericData: baseMetadata.hasNumericData,
                    hasListStructure: baseMetadata.hasListStructure,
                    wordCount: countWords(chunkContent),
                    characterCount: chunkContent.count,
                    createdAt: baseMetadata.createdAt,
                    structureType: baseMetadata.structureType,
                    siblingGroupId: baseMetadata.siblingGroupId,
                    siblingCount: baseMetadata.siblingCount,
                    entities: baseMetadata.entities,
                    abbreviations: baseMetadata.abbreviations,
                    abstractionLevel: baseMetadata.abstractionLevel,
                    sectionPath: baseMetadata.sectionPath,
                    bboxArray: baseMetadata.bboxArray,
                    documentCategory: baseMetadata.documentCategory,
                    chunkType: baseMetadata.chunkType,
                    tableTitle: baseMetadata.tableTitle,
                    imageContentType: baseMetadata.imageContentType,
                    imageCaption: baseMetadata.imageCaption,
                    imageDescription: baseMetadata.imageDescription,
                    imageExtractedText: baseMetadata.imageExtractedText,
                    imageClassifications: baseMetadata.imageClassifications,
                    hasCrossReferences: baseMetadata.hasCrossReferences,
                    resolvedReferences: baseMetadata.resolvedReferences
                )
                chunks.append(ProcessedChunk(
                    text: chunkContent,
                    parentText: parentText,
                    metadata: metadata,
                    structuredTable: chunkNumber == 0 ? structuredTable : nil
                ))
                chunkNumber += 1
                currentChunkLines = []
                currentWordCount = 0
            }

            currentChunkLines.append(line)
            currentWordCount += lineWords
        }

        // Flush remaining lines
        if !currentChunkLines.isEmpty {
            // Build chunk with header repetition for continuation chunks
            var chunkLines: [String] = structuralHeader
            if chunkNumber > 0, let header = tableHeaderLine {
                chunkLines.append(header)
                if let separator = tableSeparatorLine {
                    chunkLines.append(separator)
                }
            }
            chunkLines.append(contentsOf: currentChunkLines)
            if let sourceLine { chunkLines.append(sourceLine) }

            let chunkContent = contextPrefix + (chunkNumber > 0 ? "[Part \(chunkNumber + 1)]\n" : "") + chunkLines.joined(separator: "\n")
            let metadata = ChunkMetadata(
                chunkIndex: baseMetadata.chunkIndex + chunkNumber,
                startPosition: baseMetadata.startPosition,
                endPosition: chunkContent.count,
                pageNumber: baseMetadata.pageNumber,
                sectionTitle: baseMetadata.sectionTitle,
                keywords: extractKeywordsFromStructuredElement(chunkContent, type: element.elementType),
                semanticDensity: baseMetadata.semanticDensity,
                hasNumericData: baseMetadata.hasNumericData,
                hasListStructure: baseMetadata.hasListStructure,
                wordCount: countWords(chunkContent),
                characterCount: chunkContent.count,
                createdAt: baseMetadata.createdAt,
                structureType: baseMetadata.structureType,
                siblingGroupId: baseMetadata.siblingGroupId,
                siblingCount: baseMetadata.siblingCount,
                entities: baseMetadata.entities,
                abbreviations: baseMetadata.abbreviations,
                abstractionLevel: baseMetadata.abstractionLevel,
                sectionPath: baseMetadata.sectionPath,
                bboxArray: baseMetadata.bboxArray,
                documentCategory: baseMetadata.documentCategory,
                chunkType: baseMetadata.chunkType,
                tableTitle: baseMetadata.tableTitle,
                imageContentType: baseMetadata.imageContentType,
                imageCaption: baseMetadata.imageCaption,
                imageDescription: baseMetadata.imageDescription,
                imageExtractedText: baseMetadata.imageExtractedText,
                imageClassifications: baseMetadata.imageClassifications,
                hasCrossReferences: baseMetadata.hasCrossReferences,
                resolvedReferences: baseMetadata.resolvedReferences
            )
            chunks.append(ProcessedChunk(
                text: chunkContent,
                parentText: parentText,
                metadata: metadata,
                structuredTable: chunkNumber == 0 ? structuredTable : nil
            ))
        }

        return chunks
    }

}
