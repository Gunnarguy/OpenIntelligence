//
//  AutoTuneService.swift
//  OpenIntelligence
//
//  Heuristics to auto-tune RAG and generation defaults based on active model selection.
//  Simplified: only Apple Intelligence and On-Device Analysis are supported.
//

import Foundation

enum AutoTuneService {
    /// Apply heuristic defaults for the currently selected model type.
    /// Writes to UserDefaults keys used by SettingsView (@AppStorage):
    /// - llmMaxTokens
    /// - retrievalTopK
    /// - llmTemperature
    @MainActor
    static func tuneForSelection(selectedModel: LLMModelType) {
        let defaults = UserDefaults.standard

        // Baseline safe defaults
        var maxTokens = defaults.integer(forKey: "llmMaxTokens")
        if maxTokens <= 0 { maxTokens = 500 }
        var topK = defaults.integer(forKey: "retrievalTopK")
        if topK <= 0 { topK = 3 }
        var temperature = defaults.double(forKey: "llmTemperature")
        if temperature <= 0 { temperature = 0.7 }

        switch selectedModel {
        case .appleIntelligence:
            // Apple Intelligence (on-device/PCC) - balanced defaults
            // Context packing is handled by the pipeline; TTFT-driven execution.
            maxTokens = clamp(maxTokens, 400, 1200)
            topK = clamp(topK, 3, 7)
            temperature = clamp(temperature, 0.6, 0.9)

        case .onDeviceAnalysis:
            // Extractive QA: temperature unused; retrieval does the heavy lifting.
            topK = max(3, topK)
            temperature = 0.0
            maxTokens = 300 // short answers
        }

        // Persist
        defaults.set(maxTokens, forKey: "llmMaxTokens")
        defaults.set(topK, forKey: "retrievalTopK")
        defaults.set(temperature, forKey: "llmTemperature")
        Log.debug(
            "[AutoTune] Applied defaults → maxTokens=\(maxTokens), topK=\(topK), temperature=\(String(format: "%.2f", temperature)) for \(selectedModel.rawValue)",
            category: .pipeline
        )
    }

    // MARK: - Helpers

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        return min(max(v, lo), hi)
    }
}
