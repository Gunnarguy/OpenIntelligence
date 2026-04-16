//
//  QueryComplexityAnalyzer.swift
//  OpenIntelligence
//
//  Analyzes query complexity to auto-route between single-pass and agentic modes.
//  Philosophy: When in doubt, go agentic. Only obviously simple queries stay fast.
//

import Foundation
import NaturalLanguage

/// Result of query complexity analysis
struct QueryComplexityResult: Sendable {
    let complexity: QueryComplexity
    let confidence: Float
    let reasons: [String]
    let suggestedMode: InferredMode

    enum QueryComplexity: String, Sendable {
        case simple // "What is X?" - single fact lookup
        case moderate // "How do I do X?" - focused question
        case complex // "Compare X and Y across all documents" - multi-step reasoning
    }

    enum InferredMode: String, Sendable {
        case singlePass // Fast, comprehensive single retrieval
        case agentic // Multi-session deep reasoning
    }
}

/// Analyzes queries to determine optimal processing mode
final class QueryComplexityAnalyzer: Sendable {
    static let shared = QueryComplexityAnalyzer()

    private init() {}

    /// Analyze a query and determine optimal processing mode
    /// Biased toward agentic when uncertain — better to over-think than under-think
    func analyze(_ query: String) -> QueryComplexityResult {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(separator: " ").map(String.init)
        let wordCount = words.count

        var complexityScore: Float = 0.0
        var reasons: [String] = []

        // ═══════════════════════════════════════════════════════════════
        // SIGNALS THAT TRIGGER AGENTIC (generous detection)
        // ═══════════════════════════════════════════════════════════════

        // Multi-part questions (conjunctions suggest multiple sub-questions)
        let multiPartMarkers = ["and also", "as well as", "in addition", "furthermore",
                                "additionally", "plus", "along with", "together with"]
        for marker in multiPartMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.4
                reasons.append("Multi-part question detected: '\(marker)'")
            }
        }

        // Multiple question marks = definitely complex
        if query.filter({ $0 == "?" }).count > 1 {
            complexityScore += 0.5
            reasons.append("Multiple questions in one query")
        }

        // Comparison queries
        let comparisonMarkers = ["compare", "versus", " vs ", "difference between",
                                 "similarities between", "contrast", "pros and cons",
                                 "advantages and disadvantages", "better than", "worse than"]
        for marker in comparisonMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.5
                reasons.append("Comparison query: '\(marker)'")
            }
        }

        // Synthesis/aggregation queries
        let synthesisMarkers = ["summarize all", "across all", "comprehensive", "overview of all",
                                "complete summary", "full analysis", "everything about",
                                "all documents", "entire", "whole"]
        for marker in synthesisMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.5
                reasons.append("Synthesis query: '\(marker)'")
            }
        }

        // Analysis/evaluation queries
        let analysisMarkers = ["analyze", "evaluate", "assess", "critique", "review",
                               "implications", "consequences", "impact of", "effects of",
                               "why does", "why do", "explain why", "reasoning behind"]
        for marker in analysisMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.35
                reasons.append("Analysis query: '\(marker)'")
            }
        }

        // Multi-step procedural queries
        let proceduralMarkers = ["step by step", "how to", "process for", "procedure",
                                 "instructions for", "guide to", "walkthrough"]
        for marker in proceduralMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.3
                reasons.append("Procedural query: '\(marker)'")
            }
        }

        // Temporal/historical queries
        let temporalMarkers = ["over time", "historically", "evolution of", "changes in",
                               "timeline", "progression", "development of"]
        for marker in temporalMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.35
                reasons.append("Temporal analysis: '\(marker)'")
            }
        }

        // Hypothetical/reasoning queries
        let hypotheticalMarkers = ["what if", "what would", "assuming", "suppose",
                                   "imagine", "hypothetically", "in theory"]
        for marker in hypotheticalMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.4
                reasons.append("Hypothetical reasoning: '\(marker)'")
            }
        }

        // Cross-reference queries
        let crossRefMarkers = ["according to", "based on", "as mentioned in",
                               "referenced in", "cited in", "relates to"]
        for marker in crossRefMarkers {
            if normalized.contains(marker) {
                complexityScore += 0.25
                reasons.append("Cross-reference query: '\(marker)'")
            }
        }

        // Long queries usually indicate complexity
        if wordCount > 20 {
            complexityScore += 0.4
            reasons.append("Long query (\(wordCount) words)")
        } else if wordCount > 15 {
            complexityScore += 0.25
            reasons.append("Moderately long query (\(wordCount) words)")
        }

        // Multiple named entities suggest cross-document reasoning
        let entityCount = countNamedEntities(in: query)
        if entityCount >= 3 {
            complexityScore += 0.35
            reasons.append("Multiple entities (\(entityCount)) may require cross-document search")
        }

        // ═══════════════════════════════════════════════════════════════
        // SIGNALS FOR SIMPLE QUERIES (only if NO complexity signals)
        // ═══════════════════════════════════════════════════════════════

        var simplicityScore: Float = 0.0

        // Very short queries are usually simple lookups
        if wordCount <= 5 {
            simplicityScore += 0.4
        } else if wordCount <= 8 {
            simplicityScore += 0.2
        }

        // Direct question starters for factual lookup
        let simpleLookupStarters = ["what is", "what's", "who is", "who's", "when is",
                                    "when was", "where is", "where's", "define", "meaning of"]
        for starter in simpleLookupStarters {
            if normalized.hasPrefix(starter) {
                simplicityScore += 0.3
            }
        }

        // Simple locator queries
        let locatorMarkers = ["find", "show me", "locate", "search for", "look up"]
        for marker in locatorMarkers {
            if normalized.hasPrefix(marker) {
                simplicityScore += 0.2
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // DECISION LOGIC: Bias toward agentic
        // ═══════════════════════════════════════════════════════════════

        // Net complexity = complexity signals - simplicity signals
        let netComplexity = complexityScore - (simplicityScore * 0.5) // Simplicity has less weight

        let complexity: QueryComplexityResult.QueryComplexity
        let mode: QueryComplexityResult.InferredMode
        let confidence: Float

        if netComplexity >= 0.5 {
            // Clear complexity signals → agentic
            complexity = .complex
            mode = .agentic
            confidence = min(0.95, 0.7 + netComplexity * 0.2)
        } else if netComplexity >= 0.25 {
            // Moderate signals → still go agentic (bias toward smarter)
            complexity = .moderate
            mode = .agentic
            confidence = 0.65 + netComplexity * 0.2
        } else if simplicityScore >= 0.5 && complexityScore == 0 {
            // Only clearly simple queries with NO complexity markers stay single-pass
            complexity = .simple
            mode = .singlePass
            confidence = min(0.9, 0.6 + simplicityScore * 0.3)
        } else {
            // When in doubt → agentic (the whole point)
            complexity = .moderate
            mode = .agentic
            confidence = 0.55
            if reasons.isEmpty {
                reasons.append("Defaulting to agentic for comprehensive coverage")
            }
        }

        return QueryComplexityResult(
            complexity: complexity,
            confidence: confidence,
            reasons: reasons.isEmpty ? ["Standard processing"] : reasons,
            suggestedMode: mode
        )
    }

    /// Count named entities using NLTagger
    private func countNamedEntities(in text: String) -> Int {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entityCount = 0
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: text.startIndex ..< text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: options)
        { tag, _ in
            if let tag = tag,
               tag == .personalName || tag == .placeName || tag == .organizationName
            {
                entityCount += 1
            }
            return true
        }

        return entityCount
    }
}
