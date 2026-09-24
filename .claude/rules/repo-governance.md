---
paths:
  - ".agents/**"
  - ".codex/**"
  - ".claude/**"
  - "CLAUDE.md"
  - "AGENTS.md"
  - "GEMINI.md"
  - "Docs/RepoOS/**"
  - "Docs/AuditArtifacts/RepoOS/**"
  - "Docs/ai/**"
---

# Agent governance and context system

Route `repoos_workspace_automation`. Risk low, but this layer is what keeps every other route
honest, so drift here is expensive.

**Apple app source is out of scope for this route.** `OpenIntelligence/**`,
`OpenIntelligence.xcodeproj/**`, `Info.plist`, `Package.swift`, `Package.resolved`, `*.storekit`,
and `*.entitlements` are forbidden edits while working on governance.

**Same turn as the change:** `Docs/RepoOS/00_REPO_COMMAND_CENTER.md`,
`Docs/RepoOS/01_TASK_ROUTER.md`, `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`, and
`CHANGELOG.md` tagged `**[General]**`. A durable workflow feature also takes the full `AGENTS.md`
rule 14 list.

**Tests:**

```bash
python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py
```

```bash
python3 scripts/secret_scan.py
```

## Four instruction planes, one fact each

`AGENTS.md` is the cross-agent directive list and stays authoritative. `CLAUDE.md` is Claude Code's
control plane and is the only one Claude Code loads automatically. `GEMINI.md` serves
Gemini/Antigravity. `.agents/rules/` is always-on for Antigravity. `.geminirules` and
`.agents/AGENTS.md` are one-paragraph pointers since 2026-09-24, after both drifted into
contradicting the rest; their old text is in `Docs/Archive/`. Do not grow them back into copies.

What every task reads is decided in one place, `AGENTS.md` rule 15, and executed by
`repoos_router.py`'s `UNIVERSAL_DOCS` (pinned by `test_every_task_loads_only_the_small_universal_set`).
Until 2026-09-24 four other files still told agents to read the Atlas, the Transition Plan and the
canonical doc in full on every task, about 130 KB that rule 15 had retired.

A fact that lives in two of these will drift. Put it in one and point the others at it. If you
change a directive in `AGENTS.md` that `CLAUDE.md` restates, change both in the same edit or the
restatement becomes a lie.

## Do not weaken enforcement

`.claude/settings.local.json` holds the user's permission allowlist and is machine-local. Do not
move permissions into the tracked `settings.json`, and do not broaden an allowlist as a convenience
while working on something else.

`scripts/enforce_docs_hook.sh` is a git pre-commit hook, separate from Claude Code hooks. It may be
strengthened; it may not be loosened without the user saying so in the same turn. Until 2026-08-28
it accepted any `Docs/*` file as satisfying any Swift change, which made AGENTS.md rule 14 advisory
in practice.

## The enforcement layer, and what may not be quietly cut out of it

Seven pieces, each of which is load-bearing:

| Piece | Fires | Does |
|---|---|---|
| `scripts/required_docs.sh` | called by the other two | resolves changed paths to the docs they require |
| `scripts/enforce_docs_hook.sh` | git pre-commit | fails a commit whose staged source lacks those docs |
| `.claude/hooks/notion-receipt.sh` | PostToolUse on Notion write tools | records that a roadmap write actually landed |
| `.claude/hooks/stop-handoff.sh` | Stop | asks once for handoff, docs, and roadmap obligations left open |
| `.claude/hooks/instructions-loaded.sh` | InstructionsLoaded | records which instruction file loaded, why (`session_start`, `path_glob_match`, `compact`, ...) and what triggered it |
| `scripts/instructions_report.sh` | on demand, and from the Stop hook | names any path-scoped rule that governs changed code but never loaded |
| `scripts/verify_doc_claims.py` | git pre-commit, when a `.md`, `.swift` or `.json` file is staged | fails when a core doc's version, enum, path, anchor or `Type.member` claim, or a route-table path, no longer matches the repository |

`required_docs.sh` is the executable copy of the table in
`.agents/rules/01-docs-and-notion-sync.md`. Editing one without the other is how the two enforcement
points start disagreeing, and the script is the copy that gets obeyed.

Both hooks have tests that run the real scripts, not a reimplementation of them:

```bash
bash scripts/test_enforce_docs_hook.sh
```

```bash
bash scripts/test_stop_handoff.sh
```

To answer "did it actually read that rule?" rather than guess at it:

```bash
bash scripts/instructions_report.sh
```

Run both after any change to the layer, and `bash scripts/test_verify_doc_claims.sh` after any
change to the claims checker. Two of the defects they now pin were found by writing them:
a `${var/pat/rep}` that silently matched nothing, and a heredoc that stole the payload's stdin so
every receipt parsed an empty string.

Every one of these scripts exits 0 on failure paths so it can never block a session, which also
means a broken one fails silently. Two instances found 2026-09-24: `mktemp -t prefix` is BSD-only,
so on Linux the receipt, instructions-loaded and report scripts did nothing at all; and the
pre-commit claims gate tested `-x` on a script git stores as 100644, so it never ran on a fresh
clone. Use `mktemp "${TMPDIR:-/tmp}/name.XXXXXX"`, and test for a file with `-f`, not `-x`.
