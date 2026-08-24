#if DEBUG
import Foundation

enum DebugRAGValidationHarness {
    private final class RunGate: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !started else { return false }
            started = true
            return true
        }
    }

    struct Configuration: Sendable {
        let query: String
        let inputURLs: [URL]
        let storageDirectory: URL
        let outputDirectory: URL
        let qualityMode: RAGQualityMode?
        let shouldIngest: Bool
        let pccConsent: String?
        let benchmarkEntitlement: WorkspaceTier?
        /// Ground-truth source filenames for this query, from the eval case's `expectedCitations`.
        ///
        /// Empty for an ad hoc run, and empty for the negative-control abstention cases, which have
        /// no correct source by construction. When empty no stage metrics are emitted at all, so an
        /// unscored run is distinguishable from one that scored zero.
        ///
        /// Declared `var` with a default so the synthesised memberwise initialiser keeps a default
        /// for it: `ValidationDashboardViewModel` builds this type in two places and a required
        /// parameter would break them. A `let` with an initial value would instead be dropped from
        /// the initialiser and pinned empty forever, silently disabling stage metrics.
        var expectedSources: [String] = []

        /// Final retrieval breadth, the `topK` handed to `queryWithAudit`.
        ///
        /// Defaults to nil, which leaves `queryWithAudit`'s own default of 3 in place. That
        /// default is also what the chat UI uses (`@AppStorage("retrievalTopK") = 3`), so an
        /// unflagged benchmark run measures shipped behaviour rather than a benchmark-only
        /// setting. This exists to sweep that value: the 2026-08-12 run showed the right document
        /// reaching the final ranking on 75% of *missed* cases, so the answer is arriving and
        /// being truncated away.
        var retrievalTopK: Int? = nil
    }

    static let cachedConfiguration: Configuration? = makeConfiguration()
    private static let runGate = RunGate()
    static var lastReport: String? = nil

    static var isEnabled: Bool {
        cachedConfiguration != nil
    }

    static var isVisualModeEnabled: Bool {
        cachedConfiguration != nil && (LaunchArguments.has("--rag-validation-visual") || LaunchArguments.has("rag-validation-visual"))
    }

    static func configureStorageIfNeeded() {
        guard let configuration = cachedConfiguration else { return }
        // Pinned, not merely configured. `WorkspaceSyncService.init` runs `activateLocalWorkspace`,
        // which calls `configureBaseDir(nil)` and was silently destroying this override, so every
        // benchmark write landed in the owner's real library no matter what storage the harness was
        // given. The pin also aims LocalCache into the sandbox: `localCacheDirectory()` falls back
        // to the real root rather than to the base override, which is how benchmark FTS5 writes
        // reached the owner's real index on every run.
        AppSupportPaths.pinRuntimeDirectories(
            base: configuration.storageDirectory,
            localCache: configuration.storageDirectory.appendingPathComponent("LocalCache", isDirectory: true)
        )
        seedPCCConsentIfNeeded(configuration.pccConsent)
        seedBenchmarkEntitlementIfNeeded(configuration.benchmarkEntitlement)
        seedHybridWeightIfNeeded()
        seedEmbeddingProviderIfNeeded()
        seedSamplingOverridesIfNeeded()
    }

    /// Seed the fusion-weight override before any query builds a profile.
    ///
    /// Written to UserDefaults rather than threaded through `Configuration` because
    /// `QueryProfileService` computes weights deep inside retrieval and does not see the harness.
    /// Removed when the flag is absent, so a stale value from an earlier run cannot silently
    /// change a later one.
    private static func seedHybridWeightIfNeeded() {
        guard let raw = LaunchArguments.valueEither(for: "rag-validation-vector-weight"),
              let value = Double(raw), value >= 0, value <= 1
        else {
            UserDefaults.standard.removeObject(forKey: "benchmarkVectorWeight")
            return
        }
        UserDefaults.standard.set(value, forKey: "benchmarkVectorWeight")
    }

    /// `--rag-validation-embedding-provider <id>` forces one embedding provider for a run.
    ///
    /// Needed because the two providers are not interchangeable and nothing in the run output said
    /// which one produced the vectors. Core AI extracts the CLS token from a single-input model;
    /// Core ML mean-pools a three-input model with an attention mask. `all-MiniLM-L6-v2` is a
    /// mean-pooling model, so comparing an embedder swap without pinning this would compare two
    /// different things.
    private static func seedEmbeddingProviderIfNeeded() {
        guard let raw = LaunchArguments.valueEither(for: "rag-validation-embedding-provider")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            UserDefaults.standard.removeObject(forKey: "benchmarkEmbeddingProvider")
            return
        }
        UserDefaults.standard.set(raw, forKey: "benchmarkEmbeddingProvider")
    }

    /// Seed the sampling override, so two runs of the same build are comparable to each other.
    ///
    /// `InferenceConfig.samplingStrategy` defaults to `.topK` with `seed` nil, which means every run
    /// draws a different sample. Measured consequence: one case returned 3613, then 68, then 3357
    /// characters across three runs whose code differences cannot account for the swing. That noise
    /// is larger than most effects worth measuring, so without this an A/B is not imprecise, it is
    /// unreadable.
    ///
    /// Same UserDefaults mechanism as the fusion weight above, and for the same reason: the value is
    /// consumed deep inside `LLMService` where `GenerationOptions` is built, which is the single
    /// point every on-device generation passes through. Both keys are removed when their flag is
    /// absent so a stale value cannot silently change a later run.
    ///
    /// Three flags, answering three different questions:
    ///   - `--rag-validation-sampling greedy` for maximum reproducibility. Greedy always takes the
    ///     highest-probability token, so it also **ignores temperature entirely**.
    ///   - `--rag-validation-seed` for a reproducible *stochastic* run. This is what a temperature
    ///     comparison needs: greedy would produce identical output in both arms and a null result
    ///     that means nothing, so the draws are held fixed and only the distribution changes.
    ///   - `--rag-validation-temperature` for the quality question itself.
    private static func seedSamplingOverridesIfNeeded() {
        if let raw = LaunchArguments.valueEither(for: "rag-validation-sampling")?.lowercased(),
           ["greedy", "topk", "topp"].contains(raw) {
            UserDefaults.standard.set(raw, forKey: "benchmarkSamplingStrategy")
        } else {
            UserDefaults.standard.removeObject(forKey: "benchmarkSamplingStrategy")
        }

        if let raw = LaunchArguments.valueEither(for: "rag-validation-seed"),
           let value = UInt64(raw) {
            UserDefaults.standard.set(NSNumber(value: value), forKey: "benchmarkSamplingSeed")
        } else {
            UserDefaults.standard.removeObject(forKey: "benchmarkSamplingSeed")
        }

        if let raw = LaunchArguments.valueEither(for: "rag-validation-temperature"),
           let value = Double(raw), value >= 0, value <= 2 {
            UserDefaults.standard.set(value, forKey: "benchmarkTemperature")
        } else {
            UserDefaults.standard.removeObject(forKey: "benchmarkTemperature")
        }
    }

    static func runHeadlessIfNeeded() {
        guard cachedConfiguration != nil else { return }
        
        // If they requested visual mode, bypass the headless runner and let the UI handle it!
        if LaunchArguments.has("--rag-validation-visual") || LaunchArguments.has("rag-validation-visual") {
            return
        }
        
        configureStorageIfNeeded()

        Task { @MainActor in
            let containerService = ContainerService()
            let billingService = StoreKitBillingService()
            let entitlementStore = EntitlementStore(billingService: billingService)
            let ragService = RAGService(containerService: containerService, entitlementStore: entitlementStore)
            let settingsStore = SettingsStore(ragService: ragService)

            do {
                // Only the caller that actually ran may terminate the process. Exiting on `nil`
                // would kill the run the other path is in the middle of.
                guard let report = try await runIfNeeded(
                    ragService: ragService,
                    settingsStore: settingsStore
                ) else { return }
                print(report)
                fflush(stdout)
                exit(0)
            } catch {
                if let errorReport = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String {
                    print(errorReport)
                } else {
                    print(error.localizedDescription)
                }
                fflush(stdout)
                exit(1)
            }
        }
    }

    /// Runs the validation once, or returns `nil` if another caller already owns this run.
    ///
    /// The `nil` is load-bearing and used to be a plain string, which killed every run on iOS.
    /// Two paths call this: `runHeadlessIfNeeded` from `App.init`, and `ContentView` once its
    /// task starts. Only one can claim the gate. The loser used to receive
    /// `"No configuration or already running."`, and `runHeadlessIfNeeded` could not tell that
    /// apart from a finished report, so it printed the sentence and called `exit(0)` while the
    /// winner was still working. On macOS the headless path happens to claim first and the bug
    /// stays hidden; on the simulator `ContentView` claims first, so the app terminated a few
    /// seconds in with `ValidationOutput/` created and no report ever written.
    static func runIfNeeded(
        ragService: RAGService,
        settingsStore: SettingsStore
    ) async throws -> String? {
        guard let configuration = cachedConfiguration, runGate.claim() else { return nil }
        return try await run(configuration: configuration, ragService: ragService, settingsStore: settingsStore)
    }

    static func run(
        configuration: Configuration,
        ragService: RAGService,
        settingsStore: SettingsStore
    ) async throws -> String {

        let previousMode = settingsStore.ragQualityMode
        let previousTraceSetting = settingsStore.enablePipelineTrace

        settingsStore.enablePipelineTrace = true
        if let qualityMode = configuration.qualityMode {
            settingsStore.ragQualityMode = qualityMode
        }

        defer {
            settingsStore.ragQualityMode = previousMode
            settingsStore.enablePipelineTrace = previousTraceSetting
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: configuration.outputDirectory, withIntermediateDirectories: true)
        let reportURL = configuration.outputDirectory.appendingPathComponent("rag_validation_report.txt")

        Log.info("[RAGValidation] Starting validation run", category: .pipeline)
        Log.info("[RAGValidation] Storage: \(configuration.storageDirectory.path)", category: .pipeline)
        
        let storageString = "[RAGValidation] Storage: \(configuration.storageDirectory.path)\n"
        fputs(storageString, stdout)
        fflush(stdout)
        
        Log.info("[RAGValidation] Output: \(reportURL.path)", category: .pipeline)

        do {
            var ingestionResult: IngestionBatchResult?
            if configuration.shouldIngest, !configuration.inputURLs.isEmpty {
                Log.info("[RAGValidation] Ingesting \(configuration.inputURLs.count) document(s)", category: .ingestion)
                ingestionResult = await ragService.ingestDocuments(configuration.inputURLs)
            }

            let containerId = await MainActor.run { ragService.containerService.activeContainerId }
            let containerName = await MainActor.run {
                ragService.containerService.activeContainer?.name ?? "Unknown"
            }
            // One collector per query. Retrieval stages are captured even when generation later
            // produces nothing, which is the point: the 2026-07-30 matrix run could not measure
            // deep-think or maximum at all because no answer came back, yet retrieval had run on
            // every one of those cases and was simply never observed.
            let trace = RetrievalTraceCollector()
            // `topK` is passed only when the flag supplied one, so an unflagged run keeps
            // `queryWithAudit`'s own default of 3 and therefore measures shipped behaviour.
            let (response, auditSnapshot) = try await ragService.queryWithAudit(
                configuration.query,
                topK: configuration.retrievalTopK ?? 3,
                containerId: containerId,
                trace: trace
            )

            Log.flushTraceLog()
            let copiedTraceURL = copyTraceLog(into: configuration.outputDirectory)
            // Read after the query so anything ingested this launch is included. These resolve
            // expected filenames to document ids without relying on `sourceDocument`, which only
            // the same-launch ingestion path fills in.
            let knownDocuments = await MainActor.run { ragService.documents }

            // `--rag-validation-questions` exercises the suggested-question chips headlessly.
            //
            // This path had no coverage of any kind. The harness only ever ran queries, so the
            // questions offered before the user types anything were changed on 2026-08-15 and
            // verified by compiling. Apple Foundation Models runs on this Mac exactly as it does on
            // a phone, so "test it on a device" was the wrong framing: what was missing was a way to
            // invoke the path at all, not different hardware.
            if LaunchArguments.has("--rag-validation-questions") || LaunchArguments.has("rag-validation-questions") {
                let sampleChunks = response.retrievedChunks.map(\.chunk)
                let questions = await SuggestedQuestionsService.shared.generateQuestions(
                    for: containerId,
                    documents: knownDocuments,
                    sampleChunks: sampleChunks,
                    count: 6,
                    forceRefresh: true
                )
                Log.info(
                    "[SuggestedQuestionsProbe] \(questions.count) questions from "
                        + "\(sampleChunks.count) chunks across \(knownDocuments.count) document(s)",
                    category: .llm
                )
                for (index, question) in questions.enumerated() {
                    Log.info(
                        "[SuggestedQuestionsProbe] \(index + 1). \(question.text) "
                            + "[category: \(question.category), llm: \(question.isLLMGenerated), "
                            + "confidence: \(String(format: "%.2f", question.confidence))]",
                        category: .llm
                    )
                }
                if questions.isEmpty {
                    Log.warning("[SuggestedQuestionsProbe] produced NO questions", category: .llm)
                }
            }

            let report = buildReport(
                configuration: configuration,
                containerId: containerId,
                containerName: containerName,
                ingestionResult: ingestionResult,
                response: response,
                auditSnapshot: auditSnapshot,
                copiedTraceURL: copiedTraceURL,
                trace: trace,
                knownDocuments: knownDocuments
            )
            Self.lastReport = report
            try report.write(to: reportURL, atomically: true, encoding: .utf8)

            Log.info("[RAGValidation] Report written to \(reportURL.path)", category: .pipeline)
            if let copiedTraceURL {
                Log.info("[RAGValidation] Trace copied to \(copiedTraceURL.path)", category: .pipeline)
            }
            return report
        } catch {
            Log.error("[RAGValidation] Validation failed: \(error.localizedDescription)", category: .pipeline)
            Log.flushTraceLog()
            let copiedTraceURL = copyTraceLog(into: configuration.outputDirectory)
            let errorReport = buildErrorReport(
                configuration: configuration,
                error: error,
                copiedTraceURL: copiedTraceURL
            )
            Self.lastReport = errorReport
            try? errorReport.write(to: reportURL, atomically: true, encoding: .utf8)
            throw NSError(domain: "RAGValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: errorReport])
        }
    }

    /// Per-stage retrieval metrics, plus the evidence they were computed from.
    ///
    /// Two blocks are emitted on purpose. `STAGE METRICS` is the scored result, computed by
    /// `RetrievalStageEvaluator`, which is the same unit-tested implementation the in-app runner
    /// uses, so there is exactly one metric implementation in the project rather than a Swift one
    /// and a re-derived Python one that can drift apart. `STAGE SOURCES` lists what each stage
    /// returned, in rank order, as `<chunkId>#<documentId>#<name>`, so any number in the first
    /// block can be recomputed by hand from the second. A benchmark that cannot be checked is an
    /// assertion, not a measurement.
    ///
    /// The ids are what make that true. Printing the name alone satisfied this comment for rerank
    /// and final and quietly failed it for the five stages before them, which carry no name yet.
    /// Recording identity in rank order also makes the two fusion inputs replayable, so a different
    /// fusion weight can be scored from a finished run instead of costing another one. See the
    /// comment on the emit itself for why both ids are needed rather than either alone.
    ///
    /// Nothing is emitted when there are no expected sources. The two negative-control cases have
    /// none by construction, and scoring them would report a meaningless 0.0 that would then be
    /// averaged into the aggregate.
    /// Filename to document id, for the documents the service currently holds.
    ///
    /// Resolution below prefers this over scanning retrieved chunks, because `sourceDocument` is
    /// only populated for documents ingested in the same launch. With
    /// `--rag-validation-skip-ingest` every chunk carries an empty name, so a chunk-only lookup
    /// resolved nothing, every expected filename stayed a filename, and the run scored 0.0000 at
    /// every stage while retrieval was in fact working. That made index reuse unusable and forced
    /// each case to re-ingest the whole distractor pool: 83 cases at roughly three minutes each,
    /// against about fifteen minutes for the same pack over one shared index.
    private static func documentIdsByName(_ documents: [Document]) -> [String: UUID] {
        var map: [String: UUID] = [:]
        for document in documents {
            let stem = RetrievalRelevanceJudge.documentStem(document.filename)
            guard !stem.isEmpty else { continue }
            // First writer wins, so a later `-N` duplicate of the same source cannot displace the
            // original. Ingesting the same file twice is normal here and must not change scoring.
            if map[stem] == nil { map[stem] = document.id }
        }
        return map
    }

    /// How many candidates per stage `STAGE SOURCES` records.
    ///
    /// Re-deriving the metrics in the block above needs only 10, because that is the deepest
    /// cutoff. Re-deriving a *different* fusion weight from the same run needs more: an item
    /// ranked below the cap in one arm can be lifted into the top 10 by reweighting, and a list
    /// truncated above it cannot show that. This was 20, which was correct for the first purpose
    /// and too shallow for the second.
    private static let stageSourceDepth = 100

    private static func stageMetricsLines(
        trace: RetrievalTraceCollector?,
        expectedSources: [String],
        response: RAGResponse,
        knownDocuments: [Document] = []
    ) -> [String] {
        guard let trace, !expectedSources.isEmpty else { return [] }
        let traces = trace.stages(inOrder: RetrievalTraceCollector.Stage.allCases)
        guard !traces.isEmpty else { return [] }

        // Resolve each expected filename to the document UUID it was ingested as, and score against
        // both. This is required, not defensive: `sourceDocument` is attached by `RAGService` after
        // hybrid search returns, so the first five stages carry an empty filename and can only be
        // judged by identifier. The final chunks carry both, which is what makes the mapping
        // available here at all. Without this, a run whose answers were all correct reported
        // `0.0000` at every stage of every case.
        // Each expected filename is REPLACED by its document UUID where one can be resolved, never
        // appended to. Appending would make one expected document count as two entries in the
        // denominator and halve every recall figure. An unresolvable filename is kept as-is and
        // scores zero, which is the right answer: it was never retrieved anywhere in the pipeline.
        //
        // Resolution scans every recorded stage, not just `response.retrievedChunks`. The response
        // can be empty while retrieval succeeded — observed on `exact_capex`, where `rerank` held
        // the correct document at rank 1 and `final` delivered nothing — and resolving from the
        // response alone would then fail and report the early stages as a miss, hiding the fact
        // that retrieval worked and a later filter threw the result away. The late stages carry
        // names, the early ones carry ids, and every stage carries the same `documentId`.
        let allChunks = traces.flatMap(\.results) + response.retrievedChunks
        let byName = documentIdsByName(knownDocuments)
        let groundTruth: [String] = expectedSources.map { expected in
            // Persisted metadata first: it is available whether or not this launch did the
            // ingesting, which is what makes a reused index scorable.
            if let id = byName[RetrievalRelevanceJudge.documentStem(expected)] {
                return id.uuidString
            }
            let resolved = allChunks.first { RetrievalRelevanceJudge.matches($0, expected: expected) }
            return resolved?.chunk.documentId.uuidString ?? expected
        }

        let metrics = RetrievalStageEvaluator.score(traces: traces, expectedSources: groundTruth)
        func f(_ value: Double) -> String { String(format: "%.4f", value) }

        var lines: [String] = []
        lines.append("STAGE METRICS")
        lines.append("ExpectedSources: \(expectedSources.joined(separator: "|"))")
        // The resolved form, which is what scoring actually compared against. The line above is the
        // manifest's filenames, which is what a reader recognises; this is the document id each one
        // became, and the only form that joins to the ids in STAGE SOURCES below. Emitting the
        // first alone left the two halves of this report unjoinable.
        //
        // An entry still in filename form here did not resolve to any ingested document. That scores
        // zero at every stage, and it is worth being able to tell that apart from a retrieval miss,
        // because the cause and the fix are entirely different.
        lines.append("ExpectedSourceIds: \(groundTruth.joined(separator: "|"))")
        lines.append("stage\tresults\trelevant\tr1\tr3\tr5\tr10\tmrr\tndcg5\tndcg10\tp5")
        for m in metrics {
            lines.append(
                [
                    m.stage, "\(m.resultCount)", "\(m.relevantCount)",
                    f(m.recallAt1), f(m.recallAt3), f(m.recallAt5), f(m.recallAt10),
                    f(m.reciprocalRank), f(m.ndcgAt5), f(m.ndcgAt10), f(m.precisionAt5),
                ].joined(separator: "\t")
            )
        }
        lines.append("")

        // Each entry is `<chunkId>#<documentId>#<name>`, split on the first two `#` so a name
        // containing one cannot corrupt the ids ahead of it.
        //
        // Both ids are required and they answer different questions. `RAGEngine.reciprocalRankFusion`
        // keys on `chunk.id`, so replaying the fusion at a different weight needs chunk identity:
        // two chunks of one document are separate entities there, and document ids alone cannot say
        // which vector entry pairs with which lexical entry. Relevance is judged per document, so
        // scoring needs `documentId`. Emitting one without the other makes the block able to answer
        // only half of what it is for.
        //
        // The ids lead because they are the only fields every stage carries. `sourceDocument` is
        // attached by `RAGService` after hybrid search returns, so this block previously printed
        // `(unnamed)` for vector, lexical, fusion, boosted and candidates: the five stages where
        // every retrieval decision is made. It could therefore verify only rerank and final, the
        // two stages nobody was questioning, while the doc comment above claimed any figure could
        // be recomputed from it. The metrics themselves were never affected, because `groundTruth`
        // is resolved to ids before scoring a few lines up, so this was a hole in the audit trail
        // rather than in the numbers.
        lines.append("STAGE SOURCES")
        for t in traces {
            let sources = t.results.prefix(stageSourceDepth).map { result -> String in
                let name = result.sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines)
                return [
                    result.chunk.id.uuidString,
                    result.chunk.documentId.uuidString,
                    name.isEmpty ? "-" : name,
                ].joined(separator: "#")
            }
            lines.append("\(t.stage)\t\(sources.joined(separator: "|"))")
        }
        lines.append("")

        // STAGE SOURCES above has ids for every stage, but text only for final (RETRIEVED CHUNK
        // TEXT, on the response). That makes the 10-of-24 cases where the gold span never reaches
        // the model unattributable: unretrieved and cut-during-assembly both look identical from a
        // saved run. Emitting rerank's text too — same escaped-newline, one-line-per-chunk format —
        // lets passage_recall be scored at rerank as well as final, which is what tells the two
        // apart. Debug-harness only; this file is not on any production path.
        if let rerankTrace = traces.first(where: { $0.stage == RetrievalTraceCollector.Stage.rerank.rawValue }) {
            lines.append("RERANK CHUNK TEXT")
            for (index, result) in rerankTrace.results.enumerated() {
                let body = (result.chunk.parentContent ?? result.chunk.content)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                lines.append("CHUNK \(index + 1) | \(result.sourceDocument) | \(body)")
            }
            lines.append("END RERANK CHUNK TEXT")
            lines.append("")
        }

        return lines
    }

    private static func buildReport(
        configuration: Configuration,
        containerId: UUID,
        containerName: String,
        ingestionResult: IngestionBatchResult?,
        response: RAGResponse,
        auditSnapshot: RAGAuditSnapshot?,
        copiedTraceURL: URL?,
        trace: RetrievalTraceCollector? = nil,
        knownDocuments: [Document] = []
    ) -> String {
        var lines: [String] = []
        lines.append("OPENINTELLIGENCE RAG VALIDATION")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Query: \(configuration.query)")
        lines.append("Container: \(containerName) [\(containerId.uuidString)]")
        lines.append("Storage: \(configuration.storageDirectory.path)")
        lines.append("Quality Mode: \(response.metadata.qualityModeName ?? configuration.qualityMode?.displayName ?? "Unknown")")
        lines.append("Retrieval TopK: \(configuration.retrievalTopK ?? 3)")
        if let w = UserDefaults.standard.object(forKey: "benchmarkVectorWeight") as? Double {
            lines.append("Fusion Weights: vector \(w) / lexical \(1 - w)")
        }
        if let pccConsent = configuration.pccConsent {
            lines.append("Benchmark PCC Consent: \(pccConsent)")
        }
        if let benchmarkEntitlement = configuration.benchmarkEntitlement {
            lines.append("Benchmark Entitlement: \(benchmarkEntitlement.rawValue)")
        }
        lines.append("Model: \(response.metadata.modelUsed)")
        #if targetEnvironment(simulator)
        lines.append("Runtime: Simulator")
        #elseif targetEnvironment(macCatalyst)
        lines.append("Runtime: Mac Catalyst")
        #else
        lines.append("Runtime: Device")
        #endif
        lines.append("")

        if let ingestionResult {
            lines.append("INGESTION")
            lines.append("Success: \(ingestionResult.successCount)/\(ingestionResult.totalCount)")
            lines.append("Failures: \(ingestionResult.failureCount)")
            if !configuration.inputURLs.isEmpty {
                lines.append("Inputs:")
                for url in configuration.inputURLs {
                    lines.append("- \(url.path)")
                }
            }
            lines.append("")
        }

        lines.append("ANSWER")
        lines.append("Confidence: \(String(format: "%.2f", response.confidenceScore))")
        lines.append("Retrieved Chunks: \(response.retrievedChunks.count)")

        // Emit the text of every chunk that reached the model, so retrieval can be scored at
        // PASSAGE level rather than document level.
        //
        // Until 2026-08-21 this report carried only a count, and `r@1`/`r@10` credited a whole
        // document when any of its chunks appeared. That ruler misled four separate conclusions in
        // one day, and the last one was inverted: injecting a document summary raised `r@1` to
        // 1.000 (the summary is a chunk of the gold document) while making the answer worse,
        // because a summary cannot answer an extractive question. 19 of 25 QASPER cases are
        // `answer_kind: extractive` — the answer is a literal span — so "did the span reach the
        // model" is the question that actually matters and could not previously be asked.
        //
        // Written as one line per chunk with newlines escaped, so the scorer can substring-match
        // the fixture's `expected_evidence[].excerpt` without a parser. Debug-harness only; this
        // file is not on any production path.
        lines.append("RETRIEVED CHUNK TEXT")
        for (index, retrieved) in response.retrievedChunks.enumerated() {
            let body = (retrieved.chunk.parentContent ?? retrieved.chunk.content)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            lines.append("CHUNK \(index + 1) | \(retrieved.sourceDocument) | \(body)")
        }
        lines.append("END RETRIEVED CHUNK TEXT")
        lines.append("")

        lines.append("Response:")
        lines.append(response.generatedResponse)
        lines.append("")

        lines.append(contentsOf: stageMetricsLines(
            trace: trace,
            expectedSources: configuration.expectedSources,
            response: response,
            knownDocuments: knownDocuments
        ))

        lines.append("RETRIEVED CHUNKS")
        if response.retrievedChunks.isEmpty {
            lines.append("(none)")
        } else {
            for chunk in response.retrievedChunks.prefix(12) {
                let preview = formatChunkPreview(for: chunk)
                let page = chunk.pageNumber.map(String.init) ?? "-"
                let sourceDocument = chunk.sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("- rank=\(chunk.rank) sim=\(String(format: "%.3f", chunk.similarityScore)) page=\(page) source=\(sourceDocument.isEmpty ? "Unknown" : sourceDocument)")
                lines.append("  \(preview)")
            }
        }
        lines.append("")

        if let auditSnapshot {
            lines.append("AUDIT SNAPSHOT")
            lines.append("Embedding: \(auditSnapshot.embeddingProviderId) / \(auditSnapshot.embeddingDim)D")
            lines.append("Vector DB: \(auditSnapshot.vectorDBKind.rawValue)")
            lines.append("Stored Chunks: \(auditSnapshot.totalStoredChunks)")
            lines.append("Candidates: \(auditSnapshot.candidatesCount)")
            lines.append("Reranked: \(auditSnapshot.rerankedCount)")
            lines.append("Filtered: \(auditSnapshot.filteredCount)")
            lines.append("Dropped: \(auditSnapshot.droppedCount)")
            lines.append("MMR Selected: \(auditSnapshot.mmrSelectedCount)")
            lines.append("Unique Docs: \(auditSnapshot.uniqueDocCount)")
            lines.append("Top Similarity: \(String(format: "%.3f", auditSnapshot.topSim))")
            lines.append("Context Chars: \(auditSnapshot.contextChars)/\(auditSnapshot.maxContextChars)")
            lines.append("Context Chunks Used: \(auditSnapshot.contextChunksUsed)")
            lines.append("Execution Context: \(auditSnapshot.executionContext.description)")
            lines.append("Recursive RAG: \(auditSnapshot.isRecursiveRAG)")
            lines.append("LLM Calls: \(auditSnapshot.llmCallCount)")
            lines.append("Total Tokens Across Calls: \(auditSnapshot.totalTokensAcrossCalls)")
            lines.append("Enabled Features: \(auditSnapshot.featureFlags.enabledFeatures.joined(separator: ", "))")
            lines.append("")
        }

        lines.append("ARTIFACTS")
        lines.append("Report: \(configuration.outputDirectory.appendingPathComponent("rag_validation_report.txt").path)")
        if let copiedTraceURL {
            lines.append("Trace: \(copiedTraceURL.path)")
        } else {
            lines.append("Trace: (not found)")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatChunkPreview(for chunk: RetrievedChunk, limit: Int = 220) -> String {
        let source = chunk.chunk.parentContent ?? chunk.chunk.content
        let normalized = source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "(empty chunk)" }
        guard normalized.count > limit else { return normalized }

        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func buildErrorReport(
        configuration: Configuration,
        error: Error,
        copiedTraceURL: URL?
    ) -> String {
        var lines: [String] = []
        lines.append("OPENINTELLIGENCE RAG VALIDATION")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Query: \(configuration.query)")
        lines.append("Storage: \(configuration.storageDirectory.path)")
        if let pccConsent = configuration.pccConsent {
            lines.append("Benchmark PCC Consent: \(pccConsent)")
        }
        if let benchmarkEntitlement = configuration.benchmarkEntitlement {
            lines.append("Benchmark Entitlement: \(benchmarkEntitlement.rawValue)")
        }
        lines.append("Status: FAILED")
        lines.append("Error: \(error.localizedDescription)")
        lines.append("")
        lines.append("Inputs:")
        if configuration.inputURLs.isEmpty {
            lines.append("(none)")
        } else {
            for url in configuration.inputURLs {
                lines.append("- \(url.path)")
            }
        }
        lines.append("")
        lines.append("Artifacts:")
        if let copiedTraceURL {
            lines.append("Trace: \(copiedTraceURL.path)")
        }
        return lines.joined(separator: "\n")
    }

    private static func copyTraceLog(into outputDirectory: URL) -> URL? {
        let fm = FileManager.default
        guard let documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let sourceURL = documentsDirectory.appendingPathComponent("pipeline_trace.log")
        guard fm.fileExists(atPath: sourceURL.path) else { return nil }
        let destinationURL = outputDirectory.appendingPathComponent("pipeline_trace.log")
        try? fm.removeItem(at: destinationURL)
        do {
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            Log.warning("[RAGValidation] Failed to copy trace log: \(error.localizedDescription)", category: .pipeline)
            return nil
        }
    }

    private static func makeConfiguration() -> Configuration? {
        guard LaunchArguments.has("--rag-validation") || LaunchArguments.has("rag-validation") || LaunchArguments.has("--rag-validation-visual") || LaunchArguments.has("rag-validation-visual") else {
            return nil
        }

        guard let query = LaunchArguments.valueEither(for: "rag-validation-query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else {
            return nil
        }

        let storageDirectory: URL = {
            if let explicitPath = LaunchArguments.valueEither(for: "rag-validation-storage"), !explicitPath.isEmpty {
                return resolveSandboxPath(
                    explicitPath,
                    defaultBase: applicationSupportDirectory(),
                    isDirectory: true
                )
            }

            let runId = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            return applicationSupportDirectory()
                .appendingPathComponent("OpenIntelligenceRAGValidation", isDirectory: true)
                .appendingPathComponent(runId, isDirectory: true)
        }()

        let retrievalTopK: Int? = {
            guard let raw = LaunchArguments.valueEither(for: "rag-validation-topk"),
                  let value = Int(raw), value > 0
            else { return nil }
            return value
        }()

        let outputDirectory = storageDirectory.appendingPathComponent("ValidationOutput", isDirectory: true)
        let inputURLs = parseInputURLs()
        let qualityMode = parseQualityMode(LaunchArguments.valueEither(for: "rag-validation-quality"))
        let shouldIngest = !(LaunchArguments.has("--rag-validation-skip-ingest") || LaunchArguments.has("rag-validation-skip-ingest"))
        let pccConsent = parsePCCConsent(LaunchArguments.valueEither(for: "rag-validation-pcc-consent"))
        let benchmarkEntitlement = parseBenchmarkEntitlement(LaunchArguments.valueEither(for: "rag-validation-entitlement"))
        let expectedSources = (LaunchArguments.valueEither(for: "rag-validation-expected-sources") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Configuration(
            query: query,
            inputURLs: inputURLs,
            storageDirectory: storageDirectory,
            outputDirectory: outputDirectory,
            qualityMode: qualityMode,
            shouldIngest: shouldIngest,
            pccConsent: pccConsent,
            benchmarkEntitlement: benchmarkEntitlement,
            expectedSources: expectedSources,
            retrievalTopK: retrievalTopK
        )
    }

    private static func seedPCCConsentIfNeeded(_ consent: String?) {
        guard let consent else { return }
        let key = "cloudConsent.applePCC"
        let defaults = UserDefaults.standard
        switch consent {
        case "allow", "deny", "allowed", "denied":
            let valueToSet = consent.starts(with: "allow") ? "allowed" : "denied"
            defaults.set(valueToSet, forKey: key)
            defaults.register(defaults: [key: valueToSet])
        case "default":
            defaults.removeObject(forKey: key)
        default:
            return
        }
        defaults.synchronize()
        print("[RAGValidation] PCC consent preset: \(consent)")
    }

    private static func seedBenchmarkEntitlementIfNeeded(_ tier: WorkspaceTier?) {
        guard let tier else { return }

        let defaults = UserDefaults.standard
        defaults.set(tier.rawValue, forKey: "entitlement.activeTier")
        if tier == .free {
            defaults.set(LegacyProtectionState.none.rawValue, forKey: "entitlement.legacyProtectionState")
        } else {
            defaults.set(LegacyProtectionState.historicalPaidPurchase.rawValue, forKey: "entitlement.legacyProtectionState")
        }
        defaults.synchronize()
        print("[RAGValidation] Benchmark entitlement preset: \(tier.rawValue)")
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func appDataContainerRoot() -> URL {
        documentsDirectory().deletingLastPathComponent()
    }

    private static func resolveSandboxPath(
        _ rawPath: String,
        defaultBase: URL,
        isDirectory: Bool
    ) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed, isDirectory: isDirectory)
        }

        let rootPrefixes = ["Documents", "Library", "tmp"]
        let rootRelative = rootPrefixes.contains { prefix in
            trimmed == prefix || trimmed.hasPrefix("\(prefix)/")
        }
        let base = rootRelative ? appDataContainerRoot() : defaultBase
        return base.appendingPathComponent(trimmed, isDirectory: isDirectory)
    }

    private static func parseInputURLs() -> [URL] {
        let explicitValue = LaunchArguments.valueEither(for: "rag-validation-file")
            ?? LaunchArguments.valueEither(for: "rag-validation-files")

        guard let explicitValue, !explicitValue.isEmpty else { return [] }

        return explicitValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                resolveSandboxPath(
                    $0,
                    defaultBase: documentsDirectory(),
                    isDirectory: false
                )
            }
    }

    private static func parseQualityMode(_ rawValue: String?) -> RAGQualityMode? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "standard":
            return .standard
        case "deepthink", "deep-think", "deep_think", "agentic":
            return .deepThink
        case "maximum", "max":
            return .maximum
        default:
            return nil
        }
    }

    private static func parsePCCConsent(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "allow", "allowed":
            return "allowed"
        case "deny", "denied":
            return "denied"
        case "default", "ask", "reset", "notdetermined", "not-determined":
            return "default"
        default:
            return nil
        }
    }

    private static func parseBenchmarkEntitlement(_ rawValue: String?) -> WorkspaceTier? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "free":
            return .free
        case "pro":
            return .pro
        case "lifetime", "lifetime-cohort", "lifetime_cohort":
            return .lifetime
        case "current", "default", "none":
            return nil
        default:
            return nil
        }
    }
}
#endif
