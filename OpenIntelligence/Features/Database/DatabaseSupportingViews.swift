//
//  DatabaseSupportingViews.swift
//  OpenIntelligence
//
//  Moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

// MARK: - Supporting Views

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
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DatabaseStatusBadge: View {
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(0.15), in: Capsule())
    }
}

struct DatabaseMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                if let trend = trend {
                    Text(trend)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Text(value)
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
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
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: DSSpacing.sm) {
                    Label("Added \(doc.createdAt, style: .relative) ago", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                Text("\(doc.characterCount.formatted()) chars")
                    .font(.caption)
                Text("\(doc.wordCount.formatted()) words")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

struct IndexStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.title2)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

struct TokenizerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
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
                .font(.caption2)
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
                    .font(.subheadline)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

/// Card for diagnostics with icon and color
struct DiagnosticCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Spacer()
            }
            Text(value)
                .font(.title3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

/// Compact stat card for mini metrics
struct MiniStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(value)
                .font(.caption)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

/// Simple info row with label and value for database dashboard
struct DatabaseInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
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
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}
