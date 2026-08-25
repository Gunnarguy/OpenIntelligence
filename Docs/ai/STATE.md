# Current State

Updated: 2026-08-25
Branch/worktree: main, pushed and clean as of writing.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: 0e60e3f

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop: PCC does not ship in it and
the notes say so. **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here.

## Status

**v5.0 is 46 Completed against 1 open, and that one row is a device exercise rather than work.**
333 tests, 3 skipped, 0 failures. **The release gate is not on the board: no build is attached to
the 5.0 App Store version.** Metadata is live, correct, and verified against the API — there is
simply nothing to submit.

## Completed this session (2026-08-25)

**Afternoon, after the morning pass below.**

- **`8f76398` / `81fd54b`** The 2026-08-21 PCC claim audit fixed outward marketing and never reached
  in-app copy. Three surfaces still said PCC works today: `ModelInfoCard` gated on the wrong
  capability flag, `HowItWorksView` claimed the app "asks" before escalating, and the **sample
  documents — which the app cites back to users as sourced fact** — carried a section headed *"When
  does PCC activate?"*. Scoped, not deleted, per the precedent that pass set.
- **`93c7a97`** `DECISIONS.md`: the PCC compile-time gate is correct and a runtime gate cannot
  replace it. Settled by **compiling a probe**, not by argument: against the 26.5 SDK the symbol is
  absent, so `if #available` does not merely fail to help — it does not compile. **Read this before
  anyone proposes a runtime gate again.**
- **`ca02b36`** Extracted the rebuild-selection logic, 9 tests, and made `reembedDocuments` call the
  classifier so the tested branch is the shipping branch.
- **`0e60e3f`** Guards that prevent harm no longer log as errors. Of 254 error/warning lines in a
  device capture, 245 were Apple's FileProvider and all 9 of ours were guards working correctly.


- **`0efb2d0`** Research papers were read as parts catalogues. `"min"` inside dopa**min**e made every
  dopamine query a specification lookup; `"ft"` matched "often", `"amp"` matched "example";
  `.caseInsensitive` on an uppercase PartNumber pattern turned `behavior.42` into a part number.
  Word-boundary matching, an anchored standards regex, and a bibliography penalty at both existing
  demotion sites.
- **`11b8d9f`** **The largest finding of the pass.** The extractive evidence re-sort used
  `abs(lhs - rhs) > 0.05` inside its comparator, which is not a strict weak ordering, so
  `sorted(by:)` returned an **unspecified** result. The evidence order behind every extractive
  answer was undefined. It sits exactly where `final` r@1 falls below `rerank`.
- **`19e93d0`** One answer-replacement site had no citation guard (length test only), and it is the
  pass most likely to strip citations because it is told to remove unsupported claims. Separately
  `citationCount` matched `[S1]` but not `(S1)`, so an answer citing in parentheses counted as zero
  and the guard **waved through exactly what it exists to block**.
- **`7851b92`** Self-RAG now retries an answer asserting its sources are silent while citing them.
  Requires a corpus reference **and** an absence phrase in one sentence, so a reported null result is
  not confused with a claim about the corpus. Honest abstention with nothing cited is unaffected.
- **`a78260a`** The background-grant row's premise is **false** — the task is submitted, proven from
  `whatQuery.txt`. Its lifecycle logs moved to a trace-visible category instead of a fix being
  written for a non-bug.
- **`771461c`** Sync churn. 128 store opens / 43,164 chunk records / **0 writes** in one session,
  half before first paint. A signature of both roots plus document set, aliases and strategy now
  skips the reads when nothing has moved. Hard-boundary file, edited under explicit approval.
- **`91ea045`** A library with **no** embedding fingerprint is flagged for rebuild instead of
  silently adopting the live one. `3b48c88`'s nil-adopt was right in August and wrong for release:
  v5.0 is the first build carrying the field, so nil **plus documents** means indexed by the
  pre-5.0 pipeline — 55% of content unembedded (`2753d15`) and CLS pooling (`3ea5cd9`). **Release
  consequence: every user updating from 4.9 with documents sees a one-time rebuild offer.**
- **`a1508d6`** The App Store listing said *"nothing will prompt you to change it"*, which `91ea045`
  made false. Corrected and re-pushed, 3,966 chars, read back from the API and confirmed.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --delete --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' --exclude '.git.nosync/' ./ /private/tmp/oi-src/`
  then build there. In place it deadlocks in `NSFileCoordinator`, including
  `scripts/build_simulator_smoke.sh`.
- **Nothing else builds, tests or runs while a benchmark measures.**
- **Never delete a `BenchmarkRuns/*` directory.** Gitignored, so deletion is permanent. Tidy the
  ledger, never the runs.
- **Core AI does not work in the Simulator** — embeddings are Mac or device only.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay
  byte-identical**; `VersionHistoryTests` asserts it. `WHATS_NEW.md` is a third, condensed copy whose
  bullets are worded differently, so a text match that works on the first two often misses it.
- **`fastlane/metadata/en-US/release_notes.txt` is at 3,966 of 4,000 characters.** Anything added
  needs something removed, and it must not contradict shipped behaviour.
- Commit to `main`; do not branch.

## Working Set

| File | Why |
|---|---|
| `Docs/ai/RUNBOOK.md` → Retrieval benchmark | Items 1, 1b and 7. Item 7 is the one that was skipped and cost fifty minutes. |
| `BenchmarkRuns/LEDGER.md` | Top two entries are the undefined-sort correction and the failed run. Read before trusting any `final`-stage figure. |
| `scripts/run_quality_matrix.py` | `--limit`, `--sampling`, `--manifest`, `--resume`. |
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Hard boundary. Holds the new signature cache; needs the owner to name it in any future approval. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | The nil-fingerprint branch changed by `91ea045`. |
| `fastlane/metadata/en-US/release_notes.txt` | Live App Store text, 34 characters of headroom. |

## Verification

Command → result, this session only:

- `xcodebuild test`, iOS 27 Simulator, from `/private/tmp/oi-src` → **317 tests, 3 skipped, 0
  failures**, run after each of `19e93d0`, `7851b92`, `771461c` and `91ea045`.
- `scripts/build_simulator_smoke.sh` from `/private/tmp/oi-src` → **BUILD SUCCEEDED** each time.
- macOS Debug unsandboxed build → **BUILD SUCCEEDED**; `codesign -d --entitlements -` printed none,
  which is the runbook's precondition for benchmarking.
- `fastlane push_metadata` after `a1508d6` → exit 0; ASC read-back `whatsNew` **3,966 chars**,
  matching the local file exactly.
- `python3 scripts/secret_scan.py` → no sensitive tokens.

**Not run:** any device verification of the afternoon's fixes; any successful benchmark (two
attempts, two different failure modes — see `BenchmarkRuns/LEDGER.md`); any profiling of the
Documents tab.
## Blockers / Unknowns

1. **THE RELEASE GATE, and it is not a Notion row.** The 5.0 iOS App Store version reads
   `state=PREPARE_FOR_SUBMISSION, build=NONE`. An Xcode Cloud build off current `main` is required
   before anything can be submitted. `CURRENT_PROJECT_VERSION` is 150 while Xcode Cloud last built
   356.
2. **A library with no vectors cannot repair itself — the only open v5.0 row.** The code is done
   and now unit-tested (`ca02b36`, 9 cases); the blocked path has never been *exercised* on device.
   **Cheap recipe:** import something large, force-quit around halfway, relaunch. That leaves a
   stuck non-terminal ingestion item, which is exactly the condition. Pass = a rebuild banner that
   stays up, instead of the app logging success and silently re-flagging.
   https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36
3. **Twelve-plus fixes have never been through one ordinary session together** — import, several
   queries, relaunch, more queries, on a build carrying all of them. Each of the last three
   captures found something real, including a regression in 90-minute-old code.

## Open, investigated, NOT diagnosed — do not act on a theory here

4. **Library deletion is reported inconsistent**: same button, sometimes removes the library and
   its files, sometimes only the documents. **The mechanism is unknown.** A first diagnosis — a
   sync merge resurrecting the container — was checked and **refuted**: the container never
   reappeared across 76 subsequent sync operations. Every deletion in `AnotherOne.txt` completed
   correctly, so that capture does not contain the failure. **What is verified:** two delete paths
   exist — `DocumentLibraryView.swift:1653` calls `containerService.deleteContainer` directly,
   bypassing `LibraryDeletion.delete`, though it operates on `localOnlyLibraryIDs` where that may
   be correct — and `deleteContainer` opens with `guard containers.count > 1 else { return }`,
   returning **silently** on the last library. **Get a capture of the failing case before fixing
   anything.**
5. **The Documents tab is slow and the cause is unknown.** Read directly and cleared: the list is
   lazy; the `NavigationLink` destination's init only assigns three stored properties; the row card
   does no per-row I/O; `filteredDocuments` is O(n) over ~14 documents referenced 9 times per
   render; the sync cache runs at an **80% hit rate** (695 skips against 173 opens). **None of that
   explains it.** The only multi-second figures in any capture are ingestion — 48.7s to extract one
   document, ~6s per Vision page — which is import, not navigation. **Three theories were formed
   and all three were wrong.** Next step is measurement, not more reading: Instruments → Time
   Profiler over 30 seconds of tapping between libraries, or elapsed-time instrumentation around
   the container-switch and delete paths.

## Exact Next Action

**Cut an Xcode Cloud build off `main`.** Nothing in v5.0 can proceed without it and it is tracked
nowhere but here.

Then one session on that build: import a document, ask three or four questions of different shapes,
relaunch, ask one more — and separately import something large and force-quit halfway, to stage
Blocker 2. Share the console. That one session closes the last open row and gives the twelve fixes
the ordinary run none of them has had.

**Do not open Blockers 4 or 5 without new evidence.** Between them they have already consumed four
wrong diagnoses; each needs a capture or a profile before any code changes.
