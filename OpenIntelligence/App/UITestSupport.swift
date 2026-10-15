//
//  UITestSupport.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

#if DEBUG
    /// What the UI tests switch on when they launch the app (`OpenIntelligenceUITests`, 5.7). With
    /// `--uitest-stand-in-model`, a question asked through Siri or Shortcuts runs on a stand-in model
    /// that answers with the sentence in the `UITEST_STAND_IN_ANSWER` environment variable, because the
    /// iOS Simulator has no language model. Debug builds only: a release build has none of this.
    enum UITestSupport {
        static func configure(
            arguments: [String] = CommandLine.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            guard arguments.contains("--uitest-stand-in-model") else { return }
            let answer = environment["UITEST_STAND_IN_ANSWER"] ?? "The stand-in model was given no answer."
            AskActionRunner.makeEngine = { RAGService(llmService: StandInModel(answer: answer)) }
            Log.info("[UITest] Questions run on a stand-in model", category: .pipeline)
        }

        /// Answers with a fixed sentence, so the rest of a question's path runs as it does on a device.
        private final class StandInModel: LLMService {
            var toolHandler: RAGToolHandler?
            let answer: String
            init(answer: String) { self.answer = answer }
            var isAvailable: Bool { true }
            var modelName: String { "Stand-in" }
            func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
                LLMResponse(
                    text: answer, tokensGenerated: 12, timeToFirstToken: 0.01, totalTime: 0.01, modelName: modelName,
                    toolCallsMade: 0)
            }
        }
    }

    /// Removes the documents a UI test added, by the start of their names (Apple's guide to App Intents
    /// testing suggests intents of this kind for a test's setup and clean-up). Debug builds only, and
    /// not listed in Shortcuts.
    @available(iOS 26.0, macOS 26.0, *)
    struct UITestRemoveDocumentsIntent: AppIntent {
        static var title: LocalizedStringResource = "Remove UI Test Documents"
        static let isDiscoverable = false

        @Parameter(title: "Name Prefix")
        var namePrefix: String

        func perform() async throws -> some IntentResult & ReturnsValue<Int> {
            // A prefix this short could match a person's own document; the tests use a long one.
            guard namePrefix.count >= 8 else { return .result(value: 0) }
            let prefix = namePrefix
            let engine = await MainActor.run { IntentSupport.engine() }
            let matching = await MainActor.run { engine.documents.filter { $0.filename.hasPrefix(prefix) } }
            for document in matching {
                try await engine.removeDocument(document)
            }
            return .result(value: matching.count)
        }
    }
#endif
