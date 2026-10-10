//
//  ModelErrorClassifier.swift
//  OpenIntelligence
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Says what kind of failure a generation error is, for the code that recovers from one.
///
/// Through 5.6 three places decided this from single words in the error's text. The reasoning chain
/// cut its prompt down and retried whenever the text held "context", "exceeded", "4096" or "token",
/// which the app's own unsupported-language message does ("Try rephrasing with more context"). The
/// engine waited out a rate limit whenever the text held "rate", which "generated" does. And the
/// chain retried an unreadable response only when the text said "without producing a response",
/// one of the two messages the app writes for that failure.
///
/// Here the error's type decides first: the app's `LLMError`, the error types Apple added in iOS 27,
/// and the iOS 26 type they replace. Text is read for an error of no known type, and for an
/// `LLMError.generationFailed` whose message is not one of the three the app writes for an unreadable
/// response, since that message can be another error's text passed along. It is read as phrases,
/// in Apple's own wording, printed from the macOS 27 SDK on 2026-10-09.
nonisolated enum ModelErrorClassifier {
    enum Kind: Equatable, Sendable {
        /// The prompt did not fit the model's window: send less.
        case contextOverflow
        /// The model is busy or rate limited: wait, then send the same prompt.
        case rateLimited
        /// The model returned nothing usable for a prompt that was fine: send the same prompt.
        case transient
        /// The model or a guardrail declined the content.
        case contentFiltered
        case other
    }

    /// What the app says when the model's output could not be read. `FoundationModelErrorMapper`
    /// throws these inside `LLMError.generationFailed`, and `kind(of:)` reads them back.
    static let emptyResponseMessage = "Apple Intelligence ended the session without producing a response."
    static let unparsedResponseMessage = "Apple Intelligence returned a response that could not be parsed."
    static let legacyDecodeFailureMessage =
        "Failed to decode model response. This is an internal error—please try again."

    static func kind(of error: Error) -> Kind {
        if let known = typedKind(of: error) { return known }
        return textKind(description: error.localizedDescription, detail: String(describing: error))
    }

    /// A failure worth sending the same prompt for again: a rate limit, or output that could not be
    /// read.
    static func isWorthRetryingUnchanged(_ error: Error) -> Bool {
        let kind = kind(of: error)
        return kind == .rateLimited || kind == .transient
    }

    // MARK: - By type

    private static func typedKind(of error: Error) -> Kind? {
        if let app = error as? LLMError {
            switch app {
            case .contextWindowExceeded:
                return .contextOverflow
            case .rateLimited, .concurrentRequests:
                return .rateLimited
            case .generationFailed(let message):
                let unreadable = [emptyResponseMessage, unparsedResponseMessage, legacyDecodeFailureMessage]
                // Any other message may be another error's text passed along, so the phrases decide.
                return unreadable.contains(message) ? .transient : nil
            case .modelUnavailable, .notImplemented:
                return .other
            }
        }

        #if canImport(FoundationModels)
            #if compiler(>=6.4)
                if #available(iOS 27.0, macOS 27.0, *) {
                    if let model = error as? LanguageModelError {
                        switch model {
                        case .contextSizeExceeded: return .contextOverflow
                        case .rateLimited: return .rateLimited
                        case .guardrailViolation, .refusal: return .contentFiltered
                        default: return .other
                        }
                    }
                    if error is GeneratedContent.ParsingError { return .transient }
                    if let session = error as? LanguageModelSession.Error {
                        return session == .concurrentRequests ? .rateLimited : .other
                    }
                    if error is SystemLanguageModel.Error { return .other }
                    // Private Cloud Compute's own error type is not named here. The repository's
                    // rule is that every mention of that model sits behind `EntitlementChecker`, and
                    // nothing that recovers needs it: the fallback to the on-device model runs after
                    // any failure. Its errors fall to the text rules and read `other`.
                }
            #endif
            if let legacy = error as? LanguageModelSession.GenerationError {
                switch legacy {
                case .exceededContextWindowSize: return .contextOverflow
                case .rateLimited, .concurrentRequests: return .rateLimited
                case .decodingFailure: return .transient
                case .guardrailViolation, .refusal: return .contentFiltered
                default: return .other
                }
            }
        #endif
        return nil
    }

    // MARK: - By text

    /// For an error of no known type. `detail` is `String(describing:)`, which keeps a type name
    /// that `localizedDescription` drops.
    static func textKind(description: String, detail: String = "") -> Kind {
        let text = description.lowercased()
        let detail = detail.lowercased()

        if text.contains("context size") || (text.contains("context") && text.contains("window"))
            || (text.contains("context") && text.contains("exceed"))
            || (text.contains("token") && text.contains("limit"))
            || (text.contains("4096") && text.contains("token"))
        {
            return .contextOverflow
        }
        if text.contains("rate limit") || text.contains("rate-limit") || text.contains("too many requests")
            || text.contains("concurrent")
        {
            return .rateLimited
        }
        if text.contains("failed to parse generated content") || text.contains("without producing a response")
            || text.contains("could not be parsed") || detail.contains("parsingerror")
        {
            return .transient
        }
        return .other
    }
}
