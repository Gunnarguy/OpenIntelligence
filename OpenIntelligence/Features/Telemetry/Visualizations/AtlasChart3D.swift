//
//  AtlasChart3D.swift
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
/// The Atlas's axis key (5.7): what each of the chart's X, Y and Z runs between, named from the passages at its two
/// ends (`AtlasLabeling`). The chart itself carries only the letters.
struct AtlasAxisKey: View {
    let labels: Embedding3DSceneView.AxisLabels
    var lineLimit: Int = 2

    var body: some View {
        if hasNames {
            VStack(alignment: .leading, spacing: 4) {
                row("X", labels.xNeg, labels.xPos)
                row("Y", labels.yNeg, labels.yPos)
                row("Z", labels.zNeg, labels.zPos)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var hasNames: Bool {
        ![labels.xNeg, labels.xPos, labels.yNeg, labels.yPos, labels.zNeg, labels.zPos].allSatisfy(\.isEmpty)
    }

    private func row(_ axis: String, _ negative: String, _ positive: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(axis)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 14, alignment: .leading)
            Text(AtlasChart3D.axisTitle(negative: negative, positive: positive, fallback: "Not named"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The Knowledge Atlas in 3D (5.7): one point per passage where the Atlas's projection put it, in its cluster's or its
/// library's colour, inside a cube whose three axes `AtlasLabeling` names from the passages at each end. The pose is the
/// person's own drag, kept by the view that shows the chart when it passes one (`pose`), so a reload or a change of
/// layout doesn't start it over; auto-rotate turns the same pose, so it never jumps back.
struct AtlasChart3D: View {
    struct Plot: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let z: Double
        let color: Color
    }

    let plots: [Plot]
    /// Half the side of the cube the axes span: the largest coordinate plus a margin, the same on all three axes so
    /// the cloud keeps its shape.
    let extent: Double
    let options: Embedding3DSceneView.SceneOptions
    /// The caller's angle, when it keeps one; otherwise `localPose`.
    private let poseBinding: Binding<Chart3DPose>?
    @State private var localPose: Chart3DPose = .default
    private var pose: Binding<Chart3DPose> { poseBinding ?? $localPose }

    init(
        points: [SCNVector3], colors: [PlatformColor], options: Embedding3DSceneView.SceneOptions,
        pose: Binding<Chart3DPose>? = nil
    ) {
        var plots: [Plot] = []
        plots.reserveCapacity(points.count)
        var maxAbs = 0.0
        for (index, point) in points.enumerated() {
            let x = Double(point.x), y = Double(point.y), z = Double(point.z)
            maxAbs = max(maxAbs, abs(x), abs(y), abs(z))
            let color: Color = index < colors.count ? Self.color(colors[index]) : .accentColor
            plots.append(Plot(id: index, x: x, y: y, z: z, color: color))
        }
        self.plots = plots
        self.extent = max(maxAbs, 0.001) * 1.08
        self.options = options
        self.poseBinding = pose
    }

    static func color(_ platformColor: PlatformColor) -> Color {
        #if canImport(UIKit)
            Color(uiColor: platformColor)
        #else
            Color(nsColor: platformColor)
        #endif
    }

    /// "Negative end ↔ positive end", or the one end that has a name. An axis whose ends do not differ is "Component N"
    /// at both ends (`AtlasLabeling.axisLabels`), named once.
    static func axisTitle(negative: String, positive: String, fallback: String) -> String {
        switch (negative.isEmpty, positive.isEmpty) {
        case (true, true): return fallback
        case (true, false): return positive
        case (false, true): return negative
        case (false, false): return negative == positive ? negative : "\(negative) ↔ \(positive)"
        }
    }

    var body: some View {
        let labels = options.axisLabels
        let xTitle = Self.axisTitle(negative: labels.xNeg, positive: labels.xPos, fallback: "X")
        let yTitle = Self.axisTitle(negative: labels.yNeg, positive: labels.yPos, fallback: "Y")
        let zTitle = Self.axisTitle(negative: labels.zNeg, positive: labels.zPos, fallback: "Z")
        let spec = options.backgroundStyle.gradientSpec
        Chart3D(plots) { plot in
            PointMark(
                x: .value("X", plot.x),
                y: .value("Y", plot.y),
                z: .value("Z", plot.z)
            )
            .foregroundStyle(plot.color)
            // The chart's own point size. In a probe on the iOS 27 Simulator (2026-10-19) each of eight `symbolSize`
            // values from 0.02 to 1,000 drew the nearest point over the whole chart, and Apple documents no unit for it
            // in 3D.
        }
        .chartXScale(domain: -extent...extent)
        .chartYScale(domain: -extent...extent)
        .chartZScale(domain: -extent...extent)
        // The projection's numbers mean nothing to a person, so the axes keep their grid and drop the figures.
        .chartXAxis { AxisMarks { AxisGridLine() } }
        .chartYAxis { AxisMarks { AxisGridLine() } }
        .chartZAxis { AxisMarks { AxisGridLine() } }
        // The letters only: names drawn along a 3D chart's axes ran off the card's edge and over each other as it turned
        // (robot shots, 2026-10-19). `AtlasAxisKey` writes out what each axis runs between.
        .chartXAxisLabel("X")
        .chartYAxisLabel("Y")
        .chartZAxisLabel("Z")
        .chart3DPose(pose)
        // Depth: a perspective camera, where nearer passages draw larger, or a flat orthographic one. (The volumetric
        // rendering style is visionOS only, per the iOS 27 SDK's Charts interface.)
        .chart3DCameraProjection(options.depthCue ? .perspective : .orthographic)
        // Square, in the middle of whatever frame it is given. A 3D chart sizes its cube from its frame's longer side:
        // in a probe on the iOS 27 Simulator a frame 360 points square drew the cube inside it with room to turn, with
        // either camera, and a frame 360 wide and 640 tall drew it wider than the frame (2026-10-19); the Atlas's full
        // screen on a phone did the same.
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: spec.colors.map { Self.color($0) },
                startPoint: UnitPoint(x: spec.startPoint.x, y: spec.startPoint.y),
                endPoint: UnitPoint(x: spec.endPoint.x, y: spec.endPoint.y)
            )
        )
        // Parchment is the one light background; on the others the axes and their names are drawn light.
        .environment(\.colorScheme, options.backgroundStyle == .parchment ? .light : .dark)
        .task(id: options.autoRotate) {
            guard options.autoRotate else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                let current = pose.wrappedValue
                pose.wrappedValue = Chart3DPose(
                    azimuth: Angle2D(degrees: current.azimuth.degrees + 0.4),
                    inclination: current.inclination
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Knowledge Atlas, \(plots.count) passages in three dimensions")
        .accessibilityValue("Axes: \(xTitle); \(yTitle); \(zTitle)")
    }
}
#endif
