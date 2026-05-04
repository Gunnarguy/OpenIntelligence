//
//  TranslationService.swift
//  OpenIntelligence
//
//  On-device multilingual translation using Translation.framework.
//  Enables cross-language RAG: translate foreign documents before embedding
//  and translate queries/responses for multilingual interaction.
//

import Combine
import Foundation
import Translation
import NaturalLanguage

/// Result of a translation operation
struct TranslationResult: Sendable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let isTranslated: Bool  // false if source == target (no-op)
}

/// Configuration for batch translation
struct TranslationConfig: Sendable {
    let targetLanguage: Locale.Language
    let preserveFormatting: Bool
    let maxBatchSize: Int

    static let defaultEnglish = TranslationConfig(
        targetLanguage: Locale.Language(identifier: "en"),
        preserveFormatting: true,
        maxBatchSize: 50
    )
}

/// Service for on-device translation using Apple Translation.framework
/// Translates foreign documents/chunks to English before embedding for multilingual RAG.
@MainActor
final class TranslationService: ObservableObject {
    static let shared = TranslationService()

    @Published private(set) var isTranslating = false
    @Published private(set) var availableLanguagePairs: [LanguageAvailability.Status] = []

    private let languageAvailability = LanguageAvailability()

    private init() {}

    // MARK: - Language Availability

    /// Check if translation is available between two languages
    func isTranslationAvailable(
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> Bool {
        let status = await languageAvailability.status(
            from: source,
            to: target
        )
        return status == .installed || status == .supported
    }

    /// Check if a language pair is already downloaded for offline use
    func isLanguagePairInstalled(
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> Bool {
        let status = await languageAvailability.status(
            from: source,
            to: target
        )
        return status == .installed
    }

    // MARK: - Single Text Translation

    /// Translate a single text string to the target language
    /// Returns original text unchanged if source == target or translation unavailable
    func translate(
        _ text: String,
        to targetLanguage: Locale.Language = Locale.Language(identifier: "en")
    ) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranslationResult(
                originalText: text,
                translatedText: text,
                sourceLanguage: targetLanguage,
                targetLanguage: targetLanguage,
                isTranslated: false
            )
        }

        // Detect source language using existing LanguageDetectionService
        let detected = LanguageDetectionService.shared.detectQueryLanguage(trimmed)
        let sourceLocale = Locale.Language(identifier: detected.code.rawValue)

        // Skip translation if already in target language
        if detected.code.rawValue == targetLanguage.languageCode?.identifier ?? "en" {
            return TranslationResult(
                originalText: text,
                translatedText: text,
                sourceLanguage: sourceLocale,
                targetLanguage: targetLanguage,
                isTranslated: false
            )
        }

        // Check availability
        guard await isTranslationAvailable(from: sourceLocale, to: targetLanguage) else {
            Log.warning("[Translation] No translation available from \(detected.displayName) to \(targetLanguage.languageCode?.identifier ?? "?")", category: .ingestion)
            return TranslationResult(
                originalText: text,
                translatedText: text,
                sourceLanguage: sourceLocale,
                targetLanguage: targetLanguage,
                isTranslated: false
            )
        }

        isTranslating = true
        defer {
            isTranslating = false
            HardwareTelemetryState.shared.sustain(.queryProcessing, active: false)
        }

        DSHaptics.processingPulse()
        HardwareTelemetryState.shared.sustain(.queryProcessing, active: true, intensity: 0.7)

        var translatedText = text
        let session = TranslationSession(installedSource: sourceLocale, target: targetLanguage)
        let response = try await session.translate(trimmed)
        translatedText = response.targetText

        Log.info("[Translation] \(detected.displayName) → \(targetLanguage.languageCode?.identifier ?? "en"): '\(trimmed.prefix(50))...' → '\(translatedText.prefix(50))...'", category: .ingestion)

        return TranslationResult(
            originalText: text,
            translatedText: translatedText,
            sourceLanguage: sourceLocale,
            targetLanguage: targetLanguage,
            isTranslated: true
        )
    }

    // MARK: - Batch Translation (for document chunks)

    /// Translate multiple text chunks in a batch for efficient document processing
    /// Used during ingestion to translate foreign-language chunks to English before embedding
    func translateBatch(
        _ texts: [String],
        to targetLanguage: Locale.Language = Locale.Language(identifier: "en"),
        sourceLanguage: Locale.Language? = nil
    ) async throws -> [TranslationResult] {
        guard !texts.isEmpty else { return [] }

        isTranslating = true
        defer {
            isTranslating = false
            HardwareTelemetryState.shared.sustain(.queryProcessing, active: false)
        }

        DSHaptics.processingPulse()
        HardwareTelemetryState.shared.sustain(.queryProcessing, active: true, intensity: 0.8)

        // Determine source language from first substantial chunk
        let effectiveSource: Locale.Language
        if let source = sourceLanguage {
            effectiveSource = source
        } else {
            let sampleText = texts.first(where: { $0.count > 50 }) ?? texts[0]
            let detected = LanguageDetectionService.shared.detectQueryLanguage(sampleText)
            effectiveSource = Locale.Language(identifier: detected.code.rawValue)
        }

        // Check if translation is even needed
        if effectiveSource.languageCode?.identifier == targetLanguage.languageCode?.identifier {
            return texts.map { text in
                TranslationResult(
                    originalText: text,
                    translatedText: text,
                    sourceLanguage: effectiveSource,
                    targetLanguage: targetLanguage,
                    isTranslated: false
                )
            }
        }

        // Check availability
        guard await isTranslationAvailable(from: effectiveSource, to: targetLanguage) else {
            Log.warning("[Translation] Batch: no translation available from \(effectiveSource.languageCode?.identifier ?? "?") to \(targetLanguage.languageCode?.identifier ?? "?")", category: .ingestion)
            return texts.map { text in
                TranslationResult(
                    originalText: text,
                    translatedText: text,
                    sourceLanguage: effectiveSource,
                    targetLanguage: targetLanguage,
                    isTranslated: false
                )
            }
        }

        let batchSize = max(1, TranslationConfig.defaultEnglish.maxBatchSize)
        var results: [TranslationResult] = []
        results.reserveCapacity(texts.count)

        for startIndex in stride(from: 0, to: texts.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, texts.count)
            let batch = Array(texts[startIndex..<endIndex])
            let batchResults = try await performBatchTranslation(
                batch,
                from: effectiveSource,
                to: targetLanguage
            )
            results.append(contentsOf: batchResults)
        }

        DSHaptics.success()
        Log.info("[Translation] Batch translated \(results.count) chunks from \(effectiveSource.languageCode?.identifier ?? "?") to \(targetLanguage.languageCode?.identifier ?? "en")", category: .ingestion)

        return results
    }

    private func performBatchTranslation(
        _ texts: [String],
        from sourceLanguage: Locale.Language,
        to targetLanguage: Locale.Language
    ) async throws -> [TranslationResult] {
        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let requests = texts.map { TranslationSession.Request(sourceText: $0) }
        let responses = try await session.translations(from: requests)

        return zip(texts, responses).map { original, response in
            TranslationResult(
                originalText: original,
                translatedText: response.targetText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                isTranslated: true
            )
        }
    }

    // MARK: - Document Pre-Processing

    /// Translate a full document's text to English before chunking/embedding
    /// Returns the original text if already in English or translation unavailable
    func translateDocumentForIngestion(_ text: String) async throws -> (text: String, wasTranslated: Bool, sourceLanguage: String) {
        let profile = LanguageDetectionService.shared.analyzeDocument(text)

        // Already English or unknown — no translation needed
        if profile.primaryLanguage.isEnglish || profile.primaryLanguage.code == .undetermined {
            return (text, false, profile.primaryLanguage.displayName)
        }

        // High-confidence non-English detection
        guard profile.primaryLanguage.isConfident else {
            Log.info("[Translation] Low confidence language detection (\(Int(profile.primaryLanguage.confidence * 100))%), skipping translation", category: .ingestion)
            return (text, false, profile.primaryLanguage.displayName)
        }

        let result = try await translate(text, to: Locale.Language(identifier: "en"))
        return (result.translatedText, result.isTranslated, profile.primaryLanguage.displayName)
    }

    // MARK: - Cross-Language Query Support

    /// Translate a user query to match the document language, or translate
    /// a non-English query to English for English-indexed documents
    func translateQueryForRetrieval(
        _ query: String,
        documentLanguage: NLLanguage = .english
    ) async throws -> String {
        let queryLang = LanguageDetectionService.shared.detectQueryLanguage(query)

        // Query already matches document language
        if queryLang.code == documentLanguage {
            return query
        }

        // Translate query to document language
        let targetLocale = Locale.Language(identifier: documentLanguage.rawValue)
        let result = try await translate(query, to: targetLocale)
        return result.translatedText
    }
}
