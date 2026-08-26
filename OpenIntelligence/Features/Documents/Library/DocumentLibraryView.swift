//
//  DocumentLibraryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspaceSyncService: WorkspaceSyncService
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    @State private var showingFilePicker = false
    @State private var showingProcessingSummary = false
    @State private var lastProcessedSummary: ProcessingSummary?
    @State private var showingContainerSettings = false
    @State private var showingSemanticSearch = false
    @State private var isImportingSamples = false
    /// Display names of samples just refreshed automatically, driving the explanatory
    /// banner. `nil` once dismissed.
    @State private var refreshedSampleNames: [String]?
    @State private var sampleImportError: String?
    @State private var sampleImportStatusMessage: String?
    @State private var showingPlanSheet = false
    @State private var activePaywallEntryPoint: PlanUpgradeEntryPoint = .documents

    // New library naming
    @State private var showingNewLibraryPrompt = false
    @State private var showingNewLibraryStorageChoice = false
    @State private var shouldShowStorageChoiceAfterDismissal = false
    @State private var newLibraryName = ""
    @State private var pendingNewLibraryName = ""

    // Delete library confirmation
    @State private var showingDeleteConfirmation = false
    @State private var libraryToDelete: KnowledgeContainer?
    @State private var showingClearAllConfirmation = false
    /// The library waiting on confirmation to become Local Only.
    ///
    /// That switch is destructive and had no confirmation anywhere on its most reachable path.
    /// `handleSetLibrarySyncMode` calls `reconfigureIfNeeded()`, after which the library is
    /// filtered out of `sharedVisibleContainers` and `cleanupSharedWorkspace` removes its shared
    /// artifacts and files, so a single tap on a segmented control deleted the library's iCloud
    /// copy while the toast said only that it "stays on this device".
    @State private var pendingLocalOnlyLibrary: KnowledgeContainer?

    // Vision Capture and Cached Docs
    @State private var showVisionCapture = false
    @State private var showCachedDocs = false
    /// How many documents the documentation cache holds.
    ///
    /// Drives whether the Cached Documents entry appears at all. `DocumentationCacheService` is an
    /// `actor`, so this cannot be read synchronously from the menu body and is refreshed instead.
    @State private var cachedDocumentCount = 0
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportReview: DocumentImportReview?
    @State private var showingImportReview = false
    @State private var isRefreshingSharedWorkspace = false
    @State private var sharedWorkspaceRefreshMessage: String?
    @State private var showingSharedSyncReviewDialog = false

    private static let sharedWorkspaceRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    let onViewVisualizations: (() -> Void)?

    private var documentLimit: Int { entitlementStore.documentLimit }
    private var isAtDocumentLimit: Bool {
        ragService.documents.count >= documentLimit
    }

    private var libraryLimit: Int { entitlementStore.libraryLimit }
    private var shouldShowQuotaBanner: Bool {
        !entitlementStore.hasUnlimitedDocuments
    }

    init(ragService: RAGService, containerService: ContainerService, onViewVisualizations: (() -> Void)? = nil) {
        _ragService = ObservedObject(wrappedValue: ragService)
        _containerService = ObservedObject(wrappedValue: containerService)
        self.onViewVisualizations = onViewVisualizations
    }

    private var filteredDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                // Legacy docs without containerId appear only in the default container
                return activeId == defaultId
            }
        }
    }

    private var filteredTotalChunks: Int {
        filteredDocuments.reduce(0) { $0 + $1.totalChunks }
    }

    private var iCloudLibraryCount: Int {
        containerService.containers.filter { $0.syncMode == .iCloudShared }.count
    }

    private var hasConfiguredICloudLibraries: Bool {
        iCloudLibraryCount > 0
    }

    private var localOnlyLibraryCount: Int {
        max(containerService.containers.count - iCloudLibraryCount, 0)
    }

    private var activeLibrary: KnowledgeContainer? {
        containerService.activeContainer
    }

    private var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    private var pendingSharedSyncConflict: WorkspaceSyncService.PendingBootstrapConflict? {
        workspaceSyncService.pendingBootstrapConflict
    }

    private var isDeletionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return !conflict.localOnlyLibraryNames.isEmpty && conflict.sharedOnlyLibraryNames.isEmpty
    }

    private var isAdditionOnlySharedConflict: Bool {
        guard let conflict = pendingSharedSyncConflict else { return false }
        return conflict.localOnlyLibraryNames.isEmpty && !conflict.sharedOnlyLibraryNames.isEmpty
    }

    private var sharedSyncReviewTitle: String {
        if isDeletionOnlySharedConflict {
            return "Libraries were removed from iCloud"
        }

        if isAdditionOnlySharedConflict {
            return "New iCloud libraries are available"
        }

        return "Review iCloud library changes"
    }

    private var sharedSyncReviewMessage: String {
        guard let conflict = pendingSharedSyncConflict else {
            return "Review the latest iCloud library changes for this device."
        }

        if isDeletionOnlySharedConflict {
            let names = conflict.localOnlyLibraryNames.joined(separator: ", ")
            return "These libraries still exist on this device but were removed from iCloud: \(names). Delete them here too, keep them local, or restore them to iCloud."
        }

        if isAdditionOnlySharedConflict {
            let names = conflict.sharedOnlyLibraryNames.joined(separator: ", ")
            return "These libraries are available in iCloud but not on this device yet: \(names)."
        }

        let localNames = conflict.localOnlyLibraryNames.joined(separator: ", ")
        let sharedNames = conflict.sharedOnlyLibraryNames.joined(separator: ", ")
        return "Only on this device: \(localNames). Only in iCloud: \(sharedNames)."
    }

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
    /// rendered once, by `libraryContentView`, above this branch entirely.
    private var emptyStateContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                EmptyDocumentsView(
                    isImportingSamples: isImportingSamples,
                    hasImportedSamples: onboardingStore.hasImportedSamples,
                    isAtDocumentLimit: isAtDocumentLimit,
                    documentLimit: documentLimit,
                    statusMessage: sampleImportStatusMessage,
                    onImportSamples: importSampleWorkspace,
                    onPickFiles: presentDocumentPickerOrUpgrade
                )
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Content shown below the persistent `documentHeader`, for a library with documents.
    /// See `emptyStateContent` for why `documentHeader` no longer lives in here.
    private var documentListContent: some View {
        Group {
            // Document list with modern styling
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredDocuments) { document in
                        NavigationLink(destination: DocumentDetailsView(
                            document: document,
                            embeddingProviderId: containerService.activeContainer?.embeddingProviderId
                        )) {
                            ModernDocumentCard(document: document, ragService: ragService)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                // Stats footer with Auto Intelligence indicator
                StatsFooter(
                    totalDocuments: filteredDocuments.count,
                    totalChunks: filteredTotalChunks,
                    autoIntelligenceEnabled: containerService.activeContainer?.autoAdaptDimension ?? true
                )
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
    }

    private var documentHeader: some View {
        VStack(spacing: 12) {
            documentSectionHeader
                .padding(.horizontal)

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

            sharedWorkspaceBanner
                .padding(.horizontal)

            if shouldShowQuotaBanner {
                DocumentQuotaBanner(
                    currentCount: ragService.documents.count,
                    limit: documentLimit,
                    tierName: entitlementStore.currentPlanDisplayName,
                    addOnPacks: entitlementStore.addOnPacks,
                    onUpgrade: { presentPlanSheet(for: .quotaBanner) }
                )
                .padding(.horizontal)
            }
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Documents")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DSColors.primaryText)

                Text(documentSectionSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
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
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.accentColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.08))
                                )
                                .glassCircleEffectHelper()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingSharedWorkspace)
                }
            }
        }
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
        HStack(spacing: 12) {
            DocumentActionChip(
                title: "Add Document",
                systemImage: "plus",
                iconOnly: true
            ) {
                DSHaptics.light()
                presentDocumentPickerOrUpgrade()
            }

            DocumentActionChip(
                title: "Semantic Search",
                systemImage: "sparkle.magnifyingglass",
                isEnabled: !ragService.documents.isEmpty,
                iconOnly: true
            ) {
                DSHaptics.selection()
                showingSemanticSearch = true
            }

            DocumentActionChip(
                title: "Library Settings",
                systemImage: "slider.horizontal.3",
                iconOnly: true
            ) {
                DSHaptics.light()
                showingContainerSettings = true
            }

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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sharedWorkspaceBanner: some View {
        if let bootstrapConflict = workspaceSyncService.pendingBootstrapConflict,
           hasConfiguredICloudLibraries {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.trianglebadge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)

                    Text(
                        !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "Libraries were removed from iCloud"
                            : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                ? "New iCloud libraries are available"
                                : "Review iCloud library changes")
                    )
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }

                Text(
                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                        ? "These libraries still exist on this device, but they no longer exist in iCloud."
                        : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "iCloud has libraries that are not on this device yet."
                            : "This device currently has \(bootstrapConflict.localLibraryCount) libraries marked iCloud Sync / \(bootstrapConflict.localDocumentCount) docs, and iCloud already has \(bootstrapConflict.sharedLibraryCount) shared librar\(bootstrapConflict.sharedLibraryCount == 1 ? "y" : "ies") / \(bootstrapConflict.sharedDocumentCount) docs.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !bootstrapConflict.localOnlyLibraryNames.isEmpty {
                    Text("Only on this device: \(bootstrapConflict.localOnlyLibraryNames.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !bootstrapConflict.sharedOnlyLibraryNames.isEmpty {
                    Text("Only in iCloud: \(bootstrapConflict.sharedOnlyLibraryNames.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty {
                    Button {
                        resolvePendingBootstrap(.useICloudWorkspace)
                    } label: {
                        Text("Add iCloud Libraries Here")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshingSharedWorkspace)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Restore These to iCloud"
                                        : "Sync Both Directions"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Keep Them Local Here"
                                        : "Use iCloud State Here"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }

                        VStack(spacing: 10) {
                            Button {
                                resolvePendingBootstrap(.mergeLibraries)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Restore These to iCloud"
                                        : "Sync Both Directions"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingSharedWorkspace)

                            Button {
                                resolvePendingBootstrap(.useICloudWorkspace)
                            } label: {
                                Text(
                                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                                        ? "Keep Them Local Here"
                                        : "Use iCloud State Here"
                                )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.9)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRefreshingSharedWorkspace)
                        }
                    }
                }

                Text(
                    !bootstrapConflict.localOnlyLibraryNames.isEmpty && bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                        ? "Restore These to iCloud puts the deleted libraries back into iCloud. Keep Them Local Here removes their iCloud status on this device and leaves them stored locally."
                        : (bootstrapConflict.localOnlyLibraryNames.isEmpty && !bootstrapConflict.sharedOnlyLibraryNames.isEmpty
                            ? "Add iCloud Libraries Here pulls the libraries listed as only in iCloud onto this device."
                            : "Sync Both Directions publishes libraries listed as only on this device and pulls in libraries listed as only in iCloud. Use iCloud State Here keeps the iCloud libraries here and demotes unmatched device-only iCloud libraries to Local Only.")
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
            )
        } else if shouldShowCompactSharedWorkspaceBanner {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: compactSharedWorkspaceBannerIcon)
                        .font(.subheadline)
                        .foregroundStyle(compactSharedWorkspaceBannerIconColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(compactSharedWorkspaceBannerTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(compactSharedWorkspaceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(compactSharedWorkspaceModeLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(compactSharedWorkspaceModeColor.opacity(0.15))
                        .foregroundStyle(compactSharedWorkspaceModeColor)
                        .clipShape(Capsule())
                }

                if let detail = compactSharedWorkspaceDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(compactSharedWorkspaceDetailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DSColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(compactSharedWorkspaceBannerIconColor.opacity(0.16), lineWidth: 1)
            )
        }
    }

    private var shouldShowCompactSharedWorkspaceBanner: Bool {
        workspaceSyncService.isUsingSharedWorkspace
            || hasConfiguredICloudLibraries
            || workspaceSyncService.syncCompatibilityMessage != nil
            || workspaceSyncService.lastErrorMessage != nil
            || sharedWorkspaceRefreshMessage != nil
    }

    private var isDisplayingLocalTransitionMessage: Bool {
        sharedWorkspaceRefreshMessage?.contains("is now Local Only") == true
    }

    private var compactSharedWorkspaceBannerTitle: String {
        isDisplayingLocalTransitionMessage ? "Library Storage" : "iCloud Libraries"
    }

    private var compactSharedWorkspaceBannerIcon: String {
        if isDisplayingLocalTransitionMessage {
            return "folder.fill"
        }
        return workspaceSyncService.isUsingSharedWorkspace ? "icloud.fill" : "icloud"
    }

    private var compactSharedWorkspaceBannerIconColor: Color {
        if isDisplayingLocalTransitionMessage {
            return .accentColor
        }
        return workspaceSyncService.isUsingSharedWorkspace ? .green : .accentColor
    }

    private var compactSharedWorkspaceModeLabel: String {
        if isDisplayingLocalTransitionMessage {
            return "Local Only"
        }
        return sharedWorkspaceModeLabel
    }

    private var compactSharedWorkspaceModeColor: Color {
        if isDisplayingLocalTransitionMessage {
            return .secondary
        }
        return sharedWorkspaceModeColor
    }

    private var compactSharedWorkspaceSummary: String {
        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local"
        }

        return "No iCloud libraries configured"
    }

    private var compactSharedWorkspaceDetail: String? {
        if let compatibilityMessage = workspaceSyncService.syncCompatibilityMessage {
            return compatibilityMessage
        }

        if let lastErrorMessage = workspaceSyncService.lastErrorMessage {
            return lastErrorMessage
        }

        if let sharedWorkspaceRefreshMessage {
            return sharedWorkspaceRefreshMessage
        }

        if let syncActivitySummary {
            return syncActivitySummary
        }

        if hasConfiguredICloudLibraries || workspaceSyncService.isUsingSharedWorkspace {
            return workspaceSyncService.statusMessage
        }

        return nil
    }

    private var compactSharedWorkspaceDetailColor: Color {
        if workspaceSyncService.syncCompatibilityMessage != nil || workspaceSyncService.lastErrorMessage != nil {
            return .orange
        }

        return .secondary
    }

    private var workspaceSyncHeadline: String {
        if workspaceSyncService.isUsingSharedWorkspace {
            return "iCloud Sync is the shared copy for libraries marked iCloud Sync. There is no main device."
        }

        if hasConfiguredICloudLibraries {
            if workspaceSyncService.requiresBootstrapDecision {
                return "Choose whether to combine this device's iCloud libraries with the ones already in iCloud. Local Only libraries are not affected."
            }

            if workspaceSyncService.syncCompatibilityMessage != nil {
                return "At least one iCloud library needs the Standard Vector Store before it can sync."
            }

            if workspaceSyncService.lastErrorMessage != nil {
                return "This device has iCloud libraries configured, but iCloud Sync is not active yet."
            }

            return "Preparing your iCloud libraries for sync."
        }

        return "Local Only means the library stays on this device until you explicitly choose iCloud Sync as the shared copy."
    }

    private var sharedWorkspaceSummary: String {
        if hasConfiguredICloudLibraries {
            return "\(iCloudLibraryCount) iCloud • \(localOnlyLibraryCount) local. Libraries marked iCloud Sync use iCloud as the shared copy. Local Only libraries stay on just this device."
        }

        return "All libraries are Local Only right now. Turn iCloud Sync on per library when you want it on another device."
    }

    private var sharedWorkspaceModeLabel: String {
        if workspaceSyncService.isUsingSharedWorkspace {
            return "iCloud Sync"
        }

        if !hasConfiguredICloudLibraries {
            return "Local Only"
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return "Choose"
        }

        if workspaceSyncService.syncCompatibilityMessage != nil {
            return "Unsupported"
        }

        if workspaceSyncService.lastErrorMessage != nil {
            return "Unavailable"
        }

        return "Preparing"
    }

    private var sharedWorkspaceModeColor: Color {
        if workspaceSyncService.isUsingSharedWorkspace {
            return .green
        }

        if !hasConfiguredICloudLibraries {
            return .secondary
        }

        if workspaceSyncService.requiresBootstrapDecision {
            return .accentColor
        }

        if workspaceSyncService.syncCompatibilityMessage != nil || workspaceSyncService.lastErrorMessage != nil {
            return .orange
        }

        return .accentColor
    }

    private var syncActivitySummary: String? {
        if let lastSuccessfulSyncAt = workspaceSyncService.lastSuccessfulSyncAt {
            let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
                for: lastSuccessfulSyncAt,
                relativeTo: Date()
            )
            return "Last synced \(relativeDescription)."
        }

          guard hasConfiguredICloudLibraries,
              let lastSyncAttemptAt = workspaceSyncService.lastSyncAttemptAt
        else {
            return nil
        }

        let relativeDescription = Self.sharedWorkspaceRelativeFormatter.localizedString(
            for: lastSyncAttemptAt,
            relativeTo: Date()
        )
        return "Last checked \(relativeDescription)."
    }

    @ViewBuilder
    private func syncBenefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @MainActor
    private func resolvePendingBootstrap(_ choice: WorkspaceSyncService.BootstrapChoice) {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            guard !isRefreshingSharedWorkspace else { return }
            isRefreshingSharedWorkspace = true
            sharedWorkspaceRefreshMessage = nil
            defer { isRefreshingSharedWorkspace = false }

            _ = await workspaceSyncService.resolvePendingBootstrap(using: choice)

            guard workspaceSyncService.isUsingSharedWorkspace else {
                sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
                return
            }

            containerService.reloadFromDisk()
            ragService.reloadWorkspaceData()
            sharedWorkspaceRefreshMessage = choice == .mergeLibraries
                ? "This device's iCloud-marked libraries were shared to iCloud, and iCloud libraries were pulled in here."
                : "Libraries already in iCloud were added here. Any unmatched iCloud-marked libraries on this device were kept as Local Only."
        }
    }

    @MainActor
    private func refreshSharedWorkspaceNow() {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            await performSharedWorkspaceRefresh(isManual: true)
        }
    }

    @MainActor
    private func connectExistingICloudLibraries() {
        guard hasICloudSyncAccess else {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        Task { @MainActor in
            guard !isRefreshingSharedWorkspace else { return }
            isRefreshingSharedWorkspace = true
            sharedWorkspaceRefreshMessage = nil
            defer { isRefreshingSharedWorkspace = false }

            _ = await workspaceSyncService.connectExistingICloudLibraries()

            guard workspaceSyncService.isUsingSharedWorkspace else {
                sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
                return
            }

            containerService.reloadFromDisk()
            ragService.reloadWorkspaceData()
            sharedWorkspaceRefreshMessage = "Existing iCloud libraries were connected to this device."
        }
    }

    @MainActor
    private func autoRefreshSharedWorkspaceIfNeeded() async {
        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        let minimumRefreshInterval: TimeInterval = 15
        if let lastSyncAttemptAt = workspaceSyncService.lastSyncAttemptAt,
           Date().timeIntervalSince(lastSyncAttemptAt) < minimumRefreshInterval {
            return
        }

        await performSharedWorkspaceRefresh(isManual: false)
    }

    @MainActor
    private func handleObservedSharedWorkspaceChange() async {
        guard hasConfiguredICloudLibraries else { return }
        await performSharedWorkspaceRefresh(isManual: false)
    }

    @MainActor
    private func performSharedWorkspaceRefresh(isManual: Bool) async {
        guard hasConfiguredICloudLibraries else { return }
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        if isManual {
            sharedWorkspaceRefreshMessage = nil
        }

        defer { isRefreshingSharedWorkspace = false }

        _ = await workspaceSyncService.reconfigureIfNeeded()

        guard workspaceSyncService.isUsingSharedWorkspace else {
            presentSharedSyncReviewIfNeeded()
            if isManual {
                sharedWorkspaceRefreshMessage = workspaceSyncService.pendingBootstrapConflict != nil
                    ? workspaceSyncService.statusMessage
                    : (workspaceSyncService.lastErrorMessage ?? "Shared workspace is still unavailable on this device.")
            }
            return
        }

        let hasActiveIngestion = ragService.ingestionItems.contains { !$0.stage.isTerminal }
        guard !hasActiveIngestion else {
            if isManual {
                sharedWorkspaceRefreshMessage = "Finish the current import before reloading iCloud Sync."
            }
            return
        }

        containerService.reloadFromDisk()
        ragService.reloadWorkspaceData()

        if isManual {
            sharedWorkspaceRefreshMessage = "Shared workspace reloaded from iCloud Sync."
        }
    }

    @MainActor
    private func presentSharedSyncReviewIfNeeded() {
        showingSharedSyncReviewDialog = pendingSharedSyncConflict != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            indexRebuildBanner
            sampleRefreshBanner
            libraryAlertView
        }
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
                withAnimation { refreshedSampleNames = refreshed }
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
        if ragService.librariesNeedingIndexRebuild.contains(containerId) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("This library needs its search index rebuilt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your documents are intact. Answers here can miss information until the index is rebuilt, which takes a moment and does not re-import anything.")
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(names.count == 1 ? "Updated a sample document" : "Updated \(names.count) sample documents")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(names.joined(separator: ", ")) described things this app does not actually do. Because the app answers questions out of these documents, a wrong sentence in one becomes a wrong answer. They were re-imported with the corrections. Nothing you imported yourself was touched.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DSSpacing.xs)

                Button("OK") {
                    withAnimation { refreshedSampleNames = nil }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(DSSpacing.md)
            .background(Color.blue.opacity(0.12))
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
            .userActivity("com.openintelligence.documents") { activity in
                activity.title = "Browse Document Library"
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
                if let containerId = containerService.activeContainerId as UUID? {
                    activity.userInfo = ["containerId": containerId]
                }
            }
    }

    private var librarySheetView: some View {
        libraryChromeView
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
                    containerService: containerService
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

    private var libraryChromeView: some View {
        ZStack(alignment: .bottomTrailing) {
            libraryContentView
            ingestionQueueOverlay
        }
            .navigationTitle("Documents")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
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
            .onChange(of: workspaceSyncService.observedWorkspaceChangeCount) {
                Task { @MainActor in
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
        IngestionQueueOverlay(
            items: ragService.ingestionItems,
            onCancelItem: { ragService.cancelIngestionItem($0) },
            onCancelAll: { ragService.cancelAllIngestion() },
            onContinuePaused: { ragService.continuePausedIngestionQueue() },
            onDiscardPaused: { ragService.discardPausedIngestionQueue() },
            onStopAndDismiss: { ragService.stopAndDismissIngestionQueue() }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, ingestionQueueBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var ingestionQueueBottomPadding: CGFloat {
#if os(iOS)
        72
#else
        16
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

            VStack(spacing: 12) {
                documentHeader

                if filteredDocuments.isEmpty {
                    emptyStateContent
                } else {
                    documentListContent
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

    /// Launches the file picker if the user still has document quota remaining.
    @MainActor
    private func presentDocumentPickerOrUpgrade() {
        if !entitlementStore.canAddDocument(currentCount: ragService.documents.count) {
            presentPlanSheet(for: .documentLimit)
        } else {
            showingFilePicker = true
        }
    }

    /// Ingests a picked document and unlocks the onboarding step once any content exists.
    private func enqueueDocumentIngestion(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        DSHaptics.drop()  // Files dropped/selected feedback
        ragService.enqueueDocuments(urls)
        Task { @MainActor in
            onboardingStore.markSamplesImported()
        }
    }

    @MainActor
    private func reviewAndEnqueueDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let review = DocumentImportReview(urls: urls)
        if review.needsReview {
            pendingImportURLs = urls
            pendingImportReview = review
            showingImportReview = true
            return
        }

        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func confirmPendingImport() {
        let urls = pendingImportURLs
        pendingImportURLs = []
        pendingImportReview = nil
        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func discardPendingImportFiles() {
        let fileManager = FileManager.default
        for url in pendingImportURLs {
            try? fileManager.removeItem(at: url)
        }
        pendingImportURLs = []
    }

    /// Imports the curated onboarding workspace so the document list is not empty.
    @MainActor
    private func importSampleWorkspace() {
        guard !isImportingSamples else { return }
        sampleImportError = nil
        sampleImportStatusMessage = nil

        let currentCount = ragService.documents.count
        let sampleCount = SampleDocumentManager.shared.sampleCount
        let remainingSlots = documentLimit - currentCount

        guard remainingSlots > 0 else {
            sampleImportStatusMessage =
                "Current workspace supports up to \(documentLimit) documents. Remove a document or upgrade to import the sample workspace."
            presentPlanSheet(for: .sampleImport)
            return
        }

        guard remainingSlots >= sampleCount else {
            let needed = sampleCount - remainingSlots
            sampleImportStatusMessage =
                "Importing the curated workspace requires \(sampleCount) slots, but only \(remainingSlots) remain. Remove \(needed) document\(needed == 1 ? "" : "s") or upgrade to proceed."
            presentPlanSheet(for: .sampleImport)
            return
        }

        isImportingSamples = true

        Task {
            defer { isImportingSamples = false }
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                onboardingStore.markSamplesImported()
                sampleImportStatusMessage = "Sample workspace imported successfully."
            } catch {
                sampleImportError = "Could not import the sample workspace. Please try again."
            }
        }
    }

    @MainActor
    private func handleNewLibraryTapped() {
        let currentCount = containerService.containers.count
        guard entitlementStore.canAddLibrary(currentCount: currentCount) else {
            presentPlanSheet(for: .libraryCreation)
            return
        }

        // Suggest a default name but let user customize. Ask the service for a name that is
        // actually free rather than deriving one from the count; see nextAvailableLibraryName.
        newLibraryName = containerService.nextAvailableLibraryName()
        pendingNewLibraryName = ""
        shouldShowStorageChoiceAfterDismissal = false
        showingNewLibraryPrompt = true
    }

    @MainActor
    private func createNewLibrary(syncMode: LibrarySyncMode) {
        if syncMode == .iCloudShared, !hasICloudSyncAccess {
            pendingNewLibraryName = ""
            presentPlanSheet(for: .iCloudSync)
            return
        }

        let trimmedName = pendingNewLibraryName.isEmpty
            ? newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
            : pendingNewLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryName = trimmedName.isEmpty ? containerService.nextAvailableLibraryName() : trimmedName

        let embeddingService = EmbeddingService.forProvider(
            id: settings.defaultEmbeddingProvider,
            allowFallback: true
        )

        let newContainer: KnowledgeContainer
        do {
            newContainer = try containerService.createContainer(
                name: libraryName,
                embeddingProviderId: embeddingService.actualProviderId,
                embeddingDim: embeddingService.outputDimension,
                syncMode: syncMode
            )
        } catch is LibraryQuotaError {
            pendingNewLibraryName = ""
            presentPlanSheet(for: .libraryCreation)
            return
        } catch {
            pendingNewLibraryName = ""
            return
        }

        containerService.setActive(newContainer.id)
        newLibraryName = "" // Reset for next time
        pendingNewLibraryName = ""

        if syncMode == .iCloudShared {
            Task { @MainActor in
                await publishExplicitICloudOptIn(libraryName: newContainer.name)
            }
        }
    }

    @MainActor
    private func handleSetLibrarySyncMode(
        _ container: KnowledgeContainer,
        _ syncMode: LibrarySyncMode,
        confirmed: Bool = false
    ) {
        guard container.syncMode != syncMode else { return }

        if syncMode == .iCloudShared, !hasICloudSyncAccess {
            presentPlanSheet(for: .iCloudSync)
            return
        }

        // Leaving iCloud removes this library's copy from iCloud. Ask first.
        if syncMode == .localOnly, container.syncMode == .iCloudShared, !confirmed {
            pendingLocalOnlyLibrary = container
            return
        }

        var updatedContainer = container
        updatedContainer.syncMode = syncMode
        containerService.updateContainer(updatedContainer)

        Task { @MainActor in
            if syncMode == .iCloudShared {
                await publishExplicitICloudOptIn(libraryName: updatedContainer.name)
            } else {
                isRefreshingSharedWorkspace = true
                defer { isRefreshingSharedWorkspace = false }

                _ = await workspaceSyncService.reconfigureIfNeeded()
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()

                sharedWorkspaceRefreshMessage = "\(updatedContainer.name) is now Local Only and stays on this device."
            }
        }
    }

    @MainActor
    private func publishExplicitICloudOptIn(libraryName: String) async {
        guard !isRefreshingSharedWorkspace else { return }

        isRefreshingSharedWorkspace = true
        sharedWorkspaceRefreshMessage = nil
        defer { isRefreshingSharedWorkspace = false }

        _ = await workspaceSyncService.reconfigureForExplicitICloudOptIn()

        containerService.reloadFromDisk()
        ragService.reloadWorkspaceData()

        if workspaceSyncService.isUsingSharedWorkspace {
            sharedWorkspaceRefreshMessage = "\(libraryName) now syncs through iCloud Sync."
        } else {
            sharedWorkspaceRefreshMessage = workspaceSyncService.lastErrorMessage ?? workspaceSyncService.statusMessage
        }
    }

    @MainActor
    private func deleteConflictedLocalLibraries(_ conflict: WorkspaceSyncService.PendingBootstrapConflict) {
        let targetContainerIDs = Set(conflict.localOnlyLibraryIDs)
        guard !targetContainerIDs.isEmpty else { return }

        Task {
            await MainActor.run {
                showingSharedSyncReviewDialog = false
                isRefreshingSharedWorkspace = true
                sharedWorkspaceRefreshMessage = nil
            }

            let docsToRemove = await MainActor.run {
                ragService.documents.filter { document in
                    guard let containerId = document.containerId else { return false }
                    return targetContainerIDs.contains(containerId)
                }
            }

            for doc in docsToRemove {
                try? await ragService.removeDocument(doc)
            }

            await MainActor.run {
                for containerId in targetContainerIDs {
                    containerService.deleteContainer(id: containerId)
                    LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
                }
            }

            for containerId in targetContainerIDs {
                await EntityIndexService.shared.removeContainer(containerId)
            }

            _ = await workspaceSyncService.reconfigureIfNeeded()

            await MainActor.run {
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()
                isRefreshingSharedWorkspace = false
                sharedWorkspaceRefreshMessage = targetContainerIDs.count == 1
                    ? "Deleted the library removed from iCloud on this device too."
                    : "Deleted the libraries removed from iCloud on this device too."
            }
        }
    }

    /// Reads the documentation cache size.
    ///
    /// `statistics()` returns the count directly, so this does not materialise the whole index
    /// just to ask whether it is empty.
    private func refreshCachedDocumentCount() async {
        cachedDocumentCount = await DocumentationCacheService.shared.statistics().count
    }

    @MainActor
    private func handleDeleteLibrary(_ container: KnowledgeContainer) {
        // Can't delete the last library
        guard containerService.containers.count > 1 else { return }
        libraryToDelete = container
        showingDeleteConfirmation = true
    }

    @MainActor
    /// Deletes through `LibraryDeletion` and reports the outcome in this screen's status line.
    ///
    /// The teardown itself used to live here in full, with a near-identical copy in
    /// `ContainerSettingsSheet`. This screen's behaviour is the one that survived, including
    /// aborting when iCloud refuses. `resolvedLocalDeletionContainerIDs` and
    /// `containerDeletionMergeKey` went with it: the first's fallback compared a UUID string to
    /// itself, so it could only match the id the early return already handled.
    private func confirmDeleteLibrary() {
        guard let container = libraryToDelete else { return }

        // Haptic for destructive action
        DSHaptics.delete()
        libraryToDelete = nil

        Task {
            let isShared = container.syncMode == .iCloudShared
            if isShared {
                isRefreshingSharedWorkspace = true
                sharedWorkspaceRefreshMessage = nil
            }

            let outcome = await LibraryDeletion.delete(
                container,
                ragService: ragService,
                containerService: containerService,
                workspaceSyncService: workspaceSyncService
            )

            isRefreshingSharedWorkspace = false
            switch outcome {
            case .deleted:
                sharedWorkspaceRefreshMessage = isShared
                    ? "\(container.name) was removed from this device and iCloud Sync."
                    : nil
            case .iCloudDeleteFailed(let message):
                sharedWorkspaceRefreshMessage = message
            case .refusedLastLibrary:
                sharedWorkspaceRefreshMessage = "\(container.name) is your only library, so it was not deleted."
            }
        }
    }

    @MainActor
    private func presentPlanSheet(for entryPoint: PlanUpgradeEntryPoint) {
        activePaywallEntryPoint = entryPoint
        showingPlanSheet = true
        TelemetryCenter.emitBillingEvent(
            "Paywall presented",
            metadata: ["entryPoint": entryPoint.analyticsValue]
        )
    }
}

    /// The capsule itself, with no button behaviour.
    ///
    /// Split out so the overflow `Menu` can use the same shape as the two real chips beside it.
    /// A `Menu` supplies its own tap handling, so wrapping `DocumentActionChip` inside one would
    /// nest a `Button` in a `Menu` and the chip would swallow the tap.
    private struct DocumentActionChipLabel: View {
        let title: String
        let systemImage: String
        var tint: Color = .accentColor
        var isEnabled: Bool = true

        /// Icon-only collapses the chip to a circle. The title is not dropped: it moves to the
        /// accessibility label and the hover/long-press tooltip, so VoiceOver reads exactly what
        /// it read before. Only the visual text goes away.
        var iconOnly: Bool = false

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconOnly ? 15 : 11, weight: .bold))

                if !iconOnly {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
            }
            // 44pt minimum touch target in icon-only form. An unreliable tap reads as a slow
            // app, so the target stays full size even though the chip looks smaller.
            .frame(minWidth: iconOnly ? 44 : 0, minHeight: iconOnly ? 44 : 0)
            .padding(.horizontal, iconOnly ? 0 : 12)
            .padding(.vertical, iconOnly ? 0 : 8)
            .background(.ultraThinMaterial)
            .foregroundStyle(isEnabled ? tint : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isEnabled ? tint.opacity(0.15) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .glassEffectHelper(isSelected: false, interactive: isEnabled)
            .opacity(isEnabled ? 1 : 0.6)
        }
    }

    private struct DocumentActionChip: View {
        let title: String
        let systemImage: String
        var tint: Color = .accentColor
        var isEnabled: Bool = true
        var iconOnly: Bool = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                DocumentActionChipLabel(
                    title: title,
                    systemImage: systemImage,
                    tint: tint,
                    isEnabled: isEnabled,
                    iconOnly: iconOnly
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(title)
            .help(title)
        }
    }

private struct DocumentUtilityChipLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

private struct DocumentImportReview {
    private let transcriptOnlyFiles: [String]
    private let experimentalFiles: [String]
    private let convertFirstFiles: [String]

    init(urls: [URL]) {
        transcriptOnlyFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .transcriptOnly }
            .map(\ .lastPathComponent)
        experimentalFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .experimental }
            .map(\ .lastPathComponent)
        convertFirstFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .convertFirst }
            .map(\ .lastPathComponent)
    }

    var needsReview: Bool {
        !transcriptOnlyFiles.isEmpty || !experimentalFiles.isEmpty || !convertFirstFiles.isEmpty
    }

    var message: String {
        var parts: [String] = [
            "Strongest imports: PDF, DOCX/XLSX/PPTX, TXT/MD, CSV, images, and scans."
        ]

        if !transcriptOnlyFiles.isEmpty {
            parts.append("Transcript only: \(shortList(transcriptOnlyFiles)). Video and audio imports index spoken content, not full visual meaning.")
        }

        if !experimentalFiles.isEmpty {
            parts.append("Reduced-fidelity parsing: \(shortList(experimentalFiles)). These files often lose structure and usually need cleanup first.")
        }

        if !convertFirstFiles.isEmpty {
            parts.append("Convert first for the cleanest results: \(shortList(convertFirstFiles)). Exporting to PDF or modern Office usually gives cleaner retrieval.")
        }

        parts.append("Import anyway?")
        return parts.joined(separator: "\n\n")
    }

    private func shortList(_ files: [String]) -> String {
        let preview = files.prefix(3).joined(separator: ", ")
        if files.count > 3 {
            return "\(preview), +\(files.count - 3) more"
        }
        return preview
    }
}

private enum DocumentImportReadiness {
    case strong
    case transcriptOnly
    case experimental
    case convertFirst

    static func classify(url: URL) -> Self {
        switch url.pathExtension.lowercased() {
        case "pdf", "txt", "md", "markdown", "mdown", "rtf", "csv",
             "docx", "xlsx", "pptx",
             "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp":
            return .strong
        case "m4a", "aac", "mp3", "wav", "wave", "aiff", "aif", "caf", "mp4", "m4v", "mov":
            return .transcriptOnly
        case "doc", "xls", "ppt", "pages", "numbers", "key":
            return .convertFirst
        case "xml", "json", "jsonc", "html", "htm", "yaml", "yml", "css", "scss", "sass", "less",
             "sql", "sh", "bash", "zsh", "fish",
             "swift", "py", "pyw", "pyx", "js", "mjs", "cjs", "ts", "tsx", "java", "class",
             "cpp", "cc", "cxx", "c++", "c", "h", "m", "mm", "go", "rs", "rb", "php",
             "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim",
             "avi", "mkv", "webm":
            return .experimental
        default:
            return .experimental
        }
    }
}

#if DEBUG
    #Preview {
        let containerService = ContainerService()
        let billingService = PreviewBillingService()
        let entitlementStore = EntitlementStore(billingService: billingService)
        let ragService = RAGService(containerService: containerService, entitlementStore: entitlementStore)
        let settingsStore = SettingsStore(ragService: ragService)
        DocumentLibraryView(ragService: ragService, containerService: containerService)
            .environmentObject(OnboardingStateStore())
            .environmentObject(entitlementStore)
            .environmentObject(settingsStore)
    }

    @MainActor
    private final class PreviewBillingService: BillingService {
        let events: AsyncStream<BillingEvent>

        init() {
            events = AsyncStream { continuation in
                continuation.finish()
            }
        }

        func refreshProducts() async {}

        func purchase(_: BillingProduct) async throws -> StoreKit.Transaction? { nil }

        func restorePurchases() async {}
    }
#endif
