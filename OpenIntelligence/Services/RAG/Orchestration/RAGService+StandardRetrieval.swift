//
//  RAGService+StandardRetrieval.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Cross-Reference Resolution (Standard Pipeline)

    /// Lightweight cross-reference resolution for Standard mode.
    /// Scans retrieved chunks for patterns like "given in 'Section Name' on page X" and
    /// searches the full chunk pool for chunks from that section.
    ///
    /// Unlike the AgenticOrchestrator version (which runs a full retrieval pipeline per reference),
    /// this uses the already-loaded `allChunks` array for zero-latency lookups.
    /// This is safe because the Standard pipeline already has all chunks in memory.
    func resolveCrossReferencesStandard(
        chunks: [RetrievedChunk],
        query: String,
        allChunks: [DocumentChunk]
    ) async -> [RetrievedChunk] {
        // Cross-reference patterns common in technical documents
        let patterns: [(regex: NSRegularExpression, group: Int)] = {
            var result: [(NSRegularExpression, Int)] = []
            // QUOTED: "given in 'Recommended lubricants and capacities' on page 9-7"
            // NOTE: In raw strings #"..."#, \u{} is literal text, NOT a Unicode escape.
            // ICU regex uses \x{HHHH} for Unicode code points.
            if let r = try? NSRegularExpression(
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: .caseInsensitive)
            {
                result.append((r, 1))
            }
            // QUOTED: "see 'Section Name'" or "refer to 'Section Name'"
            if let r = try? NSRegularExpression(
                pattern:
                    #"(?:see|refer\s+to|check|consult)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
                options: .caseInsensitive)
            {
                result.append((r, 1))
            }
            // UNQUOTED: "given in Recommended lubricants and capacities on page 9-7"
            // Case-insensitive to handle OCR variations. Optional "the" article.
            if let r = try? NSRegularExpression(
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive)
            {
                result.append((r, 1))
            }
            // UNQUOTED: "see Recommended Lubricants on page X" or "refer to Section on page X"
            if let r = try? NSRegularExpression(
                pattern:
                    #"(?:see|refer\s+to|check|consult)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
                options: .caseInsensitive)
            {
                result.append((r, 1))
            }
            // CATCH-ALL UNQUOTED: "given in <any text> on page" — most permissive fallback
            // Handles OCR artifacts, mixed case, special characters in section names
            if let r = try? NSRegularExpression(
                pattern:
                    #"(?:given|found|listed|shown|described|specified|provided)\s+(?:in|under|at)\s+(?:the\s+)?(.{5,80})\s+on\s+page"#,
                options: .caseInsensitive)
            {
                result.append((r, 1))
            }
            return result
        }()

        // Page reference pattern — directly resolve "page X-Y" or "page X"
        let pagePattern = try? NSRegularExpression(
            pattern: #"(?:on|see|,)\s+page\s+(\d+[-–]\d+|\d+)"#,
            options: .caseInsensitive
        )

        var referencedSections: Set<String> = []
        var referencedPages: Set<Int> = []

        // Scan top chunks for cross-references
        for chunk in chunks.prefix(10) {
            let content = chunk.chunk.content
            let range = NSRange(content.startIndex..., in: content)

            for target in chunk.chunk.metadata.resolvedReferences {
                let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "page":
                    let pageParts = parts[1].components(separatedBy: CharacterSet(charactersIn: "-–"))
                    for pagePart in pageParts {
                        if let pageNum = Int(pagePart.trimmingCharacters(in: .whitespaces)) {
                            referencedPages.insert(pageNum)
                        }
                    }
                case "section", "chapter", "appendix":
                    referencedSections.insert(parts[1])
                default:
                    break
                }
            }

            // Check section name patterns
            for (regex, group) in patterns {
                let matches = regex.matches(in: content, range: range)
                for match in matches {
                    guard match.numberOfRanges > group,
                        let captureRange = Range(match.range(at: group), in: content)
                    else { continue }
                    let reference = String(content[captureRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if reference.count >= 5,
                        reference.range(of: #"^\d+[-–]?\d*$"#, options: .regularExpression) == nil
                    {
                        referencedSections.insert(reference)
                    }
                }
            }

            // Check page number patterns ("on page 9-7", "see page 42")
            if let pageRegex = pagePattern {
                let pageMatches = pageRegex.matches(in: content, range: range)
                for match in pageMatches {
                    guard match.numberOfRanges > 1,
                        let captureRange = Range(match.range(at: 1), in: content)
                    else { continue }
                    let pageStr = String(content[captureRange])
                    // Handle "9-7" format (chapter-page) — extract both numbers
                    let parts = pageStr.components(separatedBy: CharacterSet(charactersIn: "-–"))
                    for part in parts {
                        if let pageNum = Int(part.trimmingCharacters(in: .whitespaces)) {
                            referencedPages.insert(pageNum)
                        }
                    }
                }
            }
        }

        guard !referencedSections.isEmpty || !referencedPages.isEmpty else { return [] }

        Log.info(
            "[CrossRef-Std] Found \(referencedSections.count) section refs: [\(referencedSections.joined(separator: ", "))], \(referencedPages.count) page refs: \(referencedPages.sorted())",
            category: .retrieval)

        let existingIds = Set(chunks.map { $0.chunk.id })
        var additionalChunks: [RetrievedChunk] = []

        // Search the in-memory chunk pool for referenced sections
        // This is fast — just string matching against already-loaded chunks
        for section in referencedSections.prefix(3) {
            let sectionLower = section.lowercased()
            let sectionWords = Set(sectionLower.split(separator: " ").map(String.init).filter { $0.count > 3 })

            // Find chunks whose content mentions the section name OR whose section header matches
            var matchingChunks: [(chunk: DocumentChunk, score: Float)] = []

            for chunk in allChunks where !existingIds.contains(chunk.id) {
                let contentLower = chunk.content.lowercased()
                let isSpecificationHeavy = chunk.metadata.documentCategory?.isSpecificationHeavy ?? false

                // Medium match: content contains most of the section name words (handles line breaks/OCR)
                let matchingWords = sectionWords.filter { contentLower.contains($0) }
                if let score = EvidenceScoringPolicyService.crossReferenceSectionScore(
                    content: chunk.content,
                    structureType: chunk.metadata.structureType,
                    hasNumericData: chunk.metadata.hasNumericData,
                    isSpecificationHeavy: isSpecificationHeavy,
                    matchesFullSection: contentLower.contains(sectionLower),
                    matchingWordCount: matchingWords.count,
                    totalSectionWordCount: sectionWords.count
                ) {
                    matchingChunks.append((chunk, score))
                }
            }

            // Sort by score, take top 3 per section
            matchingChunks.sort { $0.score > $1.score }
            for (matchChunk, score) in matchingChunks.prefix(3) {
                let docName = getDocumentName(for: matchChunk.documentId)
                additionalChunks.append(
                    RetrievedChunk(
                        chunk: matchChunk,
                        similarityScore: score,
                        rank: 1,
                        sourceDocument: docName,
                        pageNumber: matchChunk.metadata.pageNumber
                    ))
            }

            Log.info(
                "[CrossRef-Std] '\(section.prefix(40))': found \(min(3, matchingChunks.count)) matching chunks",
                category: .retrieval)
        }

        // Phase 2: Page-number resolution — fetch chunks from referenced pages
        // This is the most robust approach: "page 9-7" → find chunks with pageNumber matching
        for pageNum in referencedPages.sorted().prefix(3) {
            let pageChunks = allChunks.filter { chunk in
                !existingIds.contains(chunk.id) && !additionalChunks.contains(where: { $0.chunk.id == chunk.id })
                    && chunk.metadata.pageNumber == pageNum
            }

            // Prioritize table/spec chunks from the referenced page
            let scored: [(chunk: DocumentChunk, score: Float)] = pageChunks.map { chunk in
                let queryWords = Set(query.lowercased().split(separator: " ").map(String.init).filter { $0.count > 3 })
                let contentLower = chunk.content.lowercased()
                let overlap = queryWords.filter { contentLower.contains($0) }.count
                let score = EvidenceScoringPolicyService.crossReferencePageScore(
                    content: chunk.content,
                    structureType: chunk.metadata.structureType,
                    hasNumericData: chunk.metadata.hasNumericData,
                    isSpecificationHeavy: chunk.metadata.documentCategory?.isSpecificationHeavy ?? false,
                    queryWordOverlap: overlap
                )
                return (chunk, score)
            }
            .sorted { $0.score > $1.score }

            for (matchChunk, score) in scored.prefix(3) {
                let docName = getDocumentName(for: matchChunk.documentId)
                additionalChunks.append(
                    RetrievedChunk(
                        chunk: matchChunk,
                        similarityScore: score,
                        rank: 1,
                        sourceDocument: docName,
                        pageNumber: matchChunk.metadata.pageNumber
                    ))
            }

            Log.info(
                "[CrossRef-Std] Page \(pageNum): found \(min(3, pageChunks.count))/\(pageChunks.count) chunks",
                category: .retrieval)
        }

        return additionalChunks
    }

    // MARK: - Spec Table Sniper

    /// "Spec Table Sniper" — targeted search for chunks containing query keywords + numeric data.
    /// Bypasses semantic similarity and reranker scoring entirely.
    ///
    /// The reranker has an inherent prose bias (~0.78 for prose vs ~0.30 for tables).
    /// This method searches ALL chunks for co-occurrence of discriminative query keywords
    /// and numeric/structured data — the signature of specification tables, dosage charts,
    /// legal statute numbers, financial figures, or any factual lookup target.
    ///
    /// Universal: works for technical manuals, medical papers, legal documents, research data.
    func specTableSniper(
        query: String,
        allChunks: [DocumentChunk],
        excludeIds: Set<UUID>
    ) -> [RetrievedChunk] {
        let queryLower = query.lowercased()

        // Extract meaningful query words (skip stopwords and short words)
        let precisionStopWords = Self.stopWords.union(["many", "much"])
        let queryWords =
            queryLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !precisionStopWords.contains($0) }
        let queryConcepts = buildSpecSearchConcepts(from: queryWords)

        // Need at least 2 meaningful keywords for targeted search
        guard queryConcepts.count >= 2 else { return [] }

        let conceptAliases = queryConcepts.map(\.aliases)

        var candidates: [(chunk: DocumentChunk, score: Float, matchCount: Int)] = []

        let passagesToScan = Self.passagesToScanForSpecSniper(allChunks: allChunks, excludeIds: excludeIds)

        for chunk in passagesToScan {
            guard
                let candidate = EvidenceScoringPolicyService.specSniperScore(
                    content: chunk.content,
                    structureType: chunk.metadata.structureType,
                    queryConceptAliases: conceptAliases
                )
            else {
                continue
            }

            candidates.append((chunk, candidate.score, candidate.matchCount))
        }

        // Sort by score, then by keyword match count for ties
        candidates.sort {
            if abs($0.score - $1.score) < 0.01 { return $0.matchCount > $1.matchCount }
            return $0.score > $1.score
        }

        // Take top 3 candidates
        return candidates.prefix(3).map { (chunk, score, _) in
            RetrievedChunk(
                chunk: chunk,
                similarityScore: score,
                rank: 1,
                sourceDocument: getDocumentName(for: chunk.documentId),
                pageNumber: chunk.metadata.pageNumber
            )
        }
    }

    /// The most passages the spec scan scores for one question.
    nonisolated static let specScanLimit = 20_000

    /// Which passages the spec scan scores: every passage not already retrieved, as before, for
    /// a library up to `specScanLimit`; for a larger one an even sample of that many, in order.
    /// The scan runs on the main actor for one kind of extractive question, and over 144,247
    /// passages it was seven times this. A sample can miss the one passage that holds a value,
    /// which the keyword search and the vector search still look for in full.
    static func passagesToScanForSpecSniper(
        allChunks: [DocumentChunk],
        excludeIds: Set<UUID>
    ) -> [DocumentChunk] {
        guard allChunks.count > specScanLimit else {
            return allChunks.filter { !excludeIds.contains($0.id) }
        }
        return evenSampleIndices(count: allChunks.count, limit: specScanLimit)
            .map { allChunks[$0] }
            .filter { !excludeIds.contains($0.id) }
    }

    private struct SpecSearchConcept {
        let aliases: [String]
    }

    private nonisolated func buildSpecSearchConcepts(from terms: [String]) -> [SpecSearchConcept] {
        var seen = Set<String>()
        var concepts: [SpecSearchConcept] = []

        for rawTerm in terms {
            let term = rawTerm.lowercased()
            guard seen.insert(term).inserted else { continue }

            var aliases = [term]
            switch term {
            case "gas":
                aliases.append(contentsOf: ["gasoline", "fuel"])
            case "gasoline":
                aliases.append(contentsOf: ["gas", "fuel"])
            case "fuel":
                aliases.append(contentsOf: ["gas", "gasoline"])
            case "gallon", "gallons", "gal":
                aliases.append(contentsOf: ["gal", "gallon", "gallons", "galon", "galons", "us gal"])
            case "liter", "liters", "litre", "litres":
                aliases.append(contentsOf: ["liter", "liters", "litre", "litres"])
            case "capacity", "capacities":
                aliases.append(contentsOf: ["capacity", "capacities", "volume"])
            case "hold", "holds", "holding":
                aliases.append(contentsOf: ["capacity", "capacities", "volume"])
            case "vehicle":
                aliases.append("car")
            case "car":
                aliases.append("vehicle")
            default:
                break
            }

            let uniqueAliases = Array(Set(aliases)).filter { $0.count > 1 }
            concepts.append(SpecSearchConcept(aliases: uniqueAliases))
        }

        return concepts
    }

    /// Demote chunks that merely contain cross-references to other sections.
    /// These chunks say "the answer is in Section X on page Y" but don't contain the actual answer.
    /// After the spec sniper has found actual data chunks, these pointer chunks should be deprioritized.
    func demoteCrossReferenceChunks(_ chunks: inout [RetrievedChunk]) {
        let crossRefVerbs = [
            "given in", "refer to", "found in", "listed in",
            "shown in", "specified in", "provided in", "described in",
        ]

        for i in chunks.indices {
            let contentLower = chunks[i].chunk.content.lowercased()
            // Only demote if chunk has BOTH a cross-ref verb AND a page reference
            let hasCrossRef = crossRefVerbs.contains { contentLower.contains($0) }
            let hasPageRef = contentLower.contains("page")
            if hasCrossRef && hasPageRef {
                // Halve the score so cross-ref chunks sort below actual data chunks
                let demotedScore = chunks[i].similarityScore * 0.5
                chunks[i] = RetrievedChunk(
                    chunk: chunks[i].chunk,
                    similarityScore: demotedScore,
                    rank: chunks[i].rank,
                    sourceDocument: chunks[i].sourceDocument,
                    pageNumber: chunks[i].pageNumber
                )
            }
        }
    }

    func countSpecPatterns(_ content: String) -> Int {
        EvidenceScoringPolicyService.specPatternCount(in: content)
    }

    // MARK: - Interrogative and Query Fallback Helpers

    func isInterrogativeChunk(_ chunk: DocumentChunk, query: String) -> Bool {
        if query.lowercased().contains("question") || query.lowercased().contains("example") {
            return false
        }
        let content = chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return false }

        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return false }

        var questionCount = 0
        for line in lines {
            let clean = line.replacingOccurrences(of: #"^[-*+•\d.]+\s+"#, with: "", options: .regularExpression)
            if clean.hasSuffix("?") {
                questionCount += 1
            }
        }

        let ratio = Double(questionCount) / Double(lines.count)
        if ratio >= 0.50 && lines.count > 1 {
            return true
        }

        return false
    }

    func cleanQueryForKeywordSearch(_ query: String) -> String {
        let stopwords: Set<String> = [
            "what", "whats", "which", "how", "much", "many", "does", "this", "that", "the",
            "a", "an", "is", "are", "was", "were", "do", "did", "can", "will", "i", "we", "you",
            "should", "would", "could", "for", "with", "from", "into", "have", "has", "me", "my",
            "been", "be", "it", "its", "of", "in", "on", "at", "to", "and", "or", "not", "no",
            "about", "tell", "explain", "describe", "show", "find", "get", "give", "list", "where",
            "when", "why", "there", "here", "also", "just", "some", "any", "all", "each", "every",
            "than", "then", "so", "if", "but", "up", "out", "by", "re", "please", "can you", "tell me",
        ]

        let words = query.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }

        return words.joined(separator: " ")
    }

    // MARK: - Section Metadata Boost

    /// Boost retrieval scores for chunks whose sectionTitle/sectionPath match query keywords.
    ///
    /// **Why this matters**: Embeddings for "Engine Oil: SAE 0W-20" and "Gear Oil: SAE 75W/85"
    /// have nearly identical vector similarity to "what oil does this car take".
    /// But `sectionTitle = "Engine Oil"` vs `sectionTitle = "Differential Gear Oil"` is
    /// the disambiguating signal. This method boosts chunks whose section context
    /// matches the query's discriminative keywords.
    ///
    /// - Parameters:
    ///   - chunks: Retrieved chunks from hybrid search
    ///   - query: The user's original query
    /// - Returns: Chunks with boosted scores, re-sorted. Nil if no boost applied.
    static func applyMetadataBoost(
        chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk]? {
        // Extract keywords from query (lowercase, no stopwords)
        // UNIVERSAL: Only pure English function words — no domain-specific terms
        let stopwords: Set<String> = [
            "what", "whats", "which", "how", "much", "many", "does", "this", "that", "the",
            "a", "an", "is", "are", "was", "were", "do", "did", "can", "will",
            "should", "would", "could", "for", "with", "from", "into", "have", "has",
            "been", "be", "it", "its", "my", "your", "our", "their", "of", "in", "on",
            "at", "to", "and", "or", "not", "no", "about", "tell", "me", "explain",
            "describe", "show", "find", "get", "give", "list", "where", "when", "why",
            "there", "here", "also", "just", "some", "any", "all", "each", "every",
            "than", "then", "so", "if", "but", "up", "out", "by", "re",
        ]
        let queryWords = query.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
        let queryKeywords = Set(queryWords)

        guard !queryKeywords.isEmpty else { return nil }

        // IDF-awareness: count how many chunks have each keyword in their section title
        // Keywords appearing in >30% of sections are non-discriminative for boosting
        var sectionKeywordFreq: [String: Int] = [:]
        let chunksWithSections = chunks.filter {
            !trustedSectionKeywordSet(title: $0.chunk.metadata.sectionTitle, path: $0.chunk.metadata.sectionPath)
                .isEmpty
        }
        for chunk in chunksWithSections {
            let titleWords = trustedSectionKeywordSet(title: chunk.chunk.metadata.sectionTitle, path: nil)
            for word in titleWords where queryKeywords.contains(word) {
                sectionKeywordFreq[word, default: 0] += 1
            }
        }
        let sectionCount = max(chunksWithSections.count, 1)
        let discriminativeKeywords = queryKeywords.filter { kw in
            let freq = sectionKeywordFreq[kw] ?? 0
            return Float(freq) / Float(sectionCount) < 0.30
        }

        // If ALL keywords are non-discriminative in sections, skip boosting entirely
        guard !discriminativeKeywords.isEmpty else {
            Log.debug("[MetadataBoost] All keywords non-discriminative in sections — skipping", category: .retrieval)
            return nil
        }

        // For multi-word queries, require at least 2 keyword matches (compound concept)
        // "smart mode" should NOT boost sections with just "smart" (Smart Cruise Control)
        // or just "mode" (Drive Mode) — only sections containing BOTH
        let requireMultiMatch = discriminativeKeywords.count >= 2

        var anyBoosted = false
        var boosted: [RetrievedChunk] = []

        for chunk in chunks {
            var boost: Float = 0.0

            // Check sectionTitle for keyword matches
            let titleSet = trustedSectionKeywordSet(title: chunk.chunk.metadata.sectionTitle, path: nil)
            if !titleSet.isEmpty {
                let titleMatches = discriminativeKeywords.intersection(titleSet)

                // For compound queries: require 2+ keyword matches in the section title
                // "smart mode" → only boost if title contains BOTH "smart" AND "mode"
                if requireMultiMatch && titleMatches.count < 2 {
                    // Single keyword match in a multi-keyword query — skip
                    // (prevents "Smart Cruise Control" from being boosted for "smart mode")
                } else {
                    // +0.08 per keyword match in sectionTitle
                    boost += Float(titleMatches.count) * 0.08
                }
            }

            // Check sectionPath (only if title didn't already match)
            if boost == 0 {
                let pathSet = trustedSectionKeywordSet(title: nil, path: chunk.chunk.metadata.sectionPath)
                let pathMatches = discriminativeKeywords.intersection(pathSet)

                if requireMultiMatch && pathMatches.count < 2 {
                    // Skip single-keyword path matches for compound queries
                } else {
                    boost += Float(pathMatches.count) * 0.04
                }
            }

            if boost > 0 {
                anyBoosted = true
                let cappedBoost = min(boost, 0.20)
                let newScore = min(chunk.similarityScore + cappedBoost, 1.0)

                boosted.append(
                    RetrievedChunk(
                        chunk: chunk.chunk,
                        similarityScore: newScore,
                        rank: chunk.rank,
                        sourceDocument: chunk.sourceDocument,
                        pageNumber: chunk.pageNumber
                    ))

                Log.debug(
                    "[MetadataBoost] Chunk \(chunk.chunk.metadata.chunkIndex) "
                        + "section='\(chunk.chunk.metadata.sectionTitle ?? "nil")' "
                        + "boosted \(String(format: "%.3f", chunk.similarityScore))→\(String(format: "%.3f", newScore))",
                    category: .retrieval
                )
            } else {
                boosted.append(chunk)
            }
        }

        guard anyBoosted else { return nil }

        // Re-sort by boosted scores (descending)
        boosted.sort { $0.similarityScore > $1.similarityScore }

        // Re-assign ranks
        return boosted.enumerated().map { idx, chunk in
            RetrievedChunk(
                chunk: chunk.chunk,
                similarityScore: chunk.similarityScore,
                rank: idx + 1,
                sourceDocument: chunk.sourceDocument,
                pageNumber: chunk.pageNumber
            )
        }
    }

    func applyContextualDefinitionBoost(
        chunks: [RetrievedChunk],
        query: String
    ) -> [RetrievedChunk]? {
        let queryTerms = Array(Set(extractQueryTerms(query)))
        guard !queryTerms.isEmpty else { return nil }

        var adjustedAny = false

        let boosted = chunks.map { candidate -> (chunk: RetrievedChunk, structured: Bool) in
            let content = candidate.chunk.contextText
            let lowerContent = content.lowercased()
            let metadata = candidate.chunk.metadata
            let sectionKeywords = Self.trustedSectionKeywordSet(
                title: metadata.sectionTitle,
                path: metadata.sectionPath
            )
            let sectionMatchCount = queryTerms.reduce(into: 0) { result, term in
                if sectionKeywords.contains(term) {
                    result += 1
                }
            }
            let contentMatchCount = queryTerms.reduce(into: 0) { result, term in
                if lowerContent.contains(term) {
                    result += 1
                }
            }

            let hasDefinitionCue =
                lowerContent.range(
                    of: #"\b(?:is|are|refers to|means|known as|called|defined as|first used in)\b"#,
                    options: [.regularExpression, .caseInsensitive]
                ) != nil || lowerContent.contains(" or ")
            let hasAliasCue = lowerContent.contains("(") && lowerContent.contains(")")
            let structuredText =
                looksTableLike(text: content, structureType: metadata.structureType)
                || lowerContent.contains("cell r")
                || lowerContent.contains("row ")
                || lowerContent.contains("column ")
                || content.contains("|")
            let paragraphLike = metadata.structureType == nil || metadata.structureType == "paragraph"

            var adjustedScore = candidate.similarityScore

            if metadata.abstractionLevel.isSummary {
                adjustedScore += 0.12
            }
            if metadata.chunkType == .prose || paragraphLike {
                adjustedScore += 0.05
            }
            if sectionMatchCount > 0 {
                adjustedScore += min(Float(sectionMatchCount) * 0.04, 0.12)
            }
            if contentMatchCount > 0 {
                adjustedScore += min(Float(contentMatchCount) * 0.03, 0.10)
            }
            if hasDefinitionCue {
                adjustedScore += 0.08
            }
            if hasAliasCue {
                adjustedScore += 0.04
            }

            if structuredText {
                adjustedScore -= 0.16
            }
            if metadata.chunkType == .tableStructural || metadata.chunkType == .tableSemantic {
                adjustedScore -= 0.10
            }
            if let tableTitle = metadata.tableTitle,
                !tableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                adjustedScore -= 0.06
            }
            if metadata.hasNumericData && !hasDefinitionCue && !metadata.abstractionLevel.isSummary {
                adjustedScore -= 0.03
            }

            adjustedScore = max(0.0, min(adjustedScore, 1.0))
            if abs(adjustedScore - candidate.similarityScore) >= 0.01 {
                adjustedAny = true
            }

            return (
                RetrievedChunk(
                    chunk: candidate.chunk,
                    similarityScore: adjustedScore,
                    rank: candidate.rank,
                    sourceDocument: candidate.sourceDocument,
                    pageNumber: candidate.pageNumber
                ),
                structuredText
            )
        }

        guard adjustedAny else { return nil }

        return
            boosted
            .sorted { lhs, rhs in
                if abs(lhs.chunk.similarityScore - rhs.chunk.similarityScore) >= 0.01 {
                    return lhs.chunk.similarityScore > rhs.chunk.similarityScore
                }
                if lhs.structured != rhs.structured {
                    return !lhs.structured
                }
                return lhs.chunk.rank < rhs.chunk.rank
            }
            .enumerated()
            .map { index, element in
                RetrievedChunk(
                    chunk: element.chunk.chunk,
                    similarityScore: element.chunk.similarityScore,
                    rank: index + 1,
                    sourceDocument: element.chunk.sourceDocument,
                    pageNumber: element.chunk.pageNumber
                )
            }
    }

    private static func trustedSectionKeywordSet(title: String?, path: [String]?) -> Set<String> {
        var keywords = Set<String>()

        if let titleKeywords = trustedSectionTokens(from: title) {
            keywords.formUnion(titleKeywords)
        }

        for component in path ?? [] {
            if let componentKeywords = trustedSectionTokens(from: component) {
                keywords.formUnion(componentKeywords)
            }
        }

        return keywords
    }

    nonisolated static func trustedSectionDisplayPath(_ rawPath: [String]?) -> [String]? {
        let cleaned = (rawPath ?? []).compactMap(trustedSectionDisplayLabel)
        guard !cleaned.isEmpty else { return nil }

        return cleaned.reduce(into: [String]()) { result, component in
            if result.last?.caseInsensitiveCompare(component) != .orderedSame {
                result.append(component)
            }
        }
    }

    nonisolated static func trustedSectionDisplayLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }

        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        return normalized
    }

    private static func trustedSectionTokens(from raw: String?) -> Set<String>? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }

        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        let tokens = normalized.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 2 }

        return tokens.isEmpty ? nil : Set(tokens)
    }

    // MARK: - Lexical Relevance Check

    /// Stop words to exclude from keyword matching
    nonisolated static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "through", "during", "before", "after", "above", "below", "between",
        "under", "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "each", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
        "too", "very", "just", "also", "now", "what", "which", "who", "whom",
        "this", "that", "these", "those", "am", "it", "its", "i", "me", "my",
        "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "he", "him", "his", "she", "her", "hers", "they", "them", "their",
    ]

    /// Check if query keywords appear in retrieved chunks (simple but effective)
    /// Returns 0.0-1.0 representing what fraction of query keywords appear in chunks
    func checkLexicalRelevance(query: String, chunks: [RetrievedChunk]) -> Float {
        let queryWords = extractQueryTerms(query)

        guard !queryWords.isEmpty else { return 0.5 }  // Can't evaluate, assume ok

        // Prefer the focused chunk span, but include parent context when available so
        // table rows and rescued snippets still contribute lexical evidence.
        let chunkText = chunks.prefix(5)
            .map { chunk -> String in
                let content = chunk.chunk.content.lowercased()
                guard let parent = chunk.chunk.parentContent?.lowercased(), !parent.isEmpty, parent != content else {
                    return content
                }
                return content + " " + parent
            }
            .joined(separator: " ")

        // Count how many query keywords appear in chunks
        var matchCount = 0
        for word in queryWords {
            if chunkText.contains(word) {
                matchCount += 1
            }
        }

        let relevance = Float(matchCount) / Float(queryWords.count)
        Log.debug(
            "[LexicalRelevance] \(matchCount)/\(queryWords.count) keywords found = \(String(format: "%.0f%%", relevance * 100))",
            category: .retrieval)

        return relevance
    }

    func ensureCloudConsentIfNeeded(
        service: LLMService,
        prompt: String,
        context: String?,
        sourceChunks: [DocumentChunk],
        allowPrivateCloudCompute: Bool,
        modelExecutionPlan: ModelExecutionPlan?
    ) async throws {
        guard modelExecutionPlan?.requiresCloudConsent == true else { return }
        guard let provider = cloudProvider(for: service) else { return }
        if !allowPrivateCloudCompute, provider == .applePCC {
            return  // User blocked PCC; don't prompt for consent we won't use
        }
        let record = makeTransmissionRecord(
            provider: provider,
            modelName: service.modelName,
            prompt: prompt,
            context: context,
            chunks: sourceChunks,
            modelExecutionPlan: modelExecutionPlan
        )

        // The stored choices are read again, so one changed in Settings while this question ran, or
        // made in a sheet another engine showed, counts here (5.7).
        refreshCloudConsentFromDefaults()

        if await hasTransientGrant(for: provider) {
            await recordTransmission(record, grant: "session")
            return
        }

        // A choice already made needs no sheet, so nothing has to come forward for it (5.7): Always
        // Allow sends and Don't Allow refuses, in front or not. Through 5.6 the check for the
        // foreground came first, so on iPhone a question from the background never used Always Allow.
        switch cloudConsent[provider] ?? .notDetermined {
        case .allowed:
            await recordTransmission(record, grant: "remembered")
            return
        case .denied:
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Cloud call blocked (denied)",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                ]
            )
            if VerificationJournal.isEnabled {
                let (relay, background) = await MainActor.run { (self.asksThroughRelay, Self.appIsInBackground) }
                VerificationJournal.record(
                    "consent.refused", ["reason": "remembered", "relay": "\(relay)", "background": "\(background)"])
            }
            throw RAGServiceError.cloudConsentDenied(provider: provider)
        case .notDetermined:
            break
        }

        // A question whose sheet already went unseen asks no more (5.7).
        if consentUnavailableForThisEngine {
            throw RAGServiceError.cloudConsentUnavailable(provider: provider)
        }

        #if canImport(UIKit)
            var isForegroundInteractive = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
            // An action's question can bring the app forward to ask, when the system lets it
            // (`bringAppForwardForConsent`, 5.7). When it cannot, the question goes on without
            // Private Cloud Compute, as before.
            if !isForegroundInteractive, let bringForward = bringAppForwardForConsent {
                do {
                    try await bringForward()
                    isForegroundInteractive = true
                    VerificationJournal.record("consent.broughtForward", .ok)
                } catch {
                    VerificationJournal.record(
                        "consent.broughtForward", .failed, ["error": String(describing: type(of: error))])
                    Log.info(
                        "[Consent] The app could not come forward to ask: \(error.localizedDescription)",
                        category: .pipeline)
                }
            }
            guard isForegroundInteractive else {
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Cloud consent unavailable outside foreground UI",
                    metadata: [
                        "provider": provider.shortName,
                        "planID": modelExecutionPlan?.id.uuidString ?? "unknown",
                    ]
                )
                throw RAGServiceError.cloudConsentUnavailable(provider: provider)
            }
        #elseif canImport(AppKit)
            // On the Mac the sheet shows in the app's window, which an action's question brings
            // forward first (5.7). An action's question asks only where it can be seen: when the app
            // cannot come forward it goes on without Private Cloud Compute, as on iPhone. The chat's
            // own engine asks in its window as before, in front or not.
            var inFront = NSApplication.shared.isActive
            if !inFront, let bringForward = bringAppForwardForConsent {
                do {
                    try await bringForward()
                    inFront = true
                    VerificationJournal.record("consent.broughtForward", .ok)
                } catch {
                    VerificationJournal.record(
                        "consent.broughtForward", .failed, ["error": String(describing: type(of: error))])
                    Log.info(
                        "[Consent] The app could not come forward to ask: \(error.localizedDescription)",
                        category: .pipeline)
                }
            }
            if asksThroughRelay, !inFront {
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Cloud consent unavailable outside foreground UI",
                    metadata: [
                        "provider": provider.shortName,
                        "planID": modelExecutionPlan?.id.uuidString ?? "unknown",
                    ]
                )
                throw RAGServiceError.cloudConsentUnavailable(provider: provider)
            }
        #endif

        let decision = await cloudConsentDecision(for: provider, record: record)

        switch decision {
        case .allowOnce:
            await rememberTransientGrant(provider)
            return
        case .allowAndRemember:
            return
        case .deny:
            // A sheet no window showed is not a refusal, and nothing was remembered.
            if consentRequestWentUnseen {
                consentRequestWentUnseen = false
                consentUnavailableForThisEngine = true
                throw RAGServiceError.cloudConsentUnavailable(provider: provider)
            }
            throw RAGServiceError.cloudConsentDenied(provider: provider)
        }
    }

    /// Internal so a test can ask it (`CloudConsentRelayTests`).
    @MainActor
    func cloudConsentDecision(
        for provider: CloudProvider,
        record: CloudTransmissionRecord
    ) async -> CloudConsentDecision {
        let state = cloudConsent[provider] ?? .notDetermined
        switch state {
        case .allowed:
            await recordTransmission(record, grant: "remembered")
            return .allowAndRemember
        case .denied:
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Cloud call blocked (denied)",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                ]
            )
            return .deny
        case .notDetermined:
            if let continuation = pendingConsentContinuation {
                continuation.resume(returning: .deny)
                pendingConsentContinuation = nil
            }
            pendingCloudConsent = record
            TelemetryCenter.emit(
                .system,
                title: "Cloud consent requested",
                metadata: [
                    "provider": provider.shortName,
                    "model": record.modelName,
                    "chars": "\(record.promptCharacterCount)",
                    "chunks": "\(record.contextChunkCount)",
                ]
            )
            return await withCheckedContinuation { continuation in
                pendingConsentContinuation = continuation
                // The chat shows the sheet for its own engine. For an engine an action built for its
                // question, the app's root view shows it through the relay (5.7). Posted after the
                // continuation is kept, because the relay can give a request up at once.
                if asksThroughRelay {
                    let id = record.id
                    CloudConsentRelay.shared.post(
                        record,
                        resolve: { [weak self] decision in await self?.resolveCloudConsent(decision: decision) },
                        abandon: { [weak self] in self?.abandonCloudConsentRequest(id) })
                }
            }
        }
    }

    @MainActor
    func recordTransmission(_ record: CloudTransmissionRecord, grant: String) async {
        VerificationJournal.record(
            "consent.authorized",
            ["grant": grant, "contextChars": "\(record.contextCharacterCount)", "chunks": "\(record.contextChunkCount)",
                "relay": "\(asksThroughRelay)", "background": "\(Self.appIsInBackground)"])
        pendingCloudConsent = nil
        lastCloudTransmission = record
        TelemetryCenter.emit(
            .system,
            title: "Cloud call authorized",
            metadata: [
                "provider": record.provider.shortName,
                "model": record.modelName,
                "chars": "\(record.promptCharacterCount)",
                "chunks": "\(record.contextChunkCount)",
                "bytes": "\(record.estimatedBytes)",
                "grant": grant,
                "planID": record.planID?.uuidString ?? "legacy",
                "routeReason": record.routeReason?.rawValue ?? "legacy",
            ]
        )
    }

    @MainActor
    private func hasTransientGrant(for provider: CloudProvider) async -> Bool {
        transientConsentGrants.contains(provider)
    }

    @MainActor
    private func rememberTransientGrant(_ provider: CloudProvider) async {
        transientConsentGrants.insert(provider)
    }

    /// Public wrapper for Deep Think consent checking
    /// Allows AgenticOrchestrator to trigger the same consent flow as Standard mode
    func ensureConsentForDeepThink(
        service: LLMService,
        prompt: String,
        context: String?,
        sourceChunks: [DocumentChunk],
        allowPrivateCloudCompute: Bool,
        modelExecutionPlan: ModelExecutionPlan?
    ) async throws {
        try await ensureCloudConsentIfNeeded(
            service: service,
            prompt: prompt,
            context: context,
            sourceChunks: sourceChunks,
            allowPrivateCloudCompute: allowPrivateCloudCompute,
            modelExecutionPlan: modelExecutionPlan
        )
    }

    /// Check if PCC is currently suppressed (exposed for Deep Think)
    @MainActor
    func isPCCSuppressedForDeepThink() -> Bool {
        isPCCSuppressed()
    }

    /// Check if there's a transient consent grant for PCC (exposed for Deep Think)
    @MainActor
    func hasTransientPCCGrant() -> Bool {
        transientConsentGrants.contains(.applePCC)
    }

    @MainActor
    func isPCCSuppressed(now: Date = Date()) -> Bool {
        guard let until = pccSuppressedUntil else { return false }
        if until > now { return true }
        pccSuppressedUntil = nil
        return false
    }

    @MainActor
    private func suppressPCC(for duration: TimeInterval, reason: String) {
        let until = Date().addingTimeInterval(duration)
        if let existing = pccSuppressedUntil, existing > until {
            return
        }
        pccSuppressedUntil = until
        Log.warning(
            "[RAG] PCC suppression enabled for \(Int(duration))s (\(reason))",
            category: .pipeline
        )
    }

    // MARK: - Contextual Retrieval Helper

    /// Build contextual prefix for Anthropic's Contextual Retrieval technique.
    /// Prepending document context to chunks BEFORE embedding improves retrieval by 35-67%.
    /// The prefix captures document-level semantics that help the embedding model understand
    /// what the chunk is about, even when the chunk content itself is generic.
    ///
    /// Example: A chunk "Long-press the Record Button" becomes embedded as
    /// "[PLAUD_NOTE_Manual.pdf] Long-press the Record Button" - the embedding now captures
    /// that this is about a PLAUD device, making queries like "button on this device" match better.
    func buildContextualPrefix(filename: String) -> String {
        // Clean filename for embedding (remove extension, clean underscores)
        let cleanName =
            filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let baseName = (cleanName as NSString).deletingPathExtension

        // Keep prefix concise - embeddings have limited context windows
        // Format: "[Document: Filename]" - simple but effective
        return "[\(baseName)]"
    }

    /// The fields `import.stage` writes (5.8), with the file's size, the process's memory footprint and, at the end
    /// of an import, how many documents the library already held. Sizes and counts only.
    nonisolated static func importStageFields(_ base: [String: String], url: URL, othersInLibrary: Int?) -> [String: String] {
        var fields = base
        guard VerificationJournal.isEnabled else { return fields }
        fields["bytes"] = "\(VerificationJournal.fileBytes(url))"
        fields["footprintMB"] = "\(VerificationJournal.footprintMB())"
        if let othersInLibrary { fields["othersInLibrary"] = "\(othersInLibrary)" }
        return fields
    }

    /// How many excerpt bullets still carry Markdown after tidying (5.8 journal): `**`, `__`, a backtick or a line that
    /// starts with `#`, past the bullet's own bold section label.
    nonisolated static func excerptMarkupCount(_ bullets: [String]) -> Int {
        bullets.filter { bullet in
            var body = Substring(bullet)
            if body.hasPrefix("• ") { body = body.dropFirst(2) }
            if body.hasPrefix("**"), let end = body.dropFirst(2).range(of: "**: ") { body = body[end.upperBound...] }
            if body.contains("**") || body.contains("__") || body.contains("`") { return true }
            return body.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        }.count
    }

    /// Clear deletion tombstones for documents the user is deliberately importing.
    ///
    /// `deleted_documents.json` was written in two places and cleared in none, so a
    /// document id that entered it stayed there permanently — and `WorkspaceSyncService`
    /// filters every tombstoned id out of the library on each sync. Combined with
    /// ingestion skipping a file it recognises as already imported, that formed a trap
    /// with no exit:
    ///
    ///   1. a document is deleted, or its queued item is discarded, and its id is
    ///      tombstoned
    ///   2. re-importing finds the surviving record and logs "Skipping already imported
    ///      document", creating no new record and no new id
    ///   3. the next sync applies the tombstone and erases the record
    ///   4. back to step 2, forever
    ///
    /// Deliberately importing a file is an un-delete. Reported as: import completes,
    /// wait, reopen, and the documents are gone again.
    /// Clean a raw chunk excerpt before showing it to a user verbatim.
    ///
    /// The extractive fallback prints retrieved chunk text directly, so any
    /// chunk-boundary artefact is shown as-is. Device log 2026-08-03 produced a
    /// bullet reading ", Inspection, and Testing" — a chunk that began partway
    /// through "Maintenance, Inspection, and Testing" — and another beginning
    /// "d Laparoscopes", a word cut in half.
    ///
    /// This trims the visible symptom. It does not fix the chunker, which is
    /// tracked separately; a chunk should not start mid-word in the first place.
    nonisolated static func tidiedExcerpt(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Drop leading punctuation and separators left by a mid-phrase cut.
        while let first = text.first, first.isPunctuation || first.isWhitespace {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return "" }

        // A lowercase opening token shorter than three characters is almost
        // always a severed word ("d Laparoscopes"). Drop it and start at the
        // next token. Longer lowercase openings are kept — plenty of legitimate
        // sentences start mid-clause and are still readable.
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        if let head = parts.first,
            head.count <= 2,
            let initial = head.first,
            initial.isLowercase,
            parts.count == 2
        {
            text = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    func clearDeletionTombstones(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let deletedDocsURL = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: deletedDocsURL.path),
            let data = try? Data(contentsOf: deletedDocsURL),
            var deletedDocIDs = try? JSONDecoder().decode([String].self, from: data)
        else { return }

        let removing = Set(ids.map(\.uuidString))
        let before = deletedDocIDs.count
        deletedDocIDs.removeAll { removing.contains($0) }
        guard deletedDocIDs.count != before else { return }

        if let encoded = try? JSONEncoder().encode(deletedDocIDs) {
            try? encoded.write(to: deletedDocsURL, options: .atomic)
            Log.info(
                "[RAGService] Cleared \(before - deletedDocIDs.count) deletion tombstone(s) for re-imported document(s)",
                category: .ingestion
            )
        }
    }

    func registerDeletedDocuments(_ docs: [Document]) {
        let deletedDocsURL = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        let fm = FileManager.default
        var deletedDocIDs: [String] = []
        if fm.fileExists(atPath: deletedDocsURL.path),
            let data = try? Data(contentsOf: deletedDocsURL)
        {
            deletedDocIDs = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        var changed = false
        for doc in docs {
            let idStr = doc.id.uuidString
            if !deletedDocIDs.contains(idStr) {
                deletedDocIDs.append(idStr)
                changed = true
            }
        }
        if changed {
            if let data = try? JSONEncoder().encode(deletedDocIDs) {
                try? data.write(to: deletedDocsURL, options: .atomic)
            }
        }
    }

}
