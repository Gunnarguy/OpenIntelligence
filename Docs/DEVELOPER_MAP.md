 # Master Developer Map & Directory — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Scope:** Master portal and quick-reference index linking all system architecture, pipeline, and codebase audit documents.

Welcome to the Master Directory for OpenIntelligence v4.1. This index serves as a navigation portal to help you quickly look up files, understand system rules, find answers to technical questions, or prepare responses for external reviews.

---

## 1. Quick Reference: "How Do I..." Selector

If you need to answer a specific question, locate a limit, or verify a system state, use this table to find the correct document:

| What are you looking for? | Document Link | Description / Focus |
| :--- | :--- | :--- |
| **What happens when a user asks a question?** | [16_OWNER_EXPLAINER_RAG_RELIABILITY_AND_RERANKING_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/16_OWNER_EXPLAINER_RAG_RELIABILITY_AND_RERANKING_4.1.md) | Plain-English explanation of vector similarity, RRF, reranking, and safety gates. |
| **How does the app decide to refuse/abstain?** | [14_RAG_RELIABILITY_DEEP_DIVE_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/14_RAG_RELIABILITY_DEEP_DIVE_4.1.md) | Code symbol traces for `shouldAbstain`, numeric sanity (Gate C), and semantic grounding (Gate E). |
| **How does the Core ML reranker fallback work?** | [15_RERANKING_AND_CROSS_ENCODER_REALITY_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/15_RERANKING_AND_CROSS_ENCODER_REALITY_4.1.md) | Deep dive into the TinyBERT model, tokenizers, candidate ceiling math, and fallback heuristics. |
| **What are the exact StoreKit billing limits?** | [BILLING_AND_LIMITS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/BILLING_AND_LIMITS.md) | Traces the paywall caps: Free (5 docs), Pro (1,000 docs), and Lifetime (unlimited). |
| **What are the local vs. PCC routing rules?** | [PRIVACY_AND_ROUTING.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/PRIVACY_AND_ROUTING.md) | Defines the local 4K token threshold and how secure PCC enclaves are simulated. |
| **What are the known limits of table parsing?** | [KNOWN_LIMITATIONS_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/KNOWN_LIMITATIONS_4.1.md) | Active lists of scaffolded/unimplemented paths like tabular data and iCloud sync. |
| **What is the proposal for reorganizing folders?** | [09_REORGANIZATION_PLAN_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/09_REORGANIZATION_PLAN_4.1.md) | Proposal to clean up the directory structure and isolate Dev/Diagnostics under `Developer/`. |
| **How do I run the automated quality benchmarks?** | [EVALS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/EVALS.md) | Instructions for triggering local JSONL quality runs and compiling recall metrics. |
| **Where are the safe public marketing copies?** | [PUBLIC_COPY_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/PUBLIC_COPY_4.1.md) | Factually corrected templates for the App Store, Product Hunt, and social platforms. |

---

## 2. Documentation Map (By Category)

All design files, process graphs, and ledger documents are sorted here by domain:

### Category A: The Codebase Audit Ledger
These documents prove the integrity of the codebase, tracking target membership, file status labels, and evidence notes:
* [01_AUDIT_CONTROL_LEDGER_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/01_AUDIT_CONTROL_LEDGER_4.1.md) — The master ledger and progress checklist of the 12 audit phases.
* [02_FILE_INVENTORY_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/02_FILE_INVENTORY_4.1.md) — The master inventory containing classification labels and evidence notes for all 468 git-tracked files.
* [03_TARGET_MEMBERSHIP_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/03_TARGET_MEMBERSHIP_4.1.md) — Mapped table separating files compiled in the App, Engine, and Widget extensions.
* [04_ENTRY_POINTS_AND_RUNTIME_MAP_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/04_ENTRY_POINTS_AND_RUNTIME_MAP_4.1.md) — Traces application launch, Tab view architecture, and RAG execution threads.
* [05_COMPONENT_REALITY_MAP_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/05_COMPONENT_REALITY_MAP_4.1.md) — Factual component audits evaluating code reality against marketing claims for 84+ system modules.
* [12_AUDIT_OF_AUDIT_COMPLETION_REPORT_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/12_AUDIT_OF_AUDIT_COMPLETION_REPORT_4.1.md) — Final validation verifying that all original audit gaps have been successfully resolved.
* [11_FINAL_AUDIT_SUMMARY_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/11_FINAL_AUDIT_SUMMARY_4.1.md) — An executive-level overview detailing shipped versus scaffolded code blocks and top risk mitigations.

### Category B: Pipeline & Architecture Blueprint
These blueprints map how files flow through the application during ingestion, indexing, and query execution:
* [ARCHITECTURE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/ARCHITECTURE.md) — High-level layout of SwiftUI views, Static Library services, and Live Activity targets.
* [INGESTION_PIPELINE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/INGESTION_PIPELINE.md) — Traces file parsing, page analysis, Vision OCR rendering, and haptic telemetry feedback.
* [RETRIEVAL_PIPELINE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/RETRIEVAL_PIPELINE.md) — Outlines the 29 steps in the RAG execution graph, from query input to final grounded answer output.

### Category C: Verification & Reranking Deep Dives
These deep dives provide detailed technical verification for on-device neural rerankers and grounding safety gates:
* [14_RAG_RELIABILITY_DEEP_DIVE_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/14_RAG_RELIABILITY_DEEP_DIVE_4.1.md) — Code-symbol details for the negation-based contradiction sweeps and the `shouldAbstain` refusal rules.
* [15_RERANKING_AND_CROSS_ENCODER_REALITY_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/15_RERANKING_AND_CROSS_ENCODER_REALITY_4.1.md) — Documents the TinyBERT model, vocabulary resources, dynamic concurrency bounds, and candidate truncation logic.
* [16_OWNER_EXPLAINER_RAG_RELIABILITY_AND_RERANKING_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/16_OWNER_EXPLAINER_RAG_RELIABILITY_AND_RERANKING_4.1.md) — A plain-English educational guide covering RAG, MMR, reciprocal rank fusion, and safety gates.

### Category D: Diagnostics, Benchmarks, & Automation
Tools and pipelines for developers to automate validation and testing:
* [EVALS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/EVALS.md) — Evaluates retrieval recall and grounding quality against strict target metrics.
* [AI_AGENT_MAP.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AI_AGENT_MAP.md) — Maps agent instructions, tools, and execution graphs.
* [10_BUILD_AND_VALIDATION_4.1.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/Docs/AUDIT/10_BUILD_AND_VALIDATION_4.1.md) — Logs test compile checks, link integrity scans, and automated grep sweep setups.

---

## 3. Directory Layout Overview

* **`OpenIntelligence/`** (Root application targets folder)
  * **`App/`** — SwiftUI life cycle and root view controllers (ContentView.swift, OpenIntelligenceApp.swift).
  * **`Core/`** — Shared data models (Document.swift, IngestionItem.swift).
  * **`Features/`** — User-facing SwiftUI screens (ChatScreen.swift, DocumentLibraryView.swift, OnboardingChecklistView.swift).
  * **`Services/`** — Core logic libraries (RAGService.swift, DocumentProcessor.swift, SQLiteFullTextService.swift).
  * **`UI/DesignSystem/`** — Color themes, spacing tokens, and Liquid Glass helper extensions.
  * **`Resources/`** — StoreKit tests, local Core ML models, and privacy plist configurations.
* **`OpenIntelligenceLiveActivities/`** (Widget Target folder)
  * Ingestion progress widget layouts and Dynamic Island compact views.
* **`scripts/`** (Automation tools)
  * Script helpers to run local evaluations (`run_rag_benchmarks.py`) and perform repository validations.
* **`Xrays/pipeline-xray/`** (Developer diagnostic overlays)
  * WebView-based overlay to inspect hybrid search scoring weights and RRF ranks.
