---
name: route-openintelligence-work
description: Route and execute work in the Gunnarguy/OpenIntelligence repository through its RepoOS governance layer. Use for every task, question, diagnosis, implementation, audit, documentation update, release check, roadmap change, or file edit in this workspace so Codex selects the owning subsystem, reads the right evidence, respects edit boundaries, runs the required verification, updates documentation, and synchronizes the OpenIntelligence Notion roadmap when relevant.
---

# Route OpenIntelligence Work

Use RepoOS as the workspace navigation graph. Derive routes from live repository artifacts; never replace them with remembered copies.

## Start every task

1. Run the deterministic preflight:

   ```bash
   python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<user request>" --path <path-if-known>
   ```

2. Read the files returned under `read_first_docs` plus the universal startup files in this order:
   - `AGENTS.md`
   - `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`
   - `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
   - `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`
   - `Docs/RepoOS/00_REPO_COMMAND_CENTER.md`
   - `Docs/AppleIntelligenceTransitionPlan.md`
   - `Docs/RepoOS/01_TASK_ROUTER.md`
   - `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`
3. Treat `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv` as the machine-readable route authority.
4. Read the preflight's `active_release` and `documentation_targets`; derive them fresh on every task instead of carrying a version forward from memory.
5. Inspect the real working tree before acting. Preserve unrelated and pre-existing changes.

## Classify the request before acting

- **Answer, explain, review, status, or audit:** remain read-only and report evidence.
- **Diagnose:** identify the cause and evidence; do not implement unless the request includes a fix.
- **Plan:** produce the scoped plan and stop.
- **Implement, fix, create, or change:** present the plan and wait for the repository's implementation approval gate before the first source, configuration, or schema edit. Pure documentation and tests-only work follow their matrix row. If approval is already explicit in the active request, record that fact and stay within its scope.
- **Release or finalize:** run the routed checks, documentation sync, Notion sync, explicit-path staging, and single push confirmation defined by `.agents/workflows/finalize.md`.

If no matrix row matches, do not improvise an edit boundary. Treat the task as config-risk, explain the missing route, and add a new RepoOS route only with implementation approval.

## Use evidence correctly

- Tag architecture and documentation claims with `evidence_level`, `confidence`, and source.
- Prefer current code and canonical documents over historical audit artifacts.
- Never present conceptual relationships as exact call paths.
- Separate historical status from fresh verification.
- Mark blocked verification plainly; never imply an unrun test passed.

## Apply boundaries and verification

- Use the selected row's `allowed_edit_paths`, `forbidden_edit_paths`, `required_tests`, and `required_docs_to_update` as binding.
- Stop if a hard-boundary file is needed but was not named in user approval.
- Never run destructive Git commands, delete documentation, stage with `git add .`, or absorb unrelated working-tree changes.
- Run new helper scripts directly and test deterministic behavior before relying on them.
- Use explicit file paths for staging and final reporting.

## Target release documentation every time

- Every preflight identifies the active release from current repository artifacts, with `Docs/ROADMAP.md`'s `working on vX.Y` marker taking precedence.
- For durable implementation work, update `CHANGELOG.md` under `[Unreleased]` and the active version section reported for `Docs/RELEASE_NOTES.md`, plus the full AGENTS.md rule 14 document set and route-specific docs.
- Use the same active version for the Notion `Target Release` property.
- For read-only, diagnosis-only, pure-docs, or tests-only tasks, still report the targets but do not manufacture empty release-note, changelog, or roadmap edits.
- If the active version cannot be derived exactly, stop before release-document or Notion writes and reconcile the canonical version markers first.

## Decide Notion relevance every time

Evaluate the roadmap on every task; do not blindly write to it.

- **Required:** feature work, bug fixes, implementation phases, milestones, release work, roadmap/backlog changes, or a task already represented in the roadmap.
- **Usually not required:** read-only questions, diagnosis without a fix, transient local investigation, or pure documentation cleanup that closes no roadmap item.
- **When required:** use the exact database and data-source IDs in `.agents/workflows/sync-notion.md`; set `In Progress` at start, then `Completed` with the completion date only after verification succeeds.
- **When unavailable:** report the exact manual payload instead of pretending synchronization occurred.

Read [references/decision-rules.md](references/decision-rules.md) when route selection, approval scope, Notion relevance, or closeout behavior is ambiguous.

## Close the loop

1. Re-run preflight with every changed path.
2. Compare the actual diff against the route boundary.
3. Update the preflight's effective required-doc union. Durable implementations always include `CHANGELOG.md` `[Unreleased]`, the active-version section in `Docs/RELEASE_NOTES.md`, and the full AGENTS.md rule 14 set.
4. Synchronize the Notion row when relevant.
5. Run routed tests, build smoke when required, and secret scanning for new files.
6. Report changed paths, evidence, verification, documentation, Notion status, and the next best move.
