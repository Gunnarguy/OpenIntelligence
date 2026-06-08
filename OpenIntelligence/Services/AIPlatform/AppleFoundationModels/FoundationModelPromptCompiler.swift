//
//  FoundationModelPromptCompiler.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelPromptCompiler: Sendable {
    
    // MARK: - Language Detection Fix

    /// Sanitize text to prevent false language detection by Apple Foundation Models.
    ///
    /// Apple's language detector can misidentify English text as Polish or other languages
    /// when certain character patterns are present (especially Polish diacritics like ł, ą, ę, ó, etc.
    /// or sequences that resemble them). This function normalizes such characters.
    static func sanitizeForLanguageDetection(_ text: String) -> String {
        // Common problematic characters that trigger false Polish detection:
        // - URLs with encoded characters
        // - Special Unicode characters
        // - Technical symbols that resemble diacritics
        var sanitized = text

        // Replace Polish-like diacritics with ASCII equivalents
        let replacements: [(String, String)] = [
            ("ł", "l"), ("Ł", "L"),
            ("ą", "a"), ("Ą", "A"),
            ("ę", "e"), ("Ę", "E"),
            ("ó", "o"), ("Ó", "O"),
            ("ś", "s"), ("Ś", "S"),
            ("ź", "z"), ("Ź", "Z"),
            ("ż", "z"), ("Ż", "Z"),
            ("ć", "c"), ("Ć", "C"),
            ("ń", "n"), ("Ń", "N"),
            // Other problematic diacritics
            ("ü", "u"), ("ö", "o"), ("ä", "a"),
            ("è", "e"), ("é", "e"), ("ê", "e"),
            ("à", "a"), ("á", "a"), ("â", "a"),
            ("ì", "i"), ("í", "i"), ("î", "i"),
            ("ù", "u"), ("ú", "u"), ("û", "u"),
            ("ñ", "n"), ("ç", "c"),
        ]

        for (original, replacement) in replacements {
            sanitized = sanitized.replacingOccurrences(of: original, with: replacement)
        }

        // Normalize certain problematic Unicode sequences
        // These can confuse language detection
        sanitized = sanitized.precomposedStringWithCanonicalMapping

        return sanitized
    }

    /// Compile system instructions for session creation.
    static func compileInstructions(systemPrompt: String?, disableTools: Bool) -> String {
        let defaultInstructions: String
        if disableTools {
            // Pure context/reasoning mode — no tool instructions needed
            defaultInstructions = """
            You are OpenIntelligence, a helpful assistant. Answer from the provided document context. Be thorough, cite sources, and copy values exactly.
            """
        } else {
            // Agentic mode — tools attached, need usage guidance
            defaultInstructions = """
            You are OpenIntelligence, a helpful assistant.
            When document context is provided, answer directly from it — do NOT call tools.
            Only use tools when NO context is provided:
            - retrieve_corpus_evidence: retrieve semantic evidence, exact matches, exact counts, or related documents
            - inspect_document: inspect one document by name
            - compare_topic_across_documents: compare evidence across documents
            - get_library_overview: inspect the library and available documents
            Cite sources and copy values exactly.
            """
        }
        return systemPrompt ?? defaultInstructions
    }

    /// Construct augmented prompt with RAG context and sanitization.
    static func compilePrompt(prompt: String, context: String?, systemPrompt: String?, disableTools: Bool) -> String {
        let sanitizedPrompt = sanitizeForLanguageDetection(prompt)
        let sanitizedContext = context.map { sanitizeForLanguageDetection($0) }

        if let context = sanitizedContext, !context.isEmpty {
            Log.debug("RAG mode: context=\(context.count) chars, prompt=\(sanitizedPrompt.prefix(50))...", category: .llm)

            // Estimate if we're approaching context window limit (4096 tokens, ~1.4 chars/token for Apple FM)
            let totalInputLength = context.count + sanitizedPrompt.count + 200 // Buffer for instructions
            let estimatedInputTokens = max(
                1,
                Int(ceil(Double(totalInputLength) / 1.4))
            )

            if estimatedInputTokens > 3500 {
                Log.warning("[FM] Input approaching context limit: ~\(estimatedInputTokens) tokens", category: .llm)
            }

            if systemPrompt != nil {
                // System instructions already set — formatting is handled by systemPrompt.
                // BUDGET-CONSCIOUS: No duplicate formatting instructions. Save ~80 tokens.
                return """
                CONTEXT:
                \(context)

                QUESTION: \(sanitizedPrompt)

                Answer using EXACT values from the context. Merge overlapping excerpts — NEVER repeat the same sentence frame.
                """
            } else {
                // No system prompt — embed minimal instructions in prompt.
                return """
                Answer from the excerpts below. Be thorough. Copy values VERBATIM.
                Cite sources [Document Name, p.X].
                Merge overlapping excerpts — NEVER repeat the same sentence frame.

                EXCERPTS:
                \(context)

                QUESTION: \(sanitizedPrompt)
                """
            }
        } else {
            Log.debug("General chat mode: prompt=\(sanitizedPrompt.prefix(50))...", category: .llm)

            // Handle short queries that may confuse language detection
            // Per Apple's documentation, the language detector needs sufficient text
            let wordCount = sanitizedPrompt.split(separator: " ").count

            if wordCount <= 2 {
                // Very short queries (1-2 words) - add explicit English context
                return "Please explain the following topic clearly and concisely: \(sanitizedPrompt)"
            } else if wordCount <= 5, !sanitizedPrompt.contains(" the "), !sanitizedPrompt.contains(" is ") {
                // Short queries without clear English markers
                return "Answer the following clearly and concisely: \(sanitizedPrompt)"
            } else {
                return sanitizedPrompt
            }
        }
    }
}
