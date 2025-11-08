# OpenIntelligence AI Guide

- **Scope**: Privacy-first iOS 26 RAG app. Pipeline = PDFKit/Vision ingestion → `SemanticChunker` (target 400 · clamp 100–800 · 75 overlap) → `EmbeddingService` (`NLEmbedding` 512-dim, cached norms) → per-container `PersistentVectorDatabase` → hybrid retrieval → streaming LLM.

## Architecture Snapshot

- `RAGService` (@MainActor) orchestrates ingestion, hybrid search, tool calls, telemetry. Heavy math (vector search, BM25, MMR, context assembly) runs in `RAGEngine` background actor.
- Services stay protocol-first: `DocumentProcessor`, `EmbeddingService`, `VectorDatabase`, `HybridSearchService`, `LLMService`. Register concrete implementations through `ContainerService` / `VectorStoreRouter` rather than touching views.
- Retrieval flow: `QueryEnhancementService` expands prompts, `HybridSearchService` fuses cosine + BM25 via reciprocal-rank fusion, `RAGEngine.applyMMR` diversifies before context build.
- Model routing lives in `LLMModelType` + `SettingsStore`; fallbacks = Apple Foundation Models (tool-enabled) → `OnDeviceAnalysisService`. GGUF/Core ML cartridges mount via `ModelRegistry`/`ModelManagerView`.

## Coding Patterns

- Async/await everywhere; keep functions <≈50 lines. UI state updates stay on the main actor (`@Published` in `RAGService`, `@AppStorage` for settings).
- Use `TelemetryCenter.emit` + `Log.section/info/error`; avoid raw `print` in new code paths.
- Preallocate collections in hot loops (`reserveCapacity` in chunking/search) and respect cached embedding norms when computing cosine similarity.
- SwiftUI `onChange` uses the iOS 17 zero-arg form; streaming UI renders the newest 50 messages and prunes >200.

## Retrieval & Data

- `SemanticChunker` exposes diagnostics—update `ChunkingConfig` defaults from there if adjusting overlap/limits.
- Persistent vectors: `PersistentVectorDatabase` stores JSON per knowledge container; mutate via `VectorStoreRouter` so caches + BM25 snapshots stay in sync.
- Hybrid search cache: last 20 query results for 5 minutes. Bust cache when mutating embeddings or chunk payloads.

## Agentic & Models

- Apple Foundation Models tools live under `Services/Tools`; each `@Tool` holds a weak reference back to `RAGService` (`RAGToolHandler`). Ensure tool work stays async and off the main actor.
- When adding an LLM, conform to `LLMService`, wire telemetry metadata, and register inside `RAGService.instantiateService` + fallbacks. Local cartridges must update `ModelRegistry` and set `toolHandler` on activation.

## Build & Validation

- Preferred loop: `open OpenIntelligence.xcodeproj` → ⌘B/⌘R on iPhone 17 Pro Max simulator. CLI: `xcodebuild -scheme OpenIntelligence -project OpenIntelligence.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`.
- If Xcode caches misbehave run `./clean_and_rebuild.sh`.
- Smoke test: import from `TestDocuments/`, verify Documents overlay, run a chat query (check retrieval telemetry + citations), flip model + fallback toggles in Settings.

## References

- Deep dives: `Docs/reference/ARCHITECTURE.md`, `PERFORMANCE_OPTIMIZATIONS.md`, `ROADMAP.md`, `IMPLEMENTATION_STATUS.md`.
- Sample corpora: `TestDocuments/`; telemetry UI under `Views/Telemetry/` for expected metrics.

_Last reviewed: Nov 2025_
