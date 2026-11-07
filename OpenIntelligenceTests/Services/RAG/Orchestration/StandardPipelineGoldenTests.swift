//
//  StandardPipelineGoldenTests.swift
//  OpenIntelligenceTests
//
//  Records exactly what a Standard question produces, end to end through `RAGService.queryInternal`: the answer as
//  the app returns it, the audit snapshot, the retrieval trace's stages, and every call made to the model with a
//  fingerprint of its prompt and context. It exists so breaking `queryInternal` into steps (2026-11-06,
//  `BenchmarkRuns/2026-11-06-decomposition/PLAN.md`) can be shown to change nothing: record before, record after,
//  compare with `scripts/golden_compare.py`.
//
//  The model is a stand-in, a subclass of `AppleFoundationLLMService` so the pipeline takes the branches it takes for
//  Apple's model (it asks `is AppleFoundationLLMService` in several places). It answers with the first line of the
//  context it was given and a fingerprint of the whole prompt, so a change to what retrieval found, how it was packed
//  or how the prompt was built changes the recording; a question containing `[[golden-fail]]` makes it throw, which
//  reaches the pipeline's error path. Calls that reach Apple's model some other way are not intercepted; the two
//  passes would disagree if one of them answered differently, and the test fails in that case.
//
//  Run only on purpose: it needs `TEST_RUNNER_OI_GOLDEN_DIR` with `standard-fixtures/` (`scripts/golden_compare.py
//  prepare <dir>`), and skips without it. The library "Golden standard" is imported once and reused, so every run
//  asks the same stored passages; its passage digests are recorded so a rebuilt library shows.
//

import XCTest

@testable import OpenIntelligence

@available(iOS 26.0, macOS 26.0, *)
final class GoldenEchoModel: AppleFoundationLLMService {
    struct Call {
        let kind: String
        let prompt: String
        let context: String
        let config: String
        /// The prompt itself, ids replaced, so a difference names the words that moved.
        let promptText: String
    }
    var calls: [Call] = []

    override var isAvailable: Bool { true }
    override var modelName: String { "golden-echo" }

    private func answer(
        _ kind: String, _ prompt: String, _ context: String?, _ config: InferenceConfig
    ) throws
        -> LLMResponse
    {
        let fingerprint = GoldenRecording.digest(prompt + "\u{1}" + (context ?? ""))
        calls.append(
            Call(
                kind: kind, prompt: GoldenRecording.digest(prompt), context: GoldenRecording.digest(context ?? ""),
                config: "\(GoldenRecording.reflect(config, dropping: [], ids: GoldenRecording.Ids()))",
                promptText: GoldenRecording.idsReplaced(prompt)))
        if prompt.contains("[[golden-fail]]") {
            throw LLMError.generationFailed("golden stand-in failure")
        }
        let lead =
            (context ?? prompt).split(separator: "\n").first { $0.count > 24 }.map { String($0.prefix(220)) } ?? ""
        return LLMResponse(
            text: "\(lead) [golden \(fingerprint)]", tokensGenerated: 32, timeToFirstToken: nil, totalTime: 0,
            modelName: "golden-echo", toolCallsMade: 0)
    }

    override func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        try answer("generate", prompt, context, config)
    }

    override func generateStructuredRAGAnswer(
        prompt: String, context: String, config: InferenceConfig, sourceCount: Int, mode: StructuredRAGMode = .direct
    ) async throws -> LLMResponse {
        try answer("structured-\(mode)-\(sourceCount)", prompt, context, config)
    }
}

@MainActor
final class StandardPipelineGoldenTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private static let libraryName = "Golden standard"
    private static let emptyLibraryName = "Golden empty"

    /// Keys that hold a clock time, a duration or a per-run value beyond what `GoldenRecording.isVolatile` drops.
    private static let volatileKeys: Set<String> = []

    /// The household benchmark's 20 questions (`BenchmarkRuns/household_v1/manifest.json`: 17 exact values, 3 with no
    /// answer in the documents), then questions chosen to reach the pipeline's other exits.
    private static let questions: [String] = [
        "When is my rent late, and what's the fee?",
        "What does E1 mean on my air fryer?",
        "What does Brightwater match on my 401(k)?",
        "How much notice do I have to give before I move out?",
        "When can my kid go back to school after a fever?",
        "A pipe burst in my kitchen. Am I covered?",
        "How do I clean the air fryer basket?",
        "Can I grill on my balcony?",
        "How do I cancel my gym membership?",
        "How long do I bake Grandma's banana bread, and at what temperature?",
        "When does my flight to Lisbon leave?",
        "Can I have a dog in my apartment?",
        "Which parking space is mine?",
        "How much is my rent, and when is it due?",
        "What happens when my lease term ends?",
        "How much is added each day rent stays late after the 6th?",
        "What is my flight number to Lisbon?",
        "Can I paint my bedroom walls?",
        "What is the Wi-Fi password for my apartment?",
        "What is my car insurance deductible?",
        "Summarize my lease.",
        "Compare my gym membership agreement with my lease: which one is harder to cancel?",
        "List every fee mentioned in my documents.",
        "What are the error codes on the air fryer and what does each one mean?",
        "hi",
        "Thanks!",
        "What does the school handbook say about attendance, and what does my insurance say about water damage?",
        "rent",
        "What is my rent? [[golden-fail]]",
    ]

    func testRecordStandardPipeline() async throws {
        let (dir, label) = try GoldenRecording.destination()
        let fixtureDir = dir.appendingPathComponent("standard-fixtures")
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
        // Two readings of the environment held fixed for the run, because the pipeline decides on them and in the
        // Simulator they changed between questions on 2026-11-06. The network went from connected to not: while it
        // read connected the route allowed a large context and took the Private Cloud Compute window, which the
        // Simulator reports as 0 (an 800-character budget, 2 passages); once it read disconnected the on-device window
        // applied (8,192 here, 19 passages). Held disconnected, every question takes the on-device route, the default
        // on a phone, and the on-device window is held at 4,096, the one Apple documents.
        FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = 4096
        NetworkMonitor.shared.holdForTesting(false)
        // Services that call Apple's model directly take their no-model path (`DirectModelCallsForTesting`): in the
        // Simulator the model answers in different words each time, which changed the plan and the prompt between
        // two passes on 2026-11-06.
        DirectModelCallsForTesting.disabled = true
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
        // `TEST_RUNNER_OI_GOLDEN_REBUILD=1` rebuilds the library, after a change to how it is built.
        let rebuild = ProcessInfo.processInfo.environment["OI_GOLDEN_REBUILD"] == "1"
        if rebuild || Set(documents(in: library.id).map(\.filename)) != fixtureNames
            || engine.ingestionItems.contains(where: { $0.containerId == library.id })
        {
            // Built once, without overviews (they come from a model call), then reused.
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
        // Overviews left for later (`deferredEnrichments`) are written as passages when the app is idle. On 2026-11-06
        // two arrived during one run (112 passages, then 114), so the second pass searched a different library. Run
        // them all now, as `DeepThinkRetrievalGoldenTests` does, before anything is asked.
        for _ in 0..<1800 {
            let waiting = RAGService.deferredEnrichments().contains { $0.library == library.id }
            if !waiting { break }
            engine.runDeferredEnrichmentsIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertFalse(
            RAGService.deferredEnrichments().contains { $0.library == library.id },
            "the golden library's overviews never finished")
        let db = try await engine.dbForContainer(library.id)
        var counts: [Int] = []
        for _ in 0..<600 {
            let busy = engine.ingestionItems.contains { $0.containerId == library.id && !$0.stage.isTerminal }
            counts.append(try await db.readableChunks().count)
            if !busy, counts.count >= 5, Set(counts.suffix(5)).count == 1, counts.last! > 0 { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let stored = try await db.readableChunks()
        XCTAssertFalse(stored.isEmpty, "the golden library holds no passages")
        // Everything a search reads from a passage: its text, the context prefix, the parent text and the vector.
        // On 2026-11-06 a rebuilt library gained context prefixes after its first run, which a digest of the text
        // alone did not show.
        func passageDigest(_ chunk: DocumentChunk) -> String {
            let vector = chunk.embedding.map { "\($0.bitPattern)" }.joined(separator: ",")
            return GoldenRecording.digest(
                [chunk.content, chunk.contextualPrefix ?? "", chunk.parentContent ?? "", vector].joined(separator: "\u{1}"))
        }
        let libraryDigest = GoldenRecording.digest(stored.map(passageDigest).sorted().joined(separator: ","))
        let empty =
            try libraries.containers.first { $0.name == Self.emptyLibraryName }
            ?? libraries.createContainer(name: Self.emptyLibraryName)
        XCTAssertTrue(documents(in: empty.id).isEmpty, "the empty golden library holds documents")

        // The keyword index is a local cache the app rebuilds from the library at launch, in a task of its own
        // (`RAGService.rebuildLocalSearchIndexesFromCanonicalState`), and the Simulator gives the app a new data folder
        // on every test run, so every run starts with that rebuild. On 2026-11-06 the first questions ran while it was
        // still going, BM25 read partial totals, and the keyword list's order differed between runs. Wait until every
        // document has its keyword rows and the count holds for five seconds.
        let documentCountHere = documents(in: library.id).count
        var keywordRows: [Int] = []
        for _ in 0..<300 {
            let indexed = await SQLiteFullTextService.shared.documentCount(for: library.id)
            var rows = 0
            for document in documents(in: library.id) {
                rows += await SQLiteFullTextService.shared.retrieveChunks(for: document.id).count
            }
            keywordRows.append(rows)
            if indexed == documentCountHere, rows > 0, keywordRows.count >= 5, Set(keywordRows.suffix(5)).count == 1 {
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let model = GoldenEchoModel()
        engine._llmService = model
        libraries.setActive(library.id)

        func ask(
            _ question: String, in libraryId: UUID, clearCache: Bool = true, external: [EvidenceSource]? = nil
        ) async -> [String: Any] {
            engine.clearChatHistory(for: libraryId)
            ConversationMemoryService.shared.clearMemory(for: libraryId)
            if clearCache { _ = await SQLiteFullTextService.shared.deleteAllCachedQueries() }
            model.calls = []
            let ids = GoldenRecording.Ids()
            let trace = RetrievalTraceCollector()
            var entry: [String: Any] = [:]
            do {
                let (response, audit) = try await engine.queryWithAudit(
                    question, containerId: libraryId, qualityModeOverride: .standard, externalEvidence: external,
                    trace: trace)
                entry["response"] = GoldenRecording.reflect(response, dropping: Self.volatileKeys, ids: ids)
                entry["audit"] =
                    audit.map { GoldenRecording.reflect($0, dropping: Self.volatileKeys, ids: ids) }
                    ?? NSNull()
            } catch {
                entry["threw"] = String(describing: error)
            }
            // Each stage as its passages in order: a fingerprint of the text and the score's bits. The answer above
            // carries the passages it used in full; this keeps the stages readable (the full trace was 18 MB).
            // The answer's turn is saved to conversation memory in a task of its own, which on 2026-11-06 landed after
            // the next question had cleared memory, so that question's prompt carried this answer ("Assistant: ...").
            // Wait for it, so every question starts from an empty memory.
            for _ in 0..<50 {
                if !ConversationMemoryService.shared.memory(for: libraryId).recentTurns.isEmpty { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            entry["trace"] = trace.stages.map { stage in
                [stage.stage] + stage.results.map {
                    "\(GoldenRecording.digest($0.chunk.content))|\($0.similarityScore.bitPattern)|\($0.rank)|\($0.sourceDocument)"
                }
            }
            entry["calls"] = model.calls.map {
                ["kind": $0.kind, "prompt": $0.prompt, "context": $0.context, "config": $0.config, "promptText": $0.promptText]
            }
            return entry
        }

        func pass() async -> [String: Any] {
            var out: [String: Any] = [:]
            for (i, question) in Self.questions.enumerated() {
                out[String(format: "%02d %@", i, question)] = await ask(question, in: library.id)
            }
            // The same question again with the search cache kept: the exact-cache-hit path.
            out["cache: first"] = await ask("Which parking space is mine?", in: library.id)
            out["cache: hit"] = await ask("Which parking space is mine?", in: library.id, clearCache: false)
            // Evidence the caller brings, as the camera and the scanner do: text read from an image, and a barcode.
            let seen = VisualEvidenceMetadata(
                timestamp: Date(timeIntervalSince1970: 0), ocrWordCount: 9, barcodeCount: 0, detectedObjects: [],
                boundingBoxes: nil)
            out["external: OCR"] = await ask(
                "What does this label say about the filter?", in: library.id,
                external: [.imageOCR("Replace the air fryer filter every 30 uses. Model AF-620.", seen)])
            out["external: barcode"] = await ask(
                "What is this product?", in: library.id, external: [.barcode("0012345678905")])
            out["empty: What is my rent?"] = await ask("What is my rent?", in: empty.id)
            out["empty: hi"] = await ask("hi", in: empty.id)
            return out
        }

        // `TEST_RUNNER_OI_GOLDEN_PASSES=1` records one pass, for runs after a baseline has shown the two passes agree.
        let passes = Int(ProcessInfo.processInfo.environment["OI_GOLDEN_PASSES"] ?? "") ?? 2
        let first = await pass()
        let second = passes > 1 ? await pass() : first
        XCTAssertFalse(model.calls.isEmpty && first.isEmpty, "the stand-in model was never called")
        let passagesAfter = try await db.readableChunks().count
        XCTAssertEqual(passagesAfter, stored.count, "the library changed during the run, so the passes are not comparable")
        let unsteady = GoldenRecording.differences(first, second, limit: 400)
        XCTAssertTrue(unsteady.isEmpty, "two passes in one run differ: \(unsteady)")
        try GoldenRecording.write(
            [
                "hashing": ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] ?? "unset",
                "setOrder": Array(Set(["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"])).joined(separator: ","),
                "keywordRows": keywordRows.last ?? 0,
                "label": label, "passages": stored.count, "passagesAfter": passagesAfter, "library": libraryDigest,
                "unsteady": unsteady,
                "results": first,
            ],
            to: dir.appendingPathComponent("standard-\(label).json"))
    }
}
