//
//  RAGService+AnswerResponsiveness.swift
//  OpenIntelligence
//
//  Whether the answer shown answers the question, in every mode (`AnswerResponsivenessJudge`). Standard writes the
//  answer again once when the first one does not answer; every mode appends the judge's verdict to the gating string
//  (`answers:full|partial|none`), which `VerificationOutcome` reads with the grounding checks.
//

import Foundation

extension RAGService {
    /// Asks the on-device judge whether `answer` answers `question`, and records the verdict in the trace and the
    /// journal. Nil when the model is unavailable or the call fails.
    func judgeResponsiveness(question: String, answer: String, stage: String) async -> ResponsivenessJudgment? {
        let judgment = await AnswerResponsivenessJudge.judge(
            question: question,
            answer: answer,
            sanitize: { text in
                #if canImport(FoundationModels)
                    FoundationModelPromptCompiler.sanitizeForLanguageDetection(text)
                #else
                    text
                #endif
            }
        )
        guard let judgment else {
            Log.info("[Responsiveness] \(stage): no judgment (model unavailable or the call failed)", category: .llm)
            VerificationJournal.record("answer.responsiveness", ["stage": stage, "verdict": "unjudged"])
            return nil
        }
        #if DEBUG
            Log.debug(
                "[Responsiveness] \(stage) answer: \(String(answer.prefix(400)).replacingOccurrences(of: "\n", with: " ⏎ "))",
                category: .llm)
        #endif
        Log.info(
            "[Responsiveness] \(stage): \(judgment.verdict.rawValue) in \(String(format: "%.2f", judgment.seconds))s "
                + "(asks for: \(judgment.askedFor); missing: \(judgment.missing.isEmpty ? "nothing" : judgment.missing); "
                + "answer \(answer.count) chars)",
            category: .llm
        )
        VerificationJournal.record(
            "answer.responsiveness", .info, durationMs: judgment.seconds * 1000,
            ["stage": stage, "verdict": judgment.verdict.rawValue, "answerChars": "\(answer.count)"])
        return judgment
    }

    /// Whether an answer holds no word at all: empty, or only digits, list markers and punctuation ("1", "2.", "-").
    /// Such an answer is never what this app writes, since even a bare value carries its citation ("60 [S1]"), so it is
    /// written again without asking the judge (5.8). On 2026-11-09 the on-device model stopped after "1" with a prompt
    /// near its window, the judge called "1" a full answer to "How much lysine is present?", and the reader saw a blank.
    nonisolated static func isDegenerateAnswer(_ text: String) -> Bool {
        !text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// What Standard shows when the answer and its rewrite both came back with no words (5.8), instead of a blank.
    nonisolated static let notFoundAnswer =
        "I couldn't find an answer to this in the passages I searched. Try asking with the document's own words, or in Deep Think."

    /// How completely a verdict answers, for comparing an answer with its rewrite.
    nonisolated static func responsivenessRank(_ verdict: AnswerResponsiveness) -> Int {
        switch verdict {
        case .none: return 0
        case .partial: return 1
        case .full: return 2
        }
    }

    /// `question` is the prompt the answer was generated from, which carries the conversation's earlier turns when the
    /// question is a follow-up ("And the second one?"), so the judge and the rewrite read it as the model did.
    ///
    /// Step 6r (responsiveness): judges Standard's generated answer and, when it does not give all of what the question
    /// asks for, writes it once more with the judge's note on what was asked and what was missing. The rewrite is kept
    /// only when the judge reads it as answering more completely than the first; the gates and the source-only check then run on whichever text is kept. The
    /// rewrite does not stream: the chat shows the final text when the answer finishes, as it does for the source-only
    /// check's rewrite.
    func ensureAnswerResponds(
        responseText: inout String,
        llmResponse: inout LLMResponse,
        question: String,
        genConfig: InferenceConfig,
        requiresCitations: Bool,
        generationContext: String,
        generationChunks: [DocumentChunk]
    ) async -> ResponsivenessJudgment? {
        let degenerate = Self.isDegenerateAnswer(responseText)
        let judged: ResponsivenessJudgment?
        if degenerate {
            // No word at all: the judge read "1" as a full answer to "How much lysine is present?" (2026-11-09).
            Log.warning(
                "[Responsiveness] The generated answer has no words (\(responseText.count) chars); writing it again",
                category: .llm)
            VerificationJournal.record(
                "answer.responsiveness",
                ["stage": "generated", "verdict": "degenerate", "answerChars": "\(responseText.count)"])
            judged = ResponsivenessJudgment(verdict: .none, askedFor: "", missing: "", seconds: 0)
        } else {
            judged = await judgeResponsiveness(question: question, answer: responseText, stage: "generated")
        }
        guard let first = judged else { return nil }
        guard first.verdict != .full else { return first }
        defer {
            if Self.isDegenerateAnswer(responseText) {
                Log.warning(
                    "[Responsiveness] The rewrite has no words either; saying the answer was not found", category: .llm)
                responseText = Self.notFoundAnswer
            }
        }

        emitThinkingEvent(
            .warning,
            title: first.verdict == .none ? "The answer didn't answer the question" : "The answer was incomplete",
            detail: first.askedFor.isEmpty ? "Writing it again" : "Writing it again: it asks for \(first.askedFor)"
        )
        var retryConfig = genConfig
        retryConfig.temperature = min(retryConfig.temperature, 0.2)
        retryConfig.skipContinuation = true
        let retryPrompt =
            question + "\n\n" + first.regenerationNote
            + (requiresCitations ? " Cite the sources with bracket ids like [S1]." : "")
        let regenerated: LLMResponse? = try? await LLMStreamingContext.$handler.withValue(nil) {
            try await generateWithFallback(
                prompt: retryPrompt,
                context: generationContext,
                config: retryConfig,
                sourceChunks: generationChunks
            )
        }
        guard let regenerated else {
            Log.warning("[Responsiveness] The rewrite failed; keeping the generated answer", category: .llm)
            return first
        }
        let candidate = cleanupResponseText(regenerated.text)
        guard let second = await judgeResponsiveness(question: question, answer: candidate, stage: "rewritten"),
            Self.responsivenessRank(second.verdict) > Self.responsivenessRank(first.verdict)
        else {
            Log.warning(
                "[Responsiveness] The rewrite answered no better; keeping the generated answer", category: .llm)
            return first
        }
        Log.info(
            "[Responsiveness] The rewrite replaces the generated answer (\(responseText.count) -> \(candidate.count) chars)",
            category: .llm)
        responseText = candidate
        llmResponse = regenerated
        return second
    }
}
