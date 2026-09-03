# OpenIntelligence, edge to edge

> **Documentation status:** Written 2026-09-02 against commit `9c6fcbc`. Every concept name that
> looks like a code identifier was grepped against the Swift tree (115 of 116 found; the one miss is
> noted in module 07). Every number was taken from `Docs/Engineering/FULL_SYSTEM_TRACE.md`, which
> cites its line, or from a grep run while writing the module. Where the 612-term word bank or the
> Opus walkthrough disagrees with source, the module says so and source wins.
> `[evidence_level: code_verified_for_symbols_and_constants, confidence: high; status_labels: artifact_derived, confidence: medium]`

This is every one of the 612 concepts in the word bank, in pipeline order, explained at more than one level, with what was verified and what was corrected. It is the document you asked for so you never have to do this again. You will turn it into audio; it is written to be read aloud, so identifiers are kept to the expert rungs and every module opens with plain language.

## How it is built

Seventeen modules, the same seventeen the word bank uses, in the order the app runs. Each module has two parts.

**The ladder.** Seven rungs, the whole module at each depth:

1. Like you're five.
2. Like an idiot.
3. Like less of an idiot.
4. Average Joe.
5. Dot-connector: the person who is good at connecting things and doesn't know this yet.
6. Expert.
7. Expert's expert: the numbers, the code, the hazards, the corrections.

**Every concept.** Each of the module's concepts, with its status label from the word bank and a verification note, at three rungs: idiot, dot-connector, expert. Seven rungs per concept would have been four thousand paragraphs of the same sentence reworded; three is where the information actually changes.

The status labels are the word bank's audit vocabulary, not a runtime type: **Core** runs on the default path; **Conditional** runs in some modes or for some inputs; **Support** is diagnostics and evaluation; **Dormant** is in the source and on no shipping path; **Future** is a reserved name; **Historical** is superseded and misleading if taught as current. "Verified" after a status means the symbol was found in the Swift tree or the constant was read from source this week.

## The whole thing in twelve sentences

1. A file is enqueued as a durable ticket and processed one document at a time.
2. Its text is extracted by type: text layer, 360 DPI OCR, structured table parsing, XML, CSV, or on-device speech.
3. The text is cut into chunks of at most 310 words, validated at 430 tokens by the real tokenizer, each with a contextual prefix.
4. Each chunk becomes a normalised 384-dimension vector, on Core ML or Core AI, with the compute units requested by the GPU profile.
5. Chunks are written to SQLite FTS5 and to a memory-mapped vector file; summaries and entities are derived on top.
6. A question is profiled and planned first: intent, complexity, mode, and whether it is agentic.
7. Vector search and BM25 run in parallel and are fused with reciprocal rank fusion at k = 60.
8. A cross-encoder reranks the shortlist; a similarity floor and maximal marginal relevance cut it; neighbours are added.
9. Evidence is packed under the real token budget, strongest first and last.
10. A post-retrieval plan chooses abstain, deterministic, on-device, or Private Cloud Compute, and only then asks for consent.
11. The model streams a typed answer with citations; nine deterministic gates decide what survives.
12. What comes back is inspectable: claims, byte-offset citations, the completed route, and a trace.

## The thread through all of it

Every mechanism in this app is one of two things. It keeps the promise, that your documents stay yours: container isolation, local-first, on-device everything, memory-mapped vectors so a phone can hold a library, one outside room used only after retrieval with a shown payload and your consent. Or it defends against the danger, that a language model invents: two indexes, a cross-encoder second opinion, a similarity floor, diversity, a recorded budget, exactly two generative stages with nine deterministic gates aimed at them, citations to character ranges, and a badge that reports what completed rather than what was requested. If you cannot say which of the two a piece serves, you do not understand that piece yet.

## Corrections to the earlier documents, in one place

| Claim as taught | What the source says | Module |
|---|---|---|
| Audio goes through `SpeechAnalyzer` | The branch never compiles. `SFSpeechRecognizer`, on device, 600-second segments. | 02, 16 |
| Embeddings run on the Neural Engine | Requested, not placed. Efficiency and Balanced request CPU + Neural Engine; Performance and Maximum request all units; Core ML decides; Core AI exposes nothing. | 05, 15 |
| The GPU profile decides whether vector search uses Metal | It does not. The switch is 1,000 vectors and a Metal device. The profile gates Core ML units and the MMR matrix. | 06, 15 |
| `RecognizeDocumentsRequest` does OCR | It parses structure and tables. `VNRecognizeTextRequest` does OCR. | 02 |
| Page rendering is zero-copy | The PNG round trip is skipped; a full-page bitmap is still allocated. | 02 |
| Maximum's verification bar is 0.98 | 0.80. The 0.98 is the agentic loop's stopping target. | 00, 11, 12 |
| The advanced on-device model | Executes the default model. No advanced model exists in the SDK. | 10 |
| Core AI is a fallback | On iOS 27 and macOS 27 it is the default and saved Core ML defaults are migrated. | 05 |
| About six registered tools | Ten. | 10 |
| `NO_RELEVANT_CONTENT` triggers rescue or passthrough | Inside the compressor, yes; the caller in `RAGService` removes the chunk entirely. | 09 |
| Weighted progress has no named constant | It does: `pipelineStageWeights`, extraction 0.52. | 01 |
| TinyBERT reranker name is unverified | It is documented provenance: `cross-encoder/ms-marco-TinyBERT-L2-v2` in the notices file. | 08 |
| Fourteen ingestion stages | Fifteen; the enum also has `paused`. | 01 |

## The modules

| Module | Concepts | File |
|---|---|---|
| 00 System architecture and boundaries | 14 | `00_System_architecture_and_boundaries.md` |
| 01 Ingestion control, identity, and lifecycle | 19 | `01_Ingestion_control_identity_and_lifecycle.md` |
| 02 File extraction and document understanding | 52 | `02_File_extraction_and_document_understanding.md` |
| 03 Document analysis, adaptation, and derived knowledge | 15 | `03_Document_analysis_adaptation_and_derived_knowledge.md` |
| 04 Chunking and tokenizer integrity | 21 | `04_Chunking_and_tokenizer_integrity.md` |
| 05 Embeddings and vector semantics | 33 | `05_Embeddings_and_vector_semantics.md` |
| 06 Lexical indexing, SQLite, and vector persistence | 49 | `06_Lexical_indexing_SQLite_and_vector_persistence.md` |
| 07 Query understanding, intent, and execution planning | 45 | `07_Query_understanding_intent_and_execution_planning.md` |
| 08 Retrieval, fusion, reranking, and evidence expansion | 60 | `08_Retrieval_fusion_reranking_and_evidence_expansion.md` |
| 09 Context selection, compression, and token packing | 27 | `09_Context_selection_compression_and_token_packing.md` |
| 10 Model execution, routing, tools, and generation | 62 | `10_Model_execution_routing_tools_and_generation.md` |
| 11 Agentic, recursive, and multi-session reasoning | 40 | `11_Agentic_recursive_and_multi_session_reasoning.md` |
| 12 Verification, grounding, confidence, and abstention | 40 | `12_Verification_grounding_confidence_and_abstention.md` |
| 13 Response structure, provenance, rendering, and observability | 35 | `13_Response_structure_provenance_rendering_and_observability.md` |
| 14 Evaluation, benchmarks, and quality measurement | 31 | `14_Evaluation_benchmarks_and_quality_measurement.md` |
| 15 Device adaptation, compute, background work, sync, and product limits | 44 | `15_Device_adaptation_compute_background_work_sync_and_product_limits.md` |
| 16 Dormant, future, superseded, and commonly misnamed mechanisms | 25 + 1 | `16_Dormant_future_superseded_and_commonly_misnamed_mechanisms.md` |

`EDGE_TO_EDGE_FULL.md` beside this file is all seventeen concatenated, for one paste.

## Sources

- `Docs/Engineering/FULL_SYSTEM_TRACE.md`, the execution trace with file:line for every number here.
- `Docs/Research/AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md`, the 612-term word bank; all 153 source paths it cites exist.
- `Docs/Research/HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt`, the reasons.
- `Docs/STUDY_GUIDE.md`, the course with checklists and quizzes; `Docs/Audio/`, the five-pass spoken version.
# Module 00. System architecture and boundaries

Fourteen concepts. This module is the walls, the rooms, and the house rules. Nothing here does work by itself; everything here is a rule that every other module obeys.

## The ladder

**Like you're five.** You have a box of your own papers. The box lives inside your phone and only you have the key. You can ask the box a question and it finds the page that answers it and points at the exact line. If the answer isn't in the box, it says "not in here" instead of making something up. Nothing ever leaves the box unless it asks you first and shows you what it wants to take out.

**Like an idiot.** It's a private search engine plus a writer, for your own files, that runs on the phone instead of on someone's server. The search part finds the right pages. The writer part turns them into an answer. The search part can't lie because it's just math. The writer part can lie, so there's a bouncer that checks every sentence against the pages before you see it. That's the whole app: find, write, check, and never phone home without asking.

**Like less of an idiot.** The category name is retrieval-augmented generation. Retrieve first, generate second. Retrieval is deterministic: same question, same evidence, every time, no imagination involved. Generation is a language model and can invent. So the design puts the model in a very small room: it only ever sees the evidence the retrieval found, it has to cite that evidence for every claim, and nine rule-based checks run on its output. Each of your libraries is a sealed container so one library's documents can never answer another's question. And the only thing that can ever leave the phone is the final write-up, to Apple's Private Cloud Compute, after you've seen the payload and said yes.

**Average Joe.** Three modes turn the same machine up or down: Standard is one pass, Deep Think and Maximum loop. The whole pipeline is built as a library target so it can be tested without the app's screens, billing, or platform glue. The reason the deterministic-versus-generative split matters so much is that it tells you where bullshit can enter: exactly two places, when the app rewrites your question and when it writes the answer. Everything else is a calculator.

**Dot-connector.** Here's the pattern to carry into every later module. Every mechanism in this app is one of two things: it keeps the promise (your data stays yours) or it defends against the danger (the model invents). Container isolation, local-first, on-device everything, consent-gated cloud: promise. Two indexes, reranker, floors, budget, gates, citations, honest route badge: danger. If you can't say which of the two a piece serves, you don't understand that piece yet. Also notice what the quality modes actually are: not a temperature knob but a coherent bundle of numbers (candidate breadth, similarity floors, iteration caps, confidence bars) resolved once at query start so no screen can quietly use contradictory values.

**Expert.** The engine is `RAGService` internally and `OIEngine` at the SDK boundary, built as the `OpenIntelligenceEngine` SwiftPM target with App, Features, UI, Billing and a handful of platform files excluded. Every store filters by container UUID before a candidate can enter ranking or generation: FTS rows, vector stores, entity lookups, documents, threads, queries. The runtime coordinator resolves quality mode, PCC eligibility, adaptive config, query profile and the agentic decision before any search runs. Standard uses initial top-K 30, similarity floor 0.28, MMR λ 0.60, confidence bar 0.50; Deep Think 35 / 0.25 / 0.55 / 0.60; Maximum 50 / 0.20 / 0.50 / 0.80. Generation temperature 0.4 / 0.4 / 0.3. Only the final synthesis can leave the device, through a post-retrieval execution plan with an on-device fallback attached to every cloud plan.

**Expert's expert.** Three things people get wrong at this layer. First, "local-first" is a constraint applied before every pipeline choice, not a stage; it is why exact vector scan over an mmap replaced any hosted vector database and why the context budget is a hard number instead of a hope. Second, the mode confidence bar for Maximum was 0.98 until it turned out to be unreachable and every Maximum answer failed verification; it is 0.80 now, and the 0.98 you will see elsewhere is the agentic loop's stopping target, a different number for a different job. Third, the status vocabulary the word bank uses (Core, Conditional, Support, Dormant, Future, Historical) is an audit layer, not a runtime type; there is no enum in the app that says "Dormant". Treat it as a reading aid that was checked against source on 2026-09-01, with the corrections listed per module in this document.

## Every concept

### Container isolation (Core, verified)
- **Idiot:** each library is its own locked room. A question in room A cannot see papers in room B.
- **Dot-connector:** every table and every vector store carries the container's UUID, and every read filters on it before ranking sees a candidate. That is also what makes deleting or rebuilding one library safe: the filter is the blast radius.
- **Expert:** enforced in `SQLiteFullTextService` (container column on shared tables), `VectorStoreRouter` (one store instance per container file) and `EntityIndexService`. It is a shared-schema-with-scoping design, not one SQLite file per library; the tradeoff is simpler migrations against a filter that must never be forgotten in a new query.

### Deep Think mode (Conditional, verified)
- **Idiot:** the "try harder" setting. It searches more than once and thinks in between.
- **Dot-connector:** it flips on query rewriting, expansion, HyDE, iterative retrieval and the agentic orchestrator, and it raises the verification bar. You pay in time and heat for a better shot at multi-part questions.
- **Expert:** resolved by `QueryRuntimeCoordinator` into an agentic decision of `.agentic`; the orchestrator's `default` profile is 5 steps, 0.85 confidence target, escalation below 0.35. Retrieval floor 0.25, MMR λ 0.55, mode confidence 0.60, reasoning chain 4 sessions, PCC reasoning level moderate if the cloud is chosen.

### Deterministic stage (Core, verified)
- **Idiot:** a calculator step. Same input, same answer, can't make things up.
- **Dot-connector:** extraction, chunking, search, fusion, rerank, packing, route authorization, the gates, citation mapping. These are where the app's honesty lives, because they cannot hallucinate.
- **Expert:** `ModelExecutionPlan` types its three stages as retrieve (deterministic), synthesise (the chosen target), verify (deterministic). Keeping retrieval and verification deterministic is the design decision that lets the gates be trusted more than the writer.

### Engine status vocabulary (Support, not a runtime symbol)
- **Idiot:** the labels Core, Conditional, Support, Dormant, Future, Historical. They tell you whether a thing actually runs.
- **Dot-connector:** a repo this size has scaffolds, reserved enums and dead branches that look alive. The labels stop you from learning a blueprint as if it were a gear.
- **Expert:** an audit overlay, not code. Anchored loosely to `Docs/SHIPPED_CAPABILITIES.json` and the changelog. Verified this week: one label is wrong (the Neural Engine is "requested", not "Core"), one item is missing from Dormant (the `SpeechAnalyzer` branch), and Core AI should read Conditional-becoming-default on the 27 systems.

### Generative stage (Core, verified)
- **Idiot:** the step where the AI writes words. The only step that can bullshit you.
- **Dot-connector:** there are two: rewriting your question and writing the answer. Both happen after evidence is chosen and before the gates. Everything around them is armor.
- **Expert:** `LLMService` and `FoundationModelStructuredGenerator`. Structured generation with `@Generable` makes the output typed claims with evidence IDs, which is what makes Gate B (every claim cites) mechanically checkable instead of a vibe.

### Ingestion pipeline (Core, verified)
- **Idiot:** what happens when you drop a file in. Read it, cut it up, file it, done, once.
- **Dot-connector:** every later answer is bounded by what ingestion preserved. A fact that got truncated, scrambled or filed under the wrong identity here is unrecoverable by any amount of clever retrieval. That is why ingestion has more checks than retrieval does.
- **Expert:** `DocumentProcessor` under `RAGService.runIngestionLoop`, serial per document, stages queued through complete, with the document-level full text written to FTS before chunking and the chunk rows written after embedding. Detailed in module 01 and `Docs/INGESTION_PIPELINE.md`.

### Knowledge container / library (Core, verified)
- **Idiot:** a library. A named bucket of documents with its own settings.
- **Dot-connector:** it is the isolation boundary and also the unit of embedding configuration, which matters because two libraries can legitimately use different embedding providers and their vectors must never be compared.
- **Expert:** `KnowledgeContainer` (model) and `ContainerService`. Its UUID scopes every downstream read and write, its fingerprint pins the vector space, and its sync mode decides whether iCloud reconciliation touches it.

### Local-first (Core, verified)
- **Idiot:** it all happens on your phone. Not on a server.
- **Dot-connector:** the phrase is a list, not a slogan: documents, full text, embeddings, indexes, retrieval, packing and verification all run on the device. The one exception is the final answer, which may go to Private Cloud Compute after consent. That exception is the entire cloud story.
- **Expert:** the constraint that forced the architecture: memory-mapped exact vector scan instead of a hosted ANN service, a 4,096-token on-device window as the packing budget, and a planner that only reaches for the cloud when the local budget does not fit or the complexity asks for it. `Docs/PRIVACY_AND_ROUTING.md` is the canonical statement.

### Maximum mode (Conditional, verified)
- **Idiot:** the "spend everything" setting. Widest search, most thinking, strictest checking.
- **Dot-connector:** it enters the agentic loop immediately and keeps going until it is confident, stalls, times out or hits the cap. Missing evidence costs more than waiting, so it prefers gathering.
- **Expert:** initial top-K 50, floor 0.20, MMR λ 0.50, mode confidence 0.80. The unlimited reasoning path targets 0.98, caps at 50 sessions scaled to three chunks per session, disables tools inside sessions to stop overflow, and stops on target, saturation, cancellation or cap. Correction to the bank: the "highest verification threshold" is 0.80, not 0.98; 0.98 is the loop target.

### OpenIntelligence engine (Core, verified)
- **Idiot:** the machine. Files in, cited answers out.
- **Dot-connector:** one owner for the whole contract, so ingestion, storage, retrieval, generation and verification cannot each be locally right and jointly wrong about IDs, dimensions, budgets or citation numbering.
- **Expert:** `RAGService` (19,000 lines, the mega-orchestrator) internally, `OIEngine` in `SDK/OpenIntelligenceEngine.swift` at the boundary. The SwiftPM target `OpenIntelligenceEngine` builds this without the app shell.

### Quality mode (Core, verified)
- **Idiot:** Standard, Deep Think, Maximum. A dial.
- **Dot-connector:** not a temperature knob. One dial changes candidate breadth, floors, expansion, iteration, session count, confidence requirement and memory depth together, so the pipeline stays coherent.
- **Expert:** `RAGQualityMode` holds the bundle; `QueryRuntimeCoordinator.resolveContext` resolves it once at query start. The numbers are in the ladder above and verified in the trace.

### Query pipeline (Core, verified)
- **Idiot:** what happens when you ask a question. Understand, find, pick, write, check.
- **Dot-connector:** its job is to turn a whole library into a small evidence packet that fits the model and can be audited afterwards. Every stage cuts candidates; the diagnostics record what each cut dropped.
- **Expert:** `RAGService.queryInternal` after the coordinator: vocabulary, understanding, embedding (cache-aware), hybrid search, fusion, rerank, floor, MMR, expansion, compression, packing, plan, route, session, stream, gates, response. Module 07 to 13 walk it stage by stage.

### Retrieval-augmented generation (Core, verified)
- **Idiot:** look it up, then write it up.
- **Dot-connector:** the model cannot hold your library and does not know your documents; retrieval supplies the facts and the citations, generation supplies the readable sentence. Keeping the two apart is what makes "cite every claim" possible.
- **Expert:** begins after ingestion produced the two indexes; spans query understanding through verification. The app's specific flavour is post-retrieval routing: where to generate is decided after the evidence exists, from its real size and sensitivity.

### Standard mode (Core, verified)
- **Idiot:** the normal setting. One pass, fast.
- **Dot-connector:** it still does the non-negotiables: hybrid retrieval, rerank, MMR, citations, generation, gates. What it skips is the loop.
- **Expert:** top-K 30, floor 0.28, λ 0.60, confidence 0.50, temperature 0.4, single `LanguageModelSession`. A Standard query can still become agentic through planner escalation, which is the third of the three agentic paths.
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
# Module 02. File extraction and document understanding

Fifty-two concepts. This is the reading room: getting the words, tables and pictures out of a file, on the device, without trusting the file.

## The ladder

**Like you're five.** Some papers have real words the phone can copy. Some papers are just pictures of words, so the phone has to look at the picture and read it like you do. Some papers have tables, and the phone is careful to keep the rows and columns lined up. Some "papers" are recordings, so the phone listens and writes down what it hears.

**Like an idiot.** Extraction is the step where a PDF, Word file, spreadsheet, photo or audio recording becomes plain text the rest of the app can use. The app picks a different tool per file type. It does not trust a PDF's hidden text layer, because scanned PDFs often have a garbage one; it checks a page first. It reads pages at high resolution when it has to OCR them. It reads tables as tables. And it does all of it on the phone.

**Like less of an idiot.** Extraction is the ceiling on the whole app: a fact that never makes it out of the file cannot be retrieved later by any cleverness. So there is a page-complexity triage that decides per page whether the native text is enough, whether OCR is needed, and whether a structured pass for tables is worth it. OCR goes through Apple's Vision framework with the accurate recogniser, language correction, and a language list narrowed to what was detected. A different Vision request reads document structure. Office files are unzipped and their XML streamed. CSV is parsed properly. Audio is transcribed with on-device speech recognition in ten-minute segments. Garbage-text detection throws out character salad from rotated labels and diagrams.

**Average Joe.** The reason so much machinery exists here is that the cheap path lies. A PDF that "has text" might have text from a broken OCR someone ran years ago. A two-column paper read straight across produces sentences that never existed. A number without its column header is worthless. So each of those failure modes has a specific counter: text-layer validation, column detection and reading-order reconstruction, table row records with their headers attached.

**Dot-connector.** Two Vision requests, two jobs. `VNRecognizeTextRequest` is line-oriented OCR: strings, confidence, bounding boxes. `RecognizeDocumentsRequest` is structure: paragraphs, lists, tables with rows and columns. The word bank blurs them in places; keep them separate. Rendering a page to a bitmap is cheap CPU work (12 to 16 ms a page at 360 DPI on a real trace); recognition is where the hours go, and the app throttles Vision with a semaphore sized to the device because unbounded Vision plus Metal races and exhausts command buffers. And the thing about "zero-copy": what is skipped is the PNG round trip; a full-page bitmap is still allocated.

**Expert.** PDF text-layer validation: pick the page with the most native text (at least 50 characters), render, quick OCR, compare; garbled means every page goes to OCR. Complexity triage renders at 144 DPI and looks for grid lines and figures; classes are trivial, simple, moderate, complex, visual, scanned. OCR render is `renderPDFPageAsImage(page:scale: 5.0)`, 360 DPI, `UIGraphicsImageRenderer` opaque on iOS and a `CGBitmapContext` on macOS. OCR request: `.accurate`, `usesLanguageCorrection = true`, `recognitionLanguages` narrowed by `LanguageDetectionService`, custom words from the dynamic document vocabulary plus universal custom words. Structure pass at 180 DPI downscaled, or 360 for high-risk pages. Vision concurrency 2 to 64 by device tier with a short cooldown. Audio: `AudioTranscriptionService`, `SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`, segments of at most 600 s. 500 MB cap for non-streamable files.

**Expert's expert.** The macOS render path used to go through `NSImage.lockFocus`, which produced images four times larger than requested, 370 MB per page; replaced by a bitmap context in late August. The OCR language narrowing landed 2026-08-29 because thirteen recognisers including four CJK models were loading on every request. And the `SpeechAnalyzer` branch in `SpeechAnalyzerService` never compiles: it is guarded by `#if canImport(SpeechAnalyzer)`, a module that does not exist in the SDK (the API lives in `Speech.framework`), and it calls `results(for:)` on an actor that declares `analyzeSequence(from:)` instead. Every build takes the legacy `SFSpeechRecognizer` path. Filed to Future Backlog 2026-09-02. Anything that says audio goes through SpeechAnalyzer is wrong.

## Every concept

### Adaptive preprocessing (Conditional, verified in `OCRConfiguration`)
- **Idiot:** touching up the photo before reading it: contrast, sharpen, straighten.
- **Dot-connector:** one filter cannot fix both a faint receipt and a crisp diagram, so preprocessing is chosen per page and clean pages are left alone.
- **Expert:** after rasterisation, before the OCR pass, with quality scoring selecting or escalating candidates.

### Audio transcription (Conditional, verified)
- **Idiot:** the phone listens to the recording and types it out.
- **Dot-connector:** a recording has no words to index until it is transcribed; the transcript then goes through normal chunking with timestamps kept.
- **Expert:** `AudioTranscriptionService` on `SFSpeechRecognizer`, on-device required, segmented at 600 s. Not `SpeechAnalyzer`; see the ladder.

### Barcode detection (Conditional, verified)
- **Idiot:** reads the barcode instead of squinting at the digits.
- **Dot-connector:** a barcode carries the most exact identifier on the page; OCR would only approximate it.
- **Expert:** `CaptureToRAGBridge` during live camera analysis; the payload can be written into the capture before ingestion.

### Camera-to-RAG bridge (Conditional, verified)
- **Idiot:** point the camera at a page and it becomes a document.
- **Dot-connector:** captures are turned into a temporary Markdown document and sent through the exact same ingestion pipeline, so they get the same identity, chunking, embedding and verification.
- **Expert:** an actor in `Features/Camera/CaptureToRAGBridge.swift`, runs after recognition and before enqueue.

### Column detection (Conditional, verified in `LayoutAwareExtractor`)
- **Idiot:** figures out that the page has two columns so it doesn't read across them.
- **Dot-connector:** histogram and gap clustering of text-block x-coordinates. Reading a two-column paper straight across produces nonsense passages and nonsense citations.
- **Expert:** after blocks are extracted, before per-column top-to-bottom ordering.

### Compact cell anchor (Conditional, verified in `StructuredDocumentParser`)
- **Idiot:** a tiny label on a cell saying which row and column it's from.
- **Dot-connector:** for small tables it improves exact lookup without repeating every cell and blowing the chunk budget.
- **Expert:** generated after row records, before the canonical Markdown table representation.

### CoreMLDocumentClassifier (Conditional, verified)
- **Idiot:** guesses what kind of document this is.
- **Dot-connector:** a local classifier that can steer extraction and chunking without sending content anywhere.
- **Expert:** loads with `computeUnits = .cpuAndNeuralEngine`; runs during analysis before the ingestion plan is resolved.

### CoreMLRegionDetector (Conditional, verified)
- **Idiot:** finds the boxes on the page: this is a table, that's a figure.
- **Dot-connector:** routing visually complex regions to the right extractor.
- **Expert:** `computeUnits = .all`; after rendering, before structured region processing, when enabled.

### Detected data entity (Conditional, verified)
- **Idiot:** the app notices "that's an email address," "that's a dollar amount."
- **Dot-connector:** typed data become searchable anchors and remove ambiguity during extraction.
- **Expert:** emails, phones, URLs, addresses, dates, money, measurements from visual analysis, attached to page or table structure before chunking.

### Dynamic document vocabulary (Conditional, verified in `OCRConfiguration`)
- **Idiot:** the document teaches the OCR its own weird words first.
- **Dot-connector:** acronyms, codes, CamelCase, compounds and repeated name pairs pulled from the rough native text and handed to Vision as expected words, so OCR stops misreading them. No hardcoded medical or legal lists.
- **Expert:** derived before OCR, merged with universal custom words into `customWords`.

### Embedding translation (Conditional, verified in `TranslationService`)
- **Idiot:** translate a copy for the search map, keep the original for showing you.
- **Dot-connector:** a monolingual embedder retrieves cross-language content badly; translating only the embedding input fixes that without rewriting the source you'll be quoted.
- **Expert:** immediately before embedding for affected documents or summaries.

### Escalating DPI (Conditional, verified)
- **Idiot:** try a normal zoom, zoom in more if the text is tiny.
- **Dot-connector:** max DPI everywhere wastes memory and heat; never escalating loses footnotes and labels. Page analysis and OCR confidence decide.
- **Expert:** the structure pass is 180 DPI downscaled or 360 for high-risk pages; the OCR pass is 360 by default.

### Garbage-text detection (Conditional, verified)
- **Idiot:** throws away "text" that's actually noise from a diagram.
- **Dot-connector:** rotated labels and diagrams produce fluent-looking salad; letting it in poisons chunks, vocabulary and embeddings.
- **Expert:** rules for mixed scripts, improbable consonant runs and suspicious non-ASCII, respecting detected language; after OCR, before text enters the corpus.

### ImageUnderstandingService (Conditional, verified)
- **Idiot:** looks at pictures in the document and says what's in them.
- **Dot-connector:** diagrams carry evidence OCR can't see.
- **Expert:** runs on selected visual regions after page analysis; descriptions attached to chunks.

### Language detection (Conditional, verified) and LanguageDetectionService (Conditional, verified)
- **Idiot:** figures out what language the document is in.
- **Dot-connector:** language drives OCR garbage rules, translation, tokenizer expectations, and, since 2026-08-29, which Vision recognisers load.
- **Expert:** NaturalLanguage-based; runs once enough text exists; feeds `recognitionLanguages` on the OCR request.

### Layout-aware extraction (Conditional, verified)
- **Idiot:** reads the page the way a human's eyes move, not the way the file happens to store it.
- **Dot-connector:** PDF text is stored by coordinates; multi-column pages interleave lines if you trust file order.
- **Expert:** `LayoutAwareExtractor`, after native or Vision block extraction, before page text assembly.

### Live camera analysis (Conditional, verified)
- **Idiot:** the camera preview already sees text, edges and barcodes before you snap.
- **Dot-connector:** guidance and structured observations before commit; it does not create a document by itself.
- **Expert:** `CameraManager` plus the bridge; text, boundaries, barcodes, scenes, animals, faces, humans.

### OCR (Conditional, verified)
- **Idiot:** turning a picture of words into words.
- **Dot-connector:** required before any indexing of a scan or photo; it follows render and preprocessing and precedes structure recovery and chunking.
- **Expert:** `VNRecognizeTextRequest` configured by `OCRConfiguration`; see the ladder for the exact settings.

### OCR confidence (Core, verified)
- **Idiot:** how sure the reader is about each line.
- **Dot-connector:** used to reject weak blocks, trigger rescans, and report quality instead of pretending every character is exact.
- **Expert:** per-observation confidence from Vision and per-segment from speech; consumed before normalisation and indexing.

### OCRConfiguration (Core, verified)
- **Idiot:** the one place that sets up how reading works.
- **Dot-connector:** independently configured Vision requests drift; one authority keeps ingestion and camera recognition aligned.
- **Expert:** revision, accuracy, language correction, languages, minimum text height, custom words, normalisation and garbage filtering, applied before execution and after results.

### On-device speech requirement (Core, verified)
- **Idiot:** the recording never leaves the phone to be transcribed.
- **Dot-connector:** the local-first promise applied to audio.
- **Expert:** `requiresOnDeviceRecognition = true` on every request.

### OOXML / Office parsing (Conditional, verified) and Structured Office parser (Core, verified) and StreamingXMLProcessor (Conditional, verified)
- **Idiot:** Word and PowerPoint files are zip files full of XML; the app opens them and reads the XML directly instead of taking screenshots.
- **Dot-connector:** native structure is preserved and no page is rasterised; the XML is streamed so a huge deck doesn't spike memory.
- **Expert:** selected by file type in `DocumentProcessor`; `StreamingXMLProcessor` is the bounded-memory parser.

### Page complexity class (Core, verified) and PageComplexityAnalyzer (Core, verified)
- **Idiot:** a label for how hard each page is to read.
- **Dot-connector:** trivial, simple, moderate, complex, visual, scanned. The label decides native text versus OCR versus full visual handling, so easy pages stay cheap and hard pages get the expensive path.
- **Expert:** `PageComplexityAnalyzer` combines native structure, text coverage, layout, numeric density, tables, figures, forms, columns, annotations and selective Vision signals; triage render at 144 DPI.

### Page rendering (Conditional, verified)
- **Idiot:** turning a page into a picture so it can be read as one.
- **Dot-connector:** only when analysis or OCR needs it; 360 DPI; cheap compared with recognition.
- **Expert:** `renderPDFPageAsImage(page:scale: 5.0)`; platform-specific renderer; macOS was 4× oversize until the bitmap-context fix.

### Page sentinel (Core, verified)
- **Idiot:** a marker between pages in the combined text.
- **Dot-connector:** without it, chunks and citations could cross pages without knowing where the evidence came from.
- **Expert:** inserted during extraction, interpreted when building page-aware chunks and offsets.

### PDF text layer (Core, verified) and PDFKit extraction (Core, verified)
- **Idiot:** copying the words a real PDF already contains.
- **Dot-connector:** faster and more accurate than OCR when it's trustworthy, and it preserves exact characters for offsets and citations. It also seeds the OCR vocabulary.
- **Expert:** `PDFPage` strings, selections, bounds and annotations via `LayoutAwareExtractor`; attempted first unless validation says the layer is absent or garbage.

### Reading-order reconstruction (Conditional, verified)
- **Idiot:** putting the pieces in the order a person would read them.
- **Dot-connector:** correct words in the wrong order are still a corrupted corpus.
- **Expert:** the final layout step in `LayoutAwareExtractor` before page text enters processing.

### Recognition-language set (Core, verified)
- **Idiot:** the list of languages the reader is allowed to expect.
- **Dot-connector:** English-only corrupts multilingual documents; unconstrained guessing degrades recognition; since 2026-08-29 the set is narrowed to what was detected.
- **Expert:** `recognitionLanguages` on the request, set by `OCRConfiguration`.

### RecognizeDocumentsRequest (Conditional, verified)
- **Idiot:** the reader that understands tables and lists, not just lines.
- **Dot-connector:** returns paragraphs, lists and tables as structure so rows and columns survive. This is not the OCR request.
- **Expert:** used in `StructuredDocumentParser` on pages the triage selects; 180 DPI downscaled or 360 for high-risk pages.

### RFC 4180 CSV parsing (Core, verified)
- **Idiot:** reads spreadsheets-as-text correctly, quotes and commas and all.
- **Dot-connector:** splitting on commas corrupts cells that contain commas. The standard exists for a reason.
- **Expert:** in `DocumentProcessor` CSV extraction before rows are indexed.

### Segmented transcription (Conditional, verified) and Transcription segment (Conditional, verified)
- **Idiot:** long recordings are cut into slices, each transcribed, timestamps stitched back.
- **Dot-connector:** one recognition task has a practical duration limit; slices also isolate retries.
- **Expert:** 600 s maximum per segment; each segment yields spans with start, end and confidence, offset back into the full recording.

### SpatialDocumentAnalyzer (Conditional, verified) and Spatial document analysis (Conditional, verified)
- **Idiot:** notices where things sit on the page, because position is meaning in forms and diagrams.
- **Dot-connector:** connects captions, figures and table context with surrounding text before it's too late.
- **Expert:** consumes extracted blocks before metadata and chunk construction.

### StructuredElement (Conditional, verified), TableData (Conditional, verified), Table row record (Conditional, verified), Table schema view (Conditional, verified)
- **Idiot:** the app keeps tables as tables: headers, rows, and a one-line list of the column names.
- **Dot-connector:** a row record like "Row 2: Model=1688; Reference=1688-020-122" makes a row independently retrievable; the schema view gives BM25 the column names as high-signal anchors; typed elements let the chunker keep tables atomic and boost headings.
- **Expert:** `StructuredDocumentParser` emits them; rows go to `chunk_table_rows`, elements to `chunk_structured`.

### TextBlock (Conditional, verified)
- **Idiot:** a piece of recognised text plus where it was on the page.
- **Dot-connector:** position has to survive long enough to rebuild columns, lines and tables.
- **Expert:** normalised bounding box, confidence, page number; produced by PDFKit or Vision, consumed by layout clustering.

### TranslationService (Conditional, verified)
- **Idiot:** translates when a library asks for it, but never replaces the original.
- **Dot-connector:** cross-language embedding consistency without changing the quoted evidence.
- **Expert:** after language detection, before the optional translated-embedding path.

### Type-specific extractor (Core, verified)
- **Idiot:** the right tool for the file type.
- **Dot-connector:** forcing everything through OCR loses structure and wastes rasterisation; PDF, Office XML, CSV, audio and images each keep different structure.
- **Expert:** selected right after load in `DocumentProcessor`.

### Universal custom words (Support, verified)
- **Idiot:** a list of short technical tokens the reader should expect: mg/dL, N·m, ISO.
- **Dot-connector:** Vision keeps such tokens when told to expect them.
- **Expert:** merged with the dynamic vocabulary into the OCR request.

### VisionOCRThrottle (Core, verified)
- **Idiot:** don't run too many readers at once.
- **Dot-connector:** Vision and Metal race, exhaust command buffers and destabilise memory when launched without bounds.
- **Expert:** an actor-based semaphore sized by `DeviceCapabilityService` (2 to 64 by tier) with a cooldown between operations.

### Visual evidence source (Conditional, verified) and VisualCaptioningService (Conditional, verified)
- **Idiot:** a picture can be evidence too, and the app says which picture.
- **Dot-connector:** captions bridge images into text retrieval; the provenance object keeps the caption tied to the real region so it can't pass as prose.
- **Expert:** `VisualEvidenceSource` in the response model and `VisualEvidenceCard` in the UI; captioning after image understanding, before embedding.

### VNRecognizeTextRequest (Conditional, verified)
- **Idiot:** the line reader.
- **Dot-connector:** strings, confidence and boxes for OCR blocks, live camera frames and layout extraction. This is the OCR request.
- **Expert:** `.accurate`, language correction on, narrowed languages, custom words, minimum text height from `OCRConfiguration`.

### YOLODetectionService (Conditional, verified)
- **Idiot:** spots objects in pictures.
- **Dot-connector:** labels and bounds enrich text-poor pages and captures; it does not replace text retrieval.
- **Expert:** Core ML with `computeUnits = .all`; contributes visual metadata during image understanding.

### Zero-copy image path (Core, verified with a caveat)
- **Idiot:** don't save the page as a PNG and reload it just to read it.
- **Dot-connector:** the round trip is what's skipped; the page bitmap itself is still allocated. Peak memory is lower, not zero.
- **Expert:** `CIImage` to `CGImage` handoff inside the render-to-Vision path in `DocumentProcessor`.
# Module 03. Document analysis, adaptation, and derived knowledge

Fifteen concepts. Reading between the lines: the extras the app derives from a document so later stages have more than raw text.

## The ladder

**Like you're five.** After the phone reads a paper, it writes a one-paragraph note about what the whole paper is about, and it makes a list of all the names in it. Later, if you ask "what's this paper about," it reads the note instead of the whole paper.

**Like an idiot.** Some questions are about a document, not about one line in it. So the app makes a summary chunk per document. It also builds an index of names, part numbers and places so a question about a specific thing can jump straight to every chunk that mentions it. It classifies the document, spots specification-looking text, and flags bibliographies so they don't hog the results.

**Like less of an idiot.** RAPTOR-lite: one summary chunk per document, called level one, generated by a single language-model call from a sample of the document's densest chunks. Overview questions get routed to summaries instead of forty near-identical body chunks. GraphRAG-lite: an entity index mapping normalised names to chunk IDs, so retrieval can expand from an entity found in a good chunk to other chunks that share it, even across documents. Plus content tagging, classification, specification detection, cross-references, and a pre-scan that picks chunking settings before the expensive work begins.

**Average Joe.** Why not summarise everything hierarchically like the RAPTOR paper? Cost. One model call per document is affordable on a phone; recursively clustering and summarising a whole library is not. So levels two and three exist as reserved names and nothing more. Why a reference-list detector? Because a bibliography is the strongest keyword match on a page and the weakest evidence: dense names, dense numbers, answers nothing. It used to win.

**Dot-connector.** Where this happens in the ingestion loop: after embedding, not before. Vocabulary learning and Vision-entity learning at Steps 4.1 and 4.1b, the document summary at Step 4.5 (only when summaries are enabled in settings), a second persist, then content tags at Step 5 on iOS 26 and later. That order means summaries and tags are derived from the final chunks, and it also means they are the last things to arrive, so a document can be fully searchable before its summary exists.

**Expert.** `ChunkAbstractionLevel` on `DocumentChunk` (`.detail` default, summary L1, L2/L3 reserved, marked RAPTOR-lite June 2025). `DocumentSummaryService` builds representative text (first chunk, high-density chunks, last chunk, under a character budget), one FM call, embeds and indexes the summary as a special chunk. `EntityIndexService` keeps forward and reverse maps, normalised by lowercasing and stripping periods, hyphens and whitespace, scoped by document and container. `ReferenceListDetector` recognises bibliography shape. `SpecificationDetector` recognises codes, standards, measurements, grades, part numbers, percentages, ranges, ratios and flags spec-heavy passages. `ContentTaggingService` uses Foundation Models with an `NLTagger` fallback and a timeout so tagging never blocks ingestion. `RAPTORSummaryRouter` and `QueryRouterService` consume the summary level; `enableDocumentSummaries` gates generation and routing.

**Expert's expert.** The summary is generated by the on-device model, which means it is a generative stage inside ingestion, and it is the one place ingestion can hallucinate. It is never cited as source text; it is a routing aid whose retrieval leads to detail chunks. The predictive pre-scan is described in the bank and in `HOW_IT_WORKS.md` as sample-based analysis before bulk extraction; the behaviour is in `DocumentProcessor`, but treat the exact sample sizes as undocumented. Content tagging is iOS 26 and later only, which is one of the places the platforms silently diverge.

## Every concept

### Chunk abstraction level (Core, verified as `abstractionLevel`)
- **Idiot:** a label saying whether a chunk is a detail or a summary.
- **Dot-connector:** without it a broad summary would compete invisibly with a precise detail chunk in the same ranking.
- **Expert:** `ChunkAbstractionLevel` on `DocumentChunk`: detail (L0), document summary (L1), reserved L2/L3. Used by routing and context selection.

### Content tagging (Conditional, verified)
- **Idiot:** the app writes a few tags on each document: topics, actions, objects.
- **Dot-connector:** tags help navigation and retrieval vocabulary, and the fallback plus timeout mean a missing model never stalls an import.
- **Expert:** `ContentTaggingService`, Foundation Models first, `NLTagger` fallback, Step 5 of the loop, iOS 26 and later.

### Derived metadata (Core, verified)
- **Idiot:** everything the app knows about a chunk besides its words.
- **Dot-connector:** section, page, offsets, keywords, entities, abbreviations, structure, numeric flags, siblings, bounds, table data, abstraction level. Ranking, expansion, citation and verification all need it; embeddings throw it away.
- **Expert:** fields on `DocumentChunk`, created at ingestion, carried through retrieval into the response.

### Document classification (Conditional, verified)
- **Idiot:** what kind of document is this.
- **Dot-connector:** guides chunking, suggestions and diagnostics without a domain-specific parser.
- **Expert:** `CoreMLDocumentClassifier` (`.cpuAndNeuralEngine`) during analysis before final metadata.

### Document summary chunk (Conditional, verified)
- **Idiot:** the one-paragraph note about the whole paper.
- **Dot-connector:** overview questions read the note instead of dozens of detail chunks.
- **Expert:** `DocumentSummaryService`, Step 4.5, gated by `enableDocumentSummaries`, embedded and indexed as an L1 chunk.

### Entity extraction (Core, verified)
- **Idiot:** finding the names.
- **Dot-connector:** names, organisations, places and salient terms attached to chunk metadata become high-signal lexical fields and the raw material for the entity index.
- **Expert:** `SemanticChunker` enrichment and `EntityIndexService` insertion; NaturalLanguage tagging.

### Entity index (Conditional, verified)
- **Idiot:** a phone book from names to chunks.
- **Dot-connector:** O(1)-style lookup from an entity to every chunk that mentions it; the basis of GraphRAG-lite expansion.
- **Expert:** forward and reverse maps, document- and container-scoped, populated after chunks receive entities, queried during agentic or graph expansion.

### Entity normalization (Conditional, verified)
- **Idiot:** "U.S.A." and "USA" count as the same name.
- **Dot-connector:** exact string identity would fragment the graph into spelling variants.
- **Expert:** lowercase, strip periods, hyphens and whitespace, at index and lookup time.

### GraphRAG-lite (Conditional, verified)
- **Idiot:** hop from a good chunk to its relatives.
- **Dot-connector:** vector similarity misses a relevant passage that uses different words but shares a key name or a "see page 12." The graph catches those.
- **Expert:** `EntityIndexService` plus `GraphIndexService` edges (next, previous, sibling, reference, same section, shared entity), traversed after initial retrieval in deeper paths.

### Predictive pre-scan (Core, described in docs, behaviour in `DocumentProcessor`)
- **Idiot:** look at the first few pages to decide how to handle the rest.
- **Dot-connector:** chunking and OCR settings are expensive to change after every page is embedded, so estimate code, math, lists, tables, columns and vocabulary up front.
- **Expert:** after the file is accessible, before bulk extraction; sample sizes not documented as constants.

### RAPTOR-lite (Conditional, verified)
- **Idiot:** a two-level library: details and one summary per document.
- **Dot-connector:** fast overview routing without recursively summarising the whole corpus.
- **Expert:** L0 detail chunks and L1 summary chunks; `RAPTORSummaryRouter` selects summaries for overview queries.

### Reference-list detection (Core, verified)
- **Idiot:** notices the bibliography so it doesn't get treated as an answer.
- **Dot-connector:** dense names and numbers that answer nothing used to dominate retrieval and even the suggested questions.
- **Expert:** `ReferenceListDetector` recognises bibliography shape; influences tagging, chunk metadata and ranking penalties.

### Representative-text sampling (Conditional, verified)
- **Idiot:** pick the beginning, the densest middle bits, and the end.
- **Dot-connector:** the whole document exceeds the model's context; the beginning alone misses conclusions.
- **Expert:** first chunk, high-semantic-density chunks, final chunk, under a strict character budget, before summary generation.

### Spatial document analysis (Conditional, verified)
- **Idiot:** where things are on the page matters.
- **Dot-connector:** captions and table context are lost if position is discarded early.
- **Expert:** `SpatialDocumentAnalyzer` after recognition, before structured chunks are emitted.

### Specification detection (Core, verified)
- **Idiot:** notices things that look like specs: codes, sizes, part numbers, percentages.
- **Dot-connector:** exact values are extracted more reliably by shape than inferred by a model, and spec-heavy passages earn a ranking boost.
- **Expert:** `SpecificationDetector` on extracted text; reappears in `SpecificationExtractor` at query time.
# Module 04. Chunking and tokenizer integrity

Twenty-one concepts. Cutting the document into index cards that fit the embedding model, without slicing a table in half, and without trusting a word count.

## The ladder

**Like you're five.** The phone cuts each paper into little cards, about a paragraph each. The cards overlap a tiny bit at the edges so no sentence gets cut in half. Tables are never cut. Then the phone measures each card to make sure it actually fits in the reader's mouth, because the reader just swallows the first bit and spits out the rest without telling anyone.

**Like an idiot.** A chunk is a passage-sized piece of a document. It's the unit that gets searched, ranked, cited and checked. Chunks are at most 310 words, overlap by up to 50, and never split a table or list. Each one gets a short prefix saying which document and section it's from. Then, and this is the important part, every chunk is run through the real tokenizer to make sure it's under the model's limit, because the model doesn't complain when a chunk is too long. It silently truncates.

**Like less of an idiot.** The embedding model reads at most 510 tokens. Tokens are not words: technical text runs about 1.5 tokens per word, so 510 tokens is roughly 340 words, and the contextual prefix eats about 30 of those, hence 310. But a word count is only an estimate, and the failure when you're wrong is the worst kind: the model embeds the first 510 tokens and files that vector under the identity of the whole chunk. Nothing downstream can detect it. So the app validates every chunk with the tokenizer paired to the model, at 430 tokens (510 minus 80 reserved for the prefix), and splits anything over. Chunk boundaries are chosen at sentence boundaries, section headings, structural blocks and a short list of discourse transitions ("However," "In conclusion,").

**Average Joe.** Why does chunking get its own module? Because it's where a real disaster happened. A padding block in the tokenizer wrapper once made the token counter return a constant. The 430-token guard could never fire. More than half of every document was silently truncated at embedding, every embedding was diluted, and every log line read healthy. A plausible-looking constant is the most expensive kind of wrong.

**Dot-connector.** Two independent knobs, two different consequences. Chunk size and overlap can change mid-library with no harm, because a vector for a bigger chunk and a vector for a smaller chunk still live in the same coordinate space; that's "mixed chunk strategy compatibility." Changing the embedding model, its dimension, its tokenizer or its pooling changes the coordinate space itself, which is why that requires a full re-embed and is blocked during ingestion. Also notice that offsets are computed here, and offsets are what let a citation jump to a character range instead of a page.

**Expert.** `SemanticChunker` walks sentence boundaries from `NLTokenizer`, forces breaks at detected headings, keeps `StructuredElement` tables and lists atomic, and breaks at transition phrases (the list at `SemanticChunker.swift:1115` includes "Additionally," "Nevertheless," "Consequently," "In conclusion," "To summarize,"). Container-level `chunkingConfig` carries `maxChunkWords`, target and `overlapWords`; hard ceiling 310, largest target 260, overlap capped at 50, smallest target 100. `DocumentProcessor.enforceTokenLimitOnChunks` validates at `safeTokenLimit = maxEmbeddableTokens - contextualPrefixTokens` (510 minus 80 = 430) with the Rust-backed tokenizer; sub-splits leave a 10-token margin for part markers; anything still oversized is logged as such and will be truncated by the model. Chunks record byte offsets, section path, page, sibling group, parent content, semantic type, semantic density and abstraction level.

**Expert's expert.** "Still oversized after splitting" is logged, not counted anywhere a user sees, so it belongs on the silent-drop list. The 80-token prefix reserve is a budget, not a measurement: the actual prefix is whatever the document title and section path tokenize to. The word-piece vocabulary is MiniLM's; `[CLS]` and `[SEP]` are inserted by the tokenizer and count against the 510. And the same tokenizer is loaded at launch for counting, which is the one model-adjacent thing that happens before the first embed.

## Every concept

### 510-token embedding ceiling (Core, verified)
- **Idiot:** the reader's mouth fits 510 pieces. No more.
- **Dot-connector:** MiniLM's usable sequence after special tokens; exceed it and the tail is silently dropped.
- **Expert:** `maxEmbeddableTokens` in `EmbeddingProvider`; rechecked at embedding time; the guard is at 430 because 80 are reserved for the prefix.

### Actual tokenizer validation (Core, verified)
- **Idiot:** measure with the real ruler, not by guessing.
- **Dot-connector:** word count is an estimate; the paired tokenizer is the truth; this is the step the padding bug bypassed.
- **Expert:** `enforceTokenLimitOnChunks` with the tokenizer from the embedding tokenizer bundle; splits over 430, re-checks, logs stragglers.

### Atomic structural block (Core, verified)
- **Idiot:** never cut a table in half.
- **Dot-connector:** a cell without its header, a warning without its conditions, is misleading evidence.
- **Expert:** `StructuredDocumentParser` flags them; `SemanticChunker` hands them through indivisibly when feasible.

### Chunk (Core, verified)
- **Idiot:** an index card.
- **Dot-connector:** whole documents are too broad to rank and too big for the model; chunks make retrieval granular while keeping local meaning.
- **Expert:** `DocumentChunk`: content, source identity, metadata, usually an embedding; the unit indexed, ranked, packed, cited and verified.

### Chunk offset (Core, verified)
- **Idiot:** where exactly in the document this card came from.
- **Dot-connector:** offsets are what make "jump to the sentence" and quote citations possible without fuzzy searching.
- **Expert:** start and end positions computed during chunking; consumed by citation and contextual compression.

### Chunk overlap (Core, verified as `overlapWords`)
- **Idiot:** the cards share a few words at the edges.
- **Dot-connector:** a fact on a boundary would otherwise be split out of both cards.
- **Expert:** trailing context repeated at the next chunk's start; capped at 50 words.

### Chunk semantic type (Core, verified)
- **Idiot:** a label: prose, table, list item, warning.
- **Dot-connector:** different structures get different ranking, packing and verification treatment.
- **Expert:** assigned at ingestion on `DocumentChunk`; consulted by boosts and intent-specific packing.

### Contextual prefix (Core, verified)
- **Idiot:** a sticky note on the card: "from the brake manual, section 4."
- **Dot-connector:** a chunk alone has lost what it's about; the prefix puts that back into the vector without changing the quoted text.
- **Expert:** document and section label prepended to the embedding text only; 80 tokens reserved for it.

### Cross-reference metadata (Conditional, verified)
- **Idiot:** "see page 12" is remembered as an arrow.
- **Dot-connector:** manuals answer indirectly; capturing the edge lets the graph fetch the target.
- **Expert:** on `DocumentChunk`, traversed by `GraphIndexService` after initial retrieval.

### Linguistic transition boundary (Core, verified)
- **Idiot:** words like "However" are good places to cut.
- **Dot-connector:** transitions signal a new argument or a summary; cutting there keeps passages coherent.
- **Expert:** a small English phrase list in `SemanticChunker`, considered after sentence and heading breaks.

### Maximum chunk size (Core, verified)
- **Idiot:** 310 words, tops.
- **Dot-connector:** the ceiling derived from the token limit and the prefix reserve; enforced while chunking, then double-checked by the tokenizer.
- **Expert:** `maxChunkWords` on the container config; hard cap 310.

### Mixed chunk strategy compatibility (Core, documented)
- **Idiot:** you can change the card size later without redoing everything.
- **Dot-connector:** boundaries change what a vector represents, not the coordinate system; old and new chunks stay comparable.
- **Expert:** documented in `HOW_IT_WORKS.md`; contrasts with embedding changes, which force a rebuild.

### Parent content (Core, verified)
- **Idiot:** the bigger paragraph the card was cut from, kept nearby.
- **Dot-connector:** small chunks rank precisely; generation and citation sometimes need the surrounding context to interpret them.
- **Expert:** attached at ingestion; restored by `ParentDocumentService` after ranking.

### Section-heading boundary (Core, verified)
- **Idiot:** a new heading means a new card.
- **Dot-connector:** the heading defines the local topic and is itself high-value metadata; crossing it mixes sections.
- **Expert:** evaluated as `SemanticChunker` walks sentences and structure.

### Semantic density (Support, verified)
- **Idiot:** how much information is packed into the card.
- **Dot-connector:** used to pick representative chunks for summaries and for diagnostics.
- **Expert:** heuristic score stored in chunk metadata; consumed by `DocumentSummaryService`.

### SemanticChunker (Core, verified)
- **Idiot:** the cutter.
- **Dot-connector:** sentence boundaries, headings, structural blocks and transitions instead of fixed character slicing; also supplies the metadata later stages need.
- **Expert:** 1,951 lines; runs after normalised text and structured elements exist.

### Sentence boundary (Core, verified)
- **Idiot:** don't cut in the middle of a sentence.
- **Dot-connector:** the smallest ordinary split point; breaking inside one hurts meaning, offsets and citations.
- **Expert:** `NLTokenizer` sentence segmentation before accumulation toward the target size.

### Sibling group (Core, verified)
- **Idiot:** cards from the same section know they're related.
- **Dot-connector:** one precise hit can pull its neighbours without a global search.
- **Expert:** assigned at ingestion; used by `ParentDocumentService` after rerank, with Jaccard dedup above 80% overlap.

### Target chunk size (Core, verified)
- **Idiot:** the size the cutter aims for.
- **Dot-connector:** balances completeness against precision and the token limit.
- **Expert:** resolved by document plan; largest target 260, smallest 100.

### Tokenizer-model pairing (Core, verified)
- **Idiot:** use the ruler that came with the reader.
- **Dot-connector:** a valid tensor from the wrong tokenizer represents the wrong text and quietly wrecks retrieval.
- **Expert:** recorded in `EmbeddingFingerprint`; validated when a provider is selected or rebuilt.

### Word-piece token (Core, verified)
- **Idiot:** the pieces the model actually reads; sometimes a word, sometimes half of one.
- **Dot-connector:** limits are in tokens, not words, and technical text burns them fast.
- **Expert:** produced immediately before inference for embedding and reranking; MiniLM vocabulary.
# Module 05. Embeddings and vector semantics

Thirty-three concepts. Turning meaning into coordinates: the one genuinely strange idea in the app, and the machinery that keeps it honest.

## The ladder

**Like you're five.** Imagine a big map where things that mean the same sit close together. Dog and puppy are neighbours. Dog and tax return are far apart. Every card gets a pin on the map. When you ask a question, your question gets a pin too, and the phone looks at which cards are pinned nearby.

**Like an idiot.** An embedding is a list of 384 numbers that a small model produces from a chunk of text. Those numbers are coordinates. Chunks about similar things get similar coordinates. To search, embed the question the same way and find the closest chunks. That's how "what oil does my car take" finds "SAE 0W-20 synthetic" with zero words in common.

**Like less of an idiot.** The model is MiniLM-L6-v2, run through Core ML, or through Apple's newer Core AI path on the 27 operating systems. It reads the tokens, produces one vector per token, and the app averages those (ignoring padding) into one vector for the chunk, then scales it to length one. Length one matters: comparing two unit vectors is a single multiplication, which makes searching a whole library cheap. A library records a fingerprint of the model, dimension, tokenizer and pooling, and refuses to mix vectors from different fingerprints, because two 384-number lists from two different models are not in the same space and comparing them is meaningless.

**Average Joe.** Why 384? It's what this model makes, and it's small enough that a whole library's vectors stay in one file the phone can read without loading it. Why does the phone need to "pool"? Because the model doesn't export a sentence vector, it exports token vectors, and averaging them correctly under the attention mask turned out to be load-bearing; there's a whole engineering doc about re-exporting the model so pooling was right. Why is "on the Neural Engine" not a true sentence? Because the app can only tell Core ML which processors it's allowed to use, and Core ML decides.

**Dot-connector.** The provider is a protocol, and the fingerprint is the contract. Four providers exist: Core ML MiniLM (default), Core AI MiniLM (default on iOS 27 and macOS 27, same vector space, and saved Core ML defaults are migrated to it), NLContextualEmbedding and NLEmbedding (512-dimension compatibility options, different spaces), and an Apple Foundation Models provider that is a 1,024-dimension placeholder and does nothing. Switching a library between spaces means re-embedding everything, which is blocked while ingestion runs. The model is not loaded at launch; it loads on the first embed. The query is embedded with the same provider as the documents, and a semantic query cache can skip that step for a repeated question.

**Expert.** `CoreMLSentenceEmbeddingProvider`: tokenise, fill three pre-allocated `MLMultiArray` inputs of length 512 (ids, mask, type), predict, `meanPool` under the attention mask, L2 normalise; validate dimension, finite values, non-empty. `makeModel(computeUnits:)` takes the unit set from `DeviceCapabilityService`'s GPU execution profile: Efficiency and Balanced request `.cpuAndNeuralEngine`; Performance and Maximum request `.all`. Batches over four texts run in a task group of width `embeddingConcurrency` (2 to 64 by tier). `EmbeddingService` is the actor that owns provider selection, loading, validation, batching, caching and errors. `EmbeddingFingerprint` pins provider, model, dimension, tokenizer, pooling. `CoreAISentenceEmbeddingProvider` uses Apple's Core AI compilation path and exposes no compute-unit control. The 2026-08-26 fix corrected Maximum from `.cpuAndGPU` (which excluded the Neural Engine) to `.all`.

**Expert's expert.** Three corrections to the word bank. "Neural Engine, status Core" overstates: five lines in the app permit it, none place work there, and Core AI exposes nothing; say "requested." "Core AI, Conditional" understates: on the 27 systems `SettingsStore` makes it the default and migrates. And the Opus page's "generated on the Neural Engine through Apple's newer on-device inference path" collapses two different providers into one sentence. Also worth knowing: the zero-vector fallback exists so a provider failure doesn't corrupt array shape, which means a zero vector can be persisted and will simply never match anything; validation is what should catch it.

## Every concept

### Apple Foundation Models embedding provider (Dormant, verified as a placeholder)
- **Idiot:** a plug for a future socket. Nothing behind it.
- **Dot-connector:** a 1,024-dimension scaffold that keeps the provider interface ready for an Apple embedding capability that isn't there.
- **Expert:** `AppleFMEmbeddingProvider.swift`; must not be described as a shipped embedder.

### Attention mask (Core, verified)
- **Idiot:** a list of which slots are real words and which are empty filler.
- **Dot-connector:** without it, pooling would average in the padding and the vector would depend on batch shape instead of text.
- **Expert:** built with the token IDs into the 512-length input; reused for masked pooling.

### Attention-masked mean pooling (Core, verified)
- **Idiot:** average the word vectors, skipping the filler.
- **Dot-connector:** the model exports token states, not a sentence vector; correct pooling is load-bearing for retrieval quality.
- **Expert:** `meanPool` in the Core ML provider after inference, before L2 normalisation; see `EMBEDDING_MEAN_POOLING_REEXPORT.md`.

### Bi-encoder (Core, verified)
- **Idiot:** question and passage are each turned into a pin separately, then compared.
- **Dot-connector:** independent passage vectors can be precomputed once at ingestion, which is what makes searching a corpus feasible on a phone; the cross-encoder in module 08 is the slow, smarter opposite.
- **Expert:** the first semantic stage; `CoreMLSentenceEmbeddingProvider` plus `HybridSearchService`.

### Core AI sentence provider (Conditional, default on the 27 systems)
- **Idiot:** the same model, run through Apple's newer engine on newer phones.
- **Dot-connector:** same 384-dimension space, so no rebuild; the runtime changed, the coordinates didn't.
- **Expert:** `CoreAISentenceEmbeddingProvider`; `SettingsStore` defaults to it on iOS 27 and macOS 27 and migrates saved Core ML defaults; exposes no placement control.

### Core ML sentence provider (Core, verified)
- **Idiot:** the default reader-into-numbers.
- **Dot-connector:** loads the bundled model, builds tensors, runs inference, pools, normalises; Core ML schedules the work across processors.
- **Expert:** `CoreMLSentenceEmbeddingProvider`; compute units from the GPU profile; loads on first `embed()`.

### Cosine similarity (Core, verified)
- **Idiot:** how close two pins are, as an angle.
- **Dot-connector:** compares direction, not size, so a long chunk and a short chunk about the same thing score alike.
- **Expert:** dot product over the product of norms; with unit vectors it is the dot product alone. `BNNSVectorDatabase`.

### Default MiniLM provider (Core, verified)
- **Idiot:** the specific little model the app ships.
- **Dot-connector:** compact, local, fast exact similarity, manageable storage.
- **Expert:** MiniLM-L6-v2, 384 dimensions, through Core ML; provenance in `THIRD_PARTY_NOTICES.md`.

### Document-chunk embedding (Core, verified)
- **Idiot:** the pin for each card.
- **Dot-connector:** made once at ingestion from the prefixed text; searched by every later question.
- **Expert:** written after validation, before the document becomes queryable.

### Dot product (Core, verified)
- **Idiot:** multiply matching numbers and add them up.
- **Dot-connector:** with normalised vectors it is cosine similarity, and it maps directly onto Accelerate, BNNS and Metal.
- **Expert:** `vDSP_dotpr` per vector, `vDSP_mmul` for the batch path, Metal kernel above 1,000.

### Embedding (Core, verified)
- **Idiot:** the pin.
- **Dot-connector:** a fixed-length numeric representation whose geometry approximates meaning; lets the app find related text under different words.
- **Expert:** 384 floats, produced by `EmbeddingService` for chunks at ingestion and for the query at search time.

### Embedding batch (Core, verified)
- **Idiot:** do several cards at once.
- **Dot-connector:** amortises model setup and uses the matrix hardware properly.
- **Expert:** batches over four texts run in a task group; batch size 8 to 512 by device tier.

### Embedding concurrency (Support, verified)
- **Idiot:** how many batches run at the same time.
- **Dot-connector:** too few underuses hardware; too many fights Vision for memory.
- **Expert:** `embeddingConcurrency` from `DeviceCapabilityService`, 2 to 64 by tier.

### Embedding dimension (Core, verified)
- **Idiot:** how many numbers are in a pin: 384.
- **Dot-connector:** a mismatch is not a quality difference, it's incompatibility.
- **Expert:** declared by the provider, recorded in metadata, validated on write, read and before search.

### Embedding fingerprint (Core, verified)
- **Idiot:** the map's serial number.
- **Dot-connector:** provider, model, dimension, tokenizer and pooling; vectors with different fingerprints are never compared.
- **Expert:** `EmbeddingFingerprint`, written with library metadata, checked before ingestion, loading, querying and migration. An unknown fingerprint means "do not act," not "mismatched."

### Embedding space (Core, verified)
- **Idiot:** the map itself.
- **Dot-connector:** equal vector length does not mean same map; different models make unrelated geometries at the same dimension.
- **Expert:** a library stays in one space until a full re-embed migrates it.

### Embedding translation target (Conditional, verified)
- **Idiot:** translate a copy before pinning it.
- **Dot-connector:** cross-language retrieval improves when all vectors share a language; the original stays for display.
- **Expert:** `TranslationService` before embedding, only when configured.

### Embedding validation (Core, verified)
- **Idiot:** check the pin isn't broken.
- **Dot-connector:** NaN values, wrong widths and silent truncation all serialise fine and poison every search.
- **Expert:** dimension, finiteness, non-empty; after provider output and at vector-store boundaries.

### EmbeddingProvider (Core, verified)
- **Idiot:** the plug shape every embedder has to fit.
- **Dot-connector:** the library must know exactly which map made its pins while the engine picks any available implementation.
- **Expert:** protocol: model identity, dimension, sequence limit, availability, batching, `embed`.

### EmbeddingService (Core, verified)
- **Idiot:** the manager of the pin-maker.
- **Dot-connector:** one owner for provider selection, loading, validation, batching, caching and errors, so documents and queries can't drift onto different providers.
- **Expert:** an actor between chunk or query text and the vector store on both paths.

### L2 norm (Core, verified)
- **Idiot:** the length of the arrow.
- **Dot-connector:** you need it to normalise, and it's stored separately so the batch path can divide after the fact.
- **Expert:** sqrt of the sum of squares; persisted in `_norms.bin`.

### L2 normalization (Core, verified)
- **Idiot:** shrink or stretch every arrow to length one.
- **Dot-connector:** turns cosine into a dot product and keeps providers numerically consistent.
- **Expert:** the last transformation before validation and persistence.

### NLContextualEmbedding provider (Conditional, verified)
- **Idiot:** Apple's built-in embedder, a different map.
- **Dot-connector:** 512 dimensions, a compatibility option, incompatible with MiniLM libraries.
- **Expert:** per-library selectable; requires matching fingerprint and a rebuild on change.

### NLEmbedding provider (Conditional, verified)
- **Idiot:** an older Apple embedder that averages word vectors.
- **Dot-connector:** a fallback where the sentence model is unavailable; also 512 dimensions, also a different map.
- **Expert:** isolated to libraries configured for it.

### Provider agreement test (Support, verified)
- **Idiot:** a test that two embedders make the same pins.
- **Dot-connector:** a new backend must preserve the space existing libraries expect, not merely compile.
- **Expert:** `EmbeddingProviderAgreementTests`; migration validation, not a query stage.

### Query embedding (Core, verified)
- **Idiot:** the pin for your question.
- **Dot-connector:** same provider, same space, made after rewriting and expansion decisions.
- **Expert:** Step 2 of `queryInternal`; skipped on a semantic cache hit.

### Re-embedding (Core, verified)
- **Idiot:** redo every pin with a new map.
- **Dot-connector:** required when model, dimension, tokenizer or pooling changes; partial migration would mix maps.
- **Expert:** explicit rebuild in `RAGService`; blocked during ingestion.

### Semantic query cache (Support, verified as `semantic_query_cache`)
- **Idiot:** remember the pin for a question you've asked before.
- **Dot-connector:** skips the embedding call for repeated normalised questions.
- **Expert:** a SQLite table with a container index; checked before Step 2, updated after success.

### Sentence embedding (Core, verified)
- **Idiot:** one pin for the whole card.
- **Dot-connector:** a token-level model output isn't searchable as one passage; pooling reduces it.
- **Expert:** consumes prefixed, tokenised chunk text; produces the stored vector.

### Special tokens (Core, verified)
- **Idiot:** the "start" and "end" markers the model expects.
- **Dot-connector:** the model was trained with them, and they count against the limit.
- **Expert:** `[CLS]` and `[SEP]` inserted by the tokenizer before the 510 ceiling is evaluated.

### Token IDs (Core, verified)
- **Idiot:** the numbers that stand for the words.
- **Dot-connector:** their meaning depends entirely on the tokenizer-model pairing.
- **Expert:** integers into the 512-length `input_ids` array.

### Token-state tensor (Core, verified)
- **Idiot:** one vector per word, before averaging.
- **Dot-connector:** what the model actually emits; pooling turns it into one vector.
- **Expert:** model output reduced immediately by masked mean pooling.

### Zero-vector fallback (Support, verified)
- **Idiot:** if the pin-maker fails, put in a blank pin instead of crashing.
- **Dot-connector:** keeps array shape valid; the blank carries no meaning and validation should flag it.
- **Expert:** error containment inside `EmbeddingService` before persistence.
# Module 06. Lexical indexing, SQLite, and vector persistence

Forty-nine concepts. Two filing systems for the same cards, plus the machinery that searches the vectors, and the honest answer about the GPU.

## The ladder

**Like you're five.** Every card is filed twice. Once in an alphabetical index of the exact words on it, and once as a pin on the meaning map. The index is for when you know the exact word. The map is for when you don't.

**Like an idiot.** The word index is SQLite, the little database engine built into the phone, using its full-text search feature. It ranks by a formula called BM25, which is good at part numbers, names and rare words. The vector store is one flat file of numbers per library that the phone reads directly, plus a file of the vector lengths and a file of metadata saying which vector belongs to which chunk. Writes are atomic: the new files are written on the side and swapped in.

**Like less of an idiot.** Neither index is enough alone, which is why both exist. FTS5 keeps nine tables; the `chunks` table indexes section title, section path and content with weights 10, 5 and 1, so a match in a heading beats the same word in prose. The Porter stemmer makes "run" match "running." Write-ahead logging lets the UI read while ingestion writes, and a three-second busy timeout stops normal contention from becoming an error. Vectors are memory-mapped, so a library of tens of thousands of chunks costs almost no heap to search. Searching is an exact scan over every vector; there's no approximate index, because at phone-library scale exact is fast enough and never loses recall.

**Average Joe.** Where does the GPU come in? Only here, and only for one job: comparing your question's vector against a big library. If the library has a thousand or more vectors and a Metal device exists, the mapped buffer is handed to a small Metal program with no copy. Otherwise it's the CPU with Accelerate. That's the entire honest GPU story for search. The user's GPU profile setting does not decide this; it decides other things.

**Dot-connector.** The two stores have different failure shapes. SQLite is transactional inside itself. The vector store is atomic inside itself. Nothing is transactional across the two, which is why the ingestion module talks about a window where a document is in one and not the other. Also, the `VectorStoreRouter` keeps one live store instance per container file on purpose: two instances mapping the same file would be two truths about one library. And "persistentJSON" in a settings file is a historical name that now means the BNNS binary store, kept so old libraries keep working.

**Expert.** `SQLiteFullTextService` is the actor owning the connection. Nine tables: FTS5 virtual tables `documents`, `chunks`, `document_pages`, `documents_vocab`; ordinary tables `chunk_structured`, `chunk_table_rows`, `document_content`, `document_meta`, `semantic_query_cache`. `chunks` uses `tokenize='porter unicode61'`; unindexed columns get weight 0 in the `bm25()` call; `PRAGMA journal_mode=WAL` and `busy_timeout=3000`. Fallback BM25 in `HybridSearchService`: k1 1.5, b 0.5, lowered from 0.75 because chunks are near-uniform in length. `BNNSVectorDatabase`: `_vectors.bin` (contiguous Float32), `_norms.bin`, metadata JSON, mmap on load; `search` switches at `count >= 1000 && isGPUAvailable` (a Metal device and command queue) to `GPUComputeService.batchCosineSimilarity`, which picks a threadgroup kernel at 1,000 or more documents when safe, else a SIMD kernel; below that, CPU: one `vDSP_mmul` over the mapped buffer when the count is at least the device's batch threshold (16 on M-series, `Int.max` on unsupported), else per-vector `vDSP_dotpr`. Partial top-k selection avoids sorting the whole corpus. Metal buffers come from a size-bucketed pool with a residency set on supporting OS versions; the pool clears under memory warnings on iOS.

**Expert's expert.** Correction to the bank's caveat on the GPU threshold: the route does not depend on the user's GPU policy. The profile gates Core ML compute units, ingestion embedding units, the MMR similarity matrix (above 50 candidates and only if "use Metal for vector ops" is on) and concurrency ceilings. The word bank's "nine-column chunks FTS schema" is real and the column order is part of the scoring contract: a missing weight shifts every later weight silently. The `Vectura` adapter and its HNSW are kept only for libraries configured that way; they are not the default and not maintained as the architecture.

## Every concept

### 1,000-chunk GPU threshold (Conditional, verified)
- **Idiot:** small library, CPU; big library, graphics chip.
- **Dot-connector:** GPU setup costs fixed time; below a thousand vectors the CPU wins.
- **Expert:** `count >= 1000` in `BNNSVectorDatabase.search`; the second condition is `isGPUAvailable`; the profile is not consulted.

### _norms.bin (Core, verified)
- **Idiot:** the file of arrow lengths.
- **Dot-connector:** precomputed so the CPU batch path can normalise after one big multiply.
- **Expert:** written with persistence, mapped beside the vectors.

### _vectors.bin (Core, verified)
- **Idiot:** the file of all the pins.
- **Dot-connector:** flat Float32 layout is what makes mmap and matrix math possible with no object overhead.
- **Expert:** written at ingestion and rebuild, mapped for every dense search.

### Atomic vector-store persistence (Core, verified)
- **Idiot:** write the new files beside the old, then swap.
- **Dot-connector:** a crash between independent writes would pair new metadata with old vectors.
- **Expert:** temp files plus coordinated replacement; the final vector publication step.

### BM25 (Core, verified)
- **Idiot:** the formula that ranks exact-word matches.
- **Dot-connector:** rewards rare, informative terms, saturates on repetition, penalises length; the exact-language half of hybrid search.
- **Expert:** FTS5's native `bm25()` with column weights; the in-process fallback uses k1 1.5, b 0.5.

### BM25 b (Core, verified) and BM25 k1 (Core, verified)
- **Idiot:** two dials: how much length matters, how fast repeats stop counting.
- **Dot-connector:** b lowered to 0.5 because chunks are near-uniform in length; k1 1.5 balances one precise hit against many.
- **Expert:** `HybridSearchService.swift:48-49`; the same values in `RAGEngine`'s fallback.

### BNNSVectorDatabase (Core, verified)
- **Idiot:** the pin store.
- **Dot-connector:** compact metadata, contiguous vectors, precomputed norms, mmap, Accelerate, optional Metal; a serverless store for Apple unified memory.
- **Expert:** `Services/VectorStore/BNNSVectorDatabase.swift`; receives vectors after embedding, serves dense candidates before fusion.

### Busy timeout (Core, verified)
- **Idiot:** wait a few seconds if the database is busy, don't error.
- **Dot-connector:** ingestion and a query touch SQLite together routinely.
- **Expert:** `PRAGMA busy_timeout=3000`.

### chunk_structured table (Core, verified)
- **Idiot:** where tables, lists and warnings are kept as data, not prose.
- **Dot-connector:** the flattened search string loses structure; this keeps it recoverable.
- **Expert:** written with chunk records; read by extractive and response paths.

### chunk_table_rows table (Core, verified)
- **Idiot:** every table row, stored as its own row.
- **Dot-connector:** exact lookup needs the relationship among a row's cells.
- **Expert:** populated by `StructuredDocumentParser`; queried by `SpecificationExtractor` before regex fallback.

### chunks table (Core, verified)
- **Idiot:** the main word index of cards.
- **Dot-connector:** returns the same chunk IDs the vector search returns, so fusion can merge them.
- **Expert:** FTS5, nine columns, weights 10/5/1 on title, path, content.

### Container column scoping (Core, verified)
- **Idiot:** one database, a library column on every row.
- **Dot-connector:** simpler migrations than a file per library; isolation enforced by the filter.
- **Expert:** every document and chunk query includes the active container UUID.

### Content weight (Core, verified)
- **Idiot:** body text counts once.
- **Dot-connector:** searchable, but headings outrank it.
- **Expert:** weight 1.0 in the `bm25()` call.

### CPU vector path (Core, verified)
- **Idiot:** the normal-processor search.
- **Dot-connector:** below a thousand vectors, or without a GPU; SIMD is faster than GPU setup at that size.
- **Expert:** `vDSP_mmul` above the batch threshold, `vDSP_dotpr` per vector below it.

### Document-length normalization (Core, verified)
- **Idiot:** long cards don't win just for being long.
- **Dot-connector:** a short spec row can beat a long chapter that mentions the term in passing.
- **Expert:** the b term in BM25.

### document_content table (Core, verified)
- **Idiot:** the whole document's text.
- **Dot-connector:** for direct extraction and rebuilding citations, which chunks alone can't do.
- **Expert:** persisted after extraction; read by direct-answer, citation and maintenance paths.

### document_meta table (Core, verified)
- **Idiot:** counts, dates, size, which library.
- **Dot-connector:** typed metadata needs exact access, not full-text tokenisation.
- **Expert:** written with the document commit.

### document_pages table (Core, verified)
- **Idiot:** the word index per page.
- **Dot-connector:** page search, citation navigation and cross-reference repair need page granularity.
- **Expert:** FTS5; populated during extraction.

### documents table (Core, verified)
- **Idiot:** the word index of whole documents.
- **Dot-connector:** written early in extraction, before chunking; the source of the "searchable at document level but not chunk level" window.
- **Expert:** FTS5.

### documents_vocab (Support, verified)
- **Idiot:** the list of words this library actually uses.
- **Dot-connector:** query expansion from the corpus's own language beats a generic thesaurus.
- **Expert:** FTS5 vocabulary view; read by `ContainerVocabularyService` at Step 0.

### Exact vector scan (Core, verified)
- **Idiot:** check every pin.
- **Dot-connector:** no recall loss, no index maintenance, fast enough with mmap and SIMD or Metal at phone scale.
- **Expert:** the default dense operation before partial top-k.

### FTS column weight (Core, verified)
- **Idiot:** a multiplier per column.
- **Dot-connector:** matches in intentional fields count more than matches in prose.
- **Expert:** applied inside SQLite's ranking before results leave.

### FTS5 (Core, verified)
- **Idiot:** SQLite's built-in search engine.
- **Dot-connector:** substring `LIKE` is too slow and has no ranking; FTS5 has an inverted index, tokenisation, corpus statistics.
- **Expert:** four virtual tables in the schema.

### GPU vector path (Conditional, verified)
- **Idiot:** the graphics-chip search.
- **Dot-connector:** at a thousand or more vectors with Metal present, the mapped buffer goes to a kernel with no copy.
- **Expert:** `GPUComputeService.batchCosineSimilarity`; threadgroup kernel at 1,000+ when safe, else SIMD kernel; the bank's "enabled execution profile" condition is wrong.

### HNSW (Historical, verified only in the Vectura adapter)
- **Idiot:** a shortcut index the app doesn't use.
- **Dot-connector:** approximate graphs trade recall for speed at scales this app doesn't reach.
- **Expert:** associated with `VecturaVectorDatabase`; not part of the default pipeline.

### Inverse document frequency (Core, verified)
- **Idiot:** rare words count more.
- **Dot-connector:** identifiers and technical terms discriminate better than words that appear everywhere.
- **Expert:** log((N − df + 0.5) / (df + 0.5) + 1) in the fallback; FTS5 computes its own.

### Inverted index (Core, verified)
- **Idiot:** a list from each word to the cards it's on.
- **Dot-connector:** jump straight to matches instead of scanning every card.
- **Expert:** built by FTS5 at ingestion.

### Memory mapping (Core, verified)
- **Idiot:** read the file as if it were memory, without copying it.
- **Dot-connector:** a big library stays searchable with low resident memory and no copy per query.
- **Expert:** on store load; pointers handed to CPU or GPU search.

### Metal buffer pool (Support, verified)
- **Idiot:** reuse GPU memory instead of allocating fresh every time.
- **Dot-connector:** allocation dominates short GPU operations.
- **Expert:** size-bucketed `MTLBuffer`s with tier limits; cleared on memory warnings (iOS).

### Metal residency set (Conditional, verified)
- **Idiot:** keep the hot GPU buffers pinned.
- **Dot-connector:** fewer page faults for persistent vector workloads.
- **Expert:** `createResidencySet` on supporting OS versions; `makeResident` and `evictFromResidency`.

### Nine-column chunks FTS schema (Core, verified)
- **Idiot:** the chunk table has nine columns and the weights line up with them.
- **Dot-connector:** column order is part of the scoring contract.
- **Expert:** a missing weight shifts every later one silently; covered by `HybridSearchServiceTests`.

### Partial top-k selection (Core, verified)
- **Idiot:** keep the best few while scanning; don't sort everything.
- **Dot-connector:** you want tens of hits, not an ordering of thousands.
- **Expert:** during dense search before `RetrievedChunk` construction.

### persistentJSON vector-store label (Historical, verified)
- **Idiot:** an old name that still works.
- **Dot-connector:** it now routes to the BNNS binary store; kept so existing libraries load.
- **Expert:** interpreted by `VectorStoreRouter` from `KnowledgeContainer`.

### Porter tokenizer (Core, verified) and Stemming (Core, verified)
- **Idiot:** "run" finds "running."
- **Dot-connector:** grammatical variants become one search term.
- **Expert:** `porter unicode61` on the FTS tables.

### Section-path boost (Core, verified) and Section-title boost (Core, verified)
- **Idiot:** headings count five or ten times more than body text.
- **Dot-connector:** headings are concise labels and answer navigation questions directly.
- **Expert:** weights 5.0 and 10.0 in the `bm25()` call.

### SQLite (Core, verified) and SQLiteFullTextService (Core, verified)
- **Idiot:** the database and the one object allowed to touch it.
- **Dot-connector:** one serialised owner prevents connection races and keeps schema and ranking policy in one place.
- **Expert:** an actor; 3,608 lines; opens on first use, not at launch.

### SQLite transaction (Core, verified)
- **Idiot:** all the rows go in together or not at all.
- **Dot-connector:** metadata, chunks, pages and structured rows must never be partially visible.
- **Expert:** wraps multi-row ingestion, deletion and migration.

### Term frequency (Core, verified)
- **Idiot:** how often the word appears on the card.
- **Dot-connector:** more is better, with diminishing returns so stuffing doesn't win.
- **Expert:** the k1-saturated term in BM25.

### UNINDEXED FTS column (Core, verified)
- **Idiot:** stored on the row but not searchable.
- **Dot-connector:** IDs and control fields travel with hits without polluting the vocabulary.
- **Expert:** weight 0 in `bm25()`.

### Vector metadata JSON (Core, verified)
- **Idiot:** the list saying which pin is which card.
- **Dot-connector:** the float array has no identity, page, text or deletion semantics on its own.
- **Expert:** written atomically with vectors and norms; loaded before results are materialised.

### VectorDatabase protocol (Core, verified)
- **Idiot:** the plug shape for pin stores.
- **Dot-connector:** store, load, search, delete, audit; lets the physical store change under a stable contract.
- **Expert:** `VectorDatabase.swift`, beneath the router, above BNNS or Vectura.

### VectorStoreRouter (Core, verified)
- **Idiot:** picks the right pin store for the library.
- **Dot-connector:** one library, one store implementation, one live instance; the controlled switch point for migrations.
- **Expert:** consulted before persistence and every dense retrieval; compares an on-disk signature before reloading, which is what made the idle churn cheap.

### VecturaVectorDatabase (Conditional, verified)
- **Idiot:** the alternative pin store some old libraries use.
- **Dot-connector:** kept for compatibility, not the architecture.
- **Expert:** selected only when the library's vector kind requests it.

### Virtual table (Core, verified)
- **Idiot:** a table whose insides are run by a plugin.
- **Dot-connector:** FTS5 exposes search and ranking through SQL while keeping its own index.
- **Expert:** `documents`, `chunks`, `document_pages`, `documents_vocab`.

### Write-ahead logging (Core, verified)
- **Idiot:** write changes to a log first, merge later.
- **Dot-connector:** readers keep reading while ingestion writes; better crash recovery.
- **Expert:** `journal_mode=WAL` at open.
# Module 07. Query understanding, intent, and execution planning

Forty-five concepts. Understanding the question before searching: what kind of answer is wanted, how hard it is, and what plan to run.

## The ladder

**Like you're five.** Before the librarian goes looking, she reads your question twice and asks herself: does this person want one fact, or the whole story? Is this easy or hard? Then she decides how much running around to do.

**Like an idiot.** The app profiles your question before it searches. Lookup, table lookup, procedure, comparison, summary, investigation, computation, findings: each wants different evidence and a different-shaped answer. It rates complexity, decides whether this is a one-pass job or a loop, may clean up your question, may expand it with the library's own vocabulary, and may write an imaginary answer just to search with. All of that gets resolved once, up front, into a plan.

**Like less of an idiot.** Two objects matter. `QueryProfile` describes the question: word count, entities, answer intent, search intent, routing class, complexity. `QueryExecutionPlan` says what the engine will do about it: direct or decomposed, tools or not, escalate to agentic or not, which response strategy. The runtime coordinator resolves both plus quality mode, PCC eligibility and adaptive configuration before any search runs. There are exactly three ways a run becomes agentic: the mode is Deep Think or Maximum, the user pressed Go Deeper, or the planner escalated a Standard query. A `GroundedAnswerPolicy` then decides whether the answer should be extracted by rules, extracted by a tightly constrained prompt, or synthesised with citations.

**Average Joe.** Why rewrite the question? Users type short, vague, conversational questions ("what about the other one?") and the index was built from long, specific text. A standalone rewrite resolves the pronouns from conversation memory. HyDE has the model write a plausible answer passage and searches with that, because passages land near passages on the map and questions don't; it's off in Standard on purpose, because a hypothetical can poison exact lookups. Corpus vocabulary expansion uses words that actually exist in your library instead of a generic thesaurus that would drag in unrelated meanings.

**Dot-connector.** Two things people conflate. Query complexity (trivial, standard, complex, agentic) is about how much work is justified; answer intent is about the shape of the result. A trivial lookup and a trivial summary get different packing. Also: "touchy" is decided here in policy terms but consumed in module 12, where it raises the retrieval-confidence bar from 0.40 to 0.55. And the semantic query cache lives in module 05's territory but is checked here, before embedding, keyed on the normalised question.

**Expert.** `QueryRuntimeCoordinator.resolveContext` is the first call in `queryInternal`: reads `SettingsStore` (summaries, HyDE, rewriting, compression flags), resolves `RAGQualityMode`, computes `AgenticDecision` (`.agentic`, `.forcedAgentic`, `.plannerEscalated`, none), checks the PCC suppression cooldown, builds `AdaptivePipelineConfig`. `QueryProfileService` builds the profile; `QueryComplexityAnalyzer` scores length, conjunctions, comparisons, reasoning markers, entities and intent; `QueryEnhancementService` classifies intent and expands; `QueryRewriterService` rewrites standalone; `HyDEService` generates the hypothetical only when `usesHyDE` is true (false in Standard); `ContainerVocabularyService` reads `documents_vocab`; `QueryRouterService` decides overview versus detail and hands overview to `RAPTORSummaryRouter`; `SpecificationExtractor` pulls the primary entity and descriptive keywords for spec-heavy questions; `GroundedAnswerPolicy` picks deterministic extraction, direct-extraction prompting, constrained synthesis or source-only verification.

**Expert's expert.** The rewrite and HyDE are the two generative steps before retrieval, and they can both mislead: a rewrite that drops a qualifier retrieves the wrong thing confidently. That is why the original user message is never replaced in the conversation, only the effective search string. The planner-escalation path is also the one most likely to surprise a user who chose Standard, because it changes the run from one pass to a loop without a mode change on screen; the diagnostics record it as `plannerEscalated`. And "Subquestion" is the one concept in the whole bank whose name does not appear as an identifier in code; the behaviour exists inside the orchestrator's decomposition under other names.

## Every concept

### Agentic query (Conditional, verified)
- **Idiot:** a question that takes several rounds of looking and thinking.
- **Dot-connector:** discovery, gap assessment, reformulation and synthesis that can't be planned in one shot.
- **Expert:** routed into `AgenticOrchestrator` after the coordinator resolves the plan; module 11.

### Answer intent (Core, verified)
- **Idiot:** what shape of answer you want.
- **Dot-connector:** lookup, table lookup, procedure, comparison, summary, investigation, computation, findings; it steers boosts, expansion, extraction, packing, prompting and verification.
- **Expert:** inferred by `QueryEnhancementService`; represented in `StructuredAnswer`.

### Compare intent (Core, verified)
- **Idiot:** "which is better, A or B?"
- **Dot-connector:** needs balanced evidence for each side and explicit dimensions, not one top passage.
- **Expert:** drives decomposition, source diversity, packing, and the comparison structured type.

### Complex query (Conditional, verified)
- **Idiot:** a big question.
- **Dot-connector:** more candidates and context; may be decomposed or escalated.
- **Expert:** `QueryComplexityAnalyzer`.

### Compute intent (Conditional, verified)
- **Idiot:** "add these up for me."
- **Dot-connector:** retrieve exact operands, keep units, and mark the calculation as derived, not sourced.
- **Expert:** explicit in the structured answer contract.

### Constrained-synthesis prompt mode (Core, verified)
- **Idiot:** write it in your own words, but every sentence must point at a source.
- **Dot-connector:** procedures, comparisons and explanations need composition, still bounded by retrieved context.
- **Expert:** `GroundedAnswerPolicy` after packing, before structured generation.

### Container vocabulary expansion (Conditional, verified)
- **Idiot:** use the library's own words to widen the search.
- **Dot-connector:** corpus-native terms are safer than a generic thesaurus.
- **Expert:** `ContainerVocabularyService` over `documents_vocab`, Step 0 and enhancement.

### Cross-reference query (Conditional, verified)
- **Idiot:** the answer is on the page the first page points to.
- **Dot-connector:** manuals answer with "see page X"; the graph follows the arrow.
- **Expert:** graph or page repair after the first candidates expose the reference; `EvidenceScoringPolicyService`, `GraphIndexService`.

### Decomposed execution (Conditional, verified)
- **Idiot:** split the big question into small ones.
- **Dot-connector:** one embedding for a multi-clause question averages away parts and retrieves half an answer.
- **Expert:** `QueryExecutionPlannerService` plus the orchestrator; sub-answers accumulate before synthesis.

### Descriptive keyword (Core, verified)
- **Idiot:** the word that says which property you want: "capacity," "dosage."
- **Dot-connector:** the entity says which thing; the descriptive keyword says which attribute.
- **Expert:** `SpecificationExtractor` scoring of lexical hits, table keys and extraction candidates.

### Direct execution (Core, verified)
- **Idiot:** one question, one pass.
- **Dot-connector:** minimum latency when decomposition isn't needed.
- **Expert:** the default plan; stays Standard unless mode or policy says otherwise.

### Direct-extraction prompt mode (Conditional, verified)
- **Idiot:** copy the answer out, don't rephrase it.
- **Dot-connector:** for lookup-style questions where rules couldn't decide, minimise paraphrase.
- **Expert:** `GroundedAnswerPolicy` and the prompt compiler for extractive-first intents.

### Entity extraction from query (Core, verified)
- **Idiot:** notice the names and numbers in your question.
- **Dot-connector:** the primary entity decides which record you mean.
- **Expert:** `QueryEnhancementService` and `SpecificationExtractor` before search.

### Findings intent (Conditional, verified)
- **Idiot:** "what did the studies find?"
- **Dot-connector:** research aggregation with attribution, not a topical answer.
- **Expert:** influences planning, source-only verification and structured output.

### Forced agentic execution (Conditional, verified as `.forcedAgentic`)
- **Idiot:** you pressed Go Deeper.
- **Dot-connector:** user-requested extra search and reasoning even after the planner chose Standard.
- **Expert:** overrides at `QueryRuntimeCoordinator` resolution.

### GroundedAnswerPolicy (Core, verified)
- **Idiot:** the rule for how careful the answer has to be.
- **Dot-connector:** deterministic extraction, direct-extraction prompt, constrained synthesis, source-only verification; exact lookups don't get needlessly generated.
- **Expert:** resolved after intent classification, before extraction or generation.

### HyDE (Conditional, verified) and Hypothetical document (Conditional, verified)
- **Idiot:** write a fake answer, search with it, throw it away.
- **Dot-connector:** a passage lands near passages; a short question doesn't. The hypothetical is a probe, never evidence.
- **Expert:** `HyDEService`; `usesHyDE` is false in Standard "to prevent hypothetical hallucinations from poisoning exact lookups."

### Investigate intent (Conditional, verified)
- **Idiot:** "dig into this."
- **Dot-connector:** multiple threads and relationships; raises complexity and may trigger the loop.
- **Expert:** enhancement plus the planner.

### Keyword search intent (Core, verified)
- **Idiot:** you typed a part number.
- **Dot-connector:** exact terms matter; lexical candidates and lower extraction thresholds get more weight.
- **Expert:** `QueryProfileService` and `RetrievalPolicyService`.

### Lookup intent (Core, verified)
- **Idiot:** "what's the torque spec?"
- **Dot-connector:** precision, exact identifiers, structured extraction, low tolerance for synthesis.
- **Expert:** routes preferentially through deterministic or extractive paths.

### Overview query (Conditional, verified)
- **Idiot:** "what's this document about?"
- **Dot-connector:** summary chunks represent whole-document themes better than incidental detail.
- **Expert:** `QueryRouterService` to `RAPTORSummaryRouter`.

### Planner escalation (Conditional, verified as `.plannerEscalated`)
- **Idiot:** the app decided your easy setting wasn't enough.
- **Dot-connector:** complexity, not the mode label, controls the work; the third agentic path.
- **Expert:** resolved by the coordinator before retrieval; recorded in diagnostics.

### Primary entity (Core, verified)
- **Idiot:** the main thing your question is about.
- **Dot-connector:** "1688" beats a similar spec for a similar product; used as an override in extraction.
- **Expert:** `SpecificationExtractor`.

### Procedure intent (Core, verified)
- **Idiot:** "how do I do this, step by step?"
- **Dot-connector:** needs neighbours in order; raises sibling and parent expansion; packs in sequence.
- **Expert:** enhancement plus `RetrievalPolicyService`.

### Query complexity (Core, verified)
- **Idiot:** easy, normal, hard, or "this needs the loop."
- **Dot-connector:** trivial, standard, complex, agentic, from length, conjunctions, comparisons, reasoning markers, entities and intent.
- **Expert:** `QueryComplexityAnalyzer` before adaptive configuration and path selection.

### Query decomposition (Conditional, verified)
- **Idiot:** break it into pieces.
- **Dot-connector:** separate probes reduce averaging and make missing coverage visible.
- **Expert:** in the orchestrator and the planner before iterative retrieval; feeds the FactBank.

### Query expansion (Conditional, verified)
- **Idiot:** add synonyms and related words.
- **Dot-connector:** the document may use a term you don't know or an acronym you spelled out.
- **Expert:** `QueryEnhancementService` after profile and rewrite; extra lexical or semantic searches before fusion.

### Query normalization (Core, verified)
- **Idiot:** tidy up spaces, punctuation and case.
- **Dot-connector:** stable comparison for the cache and the heuristics.
- **Expert:** immediately after submission in `QueryProfileService` and `RAGService`.

### Query rewriting (Conditional, verified)
- **Idiot:** rephrase the question so a search engine likes it.
- **Dot-connector:** conversational phrasing lowers both lexical and dense quality; the rewrite is a generative step and can drop a qualifier.
- **Expert:** `QueryRewriterService` after profiling and conversation context, before embedding.

### Query variation (Conditional, verified)
- **Idiot:** try asking it a different way.
- **Dot-connector:** issued after weak or repetitive retrieval in the loop.
- **Expert:** orchestrator plus `RetrievalPolicyService` after evidence assessment finds a gap.

### QueryExecutionPlan (Core, verified)
- **Idiot:** the decision about what to do.
- **Dot-connector:** direct or decomposed, tools, escalation, response strategy. The profile describes; the plan acts.
- **Expert:** `QueryExecutionPlannerService`, before Standard or agentic execution begins.

### QueryProfile (Core, verified)
- **Idiot:** everything the app figured out about your question.
- **Dot-connector:** one coherent interpretation consumed everywhere instead of independent reclassification.
- **Expert:** `QueryProfileService`; consumed by retrieval, packing, extraction and orchestration policy.

### Response strategy (Core, verified)
- **Idiot:** how the answer will be produced.
- **Dot-connector:** deterministic extraction, constrained synthesis, extractive summarisation, agentic synthesis; falls back when a path lacks confidence.
- **Expert:** `GroundedAnswerPolicy` and the planner.

### Routing classification (Core, verified)
- **Idiot:** direct, cross-topic, overview.
- **Dot-connector:** search architecture responds to the shape of the need, not just the words.
- **Expert:** `QueryRouterService` into `QueryProfile`; consumed by parent expansion and planning.

### Search intent (Core, verified) and Semantic search intent (Core, verified)
- **Idiot:** should the app match words or meaning?
- **Dot-connector:** a model number leans lexical; a paraphrased concept leans dense; hybrid always keeps both.
- **Expert:** `QueryProfileService`; changes weights, routes and thresholds.

### Specification-heavy query (Conditional, verified)
- **Idiot:** you want an exact number or code.
- **Dot-connector:** structured and numeric boosts, stricter unit verification, spec sniper, corrective retrieval.
- **Expert:** `SpecificationExtractor` and `EvidenceScoringPolicyService`.

### Standalone rewrite (Conditional, verified)
- **Idiot:** "it" becomes "the 1688 camera head."
- **Dot-connector:** retrieval can't see the conversation unless it's folded into the query; the original message is kept.
- **Expert:** `QueryRewriterService` with `ConversationMemoryService`.

### State-lookup query (Conditional, verified)
- **Idiot:** "what does the flashing orange light mean?"
- **Dot-connector:** the answer is a pairing of state and meaning; generic similarity picks the wrong row.
- **Expert:** `EvidenceScoringPolicyService` colour/state anchors.

### Subquestion (Conditional, behaviour verified, identifier not)
- **Idiot:** one small piece of a big question.
- **Dot-connector:** coverage and stopping measured per requirement, not by answer length.
- **Expert:** decomposition in `AgenticOrchestrator` and `AgenticPolicyService`; the only bank concept with no matching identifier name.

### Summarize intent (Core, verified)
- **Idiot:** "give me the gist."
- **Dot-connector:** coverage and low redundancy over one strong hit; can route to summary chunks or extractive sentences.
- **Expert:** `QueryRouterService` and `ExtractiveSummarizationService`.

### Table-lookup intent (Core, verified)
- **Idiot:** the answer is in a cell.
- **Dot-connector:** flattened prose finds the right table and the wrong cell; structured lookup keeps the relationship.
- **Expert:** `SpecificationExtractor` structured-row path before generative fallback.

### Touchy query (Core, verified)
- **Idiot:** medical, legal, money, safety, dosage.
- **Dot-connector:** a wrong critical number costs more than a missing adjective; thresholds go up.
- **Expert:** categories medical, legal, financial, safety, dosage, drug, medication; tau rises to 0.55; strict adds regulatory and compliance.

### Trivial query (Core, verified)
- **Idiot:** an easy one.
- **Dot-connector:** smaller candidate set, skip HyDE and iteration; expensive stages on easy lookups add latency for nothing.
- **Expert:** `QueryComplexityAnalyzer` plus `AdaptivePipelineOptimizer` minimum configuration.
# Module 08. Retrieval, fusion, reranking, and evidence expansion

Sixty concepts. Finding the evidence: two searches in parallel, one merged ranking, a second opinion from a cross-encoder, then diversity and neighbours.

## The ladder

**Like you're five.** Two helpers run off at the same time. One looks for your exact words. The other looks at the meaning map. They come back with two piles, which get shuffled into one. Then a slow, careful reader goes through the top of the pile with your question in one hand and each card in the other, and reorders them. Then the librarian throws out the cards that don't fit, spreads out the ones that all say the same thing, and grabs the card before and after each good one.

**Like an idiot.** Vector search and keyword search fail differently, so both run and their results are merged by rank position. A cross-encoder then rescores the short list by reading question and passage together, which is much more accurate and much too slow for the whole library. Chunks under a similarity floor are dropped. A diversity step stops five copies of the same paragraph from crowding out a second document. Neighbours and parent sections get pulled in. If the result is weak, a corrective search looks specifically for the shape of evidence the question needs: a table row, a number, a referenced page.

**Like less of an idiot.** Reciprocal rank fusion gives each chunk points for its rank in each list (1 over k plus rank, k = 60), weighted 0.7 for the vector list and 0.3 for keywords, and needs no score calibration because the two arms produce scores on different scales. Keyword-only hits that fell below the cut are re-attached, so an exact part number is never buried by paraphrase. The cross-encoder is a small Core ML model reading 512-token query-passage pairs. Maximal marginal relevance trades a little relevance for coverage. Parent-document retrieval restores the paragraph around a precise hit and deduplicates by token overlap. For spec questions, a "sniper" path scores chunks that jointly match several concepts and contain numeric or key-value signals, then a deterministic extractor tries structured rows, then patterns, before any model is asked.

**Average Joe.** The numbers for a Standard query: 30 is the target; the vector side gathers 90 and the keyword side up to 60; fusion merges; up to 90 are reranked; the floor at 0.28 and diversity at λ 0.60 cut from there. Deep Think starts at 35 with a 0.25 floor and λ 0.55; Maximum at 50, 0.20, 0.50. Lower floor and lower lambda mean "gather more, spread wider, let later stages sort it out." Why does the cross-encoder only see the shortlist? Because it can't precompute anything; every pair is a fresh inference.

**Dot-connector.** Recall first, precision second, and never the other way around: a reranker can only reorder what it received, so the first stage must be broad enough to contain the answer. That single sentence explains why top-K is multiplied by three before rerank, why the floor is dynamic rather than fixed, why there's an acceptance override, why lexical survivors exist, and why a retrieval cascade re-runs wider with more lexical weight when the first pass is weak. Also note the hardware: the vector arm is module 06's CPU-or-Metal scan; the reranker is Core ML with all units permitted; the MMR pairwise matrix goes to Metal above 50 candidates when the profile allows.

**Expert.** `HybridSearchService.hybridSearch` launches vector and FTS arms with `async let`; vector top-K is K×3 (×2 above K 50), FTS min(K×3, 60), structured rows min(K×3, 36). RRF k 60, weights 0.7/0.3, off the main thread on a snapshot; deterministic tie-break by chunk ID because `sort` is not stable and equal scores are routine. Lexical survivors up to max(4, K/6). Keyword-match boost ≤ 0.20 at 0.05 per weighted match, with any keyword matching over 30% of candidates treated as zero-discriminative. Section title and path boosts. `RAGEngine.rerankWithCrossEncoder` on ms-marco-TinyBERT-L2-v2 (provenance in `THIRD_PARTY_NOTICES.md`), pairs encoded to 512, concurrent prediction, `computeUnits = .all`, low-precision GPU accumulation allowed, called with K×3 and trimmed to K×3. `RetrievalPolicyService` computes the dynamic threshold (mode floor adjusted by count, top score, spread, intent, vocabulary mismatch) and the acceptance override; `filterAndDiversify` applies the floor, a multi-document guarantee, and MMR with the mode lambda (matrix on Metal above 50 candidates with Metal vector ops enabled and a GPU present). `ParentDocumentService` expands parents and siblings with Jaccard dedup above 80%. `GraphIndexService` BFS over typed edges with hop and budget limits. `EvidenceScoringPolicyService` holds the spec sniper, state-anchor adjustment, specification boost and corrective retrieval. `SpecificationExtractor` tries explicit state structures, structured table rows, then pattern-based extraction, with extraction confidence and entity-aware disambiguation, before generation.

**Expert's expert.** Retrieval is nondeterministic across runs of one build: two runs return different chunk IDs for one question, and the cause is upstream of tie-breaking (the trace and the benchmark ledger both record it). One tie at a top-N cutoff cascades: it changes which candidates survive, which changes rerank input, which changes the answer. Until that is found, no retrieval A/B on this app is trustworthy. The fusion-stage regression in the ledger is the other lesson: on one fixture set, fusing a weak dense arm with a stronger lexical arm scored worse than BM25 alone, which is why the weights are measured, not assumed. Two bank corrections: the reranker's architecture name, TinyBERT, is documented provenance, not a guess (the earlier trace called it unverified; it is in the notices file); and "neural start/end span model" is dormant, so "extractive QA" in shipping builds means the heuristic scorer.

## Every concept

### Acceptance override (Core, verified as an audit flag)
- **Idiot:** let the best card through even if its score is technically low.
- **Dot-connector:** relative rank, margin, breadth or extractive intent can justify evidence a rigid floor would discard.
- **Expert:** `RetrievalPolicyService` after the dynamic threshold, before the empty-retrieval fallback; surfaced as `acceptanceOverride` on the audit snapshot.

### Breadth-first search (Conditional, verified)
- **Idiot:** look at the neighbours first, then the neighbours' neighbours.
- **Dot-connector:** bounded, interpretable expansion around an anchor; no diving down one arbitrary link.
- **Expert:** `GraphIndexService` from top chunks, stopped by hop, score or budget.

### Candidate generation (Core, verified)
- **Idiot:** grab more cards than you'll keep.
- **Dot-connector:** rerank can't recover what was never retrieved.
- **Expert:** the hybrid entry; metrics in `RetrievalStageMetrics`.

### Corrective retrieval (Conditional, verified)
- **Idiot:** when the first search finds the topic but not the fact, search specifically for the fact's shape.
- **Dot-connector:** rescans for terms, structured data, numeric patterns or reference destinations before giving up or generating.
- **Expert:** `EvidenceScoringPolicyService` and `RAGService` after weak evidence assessment.

### Cross-encoder reranking (Core, verified)
- **Idiot:** the slow smart reader.
- **Dot-connector:** joint encoding sees interactions bi-encoders can't; accurate on a shortlist, impossible on a corpus.
- **Expert:** `RAGEngine.rerankWithCrossEncoder`; Core ML, all units, concurrent pairs.

### Cross-reference repair (Conditional, verified)
- **Idiot:** follow "see page 12" and fetch page 12.
- **Dot-connector:** the pointer chunk is not the answer and can be a false positive.
- **Expert:** `GraphIndexService` plus the scoring policy; after the first retrieval exposes the reference.

### Dense retrieval (Core, verified)
- **Idiot:** the meaning-map search.
- **Dot-connector:** paraphrase and synonyms with no word overlap.
- **Expert:** `BNNSVectorDatabase.search` inside `HybridSearchService`; module 06 for the CPU/GPU switch.

### Document-order restoration (Conditional, verified)
- **Idiot:** put the summary sentences back in the order they appeared.
- **Dot-connector:** rank order can reverse chronology.
- **Expert:** last step of `ExtractiveSummarizationService`.

### Dynamic similarity threshold (Core, verified)
- **Idiot:** the pass mark moves depending on the exam.
- **Dot-connector:** absolute cosine scores aren't calibrated across corpora; relative evidence can be useful even when every score is low.
- **Expert:** `RetrievalPolicyService` after initial candidates; inputs are count, top score, spread, intent, suspected vocabulary mismatch.

### Entity expansion (Conditional, verified)
- **Idiot:** fetch every card that mentions the same name.
- **Dot-connector:** a concept discussed across sections without repeating the query phrase.
- **Expert:** `EntityIndexService` during graph or agentic expansion.

### Entity-aware disambiguation (Core, verified)
- **Idiot:** prefer the card that actually names the thing you asked about.
- **Dot-connector:** stops a similar product's spec from winning over the named one.
- **Expert:** `SpecificationExtractor` after scoring, before ambiguity failure.

### Evidence assessment (Conditional, verified)
- **Idiot:** "do we have enough yet?"
- **Dot-connector:** coverage, relevance and gaps; the loop needs an evidence-based reason to continue.
- **Expert:** `IterativeRetrievalService` and the orchestrator after each pass.

### Explicit state-structure lookup (Conditional, verified)
- **Idiot:** the light-colour table, read directly.
- **Dot-connector:** keeps the state and its meaning paired.
- **Expert:** an early branch in `SpecificationExtractor` for state queries.

### Extraction confidence (Core, verified)
- **Idiot:** how sure the copy-out is.
- **Dot-connector:** a deterministic extractor still has to abstain when several values are plausible.
- **Expert:** computed before returning a span; low or ambiguous escalates to the model.

### Extractive QA (Conditional, verified as the heuristic path)
- **Idiot:** copy the answer out instead of writing one.
- **Dot-connector:** the value must exist in the source, which kills a whole class of hallucination.
- **Expert:** `ExtractiveQAService` heuristic scorer plus `SpecificationExtractor`; the neural span model is a stub.

### Extractive summarization (Conditional, verified)
- **Idiot:** pick the best sentences rather than writing new ones.
- **Dot-connector:** traceable wording, less hallucination.
- **Expert:** segment, embed sentences, MMR, restore order.

### Fusion weight (Core, verified) and Fusion-stage regression (Support, documented)
- **Idiot:** how much each helper's pile counts, and the day it turned out one helper was dragging the other down.
- **Dot-connector:** 0.7 vector, 0.3 keyword; on one fixture set fusion scored below BM25 alone, which is why the mix is measured.
- **Expert:** `HybridSearchService`; sweep script `scripts/sweep_fusion_weight.py`; record in `Docs/EVALS.md` and the benchmark matrix.

### Graph edge (Conditional, verified), Graph hop (Conditional, verified), Graph index (Conditional, verified)
- **Idiot:** cards connected by string, and how many strings away.
- **Dot-connector:** typed edges (next, previous, sibling, reference, same section, shared entity) preserve why two things relate; hops bound the blast radius.
- **Expert:** `GraphIndexService`, built from chunk metadata, traversed after initial retrieval; hop counts considered by packing.

### Heuristic extractive QA (Conditional, verified)
- **Idiot:** the rule-based copy-out that actually runs.
- **Dot-connector:** keyword overlap, entity types, proximity, passage rank, question type.
- **Expert:** `ExtractiveQAService` when the span model is unavailable, which is always.

### Hybrid search (Core, verified)
- **Idiot:** both searches, then merge.
- **Dot-connector:** complementary failure modes; the main retrieval entry point.
- **Expert:** `HybridSearchService.hybridSearch`.

### Initial candidate breadth (Core, verified)
- **Idiot:** how many cards to grab first: 30, 35 or 50.
- **Dot-connector:** the reranker only improves what it sees.
- **Expert:** `RAGQualityMode.initialTopK`.

### Iterative retrieval (Conditional, verified)
- **Idiot:** search, look, search again.
- **Dot-connector:** the first search can reveal the terminology the second needs.
- **Expert:** `IterativeRetrievalService`; stops on quality, pass count or no improvement.

### Jaccard deduplication (Core, verified)
- **Idiot:** don't include a parent and child that are mostly the same text.
- **Dot-connector:** token-set overlap above 80% is redundant.
- **Expert:** `ParentDocumentService` during expansion merge.

### L0 chunk (Core, verified), L1 summary chunk (Conditional, verified), L2 and L3 abstraction levels (Future, reserved)
- **Idiot:** detail cards, one summary card per document, and two levels that don't exist yet.
- **Dot-connector:** L0 is evidence; L1 is routing; L2/L3 are enum names.
- **Expert:** `ChunkAbstractionLevel` on `DocumentChunk`.

### Lexical retrieval (Core, verified)
- **Idiot:** the exact-word search.
- **Dot-connector:** part numbers, standards, names, quotations, measurements.
- **Expert:** FTS5 through `SQLiteFullTextService`, in parallel with dense.

### Lexical survivor guarantee (Core, verified)
- **Idiot:** don't let paraphrase bury an exact match.
- **Dot-connector:** exact identifiers are often the answer.
- **Expert:** re-attach up to max(4, K/6) lexical-only hits below the top-K cut; `HybridSearchService.swift:379`.

### Maximal marginal relevance (Core, verified), MMR lambda (Core, verified), Redundancy penalty (Core, verified), Pairwise similarity matrix (Support, verified)
- **Idiot:** don't pick five cards that say the same thing; the dial says how much variety to insist on.
- **Dot-connector:** greedy selection: relevance minus the max similarity to anything already chosen; lower lambda means more variety; the matrix precomputes the similarities.
- **Expert:** `RAGEngine`; λ 0.60/0.55/0.50; matrix on Metal above 50 candidates when the profile allows and a GPU exists, else `BNNSGraphService`.

### Metadata boost (Core, verified)
- **Idiot:** extra credit for headings, names, tables, numbers.
- **Dot-connector:** a raw score can't see the evidence-quality signals ingestion attached.
- **Expert:** `HybridSearchService` and `EvidenceScoringPolicyService` after fusion.

### Minimum similarity (Core, verified)
- **Idiot:** the pass mark.
- **Dot-connector:** 0.28, 0.25, 0.20 by mode, then adjusted dynamically.
- **Expert:** `RAGQualityMode` plus `RetrievalPolicyService`.

### Multi-vector retrieval (Conditional, verified) and Supplementary vector search (Conditional, verified)
- **Idiot:** search with several pins, not one.
- **Dot-connector:** rewrite, expansion, HyDE and subquestion vectors each probe a facet; results merge and dedupe before rerank.
- **Expert:** `RAGService` supplementary searches; recorded in audit feature flags.

### Neural start/end span model (Dormant, verified as a stub)
- **Idiot:** a reader that's on the blueprint shelf.
- **Dot-connector:** would find exact answer spans; the placeholder returns nil.
- **Expert:** `ExtractiveQAService` protocol and template; never active.

### Parallel retrieval arms (Core, verified)
- **Idiot:** both helpers run at once.
- **Dot-connector:** latency is the slower arm, not the sum.
- **Expert:** `async let` at the top of `hybridSearch`.

### Parent-document retrieval (Core, verified) and Sibling expansion (Core, verified)
- **Idiot:** grab the paragraph around the hit, and the cards next door.
- **Dot-connector:** small chunks rank well but lose definitions, conditions and headings; procedures span boundaries.
- **Expert:** `ParentDocumentService` after rerank and MMR, capped by mode and budget, deduped by Jaccard.

### Pattern-based specification extraction (Core, verified)
- **Idiot:** regex for grades, sizes, codes, dates.
- **Dot-connector:** not every document has a clean table; exact-value answers need a deterministic fallback.
- **Expert:** `SpecificationExtractor` after structured lookups fail, before generation.

### RAPTOR-lite summary routing (Conditional, verified)
- **Idiot:** overview questions read the summaries.
- **Dot-connector:** whole-document questions are answered by representative summaries, not an incidental chunk.
- **Expert:** `RAPTORSummaryRouter` chosen by `QueryRouterService`.

### Reciprocal rank fusion (Core, verified) and RRF constant k (Core, verified)
- **Idiot:** points for being near the top of either pile.
- **Dot-connector:** ranks are comparable across arms; scores aren't. k smooths the top positions.
- **Expert:** sum over lists of 1/(k + rank), k exactly 60, weighted 0.7/0.3; `HybridSearchService` and `BNNSGraphService`.

### Rerank batch size (Core, verified) and Rerank score (Core, verified) and Reranker tokenizer (Core, verified)
- **Idiot:** how many pairs the smart reader takes at once, the score it gives, and its own ruler.
- **Dot-connector:** batch size from mode and device; the score reorders the fused list; the tokenizer must match the reranker's contract.
- **Expert:** `AdaptivePipelineOptimizer`/`DeviceCapabilityService`; score from `RAGEngine`; tokenizer bundle `reranker_tokenizer.bundle`.

### Retrieval cascade (Conditional, verified)
- **Idiot:** if the first search is thin, search wider with more weight on exact words.
- **Dot-connector:** weak retrieval may mean the mix was too semantic, not that evidence is absent.
- **Expert:** `RetrievalPolicyService` after first-stage metrics fail; `usedRetrievalCascade` on the audit.

### Sentence-level relevance (Conditional, verified)
- **Idiot:** score sentences, not just cards.
- **Dot-connector:** a relevant chunk still contains irrelevant sentences.
- **Expert:** query-versus-sentence cosine inside extractive summarisation and context rescue.

### Spec sniper (Conditional, verified) and Specification boost (Conditional, verified) and Structured table lookup (Core, verified)
- **Idiot:** the sharpshooter for "what's the exact number."
- **Dot-connector:** chunks matching several query concepts with numeric, code or table signals are surfaced; then the table rows are read directly before any model is asked.
- **Expert:** `specTableSniper` in `RAGService`; boosts in `EvidenceScoringPolicyService`; row lookup in `SpecificationExtractor` against `chunk_table_rows`.

### Stable tie-break (Core, verified)
- **Idiot:** when scores tie, always break the tie the same way.
- **Dot-connector:** Swift's sort isn't stable; unstable order makes tests flaky and citations shift.
- **Expert:** by chunk identifier in `HybridSearchService`; note the source comment that one tie at a cutoff cascades through rerank.

### State-anchor adjustment (Conditional, verified)
- **Idiot:** extra credit for "flashing" and "orange" when you asked about a flashing orange light.
- **Dot-connector:** matching "indicator" alone is not enough in a manual full of lights.
- **Expert:** `EvidenceScoringPolicyService` before extraction for state-lookup queries.

### TinyBERT reranker (Core, verified provenance)
- **Idiot:** the specific small smart reader.
- **Dot-connector:** compact enough to run joint scoring on a phone for a shortlist.
- **Expert:** `cross-encoder/ms-marco-TinyBERT-L2-v2` in `THIRD_PARTY_NOTICES.md`; `ReRankerModel.mlpackage`; loaded at engine init in a detached task.

### Top-k (Core, verified)
- **Idiot:** keep the best K.
- **Dot-connector:** different K at different stages trades recall against cost.
- **Expert:** applied at dense/lexical retrieval, after fusion, after rerank, and at packing.

### Vocabulary mismatch (Core, verified as policy)
- **Idiot:** lots of cards, all with low scores, bunched together.
- **Dot-connector:** specialised language makes absolute thresholds misleading; lower the floor selectively.
- **Expert:** inferred from top and average scores in `RetrievalPolicyService`.
# Module 09. Context selection, compression, and token packing

Twenty-seven concepts. Deciding what the model actually reads: a hard token budget, an order that fights the model's blind spot, and optional compression.

## The ladder

**Like you're five.** The writer's desk is small. Only so many cards fit. The librarian puts the best cards first and last, because the writer doesn't look at the middle of the pile very carefully. If a card has a lot of useless words on it, she can cross out the useless bits so more cards fit.

**Like an idiot.** The on-device model can see about 4,000 tokens total. Instructions, your question, the conversation so far, and space for the answer all come out of that. What's left is the evidence budget. The packer fills it with the best chunks, strongest first and last, and records which chunks didn't fit. Optionally, a model call strips each chunk down to only the sentences that matter, which costs time and is used mainly in Deep Think.

**Like less of an idiot.** The budget is an explicit equation: model context minus system prompt minus tool schemas minus question minus conversation minus a safety reserve minus reserved output tokens. Base context is 4,096; the default evidence budget is 3,200; the safety reserve is 256; the app estimates 1.4 characters per token on device. Since iOS 26 the real window is read from the system model at runtime and can be larger. The packer allocates in priority order: core hits, then parents, then neighbours, then graph hops, with intent-specific rules (procedures keep sequence, comparisons keep both sides). Contextual compression uses a fresh Foundation Models session per chunk, rejects any "compression" that came back longer than the original, strips echoed question text, and passes chunks through untouched on any failure.

**Average Joe.** Why is the budget so paranoid? Because the model's limit is hard: overflow is a failure, not a warning. A budget that's right on average is wrong on the day the tokenizer estimate is low. Why put the best evidence at both ends? Because language models measurably underuse the middle of a long prompt, and there's a fixture in the benchmark suite that puts the answer in the middle to prove it. Why sleep one second after compressing? So the Foundation Models rate budget recovers before the real generation call.

**Dot-connector.** Two things that surprise people. First, compression can remove a chunk entirely: if the model answers with the sentinel "NO_RELEVANT_CONTENT," the orchestration layer drops that chunk rather than keeping a stub, because with only a few chunks fitting, a 400-character stub competes with real evidence. The compression service itself has a rescue path, but the caller in `RAGService` chooses removal. Second, "trimmed" is recorded: the IDs of chunks that didn't fit go onto the audit snapshot, and the retrieval diagnostics can show them. That is the difference between a silent drop and a visible one.

**Expert.** `FoundationModelTokenBudget`: base 4,096, default evidence budget 3,200, safety reserve 256, chars-per-token 1.4 on device and 2.5 for the cloud estimate; reads `SystemLanguageModel.default.contextSize` when available. `ContextPackingService` selects core, parent, neighbour and graph-hop allocations under `availableContextTokens`, applies intent-specific packing and the lost-in-the-middle reorder, and records trimmed chunk IDs and skipped sibling counts. `ContextualCompressionService`: target ratio configurable, passthrough on short chunk, unavailable model, failure, timeout or unsafe output; expansion guard rejects ratio > 1.0; query-echo stripping; `NO_RELEVANT_CONTENT` sentinel; `effectiveContent` with information-density rescue inside the service; a fresh session per chunk; a batch time budget. `RAGService` drops chunks the compressor marked irrelevant, then sleeps one second. Mode gating via `usesContextualCompression`, mainly Deep Think. `FoundationModelPromptCompiler` turns the packet into instructions and prompt with S1, S2 source labels.

**Expert's expert.** The word bank says the sentinel "triggers information-dense source rescue or passthrough." Inside the service that is true; at the call site in `RAGService` the chunk is removed, with a comment explaining why. Both are real; the caller wins for what the model sees. The tool-schema overhead is only counted when tools are attached, which is why Maximum's inner sessions disable tools: schema tokens plus tool output tokens were part of what overflowed. And the 4,096 figure is Apple's per-session limit for both on-device and PCC (Technote 3193, cited in `LLMModel.swift`), so the cloud route does not buy a bigger window; it buys a bigger model.

## Every concept

### 4,096-token on-device limit (Core, verified)
- **Idiot:** the desk holds about four thousand tokens.
- **Dot-connector:** a naive top-20 chunk set plus prompt and schema overflows; everything upstream exists to choose what fits.
- **Expert:** `contextLength` 4,096 per TN3193, on device and PCC alike; real window read at runtime.

### Available context tokens (Core, verified)
- **Idiot:** what's left for evidence after everything else.
- **Dot-connector:** the actual capacity the packer may spend.
- **Expert:** the input constraint to `ContextPackingService`.

### Compression expansion guard (Core, verified)
- **Idiot:** if "compressing" made it longer, the model was making things up; throw it away.
- **Dot-connector:** expansion means paraphrase or hallucination instead of extraction.
- **Expert:** ratio > 1.0 rejected, original passed through; `ContextualCompressionService.swift:141`.

### Compression passthrough (Core, verified)
- **Idiot:** when in doubt, keep the original.
- **Dot-connector:** compression is an optimisation and must never be a single point of evidence loss.
- **Expert:** on short chunk, unavailable model, failure, time expiry, unsafe output.

### Compression ratio (Conditional, verified)
- **Idiot:** how much smaller it got.
- **Dot-connector:** measures whether the call saved context.
- **Expert:** compressed tokens over original; target configurable (0.3 keeps 30%).

### Compression time budget (Core, verified)
- **Idiot:** a stopwatch for the whole compression batch.
- **Dot-connector:** many model calls dominate latency; when time is up, remaining chunks pass through.
- **Expert:** batch-level wall clock in the service.

### Context window (Core, verified)
- **Idiot:** everything the model can see at once.
- **Dot-connector:** instructions, tools, evidence, conversation and output framing all share it.
- **Expert:** enforced immediately before model execution.

### ContextPackingService (Core, verified)
- **Idiot:** the desk arranger.
- **Dot-connector:** chooses and orders core hits, parents, siblings, graph neighbours and compressed content under the ceiling; rank alone can't solve budget, diversity, sequence and support.
- **Expert:** after retrieval and expansion, before prompt compilation.

### Contextual compression (Conditional, verified)
- **Idiot:** cross out the useless sentences.
- **Dot-connector:** density matters in a 4,096-token window; mainly Deep Think.
- **Expert:** Foundation Models extraction of query-relevant sentences with exact wording preserved; `usesContextualCompression` by mode.

### Core evidence chunk (Core, verified)
- **Idiot:** the must-keep cards.
- **Dot-connector:** strongest direct evidence survives before any context around it is bought.
- **Expert:** selected first; parents, neighbours, hops compete for the remainder.

### Evidence packet (Core, verified)
- **Idiot:** the final stack handed to the writer.
- **Dot-connector:** the boundary between retrieval and generation; defines what the model is allowed to know.
- **Expert:** produced by packing, consumed by the prompt compiler and verification.

### Fresh compression session (Core, verified)
- **Idiot:** a new conversation for each card.
- **Dot-connector:** carrying the transcript across chunks overflows after a few calls.
- **Expert:** session reset before each chunk in a batch.

### Graph-hop allocation (Conditional, verified)
- **Idiot:** a little space saved for related-but-not-direct cards.
- **Dot-connector:** graph evidence can complete an answer but ranks lower than the anchor.
- **Expert:** lowest priority after core, parent and neighbours.

### Information-density rescue (Core, verified)
- **Idiot:** if compression found nothing, grab the sentences with numbers and names.
- **Dot-connector:** taking the first characters blindly loses a spec buried mid-passage.
- **Expert:** `CompressionResult.effectiveContent` inside the service; note the caller may drop the chunk instead.

### Intent-specific packing (Core, verified)
- **Idiot:** pack a recipe differently from a comparison.
- **Dot-connector:** the same top chunks shouldn't be arranged identically for every answer shape.
- **Expert:** resolved inside `ContextPackingService` from answer intent.

### Lost-in-the-Middle mitigation (Core, verified)
- **Idiot:** best cards first and last.
- **Dot-connector:** models underuse the middle of long prompts; a synthetic fixture tests this.
- **Expert:** applied after selection, before prompt assembly; note the reorder interleaves the ranked set, so downstream code must not assume rank order.

### Neighbor allocation (Core, verified)
- **Idiot:** space for the cards next door.
- **Dot-connector:** procedures and definitions cross chunk boundaries.
- **Expert:** after parents, by intent and remaining capacity.

### NO_RELEVANT_CONTENT sentinel (Conditional, verified)
- **Idiot:** the model's way of saying "this card is useless for this question."
- **Dot-connector:** a fixed string is easier to detect than free-form language.
- **Expert:** the compressor marks `wasMarkedIrrelevant`; `RAGService` drops the chunk entirely.

### Parent allocation (Core, verified)
- **Idiot:** space for the paragraph around a hit.
- **Dot-connector:** a precise hit can be uninterpretable without its defining context.
- **Expert:** after core, before graph expansion.

### Query-echo stripping (Core, verified)
- **Idiot:** remove the question if the model parroted it back.
- **Dot-connector:** an echoed question fools later keyword scoring.
- **Expert:** applied to compression output before ratio and relevance checks.

### Question-token cost (Core, verified)
- **Idiot:** your question takes up desk space too.
- **Dot-connector:** a long multi-part question leaves less room and can trigger decomposition.
- **Expert:** measured before capacity is determined.

### Reserved output tokens (Core, verified) and Maximum generation tokens (see module 10)
- **Idiot:** save room for the answer.
- **Dot-connector:** packing to the ceiling leaves no room to write.
- **Expert:** subtracted before evidence selection; default `maxTokens` 512.

### Safety-token reserve (Core, verified)
- **Idiot:** a little extra margin.
- **Dot-connector:** tokenizer estimates and framework wrappers vary; a budget right on average is unsafe under a hard limit.
- **Expert:** 256 tokens.

### Source sentence selection (Core, verified)
- **Idiot:** pick the exact sentences that answer.
- **Dot-connector:** the right chunk still buries the answer among unrelated prose.
- **Expert:** in extractive summarisation, compression, source-only answering and rescue.

### System-prompt overhead (Core, verified)
- **Idiot:** the instructions take space.
- **Dot-connector:** grounding rules and output format are necessary and must be counted.
- **Expert:** counted before evidence capacity.

### Token budget (Core, verified)
- **Idiot:** the whole accounting.
- **Dot-connector:** character or chunk counts aren't enough; capacity is consumed by tokens across every component.
- **Expert:** `FoundationModelTokenBudget`; computed before packing, rechecked before the session call.

### Tool-schema overhead (Conditional, verified)
- **Idiot:** describing the tools to the model costs space.
- **Dot-connector:** capability competes with evidence.
- **Expert:** included only when tools are attached; subtracted before packing.
# Module 10. Model execution, routing, tools, and generation

Sixty-two concepts. Choosing which model answers, building the session, and generating: the plan, the route, the session, the stream, the receipt.

## The ladder

**Like you're five.** After the cards are on the desk, the librarian decides who writes. Usually the writer sitting right there. Sometimes nobody, because there isn't enough. Sometimes a rule can just copy the answer out. And sometimes the pile is too big for the small desk, so she asks if she can carry it to Apple's special room, and shows you exactly which cards she'd carry.

**Like an idiot.** Only after retrieval does the app decide where to generate. Four outcomes: abstain (not enough evidence), deterministic (a rule extracts the answer directly), on-device (Apple's built-in model, the normal case), or Private Cloud Compute (Apple's cloud, built so Apple can't read it either). The cloud is picked only if the evidence doesn't fit locally or the question is genuinely hard, and only if the network is up and you've consented after seeing the exact trimmed payload. Every cloud plan has an on-device fallback. The model streams a typed answer: a list of claims, each with the IDs of the chunks that support it.

**Like less of an idiot.** The plan is an immutable object with a target, a reason, token estimates, a fallback and a policy version. The route policy maps it to a Foundation Models session. The session factory builds the session with instructions, optional tools and an optional saved transcript. Generation uses constrained decoding into `@Generable` types, so the output is a `RAGAnswer` with reasoning, answer, confidence, citations, atomic claims and matched terms, not free text to be parsed. A receipt records what was intended, what was attempted and what completed, so the badge on screen reflects the route that actually ran, not the one you picked in settings.

**Average Joe.** Why route after retrieval? Because before retrieval the app doesn't know how big the evidence is or what exact text would leave the phone, so it can't ask for meaningful consent. Why does "advanced on-device model" exist as an option if there's no such model? Because older settings stored it; the alias now runs the default model and corrects its own telemetry rather than claiming a tier that never ran. Why does the cloud not get a bigger context window? Because Apple's per-session limit is 4,096 tokens for both; the cloud buys a bigger model, not a bigger desk.

**Dot-connector.** Two vocabularies to keep apart. Execution context (automatic, on-device only, prefer cloud, cloud only) is the user's privacy policy. Quality mode is effort. They're independent: Maximum with on-device-only never leaves the phone. Also: the whole cloud apparatus (consent, transmission record, minimised payload, quota state, reasoning level) is labelled Dormant in the word bank because shipped App Store builds have carried zero PCC symbols; the code compiles under Swift 6.4 and iOS 27 but a given build is a build fact, not a source fact. On iOS 26 the route is always on-device.

**Expert.** `ModelExecutionPlanner.makePlan`: abstain when evidence is insufficient; deterministic when an extractor answers; PCC when `capability.canUsePCC && constraints.networkAvailable && (constraints.isForegroundInteractive || constraints.consentGranted) && (!localBudget.fits || complexity.requestsPCC)`, reason local context exceeded or complex synthesis; otherwise on-device with reason network unavailable, consent unavailable or local context fits. Fallback on-device for every cloud plan; stages retrieve (deterministic), synthesise (target), verify (deterministic). Cloud evidence minimiser: chunks in rank order, per-chunk allowance `min(remaining, max(240, maxChars / min(count, 8)))`, prefix-cut. `FoundationModelRoutePolicy`: with a plan, deterministic/on-device/abstain map to on-device and cloud maps to cloud with reasoning none/moderate/deep by mode; without a plan, `core3B` and `advanced20B` aliases force on-device, manual cloud forces cloud, automatic reads the on-device limit from the system model and routes cloud only when the estimate exceeds it and `isPCCAvailable` (Swift 6.4, iOS/macOS 27, entitlement, cloud model available, quota not reached). `FoundationModelSessionFactory`: on-device `SystemLanguageModel.default`, availability guard, session from saved transcript with prewarm when a transcript exists and tools are enabled, else compiled instructions; the advanced route executes the default model and corrects the reported route; cloud creates the PCC model with entitlement and quota guards. `GenerationOptions`: temperature 0.4/0.4/0.3, `maximumResponseTokens` from settings when positive (default 512). `streamResponse` with a continuation-prompt path for partial completions and response-tail trimming after termination. `FoundationModelToolRegistry` registers ten tools: SearchDocuments, ListDocuments, GetDocumentSummary, CountPattern, SearchExactPattern, GetCorpusStats, FindRelatedDocuments, CompareDocuments, RetrieveCorpusEvidence, InspectDocument. PCC suppression: `suppressPCC(for:reason:)` sets `pccSuppressedUntil` after a route failure and the coordinator checks it before planning. `ModelExecutionReceipt` records intended, actual and completed targets, attempts, quota, fallback reason, policy version and timing. Consent choices: allow once, allow and remember, deny.

**Expert's expert.** Corrections to the bank. The tool registry is ten tools, not "approximately six." `CloudTransmissionRecord` and the consent prompt are real, compiled code with a preview; "Dormant" describes shipped reach, not compilation. The on-device model's placement across CPU, GPU and Neural Engine is Apple's decision and unobservable from the app, so any sentence that says where the language model runs is speculation. And the deterministic target is where a surprising share of lookup answers come from: when structured table lookup or pattern extraction succeeds with confidence, the language model is never called, which is both the fastest path and the one with zero hallucination risk.

## Every concept

### @Generable (Core, verified) and @Guide (Core, verified) and Constrained decoding (Core, verified) and Structured generation (Core, verified)
- **Idiot:** the model has to fill in a form, not write an essay.
- **Dot-connector:** typed fields with natural-language guides; decoding restricted to the schema; claims, citations, confidence and refusal become machine-readable without fragile JSON parsing.
- **Expert:** `RAGStructuredResponse` types; `FoundationModelStructuredGenerator`; converted into `StructuredAnswer` before verification.

### Abstain execution target (Core, verified)
- **Idiot:** the plan can be "don't answer."
- **Dot-connector:** no model should turn absent or contradictory evidence into fluent certainty.
- **Expert:** `ModelExecutionPlan` target selected when evidence or authorization fails before execution.

### Active model (Core, verified) and Selected model (Core, verified) and ModelResolutionService (Support, verified)
- **Idiot:** what you asked for versus what actually ran, and the thing that keeps them straight.
- **Dot-connector:** fallback, availability and route policy make them differ; a picker label is not proof.
- **Expert:** `LLMModelType` for selection; resolution state observes settings and `RAGService` and updates the UI.

### AdapterManager (Support, verified)
- **Idiot:** the adapter that picks a model backend.
- **Dot-connector:** decouples the engine from one implementation; carries legacy transitions.
- **Expert:** resolves an `LLMService` before execution.

### advanced20B preference alias (Historical, verified) and core3B preference alias (Historical, verified)
- **Idiot:** old menu names that both mean "on device."
- **Dot-connector:** stored preferences keep resolving without claiming a model Apple doesn't expose.
- **Expert:** canonicalised in `FoundationModelRoutePolicy`; the advanced route executes the default model and reports on-device.

### Apple Foundation Models (Core, verified) and SystemLanguageModel.default (Core, verified) and LanguageModelSession (Core, verified)
- **Idiot:** Apple's built-in writer, and one conversation with it.
- **Dot-connector:** the OS owns availability, updates and hardware scheduling; the app queries capability rather than assuming a parameter count; a session carries instructions, tools, transcript and calls.
- **Expert:** created after route and budget resolution by the session factory; the app cannot place the model on a processor.

### Atomic claim (Core, verified)
- **Idiot:** one fact per sentence.
- **Dot-connector:** verifiable separately; the unit Gate B grades.
- **Expert:** in `RAGAnswer` and `StructuredAnswer`.

### Citation namespace (Core, verified) and Evidence source label (Core, verified)
- **Idiot:** S1 in the text is chip 1 below it, always.
- **Dot-connector:** a cited answer is unsafe if labels can drift between prompt, output, chips and source views.
- **Expert:** assigned by the prompt compiler; validated when the structured response is built; the agentic chain once resolved against the wrong array.

### Cloud consent (Dormant in reach, verified in code) and Cloud transmission record (Dormant in reach, verified) and Minimized cloud payload (Dormant in reach, verified) and PCC quota state (Dormant) and PCC reasoning level (Dormant) and Private Cloud Compute target (Dormant)
- **Idiot:** the whole "outside room" apparatus: ask, record what left, send the minimum, check the meter, pick how hard the cloud thinks.
- **Dot-connector:** consent after the exact payload is known; an audit record of provider, model, preview, counts, hashes, bytes, plan and reason; only selected evidence, never the library; quota available/limit reached/unsupported/unknown; reasoning none/moderate/deep by mode. All real, all compiled, none reachable in a build without PCC symbols.
- **Expert:** `CloudTransmission.swift`, `CloudConsentPromptView`, the minimiser in the planner, `FoundationModelRoute`, `ModelExecutionReceipt`; gated by `isPCCAvailable`.

### Deterministic execution target (Core, verified)
- **Idiot:** a rule copies the answer out; no writer needed.
- **Dot-connector:** when structure already yields the answer, generation adds risk and latency.
- **Expert:** selected after high-confidence extraction; skips the model call.

### DirectRAGAnswer (Conditional, verified) and RAGAnswer (Core, verified) and Reasoning-first field order (Conditional, verified)
- **Idiot:** the form the writer fills in, with a "show your reasoning" box first.
- **Dot-connector:** the smaller form skips reasoning for direct answers; the reasoning field first encourages finding facts before committing.
- **Expert:** `RAGStructuredResponse`.

### Execution attempt (Core, verified), Execution fallback (Core, verified), ModelExecutionReceipt (Core, verified), Route reason (Core, verified), Policy version (Support, verified)
- **Idiot:** the receipt: what was tried, in order, what worked, and why.
- **Dot-connector:** the badge and the debugging both come from the receipt, not from settings; fallback must be explicit.
- **Expert:** attempts appended as calls occur; `policyVersion` on plan and receipt.

### Execution context (Core, verified)
- **Idiot:** your privacy setting.
- **Dot-connector:** automatic, on-device only, prefer cloud, cloud only; independent of quality mode.
- **Expert:** `LLMModel.swift` enum; resolved before planning, enforced again at plan creation.

### Fail-closed routing (Core, verified)
- **Idiot:** if unsure, stay home.
- **Dot-connector:** denied, unknown, unsupported, unavailable or exhausted never becomes a cloud attempt.
- **Expert:** enforced in planning, consent, quota checks and receipt invariants; `RouteEvalMetrics`.

### Foundation Model preference (Core, verified) and InferenceConfig (Core, verified)
- **Idiot:** your model choice, and the bundle of settings every call uses.
- **Dot-connector:** one consistent expression of user and policy intent for all calls in a query, including agentic synthesis.
- **Expert:** preference in `InferenceConfig`; interpreted before session construction.

### Foundation Model tool (Conditional, verified), FoundationModelToolRegistry (Conditional, verified), Registered retrieval tools (Conditional, verified, ten), Tool call (Conditional, verified), Tool-call counter (Support, verified)
- **Idiot:** things the writer is allowed to ask the librarian to do, and a counter so it can't ask forever.
- **Dot-connector:** typed, allowlisted operations keep the model inside local data; schema costs tokens; a query-scoped counter bounds loops.
- **Expert:** ten `Tool` structs in the registry; attached only when the plan allows; `ToolCallCounter`.

### FoundationModelSessionFactory (Core, verified) and Session use case (Core, verified) and Session transcript (Core, verified) and Transcript persistence (Support, verified)
- **Idiot:** the one place sessions are built, labelled by job, with memory that can be saved.
- **Dot-connector:** central construction keeps instructions, tools and routing consistent; different jobs get different instructions; the transcript grows and is reset when the budget requires.
- **Expert:** `FoundationModelTranscriptStore`, `TranscriptPersistenceService`; resume with prewarm when a transcript exists and tools are enabled.

### LLMService (Core, verified) and Local OpenAI-compatible server backend (Conditional, verified)
- **Idiot:** the department that talks to the model; and a developer switch to talk to a local server instead.
- **Dot-connector:** retrieval shouldn't know session details; UI shouldn't own model state; the local server adapter gets the same packed prompt.
- **Expert:** `LLMService` (2,079 lines); `LocalOpenAIServerLLMService`.

### Matched terms (Support, verified)
- **Idiot:** the words the writer says it found.
- **Dot-connector:** a diagnostic, not a truth signal.
- **Expert:** field on `RAGAnswer`.

### Maximum generation tokens (Core, verified), Temperature (Core, verified), Top-p (Support, verified)
- **Idiot:** how long, how random, how narrow.
- **Dot-connector:** output cap bounds latency; low temperature suits exact values; nucleus sampling applies where the backend supports it.
- **Expert:** `maxTokens` default 512 into `maximumResponseTokens`; 0.4/0.4/0.3; `samplingMode .topP`.

### Model availability state (Core, verified)
- **Idiot:** is the writer even here today?
- **Dot-connector:** available, simulator unsupported, unsupported device, Apple Intelligence off, model preparing; fail explicitly, early.
- **Expert:** checked at SDK and query entry in `OpenIntelligenceEngine`.

### ModelExecutionPlan (Core, verified) and Post-retrieval routing (Core, verified)
- **Idiot:** the decision, made after the cards are on the desk.
- **Dot-connector:** a checkable decision based on the exact minimised evidence, not a vague preference.
- **Expert:** immutable; target, reason, estimates, fallback, policy version; created after packing, before consent and execution.

### On-device execution target (Core, verified)
- **Idiot:** the normal case.
- **Dot-connector:** the only generative target in shipping App Store builds.
- **Expert:** `SystemLanguageModel.default` through the session factory.

### Partial stream completion (Core, verified) and Response-tail trimming (Core, tests verified) and Streaming generation (Core, verified) and Time to first token (Support, verified) and Tokens per second (Support, verified)
- **Idiot:** the answer arrives word by word; if it cuts off, keep what's good and tidy the edge; and the stopwatch numbers.
- **Dot-connector:** partial text beats nothing when marked incomplete; trimming removes broken trailing structure; TTFT separates setup from streaming; TPS measures throughput, not quality.
- **Expert:** `RAGService+Streaming`; `ResponseTailTrimmingTests`; recorded in diagnostics.

### PCC suppression cooldown (Support, verified)
- **Idiot:** after the cloud fails, don't keep knocking.
- **Dot-connector:** repeated attempts at an unavailable route waste latency and can loop.
- **Expert:** `suppressPCC(for:reason:)` sets `pccSuppressedUntil`; checked by the coordinator and the orchestrator before planning.

### Prompt compiler (Core, verified)
- **Idiot:** writes the instructions the model reads.
- **Dot-connector:** intent, excerpts, labels, grounding rules, format and route constraints; must stay in sync with citation and verification expectations.
- **Expert:** `FoundationModelPromptCompiler` after packing, before the session request.
# Module 11. Agentic, recursive, and multi-session reasoning

Forty concepts. Thinking in loops: when one pass is not enough, plan, search, read, take notes, search again, write, check.

## The ladder

**Like you're five.** For a hard question, the librarian doesn't grab one pile and write. She makes a plan, looks, writes down what she found on a notepad, decides what's still missing, looks again, and only writes the answer when the notepad has enough. She has a timer, and she stops when it rings.

**Like an idiot.** Deep Think and Maximum run the whole search-and-read pipeline in a loop. Each round: pick a sub-question, search, read the results, add facts to a notebook, ask "is that enough?" If not, rewrite the question or split it and go again. It stops when it's confident, when new rounds find nothing new, when 180 seconds are up, or when it hits a hard cap on rounds. All the thinking happens on the phone. Only the final write-up can go to the cloud, with the same consent as always.

**Like less of an idiot.** The on-device model has a 4,096-token window and it's a small model. It cannot answer a multi-hop question in one shot. So the orchestrator works in sessions, each a fresh window, and carries a FactBank between them: atomic, source-backed facts with provenance, deduplicated, instead of the raw transcript. Escalation into the loop is decided by measured retrieval quality against a profile threshold, not by guessing complexity up front. There are four profiles with a step cap, a confidence target and an escalation threshold each. The loop has named phases (planning, searching, expanding, analyzing, synthesizing, refining, reformulating, verifying) that the UI shows as thinking events.

**Average Joe.** Why the notebook instead of just remembering the conversation? Because remembering the conversation is exactly what overflowed: the transcript carried between sessions hit 4,521 tokens on a 4,096 limit and the final draft failed. Why disable tools inside Maximum's sessions? Same reason: tool schemas cost tokens and tool outputs land in the transcript. Why a wall clock? Because thermal will stop a phone before the maths does, and the source says so in a comment.

**Dot-connector.** Three things to hold together. First, the loop reuses module 08 for every search; nothing new happens at retrieval, only more of it, driven by evidence gaps. Second, there are two call sites for recursive research with different iteration caps (five and three), and the only way to know which ran is the denominator in the log's iteration counter; guarding one of them is not guarding both. Third, the loop's stopping target (0.98 for unlimited) is a different number from the mode's verification bar (0.80 for Maximum): one says when to stop searching, the other says whether the answer may stand.

**Expert.** `AgenticConfig` profiles: fast (2 steps, 0.70 confidence, escalate below 0.25), default (5, 0.85, 0.35), thorough (8, 0.95, 0.45), unlimited (50, 0.98, 0.50). Retrieval quality is scored after each expansion; lexical relevance under 0.10 with an invalid semantic intent is a hard exit; semantic mismatch downgrades to moderate through `AgenticPolicyService`. `executeRecursiveResearch`: default max iterations 7, time budget 180 s, per-iteration decision over accumulated context with actions search or answer; call sites pass 5 (fallback on a reasoning miss) and 3 (verification-loop retry). Reasoning chain sessions: light 3, standard 4, deep 5, unlimited 50, each a 4,096-token window; rotating contexts with stride equal to chunks per session. True unlimited reasoning: target 0.98, max 50 sessions scaled to the evidence pool at three chunks per session, FactBank decomposition into subquestions, running synthesis, termination on target, saturation, cancellation or cap, tools disabled inside sessions. Internal calls set `executionContext = .onDeviceOnly`, `allowPrivateCloudCompute = false`, temperature 0.7. Final synthesis goes through `generateWithProperConsent`, which calls the post-retrieval planner. Memory turn limit by mode: roughly 5, 10, 20. Conversation memory summarises older turns.

**Expert's expert.** Recorded hazards in the source, all now fixed but worth knowing because they are the shape of what goes wrong here: citations resolved against the wrong array for the life of the chain; a shorter re-ordered list turning citations past its end into dangling references; a fabricated 0.70 match score hardcoded on the audit snapshot rather than measured, confirmed as exactly 0.7 on all 82 rows of one Deep Think run; the lost-in-middle reorder that interleaves the ranked set so the array reaching the chain is not in rank order. The bank's "Self-RAG" is a design label, not a distinct service; the behaviour is the critique and refine phases plus the gates. And "standard reasoning chain" means a bounded multi-step path inside some Standard answers that does not invoke the full orchestrator; it is easy to mistake for the agentic loop in logs.

## Every concept

### Agentic configuration (Conditional, verified)
- **Idiot:** the rules of the loop: how many rounds, how confident, how long.
- **Dot-connector:** an open-ended model loop needs deterministic bounds for battery, heat and quota.
- **Expert:** `AgenticConfig` resolved from mode, device policy and user action before the first step.

### Agentic phase (Conditional, verified) and ThinkingEvent (Support, verified) and Reasoning trace (Support, verified)
- **Idiot:** the loop tells you what it's doing: planning, searching, reading, writing.
- **Dot-connector:** explicit phases make the loop observable and let policy control what's legal next; typed events keep the UI honest without parsing logs.
- **Expert:** `ThinkingEvent` with phase, title, detail, counters, confidence; emitted through the SDK.

### AgenticOrchestrator (Conditional, verified)
- **Idiot:** the loop's brain.
- **Dot-connector:** planning, repeated retrieval, assessment, reformulation, fact accumulation, synthesis, refinement, verification.
- **Expert:** 8,780 lines; replaces the single-pass path in Deep Think, Maximum, forced and escalated runs.

### Analyzing phase (Conditional, verified)
- **Idiot:** read what you found.
- **Dot-connector:** extract facts, resolve sources, name what's missing; quantity is not completeness.
- **Expert:** after retrieval and expansion; decides synthesise, reformulate or search again.

### ChainLink (Conditional, verified)
- **Idiot:** a small note passed from one round to the next.
- **Dot-connector:** reasoning, condensed insight, next focus, cumulative confidence; a bounded state instead of a transcript.
- **Expert:** structured output in `RAGStructuredResponse`; produced by one session, consumed by the next.

### Convergence (Conditional, verified) and Evidence-driven stopping (Core, verified)
- **Idiot:** stop when nothing new is turning up.
- **Dot-connector:** coverage, confidence, novelty, contradictions and improvement decide, not a fixed count.
- **Expert:** `AgenticPolicyService` after each pass; can end the loop before the cap.

### Conversation summary (Conditional, verified) and ConversationMemoryService (Conditional, verified) and Memory turn limit (Core, verified)
- **Idiot:** the app remembers the gist of the chat so far, up to a point.
- **Dot-connector:** follow-ups need prior entities and constraints; the whole history would eat the window; roughly 5, 10 or 20 turns by mode, older ones summarised.
- **Expert:** consulted before rewriting, updated after answers; limits in `RAGQualityMode`.

### Coverage map (Conditional, verified)
- **Idiot:** a checklist of the question's parts.
- **Dot-connector:** the loop needs a concrete definition of "done."
- **Expert:** updated after each fact-analysis pass, checked before synthesis.

### Critique step (Conditional, verified) and Refining phase (Conditional, verified) and Self-RAG (Conditional, design label)
- **Idiot:** read your own draft, find the weak spots, fix them.
- **Dot-connector:** targeted repair beats restarting; this is what the bank calls Self-RAG.
- **Expert:** after synthesis, before refinement or abstention; can precede another verification pass.

### Default, Fast, Thorough, Unlimited agentic profiles (Conditional, verified)
- **Idiot:** four gears.
- **Dot-connector:** fast 2 steps, default 5, thorough 8, unlimited 50; confidence targets 0.70, 0.85, 0.95, 0.98; escalation floors 0.25, 0.35, 0.45, 0.50.
- **Expert:** `AgenticConfig` in `AgenticOrchestrator`; unlimited carries the "thermal will stop us first" comment.

### Evidence gap (Conditional, verified)
- **Idiot:** the specific thing still missing.
- **Dot-connector:** naming the gap makes the next search targeted.
- **Expert:** from evidence assessment; becomes the next reformulation or subquery.

### EvidenceThread (Core, verified)
- **Idiot:** a saved conversation, per library.
- **Dot-connector:** the user-visible thread persists separately from transient model sessions.
- **Expert:** `EvidenceThread` model, `EvidenceThreadStore`; loaded before memory processing.

### Expanding phase (Conditional, verified)
- **Idiot:** pull in the neighbours.
- **Dot-connector:** the first hit is usually an anchor, not the whole answer.
- **Expert:** parents, siblings, cross-references, entities, graph neighbours, broader candidates.

### Fact (Conditional, verified), Fact deduplication (Conditional, verified), Fact provenance (Conditional, verified), FactBank (Conditional, verified)
- **Idiot:** the notebook, one fact per line, each with where it came from, no repeats.
- **Dot-connector:** atomic facts can be deduplicated, checked for contradictions and mapped to sources; repeats raise confidence instead of consuming state; the bank is what makes fresh sessions possible.
- **Expert:** initialised after planning, updated after analysis, consumed by final synthesis; provenance reused for citations.

### Hard session cap (Core, verified)
- **Idiot:** an absolute maximum number of rounds.
- **Dot-connector:** protects battery, heat, latency, quota and cancellation even if convergence never comes.
- **Expert:** checked before each session; 50 for unlimited, scaled to the pool.

### LLM call count (Support, verified) and Reasoning-chain token total (Support, verified)
- **Idiot:** how many times the model was asked, and how many tokens that cost in total.
- **Dot-connector:** one 4,096 window per session says nothing about the whole answer's cost.
- **Expert:** accumulated in `RAGService`, stored in audit metadata.

### Planning phase (Conditional, verified)
- **Idiot:** decide what to look for before looking.
- **Dot-connector:** searching before defining requirements finds relevant passages that still don't answer.
- **Expert:** first phase; identifies subquestions and an initial strategy.

### ReasonedInsight (Conditional, verified) and ReasonedSynthesis (Conditional, verified)
- **Idiot:** the note from a reading round, and the final write-up.
- **Dot-connector:** insight: analysis, one key point, discovered terms, confidence. Synthesis: key points, confidence, sources, reconciled rather than concatenated.
- **Expert:** structured types in `RAGStructuredResponse`.

### Reasoning session (Conditional, verified)
- **Idiot:** one fresh conversation with the model, for one job.
- **Dot-connector:** fresh sessions avoid overflow and separate assessment from answer writing.
- **Expert:** one `LanguageModelSession` per objective; sequential or conditional.

### Recursive RAG (Conditional, verified)
- **Idiot:** several small searches and reads instead of one giant one.
- **Dot-connector:** many 4,096-token sessions can collectively read more than one can, if only condensed state moves forward.
- **Expert:** begins after planning, ends with synthesis over accumulated state; `executeRecursiveResearch` with its two call sites.

### Reformulating phase (Conditional, verified)
- **Idiot:** ask it differently.
- **Dot-connector:** repeating a failed search can't find a new neighbourhood.
- **Expert:** after gap analysis, before a new search pass.

### Searching phase (Conditional, verified)
- **Idiot:** go look.
- **Dot-connector:** hybrid retrieval for the current sub-question; grounded before claims.
- **Expert:** module 08's pipeline invoked per sub-question.

### Standard reasoning chain (Conditional, verified)
- **Idiot:** a little bit of structured thinking inside a normal answer.
- **Dot-connector:** bounded, no open-ended retrieval loop; easy to mistake for the agentic path in logs.
- **Expert:** in `RAGService` after context selection, before verification.

### Synthesizing phase (Conditional, verified)
- **Idiot:** write the answer.
- **Dot-connector:** only after coverage or stopping policy says there's enough.
- **Expert:** consumes the FactBank; goes through the post-retrieval plan.

### Verifying phase (Conditional, verified)
- **Idiot:** check it.
- **Dot-connector:** more model calls don't make an answer trustworthy; the gates still run.
- **Expert:** `VerificationGateService` after synthesis or refinement; can trigger repair or abstention.
# Module 12. Verification, grounding, confidence, and abstention

Forty concepts. The nine checks: deterministic gates that decide whether the generated answer is allowed to stand, and what the app says when it isn't.

## The ladder

**Like you're five.** After the writer finishes, a very grumpy checker reads every sentence and asks: is this actually on one of the cards? Does this number match? Is this even about the same thing? Anything that isn't on a card gets crossed out. If too much is crossed out, the phone says "I don't have enough to answer that" instead of guessing.

**Like an idiot.** The model can invent. So after it writes, nine rule-based checks run in a fixed order. A: was the search even confident? B: does every claim cite something? C: do the numbers exist in the sources? D: do the sources contradict each other? E: does the answer's meaning stay close to its evidence? F: are quotes real? G: is the output usable? H: does it answer the whole question? I: is the evidence from the right domain? Failed claims are removed or marked unsupported. If too little survives, the app abstains.

**Like less of an idiot.** The gates work on a structured answer: atomic claims with evidence IDs, which is what makes B mechanically checkable. Some gates are critical: retrieval confidence, numeric sanity and semantic grounding can each force abstention alone. Gate E is the interesting one: it embeds the answer and compares it with its best source chunk; below 0.50 the answer is semantically ungrounded. Confidence is then calibrated from retrieval scores, gate results and session depth, and compared against a mode-dependent bar. Fidelity is a separate number: how well the cited sources support the visible text, shown as Source-Locked, Partially Supported or Not Enough Evidence. Touchy queries (medical, legal, financial, safety, dosage) raise the bars.

**Average Joe.** Why is confidence different from fidelity? Because they answer different questions. Confidence is "how sure are we overall." Fidelity is "does the text on screen match the sources it cites." A confident answer with low fidelity is exactly the failure the gates exist to catch. Why is "not found" checked too? Because saying something isn't in the documents is itself a claim, and it should not be issued after a shallow miss. And why calibrate at all? Because raw scores from different stages live on different scales and are overconfident; the displayed percentage is a heuristic policy, not a proven probability.

**Dot-connector.** Where the gates sit: after a draft answer and before it is accepted, sanitised, or replaced. A source-only fallback can construct an extractive answer from source sentences when generative grounding fails, which is why "abstain" isn't the only alternative to a bad answer. An answer-replacement guard stops a later stage from swapping a strong extractive answer for a weaker generated one. And domain isolation runs on claim-evidence pairs so shared words across medicine, law and engineering can't create false support.

**Expert.** `VerificationGateService`, an actor. Config: `tauNormal` 0.40 (lowered from 0.55 because keyword-heavy queries carry low semantic scores even when BM25 found the right content), `tauTouchy` 0.55, margin `mu` 0.03, semantic grounding 0.50; touchy categories medical, legal, financial, safety, dosage, drug, medication; strict profile 0.65, 0.75, 0.10, 0.60 with regulatory and compliance added. Gate A: top rerank score ≥ tau and top-one minus top-two ≥ mu. Gate B: each claim cites at least one evidence ID; verdicts supported, partial, unsupported. Gate C: numbers must appear in the candidate set, using the full set rather than the packed context because the model may cite a trimmed chunk; numeric-unit checks compare units and qualifiers. Gate D: contradiction sweep including negation indicators. Gate E: response embedding versus best source, plus topical alignment and relative grounding. Gate F: quote spans exist at the attributed location. Gate G: empty, malformed, repetitive, truncated. Gate H: facets versus claims and missing fields. Gate I: `DomainIsolationService`, with a scientific-domain claim check. `ConfidencePolicyService` resolves thresholds and calibration parameters (slope, intercept, penalties, conservative set) per intent, touchy status and mode; `ConfidenceCalibrationService` applies them; mode bars 0.50, 0.60, 0.80. `SourceOnlyAnswerService` builds extractive fallbacks and verifies absence assertions.

**Expert's expert.** The bar for Maximum was 0.98 until every Maximum answer failed verification; it is 0.80. The `tauNormal` history (0.55 to 0.40) is the same lesson from the other side: a bar tuned to one query shape starves another. Gate E is the one gate that costs an inference, and its 0.50 floor is a cosine on the same 384-dimension space the retrieval uses, so a library embedded with a different provider changes what "grounded" means. And the calibration caveat is not decoration: no held-out outcome frequencies have been collected, so an on-screen 80% is a policy output, and saying otherwise in an interview would be the kind of claim this app was built to refuse.

## Every concept

### Absence assertion (Core, verified)
- **Idiot:** "it's not in here" has to be earned.
- **Dot-connector:** not-found is a factual claim; it needs broad retrieval and search checks behind it.
- **Expert:** verified before final abstention wording in `SourceOnlyAnswerService`; `AbsenceAssertionTests`.

### Abstention (Core, verified) and Abstention threshold (Core, verified)
- **Idiot:** the app says no rather than guessing, and the bar for that gets higher in the harder modes.
- **Dot-connector:** a valid no-answer outcome is what stops every retrieval miss from becoming a hallucination.
- **Expert:** before generation, after a critical gate fails, after failed refinement, or at calibration; threshold from `ConfidencePolicyService`, stricter for touchy queries and higher modes.

### Answer replacement guard (Core, verified)
- **Idiot:** don't replace a good answer with a worse one.
- **Dot-connector:** multi-stage pipelines can regress after producing a correct extractive answer.
- **Expert:** evaluated when agentic, source-only or formatting paths propose a replacement; `AnswerReplacementGuardTests`.

### Bibliography penalty (Core, verified)
- **Idiot:** the reference list doesn't count as an answer.
- **Dot-connector:** it contains the query terms and the author names and states none of the findings.
- **Expert:** `ReferenceListDetector` output applied during retrieval or verification; `BibliographyPenaltyTests`.

### Calibration caveat (Core, documented) and Calibration parameters (Core, verified) and Confidence calibration (Core, verified) and Confidence policy (Core, verified)
- **Idiot:** the confidence number is adjusted to be more careful, and it's still not a real probability.
- **Dot-connector:** slope, intercept, penalties and a conservative set, chosen per intent, touchy status and mode; applied after verification; never validated against outcome frequencies.
- **Expert:** `ConfidencePolicyService` picks, `ConfidenceCalibrationService` applies; `Docs/EVALS.md` records the caveat.

### Claim verification verdict (Core, verified), Supported claim (Core, verified), Partially supported claim (Core, verified), Unsupported claim (Core, verified)
- **Idiot:** every sentence gets a grade: yes, partly, no.
- **Dot-connector:** one global confidence hides which assertions are reliable; partial keeps useful content while lowering trust; unsupported must not survive on plausibility.
- **Expert:** produced by Gate B, stored per claim on `StructuredAnswer`; unsupported triggers removal, refinement or abstention.

### Critical gate (Core, verified)
- **Idiot:** some checks can fail the whole answer on their own.
- **Dot-connector:** retrieval confidence, numeric sanity, semantic grounding.
- **Expert:** critical status interpreted when gate results are combined.

### DomainIsolationService (Core, verified) and Gate I: Domain Isolation (Core, verified) and Scientific-domain claim check (Conditional, verified)
- **Idiot:** don't let a car manual "support" a medical claim because both say "pressure."
- **Dot-connector:** classifies claim and evidence domains and blocks incompatible support; research text gets special handling for methods, results and bibliography language.
- **Expert:** runs after evidence mapping, before final verdicts; can remove or abstain on contaminated claims.

### Evidence-first mode (Core, verified) and Source-only verification (Core, verified) and SourceOnlyAnswerService (Core, verified)
- **Idiot:** the sources are the boss; the writer only rearranges them.
- **Dot-connector:** reverses generate-then-find-citations; the answer must be reconstructible from source sentences; when generation fails, an extractive answer beats a guess.
- **Expert:** resolved before generation by `GroundedAnswerPolicy`; `SourceOnlyAnswerService` builds or validates from source sentences and may replace a failed generative answer before abstention.

### Fidelity (Core, verified), Source-Locked (Core, verified), Partially Supported (Core, verified), Not Enough Evidence (Core, verified)
- **Idiot:** the badge: fully backed, partly backed, not enough.
- **Dot-connector:** fidelity is source support specifically, distinct from confidence; the three states expose mixed support instead of one green badge.
- **Expert:** `SourceFidelityStatus` derived after verification.

### Gate A: Retrieval Confidence (Core, verified)
- **Idiot:** was the search good enough to answer from at all?
- **Dot-connector:** no phrasing compensates for an evidence set that never found the answer.
- **Expert:** top rerank ≥ tau (0.40 or 0.55), margin ≥ 0.03; critical.

### Gate B: Evidence Coverage (Core, verified)
- **Idiot:** does every sentence point at a card?
- **Dot-connector:** an answer can cite globally while individual claims float.
- **Expert:** decomposes into claims; assigns verdicts.

### Gate C: Numeric Sanity (Core, verified) and Numeric-unit verification (Core, verified)
- **Idiot:** the numbers, with their units, must be in the sources.
- **Dot-connector:** 5 mg and 5 mL are not the same; "maximum" versus "typical" changes the claim; a digit change inverts meaning.
- **Expert:** checked against the full candidate set; critical.

### Gate D: Contradiction Sweep (Core, verified)
- **Idiot:** do the sources disagree with each other or with the answer?
- **Dot-connector:** a high-similarity source can still contradict another.
- **Expert:** includes negation-indicator checks; contributes to confidence or abstention.

### Gate E: Semantic Grounding (Core, verified)
- **Idiot:** does the answer mean what the sources mean?
- **Dot-connector:** token overlap misses paraphrased fabrication; embedding comparison catches drift.
- **Expert:** response embedding versus best source, floor 0.50, plus topical alignment and relative grounding; critical; one inference.

### Gate F: Quote Faithfulness (Core, verified) and Quote-span verification (Core, verified)
- **Idiot:** if it's in quotes, it had better be there.
- **Dot-connector:** a fake quote with a real citation is worse than an uncited paraphrase.
- **Expert:** spans checked at the attributed location or an accepted normalised match; abbreviation cross-contamination handled.

### Gate G: Generation Quality (Core, verified)
- **Idiot:** is the output even usable?
- **Dot-connector:** grounded but truncated or malformed still fails as a response.
- **Expert:** empty, malformed, repetitive, truncated checks over the structure.

### Gate H: Answer Completeness (Core, verified) and Missing-information list (Core, verified)
- **Idiot:** did it answer the whole question, and what's missing?
- **Dot-connector:** partial coverage presented as complete misleads; naming the gap makes a refusal useful.
- **Expert:** facets versus claims; `missing` populated during extraction, completeness and `StructuredAnswer` construction.

### Precision lock (Conditional, verified)
- **Idiot:** when the exact value is nailed, don't let the writer touch it.
- **Dot-connector:** paraphrase degrades exact values.
- **Expert:** triggered by extractive scoring thresholds before synthesis; `EvidenceScoringPolicyService` and `SourceOnlyAnswerService`.

### Raw confidence (Core, verified)
- **Idiot:** the unadjusted score.
- **Dot-connector:** an internal signal from model output, retrieval scores, claim support or extraction strength; not a probability.
- **Expert:** passed to calibration and UI mapping.

### Reliability mode (Core, verified)
- **Idiot:** the "be careful" setting.
- **Dot-connector:** favours grounded fallback, verification and explicit uncertainty over permissive output.
- **Expert:** read by `QueryRuntimeCoordinator`.

### Verification configuration (Core, verified) and VerificationGateService (Core, verified)
- **Idiot:** the rulebook and the checker.
- **Dot-connector:** one centralised threshold bundle so no answer path uses a contradictory standard; the checker is the final enforcement boundary.
- **Expert:** 0.40 / 0.55 / 0.03 / 0.50 default; strict 0.65 / 0.75 / 0.10 / 0.60; an actor that runs after the draft and before acceptance, sanitisation or replacement.
# Module 13. Response structure, provenance, rendering, and observability

Thirty-five concepts. What comes back and how you can inspect it: typed answers, citations to character ranges, the route badge, and the trace that records every stage.

## The ladder

**Like you're five.** The answer comes back with little sticky notes on every sentence that jump to the exact line on the exact card. There's a label saying where the writer sat. And there's a diary of everything the librarian did, in case something looks wrong.

**Like an idiot.** The response is not a string. It's a structured answer: claims with evidence IDs, evidence records with a page and a short quote, a refuse flag, a missing-information list, the answer type. Citations map to character ranges in the source because ingestion recorded offsets. The badge shows which model completed the answer, from the receipt. The diagnostics show how many chunks were found, kept, dropped and packed. A trace log on disk records every stage with timings.

**Like less of an idiot.** Two layers. Internally `RAGResponse` carries answer text, retrieved chunks, confidence, abstention, reasoning trace, metadata and diagnostics; `StructuredAnswer` is the durable claim-oriented contract between generation, verification, storage and rendering. Externally the SDK exposes `OIQueryResult`, `OICitation` and `OIQueryProgressEvent` so other clients get the same provenance without the app's SwiftUI types. Evidence quotes are capped around 240 characters. Everything is persisted into a per-library evidence thread. Observability comes from typed `ThinkingEvent`s for the live UI, `TelemetryCenter` events, os-signposts for Instruments, an audit snapshot per query, a retrieval trace collector for evaluation, and the pipeline trace file.

**Average Joe.** Why so much plumbing around the answer? Because an answer you can't audit is a guess with good typography. Every piece here exists so that a wrong answer can be traced to the stage that produced it: was it extraction, retrieval, packing or generation? The feature flags on the audit snapshot record what actually ran, because configured capability is not executed capability.

**Dot-connector.** The route badge reads from the execution receipt, not the model picker, because a PCC plan can fall back to on-device and the badge must show the fallback. The hardware HUD's Neural Engine pulse is synthetic: there is no public API for Neural Engine occupancy, so the display shows activity around compute-heavy stages, not a measurement. And the pipeline trace log rotates, which is why a long capture needs `tail -F` into an archive before you start.

**Expert.** `StructuredAnswer`: refusal state, answer type (lookup, table lookup, procedure, compare, summarise, investigate, compute, findings, refused), text, atomic claims with verdicts, evidence records (ID, page, quote ≤ ~240 chars, document, section path), missing information, debug data; built from deterministic extraction or structured generation; sanitised before display. `EvidenceThreadStore` persists threads. `GroundedAnswerView`, `SourceChipsView`, `RetrievalSourcesTray`, `UnifiedMetricsBar`, `TimingBreakdownView`, `ContextUsageIndicator`, `ThinkingStreamView`, `ResponseDetailsView`, `EnhancedCodeBlock`, `MarkdownRenderer`. `RAGAuditSnapshot` with feature flags (rewrite, expansion, HyDE, iterative, routing, summaries, parent, corrective, compression, graph packing, cascade, multi-vector, unlimited reasoning), score distribution, candidate counts, context budget, route, recursive metrics, `acceptanceOverride`. `RetrievalTraceCollector` records vector, lexical, fusion, boosted, candidate, rerank and final stages for evaluation. `PipelineSignposts`; `TelemetryCenter`; `HardwareTelemetryState`; `PipelineTraceExporter` and `scripts/pull_trace.sh`; the trace file is `pipeline_trace.log` in the app container's Documents folder. `ResponseTransformService` and `WritingToolsService` for post-answer rewriting without re-entering retrieval.

**Expert's expert.** The audit snapshot once carried a fabricated `top_similarity` of exactly 0.7 on every row of a Deep Think run because it was hardcoded rather than measured; observability that lies is worse than none, and it is why the feature flags and score distributions are checked against the retrieval trace in evaluation. The evidence quote cap is also a privacy choice: 240 characters is enough to inspect and small enough not to leak a document into a stored thread.

## Every concept

### Enhanced code block (Conditional, verified) and Markdown renderer (Core, verified)
- **Idiot:** code looks like code; lists look like lists.
- **Dot-connector:** technical answers lose meaning as one plain string.
- **Expert:** `MarkdownRenderer` block-aware; `EnhancedCodeBlock` with language labels and copy.

### Evidence ID (Core, verified), Evidence record (Core, verified), Evidence quote cap (Core, verified), Inline citation (Core, verified), Source chip (Core, verified)
- **Idiot:** the sticky notes and the tappable sources under the answer.
- **Dot-connector:** a stable ID under the human-readable number; a record with page, quote, document, section; quotes capped near 240 characters; citations sit next to the claim; chips open the actual passage.
- **Expert:** `StructuredAnswer` evidence model; `SourceChipsView`, `RetrievalSourcesTray`.

### Evidence-thread persistence (Core, verified)
- **Idiot:** the conversation is saved.
- **Dot-connector:** a verified answer stays reproducible after the query task ends.
- **Expert:** `EvidenceThreadStore` after finalisation, before idle.

### Execution-route metadata (Core, verified)
- **Idiot:** the badge that says where the writer sat.
- **Dot-connector:** from execution evidence, not the picker.
- **Expert:** initialised at runtime resolution, finalised from `ModelExecutionReceipt`.

### Grounded answer view (Core, verified)
- **Idiot:** the answer screen.
- **Dot-connector:** grounding visible at the point you read the claim.
- **Expert:** `GroundedAnswerView` consuming the verified structured response.

### Hardware telemetry pulse (Support, verified as synthetic)
- **Idiot:** the little lights that blink when the phone is working hard.
- **Dot-connector:** makes invisible local computation legible; not a measurement.
- **Expert:** `HardwareTelemetryState` emitted around compute stages; consumed by the Motherboard HUD; Neural Engine utilisation is not observable.

### OICitation (Core, verified), OIEngine (Core, verified), OIQueryProgressEvent (Support, verified), OIQueryResult (Core, verified)
- **Idiot:** the version of all this that other apps can use.
- **Dot-connector:** a stable boundary above the 19,000-line orchestrator; the same provenance and route truth as the first-party UI.
- **Expert:** `SDK/OpenIntelligenceEngine.swift`.

### Pipeline signpost (Support, verified), Pipeline trace (Support, verified), PipelineTraceExporter (Support, verified)
- **Idiot:** the diary, and the way to share it.
- **Dot-connector:** Instruments measures stage latency from signposts without parsing logs; the trace is the reproducible artefact for device-only failures.
- **Expert:** `PipelineSignposts`; `pipeline_trace.log` in the container Documents; exporter plus `scripts/pull_trace.sh`.

### RAG audit feature flags (Support, verified) and RAGAuditSnapshot (Support, verified)
- **Idiot:** a checklist of what actually ran, and the full conditions of the run.
- **Dot-connector:** configured is not executed.
- **Expert:** assembled as stages complete in `RAGService`.

### RAGResponse (Core, verified), Response metadata (Core, verified), StructuredAnswer (Core, verified), Structured answer type (Core, verified), Refuse flag (Core, verified)
- **Idiot:** the answer object and its labels.
- **Dot-connector:** richer than a string so verification, UI, SDK and evaluation agree on what happened; the refuse flag is machine-readable, not inferred from wording.
- **Expert:** `RAGQuery.swift`, `StructuredAnswer.swift`.

### Response transformation (Conditional, verified) and Writing Tools integration (Conditional, verified)
- **Idiot:** rewrite or summarise the answer afterwards.
- **Dot-connector:** presentation changes that never re-enter retrieval and never replace provenance silently.
- **Expert:** `ResponseTransformService`; `WritingToolsService` as an explicit user action.

### Retrieval diagnostics (Support, verified), RetrievalLogEntry (Support, verified), RetrievalTraceCollector (Support, verified)
- **Idiot:** the numbers behind the search, and the exact lists at each stage.
- **Dot-connector:** counts can't show whether the right chunk survived; stage traces preserve identity and order.
- **Expert:** diagnostics on `RAGStructuredResponse`; the collector records seven stages for evaluation and is discarded after scoring.

### TelemetryCenter (Support, verified), Thinking stream (Support, verified), Timing breakdown (Support, verified), Token-budget metadata (Core, verified), Unified metrics bar (Support, verified)
- **Idiot:** the dashboards.
- **Dot-connector:** typed events decoupled from UI; live progress without raw reasoning; retrieval versus generation time; why evidence was compressed or omitted; one place for the operating evidence.
- **Expert:** `TelemetryCenter`, `ThinkingStreamView`, `TimingBreakdownView`, `ContextUsageIndicator`, `UnifiedMetricsBar` (4,669 lines).
# Module 14. Evaluation, benchmarks, and quality measurement

Thirty-one concepts. Measuring whether any of this works, and the two lessons that made most earlier figures unusable.

## The ladder

**Like you're five.** To know if the librarian is good, you give her a test with questions you already know the answers to, and count how often she finds the right card and gives the right answer. And sometimes you hide the answer in the middle of a pile to see if she finds it there.

**Like an idiot.** There's a harness that ingests test documents, runs questions through the real engine, records what every retrieval stage returned, and scores it: did the right chunk get found, how high did it rank, was the answer right, did the app abstain when it should have. Runs are recorded in a ledger. Baselines are frozen so changes can be compared. External question sets are used because questions you write yourself are too easy.

**Like less of an idiot.** Retrieval metrics: recall at k, precision at k, mean reciprocal rank, nDCG, and stage survival (did the correct chunk make it from vector or lexical through fusion, boosts, rerank and final). Answer metrics: exact match, token F1, hallucination rate, abstention accuracy, error rate. Route metrics: invariants on the execution receipt (completed route was attempted, fallback is attributed, denied or unknown cloud fails closed). Paired comparisons and an exact sign test say whether a change is consistent or driven by outliers.

**Average Joe.** Two lessons dominate everything here. Chunk-level retrieval was once scored against document-level ground truth, so multiple chunks from one relevant document each counted as a hit and nDCG reported 2.131, above its own ceiling. And retrieval is nondeterministic: two runs of one build return different chunks for one question, so no A/B is trustworthy until that's fixed. There's a third, human lesson: twice, one real document on real hardware found what the whole synthetic suite missed.

**Dot-connector.** Evaluation is the only place the app's numbers become claims you can defend. The ledger is the only citable source for a figure. Run directories are never deleted because they're gitignored and the raw results file is the only evidence behind whatever the ledger says; three were lost once. And the evidence-level vocabulary (code-verified, test-verified, simulator-verified, device-verified, measured, inferred) exists so that "it's in the source" is never confused with "it works on a phone."

**Expert.** `RAGEvalRunner` ingests fixtures, runs queries with `RetrievalTraceCollector` attached, aggregates through `RAGEvalMetrics` and `RetrievalStageMetrics`, writes with `RAGEvalReportWriter`. Datasets: `RAGEvalDataset` with schema validation; the tiny research suite (exact lookup, missing information, multi-hop, rank retrieval, lost-in-the-middle) for fast regression; QASPER external fixtures with distractor papers to counter synthetic-fixture bias. `RouteEvalMetrics` checks completed-route attestation, fallback attribution and the fail-closed invariant against receipts. Credited relevance maps chunks to ground truth with accepted equivalence so parent expansion isn't penalised. Scripts: `run_quality_matrix.py`, `compare_benchmark_runs.py`, `sweep_fusion_weight.py`. Ledger: `BenchmarkRuns/LEDGER.md` and `PROGRESSION.md`; baselines under `Benchmarks/baselines`. Device runs through `scripts/run_device_tests.sh`.

**Expert's expert.** The benchmark harness runs the macOS Debug build and writes into the real app library unless pointed elsewhere, which polluted the owner's documents once; aim it at the simulator. A hung app process on timeout used to poison every later case because the kill pattern matched the harness's own command line. The `VersionHistoryTests` make the user changelog a build input, so a doc edit mid-run breaks the run. None of these are pipeline facts; all of them are why benchmark numbers in this repo carry provenance.

## Every concept

### Abstention accuracy (Support, verified), Answer accuracy (Support, verified), Error rate (Support, verified), Exact match (Support, verified), Hallucination rate (Support, verified), Token F1 (Support, verified)
- **Idiot:** the scorecard: right answers, right refusals, crashes, exact hits, made-up stuff, partial credit.
- **Dot-connector:** always answering and always refusing are both bad; exact match suits short lookups; F1 gives credit for right-but-reworded; hallucination rate is reported beside accuracy because aggressive answering raises one and worsens the other; errors are counted separately so infrastructure failures don't hide in quality.
- **Expert:** `RAGEvalMetrics`.

### Benchmark baseline (Support, verified) and Benchmark ledger (Support, verified)
- **Idiot:** the frozen reference, and the logbook.
- **Dot-connector:** without a baseline, plausible-looking runs hide regressions; the ledger outlives the machine.
- **Expert:** `Benchmarks/baselines`; `BenchmarkRuns/LEDGER.md`, `PROGRESSION.md`. Never delete a run directory.

### Completed-route attestation (Support, verified), Fail-closed route invariant (Support, verified), Fallback attribution invariant (Support, verified), Route invariant (Support, verified)
- **Idiot:** the badge has to be backed by a receipt.
- **Dot-connector:** a completed target must appear in the attempt chain with success; a different completed target needs a fallback reason; denied or unknown cloud never completes on PCC.
- **Expert:** `RouteEvalMetrics` over receipts in route benchmarks and tests.

### Credited relevance (Support, verified) and Stage survival (Support, verified)
- **Idiot:** did the right card make it through every stage, counting near-misses fairly.
- **Dot-connector:** chunk boundaries and parent expansion produce relevant evidence without the exact ID; a stage can keep counts while dropping the only correct item.
- **Expert:** `RetrievalStageMetrics` over `RetrievalTraceCollector` outputs in pipeline order.

### Distractor document (Support, verified), QASPER fixture (Support, verified), Synthetic fixture bias (Support, documented), Tiny research suite (Support, verified)
- **Idiot:** hard tests, with decoys, written by someone else.
- **Dot-connector:** a corpus with only the answer document measures nothing; self-authored questions flatter the engine; the tiny suite is fast regression, not accuracy estimation.
- **Expert:** `Benchmarks/ResearchFixtures/qasper_external_v1`, `tiny_research_suite`, `rag_eval_qasper_v1.jsonl`.

### Evaluation case (Support, verified), Evaluation dataset (Support, verified), Evaluation report writer (Support, verified), RAGEvalRunner (Support, verified)
- **Idiot:** one question, the collection, the report, the machine that runs them.
- **Dot-connector:** explicit ground truth over anecdotes; versioned datasets prevent cherry-picking; durable reports for later audit.
- **Expert:** `RAGEvalCase`, `RAGEvalDataset`, `RAGEvalReportWriter`, `RAGEvalRunner`.

### Evidence level (Support, documented)
- **Idiot:** how do we know this is true?
- **Dot-connector:** code-verified, test-verified, simulator-verified, device-verified, measured, inferred, unverified; source proves implementation, not runtime behaviour.
- **Expert:** attached to documentation and audit conclusions; `CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`.

### Exact sign test (Support, documented) and Paired comparison (Support, verified)
- **Idiot:** did A beat B case by case, not just on average?
- **Dot-connector:** wins, losses and ties show whether an improvement is consistent or a few outliers; the sign test needs no normality assumption.
- **Expert:** `scripts/compare_benchmark_runs.py`; `Docs/EVALS.md`.

### Mean reciprocal rank (Support, verified), Normalized discounted cumulative gain (Support, verified), Precision at k (Support, verified), Recall at k (Support, verified)
- **Idiot:** how soon the first good card shows up, how well the whole order is, how clean the top is, how much of the good stuff was found.
- **Dot-connector:** recall measures finding; precision measures not wasting context; MRR first hit; nDCG the whole ranking with graded relevance. Score chunks against chunk-level truth or you get 2.131.
- **Expert:** `RetrievalStageMetrics`, computed per stage from trace identities.

### Physical-device verification (Support, verified)
- **Idiot:** try it on a real phone.
- **Dot-connector:** Apple Intelligence, thermal, Neural Engine scheduling, PCC, background processing and memory pressure differ from the simulator; the final evidence tier.
- **Expert:** `scripts/run_device_tests.sh`; `Docs/AuditArtifacts/Implementation`.

### Quality matrix (Support, verified)
- **Idiot:** a grid of modes and settings, all scored.
- **Dot-connector:** regressions are interactions, not single settings.
- **Expert:** `scripts/run_quality_matrix.py`; results under `Docs/AuditArtifacts/Benchmarks`.
# Module 15. Device adaptation, compute, background work, sync, and product limits

Forty-four concepts. The power manager and the janitor: how hard the device may work, what runs in the background, how libraries sync, and what the tiers limit.

## The ladder

**Like you're five.** The phone checks what kind of phone it is and how hot it is, and decides how hard to work. When it's too hot, it slows down. Some chores wait until the phone is plugged in. If you have two devices, the library can be the same on both, carefully, so nothing gets deleted by accident.

**Like an idiot.** One configuration can't serve a fanless MacBook Air and an iPhone in a hot car. So the app detects the chip, memory and GPU limits once and hands every subsystem an envelope: batch sizes, concurrency, agentic depth, cooldowns. You get a GPU profile lever on top: Efficiency, Balanced, Performance, Maximum. Thermal and memory pressure dial the pipeline down. Background tasks let ingestion and index maintenance continue when iOS allows. iCloud sync exists so a library is the same on every device, with guards so a not-yet-downloaded file never looks like an empty library.

**Like less of an idiot.** Five device tiers from the chip: baseline (A17 Pro), enhanced (A18), advanced (A19), ultra-advanced (M-series), unsupported. From tier and memory come agentic step concurrency, step cooldown, vector batch, embedding batch, the matrix-multiply threshold, Vision concurrency, render concurrency and embedding concurrency. The GPU profile sets Core ML compute units, whether Metal may be used for the MMR matrix, and concurrency ceilings. An adaptive optimiser picks full, balanced, efficient or minimal per query from thermal state, memory pressure and complexity. Five background task identifiers are registered on iOS only. Sync is per-library, local-only or iCloud-shared, with tombstones, deletion-wins, a materialisation guard, a write-in-progress guard, and a signature cache so an unchanged store isn't re-read.

**Average Joe.** Why does the GPU profile exist as a user choice at all? Because the app cannot promise a utilisation percentage; it can promise a policy. Efficiency keeps models on CPU plus Neural Engine and avoids GPU vector work; Maximum removes internal limits. Why did Maximum get slower than Performance once? Because it requested CPU plus GPU, which excludes the Neural Engine. Why is "38 TOPS" on screen a lookup? Because Apple exposes no live Neural Engine measurement; the number is a per-chip table.

**Dot-connector.** The two guards that came from real data loss. The materialisation guard: iCloud reports a vector store exists but the bytes aren't downloaded; without the guard, that read as an empty library and triggered a destructive overwrite. Deletion-wins plus tombstones: a device that still has the last full copy would otherwise resurrect what you deleted. And the open defect lives here: a 1.68-second idle timer in `WorkspaceSyncService` that fires because a container's orphaned state never resolves. It used to reload every vector store per tick, 2,848 loads in 164 idle seconds; the router's on-disk signature check made it cheap; the timer is still there.

**Expert.** `DeviceCapabilityService`: `utsname` for the device model, `sysctlbyname("machdep.cpu.brand_string")` on Mac, physical memory, a Metal device query for GPU limits; TOPS lookup per chip (35 A17 Pro, 35/38 A18/A18 Pro, 38 every M4, 45 every M5; a new Mac was once tiered as M3-era because M5 was unknown, fixed late August). Ladder: agentic step concurrency 3 to 32, step cooldown 100 ms to 0, vector batch 128 to 16,384, embedding batch 8 to 512, Vision concurrency 2 to 64, PDF render concurrency 1 to 64 capped by a per-page memory estimate, embedding concurrency 2 to 64. GPU profile to compute units: query-side models Efficiency and Balanced `.cpuAndNeuralEngine`, Performance and Maximum `.all`; ingestion embedder Efficiency `.cpuAndNeuralEngine`, the rest `.all`. `AdaptivePipelineOptimizer`: thermal critical forces minimal; memory pressure critical forces efficient; serious thermal no longer throttles; battery alone no longer degrades; on Mac only thermal and memory matter; query timeout and step cooldown per level. `BackgroundTaskService` and `OpenIntelligenceApp`: continued ingestion, continued query (system-scheduled), index maintenance no earlier than 4 h and `requiresExternalPower`, Spotlight reindex no earlier than 2 h, app refresh no earlier than 30 min; iOS only. `IngestionLiveActivityService` updates within 0.5 s. `WorkspaceSyncService` (3,866 lines): debounce 2 s, bootstrap conflict detection, merge plan, tombstones, deletion-wins, materialisation guard, write-in-progress guard, vector sync signature cache. `QuotaPolicy` for document and library limits and the free-tier Maximum daily allowance; `EntitlementStore` and `MonetizationPolicy` from StoreKit; `MaximumModeQuotaStore`. `SettingsStore` snapshotted at query start. `LoggingConfiguration` for levels, categories, buffering and redaction. `GPUComputeService` kernels: batch cosine similarity (plus SIMD and threadgroup variants), batch normalise, MMR diversity; buffer pool; residency set. `BNNSGraphService` for normalisation, matrix cosine, softmax, RRF arithmetic and pairwise similarity on Accelerate.

**Expert's expert.** Correction to the bank's GPU-profile entry: it does not gate the vector-search GPU path; module 06 has the two real conditions. The bank's "Performance profile moves sufficiently large searches to GPU" is the same error from the other side; large searches go to the GPU under any profile if a Metal device exists. "Metal Performance Shaders" appears as a concept; the kernels in `GPUComputeService` are custom Metal functions, so treat MPS as infrastructure vocabulary rather than a distinct code path. Unified memory is why the mmap-to-Metal handoff is near-zero-copy and also why Vision, Core ML and the vector store compete inside one process budget, which is what the throttle, the buffer pool and the memory-warning listener are for.

## Every concept

### AdaptivePipelineOptimizer (Core, verified) and Full, Balanced, Efficient, Minimal optimization levels (Core/Conditional, verified)
- **Idiot:** the dimmer switch, with four positions.
- **Dot-connector:** full is everything permitted; balanced disables some repeated work; efficient drops HyDE, compression and iteration and shrinks batches; minimal keeps only essential retrieval and generation with no agentic steps. Critical heat picks minimal, critical memory picks efficient.
- **Expert:** resolved per query after complexity and device state; adjusts features, candidate limits, context, rerank batch, agentic steps, cooldowns, timeout, thresholds and MMR.

### Balanced profile (Core, verified), Efficiency profile (Core, verified), Performance profile (Core, verified), Maximum GPU profile (Core, verified), GPU execution profile (Core, verified)
- **Idiot:** the user's four-position lever for how much silicon to use.
- **Dot-connector:** Efficiency keeps models on CPU plus Neural Engine; Balanced allows GPU for indexing and rendering; Performance allows all units; Maximum removes internal limits. It governs Core ML units, the MMR matrix and concurrency, not the vector-search GPU switch.
- **Expert:** `DeviceCapabilityService`; the `.cpuAndGPU` Maximum bug fixed 2026-08-26.

### BGTaskScheduler maintenance (Conditional, verified), Continued ingestion task (Conditional, verified), Continued query task (Conditional, verified)
- **Idiot:** chores that run when you're not looking.
- **Dot-connector:** continued tasks carry user-started work through backgrounding; maintenance waits for power and hours.
- **Expert:** five identifiers registered in `OpenIntelligenceApp` on iOS; index maintenance 4 h and external power; Spotlight 2 h; refresh 30 min.

### BNNSGraphService (Core, verified) and vDSP (Core, verified) and Unified memory (Core, verified)
- **Idiot:** the fast-maths library on the CPU, and the reason the GPU can read the same memory.
- **Dot-connector:** normalisation, matrix cosine, softmax, RRF arithmetic and pairwise similarity on Accelerate; unified memory enables near-zero-copy handoffs and means everything competes for one budget.
- **Expert:** `BNNSGraphService`; `vDSP_dotpr`, `vDSP_mmul`; `MTLResourceOptions.storageModeShared`.

### Core ML compute units (Core, verified) and Neural Engine (Core as a request, not a placement)
- **Idiot:** the list of chips the model is allowed to use; Apple picks.
- **Dot-connector:** `.cpuAndNeuralEngine` or `.all` from the profile; five lines in the app set them; no line places work on the Neural Engine; no API measures it.
- **Expert:** `MLModelConfiguration.computeUnits` in the embedding provider, reranker, YOLO, region detector, document classifier and the dormant QA model.

### Debounced workspace change (Core, verified)
- **Idiot:** wait two seconds so a burst of changes becomes one sync.
- **Dot-connector:** ingestion writes many artefacts; each one should not launch a full merge.
- **Expert:** `WorkspaceSyncService`.

### Device capability tier (Core, verified), DeviceCapabilityService (Core, verified), Hardware execution envelope (Core, verified), TOPS lookup (Support, verified)
- **Idiot:** what phone is this, and what's it allowed to do.
- **Dot-connector:** baseline, enhanced, advanced, ultra-advanced, unsupported; the envelope is the concrete constraints every heavy stage reads; TOPS is a table, not a measurement.
- **Expert:** detection at first access; consumers listed in the ladder.

### GPUComputeService (Conditional, verified) and Metal Performance Shaders (Conditional, vocabulary)
- **Idiot:** the graphics-chip maths service.
- **Dot-connector:** batch cosine, normalise and MMR kernels with CPU fallback; buffer pool; residency set.
- **Expert:** custom Metal kernels, not MPS calls per se.

### iCloud-shared sync mode (Conditional, verified), Local-only sync mode (Core, verified), WorkspaceSyncService (Conditional, verified), Sync bootstrap conflict (Conditional, verified), Sync merge plan (Conditional, verified), Sync write-in-progress guard (Core, verified), Shared vector-store materialization guard (Core, verified), Vector sync signature cache (Support, verified)
- **Idiot:** the same library on every device, without anything getting eaten.
- **Dot-connector:** per-library choice; a conflict when both sides have real libraries is surfaced, not auto-resolved; a deterministic merge plan preserves identity and deletions; sync writes can't trigger another sync; an undownloaded shared file aborts rather than overwrites; a matching signature skips deserialising every vector.
- **Expert:** `KnowledgeContainer.syncMode`; `WorkspaceSyncService`; the 20 s wait in ingestion is the same guard's cousin.

### Ingestion Live Activity (Conditional, verified) and Spotlight indexing (Conditional, verified)
- **Idiot:** progress on the lock screen, and your documents in system search.
- **Dot-connector:** durable progress without reopening; OS-level discovery without a remote service.
- **Expert:** `IngestionLiveActivityService` and the widget target; `SpotlightIndexService`; both iOS.

### LoggingConfiguration (Support, verified)
- **Idiot:** what gets logged and what gets hidden.
- **Dot-connector:** useful diagnostics without leaking document content or flooding storage.
- **Expert:** levels, categories, file buffering, redaction, shareable trace inclusion.

### Maximum-mode quota (Conditional, verified), QuotaPolicy (Core, verified), StoreKit entitlement (Core, verified)
- **Idiot:** what your plan lets you do.
- **Dot-connector:** libraries, documents and Maximum runs per day by tier, enforced in one place so UI and engine agree.
- **Expert:** `QuotaPolicy.documentLimit()`, `freeMaximumModeDailyLimit`; `EntitlementStore`, `MonetizationPolicy`, `MaximumModeQuotaStore`. Hard-boundary files.

### Memory pressure (Core, verified) and Thermal state (Core, verified) and Query timeout (Core, verified) and Step cooldown (Conditional, verified)
- **Idiot:** too hot, too full, too long, take a breath.
- **Dot-connector:** nominal, warning, critical memory; nominal, fair, serious, critical thermal; a hard latency boundary; a pause between heavy steps.
- **Expert:** `AdaptivePipelineOptimizer`; cooldown 100 ms on baseline down to 0 on ultra-advanced; GPU cache cleared on memory warnings. The bank anchors a query timeout to the optimiser; no `queryTimeout` identifier matched a grep, so treat the exact allowance as unverified; the 180 s recursive-research budget in module 11 is the verified wall clock.

### SettingsStore (Core, verified)
- **Idiot:** your settings, snapshotted.
- **Dot-connector:** a query reads one coherent state at start rather than live UI values mid-run.
- **Expert:** read by `QueryRuntimeCoordinator`; also where the Core AI default on the 27 systems is decided.
# Module 16. Dormant, future, superseded, and commonly misnamed mechanisms

Twenty-five concepts, plus the ones this pass added. The blueprint shelf: things in the source that are not in the machine that runs today, and old names that mislead if taught as current.

## The ladder

**Like you're five.** Some drawings in the workshop are for machines that were never built, or were taken apart. If you learn them as if they were running, you'll describe a machine that doesn't exist.

**Like an idiot.** A codebase this size has scaffolds, reserved names, removed backends and withdrawn claims. This module lists them so you never say one of them in an interview as if it were live.

**Like less of an idiot.** Dormant means the code exists but isn't on any shipping path. Future means a reserved name. Historical means superseded or withdrawn, and misleading if taught as current. The dormant list as verified this week: the Apple Foundation Models embedding provider, the neural extractive QA span model, the dynamic Foundation Model profile registry, embedding-based chunk boundary detection, production Private Cloud Compute (compiled out of shipped builds), and one the word bank missed: the `SpeechAnalyzer` transcription branch. The historical list includes the removed local generative backends (GGUF, MLX, bundled Core ML), the 3B-versus-20B selector, the 32K cloud window, the 18-of-20 zero-hallucination figure, the unmeasured speed multipliers, "zero latency," "model judges," "PCC simulation," "default HNSW," and the "single 29-step pipeline" and "single recursive thought loop" shorthands.

**Average Joe.** Why keep dead code at all? Some of it is a real future (the QA span model has a protocol waiting for a trained model). Some is compatibility (old preference values must still resolve). Some is just not yet removed. The important skill is telling them apart, and the important habit is that a withdrawn claim is corrected in place with a dated note rather than deleted, so the record shows what was claimed and when it was withdrawn.

**Dot-connector.** Two shorthands in particular collapse real structure. "Single 29-step pipeline" hides that execution branches by file type, intent, mode, evidence, device state and route; teach a shared spine with conditional sub-pipelines. "Single recursive thought loop" hides that planning, iterative retrieval, recursive multi-session RAG, critique-and-refine and deterministic verification are five different mechanisms; teach them separately, then reconnect them in sequence, which is what modules 07, 08, 11 and 12 do.

**Expert.** Verified this pass: `FoundationModelDynamicProfileRegistry` has no active call sites; `SemanticChunker`'s embedding-based boundary method returns no boundaries because the chunker is never handed an `EmbeddingService`; `ExtractiveQAService`'s span model returns nil; `AppleFMEmbeddingProvider` declares 1,024 dimensions and is a placeholder; `SpeechAnalyzerService` is guarded by `canImport(SpeechAnalyzer)`, a module that does not exist, and calls an API shape the SDK does not declare; `Docs/SHIPPED_CAPABILITIES.json` records PCC as absent from shipped builds; `AutoTuneService` operates outside the live answer path and does not train models. Historical items are recorded in `CHANGELOG.md`, `RELEASE_NOTES.md`, `HOW_IT_WORKS.md` and `PROGRESSION.md` with dated withdrawals.

**Expert's expert.** Additions to the historical list from the trace: the `.cpuAndGPU` Maximum profile that excluded the Neural Engine (fixed 2026-08-26); the `NSImage.lockFocus` macOS render path that produced 4× oversize images (replaced by a bitmap context); the 0.98 Maximum verification bar (now 0.80); the 0.55 `tauNormal` (now 0.40); the transcript-carrying reasoning chain that overflowed at 4,521 tokens (replaced by the FactBank); the reorder stride of half the chunks-per-session (now equal); the hardcoded 0.70 audit similarity. And a correction to the bank itself: "fixed 384-dimensional architecture" is listed as a historical oversimplification, which is right, but in practice every shipping library is 384 unless someone chose an NL provider, so say "384 by default, resolved per library."

## Every concept

### 18-of-20 zero-hallucination result (Historical, documented)
- **Idiot:** a score that got thrown out.
- **Dot-connector:** the run was invalidly fast; generation likely never executed as assumed.
- **Expert:** withdrawn in `HOW_IT_WORKS.md` and `PROGRESSION.md`; never cite.

### 32K PCC window (Historical, documented)
- **Idiot:** a bigger desk that isn't real.
- **Dot-connector:** a compatibility fallback value; Apple's per-session limit is 4,096 on PCC too.
- **Expert:** `HARD_LIMITS.md`; `LLMModel.contextLength` returns 4,096 for every route.

### 3B versus 20B selector (Historical, verified) and AFM 3 Core Advanced label (Historical, verified)
- **Idiot:** a menu that pretended to pick a model size.
- **Dot-connector:** the framework exposes availability and execution, not parameter tiers; aliases resolve to on-device.
- **Expert:** `FoundationModelRoutePolicy`; `LLMModelType`; changelog.

### Approximate confidence probability (Historical, documented)
- **Idiot:** the 80% isn't an 80% chance.
- **Dot-connector:** a policy-calibrated trust signal, never validated against outcomes.
- **Expert:** `ConfidenceCalibrationService`; `EVALS.md`.

### Automatic online self-training (Historical, verified) and AutoTuneService (Support, verified)
- **Idiot:** the app does not learn from your documents by retraining.
- **Dot-connector:** it adjusts policy and thresholds from evaluation data under constraints; the embedding and reranker models are never trained on user content.
- **Expert:** `AutoTuneService` outside the live path; `EmbeddingService` never fine-tunes.

### Bundled Core ML generative backend (Historical, verified), Local GGUF backend (Historical, verified), Local MLX generative backend (Historical, verified)
- **Idiot:** three writers that were fired.
- **Dot-connector:** the app consolidated on Apple's system model plus deterministic analysis; multiple runtimes fragmented routing.
- **Expert:** absent from `RAGService` model resolution.

### Default HNSW architecture (Historical, verified)
- **Idiot:** the app does not use the shortcut index.
- **Dot-connector:** exact scan over mmap is the default; HNSW belongs to the optional Vectura path.
- **Expert:** `VectorStoreRouter`.

### Dynamic Foundation Model profiles (Dormant, verified)
- **Idiot:** a registry nobody calls.
- **Dot-connector:** anticipated a more observable model-tier API that never came.
- **Expert:** `FoundationModelDynamicProfileRegistry.swift`, no active call sites.

### Embedding-based chunk boundary detection (Dormant, verified)
- **Idiot:** a cleverer cutter that's switched off.
- **Dot-connector:** would split where adjacent sentence embeddings diverge; the chunker is never given an embedding service, so it returns no boundaries.
- **Expert:** method in `SemanticChunker`; `embeddingService` never assigned.

### Fixed 384-dimensional architecture (Historical, documented)
- **Idiot:** "always 384" is an oversimplification.
- **Dot-connector:** 384 by default (MiniLM), 512 for NL providers, 1,024 declared by the dormant scaffold; resolved per library via the fingerprint.
- **Expert:** `EmbeddingProvider`, `EmbeddingFingerprint`.

### Late chunking (Historical, documented)
- **Idiot:** a research trick the app doesn't do.
- **Dot-connector:** embedding a long document jointly and pooling per span; not what `SemanticChunker` does.
- **Expert:** discussed in `EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md`.

### Live Neural Engine utilization (Future, verified absent)
- **Idiot:** a gauge that can't exist yet.
- **Dot-connector:** no public API; the HUD pulse is synthetic.
- **Expert:** `HardwareTelemetryState`, `DeviceCapabilityService`.

### Model judges (Historical, verified absent)
- **Idiot:** no second AI grades the first one.
- **Dot-connector:** deterministic gates and benchmark ground truth do different jobs; no model-as-judge service exists.
- **Expert:** `VerificationGateService`; changelog.

### Neural extractive QA model (Dormant, verified)
- **Idiot:** the reader on the shelf.
- **Dot-connector:** protocol and stub exist; heuristic extraction runs instead.
- **Expert:** `ExtractiveQAService` returns nil.

### PCC simulation (Historical, documented) and Production PCC (Dormant, verified)
- **Idiot:** older phones don't pretend to use the cloud, and shipped builds don't have the cloud.
- **Dot-connector:** no simulation stage exists; the real route compiles under Swift 6.4 and iOS 27 but shipped binaries were built without it.
- **Expert:** `SHIPPED_CAPABILITIES.json`; `isPCCAvailable` guards; iOS 26 users always get on-device.

### RAPTOR L2/L3 hierarchy (Future, verified)
- **Idiot:** two summary levels that are only names.
- **Dot-connector:** section- and corpus-level summaries above the per-document L1; reserved in the enum.
- **Expert:** `ChunkAbstractionLevel`.

### Single 29-step pipeline (Historical, documented) and Single recursive thought loop (Historical, documented)
- **Idiot:** two old shorthands that flatten the real shape.
- **Dot-connector:** execution branches by type, intent, mode, evidence, device and route; the "loop" is five mechanisms.
- **Expert:** `HOW_IT_WORKS.md`, `RETRIEVAL_PIPELINE.md`; modules 07, 08, 11, 12 here.

### Unmeasured speed multipliers (Historical, documented) and Zero latency (Historical, documented)
- **Idiot:** "1,000× faster" and "instant" were removed.
- **Dot-connector:** mechanisms are real; the factors were never benchmarked; device measurements show nonzero time to first token.
- **Expert:** withdrawn in `CHANGELOG.md` and `RELEASE_NOTES.md`; describe mechanisms or cite the ledger.

### Added by this pass: SpeechAnalyzer transcription branch (Dormant, verified)
- **Idiot:** the newer speech reader that never compiles.
- **Dot-connector:** guarded by a module that does not exist; calls an API shape the SDK doesn't declare; `SFSpeechRecognizer` runs instead; nothing is broken for the user.
- **Expert:** `SpeechAnalyzerService.swift:17, 94, 141, 160`; Future Backlog row filed 2026-09-02.
