//
//  SuggestedQuestionsService+LLMGeneration.swift
//  OpenIntelligence
//
//  Part of SuggestedQuestionsService, moved from SuggestedQuestionsService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

extension SuggestedQuestionsService {
    // MARK: - Step 2: LLM Generation (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func generateWithLLM(
        baseQuestions: [SuggestedQuestion],
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = [],
        interrupted: inout Bool
    ) async -> [SuggestedQuestion] {

        guard await isSystemLLMAvailable else {
            Log.debug("[SuggestedQuestions] Apple FM not available, falling back to content extraction")
            return []
        }
        guard !baseQuestions.isEmpty else { return [] }

        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 8)
        guard !passages.isEmpty else { return [] }

        let rewriteTargets = baseQuestions.enumerated().compactMap { index, question -> (Int, SuggestedQuestion, GroundedPassage)? in
            guard let groundedPassage = bestGroundingPassage(for: question.text, passages: passages),
                  shouldAllowLLMRewrite(for: question.text, passage: groundedPassage) else {
                return nil
            }
            return (index, question, groundedPassage)
        }
        let limitedTargets = Array(rewriteTargets.prefix(8))
        guard limitedTargets.count >= 2 else { return [] }

        let candidateText = limitedTargets.enumerated().map { index, target in
            let question = target.1
            let passage = target.2
            var headerParts = ["Document: \(passage.documentName)"]
            if let section = passage.sectionName, !section.isEmpty {
                headerParts.append("Section: \(section)")
            }
            return """
            [\(index + 1)] \(headerParts.joined(separator: " | "))
            Candidate question: \(question.text)
            Passage:
            \(passage.content)
            """
        }.joined(separator: "\n\n")

        // If refreshing, tell the LLM to avoid previously-shown questions
        let avoidClause: String
        if !avoidTexts.isEmpty {
            let listed = avoidTexts.prefix(6).enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            avoidClause = "\n\nIMPORTANT: Do NOT repeat these previously shown questions. Generate completely different ones:\n\(listed)\n"
        } else {
            avoidClause = ""
        }

        let prompt = """
        You are editing starter question chips for a document Q&A app.

        Rewrite each candidate question so it sounds natural, direct, and grounded in its passage.

        Rules:
        - Keep the SAME meaning, target fact, action, number, entity, and scope as the candidate
        - Do NOT invent a new topic, device, quantity, duration, condition, or capability
        - Vary the phrasing and grammatical structures across the list. Do not start all rewritten questions with the same words (e.g. mix 'What is...', 'How...', 'Why...', 'Which...', 'Does...').
        - Every rewritten question must still be answerable mostly from that one passage with little or no inference
        - Keep each question under 12 words when possible
        - Every question must be a complete, grammatically correct sentence. Never output trailing fragments or cut-off phrases (e.g., do NOT end with "that many?" or "Piaget Vygotsky?").
        - If naming multiple researchers or entities, connect them properly (e.g. "Piaget and Vygotsky" instead of "Piaget Vygotsky").
        - Prefer direct grounded forms like "What is...", "Which...", "When...", "How much...", or "What should you do if..."
        - If the passage is a warning, prohibition, or conditional instruction, keep the question concrete and safety-grounded
        - Do NOT turn a warning or restriction into a speculative capability question like "Can you..." or "How long can you..." unless the passage explicitly states that allowed capability or duration
        - Do NOT ask about the documents or passages themselves (e.g., do NOT say "according to the passage", "as mentioned in the text")
        - Do NOT generate or include any structural or meta references (e.g., referencing rows, columns, cells, tables, page numbers, or "the document/passage")
        - Do NOT include square brackets, placeholders, bullets, numbering, or quotes
        - Return the SAME NUMBER of questions in the SAME ORDER as the candidates below
        \(avoidClause)
        CANDIDATES:
        \(candidateText)

        Return ONLY plain question strings through the schema. Do not number them. Do not add bullets or quotes.
        """

        do {
            // Outside the timeout, so waiting for an answer to finish does not use it up (5.8).
            await AnswerModelPriority.waitWhileAnswering(job: "suggestedQuestions")
            let responseContent = try await withTimeout(seconds: 10.0) {
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
                    instructions: Instructions(
                        "You write complete, natural questions about the subject matter of documents. "
                            + "Follow the formatting rules in the request exactly."
                    )
                )
                // @Generable: typed [String] array — eliminates numbered-line regex parsing.
                // Constrained sampling enforces the declared schema at the token level.
                let response = try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
                return response.content
            }
            let rewrittenTexts = responseContent.questions.compactMap { sanitizeGeneratedQuestion($0) }
            guard rewrittenTexts.count == limitedTargets.count else {
                Log.warning("[SuggestedQuestions] LLM rewrite count mismatch (\(rewrittenTexts.count) vs \(limitedTargets.count))")
                return []
            }

            var mergedQuestions = baseQuestions
            for (target, rewrittenText) in zip(limitedTargets, rewrittenTexts) {
                let questionIndex = target.0
                let original = target.1
                let groundedPassage = target.2

                guard isFaithfulQuestionRewrite(original: original.text, rewritten: rewrittenText, passage: groundedPassage),
                      isUsableLLMGeneratedQuestion(rewrittenText, passage: groundedPassage),
                      !isSelfAnsweringGeneratedQuestion(rewrittenText)
                else {
                    mergedQuestions[questionIndex] = original
                    continue
                }

                mergedQuestions[questionIndex] = SuggestedQuestion(
                    id: UUID(),
                    text: rewrittenText,
                    category: original.category,
                    relevantDocuments: original.relevantDocuments,
                    sourceSections: original.sourceSections,
                    confidence: max(original.confidence, groundedConfidence(for: rewrittenText, passage: groundedPassage)),
                    isLLMGenerated: true
                )
            }

            let deduped = dedupeSuggestedQuestionsPreservingOrder(mergedQuestions)
            guard deduped.count >= 2 else {
                Log.warning("[SuggestedQuestions] LLM returned too few valid rewrites (\(deduped.count))")
                return []
            }

            Log.info("[SuggestedQuestions] LLM polished \(deduped.count) grounded questions")
            return deduped

        } catch {
            // A cancelled or timed-out call is not the model's answer (5.8): the caller saves nothing for it.
            if Self.isInterruption(error) { interrupted = true }
            Log.warning("[SuggestedQuestions] LLM rewrite failed: \(error.localizedDescription)")
            return []
        }
    }

    private func shouldAllowLLMRewrite(
        for question: String,
        passage: GroundedPassage
    ) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Treat this as the planning gate: only low-risk fact questions are eligible
        // for stylistic polish. Safety, requirements, procedures, and quantity asks
        // keep deterministic phrasing so the LLM cannot change their modality.
        if passageLooksSafetyCritical(passage.content) || passageContainsProhibition(passage.content) {
            return false
        }

        if isQuantityQuestion(question) || isCapabilityQuestionFraming(lower) {
            return false
        }

        if isProceduralQuestionFraming(lower) || isSafetyOrRequirementQuestionFraming(lower) {
            return false
        }

        return true
    }

    @available(iOS 26.0, *)
    func generateDirectlyWithLLM(
        chunks: [DocumentChunk],
        documents: [Document],
        avoidTexts: [String] = [],
        interrupted: inout Bool
    ) async -> [SuggestedQuestion] {
        guard await isSystemLLMAvailable else { return [] }

        let passages = buildGroundedPassages(from: chunks, documents: documents, limit: 12)
        guard !passages.isEmpty else { return [] }

        Log.info("[SuggestedQuestions] generateDirectlyWithLLM called with \(passages.count) passages")

        let avoidClause: String
        if !avoidTexts.isEmpty {
            let listed = avoidTexts.prefix(6).enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            avoidClause = "\n\nIMPORTANT: Do NOT repeat these previously shown questions. Generate completely different ones:\n\(listed)\n"
        } else {
            avoidClause = ""
        }

        var allGeneratedQuestions: [SuggestedQuestion] = []
        let batchSize = 4

        var index = 0
        while index < passages.count {
            // A cancelled run stops here rather than asking the model for batches nobody will see (5.8).
            if Task.isCancelled {
                interrupted = true
                break
            }
            let batch = Array(passages[index..<min(index + batchSize, passages.count)])
            let batchStartIndex = index
            index += batchSize

            let candidateText = batch.enumerated().map { subIndex, passage in
                var headerParts = ["Passage \(subIndex + 1)"]
                if let section = passage.sectionName, !section.isEmpty {
                    headerParts.append("Section: \(section)")
                }
                return """
                [\(subIndex + 1)] \(headerParts.joined(separator: " | "))
                Context:
                \(passage.content)
                """
            }.joined(separator: "\n\n")

            let prompt = """
            You are generating suggested starter question chips for a document Q&A application.
            The user has uploaded documents, and we want to show starter questions that explore whatever actually matters in the text, whatever kind of document it is.

            For each numbered passage below, generate exactly ONE short, natural, and highly insightful question that:
            - Is directly answerable by the text in that passage.
            - Focuses on what the passage is actually about: its claims, instructions, obligations, quantities, causes, or outcomes (avoid trivial details, page numbers, or formatting).
            - Matches the question to the kind of document it came from. A study invites questions about method and result, a manual about how to do something or what to do when something goes wrong, an agreement about obligations, amounts and deadlines, a recipe about quantities and steps, a report about a figure and what drove it, a letter or memo about what is being asked of whom.
            - Sounds natural, conversational, and direct, the way a person asks about the subject matter rather than about the file.
            - Varies the question words and grammatical structures across the list (mix "How", "Why", "What", "Which", "Does", etc. across the items).
            - Is highly distinct from the other questions in the list.

            Rules:
            - Do NOT mention the word "passage", "document", "text", "author", "study", or "table" in the questions (e.g., do NOT ask "According to the passage, what is..."). Keep them entirely about the subject matter.
            - Only ask "why" when the passage actually gives a reason. Most documents state rules without explaining them: if the text says rent is late after the fifth day but never says why, ask what the rule is, not why it exists.
            - Name the thing. Never write "certain parts", "a characteristic", "the nature of the damage" or any other stand-in for something the passage names outright. Ask "How does combining the camera head with a third-party control unit affect image latency?", never "How does combining certain parts affect performance?". A question the reader cannot answer without first guessing what you meant is a failed question.
            - Ask about the subject, not about the document. Never end a question with "described", "highlighted", "mentioned", "discussed" or "listed", because those ask what the text does rather than what is true.
            - Each question must be a complete, grammatically correct sentence under 15 words.
            - Do not include brackets, quotes, numbering, or bullets.
            \(avoidClause)
            PASSAGES:
            \(candidateText)

            Return exactly ONE question per passage through the schema, in the same order as the passages.
            """

            do {
                // Outside the timeout, so waiting for an answer to finish does not use it up (5.8).
                await AnswerModelPriority.waitWhileAnswering(job: "suggestedQuestions")
                let responseContent = try await withTimeout(seconds: 12.0) {
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
                        instructions: Instructions(
                        "You write complete, natural questions about the subject matter of documents. "
                            + "Follow the formatting rules in the request exactly."
                    )
                    )
                    let response = try await session.respond(to: prompt, generating: SuggestedQuestionList.self)
                    return response.content
                }

                Log.info("[SuggestedQuestions] Batch starting at \(batchStartIndex) generated \(responseContent.questions.count) raw questions: \(responseContent.questions)")

                var batchGains = 0
                for (subIndex, rawText) in responseContent.questions.enumerated() {
                    guard let questionText = sanitizeGeneratedQuestion(rawText) else { continue }
                    guard subIndex < batch.count else { break }

                    let passage = batch[subIndex]

                    guard isUsableLLMGeneratedQuestion(questionText, passage: passage),
                          !isSelfAnsweringGeneratedQuestion(questionText)
                    else { continue }

                    let category: QuestionCategory = inferCategoryDirect(for: questionText)

                    allGeneratedQuestions.append(SuggestedQuestion(
                        id: UUID(),
                        text: questionText,
                        category: category,
                        relevantDocuments: [passage.documentName],
                        sourceSections: passage.sectionName.map { [$0] } ?? [],
                        confidence: 0.90,
                        isLLMGenerated: true
                    ))
                    batchGains += 1
                }
                Log.info("[SuggestedQuestions] Batch starting at \(batchStartIndex) kept \(batchGains) questions after filtering")
            } catch {
                if Self.isInterruption(error) { interrupted = true }
                Log.warning("[SuggestedQuestions] Direct LLM generation failed for batch starting at \(batchStartIndex): \(error.localizedDescription)")
            }
        }

        return dedupeSuggestedQuestionsPreservingOrder(allGeneratedQuestions)
    }

    /// Extract concrete answer spans from a passage — the "answer-first" step.
    /// These are specific facts, numbers, named things, and key phrases that
    /// make good answers to questions a user would actually ask.
    private func extractAnswerSpans(from passage: GroundedPassage) -> [String] {
        var spans: [String] = []
        let content = passage.content

        // 1. Numbers with context (e.g., "50+ file formats", "4K tokens", "32K tokens")
        let numberPatterns = [
            #"\b\d[\d,]*\.?\d*\+?\s*(?:file formats?|formats?|documents?|libraries|tokens?|hours?|minutes?|categories|steps?|modes?|ways?|properties|features?)\b"#,
            #"\b\d+K\s*(?:tokens?|context|window)\b"#,
        ]
        for pattern in numberPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsContent = content as NSString
                let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
                for match in matches.prefix(2) {
                    let span = nsContent.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if span.count >= 3, span.count <= 40 {
                        spans.append(span)
                    }
                }
            }
        }

        // 2. Named things in bold (Markdown **bold** often marks key terms)
        let boldPattern = #"\*\*([^*]{3,50})\*\*"#
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches.prefix(3) {
                if match.numberOfRanges >= 2 {
                    let span = nsContent.substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if span.count >= 3, span.count <= 50, !spans.contains(span) {
                        spans.append(span)
                    }
                }
            }
        }

        // 3. Enumerated list items (e.g., "1. Parse  2. Chunk  3. Embed")
        let listPattern = #"(?:^|\n)\s*(?:\d+\.|\-|\*)\s+\*?\*?(.{5,60}?)(?:\*?\*?\s*(?:\n|$))"#
        if let regex = try? NSRegularExpression(pattern: listPattern, options: [.anchorsMatchLines]) {
            let nsContent = content as NSString
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            if matches.count >= 3 {
                // Multiple list items → the list itself is a good answer span
                let items = matches.prefix(6).compactMap { match -> String? in
                    guard match.numberOfRanges >= 2 else { return nil }
                    return nsContent.substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "**", with: "")
                }
                if !items.isEmpty {
                    let listSummary = items.joined(separator: ", ")
                    if listSummary.count <= 120, !spans.contains(listSummary) {
                        spans.append(listSummary)
                    }
                }
            }
        }

        // 4. Section title as a topic (if it's specific enough)
        if let section = passage.sectionName,
           section.count >= 5,
           section.count <= 50 {
            let sectionLower = section.lowercased()
            let genericTitles: Set<String> = [
                "introduction", "overview", "summary", "conclusion", "background",
                "discussion", "results", "methods", "references", "notes"
            ]
            if !genericTitles.contains(sectionLower) {
                spans.append(section)
            }
        }

        // 5. Abbreviations/acronyms with expansions from chunk metadata
        for (abbr, expansion) in passage.chunk.metadata.abbreviations.prefix(2) {
            let cleaned = "\(abbr) (\(expansion))"
            if cleaned.count <= 50, !spans.contains(cleaned) {
                spans.append(cleaned)
            }
        }

        return spans
    }

    private func inferCategoryDirect(for text: String) -> QuestionCategory {
        let lower = text.lowercased()
        if lower.contains("compare") || lower.contains("contrast") || lower.contains("versus") || lower.contains(" vs ") || lower.contains("different from") {
            return .comparison
        } else if lower.contains("summar") || lower.contains("overview") || lower.contains("outline") {
            return .summarization
        } else if lower.hasPrefix("how") || lower.contains("steps") || lower.contains("procedure") {
            return .procedural
        } else if lower.contains("why") || lower.contains("explain") || lower.contains("reason") || lower.contains("relation") || lower.contains("impact") || lower.contains("affect") {
            return .analytical
        } else if lower.contains("how many") || lower.contains("how much") || lower.contains("percent") || lower.contains("ratio") || lower.contains("rate") || lower.contains("cost") {
            return .numerical
        } else {
            return .factRetrieval
        }
    }
    #endif

}
