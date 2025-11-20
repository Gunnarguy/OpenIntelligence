# OpenIntelligence

**Privacy-first RAG for iOS 26**. Import documents, ask questions, get grounded answers powered by advanced hybrid search and multiple LLM pathways that prioritize on-device processing.

- Native SwiftUI app with complete document ingestion → hybrid search (vector + BM25 + MMR) → streaming LLM generation pipeline
- Single orchestrator (`RAGService`) with container-aware storage and telemetry-driven observability
- Designed to run privately by default with graceful cloud fallbacks when needed
- **Latest**: Chat streaming fixes, GGUF model persistence, multi-turn conversations working smoothly

---

## Quick Start

1. Clone the repo and open `OpenIntelligence.xcodeproj` with Xcode 16+
2. Select the `OpenIntelligence` target and run (⌘R) on iPhone 17 Pro Max simulator or device
3. Head to **Settings → AI Model** and choose your primary pathway:
     - **Apple Intelligence** (on-device with automatic Private Cloud Compute escalation) - PRIMARY
     - **ChatGPT Extension** (Apple Intelligence bridge to GPT via iOS 18.1+, per-query consent)
     - **GGUF Local** (in-process llama.cpp runtime, persistent model cartridges)
     - **Core ML Local** (bundle your own `.mlpackage`, runs on Neural Engine)
     - **OpenAI Direct** (macOS only, bring your own API key)
     - **On-Device Analysis** (extractive QA fallback, never leaves device)
4. Import PDFs or text files in the **Documents** tab
5. Ask grounded questions from the **Chat** tab; telemetry badges show execution location (📱/☁️/🔑) and tool calls (🔧×N)

> Sample content in `TestDocuments/` including technical specs about the app itself!

---

## App Tour

- **Chat** – Streaming responses with smooth token delivery (50-char bursts @ 80ms), real-time telemetry badges (📱/☁️/🔑 execution location + 🔧×N tool calls), retrieved context viewer, metrics (TTFT, tokens/sec)
- **Documents** – File picker with drag-drop, live ingestion progress overlay, per-document stats (pages, chunks, metadata), swipe-to-delete
- **Settings** – Model picker with fallback chain configuration, Private Cloud Compute toggle, OpenAI config, retrieval tuning (top-K, MMR lambda), diagnostics
- **Telemetry Dashboard** – Real-time event feed, performance charts, vector space visualizations, retrieval logs

Each surface is optimized for large knowledge bases: message pagination (newest 50, prune >200), streaming ingestion progress, container-aware caching.

---

## Pipeline Overview

```text
User Document ──▶ DocumentProcessor (PDFKit + Vision OCR)
                         └─▶ SemanticChunker (target 400w · clamp 100-800 · 75 overlap)
                         └─▶ EmbeddingService.forProvider(containerId) (NLEmbedding 512-dim default)
                         └─▶ VectorStoreRouter ──▶ PersistentVectorDatabase per container
                         └─▶ HybridSearchService primes BM25 snapshot

Query ──▶ QueryEnhancementService (synonym expansion)
     └─▶ EmbeddingService (container-specific provider)
     └─▶ HybridSearchService (vector cosine + BM25 ──▶ RRF fusion ──▶ MMR diversification)
     └─▶ RAGEngine offloads math (BM25 scoring, MMR, context assembly)
     └─▶ LLMService (selected model + fallback chain + tool calling via RAGToolHandler)
Result ──▶ Streaming response with telemetry badges + citations + container stats
```

### Model Flow & Fallbacks

- Primary selection from `LLMModelType` (Apple Intelligence, ChatGPT Extension, GGUF Local, Core ML Local, OpenAI Direct, On-Device Analysis) persisted in `SettingsStore`
- `RAGService` wires chosen service with 12 @Tool-decorated agentic functions (search, summarize, list docs, analytics)
- **Automatic fallback ladder**: Primary → Apple Foundation Models (iOS 26+) → On-Device Analysis
- Optional first/second fallback toggles in Settings pre-authorize failover
- Local cartridges (GGUF/Core ML) managed via `ModelManager` + `ModelRegistry`, persisted in Application Support (not Documents, so simulator builds keep models)

---

## What You Experience

- **Document Library** – Drop in PDFs, Markdown, Office docs and watch live progress overlay with per-chunk stats while parsing, chunking, and embedding happen on-device
- **Chat Workspace** – Ask follow-up questions with smooth streaming (no more freeze-and-dump), inspect retrieved context snippets with MMR diversification, view real-time telemetry badges showing where inference ran (📱 on-device / ☁️ PCC / 🔑 cloud API) and how many tools were called (🔧×3)
- **Settings Hub** – Toggle between all 6 LLM pathways with live availability checks, configure per-container strict mode and embedding providers, set fallback chains, tune retrieval (top-K, MMR lambda), manage API keys and PCC permissions
- **Telemetry Dashboard** – Inspect complete pipeline timeline with stage breakdowns (embedding → searching → generating), throughput metrics (TTFT, tokens/sec), vector space projections (UMAP), and retrieval logs with similarity scores
- **Model Manager** – Install GGUF/Core ML cartridges from URLs with progress tracking, activate models, view installation history

Everything is private by default; nothing leaves the device unless you explicitly connect an external LLM or approve PCC.

## Feature Highlights

- **Universal document ingestion**: PDFKit + Vision OCR, plain-text, Markdown, code, CSV, Office formats with semantic metadata extraction
- **Adaptive semantic chunking**: Target 400 words (clamps 100-800), 75-word overlap, topic boundary detection, language identification, semantic density calculation with full diagnostics
- **Hybrid retrieval**: Query expansion + vector search (cosine with cached norms) + BM25 keyword matching + reciprocal rank fusion + MMR diversification → grounded, diverse answers
- **6 LLM pathways** with configurable fallbacks: Apple Intelligence (primary), ChatGPT Extension, GGUF Local (llama.cpp), Core ML Local, OpenAI Direct (macOS), On-Device Analysis (fallback)
- **Tool-aware AI**: 12 @Tool-decorated agentic functions (search, list, summarize, analytics) callable by Apple Intelligence models
- **SwiftUI optimized for performance**: Message pagination (newest 50, prune >200), streaming in 50-char bursts @ 80ms, defer blocks guarantee cleanup, explicit animation controls, container-aware LRU caches
- **Telemetry-driven observability**: Real-time badges in chat UI, execution location inference (TTFT thresholds), tool call counters, full event logging via TelemetryCenter
- **Model persistence**: ModelRegistry cartridges in Application Support (survives simulator builds), GGUF/Core ML download with progress tracking
- **Chat UX fixes** (Nov 2025): Concurrent query guard, defer cleanup for isProcessing flag, proper error display, no more freeze after first message

## Architecture Snapshot

```text
User
 │      ChatViewV2 · DocumentsView · Settings · TelemetryDashboard · ModelManager
 ▼
@MainActor RAGService (state + orchestration + tool routing)
 ├─ DocumentProcessor        → PDFKit / Vision OCR / TextKit
 ├─ SemanticChunker (actor)  → Topic boundaries, language detection, 75-word overlap, diagnostics
 ├─ EmbeddingService         → Provider factory (NLEmbedding / Core ML / Apple FM)
 ├─ VectorStoreRouter (actor)→ PersistentVectorDatabase per container, 5-min LRU cache
 ├─ HybridSearchService      → Vector + BM25 fusion, RAGEngine offloads math
 ├─ RAGEngine (actor)        → BM25 scoring, RRF, MMR, context assembly (off main actor)
 ├─ RAGToolHandler           → 12 @Tool functions for Apple Intelligence
 └─ LLMService (protocol)    → 6 implementations with streaming + tool support
       ├─ AppleFoundationLLMService (iOS 26+, on-device + PCC, tool calling)
       ├─ AppleChatGPTExtensionService (iOS 18.1+, per-query consent)
       ├─ LlamaCPPiOSLLMService (GGUF cartridges, ModelRegistry)
       ├─ CoreMLLLMService (Core ML .mlpackage, needs tokenizer)
       ├─ OpenAILLMService (macOS only, direct API)
       └─ OnDeviceAnalysisService (extractive QA, always available)
```

- **RAGService** (@MainActor) manages ingestion, querying, telemetry, tool execution while respecting Swift concurrency
- **Protocol-first services** let you swap processors, embeddings, vector stores, or LLMs without touching SwiftUI
- **RAGEngine** (actor) offloads heavy math (BM25 snapshots, RRF fusion, MMR diversification, context assembly) to keep UI responsive
- **Defer blocks** guarantee cleanup (isProcessing flag always resets even on cancellation/error)
- **Container isolation**: Each knowledge container has dedicated vector store, BM25 snapshot, embedding provider, and strict mode settings

### Concurrency and Performance

- Swift 6 concurrency with `-strict-concurrency=complete`, MainActor isolation by default
- CPU-intensive work offloaded to `RAGEngine` actor: BM25 scoring, RRF fusion, MMR diversification, context assembly
- Embedding generation and LLM streaming invoked off-main via `Task.detached` or actor methods
- Cooperative cancellation checks (`Task.isCancelled`) in long loops for preemptible operations
- **Recent fixes** (Nov 2025):
  - Streaming UI: Removed premature `resetStreamingState()` race condition, added explicit `withAnimation(.linear)` wrapper, increased pump timing to 50 chars @ 80ms
  - Chat freezing: Added defer block to guarantee `isProcessing` cleanup, concurrent query guard, proper error handling with user-facing messages
  - Toolbar glitches: Disabled menu when empty, added opacity instead of foregroundStyle, `.animation(nil)` to prevent repeating fade-in
  - Model persistence: Fixed simulator builds by using Application Support instead of volatile Documents directory

## Service Layer (TL;DR)

| Module | Responsibility | Key Notes |
| --- | --- | --- |
| `DocumentProcessor` | Parse + chunk documents | PDFKit, Vision OCR fallback, metadata extraction |
| `SemanticChunker` | Build overlap-aware chunks | Topic boundaries, language detection, semantic density, clamps 100-800, 75 overlap |
| `EmbeddingService` | Generate embeddings + similarity | Provider factory pattern, per-container selection, cached norms, NaN guards |
| `VectorStoreRouter` | Provide per-container vector DB | PersistentVectorDatabase default, 5-min LRU cache, lazy instantiation |
| `HybridSearchService` | Fuse vector + keyword signals | BM25 snapshots, RRF fusion (k=60), off-main via `RAGEngine` |
| `RAGEngine` | Heavy math actor | BM25 scoring, RRF, MMR (λ=0.7), context assembly, cooperative cancellation |
| `VectorDatabase` | Store/search chunk vectors | Persistent JSON per container, proactive norm caching, streaming batch saves |
| `LLMService` | Abstract generation | 6 implementations, protocol-based, streaming + tool support |
| `RAGToolHandler` | Agentic tool functions | 12 @Tool-decorated functions for Apple Intelligence, weak RAGService ref |
| `RAGService` | Orchestrator + state | Manages ingestion, hybrid search, MMR, telemetry, tool routing, container scoping |
| `TelemetryCenter` | Observability | Event logging, performance tracking, execution location inference |
| `ModelRegistry` | Model cartridge system | GGUF/Core ML persistence in Application Support, installation tracking |

## UI Layer Map

```text
Views/
├─ ChatV2/              # ChatViewV2 + MessageList + ChatComposer + ResponseDetails
│  ├─ ChatScreen.swift       # Main coordinator with streaming state
│  ├─ ChatComposer.swift     # Input field with auto-grow
│  ├─ MessageListView.swift  # Paginated history (newest 50)
│  └─ InferenceLocationBadge + ToolCallBadge  # Telemetry overlays
├─ Documents/           # DocumentsView with import + progress overlay
├─ Settings/
│  ├─ SettingsView      # Model picker, fallbacks, PCC toggle
│  ├─ DeveloperSettingsView
│  └─ Components/       # ModelInfoCard, InfoRow, etc.
├─ ModelManagement/     # ModelManagerView, ModelDownloadService
├─ Telemetry/           # TelemetryDashboardView, LiveTelemetryStatsView, VisualizationView
└─ Diagnostics/         # CoreValidationView
```

Shared models (`LLMModelType`, `RAGQuery`, `ResponseMetadata`) live under `Models/`. Services remain inside `Services/` for easy discoverability.

## End-to-End Pipeline

1. **Import** – User selects document; security-scoped resource access granted
2. **Parse & Chunk** – `DocumentProcessor` extracts text (PDFKit/Vision OCR) → `SemanticChunker` builds 400-word target chunks (clamps 100-800, 75 overlap) with topic boundaries, language detection, diagnostics
3. **Embed** – `EmbeddingService.forProvider(containerId)` uses container-specific provider (NLEmbedding default), averages token vectors, caches norms
4. **Index** – `VectorStoreRouter` routes to per-container `PersistentVectorDatabase`, persists chunks + norms in JSON, updates BM25 IDF snapshots
5. **Expand & Retrieve** – `QueryEnhancementService` generates synonym variations → `HybridSearchService` runs parallel vector search (cosine, topK×2 candidates) + BM25 keyword scoring → `RAGEngine` fuses via RRF (k=60) off main actor
6. **Diversify** – `RAGEngine.applyMMR` (λ=0.7) keeps context diverse before window assembly
7. **Generate** – `LLMService` streams answer from active model with tool calling support; fallback ladder kicks in on failure (primary → Apple FM → On-Device Analysis)
8. **Present** – Chat UI renders streaming output in 50-char bursts @ 80ms with `withAnimation(.linear)`, shows telemetry badges (📱/☁️/🔑 + 🔧×N), displays source citations and container-aware metrics

## Build & Run

1. Open `OpenIntelligence.xcodeproj` in Xcode 16+
2. Select iPhone 17 Pro Max simulator (or physical iOS 26 device for Apple Intelligence)
3. `⌘R` to run; app launches into chat workspace

### Build Validation
```bash
xcodebuild -scheme OpenIntelligence \
  -project OpenIntelligence.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  build
```

Use `./clean_and_rebuild.sh` when DerivedData gets noisy.

### Optional Configuration

- **OpenAI** (macOS only): Enter API key under Settings → OpenAI Configuration
- **Private Cloud Compute**: Toggle permission + execution context (automatic / on-device / prefer cloud / cloud only)
- **Fallbacks**: Enable first/second fallback toggles; runtime steps through primary → Apple FM (if available) → On-Device Analysis
- **GGUF Models**: Install via Model Manager from URLs (e.g., Llama 3.2, Mistral, Phi), persisted in Application Support
- **Per-Container Settings**: Select embedding provider (NLEmbedding / Core ML / Apple FM), enable strict mode for topic enforcement

## Privacy Checklist

- Document parsing, embeddings, vector search, and BM25 scoring are strictly on-device
- Apple Intelligence uses Private Cloud Compute only for complex prompts exceeding on-device capacity; PCC enforces cryptographic zero retention
- OpenAI integration (macOS only) is explicit opt-in, sends prompt + retrieved context only
- ChatGPT Extension requires per-query user consent via iOS 18.1+ system prompt
- GGUF/Core ML local models never leave device
- No analytics or telemetry data transmission; TelemetryCenter logs stay local for debugging
- All cloud transmissions logged with timestamps via `recordTransmission` for transparency

## Recent Updates (November 2025)

### Chat UX Fixes ✅
- **Streaming UI**: Fixed freeze-and-dump behavior by removing premature `resetStreamingState()` call, added explicit `withAnimation(.linear)` wrapper, increased pump timing to 50 chars @ 80ms
- **Multi-turn conversations**: Added defer block to guarantee `isProcessing` flag cleanup even on cancellation/error, preventing chat from freezing after first query
- **Concurrent query guard**: Blocks new queries while processing to prevent state corruption
- **Error handling**: Proper user-facing error messages displayed in chat, no more silent failures
- **Toolbar glitches**: Fixed three-dots menu repeating fade-in animation by using `.opacity()` instead of `.foregroundStyle()` and adding `.animation(nil)` directive

### Model Persistence ✅
- **Simulator fix**: Changed GGUF/Core ML model storage from Documents (volatile in simulator) to Application Support (persists across builds)
- **Platform-specific paths**: `#if targetEnvironment(simulator)` conditional compilation for correct directory selection

### Telemetry Badges ✅
- **Execution location**: Real-time badges show where inference ran (📱 on-device / ☁️ PCC / 🔑 cloud API) based on TTFT thresholds
- **Tool call counter**: 🔧×N badge displays number of agentic function calls per response
- **Integration**: Badges rendered inline with message timestamps in MessageMetaView

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

**Status** · Core RAG pipeline production-ready · Hybrid search + tool calling + local cartridge manager shipping  
**Version** · 1.0.0  
**Last Updated** · November 19, 2025  
**Platform** · iOS 26.0+ (simulator + device)  
**Build Status** · ✅ Zero errors, zero warnings
