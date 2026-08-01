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

        let shouldIgnoreResponseText = responseLooksLikeMetaAnswer(response)
        let analysisText: String
        if shouldIgnoreResponseText, !retrievedChunks.isEmpty {
            analysisText = retrievedChunks
                .prefix(4)
                .map { $0.chunk.content }
                .joined(separator: "\n")
        } else {
            analysisText = response
        }

        guard !analysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let queryTerms = Set(extractKeyTerms(from: query).map { $0.lowercased() })

        // Strategy 1: read the answer's own structure.
        //
        // `extractKeyTerms` uses NLTagger's `.nameType` scheme and keeps anything not
        // tagged `.otherWord`, which spuriously admits ordinary words — a device run
        // offered "Tell me more about affects" and "Tell me more about mention". The
        // signals below come from choices the model made while writing, so they are
        // salient by construction and carry no domain assumptions.
        suggestions.append(contentsOf: followUpsFromAnswerShape(
            answer: analysisText,
            queryTerms: queryTerms
        ))

        if let groundedConditional = extractConditionalFollowUp(
            query: query,
            response: analysisText,
            chunks: retrievedChunks
        ) {
            suggestions.append(SmartReply(
                text: groundedConditional,
                category: .clarify,
                confidence: 0.86
            ))
        }

        // Strategy 2: Check for procedural content → suggest next steps
        if containsProceduralContent(analysisText) {
            suggestions.append(SmartReply(
                text: "What are the next steps after this?",
                category: .nextStep,
                confidence: 0.75
            ))
        }

        // Strategy 3: Check for numerical/specification content → suggest comparison
        if containsNumericalData(analysisText) {
            suggestions.append(SmartReply(
                text: "How does this compare to other options?",
                category: .compare,
                confidence: 0.7
            ))
        }

        // Strategy 4: If response mentions limitations or conditions → suggest clarification
        if containsConditionalLanguage(analysisText) {
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
            !analysisText.lowercased().contains(topic.lowercased())
        }

        for topic in relatedTopics.prefix(1) {
            suggestions.append(SmartReply(
                text: relatedTopicQuestion(for: topic),
                category: .related,
                confidence: 0.6
            ))
        }

        // Strategy 6: LLM-generated follow-ups (if available)
        if !shouldIgnoreResponseText,
           let llmSuggestions = await generateLLMFollowUps(
                query: query,
                response: response,
                retrievedChunks: retrievedChunks
           )
        {
            suggestions.append(contentsOf: llmSuggestions)
        }

        // Sort by confidence and limit
        let filteredSuggestions = uniqueByText(
            suggestions
            .filter {
                isUsableSuggestionText($0.text)
                    && !isSelfAnsweringSuggestion(
                        $0.text,
                        query: query,
                        response: response,
                        chunks: retrievedChunks
                    )
            }
        )

        let sorted = filteredSuggestions
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxSuggestions)

        return Array(sorted)
    }

    // MARK: - NLP Analysis

    /// Extract key terms (nouns, proper nouns, technical terms) from text
    /// Follow-ups derived from how the answer was written, not from what it is about.
    ///
    /// Three signals, each a decision the model made and therefore meaningful in any
    /// domain:
    ///
    /// 1. **Quoted phrases.** The model quotes what it considers load-bearing. An
    ///    answer containing `"learning and stress"` and `"feeding behavior"` is
    ///    pointing at exactly the phrases worth pulling on.
    /// 2. **Section headers.** Where the model chose to divide the answer marks a
    ///    theme substantial enough to expand.
    /// 3. **Stated gaps.** "does not specify", "not mention" and similar mean the
    ///    corpus fell short, and the useful next move is about the library rather
    ///    than the topic.
    private func followUpsFromAnswerShape(answer: String, queryTerms: Set<String>) -> [SmartReply] {
        var out: [SmartReply] = []
        var used: Set<String> = []

        func add(_ text: String, _ category: SmartReplyCategory, _ confidence: Double) {
            let key = text.lowercased()
            guard !used.contains(key) else { return }
            used.insert(key)
            out.append(SmartReply(text: text, category: category, confidence: confidence))
        }

        // 1. Quoted phrases the model chose to highlight.
        if let quoted = try? NSRegularExpression(pattern: "[\u{201C}\"]([^\u{201D}\"\n]{4,60})[\u{201D}\"]") {
            let range = NSRange(answer.startIndex..., in: answer)
            for match in quoted.matches(in: answer, range: range).prefix(4) {
                guard let r = Range(match.range(at: 1), in: answer) else { continue }
                let phrase = String(answer[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard phrase.count >= 4, !queryTerms.contains(phrase.lowercased()) else { continue }
                add("What do the documents say about \(phrase)?", .deepDive, 0.88)
            }
        }

        // 2. Section headers, which mark themes the model thought worth separating.
        for line in answer.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            var heading: String?
            if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.count > 6 {
                heading = String(trimmed.dropFirst(2).dropLast(2))
            } else if trimmed.hasPrefix("#") {
                heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            if let h = heading, h.count >= 4, h.count <= 60, !queryTerms.contains(h.lowercased()) {
                add("Go deeper on \(h.lowercased())", .related, 0.82)
            }
        }

        // 3. The answer reported a gap. Point at the library, not the topic.
        let lowered = answer.lowercased()
        let gapPhrases = [
            "does not specify", "do not specify", "does not mention", "do not mention",
            "not explicitly", "no new facts", "does not provide", "do not provide",
            "couldn't find", "could not find",
        ]
        if gapPhrases.contains(where: { lowered.contains($0) }) {
            add("What would I need to add to answer this fully?", .clarify, 0.9)
            add("Search my other libraries for this", .broader, 0.78)
        }

        return Array(out.prefix(4))
    }

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

    private func responseLooksLikeMetaAnswer(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "i want to stay grounded in your library",
            "i don't have enough evidence",
            "i do not have enough evidence",
            "best-effort note:",
            "add or select a library with relevant documents",
            "ask about a specific document title or section",
            "i couldn't fully certify a polished answer",
        ]
        return markers.contains { lower.contains($0) }
    }

    private func relatedTopicQuestion(for topic: String) -> String {
        let cleaned = topic
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned == cleaned.uppercased() {
            return "What's important about \(cleaned.lowercased())?"
        }
        return "What's important about \(cleaned)?"
    }

    private func isUsableSuggestionText(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count >= 8 else { return false }

        let bannedFragments = [
            "[", "]", "{", "}", "<", ">",
            "thing from passage",
            "condition from passage",
            "what does the document say",
            "what do the documents say",
            "uploaded document",
            "uploaded documents",
            "your documents",
            "the passages below",
        ]

        return !bannedFragments.contains { lower.contains($0) }
    }

    private func isSelfAnsweringSuggestion(
        _ suggestion: String,
        query: String,
        response: String,
        chunks: [RetrievedChunk]
    ) -> Bool {
        guard isQuantityQuestion(suggestion), isQuantityQuestion(query) else { return false }

        let suggestionNumbers = Set(extractNumericTokens(from: suggestion))
        guard !suggestionNumbers.isEmpty else { return false }

        let answerNumbers = Set(
            extractNumericTokens(
                from: ([response] + chunks.prefix(4).map { $0.chunk.content }).joined(separator: " ")
            )
        )
        guard !suggestionNumbers.intersection(answerNumbers).isEmpty else { return false }

        let queryTokens = meaningfulTokens(from: query)
        let suggestionTokens = meaningfulTokens(from: suggestion)
        let overlapCount = suggestionTokens.intersection(queryTokens).count

        return overlapCount >= 2
    }

    private func extractConditionalFollowUp(
        query: String,
        response: String,
        chunks: [RetrievedChunk]
    ) -> String? {
        guard !chunks.isEmpty else { return nil }

        let queryTokens = meaningfulTokens(from: query)
        let responseTokens = meaningfulTokens(from: response)
        let numericTokens = extractNumericTokens(from: "\(query) \(response)")

        for chunk in chunks.prefix(4) {
            let sentences = chunk.chunk.content
                .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for sentence in sentences {
                let lowered = sentence.lowercased()
                guard lowered.contains("if ") else { continue }

                let sentenceTokens = meaningfulTokens(from: sentence)
                let tokenOverlap = sentenceTokens.intersection(queryTokens).count
                let responseOverlap = sentenceTokens.intersection(responseTokens).count
                let numberOverlap = numericTokens.filter { lowered.contains($0) }.count
                guard tokenOverlap >= 1 || responseOverlap >= 1 || numberOverlap >= 1 else {
                    continue
                }

                let conditionText: String
                if let ifRange = lowered.range(of: "if ") {
                    let remainder = sentence[ifRange.upperBound...]
                    if let commaIndex = remainder.firstIndex(of: ",") {
                        conditionText = String(remainder[..<commaIndex])
                    } else {
                        conditionText = String(remainder)
                    }
                } else {
                    continue
                }

                let cleanedCondition = conditionText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                let lowerCondition = cleanedCondition.lowercased()

                guard cleanedCondition.count >= 8, cleanedCondition.count <= 90 else { continue }
                guard !lowerCondition.contains("document"),
                      !lowerCondition.contains("thing from passage"),
                      !lowerCondition.contains("individual"),
                      !lowerCondition.contains("subject")
                else {
                    continue
                }

                return "What happens if \(lowerCondition)?"
            }
        }

        return nil
    }

    private func meaningfulTokens(from text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "that", "this", "what", "when",
            "where", "which", "about", "into", "your", "their", "does", "have",
            "here", "there", "under", "over", "should", "would", "could", "after",
            "before", "using", "used", "than", "then", "they", "them", "same",
            "individual", "individuals", "people", "person", "all"
        ]

        return Set(
            text
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { token in
                    token.contains(where: \.isNumber) || (token.count >= 3 && !stopWords.contains(token))
                }
        )
    }

    private func extractNumericTokens(from text: String) -> [String] {
        text
            .split { !$0.isNumber && $0 != "." && $0 != "," }
            .map(String.init)
            .filter { token in token.contains(where: \.isNumber) }
    }

    private func isQuantityQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("how many")
            || lower.hasPrefix("how much")
            || lower.hasPrefix("how long")
            || lower.hasPrefix("what percentage")
            || lower.hasPrefix("what percent")
    }

    private func uniqueByText(_ suggestions: [SmartReply]) -> [SmartReply] {
        var seen: Set<String> = []
        var deduped: [SmartReply] = []

        for suggestion in suggestions {
            let key = suggestion.text
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(key).inserted {
                deduped.append(suggestion)
            }
        }

        return deduped
    }

    // MARK: - LLM Follow-Up Generation

    /// Use the on-device LLM to generate contextual follow-up questions
    private func generateLLMFollowUps(
        query: String,
        response: String,
        retrievedChunks: [RetrievedChunk]
    ) async -> [SmartReply]? {
        guard #available(iOS 26.0, *) else { return nil }

        do {
            let session = LanguageModelSession()
            let excerptText = retrievedChunks
                .prefix(3)
                .enumerated()
                .map { index, chunk in
                    let source = chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument
                    return "[\(index + 1)] \(source)\n\(String(chunk.chunk.content.prefix(280)))"
                }
                .joined(separator: "\n\n")

            let prompt = """
            Suggest 2 concise follow-up questions for this grounded document Q&A exchange.

            Question: \(query.prefix(200))
            Answer: \(response.prefix(500))
            Supporting excerpts:
            \(excerptText)

            Rules:
            - Stay in the same domain and subject as the question and excerpts
            - Reuse the actual nouns from the question or excerpts when possible
            - Do not generalize equipment, procedures, or measurements into people, individuals, subjects, or users unless the excerpts explicitly say that
            - Ask about a nearby condition, comparison, setting, warning, or consequence grounded in the excerpts
            - Do not restate the answer as a question
            - Do not ask a quantity question that already includes the resolved number or measurement
            - Return exactly 2 plain questions, one per line, each under 60 characters
            """

            let result = try await session.respond(to: prompt)
            let lines = result.content.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 5 && $0.count < 100 }

            let validated = lines
                .prefix(4)
                .map { line in line.hasPrefix("- ") ? String(line.dropFirst(2)) : line }
                .compactMap { sanitizeLLMFollowUp($0, query: query, chunks: retrievedChunks) }

            return validated.prefix(2).map { line in
                SmartReply(
                    text: line,
                    category: .deepDive,
                    confidence: 0.85
                )
            }
        } catch {
            Log.debug("[SmartReply] LLM follow-up generation failed: \(error.localizedDescription)", category: .retrieval)
            return nil
        }
    }

    private func sanitizeLLMFollowUp(
        _ text: String,
        query: String,
        chunks: [RetrievedChunk]
    ) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if !cleaned.hasSuffix("?") {
            cleaned += "?"
        }

        guard isUsableSuggestionText(cleaned) else { return nil }

        let corpusText = ([query] + chunks.prefix(4).map { $0.chunk.content }).joined(separator: " ").lowercased()
        let questionTokens = meaningfulTokens(from: cleaned)
        let overlapCount = questionTokens.filter { corpusText.contains($0) }.count
        let driftTerms = [
            "individual", "individuals", "subject", "subjects",
            "person", "people", "user", "users", "participant", "participants",
        ]

        if driftTerms.contains(where: { cleaned.lowercased().contains($0) && !corpusText.contains($0) }) {
            return nil
        }

        guard overlapCount >= 2 else { return nil }
        return cleaned
    }
}
