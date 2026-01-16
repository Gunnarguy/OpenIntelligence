//
//  QueryEnhancementService.swift
//  OpenIntelligence
//
//  Query expansion and light reformulation to improve hybrid retrieval.
//

import Foundation
import NaturalLanguage

/// Vocabulary extracted from the corpus for context-aware query expansion.
struct CorpusVocabulary: Sendable {
    /// All keywords from all chunks, lowercased
    let keywords: Set<String>
    /// Co-occurrence map: term → terms that appear in the same chunk
    let coOccurrences: [String: Set<String>]
    /// Full text snippets for finding contextual phrases
    let textSnippets: [String]

    static let empty = CorpusVocabulary(keywords: [], coOccurrences: [:], textSnippets: [])
}

/// Classification of query intent for adaptive weight tuning.
enum QueryIntent: String, Sendable {
    /// Specific keyword lookup (e.g., "oil type", "error code 5W-30")
    /// → Heavily favor BM25 keyword matching
    case keyword

    /// Conceptual/semantic question (e.g., "how does the engine cooling system work")
    /// → Favor vector/embedding similarity
    case conceptual

    /// Balanced mix of both (e.g., "what maintenance is needed for the 2.0L engine")
    case balanced

    /// Suggested weight adjustments for hybrid search
    var weightAdjustment: (vectorDelta: Float, keywordDelta: Float) {
        switch self {
        case .keyword:
            return (vectorDelta: -0.15, keywordDelta: +0.15) // Boost BM25 significantly
        case .conceptual:
            return (vectorDelta: +0.15, keywordDelta: -0.15) // Boost vector similarity
        case .balanced:
            return (vectorDelta: 0, keywordDelta: 0) // Use default weights
        }
    }
}

/// Enhances user queries before retrieval.
///
/// This service must be silent-by-default: do not use direct `print()`.
/// Route diagnostic output through `Log.*` so verbosity is gated.
final class QueryEnhancementService {

    /// Corpus vocabulary for context-aware expansion (optional)
    private let corpusVocabulary: CorpusVocabulary?

    init(corpusVocabulary: CorpusVocabulary? = nil) {
        self.corpusVocabulary = corpusVocabulary
    }

    // MARK: - Query Intent Classification

    /// Classifies query intent to enable adaptive weight tuning.
    ///
    /// This analyzes the query structure to determine whether it's:
    /// - **Keyword-heavy**: Looking for specific terms, codes, values (boost BM25)
    /// - **Conceptual**: Asking about processes, explanations (boost vectors)
    /// - **Balanced**: Mix of both
    func classifyIntent(_ query: String) -> QueryIntent {
        let lower = query.lowercased()
        let words = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)

        // Signals for keyword-heavy queries
        var keywordSignals = 0
        var conceptualSignals = 0

        // 1. Contains numbers, codes, or specific identifiers
        if lower.rangeOfCharacter(from: .decimalDigits) != nil {
            keywordSignals += 2
        }

        // 2. Contains technical patterns (model numbers, part codes)
        let technicalPatterns = [
            #"[A-Z0-9]{2,}-[A-Z0-9]{2,}"#, // Part numbers like "5W-30", "A-123"
            #"\d+[wW][-]?\d+"#, // Oil grades like "5W30", "10W-40"
            #"[A-Z]{2,}\d+"#, // Model codes like "VQ35", "K24"
        ]
        for pattern in technicalPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                keywordSignals += 2
            }
        }

        // 3. Short, specific queries (1-4 words, no question words)
        let questionWords: Set<String> = ["how", "why", "what", "when", "where", "which", "explain", "describe"]
        let hasQuestionWord = words.first.map { questionWords.contains($0) } ?? false

        if words.count <= 4 && !hasQuestionWord {
            keywordSignals += 1
        }

        // 4. Contains exact lookup terms
        let lookupTerms: Set<String> = [
            "type", "code", "number", "spec", "specification", "model", "part",
            "size", "capacity", "weight", "dimension", "torque", "pressure",
            "voltage", "amperage", "wattage", "rating", "grade",
        ]
        for word in words {
            if lookupTerms.contains(word) {
                keywordSignals += 1
            }
        }

        // Signals for conceptual queries
        // 1. Question words asking for explanation
        let explanationWords: Set<String> = ["how", "why", "explain", "describe", "understand", "work", "works", "function", "functions"]
        for word in words {
            if explanationWords.contains(word) {
                conceptualSignals += 2
            }
        }

        // 2. Process/system words
        let processWords: Set<String> = [
            "process", "system", "mechanism", "procedure", "method", "approach",
            "principle", "concept", "theory", "operation", "workflow",
        ]
        for word in words {
            if processWords.contains(word) {
                conceptualSignals += 1
            }
        }

        // 3. Longer queries with context (usually more conceptual)
        if words.count >= 8 {
            conceptualSignals += 1
        }

        // Classify based on signal balance
        let balance = keywordSignals - conceptualSignals
        let intent: QueryIntent
        if balance >= 2 {
            intent = .keyword
        } else if balance <= -2 {
            intent = .conceptual
        } else {
            intent = .balanced
        }

        Log.debug(
            "[QueryEnhancement] Intent: \(intent.rawValue) (keyword=\(keywordSignals), conceptual=\(conceptualSignals))",
            category: .retrieval
        )

        return intent
    }

    /// Produces a small set of query variants for keyword-heavy retrieval (BM25).
    /// - Note: The first element is always the original query (trimmed).
    func expandQuery(_ query: String) -> [String] {
        let original = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        Log.debug("[QueryEnhancement] Expanding query", category: .retrieval)

        var variations: [String] = [original]

        // 1) Extract key terms for synonym lookup.
        let keyTerms = extractKeyTerms(original)
        if !keyTerms.isEmpty {
            Log.debug("[QueryEnhancement] Key terms: \(keyTerms.joined(separator: ", "))", category: .retrieval)
        }

        // 1.5) Corpus-aware expansion: find related terms from the actual documents
        if let vocab = corpusVocabulary {
            let corpusExpansions = expandFromCorpus(keyTerms: keyTerms, query: original, vocabulary: vocab)
            if !corpusExpansions.isEmpty {
                Log.debug("[QueryEnhancement] Corpus expansions: \(corpusExpansions.joined(separator: ", "))", category: .retrieval)
                variations.append(contentsOf: corpusExpansions)
            }
        }

        // 2) Handle trivial/underspecified queries (helps BM25 avoid empty-ish inputs).
        let tokenCount = original.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let lower = original.lowercased()
        let trivialSet: Set<String> = [
            "test", "help", "hello", "hi", "hey", "ok", "okay", "thanks", "thank you",
        ]
        if tokenCount <= 1 || keyTerms.isEmpty || trivialSet.contains(lower) {
            variations.append("\(original) overview")
            variations.append("\(original) summary")
            variations.append("\(original) introduction")
            variations.append("overview")
            variations.append("summary")
            Log.debug("[QueryEnhancement] Trivial input detected; added generic boost terms", category: .retrieval)
            return uniquePreservingOrder(variations, max: 8)
        }

        // 3) Synonym-based expansions.
        let synonyms = generateSynonyms(for: keyTerms)
        if !synonyms.isEmpty {
            Log.debug("[QueryEnhancement] Synonym groups: \(synonyms.count)", category: .retrieval)

            // Replace key terms with synonyms (limited to keep the query compact).
            for (term, syns) in synonyms {
                for syn in syns.prefix(2) {
                    let expanded = original.replacingOccurrences(of: term, with: syn, options: .caseInsensitive)
                    if expanded != original {
                        variations.append(expanded)
                    }
                }
            }

            // Append a few synonyms (bag-of-words style).
            let allSynonyms = synonyms.values.flatMap { $0 }.prefix(3)
            if !allSynonyms.isEmpty {
                variations.append("\(original) \(allSynonyms.joined(separator: " "))")
            }
        }

        // 4) Simple question reformulations.
        if original.contains("?") {
            variations.append(contentsOf: reformulateQuestion(original))
        }

        let result = uniquePreservingOrder(variations, max: 12)
        Log.debug("[QueryEnhancement] Produced \(result.count) variations", category: .retrieval)
        return result
    }

    /// Extracts key terms (nouns/verbs/adjectives) using `NaturalLanguage`.
    private func extractKeyTerms(_ query: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = query

        var terms: [String] = []
        var seen = Set<String>()

        tagger.enumerateTags(
            in: query.startIndex..<query.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            // NOTE: NLTagger.Options no longer includes `.omitStopWords` on newer SDKs.
            // We already filter by lexical class (noun/verb/adjective), which naturally
            // excludes most stop words.
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard let tag else { return true }
            guard tag == .noun || tag == .verb || tag == .adjective else { return true }

            let token = String(query[range])
            guard token.count > 2 else { return true }

            let key = token.lowercased()
            if seen.insert(key).inserted {
                terms.append(token)
            }
            return true
        }

        return terms
    }

    /// Very small, domain-oriented synonym map.
    ///
    /// This is intentionally conservative (no heavy NLP / embeddings) to keep expansion cheap.
    private func generateSynonyms(for terms: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]

        let synonymDict: [String: [String]] = [
            "clean": ["sanitize", "disinfect", "sterilize", "wash"],
            "use": ["operate", "utilize", "employ", "apply"],
            "device": ["instrument", "equipment", "apparatus", "tool"],
            "procedure": ["process", "method", "protocol", "technique"],
            "patient": ["individual", "subject", "person"],
            "doctor": ["physician", "surgeon", "clinician", "practitioner"],
            "remove": ["detach", "disconnect", "separate", "extract"],
            "install": ["attach", "connect", "mount", "affix"],
            "check": ["verify", "inspect", "examine", "test"],
            "warning": ["caution", "alert", "notice", "advisory"],
            // UI/hardware controls
            "button": ["switch", "toggle", "control", "key", "trigger"],
            "press": ["tap", "click", "push", "activate", "toggle"],
            "pressing": ["tapping", "clicking", "pushing", "activating", "toggling"],
            "click": ["tap", "press", "select", "activate"],
            "start": ["begin", "initiate", "launch", "enable", "activate"],
            "stop": ["end", "disable", "deactivate", "halt", "pause"],
        ]

        for term in terms {
            let lower = term.lowercased()
            if let syns = synonymDict[lower], !syns.isEmpty {
                result[term] = syns
            }
        }

        return result
    }

    /// Reformulates common question patterns into statement/keyword forms.
    private func reformulateQuestion(_ query: String) -> [String] {
        var reformulations: [String] = []

        let patterns: [(pattern: String, replacement: String)] = [
            ("^How do I ", "instructions for "),
            ("^How to ", "procedure for "),
            ("^What is ", "information about "),
            ("^What are ", "details on "),
            ("^When should ", "timing for "),
            ("^Why ", "reason for "),
            ("^Can I ", "possibility of "),
            ("^Where ", "location of "),
        ]

        for (pattern, replacement) in patterns {
            if let range = query.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                var s = query
                s.replaceSubrange(range, with: replacement)
                s = s.replacingOccurrences(of: "?", with: "")
                reformulations.append(s)
            }
        }

        return reformulations
    }

    /// De-duplicates case-insensitively while preserving order.
    private func uniquePreservingOrder(_ strings: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for s in strings {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
                if out.count >= max {
                    break
                }
            }
        }
        return out
    }

    // MARK: - Corpus-Aware Expansion

    /// Expands query using terms that co-occur with query terms in the actual corpus.
    ///
    /// This is the key to understanding context: when user says "button", we look at
    /// what other terms appear alongside "button" in the documents (e.g., "Record Button",
    /// "toggle", "press", "hold", etc.)
    private func expandFromCorpus(
        keyTerms: [String],
        query: String,
        vocabulary: CorpusVocabulary
    ) -> [String] {
        var expansions: [String] = []
        let queryLower = query.lowercased()

        // 1) Find corpus terms that co-occur with query terms
        var relatedTerms: [String: Int] = [:] // term → frequency boost
        for term in keyTerms {
            let termLower = term.lowercased()
            if let coTerms = vocabulary.coOccurrences[termLower] {
                for coTerm in coTerms {
                    // Skip if it's already in the query
                    guard !queryLower.contains(coTerm) else { continue }
                    // Filter out garbage terms from noisy PDF extraction
                    guard isValidExpansionTerm(coTerm) else { continue }
                    relatedTerms[coTerm, default: 0] += 1
                }
            }
        }

        // 2) Sort by frequency (terms that co-occur with multiple query terms are better)
        let topRelated = relatedTerms
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { $0.key }

        if !topRelated.isEmpty {
            // Add query + corpus-derived context terms
            expansions.append("\(query) \(topRelated.joined(separator: " "))")

            // Also add targeted variations with top 2-3 related terms
            for relatedTerm in topRelated.prefix(3) {
                expansions.append("\(query) \(relatedTerm)")
            }
        }

        // 3) Find multi-word phrases in the corpus that contain query terms
        // e.g., "button" → "Record Button", "Recording Mode Switch"
        let phraseExpansions = findCorpusPhrases(keyTerms: keyTerms, vocabulary: vocabulary)
        for phrase in phraseExpansions.prefix(4) {
            // Replace the generic term with the specific phrase
            expansions.append(phrase)
        }

        return expansions
    }

    /// Finds multi-word phrases in the corpus that contain any of the query terms.
    ///
    /// For example, if user asks about "button", this finds phrases like:
    /// - "Record Button"
    /// - "Recording Mode Switch"
    /// - "toggle down the Recording Mode Switch"
    private func findCorpusPhrases(keyTerms: [String], vocabulary: CorpusVocabulary) -> [String] {
        var phrases: Set<String> = []
        let keyTermsLower = Set(keyTerms.map { $0.lowercased() })

        // Common action words that indicate physical interaction
        let actionWords: Set<String> = [
            "press", "push", "hold", "toggle", "slide", "tap", "click",
            "switch", "turn", "activate", "enable", "disable", "start", "stop",
        ]

        for snippet in vocabulary.textSnippets {
            let snippetLower = snippet.lowercased()

            // Check if snippet contains any of our key terms
            for term in keyTermsLower {
                guard snippetLower.contains(term) else { continue }

                // Extract phrases around the term (simple window approach)
                let words = snippet.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .map { String($0) }

                for (i, word) in words.enumerated() {
                    let wordLower = word.lowercased()
                        .trimmingCharacters(in: .punctuationCharacters)

                    if wordLower == term || actionWords.contains(wordLower) {
                        // Extract a 3-5 word window around this word
                        let start = max(0, i - 2)
                        let end = min(words.count, i + 3)
                        let phrase = words[start ..< end]
                            .joined(separator: " ")
                            .trimmingCharacters(in: .punctuationCharacters)

                        // Only keep phrases that look meaningful (have capitalized nouns, etc.)
                        // Also validate each word in the phrase
                        if phrase.count > 10, phrase.count < 60,
                           isValidExpansionPhrase(phrase)
                        {
                            phrases.insert(phrase)
                        }
                    }
                }
            }
        }

        // Sort by length (prefer shorter, more specific phrases)
        return phrases.sorted { $0.count < $1.count }
    }

    // MARK: - Expansion Term Validation

    /// Filters out garbage terms from noisy PDF extraction.
    /// Rejects hyphenated fragments, too-short tokens, and stopword phrases.
    private func isValidExpansionTerm(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject empty or too short
        guard trimmed.count >= 3 else { return false }

        // Reject hyphenated fragments (e.g., "sys-", "-tem", "manu-")
        if trimmed.hasPrefix("-") || trimmed.hasSuffix("-") {
            return false
        }

        // Reject terms with embedded hyphens that look like line-break artifacts
        // e.g., "sys- tem" or "manu- al" (note the space after hyphen)
        if trimmed.contains("- ") || trimmed.contains(" -") {
            return false
        }

        // Reject common stopword phrases
        let stopPhrases: Set<String> = [
            "the", "and", "or", "is", "are", "was", "were", "be", "been",
            "if", "of", "to", "for", "with", "on", "at", "by", "from",
            "turn off the", "switch with the", "or if", "and the",
        ]
        if stopPhrases.contains(trimmed.lowercased()) {
            return false
        }

        // Reject if majority is non-alphanumeric
        let alphanumericCount = trimmed.filter { $0.isLetter || $0.isNumber }.count
        if Float(alphanumericCount) / Float(trimmed.count) < 0.6 {
            return false
        }

        return true
    }

    /// Validates an entire phrase extracted from corpus snippets.
    private func isValidExpansionPhrase(_ phrase: String) -> Bool {
        let words = phrase.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return false }

        // All words must be valid
        for word in words {
            if !isValidExpansionTerm(String(word)) {
                return false
            }
        }

        return true
    }
}

// MARK: - Corpus Vocabulary Builder

extension CorpusVocabulary {
    /// Builds vocabulary from document chunks for corpus-aware query expansion.
    ///
    /// This extracts:
    /// 1. All keywords from chunk metadata
    /// 2. Co-occurrence relationships (which terms appear together)
    /// 3. Text snippets for phrase extraction
    static func build(from chunks: [DocumentChunk]) -> CorpusVocabulary {
        guard !chunks.isEmpty else { return .empty }

        var allKeywords: Set<String> = []
        var coOccurrences: [String: Set<String>] = [:]
        var textSnippets: [String] = []

        for chunk in chunks {
            // Collect keywords
            let chunkKeywords = Set(chunk.metadata.keywords.map { $0.lowercased() })
            allKeywords.formUnion(chunkKeywords)

            // Build co-occurrence map (terms that appear in the same chunk are related)
            for keyword in chunkKeywords {
                var related = coOccurrences[keyword] ?? []
                related.formUnion(chunkKeywords)
                related.remove(keyword) // Don't include self
                coOccurrences[keyword] = related
            }

            // Keep short text snippets for phrase extraction (first 500 chars)
            let snippet = String(chunk.content.prefix(500))
            textSnippets.append(snippet)
        }

        Log.debug(
            "[CorpusVocabulary] Built vocabulary: \(allKeywords.count) terms, \(coOccurrences.count) co-occurrence entries",
            category: .retrieval
        )

        return CorpusVocabulary(
            keywords: allKeywords,
            coOccurrences: coOccurrences,
            textSnippets: textSnippets
        )
    }
}
