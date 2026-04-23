//
//  RAGPipelineAuditView.swift
//  OpenIntelligence
//
//  Deep diagnostics for the live RAG pipeline.
//

import SwiftUI

struct RAGPipelineAuditView: View {
    @ObservedObject var ragService: RAGService
    @State private var isRunningVectorAudit = false

    private var activeContainerId: UUID? {
        ragService.containerService.activeContainerId
    }

    private var intelligenceReport: LibraryIntelligenceCenter.IntelligenceReport? {
        ragService.intelligenceReport(for: activeContainerId)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    snapshotCard
                    corpusCard
                    chunkingCard
                    embeddingCard
                    vectorStoreCard
                    retrievalCard
                    featureCard
                    contextCard
                }
                .padding(16)
            }
        }
        .navigationTitle("RAG Audit")
        .onAppear {
            ragService.refreshIntelligence(for: activeContainerId, force: true)
        }
    }

    private var snapshotCard: some View {
        SurfaceCard {
            SectionHeader(icon: "waveform.path.ecg", title: "Live Snapshot")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Query", value: snapshot.query)
                LabeledContent("Container", value: snapshot.containerName)
                LabeledContent("Timestamp", value: formatDate(snapshot.timestamp))
                LabeledContent("Model", value: snapshot.modelName)
                LabeledContent("Execution", value: snapshot.executionContext.description)
                LabeledContent("Network", value: snapshot.networkConnected ? "Online" : "Offline")
                LabeledContent(
                    "PCC Allowed",
                    value: snapshot.allowPrivateCloudCompute ? "Yes" : "No"
                )
                LabeledContent(
                    "Cloud Context",
                    value: snapshot.wantsCloudContext ? "Requested" : "Off"
                )
                LabeledContent(
                    "Reliability mode",
                    value: snapshot.reliabilityModeEnabled ? "On" : "Off"
                )
                LabeledContent(
                    "Ungrounded fallback",
                    value: snapshot.allowUngroundedFallback ? "Yes" : "No"
                )
            } else {
                Text("Run a query to capture the first audit snapshot.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var corpusCard: some View {
        SurfaceCard {
            SectionHeader(icon: "books.vertical", title: "Corpus Signals")
            if let report = intelligenceReport {
                LabeledContent("Documents", value: "\(report.corpus.documentCount)")
                LabeledContent("Chunks", value: "\(report.corpus.chunkCount)")
                LabeledContent(
                    "Avg words per chunk",
                    value: String(format: "%.1f", report.corpus.avgWordsPerChunk)
                )
                LabeledContent(
                    "Structured ratio",
                    value: formatPercent(report.corpus.structuredRatio)
                )
                LabeledContent(
                    "Technical density",
                    value: formatPercent(report.corpus.technicalDensity)
                )
                LabeledContent(
                    "Semantic complexity",
                    value: String(format: "%.2f", report.corpus.semanticComplexity)
                )
                LabeledContent("Has math", value: report.corpus.hasMath ? "Yes" : "No")
                LabeledContent("Has code", value: report.corpus.hasCode ? "Yes" : "No")
            } else {
                Text("No corpus intelligence snapshot available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chunkingCard: some View {
        SurfaceCard {
            SectionHeader(icon: "scissors", title: "Chunking")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Configured target", value: "\(snapshot.chunkingTargetWords) words")
                LabeledContent("Overlap", value: "\(snapshot.chunkingOverlapWords) words")
                LabeledContent("Directive source", value: snapshot.chunkingSource.capitalized)
            }
            if let report = intelligenceReport {
                LabeledContent(
                    "Recommended strategy",
                    value: report.chunking.strategy.rawValue
                )
                LabeledContent(
                    "Recommended target",
                    value: "\(report.chunking.targetWordWindow) words"
                )
                LabeledContent(
                    "Recommended overlap",
                    value: "\(report.chunking.overlapWords) words"
                )
            }
            if ragService.lastAuditSnapshot == nil && intelligenceReport == nil {
                Text("Chunking data will appear after ingestion and a query.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var embeddingCard: some View {
        SurfaceCard {
            SectionHeader(icon: "hexagon", title: "Embeddings")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Provider", value: snapshot.embeddingProviderId)
                LabeledContent("Dimension", value: "\(snapshot.embeddingDim)")
                LabeledContent("Vector DB", value: snapshot.vectorDBKind.rawValue)
            } else {
                Text("No embedding snapshot captured yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vectorStoreCard: some View {
        SurfaceCard {
            SectionHeader(icon: "externaldrive", title: "Vector Store Audit")
            HStack(spacing: 10) {
                if isRunningVectorAudit {
                    ProgressView().scaleEffect(0.9)
                }
                Button("Run audit") {
                    Task {
                        await MainActor.run { isRunningVectorAudit = true }
                        _ = await ragService.runVectorAudit(for: activeContainerId)
                        await MainActor.run { isRunningVectorAudit = false }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }

            if let audit = ragService.lastVectorAudit {
                LabeledContent("Container", value: audit.containerName)
                LabeledContent("Timestamp", value: formatDate(audit.timestamp))
                LabeledContent("Expected dim", value: "\(audit.expectedDimension)")
                LabeledContent("Total chunks", value: "\(audit.totalChunks)")
                LabeledContent("Mismatched dims", value: "\(audit.mismatchedDimensions)")
                LabeledContent("Unique docs", value: "\(audit.uniqueDocuments)")
                LabeledContent(
                    "Avg chunk words",
                    value: String(format: "%.1f", audit.averageChunkWords)
                )
                LabeledContent("Min chunk words", value: "\(audit.minChunkWords)")
                LabeledContent("Max chunk words", value: "\(audit.maxChunkWords)")
            } else {
                Text("Run the audit to validate embeddings and chunk storage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var retrievalCard: some View {
        SurfaceCard {
            SectionHeader(icon: "magnifyingglass", title: "Retrieval & Gating")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Quality mode", value: snapshot.qualityModeName)
                LabeledContent("Retrieval preset", value: snapshot.retrievalConfig.summary)
                LabeledContent(
                    "Min similarity",
                    value: String(format: "%.2f", snapshot.retrievalConfig.minSimilarity)
                )
                LabeledContent(
                    "Dynamic min",
                    value: String(format: "%.2f", snapshot.dynamicMin)
                )
                LabeledContent(
                    "Top similarity",
                    value: String(format: "%.3f", snapshot.topSim)
                )
                LabeledContent(
                    "Avg top 5",
                    value: String(format: "%.3f", snapshot.avgTop5)
                )
                LabeledContent(
                    "Acceptance override",
                    value: snapshot.acceptanceOverride ? "Yes" : "No"
                )
                LabeledContent(
                    "Lenient mode",
                    value: snapshot.lenientRetrieval ? "Yes" : "No"
                )
                LabeledContent("Candidates", value: "\(snapshot.candidatesCount)")
                LabeledContent("Reranked", value: "\(snapshot.rerankedCount)")
                LabeledContent("Filtered", value: "\(snapshot.filteredCount)")
                LabeledContent("Dropped", value: "\(snapshot.droppedCount)")
                LabeledContent("MMR selected", value: "\(snapshot.mmrSelectedCount)")
                LabeledContent("Unique docs", value: "\(snapshot.uniqueDocCount)")
            } else {
                Text("Run a query to see retrieval metrics.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contextCard: some View {
        SurfaceCard {
            SectionHeader(icon: "rectangle.stack", title: "Context Assembly")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Stored chunks", value: "\(snapshot.totalStoredChunks)")
                LabeledContent("Strategy", value: snapshot.contextStrategy)
                LabeledContent("Chunks used", value: "\(snapshot.contextChunksUsed)")
                LabeledContent("Context words", value: "\(snapshot.contextWords)")
                LabeledContent("Context chars", value: "\(snapshot.contextChars)")
                LabeledContent("Max context chars", value: "\(snapshot.maxContextChars)")
                LabeledContent("Base window", value: "\(snapshot.baseWindowTokens) tokens")
                LabeledContent("Safety tokens", value: "\(snapshot.safetyTokens)")
                LabeledContent("Prompt overhead", value: "\(snapshot.promptOverheadTokens)")
                LabeledContent("Question tokens", value: "\(snapshot.questionTokens)")
                LabeledContent("Reserved output", value: "\(snapshot.reservedOutputTokens)")
                LabeledContent("Available for context", value: "\(snapshot.availableContextTokens)")
            } else {
                Text("Context metrics will appear after a query.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var featureCard: some View {
        SurfaceCard {
            SectionHeader(icon: "switch.2", title: "Feature Activation")
            if let snapshot = ragService.lastAuditSnapshot {
                LabeledContent("Answer intent", value: snapshot.featureFlags.answerIntent)
                LabeledContent("Query rewrite", value: snapshot.featureFlags.queryWasRewritten ? "Yes" : "No")
                LabeledContent("Query expansions", value: "\(snapshot.featureFlags.queryExpansionCount)")
                LabeledContent("HyDE", value: snapshot.featureFlags.usedHyDE ? "Yes" : "No")
                LabeledContent(
                    "Iterative retrieval",
                    value: snapshot.featureFlags.usedIterativeRetrieval ? "\(snapshot.featureFlags.iterativePassCount)x" : "No"
                )
                LabeledContent("Query routing", value: snapshot.featureFlags.usedQueryRouting ? "Yes" : "No")
                LabeledContent("Summary routing", value: snapshot.featureFlags.usedSummaryRouting ? "Yes" : "No")
                LabeledContent("Parent expansion", value: snapshot.featureFlags.usedParentDocumentRetrieval ? "Yes" : "No")
                LabeledContent("Compression", value: snapshot.featureFlags.usedContextualCompression ? "Yes" : "No")
                LabeledContent("Graph packing", value: snapshot.featureFlags.usedGraphPacking ? "Yes" : "No")
                LabeledContent("Retrieval cascade", value: snapshot.featureFlags.usedRetrievalCascade ? "Yes" : "No")
                LabeledContent("Supplementary vector", value: snapshot.featureFlags.usedSupplementaryVectorSearch ? "Yes" : "No")
                if snapshot.featureFlags.usedFullUnlimitedReasoning {
                    LabeledContent("Unlimited reasoning", value: "Yes")
                }
                if !snapshot.featureFlags.enabledFeatures.isEmpty {
                    LabeledContent("Enabled", value: snapshot.featureFlags.enabledFeatures.joined(separator: " • "))
                }
            } else {
                Text("Run a query to capture feature activation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        RAGPipelineAuditView(ragService: RAGService())
    }
    #if os(iOS)
    .navigationViewStyle(.stack)
    #endif
}
