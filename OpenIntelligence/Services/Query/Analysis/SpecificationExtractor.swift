//
//  SpecificationExtractor.swift
//  OpenIntelligence
//
//  Extractive Question Answering for lookup-style queries.
//
//  DESIGN: For factual lookup queries ("What type does this use?"), we should
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

    /// Optional matched label/key for key-value style lookups.
    let matchedLabel: String?

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
    /// ARCHITECTURE:
    /// 1. **Structured Table Lookup** (PREFERRED): Parse [Specifications] sections
    ///    that were extracted during ingestion. Direct key-value matching.
    /// 2. **Pattern-Based Extraction** (FALLBACK): Regex patterns for unstructured text.
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

        // Step 1: Parse query into entities and keywords (NER-inspired)
        let queryEntities = parseQueryEntities(from: query)
        guard !queryEntities.keywords.isEmpty else {
            Log.debug("[ExtractiveQA] No keywords extracted from query", category: .retrieval)
            return .failure(.noKeywordMatch)
        }

        Log.debug("[ExtractiveQA] Primary entities: \(queryEntities.primaryEntities)", category: .retrieval)
        Log.debug("[ExtractiveQA] Descriptive keywords: \(queryEntities.descriptiveKeywords.prefix(5))", category: .retrieval)

        if let explicitStateResult = extractFromExplicitStateStructures(
            chunks: chunks,
            query: query,
            queryEntities: queryEntities
        ) {
            Log.info("[ExtractiveQA] ✓ Explicit state structure lookup succeeded: '\(explicitStateResult.matchedLabel ?? "")' → '\(explicitStateResult.answerSpan)'", category: .retrieval)
            return .success(explicitStateResult)
        }

        if let stateResult = extractFromStateMappings(
            chunks: chunks,
            query: query,
            queryEntities: queryEntities
        ) {
            Log.info("[ExtractiveQA] ✓ State mapping lookup succeeded: '\(stateResult.matchedLabel ?? "")' → '\(stateResult.answerSpan)'", category: .retrieval)
            return .success(stateResult)
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // PHASE 1: STRUCTURED TABLE LOOKUP (PREFERRED)
        // ═══════════════════════════════════════════════════════════════════════════
        // Tables are parsed during ingestion into [Specifications] sections with
        // key-value pairs. This is the CORRECT way to do lookup - direct structured
        // data access, not regex pattern matching.
        //
        // Example table chunk content:
        //   [Specifications]
        //   Product: 1688 Camera Head with Integrated Coupler
        //   Reference: 1688-020-122
        //
        // Query "1688 camera head reference number" should match:
        //   - Entity "1688" appears in key or value
        //   - Keyword "reference" appears in key
        //   → Return value "1688-020-122"
        // ═══════════════════════════════════════════════════════════════════════════
        if let structuredResult = extractFromStructuredTables(
            chunks: chunks,
            queryEntities: queryEntities
        ) {
            Log.info("[ExtractiveQA] ✓ Structured table lookup succeeded: '\(structuredResult.answerSpan)'", category: .retrieval)
            return .success(structuredResult)
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // PHASE 2: PATTERN-BASED EXTRACTION (FALLBACK)
        // ═══════════════════════════════════════════════════════════════════════════
        // For chunks without structured [Specifications] sections, fall back to
        // regex pattern detection. Less accurate but handles unstructured text.

        // Step 2: Find all specification values in all chunks
        var allCandidates: [AnswerCandidate] = []

        for chunk in chunks {
            let content = extractionContent(for: chunk)
            let candidates = findCandidates(
                in: content,
                chunk: chunk,
                queryKeywords: queryEntities.keywords
            )
            allCandidates.append(contentsOf: candidates)
        }

        guard !allCandidates.isEmpty else {
            Log.debug("[ExtractiveQA] No specification values found in chunks", category: .retrieval)
            return .failure(.noSpecsFound)
        }

        Log.debug("[ExtractiveQA] Found \(allCandidates.count) candidates", category: .retrieval)

        // Step 3: Score and rank candidates with ENTITY AWARENESS
        let scoredCandidates = allCandidates
            .map { ($0, scoreCandidate($0, queryEntities: queryEntities)) }
            .sorted { $0.1 > $1.1 }

        // Step 3.5: OPTIMIZED — Filter out irrelevant categories before ambiguity check.
        // If we have Grade candidates, suppress Code candidates that don't match query context.
        let prefersMeasurementCandidates = isMeasurementStyleQuery(queryEntities)
            && scoredCandidates.contains { candidate, _ in
                candidate.category == "Measurement"
                    && measurementUnitMatchesQuery(candidate.value, queryEntities: queryEntities)
            }
        let hasGradeCandidate = scoredCandidates.contains { $0.0.category == "Grade" }
        let relevantCandidates: [(AnswerCandidate, Float)]
        if prefersMeasurementCandidates {
            relevantCandidates = scoredCandidates.filter { candidate, _ in
                candidate.category == "Measurement"
                    || measurementUnitMatchesQuery(candidate.value, queryEntities: queryEntities)
            }
        } else if hasGradeCandidate {
            // Prefer Grade/Measurement over generic Code when Grade exists
            relevantCandidates = scoredCandidates.filter { candidate, _ in
                candidate.category != "Code" || queryEntities.keywords.contains(where: { kw in
                    candidate.value.lowercased().contains(kw)
                })
            }
        } else {
            // OPTIMIZED: Even without Grade candidates, filter out Code candidates
            // that have ZERO matched keywords. Fuse codes like "HEATER3", "PUMP 20A"
            // appear near generic words like "fuse" but never near query-specific
            // keywords like "oil", "engine", "viscosity". Require at least 1 keyword
            // match within proximity to be considered relevant.
            let filtered = scoredCandidates.filter { candidate, _ in
                // Non-Code candidates always pass
                guard candidate.category == "Code" else { return true }
                // Code candidates must have at least 1 matched keyword
                return !candidate.matchedKeywords.isEmpty
            }
            // Only use filtered results if SOMETHING survived; otherwise fall through
            relevantCandidates = filtered.isEmpty ? scoredCandidates : filtered
        }

        // Step 4: Check confidence thresholds
        guard let (bestCandidate, bestScore) = relevantCandidates.first else {
            return .failure(.noKeywordMatch)
        }

        // Log top candidates for debugging
        for (candidate, score) in relevantCandidates.prefix(3) {
            Log.debug(
                "[ExtractiveQA] Candidate: '\(candidate.value)' (\(candidate.category)) score=\(String(format: "%.2f", score))",
                category: .retrieval
            )
        }

        // ========================================================================
        // ENTITY-CENTRIC DISAMBIGUATION (Key NLP principle)
        // If query has primary entities (product codes, model numbers), candidates
        // containing those entities are CLEARLY the answer - others are distractors.
        // ========================================================================
        let bestValueLower = bestCandidate.value.lowercased()

        // Check if best candidate contains a PRIMARY ENTITY (not just any keyword)
        // This is THE critical signal for product/model lookups
        let bestContainsPrimaryEntity = queryEntities.primaryEntities.contains { entity in
            entity.count >= 3 && bestValueLower.contains(entity)
        }

        // Check for ambiguity - multiple high-scoring candidates
        let topCandidates = relevantCandidates.filter { $0.1 >= bestScore * 0.9 }
        if topCandidates.count > 1 {
            let uniqueValues = Set(topCandidates.map { $0.0.value })
            if uniqueValues.count > 1 {
                // ENTITY-CENTRIC RESOLUTION: If the best candidate contains a primary entity
                // (e.g., "1688-210-080" contains entity "1688"), it wins over candidates
                // that don't contain the entity (e.g., "1488-020-125").
                if bestContainsPrimaryEntity {
                    let othersContainEntity = topCandidates.dropFirst().contains { candidate, _ in
                        let valueLower = candidate.value.lowercased()
                        return queryEntities.primaryEntities.contains { entity in
                            entity.count >= 3 && valueLower.contains(entity)
                        }
                    }
                    if !othersContainEntity {
                        Log.debug("[ExtractiveQA] Entity-match disambiguation: '\(bestCandidate.value)' contains entity '\(queryEntities.primaryEntities.first ?? "")'", category: .retrieval)
                        // Fall through to success - best candidate is clearly THE answer
                    } else {
                        // Multiple candidates contain the entity - true ambiguity
                        Log.debug("[ExtractiveQA] Ambiguous: multiple candidates contain entity", category: .retrieval)
                        return .failure(.ambiguousMultiple(candidates: Array(uniqueValues)))
                    }
                }
                // NO PRIMARY ENTITY in query - fall back to category-based disambiguation
                else if queryEntities.primaryEntities.isEmpty {
                    let topCategories = Set(topCandidates.map { $0.0.category })
                    if topCategories.count == 1 {
                        // Same category — likely variants of the same spec, pick the best
                        Log.debug("[ExtractiveQA] Same-category candidates (\(topCategories.first ?? "")): picking best", category: .retrieval)
                    } else {
                        Log.debug("[ExtractiveQA] Ambiguous: \(uniqueValues.count) competing values", category: .retrieval)
                        return .failure(.ambiguousMultiple(candidates: Array(uniqueValues)))
                    }
                }
                // Has entity but best doesn't contain it - other candidates might
                else {
                    // Check if ANY candidate contains the entity
                    let entityContainingCandidate = relevantCandidates.first { candidate, _ in
                        let valueLower = candidate.value.lowercased()
                        return queryEntities.primaryEntities.contains { entity in
                            entity.count >= 3 && valueLower.contains(entity)
                        }
                    }
                    if let (entityCandidate, entityScore) = entityContainingCandidate, entityScore >= minConfidence {
                        // Found a candidate containing the entity - use it even if not highest scored
                        Log.debug("[ExtractiveQA] Entity override: '\(entityCandidate.value)' contains entity, replacing best", category: .retrieval)
                        let context = extractSurroundingContext(
                            for: entityCandidate.value,
                            in: extractionContent(for: entityCandidate.chunk)
                        )
                        return .success(SpecificationExtractionResult(
                            answerSpan: entityCandidate.value,
                            matchedLabel: nil,
                            confidence: entityScore,
                            sourceChunk: entityCandidate.chunk,
                            surroundingContext: context,
                            specificationType: entityCandidate.category,
                            matchedKeywords: entityCandidate.matchedKeywords
                        ))
                    }
                    // No entity match found - true ambiguity
                    Log.debug("[ExtractiveQA] Ambiguous: \(uniqueValues.count) values, none contain entity", category: .retrieval)
                    return .failure(.ambiguousMultiple(candidates: Array(uniqueValues)))
                }
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
            in: extractionContent(for: bestCandidate.chunk)
        )

        let result = SpecificationExtractionResult(
            answerSpan: bestCandidate.value,
            matchedLabel: nil,
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

    /// Score a candidate answer based on multiple signals with ENTITY AWARENESS
    ///
    /// Key insight from NLP literature: When a query contains an entity identifier
    /// (product code, model number), candidates containing that entity should be
    /// scored disproportionately higher - they're likely THE answer, not just
    /// "a relevant candidate".
    private func scoreCandidate(_ candidate: AnswerCandidate, queryEntities: QueryEntities) -> Float {
        var score: Float = 0.0
        let measurementStyleQuery = isMeasurementStyleQuery(queryEntities)

        // 1. Keyword proximity (important but not primary) - 0 to 0.25
        // Closer = better. Within 50 chars = max score
        let proximityScore: Float
        if candidate.keywordProximity < 50 {
            proximityScore = 0.25
        } else if candidate.keywordProximity < 100 {
            proximityScore = 0.20
        } else if candidate.keywordProximity < 200 {
            proximityScore = 0.15
        } else {
            proximityScore = max(0, 0.10 - Float(candidate.keywordProximity - 200) / 3000)
        }
        score += proximityScore

        // 2. Number of matched keywords - 0 to 0.15
        let keywordMatchRatio = Float(candidate.matchedKeywords.count) / Float(max(1, queryEntities.keywords.count))
        score += keywordMatchRatio * 0.15

        // 3. Structure bonus (tables/lists are specification-rich) - 0 to 0.10
        if candidate.isInTable {
            score += 0.10
        } else if candidate.isInList {
            score += 0.05
        }

        // 4. Chunk relevance (from retrieval) - 0 to 0.10
        score += min(0.10, candidate.chunk.similarityScore * 0.15)

        // 5. Specification type bonus - 0 to 0.10
        switch candidate.category {
        case "Grade":
            score += 0.10  // Oil grades, material grades - very likely answer
        case "PartNumber":
            score += 0.08  // Part numbers - very relevant for product lookups
        case "Code", "Standard":
            score += 0.06  // Spec codes (API SN, ISO 9001)
        case "Measurement":
            // Penalize distance/time measurements that aren't capacities
            let value = candidate.value.lowercased()
            let isDistanceOrTime = value.contains("km") || value.contains("mile")
                || value.contains("hour") || value.hasSuffix(" m")
                || value.hasSuffix("\nm") || value.hasSuffix("\tm")
            score += isDistanceOrTime ? 0.01 : 0.05
        default:
            score += 0.02
        }

        if measurementStyleQuery {
            if candidate.category == "Measurement" {
                score += 0.12
                if measurementUnitMatchesQuery(candidate.value, queryEntities: queryEntities) {
                    score += 0.22
                }
                if candidate.matchedKeywords.contains(where: isMeasurementAnchorKeyword(_:)) {
                    score += 0.10
                }
            } else if looksLikeIndexReference(candidate.value) {
                score -= 0.20
            }
        } else if looksLikeIndexReference(candidate.value) {
            score -= 0.10
        }

        // ========================================================================
        // 6. PRIMARY ENTITY CONTAINMENT - THE KEY SIGNAL (0 to 0.50)
        // This is the most important scoring factor for entity-centric queries.
        //
        // When user asks "1688 camera head reference number", the answer
        // "1688-210-080" CONTAINS "1688" - this is not coincidence, it's
        // the definitive signal that this is THE answer.
        //
        // Other candidates like "1488-020-125" near "camera" are DISTRACTORS
        // and should be scored much lower.
        // ========================================================================
        let valueLower = candidate.value.lowercased()

        // Check against PRIMARY ENTITIES (product codes, model numbers)
        let containsPrimaryEntity = queryEntities.primaryEntities.contains { entity in
            entity.count >= 3 && valueLower.contains(entity)
        }

        if containsPrimaryEntity {
            score += 0.50  // MASSIVE boost - this is THE answer
            Log.debug("[ExtractiveQA] Entity match: '\(candidate.value)' contains primary entity", category: .retrieval)
        } else if !queryEntities.primaryEntities.isEmpty {
            // Query HAS an entity but this candidate doesn't contain it
            // This is likely a distractor - give it a penalty
            score -= 0.10
        }

        // 7. Secondary: descriptive keyword containment (weaker signal) - 0 to 0.10
        let containsDescriptiveKeyword = queryEntities.descriptiveKeywords.contains { keyword in
            keyword.count >= 4 && valueLower.contains(keyword)
        }
        if containsDescriptiveKeyword {
            score += 0.10
        }

        return max(0, min(1.0, score))
    }

    private func isMeasurementStyleQuery(_ queryEntities: QueryEntities) -> Bool {
        queryEntities.descriptiveKeywords.contains(where: isMeasurementKeyword(_:))
    }

    private func isMeasurementKeyword(_ keyword: String) -> Bool {
        let measurementKeywords: Set<String> = [
            "capacity", "volume", "gallons", "gallon", "liters", "liter", "quarts", "quart",
            "weight", "length", "width", "height", "pressure", "temperature", "amount", "size",
        ]
        return measurementKeywords.contains(keyword)
    }

    private func isMeasurementAnchorKeyword(_ keyword: String) -> Bool {
        let anchorKeywords: Set<String> = ["gas", "gasoline", "fuel", "tank", "capacity", "volume", "coolant", "oil"]
        return anchorKeywords.contains(keyword)
    }

    private func measurementUnitMatchesQuery(_ value: String, queryEntities: QueryEntities) -> Bool {
        let loweredValue = value.lowercased()

        if queryEntities.descriptiveKeywords.contains(where: { ["gallons", "gallon", "capacity", "volume", "liters", "liter", "quarts", "quart"].contains($0) }) {
            let liquidUnits = ["us gal", "gal", "gallon", "gallons", "l)", " l", "liter", "liters", "qt", "quarts", "quart"]
            if liquidUnits.contains(where: { loweredValue.contains($0) }) {
                return true
            }
        }

        if queryEntities.descriptiveKeywords.contains(where: { ["weight"].contains($0) }) {
            let weightUnits = ["kg", "lb", "lbs", "oz", "g "]
            if weightUnits.contains(where: { loweredValue.contains($0) }) {
                return true
            }
        }

        if queryEntities.descriptiveKeywords.contains(where: { ["length", "width", "height", "size"].contains($0) }) {
            let sizeUnits = ["mm", "cm", " m", "in", "inch", "ft"]
            if sizeUnits.contains(where: { loweredValue.contains($0) }) {
                return true
            }
        }

        if queryEntities.descriptiveKeywords.contains(where: { ["pressure"].contains($0) }) {
            let pressureUnits = ["psi", "kpa", "bar"]
            if pressureUnits.contains(where: { loweredValue.contains($0) }) {
                return true
            }
        }

        return false
    }

    private func looksLikeIndexReference(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains("\n") {
            return true
        }
        if normalized.range(of: #"\b\d+-\d+\b"#, options: .regularExpression) != nil {
            return true
        }
        if normalized.range(of: #"\bvolume\s+\d+-\d+\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private func extractionContent(for chunk: RetrievedChunk) -> String {
        let content = chunk.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = (chunk.chunk.parentContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !parent.isEmpty else { return content }
        guard !content.isEmpty else { return parent }

        if content.contains(parent) {
            return content
        }

        if let structureType = chunk.chunk.metadata.structureType,
           structureType == "table" || structureType == "list" {
            return content + "\n" + parent
        }

        if parent.count > content.count {
            return parent + "\n" + content
        }

        return content + "\n" + parent
    }

    // MARK: - Proximity-Based Extraction

    private func extractFromExplicitStateStructures(
        chunks: [RetrievedChunk],
        query: String,
        queryEntities: QueryEntities
    ) -> SpecificationExtractionResult? {
        let anchors = EvidenceScoringPolicyService.stateLookupAnchors(from: query)
        guard !anchors.colors.isEmpty || !anchors.states.isEmpty else { return nil }

        var bestMatch: (label: String, value: String, score: Float, chunk: RetrievedChunk)?

        for chunk in chunks {
            let content = extractionContent(for: chunk)

            for mapping in parseExplicitStateMappings(in: content) {
                let cleanedLabel = normalizeStateLabel(mapping.label)
                let cleanedValue = cleanupStateMappingValue(mapping.value)

                guard !isDegenerateStateMapping(label: cleanedLabel, value: cleanedValue) else {
                    continue
                }

                guard stateMappingSatisfiesAnchors(cleanedLabel, anchors: anchors) else {
                    continue
                }

                var score = mapping.score
                if chunk.chunk.metadata.structureType == "table" {
                    score += 0.03
                }
                if queryEntities.descriptiveKeywords.contains(where: { keyword in
                    keyword.count >= 4 && cleanedValue.lowercased().contains(keyword)
                }) {
                    score += 0.02
                }
                score += min(0.04, chunk.similarityScore * 0.05)

                if shouldPreferStateMapping(
                    candidate: (cleanedLabel, cleanedValue, min(0.99, score), chunk),
                    over: bestMatch
                ) {
                    bestMatch = (cleanedLabel, cleanedValue, min(0.99, score), chunk)
                }
            }
        }

        guard let match = bestMatch, match.score >= 0.90 else {
            return nil
        }

        return SpecificationExtractionResult(
            answerSpan: match.value,
            matchedLabel: match.label,
            confidence: match.score,
            sourceChunk: match.chunk,
            surroundingContext: "\(match.label) \(match.value)",
            specificationType: "StateMapping",
            matchedKeywords: queryEntities.keywords
        )
    }

    private func extractFromStateMappings(
        chunks: [RetrievedChunk],
        query: String,
        queryEntities: QueryEntities
    ) -> SpecificationExtractionResult? {
        let queryLabels = buildStateLookupLabels(from: query)
        guard !queryLabels.isEmpty else { return nil }
        let queryAnchors = EvidenceScoringPolicyService.stateLookupAnchors(from: query)

        var bestMatch: (label: String, value: String, score: Float, chunk: RetrievedChunk)?

        for chunk in chunks {
            let content = extractionContent(for: chunk)
            guard !isCellOnlyStateMappingSource(content) else {
                continue
            }
            let mappings = parseStateMappings(in: content)

            for mapping in mappings {
                guard !isDegenerateStateMapping(label: mapping.label, value: mapping.value) else {
                    continue
                }

                guard stateMappingSatisfiesAnchors(mapping.label, anchors: queryAnchors) else {
                    continue
                }

                let labelScore = scoreStateLabelMatch(mapping.label, queryLabels: queryLabels)
                guard labelScore >= 0.78 else { continue }

                var score = labelScore
                if chunk.chunk.metadata.structureType == "table" {
                    score += 0.05
                }
                if mapping.value.count >= 8 {
                    score += 0.03
                }
                if queryEntities.descriptiveKeywords.contains(where: { keyword in
                    let loweredValue = mapping.value.lowercased()
                    return keyword.count >= 4 && loweredValue.contains(keyword)
                }) {
                    score += 0.03
                }
                score += min(0.04, chunk.similarityScore * 0.05)

                if shouldPreferStateMapping(
                    candidate: (mapping.label, mapping.value, min(0.98, score), chunk),
                    over: bestMatch
                ) {
                    bestMatch = (mapping.label, mapping.value, min(0.98, score), chunk)
                }
            }
        }

        guard let match = bestMatch, match.score >= 0.82 else {
            return nil
        }

        return SpecificationExtractionResult(
            answerSpan: match.value,
            matchedLabel: match.label,
            confidence: match.score,
            sourceChunk: match.chunk,
            surroundingContext: "\(match.label) \(match.value)",
            specificationType: "StateMapping",
            matchedKeywords: queryEntities.keywords
        )
    }

    private func isDegenerateStateMapping(label: String, value: String) -> Bool {
        let normalizedLabel = normalizeStatePhrase(label)
        let normalizedValue = normalizeStatePhrase(value)

        guard !normalizedValue.isEmpty else { return true }
        if normalizedValue == normalizedLabel { return true }
        if isStateLabel(value) { return true }
        if isNoisyStateMappingValue(value) { return true }

        return false
    }

    private func parseExplicitStateMappings(in content: String) -> [(label: String, value: String, score: Float)] {
        var results: [(label: String, value: String, score: Float)] = []
        var seen = Set<String>()

        func appendMapping(label: String, value: String, score: Float) {
            let cleanedLabel = normalizeStateLabel(label)
            let cleanedValue = cleanupStateMappingValue(value)
            guard !cleanedLabel.isEmpty, !cleanedValue.isEmpty else { return }
            let dedupeKey = "\(cleanedLabel.lowercased())::\(cleanedValue.lowercased())"
            guard seen.insert(dedupeKey).inserted else { return }
            results.append((cleanedLabel, cleanedValue, score))
        }

        if let summaryRegex = try? NSRegularExpression(
            pattern: #"^The\s+((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z][A-Za-z-]*(?:\s*\([^)]*\))?)\s+is\s+(.+?)(?:\.|$)"#,
            options: [.caseInsensitive]
        ) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let nsLine = trimmed as NSString
                guard let match = summaryRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsLine.length)),
                      match.numberOfRanges >= 3 else {
                    continue
                }

                appendMapping(
                    label: nsLine.substring(with: match.range(at: 1)),
                    value: nsLine.substring(with: match.range(at: 2)),
                    score: 0.95
                )
            }
        }

        let flattened = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let rowRegex = try? NSRegularExpression(
            pattern: #"Row\s+\d+:\s*(?:Row\s+\d+\s*\|\s*)?Color of Light=([^;]+);\s*PLAUD Status=([^\r\n]+?)(?=\s+Row\s+\d+:|$)"#,
            options: [.caseInsensitive]
        ) {
            let nsContent = flattened as NSString
            let matches = rowRegex.matches(in: flattened, range: NSRange(location: 0, length: nsContent.length))
            for match in matches where match.numberOfRanges >= 3 {
                appendMapping(
                    label: nsContent.substring(with: match.range(at: 1)),
                    value: nsContent.substring(with: match.range(at: 2)),
                    score: 0.93
                )
            }
        }

        if let tableRegex = try? NSRegularExpression(
            pattern: #"\|\s*((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z][A-Za-z-]*(?:\s*\([^)]*\))?)\s*\|\s*([^|]+?)\s*\|"#,
            options: [.caseInsensitive]
        ) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.contains("|") else { continue }
                let nsLine = trimmed as NSString
                let matches = tableRegex.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length))
                for match in matches where match.numberOfRanges >= 3 {
                    appendMapping(
                        label: nsLine.substring(with: match.range(at: 1)),
                        value: nsLine.substring(with: match.range(at: 2)),
                        score: 0.91
                    )
                }
            }
        }

        return results
    }

    private func stateMappingSatisfiesAnchors(
        _ label: String,
        anchors: (colors: [String], states: [String])
    ) -> Bool {
        let lowerLabel = normalizeStatePhrase(label)

        if !anchors.colors.isEmpty,
           !anchors.colors.allSatisfy({ lowerLabel.contains($0) }) {
            return false
        }

        if !anchors.states.isEmpty,
           !anchors.states.contains(where: { lowerLabel.contains($0) }) {
            return false
        }

        return true
    }

    private func isCellOnlyStateMappingSource(_ content: String) -> Bool {
        let lowerContent = content.lowercased()
        let hasCellStructure = lowerContent.contains("[cells]") || lowerContent.contains("cell r")
        let hasRowStructure = lowerContent.contains("[rows]") || lowerContent.contains("row 1:")
        return hasCellStructure && !hasRowStructure
    }

    private func isNoisyStateMappingValue(_ value: String) -> Bool {
        let lowerValue = value.lowercased()
        let artifactMarkers = [
            "cell r",
            "[plaud status]",
            "[color of light]",
            "column 1",
            "column 2",
            "row 1:",
            "row 2:",
            "row 3:"
        ]

        return artifactMarkers.contains(where: { lowerValue.contains($0) })
    }

    private func shouldPreferStateMapping(
        candidate: (label: String, value: String, score: Float, chunk: RetrievedChunk),
        over best: (label: String, value: String, score: Float, chunk: RetrievedChunk)?
    ) -> Bool {
        guard let best else { return true }

        if candidate.score > best.score + 0.01 {
            return true
        }
        if best.score > candidate.score + 0.01 {
            return false
        }

        let candidateIsTable = candidate.chunk.chunk.metadata.structureType == "table"
        let bestIsTable = best.chunk.chunk.metadata.structureType == "table"
        if candidateIsTable != bestIsTable {
            return candidateIsTable
        }

        let candidateValue = normalizeStatePhrase(candidate.value)
        let bestValue = normalizeStatePhrase(best.value)
        let candidateEchoesLabel = candidateValue == normalizeStatePhrase(candidate.label)
        let bestEchoesLabel = bestValue == normalizeStatePhrase(best.label)
        if candidateEchoesLabel != bestEchoesLabel {
            return !candidateEchoesLabel
        }

        if candidate.value.count != best.value.count {
            return candidate.value.count > best.value.count
        }

        if candidate.chunk.similarityScore != best.chunk.similarityScore {
            return candidate.chunk.similarityScore > best.chunk.similarityScore
        }

        return false
    }

    private func buildStateLookupLabels(from query: String) -> [String] {
        let pattern = #"\b(flash(?:ing)?|blink(?:ing)?|solid|steady|puls(?:e|ing)|rapid|slow)\s+([a-z-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let nsQuery = query as NSString
        let matches = regex.matches(in: query, range: NSRange(location: 0, length: nsQuery.length))
        let labels = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 3 else { return nil }
            let state = canonicalStateToken(nsQuery.substring(with: match.range(at: 1)))
            let color = nsQuery.substring(with: match.range(at: 2)).capitalized
            return "\(state) \(color)"
        }

        var normalizedLabels = Set(labels)
        let lowerQuery = query.lowercased()
        let indicatorTerms = ["indicator", "light", "lights", "led", "status", "signal"]
        let colorPattern = #"\b(red|green|blue|yellow|amber|orange|purple|white|cyan(?:-blue)?|cyan|magenta)\b"#

        if labels.isEmpty,
           indicatorTerms.contains(where: { lowerQuery.contains($0) }),
           let colorRegex = try? NSRegularExpression(pattern: colorPattern, options: .caseInsensitive) {
            let colorMatches = colorRegex.matches(in: query, range: NSRange(location: 0, length: nsQuery.length))
            for match in colorMatches {
                guard let colorRange = Range(match.range(at: 1), in: query) else { continue }
                normalizedLabels.insert(String(query[colorRange]).capitalized)
            }
        }

        return Array(normalizedLabels)
    }

    private func canonicalStateToken(_ token: String) -> String {
        let lower = token.lowercased()
        if lower.hasPrefix("flash") { return "Flashing" }
        if lower.hasPrefix("blink") { return "Blinking" }
        if lower.hasPrefix("puls") { return "Pulsing" }
        if lower == "solid" { return "Solid" }
        if lower == "steady" { return "Steady" }
        if lower == "rapid" { return "Rapid" }
        if lower == "slow" { return "Slow" }
        return token.capitalized
    }

    private func scoreStateLabelMatch(_ label: String, queryLabels: [String]) -> Float {
        let normalizedLabel = normalizeStatePhrase(label)
        let labelState = explicitStateToken(in: normalizedLabel)
        var best: Float = 0

        for queryLabel in queryLabels {
            let normalizedQuery = normalizeStatePhrase(queryLabel)
            let queryState = explicitStateToken(in: normalizedQuery)

            if let queryState, let labelState, queryState != labelState {
                continue
            }

            if normalizedLabel == normalizedQuery {
                best = max(best, 0.95)
                continue
            }

            if normalizedLabel.contains(normalizedQuery) || normalizedQuery.contains(normalizedLabel) {
                best = max(best, 0.88)
                continue
            }

            let labelTokens = Set(normalizedLabel.split(separator: " ").map(String.init))
            let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
            let overlap = labelTokens.intersection(queryTokens)
            let coverage = Float(overlap.count) / Float(max(1, queryTokens.count))
            if coverage >= 1.0 {
                best = max(best, 0.90)
            } else if coverage >= 0.5 {
                if queryState != nil {
                    best = max(best, 0.45)
                } else {
                    best = max(best, 0.80)
                }
            }
        }

        return best
    }

    private func explicitStateToken(in normalizedPhrase: String) -> String? {
        let stateTokens: Set<String> = [
            "flashing", "solid", "blinking", "steady", "pulsing", "rapid", "slow"
        ]

        guard let firstToken = normalizedPhrase.split(separator: " ").first.map(String.init) else {
            return nil
        }

        return stateTokens.contains(firstToken) ? firstToken : nil
    }

    private func normalizeStatePhrase(_ phrase: String) -> String {
        phrase
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bflash\b"#, with: "flashing", options: .regularExpression)
            .replacingOccurrences(of: #"\bblink\b"#, with: "blinking", options: .regularExpression)
            .replacingOccurrences(of: #"\bpulse\b"#, with: "pulsing", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseStateMappings(in content: String) -> [(label: String, value: String)] {
        let flattened = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pattern = #"((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Z][A-Za-z-]+)\s+(.+?)(?=\s+(?:(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Z][A-Za-z-]+)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsContent = flattened as NSString
        let matches = regex.matches(in: flattened, range: NSRange(location: 0, length: nsContent.length))

        var results: [(label: String, value: String)] = []
        var seen = Set<String>()

        func appendResult(label: String, value: String) {
            let cleanedLabel = normalizeStateLabel(label)
            let cleanedValue = cleanupStateMappingValue(value)
            guard !cleanedLabel.isEmpty, !cleanedValue.isEmpty else { return }
            guard !isDegenerateStateMapping(label: cleanedLabel, value: cleanedValue) else { return }
            let dedupeKey = "\(cleanedLabel.lowercased())::\(cleanedValue.lowercased())"
            if seen.insert(dedupeKey).inserted {
                results.append((cleanedLabel, cleanedValue))
            }
        }

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let label = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = nsContent.substring(with: match.range(at: 2))
            appendResult(label: label, value: rawValue)
        }

        for mapping in parseDirectStateMappingLines(in: content) {
            appendResult(label: mapping.label, value: mapping.value)
        }

        for mapping in parseParallelStateMappings(in: content) {
            appendResult(label: mapping.label, value: mapping.value)
        }

        return results
    }

    private func parseDirectStateMappingLines(in content: String) -> [(label: String, value: String)] {
        let lines = content.components(separatedBy: .newlines)
        var mappings: [(label: String, value: String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let mapping = parseRowStructuredStateMapping(from: trimmed) {
                mappings.append(mapping)
                continue
            }

            guard let regex = try? NSRegularExpression(
                pattern: #"((?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z][A-Za-z-]*(?:\s*\([^)]*\))?)\s*[:=|-]\s*(.+)"#,
                options: .caseInsensitive
            ) else {
                continue
            }

            let nsLine = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let label = nsLine.substring(with: match.range(at: 1))
                let value = nsLine.substring(with: match.range(at: 2))
                mappings.append((normalizeStateLabel(label), cleanupStateMappingValue(value)))
            }
        }

        return mappings.filter { !$0.label.isEmpty && !$0.value.isEmpty }
    }

    private func parseRowStructuredStateMapping(from line: String) -> (label: String, value: String)? {
        guard line.contains("=") else { return nil }

        let segments = line
            .replacingOccurrences(of: #"^Row\s+\d+\s*:\s*"#, with: "", options: .regularExpression)
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var stateLabel: String?
        var stateValue: String?

        for segment in segments {
            let parts = segment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if isStateLabel(value) {
                stateLabel = normalizeStateLabel(value)
                continue
            }

            let lowerKey = key.lowercased()
            if lowerKey.contains("status") || lowerKey.contains("meaning") || lowerKey.contains("indicat") || lowerKey.contains("signal") {
                stateValue = value
            }
        }

        if let stateLabel, let stateValue {
            return (stateLabel, cleanupStateMappingValue(stateValue))
        }

        return nil
    }

    private func parseParallelStateMappings(in content: String) -> [(label: String, value: String)] {
        let normalizedLines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let labelHeaderIndex = normalizedLines.firstIndex(where: isStateLabelHeaderLine(_:)) else { return [] }
        guard let valueHeaderIndex = normalizedLines[(labelHeaderIndex + 1)...].firstIndex(where: isStateValueHeaderLine(_:)) else { return [] }

        let labelLines = Array(normalizedLines[(labelHeaderIndex + 1)..<valueHeaderIndex])
        let valueLines = Array(normalizedLines[(valueHeaderIndex + 1)...].prefix(32))
        let labels = collapseStateColumnItems(labelLines, preferStateLabels: true)
        let values = collapseStateColumnItems(valueLines, preferStateLabels: false)
        let pairCount = min(labels.count, values.count)

        guard pairCount >= 3 else { return [] }

        return (0..<pairCount).map { index in
            (normalizeStateLabel(labels[index]), cleanupStateMappingValue(values[index]))
        }
    }

    private func collapseStateColumnItems(_ lines: [String], preferStateLabels: Bool) -> [String] {
        var items: [String] = []
        var current = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let startsNew: Bool
            if current.isEmpty {
                startsNew = true
            } else if preferStateLabels && isStateLabel(trimmed) {
                startsNew = true
            } else if current.contains("(") && !current.contains(")") {
                startsNew = false
            } else if let first = trimmed.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) {
                startsNew = false
            } else if trimmed.count <= 10 && current.count <= 40 {
                startsNew = false
            } else {
                startsNew = true
            }

            if startsNew {
                if !current.isEmpty {
                    items.append(current)
                }
                current = trimmed
            } else {
                current += " " + trimmed
            }
        }

        if !current.isEmpty {
            items.append(current)
        }

        return items
            .map { cleanupStateMappingValue($0) }
            .filter { !$0.isEmpty }
    }

    private func isStateLabelHeaderLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.contains("color") || normalized.contains("light") || normalized.contains("indicator")
    }

    private func isStateValueHeaderLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.contains("status") || normalized.contains("meaning") || normalized.contains("signal") || normalized.contains("indicates")
    }

    private func isStateLabel(_ value: String) -> Bool {
        value.range(of: #"^(?:Flashing|Solid|Blinking|Steady|Pulsing|Rapid|Slow)\s+[A-Za-z][A-Za-z-]*(?:\s*\([^)]*\))?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func normalizeStateLabel(_ label: String) -> String {
        cleanupStateMappingValue(label)
            .replacingOccurrences(of: #"\s*\(([^)]*)$"#, with: " ($1", options: .regularExpression)
    }

    private func cleanupStateMappingValue(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: #"\bROW\s+\d+\s*:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\bCell\s+r\d+c\d+\s*\[[^\]]+\]\s*[|:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bCell\s+r\d+c\d+\b\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\[(?:Color of Light|PLAUD Status)\]\s*[|:]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\(\d+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\bsecs?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[\.\|:;-]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[|\-:]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[\|:;-]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-:\t\n()"))
    }

    /// Extract answers using proximity scoring - finds part numbers near query keywords.
    ///
    /// **Why this exists**: Document data is often inline like:
    /// `1688 Camera Head with Integrated Coupler 1688-020-122`
    /// NOT structured as `[Specifications]\nKey: Value`
    ///
    /// **Algorithm**:
    /// 1. Find all part number patterns in content
    /// 2. For each part number, score surrounding context (words before)
    /// 3. Score by: entity match + descriptive keyword proximity
    /// 4. Return highest scoring match
    private func extractFromStructuredTables(
        chunks: [RetrievedChunk],
        queryEntities: QueryEntities
    ) -> SpecificationExtractionResult? {
        // Part number regex - matches codes like 1688-020-122
        // REQUIRES at least one digit to avoid matching English words ("three-quarters")
        let partNumberPattern = #"(?=[A-Z0-9.-]*\d)[A-Z0-9]{2,}[-\.][A-Z0-9]{2,}(?:[-\.][A-Z0-9]{2,})*"#
        guard let partNumberRegex = try? NSRegularExpression(pattern: partNumberPattern, options: .caseInsensitive) else {
            return nil
        }

        var bestMatch: (value: String, score: Float, context: String, chunk: RetrievedChunk)?

        for chunk in chunks {
            let content = extractionContent(for: chunk)
            let nsContent = content as NSString

            // Find all part numbers in this chunk
            let matches = partNumberRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

            for match in matches {
                let partNumber = nsContent.substring(with: match.range)

                // Skip if it looks like an action word (Long-press, Short-press)
                if partNumber.lowercased().contains("press") { continue }

                // Skip date patterns (2024-06-21, 01.15.2026, etc.) — these are metadata, not part numbers
                if partNumber.range(of: #"^\d{1,4}[-\.]\d{1,4}[-\.]\d{1,4}$"#, options: .regularExpression) != nil { continue }
                // Also skip simple date-like patterns (2024-06, 12.31, etc.)
                if partNumber.range(of: #"^\d{2,4}[-\.]\d{2,4}$"#, options: .regularExpression) != nil,
                   partNumber.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) { continue }

                // Get context: 120 chars before AND 60 chars after the part number
                // Wider window captures product descriptions that span around codes
                let contextStart = max(0, match.range.location - 120)
                let contextLength = match.range.location - contextStart
                let beforeContext = nsContent.substring(with: NSRange(location: contextStart, length: contextLength)).lowercased()

                let afterStart = match.range.location + match.range.length
                let afterLength = min(60, nsContent.length - afterStart)
                let afterContext = afterLength > 0
                    ? nsContent.substring(with: NSRange(location: afterStart, length: afterLength)).lowercased()
                    : ""

                let fullContext = beforeContext + " " + afterContext

                // Score this candidate
                var score: Float = 0.0

                // Entity match: part number or context contains primary entity
                let entityInPartNumber = queryEntities.primaryEntities.contains { partNumber.lowercased().contains($0) }
                let entityInContext = queryEntities.primaryEntities.contains { fullContext.contains($0) }

                if entityInPartNumber || entityInContext {
                    score += 0.50
                } else if !queryEntities.primaryEntities.isEmpty {
                    // Has entity requirement but doesn't match - skip
                    continue
                }

                // Keyword proximity: how many descriptive keywords appear in surrounding context
                let keywordsInContext = queryEntities.descriptiveKeywords.filter { keyword in
                    keyword.count >= 3 && fullContext.contains(keyword)
                }
                score += Float(keywordsInContext.count) * 0.15

                // Bonus if multiple keywords found — more keywords = stronger signal
                if keywordsInContext.count >= 3 {
                    score += 0.30
                } else if keywordsInContext.count >= 2 {
                    score += 0.20
                }

                Log.debug("[ExtractiveQA] Proximity candidate: '\(partNumber)' score=\(String(format: "%.2f", score)) keywords=\(keywordsInContext)", category: .retrieval)

                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (partNumber, score, beforeContext + partNumber, chunk)
                }
            }
        }

        // Return if we found a confident match
        // With entity: 0.50 (entity) + keywords = easy pass
        // Without entity: need 3+ keywords (0.45 + 0.30 = 0.75) or 2 keywords (0.30 + 0.20 = 0.50)
        if let match = bestMatch, match.score >= 0.55 {
            // Validate: for measurement/capacity queries, answer should contain
            // a digit (not just an English word that happened to match the pattern)
            let hasDigit = match.value.contains(where: { $0.isNumber })
            let isMeasurementQuery = queryEntities.descriptiveKeywords.contains(where: {
                ["capacity", "volume", "liters", "gallons", "quarts", "size", "weight", "length", "width", "height", "diameter", "pressure", "temperature"].contains($0)
            })
            if isMeasurementQuery && !hasDigit {
                Log.debug("[ExtractiveQA] Rejected proximity match '\(match.value)' — measurement query requires numeric answer", category: .retrieval)
                return nil
            }

            Log.info("[ExtractiveQA] ✓ Proximity match: '\(match.value)' (score: \(String(format: "%.2f", match.score)))", category: .retrieval)

            return SpecificationExtractionResult(
                answerSpan: match.value,
                matchedLabel: nil,
                confidence: min(0.90, match.score * 0.8 + 0.25), // Conservative: 0.55→0.69, 0.75→0.85, 0.95→0.90
                sourceChunk: match.chunk,
                surroundingContext: match.context,
                specificationType: "ProximityMatch",
                matchedKeywords: queryEntities.descriptiveKeywords
            )
        }

        Log.debug("[ExtractiveQA] No proximity match found (best: \(bestMatch?.score ?? 0))", category: .retrieval)
        return nil
    }

    // MARK: - Query Analysis

    /// Result of entity-aware query parsing
    private struct QueryEntities {
        /// All meaningful keywords (lowercased)
        let keywords: [String]
        /// Primary entity identifiers (product codes, model numbers) - THE SUBJECT of the query
        /// In "1688 camera head reference number", this is ["1688"]
        /// These are NOT just keywords - they define WHAT we're looking up
        let primaryEntities: [String]
        /// Descriptive keywords (non-entity terms like "camera", "reference")
        let descriptiveKeywords: [String]
    }

    /// Parse query into entities and keywords using NER-inspired approach.
    ///
    /// Distinguishes between:
    /// - **Primary entities**: Product IDs, model numbers, codes being looked up
    /// - **Descriptive keywords**: Generic terms describing the entity type or attribute
    ///
    /// For "1688 camera head reference number":
    /// - Primary entity: "1688" (the product being queried)
    /// - Descriptive: "camera", "head", "reference", "number"
    ///
    /// Based on: Entity-Centric QA (ACL/EMNLP literature), Named Entity Recognition
    private func parseQueryEntities(from query: String) -> QueryEntities {
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

        // ========================================================================
        // ENTITY DETECTION: Identify product/model identifiers in the query
        // These are SUBJECTS of the query, not just keywords
        // ========================================================================
        var primaryEntities: [String] = []
        var descriptiveKeywords: [String] = []

        for token in tokens {
            // Check if token looks like a product/model identifier:
            // 1. Pure numeric code >= 3 digits (e.g., "1688", "5050", "12345")
            // 2. Alphanumeric with digits (e.g., "abc123", "f150", "rx7")
            // 3. NOT common words that happen to have numbers (we filter these later)

            let hasDigits = token.contains(where: { $0.isNumber })
            let digitCount = token.filter { $0.isNumber }.count

            if hasDigits && digitCount >= 3 {
                // Strong entity signal: 3+ digits (product codes, model numbers)
                primaryEntities.append(token)
            } else if hasDigits && token.count <= 6 {
                // Weak entity signal: short alphanumeric (could be model like "f150")
                // Only treat as entity if it's not a common word pattern
                let isLikelyWord = token.allSatisfy { $0.isLetter || $0.isNumber }
                    && token.first?.isLetter == true
                    && digitCount == 1  // Single digit at end might be "version 2"
                if !isLikelyWord {
                    primaryEntities.append(token)
                } else {
                    descriptiveKeywords.append(token)
                }
            } else {
                descriptiveKeywords.append(token)
            }
        }

        // Add domain-aware expansions to descriptive keywords based on context
        if tokens.contains("capacity") || tokens.contains("much") || tokens.contains("many") {
            descriptiveKeywords.append(contentsOf: ["liters", "quarts", "gallons", "capacity", "volume"])
        }
        if tokens.contains("gas") {
            descriptiveKeywords.append(contentsOf: ["fuel", "gasoline"])
        }
        if tokens.contains("fuel") || tokens.contains("gasoline") {
            descriptiveKeywords.append(contentsOf: ["gas"])
        }
        if tokens.contains("hold") || tokens.contains("holds") || tokens.contains("holding") {
            descriptiveKeywords.append(contentsOf: ["capacity", "volume"])
        }
        if tokens.contains("car") {
            descriptiveKeywords.append("vehicle")
        }

        // All keywords = entities + descriptive (for backwards compatibility)
        let allKeywords = Array(Set(primaryEntities + descriptiveKeywords))

        Log.debug(
            "[ExtractiveQA] Query parsing - Entities: \(primaryEntities), Descriptive: \(descriptiveKeywords.prefix(5))",
            category: .retrieval
        )

        return QueryEntities(
            keywords: allKeywords,
            primaryEntities: primaryEntities,
            descriptiveKeywords: Array(Set(descriptiveKeywords))
        )
    }

    /// Legacy method for backwards compatibility
    private func extractQueryKeywords(from query: String) -> [String] {
        return parseQueryEntities(from: query).keywords
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
