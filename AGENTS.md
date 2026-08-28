# Universal Agent Instructions

This is the top-level universal instruction file for any autonomous agent operating in the OpenIntelligence repository.

**If you are being handed this repository fresh — a new agent, a new tool, or Gunnar himself
returning after a break — read `HANDOFF.md` first.** It has the current project state, what's
proven and what's still open this cycle, and a pointer index into past sessions. This file (and
`GEMINI.md`) governs *how* to work here; `HANDOFF.md` explains *where things stand*.

---

## 🚨 READ THIS FIRST: builds fail here for a non-obvious reason

This repository lives in **iCloud-synced `~/Documents`**. That causes two failure modes that look like code bugs but are not:

**1. If a build fails in a way that makes no sense** — duplicate symbols, "invalid redeclaration", a type declared twice, a codesign *"resource fork, Finder information, or similar detritus not allowed"* error, or git reporting a broken ref name — **run this before debugging anything else:**

```bash
scripts/check_icloud_conflicts.sh --fix
```

iCloud silently writes duplicate files named `Foo 2.swift` beside the original. The Xcode project uses **synchronized file groups**, so that duplicate becomes a real compiled source file. The resulting error points at your code and is completely unrelated to it.

**2. Always build with DerivedData outside `~/Documents`.** Build inputs from the working tree carry iCloud extended attributes and break `codesign`:

```bash
xcodebuild ... -derivedDataPath /tmp/oi-build
```

`scripts/build_simulator_smoke.sh` already handles both and runs the check automatically.

**Do not "fix" `.git` being a file rather than a directory.** It is a `gitdir: .git.nosync` pointer that deliberately keeps the git object store out of iCloud sync, after iCloud corrupted it (four conflict copies of `.git/index` plus a duplicate branch ref). Git works normally. Reverting it re-exposes the repository to corruption.

Background: `.agent/RISK_REGISTER.md` (RISK-20) and `Docs/AUDIT/ROADMAP_RECONCILIATION_2026-07-28.md` (F-02).

---

**CRITICAL DIRECTIVES FOR ALL AGENTS:**

1. Read `GEMINI.md` if running in Gemini/Antigravity.
2. Read `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` before any audit, docs, or implementation work.
3. Read `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` if it exists.
4. Read `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` if it exists.
5. Read the specific playbook for the task at hand (found in `Docs/AgentPlaybooks/`).
6. **Never** modify app source code during audit/governance phases.
7. **Never** run destructive git commands without explicit user approval.
8. **Never** present conceptual relationships as exact code linkages.
9. **Always** include `evidence_level` and `confidence` for architecture/doc claims.
10. **Stop** after the requested phase and wait for explicit verification and instructions before proceeding.
11. **Task Routing:** Read `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md` before any implementation or roadmap update task.
12. **Explicit Approval:** Agents must NOT auto-proceed from planning to implementation without explicit user approval.
13. **Phase 1A Implementation:** If performing Phase 1A Evidence Threads implementation, you must strictly follow `Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md`.
14. **Roadmap & Documentation Updates**: Every phase transition, milestone, task, or codebase feature modification (including Phase 1A, 1B, Core AI, etc.) MUST be documented locally in the repository's main documentation files (`README.md`, `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, `Docs/AppleIntelligenceTransitionPlan.md`, `CHANGELOG.md`, `RELEASE_NOTES.md`, `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, and `Docs/ROADMAP.md`) AND remotely in the OpenIntelligence Notion Roadmap database (Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043`) using Notion MCP tools. The agent must systematically cross-reference and update all these files to eliminate outdated design assumptions (such as local-only paths, obsolete flags, or pre-integration placeholders) and verify warning-free compilation before completing a turn or phase.
15. **Context Building on Startup — SUPERSEDED, kept for history.** This originally required reading `Docs/AppleIntelligenceTransitionPlan.md` and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` at the start of every conversation. `CLAUDE.md` overrode this for Claude Code sessions before this file was corrected to match, because those documents describe a phase-based implementation plan (Phase 1A–1D) that finished; loading them by default on every task added context cost with no benefit once the phases were done. The actual rule, restated here so any agent gets it and not only Claude: **load documentation on demand, based on what the task needs** — `Docs/ai/STATE.md` for current objective and next action, `Docs/ai/ARCHITECTURE.md` for the component map, and the specific playbook or Atlas section the task at hand actually touches. Read the Transition Plan or Atlas in full only when a task is specifically about auditing or extending that phase history.
16. **Atomic Documentation & Diagram Sync**: Whenever any code is modified, the agent MUST immediately, in the exact same response turn, update all relevant documentation to reflect the new state. This includes regenerating any affected architectural CSVs, updating all Mermaid flowcharts in `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, and ensuring 100% perfect-to-code alignment before completing the query. Documentation drift is strictly prohibited.
17. **RepoOS Routing (mandatory)**: Before ANY task, read `Docs/RepoOS/00_REPO_COMMAND_CENTER.md` and `Docs/RepoOS/01_TASK_ROUTER.md`, and match the task to its row in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`. That row's read-first docs, allowed/forbidden edit paths, required tests, and required doc updates are binding. Respect `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md` at all times. In Antigravity, the always-on rules in `.agents/rules/` and the `/update-docs`, `/sync-notion`, and `/finalize` workflows in `.agents/workflows/` implement this automatically.
18. **Workspace Codex Skill (mandatory)**: For every task in this repository, read `.codex/skills/route-openintelligence-work/SKILL.md` and run its deterministic `repoos_router.py preflight` command before planning or acting. Use the preflight's artifact-derived active release for the `CHANGELOG.md` section it names in `documentation_targets.changelog_section` (**not always `[Unreleased]`**: a first numbered heading carrying the `unreleased` marker on its own line is the open section), the matching `Docs/RELEASE_NOTES.md` section, and Notion `Target Release` on every durable implementation. Read the preflight's `state`, not just its `version`. Evaluate Notion relevance on every task; synchronize the OpenIntelligence roadmap at task start and completion whenever the skill marks it required.
