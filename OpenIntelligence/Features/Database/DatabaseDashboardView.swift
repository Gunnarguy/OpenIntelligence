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
    /// Which library the per-library figures on this screen cover.
    ///
    /// `.library(UUID)` rather than `.activeLibrary`. The old pair could not express "a library
    /// that is not the active one", so this screen was structurally capped at two choices however
    /// many libraries existed, and inspecting library three of five meant leaving for the
    /// Documents tab, switching the active library there, and coming back. Carrying the id means
    /// the selection is independent of which library is active, so looking at a library's index
    /// no longer changes what the rest of the app is pointed at.
    enum DatabaseScope: Hashable {
        case allLibraries
        case library(UUID)
    }

    // Defaults to the active library so the screen opens on what the rest of the app is
    // pointed at. Set in `onAppear` because the active id is not known at property-initialiser
    // time; `.allLibraries` is the honest placeholder until it is.
    @State private var databaseScope: DatabaseScope = .allLibraries

    /// Libraries with an analysis genuinely in flight, so the card can show a
    /// spinner that corresponds to work actually happening.
    @State private var analyzingContainerIds: Set<UUID> = []
    @State private var didSeedScope = false
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

    @State private var containerNameMap: [UUID: String] = [:]
    @State private var documentNameMap: [UUID: String] = [:]

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
                case .info: return .accentColor
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                case .step: return .accentColor
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

        /// The index and storage internals, listed only with Technical Details on (5.7). The rest of
        /// the screen says the same things in plain words unless Technical Details is on.
        var isTechnical: Bool { self == .index || self == .performance }

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
                VStack(spacing: DSSpacing.lg) {
                    // Header
                    headerSection

                    // Section picker
                    sectionPicker

                    // Content based on selection
                    switch shownSection {
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
                .padding(DSSpacing.lg)
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
            updateMaps()
        }
        .onChange(of: containerService.containers.count) { _, _ in
            resolveStaleScope()
            updateMaps()
        }
        .onChange(of: databaseScope) { _, _ in
            Task { await loadStatistics() }
        }
        .onAppear {
            guard !didSeedScope else { return }
            didSeedScope = true
            databaseScope = .library(containerService.activeContainerId)
        }
        .onChange(of: ragService.documents.count) { _, _ in
            updateMaps()
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

        // Watchdog: if Phase 1 doesn't complete in 10 seconds, force-show the UI.
        // Prevents infinite loading state if the actor is deadlocked or DB is corrupt.
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if isLoading {
                Log.warning("[DatabaseDash] ⚠️ Watchdog fired — Phase 1 did not complete in 10s, forcing UI", category: .vectorDB)
                isLoading = false
            }
        }

        // PHASE 1: Essential data (fast metadata queries on document_meta table).
        // Sequential calls — simpler to debug than async let.
        Log.info("[DatabaseDash] Phase 1: requesting getStatistics()", category: .vectorDB)
        stats = await service.getStatistics()
        Log.info("[DatabaseDash] Phase 1: getStatistics() complete, requesting getDocumentStats()", category: .vectorDB)
        // Scoped, not active. Picking "All Libraries" used to leave this list showing only the
        // active library's documents, with the section header saying nothing about which library
        // the rows belonged to. `nil` means every library, which is what the parameter already
        // meant at the service layer.
        documentStats = await loadDocumentStats(for: scopedContainerId)
        Log.info("[DatabaseDash] Phase 1: getDocumentStats() complete — showing UI", category: .vectorDB)

        watchdog.cancel()
        isLoading = false

        // PHASE 2: Diagnostic & vocabulary data — loaded in a separate unstructured Task
        // so it can NEVER block the UI. Even if these queries hang, the user can browse
        // documents and see basic stats.
        Task { @MainActor [weak containerService] in
            guard let containerService = containerService else { return }
            _ = containerService // suppress unused warning, used for capture

            Log.info("[DatabaseDash] Phase 2: loading diagnostics/vocabulary", category: .vectorDB)
            async let indexTask = service.getIndexInfo()
            async let diagTask = service.getDeepDiagnostics()
            async let termsTask = service.getTopTerms(limit: 100)
            async let distTask = service.getTermDistribution()

            indexInfo = await indexTask
            deepDiagnostics = await diagTask
            topTerms = await termsTask
            termDistribution = await distTask
            Log.info("[DatabaseDash] Phase 2: complete", category: .vectorDB)

            // PHASE 3: Background-populate document_content table for any
            // pre-migration documents so tapping a document loads instantly.
            Task.detached(priority: .utility) {
                SQLiteFullTextService.backgroundPopulateContentTable()
            }
        }
    }
    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [DSColors.accent, DSColors.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(settings.showTechnicalDetails ? "SQLite FTS5" : "Keyword Index")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(settings.showTechnicalDetails ? "Full-Text Search Engine" : "Finds the exact words of a question in your documents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let stats = stats {
                    DatabaseStatusBadge(
                        status: stats.indexStatus,
                        color: stats.totalDocuments > 0 ? .green : .orange
                    )
                }
            }

            // Scope control.
            //
            // This screen used to render two different scopes side by side with nothing
            // saying which was which. `getStatistics()` runs
            // `SELECT COUNT(*) FROM document_meta` with **no WHERE clause**, so the
            // headline counted every library at once, while the document rows below came
            // from `getDocumentStats(containerId:)`, which is scoped. A user with six
            // libraries saw "7 Total Documents" directly above a list belonging to a
            // library holding one.
            //
            // The per-library numbers were already being fetched: `FTS5Statistics`
            // carries `containerStats`, so scoping needs no new query and no change to
            // `SQLiteFullTextService`, which is a hard-boundary file.
            scopePicker

            // Quick stats row, scoped to the selection above.
            if let stats = stats {
                HStack(spacing: DSSpacing.lg) {
                    QuickStat(value: "\(scopedDocumentCount(stats))", label: "Docs", icon: "doc.fill", color: .accentColor)
                    QuickStat(value: formatLargeNumber(scopedWordCount(stats)), label: "Words", icon: "textformat", color: .accentColor)
                    // Size, terms and every other file-level figure are properties of the
                    // SQLite file itself and cannot be attributed to one library, so they
                    // stay whole-database and say so rather than silently implying scope.
                    QuickStat(value: formatBytes(stats.databaseSizeBytes), label: "Size (all)", icon: "externaldrive.fill", color: .accentColor)
                    if let indexInfo = indexInfo {
                        QuickStat(value: formatLargeNumber(indexInfo.uniqueTerms), label: "Terms (all)", icon: "list.bullet", color: .accentColor)
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    /// Library scope for the per-library figures on this screen.
    ///
    /// `nil` means every library, which is what the screen used to show unconditionally.
    private var scopedContainerId: UUID? {
        switch databaseScope {
        case .allLibraries: return nil
        case .library(let id): return id
        }
    }

    /// The scoped library's name, or nil when the scope is every library.
    ///
    /// Falls back through to `nil` when the carried id is no longer in `containers`, which happens
    /// if the selected library is deleted from another screen or another device while this one is
    /// open. `resolveStaleScope` is what actually repairs the selection; this only keeps labels
    /// from rendering a stale name in the meantime.
    private var scopedLibraryName: String? {
        guard let id = scopedContainerId else { return nil }
        return containerService.containers.first { $0.id == id }?.name
    }

    /// Short label for whatever the current scope is, for section captions.
    private var scopeLabel: String {
        scopedLibraryName ?? "All Libraries"
    }

    /// Document rows for the current scope.
    ///
    /// `getDocumentStats(containerId:)` takes a non-optional `UUID` and its SQL is
    /// `WHERE container_id = ?`, so unlike `timedSearch` it has no all-libraries form. Rather
    /// than add one, which would mean editing `SQLiteFullTextService` and that file is a hard
    /// boundary, "All Libraries" fans out over `containerService.containers` here and
    /// concatenates. This screen is opened deliberately and refreshed by hand, so N small
    /// metadata queries against `document_meta` are not worth a service change to avoid.
    private func loadDocumentStats(for scope: UUID?) async -> [SQLiteFullTextService.DocumentStat] {
        let service = SQLiteFullTextService.shared
        guard let scope else {
            var merged: [SQLiteFullTextService.DocumentStat] = []
            for container in containerService.containers {
                merged.append(contentsOf: await service.getDocumentStats(containerId: container.id))
            }
            return merged
        }
        return await service.getDocumentStats(containerId: scope)
    }

    /// Drops a selection whose library no longer exists.
    ///
    /// Without this the screen keeps reporting figures for a deleted id, which read as a library
    /// that still exists with zero documents in it.
    private func resolveStaleScope() {
        guard case .library(let id) = databaseScope else { return }
        if !containerService.containers.contains(where: { $0.id == id }) {
            databaseScope = .allLibraries
        }
    }

    private func scopedDocumentCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalDocuments }
        return stats.containerStats.first { $0.containerId == id }?.documentCount ?? 0
    }

    private func scopedWordCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalWords }
        return stats.containerStats.first { $0.containerId == id }?.totalWords ?? 0
    }

    private func scopedCharacterCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalCharacters }
        return stats.containerStats.first { $0.containerId == id }?.totalCharacters ?? 0
    }

    /// Names the scope on every scoped card, so a number is never ambiguous about
    /// whether it covers one library or all of them.
    private var scopeSubtitle: String {
        scopedLibraryName ?? "All libraries"
    }

    /// Totals over the documents actually listed on the Documents section, so its
    /// summary cannot disagree with the rows beneath them.
    private var listedWordCount: Int {
        documentStats.reduce(0) { $0 + $1.wordCount }
    }

    private var listedCharacterCount: Int {
        documentStats.reduce(0) { $0 + $1.characterCount }
    }

    /// Scope control: every library, or any one of them by name.
    ///
    /// A `.menu` Picker rather than `.segmented`. A segmented control divides its width by the
    /// number of options, so it stops being usable at four or five libraries and cannot scroll;
    /// a menu holds any number and shows the current selection in its label. The rows are built
    /// from `containerService.containers`, the same list the Documents tab's chip row uses, so a
    /// library appears here the moment it exists.
    ///
    /// Deliberately not built from `ContainerPill`. That view defaults `canDelete` to `true` and
    /// carries a long-press dialog with "Make Local Only" and "Delete Library" in it, so reusing
    /// it would put a data-destroying menu on a read-only statistics screen.
    /// A scrolling row rather than a menu.
    ///
    /// A `.menu` picker shows the current selection and hides every alternative
    /// behind a tap, then a second tap to choose — which is a lot of work to answer
    /// "what else is there". With eight libraries the row is faster to scan and each
    /// target is a full chip rather than a menu line. Matches `sectionPicker`
    /// directly below it, so the two controls on this screen behave the same way.
    @ViewBuilder
    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                scopeChip(
                    label: "All Libraries",
                    icon: "square.stack.3d.up",
                    scope: .allLibraries,
                    tint: .accentColor
                )

                ForEach(containerService.containers) { container in
                    scopeChip(
                        label: container.name,
                        icon: container.icon,
                        scope: .library(container.id),
                        tint: Color(hex: container.colorHex) ?? .accentColor
                    )
                }
            }
            .padding(.horizontal, DSSpacing.xxs)
            .padding(.vertical, DSSpacing.xxs)
        }
        .accessibilityLabel("Statistics scope")
        .accessibilityHint("Choose whether the counts cover every library or one library by name")
    }

    /// Analyses one library on demand.
    ///
    /// `refreshIntelligence` opens the library's database and loads every chunk, so
    /// this is deliberately per-library and user-initiated. Firing it for all of them
    /// when the tab appears is the same read amplification `771461c` removed from
    /// sync: eight libraries would mean eight database opens and a full chunk load
    /// each, to populate cards most of which nobody is looking at.
    @MainActor
    private func analyzeLibrary(_ containerId: UUID) {
        guard !analyzingContainerIds.contains(containerId) else { return }
        analyzingContainerIds.insert(containerId)

        Task { @MainActor in
            await ragService.refreshIntelligence(for: containerId, force: true).value
            analyzingContainerIds.remove(containerId)
        }
    }

    @ViewBuilder
    private func scopeChip(
        label: String,
        icon: String,
        scope: DatabaseScope,
        tint: Color
    ) -> some View {
        let isSelected = databaseScope == scope

        Button {
            guard databaseScope != scope else { return }
            DSHaptics.light()
            withAnimation(DSAnimations.snappySpring) {
                databaseScope = scope
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : .secondary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(
                Capsule().fill(tint.opacity(isSelected ? 0.16 : 0.06))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(isSelected ? 0.5 : 0.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The section on screen: Index and Performance only with Technical Details on.
    private var shownSection: DatabaseSection {
        selectedSection.isTechnical && !settings.showTechnicalDetails ? .overview : selectedSection
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.md) {
                ForEach(DatabaseSection.allCases.filter { settings.showTechnicalDetails || !$0.isTechnical }) { section in
                    Button {
                        withAnimation(DSAnimations.snappySpring) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: section.icon)
                            Text(section.label)
                        }
                        .font(.subheadline)
                        .fontWeight(shownSection == section ? .semibold : .regular)
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(
                            shownSection == section
                                ? Color.accentColor.opacity(0.15)
                                : DSColors.surface,
                            in: Capsule()
                        )
                        .foregroundStyle(shownSection == section ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.xs)
        }
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
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

    private var documentsSection: some View {
        VStack(spacing: DSSpacing.lg) {
            if documentStats.isEmpty {
                VStack(spacing: DSSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                    Text(settings.showTechnicalDetails ? "No Documents Indexed" : "No Documents Yet")
                        .font(.headline)
                    Text(settings.showTechnicalDetails ? "Add documents to populate the FTS5 index" : "Documents you add are listed here with their words and characters.")
                        .font(.footnote)
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

    private var intelligenceSection: some View {
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
                        .font(.subheadline.weight(.medium))
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

    // MARK: - Index Section

    private var indexSection: some View {
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

    private var vocabularySection: some View {
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

    private var performanceSection: some View {
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

    // MARK: - Maintenance Section

    private var maintenanceSection: some View {
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

    private var searchSection: some View {
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
                            .font(.caption.monospacedDigit())
                    }
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(metrics.resultsReturned) returned")
                            .font(.caption.monospacedDigit())
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
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ForEach(searchResults, id: \.documentId) { result in
                        SearchResultRow(result: result, documentName: documentName(for: result.documentId))
                    }
                }
            }
        }
    }

    private var emptyDatabaseState: some View {
        VStack(spacing: DSSpacing.lg) {
            Image(systemName: "cylinder")
                .font(.largeTitle)
                .foregroundStyle(.secondary.opacity(0.4))

            Text(settings.showTechnicalDetails ? "Database Empty" : "No Documents Yet")
                .font(.title2.weight(.semibold))

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

    private func loadStatistics() async {
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
        else if ratio < 0.6 { return .accentColor }
        else if ratio < 0.9 { return .orange }
        else { return .red }
    }

    private func containerName(for containerId: UUID) -> String {
        containerNameMap[containerId] ?? "Unknown"
    }

    private func documentName(for documentId: UUID) -> String {
        documentNameMap[documentId] ?? String(documentId.uuidString.prefix(8)) + "..."
    }

    private func updateMaps() {
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
                    .font(.caption2.monospacedDigit())
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
                                    .font(.caption2.monospaced())
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

// MARK: - Supporting Views

private struct QuickStat: View {
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
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DatabaseStatusBadge: View {
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(color.opacity(0.15), in: Capsule())
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
                .font(.title.weight(.bold).monospacedDigit())

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

private struct IndexFactRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DocumentStatRow: View {
    let doc: SQLiteFullTextService.DocumentStat
    let documentName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(documentName)
                    .font(.subheadline.weight(.medium))
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
                    .font(.caption.weight(.medium).monospacedDigit())
                Text("\(doc.wordCount.formatted()) words")
                    .font(.caption2.monospacedDigit())
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

private struct IndexStatCard: View {
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
                .font(.title2.weight(.bold).monospacedDigit())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }
}

private struct TokenizerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}

private struct FeatureBadge: View {
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

private struct SearchTip: View {
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

private struct SearchResultRow: View {
    let result: FTS5SearchResult
    let documentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(documentName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.2f", -result.bm25Score))
                    .font(.caption.monospacedDigit())
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
private struct DiagnosticCard: View {
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
                .font(.title3.weight(.bold).monospacedDigit())
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
private struct MiniStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
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
private struct DatabaseInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
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
                                    .font(.caption.weight(.semibold))
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
                .font(.caption.weight(.medium).monospacedDigit())
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
                .font(.caption2.monospacedDigit())
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

// MARK: - Document Preview Sheet

/// Full preview of a document's FTS5 content and metadata.
///
/// Large documents (947KB+, 28K+ lines) require special handling:
/// - SwiftUI `Text` chokes rendering >100K chars of monospaced text → white canvas
/// - `.filter{}` / `.components(separatedBy:)` on main thread freezes UI
/// Solution: truncate display to 100K chars, pre-compute analysis off main thread,
/// share full content via share sheet.
struct DocumentPreviewSheet: View {
    let documentId: UUID
    let documentName: String
    let characterCount: Int
    let wordCount: Int

    /// Maximum characters to render in the Text view.
    /// 100K chars ≈ 3K lines — plenty for browsing, won't kill SwiftUI layout.
    private static let displayLimit = 100_000

    @State private var fullContent: String = ""
    @State private var fullContentCharacterCount: Int = 0
    @State private var displayContent: String = ""
    @State private var isTruncated = false
    @State private var isLoading = true
    @State private var analysisStats: AnalysisStats?
    @Environment(\.dismiss) private var dismiss

    /// Pre-computed analysis stats (computed off main thread)
    struct AnalysisStats {
        let lines: Int
        let sentences: Int
        let paragraphs: Int
        let uppercaseCount: Int
        let lowercaseCount: Int
        let digitCount: Int
        let whitespaceCount: Int
        let punctuationCount: Int
        let totalChars: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    // Metadata header
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Document Metadata")
                                .font(.headline)
                            Spacer()
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                            MetadataCard(label: "Document ID", value: documentId.uuidString, isMonospace: true)
                            MetadataCard(label: "Characters", value: characterCount.formatted())
                            MetadataCard(label: "Words", value: wordCount.formatted())
                            MetadataCard(label: "Avg Word Length", value: wordCount > 0 ? String(format: "%.1f", Double(characterCount) / Double(wordCount)) : "—")
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                    // Content preview
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        HStack {
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(Color.accentColor)
                            Text("Indexed Content")
                                .font(.headline)
                            Spacer()

                            if !fullContent.isEmpty {
                                ShareLink(item: fullContent) {
                                    Label("Share Full", systemImage: "square.and.arrow.up")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    #if canImport(UIKit)
                                    UIPasteboard.general.string = fullContent
                                    #elseif canImport(AppKit)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(fullContent, forType: .string)
                                    #endif
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
                                .padding(DSSpacing.xxl)
                        } else if displayContent.isEmpty {
                            Text("No content available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(DSSpacing.lg)
                        } else {
                            if isTruncated {
                                HStack(spacing: DSSpacing.xs) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Showing first \(Self.displayLimit.formatted()) of \(fullContentCharacterCount.formatted()) characters. Use Share to export full content.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, DSSpacing.sm)
                                .padding(.vertical, DSSpacing.xs)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                            }

                            Text(displayContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(DSSpacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(DSSpacing.lg)
                    .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

                    // Analysis — uses pre-computed stats (NOT computed in view body)
                    if let stats = analysisStats {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text("Quick Analysis")
                                    .font(.headline)
                                Spacer()
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                                AnalysisCard(label: "Lines", value: "\(stats.lines)", icon: "list.number", color: .accentColor)
                                AnalysisCard(label: "Sentences", value: "\(max(1, stats.sentences))", icon: "text.quote", color: .accentColor)
                                AnalysisCard(label: "Paragraphs", value: "\(stats.paragraphs)", icon: "text.alignleft", color: .accentColor)
                            }

                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text("Character Breakdown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                CharacterBreakdownRow(label: "Uppercase", count: stats.uppercaseCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Lowercase", count: stats.lowercaseCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Digits", count: stats.digitCount, total: stats.totalChars, color: .accentColor)
                                CharacterBreakdownRow(label: "Whitespace", count: stats.whitespaceCount, total: stats.totalChars, color: .secondary)
                                CharacterBreakdownRow(label: "Punctuation", count: stats.punctuationCount, total: stats.totalChars, color: .accentColor)
                            }
                        }
                        .padding(DSSpacing.lg)
                        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                    }
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle(documentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
        .task {
            isLoading = true
            let docId = documentId
            // Read content off the actor (bypasses serial queue contention) and compute count off main thread
            let (loaded, count) = await Task.detached(priority: .userInitiated) { () -> (String, Int) in
                let content = SQLiteFullTextService.readContentDirectly(documentId: docId) ?? ""
                return (content, content.count)
            }.value

            fullContent = loaded
            fullContentCharacterCount = count

            // Truncate for display — SwiftUI Text chokes on >100K monospaced chars
            if count > Self.displayLimit {
                displayContent = String(loaded.prefix(Self.displayLimit))
                isTruncated = true
            } else {
                displayContent = loaded
                isTruncated = false
            }

            isLoading = false

            // Compute analysis stats off main thread AFTER content is visible
            if count > 0 {
                let text = loaded
                let stats = await Task.detached(priority: .utility) {
                    let lines = text.components(separatedBy: .newlines).count
                    let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
                    let paragraphs = text.components(separatedBy: "\n\n").count
                    var upper = 0, lower = 0, digits = 0, whitespace = 0, punctuation = 0
                    for char in text {
                        if char.isUppercase { upper += 1 }
                        else if char.isLowercase { lower += 1 }
                        if char.isNumber { digits += 1 }
                        if char.isWhitespace { whitespace += 1 }
                        if char.isPunctuation { punctuation += 1 }
                    }
                    return AnalysisStats(
                        lines: lines, sentences: sentences, paragraphs: paragraphs,
                        uppercaseCount: upper, lowercaseCount: lower, digitCount: digits,
                        whitespaceCount: whitespace, punctuationCount: punctuation,
                        totalChars: count
                    )
                }.value
                analysisStats = stats
            }
        }
    }
}

/// Card showing metadata
private struct MetadataCard: View {
    let label: String
    let value: String
    var isMonospace: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(isMonospace ? .system(.caption2, design: .monospaced) : .caption.monospacedDigit())
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
    }
}

/// Card for analysis metrics
private struct AnalysisCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(value)
                .font(.headline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
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
                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .trailing)

            Text(String(format: "%.1f%%", percentage * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
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
