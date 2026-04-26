# OpenIntelligence Implementation Analysis

**Updated**: April 25, 2026
**Scope**: Internal engineering and buyer-diligence view of the current repository.

This document describes the repo as it exists today, not as a finished product roadmap.

## Executive Verdict

OpenIntelligence is a real engine inside a real app codebase.

The repo includes:

- a working Apple-platform application
- a narrow public engine facade in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- ingestion, OCR, chunking, storage, retrieval, generation, and verification services under `OpenIntelligence/Services/`
- a staged evaluation packet under `output/OpenIntelligence-SDK-Package/`
- a debug benchmark harness and Python runner

What it is today:

- substantial Swift/iOS document-intelligence prototype
- codebase head start for private document QA on Apple devices
- evaluation-stage engine boundary

What it is not today:

- finished enterprise SDK
- cleanly decoupled reusable framework
- audited accuracy or compliance product

## Current Boundary Reality

| Category       | What is in it today                                                                                                   | Commercial meaning                                                         |
| -------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Core engine    | ingestion, OCR, chunking, embeddings, SQLite/FTS, vector search, retrieval, context packing, generation, verification | Real transferable technical value                                          |
| App-specific   | SwiftUI, onboarding, paywalls, StoreKit, settings presentation, diagnostics, App Store release surfaces               | Useful for demoing and proving a live product, not the engine asset itself |
| Shared/support | container config, runtime paths, device capability logic, logging, model/config types, benchmark entitlement helpers  | Important glue, but still partially app-shaped                             |

## Implemented Engine Subsystems

### SDK facade

- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` exposes a small ingest/query surface and already supports an optional `storageURL` override.
- It matters because it shows the intended commercial API boundary.
- Caveat: it still instantiates `ContainerService`, `RAGService`, and app-oriented runtime paths under the hood.

### Ingestion and OCR

- `DocumentProcessor.swift` and related processing files perform file parsing, OCR fallback, page preservation, and chunk production.
- `OCRConfiguration.swift` centralizes Vision OCR behavior and the repo still enforces the documented OCR render constraints.
- Caveat: the code is strong, but table-heavy and procedural documents remain a weakness.

### Chunking

- `SemanticChunker.swift` performs structure-aware chunking with entity extraction, section paths, and metadata enrichment.
- The implementation respects the practical embedding-token constraints documented elsewhere.
- Caveat: chunking quality is good, but not a guarantee of table/spec fidelity.

### Embeddings

- `EmbeddingService.swift` supports Core ML and Natural Language providers.
- `CoreMLSentenceEmbeddingProvider.swift` is the practical current path.
- `AppleFMEmbeddingProvider.swift` exists only as a scaffold and reports unavailable.

### Storage

- `SQLiteFullTextService.swift` provides shared-table FTS5 storage with `container_id` isolation and separate full-document lookup tables.
- `VectorStoreRouter.swift` plus `BNNSVectorDatabase.swift` provide per-container vector persistence and search.
- Caveat: storage currently assumes app-owned runtime paths and shared singleton patterns.

### Retrieval, reranking, and packing

- `HybridSearchService.swift` combines vector and BM25 retrieval using RRF and further boosts/filters results.
- `ParentDocumentService.swift`, `GraphIndexService.swift`, and `ContextPackingService.swift` expand and trim context.
- The engine has graph-style retrieval support, but not full GraphRAG.

### Generation

- `LLMService.swift` is the generation abstraction.
- The main buyer-facing story is Apple Foundation Models generation where available, plus extractive and fallback behavior.
- Caveat: tool calling is real, but the current tool set is still strongly app-shaped.

### Verification

- `VerificationGateService.swift`, `SourceOnlyAnswerService.swift`, and related safety services implement real post-generation checks.
- This is useful engineering and a real differentiator for evaluation conversations.
- Caveat: verification gates improve behavior but do not guarantee correctness.

### Benchmarking

- `OpenIntelligence/App/DebugRAGValidationHarness.swift` exercises the engine through the Debug app runtime.
- `scripts/run_rag_benchmarks.py` and `scripts/rag_benchmark_studio.py` provide runnable harness control and reporting.
- Caveat: this is early benchmark infrastructure, not a mature external evaluation program.

## App-Specific Surfaces That Should Not Be Sold As Engine Value

These areas prove product effort but should not be confused with the engine asset:

- SwiftUI chat, document, onboarding, billing, and settings screens
- StoreKit products and consumer paywall flows
- App Store metadata, screenshots, and Fastlane operations
- telemetry and visual dashboards aimed at app/debug workflows

Current app-specific pricing note:

- `BillingProduct.swift` still includes `doc_pack_addon`
- `QuotaPolicy.swift` still supports add-on increments
- `TermsOfServiceView.swift` says document packs are no longer sold in-app

That inconsistency should be treated as app-surface churn, not engine scope.

## Packaging Reality

The repo contains a staged evaluation packet and public facade. That is useful. It is not the same thing as proving a final SDK productization path.

Current truthful packaging statement:

- there is a staged evaluation packet and evaluation XCFramework artifact in the repo
- there is a small public facade
- there is not yet a fully proven, cleanly decoupled, toolchain-agnostic enterprise SDK story

## Concentration Risks

The main engineering risk is not that the engine is fake. It is that too much important behavior is still concentrated in a few app-owned orchestration paths.

Most important concentration points:

- `RAGService.swift`
- `DocumentProcessor.swift`
- app-owned container/runtime services and shared singletons

## Claims That Survive Diligence

Safe:

- local-first Apple-native document intelligence prototype
- local full-text and vector indexing
- hybrid retrieval with source review
- verification-oriented answer pipeline
- real benchmark harness and regression tooling
- meaningful codebase head start for Apple-device document QA

Not safe:

- finished SDK readiness
- HIPAA or compliance readiness
- reliable medical/legal/safety/IFU use
- Apple embedding support through Foundation Models
- full GraphRAG
- guaranteed correctness

## Practical Conclusion

This repo is substantial enough to support evaluation, diligence, acquisition, licensing, or design-partner discussions.

It should be sold as a strong engine prototype and codebase asset, not as a finished enterprise product.
