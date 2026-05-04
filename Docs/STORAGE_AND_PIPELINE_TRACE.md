# Storage and Pipeline Trace

**Updated**: April 25, 2026
**Scope**: Internal trace of how data moves through the current prototype engine from import to answer.

## Current Status

This document describes the current engine flow as implemented in the repo.

It does not prove:

- answer accuracy for every document type
- stable SDK productization
- regulated-workflow readiness

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
| Cleanup              | OCR filters and normalizers                                       | normalized text                                           | Reusable                                                                           |
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

That is a practical and reusable design, but still a prototype implementation rather than a hardened enterprise isolation story.

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

This is useful engine configuration. It is also part of the current app coupling because the SDK facade still routes through container concepts and app persistence.

## Query Trace

| Stage                   | Main code                                                       | Current note                                                |
| ----------------------- | --------------------------------------------------------------- | ----------------------------------------------------------- |
| Availability/config     | `OpenIntelligenceEngine.swift`, `DeviceCapabilityService.swift` | Small public entry point exists                             |
| Intent/routing          | query analysis and policy services                              | Real logic, still app-owned overall orchestration           |
| Query rewrite/expansion | rewriter, HyDE, vocabulary services                             | Present and useful, but should not be oversold              |
| Retrieval               | hybrid vector plus BM25 services                                | Strong core engine asset                                    |
| Expansion/diversity     | parent retrieval, MMR, source diversity                         | Real and valuable                                           |
| Context packing         | `ContextPackingService.swift`                                   | Tuned around today's public Apple token budget              |
| Generation              | `LLMService.swift`                                              | Apple-native path where available, with app-shaped tool set |
| Extraction fallback     | extractive QA services                                          | Important exact-value protection                            |
| Verification            | gate and source-only services                                   | Real safeguards, not correctness proof                      |
| Presentation            | structured response models plus SwiftUI                         | App layer                                                   |

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
