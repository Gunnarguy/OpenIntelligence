//
//  RAGService+ImportQueue.swift
//  OpenIntelligence
//
//  Part of RAGService, moved from RAGService+Import.swift on 2026-11-05 (5.8 split); only access keywords changed.
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
    func kickPendingReembedIfNeeded() {
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

}
