# OpenIntelligence AI Guide

- **Scope**: iOS 26 privacy-first RAG app. Documents flow through `DocumentProcessor` → `SemanticChunker` (target 400 · clamp 100–800 · overlap 75) → `EmbeddingService` (NLEmbedding 512-dim with cached norms) → per-container `PersistentVectorDatabase` → `HybridSearchService` (cosine + BM25 via RRF) → streaming `LLMService` with fallbacks.

## Core architecture

- `RAGService` (@MainActor) orchestrates ingestion, querying, agent tool calls, and telemetry; CPU-heavy work (MMR, rerank, context assembly, BM25) lives in the `RAGEngine` actor.
- Services are protocol-first (`DocumentProcessor`, `EmbeddingService`, `VectorDatabase`, `HybridSearchService`, `LLMService`). When swapping implementations, register them via `ContainerService` + `VectorStoreRouter`; SwiftUI views should never know storage details.
- Knowledge containers (`ContainerService`) track vector DB kind, embedding provider, and stats. Use `VectorStoreRouter.db(for:)` for DB access and call `updateStats` after mutations to keep UI/telemetry accurate.

## Retrieval details

- `DocumentProcessor` handles PDFKit + Vision OCR, encodings, and chunk metadata; reuse its `ProcessedChunk.metadata` instead of recomputing pages/keywords.
- Vector search expects 512-dim embeddings. Batch store with `VectorDatabase.storeBatch` so norms/cache stay valid; invalidate hybrid caches when altering stored chunks.
- `HybridSearchService` limits vector candidates to `topK * 2`, then lets `RAGEngine.reciprocalRankFusion` blend vector and BM25 scores; reserve capacity on arrays when extending loops to avoid allocations.
- `RAGEngine` already checks `Task.isCancelled` and yields; keep any new loops cooperative and under ≈50 lines.

## Concurrency & consent

- UI state (`@Published`, `@AppStorage`) stays on `@MainActor`; spawn CPU-bound work via `Task.detached` or calls into `RAGEngine`.
- Any cloud-bound model must flow through `ensureCloudConsentIfNeeded` so `CloudConsentDecision` and telemetry (`recordTransmission`) remain consistent.

## Telemetry, logging, diagnostics

- Use `TelemetryCenter.emit` for surfaced metrics and `Log.info/warning/error/section` for console output—avoid new `print` statements.
- Debug retrieval via `TelemetryDashboardView` (latest 50 events) and `RetrievalLogEntry`; keep added telemetry lightweight and structured.

## LLM routing & tools

- Extend models by conforming to `LLMService`, wiring telemetry metadata, and registering inside `RAGService.instantiateService` / `buildFallbackChain`. Remember to set `toolHandler` on activation.
- Agent tools live in `Services/Tools`, keep weak references to `RAGService`, and execute asynchronously off the main actor.
- Fallback ladder defaults to: selected primary → Apple Foundation Models (tool-enabled) → `OnDeviceAnalysisService`. Update the ladder whenever you add a new implementation.

## SwiftUI patterns

- Chat streams from `RAGService.messages`, trimmed to the latest 50; pruning happens in the service, not the view layer.
- Settings mutate state through `SettingsStore` (bridged by `registerSettingsStore`); avoid writing defaults directly from views.
- When touching badges or telemetry views, keep rendering logic declarative and pull data from published properties rather than direct service queries.

## Build, test, validation

- Preferred loop: open `OpenIntelligence.xcodeproj` and run on the iPhone 17 Pro Max simulator (`⌘B` / `⌘R`).
- CLI build: `xcodebuild -scheme OpenIntelligence -project OpenIntelligence.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`.
- Reset derived data with `./clean_and_rebuild.sh` if builds get noisy.
- After major retrieval/model changes, work through `smoke_test.md`: ingest sample docs, issue a chat query, exercise tool calling, and confirm telemetry badges.

## References

- Architecture + performance: `Docs/reference/ARCHITECTURE.md`, `PERFORMANCE_OPTIMIZATIONS.md`, `ROADMAP.md`, `IMPLEMENTATION_STATUS.md`.
- Sample corpora live in `TestDocuments/`; telemetry UI components sit under `Views/Telemetry/`.
