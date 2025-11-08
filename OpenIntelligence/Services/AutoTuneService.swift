//
//  AutoTuneService.swift
//  OpenIntelligence
//
//  Heuristics to auto-tune RAG and generation defaults based on active model selection.
//  Phase 1: lightweight, relies on known caps and simple vendor/quant hints.
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
        case .appleIntelligence, .chatGPTExtension:
            // Apple Intelligence (on-device/PCC) - keep current balanced defaults
            // Context packing is handled by the pipeline; TTFT-driven execution.
            maxTokens = clamp(maxTokens, 400, 1200)
            topK = clamp(topK, 3, 7)
            temperature = clamp(temperature, 0.6, 0.9)

        case .openAIDirect:
            // Cloud models generally allow longer completions; allow more by default.
            maxTokens = max(1200, maxTokens)
            topK = clamp(topK, 3, 7)
            // For reasoning models (o1/gpt-5) temp is ignored by upstream; keep user default.
            temperature = clamp(temperature, 0.3, 0.9)

        case .onDeviceAnalysis:
            // Extractive QA: temperature unused; retrieval does the heavy lifting.
            topK = max(3, topK)
            temperature = 0.0
            maxTokens = 300 // short answers

        case .ggufLocal:
            // iOS GGUF - find the installed cartridge to infer hints (contextWindow, quant, vendor).
            let (ctx, quant, vendor) = ggufHintsFromRegistry()
            // Use context window if known; allocate ~60% to completion
            if let ctx = ctx, ctx > 0 {
                maxTokens = Int(Double(ctx) * 0.6)
                // Keep within practical on-device bounds
                maxTokens = clamp(maxTokens, 256, 1024)
            } else {
                // Conservative fallback for 2B–3B small models
                maxTokens = 512
            }
            // Retrieval: slightly higher for weaker models to give more signal
            topK = 5

            // Temperature caps by quant/vendor
            if let q = quant?.uppercased() {
                if q.contains("Q2") || q.contains("Q3") {
                    temperature = 0.5
                } else if q.contains("Q4") {
                    temperature = 0.6
                } else {
                    temperature = 0.7
                }
            } else {
                temperature = 0.6
            }
            // Optional vendor nuance
            if let v = vendor?.lowercased(), v.contains("qwen") {
                // Qwen smalls tend to be concise; allow slightly higher completion len
                maxTokens = min(maxTokens + 128, 1024)
            }

        case .coreMLLocal:
            let (ctx, vendor) = coreMLHintsFromRegistry()
            if let ctx = ctx, ctx > 0 {
                maxTokens = clamp(Int(Double(ctx) * 0.6), 256, max(ctx, 1024))
            } else {
                maxTokens = clamp(maxTokens, 512, 1024)
            }
            topK = 5
            temperature = clamp(temperature, 0.5, 0.7)
            if let vendor, vendor.lowercased().contains("qwen") {
                maxTokens = min(maxTokens + 128, 1280)
            }
        }

        // Persist
        defaults.set(maxTokens, forKey: "llmMaxTokens")
        defaults.set(topK, forKey: "retrievalTopK")
        defaults.set(temperature, forKey: "llmTemperature")
        print("🔧 [AutoTune] Applied defaults → maxTokens=\(maxTokens), topK=\(topK), temperature=\(String(format: "%.2f", temperature)) for \(selectedModel.rawValue)")
    }

    // MARK: - Helpers

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        return min(max(v, lo), hi)
    }

    /// Resolve the currently selected GGUF from UserDefaults and look up the registry entry.
    @MainActor
    private static func ggufHintsFromRegistry() -> (context: Int?, quant: String?, vendor: String?) {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: LlamaCPPiOSLLMService.selectedModelIdKey),
              let id = UUID(uuidString: idString),
              let model = ModelRegistry.shared.model(id: id),
              model.backend == .gguf else {
            return (nil, nil, nil)
        }
        return (model.contextWindow, model.quantization, model.vendor)
    }

    @MainActor
    private static func coreMLHintsFromRegistry() -> (context: Int?, vendor: String?) {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: CoreMLLLMService.selectedModelIdKey),
              let id = UUID(uuidString: idString),
              let model = ModelRegistry.shared.model(id: id),
              model.backend == .coreML else {
            return (nil, nil)
        }
        return (model.contextWindow, model.vendor)
    }
}
