# Future Agent Execution Checklist

> **Superseded (2026-09-29): written for the Evidence Threads Phase 1A gate, which closed in June 2026 (`AGENTS.md` rule 13).** Before a task, read `Docs/ai/STATE.md` and `HANDOFF.md`, and run the RepoOS preflight, which names the allowed and forbidden files for the route. Item 10 contradicts the shipped code: threads are stored in `Application Support/EvidenceThreads/<containerId>/` (`EvidenceThreadStore.swift:60`), and `migrateLegacyThreadsIfNeeded` moves any `LocalCache/EvidenceThreads/` files there at launch (`EvidenceThreadStore.swift:19-23`). `[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/Storage/EvidenceThreadStore.swift, read 2026-09-29]`

Before modifying any source code in this repository, future agents must review this checklist, compile the answers in their reasoning process, and execute the steps in order:

---

## Pre-execution Check

1.  **Read the Canonical Source of Truth:** Read [CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md](../../CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md).
2.  **Read the Consistency Audit:** Read [DOCUMENTATION_CONSISTENCY_AUDIT.md](../../DOCUMENTATION_CONSISTENCY_AUDIT.md).
3.  **Check Workspace Status:** Run `git status --porcelain` to verify the state of the workspace and check for uncommitted files.
4.  **Resolve Active Phase:** State which phase is being implemented (Phase 0 / 1A / 1B / 2 / 3 / 4 / 5).
5.  **Allowed Files List:** Enumerate the exact files allowed to be modified under the active phase.
6.  **Prohibited Files List:** Enumerate the exact files prohibited from being modified under the active phase.

---

## Architectural Rules & Safeguards

7.  **Scope Boundaries Verification:** Confirm that no source code files outside the allowed scope of the active phase will be modified.
8.  **Strict Read-Only Verification:** Confirm that no implementation or code modifications will occur if the current task is audit-only (Phase 0).
9.  **Gated APIs Exclusion:** Confirm that no modifications will be made to StoreKit files, synchronization service components, LLM routing controllers, or App Intents unless the active phase explicitly permits them.
10. **Storage Boundary Enforcement:** Confirm that no thread files or indexes will be saved under the base application support directory (`AppSupportPaths.baseDir()`). All thread data must reside inside the strictly local-only cache path:
    `LocalCache/EvidenceThreads/`
11. **Streaming Write Suppression:** Confirm that no disk writes are triggered during LLM token streaming. Saves must only run on final completions or sentence splits.
12. **Non-destructive Migration:** Confirm that legacy chat history files are not deleted or formatted before being successfully migrated to a default thread.

---

## Verification Plan

1.  **Test Execution:** Detail the exact testing plan (unit tests, manual testing, or simulator QA checks) that will run to verify there are no regressions on existing sync, billing, routing, or RAG functionality.
