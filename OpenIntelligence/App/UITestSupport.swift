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

        /// A cited passage to open with no language model, for `SourceScreensUITests` (5.8): with
        /// `--uitest-show-source`, a note is imported and its first passage is handed to `show`, which opens the
        /// screen a citation opens. With `--uitest-watch-folder <path>`, that folder is watched and checked.
        static func runSourceScreens(
            engine: RAGService, show: @escaping (Document, RetrievedChunk) -> Void,
            arguments: [String] = CommandLine.arguments
        ) async {
            if let index = arguments.firstIndex(of: "--uitest-watch-folder"), index + 1 < arguments.count {
                let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                try? await Task.sleep(for: .seconds(2))
                let watcher = WatchedFolderService.shared
                try? watcher.watch(folder, library: engine.containerService.activeContainerId)
                await watcher.check(engine: engine, documentLimit: .max)
            }
            guard arguments.contains("--uitest-show-source") else { return }
            let name = "ui-test-source.txt"
            let text = "The first paragraph is here for context.\n\nThe heron note says the boathouse key sits under the third step of the old dock.\n\nThe last paragraph comes after it."
            var document = engine.documents.first { $0.filename.hasPrefix("ui-test-source") }
            if document == nil {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? text.write(to: url, atomically: true, encoding: .utf8)
                if let staged = try? IntentSupport.copyIntoImports(url) { _ = engine.enqueueDocuments([staged]) }
                for _ in 0..<600 where document == nil {
                    document = engine.documents.first { $0.filename.hasPrefix("ui-test-source") }
                    if document == nil { try? await Task.sleep(for: .milliseconds(100)) }
                }
            }
            guard let document, let library = document.containerId,
                let database = try? await engine.dbForContainer(library),
                let chunk = try? await database.allChunks().first(where: {
                    $0.documentId == document.id && !$0.metadata.abstractionLevel.isSummary
                })
            else { return }
            show(document, RetrievedChunk(chunk: chunk, similarityScore: 1, rank: 1, sourceDocument: document.filename, pageNumber: nil))
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
