//
//  FoundationModelSessionFactory.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 16.0, *)
struct FoundationModelSessionFactory {
    
    struct SessionResult {
        let session: LanguageModelSession
        let currentSystemPrompt: String?
        let pendingTranscriptConsumed: Bool
    }
    
    @MainActor
    static func createSession(
        model: SystemLanguageModel,
        toolHandler: RAGToolHandler?,
        systemPrompt: String?,
        disableTools: Bool,
        pendingTranscript: Transcript?
    ) throws -> SessionResult {
        // Check availability with detailed diagnostics BEFORE creating session
        switch model.availability {
        case .available:
            Log.debug("Foundation Models available - creating session...", category: .llm)

            // Initialize function calling tools for agentic RAG using our ToolRegistry
            let tools = disableTools ? [] : FoundationModelToolRegistry.createTools(toolHandler: toolHandler)

            // Session instructions — context-aware to avoid wasting tokens on tool guidance
            let instructionsText = FoundationModelPromptCompiler.compileInstructions(
                systemPrompt: systemPrompt,
                disableTools: disableTools
            )

            let finalSession: LanguageModelSession
            var transcriptConsumed = false

            // Check if we have a pending transcript to restore
            if let savedTranscript = pendingTranscript, !disableTools {
                finalSession = LanguageModelSession(
                    model: model,
                    tools: tools,
                    transcript: savedTranscript
                )

                // Prewarm to reduce latency on next query
                finalSession.prewarm()
                transcriptConsumed = true
                
                Log.info(
                    "Apple Foundation Model session restored from transcript (\(savedTranscript.count) entries)",
                    category: .llm
                )
            } else {
                // Fresh session - either no transcript or tools disabled (pure reasoning mode)
                finalSession = LanguageModelSession(
                    model: model,
                    tools: tools,
                    instructions: Instructions(instructionsText)
                )
                Log.info("Apple Foundation Model session initialized\(disableTools ? " (pure reasoning)" : " (Agentic RAG)")", category: .llm)
            }

            return SessionResult(
                session: finalSession,
                currentSystemPrompt: systemPrompt,
                pendingTranscriptConsumed: transcriptConsumed
            )

        case let .unavailable(reason):
            let reasonStr: String
            switch reason {
            case .deviceNotEligible:
                reasonStr = "Device not eligible (requires A17 Pro+ or M-series)"
            case .appleIntelligenceNotEnabled:
                reasonStr = "Apple Intelligence not enabled"
            case .modelNotReady:
                reasonStr = "Model downloading or initializing"
            @unknown default:
                reasonStr = "Unknown reason"
            }
            Log.warning("Foundation Models unavailable: \(reasonStr)", category: .llm)
            throw LLMError.modelUnavailable
        }
    }
}
#endif
