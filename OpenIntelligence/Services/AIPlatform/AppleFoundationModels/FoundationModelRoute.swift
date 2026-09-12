//
//  FoundationModelRoute.swift
//  OpenIntelligence
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    @available(iOS 26.0, macOS 26.0, *)
    public enum PCCReasoningLevel: String, Sendable, Equatable {
        case none
        case light
        case moderate
        case deep
    }

    @available(iOS 26.0, macOS 26.0, *)
    public enum AppleFoundationModelRoute: Sendable, Equatable {
        case onDevice
        case onDeviceAdvanced
        case privateCloudCompute(reasoning: PCCReasoningLevel)
        case automatic
    }

    #if compiler(>=6.4)

        @available(iOS 27.0, macOS 27.0, *)
        extension AppleFoundationModelRoute {
            /// The reasoning level to send Apple for this route, or `nil` to send none.
            ///
            /// WHY THIS IS A PROPERTY RATHER THAN INLINE AT EACH CALL SITE
            ///
            /// `ContextOptions` is new in iOS and macOS 27 and is a parameter on **every** `respond` and
            /// `streamResponse` overload, defaulting to an empty value. A call site that omits it does
            /// not fail; it silently runs at Apple's default effort. Until 2026-09-10 one of the app's
            /// twenty-five generation call sites passed it, so Deep Think and Maximum advertised
            /// "highest-effort reasoning" and frequently did not ask for any. Keeping the mapping in one
            /// place is what makes the next call site's omission visible.
            ///
            /// Only Private Cloud Compute takes a level. The on-device model gets nothing, because
            /// `GenerationOptions` is the only knob it accepts and it carries no reasoning level.
            /// `[evidence_level: code_verified, confidence: exact, evidence_source:
            /// FoundationModels.swiftinterface, iOS 27 SDK in Xcode 27A5194q: ContextOptions is
            /// @available(iOS 27.0, ...) and GenerationOptions declares only samplingMode, temperature,
            /// maximumResponseTokens and toolCallingMode]`
            var reasoningLevel: FoundationModels.ContextOptions.ReasoningLevel? {
                guard case .privateCloudCompute(let reasoning) = self else { return nil }

                // A reasoning profile the owner wrote themselves, if there is one.
                //
                // `ContextOptions.ReasoningLevel` has a fourth case besides light, moderate and
                // deep: `custom(String)`. It takes free text describing how the model should
                // approach the problem, which is a capability this app had never used. The three
                // named levels are a dial; `custom` is a sentence.
                //
                // It applies only where reasoning applies at all, which is the Private Cloud
                // Compute route: Apple's capability table lists reasoning as unsupported
                // on-device, and `GenerationOptions` has no equivalent knob. A profile written
                // here therefore changes nothing about a question answered on the device, and the
                // settings copy says so rather than letting someone write one and wonder why
                // nothing happened.
                //
                // `.none` still wins. That case means the query type does not warrant reasoning
                // spend at all, and a custom profile is a description of *how* to reason rather
                // than an instruction to start.
                if reasoning != .none {
                    let custom =
                        UserDefaults.standard
                        .string(forKey: "customReasoningProfile")?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !custom.isEmpty {
                        return .custom(custom)
                    }
                }

                switch reasoning {
                case .none: return nil
                case .light: return .light
                case .moderate: return .moderate
                case .deep: return .deep
                }
            }

            /// `ContextOptions` for this route, preserving the caller's schema behaviour.
            ///
            /// `includeSchemaInPrompt` must be passed through rather than defaulted. The guided-generation
            /// overloads of `respond` and `streamResponse` default it to `true` while the plain overloads
            /// leave it `nil`, so handing a structured call a bare `ContextOptions(reasoningLevel:)` would
            /// quietly stop including the schema in the prompt. Returns `nil` when there is nothing to
            /// say, so a caller can fall through to the overload that takes no context options at all.
            func contextOptions(includeSchemaInPrompt: Bool? = nil) -> FoundationModels.ContextOptions? {
                guard let reasoningLevel else { return nil }
                return FoundationModels.ContextOptions(
                    includeSchemaInPrompt: includeSchemaInPrompt,
                    reasoningLevel: reasoningLevel
                )
            }
        }

    #endif

#endif
