//
//  ContextualCompressionService.swift
//  OpenIntelligence
//
//  Contextual Compression - Extract only query-relevant content from chunks
//
//  Problem: Retrieved chunks contain relevant AND irrelevant sentences.
//           Sending all content wastes tokens and dilutes signal.
//
//  Solution: Use LLM to extract only sentences that help answer the query.
//            Can achieve 40-60% token reduction while improving answer quality.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Compresses retrieved chunks to only query-relevant content
final class ContextualCompressionService: @unchecked Sendable {
    /// Compression configuration
    struct Config: Sendable {
        /// Target compression ratio (0.3 = keep 30% of content)
        let targetCompressionRatio: Double

        /// Minimum sentences to keep per chunk
        let minSentences: Int

        /// Maximum input tokens before chunked processing
        let maxInputTokens: Int

        /// Whether to include contextually related content (not just directly answering)
        let includeRelatedContext: Bool

        nonisolated static var `default`: Config {
            Config(
                targetCompressionRatio: 0.6, // More conservative - keep 60%
                minSentences: 2,
                maxInputTokens: 1500,
                includeRelatedContext: true
            )
        }

        nonisolated static var conservative: Config {
            Config(
                targetCompressionRatio: 0.7, // Keep most context
                minSentences: 3,
                maxInputTokens: 2000,
                includeRelatedContext: true
            )
        }

        /// For "exactly" or detail-oriented queries - keep almost everything relevant
        nonisolated static var verbose: Config {
            Config(
                targetCompressionRatio: 0.85, // Keep 85% - minimal compression
                minSentences: 4,
                maxInputTokens: 2500,
                includeRelatedContext: true
            )
        }

        /// Aggressive compression for simple factual lookups
        nonisolated static var aggressive: Config {
            Config(
                targetCompressionRatio: 0.4,
                minSentences: 1,
                maxInputTokens: 1500,
                includeRelatedContext: false
            )
        }
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private var session: LanguageModelSession?
    #endif

    init() {}

    /// Compress a single chunk to query-relevant content
    /// - Parameters:
    ///   - chunk: The retrieved chunk text
    ///   - query: The user's query
    ///   - config: Compression settings
    /// - Returns: Compressed content containing only relevant sentences
    func compressChunk(
        _ chunk: String,
        forQuery query: String,
        config: Config = .default
    ) async throws -> CompressionResult {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                return CompressionResult.passthrough(chunk)
            }

            // Skip compression for short chunks
            let wordCount = chunk.split(separator: " ").count
            if wordCount < 50 {
                return CompressionResult.passthrough(chunk)
            }

            let startTime = Date()

            // Create session if needed
            if session == nil {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    return CompressionResult.passthrough(chunk)
                }
                session = LanguageModelSession(model: model)
            }

            guard let session = session else {
                return CompressionResult.passthrough(chunk)
            }

            let prompt = buildCompressionPrompt(chunk: chunk, query: query, config: config)

            let response = try await session.respond(to: prompt)
            let compressed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            let elapsed = Date().timeIntervalSince(startTime)
            let originalTokens = estimateTokens(chunk)
            let compressedTokens = estimateTokens(compressed)
            let ratio = Double(compressedTokens) / Double(originalTokens)

            Log.info("[Compression] \(originalTokens)→\(compressedTokens) tokens (\(String(format: "%.0f", ratio * 100))%) in \(String(format: "%.0f", elapsed * 1000))ms", category: .retrieval)

            return CompressionResult(
                originalContent: chunk,
                compressedContent: compressed,
                originalTokens: originalTokens,
                compressedTokens: compressedTokens,
                compressionRatio: ratio
            )

        #else
            return CompressionResult.passthrough(chunk)
        #endif
    }

    /// Compress multiple chunks in parallel
    func compressChunks(
        _ chunks: [String],
        forQuery query: String,
        config: Config = .default
    ) async throws -> [CompressionResult] {
        // Process in batches to avoid overwhelming the model
        var results: [CompressionResult] = []

        for chunk in chunks {
            let result = try await compressChunk(chunk, forQuery: query, config: config)
            results.append(result)
        }

        let totalOriginal = results.reduce(0) { $0 + $1.originalTokens }
        let totalCompressed = results.reduce(0) { $0 + $1.compressedTokens }

        if totalOriginal > 0 {
            let overallRatio = Double(totalCompressed) / Double(totalOriginal)
            Log.info("[Compression] Total: \(totalOriginal)→\(totalCompressed) tokens (\(String(format: "%.0f", overallRatio * 100))% of original)", category: .retrieval)
        }

        return results
    }

    private func buildCompressionPrompt(chunk: String, query: String, config: Config) -> String {
        if config.includeRelatedContext {
            // Verbose prompt: include related context for comprehensive answers
            return """
            Extract sentences from this text that help answer the question comprehensively.
            Include:
            - Sentences that directly answer the question
            - Related context that provides important background
            - Technical details, specifications, or procedures mentioned
            - Connections to other relevant concepts

            Keep exact wording - do not paraphrase. Preserve technical terms and values.
            Only respond with "NO_RELEVANT_CONTENT" if the text is completely unrelated.

            Question: \(query)

            Text:
            \(chunk)

            Relevant content:
            """
        } else {
            // Aggressive prompt: only directly answering sentences
            return """
            Extract ONLY the sentences that directly answer the question.
            Remove all unrelated content. Keep exact wording - do not paraphrase.
            If nothing is relevant, respond with "NO_RELEVANT_CONTENT".

            Question: \(query)

            Text to compress:
            \(chunk)

            Relevant sentences only:
            """
        }
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimate: 1 token ≈ 4 characters for English
        return max(1, text.count / 4)
    }

    /// Reset session to free memory
    func resetSession() {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                session = nil
            }
        #endif
    }
}

/// Result of contextual compression
struct CompressionResult: Sendable {
    let originalContent: String
    let compressedContent: String
    let originalTokens: Int
    let compressedTokens: Int
    let compressionRatio: Double

    /// Returns true if compression removed content
    nonisolated var wasCompressed: Bool {
        compressionRatio < 0.95
    }

    /// Returns the content to use
    /// If compression found nothing relevant, returns a truncated version of original
    /// (the chunk passed retrieval so it likely has SOME value)
    nonisolated var effectiveContent: String {
        if compressedContent.contains("NO_RELEVANT_CONTENT") || compressedContent.isEmpty {
            // Don't drop entirely - keep first 200 chars as fallback
            // The chunk passed hybrid search + reranking so it has some relevance
            let fallback = String(originalContent.prefix(400))
            if fallback.count < originalContent.count {
                return fallback + "..."
            }
            return originalContent
        }
        return compressedContent
    }

    /// Returns true if compression marked this chunk as irrelevant
    nonisolated var wasMarkedIrrelevant: Bool {
        compressedContent.contains("NO_RELEVANT_CONTENT") || compressedContent.isEmpty
    }

    /// Passthrough result when compression is skipped
    nonisolated static func passthrough(_ content: String) -> CompressionResult {
        let tokens = max(1, content.count / 4)
        return CompressionResult(
            originalContent: content,
            compressedContent: content,
            originalTokens: tokens,
            compressedTokens: tokens,
            compressionRatio: 1.0
        )
    }
}

// MARK: - Answer Verification

extension ContextualCompressionService {
    /// Verify that an answer is grounded in the provided context
    /// - Parameters:
    ///   - answer: The generated answer
    ///   - context: The retrieved context chunks
    ///   - query: The original query
    /// - Returns: Verification result with confidence score
    func verifyAnswerGrounding(
        answer: String,
        context: [String],
        query: String
    ) async throws -> GroundingVerification {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                return GroundingVerification.unverified
            }

            if session == nil {
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    return GroundingVerification.unverified
                }
                session = LanguageModelSession(model: model)
            }

            guard let session = session else {
                return GroundingVerification.unverified
            }

            let combinedContext = context.joined(separator: "\n\n---\n\n")

            let prompt = """
            Analyze whether this answer is fully grounded in the provided context.

            Question: \(query)

            Context:
            \(combinedContext.prefix(3000))

            Answer to verify:
            \(answer)

            Respond with ONLY one of:
            - GROUNDED: Answer is fully supported by context
            - PARTIAL: Answer is partially supported but adds unsupported claims
            - UNGROUNDED: Answer contains significant unsupported claims
            - NOT_ANSWERABLE: Context doesn't contain enough info to answer

            Then on a new line, briefly explain why (one sentence).
            """

            let response = try await session.respond(to: prompt)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            return parseGroundingResult(result)

        #else
            return GroundingVerification.unverified
        #endif
    }

    private func parseGroundingResult(_ result: String) -> GroundingVerification {
        let lines = result.components(separatedBy: "\n")
        let firstLine = lines.first?.uppercased() ?? ""
        let explanation = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if firstLine.contains("GROUNDED") && !firstLine.contains("UNGROUNDED") {
            return GroundingVerification(
                status: .grounded,
                confidence: 0.9,
                explanation: explanation
            )
        } else if firstLine.contains("PARTIAL") {
            return GroundingVerification(
                status: .partiallyGrounded,
                confidence: 0.6,
                explanation: explanation
            )
        } else if firstLine.contains("NOT_ANSWERABLE") {
            return GroundingVerification(
                status: .notAnswerable,
                confidence: 0.7,
                explanation: explanation
            )
        } else {
            return GroundingVerification(
                status: .ungrounded,
                confidence: 0.3,
                explanation: explanation
            )
        }
    }
}

/// Result of answer grounding verification
struct GroundingVerification: Sendable {
    enum Status: Sendable {
        case grounded // Answer fully supported
        case partiallyGrounded // Some claims unsupported
        case ungrounded // Significant hallucination
        case notAnswerable // Context insufficient
        case unverified // Couldn't verify (model unavailable)
    }

    let status: Status
    let confidence: Double // 0.0 - 1.0
    let explanation: String

    static let unverified = GroundingVerification(
        status: .unverified,
        confidence: 0.0,
        explanation: "Verification unavailable"
    )
}
