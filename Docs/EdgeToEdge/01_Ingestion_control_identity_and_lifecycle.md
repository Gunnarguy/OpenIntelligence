# Module 01. Ingestion control, identity, and lifecycle

Nineteen concepts. This is the loading dock: how a file becomes a job that survives your phone killing the app, and how the app knows which job is which.

## The ladder

**Like you're five.** When you give the phone a paper, it writes a ticket for it and puts the ticket in a line. It does one ticket at a time. If the phone falls asleep in the middle, the ticket remembers how far it got, and next time it starts from there instead of the beginning.

**Like an idiot.** Importing a document is not one function call. It's a work order with a status: waiting, reading, cutting, embedding, filing, done. The work order is saved to disk the whole time, so a crash or a force-quit just means "resume from the last finished step." One document at a time, always. If you delete a document, that wins over any half-finished import that might try to bring it back.

**Like less of an idiot.** iOS suspends and kills apps whenever it wants. A 400-page scanned manual takes a long time to OCR. So ingestion is a persistent state machine: each queue item carries its stage, its progress, a checkpoint at page batches, a lease saying "someone is working on this," and a heartbeat proving the worker is alive. Content hashes make sure the same file isn't indexed twice. A stable document ID follows the document through checkpoints, rebuilds and sync so chunks always belong to the right parent. A tombstone records deletions so sync can't resurrect them.

**Average Joe.** Why one at a time? Because the parallelism you actually want is inside a document: pages OCR'd in parallel, embeddings in batches. Two big documents at once would double memory and heat for no throughput gain on a phone. Why leases and heartbeats instead of a simple "processing" flag? Because a flag stays true after a crash and the item is stranded forever. A lease expires; a heartbeat says "still alive, just slow."

**Dot-connector.** The order of persistence matters and it's the thing to remember. Document-level full text goes into the search database early, during extraction. Chunk rows and vectors arrive much later, after embedding. Nothing wraps those two writes in one transaction. So there's a window where a document is searchable at document level and absent from both chunk indexes. The restore path is what reconciles a crash in that window. Also: iOS 26 lets a user-initiated import keep running after you switch apps, with a short UIKit background task bridging the gap until the system scheduler picks it up.

**Expert.** `RAGService.enqueueDocuments` on the main actor creates `IngestionItem`s; `runIngestionLoop` pulls the next queued item and awaits `addDocument` before taking another. The stage enum in `IngestionItem.swift` has fourteen cases: queued, loading, transcribing, extracting, chunking, analyzing, adapting, reindexing, embedding, indexing, storing, complete, cancelled, failed. Items carry `leaseExpiresAt`, a heartbeat timestamp, file identity, errors and events, and are Codable to disk. iCloud placeholders wait up to 20 seconds to materialise. Files over 500 MB that cannot be streamed are rejected before reading. Progress is published to the Live Activity within 0.5 s. Five `BGTaskScheduler` identifiers are registered on iOS only.

**Expert's expert.** Two defects shaped this module. A paused import used to be restored showing zero pages, which made "remove" look safe when it was actually discarding real progress; fixed 2026-08-29 so restoration reports the preserved page count. And the sync layer once deleted an in-flight import's vector store because a library with zero documents in metadata was treated as proof its index was garbage; that is why deletion-wins, tombstones and the materialisation guard exist as separate mechanisms rather than one. The stage weights behind the progress bar are a real table, `pipelineStageWeights` in `IngestionItem.swift`: loading 0.05, transcribing 0.03, extracting 0.52, chunking 0.08, analyzing 0.08, adapting 0.04, reindexing 0.04, embedding 0.10, indexing 0.04, storing 0.02. Extraction is more than half the bar on purpose. The enum also carries a `paused` case beyond the fourteen the bank lists.

## Every concept

### Atomic ingestion commit (Core, verified in `RAGService` and `WorkspaceSyncService`)
- **Idiot:** the document doesn't "count" until all its pieces are ready.
- **Dot-connector:** the goal is that SQLite never says "chunks exist" while the vector file says "no vectors." Publish the consistent set, then make it visible.
- **Expert:** the vector store's `persist` is an atomic file swap and the FTS chunk insert is transactional, but there is no cross-store transaction; the atomic guarantee is per store, and the reconciliation on restore covers the gap. Read the bank's "only after the new set is ready" as intent, not as a two-phase commit.

### Background continued processing (Conditional, verified)
- **Idiot:** switching apps doesn't cancel your import.
- **Dot-connector:** iOS 26's `BGContinuedProcessingTask` lets a user-started job keep going in the background with a resource policy and a persisted status. Long OCR and Maximum queries should not die because you checked a text.
- **Expert:** `BackgroundTaskService`; identifiers for continued ingestion and continued query are registered at launch on iOS. It hands the same queue runner the same item; it does not change pipeline semantics.

### Cancellation tombstone (Core, verified)
- **Idiot:** a note that says "this one was deleted on purpose, don't bring it back."
- **Dot-connector:** without it, a sync merge sees a device that still has the file and helpfully restores it. The tombstone makes deletion durable across devices.
- **Expert:** written in `WorkspaceSyncService` at cancellation or deletion and applied before merged queue or inventory items are accepted.

### Checkpoint (Core, verified)
- **Idiot:** a bookmark. "I got to page 140."
- **Dot-connector:** written at page or batch boundaries so an interrupted 400-page PDF resumes at page 140, not page 1. Saves time, heat, and duplicate risk.
- **Expert:** written by `DocumentProcessor` in the streaming lane before the next batch starts; the restore path reads it together with the stage and the true page count.

### Content hash (Core, verified)
- **Idiot:** a fingerprint of the file's bytes.
- **Dot-connector:** lets the app say "seen this already" without trusting filenames, detect stale checkpoints, and build sync signatures.
- **Expert:** computed near import in `RAGService`; compared before extraction and before destructive sync in `WorkspaceSyncService`.

### Deduplication (Core, verified)
- **Idiot:** don't file the same thing twice.
- **Dot-connector:** duplicates waste storage and context, distort rank metrics, and make one source look more supported than it is. It happens at several layers with different identity rules.
- **Expert:** import (hash), vector merge (chunk ID), parent expansion (Jaccard token overlap around 0.8 in `ParentDocumentService`), and final evidence assembly.

### Deletion-wins policy (Core, verified)
- **Idiot:** if you deleted it, it stays deleted, even if another device still has a copy.
- **Dot-connector:** distributed replicas naturally resurrect files because someone always has the last full copy. The rule breaks that tie in favour of the explicit human action.
- **Expert:** applied during workspace and queue reconciliation in `WorkspaceSyncService` before files or vectors are copied.

### Deterministic UUID (Support, symbol not found under that name)
- **Idiot:** an ID you can recompute from the same input.
- **Dot-connector:** lets derived artefacts reconnect after reload without a server handing out identities.
- **Expert:** the bank anchors this to `RAGService`; no identifier named `deterministicUUID` or similar was found. Treat as a described technique, unverified as a named helper.

### Document enqueue (Core, verified)
- **Idiot:** dropping the file into the line instead of working on it right there in the button handler.
- **Dot-connector:** queueing is what makes an import cancellable, resumable and observable. A UI callback that blocks for five minutes is how apps get killed.
- **Expert:** `RAGService.enqueueDocuments` on the main actor; `IngestionItem` created per URL. First engine action after the file importer, camera bridge, SDK request or sample import.

### Foreground background-time fallback (Conditional, verified)
- **Idiot:** a short grace period so the import doesn't get chopped the instant you leave.
- **Dot-connector:** there is a gap between the app backgrounding and the system scheduler picking up the continued task. A short `UIApplication` background task bridges it.
- **Expert:** in `BackgroundTaskService`, between foreground execution and `BGContinuedProcessingTask` acquisition.

### Heartbeat (Core, verified)
- **Idiot:** "still here, still working."
- **Dot-connector:** distinguishes slow OCR from a dead worker whose lease should be reclaimed.
- **Expert:** a timestamp on `IngestionItem`, updated during long stages, checked on queue restore.

### Ingestion lease (Core, verified as `leaseExpiresAt`)
- **Idiot:** a "reserved" sign with an expiry time.
- **Dot-connector:** a plain boolean "processing" flag survives a crash and strands the item forever. A lease expires, so another run can safely take over.
- **Expert:** acquired before work, refreshed by heartbeats, evaluated during recovery. `leaseExpiresAt: Date?` on the item.

### Ingestion stage state machine (Core, verified, fourteen cases)
- **Idiot:** the list of steps a document goes through, in order.
- **Dot-connector:** explicit stages make failure diagnosable. "Failed at storing" and "failed at extracting" are different problems; a percentage can't tell you which.
- **Expert:** queued, loading, transcribing, extracting, chunking, analyzing, adapting, reindexing, embedding, indexing, storing, complete, cancelled, failed. Adapting and reindexing exist for the corpus-intelligence path that adjusts chunk settings and re-chunks.

### IngestionContext (Core, verified)
- **Idiot:** why this import is happening.
- **Dot-connector:** user-initiated, automatic rebuild, onboarding samples. Same machinery, different UI, retry and self-heal behaviour.
- **Expert:** attached before processing and carried beside the queue item in `RAGService`.

### IngestionItem (Core, verified)
- **Idiot:** the ticket.
- **Dot-connector:** the durable record of one import: stage, progress, timestamps, lease, heartbeat, identity, errors, events. It's what lets the app tell paused from failed from cancelled from active.
- **Expert:** `Core/Models/IngestionItem.swift`, Codable, created at enqueue, updated through every stage.

### Resumable ingestion (Core, verified)
- **Idiot:** pick up where you left off.
- **Dot-connector:** the sum of queue persistence, stable IDs, leases, heartbeats, checkpoints and stage-aware restart. Turns import from all-or-nothing into recoverable work without double-processing.
- **Expert:** spans the lifecycle; invoked after relaunch, background expiry or rebuild interruption. The 2026-08-29 fix made restored progress honest.

### Stable document ID (Core, verified)
- **Idiot:** the document's name tag that never changes.
- **Dot-connector:** filename or page identity would create duplicates and attach rebuilt chunks to the wrong parent. It is also what citations and deletion hang from.
- **Expert:** a UUID assigned before extraction and copied into every chunk, FTS row, entity mapping and document record (`DocumentChunk.documentId`).

### Streaming ingestion lane (Conditional, verified)
- **Idiot:** big files get handled a few pages at a time instead of all at once.
- **Dot-connector:** a hundreds-page PDF with every rendered page in memory at once gets the app killed. Batching pages and flushing keeps the working set bounded.
- **Expert:** chosen by size and characteristics before extraction in `DocumentProcessor`; writes checkpoints between batches.

### Weighted progress (Support, verified as `pipelineStageWeights`)
- **Idiot:** the progress bar moves at a realistic speed.
- **Dot-connector:** extraction is most of the work, storage is a blip. Even weighting would sit at 10% forever then jump to done.
- **Expert:** `IngestionItem.pipelineStageWeights`: loading 0.05, transcribing 0.03, extracting 0.52, chunking 0.08, analyzing 0.08, adapting 0.04, reindexing 0.04, embedding 0.10, indexing 0.04, storing 0.02; normalised by `pipelineTotalWeight`. Feeds the overlay, the Live Activity and diagnostics.
