//
//  DatabaseSupportingViews.swift
//  OpenIntelligence
//
//  Moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

// MARK: - Supporting Views

/// Every card on the Database tab (5.8, 2026-11-15): a `SurfaceCard` titled by a `SectionHeader`, with anything that
/// belongs at the title's right (a status, a count, a button) beside it. One radius, one padding and one spacing, the
/// same as the Settings pages, where each card drew its own rounded rectangle and a title at its own size.
struct DatabaseCard<Trailing: View, Content: View>: View {
    let icon: String?
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        SurfaceCard {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                SectionHeader(icon: icon, title: title, caption: caption)
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DatabaseCard where Trailing == EmptyView {
    init(icon: String?, title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, title: title, caption: caption, trailing: { EmptyView() }, content: content)
    }
}

/// A chip in the Database tab's two rows, the library scope and the section, drawn as the Documents tab's library
/// chips are (`ContainerPill`): footnote type, a filled capsule when chosen, an outline when not (2026-11-15). The
/// sections were 44-point pills in a larger type than anything else on the page.
struct DatabaseChip: View {
    let label: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption2.weight(.medium))
                Text(label)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs + 2)
            .background(Capsule().fill(isSelected ? tint : DSColors.surface))
            .foregroundStyle(isSelected ? Color.white : DSColors.primaryText)
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : tint.opacity(0.3), lineWidth: 1))
            .shadow(color: isSelected ? tint.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct QuickStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IndexFactRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title)
                .font(.subheadline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DocumentStatRow: View {
    let doc: SQLiteFullTextService.DocumentStat
    let documentName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(documentName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)
                Label("Added \(doc.createdAt, style: .relative) ago", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                Text("\(doc.wordCount.formatted()) words")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSColors.primaryText)
                Text("\(doc.characterCount.formatted()) chars")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSColors.secondaryText)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, DSSpacing.sm)
        .contentShape(Rectangle())
    }
}

struct IndexStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        FigureTile(title: title, value: value, icon: icon, color: color)
    }
}

struct TokenizerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DSColors.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

struct FeatureBadge: View {
    let name: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .red)
                .font(.caption)
            Text(name)
                .font(.caption)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(enabled ? Color.green.opacity(0.1) : Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

struct SearchTip: View {
    let syntax: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Text(syntax)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, DSSpacing.xs)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

struct SearchResultRow: View {
    let result: FTS5SearchResult
    let documentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(documentName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.2f", -result.bm25Score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
            }

            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

/// Card for diagnostics with icon and color
struct DiagnosticCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        FigureTile(title: label, value: value, icon: icon, color: color)
    }
}

/// Compact stat card for mini metrics
struct MiniStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }
}

/// Simple info row with label and value for database dashboard
struct DatabaseInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DSColors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
    }
}

/// Health status indicator
struct HealthIndicator: View {
    enum Status {
        case good, warning, bad

        var color: Color {
            switch self {
            case .good: return .green
            case .warning: return .orange
            case .bad: return .red
            }
        }

        var icon: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .bad: return "xmark.circle.fill"
            }
        }
    }

    let label: String
    let status: Status

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs + 2)
        // One width per column and the full row's height, so three chips sit as one row however their labels wrap.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
    }
}

/// A figure inside a card (2026-11-15): the label, a value at `DSTypography.figure`, on the page's background so it
/// reads as a well in the card rather than a card of its own. `IndexStatCard` and `DiagnosticCard` draw through it;
/// they were tinted cards with `.title2` and `.title3` values.
struct FigureTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Label {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            Text(value)
                .font(DSTypography.figure)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
