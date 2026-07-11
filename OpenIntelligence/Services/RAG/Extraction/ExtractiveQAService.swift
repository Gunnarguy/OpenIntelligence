//
//  ExtractiveQAService.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Extractive QA Model for precise span extraction from retrieved context.
//  Implements §3.1 of AppleRAG spec: "Extractive → Abstractive" handoff.
//
//  Architecture:
//  - TinyBERT backbone with dual start/end heads
//  - Input: question + retrieved passages
//  - Output: exact text span with confidence score
//
//  Status: STUB – Model training/conversion pending
//  When ready, convert via:
//    scripts/convert_extractive_qa_model.py --model distilbert-squad2 --output ExtractiveQAModel.mlpackage
//

import CoreML
import Foundation
import NaturalLanguage

// MARK: - Precompiled Regular Expressions

/// Statically compiled regular expressions to avoid recompilation inside hot loops.
enum ExtractiveQARegexes: Sendable {
    // Shared Date Patterns
    nonisolated(unsafe) static let year = try! NSRegularExpression(pattern: "\\d{4}", options: [])
    nonisolated(unsafe) static let dateFormat = try! NSRegularExpression(pattern: "\\d{1,2}/\\d{1,2}", options: [])
    nonisolated(unsafe) static let months = try! NSRegularExpression(pattern: "january|february|march|april|may|june|july|august|september|october|november|december", options: [])
    nonisolated(unsafe) static let days = try! NSRegularExpression(pattern: "monday|tuesday|wednesday|thursday|friday|saturday|sunday", options: [])
    nonisolated(unsafe) static let time = try! NSRegularExpression(pattern: "\\d{1,2}\\s+(am|pm)", options: [])
    nonisolated(unsafe) static let temporalMarkers = try! NSRegularExpression(pattern: "ago|since|until|before|after", options: [])

    nonisolated(unsafe) static let scoreDatePatterns = [year, dateFormat, months, days, time, temporalMarkers]

    // Definition Patterns
    nonisolated(unsafe) static let defIs = try! NSRegularExpression(pattern: "\\bis\\b.*\\b(a|an|the)\\b", options: [])
    nonisolated(unsafe) static let defRefers = try! NSRegularExpression(pattern: "refers to", options: [])
    nonisolated(unsafe) static let defDefined = try! NSRegularExpression(pattern: "defined as", options: [])
    nonisolated(unsafe) static let defKnown = try! NSRegularExpression(pattern: "known as", options: [])
    nonisolated(unsafe) static let defMeansThat = try! NSRegularExpression(pattern: "means that", options: [])
    nonisolated(unsafe) static let defMeaning = try! NSRegularExpression(pattern: "meaning", options: [])

    nonisolated(unsafe) static let defPatterns = [defIs, defRefers, defDefined, defKnown, defMeansThat, defMeaning]

    // How Many
    nonisolated(unsafe) static let digits = try! NSRegularExpression(pattern: "\\d+", options: [])

    // Specificity Bonus
    nonisolated(unsafe) static let measurements = try! NSRegularExpression(pattern: "\\d+\\.?\\d*\\s*(mg|kg|ml|mm|cm|m|km|lbs|oz|ft|in|mph|kph|psi|°[CF]|watts?|volts?|amps?|ohms?|hz|mhz|ghz|gb|mb|kb|tb)", options: [.caseInsensitive])

    // Extract Span Patterns
    nonisolated(unsafe) static let howManySpan = try! NSRegularExpression(pattern: "\\d+[\\d,\\.]*\\s*\\w*(?:\\s+\\w+)?", options: [])

    nonisolated(unsafe) static let extractDateFormats = try! NSRegularExpression(pattern: "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b", options: [.caseInsensitive])
    nonisolated(unsafe) static let extractMonthDayYear = try! NSRegularExpression(pattern: "\\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\\s+\\d{1,2},?\\s*\\d{0,4}\\b", options: [.caseInsensitive])
    nonisolated(unsafe) static let extractYear = try! NSRegularExpression(pattern: "\\b\\d{4}\\b", options: [.caseInsensitive])
    nonisolated(unsafe) static let extractTime = try! NSRegularExpression(pattern: "\\b\\d{1,2}\\s*(?:am|pm)\\b", options: [.caseInsensitive])

    nonisolated(unsafe) static let extractDatePatterns = [extractDateFormats, extractMonthDayYear, extractYear, extractTime]

    nonisolated(unsafe) static let extractIs = try! NSRegularExpression(pattern: "\\bis\\s+", options: [])
}


// MARK: - Protocol Definition

/// Extractive QA service for identifying answer spans within retrieved context.
/// Complements abstractive LLM generation with grounded, verifiable extractions.
protocol ExtractiveQAService: Sendable {
    /// Extract the most likely answer span from retrieved context
    /// - Parameters:
    ///   - question: The user's query
    ///   - passages: Retrieved passage texts to search within
    /// - Returns: The extracted answer span with confidence and source reference
    func extractAnswer(question: String, passages: [String]) async throws -> ExtractionResult?

    /// Check if the extractive model is available and loaded
    var isAvailable: Bool { get async }

    /// Model metadata for diagnostics
    var modelInfo: ExtractiveModelInfo { get async }
}

// MARK: - Supporting Types

/// Result of extractive QA inference
struct ExtractionResult: Sendable {
    /// The extracted answer text (exact span from source)
    let answerSpan: String

    /// Confidence score for this extraction (0.0-1.0)
    let confidence: Float

    /// Index of the passage containing the answer (0-based)
    let sourcePassageIndex: Int

    /// Character range within the source passage
    let spanRange: Range<String.Index>

    /// Start position in concatenated input (for debugging)
    let startLogit: Float

    /// End position logit (for debugging)
    let endLogit: Float

    /// Whether confidence exceeds threshold for reliable extraction
    var isHighConfidence: Bool { confidence >= 0.7 }

    /// Whether this is a "no answer" prediction (span is empty or very short)
    var isNullPrediction: Bool { answerSpan.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 }
}

/// Metadata about the extractive QA model
struct ExtractiveModelInfo: Sendable {
    let modelName: String
    let version: String
    let maxSequenceLength: Int
    let vocabSize: Int
    let isLoaded: Bool
    let loadError: String?

    nonisolated static let placeholder = ExtractiveModelInfo(
        modelName: "ExtractiveQAModel (not loaded)",
        version: "0.0.0",
        maxSequenceLength: 384,
        vocabSize: 30522,
        isLoaded: false,
        loadError: "Model not yet trained/converted"
    )
}

// MARK: - Placeholder Implementation

/// Placeholder implementation until CoreML model is trained and converted.
/// Returns nil for all extractions, allowing abstractive fallback to proceed.
actor PlaceholderExtractiveQAService: ExtractiveQAService {

    var isAvailable: Bool { false }

    var modelInfo: ExtractiveModelInfo { .placeholder }

    func extractAnswer(question: String, passages: [String]) async throws -> ExtractionResult? {
        // Model not available - return nil to trigger abstractive fallback
        Log.debug("ExtractiveQA: Model not available, falling back to abstractive generation", category: .llm)
        return nil
    }
}

// MARK: - CoreML Implementation (Template for when model is ready)

/// CoreML-backed extractive QA service using TinyBERT or DistilBERT with SQuAD heads.
/// Uncomment and implement when ExtractiveQAModel.mlpackage is available.
/*
actor CoreMLExtractiveQAService: ExtractiveQAService {

    private var model: ExtractiveQAModel?
    private var tokenizer: BertTokenizer?
    private var loadError: String?

    var isAvailable: Bool { model != nil }

    var modelInfo: ExtractiveModelInfo {
        ExtractiveModelInfo(
            modelName: "ExtractiveQAModel",
            version: "1.0.0",
            maxSequenceLength: 384,
            vocabSize: 30522,
            isLoaded: model != nil,
            loadError: loadError
        )
    }

    init() {
        Task { await loadModel() }
    }

    private func loadModel() async {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            guard let modelURL = OpenIntelligenceResourceBundle.url(forResource: "ExtractiveQAModel", withExtension: "mlmodelc") else {
                loadError = "ExtractiveQAModel.mlmodelc not found in bundle"
                return
            }

            model = try ExtractiveQAModel(contentsOf: modelURL, configuration: config)
            tokenizer = try BertTokenizer.load(from: "extractive_qa_vocab")

            Log.info("ExtractiveQA: Model loaded successfully", category: .initialization)
        } catch {
            loadError = error.localizedDescription
            Log.error("ExtractiveQA: Failed to load model - \(error)", category: .initialization)
        }
    }

    func extractAnswer(question: String, passages: [String]) async throws -> ExtractionResult? {
        guard let model = model, let tokenizer = tokenizer else { return nil }

        // Concatenate passages with separator tokens
        let context = passages.joined(separator: " [SEP] ")

        // Tokenize [CLS] question [SEP] context [SEP]
        let inputIds = tokenizer.encode(question: question, context: context, maxLength: 384)

        // Run inference
        let prediction = try model.prediction(input_ids: inputIds)

        // Find best span from start/end logits
        let (startIdx, endIdx, confidence) = findBestSpan(
            startLogits: prediction.start_logits,
            endLogits: prediction.end_logits,
            maxLength: 50
        )

        // Decode span back to text
        let spanTokens = Array(inputIds[startIdx...endIdx])
        let answerSpan = tokenizer.decode(spanTokens)

        // Find which passage contains the answer
        let sourceIndex = findSourcePassage(span: answerSpan, passages: passages)

        return ExtractionResult(
            answerSpan: answerSpan,
            confidence: confidence,
            sourcePassageIndex: sourceIndex,
            spanRange: passages[sourceIndex].range(of: answerSpan) ?? passages[sourceIndex].startIndex..<passages[sourceIndex].startIndex,
            startLogit: prediction.start_logits[startIdx],
            endLogit: prediction.end_logits[endIdx]
        )
    }

    private func findBestSpan(startLogits: [Float], endLogits: [Float], maxLength: Int) -> (Int, Int, Float) {
        var bestScore: Float = -.infinity
        var bestStart = 0
        var bestEnd = 0

        for start in 0..<startLogits.count {
            for end in start..<min(start + maxLength, endLogits.count) {
                let score = startLogits[start] + endLogits[end]
                if score > bestScore {
                    bestScore = score
                    bestStart = start
                    bestEnd = end
                }
            }
        }

        // Convert logit sum to probability via softmax approximation
        let confidence = 1.0 / (1.0 + exp(-bestScore / 2))

        return (bestStart, bestEnd, confidence)
    }

    private func findSourcePassage(span: String, passages: [String]) -> Int {
        for (index, passage) in passages.enumerated() {
            if passage.contains(span) {
                return index
            }
        }
        return 0
    }
}
*/

// MARK: - Heuristic Fallback (NLP-based span detection)

/// Enhanced heuristic-based extractive QA using NaturalLanguage framework.
/// Uses multi-signal scoring: keyword overlap, entity type matching,
/// proximity weighting, and passage position bias.
actor HeuristicExtractiveQAService: ExtractiveQAService {

    var isAvailable: Bool { true }

    var modelInfo: ExtractiveModelInfo {
        ExtractiveModelInfo(
            modelName: "HeuristicQA-v2 (NLTagger+Proximity)",
            version: "2.0.0",
            maxSequenceLength: Int.max,
            vocabSize: 0,
            isLoaded: true,
            loadError: nil
        )
    }

    func extractAnswer(question: String, passages: [String]) async throws -> ExtractionResult? {
        let questionType = detectQuestionType(question)
        let questionKeywords = extractKeywords(from: question)

        // Score ALL candidates across all passages, then pick the best
        var allCandidates: [(span: String, confidence: Float, passageIndex: Int, sentenceIndex: Int)] = []

        for (passageIndex, passage) in passages.enumerated() {
            let sentences = extractSentences(from: passage)
            // Passage position bias: earlier passages (higher retrieval rank) get a boost
            let passagePositionBonus: Float = max(0, 0.15 - Float(passageIndex) * 0.03)

            for (sentenceIndex, sentence) in sentences.enumerated() {
                guard !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let score = scoreCandidate(
                    sentence: sentence,
                    questionKeywords: questionKeywords,
                    type: questionType,
                    passagePositionBonus: passagePositionBonus
                )

                if score >= 0.2 { // Lower threshold to collect more candidates for comparison
                    let span = extractSpan(from: sentence, type: questionType, question: question)
                    allCandidates.append((span, score, passageIndex, sentenceIndex))
                }
            }
        }

        // Sort by score descending
        allCandidates.sort { $0.confidence > $1.confidence }

        // Require minimum confidence after scoring
        guard let best = allCandidates.first, best.confidence >= 0.3 else {
            return nil
        }

        // If top 2 candidates are very close in score but from different passages,
        // prefer the one from the higher-ranked passage (lower index)
        if allCandidates.count >= 2 {
            let second = allCandidates[1]
            let scoreDiff = best.confidence - second.confidence
            if scoreDiff < 0.05 && second.passageIndex < best.passageIndex {
                // Second candidate is from a better-ranked passage and nearly as good
                let passage = passages[second.passageIndex]
                let range = passage.range(of: second.span) ?? passage.startIndex..<passage.startIndex
                return ExtractionResult(
                    answerSpan: second.span,
                    confidence: second.confidence,
                    sourcePassageIndex: second.passageIndex,
                    spanRange: range,
                    startLogit: second.confidence,
                    endLogit: second.confidence
                )
            }
        }

        let passage = passages[best.passageIndex]
        let range = passage.range(of: best.span) ?? passage.startIndex..<passage.startIndex

        return ExtractionResult(
            answerSpan: best.span,
            confidence: best.confidence,
            sourcePassageIndex: best.passageIndex,
            spanRange: range,
            startLogit: best.confidence,
            endLogit: best.confidence
        )
    }

    private enum QuestionType {
        case who, what, when, `where`, why, how, howMany, yesNo, definition, other
    }

    private func detectQuestionType(_ question: String) -> QuestionType {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lower.hasPrefix("who") { return .who }
        if lower.hasPrefix("what is ") || lower.hasPrefix("what are ") || lower.hasPrefix("what's ") {
            // "What is X?" is often a definition query
            return .definition
        }
        if lower.hasPrefix("what") { return .what }
        if lower.hasPrefix("when") { return .when }
        if lower.hasPrefix("where") { return .`where` }
        if lower.hasPrefix("why") { return .why }
        if lower.hasPrefix("how many") || lower.hasPrefix("how much") { return .howMany }
        if lower.hasPrefix("how") { return .how }
        if lower.hasPrefix("is ") || lower.hasPrefix("are ") ||
           lower.hasPrefix("does ") || lower.hasPrefix("do ") ||
           lower.hasPrefix("can ") || lower.hasPrefix("will ") { return .yesNo }

        // Check for implicit definition queries: "the meaning of", "define"
        if lower.contains("meaning of") || lower.contains("definition of") || lower.hasPrefix("define") {
            return .definition
        }

        return .other
    }

    /// Extract meaningful keywords from the question, removing stop words
    private func extractKeywords(from question: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "what", "who", "when",
            "where", "why", "how", "does", "do", "can", "will", "of", "in", "on",
            "at", "to", "for", "this", "that", "these", "those", "it", "its",
            "they", "their", "and", "or", "but", "not", "with", "from", "by",
            "about", "into", "through", "during", "before", "after", "above",
            "below", "between", "under", "my", "your", "his", "her", "our",
            "many", "much", "some", "any", "all", "each", "every", "both",
            "more", "most", "other", "such", "than", "too", "very", "just",
            "also", "now", "then", "here", "there", "which", "would", "should",
            "could", "might", "shall", "may", "must", "need", "have", "has", "had",
            "been", "being", "did", "done", "get", "got", "getting", "tell", "me",
            "please", "explain", "describe"
        ]
        return question.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
    }

    private func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }

    private func scoreCandidate(
        sentence: String,
        questionKeywords: [String],
        type: QuestionType,
        passagePositionBonus: Float
    ) -> Float {
        let sentenceLower = sentence.lowercased()
        guard !questionKeywords.isEmpty else { return 0 }

        // --- Signal 1: Keyword overlap (weighted by keyword rarity/length) ---
        var weightedMatchScore: Float = 0
        var totalWeight: Float = 0
        for keyword in questionKeywords {
            // Longer keywords are more discriminative
            let weight: Float = Float(keyword.count) / 4.0
            totalWeight += weight
            if sentenceLower.contains(keyword) {
                weightedMatchScore += weight
                // Bonus for exact word boundary match (not substring)
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                if sentenceLower.range(of: pattern, options: .regularExpression) != nil {
                    weightedMatchScore += weight * 0.3 // 30% bonus for exact match
                }
            }
        }
        let keywordScore = totalWeight > 0 ? weightedMatchScore / totalWeight : 0

        // --- Signal 2: Entity type match bonus ---
        var typeBonus: Float = 0
        switch type {
        case .who:
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, _ in
                if tag == .personalName || tag == .organizationName {
                    typeBonus = 0.25
                    return false
                }
                return true
            }

        case .when:
            let nsRange = NSRange(sentenceLower.startIndex..., in: sentenceLower)
            for regex in ExtractiveQARegexes.scoreDatePatterns {
                if regex.firstMatch(in: sentenceLower, range: nsRange) != nil {
                    typeBonus = max(typeBonus, 0.25)
                }
            }

        case .where:
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, _ in
                if tag == .placeName {
                    typeBonus = 0.25
                    return false
                }
                return true
            }

        case .howMany:
            let nsRange = NSRange(sentence.startIndex..., in: sentence)
            if ExtractiveQARegexes.digits.firstMatch(in: sentence, range: nsRange) != nil {
                typeBonus = 0.25
            }

        case .definition:
            // Definitional patterns: "X is Y", "refers to", "defined as", "known as", "means"
            let nsRange = NSRange(sentenceLower.startIndex..., in: sentenceLower)
            for regex in ExtractiveQARegexes.defPatterns {
                if regex.firstMatch(in: sentenceLower, range: nsRange) != nil {
                    typeBonus = max(typeBonus, 0.2)
                }
            }

        case .how:
            // Procedural markers
            let procPatterns: [String] = ["step", "first", "then", "next", "finally", "begin by", "start with", "to do this"]
            for pattern in procPatterns {
                if sentenceLower.contains(pattern) {
                    typeBonus = max(typeBonus, 0.15)
                }
            }

        case .why:
            // Causal markers
            let causePatterns: [String] = ["because", "due to", "caused by", "result of", "reason", "therefore", "since"]
            for pattern in causePatterns {
                if sentenceLower.contains(pattern) {
                    typeBonus = max(typeBonus, 0.2)
                }
            }

        default:
            break
        }

        // --- Signal 3: Sentence length penalty ---
        // Very short (<20 chars) or very long (>500 chars) sentences are less likely to be answers
        let lengthPenalty: Float
        let len = sentence.count
        if len < 20 { lengthPenalty = -0.1 }
        else if len > 500 { lengthPenalty = -0.05 }
        else { lengthPenalty = 0 }

        // --- Signal 4: Specificity bonus ---
        // Sentences with numbers, measurements, or technical terms score higher
        var specificityBonus: Float = 0
        let nsRange = NSRange(sentence.startIndex..., in: sentence)
        if ExtractiveQARegexes.measurements.firstMatch(in: sentence, range: nsRange) != nil {
            specificityBonus = 0.15 // Has measurements with units
        } else if ExtractiveQARegexes.digits.firstMatch(in: sentence, range: nsRange) != nil {
            specificityBonus = 0.05 // Has numbers
        }

        // Combine signals
        let rawScore = keywordScore * 0.50 + typeBonus + specificityBonus + passagePositionBonus + lengthPenalty
        return min(1.0, max(0, rawScore))
    }

    private func extractSpan(from sentence: String, type: QuestionType, question: String) -> String {
        switch type {
        case .howMany:
            // Extract numeric value with context
            let nsRange = NSRange(sentence.startIndex..., in: sentence)
            if let match = ExtractiveQARegexes.howManySpan.firstMatch(in: sentence, range: nsRange),
               let range = Range(match.range, in: sentence) {
                return String(sentence[range])
            }

        case .who:
            // Extract all person/org names
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            var names: [String] = []
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, range in
                if tag == .personalName || tag == .organizationName {
                    names.append(String(sentence[range]))
                }
                return true
            }
            if !names.isEmpty {
                return names.joined(separator: " ")
            }

        case .when:
            // Extract temporal expression
            let nsRange = NSRange(sentence.startIndex..., in: sentence)
            for regex in ExtractiveQARegexes.extractDatePatterns {
                if let match = regex.firstMatch(in: sentence, range: nsRange),
                   let range = Range(match.range, in: sentence) {
                    return String(sentence[range])
                }
            }

        case .where:
            // Extract place names
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            var places: [String] = []
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, range in
                if tag == .placeName {
                    places.append(String(sentence[range]))
                }
                return true
            }
            if !places.isEmpty {
                return places.joined(separator: ", ")
            }

        case .definition:
            // For "what is X?" try to extract the definitional part after "is"
            let sentenceLower = sentence.lowercased()
            let nsRange = NSRange(sentenceLower.startIndex..., in: sentenceLower)
            if let isMatch = ExtractiveQARegexes.extractIs.firstMatch(in: sentenceLower, range: nsRange),
               let isRange = Range(isMatch.range, in: sentenceLower) {
                let definition = String(sentence[isRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if definition.count > 10 && definition.count < 300 {
                    return definition.hasSuffix(".") ? String(definition.dropLast()) : definition
                }
            }

        default:
            break
        }

        // Fallback: return trimmed sentence (max 300 chars for more context)
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 300 {
            return String(trimmed.prefix(300)) + "..."
        }
        return trimmed
    }
}

// MARK: - Factory

/// Factory for creating the best available ExtractiveQA service
enum ExtractiveQAServiceFactory {
    /// Priority: CoreML model > Heuristic-v2 > Placeholder
    static func create() -> ExtractiveQAService {
        if OpenIntelligenceResourceBundle.url(forResource: "ExtractiveQAModel", withExtension: "mlmodelc") != nil {
            Log.info("ExtractiveQA: CoreML model found but implementation not ready, using heuristic-v2", category: .initialization)
        }
        return HeuristicExtractiveQAService()
    }
}
