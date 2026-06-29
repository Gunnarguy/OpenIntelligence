# Docs/ROADMAP.md — OpenIntelligence v4.4

> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-28.
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

## 3. Platform Integration & Monetization (v4.4 Completed)

- **Pro Annual Subscription Pricing:** Calibrated Pro Annual pricing to $29.99/year (a 58% savings vs monthly) and integrated a 7-day free trial introductory offer.
- **Discontinued Document Pack:** Removed the consumable Document Pack add-on UI views, quick-refill cards, and local StoreKit configuration.
- **Frictionless App Store Review Prompts:** Integrated direct native `requestReview()` prompt calls during successful RAG sessions and Thumbs-Up events to maximize rating conversions in compliance with App Store Guideline 5.6.
- **Core AI Integration (Completed):** Fully integrated and enabled Silicon-native sentence embeddings under Apple's Core AI framework (`CoreAISentenceEmbeddingProvider.swift`) on iOS 27+ / macOS 27+, with Core ML fallback support.
- **Private Cloud Compute (PCC) (Completed):** Native Private Cloud Compute secure enclave execution is integrated for iOS 27 / macOS 27+, falling back to local SLM simulation on older OS releases.
- **Siri & AppIntents (Completed):** Registered shortcuts and app intents for libraries, documents, and conversation history (`ListEvidenceThreadsIntent` and `CreateNewEvidenceThreadIntent`).
