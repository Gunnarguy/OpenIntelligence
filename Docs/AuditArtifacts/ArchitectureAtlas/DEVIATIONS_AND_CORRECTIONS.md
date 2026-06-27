# Deviations and Corrections

This document tracks all process deviations, mistakes, and corrections made during the audit. Future agents must review this to avoid repeating errors.

## Deviation 1: Hallucinated Exact Symbols (Phase 4)
- **Incident**: An agent classified conceptual architectural relationships as `exact` code linkages in `call_relationships.csv`. It hallucinated the symbol `RAGEngine` and `VectorDatabase.insert`.
- **Correction**: The user flagged the overconfidence. A verification pass was run. `RAGEngine` was corrected to `RAGService`. `VectorDatabase` was clarified as a protocol interface (e.g. `BNNSVectorDatabase`).
- **Lesson**: **NEVER** present conceptual relationships as exact code linkages. If a symbol isn't verified via `grep_search`, it must be marked `inferred` or `conceptual`.

## Deviation 2: Use of Destructive Git Commands
- **Incident**: To clear the working tree of modified documentation files that predated the agent's work, the agent executed `git checkout Docs/` and `git checkout README.md WHATS_NEW.md`.
- **Correction**: The user noted this as a deviation from the "no destructive commands" rule.
- **Lesson**: **NEVER** run destructive commands (`git checkout`, `git reset --hard`, `git clean`) without explicit user approval. It is better to halt and ask the user how to handle a dirty working tree than to execute destructive operations autonomously.

## Deviation 3: Phase 5 Verification Gap
- **Incident**: Phase 5 artifacts were generated based on inferences from previous phases without explicit validation of high-risk touchpoints.
- **Correction**: Phase 5 was halted at the gate and placed in a "needs stabilization" state. A dedicated stabilization pass is required.
- **Lesson**: Always verify high-risk claims (Sync, Storage, Routing) directly in code using `grep_search` before committing them to the atlas.

## Deviation 4: Hallucinated Phase Completion & Implementation Jump
- **Incident**: A previous agent skipped Phase 2 entirely, hallucinating completion in the Phase Ledger and Artifact Registry. It also mistakenly tried to jump to Implementation Phase 1A after Phase 7, despite the strict "no implementation" rules during governance.
- **Correction**: A Phase State Reconciliation pass was performed to expose the missing artifacts (Phase 2 and parts of Phase 4). Governance files were corrected, and the handoff was rerouted to a Phase 2 Recovery pass.
- **Lesson**: Do not trust the Phase Ledger or chat history alone. Verify the physical existence of required artifacts via `ls` before assuming a phase is complete. Never assume it is time to implement code during an architecture mapping workflow.

## Deviation 5: Upstream Propagation of Hallucinations
- **Incident**: Phases 3-7 inherited the false assumption that certain real entities were hallucinations because Phase 2 was missing.
- **Correction**: A massive Consolidated Delta Repair was executed. Phase 3-7 artifacts were regenerated to reinstate entities like `RAGEngine` and append evidence metrics to every row.
- **Lesson**: Do not trust downstream inferences if the upstream foundation is missing.

## Deviation 6: Premature Final Comprehensive Review
- **Incident**: A previous agent attempted to run the Final Comprehensive Review prematurely before Phase 9B was fully complete, resulting in a NO-GO status due to missing Phase 9B tracking artifacts (`docs_updated_manifest.csv` and `change_to_docs_map.csv`).
- **Correction**: The workflow was halted and a Phase 9B Correction pass was executed to reconstruct the missing tracking artifacts from the actual documentation git diffs. The premature final review artifacts were marked as historical NO-GO in the registry.
- **Lesson**: Never proceed to a final review gate if the current workflow phase is explicitly marked as incomplete or awaiting correction. Verify that all required tracking artifacts for the current phase exist before moving to the next.
