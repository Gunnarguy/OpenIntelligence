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
            return (vectorDelta: +0.20, keywordDelta: -0.20) // Boost vector similarity for semantic/behavioral questions
        case .balanced:
            return (vectorDelta: 0, keywordDelta: 0) // Use default weights
        }
    }
}

// MARK: - AppleRAG Answer Intent (§6 of AppleRAG Spec)

/// Answer intent classification per AppleRAG spec §6.
/// Determines the answering strategy: extractive vs abstractive, single vs multi-hop.
enum AnswerIntent: String, Sendable, CaseIterable {
    /// Direct fact lookup - run extractive QA on packed context → best span
    /// Example: "What is the oil capacity?" → "5.7 quarts [S1]"
    case lookup

    /// Table-specific lookup - retrieve table_row then extract target cell(s)
    /// Example: "What are the torque specs for head bolts?"
    case tableLookup = "table_lookup"

    /// Step-by-step procedure - output ordered list_item nodes + headings (preserve order)
    /// Example: "How do I change the oil?" → ordered steps from source
    case procedure

    /// Side-by-side comparison - retrieve evidence for A and B separately
    /// Example: "Compare synthetic vs conventional oil"
    case compare

    /// Extractive summarization - sentence selection via bi-encoder similarity
    /// Example: "Summarize the maintenance schedule"
    case summarize

    /// Multi-hop investigation - answer = "evidence map" + extracted sub-facts
    /// Example: "What factors affect engine longevity?"
    case investigate

    /// Numerical computation from extracted values
    /// Example: "What's the total fluid capacity?" (sum multiple values)
    case compute

    /// Research findings / author discovery - requires document-level context
    /// Example: "What did Orfitelli find?" → needs summary + key sections
    /// GOD MODE: Auto-injects document summary for comprehensive context
    case findings

    /// Maps to QueryIntent for hybrid search weight adjustment
    var searchIntent: QueryIntent {
        switch self {
        case .lookup, .tableLookup, .compute:
            return .keyword  // Favor exact matches
        case .procedure:
            return .balanced  // Need structure + content
        case .compare, .investigate, .findings:
            return .conceptual  // Need semantic understanding
        case .summarize:
            return .conceptual  // Need broad coverage
        }
    }

    /// Whether this intent should use extractive-first answering (spec rescue, HyDE disabled)
    /// Only for lookup/tableLookup where the answer is a literal value in a spec table.
    /// Procedure is NOT extractive — "what does pressing the button do?" needs behavioral
    /// descriptions, not specification tables.
    var isExtractiveFirst: Bool {
        switch self {
        case .lookup, .tableLookup:
            return true  // Direct extraction from source (e.g., "SAE 0W-20")
        case .procedure, .compare, .summarize, .investigate, .compute, .findings:
            return false  // Needs synthesis or behavioral descriptions
        }
    }

    /// Whether this intent benefits from multi-hop retrieval
    var benefitsFromMultiHop: Bool {
        switch self {
        case .investigate, .compare, .findings:
            return true
        case .lookup, .tableLookup, .procedure, .summarize, .compute:
            return false
        }
    }

    /// Whether this intent should auto-inject document summary (L1) chunks
    /// GOD MODE: Ensures document-level context is always available
    var requiresDocumentSummary: Bool {
        switch self {
        case .findings, .summarize, .investigate:
            return true  // Need document-level context
        case .lookup, .tableLookup, .procedure, .compare, .compute:
            return false  // Detail chunks sufficient
        }
    }

    /// Whether this is an author/research query pattern
    var isAuthorQuery: Bool {
        self == .findings
    }

    /// Structure type boost for this intent
    var structureTypeBoost: String? {
        switch self {
        case .tableLookup:
            return "table"
        case .procedure:
            return "list"
        case .findings:
            return nil  // No structure bias - need broad coverage
        default:
            return nil
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
        let rawWords = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)

        // Normalize words: strip punctuation, expand contractions
        // "what's" → "what", "do?" → "do", "it's" → "it"
        let words = rawWords.map { word -> String in
            var w = word.trimmingCharacters(in: .punctuationCharacters)
            // Handle 's contractions with ANY apostrophe variant:
            // U+0027 ' (straight), U+2019 ' (curly/smart from iOS keyboard),
            // U+2018 ' (left single), U+FF07 (fullwidth)
            // Character-agnostic: check if word ends in (non-letter)(s)
            if w.count >= 3 && w.hasSuffix("s") {
                let idx = w.index(w.endIndex, offsetBy: -2)
                let charBeforeS = w[idx]
                if !charBeforeS.isLetter && !charBeforeS.isNumber {
                    w = String(w.dropLast(2))
                }
            }
            return w
        }.filter { !$0.isEmpty }

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

        // 4. Behavioral question patterns: "what does X do", "what happens when"
        // These ask about function/behavior → strongly conceptual
        let firstWord = words.first ?? ""
        let lastWord = words.last ?? ""
        if firstWord == "what" && (lastWord == "do" || lastWord == "does" || lastWord == "happen" || lastWord == "happens") {
            conceptualSignals += 2
        }
        // "how does X work", "what does X do" mid-sentence patterns
        if lower.contains("what does") || lower.contains("what do") || lower.contains("how does") || lower.contains("what happens") {
            conceptualSignals += 2
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

    // MARK: - Answer Intent Classification (AppleRAG §6)

    /// Classifies query into answer intent per AppleRAG spec §6.
    /// Determines the answering strategy: extractive vs abstractive, single vs multi-hop.
    ///
    /// Intent hierarchy:
    /// 0. **findings**: Author/research discovery (what did X find/discover/show) - GOD MODE
    /// 1. **lookup**: Direct fact extraction (what, which, when + specific entity)
    /// 2. **table_lookup**: Table-specific queries (specs, comparisons in tables)
    /// 3. **procedure**: Step-by-step instructions (how to, steps, procedure)
    /// 4. **compare**: Side-by-side comparison (vs, compare, difference)
    /// 5. **summarize**: Overview/summary requests
    /// 6. **investigate**: Multi-hop research (factors, causes, effects)
    /// 7. **compute**: Numerical computation (total, sum, calculate)
    func classifyAnswerIntent(_ query: String) -> AnswerIntent {
        let lower = query.lowercased()
        let words = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)

        // Priority 0: FINDINGS (GOD MODE) - author/research discovery queries
        // These need document-level context, not just detail chunks
        let findingsPatterns: [String] = [
            "what did .* find", "what did .* discover", "what did .* show",
            "what did .* demonstrate", "what did .* prove", "what did .* conclude",
            "what does .* find", "what does .* show", "what does .* argue",
            "what were .* findings", "what are .* findings", "findings of",
            "what .* concluded", "what .* discovered", "what .* found",
            "according to .*'s research", ".*'s main argument", ".*'s thesis",
            "what is .*'s contribution", "what did .* contribute",
            "research by", "study by", "paper by", "article by",
            ".*'s key finding", ".*'s discovery", ".*'s conclusion"
        ]
        for pattern in findingsPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                Log.debug("[QueryEnhancement] 🔥 GOD MODE: Detected findings/author query pattern: '\(pattern)'", category: .retrieval)
                return .findings
            }
        }

        // Also detect simple author-finding patterns without regex
        let simpleFindingsPatterns: [String] = [
            "what did", "findings", "conclude", "discovered", "contribution",
            "main argument", "thesis", "demonstrated"
        ]
        let authorIndicators: [String] = ["find", "show", "argue", "discover", "prove", "demonstrate"]
        let hasAuthorIndicator = authorIndicators.contains { lower.contains($0) }

        // If query has a capitalized word (likely author name) + finding indicator
        let hasCapitalizedWord = query.split(separator: " ").contains { word in
            guard let first = word.first else { return false }
            return first.isUppercase && word.count > 2
        }

        if hasCapitalizedWord && hasAuthorIndicator {
            for pattern in simpleFindingsPatterns {
                if lower.contains(pattern) {
                    Log.debug("[QueryEnhancement] 🔥 GOD MODE: Author + finding pattern detected", category: .retrieval)
                    return .findings
                }
            }
        }

        // Priority 1: Compute (requires numerical aggregation)
        let computePatterns: [String] = [
            "total", "sum", "add up", "calculate", "compute", "how much total",
            "combined", "altogether", "in total"
        ]
        for pattern in computePatterns {
            if lower.contains(pattern) { return .compute }
        }

        // Priority 2: Compare (explicit comparison request)
        let comparePatterns: [String] = [
            " vs ", "versus", "compare", "comparison", "difference between",
            "differences between", "differ from", "better than", "worse than",
            "pros and cons", "advantages", "disadvantages"
        ]
        for pattern in comparePatterns {
            if lower.contains(pattern) { return .compare }
        }

        // Priority 3: Procedure (step-by-step instructions)
        let procedurePatterns: [String] = [
            "how to", "how do i", "how can i", "steps to", "procedure for",
            "instructions for", "guide to", "process for", "way to",
            "method for", "directions for"
        ]
        for pattern in procedurePatterns {
            if lower.contains(pattern) { return .procedure }
        }

        // Priority 4: Summarize (overview/summary requests)
        let summarizePatterns: [String] = [
            "summarize", "summary", "overview", "brief", "outline",
            "main points", "key points", "highlights", "recap", "tldr"
        ]
        for pattern in summarizePatterns {
            if lower.contains(pattern) { return .summarize }
        }

        // Priority 5a: Behavioral/functional → procedure (action-reaction answers)
        // "What does pressing the button do?" / "What's X do?" / "X does what?"
        // These ask "when I do X, what happens?" — sequential procedural answers,
        // NOT multi-hop research. Routing to .investigate would trigger iterative
        // retrieval passes that fragment the answer across unrelated chunks.
        let behavioralPatterns: [String] = [
            // "pressing button does what", "the switch does what"
            "does what", "do what",
            // "what happens if/when I press X"
            "happens if", "happens when",
            // "function of X", "purpose of X", "X is used for"
            "function of", "purpose of", "used for",
            // Regex: "what does X do", "what's X do", "what will X do", "what can X do"
            "what does .* do", "what will .* do", "what can .* do",
            "what's .* do"
        ]
        for pattern in behavioralPatterns {
            if pattern.contains(".*"), let _ = lower.range(of: pattern, options: .regularExpression) {
                Log.debug("[QueryEnhancement] Behavioral regex → procedure: '\(pattern)'", category: .retrieval)
                return .procedure
            }
            if lower.contains(pattern) {
                Log.debug("[QueryEnhancement] Behavioral pattern → procedure: '\(pattern)'", category: .retrieval)
                return .procedure
            }
        }

        // Priority 5c: Enumeration queries → summarize (NOT lookup)
        // "List all X", "List every X", "What are all the X", "Name every X"
        // These require LLM synthesis across multiple chunks, not single-value extraction.
        // MUST be checked BEFORE lookup/tableLookup/embedded patterns, which would
        // short-circuit to ExtractiveQA and return a single value like "SPY-PHI"
        // when the user wants a comprehensive listing of ALL matching values.
        let enumerationPatterns: [String] = [
            "list all", "list every", "list the", "list each",
            "name all", "name every", "name each",
            "what are all", "what are every",
            "show all", "show every", "show each",
            "give me all", "give me every",
            "enumerate", "all the .* numbers", "all .* reference",
        ]
        for pattern in enumerationPatterns {
            if pattern.contains(".*"), let _ = lower.range(of: pattern, options: .regularExpression) {
                Log.debug("[QueryEnhancement] Enumeration regex → summarize: '\(pattern)'", category: .retrieval)
                return .summarize
            }
            if lower.contains(pattern) {
                Log.debug("[QueryEnhancement] Enumeration pattern → summarize: '\(pattern)'", category: .retrieval)
                return .summarize
            }
        }

        // Priority 5b: Investigate (multi-hop research requiring iterative retrieval)
        let investigatePatterns: [String] = [
            "factors", "causes", "reasons", "why does", "why is", "why are",
            "what affects", "what influences", "implications", "consequences",
            "relationship between", "how does .* affect", "what happens when"
        ]
        for pattern in investigatePatterns {
            if pattern.contains(".*"), let _ = lower.range(of: pattern, options: .regularExpression) {
                Log.debug("[QueryEnhancement] Matched investigate regex: '\(pattern)'", category: .retrieval)
                return .investigate
            }
            if lower.contains(pattern) { return .investigate }
        }

        // BEHAVIORAL CATCH-ALL: Any query starting with "what" and ending with "do"
        // (optionally with trailing punctuation) is asking about behavior/function.
        // Examples: "What's pressing the button do?", "What does the power button do"
        // Routes to .procedure because these ask "what happens when I do X" — sequential
        // action-reaction answers, NOT multi-hop research (.investigate would trigger
        // iterative retrieval and fragment the answer across multiple search passes).
        let trimmedLower = lower.trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
        if trimmedLower.hasPrefix("what") && trimmedLower.hasSuffix(" do") {
            Log.debug("[QueryEnhancement] Behavioral catch-all: starts with 'what', ends with 'do' → procedure", category: .retrieval)
            return .procedure
        }

        // Priority 6: Table lookup (table-specific queries)
        let tablePatterns: [String] = [
            "table", "spec", "specification", "chart", "matrix", "grid",
            "torque value", "pressure value", "capacity"
        ]
        let tableIndicators = ["what is the", "what are the", "list the", "show the"]
        let hasTableIndicator = tableIndicators.contains { lower.contains($0) }
        for pattern in tablePatterns {
            if lower.contains(pattern) && hasTableIndicator { return .tableLookup }
        }

        // Also detect structured data queries without explicit "table" mention
        let structuredPatterns = [
            #"\d+\s*(psi|nm|ft-?lb|quart|liter|ml|mm|inch)"#,  // Units
            #"specification|rating|tolerance|range"#
        ]
        for pattern in structuredPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                return .tableLookup
            }
        }

        // Default: lookup (simple fact extraction)
        // Most "what", "which", "when", "where" questions are lookups
        let lookupStarters = ["what", "which", "when", "where", "who", "how much", "how many", "wat"]  // Include common typo "wat"
        for starter in lookupStarters {
            if lower.hasPrefix(starter) { return .lookup }
        }

        // CRITICAL: Detect "what is the X" patterns ANYWHERE in the query (not just at start)
        // Queries like "1688 Stryker camera head what is the reference number?" should be LOOKUP
        let embeddedLookupPatterns: [String] = [
            "what is the", "what are the", "what's the",
            "reference number", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku"
        ]
        for pattern in embeddedLookupPatterns {
            if lower.contains(pattern) {
                Log.debug("[QueryEnhancement] Detected embedded lookup pattern: '\(pattern)'", category: .retrieval)
                return .lookup
            }
        }

        // CRITICAL FIX: Detect specification lookup patterns that may not start with lookup words
        // "type of oil", "kind of fluid", "grade of", etc. are clearly looking for specific values
        let specLookupPatterns: [String] = [
            "type of", "kind of", "grade of", "brand of", "model of",
            "oil", "fluid", "coolant", "fuel", "gasoline", "diesel",
            "capacity", "weight", "pressure", "viscosity",
            "does this car take", "does this vehicle take", "should i use"
        ]
        for pattern in specLookupPatterns {
            if lower.contains(pattern) {
                Log.debug("[QueryEnhancement] Detected spec lookup pattern: '\(pattern)'", category: .retrieval)
                return .lookup
            }
        }

        // Fallback for short queries
        if words.count <= 5 { return .lookup }

        // For longer conceptual queries, default to investigate
        return .investigate
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
            // OPTIMIZED: Only add query-prefixed expansions — bare "overview"/"summary"
            // matched unrelated chunks across the entire corpus, diluting precision
            variations.append("\(original) overview")
            variations.append("\(original) summary")
            variations.append("\(original) details")
            Log.debug("[QueryEnhancement] Trivial input detected; added scoped boost terms", category: .retrieval)
            return uniquePreservingOrder(variations, max: 6)
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

        // OPTIMIZED: Filter key terms through question-framing stopwords before
        // corpus lookup. "type", "does", "car", "take" produce massive co-occurrence
        // sets that pull in irrelevant terms ("indicator lights", "lamp", "fuse").
        // Only look up substantive content words.
        let corpusStopwords: Set<String> = [
            "type", "kind", "sort", "take", "use", "does", "car", "vehicle",
            "get", "find", "tell", "know", "look", "want", "like", "make",
            "put", "give", "help", "work", "come", "thing", "much", "many",
            "way", "long", "need", "require"
        ]
        let substantiveTerms = keyTerms.filter { !corpusStopwords.contains($0.lowercased()) }

        // 1) Find corpus terms that co-occur with query terms
        var relatedTerms: [String: Int] = [:] // term → frequency boost
        for term in substantiveTerms {
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
        // OPTIMIZED: Use substantiveTerms, not raw keyTerms. Previously "type" matched
        // "lamp (LED type" and "car" matched unrelated phrases.
        let phraseExpansions = findCorpusPhrases(keyTerms: substantiveTerms, vocabulary: vocabulary)
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

        // OPTIMIZED: Reject non-Latin script characters (OCR artifacts like CJK, Arabic, etc.)
        // These come from noisy PDF extraction and pollute expansions (e.g., "notice 僅")
        let latinCount = trimmed.filter { $0.isASCII && $0.isLetter }.count
        let letterCount = trimmed.filter { $0.isLetter }.count
        if letterCount > 0 && Float(latinCount) / Float(letterCount) < 0.8 {
            return false
        }

        // Reject terms with embedded digits that look like OCR noise (e.g., "SENSOR4", "10A")
        // But allow known spec patterns like "SAE" or "API"
        let knownSpecPrefixes: Set<String> = ["sae", "api", "iso", "dot", "fmvss", "acea", "ilsac"]
        if !knownSpecPrefixes.contains(trimmed.lowercased()),
           trimmed.contains(where: { $0.isNumber }),
           trimmed.contains(where: { $0.isLetter }),
           trimmed.count <= 8 {
            // Short alphanumeric tokens like "SENSOR4", "10A" are likely noise
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
    /// 4. Adjective+noun pairs from text (e.g., "blue outlet", "red button")
    static func build(from chunks: [DocumentChunk]) -> CorpusVocabulary {
        guard !chunks.isEmpty else { return .empty }

        var allKeywords: Set<String> = []
        var coOccurrences: [String: Set<String>] = [:]
        var textSnippets: [String] = []

        for chunk in chunks {
            // Collect keywords from metadata
            let chunkKeywords = Set(chunk.metadata.keywords.map { $0.lowercased() })
            allKeywords.formUnion(chunkKeywords)

            // Extract adjective+noun phrases from the actual text
            // This catches patterns like "blue outlet", "remote access", "network control"
            let textPhrases = extractAdjectiveNounPairs(from: chunk.content)
            let phraseKeywords = Set(textPhrases.map { $0.lowercased() })
            allKeywords.formUnion(phraseKeywords)

            // Combine metadata keywords with extracted phrases for co-occurrence
            let allChunkTerms = chunkKeywords.union(phraseKeywords)

            // Build co-occurrence map (terms that appear in the same chunk are related)
            for keyword in allChunkTerms {
                var related = coOccurrences[keyword] ?? []
                related.formUnion(allChunkTerms)
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

    /// Extract adjective+noun pairs using NLTagger
    /// This catches domain-specific phrases that may not be capitalized
    private static func extractAdjectiveNounPairs(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var pairs: [String] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var previousWord: String?
        var previousTag: NLTag?

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, range in
            guard let tag = tag else { return true }

            let word = String(text[range])

            // Check for adjective + noun pattern
            if let prevWord = previousWord, let prevTag = previousTag {
                if prevTag == .adjective && tag == .noun {
                    // Found adjective+noun pair like "blue outlet"
                    let phrase = "\(prevWord) \(word)"
                    if phrase.count >= 4 && phrase.count <= 40 {
                        pairs.append(phrase)
                    }
                }
            }

            // Also capture noun + noun compounds ("network control", "power outlet")
            if let prevWord = previousWord, let prevTag = previousTag {
                if prevTag == .noun && tag == .noun {
                    let phrase = "\(prevWord) \(word)"
                    if phrase.count >= 5 && phrase.count <= 40 {
                        pairs.append(phrase)
                    }
                }
            }

            previousWord = word
            previousTag = tag

            return true
        }

        // Limit to avoid noise
        return Array(Set(pairs).prefix(30))
    }
}
