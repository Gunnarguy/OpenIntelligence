# Storage and Pipeline Trace

**Updated**: April 24, 2026
**Scope**: Internal trace of how data moves from import to answer.

## End-to-End Flow

```text
File URL
  -> DocumentProcessor
  -> normalized text + page text + structure metadata
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

## Ingestion Trace

| Stage | Main Code | Output |
| --- | --- | --- |
| File classification | `DocumentProcessor.swift` | document type and extraction path |
| Text extraction | PDFKit, Office XML parsing, plain text, CSV, OCR, SpeechAnalyzer | raw text |
| OCR fallback | `VNRecognizeTextRequest`, `OCRConfiguration.swift`, `VisionOCRThrottle.swift` | observations, text, confidence, bounding boxes |
| Cleanup | `OCRConfiguration` filters and normalizers | normalized text |
| Page preservation | `DocumentProcessor.pageBreakSentinel` and page store calls | page-level rows in SQLite |
| Chunking | `SemanticChunker.swift`, structure metadata | `DocumentChunk` records |
| Enrichment | entities, keywords, section paths, contextual prefix | searchable/retrievable chunk metadata |
| Embedding | `EmbeddingService.swift` and providers | vectors |
| Durable storage | `SQLiteFullTextService.swift`, `VectorStoreRouter.swift` | FTS rows and vector files |

## SQLite Storage

`SQLiteFullTextService.swift` creates one FTS database with shared tables and `container_id` isolation.

| Table | Type | Purpose |
| --- | --- | --- |
| `documents` | FTS5 | whole-document searchable text |
| `document_meta` | regular SQLite | document id, container id, counts, created time |
| `document_content` | regular SQLite | fast direct full-document lookup by `document_id` |
| `chunks` | FTS5 | chunk-level BM25 search with searchable section title/path |
| `document_pages` | FTS5 | page-level search and context isolation |

Important correction: libraries are not separate SQLite databases. They are isolated by `container_id`.

## Vector Storage

`VectorStoreRouter.swift` manages vector databases per knowledge container.

`BNNSVectorDatabase.swift` persists:

- `_meta.json`: chunk metadata without embedded vectors.
- `_vectors.bin`: raw contiguous Float32 vectors, memory-mapped on load.
- `_norms.bin`: precomputed vector norms.

Search behavior:

- Small searches use Accelerate/vDSP.
- Larger searches can use Metal compute.
- The router can search across containers and merge results when requested.

## Container Configuration

`KnowledgeContainer.swift` stores per-library retrieval configuration:

- embedding provider id
- embedding dimension
- vector DB kind
- chunking directive
- retrieval config
- document/chunk stats
- preferred language and auto-tag options

Default/high-accuracy containers use `coreml_sentence_embedding` at 384 dimensions.

## Query Trace

| Stage | Main Code | Notes |
| --- | --- | --- |
| Availability/config | `OpenIntelligenceEngine.swift`, `DeviceCapabilityService.swift` | device/model readiness |
| Intent/routing | `QueryEnhancementService.swift`, `QueryRouterService.swift`, `GroundedAnswerPolicy.swift` | lookup/procedure/compare/summarize/synthesis |
| Query rewrite/expansion | `QueryRewriterService.swift`, `HyDEService.swift`, `ContainerVocabularyService.swift` | guarded for exact lookup paths |
| Retrieval | `HybridSearchService.swift`, `VectorStoreRouter.swift`, `SQLiteFullTextService.swift` | vector + BM25 + RRF |
| Expansion/diversity | `ParentDocumentService.swift`, MMR, source diversity | improves coherence |
| Context packing | `ContextPackingService.swift`, graph packing, lost-in-middle ordering | fits 4096-token budget |
| Generation | `LLMService.swift` | FoundationModels session |
| Extraction fallback | `ExtractiveQAService.swift`, exact-value override logic | protects direct factual questions |
| Verification | `VerificationGateService.swift`, `SourceOnlyAnswerService.swift` | gates A-I and claim support |
| Presentation | `StructuredAnswer.swift`, `RAGStructuredResponse.swift`, chat response views | citations and trust details |

## Where Answers Can Fail

| Failure | Likely Cause | Practical Fix |
| --- | --- | --- |
| Value exists but answer says missing | relevant chunk/page did not make final context | exact-value retrieval regression test |
| Wrong numeric value | table flattened or cross-reference retrieved | table/value-aware retrieval and Gate C tests |
| Over-refusal | verification thresholds too strict | lane-specific eval set |
| Hallucinated synthesis | retrieved context weak or prompt too broad | stricter source-only path and abstention |
| Slow ingestion | OCR-heavy document, high render scale, large XML | file-type benchmarks |
| SDK integration friction | app-owned storage/singletons | caller-provided storage root and target split |

## Evaluation Artifacts To Keep

Keep small human-readable traces for:

- exact lookup questions
- table values
- missing evidence
- multi-document comparison
- broad summary
- procedural/manual questions
- OCR-heavy scans

The current `SportageTraceFuelTankCapacity`, `SportageFuelTankTrace`, and `FULLSPORTAGEMANUAL` files should be treated as seed material for an exact-value/manual QA eval.
