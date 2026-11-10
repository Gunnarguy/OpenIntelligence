//
//  EvidenceReachBenchmarkTests.swift
//  OpenIntelligenceTests
//
//  Whether the passage that answers a question reaches the model, through the app's own pipeline (5.8 audit). For each
//  QASPER question it records the exact context Standard gives the model (`queryInternal`, a stand-in model that keeps
//  the context it was handed) and the passages Deep Think's search returns in order (`executeFullRetrievalPipeline`).
//  `scripts/evidence_reach.py` scores both against the annotators' evidence paragraphs. With
//  `TEST_RUNNER_OI_RETRIEVAL_ABLATE=<rule>` (`RetrievalAblation`) one rule is switched off, so each rule's effect on
//  whether the evidence reaches the model can be measured on its own.
//
//  Run only on purpose. It needs `TEST_RUNNER_OI_EVIDENCE_DIR` (a folder holding `fixtures/` and `queries.jsonl`,
//  written by `scripts/evidence_reach.py prepare`) and writes `reach-<TEST_RUNNER_OI_EVIDENCE_LABEL>.json` there;
//  without the folder it skips. `TEST_RUNNER_OI_EVIDENCE_LIMIT` asks only the first N questions. The library
//  "Evidence benchmark" is imported once and reused. The stand-in model means steps that call Apple's model directly
//  (contextual compression, query rewriting) take their no-model path, so this measures retrieval and assembly, not
//  answers.
//

import XCTest

@testable import OpenIntelligence

@available(iOS 26.0, macOS 26.0, *)
final class ContextKeepingModel: AppleFoundationLLMService {
    var contexts: [String] = []

    override var isAvailable: Bool { true }
    override var modelName: String { "context-keeper" }

    private func answer(_ context: String?) -> LLMResponse {
        contexts.append(context ?? "")
        let lead = (context ?? "").split(separator: "\n").first { $0.count > 24 }.map { String($0.prefix(200)) } ?? ""
        return LLMResponse(
            text: "\(lead) [S1]", tokensGenerated: 32, timeToFirstToken: nil, totalTime: 0, modelName: "context-keeper",
            toolCallsMade: 0)
    }

    override func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        answer(context)
    }

    override func generateStructuredRAGAnswer(
        prompt: String, context: String, config: InferenceConfig, sourceCount: Int, mode: StructuredRAGMode = .direct
    ) async throws -> LLMResponse {
        answer(context)
    }
}

/// Apple's model through the app's own service, in the Simulator, for an answer-level run. The service reports itself
/// unavailable there (`AppleFoundationLLMService.isAvailable`), but the iOS 27 Simulator does generate after about a
/// minute of `modelNotReady` (measured 2026-10); everything past that gate runs as shipped.
@available(iOS 26.0, macOS 26.0, *)
final class SimulatorAppleModel: AppleFoundationLLMService {
    override var isAvailable: Bool { true }
}

@MainActor
final class EvidenceReachBenchmarkTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private static let libraryName = "Evidence benchmark"

    private struct Question: Decodable {
        let qid: String
        let query: String
    }

    func testRecordEvidenceReach() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["OI_EVIDENCE_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_OI_EVIDENCE_DIR to record an evidence-reach run")
        }
        let dir = URL(fileURLWithPath: folder)
        let label = environment["OI_EVIDENCE_LABEL"] ?? "run"
        let limit = Int(environment["OI_EVIDENCE_LIMIT"] ?? "") ?? .max
        let questions = try String(contentsOf: dir.appendingPathComponent("queries.jsonl"), encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(Question.self, from: Data($0.utf8)) }
            .prefix(limit)
        let fixtureDir = dir.appendingPathComponent("fixtures")
        let fixtures = try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(fixtureDir.path)")

        let engine = IntentSupport.engine()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let savedTier = UserDefaults.standard.object(forKey: tierKey)
        func forcePro() {
            UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
            AppServices.shared.entitlementStore.setDebugTier(.pro)
        }
        forcePro()
        let settings = try XCTUnwrap(engine.settingsStore, "the engine has no settings store")
        let libraries = engine.containerService
        let previous = libraries.activeContainerId
        let savedModel = engine._llmService
        let savedSummaries = settings.enableDocumentSummaries
        // Held as `StandardPipelineGoldenTests` holds them: the on-device route and Apple's documented 4,096-token
        // window, the phone's case, and no direct model calls.
        // `TEST_RUNNER_OI_EVIDENCE_REAL_MODEL=1` keeps Apple's model and the app's own checks, and records the answer
        // shown, for an answer-level run; otherwise the stand-in records what reached the model.
        let realModel = environment["OI_EVIDENCE_REAL_MODEL"] == "1"
        FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = 4096
        NetworkMonitor.shared.holdForTesting(false)
        DirectModelCallsForTesting.disabled = !realModel
        addTeardownBlock { @MainActor in
            DirectModelCallsForTesting.disabled = false
            FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = nil
            NetworkMonitor.shared.holdForTesting(nil)
            engine._llmService = savedModel
            settings.enableDocumentSummaries = savedSummaries
            UserDefaults.standard.set(savedTier, forKey: self.tierKey)
            libraries.setActive(previous)
        }
        engine.discardPausedIngestionQueue()

        func documents(in id: UUID) -> [Document] { engine.documents.filter { $0.containerId == id } }
        let fixtureNames = Set(fixtures.map(\.lastPathComponent))
        var library =
            try libraries.containers.first { $0.name == Self.libraryName }
            ?? libraries.createContainer(name: Self.libraryName)
        if Set(documents(in: library.id).map(\.filename)) != fixtureNames
            || engine.ingestionItems.contains(where: { $0.containerId == library.id })
        {
            await engine.cancelAndPurgeIngestion(for: library.id)
            for document in documents(in: library.id) { try? await engine.removeDocument(document) }
            libraries.deleteContainer(id: library.id)
            forcePro()
            settings.enableDocumentSummaries = false
            library = try libraries.createContainer(name: Self.libraryName)
            libraries.setActive(library.id)
            forcePro()
            let result = await engine.ingestDocuments(fixtures, containerId: library.id)
            XCTAssertEqual(result.successCount, fixtures.count, "every fixture imports")
            settings.enableDocumentSummaries = savedSummaries
        }
        for _ in 0..<1800 {
            if !RAGService.deferredEnrichments().contains(where: { $0.library == library.id }) { break }
            engine.runDeferredEnrichmentsIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let db = try await engine.dbForContainer(library.id)
        var counts: [Int] = []
        for _ in 0..<900 {
            let busy = engine.ingestionItems.contains { $0.containerId == library.id && !$0.stage.isTerminal }
            counts.append(try await db.readableChunks().count)
            if !busy, counts.count >= 5, Set(counts.suffix(5)).count == 1, counts.last! > 0 { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let stored = try await db.readableChunks().count
        XCTAssertGreaterThan(stored, 0, "the benchmark library holds no passages")
        // The keyword index is rebuilt at launch in a task of its own; wait until it holds still.
        var keywordRows: [Int] = []
        for _ in 0..<300 {
            var rows = 0
            for document in documents(in: library.id) {
                rows += await SQLiteFullTextService.shared.retrieveChunks(for: document.id).count
            }
            keywordRows.append(rows)
            if rows > 0, keywordRows.count >= 5, Set(keywordRows.suffix(5)).count == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let model = ContextKeepingModel()
        engine._llmService = realModel ? SimulatorAppleModel() : model
        if realModel {
            // Wait out the Simulator's model warm-up with a real request, as the October probes did.
            for attempt in 0..<40 {
                if (try? await engine._llmService.generate(prompt: "Say OK.", context: nil, config: InferenceConfig())) != nil {
                    print("[EvidenceReach] Apple's model answered after \(attempt) retries")
                    break
                }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        libraries.setActive(library.id)

        // `TEST_RUNNER_OI_EVIDENCE_CONFIGS`: configurations measured in this one process, each "name:paths:rules" with
        // paths "s" (Standard), "d" (Deep Think) or "sd", and rules a "+"-joined list of `RetrievalAblation` names
        // ("baseline:sd:" is everything on). One import serves them all; each question is asked in every configuration
        // before the next. `TEST_RUNNER_OI_EVIDENCE_SLICE=i/n` takes every n-th question from the i-th, so n simulators
        // can share a run. Without the variable, one configuration: the process's own switches, both paths.
        struct Config {
            let name: String
            let standard: Bool
            let deep: Bool
            let off: Set<RetrievalAblation.Rule>
        }
        let configs: [Config] = (environment["OI_EVIDENCE_CONFIGS"] ?? "").split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { return nil }
            return Config(
                name: parts[0], standard: parts[1].contains("s"), deep: parts[1].contains("d"),
                off: RetrievalAblation.parse(parts[2].replacingOccurrences(of: "+", with: ",")))
        }
        let runs = configs.isEmpty ? [Config(name: label, standard: true, deep: true, off: RetrievalAblation.off)] : configs
        let slice = (environment["OI_EVIDENCE_SLICE"] ?? "0/1").split(separator: "/").compactMap { Int($0) }
        let (sliceIndex, sliceCount) = slice.count == 2 && slice[1] > 0 ? (slice[0], slice[1]) : (0, 1)
        let mine = questions.enumerated().filter { $0.offset % sliceCount == sliceIndex }.map(\.element)

        var results: [String: [[String: Any]]] = [:]
        let started = Date()
        addTeardownBlock { RetrievalAblation.overrideOff = nil }
        for (number, question) in mine.enumerated() {
            for config in runs {
                RetrievalAblation.overrideOff = config.off
                var entry: [String: Any] = ["qid": question.qid]
                if config.standard {
                    engine.clearChatHistory(for: library.id)
                    ConversationMemoryService.shared.clearMemory(for: library.id)
                    _ = await SQLiteFullTextService.shared.deleteAllCachedQueries()
                    model.contexts = []
                    do {
                        let (response, _) = try await engine.queryWithAudit(
                            question.query, containerId: library.id, qualityModeOverride: .standard,
                            externalEvidence: nil, trace: nil)
                        // The answer's own call is the first; later calls (a citation retry, a repair) are handed
                        // shorter contexts. On 2026-11-09 the trial scored the last and read 745 of the 4,300
                        // characters assembled.
                        entry["standardContext"] = model.contexts.first ?? ""
                        entry["modelCalls"] = model.contexts.count
                        entry["standardSources"] = response.retrievedChunks.map(\.chunk.content)
                        if realModel { entry["answer"] = response.generatedResponse }
                    } catch {
                        entry["standardError"] = String(describing: error)
                    }
                    for _ in 0..<50 {
                        if !ConversationMemoryService.shared.memory(for: library.id).recentTurns.isEmpty { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                if config.deep {
                    let deep = try await engine.executeFullRetrievalPipeline(
                        query: question.query, topK: 15, minSimilarity: 0.05, qualityMode: .deepThink)
                    entry["deepThink"] = deep.map(\.chunk.content)
                }
                results[config.name, default: []].append(entry)
            }
            if number % 10 == 9 {
                RerankScoreCache.shared.save()
                print("[EvidenceReach] slice \(sliceIndex)/\(sliceCount): \(number + 1) of \(mine.count) questions, "
                    + "\(Int(Date().timeIntervalSince(started))) s")
            }
        }
        RetrievalAblation.overrideOff = nil
        RerankScoreCache.shared.save()
        let suffix = sliceCount > 1 ? "-s\(sliceIndex)" : ""
        for config in runs {
            try GoldenRecording.write(
                [
                    "label": config.name, "passages": stored, "seconds": Date().timeIntervalSince(started),
                    "slice": "\(sliceIndex)/\(sliceCount)", "paths": (config.standard ? "s" : "") + (config.deep ? "d" : ""),
                    "rerankCacheHits": RerankScoreCache.shared.hits, "rerankCacheMisses": RerankScoreCache.shared.misses,
                    "ablated": config.off.map(\.rawValue).sorted(), "results": results[config.name] ?? [],
                ],
                to: dir.appendingPathComponent("reach-\(config.name)\(suffix).json"))
        }
    }
}
