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

            guard let modelURL = Bundle.main.url(forResource: "ExtractiveQAModel", withExtension: "mlmodelc") else {
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

/// Heuristic-based extractive QA using NaturalLanguage framework.
/// Less accurate than neural model but provides basic span extraction capability.
/// Used as fallback when CoreML model is unavailable.
actor HeuristicExtractiveQAService: ExtractiveQAService {

    var isAvailable: Bool { true }

    var modelInfo: ExtractiveModelInfo {
        ExtractiveModelInfo(
            modelName: "HeuristicQA (NLTagger)",
            version: "1.0.0",
            maxSequenceLength: Int.max,
            vocabSize: 0,
            isLoaded: true,
            loadError: nil
        )
    }

    func extractAnswer(question: String, passages: [String]) async throws -> ExtractionResult? {
        // Detect question type to guide extraction
        let questionType = detectQuestionType(question)

        // Find sentences in passages that are most likely to contain the answer
        var bestCandidate: (span: String, confidence: Float, passageIndex: Int)?

        for (passageIndex, passage) in passages.enumerated() {
            let sentences = extractSentences(from: passage)

            for sentence in sentences {
                let score = scoreCandidate(sentence: sentence, question: question, type: questionType)

                if score > (bestCandidate?.confidence ?? 0) {
                    // Extract the specific answer span from the sentence
                    let span = extractSpan(from: sentence, type: questionType)
                    bestCandidate = (span, score, passageIndex)
                }
            }
        }

        guard let candidate = bestCandidate, candidate.confidence >= 0.3 else {
            return nil
        }

        let passage = passages[candidate.passageIndex]
        let range = passage.range(of: candidate.span) ?? passage.startIndex..<passage.startIndex

        return ExtractionResult(
            answerSpan: candidate.span,
            confidence: candidate.confidence,
            sourcePassageIndex: candidate.passageIndex,
            spanRange: range,
            startLogit: candidate.confidence,
            endLogit: candidate.confidence
        )
    }

    private enum QuestionType {
        case who, what, when, `where`, why, how, howMany, yesNo, other
    }

    private func detectQuestionType(_ question: String) -> QuestionType {
        let lower = question.lowercased()

        if lower.hasPrefix("who") { return .who }
        if lower.hasPrefix("what") { return .what }
        if lower.hasPrefix("when") { return .when }
        if lower.hasPrefix("where") { return .`where` }
        if lower.hasPrefix("why") { return .why }
        if lower.hasPrefix("how many") || lower.hasPrefix("how much") { return .howMany }
        if lower.hasPrefix("how") { return .how }
        if lower.hasPrefix("is ") || lower.hasPrefix("are ") ||
           lower.hasPrefix("does ") || lower.hasPrefix("do ") ||
           lower.hasPrefix("can ") || lower.hasPrefix("will ") { return .yesNo }

        return .other
    }

    private func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        }

        return sentences
    }

    private func scoreCandidate(sentence: String, question: String, type: QuestionType) -> Float {
        let sentenceLower = sentence.lowercased()
        let questionLower = question.lowercased()

        // Extract content words from question (skip stop words)
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "what", "who", "when", "where", "why", "how", "does", "do", "can", "will", "of", "in", "on", "at", "to", "for"]
        let questionWords = questionLower
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // Count keyword matches
        var matchCount = 0
        for word in questionWords {
            if sentenceLower.contains(word) {
                matchCount += 1
            }
        }

        let keywordScore = questionWords.isEmpty ? 0 : Float(matchCount) / Float(questionWords.count)

        // Bonus for answer type indicators
        var typeBonus: Float = 0

        switch type {
        case .who:
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, _ in
                if tag == .personalName || tag == .organizationName {
                    typeBonus = 0.3
                    return false
                }
                return true
            }

        case .when:
            // Look for date/time patterns
            let datePatterns = ["\\d{4}", "january|february|march|april|may|june|july|august|september|october|november|december", "monday|tuesday|wednesday|thursday|friday|saturday|sunday"]
            for pattern in datePatterns {
                if sentenceLower.range(of: pattern, options: .regularExpression) != nil {
                    typeBonus = 0.3
                    break
                }
            }

        case .where:
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = sentence
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameType) { tag, _ in
                if tag == .placeName {
                    typeBonus = 0.3
                    return false
                }
                return true
            }

        case .howMany:
            // Look for numbers
            if sentence.range(of: "\\d+", options: .regularExpression) != nil {
                typeBonus = 0.3
            }

        default:
            break
        }

        return min(1.0, keywordScore * 0.7 + typeBonus)
    }

    private func extractSpan(from sentence: String, type: QuestionType) -> String {
        // For now, return the full sentence as the span
        // Future: Use NLTagger to extract just the relevant noun phrase or entity

        switch type {
        case .howMany:
            // Try to extract just the numeric portion
            if let match = sentence.range(of: "\\d+[\\d,\\.]*\\s*\\w*", options: .regularExpression) {
                return String(sentence[match])
            }

        case .who:
            // Try to extract person/org name
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

        default:
            break
        }

        // Fallback: return trimmed sentence (max 200 chars)
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 200 {
            return String(trimmed.prefix(200)) + "..."
        }
        return trimmed
    }
}

// MARK: - Factory

/// Factory for creating the best available ExtractiveQA service
enum ExtractiveQAServiceFactory {
    /// Create the best available extractive QA service
    /// Priority: CoreML model > Heuristic fallback > Placeholder
    static func create() -> ExtractiveQAService {
        // Check if CoreML model is available
        if Bundle.main.url(forResource: "ExtractiveQAModel", withExtension: "mlmodelc") != nil {
            // Uncomment when CoreML implementation is ready:
            // return CoreMLExtractiveQAService()
            Log.info("ExtractiveQA: CoreML model found but implementation not ready, using heuristic", category: .initialization)
        }

        // Use heuristic service as default
        return HeuristicExtractiveQAService()
    }
}
