# Final Implementation Gate

**VERIFIED: READY FOR SEPARATE PHASE 1A EVIDENCE THREADS IMPLEMENTATION TASK**

## Exact Next Implementation Task Title
`OpenIntelligence Evidence Threads Phase 1A — Local Store Only`

## Required Model
`Gemini 3.1 Pro high reasoning`

## Required Files Future Implementation Agent Must Read
- AGENTS.md
- GEMINI.md
- Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md
- Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md
- Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
- Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md
- Docs/AuditArtifacts/FinalReview/final_implementation_gate.md
- Docs/AuditArtifacts/FinalReview/final_readiness_matrix.csv
- Docs/AuditArtifacts/FinalReview/final_unresolved_risks.csv
- Docs/AuditArtifacts/ArchitectureAtlas/evidence_threads_design_decision.md

## Files Allowed for Phase 1A Implementation
- `EvidenceThread.swift` (or similar new data model files under `Models/`).
- JSON persistence utilities explicitly required for the new thread model.
- Minimal UI routing necessary to test thread creation (if explicitly requested by user).

## Files Prohibited for Phase 1A Implementation
- `ChatMessage.swift` (existing model must remain untouched).
- `WorkspaceSyncService.swift` (no sync changes allowed).
- `EntitlementStore.swift` (no StoreKit changes allowed).
- `FoundationModelRoutePolicy.swift` and `CloudConsentPromptView.swift` (no PCC changes).
- `RAGAppIntents.swift` (no App Intent changes).
- Existing SQLite databases and `SQLiteFullTextService.swift` schema (no destructive migration).
- Existing `BNNSVectorDatabase.swift` (no destructive migration).

## Phase 1A Boundaries
- Local store only.
- No UI unless explicitly allowed.
- No iCloud sync.
- No StoreKit changes.
- No App Intents changes.
- No routing/PCC changes.
- No destructive migration.
- No streaming-token disk writes.
- No baseDir thread storage.

## Required Tests/QA
- Ensure new `EvidenceThread` model serializes and deserializes from isolated local JSON without data loss.
- Verify that saving an `EvidenceThread` does not invoke `WorkspaceSyncService`.

## Exact Implementation Prompt Stub
```text
You are implementing OpenIntelligence Evidence Threads Phase 1A — Local Store Only.
Use Gemini 3.1 Pro high reasoning.
Before writing any code, you must read the required governance files listed in Docs/AuditArtifacts/FinalReview/final_implementation_gate.md.
Adhere strictly to the boundaries and prohibited files defined in the implementation gate.
Produce a brief implementation plan and await my approval before modifying source code.
```
