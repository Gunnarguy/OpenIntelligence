//
//  SettingsCardParts.swift
//  OpenIntelligence
//
//  One section header and one tile for every card on Device & Performance and Intelligence Mode (5.8). Until then
//  Active Device, Compute Profile, Intelligence Mode and the Live System Monitor each drew their own: two tile sizes,
//  three backgrounds, and a header on some sections and not others (the owner, 2026-11-10: "unify it all").
//

import SwiftUI

/// A section's title row: icon, title, and an optional badge on the right.
struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    var badge: String? = nil
    var badgeColor: Color = .accentColor
    /// A dot before the badge, for a value that updates live.
    var live = false

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            if let badge {
                HStack(spacing: DSSpacing.xxs) {
                    if live {
                        Circle().fill(badgeColor).frame(width: 6, height: 6)
                    }
                    Text(badge)
                        .contentTransition(.interpolate)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xxs)
                .background(badgeColor.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One figure: a small label with its icon, the value, and an optional line saying where it came from. Lit with a
/// tint where a step turns it up: the tint colours the symbol and the value only, on the same neutral fill as every
/// `SettingsStatusPanel` block (5.8, 2026-11-16: one look for Settings; it was a tinted fill with a coloured outline).
struct SpecTile: View {
    let name: String
    let value: String
    let icon: String
    var caption: String? = nil
    /// Lit: the value and the outline take this colour.
    var tint: Color? = nil
    /// A symbol in place of the icon, e.g. a bolt where a step goes further or a tortoise where it does less.
    var marker: String? = nil
    var muted = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Colours worked out first: as one expression the view took the type checker too long.
        let accent: Color = tint ?? Color.secondary
        let valueColor: Color = tint.map { DSColors.readable($0) } ?? (muted ? Color.secondary : Color.primary)
        let fill: Color = SettingsStatusPanel.blockFill(dark: colorScheme == .dark)
        // No text below Apple's minimum and none cut off (5.8 premium pass): the name and caption were 9 and 8 points on
        // one line, shrinking further and ending in "..." ("Reranked per s...").
        let small = SettingsStatusPanel.minimumTextSize
        return VStack(alignment: .leading, spacing: 1) {
            // The symbol is part of the text, so a name that wraps continues under it rather than indented
            // ("Reads / per step", 2026-11-16).
            Text("\(Text(Image(systemName: marker ?? icon)).foregroundStyle(accent).fontWeight(.bold)) \(name)")
                .foregroundStyle(.secondary)
                .scaledFont(size: small, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .scaledFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .minimumScaleFactor(SettingsStatusPanel.floorScale(for: 12))
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .scaledFont(size: small)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Fills its row's height in a `SpecTileGrid`, top-aligned, so a tile with a shorter caption isn't shorter.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip + 2, style: .continuous)
                .fill(fill)
        )
        .accessibilityElement(children: .combine)
    }

    /// The grid every card uses: three columns.
    static let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs), count: 3)
}

/// Three columns of `SpecTile`s where every tile in a row takes the row's height (2026-11-16: the owner's Intelligence
/// Mode screenshots had tiles of three heights in one row). `LazyVGrid` sizes each cell to its own content.
struct SpecTileGrid: Layout {
    var columns = 3
    var spacing: CGFloat = DSSpacing.xs

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func rowHeights(_ subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let heights = rowHeights(subviews, columnWidth: columnWidth(width))
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(bounds.width)
        let heights = rowHeights(subviews, columnWidth: width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (width + spacing), y: y),
                    proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }
}

/// The small monospaced label above a group of rows or tiles ("HOW HARD", "WHEN YOU ASK").
struct SettingsGroupLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .scaledFont(size: SettingsStatusPanel.minimumTextSize, weight: .semibold, design: .monospaced)
            .foregroundStyle(.secondary)
    }
}
