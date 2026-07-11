//
//  FoundationModelSessionFactory.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
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
            
        case .onDeviceAdvanced:
            if #available(iOS 27.0, macOS 27.0, *) {
                // Initialize the native AFM 3 Core Advanced (20B) on-device model.
                // This runs locally on Apple Silicon without requiring Private Cloud Compute entitlements.
                let model = SystemLanguageModel.advanced
                guard case .available = model.availability else { throw LLMError.modelUnavailable }
                if let savedTranscript = pendingTranscript, !disableTools {
                    finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                    finalSession.prewarm()
                    transcriptConsumed = true
                } else {
                    finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
                }
            } else {
                // Graceful fallback to the standard model for iOS 26 users
                let model = SystemLanguageModel.default
                guard case .available = model.availability else { throw LLMError.modelUnavailable }
                selectedRoute = .onDevice // Update selected route for telemetry to reflect fallback
                if let savedTranscript = pendingTranscript, !disableTools {
                    finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                    finalSession.prewarm()
                    transcriptConsumed = true
                } else {
                    finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
                }
            }
            
        case .privateCloudCompute(_):
            #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *) {
                guard EntitlementChecker.hasEntitlement("com.apple.developer.private-cloud-compute") else {
                    throw LLMError.modelUnavailable
                }
                let nativeModel = FoundationModels.PrivateCloudComputeLanguageModel()
                guard nativeModel.isAvailable else { throw LLMError.modelUnavailable }
                if let savedTranscript = pendingTranscript, !disableTools {
                    finalSession = LanguageModelSession(model: nativeModel, tools: tools, transcript: savedTranscript)
                    finalSession.prewarm()
                    transcriptConsumed = true
                } else {
                    finalSession = LanguageModelSession(model: nativeModel, tools: tools, instructions: Instructions(instructionsText))
                }
            } else {
                let model = PrivateCloudComputeLanguageModel()
                guard model.isAvailable else { throw LLMError.modelUnavailable }
                if let savedTranscript = pendingTranscript, !disableTools {
                    finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                    finalSession.prewarm()
                    transcriptConsumed = true
                } else {
                    finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
                }
            }
            #else
            let model = PrivateCloudComputeLanguageModel()
            guard model.isAvailable else { throw LLMError.modelUnavailable }
            if let savedTranscript = pendingTranscript, !disableTools {
                finalSession = LanguageModelSession(model: model, tools: tools, transcript: savedTranscript)
                finalSession.prewarm()
                transcriptConsumed = true
            } else {
                finalSession = LanguageModelSession(model: model, tools: tools, instructions: Instructions(instructionsText))
            }
            #endif
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
