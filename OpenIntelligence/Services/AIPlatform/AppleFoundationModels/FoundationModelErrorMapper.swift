//
//  FoundationModelErrorMapper.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelErrorMapper {
    
    enum MappedResult {
        case throwError(Error)
        case setFlags(guardrailViolation: Bool, unsupportedLanguage: Bool)
    }

    static func mapError(
        _ error: LanguageModelSession.GenerationError,
        isStructured: Bool = false,
        estimatedTokens: Int = 0
    ) -> MappedResult {
        if isStructured {
            switch error {
            case let .exceededContextWindowSize(context):
                Log.warning("[FM] Structured context window exceeded: \(context)", category: .llm)
                return .throwError(error)
            case let .guardrailViolation(context):
                Log.warning("[FM] Structured guardrail violation: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Structured answer was filtered by Apple Intelligence guardrails."))
            case let .unsupportedLanguageOrLocale(context):
                Log.warning("[FM] Structured unsupported language/locale: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Apple Intelligence does not support the current language/locale for structured generation."))
            case let .rateLimited(context):
                Log.warning("[FM] Structured generation rate limited: \(context)", category: .llm)
                return .throwError(LLMError.rateLimited("Apple Intelligence is temporarily rate-limited. Please wait a moment and try again."))
            case let .refusal(refusal, context):
                Log.warning("[FM] Structured generation refusal: \(refusal) - \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Apple Intelligence declined the structured answer request."))
            case let .assetsUnavailable(context):
                Log.error("[FM] Structured generation assets unavailable: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Apple Intelligence models are not currently available."))
            case let .decodingFailure(context):
                Log.error("[FM] Structured generation decoding failure: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Failed to decode the structured response."))
            case let .concurrentRequests(context):
                Log.warning("[FM] Structured concurrent request blocked: \(context)", category: .llm)
                return .throwError(LLMError.concurrentRequests("A request is already in progress. Please wait for it to complete."))
            case let .unsupportedGuide(context):
                Log.error("[FM] Structured unsupported guide: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed("Unsupported structured generation guide."))
            @unknown default:
                Log.error("[FM] Structured generation error: \(error)", category: .llm)
                return .throwError(error)
            }
        } else {
            switch error {
            case let .exceededContextWindowSize(context):
                Log.warning("[FM] Context window exceeded (4096 tokens): \(context)", category: .llm)
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Context window exceeded",
                    metadata: ["estimatedTokens": "\(estimatedTokens)"]
                )
                return .throwError(error)
            case let .guardrailViolation(context):
                Log.warning("[FM] Guardrail violation - content filtered: \(context)", category: .llm)
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Guardrail violation",
                    metadata: [:]
                )
                return .setFlags(guardrailViolation: true, unsupportedLanguage: false)
            case let .unsupportedLanguageOrLocale(context):
                Log.warning("[FM] Unsupported language/locale: \(context)", category: .llm)
                return .setFlags(guardrailViolation: false, unsupportedLanguage: true)
            case let .rateLimited(context):
                Log.warning("[FM] Rate limited: \(context)", category: .llm)
                return .throwError(LLMError.rateLimited(
                    "Apple Intelligence is temporarily rate-limited. Please wait a moment and try again."
                ))
            case let .refusal(refusal, context):
                Log.warning("[FM] Model refused request: \(refusal) - \(context)", category: .llm)
                return .throwError(LLMError.generationFailed(
                    "Apple Intelligence declined this request. Try rephrasing your question."
                ))
            case let .assetsUnavailable(context):
                Log.error("[FM] Model assets unavailable: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed(
                    "Apple Intelligence models are not currently available. Ensure Apple Intelligence is enabled in Settings."
                ))
            case let .decodingFailure(context):
                Log.error("[FM] Decoding failure: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed(
                    "Failed to decode model response. This is an internal error—please try again."
                ))
            case let .concurrentRequests(context):
                Log.warning("[FM] Concurrent requests blocked: \(context)", category: .llm)
                return .throwError(LLMError.concurrentRequests(
                    "A request is already in progress. Please wait for it to complete."
                ))
            case let .unsupportedGuide(context):
                Log.error("[FM] Unsupported generation guide: \(context)", category: .llm)
                return .throwError(LLMError.generationFailed(
                    "An internal tool configuration error occurred. Please report this bug."
                ))
            @unknown default:
                Log.error("[FM] Unknown generation error: \(error)", category: .llm)
                return .throwError(error)
            }
        }
    }
}
#endif
