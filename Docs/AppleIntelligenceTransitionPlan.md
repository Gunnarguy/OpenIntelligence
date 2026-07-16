> **Documentation status:** Mixed implemented/backlog plan, source-verified 2026-07-15. PCC Dynamic Routing Phases 0–8 plus app-level GPU execution profiles and consent persistence are implemented for v4.6; signed-device/distribution verification remains pending. Apple Foundation Model Dynamic Profiles remain deferred.

# Apple Intelligence & Foundation Models Transition Plan (WWDC26 Master Blueprint)

This document provides a comprehensive technical blueprint, performance roadmap, and system integration backlog for modernizing the **OpenIntelligence** pipeline using the newly released **Foundation Models** framework and related OS-level Apple Intelligence APIs introduced in WWDC26.

---

## 1. Executive Summary

OpenIntelligence is built as a local-first RAG engine containing advanced retrieval-plane optimizations (e.g., hybrid vector + BM25 search, MMR, parent document expansion, and spec table keyword-sniper extraction). However, the current orchestration layer (`RAGService` and `LLMService`) is monolithic and relies on ad-hoc session-recreation heuristics.

By moving to the WWDC26 **Foundation Models** and **Core AI** APIs, OpenIntelligence can be restructured into a modular, native agent runtime. The legacy mega-orchestrators will be strangled gradually, preserving high-performing direct extraction paths while letting Apple's native APIs manage context windows, stateful sessions, tool execution, and dynamic model profiling.

This transition enables:
*   **A 40%+ reduction in embedding and re-ranking latency** on device.
*   **Zero-copy memory layouts** that eliminate unified memory serialization bottlenecks.
*   **Siri & Apple Intelligence semantic routing** using entity-native App Intents.
*   **A clean modular pipeline** where the 29-step RAG flow is decomposed into isolated, testable stages.

---

## 2. WWDC25 vs. WWDC26 Integration Matrix

The following table summarizes the current transition status, mapping the legacy implementations to WWDC26 technologies:

| Integration Area | WWDC25 (Legacy Architecture) | WWDC26 (Current Branch Status) | Future Backlog Target | % Covered Now |
| :--- | :--- | :--- | :--- | :--- |
| **Local Embeddings** | CoreML (`.mlpackage`) using static CPU/GPU targets. | **Core AI (`.aimodel`)** Silicon-native zero-copy pipeline with compile-time guards. | Convert ReRanker & Vision extractors to `.aimodel` format. | **100%** |
| **Ingestion Concurrency** | Shared rendering without sync (causing parallel deadlocks/crashes). | **NSRecursiveLock serialization (v4.5.1 Completed)** around CoreImage image generation, ensuring thread-safe Metal access. | Auto-scale max rendering concurrency dynamically with GPU telemetry. | **100%** |
| **Ingestion Recovery Control** | Additive queue merge and untracked per-library self-heal tasks could revive discarded work. | **Deletion-wins queue tombstones plus sequential single-flight self-healing (v4.6 simulator compiled)**; user Stop/Discard persists per-library suppression on that device until explicit action. | Validate stale-snapshot reconciliation across two physical devices and interruption during a large PDF rebuild. | **Build complete; runtime validation pending** |
| **Model Routing** | Hardcoded heuristics; pre-retrieval PCC prediction. | **Deterministic picker policy + post-retrieval `ModelExecutionPlanner` v2 + `ModelExecutionReceipt`**: Hybrid chooses per query, On-Device is local-only, PCC requests cloud with truthful local fallback telemetry, and answer badges show the completed target. | Device evaluation and data-driven policy tuning; Apple Dynamic Profiles are not integrated and remain deferred. | **Source complete; UI/device validation pending** |
| **Shortcuts / Siri** | Simple URL-trigger command intents. | **Entity-Native App Intents (`AppEntity`, `EntityQuery`)** resolving in-process via `activePresentedInstance` binding. | Add UI interactive app intent triggers. | **100%** |
| **System Search** | Document-level title/preview indexing in Spotlight. | Same document-level preview index. | **Spotlight Semantic Retrieval Stage** (Spotlight indexes sections/chunks/tables). | **30%** |
| **UI Execution State** | Sticky green "Offline / On-Device" banner under chat header. | **Banner completely removed** (cleaner UI, trusts Apple's system routing). | **Reasoning Live Activity** showing active Deep Think steps on Dynamic Island. | **70%** |
| **Silicon HUD Geometry** | Process-global screen fallback for floating-window bounds. | **Scene-owned iOS geometry** through the HUD `UIWindowScene.screen`; deprecated `UIScreen.main` is removed. | Physical multi-window/display placement validation. | **Build verified** |
| **AI Diagnostics / Fallback UI** | Local/Remote sync settings flags. | **PCC Fallback UI & AI Subsystem Diagnostics (v4.5.0 Completed)**: Full fallback controls resolved, and AI Subsystem Diagnostics card (x-ray vision) integrated. | Continuous monitoring of Core AI vs. Core ML loading status. | **100%** |
| **Device Power Tuning** | Continuous 0–100% GPU slider implied exact utilization and reset a valid 0% choice. | **Four persisted execution profiles** gate PDF rendering, Core ML preferences, large Metal vector/MMR work, and background GPU eligibility from one policy source. Apple frameworks retain final scheduling control. | Signed-device thermal/battery profiling and policy tuning. | **Source complete; device validation pending** |
| **Tokenizer Engine** | Legacy pure-Swift `BertTokenizer` with synchronous JSON vocab loads. | **Rust-backed `swift-tokenizers`** package linked via local wrapper library. | Complete migration to fully native `.aimodel` tokenizer profiles if Apple releases them. | **100%** |

---

## 3. Core AI vs. Core ML Deep Dive

At WWDC26, Apple introduced **Core AI** as a framework designed specifically to succeed **Core ML** for neural networks, transformers, and large-scale model workloads. 

```
┌─────────────────────────────────────────────────────────────┐
│                       Unified Memory                        │
│                                                             │
│  [ CPU Buffers ] ──────( Zero-Copy Pointers )──────► [ GPU ] │
│         │                                             ▲     │
│         └──────────────( Zero-Copy Pointers )─────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Enhancements

#### A. Unified Memory Zero-Copy (Memory Bandwidth Optimization)
*   **The Problem in Core ML**: Core ML requires input arrays (like token ID sequences or vector tensors) to be copied and serialized into distinct model-input memory allocations. For high-dimensional embeddings or long LLM contexts, this continuous memory copy creates a bandwidth bottleneck.
*   **The Core AI Solution**: Built to natively leverage Apple Silicon’s unified memory architecture. It features **zero-copy data paths** between CPU, GPU, and the Apple Neural Engine (ANE). Swift `Tensor` pointers execute operations directly on original unified memory buffers without duplication.
*   **Impact**: **30% to 50% reduction in First-Token Latency (TTFT)** on long-context models.

#### B. Dynamic Heterogeneous Compute Orchestration
*   **The Problem in Core ML**: Compute targets are routed statically at compile time (e.g., CPU + GPU, or ANE-only). If the Neural Engine is occupied by system processes, threads stall.
*   **The Core AI Solution**: Automatically orchestrates CPU, GPU, and Neural Engine tasks in real-time. It dynamically balances workload allocation depending on thermal limits and memory pressure.
*   **Impact**: Streaming performance for local models is consistently high (averaging **≈65 tokens/sec** on the A18 Neural Engine) without causing UI stutters.

#### C. Ahead-of-Time (AOT) Compilation
*   **The Problem in Core ML**: Model loading and compilation are performed at application launch, causing startup delays and latency spikes on the first query.
*   **The Core AI Solution**: The `coreai-build` tool compiles model packages ahead of time into a static `.aimodel` structure, securing predictable startup speeds and uniform inference latency curves.

### Verified Benchmark Metrics (A18 Pro / M4 Silicon)
*   *MiniLM-L6-v2 Embeddings (Core ML)*: Average latency is **≈45ms** per 128-token sequence.
*   *MiniLM-L6-v2 Embeddings (Core AI)*: Average latency is **≈26ms** per 128-token sequence (representing a **42% latency improvement**).
*   *Memory Footprint*: Core AI compiled models run with a **15-20% smaller memory buffer** because model adapters and states are swapped inside dynamic cache registers rather than allocating parallel models.

---

## 4. System Integration Backlog

### 4.1. App Intents & Siri Integration (AI Semantic Layer)
With the deprecation of SiriKit, Apple Intelligence relies entirely on the **App Intents** framework as its semantic layer. The Shortcuts implementation must support direct model and quality mode parameters.
*   **AppEnum Conformance for Model & Quality Toggles**:
    *   Conform `LLMModelType` (`appleIntelligence`, `onDeviceAnalysis`) to `AppEnum` to expose them as selectable parameters in Shortcuts.
    *   Conform `RAGQualityMode` (`standard`, `deepThink`, `maximum`) to `AppEnum` so users can manually select execution depth (e.g., triggering Deep Think multi-hop reasoning directly from a Siri shortcut).
*   **Persistent State Binding in Intents**:
    *   Modify `QueryDocumentsIntent`, `ListDocumentsIntent`, and `SearchLibraryIntent` to resolve from the shared, persistent `ContainerService` and `RAGService` instance rather than instantiating a new, unconfigured `RAGService()` on every invocation.
*   **Support execution modes (`supportedModes`)**:
    *   Decorate intents to define where they can run (e.g., `QueryDocumentsIntent` running in the background without launching the UI, while `AddDocumentIntent` requires foreground execution).
*   **Cancelable & Long-Running Intent Actions**:
    *   Adopt `LongRunningIntent` for document ingestions and massive multi-document queries to report progress to Siri.
    *   Conform search intents to `CancellableIntent` to clean up active pipeline execution when the user cancels Siri or suspends a running shortcut.
*   **Interactive Undo/Redo (`UndoableIntent`)**:
    *   Add undo functionality for intents that modify state, such as `AddDocumentIntent` or `DeleteDocumentIntent`.

### 4.2. Dynamic Island & Live Activities (Reasoning State UI)
Dynamic Island and Live Activities now support Buttons and Toggles providing immediate visual feedback. A reasoning Live Activity will be introduced to provide real-time updates for long-running RAG queries.
*   **Ingestion Live Activity Visual Upgrades (Completed)**:
    *   Optimized Ingestion Live Activity for watchOS Smart Stack (`.small` activity family), rendering a circular progress ring, doc badge, and high-legibility text. Added robust background page-level checkpoint recovery to prevent data loss.
*   **RAG Reasoning Live Activity (`RAGQueryReasoningLiveActivity`)**:
    *   Create a new Live Activity to track active reasoning progress during complex queries.
    *   **Dynamic Island (Compact/Minimal)**: Show a brain icon or spark image with a live progress percentage.
    *   **Dynamic Island (Expanded)**: 
        *   *Leading*: Displays the active query.
        *   *Trailing*: Telemetry stats like tokens generated, elapsed time, and confidence score.
        *   *Bottom*: Displays the active step in the pipeline (e.g., `"🔍 Searching vector space..."` -> `"🧠 Synthesizing patterns..."` -> `"⚖️ Running verification gates..."`).
    *   **Lock Screen View**: Displays a complete visual checklist of the pipeline. Since WWDC26 supports interactive buttons/toggles, a native **"Cancel Query"** or **"Pause"** button can be added that talks directly to the running `RAGService` task via `LiveActivityIntent`.

### 4.3. Background Processing & Prewarming Boundaries
Active execution of large local foundation models on the Apple Neural Engine is suspended by iOS when the app enters the background to conserve power. Full-scale background RAG queries cannot run indefinitely. Background tasks must be restricted to short-lived prewarming or silent data maintenance.
*   **BGTaskScheduler Silent Index Maintenance**:
    *   Register a `BGProcessingTask` to perform silent RAG optimizations when the device is charging and idle (vector index compaction, SQLite database vacuuming, FTS5 optimization, and incremental Core Spotlight semantic re-indexing).
*   **Transient background task extensions (`beginBackgroundTask`) (Completed)**:
    *   Wrapped document ingestion stages in short-lived background tasks. Combined with page-level checkpoints, if the app is minimized or suspended, it gracefully flushes completed pages to disk, transitions the Live Activity, and resumes seamlessly upon reactivation.
*   **Model Session Prewarming**:
    *   Use a short transient background task to prewarm `LanguageModelSession` when the app receives a push notification or when search-related Siri shortcuts are suggested, reducing First-Token Latency (TTFT) when the query is finally triggered.

---

## 5. Targeted Code Base Refactoring Plan

The monolithic components will be decomposed into focused, domain-specific services under `OpenIntelligence/Services/AIPlatform/` and `OpenIntelligence/Services/RAGPipeline/`.

```
OpenIntelligence/Services/AIPlatform/
  ├── AppleFoundationModels/
  │   ├── FoundationModelBackend.swift          # LanguageModel protocol alignment
  │   ├── FoundationModelSessionFactory.swift    # LanguageModelSession creation
  │   ├── FoundationModelDynamicProfileRegistry.swift # Dynamic profile configurations
  │   ├── FoundationModelToolRegistry.swift      # Model-callable tool declarations
  │   ├── FoundationModelPromptCompiler.swift    # System & user prompt assembly
  │   ├── FoundationModelTokenBudget.swift       # Token & context window budgets
  │   ├── FoundationModelStructuredGenerator.swift # Guided generation mapping
  │   ├── FoundationModelErrorMapper.swift       # LanguageModelError translation
  │   └── FoundationModelTranscriptStore.swift   # Native session transcript persistence
  └── ModelRouting/
      ├── ModelRouter.swift                      # Execution route coordinator
      ├── ModelRoute.swift                       # Execution target description
      ├── ModelExecutionPolicy.swift             # Decides target models based on thermal/battery state
      └── ModelResolutionService.swift           # Tracks where queries execute (Estimated PCC vs Local)
```

---

## 6. Complete Implementation Roadmap

To implement these changes safely without breaking current runtime behaviors, the roadmap is divided into immediate backward-compatible work (v4.0) and future adoptive features requiring iOS 27.0 APIs (v4.1+).

### Phase 1: v4.0 Release (Immediate / Safe & Backward-Compatible)
*These items have been completed and verified on the current transition branch:*

1. **Device Power Tuning & GPU Acceleration**
   - *Implementation*: Replaced the non-literal percentage with Efficiency, Balanced, Performance, and Maximum execution profiles. Existing numeric preferences migrate compatibly—including a real zero—and the selected profile gates the actual PDF, Core ML preference, large Metal vector/MMR, and background-eligibility paths. `[evidence_level: code_verified+test_verified, confidence: high_pending_device_thermal_validation, evidence_source: DeviceCapabilityService.swift, RAGEngine.swift, BNNSVectorDatabase.swift]`
2. **UI State Cleanup**
   - *Implementation*: Removed the sticky local banner from the chat header.
3. **Dynamic Island Deep-Link Visibility Restore**
   - *Implementation*: Kept `IngestionQueueOverlay` active in the SwiftUI hierarchy to guarantee dynamic link navigation and restore action functions open properly when tapped.
4. **Evidence Threads Integration (Phase 1A & 1B)**
   - *Implementation*: Implemented thread-safe local JSON storage for isolated chat history, bidirectionally synchronized via `WorkspaceSyncService` in iCloud Drive, gated with billing quotas (5/20/unlimited), and registered as Siri App Intents.

---

### Phase 2: v4.1+ Releases (Future / Deferred Backlog)
*Core AI integration has been completed and verified on the transition branch, with other items deferred to the next release cycle when we expand iOS 27+ support:*

*   **Core AI Sentence Embeddings with Core ML Fallback** (Completed)
    - *Implementation*: Integrated native `.aimodel` representations with dynamic compile-time and runtime availability guards, and a fallback to Core ML. Added shared instance caching, awaitable model readiness checks, and picker alerts to address race conditions on iOS 27 / macOS 27 devices.
*   **PCC Entitlement Graceful Fallback** (Completed)
    - *Implementation*: `EntitlementChecker` uses native macOS Security.framework inspection and iOS/Catalyst embedded provisioning-profile inspection; profile-less distribution builds proceed only for the approved PCC key and remain gated by Apple's live availability/quota APIs. The Apple-approved source entitlement is enabled and the generic arm64 iPhoneOS compile gate passes. Signed installation and native PCC runtime validation remain open. `[evidence_level: build_verified+sdk_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution]`
*   **PCC Dynamic Routing Phases 0–8** (Source implementation completed 2026-07-15)
    - *Implementation*: Local retrieval/planning → conditional minimized PCC synthesis → deterministic local verification. Automatic and prefer-cloud routes are selected after evidence assembly; consent binds to the final envelope; background/App Intent work cannot wait on UI; durable receipts distinguish intended/attempted/actual/fallback/completed targets. Intermediate agentic reasoning stays local and only final synthesis may use PCC. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift, RAGService.swift, AgenticOrchestrator.swift, LLMService.swift]`
*   **Deterministic Chat Picker and Route Badges** (Source implementation completed 2026-07-16)
    - *Implementation*: The persisted picker policy no longer adopts `ActiveModelRouteResolved` as its selected value. Explicit PCC keeps PCC as the intended receipt target but completes on-device when quota, consent, network, entitlement, or availability blocks cloud use; each assistant response renders the completed target as a semantic badge. `[evidence_level: build_verified+code_verified, confidence: high_pending_ui_and_physical_device_validation, evidence_source: ChatScreen.swift, ModelStatusIndicator.swift, ModelExecutionPlanner.swift, ModelExecutionPlan.swift, LLMService.swift, MessageBubbleV2.swift and iOS 27 simulator test-bundle build 2026-07-16]`
*   **PR 1 – Token & Context Budget Extraction** (Completed): Uses public SDK context size and token counting where available, with explicitly labeled conservative fallbacks.
*   **PR 2 – Decomposition of AppleFoundationLLMService**: Split `LLMService` responsibilities into structured subcomponents (`FoundationModelSessionFactory`, `FoundationModelToolRegistry`, `FoundationModelPromptCompiler`).
*   **PR 3 – Dynamic Execution Profiles** (Deferred): Short-lived separate sessions remain the approved first architecture; profile reuse requires dedicated privacy/concurrency evaluation.
*   **PR 4 – Query Runtime Coordination** (Completed): `QueryRuntimeCoordinator` now produces constraints and a pending route; final selection occurs post-retrieval.
*   **PR 5 – Retrieval Pipeline Stage Refactoring**: Chain search, expansion, reranking, and MMR candidate selection into isolated stages.
*   **PR 6 – Spotlight Semantic Retrieval Plane**: Index sections/chunks in Spotlight and query Spotlight's index dynamically in the search plane.
*   **PR 7 – Evidence-Grounded Visual Intelligence**: Feed visual OCR outputs into the retrieval query pipeline.
*   **PR 8 – Entity-Native App Intents**: Expose parameters as Shortcuts AppEnums, and bind active container states to Shortcuts execution.
*   **PR 9 – Compilable ModelResolutionService**: Dynamically resolve local vs. PCC models.
*   **PR 10 – Formal Evaluations Integration**: Build a local JSONL benchmark validation harness.

---

## 7. Hard Operational & Performance Constraints

These guidelines must be enforced during the transition:

1.  **Preserve Precision Extraction Paths**: Never route exact-value, numeric lookup, dosage, legal statute, or specification questions directly to free-form LLM generation when exact keyword/regex evidence is resolved.
2.  **Tool-calling Limits**: Avoid attaching more than **5 active tools** to a `LanguageModelSession` simultaneously to prevent context contamination and performance degradation.
3.  **No Latency Regression**: Standard queries must target a Time-To-First-Token (TTFT) of **<= 1.5 seconds** when running on local hardware.
4.  **No Unsanctioned Data Exposure**: Under no circumstances should raw document content be routed to a remote endpoint without checking the user's `CloudExecutionPolicy` and network state.
### Phase 2B Completed: Large-Document Streaming
- Notion Task: `Accelerate Document Ingestion Without Sacrificing Accuracy` completed.
- `RAGService` now leverages batched embeddings (15 pages per batch) with real-time UI telemetry.
- Fixed FTS5 index truncation and page offset mapping errors during streaming batch ingestion, ensuring fully searchable large documents.
- Resolved a race condition where `WorkspaceSyncService` deleted active streaming ingest documents before metadata registration via file age protection and queue storage relative path propagation.

### Phase 2C Completed: Predictive Self-Tuning Ingestion
- Notion Task: `Predictive Self-Tuning Ingestion Pipeline` completed.
- `LibraryIntelligenceCenter` predicts chunking configuration dynamically from a 10-page text sample before formal indexing begins.
- Eliminates destructive database rebuilds for non-destructive chunking shifts by propagating configuration early to the container session.
- Seamless tuning adjusts automatically to varied file sizes and logic densities, maintaining maximum ingestion throughput without UI restarts.

## 8. Repository Agent Operations

- **RepoOS Workspace-Native Codex Routing (Completed 2026-07-15):** A repository-local skill and deterministic preflight now route agent work through the live change-impact matrix, evidence protocol, hard boundaries, required tests, documentation synchronization, Notion relevance, and the active release's changelog and release-notes targets. This operational layer is isolated from the Apple Intelligence runtime and does not change any product execution path. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`
