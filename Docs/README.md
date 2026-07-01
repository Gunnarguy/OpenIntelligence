# OpenIntelligence Documentation Atlas & Index

Welcome to the Documentation Atlas for **OpenIntelligence**. This index organizes the codebase’s extensive documentation files into distinct categories based on their purpose, lifecycle state, and technical mappings.

---

## Category 1: Canonical System Architecture & Truth
These files represent the active, verified source of truth for the codebase architecture, modules, and namespaces.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [CANONICAL_SOURCE_OF_TRUTH.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md) | **Canonical Ground Truth** | Absolute reference file for product definitions, sync limits, routing consent, and implementation rules. |
| [ARCHITECTURE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/ARCHITECTURE.md) | **Active Reference** | Codebase directory structure overview, Swift target dependencies, and end-to-end data-flow outlines. |
| [ROADMAP.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/ROADMAP.md) | **Active Roadmap** | Current near-term, retrieval, and platform integration milestones (StoreKit 2 configurations, Core AI enclaves). |
| [LIMITATIONS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/LIMITATIONS.md) | **Active Reference** | Technical constraints (context ceilings, hardware limitations, offline bounds). |
| [RELEASE_NOTES.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/RELEASE_NOTES.md) | **Active Changelog** | Version release summaries, feature updates, and breaking dependency changes. |
| [USER_CHANGELOG.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/USER_CHANGELOG.md) | **Active Changelog** | High-level user-facing updates and user experience improvements. |

---

## Category 2: RAG Pipeline Specifications
Deep-dives into the step-by-step execution mechanics of document ingestion and semantic query retrieval.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [RETRIEVAL_PIPELINE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/RETRIEVAL_PIPELINE.md) | **Active Specification** | The 23-step query loop, reciprocal rank fusion (RRF) logic, Lost-in-the-Middle context packing, and verification gates. |
| [INGESTION_PIPELINE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/INGESTION_PIPELINE.md) | **Active Specification** | The 6-step ingestion lane: Vision OCR preprocessing, semantic chunking, subword validation, and SQLite/BNNS storage. |
| [RAG_TECHNICAL.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/RAG_TECHNICAL.md) | **Deep-Dive Specification** | Code examples, class interfaces, parameters, and algorithms (MMR, TinyBERT cross-encoders). |
| [STORAGE_AND_PIPELINE_TRACE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md) | *Historical Reference* | Prototype data flows, relational schema details, and legacy iCloud Drive syncing boundaries. |

---

## Category 3: Platform Routing, Security, & Monetization
Details regarding StoreKit billing boundaries, private routing enclaves, Apple Intelligence SSU integration, and local capability checks.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [PRIVACY_AND_ROUTING.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/PRIVACY_AND_ROUTING.md) | **Active Reference** | Details dynamic routing boundaries (`FoundationModelRoutePolicy.swift`) and local vs. Private Cloud Compute (PCC) escalations. |
| [BILLING_AND_LIMITS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/BILLING_AND_LIMITS.md) | **Active Reference** | StoreKit 2 product ID registry, quota policies (`QuotaPolicy.swift`), and legacy subscription protections. |
| [PRIVATE_CLOUD_COMPUTE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md) | **Active Reference** | Details the security properties, stateless enclaves, and verification tools of Apple's secure PCC architecture. |
| [APPLE_MODELS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/APPLE_MODELS.md) | **Active Reference** | Apple Foundation Models framework details (`LanguageModelSession`), prompt compilation configs, and token budgets. |
| [HARD_LIMITS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/HARD_LIMITS.md) | **Active Reference** | Absolute hardware floor allocations (RAM consumption thresholds, Neural Engine utilization ceilings). |

---

## Category 4: Academic & Engineering Research
Foundational research sheets, academic papers, and Apple developer technotes that ground the application's implementation math.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [RESEARCH_PAPERS_REFERENCE_SHEET.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Research/RESEARCH_PAPERS_REFERENCE_SHEET.md) | **Active Reference** | Exhaustive 25-pillar academic map (COMPILOT auto-scheduling, RAPTOR trees, SBERT, UMAP/t-SNE, Porter stemming, guided decoding). |
| [APPLE_DOCUMENT_INTELLIGENCE.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md) | **Active Reference** | Apple Machine Learning Research findings on document layout analysis, OCR confidence, and column extraction profiles. |
| [APPLE_FM_TECH_REPORT_2025.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Engineering/APPLE_FM_TECH_REPORT_2025.md) | **Active Reference** | Tech specs of Apple's pre-trained SLMs (quantization schedules, palettization optimizations). |
| [COREML_METAL_ON_DEVICE_AI.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Research/COREML_METAL_ON_DEVICE_AI.md) | **Active Reference** | Core ML model loading parameters, compute device select rules (`MLComputeUnits`), and Metal performance shaders (MPS). |
| [DOCUMENT_INTELLIGENCE_AND_OCR.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/Research/DOCUMENT_INTELLIGENCE_AND_OCR.md) | **Active Reference** | Structured Vision requests configurations (`RecognizeDocumentsRequest` vs. `VNRecognizeTextRequest`). |

---

## Category 5: Continuous Integration & Evaluations
Framework outlines for measuring and verifying system outputs against target precision parameters.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [EVALS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/EVALS.md) | **Active Reference** | Quality gate targets (Recall@5, Precision bounds), `.jsonl` dataset examples, and CI/CD CLI test executions. |
| [EVALS_ATLAS.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/EVALS.md) | *Historical Reference* | Legacy evaluations roadmap and early target configurations. |

---

## Category 6: Developer Agent Playbooks
Rules and operating protocols for any AI agent or software engineer modifying the codebase.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [SUPERSEDING_EVIDENCE_PROTOCOL.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md) | **Active Directive** | Absolute requirement protocol for resolving architectural contradictions and scoring codebase claims. |
| [TASK_ROUTER_AND_CHANGE_CONTROL.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md) | **Active Directive** | Guide for coordinating file changes, task allocations, and roadmap updates. |
| [PHASE_1A_IMPLEMENTATION_PLAN.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md) | **Active Directive** | Roadmap for performing initial evidence threads implementation tasks. |

---

## Category 7: Audit & Governance Artifacts
The massive inventory database and recovered maps compiled during core audit checkpoints.

| Document | Path | Purpose |
| :--- | :--- | :--- |
| Phase Ledger | [PHASE_LEDGER.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/PHASE_LEDGER.md) | Tracks the completion status of all repository audits (Phases 0–10). |
| Component Inventory | [component_inventory.csv](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/component_inventory.csv) | Full database tracking Swift components, method hashes, database triggers, and metrics. |
| Subsystem Map | [subsystem_map.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/subsystem_map.md) | High-level subsystem divisions mapping features back to files. |
| Verification Matrix | [document_claim_matrix.csv](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/Verification/document_claim_matrix.csv) | Full matrix mapping marketing claims to physical codebase logic to prevent false claims. |
