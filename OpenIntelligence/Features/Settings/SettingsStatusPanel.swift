//
//  SettingsStatusPanel.swift
//  OpenIntelligence
//
//  The panel of figure blocks that Intelligence Mode and Device & Performance open with, as one view the
//  other Settings pages can use (5.8). Each block states a live figure and how full it is.
//

import SwiftUI

/// A panel with a title line and figure blocks, four to a row or three to a row for more.
/// Every figure is the caller's: the panel draws what it is given and computes nothing.
///
/// Pastel, and following light and dark mode (5.8, 2026-11-16, the owner: the dark lit look "looks a little bit tacky but
/// I do like the direction", "I want to not make everything dark", "make it all pastel, but it has to look like genuinely
/// premium"). Until then it was always near-black, with scan lines, a neon edge and a glow on every block and monospaced
/// type. Now a card surface with a faint wash of its blocks' colours, each block a soft tint of its colour with no edge
/// or glow, the figure in rounded type, and the symbol and bar in the block's colour, darkened where needed to read.
///
/// Calm and neutral (5.8, 2026-11-16, the owner: the pastel pass had too many hues per panel). The panel is content, so
/// no Liquid Glass (Human Interface Guidelines, Materials, read 2026-11-16: "Don't use Liquid Glass in the content
/// layer"). The card is the system's grouped cell surface with a hairline edge and, in light mode only, a light shadow;
/// every block has the same neutral fill; colour is only on each block's symbol and bar, so it marks the data.
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

    /// Apple's smallest legible text size (Human Interface Guidelines, Typography, read 2026-11-15): 11 points on
    /// iPhone and iPad, 10 on the Mac. Before 5.8 the panels drew captions at 8 and names at 9, and a
    /// `minimumScaleFactor` could shrink a figure to 7; no text in a panel goes below this now.
    #if os(macOS)
        static let minimumTextSize: CGFloat = 10
    #else
        static let minimumTextSize: CGFloat = 11
    #endif

    /// The scale factor that keeps text drawn at `size` from shrinking below `minimumTextSize`.
    static func floorScale(for size: CGFloat) -> CGFloat { min(1, minimumTextSize / size) }

    let symbol: String
    let title: String
    let badge: String
    var badgeColor: Color = .secondary
    let blocks: [Block]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: symbol)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(title)
                    .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.xs)
                Text(badge)
                    .scaledFont(size: Self.minimumTextSize + 1, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(DSColors.readable(badgeColor))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badgeColor.opacity(dark ? 0.20 : 0.12)))
                    .lineLimit(1)
            }

            // Up to four blocks in a row; more go three to a row (Active Device's six, 2026-11-16).
            if blocks.count > 4 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs), count: 3), spacing: DSSpacing.xs) {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            } else {
                // Every block takes the row's height, so one whose caption wraps to two lines is not taller than
                // the rest (Database's "unique, all libraries", 2026-11-16).
                HStack(spacing: DSSpacing.xs) {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.md)
        .settingsPanelSurface(dark: dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title), \(badge): " + blocks.map { "\($0.name) \($0.figure), \($0.caption)" }.joined(separator: "; "))
    }

    private func blockView(_ block: Block) -> some View {
        let share = min(1, max(0, block.share ?? 1))
        let dark = colorScheme == .dark
        let ink = DSColors.readable(block.color)
        return VStack(spacing: 3) {
            Image(systemName: block.symbol)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(ink)
                // One height for every symbol, so two blocks' lines sit level whatever their symbols' shapes.
                .frame(height: 16)
            Text(block.name)
                .scaledFont(size: Self.minimumTextSize, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // A figure too wide for a quarter of a phone wraps to a second line rather than shrinking below the minimum.
            Text(block.figure)
                .scaledFont(size: 15, weight: .semibold, design: .rounded, relativeTo: .subheadline)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(Self.floorScale(for: 15))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            // The bar: the coloured part is the share.
            Capsule()
                .fill(block.color.opacity(dark ? 0.22 : 0.15))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(block.color)
                            .frame(width: max(share > 0 ? 4 : 0, proxy.size.width * share))
                    }
                }
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, 2)
            Text(block.caption)
                .scaledFont(size: Self.minimumTextSize, weight: .regular)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Top-aligned, so symbols, names, figures and bars sit level across blocks of one height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, DSSpacing.xs)
        .padding(.horizontal, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip + 2, style: .continuous)
                .fill(Self.blockFill(dark: dark))
        )
    }

    /// The one neutral fill every block in Settings sits on (`SpecTile` and the mode and compute chips use it too).
    static func blockFill(dark: Bool) -> Color { Color.primary.opacity(dark ? 0.08 : 0.04) }

    /// "3 of 5", or "3" and no limit when the limit is unlimited.
    static func used(_ count: Int, of limit: Int) -> (figure: String, share: Double?, caption: String) {
        if limit == .max { return (count.formatted(), nil, "no limit") }
        let left = max(0, limit - count)
        return ("\(count.formatted()) of \(limit.formatted())", Double(count) / Double(max(1, limit)), "\(left.formatted()) left")
    }
}

extension View {
    /// The card every Settings panel sits on (5.8, 2026-11-16): the system's grouped cell surface, a hairline edge, and a
    /// light shadow in light mode only. Content, so never Liquid Glass.
    func settingsPanelSurface(dark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
        return background(shape.fill(DSColors.secondarySystemGroupedBackground))
            .overlay(shape.strokeBorder(Color.primary.opacity(dark ? 0.10 : 0.06), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(dark ? 0 : 0.05), radius: 8, x: 0, y: 2)
    }
}
