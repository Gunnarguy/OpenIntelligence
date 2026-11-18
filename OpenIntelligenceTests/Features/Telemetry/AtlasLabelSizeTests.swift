//
//  AtlasLabelSizeTests.swift
//  OpenIntelligenceTests
//
//  The map's labels are one size on screen however far they are from the camera (5.7). The app reads the positions
//  from SceneKit's presentation nodes, which only a running renderer fills in, so these test the arithmetic.
//

import SceneKit
import XCTest

@testable import OpenIntelligence

@MainActor
final class AtlasLabelSizeTests: XCTestCase {
    /// Twice as deep in the view, a label is drawn twice as large, so it reads at the same height; at the distance the
    /// camera starts from it is drawn at its own size.
    func testALabelTwiceAsFarIsDrawnTwiceAsLarge() {
        XCTAssertEqual(screenScale(depth: startingCameraDistance, fieldOfView: 60), 1, accuracy: 0.001)
        XCTAssertEqual(screenScale(depth: startingCameraDistance * 2, fieldOfView: 60), 2, accuracy: 0.001)
        // Clamped so a label never vanishes or fills the screen.
        XCTAssertEqual(screenScale(depth: 0.05, fieldOfView: 60), 0.35, accuracy: 0.001)
        XCTAssertEqual(screenScale(depth: 1_000, fieldOfView: 60), 4, accuracy: 0.001)
    }

    /// A label off to the side is as deep as one in the middle at the same distance along the view (a refuting review,
    /// 2026-10-16: the straight-line distance drew it larger).
    func testALabelOffToTheSideIsSizedByItsDepth() {
        let camera = SIMD3<Float>(0, 0, startingCameraDistance)
        let front = SIMD3<Float>(0, 0, -1)

        XCTAssertEqual(viewDepth(of: SIMD3(3, 0, 0), camera: camera, front: front), startingCameraDistance, accuracy: 0.001)
        XCTAssertEqual(viewDepth(of: SIMD3(0, 0, -startingCameraDistance), camera: camera, front: front),
                       startingCameraDistance * 2, accuracy: 0.001)
        // Behind the camera counts as just in front of it.
        XCTAssertEqual(viewDepth(of: SIMD3(0, 0, 20), camera: camera, front: front), 0.05, accuracy: 0.001)
    }

    /// A narrower view, as when zoomed in, draws the labels smaller in the scene, so they keep their height on screen.
    func testAZoomedInViewDrawsLabelsSmallerInTheScene() {
        XCTAssertEqual(
            screenScale(depth: startingCameraDistance, fieldOfView: 30), tan(Float.pi / 12) / tan(Float.pi / 6),
            accuracy: 0.001)
    }

    /// The labels are found by name: the ends of the axes and the clusters, not the points.
    func testTheMapsLabelsAreFoundByName() {
        let scene = SCNScene()
        let axis = SCNNode()
        axis.name = "axisLabel"
        scene.rootNode.addChildNode(axis)
        let layer = SCNNode()
        for name in ["clusterLabel_0", "point_12"] {
            let node = SCNNode()
            node.name = name
            layer.addChildNode(node)
        }
        scene.rootNode.addChildNode(layer)

        XCTAssertEqual(mapLabelNodes(in: scene).compactMap(\.name).sorted(), ["axisLabel", "clusterLabel_0"])
    }

    /// The camera starts where it did through 5.6, (3.5, 2.5, 6.0), about 7.38 from the middle (back on 2026-10-20): from
    /// 2026-10-19 it started about 23 away, and the cloud drew at a third of its 5.6 size.
    func testTheCameraStartsWhereItDidThrough56() {
        XCTAssertEqual(mapCameraPosition, SIMD3<Float>(3.5, 2.5, 6.0))
        XCTAssertEqual(mapCameraDistance, 7.3824, accuracy: 0.001)
        XCTAssertEqual(mapCameraDistance, startingCameraDistance, accuracy: 0.01, "labels are drawn at their own size there")
    }

    /// The view's half-angles: across the height by default, across the width when the view is taller than wide.
    func testTheFieldOfViewRunsAcrossTheNarrowerSide() {
        let half = tan(Float.pi / 6)
        let tall = viewHalfAngles(fieldOfView: 60, aspect: 0.5, horizontal: false)
        XCTAssertEqual(tall.x, half * 0.5, accuracy: 0.0001)
        XCTAssertEqual(tall.y, half, accuracy: 0.0001)
        let across = viewHalfAngles(fieldOfView: 60, aspect: 0.5, horizontal: true)
        XCTAssertEqual(across.x, half, accuracy: 0.0001)
        XCTAssertEqual(across.y, half / 0.5, accuracy: 0.0001)
    }

    /// A point goes onto the view and back to where it was: the middle of the map is drawn in the middle of the view,
    /// at the camera's distance, and the end of the x axis to the right of it.
    func testAPointGoesOntoTheViewAndBack() {
        let camera = SCNNode()
        camera.simdPosition = mapCameraPosition
        camera.look(at: SCNVector3(0, 0, 0))
        let transform = camera.simdWorldTransform
        let halfAngles = viewHalfAngles(fieldOfView: 60, aspect: 0.46, horizontal: true)

        let middle = viewPoint(of: .zero, camera: transform, halfAngles: halfAngles)
        XCTAssertEqual(middle.point.x, 0, accuracy: 0.0001)
        XCTAssertEqual(middle.point.y, 0, accuracy: 0.0001)
        XCTAssertEqual(middle.depth, mapCameraDistance, accuracy: 0.0001)

        let end = SIMD3<Float>(5.4, 0, 0)
        let drawn = viewPoint(of: end, camera: transform, halfAngles: halfAngles)
        XCTAssertGreaterThan(drawn.point.x, 0)
        let back = worldPoint(at: drawn.point, depth: drawn.depth, camera: transform, halfAngles: halfAngles)
        XCTAssertEqual(simd_distance(back, end), 0, accuracy: 0.001)
    }

    /// An axis label whose end is in view stays on it; one whose end is past an edge is moved in until all of it is on
    /// the view, `margin` from the edge; one wider than the view is centred across it.
    func testAnAxisLabelIsKeptOnTheView() {
        let half = SIMD2<Float>(0.2, 0.05)
        let region = AxisLabelRegion(insets: .zero, margin: 0.04)
        XCTAssertEqual(axisLabelSpot(wanted: SIMD2(0.3, -0.4), halfSize: half, region: region, placed: []), SIMD2(0.3, -0.4))
        let right = axisLabelSpot(wanted: SIMD2(1.7, 0.1), halfSize: half, region: region, placed: [])
        XCTAssertEqual(right.x, 1 - 0.04 - 0.2, accuracy: 0.0001)
        XCTAssertEqual(right.y, 0.1, accuracy: 0.0001)
        let corner = axisLabelSpot(wanted: SIMD2(-3, -2), halfSize: half, region: region, placed: [])
        XCTAssertEqual(corner.x, -(1 - 0.04 - 0.2), accuracy: 0.0001)
        XCTAssertEqual(corner.y, -(1 - 0.04 - 0.05), accuracy: 0.0001)
        let wide = axisLabelSpot(wanted: SIMD2(0.5, 0), halfSize: SIMD2(1.2, 0.05), region: region, placed: [])
        XCTAssertEqual(wide.x, 0, accuracy: 0.0001)
    }

    /// The full screen's top bar and legends (the top 30% here) and its controls (the bottom 20%) are kept clear: a
    /// label whose end is near the top of the view is drawn under the legends, not under the status bar.
    func testALabelKeepsClearOfTheViewsOverTheMap() {
        let region = AxisLabelRegion(insets: AxisLabelInsets(top: 0.3, bottom: 0.2), margin: 0.04)
        XCTAssertEqual(region.maximum.y, 0.4 - 0.02, accuracy: 0.0001)
        XCTAssertEqual(region.minimum.y, -0.6 + 0.02, accuracy: 0.0001)
        let top = axisLabelSpot(wanted: SIMD2(0, 0.9), halfSize: SIMD2(0.2, 0.05), region: region, placed: [])
        XCTAssertEqual(top.y, 0.38 - 0.05, accuracy: 0.0001)
        let bottom = axisLabelSpot(wanted: SIMD2(0, -0.95), halfSize: SIMD2(0.2, 0.05), region: region, placed: [])
        XCTAssertEqual(bottom.y, -0.58 + 0.05, accuracy: 0.0001)
    }

    /// The card's cluster box covers its lower left only (5.8). A label at the bottom of the middle stays at its axis end;
    /// one that would cover the box moves up to clear it. Through 5.7 the box was a band across the whole bottom, and the
    /// green axis's lower name sat partway up its line (the owner's screenshot, 2026-11-03).
    func testALabelClearsTheCardsBox_onlyWhereItWouldCoverIt() {
        let region = AxisLabelRegion(insets: .zero, margin: 0.04)
        let box = AxisLabelPlacement(center: SIMD2(-0.65, -0.65), halfSize: SIMD2(0.3, 0.3))
        let half = SIMD2<Float>(0.2, 0.05)
        let middle = axisLabelSpot(wanted: SIMD2(0, -0.8), halfSize: half, region: region, placed: [], boxes: [box])
        XCTAssertEqual(middle, SIMD2(0, -0.8))
        let corner = axisLabelSpot(wanted: SIMD2(-0.6, -0.8), halfSize: half, region: region, placed: [], boxes: [box])
        XCTAssertEqual(corner.y, -0.35 + 0.05, accuracy: 0.0001)
        XCTAssertFalse(box.overlaps(AxisLabelPlacement(center: corner, halfSize: half)))
    }

    /// The box the card measures, in points, becomes the same box in the scene's units: -1 to 1 across and up.
    func testTheCardsBox_isMeasuredInTheScenesUnits() {
        let scene = CGRect(x: 50, y: 500, width: 800, height: 600)
        let chrome = CGRect(x: 50, y: 950, width: 240, height: 150)
        let insets = CompactAtlasSceneView.cardLabelInsets(scene: scene, chrome: chrome)
        XCTAssertEqual(insets.bottom, 0)
        let box = try! XCTUnwrap(insets.boxes.first)
        XCTAssertEqual(box.center.x, -0.7, accuracy: 0.0001)
        XCTAssertEqual(box.halfSize.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.center.y, -0.75, accuracy: 0.0001)
        XCTAssertEqual(box.halfSize.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(CompactAtlasSceneView.cardLabelInsets(scene: scene, chrome: .zero), .zero)
    }

    /// Two labels pushed to the same place at the edge: the second steps toward the middle by its height and no longer
    /// covers the first.
    func testALabelThatWouldCoverAnotherStepsTowardTheMiddle() {
        let half = SIMD2<Float>(0.2, 0.05)
        let region = AxisLabelRegion(insets: .zero, margin: 0.04)
        let first = axisLabelSpot(wanted: SIMD2(2, 0.5), halfSize: half, region: region, placed: [])
        let placed = [AxisLabelPlacement(center: first, halfSize: half)]
        let second = axisLabelSpot(wanted: SIMD2(2, 0.52), halfSize: half, region: region, placed: placed)
        XCTAssertLessThan(second.y, first.y)
        XCTAssertFalse(placed[0].overlaps(AxisLabelPlacement(center: second, halfSize: half)))
    }

    /// Each axis label moves under the scene's root, so the map's turning doesn't carry it, and an anchor is left at its
    /// place on the axis; the pins pair them in order with the text's size.
    func testAxisLabelsArePinnedToAnchorsOnTheirAxes() {
        let scene = SCNScene()
        let axes = SCNNode()
        scene.rootNode.addChildNode(axes)
        for (index, x) in [Float(5.4), -5.4].enumerated() {
            let label = SCNNode()
            label.name = "axisLabel"
            label.simdPosition = SIMD3(x, 0, 0)
            label.addChildNode(SCNNode(geometry: SCNText(string: index == 0 ? "Tenant & Landlord" : "Oct", extrusionDepth: 0.02)))
            axes.addChildNode(label)
        }

        pinAxisLabels(of: axes, to: scene.rootNode)

        XCTAssertEqual(axes.childNodes.compactMap(\.name).sorted(), ["axisAnchor_0", "axisAnchor_1"])
        XCTAssertEqual(scene.rootNode.childNodes.compactMap(\.name).filter { $0.hasPrefix("axisLabel") }.sorted(),
                       ["axisLabel_0", "axisLabel_1"])
        let pins = axisLabelPins(in: scene)
        XCTAssertEqual(pins.map(\.label.name), ["axisLabel_0", "axisLabel_1"])
        XCTAssertEqual(pins.map(\.anchor.simdPosition.x), [5.4, -5.4])
        XCTAssertGreaterThan(pins[0].halfWidth, pins[1].halfWidth, "the longer name is wider")
        XCTAssertGreaterThan(pins[0].halfHeight, 0)
        XCTAssertEqual(mapLabelNodes(in: scene).compactMap(\.name).sorted(), ["axisLabel_0", "axisLabel_1"])
    }

    // MARK: - 5.8, 2026-11-18: sizes in points, placement, leader lines

    /// The map's words are drawn at a size in points: an axis's name at 10 on the iPhone's card (11 on the Mac), 12 in
    /// the iPhone's upright full screen, a cluster's half a point smaller. Through 2026-11-17 an axis name drew at
    /// about 11.5 points on the card and 18 in the full screen.
    func testTheMapsWordsAreDrawnAtASizeInPoints() {
        #if os(macOS)
            let smallest: Float = 11
        #else
            let smallest: Float = 10
        #endif
        let card = mapLabelPoints(viewSize: SIMD2(392, 280))
        XCTAssertEqual(card.axis, smallest, accuracy: 0.001)
        XCTAssertEqual(card.cluster, smallest - 0.5, accuracy: 0.001)
        XCTAssertEqual(mapLabelPoints(viewSize: SIMD2(440, 760)).axis, smallest + 2, accuracy: 0.001)
        XCTAssertEqual(mapLabelPoints(viewSize: SIMD2(1600, 1000)).axis, smallest + 3, accuracy: 0.001, "at most 3 more")

        // Text 0.35 units high, scaled by `labelFit`, is that many points on a view 280 points high, seen from where the
        // camera starts.
        let fit = labelFit(fontSize: 0.35, points: 10, viewExtent: 280)
        let pointsPerUnit: Float = 280 / (2 * startingCameraDistance * tan(Float.pi / 6))
        XCTAssertEqual(0.35 * fit * pointsPerUnit, 10, accuracy: 0.001)
        XCTAssertLessThan(fit, 1, "smaller than the 0.35 units it was drawn at on the card")
    }

    /// A label is placed clear of every other label and box, even where a stack of them leaves room only far from its
    /// end. Through 2026-11-17 it stepped at most six times and checked the boxes only before stepping, so on the
    /// owner's iPhone one axis name was drawn across another and one on the card's legend.
    func testALabelFindsAClearSpotPastAStackOfOthersAndTheBox() {
        let half = SIMD2<Float>(0.2, 0.05)
        let region = AxisLabelRegion(insets: .zero, margin: 0.04)
        let stack = (0..<8).map { AxisLabelPlacement(center: SIMD2(0, 0.6 - Float($0) * 0.1), halfSize: half) }
        let box = AxisLabelPlacement(center: SIMD2(0, -0.6), halfSize: SIMD2(0.5, 0.3))
        let spot = axisLabelSpot(wanted: SIMD2(0, 0.3), halfSize: half, region: region, placed: stack, boxes: [box])
        let label = AxisLabelPlacement(center: spot, halfSize: half)
        XCTAssertFalse(stack.contains { $0.overlaps(label) }, "covers no other label: \(spot)")
        XCTAssertFalse(box.overlaps(label), "and not the box: \(spot)")
        XCTAssertTrue(label.isInsideView)
    }

    /// A label nudged clear of the box doesn't land on another label in doing so (the old order checked the box first,
    /// then stepped onto it again).
    func testALabelClearOfTheBoxIsAlsoClearOfTheOthers() {
        let half = SIMD2<Float>(0.2, 0.05)
        let region = AxisLabelRegion(insets: .zero, margin: 0.04)
        let box = AxisLabelPlacement(center: SIMD2(-0.65, -0.65), halfSize: SIMD2(0.3, 0.3))
        let above = AxisLabelPlacement(center: SIMD2(-0.6, -0.3), halfSize: half)
        let spot = axisLabelSpot(wanted: SIMD2(-0.6, -0.8), halfSize: half, region: region, placed: [above], boxes: [box])
        let label = AxisLabelPlacement(center: spot, halfSize: half)
        XCTAssertFalse(box.overlaps(label))
        XCTAssertFalse(above.overlaps(label))
    }

    /// A cluster's name goes beside its point on the side away from the middle of the clusters, or the nearest clear
    /// side, and nowhere when no side is clear.
    func testAClustersNameGoesBesideItsPointWhereThereIsRoom() {
        let half = SIMD2<Float>(0.2, 0.05)
        let right = clusterLabelSpot(anchor: SIMD2(0.2, 0), middle: .zero, halfSize: half, taken: [])
        XCTAssertEqual(right?.x ?? 0, 0.2 + 0.12 + 0.2, accuracy: 0.0001, "away from the middle, the gap from its edge")
        XCTAssertEqual(right?.y ?? 1, 0, accuracy: 0.0001)

        let blocked = AxisLabelPlacement(center: SIMD2(0.6, 0), halfSize: SIMD2(0.3, 0.3))
        let other = try! XCTUnwrap(clusterLabelSpot(anchor: SIMD2(0.2, 0), middle: .zero, halfSize: half, taken: [blocked]))
        let label = AxisLabelPlacement(center: other, halfSize: half)
        XCTAssertFalse(blocked.overlaps(label))
        XCTAssertTrue(label.isInsideView)
        XCTAssertFalse(label.overlaps(AxisLabelPlacement(center: SIMD2(0.2, 0), halfSize: .zero)), "not over its point")

        let everything = AxisLabelPlacement(center: .zero, halfSize: SIMD2(1, 1))
        XCTAssertNil(clusterLabelSpot(anchor: SIMD2(0.2, 0), middle: .zero, halfSize: half, taken: [everything]))
    }

    /// A cluster's name is placed on the view with its leader line from it to the cluster's point, and the two are
    /// hidden together when there's no room or the point is off the view. Through 2026-11-17 the name was hidden and
    /// the line stayed, leading to nothing.
    func testALeaderLineRunsToItsPointAndHidesWithItsName() {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.simdPosition = SIMD3(0, 0, startingCameraDistance)
        scene.rootNode.addChildNode(cameraNode)
        let content = SCNNode()
        scene.rootNode.addChildNode(content)
        let middle = SCNNode()
        middle.name = "clusterMiddle"
        middle.simdPosition = SIMD3(-1, 0, 0)
        content.addChildNode(middle)
        let anchor = SCNNode()
        anchor.name = "clusterAnchor_0"
        anchor.simdPosition = SIMD3(0.5, 0.2, 0)
        content.addChildNode(anchor)
        let label = SCNNode()
        label.name = "clusterLabel_0"
        label.addChildNode(SCNNode(geometry: SCNPlane(width: 1.0, height: 0.22)))
        content.addChildNode(label)
        let leader = SCNNode()
        leader.name = "clusterLeader_0"
        let line = SCNNode(geometry: SCNCylinder(radius: 0.01, height: 1))
        line.name = "leaderLine"
        leader.addChildNode(line)
        content.addChildNode(leader)
        pinClusterLabels(of: content, to: scene.rootNode)
        XCTAssertTrue(label.parent === scene.rootNode)
        XCTAssertTrue(leader.parent === scene.rootNode)
        SCNTransaction.flush()

        let pins = clusterLabelPins(in: scene)
        XCTAssertEqual(pins.count, 1)
        placeClusterLabels(pins, with: [], pointOfView: cameraNode, aspect: 1)
        XCTAssertFalse(label.isHidden)
        XCTAssertFalse(leader.isHidden)
        XCTAssertGreaterThan(label.simdWorldPosition.x, 0.5, "on the side away from the middle")
        // The line starts at the name and points at the cluster's point, stopping just short of it.
        XCTAssertLessThan(simd_distance(leader.simdWorldPosition, label.simdWorldPosition), 0.0001)
        let reach = leader.simdWorldPosition + leader.simdWorldOrientation.act(SIMD3(0, line.simdScale.y, 0))
        XCTAssertEqual(simd_distance(reach, anchor.simdWorldPosition), 0.1, accuracy: 0.01)

        // No room anywhere: both hidden.
        let everything = AxisLabelPlacement(center: .zero, halfSize: SIMD2(1, 1))
        placeClusterLabels(pins, with: [everything], pointOfView: cameraNode, aspect: 1)
        XCTAssertTrue(label.isHidden)
        XCTAssertTrue(leader.isHidden)

        // The point off the view: both hidden.
        anchor.simdPosition = SIMD3(-12, 0, 0)
        SCNTransaction.flush()
        placeClusterLabels(pins, with: [], pointOfView: cameraNode, aspect: 1)
        XCTAssertTrue(label.isHidden)
        XCTAssertTrue(leader.isHidden)
    }

    /// A cluster's name is anchored on one of its own points, the one nearest its middle, so its line ends on a point the
    /// map draws. Through 2026-11-17 it was the middle itself, empty space in a cluster of two lobes.
    func testAClustersNameIsAnchoredOnOneOfItsPoints() {
        let coords: [SIMD3<Float>] = [SIMD3(-2, 0, 0), SIMD3(-1.8, 0, 0), SIMD3(1.8, 0, 0), SIMD3(2, 0, 0), SIMD3(0.3, 3, 0)]
        let groups = [0, 0, 0, 0, 1]
        let annotations = AtlasSceneLabels.annotations(
            coords: coords, groups: groups, names: ["Two lobes", "One"], colors: [.red, .blue], detailLevel: { _ in 0 })
        XCTAssertEqual(annotations.count, 2)
        // The points as the map draws them: centred on their bounds and scaled to 4.5 across.
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
        for c in coords { low = pointwiseMin(low, c); high = pointwiseMax(high, c) }
        let scale = 4.5 / max(high.x - low.x, high.y - low.y, high.z - low.z)
        let drawn = coords.map { ($0 - (low + high) / 2) * scale }
        for annotation in annotations {
            let position = SIMD3<Float>(Float(annotation.position.x), Float(annotation.position.y), Float(annotation.position.z))
            XCTAssertTrue(drawn.contains { simd_distance($0, position) < 0.0001 }, "\(annotation.title) sits on a point")
        }
    }

    /// The Insights card's "fits well with your library" names a document added to a library that held something
    /// before it, the newest first. A library whose documents came in one import has none (the guide library, 2026-11-18).
    func testARecentAdditionNeedsSomethingEarlierToFitWith() {
        let now = Date()
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let start = now.addingTimeInterval(-3 * 86_400)
        let oneImport = [(a, start), (b, start.addingTimeInterval(1)), (c, start.addingTimeInterval(2))]
            .map { (id: $0.0, addedAt: $0.1) }
        XCTAssertEqual(LibraryVisualizationEngine.recentAdditions(oneImport, since: cutoff), [])
        let later = oneImport + [(id: d, addedAt: now.addingTimeInterval(-60))]
        XCTAssertEqual(LibraryVisualizationEngine.recentAdditions(later, since: cutoff), [d])
        let older = [(id: a, addedAt: now.addingTimeInterval(-30 * 86_400)), (id: b, addedAt: now.addingTimeInterval(-3_600)),
            (id: c, addedAt: now.addingTimeInterval(-60))]
        XCTAssertEqual(LibraryVisualizationEngine.recentAdditions(older, since: cutoff), [c, b], "newest first")
    }
}
