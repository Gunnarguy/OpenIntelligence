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
`CLAUDE.md` is the always-loaded control plane and stays under 200 lines. `Docs/ai/` is the durable knowledge plane: `STATE.md` is the cross-session handoff carrying the current objective, what has been verified, and one exact next action, alongside `PROJECT.md`, `ARCHITECTURE.md`, `DECISIONS.md`, and `RUNBOOK.md`. Path-scoped rules in `.claude/rules/` restate this layer's obligations only for the files being edited, so they cost nothing at startup. `.claude/skills/` holds `project-orient`, `project-handoff`, `project-context-audit`, `notion-roadmap`, and `oi-claim-audit`. `.claude/hooks/` injects the startup brief, checkpoints before compaction, and asks for one handoff pass on Stop. Route `repoos_workspace_automation` covers `.claude/**`, `CLAUDE.md`, and `Docs/ai/**`. Installed 2026-08-07 from `Docs/ai/bootstrap/CLAUDE_CONTEXT_OS_V2.md`. `[evidence: code_verified, exact, file existence + hook smoke test + preflight re-run 2026-08-07]`

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
- **G. RepoOS/Codex workflow automation** → Router row 14 → use `.codex/skills/route-openintelligence-work/SKILL.md`; keep Apple app source out of scope.

## Universal hard rules (apply to every task)
No destructive git commands. No `project.pbxproj`, `.storekit`, or `.entitlements` edits without explicit user authorization (`Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md`). No presenting conceptual links as exact code linkage. Tag all architecture claims with evidence_level + confidence. Stop after the requested phase.

Run `.codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight` before planning or acting. The script derives its result from the live change-impact matrix and reports whether the Notion roadmap is relevant, the active release, the `[Unreleased]` changelog target, the matching release-notes section, and the effective required-document union. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`
