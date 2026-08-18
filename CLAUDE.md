# OpenIntelligence — Repository Operating Protocol

<!-- Context OS control plane. Detail belongs in Docs/ai/ and Docs/, not here. Keep under 200 lines. -->

Local-first RAG app for Apple platforms, shipping on the App Store. Swift/SwiftUI, one Xcode
project plus a local SwiftPM engine target. Ingestion, indexing, retrieval and ranking run on
device. Only the final answer may optionally reach Apple Private Cloud Compute, after consent.

`AGENTS.md` is the full cross-agent directive list. Claude Code reads `CLAUDE.md` and not
`AGENTS.md`, so the operative parts are restated below. **`AGENTS.md` wins on what any directive
requires; this file governs what to load and when.** So its rule 15 ("read the Atlas and the
Transition Plan at conversation start") is superseded by the on-demand loading below, and every
other directive of its is binding as written.

`Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` overrides both. Read it before any audit
or documentation pass.

## Before your first action

1. **Builds fail here for a non-obvious reason.** The repo lives in iCloud-synced `~/Documents`.
   iCloud writes duplicate files (`Foo 2.swift`) that Xcode's synchronized file groups compile for
   real, and stamps extended attributes that break `codesign`. On any nonsensical build failure run
   `scripts/check_icloud_conflicts.sh --fix` **before** debugging code. Always build with
   `-derivedDataPath` outside `~/Documents`. `.git` is a file pointing at `.git.nosync` on purpose;
   do not "fix" it.
2. **Route the task.** Run the preflight (below). It reports the binding read-first docs, allowed
   and forbidden edit paths, required tests and required doc updates for the matched route. Those
   are not advisory. Read its `state` alongside `version`: `in_development` means `last_shipped` is
   already out and new work targets the *next* release, never that one.
3. **Implementation gate.** Present a plan and wait for an explicit `PROCEED: IMPLEMENT` before the
   first source edit. "It is only a log line" is not an exemption.
4. **Hard-boundary files.** Never edit unless the user names the file in their approval:
   `project.pbxproj`, `*.storekit`, `*.entitlements`, `Info.plist` capabilities, `Package.swift`
   pins, `ChatMessage.swift`, `WorkspaceSyncService.swift`, `SQLiteFullTextService.swift` schema,
   `BNNSVectorDatabase.swift` format, `EntitlementStore.swift`, `QuotaPolicy.swift` tier limits,
   `RAGAppIntents.swift` shortcut count, `FoundationModelRoutePolicy.swift`,
   `FoundationModelSessionFactory.swift`, `EngineSDKCompatibility.swift`. Reasons in
   `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
5. **Docs move in the same turn as code.** A code change without its matching doc update is an
   incomplete task, not a follow-up. The path-to-doc table is `.agents/rules/01-docs-and-notion-sync.md`.
   `.claude/rules/` restates the parts that apply to files you are actually editing.

## Non-negotiables

- Never run destructive git commands. Never `git add .`. Never delete docs.
- Never claim a command passed unless you ran it and read the output.
- Every architecture or documentation claim carries `[evidence_level: ..., confidence: ...]`.
- Do not present a conceptual relationship as an exact code linkage.
- Before removing a factual claim from user-facing copy, docs, or the roadmap, use the
  `oi-claim-audit` skill. Withdrawing a true claim has happened here and costs more than leaving it.
- Roadmap truth is the Notion database, not `Docs/ROADMAP.md`. Use the `notion-roadmap` skill; never
  answer a roadmap question from memory, and never locate the database by workspace search.
- **Start substantive work from the roadmap, not from what you just noticed.** Before proposing what
  to do next, read the active-release rows. Work that is not on the board is work nobody decided to
  do.
- **The active release is scope-frozen. New findings default to `Future Backlog`.** A defect only
  gets the active release if it passes one of three tests, and you must say which in the row:
  1. It loses or corrupts user data.
  2. It makes an advertised capability not work.
  3. It blocks the build from shipping at all.
  Everything else — quality improvements, performance, features, tooling, test coverage — is
  `Future Backlog` unless the user explicitly pulls it in. Finding a bug is not the same as
  scheduling it, and conflating those is what makes a release scope grow every time work gets done.
- **Fixed is not closed.** A row moves to `Completed` only when its behaviour is verified where the
  defect appeared, which for this app usually means on device. Suite-green closes nothing. Say what
  would close a row at the moment you claim it is fixed.

## Commands

Verified in this repository:

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "..." --path <path>
```

```bash
python3 scripts/secret_scan.py
```

```bash
scripts/check_icloud_conflicts.sh
```

Build and test, from `Docs/ai/RUNBOOK.md`, which records what has and has not been re-verified:

```bash
bash scripts/build_simulator_smoke.sh
```

Xcode 27 lives at `/Applications/Xcode-beta.app`. Scheme `OpenIntelligence`, test target
`OpenIntelligenceTests`. `xcodebuild test` needs an explicit iOS 27 simulator destination and a
`-derivedDataPath` outside `~/Documents`; the exact invocation is in the runbook.

## Where things live

| Need | Read |
|---|---|
| Current objective, blockers, exact next action | `Docs/ai/STATE.md` |
| What the project is, scope, constraints | `Docs/ai/PROJECT.md` |
| Component map and which doc owns which area | `Docs/ai/ARCHITECTURE.md` |
| Why something is the way it is | `Docs/ai/DECISIONS.md` |
| How to build, test, release, recover | `Docs/ai/RUNBOOK.md` |
| Full agent directives | `AGENTS.md` |
| Evidence and supersession rules, before any audit or docs pass | `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` |
| Routing, edit boundaries, release gate | `Docs/RepoOS/` |
| Absolute ground truth on product claims | `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` |
| Subsystem detail | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, `Docs/PRIVACY_AND_ROUTING.md` |

Load these on demand. Do not read the documentation set by default.

## Context governance

Route durable information to one home and do not copy it across layers:

- Invariant that applies every session → this file.
- Rule that applies only to certain paths → `.claude/rules/`.
- Repeatable procedure → `.claude/skills/`.
- Current execution state → `Docs/ai/STATE.md`.
- Stable project truth → `Docs/ai/PROJECT.md`, `Docs/ai/ARCHITECTURE.md`.
- Rationale that cannot be reconstructed from code → `Docs/ai/DECISIONS.md`.
- Operational procedure → `Docs/ai/RUNBOOK.md`.
- Recurring quirk you learned the hard way → auto memory.
- Broad repository exploration → an isolated Explore subagent, not the main context.
- Parallel write-capable work in this repo → a separate git worktree, created outside `~/Documents`.
  One writer per checkout. Two write-capable sessions in the same checkout will fight.

A subagent that can write inherits every rule in this file. It does **not** inherit an approval:
`PROCEED: IMPLEMENT` is granted to you by the user, not to an agent you spawn, and a subagent may
not touch a hard-boundary file for the same reason you may not. Delegate reading and analysis
freely; delegate edits only inside an approval you already hold, and say so in the subagent's brief.

## Handoff

Before ending substantive work, and when the objective materially changes, run the
`project-handoff` skill so `Docs/ai/STATE.md` stands on its own without this transcript. A fresh
session should be able to open `STATE.md` and take the next action without asking anything.

Do not paste conversation summaries into durable docs. Do not record a test result you did not run.
