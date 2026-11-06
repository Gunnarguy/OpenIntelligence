//
//  DatabaseDashboardView+Header.swift
//  OpenIntelligence
//
//  Part of DatabaseDashboardView, moved from DatabaseDashboardView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import SwiftUI

extension DatabaseDashboardView {
    // MARK: - Load All Data

    func loadAllData() async {
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

    var headerSection: some View {
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
    var scopedContainerId: UUID? {
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
    var scopeLabel: String {
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
    func loadDocumentStats(for scope: UUID?) async -> [SQLiteFullTextService.DocumentStat] {
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
    func resolveStaleScope() {
        guard case .library(let id) = databaseScope else { return }
        if !containerService.containers.contains(where: { $0.id == id }) {
            databaseScope = .allLibraries
        }
    }

    func scopedDocumentCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalDocuments }
        return stats.containerStats.first { $0.containerId == id }?.documentCount ?? 0
    }

    func scopedWordCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalWords }
        return stats.containerStats.first { $0.containerId == id }?.totalWords ?? 0
    }

    func scopedCharacterCount(_ stats: SQLiteFullTextService.FTS5Statistics) -> Int {
        guard let id = scopedContainerId else { return stats.totalCharacters }
        return stats.containerStats.first { $0.containerId == id }?.totalCharacters ?? 0
    }

    /// Names the scope on every scoped card, so a number is never ambiguous about
    /// whether it covers one library or all of them.
    var scopeSubtitle: String {
        scopedLibraryName ?? "All libraries"
    }

    /// Totals over the documents actually listed on the Documents section, so its
    /// summary cannot disagree with the rows beneath them.
    var listedWordCount: Int {
        documentStats.reduce(0) { $0 + $1.wordCount }
    }

    var listedCharacterCount: Int {
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
    func analyzeLibrary(_ containerId: UUID) {
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
            Tour.used(.databaseScope)
            guard databaseScope != scope else { return }
            DSHaptics.light()
            withAnimation(DSAnimations.snappySpring) {
                databaseScope = scope
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .scaledFont(size: 11, weight: .medium)
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
        .tour(.databaseScope, in: Tour.database, when: scope == .allLibraries)
    }

    /// The section on screen: Index and Performance only with Technical Details on.
    var shownSection: DatabaseSection {
        selectedSection.isTechnical && !settings.showTechnicalDetails ? .overview : selectedSection
    }

    var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.md) {
                ForEach(DatabaseSection.allCases.filter { settings.showTechnicalDetails || !$0.isTechnical }) { section in
                    Button {
                        Tour.used(.databaseSections)
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
                    .tour(.databaseSections, in: Tour.database, when: section == DatabaseSection.allCases.dropFirst().first)
                }
            }
            .padding(.horizontal, DSSpacing.xs)
        }
    }

}
