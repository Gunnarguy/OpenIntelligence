# Rule: RepoOS Routing (always on)

You are inside the OpenIntelligence repository. It has a governance layer called RepoOS. You MUST route every task through it — no exceptions, no waiting to be asked.

## On every session start
1. Read `Docs/RepoOS/00_REPO_COMMAND_CENTER.md` (current state, canonical docs, high-risk zones).
2. Read `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` — it supersedes every other doc. If any other doc contradicts it, that doc is stale; do not act on it.
3. Identify the current phase from `Docs/AppleIntelligenceTransitionPlan.md`. Evidence Threads Phases 1A–1D are COMPLETE — never re-implement them.

## On every task
1. Read `.codex/skills/route-openintelligence-work/SKILL.md` and run its `repoos_router.py preflight` command with the user's request and known paths. Record its active release and exact changelog/release-notes targets.
2. Match the task to a row in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv` by `task_type`.
3. That row is binding: read the `read_first_docs`, stay inside `allowed_edit_paths`, never touch `forbidden_edit_paths`, run `required_tests`, and update `required_docs_to_update` in the SAME task — not later, not when asked.
4. Evaluate Notion relevance on every task. Sync the roadmap at start and verified completion when required by the workspace skill and `.agents/rules/01-docs-and-notion-sync.md`.
5. If no row matches, use `Docs/RepoOS/01_TASK_ROUTER.md` route 13 rules (treat as config-risk: stop and ask).

## Hard boundaries (from Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md)
Never edit without the user naming the file in their approval: `project.pbxproj`, `*.storekit`, `*.entitlements`, `Info.plist` capabilities, `Package.swift` dependency pins, `ChatMessage.swift`, `WorkspaceSyncService.swift`, `SQLiteFullTextService.swift` schema, `BNNSVectorDatabase.swift` format, `EntitlementStore.swift`, `QuotaPolicy.swift` tier limits, `RAGAppIntents.swift` shortcut count (9/10 slots used), `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`, `EngineSDKCompatibility.swift`.

## Stop conditions
- Present an implementation plan and WAIT for `PROCEED: IMPLEMENT` before the first source edit.
- Stop and ask if a fix would require touching a hard-boundary file.
- Never run destructive git commands. Never delete docs. Never `git add .`
