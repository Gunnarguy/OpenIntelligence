# Final Canonical File Index

This index directs future agents and developers on which files serve as the active source of truth.

## 1. Essential Files to Keep at Repo Root
- `AGENTS.md`
- `GEMINI.md`

## 2. Essential Canonical Docs
- `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`
- `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
- `Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md`

## 3. Essential Playbooks
- `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`
- `Docs/AgentPlaybooks/03_CHANGE_IMPACT_DOC_UPDATE.md`
- `Docs/AgentPlaybooks/04_PR_GOVERNANCE_REVIEW.md`
- `Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md`

## 4. Essential Final Review Artifacts
- `Docs/AuditArtifacts/FinalReview/final_implementation_gate.md`
- `Docs/AuditArtifacts/FinalReview/final_readiness_matrix.csv`
- `Docs/AuditArtifacts/FinalReview/final_unresolved_risks.csv`
- `Docs/AuditArtifacts/FinalReview/final_artifact_retention_matrix.csv`

## 5. What NOT to Use as Source of Truth
The following files are retained strictly for historical auditing purposes. **Do not base implementation decisions on these:**
- Old audit docs (e.g. `Docs/FULL_REPO_*`)
- Older product positioning audits (e.g. `Docs/PRODUCT_POSITIONING_*`)
- Interim recovery reports (e.g. `PHASE_STATE_RECONCILIATION.md`, `PHASE_3_TO_7_DELTA_REPAIR_REPORT.md`)
- Generated CSVs, unless specifically referenced by the active canonical docs

## 6. What Future Agents Must Read Before Implementation
Before writing any code, future implementation agents must read:
1. `AGENTS.md`
2. `GEMINI.md`
3. `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`
4. `Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md`
5. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
6. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`
7. `Docs/AuditArtifacts/FinalReview/final_implementation_gate.md`
8. `Docs/AuditArtifacts/FinalReview/final_readiness_matrix.csv`
9. `Docs/AuditArtifacts/FinalReview/final_unresolved_risks.csv`
10. `Docs/AuditArtifacts/ArchitectureAtlas/evidence_threads_design_decision.md`
