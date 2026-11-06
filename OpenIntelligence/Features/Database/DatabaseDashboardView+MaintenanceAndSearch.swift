//
//  DatabaseDashboardView+MaintenanceAndSearch.swift
//  OpenIntelligence
//
//  Part of DatabaseDashboardView, moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

extension DatabaseDashboardView {
    // MARK: - Maintenance Section

    var maintenanceSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Integrity check
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Integrity Check")
                        .font(.headline)
                    Spacer()
                    Button("Run Check") {
                        Tour.used(.runCheck)
                        Task {
                            integrityResults = await SQLiteFullTextService.shared.runIntegrityCheck()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tour(.runCheck, in: Tour.database)
                }

                if !integrityResults.isEmpty {
                    ForEach(integrityResults, id: \.self) { result in
                        HStack {
                            Image(systemName: result.lowercased().contains("ok") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.lowercased().contains("ok") ? .green : .red)
                            Text(result)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Run integrity check to verify database health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Optimize database
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Optimize Database")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            isOptimizing = true
                            let result = await SQLiteFullTextService.shared.optimize()
                            if result.success {
                                lastOptimizeResult = "Freed \(formatBytes(result.freedBytes)) in \(String(format: "%.1f", result.elapsedMs))ms"
                            } else {
                                lastOptimizeResult = "Optimization failed"
                            }
                            isOptimizing = false
                            await loadAllData() // Refresh stats
                        }
                    } label: {
                        if isOptimizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Optimize")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isOptimizing)
                }

                Text(settings.showTechnicalDetails ? "Runs VACUUM and FTS5 optimize to reclaim space and merge the index" : "Compacts the index and frees the space it no longer uses")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = lastOptimizeResult {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Rebuild index
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.red)
                    Text("Rebuild Index")
                        .font(.headline)
                    Spacer()

                    if !rebuildLogs.isEmpty {
                        Button {
                            withAnimation(DSAnimations.snappySpring) {
                                showRebuildLog.toggle()
                            }
                        } label: {
                            HStack(spacing: DSSpacing.xs) {
                                Image(systemName: showRebuildLog ? "chevron.up" : "chevron.down")
                                Text("Log")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        Task {
                            await performDetailedRebuild()
                        }
                    } label: {
                        if isRebuildingIndex {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Rebuild")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(isRebuildingIndex)
                }

                // `SQLiteFullTextService.rebuildIndex` runs FTS5's rebuild on the whole-document table only, not on the
                // passage table that answers questions; "Completely rebuilds the FTS5 index" said otherwise (2026-10-20).
                Text(settings.showTechnicalDetails ? "⚠️ Rebuilds the documents FTS5 table from its stored text; the chunks table is not rebuilt." : "⚠️ Builds the whole-document word index again from its stored text. The index that answers questions by passage isn't touched.")
                    .font(.caption)
                    .foregroundStyle(.orange)

                // Live rebuild log
                if showRebuildLog && !rebuildLogs.isEmpty {
                    rebuildLogView
                }

                // Current status during rebuild
                if isRebuildingIndex, let lastLog = rebuildLogs.last {
                    HStack(spacing: DSSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text(lastLog.message)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, DSSpacing.xs)
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Database info
            if let diag = deepDiagnostics {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Database Info")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        if settings.showTechnicalDetails {
                            DatabaseInfoRow(label: "Journal Mode", value: diag.journalMode.uppercased())
                            DatabaseInfoRow(label: "Auto Vacuum", value: diag.autoVacuum)
                        }
                        DatabaseInfoRow(label: settings.showTechnicalDetails ? "Integrity" : "Index Check", value: diag.integrityCheckResult)
                        if settings.showTechnicalDetails {
                            DatabaseInfoRow(label: "Page Count", value: "\(diag.pageCount)")
                            DatabaseInfoRow(label: "Free Pages", value: "\(diag.freePageCount)")
                        }

                        if diag.freePageCount > 0 {
                            let wastedBytes = Int64(diag.freePageCount * diag.pageSize)
                            Text("💡 \(formatBytes(wastedBytes)) could be reclaimed with Optimize")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }
        }
    }

    // MARK: - Search Section

    var searchSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(settings.showTechnicalDetails ? "Search FTS5 index..." : "Search for words in your documents…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await performSearch() }
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DSSpacing.lg)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Search tips
            if searchResults.isEmpty && searchQuery.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(settings.showTechnicalDetails ? "FTS5 Query Syntax" : "Ways to Search")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        SearchTip(syntax: "word1 word2", description: "Match documents containing both words (AND)")
                        SearchTip(syntax: "\"exact phrase\"", description: "Match exact phrase in order")
                        SearchTip(syntax: "word1 OR word2", description: "Match either word")
                        SearchTip(syntax: "word1 NOT word2", description: "Match word1, exclude word2")
                        SearchTip(syntax: "word*", description: "Prefix matching (wildcard)")
                        SearchTip(syntax: "NEAR(word1 word2, 5)", description: "Words within 5 tokens of each other")
                        SearchTip(syntax: "^word", description: "Match at start of column")
                        SearchTip(syntax: "word + word2", description: "word2 must follow word (adjacent)")
                    }

                    Text(settings.showTechnicalDetails ? "Queries are case-insensitive. BM25 ranking is used for relevance scoring." : "Capital letters don't matter, and the best matches come first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, DSSpacing.xs)
                }
                .padding(DSSpacing.lg)
                .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            }

            // Search performance metrics
            if let metrics = searchMetrics {
                HStack(spacing: DSSpacing.md) {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(String(format: "%.2f ms", metrics.queryLatencyMs))
                            .font(.caption.monospacedDigit())
                    }
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("\(metrics.documentsScanned) scanned")
                            .font(.caption)
                    }
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(metrics.resultsReturned) returned")
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.lg)
            }

            // Search results
            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    HStack {
                        Text("Results")
                            .font(.headline)
                        Spacer()
                        Text("\(searchResults.count) matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(searchResults, id: \.documentId) { result in
                        SearchResultRow(result: result, documentName: documentName(for: result.documentId))
                    }
                }
            }
        }
    }

    var emptyDatabaseState: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "cylinder")
                .scaledFont(size: 64)
                .foregroundStyle(.secondary.opacity(0.4))

            Text(settings.showTechnicalDetails ? "Database Empty" : "No Documents Yet")
                .font(.title2)

            Text(settings.showTechnicalDetails ? "Add documents to populate the SQLite FTS5 full-text search index" : "Add documents and their words show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xxl)
        }
        .padding(DSSpacing.xxl)
        .frame(maxWidth: .infinity)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    // MARK: - Helpers

    func loadStatistics() async {
        isLoading = true
        let service = SQLiteFullTextService.shared
        stats = await service.getStatistics()
        indexInfo = await service.getIndexInfo()
        documentStats = await loadDocumentStats(for: scopedContainerId)
        isLoading = false
    }

    private func performSearch() async {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        let service = SQLiteFullTextService.shared

        // Use timed search to get performance metrics
        let (results, metrics) = await service.timedSearch(
            query: searchQuery,
            containerId: scopedContainerId,
            limit: 50
        )
        searchResults = results
        searchMetrics = metrics
        isSearching = false
    }

    func formatLargeNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func compressionColor(_ ratio: Double) -> Color {
        if ratio < 0.3 { return .green }
        else if ratio < 0.6 { return .accentColor }
        else if ratio < 0.9 { return .orange }
        else { return .red }
    }

    func containerName(for containerId: UUID) -> String {
        containerNameMap[containerId] ?? "Unknown"
    }

    func documentName(for documentId: UUID) -> String {
        documentNameMap[documentId] ?? String(documentId.uuidString.prefix(8)) + "..."
    }

    func updateMaps() {
        containerNameMap = Dictionary(uniqueKeysWithValues: containerService.containers.map { ($0.id, $0.name) })
        documentNameMap = Dictionary(uniqueKeysWithValues: ragService.documents.map { ($0.id, $0.filename) })
    }

    // MARK: - Rebuild Log View

    private var rebuildLogView: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("🔧 Rebuild Log")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(rebuildLogs.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    rebuildLogs = []
                    showRebuildLog = false
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(rebuildLogs) { entry in
                        HStack(alignment: .top, spacing: DSSpacing.sm) {
                            Image(systemName: entry.type.icon)
                                .font(.caption2)
                                .foregroundStyle(entry.type.color)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                Text(entry.timestamp, style: .time)
                                    .scaledFont(size: 9)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, DSSpacing.xxs)
                    }
                }
                .padding(.horizontal, DSSpacing.sm)
            }
            .frame(maxHeight: 200)
            .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
        }
        .padding(.top, DSSpacing.sm)
    }

    // MARK: - Detailed Rebuild Process

    private func performDetailedRebuild() async {
        isRebuildingIndex = true
        showRebuildLog = true
        rebuildLogs = []

        let service = SQLiteFullTextService.shared

        // Step 1: Pre-flight checks
        addLog("Starting FTS5 index rebuild...", type: .info)
        await Task.yield()

        // Get pre-rebuild stats
        addLog("📊 Gathering pre-rebuild statistics...", type: .step)
        let preStats = await service.getStatistics()
        addLog("  Documents: \(preStats.totalDocuments)", type: .info)
        addLog("  Words: \(formatLargeNumber(preStats.totalWords))", type: .info)
        addLog("  Characters: \(formatLargeNumber(preStats.totalCharacters))", type: .info)
        await Task.yield()

        // Step 2: Check current index health
        addLog("🔍 Running pre-rebuild integrity check...", type: .step)
        await Task.yield()
        let preIntegrity = await service.runIntegrityCheck()
        for result in preIntegrity.prefix(3) {
            addLog("  \(result)", type: result.contains("OK") ? .success : .warning)
        }
        await Task.yield()

        // Step 3: Get index info before rebuild
        addLog("📈 Capturing index metadata...", type: .step)
        let indexInfo = await service.getIndexInfo()
        addLog("  Unique terms: \(formatLargeNumber(indexInfo.uniqueTerms))", type: .info)
        addLog("  Total occurrences: \(formatLargeNumber(indexInfo.totalTerms))", type: .info)
        addLog("  Avg term frequency: \(String(format: "%.2f", indexInfo.averageTermFrequency))", type: .info)
        await Task.yield()

        // Step 4: Begin the actual rebuild
        addLog("⚡ Rebuilding database from canonical state...", type: .step)
        addLog("  Reading documents from shared workspace and importing all chunks...", type: .info)
        await Task.yield()

        let startTime = CFAbsoluteTimeGetCurrent()
        let success = await ragService.rebuildDatabase()
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if success {
            addLog("✅ Canonical rebuild completed successfully", type: .success)
            addLog("  Elapsed: \(String(format: "%.2f", elapsed))ms", type: .info)
        } else {
            addLog("❌ Canonical rebuild failed", type: .error)
        }
        await Task.yield()

        // Step 5: Post-rebuild verification
        addLog("🔍 Running post-rebuild integrity check...", type: .step)
        let postIntegrity = await service.runIntegrityCheck()
        for result in postIntegrity.prefix(3) {
            addLog("  \(result)", type: result.contains("OK") ? .success : .warning)
        }
        await Task.yield()

        // Step 6: Compare stats
        addLog("📊 Verifying post-rebuild statistics...", type: .step)
        let postStats = await service.getStatistics()
        let docMatch = preStats.totalDocuments == postStats.totalDocuments
        let wordMatch = preStats.totalWords == postStats.totalWords
        addLog("  Documents: \(postStats.totalDocuments) \(docMatch ? "✓" : "⚠️ changed")", type: docMatch ? .success : .warning)
        addLog("  Words: \(formatLargeNumber(postStats.totalWords)) \(wordMatch ? "✓" : "⚠️ changed")", type: wordMatch ? .success : .warning)
        await Task.yield()

        // Step 7: Final summary
        addLog("", type: .info)
        if success {
            addLog("🎉 Database rebuild completed successfully!", type: .success)
            addLog("  Total time: \(String(format: "%.2f", elapsed))ms", type: .info)
            lastOptimizeResult = "Database rebuilt in \(String(format: "%.1f", elapsed))ms"
        } else {
            addLog("⚠️ Database rebuild encountered issues", type: .error)
        }

        isRebuildingIndex = false
        await loadAllData()
    }

    private func addLog(_ message: String, type: RebuildLogEntry.LogType) {
        rebuildLogs.append(RebuildLogEntry(timestamp: Date(), message: message, type: type))
    }
}
