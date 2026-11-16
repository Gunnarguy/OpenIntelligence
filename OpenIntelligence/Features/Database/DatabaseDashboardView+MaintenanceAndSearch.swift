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

    // Rebuilt 2026-11-16 at the owner's ask ("make the settings make sense to people bc a rebuilding index can only be a
    // good thing (right???)"). Through 5.8's first builds this was four cards of database terms with a red Rebuild
    // button and no word on when any of them helps. Now it opens on what the checks found, and each repair says what it
    // does, how long it takes and what it can remove, and is offered as the next step only when a check found a reason.
    // What each button calls is unchanged:
    // - Check: `SQLiteFullTextService.runIntegrityCheck`, FTS5's integrity-check and `PRAGMA integrity_check`; read-only.
    // - Reclaim: `SQLiteFullTextService.optimize`, FTS5's optimize then `VACUUM`, which rewrites the file.
    // - Keyword rebuild: `RAGService.rebuildDatabase` → `rebuildLocalSearchIndexesFromCanonicalState`, every library's
    //   keyword rows written again from the passages in its vector store, no file read and nothing embedded; passages
    //   of documents no longer listed are deleted; a library whose store can't be read is skipped and its repair queued.
    // - Meaning rebuild: `RAGService.rebuildSemanticIndex`, the Documents tab banner's action: every document's stored
    //   passages embedded again (`reembedDocuments`, self-healing path), the file read again only when none are stored.

    var maintenanceSection: some View {
        let reclaimable = reclaimableBytes
        let keywordProblem = keywordIndexProblem
        return VStack(spacing: DSSpacing.lg) {
            maintenanceSummaryCard(keywordProblem: keywordProblem, reclaimable: reclaimable)
            meaningIndexCard
            keywordCheckCard
            keywordRebuildCard(problem: keywordProblem)
            reclaimSpaceCard(reclaimable: reclaimable)
            if settings.showTechnicalDetails, let diag = deepDiagnostics {
                DatabaseCard(icon: "info.circle.fill", title: "Database Info") {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        DatabaseInfoRow(label: "Journal Mode", value: diag.journalMode.uppercased())
                        DatabaseInfoRow(label: "Auto Vacuum", value: diag.autoVacuum)
                        DatabaseInfoRow(label: "Integrity", value: diag.integrityCheckResult)
                        DatabaseInfoRow(label: "Page Count", value: "\(diag.pageCount)")
                        DatabaseInfoRow(label: "Free Pages", value: "\(diag.freePageCount)")
                    }
                }
            }
        }
        .confirmationDialog(
            "Rebuild the keyword index?", isPresented: $confirmsKeywordRebuild, titleVisibility: .visible
        ) {
            Button("Rebuild All \(keywordRebuildLibraryCount) \(keywordRebuildLibraryCount == 1 ? "Library" : "Libraries")") {
                Task { await performDetailedRebuild() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(keywordRebuildConfirmation)
        }
        .confirmationDialog(
            "Rebuild search by meaning?",
            isPresented: Binding(
                get: { meaningRebuildToConfirm != nil }, set: { if !$0 { meaningRebuildToConfirm = nil } }),
            titleVisibility: .visible,
            presenting: meaningRebuildToConfirm
        ) { library in
            Button("Rebuild \(library.name)") { startMeaningRebuild(library.id) }
            Button("Cancel", role: .cancel) {}
        } message: { library in
            let count = ragService.documentsForContainer(library.id).count
            Text(
                "\(library.name)'s index is healthy, so this isn't expected to change its answers. It works out the meaning of every passage of its \(count) \(count == 1 ? "document" : "documents") again, reading a file again only where no passages are stored. That takes minutes on a large library and keeps the device busy, so it can get warm. No document is deleted, and answers in this library can miss information until it finishes."
            )
        }
    }

    // MARK: Findings

    /// The libraries the Maintenance cards cover: the one chosen above, or every library.
    var maintenanceLibraries: [KnowledgeContainer] {
        guard let id = scopedContainerId else { return containerService.containers }
        return containerService.containers.filter { $0.id == id }
    }

    /// Space the keyword file holds but no longer uses (`PRAGMA freelist_count` times the page size).
    var reclaimableBytes: Int64 {
        guard let diag = deepDiagnostics else { return 0 }
        return Int64(diag.freePageCount * diag.pageSize)
    }

    /// Reclaiming rewrites the whole file, so it is offered as the next step only when the gain is worth that: at least
    /// 1 MB and a tenth of the file. A few hundred KB is offered quietly.
    func reclaimIsWorthIt(_ reclaimable: Int64) -> Bool {
        guard let diag = deepDiagnostics else { return false }
        return reclaimable >= 1_000_000 && Double(reclaimable) >= Double(diag.databaseSizeBytes) * 0.1
    }

    /// Why the keyword index needs rebuilding, in words, or nil when the checks found nothing. Three findings count: a
    /// problem the last Check reported, the load-time comparison of the index's document list with the text it holds
    /// (`getDeepDiagnostics`, "mismatch" when they differ), and a library whose keyword index holds a different number
    /// of documents from the number it lists. Not judged while an import or rebuild runs, when they differ by design.
    var keywordIndexProblem: String? {
        if let problem = integrityResults.first(where: { !$0.lowercased().hasSuffix("ok") }) {
            return "The last check reported a problem (\(problem))."
        }
        if let diag = deepDiagnostics, diag.integrityCheckResult.lowercased().hasPrefix("mismatch") {
            return settings.showTechnicalDetails
                ? "The documents table and document_meta disagree: \(diag.integrityCheckResult)."
                : "The keyword index's list of documents and the text it holds don't match, so some documents can't be found by their words."
        }
        guard !ragService.isProcessing, !isRebuildingIndex, let stats else { return nil }
        for library in maintenanceLibraries {
            let listed = ragService.documentsForContainer(library.id).count
            let indexed = stats.containerStats.first { $0.containerId == library.id }?.documentCount ?? 0
            if listed > indexed {
                let missing = listed - indexed
                return "\(missing) \(missing == 1 ? "document" : "documents") in \(library.name) \(missing == 1 ? "isn't" : "aren't") in the keyword index, so a search for \(missing == 1 ? "its" : "their") exact words can't find \(missing == 1 ? "it" : "them")."
            }
            if indexed > listed {
                let extra = indexed - listed
                return "The keyword index holds \(extra) \(extra == 1 ? "document" : "documents") for \(library.name) that the library no longer lists."
            }
        }
        return nil
    }

    /// Libraries the keyword rebuild covers: every library with documents, whatever the scope above says.
    var keywordRebuildLibraryCount: Int {
        containerService.containers.filter { !ragService.documentsForContainer($0.id).isEmpty }.count
    }

    var keywordRebuildConfirmation: String {
        let documents = ragService.documents.count
        return
            "This writes the keyword index of every library (\(keywordRebuildLibraryCount), \(documents) \(documents == 1 ? "document" : "documents")) again from the passages already stored. No file is read again, nothing is embedded again and no document is deleted. Leftover passages of documents no longer in a library are removed. Until it finishes, a search for exact words can miss results."
    }

    // MARK: Cards

    private func maintenanceSummaryCard(keywordProblem: String?, reclaimable: Int64) -> some View {
        let meaningFlagged = maintenanceLibraries.filter { ragService.librariesNeedingIndexRebuild.contains($0.id) }
        let healthy = meaningFlagged.isEmpty && keywordProblem == nil
        return DatabaseCard(
            icon: healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", title: "Health",
            caption: scopeSubtitle
        ) {
            Text(healthy ? "Healthy" : "Needs a repair")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColors.readable(healthy ? .green : .orange))
        } content: {
            MaintenanceFinding(
                ok: meaningFlagged.isEmpty, title: "Search by meaning",
                detail: meaningFlagged.isEmpty
                    ? (scopedContainerId == nil
                        ? "Every library can be searched by meaning." : "\(scopeSubtitle) can be searched by meaning.")
                    : "\(meaningFlagged.map(\.name).joined(separator: ", ")) \(meaningFlagged.count == 1 ? "needs" : "need") a rebuild. See below.")
            MaintenanceFinding(
                ok: keywordProblem == nil, title: "Keyword index",
                detail: keywordProblem ?? "Every listed document is in the keyword index.")
            MaintenanceFinding(
                ok: true, title: "Unused space",
                detail: reclaimable == 0
                    ? "None."
                    : "\(formatBytes(reclaimable)) of \(formatBytes(deepDiagnostics?.databaseSizeBytes ?? 0)), all libraries.")
            Text(
                healthy
                    ? "Nothing here needs running. The buttons below stay available, and each says what it changes."
                    : "The repair for each problem is marked below."
            )
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One row per library: its meaning index's state and a rebuild, prominent only when the app flagged the library.
    private var meaningIndexCard: some View {
        DatabaseCard(icon: "brain", title: "Rebuild Search by Meaning") {
            Text(
                "Works out the meaning of each stored passage again. It's the repair for a library the app flags here, and it doesn't import files again or delete documents. It takes minutes on a large library, keeps the device busy, and on a healthy library isn't expected to change answers."
            )
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(maintenanceLibraries) { library in
                meaningIndexRow(library)
                if library.id != maintenanceLibraries.last?.id { Divider() }
            }
        }
    }

    @ViewBuilder
    private func meaningIndexRow(_ library: KnowledgeContainer) -> some View {
        let documents = ragService.documentsForContainer(library.id).count
        let flagged = ragService.librariesNeedingIndexRebuild.contains(library.id)
        let progress = ragService.libraryRebuildProgress?.libraryId == library.id ? ragService.libraryRebuildProgress : nil
        let waiting = ragService.librariesWaitingForRebuild.contains(library.id)
        HStack(alignment: .center, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(library.name)
                    .font(.subheadline.weight(.medium))
                Group {
                    if let progress {
                        Text("Rebuilding: \(progress.done + 1) of \(progress.total), now \(progress.filename).")
                    } else if waiting {
                        Text("Waiting to rebuild. Libraries rebuild one at a time.")
                    } else if documents == 0 {
                        Text("No documents.")
                    } else if flagged {
                        Text(
                            "Needs a rebuild: the last check found passages that search by meaning can't reach, or that were prepared under earlier settings. Answers here can miss information until it's rebuilt."
                        )
                        .foregroundStyle(DSColors.readable(.orange))
                    } else {
                        Text("Healthy, \(documents) \(documents == 1 ? "document" : "documents"). No rebuild needed.")
                    }
                }
                .font(.caption)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DSSpacing.xs)
            if progress != nil || waiting {
                ProgressView().controlSize(.small)
            } else if documents > 0 {
                if flagged {
                    Button("Rebuild") { startMeaningRebuild(library.id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button("Rebuild") { meaningRebuildToConfirm = library }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func startMeaningRebuild(_ libraryId: UUID) {
        DSHaptics.light()
        ragService.rebuildSemanticIndex(for: libraryId)
    }

    private var keywordCheckCard: some View {
        DatabaseCard(icon: "checkmark.shield.fill", title: "Check the Keyword Index") {
            Button {
                Tour.used(.runCheck)
                isCheckingIntegrity = true
                Task {
                    integrityResults = await SQLiteFullTextService.shared.runIntegrityCheck()
                    isCheckingIntegrity = false
                }
            } label: {
                if isCheckingIntegrity {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Check")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isCheckingIntegrity)
            .tour(.runCheck, in: Tour.database)
        } content: {
            Text(
                "Reads the whole keyword index and reports any damage. It changes nothing, so it's always safe. It reads every page of the file (\(formatBytes(deepDiagnostics?.databaseSizeBytes ?? 0)) now, all libraries), so on a large library it takes a while."
            )
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(integrityResults, id: \.self) { result in
                let ok = result.lowercased().hasSuffix("ok")
                Label {
                    Text(settings.showTechnicalDetails ? result : (ok ? "No damage found" : result))
                        .font(.subheadline)
                } icon: {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? .green : .red)
                }
            }
        }
    }

    private func keywordRebuildCard(problem: String?) -> some View {
        DatabaseCard(icon: "arrow.triangle.2.circlepath", title: "Rebuild the Keyword Index") {
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
            if problem != nil {
                rebuildKeywordButton.buttonStyle(.borderedProminent)
            } else {
                rebuildKeywordButton.buttonStyle(.bordered)
            }
        } content: {
            Text(
                settings.showTechnicalDetails
                    ? "Clears each library's FTS5 rows (documents and chunks tables) and writes them again from the passages in its vector store. Every library, whatever the scope above. No re-embedding, no file read. Vector chunks of documents no longer in the catalog are deleted. Time grows with the number of passages."
                    : "Writes the word index of every library again from the passages already stored. No file is read again and no document is deleted; leftover passages of documents no longer in a library are removed. Time grows with the number of passages."
            )
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            MaintenanceRecommendation(
                recommended: problem != nil,
                text: problem.map { "Recommended: \($0)" }
                    ?? "Not needed now: the checks found the keyword index complete, so a rebuild has nothing to repair.")

            if let result = lastKeywordRebuildResult, !isRebuildingIndex {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DSColors.readable(.green))
            }

            if showRebuildLog && !rebuildLogs.isEmpty {
                rebuildLogView
            }

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
    }

    private var rebuildKeywordButton: some View {
        Button {
            confirmsKeywordRebuild = true
        } label: {
            if isRebuildingIndex {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Rebuild")
            }
        }
        .controlSize(.small)
        .disabled(isRebuildingIndex)
    }

    private func reclaimSpaceCard(reclaimable: Int64) -> some View {
        let worthIt = reclaimIsWorthIt(reclaimable)
        return DatabaseCard(icon: "bolt.circle.fill", title: "Reclaim Unused Space") {
            Group {
                if worthIt {
                    reclaimButton.buttonStyle(.borderedProminent)
                } else {
                    reclaimButton.buttonStyle(.bordered)
                }
            }
        } content: {
            Text(
                settings.showTechnicalDetails
                    ? "Runs FTS5 optimize, then VACUUM, which rewrites the whole file. Needs free space up to the file's size while it runs. Nothing is deleted."
                    : "Packs the keyword index together and rewrites its file without the space it no longer uses. Nothing is deleted. It rewrites the whole file, so it takes longer the bigger the file, and it needs that much free space while it runs."
            )
            .font(.caption)
            .foregroundStyle(DSColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            MaintenanceRecommendation(
                recommended: worthIt,
                text: reclaimable == 0
                    ? "Not needed now: the file has no unused space."
                    : worthIt
                        ? "Recommended: \(formatBytes(reclaimable)) of the file is unused."
                        : "Not needed now: only \(formatBytes(reclaimable)) is unused, too little to be worth rewriting the file.")

            if let result = lastOptimizeResult {
                Label(result, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DSColors.readable(.green))
            }
        }
    }

    private var reclaimButton: some View {
        Button {
            Task {
                isOptimizing = true
                let result = await SQLiteFullTextService.shared.optimize()
                if result.success {
                    lastOptimizeResult =
                        "Freed \(formatBytes(result.freedBytes)) in \(String(format: "%.1f", result.elapsedMs)) ms"
                } else {
                    lastOptimizeResult = "Optimization failed"
                }
                isOptimizing = false
                await loadAllData()  // Refresh stats
            }
        } label: {
            if isOptimizing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Reclaim")
            }
        }
        .controlSize(.small)
        .disabled(isOptimizing)
    }

    // MARK: - Search Section

    var searchSection: some View {
        VStack(spacing: DSSpacing.lg) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    settings.showTechnicalDetails ? "Search FTS5 index..." : "Search for words in your documents…",
                    text: $searchQuery
                )
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
            .font(.subheadline)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm + 2)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))

            // Search tips
            if searchResults.isEmpty && searchQuery.isEmpty {
                DatabaseCard(
                    icon: "lightbulb.fill",
                    title: settings.showTechnicalDetails ? "Query Handling" : "How Search Reads Your Words"
                ) {

                    // What the search does with what is typed (2026-11-16). This card listed FTS5's operators (OR, NOT,
                    // "phrase", word*, NEAR, ^) through 5.8's first builds, and none of them reached the index:
                    // `search` passes the text through `escapeFTS5Query`, which drops punctuation, skips stopwords and
                    // words under two letters, and quotes each remaining word, so FTS5 ANDs them as plain terms.
                    // Supporting the operators means changing that function, in the hard-boundary
                    // `SQLiteFullTextService.swift`, so the card says what happens instead.
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        SearchTip(syntax: "lease deposit", description: "Documents that contain every word you type")
                        SearchTip(syntax: "deposit", description: "Also finds \"deposits\": word endings don't matter")
                        if settings.showTechnicalDetails {
                            SearchTip(
                                syntax: "escapeFTS5Query",
                                description:
                                    "Each word is quoted and the words are ANDed; punctuation, stopwords and one-letter words are dropped, so OR, NOT, \"phrase\", word*, NEAR and ^ are not passed to FTS5")
                        } else {
                            SearchTip(
                                syntax: "OR, NOT, \"…\"",
                                description: "Not supported here: quotes and symbols are ignored, and OR or NOT is searched as a word")
                        }
                    }

                    Text(
                        settings.showTechnicalDetails
                            ? "Queries are case-insensitive. BM25 ranking is used for relevance scoring."
                            : "Capital letters don't matter, and the best matches come first."
                    )
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                }
            }

            // Search timing, with Technical Details on (2026-11-16); the result count is on the Results card.
            if settings.showTechnicalDetails, let metrics = searchMetrics {
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
                DatabaseCard(icon: "list.bullet", title: "Results") {
                    Text("\(searchResults.count) matches")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.secondaryText)
                } content: {
                    ForEach(searchResults, id: \.documentId) { result in
                        SearchResultRow(result: result, documentName: documentName(for: result.documentId))
                        if result.documentId != searchResults.last?.documentId {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    var emptyDatabaseState: some View {
        SurfaceCard {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: "cylinder")
                    .font(.title2)
                    .foregroundStyle(DSColors.secondaryText)

                Text(settings.showTechnicalDetails ? "Database Empty" : "No Documents Yet")
                    .font(.headline)

                Text(
                    settings.showTechnicalDetails
                        ? "Add documents to populate the SQLite FTS5 full-text search index"
                        : "Add documents and their words show up here."
                )
                .font(.subheadline)
                .foregroundStyle(DSColors.secondaryText)
                .multilineTextAlignment(.center)
            }
            .padding(.vertical, DSSpacing.lg)
            .frame(maxWidth: .infinity)
        }
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
        if ratio < 0.3 {
            return .green
        } else if ratio < 0.6 {
            return .accentColor
        } else if ratio < 0.9 {
            return .orange
        } else {
            return .red
        }
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
                Text("Rebuild Log")
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
                                    .font(.caption2)
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
            .background(
                Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
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
        addLog("⚡ Rebuilding the keyword index from stored passages...", type: .step)
        addLog("  Each library's keyword rows are written again from its vector store; no file is read.", type: .info)
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
        addLog(
            "  Documents: \(postStats.totalDocuments) \(docMatch ? "✓" : "⚠️ changed")",
            type: docMatch ? .success : .warning)
        addLog(
            "  Words: \(formatLargeNumber(postStats.totalWords)) \(wordMatch ? "✓" : "⚠️ changed")",
            type: wordMatch ? .success : .warning)
        await Task.yield()

        // Step 7: Final summary
        addLog("", type: .info)
        if success {
            addLog("🎉 Database rebuild completed successfully!", type: .success)
            addLog("  Total time: \(String(format: "%.2f", elapsed))ms", type: .info)
            // Its own line on the rebuild's card (2026-11-16); it was written into the Optimize card's result.
            lastKeywordRebuildResult = "Rebuilt in \(String(format: "%.1f", elapsed / 1000)) s"
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
