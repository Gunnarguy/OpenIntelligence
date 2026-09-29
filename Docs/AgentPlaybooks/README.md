# OpenIntelligence Agent Playbooks

This directory contains the operational playbooks for autonomous agents (like Gemini/Antigravity) interacting with the OpenIntelligence repository.

## Required Reading Order
1. Always start with `AGENTS.md` (repository root).
2. If using Gemini, read `GEMINI.md` (repository root).
3. Read `00_SUPERSEDING_EVIDENCE_PROTOCOL.md` (mandatory for all tasks).
4. Read the specific numbered playbook corresponding to your assigned task.

## Playbook Directory
- **`00_SUPERSEDING_EVIDENCE_PROTOCOL.md`**: The strict master rules for evidence gathering, confidence scoring, and preventing hallucinated code relationships.
- **`01_PHASED_ARCHITECTURE_ATLAS.md`**: Workflow for discovering and mapping the repository components (Phases 0-9). Completed in June 2026; kept as the reference procedure for section 16 of `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`. Do not rerun it without the owner's request.
- **`02_DOCUMENTATION_RECONCILIATION.md`**: Workflow for updating stale or conflicting documentation.
- **`03_CHANGE_IMPACT_DOC_UPDATE.md`**: The maintenance workflow for updating documentation after PR merges or code changes.
- **`04_PR_GOVERNANCE_REVIEW.md`**: Pre-merge checklist and governance review constraints.
- **`05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md`**: Phase 1A-era implementation constraints for the Evidence Threads feature. Its banner lists what Phase 1B shipped against them and which constraints still bind.
- **`07_TASK_ROUTER_AND_CHANGE_CONTROL.md`**: Superseded. The RepoOS preflight routes tasks now (`AGENTS.md` rule 11); kept as history.
- **`architecture-atlas-update.md`**: A pointer to the path-to-doc table that says which Atlas section to update after a code change.

Moved to `Docs/Archive/` on 2026-09-29, so no longer listed here: `06_PHASE_1A_IMPLEMENTATION_PLAN.md` and the three pointer stubs `change-impact-docs-update.md`, `documentation-reconciliation.md` and `pr-review-docs-gate.md`.

## Approval gate
The approval gate in force is `AGENTS.md` rule 12: present the plan and wait for `PROCEED: IMPLEMENT` before the first source edit. Rule 10 adds that an agent stops after the requested phase and waits for instructions. The `NEXT PHASE: Phase X` handoff this section used to describe belonged to the phased atlas audit in `01_PHASED_ARCHITECTURE_ATLAS.md`, completed in June 2026; `GEMINI.md` still uses it for audit work in Antigravity. (Replaced 2026-09-29.)

## Evidence and Confidence
No claim can be made without an associated evidence level and confidence score. This prevents conceptual summaries from being falsely documented as exact code linkages. Future agents reading these files must treat `conceptual` or `inferred` claims as hypotheses requiring verification, not as source-of-truth facts.
