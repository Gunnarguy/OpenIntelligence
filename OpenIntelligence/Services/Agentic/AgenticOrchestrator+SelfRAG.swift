//
//  AgenticOrchestrator+SelfRAG.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - Self-RAG (Adaptive Retrieval)

    /// Self-RAG: Model decides when to retrieve, what to retrieve, and self-critiques answers.
    /// Paper: Asai et al. 2023 - "Self-RAG: Learning to Retrieve, Generate, and Critique"
    ///
    /// Key insight: Not every query needs retrieval. Simple queries can be answered directly,
    /// while complex queries benefit from retrieval. The model decides.
    ///
    /// Flow:
    /// 1. Analyze query → decide if retrieval is needed
    /// 2. If yes → retrieve → generate with context → self-critique
    /// 3. If no → generate directly → self-critique
    /// 4. If critique fails → force retrieval and regenerate
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - onStep: Callback for streaming thinking steps
    /// - Returns: AgenticResult with final answer
    func executeSelfRAG(
        query: String,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        Log.info("[Self-RAG] Analyzing query to decide retrieval strategy", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Decide if retrieval is needed
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (needsRetrieval, retrievalReason) = try await decideIfRetrievalNeeded(
            query: query,
            ragService: ragService
        )

        let decisionStep = ThinkingStep(
            id: UUID(),
            type: .planning,
            input: query,
            output: needsRetrieval
                ? "📚 Retrieval needed: \(retrievalReason)"
                : "💡 Direct answer possible: \(retrievalReason)",
            tokensUsed: 50,
            duration: 0.1,
            timestamp: Date()
        )
        steps.append(decisionStep)
        totalTokens += 50
        await onStep?(decisionStep)

        var answer: String

        if needsRetrieval {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 2a: Retrieve and generate with context
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Log.info("[Self-RAG] Executing retrieval-augmented generation", category: .llm)

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: query,
                ragService: ragService,
                onDetailedEvent: detailedForwarder
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            allRetrievedChunks.append(contentsOf: chunks)
            await onStep?(searchStep)

            // Generate with retrieved context
            let synthesisStep = try await executeComprehensiveSynthesis(
                query: query,
                chunks: allRetrievedChunks,
                ragService: ragService
            )
            steps.append(synthesisStep)
            totalTokens += synthesisStep.tokensUsed
            answer = synthesisStep.output
            await onStep?(synthesisStep)
        } else {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 2b: Generate directly without retrieval
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Log.info("[Self-RAG] Generating direct answer (no retrieval)", category: .llm)

            // Not streamed, unlike the other final-answer calls: this answer is provisional. A failed
            // self-critique below replaces it with a forced retrieval and a second synthesis that
            // `finishAnswerNow()` cannot end, so a streamed draft would sit under "Refining…" with a
            // Stop button that does nothing.
            let directResponse = try await ragService.generateWithFreshSession(
                prompt: "Answer concisely: \(query)",
                maxTokens: 600
            )

            let directStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: query,
                output: directResponse.text,
                tokensUsed: directResponse.tokensGenerated,
                duration: 0.5,
                timestamp: Date()
            )
            steps.append(directStep)
            totalTokens += directResponse.tokensGenerated
            answer = directResponse.text
            await onStep?(directStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Self-Critique (hallucination check)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Self-RAG] Self-critiquing answer for quality", category: .llm)

        let (isGrounded, critiqueReason) = try await selfCritiqueAnswer(
            query: query,
            answer: answer,
            hadRetrieval: needsRetrieval,
            ragService: ragService
        )

        let critiqueStep = ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Self-critique",
            output: isGrounded
                ? "✅ Answer verified: \(critiqueReason)"
                : "⚠️ Needs improvement: \(critiqueReason)",
            tokensUsed: 50,
            duration: 0.1,
            timestamp: Date()
        )
        steps.append(critiqueStep)
        totalTokens += 50
        await onStep?(critiqueStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 4: If critique failed and we didn't retrieve, force retrieval
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if !isGrounded && !needsRetrieval {
            Log.info("[Self-RAG] Critique failed → forcing retrieval", category: .llm)

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: query,
                ragService: ragService,
                onDetailedEvent: detailedForwarder
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            allRetrievedChunks.append(contentsOf: chunks)
            await onStep?(searchStep)

            // Regenerate with retrieved context
            let retryStep = try await executeComprehensiveSynthesis(
                query: query,
                chunks: allRetrievedChunks,
                ragService: ragService
            )
            steps.append(retryStep)
            totalTokens += retryStep.tokensUsed
            answer = retryStep.output
            await onStep?(retryStep)
        }

        let confidence: Float = isGrounded ? 0.85 : 0.65

        return AgenticResult(
            finalAnswer: answer,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: confidence,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    /// Decide if the query needs document retrieval or can be answered directly
    func decideIfRetrievalNeeded(
        query: String,
        ragService: RAGService
    ) async throws -> (needsRetrieval: Bool, reason: String) {
        _ = ragService

        let profile = await QueryProfileService.shared.buildProfile(
            for: query,
            routingEnabled: false
        )
        let plan = await QueryExecutionPlannerService.shared.buildPlan(
            for: query,
            profile: profile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )

        return (plan.needsRetrieval, plan.reasoning)
    }

    /// Self-critique the answer for quality and grounding
    private func selfCritiqueAnswer(
        query: String,
        answer: String,
        hadRetrieval: Bool,
        ragService: RAGService
    ) async throws -> (isGrounded: Bool, reason: String) {
        // Heuristic critique (fast)
        let answerLower = answer.lowercased()

        // Check for hallucination indicators
        let uncertaintyMarkers = [
            "i don't have", "i cannot", "i'm not able",
            "no information", "not found", "unclear",
            "i think", "probably", "might be", "possibly",
        ]

        let hasUncertainty = uncertaintyMarkers.contains { answerLower.contains($0) }

        // Check for citation presence (if we retrieved)
        let hasCitations = answer.contains("[S") || answer.contains("[Doc")

        if hadRetrieval {
            // With retrieval, we expect citations
            if hasCitations && !hasUncertainty {
                return (true, "Answer cites sources and is confident")
            } else if hasCitations {
                return (true, "Answer cites sources but has some uncertainty")
            } else {
                return (false, "Answer lacks citations despite retrieval")
            }
        } else {
            // Without retrieval, just check for confidence
            if hasUncertainty {
                return (false, "Answer shows uncertainty - should verify with documents")
            } else if answer.count < 50 {
                return (false, "Answer too brief - may be incomplete")
            } else {
                return (true, "Answer appears confident and complete")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Self-RAG 2.0: Answer Verification & Citation Grounding
    // 2026 RAG Best Practice: Don't just generate — VERIFY before returning
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Result of Self-RAG verification
    struct SelfRAGVerification: Sendable {
        /// Does the answer actually address the user's question?
        let addressesQuestion: Bool
        /// Are citations grounded in actual source content?
        let citationsVerified: Bool
        /// Number of citations that were verified
        let verifiedCitationCount: Int
        /// Number of citations that couldn't be verified (hallucinated)
        let unverifiedCitationCount: Int
        /// Calibrated confidence score (0-1) based on semantic + lexical signals
        let calibratedConfidence: Float
        /// Human-readable summary of verification
        let summary: String
        /// Suggested action: "accept", "retry", "escalate"
        let action: String
    }

    private func semanticDelta(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })
        let words2 = Set(text2.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })

        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        let jaccardSimilarity = Double(intersection) / Double(union)
        return 1.0 - jaccardSimilarity
    }

    /// Record what the verification loop is about to discard.
    ///
    /// The loop overwrites `currentAnswer` with whatever recursive research returned, and the
    /// replaced text was never written anywhere. An 83-case run on 2026-08-15 showed 18 answers
    /// collapsing from a median 3510 characters to 181, and the question of whether the discarded
    /// answer was actually better could not be settled from the artifacts, because only the winner
    /// was ever recorded. Both lengths and the citation counts are the evidence needed to decide
    /// whether this replacement should be guarded at all. Logging only, no behaviour change.
    /// Counts citation markers in both the bracket and parenthesis forms.
    ///
    /// This previously matched `\[S\d+\]` only, while `verifyCitations` a few hundred lines
    /// below already matched `[\[(]S(\d+)[\])]` — and carries a comment explaining exactly
    /// why: the prompts ask for `[S1]`, models routinely write `(S1)` instead, and a device
    /// run produced an answer carrying five `(S1)`/`(S2)` markers that scored `citations=0/0`.
    /// That fix was applied to one of the two counters, which is how this repository has now
    /// produced four separate defects.
    ///
    /// The undercount was not cosmetic here. `shouldAcceptReplacement` returns `true` when
    /// `previousCitations == 0`, on the reasoning that there is nothing to protect. An answer
    /// citing entirely in parentheses counted as zero, so the guard waved through precisely
    /// the replacement it exists to block.
    ///
    /// `nonisolated static` so both this and the guard above it are testable without an
    /// orchestrator, a model or a query.
    nonisolated static func citationCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"[\[(]S\d+[\])]"#) else { return 0 }
        return regex.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    /// Decide whether the verification loop may overwrite the answer it already has.
    ///
    /// The rule is **never trade a grounded answer for an ungrounded one**, and it is deliberately
    /// not a rule about length. A shorter answer is often the better answer, and an earlier reading
    /// of this defect that assumed "longer is better" was correctly rejected: 12 of the 18 answers
    /// discarded in the 2026-08-15 run had themselves failed citation grounding, so length alone
    /// establishes nothing.
    ///
    /// What settled it was recording both sides. The first case to hit this path after the
    /// instrumentation landed logged `2647 chars with 4 citations -> 53 chars with 0 citations`.
    /// That is not a length trade, it is the loss of every source the answer had, and this app's
    /// entire proposition is that its answers are attributable to documents the user owns.
    ///
    /// The asymmetry this closes: `AgenticPolicyService` retries when `groundingScore < 0.3 &&
    /// totalCitations > 0`, while an answer with no citations has its grounding forced to 0.5 and
    /// skips the check. So an uncited replacement always verifies cleaner than the cited original
    /// it displaced, and the loop preferred it for precisely that reason.
    /// Whether research's answer may take the place of the chain's synthesis (5.7, roadmap row "Deep
    /// Think replaces a full synthesis with a one-line research answer when the synthesis hedges, and
    /// the one line can be wrong").
    ///
    /// Research runs when the synthesis hedges, and its answer replaced the synthesis whenever
    /// `shouldAcceptReplacement` passed, which a synthesis without citation markers always lets
    /// through. Measured on 2026-09-23 (macOS, Deep Think, one document): a 3,372-character synthesis
    /// gave way to "OpenIntelligence handles file types such as notes, warnings, exceptions, and
    /// documents.", which is wrong. Now a synthesis of 400 characters or more gives way to an answer
    /// under a quarter of its length only when what that answer adds beyond the question's own words
    /// is mostly in the synthesis too (60 percent of those words or more): the short answer has to
    /// agree with what the person was already shown, not bring a claim of its own. "Nine verification
    /// checks run." can replace a synthesis that names nine checks; the file-type line can't replace
    /// one that never mentions warnings or exceptions. A longer research answer is a rewrite, and the
    /// rules before decide it.
    nonisolated static func researchMayReplaceSynthesis(question: String, synthesis: String, research: String) -> Bool {
        let synthesisText = synthesis.trimmingCharacters(in: .whitespacesAndNewlines)
        let researchText = research.trimmingCharacters(in: .whitespacesAndNewlines)
        guard synthesisText.count >= 400, researchText.count * 4 < synthesisText.count else { return true }
        let added = answerWords(in: researchText).subtracting(answerWords(in: question))
        guard !added.isEmpty else { return false }
        let shown = answerWords(in: synthesisText)
        let agreed = added.filter { shown.contains($0) }.count
        return Double(agreed) / Double(added.count) >= 0.6
    }

    /// What the Self-RAG loop does with research's answer (5.7).
    nonisolated enum LoopResearchVerdict: Equatable {
        /// Research's answer takes the loop answer's place.
        case replace
        /// The loop keeps its answer and carries on, as it always did when a replacement was turned away.
        case keep
        /// The loop keeps its answer and stops: research's answer doesn't agree with it, and another research run on
        /// the same question costs up to three minutes for the same kind of answer (review, 2026-10-18).
        case keepAndStop
    }

    /// The checks the first call site applies before research's answer replaces the chain's synthesis, for the Self-RAG
    /// loop's call, the one Deep Think reaches (`maxIterations: 3`) (5.7). Until 2026-10-18 the loop applied only
    /// `shouldAcceptReplacement`, so a short research answer turned away at the first site could still replace the
    /// answer here (found by a triage read of the roadmap row, 2026-10-18). The evidence-dump and retrieval-miss checks
    /// are instance methods, so the caller passes their results.
    nonisolated static func loopResearchVerdict(
        question: String, answer: String, research: String, isEvidenceDump: Bool, isRetrievalMiss: Bool
    ) -> LoopResearchVerdict {
        guard researchMayReplaceSynthesis(question: question, synthesis: answer, research: research) else {
            return .keepAndStop
        }
        guard !isEvidenceDump, !isRetrievalMiss else { return .keep }
        return shouldAcceptReplacement(previous: answer, replacement: research) ? .replace : .keep
    }

    /// The words of an answer that carry its content: lowercased, three letters or more or a number,
    /// without stop words, and a number written as a word ("nine") counted as its digits ("9").
    nonisolated static func answerWords(in text: String) -> Set<String> {
        let numberWords = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
            "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
            "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18",
            "nineteen": "19", "twenty": "20",
        ]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { numberWords[$0] ?? $0 }
            .filter { word in
                guard !word.isEmpty else { return false }
                if word.allSatisfy(\.isNumber) { return true }
                return word.count >= 3 && !answerStopWords.contains(word)
            }
        return Set(words)
    }

    /// The stop words `answerWords` leaves out: the lexical check's list, plus the words any short
    /// answer opens with.
    nonisolated private static let answerStopWords: Set<String> = [
        "the", "are", "was", "were", "been", "being", "have", "has", "had", "does", "did", "will",
        "would", "could", "should", "may", "might", "must", "shall", "can", "for", "with", "from",
        "into", "through", "during", "before", "after", "above", "below", "between", "under", "again",
        "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "each", "few",
        "more", "most", "other", "some", "such", "nor", "not", "only", "own", "same", "than", "too",
        "very", "just", "also", "now", "what", "which", "who", "whom", "this", "that", "these",
        "those", "its", "myself", "our", "ours", "ourselves", "you", "your", "yours", "him", "his",
        "her", "hers", "they", "them", "their", "and", "but", "any", "both", "include", "includes",
        "including", "like",
    ]

    nonisolated static func shouldAcceptReplacement(previous: String, replacement: String) -> Bool {
        let previousCitations = citationCount(in: previous)
        let replacementCitations = citationCount(in: replacement)

        // Nothing to protect: the answer being replaced was never grounded.
        guard previousCitations > 0 else { return true }

        if replacementCitations == 0 {
            Log.warning(
                "[Agentic] Rejected replacement: would trade \(previousCitations) citations for none "
                    + "(\(previous.count) chars -> \(replacement.count) chars). Keeping the grounded answer.",
                category: .llm
            )
            return false
        }
        return true
    }

    private func logAnswerReplacement(previous: String, replacement: String, reason: String) {
        let ratio = replacement.isEmpty ? 0 : Double(previous.count) / Double(max(replacement.count, 1))
        Log.warning(
            "[Agentic] Answer replaced (\(reason)): \(previous.count) chars with \(Self.citationCount(in: previous)) citations "
                + "-> \(replacement.count) chars with \(Self.citationCount(in: replacement)) citations "
                + "(shrink \(String(format: "%.1f", ratio))x)",
            category: .llm
        )
    }

    func runVerificationLoop(
        query: String,
        initialAnswer: String,
        initialSteps: [ThinkingStep],
        initialTokens: Int,
        initialConfidence: Float,
        initialSources: [RetrievedChunk],
        ragService: RAGService,
        startTime: Date,
        onStep: ((ThinkingStep) async -> Void)?
    ) async throws -> AgenticResult {
        var currentAnswer = initialAnswer
        var currentSteps = initialSteps
        var currentTokens = initialTokens
        var currentConfidence = initialConfidence
        var currentSources = initialSources

        var strikeCount = 0
        let maxStrikes = 3

        while strikeCount < maxStrikes {
            let verification = await verifySelfRAG(
                query: query,
                answer: currentAnswer,
                sourceChunks: currentSources,
                ragService: ragService
            )

            let verifyStep = ThinkingStep(
                id: UUID(),
                type: .verifying,
                input: "Self-RAG verification",
                output: verification.summary,
                tokensUsed: 0,
                duration: 0.1,
                timestamp: Date(),
                confidence: verification.calibratedConfidence
            )
            currentSteps.append(verifyStep)
            await onStep?(verifyStep)

            currentConfidence = verification.calibratedConfidence

            if verification.action == "retry" && !answerIndicatesRetrievalMiss(currentAnswer) {
                strikeCount += 1
                Log.info(
                    "[Agentic] Self-RAG: Verification suggests retry (Strike \(strikeCount)/\(maxStrikes))",
                    category: .llm)

                if strikeCount >= maxStrikes {
                    Log.warning(
                        "[Agentic] Self-RAG: Max verification strikes reached. Refusing further retries.",
                        category: .llm)
                    break
                }

                // Try recursive research as backup.
                //
                // A throw here must not destroy `currentAnswer`. The block below already keeps the
                // previous answer when research returns an *empty* one; only a throw skipped that,
                // and this call was a bare `try await`.
                //
                // This is the second of two call sites and the one that actually fires in Deep
                // Think. Device captures on 2026-08-14 identify it unambiguously by its iteration
                // count: the log reads "[RecursiveResearch] Iteration 1/3", and only this site
                // passes maxIterations: 3. The other site, guarded earlier the same day, passes 5.
                // Guarding one and not the other left the failure fully intact while looking fixed.
                let recursiveResult: AgenticResult
                do {
                    recursiveResult = try await executeRecursiveResearch(
                        query: query,
                        maxIterations: 3,
                        onStep: onStep
                    )
                } catch {
                    Log.warning(
                        "[Agentic] Self-RAG: recursive research failed (\(type(of: error))): "
                            + "\(error.localizedDescription). Keeping the current answer.",
                        category: .llm
                    )
                    break
                }

                let newAnswer = recursiveResult.finalAnswer

                // Check if the retry returned an empty response
                let cleanNewAnswer = newAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanNewAnswer.isEmpty {
                    Log.warning(
                        "[Agentic] Self-RAG: Retry returned an empty answer. Keeping the previous non-empty answer.",
                        category: .llm)
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    // Do NOT update currentAnswer to empty. Leave currentAnswer as it was.
                    break
                }

                // Check semantic delta
                let delta = semanticDelta(newAnswer, currentAnswer)
                Log.debug(
                    "[Agentic] Semantic delta between verification attempts: \(String(format: "%.4f", delta))",
                    category: .llm)

                if delta < 0.10 {
                    Log.warning(
                        "[Agentic] Self-RAG: Semantic delta too low (\(String(format: "%.4f", delta)) < 0.10). Refusing further retries.",
                        category: .llm)
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    let verdict = Self.loopResearchVerdict(
                        question: query, answer: currentAnswer, research: newAnswer,
                        isEvidenceDump: looksLikeRawEvidenceDump(cleanNewAnswer),
                        isRetrievalMiss: answerIndicatesRetrievalMiss(newAnswer))
                    if verdict == .replace {
                        logAnswerReplacement(
                            previous: currentAnswer, replacement: newAnswer, reason: "semantic delta below 0.10")
                        currentAnswer = newAnswer
                    } else {
                        Log.warning(
                            "[Agentic] Self-RAG: kept the answer (\(currentAnswer.count) chars) over research's "
                                + "\(newAnswer.count)-char answer (\(verdict))",
                            category: .llm)
                    }
                    break
                }

                if !answerIndicatesRetrievalMiss(newAnswer) {
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    let verdict = Self.loopResearchVerdict(
                        question: query, answer: currentAnswer, research: newAnswer,
                        isEvidenceDump: looksLikeRawEvidenceDump(cleanNewAnswer), isRetrievalMiss: false)
                    if verdict == .replace {
                        logAnswerReplacement(
                            previous: currentAnswer, replacement: newAnswer,
                            reason: "recursive research returned an answer")
                        currentAnswer = newAnswer
                    } else {
                        Log.warning(
                            "[Agentic] Self-RAG: kept the answer (\(currentAnswer.count) chars) over research's "
                                + "\(newAnswer.count)-char answer (\(verdict))",
                            category: .llm)
                        if verdict == .keepAndStop { break }
                    }
                    // Update sources/chunks
                    for chunk in recursiveResult.retrievedChunks {
                        if !currentSources.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                            currentSources.append(chunk)
                        }
                    }
                } else {
                    break
                }
            } else {
                break
            }
        }

        return AgenticResult(
            finalAnswer: currentAnswer,
            steps: currentSteps,
            totalTokens: currentTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: currentConfidence,
            sourcesUsed: currentSources.count,
            retrievedChunks: currentSources
        )
    }

    /// Full Self-RAG verification: answer relevance + citation grounding + confidence calibration
    /// Called after Deep Think synthesis to ensure quality before returning to user
    func verifySelfRAG(
        query: String,
        answer: String,
        sourceChunks: [RetrievedChunk],
        ragService: RAGService
    ) async -> SelfRAGVerification {
        Log.info(
            "[Self-RAG 2.0] Starting verification: query=\(query.prefix(50))..., answer=\(answer.count) chars",
            category: .llm)

        // 1. Check if answer addresses the question (semantic relevance)
        let addressScore = computeAnswerRelevance(query: query, answer: answer)
        let addressesQuestion = AgenticPolicyService.addressesQuestion(for: addressScore)

        // 2. Verify citations are grounded in sources
        let citationResult = verifyCitations(answer: answer, sources: sourceChunks)

        // 3. Compute calibrated confidence
        let calibrated = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: addressScore,
            citationScore: citationResult.groundingScore,
            answerLength: answer.count,
            sourceCount: sourceChunks.count
        )

        let assertsAbsence = AgenticPolicyService.assertsAbsenceOfEvidence(in: answer)
        if assertsAbsence && citationResult.totalCitations > 0 {
            Log.warning(
                "[Self-RAG 2.0] Answer asserts its sources do not cover the question while citing "
                    + "\(citationResult.totalCitations) of them. Treating as self-contradicting.",
                category: .llm
            )
        }

        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: addressesQuestion,
            groundingScore: citationResult.groundingScore,
            totalCitations: citationResult.totalCitations,
            calibratedConfidence: calibrated,
            assertsAbsenceOfEvidence: assertsAbsence
        )

        let summary = buildVerificationSummary(
            addressesQuestion: addressesQuestion,
            addressScore: addressScore,
            citationResult: citationResult,
            calibrated: calibrated,
            action: action
        )

        Log.info(
            "[Self-RAG 2.0] Verification complete: \(action) (relevance=\(Int(addressScore * 100))%, citations=\(citationResult.verified)/\(citationResult.totalCitations), confidence=\(Int(calibrated * 100))%)",
            category: .llm)

        return SelfRAGVerification(
            addressesQuestion: addressesQuestion,
            citationsVerified: citationResult.verified == citationResult.totalCitations
                && citationResult.totalCitations > 0,
            verifiedCitationCount: citationResult.verified,
            unverifiedCitationCount: citationResult.totalCitations - citationResult.verified,
            calibratedConfidence: calibrated,
            summary: summary,
            action: action
        )
    }

    /// Compute semantic relevance between query and answer using lexical overlap + key term matching
    /// UNIVERSAL: No domain-specific logic - works for any document type
    /// FIXED 2026-01: Previous version was too strict, rejecting valid answers with technical specs
    private func computeAnswerRelevance(query: String, answer: String) -> Float {
        let queryLower = query.lowercased()
        let answerLower = answer.lowercased()

        // Extract key terms from query (remove stop words)
        let stopWords: Set<String> = [
            "what", "how", "why", "when", "where", "who", "which",
            "does", "do", "is", "are", "was", "were", "the", "a", "an",
            "of", "in", "to", "for", "and", "or", "on", "with", "this", "that",
            "kind", "type", "take", "use", "need", "require", "should", "can",
        ]
        let queryTerms = queryLower.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // CRITICAL FIX: If query is about specs/types, check if answer has technical content
        // E.g., "what oil" → answer has "0W-20", "SAE", viscosity = GREAT match
        let isSpecQuery =
            queryLower.contains("what") || queryLower.contains("which") || queryLower.contains("type")
            || queryLower.contains("kind") || queryLower.contains("specification") || queryLower.contains("grade")

        // Technical content patterns (indicates answer is providing actual specs)
        let technicalPatterns = [
            #"\d+[wW]-\d+"#,  // Oil viscosity: 0W-20, 5W-30
            #"[A-Z]{2,}[\s-]?\d+"#,  // Spec codes: SAE, API SN, ACEA
            #"\d+\.?\d*\s*(mm|cm|l|L|gal|qt|oz|psi|bar|kpa|°|degrees)"#,  // Measurements
            #"\d+\.?\d*\s*(hp|kw|nm|lb|kg|mph|km/h)"#,  // Power/speed units
            #"[A-Z]\d{1,3}[A-Z]?"#,  // Part codes: M5, B48, etc.
        ]

        var hasTechnicalContent = false
        for pattern in technicalPatterns {
            if answer.range(of: pattern, options: .regularExpression) != nil {
                hasTechnicalContent = true
                break
            }
        }

        // If it's a spec query and answer has technical content, that's a strong signal
        let technicalBonus: Float = (isSpecQuery && hasTechnicalContent) ? 0.40 : 0

        // Score 1: Key term coverage (what % of query terms appear in answer?)
        // Relaxed: even 1 match is meaningful for short queries
        var matchedTerms = 0
        for term in queryTerms {
            if answerLower.contains(term) {
                matchedTerms += 1
            }
        }
        let termCoverage: Float
        if queryTerms.isEmpty {
            termCoverage = 0.5  // Can't evaluate without terms, neutral
        } else if matchedTerms > 0 {
            // At least one match = base relevance
            termCoverage = 0.3 + (Float(matchedTerms) / Float(queryTerms.count)) * 0.7
        } else {
            termCoverage = 0.1  // No direct matches, but don't zero out
        }

        // Score 2: Answer has concrete specifics (numbers, citations)
        let hasNumbers = answer.range(of: #"\d+\.?\d*"#, options: .regularExpression) != nil
        let hasCitations = answer.contains("[S") || answer.contains("[Doc")
        let specificityBonus: Float = (hasNumbers ? 0.10 : 0) + (hasCitations ? 0.10 : 0)

        // Score 3: Penalty for hedging/non-answers (UNIVERSAL patterns)
        // RELAXED: Only penalize strong hedging, not normal caveats
        let hedgingMarkers = [
            "isn't explicitly",
            "not explicitly",
            "remains speculative",
            "without specific information",
            "insufficient information",
            "not enough information",
            "cannot be determined",
            "no information available",
        ]
        let hedgingCount = hedgingMarkers.filter { answerLower.contains($0) }.count
        let hedgingPenalty: Float = min(Float(hedgingCount) * 0.15, 0.40)

        // Score 4: Length-to-substance ratio
        // Long answers that hedge a lot are worse than short direct answers
        let lengthPenalty: Float
        if answer.count > 4000 && hedgingCount >= 3 {
            lengthPenalty = 0.15  // Long AND heavily hedging = bad
        } else {
            lengthPenalty = 0
        }

        // Score 5: Refusal detection - STRONG penalty only for clear refusals
        let refusalMarkers = ["i cannot answer", "no information found", "unable to determine"]
        let hasRefusal = refusalMarkers.contains { answerLower.contains($0) }
        let refusalPenalty: Float = hasRefusal ? 0.30 : 0

        // Score 6: URL hallucination detection
        // If model generates URLs instead of [S1] citations, that's a hallucination
        let urlPattern = #"https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}"#
        let hasURLs = answer.range(of: urlPattern, options: .regularExpression) != nil
        let urlHallucinationPenalty: Float = hasURLs ? 0.25 : 0

        // FIXED FORMULA: Start with base relevance, add bonuses, then subtract penalties
        // Technical content bonus is additive, not just term-based
        let baseRelevance = termCoverage * 0.50 + technicalBonus + specificityBonus
        let penalties = hedgingPenalty + lengthPenalty + refusalPenalty + urlHallucinationPenalty
        let relevance = min(1.0, max(0.1, baseRelevance - penalties))  // Floor at 10% if we have any answer

        return relevance
    }

    /// Citation verification result
    private struct CitationVerificationResult {
        let verified: Int  // Citations that exist in sources
        let totalCitations: Int  // Total [S1], [S2], etc. found
        let groundingScore: Float  // 0-1, how well citations are grounded
        let details: [String]  // Per-citation verification details
    }

    /// Verify that citations [S1], [S2], etc. actually reference content from sources
    /// Report any `[S#]` in `text` that points past the end of the source list.
    ///
    /// `verifyCitations` only ever inspected the final answer, so a dangling citation in the
    /// reasoning trace — which is rendered to the user and included in the exported trace — reached
    /// the screen unchecked. The 2026-08-19 capture displayed `[S13]` and `[S17]` against a
    /// 12-source list while the existing out-of-range branch stayed silent, because it was pointed
    /// at the wrong text.
    nonisolated static func danglingCitations(in text: String, sourceCount: Int) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\[S([0-9]+)\\]") else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var dangling: Set<Int> = []
        for match in regex.matches(in: text, range: range) where match.numberOfRanges > 1 {
            guard let numberRange = Range(match.range(at: 1), in: text),
                let index = Int(text[numberRange])
            else { continue }
            if index < 1 || index > sourceCount { dangling.insert(index) }
        }
        return dangling.sorted()
    }

    private func verifyCitations(answer: String, sources: [RetrievedChunk]) -> CitationVerificationResult {
        // Extract citation markers from answer.
        //
        // Both bracket and parenthesis forms. The prompts ask for [S1], but models
        // routinely write (S1) instead, and a device run produced an answer carrying
        // five (S1)/(S2) markers that this check scored `citations=0/0` — reporting an
        // answer as uncited when every claim in it was attributed. The distinction is
        // a punctuation preference, not a difference in grounding.
        let citationPattern = #"[\[(]S(\d+)[\])]"#
        guard let regex = try? NSRegularExpression(pattern: citationPattern, options: []) else {
            return CitationVerificationResult(verified: 0, totalCitations: 0, groundingScore: 1.0, details: [])
        }

        let matches = regex.matches(in: answer, options: [], range: NSRange(answer.startIndex..., in: answer))

        // Get unique citation numbers
        var citationNumbers: Set<Int> = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: answer),
                let num = Int(answer[range])
            {
                citationNumbers.insert(num)
            }
        }

        guard !citationNumbers.isEmpty else {
            // No citations = can't verify, but not necessarily bad
            return CitationVerificationResult(
                verified: 0, totalCitations: 0, groundingScore: 0.5, details: ["No citations found"])
        }

        // Verify each citation exists in sources
        var verified = 0
        var details: [String] = []

        for citationNum in citationNumbers.sorted() {
            let sourceIndex = citationNum - 1  // [S1] = sources[0]
            if sourceIndex >= 0 && sourceIndex < sources.count {
                // Source exists — now verify the claim is actually in the source
                let sourceContent = sources[sourceIndex].chunk.content.lowercased()

                // Find text near the citation in the answer
                let citationMarker = "[S\(citationNum)]"
                if let markerRange = answer.range(of: citationMarker) {
                    // Extract ~50 chars before the citation marker
                    let start =
                        answer.index(markerRange.lowerBound, offsetBy: -50, limitedBy: answer.startIndex)
                        ?? answer.startIndex
                    let claimText = String(answer[start..<markerRange.lowerBound]).lowercased()

                    // Check if key words from the claim appear in the source
                    let claimWords = claimText.split(separator: " ")
                        .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                        .filter { $0.count > 3 }

                    var matchedWords = 0
                    for word in claimWords.prefix(10) {
                        if sourceContent.contains(word) {
                            matchedWords += 1
                        }
                    }

                    let claimGrounded =
                        claimWords.isEmpty || Float(matchedWords) / Float(max(claimWords.count, 1)) >= 0.3
                    if claimGrounded {
                        verified += 1
                        details.append("[S\(citationNum)]: ✓ Verified in source")
                    } else {
                        details.append("[S\(citationNum)]: ⚠ Claim not found in source")
                    }
                } else {
                    // Citation marker found via regex but not simple search — weird but accept
                    verified += 1
                    details.append("[S\(citationNum)]: ✓ Source exists")
                }
            } else {
                details.append("[S\(citationNum)]: ✗ Source index out of range")
            }
        }

        let groundingScore = citationNumbers.isEmpty ? 0.5 : Float(verified) / Float(citationNumbers.count)
        return CitationVerificationResult(
            verified: verified,
            totalCitations: citationNumbers.count,
            groundingScore: groundingScore,
            details: details
        )
    }

    /// Build human-readable verification summary
    private func buildVerificationSummary(
        addressesQuestion: Bool,
        addressScore: Float,
        citationResult: CitationVerificationResult,
        calibrated: Float,
        action: String
    ) -> String {
        var parts: [String] = []

        parts.append("Relevance: \(Int(addressScore * 100))%")
        if citationResult.totalCitations > 0 {
            parts.append("Citations: \(citationResult.verified)/\(citationResult.totalCitations) verified")
        }
        parts.append("Confidence: \(Int(calibrated * 100))%")
        parts.append("Action: \(action)")

        return parts.joined(separator: " | ")
    }

    // MARK: - Speculative RAG (Multi-Path Verification)

    /// Speculative RAG: Generate multiple candidate answers, verify each against documents.
    /// Catches hallucinations through multi-path verification.
    ///
    /// Flow:
    /// 1. Retrieve relevant documents
    /// 2. Generate N candidate answers (with temperature variation)
    /// 3. Score each candidate against source documents
    /// 4. Return highest-scoring grounded answer
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - candidateCount: Number of candidate answers to generate (default: 3)
    ///   - onStep: Callback for streaming thinking steps
    /// - Returns: AgenticResult with best verified answer
    func executeSpeculativeRAG(
        query: String,
        candidateCount: Int = 3,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        Log.info("[Speculative-RAG] Starting multi-path verification with \(candidateCount) candidates", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Retrieve documents
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (searchStep, chunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
        )
        steps.append(searchStep)
        totalTokens += searchStep.tokensUsed
        allRetrievedChunks.append(contentsOf: chunks)
        await onStep?(searchStep)

        // Build context from chunks
        let sourceContext = chunks.prefix(5).enumerated().map { index, chunk in
            "[S\(index + 1)] \(chunk.chunk.content.prefix(400))"
        }.joined(separator: "\n\n")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Generate multiple candidate answers
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Speculative-RAG] Generating \(candidateCount) candidate answers", category: .llm)

        var candidates: [(answer: String, tokens: Int)] = []
        let temperatures: [Float] = [0.3, 0.6, 0.8]  // Vary temperature for diversity

        for i in 0..<min(candidateCount, temperatures.count) {
            let temp = temperatures[i]

            let candidateStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: "Candidate \(i + 1) (temp=\(temp))",
                output: "Generating candidate answer...",
                tokensUsed: 0,
                duration: 0,
                timestamp: Date()
            )
            await onStep?(candidateStep)

            let response = try await generateCandidateAnswer(
                query: query,
                context: sourceContext,
                temperature: temp,
                ragService: ragService
            )

            candidates.append((response.text, response.tokensGenerated))
            totalTokens += response.tokensGenerated

            let resultStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: "Candidate \(i + 1)",
                output: "Generated: \(response.text.prefix(100))...",
                tokensUsed: response.tokensGenerated,
                duration: 0.5,
                timestamp: Date()
            )
            steps.append(resultStep)
            await onStep?(resultStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Score each candidate against source documents
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Speculative-RAG] Scoring candidates for grounding", category: .llm)

        var scoredCandidates: [(answer: String, score: Float, reason: String)] = []

        for (index, candidate) in candidates.enumerated() {
            let (score, reason) = scoreAnswerGrounding(
                answer: candidate.answer,
                sourceContext: sourceContext
            )
            scoredCandidates.append((candidate.answer, score, reason))

            let scoreStep = ThinkingStep(
                id: UUID(),
                type: .analyzing,
                input: "Scoring candidate \(index + 1)",
                output: "Score: \(String(format: "%.0f%%", score * 100)) - \(reason)",
                tokensUsed: 10,
                duration: 0.05,
                timestamp: Date()
            )
            steps.append(scoreStep)
            totalTokens += 10
            await onStep?(scoreStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 4: Select best candidate
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let best = scoredCandidates.max(by: { $0.score < $1.score }) ?? scoredCandidates[0]

        let selectionStep = ThinkingStep(
            id: UUID(),
            type: .refining,
            input: "Selecting best answer",
            output:
                "Selected answer with \(String(format: "%.0f%%", best.score * 100)) grounding score: \(best.reason)",
            tokensUsed: 5,
            duration: 0.02,
            timestamp: Date()
        )
        steps.append(selectionStep)
        totalTokens += 5
        await onStep?(selectionStep)

        Log.info("[Speculative-RAG] Selected best candidate with score \(best.score)", category: .llm)

        return AgenticResult(
            finalAnswer: best.answer,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: best.score,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    /// Generate a candidate answer with specific temperature
    private func generateCandidateAnswer(
        query: String,
        context: String,
        temperature: Float,
        ragService: RAGService
    ) async throws -> LLMResponse {
        // Note: We use generateWithFreshSession which uses default temperature
        // In a full implementation, we'd pass temperature to the LLM config
        // For now, we get diversity from multiple calls (LLM has inherent randomness)
        return try await ragService.generateWithFreshSession(
            prompt: """
                Using ONLY the excerpts below, answer the question. Cite [S1], [S2], etc.

                EXCERPTS:
                \(context)

                QUESTION: \(query)

                ANSWER:
                """,
            maxTokens: 500
        )
    }

    /// Score how well an answer is grounded in source documents
    private func scoreAnswerGrounding(
        answer: String,
        sourceContext: String
    ) -> (score: Float, reason: String) {
        var score: Float = 0.5  // Base score

        // Check for citations
        let citationPattern = #"\[S\d+\]"#
        let citationRegex = try? NSRegularExpression(pattern: citationPattern)
        let citationCount =
            citationRegex?.numberOfMatches(
                in: answer,
                range: NSRange(answer.startIndex..., in: answer)
            ) ?? 0

        if citationCount > 0 {
            score += 0.15 * Float(min(citationCount, 3))  // Up to +0.45 for citations
        }

        // Check for key term overlap with source
        let answerWords = Set(answer.lowercased().split(separator: " ").map(String.init))
        let sourceWords = Set(sourceContext.lowercased().split(separator: " ").map(String.init))
        let overlap = answerWords.intersection(sourceWords)
        let overlapRatio = Float(overlap.count) / Float(max(answerWords.count, 1))

        if overlapRatio > 0.3 {
            score += 0.1
        }
        if overlapRatio > 0.5 {
            score += 0.1
        }

        // Check for hedging language (reduces confidence)
        let hedgingWords = ["might", "possibly", "perhaps", "unclear", "uncertain"]
        let hasHedging = hedgingWords.contains { answer.lowercased().contains($0) }
        if hasHedging {
            score -= 0.15
        }

        // Check answer length (very short = suspicious)
        if answer.count < 50 {
            score -= 0.1
        } else if answer.count > 200 {
            score += 0.05
        }

        // Build reason
        var reasons: [String] = []
        if citationCount > 0 {
            reasons.append("\(citationCount) citations")
        }
        if overlapRatio > 0.3 {
            reasons.append("good term overlap")
        }
        if hasHedging {
            reasons.append("contains uncertainty")
        }

        let reason = reasons.isEmpty ? "baseline score" : reasons.joined(separator: ", ")

        return (max(0.2, min(0.95, score)), reason)
    }
}
