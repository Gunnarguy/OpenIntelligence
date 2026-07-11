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
    /// Specific keyword lookup (e.g., "part number XYZ", "error code 404")
    /// → Heavily favor BM25 keyword matching
    case keyword

    /// Conceptual/semantic question (e.g., "how does the cooling system work")
    /// → Favor vector/embedding similarity
    case conceptual

    /// Balanced mix of both (e.g., "what maintenance is needed for the 2.0L model")
    case balanced

    /// Suggested weight adjustments for hybrid search
    var weightAdjustment: (vectorDelta: Float, keywordDelta: Float) {
        switch self {
        case .keyword:
            // UNIVERSAL FIX: Gentle nudge, not a sledgehammer.
            // OCR'd text is noisy — BM25 alone can't find "fuel tank capacity"
            // when the OCR'd text says "Fuel Capacity" or "fue l capa city".
            // Embeddings understand meaning; they must always have a strong vote.
            return (vectorDelta: -0.05, keywordDelta: +0.05)
        case .conceptual:
            return (vectorDelta: +0.10, keywordDelta: -0.10) // Moderate boost to vector similarity
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
    /// Example: "What is the maximum capacity?" → "5.7 quarts [S1]"
    case lookup

    /// Table-specific lookup - retrieve table_row then extract target cell(s)
    /// Example: "What are the torque specs for the bolts?"
    case tableLookup = "table_lookup"

    /// Step-by-step procedure - output ordered list_item nodes + headings (preserve order)
    /// Example: "How do I replace the filter?" → ordered steps from source
    case procedure

    /// Side-by-side comparison - retrieve evidence for A and B separately
    /// Example: "Compare option A vs option B"
    case compare

    /// Extractive summarization - sentence selection via bi-encoder similarity
    /// Example: "Summarize the maintenance schedule"
    case summarize

    /// Multi-hop investigation - answer = "evidence map" + extracted sub-facts
    /// Example: "What factors affect system longevity?"
    case investigate

    /// Numerical computation from extracted values
    /// Example: "What's the total capacity?" (sum multiple values)
    case compute

    /// Research findings / author discovery - requires document-level context
    /// Example: "What did Orfitelli find?" → needs summary + key sections
    /// Auto-injects document summary for comprehensive context
    case findings

    /// Maps to QueryIntent for hybrid search weight adjustment
    nonisolated var searchIntent: QueryIntent {
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
    nonisolated var isExtractiveFirst: Bool {
        switch self {
        case .lookup, .tableLookup:
            return true  // Direct extraction from source (e.g., "SAE 0W-20")
        case .procedure, .compare, .summarize, .investigate, .compute, .findings:
            return false  // Needs synthesis or behavioral descriptions
        }
    }

    /// Whether this intent benefits from multi-hop retrieval
    nonisolated var benefitsFromMultiHop: Bool {
        switch self {
        case .investigate, .compare, .findings:
            return true
        case .lookup, .tableLookup, .procedure, .summarize, .compute:
            return false
        }
    }

    /// Whether this intent should auto-inject document summary (L1) chunks
    /// Ensures document-level context is always available
    /// NOTE: Overridden to false for enumeration queries in RAGService —
    ///        the summary steals chunk slots from detail chunks that contain the actual list.
    nonisolated var requiresDocumentSummary: Bool {
        switch self {
        case .findings, .summarize, .investigate:
            return true  // Need document-level context
        case .lookup, .tableLookup, .procedure, .compare, .compute:
            return false  // Detail chunks sufficient
        }
    }

    /// Whether this is an author/research query pattern
    nonisolated var isAuthorQuery: Bool {
        self == .findings
    }

    /// Structure type boost for this intent
    nonisolated var structureTypeBoost: String? {
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

    nonisolated init(corpusVocabulary: CorpusVocabulary? = nil) {
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

        if isIndicatorStateLookupQuery(lower) {
            Log.debug("[QueryEnhancement] Intent: keyword (indicator/state lookup)", category: .retrieval)
            return .keyword
        }

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
        let shortBehavioralWeight = words.count <= 8 ? 1 : 2
        if firstWord == "what" && (lastWord == "do" || lastWord == "does" || lastWord == "happen" || lastWord == "happens") {
            conceptualSignals += shortBehavioralWeight
        }
        // "how does X work", "what does X do" mid-sentence patterns
        if lower.contains("what does") || lower.contains("what do") || lower.contains("how does") || lower.contains("what happens") {
            conceptualSignals += shortBehavioralWeight
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
    /// 0. **findings**: Author/research discovery (what did X find/discover/show)
    /// 1. **lookup**: Direct fact extraction (what, which, when + specific entity)
    /// 2. **table_lookup**: Table-specific queries (specs, comparisons in tables)
    /// 3. **procedure**: Step-by-step instructions (how to, steps, procedure)
    /// 4. **compare**: Side-by-side comparison (vs, compare, difference)
    /// 5. **summarize**: Overview/summary requests
    /// 6. **investigate**: Multi-hop research (factors, causes, effects)
    /// 7. **compute**: Numerical computation (total, sum, calculate)
    nonisolated func classifyAnswerIntent(_ query: String) -> AnswerIntent {
        let lower = query.lowercased()
        let words = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)

        if isIndicatorStateLookupQuery(lower) {
            Log.debug("[QueryEnhancement] Indicator/state query → lookup", category: .retrieval)
            return .lookup
        }

        // Priority 0: FINDINGS - author/research discovery queries
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
            ".*'s key finding", ".*'s discovery", ".*'s conclusion",
            "who designed the research", "who designed the study", "who conducted the research",
            "who conducted the study", "who carried out the research", "who carried out the study",
            "who authored the paper", "who wrote the paper", "who wrote the study"
        ]
        for pattern in findingsPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                Log.debug("[QueryEnhancement] Findings query pattern detected: '\(pattern)'", category: .retrieval)
                return .findings
            }
        }

        if lower.hasPrefix("who "),
           ["research", "study", "paper", "article", "experiment", "trial"].contains(where: { lower.contains($0) }),
           ["designed", "conducted", "authored", "wrote", "performed", "carried out"].contains(where: { lower.contains($0) }) {
            Log.debug("[QueryEnhancement] Research authorship query detected", category: .retrieval)
            return .findings
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
                    Log.debug("[QueryEnhancement] Author + finding pattern detected", category: .retrieval)
                    return .findings
                }
            }
        }

        // Priority 1: Paired conditional/contrast queries
        // "When does X happen, and when does Y happen?" is not a single-value lookup.
        // These questions compare conditions or thresholds across two states and need
        // fuller synthesis, not compact fact rendering.
        let pairedContrastPatterns: [String] = [
            #"when does .+ and when does .+"#,
            #"when is .+ and when is .+"#,
            #"what stays .+ and what .+ step in"#,
        ]
        for pattern in pairedContrastPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                Log.debug("[QueryEnhancement] Paired timing/contrast query → compare", category: .retrieval)
                return .compare
            }
        }

        // Priority 2: Compute (requires numerical aggregation)
        // Do not route noun phrases like "Private Cloud Compute" into arithmetic mode.
        let computeFalsePositivePhrases = [
            "private cloud compute"
        ]
        let computePatterns: [String] = [
            "total", "sum", "add up", "calculate", "compute the", "how much total",
            "combined", "altogether", "in total"
        ]
        if !computeFalsePositivePhrases.contains(where: { lower.contains($0) }) {
            for pattern in computePatterns {
                if lower.contains(pattern) { return .compute }
            }
        }

        // Priority 3: Compare (explicit comparison request)
        let comparePatterns: [String] = [
            " vs ", "versus", "compare", "comparison", "difference between",
            "differences between", "differ from", "better than", "worse than",
            "pros and cons", "advantages", "disadvantages"
        ]
        for pattern in comparePatterns {
            if lower.contains(pattern) { return .compare }
        }

        // Priority 4: Procedure (step-by-step instructions)
        let procedurePatterns: [String] = [
            "how to", "how do i", "how can i", "steps to", "procedure for",
            "steps for", "what are the steps for", "instructions for", "guide to", "process for", "way to",
            "method for", "directions for", "what should you do if", "what do you do if",
            "what must you do if", "what should be done if", "what action is required if"
        ]
        for pattern in procedurePatterns {
            if lower.contains(pattern) { return .procedure }
        }

        // Priority 5: Summarize (overview/summary requests)
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
            // Regex: "what does X do/mean/indicate/signal/show", etc.
            "what does .* do", "what will .* do", "what can .* do",
            "what's .* do",
            "what does .* mean", "what does .* indicate", "what does .* signal", "what does .* show",
            "what's .* mean", "what's .* indicate", "what's .* signal", "what's .* show"
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
        //
        // CRITICAL: "How many X are available/there" is an enumeration, not a lookup.
        // The user wants a COUNT + full LIST. Sentence extraction (lookup) strips the
        // surrounding list context, causing the LLM to hallucinate counts and duplicate items.
        let enumerationPatterns: [String] = [
            "list all", "list every", "list the", "list each",
            "name all", "name every", "name each",
            "what are all", "what are every",
            "show all", "show every", "show each",
            "give me all", "give me every",
            "enumerate", "all the .* numbers", "all .* reference",
            // "How many X are available/there/exist/does it have" → enumeration
            // Distinct from "how many quarts" (single-value lookup with unit)
            "how many .* available", "how many .* are there",
            "how many .* exist", "how many .* does .* have",
            "how many .* can .* use", "how many .* supported",
            "how many .* included", "how many .* types",
            "how many .* options", "how many .* commands",
            "how many .* features", "how many .* modes",
            "how many .* settings", "how many .* functions",
            "how many .* methods", "how many .* ways",
            "how many kinds", "how many categories",
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

        if let specificationIntent = manualSpecificationIntent(for: lower) {
            Log.debug("[QueryEnhancement] Specification query → \(specificationIntent.rawValue)", category: .retrieval)
            return specificationIntent
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
        // Queries like "Model 1688 camera head what is the reference number?" should be LOOKUP
        let embeddedLookupPatterns: [String] = [
            "what is the", "what are the", "what's the",
            "reference number", "part number", "model number", "serial number",
            "catalog number", "item number", "product code", "sku"
        ]
        for pattern in embeddedLookupPatterns {
            if lower.range(of: "\\b\(pattern)s?\\b", options: .regularExpression) != nil {
                Log.debug("[QueryEnhancement] Detected embedded lookup pattern: '\(pattern)'", category: .retrieval)
                return .lookup
            }
        }

        // CRITICAL FIX: Detect specification lookup patterns that may not start with lookup words
        // "type of X", "kind of Y", "grade of Z", etc. are clearly looking for specific values
        let specLookupPatterns: [String] = [
            "type of", "kind of", "grade of", "brand of", "model of",
            "capacity", "weight", "pressure",
            "should i use"
        ]
        for pattern in specLookupPatterns {
            if lower.range(of: "\\b\(pattern)s?\\b", options: .regularExpression) != nil {
                Log.debug("[QueryEnhancement] Detected spec lookup pattern: '\(pattern)'", category: .retrieval)
                return .lookup
            }
        }

        // Fallback for short queries
        if words.count <= 5 { return .lookup }

        // For longer conceptual queries, default to investigate
        return .investigate
    }

    private nonisolated func isIndicatorStateLookupQuery(_ lower: String) -> Bool {
        let signalTokens = ["indicator", "light", "lights", "led", "status", "signal"]
        let stateTokens = ["solid", "flashing", "flash", "blinking", "blink", "steady", "pulsing", "pulse"]
        let colorTokens = ["red", "green", "blue", "yellow", "amber", "orange", "purple", "white", "cyan", "cyan-blue"]
        let lookupTokens = ["what does", "what is", "what's", "mean", "meaning", "indicate", "indicates", "signal", "signals"]

        let hasSignalToken = signalTokens.contains { lower.contains($0) }
        let hasStateOrColor = stateTokens.contains { lower.contains($0) } || colorTokens.contains { lower.contains($0) }
        let hasLookupCue = lookupTokens.contains { lower.contains($0) }

        return hasSignalToken && hasStateOrColor && hasLookupCue
    }

    private nonisolated func manualSpecificationIntent(for lower: String) -> AnswerIntent? {
        let summarizeCues = ["summarize", "summary", "overview", "brief", "main points", "key points", "highlights"]
        if summarizeCues.contains(where: { lower.contains($0) }) {
            return nil
        }

        let exactCuePatterns = [
            "what is", "what's", "which", "when is", "when should", "how much", "how many",
            "what should", "which setting", "which mode", "which level", "should i use",
            "recommended", "initial setting",
        ]
        let specificationTargets = [
            "capacity", "capacities", "viscosity", "oil", "engine oil", "fluid", "coolant",
            "lubricant", "spec", "specification", "setting", "mode", "level",
            "height setting", "opening height", "dimensions", "size", "interval",
            "maintenance schedule", "pressure", "torque", "payload", "fuel tank",
        ]
        let structuredTargetPattern = #"\b(?:sae|api|ilsac|dot-4|gl-5|sp4|[0o]w-20|5w-30|75w/85|qt|quarts?|gal(?:lon)?s?|l(?:iter)?s?|psi|kpa|mm|inch(?:es)?)\b"#

        let hasExactCue = exactCuePatterns.contains { lower.contains($0) }
            || ["what ", "which ", "how much", "how many"].contains(where: { lower.hasPrefix($0) })
        let hasSpecificationTarget = specificationTargets.contains { lower.contains($0) }
        let hasStructuredTarget = lower.range(of: structuredTargetPattern, options: [.regularExpression, .caseInsensitive]) != nil

        guard hasSpecificationTarget || hasStructuredTarget else { return nil }
        guard hasExactCue || lower.contains("should be used") || lower.contains("what oil") else { return nil }

        let tableLikeTargets = [
            "table", "chart", "specification", "specifications",
            "recommended lubricants and capacities", "capacity", "viscosity", "payload", "dimensions",
        ]
        if tableLikeTargets.contains(where: { lower.contains($0) }) || hasStructuredTarget {
            return .tableLookup
        }

        return .lookup
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

    /// Synonym generation for query expansion.
    ///
    /// IMPORTANT: Co-occurrence ≠ synonymy. "type" co-occurs with "air conditioning"
    /// in a car manual, but replacing "type" → "air conditioning" produces nonsense
    /// like "What air conditioning of oil does this car takes". This ruins retrieval.
    ///
    /// Strategy:
    /// - Corpus co-occurrences are NEVER used here. They're already handled by
    ///   expandFromCorpus() (step 1.5) with proper quality gates (multi-term
    ///   co-occurrence, stopword filtering). Using them again here for REPLACEMENT
    ///   is redundant and catastrophic.
    /// - Only true synonyms (universal action verbs + common noun equivalents)
    ///   are returned. These are safe for both replacement and appending.
    private func generateSynonyms(for terms: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]

        // True synonyms only — words that can safely REPLACE each other in any query.
        // Action verbs and common noun equivalents. NOT domain-specific terms
        // (those come from corpus expansion, not synonym replacement).
        let trueSynonyms: [String: [String]] = [
            // Action verbs
            "use": ["operate", "utilize", "apply"],
            "remove": ["detach", "disconnect", "extract"],
            "install": ["attach", "connect", "mount"],
            "check": ["verify", "inspect", "examine"],
            "start": ["begin", "initiate", "launch"],
            "stop": ["end", "disable", "halt"],
            "press": ["tap", "push", "activate"],
            "click": ["tap", "press", "select"],
            "replace": ["change", "swap", "renew"],
            "adjust": ["set", "configure", "calibrate"],
            "clean": ["wash", "wipe", "rinse"],
            "open": ["unlock", "release", "access"],
            "close": ["shut", "lock", "seal"],
            // Common noun equivalents
            "vehicle": ["car", "automobile"],
            "car": ["vehicle", "automobile"],
            "engine": ["motor", "powerplant"],
            "motor": ["engine", "powerplant"],
            "fluid": ["liquid", "lubricant"],
            "capacity": ["volume", "quantity"],
            "specification": ["spec", "requirement"],
            "temperature": ["temp", "heat"],
            "pressure": ["psi", "force"],
        ]

        for term in terms {
            let lower = term.lowercased()
            if let syns = trueSynonyms[lower], !syns.isEmpty {
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
        // corpus lookup. Generic framing words produce massive co-occurrence
        // sets that pull in irrelevant terms.
        // Only look up substantive content words.
        let corpusStopwords: Set<String> = [
            "type", "kind", "sort", "take", "use", "does",
            "get", "find", "tell", "know", "look", "want", "like", "make",
            "put", "give", "help", "work", "come", "thing", "much", "many",
            "way", "long", "need", "require"
        ]
        let substantiveTerms = keyTerms.filter { !corpusStopwords.contains($0.lowercased()) }

        // 1) Find corpus terms that co-occur with query terms
        var relatedTerms: [String: Int] = [:] // term → co-occurrence count with query terms
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

        // 2) Quality gate: require multi-term co-occurrence
        // For multi-term queries ("fuel capacity car"), a related term must
        // co-occur with at least 2 query terms to be considered relevant.
        // This filters noise like "tire" (only co-occurs with "car") while
        // keeping "tank" (co-occurs with both "fuel" and "capacity").
        let minCooccurrence = substantiveTerms.count >= 2 ? 2 : 1
        let qualifiedTerms = relatedTerms
            .filter { $0.value >= minCooccurrence }
            .sorted { $0.value > $1.value }
            .prefix(3)  // Tight limit: only truly relevant terms
            .map { $0.key }

        if !qualifiedTerms.isEmpty {
            // Single combined expansion — no individual term variants
            // which would each pull in unrelated chunks
            expansions.append("\(query) \(qualifiedTerms.joined(separator: " "))")
        }

        // 3) Find multi-word phrases in the corpus that contain query terms
        // REQUIRES phrases to contain 2+ query terms for multi-term queries,
        // preventing irrelevant phrases like "inhale vaporized fuel" or
        // "gage load capacity" that match only one query term in the wrong context.
        let phraseExpansions = findCorpusPhrases(keyTerms: substantiveTerms, vocabulary: vocabulary)
        for phrase in phraseExpansions.prefix(2) {
            expansions.append(phrase)
        }

        return expansions
    }

    /// Finds multi-word phrases in the corpus that contain query terms.
    ///
    /// For multi-term queries, requires phrases to contain 2+ query terms,
    /// preventing irrelevant matches like "inhale vaporized fuel" (only matches "fuel")
    /// or "gage load capacity" (wrong context for "capacity").
    ///
    /// Action words (press/turn/push) are NO LONGER used as triggers — they pulled in
    /// completely unrelated phrases like "Press START button" from snippets that
    /// happened to also contain a query term elsewhere.
    private func findCorpusPhrases(keyTerms: [String], vocabulary: CorpusVocabulary) -> [String] {
        var phrases: [(phrase: String, termOverlap: Int)] = []
        let keyTermsLower = Set(keyTerms.map { $0.lowercased() })
        let requiredOverlap = keyTermsLower.count >= 2 ? 2 : 1

        for snippet in vocabulary.textSnippets {
            let snippetLower = snippet.lowercased()

            // Quick check: snippet must contain at least one key term
            guard keyTermsLower.contains(where: { snippetLower.contains($0) }) else { continue }

            let words = snippet.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map { String($0) }

            for (i, word) in words.enumerated() {
                let wordLower = word.lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)

                // Only trigger on actual query terms — NOT action words
                guard keyTermsLower.contains(wordLower) else { continue }

                // Extract a 3-5 word window around this word
                let start = max(0, i - 2)
                let end = min(words.count, i + 3)
                let phrase = words[start ..< end]
                    .joined(separator: " ")
                    .trimmingCharacters(in: .punctuationCharacters)

                guard phrase.count > 10, phrase.count < 60,
                      isValidExpansionPhrase(phrase) else { continue }

                // Count how many query terms appear in this phrase
                let termOverlap = keyTermsLower.filter { phrase.lowercased().contains($0) }.count
                guard termOverlap >= requiredOverlap else { continue }

                phrases.append((phrase: phrase, termOverlap: termOverlap))
            }
        }

        // Sort by term overlap (more query terms = better), then by length (shorter = more specific)
        let uniquePhrases = Array(Set(phrases.map { $0.phrase }))
        return uniquePhrases.sorted { p1, p2 in
            let overlap1 = phrases.first { $0.phrase == p1 }?.termOverlap ?? 0
            let overlap2 = phrases.first { $0.phrase == p2 }?.termOverlap ?? 0
            if overlap1 != overlap2 { return overlap1 > overlap2 }
            return p1.count < p2.count
        }
    }

    // MARK: - Expansion Term Validation

    /// Filters out garbage terms from noisy PDF extraction.
    /// Rejects hyphenated fragments, too-short tokens, and stopword phrases.
    private func isValidExpansionTerm(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject empty or too short (4-char minimum filters OCR fragments like "cle", "vehi")
        guard trimmed.count >= 4 else { return false }

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
        // But allow known spec patterns like "ISO" or "API"
        let knownSpecPrefixes: Set<String> = ["api", "iso", "ieee", "ansi", "astm", "iec"]
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
    /// Quality filtering at build time:
    /// 1. Validates terms (rejects OCR garbage, fragments, non-Latin)
    /// 2. Requires minimum cross-chunk frequency (hapax legomena = noise)
    /// 3. Filters text snippets by ASCII quality (garbled OCR → skip)
    /// 4. Adjective+noun pairs from text (e.g., "blue outlet", "red button")
    static func build(from chunks: [DocumentChunk]) -> CorpusVocabulary {
        guard !chunks.isEmpty else { return .empty }

        var allKeywords: Set<String> = []
        var coOccurrences: [String: Set<String>] = [:]
        var textSnippets: [String] = []

        // Phase 1: Collect validated terms per chunk and count cross-chunk frequency
        var termChunkCount: [String: Int] = [:]  // term → number of chunks containing it
        var perChunkTerms: [Set<String>] = []
        perChunkTerms.reserveCapacity(chunks.count)

        for chunk in chunks {
            let chunkKeywords = Set(chunk.metadata.keywords.map { $0.lowercased() })
            let textPhrases = extractAdjectiveNounPairs(from: chunk.content)
            let phraseKeywords = Set(textPhrases.map { $0.lowercased() })

            // Filter at build time — reject OCR garbage, fragments, non-Latin
            let validTerms = chunkKeywords.union(phraseKeywords).filter { isValidVocabTerm($0) }
            perChunkTerms.append(validTerms)

            for term in validTerms {
                termChunkCount[term, default: 0] += 1
            }

            // Only keep text snippets with high ASCII ratio (reject garbled OCR)
            // MEMORY FIX: Cap at 300 entries × 200 chars ≈ 120KB (was uncapped × 500 ≈ 1.9MB)
            if textSnippets.count < 300 {
                let snippet = String(chunk.content.prefix(200))
                let asciiCount = snippet.filter { $0.isASCII }.count
                if Float(asciiCount) / max(Float(snippet.count), 1) > 0.85 {
                    textSnippets.append(snippet)
                }
            }
        }

        // Phase 2: Build vocabulary from validated terms.
        // UNIVERSAL FIX: Previously required minFrequency of 2+ (or chunks/500), which
        // excluded terms appearing in only 1 chunk — i.e., exactly the rare needles users
        // search for (a specific drug name, part number, legal citation, etc.).
        //
        // New strategy: frequency-1 terms ARE included in the keyword set (so they participate
        // in query expansion), but NOT in co-occurrence maps (where singleton co-occurrence
        // would just be noise). This gives rare needles a path through expansion while
        // keeping co-occurrence quality high.
        //
        // For co-occurrence: still require 2+ to maintain signal quality.
        let coOccurrenceMinFreq = max(2, chunks.count / 500)
        // For keywords: include all validated terms (frequency ≥ 1)
        let keywordMinFreq = 1

        for validTerms in perChunkTerms {
            // All valid terms join the keyword vocabulary (including rare needles)
            let keywordQualifiedTerms = validTerms.filter { (termChunkCount[$0] ?? 0) >= keywordMinFreq }
            allKeywords.formUnion(keywordQualifiedTerms)

            // Only frequent terms build co-occurrence maps (noise filter)
            let coOccurrenceQualifiedTerms = validTerms.filter { (termChunkCount[$0] ?? 0) >= coOccurrenceMinFreq }
            for keyword in coOccurrenceQualifiedTerms {
                var related = coOccurrences[keyword] ?? []
                related.formUnion(coOccurrenceQualifiedTerms)
                related.remove(keyword)
                coOccurrences[keyword] = related
            }
        }

        let filteredCount = termChunkCount.count - allKeywords.count
        Log.debug(
            "[CorpusVocabulary] Built vocabulary: \(allKeywords.count) terms (kwMinFreq=\(keywordMinFreq)), \(coOccurrences.count) co-occurrence entries (coMinFreq=\(coOccurrenceMinFreq)), filtered \(filteredCount) invalid terms",
            category: .retrieval
        )

        return CorpusVocabulary(
            keywords: allKeywords,
            coOccurrences: coOccurrences,
            textSnippets: textSnippets
        )
    }

    /// Validates a term during vocabulary building.
    /// Rejects OCR garbage, fragments, and non-meaningful tokens.
    private static func isValidVocabTerm(_ term: String) -> Bool {
        // Reject fragments ("cle", "vehi", "ble")
        guard term.count >= 4 else { return false }

        // Reject hyphenated line-break artifacts
        if term.hasPrefix("-") || term.hasSuffix("-") || term.contains("- ") || term.contains(" -") {
            return false
        }

        // Require mostly ASCII letters (rejects OCR Unicode garbage like Cyrillic, CJK)
        let asciiLetterCount = term.filter { $0.isASCII && $0.isLetter }.count
        guard Float(asciiLetterCount) / Float(term.count) > 0.6 else { return false }

        // Reject terms that are majority non-letter (digits-only, symbols)
        let letterCount = term.filter { $0.isLetter }.count
        guard Float(letterCount) / Float(term.count) > 0.5 else { return false }

        return true
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
