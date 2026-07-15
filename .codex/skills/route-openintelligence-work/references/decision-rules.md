# RepoOS Decision Rules

Use this reference only when the main skill's route is ambiguous.

## Authority order

1. Current user scope and explicit approval
2. `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md`
3. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
4. `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`
5. `Docs/RepoOS/01_TASK_ROUTER.md`
6. Subsystem playbooks and current code
7. Historical audit artifacts

Higher entries resolve contradictions in lower entries. User approval can authorize a named boundary but cannot authorize destructive behavior prohibited by higher-level system instructions.

## Route selection

Prefer exact changed-path matches over request wording. Prefer `allowed_edit_paths` matches over `likely_files`. Use task keywords only when no path is known. If two routes remain plausible, select the higher-risk route and read both routes' required evidence before narrowing.

If the request spans multiple routes, use the union of read-first documents, forbidden paths, tests, and documentation requirements. The strictest approval and risk level wins.

## Approval scope

An implementation approval covers the plan presented immediately before it. It does not authorize additional subsystems, newly discovered hard-boundary files, publishing, pushing, or destructive operations. Stop when the required solution expands beyond that scope.

## Notion relevance

Treat Notion as the durable product roadmap, not a transcript log.

- Create or update a row for durable product behavior, developer infrastructure that changes the ongoing workflow, bugs being fixed, release work, or milestone transitions.
- Do not create noise for questions, read-only inspections, failed experiments that leave no change, or routine verification with no roadmap consequence.
- Update an existing matching row rather than creating duplicates.
- Mark completion only after required verification and documentation succeed.

## Documentation relevance

Start with the route's `required_docs_to_update`, then union path-triggered documentation from `.agents/rules/01-docs-and-notion-sync.md`. Apply the full `AGENTS.md` rule 14 set to a feature or milestone. Do not edit canonical claims unless current evidence supports the new state.

Derive the active release during every preflight. Durable implementation entries go under `CHANGELOG.md` `[Unreleased]` and the matching active-version heading in `Docs/RELEASE_NOTES.md`; the same version is the Notion `Target Release`. Read-only and transient work reports these targets without creating documentation noise.

## Closeout states

- **Complete:** implementation, required docs, relevant Notion sync, and required verification succeeded.
- **Partial:** useful work landed but a stated verification or external sync remains unconfirmed.
- **Blocked:** the same external blocker prevents meaningful progress after the required repeated checks.
- **Read-only complete:** the requested report or diagnosis is delivered without implementation.
