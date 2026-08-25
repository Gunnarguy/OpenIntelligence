//
//  AgenticPolicyService.swift
//  OpenIntelligence
//
//  Shared thresholds for Deep Think and Maximum so escalation, stopping, and
//  confidence behavior stay aligned with the configured agentic mode.
//

import Foundation

enum AgenticRetrievalQuality: Sendable {
    case excellent
    case good
    case moderate
    case low

    var confidenceScore: Float {
        switch self {
        case .excellent: return 0.9
        case .good: return 0.75
        case .moderate: return 0.5
        case .low: return 0.3
        }
    }

    var description: String {
        switch self {
        case .excellent: return "Excellent (>50% match)"
        case .good: return "Good (35-50% match)"
        case .moderate: return "Moderate (20-35% match)"
        case .low: return "Low (<20% match)"
        }
    }
}

struct AgenticReasoningPolicy: Sendable {
    let isUnlimitedMode: Bool
    let isDeepThinkMode: Bool
    let usesEvidenceDrivenStopping: Bool
    let shouldReportConfidence: Bool
    let confidenceThreshold: Float
    let minSessionsBeforeEarlyStop: Int
    let maxSessionsForMode: Int
    let initialConfidence: Float
    let evidenceCoverageDefault: Float
    let evidenceCoverageExpanded: Float
    let lowNoveltyThreshold: Float
    let noveltyExhaustionStreakThreshold: Int
    let saturationScoreThreshold: Float
    let saturationStreakThreshold: Int
    /// Floor before convergence may end the run.
    ///
    /// `noveltyExhausted` uses two-session streaks, which can trip on a cold start:
    /// sessions 1 and 2 legitimately produce little novelty relative to an empty
    /// fact bank. This keeps early sessions from being mistaken for exhaustion,
    /// without weakening the streak thresholds that make the rule responsive later.
    let minimumSessionsBeforeConvergence: Int

    /// Sessions of flat sub-question coverage before concluding the remainder is
    /// simply absent from the corpus. Deliberately more patient than the novelty and
    /// saturation streaks: a plateau can break if a later chunk finally supplies the
    /// missing piece, so this waits longer before calling it.
    let coveragePlateauStreakThreshold: Int
    let sourceCoverageStopThreshold: Float
    let repetitionCheckStartSession: Int
    let repetitionSimilarityThreshold: Float
    let repetitionForceTerminationThreshold: Float
    let repetitionForceTerminationCount: Int
    let repetitionRequiresConsecutive: Bool
    let minSessionsBeforeRepetitionStop: Int
    let maxConfidence: Float

    func evidenceCoverageTarget(for subQuestionCount: Int) -> Float {
        subQuestionCount >= 4 ? evidenceCoverageExpanded : evidenceCoverageDefault
    }

    func noveltyExhausted(
        lowNoveltyStreak: Int,
        saturationStreak: Int,
        sourceCoverage: Float
    ) -> Bool {
        lowNoveltyStreak >= noveltyExhaustionStreakThreshold
            || saturationStreak >= saturationStreakThreshold
            || sourceCoverage >= sourceCoverageStopThreshold
    }

    func shouldTreatAsSaturated(
        saturationScore: Float,
        noveltyScore: Float,
        newlyAnsweredSubQuestions: Int
    ) -> Bool {
        saturationScore > saturationScoreThreshold
            && noveltyScore < lowNoveltyThreshold
            && newlyAnsweredSubQuestions == 0
    }
}

enum AgenticPolicyService {
    static func retrievalQuality(
        chunks: [RetrievedChunk],
        config: AgenticConfig
    ) -> AgenticRetrievalQuality {
        guard !chunks.isEmpty else { return .low }

        let topScore = chunks.first?.similarityScore ?? 0
        let topThreeAverage = chunks.prefix(3).map { $0.similarityScore }.reduce(0, +) / Float(min(3, chunks.count))
        let topFiveAverage = chunks.prefix(5).map { $0.similarityScore }.reduce(0, +) / Float(min(5, chunks.count))

        let excellentTop = min(0.65, max(config.escalationThreshold + 0.10, 0.45))
        let excellentAverage = max(0.35, excellentTop - 0.10)
        let goodTop = max(0.30, config.escalationThreshold - 0.05)
        let goodAverage = max(0.22, goodTop - 0.08)
        let moderateTop = max(0.15, min(goodTop - 0.10, config.escalationThreshold * 0.5))
        let moderateAverage = max(0.12, moderateTop - 0.03)

        if topScore > excellentTop, topThreeAverage > excellentAverage {
            return .excellent
        }
        if topScore > goodTop, topThreeAverage > goodAverage {
            return .good
        }
        if topScore > moderateTop || topFiveAverage > moderateAverage {
            return .moderate
        }
        return .low
    }

    static func downgradedForSemanticMismatch(_ quality: AgenticRetrievalQuality) -> AgenticRetrievalQuality {
        switch quality {
        case .excellent, .good:
            return .moderate
        case .moderate, .low:
            return quality
        }
    }

    static func speculativeAcceptanceThreshold(
        config: AgenticConfig,
        requiresExhaustiveAnswer: Bool
    ) -> Float {
        let base = max(config.confidenceThreshold - 0.10, 0.75)
        return requiresExhaustiveAnswer ? max(base, 0.90) : base
    }

    static func hardIrrelevanceLexicalThreshold() -> Float {
        0.10
    }

    static func moderateReturnConfidence(for quality: AgenticRetrievalQuality) -> Float {
        max(quality.confidenceScore, 0.55)
    }

    static func blendVerifiedFinalConfidence(
        sessionConfidence: Float,
        verificationConfidence: Float,
        addressesQuestion: Bool
    ) -> Float {
        if addressesQuestion {
            return sessionConfidence * 0.7 + verificationConfidence * 0.3
        }
        if verificationConfidence >= 0.5 {
            return (sessionConfidence + verificationConfidence) / 2
        }
        return min(sessionConfidence * 0.6, 0.5)
    }

    static func addressesQuestion(for answerRelevance: Float) -> Bool {
        answerRelevance >= 0.35
    }

    /// Whether the answer claims its own sources do not cover the question.
    ///
    /// Deliberately narrow, and the narrowness is the design. A sentence must contain
    /// **both** a reference to the corpus and an absence phrase before it counts, so
    /// "the study found no evidence of an effect" — a finding reported *by* a document —
    /// is not mistaken for "the documents contain no evidence", which is a claim *about*
    /// the documents. A false positive here costs a needless retry, so the bar is high.
    ///
    /// No model call. The row this implements observed the shape directly: an answer that
    /// asserted the corpus held no evidence on the question **while citing twenty sources
    /// from that corpus**, containing a section headed "Dopamine Dynamics During Social
    /// Stress" that presented evidence and then concluded none existed, and within a single
    /// sentence stating signalling "can include signaling in social interaction, there is
    /// no detailed evidence of such effects". The gate accepted it at 88% confidence.
    static func assertsAbsenceOfEvidence(in answer: String) -> Bool {
        let corpusTerms = [
            "document", "source", "context", "provided", "retrieved",
            "corpus", "library", "excerpt", "passage", "material"
        ]
        let absenceTerms = [
            "no evidence", "no detailed evidence", "no information", "no specific information",
            "no mention", "no details", "no data",
            "does not contain", "do not contain", "does not mention", "do not mention",
            "does not provide", "do not provide", "does not include", "do not include",
            "does not address", "do not address", "does not discuss", "do not discuss",
            "not covered", "not available", "not present", "cannot be determined"
        ]

        return answer.lowercased()
            .split(whereSeparator: { ".!?\n".contains($0) })
            .contains { sentence in
                corpusTerms.contains(where: { sentence.contains($0) })
                    && absenceTerms.contains(where: { sentence.contains($0) })
            }
    }

    static func verificationAction(
        addressesQuestion: Bool,
        groundingScore: Float,
        totalCitations: Int,
        calibratedConfidence: Float,
        assertsAbsenceOfEvidence: Bool = false
    ) -> String {
        if !addressesQuestion {
            return "retry"
        }

        // An answer that asserts its sources do not cover the question, while carrying
        // citations to those sources, contradicts itself. Nothing else in this gate can
        // see that: `citations=1/1` is a perfect score and means only that the markers
        // resolve to real chunks, not that the answer agrees with them or with itself.
        // That is how a self-contradicting answer was certified at 88% confidence on
        // 2026-08-17 — the check meant to catch a wrong answer instead endorsed it.
        //
        // `retry` rather than a new action on purpose: it is the response this gate
        // already uses for a grounding failure, so the downstream handling is exercised
        // rather than novel. The detector is deliberately conservative for the same
        // reason — a false positive here spends a retry for nothing.
        if assertsAbsenceOfEvidence && totalCitations > 0 {
            return "retry"
        }
        // Raised from 0.3 on 2026-08-19. At 0.3, seven of every ten citations could fail to check
        // out and the answer still shipped. A device capture logged
        // `accept (relevance=54%, citations=2/4, confidence=67%)` — half the citations ungrounded,
        // nowhere near the old bar. For an app whose premise is that answers are grounded in the
        // user's own documents, "most citations are wrong" should not be an accepted outcome.
        //
        // This is a judgement call and it trades latency for correctness: more answers will now
        // retry. If retries prove expensive the right response is to fix grounding, not to lower
        // this number back.
        // A strict majority of citations must check out. `< 0.5` was not enough: the device
        // capture scored exactly 2/4, and 0.5 is not less than 0.5, so the very case this was
        // raised for would still have been accepted. Caught by the test below before shipping.
        if groundingScore <= 0.5 && totalCitations > 0 {
            return "retry"
        }
        if calibratedConfidence < 0.5 {
            return "escalate"
        }
        return "accept"
    }

    static func calibrateSelfRAGConfidence(
        answerRelevance: Float,
        citationScore: Float,
        answerLength: Int,
        sourceCount: Int
    ) -> Float {
        // Confidence is relevance and grounding. Nothing else.
        //
        // There was a third `completeness` term worth 0.30, computed from answer length and source
        // count. Both saturated — length at 500 characters, sources at 5 — so for any real answer
        // it returned 1.0 and simply handed over its full weight. Combined with the floor, that
        // meant a completely ungrounded and completely irrelevant answer reported 30% confidence.
        //
        // Removing only the length half was not enough, because source count saturates the same
        // way; the first attempt at this fix still produced exactly 0.30 and the test caught it.
        // Neither term measures whether the answer is right. Retrieving twelve chunks and writing
        // five paragraphs is not evidence of correctness, and a confidence score that cannot fall
        // to zero cannot report failure.
        let relevanceWeight: Float = 0.50
        let citationWeight: Float = 0.50

        // Completeness deliberately no longer counts answer length.
        //
        // `lengthScore` saturated at 500 characters, so every real answer scored 1.0 on it and the
        // term discriminated nothing — it simply handed out its share of the weight. Worse, the two
        // saturating terms together made `completeness` a near-constant 0.30 contribution, which
        // combined with the floor below meant a completely ungrounded, completely irrelevant answer
        // still reported 30% confidence. Length is not evidence of correctness in either direction:
        // a correct answer can be one sentence and a wrong one can be five paragraphs.
        _ = sourceCount
        _ = answerLength

        let rawConfidence = (answerRelevance * relevanceWeight)
            + (citationScore * citationWeight)

        // Floor lowered from 0.30. A confidence score that cannot fall below 30% cannot express
        // failure, and an answer with zero grounding and zero relevance was reporting exactly that.
        // The floor stays non-zero only so the value reads as a score rather than an error.
        return min(0.95, max(0.05, rawConfidence))
    }

    static func reasoningPolicy(
        for reasoningConfig: ReasoningChainConfig,
        agenticConfig: AgenticConfig,
        forceConfidenceReporting: Bool = false
    ) -> AgenticReasoningPolicy {
        let isUnlimitedMode = reasoningConfig.sessionCount >= 20
        let isDeepThinkMode = reasoningConfig.sessionCount >= 4 && reasoningConfig.sessionCount <= 10 && !isUnlimitedMode
        let usesEvidenceDrivenStopping = isUnlimitedMode || isDeepThinkMode
        let shouldReportConfidence = isUnlimitedMode || isDeepThinkMode || forceConfidenceReporting
        let confidenceThreshold = agenticConfig.confidenceThreshold
        let maxSessionsForMode = isUnlimitedMode ? reasoningConfig.sessionCount : min(8, reasoningConfig.sessionCount + 4)

        return AgenticReasoningPolicy(
            isUnlimitedMode: isUnlimitedMode,
            isDeepThinkMode: isDeepThinkMode,
            usesEvidenceDrivenStopping: usesEvidenceDrivenStopping,
            shouldReportConfidence: shouldReportConfidence,
            confidenceThreshold: confidenceThreshold,
            minSessionsBeforeEarlyStop: isUnlimitedMode ? 8 : 4,
            maxSessionsForMode: maxSessionsForMode,
            initialConfidence: shouldReportConfidence ? (isUnlimitedMode ? 0.05 : 0.10) : 0,
            evidenceCoverageDefault: 0.55,
            evidenceCoverageExpanded: 0.70,
            lowNoveltyThreshold: 0.18,
            noveltyExhaustionStreakThreshold: 2,
            saturationScoreThreshold: 0.85,
            saturationStreakThreshold: 2,
            minimumSessionsBeforeConvergence: 4,
            coveragePlateauStreakThreshold: 4,
            sourceCoverageStopThreshold: 0.85,
            repetitionCheckStartSession: isUnlimitedMode ? 8 : 4,
            repetitionSimilarityThreshold: isUnlimitedMode ? 0.65 : 0.50,
            repetitionForceTerminationThreshold: isUnlimitedMode ? 0.90 : 0.75,
            repetitionForceTerminationCount: 3,
            repetitionRequiresConsecutive: isUnlimitedMode,
            minSessionsBeforeRepetitionStop: isUnlimitedMode ? 15 : 4,
            maxConfidence: min(0.99, max(isUnlimitedMode ? 0.98 : 0.95, confidenceThreshold))
        )
    }

    static func unlimitedReasoningPolicy(
        targetConfidence: Float,
        maxSessions: Int
    ) -> AgenticReasoningPolicy {
        AgenticReasoningPolicy(
            isUnlimitedMode: true,
            isDeepThinkMode: false,
            usesEvidenceDrivenStopping: true,
            shouldReportConfidence: true,
            confidenceThreshold: targetConfidence,
            minSessionsBeforeEarlyStop: 8,
            maxSessionsForMode: maxSessions,
            initialConfidence: 0.05,
            evidenceCoverageDefault: 0.55,
            evidenceCoverageExpanded: 0.70,
            lowNoveltyThreshold: 0.18,
            noveltyExhaustionStreakThreshold: 2,
            saturationScoreThreshold: 0.85,
            saturationStreakThreshold: 3,
            minimumSessionsBeforeConvergence: 6,
            coveragePlateauStreakThreshold: 6,
            sourceCoverageStopThreshold: 1.0,
            repetitionCheckStartSession: 8,
            repetitionSimilarityThreshold: 0.65,
            repetitionForceTerminationThreshold: 0.90,
            repetitionForceTerminationCount: 3,
            repetitionRequiresConsecutive: true,
            minSessionsBeforeRepetitionStop: 15,
            maxConfidence: min(0.99, max(0.98, targetConfidence))
        )
    }

    static func calculateProgressConfidence(
        allInsights: [String],
        query: String,
        sessionNum: Int,
        subQuestionConfidence: Float,
        noveltyScore: Float,
        sourceCoverage: Float,
        maxConfidence: Float,
        sessionBudget: Int = 50
    ) -> (confidence: Float, saturationScore: Float) {
        // `sessionProgress` is the dominant term (0.68 of a possible 0.99), and it
        // reaches its ceiling only when `sessionNum` reaches the session budget.
        // This was hardcoded to 50, which is right for Unlimited mode but not for
        // Deep Think, which stops at 8: log(9)/log(50) * 0.68 = 0.382, capping an
        // 8-session run at ~73% against a 90% stop threshold. Deep Think therefore
        // could never early-exit and burned all eight sessions on every query,
        // measured at ~65s of the ~99s total. Scaling the denominator to the actual
        // budget makes the threshold reachable; passing 50 reproduces the old curve
        // exactly, so Unlimited/Maximum behaviour is unchanged.
        let budget = max(2, sessionBudget)
        let sessionProgress = min(0.68, log(Float(sessionNum) + 1) / log(Float(budget) + 1) * 0.68)
        let subQuestionBonus = subQuestionConfidence * 0.18
        let sourceCoverageBonus = min(sourceCoverage, 1.0) * 0.05
        let totalChars = allInsights.joined().count
        let depthBonus = min(Float(totalChars) / 20000.0, 1.0) * 0.03
        let queryTerms = Set(query.lowercased().split(separator: " ").filter { $0.count > 3 })
        let answerText = allInsights.joined().lowercased()
        let termsFound = queryTerms.filter { answerText.contains($0) }.count
        let queryBonus = Float(termsFound) / max(1, Float(queryTerms.count)) * 0.04
        let noveltyBonus = min(0.05, max(0, noveltyScore) * 0.05)

        var saturationScore: Float = 0
        if allInsights.count > 2 {
            let recentWords = Set(allInsights.suffix(2).joined().lowercased().split(separator: " ").filter { $0.count > 4 })
            let previousWords = Set(allInsights.dropLast(2).joined().lowercased().split(separator: " ").filter { $0.count > 4 })
            let overlap = recentWords.intersection(previousWords).count
            saturationScore = Float(overlap) / max(1, Float(recentWords.count))
        }

        let saturationPenalty = saturationScore * 0.10
        let rawConfidence = sessionProgress + subQuestionBonus + sourceCoverageBonus + depthBonus + queryBonus + noveltyBonus - saturationPenalty
        let finalConfidence = min(rawConfidence, maxConfidence)
        return (max(0.05, finalConfidence), saturationScore)
    }
}
