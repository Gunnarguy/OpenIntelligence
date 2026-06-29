# Docs/ROADMAP.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.3 on 2026-06-20.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes future technical directions for the prototype. It is not a product commitment.

---

## 1. Near Term

- **Clean up File Inventory:** Resolve the mismatch in `file_inventory_4.1.csv` by categorizing remaining files and documenting evidence notes.
- **Dynamic Candidate Cutoff Fix:** Modify the candidate pool formula in [RAGEngine.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift) to dynamically scale chunk pool sizes for small libraries rather than hardcoding a floor of 100 chunks.
- **Negation and Contradiction Sweeps:** Explore upgrading negation checks to include numeric fact comparisons and direct citation checks.

---

## 2. Retrieval & Answer Quality

- **OCR Post-processing:** Improve Vision OCR layout-aware text normalization and error correction.
- **Sibling Chunk Expansion:** Tune parent-chunk expansion ranges to optimize context packing.
- **MMR Diversity Tuning:** Experiment with different diversity thresholds ($\lambda$) to evaluate retrieval recall versus answer precision.

---

## 3. Platform Integration (Future Work)

- **Core AI Integration (Completed):** Fully integrated and enabled Silicon-native sentence embeddings under Apple's Core AI framework (`CoreAISentenceEmbeddingProvider.swift`) on iOS 27+ / macOS 27+, with Core ML fallback support.
- **Private Cloud Compute (PCC) (Completed):** Native Private Cloud Compute secure enclave execution is integrated for iOS 27 / macOS 27+, falling back to local SLM simulation on older OS releases.
- **Siri & AppIntents (Completed):** Registered shortcuts and app intents for libraries, documents, and conversation history (`ListEvidenceThreadsIntent` and `CreateNewEvidenceThreadIntent`).
