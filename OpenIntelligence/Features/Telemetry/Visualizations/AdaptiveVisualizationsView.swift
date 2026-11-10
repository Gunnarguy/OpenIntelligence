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
                Tour.used(.atlasSettings)
                withAnimation(DSAnimations.snappySpring) {
                    showAtlasSettings.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .tour(.atlasSettings, in: Tour.atlas)
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
                        // "7 minutes ago", not a clock that ticks every second (5.8).
                        Text(lastAnalyzed.formatted(.relative(presentation: .named)))
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
                            Tour.used(.insights)
                            handleInsightTap(insight)
                        }
                        .tour(.insights, in: Tour.atlas, when: insight.id == engine.insights.first?.id)
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
            TopicCloudView(topics: profile.dominantTopics, profile: profile)
        case .contentBreakdown:
            ContentBreakdownView(contentMix: profile.contentMix, chunkCount: profile.chunkCount)
        case .embedding3D:
            EmbeddingSpaceView(
                chunkCount: profile.chunkCount,
                documentCount: profile.documentCount,
                // The library's own vector size; a fixed 512 described a model the default libraries don't use (5.7).
                embeddingDimension: activeContainer?.embeddingDim ?? 384
            )
        case .retrievalFlow:
            RetrievalFlowView(hotChunks: profile.hotChunks, coldZones: profile.coldZones, totalChunks: profile.chunkCount)
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
        let history = ragService.retrievalHistory.filter { $0.containerId == containerId }
        // The library, its documents and its question history are everything the profile is built from (5.8,
        // `LibraryVisualizationEngine.analyzedInputs`), so a visit with all three unchanged keeps the profile.
        // The history is capped (`retrievalHistoryLimit`), so its newest entry, not its count, says it changed.
        let inputs = AnyHashable([AnyHashable(atlasContentKey), AnyHashable(history.count), AnyHashable(history.last?.id)])
        guard !engine.hasProfile(builtFrom: inputs) else { return }
        let documents = ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == containerId
            }
            return containerId == containerService.containers.first?.id
        }
        let chunks = await ragService.allChunksForActiveContainer()
        let libraryPassageCount = await ragService.passageCountForActiveContainer()
        // Leaving the Atlas cancels this task, and nothing checked it between the reads and the analysis (5.8): on
        // his iPhone on 2026-11-05 a 3 s visit started a 61.5 s analysis of 6,000 passages while a Deep Think answer
        // ran, with Chat the selected tab.
        guard !Task.isCancelled else { return }

        await engine.analyze(
            containerId: containerId,
            documents: documents,
            chunks: chunks,
            retrievalHistory: history,
            libraryPassageCount: libraryPassageCount,
            inputs: inputs
        )
    }

    private func handleInsightTap(_ insight: VisualizationInsight) {
        switch insight.action {
        case .showTopicMap:
            expandedView = .topicCloud
        case .showRetrievalChart:
            expandedView = .retrievalFlow
        case .showEmbedding3D:
            // The Atlas's own 3D map (5.7). The page never shows `.embedding3D` as an expanded view, so this only
            // marked the tile.
            show3DFullscreen = true
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






#Preview {
    AdaptiveVisualizationsView()
        .environmentObject(RAGService())
        .environmentObject(ContainerService())
}
