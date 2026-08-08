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

    /// Roll the per-case stage metrics up into one aggregate per pipeline stage.
    ///
    /// Cases with no stage metrics are skipped rather than counted as zero, so abstention cases
    /// and failed runs cannot drag a stage's recall down without ever having been retrieved for.
    static func aggregateStageMetrics(_ results: [RAGEvalResult]) -> [AggregateStageMetrics] {
        RetrievalStageEvaluator.aggregate(perQuery: results.compactMap(\.stageMetrics))
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
        
        // One collector per case. Reusing one across cases would interleave their stages with no
        // way to separate them afterwards, which is the attribution loss the type exists to
        // prevent.
        let trace = RetrievalTraceCollector()

        do {
            let (response, _) = try await ragService.queryWithAudit(
                evalCase.query,
                containerId: containerUUID,
                qualityModeOverride: qualityMode,
                trace: trace
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
            //
            // This previously scored only when `groundTruthChunkIds` was non-empty, matching those
            // against `chunk.id.uuidString`. Every case in the committed `rag_eval_v1.jsonl` carries
            // `groundTruthChunkIds: null` and holds ground truth in `expectedCitations` as a
            // filename, so recall was `nil` for every case, `RAGEvalMetrics.compute` compactMapped
            // an empty array, and `retrievalRecallAt5` reported exactly 0.0 on every run regardless
            // of retrieval quality. The `>= 0.85` gate could never pass.
            //
            // Chunk IDs are still honoured when a case supplies them, since they are the more
            // precise ground truth. Filenames are the documented fallback, matched through
            // `RetrievalRelevanceJudge` so normalisation matches the per-stage metrics.
            var recall: Double? = nil
            if let gtIds = evalCase.groundTruthChunkIds, !gtIds.isEmpty {
                let retrievedIds = response.retrievedChunks.map { $0.chunk.id.uuidString.lowercased() }
                let matched = gtIds.filter { gtId in
                    retrievedIds.contains(gtId.lowercased())
                }.count
                recall = Double(matched) / Double(gtIds.count)
            } else if let expectedSources = evalCase.expectedCitations, !expectedSources.isEmpty {
                let matched = expectedSources.filter { expected in
                    response.retrievedChunks.contains { chunk in
                        RetrievalRelevanceJudge.matches(chunk, expected: expected)
                    }
                }.count
                recall = Double(matched) / Double(expectedSources.count)
            }

            // 3. Citation Precision
            //
            // Precision is "of the sources this answer rests on, how many are the right ones".
            // This previously asked whether the generated *prose* literally contained the string
            // `vehicle_specs.md`, which measures whether the model typed a filename rather than
            // whether it used the right source, and then returned a hardcoded 1.0 in both remaining
            // branches, so it could essentially never report a failure.
            //
            // Now computed over the distinct source documents actually retrieved. Cases with no
            // expected citations, which are the abstention cases, are left unscored rather than
            // awarded 1.0, so they neither inflate nor deflate the aggregate.
            var precision: Double? = nil
            if let expectedSources = evalCase.expectedCitations, !expectedSources.isEmpty {
                let distinctSources = Set(
                    response.retrievedChunks
                        .map { RetrievalRelevanceJudge.normalize($0.sourceDocument) }
                        .filter { !$0.isEmpty }
                )

                if distinctSources.isEmpty {
                    // Retrieval returned nothing usable. That is a miss, not a perfect score.
                    precision = 0.0
                } else {
                    let correct = Set(
                        response.retrievedChunks
                            .filter { chunk in
                                expectedSources.contains { RetrievalRelevanceJudge.matches(chunk, expected: $0) }
                            }
                            .map { RetrievalRelevanceJudge.normalize($0.sourceDocument) }
                            .filter { !$0.isEmpty }
                    )
                    precision = Double(correct.count) / Double(distinctSources.count)
                }
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
            
            // 7. Per-stage retrieval metrics.
            //
            // Scored against the same expected sources recall uses, through the same
            // `RetrievalRelevanceJudge`, so a stage number and the case's recall cannot disagree
            // about what counts as relevant. Nil rather than an empty array when the case has no
            // expected sources (the abstention cases) or nothing was recorded, so an unscored case
            // is distinguishable from one that scored zero.
            let stageMetrics: [RetrievalStageMetrics]? = {
                guard let expectedSources = evalCase.expectedCitations, !expectedSources.isEmpty else { return nil }
                let traces = trace.stages(inOrder: RetrievalTraceCollector.Stage.allCases)
                guard !traces.isEmpty else { return nil }
                return RetrievalStageEvaluator.score(traces: traces, expectedSources: expectedSources)
            }()

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
                timestamp: Date(),
                stageMetrics: stageMetrics
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
