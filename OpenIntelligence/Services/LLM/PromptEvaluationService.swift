//
//  PromptEvaluationService.swift
//  OpenIntelligence
//
//  Automated prompt quality evaluation using Apple FoundationModels API.
//  Tests prompt templates against reference Q&A pairs to measure RAG quality,
//  detect regressions, and optimize prompt engineering.
//

import Foundation
import FoundationModels

/// A test case for prompt evaluation
struct PromptTestCase: Codable, Sendable, Identifiable {
    let id: UUID
    let query: String
    let expectedKeywords: [String]       // Keywords that SHOULD appear in response
    let forbiddenKeywords: [String]      // Keywords that should NOT appear (hallucination markers)
    let referenceAnswer: String?         // Gold standard answer for comparison
    let category: String                 // e.g., "factual", "procedural", "comparison"

    nonisolated init(
        id: UUID = UUID(),
        query: String,
        expectedKeywords: [String] = [],
        forbiddenKeywords: [String] = [],
        referenceAnswer: String? = nil,
        category: String = "general"
    ) {
        self.id = id
        self.query = query
        self.expectedKeywords = expectedKeywords
        self.forbiddenKeywords = forbiddenKeywords
        self.referenceAnswer = referenceAnswer
        self.category = category
    }
}

/// Result of evaluating a single prompt test case
struct PromptEvalResult: Sendable, Identifiable {
    let id = UUID()
    let testCase: PromptTestCase
    let response: String
    let keywordHitRate: Double          // % of expected keywords found
    let forbiddenKeywordViolations: [String]  // Forbidden keywords that appeared
    let responseLengthTokens: Int
    let latencySeconds: TimeInterval
    let confidenceScore: Double         // Overall quality score 0-1
    let passed: Bool
}

/// Aggregate results for a prompt evaluation suite
struct PromptEvalSuiteResult: Sendable {
    let suiteName: String
    let results: [PromptEvalResult]
    let overallScore: Double            // Average confidence across all tests
    let passRate: Double                // % of tests that passed
    let averageLatency: TimeInterval
    let totalDuration: TimeInterval
    let timestamp: Date
}

/// Service for automated prompt quality evaluation and regression testing
actor PromptEvaluationService {
    static let shared = PromptEvaluationService()

    private var testSuites: [String: [PromptTestCase]] = [:]
    private var evaluationHistory: [PromptEvalSuiteResult] = []

    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let dir = appSupport.appendingPathComponent("OpenIntelligence/PromptEval", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test_suites.json")
    }()

    private init() {
        Task { await loadTestSuites() }
    }

    // MARK: - Test Suite Management

    /// Register a test suite with named test cases
    func registerSuite(name: String, testCases: [PromptTestCase]) {
        testSuites[name] = testCases
        Task { saveTestSuites() }
        Log.info("[PromptEval] Registered suite '\(name)' with \(testCases.count) test cases", category: .llm)
    }

    /// Get all registered suite names
    func registeredSuites() -> [String] {
        Array(testSuites.keys)
    }

    /// Generate test cases from existing RAG interactions (auto-create evaluation suite)
    func generateTestCases(
        from interactions: [(query: String, response: String, chunks: [RetrievedChunk])],
        suiteName: String = "auto-generated"
    ) -> [PromptTestCase] {
        var cases: [PromptTestCase] = []

        for interaction in interactions {
            // Extract key nouns from the response as expected keywords
            let keywords = extractSignificantWords(from: interaction.response)

            let testCase = PromptTestCase(
                query: interaction.query,
                expectedKeywords: Array(keywords.prefix(5)),
                referenceAnswer: interaction.response,
                category: classifyQuery(interaction.query)
            )
            cases.append(testCase)
        }

        testSuites[suiteName] = cases
        return cases
    }

    // MARK: - Evaluation Execution

    /// Run a prompt evaluation suite against the current prompt template
    /// - Parameters:
    ///   - suiteName: Name of the test suite to run
    ///   - promptTemplate: The prompt template to evaluate (use {query} and {context} placeholders)
    ///   - contextProvider: Closure that provides context chunks for a query
    /// - Returns: Suite evaluation results
    func evaluateSuite(
        suiteName: String,
        promptTemplate: String,
        contextProvider: @Sendable (String) async throws -> String
    ) async throws -> PromptEvalSuiteResult {
        guard let testCases = testSuites[suiteName] else {
            throw PromptEvalError.suiteNotFound(suiteName)
        }

        let suiteStart = Date()
        var results: [PromptEvalResult] = []
        HardwareTelemetryReporter.sustain(.llmInference, active: true, intensity: 0.8)

        for testCase in testCases {
            let result = try await evaluateTestCase(
                testCase,
                promptTemplate: promptTemplate,
                contextProvider: contextProvider
            )
            results.append(result)
        }

        HardwareTelemetryReporter.sustain(.llmInference, active: false)

        let suiteResult = PromptEvalSuiteResult(
            suiteName: suiteName,
            results: results,
            overallScore: results.isEmpty ? 0 : results.map(\.confidenceScore).reduce(0, +) / Double(results.count),
            passRate: results.isEmpty ? 0 : Double(results.filter(\.passed).count) / Double(results.count),
            averageLatency: results.isEmpty ? 0 : results.map(\.latencySeconds).reduce(0, +) / Double(results.count),
            totalDuration: Date().timeIntervalSince(suiteStart),
            timestamp: Date()
        )

        evaluationHistory.append(suiteResult)

        Log.info("[PromptEval] Suite '\(suiteName)': score=\(String(format: "%.1f%%", suiteResult.overallScore * 100)), pass=\(String(format: "%.1f%%", suiteResult.passRate * 100)), latency=\(String(format: "%.2fs", suiteResult.averageLatency))", category: .llm)

        return suiteResult
    }

    /// Evaluate a single test case
    private func evaluateTestCase(
        _ testCase: PromptTestCase,
        promptTemplate: String,
        contextProvider: @Sendable (String) async throws -> String
    ) async throws -> PromptEvalResult {
        let start = Date()

        // Get context for the query
        let context = try await contextProvider(testCase.query)

        // Build prompt from template
        let prompt = promptTemplate
            .replacingOccurrences(of: "{query}", with: testCase.query)
            .replacingOccurrences(of: "{context}", with: context)

        // Run through LLM
        // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
        // Every service that used the bare initialiser failed deterministically with
        // ParsingError / "Session ended without producing a response", while every path built
        // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
        // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
        // retrieved chunks, which rules out content, guardrails, context size and token caps.
        // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
        // these responses, consistent with a session that never received its model assets.
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Instructions("You evaluate prompt quality. Be concise and precise.")
        )
        HardwareTelemetryReporter.pulse(.llmInference, intensity: 0.9, duration: 0.3)

        let response = try await session.respond(to: prompt)
        let responseText = response.content
        let latency = Date().timeIntervalSince(start)
        HardwareTelemetryReporter.reportCPUOperation()

        // Score the response
        let keywordHitRate = scoreKeywordHits(
            response: responseText,
            expectedKeywords: testCase.expectedKeywords
        )

        let violations = findForbiddenKeywords(
            response: responseText,
            forbidden: testCase.forbiddenKeywords
        )

        let tokenCount = responseText.split(whereSeparator: { $0.isWhitespace }).count

        // Calculate confidence score
        let confidenceScore = calculateConfidence(
            keywordHitRate: keywordHitRate,
            violations: violations,
            referenceAnswer: testCase.referenceAnswer,
            response: responseText
        )

        let passed = confidenceScore >= 0.6 && violations.isEmpty

        return PromptEvalResult(
            testCase: testCase,
            response: responseText,
            keywordHitRate: keywordHitRate,
            forbiddenKeywordViolations: violations,
            responseLengthTokens: tokenCount,
            latencySeconds: latency,
            confidenceScore: confidenceScore,
            passed: passed
        )
    }

    // MARK: - Scoring Helpers

    private func scoreKeywordHits(response: String, expectedKeywords: [String]) -> Double {
        guard !expectedKeywords.isEmpty else { return 1.0 }
        let lower = response.lowercased()
        let hits = expectedKeywords.filter { lower.contains($0.lowercased()) }
        return Double(hits.count) / Double(expectedKeywords.count)
    }

    private func findForbiddenKeywords(response: String, forbidden: [String]) -> [String] {
        let lower = response.lowercased()
        return forbidden.filter { lower.contains($0.lowercased()) }
    }

    private func calculateConfidence(
        keywordHitRate: Double,
        violations: [String],
        referenceAnswer: String?,
        response: String
    ) -> Double {
        var score = keywordHitRate * 0.6  // 60% weight on keyword hits

        // Penalize forbidden keyword violations
        if !violations.isEmpty {
            score -= Double(violations.count) * 0.15
        }

        // Bonus for reasonable length (not too short, not too long)
        let wordCount = response.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount >= 20, wordCount <= 500 {
            score += 0.2
        } else if wordCount >= 10 {
            score += 0.1
        }

        // Bonus for matching reference answer overlap
        if let reference = referenceAnswer {
            let refWords = Set(reference.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
            let respWords = Set(response.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
            let overlap = Double(refWords.intersection(respWords).count) / Double(max(refWords.count, 1))
            score += overlap * 0.2  // 20% weight on reference overlap
        } else {
            score += 0.1  // Small bonus when no reference exists
        }

        return max(0, min(1, score))
    }

    // MARK: - Query Classification

    private func classifyQuery(_ query: String) -> String {
        let lower = query.lowercased()
        if lower.hasPrefix("how") || lower.contains("steps") || lower.contains("procedure") {
            return "procedural"
        } else if lower.contains("compare") || lower.contains("difference") || lower.contains("vs") {
            return "comparison"
        } else if lower.contains("summarize") || lower.contains("overview") {
            return "summary"
        } else if lower.contains("what") || lower.contains("which") || lower.contains("where") {
            return "factual"
        }
        return "general"
    }

    /// Extract significant words from text for keyword generation
    private func extractSignificantWords(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been",
                                       "being", "have", "has", "had", "do", "does", "did", "will",
                                       "would", "could", "should", "may", "might", "can", "shall",
                                       "of", "in", "to", "for", "with", "on", "at", "by", "from",
                                       "as", "into", "through", "during", "before", "after", "and",
                                       "but", "or", "nor", "not", "no", "so", "if", "then", "than",
                                       "that", "this", "these", "those", "it", "its", "they", "them"]

        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 3 && !stopWords.contains($0) }

        // Count frequency and return top words
        var freq: [String: Int] = [:]
        for word in words { freq[word, default: 0] += 1 }

        return freq.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: - History

    func getHistory() -> [PromptEvalSuiteResult] {
        evaluationHistory
    }

    /// Compare two evaluation runs to detect regressions
    func compareRuns(_ run1: PromptEvalSuiteResult, _ run2: PromptEvalSuiteResult) -> (scoreDelta: Double, passRateDelta: Double, latencyDelta: TimeInterval) {
        (
            scoreDelta: run2.overallScore - run1.overallScore,
            passRateDelta: run2.passRate - run1.passRate,
            latencyDelta: run2.averageLatency - run1.averageLatency
        )
    }

    // MARK: - Persistence

    private func saveTestSuites() {
        do {
            let data = try JSONEncoder().encode(testSuites)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            Log.error("[PromptEval] Failed to save test suites: \(error.localizedDescription)", category: .llm)
        }
    }

    private func loadTestSuites() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            testSuites = try JSONDecoder().decode([String: [PromptTestCase]].self, from: data)
            Log.info("[PromptEval] Loaded \(testSuites.count) test suites", category: .llm)
        } catch {
            Log.error("[PromptEval] Failed to load test suites: \(error.localizedDescription)", category: .llm)
        }
    }
}

// MARK: - Errors

enum PromptEvalError: Error, LocalizedError {
    case suiteNotFound(String)
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .suiteNotFound(let name): return "Test suite '\(name)' not found"
        case .evaluationFailed(let reason): return "Evaluation failed: \(reason)"
        }
    }
}
