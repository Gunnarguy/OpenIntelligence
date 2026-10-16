//
//  WrappingRowLayout.swift
//  OpenIntelligence
//
//  A row of pills that goes onto further lines when it does not fit across (5.7).
//

import SwiftUI

/// Lays its subviews out side by side while they fit across, and carries the ones that do not onto further lines at
/// the leading edge.
///
/// For rows of fixed-size pills (Chat's mode and model pills with the counts, Settings' status pills). Across one line
/// they ran past a 402-point screen at the larger text sizes, while an answer ran, and with a library of 100 passages
/// or more, and squeezing a pill is what cut its words. A subview that is wider than the row on its own is offered the
/// row's width, so text that may wrap does.
///
/// A `Layout` rather than `ViewThatFits`: with `ViewThatFits` a different text size built a different set of views,
/// and Apple's accessibility audit then read the row's text as not growing with the text size, although it did. Here
/// the views are the same at every size. `FlowLayout` (DocumentDetailsView.swift) places every subview at its ideal
/// size and has no trailing slot, so it could neither wrap a pill's text nor keep Chat's counts at the trailing edge.
struct WrappingRowLayout: Layout {
    /// Space between two subviews on one line.
    var spacing: CGFloat
    /// Space between two lines.
    var lineSpacing: CGFloat
    /// When every subview fits on one line, the last one sits at the trailing edge, where a `Spacer` before it would
    /// have put it.
    var lastAtTrailingEdge = false

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (lines: [Line], sizes: [CGSize]) {
        var sizes: [CGSize] = []
        var lines = [Line()]
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let size =
                ideal.width <= width ? ideal : subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            sizes.append(size)
            if !lines[lines.count - 1].indices.isEmpty, lines[lines.count - 1].width + spacing + size.width > width {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            line.width += (line.indices.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            lines[lines.count - 1] = line
        }
        return (lines, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (lines, _) = arrange(subviews, width: proposal.width ?? .infinity)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? (lines.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lines, sizes) = arrange(subviews, width: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line.indices {
                let size = sizes[index]
                let atTrailingEdge =
                    lastAtTrailingEdge && lines.count == 1 && line.indices.count > 1 && index == subviews.count - 1
                subviews[index].place(
                    at: CGPoint(
                        x: atTrailingEdge ? bounds.maxX - size.width : x, y: y + (line.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
