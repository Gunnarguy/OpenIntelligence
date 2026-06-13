> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

# Storage and Pipeline Trace

**Updated**: April 25, 2026
**Scope**: Internal trace of how data moves through the current prototype engine from import to answer.

## Current Status

This document describes the current engine flow as implemented in the repo.

It does not prove:

- answer accuracy for every document type
- stable reusable package delivery
- regulated or safety-critical workflow readiness

Read this trace as a routed system, not as one universal sequence that every query fully executes:

- import-time and query-time are separate phases, and normal query execution consumes indexes built earlier rather than rerunning `DocumentProcessor`
- some branches are early returns, especially extractive summarization and direct high-precision extraction
- agentic mode is chosen up front and runs through its own orchestrator rather than appearing as a late stage inside the standard path
- verification is a trust-control layer that can warn, refine, reduce confidence, or abstain; it does not prove truth
- exact lexical retrieval still matters alongside vector search for names, codes, and literal specs
- container isolation currently comes from `container_id` inside shared SQLite tables, not from one SQLite database per library

## End-to-End Flow

```text
File URL
  -> DocumentProcessor
  -> normalized text + page text + structure metadata + figure semantics
  -> SemanticChunker / structured chunk construction
  -> contextual prefix + token validation
  -> EmbeddingService
  -> SQLite FTS5 + vector store + container metadata
  -> RAGService query orchestration
  -> hybrid retrieval + rerank/diversity/packing
  -> FoundationModels generation or extractive answer
  -> verification gates + structured trust payload
  -> SwiftUI answer/citation surfaces
```

The engine-relevant flow ends at the trust payload and retrieved evidence. SwiftUI presentation is an app surface, not a core engine requirement.

## Ingestion Trace

| Stage                | Main code                                                         | Output                                                    | Current note                                                                       |
| -------------------- | ----------------------------------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| File classification  | `DocumentProcessor.swift`                                         | document type and extraction path                         | Real reusable engine logic                                                         |
| Text extraction      | PDFKit, XML parsing, text/CSV parsing, OCR, speech analysis paths | raw text                                                  | Strong base, file-type coverage should still be tested corpus by corpus            |
| OCR fallback         | `OCRConfiguration.swift`, Vision OCR, throttle helpers            | recognized text and observations                          | Adaptive page-by-page escalation, not a user-controlled fidelity mode              |
| Visual understanding | `ImageUnderstandingService.swift`                                 | figure descriptions, OCR labels, captions, nearby context | Embedded PDF figures and standalone images now persist as searchable figure chunks |
| Cleanup              | OCR filters, normalizers, and text-preservation profiles          | normalized text                                           | Conservative for clean digital text, heavier for OCR/scanned extraction            |
| Page preservation    | page sentinel plus page-store calls                               | page-level rows in SQLite                                 | Important for source review and exact lookup                                       |
| Chunking             | `SemanticChunker.swift`                                           | `DocumentChunk` records                                   | Reusable, but not immune to table/procedure errors                                 |
| Enrichment           | entities, keywords, section paths, contextual prefix              | chunk metadata                                            | Helps retrieval and verification                                                   |
| Embedding            | `EmbeddingService.swift` and providers                            | vectors                                                   | Current production path is Core ML/NL, not Apple FM embeddings                     |
| Durable storage      | `SQLiteFullTextService.swift`, `VectorStoreRouter.swift`          | local indexes                                             | Real engine asset                                                                  |

## SQLite Storage Reality

`SQLiteFullTextService.swift` uses shared tables with `container_id` isolation.

| Table              | Type           | Purpose                                       |
| ------------------ | -------------- | --------------------------------------------- |
| `documents`        | FTS5           | whole-document searchable text                |
| `document_meta`    | regular SQLite | document id, container id, counts, timestamps |
| `document_content` | regular SQLite | fast direct full-document lookup              |
| `chunks`           | FTS5           | chunk-level BM25 and section-aware lookup     |
| `document_pages`   | FTS5           | page-level search and context isolation       |

Important correction:

- libraries are not separate SQLite databases
- container isolation currently comes from `container_id` within shared tables

That is a practical and reusable design, but still a prototype implementation rather than a hardened multi-tenant isolation story.

## Vector Storage Reality

`VectorStoreRouter.swift` manages vector databases per knowledge container.

`BNNSVectorDatabase.swift` persists:

- `_meta.json` for chunk metadata
- `_vectors.bin` for raw contiguous Float32 vectors
- `_norms.bin` for precomputed vector norms

Search behavior today:

- smaller searches use Accelerate/vDSP
- larger searches can use Metal compute
- the router keeps vector stores isolated per container and recreates them when library config changes

This is real engine code and reusable. The main current caveat is runtime coupling through app support paths and app-shaped lifecycle behavior.

## Container Configuration

`KnowledgeContainer.swift` and `ContainerService.swift` currently hold per-library configuration such as:

- embedding provider id
- embedding dimension
- vector DB kind
- chunking directive
- retrieval config
- document and chunk counts

This is useful engine configuration. It is also part of the current app coupling because the public facade still routes through container concepts and app persistence.

## Shared Library Sync Reality

Shared iCloud libraries now use a stable library identity for reconciliation instead of relying on display names alone.

Current behavior:

- per-library storage choice still determines whether a library stays local or participates in the shared iCloud workspace
- explicit moves to iCloud Drive use a direct opt-in path rather than falling back to the broader bootstrap chooser
- Documents owns the main global refresh and review surface for shared-library additions, removals, and pull-in decisions across devices

This is closer to an intent-driven sync review model than the earlier generic "library sets differ" prompt, but it is still an app-level reconciliation layer rather than a general multi-client sync engine.

## Query Trace

Read the query trace below as a routed family of paths. The standard path can early-return into extractive handling, and harder queries can be handed to agentic orchestration before the standard lane starts.

| Stage                    | Main code                                                                           | What it is trying to do                                                      | Failure or risk it is managing                                       | Current note                                                |
| ------------------------ | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------- |
| Availability/config      | `OpenIntelligenceEngine.swift`, `DeviceCapabilityService.swift`                     | select a runnable path for the current device and mode                       | unsupported model path or runtime mismatch                           | Small public entry point exists                             |
| Intent/routing           | query analysis and policy services                                                  | choose the right answer lane before retrieval goes too far                   | wrong lane for the question, including standard vs agentic           | Real logic, still app-owned overall orchestration           |
| Query rewrite/expansion  | rewriter, HyDE, vocabulary services                                                 | bridge wording gaps between user phrasing and document phrasing              | vocabulary mismatch and weak recall                                  | Present and useful, but should not be oversold              |
| Retrieval                | hybrid vector plus BM25 services                                                    | find candidate evidence with both semantic and literal signals               | exact-term misses or semantic misses if only one method is used      | Strong core engine asset                                    |
| Expansion/diversity      | parent retrieval, MMR, source diversity, cross-reference and graph follow-up        | widen or reshape evidence when the first hit set is incomplete or repetitive | duplicate chunks, missing surrounding context, unresolved references | Real and valuable                                           |
| Context packing          | `ContextPackingService.swift`                                                       | decide which evidence survives into the final prompt budget                  | good chunks found but squeezed out by the token ceiling              | Tuned around today's public Apple token budget              |
| Generation               | `LLMService.swift`                                                                  | synthesize a grounded answer when the query should go through generation     | fluent but weakly grounded output if retrieval was weak              | Apple-native path where available, with app-shaped tool set |
| Extractive protection    | extractive QA and summarization services, direct extraction, source-only refinement | keep exact values and summaries closer to source text                        | wrong specs, wrong numbers, and freeform drift                       | Important precision protection, not a "less advanced" path  |
| Verification/calibration | gate, confidence, and source-only services                                          | adjust trust posture after an answer is produced                             | overconfident answer without enough support                          | Real safeguards, not correctness proof                      |
| Presentation/review      | structured response models plus SwiftUI                                             | expose citations, warnings, and trace surfaces for inspection                | polished answer hiding the real evidence situation                   | App layer                                                   |

## Reusable Engine Parts vs App-Coupled Wrappers

Mostly reusable today:

- ingestion and OCR core
- chunking
- SQLite full-text storage
- BNNS/Metal vector search
- hybrid retrieval and reranking
- context packing
- verification logic
- benchmark runner pattern

Still app-coupled today:

- `ContainerService`
- `AppSupportPaths` and runtime-path assumptions
- `RAGService` orchestration as the main integration point
- app-specific tool calling surfaces inside the generation path
- SwiftUI answer and citation presentation

## Where Answers Still Fail

| Failure                              | Likely cause                                                        |
| ------------------------------------ | ------------------------------------------------------------------- |
| Value exists but answer says missing | relevant page or chunk did not survive final packing                |
| Wrong numeric value                  | table flattening, nearby cross-reference retrieval, or context loss |
| Source mismatch                      | retrieved chunk is related but not the exact supporting span        |
| Over-refusal                         | verification thresholds or weak evidence coverage                   |
| Hallucinated synthesis               | weak retrieval plus overly broad generation lane                    |
| Procedural/manual miss               | multi-step structure not preserved well enough                      |

## Benchmark Hooks

Current benchmark and trace hooks live in:

- `OpenIntelligence/App/DebugRAGValidationHarness.swift`
- `scripts/run_rag_benchmarks.py`
- `scripts/rag_benchmark_studio.py`
- `Benchmarks/README.md`

That makes the current pipeline inspectable and regression-testable, but still early.
