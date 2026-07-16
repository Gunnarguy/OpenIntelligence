import Foundation

protocol ModelExecutionPlanning: Sendable {
    func makePlan(
        constraints: PreRetrievalConstraints,
        evidence: PostRetrievalEvidence,
        localBudget: ContextBudgetSnapshot,
        pccBudget: ContextBudgetSnapshot?,
        capability: FoundationModelCapabilitySnapshot
    ) -> ModelExecutionPlan
}

protocol CloudEvidenceMinimizing: Sendable {
    func makeEnvelope(
        plan: ModelExecutionPlan,
        query: String,
        chunks: [RetrievedChunk],
        maximumCharacters: Int
    ) -> CloudEvidenceEnvelope
}

struct ModelExecutionPlanner: ModelExecutionPlanning {
    func makePlan(
        constraints: PreRetrievalConstraints,
        evidence: PostRetrievalEvidence,
        localBudget: ContextBudgetSnapshot,
        pccBudget: ContextBudgetSnapshot?,
        capability: FoundationModelCapabilitySnapshot
    ) -> ModelExecutionPlan {
        let target: ModelExecutionTarget
        let reason: ModelRouteReason
        let privacy: ModelPrivacyBoundary

        if !evidence.isSufficient {
            target = .abstain
            reason = .insufficientEvidence
            privacy = .pccProhibited
        } else if constraints.requiresOnDevice {
            target = .onDevice
            reason = .userRequiredLocal
            privacy = .localOnly
        } else if constraints.requiresPCC {
            if !constraints.allowsPCC {
                target = .onDevice
                reason = .privacyRequiredLocal
                privacy = .localOnly
            } else if capability.canUsePCC
                        && constraints.networkAvailable
                        && (constraints.isForegroundInteractive || constraints.consentGranted) {
                target = .privateCloudCompute
                reason = .userRequiredCloud
                privacy = .pccEligibleAfterConsent
            } else {
                target = .onDevice
                if capability.pccQuota == .limitReached {
                    reason = .pccQuotaReached
                } else if !constraints.networkAvailable {
                    reason = .networkUnavailable
                } else if !constraints.isForegroundInteractive && !constraints.consentGranted {
                    reason = .consentUnavailable
                } else {
                    reason = .pccUnavailable
                }
                privacy = .localOnly
            }
        } else if evidence.requiresExactExtraction && !evidence.hasContradictions {
            target = .deterministic
            reason = .exactAnswerAvailable
            privacy = .localOnly
        } else if !constraints.allowsPCC {
            target = .onDevice
            reason = .privacyRequiredLocal
            privacy = .localOnly
        } else {
            let pccFits = pccBudget?.fits == true
            let complexityRequestsPCC = evidence.requiresMultiDocumentSynthesis
                && constraints.qualityMode != "Standard"
            let shouldUsePCC = capability.canUsePCC
                && constraints.networkAvailable
                && (constraints.isForegroundInteractive || constraints.consentGranted)
                && pccFits
                && (!localBudget.fits || complexityRequestsPCC)

            if shouldUsePCC {
                target = .privateCloudCompute
                reason = localBudget.fits ? .complexSynthesis : .localContextExceeded
                privacy = .pccEligibleAfterConsent
            } else {
                target = .onDevice
                if capability.pccQuota == .limitReached {
                    reason = .pccQuotaReached
                } else if !constraints.networkAvailable {
                    reason = .networkUnavailable
                } else if !capability.canUsePCC {
                    reason = .pccUnavailable
                } else {
                    reason = .localContextFits
                }
                privacy = .localOnly
            }
        }

        let fallbackTarget: ModelExecutionTarget?
        if target == .privateCloudCompute {
            fallbackTarget = .onDevice
        } else {
            fallbackTarget = nil
        }

        return ModelExecutionPlan(
            constraints: constraints,
            evidence: evidence,
            privacyBoundary: privacy,
            stages: [
                ModelExecutionStage(role: .retrieve, target: .deterministic, reason: .localContextFits),
                ModelExecutionStage(role: .synthesize, target: target, reason: reason),
                ModelExecutionStage(role: .verify, target: .deterministic, reason: .localContextFits),
            ],
            fallback: ModelFallbackPlan(
                target: fallbackTarget,
                reason: .fallback,
                mayRetryPCC: false
            ),
            verification: ModelVerificationPlan(
                verifyCitations: true,
                verifyEvidenceCoverage: true,
                maximumRepairAttempts: 1
            ),
            contextBudget: target == .privateCloudCompute ? (pccBudget ?? localBudget) : localBudget,
            pccQuotaAtPlanning: capability.pccQuota
        )
    }
}

struct CloudEvidenceMinimizer: CloudEvidenceMinimizing {
    func makeEnvelope(
        plan: ModelExecutionPlan,
        query: String,
        chunks: [RetrievedChunk],
        maximumCharacters: Int
    ) -> CloudEvidenceEnvelope {
        guard maximumCharacters > 0 else {
            return CloudEvidenceEnvelope(
                planID: plan.id,
                query: query,
                evidence: [],
                omittedChunkCount: chunks.count,
                characterCount: query.count
            )
        }

        var remaining = maximumCharacters
        var items: [CloudEvidenceItem] = []
        for retrieved in chunks.sorted(by: { $0.rank < $1.rank }) {
            guard remaining > 0 else { break }
            let content = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            let allowance = min(remaining, max(240, maximumCharacters / max(1, min(chunks.count, 8))))
            let text = String(content.prefix(allowance))
            items.append(CloudEvidenceItem(
                sourceID: retrieved.chunk.id.uuidString,
                documentName: retrieved.sourceDocument,
                pageNumber: retrieved.pageNumber,
                text: text
            ))
            remaining -= text.count
        }

        return CloudEvidenceEnvelope(
            planID: plan.id,
            query: query,
            evidence: items,
            omittedChunkCount: max(0, chunks.count - items.count),
            characterCount: query.count + items.reduce(0) { $0 + $1.text.count }
        )
    }
}
