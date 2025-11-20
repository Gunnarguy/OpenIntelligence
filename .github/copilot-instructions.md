# OpenIntelligence AI Guide

## Architecture & Core Patterns
- **Privacy-First RAG**: iOS 26 app. `RAGService` (@MainActor) orchestrates ingestion, search, and LLM routing. `RAGEngine` (actor) handles CPU-heavy math (BM25, RRF, MMR) to keep UI responsive.
- **Protocol-First**: Services are defined by protocols (`DocumentProcessor`, `EmbeddingService`, `VectorDatabase`, `HybridSearchService`, `LLMService`). Swap implementations via `ContainerService` + `VectorStoreRouter`.
- **Concurrency**: 
  - UI state on `@MainActor` (`@Published`, `@AppStorage`).
  - Heavy work offloaded to `RAGEngine` or `Task.detached`.
  - Use `Task.isCancelled` checks in hot loops.

## Data Flow & Storage
- **Ingestion Pipeline**: `DocumentProcessor` (PDFKit/Vision) → `SemanticChunker` (400w target, 75w overlap) → `EmbeddingService` (512-dim NLEmbedding) → `PersistentVectorDatabase`.
- **Hybrid Search**: Vector candidates (topK * 2) + BM25 keywords → `RAGEngine.reciprocalRankFusion` → MMR diversification.
- **Container-Aware**: Always access storage via `VectorStoreRouter.db(for: containerId)`. Invalidate hybrid caches if mutating outside `storeBatch`.

## LLM & Tooling
- **Routing**: `RAGService.instantiateService` + `buildFallbackChain`. Default: Primary → Apple Foundation Models → On-Device Analysis.
- **Cloud Consent**: Cloud calls MUST pass `ensureCloudConsentIfNeeded` and log via `recordTransmission` for privacy/telemetry.
- **Agent Tools**: Located in `OpenIntelligence/Services/Tools/`. Must hold weak `RAGService` refs and execute async off-main.

## UI & State Management
- **State**: `RAGService` owns the source of truth. Views read via `@EnvironmentObject` or bindings.
- **Settings**: Use `SettingsStore` for preferences. Never access `UserDefaults` directly in views.
- **Messaging**: `RAGService.messages` is the source. UI renders slices (pagination logic in service).

## Telemetry & Debugging
- **Logging**: Use `Log.info/warning/error/section`. Avoid `print`.
- **Dashboard**: `TelemetryDashboardView` + `RetrievalLogEntry` are primary debugging tools.
- **Metrics**: Emit via `TelemetryCenter`.

## Build & Test Workflows
- **Build**: `xcodebuild -scheme OpenIntelligence -project OpenIntelligence.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`
- **Clean**: `./clean_and_rebuild.sh` (use when DerivedData gets noisy).
- **Smoke Test**: Follow `smoke_test.md` after changes (Ingest `TestDocuments/` → Query → Verify Telemetry).
- **Docs**: See `Docs/reference/ARCHITECTURE.md` and `PERFORMANCE_OPTIMIZATIONS.md` for deep dives.
