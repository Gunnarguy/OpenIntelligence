//
//  ResponseTransformService.swift
//  OpenIntelligence
//
//  RAG-grounded response transforms powered by Apple Foundation Models.
//  Unlike generic text transforms, every action here receives the retrieved
//  source chunks and uses them to produce document-backed output.
//
//  Example: "Step-by-Step" on a car manual answer pulls actual part numbers
//  and torque specs from the source chunks — not LLM hallucinations.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// RAG-context-aware response transforms using Apple Foundation Models.
/// Each transform receives both the AI response AND the source chunks that backed it.
///
/// Design principles (10x Apple engineer):
/// 1. Every transform is grounded in retrieved source documents — no hallucination.
/// 2. Token budgets are enforced (4096 context window, ~1.4 chars/token).
/// 3. Generation has timeout + cancellation for responsiveness.
/// 4. System instructions prime the model for document-grounded extraction.
/// 5. Prompts explicitly instruct on what to OMIT, not just what to include.
@available(iOS 26.0, *)
final class ResponseTransformService: Sendable {

    // MARK: - Token Budget Constants
    // Apple FM context window = 4096 tokens. At ~1.4 chars/token:
    // - System instructions: ~150 tokens
    // - Output reservation: ~800 tokens (transforms produce structured output)
    // - Available for prompt + context: ~3146 tokens ≈ 4400 chars
    // Split: response ≤ 1800 chars (~1286 tokens), sources ≤ 2400 chars (~1714 tokens)

    private static let maxResponseChars = 1800
    private static let maxSourceChars = 2400
    private static let generationTimeoutSeconds: UInt64 = 30

    /// System instructions that prime the model for document-grounded transforms.
    /// Set once per session — saves ~100 tokens vs repeating in every prompt.
    private static let systemInstructions = """
    You are a document analysis assistant. You ONLY work with source documents provided by the user. \
    Rules: (1) Never fabricate information not in the sources. (2) If a fact cannot be traced to a \
    specific source document, omit it entirely. (3) Cite source names and page numbers when available. \
    (4) Be concise — every word must earn its place.
    """

    /// Check if Apple Foundation Models are available on this device
    nonisolated var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    // MARK: - RAG-Grounded Transforms

    /// Extract only facts directly supported by source chunks — no LLM embellishment.
    /// Each fact is traceable to a source document.
    func keyFacts(response: String, chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else { throw ResponseTransformError.notAvailable }

        let sourceContext = formatChunksForPrompt(chunks)

        let prompt = """
        AI RESPONSE:
        \(String(response.prefix(Self.maxResponseChars)))

        SOURCE DOCUMENTS:
        \(sourceContext)

        Extract ONLY factual claims that have a verbatim match or close paraphrase in a SOURCE DOCUMENT above. \
        Format as bullet points. After each fact, cite the source in parentheses (e.g., "[Owner's Manual, p.52]"). \
        If a claim in the AI response does NOT appear in any source document, omit it entirely — do not guess. \
        Return ONLY the bullet-point facts.
        """

        return try await generate(prompt: prompt)
    }

    /// Convert response into numbered action steps, grounded in source document details.
    /// Pulls actual specs, part numbers, measurements from the chunks.
    func stepByStep(response: String, chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else { throw ResponseTransformError.notAvailable }

        let sourceContext = formatChunksForPrompt(chunks)

        let prompt = """
        AI RESPONSE:
        \(String(response.prefix(Self.maxResponseChars)))

        SOURCE DOCUMENTS:
        \(sourceContext)

        Convert into clear numbered steps someone can follow immediately. \
        Each step MUST start with an action verb (Check, Open, Remove, Apply, Tighten, etc.). \
        Pull specific details from the source documents: part numbers, measurements, torque specs, page references. \
        Include ⚠️ warnings or cautions from the sources as separate ⚠️ items after the relevant step. \
        If a step cannot be verified against the sources, mark it with [unverified]. \
        Return ONLY the numbered steps.
        """

        return try await generate(prompt: prompt)
    }

    /// Show what other parts of the library mention the same topics.
    /// Highlights agreements, contradictions, and additional details across sources.
    func crossReference(response: String, chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else { throw ResponseTransformError.notAvailable }

        let sourceContext = formatChunksForPrompt(chunks)

        // Group sources by document name for the prompt header
        let docNames = Set(chunks.map { $0.sourceDocument }).filter { !$0.isEmpty }
        let sourceCount = docNames.count

        let prompt: String
        if sourceCount <= 1 {
            // Single-document mode: compare sections within the same document
            let docName = docNames.first ?? "the document"
            prompt = """
            SOURCE DOCUMENTS (all from \(docName)):
            \(sourceContext)

            These excerpts are all from the same document. Analyze what different SECTIONS say about the same topics:
            1. **Consistent**: Facts repeated across multiple sections (stronger evidence)
            2. **Contradicts**: Any section that says something different from another
            3. **Unique detail**: Important information that appears in only one section

            Quote key phrases and cite page numbers. Return ONLY the analysis.
            """
        } else {
            prompt = """
            SOURCE DOCUMENTS (from \(sourceCount) documents: \(docNames.joined(separator: ", "))):
            \(sourceContext)

            Analyze these sources across documents and report:
            1. **Agrees**: Facts that appear in multiple documents (cite both)
            2. **Differs**: Contradictions or differing details between documents (cite both, note which is newer if possible)
            3. **Unique**: Important details that only appear in one document

            Quote key phrases and cite document name + page. Return ONLY the analysis.
            """
        }

        return try await generate(prompt: prompt)
    }

    /// Generate follow-up questions that the user's document library can actually answer.
    /// Uses the retrieved chunks to identify adjacent topics worth exploring.
    func deepDive(response: String, chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else { throw ResponseTransformError.notAvailable }

        let sourceContext = formatChunksForPrompt(chunks)

        let prompt = """
        AI RESPONSE:
        \(String(response.prefix(Self.maxResponseChars)))

        SOURCE DOCUMENTS:
        \(sourceContext)

        Generate 5 follow-up questions that:
        1. Are answerable by these same source documents (reference specific topics you see in them)
        2. Explore related details mentioned in the sources but NOT covered in the AI response
        3. Would deepen the user's practical understanding

        Each question must reference a specific detail from the sources. \
        Do NOT ask generic questions like "What else is there?" — ask things the documents CAN answer. \
        Format as a numbered list. Return ONLY the questions.
        """

        return try await generate(prompt: prompt)
    }

    /// Generate Q&A flash cards from the retrieved content for study/review.
    func flashCards(response: String, chunks: [RetrievedChunk]) async throws -> String {
        guard isAvailable else { throw ResponseTransformError.notAvailable }

        let sourceContext = formatChunksForPrompt(chunks)

        let prompt = """
        SOURCE DOCUMENTS:
        \(sourceContext)

        Create 5 flash cards from this content for study and review.
        Each card must have:
        - A specific, testable question (not yes/no)
        - A concise answer sourced DIRECTLY from the documents (with page citation)
        - Cards should cover DIFFERENT topics from the material

        Format exactly:
        **Q1:** [question]
        **A1:** [answer] — [Source, p.X]

        (repeat for Q2–Q5)

        Return ONLY the flash cards.
        """

        return try await generate(prompt: prompt)
    }

    // MARK: - Private Helpers

    /// Format retrieved chunks into a prompt-friendly string with source attribution.
    /// Token-budget aware: caps total chars to stay within Apple FM's 4096 token window.
    private func formatChunksForPrompt(_ chunks: [RetrievedChunk]) -> String {
        var result = ""
        var charCount = 0
        let maxChars = Self.maxSourceChars

        for (idx, chunk) in chunks.enumerated() {
            let source = chunk.sourceDocument.isEmpty ? "Source \(idx + 1)" : chunk.sourceDocument
            let page = chunk.pageNumber.map { ", p.\($0)" } ?? ""
            let relevance = String(format: "%.0f", chunk.similarityScore * 100)
            let header = "[\(source)\(page)] (\(relevance)% match)"
            let content = chunk.chunk.content

            let entry = "\(header)\n\(content)\n\n"

            if charCount + entry.count > maxChars {
                // Try to fit a truncated version of this chunk
                let remaining = maxChars - charCount
                if remaining > 200 { // Only include if we can fit meaningful content
                    let truncatedContent = String(content.prefix(remaining - header.count - 20))
                    result += "\(header)\n\(truncatedContent)…\n\n"
                }
                break
            }
            result += entry
            charCount += entry.count
        }

        if result.isEmpty {
            return "(No source documents available)"
        }

        return result
    }

    /// Single-shot LLM generation with system instructions, timeout, and cancellation support.
    private func generate(prompt: String) async throws -> String {
        // Check for task cancellation before starting expensive LLM work
        try Task.checkCancellation()

        // Create session OUTSIDE the task group so its lifetime is bound to this
        // function scope, not the child task. Prevents a FoundationModels dealloc
        // race when group.cancelAll() fires on the cooperative queue while the
        // session's internal response streaming is still unwinding (crash: objc_release_x8
        // → _swift_release_dealloc chain on com.apple.root.user-initiated-qos.cooperative).
        let session = LanguageModelSession(instructions: Instructions(Self.systemInstructions))

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: Self.generationTimeoutSeconds * 1_000_000_000)
                throw ResponseTransformError.generationFailed("Generation timed out after \(Self.generationTimeoutSeconds)s")
            }

            // Take whichever finishes first
            guard let result = try await group.next() else {
                throw ResponseTransformError.emptyResponse
            }
            group.cancelAll()

            guard !result.isEmpty else {
                throw ResponseTransformError.emptyResponse
            }
            return result
        }
    }
}

#else

// MARK: - Stub for platforms without FoundationModels

final class ResponseTransformService: Sendable {
    nonisolated var isAvailable: Bool { false }

    func keyFacts(response: String, chunks: [RetrievedChunk]) async throws -> String {
        throw ResponseTransformError.notAvailable
    }

    func stepByStep(response: String, chunks: [RetrievedChunk]) async throws -> String {
        throw ResponseTransformError.notAvailable
    }

    func crossReference(response: String, chunks: [RetrievedChunk]) async throws -> String {
        throw ResponseTransformError.notAvailable
    }

    func deepDive(response: String, chunks: [RetrievedChunk]) async throws -> String {
        throw ResponseTransformError.notAvailable
    }

    func flashCards(response: String, chunks: [RetrievedChunk]) async throws -> String {
        throw ResponseTransformError.notAvailable
    }
}

#endif

// MARK: - Error Types

enum ResponseTransformError: LocalizedError, Sendable {
    case notAvailable
    case emptyResponse
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device"
        case .emptyResponse:
            return "Transform produced no output — try a different action"
        case .generationFailed(let detail):
            return "Transform failed: \(detail)"
        }
    }
}
