# OpenIntelligence Documentation Atlas & Index

This index organizes the repository's documentation by purpose, lifecycle state, and the code it maps to.

> **Reconciled 2026-08-28 against the shipped tree.** iOS 5.0 is live on the App Store (approved 2026-08-27) and macOS 5.0.2 is live (approved 2026-08-28). Nothing is in review; `v5.1` is open and unshipped. The platforms have diverged, so macOS carries fixes iOS has not received — `Docs/SHIPPED_VERSION.json` is the per-platform record. Previously reconciled 2026-08-05 against 4.9, and extended 2026-08-17 to list the seven dated audits that sit at the top level and were previously absent from this index. Two things were wrong before this pass and are worth naming, because both made this index actively misleading rather than merely stale. Every link was an absolute `file:///Users/...` path, so **every link in the public "Start here" document was broken for everyone except the repository owner**. And `ARCHITECTURE.md` was listed as an Active Reference while its own header marks it Superseded. Links are now relative, and lifecycle states match what each document says about itself.
>
> Lifecycle state describes the **document**, not the code. A document can be an Active Reference and still be verified at an older version; where that is true, the entry says which version, and the document's own header carries the detail.

---

## Category 1: Canonical System Architecture & Truth

The active source of truth for architecture, modules, and namespaces.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [CANONICAL_SOURCE_OF_TRUTH.md](CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md) | **Canonical Ground Truth** | Absolute reference for product definitions, sync limits, routing consent, and implementation rules. Outranks every other document here, including this index. |
| [OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md](OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md) | **Active Reference** — generated from the July 2026 audit, not regenerated since | Subsystem map, execution flows, system boundaries. Its component count predates the current tree; see its header. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | *Superseded* — historical, written at v4.1 | Kept for history. Superseded by the Atlas, and below that by the canonical document. Do not use as source of truth for any version. |
| [ROADMAP.md](ROADMAP.md) | *Mirror, header reconciled 2026-08-27* | **Notion is authoritative for the roadmap, not this file**, and it has been the stale side before. Body still predates v5.0 and is kept as record. Reach the database with the `notion-roadmap` skill. |
| [LIMITATIONS.md](LIMITATIONS.md) | **Active Reference** | Product, safety, and technical boundaries, including which quality modes have a measured accuracy baseline and which do not. |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | **Active Changelog** | Version release summaries and breaking dependency changes. |
| [USER_CHANGELOG.md](USER_CHANGELOG.md) | **Active Changelog** | User-facing updates in plain language. Current through v5.0.1. Mirrored into the app at `OpenIntelligence/Resources/VersionHistory.md`; `VersionHistoryTests` makes that copy a build input, so the two must not drift. |

---

## Category 2: RAG Pipeline Specifications

Step-by-step execution mechanics for ingestion and query retrieval.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [RETRIEVAL_PIPELINE.md](RETRIEVAL_PIPELINE.md) | **Active Specification** — source-verified at v4.6, tree is v5.0 | The query loop, reciprocal rank fusion, Lost-in-the-Middle context packing, and verification gates. Its header lists the 4.8–4.9 retrieval changes it does not yet describe. |
| [INGESTION_PIPELINE.md](INGESTION_PIPELINE.md) | **Active Specification** — source-verified at v4.6, tree is v5.0 | Vision OCR preprocessing, semantic chunking, subword validation, SQLite/BNNS storage. Header lists the 4.9 atomic-write changes not yet described. |
| [RAG_TECHNICAL.md](Engineering/RAG_TECHNICAL.md) | **Deep-Dive Specification** | Code examples, class interfaces, parameters, algorithms (MMR, TinyBERT cross-encoders). |
| [FULL_SYSTEM_TRACE.md](Engineering/FULL_SYSTEM_TRACE.md) | **Active Reference** — source-verified 2026-09-01 at `4840078` | **The execution trace**: launch, navigation, ingestion, a Standard query, the agentic modes, every hardware-unit request and the concurrency map, the iOS/macOS split, and a claims audit of the two earlier walkthroughs. Read this for *which unit runs what and how the code decides*. |
| [STUDY_GUIDE.md](STUDY_GUIDE.md) | **Active Reference** — written 2026-09-02 at `273b007` | **The course.** Seventeen modules in pipeline order: what each part is, why it exists, where it runs, its share of the 612-concept word bank, corrections, an explain-it checklist and a quiz. Sources: the Terra word bank and Opus walkthrough under `Research/`, numbers from `Engineering/FULL_SYSTEM_TRACE.md`. |
| [STORAGE_AND_PIPELINE_TRACE.md](Engineering/STORAGE_AND_PIPELINE_TRACE.md) | *Historical Reference* | Prototype data flows, relational schema, legacy iCloud Drive sync boundaries. |

---

## Category 3: Platform Routing, Security, & Monetization

StoreKit boundaries, private routing enclaves, and local capability checks.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [PRIVACY_AND_ROUTING.md](PRIVACY_AND_ROUTING.md) | **Active Reference** — source-verified at v4.6 | Routing boundaries (`FoundationModelRoutePolicy.swift`) and local vs. Private Cloud Compute escalation. Header notes the routing-picker defect fixed 2026-07-30. |
| [BILLING_AND_LIMITS.md](BILLING_AND_LIMITS.md) | **Active Reference** — product IDs re-checked 2026-08-05 | StoreKit 2 product registry, quota policies (`QuotaPolicy.swift`), legacy subscription protections. Notes the discontinued Document Pack. |
| [PRIVATE_CLOUD_COMPUTE.md](Engineering/PRIVATE_CLOUD_COMPUTE.md) | **Active Reference** | Security properties, stateless enclaves, and verification tooling for Apple's PCC architecture. |
| [APPLE_MODELS.md](Engineering/APPLE_MODELS.md) | **Active Reference** | Foundation Models framework details (`LanguageModelSession`), prompt compilation, token budgets. |
| [HARD_LIMITS.md](Engineering/HARD_LIMITS.md) | **Active Reference** — partially re-verified 2026-08-05 | **Token boundaries and the public-claim constraints they create**, plus measured device throughput. Read this before writing any performance or capability claim. |

---

## Category 4: Academic & Engineering Research

Research grounding the implementation.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [RESEARCH_PAPERS_REFERENCE_SHEET.md](Research/RESEARCH_PAPERS_REFERENCE_SHEET.md) | **Active Reference** | Academic map: RAPTOR trees, SBERT, UMAP/t-SNE, Porter stemming, guided decoding. |
| [AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md](Research/AUDIO_STUDY_GUIDE_V2_TERRA_2026-08-27.md) | *Source material* — generated by GPT-5.6 Terra 2026-08-27, not source-verified here | The 612-concept controlled word bank with status labels and code anchors; all 153 cited paths exist. Its corrections are listed in `STUDY_GUIDE.md` and `Engineering/FULL_SYSTEM_TRACE.md` §9. The `_TTS_PACK` zip beside it splits the same text for text-to-speech. |
| [HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt](Research/HOW_OPENINTELLIGENCE_WORKS_OPUS_2026-08-22.txt) | *Source material* — plain-text export of the Claude Opus 5 walkthrough artifact, republished 2026-08-22 | The reasons behind each part, written for a walkthrough. One claim is wrong (audio transcription); see `Engineering/FULL_SYSTEM_TRACE.md` §9.1. |
| [RAG_AND_RETRIEVAL_2024_2026.md](Research/RAG_AND_RETRIEVAL_2024_2026.md) | **Active Reference** | Retrieval literature underpinning the upgrade plan. |
| [EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md](Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md) | **Active Research** | The survey behind the post-4.9 retrieval arc. Paired with the engineering plan in Category 5. |
| [APPLE_DOCUMENT_INTELLIGENCE.md](Engineering/APPLE_DOCUMENT_INTELLIGENCE.md) | **Active Reference** | Document layout analysis, OCR confidence, column extraction. |
| [APPLE_FM_TECH_REPORT_2025.md](Engineering/APPLE_FM_TECH_REPORT_2025.md) | **Active Reference** | Apple's pre-trained SLM specs: quantization schedules, palettization. |
| [COREML_METAL_ON_DEVICE_AI.md](Research/COREML_METAL_ON_DEVICE_AI.md) | **Active Reference** | Core ML loading parameters, `MLComputeUnits` selection, Metal performance shaders. |
| [DOCUMENT_INTELLIGENCE_AND_OCR.md](Research/DOCUMENT_INTELLIGENCE_AND_OCR.md) | **Active Reference** | `RecognizeDocumentsRequest` vs. `VNRecognizeTextRequest` configuration. |
| [APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md](Research/APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md) | **Active Reference** | Foundation Models capabilities and constraints. |
| [CAG_AND_CONTEXT_ENGINEERING_2024_2026.md](Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md) | **Active Reference** | Cache-augmented generation and context engineering literature. |

---

## Category 5: Planning, CI, & Evaluations

Measuring and verifying outputs, and the plan for what comes next.

**Two machine-read markers live here and are load-bearing.** Both are consumed by CI
and by the three public websites, and both exist because a claim drifted from reality
and nothing caught it. Update the marker before the copy, never after.

| Marker | What it answers | Read by |
| :--- | :--- | :--- |
| [SHIPPED_VERSION.json](SHIPPED_VERSION.json) | What is live on the App Store, as opposed to what is being prepared. `CHANGELOG.md`'s first heading is the release being *built*, which is not the same thing. | gunzino.me, the portfolio and Fascinaiting, each on a daily cron. Written after this site advertised 5.0 while 4.9 was the newest anyone could install. |
| [SHIPPED_CAPABILITIES.json](SHIPPED_CAPABILITIES.json) | Which advertised capabilities actually exist in a shipping build. PCC is `built_not_enabled` and must be written in the future tense everywhere. | `scripts/verify_capabilities.py`, in CI. Written after 19 places across three sites described PCC as live. |

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [RETRIEVAL_UPGRADE_PLAN_2026-08.md](Engineering/RETRIEVAL_UPGRADE_PLAN_2026-08.md) | **Active Plan** — plan only, nothing implemented | The sequenced post-4.9 retrieval and ingestion work. Item 2A (benchmark harness) comes first because everything else is unfalsifiable without it. |
| [EVALS.md](EVALS.md) | **Active Reference** — verified at v4.4 | Quality gate targets, `.jsonl` dataset examples, CI test execution. Its header explains why no Deep Think or Maximum score is currently valid. |

> A previous version of this index listed an `EVALS_ATLAS.md` entry that pointed at `EVALS.md`, the same file as the row above it. There is no separate atlas; the duplicate has been removed.

---

## Category 6: Developer Agent Playbooks

Operating protocol for any agent or engineer modifying the codebase.

| Document | Lifecycle State | Purpose & Code Subsystems |
| :--- | :--- | :--- |
| [SUPERSEDING_EVIDENCE_PROTOCOL.md](AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md) | **Active Directive** | Resolving architectural contradictions and scoring codebase claims. Evidence tagging is mandatory. |
| [TASK_ROUTER_AND_CHANGE_CONTROL.md](AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md) | **Active Directive** | Coordinating file changes, task allocation, and roadmap updates. |
| [PHASE_1A_IMPLEMENTATION_PLAN.md](AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md) | **Active Directive** | Evidence threads implementation tasks. |
| [RepoOS Command Center](RepoOS/00_REPO_COMMAND_CENTER.md) | **Active Directive** | One-page entry point: canonical read order, edit boundaries, required tests. |

---

## Category 7: Audit & Governance Artifacts

Inventories and maps compiled during audit checkpoints. Per the RepoOS Command Center, treat `FULL_REPO_*` and `PRODUCT_POSITIONING_*` as dated snapshots, not source of truth.

| Document | Path | Purpose |
| :--- | :--- | :--- |
| Phase Ledger | [PHASE_LEDGER.md](AuditArtifacts/ArchitectureAtlas/PHASE_LEDGER.md) | Completion status of repository audits (Phases 0–10). |
| Component Inventory | [component_inventory.csv](AuditArtifacts/ArchitectureAtlas/component_inventory.csv) | Swift components, method hashes, database triggers, metrics. |
| Subsystem Map | [subsystem_map.md](AuditArtifacts/ArchitectureAtlas/subsystem_map.md) | Subsystem divisions mapping features back to files. |
| Verification Matrix | [document_claim_matrix.csv](AuditArtifacts/Verification/document_claim_matrix.csv) | Maps public claims to codebase logic, to prevent false claims. |

### Dated snapshots that still sit at the top level

These seven live in `Docs/` rather than `AuditArtifacts/` and were previously unlisted here, which is
the worst combination: they sit beside the canonical documents, look authoritative, and describe a
tree that has moved. **They are point-in-time records of what was believed on a date. None is a
source of truth.**

They are deliberately **not** relocated. A move was scoped on 2026-08-17 and rejected: the seven
carry **48 inbound references** between them, `PCC_Dynamic_Routing_Audit_Spec.md` is cited from
`CHANGELOG.md` which is history and must not be rewritten, and one of them is load-bearing for the
live routing system. Listing them here costs nothing and breaks nothing; moving them breaks the
RepoOS.

| Document | Lifecycle State | Note |
| :--- | :--- | :--- |
| [DOCUMENTATION_CONSISTENCY_AUDIT.md](DOCUMENTATION_CONSISTENCY_AUDIT.md) | **Active Directive, not a snapshot** | The exception. Referenced by 20 files including `RepoOS/01_TASK_ROUTER.md`, `02_AGENT_PROMPT_COMPILER.md`, `03_FORBIDDEN_EDIT_BOUNDARIES.md`, `04_RELEASE_READINESS_DASHBOARD.md` and the Atlas. Live governance depends on it. Do not move or delete. |
| [FULL_REPO_LINE_BY_LINE_AUDIT.md](FULL_REPO_LINE_BY_LINE_AUDIT.md) | *Dated snapshot* | Referenced only from within `AuditArtifacts/` phase documents. |
| [FULL_REPO_EVIDENCE_THREADS_ARCHITECTURE_AUDIT.md](FULL_REPO_EVIDENCE_THREADS_ARCHITECTURE_AUDIT.md) | *Dated snapshot* | Paired with its verification document below. |
| [FULL_REPO_EVIDENCE_THREADS_AUDIT_VERIFICATION.md](FULL_REPO_EVIDENCE_THREADS_AUDIT_VERIFICATION.md) | *Dated snapshot* | Verifies the document above. |
| [PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT.md](PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT.md) | *Dated snapshot, superseded by V2* | Read V2 instead. |
| [PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT_V2.md](PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT_V2.md) | *Dated snapshot* | Positioning as understood at the time of writing. |
| [PCC_Dynamic_Routing_Audit_Spec.md](PCC_Dynamic_Routing_Audit_Spec.md) | *Dated spec* | Cited from `CHANGELOG.md`. |

**Why dated audits are kept rather than deleted.** They record what was believed and when, which is
load-bearing more often than it looks. On 2026-08-17 the note in
`AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md:196`, which said the "40%+ faster"
Settings claims were *flagged rather than asserted* and to run `oi-claim-audit` before touching them,
is what allowed those claims to be resolved correctly instead of guessed at. Deleting an audit
destroys the reasoning as well as the conclusion.
