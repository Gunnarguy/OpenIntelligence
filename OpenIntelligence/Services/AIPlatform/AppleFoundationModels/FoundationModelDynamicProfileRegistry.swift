//
//  FoundationModelDynamicProfileRegistry.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    /// Generation settings chosen from what the question is asking for.
    ///
    /// **This replaced a placeholder that would have made answers worse if anyone had wired it up.**
    /// The previous version mapped each intent to a complete `systemPrompt`: one-line strings such as
    /// "You are a helpful assistant. Answer the user's questions clearly." Using those would have
    /// *replaced* the app's real instructions, which `FoundationModelPromptCompiler` assembles with
    /// grounding, citation and abstention rules, with a generic sentence. The registry had zero call
    /// sites, and `SettingsView` had already removed "Dynamic Profiles" from the capability list on
    /// the grounds that advertising an unimplemented feature is a false claim rather than a teaser.
    ///
    /// So the fix was not to connect the old shape. It was to change what the registry produces. It
    /// now returns **generation parameters only**, and nothing here touches a prompt.
    ///
    /// **Why per intent rather than per quality mode.** `RAGQualityMode` already carries a
    /// temperature, but it is the same for every question asked in that mode: Standard answers a
    /// serial-number lookup and an open-ended comparison at 0.4. The intent is already computed by
    /// `QueryEnhancementService` before generation, and it is the better signal. Looking up a value
    /// wants near-determinism, because the same question asked twice should give the same number.
    /// Investigating a topic does not.
    ///
    /// **The numbers below are reasoned, not measured.** Retrieval in this app is nondeterministic
    /// (`Docs/ai/DECISIONS.md`), so two runs of one build return different evidence and different
    /// answers, and no A/B here is currently trustworthy. That is exactly why applying a profile is
    /// opt-in and off by default: it is a hypothesis the owner can turn on and judge, not a silent
    /// change to everyone's answers.
    @available(iOS 26.0, macOS 26.0, *)
    struct FoundationModelGenerationProfile: Sendable, Equatable {
        /// Lower is more repeatable. `InferenceConfig.temperature` is a `Float`.
        let temperature: Float

        /// Ceiling for the answer, in tokens.
        let maxTokens: Int

        /// Why this profile is shaped this way. Logged when a profile is applied, so a surprising
        /// answer can be traced to the setting that produced it rather than guessed at.
        let rationale: String
    }

    @available(iOS 26.0, macOS 26.0, *)
    enum FoundationModelDynamicProfile: String, CaseIterable, Sendable {
        case extractive
        case grounded
        case analytical
        case summarization

        var generation: FoundationModelGenerationProfile {
            switch self {
            case .extractive:
                // A looked-up value must not vary between identical questions. The short ceiling is
                // deliberate: an extracted fact that runs to 500 tokens has stopped being extraction.
                return .init(
                    temperature: 0.1,
                    maxTokens: 400,
                    rationale: "extractive: the same question should return the same value"
                )
            case .grounded:
                return .init(
                    temperature: 0.3,
                    maxTokens: 900,
                    rationale: "grounded: follow the evidence, room enough for steps"
                )
            case .analytical:
                // Comparison and investigation need room to hold several sources side by side.
                return .init(
                    temperature: 0.35,
                    maxTokens: 1400,
                    rationale: "analytical: several sources held together, longer answer"
                )
            case .summarization:
                return .init(
                    temperature: 0.4,
                    maxTokens: 1000,
                    rationale: "summarization: condensing, not extracting"
                )
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    enum FoundationModelDynamicProfileRegistry {

        /// The profile for a resolved answer intent.
        static func profile(for intent: AnswerIntent) -> FoundationModelDynamicProfile {
            switch intent {
            case .lookup, .tableLookup, .compute:
                // `compute` joins the extractive group deliberately. A derived number has one right
                // answer, and sampling variance in arithmetic is not creativity, it is a wrong total.
                return .extractive
            case .procedure:
                return .grounded
            case .compare, .investigate:
                return .analytical
            case .summarize:
                return .summarization
            case .findings:
                return .grounded
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    extension InferenceConfig {

        /// A copy of this config with the intent's generation profile applied.
        ///
        /// Pure: it returns a new value and writes nothing. That matters because the obvious
        /// alternative already exists in this repository and is wrong. `AutoTuneService` adjusts the
        /// same settings by writing them back into `UserDefaults`, which silently overwrites numbers
        /// the owner chose by hand in the Model Parameters sheet and cannot be undone by turning the
        /// feature off. It has zero call sites, and it should keep them.
        ///
        /// Applying a profile replaces `temperature` and `maxTokens` outright rather than clamping to
        /// what the sheet holds. Clamping would make the feature do nothing for anyone who had
        /// already set a low ceiling, which is the population most likely to try it. The caller opts
        /// in explicitly, so replacing is what they asked for.
        func applyingAdaptiveProfile(for intent: AnswerIntent) -> InferenceConfig {
            let profile = FoundationModelDynamicProfileRegistry.profile(for: intent).generation
            var adjusted = self
            adjusted.temperature = profile.temperature
            adjusted.maxTokens = profile.maxTokens
            return adjusted
        }
    }
#endif
