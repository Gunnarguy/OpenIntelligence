//
//  SmartReplyService.swift
//  OpenIntelligence
//
//  Generates contextual follow-up question suggestions after RAG responses.
//  Analyzes the Q&A exchange to suggest relevant next questions that dig deeper
//  into the retrieved content. Inspired by Apple's Smart Reply framework.
//

import Foundation
import NaturalLanguage
import FoundationModels

/// A smart follow-up suggestion generated from conversation context
struct SmartReply: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let category: SmartReplyCategory
    let confidence: Double  // 0-1 relevance confidence
}

/// Categories of follow-up suggestions
enum SmartReplyCategory: String, Sendable {
    case deepDive = "deep_dive"         // Dig deeper into a topic mentioned
    case clarify = "clarify"            // Ask for clarification
    case compare = "compare"            // Compare with something else mentioned
    case nextStep = "next_step"         // What to do next (procedural)
    case related = "related"            // Related topic from same document
    case broader = "broader"            // Zoom out to broader context

    /// SF Symbol icon for use in follow-up chip UI
    var iconName: String {
        switch self {
        case .deepDive: return "magnifyingglass.circle"
        case .clarify: return "questionmark.circle"
        case .compare: return "arrow.left.arrow.right"
        case .nextStep: return "arrow.right.circle"
        case .related: return "link"
        case .broader: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Service for generating intelligent follow-up question suggestions
/// Uses LLM + NLP heuristics to produce contextual "smart replies"
actor SmartReplyService {
    static let shared = SmartReplyService()

    private let tagger = NLTagger(tagSchemes: [.nameType, .lemma])

    private init() {}

    // MARK: - Follow-Up Generation

    /// Generate smart follow-up suggestions based on a Q&A exchange
    /// - Parameters:
    ///   - query: The user's original question
    ///   - response: The RAG response text
    ///   - retrievedChunks: Source chunks used for the response
    ///   - maxSuggestions: Maximum number of suggestions to return
    /// - Returns: Array of SmartReply suggestions sorted by relevance
    func generateFollowUps(
        query: String,
        response: String,
        retrievedChunks: [RetrievedChunk] = [],
        maxSuggestions: Int = 3
    ) async -> [SmartReply] {
        var suggestions: [SmartReply] = []
        HardwareTelemetryReporter.pulse(.queryProcessing, intensity: 0.6, duration: 0.3)
        HardwareTelemetryReporter.reportCPUOperation()

        // Strategy 1: Extract key entities/topics from response for deep-dive questions
        let responseEntities = extractKeyTerms(from: response)
        let queryTerms = Set(extractKeyTerms(from: query).map { $0.lowercased() })

        // Find entities in response NOT already in the query (new topics introduced)
        let newTopics = responseEntities.filter { !queryTerms.contains($0.lowercased()) }

        for topic in newTopics.prefix(2) {
            suggestions.append(SmartReply(
                text: "Tell me more about \(topic)",
                category: .deepDive,
                confidence: 0.8
            ))
        }

        // Strategy 2: Check for procedural content → suggest next steps
        if containsProceduralContent(response) {
            suggestions.append(SmartReply(
                text: "What are the next steps after this?",
                category: .nextStep,
                confidence: 0.75
            ))
        }

        // Strategy 3: Check for numerical/specification content → suggest comparison
        if containsNumericalData(response) {
            suggestions.append(SmartReply(
                text: "How does this compare to other options?",
                category: .compare,
                confidence: 0.7
            ))
        }

        // Strategy 4: If response mentions limitations or conditions → suggest clarification
        if containsConditionalLanguage(response) {
            suggestions.append(SmartReply(
                text: "What are the exceptions or limitations?",
                category: .clarify,
                confidence: 0.65
            ))
        }

        // Strategy 5: Extract section headers or document titles from chunks for related topics
        let chunkTopics = extractChunkTopics(from: retrievedChunks)
        let relatedTopics = chunkTopics.filter { topic in
            !query.lowercased().contains(topic.lowercased()) &&
            !response.lowercased().contains(topic.lowercased())
        }

        for topic in relatedTopics.prefix(1) {
            suggestions.append(SmartReply(
                text: "What does the document say about \(topic)?",
                category: .related,
                confidence: 0.6
            ))
        }

        // Strategy 6: LLM-generated follow-ups (if available)
        if let llmSuggestions = await generateLLMFollowUps(query: query, response: response) {
            suggestions.append(contentsOf: llmSuggestions)
        }

        // Sort by confidence and limit
        let sorted = suggestions
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxSuggestions)

        return Array(sorted)
    }

    // MARK: - NLP Analysis

    /// Extract key terms (nouns, proper nouns, technical terms) from text
    private func extractKeyTerms(from text: String) -> [String] {
        var terms: [String] = []

        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if let tag = tag, tag != .otherWord {
                let term = String(text[range])
                if term.count >= 2 {
                    terms.append(term)
                }
            }
            return true
        }

        // Also extract PascalCase and ACRONYM terms
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count >= 3,
               cleaned.first?.isUppercase == true,
               cleaned.dropFirst().contains(where: { $0.isUppercase })
            {
                terms.append(cleaned)
            }
        }

        return Array(Set(terms))
    }

    /// Check if text contains procedural/step-by-step content
    private func containsProceduralContent(_ text: String) -> Bool {
        let patterns = ["step 1", "step 2", "first,", "then,", "next,", "finally,",
                        "procedure", "instructions", "how to", "follow these"]
        let lower = text.lowercased()
        return patterns.contains(where: { lower.contains($0) })
    }

    /// Check if text contains numerical specifications
    private func containsNumericalData(_ text: String) -> Bool {
        let patterns = ["\\d+\\.\\d+", "\\d+%", "\\d+ (mm|cm|kg|lb|psi|rpm|mph|kph|watts|volts)"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    /// Check if text contains conditional/limitation language
    private func containsConditionalLanguage(_ text: String) -> Bool {
        let patterns = ["however", "except", "unless", "only if", "note that",
                        "limitation", "caveat", "warning", "important:"]
        let lower = text.lowercased()
        return patterns.contains(where: { lower.contains($0) })
    }

    /// Extract topic hints from retrieved chunk metadata
    private func extractChunkTopics(from chunks: [RetrievedChunk]) -> [String] {
        var topics: [String] = []
        for chunk in chunks {
            // Check chunk metadata for section headers
            if let sectionTitle = chunk.chunk.metadata.sectionTitle {
                topics.append(sectionTitle)
            }
            // Check document filename for topic hints
            let docName = chunk.sourceDocument
            if !docName.isEmpty {
                let name = (docName as NSString).deletingPathExtension
                topics.append(name)
            }
        }
        return Array(Set(topics))
    }

    // MARK: - LLM Follow-Up Generation

    /// Use the on-device LLM to generate contextual follow-up questions
    private func generateLLMFollowUps(query: String, response: String) async -> [SmartReply]? {
        guard #available(iOS 26.0, *) else { return nil }

        do {
            let session = LanguageModelSession()
            HardwareTelemetryReporter.sustain(.llmInference, active: true, intensity: 0.7)

            let prompt = """
            Given this Q&A exchange, suggest 2 concise follow-up questions the user might ask.

            Question: \(query.prefix(200))
            Answer: \(response.prefix(500))

            Reply with exactly 2 follow-up questions, one per line. Keep each under 60 characters.
            """

            let result = try await session.respond(to: prompt)
            HardwareTelemetryReporter.sustain(.llmInference, active: false)
            Task { @MainActor in DSHaptics.messageReceived() }
            let lines = result.content.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 5 && $0.count < 100 }

            return lines.prefix(2).map { line in
                SmartReply(
                    text: line.hasPrefix("- ") ? String(line.dropFirst(2)) : line,
                    category: .deepDive,
                    confidence: 0.85
                )
            }
        } catch {
            Log.debug("[SmartReply] LLM follow-up generation failed: \(error.localizedDescription)", category: .retrieval)
            return nil
        }
    }
}
