# OpenIntelligence

**Privacy-first RAG for iOS 26**. Import documents, ask questions, get grounded answers that stay on your device whenever possible.

- Native SwiftUI app that orchestrates document ingestion → semantic search → LLM generation.
- Single orchestrator (`RAGService`) keeps state predictable and debuggable.
- Designed to run privately by default with graceful fallbacks when cloud access is required.

---

## Quick Start

1. Clone the repo and open `OpenIntelligence.xcodeproj` with Xcode 16 or newer.
2. Select the `OpenIntelligence` target and run the app (⌘R).
3. Head to **Settings → AI Model** and choose your primary pathway:
     - Apple Intelligence (on-device with automatic Private Cloud Compute escalation)
     - ChatGPT Extension (Apple Intelligence bridge to GPT on iOS 18.1+, user consent per query)
     - OpenAI Direct (bring your own API key)
     - GGUF Local (in-process llama.cpp runtime on iOS once a cartridge is installed)
     - Core ML Local (bundle your own `.mlpackage`, runs on-device via Neural Engine)
     - On-Device Analysis (extractive QA fallback that never leaves the device)
4. Import PDFs or text files in the **Documents** tab.
5. Ask grounded questions from the **Chat** tab; telemetry and retrieval details stream live.

> Need sample content? Try the curated documents in `TestDocuments/`.

---

## App Tour

- **Chat** – Streaming assistant responses with retrieved context, metrics (TTFT, tokens/sec), and chunk viewer.
- **Documents** – File picker, ingestion status overlay, per-document stats, and swipe-to-delete.
- **Settings** – Model picker, fallback chain, Private Cloud Compute toggle, OpenAI config, retrieval tuning, diagnostics.
- **Telemetry Dashboard** – Real-time event feed, performance charts, and quick validation tools.

Each surface is tuned for large knowledge bases: pagination keeps the chat performant, ingestion streams progress, and settings expose every lever without overwhelming new users.

---

## Pipeline Overview

```text
User Document ──▶ DocumentProcessor ──▶ SemanticChunker (target 400 words · 75 overlap · clamps 100–800)
                         └─▶ EmbeddingService (NLEmbedding 512-dim, cached norms)
                         └─▶ VectorStoreRouter ──▶ PersistentVectorDatabase per container (LRU + norms)
                         └─▶ HybridSearchService primes BM25 snapshot
Query ──▶ QueryEnhancementService (synonym expansion) ──▶ EmbeddingService
     └─▶ HybridSearchService (vector cosine + BM25, reciprocal-rank fusion)
     └─▶ RAGEngine MMR diversification & context assembly
     └─▶ LLMService (selected model + fallback chain with tool calling)
Result ──▶ Streaming response + telemetry + citations
```

### Model Flow & Fallbacks

- Primary selection comes from `LLMModelType` (Apple Intelligence, ChatGPT Extension, OpenAI Direct, GGUF Local, Core ML Local, On-Device Analysis) and is persisted in `SettingsStore`.
- `RAGService` wires the chosen service with agentic tool handlers and builds a fallback ladder: Apple Foundation Models (if available on iOS 26) → On-Device Analysis.
- Optional first/second fallback toggles in Settings let you pre-authorize automatic failover without touching the UI mid-session.
- Local cartridges (GGUF/Core ML/MLX) are managed through the Model Manager, persisted via `ModelRegistry`, and activated at startup when present.

---

## What You Experience

- **Document Library** – Drop in PDFs, Markdown, or Office docs and watch a live progress overlay while they are parsed, chunked, and embedded on-device.
- **Chat Workspace** – Ask follow-up questions, inspect retrieved context snippets, and view real-time telemetry (TTFT, tokens/sec, retrieval cost).
- **Settings Hub** – Toggle between Apple Intelligence, ChatGPT Extension, OpenAI, GGUF/Core ML cartridges, and on-device analysis; configure fallbacks, API keys, and Private Cloud Compute permissions.
- **Telemetry Dashboard** – Inspect the pipeline timeline, throughput, and latency when validating larger corpora or tuning the system.

Everything is private by default; nothing leaves the device unless you explicitly connect an external LLM.

## Feature Highlights

- Universal document ingestion with PDFKit + Vision OCR, plain-text, Markdown, code, CSV, and Office formats.
- Adaptive semantic chunking (target 400 words, clamps 100–800, 75-word overlap) with diagnostics, metadata, and language detection baked in.
- Hybrid retrieval: query expansion + vector search + BM25 fusion + MMR diversification to keep answers grounded and diverse.
- Multiple LLM pathways with configurable fallbacks: Apple Intelligence, ChatGPT Extension, OpenAI Direct, GGUF Local, Core ML Local, and On-Device Analysis.
- SwiftUI interface optimised for performance (message pagination, streaming in ~10-char bursts, telemetry overlays, container-aware caches).

## Architecture Snapshot

```text
User
 │      ChatView · DocumentLibrary · Settings · Telemetry
 ▼
@MainActor RAGService (state + orchestration)
 ├─ DocumentProcessor        → PDFKit / Vision / TextKit
 ├─ SemanticChunker          → Diagnostics, topic boundaries, 75-word overlap
 ├─ EmbeddingService         → NLEmbedding 512-dim provider, cached norms
 ├─ VectorStoreRouter        → PersistentVectorDatabase · optional Vectura HNSW
 ├─ HybridSearchService      → Vector + BM25 fusion, RAGEngine offloads math
 └─ LLMService (protocol)    → Apple FM · ChatGPT Ext · OpenAI · GGUF · Core ML · On-Device QA
```

- **RAGService** manages ingestion, querying, telemetry, and tool execution while respecting MainActor state.
- **Protocol-first services** let you swap processors, embeddings, vector stores, or LLMs without touching SwiftUI.
- **RAGEngine** offloads heavy math (vector search, BM25, MMR, context assembly) to keep UI responsive.

### Concurrency and Performance

- The project opts into Swift 6 concurrency with `-default-isolation=MainActor`. Pure CPU work is offloaded to a dedicated background actor `RAGEngine` to avoid main-thread stalls.
- MMR diversification and context assembly now execute on `RAGEngine`, reducing time spent on the main actor during Step 4.5 and Step 5 of the pipeline.
- Embedding generation and LLM generation are invoked off-main via `Task.detached` when safe (no main-actor–isolated calls).
- The background actor includes cooperative cancellation checks to keep long loops preemptible for future UI-driven cancel.

## Service Layer (TL;DR)

| Module | Responsibility | Key Notes |
| --- | --- | --- |
| `DocumentProcessor` | Parse + chunk documents | PDFKit, Vision OCR fallback, semantic paragraphs |
| `SemanticChunker` | Build overlap-aware chunks | Language detection, topic boundaries, metadata, clamps 100–800 |
| `EmbeddingService` | Generate embeddings + cosine similarity | NLEmbedding provider, cached norms, NaN guards |
| `VectorStoreRouter` | Provide per-container vector DB | PersistentVectorDatabase default, optional Vectura HNSW, 5-min LRU cache |
| `HybridSearchService` | Fuse vector + keyword signals | BM25 snapshotting, reciprocal-rank fusion, off-main via `RAGEngine` |
| `VectorDatabase` | Store/search chunk vectors | Persistent JSON storage, proactive norm caching, streaming batch saves |
| `LLMService` | Abstract generation | Apple Intelligence, ChatGPT Extension, OpenAI, GGUF Local, Core ML Local, On-Device Analysis |
| `RAGService` | Orchestrator + state | Manages ingestion, hybrid search, MMR, telemetry, tool calls |

## UI Layer Map

```text
Views/
├─ Chat/                # ChatView + supporting components
├─ Documents/           # DocumentLibraryView
├─ Settings/
│  ├─ SettingsView
│  ├─ DeveloperSettingsView
│  └─ Components/      # ModelInfoCard, InfoRow, etc.
├─ ModelManagement/     # ModelManagerView
├─ Telemetry/           # TelemetryDashboardView, LiveTelemetryStatsView
└─ Diagnostics/         # CoreValidationView
```

Shared models (e.g. `LLMModelType`, `RAGQuery`) live under `Models/`. Services remain inside `Services/` for easy discoverability.

## End-to-End Pipeline

1. **Import** – User selects a document; security-scoped resource access is opened for ingestion.
2. **Parse & Chunk** – `DocumentProcessor` extracts text while `SemanticChunker` builds overlap-aware chunks with metadata and diagnostics.
3. **Embed** – `EmbeddingService` uses `NLEmbedding.wordEmbedding`, averages token vectors, and caches norms for reuse.
4. **Index** – `VectorStoreRouter` routes to a per-container `PersistentVectorDatabase`, persists chunks, and updates BM25 snapshots.
5. **Expand & Retrieve** – `QueryEnhancementService` generates variations, `HybridSearchService` fuses vector + BM25 results off-main.
6. **Diversify** – `RAGEngine` applies MMR to keep context diverse before context window assembly.
7. **Generate** – `LLMService` streams the answer from the active model (with automatic fallback if the primary fails).
8. **Present** – Chat UI renders streaming output with telemetry, source citations, and container-aware metrics.

## Build & Run

1. Open `OpenIntelligence.xcodeproj` in Xcode 16 or later.
2. Select an iOS 26 simulator or device (A17 Pro or M-series recommended).
3. `⌘ + R` to run. The app launches into the chat workspace.

### Optional Configuration

- **OpenAI**: Enter your API key under Settings → OpenAI Configuration. Pick models such as `gpt-4o-mini`, `o1`, or `gpt-5`.
- **Private Cloud Compute**: Toggle permission and execution context (automatic / on-device / prefer cloud / cloud only).
- **Fallbacks**: Toggle first/second fallbacks in Settings; the runtime will step through Apple Intelligence (if available) → On-Device Analysis when the primary fails.

## Privacy Checklist

- Document parsing, embeddings, and vector search are strictly on-device.
- Apple Intelligence uses Private Cloud Compute only for complex prompts; PCC enforces zero retention cryptographically.
- OpenAI integration is opt-in and only sends the user prompt plus retrieved context.
- No analytics or telemetry leave the device.

## Reference Material

Historical design docs, performance logs, and roadmap notes now live in `docs/reference/`. Key files include:

- `ARCHITECTURE.md` – Extended diagrams and rationale.
- `IMPLEMENTATION_STATUS.md` – Feature-by-feature progress.
- `PERFORMANCE_OPTIMIZATIONS.md` – Benchmark data and tuning notes.
- `ROADMAP.md` – Backlog ideas and future enhancements.

## Contributing

1. Branch from `main`.
2. Implement your change using async/await, avoid blocking the main actor, and follow the protocol-first patterns.
3. Run `xcodebuild -scheme OpenIntelligence -project OpenIntelligence.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` (or use Xcode). Use `clean_and_rebuild.sh` if DerivedData gets noisy.
4. Update documentation if you touch architecture, privacy, or user-facing flows.
5. Open a PR with screenshots or logs for any UI/UX changes.

## License

MIT License – see `LICENSE` for details.

---

**Status** · Core RAG pipeline production ready · Hybrid search + local cartridge manager (GGUF/Core ML) shipping in beta.  
**Version** · 1.0.0  
**Last Updated** · November 2025
