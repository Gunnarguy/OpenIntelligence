//
//  DocumentSummaryService.swift
//  OpenIntelligence
//
//  Generates document-level summaries at ingestion time for RAPTOR-lite retrieval.
//  Summaries are stored as "level-1" chunks, enabling fast overview queries.
//
//  Created January 2026
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
    import FoundationModels
#endif

// NOTE: ChunkAbstractionLevel is defined in DocumentChunk.swift and shared across the codebase

// MARK: - Document Summary Service

private enum DocumentSummaryError: LocalizedError {
    case emptyResponse
    case timedOut(seconds: UInt64)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Summary generation returned an empty response."
        case let .timedOut(seconds):
            return "Summary generation timed out after \(seconds)s."
        }
    }
}

/// Service for generating document-level summaries using Apple Intelligence.
/// Part of RAPTOR-lite implementation for efficient overview queries.
actor DocumentSummaryService {

    // MARK: - Configuration

    nonisolated private static let summaryGenerationTimeoutSeconds: UInt64 = 12

    nonisolated private static let summaryInstructions = """
    You generate short document overview summaries for search indexing. Be concise, factual, and avoid commentary.
    """

    struct SummaryConfig: Sendable {
        /// Target word count for summaries
        let targetWords: Int
        /// Maximum input characters for summarization (prevents context overflow)
        /// CRITICAL: Technical text can have 2.5+ tokens/word, so be conservative
        /// 4096 token limit - 200 output tokens - 100 prompt overhead = ~3800 max input tokens
        /// At 2.5 tokens/word and 5 chars/word: ~3800/2.5 * 5 = 7600 chars
        /// Use 5500 for safety margin with highly technical documents (manuals, specs)
        let maxInputChars: Int
        /// Whether to include entity extraction in summary
        let extractEntities: Bool
        /// Whether to include key topics
        let extractTopics: Bool

        static let `default` = SummaryConfig(
            targetWords: 150,
            maxInputChars: 5500,  // ~1400-1800 tokens, leaves room for output + prompt
            extractEntities: true,
            extractTopics: true
        )

        static let compact = SummaryConfig(
            targetWords: 80,
            maxInputChars: 3500,
            extractEntities: false,
            extractTopics: true
        )
    }

    // MARK: - Dependencies

    private weak var ragService: RAGService?
    private let config: SummaryConfig

    // MARK: - Initialization

    init(ragService: RAGService? = nil, config: SummaryConfig = .default) {
        self.ragService = ragService
        self.config = config
    }

    func setRAGService(_ service: RAGService) {
        self.ragService = service
    }

    // MARK: - Summary Generation

    /// Generates a summary for a document from its chunks.
    /// Returns a DocumentChunk with abstractionLevel = .documentSummary
    func generateDocumentSummary(
        documentId: UUID,
        documentName: String,
        chunks: [DocumentChunk],
        embeddingService: EmbeddingService,
        embeddingTranslationTarget: Locale.Language? = nil
    ) async throws -> DocumentChunk {

        Log.info("[DocumentSummary] Generating summary for '\(documentName)' (\(chunks.count) chunks)", category: .pipeline)

        // 1. Build representative text from chunks
        let representativeText = buildRepresentativeText(from: chunks)

        // 2. Generate summary via LLM
        let summaryText = try await generateSummaryViaLLM(
            documentName: documentName,
            representativeText: representativeText
        )

        // 3. Generate embedding for the summary
        let baseSummaryEmbeddingText = "[Document Summary: \(documentName)] \(summaryText)"
        let summaryEmbeddingText: String
        if let targetLanguage = embeddingTranslationTarget {
            do {
                let translationResult = try await TranslationService.shared.translate(
                    baseSummaryEmbeddingText,
                    to: targetLanguage
                )
                summaryEmbeddingText = translationResult.translatedText
            } catch {
                Log.warning("[DocumentSummary] Summary translation failed for '\(documentName)': \(error)", category: .pipeline)
                summaryEmbeddingText = baseSummaryEmbeddingText
            }
        } else {
            summaryEmbeddingText = baseSummaryEmbeddingText
        }

        let summaryEmbedding = try await embeddingService.generateEmbedding(
            for: summaryEmbeddingText
        )

        // 4. Extract entities from summary
        let entities = extractEntitiesFromSummary(summaryText)

        // 5. Extract keywords before MainActor.run (since extractKeywords is actor-isolated)
        let keywords = extractKeywords(from: summaryText)

        // 6. Build metadata and chunk on MainActor (Swift 6 isolation requirement)
        let summaryChunk = await MainActor.run {
            let metadata = ChunkMetadata(
                chunkIndex: -1,  // Special index for summaries
                startPosition: 0,
                endPosition: summaryText.count,
                pageNumber: nil,
                sectionTitle: "Document Summary",
                keywords: keywords,
                semanticDensity: 1.0,  // Summaries are maximally dense
                hasNumericData: false,
                hasListStructure: false,
                wordCount: summaryText.split(separator: " ").count,
                characterCount: summaryText.count,
                createdAt: Date(),
                siblingGroupId: "summary-\(documentId.uuidString)",
                siblingCount: 1,
                entities: entities,
                abstractionLevel: .documentSummary
            )

            // Create summary chunk
            return DocumentChunk(
                id: UUID(),
                documentId: documentId,
                content: summaryText,
                parentContent: nil,
                contextualPrefix: "[Summary of \(documentName)]",
                embedding: summaryEmbedding,
                metadata: metadata
            )
        }

        Log.info("[DocumentSummary] Generated \(summaryText.split(separator: " ").count)-word summary", category: .pipeline)

        return summaryChunk
    }

    // MARK: - Private Helpers

    /// Builds representative text from chunks for summarization.
    /// Prioritizes first chunks, section headers, and high-density chunks.
    private func buildRepresentativeText(from chunks: [DocumentChunk]) -> String {
        var selectedText: [String] = []
        var charCount = 0

        // Strategy: Take first 2 chunks (intro), last chunk (conclusion),
        // and fill middle with highest semantic density chunks

        let sortedByDensity = chunks.sorted {
            ($0.metadata.semanticDensity ?? 0) > ($1.metadata.semanticDensity ?? 0)
        }

        // First chunk (intro)
        if let first = chunks.first {
            selectedText.append(first.content)
            charCount += first.content.count
        }

        // High-density chunks from middle
        for chunk in sortedByDensity {
            guard charCount < config.maxInputChars else { break }

            // Skip if already added (first/last)
            if chunk.id == chunks.first?.id || chunk.id == chunks.last?.id {
                continue
            }

            selectedText.append(chunk.content)
            charCount += chunk.content.count
        }

        // Last chunk (conclusion) if different from first
        if chunks.count > 1, let last = chunks.last {
            if charCount + last.content.count <= config.maxInputChars {
                selectedText.append(last.content)
            }
        }

        return selectedText.joined(separator: "\n\n")
    }

    /// Generates summary text using Apple Intelligence
    private func generateSummaryViaLLM(
        documentName: String,
        representativeText: String
    ) async throws -> String {

        guard let ragService = ragService else {
            // Fallback: extractive summary (first 150 words)
            Log.warning("[DocumentSummary] No RAGService available, using extractive fallback", category: .pipeline)
            return extractiveFallback(from: representativeText)
        }

        // HARD LIMIT: Summaries MUST fit embedding context (510 tokens max)
        // With prefix overhead, target ~120 words max to stay safe
        let safeTargetWords = min(config.targetWords, 120)

        // Pre-flight token estimation with conservative 2.5 chars/token
        // Apple FM context window is 4096 tokens
        // Budget: 4096 - 200 (output) - 150 (prompt overhead) = 3746 input tokens max
        let maxInputTokens = 3746
        let estimatedTokens = Int(ceil(Double(representativeText.count) / 2.5))

        // Truncate input if estimated tokens exceed budget
        let safeInputText: String
        if estimatedTokens > maxInputTokens {
            let safeCharLimit = Int(Double(maxInputTokens) * 2.5)
            safeInputText = String(representativeText.prefix(safeCharLimit))
            Log.warning("[DocumentSummary] Truncating input from \(representativeText.count) to \(safeCharLimit) chars (estimated \(estimatedTokens) → \(maxInputTokens) tokens)", category: .pipeline)
        } else {
            safeInputText = String(representativeText.prefix(config.maxInputChars))
        }

        let prompt = """
        Summarize this document in EXACTLY \(safeTargetWords) words or fewer. Do NOT exceed this limit.
        Focus on: main topics, key information, and document purpose.
        Be extremely concise. Stop when you reach \(safeTargetWords) words.

        Document: \(documentName)

        Content:
        \(safeInputText)

        Summary (\(safeTargetWords) words max):
        """

        #if canImport(FoundationModels)
            if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
                do {
                    let responseText = try await generateSummaryWithFoundationModels(prompt: prompt)
                    return enforceWordLimit(responseText, maxWords: 150)
                } catch {
                    Log.warning("[DocumentSummary] Apple FM summary timed out/failed for '\(documentName)': \(error), using extractive fallback", category: .pipeline)
                    return extractiveFallback(from: representativeText)
                }
            }
        #endif

        do {
            // Use the LLM service directly for summary generation
            // Access llmService and build config on MainActor since RAGService is @MainActor isolated
            let (llmService, inferenceConfig) = await MainActor.run { () -> (LLMService, InferenceConfig) in
                var config = InferenceConfig()
                config.temperature = 0.3
                // Limit tokens to ~150 words max (at ~1.5 tokens/word = 225 tokens)
                // Lower than before to reduce continuation triggering
                config.maxTokens = 200
                // CRITICAL: Skip continuation for summaries - we want concise output
                // Continuation was causing 516-word summaries that blew past 510-token embedding limit
                config.skipContinuation = true
                return (ragService.llmService, config)
            }

            // The system prompt is embedded in the prompt for summary generation
            let fullPrompt = "You are a document summarization assistant. Generate concise, informative summaries.\n\n" + prompt

            // NOTE: Continuation is disabled via config.skipContinuation
            // We also enforce hard truncation below as safety net
            let response = try await llmService.generate(
                prompt: fullPrompt,
                context: nil,
                config: inferenceConfig
            )

            return enforceWordLimit(response.text, maxWords: 150)

        } catch {
            Log.error("[DocumentSummary] LLM summary failed: \(error), using extractive fallback", category: .pipeline)
            return extractiveFallback(from: representativeText)
        }
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private func generateSummaryWithFoundationModels(prompt: String) async throws -> String {
            try Task.checkCancellation()

            // `model:` is required. Omitting it yields a session that produces no output: an Instruments
            // capture on 2026-08-15 recorded two such calls returning 0 tokens over 6.5 and 7.1
            // seconds with an empty Response, while every session built with an explicit model
            // succeeded in the same run. The bare `LanguageModelSession()` initialiser was fixed at
            // ten sites on 2026-08-14; these pass instructions but still omitted the model, so they
            // were missed by a grep for the no-argument form.
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Instructions(Self.summaryInstructions))

            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let response = try await session.respond(to: prompt)
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else {
                        throw DocumentSummaryError.emptyResponse
                    }
                    return text
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: Self.summaryGenerationTimeoutSeconds * 1_000_000_000)
                    throw DocumentSummaryError.timedOut(seconds: Self.summaryGenerationTimeoutSeconds)
                }

                guard let result = try await group.next() else {
                    throw DocumentSummaryError.emptyResponse
                }
                group.cancelAll()
                return result
            }
        }
    #endif

    private func enforceWordLimit(_ text: String, maxWords: Int) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let words = trimmed.split(separator: " ")
        guard words.count > maxWords else { return trimmed }

        Log.warning("[DocumentSummary] Truncating \(words.count)-word summary to \(maxWords) words", category: .pipeline)
        return words.prefix(maxWords).joined(separator: " ") + "..."
    }

    /// Extractive fallback when LLM is unavailable
    private func extractiveFallback(from text: String) -> String {
        let words = text.split(separator: " ")
        let targetWords = min(config.targetWords, words.count)
        return words.prefix(targetWords).joined(separator: " ") + "..."
    }

    /// Extract keywords from summary text
    private func extractKeywords(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 4 }

        // Simple frequency-based extraction
        var frequency: [String: Int] = [:]
        for word in words {
            frequency[word, default: 0] += 1
        }

        return frequency
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }

    /// Extract entities from summary using NLTagger
    private func extractEntitiesFromSummary(_ text: String) -> [String] {
        guard config.extractEntities else { return [] }

        var entities: [String] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag, [.personalName, .organizationName, .placeName].contains(tag) {
                let entity = String(text[range])
                if entity.count > 2 && !entities.contains(entity) {
                    entities.append(entity)
                }
            }
            return true
        }

        return Array(entities.prefix(15))
    }
}

// MARK: - Summary Chunk Detection

extension DocumentChunk {
    /// Whether this chunk is a document summary (level 1) rather than detail (level 0)
    var isDocumentSummary: Bool {
        metadata.abstractionLevel == .documentSummary
    }

    /// Whether this chunk is any kind of summary (level > 0)
    var isSummaryChunk: Bool {
        metadata.abstractionLevel.rawValue > 0
    }
}
