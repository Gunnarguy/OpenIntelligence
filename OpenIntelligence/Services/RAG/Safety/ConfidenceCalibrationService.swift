//
//  ConfidenceCalibrationService.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Confidence calibration per AppleRAG spec §7:
//  P(correct) = σ(α*s_max + β*m + γ*log(1+n_evidence) - δ)
//
//  Where:
//  - s_max = top rerank score
//  - m = margin between top and second score
//  - n_evidence = number of evidence chunks used
//  - α, β, γ, δ = learned parameters (initialized to sensible defaults)
//
//  This provides calibrated probabilities for answer correctness,
//  enabling principled abstention decisions.
//

import Foundation

// MARK: - Calibration Parameters

/// Parameters for confidence calibration formula
/// Tuned from empirical testing on RAG answers
struct CalibrationParameters: Codable, Sendable {
    /// Weight for top rerank score
    let alpha: Float

    /// Weight for score margin (top vs second)
    let beta: Float

    /// Weight for log(1 + n_evidence)
    let gamma: Float

    /// Bias term (subtracted)
    let delta: Float

    /// Platt scaling parameter A (slope coefficient)
    let plattA: Float

    /// Platt scaling parameter B (intercept/bias)
    let plattB: Float

    /// Default parameters (empirically tuned)
    static let `default` = CalibrationParameters(
        alpha: 2.0,    // Strong weight on top score
        beta: 1.5,     // Medium weight on margin
        gamma: 0.5,    // Moderate boost for more evidence
        delta: 1.2,    // Bias to avoid overconfidence
        plattA: -2.5,  // Slope
        plattB: 1.25   // Intercept
    )

    /// Conservative parameters (lower confidence)
    static let conservative = CalibrationParameters(
        alpha: 1.5,
        beta: 1.0,
        gamma: 0.3,
        delta: 1.5,
        plattA: -3.0,
        plattB: 1.5
    )

    /// Aggressive parameters (higher confidence)
    static let aggressive = CalibrationParameters(
        alpha: 2.5,
        beta: 2.0,
        gamma: 0.7,
        delta: 0.8,
        plattA: -2.0,
        plattB: 1.0
    )
}

// MARK: - Calibrated Confidence

/// Result of confidence calibration
struct CalibratedConfidence: Sendable {
    /// Raw probability P(correct) from sigmoid
    let probability: Float

    /// Bucketed confidence level for display
    let level: ConfidenceLevel

    /// Whether answer should be abstained
    let shouldAbstain: Bool

    /// Components that contributed to the score
    let components: ConfidenceComponents

    enum ConfidenceLevel: String, Sendable {
        case veryHigh = "very_high"   // > 0.85
        case high = "high"            // 0.70-0.85
        case medium = "medium"        // 0.50-0.70
        case low = "low"              // 0.35-0.50
        case veryLow = "very_low"     // < 0.35

        var displayText: String {
            switch self {
            case .veryHigh: "Very High Confidence"
            case .high: "High Confidence"
            case .medium: "Medium Confidence"
            case .low: "Low Confidence"
            case .veryLow: "Very Low Confidence"
            }
        }
    }

    struct ConfidenceComponents: Sendable {
        let topScore: Float
        let margin: Float
        let evidenceCount: Int
        let rawLogit: Float
    }
}

// MARK: - Confidence Calibration Service

/// Service for calibrating RAG answer confidence
/// per AppleRAG spec §7.
final class ConfidenceCalibrationService: Sendable {

    /// Calibration parameters
    private let params: CalibrationParameters

    /// Abstention threshold
    private let abstentionThreshold: Float

    /// Touchy query threshold (stricter)
    private let touchyThreshold: Float

    init(
        params: CalibrationParameters = .default,
        abstentionThreshold: Float = 0.35,
        touchyThreshold: Float = 0.55
    ) {
        self.params = params
        self.abstentionThreshold = abstentionThreshold
        self.touchyThreshold = touchyThreshold
    }

    // MARK: - Calibration

    /// Calculate calibrated confidence for an answer
    ///
    /// Implements: P(correct) = σ(α*s_max + β*m + γ*log(1+n_evidence) - δ)
    ///
    /// - Parameters:
    ///   - topScore: Highest rerank/similarity score
    ///   - secondScore: Second-highest score (for margin calculation)
    ///   - evidenceCount: Number of evidence chunks used
    ///   - isTouchyQuery: Whether query is safety-critical
    /// - Returns: Calibrated confidence with abstention recommendation
    func calibrate(
        topScore: Float,
        secondScore: Float,
        evidenceCount: Int,
        isTouchyQuery: Bool = false
    ) -> CalibratedConfidence {
        // Calculate margin
        let margin = max(0, topScore - secondScore)

        // Calculate log term
        let logEvidence = log(1 + Float(evidenceCount))

        // Calculate raw logit
        let logit = params.alpha * topScore +
                    params.beta * margin +
                    params.gamma * logEvidence -
                    params.delta

        // Apply sigmoid
        let rawProbability = sigmoid(logit)
        
        // Apply Platt Scaling Calibration: P(y=1|x) = 1 / (1 + exp(A*x + B))
        let probability = plattScale(rawProbability)

        // Determine confidence level
        let level = confidenceLevel(from: probability)

        // Determine abstention
        let threshold = isTouchyQuery ? touchyThreshold : abstentionThreshold
        let shouldAbstain = probability < threshold

        return CalibratedConfidence(
            probability: probability,
            level: level,
            shouldAbstain: shouldAbstain,
            components: CalibratedConfidence.ConfidenceComponents(
                topScore: topScore,
                margin: margin,
                evidenceCount: evidenceCount,
                rawLogit: logit
            )
        )
    }

    /// Calibrate from retrieved chunks
    func calibrate(
        chunks: [RetrievedChunk],
        isTouchyQuery: Bool = false
    ) -> CalibratedConfidence {
        guard !chunks.isEmpty else {
            return CalibratedConfidence(
                probability: 0,
                level: .veryLow,
                shouldAbstain: true,
                components: CalibratedConfidence.ConfidenceComponents(
                    topScore: 0,
                    margin: 0,
                    evidenceCount: 0,
                    rawLogit: -params.delta
                )
            )
        }

        // Get scores (use similarityScore from RetrievedChunk)
        let scores = chunks.map { $0.similarityScore }
        let sortedScores = scores.sorted(by: >)

        let topScore = sortedScores[0]
        let secondScore = sortedScores.count > 1 ? sortedScores[1] : 0

        return calibrate(
            topScore: topScore,
            secondScore: secondScore,
            evidenceCount: chunks.count,
            isTouchyQuery: isTouchyQuery
        )
    }

    /// Calibrate with verification gate results
    func calibrate(
        chunks: [RetrievedChunk],
        verification: RAGVerificationResult?,
        isTouchyQuery: Bool = false
    ) -> CalibratedConfidence {
        var baseCalibration = calibrate(chunks: chunks, isTouchyQuery: isTouchyQuery)

        // Apply penalty for failed gates
        if let verification = verification, !verification.passed {
            let failedCount = verification.gateResults.filter { !$0.passed }.count
            let penalty = Float(failedCount) * 0.15  // 15% penalty per failed gate

            let adjustedProbability = max(0, baseCalibration.probability - penalty)
            let adjustedLevel = confidenceLevel(from: adjustedProbability)
            let threshold = isTouchyQuery ? touchyThreshold : abstentionThreshold

            baseCalibration = CalibratedConfidence(
                probability: adjustedProbability,
                level: adjustedLevel,
                shouldAbstain: adjustedProbability < threshold,
                components: baseCalibration.components
            )
        }

        return baseCalibration
    }

    // MARK: - Helpers

    /// Sigmoid function
    private func sigmoid(_ x: Float) -> Float {
        1 / (1 + exp(-x))
    }

    /// Platt scaling sigmoid calibration: P(y=1|x) = 1 / (1 + exp(A*x + B))
    private func plattScale(_ x: Float) -> Float {
        let exponent = params.plattA * x + params.plattB
        return 1.0 / (1.0 + exp(exponent))
    }

    /// Map probability to confidence level
    private func confidenceLevel(from probability: Float) -> CalibratedConfidence.ConfidenceLevel {
        switch probability {
        case 0.85...: return .veryHigh
        case 0.70..<0.85: return .high
        case 0.50..<0.70: return .medium
        case 0.35..<0.50: return .low
        default: return .veryLow
        }
    }
}

// MARK: - Batch Calibration

extension ConfidenceCalibrationService {
    /// Calibrate multiple answer candidates and rank by confidence
    func rankByConfidence(
        candidates: [(chunks: [RetrievedChunk], answer: String)],
        isTouchyQuery: Bool = false
    ) -> [(answer: String, confidence: CalibratedConfidence)] {
        candidates
            .map { candidate in
                let confidence = calibrate(chunks: candidate.chunks, isTouchyQuery: isTouchyQuery)
                return (answer: candidate.answer, confidence: confidence)
            }
            .sorted { $0.confidence.probability > $1.confidence.probability }
    }
}
