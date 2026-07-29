import Foundation

enum ModelExecutionAttemptResult: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case skipped
    /// The attempt streamed meaningful output, then failed before finishing.
    /// The delivered answer genuinely came from this attempt's target, so a
    /// `.partial` attempt attests a `completedTarget` the way `.succeeded`
    /// does — while remaining distinguishable from a clean completion.
    /// Introduced for the partial-stream path (F-06); `.failed` alone would
    /// let a receipt claim a completed route whose only attempt failed.
    case partial
}

struct ModelExecutionAttempt: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let target: ModelExecutionTarget
    let startedAt: Date
    let finishedAt: Date
    let result: ModelExecutionAttemptResult
    let failureCode: String?

    init(
        id: UUID = UUID(),
        target: ModelExecutionTarget,
        startedAt: Date,
        finishedAt: Date = Date(),
        result: ModelExecutionAttemptResult,
        failureCode: String? = nil
    ) {
        self.id = id
        self.target = target
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.failureCode = failureCode
    }
}

struct ModelExecutionReceipt: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let planID: UUID
    let policyVersion: String
    let intendedTarget: ModelExecutionTarget
    let attempts: [ModelExecutionAttempt]
    let actualTarget: ModelExecutionTarget
    let completedTarget: ModelExecutionTarget
    let fallbackReason: ModelRouteReason?
    let pccQuotaAtPlanning: PCCQuotaState
    let verificationPassed: Bool?

    init(
        id: UUID = UUID(),
        planID: UUID,
        policyVersion: String,
        intendedTarget: ModelExecutionTarget,
        attempts: [ModelExecutionAttempt],
        actualTarget: ModelExecutionTarget,
        completedTarget: ModelExecutionTarget,
        fallbackReason: ModelRouteReason? = nil,
        pccQuotaAtPlanning: PCCQuotaState,
        verificationPassed: Bool? = nil
    ) {
        self.id = id
        self.planID = planID
        self.policyVersion = policyVersion
        self.intendedTarget = intendedTarget
        self.attempts = attempts
        self.actualTarget = actualTarget
        self.completedTarget = completedTarget
        self.fallbackReason = fallbackReason
        self.pccQuotaAtPlanning = pccQuotaAtPlanning
        self.verificationPassed = verificationPassed
    }

    var summary: String {
        if let fallbackReason {
            return "Intended \(intendedTarget.rawValue), completed \(completedTarget.rawValue) (\(fallbackReason.rawValue))"
        }
        return "Completed \(completedTarget.rawValue) as planned"
    }
}
