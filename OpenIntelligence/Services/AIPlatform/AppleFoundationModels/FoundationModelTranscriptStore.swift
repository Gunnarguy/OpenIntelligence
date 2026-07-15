//
//  FoundationModelTranscriptStore.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelTranscriptStore: Sendable {
    
    /// Estimate transcript tokens using token budget helper.
    static func estimateTranscriptTokens(_ transcript: Transcript) -> Int {
        return FoundationModelTokenBudget.estimateTranscriptTokens(transcript)
    }
    
    /// Trims a transcript to fit inside the remaining budget of the 4096 context window.
    /// Returns the trimmed transcript, or nil if the transcript was dropped entirely.
    static func trimTranscript(
        _ transcript: Transcript,
        context: String?,
        prompt: String,
        config: InferenceConfig
    ) -> Transcript? {
        guard !transcript.isEmpty else { return transcript }
        
        let contextChars = context?.count ?? 0
        let promptChars = prompt.count
        let systemChars = (config.systemPrompt ?? "").count
        // Conservative: instructions + system + prompt + context + overhead
        let contentTokens = Int(ceil(Double(contextChars + promptChars + systemChars + 200) / 1.4))
        let outputReserve = max(150, min(config.maxTokens, 300))
        let toolSchemaTokens = config.disableTools ? 0 : 1000
        let budgetForContent = contentTokens + outputReserve + toolSchemaTokens

        let contextSize = config.modelExecutionPlan?.contextBudget.contextSize
            ?? FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let maxTranscriptTokens = max(0, contextSize - budgetForContent)
        let currentTranscriptTokens = estimateTranscriptTokens(transcript)

        if currentTranscriptTokens > maxTranscriptTokens {
            // Trim oldest entries, keeping instructions (first entry) + most recent
            let allEntries = Array(transcript)
            let firstEntry = allEntries.first  // Usually instructions — always keep

            // Binary-search-style trim: keep removing oldest non-instruction entries
            var keepCount = allEntries.count
            while keepCount > 1 {
                let candidateEntries: [Transcript.Entry]
                if let first = firstEntry {
                    candidateEntries = [first] + Array(allEntries.suffix(keepCount - 1))
                } else {
                    candidateEntries = Array(allEntries.suffix(keepCount))
                }
                let candidateTranscript = Transcript(entries: candidateEntries)
                let tokens = estimateTranscriptTokens(candidateTranscript)
                if tokens <= maxTranscriptTokens {
                    let dropped = allEntries.count - candidateEntries.count
                    Log.info("[FM] Auto-trimmed transcript: \(currentTranscriptTokens)→\(tokens) tokens (dropped \(dropped) oldest entries, preserving \(contentTokens) tokens for context)", category: .llm)
                    return candidateTranscript
                }
                keepCount -= 1
            }

            // If even 1 entry is too large, drop transcript entirely
            if keepCount <= 1 {
                Log.warning("[FM] Transcript (\(currentTranscriptTokens) tokens) too large even after trimming, dropping to preserve context (\(contentTokens) tokens)", category: .llm)
                return nil
            }
        }
        
        return transcript
    }
}
#endif
