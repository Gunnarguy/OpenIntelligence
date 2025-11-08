//  Embedding3DView.swift
//  OpenIntelligence
//
//  Lightweight 3D scatter for document embeddings (Apple-style scaffolding)
//  - Projects 512-d embeddings to 3D using PCA (approx) or RP via ProjectionService
//  - Colors points by source document (per active container)
//  - SceneKit-based viewer with orbit control and default lighting
//  - Deterministic stratified downsampling with caching and per-file filters
//
//  NOTE: This is an integration scaffold. Swap ProjectionService backend with Apple's
//  Embedding Atlas or true UMAP/t-SNE later without changing UI.

import SwiftUI

#if canImport(SceneKit)
import SceneKit

#if canImport(UIKit)
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

// MARK: - Public Renderer (used from VisualizationsView.EmbeddingSpaceView)

struct EmbeddingSpaceRenderer: View {
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    
    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    
    @State private var isLoading = true
    @State private var points: [SCNVector3] = []
    @State private var pointColorsUI: [PlatformColor] = []
    struct VizLegendItem: Identifiable {
        let docId: UUID
        let name: String
        let color: Color
        let count: Int
        var id: UUID { docId }
    }
    @State private var legendItems: [VizLegendItem] = []
    @State private var errorText: String? = nil
    
    // Deterministic per-container controls and state
    @State private var sampleLimit: Int = 2000
    @State private var allDocIdsForPoints: [UUID] = [] // aligned with points/colors
    @State private var totalPoints: Int = 0
    @State private var selectedDocFilters: Set<UUID> = [] // empty = select all by default
    @State private var loadTask: Task<Void, Never>? = nil
    
    // Default: 1K/2K/5K
    private let sampleOptions = [1000, 2000, 5000]
    
    var body: some View {
        VStack(spacing: 12) {
            if let err = errorText {
                errorBanner(err)
            }
            contentBody
        }
        // Reload when container/method/sample changes
        .task(id: containerService.activeContainerId) {
            loadSampleLimitForActive()
            await loadAndProject()
        }
        .task(id: projectionMethod) {
            await loadAndProject()
        }
        .task(id: sampleLimit) {
            await loadAndProject()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
    
        // MARK: - Subview builders (split to help the type-checker)
    
    private func errorBanner(_ err: String) -> some View {
        Text(err)
            .font(.caption)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var contentBody: some View {
        if isLoading {
            loadingCard
        } else if points.isEmpty {
            emptyStateCard
        } else {
            samplingControls
            sceneSection
            legendSection
        }
    }
    
    private var loadingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: 12) {
                ProgressView("Preparing 3D embedding space…")
                Text("Downsampling and projecting to 3D")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(height: 340)
    }
    
    private var emptyStateCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            VStack(spacing: 8) {
                Text("No embeddings available for the active container")
                    .font(.subheadline)
                Text("Add documents or switch libraries to see the 3D map")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(height: 340)
    }
    
    private var samplingControls: some View {
        HStack(spacing: 8) {
            Text("Points:")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(sampleOptions, id: \.self) { opt in
                Button {
                    if sampleLimit != opt {
                        sampleLimit = opt
                        saveSampleLimit(opt)
                    }
                } label: {
                    Text(opt >= 1000 ? "\(opt/1000)K" : "\(opt)")
                        .font(.caption2)
                        .fontWeight(sampleLimit == opt ? .semibold : .regular)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(sampleLimit == opt ? Color.blue.opacity(0.12) : DSColors.surface)
                        .foregroundColor(sampleLimit == opt ? .blue : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            InfoButtonView(
                title: "Point Sampling",
                explanation: "To maintain performance, the 3D view shows a random sample of the total embedding points. Higher counts provide more detail but may be slower on older devices."
            )
        }
        .padding(.horizontal)
    }
    
    private var sceneSection: some View {
        let (fPoints, fColors) = filteredArrays()
        return Embedding3DSceneView(points: fPoints, colors: fColors)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
    
    @ViewBuilder
    private var legendSection: some View {
        if !legendItems.isEmpty {
            HStack {
                LegendChipsView(
                    items: legendItems,
                    selectedDocFilters: $selectedDocFilters,
                    totalPoints: totalPoints
                )
                InfoButtonView(
                    title: "Document Legend",
                    explanation: "Each color represents a different document in the active library. The numbers show how many points from that document are included in the current sample, and the percentage of the total points they represent. Tap a document to toggle it on or off in the 3D view."
                )
                .padding(.trailing)
            }
        }
    }
    
    // Extracted legend chips to reduce type-checking complexity
    struct LegendChipsView: View {
        let items: [EmbeddingSpaceRenderer.VizLegendItem]
        @Binding var selectedDocFilters: Set<UUID>
        let totalPoints: Int
        
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        LegendChip(
                            item: item,
                            selected: selectedDocFilters.isEmpty || selectedDocFilters.contains(item.docId),
                            totalPoints: totalPoints
                        )
                        .onTapGesture {
                            toggle(item.docId)
                        }
                    }
                }
                .padding(.leading)
            }
        }
        
        private func toggle(_ id: UUID) {
            if selectedDocFilters.isEmpty {
                selectedDocFilters = Set(items.map { $0.docId })
            }
            if selectedDocFilters.contains(id) {
                selectedDocFilters.remove(id)
            } else {
                selectedDocFilters.insert(id)
            }
            if selectedDocFilters.isEmpty {
                // keep empty to mean "all"
            }
        }
    }
    
    struct LegendChip: View {
        let item: EmbeddingSpaceRenderer.VizLegendItem
        let selected: Bool
        let totalPoints: Int
        
        private var pctStr: String {
            totalPoints > 0
                ? String(format: "%.0f%%", (Double(item.count) / Double(totalPoints)) * 100.0)
                : "0%"
        }
        
        var body: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text("\(item.name) • \(item.count) • \(pctStr)")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(DSColors.surface.opacity(selected ? 0.9 : 0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
    }
    
// MARK: - Filtering
    
    private func filteredArrays() -> ([SCNVector3], [PlatformColor]) {
        guard !points.isEmpty else { return ([], []) }
        // If no explicit filters, return all
        if selectedDocFilters.isEmpty {
            return (points, pointColorsUI)
        }
        var fp: [SCNVector3] = []
        var fc: [PlatformColor] = []
        fp.reserveCapacity(points.count)
        fc.reserveCapacity(pointColorsUI.count)
        for i in 0..<points.count {
            if i < allDocIdsForPoints.count, selectedDocFilters.contains(allDocIdsForPoints[i]) {
                fp.append(points[i])
                fc.append(pointColorsUI[i])
            }
        }
        return (fp, fc)
    }
    
    // MARK: - Data + Projection
    
    private func loadAndProject() async {
        // Cancel any ongoing load
        loadTask?.cancel()
        loadTask = Task {
            await MainActor.run {
                isLoading = true
                errorText = nil
            }
            
            // Snapshot documents to resolve names and filter by active container
            let docsSnapshot = await MainActor.run { ragService.documents }
            let activeId = containerService.activeContainerId
            let defaultId = containerService.containers.first?.id
            let activeDocs = docsSnapshot.filter { doc in
                if let cid = doc.containerId {
                    return cid == activeId
                } else {
                    // Legacy docs (no containerId) belong to the default container (first in list)
                    return activeId == defaultId
                }
            }
            let activeDocIdsSet = Set(activeDocs.map { $0.id })
            let nameById: [UUID: String] = Dictionary(uniqueKeysWithValues: activeDocs.map { ($0.id, $0.filename) })
            
            // Pull chunks from the active container's vector DB
            let allChunks = await ragService.allChunksForActiveContainer()
            if Task.isCancelled { return }
            guard !allChunks.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                }
                return
            }
            // Filter chunks to documents visible in current container snapshot (defensive)
            let filtered = allChunks.filter { activeDocIdsSet.contains($0.documentId) }
            if Task.isCancelled { return }
            guard !filtered.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                }
                return
            }
            
            // Group by document for stratified downsampling
            var chunksByDoc: [UUID: [DocumentChunk]] = [:]
            for c in filtered {
                chunksByDoc[c.documentId, default: []].append(c)
            }
            
            // Allocate fair share of sampleLimit across docs
            let docIds = Array(chunksByDoc.keys)
            let perDocQuota = max(1, sampleLimit / max(docIds.count, 1))
            var sampledEmbeddings: [[Float]] = []
            var sampledDocIds: [UUID] = []
            sampledEmbeddings.reserveCapacity(min(sampleLimit, filtered.count))
            sampledDocIds.reserveCapacity(min(sampleLimit, filtered.count))
            
            // Deterministic sampling per containerId
            let rngSeed = UInt64(abs(Int64(activeId.uuidString.hashValue)))
            var prng = VizLCG(seed: rngSeed)
            
            for did in docIds {
                let arr = chunksByDoc[did] ?? []
                if arr.count > perDocQuota {
                    var indices = Array(0..<arr.count)
                    // shuffle deterministically
                    for i in stride(from: indices.count - 1, through: 1, by: -1) {
                        let j = Int(prng.next() % UInt64(i + 1))
                        if i != j { indices.swapAt(i, j) }
                    }
                    for idx in indices.prefix(perDocQuota) {
                        sampledEmbeddings.append(arr[idx].embedding)
                        sampledDocIds.append(did)
                    }
                } else {
                    for c in arr {
                        sampledEmbeddings.append(c.embedding)
                        sampledDocIds.append(did)
                    }
                }
            }
            // Global cap if above sampleLimit
            if sampledEmbeddings.count > sampleLimit {
                var order = Array(0..<sampledEmbeddings.count)
                for i in stride(from: order.count - 1, through: 1, by: -1) {
                    let j = Int(prng.next() % UInt64(i + 1))
                    if i != j { order.swapAt(i, j) }
                }
                order = Array(order.prefix(sampleLimit))
                var newEmb: [[Float]] = []
                var newIds: [UUID] = []
                newEmb.reserveCapacity(order.count)
                newIds.reserveCapacity(order.count)
                for idx in order {
                    newEmb.append(sampledEmbeddings[idx])
                    newIds.append(sampledDocIds[idx])
                }
                sampledEmbeddings = newEmb
                sampledDocIds = newIds
            }
            
            // Validate dims
            sampledEmbeddings = sampledEmbeddings.filter { !$0.isEmpty }
            if Task.isCancelled { return }
            guard !sampledEmbeddings.isEmpty else {
                await MainActor.run {
                    self.points = []
                    self.pointColorsUI = []
                    self.legendItems = []
                    self.allDocIdsForPoints = []
                    self.totalPoints = 0
                    self.isLoading = false
                }
                return
            }
            
            // Projection & caching
            let methodKind: ProjectionMethodKind = (projectionMethod == .pca) ? .pca : .rp
            let cacheKey = ProjectionCacheKey(
                containerId: activeId,
                method: methodKind.rawValue,
                sampleLimit: sampleLimit,
                seed: rngSeed
            )
            
            var coords3D: [SIMD3<Float>]
            if let cached = ProjectionCache.shared.get(cacheKey),
               cached.coords.count == sampledEmbeddings.count {
                coords3D = cached.coords
            } else {
                coords3D = ProjectionService.shared.project3D(
                    embeddings: sampledEmbeddings,
                    method: methodKind,
                    seed: rngSeed
                )
                // Build counts per doc for legend and cache
                var perDocCounts: [UUID: Int] = [:]
                for did in sampledDocIds {
                    perDocCounts[did, default: 0] += 1
                }
                let entry = ProjectionCacheEntry(
                    coords: coords3D,
                    docIds: sampledDocIds,
                    totalPoints: coords3D.count,
                    perDocCounts: perDocCounts,
                    timestamp: Date()
                )
                ProjectionCache.shared.set(entry, for: cacheKey)
            }
            if Task.isCancelled { return }
            
            // Color mapping per document (deterministic by sorted doc ids)
            let palette = ColorPalette.makePalette(count: docIds.count)
            var colorByDoc: [UUID: PlatformColor] = [:]
            let sortedDocIds = docIds.sorted { $0.uuidString < $1.uuidString }
            for (i, did) in sortedDocIds.enumerated() {
                let pcol = palette[i % palette.count]
                colorByDoc[did] = pcol
            }
            
            // Legend build with counts
            var counts: [UUID: Int] = [:]
            for did in sampledDocIds { counts[did, default: 0] += 1 }
            var legend: [VizLegendItem] = []
            for did in sortedDocIds {
                let uiColor = colorByDoc[did] ?? ColorPalette.fallback
                let swiftUIColor = Color(uiColor)
                let name = nameById[did] ?? "Unknown"
                let cnt = counts[did] ?? 0
                legend.append(VizLegendItem(docId: did, name: name, color: swiftUIColor, count: cnt))
            }
            
            // Build SceneKit vectors and color list aligned
            let scnPoints: [SCNVector3] = coords3D.map { SCNVector3($0.x, $0.y, $0.z) }
            let uiColors: [PlatformColor] = sampledDocIds.map { colorByDoc[$0] ?? ColorPalette.fallback }
            
            await MainActor.run {
                self.points = scnPoints
                self.pointColorsUI = uiColors
                self.legendItems = legend
                self.allDocIdsForPoints = sampledDocIds
                self.totalPoints = scnPoints.count
                // Default: if no filters yet, treat as "all" selected by keeping set empty
                self.isLoading = false
            }
        }
    }
    
    // MARK: - SampleLimit persistence
    
    private func saveSampleLimit(_ value: Int) {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        UserDefaults.standard.setValue(value, forKey: key)
    }
    
    private func loadSampleLimitForActive() {
        let key = "viz.sampleLimit.\(containerService.activeContainerId.uuidString)"
        if let v = UserDefaults.standard.value(forKey: key) as? Int, sampleOptions.contains(v) {
            sampleLimit = v
        } else {
            sampleLimit = 2000
        }
    }
}

// MARK: - SceneKit SwiftUI Wrapper

struct Embedding3DSceneView: View {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    
    var body: some View {
        SceneViewContainer(points: points, colors: colors)
            .background(DSColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#if canImport(UIKit)
struct SceneViewContainer: UIViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = buildScene(points: points, colors: colors)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = buildScene(points: points, colors: colors)
    }
}
#else
struct SceneViewContainer: NSViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = buildScene(points: points, colors: colors)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        return view
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = buildScene(points: points, colors: colors)
    }
}
#endif

// MARK: - Scene construction

private func buildScene(points: [SCNVector3], colors: [PlatformColor]) -> SCNScene {
    let scene = SCNScene()
    
    // Camera
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.position = SCNVector3(0, 0, 3.2)
    cameraNode.camera?.zNear = 0.01
    cameraNode.camera?.zFar = 100
    scene.rootNode.addChildNode(cameraNode)
    
    // Axes (subtle)
    let axesNode = SCNNode()
    #if canImport(UIKit)
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemRed, axis: .x))
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemGreen, axis: .y))
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemBlue, axis: .z))
    #else
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemRed, axis: .x))
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemGreen, axis: .y))
    axesNode.addChildNode(axisNode(length: 1.6, color: .systemBlue, axis: .z))
    #endif
    axesNode.opacity = 0.2
    scene.rootNode.addChildNode(axesNode)
    
    // Points
    let count = min(points.count, colors.count)
    if count > 0 {
        let radius: CGFloat = 0.015
        for i in 0..<count {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 8
            let mat = SCNMaterial()
            mat.diffuse.contents = colors[i]
            mat.lightingModel = .phong
            sphere.materials = [mat]
            
            let node = SCNNode(geometry: sphere)
            node.position = points[i]
            scene.rootNode.addChildNode(node)
        }
    }
    
    // Light
    let light = SCNLight()
    light.type = .omni
    light.intensity = 800
    let lightNode = SCNNode()
    lightNode.light = light
    lightNode.position = SCNVector3(1.2, 1.2, 2.0)
    scene.rootNode.addChildNode(lightNode)
    
    // Ambient
    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 200
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)
    
    return scene
}

private enum AxisDirection { case x, y, z }

#if canImport(UIKit)
private func axisNode(length: CGFloat, color: UIColor, axis: AxisDirection) -> SCNNode {
    let cyl = SCNCylinder(radius: 0.0025, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(length/2, 0, 0)
    case .y:
        node.position = SCNVector3(0, length/2, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, length/2)
    }
    return node
}
#else
private func axisNode(length: CGFloat, color: NSColor, axis: AxisDirection) -> SCNNode {
    let cyl = SCNCylinder(radius: 0.0025, height: length)
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    cyl.materials = [mat]
    let node = SCNNode(geometry: cyl)
    switch axis {
    case .x:
        node.eulerAngles = SCNVector3(0, 0, Float.pi/2)
        node.position = SCNVector3(length/2, 0, 0)
    case .y:
        node.position = SCNVector3(0, length/2, 0)
    case .z:
        node.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.position = SCNVector3(0, 0, length/2)
    }
    return node
}
#endif

// MARK: - Color Palette

enum ColorPalette {
    static let fallback: PlatformColor = {
        #if canImport(UIKit)
        return UIColor.systemGray
        #else
        return NSColor.systemGray
        #endif
    }()
    
    static func makePalette(count: Int) -> [PlatformColor] {
        let base = 12
        let n = max(count, base)
        var colors: [PlatformColor] = []
        colors.reserveCapacity(n)
        for i in 0..<n {
            let hue = CGFloat(i) / CGFloat(n)
            #if canImport(UIKit)
            colors.append(UIColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1.0))
            #else
            colors.append(NSColor(calibratedHue: hue, saturation: 0.75, brightness: 0.95, alpha: 1.0))
            #endif
        }
        return colors
    }
}

#else

// Fallback when SceneKit is not available on this platform (e.g., visionOS without SceneKit).
// Provides a graceful placeholder so VisualizationsView compiles across all supported platforms.
struct EmbeddingSpaceRenderer: View {
    let projectionMethod: EmbeddingSpaceView.ProjectionMethod
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(DSColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("3D embedding visualization requires SceneKit")
                        .font(.subheadline)
                    Text("This platform does not support SceneKit. A compatible renderer (RealityKit) can be added.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .frame(height: 340)
        }
    }
}

#endif
