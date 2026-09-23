# Handoff

Written 2026-08-22, rewritten 2026-09-20, updated 2026-09-23 against commit `2352aca` on `main`.

This file exists so that whatever picks this repository up next lands somewhere useful without
re-deriving weeks of work. It assumes no particular tool. It is plain markdown, every path in it is
repository-relative, and every external system it names (Notion, git, App Store Connect) is
reachable by anyone with the right login. If your tool has its own instruction-file convention,
`AGENTS.md` is written to be that file regardless of what reads it.

This is a synthesis and a pointer, not a source of truth. Where it restates something that also
lives in `Docs/ai/STATE.md`, `CHANGELOG.md` or `BenchmarkRuns/LEDGER.md`, those files win. Pointer
documents rot faster than the things they point at, and only `Docs/ai/STATE.md` is under standing
instruction to stay current.

## Where the project stands, 2026-09-23

- **5.4 carries every change since 5.3 and is not submitted** (2026-09-23). App Store Connect has
  5.4 in Prepare for Submission on both platforms with build 474 attached. 474 carries the fix for
  build 469's crash at the end of setup (`a713bfc`) and the corrected copy, but not the answer work
  below, so the build to submit is the first Xcode Cloud build of `main` after the copy commit that
  follows `3ad7ed6`, in place of 474. The listing text, review notes, sale promotional text and two
  subscription images are written. At the owner's direction, 5.4's release notes, `WHATS_NEW.md`,
  the user changelog and the in-app What's New cover function and performance only. The owner holds submission
  until a TestFlight check on a device. Build 469 must never be submitted. `Docs/ai/STATE.md` has
  the owner's remaining steps and the release close-out.
- **The answer work of 2026-09-23 is in 5.4**: the Standard end-of-stream stall (19 to 164 s after
  the last word on four measured lookup questions, 0.15 to 0.33 s after the fix), finishing an
  answer early with its sources, off-screen completion signals, and streaming for Deep Think and
  Maximum. It was first pushed under a `## 5.5` heading (`faed0d6`), so Xcode Cloud build 475 went
  to TestFlight as 5.5. The owner put every change since 5.3 in 5.4 the same day, because 5.4 is not
  submitted and App Store Connect has no 5.5; nothing uses build 475.

- **5.3 is live on the App Store on both platforms**, released by the owner on 2026-09-18 from
  build 464 after both platforms were approved. `Docs/SHIPPED_VERSION.json` carries it.
- **5.4 is the open release, and new work goes into it until it is submitted.** `CHANGELOG.md` has
  `## 5.4 <!-- unreleased -->` as its first numbered heading, and `ci_scripts/ci_post_clone.sh`
  stamps every Xcode Cloud build from that heading, so every build from `main` is 5.4. Do not open
  a new version in `CHANGELOG.md` while one is unsubmitted (`Docs/ai/DECISIONS.md`, 2026-09-23).
- **Private Cloud Compute shipped in 5.2 and reaches users today.** Earlier revisions of this file
  said PCC had never reached a single user. That was true when written and is false now. Anything
  describing PCC as staged, pending or compiled out is stale.
- **Xcode 27.0, build `27A266a`, Swift 6.4, is the installed release**, and `xcode-select` points at
  it. The separate beta application no longer exists on this machine, so any command naming that
  path fails. Anything below or elsewhere describing Xcode 27 as a beta is stale.
- **Xcode Cloud has one workflow, `Default`**, pinned to that same Xcode 27 build on macOS
  `Latest Release`, with two archive actions, one per platform, and no test action. It starts on
  pushes to `main` only, and a path filter keeps documentation-only pushes from consuming build
  compute, which matters because this account has hit its compute cap before. There is no GitHub
  Actions workflow directory in this repository; a push starts Xcode Cloud and nothing else.
- **A launch sale is running and expires 2026-09-30.** Lifetime at $39.99. The sale is named in the
  App Store promotional text on the live 5.3 records, in a banner inside the app, and on three
  websites. All three have to be changed after the sale ends. The 5.4 records already carry the
  non-sale wording, so they need nothing. Separately, the live 5.3 text says "33% off", which is
  not true in every storefront; `scripts/asc_fix_listing_copy.rb` corrects it and has not been run.
- **A cold full build can take this Mac down.** It has 18 GB of memory. On 2026-09-20 one full test
  build ran two compiler processes to about 15 GB each; macOS killed hundreds of processes and the
  machine rebooted with nobody there to restart it. Incremental builds are safe. Guard memory on
  any long build. `Docs/ai/STATE.md` fact 6 has the numbers and the guard.
- **Only the iOS 27.0 simulator runtime remains.** 18.0, 18.3 and 26.5 were removed on 2026-09-21,
  with their devices. Test against the iPhone 18 Pro, `25E29FA1-6A22-4A86-AE9F-A6F48411E6D0`.

`Docs/ai/STATE.md` carries the detail behind every line above, including what is still open and who
owns it.

## Read these first, in this order

| # | Read | Why |
|---|---|---|
| 1 | `AGENTS.md` | The rules binding on any agent: the iCloud build trap, the files that may not be edited, task routing. |
| 2 | `Docs/ai/STATE.md` | Current objective, open work, active constraints, exact next action. The freshest file in the repository. |
| 3 | `CHANGELOG.md` | The only version authority here. The first numbered heading is the open release. |
| 4 | The Notion roadmap, below | What is actually planned. Not `Docs/ROADMAP.md`, which drifts and is not authoritative. |
| 5 | `BenchmarkRuns/LEDGER.md` | Every retrieval and accuracy claim this project has made, including the ones that turned out wrong. Read before trusting any number about answer quality. |

`CLAUDE.md` is one tool's loader, but read it anyway if you are not using that tool: a handful of
`AGENTS.md`'s numbered directives describe an audit workflow from an earlier phase of the project,
and `CLAUDE.md` carries corrections to them that `AGENTS.md` alone does not.

## What the product is

A local-first RAG application for iOS and macOS, on the App Store. Ingestion, indexing, retrieval
and ranking run entirely on device, on Apple Foundation Models plus a hybrid vector and BM25
pipeline. Only the final answer may optionally route to Apple Private Cloud Compute, after the user
consents. The claim that matters commercially is that answers are grounded in the user's own
documents and that the app says so honestly. Several of the worst defects in this project's history
were exactly that promise being broken silently.

## The absolute constraints

- **This repository lives in iCloud-synced `~/Documents`.** Builds and tests must run from a copy
  outside it, with DerivedData also outside it, or they hang or fail with codesign errors that make
  no sense. iCloud also writes `Foo 2.swift` conflict copies that Xcode's synchronized file groups
  compile for real. Run `scripts/check_icloud_conflicts.sh --fix` before debugging any build failure
  that looks impossible. `.git` is a file pointing at `.git.nosync` on purpose; do not repair it.
  `AGENTS.md` and `Docs/ai/RUNBOOK.md` carry the exact commands.
- **Never edit these unless the request names the file:** `project.pbxproj`, `*.storekit`,
  `*.entitlements`, `Info.plist` capabilities, `Package.swift` pins, `ChatMessage.swift`,
  `WorkspaceSyncService.swift`, `SQLiteFullTextService.swift` schema, `BNNSVectorDatabase.swift`
  format, `EntitlementStore.swift`, `QuotaPolicy.swift` tier limits, `RAGAppIntents.swift` shortcut
  count, `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`,
  `EngineSDKCompatibility.swift`. The reasons are in `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`.
- **Never delete a directory under `BenchmarkRuns/`.** It is gitignored, so a deleted run is gone
  permanently, and its `results.jsonl` is the only audit trail behind whatever the ledger claims
  about it. This happened once, on 2026-08-19, and destroyed the data behind a figure the ledger
  still cites.
- **Commit to `main`. No branches, no pull requests**, unless asked. One contributor, one line of
  history. Do not add an AI co-author trailer to a commit message; it was removed once already at
  the owner's request.
- **Present a plan and wait for an explicit go-ahead before the first source edit.** The convention
  in this repository is the literal phrase `PROCEED: IMPLEMENT`. If your tool has no equivalent,
  ask anyway. This has stopped at least one bad diagnosis from becoming a bad fix.
- **Roadmap truth is Notion, never `Docs/ROADMAP.md`.** The database is
  `37f49a74-d54f-81b7-9424-dae1288c0043`; the data source URL for API queries is
  `collection://37f49a74-d54f-81b0-92d9-000bce5e05fa`. Open it in a browser if your tool has no
  Notion access. Do not answer a roadmap question from memory, and do not locate the database by
  searching the workspace.
- **The active release is scope-frozen.** A new finding goes to `Future Backlog` unless it loses or
  corrupts user data, makes an advertised capability not work, or blocks the build from shipping,
  and the row has to say which of the three it is. Finding a defect is not the same as scheduling it.
- **Fixed is not closed.** A row moves to `Completed` only when the behaviour is verified where the
  defect appeared, which for this application usually means on a device. A green test suite closes
  nothing.
- **Before removing any factual claim from user-facing copy**, a changelog entry, a document or a
  roadmap row, verify the claim is actually false first. Finding no evidence for a claim is not
  evidence against it. Two claim-removal regressions have happened here. The protocol lives in
  `.claude/skills/oi-claim-audit/`; if your tool cannot read that, the rule is to grep the whole
  repository and check the primary vendor documentation before deleting, not just the one file that
  raised the question.
- **Never report that a command passed unless you ran it and read its output.**

## What is open

`Docs/ai/STATE.md` is the maintained list. In summary, as of 2026-09-22 no code work is outstanding,
and what remains is either the owner's to do outside this repository or a decision nobody has made.

**Most urgent, owner only:** fascinaiting.me serves four internal files publicly, confirmed
2026-09-21: `/CLAUDE.md`, `/ANALYTICS_AUDIT.md`, `/google_ads_config.json` and
`/FACT_CHECK-2026-09.md`. The ads file carries the Google Ads customer ID, every campaign and ad ID,
and all ad copy. The fix is in the Fascinaiting repository, not this one.

Owner, outside the repository: run `scripts/asc_fix_listing_copy.rb`, which corrects the "33% off"
line and both Pro subscription descriptions (they promise unlimited documents and 5 libraries; the
plan is 1,000 and 10); replace the sale promotional text on the live 5.3 records and on the
three websites after 2026-09-30; regenerate the macOS screenshot set, which is the only set still
predating 5.3 and which needs a Screen Recording grant no automated process here has; decide whether
to rename the Lifetime product, which Apple refuses to edit in place because an approved in-app
purchase localization is immutable; and run 5.3 on a device, since nothing in this repository
records a device run against build 464.

Undecided: whether to remove the camera's `#if os(iOS) && DEBUG` gate, which is what releasing that
feature means; what to do about a test that is excluded from every run in prose but by no flag in
any script, and which failed its 60-second timeout again on 2026-09-21, now on iOS 27; and roughly 1.3 GB of build output at the repository root sitting in two directories
that lack the `.nosync` suffix every other build directory has.

Three user-interface fixes recorded on 2026-08-22 asked for device confirmation and this file cannot
say whether they got it: a library picker that reset when switching to or from an empty library, a
glossary navigation fix that the owner did confirm on a phone, and a glossary content
expansion that was only build-verified. The roadmap is the authority on whether those rows closed.

## Findings that should not be re-derived

Measured on the dates given and not re-verified in this pass. `BenchmarkRuns/LEDGER.md` carries the
full reasoning, including conclusions that were retracted with the retraction left in place.

- **The retrieval bottleneck is the context budget, not ranking.** Measured at n=83: the reranker
  puts the right document first in about 61% of cases, MMR selects 30 chunks, and the prompt
  receives a median of 5. Roughly 83% of what retrieval ranks never reaches the model, because five
  chunks of about 2,000 characters fill the on-device 4K-token window. Improving ranking past
  position 5 cannot change an on-device answer. This is why three different fusion weights all
  measured identically, which was a mystery for a week.
- **The accuracy noise floor is about one case at n of roughly 24.** Two runs of identical code,
  differing only in debug verbosity, scored 11 of 24 and 10 of 24. Do not trust an accuracy delta
  smaller than about four cases at that sample size. Per-stage retrieval metrics are far more
  stable.
- **Retrieval is nondeterministic.** Two runs of one build give different evidence and different
  answers, and the cause is upstream of tie-breaking. No A/B comparison of answer quality in this
  repository is trustworthy yet, which is why adaptive generation profiles ship off by default and
  are described as reasoned rather than measured.
- **Temperature 0.4 against 0.7 made no measurable difference** (sign test p=0.938). Greedy
  sampling has never been tested.
- **Rasterisation was never the ingestion bottleneck.** Page render measures 12 to 16 ms per page on
  a live trace, so a multi-hour ingest is Vision recognition. A 2026-09-01 change removed 4.0x
  oversize and 370 MB per page from the macOS path anyway, but do not go looking for speed there.
- **Trace the request the application actually builds before editing OCR settings.** Two OCR changes
  were first applied to a configuration type the live path does not use;
  `StructuredDocumentParser` constructs the recognition request directly.
- **Benchmark runs are archived, not on disk.** Ninety directories, 474 MB, verified byte-identical
  before deletion. `BenchmarkRuns/LEDGER.md` still indexes them and explains how to read one, and
  `BenchmarkRuns/PROGRESSION.md` is a generated table over whatever is on disk.

## What earlier copies of this file got wrong

Listed so that anyone holding a cached or forked copy can recognise it.

- It said Private Cloud Compute had never shipped to a user, and that the App Store listing should
  stop advertising it. PCC shipped in 5.2 and the listing is correct.
- It said Xcode Cloud builds on Xcode 26.6 and that releases must therefore be archived locally.
  The workflow builds on the Xcode 27 release, and releases go through Xcode Cloud.
- It said 5.3 was the open release. 5.3 shipped on 2026-09-18; 5.4 is open.
- It said a push triggers GitHub Actions as well as Xcode Cloud. There is no GitHub Actions workflow
  directory in this repository.
- It carried a Notion snapshot of v5.0 rows from 2026-08-21 and a list of past sessions by title.
  Both were stale enough to mislead and are gone. Query Notion for rows.

## Where deeper history lives

- `BenchmarkRuns/LEDGER.md` for the reasoning behind every quality claim, retractions included.
- `Docs/ai/DECISIONS.md` for why things are the way they are, when that cannot be reconstructed from
  the code.
- `Docs/Release/APP_STORE_METADATA_HISTORY.md` for every version of the store copy since 2.1.1, per
  platform, with live dates, plus the template the next release's notes must match.
- `Docs/ai/RUNBOOK.md` for how to build, test, release, regenerate screenshots and recover.
- The project's agent memory directory on the owner's machine, at
  `~/.claude/projects/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/memory/`. Plain
  markdown, readable by anything with filesystem access. `MEMORY.md` there is an index; each linked
  file is one lesson with a reason and an application. The ones worth reading even if you read
  nothing else are the iCloud one, the nondeterminism one, the tokenizer padding one (a bug that
  silently truncated 55% of every ingested document) and the silent-truncation one (the pattern
  behind several of this project's worst defects: a stage discards data and everything downstream
  still reports healthy).

## If you are picking this up cold

1. Read `AGENTS.md`, then `Docs/ai/STATE.md`.
2. Run `git log --oneline -15` and `git status`. Trust git over any document that may have gone
   stale, this one included.
3. Run the preflight before touching anything. It reports the allowed edit paths, the required tests
   and the required documentation updates for your specific task, and they are binding rather than
   advisory.

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<what you are about to do>"
```

4. If the task touches retrieval, ingestion or any benchmark number, read `BenchmarkRuns/LEDGER.md`
   fully before writing anything down. Most of the wrong conclusions in this project's history came
   from skipping that.
5. Query the Notion roadmap before proposing what to do next. Work that is not on the board is work
   nobody decided to do.
