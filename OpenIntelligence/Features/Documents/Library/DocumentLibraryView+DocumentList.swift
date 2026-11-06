//
//  DocumentLibraryView+DocumentList.swift
//  OpenIntelligence
//
//  Part of DocumentLibraryView, moved from DocumentLibraryView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

extension DocumentLibraryView {
    /// Content shown below the persistent `documentHeader`, for a library with no documents.
    ///
    /// `documentHeader` used to live inside this view *and* inside `documentListContent`, as two
    /// separate calls to the same computed property. `libraryContentView` swaps between the two
    /// with a plain `if/else`, and SwiftUI cannot tell that a `documentHeader` on one side of that
    /// branch is "the same" view as a `documentHeader` on the other — they are different parents,
    /// so crossing the branch tore the whole header down and rebuilt it, including
    /// `ContainerPickerStrip`'s horizontal `ScrollView`. A rebuilt `ScrollView` starts at its
    /// leading edge, which is why switching to or from an empty library made the library picker
    /// visibly jump back to the first pill and the whole screen flash, even though
    /// `containerService.activeContainerId` never actually changed. `documentHeader` is now
    /// rendered once, by `libraryContentView`, above this branch entirely, and since 5.7 so is the row of
    /// libraries, `libraryPicker`, which is no longer part of it.
    var emptyStateContent: some View {
        ScrollView {
            emptyStateStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The empty state itself, scrolled by `emptyStateContent`, or with the header at accessibility text sizes (5.7).
    var emptyStateStack: some View {
        VStack(spacing: DSSpacing.lg) {
            EmptyDocumentsView(
                isImportingSamples: isImportingSamples,
                hasImportedSamples: onboardingStore.hasImportedSamples,
                isAtDocumentLimit: isAtDocumentLimit,
                documentLimit: documentLimit,
                statusMessage: sampleImportStatusMessage,
                onImportSamples: importSampleWorkspace,
                onPickFiles: presentDocumentPickerOrUpgrade
            )
            .padding(.horizontal, DSSpacing.lg)
        }
        .padding(.bottom, DSSpacing.xl)
    }

    /// Content shown below the persistent `documentHeader`, for a library with documents.
    /// See `emptyStateContent` for why `documentHeader` no longer lives in here.
    var documentListContent: some View {
        Group {
            // Document list with modern styling
            withSwipeDeleteAlert(
                ScrollView {
                    documentCards
                }
                // The cards carry swipe actions from iOS and macOS 27 (`DocumentSwipeToDelete`).
                .modifier(SwipeActionsContainerOn27())
            )
        }
    }

    /// The document cards and the stats footer, scrolled by `documentListContent`, or with the header at
    /// accessibility text sizes (5.7).
    @ViewBuilder
    var documentCards: some View {
        documentCardList
            .tour(.dragAndDrop, in: Tour.documents, arrow: .bottom)
    }

    @ViewBuilder
    private var documentCardList: some View {
        LazyVStack(spacing: DSSpacing.md) {
            ForEach(filteredDocuments) { document in
                NavigationLink(destination: DocumentDetailsView(
                    document: document,
                    embeddingProviderId: containerService.activeContainer?.embeddingProviderId
                )) {
                    ModernDocumentCard(document: document, ragService: ragService)
                }
                .buttonStyle(.plain)
                // Each card names its document, so Siri and Apple Intelligence know which
                // documents are on screen (5.7).
                .appEntityIdentifier(.document(document.id))
                .modifier(DocumentSwipeToDelete { swipeDelete(document) })
                .tour(.documentMenu, in: Tour.documents, when: document.id == filteredDocuments.first?.id)
            }
        }
        .padding(DSSpacing.lg)

        // Stats footer with Auto Intelligence indicator
        StatsFooter(
            totalDocuments: filteredDocuments.count,
            totalChunks: filteredTotalChunks,
            autoIntelligenceEnabled: containerService.activeContainer?.autoAdaptDimension ?? true
        )
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)

        // The Siri phrase that finds passages in the open library, the one listed above (5.7).
        SiriPhraseTip(.findPassages)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
    }

    /// The confirmation a swipe asks for before it deletes a document in an iCloud library (`swipeDelete`), on the
    /// list's scroll view in either layout.
    func withSwipeDeleteAlert<Content: View>(_ content: Content) -> some View {
        content.alert(
            "Delete Document?",
            isPresented: Binding(
                get: { swipeDeleteCandidate != nil },
                set: { if !$0 { swipeDeleteCandidate = nil } }),
            presenting: swipeDeleteCandidate
        ) { document in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                ragService.scheduleRemoval(of: [document], undoManager: undoManager)
            }
        } message: { document in
            Text(ModernDocumentCard.sharedDeleteMessage(for: document.filename))
        }
    }

    /// A swipe deletes a document only this device has at once, because the deletion can be undone for a few
    /// seconds; one in an iCloud library asks first, as Delete in its menu does (5.7).
    private func swipeDelete(_ document: Document) {
        if ragService.syncMode(for: document) == .iCloudShared {
            swipeDeleteCandidate = document
        } else {
            ragService.scheduleRemoval(of: [document], undoManager: undoManager)
        }
    }

    /// The header above the row of libraries: the title, the storage picker and the action buttons. It takes dropped
    /// files, and the row of libraries below it does not (`takingDroppedFiles(as:)`).
    var documentHeader: some View {
        VStack(spacing: DSSpacing.md) {
            documentSectionHeader
                .padding(.horizontal, DSSpacing.lg)

            documentActionStrip
                // This action empties a library and keeps the library itself, which is exactly
                // the "wipe" operation the app was missing, so it is named that now.
                //
                // Its previous name and copy were not merely unclear, they were false. On an
                // iCloud library it read "Remove Local Copies" and promised "If those documents
                // still exist in iCloud Sync, Sync Now can bring them back." They cannot.
                // `clearAllDocuments` calls `registerDeletedDocuments`, which appends every id to
                // `deleted_documents.json`; the sync service unions that file into both workspace
                // roots and then filters those ids out of the shared inventory, so the next pass
                // removes them from iCloud and from every other device. `BNNSVectorDatabase.clear()`
                // posts `.localWorkspaceDidChange`, which schedules that pass about two seconds
                // later. There is no local-only eviction here to describe.
                //
                // The wording is now the same for both storage modes, because the outcome is.
                .alert("Remove all documents from \"\(activeLibrary?.name ?? "this library")\"?", isPresented: $showingClearAllConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Remove All Documents", role: .destructive) {
                        Task {
                            try? await ragService.clearAllDocuments()
                        }
                    }
                } message: {
                    if let activeLibrary, activeLibrary.syncMode == .iCloudShared {
                        Text("Deletes all \(ragService.documents.filter { $0.containerId == activeLibrary.id }.count) documents in this library, here and in iCloud, on every device signed in to it. The library itself stays. This cannot be undone.")
                    } else if let activeLibrary {
                        Text("Deletes all \(ragService.documents.filter { $0.containerId == activeLibrary.id }.count) documents in \"\(activeLibrary.name)\". The library itself stays. This cannot be undone.")
                    } else {
                        Text("Deletes every document in this library. The library itself stays. This cannot be undone.")
                    }
                }
                .alert(
                    "Move \"\(pendingLocalOnlyLibrary?.name ?? "this library")\" off iCloud?",
                    isPresented: Binding(
                        get: { pendingLocalOnlyLibrary != nil },
                        set: { if !$0 { pendingLocalOnlyLibrary = nil } }
                    )
                ) {
                    Button("Cancel", role: .cancel) { pendingLocalOnlyLibrary = nil }
                    Button("Move Off iCloud", role: .destructive) {
                        if let pending = pendingLocalOnlyLibrary {
                            pendingLocalOnlyLibrary = nil
                            handleSetLibrarySyncMode(pending, .localOnly, confirmed: true)
                        }
                    }
                } message: {
                    Text("This library's copy in iCloud is removed, and it stops appearing on your other devices. The documents stay on this device. Switching back to iCloud Sync uploads them again.")
                }
        }
    }

    /// The row of libraries, in none of the library area's file drop targets (`takingDroppedFiles(as:)`, 5.7).
    var libraryPicker: some View {
        ContainerPickerStrip(
            containerService: containerService,
            allowsCreation: true,
            onCreateLibrary: handleNewLibraryTapped,
            onDeleteLibrary: handleDeleteLibrary,
            // Wrapped rather than passed by reference. `handleSetLibrarySyncMode` gained a
            // defaulted `confirmed:` parameter, and Swift does not apply default arguments
            // when a function is used as a value, so the bare reference no longer matches
            // the two-parameter closure this expects.
            onSetLibraryStorage: { container, syncMode in
                handleSetLibrarySyncMode(container, syncMode)
            }
        )
        .alert("New Library", isPresented: $showingNewLibraryPrompt) {
            TextField("Library name", text: $newLibraryName)
            Button("Cancel", role: .cancel) {
                newLibraryName = ""
                pendingNewLibraryName = ""
            }
            Button("Create") {
                pendingNewLibraryName = newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                shouldShowStorageChoiceAfterDismissal = true
            }
        } message: {
            Text("Enter a name for your new library")
        }
        .confirmationDialog("Choose Library Storage", isPresented: $showingNewLibraryStorageChoice, titleVisibility: .visible) {
            Button("Local Only") {
                createNewLibrary(syncMode: .localOnly)
            }
            Button("iCloud Sync") {
                createNewLibrary(syncMode: .iCloudShared)
            }
            Button("Cancel", role: .cancel) {
                pendingNewLibraryName = ""
            }
        } message: {
            Text("Local Only keeps the library only on this device. iCloud Sync makes iCloud the shared copy for that library across your devices.")
        }
        // Names the library, matching the remove-all-documents alert above, so the two
        // destructive confirmations read as clearly different actions rather than as two
        // similar red dialogs.
        .alert("Delete the \"\(libraryToDelete?.name ?? "selected")\" library?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                libraryToDelete = nil
            }
            if libraryToDelete?.syncMode == .iCloudShared {
                Button("Delete from iCloud", role: .destructive) {
                    confirmDeleteLibrary()
                }
            } else {
                Button("Delete Locally", role: .destructive) {
                    confirmDeleteLibrary()
                }
            }
        } message: {
            if let lib = libraryToDelete {
                let docCount = ragService.documents.filter { $0.containerId == lib.id }.count
                if lib.syncMode == .iCloudShared {
                    Text("This will permanently delete \"\(lib.name)\" from iCloud Sync and remove it from every device using that shared library, along with all \(docCount) document\(docCount == 1 ? "" : "s"). This cannot be undone.")
                } else {
                    Text("This will permanently delete \"\(lib.name)\" only on this device, along with all \(docCount) document\(docCount == 1 ? "" : "s") inside it. This cannot be undone.")
                }
            } else {
                Text("This will permanently delete this library and all documents inside it.")
            }
        }
    }

    /// The banners below the row of libraries, shown above the documents and taking dropped files with them.
    @ViewBuilder
    var documentBanners: some View {
        sharedWorkspaceBanner
            .padding(.horizontal, DSSpacing.lg)

        // The guide library (5.8): what it is, and where the person's own files go.
        if containerService.isGuideLibrary(containerService.activeContainerId) {
            Label {
                Text(
                    "OpenIntelligence's own guides, free and outside your plan's limits. Ask this library how the app works. Files you add go to \(containerService.containers.first { !containerService.isGuideLibrary($0.id) }?.name ?? "your library")."
                )
                .font(.footnote)
                .foregroundStyle(DSColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(DSColors.accent)
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
            .padding(.horizontal, DSSpacing.lg)
        }

        if shouldShowQuotaBanner {
            DocumentQuotaBanner(
                currentCount: ragService.countedDocumentCount,
                limit: documentLimit,
                tierName: entitlementStore.currentPlanDisplayName,
                addOnPacks: entitlementStore.addOnPacks,
                onUpgrade: { presentPlanSheet(for: .quotaBanner) }
            )
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    private var syncModeBinding: Binding<LibrarySyncMode> {
        Binding(
            get: {
                activeLibrary?.syncMode ?? .localOnly
            },
            set: { newMode in
                if let activeLibrary {
                    handleSetLibrarySyncMode(activeLibrary, newMode)
                }
            }
        )
    }

    private var documentSectionHeader: some View {
        // At accessibility text sizes the picker goes under the title, which beside it broke as "Docu-ments" (5.7).
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DSSpacing.md))
        return layout {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Documents")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(DSColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(documentSectionSubtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DSColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !stacked {
                Spacer(minLength: DSSpacing.sm)
            }

            HStack(spacing: DSSpacing.sm) {
                if activeLibrary != nil {
                    Picker("Sync Mode", selection: syncModeBinding) {
                        Text("Local").tag(LibrarySyncMode.localOnly)
                        Text("iCloud").tag(LibrarySyncMode.iCloudShared)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .labelsHidden()
                    .disabled(isRefreshingSharedWorkspace)
                }

                if hasConfiguredICloudLibraries {
                    Button {
                        DSHaptics.light()
                        refreshSharedWorkspaceNow()
                    } label: {
                        if isRefreshingSharedWorkspace {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .frame(minWidth: DSSpacing.tapTarget, minHeight: DSSpacing.tapTarget)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .scaledFont(size: 14, weight: .bold)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.08))
                                )
                                .glassCircleEffectHelper()
                                .frame(minWidth: DSSpacing.tapTarget, minHeight: DSSpacing.tapTarget)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingSharedWorkspace)
                }
            }
        }
        // Stacked, the block is only as wide as its widest line, and the header's stack would center it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var documentSectionSubtitle: String {
        if let activeLibrary {
            let documentLabel = filteredDocuments.count == 1 ? "document" : "documents"
            return "\(filteredDocuments.count) \(documentLabel) in \(activeLibrary.name)"
        }

        let documentLabel = ragService.documents.count == 1 ? "document" : "documents"
        return "\(ragService.documents.count) \(documentLabel) in this workspace"
    }

    /// Two everyday actions, then everything else behind one menu.
    ///
    /// This was six chips in a horizontal `ScrollView` with `showsIndicators: false`, so at
    /// iPhone width the last three were off-screen with nothing on the screen suggesting they
    /// existed. Manage Library is the only route to `ContainerSettingsSheet` and Wipe Library is
    /// destructive, so both were effectively hidden behind a swipe nobody knew to make.
    ///
    /// Add Document and Semantic Search stay as chips because they are what someone comes to this
    /// screen to do. The rest move into a menu that is always visible at a fixed position.
    /// Visualize is gone entirely: it called `onViewVisualizations`, whose only implementation in
    /// `ContentView` sets `selectedTab = .visualizations`, passing no scope and no deep link, and
    /// that tab renders `AdaptiveVisualizationsView()` which takes no parameters. The chip was a
    /// second button for the Atlas tab sitting two inches above the Atlas tab.
    private var documentActionStrip: some View {
        HStack(spacing: DSSpacing.md) {
            DocumentActionChip(
                title: "Add Document",
                systemImage: "plus",
                iconOnly: true
            ) {
                Tour.used(.addDocument)
                DSHaptics.light()
                presentDocumentPickerOrUpgrade()
            }
            .tour(.addDocument, in: Tour.documents)

            // A copied file, web address or text. The same chip as its neighbours; what it stores
            // takes the plan check and the import review that a file handed over by another app
            // takes.
            LibraryPasteButton { staged in
                Tour.used(.paste)
                DSHaptics.drop()
                importOpenedFiles(staged)
            } label: { isWorking in
                DocumentActionChipLabel(
                    title: "Paste",
                    systemImage: isWorking ? "hourglass" : "doc.on.clipboard",
                    isEnabled: !isWorking,
                    iconOnly: true
                )
            }
            .tour(.paste, in: Tour.documents)

            DocumentActionChip(
                title: "Semantic Search",
                systemImage: "sparkle.magnifyingglass",
                isEnabled: !ragService.documents.isEmpty,
                iconOnly: true
            ) {
                Tour.used(.semanticSearch)
                DSHaptics.selection()
                showingSemanticSearch = true
            }
            .tour(.semanticSearch, in: Tour.documents)

            DocumentActionChip(
                title: "Library Settings",
                systemImage: "slider.horizontal.3",
                iconOnly: true
            ) {
                Tour.used(.librarySettings)
                DSHaptics.light()
                showingContainerSettings = true
            }
            .tour(.librarySettings, in: Tour.documents)

            // Shown only when the cache can actually contain something.
            //
            // `DocumentationCacheService.cache(...)` is its only writer and has no call sites
            // anywhere in the app, so nothing populates this and the screen was permanently
            // empty. That is not dead code: the producer is the open roadmap row "Web Clipper
            // / Share Extension", and the service, its expiry, pruning and ingestion export
            // are all built and waiting for it. Deleting them would repeat a mistake this
            // repository has already made twice.
            //
            // Gating on content rather than removing the entry means the door disappears
            // while the room is empty and comes back on its own the day something fills it.
            if cachedDocumentCount > 0 {
                DocumentActionChip(
                    title: "Cached Documents (\(cachedDocumentCount))",
                    systemImage: "doc.on.doc.fill",
                    iconOnly: true
                ) {
                    DSHaptics.light()
                    showCachedDocs = true
                }
            }

            Spacer(minLength: 0)

            // The two destructive actions are direct buttons rather than items behind an
            // overflow menu, by explicit request: five buttons, no ellipsis, nothing hidden
            // behind an extra tap.
            //
            // They are not the same action and they must not read as the same action. One
            // empties a library and keeps it; the other removes the library itself. So the
            // glyphs deliberately do not rhyme, a Spacer separates them from the constructive
            // actions, and only the nuclear one is tinted red — a row of identical red icons
            // is how a user taps the wrong one.
            //
            // Losing the text label costs the on-screen indication of *which* library is
            // affected. That is recovered rather than dropped: both already route through a
            // confirmation that names the library and states what survives, and the name is
            // carried here in `accessibilityLabel` so VoiceOver still announces it in full.
            //
            // Enabled against `filteredDocuments`, the documents this screen is actually
            // showing, rather than `ragService.documents`, which is every document in every
            // library. The old binding left the destructive action live on a library that is
            // visibly empty, because some other library had documents in it.
            DocumentActionChip(
                title: activeLibrary.map { "Remove All Documents from \($0.name)" } ?? "Remove All Documents",
                systemImage: "doc.badge.ellipsis",
                isEnabled: !filteredDocuments.isEmpty,
                iconOnly: true
            ) {
                DSHaptics.medium()
                showingClearAllConfirmation = true
            }

            DocumentActionChip(
                title: activeLibrary.map { "Delete \u{201C}\($0.name)\u{201D}" } ?? "Delete Library",
                systemImage: "folder.badge.minus",
                tint: .red,
                isEnabled: activeLibrary != nil && containerService.containers.count > 1,
                iconOnly: true
            ) {
                DSHaptics.medium()
                if let activeLibrary {
                    handleDeleteLibrary(activeLibrary)
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
    }

}
