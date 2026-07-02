# /update-docs — Sync documentation to the current diff

Deterministically update every doc affected by the current working changes. Runs standalone or called from /finalize.

1. Run `git status --porcelain` and `git diff` (plus `git diff --cached`) to enumerate changed files. Never use `git add .` at any point.
2. For each changed path, look up its row in `.agents/rules/01-docs-and-notion-sync.md` (path-trigger table) AND the matching `task_type` row in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv` (`required_docs_to_update` column). The union of both lists is mandatory.
3. Update each doc:
   - `CHANGELOG.md`: technical bullets under `[Unreleased]`, each prefixed with its architectural tag (e.g., `[Retrieval] Added RRF weight override`).
   - `WHATS_NEW.md` / `Docs/USER_CHANGELOG.md`: only for user-visible changes; plain language; never overclaim (no CloudKit wording — sync is iCloud Drive; no unconditional PCC-enclave claims — PCC currently falls back to on-device, see canonical §3).
   - Mermaid diagrams in `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`: regenerate any diagram whose depicted flow changed.
   - Canonical doc (`Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`): only if a §3 Safe Claim changed; tag with `[evidence: code_verified, exact, <file>]`.
4. Cross-check: no updated doc may contradict the canonical doc. If a contradiction is unavoidable, STOP and report it instead of writing.
5. Output a table: changed code path → docs updated → evidence tag.
