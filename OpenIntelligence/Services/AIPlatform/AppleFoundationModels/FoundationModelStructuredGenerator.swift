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
            route: AppleFoundationModelRoute,
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
                    // `includeSchemaInPrompt: true` is the guided-generation overload's own
                    // default and has to be restated: passing any ContextOptions replaces that
                    // default wholesale, so a bare ContextOptions(reasoningLevel:) would quietly
                    // stop putting the schema in the prompt.
                    #if compiler(>=6.4)
                        if #available(iOS 27.0, macOS 27.0, *),
                            let contextOptions = route.contextOptions(includeSchemaInPrompt: true)
                        {
                            return try await session.respond(
                                to: prompt,
                                generating: type,
                                contextOptions: contextOptions
                            )
                        }
                    #endif
                    return try await session.respond(to: prompt, generating: type)
                } catch let error as LanguageModelSession.GenerationError {
                    if case .throwError(let mappedError) = FoundationModelErrorMapper.mapError(
                        error, isStructured: true)
                    {
                        throw mappedError
                    }
                    throw error
                } catch {
                    // Guided generation is where `GeneratedContent.ParsingError` actually lands, because
                    // it is thrown when the model's output does not conform to the @Generable schema.
                    // On iOS 27 that no longer matches the typed catch above, so these failures reached
                    // callers as a bare "Failed to parse generated content" with the raw output, which
                    // the error carries, never read.
                    if let mapped = FoundationModelErrorMapper.mapModernError(error, isStructured: true),
                        case .throwError(let mappedError) = mapped
                    {
                        throw mappedError
                    }
                    throw error
                }
            }

            /// Characters of the `answer` field already sent to the chat as it was generated.
            var streamedAnswerCount = 0

            /// Streams `DirectRAGAnswer`, sending its `answer` field to the chat as it grows.
            ///
            /// `answer` is the schema's first property, so it is generated first. Until 5.5 this
            /// call used `respond(generating:)` and replayed the finished answer in one piece, so a
            /// Standard answer small enough for this path showed the typing indicator for the whole
            /// generation and then dripped out text that already existed. Probed 2026-09-23 on
            /// macOS: the partial `answer` grew in 14 steps across 27 snapshots, each extending the
            /// last, and the value rebuilt from the final snapshot matched what had been streamed.
            func streamDirectAnswer(to prompt: String) async throws -> DirectRAGAnswer {
                do {
                    let stream: LanguageModelSession.ResponseStream<DirectRAGAnswer>
                    #if compiler(>=6.4)
                        if #available(iOS 27.0, macOS 27.0, *),
                            let contextOptions = route.contextOptions(includeSchemaInPrompt: true)
                        {
                            stream = session.streamResponse(
                                to: prompt,
                                generating: DirectRAGAnswer.self,
                                contextOptions: contextOptions
                            )
                        } else {
                            stream = session.streamResponse(to: prompt, generating: DirectRAGAnswer.self)
                        }
                    #else
                        stream = session.streamResponse(to: prompt, generating: DirectRAGAnswer.self)
                    #endif

                    var streamed = ""
                    var finalContent: GeneratedContent?
                    for try await snapshot in stream {
                        finalContent = snapshot.rawContent
                        guard let partial = snapshot.content.answer, partial.count > streamed.count,
                            partial.hasPrefix(streamed)
                        else { continue }
                        LLMStreamingContext.emit(text: String(partial.dropFirst(streamed.count)), isFinal: false)
                        streamed = partial
                        streamedAnswerCount = streamed.count
                    }
                    guard let finalContent else {
                        throw LLMError.generationFailed("Structured answer stream ended without content")
                    }
                    return try DirectRAGAnswer(finalContent)
                } catch let error as LanguageModelSession.GenerationError {
                    if case .throwError(let mappedError) = FoundationModelErrorMapper.mapError(
                        error, isStructured: true)
                    {
                        throw mappedError
                    }
                    throw error
                } catch {
                    if let mapped = FoundationModelErrorMapper.mapModernError(error, isStructured: true),
                        case .throwError(let mappedError) = mapped
                    {
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
                    normalizedCitations = normalizeStructuredCitations(
                        response.content.citations, maxSourceCount: sourceCount)
                    reasoningText = response.content.reasoning.trimmingCharacters(
                        in: CharacterSet.whitespacesAndNewlines)
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
                    let content = try await streamDirectAnswer(to: fullPrompt)
                    normalizedCitations = normalizeStructuredCitations(
                        content.citations, maxSourceCount: sourceCount)
                    reasoningText = ""
                    answerText = content.answer.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    matchedTerms = content.matchedTerms
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    structuredClaims = content.claims.compactMap { claim -> StructuredRAGClaim? in
                        let claimText = claim.claim.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        guard !claimText.isEmpty else { return nil }
                        return StructuredRAGClaim(
                            claim: claimText,
                            citations: normalizeStructuredCitations(claim.citations, maxSourceCount: sourceCount),
                            isExtracted: claim.isExtracted
                        )
                    }
                    confidence = content.confidence
                }
            } catch {
                Log.warning(
                    "[FM] Structured generation failed (\(type(of: error))): \(error.localizedDescription). "
                        + "Falling back to prose rather than losing the query.",
                    category: .llm
                )
                // No schema on this path, so no includeSchemaInPrompt to preserve.
                let prose: LanguageModelSession.Response<String>
                #if compiler(>=6.4)
                    if #available(iOS 27.0, macOS 27.0, *),
                        let contextOptions = route.contextOptions()
                    {
                        prose = try await session.respond(to: fullPrompt, contextOptions: contextOptions)
                    } else {
                        prose = try await session.respond(to: fullPrompt)
                    }
                #else
                    prose = try await session.respond(to: fullPrompt)
                #endif
                let text = prose.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // If prose fails too, the original schema error is the more informative one to surface.
                guard !text.isEmpty else { throw error }

                let recovered = normalizeStructuredCitations([text], maxSourceCount: sourceCount)
                let totalTime = Date().timeIntervalSince(startTime)
                // A stream that failed part way has already shown its partial answer, and the chat
                // appends what it is sent, so the prose would follow it rather than replace it. The
                // finished message carries the prose either way.
                if streamedAnswerCount == 0 {
                    LLMStreamingContext.emit(text: text, isFinal: false)
                }
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
                effectiveClaims = [
                    StructuredRAGClaim(
                        claim: answerText,
                        citations: normalizedCitations,
                        isExtracted: false
                    )
                ]
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
            if streamedAnswerCount == 0 {
                if !finalText.isEmpty {
                    LLMStreamingContext.emit(text: finalText, isFinal: false)
                }
            } else if !citationFooter.isEmpty {
                // The answer itself was streamed as it was written; only the footer is new.
                LLMStreamingContext.emit(text: citationFooter, isFinal: false)
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
