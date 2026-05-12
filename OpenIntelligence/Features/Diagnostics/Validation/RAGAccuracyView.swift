//
//  RAGAccuracyView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/27/26.
//
//  Proves RAG pipeline accuracy with real metrics.
//  "Trust, but verify" — now you can verify.
//

import SwiftUI

struct RAGAccuracyView: View {
    @ObservedObject var ragService: RAGService

    @State private var isRunningTests = false
    @State private var testProgress: String = ""
    @State private var embeddingSanityResult: EmbeddingSanityResult?
    @State private var quickSanityPassed: Bool?
    @State private var benchmarkReport: RAGBenchmarkSuiteResult?
    @State private var errorMessage: String?
    @State private var embeddingSnapshot: RAGService.EmbeddingDiagnosticsSnapshot?
    @State private var isImportingSamples = false

    var body: some View {
        List {
            // Quick Status
            Section {
                quickStatusCard
            } header: {
                Text("Pipeline Health")
            }

            // Quick Sanity Check
            Section {
                Button {
                    Task { await runQuickSanity() }
                } label: {
                    HStack {
                        Label("Quick Sanity Check", systemImage: "bolt.fill")
                        Spacer()
                        if isRunningTests {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let passed = quickSanityPassed {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(passed ? .green : .red)
                        }
                    }
                }
                .disabled(isRunningTests)
            } header: {
                Text("Quick Tests")
            } footer: {
                Text("Tests 3 critical embedding pairs in ~100ms. Run on startup to verify pipeline health.")
            }

            // Embedding Sanity (detailed)
            Section {
                Button {
                    Task { await runEmbeddingSanity() }
                } label: {
                    HStack {
                        Label("Embedding Sanity Suite", systemImage: "brain.head.profile")
                        Spacer()
                        if isRunningTests {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let result = embeddingSanityResult {
                            Text(String(format: "%.0f%%", result.correlation * 100))
                                .font(.caption.monospaced())
                                .foregroundStyle(result.passed ? .green : .red)
                        }
                    }
                }
                .disabled(isRunningTests)

                if let result = embeddingSanityResult {
                    embeddingResultsView(result)
                }
            } header: {
                Text("Embedding Quality")
            } footer: {
                Text("Verifies semantic embeddings work correctly: synonyms close, unrelated far.")
            }

            // Full Pipeline Test
            Section {
                Button {
                    Task { await importSampleWorkspace() }
                } label: {
                    HStack {
                        Label("Import Sample Workspace", systemImage: "square.and.arrow.down.on.square")
                        Spacer()
                        if isImportingSamples {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isRunningTests || isImportingSamples)

                Button {
                    Task { await runFullSuite() }
                } label: {
                    HStack {
                        Label("Full Pipeline Audit", systemImage: "testtube.2")
                        Spacer()
                        if isRunningTests {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let report = benchmarkReport {
                            Text(report.metrics.passed ? "PASS" : "FAIL")
                                .font(.caption.bold())
                                .foregroundStyle(report.metrics.passed ? .green : .red)
                        }
                    }
                }
                .disabled(isRunningTests || isImportingSamples || ragService.documents.isEmpty)

                if let report = benchmarkReport {
                    fullMetricsView(report.metrics)
                    pipelineCensusView(report.pipelineCensus)
                    benchmarkCaseResultsView(report.caseResults)
                }
            } header: {
                Text("Full Accuracy Audit")
            } footer: {
                if ragService.documents.isEmpty {
                    Text("⚠️ Import the sample workspace or add your own documents first to test retrieval and answer accuracy.")
                } else {
                    Text("Tests embedding, retrieval (Recall@K, MRR), answer quality (F1), and pipeline activation. The built-in suite is aligned to the app's sample workspace documents.")
                }
            }

            // Error display
            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Test Progress
            if isRunningTests && !testProgress.isEmpty {
                Section {
                    Text(testProgress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Progress")
                }
            }

            // Explanation
            Section {
                explanationView
            } header: {
                Text("What This Proves")
            }
        }
        .navigationTitle("RAG Accuracy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            if embeddingSnapshot == nil {
                embeddingSnapshot = await ragService.embeddingDiagnosticsSnapshot()
            }
        }
    }

    // MARK: - Quick Status Card

    @ViewBuilder
    private var quickStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                let status = determineOverallStatus()
                Circle()
                    .fill(status.color)
                    .frame(width: 12, height: 12)
                Text(status.label)
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 20) {
                metricPill("Embedding", value: embeddingSanityResult?.correlation, threshold: 0.8)
                metricPill("Retrieval", value: benchmarkReport?.metrics.recallAt5, threshold: 0.6)
                metricPill("Answers", value: benchmarkReport?.metrics.f1Score, threshold: 0.5)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func metricPill(_ label: String, value: Float?, threshold: Float) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let v = value {
                Text(String(format: "%.0f%%", v * 100))
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(v >= threshold ? .green : .red)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func determineOverallStatus() -> (label: String, color: Color) {
        if let metrics = benchmarkReport?.metrics {
            return metrics.passed ? ("Verified Accurate", .green) : ("Issues Detected", .red)
        }
        if let sanity = embeddingSanityResult {
            return sanity.passed ? ("Embeddings OK", .green) : ("Embedding Issues", .orange)
        }
        if let quick = quickSanityPassed {
            return quick ? ("Quick Check Passed", .green) : ("Quick Check Failed", .red)
        }
        return ("Not Tested", .gray)
    }

    // MARK: - Embedding Results View

    @ViewBuilder
    private func embeddingResultsView(_ result: EmbeddingSanityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.passed ? "✅ PASSED" : "❌ FAILED")
                    .font(.caption.bold())
                Spacer()
                Text("Correlation: \(String(format: "%.1f%%", result.correlation * 100))")
                    .font(.caption.monospaced())
            }

            if !result.details.isEmpty {
                Text(result.details)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Full Metrics View

    @ViewBuilder
    private func fullMetricsView(_ metrics: RAGQualityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Overall status
            HStack {
                Text(metrics.passed ? "✅ PIPELINE VERIFIED" : "❌ ISSUES DETECTED")
                    .font(.caption.bold())
                Spacer()
                Text(String(format: "%.0f%%", metrics.overallScore * 100))
                    .font(.caption.bold().monospaced())
            }

            Divider()

            // Metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricRow("Recall@1", metrics.recallAt1, threshold: 0.5)
                metricRow("Recall@5", metrics.recallAt5, threshold: 0.6)
                metricRow("MRR", metrics.mrr, threshold: 0.7)
                metricRow("Precision", metrics.precision, threshold: 0.5)
                metricRow("Exact Match", metrics.exactMatchAccuracy, threshold: 0.5)
                metricRow("F1 Score", metrics.f1Score, threshold: 0.5)
            }

            // Failures
            if !metrics.failures.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Issues:")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    ForEach(metrics.failures, id: \.self) { failure in
                        Text("• \(failure)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func pipelineCensusView(_ census: RAGBenchmarkPipelineCensus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Pipeline Census")
                .font(.caption.bold())

            metricRow("Recursive RAG", Float(census.recursiveRAGCases) / Float(max(census.totalCases, 1)), threshold: 0)
            metricRow("Query rewrite", Float(census.queryRewriteCases) / Float(max(census.totalCases, 1)), threshold: 0)
            metricRow("HyDE", Float(census.hydeCases) / Float(max(census.totalCases, 1)), threshold: 0)
            metricRow("Iterative", Float(census.iterativeCases) / Float(max(census.totalCases, 1)), threshold: 0)
            metricRow("Compression", Float(census.compressionCases) / Float(max(census.totalCases, 1)), threshold: 0)
            metricRow("Graph pack", Float(census.graphPackingCases) / Float(max(census.totalCases, 1)), threshold: 0)

            if !census.enabledFeatureSummary.isEmpty {
                Text(census.enabledFeatureSummary.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func benchmarkCaseResultsView(_ caseResults: [RAGBenchmarkCaseResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Benchmark Cases")
                .font(.caption.bold())

            ForEach(caseResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: result.exactMatch ? "checkmark.circle.fill" : (result.f1Score >= 0.5 ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                            .foregroundStyle(result.exactMatch ? .green : (result.f1Score >= 0.5 ? .orange : .red))
                        Text(result.queryClass.rawValue)
                            .font(.caption.bold())
                        Spacer()
                        Text(String(format: "F1 %.0f%%", result.f1Score * 100))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Text(result.query)
                        .font(.caption2)
                    if let snapshot = result.auditSnapshot {
                        let featureSummary = snapshot.featureFlags.enabledFeatures
                        Text(featureSummary.isEmpty ? "Literal path" : featureSummary.joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func metricRow(_ label: String, _ value: Float, threshold: Float) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f%%", value * 100))
                .font(.caption.monospaced())
                .foregroundStyle(value >= threshold ? Color.primary : Color.red)
        }
    }

    // MARK: - Explanation View

    @ViewBuilder
    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            explanationItem("Embedding Sanity", "Verifies \"dog\" ≈ \"canine\" and \"pizza\" ≠ \"democracy\". If this fails, semantic search is broken.")
            explanationItem("Recall@K", "% of queries where the correct document appears in top K results. Target: >60%")
            explanationItem("MRR", "Mean Reciprocal Rank — how high correct answers rank. Target: >0.70")
            explanationItem("F1 Score", "Token overlap between generated and expected answers. Target: >50%")
            explanationItem("Built-in Corpus", "The default benchmark suite is aligned to the curated sample workspace imported by SampleDocumentManager.")
        }
    }

    @ViewBuilder
    private func explanationItem(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

        private func resolveEmbeddingSnapshot() async -> RAGService.EmbeddingDiagnosticsSnapshot {
            if let embeddingSnapshot {
                return embeddingSnapshot
            }

            let snapshot = await ragService.embeddingDiagnosticsSnapshot()
            await MainActor.run {
                self.embeddingSnapshot = snapshot
            }
            return snapshot
        }

        private func importSampleWorkspace() async {
            await MainActor.run {
                isImportingSamples = true
                errorMessage = nil
                testProgress = "Importing sample workspace..."
            }

            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                await MainActor.run {
                    testProgress = "Sample workspace imported."
                    isImportingSamples = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    testProgress = ""
                    isImportingSamples = false
                }
            }
        }

    // MARK: - Test Actions

    private func runQuickSanity() async {
        isRunningTests = true
        testProgress = "Running quick sanity check..."
        errorMessage = nil

        let snapshot = await resolveEmbeddingSnapshot()
        let embeddingService = snapshot.makeEmbeddingService()
        let passed = await QualityAssuranceService.shared.quickSanityCheck(embeddingService: embeddingService)

        await MainActor.run {
            quickSanityPassed = passed
            testProgress = ""
            isRunningTests = false
        }
    }

    private func runEmbeddingSanity() async {
        isRunningTests = true
        testProgress = "Testing semantic embedding pairs..."
        errorMessage = nil

        let snapshot = await resolveEmbeddingSnapshot()
        let embeddingService = snapshot.makeEmbeddingService()
        let (passed, correlation, details) = await QualityAssuranceService.shared.testEmbeddingSanity(embeddingService: embeddingService)

        await MainActor.run {
            embeddingSanityResult = EmbeddingSanityResult(passed: passed, correlation: correlation, details: details)
            testProgress = ""
            isRunningTests = false
        }
    }

    private func runFullSuite() async {
        isRunningTests = true
        testProgress = "Running benchmark + pipeline census..."
        errorMessage = nil

        let snapshot = await resolveEmbeddingSnapshot()
        let embeddingService = snapshot.makeEmbeddingService()

        // Create search function wrapper using searchDocumentsRaw
        let searchFunction: @Sendable (String) async throws -> [RetrievedChunk] = { [ragService] query in
            try await ragService.searchDocumentsRaw(query: query, topK: 10)
        }

        // Create answer function wrapper using queryWithAudit()
        let answerFunction: @Sendable (String) async throws -> (answer: String, auditSnapshot: RAGAuditSnapshot?) = { [ragService] query in
            let result = try await ragService.queryWithAudit(query)
            return (result.response.generatedResponse, result.auditSnapshot)
        }

        testProgress = "Testing embeddings, retrieval, answers, and feature activation..."
        let report = await QualityAssuranceService.shared.runEndToEndBenchmarkSuite(
            embeddingService: embeddingService,
            searchFunction: searchFunction,
            auditedAnswerFunction: answerFunction
        )

        await MainActor.run {
            benchmarkReport = report
            testProgress = ""
            isRunningTests = false
        }
    }
}

// MARK: - Result Types

struct EmbeddingSanityResult {
    let passed: Bool
    let correlation: Float
    let details: String
}

// MARK: - Preview

#Preview {
    NavigationView {
        RAGAccuracyView(ragService: RAGService())
    }
}
