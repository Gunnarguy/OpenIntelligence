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
    @EnvironmentObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @EnvironmentObject var settings: SettingsStore

    @State var selectedSection: DatabaseSection = .overview
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
    @State var databaseScope: DatabaseScope = .allLibraries

    /// Libraries with an analysis genuinely in flight, so the card can show a
    /// spinner that corresponds to work actually happening.
    @State var analyzingContainerIds: Set<UUID> = []
    @State private var didSeedScope = false
    @State var stats: SQLiteFullTextService.FTS5Statistics?
    @State var indexInfo: SQLiteFullTextService.FTS5IndexInfo?
    @State var documentStats: [SQLiteFullTextService.DocumentStat] = []
    @State var isLoading = true
    @State var searchQuery = ""
    @State var searchResults: [FTS5SearchResult] = []
    @State var isSearching = false

    // Advanced diagnostics
    @State var deepDiagnostics: SQLiteFullTextService.DeepDiagnostics?
    @State var topTerms: [SQLiteFullTextService.TermFrequency] = []
    @State var termDistribution: [SQLiteFullTextService.TermDistribution] = []
    @State private var docLengthStats: [SQLiteFullTextService.DocumentLengthStat] = []
    @State var searchMetrics: SQLiteFullTextService.SearchPerformanceMetrics?
    @State var integrityResults: [String] = []
    @State var isOptimizing = false
    @State var isRebuildingIndex = false
    @State var lastOptimizeResult: String?
    @State var lastKeywordRebuildResult: String?
    @State var selectedDocument: SQLiteFullTextService.DocumentStat?
    @State private var documentPreview: String?
    @State var rebuildLogs: [RebuildLogEntry] = []
    @State var showRebuildLog = false
    // Maintenance (2026-11-16): a check shows it is running, and the two rebuilds ask first, naming what they cover.
    @State var isCheckingIntegrity = false
    @State var confirmsKeywordRebuild = false
    @State var meaningRebuildToConfirm: KnowledgeContainer?

    @State var containerNameMap: [UUID: String] = [:]
    @State var documentNameMap: [UUID: String] = [:]

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

        /// What a person comes to the section for, shown under the section chips (2026-11-16). The owner asked that every
        /// inner tab make sense to a person; each sentence says what the section's cards actually show.
        var purpose: String {
            switch self {
            case .overview:
                return "How much of each library is indexed for keyword search, and whether the indexes are in good shape."
            case .intelligence:
                return "How the app has tuned each library's passages and search style to its kind of documents."
            case .documents:
                return "The words and characters indexed for each document. Tap one to read the text the app searches."
            case .vocabulary:
                return
                    "The words that occur most across all your libraries. Broken or strange words here can mean a scan was read badly."
            case .index:
                return "How the keyword index is built: its tokenizer, ranking and term counts."
            case .performance:
                return "The keyword index file: its size, pages, settings, and the timing of the last search."
            case .maintenance:
                return "The health of both search indexes, and the repairs to run when a check finds a problem."
            case .search:
                return "Find which documents contain every word you type."
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

                    // Section picker, and what the chosen section is for
                    sectionPicker
                    Text(shownSection.purpose)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, -DSSpacing.sm)
                        .accessibilityIdentifier("database.sectionPurpose")

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
                // The Settings pages' column (5.8, 2026-11-15), so on a Mac or an iPad the cards keep a phone's width.
                .frame(maxWidth: SettingsView.detailColumnWidth)
                .frame(maxWidth: .infinity)
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
        // Inline, as every root tab is (5.8, see `DSTypography`): the panel opens the page, not a 34-point title.
        .navigationBarTitleDisplayMode(.inline)
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

}




// MARK: - Preview

#Preview {
    NavigationView {
        DatabaseDashboardView()
            .environmentObject(RAGService())
            .environmentObject(ContainerService())
    }
}
