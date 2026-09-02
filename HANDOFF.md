# Handoff

Written 2026-08-22, **refreshed 2026-09-02 and current through commit `2154df3`**, because Gunnar expects to run out of Claude usage this
week and wants whatever picks this repo up next — Gemini/Antigravity, Codex, a different tool
entirely, or just himself six months from now — to land somewhere useful without re-deriving three
weeks of work. Nothing here requires Claude-specific tooling to read: it's plain markdown, and every
external system it points at (Notion, git, the App Store Connect UI) is reachable by anyone with
the right login.

This is a synthesis and a pointer, not a new source of truth. Where it restates a fact that also
lives in `AGENTS.md`, `Docs/ai/STATE.md`, or `BenchmarkRuns/LEDGER.md`, those files are what to
trust if this one goes stale — pointer docs rot faster than the things they point at, and nobody is
under instruction to keep this one current the way `STATE.md` is.

## Read this first, in order

| # | Read | Why |
|---|---|---|
| 1 | `AGENTS.md` | Repo rules binding on *any* agent — the iCloud build trap, forbidden files, routing. |
| 2 | `Docs/ai/STATE.md` | Exact current objective and next action, kept current by whoever works here. |
| 3 | This section of this file | The synthesis of everything below, if you don't have time for the rest. |
| 4 | `BenchmarkRuns/LEDGER.md` | Every retrieval/accuracy claim this project has made, including which ones turned out wrong. Read before trusting any number about the app's quality. |
| 5 | Notion roadmap (below) | What's actually planned, not `Docs/ROADMAP.md`, which drifts. |

If you're a coding agent and your tool has its own instruction-file convention (`.cursorrules`,
`.windsurfrules`, whatever), `AGENTS.md` is written to be that file regardless of what reads it.
`GEMINI.md` adds Antigravity-specific wiring on top of it. `CLAUDE.md` is Claude Code's own loader
and mostly says "read AGENTS.md" — but a handful of `AGENTS.md`'s numbered directives (13–16) are
older and describe an audit/governance workflow from an earlier phase of this project that isn't
how work actually happens now; `CLAUDE.md` had already learned to override one of them (item 15)
before this file existed. If you're not using Claude Code, read `CLAUDE.md` anyway for that reason —
it has corrections `AGENTS.md` alone doesn't.

## What this is

OpenIntelligence: a local-first RAG app for iOS/macOS, on the App Store. Ingestion, retrieval and
ranking run entirely on-device (Apple Foundation Models + a hybrid vector/BM25 pipeline); only the
final answer may optionally route to Apple Private Cloud Compute, after consent. The product claim
that actually matters is that its answers are grounded in the user's own documents and it says so
honestly — several defects fixed this cycle were exactly that promise being silently broken.

## The absolute constraints, restated so a fresh tool doesn't have to find them buried in a rules file

- **This repo lives in iCloud-synced `~/Documents`.** Builds and tests must run from a copy outside
  it (`rsync` to `/private/tmp/oi-src`, build there with `-derivedDataPath` also outside
  `~/Documents`) or they hang or fail with nonsensical codesign errors. `AGENTS.md` has the exact
  commands. `scripts/check_icloud_conflicts.sh --fix` before debugging any build failure that makes
  no sense.
- **Never edit without being told, by name, in the current request**: `project.pbxproj`,
  `*.storekit`, `*.entitlements`, `Info.plist` capabilities, `Package.swift` pins,
  `ChatMessage.swift`, `WorkspaceSyncService.swift`, `SQLiteFullTextService.swift` schema,
  `BNNSVectorDatabase.swift` format, `EntitlementStore.swift`, `QuotaPolicy.swift`,
  `RAGAppIntents.swift`, `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`,
  `EngineSDKCompatibility.swift`.
- **Never delete a directory under `BenchmarkRuns/`.** It's gitignored. A deleted run is gone
  permanently and its `results.jsonl` is the only audit trail behind whatever the ledger claims.
  This has happened once already (2026-08-19) and cost real evidence.
- **Commit to `main`. No branches, no PRs, unless explicitly asked.** This is a personal project
  with one contributor; branching has annoyed Gunnar every time it's happened unprompted.
- **No AI co-author trailer in commit messages.** Removed once already, at his request — it reads
  as "100% vibecoded" on a repo whose credibility is the actual product.
- **Adopt an equivalent of the `PROCEED: IMPLEMENT` gate.** This project's convention is: present a
  plan, wait for that literal phrase (or your tool's equivalent explicit go-ahead), before the first
  source edit. It has prevented at least one bad diagnosis from becoming a bad fix. If your tool
  doesn't have a native version of this, ask before editing source anyway.
- **Roadmap truth is Notion, never `Docs/ROADMAP.md`.** The database is
  `37f49a74-d54f-81b7-9424-dae1288c0043`; the data-source URL for API queries is
  `collection://37f49a74-d54f-81b0-92d9-000bce5e05fa`. A snapshot is embedded below in case your
  tool has no Notion access at all.
- **Before removing any factual claim from user-facing copy** (README, App Store description,
  in-app strings, CHANGELOG, a Notion row), verify it's actually false before deleting it. Two
  claim-removal regressions have happened here from someone finding no evidence *for* a claim and
  wrongly treating that as evidence *against* it. `.claude/skills/oi-claim-audit/` has the protocol
  and the specific incidents if your tool can read Claude Code skill files; if not, the rule is:
  check `THIRD_PARTY_NOTICES.md`, grep the whole repo, and check primary vendor docs before you
  delete, not just the one file that prompted the question.

## Current state, as of `2154df3` (2026-09-02)

**Shipped:** iOS **5.0** (approved 2026-08-27), macOS **5.0.2** (approved 2026-08-28). Nothing in
review. **v5.1 is staged, not submitted:** both platform records are in `PREPARE_FOR_SUBMISSION`
with metadata verified against the local files and Xcode Cloud build 432 (commit `845c7b9`)
attached, as of 2026-09-02. It is waiting on the owner's screenshots and a word to submit; the exact
commands are in `Docs/ai/STATE.md`. `Docs/SHIPPED_VERSION.json` is the per-platform record.

**The platforms have diverged and it is the single most load-bearing fact here.** macOS carries
5.0.1 and 5.0.2; iOS never received either. Most of 5.0.1's seventeen entries are cross-platform
fixes that only reached the Mac, so an iPhone user installing 5.1 gets roughly twenty fixes a Mac
user already has. This is why the App Store release notes are per-platform
(`fastlane/metadata/` is macOS, `fastlane/metadata-ios/` is iOS) and why the Notion `Shipped On`
property exists alongside `Status`.

**Roadmap, verified against Notion 2026-09-02:** v5.0 closed at 57 rows, every one `Completed` with
`Shipped On` recorded. v5.1 has 4 rows, all `Completed`, `Shipped On` empty until live. Two rows
were moved to Future Backlog on 2026-09-02 with dated notes: the ingestion pause control (a
feature) and the NSFileCoordinator sync row (real data loss, first in line for the next release,
not started). Future Backlog is 72 rows, all `To Do`.

**The one open row that loses user data** is
[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171),
599 conflict copies observed, untouched. `WorkspaceSyncService.swift` is the highest-leverage file
in the repository: it holds that row *and* the orphan guard behind the idle-churn defect below. It
is Tier-2 hard boundary and needs the owner to name it.

**What landed 2026-08-29 to 09-01, all in build 432. The owner ran a large-PDF ingest on the Mac on 2026-09-02 and reported it working; that is the device evidence, by the owner's word:**

- macOS PDF rendering moved off deprecated `NSImage.lockFocus` and a TIFF round-trip to a
  `CGBitmapContext`. Measured: 4.0x oversize and 370 MB per page removed. **Render was never the
  bottleneck** — it measures 12-16 ms/page on a live trace, so a five-hour ingest is Vision
  recognition, not rasterisation. Do not re-derive this.
- A paused import now reports the pages it already finished. It always resumed correctly; the screen
  said zero, which steered users toward the one destructive action.
- OCR now narrows to the detected language and sets `minimumTextHeightFraction` to 0.004 instead of
  0.0. **Both were first applied to the wrong file** — `OCRConfiguration` is not what the live path
  builds; `StructuredDocumentParser` constructs `RecognizeDocumentsRequest` directly. Trace the
  request the app actually builds before editing OCR settings.
- `VectorStoreRouter.clearAll()` reloads only stores whose files changed. An idle Mac was spawning
  162,712 reload tasks against 76,391 completions — a 53% backlog that grew without bound until the
  app hung after 169 minutes.
- All 20 macOS app icon slots regenerated: they were full-bleed opaque squares where macOS needs
  824-of-1024 inset behind a superellipse, and the dark variant carried the light icon's blue on its
  edges.

**Benchmark runs are archived, not on disk.** 90 directories, 474 MB, in
`~/OpenIntelligence-BenchmarkArchive/BenchmarkRuns-2026-09-01.tar.gz`, verified byte-identical before
deletion. `BenchmarkRuns/LEDGER.md` still indexes them and explains how to read one.

---

## Historical state, as of `e7e51da` (2026-08-22)

*Kept as the record of what was true then. 120 commits have landed since; prefer the section above.*


**v5.0 was re-scoped on 2026-08-21** from 25 open roadmap rows to 11, cut to only what loses data,
breaks an advertised capability, or blocks shipping — the rest moved to Future Backlog, including
the embedding-migration EPIC and WWDC26 API adoption, both previously called top priorities. That
was a deliberate trade for shipping speed, recorded on the affected Notion rows, not an oversight.

**Three UI/content changes happened this session. One is device-confirmed working. One is still
unverified. One is a content expansion built on top of the confirmed fix and only build/test-checked
so far.** The Claude Code iOS Simulator streaming panel crashed and stopped retrying partway through
the first two, so most of this was reasoned from code rather than watched happen; the glossary
navigation fix is the exception, confirmed directly against the owner's physical device.

1. **Library picker resetting to the first library — confirmed stable under general use, the exact edge case still unconfirmed.** A device trace (`Test.txt`, 2026-08-22) shows 21 rapid switches across 7 populated libraries, every chunk count correct, no resets. But none of those libraries were empty, and the bug was specifically about switching to/from an *empty* library. Encouraging, not conclusive — test that specific case before calling this fully closed.
   `documentHeader`, which hosts `ContainerPickerStrip`, was called from both branches of an `if
   filteredDocuments.isEmpty { emptyStateView } else { documentListView }`, so switching to or from
   an empty library tore the picker's `ScrollView` down and rebuilt it at its default scroll
   position. Fixed by hoisting `documentHeader` above the branch (`e1113f7`). The mechanism is
   unambiguous from the code, but nobody has actually tapped through it on a library that starts
   empty since the fix landed. **Do this before assuming it's fine.**
2. **Glossary term taps not navigating cleanly — fixed, and confirmed on the owner's physical
   iPhone.** First attempt (`e1113f7`) moved `.navigationDestination(for: GlossaryTermID.self)` off
   the same `List` that carries `.searchable(text:)`. The owner tested it on device and it did not
   fix it — his exact repro (tap animates to nothing new; the *next* back tap is what reveals the
   real detail; a second back tap is what one correct pop should have done) showed a transition
   running one step behind the navigation stack, not a registration-scope problem. Second attempt
   (`c7f1919`) switched the row taps to `.sheet(item:)` presenting `GlossaryTermSheet` — the same
   mechanism `GlossaryInfoButton` already used successfully everywhere else a term is tappable in
   this app — sidestepping the collision instead of continuing to guess at its mechanism. **The
   owner confirmed this works** ("now tappable and it's like pulling up a card, neat"). If you touch
   `GlossaryView.swift` again: don't put term taps back on push navigation. The sheet pattern is now
   the proven one for this specific screen.
3. **Glossary content expanded from 25 terms to 32, plus two corrections — build/test-verified
   only, not yet read on a real device.** Prompted by the owner asking whether the glossary actually
   covered app-specific concepts or just read as generic. An audit found ~35-40 genuinely undefined
   terms across Settings, chat, and the Atlas/Database tabs; this pass (`e7e51da`) covers the
   highest-confusion subset by the owner's own priority call — quality modes, routing, and the trust
   cluster (confidence vs. fidelity vs. verification gates vs. the abstained badge, which are shown
   together in the response-details screen with nothing previously explaining that confidence and
   fidelity are two different measurements that can disagree). Also corrected the `vector` entry,
   which had hardcoded one embedding provider's dimension count as if it were universal when the app
   switches live between four. A new `trust` `GlossarySection` was added. All 277 tests pass,
   including `GlossaryTests`' orphan-graph and no-em-dash checks, but nobody has scrolled through the
   new entries on an actual screen yet to check for the same two-line-truncation issue the existing
   terms already had to design around. The remaining ~25-30 lower-priority terms (Database/Atlas tab
   jargon, generation-parameter sliders) are unaddressed; see the commit message on `e7e51da` for
   exactly which six areas were audited if you pick that up.

**Whoever picks this up: verify #1 and eyeball #3 on a real device before building further on either
file.** #2 is the one you can trust — it's the only one of the three actually confirmed against
hardware.

**Eight commits are unpushed** as of `e7e51da` (`git rev-list --count origin/main..HEAD` will
confirm the exact count when you read this, since this number moves every commit). Pushing
triggers both GitHub Actions CI and an Xcode Cloud build; see below on Xcode Cloud before pushing
something you want archived.

**Owner-only, blocking several roadmap rows:**
1. **Build `main` to a physical iPhone** and run delete → ingest → query → force-quit → reopen.
   Several data-integrity fixes (a library losing its vector index while keeping its documents —
   the bug behind documents that looked present and answered nothing) are committed and have never
   executed where the defect actually happened. Suite-green does not close these rows; only a
   device run does.
2. **Push the App Store metadata** (`fastlane/metadata/en-US/`) so the live listing stops
   advertising Private Cloud Compute as active — it never has shipped, see below. The push script
   needs `.env.appstore` (gitignored, present locally) and reads `~/Documents/GitHub/ASC/config.json`
   for credentials, which is Gunnar's own analytics tool, not this repo.

## What's been proven this cycle — read before re-investigating any of it

- **PCC has never shipped to a single user, and it's not a code bug.** Xcode Cloud's `Default`
  workflow builds with Xcode Version = "Latest Release", currently **Xcode 26.6**. Every PCC code
  path sits behind `#if compiler(>=6.4)`, which only Xcode 27 satisfies, so it compiles out of every
  App Store build. PCC genuinely works — verified on a local Xcode 27 device archive — it just isn't
  in anything Gunnar has ever submitted. Apple has not shipped an Xcode 27 Release Candidate as of
  this writing, and App Store submissions historically open at the RC, not at a beta. Check
  `developer.apple.com/news/releases` for whether that's changed before assuming it hasn't.
- **Xcode Cloud is compute-capped, and that is the v5.0 release gate.** Runs #376 through #385
  (2026-08-25) were each created and cancelled 5-9 seconds later with `startedDate: null`, never
  scheduled. That is not the workflow's `autoCancel`, because #385 had no successor push to cancel
  it. The last run to produce a build was #375. **Checked 2026-08-25: Xcode 27 is still at beta 6
  (27A5252f) with no Release Candidate**, which answers the standing question in the bullet above.
  So the release must be built locally on **Xcode 26.6**, and `Docs/ai/RUNBOOK.md` carries the
  procedure plus the `nm -u` gate that stops an Xcode 27 archive from shipping PCC. Installing 26.6
  needs Gunnar's password; no agent can do it.
- **The retrieval bottleneck is context budget, not ranking.** Measured at n=83: the reranker puts
  the right document first in ~61% of cases; MMR selects 30 chunks; **the prompt receives a median
  of 5**. Roughly 83% of what retrieval ranks never reaches the model, because five ~2,000-character
  chunks fill the on-device 4K-token window. Improving ranking past position ~5 cannot change an
  on-device answer. This is why three fusion-weight values (0.3/0.5/0.7) all measured identically —
  a real mystery for a week, resolved by this one fact.
- **The accuracy noise floor is ±1 case at n≈24.** Two runs of identical code, differing only in
  debug-output verbosity, scored 11/24 and 10/24. Don't trust any accuracy delta smaller than about
  4 cases at that sample size; trust per-stage retrieval metrics (r@1, MRR) instead, which are far
  more stable — 22 of 24 cases were stage-identical in that same A/A pair.
- **Temperature 0.4 vs 0.7 made no measurable difference** (sign test p=0.938, point estimate
  slightly favored the *lower* temperature doing worse, i.e. no support for "cooler is more
  accurate"). Greedy sampling (0.0) has never been tested — that's still open.
- **Fusion no longer ranks below its own lexical arm** — the defect that row was named for is fixed
  (`guaranteeingLexicalSurvivors`, `89bf928`) and reproduces as fixed across two independent 25-case
  runs.
- **5.0 measurably beats 4.9 on reliability, not yet proven on accuracy.** Paired on 22 identical
  cases: 4.9 scored 6/22 and failed to answer 3 of 25 outright (two 10-minute timeouts, one blank
  response); 5.0 scored 10–11/22 with zero timeouts across 50+ benchmarked cases. The accuracy delta
  alone sits at p=0.06–0.14 — consistent, not statistically proven at this sample size.
- **A benchmark harness bug lost a 5-hour run** (`UnicodeDecodeError` on a truncated multibyte
  character in app stdout, `text=True` without `errors="replace"`) — fixed in `scripts/run_quality_matrix.py`,
  commit `67ba90a`. If you rerun the 4.9 baseline arm, it should no longer die mid-run.

## Where deeper history lives

- **`BenchmarkRuns/LEDGER.md`** — the full, corrected narrative of every benchmark run, including
  retracted conclusions with the retraction left in place rather than deleted. This is the single
  best document if you want the *reasoning*, not just the current-belief summary above.
- **`BenchmarkRuns/PROGRESSION.md`** — a generated table over every run on disk (regenerate with
  `python3 scripts/benchmark_progression.py --out BenchmarkRuns/PROGRESSION.md`), config columns
  included so an invalid comparison is visible rather than silent.
- **This project's Claude Code memory directory** — `~/.claude/projects/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/memory/`
  on Gunnar's machine, plain markdown, readable by anything with filesystem access. `MEMORY.md`
  there is a ~25-line index; each linked file is one lesson with a **Why** and **How to apply**.
  Notable ones if you only read a few: `repo-in-icloud-is-breaking-things.md`,
  `retrieval-is-nondeterministic.md`, `tokenizer-padding-broke-everything.md` (a padding bug that
  silently truncated 55% of every ingested document for a period — the kind of defect that produces
  a plausible-looking constant instead of an error), `silent-truncation-is-the-failure-class.md`
  (the pattern connecting several of this project's worst bugs — a stage discards data and
  everything downstream still reports healthy).
- **Past Claude Code sessions in this repo**, newest first (title, date, archived status) — a human
  or a tool with transcript search can go find the full conversation by title:

  | Date | Title | Archived |
  |---|---|---|
  | 2026-08-22 | Vocabulary explanations in onboarding | no |
  | 2026-08-19 | Memory and handoff documentation | no |
  | 2026-08-17 | Where I left off | no |
  | 2026-08-15 | *(untitled)* | no |
  | 2026-08-11 | App v5.0 UI/UX overhaul | yes |
  | 2026-08-10 | App architecture walkthrough guide | yes |
  | 2026-08-10 | macOS app sandbox signing issue | yes |
  | 2026-08-10 | Session status and context | yes |
  | 2026-08-09 | Session continuation | yes |
  | 2026-08-09 | Claude workspace setup file | yes |
  | 2026-08-07 | Handoff notes and routing verification | yes |
  | 2026-08-07 | App copy and roadmap audit | yes |
  | 2026-08-06 | OpenIntelligence v4.9 next steps | yes |
  | 2026-08-05 | App roadmap discussion (fork) | yes |
  | 2026-08-02 | App roadmap discussion | yes |
  | 2026-07-16 | OpenIntelligence PR audit Phase A (PR #69, merged) | yes |
  | 2026-07-11 | Local commits visibility check | yes |
  | 2026-07-09 | Open Intelligence story and agent verification | yes |

  This session (the one that produced this handoff) isn't in that list because a session can't see
  itself; it's the continuation of everything from roughly 2026-08-19 onward — the disappearing-
  document investigation, the retrieval benchmark buildout, the PCC/Xcode Cloud discovery, and these
  two UI fixes. `CHANGELOG.md`'s `## 5.0` section and `BenchmarkRuns/LEDGER.md` are that session's
  durable output; treat them as more reliable than trying to reconstruct it from the transcript.

## Notion roadmap — v5.0 rows, snapshotted 2026-08-21 (STALE: v5.0 has since closed at 57 rows and v5.1 opened; fetch fresh)

Database `37f49a74-d54f-81b7-9424-dae1288c0043`. Query the data source URL above, or open it in a
browser if your tool has no Notion integration at all.

| Status | Component | Row |
|---|---|---|
| In Progress | Indexing | Existing libraries keep truncated vectors because nothing detects the embedding change |
| In Progress | Indexing | A library with no vectors cannot repair itself, and the repair reports success |
| In Progress | Ingestion | iWork import advertised but can't read any file iWork produces *(copy corrected; code decision — build a parser or leave de-advertised — still open)* |
| In Progress | Ingestion | Switching libraries during an import wrote the document's vectors to the wrong one |
| In Progress | Orchestration | The reasoning chain overruns its own context window and the final draft fails |
| To Do | Ingestion | Two-column PDFs can reach the raw text path, which reads across the columns *(offset bug fixed; symptom attribution still open, see LEDGER)* |
| To Do | Orchestration | Self-RAG accepted an answer that contradicts itself and its own sources at 88% confidence |
| To Do | Orchestration | A long answer outlives its 30-second background grant; the task that would save it is registered but never submitted |
| To Do | Infrastructure | PCC works on device; prove the entitlement survives Archive and TestFlight signing |
| To Do | Infrastructure | The App Store build's Xcode version *(this is now answered — see above — the row needs closing or re-scoping, not more investigation)* |
| To Do | Infrastructure | No test has ever run on a physical device; the engine framework has a macOS install name |

Five of these close or reopen from the single device test in the owner-only list above.

## If you're a fresh agent picking this up cold, do this first

1. Read `AGENTS.md`, then `Docs/ai/STATE.md`.
2. Run `git log --oneline -15` and `git status` — trust git over any doc that might have gone stale
   since it was written, this one included.
3. Run the preflight before touching anything: `python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<what you're about to do>"`. It tells you the allowed edit paths, required tests, and required doc updates for that specific task — binding, not advisory.
4. If the task touches retrieval, ingestion, or benchmark numbers, read `BenchmarkRuns/LEDGER.md`
   fully before writing anything down. Most wrong conclusions in this project's history came from
   skipping that.
5. Verify the two UI fixes above on a real simulator or device before building on top of either file.
