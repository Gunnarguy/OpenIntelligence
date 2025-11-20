# OpenIntelligence AI Guide

- Privacy-first iOS 26 RAG app. Ingestion flows `DocumentProcessor` → `SemanticChunker` (target 400 words · clamps 100–800 · 75 overlap) → `EmbeddingService` (NLEmbedding 512-dim with cached norms) → per-container `PersistentVectorDatabase` → `HybridSearchService` (cosine + BM25 via RRF) → streaming `LLMService` with tool-aware fallbacks.
- `RAGService` (MainActor, see `OpenIntelligence/Services/RAGService.swift`) owns state, ingestion, hybrid search, tool routing, and telemetry. Heavy math (BM25 snapshots, MMR, context assembly) must stay inside the `RAGEngine` actor to avoid blocking SwiftUI.
- Services are protocol-first (`DocumentProcessor`, `EmbeddingService`, `VectorDatabase`, `HybridSearchService`, `LLMService`). Register swaps via `ContainerService` + `VectorStoreRouter`; views should only talk through `RAGService` or `SettingsStore`.
- `DocumentProcessor` already wraps PDFKit + Vision OCR + metadata. Reuse `ProcessedChunk.metadata` and `SemanticChunker.Diagnostics` instead of recomputing page/keyword hints.
- Embeddings are 512-dim. Persist via `VectorDatabase.storeBatch` so cached norms stay valid, then call `ContainerService.updateStats` to keep UI + telemetry accurate.
- Retrieval runs through `HybridSearchService`: vector candidate cap = `topK * 2`, then `RAGEngine.reciprocalRankFusion` blends vector/BM25 before MMR diversification. Reserve capacity on hot loops and keep them <≈50 lines with `Task.isCancelled` checks.
- Any cloud-bound LLM call must go through `ensureCloudConsentIfNeeded` and log via `recordTransmission`; this powers privacy prompts and PCC telemetry.
- Telemetry: emit via `TelemetryCenter` and log with `Log.info/warning/error/section`. `TelemetryDashboardView` + `RetrievalLogEntry` are the primary debugging surfaces—avoid ad-hoc `print`.
- LLM routing lives in `RAGService.instantiateService` + `buildFallbackChain`. Default ladder: selected primary → Apple Foundation Models (tool-enabled) → `OnDeviceAnalysisService`. New providers must conform to `LLMService`, wire telemetry metadata, and set `toolHandler` before streaming.
- Agent tools (see `OpenIntelligence/Services/Tools/`) should hold weak `RAGService` refs and execute async off the main actor to keep chat responsive.
- Settings and long-lived preferences flow through `SettingsStore` (configured in `registerSettingsStore`). Views mutate via published bindings—never call UserDefaults directly.
- UI messaging pulls from `RAGService.messages`, already trimmed to 50 entries. Leave pruning logic in the service; views only render slices.
- Storage is container-aware: always ask `VectorStoreRouter.db(for:)` for access, and invalidate hybrid caches if you mutate stored chunks outside `storeBatch`.
- Sample corpora live in `TestDocuments/`; run `smoke_test.md` after changing ingestion, retrieval, or LLM routing (ingest sample docs → ask a grounded query → verify telemetry badges and tool calls).
- Build loop: open `OpenIntelligence.xcodeproj` and run on the iPhone 17 Pro Max simulator (`⌘B/⌘R`). CLI: `xcodebuild -scheme OpenIntelligence -project OpenIntelligence.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`. Use `./clean_and_rebuild.sh` when DerivedData gets noisy.
- Keep UI state on `@MainActor` (`@Published`, `@AppStorage`); spawn CPU-bound work with `Task.detached` or direct calls into `RAGEngine`.
- When integrating local GGUF/Core ML cartridges, manage them via `ModelManager` + `ModelRegistry` and ensure the fallback ladder reflects the new option.
- Docs worth skimming for architecture/perf decisions: `Docs/reference/ARCHITECTURE.md`, `PERFORMANCE_OPTIMIZATIONS.md`, `ROADMAP.md`, `IMPLEMENTATION_STATUS.md`.
