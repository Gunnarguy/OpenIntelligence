//  AdaptiveVisualizationsView.swift
//  OpenIntelligence
//
//  Dynamic visualization dashboard that adapts to each library's unique
//  content, structure, and usage patterns. Replaces static tabs with
//  contextually relevant insight cards and recommended views.

import Charts
import SceneKit
import SwiftUI
import TipKit

// MARK: - When the Atlas loads

/// When the Atlas's views load again (5.7): the page's profile, the 3D card and the full-screen view. Through 5.6 they
/// loaded when they appeared and when the open library changed, so passages imported while the Atlas was on screen
/// stayed out of it until it was opened again. An import sets `RAGService.isProcessing` once for its whole queue
/// (`runIngestionLoop`), so the views load once when it ends, not for each document. `addDocument` with its default
/// `manageProcessingState` clears the flag on its own, and `reembedDocuments` re-adds each document that way, so a
/// re-embed flips it once per document: a view waits `settleDelay` when only the document count moved (`settlesFirst`),
/// and a burst like that loads once, at its end. A view records the key it loaded only when that load finished, so a
/// load an import interrupted is done again rather than skipped.
struct AtlasContentKey: Hashable {
    let containerId: UUID
    /// The number of documents in every library, or nil while an import runs.
    let settledDocumentCount: Int?
    /// What else the view draws by, such as its projection method.
    let variant: String

    init(containerId: UUID, documentCount: Int, importing: Bool, variant: String = "") {
        self.containerId = containerId
        self.settledDocumentCount = importing ? nil : documentCount
        self.variant = variant
    }

    /// True when this key only says that an import has started in what the view last loaded: nothing new is in the
    /// library yet, so the view keeps what it shows and loads when the import ends.
    func onlyStartsAnImport(after loaded: AtlasContentKey?) -> Bool {
        guard let loaded, settledDocumentCount == nil, loaded.settledDocumentCount != nil else { return false }
        return loaded.containerId == containerId && loaded.variant == variant
    }

    /// True when only the document count has moved since what the view last loaded, in the same library and view: an
    /// import or a re-embed step has just ended, or a document was deleted. The view waits `settleDelay` first, and a
    /// change in that time cancels the wait.
    func settlesFirst(after loaded: AtlasContentKey?) -> Bool {
        guard let loaded, settledDocumentCount != nil else { return false }
        return loaded.containerId == containerId && loaded.variant == variant
    }

    /// How long a view waits before loading for a key that `settlesFirst`.
    static let settleDelay: Duration = .milliseconds(800)
}

// MARK: - Main View

/// How the Atlas draws its 3D map (5.7). The scene is the SceneKit map the Atlas had through 5.6: a label at each end
/// of each axis and each cluster's name in the map, with the cluster list and the axis names over it. The chart is the
/// Swift Charts cube with a written key that replaced it in 5.7. On 2026-10-20 the owner asked for the scene back: its
/// named axes and clusters showed where a library's material sits and what it is about. So the scene is the default
/// and the chart is the other choice, kept in the app's settings for the card and the full screen alike.
enum AtlasDrawingStyle: String, CaseIterable {
    case scene
    case chart

    var title: String {
        switch self {
        case .scene: return "Scene"
        case .chart: return "Chart"
        }
    }
}

/// The names the Atlas's scene puts in the map (5.7, restored): one at the middle of each group of points, a cluster or
/// in All Libraries a library, in the group's colour, scaled as the points are (to 4.5 around their centre). Through
/// 5.6 the card and the full screen each had a copy of this.
enum AtlasSceneLabels {
    static func annotations(
        coords: [SIMD3<Float>],
        groups: [Int],
        names: [String],
        colors: [PlatformColor],
        detailLevel: (Int) -> Int
    ) -> [Embedding3DSceneView.AnnotationData] {
        guard coords.count == groups.count, !coords.isEmpty, !colors.isEmpty else { return [] }
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for c in coords {
            minimum = pointwiseMin(minimum, c)
            maximum = pointwiseMax(maximum, c)
        }
        let center = (minimum + maximum) / 2
        let span = maximum - minimum
        let scale: Float = 4.5 / max(max(span.x, span.y), max(span.z, 0.0001))

        var members: [Int: (sum: SIMD3<Float>, count: Int)] = [:]
        for (index, group) in groups.enumerated() where group >= 0 && group < names.count {
            let entry = members[group] ?? (SIMD3<Float>(repeating: 0), 0)
            members[group] = (entry.sum + coords[index], entry.count + 1)
        }
        return names.indices.compactMap { group in
            guard let entry = members[group], entry.count > 0 else { return nil }
            let centroid = (entry.sum / Float(entry.count) - center) * scale
            return Embedding3DSceneView.AnnotationData(
                position: SCNVector3(centroid.x, centroid.y, centroid.z),
                title: names[group],
                keywords: ["\(entry.count) pts"],
                color: colors[group % colors.count],
                detailLevel: detailLevel(entry.count),
                clusterSize: entry.count,
                isDocumentCluster: false
            )
        }
    }

    /// Point size scaled down for large maps, as through 5.6.
    static func pointScale(for count: Int) -> Double {
        if count >= 10000 { return 0.6 }
        if count >= 5000 { return 0.7 }
        if count >= 2000 { return 0.85 }
        return 1.0
    }
}

struct AdaptiveVisualizationsView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var engine = LibraryVisualizationEngine.shared

    @State private var selectedInsight: VisualizationInsight?
    @State private var expandedView: LibraryVisualizationEngine.RecommendedView.ViewType?
    @State private var showAllViews = false
    @State private var showAllInsights = false
    @State private var show3DFullscreen = false
    @State private var atlasMode: AtlasMode = .compact
    @State private var showAtlasSettings = false

    // Atlas visualization settings
    @State private var atlasProjection: AtlasProjectionMethod = .pca
    @State private var atlasAutoRotate = false // Off by default - let user explore
    @State private var atlasDepthCue = false // Off for cleaner look
    // For the scene only (`AtlasDrawingStyle`): the chart draws its own points and no labels in the map.
    @State private var atlasPointScale: Double = 1.2
    @State private var atlasShowLabels = true
    @AppStorage("atlasDrawingStyle") private var atlasStyle: AtlasDrawingStyle = .scene
    @State private var atlasShowAxes = true // On by default - show spatial reference
    @State private var atlasBackground: AtlasBackgroundStyle = .midnight // Dark for contrast
    /// What the profile was last built for (`AtlasContentKey`).
    @State private var atlasLoadedKey: AtlasContentKey?

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
        case cosmos = "Cosmos"
        case nebula = "Nebula"
        case ocean = "Ocean"
        case forest = "Forest"
        case parchment = "Parchment"

        var sceneStyle: EmbeddingSceneBackgroundStyle {
            switch self {
            case .aurora: return .aurora
            case .midnight: return .midnight
            case .cosmos: return .cosmos
            case .nebula: return .nebula
            case .ocean: return .ocean
            case .forest: return .forest
            case .parchment: return .parchment
            }
        }

        var icon: String {
            switch self {
            case .aurora: return "sparkles"
            case .midnight: return "moon.stars"
            case .cosmos: return "star.fill"
            case .nebula: return "hurricane"
            case .ocean: return "water.waves"
            case .forest: return "leaf"
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
            LazyVStack(spacing: DSSpacing.lg) {
                // Atlas is the least self-explanatory tab in the app: it had no
                // `InfoButtonView`, no empty-state copy explaining what a cluster or an
                // embedding is, and nothing telling a new user why they would open it.
                //
                // The tip retires itself once the user actually explores — the
                // `atlasViewed` event is donated on opening the fullscreen atlas or
                // expanding a view, not on appearance, so it does not flash once and
                // vanish before it has been read.
                InlineTipView(tip: AtlasTip())

                // HERO: 3D Atlas (always visible for libraries with content)
                if let profile = engine.currentProfile, profile.chunkCount >= 10 {
                    hero3DAtlasSection(profile: profile)
                }

                libraryHeader

                // Only show the loading card when there is genuinely nothing to show. `analyze()`
                // sets `isAnalyzing` before doing any work, so on a re-entry this replaced a
                // complete, in-memory profile with a spinner: the page collapsed, the scroll
                // position clamped to the top, and everything reflowed back in once the same
                // result was re-derived.
                //
                // Nothing is hidden by this. The first analysis of a library still shows the
                // card, because `currentProfile` is nil then. A refresh over existing data now
                // keeps the old profile on screen until the new one replaces it.
                if engine.isAnalyzing, engine.currentProfile == nil {
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
            .padding(DSSpacing.lg)
        }
        .background(DSColors.background)
        .navigationTitle("Knowledge Atlas")
        .navigationBarTitleDisplayMode(.large)
        #if os(iOS)
        .fullScreenCover(isPresented: $show3DFullscreen) {
            Fullscreen3DAtlasView()
                .environmentObject(ragService)
                .environmentObject(containerService)
        }
        #else
        .sheet(isPresented: $show3DFullscreen) {
            Fullscreen3DAtlasView()
                .environmentObject(ragService)
                .environmentObject(containerService)
                .frame(minWidth: 800, minHeight: 600)
        }
        #endif
        .sheet(isPresented: $showAllInsights) {
            NavigationStack {
                List(engine.insights) { insight in
                    HStack(spacing: DSSpacing.md) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(insight.color)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(insight.title)
                                .font(.subheadline.weight(.medium))
                            Text(insight.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("All Insights")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showAllInsights = false }
                    }
                }
            }
        }
        .onChange(of: show3DFullscreen) { _, entering in
            if entering {
                // Retires `AtlasTip`. Donated on real exploration rather than on appear,
                // so the tip survives until it has done its job.
                Task { await AtlasTip.atlasViewed.donate() }
                DSHaptics.medium()
            }
        }
        .onChange(of: expandedView) { _, expanded in
            if expanded != nil {
                Task { await AtlasTip.atlasViewed.donate() }
            }
        }
        // One task, not two. A bare `.task` and `.task(id:)` both called `refreshAnalysis()`, so
        // every Atlas entry built the profile twice. `.task(id:)` already fires on first
        // appearance as well as on container change, so it covers both cases the pair covered.
        //
        // The duplicate could not be cancelled away: `analysisTask?.cancel()` cannot stop the
        // in-flight copy because `buildProfile` does not check `Task.isCancelled`. Its work for
        // each passage runs off the main actor since 5.7 (`LibraryVisualizationEngine.analyzePassages`),
        // so a duplicate costs time, not the screen.
        //
        // Keyed by the open library and the number of documents in every library once no import runs
        // (`AtlasContentKey`, 5.7), so an import that ends while the Atlas is open shows in it.
        .task(id: atlasContentKey) {
            let key = atlasContentKey
            guard !key.onlyStartsAnImport(after: atlasLoadedKey) else { return }
            if key.settlesFirst(after: atlasLoadedKey) {
                try? await Task.sleep(for: AtlasContentKey.settleDelay)
                guard !Task.isCancelled else { return }
            }
            await refreshAnalysis()
            if !Task.isCancelled { atlasLoadedKey = key }
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
                // The chart is taller (5.7): its axis key sits under it, inside this height. The scene names its axes
                // in the map, at the heights it had through 5.6.
                height: atlasStyle == .chart ? (atlasMode == .expanded ? 470 : 340) : (atlasMode == .expanded ? 420 : 280),
                projectionMethod: atlasProjection.projectionKind,
                autoRotate: atlasAutoRotate,
                depthCue: atlasDepthCue,
                backgroundStyle: atlasBackground.sceneStyle,
                style: atlasStyle,
                pointScale: atlasPointScale,
                showLabels: atlasShowLabels
            )
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.sm)

            // Topic legend (makes the dots meaningful)
            if !profile.dominantTopics.isEmpty {
                atlasTopicLegend(topics: profile.dominantTopics)
            }

            // Quick stats bar
            atlas3DStatsBar(profile: profile)
        }
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
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
        .animation(DSAnimations.snappySpring, value: atlasMode)
    }

    private var atlasHeader: some View {
        HStack(spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Semantic Atlas")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(
                    settings.showTechnicalDetails
                        ? atlasProjection.rawValue + " projection • \(atlasAutoRotate ? "Rotating" : "Static")"
                        : "Passages that mean similar things sit close together")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Settings toggle
            Button {
                withAnimation(DSAnimations.snappySpring) {
                    showAtlasSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .padding(DSSpacing.xs)
                    .background(
                        Circle().fill(showAtlasSettings ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                    .foregroundStyle(.white.opacity(showAtlasSettings ? 1 : 0.7))
            }

            // Compact/Expanded toggle
            HStack(spacing: DSSpacing.xxs) {
                ForEach([AtlasMode.compact, AtlasMode.expanded], id: \.self) { mode in
                    Button {
                        withAnimation(DSAnimations.snappySpring) {
                            atlasMode = mode
                        }
                    } label: {
                        Image(systemName: mode == .compact ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward")
                            .font(.caption)
                            .padding(DSSpacing.xs)
                            .background(
                                Circle().fill(atlasMode == mode ? Color.white.opacity(0.2) : Color.clear)
                            )
                            .foregroundStyle(.white.opacity(atlasMode == mode ? 1 : 0.5))
                    }
                }
            }

            Button {
                show3DFullscreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(DSSpacing.sm)
                    .background(Circle().fill(Color.white.opacity(0.15)))
                    .foregroundStyle(.white)
            }
            // An icon alone had no name for VoiceOver or a UI test (5.7).
            .accessibilityLabel("Full screen")
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
    }

    // MARK: - Atlas Settings Toolbar

    private var atlasSettingsToolbar: some View {
        VStack(spacing: DSSpacing.md) {
            // Row 1: Projection method
            HStack(spacing: DSSpacing.sm) {
                Text("Projection")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                ForEach(AtlasProjectionMethod.allCases, id: \.self) { method in
                    Button {
                        withAnimation(DSAnimations.snappySpring) {
                            atlasProjection = method
                        }
                    } label: {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: method.icon)
                                .scaledFont(size: 10)
                            Text(method.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(
                            Capsule().fill(atlasProjection == method ? Color.accentColor : Color.white.opacity(0.1))
                        )
                        .foregroundStyle(atlasProjection == method ? .white : .white.opacity(0.7))
                    }
                }
            }

            // Scene or chart (`AtlasDrawingStyle`, 5.7).
            Picker("Map", selection: $atlasStyle) {
                ForEach(AtlasDrawingStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            // Row 2: Point size slider, for the scene. The chart draws its own points (`AtlasChart3D`), and Apple does
            // not document the unit of a 3D chart's `symbolSize`, so a slider could not promise what it changed there.
            if atlasStyle == .scene {
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "circle.fill")
                        .scaledFont(size: 6)
                        .imageScale(.small)
                        .foregroundStyle(.white.opacity(0.5))

                    Slider(value: $atlasPointScale, in: 0.5 ... 2.0, step: 0.1)
                        .tint(.accentColor)
                        .accessibilityLabel("Point size")

                    Image(systemName: "circle.fill")
                        .scaledFont(size: 12)
                        .foregroundStyle(.white.opacity(0.5))

                    Text(String(format: "%.1fx", atlasPointScale))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32)
                }
            }

            // Row 3: Toggle options
            HStack(spacing: DSSpacing.lg) {
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

                if atlasStyle == .scene {
                    AtlasToggleChip(
                        icon: "tag",
                        label: "Labels",
                        isOn: $atlasShowLabels
                    )
                }

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
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: atlasBackground.icon)
                            .scaledFont(size: 10)
                        Text(atlasBackground.rawValue)
                            .font(.caption2)
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.white.opacity(0.05))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func atlasTopicLegend(topics: [TopicCluster]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(topics.prefix(5)) { topic in
                    HStack(spacing: DSSpacing.xs) {
                        Circle()
                            .fill(topic.color)
                            .frame(width: 8, height: 8)

                        Text(topic.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.9))

                        Text("\(topic.chunkCount)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xs)
                    .background(
                        Capsule().fill(topic.color.opacity(0.2))
                    )
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.bottom, DSSpacing.sm)
    }

    private func atlas3DStatsBar(profile: LibraryProfile) -> some View {
        HStack(spacing: DSSpacing.lg) {
            AtlasStatPill(icon: "cube.fill", value: "\(profile.chunkCount)", label: "Points", color: DSColors.accent)
            AtlasStatPill(icon: "doc.fill", value: "\(profile.documentCount)", label: "Sources", color: .green)

            if !profile.dominantTopics.isEmpty {
                AtlasStatPill(icon: "circle.hexagongrid.fill", value: "\(profile.dominantTopics.count)", label: "Clusters", color: DSColors.accent)
            }

            if profile.topicDiversity > 0.5 {
                AtlasStatPill(icon: "arrow.triangle.branch", value: "High", label: "Diversity", color: .orange)
            }

            Spacer()
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.bottom, DSSpacing.md)
    }

    // MARK: - Library Header

    private var libraryHeader: some View {
        VStack(spacing: DSSpacing.lg) {
            HStack(spacing: DSSpacing.lg) {
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
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(activeContainer?.name ?? "Library")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let profile = engine.currentProfile {
                        HStack(spacing: DSSpacing.sm) {
                            Label(profile.sizeCategory.rawValue, systemImage: profile.sizeCategory.icon)
                            Text("•")
                            Label(profile.retrievalActivity.rawValue, systemImage: profile.retrievalActivity.icon)
                                .foregroundStyle(profile.retrievalActivity.color)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if engine.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastAnalyzed = engine.lastAnalyzed {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text("Updated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(lastAnalyzed, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Quick metrics strip
            if let profile = engine.currentProfile {
                quickMetricsStrip(profile: profile)
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func quickMetricsStrip(profile: LibraryProfile) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.lg) {
                QuickMetric(icon: "doc.text", label: "Docs", value: "\(profile.documentCount)")
                QuickMetric(icon: "square.stack.3d.down.right", label: "Passages", value: "\(profile.libraryPassageCount)")
                QuickMetric(icon: "text.word.spacing", label: "Words", value: formatNumber(profile.totalWords))

                if !profile.dominantTopics.isEmpty {
                    QuickMetric(icon: "circle.hexagongrid", label: "Topics", value: "\(profile.dominantTopics.count)")
                }

                if profile.isHighlyActive {
                    QuickMetric(icon: "flame.fill", label: "Hot Chunks", value: "\(profile.hotChunks.count)", color: .orange)
                }
            }
            .padding(.horizontal, DSSpacing.xs)
        }
    }

    // MARK: - Insights Horizontal

    private var insightsHorizontalSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Insights")
                    .font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(engine.insights.prefix(5)) { insight in
                        CompactInsightCard(insight: insight) {
                            handleInsightTap(insight)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.xxs)
            }
        }
    }

    // MARK: - Insight Cards (legacy vertical)

    private func insightCardsSection(profile _: LibraryProfile) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("Insights")
                    .font(.headline)

                Spacer()

                if engine.insights.count > 3 {
                    Button("See All") {
                        showAllInsights = true
                    }
                    .font(.caption)
                }
            }

            if engine.insights.isEmpty {
                noInsightsCard
            } else {
                LazyVStack(spacing: DSSpacing.md) {
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
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Library looks great!")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("No specific recommendations right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Recommended Views

    private var recommendedViewsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("Explore")
                    .font(.headline)

                Spacer()

                Button(showAllViews ? "Show Less" : "All Views") {
                    withAnimation(DSAnimations.snappySpring) {
                        showAllViews.toggle()
                    }
                }
                .font(.caption)
            }

            let views = showAllViews ? engine.recommendedViews : Array(engine.recommendedViews.prefix(4))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DSSpacing.md) {
                ForEach(views) { view in
                    RecommendedViewCard(view: view, isExpanded: expandedView == view.type) {
                        // "3D Semantic Map" opens the Atlas's full-screen 3D map (5.7). The page never shows
                        // `.embedding3D` as an expanded view, so through 5.6 a tap only put a check on the tile.
                        if view.type == .embedding3D {
                            show3DFullscreen = true
                            return
                        }
                        withAnimation(DSAnimations.snappySpring) {
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
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text(type.rawValue)
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(DSAnimations.snappySpring) {
                        expandedView = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            expandedViewContent(type: type, profile: profile)
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
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
                // The library's own vector size; a fixed 512 described a model the default libraries don't use (5.7).
                embeddingDimension: activeContainer?.embeddingDim ?? 384
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
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Library Stats")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DSSpacing.md) {
                StatTile(icon: "doc.text.fill", label: "Documents", value: "\(profile.documentCount)", color: DSColors.accent)
                StatTile(icon: "square.stack.3d.down.right.fill", label: "Passages", value: "\(profile.libraryPassageCount)", color: DSColors.accent)
                StatTile(icon: "character.cursor.ibeam", label: "Avg Chunk", value: "\(profile.avgChunkSize)w", color: .green)
                StatTile(icon: "chart.pie.fill", label: "Diversity", value: String(format: "%.0f%%", profile.topicDiversity * 100), color: .orange)
                StatTile(icon: "circle.hexagongrid.fill", label: "Topics", value: "\(profile.dominantTopics.count)", color: DSColors.accent)
                StatTile(icon: "eye.slash.fill", label: "Unused", value: "\(profile.coldZones)", color: .secondary)
            }
        }
    }

    // MARK: - Helper Views

    private var analyzeLoadingCard: some View {
        VStack(spacing: DSSpacing.lg) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing your library...")
                .font(.headline)

            Text("Detecting topics, patterns, and insights")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    private var emptyStateCard: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "books.vertical.circle")
                .scaledFont(size: 60)
                .imageScale(.large)
                .foregroundStyle(.secondary)

            Text("Add documents to visualize")
                .font(.headline)

            Text("Import files to see your knowledge atlas come alive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .fill(DSColors.surface)
        )
    }

    // MARK: - Actions

    /// The open library, and the number of documents in every library once no import runs (`AtlasContentKey`).
    private var atlasContentKey: AtlasContentKey {
        AtlasContentKey(
            containerId: containerService.activeContainerId, documentCount: ragService.documents.count,
            importing: ragService.isProcessing)
    }

    private func refreshAnalysis() async {
        let containerId = containerService.activeContainerId
        let documents = ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == containerId
            }
            return containerId == containerService.containers.first?.id
        }
        let chunks = await ragService.allChunksForActiveContainer()
        let libraryPassageCount = await ragService.passageCountForActiveContainer()
        let history = ragService.retrievalHistory.filter { $0.containerId == containerId }

        await engine.analyze(
            containerId: containerId,
            documents: documents,
            chunks: chunks,
            retrievalHistory: history,
            libraryPassageCount: libraryPassageCount
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
            // The Atlas's own 3D map (5.7). The page never shows `.embedding3D` as an expanded view, so this only
            // marked the tile.
            show3DFullscreen = true
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
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
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
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(insight.color.opacity(0.15))
                        .frame(width: DSSpacing.tapTarget, height: DSSpacing.tapTarget)

                    Image(systemName: insight.icon)
                        .scaledFont(size: 18)
                        .foregroundStyle(insight.color)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(insight.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if !insight.metrics.isEmpty {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        if let first = insight.metrics.first {
                            Text(first.value)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(DSColors.readable(insight.color))
                            Text(first.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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
        case .topicCloud: return DSColors.accent
        case .embedding3D: return DSColors.accent
        case .documentGraph: return DSColors.accent
        case .retrievalFlow: return .orange
        case .clusterView: return DSColors.accent
        case .timelineView: return .green
        case .heatmap: return .red
        case .contentBreakdown: return .secondary
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Image(systemName: viewIcon)
                        .font(.title3)
                        .foregroundStyle(viewColor)

                    Spacer()

                    if isExpanded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(view.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(view.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(isExpanded ? viewColor.opacity(0.1) : DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
    }
}

// MARK: - Visualization Subviews

struct TopicCloudView: View {
    let topics: [TopicCluster]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ForEach(topics) { topic in
                HStack(spacing: DSSpacing.md) {
                    Circle()
                        .fill(topic.color)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text(topic.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Text("\(topic.chunkCount) chunks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Keyword tags
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DSSpacing.xs) {
                                ForEach(topic.keywords, id: \.self) { keyword in
                                    Text(keyword)
                                        .font(.caption2)
                                        .padding(.horizontal, DSSpacing.sm)
                                        .padding(.vertical, DSSpacing.xs)
                                        .background(topic.color.opacity(0.15))
                                        .foregroundStyle(DSColors.readable(topic.color))
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
                .padding(DSSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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
        VStack(spacing: DSSpacing.lg) {
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
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 200)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                ForEach(sortedCategories.filter { $0.1 > 0.05 }, id: \.0) { category, percentage in
                    HStack(spacing: DSSpacing.sm) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)

                        Image(systemName: category.icon)
                            .font(.caption)
                            .foregroundStyle(category.color)

                        Text(category.rawValue)
                            .font(.caption)

                        Spacer()

                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: CGFloat(topics.count * 44))

            // Cluster quality indicator
            HStack(spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Cluster Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: DSSpacing.xs) {
                        ForEach(0 ..< 5) { i in
                            Circle()
                                .fill(i < Int(profile.clusterQuality * 5) ? Color.green : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }

                        Text(profile.clusterQuality > 0.7 ? "Excellent" : profile.clusterQuality > 0.4 ? "Good" : "Fair")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                    Text("Diversity Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.0f%%", profile.topicDiversity * 100))
                        .font(.headline)
                        .foregroundStyle(DSColors.accent)
                }
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Hot chunks list
            ForEach(hotChunks) { chunk in
                HStack(spacing: DSSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Text("\(chunk.retrievalCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(DSColors.readable(.orange))
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(chunk.documentName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(chunk.snippet)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(String(format: "%.2f", chunk.avgSimilarity))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("avg sim")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DSSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .fill(DSColors.background)
                )
            }

            // Coverage summary
            HStack(spacing: DSSpacing.xl) {
                VStack(spacing: DSSpacing.xs) {
                    Text("\(hotChunks.reduce(0) { $0 + $1.retrievalCount })")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(DSColors.readable(.orange))
                    Text("Total Hits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DSSpacing.xs) {
                    Text("\(totalChunks - coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(DSColors.readable(.green))
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: DSSpacing.xs) {
                    Text("\(coldZones)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text("Untouched")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
            )
        }
    }
}

struct DocumentRelationshipView: View {
    let documentCount: Int

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .scaledFont(size: 60)
                .imageScale(.large)
                .foregroundStyle(.secondary)

            Text("Document Connections")
                .font(.headline)

            Text("Visualizing relationships between \(documentCount) documents")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Full graph view coming soon")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, DSSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
    }
}

struct SimilarityHeatmapPreview: View {
    let chunkCount: Int

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            // Simulated heatmap grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xxs), count: 10), spacing: DSSpacing.xxs) {
                ForEach(0 ..< 100, id: \.self) { _ in
                    Rectangle()
                        .fill(heatmapColor(for: Double.random(in: 0 ... 1)))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

            Text("Similarity matrix across \(chunkCount) chunks")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Legend
            HStack(spacing: DSSpacing.xs) {
                ForEach(0 ..< 10, id: \.self) { i in
                    Rectangle()
                        .fill(heatmapColor(for: Double(i) / 10.0))
                        .frame(width: 20, height: 8)
                }
            }

            HStack {
                Text("Low")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("High Similarity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            // Age summary
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Library Age")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatAge(libraryAge))
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                    Text("Recent Additions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(additions.count)")
                        .font(.headline)
                        .foregroundStyle(DSColors.readable(.green))
                }
            }
            .padding(DSSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.background)
            )

            // Recent additions list
            if !additions.isEmpty {
                ForEach(additions) { addition in
                    HStack(spacing: DSSpacing.md) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(addition.documentName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(addition.addedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                            Text(String(format: "%.0f%%", addition.integrationScore * 100))
                                .font(.caption)
                                .foregroundStyle(DSColors.readable(addition.integrationScore > 0.6 ? .green : .orange))
                            Text("fit")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                            .fill(DSColors.background)
                    )
                }
            } else {
                Text("No recent additions in the last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(DSSpacing.lg)
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
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .scaledFont(size: 9)
                .foregroundStyle(color)

            Text(value)
                .scaledFont(size: 10, weight: .bold, design: .rounded)
                .foregroundStyle(.white)

            Text(label)
                .scaledFont(size: 8)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            Capsule()
                .fill(color.opacity(0.3))
        )
        .fixedSize() // Prevent wrapping
    }
}

struct AtlasToggleChip: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DSAnimations.snappySpring) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .scaledFont(size: 10)
                Text(label)
                    .font(.caption2)
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.1))
            )
            .foregroundStyle(isOn ? .white : .white.opacity(0.6))
        }
    }
}

struct CompactInsightCard: View {
    let insight: VisualizationInsight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: insight.icon)
                        .scaledFont(size: 16)
                        .foregroundStyle(insight.color)

                    Text(insight.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(insight.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let metric = insight.metrics.first {
                    HStack(spacing: DSSpacing.xs) {
                        Text(metric.value)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(DSColors.readable(insight.color))
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 160)
            .padding(DSSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(DSColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
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
    /// Scene or chart (`AtlasDrawingStyle`, 5.7), shared with the card.
    @AppStorage("atlasDrawingStyle") private var style: AtlasDrawingStyle = .scene
    // The scene turns from the start on Aurora, as through 5.6. The chart starts still on Midnight (5.7): a turning
    // chart redraws 30 times a second, nobody has timed a 3D chart of 6,000 passages on a phone, and on Aurora's blue
    // its blue cluster was hard to make out (robot shots, 2026-10-19). `applyStyleDefaults` sets these.
    @State private var autoRotate = false
    @State private var depthCue = true
    @State private var backgroundStyle: EmbeddingSceneBackgroundStyle = .midnight
    @State private var appliedStyleDefaults = false
    @State private var showSettings = false
    // Where the scene is and what is drawn over it, in global coordinates, for its axis labels (`sceneLabelInsets`).
    @State private var sceneFrame: CGRect = .zero
    @State private var chromeTop: CGFloat = 0
    @State private var chromeBottom: CGFloat = 0
    // The scene's own settings, as through 5.6.
    @State private var pointScale: Double = 1.0
    @State private var showLabels = true
    @State private var showLines = true
    /// The scene's names in the map: each cluster, or each library in All Libraries.
    @State private var annotations: [Embedding3DSceneView.AnnotationData] = []

    // Data state
    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var colors: [PlatformColor] = []
    @State private var sceneReloadToken = UUID()
    @State private var docLegendItems: [VizLegendItem] = [] // per-document legend
    /// The chart's angle (5.7), held here so it outlasts the chart: a reload, a turn of the screen or a resize that
    /// swaps the layout recreates the chart.
    @State private var pose: Chart3DPose = .default
    /// The library and scope the points on screen are from, so another one's load clears them rather than drawing
    /// under the new names.
    @State private var drawnScope: String?
    /// All Libraries (5.7): every library whose vectors share one embedding space, drawn together in its own colour.
    @State private var showsAllLibraries = false
    /// Libraries left out of All Libraries because another embedding model made their vectors.
    @State private var leftOutLibraries: [String] = []
    /// How many documents the drawn passages come from.
    @State private var documentsDrawn = 0
    /// What the view last loaded (`AtlasContentKey`).
    @State private var loadedKey: AtlasContentKey?
    @State private var dynamicAxisLabels: Embedding3DSceneView.AxisLabels = .placeholder

    // A guard only: the passages arrive sampled to `RAGService.visualizationPassageLimit` (6,000) since 5.7.
    private let sampleLimit = 50000

    // The 3D chart draws its own points (`AtlasChart3D`); point size and lines apply to the SceneKit scene only.
    private var sceneOptions: Embedding3DSceneView.SceneOptions {
        Embedding3DSceneView.SceneOptions(
            pointScale: style == .scene ? CGFloat(pointScale * AtlasSceneLabels.pointScale(for: points.count)) : 1,
            autoRotate: autoRotate,
            showAxes: true, // Always show axes for spatial reference
            showLines: style == .scene && showLines,
            depthCue: depthCue,
            backgroundStyle: backgroundStyle,
            projectionMethod: projectionMethod,
            axisLabels: dynamicAxisLabels
        )
    }

    var body: some View {
        ZStack {
            // Background
            backgroundGradient

            if style == .scene {
                sceneLayout
            } else {
                chartLayout
            }

            // Settings panel
            if showSettings {
                settingsPanel
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            if !appliedStyleDefaults {
                appliedStyleDefaults = true
                applyStyleDefaults()
            }
        }
        .onChange(of: style) { _, _ in applyStyleDefaults() }
        // One task keyed by the open library, the number of documents in every library once no import runs, the
        // projection and the scope (`AtlasContentKey`, 5.7), so a change cancels the load it replaces and an import that
        // ends while this is open shows in it. The key is recorded when a load finishes, and an interrupted load is
        // done again.
        .task(id: contentKey) {
            let key = contentKey
            guard !(key.onlyStartsAnImport(after: loadedKey) && !isLoading) else { return }
            if key.settlesFirst(after: loadedKey) {
                try? await Task.sleep(for: AtlasContentKey.settleDelay)
                guard !Task.isCancelled else { return }
            }
            await loadData()
            if !Task.isCancelled { loadedKey = key }
        }
    }

    /// The scene turns on Aurora and the chart stays still on Midnight, each from when it is chosen.
    private func applyStyleDefaults() {
        autoRotate = style == .scene
        backgroundStyle = style == .scene ? .aurora : .midnight
    }

    /// The scene filling the screen with the cluster list, the axis names and the hint over it, and the cluster chips
    /// and counts under it, as through 5.6. The legends sit under the top bar in the layout, so they move down as it
    /// grows with the scope picker, the note of libraries left out or a large text size, where through 5.6 they sat a
    /// fixed 70 points down (review, 2026-10-20).
    private var sceneLayout: some View {
        ZStack {
            if !points.isEmpty {
                Embedding3DSceneView(
                    points: points,
                    colors: colors,
                    options: sceneOptions,
                    reloadToken: sceneReloadToken,
                    annotations: showLabels ? annotations : [],
                    drawsScene: true,
                    labelInsets: sceneLabelInsets
                )
                .ignoresSafeArea()
                // The whole frame it draws in: what a geometry reader reports here is the frame inside the safe area, about
                // 59 points short at the top of an iPhone 15 Pro (robot shot, 2026-10-20).
                .onGeometryChange(for: CGRect.self, of: { Self.fullFrame($0) }) { sceneFrame = $0 }
            }

            VStack(spacing: 0) {
                topBar
                if isLoading && points.isEmpty {
                    Spacer()
                    loadingView
                    Spacer()
                } else if points.isEmpty {
                    Spacer()
                    emptyView
                    Spacer()
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        fullscreenTopicLegend
                        Spacer(minLength: 0)
                        axisSemanticLegend
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { chromeTop = $0 }
                    .overlay(alignment: .top) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        HStack {
                            fullscreenHintOverlay
                            Spacer()
                        }
                        bottomBar
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { chromeBottom = $0 }
                }
            }
        }
    }

    /// A view's frame in global coordinates with its safe area added back (5.7): the frame a view that ignores the safe
    /// area draws in.
    nonisolated static func fullFrame(_ proxy: GeometryProxy) -> CGRect {
        let frame = proxy.frame(in: .global)
        let insets = proxy.safeAreaInsets
        return CGRect(
            x: frame.minX - insets.leading, y: frame.minY - insets.top,
            width: frame.width + insets.leading + insets.trailing, height: frame.height + insets.top + insets.bottom)
    }

    /// What the top bar, the legends and the controls cover of the full screen's scene, which its axis labels keep clear
    /// of (5.7): on an upright phone the top 30% or so and the bottom 18%.
    private var sceneLabelInsets: AxisLabelInsets {
        guard sceneFrame.height > 0 else { return .zero }
        let top = max(chromeTop - sceneFrame.minY, 0) / sceneFrame.height
        let bottom = chromeBottom > 0 ? max(sceneFrame.maxY - chromeBottom, 0) / sceneFrame.height : 0
        return AxisLabelInsets(top: Float(min(top, 0.45)), bottom: Float(min(bottom, 0.45)))
    }

    /// The chart and its key under or beside it (5.7).
    private var chartLayout: some View {
            VStack(spacing: 0) {
                topBar
                // The chart stays on screen while it reloads (5.7), so it keeps the angle it was turned to; the spinner
                // is for a map with nothing drawn yet.
                if isLoading && points.isEmpty {
                    Spacer()
                    loadingView
                    Spacer()
                } else if points.isEmpty {
                    Spacer()
                    emptyView
                    Spacer()
                } else {
                    atlasLayout
                        .overlay(alignment: .top) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(.top, 8)
                            }
                        }
                }
            }
    }

    // MARK: - The scene's overlays (as through 5.6; Atlas canvas overlays keep fixed sizes so they fit inside the 3D scene)

    /// The clusters, or the libraries in All Libraries, with their colours and counts.
    private var fullscreenTopicLegend: some View {
        Group {
            if !docLegendItems.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(showsAllLibraries ? "Libraries" : "Clusters")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(docLegendItems.prefix(5), id: \.docId) { item in
                        HStack(spacing: DSSpacing.xs) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)

                            Text(item.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.count)")
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .padding(DSSpacing.sm)
                .frame(maxWidth: 200)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        }
    }

    /// What each axis runs between, named from the passages at its two ends (`AtlasLabeling`).
    private var axisSemanticLegend: some View {
        let labels = dynamicAxisLabels
        let hasContent = !labels.xPos.isEmpty || !labels.yPos.isEmpty || !labels.zPos.isEmpty

        return Group {
            if hasContent {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Axes")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    if !labels.xNeg.isEmpty || !labels.xPos.isEmpty {
                        axisRow(color: .red, neg: labels.xNeg, pos: labels.xPos)
                    }
                    if !labels.yNeg.isEmpty || !labels.yPos.isEmpty {
                        axisRow(color: .green, neg: labels.yNeg, pos: labels.yPos)
                    }
                    if !labels.zNeg.isEmpty || !labels.zPos.isEmpty {
                        axisRow(color: .blue, neg: labels.zNeg, pos: labels.zPos)
                    }
                }
                .padding(DSSpacing.sm)
                .frame(maxWidth: 220)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        }
    }

    /// A single axis row showing "neg ↔ pos" with the axis color
    private func axisRow(color: Color, neg: String, pos: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 6, height: 6)

            // An axis whose ends do not differ is "Component N" at both ends (5.7): named once.
            if !neg.isEmpty && !pos.isEmpty && neg != pos {
                Text("\(neg) ↔ \(pos)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            } else {
                Text(neg.isEmpty ? pos : neg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    private var fullscreenHintOverlay: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "hand.draw")
                .font(.system(size: 9))
            Text("Drag to rotate • Pinch to zoom")
                .font(.system(size: 9))
        }
        .foregroundStyle(.white.opacity(0.35))
        .padding(DSSpacing.sm)
    }

    /// The cluster chips (the libraries in All Libraries) and the counts under the scene.
    private var bottomBar: some View {
        VStack(spacing: DSSpacing.md) {
            if !docLegendItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.md) {
                        ForEach(docLegendItems, id: \.docId) { item in
                            HStack(spacing: DSSpacing.xs) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)

                                Text(item.name)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.horizontal, DSSpacing.lg)
                }
            }

            HStack(spacing: DSSpacing.xl) {
                Label("\(points.count)", systemImage: "cube.fill")
                Label("\(documentsDrawn)", systemImage: "doc.fill")
                Label("\(docLegendItems.count) \(showsAllLibraries ? "libraries" : "topics")", systemImage: "tag.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
        }
        .padding(.bottom, DSSpacing.xl)
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
        VStack(spacing: DSSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Mapping semantic space…")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            // No count: the map draws a sample of at most `RAGService.visualizationPassageLimit` passages, and
            // through 5.6 this added up every library's passages (5.7).
            Text("Projecting your passages into 3D")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var emptyView: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "cube.transparent")
                .scaledFont(size: 64)
                .imageScale(.large)
                .foregroundStyle(.white.opacity(0.3))

            Text("No documents to visualize")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            Text("Add documents to your library to see them in 3D space")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var topBar: some View {
        HStack(spacing: DSSpacing.lg) {
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
            VStack(spacing: DSSpacing.xxs) {
                Text("Semantic Atlas")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("\(projectionMethodName) • \(points.count) points")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))

                Picker("Libraries", selection: $showsAllLibraries) {
                    Text("This library").tag(false)
                    Text("All libraries").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .padding(.top, DSSpacing.xs)

                if showsAllLibraries && !leftOutLibraries.isEmpty {
                    Text("Not shown, made with another embedding model: \(leftOutLibraries.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Settings toggle
            Button {
                withAnimation(DSAnimations.snappySpring) {
                    showSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .padding(DSSpacing.sm)
                    .background(
                        Circle().fill(showSettings ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
    }

    private var projectionMethodName: String {
        switch projectionMethod {
        case .pca: return "PCA"
        case .rp: return "Random"
        case .tsne: return "t-SNE"
        case .umap: return "UMAP"
        }
    }

    // MARK: - Chart and key (5.7)

    /// The chart and its key: beside it when the screen is wider than tall, under it otherwise. Through 5.6 the scene
    /// filled the screen with the cluster list, the axis names, the hint and the topic chips laid over it; with the
    /// chart square (`AtlasChart3D`) they have room of their own and nothing covers a passage.
    private var atlasLayout: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                HStack(alignment: .center, spacing: 20) {
                    atlasChart
                        .frame(width: min(geo.size.height, geo.size.width * 0.6))
                    ScrollView {
                        atlasKeyPanel
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 14) {
                    atlasChart
                        .frame(height: min(geo.size.width - 32, geo.size.height * 0.62))
                    ScrollView {
                        atlasKeyPanel
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private var atlasChart: some View {
        Embedding3DSceneView(
            points: points,
            colors: colors,
            options: sceneOptions,
            reloadToken: sceneReloadToken,
            annotations: [],
            pose: $pose
        )
    }

    /// What the axes run between, what each colour is (a cluster, or a library in All Libraries), and the counts.
    private var atlasKeyPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                keyTitle("Axes")
                AtlasAxisKey(labels: dynamicAxisLabels)
            }

            if !docLegendItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    keyTitle(showsAllLibraries ? "Libraries" : "Clusters")
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading)],
                        alignment: .leading, spacing: 6
                    ) {
                        ForEach(docLegendItems, id: \.docId) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Text("\(item.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                Label("\(points.count) passages", systemImage: "circle.grid.3x3.fill")
                Label("\(documentsDrawn) \(documentsDrawn == 1 ? "document" : "documents")", systemImage: "doc.fill")
                // A 3D chart turns with a drag and does not zoom with a pinch (probe, iOS 27 Simulator, 2026-10-19).
                Label("Drag to turn", systemImage: "hand.draw")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DSSpacing.lg) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, DSSpacing.md)

                // Projection method
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Projection")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: DSSpacing.sm) {
                        ForEach([ProjectionMethodKind.pca, .tsne, .umap], id: \.self) { method in
                            Button {
                                projectionMethod = method
                            } label: {
                                Text(methodName(method))
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, DSSpacing.lg)
                                    .padding(.vertical, DSSpacing.sm)
                                    .background(
                                        Capsule().fill(projectionMethod == method ? Color.accentColor : Color.white.opacity(0.15))
                                    )
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                // Scene or chart (`AtlasDrawingStyle`, 5.7).
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Map")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Picker("Map", selection: $style) {
                        ForEach(AtlasDrawingStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Point size, for the scene: the chart draws its own points (`AtlasChart3D`).
                if style == .scene {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        HStack {
                            Text("Point Size")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "%.1fx", pointScale))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }

                        Slider(value: $pointScale, in: 0.5 ... 2.0, step: 0.1)
                            .tint(.accentColor)
                            .accessibilityLabel("Point size")
                    }
                }

                // Rotate turns the map; Depth fades far passages in the scene and draws the chart in perspective
                // (`chart3DCameraProjection`). Labels and Lines are the scene's: the chart names no cluster in the map.
                HStack(spacing: DSSpacing.lg) {
                    Toggle("Rotate", isOn: $autoRotate)
                    Toggle("Depth", isOn: $depthCue)
                    if style == .scene {
                        Toggle("Labels", isOn: $showLabels)
                        Toggle("Lines", isOn: $showLines)
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .font(.caption)
                .foregroundStyle(.white)

                // Background style
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Background")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: DSSpacing.sm) {
                        ForEach([EmbeddingSceneBackgroundStyle.aurora, .midnight, .parchment], id: \.self) { style in
                            Button {
                                backgroundStyle = style
                            } label: {
                                Text(styleName(style))
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.xs)
                                    .background(
                                        Capsule().fill(backgroundStyle == style ? Color.accentColor : Color.white.opacity(0.15))
                                    )
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
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
        case .cosmos: return "Cosmos"
        case .nebula: return "Nebula"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .parchment: return "Parchment"
        }
    }

    /// Topic color legend for fullscreen view
    /// Per-document legend overlay with material background
    // MARK: - Data Loading

    /// The open library, the number of documents in every library once no import runs, the projection and the scope
    /// (`AtlasContentKey`).
    private var contentKey: AtlasContentKey {
        AtlasContentKey(
            containerId: containerService.activeContainerId, documentCount: ragService.documents.count,
            importing: ragService.isProcessing, variant: "\(projectionMethod.rawValue)|\(showsAllLibraries)")
    }

    private func loadData() async {
        let (activeContainer, wantsAll) = await MainActor.run {
            (ragService.containerService.activeContainerId, showsAllLibraries)
        }
        let scope = "\(activeContainer.uuidString)|\(wantsAll)"
        await MainActor.run {
            isLoading = true
            // Another library or scope (5.7): the old map would sit under the new names until this one is drawn.
            if drawnScope != scope {
                points = []
                colors = []
                annotations = []
                docLegendItems = []
                leftOutLibraries = []
            }
        }

        // Through 5.6 this also read the corpus terms and phrases, which nothing here showed, and rebuilt the Atlas
        // page's profile from every library's documents for the topic chips, cancelling the page's own analysis. From
        // 5.7 it reads only what it draws, so All Libraries holds at most `visualizationPassageLimit` passages.

        // This library, or every library in one embedding space (5.7).
        var libraries: [KnowledgeContainer] = []
        var libraryOfChunk: [UUID: Int] = [:]
        var leftOut: [String] = []
        let sampledChunks: [DocumentChunk]
        if wantsAll {
            let (included, excluded) = await ragService.atlasSamplesForAllLibraries()
            libraries = included.map(\.library)
            leftOut = excluded.map(\.name)
            var joined: [DocumentChunk] = []
            for (index, sample) in included.enumerated() {
                for chunk in sample.chunks { libraryOfChunk[chunk.id] = index }
                joined += sample.chunks
            }
            sampledChunks = joined
        } else {
            sampledChunks = sampleChunks(await ragService.allChunksForActiveContainer())
        }

        guard !sampledChunks.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        let embeddings = sampledChunks.map { $0.embedding }

        guard !embeddings.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        // Project to 3D — use deterministic seed (not .hashValue which is randomized per launch)
        let seed = deterministicSeed(from: containerService.activeContainerId.uuidString)
        // Off the main actor: UMAP and t-SNE take seconds on a few thousand passages (`ProjectionService`).
        let method = projectionMethod
        let coords3D = await Task.detached(priority: .userInitiated) {
            ProjectionService.shared.project3D(embeddings: embeddings, method: method, seed: seed)
        }.value

        // === CLUSTER MEMBERSHIP & NAMING ===
        // Cluster membership derives deterministically from embeddings via k-means.
        // Cluster names derive solely from the words of the passages in the cluster.
        let texts = sampledChunks.map { $0.content }
        // Splitting 6,000 passages into words and clustering their vectors is seconds of work on
        // a phone, so it is done off the main actor; only the results come back to it.
        // The axes' words are read here too (5.7): they were six passes over the sample on the main actor.
        // What each passage belongs to (5.7): its document, its library in All Libraries, and its section heading, so
        // an axis end or a cluster is named for the part of the library it is (`AtlasLabeling.PassageSources`). All
        // Libraries names documents from every library's records (`OIDocumentEntityQuery.loadDocumentRecords`).
        let documentNames = await MainActor.run {
            Dictionary(
                (wantsAll ? OIDocumentEntityQuery.loadDocumentRecords() : ragService.documents)
                    .map { ($0.id, AtlasLabeling.shortDocumentName($0.filename)) },
                uniquingKeysWith: { first, _ in first })
        }
        let sources = AtlasLabeling.PassageSources(
            groups: sampledChunks.map { documentNames[$0.documentId] },
            sections: sampledChunks.map(\.metadata.sectionTitle),
            libraries: wantsAll ? sampledChunks.map { chunk in libraryOfChunk[chunk.id].map { libraries[$0].name } } : [])
        let (clusterIndices, clusterNames, axisEnds) = await Task.detached(priority: .userInitiated) {
            // The word classes of the passages' languages first (5.7), so an adverb names nothing in them.
            await AtlasLabeling.loadWordClasses(for: texts)
            let terms = texts.map { AtlasLabeling.terms(in: $0) }
            let indices = AtlasLabeling.kMeans(embeddings: embeddings)
            let names = AtlasLabeling.clusterNames(
                texts: texts,
                clusterMembership: indices,
                precomputedTerms: terms,
                sources: sources
            )
            return (
                indices, names,
                AtlasLabeling.axisLabels(coords: coords3D, texts: texts, passageTerms: terms, sources: sources)
            )
        }.value

        let palette: [PlatformColor] = [
            PlatformColor(.blue),
            PlatformColor(.purple),
            PlatformColor(.green),
            PlatformColor(.orange),
            PlatformColor(.pink),
            PlatformColor(.teal)
        ]

        var mappedColors: [PlatformColor] = []
        mappedColors.reserveCapacity(sampledChunks.count)

        for i in sampledChunks.indices {
            let c = (i < clusterIndices.count && clusterIndices[i] >= 0 && clusterIndices[i] < clusterNames.count) ? clusterIndices[i] : 0
            mappedColors.append(palette[c % palette.count])
        }

        // Build legend items matching clusters
        var clusterCounts = Array(repeating: 0, count: clusterNames.count)
        for c in clusterIndices {
            if c >= 0 && c < clusterCounts.count {
                clusterCounts[c] += 1
            }
        }

        var clusterLegend: [VizLegendItem] = []
        for c in 0..<clusterNames.count {
            let count = clusterCounts[c]
            guard count > 0 else { continue }
            clusterLegend.append(VizLegendItem(
                docId: UUID(),
                name: clusterNames[c],
                color: Color(palette[c % palette.count]),
                count: count
            ))
        }

        // All Libraries: each point in its library's own colour, and the legend lists the libraries (5.7).
        if wantsAll {
            let libraryColors = Self.distinctLibraryColors(libraries.map(\.colorHex), palette: palette)
            mappedColors = sampledChunks.map { libraryColors[libraryOfChunk[$0.id] ?? 0] }
            var counts = Array(repeating: 0, count: libraries.count)
            for chunk in sampledChunks { counts[libraryOfChunk[chunk.id] ?? 0] += 1 }
            clusterLegend = libraries.enumerated().compactMap { index, library in
                counts[index] > 0
                    ? VizLegendItem(docId: library.id, name: library.name, color: Color(libraryColors[index]), count: counts[index])
                    : nil
            }
        }

        // Scale points properly for viewing
        let scaledPoints = scaleCoordinatesForViewing(coords3D)

        // Each end of each axis named by the words of the passages there (5.7).
        let axisLabels = Embedding3DSceneView.AxisLabels(ends: axisEnds)

        // The scene's names in the map: each cluster, or in All Libraries each library, at the middle of its points.
        let sceneAnnotations: [Embedding3DSceneView.AnnotationData]
        if wantsAll {
            let libraryColors = Self.distinctLibraryColors(libraries.map(\.colorHex), palette: palette)
            sceneAnnotations = AtlasSceneLabels.annotations(
                coords: coords3D, groups: sampledChunks.map { libraryOfChunk[$0.id] ?? 0 },
                names: libraries.map(\.name), colors: libraryColors,
                detailLevel: { $0 > 20 ? 2 : ($0 > 5 ? 1 : 0) })
        } else {
            sceneAnnotations = AtlasSceneLabels.annotations(
                coords: coords3D, groups: clusterIndices, names: clusterNames, colors: palette,
                detailLevel: { $0 > 20 ? 2 : ($0 > 5 ? 1 : 0) })
        }

        let drawnDocuments = Set(sampledChunks.map(\.documentId)).count

        // A load for another method, library or scope started while this one worked: that one draws, not this.
        guard !Task.isCancelled, method == projectionMethod,
            activeContainer == ragService.containerService.activeContainerId,
            wantsAll == showsAllLibraries
        else { return }

        await MainActor.run {
            points = scaledPoints
            colors = mappedColors
            annotations = sceneAnnotations
            docLegendItems = clusterLegend
            leftOutLibraries = leftOut
            dynamicAxisLabels = axisLabels
            documentsDrawn = drawnDocuments
            drawnScope = scope
            sceneReloadToken = UUID()
            isLoading = false
        }
    }

    /// A colour for each library on the All Libraries map (5.7), in order: its own, unless a library before it has one
    /// that close; then the free palette colour farthest from those used, so neighbours on the map contrast (indigo
    /// next to blue read as one in a robot shot, 2026-10-19); then further hues a golden angle apart. Every library
    /// starts with the same colour (`ContainerService.defaultContainer`, `#4F46E5`), so repeats are the common case.
    static func distinctLibraryColors(_ hexes: [String], palette: [PlatformColor]) -> [PlatformColor] {
        var used: [SIMD3<Double>] = []
        func nearest(_ color: PlatformColor) -> Double {
            let rgb = Self.rgb(of: color)
            return used.map { abs($0.x - rgb.x) + abs($0.y - rgb.y) + abs($0.z - rgb.z) }.min() ?? .infinity
        }
        func isTaken(_ color: PlatformColor) -> Bool { nearest(color) < 0.15 }
        func take(_ color: PlatformColor) -> PlatformColor {
            used.append(Self.rgb(of: color))
            return color
        }
        var hue = 0.0
        return hexes.map { hex in
            if let own = Color(hex: hex).map({ PlatformColor($0) }), !isTaken(own) { return take(own) }
            if let free = palette.filter({ !isTaken($0) }).max(by: { nearest($0) < nearest($1) }) { return take(free) }
            var candidate = PlatformColor(hue: 0, saturation: 0.65, brightness: 0.95, alpha: 1)
            for _ in 0..<64 {
                hue = (hue + 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1)
                candidate = PlatformColor(hue: CGFloat(hue), saturation: 0.65, brightness: 0.95, alpha: 1)
                if !isTaken(candidate) { break }
            }
            return take(candidate)
        }
    }

    /// A colour's red, green and blue from 0 to 1, in sRGB.
    static func rgb(of color: PlatformColor) -> SIMD3<Double> {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
            (color.usingColorSpace(.sRGB) ?? color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return SIMD3(Double(red), Double(green), Double(blue))
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

        // Fill ~90% of the 5-unit axis range for a full, professional atlas look
        let targetSize: Float = 4.5
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
    let autoRotate: Bool
    let depthCue: Bool
    let backgroundStyle: EmbeddingSceneBackgroundStyle
    /// Scene or chart (`AtlasDrawingStyle`, 5.7), and the scene's own two settings.
    let style: AtlasDrawingStyle
    let pointScale: Double
    let showLabels: Bool

    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var colors: [PlatformColor] = []
    @State private var sceneReloadToken = UUID()
    /// The chart's angle (5.7), held here so it outlasts the chart while the card reloads.
    @State private var pose: Chart3DPose = .default
    /// The library the points on screen are from, so another library's load clears them rather than drawing under
    /// its name.
    @State private var drawnLibrary: UUID?
    /// What the card last loaded (`AtlasContentKey`).
    @State private var loadedKey: AtlasContentKey?

    // Dynamic axis labels derived from content analysis
    @State private var dynamicAxisLabels: Embedding3DSceneView.AxisLabels = .placeholder
    /// The scene's cluster names in the map, and the box of cluster names over its corner (the Scene style).
    @State private var annotations: [Embedding3DSceneView.AnnotationData] = []
    @State private var legendItems: [TopicColorItem] = []
    // Where the scene is and where the cluster box and hint over it start, for its axis labels (`cardLabelInsets`).
    @State private var cardSceneFrame: CGRect = .zero
    @State private var cardChromeTop: CGFloat = 0

    // A guard only: the passages arrive sampled to `RAGService.visualizationPassageLimit` (6,000) since 5.7.
    private let sampleLimit = 50000

    // The 3D chart draws its own points (`AtlasChart3D`); point size applies to the SceneKit scene only.
    private var sceneOptions: Embedding3DSceneView.SceneOptions {
        Embedding3DSceneView.SceneOptions(
            pointScale: style == .scene ? CGFloat(pointScale * AtlasSceneLabels.pointScale(for: points.count)) : 1,
            autoRotate: autoRotate,
            showAxes: true, // Always show axes for spatial reference
            showLines: true,
            depthCue: depthCue,
            backgroundStyle: backgroundStyle,
            projectionMethod: projectionMethod,
            axisLabels: dynamicAxisLabels
        )
    }

    var body: some View {
        ZStack {
            // The chart stays on screen while it reloads (5.7), so it keeps the angle it was turned to.
            if isLoading && points.isEmpty {
                loadingPlaceholder
            } else if points.isEmpty {
                emptyPlaceholder
            } else {
                sceneContent
                    .overlay(alignment: .topTrailing) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .padding(10)
                        }
                    }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        // One task keyed by the open library, the number of documents in every library once no import runs, and the
        // projection (`AtlasContentKey`, 5.7). Through 5.6 there were two, one per key, so both loaded when the card
        // appeared, and an import that ended with the card on screen never showed in it. The key is recorded when a
        // load finishes, and an interrupted load is done again.
        .task(id: contentKey) {
            let key = contentKey
            guard !(key.onlyStartsAnImport(after: loadedKey) && !isLoading) else { return }
            if key.settlesFirst(after: loadedKey) {
                try? await Task.sleep(for: AtlasContentKey.settleDelay)
                guard !Task.isCancelled else { return }
            }
            await loadAndProject()
            if !Task.isCancelled { loadedKey = key }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.7))

            Text("Mapping semantic space…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
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
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "cube.transparent")
                .scaledFont(size: 36)
                .foregroundStyle(.white.opacity(0.4))

            Text("Add documents to visualize")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
    }

    /// The scene with its labels, the box of cluster names and the hint over its lower corner, as through 5.6; or the
    /// chart and under it what its axes run between (5.7), with the chips under the card naming the clusters.
    @ViewBuilder
    private var sceneContent: some View {
        if style == .scene {
            ZStack(alignment: .bottomLeading) {
                Embedding3DSceneView(
                    points: points,
                    colors: colors,
                    options: sceneOptions,
                    reloadToken: sceneReloadToken,
                    annotations: showLabels ? annotations : [],
                    drawsScene: true,
                    labelInsets: cardLabelInsets
                )
                .onGeometryChange(for: CGRect.self, of: { Fullscreen3DAtlasView.fullFrame($0) }) { cardSceneFrame = $0 }

                VStack(alignment: .leading, spacing: 0) {
                    topicLegendOverlay
                    sceneHintOverlay
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { cardChromeTop = $0 }
            }
        } else {
            chartContent
        }
    }

    /// What the cluster box and the hint cover of the card's scene, along its bottom, which its axis labels keep clear
    /// of (5.7).
    private var cardLabelInsets: AxisLabelInsets {
        guard cardSceneFrame.height > 0, cardChromeTop > 0 else { return .zero }
        let bottom = max(cardSceneFrame.maxY - cardChromeTop, 0) / cardSceneFrame.height
        return AxisLabelInsets(bottom: Float(min(bottom, 0.45)))
    }

    /// Shows what each color represents (Atlas canvas overlay keeps fixed sizes so it fits inside the compact 3D scene)
    private var topicLegendOverlay: some View {
        Group {
            if !legendItems.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(legendItems.prefix(5), id: \.name) { item in
                        HStack(spacing: DSSpacing.xs) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 6, height: 6)

                            Text(item.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(DSSpacing.xs)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }
        }
    }

    private struct TopicColorItem: Hashable {
        let name: String
        let color: Color
        let count: Int
    }

    /// Small overlay explaining what the user is looking at (Atlas canvas overlay keeps fixed sizes)
    private var sceneHintOverlay: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "hand.draw")
                .font(.system(size: 8))
            Text("Drag to rotate • Pinch to zoom")
                .font(.system(size: 8))
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(DSSpacing.xs)
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Embedding3DSceneView(
                points: points,
                colors: colors,
                options: sceneOptions,
                reloadToken: sceneReloadToken,
                annotations: [],
                pose: $pose
            )
            AtlasAxisKey(labels: dynamicAxisLabels, lineLimit: 1)
                .padding(.horizontal, DSSpacing.sm)
            // A 3D chart turns with a drag and does not zoom with a pinch (probe, iOS 27 Simulator, 2026-10-19).
            Label("Drag to turn", systemImage: "hand.draw")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)
        }
    }

    // MARK: - Data Loading

    /// The open library, the number of documents in every library once no import runs, and the projection
    /// (`AtlasContentKey`).
    private var contentKey: AtlasContentKey {
        AtlasContentKey(
            containerId: containerService.activeContainerId, documentCount: ragService.documents.count,
            importing: ragService.isProcessing, variant: projectionMethod.rawValue)
    }

    private func loadAndProject() async {
        // Through 5.6 this also read the corpus terms and phrases, which nothing on the card showed (5.7).
        let activeId = containerService.activeContainerId
        await MainActor.run {
            isLoading = true
            // Another library (5.7): the old map would sit under the new library's name until this one is drawn.
            if drawnLibrary != activeId {
                points = []
                colors = []
                annotations = []
                legendItems = []
            }
        }

        let allChunks = await ragService.allChunksForActiveContainer()

        guard !allChunks.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        // Sample chunks (stratified by document)
        let sampledChunks = sampleChunks(allChunks)
        let embeddings = sampledChunks.map { $0.embedding }

        guard !embeddings.isEmpty else {
            // Not when another load has taken this one's place (5.7): it draws, and these writes would leave its view
            // empty, or skip its reload during an import.
            guard !Task.isCancelled else { return }
            await MainActor.run {
                points = []
                colors = []
                isLoading = false
            }
            return
        }

        // Project to 3D — use deterministic seed (not .hashValue which is randomized per launch)
        let seed = deterministicSeed(from: containerService.activeContainerId.uuidString)
        // Off the main actor: UMAP and t-SNE take seconds on a few thousand passages (`ProjectionService`).
        let method = projectionMethod
        let coords3D = await Task.detached(priority: .userInitiated) {
            ProjectionService.shared.project3D(embeddings: embeddings, method: method, seed: seed)
        }.value

        // === CLUSTER MEMBERSHIP & NAMING ===
        // Cluster membership derives deterministically from embeddings via k-means.
        // Cluster names derive solely from the words of the passages in the cluster.
        let texts = sampledChunks.map { $0.content }
        // Splitting 6,000 passages into words and clustering their vectors is seconds of work on
        // a phone, so it is done off the main actor; only the results come back to it.
        // The axes' words are read here too (5.7): they were six passes over the sample on the main actor.
        // What each passage belongs to (5.7): its document and its section heading, so an axis end or a cluster is named
        // for the part of the library it is (`AtlasLabeling.PassageSources`).
        let documentNames = await MainActor.run {
            Dictionary(
                ragService.documents.map { ($0.id, AtlasLabeling.shortDocumentName($0.filename)) },
                uniquingKeysWith: { first, _ in first })
        }
        let sources = AtlasLabeling.PassageSources(
            groups: sampledChunks.map { documentNames[$0.documentId] },
            sections: sampledChunks.map(\.metadata.sectionTitle))
        let (clusterIndices, clusterNames, axisEnds) = await Task.detached(priority: .userInitiated) {
            // The word classes of the passages' languages first (5.7), so an adverb names nothing in them.
            await AtlasLabeling.loadWordClasses(for: texts)
            let terms = texts.map { AtlasLabeling.terms(in: $0) }
            let indices = AtlasLabeling.kMeans(embeddings: embeddings)
            let names = AtlasLabeling.clusterNames(
                texts: texts,
                clusterMembership: indices,
                precomputedTerms: terms,
                sources: sources
            )
            return (
                indices, names,
                AtlasLabeling.axisLabels(coords: coords3D, texts: texts, passageTerms: terms, sources: sources)
            )
        }.value

        let palette: [PlatformColor] = [
            PlatformColor(.blue),
            PlatformColor(.purple),
            PlatformColor(.green),
            PlatformColor(.orange),
            PlatformColor(.pink),
            PlatformColor(.teal)
        ]

        var mappedColors: [PlatformColor] = []
        mappedColors.reserveCapacity(sampledChunks.count)

        for i in sampledChunks.indices {
            let c = (i < clusterIndices.count && clusterIndices[i] >= 0 && clusterIndices[i] < clusterNames.count) ? clusterIndices[i] : 0
            mappedColors.append(palette[c % palette.count])
        }

        // Use ACTUAL PCA/UMAP coordinates - scale them properly for viewing
        // This preserves natural clustering and semantic structure!
        let scaledPoints = scalePointsForViewing(coords3D)

        // The scene's cluster names in the map and its box of names (the Scene style). The chart shows neither: the
        // chips under the card name the clusters (`atlasTopicLegend`).
        let clusterAnnotations = AtlasSceneLabels.annotations(
            coords: coords3D, groups: clusterIndices, names: clusterNames, colors: palette,
            detailLevel: { $0 > 50 ? 2 : ($0 > 20 ? 1 : 0) })
        var clusterCounts = Array(repeating: 0, count: clusterNames.count)
        for c in clusterIndices where c >= 0 && c < clusterCounts.count { clusterCounts[c] += 1 }
        let clusterLegend: [TopicColorItem] = clusterNames.indices.compactMap { c in
            clusterCounts[c] > 0
                ? TopicColorItem(name: clusterNames[c], color: Color(palette[c % palette.count]), count: clusterCounts[c])
                : nil
        }

        // Each end of each axis named by the words of the passages there (5.7).
        let axisLabels = Embedding3DSceneView.AxisLabels(ends: axisEnds)

        // A load for another method or library started while this one worked: that one draws, not this.
        // `.task(id: contentKey)` cancels this one when its key changes.
        guard !Task.isCancelled, activeId == containerService.activeContainerId else { return }

        await MainActor.run {
            points = scaledPoints
            colors = mappedColors
            annotations = clusterAnnotations
            legendItems = clusterLegend
            dynamicAxisLabels = axisLabels
            drawnLibrary = activeId
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
        let targetSize: Float = 4.5
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

        let seed = deterministicSeed(from: containerService.activeContainerId.uuidString)
        var prng = VizLCG(seed: seed)

        let sortedDocIds = byDoc.keys.sorted { $0.uuidString < $1.uuidString }
        for docId in sortedDocIds {
            guard let docChunks = byDoc[docId] else { continue }
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

#Preview {
    AdaptiveVisualizationsView()
        .environmentObject(RAGService())
        .environmentObject(ContainerService())
}
