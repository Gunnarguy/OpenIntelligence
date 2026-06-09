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
        let actualRoute: AppleFoundationModelRoute
    }
    
    @MainActor
    static func createSession(
        route: AppleFoundationModelRoute,
        toolHandler: RAGToolHandler?,
        systemPrompt: String?,
        disableTools: Bool,
        pendingTranscript: Transcript?
    ) throws -> SessionResult {
        // Initialize function calling tools for agentic RAG using our ToolRegistry
        let tools = disableTools ? [] : FoundationModelToolRegistry.createTools(toolHandler: toolHandler)

        // Session instructions — context-aware to avoid wasting tokens on tool guidance
        let instructionsText = FoundationModelPromptCompiler.compileInstructions(
            systemPrompt: systemPrompt,
            disableTools: disableTools
        )

        let finalSession: LanguageModelSession
        var transcriptConsumed = false
        var selectedRoute = route
        
        switch route {
        case .onDevice:
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { throw LLMError.modelUnavailable }
            if let savedTranscript = pendingTranscript, !disableTools {
                finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                finalSession.prewarm()
                transcriptConsumed = true
            } else {
                finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
            }
        case .privateCloudCompute(_):
            let model = PrivateCloudComputeLanguageModel()
            guard model.isAvailable else { throw LLMError.modelUnavailable }
            if let savedTranscript = pendingTranscript, !disableTools {
                finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                finalSession.prewarm()
                transcriptConsumed = true
            } else {
                finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
            }
        case .automatic:
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { throw LLMError.modelUnavailable }
            selectedRoute = .onDevice
            if let savedTranscript = pendingTranscript, !disableTools {
                finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                finalSession.prewarm()
                transcriptConsumed = true
            } else {
                finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
            }
        }

        return SessionResult(
            session: finalSession,
            currentSystemPrompt: systemPrompt,
            pendingTranscriptConsumed: transcriptConsumed,
            actualRoute: selectedRoute
        )
    }
}
#endif
