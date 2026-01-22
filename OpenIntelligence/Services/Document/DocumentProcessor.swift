//
//  DocumentProcessor.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Service responsible for parsing documents and chunking them for embedding
class DocumentProcessor {
    struct ProcessedChunk: Sendable {
        let text: String
        let parentText: String?
        let metadata: ChunkMetadata
    }

    struct ChunkingOverride: Sendable {
        let targetWordWindow: Int
        let overlapWords: Int
    }

    // MARK: - Structured Parsing Results (iOS 26+)

    /// Result of structured document extraction, containing both text and structured elements
    private struct StructuredExtractionResult {
        let text: String
        let pageInfo: PageInfo
        let structuredElements: [StructuredElementWrapper]  // Tables, lists with metadata
        let usedStructuredParsing: Bool
    }

    /// Wrapper to hold structured elements with page info (works on all iOS versions)
    private struct StructuredElementWrapper {
        let text: String
        let elementType: String  // "table", "list", "paragraph", "title"
        let pageNumber: Int
        let isAtomicChunk: Bool  // Tables should be chunked as single units
        let detectedEntities: [(type: String, value: String)]  // Vision-detected entities (emails, phones, etc.)

        init(text: String, elementType: String, pageNumber: Int, isAtomicChunk: Bool, detectedEntities: [(type: String, value: String)] = []) {
            self.text = text
            self.elementType = elementType
            self.pageNumber = pageNumber
            self.isAtomicChunk = isAtomicChunk
            self.detectedEntities = detectedEntities
        }
    }

    // MARK: - Configuration

    /// Optimal chunk size balances context vs. precision (typically 200-500 words)
    let targetChunkSize: Int
    let chunkOverlap: Int

    /// Progress callback for real-time UI updates
    var progressHandler: ((String) -> Void)?

    /// Vision-detected entities from last document processing (reset on each call)
    /// Contains emails, phone numbers, URLs, dates, etc. extracted via DataDetection
    private(set) var lastDetectedEntities: [(type: String, value: String)] = []

    init(targetChunkSize: Int = 350, chunkOverlap: Int = 60) {
        self.targetChunkSize = targetChunkSize
        self.chunkOverlap = chunkOverlap
    }

    // MARK: - Public API

    /// Process a document and extract text chunks
    func processDocument(at url: URL, chunkOverride: ChunkingOverride? = nil) async throws -> (Document, [ProcessedChunk]) {
        // Reset detected entities for this document
        lastDetectedEntities = []
        let filename = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let fileSizeMB = Double(fileSize) / 1_048_576.0

        Log.info("[DocumentProcessor] Processing \(filename) (\(String(format: "%.2f", fileSizeMB)) MB)", category: .ingestion)

    let startTime = Date()
    let documentId = UUID()
    var pagesProcessed: Int? = nil
    var ocrPagesCount: Int? = nil

        // Determine document type
        let documentType = detectDocumentType(url: url)
        Log.debug("[DocumentProcessor] Document type: \(documentType)", category: .ingestion)

        // Track structured elements for structure-aware chunking (iOS 26+ PDFs)
        var structuredElements: [StructuredElementWrapper] = []
        var usedStructuredParsing = false

        // Extract text based on document type
        progressHandler?("reading file")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s to show loading (increased for visibility)

        let extractedText: String
        let pageInfo: PageInfo

        // Use structured parsing for PDFs on iOS 26+ (preserves table/list structure)
        if documentType == .pdf {
            let structuredResult = try await extractStructuredPDFContent(url: url)
            extractedText = structuredResult.text
            pageInfo = structuredResult.pageInfo
            structuredElements = structuredResult.structuredElements
            usedStructuredParsing = structuredResult.usedStructuredParsing

            if usedStructuredParsing {
                let tableCount = structuredElements.filter { $0.elementType == "table" }.count
                let listCount = structuredElements.filter { $0.elementType == "list" }.count
                Log.info("[DocumentProcessor] Structured parsing: \(tableCount) tables, \(listCount) lists extracted", category: .ingestion)
            }
        } else {
            let result = try await extractTextWithPageInfo(from: url, type: documentType)
            extractedText = result.text
            pageInfo = result.pageInfo
        }

        pagesProcessed = pageInfo.totalPages
        ocrPagesCount = pageInfo.ocrPagesUsed > 0 ? pageInfo.ocrPagesUsed : nil

        let extractionTime = Date().timeIntervalSince(startTime)
        let charCount = extractedText.count
        let wordCount = extractedText.split(separator: " ").count

        Log.debug(
            "[DocumentProcessor] Extracted \(charCount) chars (\(wordCount) words) in \(String(format: "%.2f", extractionTime))s",
            category: .ingestion
        )

        // Chunk the text using semantic chunker
        progressHandler?("chunking text")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s to show chunking (increased for visibility)
        let chunkingStartTime = Date()

        // Create semantic chunker configuration
        // Use content-adaptive defaults if no override provided
        let baseConfig = SemanticChunker.ChunkingConfig.recommended(for: documentType)
        let activeWindow = chunkOverride?.targetWordWindow ?? baseConfig.targetSize
        let activeOverlap = chunkOverride?.overlapWords ?? baseConfig.overlap
        let chunkerConfig = SemanticChunker.ChunkingConfig(
            targetSize: activeWindow,
            minSize: max(baseConfig.minSize, activeWindow / 4),
            maxSize: max(baseConfig.maxSize, activeWindow * 2),
            overlap: activeOverlap,
            useTopicDetection: baseConfig.useTopicDetection,
            preserveStructure: baseConfig.preserveStructure
        )

        Log.debug(
            "[DocumentProcessor] Using \(documentType.rawValue) chunking: target=\(activeWindow)w, overlap=\(activeOverlap)w",
            category: .ingestion
        )

        let processedChunks: [ProcessedChunk]

        // Structure-aware chunking: Tables and lists become atomic chunks, paragraphs get semantic chunking
        if usedStructuredParsing && !structuredElements.isEmpty {
            processedChunks = createStructureAwareChunks(
                elements: structuredElements,
                fullText: extractedText,
                config: chunkerConfig,
                documentId: documentId,
                pageInfo: pageInfo
            )
            Log.info("[DocumentProcessor] Created \(processedChunks.count) structure-aware chunks", category: .ingestion)
        } else {
            // Standard semantic chunking for non-PDF or iOS < 26
            let semanticChunker = SemanticChunker()
            let pageMapping = pageInfo.pageTextRanges.isEmpty ? nil : pageInfo.pageTextRanges
            let enhancedChunks = semanticChunker.chunkText(
                extractedText,
                documentId: documentId,
                config: chunkerConfig,
                pageNumbers: pageMapping
            )

            // Extract text strings and metadata for downstream use
            processedChunks = enhancedChunks.enumerated().map { index, chunk in
                let metadata = ChunkMetadata(
                    chunkIndex: index,
                    startPosition: chunk.metadata.startOffset,
                    endPosition: chunk.metadata.endOffset,
                    pageNumber: chunk.metadata.pageNumber,
                    sectionTitle: chunk.metadata.sectionTitle,
                    keywords: chunk.metadata.topKeywords,
                    semanticDensity: chunk.metadata.semanticDensity,
                    hasNumericData: chunk.metadata.hasNumericData,
                    hasListStructure: chunk.metadata.hasListStructure,
                    wordCount: chunk.metadata.wordCount,
                    characterCount: chunk.metadata.characterCount,
                    structureType: nil,  // Legacy flat text extraction
                    sectionPath: chunk.metadata.sectionPath.isEmpty ? nil : chunk.metadata.sectionPath
                )
                return ProcessedChunk(text: chunk.content, parentText: chunk.parentContent, metadata: metadata)
            }
        }

        let chunkingTime = Date().timeIntervalSince(chunkingStartTime)

    		Log.debug(
                "[DocumentProcessor] Created \(processedChunks.count) semantic chunks in \(String(format: "%.3f", chunkingTime))s",
    			category: .ingestion
    		)

        // Log semantic features detected
        let chunksWithSections = processedChunks.filter { $0.metadata.sectionTitle != nil }.count
        let chunksWithKeywords = processedChunks.filter { !$0.metadata.keywords.isEmpty }.count
        let chunksWithNumericData = processedChunks.filter { $0.metadata.hasNumericData }.count
        let chunksWithLists = processedChunks.filter { $0.metadata.hasListStructure }.count

    		Log.debug("   📑 Semantic features:", category: .ingestion)
    		Log.debug("      - Sections detected: \(chunksWithSections)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - Keywords extracted: \(chunksWithKeywords)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - Numeric data: \(chunksWithNumericData)/\(processedChunks.count)", category: .ingestion)
    		Log.debug("      - List structures: \(chunksWithLists)/\(processedChunks.count)", category: .ingestion)

        // Calculate average semantic density
        let avgSemanticDensity = processedChunks
            .map { Double($0.metadata.semanticDensity ?? 0) }
            .reduce(0.0, +) / Double(max(1, processedChunks.count))
            Log.debug("      - Avg semantic density: \(String(format: "%.3f", avgSemanticDensity))", category: .ingestion)

        // Print chunk statistics
        if !processedChunks.isEmpty {
            let chunkLengths = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkLengths.reduce(0, +) / processedChunks.count
            let minChunkSize = chunkLengths.min() ?? 0
            let maxChunkSize = chunkLengths.max() ?? 0
                Log.debug("   📊 Chunk stats: avg=\(avgChunkSize), min=\(minChunkSize), max=\(maxChunkSize) chars", category: .ingestion)

            let chunkStats = ChunkStatistics(
                averageChars: avgChunkSize,
                minChars: minChunkSize,
                maxChars: maxChunkSize
            )

            let totalTime = Date().timeIntervalSince(startTime)
                Log.debug("   ✅ Total processing: \(String(format: "%.2f", totalTime))s", category: .ingestion)

            // Create processing metadata
            let metadata = ProcessingMetadata(
                fileSizeMB: fileSizeMB,
                totalCharacters: charCount,
                totalWords: wordCount,
                extractionTimeSeconds: extractionTime,
                chunkingTimeSeconds: chunkingTime,
                embeddingTimeSeconds: 0, // Will be updated by RAGService after embeddings are generated
                totalProcessingTimeSeconds: totalTime,
                pagesProcessed: pagesProcessed,
                ocrPagesCount: ocrPagesCount,
                chunkStats: chunkStats
            )

            // Create document metadata
            let document = Document(
                id: documentId,
                filename: filename,
                fileURL: url,
                contentType: documentType,
                totalChunks: processedChunks.count,
                processingMetadata: metadata
            )

            return (document, processedChunks)
        }

        let totalTime = Date().timeIntervalSince(startTime)
            Log.debug("   ✅ Total processing: \(String(format: "%.2f", totalTime))s", category: .ingestion)

        // Create document metadata (no chunks case)
        let document = Document(
            id: documentId,
            filename: filename,
            fileURL: url,
            contentType: documentType,
            totalChunks: processedChunks.count
        )

        return (document, processedChunks)
    }

    // MARK: - Text Extraction

    /// Maps page numbers to their corresponding text range in the concatenated document string
    typealias PageTextMapping = [Int: Range<String.Index>]

    /// Holds page information from document extraction
    private struct PageInfo {
        let totalPages: Int
        let ocrPagesUsed: Int
        let pageNumbers: [Int]           // Array of page numbers corresponding to text chunks
        let pageTextRanges: PageTextMapping  // Maps page numbers to text ranges (for citations)

        init(totalPages: Int, ocrPagesUsed: Int, pageNumbers: [Int], pageTextRanges: PageTextMapping = [:]) {
            self.totalPages = totalPages
            self.ocrPagesUsed = ocrPagesUsed
            self.pageNumbers = pageNumbers
            self.pageTextRanges = pageTextRanges
        }
    }

    /// Extract text with page information for semantic chunking
    private func extractTextWithPageInfo(from url: URL, type: DocumentType) async throws -> (text: String, pageInfo: PageInfo) {
        let text: String
        var pageInfo = PageInfo(totalPages: 0, ocrPagesUsed: 0, pageNumbers: [], pageTextRanges: [:])

        switch type {
        case .pdf:
            let (extractedText, pdfPageInfo) = try await extractTextFromPDFWithPages(url: url)
            text = extractedText
            pageInfo = pdfPageInfo

        case .text, .markdown:
            do {
                // Try UTF-8 first (most common)
                text = try String(contentsOf: url, encoding: .utf8)
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
            } catch {
                // Fallback to other encodings if UTF-8 fails
                Log.warning("[DocumentProcessor] UTF-8 decode failed; trying fallback encodings", category: .ingestion)
                if let data = try? Data(contentsOf: url) {
                    if let decodedText = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
                        text = decodedText
                        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                        Log.debug("[DocumentProcessor] Decoded with fallback encoding", category: .ingestion)
                    } else {
                        throw DocumentProcessingError.unsupportedEncoding
                    }
                } else {
                    throw error
                }
            }

        case .rtf:
            text = try extractTextFromRTF(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Images - Use OCR
        case .png, .jpeg, .heic, .tiff, .gif, .image:
            Log.debug("[DocumentProcessor] Image detected; applying OCR", category: .ingestion)
            text = try await extractTextFromImage(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 1, pageNumbers: [1])

        // Code files - Preserve as-is with syntax
        case .swift, .python, .javascript, .typescript, .java, .cpp, .c, .objc,
             .go, .rust, .ruby, .php, .html, .css, .json, .xml, .yaml, .sql, .shell, .code:
            Log.debug("[DocumentProcessor] Code file detected; preserving syntax", category: .ingestion)
            text = try extractTextFromCode(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // CSV - Convert to structured text
        case .csv:
            Log.debug("[DocumentProcessor] CSV detected; converting to structured text", category: .ingestion)
            text = try extractTextFromCSV(url: url)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Office documents - Attempt extraction
        case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
            Log.debug("[DocumentProcessor] Office document detected; attempting extraction", category: .ingestion)
            text = try await extractTextFromOfficeDocument(url: url, type: type)
            pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        // Audio/Video - Use Speech transcription
        case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
            Log.debug("[DocumentProcessor] Audio/Video detected; transcribing with Speech.framework", category: .ingestion)
        text = try await extractTextFromAudioVideo(url: url)
        pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])

        case .unknown:
            // Last resort: try treating as plain text
            Log.warning("[DocumentProcessor] Unknown format; attempting plain text extraction", category: .ingestion)
            if let attemptedText = try? String(contentsOf: url, encoding: .utf8), !attemptedText.isEmpty {
                text = attemptedText
                pageInfo = PageInfo(totalPages: 1, ocrPagesUsed: 0, pageNumbers: [1])
                Log.debug("[DocumentProcessor] Extracted as plain text", category: .ingestion)
            } else {
                Log.error("[DocumentProcessor] Unsupported format: \(url.pathExtension)", category: .ingestion)
                throw DocumentProcessingError.unsupportedFormat
            }
        }

        // Edge case: Empty or whitespace-only document
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Log.error("[DocumentProcessor] Document is empty or contains only whitespace", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        // Edge case: Very short document
        if trimmedText.count < 50 {
            Log.warning("[DocumentProcessor] Very short document (\(trimmedText.count) chars)", category: .ingestion)
        }

        // Edge case: Suspiciously long document (possible issue)
        if text.count > 10_000_000 { // 10MB of text
            Log.warning("[DocumentProcessor] Very large document (\(text.count) chars)", category: .ingestion)
        }

        return (text, pageInfo)
    }

    // MARK: - Text Quality Validation

    /// Check if extracted text is likely garbage (bad OCR layer, encoding issues, etc.)
    /// Returns true if text quality is acceptable, false if OCR should be used instead
    ///
    /// This function is CRITICAL for bulletproof PDF ingestion. PDFs often have
    /// invisible/garbage text layers that PDFKit returns, but the visual content
    /// is completely different. We must detect this and fall back to OCR.
    private func isTextQualityAcceptable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            Log.debug("[DocumentProcessor] Text too short to assess quality (\(trimmed.count) chars)", category: .ingestion)
            return false
        }

        // === CHECK 1: Alphanumeric ratio (should be > 65%) ===
        // Garbage text often has many special characters, ligature placeholders, etc.
        let alphanumericCount = trimmed.filter { $0.isLetter || $0.isNumber }.count
        let alphanumericRatio = Double(alphanumericCount) / Double(trimmed.count)
        if alphanumericRatio < 0.60 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Low alphanumeric ratio: \(String(format: "%.1f", alphanumericRatio * 100))% (need 60%+)", category: .ingestion)
            return false
        }

        // === CHECK 2: Word length distribution ===
        // Garbage text often has very short or very long "words"
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3 else {
            Log.debug("[DocumentProcessor] ❌ FAIL: Too few words to assess (\(words.count))", category: .ingestion)
            return false
        }

        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        if avgWordLength < 2.5 || avgWordLength > 18.0 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal avg word length: \(String(format: "%.1f", avgWordLength))", category: .ingestion)
            return false
        }

        // === CHECK 3: Gibberish detector (consecutive non-letter sequences) ===
        let consecutiveNonLetterPattern = try? NSRegularExpression(pattern: "[^a-zA-Z0-9\\s]{4,}", options: [])
        let gibberishMatches = consecutiveNonLetterPattern?.numberOfMatches(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) ?? 0
        let gibberishRatio = Double(gibberishMatches) / Double(max(1, trimmed.count / 80))
        if gibberishRatio > 2.5 {
            Log.debug("[DocumentProcessor] ❌ FAIL: High gibberish ratio: \(String(format: "%.1f", gibberishRatio))", category: .ingestion)
            return false
        }

        // === CHECK 4: Vowel/consonant balance ===
        // Real English text has ~38% vowels, garbage is often wildly different
        let letters = trimmed.lowercased().filter { $0.isLetter }
        let vowels = letters.filter { "aeiou".contains($0) }
        let vowelRatio = Double(vowels.count) / Double(max(1, letters.count))
        if vowelRatio < 0.15 || vowelRatio > 0.65 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal vowel ratio: \(String(format: "%.1f", vowelRatio * 100))% (need 15-65%)", category: .ingestion)
            return false
        }

        // === CHECK 5: Character entropy (randomness detection) ===
        // Real text has lower entropy than random garbage
        let entropy = calculateCharacterEntropy(trimmed)
        if entropy > 5.5 {  // English text is typically 4.0-5.0 bits/char
            Log.debug("[DocumentProcessor] ❌ FAIL: High entropy (random-looking): \(String(format: "%.2f", entropy)) bits/char", category: .ingestion)
            return false
        }

        // === CHECK 6: Common English words ===
        // At least some common words should be present
        let commonPatterns = ["the ", "and ", "is ", "to ", "of ", "a ", "in ", "for ", "that ", "with ", "this ", "are ", "be ", "at ", "or "]
        let matchCount = commonPatterns.filter { trimmed.lowercased().contains($0) }.count
        let hasEnoughCommonWords = matchCount >= 2

        // If no common words AND metrics are borderline, prefer OCR
        if !hasEnoughCommonWords && (alphanumericRatio < 0.70 || vowelRatio < 0.25 || vowelRatio > 0.50) {
            Log.debug("[DocumentProcessor] ❌ FAIL: Only \(matchCount) common words found + borderline metrics", category: .ingestion)
            return false
        }

        // === CHECK 7: Sample the text for diagnostic logging ===
        let sampleLength = min(100, trimmed.count)
        let sample = String(trimmed.prefix(sampleLength)).replacingOccurrences(of: "\n", with: "↵")
        Log.debug("[DocumentProcessor] ✓ PASS: Text quality OK (alpha=\(String(format: "%.0f", alphanumericRatio * 100))%, vowel=\(String(format: "%.0f", vowelRatio * 100))%, entropy=\(String(format: "%.1f", entropy)), words=\(matchCount)) Sample: \"\(sample)...\"", category: .ingestion)

        return true
    }

    /// Calculate Shannon entropy of text (bits per character)
    /// Higher values indicate more randomness (potential garbage)
    private func calculateCharacterEntropy(_ text: String) -> Double {
        let lowered = text.lowercased()
        var frequencies: [Character: Int] = [:]

        for char in lowered where char.isLetter || char.isNumber || char == " " {
            frequencies[char, default: 0] += 1
        }

        let total = Double(frequencies.values.reduce(0, +))
        guard total > 0 else { return 0 }

        var entropy: Double = 0
        for count in frequencies.values {
            let probability = Double(count) / total
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }

        return entropy
    }

    // MARK: - Header/Footer Removal

    /// Remove repeated headers and footers from multi-page document text
    /// Detects patterns that appear at the start/end of multiple pages
    private func removeRepeatedHeadersFooters(from pageTexts: [String]) -> [String] {
        guard pageTexts.count >= 3 else { return pageTexts }  // Need multiple pages to detect patterns

        // Collect first and last lines from each page
        var firstLines: [String: Int] = [:]  // line → occurrence count
        var lastLines: [String: Int] = [:]

        for pageText in pageTexts {
            let lines = pageText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Get first 2 non-empty lines (headers)
            for line in lines.prefix(2) {
                let normalized = normalizeForComparison(line)
                if !normalized.isEmpty && normalized.count < 100 {  // Headers are typically short
                    firstLines[normalized, default: 0] += 1
                }
            }

            // Get last 2 non-empty lines (footers)
            for line in lines.suffix(2) {
                let normalized = normalizeForComparison(line)
                if !normalized.isEmpty && normalized.count < 100 {
                    lastLines[normalized, default: 0] += 1
                }
            }
        }

        // Find patterns that appear in >50% of pages
        let threshold = pageTexts.count / 2
        let repeatedHeaders = Set(firstLines.filter { $0.value > threshold }.keys)
        let repeatedFooters = Set(lastLines.filter { $0.value > threshold }.keys)

        if repeatedHeaders.isEmpty && repeatedFooters.isEmpty {
            return pageTexts  // No repeated patterns found
        }

        Log.debug(
            "[DocumentProcessor] Removing \(repeatedHeaders.count) repeated headers, \(repeatedFooters.count) footers",
            category: .ingestion
        )

        // Remove the repeated lines from each page
        return pageTexts.map { pageText in
            var lines = pageText.components(separatedBy: .newlines)

            // Remove headers (from start)
            while let firstLine = lines.first {
                let normalized = normalizeForComparison(firstLine)
                if repeatedHeaders.contains(normalized) || isPageNumber(firstLine) {
                    lines.removeFirst()
                } else if firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.removeFirst()  // Skip empty lines at start
                } else {
                    break
                }
            }

            // Remove footers (from end)
            while let lastLine = lines.last {
                let normalized = normalizeForComparison(lastLine)
                if repeatedFooters.contains(normalized) || isPageNumber(lastLine) {
                    lines.removeLast()
                } else if lastLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.removeLast()  // Skip empty lines at end
                } else {
                    break
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    /// Normalize text for header/footer comparison (ignore case, extra spaces, page numbers)
    private func normalizeForComparison(_ text: String) -> String {
        var normalized = text.lowercased()
            .trimmingCharacters(in: .whitespaces)

        // Remove page numbers for comparison (they change per page but pattern is same)
        // Matches: "Page 1", "1 of 42", "- 5 -", etc.
        let pageNumberPatterns = [
            "page\\s*\\d+",
            "\\d+\\s*of\\s*\\d+",
            "-\\s*\\d+\\s*-",
            "^\\d+$"
        ]

        for pattern in pageNumberPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                normalized = regex.stringByReplacingMatches(
                    in: normalized,
                    options: [],
                    range: NSRange(normalized.startIndex..., in: normalized),
                    withTemplate: ""
                )
            }
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    /// Check if a line is just a page number
    private func isPageNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Common page number patterns
        let patterns = [
            "^\\d+$",                           // Just a number: "5"
            "^page\\s*\\d+$",                   // "Page 5"
            "^\\d+\\s*of\\s*\\d+$",             // "5 of 42"
            "^-\\s*\\d+\\s*-$",                 // "- 5 -"
            "^\\[\\d+\\]$",                     // "[5]"
            "^\\(\\d+\\)$"                      // "(5)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        return false
    }

    /// Extract text from PDF with page tracking for semantic chunking
    /// Uses spatial-aware extraction to handle multi-column layouts correctly
    private func extractTextFromPDFWithPages(url: URL) async throws -> (text: String, pageInfo: PageInfo) {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        var pageTexts: [String] = []  // Collect page texts first for header/footer removal
        var pagesWithoutText = 0
        var ocrUsedCount = 0
        var totalOCRChars = 0
        var spatialExtractionCount = 0

        // PASS 1: Extract text from all pages
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                pageTexts.append("")
                continue
            }

            let pageStartTime = Date()
            let pageNumber = pageIndex + 1  // 1-indexed for user-facing citations
            var extractedPageText = ""

            // Try standard text extraction first to check if text layer exists
            let pageText = page.string
            let hasText = pageText != nil && !pageText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Check if extracted text is actually readable (not garbage from bad OCR layer)
            let textQualityOK = hasText && isTextQualityAcceptable(pageText!)

            if hasText && textQualityOK {
                // ENHANCEMENT: Use spatial-aware extraction to preserve column ordering
                // This prevents left-column and right-column text from being interleaved
                if let spatialText = extractTextWithSpatialOrdering(from: page), !spatialText.isEmpty {
                    extractedPageText = spatialText
                    spatialExtractionCount += 1
                    progressHandler?("page \(pageNumber)/\(pageCount)")
                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageNumber): \(spatialText.count) chars (spatial, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                } else {
                    // Fall back to simple extraction
                    progressHandler?("page \(pageNumber)/\(pageCount)")
                    extractedPageText = pageText!
                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageNumber): \(pageText!.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                }
            } else if hasText && !textQualityOK {
                // Text exists but quality is poor - try OCR instead
                Log.debug("   ⚠️ Page \(pageNumber): Text layer quality poor, trying OCR...", category: .ingestion)
                progressHandler?("page \(pageNumber)/\(pageCount), OCR (quality)")

                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty,
                   isTextQualityAcceptable(ocrText) {
                    extractedPageText = ocrText
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageNumber): OCR replaced garbage text (\(ocrText.count) chars, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                } else {
                    extractedPageText = pageText!
                    Log.warning("   ⚠️ Page \(pageNumber): Using original text despite quality concerns", category: .ingestion)
                }
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1
                progressHandler?("page \(pageNumber)/\(pageCount), OCR")
                try? await Task.sleep(nanoseconds: 50_000_000)

                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty {
                    extractedPageText = ocrText
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageNumber): OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                }
            }

            pageTexts.append(extractedPageText)
        }

        // PASS 2: Remove repeated headers and footers
        progressHandler?("cleaning headers/footers")
        let cleanedPageTexts = removeRepeatedHeadersFooters(from: pageTexts)

        // PASS 3: Assemble final text with page mappings
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex

            if !cleanedText.isEmpty {
                fullText += cleanedText + "\n\n"
                let pageEndIndex = fullText.endIndex
                pageTextRanges[pageNumber] = pageStartIndex..<pageEndIndex
            }
        }

        // Report extraction methods used
        if ocrUsedCount > 0 {
            Log.debug(
                "[DocumentProcessor] OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)",
                category: .ingestion
            )
        }
        if spatialExtractionCount > 0 {
            Log.info(
                "[DocumentProcessor] Spatial extraction (multi-column aware) used on \(spatialExtractionCount)/\(pageCount) pages",
                category: .ingestion
            )
        }

        // Log page mapping stats for debugging
        Log.debug("[DocumentProcessor] Built page→text mapping for \(pageTextRanges.count) pages", category: .ingestion)

        let pageInfo = PageInfo(
            totalPages: pageCount,
            ocrPagesUsed: ocrUsedCount,
            pageNumbers: Array(1...pageCount),
            pageTextRanges: pageTextRanges
        )

        return (fullText, pageInfo)
    }

    // MARK: - Structured Document Parsing (iOS 26+)

    /// Extract PDF content with structure awareness (tables, lists, paragraphs as separate elements)
    /// On iOS 26+, uses Vision's RecognizeDocumentsRequest for structure-aware parsing.
    /// This preserves tabular data integrity - specs in one table won't mix with unrelated data.
    private func extractStructuredPDFContent(url: URL) async throws -> StructuredExtractionResult {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed for structured parsing: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocumentProcessingError.emptyDocument
        }

        // Check if structured parsing is available (iOS 26+)
        if #available(iOS 26.0, *) {
            return try await extractWithStructuredParsing(pdfDocument: pdfDocument, pageCount: pageCount)
        } else {
            // Fallback to regular extraction on older iOS versions
            Log.debug("[DocumentProcessor] iOS < 26: Using flat text extraction (no structure awareness)", category: .ingestion)
            let (text, pageInfo) = try await extractTextFromPDFWithPages(url: url)
            return StructuredExtractionResult(
                text: text,
                pageInfo: pageInfo,
                structuredElements: [],
                usedStructuredParsing: false
            )
        }
    }

    /// iOS 26+ structured parsing using Vision's RecognizeDocumentsRequest
    @available(iOS 26.0, *)
    private func extractWithStructuredParsing(pdfDocument: PDFDocument, pageCount: Int) async throws -> StructuredExtractionResult {
        let parser = StructuredDocumentParser.shared

        var allElements: [StructuredElementWrapper] = []
        var pageTexts: [String] = []
        var pagesWithStructure = 0
        var ocrUsedCount = 0

        Log.info("[DocumentProcessor] Starting structured parsing for \(pageCount) pages (iOS 26+)", category: .ingestion)

        for pageIndex in 0..<pageCount {
            let pageNumber = pageIndex + 1
            progressHandler?("structured parse \(pageNumber)/\(pageCount)")

            guard let page = pdfDocument.page(at: pageIndex) else {
                pageTexts.append("")
                continue
            }

            // Render page as image for Vision API
            guard let pageImage = renderPDFPageAsImage(page: page) else {
                Log.warning("[DocumentProcessor] Failed to render page \(pageNumber) for structured parsing", category: .ingestion)
                // Fallback to plain text extraction for this page
                if let plainText = page.string, !plainText.isEmpty {
                    pageTexts.append(plainText)
                    allElements.append(StructuredElementWrapper(
                        text: plainText,
                        elementType: "paragraph",
                        pageNumber: pageNumber,
                        isAtomicChunk: false
                    ))
                } else {
                    pageTexts.append("")
                }
                continue
            }

            do {
                // Use structured document parser
                let structuredContent = try await parser.parsePageImage(pageImage, pageNumber: pageNumber)

                if structuredContent.hasStructuredContent {
                    pagesWithStructure += 1
                }

                // Log figure references if any were found
                if !structuredContent.figureReferences.isEmpty {
                    Log.debug("[DocumentProcessor] Page \(pageNumber) has \(structuredContent.figureReferences.count) figure references: \(structuredContent.figureReferences.prefix(3).joined(separator: ", "))", category: .ingestion)
                }

                // Use effectiveContent which automatically falls back to raw text if quality is low
                // This ensures we don't lose content from low-quality scans
                let elementsToUse = structuredContent.effectiveContent

                // Convert structured elements to wrappers
                for element in elementsToUse {
                    let isAtomic = element.elementType == "table"  // Tables should not be split

                    // Extract detected entities from table elements
                    var entities: [(type: String, value: String)] = []
                    if case .table(let tableData) = element {
                        entities = tableData.detectedEntities.map { ($0.type.rawValue, $0.value) }
                    }

                    allElements.append(StructuredElementWrapper(
                        text: element.textForEmbedding,
                        elementType: element.elementType,
                        pageNumber: element.pageNumber,
                        isAtomicChunk: isAtomic,
                        detectedEntities: entities
                    ))
                }

                // Add figure references as searchable content (so queries about figures work)
                if !structuredContent.figureReferences.isEmpty {
                    let figureText = "[Visual Content on Page \(pageNumber)]\n" + structuredContent.figureReferences.joined(separator: "\n")
                    allElements.append(StructuredElementWrapper(
                        text: figureText,
                        elementType: "figure",
                        pageNumber: pageNumber,
                        isAtomicChunk: true,
                        detectedEntities: []
                    ))
                }

                // Use raw text for page text assembly
                pageTexts.append(structuredContent.rawText)

            } catch StructuredParsingError.noDocumentDetected {
                // No document content - try OCR fallback
                if let ocrText = try? await performOCR(on: pageImage), !ocrText.isEmpty {
                    pageTexts.append(ocrText)
                    ocrUsedCount += 1
                    allElements.append(StructuredElementWrapper(
                        text: ocrText,
                        elementType: "paragraph",
                        pageNumber: pageNumber,
                        isAtomicChunk: false
                    ))
                } else {
                    pageTexts.append("")
                }

            } catch {
                Log.warning("[DocumentProcessor] Structured parsing failed for page \(pageNumber): \(error.localizedDescription)", category: .ingestion)
                // Fallback to plain text
                if let plainText = page.string, !plainText.isEmpty {
                    pageTexts.append(plainText)
                } else {
                    pageTexts.append("")
                }
            }
        }

        Log.info("[DocumentProcessor] Structured parsing complete: \(pagesWithStructure)/\(pageCount) pages with tables/lists, \(allElements.count) elements extracted", category: .ingestion)

        // Clean headers/footers and assemble text
        let cleanedPageTexts = removeRepeatedHeadersFooters(from: pageTexts)
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex
            if !cleanedText.isEmpty {
                fullText += cleanedText + "\n\n"
                pageTextRanges[pageNumber] = pageStartIndex..<fullText.endIndex
            }
        }

        let pageInfo = PageInfo(
            totalPages: pageCount,
            ocrPagesUsed: ocrUsedCount,
            pageNumbers: Array(1...pageCount),
            pageTextRanges: pageTextRanges
        )

        return StructuredExtractionResult(
            text: fullText,
            pageInfo: pageInfo,
            structuredElements: allElements,
            usedStructuredParsing: pagesWithStructure > 0
        )
    }

    /// Create chunks that respect document structure (tables as atomic units, paragraphs chunked normally)
    /// Tables are kept as single chunks to preserve data integrity across any domain.
    private func createStructureAwareChunks(
        elements: [StructuredElementWrapper],
        fullText: String,
        config: SemanticChunker.ChunkingConfig,
        documentId: UUID,
        pageInfo: PageInfo
    ) -> [ProcessedChunk] {
        var chunks: [ProcessedChunk] = []
        var chunkIndex = 0

        // Collect all detected entities from structured elements
        var allDetectedEntities: [(type: String, value: String)] = []
        for element in elements {
            allDetectedEntities.append(contentsOf: element.detectedEntities)
        }

        // Store entities for vocabulary learning
        self.lastDetectedEntities = allDetectedEntities
        if !allDetectedEntities.isEmpty {
            Log.info("[DocumentProcessor] Collected \(allDetectedEntities.count) Vision-detected entities for vocabulary learning", category: .ingestion)
        }

        // Group paragraphs for semantic chunking, but tables and lists become atomic chunks
        var paragraphBuffer: [(text: String, page: Int)] = []

        func flushParagraphBuffer() {
            guard !paragraphBuffer.isEmpty else { return }

            // Combine paragraphs for semantic chunking
            let combinedText = paragraphBuffer.map { $0.text }.joined(separator: "\n\n")
            let primaryPage = paragraphBuffer.first?.page

            let semanticChunker = SemanticChunker()
            let subChunks = semanticChunker.chunkText(
                combinedText,
                documentId: documentId,
                config: config,
                pageNumbers: nil
            )

            for subChunk in subChunks {
                let metadata = ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: subChunk.metadata.startOffset,
                    endPosition: subChunk.metadata.endOffset,
                    pageNumber: primaryPage ?? subChunk.metadata.pageNumber,
                    sectionTitle: subChunk.metadata.sectionTitle,
                    keywords: subChunk.metadata.topKeywords,
                    semanticDensity: subChunk.metadata.semanticDensity,
                    hasNumericData: subChunk.metadata.hasNumericData,
                    hasListStructure: subChunk.metadata.hasListStructure,
                    wordCount: subChunk.metadata.wordCount,
                    characterCount: subChunk.metadata.characterCount,
                    structureType: "paragraph",
                    sectionPath: subChunk.metadata.sectionPath.isEmpty ? nil : subChunk.metadata.sectionPath
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

        // Track section context for table association
        var currentSectionTitle: String? = nil
        var currentSectionPath: [String] = []

        for element in elements {
            // Track section titles for context association
            if element.elementType == "title" {
                let titleText = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
                currentSectionTitle = titleText
                // Build section path (max 3 levels)
                if currentSectionPath.count >= 3 {
                    currentSectionPath.removeFirst()
                }
                currentSectionPath.append(titleText)
            }

            if element.isAtomicChunk {
                // Flush any pending paragraphs first
                flushParagraphBuffer()

                // Tables and important lists become single atomic chunks
                var text = element.text
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                // ENHANCEMENT: Prepend section context to table for better retrieval
                // This helps queries like "oil specifications" find the right table
                var contextPrefix = ""
                if let sectionTitle = currentSectionTitle, element.elementType == "table" {
                    contextPrefix = "Section: \(sectionTitle)\n"
                    text = contextPrefix + text
                    Log.debug("[DocumentProcessor] Table associated with section: \(sectionTitle)", category: .ingestion)
                }

                let wordCount = text.split(separator: " ").count
                let metadata = ChunkMetadata(
                    chunkIndex: chunkIndex,
                    startPosition: 0,
                    endPosition: text.count,
                    pageNumber: element.pageNumber,
                    sectionTitle: currentSectionTitle,  // NOW carries section context
                    keywords: extractKeywordsFromStructuredElement(text, type: element.elementType),
                    semanticDensity: 0.8,  // Tables are very information-dense
                    hasNumericData: element.elementType == "table",
                    hasListStructure: element.elementType == "list",
                    wordCount: wordCount,
                    characterCount: text.count,
                    structureType: element.elementType,
                    sectionPath: currentSectionPath.isEmpty ? nil : currentSectionPath  // NOW carries section path
                )

                chunks.append(ProcessedChunk(
                    text: text,
                    parentText: currentSectionTitle,  // Parent text is the section title
                    metadata: metadata
                ))
                chunkIndex += 1

                Log.debug("[DocumentProcessor] Created atomic \(element.elementType) chunk (\(wordCount) words) from page \(element.pageNumber), section: \(currentSectionTitle ?? "none")", category: .ingestion)

            } else if element.elementType == "paragraph" || element.elementType == "title" {
                // Buffer paragraphs for semantic chunking
                paragraphBuffer.append((text: element.text, page: element.pageNumber))
            } else {
                // Lists that aren't atomic get buffered too
                paragraphBuffer.append((text: element.text, page: element.pageNumber))
            }
        }

        // Flush any remaining paragraphs
        flushParagraphBuffer()

        // Log structure breakdown
        let tableChunks = chunks.filter { $0.metadata.structureType == "table" }.count
        let listChunks = chunks.filter { $0.metadata.structureType == "list" }.count
        let paragraphChunks = chunks.filter { $0.metadata.structureType == "paragraph" }.count

        Log.info("[DocumentProcessor] Structure-aware chunking: \(tableChunks) tables, \(listChunks) lists, \(paragraphChunks) paragraphs", category: .ingestion)

        return chunks
    }

    /// Extract keywords from structured elements using NLTagger (domain-agnostic)
    /// Leverages Apple's NLP for nouns, technical terms, and alphanumeric patterns
    private func extractKeywordsFromStructuredElement(_ text: String, type: String) -> [String] {
        var keywords: [String] = []

        // Use NLTagger to extract nouns and technical terms (domain-agnostic)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text

        // Extract nouns and proper nouns (key terms in any domain)
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(text[range]).trimmingCharacters(in: .punctuationCharacters)
                if word.count >= 3 {
                    keywords.append(word.lowercased())
                }
            }
            return true
        }

        // Detect alphanumeric codes/identifiers (e.g., "SAE 0W-20", "API-1234", "ISO 9001")
        // These patterns appear in technical specs across ALL domains
        let alphanumericPattern = #"\b[A-Z]{2,}[-\s]?\d+[A-Z\d-]*\b"#
        if let regex = try? NSRegularExpression(pattern: alphanumericPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    keywords.append(String(text[range]).uppercased())
                }
            }
        }

        // Detect measurement patterns (numbers with units - universal across domains)
        let measurementPattern = #"\b\d+(?:\.\d+)?\s*(?:mg|kg|ml|L|mm|cm|m|ft|in|oz|lb|psi|kPa|V|A|W|Hz|°[CF]|%)\b"#
        if let regex = try? NSRegularExpression(pattern: measurementPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    keywords.append(String(text[range]))
                }
            }
        }

        return Array(Set(keywords)).prefix(20).map { $0 }  // Deduplicate, limit to top 20
    }

    /// Extract text from PDF using PDFKit (native iOS framework) - Legacy method
    /// Now with OCR fallback for image-only pages
    private func extractTextFromPDF(url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] PDF load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        var fullText = ""
        var pagesWithoutText = 0
        var ocrUsedCount = 0
        var totalOCRChars = 0

        // Extract text from all pages, with OCR fallback for image-only pages
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageStartTime = Date()

            // Try standard text extraction first
            let pageText = page.string
            let hasText = pageText != nil && !pageText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let textQualityOK = hasText && isTextQualityAcceptable(pageText!)

            if hasText && textQualityOK {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                // Delay to ensure UI updates (increased for visibility)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

                fullText += pageText! + "\n\n"

                let pageTime = Date().timeIntervalSince(pageStartTime)
                Log.debug("   ✓ Page \(pageIndex + 1): \(pageText!.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
            } else if hasText && !textQualityOK {
                // Text exists but quality is poor - try OCR instead
                Log.debug("   ⚠️ Page \(pageIndex + 1): Text layer quality poor, trying OCR...", category: .ingestion)
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR (quality)")

                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty,
                   isTextQualityAcceptable(ocrText) {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageIndex + 1): OCR replaced garbage text (\(ocrText.count) chars, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                } else {
                    // OCR didn't help - fall back to original text
                    fullText += pageText! + "\n\n"
                    Log.warning("   ⚠️ Page \(pageIndex + 1): Using original text despite quality concerns", category: .ingestion)
                }
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1

                // Update progress for OCR
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR")
                // Small delay to ensure UI updates
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s

                // Render page as image and apply OCR
                if let pageImage = renderPDFPageAsImage(page: page),
                   let ocrText = try? await performOCR(on: pageImage),
                   !ocrText.isEmpty {
                    fullText += ocrText + "\n\n"
                    ocrUsedCount += 1
                    totalOCRChars += ocrText.count

                    let pageTime = Date().timeIntervalSince(pageStartTime)
                    Log.debug("   ✓ Page \(pageIndex + 1): OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                }
            }
        }

        // Report OCR usage
        if ocrUsedCount > 0 {
            Log.debug("[DocumentProcessor] OCR applied to \(ocrUsedCount)/\(pageCount) pages (\(totalOCRChars) chars total)", category: .ingestion)
        }

        if pagesWithoutText > 0 && ocrUsedCount == 0 {
            Log.warning("[DocumentProcessor] \(pagesWithoutText) pages had no extractable text (may be images)", category: .ingestion)
        }

        // Only throw error if NO text was extracted at all
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            if pagesWithoutText == pageCount {
                Log.error("[DocumentProcessor] PDF contains no extractable text (all pages are images)", category: .ingestion)
                Log.info("[DocumentProcessor] Hint: OCR attempted but found no text. Image quality may be too low.", category: .ingestion)
                Log.info("[DocumentProcessor] Suggestion: Try a higher quality scan or text-based PDF", category: .ingestion)
            }
            throw DocumentProcessingError.imageOnlyPDF
        }

        return fullText
    }

    /// Render a PDF page as a high-resolution image for OCR processing
    /// Uses 3x scale (216 DPI) for optimal Vision OCR accuracy
    /// Apple's Vision framework works best at 150-300 DPI
    private func renderPDFPageAsImage(page: PDFPage, scale: CGFloat = 3.0) -> CIImage? {
        let pageBounds = page.bounds(for: .mediaBox)

        // Scale up for OCR accuracy - Vision needs high DPI images
        // PDF pages are typically 72 DPI, so 3x = 216 DPI (optimal for text recognition)
        let scaledSize = CGSize(
            width: pageBounds.size.width * scale,
            height: pageBounds.size.height * scale
        )

        #if canImport(UIKit)
        // Use opaque format to avoid alpha channel overhead
        // This prevents the "AlphaPremulLast" warning and halves memory usage
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true  // No alpha channel needed - we draw on white background
        format.scale = 1.0    // We've already scaled the size

        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            // Scale up the PDF rendering
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: 0, y: pageBounds.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI)", category: .ingestion)
        return CIImage(image: image)
        #elseif canImport(AppKit)
        guard scaledSize.width > 0 && scaledSize.height > 0 else { return nil }

        let image = NSImage(size: scaledSize)
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: scaledSize)).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: pageBounds.size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return nil
        }

        Log.debug("[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI)", category: .ingestion)
        return CIImage(cgImage: cgImage)
        #else
        return nil
        #endif
    }

    // MARK: - PDF Image Extraction (Visual Document Understanding)

    /// Extract embedded images from a PDF page for visual understanding
    /// Returns array of (image, bounds) tuples where bounds are normalized coordinates
    private func extractImagesFromPDFPage(page: PDFPage) -> [(image: CIImage, bounds: CGRect)] {
        var extractedImages: [(CIImage, CGRect)] = []
        let pageBounds = page.bounds(for: .mediaBox)

        // PDFKit doesn't directly expose embedded images, so we use annotations
        // and render specific regions that might contain images
        // For a more comprehensive solution, we'd need to parse the PDF stream

        // Strategy 1: Look for image annotations
        for annotation in page.annotations {
            if let bounds = annotation.bounds as CGRect?,
               bounds.width > 50, bounds.height > 50
            { // Filter out small icons
                // Render this region
                if let regionImage = renderPDFRegion(page: page, region: bounds) {
                    // Normalize bounds to 0-1 range
                    let normalizedBounds = CGRect(
                        x: bounds.minX / pageBounds.width,
                        y: bounds.minY / pageBounds.height,
                        width: bounds.width / pageBounds.width,
                        height: bounds.height / pageBounds.height
                    )
                    extractedImages.append((regionImage, normalizedBounds))
                }
            }
        }

        // Strategy 2: If page has no extractable text but renders as image,
        // the whole page might be a scanned image
        if page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            if let fullPageImage = renderPDFPageAsImage(page: page) {
                let normalizedBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                extractedImages.append((fullPageImage, normalizedBounds))
            }
        }

        return extractedImages
    }

    /// Render a specific region of a PDF page as an image
    private func renderPDFRegion(page: PDFPage, region: CGRect) -> CIImage? {
        #if canImport(UIKit)
            let scale: CGFloat = 2.0 // 2x for better quality
            let size = CGSize(width: region.width * scale, height: region.height * scale)

            // Use opaque format to avoid alpha channel overhead
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 1.0

            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: size))

                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: -region.minX, y: region.maxY - page.bounds(for: .mediaBox).height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)

                page.draw(with: .mediaBox, to: context.cgContext)
            }
            return CIImage(image: image)
        #else
            return nil
        #endif
    }

    /// Extract images from entire PDF document with page tracking
    func extractAllImagesFromPDF(url: URL) async -> [(image: CIImage, pageNumber: Int, bounds: CGRect)] {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.warning("[DocumentProcessor] Cannot extract images: PDF load failed", category: .ingestion)
            return []
        }

        var allImages: [(CIImage, Int, CGRect)] = []

        for pageIndex in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            let pageImages = extractImagesFromPDFPage(page: page)
            for (image, bounds) in pageImages {
                allImages.append((image, pageIndex + 1, bounds))
            }
        }

        Log.info("[DocumentProcessor] Extracted \(allImages.count) images from PDF", category: .ingestion)
        return allImages
    }

    /// Process a PDF with full visual understanding (text + images)
    /// Returns extracted text with image descriptions interleaved at appropriate positions
    func processDocumentWithVisualUnderstanding(at url: URL) async throws -> (text: String, visualMetadata: VisualContentMetadata) {
        guard url.pathExtension.lowercased() == "pdf" else {
            // Non-PDF documents don't have embedded images in the same way
            return try (await extractTextWithPageInfo(from: url, type: detectDocumentType(url: url)).text, .empty)
        }

        guard let pdfDocument = PDFDocument(url: url) else {
            throw DocumentProcessingError.pdfLoadFailed
        }

        let startTime = Date()
        var fullText = ""
        var perPageTextObservations: [[VNRecognizedTextObservation]] = []
        var extractedImages: [(image: CIImage, pageNumber: Int, bounds: CGRect)] = []

        // First pass: Extract text with bounding boxes for caption matching
        for pageIndex in 0 ..< pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            let pageNumber = pageIndex + 1

            progressHandler?("analyzing page \(pageNumber)/\(pdfDocument.pageCount)")

            // Get text
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n\n"
                perPageTextObservations.append([]) // No OCR observations for native text
            } else if let pageImage = renderPDFPageAsImage(page: page) {
                // OCR with observations for caption matching
                let observations = try await performOCRWithObservations(on: pageImage)
                perPageTextObservations.append(observations)

                let ocrText = extractTextWithColumnAwareness(from: observations)
                fullText += ocrText + "\n\n"
            } else {
                perPageTextObservations.append([])
            }

            // Extract images from this page
            let pageImages = extractImagesFromPDFPage(page: page)
            for (image, bounds) in pageImages {
                extractedImages.append((image, pageNumber, bounds))
            }
        }

        // Second pass: Analyze images with ImageUnderstandingService
        var visualMetadata = VisualContentMetadata.empty

        if !extractedImages.isEmpty {
            progressHandler?("analyzing \(extractedImages.count) images")

            let (analyzedImages, metadata) = await ImageUnderstandingService.shared.analyzeDocumentImages(
                images: extractedImages,
                textObservations: perPageTextObservations
            )

            visualMetadata = metadata

            // Append compact image descriptions to text for embedding
            // Cap total image text to avoid overwhelming document/context budgets
            let maxImageTextPerDoc = 3000  // ~2 chunks worth of image descriptions max
            var totalImageTextAdded = 0

            for analyzed in analyzedImages {
                // Skip if we've hit the budget
                if totalImageTextAdded >= maxImageTextPerDoc { break }

                var imageText = "\n[Figure p.\(analyzed.pageNumber)"
                if analyzed.contentType != .unknown {
                    imageText += " - \(analyzed.contentType.rawValue)"
                }
                imageText += "]"

                // Prioritize: extracted text > caption > description (most useful first)
                var contentParts: [String] = []

                // Extracted text is most valuable (actual labels in diagrams)
                if let extractedText = analyzed.extractedText, !extractedText.isEmpty {
                    let truncated = String(extractedText.prefix(200))
                    contentParts.append(truncated)
                }

                // Caption is next most valuable
                if let caption = analyzed.associatedCaption {
                    let truncated = String(caption.prefix(150))
                    contentParts.append("Caption: \(truncated)")
                }

                // Full description only if we have room and no other content
                if contentParts.isEmpty, let description = analyzed.description {
                    let truncated = String(description.prefix(200))
                    contentParts.append(truncated)
                }

                if !contentParts.isEmpty {
                    imageText += " " + contentParts.joined(separator: ". ")
                }

                // Cap per-image text and track total
                let finalImageText = String(imageText.prefix(400)) + "\n"
                totalImageTextAdded += finalImageText.count
                fullText += finalImageText
            }

            if analyzedImages.count > 0 {
                Log.debug("[DocumentProcessor] Added \(totalImageTextAdded) chars of image descriptions (\(analyzedImages.count) images)", category: .ingestion)
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)
        Log.info("[DocumentProcessor] Visual understanding complete in \(String(format: "%.2f", processingTime))s: \(extractedImages.count) images analyzed", category: .ingestion)

        return (fullText, visualMetadata)
    }

    /// Perform OCR and return raw observations for spatial analysis
    /// Uses same bulletproof configuration as performOCR()
    private func performOCRWithObservations(on image: CIImage) async throws -> [VNRecognizedTextObservation] {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: observations)
            }

            // === BULLETPROOF OCR CONFIGURATION (same as performOCR) ===
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]
            request.minimumTextHeight = 0.0
            // Note: customWords left empty - Vision's language correction handles domain terms
            // Adding domain-specific words here would make the app less universal

            do {
                try requestHandler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Extract text from RTF using native AttributedString
    private func extractTextFromRTF(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]

        var documentAttributes: NSDictionary?
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: &documentAttributes
        ) else {
            throw DocumentProcessingError.rtfParseFailed
        }
        return attributedString.string
    }

    /// Extract text from images using Vision framework OCR
    private func extractTextFromImage(url: URL) async throws -> String {
        progressHandler?("OCR scanning")
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s to show OCR status

        let startTime = Date()

        guard let image = CIImage(contentsOf: url) else {
            Log.error("[DocumentProcessor] Failed to load image: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.imageLoadFailed
        }

        let imageSize = image.extent.size
        Log.debug("[DocumentProcessor] Image dimensions: \(Int(imageSize.width))×\(Int(imageSize.height))px", category: .ingestion)

        let text = try await performOCR(on: image)
        let ocrTime = Date().timeIntervalSince(startTime)

        Log.debug("[DocumentProcessor] OCR extracted \(text.count) chars in \(String(format: "%.2f", ocrTime))s", category: .ingestion)

        return text
    }

    /// Perform OCR on an image using Vision framework with layout-aware text ordering
    /// Configured for maximum accuracy with Apple's latest Vision capabilities
    private func performOCR(on image: CIImage) async throws -> String {
        let requestHandler = VNImageRequestHandler(ciImage: image, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    Log.error("[DocumentProcessor] OCR failed: \(error.localizedDescription)", category: .ingestion)
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    Log.warning("[DocumentProcessor] OCR returned no results", category: .ingestion)
                    continuation.resume(returning: "")
                    return
                }

                Log.debug("[DocumentProcessor] OCR found \(observations.count) text blocks", category: .ingestion)

                // VISUAL DOCUMENT UNDERSTANDING: Sort observations by reading order
                // Vision uses normalized coordinates where (0,0) is bottom-left
                // Sort by Y descending (top to bottom), then X ascending (left to right)
                let sortedObservations = observations.sorted { obs1, obs2 in
                    let box1 = obs1.boundingBox
                    let box2 = obs2.boundingBox

                    // Use a threshold to detect "same line" (within 2% of image height)
                    let lineThreshold: CGFloat = 0.02
                    let y1 = box1.midY
                    let y2 = box2.midY

                    // If on different lines, sort top-to-bottom (higher Y = higher on page in Vision coords)
                    if abs(y1 - y2) > lineThreshold {
                        return y1 > y2 // Higher Y value means higher on the page
                    }

                    // Same line: sort left-to-right
                    return box1.minX < box2.minX
                }

                // Detect potential columns by analyzing X-position clusters
                let columnText = self.extractTextWithColumnAwareness(from: sortedObservations)

                continuation.resume(returning: columnText)
            }

            // === BULLETPROOF OCR CONFIGURATION ===

            // Use latest Vision revision for best accuracy
            request.revision = VNRecognizeTextRequestRevision3

            // Maximum accuracy mode (uses neural network)
            request.recognitionLevel = .accurate

            // Enable language correction (NLP post-processing)
            request.usesLanguageCorrection = true

            // Automatically detect language (iOS 16+)
            // This is better than hardcoded language list for mixed-language docs
            request.automaticallyDetectsLanguage = true

            // Prioritize English but support many languages
            // Order matters - first language is preferred
            request.recognitionLanguages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"]

            // Capture small text (important for footnotes, table cells, diagrams)
            // 0.0 = detect all text regardless of size (relative to image height)
            request.minimumTextHeight = 0.0

            // Note: customWords left empty - Vision's language correction handles domain terms
            // Adding domain-specific words here would make the app less universal

            do {
                try requestHandler.perform([request])
            } catch {
                Log.error("[DocumentProcessor] OCR request failed: \(error.localizedDescription)", category: .ingestion)
                continuation.resume(throwing: error)
            }
        }
    }

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
    private func extractTextWithSpatialOrdering(from page: PDFPage) -> String? {
        // Get all selections for lines on this page
        // We'll enumerate through the page character by character to find line boundaries
        guard let pageString = page.string, !pageString.isEmpty else { return nil }

        // Use word-level selection to build spatial lines
        var spatialLines: [SpatialLine] = []
        var currentLineText = ""
        var currentLineY: CGFloat = -1
        var currentLineBounds: CGRect = .zero
        var lineXPositions: [CGFloat] = []

        // Enumerate words and group into lines based on Y position
        let words = pageString.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var wordIndex = 0

        for word in words {
            let wordString = String(word)

            // Try to find this word in the page and get its bounds
            if let selection = page.selection(for: NSRange(location: wordIndex, length: wordString.count)),
               let firstChar = selection.selectionsByLine().first {

                let bounds = firstChar.bounds(for: page)

                // Check if this is a new line (Y position changed significantly)
                let yThreshold: CGFloat = bounds.height * 0.5
                let isNewLine = currentLineY >= 0 && abs(bounds.midY - currentLineY) > yThreshold

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
            }

            wordIndex += wordString.count + 1 // +1 for separator
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

        // If we couldn't get spatial info, fall back to simple extraction
        guard spatialLines.count > 3 else { return nil }

        // Detect columns from X positions
        let xPositions = spatialLines.map { $0.xPosition }
        let pageWidth = page.bounds(for: .mediaBox).width
        let columnBoundaries = detectColumnBoundaries(from: xPositions, pageWidth: pageWidth)

        if columnBoundaries.isEmpty {
            // Single column - just sort by Y (top to bottom)
            let sorted = spatialLines.sorted { $0.yPosition > $1.yPosition }
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
            let sortedColumn = group.sorted { $0.yPosition > $1.yPosition }
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

    /// Extract text with awareness of multi-column layouts
    /// Groups observations by columns and processes each column top-to-bottom
    private func extractTextWithColumnAwareness(from observations: [VNRecognizedTextObservation]) -> String {
        guard !observations.isEmpty else { return "" }

        // Collect X midpoints to detect columns
        let xMidpoints = observations.map { $0.boundingBox.midX }
        let columns = detectColumns(from: xMidpoints)

        // If single column or can't detect columns, use simple reading order
        guard columns.count > 1 else {
            Log.debug("[DocumentProcessor] Single column layout detected", category: .ingestion)
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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

        // Sort each column top-to-bottom and extract text
        var allText: [String] = []
        for (index, group) in columnGroups.enumerated() {
            let sortedGroup = group.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            let columnText = sortedGroup.compactMap { $0.topCandidates(1).first?.string }

            if !columnText.isEmpty {
                Log.debug("[DocumentProcessor] Column \(index + 1): \(columnText.count) text blocks", category: .ingestion)
                allText.append(contentsOf: columnText)
                allText.append("") // Paragraph break between columns
            }
        }

        return allText.joined(separator: "\n")
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

    // MARK: - Table Detection

    /// Detected table structure from OCR observations
    struct DetectedTable: Sendable {
        let rows: [[String]]
        let boundingBox: CGRect
        let confidence: Float

        /// Convert table to readable text format
        func toText() -> String {
            guard !rows.isEmpty else { return "" }

            var output = "[Table]\n"

            // Header row
            if let header = rows.first {
                output += "| " + header.joined(separator: " | ") + " |\n"
                output += "|" + header.map { _ in "---" }.joined(separator: "|") + "|\n"
            }

            // Data rows
            for row in rows.dropFirst() {
                output += "| " + row.joined(separator: " | ") + " |\n"
            }

            output += "[/Table]\n"
            return output
        }
    }

    /// Detect tables in OCR observations using grid alignment analysis
    /// Returns detected tables and remaining non-table observations
    func detectTables(from observations: [VNRecognizedTextObservation]) -> (tables: [DetectedTable], remaining: [VNRecognizedTextObservation]) {
        guard observations.count >= 4 else {
            return ([], observations)
        }

        // Group observations by Y position (rows)
        let lineThreshold: CGFloat = 0.02 // 2% of page height = same row
        var rows: [[VNRecognizedTextObservation]] = []
        var currentRow: [VNRecognizedTextObservation] = []
        var lastY: CGFloat = -1

        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        for obs in sorted {
            let y = obs.boundingBox.midY
            if lastY < 0 || abs(y - lastY) < lineThreshold {
                currentRow.append(obs)
            } else {
                if !currentRow.isEmpty {
                    rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
                }
                currentRow = [obs]
            }
            lastY = y
        }
        if !currentRow.isEmpty {
            rows.append(currentRow.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
        }

        // Detect table regions: multiple rows with consistent column count
        var tables: [DetectedTable] = []
        var tableObservations: Set<UUID> = []
        var i = 0

        while i < rows.count {
            let columnCount = rows[i].count

            // Need at least 2 columns and 2 rows for a table
            if columnCount >= 2 {
                var tableRows: [[VNRecognizedTextObservation]] = [rows[i]]
                var j = i + 1

                // Find consecutive rows with similar column count (±1)
                while j < rows.count {
                    let nextColCount = rows[j].count
                    if abs(nextColCount - columnCount) <= 1, nextColCount >= 2 {
                        tableRows.append(rows[j])
                        j += 1
                    } else {
                        break
                    }
                }

                // If we found 2+ rows with consistent columns, it's likely a table
                if tableRows.count >= 2 {
                    // Check X-alignment consistency (column structure)
                    if hasConsistentColumnAlignment(tableRows) {
                        let textRows = tableRows.map { row in
                            row.compactMap { $0.topCandidates(1).first?.string }
                        }

                        // Calculate bounding box
                        let allObs = tableRows.flatMap { $0 }
                        let minX = allObs.map { $0.boundingBox.minX }.min() ?? 0
                        let maxX = allObs.map { $0.boundingBox.maxX }.max() ?? 1
                        let minY = allObs.map { $0.boundingBox.minY }.min() ?? 0
                        let maxY = allObs.map { $0.boundingBox.maxY }.max() ?? 1

                        tables.append(DetectedTable(
                            rows: textRows,
                            boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                            confidence: Float(tableRows.count) / Float(max(1, rows.count))
                        ))

                        // Mark these observations as table content
                        for row in tableRows {
                            for obs in row {
                                tableObservations.insert(obs.uuid)
                            }
                        }

                        Log.debug("[DocumentProcessor] Detected table: \(tableRows.count) rows × \(columnCount) columns", category: .ingestion)
                    }
                }

                i = j
            } else {
                i += 1
            }
        }

        // Return non-table observations
        let remaining = observations.filter { !tableObservations.contains($0.uuid) }

        return (tables, remaining)
    }

    /// Check if rows have consistent column X-alignment (suggesting table structure)
    private func hasConsistentColumnAlignment(_ rows: [[VNRecognizedTextObservation]]) -> Bool {
        guard rows.count >= 2 else { return false }

        // Get X positions of first row as reference
        let referenceXs = rows[0].map { $0.boundingBox.midX }
        let alignmentThreshold: CGFloat = 0.05 // 5% tolerance

        for row in rows.dropFirst() {
            let rowXs = row.map { $0.boundingBox.midX }

            // Check if this row's X positions roughly align with reference
            var alignedCount = 0
            for x in rowXs {
                for refX in referenceXs {
                    if abs(x - refX) < alignmentThreshold {
                        alignedCount += 1
                        break
                    }
                }
            }

            // Require at least 50% of columns to align
            if alignedCount < row.count / 2 {
                return false
            }
        }

        return true
    }

    /// Extract text from code files - preserve syntax and structure
    private func extractTextFromCode(url: URL) throws -> String {
        // Try UTF-8 first (standard for code)
        if let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }

        // Fallback to other encodings
        if let data = try? Data(contentsOf: url),
           let code = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii) {
            return code
        }

        throw DocumentProcessingError.unsupportedEncoding
    }

    /// Extract text from CSV - convert to structured readable format
    private func extractTextFromCSV(url: URL) throws -> String {
        let csvContent = try String(contentsOf: url, encoding: .utf8)
        let lines = csvContent.components(separatedBy: .newlines)

        guard !lines.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        // Parse CSV and convert to readable format
        var structuredText = ""

        // Detect delimiter (comma or tab)
        let delimiter = lines.first?.contains("\t") == true ? "\t" : ","

        // Process header
        if let header = lines.first {
            let headers = header.components(separatedBy: delimiter)
            structuredText += "Table with columns: " + headers.joined(separator: ", ") + "\n\n"
        }

        // Process rows (limit to reasonable size for context)
        let rowsToProcess = min(lines.count - 1, 1000)
        for i in 1..<rowsToProcess {
            let row = lines[i]
            if !row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let values = row.components(separatedBy: delimiter)
                structuredText += "Row \(i): " + values.joined(separator: " | ") + "\n"
            }
        }

        if lines.count > 1001 {
            structuredText += "\n(Note: CSV contains \(lines.count) total rows, showing first 1000 for efficiency)\n"
        }

        return structuredText
    }

    // MARK: - Audio/Video Transcription

    /// Extract text from audio/video files using Speech.framework
    private func extractTextFromAudioVideo(url: URL) async throws -> String {
        let transcriptionService = AudioTranscriptionService.shared

        // Check authorization first
        let authorized = await transcriptionService.checkAuthorization()
        if !authorized {
            Log.warning("[DocumentProcessor] Speech recognition not authorized; requesting permission", category: .ingestion)
            try await transcriptionService.requestAuthorization()
        }

        // Detect language from filename or default to English
        let filename = url.lastPathComponent.lowercased()
        var language: NLLanguage = .english

        // Simple language hints from filename
        if filename.contains("_es") || filename.contains("spanish") {
            language = .spanish
        } else if filename.contains("_fr") || filename.contains("french") {
            language = .french
        } else if filename.contains("_de") || filename.contains("german") {
            language = .german
        } else if filename.contains("_zh") || filename.contains("chinese") {
            language = .simplifiedChinese
        } else if filename.contains("_ja") || filename.contains("japanese") {
            language = .japanese
        }

        progressHandler?("transcribing audio")

        do {
            let result = try await transcriptionService.transcribe(url: url, language: language)

            if result.isSuccessful {
                Log.info("[DocumentProcessor] Transcribed \(result.wordCount) words from \(url.lastPathComponent)", category: .ingestion)
                return transcriptionService.transcriptionToDocument(result, sourceFile: url.lastPathComponent)
            } else {
                throw DocumentProcessingError.audioTranscriptionEmpty
            }
        } catch let error as TranscriptionError {
            Log.error("[DocumentProcessor] Transcription failed: \(error.localizedDescription)", category: .ingestion)
            throw DocumentProcessingError.audioTranscriptionFailed(error.localizedDescription)
        }
    }

    /// Extract text from Office documents (Word, Excel, PowerPoint, iWork)
    private func extractTextFromOfficeDocument(url: URL, type: DocumentType) async throws -> String {
        // For iWork documents (.pages, .numbers, .keynote), they're actually ZIP packages
        if type == .pages || type == .numbers || type == .keynote {
            return try extractTextFromIWorkDocument(url: url)
        }

        // For Microsoft Office formats, attempt extraction
        // .docx, .xlsx, .pptx are also ZIP packages with XML
        if type == .word || type == .excel || type == .powerpoint {
            return try extractTextFromOfficeXML(url: url, type: type)
        }

        // Legacy .doc, .xls, .ppt - limited support
        Log.warning("[DocumentProcessor] Legacy Office format detected", category: .ingestion)
        Log.info("[DocumentProcessor] Suggestion: Convert to .docx, .xlsx, or .pptx for better support", category: .ingestion)
        throw DocumentProcessingError.legacyOfficeFormat
    }

    /// Extract text from iWork documents (Pages, Numbers, Keynote)
    private func extractTextFromIWorkDocument(url: URL) throws -> String {
        // iWork documents are packages - look for index.xml or similar
        // This is a simplified implementation
        Log.warning("[DocumentProcessor] iWork document support is limited", category: .ingestion)
        Log.info("[DocumentProcessor] Suggestion: Export as PDF or text for full compatibility", category: .ingestion)

        // Try to read as a package
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Look for text content in the package
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                if file.pathExtension == "xml" || file.pathExtension == "txt" {
                    if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                        // Basic XML stripping for text extraction
                        let text = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return text
                        }
                    }
                }
            }
        }

        throw DocumentProcessingError.iWorkExtractionFailed
    }

    /// Extract text from modern Office XML formats
    private func extractTextFromOfficeXML(url: URL, type: DocumentType) throws -> String {
        // Modern Office formats (.docx, .xlsx, .pptx) are ZIP files
        // They contain XML files with the actual content

        Log.warning("[DocumentProcessor] Modern Office format detected", category: .ingestion)
        Log.info("[DocumentProcessor] Suggestion: For best results, export as PDF before importing", category: .ingestion)

        // This would require ZIP extraction and XML parsing
        // For now, suggest conversion
        throw DocumentProcessingError.officeFormatNeedsConversion
    }

    // MARK: - Chunking Strategy

    /// Intelligent text chunking strategy using semantic boundaries
    /// Splits on paragraphs first, then sentences, maintaining context overlap
    private func chunkText(_ text: String) -> [String] {
        var chunks: [String] = []

        // First, split by paragraphs (semantic boundaries)
        let paragraphs = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var currentChunk = ""
        var wordCount = 0

        for paragraph in paragraphs {
            let paragraphWords = paragraph.split(separator: " ")
            let paragraphWordCount = paragraphWords.count

            // If adding this paragraph exceeds target size, finalize current chunk
            if wordCount + paragraphWordCount > targetChunkSize && wordCount > 0 {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))

                // Implement overlap by keeping last N words
                let overlapWords = currentChunk.split(separator: " ").suffix(chunkOverlap)
                currentChunk = overlapWords.joined(separator: " ") + " "
                wordCount = overlapWords.count
            }

            currentChunk += paragraph + "\n\n"
            wordCount += paragraphWordCount
        }

        // Add final chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks
    }

    // MARK: - Utilities

    private func detectDocumentType(url: URL) -> DocumentType {
        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        // Documents
        case "pdf":
            return .pdf
        case "txt":
            return .text
        case "md", "markdown", "mdown":
            return .markdown
        case "rtf":
            return .rtf

        // Images (OCR support)
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "heic", "heif":
            return .heic
        case "tiff", "tif":
            return .tiff
        case "gif":
            return .gif
        case "bmp", "webp":
            return .image

        // Code files
        case "swift":
            return .swift
        case "py", "pyw", "pyx":
            return .python
        case "js", "mjs", "cjs":
            return .javascript
        case "ts", "tsx":
            return .typescript
        case "java", "class":
            return .java
        case "cpp", "cc", "cxx", "c++":
            return .cpp
        case "c", "h":
            return .c
        case "m", "mm":
            return .objc
        case "go":
            return .go
        case "rs":
            return .rust
        case "rb":
            return .ruby
        case "php":
            return .php
        case "html", "htm":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        case "json", "jsonc":
            return .json
        case "xml":
            return .xml
        case "yaml", "yml":
            return .yaml
        case "sql":
            return .sql
        case "sh", "bash", "zsh", "fish":
            return .shell
        case "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim":
            return .code

        // Office documents
        case "doc", "docx":
            return .word
        case "xls", "xlsx":
            return .excel
        case "ppt", "pptx":
            return .powerpoint
        case "pages":
            return .pages
        case "numbers":
            return .numbers
        case "key":
            return .keynote

        // Data formats
        case "csv":
            return .csv

        // Audio formats (Speech transcription)
        case "m4a", "aac":
            return .m4a
        case "mp3":
            return .mp3
        case "wav", "wave", "aiff", "aif", "caf":
            return .wav

        // Video formats (Speech transcription)
        case "mp4", "m4v":
            return .mp4
        case "mov":
            return .mov
        case "avi", "mkv", "webm":
            return .video

        default:
            // Try to detect by content type as fallback
            if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let contentType = resourceValues.contentType {

                if contentType.conforms(to: .image) {
                    return .image
                } else if contentType.conforms(to: .audio) {
                    return .audio
                } else if contentType.conforms(to: .audiovisualContent) {
                    return .video
                } else if contentType.conforms(to: .plainText) || contentType.conforms(to: .sourceCode) {
                    return .code
                }
            }

            return .unknown
        }
    }
}

// MARK: - Errors

enum DocumentProcessingError: LocalizedError {
    case unsupportedFormat
    case pdfLoadFailed
    case emptyDocument
    case imageOnlyPDF
    case rtfParseFailed
    case fileNotFound
    case unsupportedEncoding
    case corruptedFile
    case imageLoadFailed
    case ocrFailed
    case legacyOfficeFormat
    case officeFormatNeedsConversion
    case iWorkExtractionFailed
    case audioTranscriptionFailed(String)
    case audioTranscriptionEmpty

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported document format"
        case .pdfLoadFailed:
            return "Failed to load PDF document"
        case .emptyDocument:
            return "Document contains no text"
        case .imageOnlyPDF:
            return "PDF contains only images (no extractable text). OCR attempted but no text found. Try a higher quality scan or text-based PDF."
        case .rtfParseFailed:
            return "Failed to parse RTF document"
        case .fileNotFound:
            return "File not found at specified location"
        case .unsupportedEncoding:
            return "Document encoding not supported"
        case .corruptedFile:
            return "File appears to be corrupted"
        case .imageLoadFailed:
            return "Failed to load image file"
        case .ocrFailed:
            return "OCR text recognition failed"
        case .legacyOfficeFormat:
            return "Legacy Office format detected. Please convert to .docx, .xlsx, or .pptx for better support, or export as PDF."
        case .officeFormatNeedsConversion:
            return "Office document detected. For best results, export as PDF before importing."
        case .iWorkExtractionFailed:
            return "iWork document support is limited. Please export as PDF or text for full compatibility."
        case let .audioTranscriptionFailed(reason):
            return "Audio transcription failed: \(reason)"
        case .audioTranscriptionEmpty:
            return "Audio transcription produced no text. The audio may be silent or incompatible."
        }
    }
}
