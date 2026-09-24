# Universal Agent Instructions

This is the top-level universal instruction file for any autonomous agent operating in the OpenIntelligence repository.

**If you are being handed this repository fresh — a new agent, a new tool, or Gunnar himself
returning after a break — read `Docs/ai/STATE.md` first.** It has the current objective, what is
verified, and the one exact next action. `HANDOFF.md` is a short tool-neutral pointer to the same
places. This file (and `GEMINI.md`) governs *how* to work here; `Docs/ai/STATE.md` says *where
things stand*.

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

Background: `.agent/RISK_REGISTER.md` (RISK-20). The reconciliation audit that recorded it as F-02, `ROADMAP_RECONCILIATION_2026-07-28.md`, was written to the gitignored `Docs/AUDIT/` directory and is not in the repository.

---

**CRITICAL DIRECTIVES FOR ALL AGENTS:**

1. Read `GEMINI.md` if running in Gemini/Antigravity.
2. Read `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` before any audit, docs, or implementation work.
3. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` outranks every other document. Read the section the task touches (the preflight's route names it), and read it before writing or changing any product claim. It is not a whole-document startup read (rule 15).
4. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` is the deep subsystem reference. Read the section the task touches (the route names it). It is not a whole-document startup read (rule 15).
5. Read the specific playbook for the task at hand (found in `Docs/AgentPlaybooks/`).
6. **Never** modify app source code during audit/governance phases.
7. **Never** run destructive git commands without explicit user approval.
8. **Never** present conceptual relationships as exact code linkages.
9. **Always** include `evidence_level` and `confidence` for architecture/doc claims.
10. **Stop** after the requested phase and wait for explicit verification and instructions before proceeding.
11. **Task Routing:** the RepoOS preflight (rules 17 and 18) is the task router. `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md` is its first version: its task-class table is superseded by `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`, and its stop conditions are restated in rule 12, so it no longer needs reading before a task.
12. **Explicit Approval:** Agents must NOT auto-proceed from planning to implementation without explicit user approval: present the plan and wait for `PROCEED: IMPLEMENT` before the first source edit.
13. **Phase 1A Implementation — COMPLETE, kept for history.** Evidence Threads Phases 1A–1D are done (`Docs/AuditArtifacts/Implementation/phase_1b_1c_1d_post_implementation_verification.md`). `Docs/AgentPlaybooks/06_PHASE_1A_IMPLEMENTATION_PLAN.md` is a historical record; never re-implement those phases. Evidence Threads changes follow the `evidence_threads_change` route.
14. **Roadmap & Documentation Updates**: Every phase transition, milestone, task, or codebase feature modification (including Phase 1A, 1B, Core AI, etc.) MUST be documented locally in the repository's main documentation files (`README.md`, `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, `Docs/AppleIntelligenceTransitionPlan.md`, `CHANGELOG.md`, `RELEASE_NOTES.md`, `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, and `Docs/ROADMAP.md`) AND remotely in the OpenIntelligence Notion Roadmap database (Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043`) using Notion MCP tools. The agent must systematically cross-reference and update all these files to eliminate outdated design assumptions (such as local-only paths, obsolete flags, or pre-integration placeholders) and verify warning-free compilation before completing a turn or phase. Update the section a change affects; none of these files needs reading whole to do it (rule 15).
15. **Context Building: load on demand, and by section.** On every task read `Docs/ai/STATE.md` (current objective and next action), `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` and `Docs/ai/ARCHITECTURE.md` (the component map and product vocabulary), then only what the preflight's route lists and what the task actually touches. Large documents are read by section, never whole: list the headings with `grep -n '^## ' <file>` and read that range. That applies above all to `CHANGELOG.md` (the open release is its first numbered section; versions before 5.3 are in `Docs/Archive/CHANGELOG_2.0_to_5.2.md`), `Docs/ai/RUNBOOK.md`, `Docs/ai/DECISIONS.md`, the Atlas, and `Docs/INGESTION_PIPELINE.md`. History: this rule originally required reading the Transition Plan and the Atlas in full at every start, for a phase-based plan (Phase 1A–1D) that has finished; that requirement was retired, and on 2026-09-24 the last places still enforcing it (rules 3, 4 and 17, the router's universal list, the Codex skill and `.agents/rules/00-repoos-routing.md`) were brought into line.
16. **Atomic Documentation & Diagram Sync**: Whenever any code is modified, the agent MUST immediately, in the exact same response turn, update all relevant documentation to reflect the new state. This includes updating all Mermaid flowcharts in `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, and ensuring 100% perfect-to-code alignment before completing the query. Documentation drift is strictly prohibited. The CSVs in `Docs/AuditArtifacts/ArchitectureAtlas/` are a July 2026 snapshot whose generators are not in the repository, so they cannot be regenerated; do not hand-edit them into a new "current" state. `python3 scripts/verify_doc_claims.py` checks the paths, symbols, enum cases, anchors and route-table paths the core documents cite.
17. **RepoOS Routing (mandatory)**: Before ANY task, match it to its row in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv` by running the preflight (rule 18), which prints that row. The row's read-first docs, allowed/forbidden edit paths, required tests, and required doc updates are binding. Read `Docs/RepoOS/00_REPO_COMMAND_CENTER.md` and `Docs/RepoOS/01_TASK_ROUTER.md` when the preflight finds no route or the task changes routing itself. Respect `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md` at all times. In Antigravity, the always-on rules in `.agents/rules/` and the `/update-docs`, `/sync-notion`, and `/finalize` workflows in `.agents/workflows/` implement this automatically.
18. **Workspace Codex Skill (mandatory)**: For every task in this repository, read `.codex/skills/route-openintelligence-work/SKILL.md` and run its deterministic `repoos_router.py preflight` command before planning or acting. Use the preflight's artifact-derived active release for the `CHANGELOG.md` section it names in `documentation_targets.changelog_section` (**not always `[Unreleased]`**: a first numbered heading carrying the `unreleased` marker on its own line is the open section), the matching `Docs/RELEASE_NOTES.md` section, and Notion `Target Release` on every durable implementation. Read the preflight's `state`, not just its `version`. Evaluate Notion relevance on every task; synchronize the OpenIntelligence roadmap at task start and completion whenever the skill marks it required.
