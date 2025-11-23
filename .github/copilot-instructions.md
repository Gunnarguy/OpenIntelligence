# OpenIntelligence AI Guide

## Project Context

- **Platform**: iOS 26.0+ (Swift 6.0).
- **Core Mission**: Privacy-first RAG (Retrieval-Augmented Generation) running on-device with optional Private Cloud Compute (PCC).
- **Key Technologies**: Swift Concurrency (`actor`, `Task`), Apple Foundation Models, Core ML, PDFKit, Vision, NaturalLanguage.

## Architecture & Core Patterns

- **Protocol-First Design**: All major services are defined by protocols (`DocumentProcessor`, `EmbeddingService`, `VectorDatabase`, `LLMService`). Implementations are swapped via dependency injection.
- **Actor Isolation**:
  - `RAGService` (`@MainActor`): Orchestrates UI state, ingestion, and routing. Source of truth for `documents` and `messages`.
  - `RAGEngine` (`actor`): Handles CPU-intensive tasks (BM25 scoring, RRF fusion, MMR) off the main thread.
- **Containerization**: Data is isolated in `KnowledgeContainer`s. Access storage **only** via `VectorStoreRouter.db(for: containerId)`.

## Data Flow

1.  **Ingestion**: `DocumentProcessor` (PDF/Vision) → `SemanticChunker` (400w/75w overlap) → `EmbeddingService` (512-dim `NLEmbedding`) → `PersistentVectorDatabase` (via `VectorStoreRouter`).
2.  **Retrieval**: Hybrid Search (Vector + BM25) → `RAGEngine.reciprocalRankFusion` → MMR Diversification.
3.  **Generation**: `LLMService` generates response.
    - **Routing**: `AppleFoundationLLMService` (Primary) → `OnDeviceAnalysisService` (Fallback) or `OpenAILLMService` (if configured).
    - **Privacy**: Cloud calls **must** pass `ensureCloudConsentIfNeeded` and log via `recordTransmission`.

## Critical Workflows

- **Build**: `xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'` or ⌘R in Xcode.
- **Clean**: Run `./clean_and_rebuild.sh` to clear DerivedData and force UI updates (especially for Settings).
- **Test**: Follow `smoke_test.md` manually.
  - **Smoke Test**: Ingest `TestDocuments/` → Query → Verify Telemetry Badges.
- **Local LLM**: `Vendor/LocalLLMClient` handles `llama.cpp` integration.

## Coding Conventions

- **Concurrency**: Use structured concurrency (`Task`, `async/await`). **Avoid** `DispatchQueue` unless interfacing with legacy APIs.
- **Logging**: Use `Log.info`, `Log.warning`, `Log.error`. **Do not use** `print` for production logs.
- **Settings**: Access preferences via `SettingsStore`. **Never** access `UserDefaults` directly in Views.
- **UI State**: `RAGService` is the single source of truth. Views use `@EnvironmentObject` or bindings to `RAGService`.
- **Error Handling**: User-facing errors go to `RAGService.lastError`.

## Key Files

- `Services/RAGService.swift`: Main orchestrator.
- `Services/RAGEngine.swift`: Math/Logic actor.
- `Services/LLMService.swift`: LLM protocols and implementations (Apple FM, OpenAI, On-Device).
- `Services/VectorStoreRouter.swift`: Storage access point.
- `Services/DocumentProcessor.swift`: Ingestion logic.
- `Docs/reference/ARCHITECTURE.md`: Detailed technical reference.
