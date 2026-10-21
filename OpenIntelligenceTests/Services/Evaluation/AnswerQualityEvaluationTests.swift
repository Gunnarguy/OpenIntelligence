//
//  AnswerQualityEvaluationTests.swift
//  OpenIntelligenceTests
//
//  Answers Apple's on-device model writes through the app's whole question path, graded by a model
//  judge with Apple's Evaluations framework (5.7, roadmap row "Adopt Apple's Evaluations framework
//  for answer-quality grading"). The cases are `Benchmarks/rag_eval_v1.jsonl` over the committed
//  fixtures of `Benchmarks/ResearchFixtures/tiny_research_suite`. The fixtures are imported into a
//  library of their own, each question runs through `AskActionRunner` in Standard, as Siri and
//  Shortcuts ask, with an engine whose model is Apple's own (`OnDeviceModel`), and
//  `ModelJudgeEvaluator` compares each answer with the case's reference answer.
//
//  Opt-in, because it takes minutes and its verdicts depend on a model: run it with
//  `TEST_RUNNER_OI_MODEL_EVALS=1` in the environment of `xcodebuild test`. The iOS 27.0 Simulator on
//  this Mac generates with Apple's model (measured 2026-10-01); the app keeps its own model off in the
//  Simulator, which is why the test hands the engine a model of its own.
//

import Evaluations
import Foundation
import FoundationModels
import Testing

@testable import OpenIntelligence

/// Apple's on-device model, called the way the app's own service calls it: the engine's system prompt as
/// the session's instructions, and the prompt the app's compiler builds from the question and the context.
@available(iOS 27.0, macOS 27.0, *)
private final class OnDeviceModel: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
    var modelName: String { "Apple on-device model (evaluation)" }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        let started = Date()
        let compiled = FoundationModelPromptCompiler.compilePrompt(
            prompt: prompt, context: context, systemPrompt: config.systemPrompt, disableTools: true)
        let session =
            config.systemPrompt.map { LanguageModelSession(instructions: $0) } ?? LanguageModelSession()
        let text = try await session.respond(to: compiled).content
        let seconds = Date().timeIntervalSince(started)
        return LLMResponse(
            text: text, tokensGenerated: text.split(separator: " ").count, timeToFirstToken: seconds,
            totalTime: seconds, modelName: modelName, toolCallsMade: 0)
    }
}

/// One case of `rag_eval_v1.jsonl`, as the file writes it.
private struct EvalCase: Decodable {
    let id: String
    let query: String
    let expectedAnswer: String
    let shouldAbstain: Bool
    let notes: String?

    /// The fixture file names in `notes` ("fixtures: a.md, b.md").
    var fixtureNames: [String] {
        guard let notes, let range = notes.range(of: "fixtures:") else { return [] }
        return notes[range.upperBound...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private enum AnswerQualityData {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let fixtures = repository.appendingPathComponent("Benchmarks/ResearchFixtures/tiny_research_suite/fixtures")

    static let cases: [EvalCase] = {
        let url = repository.appendingPathComponent("Benchmarks/rag_eval_v1.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { try? JSONDecoder().decode(EvalCase.self, from: Data($0.utf8)) }
    }()

    /// Every fixture the cases name, found by name under the suite's fixture folder.
    static var fixtureFiles: [URL] {
        let wanted = Set(cases.flatMap(\.fixtureNames))
        let all = FileManager.default.enumerator(at: fixtures, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return all.filter { wanted.contains($0.lastPathComponent) }
    }

    /// What the judge compares an answer with. An abstention case has no answer to state.
    static func reference(for evalCase: EvalCase) -> String {
        evalCase.shouldAbstain
            ? "The documents do not contain this information, so the answer should say it is not available."
            : evalCase.expectedAnswer
    }
}

/// The library the questions are asked of, made once per run. The fixtures are more than the free plan's five
/// documents, and the engine the app shows holds the app's own plan, so they are imported by an engine of their
/// own whose plan store reads Pro from a defaults suite of this test; the app's saved plan is set to Pro only for the
/// moment the library is created (`createContainer` reads it) and put back. The
/// first run set Pro in the app's defaults instead, which the shown engine's store never read, and imported 6 of
/// the 25 fixtures (2026-10-20).
///
/// The library and its documents are removed when the run ends (`remove`), and any a run that stopped early left
/// are removed before a new one is made. The first run left its library on the test simulator, and its five
/// documents filled the free plan's limit there, so the next suite's import test was refused (2026-10-20).
@available(iOS 27.0, macOS 27.0, *)
private actor EvaluationLibrary {
    static let shared = EvaluationLibrary()
    static let namePrefix = "Answer evaluation "
    private var made: (library: UUID, importer: RAGService)?
    /// The one setup of the run. The framework produces answers concurrently, and the actor takes another call while
    /// the first setup awaits, so each question started a library of its own (2026-10-21).
    private var making: Task<(library: UUID, importer: RAGService), Error>?

    func id() async throws -> UUID {
        if let made { return made.library }
        if making == nil { making = Task { try await Self.make() } }
        let new = try await making!.value
        made = new
        return new.library
    }

    /// The engine that imported the fixtures, which answers the questions too: it holds the Pro plan and the
    /// library. The second run made a new engine per question with the app's default plan, which is Free, and every
    /// question was refused with "This would bring your workspace to 2 libraries" (2026-10-21).
    func engine() async throws -> RAGService {
        _ = try await id()
        return made!.importer
    }

    /// Removes the library and its documents, and gives Siri and Shortcuts their usual engine back.
    func remove() async {
        guard let made else { return }
        self.made = nil
        await Self.delete(made.library, importer: made.importer)
        await MainActor.run { AskActionRunner.makeEngine = { RAGService() } }
    }

    /// Per document, then the library: `deleteContainer` alone leaves the documents in the document list, where
    /// they still count against the plan (`ImportTargetLibraryTests` does the same).
    @MainActor
    private static func delete(_ library: UUID, importer: RAGService) async {
        for document in importer.documents where document.containerId == library {
            try? await importer.removeDocument(document)
        }
        importer.containerService.deleteContainer(id: library)
    }

    @MainActor
    private static func make() async throws -> (library: UUID, importer: RAGService) {
        // Apple's model reads "not ready" for about a minute after a Simulator boots (measured 2026-10-01).
        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        print("[AnswerQualityEvaluation] model availability: \(SystemLanguageModel.default.availability)")
        let plan = UserDefaults(suiteName: "AnswerQualityEvaluation.plan") ?? .standard
        plan.set(WorkspaceTier.pro.rawValue, forKey: "entitlement.activeTier")
        let store = EntitlementStore(billingService: StoreKitBillingService(), defaults: plan)
        let libraries = IntentSupport.libraries()
        let importer = RAGService(llmService: OnDeviceModel(), containerService: libraries, entitlementStore: store)
        for _ in 0..<100 where !importer.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        if importer.hasLoadedDocumentsFromDisk {
            for leftover in libraries.containers where leftover.name.hasPrefix(namePrefix) {
                await delete(leftover.id, importer: importer)
                print("[AnswerQualityEvaluation] removed \(leftover.name), left by an earlier run")
            }
        } else {
            print("[AnswerQualityEvaluation] the documents were not loaded in 10 s; earlier libraries are left as they are")
        }
        // `ContainerService.createContainer` checks the plan the app saved (`EntitlementStore.currentLibraryLimit()`,
        // standard defaults), not an engine's store, and on the test simulator that plan is Free with its one library
        // taken. Pro is set there for this one call and what was there is put back (2026-10-21).
        let tierKey = "entitlement.activeTier"
        let savedTier = UserDefaults.standard.string(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let created = Result { try libraries.createContainer(name: "\(namePrefix)\(UUID().uuidString.prefix(6))") }
        if let savedTier {
            UserDefaults.standard.set(savedTier, forKey: tierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tierKey)
        }
        let container = try created.get()
        let files = AnswerQualityData.fixtureFiles
        let result = await importer.ingestDocuments(files, containerId: container.id)
        print("[AnswerQualityEvaluation] imported \(result.successCount) of \(files.count) fixtures")
        return (container.id, importer)
    }
}

@available(iOS 27.0, macOS 27.0, *)
private struct AnswerQualityEvaluation: Evaluation {
    typealias Sample = ModelSample<String>
    typealias Subject = ModelSubject<String>

    static let correct = Metric("Correct")

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(
            samples: AnswerQualityData.cases.map {
                ModelSample(prompt: $0.query, expected: AnswerQualityData.reference(for: $0))
            })
    }

    /// Passages per question: the Ask My Documents action's default, 3, unless OI_EVAL_TOPK (TEST_RUNNER_OI_EVAL_TOPK)
    /// sets another number from 1 to 12, the action's own range.
    static var passages: Int {
        Int(ProcessInfo.processInfo.environment["OI_EVAL_TOPK"] ?? "").map { min(max($0, 1), 12) } ?? 3
    }

    /// On the main actor, as the engine and its answer are (the module's default isolation).
    @MainActor
    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        let library = try await EvaluationLibrary.shared.id()
        let engine = try await EvaluationLibrary.shared.engine()
        AskActionRunner.makeEngine = { engine }
        do {
            let outcome = try await AskActionRunner.ask(
                sample.promptDescription, mode: .standard, topK: Self.passages, libraryId: library)
            return ModelSubject(value: outcome.answer.text)
        } catch {
            // A refused question is an answer too: an abstention case may end here.
            return ModelSubject(value: "\(error)")
        }
    }

    var evaluators: Evaluators {
        ModelJudgeEvaluator<ModelSample<String>>(
            "Correct",
            scale: .passFail(
                passDescription: "The response gives the facts of the reference answer, or, when the reference says the information is not available, the response says so too.",
                failDescription: "The response leaves out or contradicts the reference answer, or answers when the reference says the information is not available."
            ))
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: Self.correct)
    }
}

@Suite(
    "Answers graded by a model judge with Apple's Evaluations framework",
    .enabled(if: ProcessInfo.processInfo.environment["OI_MODEL_EVALS"] == "1"))
struct AnswerQualityEvaluationTests {
    @available(iOS 27.0, macOS 27.0, *)
    @Test(.evaluates(AnswerQualityEvaluation()), .timeLimit(.minutes(30)))
    func answersAgreeWithTheReferenceAnswers() async throws {
        let result = EvaluationContext.current.result
        let correct = result.aggregateValue(.mean(of: AnswerQualityEvaluation.correct))
        print("[AnswerQualityEvaluation] correct: \(correct) over \(AnswerQualityData.cases.count) cases")
        print("[AnswerQualityEvaluation] \(result.groupedSummary)")
        await EvaluationLibrary.shared.remove()
        #expect(AnswerQualityData.cases.count == 20, "the dataset has \(AnswerQualityData.cases.count) cases")
        // A floor, not a target: the figure itself is what the run is for, and it is in the report. Measured in the
        // iOS 27.0 Simulator on 2026-10-21: 0.3 with the action's 3 passages, 0.25 with 12. Most misses are the
        // dataset's: the five synthetic exact fixtures never say what their value measures ("| Primary answer |
        // 14.3 US gal |" for "How many gallons of gasoline can the vehicle hold?"), so a grounded "the excerpts do not
        // say" is graded wrong, and the four "which document" references are bare keys ("ALPHA-17"). The floor catches
        // a run that produces no answers, as the first two runs that night did (-1.0); raise it when cases with real
        // reference answers replace these (row https://app.notion.com/p/3b549a74d54f814cbb06fa629417b657).
        #expect(correct >= 0.2, "\(result.groupedSummary)")
    }
}
