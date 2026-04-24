#if DEBUG
import Foundation

enum DebugRAGValidationHarness {
    struct Configuration: Sendable {
        let query: String
        let inputURLs: [URL]
        let storageDirectory: URL
        let outputDirectory: URL
        let qualityMode: RAGQualityMode?
        let shouldIngest: Bool
    }

    private static let cachedConfiguration: Configuration? = makeConfiguration()

    static var isEnabled: Bool {
        cachedConfiguration != nil
    }

    static func configureStorageIfNeeded() {
        guard let configuration = cachedConfiguration else { return }
        AppSupportPaths.configureBaseDir(configuration.storageDirectory)
    }

    static func runIfNeeded(
        ragService: RAGService,
        settingsStore: SettingsStore
    ) async {
        guard let configuration = cachedConfiguration else { return }

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
            let (response, auditSnapshot) = try await ragService.queryWithAudit(
                configuration.query,
                containerId: containerId
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
                copiedTraceURL: copiedTraceURL
            )
            try report.write(to: reportURL, atomically: true, encoding: .utf8)

            Log.info("[RAGValidation] Report written to \(reportURL.path)", category: .pipeline)
            if let copiedTraceURL {
                Log.info("[RAGValidation] Trace copied to \(copiedTraceURL.path)", category: .pipeline)
            }
            print("[RAGValidation] Report: \(reportURL.path)")
            if let copiedTraceURL {
                print("[RAGValidation] Trace: \(copiedTraceURL.path)")
            }
            exit(0)
        } catch {
            Log.error("[RAGValidation] Validation failed: \(error.localizedDescription)", category: .pipeline)
            Log.flushTraceLog()
            let copiedTraceURL = copyTraceLog(into: configuration.outputDirectory)
            let errorReport = buildErrorReport(
                configuration: configuration,
                error: error,
                copiedTraceURL: copiedTraceURL
            )
            try? errorReport.write(to: reportURL, atomically: true, encoding: .utf8)
            print("[RAGValidation] Report: \(reportURL.path)")
            if let copiedTraceURL {
                print("[RAGValidation] Trace: \(copiedTraceURL.path)")
            }
            exit(1)
        }
    }

    private static func buildReport(
        configuration: Configuration,
        containerId: UUID,
        containerName: String,
        ingestionResult: IngestionBatchResult?,
        response: RAGResponse,
        auditSnapshot: RAGAuditSnapshot?,
        copiedTraceURL: URL?
    ) -> String {
        var lines: [String] = []
        lines.append("OPENINTELLIGENCE RAG VALIDATION")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Query: \(configuration.query)")
        lines.append("Container: \(containerName) [\(containerId.uuidString)]")
        lines.append("Storage: \(configuration.storageDirectory.path)")
        lines.append("Quality Mode: \(response.metadata.qualityModeName ?? configuration.qualityMode?.displayName ?? "Unknown")")
        lines.append("Model: \(response.metadata.modelUsed)")
        #if targetEnvironment(simulator)
        lines.append("Runtime: Simulator")
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

        lines.append("RETRIEVED CHUNKS")
        if response.retrievedChunks.isEmpty {
            lines.append("(none)")
        } else {
            for chunk in response.retrievedChunks.prefix(12) {
                let preview = chunk.chunk.content
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedPreview = String(preview.prefix(220))
                let page = chunk.pageNumber.map(String.init) ?? "-"
                lines.append("- rank=\(chunk.rank) sim=\(String(format: "%.3f", chunk.similarityScore)) page=\(page) source=\(chunk.sourceDocument)")
                lines.append("  \(trimmedPreview)")
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
        guard LaunchArguments.has("--rag-validation") || LaunchArguments.has("rag-validation") else {
            return nil
        }

        guard let query = LaunchArguments.valueEither(for: "rag-validation-query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty
        else {
            return nil
        }

        let storageDirectory: URL = {
            if let explicitPath = LaunchArguments.valueEither(for: "rag-validation-storage"), !explicitPath.isEmpty {
                return URL(fileURLWithPath: explicitPath, isDirectory: true)
            }

            let runId = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return appSupport
                .appendingPathComponent("OpenIntelligenceRAGValidation", isDirectory: true)
                .appendingPathComponent(runId, isDirectory: true)
        }()

        let outputDirectory = storageDirectory.appendingPathComponent("ValidationOutput", isDirectory: true)
        let inputURLs = parseInputURLs()
        let qualityMode = parseQualityMode(LaunchArguments.valueEither(for: "rag-validation-quality"))
        let shouldIngest = !(LaunchArguments.has("--rag-validation-skip-ingest") || LaunchArguments.has("rag-validation-skip-ingest"))

        return Configuration(
            query: query,
            inputURLs: inputURLs,
            storageDirectory: storageDirectory,
            outputDirectory: outputDirectory,
            qualityMode: qualityMode,
            shouldIngest: shouldIngest
        )
    }

    private static func parseInputURLs() -> [URL] {
        let explicitValue = LaunchArguments.valueEither(for: "rag-validation-file")
            ?? LaunchArguments.valueEither(for: "rag-validation-files")

        guard let explicitValue, !explicitValue.isEmpty else { return [] }

        return explicitValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
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
}
#endif
