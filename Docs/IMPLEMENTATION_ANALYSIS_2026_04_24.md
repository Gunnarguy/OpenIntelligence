# OpenIntelligence Implementation Analysis

**Updated**: April 24, 2026
**Scope**: Internal engineering and buyer-diligence analysis of the current repository.

This is the deeper implementation layer behind [CURRENT_STATE_AND_GAPS.md](./CURRENT_STATE_AND_GAPS.md). It is intentionally more specific than the public architecture summary.

## Executive Verdict

OpenIntelligence is a real engine, not just an app shell. The repo contains:

- A complete Apple-platform application.
- A public engine facade in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`.
- A generated evaluation package under `output/OpenIntelligence-SDK-Package/`.
- 107 Swift service files under `OpenIntelligence/Services`.
- A dense retrieval, storage, verification, and generation stack centered on `RAGService.swift`.

The product is strongest when described as:

> A local-first Apple-native document intelligence engine that ingests private files, builds local full-text and vector indexes, retrieves evidence, generates through Apple's public Foundation Models path when available, and verifies answers against source material.

The main engineering risk is not the idea. It is concentration: too much critical policy is still in `RAGService.swift`, `DocumentProcessor.swift`, and `AgenticOrchestrator.swift`.

## Service Inventory

| Service Area | Count | Role | Commercial Meaning |
| --- | ---: | --- | --- |
| Document | 24 | File parsing, OCR, chunking, classification, summaries, entities, speech/audio extraction | Turns messy source material into searchable evidence. |
| Infrastructure | 21 | settings, quotas, device capability, telemetry, background work, projections, Spotlight | Makes the engine shippable inside an Apple app. |
| RAG | 17 | retrieval, packing, extraction, verification, confidence, orchestration | Core defensible engine logic. |
| Query | 10 | query routing, rewriting, HyDE, compression, suggestions | Adapts user intent before retrieval/generation. |
| Billing | 8 | StoreKit, tiers, entitlements, maximum-mode quotas | Consumer monetization, mostly outside SDK boundary. |
| Embedding | 7 | provider selection, Core ML/NL embedding paths, token counting | Builds local semantic search substrate. |
| Agentic | 7 | multi-step reasoning, tool calls, memory, App Intents/writing tools | Useful for high-value demos, but partly app-shaped. |
| LLM | 6 | FoundationModels integration, model resolution, streaming, prompt evaluation | Generation/runtime layer. |
| VectorStore | 4 | vector DB protocol, router, BNNS/mmap backend, Vectura backend | Local semantic retrieval performance layer. |
| Storage | 3 | SQLite FTS5, full-text storage, documentation cache | Exact lookup and durable retrieval layer. |

## What Is Implemented

### Ingestion

Implemented:

- PDFKit-first text extraction with fallback to Vision OCR.
- Garbled text-layer detection using sample OCR/PDFKit comparison.
- Metal-backed Core Image preprocessing for OCR pages.
- Page-level text preservation.
- Structure-aware chunking with metadata.
- Contextual prefixes before embedding.
- Token validation against provider tokenizers.
- Core ML/Natural Language embedding providers.
- Per-container vector store selection.
- SQLite FTS5 document, chunk, and page indexes.

Missing or incomplete:

- A formal ingestion benchmark suite by file type and quality level.
- A buyer-facing corpus readiness report after ingestion.
- A stable table-first representation for tabular documents. The code has table-aware OCR heuristics, but not a TableRAG-style SQL/table reasoning layer.
- Public Apple FoundationModels embeddings. `AppleFMEmbeddingProvider.swift` is a scaffold, not a shipped provider.

### Retrieval

Implemented:

- Hybrid vector + BM25 retrieval.
- Reciprocal rank fusion.
- MMR diversification.
- Query rewriting and expansion.
- HyDE for appropriate synthesis-style queries.
- Iterative/corrective retrieval behavior.
- Parent document retrieval.
- RAPTOR-lite document-summary routing.
- Graph-style context packing.
- Exact-value lookup protections.

Missing or incomplete:

- Full GraphRAG community extraction, clustering, and community summaries.
- A public eval report showing retrieval recall by query category.
- A deterministic alias/entity graph with source-span provenance.
- Table-specific retrieval and reasoning for heterogeneous documents.

### Generation and Verification

Implemented:

- Apple FoundationModels `LanguageModelSession` generation.
- Tool calling when useful.
- Tool disabling when context is already assembled to reclaim tokens.
- Structured output through `@Generable`.
- Verification gates A-I.
- Source-only claim verification and trust payloads.
- Calibrated confidence and response metadata.
- Extractive override paths for exact-value/specification queries.

Missing or incomplete:

- A maintained scenario set for each answer lane.
- Buyer-readable evaluation artifacts.
- Clear separation between verification gates and source-only verification responsibilities.
- A formal policy for when Maximum mode should stop, abstain, or keep searching.

### SDK/Productization

Implemented:

- Public wrapper in `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`.
- Availability states for simulator/device/model readiness.
- Public ingest/query request and result types.
- Generated evaluation package with an `OpenIntelligenceEngine.xcframework`.
- Sample host app and buyer-packet artifacts under `output/OpenIntelligence-SDK-Package/`.

Still needed:

- A reproducible framework target and shared scheme from the current Xcode project.
- Target-membership cleanup so app/UI/billing code cannot leak into the SDK.
- Caller-controlled storage root by default.
- Fewer singleton assumptions for multi-instance SDK use.
- Stable semantic versioning and package validation.

## The 29-Step Pipeline, Interpreted Correctly

The 29-step pipeline is a logical/audit model. It is not a guarantee that every query runs every step.

For example:

- A direct exact-value query should lean toward extraction and exact search.
- A broad summary query should route through summaries and source diversity.
- A multi-hop query should use iterative retrieval, graph packing, and more verification.
- A well-supported direct lookup should not waste tokens on tool schemas or broad agentic exploration.

This adaptive behavior is correct. The docs should not make it sound like every answer always pays the full pipeline cost.

## Why It Works

The engine works because it avoids relying on the small language model for everything.

- OCR/parsing is done by Apple document frameworks and local heuristics.
- Full-text lookup is handled by SQLite FTS5/BM25.
- Semantic recall is handled by local embeddings and vector search.
- Ranking/diversity are algorithmic.
- The LLM is reserved for synthesis, tool decisions, formatting, and structured output.
- Verification runs after generation to catch unsupported or conflicting claims.

This is the right architecture for a 4096-token public FoundationModels session.

## Why It Still Misses Data Sometimes

Likely causes:

1. The relevant page/chunk exists in SQLite but not in the final packed context.
2. OCR/table structure flattened values that need row/column relationships.
3. Query expansion or HyDE drifts away from exact source language.
4. Retrieval finds a nearby cross-reference instead of the table/value source.
5. Context compression removes the value or surrounding unit.
6. Verification correctly rejects weak answers, but the fallback retrieval does not broaden in the right direction.
7. Multi-document/library routing excludes the relevant container.

The Sportage fuel-tank trace files in the working tree are exactly the kind of evaluation artifact that should become a maintained exact-value regression.

## Buyer-Ready Claims

Safe:

- Local-first private document QA on Apple devices.
- Local full-text and vector indexes.
- Hybrid retrieval instead of vector-only search.
- Cited answers with source inspection.
- Conservative verification and abstention behavior.
- Evaluation-stage SDK package exists.

Needs evidence before saying:

- Healthcare production readiness.
- HIPAA compliance.
- Clinical decision support.
- Diagnostic assistance.
- Guaranteed correctness.
- Full GraphRAG.
- Direct PCC server-model access.
- 65K FoundationModels context.

## Highest-Value Next Engineering Work

1. Build a small eval set from real failure traces, including the Sportage exact-value cases.
2. Add table/value-specific retrieval tests.
3. Split exact-value retrieval policy out of `RAGService.swift` into a focused service.
4. Add a buyer-readable evaluation report template.
5. Make the SDK build path reproducible from source, not artifact-only.
6. Create a "source inventory after ingestion" report so users and buyers can see what was actually indexed.
