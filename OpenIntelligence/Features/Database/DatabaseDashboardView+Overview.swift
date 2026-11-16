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
                // The scope's figures as wells in one card (2026-11-15), as Vocabulary Statistics shows its own. They
                // were four cards with `.title` numbers under a panel that states three of them already. Scoped
                // alongside the panel: leaving these reading whole-store totals underneath a scoped header would
                // have moved the confusion down the page rather than fixed it.
                DatabaseCard(icon: "chart.bar.doc.horizontal", title: "Contents", caption: scopeSubtitle) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                        FigureTile(
                            title: "Documents", value: "\(scopedDocumentCount(stats))", icon: "doc.text.fill",
                            color: .accentColor)
                        FigureTile(
                            title: "Characters", value: formatLargeNumber(scopedCharacterCount(stats)),
                            icon: "character.cursor.ibeam", color: .accentColor)
                        FigureTile(
                            title: "Words", value: formatLargeNumber(scopedWordCount(stats)), icon: "text.word.spacing",
                            color: .accentColor)
                        FigureTile(
                            title: "Size on disk, all", value: formatBytes(stats.databaseSizeBytes),
                            icon: "internaldrive.fill", color: .accentColor)
                    }
                }

                // Quick stats row: storage internals, with Technical Details on.
                if settings.showTechnicalDetails, let diag = deepDiagnostics {
                    SurfaceCard {
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
                    }
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
        let healthy = diag.integrityCheckResult.lowercased().contains("ok")
        return DatabaseCard(icon: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", title: "Database Health") {
            Text(healthy ? "Healthy" : "Issues Detected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColors.readable(healthy ? .green : .red))
        } content: {
            // One row of equal chips: the row takes its tallest label's height and each chip fills it (2026-11-15).
            HStack(spacing: DSSpacing.sm) {
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
            .fixedSize(horizontal: false, vertical: true)

            if diag.freePageCount > 0 || diag.walSizeBytes > 10_000_000 {
                Label("Consider running Optimize in the Maintenance tab to reclaim space", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(DSColors.readable(.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How keyword search works. Through 5.6 this card was "Performance Advantage", with "100X", "10X" and
    /// "~500ms to ~5ms" set against a file scan the app no longer has; none of the figures was measured
    /// anywhere in the repository (checked 2026-10-20: BenchmarkRuns/LEDGER.md, Docs, the audits), so they
    /// are gone and the card says what the index does.
    private var performanceCard: some View {
        DatabaseCard(icon: "bolt.fill", title: settings.showTechnicalDetails ? "Keyword Index" : "How Keyword Search Works") {
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
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func containerBreakdownCard(_ stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        DatabaseCard(icon: "square.stack.3d.up.fill", title: "Libraries") {
            Text("\(stats.containerStats.count) \(stats.containerStats.count == 1 ? "library" : "libraries")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(DSColors.secondaryText)
        } content: {
            ForEach(stats.containerStats) { container in
                HStack {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(containerName(for: container.containerId))
                            .font(.subheadline.weight(.medium))
                        Text("\(container.documentCount) docs • \(formatLargeNumber(container.totalWords)) words")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.secondaryText)
                    }

                    Spacer()

                    Text("\(formatLargeNumber(container.totalCharacters)) chars")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.secondaryText)
                }

                if container.id != stats.containerStats.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Documents Section

    var documentsSection: some View {
        VStack(spacing: DSSpacing.lg) {
            if documentStats.isEmpty {
                SurfaceCard {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(settings.showTechnicalDetails ? "No Documents Indexed" : "No Documents Yet")
                        .font(.headline)
                    Text(settings.showTechnicalDetails ? "Add documents to populate the FTS5 index" : "Documents you add are listed here with their words and characters.")
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, DSSpacing.lg)
                .frame(maxWidth: .infinity)
                }
            } else {
                // Document list header.
                //
                // Names the scope. This read "Indexed Documents" with no library anywhere on it,
                // while the rows underneath were always the active library's regardless of what
                // the scope control said, so choosing All Libraries silently showed one library's
                // documents under a heading that claimed nothing. The rows follow the scope now,
                // and the heading says which scope produced them.
                DatabaseCard(icon: "doc.text.fill", title: "Indexed Documents", caption: scopeLabel) {
                    Text("\(documentStats.count) total")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.secondaryText)
                } content: {

                // Summary computed from `documentStats`, which is the very list below it.
                //
                // These read `stats.totalWords` and `stats.totalCharacters` — whole-store
                // figures — while sitting on top of a document list that
                // `getDocumentStats(containerId:)` had already scoped to one library. The
                // averages were worse than merely mismatched: "Avg Words/Doc" divided the
                // word count of *every* library by the document count of *one*, so with
                // six libraries it reported a number that described nothing. Deriving all
                // three from the displayed rows makes the summary true by construction.
                HStack(spacing: DSSpacing.sm) {
                    MiniStatCard(label: "Words", value: formatLargeNumber(listedWordCount))
                    MiniStatCard(label: "Characters", value: formatLargeNumber(listedCharacterCount))
                    MiniStatCard(
                        label: "Avg Words/Doc",
                        value: documentStats.isEmpty ? "—" : "\(listedWordCount / max(1, documentStats.count))"
                    )
                }

                Text("Tap a document to preview it")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)

                // Document list: rows in the card, divided as a list's are.
                LazyVStack(spacing: 0) {
                    ForEach(documentStats) { doc in
                        Button {
                            selectedDocument = doc
                        } label: {
                            DocumentStatRow(doc: doc, documentName: documentName(for: doc.documentId))
                        }
                        .buttonStyle(.plain)
                        if doc.id != documentStats.last?.id {
                            Divider()
                        }
                    }
                }
                }
            }
        }
    }

    // MARK: - Intelligence Section

    var intelligenceSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // The page's section title, at `.headline` on the page (2026-11-15); it was a card of its own.
            Label(
                settings.showTechnicalDetails ? "Auto Intelligence Adaptations" : "How Each Library Is Tuned",
                systemImage: "wand.and.stars"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)

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
            DatabaseCard(
                icon: "lightbulb.fill",
                title: settings.showTechnicalDetails ? "How Auto Intelligence Works" : "What the App Adjusts"
            ) {
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
                    .foregroundStyle(DSColors.secondaryText)
            }
        }
    }

}
