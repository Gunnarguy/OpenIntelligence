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
/// Given the view's size in points (5.8, 2026-11-18), each label is drawn at a size in points instead
/// (`mapLabelPoints`): an axis's name at 10 points on the iPhone's card, a cluster's half a point smaller. Through
/// 2026-11-17 a label's size was a share of the view's height, so an axis name drew at about 11.5 points on the card,
/// in bold, near the card title's height on the owner's iPhone, and at about 18 in the upright full screen.
///
/// It reads the positions as drawn: a spinning map turns its content with an animation, which moves only the
/// presentation nodes (SCNNode.h, `presentationNode`: "with any active animations applied"), so a model position
/// stands still while the map turns. And it uses the depth along the view, not the straight-line distance: a label
/// off to the side of the screen is no smaller on it for being further along the diagonal.
nonisolated func sizeLabelsForScreen(_ labels: [SCNNode], pointOfView: SCNNode, viewSize: SIMD2<Float>? = nil) {
    let view = pointOfView.presentation
    let camera = view.simdWorldPosition
    let front = view.simdWorldFront
    let fieldOfView = Float(pointOfView.camera?.fieldOfView ?? 60)
    // The side of the view the field of view spans (`fitProjection`), in points.
    let extent: Float? = viewSize.flatMap { size in
        guard size.x > 0, size.y > 0 else { return nil }
        return pointOfView.camera?.projectionDirection == .horizontal ? size.x : size.y
    }
    let points = viewSize.map { mapLabelPoints(viewSize: $0) }
    // A cluster's label fades by how far behind the middle of the map it is, so the fade is the same from any distance.
    let middle = viewDepth(of: .zero, camera: camera, front: front)
    for label in labels {
        let depth = viewDepth(of: label.presentation.simdWorldPosition, camera: camera, front: front)
        let isCluster = label.name?.hasPrefix("clusterLabel_") ?? false
        // An axis label is kept on screen (`keepAxisLabelsInView`) even when its end is near the camera, where the
        // 0.35 floor would draw it larger than the others (review, 2026-10-20).
        let scale = screenScale(depth: depth, fieldOfView: fieldOfView, minimum: isCluster ? 0.35 : 0.02)
        var fit: Float = isCluster ? 1.5 : 1
        if let extent, let points, let font = labelFontSize(label) {
            fit = labelFit(
                fontSize: font, points: isCluster ? points.cluster : points.axis, viewExtent: extent)
        }
        label.simdScale = SIMD3(repeating: scale * fit)
        if isCluster {
            let behind = depth - middle
            label.opacity = behind < -3.4 ? 0.95 : behind < 1.6 ? 0.88 : 0.75
        }
    }
}

/// The size on screen, in points, of an axis's name and of a cluster's name in the map (5.8, 2026-11-18): the smallest
/// text the app sets (`SettingsStatusPanel.minimumTextSize`, 10 points on iPhone and iPad, 11 on the Mac) on a view 280
/// points on its shorter side, the card's height, one point more for every 80 points beyond that, up to three; a
/// cluster's name half a point under an axis's. So 10 on the iPhone's card and 12 in its upright full screen.
nonisolated func mapLabelPoints(viewSize: SIMD2<Float>) -> (axis: Float, cluster: Float) {
    #if os(macOS)
        let smallest: Float = 11
    #else
        let smallest: Float = 10
    #endif
    let shorter = min(viewSize.x, viewSize.y)
    let axis = smallest + min(max((shorter - 280) / 80, 0), 3)
    return (axis, axis - 0.5)
}

/// The scale that draws text set at `fontSize` scene units at `points` on a view `viewExtent` points across the side its
/// field of view spans, at the distance the camera starts from with the default 60 degrees; `screenScale` carries it
/// to any other depth and field of view. Between 0.05 and 20.
nonisolated func labelFit(fontSize: Float, points: Float, viewExtent: Float) -> Float {
    let pointsPerUnit = viewExtent / (2 * startingCameraDistance * tan(Float.pi / 6))
    guard fontSize > 0, pointsPerUnit > 0 else { return 1 }
    return min(max(points / (fontSize * pointsPerUnit), 0.05), 20)
}

/// The scale that draws `label` at `points` on screen at `depth` along the view (5.8): what `sizeLabelsForScreen` sets,
/// for the depth the label is drawn at. The placing passes call it once they know that depth, because SceneKit stops
/// drawing a still map after a frame or two: a label sized for where its axis end was, then moved nearer to stay out of
/// the fog, kept the larger size, and three of the six names on the iPhone's card drew half as large again as the rest
/// (iOS 27.0 Simulator, 2026-11-18). Nil without the view's size or the label's text.
nonisolated func labelScale(
    _ label: SCNNode, depth: Float, pointOfView: SCNNode, viewSize: SIMD2<Float>?, cluster: Bool
) -> Float? {
    guard let viewSize, viewSize.x > 0, viewSize.y > 0, let font = labelFontSize(label), let camera = pointOfView.camera
    else { return nil }
    let extent = camera.projectionDirection == .horizontal ? viewSize.x : viewSize.y
    let points = mapLabelPoints(viewSize: viewSize)
    let scale = screenScale(depth: depth, fieldOfView: Float(camera.fieldOfView), minimum: cluster ? 0.35 : 0.02)
    return scale * labelFit(fontSize: font, points: cluster ? points.cluster : points.axis, viewExtent: extent)
}

/// The font size, in scene units, of a map label's text: its first child drawn with `SCNText`.
nonisolated func labelFontSize(_ label: SCNNode) -> Float? {
    for child in label.childNodes {
        if let text = child.geometry as? SCNText, let font = text.font { return Float(font.pointSize) }
    }
    return nil
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
@discardableResult
nonisolated func keepAxisLabelsInView(
    _ pins: [AxisLabelPin], pointOfView: SCNNode, aspect: Float, insets: AxisLabelInsets = .zero, margin: Float = 0.04,
    viewSize: SIMD2<Float>? = nil
) -> [AxisLabelPlacement] {
    guard let camera = pointOfView.camera, !pins.isEmpty else { return [] }
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
        if let sized = labelScale(pin.label, depth: drawDepth, pointOfView: pointOfView, viewSize: viewSize, cluster: false) {
            pin.label.simdScale = SIMD3(repeating: sized)
        }
        let scale = pin.label.simdScale.x
        let size = SIMD2<Float>(pin.halfWidth, pin.halfHeight) * scale / (halfAngles * drawDepth)
        var spot = axisLabelSpot(wanted: wanted, halfSize: size, region: region, placed: placed, boxes: insets.boxes)
        var held = size
        // A label held off its end gets an arrow beside it (`markOffViewEnd`), which counts as part of it (5.8): placed
        // by the text alone, the arrow of a name held at the card's edge was drawn past the edge.
        if isOffEnd(spot: spot, wanted: wanted, size: size) {
            let away = simd_normalize(wanted - spot)
            let arrow = edgeArrowReach * scale / (halfAngles * drawDepth)
            held = size + SIMD2(abs(away.x), abs(away.y)) * arrow
            spot = axisLabelSpot(wanted: wanted, halfSize: held, region: region, placed: placed, boxes: insets.boxes)
        }
        placed.append(AxisLabelPlacement(center: spot, halfSize: held))
        pin.label.simdWorldPosition = worldPoint(at: spot, depth: drawDepth, camera: transform, halfAngles: halfAngles)
        markOffViewEnd(pin, spot: spot, wanted: wanted, size: size)
    }
    return placed
}

/// Half the width and height of a cluster's label in its own units: its background's, else its text's. Read from the
/// geometry, not the node (5.8): SceneKit leaves a hidden node out of its bounding box, so a label hidden for one frame
/// measured nothing the next, showed, and was hidden again, every other frame (offscreen render, 2026-11-18).
nonisolated func clusterLabelHalfSize(_ label: SCNNode) -> SIMD2<Float> {
    for child in label.childNodes {
        if let plane = child.geometry as? SCNPlane {
            return SIMD2(Float(plane.width), Float(plane.height)) * 0.5
        }
    }
    for child in label.childNodes {
        if let text = child.geometry as? SCNText {
            let (low, high) = text.boundingBox
            return SIMD2(Float(high.x - low.x), Float(high.y - low.y)) * 0.5
        }
    }
    return .zero
}

/// How far beside a label's text the edge arrow reaches, in the label's own units: the arrow's offset (0.22) and the
/// glyph's half width at its 0.24 size, with room.
nonisolated let edgeArrowReach: Float = 0.38

/// Whether a label at `spot` is held off the end it names at `wanted`: more than its own height from it, so a nudge
/// clear of another label is not that.
nonisolated func isOffEnd(spot: SIMD2<Float>, wanted: SIMD2<Float>, size: SIMD2<Float>) -> Bool {
    simd_length(wanted - spot) > max(size.y * 2, 0.08)
}

/// A label held at the edge because its axis end is off the view says so (5.8): dimmed, with an arrow on the side
/// toward the end. Before, it sat at the edge looking like it named something there; on the owner's iPhone on
/// 2026-11-13 the green axis's name rode down onto the card's lower edge as the map turned, and read as a bug.
nonisolated private func markOffViewEnd(_ pin: AxisLabelPin, spot: SIMD2<Float>, wanted: SIMD2<Float>, size: SIMD2<Float>) {
    let away = wanted - spot
    let offEnd = isOffEnd(spot: spot, wanted: wanted, size: size)
    pin.label.opacity = offEnd ? 0.6 : 1
    let arrow = pin.label.childNode(withName: "edgeArrow", recursively: false) ?? {
        let glyph = SCNText(string: "\u{25B2}", extrusionDepth: 0.02)
        #if canImport(UIKit)
            glyph.font = UIFont.systemFont(ofSize: 0.24, weight: .bold)
        #else
            glyph.font = NSFont.systemFont(ofSize: 0.24, weight: .bold)
        #endif
        glyph.flatness = 0.02
        glyph.materials = pin.label.childNodes.first?.geometry?.materials ?? []
        let (low, high) = glyph.boundingBox
        let node = SCNNode(geometry: glyph)
        node.pivot = SCNMatrix4MakeTranslation((low.x + high.x) / 2, (low.y + high.y) / 2, 0)
        node.renderingOrder = 100
        let holder = SCNNode()
        holder.name = "edgeArrow"
        holder.addChildNode(node)
        pin.label.addChildNode(holder)
        return holder
    }()
    arrow.isHidden = !offEnd
    guard offEnd else { return }
    let direction = simd_normalize(away)
    // Beside the text on the side toward the axis end, in the label's own units, pointing at it.
    arrow.simdPosition = SIMD3(direction.x * (pin.halfWidth + 0.22), direction.y * (pin.halfHeight + 0.22), 0)
    arrow.simdEulerAngles = SIMD3(0, 0, atan2(direction.y, direction.x) - .pi / 2)
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

    /// All of it on the view: -1 to 1 across and up.
    var isInsideView: Bool {
        abs(center.x) + halfSize.x <= 1 && abs(center.y) + halfSize.y <= 1
    }

    /// How much of it lies over `other`, in the view's units squared.
    func overlapArea(_ other: AxisLabelPlacement) -> Float {
        let width = min(center.x + halfSize.x, other.center.x + other.halfSize.x)
            - max(center.x - halfSize.x, other.center.x - other.halfSize.x)
        let height = min(center.y + halfSize.y, other.center.y + other.halfSize.y)
            - max(center.y - halfSize.y, other.center.y - other.halfSize.y)
        return max(width, 0) * max(height, 0)
    }
}

/// Where a label of `halfSize` goes on the view (-1 to 1 across and up) to name the point at `wanted`: there, moved in
/// until all of it is inside `region`; then, while it would cover a label in `placed` or one of `boxes`, the nearest
/// spot that covers none of them, looked for up and down the region in steps of half its height and right up against
/// each label and box, and then along the row toward the middle. A step toward the middle of the region counts as
/// nearer than the same step away from it. A label wider or taller than the region is centred across it. When no spot
/// is clear, the one that covers the least.
///
/// Through 2026-11-17 a label that covered one in `placed` stepped toward the middle by its height at most six times,
/// and was checked against the boxes only before it stepped. On the owner's iPhone "RAG-Technical-Architecture" was
/// drawn across "Core & Embedding" where an axis pointed at the camera, and "Core & Embedding" was drawn on the card's
/// legend (2026-11-18).
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
    let start = simd_clamp(wanted, low, high)
    let others = placed + boxes
    func covered(_ spot: SIMD2<Float>) -> Float {
        let label = AxisLabelPlacement(center: spot, halfSize: halfSize)
        let area = others.reduce(0) { $0 + $1.overlapArea(label) }
        return area < 1e-6 ? 0 : area
    }
    guard covered(start) > 0 else { return start }

    // Rows to try: the start's, then up to four steps of half the label's width toward the middle.
    var columns: [Float] = [start.x]
    let across = max(halfSize.x * 0.5, 0.01)
    for step in 1...4 {
        let x = start.x + (start.x > middle.x ? -1 : 1) * Float(step) * across
        if x >= low.x - 0.0001, x <= high.x + 0.0001 { columns.append(min(max(x, low.x), high.x)) }
    }
    // Heights to try: up against each other label or box, and in steps of half the label's height.
    var heights: [Float] = []
    // A hair apart, so rounding never counts two labels that touch as covering each other.
    for other in others {
        heights.append(other.center.y + other.halfSize.y + halfSize.y + 0.00002)
        heights.append(other.center.y - other.halfSize.y - halfSize.y - 0.00002)
    }
    let step = max(halfSize.y, 0.005)
    var offset = step
    while offset <= high.y - low.y + step {
        heights.append(start.y + offset)
        heights.append(start.y - offset)
        offset += step
    }
    heights = heights.filter { $0 >= low.y - 0.0001 && $0 <= high.y + 0.0001 }.map { min(max($0, low.y), high.y) }

    var best = start
    var bestCost = Float.greatestFiniteMagnitude
    var leastCovered = covered(start)
    var leastCoveredSpot = start
    for (column, x) in columns.enumerated() {
        for y in [start.y] + heights {
            let spot = SIMD2(x, y)
            let dy = y - start.y
            // Toward the middle is nearer: a label pushed in from an edge stays nearer the middle of the view.
            let towardMiddle = (dy < 0) == (start.y > middle.y)
            let cost = abs(dy) * (towardMiddle ? 1 : 2) + Float(column) * across * 3
            guard cost < bestCost else { continue }
            let cover = covered(spot)
            if cover == 0 {
                best = spot
                bestCost = cost
            } else if cover < leastCovered {
                leastCovered = cover
                leastCoveredSpot = spot
            }
        }
    }
    return bestCost < .greatestFiniteMagnitude ? best : leastCoveredSpot
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
    pinClusterLabels(of: contentRoot, to: scene.rootNode)
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
    // At most 30 characters, in whole words (5.8): a library's or a heading's name can be any length.
    let textGeo = SCNText(string: AtlasLabeling.mapLabelText(text), extrusionDepth: 0.02)

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

/// Each cluster's name, its leader line and the point the line runs to (5.8, 2026-11-18). The point (`clusterAnchor_<n>`)
/// sits on one of the cluster's points in the map and turns with it; the name and its line hang under the scene's root
/// and are placed on the view every frame (`placeClusterLabels`), beside the point, where nothing else is drawn.
///
/// Through 2026-11-17 each name sat at a fixed place in the map at least 3.5 units out from the middle of the clusters,
/// turned round the vertical by the golden angle for each label after the first, with a line from it to the cluster's
/// middle. So the second cluster's name was sent about 137 degrees round the map from its cluster, out by the axis
/// ends, past the card's edge or onto an axis name; a name on an axis name was hidden and its line was not; and a
/// cluster's middle is empty space when its points lie in two lobes. On the owner's iPhone those were the "lines that
/// lead to nothing".
private func addClusterLabels(_ annotations: [Embedding3DSceneView.AnnotationData], backgroundStyle: EmbeddingSceneBackgroundStyle, into root: SCNNode) {
    guard !annotations.isEmpty else { return }

    let labelLayer = SCNNode()
    labelLayer.name = "labelLayer"
    labelLayer.renderingOrder = 100

    // Document clusters first, then the larger: the order a label is placed in when two want the same room.
    let sortedAnnotations = annotations.sorted { a, b in
        if a.isDocumentCluster != b.isDocumentCluster { return a.isDocumentCluster }
        return a.clusterSize > b.clusterSize
    }

    // The middle of the clusters: each name is placed on the side of its point away from it.
    let positions = annotations.map { simd_float3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) }
    let middle = SCNNode()
    middle.name = "clusterMiddle"
    middle.simdPosition = positions.reduce(simd_float3.zero, +) / Float(positions.count)
    labelLayer.addChildNode(middle)

    for (index, annotation) in sortedAnnotations.enumerated() {
        let anchor = SCNNode()
        anchor.name = "clusterAnchor_\(index)"
        anchor.position = annotation.position
        labelLayer.addChildNode(anchor)

        let leader = makeClusterLeader(
            color: annotation.color, backgroundStyle: backgroundStyle, isDocumentCluster: annotation.isDocumentCluster)
        leader.name = "clusterLeader_\(index)"
        leader.isHidden = true
        labelLayer.addChildNode(leader)

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
        labelNode.position = annotation.position
        // Shown once placed (`placeClusterLabels`), so it never draws for a frame on its point.
        labelNode.isHidden = true
        labelLayer.addChildNode(labelNode)
    }

    root.addChildNode(labelLayer)
}

/// Moves each cluster's name and leader line out of `content` to `root` (5.8), as `pinAxisLabels` does for the axes:
/// the map turns its content, and a name placed on the view each frame must not be turned with it.
nonisolated func pinClusterLabels(of content: SCNNode, to root: SCNNode) {
    let nodes = content.childNodes { node, _ in
        (node.name?.hasPrefix("clusterLabel_") ?? false) || (node.name?.hasPrefix("clusterLeader_") ?? false)
    }
    for node in nodes {
        let transform = node.simdWorldTransform
        node.removeFromParentNode()
        node.simdTransform = transform
        root.addChildNode(node)
    }
}

/// A cluster's name, its leader line, the point the line runs to and the middle of the clusters (5.8).
nonisolated struct ClusterLabelPin {
    let label: SCNNode
    let leader: SCNNode
    let anchor: SCNNode
    let middle: SCNNode?
}

/// The scene's cluster names with their lines and points, found once for each scene, in the order they are placed.
nonisolated func clusterLabelPins(in scene: SCNScene) -> [ClusterLabelPin] {
    var anchors: [String: SCNNode] = [:], labels: [String: SCNNode] = [:], leaders: [String: SCNNode] = [:]
    var middle: SCNNode?
    scene.rootNode.enumerateHierarchy { node, _ in
        guard let name = node.name else { return }
        if name == "clusterMiddle" {
            middle = node
        } else if name.hasPrefix("clusterAnchor_") {
            anchors[String(name.dropFirst("clusterAnchor_".count))] = node
        } else if name.hasPrefix("clusterLabel_") {
            labels[String(name.dropFirst("clusterLabel_".count))] = node
        } else if name.hasPrefix("clusterLeader_") {
            leaders[String(name.dropFirst("clusterLeader_".count))] = node
        }
    }
    return labels.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { key in
        guard let label = labels[key], let leader = leaders[key], let anchor = anchors[key] else { return nil }
        return ClusterLabelPin(label: label, leader: leader, anchor: anchor, middle: middle)
    }
}

/// Places each cluster's name on the view beside the point its line runs to, every frame after `keepAxisLabelsInView`
/// (5.8, 2026-11-18): on the side away from the middle of the clusters if that side is clear, else the nearest clear
/// side (`clusterLabelSpot`), clear of every axis name, of `insets` (the full screen's bars, the card's legend) and of the names placed
/// before it, nearer ones first. Its leader line is drawn from the name to the point. A name with no clear side, or
/// whose point is off the view or behind the camera, is hidden with its line, so no line is ever drawn to nothing.
nonisolated func placeClusterLabels(
    _ pins: [ClusterLabelPin], with axisLabels: [AxisLabelPlacement], pointOfView: SCNNode, aspect: Float,
    insets: AxisLabelInsets = .zero, viewSize: SIMD2<Float>? = nil
) {
    guard let camera = pointOfView.camera, !pins.isEmpty else { return }
    let transform = pointOfView.presentation.simdWorldTransform
    let halfAngles = viewHalfAngles(
        fieldOfView: Float(camera.fieldOfView), aspect: aspect, horizontal: camera.projectionDirection == .horizontal)
    var taken = axisLabels + insets.boxes
    // Clear of the full screen's top bar and controls too (`AxisLabelInsets` top and bottom).
    let region = AxisLabelRegion(insets: insets, margin: 0.02)
    let middle = pins.first?.middle.map {
        viewPoint(of: $0.presentation.simdWorldPosition, camera: transform, halfAngles: halfAngles).point
    }
    let seen = pins.map { pin in
        (pin: pin, view: viewPoint(of: pin.anchor.presentation.simdWorldPosition, camera: transform, halfAngles: halfAngles))
    }
    for (pin, view) in seen.sorted(by: { $0.view.depth < $1.view.depth }) {
        var spot: SIMD2<Float>?
        var drawDepth = view.depth
        if view.depth > 0.1, abs(view.point.x) <= 1, abs(view.point.y) <= 1 {
            // No deeper than where the fog starts, as the axis names (`keepAxisLabelsInView`).
            drawDepth = min(view.depth, max(mapCameraDistance - 1, 0.2))
            if let sized = labelScale(pin.label, depth: drawDepth, pointOfView: pointOfView, viewSize: viewSize, cluster: true) {
                pin.label.simdScale = SIMD3(repeating: sized)
            }
            let half = clusterLabelHalfSize(pin.label) * pin.label.simdScale.x / (halfAngles * drawDepth)
            spot = clusterLabelSpot(anchor: view.point, middle: middle, halfSize: half, taken: taken, region: region)
            if let spot { taken.append(AxisLabelPlacement(center: spot, halfSize: half)) }
        }
        guard let spot else {
            pin.label.isHidden = true
            pin.leader.isHidden = true
            continue
        }
        let labelPoint = worldPoint(at: spot, depth: drawDepth, camera: transform, halfAngles: halfAngles)
        pin.label.simdWorldPosition = labelPoint
        pin.label.isHidden = false
        drawClusterLeader(
            pin.leader, from: labelPoint, to: pin.anchor.presentation.simdWorldPosition,
            width: drawDepth / startingCameraDistance)
        pin.leader.isHidden = false
    }
}

/// Where a cluster's name of `halfSize` goes on the view (-1 to 1 across and up) to name the point at `anchor`: `gap`
/// from it, on the side away from `middle` (straight up when it is at the middle), else turned from that side by 45
/// degrees at a time, nearest turn first, then the same again twice as far out. The first spot all inside `region` (the
/// view less the bars over it, `margin` in from its edges) and over nothing in `taken`; nil when there is none.
nonisolated func clusterLabelSpot(
    anchor: SIMD2<Float>, middle: SIMD2<Float>?, halfSize: SIMD2<Float>, taken: [AxisLabelPlacement],
    gap: Float = 0.12, region: AxisLabelRegion = AxisLabelRegion(insets: .zero, margin: 0.02)
) -> SIMD2<Float>? {
    var outward = anchor - (middle ?? .zero)
    if simd_length(outward) < 0.02 { outward = SIMD2(0, 1) }
    let base = atan2(outward.y, outward.x)
    for distance in [gap, gap * 2.2] {
        for turn in [0, 1, -1, 2, -2, 3, -3, 4] {
            let angle = base + Float(turn) * .pi / 4
            let direction = SIMD2(cos(angle), sin(angle))
            // From the label's centre to its edge along `direction`.
            let reach = min(
                abs(direction.x) > 0.001 ? halfSize.x / abs(direction.x) : .greatestFiniteMagnitude,
                abs(direction.y) > 0.001 ? halfSize.y / abs(direction.y) : .greatestFiniteMagnitude)
            let spot = anchor + direction * (distance + reach)
            guard spot.x - halfSize.x >= region.minimum.x, spot.x + halfSize.x <= region.maximum.x,
                spot.y - halfSize.y >= region.minimum.y, spot.y + halfSize.y <= region.maximum.y
            else { continue }
            let label = AxisLabelPlacement(center: spot, halfSize: halfSize)
            if !taken.contains(where: { $0.overlaps(label) }) { return spot }
        }
    }
    return nil
}

/// Draws a leader line from a cluster's name at `start` to its point at `end`, stopping short of the point by the size
/// it is drawn at, `width` times the line's own thickness; with an arrowhead at the point when it has one.
nonisolated func drawClusterLeader(_ leader: SCNNode, from start: SIMD3<Float>, to end: SIMD3<Float>, width: Float) {
    let offset = end - start
    let distance = simd_length(offset)
    guard distance > 0.0001 else { return }
    let length = max(distance - 0.1, 0.01)
    let direction = offset / distance
    leader.simdWorldPosition = start
    leader.simdWorldOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: direction)
    let thickness = max(width, 0.2)
    if let line = leader.childNode(withName: "leaderLine", recursively: false) {
        line.simdScale = SIMD3(thickness, length, thickness)
        line.simdPosition = SIMD3(0, length / 2, 0)
    }
    if let tip = leader.childNode(withName: "leaderTip", recursively: false) {
        tip.simdScale = SIMD3(repeating: thickness)
        tip.simdPosition = SIMD3(0, length - 0.03 * thickness, 0)
    }
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

/// A cluster's leader line (5.8): a line one unit long along +y, which `drawClusterLeader` stretches from the name to
/// the point every frame, in the cluster's colour, with an arrowhead for a document's cluster. Drawn over the points.
private func makeClusterLeader(
    color: PlatformColor,
    backgroundStyle: EmbeddingSceneBackgroundStyle,
    isDocumentCluster: Bool
) -> SCNNode {
    let container = SCNNode()

    // About a point wide on the card (5.8): at 0.003 a line was a hairline the owner could barely follow.
    let line = SCNCylinder(radius: isDocumentCluster ? 0.014 : 0.012, height: 1)
    let lineMat = SCNMaterial()
    lineMat.diffuse.contents = color.withAlphaComponent(0.6)
    lineMat.emission.contents = color
    lineMat.emission.intensity = backgroundStyle.isDark ? 0.35 : 0.15
    lineMat.lightingModel = .constant
    lineMat.writesToDepthBuffer = false
    lineMat.readsFromDepthBuffer = false
    line.materials = [lineMat]
    let lineNode = SCNNode(geometry: line)
    lineNode.name = "leaderLine"
    lineNode.renderingOrder = 99
    container.addChildNode(lineNode)

    if isDocumentCluster {
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.025, height: 0.06)
        let coneMat = SCNMaterial()
        coneMat.diffuse.contents = color
        coneMat.emission.contents = color
        coneMat.emission.intensity = 0.5
        coneMat.lightingModel = .constant
        coneMat.readsFromDepthBuffer = false
        cone.materials = [coneMat]
        let coneNode = SCNNode(geometry: cone)
        coneNode.name = "leaderTip"
        coneNode.renderingOrder = 99
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
        let truncatedTitle = AtlasLabeling.mapLabelText(title, limit: 32)
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
        // 28 characters (5.7): at 18, "Cleaning & Detergent" read "Cleaning & Deterge…". From 5.8, 30 in whole words
        // (`AtlasLabeling.mapLabelText`): "OpenIntelligence Product Guide" read "OpenIntelligence Product Gui…".
        let truncatedTitle = AtlasLabeling.mapLabelText(title, limit: 30)
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
    // No chamfer (5.8, 2026-11-18), as the axis names since 5.7: with 0.005, iOS 27 drew no text at all, so the
    // badge's bounding box was its padding alone and the name showed as a small grey pill at the end of its line, the
    // "small grey dot in empty space" on the owner's iPhone (reproduced in the iOS 27.0 Simulator the same day).
    textGeo.chamferRadius = 0

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
