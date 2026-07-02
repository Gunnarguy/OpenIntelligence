# Universal Agent Instructions

This is the top-level universal instruction file for any autonomous agent operating in the OpenIntelligence repository.

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
15. **Context Building on Startup**: At the beginning of any conversation, the agent MUST read `Docs/AppleIntelligenceTransitionPlan.md` and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` to identify which implementation phases are completed and which phase represents the current active target (e.g. Phase 1C).
16. **Atomic Documentation & Diagram Sync**: Whenever any code is modified, the agent MUST immediately, in the exact same response turn, update all relevant documentation to reflect the new state. This includes regenerating any affected architectural CSVs, updating all Mermaid flowcharts in `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, and `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, and ensuring 100% perfect-to-code alignment before completing the query. Documentation drift is strictly prohibited.
17. **RepoOS Routing (mandatory)**: Before ANY task, read `Docs/RepoOS/00_REPO_COMMAND_CENTER.md` and `Docs/RepoOS/01_TASK_ROUTER.md`, and match the task to its row in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`. That row's read-first docs, allowed/forbidden edit paths, required tests, and required doc updates are binding. Respect `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md` at all times. In Antigravity, the always-on rules in `.agents/rules/` and the `/update-docs`, `/sync-notion`, and `/finalize` workflows in `.agents/workflows/` implement this automatically.
