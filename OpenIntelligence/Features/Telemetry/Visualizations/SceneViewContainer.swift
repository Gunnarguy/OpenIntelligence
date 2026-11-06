//
//  SceneViewContainer.swift
//  OpenIntelligence
//
//  Moved from Embedding3DView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import SwiftUI
import Charts
import Spatial
#if canImport(SceneKit)
import SceneKit
import QuartzCore
#if canImport(UIKit)
struct SceneViewContainer: UIViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: Embedding3DSceneView.SceneOptions
    let reloadToken: UUID
    let annotations: [Embedding3DSceneView.AnnotationData]

    // Callback for when a point is tapped
    var onPointTapped: ((Int, SCNVector3) -> Void)?
    /// What the views over the scene cover, which the axis labels keep clear of (5.7).
    var labelInsets = AxisLabelInsets.zero

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view, coordinator: context.coordinator)

        // Add tap gesture for point inspection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        context.coordinator.scnView = view
        context.coordinator.onPointTapped = onPointTapped

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        configure(uiView, coordinator: context.coordinator)
        context.coordinator.onPointTapped = onPointTapped
    }

    private func configure(_ view: SCNView, coordinator: Coordinator) {
        installScene(in: view, built: &coordinator.builtKey)
        coordinator.labelInsets = labelInsets
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.05 // Throttle to 20fps for performance
        weak var scnView: SCNView?
        var onPointTapped: ((Int, SCNVector3) -> Void)?
        /// What the scene on screen was built from (`SceneBuildKey`).
        var builtKey: SceneBuildKey?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)

            // Perform hit test
            let hitResults = view.hitTest(location, options: [
                // Every hit, nearest first: an axis label drawn over the cloud (5.7) would otherwise be the only one.
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .boundingBoxOnly: false
            ])

            // Find the first hit that's a point node
            for result in hitResults {
                if let nodeName = result.node.name, nodeName.hasPrefix("point_") {
                    // Extract point index from name "point_123"
                    let indexStr = nodeName.dropFirst(6) // Remove "point_"
                    if let index = Int(indexStr) {
                        let position = result.node.position
                        onPointTapped?(index, position)
                        return
                    }
                }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Throttle updates for performance
            guard time - lastUpdateTime > updateInterval else { return }
            lastUpdateTime = time

            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        /// The map's labels, found once for each scene: walking every node 20 times a second visits each of up to
        /// 6,000 points (5.7).
        private weak var labelledScene: SCNScene?
        private var labelNodes: [SCNNode] = []
        private var axisPins: [AxisLabelPin] = []

        /// The share of the view at each edge that the axis labels keep clear of (`AxisLabelInsets`).
        var labelInsets = AxisLabelInsets.zero

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            if labelledScene !== scene {
                labelNodes = mapLabelNodes(in: scene)
                axisPins = axisLabelPins(in: scene)
                labelledScene = scene
            }
            sizeLabelsForScreen(labelNodes, pointOfView: camera)
        }

        /// Every frame, once the map's turning is applied: the field of view across the narrower side, and each axis
        /// label on its end or at the edge of the view (5.7). Six labels, so this is cheap enough for every frame.
        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            guard let scene = renderer.scene, labelledScene === scene, let camera = renderer.pointOfView else { return }
            let viewport = renderer.currentViewport
            guard viewport.width > 0, viewport.height > 0 else { return }
            let aspect = Float(viewport.width / viewport.height)
            fitProjection(of: camera, aspect: aspect)
            keepAxisLabelsInView(axisPins, pointOfView: camera, aspect: aspect, insets: labelInsets)
        }
    }
}
#else
struct SceneViewContainer: NSViewRepresentable {
    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: Embedding3DSceneView.SceneOptions
    let reloadToken: UUID
    let annotations: [Embedding3DSceneView.AnnotationData]

    // Callback for when a point is tapped (optional for macOS)
    var onPointTapped: ((Int, SCNVector3) -> Void)?
    /// What the views over the scene cover, which the axis labels keep clear of (5.7).
    var labelInsets = AxisLabelInsets.zero

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.delegate = context.coordinator
        configure(view, coordinator: context.coordinator)

        // Add click gesture for point inspection
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(clickGesture)
        context.coordinator.scnView = view
        context.coordinator.onPointTapped = onPointTapped

        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        configure(nsView, coordinator: context.coordinator)
        context.coordinator.onPointTapped = onPointTapped
    }

    private func configure(_ view: SCNView, coordinator: Coordinator) {
        installScene(in: view, built: &coordinator.builtKey)
        coordinator.labelInsets = labelInsets
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        private var lastUpdateTime: TimeInterval = 0
        private let updateInterval: TimeInterval = 0.05 // Throttle to 20fps for performance
        weak var scnView: SCNView?
        var onPointTapped: ((Int, SCNVector3) -> Void)?
        /// What the scene on screen was built from (`SceneBuildKey`).
        var builtKey: SceneBuildKey?

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = scnView else { return }
            let location = gesture.location(in: view)

            // Perform hit test
            let hitResults = view.hitTest(location, options: [
                // Every hit, nearest first: an axis label drawn over the cloud (5.7) would otherwise be the only one.
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .boundingBoxOnly: false
            ])

            // Find the first hit that's a point node
            for result in hitResults {
                if let nodeName = result.node.name, nodeName.hasPrefix("point_") {
                    let indexStr = nodeName.dropFirst(6)
                    if let index = Int(indexStr) {
                        let position = result.node.position
                        onPointTapped?(index, position)
                        return
                    }
                }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Throttle updates for performance
            guard time - lastUpdateTime > updateInterval else { return }
            lastUpdateTime = time

            guard let scene = renderer.scene else { return }
            updateLabelLOD(scene: scene, pointOfView: renderer.pointOfView)
        }

        /// The map's labels, found once for each scene: walking every node 20 times a second visits each of up to
        /// 6,000 points (5.7).
        private weak var labelledScene: SCNScene?
        private var labelNodes: [SCNNode] = []
        private var axisPins: [AxisLabelPin] = []

        /// The share of the view at each edge that the axis labels keep clear of (`AxisLabelInsets`).
        var labelInsets = AxisLabelInsets.zero

        private func updateLabelLOD(scene: SCNScene, pointOfView: SCNNode?) {
            guard let camera = pointOfView else { return }
            if labelledScene !== scene {
                labelNodes = mapLabelNodes(in: scene)
                axisPins = axisLabelPins(in: scene)
                labelledScene = scene
            }
            sizeLabelsForScreen(labelNodes, pointOfView: camera)
        }

        /// Every frame, once the map's turning is applied: the field of view across the narrower side, and each axis
        /// label on its end or at the edge of the view (5.7). Six labels, so this is cheap enough for every frame.
        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            guard let scene = renderer.scene, labelledScene === scene, let camera = renderer.pointOfView else { return }
            let viewport = renderer.currentViewport
            guard viewport.width > 0, viewport.height > 0 else { return }
            let aspect = Float(viewport.width / viewport.height)
            fitProjection(of: camera, aspect: aspect)
            keepAxisLabelsInView(axisPins, pointOfView: camera, aspect: aspect, insets: labelInsets)
        }
    }
}
#endif

/// What a SceneKit map was built from (5.7). SwiftUI calls a representable's update for every change around it (the
/// explorer's search field, its HUD, an import's progress), and through 5.6 each call built the whole scene again, up to
/// 6,000 nodes, and put the camera back where it starts. The scene is built again only when this changes.
struct SceneBuildKey: Equatable {
    let reloadToken: UUID
    let pointCount: Int
    /// A sum over every point, so a different set of the same size (another document filter) still counts as changed.
    let pointChecksum: Double
    let colorCount: Int
    let annotationCount: Int
    let options: String

    init(
        reloadToken: UUID, points: [SCNVector3], colorCount: Int, annotationCount: Int,
        options: Embedding3DSceneView.SceneOptions
    ) {
        self.reloadToken = reloadToken
        self.pointCount = points.count
        var sum = 0.0
        for (index, point) in points.enumerated() {
            sum += (Double(point.x) + 2 * Double(point.y) + 3 * Double(point.z)) * Double(index % 7 + 1)
        }
        self.pointChecksum = sum
        self.colorCount = colorCount
        self.annotationCount = annotationCount
        self.options = String(describing: options)
    }
}

extension SceneViewContainer {
    /// Puts the scene on `view` when what it shows has changed since `built` (`SceneBuildKey`). A new scene starts
    /// from its own camera, as through 5.6, which is what the explorer's Reset relies on.
    func installScene(in view: SCNView, built: inout SceneBuildKey?) {
        let key = SceneBuildKey(
            reloadToken: reloadToken, points: points, colorCount: colors.count, annotationCount: annotations.count,
            options: options)
        guard key != built else { return }
        view.scene = buildScene(points: points, colors: colors, options: options, annotations: annotations)
        built = key
    }
}
#endif
