//
//  SpecificationExtractor.swift
//  OpenIntelligence
//
//  Extractive Question Answering for lookup-style queries.
//
//  DESIGN: For factual lookup queries ("What oil does this car take?"), we should
//  EXTRACT the answer span from the source text, not GENERATE it. This eliminates
//  hallucination risk - we can only return values that actually exist in the documents.
//
//  PIPELINE:
//  1. Detect all specification values in retrieved chunks using SpecificationDetector
//  2. Score each candidate by proximity to query keywords
//  3. Validate best candidate has high enough confidence
//  4. Return extracted span with citation, or escalate to LLM if uncertain
//
//  This implements AppleRAG Spec §6 "Extractive QA Span Model" using pattern-based
//  extraction (Phase 1) with future path to TinyBERT start/end heads (Phase 2).
//

import Foundation
import NaturalLanguage

// MARK: - Specification Extraction Result

/// Result of specification extraction - the answer span found in source text
struct SpecificationExtractionResult: Sendable {
    /// The extracted answer span (e.g., "0W-20", "4.5 liters")
    let answerSpan: String

    /// Confidence in this extraction (0-1)
    let confidence: Float

    /// The chunk containing this answer
    let sourceChunk: RetrievedChunk

    /// Context around the answer (for citation)
    let surroundingContext: String

    /// Type of specification (Grade, Measurement, Code, etc.)
    let specificationType: String

    /// The query keywords that this answer relates to
    let matchedKeywords: [String]

    /// Formatted citation string
    var citation: String {
        let source = sourceChunk.sourceDocument.isEmpty
            ? "Document"
            : URL(fileURLWithPath: sourceChunk.sourceDocument).lastPathComponent
        let page = sourceChunk.pageNumber.map { ", p.\($0)" } ?? ""
        return "[\(source)\(page)]"
    }

    /// Full answer with citation
    var formattedAnswer: String {
        // Include surrounding context for clarity
        if surroundingContext.count > answerSpan.count + 20 {
            return "\(surroundingContext) \(citation)"
        }
        return "\(answerSpan) \(citation)"
    }
}

/// Why specification extraction failed - guides escalation strategy
enum SpecificationExtractionFailure: Error, Sendable {
    /// No specification values found in chunks at all
    case noSpecsFound

    /// Found specs but none match the query keywords
    case noKeywordMatch

    /// Found matching specs but confidence too low (ambiguous)
    case lowConfidence(bestMatch: String, confidence: Float)

    /// Multiple equally-good candidates (need LLM to disambiguate)
    case ambiguousMultiple(candidates: [String])

    /// Query doesn't seem like a factual lookup
    case notLookupQuery
}

// MARK: - Specification Extractor

/// Service for extracting factual specification values directly from source text.
/// Eliminates hallucination by only returning values that exist in documents.
actor SpecificationExtractor {

    // MARK: - Configuration

    /// Minimum confidence to return an extraction (vs escalating to LLM)
    private let minConfidence: Float = 0.65

    /// Maximum context chars to include around the answer
    private let maxContextChars: Int = 150

    // MARK: - Public API

    /// Attempt to extract a factual answer from retrieved chunks.
    ///
    /// For queries like "What oil does this car take?", finds the specification
    /// value (e.g., "0W-20") directly in the source text.
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - chunks: Retrieved chunks to search
    ///   - answerIntent: The classified intent (should be .lookup or .tableLookup)
    /// - Returns: SpecificationExtractionResult if confident extraction found, failure otherwise
    func extract(
        query: String,
        chunks: [RetrievedChunk],
        answerIntent: AnswerIntent
    ) async -> Result<SpecificationExtractionResult, SpecificationExtractionFailure> {

        // Only handle lookup-style queries
        guard answerIntent == .lookup || answerIntent == .tableLookup else {
            return .failure(.notLookupQuery)
        }

        // Step 1: Extract query keywords (what are we looking for?)
        let queryKeywords = extractQueryKeywords(from: query)
        guard !queryKeywords.isEmpty else {
            Log.debug("[ExtractiveQA] No keywords extracted from query", category: .retrieval)
            return .failure(.noKeywordMatch)
        }

        Log.debug("[ExtractiveQA] Query keywords: \(queryKeywords)", category: .retrieval)

        // Step 2: Find all specification values in all chunks
        var allCandidates: [AnswerCandidate] = []

        for chunk in chunks {
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            let candidates = findCandidates(
                in: content,
                chunk: chunk,
                queryKeywords: queryKeywords
            )
            allCandidates.append(contentsOf: candidates)
        }

        guard !allCandidates.isEmpty else {
            Log.debug("[ExtractiveQA] No specification values found in chunks", category: .retrieval)
            return .failure(.noSpecsFound)
        }

        Log.debug("[ExtractiveQA] Found \(allCandidates.count) candidates", category: .retrieval)

        // Step 3: Score and rank candidates
        let scoredCandidates = allCandidates
            .map { ($0, scoreCandidate($0, queryKeywords: queryKeywords)) }
            .sorted { $0.1 > $1.1 }

        // Step 4: Check confidence thresholds
        guard let (bestCandidate, bestScore) = scoredCandidates.first else {
            return .failure(.noKeywordMatch)
        }

        // Log top candidates for debugging
        for (candidate, score) in scoredCandidates.prefix(3) {
            Log.debug(
                "[ExtractiveQA] Candidate: '\(candidate.value)' (\(candidate.category)) score=\(String(format: "%.2f", score))",
                category: .retrieval
            )
        }

        // Check for ambiguity - multiple high-scoring candidates
        let topCandidates = scoredCandidates.filter { $0.1 >= bestScore * 0.9 }
        if topCandidates.count > 1 {
            let uniqueValues = Set(topCandidates.map { $0.0.value })
            if uniqueValues.count > 1 {
                Log.debug("[ExtractiveQA] Ambiguous: \(uniqueValues.count) competing values", category: .retrieval)
                // If there are truly different values, we might need LLM help
                // But if they're the same value found in different places, that's confirmation
                return .failure(.ambiguousMultiple(candidates: Array(uniqueValues)))
            }
        }

        // Check minimum confidence
        if bestScore < minConfidence {
            Log.debug(
                "[ExtractiveQA] Low confidence: \(String(format: "%.2f", bestScore)) < \(minConfidence)",
                category: .retrieval
            )
            return .failure(.lowConfidence(bestMatch: bestCandidate.value, confidence: bestScore))
        }

        // Step 5: Build the extraction result
        let context = extractSurroundingContext(
            for: bestCandidate.value,
            in: bestCandidate.chunk.chunk.parentContent ?? bestCandidate.chunk.chunk.content
        )

        let result = SpecificationExtractionResult(
            answerSpan: bestCandidate.value,
            confidence: bestScore,
            sourceChunk: bestCandidate.chunk,
            surroundingContext: context,
            specificationType: bestCandidate.category,
            matchedKeywords: bestCandidate.matchedKeywords
        )

        Log.info(
            "[ExtractiveQA] ✓ Extracted '\(result.answerSpan)' (confidence: \(String(format: "%.0f", result.confidence * 100))%)",
            category: .retrieval
        )

        return .success(result)
    }

    // MARK: - Candidate Finding

    /// Internal candidate structure
    private struct AnswerCandidate {
        let value: String
        let category: String
        let chunk: RetrievedChunk
        let position: Int
        let keywordProximity: Int  // Words between value and nearest keyword
        let matchedKeywords: [String]
        let isInTable: Bool
        let isInList: Bool
    }

    /// Find all specification values in a chunk, with metadata for scoring
    private func findCandidates(
        in content: String,
        chunk: RetrievedChunk,
        queryKeywords: [String]
    ) -> [AnswerCandidate] {

        let contentLower = content.lowercased()
        let specs = SpecificationDetector.detectSpecifications(in: content)

        // Check if chunk is table/list structure
        let isTable = chunk.chunk.metadata.structureType == "table" ||
                      content.contains("|") && content.components(separatedBy: "|").count >= 4
        let isList = chunk.chunk.metadata.structureType == "list" ||
                     content.contains("•") || content.range(of: #"^\s*[-*]\s+"#, options: .regularExpression) != nil

        var candidates: [AnswerCandidate] = []

        for spec in specs {
            // Find position in text
            let position = content.distance(from: content.startIndex, to: spec.range.lowerBound)

            // Calculate keyword proximity
            var nearestKeywordDistance = Int.max
            var matchedKeywords: [String] = []

            for keyword in queryKeywords {
                // Find all occurrences of keyword
                var searchStart = contentLower.startIndex
                while let keywordRange = contentLower.range(of: keyword, range: searchStart..<contentLower.endIndex) {
                    let keywordPos = contentLower.distance(from: contentLower.startIndex, to: keywordRange.lowerBound)
                    let distance = abs(keywordPos - position)

                    // Keywords within 100 chars are "matched"
                    if distance < 100 {
                        if !matchedKeywords.contains(keyword) {
                            matchedKeywords.append(keyword)
                        }
                    }

                    nearestKeywordDistance = min(nearestKeywordDistance, distance)
                    searchStart = keywordRange.upperBound
                }
            }

            // Only include if there's at least some keyword proximity
            if nearestKeywordDistance < 500 {
                candidates.append(AnswerCandidate(
                    value: spec.value,
                    category: spec.category,
                    chunk: chunk,
                    position: position,
                    keywordProximity: nearestKeywordDistance,
                    matchedKeywords: matchedKeywords,
                    isInTable: isTable,
                    isInList: isList
                ))
            }
        }

        return candidates
    }

    // MARK: - Candidate Scoring

    /// Score a candidate answer based on multiple signals
    private func scoreCandidate(_ candidate: AnswerCandidate, queryKeywords: [String]) -> Float {
        var score: Float = 0.0

        // 1. Keyword proximity (most important) - 0 to 0.4
        // Closer = better. Within 50 chars = max score
        let proximityScore: Float
        if candidate.keywordProximity < 50 {
            proximityScore = 0.4
        } else if candidate.keywordProximity < 100 {
            proximityScore = 0.3
        } else if candidate.keywordProximity < 200 {
            proximityScore = 0.2
        } else {
            proximityScore = max(0, 0.15 - Float(candidate.keywordProximity - 200) / 2000)
        }
        score += proximityScore

        // 2. Number of matched keywords - 0 to 0.25
        let keywordMatchRatio = Float(candidate.matchedKeywords.count) / Float(max(1, queryKeywords.count))
        score += keywordMatchRatio * 0.25

        // 3. Structure bonus (tables/lists are specification-rich) - 0 to 0.15
        if candidate.isInTable {
            score += 0.15
        } else if candidate.isInList {
            score += 0.08
        }

        // 4. Chunk relevance (from retrieval) - 0 to 0.15
        score += min(0.15, candidate.chunk.similarityScore * 0.2)

        // 5. Specification type bonus - 0 to 0.1
        // Grades and measurements are more likely to be "the answer"
        switch candidate.category {
        case "Grade":
            score += 0.10  // Oil grades, material grades - very likely answer
        case "Measurement":
            score += 0.08  // Capacities, dimensions
        case "Code", "Standard":
            score += 0.06  // Spec codes
        default:
            score += 0.02
        }

        return min(1.0, score)
    }

    // MARK: - Query Analysis

    /// Extract meaningful keywords from the query
    private func extractQueryKeywords(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "what", "which", "who", "whom", "whose", "where", "when", "why", "how",
            "do", "does", "did", "will", "would", "could", "should", "can", "may",
            "this", "that", "these", "those", "it", "its",
            "for", "of", "in", "on", "at", "to", "from", "by", "with",
            "i", "me", "my", "you", "your", "we", "our", "they", "their",
            "kind", "type", "sort", "take", "use", "need", "require", "want"
        ]

        // Tokenize and filter
        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }

        // Add domain-specific expansions
        var keywords = tokens

        // Oil query expansion
        if tokens.contains("oil") {
            keywords.append(contentsOf: ["engine", "motor", "viscosity", "grade", "sae", "recommended"])
        }

        // Capacity query expansion
        if tokens.contains("capacity") || tokens.contains("much") || tokens.contains("many") {
            keywords.append(contentsOf: ["liters", "quarts", "gallons", "capacity", "volume"])
        }

        return Array(Set(keywords))
    }

    // MARK: - Context Extraction

    /// Extract surrounding context for the answer
    private func extractSurroundingContext(for value: String, in text: String) -> String {
        guard let valueRange = text.range(of: value) else {
            return value
        }

        // Find sentence containing the value
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        for sentence in sentences {
            if sentence.contains(value) {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count <= maxContextChars {
                    return trimmed
                }
                // Truncate around the value
                if let range = trimmed.range(of: value) {
                    let start = trimmed.index(range.lowerBound, offsetBy: -50, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
                    let end = trimmed.index(range.upperBound, offsetBy: 50, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                    return String(trimmed[start..<end])
                }
            }
        }

        // Fallback: window around value
        let startOffset = text.distance(from: text.startIndex, to: valueRange.lowerBound)
        let contextStart = max(0, startOffset - 50)
        let contextEnd = min(text.count, startOffset + value.count + 50)

        let startIdx = text.index(text.startIndex, offsetBy: contextStart)
        let endIdx = text.index(text.startIndex, offsetBy: contextEnd)

        return String(text[startIdx..<endIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
