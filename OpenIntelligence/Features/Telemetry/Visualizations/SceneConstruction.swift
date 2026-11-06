//
//  SceneConstruction.swift
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
// MARK: - Label size

/// The distance at which a map label is drawn at its own size: where the camera started through 5.6, |(3.5, 2.5, 6.0)|.
/// `sizeLabelsForScreen` scales each label from it, so labels keep the size on screen they had then.
nonisolated let startingCameraDistance: Float = 7.38

/// Where the camera starts: where it started through 5.6 (back on 2026-10-20). From 2026-10-19 it started about 23 from
/// the middle (22.9, fitted so each axis label's centre stayed within 70% of the half-width at any angle in a view at least
/// 0.6 as wide as tall), and the cloud drew at about a third of its 5.6 size under labels kept at their 5.6 size; the owner
/// wanted the 5.6 map back. Axis labels are kept in view by `keepAxisLabelsInView` instead.
nonisolated let mapCameraPosition = SIMD3<Float>(3.5, 2.5, 6.0)

/// How far the camera starts from the middle of the map, about 7.38.
nonisolated let mapCameraDistance: Float = simd_length(mapCameraPosition)

/// The map's words: the labels at the ends of its axes and the clusters' labels (5.7).
nonisolated func mapLabelNodes(in scene: SCNScene) -> [SCNNode] {
    scene.rootNode.childNodes { node, _ in
        (node.name?.hasPrefix("axisLabel") ?? false) || (node.name?.hasPrefix("clusterLabel_") ?? false)
    }
}

/// Keeps every label of the map one size on screen however near or far it is (5.7), 20 times a second (the scene's
/// update is throttled to that). Each was drawn at one size in the scene, so on the owner's iPhone an axis end near the
/// camera read in letters about four times the height of the one at the far end of the same axis (2026-10-16). The
/// scale grows with the label's depth along the view and with the camera's field of view, and is 1 at the distance
/// the camera starts from, between 0.35 and 4; a cluster's label is drawn half as large again, as at that distance
/// before, and fades a little with depth.
///
/// It reads the positions as drawn: a spinning map turns its content with an animation, which moves only the
/// presentation nodes (SCNNode.h, `presentationNode`: "with any active animations applied"), so a model position
/// stands still while the map turns. And it uses the depth along the view, not the straight-line distance: a label
/// off to the side of the screen is no smaller on it for being further along the diagonal.
nonisolated func sizeLabelsForScreen(_ labels: [SCNNode], pointOfView: SCNNode) {
    let view = pointOfView.presentation
    let camera = view.simdWorldPosition
    let front = view.simdWorldFront
    let fieldOfView = Float(pointOfView.camera?.fieldOfView ?? 60)
    // A cluster's label fades by how far behind the middle of the map it is, so the fade is the same from any distance.
    let middle = viewDepth(of: .zero, camera: camera, front: front)
    for label in labels {
        let depth = viewDepth(of: label.presentation.simdWorldPosition, camera: camera, front: front)
        let scale = screenScale(depth: depth, fieldOfView: fieldOfView)
        if label.name?.hasPrefix("clusterLabel_") ?? false {
            label.simdScale = SIMD3(repeating: scale * 1.5)
            let behind = depth - middle
            label.opacity = behind < -3.4 ? 0.95 : behind < 1.6 ? 0.88 : 0.75
        } else {
            // An axis label is kept on screen (`keepAxisLabelsInView`) even when its end is near the camera, where the
            // 0.35 floor would draw it larger than the others (review, 2026-10-20).
            label.simdScale = SIMD3(repeating: screenScale(depth: depth, fieldOfView: fieldOfView, minimum: 0.02))
        }
    }
}

/// How far in front of the camera a point is, along the way it looks: the depth a perspective view divides by, never
/// under 0.05.
nonisolated func viewDepth(of position: SIMD3<Float>, camera: SIMD3<Float>, front: SIMD3<Float>) -> Float {
    max(simd_dot(position - camera, front), 0.05)
}

/// The scale that keeps a label one size on screen at `depth` with a field of view of `fieldOfView` degrees: 1 at the
/// distance the camera starts from and the default 60 degrees, between `minimum` (0.35 unless given) and 4.
nonisolated func screenScale(depth: Float, fieldOfView: Float, minimum: Float = 0.35) -> Float {
    let viewFactor = tan(fieldOfView * .pi / 360) / tan(Float.pi / 6)
    return min(max(depth * viewFactor / startingCameraDistance, minimum), 4)
}

// MARK: - Axis labels kept in view

/// An axis end's label and the point it names (5.7). The label hangs under the scene's root, so the map's turning
/// never moves it; `anchor` sits at the axis end inside the map, and turns with it.
nonisolated struct AxisLabelPin {
    let label: SCNNode
    let anchor: SCNNode
    /// Half the text's width and height, in the label's own units, before `sizeLabelsForScreen` scales it.
    let halfWidth: Float
    let halfHeight: Float
}

/// Moves each axis label of `axes` under `root`, at its place, with an empty node named "axisAnchor_<n>" left at that
/// place in the map, and names the label "axisLabel_<n>" to match. The map turns its content node, so the anchors turn
/// with it and the labels do not, and `keepAxisLabelsInView` puts each label back on its anchor every frame.
nonisolated func pinAxisLabels(of axes: SCNNode, to root: SCNNode) {
    let labels = axes.childNodes.filter { $0.name == "axisLabel" }
    for (index, label) in labels.enumerated() {
        let anchor = SCNNode()
        anchor.name = "axisAnchor_\(index)"
        anchor.position = label.position
        axes.addChildNode(anchor)
        label.removeFromParentNode()
        label.name = "axisLabel_\(index)"
        root.addChildNode(label)
    }
}

/// The scene's pinned axis labels with their anchors, found once for each scene.
nonisolated func axisLabelPins(in scene: SCNScene) -> [AxisLabelPin] {
    var anchors: [String: SCNNode] = [:]
    var labels: [(key: String, node: SCNNode)] = []
    scene.rootNode.enumerateHierarchy { node, _ in
        guard let name = node.name else { return }
        if name.hasPrefix("axisAnchor_") {
            anchors[String(name.dropFirst("axisAnchor_".count))] = node
        } else if name.hasPrefix("axisLabel_") {
            labels.append((String(name.dropFirst("axisLabel_".count)), node))
        }
    }
    return labels.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }.compactMap { key, label in
        guard let anchor = anchors[key], let text = label.childNodes.first?.geometry else { return nil }
        let (low, high) = text.boundingBox
        return AxisLabelPin(
            label: label, anchor: anchor, halfWidth: Float(high.x - low.x) / 2, halfHeight: Float(high.y - low.y) / 2)
    }
}

/// The share of the view at each edge that a label keeps clear of (5.7): the top bar, the legends and the controls
/// drawn over the scene. Top and bottom are shares of the view's height, leading and trailing of its width.
nonisolated struct AxisLabelInsets: Equatable, Sendable {
    var top: Float = 0
    var bottom: Float = 0
    var leading: Float = 0
    var trailing: Float = 0
    /// Boxes drawn over the scene that don't span its width, in the view's units (-1 to 1 across and up), which a
    /// label keeps clear of only where it would cover one (5.8). The card's cluster box sits at the lower left; as a
    /// `bottom` band it held every label above its top across the whole card, so the far end of an upright axis had
    /// its name partway along the line (the owner, 2026-11-03).
    var boxes: [AxisLabelPlacement] = []

    static let zero = AxisLabelInsets()
}

/// The tangents of half the view's width and height as the camera sees them: a field of view of `fieldOfView` degrees
/// across the height (SceneKit's default projection direction) or, when `horizontal`, across the width, in a view
/// `aspect` wide for each unit high.
nonisolated func viewHalfAngles(fieldOfView: Float, aspect: Float, horizontal: Bool) -> SIMD2<Float> {
    let half = tan(fieldOfView * .pi / 360)
    return horizontal ? SIMD2(half, half / aspect) : SIMD2(half * aspect, half)
}

/// Where a point is drawn on the view, -1 to 1 across and up, and how deep it is along the view, for a camera at
/// `camera` (its world transform; a SceneKit camera looks down its -z) with the view's half-angle tangents `halfAngles`.
nonisolated func viewPoint(
    of world: SIMD3<Float>, camera: simd_float4x4, halfAngles: SIMD2<Float>
) -> (point: SIMD2<Float>, depth: Float) {
    let local = simd_inverse(camera) * SIMD4<Float>(world, 1)
    let depth = -local.z
    return (SIMD2(local.x, local.y) / (halfAngles * max(depth, 0.0001)), depth)
}

/// The world position drawn at `point` on the view at `depth`: the inverse of `viewPoint`.
nonisolated func worldPoint(
    at point: SIMD2<Float>, depth: Float, camera: simd_float4x4, halfAngles: SIMD2<Float>
) -> SIMD3<Float> {
    let local = point * halfAngles * depth
    let world = camera * SIMD4<Float>(local.x, local.y, -depth, 1)
    return SIMD3(world.x, world.y, world.z)
}

/// Sets the camera's field of view to run across the narrower side of the view (5.7): across the width on a screen
/// taller than wide, across the height otherwise. Through 5.6 it always ran across the height, so on an upright phone the
/// map in the full screen was wider than the screen and an axis's name could take most of its width.
nonisolated func fitProjection(of pointOfView: SCNNode, aspect: Float) {
    guard let camera = pointOfView.camera else { return }
    let direction: SCNCameraProjectionDirection = aspect < 1 ? .horizontal : .vertical
    if camera.projectionDirection != direction { camera.projectionDirection = direction }
}

/// Puts each axis label on its axis end as the map is drawn now, or, when that end is out of the part of the view
/// `insets` leave clear, at the edge of that part nearest it, so every axis keeps its names on screen at any angle (5.7).
/// Through 5.6 a label went off the screen with its end, and an axis lying across the view had both its names outside
/// it. A label that would cover one already placed steps toward the middle of the clear part by its height. Called for
/// every frame after the map's turning is applied (`renderer(_:didApplyAnimationsAtTime:)`), so a label moves with its
/// end. `margin` is the share of the clear part's half-width and half-height kept free at its edge. A label whose end
/// is behind the camera is hidden.
nonisolated func keepAxisLabelsInView(
    _ pins: [AxisLabelPin], pointOfView: SCNNode, aspect: Float, insets: AxisLabelInsets = .zero, margin: Float = 0.04
) {
    guard let camera = pointOfView.camera, !pins.isEmpty else { return }
    let transform = pointOfView.presentation.simdWorldTransform
    let halfAngles = viewHalfAngles(
        fieldOfView: Float(camera.fieldOfView), aspect: aspect, horizontal: camera.projectionDirection == .horizontal)
    let region = AxisLabelRegion(insets: insets, margin: margin)
    var placed: [AxisLabelPlacement] = []
    for pin in pins {
        let (wanted, depth) = viewPoint(
            of: pin.anchor.presentation.simdWorldPosition, camera: transform, halfAngles: halfAngles)
        guard depth > 0.1 else {
            pin.label.isHidden = true
            continue
        }
        pin.label.isHidden = false
        // Drawn no deeper than where the fog starts: SceneKit fogs every material (no switch for one in the iOS 27 SDK),
        // and a blue name at the far end of the blue axis faded into the blue background (robot shots, 2026-10-20).
        // A label is drawn over everything and sized for the screen by its depth (`sizeLabelsForScreen`), so the depth
        // it is drawn at changes nothing else.
        let drawDepth = min(depth, max(mapCameraDistance - 1, 0.2))
        let scale = pin.label.simdScale.x
        let size = SIMD2<Float>(pin.halfWidth, pin.halfHeight) * scale / (halfAngles * drawDepth)
        let spot = axisLabelSpot(wanted: wanted, halfSize: size, region: region, placed: placed, boxes: insets.boxes)
        placed.append(AxisLabelPlacement(center: spot, halfSize: size))
        pin.label.simdWorldPosition = worldPoint(at: spot, depth: drawDepth, camera: transform, halfAngles: halfAngles)
    }
}

/// The part of the view a label may be drawn in, -1 to 1 across and up: the view less `insets`, less `margin` of
/// what is left at each side.
nonisolated struct AxisLabelRegion: Equatable {
    let minimum: SIMD2<Float>
    let maximum: SIMD2<Float>

    init(insets: AxisLabelInsets, margin: Float) {
        let low = SIMD2<Float>(-1 + 2 * insets.leading, -1 + 2 * insets.bottom)
        let high = SIMD2<Float>(1 - 2 * insets.trailing, 1 - 2 * insets.top)
        let inset = (high - low) * margin / 2
        minimum = low + inset
        maximum = high - inset
    }
}

/// A label placed on the view, in its own units: -1 to 1 across and up.
nonisolated struct AxisLabelPlacement: Equatable, Sendable {
    let center: SIMD2<Float>
    let halfSize: SIMD2<Float>

    func overlaps(_ other: AxisLabelPlacement) -> Bool {
        abs(center.x - other.center.x) < halfSize.x + other.halfSize.x
            && abs(center.y - other.center.y) < halfSize.y + other.halfSize.y
    }
}

/// Where a label of `halfSize` goes on the view (-1 to 1 across and up) to name the point at `wanted`: there, moved in
/// until all of it is inside `region`, then, where it would cover one of `boxes`, moved up or down to clear it on the
/// side with room, then stepped toward the middle of the region by its height while it covers one in `placed`, at
/// most six times. A label wider or taller than the region is centred across it.
nonisolated func axisLabelSpot(
    wanted: SIMD2<Float>, halfSize: SIMD2<Float>, region: AxisLabelRegion, placed: [AxisLabelPlacement],
    boxes: [AxisLabelPlacement] = []
) -> SIMD2<Float> {
    let middle = (region.minimum + region.maximum) / 2
    var low = region.minimum + halfSize
    var high = region.maximum - halfSize
    for axis in 0..<2 where low[axis] > high[axis] {
        low[axis] = middle[axis]
        high[axis] = middle[axis]
    }
    var spot = simd_clamp(wanted, low, high)
    for box in boxes where box.overlaps(AxisLabelPlacement(center: spot, halfSize: halfSize)) {
        let above = box.center.y + box.halfSize.y + halfSize.y
        let below = box.center.y - box.halfSize.y - halfSize.y
        spot.y = above <= high.y || below < low.y ? min(above, high.y) : below
    }
    var steps = 0
    while steps < 6, placed.contains(where: { $0.overlaps(AxisLabelPlacement(center: spot, halfSize: halfSize)) }) {
        spot.y += (spot.y > middle.y ? -2.2 : 2.2) * halfSize.y
        spot.y = min(max(spot.y, low.y), high.y)
        steps += 1
    }
    return spot
}

// MARK: - Scene construction

func buildScene(points: [SCNVector3], colors: [PlatformColor], options: Embedding3DSceneView.SceneOptions, annotations: [Embedding3DSceneView.AnnotationData]) -> SCNScene {
    let scene = SCNScene()
    scene.rootNode.addChildNode(makeCameraNode(depthCue: options.depthCue))

    let contentRoot = SCNNode()
    contentRoot.name = "contentRoot"
    scene.rootNode.addChildNode(contentRoot)

    // Always add a subtle ground plane and grid for spatial reference
    contentRoot.addChildNode(makeGroundPlane())

    // Add intuitive axes with human-readable labels
    if options.showAxes {
        let axes = makeIntuiveAxesNode(axisLabels: options.axisLabels)
        contentRoot.addChildNode(axes)
        pinAxisLabels(of: axes, to: scene.rootNode)
    }

    addPointNodes(points, colors, scale: options.pointScale, depthCue: options.depthCue, into: contentRoot)
    addClusterLabels(annotations, backgroundStyle: options.backgroundStyle, into: contentRoot)
    if options.showLines {
        addInterClusterLines(annotations, backgroundStyle: options.backgroundStyle, into: contentRoot)
    }
    addLighting(into: scene.rootNode, depthCue: options.depthCue)
    applyBackground(style: options.backgroundStyle, to: scene)
    applyAutoRotate(options.autoRotate, to: contentRoot)

    if options.depthCue {
        // From just in front of the middle of the map to past the far axis labels, and light enough that a label on
        // the far side still reads: SceneKit fogs every material, with no switch for one (SCNMaterial.h, iOS 27 SDK).
        // Through 5.6 it ran from 5 to 12 with the camera 7.38 away, so the far half of the map and its labels sank
        // into the fog.
        scene.fogStartDistance = CGFloat(mapCameraDistance - 1)
        scene.fogEndDistance = CGFloat(mapCameraDistance + 9)
        scene.fogDensityExponent = 1.0
        scene.fogColor = options.backgroundStyle.fogColor.withAlphaComponent(0.55)
    } else {
        scene.fogStartDistance = 0
        scene.fogEndDistance = 0
    }

    return scene
}

// MARK: - Ground Plane (Spatial Reference)

private func makeGroundPlane() -> SCNNode {
    let container = SCNNode()

    // Subtle grid floor - sized to match full axis extent (6.0)
    // OPTIMIZATION: Fewer grid lines for better performance
    let gridSize: Float = 6.0
    let gridLines = 6 // Reduced from 12
    let spacing = gridSize / Float(gridLines)

    // Share geometry for all grid lines
    let lineGeo = SCNCylinder(radius: 0.004, height: CGFloat(gridSize))
    let lineMat = SCNMaterial()
    #if canImport(UIKit)
        lineMat.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
    #else
        lineMat.diffuse.contents = NSColor.white.withAlphaComponent(0.08)
    #endif
    lineMat.lightingModel = .constant
    lineGeo.materials = [lineMat]

    for i in 0 ... gridLines {
        let offset = -gridSize / 2 + Float(i) * spacing

        // X-axis lines (share geometry)
        let xNode = SCNNode(geometry: lineGeo)
        xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        xNode.position = SCNVector3(0, -3.0, offset)
        container.addChildNode(xNode)

        // Z-axis lines (share geometry)
        let zNode = SCNNode(geometry: lineGeo)
        zNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        zNode.position = SCNVector3(offset, -3.0, 0)
        container.addChildNode(zNode)
    }

    return container
}

// MARK: - Clean Arrow Axes (visible, no text clutter)

private func makeIntuiveAxesNode(axisLabels: Embedding3DSceneView.AxisLabels) -> SCNNode {
    let node = SCNNode()

    // Bright axis colors
    #if canImport(UIKit)
    let xColor = UIColor.systemRed
    let yColor = UIColor.systemGreen
    let zColor = UIColor.systemBlue
    #else
    let xColor = NSColor.systemRed
    let yColor = NSColor.systemGreen
    let zColor = NSColor.systemBlue
    #endif

    // Create arrow axes - 5 units in each direction from origin
    let axisHalfLength: Float = 5.0

    // X axis (red) - horizontal
    node.addChildNode(makeArrowAxis(from: SCNVector3(-axisHalfLength, 0, 0),
                                    to: SCNVector3(axisHalfLength, 0, 0),
                                    color: xColor))

    // Y axis (green) - vertical
    node.addChildNode(makeArrowAxis(from: SCNVector3(0, -axisHalfLength, 0),
                                    to: SCNVector3(0, axisHalfLength, 0),
                                    color: yColor))

    // Z axis (blue) - depth
    node.addChildNode(makeArrowAxis(from: SCNVector3(0, 0, -axisHalfLength),
                                    to: SCNVector3(0, 0, axisHalfLength),
                                    color: zColor))

    // Origin sphere
    node.addChildNode(makeOriginMarker())

    // === DYNAMIC CONTENT-DERIVED AXIS LABELS ===
    // Each end of each axis is named by the words of the passages at that end (`AtlasLabeling.axisLabels`), so once the
    // map has loaded every end has a label (5.7). While it loads, the positive ends read X, Y and Z.

    let xPosText = axisLabels.xPos.isEmpty ? "X" : axisLabels.xPos
    let yPosText = axisLabels.yPos.isEmpty ? "Y" : axisLabels.yPos
    let zPosText = axisLabels.zPos.isEmpty ? "Z" : axisLabels.zPos

    // Add text labels at the positive end of each axis
    node.addChildNode(makeAxisLabel(text: xPosText,
                                    position: SCNVector3(axisHalfLength + 0.4, 0, 0),
                                    color: xColor))
    node.addChildNode(makeAxisLabel(text: yPosText,
                                    position: SCNVector3(0, axisHalfLength + 0.4, 0),
                                    color: yColor))
    node.addChildNode(makeAxisLabel(text: zPosText,
                                    position: SCNVector3(0, 0, axisHalfLength + 0.4),
                                    color: zColor))

    // Add labels at the negative end of each axis (if we have content-derived labels)
    if !axisLabels.xNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.xNeg,
                                        position: SCNVector3(-axisHalfLength - 0.4, 0, 0),
                                        color: xColor))
    }
    if !axisLabels.yNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.yNeg,
                                        position: SCNVector3(0, -axisHalfLength - 0.4, 0),
                                        color: yColor))
    }
    if !axisLabels.zNeg.isEmpty {
        node.addChildNode(makeAxisLabel(text: axisLabels.zNeg,
                                        position: SCNVector3(0, 0, -axisHalfLength - 0.4),
                                        color: zColor))
    }

    // The hint that sat under the origin ("← themes from content →") went in 5.7: it was drawn over the middle of
    // the points, where the cluster labels are, and its words said less than the labels do.

    return node
}

/// Creates a floating label for an axis endpoint
private func makeAxisLabel(text: String, position: SCNVector3, color: PlatformColor) -> SCNNode {
    let textGeo = SCNText(string: text, extrusionDepth: 0.02)

    #if canImport(UIKit)
    textGeo.font = UIFont.systemFont(ofSize: 0.35, weight: .bold)
    #else
    textGeo.font = NSFont.systemFont(ofSize: 0.35, weight: .bold)
    #endif
    textGeo.flatness = 0.02
    // No chamfer (5.7): with one, the iOS 27 Simulator drew nothing for a name with a colon ("Juniper Flats Lease: Late
    // Charges", an empty text box, robot run 2026-10-20), and at 0.01 on text 0.35 high it was not visible anyway.
    textGeo.chamferRadius = 0

    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.emission.contents = color
    mat.emission.intensity = 0.9
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    // Drawn over the points (5.7): tested against their depth, a label behind the translucent cloud was hidden by it.
    mat.readsFromDepthBuffer = false
    textGeo.materials = [mat]

    let textNode = SCNNode(geometry: textGeo)
    textNode.renderingOrder = 100

    // Center the text
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    let container = SCNNode()
    container.name = "axisLabel"
    container.addChildNode(textNode)
    container.position = position

    // Billboard constraint so it always faces camera, on every axis (5.7): turned only about x and y, a name was upside
    // down on screen once the map was turned over the top (robot shots, 2026-10-20).
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    container.constraints = [billboard]

    return container
}

/// Creates an arrow from start to end with a cone tip
private func makeArrowAxis(from start: SCNVector3, to end: SCNVector3, color: PlatformColor) -> SCNNode {
    let container = SCNNode()

    // Calculate direction and length
    let dx = end.x - start.x
    let dy = end.y - start.y
    let dz = end.z - start.z
    let length = sqrt(dx * dx + dy * dy + dz * dz)

    // Shaft (cylinder) - visible but not too thick
    let shaftLength = length - 0.3 // Leave room for cone tip
    let shaft = SCNCylinder(radius: 0.025, height: CGFloat(shaftLength))
    let shaftMat = SCNMaterial()
    shaftMat.diffuse.contents = color
    shaftMat.emission.contents = color
    shaftMat.emission.intensity = 0.8
    shaftMat.lightingModel = .constant
    shaft.materials = [shaftMat]

    let shaftNode = SCNNode(geometry: shaft)
    // Position at midpoint
    shaftNode.position = SCNVector3((start.x + end.x) / 2 - dx * 0.2 / length,
                                    (start.y + end.y) / 2 - dy * 0.2 / length,
                                    (start.z + end.z) / 2 - dz * 0.2 / length)

    // Rotate to align with axis
    if abs(dy) > abs(dx), abs(dy) > abs(dz) {
        // Y axis - no rotation needed
    } else if abs(dx) > abs(dz) {
        // X axis
        shaftNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
    } else {
        // Z axis
        shaftNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    }

    container.addChildNode(shaftNode)

    // Cone tip at positive end
    let cone = SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.25)
    let coneMat = SCNMaterial()
    coneMat.diffuse.contents = color
    coneMat.emission.contents = color
    coneMat.emission.intensity = 1.0
    coneMat.lightingModel = .constant
    cone.materials = [coneMat]

    let coneNode = SCNNode(geometry: cone)
    coneNode.position = SCNVector3(end.x - dx * 0.1 / length,
                                   end.y - dy * 0.1 / length,
                                   end.z - dz * 0.1 / length)

    // Rotate cone to point in direction
    if abs(dy) > abs(dx), abs(dy) > abs(dz) {
        if dy < 0 { coneNode.eulerAngles = SCNVector3(Float.pi, 0, 0) }
    } else if abs(dx) > abs(dz) {
        coneNode.eulerAngles = SCNVector3(0, 0, dx > 0 ? -Float.pi / 2 : Float.pi / 2)
    } else {
        coneNode.eulerAngles = SCNVector3(dz > 0 ? Float.pi / 2 : -Float.pi / 2, 0, 0)
    }

    container.addChildNode(coneNode)

    return container
}

/// White sphere at origin
private func makeOriginMarker() -> SCNNode {
    let sphere = SCNSphere(radius: 0.06)
    let mat = SCNMaterial()
    #if canImport(UIKit)
        mat.diffuse.contents = UIColor.white
        mat.emission.contents = UIColor.white
    #else
        mat.diffuse.contents = NSColor.white
        mat.emission.contents = NSColor.white
    #endif
    mat.emission.intensity = 1.0
    mat.lightingModel = .constant
    sphere.materials = [mat]
    return SCNNode(geometry: sphere)
}

private func makeCameraNode(depthCue: Bool) -> SCNNode {
    let node = SCNNode()
    let camera = SCNCamera()
    camera.zNear = 0.01
    camera.zFar = 100
    camera.wantsDepthOfField = depthCue
    if depthCue {
        camera.focusDistance = CGFloat(mapCameraDistance)
        camera.fStop = 10
    }
    node.camera = camera
    // Where it started through 5.6, `mapCameraDistance` from the middle.
    node.simdPosition = mapCameraPosition
    node.look(at: SCNVector3(0, 0, 0))
    return node
}

private func addPointNodes(_ points: [SCNVector3], _ colors: [PlatformColor], scale: CGFloat, depthCue: Bool, into root: SCNNode) {
    let count = min(points.count, colors.count)
    guard count > 0 else { return }

    // Size relative to point count: fewer points = larger, more points = smaller
    // Range: 10 points → 0.12 radius, 500 points → 0.025 radius
    let countFactor = max(0.3, min(1.0, 50.0 / CGFloat(count)))
    let baseRadius: CGFloat = 0.08 * countFactor
    let radius = max(0.02, min(0.12, baseRadius * scale))

    // OPTIMIZATION: Reduce geometry complexity based on point count
    // More points = simpler spheres (8 segments vs 16 for few points)
    let segmentCount: Int
    if count > 1000 {
        segmentCount = 6 // Very simple for large datasets
    } else if count > 500 {
        segmentCount = 8
    } else if count > 100 {
        segmentCount = 10
    } else {
        segmentCount = 12
    }

    // Group points by color for efficient batching
    var colorToIndices: [Int: [Int]] = [:]
    colorToIndices.reserveCapacity(20) // Typical doc count
    for index in 0..<count {
        let colorHash = colors[index].hash
        colorToIndices[colorHash, default: []].append(index)
    }

    // Create one sphere geometry per color (true geometry sharing)
    // Each color group shares the SAME geometry instance
    for (_, indices) in colorToIndices {
        guard let firstIndex = indices.first else { continue }
        let color = colors[firstIndex]

        // Create shared geometry for this color group
        let sharedSphere = SCNSphere(radius: radius)
        sharedSphere.segmentCount = segmentCount

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.emission.contents = color
        material.emission.intensity = 0.85
        material.transparency = 0.92
        sharedSphere.materials = [material]

        // Create nodes sharing this geometry
        for index in indices {
            let node = SCNNode(geometry: sharedSphere)
            node.position = points[index]
            node.name = "point_\(index)"
            root.addChildNode(node)
        }
    }
}

// MARK: - Cluster Labels (Background-Aware with Arrows)

private func addClusterLabels(_ annotations: [Embedding3DSceneView.AnnotationData], backgroundStyle: EmbeddingSceneBackgroundStyle, into root: SCNNode) {
    guard !annotations.isEmpty else { return }

    // Create a dedicated label layer node that renders on top of everything
    let labelLayer = SCNNode()
    labelLayer.name = "labelLayer"
    labelLayer.renderingOrder = 100

    // === PHASE 1: Calculate scene bounds and spread distance ===
    let allPositions = annotations.map { simd_float3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) }
    let centroid = allPositions.reduce(simd_float3.zero, +) / Float(allPositions.count)
    let maxDistFromCenter = allPositions.map { simd_length($0 - centroid) }.max() ?? 1.0

    // Spread labels VERY far out - at least 2.5x the data spread, minimum 3.5 units
    let baseSpreadRadius = max(maxDistFromCenter * 2.8, 3.5)

    // === PHASE 2: Sort annotations by importance (document clusters first, larger clusters prioritized) ===
    let sortedAnnotations = annotations.sorted { a, b in
        if a.isDocumentCluster != b.isDocumentCluster { return a.isDocumentCluster }
        return a.clusterSize > b.clusterSize
    }

    // === PHASE 3: Calculate initial positions using golden angle spiral for maximum spread ===
    var labelPositions: [simd_float3] = []
    let goldenAngle: Float = .pi * (3.0 - sqrt(5.0)) // ~137.5° - optimal distribution

    for (index, annotation) in sortedAnnotations.enumerated() {
        let clusterPos = simd_float3(Float(annotation.position.x), Float(annotation.position.y), Float(annotation.position.z))

        // Calculate direction from scene centroid through cluster point (push labels outward)
        var outwardDir = simd_normalize(clusterPos - centroid)
        if simd_length(outwardDir) < 0.01 {
            // Fallback if cluster is at centroid
            outwardDir = simd_float3(cos(Float(index)), 0.3, sin(Float(index)))
        }

        // Use golden angle spiral for vertical distribution
        let spiralOffset = goldenAngle * Float(index)
        let verticalAngle = Float(index) / Float(max(sortedAnnotations.count, 1)) * Float.pi - Float.pi / 2

        // Add rotation around vertical axis based on spiral
        let rotatedX = outwardDir.x * cos(spiralOffset) - outwardDir.z * sin(spiralOffset)
        let rotatedZ = outwardDir.x * sin(spiralOffset) + outwardDir.z * cos(spiralOffset)
        outwardDir = simd_normalize(simd_float3(rotatedX, outwardDir.y + sin(verticalAngle) * 0.5, rotatedZ))

        // Distance varies by type: document clusters further out
        let distanceMultiplier: Float = annotation.isDocumentCluster ? 1.4 : 1.1
        let spreadDist = baseSpreadRadius * distanceMultiplier

        // Add some index-based variation to prevent exact alignments
        let jitter = Float(index % 3) * 0.2 - 0.2

        let labelPos = clusterPos + outwardDir * (spreadDist + jitter)
        labelPositions.append(labelPos)
    }

    // === PHASE 4: Collision detection and resolution ===
    let minSeparation: Float = 0.8 // Minimum distance between labels
    let iterations = 4 // Number of repulsion passes

    for _ in 0..<iterations {
        for i in 0..<labelPositions.count {
            for j in (i + 1)..<labelPositions.count {
                let delta = labelPositions[j] - labelPositions[i]
                let dist = simd_length(delta)

                if dist < minSeparation && dist > 0.001 {
                    // Push labels apart
                    let overlap = minSeparation - dist
                    let pushDir = simd_normalize(delta)
                    let pushAmount = overlap * 0.6

                    labelPositions[i] -= pushDir * pushAmount
                    labelPositions[j] += pushDir * pushAmount
                }
            }
        }
    }

    // === PHASE 5: Create label nodes with arrows ===
    for (index, annotation) in sortedAnnotations.enumerated() {
        let labelPos = labelPositions[index]
        let clusterPos = annotation.position

        // Create arrow pointing FROM label TO cluster centroid
        let arrowNode = makeArrowToCluster(
            from: SCNVector3(labelPos.x, labelPos.y, labelPos.z),
            to: clusterPos,
            color: annotation.color,
            backgroundStyle: backgroundStyle,
            isDocumentCluster: annotation.isDocumentCluster
        )

        // Create the badge
        let labelNode = makeClusterBadge(
            title: annotation.title,
            clusterSize: annotation.clusterSize,
            detailLevel: annotation.detailLevel,
            keywords: annotation.keywords,
            accentColor: annotation.color,
            backgroundStyle: backgroundStyle,
            priority: index,
            isDocumentCluster: annotation.isDocumentCluster
        )

        labelNode.position = SCNVector3(labelPos.x, labelPos.y, labelPos.z)
        labelLayer.addChildNode(arrowNode)
        labelLayer.addChildNode(labelNode)
    }

    root.addChildNode(labelLayer)
}

// MARK: - Inter-Cluster Relationship Lines

/// Draws faint connection lines between nearby clusters to show semantic relationships.
/// Only connects clusters whose centroids are within a threshold distance — closer means more related.
private func addInterClusterLines(_ annotations: [Embedding3DSceneView.AnnotationData], backgroundStyle: EmbeddingSceneBackgroundStyle, into root: SCNNode) {
    guard annotations.count >= 2 else { return }

    let lineLayer = SCNNode()
    lineLayer.name = "interClusterLines"
    lineLayer.renderingOrder = 5 // Behind cluster labels (100) but above points

    // Calculate median pairwise distance to set adaptive threshold
    var allDists: [Float] = []
    for i in 0..<annotations.count {
        for j in (i + 1)..<annotations.count {
            let pi = simd_float3(Float(annotations[i].position.x), Float(annotations[i].position.y), Float(annotations[i].position.z))
            let pj = simd_float3(Float(annotations[j].position.x), Float(annotations[j].position.y), Float(annotations[j].position.z))
            allDists.append(simd_distance(pi, pj))
        }
    }
    allDists.sort()

    // Connect pairs within the 40th percentile of distances (closest ~40%)
    let threshold: Float
    if allDists.count >= 2 {
        let p40Index = Int(Float(allDists.count) * 0.4)
        threshold = allDists[min(p40Index, allDists.count - 1)]
    } else {
        threshold = 3.0
    }

    // Maximum lines to avoid visual clutter
    let maxLines = min(annotations.count * 2, 15)
    var lineCount = 0

    // Sort pairs by distance (closest first) for priority drawing
    var pairs: [(i: Int, j: Int, dist: Float)] = []
    for i in 0..<annotations.count {
        for j in (i + 1)..<annotations.count {
            let pi = simd_float3(Float(annotations[i].position.x), Float(annotations[i].position.y), Float(annotations[i].position.z))
            let pj = simd_float3(Float(annotations[j].position.x), Float(annotations[j].position.y), Float(annotations[j].position.z))
            let dist = simd_distance(pi, pj)
            if dist <= threshold && dist > 0.1 {
                pairs.append((i, j, dist))
            }
        }
    }
    pairs.sort { $0.dist < $1.dist }

    for pair in pairs {
        guard lineCount < maxLines else { break }

        let a = annotations[pair.i]
        let b = annotations[pair.j]
        let posA = simd_float3(Float(a.position.x), Float(a.position.y), Float(a.position.z))
        let posB = simd_float3(Float(b.position.x), Float(b.position.y), Float(b.position.z))

        // Opacity inversely proportional to distance (closer = slightly more visible)
        let normalizedDist = pair.dist / max(threshold, 0.01)
        let alpha = CGFloat(max(0.04, 0.14 * (1.0 - Double(normalizedDist))))

        // Create hair-thin cylinder between the two cluster centroids
        let midpoint = (posA + posB) * 0.5
        let length = CGFloat(pair.dist)
        let lineGeo = SCNCylinder(radius: 0.004, height: length)

        // Use cluster color at very low opacity — visible on rotation, not distracting
        let lineMat = SCNMaterial()
        #if canImport(UIKit)
        lineMat.diffuse.contents = a.color.withAlphaComponent(alpha)
        lineMat.emission.contents = a.color.withAlphaComponent(alpha * 0.5)
        #else
        lineMat.diffuse.contents = a.color.withAlphaComponent(alpha)
        lineMat.emission.contents = a.color.withAlphaComponent(alpha * 0.5)
        #endif
        lineMat.emission.intensity = 0.3
        lineMat.lightingModel = .constant
        lineMat.isDoubleSided = true
        lineMat.writesToDepthBuffer = false
        lineMat.readsFromDepthBuffer = true
        lineGeo.materials = [lineMat]

        let lineNode = SCNNode(geometry: lineGeo)
        lineNode.position = SCNVector3(midpoint.x, midpoint.y, midpoint.z)

        // Rotate cylinder to align between the two points
        let direction = simd_normalize(posB - posA)
        let up = simd_float3(0, 1, 0)
        let dotProduct = simd_dot(direction, up)

        if abs(dotProduct) > 0.999 {
            // Nearly parallel to Y — minimal rotation needed
            if dotProduct < 0 { lineNode.eulerAngles.z = .pi }
        } else {
            let crossVec = simd_cross(up, direction)
            let angle = acos(min(max(dotProduct, -1), 1))
            lineNode.rotation = SCNVector4(crossVec.x, crossVec.y, crossVec.z, angle)
        }

        lineLayer.addChildNode(lineNode)
        lineCount += 1
    }

    root.addChildNode(lineLayer)
}

/// Creates an arrow line from label position pointing to cluster centroid
private func makeArrowToCluster(
    from labelPos: SCNVector3,
    to clusterPos: SCNVector3,
    color: PlatformColor,
    backgroundStyle: EmbeddingSceneBackgroundStyle,
    isDocumentCluster: Bool
) -> SCNNode {
    let container = SCNNode()

    // Calculate direction and length
    let dx = Float(clusterPos.x) - Float(labelPos.x)
    let dy = Float(clusterPos.y) - Float(labelPos.y)
    let dz = Float(clusterPos.z) - Float(labelPos.z)
    let length = sqrt(dx * dx + dy * dy + dz * dz)

    guard length > 0.1 else { return container } // Skip if too short

    // Shorten the line so it doesn't overlap with label or cluster
    let shortenAmount: Float = isDocumentCluster ? 0.15 : 0.1
    let effectiveLength = max(0.1, length - shortenAmount * 2)

    // Create the line (cylinder) — subtle enough to not clutter, visible enough to trace
    let lineRadius: CGFloat = isDocumentCluster ? 0.005 : 0.003
    let line = SCNCylinder(radius: lineRadius, height: CGFloat(effectiveLength))

    let lineMat = SCNMaterial()
    lineMat.diffuse.contents = color.withAlphaComponent(0.35)
    lineMat.emission.contents = color
    lineMat.emission.intensity = backgroundStyle.isDark ? 0.25 : 0.12
    lineMat.lightingModel = .constant
    lineMat.writesToDepthBuffer = false
    lineMat.readsFromDepthBuffer = false
    line.materials = [lineMat]

    let lineNode = SCNNode(geometry: line)

    // Position at midpoint
    let midX = (Float(labelPos.x) + Float(clusterPos.x)) / 2
    let midY = (Float(labelPos.y) + Float(clusterPos.y)) / 2
    let midZ = (Float(labelPos.z) + Float(clusterPos.z)) / 2
    lineNode.position = SCNVector3(xFloat: midX, yFloat: midY, zFloat: midZ)

    // Rotate to point from label to cluster
    // Default cylinder is along Y axis, we need to rotate it
    let direction = simd_normalize(simd_float3(dx, dy, dz))
    let up = simd_float3(0, 1, 0)

    // Calculate rotation quaternion
    let dot = simd_dot(up, direction)
    if abs(dot) < 0.999 {
        let cross = simd_cross(up, direction)
        let angle = acos(dot)
        lineNode.rotation = SCNVector4(xFloat: cross.x, yFloat: cross.y, zFloat: cross.z, wFloat: angle)
    } else if dot < 0 {
        // Pointing down
        lineNode.eulerAngles = SCNVector3(xFloat: Float.pi, yFloat: 0, zFloat: 0)
    }

    container.addChildNode(lineNode)

    // Create arrowhead (cone) pointing at cluster
    if isDocumentCluster {
        let coneHeight: CGFloat = 0.06
        let coneRadius: CGFloat = 0.025
        let cone = SCNCone(topRadius: 0, bottomRadius: coneRadius, height: coneHeight)

        let coneMat = SCNMaterial()
        coneMat.diffuse.contents = color
        coneMat.emission.contents = color
        coneMat.emission.intensity = 0.5
        coneMat.lightingModel = .constant
        cone.materials = [coneMat]

        let coneNode = SCNNode(geometry: cone)

        // Position near cluster (but not at it)
        let arrowTipDist = shortenAmount + Float(coneHeight) / 2
        let tipX = Float(clusterPos.x) - direction.x * arrowTipDist
        let tipY = Float(clusterPos.y) - direction.y * arrowTipDist
        let tipZ = Float(clusterPos.z) - direction.z * arrowTipDist
        coneNode.position = SCNVector3(xFloat: tipX, yFloat: tipY, zFloat: tipZ)

        // Rotate cone to point at cluster
        if abs(dot) < 0.999 {
            let cross = simd_cross(up, direction)
            let angle = acos(dot)
            coneNode.rotation = SCNVector4(xFloat: cross.x, yFloat: cross.y, zFloat: cross.z, wFloat: angle)
        } else if dot < 0 {
            coneNode.eulerAngles = SCNVector3(xFloat: Float.pi, yFloat: 0, zFloat: 0)
        }

        container.addChildNode(coneNode)
    }

    return container
}

/// Creates a floating cluster label - contrast-aware, with document name, count, and optional keywords
private func makeClusterBadge(
    title: String,
    clusterSize: Int,
    detailLevel: Int,
    keywords: [String],
    accentColor: PlatformColor,
    backgroundStyle: EmbeddingSceneBackgroundStyle,
    priority: Int,
    isDocumentCluster: Bool = true
) -> SCNNode {
    let container = SCNNode()
    container.name = "clusterLabel_\(priority)"
    container.renderingOrder = 101 + priority

    // === DETERMINE LABEL STYLE ===
    let isKeywordLabel = title.hasPrefix("#")
    let isSubCluster = !isDocumentCluster && !isKeywordLabel

    // === BUILD THE LABEL TEXT ===
    var displayText: String
    if isKeywordLabel {
        // Keyword hotspot: just the hashtag
        displayText = title
    } else if isDocumentCluster {
        // Main document cluster: Name (count) + keywords
        let truncatedTitle = String(title.prefix(32)) + (title.count > 32 ? "…" : "")
        displayText = "\(truncatedTitle) (\(clusterSize))"
        if detailLevel >= 1 && !keywords.isEmpty {
            // Filter out keywords that are substrings of the title (avoid "API API" duplication)
            let titleLower = title.lowercased()
            let filteredKeywords = keywords.filter { kw in
                let kwLower = kw.lowercased()
                return !titleLower.contains(kwLower) && !kwLower.contains(titleLower.prefix(4))
            }
            // Deduplicate keywords (case-insensitive)
            var seenKeywords: Set<String> = []
            let uniqueKeywords = filteredKeywords.filter { kw in
                let lower = kw.lowercased()
                if seenKeywords.contains(lower) { return false }
                seenKeywords.insert(lower)
                return true
            }
            if !uniqueKeywords.isEmpty {
                let keywordStr = uniqueKeywords.prefix(3).joined(separator: " • ")
                displayText += "\n\(keywordStr)"
            }
        }
    } else {
        // Sub-cluster: Section name only, smaller
        // 28 characters (5.7): at 18, "Cleaning & Detergent" read "Cleaning & Deterge…".
        let truncatedTitle = String(title.prefix(28)) + (title.count > 28 ? "…" : "")
        displayText = "▸ \(truncatedTitle)"
        if !keywords.isEmpty {
            // Filter keywords that match section title
            let titleLower = title.lowercased()
            let filtered = keywords.filter { !titleLower.contains($0.lowercased()) }
            if let firstKw = filtered.first {
                displayText += " • \(firstKw)"
            }
        }
    }

    let textGeo = SCNText(string: displayText, extrusionDepth: isDocumentCluster ? 0.02 : 0.012)

    // === DYNAMIC FONT SIZE (larger for readability) ===
    let baseFontSize: CGFloat
    if isKeywordLabel {
        baseFontSize = 0.18 // Larger for keyword tags
    } else if isDocumentCluster {
        baseFontSize = 0.24 + CGFloat(min(clusterSize, 80)) / 400.0 // Scale with cluster size, bigger base
    } else {
        baseFontSize = 0.16 // Sub-clusters slightly smaller
    }

    #if canImport(UIKit)
        let fontWeight: UIFont.Weight = isDocumentCluster ? .semibold : (isKeywordLabel ? .medium : .regular)
        textGeo.font = UIFont.systemFont(ofSize: baseFontSize, weight: fontWeight)
    #else
        let fontWeight: NSFont.Weight = isDocumentCluster ? .semibold : (isKeywordLabel ? .medium : .regular)
        textGeo.font = NSFont.systemFont(ofSize: baseFontSize, weight: fontWeight)
    #endif
    textGeo.flatness = 0.02 // Much smoother curves (lower = smoother but more geometry)
    textGeo.chamferRadius = 0.005 // Slightly rounded edges

    // === STYLE-SPECIFIC COLORS ===
    let textMat = SCNMaterial()
    if isKeywordLabel {
        // Keyword labels: cyan/teal color scheme
        textMat.diffuse.contents = platformColor(0.2, 0.9, 1.0) // Bright cyan
        textMat.emission.contents = platformColor(0.0, 0.7, 0.9)
        textMat.emission.intensity = 0.8
    } else if isSubCluster {
        // Sub-cluster: slightly muted, matches document color
        textMat.diffuse.contents = backgroundStyle.labelTextColor.withAlphaComponent(0.85)
        textMat.emission.contents = accentColor
        textMat.emission.intensity = backgroundStyle.isDark ? 0.4 : 0.2
    } else {
        // Document cluster: full prominence
        textMat.diffuse.contents = backgroundStyle.labelTextColor
        textMat.emission.contents = accentColor
        textMat.emission.intensity = backgroundStyle.isDark ? 0.6 : 0.3
    }
    textMat.lightingModel = .constant
    textMat.isDoubleSided = true
    textMat.writesToDepthBuffer = false
    textMat.readsFromDepthBuffer = false
    textGeo.materials = [textMat]

    let textNode = SCNNode(geometry: textGeo)

    // Center the text pivot point
    let (minBound, maxBound) = textGeo.boundingBox
    let textWidth = maxBound.x - minBound.x
    let textHeight = maxBound.y - minBound.y
    textNode.pivot = SCNMatrix4MakeTranslation(
        minBound.x + textWidth / 2,
        minBound.y + textHeight / 2,
        0
    )

    // === BACKGROUND PILL (style varies by type) ===
    let paddingH: CGFloat = isDocumentCluster ? 0.08 : 0.05
    let paddingV: CGFloat = isDocumentCluster ? 0.04 : 0.03
    let bgWidth = CGFloat(textWidth) + paddingH * 2
    let bgHeight = CGFloat(textHeight) + paddingV * 2
    let bgPlane = SCNPlane(width: bgWidth, height: bgHeight)
    bgPlane.cornerRadius = min(bgHeight / 2, 0.06)

    let bgMat = SCNMaterial()
    if isKeywordLabel {
        // Keyword: dark teal background
        bgMat.diffuse.contents = platformColor(0.0, 0.15, 0.2, alpha: 0.85)
    } else if isSubCluster {
        // Sub-cluster: slightly transparent version of main background
        bgMat.diffuse.contents = backgroundStyle.labelBackgroundColor.withAlphaComponent(0.6)
    } else {
        bgMat.diffuse.contents = backgroundStyle.labelBackgroundColor
    }
    bgMat.lightingModel = .constant
    bgMat.writesToDepthBuffer = false
    bgMat.readsFromDepthBuffer = false
    bgPlane.materials = [bgMat]

    let bgNode = SCNNode(geometry: bgPlane)
    bgNode.renderingOrder = 100 + priority
    bgNode.position = SCNVector3(0, 0, -0.005)

    // === ASSEMBLE BASE ===
    container.addChildNode(bgNode)
    container.addChildNode(textNode)

    // === ACCENT INDICATOR (only for document clusters) ===
    if isDocumentCluster {
        let indicatorRadius: CGFloat = 0.022
        let indicator = SCNSphere(radius: indicatorRadius)
        let indicatorMat = SCNMaterial()
        indicatorMat.diffuse.contents = accentColor
        indicatorMat.emission.contents = accentColor
        indicatorMat.emission.intensity = 0.6
        indicatorMat.lightingModel = .constant
        indicator.materials = [indicatorMat]

        let indicatorNode = SCNNode(geometry: indicator)
        indicatorNode.position = SCNVector3(
            Float(-bgWidth / 2) - Float(indicatorRadius) - 0.012,
            0,
            0
        )
        container.addChildNode(indicatorNode)
    }

    // Billboard constraint - always face camera, on every axis (5.7), so a cluster's name stays upright on screen once the
    // map is turned over the top.
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    container.constraints = [billboard]

    return container
}

private func addLighting(into root: SCNNode, depthCue: Bool) {
    // Brighter, more even lighting for better visibility
    let keyLight = SCNLight()
    keyLight.type = .omni
    keyLight.intensity = depthCue ? 1400 : 1100
    keyLight.castsShadow = false // Shadows can obscure points
    keyLight.attenuationStartDistance = 2.0
    keyLight.attenuationEndDistance = 15
    let keyNode = SCNNode()
    keyNode.light = keyLight
    keyNode.position = SCNVector3(2.5, 2.5, 3.0)
    root.addChildNode(keyNode)

    let fillLight = SCNLight()
    fillLight.type = .omni
    fillLight.intensity = depthCue ? 700 : 600
    fillLight.attenuationStartDistance = 2.0
    fillLight.attenuationEndDistance = 15
    let fillNode = SCNNode()
    fillNode.light = fillLight
    fillNode.position = SCNVector3(-2.5, -1.5, -3.0)
    root.addChildNode(fillNode)

    // Stronger ambient for base visibility
    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 350
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    root.addChildNode(ambientNode)
}

private func applyAutoRotate(_ isEnabled: Bool, to node: SCNNode) {
    // Always remove any existing animation first
    node.removeAnimation(forKey: "autoRotate")

    // Only add rotation if explicitly enabled
    guard isEnabled else { return }

    let animation = CABasicAnimation(keyPath: "rotation")
    animation.fromValue = SCNVector4(0, 1, 0, 0)
    animation.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
    animation.duration = 30 // Slower rotation
    animation.repeatCount = .greatestFiniteMagnitude
    node.addAnimation(animation, forKey: "autoRotate")
}

private func applyBackground(style: EmbeddingSceneBackgroundStyle, to scene: SCNScene) {
    if let image = gradientImage(for: style) {
        scene.background.contents = image
        scene.lightingEnvironment.contents = image
    } else {
        scene.background.contents = style.gradientSpec.colors.last
    }
}

private func gradientImage(for style: EmbeddingSceneBackgroundStyle) -> PlatformImage? {
    #if canImport(UIKit)
    let size = CGSize(width: 1024, height: 1024)
    let layer = CAGradientLayer()
    layer.frame = CGRect(origin: .zero, size: size)
    layer.colors = style.gradientSpec.colors.map { $0.cgColor }
    layer.startPoint = style.gradientSpec.startPoint
    layer.endPoint = style.gradientSpec.endPoint

    UIGraphicsBeginImageContextWithOptions(size, true, 0)
    guard let ctx = UIGraphicsGetCurrentContext() else {
        UIGraphicsEndImageContext()
        return nil
    }
    layer.render(in: ctx)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
    #else
    let size = CGSize(width: 1024, height: 1024)
    let layer = CAGradientLayer()
    layer.frame = CGRect(origin: .zero, size: size)
    layer.colors = style.gradientSpec.colors.map { $0.cgColor }
    layer.startPoint = style.gradientSpec.startPoint
    layer.endPoint = style.gradientSpec.endPoint

    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return nil
    }
    layer.render(in: ctx)
    image.unlockFocus()
    return image
    #endif
}

// MARK: - Coordinate Normalization (Apple Embedding Atlas style)

/// Scales coordinates to fit viewing space while preserving natural clustering
/// Unlike forced sphere distribution, this maintains actual embedding relationships
func normalizeToViewingCube(_ coords: [SIMD3<Float>], jitterAmount: Float = 0.02) -> [SCNVector3] {
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

    // Calculate center and uniform scale
    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    let centerZ = (minZ + maxZ) / 2

    let spanX = max(maxX - minX, 0.0001)
    let spanY = max(maxY - minY, 0.0001)
    let spanZ = max(maxZ - minZ, 0.0001)
    let maxSpan = max(spanX, max(spanY, spanZ))

    // Target viewing size
    let targetSize: Float = 3.0
    let scale = targetSize / maxSpan

    var result: [SCNVector3] = []
    result.reserveCapacity(coords.count)

    for (index, c) in coords.enumerated() {
        // Center and scale uniformly to preserve shape
        var x = (c.x - centerX) * scale
        var y = (c.y - centerY) * scale
        var z = (c.z - centerZ) * scale

        // Small jitter to prevent exact overlaps
        let seed = UInt32(index)
        x += (Float((seed &* 1_103_515_245 &+ 12345) % 10000) / 20000.0 - 0.025) * jitterAmount
        y += (Float((seed &* 1_664_525 &+ 1_013_904_223) % 10000) / 20000.0 - 0.025) * jitterAmount
        z += (Float((seed &* 22_695_477 &+ 1) % 10000) / 20000.0 - 0.025) * jitterAmount

        result.append(SCNVector3(x, y, z))
    }

    return result
}
#endif
