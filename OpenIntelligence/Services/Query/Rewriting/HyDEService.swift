//
//  HyDEService.swift
//  OpenIntelligence
//
//  Hypothetical Document Embeddings (HyDE) - Gao et al. 2022
//  "Precise Zero-Shot Dense Retrieval without Relevance Labels"
//
//  Instead of embedding the query directly, we first generate a hypothetical
//  answer, then embed THAT for retrieval. This bridges the vocabulary gap
//  between questions and documents.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// HyDE: Hypothetical Document Embeddings
/// Generates a hypothetical answer to the query, then embeds that for better retrieval
final class HyDEService: @unchecked Sendable {
    /// Whether HyDE is available (requires LLM)
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return SystemLanguageModel.default.isAvailable
            }
        #endif
        return false
    }

    /// Configuration for HyDE generation
    struct Config: Sendable {
        /// Maximum tokens for hypothetical answer
        let maxTokens: Int

        /// Whether to include domain hints
        let includeDomainHint: Bool

        /// Document type hint (e.g., "technical manual", "legal document")
        let documentTypeHint: String?

        nonisolated static var `default`: Config {
            Config(
                maxTokens: 150,
                includeDomainHint: true,
                documentTypeHint: nil
            )
        }

        nonisolated static func forDocumentType(_ type: String) -> Config {
            Config(maxTokens: 150, includeDomainHint: true, documentTypeHint: type)
        }
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private var session: LanguageModelSession?
    #endif

    init() {}

    /// Generate a hypothetical document that would answer the query
    /// - Parameters:
    ///   - query: The user's question
    ///   - config: HyDE configuration
    /// - Returns: A hypothetical document passage that would contain the answer
    func generateHypotheticalDocument(
        for query: String,
        config: Config = .default
    ) async throws -> String {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                throw HyDEError.unavailable
            }

            guard Self.isAvailable else {
                throw HyDEError.unavailable
            }

            let startTime = Date()

            // Build the HyDE prompt
            let prompt = buildHyDEPrompt(query: query, config: config)

            // Create session if needed
            if session == nil {
                let model = SystemLanguageModel.default
                session = LanguageModelSession(model: model)
            }

            guard let session = session else {
                throw HyDEError.sessionCreationFailed
            }

            // Generate hypothetical document
            let response = try await session.respond(to: prompt)
            let hypotheticalDoc = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            let elapsed = Date().timeIntervalSince(startTime)
            Log.info("[HyDE] Generated hypothetical doc in \(String(format: "%.0f", elapsed * 1000))ms: \"\(hypotheticalDoc.prefix(100))...\"", category: .retrieval)

            return hypotheticalDoc

        #else
            throw HyDEError.unavailable
        #endif
    }

    /// Ground hypothetical text against database vocabulary index, pruning out words with zero index presence
    func groundHyDEText(_ text: String, containerId: UUID) async -> String {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [(range: Range<String.Index>, text: String)] = []
        var wordsToQuery: [String] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let wordText = String(text[range])
            tokens.append((range, wordText))
            wordsToQuery.append(wordText)
            return true
        }

        guard !wordsToQuery.isEmpty else { return text }

        let presence = await SQLiteFullTextService.shared.checkVocabularyPresence(
            words: wordsToQuery,
            containerId: containerId
        )

        var result = ""
        var lastIndex = text.startIndex

        for token in tokens {
            let isPresent = presence[token.text] ?? true

            if token.range.lowerBound > lastIndex {
                result += text[lastIndex..<token.range.lowerBound]
            }

            if isPresent {
                result += token.text
            }

            lastIndex = token.range.upperBound
        }

        if lastIndex < text.endIndex {
            result += text[lastIndex..<text.endIndex]
        }

        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate hypothetical document and return both it and the original query
    /// This allows the retrieval system to search using both
    func generateHyDEQuery(
        for query: String,
        containerId: UUID? = nil,
        config: Config = .default
    ) async throws -> HyDEResult {
        let hypotheticalDoc = try await generateHypotheticalDocument(for: query, config: config)

        let groundedDoc: String
        if let containerId = containerId {
            groundedDoc = await groundHyDEText(hypotheticalDoc, containerId: containerId)
            Log.info("[HyDE] Grounded hypothetical doc (original: \(hypotheticalDoc.count) chars, grounded: \(groundedDoc.count) chars)", category: .retrieval)
        } else {
            groundedDoc = hypotheticalDoc
        }

        // UNIVERSAL FIX: Blend original query + hypothetical document for embedding.
        // This ensures the original query terms aren't lost in the generated text.
        let blendedText = "\(query) \(groundedDoc)"

        return HyDEResult(
            originalQuery: query,
            hypotheticalDocument: groundedDoc,
            // Blended: query vocabulary (intent) + hypothetical vocabulary (answer domain)
            combinedForEmbedding: blendedText
        )
    }

    private func buildHyDEPrompt(query: String, config: Config) -> String {
        // Extract key terms from the query to keep the hypothetical doc focused
        let keyTerms = extractKeyTerms(from: query)
        let keyTermsHint = keyTerms.isEmpty ? "" : " Key terms to include: \(keyTerms.joined(separator: ", "))."

        var prompt = """
        Write a brief factual passage (2-3 sentences) that would answer this question.
        Write as if this is an excerpt from a reference document.
        Your answer MUST directly address the question. Do NOT make up unrelated information.\(keyTermsHint)

        Question: \(query)

        """

        if config.includeDomainHint, let docType = config.documentTypeHint {
            prompt += "Context: This is from a \(docType).\n\n"
        }

        prompt += "Passage:"

        return prompt
    }

    /// Extract key terms from a query to keep HyDE grounded
    private func extractKeyTerms(from query: String) -> [String] {
        let stopWords: Set<String> = ["what", "what's", "how", "why", "when", "where", "which", "who",
                                      "is", "are", "was", "were", "do", "does", "did", "the", "a", "an",
                                      "to", "for", "of", "in", "on", "at", "by", "with", "about"]
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 && !stopWords.contains($0) }
        return Array(words.prefix(5))
    }

    /// Clear the session to free memory
    func resetSession() {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                session = nil
            }
        #endif
    }
}

/// Result of HyDE query expansion
struct HyDEResult: Sendable {
    /// The original user query
    let originalQuery: String

    /// The generated hypothetical document
    let hypotheticalDocument: String

    /// The text to use for embedding — blends original query + hypothetical document.
    /// The original query captures intent vocabulary; the hypothetical captures answer vocabulary.
    /// This ensures a wrong hypothetical doesn't completely hijack retrieval.
    let combinedForEmbedding: String
}

/// HyDE-specific errors
enum HyDEError: Error, LocalizedError {
    case unavailable
    case sessionCreationFailed
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HyDE requires Apple Intelligence which is not available"
        case .sessionCreationFailed:
            return "Failed to create language model session for HyDE"
        case let .generationFailed(reason):
            return "HyDE generation failed: \(reason)"
        }
    }
}

// MARK: - Integration with RAGService

extension HyDEService {
    /// Determine if HyDE should be used for this query
    /// HyDE works best for factual questions, not conversational queries
    static func shouldUseHyDE(for query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // HyDE is most effective for:
        // 1. Factual questions (what, when, where, how much, which)
        // 2. Technical queries
        // 3. Queries with specific entities

        let factualPatterns = [
            "what ", "which ", "when ", "where ", "how much", "how many",
            "what's ", "what is ", "what are ", "tell me about",
            "explain ", "describe ", "list ", "show me ",
        ]

        for pattern in factualPatterns {
            if trimmed.hasPrefix(pattern) || trimmed.contains(" \(pattern)") {
                return true
            }
        }

        // Also use for queries that look like they expect specific data
        let technicalIndicators = [
            "specification", "spec", "requirement", "capacity",
            "dimension", "weight", "size", "model", "version", "number",
        ]

        for indicator in technicalIndicators {
            if trimmed.contains(indicator) {
                return true
            }
        }

        return false
    }
}
