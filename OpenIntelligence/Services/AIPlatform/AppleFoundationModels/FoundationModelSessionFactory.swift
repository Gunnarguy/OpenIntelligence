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
                // The installed SDK exposes no advanced/20B on-device model
                // (`SystemLanguageModel.advanced` does not exist — compiler-probe
                // verified). This route executes the standard on-device model, so
                // telemetry must report `.onDevice`, not a tier that never ran.
                let model = SystemLanguageModel.default
                guard case .available = model.availability else { throw LLMError.modelUnavailable }
                selectedRoute = .onDevice // Telemetry: actual executed route
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
                guard EntitlementChecker.hasEntitlement(EntitlementChecker.privateCloudComputeKey) else {
                    throw LLMError.modelUnavailable
                }
                let nativeModel = FoundationModels.PrivateCloudComputeLanguageModel()
                guard nativeModel.isAvailable, !nativeModel.quotaUsage.isLimitReached else {
                    throw LLMError.modelUnavailable
                }
                if let savedTranscript = pendingTranscript, !disableTools {
                    finalSession = LanguageModelSession(model: nativeModel, tools: tools, transcript: savedTranscript)
                    finalSession.prewarm()
                    transcriptConsumed = true
                } else {
                    finalSession = LanguageModelSession(model: nativeModel, tools: tools, instructions: Instructions(instructionsText))
                }
            } else {
                // PCC is an iOS/macOS 27 capability. Never report a local iOS 26
                // session as cloud execution.
                throw LLMError.modelUnavailable
            }
            #else
            throw LLMError.modelUnavailable
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
