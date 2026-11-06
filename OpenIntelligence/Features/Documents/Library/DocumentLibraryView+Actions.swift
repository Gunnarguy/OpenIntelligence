//
//  DocumentLibraryView+Actions.swift
//  OpenIntelligence
//
//  Part of DocumentLibraryView, moved from DocumentLibraryView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

extension DocumentLibraryView {
    /// Launches the file picker if the user still has document quota remaining.
    ///
    /// macOS opens `NSOpenPanel` directly rather than presenting `DocumentPicker`
    /// in a sheet. A sheet would stack two windows for one action, and its
    /// `onAppear` runs inside a CATransaction commit, where AppKit refuses to
    /// start a modal panel at all.
    @MainActor
    func presentDocumentPickerOrUpgrade() {
        let allowed = entitlementStore.canAddDocument(currentCount: ragService.countedDocumentCount)
        // What the plan counted when Add was asked for (5.8 journal): row "The app's guides take three of a free
        // plan's five documents".
        VerificationJournal.record(
            "plan.documentCheck",
            ["counted": "\(ragService.countedDocumentCount)", "limit": "\(entitlementStore.documentLimit)",
                "unlimited": "\(entitlementStore.hasUnlimitedDocuments)", "allowed": "\(allowed)"])
        guard allowed else {
            presentPlanSheet(for: .documentLimit)
            return
        }
        #if os(macOS)
        MacDocumentImportPanel.present(folderFileLimit: folderFileRoom) { urls in
            reviewAndEnqueueDocuments(urls)
        }
        #else
        showingFilePicker = true
        #endif
    }

    /// Imports files dragged from Finder onto the library.
    ///
    /// Drops hand back the file's original location, so they take the same
    /// copy-into-workspace path as the open panel rather than being referenced
    /// in place. Returns `false` when nothing usable was dropped, which is what
    /// makes the system play the standard rejection animation.
    @MainActor
    @discardableResult
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        Tour.used(.dragAndDrop)
        // A folder is not a document: it brings in the files inside it that the app imports, through
        // its subfolders (5.7). Through 5.6 a dropped folder was filtered out here and refused.
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        guard entitlementStore.canAddDocument(currentCount: ragService.countedDocumentCount) else {
            presentPlanSheet(for: .documentLimit)
            return false
        }

        let staged = ImportedFileStaging.copyIntoWorkspaceExpandingFolders(fileURLs, limit: folderFileRoom, via: "drop")
        guard !staged.isEmpty else { return false }

        reviewAndEnqueueDocuments(staged)
        return true
    }

    /// Files another app handed over, already copied into the app. They get the same plan check
    /// and import review as a picked or dropped file. When the plan has no room, the copies are
    /// removed so they do not stay in the app's storage unimported.
    @MainActor
    func importOpenedFiles(_ staged: [URL], into library: UUID? = nil) {
        guard !staged.isEmpty else { return }
        guard entitlementStore.canAddDocument(currentCount: ragService.countedDocumentCount) else {
            staged.forEach { try? FileManager.default.removeItem(at: $0) }
            presentPlanSheet(for: .documentLimit)
            return
        }
        reviewAndEnqueueDocuments(staged, into: library)
    }

    /// Files "Open in" handed over: the plan check first, as for any import, then the viewer. Files
    /// that come while it is open join it.
    @MainActor
    func showOpenedFiles(_ staged: [URL]) {
        guard entitlementStore.canAddDocument(currentCount: ragService.countedDocumentCount) else {
            ImportedFileStaging.discardViewingCopies(staged)
            presentPlanSheet(for: .documentLimit)
            return
        }
        openedFiles.append(contentsOf: staged)
        showingOpenedFiles = true
    }

    /// When the viewer closes: Add to Library copies the files into the library's folder and runs the
    /// usual import review on them; Don't Add removes the app's copies. The viewing copies are kept when
    /// any file could not be copied, so nothing is lost.
    @MainActor
    func finishOpenedFiles() {
        let files = openedFiles
        let add = addOpenedFiles
        let library = openedFilesLibraryId
        openedFiles = []
        addOpenedFiles = false
        openedFilesLibraryId = nil
        guard add else {
            ImportedFileStaging.discardViewingCopies(files)
            return
        }
        Task { @MainActor in
            let inWorkspace = await ImportedFileStaging.copyIntoWorkspaceOffMainActor(files)
            if inWorkspace.count == files.count {
                ImportedFileStaging.discardViewingCopies(files)
            } else {
                Log.error(
                    "[OpenIn] \(files.count - inWorkspace.count) opened file(s) could not be copied into the library; the copies are kept",
                    category: .ingestion)
            }
            importOpenedFiles(inWorkspace, into: library)
        }
    }

    /// Ingests a picked document and unlocks the onboarding step once any content exists.
    private func enqueueDocumentIngestion(_ urls: [URL], into library: UUID? = nil) {
        guard !urls.isEmpty else { return }
        DSHaptics.drop()  // Files dropped/selected feedback
        ragService.enqueueDocuments(urls, containerId: library)
        Task { @MainActor in
            onboardingStore.markSamplesImported()
        }
    }

    @MainActor
    func reviewAndEnqueueDocuments(_ urls: [URL], into library: UUID? = nil) {
        guard !urls.isEmpty else { return }

        let review = DocumentImportReview(urls: urls)
        if review.needsReview {
            pendingImportURLs = urls
            pendingImportLibraryId = library
            pendingImportReview = review
            showingImportReview = true
            return
        }

        enqueueDocumentIngestion(urls, into: library)
    }

    @MainActor
    func confirmPendingImport() {
        let urls = pendingImportURLs
        let library = pendingImportLibraryId
        pendingImportURLs = []
        pendingImportLibraryId = nil
        pendingImportReview = nil
        enqueueDocumentIngestion(urls, into: library)
    }

    @MainActor
    func discardPendingImportFiles() {
        let fileManager = FileManager.default
        for url in pendingImportURLs {
            try? fileManager.removeItem(at: url)
        }
        pendingImportURLs = []
        pendingImportLibraryId = nil
    }

    /// Imports the curated onboarding workspace so the document list is not empty.
    @MainActor
    func importSampleWorkspace() {
        guard !isImportingSamples else { return }
        sampleImportError = nil
        sampleImportStatusMessage = nil

        // The guides use none of the plan's documents (5.8): they go in their own library, which counts toward neither
        // limit, so importing them needs no room. Through 5.7 they took three of a free plan's five.
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
    func handleNewLibraryTapped() {
        // The guide library isn't one of the plan's libraries (5.8).
        let currentCount = containerService.countedLibraryCount
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
    func createNewLibrary(syncMode: LibrarySyncMode) {
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
    func handleSetLibrarySyncMode(
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
    func deleteConflictedLocalLibraries(_ conflict: WorkspaceSyncService.PendingBootstrapConflict) {
        let targetContainerIDs = Set(conflict.localOnlyLibraryIDs)
        guard !targetContainerIDs.isEmpty else { return }

        Task {
            await MainActor.run {
                showingSharedSyncReviewDialog = false
                isRefreshingSharedWorkspace = true
                sharedWorkspaceRefreshMessage = nil
            }
            // A deletion still in its undo seconds runs first (5.7): its documents are out of the list.
            await ragService.commitPendingRemovals()

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
    func refreshCachedDocumentCount() async {
        cachedDocumentCount = await DocumentationCacheService.shared.statistics().count
    }

    @MainActor
    func handleDeleteLibrary(_ container: KnowledgeContainer) {
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
    func confirmDeleteLibrary() {
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
    func presentPlanSheet(for entryPoint: PlanUpgradeEntryPoint) {
        activePaywallEntryPoint = entryPoint
        showingPlanSheet = true
        TelemetryCenter.emitBillingEvent(
            "Paywall presented",
            metadata: ["entryPoint": entryPoint.analyticsValue]
        )
    }
}
