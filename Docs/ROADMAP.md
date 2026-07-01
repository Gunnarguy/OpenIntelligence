# Docs/ROADMAP.md — OpenIntelligence v4.4 (working on v4.5)

> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes future technical directions for the prototype. It is not a product commitment.

---

## 1. Near Term

- **Rust-Backed Tokenizer Migration (Completed):** Migrated the local on-device tokenizer from legacy pure-Swift `BertTokenizer` to high-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) package loaded asynchronously from the local resource bundle, yielding a 100x speedup and exact byte-level character offsets. Excluded `tokenizer.json` files from Xcode's synchronized root group via `project.pbxproj` exception sets to prevent app-level copy conflicts.
- **Ingestion Performance & Checkpointing (Completed):** Bypassed PNG encoding by feeding GPU-rendered `CGImage` buffers directly to Vision OCR/Structure requests. Introduced a local page-level JSON checkpointing cache to protect long document ingestions from OOM and app-restart data loss. Fixed FTS5 index truncation and page offset mapping errors during streaming batch ingestion, ensuring fully searchable large documents. Resolved a race condition where `WorkspaceSyncService` deleted active streaming ingest documents before metadata registration. Exposed and stabilized the Core AI sentence embedding provider option on iOS 27 through shared-instance caching, an awaitable readiness gate, and clean compile-time/runtime picker alerts.
- **watchOS Live Activities Layout (Completed):** Customized the lock screen widget view with conditional rendering for watchOS Smart Stack `.small` widget family, detailing a circular gauge and compact status labels.
- **PCC Fallbacks & UI Diagnostics (v4.5.0 Completed):** Restored and fixed the iCloud/PCC settings sheet views on iOS 27, ensuring robust `self.settings` scope lookup within SwiftUI sheet extensions to prevent routing crashes. Integrated an **AI Subsystem Diagnostics** card to the Library Deep Dive settings, giving full 'x-ray vision' over the active embedding model framework, ANE hardware target, readiness gate state, Rust-backed tokenizer parser, vocabulary details, byte-level citation offsets, and latency profiles. Fixed a rare sync-sweep race condition where background cleanups deleted recently uploaded files by touching their modification dates upon copy.
- **Dynamic Candidate Cutoff Fix:** Modify the candidate pool formula in [RAGEngine.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift) to dynamically scale chunk pool sizes for small libraries rather than hardcoding a floor of 100 chunks.
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
- **Private Cloud Compute (PCC) (Completed):** Native Private Cloud Compute secure enclave execution is integrated for iOS 27 / macOS 27+, falling back to local SLM simulation on older OS releases. Added a runtime `EntitlementChecker` signature scan on iOS 27 / macOS 27+ to verify the `com.apple.developer.private-cloud-compute` entitlement and fallback to on-device models to prevent fatal crashes if the entitlement is missing.
- **Siri & AppIntents (Completed):** Registered shortcuts and app intents for libraries, documents, and conversation history (`ListEvidenceThreadsIntent` and `CreateNewEvidenceThreadIntent`).
