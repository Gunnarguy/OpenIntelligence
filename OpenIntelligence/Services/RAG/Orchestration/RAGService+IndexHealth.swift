//
//  RAGService+IndexHealth.swift
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
