# RepoOS 00 — Repository Command Center

One-page operational overview for any agent entering the OpenIntelligence repository. Generated 2026-07-01 from the Architecture Atlas audit artifacts. This layer routes work; it does not supersede `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`.

## What this repository is
OpenIntelligence is a local-first, privacy-preserving RAG application for Apple platforms (iOS/macOS/watchOS surfaces), ~270 Swift components across 30 subsystems. `[evidence: artifact_derived, high, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md]`

## Canonical documents (read in this order)
1. `AGENTS.md` — universal agent directives (rules 1–18; rule 14 mandates doc + Notion roadmap updates on every feature change, and rules 17–18 make RepoOS routing and the workspace preflight mandatory). Claude Code does not read `AGENTS.md`; `CLAUDE.md` at the repository root carries the operative subset for it and routes into `Docs/ai/`.
2. `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` — overrides everything; evidence_level/confidence tagging is mandatory.
3. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` — absolute ground truth; any contradicting doc is stale by definition (§1).
4. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` — subsystem map, boundaries, flows.
5. `Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md` — task classes and the `PROCEED: IMPLEMENT` stop rule.
6. `Docs/RepoOS/01_TASK_ROUTER.md` — this layer's per-task routing (read-first docs, edit zones, tests).
7. `GEMINI.md` — only if running in Gemini/Antigravity.

Do NOT use as source of truth: `Docs/FULL_REPO_*`, `Docs/PRODUCT_POSITIONING_*`, interim delta-repair reports, or raw generated CSVs unless referenced by canonical docs (`Docs/AuditArtifacts/FinalReview/final_canonical_file_index.md` §5).

## Agent context system (Claude Code)
`CLAUDE.md` is the always-loaded control plane and stays under 200 lines. `Docs/ai/` is the durable knowledge plane: `STATE.md` is the cross-session handoff carrying the current objective, what has been verified, and one exact next action, alongside `PROJECT.md`, `ARCHITECTURE.md`, `DECISIONS.md`, and `RUNBOOK.md`. Path-scoped rules in `.claude/rules/` restate this layer's obligations only for the files being edited, so they cost nothing at startup. `.claude/skills/` holds `project-orient`, `project-handoff`, `project-context-audit`, `notion-roadmap`, and `oi-claim-audit`. `.claude/hooks/` injects the startup brief, checkpoints before compaction, records Notion writes, and asks once on Stop for whatever the session left open. Route `repoos_workspace_automation` covers `.claude/**`, `CLAUDE.md`, `Docs/ai/**`, and the enforcement-layer scripts. Installed 2026-08-07 from `Docs/ai/bootstrap/CLAUDE_CONTEXT_OS_V2.md`. `[evidence: code_verified, exact, file existence + hook smoke test + preflight re-run 2026-08-07]`

### Enforcement layer, added 2026-08-28
The obligations above were prose until this date, and prose is what drifted. Six pieces now make them mechanical:

| Piece | Fires | Does |
|---|---|---|
| `scripts/required_docs.sh` | called by the two hooks | resolves changed paths to the documents they require, from the table in `.agents/rules/01-docs-and-notion-sync.md` unioned with the RepoOS change-impact matrix |
| `scripts/verify_doc_claims.py` | git pre-commit, via `enforce_docs_hook.sh` | fails a commit whose documentation no longer matches source: a shipped-version claim contradicting `Docs/SHIPPED_VERSION.json`, an enum case list disagreeing with the Swift enum, a referenced path that does not exist, or a `file.swift:NNN` anchor past end of file. Doc-versus-doc agreement follows for free, since two documents describing one enum are both checked against that enum. Each rule declares a minimum number of claims it must match, so a rewording cannot silently disable a check. Proven to fire by `scripts/test_verify_doc_claims.sh`, which breaks one claim of each kind and asserts a non-zero exit |
| `scripts/enforce_docs_hook.sh` | git pre-commit | fails a commit whose staged source lacks those documents; also enforces the CHANGELOG architecture tag and `ci_post_clone.sh`'s empty-`[Unreleased]` invariant at commit time |
| `.claude/hooks/notion-receipt.sh` | PostToolUse on Notion write tools | records that a roadmap write actually landed, so "did you update Notion?" is answered by evidence rather than recollection |
| `.claude/hooks/stop-handoff.sh` | Stop | asks once per session for the handoff, documentation, and roadmap obligations still open |
| `.claude/hooks/instructions-loaded.sh` | InstructionsLoaded | records which instruction file loaded, why (`session_start`, `path_glob_match`, `compact`, ...) and what triggered it |
| `scripts/instructions_report.sh` | on demand, and from the Stop hook | names any path-scoped rule that governs changed code but never loaded |

What this replaced: the pre-commit hook accepted **any** file under `Docs/` as satisfying **any** Swift change, so a retrieval rewrite committed alongside an unrelated `Docs/ai/STATE.md` edit passed a check named "Full Closed Loop Required". The `InstructionsLoaded` pair answers a different question from the rest. A rule under `.claude/rules/` with `paths:` frontmatter enters context only when Claude touches a matching file; if the glob is wrong the rule never loads, and from outside that is indistinguishable from a session that read the rule and ignored it. Those two have opposite fixes. Verified by `bash scripts/test_enforce_docs_hook.sh` and `bash scripts/test_stop_handoff.sh`, which drive the real scripts against synthetic git indexes and synthetic session baselines. **A second gap, closed 2026-09-01:** those checks enforce that a document is *touched*, never that it is *true*. A claim-by-claim re-read that day found two foundational documents asserting a shipped version eight weeks stale, disagreeing with each other about an enum's cases, and citing paths that no longer existed. All four were mechanically checkable and none was caught, because nothing was checking. `scripts/verify_doc_claims.py` closes that, and `scripts/test_verify_doc_claims.sh` proves it fires rather than merely passing. `[evidence: code_verified + test_verified, exact, 10/10 and 11/11 assertions passing 2026-08-28; instructions-loaded.sh observed firing live with load_reason path_glob_match]`

## Current high-risk subsystems
Per `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` §14 and `Docs/AuditArtifacts/ArchitectureAtlas/subsystem_map.md` (risk = HIGH):

| Subsystem | Anchor files |
|---|---|
| PCC routing/consent | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`, `OpenIntelligence/UI/Components/CloudConsentPromptView.swift` |
| Apple Foundation Models | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/*` |
| iCloud/workspace sync | `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` |
| StoreKit / billing | `OpenIntelligence/Services/Billing/StoreKitBillingService.swift`, `EntitlementStore.swift`, `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit` |
| App Intents/Siri/Shortcuts | `OpenIntelligence/Services/Agentic/RAGAppIntents.swift` (9 of 10 shortcut slots used) |

See `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md` before touching any of these.

## Release / implementation gate status
- `Docs/AuditArtifacts/FinalReview/final_implementation_gate.md` reads "READY FOR PHASE 1A" — **this gate is STALE**. `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` §12 records Phases 0–10 complete, including Phase 9 (Evidence Threads MVP Integration) and Phase 10 (Ingestion & watchOS Live Activity Refinement). Evidence Threads code exists: `OpenIntelligence/Core/Models/EvidenceThread.swift`, `OpenIntelligence/Services/Storage/EvidenceThreadStore.swift`, `OpenIntelligence/Features/Chat/Conversation/ThreadSidebarView.swift`. `[evidence: code_verified, high, file existence check]`
- Treat the FinalReview gate as historical evidence of governance process, not as the current phase pointer. `Docs/AuditArtifacts/ArchitectureAtlas/ARTIFACT_REGISTRY.csv` itself lists the FinalReview files with conflicting statuses (`historical_do_not_use_for_implementation` and `canonical`) — resolved in favor of the canonical source of truth's supersession rule.
- Per `AGENTS.md` rule 15, confirm the current active phase by reading `Docs/AppleIntelligenceTransitionPlan.md` at conversation start.
- Release checklist: `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md`.

## Next-action menu for agents
Pick exactly one; each routes through `Docs/RepoOS/01_TASK_ROUTER.md`:

- **A. Implement / fix code** → Router row for the owning subsystem → produce plan → STOP for `PROCEED: IMPLEMENT`.
- **B. Documentation governance** → `Docs/AgentPlaybooks/02_DOCUMENTATION_RECONCILIATION.md` + `03_CHANGE_IMPACT_DOC_UPDATE.md`; never delete docs.
- **C. Release readiness check** → `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` (read-only verification, no source edits).
- **D. Architecture re-audit / atlas update** → `Docs/AgentPlaybooks/architecture-atlas-update.md`; required before superseding the canonical doc (canonical §16).
- **E. Resolve the stale-gate contradiction** → docs-only task: update `CURRENT_HANDOFF_PACKET.md` and FinalReview registry rows to reflect Phase 10 completion (needs user approval; modifies governance record).
- **F. Anything touching a forbidden boundary** → STOP, present plan, wait for explicit user approval.
- **G. App icon / asset appearance** → Router row 14 → keep the change inside the AppIcon asset catalog and validate with `actool` plus the simulator smoke build.
- **H. RepoOS/Codex workflow automation** → Router row 15 → use `.codex/skills/route-openintelligence-work/SKILL.md`; keep Apple app source out of scope.

## Universal hard rules (apply to every task)
No destructive git commands. No `project.pbxproj`, `.storekit`, or `.entitlements` edits without explicit user authorization (`Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md`). No presenting conceptual links as exact code linkage. Tag all architecture claims with evidence_level + confidence. Stop after the requested phase.

Run `.codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight` before planning or acting. The script derives its result from the live change-impact matrix and reports whether the Notion roadmap is relevant, the active release and its `state`, the changelog target section (which is `[Unreleased]` only when no numbered heading carries the `unreleased` marker), the matching release-notes section, and the effective required-document union. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`
