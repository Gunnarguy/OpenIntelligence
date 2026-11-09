# OpenIntelligence — Repository Operating Protocol

<!-- Context OS control plane. Detail belongs in Docs/ai/ and Docs/, not here. Keep under 200 lines. -->

Local-first RAG app for Apple platforms, shipping on the App Store. Swift/SwiftUI, one Xcode
project plus a local SwiftPM engine target. Ingestion, indexing, retrieval and ranking run on
device. Only the final answer may optionally reach Apple Private Cloud Compute, after consent.

`AGENTS.md` is the full cross-agent directive list. Claude Code reads `CLAUDE.md` and not
`AGENTS.md`, so the operative parts are restated below. **`AGENTS.md` wins on what any directive
requires; this file governs what to load and when.** Every directive in it is binding as written.
Its rule 15 is the loading rule, restated under "Where things live" below.

`Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` overrides both. Read it before any audit
or documentation pass.

The section below is what every piece of work here serves. It is generated from `Docs/ai/PURPOSE.md`
(edit it there, then run `python3 scripts/sync_purpose.py --write`).

<!-- purpose:begin -->
## Purpose: what this app is, and the owner's rules

OpenIntelligence is a private research librarian for the documents people own. You import any
document, of any size, quality or file type, from a one-page text file to a 1,000-page research
paper full of tables and figures. The app reads it as carefully as a person would, organizes,
imports and embeds it correctly, and then answers questions about it: one document or a library of
50 documents of 50 pages each. Answers come only from what the documents say, extracted
surgically, with the exact passage each one came from. It works offline: in airplane mode
everything works. The network is used only to import a file that is not on the device and, when
the user consents, to send the final answer's generation to Apple Private Cloud Compute. It exists
because most document AI makes people upload their files first, which is the whole problem when the
files are medical, legal, financial, or simply theirs. It is a paid App Store app with a Pro tier,
and its repository is public under MIT, so people can check it.

The owner's rules, in his words (dated quotes in `Docs/ai/PURPOSE.md`). When two conflict, the
earlier one wins. Check every plan against them, and say so when a request or a plan breaks one.

1. **Commercial use only.** Bundle nothing that is not cleared for commercial use: check a model's
   weights licence and the terms of the data it was trained on, and every library and asset. The
   app earns money, so a non-commercial dependency is a defect, whatever its weights tag says.
2. **Offline and private by construction.** Ingestion, indexing, retrieval, ranking and on-device
   answers work with no network at all. Nothing else may need one; routing changes go through the
   hard-boundary files and the owner's approval.
3. **Accuracy first, speed second.** Take a measured accuracy gain even when it costs time. Make
   things faster only through changes that leave answers as accurate, as complete and as well cited;
   Deep Think and Maximum never get shallower to get quicker.
4. **Fidelity on any document.** A 1950s typewritten scan and a table-rich research paper with
   figures must both be read, organized and understood. Losing text, a table cell or a number at
   import is the worst kind of defect, because nothing later can recover it.
5. **Honest answers.** Cite the passage. When the documents do not hold the answer, say so instead
   of guessing. Name defects plainly in release notes and copy; the honesty is the product.
6. **Universal fixes.** This is a general RAG engine. A bad answer is a probe for a general defect:
   fix the layer that caused it and measure on every benchmark set, never patch one file or one
   question type.
7. **Make it work.** A clear refusal of the owner's own file is still a failure. Build the
   capability, using Apple's frameworks.
8. **Apple's models and hardware, used fully.** Generation uses Apple's Foundation Models. Use the
   Neural Engine, GPU, Vision and the system surfaces (Share Sheet, Siri, Shortcuts, App Intents)
   to their full extent. Third-party models are limited to the embedder and the reranker.
9. **Find the better way yourself.** Research current published methods and measure them here
   before guessing. The owner should not have to be the one who suspects there is a better way.
<!-- purpose:end -->

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
   pins, `ChatMessage.swift`, `WorkspaceSyncService.swift` and its `WorkspaceSyncService+*.swift` files,
   `SQLiteFullTextService.swift` schema (in that file; the `+` files hold its queries),
   `BNNSVectorDatabase.swift` format, `EntitlementStore.swift`, `QuotaPolicy.swift` tier limits,
   `RAGAppIntents.swift` shortcut count, `FoundationModelRoutePolicy.swift`,
   `FoundationModelSessionFactory.swift`, `EngineSDKCompatibility.swift`. Reasons in
   `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
5. **Docs move in the same turn as code.** A code change without its matching doc update is an
   incomplete task, not a follow-up. The path-to-doc table is `.agents/rules/01-docs-and-notion-sync.md`.
   `.claude/rules/` restates the parts that apply to files you are actually editing.

## Non-negotiables

- **Never answer "I don't know" about something installed on this machine or published on the web.**
  A knowledge cutoff is a reason to look. Xcode, the SDKs, the simulators and every framework are on
  disk (`find`, `strings`, `plutil`, `--help`); check the local install first, `developer.apple.com`
  second, and never send the owner to look up what is on his own machine.
- Never run destructive git commands. Never `git add .`. Never delete docs.
- **Never delete a benchmark run directory.** `BenchmarkRuns/*` is gitignored, so a deleted run is
  gone permanently, and its `results.jsonl` is the only evidence behind what `LEDGER.md` claims
  about it. Tidy the ledger, never the runs.
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
  Everything else (quality, performance, features, tooling, test coverage) is `Future Backlog`
  unless the user pulls it in; finding a bug is not scheduling it.
- **Fixed is not closed.** A row moves to `Completed` only when its behaviour is verified where the
  defect appeared, which for this app usually means on device. Suite-green closes nothing. Say what
  would close a row at the moment you claim it is fixed.
- **`Status` tracks the work; `Shipped On` tracks reach** (decided 2026-08-28). A verified fix live on
  one platform is `Completed` with `Shipped On` naming that platform; an empty `Shipped On` means
  *not recorded*, never *not shipped*. Detail in the `notion-roadmap` skill.

## Commands

Verified in this repository (build and test from `Docs/ai/RUNBOOK.md`, which records what has and
has not been re-verified):

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "..." --path <path>
python3 scripts/secret_scan.py
scripts/check_icloud_conflicts.sh
python3 .claude/codemap/codemap.py check
python3 scripts/sync_purpose.py --check
bash scripts/build_simulator_smoke.sh
```

Xcode 27.0 (`27A266a`, Swift 6.4) at `/Applications/Xcode.app` is what `xcode-select` points at.
Scheme `OpenIntelligence`, test target `OpenIntelligenceTests`. `xcodebuild test` needs an explicit iOS 27 simulator destination and a
`-derivedDataPath` outside `~/Documents`; the exact invocation is in the runbook's `## Test` section.

## Where things live

| Need | Read |
|---|---|
| Current objective, blockers, exact next action | `Docs/ai/STATE.md` |
| What the project is, scope, constraints | `Docs/ai/PROJECT.md` |
| Component map and which doc owns which area | `Docs/ai/ARCHITECTURE.md` |
| Which file of a split type holds what (RAGService, ChatScreen, DocumentProcessor and 14 more) | `Docs/ai/FILE_MAP.md` |
| Why something is the way it is | `Docs/ai/DECISIONS.md` |
| How to build, test, release, recover | `Docs/ai/RUNBOOK.md` |
| Full agent directives | `AGENTS.md` |
| Tool-neutral pointer for agents that do not read this file | `HANDOFF.md` |
| Evidence and supersession rules, before any audit or docs pass | `Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md` |
| Routing, edit boundaries, release gate | `Docs/RepoOS/` |
| Absolute ground truth on product claims | `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` |
| Subsystem detail | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`, `Docs/RETRIEVAL_PIPELINE.md`, `Docs/INGESTION_PIPELINE.md`, `Docs/PRIVACY_AND_ROUTING.md` |
| Every file at once: which docs still match the code, unused Swift, loose files | the `repo-map` skill, which rebuilds the owner's Repo Map page |
| Which code makes up a feature, and what ties into what | `Docs/ai/codemap/INDEX.md`, then that feature's `features/<id>.json`; the prompt hook prints the slice a prompt names (`AGENTS.md` rule 19) |

Load these on demand. Do not read the documentation set by default. Every task reads `Docs/ai/STATE.md`,
the superseding protocol and `Docs/ai/ARCHITECTURE.md`; the preflight names the rest. Read large
files by section (`grep -n '^## ' <file>`, then that range), never whole: `CHANGELOG.md` (only its
first numbered section is the open release), `Docs/ai/RUNBOOK.md`, `Docs/ai/DECISIONS.md`, the Atlas,
`Docs/INGESTION_PIPELINE.md`. `RAGService`, `AgenticOrchestrator` and fifteen more large types are split by
job into extension files under 2,000 lines each (`RAGService+Import.swift`, `+QueryPipeline.swift`, ...);
`Docs/ai/FILE_MAP.md` says which file holds what. Find a symbol with `grep -n` and read that range; an old
`RAGService.swift:N` citation resolves with `python3 scripts/split_linemap.py`. Moving code between files can
change which declaration a call reaches, or a member's actor isolation, with the build still green: read the
procedure at the end of `BenchmarkRuns/2026-11-05-file-split/OVERNIGHT.md` before doing it again.

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
