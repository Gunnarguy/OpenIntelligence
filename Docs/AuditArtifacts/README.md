# Audit Artifacts — historical record, not live documentation

**Nothing in this directory is authoritative.** These are working artifacts from
audits that have completed: phase reports, scan notes, component summaries,
verification checklists. They record what was believed and checked at a point in
time, which is exactly why they are kept and exactly why they must not be read as
current.

Written between **2026-06-26 and 2026-08-23**, across ten audit tracks
(`ArchitectureAtlas`, `Benchmarks`, `DefectDiagnosis`, `DocumentationGovernance`,
`FinalReview`, `Governance`, `Implementation`, `Planning`, `RepoOS`,
`Verification`), plus eleven files at this folder's top level. 109 files, not
counting this README: 58 Markdown and 51 data files (47 CSV, 3 JSON, 1 text).
All of them predate the v5.0 release. (Corrected 2026-09-29: this line said
fifty-eight files, which is the Markdown alone.)
`[evidence_level: grep_verified, confidence: exact, evidence_source: git ls-files Docs/AuditArtifacts, with each file's first-add date from git log --diff-filter=A, counted 2026-09-29]`

## If you are looking for what is true now

| Question | Read |
|---|---|
| What is live on the App Store | [`../SHIPPED_VERSION.json`](../SHIPPED_VERSION.json) |
| Which capabilities actually ship | [`../SHIPPED_CAPABILITIES.json`](../SHIPPED_CAPABILITIES.json) |
| Current objective and next action | [`../ai/STATE.md`](../ai/STATE.md) |
| Component map | [`../OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`](../OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md) |
| Roadmap | The Notion database. Not `../ROADMAP.md`, which is a mirror and has been the stale side before. |
| How to build, test and release | [`../ai/RUNBOOK.md`](../ai/RUNBOOK.md) |

## Why these are not deleted

An audit that found something, and the record of what it checked to find it, is
evidence. Deleting it leaves a claim in the changelog with nothing behind it. The
same reasoning keeps `BenchmarkRuns/` on disk and keeps withdrawn claims corrected
in place rather than removed.

## Why these are not moved

Four hundred and seventy-one cross-references in this repository were repaired on
2026-08-27, converting absolute paths on one developer's machine into
repo-relative links. Relocating these files would break that work for no gain. The
directory is marked instead.

`[evidence_level: file_dates_verified, confidence: exact]`

## Added after this index was written

The description at the top covers the original 109 files. These folders were
added later. The same rule applies to them: they are a historical record, not live
documentation.

| Folder | Date | Contents |
|---|---|---|
| [`DocOverhaul_2026-09-24/`](DocOverhaul_2026-09-24/README.md) | 2026-09-24 | Unapplied edit proposals and suspected code defects from the documentation overhaul |
| [`RAGArchitectureAudit_2026-09-26/`](RAGArchitectureAudit_2026-09-26/README.md) | 2026-09-26 | The diagnosis of the "1 lb" wrong answer, and its fix. The fix is applied in 5.5, the open release: it merged into `main` in `206e044` on 2026-09-28 after the full iOS suite passed on the merged tree (504 tests, 4 skipped, 0 failures), and 5.5 is not yet submitted. Also an audit of ingestion, SQLite and vector storage, retrieval, generation and verification against Apple's iOS 27 frameworks and current practice |

`[evidence_level: file_existence_verified, confidence: exact]`
`[evidence_level: artifact_derived, confidence: high, evidence_source: commit message of 206e044; Docs/ai/STATE.md "Verification (2026-09-28)"; the suite was not re-run for this note, 2026-09-29]`
