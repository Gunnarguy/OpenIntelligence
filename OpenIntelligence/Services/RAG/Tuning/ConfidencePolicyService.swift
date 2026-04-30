//
//  ConfidencePolicyService.swift
//  OpenIntelligence
//
//  Centralized verification and calibration policy so answer acceptance,
//  abstention, and safety gating use one per-query decision model.
//

import Foundation

struct QueryConfidencePolicy: Sendable {
    let isTouchyQuery: Bool
    let verificationConfig: VerificationConfig
    let verificationPassThreshold: Float
    let calibrationParameters: CalibrationParameters
    let calibrationAbstentionThreshold: Float
    let calibrationTouchyThreshold: Float
}

enum ConfidencePolicyService {
    static func policy(
        for query: String,
        answerIntent: AnswerIntent,
        qualityMode: RAGQualityMode
    ) -> QueryConfidencePolicy {
        let isTouchy = detectTouchyQuery(query)
        let strictnessLift: Float
        switch qualityMode.canonical {
        case .standard:
            strictnessLift = 0.0
        case .deepThink:
            strictnessLift = 0.05
        case .maximum:
            strictnessLift = 0.10
        default:
            strictnessLift = 0.0
        }

        let baseVerification = VerificationConfig.default
        let verificationConfig = VerificationConfig(
            tauNormal: min(0.60, baseVerification.tauNormal + strictnessLift),
            tauTouchy: min(0.75, baseVerification.tauTouchy + strictnessLift),
            muMargin: min(0.10, baseVerification.muMargin + strictnessLift * 0.5),
            semanticGroundingThreshold: min(0.60, baseVerification.semanticGroundingThreshold + strictnessLift * 0.5),
            touchyCategories: baseVerification.touchyCategories
        )

        let verificationPassThreshold: Float = {
            let modeThreshold = qualityMode.verificationConfidenceThreshold
            if answerIntent.isExtractiveFirst {
                return max(0.25, modeThreshold * 0.5)
            }
            return modeThreshold
        }()

        let calibrationParameters: CalibrationParameters = {
            switch qualityMode.canonical {
            case .standard:
                return .default
            case .deepThink, .maximum:
                return .conservative
            default:
                return .default
            }
        }()

        var abstentionThreshold: Float
        switch qualityMode.canonical {
        case .standard:
            abstentionThreshold = 0.35
        case .deepThink:
            abstentionThreshold = 0.45
        case .maximum:
            abstentionThreshold = 0.55
        default:
            abstentionThreshold = 0.35
        }

        if answerIntent.isExtractiveFirst {
            abstentionThreshold = max(0.25, abstentionThreshold - 0.05)
        }

        let touchyThreshold = min(0.80, max(abstentionThreshold + 0.15, verificationPassThreshold))

        return QueryConfidencePolicy(
            isTouchyQuery: isTouchy,
            verificationConfig: verificationConfig,
            verificationPassThreshold: verificationPassThreshold,
            calibrationParameters: calibrationParameters,
            calibrationAbstentionThreshold: abstentionThreshold,
            calibrationTouchyThreshold: touchyThreshold
        )
    }

    static func detectTouchyQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        let touchyTerms = VerificationConfig.default.touchyCategories.union([
            "warning",
            "danger",
            "hazard",
            "emergency",
            "injury",
            "shock",
            "temperature",
            "pressure",
            "maximum",
            "minimum",
            "limit",
            "critical",
            "fault",
            "failure",
        ])

        return touchyTerms.contains { lower.contains($0) }
    }
}
