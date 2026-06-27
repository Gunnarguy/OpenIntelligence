# OpenIntelligence Agent Playbooks

This directory contains the operational playbooks for autonomous agents (like Gemini/Antigravity) interacting with the OpenIntelligence repository.

## Required Reading Order
1. Always start with `AGENTS.md` (repository root).
2. If using Gemini, read `GEMINI.md` (repository root).
3. Read `00_SUPERSEDING_EVIDENCE_PROTOCOL.md` (mandatory for all tasks).
4. Read the specific numbered playbook corresponding to your assigned task.

## Playbook Directory
- **`00_SUPERSEDING_EVIDENCE_PROTOCOL.md`**: The strict master rules for evidence gathering, confidence scoring, and preventing hallucinated code relationships.
- **`01_PHASED_ARCHITECTURE_ATLAS.md`**: Workflow for discovering and mapping the repository components (Phases 0-9).
- **`02_DOCUMENTATION_RECONCILIATION.md`**: Workflow for updating stale or conflicting documentation.
- **`03_CHANGE_IMPACT_DOC_UPDATE.md`**: The maintenance workflow for updating documentation after PR merges or code changes.
- **`04_PR_GOVERNANCE_REVIEW.md`**: Pre-merge checklist and governance review constraints.
- **`05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md`**: Specific implementation constraints for the Evidence Threads feature.
- **`06_PHASE_1A_IMPLEMENTATION_PLAN.md`**: Implementation plan for Evidence Threads Phase 1A.
- **`07_TASK_ROUTER_AND_CHANGE_CONTROL.md`**: Task routing and preflight change impact verification.

## Phase Gates
Agents must operate in discrete phases. At the end of a phase, the agent must present its work and halt. Do not proceed to the next phase without explicit user command (`NEXT PHASE: Phase X`).

## Evidence and Confidence
No claim can be made without an associated evidence level and confidence score. This prevents conceptual summaries from being falsely documented as exact code linkages. Future agents reading these files must treat `conceptual` or `inferred` claims as hypotheses requiring verification, not as source-of-truth facts.
