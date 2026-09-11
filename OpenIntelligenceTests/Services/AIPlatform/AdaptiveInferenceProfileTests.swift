//
//  AdaptiveInferenceProfileTests.swift
//  OpenIntelligenceTests
//
//  Pins the two properties that make adaptive profiles safe to ship off by default:
//  the mapping from intent to profile, and the fact that applying one writes nothing.
//
//  The numbers themselves are a hypothesis, not a measurement. Retrieval in this app is
//  nondeterministic, so no A/B here can currently show whether these values produce better
//  answers. What these tests can guarantee is that the mechanism does exactly and only what it
//  claims: a value lookup is near-deterministic, an analysis is not, and nothing leaks into the
//  owner's saved settings.
//

import XCTest

@testable import OpenIntelligence

#if canImport(FoundationModels)

    @available(iOS 26.0, macOS 26.0, *)
    final class AdaptiveInferenceProfileTests: XCTestCase {

        // MARK: - Intent mapping

        func testLookupsAndCalculationsGetTheExtractiveProfile() {
            // A looked-up value and a derived number both have exactly one right answer. Sampling
            // variance in arithmetic is not creativity, it is a wrong total.
            for intent in [AnswerIntent.lookup, .tableLookup, .compute] {
                XCTAssertEqual(
                    FoundationModelDynamicProfileRegistry.profile(for: intent),
                    .extractive,
                    "\(intent.rawValue) should be extractive"
                )
            }
        }

        func testComparisonAndInvestigationGetTheAnalyticalProfile() {
            XCTAssertEqual(FoundationModelDynamicProfileRegistry.profile(for: .compare), .analytical)
            XCTAssertEqual(FoundationModelDynamicProfileRegistry.profile(for: .investigate), .analytical)
        }

        func testSummarizeAndProcedureAreNotTreatedAsExtraction() {
            XCTAssertEqual(FoundationModelDynamicProfileRegistry.profile(for: .summarize), .summarization)
            XCTAssertEqual(FoundationModelDynamicProfileRegistry.profile(for: .procedure), .grounded)
        }

        func testEveryIntentResolvesToAProfile() {
            // What this proves, and what it does not. `profile(for:)` switches exhaustively today,
            // so a new `AnswerIntent` case breaks the build rather than falling into a default, and
            // that guarantee comes from the compiler, not from here. This asserts only that every
            // case resolves to a profile carrying a stated rationale. It would still pass if
            // someone added `default: return .grounded`, so it is not a guard against that.
            for intent in AnswerIntent.allCases {
                XCTAssertFalse(
                    FoundationModelDynamicProfileRegistry.profile(for: intent).generation.rationale.isEmpty,
                    "\(intent.rawValue) resolved to a profile with no stated rationale"
                )
            }
        }

        // MARK: - The values are ordered the way the feature claims

        func testExtractionIsColderThanAnalysis() {
            let extractive = FoundationModelDynamicProfile.extractive.generation
            let analytical = FoundationModelDynamicProfile.analytical.generation

            XCTAssertLessThan(
                extractive.temperature, analytical.temperature,
                "The whole claim is that a value lookup is more repeatable than an investigation"
            )
            XCTAssertLessThan(
                extractive.maxTokens, analytical.maxTokens,
                "An extracted fact that runs as long as an analysis has stopped being extraction"
            )
        }

        func testNoProfileIsHotEnoughToInventFacts() {
            // This app abstains rather than guesses. Nothing here should reach the range where the
            // model starts writing freely over thin evidence.
            for profile in FoundationModelDynamicProfile.allCases {
                XCTAssertLessThanOrEqual(
                    profile.generation.temperature, 0.5,
                    "\(profile.rawValue) is too hot for a grounded RAG answer"
                )
                XCTAssertGreaterThanOrEqual(profile.generation.temperature, 0.0)
                XCTAssertGreaterThan(profile.generation.maxTokens, 0)
            }
        }

        // MARK: - Applying a profile is pure

        func testApplyingAProfileReturnsACopyAndLeavesTheOriginalAlone() {
            var original = InferenceConfig()
            original.temperature = 0.9
            original.maxTokens = 2048

            let adjusted = original.applyingAdaptiveProfile(for: .lookup)

            XCTAssertEqual(original.temperature, 0.9, "the source config was mutated")
            XCTAssertEqual(original.maxTokens, 2048, "the source config was mutated")
            XCTAssertEqual(adjusted.temperature, FoundationModelDynamicProfile.extractive.generation.temperature)
            XCTAssertEqual(adjusted.maxTokens, FoundationModelDynamicProfile.extractive.generation.maxTokens)
        }

        func testApplyingAProfileTouchesNothingElseInTheConfig() {
            // The feature adjusts two numbers. If it ever starts changing sampling, the route or the
            // system prompt, that is a behaviour change nobody opted into by flipping this toggle.
            var original = InferenceConfig()
            original.topP = 0.77
            original.topK = 11
            original.samplingStrategy = .topP
            original.seed = 4242
            original.qualityMode = .maximum

            let adjusted = original.applyingAdaptiveProfile(for: .summarize)

            XCTAssertEqual(adjusted.topP, 0.77)
            XCTAssertEqual(adjusted.topK, 11)
            XCTAssertEqual(adjusted.samplingStrategy, .topP)
            XCTAssertEqual(adjusted.seed, 4242)
            XCTAssertEqual(adjusted.qualityMode, .maximum)
        }

        func testApplyingAProfileWritesNothingToUserDefaults() {
            // `AutoTuneService` adjusts the same two settings by writing them back into
            // `UserDefaults`, which silently overwrites what the owner set by hand and survives
            // turning the feature off. It has zero call sites and this test is why.
            let defaults = UserDefaults.standard
            let temperatureBefore = defaults.object(forKey: "llmTemperature")
            let tokensBefore = defaults.object(forKey: "llmMaxTokens")

            _ = InferenceConfig().applyingAdaptiveProfile(for: .compare)

            XCTAssertEqual(
                defaults.object(forKey: "llmTemperature") as? Double,
                temperatureBefore as? Double,
                "applying a profile must not persist anything"
            )
            XCTAssertEqual(
                defaults.object(forKey: "llmMaxTokens") as? Int,
                tokensBefore as? Int,
                "applying a profile must not persist anything"
            )
        }

        func testTheFeatureIsOffWhenNobodyHasTurnedItOn() {
            // `RAGService` gates on `UserDefaults.bool(forKey:)`, which returns false for an absent
            // key. This is the property that makes the change invisible to every existing install.
            let key = "adaptiveInferenceProfiles"
            let saved = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)

            XCTAssertFalse(UserDefaults.standard.bool(forKey: key))

            if let saved { UserDefaults.standard.set(saved, forKey: key) }
        }
    }

#endif
