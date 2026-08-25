# Current State

Updated: 2026-08-25
Branch/worktree: main, pushed and clean as of writing.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: cd507d0

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop: PCC does not ship in it and
the notes say so. **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here.

## Status

**v5.0 is 45 Completed against 2 open.** Today's device capture closed the sync churn and Self-RAG
rows on evidence, moved the background-grant row to `Future Backlog` because its admitting premise
was false, and **caught a regression in 90-minute-old code** — `91ea045` was offering a rebuild to
libraries built by the correct pipeline, fixed in `cd507d0`. 317 tests, 3 skipped, 0 failures.

**Both remaining rows need a device action, not code.** Neither is blocked on anything an agent can
do.

## Completed this session (2026-08-25)

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

**Not run:** any device verification of the nine fixes; any successful benchmark.

## Blockers / Unknowns

1. **Fingerprint rebuild has never been run from the banner.** The flag itself is device-proven —
   it fired on 2026-08-25, incorrectly, which is how `cd507d0` was found. What has never been
   exercised is tapping the banner and watching the rebuild finish. Needs a library that genuinely
   predates the fingerprint field; the owner's were stamped by dev builds carrying `3b48c88` and a
   library created on v5.0 is now correctly stamped at ingest, so **neither will flag**. Delete and
   re-import on a build *without* `cd507d0`, or find an untouched pre-5.0 library.
   https://app.notion.com/p/3bf49a74d54f812597ffd48a165a139f
2. **A library with no vectors cannot repair itself.** The only remaining row that is setup rather
   than observation. Needs a staged stuck-queue item so the blocked-rebuild path executes.
   Discriminator: `Self-healing rebuild completed successfully` with **no** preceding
   `[Reembed] STARTING FULL REBUILD` — success reported for work that never ran.
   https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36

**Not a blocker, but the honest risk before cutting a build:** none of the ten fixes from the
2026-08-24/25 pass has been through one ordinary unhurried session — import, several queries,
relaunch — on a build carrying all of them. The 2026-08-25 capture covered one import and one query
and found a regression in code 90 minutes old.

**Agent-side and unclaimed:** the benchmark that would re-take `final` vs `rerank` r@1 has never
succeeded. See the ledger's top entry. Next attempt runs `--limit 2` first.

## Exact Next Action

**Owner: one unhurried session on a build carrying `cd507d0`.** Import a document, ask three or four
questions of different shapes, relaunch, ask one more. Share the trace. That is the pass none of the
ten fixes has had, and today demonstrated it finds things.

If it is clean, the only work left in v5.0 is staging the stuck-queue test for row 2 above.
