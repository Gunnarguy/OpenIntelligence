# Rule: Automatic Docs & Notion Roadmap Sync (always on)

Documentation drift is prohibited (AGENTS.md rules 14 & 16). You do NOT wait to be told to update docs or Notion. The moment you modify code, the matching doc + roadmap updates become part of the same task. A task with code changes but no doc/roadmap sync is INCOMPLETE.

## Path-triggered doc updates
When you edit files matching a pattern below, update the listed docs in the same turn (including any Mermaid diagrams inside them):

| You edited... | You must update... | Notion Component |
|---|---|---|
| `Services/RAG/Retrieval/**`, `Services/Query/**`, `Services/RAG/Tuning/**` | `Docs/RETRIEVAL_PIPELINE.md` (+ its Mermaid), `CHANGELOG.md` | Retrieval |
| `Services/Document/**` (processing, chunking, OCR) | `Docs/INGESTION_PIPELINE.md` (+ its Mermaid), `CHANGELOG.md` | Ingestion or Chunking |
| `Services/Embedding/**` | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` §17, `CHANGELOG.md` | Indexing |
| `Services/Storage/**`, `Services/VectorStore/**` | Atlas §9 + storage sections, `CHANGELOG.md` | Indexing |
| `Services/AIPlatform/**`, `Services/LLM/**` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10, `CHANGELOG.md` | Orchestration |
| `Services/RAG/Orchestration/**`, `Services/Agentic/**` | Atlas service map, `CHANGELOG.md` | Orchestration |
| `RAGAppIntents.swift`, `Services/Agentic/Entities/**` | Atlas §12, `CHANGELOG.md` | Shortcuts |
| `Services/Billing/**`, `Features/Billing/**` | `Docs/BILLING_AND_LIMITS.md`, `CHANGELOG.md` | General |
| `EvidenceThread*`, `ThreadSidebarView.swift` | Atlas §15, canonical §11, `CHANGELOG.md` | Orchestration |
| `Features/**`, `UI/**` (user-visible) | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` | UI |
| `.codex/skills/**`, `.agents/**`, `Docs/RepoOS/**` | Command Center, Task Router, change-impact matrix, `CHANGELOG.md`; full rule 14 list for a durable workflow feature | General |
| Any phase/milestone completion | Full AGENTS.md rule 14 list: `README.md`, Atlas, `Docs/AppleIntelligenceTransitionPlan.md`, `CHANGELOG.md`, `Docs/RELEASE_NOTES.md`, canonical doc, `Docs/ROADMAP.md` + Notion | (as appropriate) |

CHANGELOG bullets always carry the architectural tag: `[Retrieval]`, `[Ingestion]`, `[Chunking]`, `[Indexing]`, `[Orchestration]`, `[Shortcuts]`, `[UI]`, or `[General]`.

## Active-release targeting (every task)

Run the repository preflight before acting. It derives the active release from current artifacts and reports the exact targets, including `documentation_targets.changelog_section`. Write the entry into the section the preflight names, which is **not always `[Unreleased]`**: when the first numbered heading in `CHANGELOG.md` carries the `unreleased` HTML-comment marker on its own line, that heading is the open section and entries go under it. Entries left in `[Unreleased]` above an uncut numbered heading are what `ci_post_clone.sh` refuses to build, and `scripts/enforce_docs_hook.sh` now rejects that at commit time. Then update the matching active-version section in `Docs/RELEASE_NOTES.md`, and use that same version for Notion `Target Release`. Read-only, diagnosis-only, pure-docs, and tests-only tasks report the targets but do not create empty or speculative release documentation changes. If the version is `unknown`, reconcile the canonical version markers before writing release documentation or Notion.

## Notion Roadmap — when to touch it (unprompted)
Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043`; its data source ID is `37f49a74-d54f-81b0-92d9-000bce5e05fa` (different suffix — query tools take the data source ID, retrieve-database tools take the database ID). Never locate the roadmap via workspace search, and never answer roadmap questions from search results — other databases in the workspace have similar-looking rows (theirs use emoji statuses; this one does not). Follow the exact tool recipe in `.agents/workflows/sync-notion.md`.

- **Starting a feature/task** → query the DB for a matching row. If found, set `Status` = `In Progress`. If not, create one (`Name` = feature summary, `Status` = `In Progress`, `Component`, `Priority`, `Target Release`, `Added` = today).
- **Completing a feature/task** → set `Status` = `Completed`, set the `Completed` date to today, AND set `Shipped On` to the platforms where the change is actually installable. `Status` tracks the work; `Shipped On` tracks reach. A verified fix live on macOS only is `Completed` with `Shipped On: macOS`, not held open because iOS has not had a release.
- **User mentions roadmap/plans/backlog** → pull current rows from the DB first; never answer from memory.
- **Pure docs-only or refactor-only changes** → no Notion row required unless it closes a roadmap item.

## Notion schema — exact values only (do not invent options)
- `Status`: `To Do` | `In Progress` | `Completed` — there is NO "Shipped" option.
- `Component`: `Ingestion` | `Chunking` | `Indexing` | `Retrieval` | `Orchestration` | `Shortcuts` | `General` | `UI` | `Infrastructure`
- `Priority`: `High` | `Medium` | `Low`
- `Target Release`: `v4.0`, `v4.1`, `v4.2`, `v4.3`, `v4.3.1`, `v4.4`, `v4.5 (Phase 2B)`, `v4.6`, `v4.7 (iOS) / v3.0 (macOS)`, `v4.8 (iOS)`, `v4.9`, `v5.0`, `v5.0.1`, `v5.0.2`, `v5.1`, `Future Backlog`.
- `Shipped On`: multi-select, `iOS` | `macOS`. Added 2026-08-28. Where users can actually install the change, which is not the same as where it was written. The platforms diverged on 2026-08-26 — macOS is on 5.0.2 while iOS is on 5.0 — so a fix can be live on one and absent on the other. Empty means not recorded, not "not shipped". Read off the live data source 2026-08-28. Note the two split-numbering options are historical: from 4.9 onward both platforms share one version, so new rows use a single label such as `v5.1`, never a split one. This list is a cache: it sat at `v5.0` while `v5.1` was already live in the database, so re-read the data source whenever the active release changes.
- `Target OS`: `All (26.5 & 27)` | `iOS/macOS 26.5 Only` | `iOS/macOS 27+ Only`. **This property was missing from this file entirely** and is part of the schema.
- Dates: `Added`, `Completed` (ISO dates).

## Verification before ending any code-modifying turn
1. Warning-free build: `bash scripts/build_simulator_smoke.sh` (AGENTS.md rule 14).
2. Docs updated per the table above — confirm by listing them in your summary.
3. Notion updated if a feature started/finished — state the row you touched.

The table above is no longer enforced by good intentions. `scripts/required_docs.sh` is its
executable copy: it resolves changed paths to the documents they require, and both the git
pre-commit hook and the Claude Code Stop hook fail or ask against its output. Change the table here
and change that script in the same edit, or the two will disagree and the script is the one that
gets obeyed.
