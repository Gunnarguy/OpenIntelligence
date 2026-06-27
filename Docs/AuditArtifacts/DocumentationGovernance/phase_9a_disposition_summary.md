# Phase 9A Document Disposition Summary

This document summarizes the results of the Phase 9A Documentation Disposition audit. All documentation and playbook files in the repository have been inspected and classified without modifying any active codebase documentation.

## Executive Metrics
- **Total files inspected**: 37
- **KEEP**: 24
- **UPDATE**: 10
- **MERGE**: 1
- **SUPERSEDE**: 1
- **ARCHIVE**: 5
- **DELETE-CANDIDATE**: 0

---

## Detailed Classification Matrix

### 1. KEEP
These files are technically accurate, up-to-date, or represent critical process parameters and frameworks that require no modification:
- `AGENTS.md` (Active universal agent instructions)
- `GEMINI.md` (Active Gemini IDE environment parameters)
- `THIRD_PARTY_NOTICES.md` (Standard factual third-party licensing)
- `WHATS_NEW.md` (User-facing release logs, avoids pronouns)
- `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` (Phase 8 active master source of truth)
- `Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md` (Phase 8 consistency matrix)
- `Docs/EVALS.md` (Factual evaluation pipeline configurations and JSONL structures)
- `Docs/LIMITATIONS.md` (Product disclaimers and safety limits, verified up-to-date)
- `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` (Phase 8 active canonical architecture atlas)
- `Docs/USER_CHANGELOG.md` (Clean factual changelog)
- `Docs/DEMO.md` ( walkthrough outlines, already marked as historical reference)
- `Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md` (Factual engineering reference on Apple platform APIs)
- `Docs/Engineering/APPLE_FM_TECH_REPORT_2025.md` (Factual engineering reference on Apple Intelligence architecture)
- `Docs/Engineering/APPLE_MODELS.md` (Factual Silicon model architecture notes)
- `Docs/Engineering/HARD_LIMITS.md` (Factual framework parameter and constraint indexes)
- `Docs/Research/APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md` (Platform research notes)
- `Docs/Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md` (CAG vs RAG engineering notes)
- `Docs/Research/COREML_METAL_ON_DEVICE_AI.md` (Metal execution research notes)
- `Docs/Research/DOCUMENT_INTELLIGENCE_AND_OCR.md` (Vision OCR research notes)
- `Docs/Research/RAG_AND_RETRIEVAL_2024_2026.md` (Hybrid retrieval research notes)
- `Docs/Research/README.md` (Research directory index)
- `Docs/AgentPlaybooks/README.md` (Active playbook index)
- `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` (Active master evidence protocol)
- `Docs/AgentPlaybooks/01_PHASED_ARCHITECTURE_ATLAS.md` (Active phase workflow guidelines)
- `Docs/AgentPlaybooks/02_DOCUMENTATION_RECONCILIATION.md` (Active reconciliation workflow guidelines)
- `Docs/AgentPlaybooks/03_CHANGE_IMPACT_DOC_UPDATE.md` (Active post-merge workflow guidelines)
- `Docs/AgentPlaybooks/04_PR_GOVERNANCE_REVIEW.md` (Active pre-merge checklists)
- `Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md` (Active implementation constraint guidelines)
- `Docs/AgentPlaybooks/architecture-atlas-update.md` (Short atlas playbook)
- `Docs/AgentPlaybooks/change-impact-docs-update.md` (Short impact playbook)
- `Docs/AgentPlaybooks/documentation-reconciliation.md` (Short reconciliation playbook)
- `Docs/AgentPlaybooks/pr-review-docs-gate.md` (Short gate playbook)

### 2. UPDATE
These files contain style violations (e.g. first-person pronouns 'I/we/our') or outdated technical claims (e.g. CloudKit sync, Keychain billing limits, active remote PCC secure enclaves) that must be resolved in Phase 9B:
- `README.md` (Update setup guides and references to new canonical docs)
- `CHANGELOG.md` (Remove style violation CON15 "Shoutout to Tim...")
- `HOW_IT_WORKS.md` (Align with shared SQLite database and WorkspaceSyncService realities)
- `PRIVACY.md` (Clarify PCC local simulation and local application support persistence)
- `Docs/AppleIntelligenceTransitionPlan.md` (Label clearly as planning/experimental document, verify Core AI embeddings are currently disabled)
- `Docs/BILLING_AND_LIMITS.md` (Fix style violations CON12/CON13, update Keychain limits to UserDefaults)
- `Docs/INGESTION_PIPELINE.md` (Fix style violation CON14, document page complexity Vision OCR fallbacks)
- `Docs/PRIVACY_AND_ROUTING.md` (Fix style violations CON04/CON08, document local compatibility simulation wrappers)
- `Docs/RELEASE_NOTES.md` (Update release details to indicate standard on-device inference without Core AI embeddings)
- `Docs/RETRIEVAL_PIPELINE.md` (Remove pronouns CON09/CON10/CON11, update BM25 hybrid indexing)
- `Docs/ROADMAP.md` (Update development milestones to match current phase ledger)
- `Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md` (Add warning notice that remote PCC is currently simulated locally)

### 3. MERGE
These files contain detailed technical specifications that should be absorbed into a single canonical source of truth:
- `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md` (SQLite schema tables and BNNS vector persistence traces to be merged into `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`)

### 4. SUPERSEDE
These files are obsolete and have been fully replaced by newer, evidence-verified canonical control documents:
- `Docs/ARCHITECTURE.md` (Replaced by `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` and `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`)

### 5. ARCHIVE
These files are historical records of previous audit steps, planning phases, or static verification outputs. They will be marked as historical evidence in the disposition matrix without moving the files:
- `Docs/FULL_REPO_EVIDENCE_THREADS_ARCHITECTURE_AUDIT.md` (Feasibility audit records)
- `Docs/FULL_REPO_EVIDENCE_THREADS_AUDIT_VERIFICATION.md` (Verification checklist output records)
- `Docs/FULL_REPO_LINE_BY_LINE_AUDIT.md` (Line-by-line static analysis records)
- `Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT.md` (Initial product strategy records)
- `Docs/PRODUCT_POSITIONING_AND_EVIDENCE_THREADS_AUDIT_V2.md` (Updated MVP planning records)
- `Docs/Engineering/RAG_TECHNICAL.md` (Detailed design spec, superseded by active retrieval pipelines)

### 6. DELETE-CANDIDATE
No documents were classified under this category, as all historical files contain useful reference value or context, and none represent a direct risk of confusion that cannot be resolved via marking them as historical/archived.

---

## Technical Audit Findings
- **PCC Local Simulation**: Explicitly verified in `EngineSDKCompatibility.swift` and `FoundationModelRoutePolicy.swift`. All documents claiming PCC remote enclave execution must be updated or superseded.
- **SQLite Database Scheme**: Explicitly verified in `SQLiteFullTextService.swift` that all knowledge libraries share a single SQLite database with column-based `container_id` isolation. Documents claiming separate isolated database files must be corrected.
- **Sync Plane**: Explicitly verified in `WorkspaceSyncService.swift` that ubiquity sweeps operate on iCloud Drive, not CloudKit.
- **Billing Plane**: Explicitly verified in `EntitlementStore.swift` that subscription limits reside in UserDefaults, not Keychain.

## Action Plan for Phase 9B
1. Apply Documentation Reconciliation Workflow (`02_DOCUMENTATION_RECONCILIATION.md`).
2. Surgically edit files classified as **UPDATE** to purge pronouns, remove personal greetings, and correct technical parameters.
3. Execute the merge of `STORAGE_AND_PIPELINE_TRACE.md` into the active atlas, then archive the source file.
4. Update `ARCHITECTURE.md` to indicate it has been superseded.
