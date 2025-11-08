//
//  VisualizationsView.swift
//  OpenIntelligence
//
//  Data visualization dashboard for embeddings and RAG analytics
//  Created by GitHub Copilot on 10/18/25.
//

import SwiftUI
import Charts

struct VisualizationsView: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @StateObject private var telemetry = TelemetryCenter.shared
    @State private var selectedVisualization: VisualizationType = .embeddingSpace
    @State private var showingExplanation: Bool = false
    @State private var selectedMetricExplanation: String? = nil
    let onRequestAddDocuments: (() -> Void)?
    
    init(onRequestAddDocuments: (() -> Void)? = nil) {
        self.onRequestAddDocuments = onRequestAddDocuments
    }
    
    enum VisualizationType: String, CaseIterable {
        case embeddingSpace = "Embedding Space"
        case chunkDistribution = "Chunk Distribution"
        case queryAnalytics = "Query Analytics"
        case performanceMetrics = "Performance Metrics"
        case similarityHeatmap = "Similarity Heatmap"
        case retrievalPatterns = "Retrieval Patterns"
        case pipelineFlow = "Pipeline Flow"
        case semanticClustering = "Semantic Clustering"
        
        var icon: String {
            switch self {
            case .embeddingSpace: return "cube.transparent"
            case .chunkDistribution: return "chart.bar.fill"
            case .queryAnalytics: return "chart.line.uptrend.xyaxis"
            case .performanceMetrics: return "speedometer"
            case .similarityHeatmap: return "square.grid.3x3.fill"
            case .retrievalPatterns: return "arrow.triangle.branch"
            case .pipelineFlow: return "flowchart.fill"
            case .semanticClustering: return "circle.hexagongrid.fill"
            }
        }
        
        var explanation: String {
            switch self {
            case .embeddingSpace:
                return "Shows how documents are positioned in semantic space. Documents with similar meanings cluster together. Think of it like a map where similar topics are neighbors."
            case .chunkDistribution:
                return "Displays the size distribution of text chunks across documents. Helps identify if documents are evenly chunked or if some need reprocessing."
            case .queryAnalytics:
                return "Tracks your query patterns over time. Shows what you're asking about, how complex your queries are, and how the system is performing."
            case .performanceMetrics:
                return "Real-time performance breakdown of the RAG pipeline. Each stage (parsing, embedding, retrieval, generation) is measured in milliseconds."
            case .similarityHeatmap:
                return "Visual matrix showing how similar each document chunk is to others. Bright colors = high similarity, dark = semantically different."
            case .retrievalPatterns:
                return "Analyzes which document chunks are retrieved most often. Helps identify your most relevant knowledge sources."
            case .pipelineFlow:
                return "Live flowchart showing data moving through the RAG pipeline stages. Watch your query transform from text → embeddings → context → response."
            case .semanticClustering:
                return "Groups similar document chunks using K-means clustering. Reveals the main topics in your knowledge base."
            }
        }
    }
    
    // Active-container scoped documents
    private var docsForActive: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                // Legacy docs (no containerId) belong to the default container (first in list)
                return activeId == defaultId
            }
        }
    }

    private var chunkCountForActive: Int {
        docsForActive.reduce(0) { $0 + $1.totalChunks }
    }

    var body: some View {
        ZStack {
            backgroundGradient
            
            if docsForActive.isEmpty {
                EmptyVisualizationsView(onAddDocuments: onRequestAddDocuments)
            } else {
                mainContentView
            }
        }
        .navigationTitle("Visualizations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var mainContentView: some View {
        VStack(spacing: 12) {
            ContainerPickerStrip(containerService: containerService)
                .padding(.horizontal)
            ScrollView {
                VStack(spacing: 20) {
                    infoBanner
                    
                    if showingExplanation {
                        explanationCard
                    }
                    
                    visualizationPicker
                    visualizationContent
                }
            }
        }
    }
    
    private var infoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Visualization Dashboard")
                    .font(.headline)
                Text("Explore your RAG pipeline with interactive visualizations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingExplanation.toggle()
                }
            } label: {
                Image(systemName: showingExplanation ? "info.circle.fill" : "info.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(DSColors.background)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedVisualization.explanation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var visualizationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(VisualizationType.allCases, id: \.self) { type in
                    visualizationButton(for: type)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func visualizationButton(for type: VisualizationType) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedVisualization = type
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(
                        selectedVisualization == type
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                Text(type.rawValue)
                    .font(.caption2)
                    .fontWeight(selectedVisualization == type ? .semibold : .regular)
                    .foregroundColor(selectedVisualization == type ? .primary : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 90)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                selectedVisualization == type
                    ? Color.blue.opacity(0.1)
                    : DSColors.surface
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedVisualization == type ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var visualizationContent: some View {
        Group {
            switch selectedVisualization {
            case .embeddingSpace:
                EmbeddingSpaceView(chunkCount: chunkCountForActive, documentCount: docsForActive.count)
            case .chunkDistribution:
                ChunkDistributionView(documents: docsForActive, chunkCount: chunkCountForActive)
            case .queryAnalytics:
                QueryAnalyticsView(ragService: ragService)
            case .performanceMetrics:
                PerformanceMetricsView(ragService: ragService)
            case .similarityHeatmap:
                SimilarityHeatmapView()
            case .retrievalPatterns:
                RetrievalPatternsView()
            case .pipelineFlow:
                PipelineFlowView()
            case .semanticClustering:
                SemanticClusteringView()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .id(selectedVisualization)
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
    
    enum ProjectionMethod: String, CaseIterable {
        case pca = "PCA"
        case tsne = "t-SNE"
        case umap = "UMAP"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
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
            
            // Projection method picker
            HStack {
                Picker("Projection", selection: $projectionMethod) {
                    ForEach(ProjectionMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                
                InfoButtonView(
                    title: "Projection Method",
                    explanation: "High-dimensional embedding vectors (512 dimensions) are 'projected' into 3D space for visualization.\n\n• PCA (Principal Component Analysis): A standard linear method that finds the directions of greatest variance. Fast and deterministic.\n\n• t-SNE & UMAP: Advanced non-linear methods that are excellent at revealing clusters but are slower and can be less deterministic."
                )
            }
            .padding(.horizontal)
            
            // 3D Embedding visualization (Apple-style scaffold)
            EmbeddingSpaceRenderer(projectionMethod: projectionMethod)
                .padding(.horizontal)
            
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
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingInfo) {
            EmbeddingInfoSheet()
        }
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
        HStack(spacing: 12) {
            // Index badge
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let duration = event.duration {
                    Text(String(format: "%.2fs", duration))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
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
    @State private var sampleChunks: [DocumentChunk] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with explanation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(
                            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Similarity Heatmap")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("Shows semantic similarity between document chunks using cosine similarity of embeddings. Brighter colors indicate higher similarity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VisualizationInfoSection(title: "💡 What is Cosine Similarity?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Measures how similar two text embeddings are:")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("1.0 = Identical meaning")
                                .font(.caption2)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("0.7-0.9 = Very similar")
                                .font(.caption2)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.yellow).frame(width: 8, height: 8)
                            Text("0.4-0.7 = Somewhat related")
                                .font(.caption2)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("<0.4 = Different topics")
                                .font(.caption2)
                        }
                    }
                }
            }
            .padding()
            .background(DSColors.background)
            .background(DSColors.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)
            
            // Heatmap Grid (using sample chunks from state)
            if sampleChunks.isEmpty {
                Text("Perform queries to see similarity heatmap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 2) {
                        ForEach(Array(sampleChunks.enumerated()), id: \.offset) { row, chunk1 in
                            HStack(spacing: 2) {
                                ForEach(Array(sampleChunks.enumerated()), id: \.offset) { col, chunk2 in
                                    let similarity = cosineSimilarity(chunk1.embedding, chunk2.embedding)
                                    
                                    Rectangle()
                                        .fill(similarityColor(similarity))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Text(String(format: "%.2f", similarity))
                                                .font(.system(size: 8))
                                                .foregroundColor(similarity > 0.5 ? .white : .black)
                                        )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 400)
                .background(DSColors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            // Stats
            HStack(spacing: 12) {
                StatCard(
                    icon: "number",
                    label: "Chunks Analyzed",
                    value: "\(sampleChunks.count)",
                    color: .purple
                )
                
                StatCard(
                    icon: "arrow.triangle.branch",
                    label: "Comparisons",
                    value: "\(sampleChunks.count * sampleChunks.count)",
                    color: .pink
                )
            }
            .padding(.horizontal)
        }
        .task {
            // Load sample chunks from recent telemetry events
            await loadSampleChunks()
        }
    }
    
    private func loadSampleChunks() async {
        // Get sample chunks from telemetry metadata if available
        // For now, create empty state - in real app, this would query vectorDatabase
        sampleChunks = []
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    private func similarityColor(_ similarity: Float) -> Color {
        if similarity > 0.9 {
            return .red
        } else if similarity > 0.7 {
            return .orange
        } else if similarity > 0.4 {
            return .yellow
        } else {
            return .blue.opacity(Double(similarity))
        }
    }
}

struct RetrievalPatternsView: View {
    @EnvironmentObject var ragService: RAGService
    @StateObject private var telemetry = TelemetryCenter.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(
                            LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Retrieval Patterns")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("Tracks which document chunks are retrieved most frequently by your queries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VisualizationInfoSection(title: "🔍 Why This Matters") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Identifies your most valuable knowledge sources")
                            .font(.caption2)
                        Text("• Shows topic coverage and gaps in your database")
                            .font(.caption2)
                        Text("• Helps optimize chunking strategy for better retrieval")
                            .font(.caption2)
                    }
                }
            }
            .padding()
            .background(DSColors.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)
            
            // Top Retrieved Chunks Chart
            let retrievalEvents = telemetry.events.filter { $0.category == .retrieval && $0.metadata["topK"] != nil }
            let chunkRetrievalCounts = calculateChunkRetrievalFrequency(from: retrievalEvents)
            
            if !chunkRetrievalCounts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most Retrieved Chunks")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Chart {
                        ForEach(Array(chunkRetrievalCounts.prefix(10).enumerated()), id: \.offset) { index, item in
                            BarMark(
                                x: .value("Retrievals", item.value),
                                y: .value("Chunk", "Chunk \(index + 1)")
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .annotation(position: .trailing) {
                                Text("\(item.value)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 300)
                    .chartXAxis {
                        AxisMarks(position: .bottom)
                    }
                    .padding()
                    .background(DSColors.surface)
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
            }
            
            // Retrieval Stats
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    icon: "magnifyingglass",
                    label: "Total Retrievals",
                    value: "\(retrievalEvents.count)",
                    color: .blue
                )
                
                StatCard(
                    icon: "chart.bar.fill",
                    label: "Unique Chunks Hit",
                    value: "\(chunkRetrievalCounts.count)",
                    color: .green
                )
                
                StatCard(
                    icon: "percent",
                    label: "Coverage",
                    value: String(format: "%.1f%%", calculateCoveragePercentage()),
                    color: .orange
                )
                
                StatCard(
                    icon: "star.fill",
                    label: "Most Popular",
                    value: chunkRetrievalCounts.first.map { "\($0.value)x" } ?? "N/A",
                    color: .purple
                )
            }
            .padding(.horizontal)
        }
    }
    
    private func calculateChunkRetrievalFrequency(from events: [TelemetryEvent]) -> [(key: String, value: Int)] {
        var counts: [String: Int] = [:]
        
        for event in events {
            if let topKString = event.metadata["topK"],
               let topK = Int(topKString) {
                for i in 0..<topK {
                    let chunkKey = "chunk_\(i)"
                    counts[chunkKey, default: 0] += 1
                }
            }
        }
        
        return counts.sorted { $0.value > $1.value }
    }
    
    private func calculateCoveragePercentage() -> Double {
        // Get chunks from vector database instead of documents
        // Since documents don't have a chunks property
        guard ragService.totalChunksStored > 0 else { return 0 }
        
        let retrievedChunks = calculateChunkRetrievalFrequency(from: telemetry.events.filter { $0.category == .retrieval }).count
        return Double(retrievedChunks) / Double(ragService.totalChunksStored) * 100
    }
}

struct PipelineFlowView: View {
    @EnvironmentObject var ragService: RAGService
    @StateObject private var telemetry = TelemetryCenter.shared
    @State private var animationPhase: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flowchart.fill")
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Pipeline Flow")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("Live visualization of data flowing through the RAG pipeline stages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VisualizationInfoSection(title: "⚡️ Pipeline Stages") {
                    VStack(alignment: .leading, spacing: 6) {
                        PipelineStageInfo(number: "1", name: "Document Ingestion", desc: "Parse PDF/text files")
                        PipelineStageInfo(number: "2", name: "Semantic Chunking", desc: "Split into 400-word sections")
                        PipelineStageInfo(number: "3", name: "Embedding Generation", desc: "Convert text → 512-dim vectors")
                        PipelineStageInfo(number: "4", name: "Vector Storage", desc: "Store in in-memory database")
                        PipelineStageInfo(number: "5", name: "Query Processing", desc: "Embed user question")
                        PipelineStageInfo(number: "6", name: "Similarity Search", desc: "Find top-K relevant chunks")
                        PipelineStageInfo(number: "7", name: "Context Assembly", desc: "Format retrieved chunks")
                        PipelineStageInfo(number: "8", name: "LLM Generation", desc: "Generate final response")
                    }
                }
            }
            .padding()
            .background(DSColors.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)
            
            // Flow Diagram
            VStack(spacing: 0) {
                ForEach(pipelineStages, id: \.name) { stage in
                    VStack(spacing: 0) {
                        PipelineStageCard(stage: stage, isActive: isStageActive(stage.category))
                        
                        if stage.name != pipelineStages.last?.name {
                            FlowArrow(isActive: isStageActive(stage.category))
                        }
                    }
                }
            }
            .padding()
            .background(DSColors.surface.opacity(0.3))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Real-time Activity
            let recentEvents = telemetry.events.suffix(5).reversed()
            if !recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(Array(recentEvents), id: \.id) { event in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(categoryColor(event.category))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                Text(event.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let duration = event.duration {
                                Text(String(format: "%.0fms", duration * 1000))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(DSColors.background)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
    }
    
    private let pipelineStages: [(name: String, icon: String, category: TelemetryCategory)] = [
        ("Ingestion", "doc.text.fill", .ingestion),
        ("Chunking", "square.split.2x2", .ingestion),
        ("Embedding", "function", .embedding),
        ("Storage", "externaldrive.fill", .storage),
        ("Query", "magnifyingglass", .retrieval),
        ("Retrieval", "arrow.down.circle.fill", .retrieval),
        ("Assembly", "square.stack.3d.up.fill", .retrieval),
        ("Generation", "sparkles", .generation)
    ]
    
    private func isStageActive(_ category: TelemetryCategory) -> Bool {
        let recentEvents = telemetry.events.suffix(10)
        return recentEvents.contains { $0.category == category && Date().timeIntervalSince($0.timestamp) < 5 }
    }
    
    private func categoryColor(_ category: TelemetryCategory) -> Color {
        switch category {
        case .ingestion: return .orange
        case .embedding: return .purple
        case .retrieval: return .blue
        case .generation: return .green
        case .storage: return .cyan
        case .system: return .gray
        case .error: return .red
        }
    }
}

struct PipelineStageInfo: View {
    let number: String
    let name: String
    let desc: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct PipelineStageCard: View {
    let stage: (name: String, icon: String, category: TelemetryCategory)
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stage.icon)
                .font(.title3)
                .foregroundColor(isActive ? .white : categoryColor(stage.category))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isActive ? categoryColor(stage.category) : DSColors.surface)
                )
            
            Text(stage.name)
                .font(.headline)
                .foregroundColor(isActive ? .primary : .secondary)
            
            Spacer()
            
            if isActive {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: categoryColor(stage.category)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? categoryColor(stage.category).opacity(0.1) : DSColors.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? categoryColor(stage.category) : Color.clear, lineWidth: 2)
        )
    }
    
    private func categoryColor(_ category: TelemetryCategory) -> Color {
        switch category {
        case .ingestion: return .orange
        case .embedding: return .purple
        case .retrieval: return .blue
        case .generation: return .green
        case .storage: return .cyan
        case .system: return .gray
        case .error: return .red
        }
    }
}

struct FlowArrow: View {
    let isActive: Bool
    
    var body: some View {
        Image(systemName: "arrow.down")
            .font(.title3)
            .foregroundColor(isActive ? .blue : .gray)
            .padding(.vertical, 4)
    }
}

struct SemanticClusteringView: View {
    @EnvironmentObject var ragService: RAGService
    @State private var selectedK: Int = 3
    @State private var sampleChunks: [DocumentChunk] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Semantic Clustering")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("Groups similar document chunks using K-means clustering algorithm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ClusteringInfoCard()
            }
            .padding()
            .background(DSColors.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
            .padding(.horizontal)
            
            // K Selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Number of Clusters (K):")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(selectedK)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
                
                Slider(value: Binding(
                    get: { Double(selectedK) },
                    set: { selectedK = Int($0) }
                ), in: 2...10, step: 1)
                    .tint(.purple)
                
                Text("💡 Start with 3-5 clusters for most documents")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Cluster Distribution
            clusterDistributionSection
            
            // Cluster Stats
            clusterStatsGrid
            
            // Cluster Preview
            clusterPreviewSection
        }
        .task {
            await loadSampleChunks()
        }
    }
    
    // MARK: - Computed Properties
    
    private var clusters: [[DocumentChunk]] {
        performKMeansClustering(chunks: sampleChunks, k: selectedK)
    }
    
    private var maxClusterSize: Int {
        clusters.max(by: { $0.count < $1.count })?.count ?? 0
    }
    
    private var averageClusterSize: String {
        guard !sampleChunks.isEmpty else { return "0.0" }
        return String(format: "%.1f", Double(sampleChunks.count) / Double(selectedK))
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var clusterDistributionSection: some View {
        if sampleChunks.isEmpty {
            Text("Perform queries to build clustering data")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cluster Distribution")
                    .font(.headline)
                    .padding(.horizontal)
                
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
                .frame(height: CGFloat(selectedK * 50))
                .padding()
                .background(DSColors.surface)
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var clusterStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                icon: "number",
                label: "Total Clusters",
                value: "\(selectedK)",
                color: .purple
            )
            
            StatCard(
                icon: "doc.text.fill",
                label: "Chunks Analyzed",
                value: "\(sampleChunks.count)",
                color: .blue
            )
            
            StatCard(
                icon: "chart.pie.fill",
                label: "Largest Cluster",
                value: "\(maxClusterSize)",
                color: .green
            )
            
            StatCard(
                icon: "chart.bar.fill",
                label: "Avg Size",
                value: averageClusterSize,
                color: .orange
            )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var clusterPreviewSection: some View {
        if !clusters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cluster Preview")
                    .font(.headline)
                    .padding(.horizontal)
                
                ForEach(Array(clusters.enumerated()), id: \.offset) { index, cluster in
                    ClusterPreviewCard(
                        index: index,
                        cluster: cluster,
                        color: clusterColor(index)
                    )
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSampleChunks() async {
        // Load sample chunks - for now empty state
        // In real app, would query vectorDatabase
        sampleChunks = []
    }
    
    private func performKMeansClustering(chunks: [DocumentChunk], k: Int) -> [[DocumentChunk]] {
        guard !chunks.isEmpty, k > 0 else { return [] }
        
        // Initialize random centroids
        var centroids = (0..<k).map { _ in
            chunks.randomElement()?.embedding ?? []
        }
        
        var clusters: [[DocumentChunk]] = Array(repeating: [], count: k)
        
        // Run K-means for 10 iterations
        for _ in 0..<10 {
            // Clear clusters
            clusters = Array(repeating: [], count: k)
            
            // Assign chunks to nearest centroid
            for chunk in chunks {
                let distances = centroids.map { centroid in
                    euclideanDistance(chunk.embedding, centroid)
                }
                
                if let minIndex = distances.enumerated().min(by: { $0.element < $1.element })?.offset {
                    clusters[minIndex].append(chunk)
                }
            }
            
            // Recalculate centroids
            for i in 0..<k {
                if !clusters[i].isEmpty {
                    centroids[i] = averageEmbedding(clusters[i].map { $0.embedding })
                }
            }
        }
        
        return clusters.filter { !$0.isEmpty }
    }
    
    private func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        return sqrt(zip(a, b).map { pow($0 - $1, 2) }.reduce(0, +))
    }
    
    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        let dim = embeddings.first?.count ?? 0
        
        return (0..<dim).map { i in
            embeddings.map { $0[i] }.reduce(0, +) / Float(embeddings.count)
        }
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

struct ClusterPreviewCard: View {
    let index: Int
    let cluster: [DocumentChunk]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            
            if let firstChunk = cluster.first {
                Text(String(firstChunk.content.prefix(150)) + "...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
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
