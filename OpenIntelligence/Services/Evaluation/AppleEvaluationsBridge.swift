//
//  AppleEvaluationsBridge.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Bridges OpenIntelligence RAG evaluations to Apple's Evaluations framework.
/// Provides compile-time gating for compatibility.
final class AppleEvaluationsBridge: Sendable {
    
    init() {}
    
    /// Bridges an OpenIntelligence RAGEvalResult to an Apple-compatible evaluation structure.
    func bridgeResult(_ result: RAGEvalResult) -> [String: Any] {
        var payload: [String: Any] = [
            "id": result.id,
            "query": result.query,
            "latency": result.latencySeconds,
            "qualityMode": result.qualityModeUsed,
            "passed": result.answerMatch || result.abstentionCorrect,
            "metrics": [
                "retrievalRecall": result.retrievalRecall ?? 0.0,
                "citationPrecision": result.citationPrecision ?? 0.0,
                "contextOverflow": result.contextOverflow,
                "abstentionCorrect": result.abstentionCorrect
            ]
        ]
        
        #if canImport(FoundationModels)
        // Hook into Apple's official telemetry / evaluations reporting if available on device.
        if #available(macOS 15.0, iOS 18.0, *) {
            // Placeholder for Apple FoundationModels Evaluation metric reporting:
            // e.g. let metric = LanguageModelEvaluation.Metric(...)
            payload["apple_framework_compatible"] = true
        }
        #endif
        
        return payload
    }
    
    /// Export a full run of results to a dictionary structure suitable for Apple's `fm` command-line utility.
    func exportForFMCLI(metrics: RAGEvalMetrics, results: [RAGEvalResult]) -> [String: Any] {
        var casesPayload: [[String: Any]] = []
        for res in results {
            casesPayload.append(bridgeResult(res))
        }
        
        return [
            "version": "1.0",
            "framework": "Apple Foundation Models",
            "summary": [
                "total": metrics.totalCases,
                "passed": metrics.passedCases,
                "failed": metrics.failedCases,
                "passRate": metrics.passRate,
                "recall": metrics.retrievalRecallAt5,
                "precision": metrics.citationPrecision
            ],
            "cases": casesPayload
        ]
    }
}
