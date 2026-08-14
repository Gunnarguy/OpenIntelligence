//
//  FoundationModelStructuredGenerator.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelStructuredGenerator {
    
    private static let structuredCitationRegex = try? NSRegularExpression(
        pattern: #"S(\d+)"#,
        options: [.caseInsensitive]
    )
    
    @MainActor
    static func generateStructuredRAGAnswer(
        session: LanguageModelSession,
        modelName: String,
        prompt: String,
        context: String,
        config: InferenceConfig,
        sourceCount: Int,
        mode: StructuredRAGMode = .direct
    ) async throws -> LLMResponse {
        guard sourceCount > 0 else {
            throw LLMError.generationFailed("Structured generation requires source excerpts")
        }

        let startTime = Date()
        let sanitizedPrompt = FoundationModelPromptCompiler.sanitizeForLanguageDetection(prompt)
        let sanitizedContext = FoundationModelPromptCompiler.sanitizeForLanguageDetection(context)
        let fullPrompt: String = {
            switch mode {
            case .reasoned:
                return """
                CONTEXT:
                \(sanitizedContext)

                QUESTION: \(sanitizedPrompt)

                Return grounded fields only.
                - `reasoning`: concise grounded reasoning based only on the excerpts
                - `answer`: direct answer from the excerpts
                - `confidence`: 0-100 based only on excerpt support
                - `citations`: source ids like [S1], [S2]
                - `claims`: atomic answer claims with supporting source ids per claim
                - `matchedTerms`: exact query terms supported by the excerpts
                """
            case .direct:
                return """
                CONTEXT:
                \(sanitizedContext)

                QUESTION: \(sanitizedPrompt)

                Return grounded fields only.
                - `answer`: direct answer from the excerpts with no extra reasoning text
                - `confidence`: 0-100 based only on excerpt support
                - `citations`: source ids like [S1], [S2]
                - `claims`: atomic answer claims with supporting source ids per claim
                - `matchedTerms`: exact query terms supported by the excerpts
                """
            }
        }()

        func respondStructured<GeneratedType: Generable>(
            to prompt: String,
            generating type: GeneratedType.Type
        ) async throws -> LanguageModelSession.Response<GeneratedType> {
            do {
                return try await session.respond(to: prompt, generating: type)
            } catch let error as LanguageModelSession.GenerationError {
                if case let .throwError(mappedError) = FoundationModelErrorMapper.mapError(error, isStructured: true) {
                    throw mappedError
                }
                throw error
            }
        }

        let normalizedCitations: [String]
        let reasoningText: String
        let answerText: String
        let matchedTerms: [String]
        let structuredClaims: [StructuredRAGClaim]
        let confidence: Int

        // Guided generation can fail in a way that is not transient, and the pipeline had no way to
        // express that. Device evidence 2026-08-14: in one run fifteen reasoning sessions generated
        // successfully in prose and all six final syntheses failed with "Failed to parse generated
        // content", which is what `session.respond(to:generating:)` throws when the model cannot
        // produce output conforming to the @Generable schema. Before failing, the pipeline had
        // already reduced the prompt twice (2927, then 2491, then 1565 estimated tokens) and an
        // escalating 19 second backoff retried the same constrained call three more times. Every one
        // of those remedies assumes the failure is transient or a size problem. It was neither: it
        // was deterministic, and the user lost a query whose evidence had been fully gathered.
        //
        // So a schema failure now degrades instead of terminating. Prose is a genuine loss: no
        // per-claim citations, no model confidence, no matched terms, and `structuredRAGGeneration`
        // is nil so downstream treats it as unstructured. It is still strictly better than nothing,
        // and inline [Sn] markers are recovered from the text so the citations the model did write
        // still resolve.
        do {
        switch mode {
        case .reasoned:
            let response = try await respondStructured(to: fullPrompt, generating: RAGAnswer.self)
            normalizedCitations = normalizeStructuredCitations(response.content.citations, maxSourceCount: sourceCount)
            reasoningText = response.content.reasoning.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            answerText = response.content.answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            matchedTerms = response.content.matchedTerms
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            structuredClaims = response.content.claims.compactMap { claim -> StructuredRAGClaim? in
                let claimText = claim.claim.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !claimText.isEmpty else { return nil }
                return StructuredRAGClaim(
                    claim: claimText,
                    citations: normalizeStructuredCitations(claim.citations, maxSourceCount: sourceCount),
                    isExtracted: claim.isExtracted
                )
            }
            confidence = response.content.confidence
        case .direct:
            let response = try await respondStructured(to: fullPrompt, generating: DirectRAGAnswer.self)
            normalizedCitations = normalizeStructuredCitations(response.content.citations, maxSourceCount: sourceCount)
            reasoningText = ""
            answerText = response.content.answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            matchedTerms = response.content.matchedTerms
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            structuredClaims = response.content.claims.compactMap { claim -> StructuredRAGClaim? in
                let claimText = claim.claim.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !claimText.isEmpty else { return nil }
                return StructuredRAGClaim(
                    claim: claimText,
                    citations: normalizeStructuredCitations(claim.citations, maxSourceCount: sourceCount),
                    isExtracted: claim.isExtracted
                )
            }
            confidence = response.content.confidence
        }
        } catch {
            Log.warning(
                "[FM] Structured generation failed (\(type(of: error))): \(error.localizedDescription). "
                    + "Falling back to prose rather than losing the query.",
                category: .llm
            )
            let prose = try await session.respond(to: fullPrompt)
            let text = prose.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // If prose fails too, the original schema error is the more informative one to surface.
            guard !text.isEmpty else { throw error }

            let recovered = normalizeStructuredCitations([text], maxSourceCount: sourceCount)
            let totalTime = Date().timeIntervalSince(startTime)
            LLMStreamingContext.emit(text: text, isFinal: false)
            LLMStreamingContext.emit(text: "", isFinal: true)
            Log.info(
                "[FM] Prose fallback produced \(text.count) chars, \(recovered.count) citation(s) recovered",
                category: .llm
            )
            return LLMResponse(
                text: text,
                tokensGenerated: max(1, Int(ceil(Double(text.count) / 1.4))),
                timeToFirstToken: nil,
                totalTime: totalTime,
                modelName: "\(modelName) (Prose fallback)",
                toolCallsMade: 0,
                structuredRAGGeneration: nil
            )
        }

        guard !answerText.isEmpty else {
            throw LLMError.generationFailed("Structured answer was empty")
        }

        let effectiveClaims: [StructuredRAGClaim]
        if structuredClaims.isEmpty {
            effectiveClaims = [StructuredRAGClaim(
                claim: answerText,
                citations: normalizedCitations,
                isExtracted: false
            )]
        } else {
            effectiveClaims = Array(structuredClaims.prefix(6))
        }

        let citationFooter: String
        if normalizedCitations.isEmpty || answerText.contains("[S") {
            citationFooter = ""
        } else {
            citationFooter = "\n\nSources: " + normalizedCitations.joined(separator: " ")
        }

        let finalText = answerText + citationFooter
        if !finalText.isEmpty {
            LLMStreamingContext.emit(text: finalText, isFinal: false)
        }
        LLMStreamingContext.emit(text: "", isFinal: true)

        let totalTime = Date().timeIntervalSince(startTime)
        let estimatedTokens = max(1, Int(ceil(Double(finalText.count) / 1.4)))

        return LLMResponse(
            text: finalText,
            tokensGenerated: estimatedTokens,
            timeToFirstToken: nil,
            totalTime: totalTime,
            modelName: "\(modelName) (Structured)",
            toolCallsMade: 0,
            structuredRAGGeneration: StructuredRAGGeneration(
                reasoning: reasoningText.isEmpty ? nil : reasoningText,
                answer: answerText,
                confidence: confidence,
                citations: normalizedCitations,
                matchedTerms: matchedTerms,
                claims: effectiveClaims
            )
        )
    }

    private static func normalizeStructuredCitations(_ citations: [String], maxSourceCount: Int) -> [String] {
        guard maxSourceCount > 0 else { return [] }
        var seen: Set<Int> = []
        var normalized: [String] = []

        for citation in citations {
            guard let regex = structuredCitationRegex else { continue }
            let nsRange = NSRange(citation.startIndex..<citation.endIndex, in: citation)
            for match in regex.matches(in: citation, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: citation),
                      let index = Int(citation[range]),
                      (1...maxSourceCount).contains(index),
                      !seen.contains(index)
                else { continue }
                seen.insert(index)
                normalized.append("[S\(index)]")
            }
        }

        return normalized
    }
}
#endif
