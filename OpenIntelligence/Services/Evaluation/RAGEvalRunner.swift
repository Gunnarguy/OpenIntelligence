//
//  RAGEvalRunner.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

/// Executes evaluation cases against the RAG pipeline.
final class RAGEvalRunner: Sendable {
    
    init() {}
    
    /// Run an entire dataset and compute metrics.
    ///
    /// - Parameters:
    ///   - dataset: The evaluation dataset
    ///   - ragService: The RAG service to evaluate
    ///   - progress: Optional progress handler callback
    /// - Returns: The results of each test case evaluation
    func run(
        dataset: RAGEvalDataset,
        ragService: RAGService,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [RAGEvalResult] {
        var results: [RAGEvalResult] = []
        let total = dataset.cases.count
        
        for (index, evalCase) in dataset.cases.enumerated() {
            let result = await evaluate(case: evalCase, ragService: ragService)
            results.append(result)
            progress?(index + 1, total)
        }
        
        return results
    }
    
    /// Evaluates a single test case.
    func evaluate(
        case evalCase: RAGEvalCase,
        ragService: RAGService
    ) async -> RAGEvalResult {
        let startTime = Date()
        
        let containerUUID: UUID? = evalCase.containerId.flatMap { UUID(uuidString: $0) }
        let qualityMode: RAGQualityMode? = evalCase.qualityMode.flatMap { modeStr in
            switch modeStr.lowercased() {
            case "standard": return .standard
            case "deepthink", "deep-think", "deep_think": return .deepThink
            case "maximum", "max": return .maximum
            default: return nil
            }
        }
        
        do {
            let (response, _) = try await ragService.queryWithAudit(
                evalCase.query,
                containerId: containerUUID,
                qualityModeOverride: qualityMode
            )
            
            let latency = Date().timeIntervalSince(startTime)
            
            // 1. Answer matching (case-insensitive substring check or exact match)
            let generatedAnswer = response.generatedResponse
            let expected = evalCase.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedGenerated = generatedAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedExpected = expected.lowercased()
            
            let answerMatch: Bool
            if evalCase.shouldAbstain {
                answerMatch = false
            } else {
                answerMatch = normalizedGenerated.contains(normalizedExpected) || normalizedExpected.contains(normalizedGenerated)
            }
            
            // 2. Retrieval Recall
            var recall: Double? = nil
            if let gtIds = evalCase.groundTruthChunkIds, !gtIds.isEmpty {
                let retrievedIds = response.retrievedChunks.map { $0.chunk.id.uuidString.lowercased() }
                let matched = gtIds.filter { gtId in
                    retrievedIds.contains(gtId.lowercased())
                }.count
                recall = Double(matched) / Double(gtIds.count)
            }
            
            // 3. Citation Precision
            var precision: Double? = nil
            if let expectedCits = evalCase.expectedCitations, !expectedCits.isEmpty {
                let responseText = generatedAnswer.lowercased()
                let citedCount = expectedCits.filter { cit in
                    responseText.contains(cit.lowercased())
                }.count
                precision = Double(citedCount) / Double(expectedCits.count)
            } else if response.retrievedChunks.isEmpty {
                precision = 1.0
            } else {
                precision = 1.0
            }
            
            // 4. Abstention Correctness
            let abstentionCorrect: Bool
            if evalCase.shouldAbstain {
                // Check if the response indicates it doesn't know / can't answer
                let responseLower = generatedAnswer.lowercased()
                let abstainedPhrases = [
                    "i do not know", "i don't know", "not mentioned", "not found",
                    "insufficient information", "cannot answer", "no information",
                    "abstained", "unable to answer", "don't have information"
                ]
                let didAbstain = abstainedPhrases.contains { responseLower.contains($0) }
                abstentionCorrect = didAbstain
            } else {
                abstentionCorrect = !generatedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            
            // 5. Context overflow detection
            let contextOverflow = response.qualityWarnings.contains { warning in
                let warningLower = warning.lowercased()
                return warningLower.contains("overflow") || warningLower.contains("context limit") || warningLower.contains("truncated")
            }
            
            // 6. Visual evidence used
            var usedVisualEvidence: Bool? = nil
            if evalCase.category == .visualEvidence {
                usedVisualEvidence = response.retrievedChunks.contains { chunk in
                    chunk.chunk.metadata.imageExtractedText != nil || chunk.chunk.metadata.imageContentType != nil
                }
            }
            
            return RAGEvalResult(
                id: evalCase.id,
                query: evalCase.query,
                generatedResponse: generatedAnswer,
                answerMatch: answerMatch,
                retrievalRecall: recall,
                citationPrecision: precision,
                abstentionCorrect: abstentionCorrect,
                latencySeconds: latency,
                tokensGenerated: response.metadata.tokensGenerated,
                qualityModeUsed: response.metadata.qualityModeName ?? qualityMode?.displayName ?? "Standard",
                contextOverflow: contextOverflow,
                usedVisualEvidence: usedVisualEvidence,
                warnings: response.qualityWarnings,
                timestamp: Date()
            )
            
        } catch {
            let latency = Date().timeIntervalSince(startTime)
            return RAGEvalResult(
                id: evalCase.id,
                query: evalCase.query,
                generatedResponse: "Error: \(error.localizedDescription)",
                answerMatch: false,
                retrievalRecall: 0.0,
                citationPrecision: 0.0,
                abstentionCorrect: evalCase.shouldAbstain, // If we failed, did we correctly abstain? Let's say false unless expected.
                latencySeconds: latency,
                tokensGenerated: 0,
                qualityModeUsed: qualityMode?.displayName ?? "Standard",
                contextOverflow: false,
                usedVisualEvidence: false,
                warnings: ["Evaluation execution failed: \(error.localizedDescription)"],
                timestamp: Date()
            )
        }
    }
}
