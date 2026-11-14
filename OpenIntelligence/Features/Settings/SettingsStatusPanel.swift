//
//  SettingsStatusPanel.swift
//  OpenIntelligence
//
//  The dark panel of lit blocks that Intelligence Mode and Device & Performance open with, as one view the
//  other Settings pages can use (5.8). Each block states a live figure and how full it is.
//

import SwiftUI

/// A dark panel with a title line and up to three lit blocks, drawn the way `ComputeProfileCard`'s chip is.
/// Every figure is the caller's: the panel draws what it is given and computes nothing.
struct SettingsStatusPanel: View {
    struct Block: Identifiable {
        let symbol: String
        let name: String
        let color: Color
        /// The big figure, as it should read: "3 of 5", "8,192", "Unlimited".
        let figure: String
        /// How much of the bar is lit, 0 to 1. Nil lights the whole bar (no limit).
        let share: Double?
        let caption: String
        var id: String { name }
    }

    let symbol: String
    let title: String
    let badge: String
    var badgeColor: Color = .white
    let blocks: [Block]

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: symbol)
                    .scaledFont(size: 11, weight: .semibold)
                Text(title)
                    .scaledFont(size: 12, weight: .bold, design: .monospaced)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(badge.uppercased())
                    .scaledFont(size: 10, weight: .heavy, design: .monospaced)
                    .foregroundStyle(badgeColor)
            }
            .foregroundStyle(Color.white.opacity(0.85))

            HStack(spacing: DSSpacing.sm) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
        }
        .padding(DSSpacing.sm)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(Color(white: 0.07))
                Canvas { context, size in
                    var path = Path()
                    stride(from: 0, through: size.height, by: 9).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.035)), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: blocks.map(\.color), startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1.2
                )
                .opacity(0.8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title), \(badge): " + blocks.map { "\($0.name) \($0.figure), \($0.caption)" }.joined(separator: "; "))
    }

    private func blockView(_ block: Block) -> some View {
        let share = min(1, max(0, block.share ?? 1))
        return VStack(spacing: 3) {
            Image(systemName: block.symbol)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.white)
                // One height for every symbol, so two blocks' lines sit level whatever their symbols' shapes.
                .frame(height: 20)
            Text(block.name)
                .scaledFont(size: 10, weight: .bold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(block.figure)
                .scaledFont(size: 13, weight: .heavy, design: .monospaced)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            // The bar: the lit part is the share.
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(block.color)
                            .frame(width: max(share > 0 ? 4 : 0, proxy.size.width * share))
                    }
                }
                .padding(.horizontal, DSSpacing.xs)
            Text(block.caption)
                .scaledFont(size: 9, weight: .semibold, design: .monospaced)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xs)
        .padding(.horizontal, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [block.color.opacity(0.30 + 0.35 * share), block.color.opacity(0.10)],
                        center: .center, startRadius: 2, endRadius: 70))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .strokeBorder(block.color.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: block.color.opacity(0.25 + 0.3 * share), radius: 4 + 8 * share)
    }

    /// "3 of 5", or "3" and no limit when the limit is unlimited.
    static func used(_ count: Int, of limit: Int) -> (figure: String, share: Double?, caption: String) {
        if limit == .max { return (count.formatted(), nil, "no limit") }
        let left = max(0, limit - count)
        return ("\(count.formatted()) of \(limit.formatted())", Double(count) / Double(max(1, limit)), "\(left.formatted()) left")
    }
}
