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
control plane and is the only one Claude Code loads automatically. `.geminirules` and `GEMINI.md`
serve Gemini/Antigravity. `.agents/rules/` is always-on for Antigravity.

A fact that lives in two of these will drift. Put it in one and point the others at it. If you
change a directive in `AGENTS.md` that `CLAUDE.md` restates, change both in the same edit or the
restatement becomes a lie.

## Do not weaken enforcement

`.claude/settings.local.json` holds the user's permission allowlist and is machine-local. Do not
move permissions into the tracked `settings.json`, and do not broaden an allowlist as a convenience
while working on something else. `scripts/enforce_docs_hook.sh` is a git pre-commit hook, separate
from Claude Code hooks; leave it alone.
