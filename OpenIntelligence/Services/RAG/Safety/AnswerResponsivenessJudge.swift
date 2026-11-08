//
//  AnswerResponsivenessJudge.swift
//  OpenIntelligence
//
//  Whether an answer answers its question. Every other check in the app asks whether an answer is in the sources
//  (the gates, the source-only check, Fact Check), and a fragment copied from a source passes all of them: on
//  2026-11-07 the on-device model answered "How much DHA is recommended?" with "1-28. [S3]", a page range from the
//  paper, and the source-only check called it supported at fidelity 1.00. Rules per question type ("how much needs a
//  unit") would be one patch per shape of question, so the judgment comes from the question itself: the on-device
//  model reads the question and the answer, names what the question asks for, and says whether the answer gives it.
//  It does not judge truth; grounding stays with the gates.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// How fully an answer gives what its question asks for.
nonisolated enum AnswerResponsiveness: String, Sendable, Equatable, CaseIterable {
    /// It gives what was asked, or says plainly that the sources do not have it.
    case full
    /// It gives part of what was asked.
    case partial
    /// It does not answer: a fragment, a bare number or range with nothing saying what it is, a heading, a citation
    /// alone, or text about something else.
    case none
}

/// The judge's reading of one answer.
nonisolated struct ResponsivenessJudgment: Sendable, Equatable {
    let verdict: AnswerResponsiveness
    /// What the question asks for, in the judge's words ("an amount of DHA with its unit").
    let askedFor: String
    /// What the answer lacks; empty when the verdict is full.
    let missing: String
    let seconds: Double

    /// The token appended to an answer's gating string, read by `VerificationOutcome`.
    var gatingToken: String { "answers:\(verdict.rawValue)" }

    /// The instruction a regeneration gets when the first answer did not answer.
    var regenerationNote: String {
        let need = askedFor.trimmingCharacters(in: .whitespacesAndNewlines)
        let gap = missing.trimmingCharacters(in: .whitespacesAndNewlines)
        var note =
            verdict == .partial
            ? "Your previous answer answered only part of the question."
            : "Your previous answer did not answer the question."
        if !need.isEmpty { note += " The question asks for \(need)." }
        if !gap.isEmpty { note += " Missing: \(gap)." }
        note += " Answer it directly in a complete sentence from the sources, with any unit, and cite them."
        note += " If the sources give several values, give each with what it applies to."
        note += " If the sources do not contain it, say so."
        return note
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct ResponsivenessReview: Sendable {
        @Guide(description: "What the question asks for, in a few words, for example: an amount with its unit, a date, a person's name, yes or no, a list of items, an explanation, a comparison of two things.")
        let askedFor: String

        @Guide(description: "True if the answer says the documents or sources do not contain what was asked, or do not say. Otherwise false.")
        let saysItIsNotInTheSources: Bool

        @Guide(description: "full, partial or none.", .anyOf(["full", "partial", "none"]))
        let verdict: String

        @Guide(description: "What the answer is missing, in one short sentence. Empty when it gives all of it.")
        let missing: String
    }
#endif

nonisolated enum AnswerResponsivenessJudge {
    /// Longest answer text the judge reads. The on-device window is 4,096 tokens on iPhone; this is about 1,100.
    static let answerCharacterLimit = 4_000

    static let instructions = """
        You check whether an answer answers the question it was given. You do not check whether it is true; another \
        step does that. First decide what the question asks for, then whether the answer gives it.
        full: the answer gives what was asked. A short answer is full when it is what was asked, for example \
        "14.3 gallons" for how much a tank holds, or "Yes, it does" for a yes-or-no question. An answer that says the \
        sources disagree and gives what each says is full.
        partial: it gives only part of what was asked, for example one of two things being compared, or one item of \
        a list that was asked for.
        none: it does not answer. Examples: a number or range with no unit and no words saying what it measures, \
        even when the question asks for an amount, so "1-28" is none for "How much is recommended?"; a page or \
        section number; a heading; a citation alone; a fragment of a sentence; text about something else.
        """

    /// The answer as the judge reads it: citation markers and markdown emphasis removed, cut at the limit.
    static func readableAnswer(_ answer: String) -> String {
        var text = answer.replacingOccurrences(
            of: #"\[(?:S|E)\d+(?:\s*,\s*(?:S|E)?\d+)*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > answerCharacterLimit {
            text = String(text.prefix(answerCharacterLimit)) + " [answer continues]"
        }
        return text
    }

    static func prompt(question: String, answer: String) -> String {
        let readable = readableAnswer(answer)
        return """
            Question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))

            Answer: \(readable.isEmpty ? "(empty)" : readable)

            Does the answer give what the question asks for?
            """
    }

    /// An empty answer, or one with no letter or digit, needs no model to be judged.
    static func judgmentWithoutModel(answer: String) -> ResponsivenessJudgment? {
        let readable = readableAnswer(answer)
        guard !readable.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return ResponsivenessJudgment(verdict: .none, askedFor: "", missing: "the answer is empty", seconds: 0)
    }

    /// The verdict from the review's two answers. An answer that says the sources do not have it answers the
    /// question: the reader learns the library does not say. Measured 2026-11-07, a single verdict field read 5 of 8
    /// such answers as not answering, so the model is asked this as its own question. Its
    /// verdict wording stays the first version's: a second asking "all, some or nothing" and saying an answer naming
    /// one thing of the kind asked for is never nothing passed 24 of 25 page ranges (`BenchmarkRuns/2026-11-07-responsiveness`).
    static func verdict(saysItIsNotInTheSources: Bool, verdict: String) -> AnswerResponsiveness {
        if saysItIsNotInTheSources { return .full }
        return AnswerResponsiveness(rawValue: verdict.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .full
    }

    /// Asks the on-device model. Returns nil when the model is unavailable or the call fails, so a caller keeps its
    /// own behaviour rather than treating an unread answer as unresponsive.
    static func judge(
        question: String,
        answer: String,
        sanitize: @Sendable (String) -> String = { $0 }
    ) async -> ResponsivenessJudgment? {
        if let immediate = judgmentWithoutModel(answer: answer) { return immediate }
        // The golden recorders turn direct model calls off so two passes record the same thing.
        if DirectModelCallsForTesting.isOn { return nil }
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let started = Date()
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: Instructions(sanitize(instructions))
            )
            do {
                let response = try await session.respond(
                    to: sanitize(prompt(question: question, answer: answer)),
                    generating: ResponsivenessReview.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 160)
                )
                let review = response.content
                let reading = Self.verdict(saysItIsNotInTheSources: review.saysItIsNotInTheSources, verdict: review.verdict)
                return ResponsivenessJudgment(
                    verdict: reading,
                    askedFor: review.askedFor,
                    missing: reading == .full ? "" : review.missing,
                    seconds: Date().timeIntervalSince(started)
                )
            } catch {
                return nil
            }
        #else
            return nil
        #endif
    }
}
