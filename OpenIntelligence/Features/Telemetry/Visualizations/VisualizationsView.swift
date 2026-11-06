//
//  VisualizationsView.swift
//  OpenIntelligence
//
//  Data visualization dashboard for embeddings and RAG analytics
//  Created by GitHub Copilot on 10/18/25.
//

import Charts
import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Top-level telemetry dashboard for the RAG pipeline.
/// Aggregates embedding, retrieval, and performance diagnostics for the active container.
struct VisualizationsView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    let onRequestAddDocuments: (() -> Void)?
    @State private var selectedTab: DashboardTab = .overview

    init(onRequestAddDocuments: (() -> Void)? = nil) {
        self.onRequestAddDocuments = onRequestAddDocuments

        #if DEBUG
            if LaunchArguments.has("--screenshot") || LaunchArguments.has("screenshot") {
                if let raw = LaunchArguments.valueEither(for: "screenshot-viz-tab")?.lowercased() {
                    switch raw {
                    case "overview":
                        _selectedTab = State(initialValue: .overview)
                    case "retrieval":
                        _selectedTab = State(initialValue: .retrieval)
                    case "clustering":
                        _selectedTab = State(initialValue: .clustering)
                    default:
                        break
                    }
                }
            }
        #endif
    }

    enum DashboardTab: String, CaseIterable, Identifiable {
        case overview
        case retrieval
        case clustering

        var id: String { rawValue }

        var label: String {
            switch self {
            case .overview: return "Overview"
            case .retrieval: return "Retrieval"
            case .clustering: return "Clustering"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "rectangle.grid.2x2"
            case .retrieval: return "magnifyingglass.circle"
            case .clustering: return "hexagon"
            }
        }
    }

    var body: some View {
        Group {
            if activeDocuments.isEmpty {
                EmptyVisualizationsView(onAddDocuments: onRequestAddDocuments)
                    .padding(.top, DSSpacing.xxl)
            } else {
                ScrollView {
                    VStack(spacing: DSSpacing.xl) {
                        containerPicker
                        summaryCard
                        tabPicker
                        tabContent
                    }
                    .padding(.vertical, DSSpacing.xl)
                }
            }
        }
        .background(DSColors.background.ignoresSafeArea())
        .navigationTitle("Visualizations")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
    }

    @ViewBuilder
    private var containerPicker: some View {
        if containerService.containers.count > 1 {
            ContainerPickerStrip(containerService: containerService)
                .padding(.horizontal, DSSpacing.lg)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(activeContainerName)
                        .font(.headline)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let updated = lastUpdatedDocumentsSummary {
                        Text(updated)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let action = onRequestAddDocuments {
                    Button(action: action) {
                        Label("Add Documents", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, DSSpacing.sm)
                            .background(DSColors.accent.opacity(0.15))
                            .foregroundStyle(DSColors.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: DSSpacing.md) {
                StatCard(
                    icon: "doc.text",
                    label: "Documents",
                    value: "\(activeDocuments.count)",
                    color: DSColors.accent
                )

                StatCard(
                    icon: "cube.box",
                    label: "Chunks",
                    value: "\(totalChunkCount)",
                    color: DSColors.accent
                )
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, DSSpacing.lg)
    }

    private var summaryLine: String {
        guard !activeDocuments.isEmpty else { return "No documents indexed yet" }
        let documentWord = activeDocuments.count == 1 ? "document" : "documents"
        let chunkWord = totalChunkCount == 1 ? "chunk" : "chunks"
        return "\(activeDocuments.count) \(documentWord), \(totalChunkCount) \(chunkWord)"
    }

    private var lastUpdatedDocumentsSummary: String? {
        guard let latest = activeDocuments.map(\.addedAt).max() else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: latest, relativeTo: Date()))"
    }

    private var activeContainerName: String {
        activeContainer?.name ?? "Current Library"
    }

    private var activeContainer: KnowledgeContainer? {
        containerService.containers.first(where: { $0.id == containerService.activeContainerId })
    }

    private var activeDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents
            .filter { doc in
                if let containerId = doc.containerId {
                    return containerId == activeId
                }
                return defaultId == activeId
            }
            .sorted { lhs, rhs in
                lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
            }
    }

    private var totalChunkCount: Int {
        activeDocuments.reduce(0) { $0 + $1.totalChunks }
    }

    private var tabPicker: some View {
        Picker("Dashboard Section", selection: $selectedTab) {
            ForEach(DashboardTab.allCases) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .retrieval:
            retrievalTab
        case .clustering:
            clusteringTab
        }
    }

    private var overviewTab: some View {
        VStack(spacing: DSSpacing.xl) {
            ChunkDistributionView(
                documents: activeDocuments,
                chunkCount: totalChunkCount
            )
            AdvancedCorpusStatsView(
                documents: activeDocuments,
                chunkCount: totalChunkCount
            )
            QueryAnalyticsView(ragService: ragService)
            PerformanceMetricsView(ragService: ragService)
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var retrievalTab: some View {
        VStack(spacing: DSSpacing.xl) {
            embeddingSection
            RetrievalPatternsView(
                totalChunkCount: totalChunkCount,
                activeDocuments: activeDocuments
            )
            SimilarityHeatmapView()
            PipelineTimelineView()
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var clusteringTab: some View {
        VStack(spacing: DSSpacing.xl) {
            SemanticClusteringView()
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    @ViewBuilder
    private var embeddingSection: some View {
        let dimension = containerService.activeContainer?.embeddingDim ?? 512
        if totalChunkCount > 0 {
            EmbeddingSpaceView(
                chunkCount: totalChunkCount,
                documentCount: activeDocuments.count,
                embeddingDimension: dimension
            )
        } else {
            EmbeddingSpacePlaceholder(
                projectionMethod: .pca,
                chunkCount: totalChunkCount,
                documentCount: activeDocuments.count
            )
        }
    }
}

// MARK: - Empty State

struct EmptyVisualizationsView: View {
    let onAddDocuments: (() -> Void)?
    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            // Hero icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DSColors.accent.opacity(0.2),
                                DSColors.accent.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "chart.xyaxis.line")
                    .scaledFont(size: 50)
                    .foregroundStyle(DSColors.accent.gradient)
            }

            VStack(spacing: DSSpacing.sm) {
                Text("No Data to Visualize")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Add documents to see embedding visualizations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    onAddDocuments?()
                } label: {
                    Label("Add Documents", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColors.accent.opacity(0.15))
                        .foregroundStyle(DSColors.accent)
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}









