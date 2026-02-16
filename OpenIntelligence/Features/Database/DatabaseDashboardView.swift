//
//  DatabaseDashboardView.swift
//  OpenIntelligence
//
//  Dedicated dashboard for SQLite FTS5 full-text search database
//  Provides visibility into the inverted index, document storage, and search performance
//

import Charts
import SwiftUI

/// Main dashboard for SQLite FTS5 database inspection and management
struct DatabaseDashboardView: View {
    @EnvironmentObject private var ragService: RAGService
    @EnvironmentObject private var containerService: ContainerService
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectedSection: DatabaseSection = .overview
    @State private var stats: SQLiteFullTextService.FTS5Statistics?
    @State private var indexInfo: SQLiteFullTextService.FTS5IndexInfo?
    @State private var documentStats: [SQLiteFullTextService.DocumentStat] = []
    @State private var isLoading = true
    @State private var searchQuery = ""
    @State private var searchResults: [FTS5SearchResult] = []
    @State private var isSearching = false

    // Advanced diagnostics
    @State private var deepDiagnostics: SQLiteFullTextService.DeepDiagnostics?
    @State private var topTerms: [SQLiteFullTextService.TermFrequency] = []
    @State private var termDistribution: [SQLiteFullTextService.TermDistribution] = []
    @State private var docLengthStats: [SQLiteFullTextService.DocumentLengthStat] = []
    @State private var searchMetrics: SQLiteFullTextService.SearchPerformanceMetrics?
    @State private var integrityResults: [String] = []
    @State private var isOptimizing = false
    @State private var isRebuildingIndex = false
    @State private var lastOptimizeResult: String?
    @State private var selectedDocument: SQLiteFullTextService.DocumentStat?
    @State private var documentPreview: String?
    @State private var rebuildLogs: [RebuildLogEntry] = []
    @State private var showRebuildLog = false

    struct RebuildLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType

        enum LogType {
            case info, success, warning, error, step

            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.circle.fill"
                case .step: return "arrow.right.circle"
                }
            }

            var color: Color {
                switch self {
                case .info: return .blue
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                case .step: return .purple
                }
            }
        }
    }

    enum DatabaseSection: String, CaseIterable, Identifiable {
        case overview
        case intelligence
        case documents
        case vocabulary
        case index
        case performance
        case maintenance
        case search

        var id: String { rawValue }

        var label: String {
            switch self {
            case .overview: return "Overview"
            case .intelligence: return "Intelligence"
            case .documents: return "Documents"
            case .vocabulary: return "Vocabulary"
            case .index: return "Index"
            case .performance: return "Performance"
            case .maintenance: return "Maintenance"
            case .search: return "Search"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.doc.horizontal"
            case .intelligence: return "wand.and.stars"
            case .documents: return "doc.text.fill"
            case .vocabulary: return "textformat.abc"
            case .index: return "list.bullet.indent"
            case .performance: return "gauge.with.dots.needle.33percent"
            case .maintenance: return "wrench.and.screwdriver.fill"
            case .search: return "magnifyingglass"
            }
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Section picker
                    sectionPicker

                    // Content based on selection
                    switch selectedSection {
                    case .overview:
                        overviewSection
                    case .intelligence:
                        intelligenceSection
                    case .documents:
                        documentsSection
                    case .vocabulary:
                        vocabularySection
                    case .index:
                        indexSection
                    case .performance:
                        performanceSection
                    case .maintenance:
                        maintenanceSection
                    case .search:
                        searchSection
                    }
                }
                .padding()
            }
            .background(DSColors.background.ignoresSafeArea())

            // Motherboard HUD - Full-screen X-ray overlay
            // Shows glowing borders at the ACTUAL physical locations where
            // the Neural Engine, GPU, and CPU sit behind the screen
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false) // Don't block touches
                    .transition(.opacity)
            }
        }
        .navigationTitle("Database")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadAllData()
        }
        .refreshable {
            await loadAllData()
        }
        .sheet(item: $selectedDocument) { doc in
            DocumentPreviewSheet(
                documentId: doc.documentId,
                documentName: documentName(for: doc.documentId),
                characterCount: doc.characterCount,
                wordCount: doc.wordCount
            )
        }
    }

    // MARK: - Load All Data

    private func loadAllData() async {
        isLoading = true
        let service = SQLiteFullTextService.shared

        // Load in parallel
        async let statsTask = service.getStatistics()
        async let indexTask = service.getIndexInfo()
        async let docsTask = service.getDocumentStats(containerId: containerService.activeContainerId)
        async let diagTask = service.getDeepDiagnostics()
        async let termsTask = service.getTopTerms(limit: 100)
        async let distTask = service.getTermDistribution()

        stats = await statsTask
        indexInfo = await indexTask
        documentStats = await docsTask
        deepDiagnostics = await diagTask
        topTerms = await termsTask
        termDistribution = await distTask

        isLoading = false
    }
    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("SQLite FTS5")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Full-Text Search Engine")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let stats = stats {
                    DatabaseStatusBadge(
                        status: stats.indexStatus,
                        color: stats.totalDocuments > 0 ? .green : .orange
                    )
                }
            }

            // Quick stats row
            if let stats = stats {
                HStack(spacing: 16) {
                    QuickStat(value: "\(stats.totalDocuments)", label: "Docs", icon: "doc.fill", color: .blue)
                    QuickStat(value: formatLargeNumber(stats.totalWords), label: "Words", icon: "textformat", color: .green)
                    QuickStat(value: formatBytes(stats.databaseSizeBytes), label: "Size", icon: "externaldrive.fill", color: .orange)
                    if let indexInfo = indexInfo {
                        QuickStat(value: formatLargeNumber(indexInfo.uniqueTerms), label: "Terms", icon: "list.bullet", color: .purple)
                    }
                }
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(16)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DatabaseSection.allCases) { section in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.icon)
                            Text(section.label)
                        }
                        .font(.subheadline)
                        .fontWeight(selectedSection == section ? .semibold : .regular)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            selectedSection == section
                                ? Color.accentColor.opacity(0.15)
                                : Color.gray.opacity(0.1)
                        )
                        .foregroundColor(selectedSection == section ? .accentColor : .secondary)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView("Loading database statistics...")
                    .padding(40)
            } else if let stats = stats {
                // Main metrics grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    DatabaseMetricCard(
                        icon: "doc.text.fill",
                        title: "Total Documents",
                        value: "\(stats.totalDocuments)",
                        subtitle: "Indexed in FTS5",
                        color: .blue,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "character.cursor.ibeam",
                        title: "Total Characters",
                        value: formatLargeNumber(stats.totalCharacters),
                        subtitle: "Stored text",
                        color: .purple,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "text.word.spacing",
                        title: "Total Words",
                        value: formatLargeNumber(stats.totalWords),
                        subtitle: "Searchable tokens",
                        color: .green,
                        trend: nil
                    )

                    DatabaseMetricCard(
                        icon: "internaldrive.fill",
                        title: "Database Size",
                        value: formatBytes(stats.databaseSizeBytes),
                        subtitle: "On disk",
                        color: .orange,
                        trend: nil
                    )
                }

                // Quick stats row
                if let diag = deepDiagnostics {
                    HStack(spacing: 8) {
                        QuickStat(
                            value: "\(diag.pageCount)",
                            label: "Pages",
                            icon: "square.grid.3x3",
                            color: .blue
                        )
                        QuickStat(
                            value: "\(diag.pageSize)B",
                            label: "Page Size",
                            icon: "ruler",
                            color: .green
                        )
                        QuickStat(
                            value: diag.journalMode.uppercased(),
                            label: "Journal",
                            icon: "doc.badge.gearshape",
                            color: .purple
                        )
                        QuickStat(
                            value: "\(topTerms.count)",
                            label: "Unique Terms",
                            icon: "textformat.abc",
                            color: .orange
                        )
                    }
                    .padding()
                    .background(DSColors.surface)
                    .cornerRadius(12)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: diag.integrityCheckResult.lowercased().contains("ok") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(diag.integrityCheckResult.lowercased().contains("ok") ? .green : .red)
                Text("Database Health")
                    .font(.headline)
                Spacer()
                Text(diag.integrityCheckResult.lowercased().contains("ok") ? "Healthy" : "Issues Detected")
                    .font(.caption)
                    .foregroundColor(diag.integrityCheckResult.lowercased().contains("ok") ? .green : .red)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                HealthIndicator(
                    label: "Integrity",
                    status: diag.integrityCheckResult.lowercased().contains("ok") ? .good : .bad
                )
                HealthIndicator(
                    label: "Free Pages",
                    status: diag.freePageCount == 0 ? .good : (diag.freePageCount < 100 ? .warning : .bad)
                )
                HealthIndicator(
                    label: "WAL Size",
                    status: diag.walSizeBytes < 10_000_000 ? .good : (diag.walSizeBytes < 100_000_000 ? .warning : .bad)
                )
            }

            if diag.freePageCount > 0 || diag.walSizeBytes > 10_000_000 {
                Text("💡 Consider running Optimize in the Maintenance tab to reclaim space")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("Performance Advantage")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 12) {
                PerformanceComparisonRow(
                    operation: "Pattern Counting",
                    oldMethod: "O(n) file scan",
                    newMethod: "O(log n) index",
                    speedup: "100X"
                )

                Divider()

                PerformanceComparisonRow(
                    operation: "BM25 Scoring",
                    oldMethod: "Rebuild each query",
                    newMethod: "Native bm25()",
                    speedup: "10X"
                )

                Divider()

                PerformanceComparisonRow(
                    operation: "Keyword Search",
                    oldMethod: "Linear scan ~500ms",
                    newMethod: "Inverted index ~5ms",
                    speedup: "100X"
                )
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }

    private func containerBreakdownCard(_ stats: SQLiteFullTextService.FTS5Statistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.indigo)
                Text("Container Breakdown")
                    .font(.headline)
                Spacer()
                Text("\(stats.containerStats.count) containers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(stats.containerStats) { container in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(containerName(for: container.containerId))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(container.documentCount) docs • \(formatLargeNumber(container.totalWords)) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(formatLargeNumber(container.totalCharacters))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)

                if container.id != stats.containerStats.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }

    // MARK: - Documents Section

    private var documentsSection: some View {
        VStack(spacing: 16) {
            if documentStats.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Documents Indexed")
                        .font(.headline)
                    Text("Add documents to populate the FTS5 index")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(40)
            } else {
                // Document list header
                HStack {
                    Text("Indexed Documents")
                        .font(.headline)
                    Spacer()
                    Text("\(documentStats.count) total • Tap to preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Summary stats
                if let stats = stats {
                    HStack(spacing: 12) {
                        MiniStatCard(label: "Total Words", value: formatLargeNumber(stats.totalWords))
                        MiniStatCard(label: "Total Chars", value: formatLargeNumber(stats.totalCharacters))
                        MiniStatCard(label: "Avg Words/Doc", value: documentStats.isEmpty ? "—" : "\(stats.totalWords / max(1, documentStats.count))")
                    }
                }

                // Document list
                LazyVStack(spacing: 8) {
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

    private var intelligenceSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                    .font(.title2)
                Text("Auto Intelligence Adaptations")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Per-library intelligence cards
            ForEach(containerService.containers) { container in
                LibraryIntelligenceCard(
                    container: container,
                    intelligenceReport: ragService.intelligenceReport(for: container.id)
                )
            }

            // Explanation card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("How Auto Intelligence Works")
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 8) {
                    IntelligenceExplanationRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Content Analysis",
                        description: "Scans vocabulary richness, code density, and document structure"
                    )
                    IntelligenceExplanationRow(
                        icon: "slider.horizontal.3",
                        title: "Adaptive Chunking",
                        description: "Adjusts chunk size and overlap based on content type"
                    )
                    IntelligenceExplanationRow(
                        icon: "arrow.triangle.branch",
                        title: "Retrieval Tuning",
                        description: "Optimizes search weights for your specific corpus"
                    )
                }

                Text("Each library learns independently from its documents")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)
        }
    }

    // MARK: - Index Section

    private var indexSection: some View {
        VStack(spacing: 16) {
            if let indexInfo = indexInfo {
                // Term statistics
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "text.book.closed.fill")
                            .foregroundColor(.blue)
                        Text("Vocabulary Statistics")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        IndexStatCard(
                            title: "Unique Terms",
                            value: formatLargeNumber(indexInfo.uniqueTerms),
                            icon: "textformat.abc",
                            color: .blue
                        )

                        IndexStatCard(
                            title: "Total Occurrences",
                            value: formatLargeNumber(indexInfo.totalTerms),
                            icon: "number",
                            color: .green
                        )

                        IndexStatCard(
                            title: "Avg Frequency",
                            value: String(format: "%.1f", indexInfo.averageTermFrequency),
                            icon: "chart.line.uptrend.xyaxis",
                            color: .purple
                        )

                        IndexStatCard(
                            title: "Compression",
                            value: String(format: "%.0f%%", indexInfo.compressionRatio * 100),
                            icon: "arrow.down.right.and.arrow.up.left",
                            color: compressionColor(indexInfo.compressionRatio)
                        )
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)

                // Tokenizer info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "scissors")
                            .foregroundColor(.orange)
                        Text("Tokenizer Configuration")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TokenizerInfoRow(label: "Tokenizer", value: "porter unicode61")
                        TokenizerInfoRow(label: "Stemming", value: "English Porter Stemmer")
                        TokenizerInfoRow(label: "Case Handling", value: "Case-insensitive (Unicode)")
                        TokenizerInfoRow(label: "Ranking", value: "BM25 (built-in)")
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)

                // FTS5 features
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("FTS5 Capabilities")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)
            } else {
                ProgressView("Loading index info...")
                    .padding(40)
            }
        }
    }

    // MARK: - Vocabulary Section (Power User)

    private var vocabularySection: some View {
        VStack(spacing: 16) {
            // Top terms
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "textformat.abc")
                        .foregroundColor(.purple)
                    Text("Top 100 Terms by Frequency")
                        .font(.headline)
                    Spacer()
                    Text("\(topTerms.count) terms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if topTerms.isEmpty {
                    Text("No vocabulary data yet. Add documents to populate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    // Term frequency chart
                    Chart(topTerms.prefix(20)) { term in
                        BarMark(
                            x: .value("Occurrences", term.totalOccurrences),
                            y: .value("Term", term.term)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    .chartXAxisLabel("Total Occurrences")
                    .frame(height: 400)

                    Divider()

                    // Full term list
                    LazyVStack(spacing: 6) {
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
                        .foregroundColor(.secondary)

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
                                    .foregroundColor(.accentColor)
                                    .frame(width: 60)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Term distribution histogram
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.orange)
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
                        .foregroundStyle(.orange.gradient)
                    }
                    .chartYAxisLabel("Number of Terms")
                    .chartXAxisLabel("Occurrence Count")
                    .frame(height: 200)

                    Text("Shows how many terms appear with each frequency range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(spacing: 16) {
            // Deep diagnostics header
            if let diag = deepDiagnostics {
                // Database file info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.blue)
                        Text("Storage Details")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        DiagnosticCard(label: "Database", value: formatBytes(diag.databaseSizeBytes), icon: "cylinder.fill", color: .blue)
                        DiagnosticCard(label: "WAL File", value: formatBytes(diag.walSizeBytes), icon: "doc.fill", color: .green)
                        DiagnosticCard(label: "SHM File", value: formatBytes(diag.shmSizeBytes), icon: "doc.fill", color: .orange)
                        DiagnosticCard(label: "Total", value: formatBytes(diag.databaseSizeBytes + diag.walSizeBytes + diag.shmSizeBytes), icon: "externaldrive.fill", color: .purple)
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)

                // Page statistics
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundColor(.cyan)
                        Text("Page Statistics")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MiniStatCard(label: "Page Size", value: "\(diag.pageSize) B")
                        MiniStatCard(label: "Pages", value: "\(diag.pageCount)")
                        MiniStatCard(label: "Free Pages", value: "\(diag.freePageCount)")
                        MiniStatCard(label: "Schema Ver", value: "\(diag.schemaVersion)")
                        MiniStatCard(label: "Cache Size", value: "\(abs(diag.cacheSize))")
                        MiniStatCard(label: "MMap", value: formatBytes(diag.mMapSize))
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)

                // SQLite settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gearshape.2.fill")
                            .foregroundColor(.gray)
                        Text("SQLite Configuration")
                            .font(.headline)
                        Spacer()
                    }

                    ForEach(Array(diag.pragmaSettings.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(diag.pragmaSettings[key] ?? "—")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    Divider()

                    // Database path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database Path")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(diag.databasePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)

                // Table stats
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "tablecells.fill")
                            .foregroundColor(.indigo)
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
                                .foregroundColor(.secondary)
                            Text("~\(formatBytes(table.estimatedSize))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)
            } else {
                ProgressView("Loading diagnostics...")
                    .padding(40)
            }

            // Search performance test
            if let metrics = searchMetrics {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(.green)
                        Text("Last Search Performance")
                            .font(.headline)
                        Spacer()
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        DiagnosticCard(label: "Latency", value: String(format: "%.2f ms", metrics.queryLatencyMs), icon: "clock.fill", color: .green)
                        DiagnosticCard(label: "Docs Scanned", value: "\(metrics.documentsScanned)", icon: "doc.text.magnifyingglass", color: .blue)
                        DiagnosticCard(label: "Results", value: "\(metrics.resultsReturned)", icon: "list.bullet", color: .purple)
                        DiagnosticCard(label: "Index Hits", value: "\(metrics.indexHits)", icon: "target", color: .orange)
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Maintenance Section

    private var maintenanceSection: some View {
        VStack(spacing: 16) {
            // Integrity check
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Integrity Check")
                        .font(.headline)
                    Spacer()
                    Button("Run Check") {
                        Task {
                            integrityResults = await SQLiteFullTextService.shared.runIntegrityCheck()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !integrityResults.isEmpty {
                    ForEach(integrityResults, id: \.self) { result in
                        HStack {
                            Image(systemName: result.lowercased().contains("ok") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(result.lowercased().contains("ok") ? .green : .red)
                            Text(result)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Run integrity check to verify database health")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Optimize database
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
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

                Text("Runs VACUUM and FTS5 optimize to reclaim space and improve performance")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let result = lastOptimizeResult {
                    Label(result, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Rebuild index
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.red)
                    Text("Rebuild Index")
                        .font(.headline)
                    Spacer()

                    if !rebuildLogs.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                showRebuildLog.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
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

                Text("⚠️ Completely rebuilds the FTS5 index. Use if search results seem corrupted.")
                    .font(.caption)
                    .foregroundColor(.orange)

                // Live rebuild log
                if showRebuildLog && !rebuildLogs.isEmpty {
                    rebuildLogView
                }

                // Current status during rebuild
                if isRebuildingIndex, let lastLog = rebuildLogs.last {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(lastLog.message)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Database info
            if let diag = deepDiagnostics {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Database Info")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        DatabaseInfoRow(label: "Journal Mode", value: diag.journalMode.uppercased())
                        DatabaseInfoRow(label: "Auto Vacuum", value: diag.autoVacuum)
                        DatabaseInfoRow(label: "Integrity", value: diag.integrityCheckResult)
                        DatabaseInfoRow(label: "Page Count", value: "\(diag.pageCount)")
                        DatabaseInfoRow(label: "Free Pages", value: "\(diag.freePageCount)")

                        if diag.freePageCount > 0 {
                            let wastedBytes = Int64(diag.freePageCount * diag.pageSize)
                            Text("💡 \(formatBytes(wastedBytes)) could be reclaimed with Optimize")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(spacing: 16) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search FTS5 index...", text: $searchQuery)
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
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(DSColors.surface)
            .cornerRadius(12)

            // Search tips
            if searchResults.isEmpty && searchQuery.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("FTS5 Query Syntax")
                            .font(.headline)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SearchTip(syntax: "word1 word2", description: "Match documents containing both words (AND)")
                        SearchTip(syntax: "\"exact phrase\"", description: "Match exact phrase in order")
                        SearchTip(syntax: "word1 OR word2", description: "Match either word")
                        SearchTip(syntax: "word1 NOT word2", description: "Match word1, exclude word2")
                        SearchTip(syntax: "word*", description: "Prefix matching (wildcard)")
                        SearchTip(syntax: "NEAR(word1 word2, 5)", description: "Words within 5 tokens of each other")
                        SearchTip(syntax: "^word", description: "Match at start of column")
                        SearchTip(syntax: "word + word2", description: "word2 must follow word (adjacent)")
                    }

                    Text("Queries are case-insensitive. BM25 ranking is used for relevance scoring.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .background(DSColors.surface)
                .cornerRadius(12)
            }

            // Search performance metrics
            if let metrics = searchMetrics {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(String(format: "%.2f ms", metrics.queryLatencyMs))
                            .font(.caption.monospacedDigit())
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(metrics.documentsScanned) scanned")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        Text("\(metrics.resultsReturned) returned")
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }

            // Search results
            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Results")
                            .font(.headline)
                        Spacer()
                        Text("\(searchResults.count) matches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(searchResults, id: \.documentId) { result in
                        SearchResultRow(result: result, documentName: documentName(for: result.documentId))
                    }
                }
            }
        }
    }

    private var emptyDatabaseState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Database Empty")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add documents to populate the SQLite FTS5 full-text search index")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(DSColors.surface)
        .cornerRadius(16)
    }

    // MARK: - Helpers

    private func loadStatistics() async {
        isLoading = true
        let service = SQLiteFullTextService.shared
        stats = await service.getStatistics()
        indexInfo = await service.getIndexInfo()
        documentStats = await service.getDocumentStats(containerId: containerService.activeContainerId)
        isLoading = false
    }

    private func performSearch() async {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        let service = SQLiteFullTextService.shared

        // Use timed search to get performance metrics
        let (results, metrics) = await service.timedSearch(
            query: searchQuery,
            containerId: containerService.activeContainerId,
            limit: 50
        )
        searchResults = results
        searchMetrics = metrics
        isSearching = false
    }

    private func formatLargeNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func compressionColor(_ ratio: Double) -> Color {
        if ratio < 0.3 { return .green }
        else if ratio < 0.6 { return .blue }
        else if ratio < 0.9 { return .orange }
        else { return .red }
    }

    private func containerName(for containerId: UUID) -> String {
        containerService.containers.first { $0.id == containerId }?.name ?? "Unknown"
    }

    private func documentName(for documentId: UUID) -> String {
        ragService.documents.first { $0.id == documentId }?.filename ?? String(documentId.uuidString.prefix(8)) + "..."
    }

    // MARK: - Rebuild Log View

    private var rebuildLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔧 Rebuild Log")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(rebuildLogs.count) entries")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    rebuildLogs = []
                    showRebuildLog = false
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rebuildLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.type.icon)
                                .font(.caption2)
                                .foregroundColor(entry.type.color)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.primary)
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 9).monospaced())
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 200)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.top, 8)
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
        addLog("⚡ Executing FTS5 rebuild command...", type: .step)
        addLog("  INSERT INTO documents(documents) VALUES('rebuild')", type: .info)
        await Task.yield()

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await service.rebuildIndex()
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if result.success {
            addLog("✅ Rebuild command completed successfully", type: .success)
            addLog("  Elapsed: \(String(format: "%.2f", elapsed))ms", type: .info)
        } else {
            addLog("❌ Rebuild command failed", type: .error)
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
        if result.success {
            addLog("🎉 Index rebuild completed successfully!", type: .success)
            addLog("  Total time: \(String(format: "%.2f", elapsed))ms", type: .info)
            lastOptimizeResult = "Index rebuilt in \(String(format: "%.1f", elapsed))ms"
        } else {
            addLog("⚠️ Index rebuild encountered issues", type: .error)
        }

        isRebuildingIndex = false
        await loadAllData()
    }

    private func addLog(_ message: String, type: RebuildLogEntry.LogType) {
        rebuildLogs.append(RebuildLogEntry(timestamp: Date(), message: message, type: type))
    }
}

// MARK: - Supporting Views

private struct QuickStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DatabaseStatusBadge: View {
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(20)
    }
}

private struct DatabaseMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
                if let trend = trend {
                    Text(trend)
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }
}

private struct PerformanceComparisonRow: View {
    let operation: String
    let oldMethod: String
    let newMethod: String
    let speedup: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(operation)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(oldMethod)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(newMethod)
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Text(speedup)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
        }
    }
}

private struct DocumentStatRow: View {
    let doc: SQLiteFullTextService.DocumentStat
    let documentName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(documentName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label("Added \(doc.createdAt, style: .relative) ago", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(doc.characterCount.formatted()) chars")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(doc.wordCount.formatted()) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(10)
    }
}

private struct IndexStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

private struct TokenizerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

private struct FeatureBadge: View {
    let name: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? .green : .red)
                .font(.caption)
            Text(name)
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(enabled ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct SearchTip: View {
    let syntax: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(syntax)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

private struct SearchResultRow: View {
    let result: FTS5SearchResult
    let documentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(documentName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.2f", -result.bm25Score))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }

            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(DSColors.surface)
        .cornerRadius(10)
    }
}

/// Card for diagnostics with icon and color
private struct DiagnosticCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Spacer()
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

/// Compact stat card for mini metrics
private struct MiniStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Simple info row with label and value for database dashboard
private struct DatabaseInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

/// Health status indicator
private struct HealthIndicator: View {
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
        HStack(spacing: 6) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Library Intelligence Card

/// Card showing Auto Intelligence adaptations for a specific library
struct LibraryIntelligenceCard: View {
    let container: KnowledgeContainer
    let intelligenceReport: LibraryIntelligenceCenter.IntelligenceReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with library info
            HStack(spacing: 10) {
                Image(systemName: container.icon)
                    .foregroundColor(Color(hex: container.colorHex) ?? .accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.headline)

                    HStack(spacing: 6) {
                        if container.autoAdaptDimension {
                            Label("Auto", systemImage: "wand.and.stars")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        } else {
                            Label("Manual", systemImage: "slider.horizontal.3")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let lastTune = container.lastSelfTuneAt {
                            Text("• Updated \(lastTune, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Status indicator
                Circle()
                    .fill(container.autoAdaptDimension ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Chunking adaptations
            if let report = intelligenceReport {
                VStack(alignment: .leading, spacing: 8) {
                    IntelligenceMetricRow(
                        icon: "rectangle.split.3x1",
                        label: "Chunking Strategy",
                        value: report.chunking.strategy.rawValue.capitalized,
                        color: .blue
                    )

                    IntelligenceMetricRow(
                        icon: "textformat.size",
                        label: "Target Chunk Size",
                        value: "\(report.chunking.targetWordWindow) words",
                        color: .green
                    )

                    IntelligenceMetricRow(
                        icon: "arrow.left.arrow.right",
                        label: "Overlap",
                        value: "\(report.chunking.overlapWords) words",
                        color: .orange
                    )

                    if !report.chunking.rationales.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Why these settings:")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)

                            ForEach(report.chunking.rationales.prefix(3), id: \.self) { reason in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(.accentColor)
                                    Text(reason)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } else if container.autoAdaptDimension {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Analyzing corpus...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Manual mode - show current directive
                if let directive = container.chunkingDirective {
                    VStack(alignment: .leading, spacing: 8) {
                        IntelligenceMetricRow(
                            icon: "rectangle.split.3x1",
                            label: "Chunking Strategy",
                            value: directive.strategy.capitalized,
                            color: .gray
                        )

                        IntelligenceMetricRow(
                            icon: "textformat.size",
                            label: "Target Chunk Size",
                            value: "\(directive.targetWordWindow) words",
                            color: .gray
                        )

                        IntelligenceMetricRow(
                            icon: "arrow.left.arrow.right",
                            label: "Overlap",
                            value: "\(directive.overlapWords) words",
                            color: .gray
                        )
                    }
                } else {
                    Text("Using default chunking settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Corpus signals if available
            if let report = intelligenceReport {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Corpus Signals")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        CorpusSignalBadge(
                            icon: "doc.text",
                            label: "\(report.corpus.documentCount) docs"
                        )
                        CorpusSignalBadge(
                            icon: "cube.box",
                            label: "\(report.corpus.chunkCount) chunks"
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
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(container.autoAdaptDimension ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
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
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
    }
}

/// Row explaining how intelligence works
struct IntelligenceExplanationRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Document Preview Sheet

/// Full preview of a document's FTS5 content and metadata
struct DocumentPreviewSheet: View {
    let documentId: UUID
    let documentName: String
    let characterCount: Int
    let wordCount: Int

    @State private var content: String = ""
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.accentColor)
                            Text("Document Metadata")
                                .font(.headline)
                            Spacer()
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetadataCard(label: "Document ID", value: documentId.uuidString, isMonospace: true)
                            MetadataCard(label: "Characters", value: characterCount.formatted())
                            MetadataCard(label: "Words", value: wordCount.formatted())
                            MetadataCard(label: "Avg Word Length", value: wordCount > 0 ? String(format: "%.1f", Double(characterCount) / Double(wordCount)) : "—")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Content preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "text.alignleft")
                                .foregroundColor(.blue)
                            Text("Indexed Content")
                                .font(.headline)
                            Spacer()

                            if !content.isEmpty {
                                Button {
                                    UIPasteboard.general.string = content
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if isLoading {
                            ProgressView("Loading content...")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(40)
                        } else if content.isEmpty {
                            Text("No content available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            Text(content)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Analysis
                    if !content.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundColor(.purple)
                                Text("Quick Analysis")
                                    .font(.headline)
                                Spacer()
                            }

                            let lines = content.components(separatedBy: .newlines).count
                            let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
                            let paragraphs = content.components(separatedBy: "\n\n").count

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                AnalysisCard(label: "Lines", value: "\(lines)", icon: "list.number", color: .blue)
                                AnalysisCard(label: "Sentences", value: "\(max(1, sentences))", icon: "text.quote", color: .green)
                                AnalysisCard(label: "Paragraphs", value: "\(paragraphs)", icon: "text.alignleft", color: .orange)
                            }

                            // Character breakdown
                            let uppercaseCount = content.filter { $0.isUppercase }.count
                            let lowercaseCount = content.filter { $0.isLowercase }.count
                            let digitCount = content.filter { $0.isNumber }.count
                            let whitespaceCount = content.filter { $0.isWhitespace }.count
                            let punctuationCount = content.filter { $0.isPunctuation }.count

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Character Breakdown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)

                                CharacterBreakdownRow(label: "Uppercase", count: uppercaseCount, total: characterCount, color: .blue)
                                CharacterBreakdownRow(label: "Lowercase", count: lowercaseCount, total: characterCount, color: .green)
                                CharacterBreakdownRow(label: "Digits", count: digitCount, total: characterCount, color: .orange)
                                CharacterBreakdownRow(label: "Whitespace", count: whitespaceCount, total: characterCount, color: .gray)
                                CharacterBreakdownRow(label: "Punctuation", count: punctuationCount, total: characterCount, color: .purple)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle(documentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            isLoading = true
            // Load FULL content — no artificial truncation
            content = await SQLiteFullTextService.shared.getFullContent(
                documentId: documentId
            ) ?? ""
            isLoading = false
        }
    }
}

/// Card showing metadata
private struct MetadataCard: View {
    let label: String
    let value: String
    var isMonospace: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(isMonospace ? .system(.caption2, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

/// Card for analysis metrics
private struct AnalysisCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Row showing character breakdown with progress bar
private struct CharacterBreakdownRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)

            Text(String(format: "%.1f%%", percentage * 100))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        DatabaseDashboardView()
            .environmentObject(RAGService())
            .environmentObject(ContainerService())
    }
}
