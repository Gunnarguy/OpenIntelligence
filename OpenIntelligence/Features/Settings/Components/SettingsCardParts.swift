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
/// tint where a step turns it up.
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

    var body: some View {
        // Colours worked out first: as one expression the view took the type checker too long.
        let accent: Color = tint ?? Color.secondary
        let valueColor: Color = tint ?? (muted ? Color.secondary : Color.primary)
        let fill: Color = tint.map { $0.opacity(0.10) } ?? Color.secondary.opacity(0.07)
        let stroke: Color = (tint ?? Color.clear).opacity(0.5)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: marker ?? icon)
                    .scaledFont(size: 8, weight: .bold)
                    .foregroundStyle(accent)
                Text(name)
                    .scaledFont(size: 9, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .scaledFont(size: 12, weight: .bold, design: .rounded)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .scaledFont(size: 8)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// The grid every card uses: three columns.
    static let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs), count: 3)
}

/// The small monospaced label above a group of rows or tiles ("HOW HARD", "WHEN YOU ASK").
struct SettingsGroupLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .scaledFont(size: 9, weight: .semibold, design: .monospaced)
            .foregroundStyle(.secondary)
    }
}
