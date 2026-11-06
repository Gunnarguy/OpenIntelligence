//
//  LibraryIntelligenceCard.swift
//  OpenIntelligence
//
//  Moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

// MARK: - Library Intelligence Card

/// Card showing Auto Intelligence adaptations for a specific library
struct LibraryIntelligenceCard: View {
    let container: KnowledgeContainer
    let intelligenceReport: LibraryIntelligenceCenter.IntelligenceReport?
    /// Whether an analysis is genuinely running for *this* library right now.
    ///
    /// Previously the card inferred it: a nil report plus `autoAdaptDimension` was
    /// rendered as "Analyzing corpus…" with a spinner. Nothing was running. The
    /// dashboard lists every library but only ever requested a report for the active
    /// one, and `containerIntelligence` is in-memory and starts empty every launch,
    /// so most cards showed a progress indicator that could never finish.
    var isAnalyzing: Bool = false
    /// Runs the analysis for this library on demand. It is not automatic because a
    /// refresh opens the library's database and reads up to 4,000 of its passages
    /// (every passage, through 5.6), and doing that for every library on tab appear is
    /// the read-amplification `771461c` removed from sync.
    var onAnalyze: (() -> Void)?
    /// Settings' Technical Details: the card says "chunks" and "corpus" with it on and "passages" without.
    var showsTechnicalDetails: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Header with library info
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: container.icon)
                    .foregroundStyle(Color(hex: container.colorHex) ?? .accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(container.name)
                        .font(.headline)

                    HStack(spacing: DSSpacing.xs) {
                        if container.autoAdaptDimension {
                            Label("Auto", systemImage: "wand.and.stars")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Label("Manual", systemImage: "slider.horizontal.3")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let lastTune = container.lastSelfTuneAt {
                            Text("• Updated \(lastTune, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Status indicator
                Circle()
                    .fill(container.autoAdaptDimension ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Chunking adaptations
            if let report = intelligenceReport {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    if report.corpus.isEstimate {
                        // A large library is measured from a sample of its passages.
                        Text(
                            showsTechnicalDetails
                                ? "Measured from \(report.corpus.analysedChunkCount) of \(report.corpus.chunkCount) chunks"
                                : "Measured from \(report.corpus.analysedChunkCount) of its \(report.corpus.chunkCount) passages")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    // The library analysis's plan is shown and never applied: each import sets its own from a
                    // scan of the new document (`recommendChunkingPlan`), so these rows are what the analysis
                    // suggests, not the library's settings (2026-10-20).
                    Text(
                        showsTechnicalDetails
                            ? "Suggested by the library analysis; each import sets its own plan"
                            : "What the analysis suggests. Each document gets its own when it's added."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    IntelligenceMetricRow(
                        icon: "rectangle.split.3x1",
                        label: showsTechnicalDetails ? "Chunking Strategy" : "Splitting",
                        value: report.chunking.strategy.rawValue.capitalized,
                        color: .accentColor
                    )

                    IntelligenceMetricRow(
                        icon: "textformat.size",
                        label: showsTechnicalDetails ? "Target Chunk Size" : "Passage Length",
                        value: "\(report.chunking.targetWordWindow) words",
                        color: .accentColor
                    )

                    IntelligenceMetricRow(
                        icon: "arrow.left.arrow.right",
                        label: "Overlap",
                        value: "\(report.chunking.overlapWords) words",
                        color: .accentColor
                    )

                    if !report.chunking.rationales.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(showsTechnicalDetails ? "Rationale:" : "Why:")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)

                            ForEach(report.chunking.rationales.prefix(3), id: \.self) { reason in
                                HStack(alignment: .top, spacing: DSSpacing.xs) {
                                    Text("•")
                                        .foregroundStyle(Color.accentColor)
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, DSSpacing.xs)
                    }
                }
            } else if isAnalyzing {
                HStack(spacing: DSSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(showsTechnicalDetails ? "Analyzing corpus…" : "Analyzing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if container.autoAdaptDimension {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Not analyzed yet in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Analyzing a library means opening it and reading up to 4,000 of its passages, so it runs when you ask rather than for all libraries at once.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let onAnalyze {
                        Button {
                            DSHaptics.light()
                            onAnalyze()
                        } label: {
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: "wand.and.stars")
                                    .scaledFont(size: 11, weight: .semibold)
                                Text("Analyze this library")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Manual mode - show current directive
                if let directive = container.chunkingDirective {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        IntelligenceMetricRow(
                            icon: "rectangle.split.3x1",
                            label: showsTechnicalDetails ? "Chunking Strategy" : "Splitting",
                            value: directive.strategy.capitalized,
                            color: .secondary
                        )

                        IntelligenceMetricRow(
                            icon: "textformat.size",
                            label: showsTechnicalDetails ? "Target Chunk Size" : "Passage Length",
                            value: "\(directive.targetWordWindow) words",
                            color: .secondary
                        )

                        IntelligenceMetricRow(
                            icon: "arrow.left.arrow.right",
                            label: "Overlap",
                            value: "\(directive.overlapWords) words",
                            color: .secondary
                        )
                    }
                } else {
                    Text(showsTechnicalDetails ? "Using default chunking settings" : "Using the standard passage length")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Corpus signals if available
            if let report = intelligenceReport {
                Divider()

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(showsTechnicalDetails ? "Corpus Signals" : "What's in It")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: DSSpacing.lg) {
                        CorpusSignalBadge(
                            icon: "doc.text",
                            label: "\(report.corpus.documentCount) docs"
                        )
                        CorpusSignalBadge(
                            icon: "cube.box",
                            label: showsTechnicalDetails ? "\(report.corpus.chunkCount) chunks" : "\(report.corpus.chunkCount) passages"
                        )
                        if report.corpus.hasCode {
                            CorpusSignalBadge(
                                icon: "chevron.left.forwardslash.chevron.right",
                                label: "Code"
                            )
                        }
                        if report.corpus.hasMath {
                            CorpusSignalBadge(
                                icon: "function",
                                label: "Math"
                            )
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .stroke(container.autoAdaptDimension ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

/// Row showing an intelligence metric
struct IntelligenceMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

/// Badge for corpus signals
struct CorpusSignalBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

/// Row explaining how intelligence works
struct IntelligenceExplanationRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
