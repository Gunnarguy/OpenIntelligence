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

    /// What a caller can usefully *do* about a failure, across both error taxonomies.
    ///
    /// Callers that recover rather than report were switching on `GenerationError` cases directly,
    /// which means their recovery is unreachable on iOS 27 where the equivalent failure arrives as a
    /// different type. `ContentTaggingService` is the clear example: it shortens the text on context
    /// overflow and falls back to `NLTagger` when content is filtered, and both branches went dead.
    /// This collapses the two taxonomies into the only distinction those callers actually need.
    enum RecoveryHint {
        case contextOverflow
        case contentFiltered
        case other
    }

    static func recoveryHint(for error: Error) -> RecoveryHint {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize: return .contextOverflow
            case .guardrailViolation, .refusal: return .contentFiltered
            default: return .other
            }
        }
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), let modern = error as? LanguageModelError {
            switch modern {
            case .contextSizeExceeded: return .contextOverflow
            case .guardrailViolation, .refusal: return .contentFiltered
            default: return .other
            }
        }
        #endif
        return .other
    }

    /// Map the iOS 27 Foundation Models error types, which replaced `GenerationError` wholesale.
    ///
    /// Returns `nil` when the error is none of them, so the caller falls through to its existing
    /// handling unchanged. This is additive on purpose: every case of
    /// `LanguageModelSession.GenerationError` is deprecated in iOS 27 rather than removed, both
    /// taxonomies still exist, and which one a given call throws is not documented anywhere. The
    /// safe migration handles both.
    ///
    /// The deployment target is iOS 26, and all four replacement types are iOS 27, which is why
    /// this is one availability-guarded downcast rather than typed `catch` clauses at each site.
    ///
    /// Apple split one enum into four:
    ///   - `GeneratedContent.ParsingError` replaces `decodingFailure`
    ///   - `LanguageModelError` replaces context size, guardrail, rate limit, refusal, guide, locale
    ///   - `LanguageModelSession.Error` replaces `concurrentRequests`
    ///   - `SystemLanguageModel.Error` replaces `assetsUnavailable`
    ///
    /// A device capture of 17 consecutive failures on 2026-08-16 was **17 of 17
    /// `GeneratedContent.ParsingError`**, every one reported as "Session ended without producing a
    /// response" with `partialTextChars: 0`. None of them matched any typed catch in the app, so
    /// each reached a generic handler that could only print `localizedDescription`. That is the
    /// whole reason this failure has resisted five separate hypotheses: the type carrying the
    /// evidence was never caught.
    static func mapModernError(
        _ error: Error,
        isStructured: Bool = false,
        estimatedTokens: Int = 0
    ) -> MappedResult? {
        // The four iOS 27 replacement types do not exist in the iOS 26 SDK, and CI builds with
        // Xcode 26. `#if compiler(>=6.4)` is the same gate `FoundationModelRoutePolicy`,
        // `FoundationModelTokenBudget` and `FoundationModelCapabilityProvider` already use for
        // SDK-version-dependent Foundation Models API. On an older toolchain this returns nil and
        // every caller falls through to its existing handling unchanged.
        #if compiler(>=6.4)
        guard #available(iOS 27.0, macOS 27.0, *) else { return nil }

        // Ordered by observed frequency on device, not by taxonomy.
        if let parsing = error as? GeneratedContent.ParsingError {
            // `rawContent` is the model output that failed to parse, and it is the thing nobody has
            // ever seen. The stream buffer reads empty on these failures, so the app concluded
            // "produced nothing" while the content sat here unread.
            let raw = parsing.rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
            Log.error(
                "[FM] GeneratedContent.ParsingError (was decodingFailure):\n"
                    + "     rawContentChars: \(raw.count)\n"
                    + "     rawContent: \(raw.isEmpty ? "<empty>" : String(raw.prefix(600)))\n"
                    + "     underlying: \(parsing.underlyingError.map { "\(type(of: $0)): \($0)" } ?? "<none>")\n"
                    + "     debug: \(parsing.debugDescription)",
                category: .llm
            )
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Generated content failed to parse",
                metadata: ["rawContentChars": "\(raw.count)"]
            )
            return .throwError(LLMError.generationFailed(
                raw.isEmpty
                    ? "Apple Intelligence ended the session without producing a response."
                    : "Apple Intelligence returned a response that could not be parsed."
            ))
        }

        if let modelError = error as? LanguageModelError {
            return mapLanguageModelError(modelError, isStructured: isStructured, estimatedTokens: estimatedTokens)
        }

        if let sessionError = error as? LanguageModelSession.Error {
            switch sessionError {
            case .concurrentRequests:
                Log.warning("[FM] Concurrent requests blocked (LanguageModelSession.Error)", category: .llm)
                return .throwError(LLMError.concurrentRequests(
                    "A request is already in progress. Please wait for it to complete."
                ))
            case .transcriptMutationWhileResponding:
                Log.error("[FM] Transcript mutated while the session was responding", category: .llm)
                return .throwError(LLMError.generationFailed(
                    "The conversation changed while a response was being generated. Please try again."
                ))
            @unknown default:
                Log.error("[FM] Unknown LanguageModelSession.Error: \(sessionError)", category: .llm)
                return .throwError(error)
            }
        }

        if let systemError = error as? SystemLanguageModel.Error {
            Log.error("[FM] SystemLanguageModel.Error: \(systemError)", category: .llm)
            return .throwError(LLMError.generationFailed(
                "Apple Intelligence models are not currently available. Ensure Apple Intelligence is enabled in Settings."
            ))
        }

        #endif

        return nil
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, macOS 27.0, *)
    private static func mapLanguageModelError(
        _ error: LanguageModelError,
        isStructured: Bool,
        estimatedTokens: Int
    ) -> MappedResult {
        switch error {
        case let .contextSizeExceeded(context):
            // The old type made the app guess with `estimatedTokens`. This one reports both numbers.
            Log.warning(
                "[FM] Context size exceeded: tokenCount \(context.tokenCount) of contextSize "
                    + "\(context.contextSize) (app estimate was \(estimatedTokens))",
                category: .llm
            )
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Context window exceeded",
                metadata: [
                    "tokenCount": "\(context.tokenCount)",
                    "contextSize": "\(context.contextSize)",
                    "estimatedTokens": "\(estimatedTokens)"
                ]
            )
            return .throwError(LLMError.contextWindowExceeded)

        case let .rateLimited(context):
            // `resetDate` is what the existing hardcoded [2, 5, 12] second backoff was approximating.
            let wait = context.resetDate.map { max(0, $0.timeIntervalSinceNow) }
            Log.warning(
                "[FM] Rate limited, resets in \(wait.map { String(format: "%.0fs", $0) } ?? "<unknown>")",
                category: .llm
            )
            return .throwError(LLMError.rateLimited(
                wait.map { "Apple Intelligence is rate-limited. Try again in about \(Int($0.rounded(.up))) seconds." }
                    ?? "Apple Intelligence is temporarily rate-limited. Please wait a moment and try again."
            ))

        case let .guardrailViolation(context):
            Log.warning("[FM] Guardrail violation: \(context.debugDescription)", category: .llm)
            TelemetryCenter.emit(.system, severity: .warning, title: "Guardrail violation", metadata: [:])
            if isStructured {
                return .throwError(LLMError.generationFailed(
                    "Structured answer was filtered by Apple Intelligence guardrails."
                ))
            }
            return .setFlags(guardrailViolation: true, unsupportedLanguage: false)

        case let .refusal(context):
            Log.warning("[FM] Model refused: \(context.debugDescription)", category: .llm)
            return .throwError(LLMError.generationFailed(
                "Apple Intelligence declined this request. Try rephrasing your question."
            ))

        case let .unsupportedLanguageOrLocale(context):
            Log.warning("[FM] Unsupported language: \(context.languageCode.identifier)", category: .llm)
            if isStructured {
                return .throwError(LLMError.generationFailed(
                    "Apple Intelligence does not support the current language/locale for structured generation."
                ))
            }
            return .setFlags(guardrailViolation: false, unsupportedLanguage: true)

        case let .unsupportedGenerationGuide(context):
            Log.error(
                "[FM] Unsupported generation guide, schema: \(context.schemaName ?? "<unnamed>")",
                category: .llm
            )
            return .throwError(LLMError.generationFailed(
                "An internal tool configuration error occurred. Please report this bug."
            ))

        case let .unsupportedCapability(context):
            Log.error("[FM] Unsupported capability: \(context.debugDescription)", category: .llm)
            return .throwError(LLMError.generationFailed(
                "This request needs a capability Apple Intelligence does not offer on this device."
            ))

        case let .unsupportedTranscriptContent(context):
            Log.error(
                "[FM] Unsupported transcript content, \(context.unsupportedContent.count) entrie(s)",
                category: .llm
            )
            return .throwError(LLMError.generationFailed(
                "Part of this conversation cannot be processed by Apple Intelligence."
            ))

        case let .timeout(context):
            Log.warning("[FM] Generation timed out: \(context.debugDescription)", category: .llm)
            return .throwError(LLMError.generationFailed(
                "Apple Intelligence took too long to respond. Please try again."
            ))

        @unknown default:
            Log.error("[FM] Unknown LanguageModelError: \(error)", category: .llm)
            return .throwError(error)
        }
    }
    #endif

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
