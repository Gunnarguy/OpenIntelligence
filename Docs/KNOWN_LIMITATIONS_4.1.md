# Docs/KNOWN_LIMITATIONS_4.1.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.

This document identifies known technical limitations, placeholders, architectural stubs, and RAG execution constraints in OpenIntelligence v4.1.

---

## 1. Architectural Scaffolding & Stubs

### Core AI Integration
- **Status:** Scaffolded / Placeholder.
- **Details:** The embedding provider [CoreAISentenceEmbeddingProvider.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift) is disabled behind a `#if false` preprocessor directive. The system does not utilize system-native Apple Core AI embeddings at compile time; instead, it compiles with a local `CoreMLSentenceEmbeddingProvider`.

### Private Cloud Compute (PCC) Execution
- **Status:** Mocked.
- **Details:** Remote Private Cloud Compute enclave execution is simulated locally using the system language model compatibility layer [EngineSDKCompatibility.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Core/Support/EngineSDKCompatibility.swift). No remote attestation, enclave packaging, or secure iCloud network routing is implemented.

---

## 2. RAG Pipeline & Retrieval Constraints

### Candidate-Pool Cutoff Bug
- **Status:** Known Logic Issue.
- **Details:** In [RAGEngine.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift), the formula to compute the reranking candidate pool size is:
  `min(chunks.count, max(100, min(250, topK * 5)))`
  If a user has a small document library (e.g., total chunk count is 25, with `topK = 5`), the inner `max(100, ...)` evaluates to `100`, and the outer `min(chunks.count, 100)` evaluates to `25`. However, for target-library sizes between 100 and 200 chunks, this formula sets a floor of 100 chunks. This means chunks may be unnecessarily clipped before reaching the reranker when `topK < 20`, contradicting comments claiming small corpora retain all chunks.

### Contradiction Sweeps Limitations
- **Status:** Non-Critical.
- **Details:** The contradiction detection in [VerificationGateService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift) is implemented as a simple lexical negation search and word-overlap check. It does not perform formal logical proofs or compare numeric facts. Additionally, detecting a contradiction does *not* force the RAG engine to abstain; it merely reduces the overall answer confidence score, allowing the answer to still display if the final score remains above the threshold.

---

## 3. Platform & Hardware Dependencies

### Neural Engine (ANE) Scheduling
- **Status:** Non-guaranteed.
- **Details:** The Core ML models are loaded using `computeUnits = .all`. While this enables Apple Neural Engine (ANE) execution on supported hardware, macOS and iOS decide thread scheduling dynamically. I make no guarantees of exclusive ANE execution, lower thermal throttling, or specific battery-consumption improvements.

### Memory & Concurrency Bounds
- **Status:** Non-adaptive.
- **Details:** Concurrency limits for chunking and embedding generation are configured as static maximum values. The system does not adapt execution threads dynamically to changes in available device memory or temperature limits, which may cause latency spikes on lower-end devices during large document imports.
