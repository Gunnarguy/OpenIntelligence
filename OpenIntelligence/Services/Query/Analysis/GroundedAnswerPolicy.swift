import Foundation

enum GroundedPromptMode: Sendable {
    case directExtraction
    case constrainedSynthesis
}

struct GroundedAnswerPolicy: Sendable {
    let answerIntent: AnswerIntent
    let deterministicExtraction: Bool
    let promptMode: GroundedPromptMode

    init(query: String, answerIntent: AnswerIntent) {
        self.answerIntent = answerIntent
        self.deterministicExtraction = Self.shouldUseDeterministicExtractionPath(
            query: query,
            answerIntent: answerIntent
        )
        self.promptMode = answerIntent.isExtractiveFirst ? .directExtraction : .constrainedSynthesis
    }

    func shouldRunSourceOnlyVerification(
        evidenceFirstMode: Bool,
        requiresCitations: Bool
    ) -> Bool {
        if evidenceFirstMode || requiresCitations {
            return true
        }

        switch answerIntent {
        case .lookup, .tableLookup, .compare, .investigate, .compute, .findings:
            return true
        case .procedure, .summarize:
            return false
        }
    }

    private static func shouldUseDeterministicExtractionPath(
        query: String,
        answerIntent: AnswerIntent
    ) -> Bool {
        if answerIntent == .tableLookup {
            return true
        }

        if answerIntent == .summarize || answerIntent == .compare || answerIntent == .investigate || answerIntent == .findings {
            return false
        }

        let lower = query.lowercased()
        let negativePatterns = [
            "compare", "comparison", "summarize", "summary", "explain", "why", "implications", "mechanism",
            "advantages", "disadvantages", "pros and cons"
        ]
        if negativePatterns.contains(where: { lower.contains($0) }) {
            return false
        }

        let extractionSignals = [
            "how many", "how much", "when", "what day", "what dose", "what route",
            "route of administration", "p-value", "sample size", "mg/kg", "mg/day", "mg/ml",
            "hours", "days", "weeks", "timing", "exact group", "exact endpoint", "exact assay result",
            "what time", "what was the dose", "what was the route"
        ]
        return extractionSignals.contains { lower.contains($0) }
    }
}
