//
//  DocumentProcessor+PDFText.swift
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
    // MARK: - Text Quality Validation

    /// Check if extracted text is likely garbage (bad OCR layer, encoding issues, etc.)
    /// Returns true if text quality is acceptable, false if OCR should be used instead
    ///
    /// This function is CRITICAL for bulletproof PDF ingestion. PDFs often have
    /// invisible/garbage text layers that PDFKit returns, but the visual content
    /// Checks if extracted text appears to be legitimate human-readable content
    /// vs. garbled/corrupt PDF text layer garbage.
    ///
    /// LANGUAGE-AGNOSTIC: Works for English, CJK, Arabic, Cyrillic, and mixed scripts.
    /// Uses NaturalLanguage framework for script detection instead of English-specific heuristics.
    /// is completely different. We must detect this and fall back to OCR.
    func isTextQualityAcceptable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            Log.debug("[DocumentProcessor] Text too short to assess quality (\(trimmed.count) chars)", category: .ingestion)
            return false
        }

        // === CHECK 1: Printable character ratio ===
        // Garbage text often has control characters, private use area, etc.
        // This works for ALL scripts — letters, digits, punctuation, CJK, Arabic, etc.
        let printableCount = trimmed.unicodeScalars.filter { scalar in
            // Accept: letters (any script), numbers, punctuation, symbols, spaces
            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .spaceSeparator, .lineSeparator, .paragraphSeparator,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .nonspacingMark, .spacingMark, .enclosingMark:
                return true
            default:
                return false
            }
        }.count
        let printableRatio = Double(printableCount) / Double(trimmed.unicodeScalars.count)
        if printableRatio < 0.60 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Low printable ratio: \(String(format: "%.1f", printableRatio * 100))% (need 60%+)", category: .ingestion)
            return false
        }

        // === CHECK 2: Word length distribution (language-agnostic) ===
        // Garbage text often has very long "words" (no spaces in random bytes)
        // CJK is fine — even single chars are separated by whitespace in PDFKit output
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3 else {
            Log.debug("[DocumentProcessor] ❌ FAIL: Too few words to assess (\(words.count))", category: .ingestion)
            return false
        }

        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        if avgWordLength < 1.0 || avgWordLength > 25.0 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Abnormal avg word length: \(String(format: "%.1f", avgWordLength))", category: .ingestion)
            return false
        }

        // === CHECK 3: Gibberish detector (consecutive non-printable sequences) ===
        // Look for runs of 4+ characters that aren't letters, digits, or common punctuation
        let controlChars = trimmed.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory == .control ||
            scalar.properties.generalCategory == .privateUse ||
            scalar.properties.generalCategory == .surrogate ||
            scalar.properties.generalCategory == .unassigned
        }.count
        let controlRatio = Double(controlChars) / Double(max(1, trimmed.unicodeScalars.count))
        if controlRatio > 0.05 {
            Log.debug("[DocumentProcessor] ❌ FAIL: High control character ratio: \(String(format: "%.1f", controlRatio * 100))%", category: .ingestion)
            return false
        }

        // === CHECK 4: NaturalLanguage script/language detection ===
        // Use Apple's NLLanguageRecognizer to check if the text is recognizable as ANY language
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let languageHypotheses = recognizer.languageHypotheses(withMaximum: 3)

        // If NL can't identify ANY language with >10% confidence, it's likely garbage
        let bestConfidence = languageHypotheses.values.max() ?? 0
        if bestConfidence < 0.10 && trimmed.count > 50 {
            Log.debug("[DocumentProcessor] ❌ FAIL: NLLanguageRecognizer can't identify language (best conf: \(String(format: "%.1f%%", bestConfidence * 100)))", category: .ingestion)
            return false
        }

        // === CHECK 5: Character entropy (randomness detection) ===
        // Works for all scripts — random bytes have high entropy regardless of language
        let entropy = calculateCharacterEntropy(trimmed)
        if entropy > 6.0 {  // Raised from 5.5 to accommodate CJK (larger alphabet = higher natural entropy)
            Log.debug("[DocumentProcessor] ❌ FAIL: High entropy (random-looking): \(String(format: "%.2f", entropy)) bits/char", category: .ingestion)
            return false
        }

        // === CHECK 6: Repeated character detection ===
        // Garbage often has the same character repeated many times
        let charCounts = Dictionary(trimmed.map { ($0, 1) }, uniquingKeysWith: +)
        let maxCharFreq = Double(charCounts.values.max() ?? 0) / Double(trimmed.count)
        if maxCharFreq > 0.4 && trimmed.count > 30 {
            Log.debug("[DocumentProcessor] ❌ FAIL: Dominant character frequency: \(String(format: "%.1f%%", maxCharFreq * 100))", category: .ingestion)
            return false
        }

        // === Diagnostic logging ===
        let sampleLength = min(100, trimmed.count)
        let sample = String(trimmed.prefix(sampleLength)).replacingOccurrences(of: "\n", with: "↵")
        let detectedLang = languageHypotheses.max(by: { $0.value < $1.value })?.key.rawValue ?? "?"
        Log.debug("[DocumentProcessor] ✓ PASS: Text quality OK (printable=\(String(format: "%.0f", printableRatio * 100))%, entropy=\(String(format: "%.1f", entropy)), lang=\(detectedLang)) Sample: \"\(sample)...\"", category: .ingestion)

        return true
    }

    /// Remove isolated garbage lines from extracted PDF page text before page assembly.
    /// This is intentionally page-scoped so we preserve page mapping and only strip the
    /// obviously bad lines that survive page-level extraction in otherwise readable PDFs.
    func removeGarbageLinesFromExtractedPages(
        _ pageTexts: [String],
        source: String
    ) -> [String] {
        var totalRemoved = 0
        var affectedPages = 0
        var cleanedPages: [String] = []
        cleanedPages.reserveCapacity(pageTexts.count)

        for (index, pageText) in pageTexts.enumerated() {
            guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                cleanedPages.append(pageText)
                continue
            }

            let (cleaned, removedCount) = OCRConfiguration.filterGarbageText(
                pageText,
                revertIfTooAggressive: false
            )
            if removedCount > 0 {
                totalRemoved += removedCount
                affectedPages += 1
                Log.debug(
                    "[DocumentProcessor] Removed \(removedCount) garbage line(s) from page \(index + 1) (\(source))",
                    category: .ingestion
                )
            }
            cleanedPages.append(cleaned)
        }

        if totalRemoved > 0 {
            Log.info(
                "[DocumentProcessor] Garbage filter removed \(totalRemoved) line(s) across \(affectedPages) page(s) (\(source))",
                category: .ingestion
            )
        }

        return cleanedPages
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
    func removeRepeatedHeadersFooters(from pageTexts: [String]) -> [String] {
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
            "^\\(\\d+\\)$",                     // "(5)"
            "^\\d{1,3}\\s+\\d{1,3}$",           // "2 2" (doubled page number from dual columns)
            "^\\d{1,3}\\s*[-—–]\\s*\\d{0,3}$",  // "3 - 5", "2-", "2 — 7" (section-page)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - PDF Loading with Encryption Detection

    /// Load a PDF document with encryption/password detection.
    /// Attempts empty-password unlock for owner-encrypted PDFs.
    /// - Parameters:
    ///   - url: Path to the PDF file
    ///   - context: Calling function name for logging
    /// - Returns: Loaded and unlocked PDFDocument
    /// - Throws: `pdfEncrypted` if password-locked, `pdfLoadFailed` if corrupt/unreadable
    func loadPDF(url: URL, context: String = "PDF") throws -> PDFDocument {
        guard let pdfDocument = PDFDocument(url: url) else {
            Log.error("[DocumentProcessor] \(context) load failed: \(url.lastPathComponent)", category: .ingestion)
            throw DocumentProcessingError.pdfLoadFailed
        }

        if pdfDocument.isEncrypted {
            if pdfDocument.isLocked {
                // Try empty password — many "encrypted" PDFs have no user password
                if !pdfDocument.unlock(withPassword: "") {
                    Log.error("[DocumentProcessor] \(context) is password-protected: \(url.lastPathComponent)", category: .ingestion)
                    throw DocumentProcessingError.pdfEncrypted
                }
                Log.info("[DocumentProcessor] \(context) unlocked with empty password", category: .ingestion)
            } else {
                Log.debug("[DocumentProcessor] \(context) has owner encryption (restrictions only)", category: .ingestion)
            }
        }

        return pdfDocument
    }

    /// Extract text from PDF with page tracking for semantic chunking
    /// Uses spatial-aware extraction to handle multi-column layouts correctly
    /// ADAPTIVE OCR: Pre-scans pages to classify complexity, skips OCR for simple pages
    /// Detect the document's language once and narrow Vision's recognition set accordingly.
    ///
    /// Idempotent: does nothing if a previous stage already detected for this document. That
    /// matters because `extractStructuredPDFContent` calls this before branching, and its pre-26
    /// fallback `extractTextFromPDFWithPages` is also reachable directly from
    /// `extractTextWithPageInfo`.
    ///
    /// Reads the PDFKit text layer of the first 50 pages — the same text already mined for custom
    /// vocabulary — so it adds one language pass and no additional I/O. Hops to the main actor once
    /// per document for `LanguageDetectionService`, which is isolated there.
    func detectDocumentRecognitionLanguagesIfNeeded(pdfDocument: PDFDocument, pageCount: Int) async {
        guard currentDocumentRecognitionLanguages == nil else { return }

        let roughText = (0..<min(pageCount, 50)).compactMap { pdfDocument.page(at: $0)?.string }
            .joined(separator: "\n")
        guard !roughText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.info("[DocumentProcessor] OCR languages NOT narrowed, keeping all \(OCRConfiguration.recognitionLanguages.count) (no text layer to detect from)", category: .ingestion)
            return
        }

        let profile = await MainActor.run { LanguageDetectionService.shared.analyzeDocument(roughText) }
        currentDocumentRecognitionLanguages = OCRConfiguration.narrowedRecognitionLanguages(matching: profile)

        let detected = "\(profile.primaryLanguage.displayName) @ \(String(format: "%.2f", profile.primaryLanguage.confidence))"
        if let narrowed = currentDocumentRecognitionLanguages {
            Log.info("[DocumentProcessor] OCR languages narrowed \(OCRConfiguration.recognitionLanguages.count) -> \(narrowed.count) [\(narrowed.joined(separator: ", "))] (detected \(detected))", category: .ingestion)
        } else {
            // Info, not debug: a silent fallback to the most expensive setting is the failure shape
            // this pipeline keeps rediscovering.
            Log.info("[DocumentProcessor] OCR languages NOT narrowed, keeping all \(OCRConfiguration.recognitionLanguages.count) (detected \(detected))", category: .ingestion)
        }
    }

    func extractTextFromPDFWithPages(url: URL) async throws -> (text: String, pageInfo: PageInfo) {
        let pdfDocument = try loadPDF(url: url, context: "PDF")

        let pageCount = pdfDocument.pageCount
        Log.debug("[DocumentProcessor] PDF pages: \(pageCount)", category: .ingestion)

        // Edge case: Empty PDF
        guard pageCount > 0 else {
            Log.warning("[DocumentProcessor] PDF has zero pages", category: .ingestion)
            throw DocumentProcessingError.emptyDocument
        }

        // ═══════════════════════════════════════════════════════════════════════
        // PHASE -1: DOCUMENT-LEVEL TEXT LAYER VALIDATION
        // ═══════════════════════════════════════════════════════════════════════
        // Many PDFs (Kia, Hyundai, Asian-publisher manuals) use font substitution
        // ciphers: the text layer is a character-shifted encoding that LOOKS like
        // normal text to naive analysis (printable ASCII, normal word lengths,
        // NLLanguageRecognizer detects "Dutch" at 56% confidence) but is completely
        // garbled. The ONLY reliable detection is to OCR a sample page and compare
        // the result to PDFKit's text layer. If they don't match, the entire
        // document's text layer is unusable and ALL pages must go through Vision OCR.
        //
        // This runs ONCE per document (~200-500ms) and prevents the catastrophic
        // failure where 93% of content is silently lost to garbled text acceptance.
        // ═══════════════════════════════════════════════════════════════════════
        let startPageIdx = 0
        let endPageIdx = pageCount - 1
        let documentTextLayerGarbled: Bool
        textLayerValidation: do {
            // Sample 3 spread-out pages to get representative PDFKit text
            let sliceCount = (endPageIdx - startPageIdx) + 1
            let sampleIndices = sliceCount <= 3
                ? Array(startPageIdx...endPageIdx)
                : [startPageIdx, startPageIdx + sliceCount / 3, startPageIdx + 2 * sliceCount / 3]

            var bestSampleText = ""
            var bestSamplePage: PDFPage?

            for idx in sampleIndices {
                guard let page = pdfDocument.page(at: idx) else { continue }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count > bestSampleText.count {
                    bestSampleText = text
                    bestSamplePage = page
                }
            }

            // If no text layer at all, not garbled — just needs OCR (handled by existing flow)
            guard bestSampleText.count >= 50, let samplePage = bestSamplePage else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] Text layer validation: no/minimal text layer, skipping validation", category: .ingestion)
                break textLayerValidation
            }

            // Render the best sample page and run quick OCR
            emitProgress(stage: "validating", detail: "🔍 Validating text layer...", page: nil, totalPages: pageCount)
            guard let sampleImage = renderPDFPageAsImage(page: samplePage) else {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] Text layer validation: failed to render sample page", category: .ingestion)
                break textLayerValidation
            }

            let ocrObservations: [VNRecognizedTextObservation]
            do {
                ocrObservations = try await performOCRWithObservationsAsync(on: sampleImage)
            } catch {
                documentTextLayerGarbled = false
                Log.warning("[DocumentProcessor] Text layer validation: OCR failed on sample page (\(error.localizedDescription)), assuming text layer OK", category: .ingestion)
                break textLayerValidation
            }
            let ocrWords: Set<String> = Set(
                ocrObservations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            let pdfKitWords: Set<String> = Set(
                bestSampleText.lowercased()
                    .split(whereSeparator: { !$0.isLetter })
                    .map { String($0) }
                    .filter { $0.count >= 3 }
            )

            // Jaccard similarity: |intersection| / |union|
            guard !ocrWords.isEmpty && !pdfKitWords.isEmpty else {
                documentTextLayerGarbled = false
                Log.debug("[DocumentProcessor] Text layer validation: insufficient words for comparison (OCR: \(ocrWords.count), PDFKit: \(pdfKitWords.count))", category: .ingestion)
                break textLayerValidation
            }

            let intersection = ocrWords.intersection(pdfKitWords).count
            let union = ocrWords.union(pdfKitWords).count
            let jaccard = Double(intersection) / Double(union)

            Log.info("[DocumentProcessor] Text layer validation: Jaccard similarity = \(String(format: "%.3f", jaccard)) (OCR words: \(ocrWords.count), PDFKit words: \(pdfKitWords.count), shared: \(intersection))", category: .ingestion)

            if jaccard < 0.15 {
                // Text layer does NOT match what's visually on the page
                // This is a font substitution cipher — text layer is USELESS
                documentTextLayerGarbled = true
                Log.warning("[DocumentProcessor] ⚠️ GARBLED TEXT LAYER DETECTED (Jaccard=\(String(format: "%.3f", jaccard))). Font substitution cipher suspected. ALL pages will use Vision OCR.", category: .ingestion)

                // Log sample comparison for debugging
                let ocrSample = Array(ocrWords.prefix(5)).joined(separator: ", ")
                let pdfSample = Array(pdfKitWords.prefix(5)).joined(separator: ", ")
                Log.info("[DocumentProcessor] OCR sample: [\(ocrSample)] vs PDFKit sample: [\(pdfSample)]", category: .ingestion)
            } else {
                // Main Jaccard passed. For marginal scores (0.15–0.45), run a secondary
                // check for AutoCAD SHX / CAD font encoding (Gap 3 fix).
                // SHX fonts score Jaccard 0.20–0.40 because ASCII digits survive, but
                // dimension symbols (±, °, Ø) and special chars are remapped.
                // Numeric tokens (dimensions, part numbers) are format-stable and DON'T
                // survive SHX encoding — "M10" becomes garbage, "25.4" becomes "253".
                var shxGarbled = false
                if jaccard < 0.45 {
                    let numericPattern = #"\b\d+\.?\d*\s*[A-Za-z]{0,4}\b"#
                    if let numericRegex = try? NSRegularExpression(pattern: numericPattern) {
                        let extractNumerics = { (text: String) -> Set<String> in
                            let range = NSRange(text.startIndex..., in: text)
                            return Set(
                                numericRegex.matches(in: text, range: range)
                                    .compactMap { Range($0.range, in: text).map { String(text[$0]).lowercased().trimmingCharacters(in: .whitespaces) } }
                                    .filter { $0.count >= 2 }
                            )
                        }
                        let ocrText = ocrObservations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                        let ocrNumerics = extractNumerics(ocrText)
                        let pdfNumerics = extractNumerics(bestSampleText)
                        // Only fire if there's enough numeric content to be meaningful
                        // (5+ tokens ensures we're looking at a real engineering/CAD document)
                        if pdfNumerics.count >= 5 {
                            let numIntersection = ocrNumerics.intersection(pdfNumerics).count
                            let numUnion = ocrNumerics.union(pdfNumerics).count
                            let numericJaccard = numUnion > 0 ? Double(numIntersection) / Double(numUnion) : 1.0
                            Log.info("[DocumentProcessor] SHX secondary check: \(pdfNumerics.count) PDF numerics, \(ocrNumerics.count) OCR numerics, numeric Jaccard=\(String(format: "%.3f", numericJaccard))", category: .ingestion)
                            if numericJaccard < 0.25 {
                                shxGarbled = true
                                Log.warning("[DocumentProcessor] ⚠️ SHX FONT ENCODING DETECTED (numeric Jaccard=\(String(format: "%.3f", numericJaccard)), text Jaccard=\(String(format: "%.3f", jaccard))). Likely AutoCAD/CAD/SHX PDF. ALL pages → Vision OCR.", category: .ingestion)
                            }
                        }
                    }
                }
                documentTextLayerGarbled = shxGarbled
                if !shxGarbled {
                    Log.debug("[DocumentProcessor] ✓ Text layer validated: matches OCR output (Jaccard=\(String(format: "%.3f", jaccard)))", category: .ingestion)
                }
            }
        }

        // PHASE 0: ADAPTIVE COMPLEXITY PRE-SCAN (~5-10ms per page)
        // Quickly analyze all pages to determine OCR strategy BEFORE rendering images
        // This saves massive time by skipping OCR entirely for simple text pages
        let complexityStartTime = Date()
        var complexityAnalyses: [PageComplexityAnalysis] = []

        // Batch analyze pages (runs concurrently, very fast)
        let pagesToAnalyze: [(PDFPage, Int)] = (startPageIdx...endPageIdx).compactMap { index in
            guard let page = pdfDocument.page(at: index) else { return nil }
            return (page, index + 1)
        }

        complexityAnalyses = await PageComplexityAnalyzer.shared.analyzeBatch(pages: pagesToAnalyze)

        // Log summary and estimate time savings
        let complexityTime = Date().timeIntervalSince(complexityStartTime) * 1000
        PageComplexityAnalyzer.shared.logBatchSummary(complexityAnalyses)
        Log.debug("[DocumentProcessor] Complexity pre-scan: \(String(format: "%.0f", complexityTime))ms for \(pageCount) pages", category: .ingestion)

        // Build lookup map for quick access during processing
        var pageComplexity: [Int: PageComplexityAnalysis] = [:]
        for analysis in complexityAnalyses {
            pageComplexity[analysis.pageNumber] = analysis
        }

        // PHASE 1: Extract text from all pages with ADAPTIVE parallel processing
        // Use device-specific concurrency to maximize hardware utilization
        // OCR runs on Neural Engine (ANE), so concurrency is tuned per device tier
        let maxConcurrentPages = DeviceCapabilityService.shared.ocrExtractionConcurrency
        Log.debug("[DocumentProcessor] Using \(maxConcurrentPages) concurrent pages for OCR (tier: \(DeviceCapabilityService.shared.tier.rawValue))", category: .ingestion)

        // PHASE 1.5: DYNAMIC VOCABULARY EXTRACTION
        // Extract domain-specific terms from PDFKit's rough text layer BEFORE Vision OCR.
        // This implements the "document teaches Vision what to look for" approach:
        //   1. PDFKit gives us fast, rough text (free — no Neural Engine needed)
        //   2. We mine it for acronyms, codes, technical terms, compound units
        //   3. Feed those as customWords to Vision, so its neural network knows
        //      "these ARE real words, don't autocorrect them"
        // This scales to ANY domain without hardcoding domain-specific vocabulary.
        let roughDocumentText: String
        if documentTextLayerGarbled {
            roughDocumentText = "" // PDFKit text is garbled — don't mine it for vocab
            Log.debug("[DocumentProcessor] Skipping dynamic vocabulary extraction (garbled text layer)", category: .ingestion)
        } else {
            roughDocumentText = (0..<min(pageCount, 50)).compactMap { i in
                pdfDocument.page(at: i)?.string
            }.joined(separator: "\n")
        }

        let documentCustomWords = OCRConfiguration.customWords(forDocumentText: roughDocumentText)
        self.currentDocumentCustomWords = documentCustomWords
        Log.debug("[DocumentProcessor] Dynamic vocabulary: \(documentCustomWords.count - OCRConfiguration.universalCustomWords.count) document-specific terms extracted", category: .ingestion)

        // PHASE 1.6: LANGUAGE NARROWING (idempotent; usually already done by the caller)
        await detectDocumentRecognitionLanguagesIfNeeded(pdfDocument: pdfDocument, pageCount: pageCount)

        // Result container for parallel extraction
        struct PageExtractionResult: Sendable {
            let pageIndex: Int
            let text: String
            let usedOCR: Bool
            let usedSpatial: Bool
            let ocrCharCount: Int
            let noTextLayer: Bool
        }

        // MEMORY OPTIMIZATION: Page data struct for batch rendering
        // We now render only maxConcurrentPages at a time instead of all pages upfront
        // Each 1260×1785 RGBA image ≈ 9MB; 542 pages would be 4.8GB if pre-rendered!
        struct PageData: Sendable {
            let pageIndex: Int
            let pageString: String?
            let pageImage: CIImage?
            let hasText: Bool
            let textQualityOK: Bool
            /// True when complexity analysis detected table or dense numeric content.
            /// Forces Vision OCR even when PDFKit text quality looks acceptable,
            /// because PDFKit scrambles table cell values and column alignment.
            let requiresOCRForAccuracy: Bool
        }

        // Parallel extraction using TaskGroup with controlled concurrency
        var results: [PageExtractionResult] = []

        // MEMORY-SAFE RENDERING: Limit how many full-resolution page images are alive at once.
        // At 360 DPI, each page = 6210×11040px ≈ 206 MB (opaque RGB).
        // Previous code rendered maxConcurrentPages (10) images at once = 2+ GB → OOM crash.
        // Now we sub-batch: render pdfRenderingConcurrency (3) images → OCR them → release → next.
        // Quality is UNCHANGED: same 360 DPI, same preprocessing, same Vision accuracy.
        let maxRenderConcurrency = DeviceCapabilityService.shared.pdfRenderingConcurrency
        Log.info("[DocumentProcessor] Memory-safe rendering: max \(maxRenderConcurrency) page images alive at once (\(maxRenderConcurrency) × ~206 MB = ~\(maxRenderConcurrency * 206) MB)", category: .ingestion)

        // Process pages in render-safe sub-batches
        // Outer stride: groups pages for progress reporting (keeps maxConcurrentPages for ANE pipeline)
        // Inner stride: limits concurrent full-res images to pdfRenderingConcurrency
        for batchStart in stride(from: startPageIdx, to: endPageIdx + 1, by: maxConcurrentPages) {
            let batchEnd = min(batchStart + maxConcurrentPages, endPageIdx + 1)

            // Sub-batch rendering: render only maxRenderConcurrency pages at a time
            for renderStart in stride(from: batchStart, to: batchEnd, by: maxRenderConcurrency) {
                let renderEnd = min(renderStart + maxRenderConcurrency, batchEnd)
                let subBatchIndices = renderStart..<renderEnd

            // MEMORY-SAFE: Render only this sub-batch's pages (maxRenderConcurrency at a time)
            // GPU ACCELERATION: Apply preprocessing filters for better OCR accuracy
            // ADAPTIVE OCR: Only render images for pages that need OCR based on complexity analysis
            var batchPageData: [PageData] = []
            for pageIndex in subBatchIndices {
                autoreleasepool {
                    guard let page = pdfDocument.page(at: pageIndex) else {
                        batchPageData.append(PageData(pageIndex: pageIndex, pageString: nil, pageImage: nil, hasText: false, textQualityOK: false, requiresOCRForAccuracy: false))
                        return
                    }

                    let pageNumber = pageIndex + 1
                    let complexity = pageComplexity[pageNumber]
                    let strategy = complexity?.processingStrategy ?? .enhancedOCR  // Default to safe
                    let renderScale = preferredOCRRenderScale(for: complexity, documentTextLayerGarbled: documentTextLayerGarbled)
                    let fidelityForcesVision = shouldForceVisionForAdaptiveRecovery(
                        analysis: complexity,
                        strategy: strategy,
                        documentTextLayerGarbled: documentTextLayerGarbled
                    )

                    let pageString = page.string

                    // Detect if this page has table/numeric content that REQUIRES Vision OCR
                    // even when PDFKit text quality looks acceptable.
                    // PDFKit text extraction scrambles table cell values and column alignment.
                    let requiresOCRForAccuracy: Bool = {
                        guard let c = complexity else { return false }
                        return c.tablePresence > 0.2 || c.numericDensity > 0.3
                    }()

                    // ADAPTIVE: Only render image if this page actually needs OCR
                    // Simple pages (.directText, .spatialText) skip expensive image rendering entirely!
                    // EXCEPTION: If text layer is garbled (font substitution cipher), ALL pages need OCR
                    var pageImage: CIImage? = nil
                    if documentTextLayerGarbled || fidelityForcesVision || strategy == .basicOCR || strategy == .enhancedOCR || strategy == .fullOCR {
                        // Complex page - render and preprocess image with adaptive strategy
                        if renderScale > 5.0 {
                            Log.info("[DocumentProcessor] Page \(pageNumber): fine text risk \(Int((complexity?.fineTextRisk ?? 0) * 100))% → rendering at \(Int(72 * renderScale)) DPI", category: .ingestion)
                        }
                        pageImage = renderPDFPageAsImage(page: page, scale: renderScale)
                        if let image = pageImage {
                            let textQuality = complexity?.textQuality ?? 0.7
                            let isScanned = complexity?.processingStrategy == .fullOCR
                            let hasText = (pageString?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 10
                            pageImage = preprocessImageForOCR(
                                image,
                                textQuality: textQuality,
                                hasNativeTextLayer: hasText,
                                isScanned: isScanned
                            )
                        }
                    }
                    // else: Skip image rendering - saves ~50-100ms per simple page!

                    // Pre-compute text presence and quality checks
                    let hasText = pageString != nil && !pageString!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    // When text layer is garbled (font substitution cipher), NEVER trust PDFKit text
                    // If the page is mixed-mode scanned, also do not trust the incomplete native text layer
                    let isMixedMode = complexity?.isMixedModeScanned ?? false
                    let textQualityOK = !documentTextLayerGarbled && !isMixedMode && hasText && isTextQualityAcceptable(pageString!)

                    traceIngestionDecision(
                        pageNumber: pageNumber,
                        strategy: fidelityForcesVision && strategy == .spatialText ? "\(strategy.description)+fidelity" : strategy.description,
                        hasText: hasText,
                        textQualityOK: textQualityOK,
                        requiresTableOCR: requiresOCRForAccuracy,
                        mode: fidelityForcesVision ? "ocr-extraction-fidelity" : "ocr-extraction"
                    )

                    // For pages with good text quality that DON'T have tables, try spatial extraction
                    // Table pages skip spatial — their text will come from Vision OCR instead
                    var effectiveString = pageString
                    if hasText && textQualityOK && !requiresOCRForAccuracy {
                        if let spatialText = extractTextWithSpatialOrdering(from: page), !spatialText.isEmpty {
                            effectiveString = spatialText
                        } else {
                            // Second of the two silent fallbacks to raw `page.string`. Same reason
                            // as the one in the batch path: the fallback does not preserve column
                            // order, so a page taking it is a quality event worth seeing.
                            Log.warning(
                                "[DocumentProcessor] Page \(pageIndex + 1): spatial extraction "
                                    + "produced nothing; using raw page text (column order not preserved)",
                                category: .ingestion
                            )
                        }
                    }

                    batchPageData.append(PageData(pageIndex: pageIndex, pageString: effectiveString, pageImage: pageImage, hasText: hasText, textQualityOK: textQualityOK, requiresOCRForAccuracy: requiresOCRForAccuracy))
                }
            }

            let batchResults = await withTaskGroup(of: PageExtractionResult.self) { group in
                for (batchOffset, pageIndex) in subBatchIndices.enumerated() {
                    let pageData = batchPageData[batchOffset]

                    group.addTask {
                        if Task.isCancelled {
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        }

                        let pageStartTime = Date()
                        let pageNumber = pageIndex + 1

                        let pageText = pageData.pageString
                        // Use pre-computed values to avoid MainActor calls
                        let hasText = pageData.hasText
                        let textQualityOK = pageData.textQualityOK
                        let requiresOCRForAccuracy = pageData.requiresOCRForAccuracy

                        if requiresOCRForAccuracy && pageData.pageImage != nil {
                            // ═══════════════════════════════════════════════════════════
                            // TABLE/NUMERIC PAGE: Force Vision OCR for accurate data
                            // PDFKit text extraction DESTROYS table structure —
                            // column values get scrambled, decimals get misread,
                            // and cell boundaries are lost. Vision OCR with
                            // RecognizeDocumentsRequest preserves exact numeric values.
                            // ═══════════════════════════════════════════════════════════
                            Log.debug("   🔬 Page \(pageNumber): Table/numeric content detected, forcing Vision OCR for accuracy", category: .ingestion)
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR (table accuracy)")
                            }

                            if let pageImage = pageData.pageImage,
                               let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                               !ocrText.isEmpty {
                                let pageTime = Date().timeIntervalSince(pageStartTime)
                                // Log comparison for debugging
                                let pdfKitChars = pageText?.count ?? 0
                                Log.debug("   ✓ Page \(pageNumber): Vision OCR \(ocrText.count) chars vs PDFKit \(pdfKitChars) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "table-forced-ocr",
                                    chars: ocrText.count,
                                    duration: pageTime,
                                    extra: [("pdfkitChars", "\(pdfKitChars)")]
                                )

                                return PageExtractionResult(
                                    pageIndex: pageIndex,
                                    text: ocrText,
                                    usedOCR: true,
                                    usedSpatial: false,
                                    ocrCharCount: ocrText.count,
                                    noTextLayer: false
                                )
                            }

                            // Vision OCR failed — fall through to PDFKit text if available
                            if hasText, let fallback = pageText {
                                Log.warning("   ⚠️ Page \(pageNumber): Vision OCR failed on table page, using PDFKit fallback", category: .ingestion)
                                self.traceIngestionOutcome(
                                    pageNumber: pageNumber,
                                    path: "table-fallback-pdfkit",
                                    chars: fallback.count,
                                    duration: Date().timeIntervalSince(pageStartTime)
                                )
                                return PageExtractionResult(
                                    pageIndex: pageIndex,
                                    text: fallback,
                                    usedOCR: false,
                                    usedSpatial: false,
                                    ocrCharCount: 0,
                                    noTextLayer: false
                                )
                            }
                        }

                        if hasText && textQualityOK {
                            // Good text layer - use it (spatial extraction already applied above)
                            let isSpatial = pageText != pageData.pageString  // Changed means spatial was used
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount)")
                            }
                            let pageTime = Date().timeIntervalSince(pageStartTime)
                            let method = isSpatial ? "spatial" : "text"
                            Log.debug("   ✓ Page \(pageNumber): \(pageText?.count ?? 0) chars (\(method), \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: isSpatial ? "spatial-ordering" : "native-text",
                                chars: pageText?.count ?? 0,
                                duration: pageTime
                            )

                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText ?? "",
                                usedOCR: false,
                                usedSpatial: isSpatial,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        } else if hasText && !textQualityOK {
                            // Poor quality text - try enhanced OCR
                            Log.debug("   ⚠️ Page \(pageNumber): Text layer quality poor, trying enhanced OCR...", category: .ingestion)
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR (quality)")
                            }

                            if let pageImage = pageData.pageImage {
                                if let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                                   !ocrText.isEmpty {
                                    // Check OCR quality on MainActor
                                    let ocrQualityOK = await MainActor.run { self.isTextQualityAcceptable(ocrText) }
                                    if ocrQualityOK {
                                        let pageTime = Date().timeIntervalSince(pageStartTime)
                                        Log.debug("   ✓ Page \(pageNumber): Enhanced OCR replaced garbage text (\(ocrText.count) chars, \(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                        self.traceIngestionOutcome(
                                            pageNumber: pageNumber,
                                            path: "quality-repair-ocr",
                                            chars: ocrText.count,
                                            duration: pageTime
                                        )

                                        return PageExtractionResult(
                                            pageIndex: pageIndex,
                                            text: ocrText,
                                            usedOCR: true,
                                            usedSpatial: false,
                                            ocrCharCount: ocrText.count,
                                            noTextLayer: false
                                        )
                                    }
                                }
                            }

                            // Fallback to original text
                            Log.warning("   ⚠️ Page \(pageNumber): Using original text despite quality concerns", category: .ingestion)
                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "quality-fallback-native",
                                chars: pageText?.count ?? 0,
                                duration: Date().timeIntervalSince(pageStartTime)
                            )
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: pageText ?? "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: false
                            )
                        } else {
                            // No text layer - OCR required
                            await MainActor.run {
                                self.progressHandler?("page \(pageNumber)/\(pageCount), OCR")
                            }

                            if let pageImage = pageData.pageImage {
                                if let (ocrText, _) = try? await self.performEnhancedSpatialOCR(on: pageImage, pageNumber: pageNumber),
                                   !ocrText.isEmpty {
                                    let pageTime = Date().timeIntervalSince(pageStartTime)
                                    Log.debug("   ✓ Page \(pageNumber): Enhanced OCR extracted \(ocrText.count) chars (\(String(format: "%.2f", pageTime))s)", category: .ingestion)
                                    self.traceIngestionOutcome(
                                        pageNumber: pageNumber,
                                        path: "no-text-ocr",
                                        chars: ocrText.count,
                                        duration: pageTime
                                    )

                                    return PageExtractionResult(
                                        pageIndex: pageIndex,
                                        text: ocrText,
                                        usedOCR: true,
                                        usedSpatial: false,
                                        ocrCharCount: ocrText.count,
                                        noTextLayer: true
                                    )
                                }
                            }

                            self.traceIngestionOutcome(
                                pageNumber: pageNumber,
                                path: "no-text-ocr-empty",
                                chars: 0,
                                duration: Date().timeIntervalSince(pageStartTime)
                            )
                            return PageExtractionResult(
                                pageIndex: pageIndex,
                                text: "",
                                usedOCR: false,
                                usedSpatial: false,
                                ocrCharCount: 0,
                                noTextLayer: true
                            )
                        }
                    }
                }

                var collected: [PageExtractionResult] = []
                for await result in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    collected.append(result)
                }
                return collected
            }

            try Task.checkCancellation()

            results.append(contentsOf: batchResults)
            // MEMORY-SAFE: batchPageData goes out of scope here, releasing CIImages
            // Only maxRenderConcurrency (3) page images were alive at once
            // At 360 DPI: 3 × 206 MB = ~618 MB peak vs previous 10 × 206 MB = 2+ GB
            } // end inner sub-batch (render-safe)
        } // end outer batch (progress reporting)

        // Sort results by page index and compute statistics
        results.sort { $0.pageIndex < $1.pageIndex }

        let rawPageTexts = results.map { $0.text }
        let pageTexts = removeGarbageLinesFromExtractedPages(rawPageTexts, source: "pdf-legacy")
        _ = results.filter { $0.noTextLayer }.count  // pagesWithoutText - tracked but not logged
        let ocrUsedCount = results.filter { $0.usedOCR }.count
        let totalOCRChars = results.reduce(0) { $0 + $1.ocrCharCount }
        let spatialExtractionCount = results.filter { $0.usedSpatial }.count

        // PASS 2: Remove repeated headers and footers
        progressHandler?("cleaning headers/footers")
        let cleanedPageTexts = removeRepeatedHeadersFooters(from: pageTexts)

        // PASS 3: Assemble final text with page mappings AND page break sentinels
        // The sentinel survives normalization and lets us split per-page later for FTS5 storage.
        var fullText = ""
        var pageTextRanges: PageTextMapping = [:]

        for (index, cleanedText) in cleanedPageTexts.enumerated() {
            let pageNumber = index + 1
            let pageStartIndex = fullText.endIndex

            if !cleanedText.isEmpty {
                // Insert page break sentinel between pages (not before first page)
                if !fullText.isEmpty {
                    fullText += "\n\n\(Self.pageBreakSentinel)\n\n"
                }
                fullText += cleanedText
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

}
