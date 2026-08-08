# Docs/ai — agent context index

OpenIntelligence is a local-first, on-device RAG app for Apple platforms, shipping on the App Store.
Ask questions of your own documents and get answers that cite the excerpt they came from.

This directory is the durable knowledge plane for agent sessions. `CLAUDE.md` at the repository root
is the always-loaded control plane and points here. Read on demand, not by default.

| File | Read it when |
|---|---|
| [STATE.md](STATE.md) | Always, before substantive work. Current objective, what is verified, one exact next action. |
| [PROJECT.md](PROJECT.md) | You need scope, constraints, or what this app deliberately does not do. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | You need the component map, or you do not know which doc owns an area. |
| [DECISIONS.md](DECISIONS.md) | Something looks wrong and you are about to "fix" it. Check whether it was decided. |
| [RUNBOOK.md](RUNBOOK.md) | You need to build, test, release, or recover, and want to know which commands are actually verified. |

## Relationship to the rest of the documentation

This directory does not replace anything. It routes.

- `AGENTS.md` is the cross-agent directive list and stays authoritative for agent behavior.
- `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` supersedes every other document. If any doc
  here contradicts it, this one is stale.
- `Docs/RepoOS/` is the routing and change-control layer. Its change-impact matrix is binding.
- `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` is the deep subsystem reference.
- The Notion roadmap database is the source of truth for plans, not `Docs/ROADMAP.md`.

## Maintenance

`Docs/ai/STATE.md` is rewritten by the `project-handoff` skill. The other four change only when the
underlying fact changes. The `project-context-audit` skill checks this directory against the
repository and updates the date below.

Last context-system audit: 2026-08-07
Installed from: [bootstrap/CLAUDE_CONTEXT_OS_V2.md](bootstrap/CLAUDE_CONTEXT_OS_V2.md)
