//
//  DocumentLibraryView+Body.swift
//  OpenIntelligence
//
//  Part of DocumentLibraryView, moved from DocumentLibraryView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

extension DocumentLibraryView {
    var body: some View {
        VStack(spacing: 0) {
            indexRebuildBanner
            sampleRefreshBanner
            libraryAlertView
        }
        .overlay(alignment: .bottom) { pendingRemovalBar }
        .animation(DSAnimations.snappySpring, value: ragService.pendingRemovals.map(\.id))
        // Runs once per appearance and returns immediately when nothing has drifted:
        // `staleImportedSamples` compares a recorded hash per sample and exits on the
        // first mismatch check. Deliberately not run during onboarding, which is
        // importing these same files at that moment.
        .task {
            // Timed because the Documents tab is reported slow to open and four
            // separate readings of this path have failed to explain it. Reading has
            // been tried; measuring has not. `.pipeline` is in
            // `LoggingConfiguration.fileLogCategories`, so these reach a shareable
            // trace instead of only an attached console.
            let appearStarted = Date()
            // Interval from the tab tap to this task running: the part every previous
            // measurement missed. Everything timed below happens *after* the view has
            // already appeared, which is why each came back in milliseconds while the
            // tab still felt slow.
            let sinceTap = NavigationTiming.describe("documents")

            // The cached-documents count is display-only: it decides whether an
            // optional "Cached Documents" row appears, and nothing else reads it. It
            // was the first thing awaited when this tab appeared, and it is what made
            // the tab slow.
            //
            // Measured on device 2026-08-26: 44ms, 76ms and 393ms across three
            // appearances, against 0 to 4ms for the tab switch itself and single-digit
            // milliseconds for everything else on the path. `DocumentationCacheService`
            // is an actor whose initialiser does synchronous disk I/O, so the first
            // access pays for that and every access pays for the hop — to return a
            // count that is zero, for a row that then does not render.
            //
            // A child task rather than a detached one: this inherits main-actor
            // isolation, which the `@State` assignment inside requires. Nothing on
            // screen waits for it, and the row appears when the count arrives. Four
            // earlier attempts at this bug measured work that happens *after* the view
            // appears and found it fast; this line was assumed cheap and never timed.
            Task { await refreshCachedDocumentCount() }

            guard !onboardingStore.isChecklistVisible else {
                Log.info(
                    "[DocumentsTab] appear: \(sinceTap), "
                        + "total \(String(format: "%.0f", Date().timeIntervalSince(appearStarted) * 1000))ms "
                        + "(onboarding visible, samples skipped)",
                    category: .pipeline
                )
                return
            }

            let samplesStarted = Date()
            let refreshed = await SampleDocumentManager.shared.refreshStaleSamples(in: ragService)
            let samplesMs = Date().timeIntervalSince(samplesStarted) * 1000

            if !refreshed.isEmpty {
                withAnimation(DSAnimations.snappySpring) { refreshedSampleNames = refreshed }
            }

            Log.info(
                "[DocumentsTab] appear: \(sinceTap), "
                    + "staleSamples \(String(format: "%.0f", samplesMs))ms, "
                    + "total \(String(format: "%.0f", Date().timeIntervalSince(appearStarted) * 1000))ms, "
                    + "documents=\(ragService.documents.count), libraries=\(containerService.containers.count)",
                category: .pipeline
            )
        }
    }

    /// Shown when the active library holds documents but cannot answer
    /// semantically, because its vector store is missing and automatic repair was
    /// suppressed by an earlier dismissal.
    ///
    /// This state was previously invisible. The library listed its documents,
    /// keyword search kept working, and semantic retrieval silently returned
    /// nothing — so the app answered "I couldn't find information about that in
    /// your documents" for topics the document plainly covered. The rebuild
    /// regenerates embeddings from chunks already on disk: no re-import, no
    /// re-OCR, and no need to recreate the library.
    @ViewBuilder
    private var indexRebuildBanner: some View {
        let containerId = containerService.activeContainerId
        // A rebuild in this library, or one waiting its turn, says so where the Rebuild button was (5.8). The button
        // only queued it, behind any other library's rebuild, and took the banner down, so nothing on screen said
        // anything was happening.
        if let progress = ragService.libraryRebuildProgress, progress.libraryId == containerId {
            rebuildStatusRow(
                title: "Rebuilding this library: \(progress.done + 1) of \(progress.total)",
                detail: "Now on \(progress.filename). A long document takes a while, and you can keep using the app.",
                showsProgress: true)
        } else if let position = ragService.librariesWaitingForRebuild.firstIndex(of: containerId) {
            rebuildStatusRow(
                title: "Waiting to rebuild",
                detail: position == 0 && ragService.libraryRebuildProgress == nil
                    ? "It starts in a moment."
                    : "Another library is rebuilding first. Libraries rebuild one at a time.",
                showsProgress: true)
        } else if ragService.librariesNeedingIndexRebuild.contains(containerId) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(.orange)
                    .padding(.top, DSSpacing.xxs)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("This library needs its search index rebuilt")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    // A rebuild re-embeds stored passages where the chunking is unchanged and reads the document again
                    // from the kept copy otherwise (`reembedDocuments`); through 5.7 this said it "does not re-import
                    // anything" and "takes a moment", and a large PDF takes minutes.
                    Text("Your documents are intact. Answers here can miss information until it's rebuilt. A rebuild works through every document, reading it again where it has to, so a large library takes a while.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DSSpacing.xs)

                Button("Rebuild") {
                    ragService.rebuildSemanticIndex(for: containerId)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(DSSpacing.md)
            .background(Color.orange.opacity(0.12))
            .accessibilityElement(children: .combine)
        }
    }

    private func rebuildStatusRow(title: String, detail: String, showsProgress: Bool) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, DSSpacing.xxs)
            }
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(DSColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .background(DSColors.accent.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    /// The last deletion that can still be undone (5.7, `PendingDocumentRemoval`), at the bottom of the
    /// library until its seconds run out or it is undone. Styled as the chat's stage notices
    /// (`EventToastView`), with this screen's own banner button.
    @ViewBuilder
    private var pendingRemovalBar: some View {
        if let removal = ragService.pendingRemovals.last {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "trash")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.red)
                Text(removal.summary)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(DSColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DSSpacing.xs)
                Button("Undo") {
                    ragService.undoRemoval(removal.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .padding(.horizontal, DSSpacing.md)
            .padding(.bottom, DSSpacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Explains an automatic sample refresh after the fact.
    ///
    /// Without this the user watches three documents they did not touch disappear and
    /// reappear, with the ingestion theater running, for no stated reason. That reads as a
    /// bug, and it looks worst on the documents the app itself shipped. The notice names
    /// what changed and why, and stays until dismissed.
    @ViewBuilder
    private var sampleRefreshBanner: some View {
        if let names = refreshedSampleNames, !names.isEmpty {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "checkmark.seal")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, DSSpacing.xxs)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(names.count == 1 ? "Updated a sample document" : "Updated \(names.count) sample documents")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(names.joined(separator: ", ")) described things this app does not actually do. Because the app answers questions out of these documents, a wrong sentence in one becomes a wrong answer. They were re-imported with the corrections. Nothing you imported yourself was touched.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DSSpacing.xs)

                Button("OK") {
                    withAnimation(DSAnimations.snappySpring) { refreshedSampleNames = nil }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(DSSpacing.md)
            .background(Color.accentColor.opacity(0.12))
            .accessibilityElement(children: .combine)
        }
    }

    private var libraryAlertView: some View {
        librarySheetView
            .alert("Sample Import Failed", isPresented: sampleImportErrorBinding) {
                Button("OK", role: .cancel) { sampleImportError = nil }
            } message: {
                if let message = sampleImportError {
                    Text(message)
                }
            }
            .alert("Error Processing Document", isPresented: ragServiceErrorBinding) {
                Button("OK", role: .cancel) {
                    ragService.lastError = nil
                }
            } message: {
                if let error = ragService.lastError {
                    Text(error)
                }
            }
            .alert("Billing Error", isPresented: entitlementErrorBinding) {
                Button("OK", role: .cancel) {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            } message: {
                if let error = entitlementStore.lastError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingOpenedFiles, onDismiss: finishOpenedFiles) {
                OpenedFilesSheet(
                    files: openedFiles,
                    libraries: containerService.pickableContainers,
                    initialLibraryId: containerService.activeContainerId,
                    documentCount: { containerService.documentCount(for: $0) },
                    onAdd: { libraryId in
                        openedFilesLibraryId = libraryId
                        addOpenedFiles = true
                        showingOpenedFiles = false
                    },
                    onDiscard: { showingOpenedFiles = false })
                // Only Add or Don't Add closes it: a swipe would delete what may be the file's only
                // copy on the device, as with a file sent by AirDrop.
                .interactiveDismissDisabled(true)
            }
            .alert("Review Import", isPresented: $showingImportReview) {
                Button("Cancel", role: .cancel) {
                    discardPendingImportFiles()
                    pendingImportReview = nil
                }
                Button("Import Anyway") {
                    confirmPendingImport()
                }
            } message: {
                if let review = pendingImportReview {
                    Text(review.message)
                }
            }
            .confirmationDialog(sharedSyncReviewTitle, isPresented: $showingSharedSyncReviewDialog, titleVisibility: .visible) {
                if isDeletionOnlySharedConflict, let conflict = pendingSharedSyncConflict {
                    Button("Delete Here Too", role: .destructive) {
                        deleteConflictedLocalLibraries(conflict)
                    }

                    Button("Keep Them Local Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }

                    Button("Restore Them to iCloud") {
                        resolvePendingBootstrap(.mergeLibraries)
                    }
                } else if isAdditionOnlySharedConflict {
                    Button("Add iCloud Libraries Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }
                } else {
                    Button("Sync Both Directions") {
                        resolvePendingBootstrap(.mergeLibraries)
                    }

                    Button("Use iCloud State Here") {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    }
                }

                Button("Not Now", role: .cancel) {}
            } message: {
                Text(sharedSyncReviewMessage)
            }
            .userActivity(AppActivity.documents) { activity in
                activity.title = "Browse Document Library"
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
                activity.userInfo = AppActivity.userInfo(library: containerService.activeContainerId)
                activity.appEntityIdentifier = .library(containerService.activeContainerId)
            }
    }

    /// Opens the page of the document a request names; a document that is gone leaves the screen
    /// on its library. With no documents listed yet, which is also how the first moments after a
    /// launch look, the request waits up to three seconds for them, and is then let go: a request
    /// left in the queue would hold back every request behind it (`ContentView` routes the oldest).
    private func takeDocumentRequest(afterWaiting waited: Bool = false) {
        func isDocumentRequest(_ destination: AppDestination) -> Bool {
            if case .document = destination { return true }
            return false
        }
        guard AppNavigationRequest.shared.waiting.contains(where: isDocumentRequest) else { return }
        if ragService.documents.isEmpty && !waited {
            // One wait at a time, so a later request is not let go early by an earlier one's timer.
            guard documentRequestWait == nil else { return }
            documentRequestWait = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                documentRequestWait = nil
                takeDocumentRequest(afterWaiting: true)
            }
            return
        }
        guard case .document(let id)? = AppNavigationRequest.shared.take(where: isDocumentRequest) else { return }
        guard let document = ragService.documents.first(where: { $0.id == id }) else {
            Log.info("[Navigation] The document a request named is not in the library", category: .ui)
            return
        }
        // The document's own library, which the main view could not switch to before the documents
        // had loaded. A document stored before libraries existed lives in the first one.
        if let libraryId = document.containerId ?? containerService.containers.first?.id {
            containerService.setActive(libraryId)
        }
        openedDocumentID = id
    }

    private var librarySheetView: some View {
        libraryChromeView
            .onReceive(AppNavigationRequest.shared.changes) { _ in
                // Files other apps handed over: every waiting batch at once, so several files sent
                // together get one plan check and one import review.
                let handedOver = AppNavigationRequest.shared.takeAll { destination in
                    if case .importFiles = destination { return true }
                    return false
                }
                let staged = handedOver.flatMap { destination -> [URL] in
                    if case .importFiles(let urls) = destination { return urls }
                    return []
                }
                if !staged.isEmpty { importOpenedFiles(staged) }

                // Files "Open in" handed over: shown first, every waiting batch together.
                let opened = AppNavigationRequest.shared.takeAll { destination in
                    if case .openedFiles = destination { return true }
                    return false
                }.flatMap { destination -> [URL] in
                    if case .openedFiles(let urls) = destination { return urls }
                    return []
                }
                if !opened.isEmpty { showOpenedFiles(opened) }

                // "Add a Document" from Siri, Shortcuts or a link ends here, at the file picker.
                if AppNavigationRequest.shared.take(where: { $0 == .addDocument }) != nil {
                    #if os(macOS)
                        let picker = "macPanel"
                    #else
                        let picker = "picker"
                    #endif
                    VerificationJournal.record(
                        "nav.taken",
                        ["to": "addDocument",
                            "shows": entitlementStore.canAddDocument(currentCount: ragService.countedDocumentCount)
                                ? picker : "planSheet"])
                    presentDocumentPickerOrUpgrade()
                }

                // "Find in Library" from the menu, a keyboard or a link. The search needs something
                // to search, as its button on this screen does.
                if AppNavigationRequest.shared.take(where: { $0 == .search }) != nil, !ragService.documents.isEmpty {
                    handedOverSearch = ""
                    showingSemanticSearch = true
                }

                // "Search OpenIntelligence for ..." from Siri: the search screen, run for that text.
                if case .searchFor(let term)? = AppNavigationRequest.shared.take(where: { destination in
                    if case .searchFor = destination { return true }
                    return false
                }) {
                    handedOverSearch = term
                    showingSemanticSearch = true
                }

                takeDocumentRequest()
            }
            // A request that came before the documents were loaded is taken once they are.
            .onChange(of: ragService.documents.isEmpty) { _, isEmpty in
                if !isEmpty { takeDocumentRequest() }
            }
            .navigationDestination(item: $openedDocumentID) { id in
                if let document = ragService.documents.first(where: { $0.id == id }) {
                    DocumentDetailsView(
                        document: document,
                        embeddingProviderId: containerService.activeContainer?.embeddingProviderId)
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { urls in
                    reviewAndEnqueueDocuments(urls)
                }
            }
            .sheet(isPresented: $showingContainerSettings) {
                ContainerSettingsSheet(containerService: containerService, ragService: ragService)
            }
            .sheet(isPresented: $showingSemanticSearch) {
                SemanticSearchView(
                    ragService: ragService,
                    containerService: containerService,
                    initialQuery: handedOverSearch
                )
            }
            .sheet(isPresented: $showingPlanSheet) {
                PlanUpgradeSheet(entryPoint: activePaywallEntryPoint)
                    .environmentObject(entitlementStore)
            }
            .sheet(isPresented: $showCachedDocs) {
                CachedDocsView(ragService: ragService)
            }
            .onChange(of: showCachedDocs) { _, isShowing in
                // Recount on dismiss, so emptying the cache from that screen also removes the
                // entry that leads to it.
                if !isShowing { Task { await refreshCachedDocumentCount() } }
            }
    }

    /// The parts of the library area that take dropped files, such as files dragged from Finder.
    enum LibraryDropPart: Hashable {
        case header
        case documents
        case importQueue
    }

    /// Makes `content`, one part of the library area, take dropped files (5.7).
    ///
    /// Three parts, the header above the row of libraries, everything below the row and the import panel, instead of one
    /// target around the whole area as through 5.6. A drop target around the row keeps SwiftUI's reorderable chips from following a drag
    /// on iOS 27.0: the move reported the dragged chip's own place, so no library moved. Measured 2026-10-19 with a probe
    /// app in the iOS 27.0 Simulator: a target around the row broke the reorder with either of SwiftUI's drop APIs and
    /// with the target switched off for the drag, and with a target above the row and one below it the chips reordered
    /// and files dropped on either part were taken. A file dropped on the row of libraries itself is not taken.
    ///
    /// Each part takes a drop anywhere in its frame, as the one target did through its background, and not only on
    /// what it draws. A part leaves the outline when it has no area, as the import panel does when it hides, or
    /// leaves the screen, because a drag over it then may never be told it left.
    private func takingDroppedFiles<Content: View>(as part: LibraryDropPart, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .dropDestination(for: URL.self) { urls, _ in
                handleDroppedFiles(urls)
            } isTargeted: { targeted in
                if targeted {
                    dropTargetedParts.insert(part)
                } else {
                    dropTargetedParts.remove(part)
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size == .zero } action: { hasNoArea in
                if hasNoArea { dropTargetedParts.remove(part) }
            }
            .onDisappear { dropTargetedParts.remove(part) }
    }

    private var libraryChromeView: some View {
        ZStack(alignment: .bottomTrailing) {
            libraryContentView
            ingestionQueueOverlay
        }
            // The outline goes around the whole library area. The parts that take the files, everything but the row of
            // libraries, are in `libraryContentView` and the import panel (`takingDroppedFiles(as:)`).
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                        .strokeBorder(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, dash: [8])
                        )
                        .padding(DSSpacing.sm)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(DSAnimations.fastEase, value: isDropTargeted)
            .navigationTitle("Documents")
            #if os(iOS)
            // Inline at accessibility text sizes (5.7): there the large title wrapped to "Docu-" and "ments" and took a
            // fifth of the screen above the header, which carries the same name.
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            #endif
            .onAppear {
                Task { @MainActor in
                    await autoRefreshSharedWorkspaceIfNeeded()
                }
            }
            // Times a library switch end to end. `state` is the moment SwiftUI sees the
            // new selection; `settled` is after the run loop turn that renders it, which
            // is the number that corresponds to what a switch feels like. Reported
            // separately because they fail differently: a slow `state` means the work is
            // upstream of the view, a slow `settled` means body evaluation is the cost.
            .onChange(of: containerService.activeContainerId) { _, newId in
                let stateMs = NavigationTiming.elapsedMilliseconds("library")
                let switchStarted = Date()
                DispatchQueue.main.async {
                    let settledMs = Date().timeIntervalSince(switchStarted) * 1000
                    let state = stateMs.map { String(format: "%.0f", $0) + "ms" } ?? "n/a"
                    let docs = ragService.documents.filter { $0.containerId == newId }.count
                    Log.info(
                        "[LibrarySwitch] state \(state), "
                            + "settled +\(String(format: "%.0f", settledMs))ms, "
                            + "documents=\(docs)",
                        category: .pipeline
                    )
                }
            }
            // Throttled like `ContentView`'s (5.8, `ObservedChangeThrottle`).
            .onChange(of: workspaceSyncService.observedWorkspaceChangeCount) {
                ObservedChangeThrottle.run("documents.workspaceRefresh") {
                    await handleObservedSharedWorkspaceChange()
                }
            }
            .onChange(of: showingNewLibraryPrompt) { _, isShowing in
                if !isShowing && shouldShowStorageChoiceAfterDismissal {
                    shouldShowStorageChoiceAfterDismissal = false
                    // Chains are often missed if triggered too fast during alert dismissal
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms delay
                        showingNewLibraryStorageChoice = true
                    }
                }
            }
    }

    private var ingestionQueueOverlay: some View {
        // The panel takes dropped files as the area under it does (`takingDroppedFiles(as:)`); it has no area while hidden.
        takingDroppedFiles(as: .importQueue) {
            IngestionQueueOverlay(
                items: ragService.ingestionItems,
                onCancelItem: { ragService.cancelIngestionItem($0) },
                onCancelAll: { ragService.cancelAllIngestion() },
                onContinuePaused: { ragService.continuePausedIngestionQueue() },
                onDiscardPaused: { ragService.discardPausedIngestionQueue() },
                onStopAndDismiss: { ragService.stopAndDismissIngestionQueue() },
                onPause: { ragService.pauseIngestionQueue() },
                pausedByPerson: ragService.ingestionPausedByPerson,
                isAutomatic: WatchedFolderService.shared.isOnlyWatchedWork(ragService.ingestionItems)
            )
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.bottom, ingestionQueueBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var ingestionQueueBottomPadding: CGFloat {
#if os(iOS)
        72
#else
        DSSpacing.lg
#endif
    }

    private var libraryContentView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility text sizes the header alone is taller than the screen. Outside a scroll view
                // its stack was centered and spilled up under the status and navigation bars, so there the header
                // scrolls with the documents (5.7). The header still sits above the branch, for the reason given
                // at `emptyStateContent`. Crossing into or out of the accessibility sizes builds the header again,
                // which closes an alert it had open if the text size changes while one is up.
                withSwipeDeleteAlert(
                    ScrollView {
                        VStack(spacing: DSSpacing.md) {
                            takingDroppedFiles(as: .header) {
                                documentHeader
                            }

                            libraryPicker

                            takingDroppedFiles(as: .documents) {
                                VStack(spacing: DSSpacing.md) {
                                    documentBanners

                                    if filteredDocuments.isEmpty {
                                        emptyStateStack
                                    } else {
                                        documentCards
                                    }
                                }
                            }
                        }
                    }
                    .modifier(SwipeActionsContainerOn27())
                )
            } else {
                VStack(spacing: DSSpacing.md) {
                    takingDroppedFiles(as: .header) {
                        documentHeader
                    }

                    libraryPicker

                    takingDroppedFiles(as: .documents) {
                        VStack(spacing: DSSpacing.md) {
                            documentBanners

                            if filteredDocuments.isEmpty {
                                emptyStateContent
                            } else {
                                documentListContent
                            }
                        }
                    }
                }
            }

            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var sampleImportErrorBinding: Binding<Bool> {
        Binding(
            get: { sampleImportError != nil },
            set: { if !$0 { sampleImportError = nil } }
        )
    }

    private var ragServiceErrorBinding: Binding<Bool> {
        Binding(
            get: { ragService.lastError != nil },
            set: { if !$0 { ragService.lastError = nil } }
        )
    }

    private var entitlementErrorBinding: Binding<Bool> {
        Binding(
            get: { entitlementStore.lastError != nil },
            set: { newValue in
                if !newValue {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            }
        )
    }

}
