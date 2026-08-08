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
        AppSupportPaths.configureBaseDir(configuration.storageDirectory)
        seedPCCConsentIfNeeded(configuration.pccConsent)
        seedBenchmarkEntitlementIfNeeded(configuration.benchmarkEntitlement)
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
                let report = try await runIfNeeded(
                    ragService: ragService,
                    settingsStore: settingsStore
                )
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

    static func runIfNeeded(
        ragService: RAGService,
        settingsStore: SettingsStore
    ) async throws -> String {
        guard let configuration = cachedConfiguration, runGate.claim() else { return "No configuration or already running." }
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
            let (response, auditSnapshot) = try await ragService.queryWithAudit(
                configuration.query,
                containerId: containerId,
                trace: trace
            )

            Log.flushTraceLog()
            let copiedTraceURL = copyTraceLog(into: configuration.outputDirectory)
            let report = buildReport(
                configuration: configuration,
                containerId: containerId,
                containerName: containerName,
                ingestionResult: ingestionResult,
                response: response,
                auditSnapshot: auditSnapshot,
                copiedTraceURL: copiedTraceURL,
                trace: trace
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
    /// and a re-derived Python one that can drift apart. `STAGE SOURCES` lists the ranked source
    /// documents each stage returned, so any number in the first block can be recomputed by hand
    /// from the second. A benchmark that cannot be checked is an assertion, not a measurement.
    ///
    /// Nothing is emitted when there are no expected sources. The two negative-control cases have
    /// none by construction, and scoring them would report a meaningless 0.0 that would then be
    /// averaged into the aggregate.
    private static func stageMetricsLines(
        trace: RetrievalTraceCollector?,
        expectedSources: [String],
        response: RAGResponse
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
        let groundTruth: [String] = expectedSources.map { expected in
            let resolved = allChunks.first { RetrievalRelevanceJudge.matches($0, expected: expected) }
            return resolved?.chunk.documentId.uuidString ?? expected
        }

        let metrics = RetrievalStageEvaluator.score(traces: traces, expectedSources: groundTruth)
        func f(_ value: Double) -> String { String(format: "%.4f", value) }

        var lines: [String] = []
        lines.append("STAGE METRICS")
        lines.append("ExpectedSources: \(expectedSources.joined(separator: "|"))")
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

        // Capped at 20 per stage: enough to re-derive every metric above, since the deepest cutoff
        // is 10, without pasting a whole candidate pool into every report.
        lines.append("STAGE SOURCES")
        for t in traces {
            let sources = t.results.prefix(20).map { chunk -> String in
                let name = chunk.sourceDocument.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "(unnamed)" : name
            }
            lines.append("\(t.stage)\t\(sources.joined(separator: "|"))")
        }
        lines.append("")

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
        trace: RetrievalTraceCollector? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("OPENINTELLIGENCE RAG VALIDATION")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Query: \(configuration.query)")
        lines.append("Container: \(containerName) [\(containerId.uuidString)]")
        lines.append("Storage: \(configuration.storageDirectory.path)")
        lines.append("Quality Mode: \(response.metadata.qualityModeName ?? configuration.qualityMode?.displayName ?? "Unknown")")
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
        lines.append("Response:")
        lines.append(response.generatedResponse)
        lines.append("")

        lines.append(contentsOf: stageMetricsLines(
            trace: trace,
            expectedSources: configuration.expectedSources,
            response: response
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
            expectedSources: expectedSources
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
