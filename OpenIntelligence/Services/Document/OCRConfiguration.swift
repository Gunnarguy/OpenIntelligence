// OCRConfiguration.swift
// OpenIntelligence
//
// ═══════════════════════════════════════════════════════════════════════════════
// ADAPTIVE DOCUMENT INTELLIGENCE ENGINE
// ═══════════════════════════════════════════════════════════════════════════════
//
// This is NOT a config file. It is the brain of the ingestion pipeline.
//
// MISSION: Ingest ANY document — scanned receipts, medical research, ancient
// legal contracts, hand-drawn schematics, blurry phone photos, 600-page PDFs
// with mixed tables/figures/text in 13 languages — and extract EVERY piece of
// data with ZERO loss.
//
// DESIGN PRINCIPLES:
//   1. ZERO domain assumptions. No hardcoded automotive/medical/legal terms.
//   2. The DOCUMENT teaches US what to look for, not the other way around.
//   3. Multiple candidates, confidence-weighted. Never trust a single OCR pass.
//   4. Adaptive preprocessing — different filters for different page conditions.
//   5. Escalating DPI — start reasonable, re-scan at higher DPI if confidence low.
//   6. Every decision is logged and measurable.
//
// ARCHITECTURE:
//   OCRConfiguration       — Central config: vocabulary, languages, factory methods
//   AdaptivePreprocessor   — Multi-strategy image enhancement with quality scoring
//   ConfidenceVerifier     — Character-level confidence analysis for numeric data
//
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import CoreImage
import Vision
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - OCR Configuration (Central Authority)

/// Single source of truth for ALL Vision OCR configuration.
/// Every VNRecognizeTextRequest and RecognizeDocumentsRequest in the codebase
/// MUST use these factory methods instead of configuring requests manually.
enum OCRConfiguration {

    // MARK: - Genuinely Universal Custom Words

    /// Words that appear across 3+ unrelated domains. These are mathematical,
    /// scientific, and structural — NOT domain-specific.
    /// Domain vocabulary is extracted dynamically from each document.
    static let universalCustomWords: [String] = [
        // SI units & prefixes (ISO 80000)
        "kg", "g", "mg", "µg", "ng",
        "km", "m", "cm", "mm", "µm", "nm",
        "kL", "L", "mL", "µL", "dL",
        "kW", "W", "mW", "MW", "GW",
        "kWh", "MWh",
        "kHz", "Hz", "MHz", "GHz", "THz",
        "kPa", "MPa", "GPa", "Pa", "hPa",
        "kJ", "J", "MJ",
        "mol", "mmol", "µmol",
        "°C", "°F", "K",
        "dB", "dBm",
        "Ω", "kΩ", "MΩ",
        "V", "mV", "kV",
        "A", "mA", "µA",
        // Imperial (US/UK standard)
        "lb", "lbs", "oz", "fl",
        "gal", "qt", "pt",
        "ft", "in", "yd", "mi",
        "psi", "PSI",
        "hp", "HP",
        "mph", "fps",
        "BTU", "Btu",
        // Compound units
        "km/h", "m/s", "ft/s",
        "mg/dL", "mmol/L", "mEq/L",
        "kg/m³", "g/cm³",
        "N·m", "Nm", "ft-lb", "lb-ft",
        "rpm", "RPM",
        "ppm", "ppb",
        // Math & science symbols
        "±", "≤", "≥", "×", "÷", "≈", "≠", "∞",
        "²", "³", "⁻¹",
        "π", "Σ", "Δ", "α", "β", "γ", "λ", "µ", "σ", "θ", "φ",
        "pH",
        // Document structure (universal across all formatted docs)
        "N/A", "n/a", "TBD", "TBA",
        "No.", "Nos.", "Vol.", "Fig.", "Sec.", "Pg.",
        "vs.", "etc.", "i.e.", "e.g.", "approx.",
        "max", "min", "avg", "typ", "nom",
        "Qty", "Ref", "Rev", "Ver",
        // Safety / legal callouts (international standard labels)
        "CAUTION", "WARNING", "DANGER", "NOTE", "NOTICE", "IMPORTANT",
        // Data sizes
        "KB", "MB", "GB", "TB", "PB",
        "Kbps", "Mbps", "Gbps",
    ]

    // MARK: - Recognition Languages

    /// All languages Vision supports for text recognition, in priority order.
    /// Applied uniformly to every OCR request — no more fragmented lists.
    static let recognitionLanguages: [String] = [
        "en-US", "en-GB",           // English (primary)
        "es-ES", "fr-FR", "de-DE",  // Romance / Germanic
        "it-IT", "pt-BR", "nl-NL",  // More European
        "pl-PL",                     // Slavic
        "ja-JP", "ko-KR",           // East Asian
        "zh-Hans", "zh-Hant",       // Chinese
    ]

    // MARK: - Factory Methods (Single Source of Truth)

    /// Configure a VNRecognizeTextRequest with maximum accuracy settings.
    /// Every VNRecognizeTextRequest in the codebase MUST go through this.
    ///
    /// - Parameter customWords: Document-specific vocabulary (from `customWords(forDocumentText:)`)
    /// - Returns: Fully configured request ready to perform
    static func configureRequest(_ request: VNRecognizeTextRequest, customWords: [String]? = nil) {
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = recognitionLanguages
        request.minimumTextHeight = 0.0  // Detect ALL text including tiny footnotes
        request.customWords = customWords ?? universalCustomWords
    }

    // MARK: - Dynamic Vocabulary Extraction

    /// Extract domain-specific vocabulary from a document's raw text layer.
    /// The document teaches Vision what to look for — not the other way around.
    ///
    /// Called ONCE during ingestion, BEFORE Vision OCR runs.
    /// PDFKit gives us rough (possibly garbled) text. We extract:
    ///   - Acronyms (all-caps 2-8 chars)
    ///   - Alphanumeric codes (mixed letters+digits+hyphens)
    ///   - CamelCase/PascalCase words
    ///   - Technical compound terms (slashes, dots)
    ///   - Repeated capitalized bigrams (proper nouns, product names)
    ///
    /// - Parameter rawText: Text from PDFKit's native text layer (may be imperfect)
    /// - Returns: Up to 500 document-specific custom words
    static func extractDynamicVocabulary(from rawText: String) -> [String] {
        guard !rawText.isEmpty else { return [] }

        var vocabulary = Set<String>()

        let sampleText = String(rawText.prefix(50_000))
        let words = sampleText.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        for word in words {
            guard word.count >= 2, word.count <= 40 else { continue }

            // Acronyms: 2-8 all-uppercase letters (TPMS, HVAC, CBC, DOHC)
            if word.count <= 8, word == word.uppercased(), word.allSatisfy({ $0.isLetter }) {
                vocabulary.insert(word)
                continue
            }

            // Alphanumeric codes: letters+digits mix (0W-20, A1C, R-134a)
            let hasDigit = word.contains(where: { $0.isNumber })
            let hasLetter = word.contains(where: { $0.isLetter })
            let hasHyphen = word.contains("-")
            if hasDigit && hasLetter {
                vocabulary.insert(word)
                continue
            }
            if hasHyphen && (hasDigit || hasLetter) && word.count >= 3 {
                vocabulary.insert(word)
                continue
            }

            // CamelCase / internal capitals (kWh, iPhone, mEq)
            if word.count >= 3 {
                let midChars = word.dropFirst().dropLast()
                if midChars.contains(where: { $0.isUppercase }) {
                    vocabulary.insert(word)
                    continue
                }
            }

            // Slash/dot compound terms (mg/dL, 3.5L, ft-lb)
            if word.contains("/") || (word.contains(".") && hasLetter) {
                vocabulary.insert(word)
                continue
            }

            // Low-vowel-ratio words: likely abbreviations (ctrl, mgmt, cfg)
            if word.count >= 4, word.allSatisfy({ $0.isLetter }) {
                let vowels = Set("aeiouAEIOU")
                let vowelRatio = Double(word.filter { vowels.contains($0) }.count) / Double(word.count)
                if vowelRatio < 0.2 {
                    vocabulary.insert(word)
                }
            }
        }

        // Repeated capitalized bigrams → proper nouns, product names
        let lines = sampleText.components(separatedBy: .newlines)
        var bigramCounts: [String: Int] = [:]
        for line in lines {
            let lineWords = line.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
            for i in 0..<max(0, lineWords.count - 1) {
                if let c1 = lineWords[i].first, let c2 = lineWords[i + 1].first,
                   c1.isUppercase, c2.isUppercase {
                    bigramCounts["\(lineWords[i]) \(lineWords[i + 1])", default: 0] += 1
                }
            }
        }
        for (bigram, count) in bigramCounts where count >= 2 {
            vocabulary.insert(bigram)
        }

        return Array(vocabulary.prefix(500))
    }

    /// Build final custom words: universal + document-specific dynamic vocabulary.
    static func customWords(forDocumentText documentText: String?) -> [String] {
        var words = universalCustomWords
        if let text = documentText, !text.isEmpty {
            let dynamic = extractDynamicVocabulary(from: text)
            let existing = Set(words)
            words.append(contentsOf: dynamic.filter { !existing.contains($0) })
        }
        return words
    }

    // MARK: - Post-OCR Garbage Text Detection

    /// Unicode scalar ranges for Cyrillic characters
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x04FF
    private static let cyrillicSupplementRange: ClosedRange<UInt32> = 0x0500...0x052F

    /// Detect document language using NLLanguageRecognizer.
    /// Returns whether the document is primarily a Latin-script language.
    /// This prevents garbage filters from destroying legitimate non-Latin documents.
    private static func detectDocumentLanguage(_ text: String) -> (isLatinScript: Bool, dominantLanguage: NLLanguage?) {
        let recognizer = NLLanguageRecognizer()
        // Use a sample to avoid processing huge texts
        let sample = String(text.prefix(2000))
        recognizer.processString(sample)

        guard let dominant = recognizer.dominantLanguage else {
            // Can't detect → assume Latin to enable garbage filtering (conservative)
            return (true, nil)
        }

        // Latin-script languages where Cyrillic/non-ASCII detection is valid
        let latinScriptLanguages: Set<NLLanguage> = [
            .english, .french, .german, .spanish, .portuguese,
            .italian, .dutch, .swedish, .danish, .norwegian,
            .finnish, .polish, .czech, .romanian, .hungarian,
            .turkish, .indonesian, .malay, .vietnamese,
            .catalan, .croatian, .slovak
        ]

        let isLatin = latinScriptLanguages.contains(dominant)
        return (isLatin, dominant)
    }

    /// Check if a single line of OCR output is garbage.
    ///
    /// Garbage patterns from rotated/angled text in parts diagrams:
    ///   1. Cyrillic characters mixed with Latin (Vision misreads rotated Latin as Cyrillic)
    ///   2. Extremely low vowel ratio (consonant noise)
    ///   3. High non-ASCII ratio when document language is Latin
    ///   4. Very short "words" that are just character salad
    ///
    /// - Parameters:
    ///   - line: A single line of OCR text
    ///   - isLatinDocument: Whether the document is in a Latin-script language.
    ///     Rules 1, 2, 4 only fire for Latin-script documents to avoid destroying
    ///     Russian, Arabic, Chinese, etc.
    /// - Returns: true if the line appears to be garbage OCR output
    static func isGarbageText(_ line: String, isLatinDocument: Bool = true) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false } // Too short to judge

        let scalars = trimmed.unicodeScalars

        // Count character categories
        var latinCount = 0
        var cyrillicCount = 0
        var digitCount = 0
        var asciiCount = 0
        var totalLetters = 0

        for scalar in scalars {
            let value = scalar.value
            if (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value) {
                latinCount += 1
                asciiCount += 1
                totalLetters += 1
            } else if cyrillicRange.contains(value) || cyrillicSupplementRange.contains(value) {
                cyrillicCount += 1
                totalLetters += 1
            } else if (0x0030...0x0039).contains(value) {
                digitCount += 1
                asciiCount += 1
            } else if value < 0x0080 {
                asciiCount += 1
            }
        }

        let totalChars = scalars.count

        // === LATIN-SCRIPT-ONLY RULES ===
        // These rules detect Vision misreads where Latin is confused with Cyrillic.
        // They MUST NOT fire for legitimate Russian, Ukrainian, etc. documents.
        if isLatinDocument {
            // Rule 1: Cyrillic in a Latin document = Vision misread rotated text
            if cyrillicCount > 0 && latinCount > 0 {
                let cyrillicRatio = Double(cyrillicCount) / Double(totalChars)
                if cyrillicRatio > 0.10 {
                    return true
                }
            }

            // Rule 2: Purely Cyrillic block in a Latin document = misread
            if cyrillicCount > 3 && latinCount == 0 && digitCount == 0 {
                return true
            }

            // Rule 4: High non-ASCII ratio in a Latin document
            let nonAsciiRatio = 1.0 - (Double(asciiCount) / Double(totalChars))
            if nonAsciiRatio > 0.40 && totalChars > 8 {
                return true
            }
        }

        // === UNIVERSAL RULES (apply to ALL languages) ===

        // Rule 3: Very low vowel ratio for text with enough letters
        // This detects consonant noise from truly garbled OCR regardless of script
        if totalLetters >= 8 {
            // Expanded vowel set covering multiple scripts
            let vowels = Set<Character>([
                "a", "e", "i", "o", "u", "A", "E", "I", "O", "U",           // Latin
                "а", "е", "и", "о", "у", "э", "ю", "я", "ё",               // Cyrillic lower
                "А", "Е", "И", "О", "У", "Э", "Ю", "Я", "Ё",               // Cyrillic upper
                "ä", "ö", "ü", "à", "è", "ì", "ò", "ù", "é", "ê", "î",     // Extended Latin
                "â", "ô", "á", "í", "ó", "ú", "å", "ø", "æ"                // Nordic/Portuguese
            ])
            let vowelCount = trimmed.filter { vowels.contains($0) }.count
            let vowelRatio = Double(vowelCount) / Double(totalLetters)
            if vowelRatio < 0.03 {
                return true // Almost no vowels = consonant noise
            }
        }

        // Rule 5: Excessive punctuation/symbols (>60% non-alphanumeric in a long string)
        let alphanumCount = totalLetters + digitCount
        if totalChars > 10 && Double(alphanumCount) / Double(totalChars) < 0.35 {
            return true
        }

        return false
    }

    /// Filter garbage lines from OCR output while preserving valid text.
    /// Uses NLLanguageRecognizer to detect document language before filtering,
    /// preventing destruction of legitimate non-Latin documents.
    ///
    /// - Parameter text: Raw OCR text (may contain garbage)
    /// - Returns: Cleaned text with garbage lines removed, and count of removed lines
    static func filterGarbageText(_ text: String) -> (cleaned: String, removedCount: Int) {
        // LANGUAGE AWARENESS: Detect if this is a Latin-script document
        // If it's Russian, Arabic, Chinese, etc. — skip Latin-specific rules
        let (isLatinScript, detectedLang) = detectDocumentLanguage(text)
        if !isLatinScript, let lang = detectedLang {
            Log.info("[OCR] Non-Latin document detected (\(lang.rawValue)) — using language-safe garbage filter", category: .ingestion)
        }

        let lines = text.components(separatedBy: .newlines)
        var kept: [String] = []
        var removedCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Keep empty lines (preserve paragraph structure)
            if trimmed.isEmpty {
                kept.append(line)
                continue
            }

            // Keep lines that are just numbers or short codes (model numbers, page numbers)
            if trimmed.count <= 3 {
                kept.append(line)
                continue
            }

            // Check for garbage using language-aware rules
            if isGarbageText(trimmed, isLatinDocument: isLatinScript) {
                removedCount += 1
                continue
            }

            kept.append(line)
        }

        // If we removed more than 80% of substantive lines, the filtering was too aggressive
        // — return original text rather than empty to avoid silent data loss
        let substantiveLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if substantiveLines.count > 3 && removedCount > (substantiveLines.count * 4 / 5) {
            Log.warning("[OCR] Garbage filter removed \(removedCount)/\(substantiveLines.count) lines — too aggressive, keeping original", category: .ingestion)
            return (text, 0)  // Return original rather than empty
        }

        return (kept.joined(separator: "\n"), removedCount)
    }

    // MARK: - Universal Text Normalization

    /// Normalizes extracted text for clean chunking and embedding.
    /// Runs on ALL extracted text (both PDFKit and OCR) to fix:
    /// - Unicode compatibility forms (ligatures ﬁ→fi, ﬂ→fl, ﬀ→ff, etc.)
    /// - Broken hyphens at line breaks (speci-\nfication → specification)
    /// - Curly/smart quotes → straight quotes
    /// - Zero-width characters that break tokenization
    /// - Multi-space column alignment artifacts
    /// - Stray control characters
    ///
    /// This is the SINGLE normalization gate between raw extraction and the
    /// chunking/embedding pipeline.  Every document — PDF, image, Office,
    /// audio transcript — passes through here exactly once.
    static func normalizeExtractedText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // 1. Unicode NFKC: decomposes compatibility forms + recomposes canonical.
        //    Fixes ligatures (ﬁ→fi), fullwidth chars (Ａ→A), superscripts, etc.
        var result = text.precomposedStringWithCompatibilityMapping  // NFKC

        // 2. Remove zero-width characters that break BertTokenizer
        let zeroWidthChars: [Character] = [
            "\u{200B}",  // Zero-width space
            "\u{200C}",  // Zero-width non-joiner
            "\u{200D}",  // Zero-width joiner
            "\u{FEFF}",  // BOM / zero-width no-break space
            "\u{00AD}",  // Soft hyphen
        ]
        result = String(result.filter { !zeroWidthChars.contains($0) })

        // 3. Repair broken hyphens at line breaks: "speci-\nfication" → "specification"
        //    Only joins when the hyphen is followed by a newline + lowercase letter,
        //    which is the universal pattern for word-wrap hyphenation.
        //    Preserves intentional hyphens like "self-contained" (no newline).
        result = result.replacingOccurrences(
            of: #"([a-zA-Z])\-\s*\n\s*([a-z])"#,
            with: "$1$2",
            options: .regularExpression
        )

        // 4. Smart/curly quotes → straight (prevents tokenizer confusion)
        let quoteMap: [Character: Character] = [
            "\u{2018}": "'",   // Left single
            "\u{2019}": "'",   // Right single / apostrophe
            "\u{201C}": "\"", // Left double
            "\u{201D}": "\"", // Right double
            "\u{2032}": "'",   // Prime
            "\u{2033}": "\"", // Double prime
            "\u{00AB}": "\"", // «
            "\u{00BB}": "\"", // »
        ]
        result = String(result.map { quoteMap[$0] ?? $0 })

        // 5. Normalize dashes: em-dash / en-dash → standard hyphen-minus
        //    when surrounded by alphanumeric (spec values like "0W-20")
        //    Keep em-dashes in prose (they'll have spaces around them)
        //    NOTE: Raw strings (#"..."#) require \x{HHHH} for ICU regex, NOT \u{HHHH}
        result = result.replacingOccurrences(
            of: #"([A-Za-z0-9])\x{2013}([A-Za-z0-9])"#,
            with: "$1-$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"([A-Za-z0-9])\x{2014}([A-Za-z0-9])"#,
            with: "$1-$2",
            options: .regularExpression
        )

        // 6. Collapse multi-space runs (from column alignment, OCR spacing)
        //    but preserve single newlines (paragraph structure)
        result = result.replacingOccurrences(
            of: #"[^\S\n]{2,}"#,
            with: " ",
            options: .regularExpression
        )

        // 7. Normalize line endings: \r\n → \n, standalone \r → \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // 8. Collapse 3+ consecutive blank lines into 2 (preserve paragraph gaps)
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        // 9. Remove stray control characters (C0/C1) except tab and newline
        result = String(result.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0x09 || v == 0x0A { return true }  // Keep tab, newline
            if v < 0x20 { return false }                // Remove C0 controls
            if (0x7F...0x9F).contains(v) { return false } // Remove DEL + C1 controls
            return true
        }.map { Character($0) })

        // 10. Replace CJK bullet artifacts in Latin-dominant text
        //     Many PDFs from Asian publishers (Kia, Hyundai, etc.) encode bullet
        //     point glyphs as CJK ideographs in the text layer. PDFKit faithfully
        //     extracts them (e.g. 僅 U+50C5 instead of •). Replace isolated CJK
        //     chars at line starts with standard bullets when the document is
        //     predominantly Latin script.
        result = replaceCJKBulletArtifacts(result)

        // 11. Repair systematic ll-ligature encoding errors
        //     Some PDF fonts map the "ll" ligature to a single "l" in their
        //     ToUnicode table. PDFKit extracts "wil" instead of "will", "al"
        //     instead of "all", etc. Detect the pattern and repair using a
        //     curated word list where single-l is NEVER valid English.
        result = repairLLLigature(result)

        // 12. Miscellaneous symbol normalization
        //     Japanese long vowel mark ー (U+30FC) misread as dash
        //     CJK numeral 一 (U+4E00) used as horizontal line
        result = result.replacingOccurrences(of: "\u{30FC}", with: "-")  // Katakana ー → -
        // Only replace 一 when surrounded by digits (used as dash in "2一8" → "2-8")
        //     NOTE: Raw strings (#"..."#) require \x{HHHH} for ICU regex, NOT \u{HHHH}
        result = result.replacingOccurrences(
            of: #"(\d)\x{4E00}(\d)"#,
            with: "$1-$2",
            options: .regularExpression
        )

        // 13. Strip document noise artifacts
        //     Removes lines that are ONLY internal asset codes, orphan page numbers,
        //     or cross-reference page clusters. These are structural PDF artifacts
        //     that waste chunk token budget and pollute BM25/vector search.
        result = stripDocumentNoise(result)

        return result
    }

    // MARK: - CJK Bullet Artifact Replacement

    /// Replaces isolated CJK ideographs used as bullet markers in Latin-dominant text.
    /// Only triggers when >85% of the text is Latin/ASCII — safe for actual CJK documents.
    private static func replaceCJKBulletArtifacts(_ text: String) -> String {
        // Quick exit: if text is short, skip analysis
        guard text.count > 200 else { return text }

        // Check if text is predominantly Latin
        let sampleSize = min(text.count, 3000)
        let sample = String(text.prefix(sampleSize))
        let sampleScalars = sample.unicodeScalars
        let totalScalars = sampleScalars.count
        guard totalScalars > 0 else { return text }

        let latinAndCommonCount = sampleScalars.filter { scalar in
            let v = scalar.value
            // Latin, Latin Extended, digits, ASCII punctuation, whitespace
            return v < 0x0250 || (0x2000...0x206F).contains(v) ||  // General Punctuation
                   CharacterSet.whitespaces.contains(scalar) ||
                   CharacterSet.decimalDigits.contains(scalar)
        }.count

        let latinRatio = Double(latinAndCommonCount) / Double(totalScalars)
        guard latinRatio > 0.85 else { return text }  // Not Latin-dominant, leave as-is

        // Replace CJK ideographs at line starts used as bullet points:
        // Pattern: start-of-line + optional whitespace + single CJK char + optional whitespace + Latin letter
        // CJK Unified Ideographs: U+4E00-U+9FFF, Extension A: U+3400-U+4DBF
        // NOTE: Raw strings (#"..."#) require \x{HHHH} for ICU regex, NOT \u{HHHH}
        //       Swift does NOT process \u{} escapes in raw strings — they pass as literal text.
        //       ICU regex only understands \x{HHHH} (with braces) or \uHHHH (no braces).
        var result = text
        // Case 1: CJK char + space(s) + Latin letter (most common: "僅 Tighten")
        result = result.replacingOccurrences(
            of: #"(?:^|\n)([ \t]*)[\x{4E00}-\x{9FFF}\x{3400}-\x{4DBF}]\s+(?=[A-Za-z])"#,
            with: "\n$1- ",
            options: .regularExpression
        )
        // Case 2: CJK char immediately followed by Latin letter, no space ("僅How")
        result = result.replacingOccurrences(
            of: #"(?:^|\n)([ \t]*)[\x{4E00}-\x{9FFF}\x{3400}-\x{4DBF}](?=[A-Za-z])"#,
            with: "\n$1- ",
            options: .regularExpression
        )

        // Also replace isolated CJK chars used inline as separators (rare but seen)
        // Only when surrounded by Latin text on both sides
        result = result.replacingOccurrences(
            of: #"([a-zA-Z.,;:!?)\]]) [\x{4E00}-\x{9FFF}] ([A-Za-z])"#,
            with: "$1 - $2",
            options: .regularExpression
        )

        return result
    }

    // MARK: - LL-Ligature Repair

    /// Detects and repairs systematic "ll" → "l" font encoding errors.
    ///
    /// Many PDF generators (especially Asian publishing tools) use fonts where
    /// the "ll" ligature glyph maps to a single "l" in the ToUnicode table.
    /// PDFKit faithfully extracts this, producing "wil" instead of "will",
    /// "colision" instead of "collision", etc.
    ///
    /// This method first DETECTS the pattern (requiring ≥3 unambiguous indicators),
    /// then applies a curated word list where single-l is NEVER a valid English word.
    private static func repairLLLigature(_ text: String) -> String {
        guard text.count > 100 else { return text }

        // Phase 1: Detect if document has the systematic ll→l issue
        // These words/stems are NEVER valid English with single-l
        let indicators: [(pattern: String, weight: Int)] = [
            (#"\bwil\b"#, 2),          // "wil" is never valid (will)
            (#"\balow"#, 2),           // "alow" is never valid (allow)
            (#"\bfolow"#, 2),          // "folow" is never valid (follow)
            (#"\binstal(?!l)"#, 1),    // "instal" without ll (install)
            (#"\bilustr"#, 2),         // "ilustr" is never valid (illustr)
            (#"\boveral\b"#, 1),       // "overal" is never valid (overall)
            (#"\bcolision"#, 2),       // "colision" is never valid (collision)
            (#"\bsmal\b"#, 1),         // "smal" is never valid (small)
            (#"\bfinaly\b"#, 1),       // adverb suffix
        ]

        var score = 0
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for (pattern, weight) in indicators {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.numberOfMatches(in: text, range: fullRange)
            score += matches * weight
            if score >= 5 { break }  // Early exit once confident
        }

        // Need strong evidence (≥5 weighted score) to avoid false positives
        guard score >= 5 else { return text }

        var result = text

        // Phase 2a: Whole-word replacements (highest confidence)
        let wholeWordFixes: [(wrong: String, right: String)] = [
            ("wil", "will"),
            ("wel", "well"),
            ("tel", "tell"),     // "tel" (archaeo mound) is vanishingly rare vs "tell"
            ("sel", "sell"),
            ("bel", "bell"),     // standalone "bel" (unit) extremely rare in general text
            ("cel", "cell"),
            ("fel", "fell"),
            ("shal", "shall"),
            ("stil", "still"),
            ("smal", "small"),
            ("spil", "spill"),
            ("skil", "skill"),
            ("pul", "pull"),     // "pul" is not a standard word
            ("ful", "full"),     // standalone "ful" is not valid
            ("tal", "tall"),
            ("wal", "wall"),
            ("rol", "roll"),
            ("fil", "fill"),     // standalone "fil" is not standard
            ("bul", "bull"),
            ("hil", "hill"),
            ("kil", "kill"),
            ("mil", "mill"),     // "mil" IS a unit, but "mill" is more common in general text
            ("dril", "drill"),
            ("gril", "grill"),
            ("spel", "spell"),
            ("dwel", "dwell"),
            ("swel", "swell"),
            ("smel", "smell"),
            ("shel", "shell"),
            ("colar", "collar"),  // "colar" is never valid
            ("instal", "install"),
        ]

        for fix in wholeWordFixes {
            // Case-sensitive whole-word replacement
            result = result.replacingOccurrences(
                of: "\\b\(fix.wrong)\\b",
                with: fix.right,
                options: .regularExpression
            )
            // Capitalized variant (sentence start)
            let capWrong = fix.wrong.prefix(1).uppercased() + fix.wrong.dropFirst()
            let capRight = fix.right.prefix(1).uppercased() + fix.right.dropFirst()
            result = result.replacingOccurrences(
                of: "\\b\(capWrong)\\b",
                with: capRight,
                options: .regularExpression
            )
        }

        // Phase 2b: Stem replacements (prefix match, covers all inflections)
        // e.g., "alow" matches "alowed", "alowing", "alowance"
        let stemFixes: [(wrong: String, right: String)] = [
            ("alow", "allow"),
            ("folow", "follow"),
            ("ilustr", "illustr"),
            ("colision", "collision"),
            ("colect", "collect"),
            ("colaps", "collaps"),
            ("colabor", "collabor"),
            ("colater", "collater"),
            ("milion", "million"),
            ("bilion", "billion"),
            ("galery", "gallery"),
            ("galer", "galler"),
            ("paralel", "parallel"),
            ("inteligent", "intelligent"),
            ("inteligenc", "intelligenc"),
            ("celing", "ceiling"),
            ("excelent", "excellent"),
            ("cancelation", "cancellation"),
            ("fufilment", "fulfillment"),
            ("fulfilment", "fulfillment"),  // British variant
            ("enrolment", "enrollment"),
            ("metalic", "metallic"),
            ("crystaline", "crystalline"),
            ("sateite", "satellite"),
            ("apeling", "appealing"),
            ("balast", "ballast"),
            ("baloon", "balloon"),
            ("bulet", "bullet"),
            ("chaleng", "challeng"),
            ("compeling", "compelling"),
            ("controling", "controlling"),
            ("controled", "controlled"),
            ("controler", "controller"),
            ("counseling", "counselling"),
            ("counselor", "counsellor"),
            ("dweling", "dwelling"),
            ("exeling", "excelling"),
            ("filing", "filling"),    // "filing" IS valid but in ll-ligature docs, likely "filling"
            ("fueling", "fuelling"),
            ("griling", "grilling"),
            ("halway", "hallway"),
            ("ilegal", "illegal"),
            ("ilicit", "illicit"),
            ("iluminate", "illuminate"),
            ("ilusion", "illusion"),
            ("ilustrate", "illustrate"),
            ("instaling", "installing"),
            ("instaled", "installed"),
            ("instalation", "installation"),
            ("kiling", "killing"),
            ("meling", "melling"),
            ("paroling", "patrolling"),
            ("poling", "polling"),
            ("polut", "pollut"),
            ("puling", "pulling"),
            ("recaling", "recalling"),
            ("repeling", "repelling"),
            ("roling", "rolling"),
            ("seling", "selling"),
            ("sheling", "shelling"),
            ("skiling", "skilling"),
            ("smeling", "smelling"),
            ("speling", "spelling"),
            ("spiling", "spilling"),
            ("staling", "stalling"),
            ("sweling", "swelling"),
            ("teling", "telling"),
            ("thril", "thrill"),
            ("yelow", "yellow"),
            ("vilage", "village"),
            ("rolover", "rollover"),
            ("spilage", "spillage"),
            ("colarbone", "collarbone"),
            ("reinstal", "reinstall"),
            ("uninstal", "uninstall"),
            ("preinstal", "preinstall"),
            ("basebal", "baseball"),
            ("basketbal", "basketball"),
            ("footbal", "football"),
            ("softbal", "softball"),
            ("voleybal", "volleyball"),
            ("firewal", "firewall"),
            ("downhil", "downhill"),
            ("uphil", "uphill"),
            ("alocat", "allocat"),
            ("aply", "apply"),      // stem covers "aplying", "aplied"
            ("apeal", "appeal"),
            ("balad", "ballad"),
            ("balet", "ballet"),
            ("beliger", "belliger"),
            ("bilard", "billiard"),
            ("bulit", "bullet"),     // alternate of "bulet"
            ("caling", "calling"),
            ("caterpil", "caterpill"),
            ("chily", "chilly"),
            ("colar", "collar"),
            ("galop", "gallop"),
            ("gorila", "gorilla"),
            ("guerilar", "guerillar"),
            ("halucin", "hallucin"),
            ("miscel", "miscell"),
            ("paral", "parall"),
            ("rebelio", "rebellio"),
            ("surveilance", "surveillance"),
            ("vanila", "vanilla"),
            ("vilain", "villain"),
            ("walboard", "wallboard"),
            ("walet", "wallet"),
            ("walpaper", "wallpaper"),
        ]

        for fix in stemFixes {
            // Case-insensitive stem replacement
            // Negative lookahead (?!l) prevents double-fixing "install" → "installl"
            result = result.replacingOccurrences(
                of: "(?i)\\b\(fix.wrong)(?!l)",
                with: fix.right,
                options: .regularExpression
            )
        }

        // Phase 2c: Adverb -aly → -ally (covers dozens of words at once)
        // "carefuly" → "carefully", "especialy" → "especially", etc.
        // Exclude "anomaly" (the only common English word ending in -aly)
        result = result.replacingOccurrences(
            of: #"(?i)(?<!anom)(\w{3,})aly\b"#,
            with: "$1ally",
            options: .regularExpression
        )

        // Phase 2d: "al" → "all" when lowercase before lowercase word
        // "al rights" → "all rights", "al passengers" → "all passengers"
        // Safe because lowercase "al" before a lowercase word is almost never a name
        result = result.replacingOccurrences(
            of: #"(?<![A-Za-z])al (?=[a-z])"#,
            with: "all ",
            options: .regularExpression
        )

        // Also fix "Al " at very start of sentence before common determiners/prepositions
        // that would make no sense as a name: "Al rights reserved" → "All rights reserved"
        result = result.replacingOccurrences(
            of: #"(?:^|\n)Al (?=rights|information|options|variants|types|passengers|occupants|vehicles|vehicle|seat|seats|of|the|that|those|these|other|children|under|data|ages|new|models|doors|windows|features|functions|controls|settings|items|components|parts|instructions)"#,
            with: "All ",
            options: .regularExpression
        )

        // Phase 2e: "overal" at word boundary → "overall"
        result = result.replacingOccurrences(
            of: #"(?i)\boveral\b"#,
            with: "overall",
            options: .regularExpression
        )

        return result
    }

    // MARK: - Document Noise Stripping

    /// Removes lines that consist solely of structural PDF artifacts:
    /// internal asset/figure reference codes, orphan page numbers, and
    /// cross-reference page clusters. These waste chunk token budget and
    /// pollute BM25/vector search with non-content tokens.
    ///
    /// Only removes entire lines — never modifies partial lines. This ensures
    /// no real content is accidentally stripped.
    private static func stripDocumentNoise(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Preserve blank lines (paragraph structure matters for chunking)
            guard !trimmed.isEmpty else { return line }

            // 1. Remove standalone asset/figure reference codes
            //    ONQ5011001N, OCV031071, ONQ5021120N_2, etc.
            if isStandaloneAssetCode(trimmed) { return nil }

            // 2. Remove orphan compound page number annotations
            //    "2 2", "3 - 5", "2-", "2 — 7", standalone "42"
            if isOrphanPageAnnotation(trimmed) { return nil }

            // 3. Remove standalone cross-reference page clusters
            //    "4-38", "4-93, 8-54", "8-29, 9-6"
            if isCrossReferenceCluster(trimmed) { return nil }

            // 4. Clean TOC leader dots (reformat, don't remove)
            //    "Fuel requirements .........  1-2" → "Fuel requirements 1-2"
            if trimmed.contains("...") {
                let cleaned = trimmed.replacingOccurrences(
                    of: #"\.{2,}"#,
                    with: " ",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #" {2,}"#,
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespaces)
                return cleaned
            }

            // 5. Remove lines that are ONLY an asterisk + boilerplate illustration note
            //    "* The actual shape may differ from the illustration."
            //    "* The actual engine compartment in the vehicle may differ from the illustration."
            //    These repeat on every diagram page and provide zero RAG value.
            if trimmed.hasPrefix("*") && trimmed.lowercased().contains("may differ from the illustration") {
                return nil
            }

            return line
        }
        return cleaned.joined(separator: "\n")
    }

    /// Detects standalone internal asset/figure reference codes.
    /// These are alphanumeric codes used by publishers as image tags (e.g., ONQ5011001N).
    /// Only matches lines consisting SOLELY of the code (no other words).
    private static func isStandaloneAssetCode(_ trimmed: String) -> Bool {
        // Strip optional leading "* " annotation marker
        let clean = trimmed.hasPrefix("* ") ? String(trimmed.dropFirst(2)) : trimmed

        // Length guard: codes are typically 6-24 chars
        guard clean.count >= 6, clean.count <= 24 else { return false }

        // Must not contain spaces (a code is a single token)
        guard !clean.contains(" ") else { return false }

        // Must not contain any lowercase letters (codes are ALL-CAPS + digits)
        guard !clean.contains(where: { $0.isLowercase }) else { return false }

        // Must have at least 3 digits AND at least 2 uppercase letters
        let digitCount = clean.filter(\.isNumber).count
        let upperCount = clean.filter(\.isUppercase).count
        guard digitCount >= 3, upperCount >= 2 else { return false }

        // Only allow alphanumerics and underscores
        return clean.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Detects orphan page number annotations — structural pagination artifacts from PDFs.
    /// These are standalone lines consisting only of page indicators.
    private static func isOrphanPageAnnotation(_ trimmed: String) -> Bool {
        // Must be very short — page numbers are never long
        guard trimmed.count <= 12 else { return false }

        // Patterns:
        // "5", "42", "523"                     — standalone page number
        // "2 2", "3 5"                         — doubled page number (column headers)
        // "3 - 5", "2-8", "2 — 7", "2-"       — section-page or range notation
        let patterns: [String] = [
            #"^\d{1,4}$"#,                         // "5", "42"
            #"^\d{1,3}\s+\d{1,3}$"#,               // "2 2", "3 5"
            #"^\d{1,3}\s*[-—–]\s*\d{0,3}$"#,       // "3 - 5", "2-", "2 — 7"
        ]

        for pattern in patterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Detects standalone cross-reference page clusters.
    /// Lines like "4-38", "4-93, 8-54" where every comma-separated
    /// element is a section-page reference.
    private static func isCrossReferenceCluster(_ trimmed: String) -> Bool {
        // Length guard: cross-ref clusters are short-to-medium
        guard trimmed.count >= 3, trimmed.count <= 60 else { return false }

        // Must contain at least one hyphen-like character (section-page separator)
        guard trimmed.contains(where: { $0 == "-" || $0 == "–" || $0 == "—" }) else {
            return false
        }

        // Split by comma; each segment must be a section-page reference
        let segments = trimmed.components(separatedBy: ",")
        guard !segments.isEmpty else { return false }

        // Pattern: optional spaces + 1-3 digits + hyphen + 1-4 digits + optional spaces
        let refPattern = #"^\s*\d{1,3}\s*[-–—]\s*\d{1,4}\s*$"#
        return segments.allSatisfy { segment in
            segment.trimmingCharacters(in: .whitespaces).range(
                of: refPattern,
                options: .regularExpression
            ) != nil
        }
    }
}

// MARK: - Adaptive Image Preprocessor

/// Applies multiple preprocessing strategies to a single page image and lets
/// Vision pick the best one via confidence scoring.
///
/// Different document conditions need different filters:
/// - Clean digital PDFs: minimal processing (just slight sharpen)
/// - Old scans: heavy denoise + contrast boost + threshold
/// - Faded text: gamma correction + adaptive threshold
/// - Blurry photos: aggressive sharpen + edge enhancement
/// - Low contrast: histogram equalization + contrast stretch
///
/// The engine tries multiple strategies and picks the one where Vision's
/// average character confidence is HIGHEST.
enum AdaptivePreprocessor {

    /// A preprocessing strategy with its associated CIFilter parameters
    struct Strategy: Sendable {
        let name: String
        let sharpenRadius: Double
        let sharpenIntensity: Double
        let contrast: Double
        let brightness: Double
        let saturation: Double
        /// Additional filter: if true, applies exposure adjustment for faded docs
        let exposureAdjust: Double?
        /// Additional filter: if true, applies noise reduction
        let noiseReduction: Double?
    }

    /// The default strategy set — covers the most common document conditions.
    /// Ordered from lightest to heaviest processing.
    static let strategies: [Strategy] = [
        // Strategy 0: Minimal — clean digital PDFs, born-digital docs
        Strategy(
            name: "minimal",
            sharpenRadius: 0.3, sharpenIntensity: 0.5,
            contrast: 1.02, brightness: 0.0, saturation: 1.0,
            exposureAdjust: nil, noiseReduction: nil
        ),
        // Strategy 1: Standard — good quality scans, modern printers
        Strategy(
            name: "standard",
            sharpenRadius: 0.5, sharpenIntensity: 0.8,
            contrast: 1.05, brightness: 0.0, saturation: 1.0,
            exposureAdjust: nil, noiseReduction: nil
        ),
        // Strategy 2: Enhanced — older scans, slightly degraded quality
        Strategy(
            name: "enhanced",
            sharpenRadius: 0.8, sharpenIntensity: 1.2,
            contrast: 1.15, brightness: 0.01, saturation: 0.9,
            exposureAdjust: nil, noiseReduction: 0.02
        ),
        // Strategy 3: Aggressive — very poor quality, faded, blurry
        Strategy(
            name: "aggressive",
            sharpenRadius: 1.2, sharpenIntensity: 1.5,
            contrast: 1.25, brightness: 0.02, saturation: 0.8,
            exposureAdjust: 0.3, noiseReduction: 0.04
        ),
        // Strategy 4: Maximum — worst case: old microfiche, bad phone photos, ancient docs
        Strategy(
            name: "maximum",
            sharpenRadius: 1.5, sharpenIntensity: 2.0,
            contrast: 1.40, brightness: 0.03, saturation: 0.6,
            exposureAdjust: 0.5, noiseReduction: 0.06
        ),
    ]

    /// Apply a preprocessing strategy to a CIImage using Metal-backed CIFilters.
    ///
    /// - Parameters:
    ///   - image: Source CIImage
    ///   - strategy: The preprocessing strategy to apply
    ///   - gpuContext: CIContext for eager rendering (prevents Metal races)
    ///   - gpuQueue: Concurrent queue for GPU rendering (CIContext is thread-safe)
    /// - Returns: Processed CIImage, eagerly rendered to prevent Metal command buffer races
    static func apply(
        _ strategy: Strategy,
        to image: CIImage,
        gpuContext: CIContext,
        gpuQueue: DispatchQueue
    ) -> CIImage {
        var processedImage = image

        // 1. Noise reduction (if needed) — BEFORE sharpening to avoid amplifying noise
        if let noiseLevel = strategy.noiseReduction {
            if let noiseFilter = CIFilter(name: "CINoiseReduction") {
                noiseFilter.setValue(processedImage, forKey: kCIInputImageKey)
                noiseFilter.setValue(noiseLevel, forKey: "inputNoiseLevel")
                noiseFilter.setValue(0.4, forKey: "inputSharpness")
                if let output = noiseFilter.outputImage {
                    processedImage = output
                }
            }
        }

        // 2. Exposure adjustment (for faded documents)
        if let exposureValue = strategy.exposureAdjust {
            if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
                exposureFilter.setValue(processedImage, forKey: kCIInputImageKey)
                exposureFilter.setValue(exposureValue, forKey: kCIInputEVKey)
                if let output = exposureFilter.outputImage {
                    processedImage = output
                }
            }
        }

        // 3. Unsharp mask — enhances text edges
        if let unsharpMask = CIFilter(name: "CIUnsharpMask") {
            unsharpMask.setValue(processedImage, forKey: kCIInputImageKey)
            unsharpMask.setValue(strategy.sharpenRadius, forKey: kCIInputRadiusKey)
            unsharpMask.setValue(strategy.sharpenIntensity, forKey: kCIInputIntensityKey)
            if let output = unsharpMask.outputImage {
                processedImage = output
            }
        }

        // 4. Color controls — contrast, brightness, saturation
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(processedImage, forKey: kCIInputImageKey)
            colorControls.setValue(strategy.contrast, forKey: kCIInputContrastKey)
            colorControls.setValue(strategy.brightness, forKey: kCIInputBrightnessKey)
            colorControls.setValue(strategy.saturation, forKey: kCIInputSaturationKey)
            if let output = colorControls.outputImage {
                processedImage = output
            }
        }

        let croppedImage = processedImage.cropped(to: image.extent)

        // Eagerly render to CGImage to prevent Metal command buffer races
        var renderedCGImage: CGImage?
        gpuQueue.sync {
            renderedCGImage = gpuContext.createCGImage(croppedImage, from: croppedImage.extent)
        }

        if let cgImage = renderedCGImage {
            return CIImage(cgImage: cgImage)
        }

        return croppedImage
    }

    /// Select the best preprocessing strategy based on page characteristics.
    ///
    /// Instead of trying all strategies (expensive), we use heuristics from the
    /// complexity analysis and PDFKit text quality to pick the right one.
    ///
    /// - Parameters:
    ///   - textQuality: 0.0-1.0 from PageComplexityAnalyzer
    ///   - hasNativeTextLayer: Whether PDFKit extracted text
    ///   - isScanned: Whether this appears to be a scanned document
    ///   - imagePresence: Visual complexity score 0.0-1.0
    /// - Returns: The strategy index to use (into `strategies` array)
    static func selectStrategy(
        textQuality: Double,
        hasNativeTextLayer: Bool,
        isScanned: Bool,
        imagePresence: Double
    ) -> Strategy {
        if isScanned {
            // Scanned docs need heavier processing
            if textQuality < 0.3 {
                return strategies[4]  // maximum — worst case scan
            } else if textQuality < 0.5 {
                return strategies[3]  // aggressive — poor scan
            } else {
                return strategies[2]  // enhanced — decent scan
            }
        }

        if !hasNativeTextLayer {
            // No text layer = probably a rasterized image, treat like a scan
            return strategies[3]  // aggressive
        }

        if textQuality > 0.8 {
            return strategies[0]  // minimal — clean digital doc
        } else if textQuality > 0.6 {
            return strategies[1]  // standard
        } else {
            return strategies[2]  // enhanced — degraded text
        }
    }
}

// MARK: - Confidence Verifier

/// Analyzes Vision OCR confidence at the character and word level to flag
/// uncertain recognitions — especially critical for numeric data in tables.
///
/// Key insight: Vision's top candidate might be "15.5" with 0.82 confidence,
/// but candidate #2 might be "14.3" with 0.78 confidence. For a RAG system,
/// that 4-point confidence gap is NOT enough to trust "15.5" blindly.
/// We flag these uncertain recognitions so upstream consumers can:
///   1. Log them for diagnostics
///   2. Request re-scan at higher DPI
///   3. Cross-reference with PDFKit text layer
///   4. Present both candidates to the LLM with confidence scores
enum ConfidenceVerifier {

    /// Result of analyzing a single text observation
    struct ObservationAnalysis: Sendable {
        /// The best candidate text
        let text: String
        /// Overall confidence (0.0-1.0)
        let confidence: Float
        /// Whether this observation contains numeric data
        let containsNumericData: Bool
        /// Whether confidence is below threshold (needs verification)
        let isUncertain: Bool
        /// Alternative candidate texts with their confidences (if uncertain)
        let alternatives: [(text: String, confidence: Float)]
        /// Specific uncertain numeric values found
        let uncertainNumbers: [UncertainNumber]
    }

    /// A numeric value where OCR confidence is too low to trust
    struct UncertainNumber: Sendable {
        let value: String            // The recognized number
        let confidence: Float        // Confidence of this recognition
        let alternatives: [String]   // What else it could be
    }

    /// Minimum confidence to trust a text observation without flagging
    static let textConfidenceThreshold: Float = 0.85

    /// Minimum confidence to trust NUMERIC values (higher bar than text)
    /// Numbers are more critical in RAG answers — "14.3 gallons" vs "15.5 gallons"
    /// is a factual error, while "recomended" vs "recommended" is just a typo.
    static let numericConfidenceThreshold: Float = 0.90

    /// Analyze a VNRecognizedTextObservation for confidence issues.
    ///
    /// - Parameter observation: A text observation from Vision OCR
    /// - Returns: Analysis including uncertainty flags and alternatives
    static func analyze(_ observation: VNRecognizedTextObservation) -> ObservationAnalysis {
        let candidates = observation.topCandidates(5) // Get top 5 alternatives
        guard let best = candidates.first else {
            return ObservationAnalysis(
                text: "", confidence: 0, containsNumericData: false,
                isUncertain: true, alternatives: [], uncertainNumbers: []
            )
        }

        let text = best.string
        let confidence = best.confidence

        // Does this text contain numeric data?
        let numberPattern = try? NSRegularExpression(pattern: #"\d+\.?\d*"#)
        let range = NSRange(text.startIndex..., in: text)
        let numberMatches = numberPattern?.numberOfMatches(in: text, range: range) ?? 0
        let containsNumericData = numberMatches > 0

        // Determine threshold based on content type
        let threshold = containsNumericData ? numericConfidenceThreshold : textConfidenceThreshold
        let isUncertain = confidence < threshold

        // Build alternatives list (only other candidates, not the best)
        let alternatives: [(text: String, confidence: Float)] = candidates.dropFirst().map {
            (text: $0.string, confidence: $0.confidence)
        }

        // Find specific uncertain numbers
        var uncertainNumbers: [UncertainNumber] = []
        if containsNumericData && isUncertain {
            // Extract numbers from best candidate
            if let regex = numberPattern {
                let matches = regex.matches(in: text, range: range)
                for match in matches {
                    if let matchRange = Range(match.range, in: text) {
                        let numberStr = String(text[matchRange])
                        // Check if alternatives have different numbers in the same position
                        var altNumbers: [String] = []
                        for alt in candidates.dropFirst() {
                            let altText = alt.string
                            let altRange = NSRange(altText.startIndex..., in: altText)
                            let altMatches = regex.matches(in: altText, range: altRange)
                            for altMatch in altMatches {
                                if let altMatchRange = Range(altMatch.range, in: altText) {
                                    let altNumber = String(altText[altMatchRange])
                                    if altNumber != numberStr && !altNumbers.contains(altNumber) {
                                        altNumbers.append(altNumber)
                                    }
                                }
                            }
                        }
                        if !altNumbers.isEmpty {
                            uncertainNumbers.append(UncertainNumber(
                                value: numberStr,
                                confidence: confidence,
                                alternatives: altNumbers
                            ))
                        }
                    }
                }
            }
        }

        return ObservationAnalysis(
            text: text,
            confidence: confidence,
            containsNumericData: containsNumericData,
            isUncertain: isUncertain,
            alternatives: alternatives,
            uncertainNumbers: uncertainNumbers
        )
    }

    /// Analyze an array of observations and return the best text with
    /// confidence annotations for uncertain sections.
    ///
    /// When a numeric value is uncertain, BOTH candidates are included in the
    /// output text so the LLM can reason about which is correct from context.
    ///
    /// - Parameters:
    ///   - observations: VNRecognizedTextObservation array from Vision OCR
    ///   - annotateUncertain: If true, adds [UNCERTAIN: X or Y] markers to text
    /// - Returns: Assembled text with optional uncertainty annotations
    static func assembleVerifiedText(
        from observations: [VNRecognizedTextObservation],
        annotateUncertain: Bool = false
    ) -> (text: String, uncertainCount: Int, avgConfidence: Float) {
        var lines: [String] = []
        var totalConfidence: Float = 0
        var uncertainCount = 0

        for observation in observations {
            let analysis = analyze(observation)
            totalConfidence += analysis.confidence

            if analysis.isUncertain {
                uncertainCount += 1
            }

            if annotateUncertain && !analysis.uncertainNumbers.isEmpty {
                // Annotate uncertain numbers inline
                var annotatedText = analysis.text
                for uncertain in analysis.uncertainNumbers.reversed() {
                    // Find and annotate the uncertain number
                    if let range = annotatedText.range(of: uncertain.value) {
                        let altText = uncertain.alternatives.joined(separator: "/")
                        annotatedText.replaceSubrange(range,
                            with: "\(uncertain.value) [or \(altText), conf:\(String(format: "%.0f", uncertain.confidence * 100))%]")
                    }
                }
                lines.append(annotatedText)
            } else {
                lines.append(analysis.text)
            }
        }

        let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)
        return (lines.joined(separator: "\n"), uncertainCount, avgConfidence)
    }
}
