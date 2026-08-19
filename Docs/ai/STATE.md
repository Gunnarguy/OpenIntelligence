# Current State

Updated: 2026-08-19
Branch/worktree: main, clean, fully pushed (`HEAD` == `origin/main`).
Last verified commit: e138b31

## Objective

**Get v5.0 shippable.** Two things block it, neither is a code defect, and neither is mine to fix
from here — see Blockers 1 and 2. Everything else on the board is optional for this release.

The week's arc has moved. The embedding work is finished and hardware-verified. **The open question
is now retrieval, not synthesis**, and the instrumentation that answers it is committed and has
never been run.

## Exact Next Action

**Two things, in this order. The first settles a data-integrity blocker and costs whatever three
device imports cost; the second costs 95 minutes and settles a quality one.**

### 1. Does a fresh import still lose its vectors? (three imports, on device)

**This is no longer the two-minute test it was recorded as.** Two of the three cases below require
switching libraries *during* an import, so the cost is set by how long the documents take to ingest,
not by the clicking. `0350083`'s own commit cites a device import at 1 hr 14 min. Pick documents
large enough to leave a window to switch in and no larger. It is still far cheaper than item 2 and
still settles a blocker, so the ordering stands.

Three separate libraries have been found holding documents with **0 chunks** in their vector store —
Library 6, `009866A3`, and `4AF043A3`. `0350083` fixes the suspected cause and has never been
confirmed. Nothing else on the board matters as much as knowing whether it worked.

**Three imports, not two.** `0350083` landed in two places and which one runs is decided by
`RAGService.swift:5569` — `documentType == .pdf && fileSizeMB > 10`. A PDF over 10 MB streams and
hits the fix at `RAGService+Streaming.swift:75`; anything else takes the inline path and hits it at
`RAGService.swift:6125`. A small document also gives no window to switch libraries mid-import, so a
two-step protocol cannot exercise the inline fix under its own trigger.

1. New library, **small document**, no switch. Query it. Baseline.
2. New library, **PDF over 10 MB**, switch libraries mid-import. Tests the streamed fix.
3. New library, **large non-PDF** or a slow scanned PDF under 10 MB, switch mid-import. Tests the
   inline fix.

Vectors land in all three → the fix works, every broken library seen so far is residue, and
[the row](https://app.notion.com/3c149a74d54f81239443c15fe6ae3782) closes. Empty in 2 or 3 tells you
*which* of the two fixes is wrong.

**How to capture it: ask a question after each import and share the trace from the response.** No
Xcode, no cable. The exported trace now carries a `LIBRARY STATE` section with the document count,
the ingested chunk count and the searchable one side by side, the rebuild flag, and the stored
embedding fingerprint against the live one. Documents present with zero searchable chunks is the
failure signature, and it is stated outright in the section. Before this, that line was logged under
`.vectorDB`, which is excluded from `fileLogCategories`, so it reached an attached Xcode console and
nothing else — which is why all three device rows stayed open.

The same capture also answers the fingerprint row, since stored and live appear together, and shows
whether a rebuild is flagged while the store is empty, which is the self-heal row.

**Left behind by `0350083`:** `RAGService.swift:5695` is still `dbForActiveContainer()`. Read-only,
gated on `autoAdaptDimension`, and it loads chunks from whatever library is on screen while
combining them with documents filtered by the captured `activeContainerId` at `:5710` — so switching
mid-import mixes corpora during auto-adapt. Not the vector-loss defect and not data loss, so
`Future Backlog`. Whether a wrong auto-tuned dimension can propagate into a mixed-dimension store is
open and unchecked.

### 2. Run the paired benchmark with tracing (95 min, Mac)

The trace wiring in `ef3fd25` has never executed. Rebuild first — `/private/tmp/oi-mac-40` predates
it, and without a rebuild the run reproduces the same unattributable result.

```bash
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' \
  ./ /private/tmp/oi-src/ && cd /private/tmp/oi-src && \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -scheme OpenIntelligence -destination "platform=macOS" -configuration Debug \
  -derivedDataPath /private/tmp/oi-mac-40 -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

```bash
caffeinate -dimsu \
python3 scripts/run_quality_matrix.py \
  --app /private/tmp/oi-mac-40/Build/Products/Debug/OpenIntelligence.app \
  --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json \
  --pcc deny --pool-limit 10 --reset-shared-library --timeout 1800 \
  --sampling topk --seed 42 --temperature 0.7 \
  --modes deep-think,standard --limit 8 --output-dir BenchmarkRuns/paired-traced
```

**`pool_limit 10` is not optional** — `tokfix` and `coreml-provider` used 10, and standard's 9/25 and
13/25 baselines are only comparable at that value.

**Pass condition:**

```bash
python3 -c "
import json;d=json.load(open('BenchmarkRuns/paired-traced/results.json'))
for m,rows in d['stage_summaries'].items(): print(m,[r['stage'] for r in rows])"
```

`deep-think` must list **seven** stages. Last run it listed one, `final`. If it still lists one, the
build is stale — check that before concluding the fix failed.

Then read where deep-think's recall falls off against standard's. That is Blocker 4.

## Status

`e138b31`, clean, **not pushed** — `origin/main` is at `8791baa`, five commits behind. Nothing running. No background
tasks or monitors left armed.

**Twenty-four commits over two days.** 1,483 insertions across 21 Swift files, plus a regenerated
`main.mlirb`. Six fixes device-confirmed, two shipped and never once executed (Blocker 5).

## The finding that redirects everything

From `BenchmarkRuns/paired-retry`, 8 cases, both modes, `pool_limit 10`, QASPER:

| mode | correct | gold_recall |
| :-- | :-- | :-- |
| deep-think | **2/8 (25%)** | 0.38 |
| standard | **4/7 (57%)**, 1 timeout | 0.57 |

Standard lands on its historical 36%/52% baseline, so the harness measures consistently. This is
**Deep Think's first quality number in the project's history**.

**`correct == (gold_recall == 1.0)` in 14 of 15 scored runs.** Answer accuracy is almost entirely
determined by whether retrieval surfaced the gold document. Neither mode ever produced a right
answer without the evidence, and only once produced a wrong answer with it.

Three consequences:

1. **Synthesis is not the bottleneck and has not been for some time.** The truncation fix, the
   session cap and the SourceOnly budget are all real and none of them can move this number.
2. **Deep Think's retrieval is worse than Standard's**, 0.38 against 0.57, and that gap *is* the
   quality difference between the modes.
3. **Fusion ranks below the lexical arm it fuses**, 0.714 against 0.857 at r@10. The keyword arm
   alone would have retrieved more than the hybrid did. That is an open row, now with numbers.

Do **not** restructure the three-mode design on this. n=8, one corpus, ~21% reproducibility.

## Two hypotheses already refuted — do not re-investigate

Both were formed from source and killed by reading further. Recorded so the next session does not
spend the hour again:

- **Query expansion degrades the lexical arm.** False. `searchWithFTS5` searches `originalQuery`
  (`HybridSearchService.swift:941,947`) and uses expansions only as a fallback when the original
  returns nothing (`:967`). `applyKeywordMatchBoost` also uses `originalQuery` (`:1102`).
- **Expansion replaces the original query.** False, same evidence. The original is filtered out of
  `expandedQueries` at `RAGService.swift:9325`, but that set only feeds the FTS5 *fallback* and the
  supplementary vector searches, never the primary lexical arm.

A third guess was deliberately not attempted. That is what `ef3fd25` is for.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then build there
  with `-derivedDataPath` under `/private/tmp`. In place it hangs in NSFileCoordinator.
- **Nothing else builds, tests or runs while a benchmark measures.** Cost 20 minutes twice.
- **Never `pkill` on the app path.** `oi-mac-40.*OpenIntelligence` also matches the harness, whose
  command line contains `--app /private/tmp/oi-mac-40/...`. That killed a run at case 11 of 16 and
  orphaned the apps it had spawned, which poisoned the *next* run. Match
  `Contents/MacOS/OpenIntelligence`.
- **Core AI does not work in the simulator.** It resolves no model resource and sets
  `isModelLoadingFailed` before attempting a load, so anything touching Core AI is device-only.
- **The benchmark ingests into the real library** and protects pre-existing documents by snapshot.
  It has destroyed documents before. Check `ImportedDocuments` if a count looks wrong; a low count
  in `documents_metadata.json` mid-run is normal transient state.
- Commit to `main`; do not branch. Do not push unless asked.
- Hard-boundary files edited under explicit approval this week: `WorkspaceSyncService.swift`.

## Working Set

| File | Why |
|---|---|
| `scripts/run_quality_matrix.py` | The harness. `reap_orphan_apps` and the pre-run guard are new; read their comments before changing timeout handling. |
| `BenchmarkRuns/LEDGER.md` | Every run, what it settled, and four places analysis was wrong. Read before trusting any figure quoted anywhere else. |
| `Docs/RETRIEVAL_PIPELINE.md` items 12, 18, 19 | Per-stage metrics, the truncation defect, and why the agentic path was unmeasurable. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:18093` | `executeFullRetrievalPipeline` and the trace it now accepts. |
| `Docs/Engineering/V50_PERF_AUDIT.md`, `V50_FLOW_AUDIT.md`, `V50_STAGE1_DIAGNOSIS.md` | Three adversarially-verified audits with refutations recorded. |
| `scripts/run_device_tests.sh` | Runs the suite on a wired iPhone. Read its header before touching signing. |

## Verification

Run and output read, this session:

- `xcodebuild test`, iOS 27.0 iPhone 17 Pro simulator → **238 tests, 2 skipped, 0 failures**. The
  skips are `EmbeddingProviderAgreementTests`, which cannot run in the simulator and **passed on
  device**.
- `BenchmarkRuns/paired-retry` → 16/16 attempted, 1 timeout, **no cascade**. 5,659s wall.
- **Device, self-heal end to end (2026-08-19).** One capture containing both the failure and the
  recovery: detection at line 357, user taps Rebuild at 562, `STARTING FULL REBUILD` at 563,
  **196 chunks embedded in 3.69s (19ms/chunk)** at 585, success at 592, and the same library then
  answers a real question with **20 chunks, 512 words, 94.5s**. Before `116978a` the state at 357
  was silent.
- Same capture: five other libraries logged `already current; skipping rewrite` at 26/182/182/1451/196
  chunks — the sync fix holding across a full session, third confirmation.
- Device: `EmbeddingProviderAgreementTests` → 2 passed on iPhone 16 Pro Max, wired. First device
  test run in the project's history.
- Device, App Launch Instruments → first frame **0.69s**.
- Mac, Foundation Models Instruments → generation is **90%** of a Deep Think query (48.7s of 54.2s).
- `secret_scan.py` clean, `check_icloud_conflicts.sh` clean.
- `build_simulator_smoke.sh` → **BUILD SUCCEEDED**, iPhone 17 Pro simulator. Run because the
  `repoos_workspace_automation` route requires it, not because a shell-script edit could affect it.
- **The preflight's `active_release` was wrong, and both failure directions are now covered by
  tests.** It read `## 5.0 - 2026-08-10` as a shipped release, because it treats the first numbered
  heading in `CHANGELOG.md` as `last_shipped`. That heading is the open section here: all nine
  commits of this cycle filed into it while `[Unreleased]` stayed empty. Ground truth is that v5.0
  has **not** shipped — Notion has 28 open rows against it while every release v4.0 through v4.9 is
  100% Completed, there is no `v5.0` tag, and `RELEASE_NOTES.md` still lists Archive/TestFlight
  validation as pending. Fixed with a `<!-- unreleased -->` marker on the heading. `test_repoos_router.py`
  → **29 tests, OK**, up from 24. The preflight now reports `v5.0 (in_development, last shipped
  v4.9)` and `Changelog target: ## 5.0`. `ci_post_clone.sh` still extracts `5.0` for
  `MARKETING_VERSION`, checked with its own `grep`/`awk` after the marker was added.
- **The session-start hook parser, fixed and measured either side of the change.** Before: the
  parser returned ``ef3fd25—thelastchangetocode.`6cc5e55`and`cfab566`aredocs-only,so`` and the hook
  printed "names a commit not in this repository". After: `ef3fd25`, and drift counted over
  non-`STATE.md` commits gives 0 for `ef3fd25..HEAD` and 1 for `552885e..HEAD`, which contains a
  code commit. The specified pathspec was corrected while applying it: `:(exclude)` resolves against
  the working directory, so the `.`-relative form returns 4 rather than 0 when run from a
  subdirectory. `:(top)` is used instead. `test_repoos_router.py` → 24 tests, OK.

**Not run:** the 25-case benchmark; the traced run above; item 1's three device imports.

## Blockers / Unknowns

1. **The App Store build pins Xcode 26.5**, so no iOS 27 API can ship. Decides what 5.0 can contain.
   [Notion](https://app.notion.com/3bf49a74d54f818cb1bde1b11a0a7557)
2. **PCC entitlement unproven through Archive and TestFlight.** It is advertised, so it has to work
   through the signing path. [Notion](https://app.notion.com/39e49a74d54f81388056f384c4663876)
3. **A fresh import may still lose its vectors, and this is the cheapest open blocker.** Three
   libraries found with documents and 0 chunks. `0350083` fixes the suspected cause and is
   unconfirmed. Not the cause, from the 2026-08-19 capture: the provider/dimension wipe path never
   fired, no provider fallback occurred, and five other stores were intact. So nothing shipped this
   week emptied them — but whether the import bug is dead is unknown.

   **The fingerprint's 0 occurrences of `"Embedding pipeline changed"` is not evidence of anything
   and must not be read as ruling it out.** `3b48c88` shipped the fingerprint and `3ea5cd9`
   re-exported the model with mean pooling, adjacent commits on 2026-08-18. At first launch on a
   build carrying both, every existing library had `embeddingFingerprint == nil`, took the
   silent-adopt branch at `RAGService.swift:4359`, and recorded the *post*-re-export fingerprint
   over *pre*-re-export vectors. The nil-adopt behaviour is deliberate and the row argues for it
   correctly, but it consumed the one event that would have proven the flag works, and it leaves
   those libraries reading healthy while holding stale vectors. Closing that row now needs a
   fingerprint change induced on a library that already carries one — a chunker-recipe change or a
   `modelRevision` bump — because nil-adopt cannot fire twice. Re-importing a library is the
   owner-side fix and takes about two minutes for fifteen documents.
   [Notion](https://app.notion.com/3c149a74d54f81239443c15fe6ae3782)
4. **Deep Think's recall gap is measured but unattributed.** r@10 0.625 against standard's 1.000.
   The instrumented run above is what attributes it.
   [Notion](https://app.notion.com/3bf49a74d54f81d593ddfe700f277f1e)
5. **The engine framework has a macOS install name**, so device tests need
   `scripts/run_device_tests.sh` and its `install_name_tool` workaround. The real fix is
   `DYLIB_INSTALL_NAME_BASE` in `project.pbxproj`, a hard-boundary file.
   [Notion](https://app.notion.com/3c149a74d54f81959f96cef9d1e28dfc)
6. **Two shipped engine changes have never executed anywhere.** The truncation fix
   (`executeDirectSynthesis`, reached only at moderate/low retrieval confidence — three device runs
   all took the reasoning-chain branch) and the SourceOnly prompt budget (`SourceOnly` appeared zero
   times in two captures). Exercising the first needs a query the library covers *poorly*.
7. **Retrieval is ~21% reproducible.** Paired comparison plus the sign test is the only trustworthy
   readout. A single run cannot separate a change from noise.
8. **A long answer outlives its ~30s background grant.** `BGContinuedProcessingTask` is registered
   at `OpenIntelligenceApp.swift:154` with a handler ready and **is never submitted**.
   [Notion](https://app.notion.com/p/3c149a74d54f8171adfcce5dcb345777)
9. **The `Hang detected: N s` lines are not launch cost.** Instruments measured first frame at
   0.69s. Those hangs happen *after* the app is interactive; look at post-launch work.

## Retracted, so nobody acts on them

- ~~A 4-7x performance regression on 2026-08-18.~~ The baselines used `pool_limit 10` and the
  comparison run used 40. `meta.pool_documents` is the *available* pool; `run_config.json`
  `pool_limit` is the per-case ingest. **Always compare `run_config.json`.**
- ~~The sync short-circuit's comparison caused it.~~ Plausible, matched the timing, wrong. The fix
  shipped anyway and is a genuine improvement.
- ~~A benchmark timeout cascades and poisons later cases.~~ `paired-retry` case 14 timed out and
  case 15 completed in 268.9s. The reaper never fired, because `subprocess.run` kills its own child
  and that child *is* the app. The orphans came from a manual `pkill`.
- ~~Timing from any run containing a timeout is suspect.~~ Follows from the above; withdrawn.
- ~~Generation holds no background assertion.~~ It does — `ChatScreen.swift:116` arms
  `RAGQueryHandoff`. The real gap is Blocker 7.
- ~~No watchOS surface exists.~~ Live Activities mirror to Apple Watch automatically; the ingestion
  activity already appears there.

## Roadmap

v5.0: **34 Completed, 8 In Progress, 17 To Do**, verified against the database 2026-08-19.

Three rows closed that day, each against its own stated condition rather than a judgement call:
[external fixtures](https://app.notion.com/3b349a74d54f81478901c122d923dd17) (the pack was built and
`paired-retry` ran against it), [retrieval benchmark
harness](https://app.notion.com/3b149a74d54f813eacd9c035051f553d) (per-stage metrics measured, and
external ground truth delivered by the row above), and [the harness timeout
row](https://app.notion.com/3c149a74d54f817bb929ec79362f3c0f) (a timeout run completed cleanly, and
the pre-run guard was observed reaping and warning about a stale process). That last row's original
diagnosis is refuted and was left standing in the body rather than deleted.

**Neither of the two "device-confirmed" rows is closeable, and an earlier version of this line said
they were.** Read the rows, not this summary; both state their own closing conditions and both fail
them.

- [self-heal](https://app.notion.com/3c049a74d54f81fd9255edc739959d36) covers two defects. "Cannot
  repair itself" is disproven on device. "The repair reports success" has never been exercised,
  because no rebuild in any capture has been blocked. Needs a library with a stuck non-terminal
  ingestion item.
- [embedding fingerprint](https://app.notion.com/3bf49a74d54f812597ffd48a165a139f) closes when a
  device run shows a library flagged after an embedding change and rebuilt from the banner. That
  can no longer happen by the route the row names — see Blocker 3.

Roughly fifteen of the open rows are features and tooling rather than defects. Use the
`notion-roadmap` skill; never answer a roadmap question from memory or from `Docs/ROADMAP.md`.
