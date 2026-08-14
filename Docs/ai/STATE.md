# Current State

Updated: 2026-08-14
Branch/worktree: main, primary checkout
Last verified commit: 3b0e6ca

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

None active. The previous objective, **make Deep Think work on a real device**, is complete and
committed. Pick the next item from the recommendations below, or ask the owner.

## Status

Tree clean at `3b0e6ca`, four commits landed on 2026-08-14, nothing unpushed except these four.
Only `main` exists.

- `1127fba` gitignore root-level device log captures
- `ab0fc6d` benchmark harness records stage identities, plus two new scripts
- `7ac2618` the Deep Think fixes
- `3b0e6ca` what the overnight run measured

## Completed

**Deep Think reasoned over section headings instead of document text.** Found in a 29,179 line
console capture from a physical iPhone. Retrieval was healthy (88.5ms, 177 candidates, reranker
0.90 on the right chunk) and the user's query still failed. Two causes, both in
`RAGService.extractRelevantSentences`, which runs *after* the last stage anything measures:
keyword matching had no stemming while FTS5 indexes with `porter unicode61`, and a heading was
required to contain no digits, which excludes every heading in a numbered manual. Sessions received
67 characters against a 3000+ budget. Also fixed: `AgenticOrchestrator`'s fallback tested `isEmpty`
so a degenerate context never triggered it; the model's own instructions were being recorded as
findings and shown to the user; and a rate-limited generation retried once after 2s with an
identical prompt.

**Confirmed on device.** A second capture after the fix shows session contexts of 855, 1468, 850,
242, 252, 252, 242, 899 characters against the previous 106, 123, 67, 53, 167, 111, 67, 67.

**The benchmark harness could not be checked.** `STAGE SOURCES` printed display names, which
`RAGService` only attaches after hybrid search returns, so the five pre-rerank stages logged
`(unnamed)`. It now emits `<chunkId>#<documentId>#<name>` at depth 100, plus a resolved
`ExpectedSourceIds` line.

## Active Constraints

- **No em-dashes anywhere**, including Swift string literals. `USER_CHANGELOG.md` renders in the app.
- **`[Unreleased]` in `CHANGELOG.md` stays empty. New entries go under `## 5.0`.** **v5.0 has NOT
  shipped.** The App Store is on 4.9, confirmed by `Docs/SHIPPED_VERSION.json`
  (`app_store: 4.9`, `preparing: 5.0`, verified against App Store Connect download data) and by a
  device capture reporting `appVersion=4.9, buildNumber=150`. The first numbered heading in
  `CHANGELOG.md` is the release being **prepared**: `ci_post_clone.sh` reads it to stamp
  `MARKETING_VERSION`. A date on that heading does not mean it shipped.
  **The preflight router gets this wrong** and reports `v5.1 (in_development, last shipped v5.0)`.
  `SHIPPED_VERSION.json` names the router and this file as having made exactly that conflation
  before. On 2026-08-14 this rule was "corrected" to the opposite on the router's say-so and the
  entries were moved into `[Unreleased]`; both were reverted the same day. Trust
  `SHIPPED_VERSION.json` over the router, and run `oi-claim-audit` before overturning a rule here.
- **Do not do heavy file work while a benchmark is measuring.** Per-case wall clock moved 40% in one
  run purely from this session's own file copying. See `Docs/EVALS.md`.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay byte
  identical.**
- **Commits must not carry a `Co-Authored-By: Claude` trailer.**
- **Zero call sites is not dead code.** Run `oi-claim-audit` before any removal.
- Hard-boundary files still need the owner to name them. None were touched.

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`, `extractRelevantSentences` around
  line 2900 and the rate-limit backoff around line 15410. Both changed in `7ac2618`.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`, the reasoning-chain context builder
  around line 4020 and `stripPromptEchoAndToolNoise` around line 7300.
- `scripts/sweep_fusion_weight.py`, replays weighted RRF offline from a finished run. Calibrates
  against the app's own recorded `fusion` stage and refuses to print a curve it cannot verify.
- `scripts/compare_runs.py`, pairs two runs on `case_id` with an exact sign test and `--by-category`.
- `Docs/EVALS.md`, the single entry point for anything about measurement. Read it before quoting a
  number.
- `BenchmarkRuns/qasper-overnight` (the 44% baseline) and `BenchmarkRuns/qasper-postfix-20260813`
  (this session's run). Both gitignored; summaries are in `Docs/AuditArtifacts/Benchmarks/`.

## Verification

- `xcodebuild build -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-dd` from `/private/tmp/oi-src` -> **BUILD SUCCEEDED**, run twice, after the extraction fix and again after the backoff fix.
- macOS Debug build for the benchmark -> **BUILD SUCCEEDED**, and the binary was confirmed to carry
  the session's changes by `strings` on `OpenIntelligence.debug.dylib`.
- `python3 scripts/sweep_fusion_weight.py --self-test` -> **OK**.
- 83-case benchmark run -> completed 04:57, summary committed.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 24 tests, OK.
- `python3 scripts/secret_scan.py` -> clean.

**`xcodebuild test` has NOT been run this session.** It was started twice and both runs were killed
by process teardown during SDK setup, before any Swift compiled. The last known figure is 236 / 0
from 2026-08-12, against Swift this session has since changed. **This is the largest open risk.**

## Blockers / Unknowns

1. **The full test suite is unrun against this session's Swift.** Run it first, from a non-iCloud
   copy per `RUNBOOK.md` item 1b. `xcodebuild` deadlocks on this repository's own path.
2. **The run could not resolve whether the extraction fix helps Standard accuracy.** 44.6% to 38.5%
   paired on 65 cases, p = 0.424, against a minimum detectable effect of about 9 points at that
   sample size. Not evidence of regression, not evidence of neutrality.
3. **Seven cases newly failed, six at the 600s ceiling**, five of them inside the window where this
   session's own file copying had the machine at 461s per case. Machine load is the leading
   explanation and is unproven. The secondary hypothesis is the per-subline `headingStems` cost
   added in `7ac2618`; verify by profiling `sentenceScore` or by rerunning on an idle machine.
4. **Notion `Target Release` is `v5.0` on the new rows.** Not v5.1. All of this work is part of the
   release being prepared, and 5.0 has not shipped. The router's `v5.1` is wrong; see the changelog
   constraint above.
5. **Apple Intelligence cannot generate in the iOS Simulator on this machine.** Documented in
   `DECISIONS.md`; the owner has declined the remedy. Do not spend a session on it.
6. **44 verified findings remain on the library surfaces**, in
   `Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`: 3 high, 18 medium, 13 low.

## Exact Next Action

**Run the full test suite**, because this session changed three Swift files and never ran it:

```bash
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude '*.txt' ./ /private/tmp/oi-src/
```

then from `/private/tmp/oi-src`, `xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-dd`. Expect 236 tests. Anything less than 0 failures blocks everything below.

### Then, the highest-value measured opportunity

**Set the hybrid fusion weight to zero.** The sweep found MRR@10 of 0.642 at dense weight 0.00
against 0.550 at the app's effective 0.49, monotonically decreasing to 0.280 at 1.00. That is a 17%
relative gain and it is the largest measured improvement currently available.

The floor that prevents it is `max(0.35, ...)` in `QueryProfile.adjustedHybridWeights`
(`QueryProfileService.swift:50`), whose own comment says the floor "is a product decision and is
deliberately not made here". So it needs the owner's decision, not just an edit.

**Confirm it with one run before changing the default**, because 32 of 68 cases calibrated below 95%
order agreement:

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny --pool-limit 10 --reset-shared-library --vector-weight 0.0 --output-dir BenchmarkRuns/qasper-vw00
```

**Before any run:** `python3 /private/tmp/clean_benchmark_library.py --apply`. The app writes
ingested documents into the real library regardless of `--rag-validation-storage`. A backup of the
owner's library is at `/private/tmp/oi-library-backup-20260813-2219`. A run costs about 4.7 hours
and pins the machine, so ask first.

### Other candidates, in rough order of value

- **Delete the structure/keyword boost stage.** Measured at 22 better, 21 worse, p = 1.0 over 72
  cases. It reorders 43 of them and buys nothing. See `Docs/EVALS.md`.
- **Benchmark Deep Think against Standard.** The only measurement that would have caught this
  session's bug, and it remains unmeasured. Costs roughly 16 generations per case, so scope it to a
  subset.
- **Do not resume `BenchmarkRuns/qasper-vw30`.** The offline sweep answers what it was testing.
