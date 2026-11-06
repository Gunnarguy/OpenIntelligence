//
//  DatabaseDashboardView+Index.swift
//  OpenIntelligence
//
//  Part of DatabaseDashboardView, moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

extension DatabaseDashboardView {
    // MARK: - Index Section

    var indexSection: some View {
        VStack(spacing: DSSpacing.lg) {
            if let indexInfo = indexInfo {
                // Term statistics
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    HStack {
                        Image(systemName: "text.book.closed.fill")
                            .foregroundStyle(DSColors.accent)
                        Text("Vocabulary Statistics")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                        IndexStatCard(
                            title: "Unique Terms",
                            value: formatLargeNumber(indexInfo.uniqueTerms),
                            icon: "textformat.abc",
                            color: .accentColor
                        )

                        IndexStatCard(
                            title: "Total Occurrences",
                            value: formatLargeNumber(indexInfo.totalTerms),
                            icon: "number",
                            color: .accentColor
                        )

                        IndexStatCard(
                            title: "Avg Frequency",
                            value: String(format: "%.1f", indexInfo.averageTermFrequency),
                            icon: "chart.line.uptrend.xyaxis",
                            color: .accentColor
                        )

                        IndexStatCard(
                            title: "Compression",
                            value: String(format: "%.0f%%", indexInfo.compressionRatio * 100),
                            icon: "arrow.down.right.and.arrow.up.left",
                            color: compressionColor(indexInfo.compressionRatio)
                        )
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                // Tokenizer info
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "scissors")
                            .foregroundStyle(DSColors.accent)
                        Text("Tokenizer Configuration")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        TokenizerInfoRow(label: "Tokenizer", value: "porter unicode61")
                        TokenizerInfoRow(label: "Stemming", value: "English Porter Stemmer")
                        TokenizerInfoRow(label: "Case Handling", value: "Case-insensitive (Unicode)")
                        TokenizerInfoRow(label: "Ranking", value: "BM25 (built-in)")
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                // FTS5 features
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(DSColors.accent)
                        Text("FTS5 Capabilities")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                        FeatureBadge(name: "MATCH Queries", enabled: true)
                        FeatureBadge(name: "bm25() Ranking", enabled: true)
                        FeatureBadge(name: "snippet()", enabled: true)
                        FeatureBadge(name: "highlight()", enabled: true)
                        FeatureBadge(name: "Phrase Search", enabled: true)
                        FeatureBadge(name: "Prefix Search", enabled: true)
                        FeatureBadge(name: "NEAR Queries", enabled: true)
                        FeatureBadge(name: "Column Filters", enabled: true)
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            } else {
                ProgressView("Loading index info...")
                    .padding(DSSpacing.xxl)
            }
        }
    }

    // MARK: - Vocabulary Section (Power User)

    var vocabularySection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Top terms
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "textformat.abc")
                        .foregroundStyle(DSColors.accent)
                    Text("Top 100 Terms by Frequency")
                        .font(.headline)
                    Spacer()
                    Text("\(topTerms.count) terms")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if topTerms.isEmpty {
                    Text("No vocabulary data yet. Add documents to populate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(DSSpacing.lg)
                } else {
                    // Term frequency chart
                    Chart(topTerms.prefix(20)) { term in
                        BarMark(
                            x: .value("Occurrences", term.totalOccurrences),
                            y: .value("Term", term.term)
                        )
                        .foregroundStyle(DSColors.accent.gradient)
                    }
                    .chartXAxisLabel("Total Occurrences")
                    .frame(height: 400)

                    Divider()

                    // Full term list
                    LazyVStack(spacing: DSSpacing.xs) {
                        HStack {
                            Text("Term")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Docs")
                                .font(.caption.weight(.semibold))
                                .frame(width: 60)
                            Text("Total")
                                .font(.caption.weight(.semibold))
                                .frame(width: 60)
                        }
                        .foregroundStyle(.secondary)

                        ForEach(topTerms) { term in
                            HStack {
                                Text(term.term)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(term.documentFrequency)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 60)
                                Text("\(term.totalOccurrences)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DSColors.accent)
                                    .frame(width: 60)
                            }
                        }
                    }
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Term distribution histogram
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(DSColors.accent)
                    Text("Term Frequency Distribution")
                        .font(.headline)
                    Spacer()
                }

                if !termDistribution.isEmpty {
                    Chart(termDistribution, id: \.bucket) { dist in
                        BarMark(
                            x: .value("Bucket", dist.bucket),
                            y: .value("Terms", dist.termCount)
                        )
                        .foregroundStyle(DSColors.accent.gradient)
                    }
                    .chartYAxisLabel("Number of Terms")
                    .chartXAxisLabel("Occurrence Count")
                    .frame(height: 200)

                    Text("Shows how many terms appear with each frequency range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
    }

    // MARK: - Performance Section

    var performanceSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Deep diagnostics header
            if let diag = deepDiagnostics {
                // Database file info
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundStyle(DSColors.accent)
                        Text("Storage Details")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                        DiagnosticCard(label: "Database", value: formatBytes(diag.databaseSizeBytes), icon: "cylinder.fill", color: .accentColor)
                        DiagnosticCard(label: "WAL File", value: formatBytes(diag.walSizeBytes), icon: "doc.fill", color: .accentColor)
                        DiagnosticCard(label: "SHM File", value: formatBytes(diag.shmSizeBytes), icon: "doc.fill", color: .accentColor)
                        DiagnosticCard(label: "Total", value: formatBytes(diag.databaseSizeBytes + diag.walSizeBytes + diag.shmSizeBytes), icon: "externaldrive.fill", color: .accentColor)
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                // Page statistics
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundStyle(DSColors.accent)
                        Text("Page Statistics")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                        MiniStatCard(label: "Page Size", value: "\(diag.pageSize) B")
                        MiniStatCard(label: "Pages", value: "\(diag.pageCount)")
                        MiniStatCard(label: "Free Pages", value: "\(diag.freePageCount)")
                        MiniStatCard(label: "Schema Ver", value: "\(diag.schemaVersion)")
                        MiniStatCard(label: "Cache Size", value: "\(abs(diag.cacheSize))")
                        MiniStatCard(label: "MMap", value: formatBytes(diag.mMapSize))
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                // SQLite settings
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundStyle(.secondary)
                        Text("SQLite Configuration")
                            .font(.headline)
                        Spacer()
                    }

                    ForEach(Array(diag.pragmaSettings.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(diag.pragmaSettings[key] ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Divider()

                    // Database path
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Database Path")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(diag.databasePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                // Table stats
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "tablecells.fill")
                            .foregroundStyle(DSColors.accent)
                        Text("Table Statistics")
                            .font(.headline)
                        Spacer()
                    }

                    ForEach(diag.tableStats) { table in
                        HStack {
                            Text(table.name)
                                .font(.caption)
                            Spacer()
                            Text("\(table.rowCount) rows")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("~\(formatBytes(table.estimatedSize))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DSColors.accent)
                        }
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            } else {
                ProgressView("Loading diagnostics...")
                    .padding(DSSpacing.xxl)
            }

            // Search performance test
            if let metrics = searchMetrics {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundStyle(.green)
                        Text("Last Search Performance")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                        DiagnosticCard(label: "Latency", value: String(format: "%.2f ms", metrics.queryLatencyMs), icon: "clock.fill", color: .accentColor)
                        DiagnosticCard(label: "Docs Scanned", value: "\(metrics.documentsScanned)", icon: "doc.text.magnifyingglass", color: .accentColor)
                        DiagnosticCard(label: "Results", value: "\(metrics.resultsReturned)", icon: "list.bullet", color: .accentColor)
                        DiagnosticCard(label: "Index Hits", value: "\(metrics.indexHits)", icon: "target", color: .accentColor)
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        }
    }

}
