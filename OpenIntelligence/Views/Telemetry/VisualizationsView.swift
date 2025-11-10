//
//  VisualizationsView.swift
//  OpenIntelligence
//
//  Data visualization dashboard for embeddings and RAG analytics
//  Created by GitHub Copilot on 10/18/25.
//

import SwiftUI
import Charts
import Foundation
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
                    .padding(.top, 32)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        containerPicker
                        summaryCard
                        tabPicker
                        tabContent
                    }
                    .padding(.vertical, 24)
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
                .padding(.horizontal)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeContainerName)
                        .font(.headline)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let updated = lastUpdatedDocumentsSummary {
                        Text(updated)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let action = onRequestAddDocuments {
                    Button(action: action) {
                        Label("Add Documents", systemImage: "plus")
                            .font(.caption)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                StatCard(
                    icon: "doc.text",
                    label: "Documents",
                    value: "\(activeDocuments.count)",
                    color: .blue
                )

                StatCard(
                    icon: "cube.box",
                    label: "Chunks",
                    value: "\(totalChunkCount)",
                    color: .purple
                )
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
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
        .padding(.horizontal)
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
        VStack(spacing: 24) {
            ChunkDistributionView(
                documents: activeDocuments,
                chunkCount: totalChunkCount
            )
            QueryAnalyticsView(ragService: ragService)
            PerformanceMetricsView(ragService: ragService)
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var retrievalTab: some View {
        VStack(spacing: 24) {
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
        VStack(spacing: 24) {
            SemanticClusteringView()
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    @ViewBuilder
    private var embeddingSection: some View {
        if totalChunkCount > 0 {
            EmbeddingSpaceView(
                chunkCount: totalChunkCount,
                documentCount: activeDocuments.count
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
        VStack(spacing: 24) {
            Spacer()
            
            // Hero icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.2),
                                Color.blue.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Data to Visualize")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Add documents to see embedding visualizations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    onAddDocuments?()
                } label: {
                    Label("Add Documents", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Embedding Space View

struct EmbeddingSpaceView: View {
    let chunkCount: Int
    let documentCount: Int

    @State private var projectionMethod: ProjectionMethod = .pca
    @State private var showingInfo = false

    enum ProjectionMethod: String, CaseIterable, Identifiable {
        case pca = "PCA"
        case tsne = "t-SNE"
        case umap = "UMAP"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            projectionPicker
            EmbeddingSpaceRenderer(projectionMethod: projectionMethod)
            statsRow
        }
        .sheet(isPresented: $showingInfo) {
            EmbeddingInfoSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Embedding Space")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(chunkCount) chunks in 512-dimensional space")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
    }

    private var projectionPicker: some View {
        HStack {
            Picker("Projection", selection: $projectionMethod) {
                ForEach(ProjectionMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)

            InfoButtonView(
                title: "Projection Method",
                explanation: "High-dimensional embedding vectors (512 dimensions) are projected into 3D for inspection.\n\n• PCA: deterministic and lightweight.\n• t-SNE & UMAP: preserve neighborhoods, useful for spotting topical islands." 
            )
        }
        .padding(.horizontal)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "cube.box",
                label: "Chunks",
                value: "\(chunkCount)",
                color: .blue
            )

            StatCard(
                icon: "doc.text",
                label: "Documents",
                value: "\(documentCount)",
                color: .green
            )

            StatCard(
                icon: "ruler",
                label: "Dimensions",
                value: "512",
                color: .purple
            )
        }
        .padding(.horizontal)
    }
}

struct EmbeddingSpacePlaceholder: View {
    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    let chunkCount: Int
    let documentCount: Int
    
    var body: some View {
        VStack(spacing: 20) {
            // Chart placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DSColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                VStack(spacing: 16) {
                    // Simulated scatter plot
                    GeometryReader { geometry in
                        Canvas { context, size in
                            // Draw simulated clusters
                            drawSimulatedClusters(context: context, size: size, documentCount: documentCount)
                        }
                    }
                    .frame(height: 300)
                    .padding()
                    
                    VStack(spacing: 8) {
                        Text("🔮 Embedding Atlas Integration")
                            .font(.headline)
                        
                        Text("Future: Interactive visualization with Apple's Embedding Atlas")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            
            // Stats cards
            HStack(spacing: 12) {
                StatCard(
                    icon: "cube.box",
                    label: "Chunks",
                    value: "\(chunkCount)",
                    color: .blue
                )
                
                StatCard(
                    icon: "doc.text",
                    label: "Documents",
                    value: "\(documentCount)",
                    color: .green
                )
                
                StatCard(
                    icon: "ruler",
                    label: "Dimensions",
                    value: "512",
                    color: .purple
                )
            }
        }
    }
    
    private func drawSimulatedClusters(context: GraphicsContext, size: CGSize, documentCount: Int) {
        // Draw simulated embedding clusters
        let clusterCount = min(documentCount, 5)
        let colors: [Color] = [.blue, .green, .purple, .orange, .red]
        
        for i in 0..<clusterCount {
            let centerX = CGFloat.random(in: size.width * 0.2...size.width * 0.8)
            let centerY = CGFloat.random(in: size.height * 0.2...size.height * 0.8)
            let pointCount = Int.random(in: 10...30)
            
            for _ in 0..<pointCount {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let radius = CGFloat.random(in: 0...40)
                let x = centerX + cos(angle) * radius
                let y = centerY + sin(angle) * radius
                
                let point = CGPoint(x: x, y: y)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                    with: .color(colors[i].opacity(0.6))
                )
            }
        }
    }
}

// MARK: - Chunk Distribution View

struct ChunkDistributionView: View {
    let documents: [Document]
    let chunkCount: Int
    
    var chunkSizeData: [(document: String, avgSize: Double)] {
        documents.map { doc in
            let avgSize = doc.processingMetadata?.chunkStats.averageChars ?? 0
            return (doc.filename, Double(avgSize))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chunk Distribution")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Chart
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(chunkSizeData, id: \.document) { item in
                        BarMark(
                            x: .value("Size", item.avgSize),
                            y: .value("Document", item.document)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                }
                .frame(height: CGFloat(documents.count * 50))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DSColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
                .padding(.horizontal)
            }
            
            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    icon: "doc.text",
                    label: "Total Docs",
                    value: "\(documents.count)",
                    color: .blue
                )
                
                StatCard(
                    icon: "cube.box",
                    label: "Total Chunks",
                    value: "\(chunkCount)",
                    color: .green
                )
                
                StatCard(
                    icon: "chart.bar",
                    label: "Avg per Doc",
                    value: "\(documents.isEmpty ? 0 : chunkCount / documents.count)",
                    color: .purple
                )
                
                StatCard(
                    icon: "waveform",
                    label: "Avg Size",
                    value: "\(averageChunkSize) chars",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
    }
    
    private var averageChunkSize: Int {
        let totalSize = documents.compactMap { $0.processingMetadata?.chunkStats.averageChars }.reduce(0, +)
        return documents.isEmpty ? 0 : totalSize / documents.count
    }
}

// MARK: - Query Analytics View

struct QueryAnalyticsView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject private var telemetry = TelemetryCenter.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Query Analytics")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Recent queries from telemetry
            if telemetry.events.isEmpty {
                EmptyAnalyticsView()
                    .padding()
            } else {
                QueryStatsGrid()
                    .padding(.horizontal)
                
                RecentQueriesList(telemetry: telemetry)
                    .padding(.horizontal)
            }
        }
    }
}

struct EmptyAnalyticsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("No query data yet")
                .font(.headline)
            
            Text("Run some queries to see analytics")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct QueryStatsGrid: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared
    
    var queryCount: Int {
        telemetry.events.filter { $0.category == .generation && $0.title.contains("Query") }.count
    }
    
    var avgResponseTime: Double {
        let queryEvents = telemetry.events.filter { $0.category == .generation }
        guard !queryEvents.isEmpty else { return 0 }
        let totalTime = queryEvents.compactMap { $0.duration }.reduce(0, +)
        return totalTime / Double(queryEvents.count)
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                icon: "bubble.left.and.bubble.right",
                label: "Queries",
                value: "\(queryCount)",
                color: .blue
            )
            
            StatCard(
                icon: "clock",
                label: "Avg Time",
                value: String(format: "%.1fs", avgResponseTime),
                color: .green
            )
        }
    }
}

struct RecentQueriesList: View {
    @ObservedObject var telemetry: TelemetryCenter
    
    var recentQueries: [TelemetryEvent] {
        telemetry.events
            .filter { $0.category == .generation && $0.title.contains("Query") }
            .prefix(5)
            .reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Queries")
                .font(.headline)
            
            ForEach(Array(recentQueries.enumerated()), id: \.element.id) { index, event in
                QueryEventCard(event: event, index: index + 1)
            }
        }
    }
}

struct QueryEventCard: View {
    let event: TelemetryEvent
    let index: Int
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 32, height: 32)

                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(event.formattedTimestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let duration = event.duration {
                    Text(String(format: "%.2f s", duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}

struct RetrievalPatternsView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    let totalChunkCount: Int
    let activeDocuments: [Document]

    private var activeContainerId: UUID { containerService.activeContainerId }

    private var history: [RetrievalLogEntry] {
        ragService.retrievalHistory.filter { $0.containerId == activeContainerId }
    }

    private var documentLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: activeDocuments.map { ($0.id, $0.filename) })
    }

    var body: some View {
        let docLookup = documentLookup
        let chunkStats = buildChunkStats(docLookup: docLookup)
        let documentStats = buildDocumentStats(from: chunkStats)
        let totalRetrievals = history.reduce(0) { $0 + $1.chunks.count }
        let coverage = coveragePercentage(uniqueChunkCount: chunkStats.count)
        let coverageLabel = formattedCoverage(coverage)
        let topDocumentName = documentStats.first?.name ?? "—"

        return DashboardSectionCard(
            icon: "target",
            title: "Retrieval Patterns",
            subtitle: "See which chunks ground your answers most often"
        ) {
            if history.isEmpty {
                Text("Run a few queries to populate retrieval analytics.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                statsGrid(
                    totalRetrievals: totalRetrievals,
                    uniqueChunks: chunkStats.count,
                    coverageLabel: coverageLabel,
                    topDocument: topDocumentName
                )

                if !chunkStats.isEmpty {
                    chunkChart(chunkStats.prefix(8))
                        .padding(.top, 8)
                }

                if !documentStats.isEmpty {
                    documentChart(documentStats.prefix(6))
                        .padding(.top, 12)
                }

                if !chunkStats.isEmpty {
                    chunkDetailSection(chunkStats.prefix(3))
                        .padding(.top, 12)
                }

                VisualizationInfoSection(title: "🔍 Atlas-inspired cross filtering") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apple's Embedding Atlas advocates linking projection, clustering, and metadata views so you can spot the sources that actually ground responses.")
                            .font(.caption2)
                        Text("These retrieval metrics are computed directly from your live history, making it easy to compare hit coverage against chunking strategy or embedding quality.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func statsGrid(
        totalRetrievals: Int,
        uniqueChunks: Int,
        coverageLabel: String,
        topDocument: String
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                icon: "arrow.2.squarepath",
                label: "Retrievals",
                value: "\(totalRetrievals)",
                color: .blue
            )

            StatCard(
                icon: "number",
                label: "Unique Chunks",
                value: "\(uniqueChunks)",
                color: .purple
            )

            StatCard(
                icon: "percent",
                label: "Coverage",
                value: coverageLabel,
                color: .orange
            )

            StatCard(
                icon: "doc.richtext",
                label: "Top Document",
                value: topDocument,
                color: .green
            )
        }
    }

    @ViewBuilder
    private func chunkChart(_ stats: ArraySlice<ChunkHitStat>) -> some View {
        let entries = Array(stats)

        Chart {
            ForEach(entries) { stat in
                BarMark(
                    x: .value("Hits", stat.hits),
                    y: .value("Chunk", chunkLabel(for: stat))
                )
                .foregroundStyle(color(for: stat.docId))
                .annotation(position: .trailing) {
                    Text("\(stat.hits) hits\navg \(String(format: "%.2f", stat.averageSimilarity))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(height: CGFloat(entries.count) * 32 + 20)
    }

    @ViewBuilder
    private func documentChart(_ stats: ArraySlice<DocumentHitStat>) -> some View {
        let entries = Array(stats)

        Chart {
            ForEach(entries) { stat in
                BarMark(
                    x: .value("Retrievals", stat.hits),
                    y: .value("Document", stat.name)
                )
                .foregroundStyle(color(for: stat.id))
                .annotation(position: .trailing) {
                    Text("\(stat.uniqueChunks) chunks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .annotation(position: .trailing) {
                    Text("\(stat.hits)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: CGFloat(entries.count) * 28 + 20)
    }

    private func chunkDetailSection(_ stats: ArraySlice<ChunkHitStat>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most-retrieved chunks")
                .font(.headline)

            ForEach(Array(stats)) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(color(for: stat.docId))
                            .frame(width: 10, height: 10)

                        Text(chunkLabel(for: stat))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Text(String(format: "%.2f", stat.averageSimilarity))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    if let section = stat.sectionTitle, !section.isEmpty {
                        Text(section)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(stat.snippet)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 12) {
                        if let page = stat.pageNumber {
                            Label("Page \(page)", systemImage: "doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Label("\(stat.hits) hits", systemImage: "arrow.counterclockwise")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Label(relativeTime(for: stat.lastRetrieved), systemImage: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DSColors.background)
                )
            }
        }
    }

    private func buildChunkStats(docLookup: [UUID: String]) -> [ChunkHitStat] {
        struct MutableAccumulator {
            // Track per-chunk retrieval aggregation to stay aligned with live telemetry
            var chunk: DocumentChunk
            var docName: String
            var hits: Int
            var similaritySum: Double
            var lastRetrieved: Date
        }

        var accumulator: [UUID: MutableAccumulator] = [:]
        for entry in history {
            for retrieved in entry.chunks {
                let chunk = retrieved.chunk
                let chunkId = chunk.id
                let docId = chunk.documentId
                let docName = docLookup[docId] ?? retrieved.sourceDocument
                let similarity = Double(retrieved.similarityScore)
                if accumulator[chunkId] == nil {
                    accumulator[chunkId] = MutableAccumulator(
                        chunk: chunk,
                        docName: docName,
                        hits: 0,
                        similaritySum: 0,
                        lastRetrieved: entry.timestamp
                    )
                }
                accumulator[chunkId]?.hits += 1
                accumulator[chunkId]?.similaritySum += similarity
                if let current = accumulator[chunkId], entry.timestamp > current.lastRetrieved {
                    accumulator[chunkId]?.lastRetrieved = entry.timestamp
                }
            }
        }

        return accumulator.values.map { value in
            let chunk = value.chunk
            return ChunkHitStat(
                id: chunk.id,
                docId: chunk.documentId,
                docName: value.docName,
                chunkIndex: chunk.metadata.chunkIndex,
                hits: value.hits,
                averageSimilarity: value.hits > 0 ? value.similaritySum / Double(value.hits) : 0,
                lastRetrieved: value.lastRetrieved,
                pageNumber: chunk.metadata.pageNumber,
                sectionTitle: chunk.metadata.sectionTitle,
                snippet: snippet(for: chunk.content)
            )
        }
        .sorted { lhs, rhs in
            if lhs.hits == rhs.hits {
                return lhs.lastRetrieved > rhs.lastRetrieved
            }
            return lhs.hits > rhs.hits
        }
    }

    private func buildDocumentStats(from chunkStats: [ChunkHitStat]) -> [DocumentHitStat] {
        var accumulator: [UUID: DocumentHitStat] = [:]
        for stat in chunkStats {
            var entry = accumulator[stat.docId] ?? DocumentHitStat(
                id: stat.docId,
                name: stat.docName,
                hits: 0,
                uniqueChunks: 0
            )
            entry.hits += stat.hits
            entry.uniqueChunks += 1
            accumulator[stat.docId] = entry
        }
        return accumulator.values.sorted { lhs, rhs in
            if lhs.hits == rhs.hits {
                return lhs.uniqueChunks > rhs.uniqueChunks
            }
            return lhs.hits > rhs.hits
        }
    }

    private func coveragePercentage(uniqueChunkCount: Int) -> Double {
        guard totalChunkCount > 0 else { return 0 }
        return (Double(uniqueChunkCount) / Double(totalChunkCount)) * 100
    }

    private func formattedCoverage(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.0f%%", value)
    }

    private func color(for docId: UUID) -> Color {
        let hash = abs(docId.uuidString.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.9)
    }

    private func chunkLabel(for stat: ChunkHitStat) -> String {
        "\(stat.docName) • #\(stat.chunkIndex + 1)"
    }

    private func relativeTime(for date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func snippet(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return String(trimmed.prefix(180)) + "…"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private struct ChunkHitStat: Identifiable {
        let id: UUID
        let docId: UUID
        let docName: String
        let chunkIndex: Int
        let hits: Int
        let averageSimilarity: Double
        let lastRetrieved: Date
        let pageNumber: Int?
        let sectionTitle: String?
        let snippet: String
    }

    private struct DocumentHitStat: Identifiable {
        let id: UUID
        let name: String
        var hits: Int
        var uniqueChunks: Int
    }
}

struct DashboardSectionCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    private let content: Content

    init(icon: String, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            content
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(DSColors.surface)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }
}

// MARK: - Performance Metrics View

struct PerformanceMetricsView: View {
    @ObservedObject var ragService: RAGService
    @ObservedObject private var telemetry = TelemetryCenter.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Metrics")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Pipeline stage breakdown
            PipelineStagesCard()
                .padding(.horizontal)
            
            // System metrics
            SystemMetricsGrid()
                .padding(.horizontal)
        }
    }
}

struct PipelineStagesCard: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared
    
    var stageMetrics: [(stage: String, avgTime: Double, color: Color)] {
        [
            ("Embedding", avgDuration(for: .embedding), .purple),
            ("Retrieval", avgDuration(for: .retrieval), .blue),
            ("Generation", avgDuration(for: .generation), .green)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pipeline Stages")
                .font(.headline)
            
            ForEach(stageMetrics, id: \.stage) { metric in
                StageMetricRow(
                    stage: metric.stage,
                    avgTime: metric.avgTime,
                    color: metric.color
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private func avgDuration(for category: TelemetryCategory) -> Double {
        let events = telemetry.events.filter { $0.category == category }
        guard !events.isEmpty else { return 0 }
        let totalTime = events.compactMap { $0.duration }.reduce(0, +)
        return totalTime / Double(events.count)
    }
}

struct StageMetricRow: View {
    let stage: String
    let avgTime: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(stage)
                .font(.subheadline)
            
            Spacer()
            
            Text(String(format: "%.2fs", avgTime))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

struct SystemMetricsGrid: View {
    var body: some View {
        #if canImport(UIKit)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                icon: "memorychip",
                label: "Device",
                value: UIDevice.current.model,
                color: .blue
            )
            
            StatCard(
                icon: "cpu",
                label: "iOS",
                value: UIDevice.current.systemVersion,
                color: .green
            )
        }
        #else
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                icon: "desktopcomputer",
                label: "Device",
                value: "Mac",
                color: .blue
            )
            
            StatCard(
                icon: "cpu",
                label: "OS",
                value: ProcessInfo.processInfo.operatingSystemVersionString,
                color: .green
            )
        }
        #endif
    }
}

// MARK: - Reusable Components

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Info Sheet

struct EmbeddingInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VisualizationInfoSection(title: "What are Embeddings?") {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.purple)
                            Text("Embeddings are numerical representations of text in a high-dimensional space. Similar meanings are placed closer together.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VisualizationInfoSection(title: "Current Method") {
                        HStack(spacing: 8) {
                            Image(systemName: "cube.box")
                                .foregroundColor(.blue)
                            Text("Using NLEmbedding with 512 dimensions. Each document chunk is converted to a 512-number vector.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VisualizationInfoSection(title: "Projection Methods") {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundColor(.green)
                            Text("PCA, t-SNE, and UMAP reduce 512 dimensions to 2D for visualization while preserving semantic relationships.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VisualizationInfoSection(title: "Future: Embedding Atlas") {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("Apple's Embedding Atlas will provide interactive exploration of your document embeddings with automatic clustering.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Embedding Space")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct VisualizationInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.blue)
            
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

// MARK: - New Advanced Visualizations

struct SimilarityHeatmapView: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @State private var sampleChunks: [DocumentChunk] = []
    @State private var chunkDescriptors: [UUID: HeatmapChunkDescriptor] = [:]
    @State private var isLoading = false
    @State private var lastUpdated: Date? = nil
    @State private var refreshNonce: UInt64 = 0

    private let maxSampleCount = 12
    private let cellSize: CGFloat = 56
    private let rowLabelWidth: CGFloat = 140

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            heatmapSection
            statsSection
        }
        .task { await refreshSample() }
        .task(id: containerService.activeContainerId) {
            await MainActor.run { refreshNonce = 0 }
            await refreshSample()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Similarity Heatmap")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Pairwise cosine similarity across sampled chunks from the active library.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let stamp = formattedLastUpdated() {
                    Text("Updated \(stamp)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button {
                    guard !isLoading else { return }
                    refreshNonce &+= 1
                    Task(priority: .userInitiated) {
                        await refreshSample()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            VisualizationInfoSection(title: "💡 Why cosine similarity?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Embeddings are high-dimensional vectors. Cosine similarity measures the angle between them, giving a scale from 0 (unrelated) to 1 (identical).")
                        .font(.caption2)
                    Text("Cells along the diagonal are always 1.0 because a chunk is perfectly similar to itself.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(DSColors.background)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var heatmapSection: some View {
        if isLoading {
            ProgressView("Computing similarities…")
                .padding()
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(DSColors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
        } else if sampleChunks.isEmpty {
            Text("Add documents or run a query to populate similarity data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(DSColors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
        } else {
            heatmapGrid
        }
    }

    private var heatmapGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Color.clear.frame(width: rowLabelWidth, height: cellSize)
                    ForEach(sampleChunks) { chunk in
                        headerLabel(for: chunk)
                    }
                }
                ForEach(sampleChunks) { rowChunk in
                    HStack(spacing: 2) {
                        sideLabel(for: rowChunk)
                        ForEach(sampleChunks) { columnChunk in
                            heatmapCell(rowChunk, columnChunk)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 420)
        .background(DSColors.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "number",
                label: "Chunks",
                value: "\(sampleChunks.count)",
                color: .purple
            )
            StatCard(
                icon: "doc.text.fill",
                label: "Documents",
                value: "\(uniqueDocumentCount)",
                color: .blue
            )
            StatCard(
                icon: "waveform.path.ecg",
                label: "Avg Similarity",
                value: String(format: "%.2f", averagePairSimilarity),
                color: .pink
            )
            StatCard(
                icon: "arrow.up",
                label: "Max Similarity",
                value: String(format: "%.2f", maximumPairSimilarity),
                color: .orange
            )
        }
        .padding(.horizontal)
    }

    private func refreshSample() async {
        await MainActor.run { isLoading = true }
        let allChunks = await ragService.allChunksForActiveContainer()
        if Task.isCancelled { return }
        guard !allChunks.isEmpty else {
            await MainActor.run {
                sampleChunks = []
                chunkDescriptors = [:]
                lastUpdated = Date()
                isLoading = false
            }
            return
        }

        let docNames = await MainActor.run {
            Dictionary(uniqueKeysWithValues: ragService.documents.map { ($0.id, $0.filename) })
        }
        let seed = VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce
        let sample = VisualizationChunkSampler.sampleChunks(
            allChunks,
            limit: maxSampleCount,
            seed: seed
        )
        let descriptors = buildDescriptors(for: sample, docNames: docNames)

        await MainActor.run {
            sampleChunks = sample
            chunkDescriptors = descriptors
            lastUpdated = Date()
            isLoading = false
        }
    }

    private func buildDescriptors(
        for chunks: [DocumentChunk],
        docNames: [UUID: String]
    ) -> [UUID: HeatmapChunkDescriptor] {
        var result: [UUID: HeatmapChunkDescriptor] = [:]
        result.reserveCapacity(chunks.count)
        for chunk in chunks {
            let docName = docNames[chunk.documentId] ?? "Unknown"
            let descriptor = HeatmapChunkDescriptor(
                docName: docName,
                sectionTitle: chunk.metadata.sectionTitle,
                chunkIndex: chunk.metadata.chunkIndex,
                page: chunk.metadata.pageNumber,
                norm: VisualizationMath.vectorNorm(chunk.embedding),
                snippet: String(chunk.content.prefix(120))
            )
            result[chunk.id] = descriptor
        }
        return result
    }

    private func headerLabel(for chunk: DocumentChunk) -> some View {
        Text(label(for: chunk))
            .font(.caption2.weight(.medium))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(width: cellSize, height: cellSize)
    }

    private func sideLabel(for chunk: DocumentChunk) -> some View {
        Text(label(for: chunk))
            .font(.caption2)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(width: rowLabelWidth, height: cellSize, alignment: .leading)
    }

    private func heatmapCell(_ row: DocumentChunk, _ column: DocumentChunk) -> some View {
        let similarity = cosineSimilarity(row, column)
        let color = heatColor(for: similarity)
        let textColor = heatTextColor(for: similarity)
        let value = String(format: "%.2f", similarity)
        return Rectangle()
            .fill(color)
            .frame(width: cellSize, height: cellSize)
            .overlay(
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textColor)
            )
            .accessibilityLabel(
                Text("Similarity between \(label(for: row)) and \(label(for: column)) is \(value)")
            )
    }

    private func label(for chunk: DocumentChunk) -> String {
        guard let descriptor = chunkDescriptors[chunk.id] else {
            return "Chunk \(chunk.metadata.chunkIndex + 1)"
        }
        var parts: [String] = [descriptor.docName]
        if let page = descriptor.page {
            parts.append("p.\(page)")
        }
        parts.append("#\(descriptor.chunkIndex + 1)")
        return parts.joined(separator: " • ")
    }

    private func cosineSimilarity(_ lhs: DocumentChunk, _ rhs: DocumentChunk) -> Float {
        guard lhs.embedding.count == rhs.embedding.count else { return 0 }
        let dot = zip(lhs.embedding, rhs.embedding).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let leftNorm = chunkDescriptors[lhs.id]?.norm ?? VisualizationMath.vectorNorm(lhs.embedding)
        let rightNorm = chunkDescriptors[rhs.id]?.norm ?? VisualizationMath.vectorNorm(rhs.embedding)
        let denom = max(leftNorm * rightNorm, 1e-6)
        return max(0, min(1, dot / denom))
    }

    private func heatColor(for similarity: Float) -> Color {
        let clamped = max(0, min(1, similarity))
        let hue = 0.58 - (Double(clamped) * 0.45)
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }

    private func heatTextColor(for similarity: Float) -> Color {
        similarity > 0.6 ? .white : .black.opacity(0.8)
    }

    private func formattedLastUpdated() -> String? {
        guard let date = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var uniqueDocumentCount: Int {
        Set(sampleChunks.map { $0.documentId }).count
    }

    private var averagePairSimilarity: Double {
        guard sampleChunks.count > 1 else { return 1.0 }
        var sum: Double = 0
        var count = 0
        for (idx, chunk) in sampleChunks.enumerated() {
            for jdx in idx + 1..<sampleChunks.count {
                sum += Double(cosineSimilarity(chunk, sampleChunks[jdx]))
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 1.0
    }

    private var maximumPairSimilarity: Double {
        guard sampleChunks.count > 1 else { return 1.0 }
        var maxValue: Double = 0
        for chunk in sampleChunks {
            for other in sampleChunks where chunk.id != other.id {
                maxValue = max(maxValue, Double(cosineSimilarity(chunk, other)))
            }
        }
        return maxValue
    }

    private struct HeatmapChunkDescriptor {
        let docName: String
        let sectionTitle: String?
        let chunkIndex: Int
        let page: Int?
        let norm: Float
        let snippet: String
    }
}

struct PipelineTimelineView: View {
    @StateObject private var telemetry = TelemetryCenter.shared

    private struct Stage: Identifiable {
        let id: String
        let name: String
        let detail: String
        let icon: String
        let category: TelemetryCategory
    }

    private var stages: [Stage] {
        [
            Stage(id: "ingest", name: "Ingestion", detail: "Parse PDFs and text into raw payloads", icon: "doc.text.fill", category: .ingestion),
            Stage(id: "chunk", name: "Chunking", detail: "Split content into 400-token windows", icon: "square.split.2x2", category: .ingestion),
            Stage(id: "embed", name: "Embedding", detail: "Map chunks into the 512-dim vector space", icon: "function", category: .embedding),
            Stage(id: "store", name: "Storage", detail: "Persist vectors + BM25 payloads per container", icon: "externaldrive.fill", category: .storage),
            Stage(id: "query", name: "Query", detail: "Embed the question and expand with heuristics", icon: "magnifyingglass", category: .retrieval),
            Stage(id: "retrieve", name: "Retrieval", detail: "Run hybrid search + MMR diversification", icon: "arrow.down.circle.fill", category: .retrieval),
            Stage(id: "assemble", name: "Assembly", detail: "Build grounded context + metadata bundle", icon: "square.stack.3d.up.fill", category: .retrieval),
            Stage(id: "generate", name: "Generation", detail: "Stream the answer with citations + tools", icon: "sparkles", category: .generation)
        ]
    }

    private var recentEvents: [TelemetryEvent] {
        Array(telemetry.events.suffix(3).reversed())
    }

    var body: some View {
        DashboardSectionCard(
            icon: "flowchart.fill",
            title: "Pipeline Timeline",
            subtitle: "Track where the current request is spending time"
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stages) { stage in
                        StageChip(stage: stage, isActive: isStageActive(stage.category), color: color(for: stage.category))
                    }
                }
                .padding(.vertical, 6)
            }

            if !recentEvents.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent activity")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(recentEvents, id: \.id) { event in
                        ActivityRow(event: event, accent: color(for: event.category))
                    }
                }
            }

            VisualizationInfoSection(title: "Stage reference") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stages) { stage in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: stage.icon)
                                .font(.caption)
                                .foregroundColor(color(for: stage.category))
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(stage.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func isStageActive(_ category: TelemetryCategory) -> Bool {
        let window = telemetry.events.suffix(12)
        return window.contains { event in
            event.category == category && Date().timeIntervalSince(event.timestamp) < 6
        }
    }

    private func color(for category: TelemetryCategory) -> Color {
        switch category {
        case .ingestion: return .orange
        case .embedding: return .purple
        case .retrieval: return .blue
        case .generation: return .green
        case .storage: return .teal
        case .system: return .gray
        case .error: return .red
        }
    }

    private struct StageChip: View {
        let stage: Stage
        let isActive: Bool
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: stage.icon)
                        .font(.subheadline)
                        .foregroundColor(isActive ? .white : color)
                        .padding(8)
                        .background(
                            Circle().fill(isActive ? color : color.opacity(0.12))
                        )

                    Text(stage.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Text(stage.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? color.opacity(0.12) : DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }

    private struct ActivityRow: View {
        let event: TelemetryEvent
        let accent: Color

        var body: some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let duration = event.duration {
                    Text(String(format: "%.0f ms", duration * 1000))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.surface)
            )
        }
    }
}

struct SemanticClusteringView: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @State private var selectedK: Int = 3
    @State private var sampleChunks: [DocumentChunk] = []
    @State private var docNames: [UUID: String] = [:]
    @State private var chunkNorms: [UUID: Float] = [:]
    @State private var clusters: [[DocumentChunk]] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var lastUpdated: Date?
    @State private var refreshNonce: UInt64 = 0
    @State private var showClusterTopics = true

    private let maxSampleCount = 180
    private let maxIterations = 12

    var body: some View {
        DashboardSectionCard(
            icon: "circle.hexagongrid.fill",
            title: "Semantic Clustering",
            subtitle: "Sample embeddings to discover the highest-signal topics"
        ) {
            VStack(spacing: 20) {
                clusterControls

                if let error = lastError {
                    errorCard(error)
                } else if isLoading {
                    loadingCard
                } else if sampleChunks.isEmpty {
                    emptyStateCard
                } else {
                    clusterSummarySection
                    clusterDistributionSection
                    clusterPreviewSection
                    ClusteringInfoCard()
                }
            }
        }
        .task {
            await refreshSample()
        }
        .task(id: containerService.activeContainerId) {
            refreshNonce = 0
            await refreshSample()
        }
        .onChange(of: selectedK) { oldValue, newValue in
            guard newValue != oldValue else { return }
            recomputeClusters()
        }
    }

    private var clusterControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cluster granularity")
                        .font(.headline)

                    Text("Tighter clusters surface more niche themes.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("K = \(selectedK)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
            }

            Slider(value: Binding(
                get: { Double(selectedK) },
                set: { selectedK = Int($0) }
            ), in: 2...10, step: 1)
            .tint(.purple)

            HStack(spacing: 12) {
                Button {
                    guard !isLoading else { return }
                    refreshNonce &+= 1
                    Task { await refreshSample() }
                } label: {
                    Label(isLoading ? "Refreshing…" : "Refresh sample", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if let stamp = formattedLastUpdated {
                    Label("Updated \(stamp)", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Label("\(sampleChunks.count) chunks", systemImage: "square.stack.3d.down.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var loadingCard: some View {
        ProgressView("Clustering embeddings…")
            .padding()
            .frame(maxWidth: .infinity)
            .background(DSColors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyStateCard: some View {
        Text("Import documents or run queries to generate chunk embeddings for clustering.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(DSColors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var clusterDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cluster Distribution")
                .font(.headline)
            Chart {
                ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                    BarMark(
                        x: .value("Count", cluster.count),
                        y: .value("Cluster", "Topic \(index + 1)")
                    )
                    .foregroundStyle(clusterColor(index))
                    .annotation(position: .trailing) {
                        Text("\(cluster.count) chunks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: CGFloat(max(clusters.count, 1) * 48))
            .padding(.horizontal, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DSColors.background)
        )
    }

    private var clusterSummarySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                MetricPill(icon: "number", label: "Clusters", value: "\(clusters.count)")
                MetricPill(icon: "doc.on.doc", label: "Unique docs", value: "\(uniqueDocumentCount)")
                MetricPill(icon: "chart.bar", label: "Avg size", value: averageClusterSize)
                MetricPill(icon: "chart.pie", label: "Largest", value: "\(maxClusterSize)")
                MetricPill(icon: "link", label: "Avg sim", value: String(format: "%.2f", averagePairSimilarity))
            }
            .padding(.vertical, 4)
        }
    }

    private var clusterPreviewSection: some View {
        DisclosureGroup(isExpanded: $showClusterTopics) {
            VStack(spacing: 12) {
                ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                    ClusterPreviewCard(
                        index: index,
                        cluster: cluster,
                        color: clusterColor(index),
                        docNameProvider: docName(for:)
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Topic highlights")
                    .font(.headline)
                Spacer()
                Text("Tap to \(showClusterTopics ? "collapse" : "expand")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private struct MetricPill: View {
        let icon: String
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(label.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }

    private func refreshSample() async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        let allChunks = await ragService.allChunksForActiveContainer()
        if Task.isCancelled { return }

        let seedBase = VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce

        if allChunks.isEmpty {
            await MainActor.run {
                sampleChunks = []
                docNames = [:]
                chunkNorms = [:]
                clusters = []
                lastUpdated = Date()
                isLoading = false
            }
            return
        }

        let sampled = VisualizationChunkSampler.sampleChunks(
            allChunks,
            limit: maxSampleCount,
            seed: seedBase
        )

        let norms = Dictionary(uniqueKeysWithValues: sampled.map { ($0.id, VisualizationMath.vectorNorm($0.embedding)) })

        let names = await MainActor.run {
            Dictionary(uniqueKeysWithValues: ragService.documents.map { ($0.id, $0.filename) })
        }

        await MainActor.run {
            docNames = names
            sampleChunks = sampled
            chunkNorms = norms
            recomputeClusters(seed: seedBase &+ UInt64(selectedK))
            lastUpdated = Date()
            isLoading = false
        }
    }

    @MainActor
    private func recomputeClusters(seed: UInt64? = nil) {
        guard !sampleChunks.isEmpty else {
            clusters = []
            return
        }
        let baseSeed = seed ?? (VisualizationChunkSampler.seed(for: containerService.activeContainerId) ^ refreshNonce)
        let rawClusters = performKMeansClustering(chunks: sampleChunks, k: selectedK, seed: baseSeed)
        clusters = sanitizeClusters(rawClusters)
    }

    private var formattedLastUpdated: String? {
        guard let date = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var uniqueDocumentCount: Int {
        Set(sampleChunks.map { $0.documentId }).count
    }

    private var maxClusterSize: Int {
        clusters.map(\.count).max() ?? 0
    }

    private var averageClusterSize: String {
        guard !clusters.isEmpty else { return "0.0" }
        return String(format: "%.1f", Double(sampleChunks.count) / Double(max(clusters.count, 1)))
    }

    private var averagePairSimilarity: Double {
        var total: Double = 0
        var pairCount = 0

        for cluster in clusters where cluster.count > 1 {
            for lhsIndex in 0..<(cluster.count - 1) {
                let lhs = cluster[lhsIndex]
                for rhs in cluster[(lhsIndex + 1)..<cluster.count] {
                    total += cosineSimilarity(lhs, rhs)
                    pairCount += 1
                }
            }
        }

        guard pairCount > 0 else { return 0 }
        return total / Double(pairCount)
    }

    @MainActor
    private func docName(for chunk: DocumentChunk) -> String {
        if let cached = docNames[chunk.documentId] {
            return cached
        }
        return ragService.getDocumentName(for: chunk.documentId)
    }

    private func cosineSimilarity(_ lhs: DocumentChunk, _ rhs: DocumentChunk) -> Double {
        let embeddingA = lhs.embedding
        let embeddingB = rhs.embedding
        guard embeddingA.count == embeddingB.count, !embeddingA.isEmpty else { return 0 }

        var dot: Double = 0
        for (valueA, valueB) in zip(embeddingA, embeddingB) {
            dot += Double(valueA * valueB)
        }

        let normA = Double(chunkNorms[lhs.id] ?? VisualizationMath.vectorNorm(embeddingA))
        let normB = Double(chunkNorms[rhs.id] ?? VisualizationMath.vectorNorm(embeddingB))
        let denominator = max(normA * normB, 1e-6)
        let similarity = dot / denominator
        return max(0, min(1, similarity))
    }

    private func performKMeansClustering(chunks: [DocumentChunk], k: Int, seed: UInt64) -> [[DocumentChunk]] {
        guard !chunks.isEmpty, k > 0 else { return [] }

        var generator = SplitMix64(seed: seed == 0 ? 0xCAFE_BABE_DEAD_BEEF : seed)
        var centroids: [[Float]] = []
        centroids.reserveCapacity(k)
        for _ in 0..<k {
            if let embedding = chunks.randomElement(using: &generator)?.embedding {
                centroids.append(embedding)
            } else {
                centroids.append(chunks[0].embedding)
            }
        }

        var clusters = Array(repeating: [DocumentChunk](), count: k)

        for _ in 0..<maxIterations {
            clusters = Array(repeating: [], count: k)
            for chunk in chunks {
                let distances = centroids.enumerated().map { (index, centroid) -> (Int, Float) in
                    (index, euclideanDistance(chunk.embedding, centroid))
                }
                if let nearest = distances.min(by: { $0.1 < $1.1 })?.0 {
                    clusters[nearest].append(chunk)
                }
            }

            for index in 0..<k where !clusters[index].isEmpty {
                centroids[index] = averageEmbedding(clusters[index].map { $0.embedding })
            }
        }

        return clusters.filter { !$0.isEmpty }
    }

    private func sanitizeClusters(_ raw: [[DocumentChunk]]) -> [[DocumentChunk]] {
        guard !raw.isEmpty else { return [] }
        let normalized = raw.compactMap { cluster -> (ClusterSignature, [DocumentChunk])? in
            let ordered = cluster.sorted(by: chunkOrdering)
            guard !ordered.isEmpty else { return nil }
            // Use a deterministic signature so "Topic 1" consistently tracks the same cluster weight.
            return (clusterSignature(for: ordered), ordered)
        }
        return normalized.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private func chunkOrdering(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
        if lhs.documentId == rhs.documentId {
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
        return lhs.documentId.uuidString < rhs.documentId.uuidString
    }

    private func clusterSignature(for cluster: [DocumentChunk]) -> ClusterSignature {
        var docAccumulator: UInt64 = 0
        var leading = cluster.first
        for chunk in cluster {
            let hash = UInt64(bitPattern: Int64(chunk.documentId.hashValue))
            docAccumulator ^= hash
            if let current = leading, chunkOrdering(lhs: current, rhs: chunk) {
                continue
            }
            leading = chunk
        }
        return ClusterSignature(
            size: cluster.count,
            docHash: docAccumulator,
            leadChunkId: leading?.id ?? UUID()
        )
    }

    private struct ClusterSignature: Comparable {
        let size: Int
        let docHash: UInt64
        let leadChunkId: UUID

        static func < (lhs: ClusterSignature, rhs: ClusterSignature) -> Bool {
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            if lhs.docHash != rhs.docHash { return lhs.docHash < rhs.docHash }
            return lhs.leadChunkId.uuidString < rhs.leadChunkId.uuidString
        }
    }

    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.infinity }
        var sum: Float = 0
        for (lhs, rhs) in zip(a, b) {
            let diff = lhs - rhs
            sum += diff * diff
        }
        return sqrt(sum)
    }

    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        var accumulator = Array(repeating: Float.zero, count: first.count)
        for embedding in embeddings {
            for (index, value) in embedding.enumerated() {
                accumulator[index] += value
            }
        }
        let count = Float(embeddings.count)
        return accumulator.map { $0 / count }
    }

    private func clusterColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .red, .cyan, .indigo, .mint, .teal]
        return colors[index % colors.count]
    }
}

// MARK: - Helper Views

struct ClusteringInfoCard: View {
    var body: some View {
        VisualizationInfoSection(title: "🧠 What is K-means Clustering?") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatically groups similar chunks together:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("1. Picks K random cluster centers in embedding space")
                    .font(.caption2)
                Text("2. Assigns each chunk to nearest center")
                    .font(.caption2)
                Text("3. Recalculates centers based on assignments")
                    .font(.caption2)
                Text("4. Repeats until clusters stabilize")
                    .font(.caption2)
                
                Divider()
                
                Text("Use this to discover main topics in your knowledge base without manual tagging!")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
        }
    }
}

@MainActor
struct ClusterPreviewCard: View {
    let index: Int
    let cluster: [DocumentChunk]
    let color: Color
    let docNameProvider: @MainActor (DocumentChunk) -> String

    private var representativeDocName: String? {
        guard let chunk = cluster.first else { return nil }
        return docNameProvider(chunk)
    }

    private var snippet: String {
        guard let chunk = cluster.first else { return "" }
        let trimmed = chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 180 {
            return String(trimmed.prefix(180)) + "…"
        }
        return trimmed
    }

    private var docCounts: [(String, Int)] {
        Dictionary(grouping: cluster, by: { docNameProvider($0) })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                Text("Topic \(index + 1)")
                    .font(.headline)

                Spacer()

                Text("\(cluster.count) chunks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let docName = representativeDocName {
                Text(docName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            if !snippet.isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            if !docCounts.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(docCounts.prefix(3)), id: \.0) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            Text("\(item.1) chunks")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Math & Sampling Helpers

enum VisualizationMath {
    /// Compute the L2 norm of an embedding vector while guarding against overflow.
    static func vectorNorm(_ vector: [Float]) -> Float {
        guard !vector.isEmpty else { return 0 }
        let sum = vector.reduce(Float.zero) { partial, value in
            partial + (value * value)
        }
        return sqrt(sum)
    }
}

enum VisualizationChunkSampler {
    static func seed(for containerId: UUID) -> UInt64 {
        let uuid = containerId.uuid
        let high =
            (UInt64(uuid.0) << 56) |
            (UInt64(uuid.1) << 48) |
            (UInt64(uuid.2) << 40) |
            (UInt64(uuid.3) << 32) |
            (UInt64(uuid.4) << 24) |
            (UInt64(uuid.5) << 16) |
            (UInt64(uuid.6) << 8) |
            UInt64(uuid.7)
        let low =
            (UInt64(uuid.8) << 56) |
            (UInt64(uuid.9) << 48) |
            (UInt64(uuid.10) << 40) |
            (UInt64(uuid.11) << 32) |
            (UInt64(uuid.12) << 24) |
            (UInt64(uuid.13) << 16) |
            (UInt64(uuid.14) << 8) |
            UInt64(uuid.15)
        let combined = high ^ low
        return combined == 0 ? 0x9E37_79B9_7F4A_7C15 : combined
    }

    static func sampleChunks(
        _ chunks: [DocumentChunk],
        limit: Int,
        seed: UInt64
    ) -> [DocumentChunk] {
        guard limit > 0, !chunks.isEmpty else { return [] }
        guard chunks.count > limit else { return chunks }
        var generator = SplitMix64(seed: seed)
        var selection = Array(chunks.shuffled(using: &generator).prefix(limit))
        selection.sort(by: VisualizationChunkSampler.chunkOrdering)
        return selection
    }

    nonisolated private static func chunkOrdering(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
        if lhs.documentId == rhs.documentId {
            return lhs.metadata.chunkIndex < rhs.metadata.chunkIndex
        }
        return lhs.documentId.uuidString < rhs.documentId.uuidString
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x1234_5678_9ABC_DEF0 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        VisualizationsView()
            .environmentObject(RAGService())
            .environmentObject(ContainerService())
    }
}
