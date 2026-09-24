# Handoff

The entry point for any agent or person picking this repository up, whatever tool reads it. It
holds no project facts, only where they live and how much of each file to read. If this file and
another disagree, the other file wins; correct this one.

Until 2026-09-24 this file was a 17 KB synthesis that duplicated `Docs/ai/STATE.md` and had gone
stale in 14 places. Its unique facts moved to their homes (`Docs/ai/RUNBOOK.md`, `Docs/ai/STATE.md`,
`Docs/ai/PROJECT.md`, `Docs/INGESTION_PIPELINE.md`); the old text is in `git log -p -- HANDOFF.md`.

## Reading order

1. `AGENTS.md`, then the "Before your first action" and "Non-negotiables" sections of `CLAUDE.md`.
   Read those two sections whatever your tool is: they carry project rules `AGENTS.md` does not.
2. `Docs/ai/STATE.md`, whole. Current objective, release status, constraints, exact next action.
3. `git log --oneline -15` and `git status`. Trust git over any document, this one included.
4. The route for your task, before touching anything. Its output is binding:
   `python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<task>" --path <path>`
5. The Notion roadmap, before proposing work. Work that is not on the board is work nobody decided
   to do. How to reach it: `.claude/skills/notion-roadmap/SKILL.md`.

## Read by section, never whole

| File | Read only |
|---|---|
| `CHANGELOG.md` | The `## [Unreleased]` stub and the first numbered `## <version>` section, stopping at the next `## ` heading. Versions 2.0 to 5.2 are in `Docs/Archive/CHANGELOG_2.0_to_5.2.md`. |
| `Docs/ai/RUNBOOK.md` | `grep -n '^## ' Docs/ai/RUNBOOK.md`, then the one section your task needs. |
| `Docs/ai/DECISIONS.md` | The heading list, then any decision touching what you are about to change. |
| `BenchmarkRuns/LEDGER.md` | Before writing down any retrieval, ingestion or answer-quality number: its header, then every entry on the stage or figure you touch. Most of the wrong conclusions in this project's history came from skipping it. |

Short enough to read whole when the task needs them: `Docs/ai/PROJECT.md` (scope),
`Docs/ai/ARCHITECTURE.md` (component map, product vocabulary, and which document owns each area),
`Docs/SHIPPED_VERSION.json` (what the App Store has versus what is being prepared), `Docs/ai/INDEX.md`.

## Elsewhere

- Evidence rules, before any audit or docs pass: `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`.
- Files that may not be edited unless named: `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
- Before removing any factual claim: `.claude/skills/oi-claim-audit/SKILL.md`.
- Store copy per version, newest first: `Docs/Release/APP_STORE_METADATA_HISTORY.md`.
- The owner's agent memory, plain markdown on his machine, indexed by `MEMORY.md`:
  `~/.claude/projects/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/memory/`. The lessons
  worth reading even if you read nothing else there: the iCloud one, the nondeterminism one, the
  tokenizer padding one (a bug that silently truncated 55% of every ingested document) and the
  silent-truncation one (a stage discards data and everything downstream still reports healthy).
