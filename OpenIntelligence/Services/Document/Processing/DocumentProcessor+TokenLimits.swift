//
//  DocumentProcessor+TokenLimits.swift
//  OpenIntelligence
//
//  Part of DocumentProcessor, moved from DocumentProcessor.swift on 2026-11-05 (5.8 split); only access keywords changed.
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
    // MARK: - Token Limit Enforcement (Critical Safety Net)

    /// Maximum embedding tokens per chunk (512 model limit - 2 for CLS/SEP)
    private static let maxEmbeddableTokens = 510

    /// Contextual prefix adds ~50-80 tokens during embedding
    private static let contextualPrefixTokens = 80

    /// Safe token limit for chunks (before contextual prefix is added)
    static let safeTokenLimit = maxEmbeddableTokens - contextualPrefixTokens  // 430 tokens

    /// Legacy word-based limit (kept for fallback split function)
    /// ~200 words should be safe even for high-tokenization content (200 * 2 = 400 tokens)
    private static let maxEmbeddableWords = 200

    /// Count ACTUAL embedding tokens using Tokenizer
    /// CRITICAL: NLTokenizer "word count" does NOT match BPE/WordPiece tokens!
    /// Example: "VHA21\VHAPALGarciG1" = 1 NL word but 10+ embedding tokens
    /// Tables with abbreviations/codes can be 2-3x higher than word-based estimates
    func countTokens(_ text: String) -> Int {
        if let tokenizer = embeddingTokenizer {
            do {
                let ids = try tokenizer.encode(text: text, addSpecialTokens: true)
                return ids.count
            } catch {
                return text.count / 3 + 2
            }
        } else {
            // Fallback: conservative 3 chars/token for technical content
            return text.count / 3 + 2
        }
    }

    /// Count words using NLTokenizer (for logging/stats only, NOT for limit enforcement)
    func countWords(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    /// Post-processing validation that ensures NO chunk exceeds embedding token limit
    /// Uses ACTUAL BertTokenizer counting, not word estimation
    /// This is critical for technical content with abbreviations, codes, special chars
    ///
    /// Each chunk is counted once. Until 2026-10-09 it was counted three times (the check, a
    /// second pass to verify, a third for the log's maximum), in one stretch on the main actor.
    /// The loop lets the main actor go every `tokenizerCallsBetweenYields` chunks.
    func enforceTokenLimitOnChunks(_ chunks: [ProcessedChunk]) async -> [ProcessedChunk] {
        var validatedChunks: [ProcessedChunk] = []
        validatedChunks.reserveCapacity(chunks.count)
        var splitCount = 0
        var maxTokenCount = 0
        var stillTooLarge: [(chunk: ProcessedChunk, tokens: Int)] = []

        for (offset, chunk) in chunks.enumerated() {
            if offset > 0, offset % Self.tokenizerCallsBetweenYields == 0 { await Task.yield() }
            let tokenCount = countTokens(chunk.text)

            if tokenCount > Self.safeTokenLimit {
                // This chunk WILL cause token truncation - must split it
                let splitChunks = splitOversizedChunkByTokens(chunk)
                validatedChunks.append(contentsOf: splitChunks)
                splitCount += 1

                Log.warning(
                    "[DocumentProcessor] ⚠️ SPLIT OVERSIZED CHUNK: \(tokenCount)t/\(countWords(chunk.text))w → \(splitChunks.count) sub-chunks "
                    + "(section: \(chunk.metadata.sectionTitle ?? "none"), type: \(chunk.metadata.structureType ?? "paragraph"))",
                    category: .ingestion
                )

                // VERIFICATION: no part should exceed the limit now
                for part in splitChunks {
                    let partTokens = countTokens(part.text)
                    maxTokenCount = max(maxTokenCount, partTokens)
                    if partTokens > Self.safeTokenLimit { stillTooLarge.append((part, partTokens)) }
                }
            } else {
                validatedChunks.append(chunk)
                maxTokenCount = max(maxTokenCount, tokenCount)
            }
        }

        if splitCount > 0 {
            Log.info(
                "[DocumentProcessor] Token limit enforcement: split \(splitCount) oversized chunks → " +
                "\(chunks.count) → \(validatedChunks.count) total",
                category: .ingestion
            )
        }

        if !stillTooLarge.isEmpty {
            Log.error(
                "[DocumentProcessor] ❌ CRITICAL: \(stillTooLarge.count) chunks STILL exceed token limit after split!",
                category: .ingestion
            )
            // Log details of problematic chunks for debugging
            for (idx, entry) in stillTooLarge.prefix(3).enumerated() {
                Log.error(
                    "[DocumentProcessor] Oversized chunk \(idx+1): \(entry.tokens)t, preview: \(String(entry.chunk.text.prefix(100)))...",
                    category: .ingestion)
            }
        }

        // Always log enforcement stats for visibility
        Log.debug(
            "[DocumentProcessor] Token limit enforcement complete: \(chunks.count)→\(validatedChunks.count) chunks, " +
            "split=\(splitCount), maxTokens=\(maxTokenCount)/\(Self.safeTokenLimit)",
            category: .ingestion
        )

        return validatedChunks
    }

    /// Split a single oversized chunk into multiple smaller chunks that fit within token limits
    /// Preserves metadata and adds part markers for context
    private func splitOversizedChunk(_ chunk: ProcessedChunk) -> [ProcessedChunk] {
        var subChunks: [ProcessedChunk] = []
        let text = chunk.text
        let maxWords = Self.maxEmbeddableWords

        // Try to split on sentence boundaries for coherence
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).filter { !$0.isEmpty }

        var currentText = ""
        var currentWordCount = 0
        var partNumber = 0

        for sentence in sentences {
            let sentenceWords = countWords(sentence)

            // If adding this sentence would exceed limit, flush current buffer
            if currentWordCount + sentenceWords > maxWords && !currentText.isEmpty {
                partNumber += 1
                let partText = "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                currentText = ""
                currentWordCount = 0
            }

            // Handle case where a single sentence is too large (rare but possible)
            if sentenceWords > maxWords {
                // Force-split at word boundaries
                let words = sentence.split(separator: " ")
                for wordSlice in stride(from: 0, to: words.count, by: maxWords) {
                    let end = min(wordSlice + maxWords, words.count)
                    partNumber += 1
                    let partWords = words[wordSlice..<end].joined(separator: " ")
                    let partText = "[Part \(partNumber)]\n" + partWords
                    subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
                }
            } else {
                currentText += sentence + ". "
                currentWordCount += sentenceWords
            }
        }

        // Flush remaining content
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            partNumber += 1
            let partText = partNumber > 1
                ? "[Part \(partNumber)]\n" + currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                : currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            subChunks.append(createSubChunk(from: chunk, text: partText, index: partNumber - 1))
        }

        // Edge case: if no sub-chunks were created, return original (shouldn't happen)
        if subChunks.isEmpty {
            Log.warning("[DocumentProcessor] Split produced no sub-chunks, returning original", category: .ingestion)
            return [chunk]
        }

        return subChunks
    }

    /// Split a chunk using ACTUAL token counting (not word estimation)
    /// This is critical for technical content with abbreviations, codes, special chars
    private func splitOversizedChunkByTokens(_ chunk: ProcessedChunk) -> [ProcessedChunk] {
        let maxTokens = Self.safeTokenLimit - 10  // Leave margin for part markers

        // The parts are runs of the chunk's own text. Through 5.6 this split at every ".", "!", "?"
        // and line break and joined the pieces with ". ", which stored "$75. 50" for "$75.50".
        let parts = OversizedChunkSplitter.parts(of: chunk.text, maxTokens: maxTokens, countTokens: countTokens)
        guard parts.count > 1 else {
            Log.warning("[DocumentProcessor] Token-based split produced no sub-chunks, returning original", category: .ingestion)
            return [chunk]
        }

        let subChunks = parts.enumerated().map { index, part in
            createSubChunk(from: chunk, text: "[Part \(index + 1)]\n" + part, index: index)
        }

        // Final validation: ensure all sub-chunks are within limit
        let stillOversized = subChunks.filter { countTokens($0.text) > Self.safeTokenLimit }
        if !stillOversized.isEmpty {
            Log.warning("[DocumentProcessor] \(stillOversized.count) sub-chunks still oversized after token split, will be truncated at embedding time", category: .ingestion)
        }

        return subChunks
    }

    /// Create a sub-chunk with inherited metadata from parent
    private func createSubChunk(from parent: ProcessedChunk, text: String, index: Int) -> ProcessedChunk {
        let wordCount = countWords(text)  // Use NLTokenizer for accuracy
        let metadata = ChunkMetadata(
            chunkIndex: parent.metadata.chunkIndex + index,
            startPosition: parent.metadata.startPosition,
            endPosition: parent.metadata.endPosition,
            pageNumber: parent.metadata.pageNumber,
            sectionTitle: parent.metadata.sectionTitle,
            keywords: parent.metadata.keywords,
            semanticDensity: parent.metadata.semanticDensity,
            hasNumericData: parent.metadata.hasNumericData,
            hasListStructure: parent.metadata.hasListStructure,
            wordCount: wordCount,
            characterCount: text.count,
            structureType: parent.metadata.structureType,
            siblingGroupId: parent.metadata.siblingGroupId,
            siblingCount: parent.metadata.siblingCount,
            entities: parent.metadata.entities,
            abbreviations: parent.metadata.abbreviations,
            abstractionLevel: parent.metadata.abstractionLevel,
            sectionPath: parent.metadata.sectionPath,
            bboxArray: parent.metadata.bboxArray,
            documentCategory: parent.metadata.documentCategory,
            chunkType: parent.metadata.chunkType,
            tableTitle: parent.metadata.tableTitle,
            imageContentType: parent.metadata.imageContentType,
            imageCaption: parent.metadata.imageCaption,
            imageDescription: parent.metadata.imageDescription,
            imageExtractedText: parent.metadata.imageExtractedText,
            imageClassifications: parent.metadata.imageClassifications,
            hasCrossReferences: parent.metadata.hasCrossReferences,
            resolvedReferences: parent.metadata.resolvedReferences
        )
        return ProcessedChunk(
            text: text,
            parentText: parent.parentText,
            metadata: metadata,
            structuredTable: index == 0 ? parent.structuredTable : nil
        )
    }

    // MARK: - Content Coverage Verification

    /// Verify that chunking captured all content from the original document
    /// This is a diagnostic check - logs warnings if significant content is missing
    @concurrent
    nonisolated static func verifyContentCoverage(
        original: String,
        chunkTexts: [String],
        documentId: UUID
    ) async {
        // Count words in original (normalize whitespace)
        let originalWords = Set(
            original.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 3 }  // Only count meaningful words
        )

        // Count unique words in all chunks combined
        var chunkWords = Set<String>()
        for text in chunkTexts {
            let words = text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 3 }
            chunkWords.formUnion(words)
        }

        // Calculate coverage
        let covered = originalWords.intersection(chunkWords).count
        let total = originalWords.count
        let coverage = total > 0 ? Double(covered) / Double(total) * 100 : 100

        // Volume, as opposed to vocabulary. Whitespace is excluded from both sides so reflow and
        // re-indentation cannot move the number.
        let originalChars = original.filter { !$0.isWhitespace }.count
        let chunkChars = chunkTexts.reduce(0) { $0 + $1.filter { !$0.isWhitespace }.count }
        // Account for overlap - chunks may duplicate some content
        let charRatio = originalChars > 0 ? Double(chunkChars) / Double(originalChars) * 100 : 100

        // WHY `charRatio` IS CHECKED AND NOT ONLY LOGGED
        //
        // `coverage` above is a set intersection of unique words, and unique vocabulary saturates
        // long before content does. Truncate the back half of a real document and almost every
        // distinct three-letter-or-longer word still appears in the front half, so word coverage
        // stays above 90 and this function stays silent while half the document is gone. Volume is
        // the metric that moves in that case, and until 2026-08-28 it was computed here, formatted
        // into the healthy-path debug line, and compared against nothing at all.
        //
        // Two bounds, because both directions are real failures seen in this project:
        //   - Below 90%: text was dropped between extraction and the finished chunks.
        //   - Above 200%: chunks are duplicating content far beyond what overlap explains. Legitimate
        //     overlap runs roughly 115–125% at the configured word overlap, so 200 leaves wide margin
        //     and still catches the duplicate-import shape that put five files in the library for
        //     three samples.
        let coverageIsLow = coverage < 90
        let volumeIsLow = charRatio < 90
        let volumeIsImplausible = charRatio > 200

        guard coverageIsLow || volumeIsLow || volumeIsImplausible else {
            Log.debug(
                "[DocumentProcessor] ✅ Content coverage: \(String(format: "%.1f", coverage))% words, " +
                "\(String(format: "%.0f", charRatio))% chars (includes overlap)",
                category: .ingestion
            )
            return
        }

        // Both numbers on every warning, whichever bound tripped. A warning that reports only the
        // metric that failed makes the other one unavailable at exactly the moment it is diagnostic:
        // high word coverage beside low volume is the truncation signature specifically, and is a
        // different fault from both being low.
        let readings = "\(String(format: "%.1f", coverage))% of unique words (\(covered)/\(total)), " +
            "\(String(format: "%.0f", charRatio))% of characters"

        if volumeIsLow {
            Log.warning(
                "[DocumentProcessor] ⚠️ CONTENT VOLUME LOST: \(readings). " +
                "Chunks hold \(chunkChars) non-whitespace characters against \(originalChars) extracted. " +
                "High word coverage beside low volume means the document was truncated rather than filtered.",
                category: .ingestion
            )
        }
        if volumeIsImplausible {
            Log.warning(
                "[DocumentProcessor] ⚠️ CONTENT DUPLICATED: \(readings). " +
                "Chunks hold \(chunkChars) non-whitespace characters against \(originalChars) extracted, " +
                "which overlap alone does not explain.",
                category: .ingestion
            )
        }
        if coverageIsLow {
            let missing = originalWords.subtracting(chunkWords)
            let sampleMissing = Array(missing.prefix(10)).joined(separator: ", ")
            Log.warning(
                "[DocumentProcessor] ⚠️ LOW CONTENT COVERAGE: \(readings). " +
                "Missing samples: \(sampleMissing)...",
                category: .ingestion
            )
        }
    }

    /// Extract keywords from structured elements using NLTagger (domain-agnostic)
    /// Leverages Apple's NLP for nouns, technical terms, and alphanumeric patterns
    func extractKeywordsFromStructuredElement(_ text: String, type: String) -> [String] {
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

        // Deduplicate in order of first appearance and keep the first 20 (5.8). `Array(Set(...)).prefix(20)` kept a
        // different 20 of a table passage's keywords on every import, because a Set's order is seeded per process.
        var seen = Set<String>()
        return Array(keywords.filter { seen.insert($0).inserted }.prefix(20))
    }

    /// Extract text from PDF using PDFKit (native iOS framework) - Legacy method
    /// Now with OCR fallback for image-only pages
    private func extractTextFromPDF(url: URL) async throws -> String {
        let pdfDocument = try loadPDF(url: url, context: "PDF")

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
            let trimmedText = pageText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = trimmedText.map { !$0.isEmpty } ?? false
            let textQualityOK = hasText && isTextQualityAcceptable(pageText ?? "")

            if hasText && textQualityOK {
                progressHandler?("page \(pageIndex + 1)/\(pageCount)")
                await Task.yield()

                fullText += (pageText ?? "") + "\n\n"

                let pageTime = Date().timeIntervalSince(pageStartTime)
                Log.debug("   ✓ Page \(pageIndex + 1): \(pageText?.count ?? 0) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
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
                    fullText += (pageText ?? "") + "\n\n"
                    Log.warning("   ⚠️ Page \(pageIndex + 1): Using original text despite quality concerns", category: .ingestion)
                }
            } else {
                // No extractable text - try OCR on the page image
                pagesWithoutText += 1

                // Update progress for OCR
                progressHandler?("page \(pageIndex + 1)/\(pageCount), OCR")
                await Task.yield()

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
    /// Uses 5x scale (360 DPI) for maximum Vision OCR accuracy
    /// Higher DPI captures fine text, small labels, and low-quality scans better
    /// Apple's Vision framework works best at 150-300+ DPI
    /// GPU-accelerated when DeviceCapabilityService.useGPUForPDFRendering is enabled
    ///
    /// ROTATION HANDLING: PDF pages can have /Rotate flags (90°, 180°, 270°).
    /// We use .cropBox which returns dimensions in the page's display orientation,
    /// and PDFPage.draw() automatically applies the rotation transform.
    func renderPDFPageAsImage(page: PDFPage, scale: CGFloat = 5.0) -> CIImage? {
        // Use .cropBox instead of .mediaBox — cropBox respects the page's /Rotate flag
        // and returns dimensions in the correct display orientation.
        // For a portrait page rotated 90° to landscape, cropBox gives landscape dimensions.
        let pageBounds = page.bounds(for: .cropBox)

        // Scale up for maximum OCR accuracy - Vision needs high DPI images
        // PDF pages are typically 72 DPI, so 5x = 360 DPI (maximum quality for text recognition)
        // This captures fine print, subscripts, small labels that 216 DPI misses
        let scaledSize = CGSize(
            width: pageBounds.size.width * scale,
            height: pageBounds.size.height * scale
        )

        let pageRotation = page.rotation
        if pageRotation != 0 {
            Log.info("[DocumentProcessor] PDF page has rotation=\(pageRotation)° — using cropBox for correct orientation", category: .ingestion)
        }

        // Per-page render timing. This measurement was missing when a 210-page PDF took five
        // hours on a Mac: the logs gave no way to separate render cost from OCR cost. Pair it
        // with the "Page N: OCR extracted ..." timing the caller already emits to split them.
        let renderStart = CFAbsoluteTimeGetCurrent()

        // The raster is CPU work on BOTH platforms. `useGPUForPDFRendering` selects only the
        // Core Image preprocessing chain attached afterwards, and CIImage is lazy, so no GPU
        // work has actually run by the time this function returns. The old log line claimed
        // "[GPU-accelerated]" at this point, which pointed a real investigation away from the
        // true bottleneck.
        let attachesOCRPostProcess = DeviceCapabilityService.shared.useGPUForPDFRendering

        func logRender(_ backend: String) {
            let ms = (CFAbsoluteTimeGetCurrent() - renderStart) * 1000
            let suffix = attachesOCRPostProcess ? ", post-process attached" : ""
            Log.debug(
                "[DocumentProcessor] Rendered PDF page at \(Int(scaledSize.width))×\(Int(scaledSize.height))px (\(Int(72 * scale)) DPI) in \(String(format: "%.1f", ms))ms via \(backend), CPU raster\(suffix)",
                category: .ingestion
            )
        }

        #if canImport(UIKit)
        // Use opaque format to avoid alpha channel overhead
        // This prevents the "AlphaPremulLast" warning and halves memory usage
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true  // No alpha channel needed - we draw on white background
        format.scale = 1.0    // We've already scaled the size

        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        let uiImage = renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: scaledSize))

            let ctx = context.cgContext
            ctx.saveGState()

            // Scale up the PDF rendering
            ctx.scaleBy(x: scale, y: scale)

            // Flip Y-axis: UIKit has origin at top-left, PDF at bottom-left
            ctx.translateBy(x: 0, y: pageBounds.size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)

            // PDFPage.draw(with:to:) handles /Rotate internally when using .cropBox
            page.draw(with: .cropBox, to: ctx)

            ctx.restoreGState()
        }

        logRender("UIGraphicsImageRenderer")

        if attachesOCRPostProcess {
            guard let ciImage = CIImage(image: uiImage) else { return nil }

            // Report GPU activity to HUD
            Task { @MainActor in
                HardwareTelemetryState.shared.reportGPUCompute(operation: .imageProcessing)
            }

            // Apply GPU-accelerated preprocessing for better OCR
            return preprocessImageForOCR(ciImage)
        } else {
            return CIImage(image: uiImage)
        }
        #elseif canImport(AppKit)
        // Draw straight into a bitmap we own, at exactly the pixel size we asked for.
        //
        // This replaces NSImage.lockFocus() + tiffRepresentation + NSBitmapImageRep(data:).
        // AppKit/NSImage.h deprecates lockFocus with the reason "This method is incompatible
        // with resolution-independent drawing": it sizes its backing store from the display's
        // scale factor, so on a Retina display it silently allocated 4x the pixels requested.
        // tiffRepresentation then encoded that whole raster to uncompressed TIFF in memory and
        // NSBitmapImageRep(data:) decoded it straight back — a full CPU serialize/deserialize
        // round-trip, per page. At scale 5 a US Letter page is 3060×3960px; under lockFocus at
        // 2x backing scale it was 6120×7920, roughly 194MB, round-tripped 210 times for the
        // document that took five hours.
        //
        // A CGBitmapContext has the same bottom-left origin as the lockFocus context it
        // replaces, so the transform below is unchanged and page orientation is preserved. It
        // also avoids touching NSGraphicsContext.current, which lockFocus mutates and which is
        // process-global state shared with every concurrent Vision operation.
        let pixelWidth = Int(scaledSize.width.rounded())
        let pixelHeight = Int(scaledSize.height.rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let bitmapContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // let CoreGraphics choose an aligned stride
            space: CGColorSpaceCreateDeviceRGB(),
            // Opaque, matching format.opaque = true on the UIKit side. We draw on white.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            Log.warning("[DocumentProcessor] Could not create \(pixelWidth)×\(pixelHeight) bitmap context for PDF page render", category: .ingestion)
            return nil
        }

        bitmapContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        bitmapContext.saveGState()
        bitmapContext.scaleBy(x: scale, y: scale)
        // PDFPage.draw(with:to:) handles /Rotate internally when using .cropBox
        page.draw(with: .cropBox, to: bitmapContext)
        bitmapContext.restoreGState()

        guard let cgImage = bitmapContext.makeImage() else {
            Log.warning("[DocumentProcessor] Bitmap context produced no image for PDF page render", category: .ingestion)
            return nil
        }

        logRender("CGBitmapContext")

        let ciImage = CIImage(cgImage: cgImage)
        if attachesOCRPostProcess {
            // The same report as the UIKit branch (5.8): the Mac's hardware HUD showed nothing for the post-process,
            // which runs through the Metal-backed CIContext as it does on iPhone (row "PDF page renders are logged as
            // GPU-accelerated on a macOS path").
            Task { @MainActor in
                HardwareTelemetryState.shared.reportGPUCompute(operation: .imageProcessing)
            }
            return preprocessImageForOCR(ciImage)
        } else {
            return ciImage
        }
        #else
        return nil
        #endif
    }

}
