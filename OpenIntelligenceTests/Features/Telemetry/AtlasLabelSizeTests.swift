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
}
