//
//  RAGService+Import.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif

extension RAGService {
    // MARK: - Document Management

    @MainActor
    @discardableResult
    /// - Parameter containerId: library to ingest into. Defaults to the active one, which
    ///   is right for a user-initiated import and wrong for anything the app decides to
    ///   import on its own: an automatic sample refresh fired while "Library 2" happened
    ///   to be selected would drop the samples into Library 2.
    func enqueueDocuments(
        _ urls: [URL],
        context: IngestionContext = .userInitiated,
        containerId: UUID? = nil
    ) -> [UUID] {
        guard !urls.isEmpty else { return [] }
        var activeContainerId = containerId ?? containerService.activeContainerId
        // The guide library takes the app's guides only (5.8). What the person adds while it is open goes to their
        // own first library, which is opened so they see it arrive.
        if context != .onboarding, containerService.isGuideLibrary(activeContainerId),
            let own = containerService.libraryForOwnFiles(requested: activeContainerId)
        {
            activeContainerId = own
            if containerId == nil { containerService.setActive(own) }
        }
        VerificationJournal.record(
            "import.enqueue",
            ["count": "\(urls.count)", "context": "\(context)", "library": VerificationJournal.anon(activeContainerId),
                "types": Set(urls.map { $0.pathExtension.lowercased() }).sorted().joined(separator: ","),
                "guide": "\(containerService.isGuideLibrary(activeContainerId))",
                "counted": "\(countedDocumentCount)", "ownLibraries": "\(containerService.countedLibraryCount)",
                "voiceOver": "\(VerificationJournal.voiceOverOn)"])
        if context == .userInitiated {
            clearSelfHealingSuppression(for: activeContainerId)
        }
        let newItems = urls.map { url in
            let item = IngestionItem(
                url: url,
                containerId: activeContainerId,
                stage: .queued,
                detail: "Queued"
            )
            ingestionContexts[item.id] = context
            return item
        }
        ingestionItems.append(contentsOf: newItems)
        if ingestionItems.count > 1 {
            suppressProcessingSummary = true
        }
        savePersistedIngestionQueueState()
        if context == .userInitiated {
            liveActivityTrackedIngestionIds.formUnion(newItems.map(\.id))
            let subtitle =
                newItems.count == 1
                ? newItems[0].filename
                : "\(newItems.count) documents"
            IngestionRuntimeBridge.shared.beginUserInitiatedIngestion(
                title: "Importing documents",
                subtitle: subtitle
            )
            syncIngestionLiveActivity()
        }
        startIngestionTaskIfNeeded()
        return newItems.map { $0.id }
    }

    /// - Parameter containerId: library to ingest into. `nil` uses the active library.
    func ingestDocuments(
        _ urls: [URL],
        context: IngestionContext = .userInitiated,
        containerId: UUID? = nil
    ) async -> IngestionBatchResult {
        let ids = await MainActor.run {
            enqueueDocuments(urls, context: context, containerId: containerId)
        }
        return await waitForIngestionCompletion(ids: ids)
    }

    @MainActor
    func startIngestionTaskIfNeeded() {
        guard ingestionTask == nil else { return }
        ingestionLoopID += 1
        let loopID = ingestionLoopID
        let unwinding = ingestionTaskUnwinding
        ingestionTaskUnwinding = nil
        ingestionTask = Task.detached(priority: .userInitiated) { [weak self] in
            // A cancelled loop is still inside its import until the next cancellation check.
            // Starting before it has ended would put two loops on the same queued file.
            await unwinding?.value
            guard let self else { return }
            await self.runIngestionLoop(loopID: loopID)
        }
    }

    @MainActor
    func runPendingIngestionQueue() async -> Bool {
        guard !ingestionItems.contains(where: { $0.stage == .paused }) else {
            Log.info(
                "[RAGService] Pending ingestion queue is paused after restart; waiting for user decision",
                category: .ingestion)
            return false
        }

        let ids =
            ingestionItems
            .filter { !$0.stage.isTerminal }
            .map(\.id)

        guard !ids.isEmpty else { return true }
        startIngestionTaskIfNeeded()
        let result = await waitForIngestionCompletion(ids: ids)
        return result.failureCount == 0 && result.completedIds.count == ids.count
    }

    @MainActor
    func cancelIngestionItem(_ id: UUID) {
        guard let index = ingestionItems.firstIndex(where: { $0.id == id }) else { return }
        let item = ingestionItems[index]
        guard !item.stage.isTerminal else { return }
        recordIngestionQueueTombstones(for: [item])
        if Self.isAutomaticSelfHealingItem(item), let containerId = item.containerId {
            suppressSelfHealing(for: [containerId])
        }

        if item.stage == .queued || item.stage == .paused {
            // A file that was part-way through an import in pieces: its committed pieces go.
            purgeStreamedTextImport(for: item.url, containerId: item.containerId ?? containerService.containers.first?.id)
            updateIngestionItem(
                id: id,
                filename: item.filename,
                stage: .cancelled,
                detail: "Cancelled"
            )
            finalizeCancelledIngestionTracking(for: [id])
            pruneCompletedIngestionItems()
            return
        }

        requestedIngestionCancellationIds.insert(id)
        ingestionTask?.cancel()
    }

    @MainActor
    func cancelAllIngestion() {
        let activeItems = ingestionItems.filter { !$0.stage.isTerminal }
        let activeIds =
            activeItems
            .map(\.id)

        guard !activeIds.isEmpty else { return }
        recordIngestionQueueTombstones(for: activeItems)
        suppressSelfHealing(
            for: Set(
                activeItems.compactMap { item in
                    Self.isAutomaticSelfHealingItem(item) ? item.containerId : nil
                }))

        for item in ingestionItems where item.stage == .queued || item.stage == .paused {
            purgeStreamedTextImport(for: item.url, containerId: item.containerId ?? containerService.containers.first?.id)
            updateIngestionItem(
                id: item.id,
                filename: item.filename,
                stage: .cancelled,
                detail: "Cancelled"
            )
        }

        let activeNonQueuedIds =
            ingestionItems
            .filter { !$0.stage.isTerminal && $0.stage != .queued && $0.stage != .paused }
            .map(\.id)

        if activeNonQueuedIds.isEmpty {
            finalizeCancelledIngestionTracking(for: activeIds)
            pruneCompletedIngestionItems()
            return
        }

        requestedIngestionCancellationIds.formUnion(activeNonQueuedIds)
        ingestionTask?.cancel()
    }

    @MainActor
    func continuePausedIngestionQueue() {
        let continuedFromPause = ingestionPausedByPerson
        ingestionPausedByPerson = false
        let pausedIndices = ingestionItems.indices.filter { ingestionItems[$0].stage == .paused }
        guard !pausedIndices.isEmpty else {
            startIngestionTaskIfNeeded()
            return
        }

        for index in pausedIndices {
            var item = ingestionItems[index]
            if let containerId = item.containerId {
                clearSelfHealingSuppression(for: containerId)
            }
            item.stage = .queued
            item.detail = "Queued"
            item.progress = nil
            item.startedAt = nil
            item.finishedAt = nil
            item.errorMessage = nil
            item.clearLease()
            item.events.append(
                IngestionEvent(
                    stage: .queued, title: "Queued",
                    detail: continuedFromPause ? "Continued after a pause" : "Resumed after app restart"))
            ingestionItems[index] = item
        }

        Log.info("[RAGService] User resumed \(pausedIndices.count) interrupted ingestion item(s)", category: .ingestion)
        savePersistedIngestionQueueState()
        resumeUserInitiatedIngestionBackgroundSupportIfNeeded(
            restoredItems: ingestionItems.filter { !$0.stage.isTerminal })
        syncIngestionLiveActivity()
        startIngestionTaskIfNeeded()
    }

    @MainActor
    func discardPausedIngestionQueue() {
        ingestionPausedByPerson = false
        let pausedItems = ingestionItems.filter { $0.stage == .paused }
        let pausedIds = Set(pausedItems.map(\.id))
        guard !pausedIds.isEmpty else { return }

        recordIngestionQueueTombstones(for: pausedItems)
        suppressSelfHealing(
            for: Set(
                pausedItems.compactMap { item in
                    Self.isAutomaticSelfHealingItem(item) ? item.containerId : nil
                }))

        ingestionItems.removeAll { pausedIds.contains($0.id) }
        ingestionContexts = ingestionContexts.filter { id, _ in !pausedIds.contains(id) }
        liveActivityTrackedIngestionIds.subtract(pausedIds)
        requestedIngestionCancellationIds.subtract(pausedIds)

        Log.info("[RAGService] User discarded \(pausedIds.count) interrupted ingestion item(s)", category: .ingestion)

        // Nuke any document records or files corresponding to these discarded items
        for item in pausedItems {
            let resolvedContainerId =
                item.containerId ?? self.containerService.containers.first?.id
                ?? self.containerService.activeContainerId

            // 1. Clean up temporary page checkpoints, and for a file that was being imported in
            // pieces the chunks its committed pieces already stored. Before the file is deleted:
            // the checkpoint folder is named from the file's path, size and date, and with the
            // file gone that name comes out different, so nothing was found and nothing removed.
            let fileURL = item.url
            purgeStreamedTextImport(for: fileURL, containerId: resolvedContainerId)
            documentProcessor.cleanCheckpoints(for: fileURL)

            // 1.5 Delete physical file if it's in our internal storage
            if fileURL.path.contains("ImportedDocuments") {
                try? FileManager.default.removeItem(at: fileURL)
            }

            // 2. Remove document record from the catalog if it exists
            if let existingDoc = existingImportedDocument(
                in: resolvedContainerId,
                storageRelativePath: item.storageRelativePath,
                fileHash: item.documentHash
            ) {
                Task {
                    do {
                        try await removeDocument(existingDoc)
                        Log.info(
                            "[RAGService] Completely nuked document '\(existingDoc.filename)' corresponding to discarded ingestion item",
                            category: .ingestion)
                    } catch {
                        Log.error(
                            "[RAGService] Failed to remove document '\(existingDoc.filename)' during discard: \(error)",
                            category: .ingestion)
                    }
                }
            }
        }

        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    /// Stops the visible queue and records deletion-wins state so iCloud cannot
    /// resurrect the exact discarded work item on another workspace reload.
    @MainActor
    func stopAndDismissIngestionQueue() {
        let activeItems = ingestionItems.filter { !$0.stage.isTerminal }
        guard !activeItems.isEmpty else {
            clearRuntimeIngestionQueueState()
            savePersistedIngestionQueueState()
            return
        }

        let activeIds = Set(activeItems.map(\.id))
        let selfHealingContainerIds = Set(
            activeItems.compactMap { item in
                Self.isAutomaticSelfHealingItem(item) ? item.containerId : nil
            })
        recordIngestionQueueTombstones(for: activeItems)
        suppressSelfHealing(for: selfHealingContainerIds)
        if ingestionTask != nil {
            requestedIngestionCancellationIds.formUnion(activeIds)
        }
        cancelIngestionTaskAndSetItAside()

        for item in activeItems where item.stage == .queued || item.stage == .paused {
            purgeStreamedTextImport(
                for: item.url, containerId: item.containerId ?? containerService.containers.first?.id)
            documentProcessor.cleanCheckpoints(for: item.url)
        }

        ingestionItems.removeAll { activeIds.contains($0.id) }
        ingestionContexts = ingestionContexts.filter { id, _ in !activeIds.contains(id) }
        liveActivityTrackedIngestionIds.subtract(activeIds)
        isProcessing = false
        processingStatus = ""
        // Nothing is paused once the queue is gone (5.7). Left set, it made the next import's end of background time
        // return early in `handleContinuedIngestionExpiration`, so that import was neither set aside nor queued again.
        ingestionPausedByPerson = false
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
        Log.info(
            "[RAGService] User stopped and dismissed \(activeIds.count) ingestion item(s); automatic self-healing is suppressed for \(selfHealingContainerIds.count) library/libraries",
            category: .ingestion
        )
        removeImportedCopies(of: activeItems.map(\.url), after: ingestionTaskUnwinding)
    }

    /// The app's own copies of files whose imports were stopped, once the import that was running has stopped
    /// reading its file (5.7). "Discard" on interrupted imports always removed them; Stop and dismiss did not, so the
    /// copy stayed in ImportedDocuments with no document, and the same file chosen again came in as "Support
    /// Tickets-2.jsonl" (demo copy of 37330a9 in the iOS 27 Simulator, 2026-10-20). A copy that a stored document or a
    /// queued import still names stays: a rebuild's item points at its document's own file.
    @MainActor
    func removeImportedCopies(of urls: [URL], after unwinding: Task<Void, Never>?) {
        let copies = urls.filter { $0.path.contains("ImportedDocuments") }
        guard !copies.isEmpty else { return }
        Task { @MainActor [weak self] in
            await unwinding?.value
            guard let self else { return }
            // Before the stored documents are read, `documents` cannot say which copy a document names (a stop
            // tapped at launch, on a restored rebuild), so every copy stays.
            guard hasAppliedLoadedDocuments else {
                Log.info(
                    "[RAGService] Kept \(copies.count) stopped import file(s): the documents are not loaded yet",
                    category: .ingestion)
                return
            }
            for url in copies {
                let path = url.standardizedFileURL.path
                let named =
                    documents.contains { $0.fileURL.standardizedFileURL.path == path }
                    || ingestionItems.contains { $0.url.standardizedFileURL.path == path }
                guard !named, FileManager.default.fileExists(atPath: url.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: url)
                    Log.info("[RAGService] Removed the copy of \(url.lastPathComponent) left by a stopped import", category: .ingestion)
                } catch {
                    Log.warning(
                        "[RAGService] Could not remove the copy of \(url.lastPathComponent): \(error.localizedDescription)",
                        category: .ingestion)
                }
            }
        }
    }

    @MainActor
    func cancelAndPurgeIngestion(for containerId: UUID) async {
        let matchingItems = ingestionItems.filter { $0.containerId == containerId }
        guard !matchingItems.isEmpty else { return }
        recordIngestionQueueTombstones(for: matchingItems)
        suppressSelfHealing(for: [containerId])

        let immediateRemovalIds = Set(
            matchingItems
                .filter { $0.stage == .queued || $0.stage == .paused || $0.stage.isTerminal }
                .map(\.id)
        )

        if !immediateRemovalIds.isEmpty {
            ingestionItems.removeAll { immediateRemovalIds.contains($0.id) }
            finalizeCancelledIngestionTracking(for: Array(immediateRemovalIds))
        }

        let activeIds =
            matchingItems
            .filter { !immediateRemovalIds.contains($0.id) }
            .map(\.id)

        guard !activeIds.isEmpty else {
            savePersistedIngestionQueueState()
            syncIngestionLiveActivity()
            return
        }

        requestedIngestionCancellationIds.formUnion(activeIds)
        ingestionTask?.cancel()

        _ = await waitForIngestionCompletion(ids: activeIds)

        let settledIds =
            ingestionItems
            .filter { activeIds.contains($0.id) }
            .map(\.id)
        ingestionItems.removeAll { activeIds.contains($0.id) }
        finalizeCancelledIngestionTracking(for: settledIds)
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    private func runIngestionLoop(loopID: Int) async {
        await MainActor.run { self.isProcessing = true }

        var shouldRestartQueueAfterUserCancellation = false

        while let next = await MainActor.run(body: { self.nextQueuedIngestionItem() }) {
            if Task.isCancelled { break }
            let context = await MainActor.run { self.ingestionContexts[next.id] ?? .userInitiated }
            do {
                try await addDocument(
                    at: next.url,
                    context: context,
                    trackingId: next.id,
                    manageProcessingState: false,
                    containerId: next.containerId
                )
                if Task.isCancelled { break }
            } catch let error where error is CancellationError || Task.isCancelled {
                // Any error thrown once the task is cancelled is the cancellation, whatever a
                // layer below has dressed it as. An import that was stopped is never "failed".
                let userInitiatedCancellation = await MainActor.run {
                    self.handleUserRequestedIngestionCancellation(activeItemId: next.id)
                }
                if userInitiatedCancellation {
                    shouldRestartQueueAfterUserCancellation = true
                    break
                } else {
                    await MainActor.run {
                        // Not when a later loop has been started: the items are queued for it.
                        if self.ingestionLoopID == loopID {
                            self.handleContinuedIngestionExpiration()
                        }
                    }
                    break
                }
            } catch {
                await MainActor.run {
                    self.markIngestionFailed(id: next.id, error: error)
                }
            }
        }

        await MainActor.run {
            // A loop that was cancelled and set aside may end after a later one was started.
            // The queue's task is the later loop's then, and this one must not clear it.
            let isLatestLoop = self.ingestionLoopID == loopID
            self.isProcessing = false
            self.processingStatus = ""
            if isLatestLoop { self.ingestionTask = nil }
            self.suppressProcessingSummary = false
            self.savePersistedIngestionQueueState()
            self.syncIngestionLiveActivity()
            self.pruneCompletedIngestionItems()
            self.kickPendingReembedIfNeeded()
            self.runDeferredEnrichmentsIfNeeded()
            if isLatestLoop, shouldRestartQueueAfterUserCancellation,
                self.ingestionItems.contains(where: { $0.stage == .queued && !$0.metrics.isRebuild })
            {
                self.startIngestionTaskIfNeeded()
            }
        }
    }

    @MainActor
    func enqueuePendingReembed(containerId: UUID) {
        pendingReembedContainerIds.insert(containerId)
        kickPendingReembedIfNeeded()
    }

    /// If we have queued re-embed work and the app is idle, run it.
    /// This prevents leaving a library with an empty index after a provider/dimension fallback.
    @MainActor
    private func kickPendingReembedIfNeeded() {
        guard !suppressReembedKicks else { return }  // Suppress during onboarding
        guard !isProcessing else { return }
        guard pendingReembedTask == nil else { return }
        guard !pendingReembedContainerIds.isEmpty else { return }

        let containerIds = Array(pendingReembedContainerIds)
        pendingReembedContainerIds.removeAll()

        pendingReembedTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            for id in containerIds {
                do {
                    try await self.reembedDocuments(in: id)
                } catch {
                    Log.error(
                        "[RAGService] Deferred re-embed failed for container \(id): \(error)", category: .embedding)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pendingReembedTask = nil
                // If anything queued up while we were running, kick again.
                self.kickPendingReembedIfNeeded()
            }
        }
    }

    /// Start suppressing automatic reembed kicks (call before batch onboarding import)
    @MainActor
    func beginOnboardingBatch() {
        suppressReembedKicks = true
        Log.info("[RAGService] Suppressing reembed kicks for onboarding batch", category: .ingestion)
    }

    /// Clear any pending reembed operations (used after onboarding to prevent unnecessary rebuilds)
    @MainActor
    func clearPendingReembeds() {
        suppressReembedKicks = false  // Re-enable kicks
        pendingReembedContainerIds.removeAll()
        pendingReembedTask?.cancel()
        pendingReembedTask = nil
        Log.info("[RAGService] Cleared pending reembed queue", category: .ingestion)
    }

    @MainActor
    private func nextQueuedIngestionItem() -> IngestionItem? {
        let now = Date()
        let currentDeviceID = WorkspaceSyncService.currentDeviceID()
        guard
            let index = ingestionItems.firstIndex(where: { item in
                // A rebuild's items are worked by the rebuild itself (`reembedDocuments`), not by this queue (5.8):
                // taken here, a rebuild's document was imported as a new file, skipped as already imported, and its
                // item marked done while the rebuild still waited on it.
                guard item.stage == .queued, !item.metrics.isRebuild else { return false }
                return !item.hasActiveLease(at: now) || item.isLeased(to: currentDeviceID, at: now)
            })
        else {
            return nil
        }

        var item = ingestionItems[index]
        item.claimLease(ownerDeviceId: currentDeviceID, duration: Self.ingestionLeaseDuration, now: now)
        ingestionItems[index] = item
        savePersistedIngestionQueueState()
        return item
    }

    @MainActor
    func removeIngestionItem(id: UUID?) {
        guard let id else { return }
        ingestionItems.removeAll { $0.id == id }
    }

    @MainActor
    func updateIngestionItem(
        id: UUID?,
        filename: String,
        stage: IngestionStage,
        detail: String,
        progress: Double? = nil,
        errorMessage: String? = nil,
        savesQueue: Bool = true,
        metricsUpdate: ((inout PipelineMetrics) -> Void)? = nil
    ) {
        // A file the person paused stays paused until Continue, Discard or its own Cancel (5.7). The task the pause
        // cancelled runs on to its next cancellation check, and its progress can land after the pause: on
        // 2026-10-16, in the Simulator, "Storing" replaced "Paused" on a file whose embedding had just finished, and
        // Continue, which takes the paused files, left that one at "Storing" with nothing importing it. An end still
        // lands: a store that finished before the check put the file in the library, and Cancel on a paused file
        // ends it through here.
        if let id, let index = ingestionItems.firstIndex(where: { $0.id == id }),
            ingestionItems[index].stage == .paused, stage != .paused, !stage.isTerminal
        {
            return
        }
        processingStatus = "\(filename) • \(detail)"
        guard let id, let index = ingestionItems.firstIndex(where: { $0.id == id }) else { return }

        // Haptic feedback for stage transitions
        let oldStage = ingestionItems[index].stage
        if oldStage != stage {
            triggerIngestionHaptic(for: stage)
            // Each stage a file reaches, with its type and the time since it started (5.8). No file name.
            VerificationJournal.record(
                "import.stage",
                stage == .failed ? .failed : stage == .cancelled ? .cancelled : stage == .complete ? .ok : .info,
                durationMs: ingestionItems[index].startedAt.map { Date().timeIntervalSince($0) * 1000 },
                Self.importStageFields(
                    ["item": VerificationJournal.anon(id), "from": oldStage.rawValue, "to": stage.rawValue,
                        "type": ingestionItems[index].url.pathExtension.lowercased(),
                        "background": "\(Self.appIsInBackground)",
                        "rebuild": "\(ingestionItems[index].metrics.isRebuild)"],
                    url: ingestionItems[index].url,
                    othersInLibrary: stage == .complete
                        ? documentsForContainer(ingestionItems[index].containerId ?? containerService.activeContainerId).count : nil))
        }

        var item = ingestionItems[index]
        let currentDeviceID = WorkspaceSyncService.currentDeviceID()
        item.stage = stage
        item.detail = detail
        item.progress = progress

        let event = IngestionEvent(
            stage: stage,
            title: stage.displayName,
            detail: detail
        )

        if let lastEvent = item.events.last, lastEvent.stage == stage && lastEvent.detail == detail {
            // Prevent duplicate events for pure progress updates
        } else {
            item.events.append(event)
            // Limit event history to prevent OOM / unbounded UI rendering for massive documents
            if item.events.count > 100 {
                item.events.removeFirst(item.events.count - 100)
            }
        }

        if item.startedAt == nil, stage != .queued && stage != .paused {
            item.startedAt = Date()
        }
        if stage.isTerminal {
            item.finishedAt = Date()
            if let startedAt = item.startedAt {
                item.metrics.totalTimeMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            }
            item.clearLease()
        } else if stage == .queued || stage == .paused {
            item.clearLease()
        } else {
            item.claimLease(ownerDeviceId: currentDeviceID, duration: Self.ingestionLeaseDuration)
        }
        if let errorMessage {
            item.errorMessage = errorMessage
        }
        if let metricsUpdate {
            metricsUpdate(&item.metrics)
        }
        ingestionItems[index] = item
        // The queue file is in the workspace, which iCloud may be syncing, and it is written with
        // file coordination on the main actor. A caller that reports progress every few seconds
        // (the passages of a piece as they are embedded) leaves the file alone; what it reports
        // is not needed to continue.
        if savesQueue {
            savePersistedIngestionQueueState()
        }
        IngestionRuntimeBridge.shared.updateContinuedIngestionProgress(
            title: "Importing documents",
            subtitle: "\(filename) • \(stage.displayName)",
            fraction: ImportProgress.fraction(of: currentImportItems)
        )
        syncIngestionLiveActivity()
    }

    /// Haptic feedback based on ingestion stage
    @MainActor
    private func triggerIngestionHaptic(for stage: IngestionStage) {
        switch stage {
        case .loading, .extracting:
            DSHaptics.soft()  // Just starting
        case .transcribing:
            DSHaptics.processingPulse()  // Audio/video processing
        case .chunking, .analyzing, .adapting:
            DSHaptics.tick()  // Processing ticks
        case .embedding:
            DSHaptics.processingPulse()  // Neural processing
        case .indexing:
            DSHaptics.tick()
        case .storing:
            DSHaptics.soft()
        case .complete:
            DSHaptics.documentIngested()  // Success!
        case .cancelled:
            break
        case .failed:
            DSHaptics.warning()  // Something went wrong
        case .reindexing, .queued, .paused:
            break  // No haptic for these
        }
    }

    @MainActor
    private func markIngestionFailed(id: UUID, error: Error) {
        if let item = ingestionItems.first(where: { $0.id == id }) {
            updateIngestionItem(
                id: id,
                filename: item.filename,
                stage: .failed,
                detail: "Failed",
                errorMessage: error.localizedDescription
            )
        }
    }

    @MainActor
    private func handleUserRequestedIngestionCancellation(activeItemId: UUID) -> Bool {
        guard !requestedIngestionCancellationIds.isEmpty else { return false }

        let idsToFinalize = requestedIngestionCancellationIds
        requestedIngestionCancellationIds.removeAll()

        if idsToFinalize.contains(activeItemId),
            let activeItem = ingestionItems.first(where: { $0.id == activeItemId && !$0.stage.isTerminal })
        {
            updateIngestionItem(
                id: activeItemId,
                filename: activeItem.filename,
                stage: .cancelled,
                detail: "Cancelled"
            )
        }

        finalizeCancelledIngestionTracking(for: Array(idsToFinalize))
        pruneCompletedIngestionItems()
        return true
    }

    @MainActor
    private func finalizeCancelledIngestionTracking(for ids: [UUID]) {
        guard !ids.isEmpty else { return }

        let idSet = Set(ids)
        ingestionContexts = ingestionContexts.filter { key, _ in !idSet.contains(key) }
        liveActivityTrackedIngestionIds.subtract(idSet)
        savePersistedIngestionQueueState()
        syncIngestionLiveActivity()
    }

    private func waitForIngestionCompletion(ids: [UUID]) async -> IngestionBatchResult {
        guard !ids.isEmpty else {
            return IngestionBatchResult(
                successCount: 0,
                failureCount: 0,
                totalCount: 0,
                completedIds: []
            )
        }
        while true {
            if Task.isCancelled {
                let snapshot = await MainActor.run {
                    ingestionItems.filter { ids.contains($0.id) }
                }
                return IngestionBatchResult(
                    successCount: snapshot.filter { $0.stage == .complete }.count,
                    failureCount: snapshot.filter { !$0.stage.isTerminal }.count,
                    totalCount: snapshot.count,
                    completedIds: snapshot.filter { $0.stage.isTerminal }.map(\.id)
                )
            }
            let snapshot = await MainActor.run {
                ingestionItems.filter { ids.contains($0.id) }
            }
            let allDone = snapshot.allSatisfy { $0.stage.isTerminal }
            if allDone {
                let successCount = snapshot.filter { $0.stage == .complete }.count
                let failureCount = snapshot.filter { $0.stage == .failed }.count
                return IngestionBatchResult(
                    successCount: successCount,
                    failureCount: failureCount,
                    totalCount: snapshot.count,
                    completedIds: snapshot.map { $0.id }
                )
            }
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms poll interval (was 200ms)
        }
    }

    /// The import the person is watching: the documents they started that the Live Activity follows,
    /// finished ones included until the whole import has finished, or every document in the queue
    /// when none is followed (an import resumed in the background). The background task, the Live
    /// Activity and "Check Import Status" all count this list (`ImportProgress`), so a document
    /// finished in an earlier import and not yet cleared from the queue is not counted as done.
    @MainActor
    var currentImportItems: [IngestionItem] {
        let followed = ingestionItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        return followed.isEmpty ? ingestionItems : followed
    }

    @MainActor
    func pruneCompletedIngestionItems(delay: TimeInterval = 4.0) {
        guard ingestionItems.contains(where: { $0.stage.isTerminal }) else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let self else { return }
                let hasActive = self.ingestionItems.contains { !$0.stage.isTerminal }
                if hasActive { return }
                self.ingestionItems.removeAll { $0.stage.isTerminal }
                self.ingestionContexts = self.ingestionContexts.filter { key, _ in
                    self.ingestionItems.contains(where: { $0.id == key })
                }
                self.liveActivityTrackedIngestionIds = self.liveActivityTrackedIngestionIds.filter { trackedId in
                    self.ingestionItems.contains(where: { $0.id == trackedId })
                }
                self.syncIngestionLiveActivity()
                self.savePersistedIngestionQueueState()
            }
        }
    }

    @MainActor
    func syncIngestionLiveActivity() {
        let trackedSnapshot = ingestionItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        let containerName = containerService.activeContainer?.name
        if !trackedSnapshot.isEmpty, trackedSnapshot.allSatisfy({ $0.stage.isTerminal }) {
            let success = trackedSnapshot.allSatisfy { $0.stage == .complete }
            IngestionRuntimeBridge.shared.finishLiveActivity(items: trackedSnapshot, containerName: containerName)
            IngestionRuntimeBridge.shared.completeUserInitiatedIngestion(success: success)
            liveActivityTrackedIngestionIds.removeAll()
            return
        }

        // A document that has finished stays tracked until the whole import has (5.7). Through 5.6
        // it was dropped as it finished, so the Live Activity counted only what was left: three
        // documents read 0/3, then 0/2, then 0/1, and its bar went back as each one ended.
        liveActivityTrackedIngestionIds = liveActivityTrackedIngestionIds.filter { trackedId in
            ingestionItems.contains { $0.id == trackedId }
        }

        let trackedItems = ingestionItems.filter { liveActivityTrackedIngestionIds.contains($0.id) }
        if trackedItems.isEmpty {
            IngestionRuntimeBridge.shared.endLiveActivity()
        } else {
            IngestionRuntimeBridge.shared.syncLiveActivity(items: trackedItems, containerName: containerName)
        }
    }

    /// Add a document to the knowledge base
    /// This performs the full ingestion pipeline: parse → chunk → embed → store
    /// - Parameter containerId: the library to import into. `nil`, or a library that no longer exists,
    ///   means the active one.
    func addDocument(
        at url: URL,
        context: IngestionContext = .userInitiated,
        trackingId: UUID? = nil,
        manageProcessingState: Bool = true,
        containerId: UUID? = nil,
        documentId reusedDocumentId: UUID? = nil
    ) async throws {
        let managedURL = try prepareManagedDocumentURL(from: url)
        try await WorkspaceSyncService.ensureItemAvailableLocally(at: managedURL)
        let filename = managedURL.lastPathComponent
        let managedRelativePath = AppSupportPaths.relativePath(for: managedURL)
        // The library the file was queued for (5.7). Through 5.6 every import went to the library that
        // was active when the queue reached it, so "Add to Library" naming another library, or a file
        // queued before the person switched libraries, landed in the open one. The name stays: the
        // rest of this function and the large-file paths take it as the import's library.
        let activeContainerId = await MainActor.run { () -> UUID in
            if let containerId, self.containerService.containers.contains(where: { $0.id == containerId }) {
                // The guide library takes the app's guides only (5.8): anything else goes to the person's own. A rebuild
                // puts each document back where it was, the guides included.
                if context != .onboarding, context != .autoRebuild, let own = self.containerService.libraryForOwnFiles(requested: containerId) {
                    return own
                }
                return containerId
            }
            if context != .onboarding, context != .autoRebuild,
                let own = self.containerService.libraryForOwnFiles(requested: self.containerService.activeContainerId)
            {
                return own
            }
            return self.containerService.activeContainerId
        }

        let documentHash: String?
        do {
            documentHash = try computeDocumentHash(for: managedURL)
        } catch {
            Log.warning(
                "[RAGService] Failed to compute document hash for \(filename): \(error.localizedDescription)",
                category: .ingestion)
            documentHash = nil
        }

        await MainActor.run {
            self.updateIngestionItemMetadata(
                id: trackingId,
                documentHash: documentHash,
                storageRelativePath: managedRelativePath
            )
        }

        // A rebuild's document is the one being replaced (5.8): a sync pass while it ran can have put its record back.
        if reusedDocumentId == nil, let existingDocument = await MainActor.run(
            resultType: Document?.self,
            body: {
                self.existingImportedDocument(
                    in: activeContainerId,
                    storageRelativePath: managedRelativePath,
                    fileHash: documentHash
                )
            })
        {
            Log.info(
                "[RAGService] Skipping already imported document '\(filename)' (existing id: \(existingDocument.id.uuidString))",
                category: .ingestion
            )

            // The user asked for this file. If a previous deletion tombstoned this id,
            // skipping here without clearing it would leave the record to be erased by
            // the next sync, with nothing left to recreate it.
            await MainActor.run {
                self.clearDeletionTombstones(for: [existingDocument.id])
            }

            await MainActor.run {
                if let trackingId {
                    self.updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .complete,
                        detail: "Already imported",
                        progress: 1.0,
                        errorMessage: nil
                    ) { metrics in
                        if let meta = existingDocument.processingMetadata {
                            metrics.fileSizeMB = meta.fileSizeMB
                            metrics.totalCharacters = meta.totalCharacters
                            metrics.totalWords = meta.totalWords
                            metrics.pageCount = meta.pagesProcessed ?? 0
                            metrics.ocrPagesCount = meta.ocrPagesCount ?? 0
                            metrics.usedStructuredParsing = meta.usedStructuredParsing
                            metrics.structuredParsingQuality = meta.structuredParsingQuality
                            metrics.tablesExtracted = meta.tablesExtracted
                            metrics.tableRowsTotal = meta.tableRowsTotal
                            metrics.tableColumnsMax = meta.tableColumnsMax
                            metrics.listsExtracted = meta.listsExtracted
                            metrics.listItemsTotal = meta.listItemsTotal
                            metrics.titlesDetected = meta.titlesDetected
                            metrics.figureReferences = meta.figureReferences
                            metrics.visionEntitiesDetected = meta.visionEntitiesDetected
                            metrics.sectionPathDepth = meta.sectionPathDepth
                            metrics.structuredParsingTimeMs = Int(meta.structuredParsingTimeSeconds * 1000)
                            metrics.atomicTableChunks = meta.atomicTableChunks
                            metrics.atomicListChunks = meta.atomicListChunks

                            metrics.chunkCount = existingDocument.totalChunks
                            metrics.embeddingsGenerated = existingDocument.totalChunks

                            metrics.extractionTimeMs = Int(meta.extractionTimeSeconds * 1000)
                            metrics.chunkingTimeMs = Int(meta.chunkingTimeSeconds * 1000)
                            metrics.embeddingTimeMs = Int(meta.embeddingTimeSeconds * 1000)
                            metrics.totalTimeMs = Int(meta.totalProcessingTimeSeconds * 1000)
                            metrics.documentDomain = meta.documentCategory?.rawValue ?? ""
                        } else {
                            metrics.chunkCount = existingDocument.totalChunks
                            metrics.embeddingsGenerated = existingDocument.totalChunks
                        }
                    }
                }

                if manageProcessingState { self.isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    self.processingStatus = ""
                }
                self.lastError = nil
                self.kickPendingReembedIfNeeded()
            }
            return
        }

        // Onboarding sample docs bypass quota — they're educational material
        // that ships with the app, not user-generated content
        // A rebuild re-imports a document already counted (5.8): its record stays listed, so at the plan's limit the
        // check refused it and left it with no passages (review, 2026-11-03).
        let skipQuota = (context == .onboarding) || reusedDocumentId != nil

        let gating = await MainActor.run { () -> (limit: Int, canAdd: Bool, tier: WorkspaceTier, count: Int) in
            let count = self.countedDocumentCount
            if let store = self.entitlementStore {
                return (
                    store.documentLimit, skipQuota || store.canAddDocument(currentCount: count), store.activeTier, count
                )
            } else {
                // No entitlement store: an engine a Shortcuts or Siri action built while the app is closed
                // (`IntentSupport.engine`). Until 5.7 this used the free plan's limit, so Add to Library refused
                // a Pro or Lifetime library of five documents or more; it reads the plan and the document packs
                // the app's store last saved (`EntitlementStore.savedDocumentAllowance`).
                let saved = EntitlementStore.savedDocumentAllowance()
                return (saved.limit, skipQuota || saved.isUnlimited || count < saved.limit, saved.tier, count)
            }
        }
        let documentLimit = gating.limit
        let currentDocumentCount = gating.count
        if !gating.canAdd {
            let quotaError = DocumentQuotaError(limit: documentLimit)
            await MainActor.run {
                self.lastError = quotaError.errorDescription
            }
            TelemetryCenter.emit(
                .ingestion,
                severity: .warning,
                title: "Document quota reached",
                metadata: [
                    "file": filename,
                    "limit": "\(documentLimit)",
                    "currentCount": "\(currentDocumentCount)",
                ]
            )
            TelemetryCenter.emitBillingEvent(
                "Quota hit",
                severity: .warning,
                metadata: [
                    "tier": gating.tier.rawValue,
                    "limit": "\(documentLimit)",
                    "currentCount": "\(currentDocumentCount)",
                    "file": filename,
                ]
            )
            throw quotaError
        }
        let preExistingDocumentsInContainerCount = await MainActor.run {
            self.documentsForContainer(activeContainerId).count
        }

        // Get the active container to determine which embedding provider to use
        var container = await MainActor.run {
            self.containerService.containers.first { $0.id == activeContainerId }
        }
        // FIXED: Default to CoreML sentence embedding (better accuracy) instead of deprecated NLEmbedding
        var providerId = container?.embeddingProviderId ?? "coreml_sentence_embedding"
        var initialDimension = container?.embeddingDim ?? 384
        let chunkOverride = chunkingOverride(for: container)

        // Create container-specific embedding service
        var containerEmbeddingService = EmbeddingService.forProvider(
            id: providerId,
            targetDimension: initialDimension
        )

        // Check if we got a fallback provider and update providerId accordingly
        let actualProvider = containerEmbeddingService.actualProviderId
        let actualDimension = containerEmbeddingService.outputDimension

        if actualProvider != providerId || actualDimension != initialDimension {
            Log.warning(
                "[RAGService] Requested embedding context '\(providerId)' \(initialDimension)D resolved to '\(actualProvider)' \(actualDimension)D. Updating container + clearing index.",
                category: .ingestion
            )

            // Persist corrected config so subsequent queries/ingestion use the real dimension.
            if var current = container {
                current.embeddingProviderId = actualProvider
                current.embeddingDim = actualDimension
                await MainActor.run {
                    self.containerService.updateContainer(current)
                    self.invalidateVectorStore(for: activeContainerId, clearStorage: true)
                }
                container = current
            } else {
                await MainActor.run {
                    self.invalidateVectorStore(for: activeContainerId, clearStorage: true)
                }
            }

            providerId = actualProvider
            initialDimension = actualDimension

            // Recreate the embedding service with the reconciled dimension to keep downstream logging consistent.
            containerEmbeddingService = EmbeddingService.forProvider(
                id: providerId,
                targetDimension: initialDimension,
                allowFallback: true
            )
        }

        let pipelineStartTime = Date()

        // Imports can overlap (a file attached in Chat while the queue imports), and the Core ML and Core AI
        // providers are each one object shared by every service (5.8), so the first import to finish used to
        // switch the other's provider back mid-import. Only the last import using a provider switches it back.
        let ingestionModeKey = containerEmbeddingService.actualProviderId
        ingestionModeHolders[ingestionModeKey, default: 0] += 1
        containerEmbeddingService.enableIngestionMode()
        defer {
            let remaining = (ingestionModeHolders[ingestionModeKey] ?? 1) - 1
            ingestionModeHolders[ingestionModeKey] = remaining > 0 ? remaining : nil
            if remaining <= 0 { containerEmbeddingService.disableIngestionMode() }
        }

        TelemetryCenter.emit(
            .ingestion,
            title: "Ingestion started",
            metadata: [
                "file": filename,
                "embeddingProvider": providerId,
            ]
        )

        var pendingSelfTuneReasons: [String] = []

        await MainActor.run {
            if manageProcessingState { isProcessing = true }
            updateIngestionItem(id: trackingId, filename: filename, stage: .loading, detail: "Loading")
        }

        // Yield to let SwiftUI render the overlay (@Published updates propagate on next run loop)
        await Task.yield()

        // Set up progress handler for real-time updates (legacy string-based)
        documentProcessor.progressHandler = { [weak self] progress in
            Task { @MainActor in
                // Use transcribing stage for audio/video files
                let stage: IngestionStage = progress.contains("transcribing") ? .transcribing : .extracting
                let detail = progress.contains("transcribing") ? "Transcribing audio" : "Extracting (\(progress))"
                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: stage,
                    detail: detail
                )
            }
        }

        // Set up RICH progress handler for live metrics during extraction
        documentProcessor.richProgressHandler = { [weak self] progress in
            Task { @MainActor in
                let stage: IngestionStage
                switch progress.stage {
                case "transcribing":
                    stage = .transcribing
                case "chunking":
                    stage = .chunking
                case "analyzing":
                    stage = .analyzing
                default:
                    stage = .extracting
                }

                var progressFraction: Double? = nil
                if let base = stage.pipelineBaseFraction {
                    let weight = stage.pipelineWeightFraction ?? 0.0
                    if let current = progress.currentPage, let total = progress.totalPages, total > 0 {
                        let stageProgress = Double(current) / Double(total)
                        progressFraction = base + (stageProgress * weight)
                    } else {
                        progressFraction = base
                    }
                }

                self?.updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: stage,
                    detail: progress.detail,
                    progress: progressFraction
                ) { metrics in
                    // Update live metrics from extraction progress
                    metrics.usedStructuredParsing = progress.usingVision
                    metrics.tablesExtracted = progress.tablesFound
                    metrics.listsExtracted = progress.listsFound
                    metrics.titlesDetected = progress.headersFound
                    metrics.ocrPagesCount = progress.ocrPagesUsed
                    if let totalPages = progress.totalPages {
                        metrics.pageCount = totalPages
                    }
                }
            }
        }

        // The document's Spotlight entry, once written, so an import that fails or is cancelled
        // after it removes it (5.7: entries no longer expire).
        var listedInSpotlight: UUID?
        do {
            // Step 1: Parse document and extract chunks
            let documentType = documentProcessor.detectDocumentType(url: managedURL)
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: managedURL.path)
            let fileSizeMB = Double((fileAttrs?[.size] as? Int64) ?? 0) / 1_048_576.0

            // Pre-scan document and auto-tune container settings before ingestion starts (predictive self-tuning)
            var activeChunkOverride = chunkOverride
            if let currentContainer = container, currentContainer.autoAdaptDimension {
                let previewText = await extractPreviewText(from: managedURL, documentType: documentType)
                if !previewText.isEmpty {
                    let plan = await intelligenceCenter.recommendChunkingPlan(
                        forPreviewText: previewText, contentType: documentType)

                    var updated = currentContainer
                    let directive = ChunkingDirective(
                        source: .auto,
                        strategy: plan.strategy.rawValue,
                        targetWordWindow: plan.targetWordWindow,
                        overlapWords: plan.overlapWords,
                        rationale: plan.rationales
                    )
                    updated.chunkingDirective = directive

                    if updated != currentContainer {
                        await MainActor.run {
                            self.containerService.updateContainer(updated)
                        }
                        container = updated
                        activeChunkOverride = chunkingOverride(for: updated)
                        Log.info(
                            "[SelfTuning] Predictive pre-scan auto-tuned configuration for \(filename): Chunk strategy → \(plan.strategy.rawValue.capitalized) • Window \(plan.targetWordWindow) (Rationale: \(plan.rationales.joined(separator: " | "))). Ingesting with optimized settings.",
                            category: .ingestion
                        )
                    }
                }
            }

            let isLargePDF = documentType == .pdf && fileSizeMB > 10
            if isLargePDF {
                try await importLargePDFStreamed(
                    at: managedURL,
                    trackingId: trackingId ?? UUID(),
                    filename: filename,
                    activeContainerId: activeContainerId,
                    chunkOverride: activeChunkOverride,
                    providerId: providerId,
                    embeddingDim: initialDimension,
                    containerEmbeddingService: containerEmbeddingService,
                    documentId: reusedDocumentId
                )
                // The refresh every other import ends with (the rest of what a whole-file
                // import does at its end is not done here). Without it the analysis and the
                // vocabulary held for the library, in memory and on disk, stayed those of the
                // library before this document until the app was opened again.
                refreshIntelligence(for: activeContainerId, force: true)
                return  // Streaming method handles the full end-to-end pipeline
            }

            // A large text or JSON Lines file, a piece at a time. Read whole, an 88 MB file held
            // 2.8 GB on an iPhone and never finished (2026-10-09).
            let fileBytes = (fileAttrs?[.size] as? Int64).map { Int($0) } ?? 0
            if DocumentProcessor.importsInPieces(
                fileExtension: managedURL.pathExtension, documentType: documentType, fileBytes: fileBytes),
                (try? TextPieceReader(url: managedURL))?.canBeCutAtLineFeeds == true
            {
                try await importLargeTextStreamed(
                    at: managedURL,
                    trackingId: trackingId ?? UUID(),
                    filename: filename,
                    activeContainerId: activeContainerId,
                    documentType: documentType,
                    chunkOverride: activeChunkOverride,
                    providerId: providerId,
                    containerEmbeddingService: containerEmbeddingService,
                    documentId: reusedDocumentId
                )
                refreshIntelligence(for: activeContainerId, force: true)
                return  // It handles the whole import, like the streamed PDF above.
            }

            let extractionStartTime = Date()
            let (document, processedChunks) = try await documentProcessor.processDocument(
                at: managedURL,
                chunkOverride: activeChunkOverride,
                containerId: activeContainerId,  // FTS5 storage with container isolation
                documentId: reusedDocumentId
            )
            // How long the main thread went unanswered while the document was read and cut into passages (5.8), from
            // the development build's watchdog: row "Import still runs whole-document passes on the main thread".
            if VerificationJournal.isEnabled, MainThreadWatchdog.shared.isRunning {
                let lagMs = MainThreadWatchdog.shared.longestStall(since: extractionStartTime)
                VerificationJournal.record(
                    "import.mainThreadLag", .ok,
                    durationMs: Date().timeIntervalSince(extractionStartTime) * 1000,
                    ["type": managedURL.pathExtension.lowercased(),
                        "bytes": "\(VerificationJournal.fileBytes(managedURL))",
                        "maxLagMs": "\(Int(lagMs))", "responsive": "\(lagMs < MainThreadWatchdog.stallThresholdMs)",
                        "chunks": "\(processedChunks.count)"])
            }
            try Task.checkCancellation()
            let extractionTime = Date().timeIntervalSince(extractionStartTime)
            // The document's own counts, of its text as it was read (5.7). Summing the passages counted
            // the words two neighbours share twice (row "Word counts look wrong").
            let totalChars =
                document.processingMetadata?.totalCharacters
                ?? processedChunks.reduce(0) { $0 + $1.metadata.characterCount }
            let totalWords =
                document.processingMetadata?.totalWords
                ?? processedChunks.reduce(0) { $0 + $1.metadata.wordCount }

            // Calculate chunk word stats
            let chunkWordCounts = processedChunks.map { $0.metadata.wordCount }
            let avgChunkWords = chunkWordCounts.isEmpty ? 0 : chunkWordCounts.reduce(0, +) / chunkWordCounts.count
            let minChunkWords = chunkWordCounts.min() ?? 0
            let maxChunkWords = chunkWordCounts.max() ?? 0

            // Get file metadata (already parsed above)

            TelemetryCenter.emit(
                .ingestion,
                title: "Extraction complete",
                metadata: [
                    "file": filename,
                    "chunks": "\(processedChunks.count)",
                    "words": "\(totalWords)",
                ],
                duration: extractionTime
            )

            // Build domain vocabulary from extracted text for improved entity recognition
            let combinedText = processedChunks.map { $0.text }.joined(separator: " ")
            await GazetteerService.shared.extractAndAddTerms(from: combinedText, source: filename)
            try Task.checkCancellation()

            // Index document in Spotlight for system-wide search
            let spotlightEnabled = await MainActor.run { self.settingsStore?.enableSpotlightIndexing ?? true }
            if spotlightEnabled {
                let cid = activeContainerId
                let containerName = await MainActor.run {
                    self.containerService.containers.first(where: { $0.id == cid })?.name ?? "Library"
                }
                SpotlightIndexService.shared.indexDocument(
                    id: document.id,
                    filename: document.filename,
                    containerId: activeContainerId,
                    containerName: containerName,
                    textPreview: String(combinedText.prefix(500)),
                    chunkCount: processedChunks.count
                )
                listedInSpotlight = document.id
            }
            try Task.checkCancellation()

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .chunking,
                    detail: "\(processedChunks.count) chunks • \(totalWords) words • avg \(avgChunkWords)w/chunk"
                ) { metrics in
                    metrics.fileSizeMB = fileSizeMB
                    metrics.totalCharacters = totalChars
                    metrics.totalWords = totalWords
                    metrics.pageCount = document.processingMetadata?.pagesProcessed ?? 0
                    metrics.ocrPagesCount = document.processingMetadata?.ocrPagesCount ?? 0
                    metrics.chunkCount = processedChunks.count
                    metrics.avgChunkWords = avgChunkWords
                    metrics.minChunkWords = minChunkWords
                    metrics.maxChunkWords = maxChunkWords
                    metrics.extractionTimeMs = Int(extractionTime * 1000)

                    // === STRUCTURED PARSING TRANSPARENCY ===
                    if let meta = document.processingMetadata {
                        metrics.usedStructuredParsing = meta.usedStructuredParsing
                        metrics.structuredParsingQuality = meta.structuredParsingQuality
                        metrics.tablesExtracted = meta.tablesExtracted
                        metrics.tableRowsTotal = meta.tableRowsTotal
                        metrics.tableColumnsMax = meta.tableColumnsMax
                        metrics.listsExtracted = meta.listsExtracted
                        metrics.listItemsTotal = meta.listItemsTotal
                        metrics.titlesDetected = meta.titlesDetected
                        metrics.figureReferences = meta.figureReferences
                        metrics.visionEntitiesDetected = meta.visionEntitiesDetected
                        metrics.sectionPathDepth = meta.sectionPathDepth
                        metrics.structuredParsingTimeMs = Int(meta.structuredParsingTimeSeconds * 1000)
                        metrics.atomicTableChunks = meta.atomicTableChunks
                        metrics.atomicListChunks = meta.atomicListChunks
                    }
                }
            }

            // Yield to let SwiftUI render chunking status
            await Task.yield()

            // Step 1.5: Auto-adapt configuration if enabled
            if context.allowsSelfTuningScheduling,
                let autoContainer = container,
                autoContainer.autoAdaptDimension
            {
                let analysisStartTime = Date()
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Loading existing chunks for corpus analysis...",
                        progress: 0.1
                    ) { metrics in
                        metrics.isAutoAdaptive = true
                    }
                }

                // This block does not run in any build so far: `allowsSelfTuningScheduling` is
                // false for every kind of import. It is kept in step with the launch analysis so
                // that turning it on would not bring back a read of every passage.
                // The library as it is, counted. Its passages are read by `libraryAnalysisInput`
                // below, all of them or a sample.
                let db = await dbForActiveContainer()
                let existingPassageCount = (try? await db.count()) ?? 0

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail:
                            "Analyzing \(existingPassageCount + processedChunks.count) chunks for vocabulary patterns...",
                        progress: 0.3
                    )
                }

                // Analyze combined corpus (existing + new document)
                let allDocumentsForAnalysis = await MainActor.run {
                    self.documents.filter { $0.containerId == activeContainerId } + [document]
                }
                let newDocumentChunks =
                    processedChunks.enumerated().map { index, chunk in
                        DocumentChunk(
                            documentId: document.id,
                            content: chunk.text,
                            parentContent: chunk.parentText,
                            embedding: [],  // Empty for analysis
                            metadata: ChunkMetadata(
                                chunkIndex: index,
                                startPosition: chunk.metadata.startPosition,
                                endPosition: chunk.metadata.endPosition,
                                pageNumber: chunk.metadata.pageNumber,
                                sectionTitle: chunk.metadata.sectionTitle,
                                keywords: chunk.metadata.keywords,
                                semanticDensity: chunk.metadata.semanticDensity,
                                hasNumericData: chunk.metadata.hasNumericData,
                                hasListStructure: chunk.metadata.hasListStructure,
                                wordCount: chunk.metadata.wordCount,
                                characterCount: chunk.metadata.characterCount,
                                createdAt: chunk.metadata.createdAt,
                                structureType: chunk.metadata.structureType,
                                siblingGroupId: chunk.metadata.siblingGroupId,
                                siblingCount: chunk.metadata.siblingCount,
                                entities: chunk.metadata.entities,
                                abbreviations: chunk.metadata.abbreviations,
                                abstractionLevel: chunk.metadata.abstractionLevel,
                                sectionPath: chunk.metadata.sectionPath,
                                bboxArray: chunk.metadata.bboxArray,
                                documentCategory: chunk.metadata.documentCategory,
                                chunkType: chunk.metadata.chunkType,
                                tableTitle: chunk.metadata.tableTitle,
                                imageContentType: chunk.metadata.imageContentType,
                                imageCaption: chunk.metadata.imageCaption,
                                imageDescription: chunk.metadata.imageDescription,
                                imageExtractedText: chunk.metadata.imageExtractedText,
                                imageClassifications: chunk.metadata.imageClassifications,
                                hasCrossReferences: chunk.metadata.hasCrossReferences,
                                resolvedReferences: chunk.metadata.resolvedReferences
                            )
                        )
                    }

                // Update progress before analysis
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Detecting languages, code patterns, and domain signals...",
                        progress: 0.5
                    )
                }

                let analysisInput = await Self.libraryAnalysisInput(from: db, adding: newDocumentChunks)
                let report = await intelligenceCenter.analyzeLibrary(
                    documents: allDocumentsForAnalysis,
                    chunks: analysisInput.chunks,
                    library: analysisInput.size
                )

                // Update progress after analysis
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: "Computing optimal chunking and embedding strategy...",
                        progress: 0.8
                    )
                }

                let analysisTime = Date().timeIntervalSince(analysisStartTime)

                // Update metrics with analysis results
                let detectedLangs = report.corpus.languageHypotheses.sorted { $0.value > $1.value }.prefix(3).map {
                    $0.key.rawValue
                }

                // Classify document domain from filename and content signals
                let domain = Self.classifyDocumentDomain(
                    filename: filename, signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
                let descriptor = Self.buildContentDescriptor(
                    signals: report.corpus, entities: report.documents.flatMap { $0.keyTopics })
                let categories = Self.extractContentCategories(
                    entities: report.documents.flatMap { $0.keyTopics }, signals: report.corpus)
                let primaryLang = detectedLangs.first.flatMap { Self.languageDisplayName($0) } ?? ""

                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .analyzing,
                        detail: domain.isEmpty ? "Analyzing content structure..." : "\(domain) • \(descriptor)",
                        progress: 1.0
                    ) { metrics in
                        metrics.vocabularyRichness = report.corpus.vocabularyRichness
                        metrics.technicalDensity = report.corpus.technicalDensity
                        metrics.semanticComplexity = report.corpus.semanticComplexity
                        metrics.multilingualScore = report.corpus.multilingualScore
                        metrics.hasCode = report.corpus.hasCode
                        metrics.hasMath = report.corpus.hasMath
                        metrics.detectedLanguages = detectedLangs
                        metrics.chunkingStrategy = report.chunking.strategy.rawValue
                        metrics.targetWordWindow = report.chunking.targetWordWindow
                        metrics.overlapWords = report.chunking.overlapWords
                        metrics.analysisTimeMs = Int(analysisTime * 1000)

                        // Document content profile (displayed in UI instead of raw ratios)
                        metrics.documentDomain = domain
                        metrics.contentDescriptor = descriptor
                        metrics.contentCategories = categories
                        metrics.documentLanguage = primaryLang
                        // extractionCoverage is set during extraction phase
                    }
                }

                await MainActor.run {
                    // This report is of the library with the document being imported added to
                    // it, which no signature of the library on disk describes yet.
                    self.containerIntelligence[activeContainerId] = report
                    self.containerIntelligenceSignature.removeValue(forKey: activeContainerId)
                }

                // Log analysis results
                TelemetryCenter.emit(
                    .ingestion,
                    title: "Content analysis complete",
                    metadata: [
                        "file": filename,
                        "vocabularyRichness": String(format: "%.2f", report.corpus.vocabularyRichness),
                        "multilingualScore": String(format: "%.2f", report.corpus.multilingualScore),
                        "technicalDensity": String(format: "%.2f", report.corpus.technicalDensity),
                        "semanticComplexity": String(format: "%.2f", report.corpus.semanticComplexity),
                        "chunkingStrategy": report.chunking.strategy.rawValue,
                        "chunkWindow": "\(report.chunking.targetWordWindow)",
                        "chunkOverlap": "\(report.chunking.overlapWords)",
                        "retrievalFusion": report.retrieval.fusionStyle.rawValue,
                        "retrievalVectorWeight": String(format: "%.2f", report.retrieval.vectorWeight),
                        "retrievalLexicalWeight": String(format: "%.2f", report.retrieval.lexicalWeight),
                        "recommendedDimension": "\(report.embedding.dimension)",
                        "recommendedProvider": report.embedding.providerId,
                        "confidence": String(format: "%.1f%%", report.embedding.confidence * 100),
                        "reasoning": report.embedding.rationale,
                        "alerts": report.alerts.joined(separator: " | "),
                    ]
                )

                // A library with no documents yet is choosing its settings for this first
                // import, which nothing has been embedded under, so its embedding model may come
                // from a sample of a long document. A library that has documents does not get
                // another model from a sample.
                let (updatedContainer, autoReasons) = Self.resolveAutoAdjustments(
                    for: autoContainer,
                    report: report,
                    allowingEstimate: preExistingDocumentsInContainerCount == 0
                )

                if updatedContainer != autoContainer {
                    let embeddingChanged =
                        updatedContainer.embeddingProviderId != autoContainer.embeddingProviderId
                        || updatedContainer.embeddingDim != autoContainer.embeddingDim

                    if embeddingChanged {
                        providerId = updatedContainer.embeddingProviderId
                        containerEmbeddingService = EmbeddingService.forProvider(
                            id: updatedContainer.embeddingProviderId,
                            targetDimension: updatedContainer.embeddingDim
                        )
                        await MainActor.run {
                            updateIngestionItem(
                                id: trackingId,
                                filename: filename,
                                stage: .analyzing,
                                detail: "Config adapted to \(updatedContainer.embeddingDim)D"
                            )
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms flash
                    }

                    container = updatedContainer
                    await MainActor.run {
                        self.containerService.updateContainer(updatedContainer)
                    }
                }

                if context.allowsSelfTuningScheduling, !autoReasons.isEmpty {
                    // If this is the first document in the container, we've already applied the
                    // updated config *before* embedding, so there is nothing to rebuild yet.
                    // Without this guard, the app will immediately re-embed the just-added doc,
                    // which looks like an infinite “re-upload” loop to the user.
                    if preExistingDocumentsInContainerCount > 0, !report.corpus.isEstimate {
                        // Never from a sample: its reason can only be the chunking, and a
                        // rebuild embeds every document again.
                        pendingSelfTuneReasons = autoReasons
                    } else if preExistingDocumentsInContainerCount > 0 {
                        Log.info(
                            "Skipping self-tuning rebuild: the analysis read a sample of the library.",
                            category: .ingestion)
                    } else {
                        Log.info(
                            "Skipping self-tuning rebuild: config updated during first ingest and there are no prior documents to rebuild.",
                            category: .ingestion
                        )
                    }
                }
            }

            try Task.checkCancellation()

            // Step 2: Generate embeddings with progress updates
            // Implements Anthropic's Contextual Retrieval: prepend document context to chunks
            // BEFORE embedding, so the embedding captures document-level semantics.
            // This reduces retrieval failures by 35-67% according to Anthropic's research.
            var embeddings: [[Float]] = []
            var contextualPrefixes: [String] = []
            let embeddingStartTime = Date()

            // Get embedding dimension from provider
            let embeddingDim = container?.embeddingDim ?? 384
            let embeddingProviderName = Self.shortProviderName(for: providerId)

            // Build contextual prefix once (reused for all chunks in this document)
            let docContext = buildContextualPrefix(filename: filename)
            Log.info("[Contextual] Document prefix: '\(docContext)'", category: .ingestion)

            // HYPERCHARGE: Build all texts to embed upfront, then batch embed
            // This uses parallel embedding (TaskGroup) in the provider layer
            var textsToEmbed: [String] = []
            textsToEmbed.reserveCapacity(processedChunks.count)
            let translatedChunkTexts = await translatedTextsForEmbedding(
                processedChunks.map(\.text),
                container: container
            )

            // Get token limits from the embedding service
            let maxTokens = containerEmbeddingService.maxSafeTokens  // 510 for CoreML

            for (chunk, translatedChunkText) in zip(processedChunks, translatedChunkTexts) {
                // Build chunk-specific contextual prefix with FULL section hierarchy
                // Uses sectionPath (e.g. ["SPECIFICATIONS", "Engine Oil"]) for maximum
                // heading context in the embedding. This is THE key to making embeddings
                // discriminative — "[CarManual] [SPECIFICATIONS > Engine Oil] SAE 0W-20"
                // vs "[CarManual] [SPECIFICATIONS > Differential Gear Oil] SAE 75W/85"
                let sectionContext: String
                if let path = Self.trustedSectionDisplayPath(chunk.metadata.sectionPath), !path.isEmpty {
                    // Full hierarchical path: " [SPECIFICATIONS > Engine Oil]"
                    sectionContext = " [\(path.joined(separator: " > "))]"
                } else if let title = Self.trustedSectionDisplayLabel(chunk.metadata.sectionTitle) {
                    // Fallback to just title
                    sectionContext = " [\(title)]"
                } else {
                    sectionContext = ""
                }
                let contextualPrefix = docContext + sectionContext + " "
                contextualPrefixes.append(contextualPrefix)

                // Embed with contextual prefix prepended (Anthropic's key insight)
                var textForEmbedding = contextualPrefix + translatedChunkText

                // CRITICAL: Validate token count using ACTUAL tokenizer
                // NLTokenizer word count != BPE/WordPiece token count!
                let tokenCount = containerEmbeddingService.countTokens(textForEmbedding)
                if tokenCount > maxTokens {
                    // Truncate text to fit within token limit
                    // This should rarely happen if DocumentProcessor limits are set correctly
                    Log.warning(
                        "[RAGService] ⚠️ Chunk exceeds token limit: \(tokenCount)/\(maxTokens) tokens. "
                            + "Truncating to prevent embedding data loss.",
                        category: .ingestion
                    )

                    // Binary search for safe truncation point
                    var low = 0
                    var high = textForEmbedding.count
                    while low < high {
                        let mid = (low + high + 1) / 2
                        let truncated = String(textForEmbedding.prefix(mid))
                        if containerEmbeddingService.countTokens(truncated) <= maxTokens {
                            low = mid
                        } else {
                            high = mid - 1
                        }
                    }
                    textForEmbedding = String(textForEmbedding.prefix(low))

                    let newTokenCount = containerEmbeddingService.countTokens(textForEmbedding)
                    Log.info(
                        "[RAGService] Truncated to \(newTokenCount) tokens (\(textForEmbedding.count) chars)",
                        category: .ingestion)
                }

                textsToEmbed.append(textForEmbedding)
            }

            // Show initial progress
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .embedding,
                    detail: "Vectorizing \(processedChunks.count) chunks → \(embeddingDim)D",
                    progress: 0.0
                ) { metrics in
                    metrics.embeddingDimension = embeddingDim
                    metrics.embeddingProvider = embeddingProviderName
                }
            }

            // Capture variables for closure
            _ = processedChunks.count  // totalChunks used indirectly via embeddings
            let trackingIdForProgress = trackingId
            let filenameForProgress = filename

            // Batch embed with progress callback for live UI updates
            // Kept in the import's checkpoint folder, which is removed when the import finishes (5.7).
            let embeddingCache = documentProcessor.checkpointDirectoryURL(
                for: documentProcessor.computeDocumentFingerprint(at: url))
            embeddings = try await containerEmbeddingService.generateEmbeddings(
                for: textsToEmbed,
                cacheDirectory: embeddingCache,
                progressHandler: { [weak self] (completed: Int, total: Int) in
                    Task { @MainActor in
                        let progress = Double(completed) / Double(max(1, total))
                        self?.updateIngestionItem(
                            id: trackingIdForProgress,
                            filename: filenameForProgress,
                            stage: .embedding,
                            detail: "Embedding \(completed)/\(total) chunks...",
                            progress: progress
                        ) { metrics in
                            metrics.embeddingsGenerated = completed
                            metrics.embeddingBatchProgress = progress
                        }
                    }
                }
            )
            try Task.checkCancellation()
            try EmbeddingVectorCheck.requireUsable(embeddings, of: filename)

            let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

            // Update with final embedding stats
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .indexing,
                    detail: "Building vector + BM25 indexes...",
                    progress: 0.94
                ) { metrics in
                    metrics.embeddingTimeMs = Int(embeddingTime * 1000)
                    metrics.embeddingsGenerated = embeddings.count
                }
            }

            TelemetryCenter.emit(
                .embedding,
                title: "Embeddings generated",
                metadata: [
                    "file": filename,
                    "chunks": "\(processedChunks.count)",
                    "dimensions": "\(embeddings.first?.count ?? 0)",
                    "provider": providerId,
                ],
                duration: embeddingTime
            )

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .storing,
                    detail: "Persisting \(processedChunks.count) chunks to vector database...",
                    progress: 0.94
                )
            }

            // Step 3: Create DocumentChunk objects with embeddings and contextual prefixes
            let chunkingStartTime = Date()
            let documentChunks = zip(zip(processedChunks, embeddings), contextualPrefixes).enumerated().map {
                (index: Int, pair: ((DocumentProcessor.ProcessedChunk, [Float]), String)) in
                let ((chunk, embedding), prefix) = pair
                let base = chunk.metadata
                let enrichedMetadata = ChunkMetadata(
                    chunkIndex: index,
                    startPosition: base.startPosition,
                    endPosition: base.endPosition,
                    pageNumber: base.pageNumber,
                    sectionTitle: base.sectionTitle,
                    keywords: base.keywords,
                    semanticDensity: base.semanticDensity,
                    hasNumericData: base.hasNumericData,
                    hasListStructure: base.hasListStructure,
                    wordCount: base.wordCount,
                    characterCount: base.characterCount,
                    createdAt: base.createdAt,
                    structureType: base.structureType,
                    siblingGroupId: base.siblingGroupId,
                    siblingCount: base.siblingCount,
                    entities: base.entities,
                    abbreviations: base.abbreviations,
                    abstractionLevel: base.abstractionLevel,
                    sectionPath: base.sectionPath,
                    bboxArray: base.bboxArray,
                    documentCategory: base.documentCategory,
                    chunkType: base.chunkType,
                    tableTitle: base.tableTitle,
                    imageContentType: base.imageContentType,
                    imageCaption: base.imageCaption,
                    imageDescription: base.imageDescription,
                    imageExtractedText: base.imageExtractedText,
                    imageClassifications: base.imageClassifications,
                    hasCrossReferences: base.hasCrossReferences,
                    resolvedReferences: base.resolvedReferences
                )
                return DocumentChunk(
                    documentId: document.id,
                    content: chunk.text,
                    parentContent: chunk.parentText,
                    contextualPrefix: prefix,
                    embedding: embedding,
                    metadata: enrichedMetadata
                )
            }
            let chunkingTime = Date().timeIntervalSince(chunkingStartTime)
            TelemetryCenter.emit(
                .storage,
                title: "Chunks prepared",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ],
                duration: chunkingTime
            )

            // Step 4: Store chunks in the vector database for the container this import targets.
            //
            // `dbForActiveContainer()` here was a live read, while every other write in this
            // function uses the `activeContainerId` captured at the top. Switching libraries during
            // a long import therefore split the document: metadata and FTS5 to the captured
            // container, vectors to whichever one was on screen. See `dbForContainer`.
            try Task.checkCancellation()
            let db = try await dbForContainer(activeContainerId)

            // A store that is empty *before* this batch will afterwards hold nothing but chunks
            // written by the pipeline running right now, so its fingerprint is knowable rather
            // than assumed. Recording it here is what makes a nil fingerprint mean "predates the
            // field" instead of "nobody has looked yet".
            //
            // Without this, `91ea045` mis-fired on its first device run: a library deleted and
            // recreated on v5.0, whose 193 chunks were embedded by the corrected pipeline at
            // 19ms/chunk, was offered a rebuild it did not need — because the fingerprint is
            // otherwise only ever written by the staleness check itself, so a freshly built
            // library reads nil until that check runs. Every new library would have seen a
            // spurious rebuild prompt, which is worse than the silence it replaced: a prompt
            // that cries wolf teaches the owner to dismiss the one that matters.
            let chunksBeforeThisImport = (try? await db.count()) ?? -1
            try await db.storeBatch(chunks: documentChunks)
            try await db.persist()
            if chunksBeforeThisImport == 0 {
                await MainActor.run { self.stampEmbeddingFingerprintIfAbsent(for: activeContainerId) }
            }
            // Invalidate visualization cache for this container after data change
            ProjectionCache.shared.invalidate(forContainer: activeContainerId)

            // Step 4.0.0: Index individual document chunks in Spotlight for fine-grained search
            let chunkSpotlightEnabled = await MainActor.run { self.settingsStore?.enableSpotlightIndexing ?? true }
            if chunkSpotlightEnabled {
                await MainActor.run {
                    updateIngestionItem(
                        id: trackingId,
                        filename: filename,
                        stage: .indexing,
                        detail: "Indexing Spotlight search...",
                        progress: 0.95
                    )
                }
                let cid = activeContainerId
                let containerName = await MainActor.run {
                    self.containerService.containers.first(where: { $0.id == cid })?.name ?? "Library"
                }
                SpotlightIndexService.shared.indexDocumentChunks(
                    documentId: document.id,
                    documentName: document.filename,
                    chunks: documentChunks,
                    containerId: activeContainerId,
                    containerName: containerName
                )
            }

            TelemetryCenter.emit(
                .storage,
                title: "Chunks stored",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ]
            )

            // Step 4.0.1: Store chunks in chunk-level FTS5 for section-aware BM25 search
            // This enables chunk-level BM25 scoring with section heading boosts:
            // "oil" matching in sectionTitle="Engine Oil" gets 10x the score of body text
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .indexing,
                    detail: "Indexing text search...",
                    progress: 0.96
                )
            }
            let fts5ChunkData:
                [(
                    chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                    sectionPath: String?, structureType: String?, chunkType: String?,
                    tableTitle: String?, content: String,
                    structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?
                )] =
                    zip(documentChunks, processedChunks).map { chunk, processedChunk in
                        let pathStr = chunk.metadata.sectionPath?.joined(separator: " > ")
                        let structuredMetadata = processedChunk.structuredTable.map { table in
                            SQLiteFullTextService.StructuredChunkMetadata(
                                chunkType: chunk.metadata.chunkType?.rawValue,
                                tableTitle: table.title,
                                headers: table.headers,
                                rows: table.rows,
                                searchText: table.searchText,
                                extractionQuality: table.extractionQuality,
                                extractionSource: table.extractionSource,
                                lowQualityRowIndices: table.lowQualityRowIndices
                            )
                        }
                        return (
                            chunkIndex: chunk.metadata.chunkIndex,
                            pageNumber: chunk.metadata.pageNumber,
                            sectionTitle: chunk.metadata.sectionTitle,
                            sectionPath: pathStr,
                            structureType: chunk.metadata.structureType,
                            chunkType: chunk.metadata.chunkType?.rawValue,
                            tableTitle: chunk.metadata.tableTitle,
                            content: chunk.content,
                            structuredMetadata: structuredMetadata
                        )
                    }
            await SQLiteFullTextService.shared.storeChunks(
                documentId: document.id,
                containerId: activeContainerId,
                chunks: fts5ChunkData
            )
            Log.info("[RAGService] Stored \(documentChunks.count) chunks in FTS5 chunk index", category: .ingestion)

            // Step 4.1: Learn vocabulary from chunks for per-container domain adaptation
            // Extracts domain terms, spec codes, and technical phrases to improve future retrieval
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .analyzing,
                    detail: "Learning vocabulary...",
                    progress: 0.97
                )
            }
            for chunk in documentChunks {
                await ContainerVocabularyService.shared.learnFromChunk(
                    chunk.content,
                    containerId: activeContainerId
                )
            }

            // Step 4.1b: Learn from Vision-detected entities (emails, phones, dates, URLs, etc.)
            // These are automatically extracted during structured document parsing
            let visionEntities = documentProcessor.lastDetectedEntities
            if !visionEntities.isEmpty {
                await ContainerVocabularyService.shared.learnFromDetectedEntities(
                    visionEntities,
                    containerId: activeContainerId
                )
                Log.debug("[RAGService] Learned \(visionEntities.count) Vision-detected entities", category: .ingestion)
            }

            await ContainerVocabularyService.shared.documentIngested(
                filename,
                containerId: activeContainerId
            )
            TelemetryCenter.emit(
                .ingestion,
                title: "Vocabulary learned",
                metadata: [
                    "file": filename,
                    "container": activeContainerId.uuidString,
                    "visionEntities": "\(visionEntities.count)",
                ]
            )

            // Step 4.9: Persist vector store to disk (single write after all batch stores). Before the
            // model work in `enrichImportedDocument`, which comes after the document is saved (5.7).
            // Deferred persistence avoids redundant JSON serialization after each storeBatch call
            try await db.persist()

            // Calculate total pipeline time
            let totalTime = Date().timeIntervalSince(pipelineStartTime)

            // Calculate chunk statistics
            let chunkSizes = processedChunks.map { $0.metadata.characterCount }
            let avgChunkSize = chunkSizes.isEmpty ? 0 : chunkSizes.reduce(0, +) / chunkSizes.count
            let minChunkSize = chunkSizes.min() ?? 0
            let maxChunkSize = chunkSizes.max() ?? 0

            // Format file size string from existing fileSizeMB
            let fileSizeStr: String
            if fileSizeMB < 0.001 {
                fileSizeStr = String(format: "%.0f B", fileSizeMB * 1_048_576)
            } else if fileSizeMB < 1.0 {
                fileSizeStr = String(format: "%.2f KB", fileSizeMB * 1024.0)
            } else {
                fileSizeStr = String(format: "%.2f MB", fileSizeMB)
            }

            // Update document with embedding time and complete metadata
            var updatedDocument = document
            if let existingMetadata = document.processingMetadata {
                // Create new metadata with embedding time added
                var completeMetadata = ProcessingMetadata(
                    fileSizeMB: fileSizeMB,
                    totalCharacters: existingMetadata.totalCharacters,
                    totalWords: existingMetadata.totalWords,
                    extractionTimeSeconds: existingMetadata.extractionTimeSeconds,
                    chunkingTimeSeconds: existingMetadata.chunkingTimeSeconds,
                    embeddingTimeSeconds: embeddingTime,
                    totalProcessingTimeSeconds: totalTime,
                    pagesProcessed: existingMetadata.pagesProcessed,
                    ocrPagesCount: existingMetadata.ocrPagesCount,
                    chunkStats: existingMetadata.chunkStats
                )
                completeMetadata.usedStructuredParsing = existingMetadata.usedStructuredParsing
                completeMetadata.structuredParsingQuality = existingMetadata.structuredParsingQuality
                completeMetadata.tablesExtracted = existingMetadata.tablesExtracted
                completeMetadata.tableRowsTotal = existingMetadata.tableRowsTotal
                completeMetadata.tableColumnsMax = existingMetadata.tableColumnsMax
                completeMetadata.listsExtracted = existingMetadata.listsExtracted
                completeMetadata.listItemsTotal = existingMetadata.listItemsTotal
                completeMetadata.titlesDetected = existingMetadata.titlesDetected
                completeMetadata.figureReferences = existingMetadata.figureReferences
                completeMetadata.visionEntitiesDetected = existingMetadata.visionEntitiesDetected
                completeMetadata.sectionPathDepth = existingMetadata.sectionPathDepth
                completeMetadata.structuredParsingTimeSeconds = existingMetadata.structuredParsingTimeSeconds
                completeMetadata.atomicTableChunks = existingMetadata.atomicTableChunks
                completeMetadata.atomicListChunks = existingMetadata.atomicListChunks
                completeMetadata.documentCategory = existingMetadata.documentCategory

                updatedDocument = Document(
                    id: document.id,
                    filename: document.filename,
                    fileURL: document.fileURL,
                    storageRelativePath: document.storageRelativePath,
                    fileHash: documentHash ?? document.fileHash,
                    contentType: document.contentType,
                    addedAt: document.addedAt,
                    totalChunks: document.totalChunks,
                    processingMetadata: completeMetadata,
                    containerId: document.containerId,
                    contentTags: nil
                )
            }

            // Ensure document is associated with the active container and has content tags
            let docWithContainer = Document(
                id: updatedDocument.id,
                filename: updatedDocument.filename,
                fileURL: updatedDocument.fileURL,
                storageRelativePath: updatedDocument.storageRelativePath,
                fileHash: documentHash ?? updatedDocument.fileHash,
                contentType: updatedDocument.contentType,
                addedAt: updatedDocument.addedAt,
                totalChunks: updatedDocument.totalChunks,
                processingMetadata: updatedDocument.processingMetadata,
                containerId: activeContainerId,
                contentTags: updatedDocument.contentTags
            )
            updatedDocument = docWithContainer

            // Create processing summary with embedding provider info
            let activeProviderId =
                containerService.containers.first { $0.id == activeContainerId }?.embeddingProviderId
                ?? "coreml_sentence_embedding"
            let summary = ProcessingSummary(
                filename: filename,
                fileSize: fileSizeStr,
                documentType: document.contentType,
                pageCount: document.processingMetadata?.pagesProcessed,
                ocrPagesUsed: document.processingMetadata?.ocrPagesCount,
                totalChars: totalChars,
                totalWords: totalWords,
                chunksCreated: processedChunks.count,
                extractionTime: extractionTime,
                chunkingTime: chunkingTime,
                embeddingTime: embeddingTime,
                totalTime: totalTime,
                chunkStats: ProcessingSummary.ChunkStatistics(
                    avgChars: avgChunkSize,
                    minChars: minChunkSize,
                    maxChars: maxChunkSize
                ),
                embeddingProviderId: activeProviderId
            )

            // Step 5: Update state
            await MainActor.run {
                let replacedChunks = listImportedDocument(updatedDocument)
                totalChunksStored += documentChunks.count - replacedChunks
                syncContainerStats(for: activeContainerId, lastIndexedAt: Date())
                if !suppressProcessingSummary {
                    lastProcessingSummary = summary
                }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }
            }

            TelemetryCenter.emit(
                .ingestion,
                title: "Document indexed",
                metadata: [
                    "file": filename,
                    "chunks": "\(documentChunks.count)",
                    "size": fileSizeStr,
                ],
                duration: totalTime
            )

            // Save documents metadata to disk
            await saveDocumentsToDisk()

            // The document is saved and can be searched. What follows is model work that improves it
            // and is not needed to answer from it (5.7). In the background it waits for the app to be
            // in front: on 2026-10-15 iOS ended a background import 53 s in, during this work, and the Lock
            // Screen said "Task failed"; the overview and the tags then came before the save, so an earlier
            // end would have stopped the import before its document was recorded.
            //
            // From 5.8 it also waits while more files are queued, so the queue moves to the next file at once and
            // the work runs when it empties (`runDeferredEnrichmentsIfNeeded`, called at the end of the loop). The
            // work is the same and so is what it writes; through 5.7 each file held the next one for it, up to 20 s
            // a document on an A18 Pro (the note in `enrichImportedDocument`). The last file of an import, or a
            // single file, is still enriched here.
            let (inBackground, filesWaiting) = await MainActor.run {
                (
                    Self.appIsInBackground,
                    self.ingestionItems.contains { $0.stage == .queued && $0.id != trackingId }
                )
            }
            if Self.shouldDeferEnrichment(
                appIsInBackground: inBackground, otherFilesQueued: filesWaiting, isOnboarding: context == .onboarding)
            {
                Self.deferEnrichment(of: updatedDocument.id, in: activeContainerId)
                VerificationJournal.record(
                    "import.enrichmentDeferred",
                    ["document": VerificationJournal.anon(updatedDocument.id),
                        "reason": inBackground ? "background" : "queue", "context": "\(context)"])
                Log.info(
                    inBackground
                        ? "[RAGService] Saved '\(filename)'; its overview, tags and suggested questions wait until the app is in front"
                        : "[RAGService] Saved '\(filename)'; its overview, tags and suggested questions wait until the queue's other files are in",
                    category: .ingestion)
            } else {
                await enrichImportedDocument(
                    updatedDocument, chunks: documentChunks, container: container,
                    embeddingService: containerEmbeddingService, db: db, context: context,
                    trackingId: trackingId, containerId: activeContainerId)
            }

            // Brief yield for UI to catch up before marking complete
            await Task.yield()

            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .complete,
                    detail: "Complete",
                    progress: 1.0
                )
                if manageProcessingState { isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }

                // Record ingestion completion time to prevent immediate self-tuning rebuilds.
                // This stops the bug where adding a large PDF triggers re-embedding of ALL docs.
                self.lastIngestionCompletionTime[activeContainerId] = Date()

                self.kickPendingReembedIfNeeded()

                // Auto-tune retrieval config based on document types in container
                self.autoTuneRetrievalConfigIfNeeded(for: activeContainerId)
            }

            refreshIntelligence(
                for: activeContainerId,
                force: true,
                allowSelfTuningScheduling: context.allowsSelfTuningScheduling
            )

            // Clean up temporary page checkpoints on successful ingestion completion
            documentProcessor.cleanCheckpoints(for: managedURL)

            if context.allowsSelfTuningScheduling, !pendingSelfTuneReasons.isEmpty {
                scheduleSelfTuningRebuild(for: activeContainerId, reasons: pendingSelfTuneReasons)
            }

        } catch {
            if let listedInSpotlight {
                await MainActor.run {
                    SpotlightIndexService.shared.deindexDocument(id: listedInSpotlight, containerId: activeContainerId)
                }
            }
            if error is CancellationError {
                await MainActor.run {
                    if manageProcessingState { isProcessing = false }
                    if manageProcessingState, trackingId == nil {
                        processingStatus = ""
                    }
                    if let trackingId,
                        requestedIngestionCancellationIds.contains(trackingId),
                        let item = ingestionItems.first(where: { $0.id == trackingId && !$0.stage.isTerminal })
                    {
                        updateIngestionItem(
                            id: trackingId,
                            filename: item.filename,
                            stage: .cancelled,
                            detail: "Cancelled"
                        )
                    }
                    self.kickPendingReembedIfNeeded()
                }

                Log.info("[RAGService] Ingestion cancelled for \(filename)", category: .ingestion)
                throw error
            }

            // Reset processing state on error
            await MainActor.run {
                if manageProcessingState { isProcessing = false }
                if manageProcessingState, trackingId == nil {
                    processingStatus = ""
                }
                lastError = error.localizedDescription
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .failed,
                    detail: "Failed",
                    errorMessage: error.localizedDescription
                )
                self.kickPendingReembedIfNeeded()
            }

            // Re-throw with context
            Log.error(" [RAGService] Failed to add document: \(error.localizedDescription)")
            TelemetryCenter.emit(
                .ingestion,
                severity: .error,
                title: "Ingestion failed",
                metadata: [
                    "file": filename,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }
    }

    /// The model work an import does after its document is saved (5.7): the RAPTOR-lite overview, the
    /// content tags and the suggested questions. None of it is needed to search or answer from the
    /// document. Through 5.6 the overview and the tags ran before the save, so iOS ending a background
    /// import during them stopped it before its document was recorded.
    private func enrichImportedDocument(
        _ document: Document,
        chunks documentChunks: [DocumentChunk],
        container: KnowledgeContainer?,
        embeddingService containerEmbeddingService: EmbeddingService,
        db: VectorDatabase,
        context: IngestionContext,
        trackingId: UUID?,
        containerId activeContainerId: UUID
    ) async {
        let filename = document.filename
        let chunkTexts = documentChunks.map(\.content)

        // Step 4.5: Generate document summary (RAPTOR-lite)
        // Creates a level-1 summary chunk for efficient overview queries
        // Controlled by settings.enableDocumentSummaries
        // Skipped for onboarding samples. This is a language-model call with a 12s
        // timeout (`DocumentSummaryService.summaryGenerationTimeoutSeconds`) and it
        // runs once per document. Together with content tagging below, it was the
        // reason importing three small curated markdown files took **1.3 minutes** on
        // an A18 Pro: 3,168 words and 38 chunks, of which the embedding work is a
        // fraction of a second and the enrichment is up to 20s per document.
        //
        // The samples exist to demonstrate the pipeline, and the theater the user is
        // watching shows Extract, Chunk, Embed and Index. An auto-generated overview
        // of a document the app itself wrote adds nothing to that, and a first
        // impression that takes over a minute costs more than the summary is worth.
        // Anything the user imports themselves is unaffected.
        let summariesEnabled =
            await MainActor.run { self.settingsStore?.enableDocumentSummaries ?? true }
            && context != .onboarding

        if summariesEnabled {
            await MainActor.run {
                updateIngestionItem(
                    id: trackingId,
                    filename: filename,
                    stage: .storing,
                    detail: "Optimizing overview...",
                    progress: 0.98
                )
            }

            do {
                let summaryChunk = try await documentSummaryService.generateDocumentSummary(
                    documentId: document.id,
                    documentName: filename,
                    chunks: documentChunks,
                    embeddingService: containerEmbeddingService,
                    embeddingTranslationTarget: translationTargetLanguage(for: container)
                )

                // The overview takes up to 12 s to write, and the document can be deleted meanwhile
                // (`enrichmentTargetState`, 5.7).
                if await enrichmentTargetState(document.id) != .listed {
                    Log.info(
                        "[RAGService] Not storing the overview of '\(filename)': the document was deleted while it was written",
                        category: .ingestion)
                } else {
                    // Store the summary chunk alongside detail chunks
                    try await db.storeBatch(chunks: [summaryChunk])
                    try await db.persist()

                    if await enrichmentTargetState(document.id) == .removalStarted {
                        // The deletion began while the overview was stored and may have taken the document's
                        // passages out before it, so the overview is taken out here.
                        do {
                            try await db.deleteChunks(forDocument: document.id)
                            Log.info(
                                "[RAGService] Took out the overview of '\(filename)': the document was deleted while it was stored",
                                category: .ingestion)
                        } catch {
                            Log.error(
                                "[RAGService] Could not take out the overview of '\(filename)', whose document was deleted while it was stored: \(error.localizedDescription)",
                                category: .ingestion)
                        }
                    } else {
                        TelemetryCenter.emit(
                            .ingestion,
                            title: "Document summary generated",
                            metadata: [
                                "file": filename,
                                "summaryWords": "\(summaryChunk.metadata.wordCount)",
                                "abstractionLevel": "L1",
                            ]
                        )

                        Log.info("[RAGService] RAPTOR-lite: Generated L1 summary for '\(filename)'", category: .ingestion)
                    }
                }
            } catch {
                // Summary generation is optional - log but don't fail ingestion
                Log.warning(
                    "[RAGService] Summary generation failed for '\(filename)': \(error)", category: .ingestion)
                TelemetryCenter.emit(
                    .ingestion,
                    severity: .warning,
                    title: "Summary generation skipped",
                    metadata: [
                        "file": filename,
                        "error": error.localizedDescription,
                    ]
                )
            }
        } else {
            Log.debug("[RAGService] Document summaries disabled in settings, skipping", category: .ingestion)
        }


        // Step 5: Generate content tags using Apple's content tagging model (iOS 26+)
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .storing,
                detail: "Generating tags...",
                progress: 0.99
            )
        }

        var generatedContentTags: [String]?
        // Skipped for onboarding samples, same reasoning as the summary above: this is
        // a language-model call with an 8s timeout, once per document.
        let contentTaggingEnabled =
            await contentTaggingEnabled(for: container)
            && context != .onboarding
        if #available(iOS 26.0, *), contentTaggingEnabled {
            let taggingService = ContentTaggingService.shared
            if taggingService.isAvailable {
                do {
                    let tags = try await taggingService.generateTagsForDocument(
                        chunks: chunkTexts,
                        documentName: filename
                    )
                    if !tags.displayTags.isEmpty {
                        generatedContentTags = tags.displayTags
                        TelemetryCenter.emit(
                            .generation,
                            title: "Content tags generated",
                            metadata: [
                                "file": filename,
                                "tags": tags.displayTags.joined(separator: ", "),
                                "count": "\(tags.displayTags.count)",
                            ]
                        )
                    }
                } catch {
                    Log.warning("[RAGService] Content tagging failed for \(filename): \(error)", category: .llm)
                }
            }
        }

        if let tags = generatedContentTags {
            await MainActor.run {
                if let index = documents.firstIndex(where: { $0.id == document.id }) {
                    let saved = documents[index]
                    documents[index] = Document(
                        id: saved.id,
                        filename: saved.filename,
                        fileURL: saved.fileURL,
                        storageRelativePath: saved.storageRelativePath,
                        fileHash: saved.fileHash,
                        contentType: saved.contentType,
                        addedAt: saved.addedAt,
                        totalChunks: saved.totalChunks,
                        processingMetadata: saved.processingMetadata,
                        containerId: saved.containerId,
                        contentTags: tags
                    )
                }
            }
            await saveDocumentsToDisk()
        }

        // Generate suggested questions for the document
        await MainActor.run {
            updateIngestionItem(
                id: trackingId,
                filename: filename,
                stage: .storing,
                detail: "Generating suggested questions...",
                progress: 0.99
            )
        }
        guard await enrichmentTargetState(document.id) == .listed else {
            Log.info(
                "[RAGService] No suggested questions for '\(filename)': the document was deleted after its import",
                category: .ingestion)
            return
        }
        await SuggestedQuestionsService.shared.generateQuestionsForIngestedDocument(
            document,
            chunks: documentChunks,
            in: activeContainerId
        )
        if await enrichmentTargetState(document.id) == .removalStarted {
            await SuggestedQuestionsService.shared.removeQuestions(for: document.id, in: activeContainerId)
        }
    }

    /// Where a document stands for the model work that follows its import (5.7), which takes seconds per step:
    /// listed (in the list, or out of it for its undo seconds), recorded as deleted, which `removeDocument` and
    /// `clearAllDocuments` do before they take anything out, or neither. Since that work moved after the document
    /// is saved (2026-10-15, during 5.7), a document deleted while its overview was written kept that overview as
    /// a passage of no document, and later answers cited it as "Unknown Document Summary" (seen in the iOS 27
    /// Simulator on 2026-10-19, `ShortcutsActionTests`); no release had it. What a step makes is stored only for a
    /// listed document, and taken out again when the deletion began while it was stored. A document in its undo
    /// seconds gets its overview and questions: an Undo brings it back with them, and a removal that runs takes them
    /// out with the rest (review, 2026-10-19).
    enum EnrichmentTargetState: Equatable { case listed, unlisted, removalStarted }

    private func enrichmentTargetState(_ id: UUID) async -> EnrichmentTargetState {
        let url = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        if let data = try? Data(contentsOf: url), let ids = try? JSONDecoder().decode([String].self, from: data),
            ids.contains(id.uuidString)
        {
            return .removalStarted
        }
        let listed = await MainActor.run { self.documents.contains { $0.id == id } || self.isRemovalPending(id) }
        return listed ? .listed : .unlisted
    }

    /// Whether a saved document's overview, tags and suggested questions wait instead of running before the next
    /// file (5.7 in the background; 5.8 also while other files are queued). An onboarding sample never waits: its
    /// overview is skipped altogether.
    nonisolated static func shouldDeferEnrichment(
        appIsInBackground: Bool, otherFilesQueued: Bool, isOnboarding: Bool
    ) -> Bool {
        !isOnboarding && (appIsInBackground || otherFilesQueued)
    }

    /// Waits while the app is in the background, and returns how long it waited (5.8). A model call that
    /// iOS refuses there goes on when the app is opened; a suspended app's wait simply pauses. Waiters are
    /// counted, so the answer reads as paused until the last of them goes on.
    @MainActor static func waitWhileAppIsInBackground() async -> TimeInterval {
        let started = Date()
        guard appIsInBackground else { return 0 }
        backgroundWaiters += 1
        if backgroundWaiters == 1 {
            // The answer's Live Activity and the system's task card say "Paused, tap to resume" while it waits.
            NotificationCenter.default.post(name: answerPausedNotification, object: nil, userInfo: ["paused": true])
        }
        while appIsInBackground, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
        backgroundWaiters -= 1
        if backgroundWaiters == 0 {
            NotificationCenter.default.post(name: answerPausedNotification, object: nil, userInfo: ["paused": false])
        }
        return Date().timeIntervalSince(started)
    }

    @MainActor private static var backgroundWaiters = 0

    /// Posted with `["paused": Bool]` when an answer starts and stops waiting for the app to come back (5.8).
    nonisolated static let answerPausedNotification = Notification.Name("OpenIntelligence.answerPausedForBackground")

    /// Whether the app is in the background, where iOS ends an import that stalls (5.7).
    @MainActor static var appIsInBackground: Bool {
        #if canImport(UIKit)
            UIApplication.shared.applicationState == .background
        #else
            false
        #endif
    }

    /// Documents whose overview, tags and suggested questions wait for the app to be in front (5.7),
    /// each as "<library id> <document id>".
    nonisolated static let deferredEnrichmentKey = "deferredDocumentEnrichment"

    nonisolated static func deferredEnrichments(defaults: UserDefaults = .standard) -> [(document: UUID, library: UUID)] {
        (defaults.stringArray(forKey: deferredEnrichmentKey) ?? []).compactMap { entry in
            let parts = entry.split(separator: " ")
            guard parts.count == 2, let library = UUID(uuidString: String(parts[0])),
                let document = UUID(uuidString: String(parts[1]))
            else { return nil }
            return (document, library)
        }
    }

    nonisolated static func deferEnrichment(
        of document: UUID, in library: UUID, defaults: UserDefaults = .standard
    ) {
        let entry = "\(library.uuidString) \(document.uuidString)"
        var entries = defaults.stringArray(forKey: deferredEnrichmentKey) ?? []
        guard !entries.contains(entry) else { return }
        entries.append(entry)
        defaults.set(entries, forKey: deferredEnrichmentKey)
    }

    nonisolated static func finishDeferredEnrichment(of document: UUID, defaults: UserDefaults = .standard) {
        let entries = (defaults.stringArray(forKey: deferredEnrichmentKey) ?? []).filter {
            !$0.hasSuffix(document.uuidString)
        }
        defaults.set(entries, forKey: deferredEnrichmentKey)
    }

    /// Runs the model work background imports left for later, one document at a time, while the app
    /// is in front and no import is running (5.7). Called when the app comes to the front and when the
    /// import queue empties. A document deleted in the meantime is dropped from the list.
    @MainActor
    func runDeferredEnrichmentsIfNeeded() {
        guard !deferredEnrichmentIsRunning, !isProcessing, !Self.appIsInBackground else { return }
        let pending = Self.deferredEnrichments()
        guard !pending.isEmpty else { return }
        deferredEnrichmentIsRunning = true
        Task { @MainActor in
            defer {
                deferredEnrichmentIsRunning = false
                if !isProcessing { processingStatus = "" }
            }
            for item in pending {
                guard !Self.appIsInBackground, !isProcessing else { return }
                guard let document = documents.first(where: { $0.id == item.document }) else {
                    Self.finishDeferredEnrichment(of: item.document)
                    continue
                }
                let container = containerService.containers.first { $0.id == item.library }
                guard let db = try? await dbForContainer(item.library),
                    let stored = try? await db.chunks(forDocument: document.id), !stored.isEmpty
                else { continue }
                let chunks = stored.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
                let service = EmbeddingService.forProvider(
                    id: container?.embeddingProviderId ?? "coreml_sentence_embedding",
                    targetDimension: container?.embeddingDim ?? 384,
                    allowFallback: true)
                Log.info(
                    "[RAGService] Adding the overview, tags and suggested questions that waited for '\(document.filename)'",
                    category: .ingestion)
                let enrichmentStarted = Date()
                VerificationJournal.record(
                    "import.deferredEnrichment", .started, ["document": VerificationJournal.anon(document.id)])
                await enrichImportedDocument(
                    document, chunks: chunks, container: container, embeddingService: service, db: db,
                    context: .userInitiated, trackingId: nil, containerId: item.library)
                Self.finishDeferredEnrichment(of: document.id)
                VerificationJournal.record(
                    "import.deferredEnrichment", .ok, durationMs: Date().timeIntervalSince(enrichmentStarted) * 1000,
                    ["document": VerificationJournal.anon(document.id),
                        "tags": "\(documents.first { $0.id == document.id }?.contentTags?.count ?? 0)"])
            }
        }
    }

    private func prepareManagedDocumentURL(from url: URL) throws -> URL {
        if let relativePath = AppSupportPaths.relativePath(for: url) {
            return AppSupportPaths.documentURL(forRelativePath: relativePath)
        }

        let destinationURL = AppSupportPaths.nextAvailableImportedDocumentURL(preferredFileName: url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
        }
        return destinationURL
    }

    /// The embedding service a library's fingerprint describes: the same one
    /// `resolveEmbeddingContext` embeds and compares with.
    private func fingerprintService(for container: KnowledgeContainer) -> EmbeddingService {
        if embeddingServiceWasInjected, embeddingService.outputDimension == container.embeddingDim {
            return embeddingService
        }
        return EmbeddingService.forProvider(
            id: container.embeddingProviderId,
            targetDimension: container.embeddingDim,
            allowFallback: true
        )
    }

    @MainActor
    /// Records the fingerprint of the pipeline that just wrote a container's vectors.
    ///
    /// Call only when the vector store was empty immediately before the write, so every vector in
    /// it demonstrably came from the current pipeline. Never overwrites an existing fingerprint: a
    /// store that already held vectors may hold two populations, and that is exactly the case the
    /// staleness check exists to flag.
    func stampEmbeddingFingerprintIfAbsent(for containerId: UUID) {
        guard var container = containerService.containers.first(where: { $0.id == containerId }),
            container.embeddingFingerprint == nil
        else { return }

        // The fingerprint has to describe the service this library embeds with, the one
        // `resolveEmbeddingContext` builds from the library's own provider. Through 5.5 this read
        // the app's default service, which is Core ML, so a library on Core AI was recorded under
        // the Core ML identity and its first question found a different live fingerprint. On the
        // owner's iPhone on 2026-10-07 the two values in the log (69f06c6c23035978 recorded,
        // 3236a5aa2cfabb78 live) are exactly the Core ML and the Core AI fingerprints.
        let service = fingerprintService(for: container)
        container.embeddingFingerprint = EmbeddingFingerprint.compute(
            providerId: service.actualProviderId,
            dimension: service.outputDimension,
            maxSequenceLength: service.maxSafeTokens,
            poolingRecipe: service.poolingRecipe,
            modelRevision: service.modelRevision,
            chunkerRecipe: EmbeddingFingerprint.chunkerRecipe(for: container.chunkingDirective)
        )
        containerService.updateContainer(container)
        Log.info(
            "[RAGService] Recorded embedding fingerprint for newly built container \(containerId); "
                + "its vectors were written by the current pipeline.",
            category: .embedding
        )
    }

    /// Why a rebuild has nothing to do. The three cases were reported identically, and that
    /// is the defect this row is named for.
    enum RebuildSelection: Equatable {
        /// There is work to do.
        case rebuild(count: Int)
        /// The library genuinely holds no documents. A real no-op.
        case libraryEmpty
        /// The library HAS documents and every one was excluded by an in-flight ingestion
        /// item. Returning normally here told the caller the repair succeeded, so it logged
        /// success, took the rebuild banner down having rebuilt nothing, and the next health
        /// check re-flagged the library. That cycle does not terminate, and deleting the
        /// library was the only way out of it.
        case blockedByQueue(blocked: Int)
    }

    /// URLs an in-flight ingestion is already working on, which a rebuild must not duplicate.
    ///
    /// `isTerminal` is the whole correctness of this. Built from every item regardless of
    /// stage, a finished `.complete` entry vetoed its own document forever — and because
    /// `pruneCompletedIngestionItems` bails whenever any item is non-terminal, one stuck
    /// `.paused` entry pinned every completed entry in the array, each of which then blocked
    /// its own document's repair.
    nonisolated static func blockingIngestionURLs(in items: [IngestionItem]) -> Set<URL> {
        Set(items.filter { !$0.stage.isTerminal }.map(\.url))
    }

    /// The documents a rebuild of `targetContainerId` should re-embed.
    ///
    /// Extracted as `nonisolated static` because it is the only part of the blocked-rebuild
    /// defect provable without hardware. Everything else about that failure needs a device
    /// with a stuck ingestion queue; this is pure selection over values.
    nonisolated static func documentsEligibleForRebuild(
        in documents: [Document],
        targetContainerId: UUID,
        blockingURLs: Set<URL>,
        fallbackContainerId: UUID?
    ) -> [Document] {
        documents.filter { document in
            // Prevent duplicate extraction pipelines if the item is already queued or paused.
            if blockingURLs.contains(document.fileURL) { return false }
            if let docContainer = document.containerId {
                return docContainer == targetContainerId
            } else if let fallbackId = fallbackContainerId {
                return fallbackId == targetContainerId
            }
            return false
        }
    }

    /// Classifies an empty rebuild, so a vetoed one is never mistaken for a completed one.
    nonisolated static func classifyRebuild(
        eligible: [Document],
        documentsInLibrary: Int
    ) -> RebuildSelection {
        if !eligible.isEmpty { return .rebuild(count: eligible.count) }
        return documentsInLibrary > 0 ? .blockedByQueue(blocked: documentsInLibrary) : .libraryEmpty
    }

    func localIndexSyncFingerprint(for documents: [Document]) -> String {
        documents
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { document in
                let containerComponent = document.containerId?.uuidString ?? "none"
                let pathComponent = document.storageRelativePath ?? document.filename
                let hashComponent = document.fileHash ?? "nohash"
                let addedAtComponent = String(format: "%.0f", document.addedAt.timeIntervalSince1970)
                return
                    "\(document.id.uuidString)|\(containerComponent)|\(document.totalChunks)|\(pathComponent)|\(hashComponent)|\(addedAtComponent)"
            }
            .joined(separator: ";")
    }

    /// Decide whether a library can answer semantically, and surface it if not.
    ///
    /// A library holding documents whose vector store has no chunks cannot do
    /// semantic retrieval at all. Keyword search still works, so the failure is
    /// invisible: the library lists its documents and the app answers "I couldn't
    /// find information about that in your documents" for topics the document
    /// plainly covers.
    ///
    /// This runs on container switch because that is where the truth is cheaply
    /// available and where the user is about to ask something. The previous
    /// surfacing hung off `enqueueSelfHealingRebuild`, which is only reached when
    /// ingestion-time detection fires — so a library that arrived in this state by
    /// any other route stayed silent. Device evidence 2026-08-03: Library 3 sat
    /// with 239 chunks in FTS5 and no vector store across an entire session, and
    /// `enqueueSelfHealingRebuild` was never called once.
    @MainActor
    func evaluateSemanticIndexHealth(for containerId: UUID) async {
        let documentCount = documentsForContainer(containerId).count
        guard documentCount > 0 else {
            librariesNeedingIndexRebuild.remove(containerId)
            return
        }

        guard let container = containerService.containers.first(where: { $0.id == containerId }) else {
            return
        }

        // Read the store rather than the container's cached `totalChunks`. The
        // cached figure is what said 420 while the vector store held none — it
        // counts what was ingested, not what is searchable.
        //
        // A read failure is treated as "not proven missing", the same rule the
        // ingestion check uses. Claiming a library is broken because a read threw
        // would be the third variant today of trusting a failed read as evidence.
        let indexedChunkCount: Int
        do {
            indexedChunkCount = try await vectorRouter.db(for: container).count()
        } catch {
            Log.warning(
                "[RAGService] Could not read the vector store for library \(containerId) while checking index health: \(error.localizedDescription). Not flagging it.",
                category: .vectorDB
            )
            return
        }

        if indexedChunkCount == 0 {
            VerificationJournal.record(
                "index.health", .failed,
                ["library": VerificationJournal.anon(containerId), "result": "emptyStore",
                    "documents": "\(documentCount)", "passages": "0"])
            if !librariesNeedingIndexRebuild.contains(containerId) {
                Log.warning(
                    "[RAGService] Library \(containerId) holds \(documentCount) document(s) but its vector store has 0 chunks. Semantic retrieval cannot work here; repairing.",
                    category: .vectorDB
                )
                librariesNeedingIndexRebuild.insert(containerId)
            }

            // Repair it, do not merely flag it.
            //
            // This branch used to insert into `librariesNeedingIndexRebuild` and stop. That set has
            // exactly one reader in the whole app — the banner in `DocumentLibraryView` — so a
            // library detected as broken while the user was in Chat stayed broken until they
            // happened to visit the Documents tab and notice a banner. Observed on device
            // 2026-08-20: the detector logged this line, the query returned
            // `Fused 0 results into 0 unique chunks`, and no self-healing line appears anywhere in
            // the capture, because nothing enqueued one. The owner reported no banner and no repair.
            //
            // `enqueueSelfHealingRebuild` is the right call to make unconditionally here: it is
            // idempotent (guards on suppression, on `pendingSelfHealingContainerIds`, on an
            // already-queued ingestion item, and on a running task), and when self-healing is
            // suppressed by an earlier user dismissal it re-publishes the flag rather than
            // repairing — which is exactly the intended behaviour for a user who said no.
            //
            // Called on every evaluation rather than only on the first flag, because a library
            // already flagged in a previous session would otherwise return early forever and never
            // attempt the repair at all.
            enqueueSelfHealingRebuild(for: containerId)
        } else {
            await checkVectorsAndDocuments(of: container, passageCount: indexedChunkCount)
        }
    }

    /// The two ways a library whose store holds passages still can't be searched by meaning (5.7).
    ///
    /// Its vectors are empty: a model that returned zeros for every passage built a library that
    /// read as healthy (row "A library is built from all-zero vectors when the embedding model
    /// fails"; seen in the iOS 27 Simulator on 2026-10-08, 127 of 127 vectors zero). A sample of the
    /// vectors decides it; a real vector is never all zeros.
    ///
    /// A listed document has no passages: the owner's backup of 2026-09-10 held a document of 455
    /// passages with none in the store and none in the keyword index, so it could not be found at
    /// all, and this check looked only at whether the whole store was empty. A document whose import
    /// hasn't finished is skipped, since an import saves its passages before its record only for
    /// small files.
    ///
    /// Either one starts the same repair as an empty store, limited to the documents that need it,
    /// once a launch; a repair that didn't take leaves the rebuild banner up.
    @MainActor
    private func checkVectorsAndDocuments(of container: KnowledgeContainer, passageCount: Int) async {
        let containerId = container.id
        let db = vectorRouter.db(for: container)

        let sample = await db.getEmbeddings(forIndices: Self.sampleIndices(count: passageCount))
        if Self.vectorsLookEmpty(sample) {
            Log.warning(
                "[RAGService] Library \(containerId): \(EmbeddingVectorCheck.unusableCount(sample)) of \(sample.count) "
                    + "sampled vectors are empty, so it can't be searched by meaning; re-embedding it.",
                category: .ingestion)
            VerificationJournal.record(
                "index.health", .failed,
                ["library": VerificationJournal.anon(containerId), "result": "emptyVectors",
                    "passages": "\(passageCount)"])
            librariesNeedingIndexRebuild.insert(containerId)
            let key = "vectors:\(containerId.uuidString)"
            if !indexRepairsTriedThisLaunch.contains(key) {
                indexRepairsTriedThisLaunch.insert(key)
                enqueueSelfHealingRebuild(for: containerId)
            }
            return
        }

        let records: [PassageRecord]
        do {
            records = try await db.passageRecords()
        } catch {
            // Not proven missing, the same rule as the count above.
            librariesNeedingIndexRebuild.remove(containerId)
            return
        }
        var passagesByDocument: [UUID: Int] = [:]
        for record in records {
            passagesByDocument[record.documentId, default: 0] += 1
        }
        let eligible = Self.documentsEligibleForRebuild(
            in: documents,
            targetContainerId: containerId,
            blockingURLs: Self.blockingIngestionURLs(in: ingestionItems),
            fallbackContainerId: containerService.containers.first?.id)
        let missing = Self.documentsMissingPassages(eligible, passagesByDocument: passagesByDocument)
        VerificationJournal.record(
            "index.health", missing.isEmpty ? .ok : .failed,
            ["library": VerificationJournal.anon(containerId), "result": missing.isEmpty ? "healthy" : "missingPassages",
                "documents": "\(eligible.count)", "passages": "\(passageCount)", "missing": "\(missing.count)"])
        guard !missing.isEmpty else {
            librariesNeedingIndexRebuild.remove(containerId)
            return
        }
        Log.warning(
            "[RAGService] Library \(containerId): \(missing.count) document(s) have no passages in the store, "
                + "so search can't find them: \(missing.map(\.filename).joined(separator: ", ")). Rebuilding those.",
            category: .ingestion)
        librariesNeedingIndexRebuild.insert(containerId)
        let untried = missing.filter { !indexRepairsTriedThisLaunch.contains("document:\($0.id.uuidString)") }
        guard !untried.isEmpty else { return }
        for document in untried {
            indexRepairsTriedThisLaunch.insert("document:\(document.id.uuidString)")
        }
        enqueueSelfHealingRebuild(for: containerId, onlyDocuments: Set(untried.map(\.id)))
    }

    /// The stored vectors of the candidates that came without one, by passage id, for MMR (5.7).
    ///
    /// The store hands passages back without their vectors, so through 5.6 MMR compared empty
    /// vectors, found every pair 0 alike and kept passages in score order whatever λ said, in every
    /// mode, while Settings said MMR diversified. A passage from another library, or one whose vector
    /// is empty, gets none and counts as unlike everything, as before.
    func storedVectors(for candidates: [RetrievedChunk], in containerId: UUID) async -> [UUID: [Float]] {
        let ids = candidates.filter { $0.chunk.embedding.isEmpty }.map(\.chunk.id)
        guard !ids.isEmpty else { return [:] }
        let vectors = await dbFor(containerId).getEmbeddings(forChunkIDs: ids)
        var byId: [UUID: [Float]] = [:]
        for (id, vector) in zip(ids, vectors) where EmbeddingVectorCheck.isUsable(vector) {
            byId[id] = vector
        }
        return byId
    }

    /// Whether a word of a question, or of a line of evidence, counts when lines are matched to the
    /// question: three characters or more, or a two-character code that mixes letters and digits
    /// ("E1", "F2", "3D") (5.7).
    ///
    /// Through 5.6 every word of two characters was dropped, so in "What does E1 mean on the air
    /// fryer?" the one word that names the answer never counted, and the lines picked for the answer
    /// were the ones about the air fryer in general. The sample library's air fryer answer was wrong
    /// on 2026-10-01 and again on real vectors on 2026-10-08 (row "Wrong answers from the sample
    /// library"); this is the likely cause, not yet confirmed on a device.
    nonisolated static func isEvidenceKeyword(_ word: some StringProtocol) -> Bool {
        if word.count > 2 { return true }
        guard word.count == 2 else { return false }
        return word.contains(where: \.isLetter) && word.contains(where: \.isNumber)
    }

    /// Evenly spread positions in a store of `count` passages, at most `limit` of them.
    nonisolated static func sampleIndices(count: Int, limit: Int = 64) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        let taken = min(count, limit)
        return (0..<taken).map { $0 * count / taken }
    }

    /// True when a sample of a store's vectors says the model failed for the library: at least nine
    /// in ten unusable, out of a sample of at least eight (or the whole store, if smaller).
    nonisolated static func vectorsLookEmpty(_ sample: [[Float]]) -> Bool {
        guard !sample.isEmpty else { return false }
        let unusable = EmbeddingVectorCheck.unusableCount(sample)
        return unusable * 10 >= sample.count * 9
    }

    /// Listed documents that had passages when they were imported and have none in the store now.
    nonisolated static func documentsMissingPassages(
        _ documents: [Document], passagesByDocument: [UUID: Int]
    ) -> [Document] {
        documents.filter { $0.totalChunks > 0 && (passagesByDocument[$0.id] ?? 0) == 0 }
    }

    /// A readable snapshot of a library's index state, for the trace a user shares from a response.
    ///
    /// Everything here is invisible in a shared capture today. `Log`'s `.vectorDB` category is not
    /// in `fileLogCategories`, so the one line separating "retrieval found nothing relevant" from
    /// "this library has no vectors at all" only ever reaches an attached Xcode console. Three open
    /// defects are told apart by exactly that distinction, and all three are device-only.
    ///
    /// Reports the ingested and the searchable chunk counts side by side rather than choosing one.
    /// `container.totalChunks` counts what ingestion believed it wrote; `count()` counts what
    /// retrieval can actually reach. The divergence is the defect signature itself — a library once
    /// reported 420 against a vector store holding none.
    ///
    /// Deliberately side-effect free. It does not route through `resolveEmbeddingContext`, which
    /// flags and can wipe a store, and it does not mutate `librariesNeedingIndexRebuild`. Sharing a
    /// trace has to observe the system without changing it, or the next capture describes the act
    /// of capturing.
    @MainActor
    func libraryStateTraceBlock(for containerId: UUID) async -> String {
        guard let container = containerService.containers.first(where: { $0.id == containerId }) else {
            return "  Container \(containerId.uuidString) is not registered; it may have been deleted."
        }

        let documentCount = documentsForContainer(containerId).count
        var lines: [String] = [
            "  Library:             \(container.name)",
            "  Container:           \(container.id.uuidString)",
            "  Documents:           \(documentCount)",
            "  Chunks (ingested):   \(container.totalChunks)",
        ]

        // A failed read is reported as unknown, never as zero. Treating a failed read as evidence
        // of an empty store is a mistake this file has already made.
        var searchableChunks: Int?
        do {
            let count = try await vectorRouter.db(for: container).count()
            searchableChunks = count
            lines.append("  Chunks (searchable): \(count)")
        } catch {
            lines.append("  Chunks (searchable): UNREADABLE - \(error.localizedDescription)")
        }

        if documentCount > 0, searchableChunks == 0 {
            lines.append("  >> This library holds documents and zero searchable chunks.")
            lines.append("     Semantic retrieval cannot work here, whatever the query was.")
        }

        lines.append("  Rebuild flagged:     \(librariesNeedingIndexRebuild.contains(containerId) ? "YES" : "no")")

        let snapshotService = fingerprintService(for: container)
        let liveFingerprint = EmbeddingFingerprint.compute(
            providerId: snapshotService.actualProviderId,
            dimension: snapshotService.outputDimension,
            maxSequenceLength: snapshotService.maxSafeTokens,
            poolingRecipe: snapshotService.poolingRecipe,
            modelRevision: snapshotService.modelRevision,
            chunkerRecipe: EmbeddingFingerprint.chunkerRecipe(for: container.chunkingDirective)
        )
        lines.append("  Fingerprint stored:  \(container.embeddingFingerprint ?? "none recorded")")
        lines.append("  Fingerprint live:    \(liveFingerprint)")

        if let stored = container.embeddingFingerprint, stored != liveFingerprint {
            lines.append("  >> The embedding pipeline changed after these vectors were written.")
            lines.append("     They are valid and searchable but stale.")
        } else if container.embeddingFingerprint == nil {
            lines.append("  >> No fingerprint recorded, so a pipeline change cannot be detected for")
            lines.append("     this library. It adopts the current one silently on the next check,")
            lines.append("     which is why an absent flag is not evidence that nothing changed.")
        }

        return lines.joined(separator: "\n")
    }

    /// Rebuild a library's semantic index and re-arm automatic repair for it.
    ///
    /// Deliberately clears suppression first. A user asking for a rebuild is
    /// unambiguously asking for this library to be repaired, which also revokes
    /// whatever earlier dismissal disarmed it — otherwise the library would fall
    /// back into the same silent state the next time its vectors went missing.
    @MainActor
    func rebuildSemanticIndex(for containerId: UUID) {
        clearSelfHealingSuppression(for: containerId)
        librariesNeedingIndexRebuild.remove(containerId)
        Log.info(
            "[RAGService] Manual index rebuild requested for container \(containerId); automatic self-healing re-armed.",
            category: .ingestion
        )
        enqueueSelfHealingRebuild(for: containerId)
    }

    @MainActor
    private func enqueueSelfHealingRebuild(for containerId: UUID, onlyDocuments: Set<UUID>? = nil) {
        guard !isSelfHealingSuppressed(for: containerId) else {
            // Suppressed, and previously that meant silently giving up: the
            // library kept its documents, kept its text index, and permanently
            // lost semantic retrieval with nothing surfaced to the user.
            //
            // Suppression is set by declining a queue prompt (discard, stop,
            // pause, cancel). While the phantom "resume interrupted import?"
            // prompts were firing, every correct dismissal silently disarmed the
            // repair for that library. Device evidence 2026-08-03: Library 3 had
            // 239 chunks in FTS5, no vector store, and answered "your documents
            // don't cover this" for a topic its own tool call found 45 chunks of.
            //
            // Publish it instead so the library can show a rebuild action.
            Log.warning(
                "[RAGService] Container \(containerId) needs an index rebuild but automatic self-healing is suppressed after a user dismissal. Surfacing a manual rebuild instead of giving up silently.",
                category: .ingestion
            )
            librariesNeedingIndexRebuild.insert(containerId)
            return
        }
        guard !pendingSelfHealingContainerIds.contains(containerId) else {
            // Already waiting: a whole-library repair covers any documents; two limited ones join.
            if let onlyDocuments, let waiting = selfHealingDocumentIds[containerId] {
                selfHealingDocumentIds[containerId] = waiting.union(onlyDocuments)
            } else {
                selfHealingDocumentIds[containerId] = nil
            }
            return
        }
        // Any rebuild of the library under way, not only a self-healing one (5.8): a rebuild leaves each document listed
        // with its passages cleared until it is re-imported, so a sync pass meanwhile finds the store empty and asked
        // for a second rebuild of the same library (review, 2026-11-03).
        let alreadyQueued = ingestionItems.contains { item in
            item.containerId == containerId && !item.stage.isTerminal && item.metrics.isRebuild
        }
        guard !alreadyQueued else { return }

        selfHealingDocumentIds[containerId] = onlyDocuments
        pendingSelfHealingContainerIds.append(containerId)
        guard selfHealingRebuildTask == nil else { return }
        selfHealingRebuildTask = Task { @MainActor [weak self] in
            await self?.runPendingSelfHealingRebuilds()
        }
    }

    @MainActor
    private func runPendingSelfHealingRebuilds() async {
        defer { selfHealingRebuildTask = nil }
        while !pendingSelfHealingContainerIds.isEmpty {
            let containerId = pendingSelfHealingContainerIds.removeFirst()
            let onlyDocuments = selfHealingDocumentIds.removeValue(forKey: containerId)
            guard !isSelfHealingSuppressed(for: containerId) else { continue }
            do {
                try await reembedDocuments(
                    in: containerId,
                    reason: onlyDocuments == nil
                        ? "Self-healing: empty vector store" : "Self-healing: documents without passages",
                    onlyDocumentIds: onlyDocuments
                )
                if isSelfHealingSuppressed(for: containerId) {
                    Log.info(
                        "[RAGService] Self-healing rebuild stopped by user for container \(containerId)",
                        category: .ingestion
                    )
                    VerificationJournal.record(
                        "rebuild.selfHeal", .cancelled,
                        ["library": VerificationJournal.anon(containerId), "result": "stoppedByUser"])
                } else {
                    Log.info(
                        "[RAGService] Self-healing rebuild completed successfully for container \(containerId)",
                        category: .ingestion
                    )
                    // Repaired — take the banner down.
                    await MainActor.run {
                        self.librariesNeedingIndexRebuild.remove(containerId)
                    }
                    VerificationJournal.record(
                        "rebuild.selfHeal", .ok,
                        ["library": VerificationJournal.anon(containerId), "result": "rebuilt"])
                }
            } catch is CancellationError {
                Log.info(
                    "[RAGService] Self-healing rebuild cancelled for container \(containerId)",
                    category: .ingestion
                )
            } catch let error as RAGServiceError {
                // A blocked rebuild is not a failure to retry silently and it is not a success.
                // Put the banner back so the library keeps offering a manual rebuild, which is
                // the only thing that gets a user out of this state short of deleting the library.
                if case .rebuildBlockedByQueue(let blocked) = error {
                    await MainActor.run {
                        self.librariesNeedingIndexRebuild.insert(containerId)
                    }
                    VerificationJournal.record(
                        "rebuild.selfHeal", .failed,
                        ["library": VerificationJournal.anon(containerId), "result": "blockedByQueue",
                            "blocked": "\(blocked)"])
                    Log.warning(
                        "[RAGService] Self-healing rebuild for container \(containerId) was vetoed by the "
                            + "ingestion queue with \(blocked) document(s) present; surfacing a manual rebuild.",
                        category: .ingestion
                    )
                } else {
                    Log.error(
                        "[RAGService] Self-healing rebuild failed for container \(containerId): \(error.localizedDescription)",
                        category: .ingestion
                    )
                }
            } catch {
                Log.error(
                    "[RAGService] Self-healing rebuild failed for container \(containerId): \(error.localizedDescription)",
                    category: .ingestion
                )
            }
        }
    }

    func rebuildLocalSearchIndexesFromCanonicalState(documents: [Document]) async -> Bool {
        let snapshot = await MainActor.run {
            (self.containerService.containers, self.containerService.containers.first?.id)
        }
        let containers = snapshot.0
        let defaultContainerId = snapshot.1

        do {
            for container in containers {
                let containerDocuments = documents.filter { document in
                    (document.containerId ?? defaultContainerId) == container.id
                }
                guard !containerDocuments.isEmpty else { continue }

                let database = await MainActor.run { self.vectorRouter.db(for: container) }
                // Which documents the store holds is read from its records, and each document's
                // passages are read when its turn comes (5.7). Through 5.6 every passage of the
                // library was read first and held while its index was rebuilt.
                let storedRecords = try await database.passageRecords()

                // The guard below is about passages that can be read, and the records count one
                // that cannot. So passages are read, a batch at a time, until one comes back:
                // the first batch for any store in working order, and every batch only for a
                // store nothing can be read from, which is the case the guard is for.
                let holdsAReadablePassage = try await Self.holdsAReadablePassage(database, records: storedRecords)

                // Safety guard: If we have documents but the vector database returns 0 chunks,
                // do not wipe the existing FTS5 search index, as it would destroy the index.
                guard holdsAReadablePassage else {
                    Log.warning(
                        "[RAGService] Safety guard triggered: vector store is empty but container \(container.id) has \(containerDocuments.count) documents. Skipping FTS5 rebuild.",
                        category: .ingestion)

                    let containerId = container.id
                    Log.info(
                        "[RAGService] Queuing single-flight self-healing rebuild for container \(containerId)...",
                        category: .ingestion)
                    await MainActor.run {
                        // Surface it in the library the moment it is detected,
                        // whether or not the automatic rebuild is allowed to run.
                        // This is the point that reliably fires — device log
                        // 2026-08-03 shows it firing and the rebuild succeeding —
                        // so the banner belongs here rather than only inside
                        // `enqueueSelfHealingRebuild`, which is skipped entirely
                        // when self-healing is suppressed.
                        //
                        // `enqueueSelfHealingRebuild` clears the flag again on
                        // success, so a library that repairs itself shows the
                        // banner only briefly, and one that cannot keeps it.
                        self.librariesNeedingIndexRebuild.insert(containerId)
                        self.enqueueSelfHealingRebuild(for: containerId)
                    }
                    continue
                }

                await SQLiteFullTextService.shared.deleteContainer(containerId: container.id)
                await SQLiteFullTextService.shared.deleteChunksForContainer(containerId: container.id)

                let storedDocumentIDs = Set(storedRecords.map(\.documentId))

                // Clean up orphaned vector database chunks for documents no longer in the metadata catalog
                let containerDocIDs = Set(containerDocuments.map(\.id))
                for docID in storedDocumentIDs {
                    if !containerDocIDs.contains(docID) {
                        Log.info(
                            "[RAGService] Wiping orphaned vector database chunks for document \(docID) in container \(container.id)",
                            category: .ingestion)
                        VerificationJournal.record(
                            "sync.orphanWipe",
                            ["library": VerificationJournal.anon(container.id), "document": VerificationJournal.anon(docID)])
                        try? await database.deleteChunks(forDocument: docID)
                    }
                }

                for document in containerDocuments {
                    guard storedDocumentIDs.contains(document.id) else { continue }
                    // In store order, which is the order grouping every passage gave.
                    let unsortedChunks = try await database.chunks(forDocument: document.id)
                    guard !unsortedChunks.isEmpty else { continue }

                    let documentChunks = unsortedChunks.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
                    let fullText = documentChunks.map(\.content).joined(separator: "\n\n")
                    await SQLiteFullTextService.shared.store(
                        text: fullText, for: document.id, containerId: container.id)

                    let chunkPayload = documentChunks.map { chunk in
                        (
                            chunkIndex: chunk.metadata.chunkIndex,
                            pageNumber: chunk.metadata.pageNumber,
                            sectionTitle: chunk.metadata.sectionTitle,
                            sectionPath: chunk.metadata.sectionPath?.joined(separator: " > "),
                            structureType: chunk.metadata.structureType,
                            chunkType: chunk.metadata.chunkType?.rawValue,
                            tableTitle: chunk.metadata.tableTitle,
                            content: chunk.content,
                            structuredMetadata: Optional<SQLiteFullTextService.StructuredChunkMetadata>.none
                        )
                    }
                    await SQLiteFullTextService.shared.storeChunks(
                        documentId: document.id,
                        containerId: container.id,
                        chunks: chunkPayload
                    )

                    let pages = Dictionary(
                        grouping: documentChunks.compactMap { chunk -> (Int, String)? in
                            guard let pageNumber = chunk.metadata.pageNumber else { return nil }
                            return (pageNumber, chunk.content)
                        }, by: { $0.0 }
                    )
                    .map { pageNumber, contentPairs in
                        (
                            pageNumber: pageNumber,
                            content:
                                contentPairs
                                .sorted { $0.0 < $1.0 }
                                .map(\.1)
                                .joined(separator: "\n\n")
                        )
                    }
                    .sorted { $0.pageNumber < $1.pageNumber }

                    if !pages.isEmpty {
                        await SQLiteFullTextService.shared.storePages(
                            pages: pages,
                            for: document.id,
                            containerId: container.id
                        )
                    }
                }
            }

            return true
        } catch {
            Log.error(
                "[RAGService] Failed to rebuild local indexes from shared workspace: \(error.localizedDescription)",
                category: .ingestion)
            return false
        }
    }

}
