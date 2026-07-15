# OpenIntelligence

> **Documentation status:** Source-verified for OpenIntelligence v4.6 on July 15, 2026; signed-device PCC validation remains pending.
> **Scope:** Describes shipped behavior for on-device Apple Intelligence RAG architecture.

<p align="center">
   <img src=".github/assets/openintelligence-app-icon.png" alt="OpenIntelligence app icon" width="132" height="132">
</p>

<p align="center">
   <strong>Local-first document intelligence for macOS and iOS, featuring an entirely on-device Retrieval-Augmented Generation (RAG) pipeline and native Apple Foundation Models integration.</strong>
</p>

<p align="center">
   <a href="https://apps.apple.com/us/app/openintelligence/id6756559175"><img alt="Download OpenIntelligence on the App Store" src="https://img.shields.io/badge/App%20Store-Download-0D96F6?style=for-the-badge&logo=appstore&logoColor=white"></a>
   <a href="Docs/DEMO.md"><img alt="Read the OpenIntelligence demo guide" src="https://img.shields.io/badge/Demo-Guide-6E56CF?style=for-the-badge"></a>
   <a href="Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md"><img alt="Read the OpenIntelligence architecture guide" src="https://img.shields.io/badge/Architecture-Read-111827?style=for-the-badge"></a>
   <a href="https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075"><img alt="View the OpenIntelligence public roadmap" src="https://img.shields.io/badge/Public-Roadmap-FF6B6B?style=for-the-badge&logo=notion&logoColor=white"></a>
</p>

OpenIntelligence is an exploratory, privacy-obsessed document query assistant built natively for Apple platforms. Document ingestion, vector indexing, lexical retrieval, planning, and verification remain on device. On iOS/macOS 27+, optional final synthesis may use Apple Private Cloud Compute only after entitlement evidence, capability, quota, minimization, and consent gates pass. The platform-specific entitlement path is generic arm64 iPhoneOS compile-verified, and no third-party cloud wrapper is used. Signed-installation PCC validation remains pending. `[evidence_level: build_verified, confidence: high_for_source_unverified_for_device, evidence_source: EngineSDKCompatibility.swift, ModelExecutionPlanner.swift, RAGService.swift, FoundationModelCapabilityProvider.swift]`

---

## 📚 Rigorous Engineering Documentation

OpenIntelligence is backed by extensive, rigorous engineering documentation detailing how reliable, hallucination-resistant on-device RAG is achieved using Apple's 4K-token local context windows.

### 🗺️ Documentation Atlas
* [**Documentation Atlas (`Docs/README.md`)**](Docs/README.md): The unified index of all verified codebase audits, pipeline specs, and technical research sheets. Start here to navigate the documentation.

### Core Architecture & Systems
* [**System Architecture**](Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md): The high-level view of the decoupled import-time and query-time pipelines.
* [**Retrieval Pipeline (`RETRIEVAL_PIPELINE.md`)**](Docs/RETRIEVAL_PIPELINE.md): Deep dive into the hybrid search engine (BM25 + Core ML Vector) and Reciprocal Rank Fusion implementation.
* [**Ingestion Pipeline (`INGESTION_PIPELINE.md`)**](Docs/INGESTION_PIPELINE.md): Details of the semantic chunker, local Vision OCR fallbacks, and NLP metadata extraction.
* [**Privacy & Routing (`PRIVACY_AND_ROUTING.md`)**](Docs/PRIVACY_AND_ROUTING.md): Strict local-first data guarantees, local cache layouts, and routing protocols.

### Apple Intelligence Engineering Specs
* [**Apple Foundation Models Specs**](Docs/Engineering/APPLE_MODELS.md): Optimization guide for macOS/iOS 26.x/27, managing 4K token budgets, guided generation via `@Generable`, and `SystemLanguageModel` sessions.
* [**Apple Document Intelligence**](Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md): Practical integration with Vision OCR, SFSpeechRecognizer, PDFKit, and CoreText for semantic document parsing.
* [**Private Cloud Compute (PCC)**](Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md): Analysis of Apple's PCC enclave constraints, secure remote processing, and native execution routing layers.

### Audits & Constraints
* [**Hard Limits**](Docs/Engineering/HARD_LIMITS.md): A centralized reference for token boundaries, model caps, memory limitations, and platform bottlenecks.
* [**Current State & Gaps**](Docs/CURRENT_STATE_AND_GAPS.md): Analysis of local inference latency, context packing, and model capability gaps.
* [**Evaluation Framework**](Docs/EVALS.md): Detailed verification procedures using `scripts/run_rag_benchmarks.py` to assert extraction accuracy and similarity scores.

### Agent Workspace Operations
* [**RepoOS Command Center**](Docs/RepoOS/00_REPO_COMMAND_CENTER.md): Routes repository work through canonical evidence, safe edit boundaries, required tests, documentation synchronization, and release gates.
* [**OpenIntelligence RepoOS Skill**](.codex/skills/route-openintelligence-work/SKILL.md): Gives Codex a repository-local task navigation layer backed by the live change-impact matrix, explicit Notion relevance checks, and active-release-aware changelog and release-notes targets. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`

---

## ⚙️ Technical Architecture Overview

The runtime operates in two decoupled phases:

```mermaid
flowchart TD
  subgraph INGEST["Import-Time Pipeline"]
    A1["Import Files"]
    SCAN["Predictive Pre-Scan (10 pages)"]
    A1 --> SCAN
    SCAN --> A2["File Size Check"]
    A2 -- "< 10MB" --> A3["Standard Extraction & Parsing"]
    A3 --> A4["Semantic Chunking"]
    A4 --> A5["Vector & SQLite Indexing"]
    
    A2 -- ">= 10MB" --> S1["Stream Batches (15 pages)"]
    S1 --> S2["Extract Chunks"]
    S2 --> S3["Generate Embeddings"]
    S3 --> S4["Store Batch to Vector & DB"]
    S4 --> S5{"More Pages?"}
    S5 -- "Yes" --> S1
    S5 -- "No" --> S6["Finalize Ingestion"]
  end

  subgraph QUERY["Query-Time Pipeline"]
    B1["User Query"]
    B2["Analyze Intent & HyDE Expansion"]
    B3["Hybrid Retrieval & RRF Merge"]
    B4["Cross-Encoder Reranking"]
    B5["Verification Gates"]
    B6["Generative LLM Response"]
    B1 --> B2 --> B3 --> B4 --> B5 --> B6
  end

  A4 --> B3
```

### 🧠 Quality Modes & Inference Routing
The entire RAG architecture operates on a strict **29-Step Pipeline** (6 Ingestion steps + 23 Query Loop steps). To handle complex queries, the query loop routes dynamically across three agentic modes and foundation models:

#### 3 Agentic Quality Modes
* **Standard:** Executes the 23-step query loop sequentially for maximum speed and battery life.
* **Deep Think:** Actively loops the retrieval agent through 4-10 concurrent reasoning sessions until it hits 98% confidence (scales dynamically based on device thermal state).
* **Maximum:** Removes the 8-session ceiling, granting the orchestrator an unlimited budget to recursively hunt down answers up to 50 loops.

#### 2 Public Foundation Model Targets
* **On-Device Apple Intelligence:** `SystemLanguageModel.default` executes retrieval-adjacent analysis and any synthesis that fits the live SDK context budget. OpenIntelligence does not claim a separately selectable 3B, 20B, or Advanced runtime because the installed public SDK exposes no such model selector.
* **Private Cloud Compute:** On iOS/macOS 27+, the post-retrieval planner may select `FoundationModels.PrivateCloudComputeLanguageModel` for an evidence-sufficient long-context or multi-document synthesis. The app checks its signed PCC entitlement, live availability, quota, network, foreground/consent state, and exact context budget; only a minimized evidence envelope crosses the PCC boundary. iOS/macOS 26 remains local-only.

Each response can carry a durable route receipt separating the intended, attempted, actual, fallback, and completed targets. Retrieval and verification remain local regardless of synthesis target. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift, RAGService.swift, LLMService.swift]`

---

## 🗺️ Codebase Map

| Module | Core Files | Responsibility |
| :--- | :--- | :--- |
| **Ingestion** | `DocumentProcessor.swift`, `LayoutAwareExtractor.swift` | Document content extraction, Vision OCR fallback, semantic structure recovery. |
| **Chunking** | `SemanticChunker.swift`, `ContentTaggingService.swift` | Context-aware document chunking, entity resolution, NLP metadata enrichment. |
| **Indexing** | `SQLiteFullTextService.swift`, `BNNSVectorDatabase.swift` | SQLite FTS5 lexical storage and local BNNS-accelerated vector indexing. |
| **Retrieval** | `HybridSearchService.swift`, `ContextPackingService.swift` | BM25 + Vector hybrid merging, parent-chunk reconstruction, exact token packing. |
| **Orchestration** | `RAGEngine.swift`, `AgenticOrchestrator.swift` | Reranking, MMR, context packing, execution coordination, and closed-loop agentic reasoning. |
| **Foundation Models**| `LLMService.swift`, `FoundationModelRoutePolicy.swift` | On-device SLM context execution, Private Cloud Compute escalation, and routing. |
| **Evidence Threads**| `EvidenceThread.swift`, `EvidenceThreadStore.swift` | Thread-safe local persistence of conversational research queries and verification results. |
| **Storage & Sync**| `SettingsStore.swift`, `EntitlementStore.swift` | Persistence of feature gates, StoreKit 2 quotas, and iCloud ubiquity container sync. |
| **User Interface**| `ChatScreen.swift`, `DocumentLibraryView.swift` | Primary SwiftUI surfaces for conversational RAG queries and library document management. |
| **Shortcuts** | `RAGAppIntents.swift`, `ScreenAwarenessIntents.swift` | Siri voice integration and entity-native App Intents resolving in-process. |
| **Diagnostics** | `EvidenceThreadDebugService.swift` | Developer-only view and helper service to test local persistent store integrity. |

---

## 🛠️ Placeholders & Scaffolding Warnings

To maintain codebase transparency, please note:
* **Core AI Integration:** Fully integrated and registered via `CoreAISentenceEmbeddingProvider.swift`. Runs zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, automatically falling back to the standard `CoreMLSentenceEmbeddingProvider` on older targets. Powered by a unified, high-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) wrapper target for microsecond-latency batch tokenization and exact byte-level offset matching.
* **Private Cloud Compute (PCC):** Apple approved the managed entitlement on 2026-07-15 and the source entitlement is enabled for v4.6. Source integration is complete, but a newly signed physical-device build, Archive/TestFlight artifact, live quota behavior, and actual PCC execution still require validation before production readiness is claimed. `[evidence_level: code_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution, evidence_source: OpenIntelligence.entitlements and user confirmation 2026-07-15]`
* **iCloud Sync:** Sync utilizes iCloud Drive ubiquity containers (`NSFileCoordinator` and `NSMetadataQuery`). The app does not utilize CloudKit databases.
* **Pro Tier Document Limit:** Document uploads are restricted to a hard quota of 1,000 documents under the Pro tier. Unlimited uploads are restricted to the Lifetime tier.
* **Evidence Thread Synchronization:** Thread history JSON arrays are stored under `Application Support/EvidenceThreads/<containerId>/` and are synchronized bidirectionally across devices via `WorkspaceSyncService` in iCloud Drive, gated by tier-specific limits (5 Free / 20 Pro / Unlimited Lifetime).

---

## 🚀 Build & Verification

### Requirements
* macOS Tahoe (26.x) with Xcode 26+
* iOS 26.0+ SDK target support
* Apple Silicon (M1+ / A17 Pro+) for adequate Neural Engine throughput

### Instructions
1. Clear macOS extended attributes to prevent codesign failure:
   ```bash
   /usr/bin/xattr -cr /Users/gunnarhostetler/Documents/GitHub/OpenIntelligence
   ```
2. Compile the simulator smoke target:
   ```bash
   ./scripts/build_simulator_smoke.sh
   ```
3. Execute the local RAG pipeline validation harness:
   ```bash
   python3 scripts/run_rag_benchmarks.py
   ```

---

## License
OpenIntelligence is open-source software. See [LICENSE](LICENSE) for details.
\n## Document Ingestion Optimization\nOpenIntelligence now supports massive documents (500+ pages) through an end-to-end streamed and batched ingestion pipeline, preventing OOM crashes during CoreImage text-layer rendering and LLM embedding generation.\n
