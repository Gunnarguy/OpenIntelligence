# Docs/APP_REALITY_4.1.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.

---

## 1. Executive Summary
This document defines the absolute technical and user-facing reality of OpenIntelligence v4.1. I compiled this report from a file-by-file audit of the repository. It serves as the single source of truth for the shipped app, separating user-reachable features from developer tooling, internal systems, and disabled future scaffolding.

---

## 2. Technical Classification Map

### Shipped & User-Facing
- **Core Chat UI:** Multi-turn chat interfaces with cited answer bubbles and unified system metrics, defined in [SurfaceCard.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/UI/DesignSystem/SurfaceCard.swift) and [IngestionQueueOverlay.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/UI/Components/IngestionQueueOverlay.swift).
- **Document Library:** User document import, cataloging, and metadata tracking.
- **StoreKit 2 Purchase Flow:** StoreKit integration supporting Free, Pro, and Lifetime tiers, located in [StoreKitTestHarness.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Resources/StoreKit/StoreKitTestHarness.swift) and configured via [StoreKitConfiguration.storekit](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit).
- **Settings HUD:** System model settings, telemetry bars, and PCC consent prompts.

### Shipped & Internal
- **Hybrid Search Engine:** Combines vector embeddings and BM25 lexical searches via SQLite FTS, located in [SQLiteFullTextService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Storage/SQLiteFullTextService.swift).
- **Core ML Reranking (Fallback):** The cross-encoder reranking function in [RAGEngine.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift) runs with CPU/GPU/ANE compute units. When the Core ML model is missing from the bundle, the system automatically falls back to heuristic scoring.
- **Verification Gates & Abstention:** RAG output evaluation using lexical negation filters and word-overlap checks to calibrate answer confidence, located in [VerificationGateService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift).

### Developer-Only / Debug
- **Pipeline Xray Diagnostic:** A local HTML/JS interface under [Xrays/pipeline-xray/index.html](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Xrays/pipeline-xray/index.html) used to visualize token compression and retrieval traces.
- **RAG Evaluation Suite:** Automated RAG benchmark execution scripts under [scripts/run_rag_benchmarks.py](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/scripts/run_rag_benchmarks.py) and test fixtures.

### Scaffolded / Placeholders (Future Work)
- **Core AI Integration:** The files [CoreAISentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift) and related systems are completely disabled via `#if false` compiler flags and return empty mock stubs.
- **Private Cloud Compute (PCC) Remote Execution:** PCC routes are simulated using a local system language model compatibility wrapper in [EngineSDKCompatibility.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Core/Support/EngineSDKCompatibility.swift). Remote PCC enclave execution is not compiled in or active.

---

## 3. RAG Pipeline Reality

### 1. Ingestion
- **Formats:** Processes clean PDFs and text documents.
- **OCR:** Leverages the Vision framework for OCR, normalizes OCR output text, and caches extraction logs.
- **Chunking:** Semantic and structure-aware chunking enforce strict token boundaries before vectorizing.

### 2. Retrieval & Reranking
- **First-Pass Search:** Runs parallel vector searches (using local model weights) and full-text lexical queries, merging results with Reciprocal Rank Fusion (RRF).
- **Reranking Pool & Formula:** Retrieves candidate chunks up to a limit determined by:
  `min(chunks.count, max(100, min(250, topK * 5)))`
  *Caveat:* For small document libraries where `chunks.count < 100`, this formula caps the pool size unnecessarily.
- **Reranker Execution:** Uses a local Core ML model (`ReRankerModel.mlpackage`). If the model resource is absent, it bypasses the neural cross-encoder and falls back to a term-proximity/boost heuristic score.

### 3. Verification & Refusal (Abstention)
- **Verification Gates:** Chunks pass through multiple calibration checks.
- **Contradiction Sweep:** Performs a lexical negation scan and word-overlap analysis. It does *not* execute formal mathematical checks.
- **Abstention Path:** If confidence falls below a configured threshold, the RAG engine flags `shouldAbstain = true` and displays a structured refusal in the UI, avoiding hallucinations.

---

## 4. Billing & Quota Rules
Limits are hardcoded and enforced in the following tiers:
- **Free:** Enforces a limit of 5 documents in the active library.
- **Pro:** Enforces a limit of 1,000 documents.
- **Lifetime:** Unlimited document ingestion.
Enforcement is performed locally by querying StoreKit transaction statuses.

---

## 5. Source Evidence Index
- **Verification Gate Logic:** [VerificationGateService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift)
- **RAG Engine Orchestration:** [RAGEngine.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift)
- **StoreKit Configurations:** [StoreKitConfiguration.storekit](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit)
- **Local LLM Compatibility Wrappers:** [EngineSDKCompatibility.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Core/Support/EngineSDKCompatibility.swift)
- **FTS Query Storage:** [SQLiteFullTextService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Storage/SQLiteFullTextService.swift)
- **Disabled Core AI backend:** [CoreAISentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift)
