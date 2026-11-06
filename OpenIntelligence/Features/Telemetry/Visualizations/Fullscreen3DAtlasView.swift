//
//  Fullscreen3DAtlasView.swift
//  OpenIntelligence
//
//  Moved unchanged from AdaptiveVisualizationsView.swift on 2026-11-05 (5.8 split).
//

import Charts
import SceneKit
import SwiftUI
import TipKit

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
                .tour(.allLibraries, in: Tour.atlas, when: TourContext.libraries >= 2)
                .onChange(of: showsAllLibraries) { _, _ in Tour.used(.allLibraries) }
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
        AtlasLabeling.recordLabels(
            view: "fullscreen", scope: wantsAll ? "all" : "library", library: activeContainer, passages: texts.count,
            clusterNames: clusterNames, axisEnds: axisEnds)

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
