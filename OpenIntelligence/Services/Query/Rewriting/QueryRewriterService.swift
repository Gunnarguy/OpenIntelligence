//
//  QueryRewriterService.swift
//  OpenIntelligence
//
//  Lightweight query clarification for improved retrieval.
//
//  Philosophy: Trust the embeddings. Only rewrite when there's genuine ambiguity
//  (pronouns, vague references). Don't over-engineer or domain-lock.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Recent conversation turn for context
struct ConversationTurn: Sendable {
    let role: String
    let content: String
    let entities: [String]
}

/// Result of query processing
struct RewrittenQuery: Sendable {
    let original: String
    let rewritten: String
    let intent: SemanticIntent
    let entities: [String]
    let searchTerms: [String]
    let confidence: Float
    let wasRewritten: Bool
    let resolvedEntities: [String]
}

/// Detected query intent for semantic classification
enum SemanticIntent: String, Sendable {
    case howTo = "how_to"
    case whatIs = "what_is"
    case why
    case when
    case where_ = "where"
    case comparison
    case troubleshoot
    case list
    case followUp = "follow_up"
    case unknown
}

/// Lightweight query clarification service.
///
/// Only intervenes when there's genuine ambiguity that would hurt retrieval:
/// - Pronouns without clear referents ("it", "this", "that")
/// - Follow-up questions that need context ("what else", "and how about")
/// - Very short queries that need expansion
final class QueryRewriterService: @unchecked Sendable {
    private let corpusVocabulary: CorpusVocabulary?
    private let documentSummaries: [String]?

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private var session: LanguageModelSession?
    #endif

    init(
        corpusVocabulary: CorpusVocabulary? = nil,
        documentSummaries: [String]? = nil
    ) {
        self.corpusVocabulary = corpusVocabulary
        self.documentSummaries = documentSummaries
    }

    // MARK: - Public API

    func rewrite(
        query: String,
        documentNames _: [String] = [],
        conversationContext: [ConversationTurn] = []
    ) async throws -> RewrittenQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect if this query actually needs clarification
        let ambiguityType = detectAmbiguity(trimmed, conversationContext: conversationContext)

        guard ambiguityType != .none else {
            // Query is clear enough - don't mess with it
            return passthrough(trimmed)
        }

        let intent = detectIntent(trimmed)
        let entities = extractEntities(trimmed)
        let conversationEntities = extractConversationEntities(from: conversationContext)

        // Try LLM clarification for genuinely ambiguous queries
        do {
            let clarified = try await clarifyWithLLM(
                query: trimmed,
                ambiguityType: ambiguityType,
                conversationContext: conversationContext
            )

            Log.info("[QueryRewriter] Clarified: \"\(trimmed)\" → \"\(clarified)\"", category: .retrieval)

            return RewrittenQuery(
                original: trimmed,
                rewritten: clarified,
                intent: intent,
                entities: entities,
                searchTerms: [],
                confidence: 0.85,
                wasRewritten: true,
                resolvedEntities: conversationEntities
            )
        } catch {
            // Fallback: simple pronoun substitution from context
            let fallback = simplePronounSubstitution(
                query: trimmed,
                conversationContext: conversationContext
            )

            return RewrittenQuery(
                original: trimmed,
                rewritten: fallback,
                intent: intent,
                entities: entities,
                searchTerms: [],
                confidence: 0.6,
                wasRewritten: fallback != trimmed,
                resolvedEntities: conversationEntities
            )
        }
    }

    // MARK: - Ambiguity Detection

    private enum AmbiguityType {
        case none // Query is clear
        case pronouns // Has "it", "this", "that" without clear referent
        case followUp // "what else", "and how about", "more about"
        case tooShort // Under 3 words, might need context
    }

    /// Check if a word is a stop word (not a content-bearing noun)
    private func isStopWord(_ word: String) -> Bool {
        let stopWords: Set<String> = [
            "is", "are", "was", "were", "be", "been", "being",
            "do", "does", "did", "have", "has", "had",
            "can", "could", "will", "would", "shall", "should", "may", "might", "must",
            "a", "an", "the", "and", "or", "but", "if", "then", "else",
            "when", "where", "why", "how", "what", "which", "who", "whom",
            "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "about", "into", "through", "during", "before", "after",
            "i", "you", "he", "she", "we", "they", "me", "him", "her", "us",
            "my", "your", "his", "its", "our", "their",
            "all", "any", "both", "each", "few", "more", "most", "some",
            "no", "not", "only", "same", "so", "than", "too", "very",
            "just", "also", "now", "here", "there",
        ]
        return stopWords.contains(word.lowercased())
    }

    private func detectAmbiguity(_ query: String, conversationContext: [ConversationTurn]) -> AmbiguityType {
        let lower = query.lowercased()
        let words = query.split(separator: " ")

        // Follow-up patterns (need prior context)
        let followUpPatterns = [
            "what else", "what about", "how about", "and the", "more about",
            "tell me more", "anything else", "what other", "also", "too?",
        ]
        for pattern in followUpPatterns {
            if lower.contains(pattern) && !conversationContext.isEmpty {
                return .followUp
            }
        }

        // Pronoun ambiguity (only if we have context to resolve from)
        // CRITICAL: "this/that" + noun is NOT ambiguous ("this button" is clear)
        // Only flag demonstratives that stand alone ("what is this?")
        if !conversationContext.isEmpty {
            let queryWords = lower.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }

            // These are always ambiguous when present
            let alwaysAmbiguous = ["it", "they", "them"]
            for pronoun in alwaysAmbiguous {

                if queryWords.contains(pronoun) {
                    return .pronouns
                }
            }

            // Demonstratives (this/that/these/those) are only ambiguous when:
            // - They appear at the end of a sentence ("what is this?")
            // - They stand alone without a following noun
            let demonstratives = ["this", "that", "these", "those"]
            for (i, word) in queryWords.enumerated() {
                if demonstratives.contains(word) {
                    let isLastWord = (i == queryWords.count - 1)
                    let nextWordIsNoun = !isLastWord && !isStopWord(queryWords[i + 1])
                    // Only ambiguous if standalone (last word or followed by verb/stop word)
                    if isLastWord || !nextWordIsNoun {
                        return .pronouns
                    }
                    // "this button", "that document" - demonstrative + noun is CLEAR, don't rewrite
                }
            }
        }

        // Very short queries ONLY need rewriting if they look like follow-ups
        // A short content query like "Test", "oil weight", "summary" is perfectly valid
        // Only flag if the short query is pure stop-words with no content
        if words.count <= 2 && !conversationContext.isEmpty {
            let contentWords = words.filter { !isStopWord(String($0)) }
            if contentWords.isEmpty {
                // Pure stop-words like "and?" or "so?" — genuinely needs context
                return .tooShort
            }
            // Has content words (e.g., "Test", "oil specs") — this is a valid query, don't rewrite
        }

        return .none
    }

    // MARK: - LLM Clarification

    @MainActor
    private func clarifyWithLLM(
        query: String,
        ambiguityType: AmbiguityType,
        conversationContext: [ConversationTurn]
    ) async throws -> String {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *),
                  SystemLanguageModel.default.isAvailable
            else {
                throw QueryRewriterError.unavailable
            }

            if session == nil {
                // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
                // Every service that used the bare initialiser failed deterministically with
                // ParsingError / "Session ended without producing a response", while every path built
                // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
                // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
                // retrieved chunks, which rules out content, guardrails, context size and token caps.
                // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
                // these responses, consistent with a session that never received its model assets.
                session = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: Instructions("You rewrite search queries. Reply with the rewritten query only.")
                )
            }

            let prompt = buildClarificationPrompt(
                query: query,
                ambiguityType: ambiguityType,
                conversationContext: conversationContext
            )

            guard let activeSession = session else {
                return query
            }
            let response = try await activeSession.respond(to: prompt)
            let clarified = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            // Sanity check: result should be reasonable
            guard clarified.count > 3, clarified.count < 300 else {
                return query
            }

            return clarified
        #else
            throw QueryRewriterError.unavailable
        #endif
    }

    private func buildClarificationPrompt(
        query: String,
        ambiguityType: AmbiguityType,
        conversationContext: [ConversationTurn]
    ) -> String {
        var prompt = ""

        // Add conversation context
        if !conversationContext.isEmpty {
            prompt += "Conversation so far:\n"
            for turn in conversationContext.suffix(4) {
                let role = turn.role == "user" ? "User" : "Assistant"
                prompt += "\(role): \(String(turn.content.prefix(200)))\n"
            }
            prompt += "\n"
        }

        prompt += "Current question: \"\(query)\"\n\n"

        switch ambiguityType {
        case .pronouns:
            prompt += """
            The question contains pronouns (it/this/that/etc) that refer to something from the conversation.
            Rewrite the question replacing pronouns with what they refer to.
            Keep it natural and concise. Output only the rewritten question.

            CRITICAL: Do NOT introduce any nouns, entities, or concepts not explicitly present in the conversation.
                If the pronoun has no clear referent in the context above, leave the original wording unchanged.
            """
        case .followUp:
            prompt += """
            This is a follow-up question. Make it standalone by incorporating the relevant context.
            Keep it natural and concise. Output only the rewritten question.

            CRITICAL: Do NOT introduce any nouns, entities, or concepts not explicitly present in the conversation.
                If the pronoun has no clear referent in the context above, leave the original wording unchanged.
            """
        case .tooShort:
            prompt += """
            This question is very brief and appears to lack context.
            If it CLEARLY refers to something specific in the conversation above, incorporate that context.
            Otherwise, output it EXACTLY as-is — do NOT guess, rephrase, or add meaning.
            Never ask if the user made a mistake. Never question the query itself.
            Output only the question.

            CRITICAL: Do NOT introduce any nouns, entities, or concepts not explicitly present in the conversation.
                If the meaning is unclear, return the original query unchanged.
            """
        case .none:
            return query
        }

        return prompt
    }

    // MARK: - Simple Fallback

    private func simplePronounSubstitution(
        query: String,
        conversationContext: [ConversationTurn]
    ) -> String {
        guard !conversationContext.isEmpty else { return query }

        // Extract nouns from recent assistant responses
        let recentNouns = conversationContext
            .filter { $0.role == "assistant" }
            .suffix(2)
            .flatMap { extractEntities($0.content) }
            .prefix(3)

        guard let firstNoun = recentNouns.first else { return query }

        // Simple replacement of common pronouns
        var result = query
        let pronouns = ["it", "this", "that"]

        for pronoun in pronouns {
            let pattern = "\\b\(pronoun)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                if regex.firstMatch(in: result, range: range) != nil {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: range,
                        withTemplate: firstNoun
                    )
                    break // Only replace one pronoun
                }
            }
        }

        return result
    }

    // MARK: - Intent Detection

    private func detectIntent(_ query: String) -> SemanticIntent {
        let lower = query.lowercased()

        if lower.hasPrefix("how do") || lower.hasPrefix("how to") || lower.hasPrefix("how can") {
            return .howTo
        }
        if lower.hasPrefix("what is") || lower.hasPrefix("what are") || lower.hasPrefix("what does") {
            return .whatIs
        }
        if lower.hasPrefix("why") { return .why }
        if lower.hasPrefix("when") { return .when }
        if lower.hasPrefix("where") { return .where_ }
        if lower.contains("compare") || lower.contains("difference") || lower.contains(" vs ") {
            return .comparison
        }
        if lower.contains("problem") || lower.contains("error") || lower.contains("not working") || lower.contains("fix") {
            return .troubleshoot
        }
        if lower.hasPrefix("list") || lower.contains("what are the") {
            return .list
        }
        if lower.contains("else") || lower.contains("more") || lower.contains("also") {
            return .followUp
        }

        return .unknown
    }

    // MARK: - Entity Extraction

    private func extractEntities(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var entities: [String] = []

        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard let tag = tag, tag == .noun else { return true }
            let word = String(text[range])
            if word.count > 2 {
                entities.append(word)
            }
            return true
        }

        return entities
    }

    private func extractConversationEntities(from turns: [ConversationTurn]) -> [String] {
        var entities: [String] = []
        for turn in turns.suffix(3) {
            entities.append(contentsOf: turn.entities)
            entities.append(contentsOf: extractEntities(turn.content))
        }
        var seen = Set<String>()
        return entities.filter { seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    }

    private func passthrough(_ query: String) -> RewrittenQuery {
        RewrittenQuery(
            original: query,
            rewritten: query,
            intent: detectIntent(query),
            entities: extractEntities(query),
            searchTerms: [],
            confidence: 1.0,
            wasRewritten: false,
            resolvedEntities: []
        )
    }
}

// MARK: - Errors

enum QueryRewriterError: Error, LocalizedError {
    case unavailable
    case rewriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Query rewriting unavailable"
        case let .rewriteFailed(reason):
            return "Query rewrite failed: \(reason)"
        }
    }
}
