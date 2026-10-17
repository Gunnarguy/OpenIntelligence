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
}
