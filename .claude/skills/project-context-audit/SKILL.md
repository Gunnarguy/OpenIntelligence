---
name: project-context-audit
description: Audit the Claude context system in OpenIntelligence for staleness, duplication, contradiction, bloat, and dead references, then repair what is safe and report what is not. Use when instructions look wrong or contradictory, after a large refactor or release, when CLAUDE.md or STATE.md feel out of date, and when the user says "audit the context", "clean up the instructions", or "is CLAUDE.md still right".
---

# Context audit

The point is entropy removal. Read the artifacts, compare them to the repository, fix what the
evidence settles, and report what it does not.

This audits the *context system*. To audit a factual claim in user-facing copy or the roadmap, use
`oi-claim-audit` instead, and read its rule before deleting anything.

## Scope

`CLAUDE.md`, `.claude/rules/*.md`, `.claude/skills/*/SKILL.md`, `.claude/settings.json`,
`.claude/hooks/*.sh`, `Docs/ai/*.md`, and the auto memory index at
`~/.claude/projects/<project>/memory/MEMORY.md`.

## Checks

**Staleness**
- `Docs/ai/STATE.md`: does `Last verified commit:` still exist, and how far behind HEAD is it?
  Does its Working Set name files that no longer exist? Is its objective already shipped?
- Do commands in `Docs/ai/RUNBOOK.md` still exist? Check script paths, scheme and target names, the
  Xcode path, and the simulator UDID, which changes when runtimes are reinstalled.
- Does `Docs/ai/ARCHITECTURE.md` describe a component that has been deleted?

**Duplication and contradiction**
- Does `CLAUDE.md` restate an `AGENTS.md` directive that has since changed? These two drift first.
- Does the same fact appear in `CLAUDE.md`, a rule, a skill, and `Docs/ai/`? Pick one home, and make
  the others point at it.
- Do two rules give conflicting guidance for the same path?
- Does auto memory contradict a version-controlled file? Version control wins; correct or delete the
  memory.
- **Is any fact's only home auto memory?** Contradiction is the easy case. The dangerous one is a
  canonical fact that lives nowhere else: a requirement, an architectural contract, a security
  constraint, or a continuation state sitting only in
  `~/.claude/projects/<project>/memory/`. That directory is machine-local and invisible to
  teammates, to CI, and to any other machine. Read `MEMORY.md` and each topic file, and for every
  fact ask which version-controlled file owns it. If none does, move it to the owner and reduce the
  memory to a pointer, or delete it if the repo already says it better.

**Context cost**
- Is `CLAUDE.md` under 200 lines and still all invariants?
- Does any `.claude/rules/*.md` lack `paths` frontmatter? Unscoped rules load every session. Either
  scope it or justify the cost.
- Is a multi-step procedure sitting in `CLAUDE.md` where it should be a skill?
- Is a fact in `CLAUDE.md` that is cheaply rediscoverable from the code?

**Reference integrity**
- Every path named in `CLAUDE.md`, the rules, the skills, and `Docs/ai/` exists.
- Every `paths` glob in a rule matches at least one real file. A rule that matches nothing never
  fires and reads as coverage that is not there.
- Hook commands in `.claude/settings.json` point at files that exist and are executable.
- `.claude/settings.json` parses.

**Safety**
- No API key, token, password, private key, `.env` value, or UDID-plus-credential pair in any
  durable context file. Record the environment variable's name, never its value.
- `.claude/.state/` is gitignored and contains nothing tracked.
- No hook acquired network access or a destructive command.
- `.claude/settings.local.json` permissions were not broadened.

**Decisions**
- Is a decision in `Docs/ai/DECISIONS.md` superseded without being marked? Add the superseded-by
  link rather than editing history.

## Repair rules

Fix directly when the evidence is unambiguous: a dead path, a renamed command, a duplicated fact, a
stale commit SHA, a rule glob that matches nothing.

When the evidence is ambiguous, do not guess. Write the uncertainty into the file itself in the form:

```text
Unknown: whether the eight unregistered tool structs are still intended to ship.
Verify: check FoundationModelToolRegistry.createTools against the declared set, then the roadmap row.
```

Report anything you changed and anything you left, and finish by updating the audit date in
`Docs/ai/INDEX.md`.
