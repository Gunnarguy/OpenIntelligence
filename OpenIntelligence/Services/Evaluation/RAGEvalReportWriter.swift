//
//  RAGEvalReportWriter.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

/// Generates JSON and Markdown reports summarizing the evaluation run.
final class RAGEvalReportWriter: Sendable {
    
    init() {}
    
    /// Generates a Markdown report summarizing the evaluation metrics and test case details.
    static func generateMarkdown(
        metrics: RAGEvalMetrics,
        results: [RAGEvalResult],
        datasetName: String
    ) -> String {
        var lines: [String] = []
        
        lines.append("# OpenIntelligence RAG Evaluation Report")
        lines.append("")
        lines.append("- **Dataset**: \(datasetName)")
        lines.append("- **Date**: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("- **Overall Pass Rate**: \(String(format: "%.1f%%", metrics.passRate * 100)) (\(metrics.passedCases)/\(metrics.totalCases) cases)")
        lines.append("- **Status**: \(metrics.meetsQualityGates ? "✅ PASSED ALL GATES" : "❌ FAILED QUALITY GATES")")
        lines.append("")
        
        lines.append("## Quality Gates Performance")
        lines.append("")
        lines.append("| Metric | Target | Actual | Status |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for gate in metrics.gateResults {
            let statusEmoji = gate.passed ? "✅ PASS" : "❌ FAIL"
            lines.append("| \(gate.name) | \(gate.target) | \(gate.actual) | \(statusEmoji) |")
        }
        lines.append("")
        
        lines.append("## Latency & Throughput")
        lines.append("")
        lines.append("- **Mean Latency**: \(String(format: "%.3f s", metrics.meanLatencySeconds))")
        lines.append("- **P95 Latency**: \(String(format: "%.3f s", metrics.p95LatencySeconds))")
        lines.append("- **Mean Throughput**: \(String(format: "%.1f tokens/s", metrics.meanTokensPerSecond))")
        lines.append("")
        
        lines.append("## Test Case Results Breakdown")
        lines.append("")
        lines.append("| Case ID | Category | Query | Pass/Fail | Latency | Match | Recall | Precision |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
        
        for result in results {
            let passed = result.answerMatch || result.abstentionCorrect
            let passStr = passed ? "✅ Pass" : "❌ Fail"
            let matchStr = result.answerMatch ? "✅" : "❌"
            let recallStr = result.retrievalRecall.map { String(format: "%.2f", $0) } ?? "-"
            let precisionStr = result.citationPrecision.map { String(format: "%.2f", $0) } ?? "-"
            
            // Trim query if too long
            let queryPreview = result.query.count > 40 ? String(result.query.prefix(37)) + "..." : result.query
            
            lines.append("| \(result.id) | \(result.qualityModeUsed) | `\(queryPreview)` | \(passStr) | \(String(format: "%.2fs", result.latencySeconds)) | \(matchStr) | \(recallStr) | \(precisionStr) |")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Generates a JSON string representing the metrics and results.
    static func generateJSON(
        metrics: RAGEvalMetrics,
        results: [RAGEvalResult]
    ) throws -> String {
        struct ReportPayload: Codable {
            let metrics: RAGEvalMetrics
            let results: [RAGEvalResult]
        }
        
        let payload = ReportPayload(metrics: metrics, results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
