//  AdaptiveVisualizationsView.swift
//  OpenIntelligence
//
//  Dynamic visualization dashboard that adapts to each library's unique
//  content, structure, and usage patterns. Replaces static tabs with
//  contextually relevant insight cards and recommended views.

import Charts
import SceneKit
import SwiftUI

// MARK: - Main View

struct AdaptiveVisualizationsView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService
    @StateObject private var engine = LibraryVisualizationEngine.shared

    @State private var selectedInsight: VisualizationInsight?
    @State private var expandedView: LibraryVisualizationEngine.RecommendedView.ViewType?
    @State private var showAllViews = false
    @State private var show3DFullscreen = false
    @State private var atlasMode: AtlasMode = .compact
    @State private var showAtlasSettings = false

    // Atlas visualization settings
    @State private var atlasProjection: AtlasProjectionMethod = .pca
    @State private var atlasPointScale: Double = 1.2
    @State private var atlasAutoRotate = false // Off by default - let user explore
    @State private var atlasDepthCue = false // Off for cleaner look
    @State private var atlasShowLabels = true
    @State private var atlasShowAxes = true // On by default - show spatial reference
    @State private var atlasBackground: AtlasBackgroundStyle = .midnight // Dark for contrast

    enum AtlasProjectionMethod: String, CaseIterable {
        case pca = "PCA"
        case tsne = "t-SNE"
        case umap = "UMAP"

        var icon: String {
            switch self {
            case .pca: return "cube"
            case .tsne: return "point.3.connected.trianglepath.dotted"
            case .umap: return "chart.dots.scatter"
            }
        }

        var projectionKind: ProjectionMethodKind {
            switch self {
            case .pca: return .pca
            case .tsne: return .tsne
            case .umap: return .umap
            }
        }
    }

    enum AtlasBackgroundStyle: String, CaseIterable {
        case aurora = "Aurora"
        case midnight = "Midnight"
        case parchment = "Parchment"

        var sceneStyle: EmbeddingSceneBackgroundStyle {
            switch self {
            case .aurora: return .aurora
            case .midnight: return .midnight
            case .parchment: return .parchment
            }
        }

        var icon: String {
            switch self {
            case .aurora: return "sparkles"
            case .midnight: return "moon.stars"
            case .parchment: return "scroll"
            }
        }
    }

    private var activeContainer: KnowledgeContainer? {
        containerService.containers.first { $0.id == containerService.activeContainerId }
    }

    enum AtlasMode: String, CaseIterable {
        case compact = "Compact"
        case expanded = "Expanded"
        case fullscreen = "Fullscreen"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // HERO: 3D Atlas (always visible for libraries with content)
                if let profile = engine.currentProfile, profile.chunkCount >= 10 {
                    hero3DAtlasSection(profile: profile)
                }

                libraryHeader

                if engine.isAnalyzing {
                    analyzeLoadingCard
                } else if let profile = engine.currentProfile {
                    // Insights row (horizontal scroll for space efficiency)
                    if !engine.insights.isEmpty {
                        insightsHorizontalSection
                    }

                    // Dynamic views grid
                    if !engine.recommendedViews.isEmpty {
                        recommendedViewsSection
                    }

                    if let expanded = expandedView, expanded != .embedding3D {
                        expandedViewSection(type: expanded, profile: profile)
                    }

                    libraryStatsSection(profile: profile)
                } else {
                    emptyStateCard
                }
            }
            .padding()
        }
        .background(DSColors.background)
        .navigationTitle("Knowledge Atlas")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $show3DFullscreen) {
            Fullscreen3DAtlasView()
                .environmentObject(ragService)
                .environmentObject(containerService)
        }
        .task {
            await refreshAnalysis()
        }
        .task(id: containerService.activeContainerId) {
            await refreshAnalysis()
        }
        .refreshable {
            await refreshAnalysis()
        }
    }

    // MARK: - Hero 3D Atlas

    private func hero3DAtlasSection(profile: LibraryProfile) -> some View {
        VStack(spacing: 0) {
            // Compact header with controls
            atlasHeader

            // Settings toolbar (collapsible)
            if showAtlasSettings {
                atlasSettingsToolbar
            }

            // The 3D scene with all settings passed through
            CompactAtlasSceneView(
                profile: profile,
                height: atlasMode == .expanded ? 420 : 280,
                projectionMethod: atlasProjection.projectionKind,
                pointScale: atlasPointScale,
                autoRotate: atlasAutoRotate,
                depthCue: atlasDepthCue,
                showLabels: atlasShowLabels,
                backgroundStyle: atlasBackground.sceneStyle
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // Topic legend (makes the dots meaningful)
            if !profile.dominantTopics.isEmpty {
                atlasTopicLegend(topics: profile.dominantTopics)
            }

            // Quick stats bar
            atlas3DStatsBar(profile: profile)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.1, blue: 0.18),
                            Color(red: 0.12, green: 0.16, blue: 0.28),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: atlasMode)
    }

    private var atlasHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Semantic Atlas")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(atlasProjection.rawValue + " projection • \(atlasAutoRotate ? "Rotating" : "Static")")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Settings toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showAtlasSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .padding(6)
                    .background(
                        Circle().fill(showAtlasSettings ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                    .foregroundColor(.white.opacity(showAtlasSettings ? 1 : 0.7))
            }

            // Compact/Expanded toggle
            HStack(spacing: 2) {
                ForEach([AtlasMode.compact, AtlasMode.expanded], id: \.self) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            atlasMode = mode
                        }
                    } label: {
                        Image(systemName: mode == .compact ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                            .font(.caption)
                            .padding(6)
                            .background(
                                Circle().fill(atlasMode == mode ? Color.white.opacity(0.2) : Color.clear)
                            )
                            .foregroundColor(.white.opacity(atlasMode == mode ? 1 : 0.5))
                    }
                }
            }

            Button {
                show3DFullscreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Atlas Settings Toolbar

    private var atlasSettingsToolbar: some View {
        VStack(spacing: 12) {
            // Row 1: Projection method
            HStack(spacing: 8) {
                Text("Projection")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                ForEach(AtlasProjectionMethod.allCases, id: \.self) { method in
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            atlasProjection = method
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: method.icon)
                                .font(.system(size: 10))
                            Text(method.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(atlasProjection == method ? Color.accentColor : Color.white.opacity(0.1))
                        )
                        .foregroundColor(atlasProjection == method ? .white : .white.opacity(0.7))
                    }
                }
            }

            // Row 2: Point size slider
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.white.opacity(0.5))

                Slider(value: $atlasPointScale, in: 0.5 ... 2.0, step: 0.1)
                    .tint(.accentColor)

                Image(systemName: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                Text(String(format: "%.1fx", atlasPointScale))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32)
            }

            // Row 3: Toggle options
            HStack(spacing: 16) {
                AtlasToggleChip(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Rotate",
                    isOn: $atlasAutoRotate
                )

                AtlasToggleChip(
                    icon: "cube.transparent",
                    label: "Depth",
                    isOn: $atlasDepthCue
                )

                AtlasToggleChip(
                    icon: "tag",
                    label: "Labels",
                    isOn: $atlasShowLabels
                )

                Spacer()

                // Background style picker
                Menu {
                    ForEach(AtlasBackgroundStyle.allCases, id: \.self) { style in
                        Button {
                            atlasBackground = style
                        } label: {
                            Label(style.rawValue, systemImage: style.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: atlasBackground.icon)
                            .font(.system(size: 10))
                        Text(atlasBackground.rawValue)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func atlasTopicLegend(topics: [TopicCluster]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(topics.prefix(5)) { topic in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(topic.color)
                            .frame(width: 8, height: 8)

                        Text(topic.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))

                        Text("\(topic.chunkCount)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(topic.color.opacity(0.2))
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func atlas3DStatsBar(profile: LibraryProfile) -> some View {
        HStack(spacing: 16) {
            AtlasStatPill(icon: "cube.fill", value: "\(profile.chunkCount)", label: "Points", color: .blue)
            AtlasStatPill(icon: "doc.fill", value: "\(profile.documentCount)", label: "Sources", color: .green)

            if !profile.dominantTopics.isEmpty {
                AtlasStatPill(icon: "circle.hexagongrid.fill", value: "\(profile.dominantTopics.count)", label: "Clusters", color: .purple)
            }

            if profile.topicDiversity > 0.5 {
                AtlasStatPill(icon: "arrow.triangle.branch", value: "High", label: "Diversity", color: .orange)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Library Header

    private var libraryHeader: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Library icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.accentColor.opacity(0.8), .accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: activeContainer?.icon ?? "books.vertical")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(activeContainer?.name ?? "Library")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let profile = engine.currentProfile {
                        HStack(spacing: 8) {
                            Label(profile.sizeCategory.rawValue, systemImage: profile.sizeCategory.icon)
                            Text("•")
                            Label(profile.retrievalActivity.rawValue, systemImage: profile.retrievalActivity.icon)
                                .foregroundColor(profile.retrievalActivity.color)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if engine.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastAnalyzed = engine.lastAnalyzed {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Updated")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(lastAnalyzed, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Quick metrics strip
            if let profile = engine.currentProfile {
                quickMetricsStrip(profile: profile)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func quickMetricsStrip(profile: LibraryProfile) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                QuickMetric(icon: "doc.text", label: "Docs", value: "\(profile.documentCount)")
                QuickMetric(icon: "square.stack.3d.down.right", label: "Chunks", value: "\(profile.chunkCount)")
                QuickMetric(icon: "text.word.spacing", label: "Words", value: formatNumber(profile.totalWords))

                if !profile.dominantTopics.isEmpty {
                    QuickMetric(icon: "circle.hexagongrid", label: "Topics", value: "\(profile.dominantTopics.count)")
                }

                if profile.isHighlyActive {
                    QuickMetric(icon: "flame.fill", label: "Hot Chunks", value: "\(profile.hotChunks.count)", color: .orange)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Insights Horizontal

    private var insightsHorizontalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Insights")
                    .font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(engine.insights.prefix(5)) { insight in
                        CompactInsightCard(insight: insight) {
                            handleInsightTap(insight)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Insight Cards (legacy vertical)

    private func insightCardsSection(profile _: LibraryProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insights")
                    .font(.headline)

                Spacer()

                if engine.insights.count > 3 {
                    Button("See All") {
                        // TODO: Show all insights sheet
                    }
                    .font(.caption)
                }
            }

            if engine.insights.isEmpty {
                noInsightsCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(engine.insights.prefix(4)) { insight in
                        InsightCard(insight: insight) {
                            handleInsightTap(insight)
                        }
                    }
                }
            }
        }
    }

    private var noInsightsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Library looks great!")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("No specific recommendations right now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Recommended Views

    private var recommendedViewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Explore")
                    .font(.headline)

                Spacer()

                Button(showAllViews ? "Show Less" : "All Views") {
                    withAnimation(.spring(response: 0.35)) {
                        showAllViews.toggle()
                    }
                }
                .font(.caption)
            }

            let views = showAllViews ? engine.recommendedViews : Array(engine.recommendedViews.prefix(4))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(views) { view in
                    RecommendedViewCard(view: view, isExpanded: expandedView == view.type) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if expandedView == view.type {
                                expandedView = nil
                            } else {
                                expandedView = view.type
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expanded View

    @ViewBuilder
    private func expandedViewSection(type: LibraryVisualizationEngine.RecommendedView.ViewType, profile: LibraryProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(type.rawValue)
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        expandedView = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            expandedViewContent(type: type, profile: profile)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DSColors.surface)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private func expandedViewContent(type: LibraryVisualizationEngine.RecommendedView.ViewType, profile: LibraryProfile) -> some View {
        switch type {
        case .topicCloud:
            TopicCloudView(topics: profile.dominantTopics)
        case .contentBreakdown:
            ContentBreakdownView(contentMix: profile.contentMix, chunkCount: profile.chunkCount)
        case .embedding3D:
            EmbeddingSpaceView(
                chunkCount: profile.chunkCount,
                documentCount: profile.documentCount,
                embeddingDimension: 512
            )
        case .clusterView:
            ClusterOverviewView(topics: profile.dominantTopics, profile: profile)
        case .retrievalFlow:
            RetrievalFlowView(hotChunks: profile.hotChunks, coldZones: profile.coldZones, totalChunks: profile.chunkCount)
        case .documentGraph:
            DocumentRelationshipView(documentCount: profile.documentCount)
        case .heatmap:
            SimilarityHeatmapPreview(chunkCount: profile.chunkCount)
        case .timelineView:
            LibraryTimelineView(additions: profile.recentAdditions, libraryAge: profile.libraryAge)
        }
    }

    // MARK: - Library Stats

    private func libraryStatsSection(profile: LibraryProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library Stats")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                StatTile(icon: "doc.text.fill", label: "Documents", value: "\(profile.documentCount)", color: .blue)
                StatTile(icon: "square.stack.3d.down.right.fill", label: "Chunks", value: "\(profile.chunkCount)", color: .purple)
                StatTile(icon: "character.cursor.ibeam", label: "Avg Chunk", value: "\(profile.avgChunkSize)w", color: .green)
                StatTile(icon: "chart.pie.fill", label: "Diversity", value: String(format: "%.0f%%", profile.topicDiversity * 100), color: .orange)
                StatTile(icon: "circle.hexagongrid.fill", label: "Topics", value: "\(profile.dominantTopics.count)", color: .pink)
                StatTile(icon: "eye.slash.fill", label: "Unused", value: "\(profile.coldZones)", color: .secondary)
            }
        }
    }

    // MARK: - Helper Views

    private var analyzeLoadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing your library...")
                .font(.headline)

            Text("Detecting topics, patterns, and insights")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Add documents to visualize")
                .font(.headline)

            Text("Import files to see your knowledge atlas come alive")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Actions

    private func refreshAnalysis() async {
        let containerId = containerService.activeContainerId
        let documents = ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == containerId
            }
            return containerId == containerService.containers.first?.id
        }
        let chunks = await ragService.allChunksForActiveContainer()
        let history = ragService.retrievalHistory.filter { $0.containerId == containerId }

        await engine.analyze(
            containerId: containerId,
            documents: documents,
            chunks: chunks,
            retrievalHistory: history
        )
    }

    private func handleInsightTap(_ insight: VisualizationInsight) {
        switch insight.action {
        case .showTopicMap:
            expandedView = .topicCloud
        case .showClusterView:
            expandedView = .clusterView
        case .showRetrievalChart:
            expandedView = .retrievalFlow
        case .showEmbedding3D:
            expandedView = .embedding3D
        case .showHeatmap:
            expandedView = .heatmap
        case .showDocumentGraph:
            expandedView = .documentGraph
        case .showTimeline:
            expandedView = .timelineView
        case .expandDetail:
            selectedInsight = insight
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.1fK", Double(n) / 1000)
        }
        return "\(n)"
    }
}

// MARK: - Supporting Views

struct QuickMetric: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

struct InsightCard: View {
    let insight: VisualizationInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(insight.color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: insight.icon)
                        .font(.system(size: 18))
                        .foregroundColor(insight.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(insight.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if !insight.metrics.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let first = insight.metrics.first {
                            Text(first.value)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(insight.color)
                            Text(first.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DSColors.surface)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecommendedViewCard: View {
    let view: LibraryVisualizationEngine.RecommendedView
    let isExpanded: Bool
    let onTap: () -> Void

    private var viewIcon: String {
        switch view.type {
        case .topicCloud: return "cloud.fill"
        case .embedding3D: return "cube.fill"
        case .documentGraph: return "point.3.connected.trianglepath.dotted"
        case .retrievalFlow: return "arrow.triangle.branch"
        case .clusterView: return "circle.hexagongrid.fill"
        case .timelineView: return "calendar"
        case .heatmap: return "square.grid.3x3.fill"
        case .contentBreakdown: return "chart.pie.fill"
        }
    }

    private var viewColor: Color {
        switch view.type {
        case .topicCloud: return .purple
        case .embedding3D: return .blue
        case .documentGraph: return .teal
        case .retrievalFlow: return .orange
        case .clusterView: return .pink
        case .timelineView: return .green
        case .heatmap: return .red
        case .contentBreakdown: return .indigo
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: viewIcon)
                        .font(.title3)
                        .foregroundColor(viewColor)

                    Spacer()

                    if isExpanded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                Text(view.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(view.reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Relevance bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(viewColor.opacity(0.2))
                            .frame(height: 4)

                        Capsule()
                            .fill(viewColor)
                            .frame(width: geo.size.width * CGFloat(view.relevanceScore), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isExpanded ? viewColor.opacity(0.1) : DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isExpanded ? viewColor.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}

// MARK: - Visualization Subviews

struct TopicCloudView: View {
    let topics: [TopicCluster]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(topics) { topic in
                HStack(spacing: 12) {
                    Circle()
                        .fill(topic.color)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(topic.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("\(topic.chunkCount) chunks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Keyword tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(topic.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(topic.color.opacity(0.15))
                                        .foregroundColor(topic.color)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(topic.color.opacity(0.2))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(topic.color)
                                    .frame(width: geo.size.width * CGFloat(topic.percentage), height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DSColors.background)
                )
            }
        }
    }
}

struct ContentBreakdownView: View {
    let contentMix: [ContentCategory: Float]
    let chunkCount: Int

    var sortedCategories: [(ContentCategory, Float)] {
        contentMix.sorted { $0.value > $1.value }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Pie chart representation
            Chart {
                ForEach(sortedCategories, id: \.0) { category, percentage in
                    SectorMark(
                        angle: .value("Percentage", percentage),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(category.color)
                    .annotation(position: .overlay) {
                        if percentage > 0.1 {
                            Text(String(format: "%.0f%%", percentage * 100))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .frame(height: 200)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(sortedCategories.filter { $0.1 > 0.05 }, id: \.0) { category, percentage in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)

                        Image(systemName: category.icon)
                            .font(.caption)
                            .foregroundColor(category.color)

                        Text(category.rawValue)
                            .font(.caption)

                        Spacer()

                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ClusterOverviewView: View {
    let topics: [TopicCluster]
    let profile: LibraryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Cluster bar chart
            Chart {
                ForEach(topics) { topic in
                    BarMark(
                        x: .value("Chunks", topic.chunkCount),
                        y: .value("Topic", topic.name)
                    )
                    .foregroundStyle(topic.color)
                    .annotation(position: .trailing) {
                        Text("\(topic.chunkCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: CGFloat(topics.count * 44))

            // Cluster quality indicator
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cluster Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        ForEach(0 ..< 5) { i in
                            Circle()
                                .fill(i < Int(profile.clusterQuality * 5) ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }

                        Text(profile.clusterQuality > 0.7 ? "Excellent" : profile.clusterQuality > 0.4 ? "Good" : "Fair")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Diversity Score")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.0f%%", profile.topicDiversity * 100))
                        .font(.headline)
                        .foregroundColor(.purple)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }
}

struct RetrievalFlowView: View {
    let hotChunks: [HotChunk]
    let coldZones: Int
    let totalChunks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hot chunks list
            ForEach(hotChunks) { chunk in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Text("\(chunk.retrievalCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chunk.documentName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(chunk.snippet)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f", chunk.avgSimilarity))
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text("avg sim")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DSColors.background)
                )
            }

            // Coverage summary
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(hotChunks.reduce(0) { $0 + $1.retrievalCount })")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("Total Hits")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(totalChunks - coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text("Untouched")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }
}

struct DocumentRelationshipView: View {
    let documentCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 60))
                .foregroundColor(.teal.opacity(0.6))

            Text("Document Connections")
                .font(.headline)

            Text("Visualizing relationships between \(documentCount) documents")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Full graph view coming soon")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct SimilarityHeatmapPreview: View {
    let chunkCount: Int

    var body: some View {
        VStack(spacing: 16) {
            // Simulated heatmap grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 10), spacing: 2) {
                ForEach(0 ..< 100, id: \.self) { _ in
                    Rectangle()
                        .fill(heatmapColor(for: Double.random(in: 0 ... 1)))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Similarity matrix across \(chunkCount) chunks")
                .font(.caption)
                .foregroundColor(.secondary)

            // Legend
            HStack(spacing: 4) {
                ForEach(0 ..< 10, id: \.self) { i in
                    Rectangle()
                        .fill(heatmapColor(for: Double(i) / 10.0))
                        .frame(width: 20, height: 8)
                }
            }

            HStack {
                Text("Low")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("High Similarity")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func heatmapColor(for value: Double) -> Color {
        if value < 0.3 {
            return Color.blue.opacity(0.3 + value)
        } else if value < 0.6 {
            return Color.yellow.opacity(0.5 + value * 0.5)
        } else {
            return Color.red.opacity(0.6 + value * 0.4)
        }
    }
}

struct LibraryTimelineView: View {
    let additions: [RecentAddition]
    let libraryAge: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Age summary
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library Age")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formatAge(libraryAge))
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Recent Additions")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(additions.count)")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DSColors.background)
            )

            // Recent additions list
            if !additions.isEmpty {
                ForEach(additions) { addition in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(addition.documentName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(addition.addedAt, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0f%%", addition.integrationScore * 100))
                                .font(.caption)
                                .foregroundColor(addition.integrationScore > 0.6 ? .green : .orange)
                            Text("fit")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DSColors.background)
                    )
                }
            } else {
                Text("No recent additions in the last 7 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func formatAge(_ interval: TimeInterval) -> String {
        let days = Int(interval / (24 * 60 * 60))
        if days < 1 {
            return "New"
        } else if days < 30 {
            return "\(days) days"
        } else if days < 365 {
            return "\(days / 30) months"
        } else {
            return "\(days / 365) years"
        }
    }
}

// MARK: - Atlas Components

struct AtlasStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.3))
        )
    }
}

struct AtlasToggleChip: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1))
            )
            .foregroundColor(isOn ? .white : .white.opacity(0.6))
        }
    }
}

struct CompactInsightCard: View {
    let insight: VisualizationInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 16))
                        .foregroundColor(insight.color)

                    Text(insight.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Text(insight.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let metric = insight.metrics.first {
                    HStack(spacing: 4) {
                        Text(metric.value)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(insight.color)
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 160)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(insight.color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fullscreen 3D Atlas

struct Fullscreen3DAtlasView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    // Settings state
    @State private var projectionMethod: ProjectionMethodKind = .pca
    @State private var pointScale: Double = 1.0
    @State private var autoRotate = true
    @State private var depthCue = true
    @State private var showLabels = true
    @State private var backgroundStyle: EmbeddingSceneBackgroundStyle = .aurora
    @State private var showSettings = false

    // Data state
    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var colors: [PlatformColor] = []
    @State private var annotations: [Embedding3DSceneView.AnnotationData] = []
    @State private var sceneReloadToken = UUID()
    @State private var profile: LibraryProfile?
    @State private var chunkTopicAssignments: [UUID: String] = [:]

    private let sampleLimit = 2000 // Higher limit for fullscreen

    private var sceneOptions: Embedding3DSceneView.SceneOptions {
        Embedding3DSceneView.SceneOptions(
            pointScale: CGFloat(pointScale),
            autoRotate: autoRotate,
            showAxes: true, // Always show axes for spatial reference
            depthCue: depthCue,
            backgroundStyle: backgroundStyle
        )
    }

    var body: some View {
        ZStack {
            // Background
            backgroundGradient

            // Main 3D scene
            if isLoading {
                loadingView
            } else if points.isEmpty {
                emptyView
            } else {
                ZStack { 
                    Embedding3DSceneView(
                        points: points,
                        colors: colors,
                        options: sceneOptions,
                        reloadToken: sceneReloadToken,
                        annotations: showLabels ? annotations : []
                    )
                    .ignoresSafeArea()

                    // Topic legend - top left
                    VStack {
                        HStack {
                            fullscreenTopicLegend
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.top, 70) // Below topBar

                    // Interaction hint - bottom left
                    VStack {
                        Spacer()
                        HStack {
                            fullscreenHintOverlay
                            Spacer()
                        }
                    }
                    .padding(.bottom, 80) // Above bottomBar
                }
            }

            // Overlay controls
            VStack(spacing: 0) {
                topBar
                Spacer()
                if !isLoading && !points.isEmpty {
                    bottomBar
                }
            }

            // Settings panel
            if showSettings {
                settingsPanel
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            await loadData()
        }
        .onChange(of: projectionMethod) { _, _ in
            Task { await loadData() }
        }
        .onChange(of: pointScale) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: autoRotate) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: depthCue) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: showLabels) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: backgroundStyle) { _, _ in sceneReloadToken = UUID() }
    }

    // MARK: - UI Components

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.02, blue: 0.08),
                Color(red: 0.08, green: 0.1, blue: 0.18),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Mapping semantic space…")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))

            Text("Projecting \(ragService.documents.reduce(0) { $0 + $1.totalChunks }) chunks to 3D")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.3))

            Text("No documents to visualize")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))

            Text("Add documents to your library to see them in 3D space")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9), .white.opacity(0.2))
            }

            Spacer()

            // Title + projection
            VStack(spacing: 2) {
                Text("Semantic Atlas")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(projectionMethodName) • \(points.count) points")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Settings toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .padding(10)
                    .background(
                        Circle().fill(showSettings ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var projectionMethodName: String {
        switch projectionMethod {
        case .pca: return "PCA"
        case .rp: return "Random"
        case .tsne: return "t-SNE"
        case .umap: return "UMAP"
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Topic legend
            if let profile, !profile.dominantTopics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(profile.dominantTopics) { topic in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(topic.color)
                                    .frame(width: 10, height: 10)

                                Text(topic.name)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Stats bar
            HStack(spacing: 24) {
                Label("\(points.count)", systemImage: "cube.fill")
                Label("\(ragService.documents.count)", systemImage: "doc.fill")
                if let profile {
                    Label("\(profile.dominantTopics.count) topics", systemImage: "tag.fill")
                }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
        }
        .padding(.bottom, 24)
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                // Projection method
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projection")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 8) {
                        ForEach([ProjectionMethodKind.pca, .tsne, .umap], id: \.self) { method in
                            Button {
                                projectionMethod = method
                            } label: {
                                Text(methodName(method))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(projectionMethod == method ? Color.accentColor : Color.white.opacity(0.15))
                                    )
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }

                // Point scale
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Point Size")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(String(format: "%.1fx", pointScale))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }

                    Slider(value: $pointScale, in: 0.5 ... 2.0, step: 0.1)
                        .tint(.accentColor)
                }

                // Toggles
                HStack(spacing: 16) {
                    Toggle("Rotate", isOn: $autoRotate)
                    Toggle("Labels", isOn: $showLabels)
                    Toggle("Depth", isOn: $depthCue)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .font(.caption)
                .foregroundColor(.white)

                // Background style
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 8) {
                        ForEach([EmbeddingSceneBackgroundStyle.aurora, .midnight, .parchment], id: \.self) { style in
                            Button {
                                backgroundStyle = style
                            } label: {
                                Text(styleName(style))
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(backgroundStyle == style ? Color.accentColor : Color.white.opacity(0.15))
                                    )
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func methodName(_ method: ProjectionMethodKind) -> String {
        switch method {
        case .pca: return "PCA"
        case .rp: return "Random"
        case .tsne: return "t-SNE"
        case .umap: return "UMAP"
        }
    }

    private func styleName(_ style: EmbeddingSceneBackgroundStyle) -> String {
        switch style {
        case .aurora: return "Aurora"
        case .midnight: return "Midnight"
        case .parchment: return "Parchment"
        }
    }

    /// Topic color legend for fullscreen view
    private var fullscreenTopicLegend: some View {
        let topicColors = buildFullscreenTopicLegend()

        return Group {
            if !topicColors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(topicColors.prefix(6), id: \.name) { item in
                        HStack(spacing: 6) {
                            Circle()
.fill(item.color)
    .frame(width: 8, height: 8)

                            Text(item.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private struct FullscreenTopicItem: Hashable {
        let name: String
        let color: Color
        let count: Int
    }

    private func buildFullscreenTopicLegend() -> [FullscreenTopicItem] {
        var topicCounts: [String: Int] = [:]
        for (_, topicName) in chunkTopicAssignments {
            topicCounts[topicName, default: 0] += 1
        }

        var result: [FullscreenTopicItem] = []
        if let prof = profile {
            for topic in prof.dominantTopics {
                if let count = topicCounts[topic.name], count > 0 {
                    result.append(FullscreenTopicItem(name: topic.name, color: topic.color, count: count))
                }
            }
        }

        return result.sorted { $0.count > $1.count }
    }

    /// Overlay hint for fullscreen view
    private var fullscreenHintOverlay: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.draw")
                .font(.system(size: 9))
            Text("Drag to rotate • Pinch to zoom")
                .font(.system(size: 9))
        }
        .foregroundColor(.white.opacity(0.35))
        .padding(8)
    }

    // MARK: - Data Loading

    private func loadData() async {
        await MainActor.run { isLoading = true }

        // Force fresh profile build if none exists or if we need updated topic analysis
        let engine = LibraryVisualizationEngine.shared

        // Trigger fresh analysis for the active container
        let activeContainer = await MainActor.run { ragService.containerService.activeContainerId }
        let allChunks = await ragService.allChunksForActiveContainer()
        let docs = await MainActor.run { ragService.documents }
        await engine.analyze(
            containerId: activeContainer,
            documents: docs,
            chunks: allChunks,
            retrievalHistory: []
        )

        // Now use the freshly built profile
        if let freshProfile = engine.currentProfile {
            await MainActor.run { profile = freshProfile }
        }

        // allChunks already fetched above

        guard !allChunks.isEmpty else {
            await MainActor.run {
                points = []
                colors = []
                annotations = []
                isLoading = false
            }
            return
        }

        // Sample chunks
        let sampledChunks = sampleChunks(allChunks)
        let embeddings = sampledChunks.map { $0.embedding }

        guard !embeddings.isEmpty else {
            await MainActor.run {
                points = []
                colors = []
                annotations = []
                isLoading = false
            }
            return
        }

        // Project to 3D
        let seed = UInt64(abs(Int64(containerService.activeContainerId.uuidString.hashValue)))
        let coords3D = ProjectionService.shared.project3D(
            embeddings: embeddings,
            method: projectionMethod,
            seed: seed
        )

        // Topic assignment using existing functions in this scope
        let topicAssignments = assignTopics(chunks: sampledChunks)
        let mappedColors = mapColors(chunks: sampledChunks, assignments: topicAssignments)

        // Scale points properly for viewing (same approach as CompactAtlasSceneView)
        let scaledPoints = scaleCoordinatesForViewing(coords3D)

        // Build annotations with proper scaling applied
        let clusterAnnotations = buildScaledAnnotations(
            chunks: sampledChunks,
            coords: coords3D,
            assignments: topicAssignments
        )

        await MainActor.run {
            points = scaledPoints
            colors = mappedColors
            annotations = clusterAnnotations
            chunkTopicAssignments = topicAssignments
            sceneReloadToken = UUID()
            isLoading = false
        }
    }

    private func sampleChunks(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        guard chunks.count > sampleLimit else { return chunks }

        // Stratified sampling by document - DETERMINISTIC order
        var byDocument: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDocument[chunk.documentId, default: []].append(chunk)
        }

        // Sort document IDs for deterministic iteration order
        let sortedDocIds = byDocument.keys.sorted { $0.uuidString < $1.uuidString }

        var sampled: [DocumentChunk] = []
        let perDoc = max(1, sampleLimit / max(1, sortedDocIds.count))

        for docId in sortedDocIds {
            guard let docChunks = byDocument[docId] else { continue }
            if docChunks.count <= perDoc {
                sampled.append(contentsOf: docChunks)
            } else {
                let stride = docChunks.count / perDoc
                for i in Swift.stride(from: 0, to: docChunks.count, by: stride) {
                    sampled.append(docChunks[i])
                    if sampled.count >= sampleLimit { break }
                }
            }
            if sampled.count >= sampleLimit { break }
        }

        return Array(sampled.prefix(sampleLimit))
    }

    private func assignTopics(chunks: [DocumentChunk]) -> [UUID: String] {
        var assignments: [UUID: String] = [:]

        // Use profile topics if available
        var topicKeywords: [String: Set<String>] = [:]
        if let profile {
            for topic in profile.dominantTopics {
                var keywords = Set<String>()
                keywords.insert(topic.name.lowercased())
                topicKeywords[topic.name] = keywords
            }
        }

        for chunk in chunks {
            let text = chunk.text.lowercased()
            let words = Set(text.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })

            var bestTopic: String?
            var bestScore = 0

            for (name, keywords) in topicKeywords {
                let score = words.intersection(keywords).count
                if score > bestScore {
                    bestScore = score
                    bestTopic = name
                }
            }

            assignments[chunk.id] = bestTopic ?? inferTopic(from: text)
        }

        return assignments
    }

    private func inferTopic(from text: String) -> String {
        let patterns: [(String, String)] = [
            ("func |class |struct |enum ", "Code"),
            ("import |require\\(|from .+ import", "Code"),
            ("http|api|endpoint|request", "API"),
            ("test|spec|assert|expect", "Testing"),
            ("config|settings|options", "Config"),
            ("error|exception|throw", "Errors"),
            ("view|component|render", "UI"),
        ]

        for (pattern, topic) in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return topic
            }
        }

        return "General"
    }

    private func mapColors(chunks: [DocumentChunk], assignments: [UUID: String]) -> [PlatformColor] {
        var topicColorMap: [String: PlatformColor] = [:]
        if let profile {
            for topic in profile.dominantTopics {
                topicColorMap[topic.name] = PlatformColor(topic.color)
            }
        }

        let fallback: [String: Color] = [
            "Code": .blue, "API": .purple, "Testing": .green,
            "Config": .orange, "Errors": .red, "UI": .pink,
            "General": .gray,
        ]

        let docPalette: [PlatformColor] = [
            PlatformColor(.blue.opacity(0.8)),
            PlatformColor(.purple.opacity(0.8)),
            PlatformColor(.teal.opacity(0.8)),
            PlatformColor(.orange.opacity(0.8)),
        ]
        var docColors: [UUID: PlatformColor] = [:]
        var idx = 0

        return chunks.map { chunk in
            guard let topic = assignments[chunk.id] else {
                if let c = docColors[chunk.documentId] { return c }
                let c = docPalette[idx % docPalette.count]
                docColors[chunk.documentId] = c
                idx += 1
                return c
            }

            if let c = topicColorMap[topic] { return c }
            if let c = fallback[topic] { return PlatformColor(c) }
            return PlatformColor(.gray.opacity(0.6))
        }
    }

    private func buildAnnotations(
        chunks: [DocumentChunk],
        coords: [SIMD3<Float>],
        assignments: [UUID: String]
    ) -> [Embedding3DSceneView.AnnotationData] {
        guard chunks.count == coords.count else { return [] }

        var topicPoints: [String: [SIMD3<Float>]] = [:]
        for (i, chunk) in chunks.enumerated() {
            guard i < coords.count else { continue }
            let topic = assignments[chunk.id] ?? "General"
            topicPoints[topic, default: []].append(coords[i])
        }

        var topicColorMap: [String: PlatformColor] = [:]
        if let profile {
            for topic in profile.dominantTopics {
                topicColorMap[topic.name] = PlatformColor(topic.color)
            }
        }

        var result: [Embedding3DSceneView.AnnotationData] = []
        for (topic, pts) in topicPoints where pts.count >= 3 {
            let centroid = pts.reduce(.zero, +) / Float(pts.count)
            let color = topicColorMap[topic] ?? PlatformColor(.gray)

            result.append(Embedding3DSceneView.AnnotationData(
                position: SCNVector3(centroid.x, centroid.y + 0.15, centroid.z),
                title: topic,
                keywords: [],
                color: color,
                detailLevel: pts.count > 20 ? 2 : 1
            ))
        }

        return result
    }

    // MARK: - Coordinate Scaling (matches CompactAtlasSceneView)

    /// Scales coordinates properly for 3D viewing - preserves natural clustering
    private func scaleCoordinatesForViewing(_ coords: [SIMD3<Float>]) -> [SCNVector3] {
        guard !coords.isEmpty else { return [] }

        // Find bounds
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for c in coords {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
            minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2

        let spanX = max(maxX - minX, 0.0001)
        let spanY = max(maxY - minY, 0.0001)
        let spanZ = max(maxZ - minZ, 0.0001)
        let maxSpan = max(spanX, max(spanY, spanZ))

        let targetSize: Float = 3.0
        let scale = targetSize / maxSpan

        var result: [SCNVector3] = []
        result.reserveCapacity(coords.count)

        for c in coords {
            let x = (c.x - centerX) * scale
            let y = (c.y - centerY) * scale
            let z = (c.z - centerZ) * scale
            result.append(SCNVector3(x, y, z))
        }

        return result
    }

    /// Build annotations with same scaling as points
    private func buildScaledAnnotations(
        chunks: [DocumentChunk],
        coords: [SIMD3<Float>],
        assignments: [UUID: String]
    ) -> [Embedding3DSceneView.AnnotationData] {
        guard chunks.count == coords.count, !coords.isEmpty else { return [] }

        // Calculate scaling parameters (same as scaleCoordinatesForViewing)
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for c in coords {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
            minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2
        let maxSpan = max(max(maxX - minX, maxY - minY), max(maxZ - minZ, 0.0001))
        let scale = 3.0 / maxSpan

        // Group by topic
        var topicPoints: [String: [SIMD3<Float>]] = [:]
        for (i, chunk) in chunks.enumerated() {
            guard i < coords.count else { continue }
            let topic = assignments[chunk.id] ?? "General"
            topicPoints[topic, default: []].append(coords[i])
        }

        // Get topic colors
        var topicColorMap: [String: PlatformColor] = [:]
        if let profile {
            for topic in profile.dominantTopics {
                topicColorMap[topic.name] = PlatformColor(topic.color)
            }
        }

        var result: [Embedding3DSceneView.AnnotationData] = []
        for (topic, pts) in topicPoints where pts.count >= 3 {
            // Calculate centroid in original coords
            var sumX: Float = 0, sumY: Float = 0, sumZ: Float = 0
            for p in pts {
                sumX += p.x; sumY += p.y; sumZ += p.z
            }
            let count = Float(pts.count)

            // Apply SAME scaling as points!
            let centroidX = ((sumX / count) - centerX) * scale
            let centroidY = ((sumY / count) - centerY) * scale
            let centroidZ = ((sumZ / count) - centerZ) * scale

            let color = topicColorMap[topic] ?? PlatformColor(.gray)

            result.append(Embedding3DSceneView.AnnotationData(
                position: SCNVector3(centroidX, centroidY, centroidZ),
                title: topic,
                keywords: ["\(pts.count) pts"],
                color: color,
                detailLevel: pts.count
            ))
        }

        return result
    }
}

// MARK: - Compact Atlas Scene View

/// A streamlined 3D embedding view designed for embedded use.
/// Shows topic-colored dots with cluster labels and full settings control.
struct CompactAtlasSceneView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService

    let profile: LibraryProfile
    let height: CGFloat

    // Settings passed from parent
    let projectionMethod: ProjectionMethodKind
    let pointScale: Double
    let autoRotate: Bool
    let depthCue: Bool
    let showLabels: Bool
    let backgroundStyle: EmbeddingSceneBackgroundStyle

    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var colors: [PlatformColor] = []
    @State private var annotations: [Embedding3DSceneView.AnnotationData] = []
    @State private var sceneReloadToken = UUID()
    @State private var chunkTopicAssignments: [UUID: String] = [:] // chunk.id → topic name

    private let sampleLimit = 1500

    // Computed scene options from settings
    private var sceneOptions: Embedding3DSceneView.SceneOptions {
        Embedding3DSceneView.SceneOptions(
            pointScale: CGFloat(pointScale),
            autoRotate: autoRotate,
            showAxes: true, // Always show axes for spatial reference
            depthCue: depthCue,
            backgroundStyle: backgroundStyle
        )
    }

    var body: some View {
        ZStack {
            if isLoading {
                loadingPlaceholder
            } else if points.isEmpty {
                emptyPlaceholder
            } else {
                sceneContent
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: containerService.activeContainerId) {
            await loadAndProject()
        }
        .task(id: projectionMethod) {
            await loadAndProject()
        }
        // Trigger scene reload when settings change (without full recompute)
        .onChange(of: pointScale) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: autoRotate) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: depthCue) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: showLabels) { _, _ in sceneReloadToken = UUID() }
        .onChange(of: backgroundStyle) { _, _ in sceneReloadToken = UUID() }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.7))

            Text("Mapping semantic space…")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.4))

            Text("Add documents to visualize")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
    }

    private var sceneContent: some View {
        ZStack(alignment: .bottomLeading) {
            Embedding3DSceneView(
                points: points,
                colors: colors,
                options: sceneOptions,
                reloadToken: sceneReloadToken,
                annotations: showLabels ? annotations : []
            )

            // Legend overlay with topic colors
            VStack(alignment: .leading, spacing: 0) {
                topicLegendOverlay
                sceneHintOverlay
            }
        }
    }

    /// Shows what each color represents
    private var topicLegendOverlay: some View {
        let topicColors = buildTopicColorLegend()

        return Group {
            if !topicColors.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(topicColors.prefix(5), id: \.name) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)

                            Text(item.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    private struct TopicColorItem: Hashable {
        let name: String
        let color: Color
        let count: Int
    }

    private func buildTopicColorLegend() -> [TopicColorItem] {
        // Count chunks per topic
        var topicCounts: [String: Int] = [:]
        for (_, topicName) in chunkTopicAssignments {
            topicCounts[topicName, default: 0] += 1
        }

        // Map to colors from profile
        var result: [TopicColorItem] = []
        for topic in profile.dominantTopics {
            if let count = topicCounts[topic.name], count > 0 {
                result.append(TopicColorItem(name: topic.name, color: topic.color, count: count))
            }
        }

        // Sort by count descending
        return result.sorted { $0.count > $1.count }
    }

    /// Small overlay explaining what the user is looking at
    private var sceneHintOverlay: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.draw")
                .font(.system(size: 8))
            Text("Drag to rotate • Pinch to zoom")
                .font(.system(size: 8))
        }
        .foregroundColor(.white.opacity(0.4))
        .padding(6)
    }

    // MARK: - Data Loading

    private func loadAndProject() async {
        await MainActor.run { isLoading = true }

        let allChunks = await ragService.allChunksForActiveContainer()

        guard !allChunks.isEmpty else {
            await MainActor.run {
                points = []
                colors = []
                annotations = []
                isLoading = false
            }
            return
        }

        // Sample chunks (stratified by document)
        let sampledChunks = sampleChunks(allChunks)
        let embeddings = sampledChunks.map { $0.embedding }

        guard !embeddings.isEmpty else {
            await MainActor.run {
                points = []
                colors = []
                annotations = []
                isLoading = false
            }
            return
        }

        // Project to 3D
        let seed = UInt64(abs(Int64(containerService.activeContainerId.uuidString.hashValue)))
        let coords3D = ProjectionService.shared.project3D(
            embeddings: embeddings,
            method: projectionMethod,
            seed: seed
        )

        // Enhanced topic assignment using NLP keywords
        let topicAssignments = assignTopicsNLP(chunks: sampledChunks)

        // Map colors based on topic assignments
        let mappedColors = mapTopicColors(chunks: sampledChunks, assignments: topicAssignments)

        // Use ACTUAL PCA/UMAP coordinates - scale them properly for viewing
        // This preserves natural clustering and semantic structure!
        let scaledPoints = scalePointsForViewing(coords3D)

        // Build 3D cluster label annotations at ACTUAL cluster positions
        let clusterAnnotations = buildClusterAnnotations(
            chunks: sampledChunks,
            coords: coords3D, // Use original coords for centroid calculation
            assignments: topicAssignments
        )

        await MainActor.run {
            points = scaledPoints
            colors = mappedColors
            annotations = clusterAnnotations
            chunkTopicAssignments = topicAssignments
            sceneReloadToken = UUID()
            isLoading = false
        }
    }

    /// Scales actual PCA/UMAP coordinates for proper 3D viewing
    /// Preserves natural clustering and semantic structure (like Apple Embedding Atlas)
    private func scalePointsForViewing(_ coords: [SIMD3<Float>]) -> [SCNVector3] {
        guard !coords.isEmpty else { return [] }

        // Find bounds
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for c in coords {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
            minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
        }

        // Calculate center and span
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2

        let spanX = max(maxX - minX, 0.0001)
        let spanY = max(maxY - minY, 0.0001)
        let spanZ = max(maxZ - minZ, 0.0001)
        let maxSpan = max(spanX, max(spanY, spanZ))

        // Target viewing size - fills scene nicely with room for labels
        let targetSize: Float = 3.0
        let scale = targetSize / maxSpan

        var result: [SCNVector3] = []
        result.reserveCapacity(coords.count)

        for c in coords {
            // Center at origin and scale uniformly to preserve shape
            let x = (c.x - centerX) * scale
            let y = (c.y - centerY) * scale
            let z = (c.z - centerZ) * scale

            // Small jitter to prevent exact overlaps (rare edge case)
            let seed = UInt32(result.count)
            let jitterX = (Float((seed &* 1_103_515_245 &+ 12345) % 10000) / 20000.0 - 0.025) * 0.02
            let jitterY = (Float((seed &* 1_664_525 &+ 1_013_904_223) % 10000) / 20000.0 - 0.025) * 0.02
            let jitterZ = (Float((seed &* 22_695_477 &+ 1) % 10000) / 20000.0 - 0.025) * 0.02

            result.append(SCNVector3(x + jitterX, y + jitterY, z + jitterZ))
        }

        return result
    }

    // MARK: - DEPRECATED: Old Fibonacci sphere distribution (removed - made everything look like a ball!)

    // Keeping commented for reference:
    // private func spreadPointsOnSphere(_ coords: [SIMD3<Float>]) -> [SCNVector3]

    // MARK: - Enhanced NLP Topic Assignment

    private func assignTopicsNLP(chunks: [DocumentChunk]) -> [UUID: String] {
        var assignments: [UUID: String] = [:]

        // Build keyword sets for each topic from profile
        var topicKeywords: [String: Set<String>] = [:]
        for topic in profile.dominantTopics {
            var keywords = Set<String>()
            keywords.insert(topic.name.lowercased())
            // Add common variations and related terms
            keywords.formUnion(expandKeywords(topic.name))
            topicKeywords[topic.name] = keywords
        }

        for chunk in chunks {
            let text = chunk.text.lowercased()
            let words = extractSignificantWords(from: text)

            var bestTopic: String?
            var bestScore = 0

            for (topicName, keywords) in topicKeywords {
                let score = words.intersection(keywords).count
                if score > bestScore {
                    bestScore = score
                    bestTopic = topicName
                }
            }

            if let topic = bestTopic, bestScore > 0 {
                assignments[chunk.id] = topic
            } else {
                // Fallback: infer from content patterns
                assignments[chunk.id] = inferTopicFromContent(text: text)
            }
        }

        return assignments
    }

    private func expandKeywords(_ topic: String) -> Set<String> {
        let base = topic.lowercased()
        var expanded = Set<String>()

        // Add the base term
        expanded.insert(base)

        // Add common suffixes/variations
        let suffixes = ["s", "ing", "ed", "er", "tion", "ment", "ness", "ity", "ies"]
        for suffix in suffixes {
            expanded.insert(base + suffix)
        }

        // Domain-specific expansions
        let domainMappings: [String: [String]] = [
            "code": ["programming", "software", "function", "class", "method", "api", "algorithm"],
            "data": ["database", "analytics", "statistics", "dataset", "schema", "query"],
            "design": ["ui", "ux", "interface", "layout", "visual", "style", "component"],
            "security": ["authentication", "encryption", "auth", "token", "password", "secure"],
            "network": ["http", "api", "endpoint", "request", "response", "server", "client"],
            "test": ["testing", "unit", "integration", "mock", "assert", "spec", "coverage"],
            "document": ["documentation", "readme", "guide", "tutorial", "reference", "manual"],
            "config": ["configuration", "settings", "options", "parameters", "env", "environment"],
            "model": ["schema", "entity", "struct", "class", "type", "object", "record"],
            "view": ["component", "screen", "page", "layout", "template", "render", "display"],
        ]

        if let related = domainMappings[base] {
            expanded.formUnion(related)
        }

        // Check if base matches any domain
        for (_, related) in domainMappings where related.contains(base) {
            expanded.formUnion(related)
        }

        return expanded
    }

    private func extractSignificantWords(from text: String) -> Set<String> {
        // Common stop words to filter out
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
            "be", "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "must", "shall", "can", "need",
            "this", "that", "these", "those", "it", "its", "they", "them",
            "we", "us", "our", "you", "your", "he", "she", "him", "her",
        ]

        let words = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .map { $0.lowercased() }
            .filter { !stopWords.contains($0) }

        return Set(words)
    }

    private func inferTopicFromContent(text: String) -> String {
        // Pattern-based topic inference for unmatched chunks
        let patterns: [(pattern: String, topic: String)] = [
            ("func |class |struct |enum |protocol ", "Code"),
            ("import |#include|require\\(|from .+ import", "Code"),
            ("http|api|endpoint|request|response", "API"),
            ("test|spec|assert|expect|describe|it\\(", "Testing"),
            ("config|settings|options|parameters", "Config"),
            ("error|exception|throw|catch|try", "Errors"),
            ("async|await|promise|future|task", "Async"),
            ("view|component|render|display|screen", "UI"),
            ("model|schema|entity|record|data", "Data"),
            ("auth|login|token|session|permission", "Auth"),
        ]

        for (pattern, topic) in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return topic
            }
        }

        return "General"
    }

    // MARK: - Color Mapping

    private func mapTopicColors(chunks: [DocumentChunk], assignments: [UUID: String]) -> [PlatformColor] {
        // Build topic → color mapping from profile
        var topicColorMap: [String: PlatformColor] = [:]
        for topic in profile.dominantTopics {
            topicColorMap[topic.name] = PlatformColor(topic.color)
        }

        // Fallback palette for inferred topics
        let fallbackPalette: [String: Color] = [
            "Code": .blue,
            "API": .purple,
            "Testing": .green,
            "Config": .orange,
            "Errors": .red,
            "Async": .cyan,
            "UI": .pink,
            "Data": .indigo,
            "Auth": .yellow,
            "General": .gray,
        ]

        // Document-based fallback palette
        let docPalette: [PlatformColor] = [
            PlatformColor(.blue.opacity(0.8)),
            PlatformColor(.purple.opacity(0.8)),
            PlatformColor(.teal.opacity(0.8)),
            PlatformColor(.orange.opacity(0.8)),
            PlatformColor(.pink.opacity(0.8)),
            PlatformColor(.green.opacity(0.8)),
        ]
        var docColorMap: [UUID: PlatformColor] = [:]
        var docColorIndex = 0

        return chunks.map { chunk in
            guard let topicName = assignments[chunk.id] else {
                // No topic assigned - use document color
                if let existing = docColorMap[chunk.documentId] {
                    return existing
                }
                let color = docPalette[docColorIndex % docPalette.count]
                docColorMap[chunk.documentId] = color
                docColorIndex += 1
                return color
            }

            // Try profile topic color
            if let color = topicColorMap[topicName] {
                return color
            }

            // Try fallback palette
            if let fallback = fallbackPalette[topicName] {
                return PlatformColor(fallback)
            }

            // Ultimate fallback
            return PlatformColor(.gray.opacity(0.6))
        }
    }

    // MARK: - 3D Cluster Annotations

    private func buildClusterAnnotations(
        chunks: [DocumentChunk],
        coords: [SIMD3<Float>],
        assignments: [UUID: String]
    ) -> [Embedding3DSceneView.AnnotationData] {
        guard chunks.count == coords.count else { return [] }

        // First, compute the same scaling parameters used for points
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude

        for c in coords {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minY = min(minY, c.y); maxY = max(maxY, c.y)
            minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let centerZ = (minZ + maxZ) / 2

        let spanX = max(maxX - minX, 0.0001)
        let spanY = max(maxY - minY, 0.0001)
        let spanZ = max(maxZ - minZ, 0.0001)
        let maxSpan = max(spanX, max(spanY, spanZ))
        let scale = 3.0 / maxSpan // Same as scalePointsForViewing

        // Group points by topic
        var topicPoints: [String: [SIMD3<Float>]] = [:]
        for (index, chunk) in chunks.enumerated() {
            guard index < coords.count else { continue }
            let topic = assignments[chunk.id] ?? "General"
            topicPoints[topic, default: []].append(coords[index])
        }

        // Build topic → color mapping
        var topicColorMap: [String: PlatformColor] = [:]
        for topic in profile.dominantTopics {
            topicColorMap[topic.name] = PlatformColor(topic.color)
        }

        // Create annotation at centroid of each cluster
        var annotations: [Embedding3DSceneView.AnnotationData] = []

        for (topicName, pointsInCluster) in topicPoints {
            guard pointsInCluster.count >= 3 else { continue } // Only label significant clusters

            // Calculate centroid in ORIGINAL coords
            var sumX: Float = 0
            var sumY: Float = 0
            var sumZ: Float = 0
            for p in pointsInCluster {
                sumX += p.x
                sumY += p.y
                sumZ += p.z
            }
            let count = Float(pointsInCluster.count)

            // Apply same scaling as points so label appears at cluster center!
            let centroidX = ((sumX / count) - centerX) * scale
            let centroidY = ((sumY / count) - centerY) * scale
            let centroidZ = ((sumZ / count) - centerZ) * scale

            let centroid = SCNVector3(centroidX, centroidY, centroidZ)

            // Get color for this topic
            let color = topicColorMap[topicName] ?? PlatformColor(.white.opacity(0.7))

            // Create keywords from topic name
            let keywords = [topicName, "\(pointsInCluster.count) pts"]

            annotations.append(Embedding3DSceneView.AnnotationData(
                position: centroid,
                title: topicName,
                keywords: keywords,
                color: color,
                detailLevel: pointsInCluster.count > 50 ? 2 : (pointsInCluster.count > 20 ? 1 : 0)
            ))
        }

        // Sort by cluster size (largest first) - show ALL topics, not just top few
        annotations.sort { $0.detailLevel > $1.detailLevel }
        return annotations
    }

    // MARK: - Sampling

    private func sampleChunks(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        guard chunks.count > sampleLimit else { return chunks }

        var byDoc: [UUID: [DocumentChunk]] = [:]
        for chunk in chunks {
            byDoc[chunk.documentId, default: []].append(chunk)
        }

        let docCount = byDoc.count
        let perDocQuota = max(1, sampleLimit / max(docCount, 1))

        var sampled: [DocumentChunk] = []
        sampled.reserveCapacity(sampleLimit)

        let seed = UInt64(abs(Int64(containerService.activeContainerId.uuidString.hashValue)))
        var prng = VizLCG(seed: seed)

        for (_, docChunks) in byDoc {
            if docChunks.count > perDocQuota {
                var indices = Array(0 ..< docChunks.count)
                for i in stride(from: indices.count - 1, through: 1, by: -1) {
                    let j = Int(prng.next() % UInt64(i + 1))
                    if i != j { indices.swapAt(i, j) }
                }
                for idx in indices.prefix(perDocQuota) {
                    sampled.append(docChunks[idx])
                }
            } else {
                sampled.append(contentsOf: docChunks)
            }
        }

        if sampled.count > sampleLimit {
            var order = Array(0 ..< sampled.count)
            for i in stride(from: order.count - 1, through: 1, by: -1) {
                let j = Int(prng.next() % UInt64(i + 1))
                if i != j { order.swapAt(i, j) }
            }
            sampled = order.prefix(sampleLimit).map { sampled[$0] }
        }

        return sampled
    }
}
