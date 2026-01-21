//
//  LanguageDetectionService.swift
//  OpenIntelligence
//
//  Auto-detect document and query language using NLLanguageRecognizer.
//  Enables multi-language RAG without user configuration.
//

import Foundation
import NaturalLanguage

/// Detected language with confidence
struct DetectedLanguage: Sendable {
    let code: NLLanguage
    let confidence: Double
    let displayName: String

    /// Whether this is a high-confidence detection
    var isConfident: Bool { confidence > 0.8 }

    /// Whether this is English (optimization path)
    var isEnglish: Bool { code == .english }

    static let english = DetectedLanguage(
        code: .english,
        confidence: 1.0,
        displayName: "English"
    )

    static let unknown = DetectedLanguage(
        code: .undetermined,
        confidence: 0.0,
        displayName: "Unknown"
    )
}

/// Multi-language document metadata
struct DocumentLanguageProfile: Sendable {
    let primaryLanguage: DetectedLanguage
    let additionalLanguages: [DetectedLanguage]
    let isMultilingual: Bool
    let sampleSize: Int

    /// Get all languages above a confidence threshold
    func languages(above threshold: Double = 0.1) -> [DetectedLanguage] {
        var result = [primaryLanguage]
        result.append(contentsOf: additionalLanguages.filter { $0.confidence >= threshold })
        return result
    }
}

/// Service for detecting languages in documents and queries
@MainActor
final class LanguageDetectionService {
    static let shared = LanguageDetectionService()

    private let recognizer = NLLanguageRecognizer()

    // Cache recent detections to avoid re-processing
    private var cache: [Int: DetectedLanguage] = [:]
    private let maxCacheSize = 1000

    private init() {}

    // MARK: - Query Language Detection

    /// Detect the language of a query string
    /// Returns .english for very short queries (< 5 words) to avoid false positives
    func detectQueryLanguage(_ query: String) -> DetectedLanguage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Very short queries default to English (language detection unreliable)
        let wordCount = trimmed.components(separatedBy: .whitespaces).count
        if wordCount < 5 {
            return .english
        }

        // Check cache
        let cacheKey = trimmed.hashValue
        if let cached = cache[cacheKey] {
            return cached
        }

        // Detect language
        recognizer.reset()
        recognizer.processString(trimmed)

        guard let dominant = recognizer.dominantLanguage else {
            return .unknown
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominant] ?? 0.5

        let result = DetectedLanguage(
            code: dominant,
            confidence: confidence,
            displayName: Locale.current.localizedString(forLanguageCode: dominant.rawValue) ?? dominant.rawValue
        )

        // Cache result
        if cache.count >= maxCacheSize {
            cache.removeAll()
        }
        cache[cacheKey] = result

        Log.debug("[LanguageDetection] Query '\(trimmed.prefix(50))...' → \(result.displayName) (\(Int(confidence * 100))%)", category: .retrieval)

        return result
    }

    // MARK: - Document Language Detection

    /// Analyze a document's language profile
    /// Samples multiple sections for multi-language detection
    func analyzeDocument(_ text: String, sampleCount: Int = 5) -> DocumentLanguageProfile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return DocumentLanguageProfile(
                primaryLanguage: .unknown,
                additionalLanguages: [],
                isMultilingual: false,
                sampleSize: 0
            )
        }

        // For short documents, analyze the whole thing
        if trimmed.count < 1000 {
            let detected = detectText(trimmed)
            return DocumentLanguageProfile(
                primaryLanguage: detected,
                additionalLanguages: [],
                isMultilingual: false,
                sampleSize: trimmed.count
            )
        }

        // Sample multiple sections for longer documents
        let samples = extractSamples(from: trimmed, count: sampleCount)
        var languageCounts: [NLLanguage: (count: Int, totalConfidence: Double)] = [:]

        for sample in samples {
            let detected = detectText(sample)
            if detected.code != .undetermined {
                let current = languageCounts[detected.code] ?? (0, 0.0)
                languageCounts[detected.code] = (current.count + 1, current.totalConfidence + detected.confidence)
            }
        }

        // Sort by frequency
        let sorted = languageCounts.sorted { $0.value.count > $1.value.count }

        guard let primary = sorted.first else {
            return DocumentLanguageProfile(
                primaryLanguage: .unknown,
                additionalLanguages: [],
                isMultilingual: false,
                sampleSize: trimmed.count
            )
        }

        let primaryLanguage = DetectedLanguage(
            code: primary.key,
            confidence: primary.value.totalConfidence / Double(primary.value.count),
            displayName: Locale.current.localizedString(forLanguageCode: primary.key.rawValue) ?? primary.key.rawValue
        )

        let additional = sorted.dropFirst().map { entry in
            DetectedLanguage(
                code: entry.key,
                confidence: entry.value.totalConfidence / Double(entry.value.count),
                displayName: Locale.current.localizedString(forLanguageCode: entry.key.rawValue) ?? entry.key.rawValue
            )
        }

        let isMultilingual = additional.contains { $0.confidence > 0.3 }

        Log.info("[LanguageDetection] Document profile: \(primaryLanguage.displayName) (\(Int(primaryLanguage.confidence * 100))%), multilingual: \(isMultilingual)", category: .retrieval)

        return DocumentLanguageProfile(
            primaryLanguage: primaryLanguage,
            additionalLanguages: additional,
            isMultilingual: isMultilingual,
            sampleSize: trimmed.count
        )
    }

    // MARK: - Helpers

    private func detectText(_ text: String) -> DetectedLanguage {
        recognizer.reset()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage else {
            return .unknown
        }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[dominant] ?? 0.5

        return DetectedLanguage(
            code: dominant,
            confidence: confidence,
            displayName: Locale.current.localizedString(forLanguageCode: dominant.rawValue) ?? dominant.rawValue
        )
    }

    private func extractSamples(from text: String, count: Int) -> [String] {
        let length = text.count
        let sampleSize = min(500, length / count)
        let step = length / count

        var samples: [String] = []
        for i in 0 ..< count {
            let startOffset = i * step
            let startIndex = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex) ?? text.startIndex
            let endIndex = text.index(startIndex, offsetBy: sampleSize, limitedBy: text.endIndex) ?? text.endIndex
            samples.append(String(text[startIndex ..< endIndex]))
        }

        return samples
    }

    // MARK: - Embedding Language Matching

    /// Check if NLEmbedding supports a language
    func isEmbeddingSupported(for language: DetectedLanguage) -> Bool {
        // NLEmbedding.supportedLanguages returns available embedding models
        // Most common: English, Spanish, French, German, Italian, Portuguese, etc.
        return NLEmbedding.wordEmbedding(for: language.code) != nil
    }

    /// Get best embedding language for a detected language
    /// Falls back to English if language not supported
    func bestEmbeddingLanguage(for detected: DetectedLanguage) -> NLLanguage {
        if isEmbeddingSupported(for: detected) {
            return detected.code
        }
        // Fall back to English
        return .english
    }
}
