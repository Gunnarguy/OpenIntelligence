# Audit Artifacts — historical record, not live documentation

**Nothing in this directory is authoritative.** These are working artifacts from
audits that have completed: phase reports, scan notes, component summaries,
verification checklists. They record what was believed and checked at a point in
time, which is exactly why they are kept and exactly why they must not be read as
current.

Written between **2026-06-26 and 2026-08-23**, across ten audit tracks
(`ArchitectureAtlas`, `Benchmarks`, `DefectDiagnosis`, `DocumentationGovernance`,
`FinalReview`, `Governance`, `Implementation`, `Planning`, `RepoOS`,
`Verification`). Fifty-eight files. All of them predate the v5.0 release.

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
