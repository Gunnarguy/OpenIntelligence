# Documentation Consistency Audit

## 1. Docs Inspected
- `Docs/ARCHITECTURE.md`
- `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
- `Docs/BILLING_AND_LIMITS.md`
- `Docs/INGESTION_PIPELINE.md`
- `Docs/PRIVACY_AND_ROUTING.md`
- `Docs/RETRIEVAL_PIPELINE.md`
- `Docs/Engineering/RAG_TECHNICAL.md`
- `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md`
- `Docs/LIMITATIONS.md`
- `Docs/RELEASE_NOTES.md`
- `Docs/ROADMAP.md`
- `Docs/USER_CHANGELOG.md`
- `CHANGELOG.md`

## 2. Stale Docs
- `Docs/RELEASE_NOTES.md` (claims Core AI sentence embeddings are active).
- `Docs/ARCHITECTURE.md` (violates objective tone rules).

## 3. Contradictory Docs
- **Sync**: Docs claim CloudKit; Code uses iCloud Drive Ubiquity.
- **PCC**: Docs claim remote enclave; Code uses local simulation.
- **SQLite**: Docs claim isolated files; Code uses shared file with column isolation.
- **Billing**: Docs claim Keychain; Code uses UserDefaults.

## 4. Overgeneralized Docs
- `Docs/Engineering/RAG_TECHNICAL.md` does not accurately describe the limitations of the context packing heuristic vs CoreML tokenizers.

## 5. Missing Docs
- FTS5 query tokenizer behavior in `SQLiteFullTextService.swift` is undocumented.

## 6. Recommended Doc Actions
Apply the Documentation Reconciliation Workflow (`02_DOCUMENTATION_RECONCILIATION.md`).

## 7. Docs that should be kept
- `Docs/LIMITATIONS.md`
- `Docs/USER_CHANGELOG.md`

## 8. Docs that should be updated
- `Docs/BILLING_AND_LIMITS.md` (Update to UserDefaults)
- `Docs/PRIVACY_AND_ROUTING.md` (Update to local simulation, remove pronouns)
- `Docs/RETRIEVAL_PIPELINE.md` (Remove pronouns)
- `Docs/INGESTION_PIPELINE.md` (Remove pronouns)

## 9. Docs that should be merged
- `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md` into `OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`.

## 10. Docs that should be superseded
- Old canonical docs replaced by `CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`.

## 11. Docs that should be archived
- `Docs/Engineering/RAG_TECHNICAL.md`

## 12. Docs that should be delete-candidates
- Redundant files superseded by the Architecture Atlas.

## 13. Link to document_claim_matrix.csv
[document_claim_matrix.csv](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/document_claim_matrix.csv)

## 14. Link to document_contradictions.csv
[document_contradictions.csv](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/document_contradictions.csv)

## 15. Link to documentation_cross_reference.csv
[documentation_cross_reference.csv](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/Docs/AuditArtifacts/ArchitectureAtlas/documentation_cross_reference.csv)
