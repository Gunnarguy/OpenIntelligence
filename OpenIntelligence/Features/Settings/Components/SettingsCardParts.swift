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

extension View {
    /// A choice on a mode or profile ladder drawn as a pill, the way a segmented control's segments read as buttons
    /// (5.8, 2026-11-16, the owner: "people might not know they can tap on each of the different options? There's not
    /// really any indicators"). The chosen one is filled in its colour; the others sit in a soft outlined pill.
    func ladderChoice(selected: Bool, color: Color) -> some View {
        modifier(LadderChoice(selected: selected, color: color))
    }
}

private struct LadderChoice: ViewModifier {
    let selected: Bool
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tint = color == .secondary ? Color.gray : color
        content
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)))
            )
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 0.75))
            .shadow(color: selected ? tint.opacity(0.35) : .clear, radius: 4, y: 2)
            .contentShape(Capsule())
    }
}

/// A row of choices drawn as the Intelligence Mode and Compute Profile ladders are (5.8, 2026-11-17): a bar over each
/// pill that rises from left to right, lit up to the chosen one, and the chosen pill filled in its colour. Model &
/// Privacy uses it for where answers are written and for the Private Cloud Compute permission, which were a list of
/// paragraph rows with a checkmark and a menu.
struct SettingsLadder<Item: Hashable>: View {
    struct Rung {
        let item: Item
        let name: String
        let color: Color
        var enabled = true
        let accessibilityLabel: String
    }

    let rungs: [Rung]
    let selected: Item
    var disabled = false
    let onSelect: (Item) -> Void

    var body: some View {
        let selectedIndex = rungs.firstIndex { $0.item == selected } ?? 0
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            ForEach(Array(rungs.enumerated()), id: \.offset) { index, rung in
                let isSelected = rung.item == selected
                let lit = index <= selectedIndex && !disabled
                Button {
                    guard !isSelected, rung.enabled, !disabled else { return }
                    DSHaptics.selection()
                    onSelect(rung.item)
                } label: {
                    VStack(spacing: DSSpacing.xxs) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                lit
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [rung.color.opacity(0.55), rung.color],
                                            startPoint: .bottom, endPoint: .top))
                                    : AnyShapeStyle(Color.secondary.opacity(0.14))
                            )
                            .frame(height: 6 + CGFloat(index) * 5)
                            .shadow(color: isSelected && !disabled ? rung.color.opacity(0.6) : .clear, radius: 6)
                        Text(rung.name)
                            .scaledFont(size: SettingsStatusPanel.minimumTextSize + 1, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(SettingsStatusPanel.floorScale(for: SettingsStatusPanel.minimumTextSize + 1))
                            .ladderChoice(selected: isSelected && !disabled, color: rung.color)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(rung.enabled && !disabled ? 1 : 0.45)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!rung.enabled || disabled)
                .accessibilityLabel(rung.enabled ? rung.accessibilityLabel : "\(rung.accessibilityLabel), not available")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

/// The tinted line under a ladder that says what the chosen step does (Intelligence Mode's "The base step" banner).
/// It keeps the height of its tallest wording, so the page doesn't shift as the choice changes.
struct SettingsLadderNote: View {
    struct Wording: Equatable {
        let symbol: String
        let title: String
        let detail: String
    }

    let wordings: [Wording]
    let current: Wording
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(wordings.enumerated()), id: \.offset) { _, wording in
                note(wording).hidden().accessibilityHidden(true)
            }
            note(current)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private func note(_ wording: Wording) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: wording.symbol)
                .foregroundStyle(DSColors.readable(color))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(wording.title)
                    .scaledFont(size: 11, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(wording.detail)
                    .scaledFont(size: 11)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A pushed Settings page that draws itself again whenever `SettingsStore` changes (2026-11-17). Its own
/// `@EnvironmentObject` subscribes it to the store, and calling `content` again reads the store's current values.
struct SettingsLivePage<Content: View>: View {
    @EnvironmentObject private var settings: SettingsStore
    let content: () -> Content

    var body: some View { content() }
}
