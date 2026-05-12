//
//  WritingToolsService.swift
//  OpenIntelligence
//
//  Writing Tools powered by Apple Foundation Models (FoundationModels framework).
//  Provides proofread, rewrite, and summarize via on-device LLM (iOS 26+).
//
//  NOTE: Apple's system Writing Tools are a UI-level feature on UITextView
//  (writingToolsBehavior), NOT a programmatic API. There is no "WritingTools"
//  framework to import. This service uses FoundationModels directly to
//  replicate the same capabilities programmatically.
//

import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels

/// Programmatic writing tools powered by Apple Foundation Models.
/// Replicates proofread / rewrite / summarize using the on-device LLM.
///
/// Design notes:
/// 1. Apple's system Writing Tools are a UI-level UITextView feature, NOT a framework.
///    This service uses FoundationModels directly for programmatic equivalents.
/// 2. `generate()` has a 30-second timeout matching ResponseTransformService.
/// 3. System instructions prime the model for text-refinement tasks.
/// 4. All methods check for task cancellation before starting LLM work.
@available(iOS 26.0, *)
final class WritingToolsService: Sendable {

    /// Timeout matches ResponseTransformService for consistency
    nonisolated private static let generationTimeoutSeconds: UInt64 = 30

    /// System instructions for text-refinement tasks
    nonisolated private static let systemInstructions = """
    You are a precise text editor. Rules: (1) Return ONLY the edited text — no preamble, \
    no explanations, no commentary. (2) Preserve all factual content. (3) Do not add \
    information that was not in the original text.
    """

    /// Check if Apple Foundation Models are available on this device
    nonisolated var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - Text Enhancement

    /// Proofread text — fix grammar, spelling, and punctuation while preserving meaning
    func proofread(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Proofreading text (chars=\(text.count))", category: .pipeline)

        let prompt = """
        Proofread the following text. Fix grammar, spelling, and punctuation errors. \
        Preserve the original meaning and tone. Return ONLY the corrected text.

        Text:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        Log.debug("[WritingTools] Proofreading complete (chars=\(result.count))", category: .pipeline)
        return result
    }

    /// Rewrite text in a given tone
    func rewrite(_ text: String, tone: RewriteTone) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Rewriting text (chars=\(text.count), tone=\(tone.rawValue))", category: .pipeline)

        let prompt = """
        Rewrite the following text in a \(tone.rawValue.lowercased()) tone. \
        Preserve all factual content. Return ONLY the rewritten text.

        Text:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        Log.debug("[WritingTools] Rewrite complete (chars=\(result.count))", category: .pipeline)
        return result
    }

    /// Summarize text into key points
    func summarize(_ text: String, style: SummaryStyle) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Summarizing text (chars=\(text.count), style=\(style.rawValue))", category: .pipeline)

        let styleInstruction: String
        switch style {
        case .keyPoints:
            styleInstruction = "Summarize as concise bullet-point key takeaways."
        case .paragraph:
            styleInstruction = "Summarize in a single concise paragraph."
        case .list:
            styleInstruction = "Summarize as a numbered list of main points."
        }

        let prompt = """
        \(styleInstruction) \
        Preserve all important facts. Return ONLY the summary.

        Text:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        let compression = text.isEmpty ? 0.0 : (Double(result.count) / Double(text.count) * 100)
        Log.debug("[WritingTools] Summary complete (originalChars=\(text.count), summaryChars=\(result.count), compression=\(String(format: "%.1f", compression))%)", category: .pipeline)
        return result
    }

    /// Make text more concise
    func makeConcise(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Making text concise (chars=\(text.count))", category: .pipeline)

        let prompt = """
        Make the following text more concise. Remove redundancy and filler words while \
        preserving all essential meaning. Return ONLY the concise version.

        Text:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        Log.debug("[WritingTools] Concise version ready (originalChars=\(text.count), conciseChars=\(result.count))", category: .pipeline)
        return result
    }

    // MARK: - RAG Response Transforms

    /// Simplify — rewrite an AI response in plain, everyday language (ELI5)
    func simplify(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Simplifying text (chars=\(text.count))", category: .pipeline)

        let prompt = """
        Rewrite the following text in simple, everyday language that anyone can understand. \
        Use short sentences. Avoid jargon and technical terms — if you must use one, explain it \
        in parentheses. Keep ALL the facts but make it easy to read. \
        Return ONLY the simplified text.

        Text:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        Log.debug("[WritingTools] Simplify complete (chars=\(result.count))", category: .pipeline)
        return result
    }

    /// Make Actionable — convert an informational AI response into numbered steps / checklist
    func makeActionable(_ text: String) async throws -> String {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }
        try Task.checkCancellation()

        Log.debug("[WritingTools] Making actionable (chars=\(text.count))", category: .pipeline)

        let prompt = """
        Convert the following information into a clear, numbered action plan. \
        Each step should start with a verb (Check, Open, Remove, Apply, etc.). \
        If there are warnings or important notes, put them as ⚠️ items. \
        Keep it practical — someone should be able to follow these steps immediately. \
        Return ONLY the action steps.

        Information:
        \(text)
        """

        let result = try await generate(prompt: prompt)
        Log.debug("[WritingTools] Actionable complete (chars=\(result.count))", category: .pipeline)
        return result
    }

    // MARK: - RAG-Specific Enhancements

    /// Summarize retrieved chunks before passing to LLM (reduces token usage)
    func summarizeContext(_ chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else {
            return chunks.map { $0.chunk.content }.joined(separator: "\n\n")
        }

        Log.debug("[WritingTools] Summarizing context (chunks=\(chunks.count))", category: .pipeline)

        let rawContext = chunks.map { chunk in
            """
            [Relevance: \(String(format: "%.2f", chunk.similarityScore))]
            \(chunk.chunk.content)
            """
        }.joined(separator: "\n\n---\n\n")

        let summary = try await summarize(rawContext, style: .keyPoints)

        let savings = rawContext.count - summary.count
        let pct = rawContext.isEmpty ? 0.0 : ((1.0 - Double(summary.count) / Double(rawContext.count)) * 100)
        Log.debug("[WritingTools] Context summarized (originalChars=\(rawContext.count), summaryChars=\(summary.count), savingsChars=\(savings), savingsPct=\(String(format: "%.1f", pct))%)", category: .pipeline)

        return summary
    }

    /// Improve user query clarity before RAG processing
    func clarifyQuery(_ query: String) async throws -> String {
        guard isAvailable else {
            return query
        }

        Log.debug("[WritingTools] Clarifying user query (chars=\(query.count))", category: .pipeline)
        let clarified = try await proofread(query)

        if clarified != query {
            Log.debug("[WritingTools] Query clarified (charsBefore=\(query.count), charsAfter=\(clarified.count))", category: .pipeline)
        } else {
            Log.verbose("[WritingTools] Query already clear", category: .pipeline)
        }

        return clarified
    }

    // MARK: - Private LLM Helper

    /// Single-shot LLM generation with system instructions, timeout, and cancellation support.
    /// Matches ResponseTransformService pattern for consistency.
    private func generate(prompt: String) async throws -> String {
        try Task.checkCancellation()

        // Create session OUTSIDE the task group to prevent FoundationModels dealloc race
        // (same pattern as ResponseTransformService — see crash: objc_release_x8)
        let session = LanguageModelSession(instructions: Instructions(Self.systemInstructions))

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw WritingToolsError.processingFailed("Model returned empty response")
                }
                return text
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: Self.generationTimeoutSeconds * 1_000_000_000)
                throw WritingToolsError.processingFailed("Generation timed out after \(Self.generationTimeoutSeconds)s")
            }

            // Take whichever finishes first
            guard let result = try await group.next() else {
                throw WritingToolsError.processingFailed("No generation result")
            }
            group.cancelAll()
            return result
        }
    }
}

#else

// MARK: - Stub for platforms without FoundationModels (macOS, older iOS)

final class WritingToolsService: Sendable {
    nonisolated var isAvailable: Bool { false }

    func proofread(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func rewrite(_ text: String, tone: RewriteTone) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func summarize(_ text: String, style: SummaryStyle) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func makeConcise(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func simplify(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func makeActionable(_ text: String) async throws -> String {
        throw WritingToolsError.notAvailable
    }

    func summarizeContext(_ chunks: [RetrievedChunk]) async throws -> String {
        return chunks.map { $0.chunk.content }.joined(separator: "\n\n")
    }

    func clarifyQuery(_ query: String) async throws -> String {
        return query
    }
}

#endif

// MARK: - Supporting Types (always available)

enum RewriteTone: String, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case casual = "Casual"
}

enum SummaryStyle: String, CaseIterable {
    case keyPoints = "Key Points"
    case paragraph = "Paragraph"
    case list = "List"
}

enum WritingToolsError: LocalizedError {
    case notAvailable
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence not available on this device (requires iOS 26+, A17 Pro or M1+)"
        case .processingFailed(let message):
            return "Writing Tools processing failed: \(message)"
        }
    }
}
