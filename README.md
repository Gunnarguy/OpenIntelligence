# OpenIntelligence

> **Documentation status:** Verified for OpenIntelligence v4.3 on June 20, 2026.
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

OpenIntelligence is an exploratory, privacy-obsessed document query assistant built natively for Apple platforms. It demonstrates that production-grade document ingestion, vector indexing, lexical retrieval, and generative AI can run **entirely on device** without sacrificing privacy or relying on third-party cloud wrappers.

---

## 📚 Rigorous Engineering Documentation

OpenIntelligence is backed by extensive, rigorous engineering documentation detailing how reliable, hallucination-resistant on-device RAG is achieved using Apple's 4K-token local context windows. Start here:

### Core Architecture & Systems
* [**System Architecture**](Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md): The high-level view of the decoupled import-time and query-time pipelines.
* [**Retrieval Pipeline (`RETRIEVAL_PIPELINE.md`)**](Docs/RETRIEVAL_PIPELINE.md): Deep dive into the hybrid search engine (BM25 + Core ML Vector) and Reciprocal Rank Fusion implementation.
* [**Ingestion Pipeline (`INGESTION_PIPELINE.md`)**](Docs/INGESTION_PIPELINE.md): How the system chunks documents, runs local Vision OCR fallbacks, and structures semantic data.
* [**Privacy & Routing (`PRIVACY_AND_ROUTING.md`)**](Docs/PRIVACY_AND_ROUTING.md): Strict local-first data guarantees and routing protocols.

### Apple Intelligence Engineering Specs
* [**Apple Foundation Models Specs**](Docs/Engineering/APPLE_MODELS.md): Optimization for macOS/iOS 26.x and WWDC26 betas, managing 4K token budgets and `SystemLanguageModel` sessions.
* [**Apple Document Intelligence**](Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md): Detailed usage of Vision, PDFKit, and CoreText for semantic extraction.
* [**Private Cloud Compute (PCC)**](Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md): Documentation on Apple's PCC architecture constraints and secure enclave routing.

### Audits & Constraints
* [**Hard Limits**](Docs/Engineering/HARD_LIMITS.md): A transparent look at engine constraints and where memory bottlenecks occur.
* [**Current State & Gaps**](Docs/CURRENT_STATE_AND_GAPS.md): Ongoing challenges with local LLM hallucination and pipeline latency.
* [**Evaluation Framework**](Docs/EVALS.md): How local `scripts/run_rag_benchmarks.py` scripts are run to continuously validate output quality.

---

## ⚙️ Technical Architecture Overview

The runtime operates in two decoupled phases:

```mermaid
flowchart TD
  subgraph INGEST[Import-Time Pipeline]
    A1[Import files]
    A2[Extract & normalize (Vision OCR)]
    A3[Semantic Chunking]
    A4[Build FTS5 & BNNS vector indexes]
    A1 --> A2 --> A3 --> A4
  end

  subgraph QUERY[Query-Time Pipeline]
    B1[User query]
    B2[Analyze intent & HyDE expansion]
    B3[Hybrid Retrieval & RRF merge]
    B4[Cross-encoder reranking]
    B5[Verification Gates]
    B6[Generative LLM Response]
    B1 --> B2 --> B3 --> B4 --> B5 --> B6
  end

  A4 --> B3
```

### 🧠 Quality Modes & Inference Routing
The entire RAG architecture operates on a strict **29-Step Pipeline** (6 Ingestion steps + 23 Query Loop steps). To handle complex queries, the query loop escalates dynamically across three agentic modes and foundation models:

**3 Agentic Quality Modes**
* **Standard:** Executes the 23-step query loop sequentially for maximum speed and battery life.
* **Deep Think:** Actively loops the retrieval agent through 4-10 concurrent reasoning sessions until it hits 98% confidence (scales dynamically based on device thermal state).
* **Maximum:** Removes the 8-session ceiling, granting the orchestrator an unlimited budget to recursively hunt down answers up to 50 loops.

**3 Foundation Model Routes**
* `3B Core`: Offline Apple Silicon model (Standard offline inference).
* `20B Advanced`: Offline Apple Silicon model leveraging unified memory and NAND Flash Paging.
* `Private Cloud Compute (PT-MoE)`: Escalates over encrypted channels to Apple's 32K context secure server enclaves, powered by a Parallel-Track Mixture-of-Experts architecture.

---

## 🗺️ Codebase Map

| Module | Core Files | Responsibility |
| :--- | :--- | :--- |
| **Ingestion** | `DocumentProcessor.swift`, `LayoutAwareExtractor.swift` | Document content extraction, Vision OCR fallback, semantic structure recovery. |
| **Chunking** | `SemanticChunker.swift`, `ContentTaggingService.swift` | Context-aware document chunking, entity resolution, NLP metadata enrichment. |
| **Indexing** | `SQLiteFullTextService.swift`, `BNNSVectorDatabase.swift` | Blazing-fast SQLite FTS5 lexical storage and local BNNS-accelerated vector indexing. |
| **Retrieval** | `HybridSearchService.swift`, `ContextPackingService.swift` | BM25 + Vector hybrid merging, parent-chunk reconstruction, exact token packing. |
| **Orchestration** | `LLMService.swift`, `RAGService.swift` | Execution coordination with the local `SystemLanguageModel` and evaluation loops. |
| **Shortcuts** | `RAGAppIntents.swift` | Siri integration and entity-native App Intents for OS-level query capabilities. |

---

## 🛠️ Placeholders & Scaffolding Warnings
To maintain codebase transparency, please note:
- **Core AI Integration:** Disabled via `#if false` directives in `CoreAISentenceEmbeddingProvider.swift`. The project currently runs on reliable local `CoreMLSentenceEmbeddingProvider` implementations until the OS 27 beta stabilizes.
- **Private Cloud Compute (PCC):** Routed locally using a fallback system language model wrapper in `EngineSDKCompatibility.swift` to ensure compilability on current public SDKs.

---

## 🚀 Build & Verification

**Requirements:**
* macOS Tahoe (26.x) with Xcode 26+
* iOS 26.0+ SDK target support
* Apple Silicon (M1+ / A17 Pro+) for adequate Neural Engine throughput

**Instructions:**
1. Clear macOS extended attributes to prevent codesign failure:
   ```bash
   /usr/bin/xattr -cr /Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence
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
