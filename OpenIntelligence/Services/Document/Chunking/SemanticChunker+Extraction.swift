//
//  SemanticChunker+Extraction.swift
//  OpenIntelligence
//
//  Part of SemanticChunker, moved from SemanticChunker.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import Accelerate

nonisolated extension SemanticChunker {
    // MARK: - Entity Extraction (Connective Tissue for GraphRAG)

    /// Extract named entities from chunk text using NLTagger.
    ///
    /// Uses multiple passes:
    /// 1. **Named Entity Recognition**: PersonalName, PlaceName, OrganizationName
    /// 2. **Technical Terms**: PascalCase identifiers (class names, APIs, frameworks)
    /// 3. **Capitalized Nouns**: Important domain terms that aren't standard NER entities
    ///
    /// These entities are used by:
    /// - `EntityIndexService` for cross-document correlation (Dict<Entity, [ChunkID]>)
    /// - `AgenticOrchestrator.executeGraphExpansion()` for 2-hop retrieval
    ///
    /// - Parameter text: The chunk text to extract entities from
    /// - Returns: Array of unique entity strings (deduplicated, sorted by first occurrence)
    func extractEntities(_ text: String) -> [String] {
        var entities: [String] = []
        var seen = Set<String>()

        // Pass 1: NLTagger Named Entity Recognition (reuse cached instance)
        cachedNERTagger.string = text

        cachedNERTagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard let tag = tag else { return true }

            // Accept persons, organizations, and places
            switch tag {
            case .personalName, .organizationName, .placeName:
                let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = entity.lowercased()
                if entity.count >= 2, entity.count <= 50, !seen.contains(key) {
                    seen.insert(key)
                    entities.append(entity)
                }
            default:
                break
            }
            return true
        }

        // Pass 2: Technical Terms - PascalCase identifiers (class names, APIs, frameworks)
        // Pattern: Word starting with capital followed by lowercase, then another capital
        // Examples: "URLSession", "CoreData", "SwiftUI", "NLTagger"
        let technicalPattern = #"\b([A-Z][a-z]+(?:[A-Z][a-z0-9]*)+)\b"#
        if let regex = try? NSRegularExpression(pattern: technicalPattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches.prefix(20) { // Limit to avoid runaway in code-heavy docs
                if let range = Range(match.range, in: text) {
                    let term = String(text[range])
                    let key = term.lowercased()
                    if term.count >= 3, term.count <= 40, !seen.contains(key) {
                        seen.insert(key)
                        entities.append(term)
                    }
                }
            }
        }

        // Pass 3: Capitalized Nouns (important domain terms not caught by NER)
        // Only add if they look like proper nouns (start with capital, not ALL CAPS)
        cachedLexicalTagger.string = text

        cachedLexicalTagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            guard tag == .noun else { return true }

            let word = String(text[range])
            // Check if it starts with capital but isn't all caps (proper noun heuristic)
            guard let first = word.first,
                  first.isUppercase,
                  word.count >= 3,
                  word.count <= 30,
                  word != word.uppercased() // Skip ALL CAPS
            else { return true }

            let key = word.lowercased()
            // Skip common English words that happen to start sentences
            let stopWords: Set<String> = ["the", "this", "that", "these", "those", "there", "then", "when", "where", "which", "what", "who", "how", "why"]
            if !seen.contains(key), !stopWords.contains(key) {
                seen.insert(key)
                entities.append(word)
            }
            return true
        }

        // Deterministic supplement: ALWAYS runs. Do not make this conditional.
        //
        // Passes 1-3 depend on Natural Language's linguistic assets, whose results
        // vary with process state. Observed on iOS 27: for "Tim Cook works at Apple
        // in Cupertino.", NER tags "Apple" as `.otherWord` (not an organization),
        // so "Apple" is only ever captured by the lexical-class pass as a
        // capitalized noun — and that pass does not classify it consistently. The
        // same chunk therefore yielded different entities between runs, which
        // propagates into the entity index and 2-hop graph expansion.
        //
        // Two narrower gates were tried and both failed: `entities.isEmpty` (never
        // fires on partial results) and "did each pass emit any tag" (a pass can
        // emit tags while still missing the token). Neither is sound, because a
        // present-but-differently-classified token is indistinguishable from an
        // absent one at this layer.
        //
        // Running unconditionally is what makes extraction deterministic. The cost
        // is bounded: the supplement only appends, dedupes against `seen`, and the
        // final `prefix(15)` means it can only contribute when passes 1-3 returned
        // fewer than 15 entities. On dense chunks it adds nothing.
        do {
            // Match consecutive capitalized words first (e.g. "Tim Cook", "Model Architecture")
            let multiWordPattern = #"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b"#
            if let regex = try? NSRegularExpression(pattern: multiWordPattern, options: []) {
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let term = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let key = term.lowercased()
                        if term.count >= 2, term.count <= 50, !seen.contains(key) {
                            seen.insert(key)
                            entities.append(term)
                        }
                    }
                }
            }

            // Match single capitalized words (e.g. "Apple", "Cupertino")
            let singleWordPattern = #"\b[A-Z][a-z]+\b"#
            if let regex = try? NSRegularExpression(pattern: singleWordPattern, options: []) {
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: nsRange)
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let term = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let key = term.lowercased()
                        // A capitalized word at the start of a sentence is not a name. Through 5.6
                        // "However" and its like became entities, because this supplement runs on every
                        // chunk (row "Sentence-opening words like However become entities"); 5.7 adds
                        // the words that open sentences and are never names on their own.
                        let stopWords: Set<String> = [
                            "the", "this", "that", "these", "those", "there", "then", "when", "where", "which", "what",
                            "who", "how", "why", "we", "our", "us", "i",
                            "however", "therefore", "moreover", "furthermore", "additionally", "meanwhile",
                            "nevertheless", "nonetheless", "consequently", "thus", "hence", "also", "instead",
                            "otherwise", "finally", "first", "second", "third", "next", "although", "because",
                            "since", "while", "if", "in", "on", "at", "for", "with", "as", "it", "its", "a", "an",
                            "and", "but", "or", "so", "yet", "after", "before", "each", "every", "some", "many",
                            "most", "such", "please", "note", "see",
                            "should", "would", "could", "shall", "must", "might", "can", "do", "does", "did",
                            "is", "are", "was", "were", "be", "has", "have", "had", "not", "no", "all", "any",
                            "both", "only", "here", "now", "you", "your", "he", "she", "they", "their", "his",
                            "her", "my", "from", "to", "of", "by", "about", "during", "until", "unless",
                            "whether", "once", "even", "still", "just", "always", "never", "often", "perhaps",
                            "indeed", "overall", "similarly", "specifically", "generally", "typically",
                            "currently", "recently", "later", "lastly", "today", "yes",
                        ]
                        if term.count >= 2, term.count <= 50, !seen.contains(key), !stopWords.contains(key) {
                            seen.insert(key)
                            entities.append(term)
                        }
                    }
                }
            }
        }

        // Return up to 15 entities per chunk (balance between richness and noise)
        return Array(entities.prefix(15))
    }

    // MARK: - Abbreviation Extraction (Anti-Hallucination)

    /// Extract abbreviation→expansion mappings from inline definitions in text.
    ///
    /// Academic papers, technical manuals, and medical documents consistently define
    /// abbreviations inline using patterns like:
    /// - "Emotional Dysregulation (ED)" → ED = Emotional Dysregulation
    /// - "ED: Emotional Dysregulation" → ED = Emotional Dysregulation
    /// - "ODD, Oppositional Defiant Disorder" → ODD = Oppositional Defiant Disorder
    /// - "ECU — Electronic Control Unit" → ECU = Electronic Control Unit
    ///
    /// These mappings are injected as a glossary into the LLM context, preventing the model
    /// from cross-contaminating abbreviations (e.g., expanding "ED" as "Oppositional Defiant
    /// Disorder" when the document defines it as "Emotional Dysregulation").
    ///
    /// Pre-compiled static regex patterns for performance (called once per chunk during ingestion).
    private static let abbreviationPatterns: [(regex: NSRegularExpression, abbrGroup: Int, expansionGroup: Int)] = {
        var patterns: [(NSRegularExpression, Int, Int)] = []

        // Pattern 1: "Full Name (ABBR)" — most common in academic/medical papers
        // Matches: "Emotional Dysregulation (ED)", "Oppositional Defiant Disorder (ODD)"
        // Requires: 2-6 uppercase letters in parens, preceded by 2-5 capitalized words
        if let r = try? NSRegularExpression(
            pattern: #"((?:[A-Z][a-zA-Z]+\s+){1,5}[A-Z][a-zA-Z]+)\s*\(([A-Z]{2,8})\)"#,
            options: []
        ) {
            patterns.append((r, 2, 1))  // group 2 = abbr, group 1 = expansion
        }

        // Pattern 2: "ABBR: Full Name" or "ABBR - Full Name" or "ABBR — Full Name"
        // Matches: "ECU: Electronic Control Unit", "OBD — On-Board Diagnostics"
        if let r = try? NSRegularExpression(
            pattern: #"\b([A-Z]{2,8})\s*[:\-—–]\s*((?:[A-Z][a-zA-Z]+\s+){1,5}[A-Z][a-zA-Z]+)"#,
            options: []
        ) {
            patterns.append((r, 1, 2))  // group 1 = abbr, group 2 = expansion
        }

        // Pattern 3: "ABBR, Full Name" (common in glossary/table sections)
        // Matches: "ODD, Oppositional Defiant Disorder"
        // Requires comma-separated with capitalized expansion words
        if let r = try? NSRegularExpression(
            pattern: #"\b([A-Z]{2,8}),\s+((?:[A-Z][a-zA-Z]+\s+){1,5}[A-Z][a-zA-Z]+)"#,
            options: []
        ) {
            patterns.append((r, 1, 2))
        }

        // Pattern 4: Glossary-style "ABBR  Full Name" (tab or multi-space separated)
        // Matches lines in glossary tables: "ODD     Oppositional Defiant Disorder"
        if let r = try? NSRegularExpression(
            pattern: #"^([A-Z]{2,8})\s{2,}((?:[A-Z][a-zA-Z]+\s+){1,5}[A-Z][a-zA-Z]+)"#,
            options: .anchorsMatchLines
        ) {
            patterns.append((r, 1, 2))
        }

        return patterns
    }()

    /// Extract abbreviation mappings from a chunk of text
    func extractAbbreviations(_ text: String) -> [String: String] {
        guard text.count >= 10 else { return [:] }

        var abbreviations: [String: String] = [:]
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for (regex, abbrGroup, expansionGroup) in Self.abbreviationPatterns {
            let matches = regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                guard match.numberOfRanges > max(abbrGroup, expansionGroup) else { continue }

                let abbrRange = match.range(at: abbrGroup)
                let expRange = match.range(at: expansionGroup)
                guard abbrRange.location != NSNotFound, expRange.location != NSNotFound else { continue }

                let abbr = nsText.substring(with: abbrRange).trimmingCharacters(in: .whitespaces)
                let expansion = nsText.substring(with: expRange).trimmingCharacters(in: .whitespaces)

                // Validate: abbreviation should be initials of expansion words
                // e.g., "ED" matches "Emotional Dysregulation" (E+D)
                let expansionWords = expansion.split(separator: " ").map { String($0) }
                let initials = String(expansionWords.compactMap { $0.first })

                // Accept if initials match, or if at least 60% of abbr chars are in initials
                // (handles cases like "ADHD" for "Attention Deficit Hyperactivity Disorder")
                let initialsUpper = initials.uppercased()
                let abbrUpper = abbr.uppercased()

                let matchingChars = abbrUpper.filter { initialsUpper.contains($0) }.count
                let matchRatio = Float(matchingChars) / Float(max(abbrUpper.count, 1))

                if abbrUpper == initialsUpper || matchRatio >= 0.6 {
                    // Don't overwrite existing entry (first definition wins — most authoritative)
                    if abbreviations[abbrUpper] == nil {
                        abbreviations[abbrUpper] = expansion
                    }
                }
            }
        }

        return abbreviations
    }

    /// The keywords with the highest counts, those with the same count in alphabetical order (5.7). A dictionary's
    /// order changes with every launch, and through 5.6 ties kept it, so the same passage could keep different keywords
    /// each time it was imported.
    static func topKeywords(_ counts: [String: Int], limit: Int) -> [String] {
        counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    /// Two lists in their order, with the second's repeats left out (5.7). Merging a small passage into the one before
    /// it took the union of their keywords and entities through a set, whose order changes with every launch.
    static func orderedUnion(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0).inserted }
    }

    /// Also extracts capitalized multi-word phrases (e.g., "Record Button", "Note Recording")
    /// ENHANCED: Also extracts specification values (SAE 0W-20, API SN, etc.) via SpecificationDetector
    func extractKeywords(_ text: String, topN: Int) -> [String] {
        // Prefer lemma-based counting to normalize inflections (reuse cached instance)
        cachedKeywordTagger.string = text

        var counts: [String: Int] = [:]

        cachedKeywordTagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { lemmaTag, range in
            // Determine POS for filtering
            let pos = cachedKeywordTagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            guard pos == .noun || pos == .verb || pos == .adjective else {
                return true
            }

            let token = String(text[range]).lowercased()
            let lemma = lemmaTag?.rawValue.lowercased() ?? token
            if lemma.count > 2 {
                counts[lemma, default: 0] += 1
            }
            return true
        }

        // Also extract capitalized multi-word phrases (domain-specific terms)
        // e.g., "Record Button", "Note Recording Mode", "Recording Mode Switch"
        let phrasePattern = #"\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b"#
        if let regex = try? NSRegularExpression(pattern: phrasePattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let phrase = String(text[range]).lowercased()
                    if phrase.count > 5, phrase.count < 40 {
                        counts[phrase, default: 0] += 2 // Boost multi-word phrases
                    }
                }
            }
        }

        // ENHANCED: Extract specification values (SAE 0W-20, API SN, etc.)
        // These are critical for technical document retrieval (automotive, engineering, medical)
        let specs = SpecificationDetector.detectSpecifications(in: text)
        for spec in specs {
            // Use uppercase for spec values (more recognizable)
            let specKey = spec.value.uppercased()
            counts[specKey, default: 0] += 3 // Boost specs even higher than phrases
        }

        // Return more keywords for richer corpus vocabulary (up to 2x requested).
        return Self.topKeywords(counts, limit: topN * 2)
    }

    /// Advance position with intelligent overlap that snaps to sentence boundaries.
    /// Instead of splitting overlap mid-sentence by raw word count, we find the
    /// nearest sentence boundary within the overlap region.
    ///
    /// The overlap is counted in the word tokenizer's words from 5.7, as the cap on a passage's size is (`maxSize`,
    /// `tokenWordCount`); the passage's target size is still counted in runs of text between spaces. Through 5.6 the
    /// overlap was counted in those runs too, so text with few spaces overlapped by several times the setting: in
    /// `id:7,name:alpha` each run is three or more of the tokenizer's words. Only the passage is tokenized, so the cost
    /// stays with the passage and not the whole text.
    func advancePosition(
        from start: String.Index,
        chunkEnd: String.Index,
        overlap: Int,
        in text: String
    ) -> String.Index {
        guard overlap > 0, start < chunkEnd else { return chunkEnd }
        // A passage that reaches the end of the text, or all of it but a short tail with no letter or digit (spaces,
        // punctuation, symbols), leaves nothing to cut. Stepping back for the overlap there made one more passage of the
        // overlap alone, wholly inside the one before it, at the end of nearly every document (5.7, measured
        // 2026-10-17). At most 64 characters are looked at, so this is no pass over the rest of the text.
        if text.index(chunkEnd, offsetBy: 64, limitedBy: text.endIndex) == nil,
            !text[chunkEnd...].contains(where: { $0.isLetter || $0.isNumber })
        {
            return text.endIndex
        }
        let passage = String(text[start..<chunkEnd])
        cachedWordTokenizer.string = passage
        let words = cachedWordTokenizer.tokens(for: passage.startIndex..<passage.endIndex)
        guard words.count > overlap else { return chunkEnd }

        // Move back by overlap words from chunk end
        let offset = passage.distance(from: passage.startIndex, to: words[words.count - overlap].lowerBound)
        guard let overlapStart = text.index(start, offsetBy: offset, limitedBy: chunkEnd) else { return chunkEnd }

        // Snap to nearest sentence boundary within ±30 chars of the overlap point
        // This ensures overlap regions start at clean sentence boundaries
        if let sentenceStart = findNearestSentenceStart(in: text, near: overlapStart, within: 30) {
            // Only use sentence boundary if it's still within the overlap region
            if sentenceStart > start && sentenceStart < chunkEnd {
                return sentenceStart
            }
        }
        return overlapStart > start ? overlapStart : chunkEnd
    }

    /// Print chunk statistics
    func printChunkStatistics(_ chunks: [EnhancedChunk]) {
        let avgWords = chunks.map { $0.metadata.wordCount }.reduce(0, +) / max(chunks.count, 1)
        let avgDensity = chunks.map { $0.metadata.semanticDensity }.reduce(0, +) / Float(max(chunks.count, 1))
        let withSections = chunks.filter { $0.metadata.sectionTitle != nil }.count
        let withNumeric = chunks.filter { $0.metadata.hasNumericData }.count

        Log.debug("[SemanticChunker] Avg words/chunk: \(avgWords)", category: .ingestion)
        Log.debug("[SemanticChunker] Avg semantic density: \(String(format: "%.2f", avgDensity))", category: .ingestion)
        Log.debug("[SemanticChunker] Chunks with sections: \(withSections)", category: .ingestion)
        Log.debug("[SemanticChunker] Chunks with numeric data: \(withNumeric)", category: .ingestion)
    }

    /// Create a single chunk for very small documents
    func createSingleChunk(
        _ text: String,
        documentId: UUID,
        pageNumbers: [Int: Range<String.Index>]? = nil,
        documentCategory: DocumentSemanticCategory? = nil
    ) -> EnhancedChunk {
        let wordCount = tokenWordCount(text)

        // Extract basic metadata
        let keywords = extractKeywords(text, topN: 5)
        let hasNumeric = text.range(of: #"\d+"#, options: .regularExpression) != nil
        let hasList = text.contains("•") || text.range(of: #"^\d+\."#, options: .regularExpression) != nil
        let entities = extractEntities(text)
        let resolvedReferences = GraphIndexService.extractReferenceTargets(from: text)
        let chunkType: ChunkSemanticType = isWarningLike(text: text, sectionTitle: nil) ? .warning : .prose

        let metadata = EnhancedChunk.ChunkMetadata(
            documentId: documentId,
            chunkIndex: 0,
            totalChunks: 1,
            pageNumber: nil,
            sectionTitle: nil,
            sectionPath: [],  // No section hierarchy for single-chunk docs
            wordCount: wordCount,
            characterCount: text.count,
            topKeywords: keywords,
            semanticDensity: 0.5, // Default for single chunk
            hasNumericData: hasNumeric,
            hasListStructure: hasList,
            startOffset: 0,
            endOffset: text.count,
            entities: entities,
            abbreviations: extractAbbreviations(text),
            documentCategory: documentCategory,
            chunkType: chunkType,
            tableTitle: nil,
            hasCrossReferences: !resolvedReferences.isEmpty,
            resolvedReferences: resolvedReferences
        )

        return EnhancedChunk(
            content: text,
            parentContent: text,
            metadata: metadata,
            embedding: nil // Will be added later by RAGService
        )
    }
}
