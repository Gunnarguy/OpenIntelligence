//
//  Embedding3DSceneView.swift
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
// MARK: - SceneKit SwiftUI Wrapper

struct Embedding3DSceneView: View {
    struct SceneOptions {
        let pointScale: CGFloat
        let autoRotate: Bool
        let showAxes: Bool
        let showLines: Bool
        let depthCue: Bool
        let backgroundStyle: EmbeddingSceneBackgroundStyle
        let projectionMethod: ProjectionMethodKind
        // Dynamic axis labels derived from content analysis
        let axisLabels: AxisLabels
    }

    /// Dynamic axis labels derived from analyzing content at extremes of each axis
    struct AxisLabels {
        let xNeg: String  // Label for negative X direction
        let xPos: String  // Label for positive X direction
        let yNeg: String  // Label for negative Y direction
        let yPos: String  // Label for positive Y direction
        let zNeg: String  // Label for negative Z direction
        let zPos: String  // Label for positive Z direction

        static let placeholder = AxisLabels(
            xNeg: "", xPos: "",
            yNeg: "", yPos: "",
            zNeg: "", zPos: ""
        )
    }

    struct AnnotationData: Identifiable {
        let id = UUID()
        let position: SCNVector3       // Cluster centroid position
        let title: String              // Document/cluster name
        let keywords: [String]         // Top keywords for this cluster
        let color: PlatformColor       // Document accent color
        let detailLevel: Int           // 0=minimal, 1=normal, 2=detailed
        let clusterSize: Int           // Number of points in this cluster
        let isDocumentCluster: Bool    // True = per-doc cluster, False = spatial cluster
    }

    /// Info for a tapped point
    struct TappedPointInfo: Identifiable {
        let id = UUID()
        let index: Int
        let position: SCNVector3
    }

    let points: [SCNVector3]
    let colors: [PlatformColor]
    let options: SceneOptions
    let reloadToken: UUID
    let annotations: [AnnotationData]
    var onPointTapped: ((Int, SCNVector3) -> Void)?
    /// The 3D chart's angle, when the view that shows it keeps it (5.7), so it outlasts the chart: a reload or a change
    /// of layout recreates the chart, and a pose of its own would start over.
    var pose: Binding<Chart3DPose>?
    /// Draws the SceneKit scene rather than the chart (5.7): the Atlas's Scene style (`AtlasDrawingStyle`), which names
    /// each axis end and each cluster in the map, as the Atlas did through 5.6.
    var drawsScene = false
    /// What the views over the scene cover, which its axis labels keep clear of (5.7).
    var labelInsets = AxisLabelInsets.zero

    /// What each axis runs between, for VoiceOver, in the chart's words (`AtlasChart3D.axisTitle`).
    private var sceneAxesDescription: String {
        let labels = options.axisLabels
        let x = AtlasChart3D.axisTitle(negative: labels.xNeg, positive: labels.xPos, fallback: "X")
        let y = AtlasChart3D.axisTitle(negative: labels.yNeg, positive: labels.yPos, fallback: "Y")
        let z = AtlasChart3D.axisTitle(negative: labels.zNeg, positive: labels.zPos, fallback: "Z")
        return "Axes: \(x); \(y); \(z)"
    }

    var body: some View {
        if onPointTapped != nil || drawsScene {
            // The explorer (`EmbeddingSpaceRenderer`) opens the passage a tap lands on, which a 3D chart can't do: on
            // the iOS 27 Simulator, `chartXSelection`, `chartYSelection` and `chartZSelection` on a `Chart3D` reported
            // nothing for a tap, a press or a drag on a point (a drag turned it, 1° per point; probe run 2026-10-19),
            // and Apple's page for `chartZSelection` describes no behaviour. So it keeps the SceneKit scene, framed as
            // through 5.6, with each axis's names kept on screen at any angle (`keepAxisLabelsInView`). The Atlas's
            // Scene style draws the same scene, without the tap (`drawsScene`).
            SceneViewContainer(
                points: points,
                colors: colors,
                options: options,
                reloadToken: reloadToken,
                annotations: annotations,
                onPointTapped: onPointTapped,
                labelInsets: labelInsets
            )
            .background(DSColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // VoiceOver reads the map as the chart's is read (5.7): the scene's words are SceneKit text, which it
            // can't reach (review, 2026-10-20).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Knowledge Atlas, \(points.count) passages in three dimensions")
            .accessibilityValue(sceneAxesDescription)
        } else {
            // The Atlas's card and full screen are drawn with Swift Charts' `Chart3D` from 5.7 (`AtlasChart3D`). The
            // SceneKit scene drew the axes to ±5 and their labels at ±5.4 around a cloud scaled to 4.5, with the camera
            // 7.38 away and a 60° field of view, so an axis lying across the screen had both labels outside the view.
            // Fog, labels tested against the depth of the translucent points, and a blue Aurora background behind the
            // blue axis hid more, and every update rebuilt the scene and put the camera back. A
            // chart frames its axes inside the plot volume and keeps the user's angle in state. Cluster badges and
            // their lines are not drawn: the views' legends name the clusters, and the colours match.
            AtlasChart3D(points: points, colors: colors, options: options, pose: pose)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
extension Embedding3DSceneView.AxisLabels {
    /// The six labels in `AtlasLabeling.axisLabels`'s order: x low, x high, y low, y high, z low, z high (5.7).
    init(ends: [String]) {
        func end(_ index: Int) -> String { index < ends.count ? ends[index] : "" }
        self.init(xNeg: end(0), xPos: end(1), yNeg: end(2), yPos: end(3), zNeg: end(4), zPos: end(5))
    }
}
#endif
