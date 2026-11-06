//
//  DatabaseDashboardView+Overview.swift
//  OpenIntelligence
//
//  Part of DatabaseDashboardView, moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

extension DatabaseDashboardView {
    // MARK: - Overview Section

    var overviewSection: some View {
        VStack(spacing: DSSpacing.lg) {
            if isLoading {
                ProgressView("Loading database statistics...")
                    .padding(DSSpacing.xxl)
            } else if let stats = stats {
                // Main metrics grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DSSpacing.md) {
                    // Scoped alongside the headline row. Leaving these reading whole-store
                    // totals underneath a scoped header would have moved the confusion
                    // down the page rather than fixed it.
                    DatabaseMetricCard(
                        icon: "doc.text.fill",
                        title: "Documents",
                        value: "\(scopedDocumentCount(stats))",
                        subtitle: scopeSubtitle,
                        color: .accentColor,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "character.cursor.ibeam",
                        title: "Characters",
                        value: formatLargeNumber(scopedCharacterCount(stats)),
                        subtitle: scopeSubtitle,
                        color: .accentColor,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "text.word.spacing",
                        title: "Words",
                        value: formatLargeNumber(scopedWordCount(stats)),
                        subtitle: scopeSubtitle,
                        color: .accentColor,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "internaldrive.fill",
                        title: "Database Size",
                        value: formatBytes(stats.databaseSizeBytes),
                        subtitle: "On disk",
                        color: .accentColor,
                        trend: nil
                    )
                }

                // Quick stats row: storage internals, with Technical Details on.
                if settings.showTechnicalDetails, let diag = deepDiagnostics {
                    HStack(spacing: DSSpacing.sm) {
                        QuickStat(
                            value: "\(diag.pageCount)",
                            label: "Pages",
                            icon: "square.grid.3x3",
                            color: .accentColor
                        )
                        QuickStat(
                            value: "\(diag.pageSize)B",
                            label: "Page Size",
                            icon: "ruler",
                            color: .accentColor
                        )
                        QuickStat(
                            value: diag.journalMode.uppercased(),
                            label: "Journal",
                            icon: "doc.badge.gearshape",
                            color: .accentColor
                        )
                        QuickStat(
                            value: "\(topTerms.count)",
                            label: "Unique Terms",
                            icon: "textformat.abc",
                            color: .accentColor
                        )
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                }

                // Performance card
                performanceCard

                // Container breakdown
                if !stats.containerStats.isEmpty {
                    containerBreakdownCard(stats)
                }

                // Database health indicator
                if let diag = deepDiagnostics {
                    databaseHealthCard(diag)
                }
            } else {
                emptyDatabaseState
            }
        }
    }

    private func databaseHealthCard(_ diag: SQLiteFullTextService.DeepDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: diag.integrityCheckResult.lowercased().contains("ok") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diag.integrityCheckResult.lowercased().contains("ok") ? .green : .red)
                Text("Database Health")
                    .font(.headline)
                Spacer()
                Text(diag.integrityCheckResult.lowercased().contains("ok") ? "Healthy" : "Issues Detected")
                    .font(.caption)
                    .foregroundStyle(diag.integrityCheckResult.lowercased().contains("ok") ? .green : .red)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                HealthIndicator(
                    label: settings.showTechnicalDetails ? "Integrity" : "Index Check",
                    status: diag.integrityCheckResult.lowercased().contains("ok") ? .good : .bad
                )
                HealthIndicator(
                    label: settings.showTechnicalDetails ? "Free Pages" : "Unused Space",
                    status: diag.freePageCount == 0 ? .good : (diag.freePageCount < 100 ? .warning : .bad)
                )
                HealthIndicator(
                    label: settings.showTechnicalDetails ? "WAL Size" : "Write Log",
                    status: diag.walSizeBytes < 10_000_000 ? .good : (diag.walSizeBytes < 100_000_000 ? .warning : .bad)
                )
            }

            if diag.freePageCount > 0 || diag.walSizeBytes > 10_000_000 {
                Text("💡 Consider running Optimize in the Maintenance tab to reclaim space")
                    .font(.caption2)
                    .foregroundStyle(DSColors.readable(.orange))
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    /// How keyword search works. Through 5.6 this card was "Performance Advantage", with "100X", "10X" and
    /// "~500ms to ~5ms" set against a file scan the app no longer has; none of the figures was measured
    /// anywhere in the repository (checked 2026-10-20: BenchmarkRuns/LEDGER.md, Docs, the audits), so they
    /// are gone and the card says what the index does.
    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(DSColors.accent)
                Text(settings.showTechnicalDetails ? "Keyword Index" : "How Keyword Search Works")
                    .font(.headline)
                Spacer()
            }

            if settings.showTechnicalDetails {
                IndexFactRow(
                    title: "Lookup", detail: "SQLite FTS5, an inverted index of each word (tokenizer porter unicode61)")
                Divider()
                IndexFactRow(title: "Ranking", detail: "FTS5's built-in bm25()")
            } else {
                Text(
                    "The app keeps an index of the words in your documents, so a search looks words up instead of reading every passage, and the best matches come first."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    private func containerBreakdownCard(_ stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(DSColors.accent)
                Text("Libraries")
                    .font(.headline)
                Spacer()
                Text("\(stats.containerStats.count) \(stats.containerStats.count == 1 ? "library" : "libraries")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ForEach(stats.containerStats) { container in
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(containerName(for: container.containerId))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(container.documentCount) docs • \(formatLargeNumber(container.totalWords)) words")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(formatLargeNumber(container.totalCharacters))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DSSpacing.xs)

                if container.id != stats.containerStats.last?.id {
                    Divider()
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Documents Section

    var documentsSection: some View {
        VStack(spacing: DSSpacing.lg) {
            if documentStats.isEmpty {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .scaledFont(size: 48)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    Text(settings.showTechnicalDetails ? "No Documents Indexed" : "No Documents Yet")
                        .font(.headline)
                    Text(settings.showTechnicalDetails ? "Add documents to populate the FTS5 index" : "Documents you add are listed here with their words and characters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DSSpacing.xxl)
            } else {
                // Document list header.
                //
                // Names the scope. This read "Indexed Documents" with no library anywhere on it,
                // while the rows underneath were always the active library's regardless of what
                // the scope control said, so choosing All Libraries silently showed one library's
                // documents under a heading that claimed nothing. The rows follow the scope now,
                // and the heading says which scope produced them.
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("Indexed Documents")
                            .font(.headline)
                        Text(scopeLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(documentStats.count) total • Tap to preview")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                // Summary computed from `documentStats`, which is the very list below it.
                //
                // These read `stats.totalWords` and `stats.totalCharacters` — whole-store
                // figures — while sitting on top of a document list that
                // `getDocumentStats(containerId:)` had already scoped to one library. The
                // averages were worse than merely mismatched: "Avg Words/Doc" divided the
                // word count of *every* library by the document count of *one*, so with
                // six libraries it reported a number that described nothing. Deriving all
                // three from the displayed rows makes the summary true by construction.
                HStack(spacing: DSSpacing.md) {
                    MiniStatCard(label: "Words", value: formatLargeNumber(listedWordCount))
                    MiniStatCard(label: "Characters", value: formatLargeNumber(listedCharacterCount))
                    MiniStatCard(
                        label: "Avg Words/Doc",
                        value: documentStats.isEmpty ? "—" : "\(listedWordCount / max(1, documentStats.count))"
                    )
                }

                // Document list
                LazyVStack(spacing: DSSpacing.sm) {
                    ForEach(documentStats) { doc in
                        Button {
                            selectedDocument = doc
                        } label: {
                            DocumentStatRow(doc: doc, documentName: documentName(for: doc.documentId))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Intelligence Section

    var intelligenceSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(DSColors.accent)
                    .font(.title2)
                Text(settings.showTechnicalDetails ? "Auto Intelligence Adaptations" : "How Each Library Is Tuned")
                    .font(.headline)
                Spacer()
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Per-library intelligence cards
            ForEach(containerService.containers) { container in
                LibraryIntelligenceCard(
                    container: container,
                    intelligenceReport: ragService.intelligenceReport(for: container.id),
                    isAnalyzing: analyzingContainerIds.contains(container.id),
                    onAnalyze: { analyzeLibrary(container.id) },
                    showsTechnicalDetails: settings.showTechnicalDetails
                )
            }

            // Explanation card
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(DSColors.accent)
                    Text(settings.showTechnicalDetails ? "How Auto Intelligence Works" : "What the App Adjusts")
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    // Each line says what the code does (2026-10-20): the analysis measures vocabulary richness,
                    // technical density, code, math and structured passages (`analyzeLibrary`); each import sets
                    // its passage plan from a scan of the new document when the library is on Auto
                    // (`recommendChunkingPlan`, RAGService); and the search style follows the library's document
                    // types while it is on Automatic (`RetrievalConfig.autoTuned`). "Optimizes search weights for
                    // your specific corpus" overstated the last: it picks Balanced or Technical Manual.
                    IntelligenceExplanationRow(
                        icon: "doc.text.magnifyingglass",
                        title: settings.showTechnicalDetails ? "Content Analysis" : "What's in a Library",
                        description: settings.showTechnicalDetails
                            ? "Measures vocabulary richness, technical density, code, math and structure (analyzeLibrary)"
                            : "Looks at the words, any code or math, and how the documents are laid out"
                    )
                    IntelligenceExplanationRow(
                        icon: "slider.horizontal.3",
                        title: settings.showTechnicalDetails ? "Adaptive Chunking" : "Passage Length",
                        description: settings.showTechnicalDetails
                            ? "On Auto, each import sets the chunk plan from a scan of the new document (recommendChunkingPlan)"
                            : "On Auto, each document added gets passages sized for its kind of text"
                    )
                    IntelligenceExplanationRow(
                        icon: "arrow.triangle.branch",
                        title: settings.showTechnicalDetails ? "Retrieval Tuning" : "Search Style",
                        description: settings.showTechnicalDetails
                            ? "On Automatic, the search style follows the library's document types (RetrievalConfig.autoTuned)"
                            : "On Automatic, the search style follows the kinds of documents in the library"
                    )
                }

                Text(settings.showTechnicalDetails ? "Each library is analyzed on its own documents" : "Each library is looked at on its own")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, DSSpacing.xs)
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
        }
    }

}
