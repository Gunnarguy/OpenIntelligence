# OpenIntelligence Current State and Gaps

**Updated**: April 25, 2026
**Scope**: Repo-grounded assessment of the current engine, app-only surfaces, evaluation artifacts, and claim boundaries.

This document describes what exists in the repo today. It is written for diligence, internal alignment, and honest buyer conversations.

Companion docs:

- [Implementation Analysis](./IMPLEMENTATION_ANALYSIS_2026_04_24.md)
- [Storage and Pipeline Trace](./STORAGE_AND_PIPELINE_TRACE.md)
- [Buyer Readiness and Evaluation](./BUYER_READINESS_AND_EVALUATION.md)
- [EngineSale README](../EngineSale/README.md)

## Current Status

OpenIntelligence should currently be described as a local-first Apple-native document intelligence prototype and codebase asset.

The repo contains real ingestion, OCR, chunking, embeddings, local storage, hybrid retrieval, answer generation, verification logic, and benchmark tooling. It does not yet contain a cleanly separated, production-ready enterprise SDK.

Use this framing:

> OpenIntelligence Engine is a substantial Swift/iOS prototype for private document QA on Apple devices. It ingests documents locally, builds full-text and vector indexes, retrieves supporting evidence, generates answers through Apple-native model paths where available, and includes source review, verification logic, and early benchmark tooling.

Do not use this repo to claim:

- a finished enterprise SDK
- guaranteed answer correctness
- healthcare, legal, safety, or IFU readiness
- HIPAA, compliance, or security certification
- full GraphRAG
- Apple Foundation Models embeddings
- a public 65K Foundation Models context path

## What Exists Today

| Area              | What exists now                                                                                  | Current status                                                         |
| ----------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| App product       | Shipping Apple-platform app under `OpenIntelligence/`                                            | Real product surface, but not the same thing as an engine handoff      |
| Engine core       | More than 100 service files covering ingestion, storage, retrieval, generation, and verification | Real codebase asset, but still concentrated in app-owned orchestration |
| SDK facade        | `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`                                              | Real narrow facade, evaluation-stage boundary                          |
| Evaluation packet | `output/OpenIntelligence-SDK-Package/` with staged docs and XCFramework artifact                 | Useful evaluation collateral, not proof of finished SDK packaging      |
| Benchmark tooling | Debug harness, Python runner, dashboard, fixtures, and `BenchmarkRuns/` outputs                  | Useful for regression and buyer pilots, early rather than mature       |

## Reusable Engine Assets

| Subsystem               | Current reality                                                                                                                    | Reuse outlook | Main caveat                                                               |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------- |
| Ingestion and OCR       | `DocumentProcessor`, `OCRConfiguration`, `StructuredDocumentParser`, `LayoutAwareExtractor` handle PDF/text/OCR-heavy import paths | Strong        | Still wired into app services, logging, and runtime paths                 |
| Chunking                | `SemanticChunker` produces structure-aware chunks with metadata, section paths, and entity hints                                   | Strong        | Table and procedure fidelity remain uneven                                |
| Embeddings              | `EmbeddingService` plus Core ML and Natural Language providers                                                                     | Strong        | `AppleFMEmbeddingProvider` is a scaffold, not a live Apple embedding path |
| Full-text storage       | `SQLiteFullTextService` stores whole-document, chunk, and page indexes with `container_id` isolation                               | Strong        | Currently singleton- and app-path-oriented                                |
| Vector storage          | `VectorStoreRouter` plus `BNNSVectorDatabase` provide per-container vector search                                                  | Strong        | App support paths and memory warning handling are app-shaped              |
| Retrieval and reranking | Hybrid vector plus BM25 retrieval, RRF, MMR, parent expansion, graph-style cross-reference following                               | Strong        | Not a full GraphRAG implementation                                        |
| Context packing         | `ContextPackingService` trims and orders evidence for the public Apple token budget                                                | Good          | Tuned around today's 4096-token public Foundation Models path             |
| Generation              | `LLMService` and `RAGService` drive Apple-native generation and extractive fallback                                                | Medium        | Tool calling and orchestration are still tied closely to app-owned flows  |
| Verification            | `VerificationGateService`, `SourceOnlyAnswerService`, calibration, and domain isolation logic exist                                | Good          | Improves behavior, but does not guarantee correctness                     |
| Benchmarking            | `DebugRAGValidationHarness`, `run_rag_benchmarks.py`, `rag_benchmark_studio.py`, dashboards                                        | Good          | Debug-harness-driven, not formal third-party evaluation                   |

## App-Specific or Buyer-Irrelevant Surfaces

These areas matter to the product, but they are not the core engine story:

- SwiftUI screens, onboarding, navigation, and visual chrome under `OpenIntelligence/App`, `OpenIntelligence/Features`, and `OpenIntelligence/UI`
- StoreKit, paywalls, pricing UI, purchase restoration, and quota messaging
- App Store metadata, screenshots, Fastlane, and release automation
- Consumer settings presentation and diagnostics dashboards
- Sample in-app marketing or diagnostics copy that speaks more loosely than the code-backed engine docs should

Important current example:

- `BillingProduct.swift` still includes `doc_pack_addon`
- `QuotaPolicy.swift` still supports add-on increments
- `PlanUpgradeSheet.swift` still exposes live document-pack purchase UI
- `EntitlementStore.swift` still persists and credits document-pack purchases
- `fastlane/subscriptions.json` still includes App Store Connect setup for `doc_pack_addon`
- `TermsOfServiceView.swift` and `DocumentQuotaBanner.swift` say document packs are no longer sold in-app

That is a literal code-level contradiction inside the app surface, not an engine capability issue.

## Verified Technical Boundaries

### Public Foundation Models Context

The public Apple Foundation Models session budget should still be treated as 4096 tokens. The repo contains execution-context enums and PCC consent plumbing, but those do not justify claiming a larger public session budget.

### Private Cloud Compute

The codebase can allow or disallow Apple-managed cloud routing where Apple exposes that behavior. It does not provide a developer-operated PCC backend, direct server-model access, or a verified larger context path for third-party apps.

### Apple Embeddings

`AppleFMEmbeddingProvider.swift` is an unavailable scaffold. Actual embeddings today come from Core ML and Natural Language providers.

### GraphRAG

The repo has RAPTOR-lite summaries, graph-style cross-reference packing, and an entity index. It does not implement the full GraphRAG stack of entity resolution, community extraction, community summaries, and evaluated graph retrieval.

### Verification and Citations

Verification gates, source-only answer logic, and citations reduce fabrication risk. They do not prove correctness, suitability for regulated decisions, or perfect source support.

## Benchmarkable Today

The repo already supports useful technical evaluation:

- `OpenIntelligence/App/DebugRAGValidationHarness.swift` runs ingestion and query audit flows through the real app engine in Debug
- `scripts/run_rag_benchmarks.py` stages manifests, launches the harness, and collects artifacts
- `scripts/rag_benchmark_studio.py` gives a local UI for ad hoc benchmark runs
- `Benchmarks/` contains sample manifests and research-fixture helpers
- `BenchmarkRuns/` stores summaries, dashboards, and raw case artifacts

What this is good for today:

- regression tracking
- buyer pilot runs on sample corpora
- exact-value/manual QA investigation
- source-support troubleshooting

What it is not yet:

- a formal external benchmark program
- a medical or legal accuracy study
- a security or compliance validation artifact

## Biggest Gaps

1. **SDK packaging is still evaluation-stage.** The repo contains a public facade and a staged evaluation packet, but the clean, reproducible, toolchain-agnostic SDK story is not finished.
2. **App and engine are still coupled.** The current facade still drives `ContainerService`, `RAGService`, shared runtime paths, and app-oriented singletons.
3. **Table and procedure fidelity remain a real weakness.** Hard technical/manual questions can still fail due to flattening, retrieval misses, or context loss.
4. **Claim maturity is limited.** There is no formal HIPAA, compliance, security, or regulated-workflow review.
5. **Benchmark maturity is limited.** The harness is useful and real, but early.
6. **Consumer monetization is not settled.** Active paywall, entitlement, quota, and App Store metadata still support document packs, while some in-app policy copy says they are no longer sold.

## Best Current Framing

The strongest honest story is not "finished enterprise product." It is "substantial Apple-native engine prototype and codebase head start."

That means:

- good fit for diligence, acquisition, licensing, or design-partner evaluation
- good fit for teams exploring private document QA on Apple devices
- not good fit for claims of production-ready SDK maturity or regulated decision support
