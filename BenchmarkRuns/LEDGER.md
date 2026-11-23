# Benchmark run ledger

> **The run directories this ledger indexes are archived, not on disk. Archived 2026-09-01 at the
> owner's instruction.** 90 directories, 1,374 files, 474 MB, including all 53 `results.jsonl`, are
> in `~/OpenIntelligence-BenchmarkArchive/BenchmarkRuns-2026-09-01.tar.gz` (59 MB). The archive was
> verified before deletion: file count and `results.jsonl` count matched disk exactly, `gzip -t`
> passed over every member, and five randomly chosen `results.jsonl` compared byte-identical against
> the originals, the largest at 18 MB. **Every row below still refers to a real run**; to read one,
> extract it rather than assuming it is gone. `LEDGER.md` and `PROGRESSION.md` are the only tracked
> files in `BenchmarkRuns/` and were deliberately left in place.
>
> **2026-09-29: two later runs are on disk and not in that archive.** They are
> `BenchmarkRuns/2026-09-23-sourceonly-before-greedy25/` and
> `BenchmarkRuns/2026-09-23-sourceonly-after-greedy25/`, the pair in the 2026-09-23 entry below, which
> names them without the `2026-09-23-` prefix. Like every run they are gitignored (`.gitignore:34`), so
> a fresh clone has neither. The archive also carries its own 2026-09-01 copies of
> `BenchmarkRuns/LEDGER.md` and `BenchmarkRuns/PROGRESSION.md`, so extracting it at the repository root
> overwrites both tracked files; exclude those two members
> (`--exclude 'BenchmarkRuns/LEDGER.md' --exclude 'BenchmarkRuns/PROGRESSION.md'`, which drop exactly
> those two when listed with `tar -t`). `[evidence_level: measured, confidence: exact, evidence_source:
> ls BenchmarkRuns; tar -tzf of the archive (1,628 members, 53 results.jsonl, none named sourceonly);
> git check-ignore -v on both runs' results.jsonl; read 2026-09-29]`
>
> `.gitignore:34` is `BenchmarkRuns/*` with `LEDGER.md` and `PROGRESSION.md` negated back in, so the
> run contents are ignored and were never recoverable from git. Checking `git check-ignore
> BenchmarkRuns` on the *directory* reports "not ignored" and is misleading; the pattern targets the
> contents. That distinction is worth knowing, because it is how three runs were lost on 2026-08-19.


`results.jsonl` records **what happened**. It does not record **what the run was testing, against
which commit, or what it settled**. Sixty-two run directories existed before this file with none of
that, which makes them unreadable a week later and impossible to sequence work from.

One row per run. Add the row when you launch, fill the verdict when it lands. A run with no row is
indistinguishable from a run nobody learned anything from.

`run_config.json` does **not** capture the commit or the embedding provider. Until it does, both go
in this table by hand.

---


## 2026-09-23: `sourceonly-before-greedy25` / `sourceonly-after-greedy25` — no accuracy loss from skipping the source-only check on passing Standard answers; the higher after-score is not attributable to the change

**Intent.** A/B for the 5.4 change that stops Standard running `SourceOnlyAnswerService` on answers
the nine verification gates passed (`RAGService.standardSkipsSourceOnlyCheck`). The check is two
structured model calls after the last word; on four HOW_IT_WORKS lookups it had held a finished
answer 19.4 to 163.8 s and changed none of them. The question here is whether skipping it costs
correct answers.

**Configuration.** Identical for both: macOS Debug, unsigned (entitlements empty), built from
`/private/tmp/oi-src`, `SWIFT_DETERMINISTIC_HASHING=1`, `--manifest
Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny --sampling
greedy --pool-limit 10 --top-k 3 --limit 25`. Before: working tree at `2e3ab4a` (app frozen to
`/private/tmp/oi-bench/before`). After: `2e3ab4a` plus the uncommitted working tree of 10:05
(app `/private/tmp/oi-bench/after-all`; includes the streaming and UI work, which does not touch the
Standard path the harness runs except the skip and the structured-answer streaming, and no case
here was small enough for the structured path).

**Outcome.**

| | before | after |
| :-- | --: | --: |
| correct, 25 cases | 6 | 11 |
| correct, 18 cases without the environment fault below | 6 | 9 |
| pass to miss | | 0 |
| source-only ran / replaced an answer | 5 / 0 | 2 / 0 |
| source-only skipped, gates passed | | 7 |
| hallucinated (report table) | 1 | 1 |

**Why the after-score is not the change's doing.** (1) Seven consecutive before cases (9 to 15 by
run order, papers 1604.02038, 1911.04474, 1905.00840, 1810.02229, 1805.11937) logged
`SensitiveContentAnalysisML error 15` from Foundation Models, up to 130 times each, during ingestion
summaries, tagging and query-time calls, and all seven missed; case `6e040e80` assembled 743
characters of context against 9,333 after. The after run logged the error zero times. The episode
overlapped this session's builds, which is a plausible trigger, not an established one. (2) The three
flips among the clean cases (`3319d565`, `57ee20f4`, `f54e19f7`, all miss to pass) each assembled a
different context before generation (7,654 vs 7,641; 9,455 vs 9,454; 9,370 vs 9,441 characters),
upstream of any changed code: the retrieval nondeterminism recorded in older entries below. Three one-directional
discordant pairs give a two-sided sign test p of 0.25. (3) The source-only check replaced no answer
in either run, so skipping it cannot have changed a verdict here; in the before run every answer it
ran on still carried the model's own `[S#]` markers.

**Verdict.** No accuracy loss detected: zero pass-to-miss cases, and the check being skipped changed
nothing in this sample. Not established: whether the check ever corrects a passed Standard answer on
a larger or different corpus. The before run's error episode means its 6/25 is not a clean baseline
for anything else.



## 2026-08-25: `20260825-postfix-greedy-83` — failed, every case timed out, cause not attributed

Recorded rather than deleted, per the standing rule, and recorded as **failed** so nobody reads the
directory as evidence of anything.

**Intent.** Re-take `final` vs `rerank` r@1 on a build containing `11b8d9f`, which made the
extractive evidence re-sort deterministic. Every `final`-stage figure in this ledger was measured
against a comparator whose output was undefined, so the 27.0%/15.2% attribution above needs
re-taking before it is trusted or acted on.

**Configuration.** macOS Debug, unsandboxed, built from `/private/tmp/oi-src`, entitlements
confirmed empty. QASPER `qasper_external_v1`, 83 cases, `--modes standard --pcc deny
--sampling greedy`. Commit `91ea045`.

**Outcome.** Cases 1 through 5 each returned `ERROR: timeout after 600s`; the run was killed during
case 6 when the session ended. No `reports/` were written, so there is no per-case stdout and
**nothing attributes the hang**.

**Ruled out.** The sandbox cause the runbook documents first: zero occurrences of
`have permission to save`, and `codesign -d --entitlements -` printed none. No other error of any
kind appears in the harness log.

**Not established.** Whether Foundation Models generation completed. The 600s figure matches the
runbook's recorded shape exactly — the agentic path retrying eight reasoning sessions is "the ten
minutes" — but that passage concerns the **Simulator** and states the host Mac generates real text.
Attributing this to FM without per-case output would be a guess, and this project has spent four
wrong root causes this week on exactly that move.

**Process failure worth recording.** Runbook item 7 says run six cases before eighty three, for this
reason. Eighty three were launched directly. The discipline exists because a broken configuration
should cost ten minutes, and this cost about fifty.

**Next attempt must**: run `--limit 2` first, capture per-case stdout, and attach
`scripts/watch_benchmark_defects.sh` so a failure shape is visible as it happens rather than after.

`[evidence_level: run_artifact_verified, confidence: exact_for_the_failure, cause_unattributed]`

---

## 2026-08-24: the `final` vs `rerank` r@1 figures were measured against an undefined sort

Recorded at the top because it affects how every `final`-stage number in this ledger should be
read, and because the correction is not visible from any run directory.

`RAGService`'s extractive evidence re-sort used `abs(aPriority - bPriority) >= 2` inside its
comparator. That predicate is not a strict weak ordering — with priorities 5, 4 and 3 the inner
pairs compare equal while the outer pair compares ordered — and `sorted(by:)` is documented as
producing an **unspecified** result when given one. The final evidence order was therefore
undefined, not merely debatable.

**Consequences for what is written below.** The `shipcfg-50` account attributing rank-1 loss of
27.0% where the re-sort fires against 15.2% where it does not was computed over that undefined
ordering, so the figure characterises the sort's arbitrary output rather than the scoring policy.
It should be re-taken on a build containing `EvidenceScoringPolicyService.extractiveEvidencePrecedes`
before the proposed tie-break experiment is run, because that experiment was designed to test a
hypothesis the measurement cannot currently support.

`final` r@1 0.442 against `rerank` r@1 0.610 at n=83 remains the observation worth explaining. An
undefined sort at exactly the stage where rank 1 degrades is a better candidate than any scoring
hypothesis, and it is now removed. Whether it was the whole cause is open.

No run directory was modified. `[evidence_level: code_verified, confidence: exact_for_the_defect,
retrieval_effect_unmeasured]`


## 2026-08-19: the overnight run that found a regression instead of a number

Ran to measure whether the reasoning-chain session cap (`e16a2d3`) changed answer quality. It never
got that far. What it found is worth more.

| run | commit | tests | verdict |
| :-- | :-- | :-- | :-- |
> **The `overnight-smoke`, `overnight-paired` and `timing-check` directories were deleted on
> 2026-08-19 while tidying, before anyone had re-read them.** `BenchmarkRuns/*` is gitignored, so
> they are not recoverable. The figures in the three rows below are therefore **unauditable**: the
> conclusions survive, the raw `results.jsonl` behind them does not. Treat the smoke's 1/5 and its
> three `gold_recall` zeros as reported-once and unverified, especially given this same run was
> misread twice on the night. Do not delete a run directory until its row cites nothing that would
> need re-checking.

| `overnight-smoke` | `0eb5d96` | 6 cases, deep-think, pool 40, QASPER. First Deep Think benchmark ever attempted. | **1/5 correct, 1 timeout at 1800s, ~900s/case.** `gold_recall` **0.0 on 3 of 5** — retrieval never surfaced the expected document. Gate aborted the full run, correctly, but **reported 0/6 when the truth was 1/5**: it read `answer_accuracy`/`pass`/`status`, none of which exist. The schema is `score.correct` with `patterns_hit`/`patterns_total`. Right call, wrong arithmetic. |
| `overnight-paired` | `0eb5d96` | 10 cases x {deep-think, standard}, pool 40. | **Killed at case 2.** Deep Think case 1 timed out at 1800s having taken 1242s in the smoke an hour earlier. Then **standard** timed out too, and standard does one generation, so this was not session-count variance. |
| `timing-check` | `025b912` | 2 standard cases, pool 40, after the comparison fix. | **925s/case, unchanged.** The fix moved nothing, which is what exposed the premise as wrong rather than the code. |
| `paired-pool10` | `025b912` | 8 cases x {deep-think, standard}, **pool_limit 10**, matching `tokfix` and `coreml-provider` exactly. | **Failed at case 11/16. One scored pair out of eight.** Case 1: deep-think **miss** at 256.9s / 7 generations, standard **PASS** at 197.2s / 1 generation, both `gold_recall` 1.0 — retrieval found the document and only Deep Think failed to answer from it. Cases 2-5 all timed out in both modes. Confirms cost is linear in pool size (256.9s here against 1242s for the identical case at pool 40) and nothing else. |

### What this arc settled

- **There was no regression. The comparison was invalid.** `tokfix` and `coreml-provider` ran with
  **`pool_limit: 10`**; tonight ran with **`pool_limit: 40`**. Four times the corpus ingested,
  embedded and indexed per case. 269s → 925s is roughly linear in pool size and is the expected
  cost of the configuration, not a defect.
- **The error was reading the wrong field.** `meta.pool_documents` is the size of the *available*
  fixture pool. `run_config.json` `pool_limit` is what each case actually ingests. They are both 40
  in tonight's run and 40 vs 10 in the baselines, so the meta field looked like a match and was not.
  **Check `run_config.json`, never `meta.pool_documents`, before comparing two runs.**
- **A plausible mechanism that matches the timing is not evidence.** The sync short-circuit's
  comparison was O(chunks x 384) per pass, scaled with corpus size, and had shipped that same day.
  Every part of that was true and it explained nothing, because there was nothing to explain. The
  fix went in anyway and stands on its own merits; it did not change the timing at all, which is
  what should have prompted the config check an hour earlier.
- **A pilot's 3/3 pass was worthless as a Deep Think baseline.** `run_deepthink_pilot.sh` passes no
  `--manifest`, so it silently used `tiny_research_suite`, not QASPER. Different corpus, different
  difficulty.
- **Deep Think at pool 40 costs roughly 900-1800s/case on an unoptimised Debug build**, against
  ~80s on device for a comparable query. A 25-case paired run is therefore a 12+ hour job, not an
  overnight one. Either run at `pool_limit: 10` to match the existing baselines, or budget two
  nights.

### CORRECTED 2026-08-19 10:30: a timeout does not cascade. I caused the cascade.

The `paired-retry` run settles it. **Case 14 timed out at 1800s and case 15 completed normally in
268.9s.** A timeout does not poison what follows.

The reaper added in `9aed4cf` **never fired** — zero reap events across the whole run. That is
correct behaviour, and it shows the original diagnosis was wrong: `subprocess.run(timeout=)` kills
its direct child, and the direct child *is* the app binary, because the harness launches it
directly. On a clean timeout the app dies on its own and there is nothing to reap.

So where did the two 4.5-hour-old processes come from? **From me.** I ran `pkill -f run_quality_matrix`
during the timing-check, which killed the harness and orphaned the apps it had spawned. Those
orphans then held the shared library and every case in the next run blocked behind them.

The fix that actually matters is therefore not the reaper but the **pre-run guard**, which asserts a
clean slate and warns if it finds one. It catches contamination from any source, including a human
killing a job. The reaper stays as a cheap safety net for the case where the app outlives its
parent for some other reason.

**Two mis-attributions on the same defect in one night.** First the sync comparison, then the
timeout mechanism. Both were plausible, both matched the symptom, and both were wrong. The pattern
is reasoning from mechanism and stopping before the measurement that would separate the candidates.

### Superseded: the original diagnosis

Case 1 completed in both modes. Everything from case 2 onward timed out, including standard mode,
which had just answered case 1 in 197s. That is not variance, it is state.

Two `OpenIntelligence` processes were found alive at 0% CPU, both started at 02:03 when the run
began, still resident four and a half hours later. A hung app instance holding the shared library
blocks the next case's file coordination, so every subsequent case waits out its full 1800s timeout.
The harness's per-run timeout kills its own subprocess and does not reap the app.

**This very likely also explains the earlier pool-40 results**, which were read as a performance
regression. If cases were serialising behind hung predecessors rather than doing work, the 925s
figure measures blocking, not cost, and the pool-size explanation may be only part of the story.
`tokfix` and `coreml-provider` completed 25 cases each without this, so something about tonight's
sequence provokes it — worth finding before trusting any timing from this harness again.

**The run was then ended by hand, in error.** A `pkill` pattern matching `oi-mac-40.*OpenIntelligence`
also matches the python harness, whose command line contains the app path. Killing the two hung
processes killed the job at case 11/16. Use `pgrep -f 'Contents/MacOS/OpenIntelligence'` to target
the app alone.

### `postfix-citations` — after the 2026-08-19 fixes, and what it settled

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `postfix-citations` | `4a96958` | 8 cases x {deep-think, standard}, `pool_limit 10`, QASPER, seed 42, temp 0.7, `topk`, `--pcc deny`. **Flag-for-flag identical to `paired-retry`.** | **Complete. 16/16, no timeout, no cascade.** deep-think **3/8 (37.5%)**, standard **5/8 (62.5%)**. |

**Read the caveat before the numbers.** Six behavioural changes shipped between `paired-retry` and
this run: intent classification, source-only evidence budgeting, review/extraction evidence
consistency, the citation source list, the grounding threshold and the confidence formula. This is
**not** a single-variable A/B and cannot attribute any delta to any one change. At n=8 with roughly
21% reproducibility it also cannot resolve a difference of one case. Both modes moving up by exactly
one case is inside noise.

| | baseline | today |
| :-- | --: | --: |
| deep-think correct | 2/8 | **3/8** |
| standard correct | 4/8 (1 failed) | **5/8 (0 failed)** |
| deep-think mean seconds | 292.7 | **242.3** |
| standard mean seconds | 216.7 | **196.0** |
| deep-think mean confidence | 0.83 | **0.77** |
| deep-think stages reported | **1** (`final`) | **6** |

**The two things this run actually settles, neither of which is the accuracy number.**

**Deep Think's retrieval is measurable for the first time.** `ef3fd25` instrumented the agentic path
and had never executed; the baseline reported a single `final` stage. This run reports `vector`,
`lexical`, `fusion`, `boosted`, `candidates`, `final`. `rerank` is still absent for deep-think while
standard reports all seven, which is itself worth chasing — the agentic path either does not rerank
or does not capture it.

**Fusion ranks below the lexical arm it fuses, in both modes.** Previously observed on standard
only. Now measured on both, in the same direction and similar magnitude:

| mode | lexical r@10 | fusion r@10 | delta | lexical MRR | fusion MRR | delta |
| :-- | --: | --: | --: | --: | --: | --: |
| deep-think | 0.692 | 0.538 | **-0.154** | 0.615 | 0.431 | **-0.185** |
| standard | 0.750 | 0.625 | **-0.125** | 0.646 | 0.448 | **-0.198** |

Combining the vector and lexical arms produces a ranking worse than the lexical arm alone, and the
MRR penalty is larger than the recall penalty in both modes, meaning fusion is pushing correct
documents *down* rather than dropping them.

**A scoring caveat that must not be skipped.** deep-think's `final` stage is scored over **n=21**
while its other stages are **n=13**. Different denominators, so `final` r@10 0.857 is not comparable
to `candidates` 0.462 and the apparent recovery across that boundary is partly an artifact. Standard
is n=8 throughout and does not have this problem.

`boosted` and `candidates` are byte-identical in both modes, so top-K truncation dropped nothing
here and the boost stage is doing no reordering that survives to candidates.

`[evidence_level: run_artifact_verified, confidence: exact_for_the_figures, causal_attribution_impossible]`

### `paired-retry` — the run that worked, and what it found

| run | commit | tests | verdict |
| :-- | :-- | :-- | :-- |
| `paired-retry` | `1b700ed` | 8 cases x {deep-think, standard}, pool_limit 10, QASPER, matching `tokfix` and `coreml-provider`. | **Complete. 16/16 attempted, one timeout, no cascade.** deep-think **2/8 (25%)**, standard **4/7 (57%)**, `gold_recall` 0.38 against 0.57. Standard lands on its historical baseline of 36% and 52%, so the harness is measuring consistently. **Deep Think's first quality number ever.** |

**The finding: `correct == (gold_recall == 1.0)` in 14 of 15 scored runs.**

Answer accuracy is almost entirely determined by whether retrieval surfaced the gold document.
Neither mode produced a wrong answer from correct evidence except once, and neither produced a right
answer without it, ever.

The single exception is `qasper_1911.10742_397a1e85`, where Deep Think **had** the right document and
still answered wrong. That is the only genuine synthesis failure in the set, and it is the same
shape as the device-observed dopamine query.

**What follows, and it redirects the whole quality arc:**

- **Synthesis is not the bottleneck and has not been for some time.** Truncation, the session cap,
  the SourceOnly budget — all real fixes, none of which can move this number, because synthesis is
  already 14/15 correct given the evidence.
- **Deep Think's retrieval is worse than Standard's**, 0.38 against 0.57. Deep Think's distinguishing
  feature at the retrieval stage is multi-query expansion plus HyDE. On this corpus the expansion is
  *losing* documents Standard finds.
- **Do not restructure the mode design on this.** n=8, one corpus, ~21% reproducibility. The
  actionable move is to find why expansion lowers recall; if that is fixable, Deep Think should
  dominate Standard rather than trail it.

Session-cap behaviour confirmed off-device for the first time: **11 generations** on a rich case,
**6** on a sparse one, against 5 observed on the phone. It scales with distinct windows in both
directions, which is what `e16a2d3` was for.

### Still open

Deep Think has **no** quality baseline. The only numbers are 1/5 on six QASPER cases with three
retrieval misses, at n=5, against a standard-mode baseline of 9/25 and 13/25. Not enough to
conclude anything, and the retrieval misses matter more than the answer count.

---

## 2026-08-17: the tokenizer arc

| run | commit | tests | verdict |
| :-- | :-- | :-- | :-- |
| `cmp-standard` | `24d3b54` | Baseline, standard mode, 25 cases. Tokenizer at 128. | **Reference.** vector r@1 **0.080**, lexical **0.600**, fusion **0.360**, rerank r@10 **0.840**, final r@1 **0.400** / r@10 **0.760**. The lexical-beats-vector gap here is what started the whole investigation. |
| `cmp-deepthink` | `24d3b54` | Deep Think vs standard at one commit. | **Abandoned at 16/30**, stopped deliberately to pursue the tokenizer finding. Resumable with `--resume`. Not a failure, a reprioritisation. |
| `det-A` / `det-B` | `24d3b54` | Determinism: same 20 cases twice. | **Failed.** 3 of 14 paired cases byte-identical, **21%**. The reranker race fix helped and did not solve it. Cause remains upstream and unidentified. |
| `tok512` | tokenizer 512 **with** padding block | Raise truncation to 512. | **Catastrophic, and diagnostic.** Case 1 exceeded a 1500s timeout having taken 250s at baseline. Cause: `countTokens` returns `encode().count`, and a padded encode is constant, so `512 > 430` fired for every chunk and ingestion emitted roughly one chunk per word. **This timeout was then misread as quadratic attention cost, which was wrong.** Both models are fixed-shape `[1, 512]` and were always fed 512-wide tensors. |
| `tokfix` | `2753d15` | Truncation 512, padding block **removed**. | **Complete, 25/25. Recall improved at every stage.** final r@10 **0.760 to 0.864**, fusion r@10 **0.760 to 0.909**, vector r@10 **0.360 to 0.455**, rerank r@1 **0.520 to 0.636**. Correct 9/25 to 9/22. **r@1 flat or down at every stage the vector arm feeds** (vector 0.080 to 0.000, fusion 0.360 to 0.318), which is what CLS pooling predicts. Two cases failed, one a 25-minute hang on a case that passed at baseline. Earlier note said **In progress.** Token counts now vary (386 to 430) where they were a constant 128 across 3,910 prior ingestions. At n=7: rerank r@10 **0.840 to 1.000**, final r@10 **0.760 to 0.857**, but **vector r@1 flat**. Control (lexical) settled at 0.714 against a 0.600 baseline, so the runs are comparable. |

### What this arc settled

- **55% of all library content never reached the embedder.** Real WordPiece tokenization over 139
  live chunks: median 273 tokens against a 128 cap, 125 of 139 truncated.
- **The token counter was a constant**, so the 430-token chunk guard never fired in production.
- **The reranker fix works and the embedder fix does not**, which is the observation that led to the
  pooling discovery below.

### What it did NOT settle

- Whether MiniLM is actually weak, because it is being **read wrong** (see below).
- Determinism. Still 21%.
- Whether Deep Think beats standard. That comparison was abandoned mid-run.

### The control was not a control, and this limits every number above

`lexical` was designated the control on the reasoning that BM25 reads full text through FTS5 and
cannot be touched by a tokenizer change. **It moved from 0.600 to 0.682 at r@1 and 0.800 to 0.909 at
r@10.**

The reasoning was wrong. Fixing `countTokens` also fixed **chunking**: the `safeTokenLimit` guard at
430 tokens now fires for the first time in the product's life, so chunk boundaries differ, and FTS5
indexes different text. The tokenizer fix therefore reaches both arms.

**Consequence for reading this run:** the gains are real and they are measured, but they are
"truncation plus chunking", not truncation alone. No number here isolates the embedding change. A
clean attribution would need a run with the padding block removed and the 430 guard disabled, which
has not been done.

Recorded because a stated control that turns out to be coupled is worse than no control: it invites
attributing an effect to the wrong cause with more confidence than the evidence carries.

### Open question raised by `tokfix`, not yet diagnosed

**A case that passed at baseline now hangs to timeout.** `qasper_1604.02038_a0fd0c0f` completed in
`cmp-standard` with a 505-character answer over 13 chunks. Under `tokfix` it sat at **0.4% CPU for 25
minutes** and hit the 1500s timeout. Two cases have now timed out in this run.

**It is a hang, not slow computation, and not machine contention.** CPU stayed at 0.4% through three
minutes with the machine otherwise idle. A test suite was running concurrently for part of that
window, which was a mistake and against a recorded constraint, but it is not the cause: contention
raises CPU, it does not pin it near zero.

Candidate causes, none verified:

- The `enforceTokenLimitOnChunks` path now genuinely executes for the first time, since `countTokens`
  finally returns real values and the 430-token guard can fire. That code had never run in production
  across 3,910 recorded ingestions, so it is unexercised.
- Something in the split path blocks rather than loops, which would explain near-zero CPU better than
  an infinite loop would.

**Do not dismiss this as a slow case.** A hang that only appears once the token counter starts
working is exactly the kind of defect this fix would be expected to expose, and it reached a timeout
on a case that previously succeeded.

---

## 2026-08-17: the pooling arc

| run | commit | tests | verdict |
| :-- | :-- | :-- | :-- |
| `coreml-provider` | `308e4df` + 5 uncommitted (provider override, queue guard) | Same 25 cases, same seed, forced onto `CoreMLSentenceEmbeddingProvider` via the new `benchmarkEmbeddingProvider` default. Isolates **pooling** and nothing else: identical weights, identical corpus, identical tokenizer. | **In progress.** At 9/25, **paired against `tokfix` on the 7 cases both runs completed**: `vector r@1` **0 of 7 to 3 of 7**, correct **3 of 7 to 5 of 7**, and the `lexical` control is **identical case for case**. |

**Read this run paired, never as a raw average.** Two cases in `coreml-provider`
(`qasper_1611.06322_57ee20f4`, `qasper_1604.02038_a0fd0c0f`) produced no stage metrics in `tokfix`,
so any mean over "all cases so far" compares different case sets and understates the new run. The
first interim figure recorded in this row was such an average and has been replaced. **Compare per
case, on the intersection.**

**The control holds, and that is the load-bearing result.** `lexical r@1` is identical on all 7
paired cases. BM25 reads full text through FTS5 and cannot be touched by which provider produces
vectors, so this is what a valid run looks like. The previous arc's control moved and destroyed
attribution for that entire table; this one does not, so the vector movement here is readable.

**Direction is monotone.** Three cases flip `vector r@1` from 0 to 1 and **none flip the other way**.
A wash would be expected to produce regressions as well as gains.

**Significance reached at 15/25, against a threshold fixed at 10/25 before the result was known.**
At 13 paired cases: **8 better, 0 worse, exact two-sided sign test p = 0.0078**. The threshold was
written into `scripts/compare_benchmark_runs.py` while the run sat at 4 better and 0 worse
(p = 0.125, short of the bar), specifically so it could not be adjusted once the answer was visible.

Interim readings, kept to show the direction was called before it was significant and not after:

| paired n | vector r@1 | discordant | p |
| :-- | :-- | :-- | :-- |
| 7 | 0.000 to 0.429 | 3 better, 0 worse | 0.250 |
| 8 | 0.000 to 0.500 | 4 better, 0 worse | 0.125 |
| 13 | 0.000 to **0.615** | **8 better, 0 worse** | **0.0078** |

## VERDICT, 25/25 complete

**The Core AI export reads the wrong output of the embedding model. MiniLM is not the problem.**

21 paired cases, 4 excluded because `tokfix` produced no stage metrics for them:

| stage | r@1 | r@10 | mrr |
| :-- | :-- | :-- | :-- |
| `vector` | 0.000 → **0.571** | 0.476 → 0.762 | 0.099 → **0.624** |
| `lexical` (control) | 0.714 → 0.714 | 0.905 → 0.905 | 0.778 → 0.778 |
| `fusion` | 0.333 → **0.714** | 0.905 → 0.905 | 0.550 → 0.782 |
| correct | **9/21 → 12/21** | | |

**`vector r@1`: 12 better, 0 worse, exact two-sided sign test p = 0.0005.** The `lexical` control is
identical on all 21 cases, so the runs are comparable and the movement is attributable.

**What this settles.** Reading the same weights with mean pooling instead of the CLS token moves the
dense arm from never ranking the right chunk first to doing it 57% of the time. The embedder was
never weak; it was being read at a position it was never trained to make meaningful.

**What it does not settle.** This run swaps the whole provider, so it measures pooling together with
runtime and model artifact. The corrected Core AI export should land near these numbers; if it does
not, pooling was not the whole cause. End-to-end `correct` moved 9/21 to 12/21, which is **4 better,
0 worse, p = 0.125, not significant** — retrieval quality is established, the answer-quality effect
is not. Determinism is still 21%, so a rerun would not reproduce these exact figures.

**One regression, recorded rather than buried.** `qasper_1911.10742_f7662b11` drops `fusion r@10`
from 1.00 to 0.00 while its own vector arm does not improve. Plausible mechanism: better vectors on
competing chunks displace the one fusion previously surfaced. Unverified.

**The `tokfix` hang did not recur.** `qasper_1604.02038_a0fd0c0f` timed out at 0.4% CPU for 25
minutes in `tokfix`; here it completed with `fusion r@10` 1.00, still not correct. One observation.
It does not explain the hang and does not close it.

The mechanism is independently established by code reading and does not depend on this run:
`compile_core_ai_model.py` returns `last_hidden_state[:, 0, :]` from a model whose own card, and
this app's own Settings copy, specify mean pooling. The benchmark measures the size of the
consequence, not whether the defect exists.

**Caveat on attribution.** This run swaps the whole provider, not just the pooling step. Core AI and
Core ML differ in runtime, model artifact (`main.mlirb` against `.mlpackage`) and input count as
well as pooling. Pooling is the only difference with a known mechanism for changing vector quality,
but a clean isolation requires the corrected Core AI export, which is the point of
`Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md`. **A corrected Core AI export should land near
this number. If it does not, the cause is not only pooling and this row is incomplete.**

---

## Open, not yet run

| planned run | tests | why it matters |
| :-- | :-- | :-- |
| Corrected Core AI export | Same 25 cases on a Core AI model re-exported with mean pooling and an attention mask. | Confirms the fix on the path iOS/macOS 27 actually uses, and isolates pooling from the provider swap above. Instructions: `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md`. |
| Embedder comparison | bge-small-en-v1.5 (MIT, 384-dim, 512-trained) against a correctly-read MiniLM. | **Blocked.** Running it before the export is corrected would compare a candidate against a misconfigured incumbent, which is the confound this entire arc exists to remove. |

---

## Rules learned the hard way

1. **Record the commit.** `run_config.json` does not, and two runs from different commits are not
   comparable. An earlier Deep Think comparison was invalidated by 32 commits of drift between arms.
2. **Record the provider.** Nothing in the run output states which embedding provider produced the
   vectors. It took reading `[CoreAISentence...]` log markers to discover which one had been running.
3. **A single case decides nothing.** Determinism was declared fixed from one paired case and was 21%
   at fourteen. `vector r@1 = 0.000` at n=7 is statistically identical to a 0.080 baseline.
4. **Name the control.** `lexical` reads full text through FTS5 and is untouched by tokenizer changes,
   so if it moves the runs are not comparable and nothing else in the table can be read.
5. **Compare paired, on the intersection of completed cases.** Runs disagree about which cases
   produce stage metrics, because timeouts and hangs differ between them. A mean over "all cases in
   run A" against "all cases in run B" silently compares different corpora and moves numbers in
   whichever direction the missing cases happened to fall. Use `scripts/compare_benchmark_runs.py`,
   which intersects by `case_id` and reports per-case flips. An interim average in this ledger was
   wrong for exactly this reason before it was caught.

### `fusion-vw030` — the fusion weight, measured rather than argued

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `fusion-vw030` | `4a96958` | 8 cases x standard only, **`--vector-weight 0.3`**, `pool_limit 10`, QASPER, seed 42, temp 0.7, `topk`, `--pcc deny`. Otherwise identical to `postfix-citations`. | 7 scored, 1 timeout. Fusion improved on every metric and **the improvement did not reach the answer.** |

**The question.** Default fusion weights are `vector 0.7 / keyword 0.3`, but every measurement taken
of the two arms says lexical is the stronger one — `RAGEngine.swift:982` records lexical ranking the
gold document first in 60% of cases against dense's 8%, and `postfix-citations` measured lexical MRR
0.646 against vector's 0.396. The weighting is inverted relative to the evidence. This run asked
whether correcting it helps.

**Paired on the 7 cases with metrics in both runs**, via `scripts/compare_benchmark_runs.py`:

| stage | MRR 0.7 → 0.3 | r@10 0.7 → 0.3 | nDCG@10 0.7 → 0.3 |
| :-- | :-- | :-- | :-- |
| `vector` | 0.452 → 0.452 | 0.571 → 0.571 | 0.479 → 0.479 |
| `lexical` | 0.714 → 0.714 | 0.714 → 0.714 | 0.714 → 0.714 |
| **`fusion`** | **0.476 → 0.571** | **0.571 → 0.714** | **0.500 → 0.609** |
| `boosted` | 0.476 → **0.405** | 0.571 → 0.571 | 0.500 → **0.447** |
| `candidates` | 0.476 → 0.405 | 0.571 → 0.571 | 0.500 → 0.447 |
| `rerank` | 0.714 → 0.714 | 0.714 → 0.714 | 0.714 → 0.714 |
| `final` | 0.786 → 0.786 | 0.857 → 0.857 | 0.804 → 0.804 |

**The comparison is trustworthy.** `vector` and `lexical` are bit-identical case for case at both
weights, which is what they must be — the knob touches only fusion. The tool's own control line
reports `identical case for case, runs are comparable`. This is a genuine single-variable test, which
is rare in this ledger.

**Three findings, in order of confidence.**

1. **The hypothesis was right about fusion.** Weighting the stronger arm higher improved fusion on
   all four metrics: MRR +0.095, r@10 +0.143, nDCG@10 +0.109. Not one metric moving, all of them.

2. **`boosted` gives the improvement back.** MRR 0.571 → 0.405 and r@1 0.429 → 0.286. The
   keyword-match boost reorders a better-ordered list into a worse one. That is a defect independent
   of the weight question and it was invisible until fusion was improved enough to expose it.

3. **`rerank` and `final` are identical at both weights.** The cross-encoder re-sorts everything and
   erases the difference completely — 0.714 and 0.786 either way, to three decimals.

**Standard mode was the wrong vehicle and this run proves it.** Its reranker sits downstream of
fusion and normalises any fusion change out of existence. **Deep Think has no `rerank` stage at all**
— `postfix-citations` shows it going `fusion 0.431 → final 0.688` with nothing in between, while
standard goes `fusion 0.448 → rerank 0.750 → final 0.812`. If the fusion weight can reach an answer
anywhere, it is only there. **Do not conclude from this run that the fusion weight does not matter.
Conclude that it cannot matter in the mode that reranks.**

**Accuracy went 4/7 to 3/7 and means nothing at n=7.** One case. The sign test found no discordant
pairs on the retrieval metric and reported nothing to test.

**The hang recurred, third occurrence, same paper.** `qasper_1604.02038_bc8526d4` sat at 0.1% CPU
for 21 minutes and timed out at 1800s; `qasper_1604.02038_a0fd0c0f` did the same in `tokfix` for 25
minutes. Something about `1604.02038` provokes it. The reaper did not fire and no orphan survived,
which is the fourth confirmation that `subprocess.run` kills its own child correctly.

### `fusion-vw030-deepthink` — the fusion weight is not the lever, and `boosted` is

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `fusion-vw030-deepthink` | `61a6a70` | 8 cases x deep-think only, **`--vector-weight 0.3`**, `pool_limit 10`, QASPER, seed 42, temp 0.7, `topk`, `--pcc deny`. | **8/8 complete, no timeout.** Fusion improved sharply. `final` got worse. **Do not change the weight.** |

**Why this run existed.** `fusion-vw030` showed a fusion improvement that `rerank` erased in Standard.
Deep Think has no `rerank` stage, so it was the only pipeline where the change could reach an answer.

**Deep-think paired on all 8 cases** (mode-aware; see the tooling warning below):

| stage | MRR 0.7 → 0.3 | r@10 0.7 → 0.3 |
| :-- | :-- | :-- |
| `vector` | 0.330 → 0.419 | 0.462 → 0.533 |
| `lexical` | 0.615 → 0.613 | 0.692 → 0.733 |
| **`fusion`** | **0.431 → 0.591** | **0.538 → 0.800** |
| `boosted` | 0.591 → **0.442** | 0.800 → 0.667 |
| `candidates` | 0.336 → 0.442 | 0.615 → 0.667 |
| **`final`** | **0.688 → 0.530** | **0.857 → 0.739** |

Accuracy **3/8 → 2/8**.

**The answer: no.** Fusion improves substantially at weight 0.3 — MRR +0.160, r@10 0.538 to 0.800 —
and the answer still gets worse. Combined with `fusion-vw030`, the weight change is neutral in
Standard and negative in Deep Think. **The default `vector 0.7 / keyword 0.3` stays.** Two runs, both
modes, one conclusion.

**What the two runs actually found is `boosted`.** Isolating what
`applyKeywordMatchBoost` does to the ranking fusion hands it, across all four conditions:

| condition | fusion MRR | boosted MRR | change |
| :-- | --: | --: | --: |
| standard vw0.7 | 0.448 | 0.442 | −0.006 |
| deep-think vw0.7 | 0.431 | 0.336 | −0.095 |
| standard vw0.3 | 0.571 | 0.405 | **−0.167** |
| deep-think vw0.3 | 0.591 | 0.442 | **−0.149** |

**It degrades the ranking in every condition, and it degrades more the better the ranking it is
given.** Sorted by fusion quality, the damage rises monotonically. That is not a tuning problem; a
stage that destroys more value the more value it receives is doing the wrong thing. This is the
lever, and it was invisible until fusion was improved enough to expose it.

**Tooling warning, recorded because it nearly produced a wrong conclusion.**
`scripts/compare_benchmark_runs.py` pairs by `case_id` alone and has no `--mode` filter. Comparing a
single-mode run against a two-mode run silently matched deep-think candidate rows against **standard**
baseline rows. The control line caught it — `lexical r1: MOVED -- runs are not comparable` — which is
the control doing exactly its job. The table above was recomputed mode-aware. **Add a mode filter to
that script, or always pass single-mode runs to it.**

**A structural limit on A/B testing Deep Think.** In the mode-aware pairing, `vector` MRR moved
0.330 → 0.419, and the fusion weight cannot touch the vector arm directly. The agentic loop is
adaptive: changing fusion changes which chunks come back, which changes the next query it issues,
which changes every later call's vector stage. **No stage is a valid control in Deep Think**, and
per-call means are taken over different query sets between runs (n=13 against n=15 here). Deep-think
stage deltas are directional evidence, not measurements. The `final` and accuracy figures are the
trustworthy ones because they are per-case.

### 2026-08-20, per-case forensics — the mechanism behind three open mysteries, from data already on disk

No new runs. Everything below comes from per-case `stage_metrics` in `postfix-citations`,
`boostfix-standard` and `fusion-vw050`, plus reading the code.

**1. The dense arm is not a retrieval list; it is the whole corpus, ranked.** `vector` returns 180
of ~182 chunks — no similarity floor cuts it. RRF therefore fuses 3–9 precise lexical hits into a
ranking of everything: with k=60, a lexical rank-1 contributes `w/61` once while every chunk in the
store collects a dense contribution. A lexical rank-1 gold chunk can leave fusion below the top-90
cut. **This is why "fusion ranks below its own lexical arm", and why no weight — 0.3, 0.5, 0.7 —
could fix it.** The sweeps were tuning the coefficients of a structural burial.

**2. The rerank→final "inversion" was two individual cases, not a force.**
`qasper_1911.10742_f7662b11`: gold at lexical rank 1 of 3, absent from fusion's top 10, cut from
the reranker pool, rescued by the post-rerank cascade in all three runs (final mrr 1.0 every time).
`qasper_1604.02038_bc8526d4`: the cross-encoder ranked gold #1 given one 90-chunk pool and #7 given
another — the pools differed because the 182→90 cut is taken in list order, and the boost sort
controlled that order. Rank 7 then died at the final k=6 cut. **The boost fix's "regression" was
this single case: the boost sort was load-bearing for pool membership, not for ranking quality.**

**3. The cascade trigger reads synthetic numbers.** `cascadeDecision` compares
`metrics.topSimilarity < 0.45`, but post-cross-encoder scores are normalized to [0.1, 0.9] by
construction — the top is ~0.9 regardless of quality. On the cross-encoder path the trigger is
structurally near-dead; the rescues observed came through its other conditions.

**Fix implemented on the strength of this** (uncommitted pending measurement): a lexical survival
guarantee in `HybridSearchService` — the reranker pool is the top-K cut unioned with the lexical
arm's best hits (capped, tail-appended; the cross-encoder scores the whole pool regardless of
position). Both hybrid paths.

**Measurement blocked by an environment failure, recorded so nobody trusts the numbers.**
`BenchmarkRuns/lexical-survival` is **invalid**: every case completed in ~19–23s with every answer
the graceful-degradation fallback, and `ModelManagerServices.ModelManagerError Code=1026` on every
generation *and* on ingestion summarization. Foundation Models on this Mac wedged after five
back-to-back benchmark runs plus a simulator suite; shutting the simulator down did not clear it.
Do not read that run's stage metrics either — ingestion enrichment failed during it, so chunk
metadata differs from healthy runs. The intermittent 1800s hang at 0.1% CPU (`1604.02038`, three
occurrences) is plausibly the same daemon wedging mid-run rather than anything about that paper —
hypothesis, not established.

**2026-08-20, later: the FM outage cleared with a reboot.** Probe returned `GENERATION OK`;
`lexical-survival-2` case 1 ran healthy (PASS, 207.5s). The `availability`-flag lesson stands. The
run was interrupted by the owner at case 2 and resumes via `--resume`; its verdict decides the
uncommitted survival fix.

### `lexical-survival-3` — the survival fix's verdict: committed as `89bf928`

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `lexical-survival-3` | tree at `6790548` + the fix | 8 cases x standard, defaults, flag-for-flag with `postfix-citations`. | 8/8 attempted, 1 timeout (intermittent hang, excluded from pairing). **Committed.** |

Paired on 7 cases, lexical control **bit-identical** — a valid single-variable comparison.

| stage | baseline → fix |
| :-- | :-- |
| `rerank` r@5 / r@10 | 0.714 → **0.857** |
| `rerank` MRR | 0.714 → 0.714 |
| `final` r@10 | 0.857 → 0.857 |
| `final` MRR | 0.786 → **0.679** |
| correct | 4/7 → **5/7** |

**What the fix provably did:** the cross-encoder surfaced gold it previously never received — the
rerank recall gain and the accuracy flip are the same case, `qasper_1611.06322_57ee20f4`, which at
baseline had gold at **no stage** (rerank r10=0, final r10=0, wrong answer) and now passes. That is
the categorical claim the fix makes — pool membership, not ranking — landing exactly where predicted.

**What it cost, recorded rather than hidden:** one other case's gold moved from rank 1 to lower in
the final top 3, dragging final MRR 0.786 → 0.679. At n=7 that is one case, the same ±1-case jitter
every run this week has shown. `final` r@10 held.

**Why committed despite the mixed final-MRR:** the pre-registered protocol said "better or equal →
commit" without naming the governing metric. The call: membership is categorical and confirmed, an
unfixable case class is now fixable, accuracy and rerank recall improved, and the dip is
noise-scale. Device n=1 corroborates end-to-end (regression query: 8 words → 4,593 chars, survival
log firing).

**The intermittent hang struck a third distinct case id** (`85e41723`, second distinct paper),
killing the paper-specific theory for good. It is the app/daemon wedge, frequency roughly 1-in-8
cases per run today.

### 2026-08-20, retraction: "Deep Think has no rerank stage" was an instrumentation artifact

Withdrawn before any feature was built on it, but after it reached this ledger, `STATE.md`, the
fusion roadmap row, and the `89bf928` commit message. The record stays; this entry corrects it.

**Deep Think reranks and always has.** `performFullRetrievalPipeline` — the function every
`AgenticOrchestrator` retrieval call goes through — calls `engine.rerank(chunks:query:topK*2)`
unconditionally between the hybrid search and its return (`RAGService.swift:18396`). What was
missing was one line: `trace?.record(.rerank, …)`. The benchmark trace therefore showed six stages,
and the absent *record* was read as an absent *reranker*, then hardened by repetition. Two
confirmations beyond the code path: no gate or early return exists between search and rerank (only
the empty-corpus guard), and deep-think's own numbers carry the reranker's signature — `candidates`
MRR 0.336 → `final` 0.688, the same shape as standard's 0.442 → 0.750. Blocker 5 had flagged
"deliberate or omission is unverified"; the verification happened only after a feature to "add" the
reranker was approved. The stage is now recorded (same commit as this entry).

**What this reopens:** the deep-think vs standard gap (final MRR 0.688 vs 0.812 at the last valid
paired read) is *unattributed again*. Both modes rerank. Remaining candidates, none established:
the agentic path has no post-rerank cascade; its per-call `topK` differs; its queries are adaptive
rewrites rather than the user's question; and per-call stage means are structurally untrustworthy in
an adaptive loop. Attribution requires the newly recorded `.rerank` stage in a fresh paired run —
per-case `final`/accuracy remain the only trustworthy deep-think readouts.

**"+30 MRR points from the cross-encoder" survives** — it was measured in Standard, where controls
hold. What is withdrawn is only its corollary "and Deep Think gets zero."

### `overnight-25case-nodeadlock` — the largest paired run this project has completed, and it moves the target

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `overnight-25case-nodeadlock` | `73fff4f` | 25 cases x {deep-think, standard} = 50 runs, `pool_limit 10`, QASPER, seed 42, temp 0.7, `topk`, `--pcc deny`. | **50/50 completed, 0 failed, 0 timeouts, 209 min.** |

**It proves the deadlock fix.** The prior attempt on the unfixed binary hit its first 1800s timeout
by case 3 and was aborted at 10/50 (preserved as `overnight-25case-aborted-deadlock`). Fifty
consecutive runs with none, against a prior rate near one per eight cases.

**Per-stage, both modes** (n=24 standard, n=66 deep-think per-retrieval-call):

| stage | std MRR | std r@1 | dt MRR | dt r@1 |
| :-- | --: | --: | --: | --: |
| `vector` | 0.563 | 0.500 | 0.603 | 0.530 |
| `lexical` | 0.691 | 0.625 | 0.696 | 0.621 |
| **`fusion`** | **0.708** | 0.625 | **0.719** | 0.667 |
| `boosted` | 0.635 | 0.542 | 0.583 | 0.500 |
| `candidates` | 0.635 | 0.542 | 0.583 | 0.500 |
| `rerank` | **0.753** | 0.667 | 0.699 | 0.606 |
| **`final`** | **0.590** | **0.417** | 0.665 | 0.567 |

**1. Fusion now beats its own lexical arm, in both modes.** 0.708 against 0.691 (standard), 0.719
against 0.696 (deep-think). The defect that drove a week of fusion-weight sweeps — "fusion ranks
below the keyword arm it is fusing" — **is gone**, and the lexical survival guarantee (`89bf928`) is
why: the reranker pool now contains the lexical hits that used to die at the cut. That roadmap row's
central claim no longer reproduces.

**2. `boosted` is now unambiguously the worst stage.** It destroys 0.073 MRR (standard) and 0.136
(deep-think) of what fusion earned, at n=24 and n=66 — far past the 8-case noise that made this
arguable before. Confirmed in every measured condition to date.

**3. The rerank→final collapse is real, large, and now the headline defect.** Standard: MRR 0.753 →
**0.590**, and r@1 0.667 → **0.417** — a quarter of all cases lose their top-ranked gold document
*after* the cross-encoder has correctly ranked it. `final` has the same n as `rerank` (24), so this
is not a sampling artifact. Deep-think shows the same direction, smaller (0.699 → 0.665). **Whatever
runs between the reranker and the answer is the largest single quality loss in the pipeline.**
Candidates to read, in order: the MMR diversification (`topK * 3` then re-select), parent-document
expansion, and the final top-K truncation.

**4. Deep Think emits all seven stages**, including `rerank`, confirming `017280b`. Its `final` MRR
(0.665) is *higher* than standard's (0.590) while its accuracy is lower (36% vs 40%) — retrieval
quality and answer correctness are diverging, which is worth its own investigation.

**Accuracy: deep-think 9/25 (36%), standard 10/25 (40%).** Paired against `postfix-citations` on the
8 shared cases with the lexical control identical: 5/8 → 5/8, no change. The four-point mode gap at
n=25 is one case; nothing is resolvable at this size, as ever.

### `rescue-position-fix` — first accuracy movement of the week with a valid control

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `rescue-position-fix` | `a7c1945` | 25 cases x standard, otherwise flag-for-flag with `overnight-25case-nodeadlock`. | 25/25, no timeouts. **Committed.** |

Paired on 24 cases, lexical control identical case for case:

| stage | before | after |
| :-- | --: | --: |
| `lexical` (control) | 0.691 | 0.691 |
| `fusion` | 0.708 | 0.708 |
| `rerank` MRR | 0.753 | 0.732 |
| **`final` r@1** | **0.417** | **0.500** |
| **`final` MRR** | **0.590** | **0.646** |
| **correct** | **9/24** | **11/24** |

**Predicted before the run** (recorded in the working message, then verified): `final` r@1 recovers
toward `rerank`'s 0.667, `rerank` unchanged, control identical. Two of three held exactly. `rerank`
drifted 0.753 → 0.732, which the fix cannot touch — small, unexplained, and deliberately not
attributed.

**Partial, not complete.** `final` r@1 0.500 is still well below `rerank`'s 0.667, so at least one
more stage between reranking and the answer drops rank-1 chunks. Remaining suspects: parent-document
expansion, the final top-K truncation, and MMR's own diversity penalty demoting a correct chunk.

### The measurement gap that matters more than any of this

Three claims were withdrawn on 2026-08-21, all the same error — reading a number as stronger evidence
than it was:

1. **"Retrieval finds the gold document 84% of the time, so the bottleneck is synthesis."** `r@10`
   credits the *document*, not the passage. In `qasper_1611.06322_1a615618` the gold sentence appears
   **zero times** in the entire run while the case scored as retrieval success; the model then
   summarised a different section of the correct paper, fluently and with citations. This ledger has
   warned since 2026-08-11 that document-level truth is a generous ruler; it was quoted anyway.
2. **"40% accuracy is partly a grading artifact."** Refuted by the harness's own unused soft metric:
   of 13 retrieved-but-wrong standard cases, **zero** had `gold_recall >= 0.8` and eleven had `< 0.4`.
   The answers are genuinely wrong, not merely phrased differently.
3. **A passage-level measurement of those same cases.** Invalid: it grepped run *reports*, which
   store only truncated previews. Eight cases scored correct while the detector claimed the passage
   was absent — impossible, and the tell that the detector was broken.

**Passage-level retrieval is therefore unmeasured and unmeasurable from anything on disk**, because
`retrieved_chunks` is an integer count and chunk text is never persisted. The fixture pack already
carries `expected_evidence[].excerpt` for every case, so only the harness side is missing. **This is
the single highest-value instrumentation left**: 19 of 25 QASPER cases are `answer_kind: extractive`
(6/19 correct), meaning the answer is a literal span, and nobody can currently say whether that span
reaches the model.

### 2026-08-21: an index over this ledger, and a warning it now carries

`BenchmarkRuns/PROGRESSION.md` (regenerate with `python3 scripts/benchmark_progression.py --out
BenchmarkRuns/PROGRESSION.md`, but only after extracting the 2026-09-01 archive named at the top of
this file: the script reads whatever is in `BenchmarkRuns/`, which now holds only the two
2026-09-23 runs, so running it now would replace the table with those two; qualified 2026-09-29)
tabulates every run on disk — 44 run/mode pairs across 39 runs —
with the config that produced each row beside it, so a reader can see at a glance whether two rows
are comparable at all. **It is an index, not a replacement.** This file stays authoritative for what
each run settled and for the analyses that turned out to be wrong, which is the part a table cannot
hold.

Two things it surfaced immediately:

- **Six run/mode pairs average under 60 seconds per case**, which means generation never ran. They
  are marked ⚠ SUSPECT. One is `lexical-survival`, already recorded above as invalid (Foundation
  Models wedged machine-wide, every answer the fallback text). The heuristic also independently
  flagged `20260811-150328-matrix` and `20260811-133233-matrix` at ~21s per case — the same runs
  this ledger separately records as measuring each case against an index containing only its own
  expected documents, the defect that pinned every stage at 1.000. **An invalid run listed beside
  valid ones is worse than no table**, which is why the flag exists.
- **The trend the prose obscured**: across the three 25-case standard runs at identical config,
  `final r@1` went 0.417 → 0.500 while `fusion` MRR held at 0.708 and `lexical` at 0.691. Retrieval
  quality upstream is stable; everything moving is downstream of the reranker.

### Passage-level recall — the metric that should have existed from the start

Committed 2026-08-21 alongside this entry, **not yet exercised by any run**.

`DebugRAGValidationHarness` now emits a `RETRIEVED CHUNK TEXT` block listing every chunk that
reached the model, and `run_quality_matrix.py` gained `passage_recall()`, which slides a 12-word
window over the fixture's `expected_evidence[].excerpt` and reports `passage_present` plus the rank
of the chunk containing it. Cases without an excerpt, and reports predating the block, return
`None` rather than a miss — an unmeasurable case must never look like a failure.

**Why it matters more than anything else here.** Every retrieval number in this file is
document-level: `r@1` and `r@10` credit a whole document when any of its chunks appears. On
2026-08-21 that ruler produced four wrong conclusions in one day, the last of them *inverted* —
injecting a document summary drove `r@1` up (a summary is a chunk of the gold document) while making
answers worse, because a summary cannot answer an extractive question. 19 of 25 QASPER cases are
`answer_kind: extractive`, so the answer is a literal span and "did the span arrive" is the only
question that matters at that stage. It could not previously be asked; `retrieved_chunks` was an
integer count and chunk text was persisted nowhere.

### `passage-level-1` — the retrieval/synthesis split, measured at last; and the noise floor, measured by accident

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `passage-level-1` | `ad99b1b` | 25 cases x standard, flag-for-flag with `rescue-position-fix`. | 25/25, no timeouts. First run carrying passage-level scoring. |

**The decomposition** (re-scored offline with the corrected matcher, n=25):

| gold span | answer | count |
| :-- | :-- | --: |
| present | correct | 7 |
| **present** | **wrong** | **7** |
| absent | correct | 3 |
| absent | wrong | 7 |
| unmeasurable | correct | 1 |

**Two problems of roughly equal size.** The gold span fails to reach the model in **10 of 24**
measurable cases (42%) — retrieval. When it does reach the model the answer is still wrong in
**7 of 14** (50%) — synthesis. Every prior argument on this row assumed one or the other dominated;
both are wrong. Document-level `r@10` of 0.875 concealed this entirely, because it credits the
document while the answer needs the passage.

**Position of the answer-bearing chunk when present:** `1,1,1,2,2,3,3,4,4,4,4,4,7,9`. Position 1 in
3 of 14 (21%), top-3 in 7 of 14. Less dramatic than the partial-run reading of "never in the top 3"
(4,4,4,7 at n=10), which was a small-sample artifact and is withdrawn.

**Correction to how that list was first described, same day.** It was written as "rank of the chunk",
which reads as *retrieval* rank. It is not. `passage_chunk_rank` counts position in the
`RETRIEVED CHUNK TEXT` block, and that block is `response.retrievedChunks`, which is
`promptSources + rescuedChunks` (`RAGService.swift:12193`) — **the chunks that reached the prompt.**
So it is prompt position, and the reranker's own ordering is not what it measures.

**Three cases remain "span absent, answer correct."** Either residual matcher false negatives or
QASPER answers derivable from other passages — its questions often carry several valid evidence
spans and the fixture stores one. Do not build on that column.

### The noise floor, measured: ±1 case at n=24

`rescue-position-fix` and `passage-level-1` differ **only** by the debug harness printing chunk text
*after* generation, plus offline scoring. Same binary behaviour, same config, control identical case
for case. Accuracy: **11/24 vs 10/24.**

That is a same-code A/A comparison, and it puts a number on this project's long-suspected
reproducibility problem: **a one-case accuracy difference at n=24 is indistinguishable from noise.**

**Consequence, applied to this ledger's own recent claim.** The rescue-position fix was recorded
above as 9/24 → 11/24 and described as the first accuracy movement of the week. At a ±1 floor, +2
is barely outside noise and should not have been leaned on as hard as it was. What survives is the
mechanism and the retrieval metric: the code provably evicted the reranker's top chunk, and `final`
r@1 moved 0.417 → 0.500 — a stage-level figure, far more stable than end accuracy. **Accuracy at
n=25 cannot adjudicate anything smaller than about a 4-case swing. Stage metrics can.**

### What `passage_present` actually proves, and the bottleneck found while checking it

Two properties of the metric were checked against the code rather than assumed, because the metric
was three hours old and had already been wrong once.

**Checked and sound.** `response.retrievedChunks` is `promptSources + rescuedChunks`
(`RAGService.swift:12193`), assigned from `assembleContext`'s returned `sources` — not the
pre-assembly candidate list. `passage_present: true` therefore means the chunk reached the prompt,
which is the claim the metric is making.

**A worry raised and then refuted by measurement.** `assembleContext` truncates early chunks to
`targetCharsPerChunk` (`RAGEngine.swift:591`) while the harness prints the *full* chunk text, so a
gold span past the cut would score present although the model never saw it. Measured across all 25
reports: the budget is 9,485–9,553 chars, giving a per-chunk target of ~3,150, and **the longest
chunk in any case is 2,585. Zero cases truncated.** The concern does not apply to this run. It would
apply on a smaller budget — the floor is 400 chars — so re-check it if the context budget changes.

**The bottleneck that check exposed.** From the audit snapshots, every case:

| | value |
| :-- | :-- |
| chunks MMR selects | 30 (25 in one case) |
| chunks that reach the prompt | **median 5**, range 4–24 |
| cases dropping 23–26 of the 30 | **20 of 25** |
| context chars used | 9,300–9,500 of ~9,540 — the budget is full |

**Roughly 83% of what the retrieval pipeline ranks never reaches the model.** The budget is the
on-device 4K-token window and it is saturated, not misconfigured; chunks average ~2,000 chars, so
five of them is the whole budget. The arithmetic is forced.

**Consequence for where tuning effort goes.** Any change that improves the ordering of chunks
beyond roughly position 5 cannot change an on-device answer, because those chunks are not in the
prompt. That covers most of what fusion-weight and rerank tuning move. What can change an answer is
(a) getting the right chunk into the top ~5, or (b) putting more of the *right sentences* into the
same budget instead of whole chunks. The code already contains machinery for (b) — a sentence
extraction path and a "needle rescue from dropped chunks" step (`RAGService.swift:12130`) — and
whether either fires on these cases is unmeasured.

**What cannot be attributed offline.** The 10 cases where the span never reached the prompt split
into "never retrieved" and "retrieved, ranked, then cut at assembly", and those have completely
different fixes. `STAGE SOURCES` records chunk *ids* per stage but only the final chunks carry
*text*, so the gold span cannot be located in the rerank set from saved data. Splitting that 10
requires the harness to emit rerank-stage chunk text. That is the next measurement.

### The A/A pair, decomposed: nondeterminism has two independent causes

Pushing the same A/A comparison further, per case rather than in aggregate.

| | 24 paired cases |
| :-- | :-- |
| `vector` / `lexical` / `fusion` metrics identical | **24 / 24** |
| `boosted` / `candidates` / `rerank` / `final` identical | 23 / 24 |
| every retrieval stage identical | **22 / 24** |
| identical `context_chars` | **10 / 25** |
| identical retrieved-chunk count | 22 / 25 |
| identical answer | **7 / 25** |

**Cause 1: prompt assembly diverges below the resolution of every metric here.** 22 of 24 cases
match at every retrieval stage, and the assembled prompt still differs in 15 of 25. Stage metrics
score against *gold documents*, so a different chunk selection or ordering **within the same
documents** scores identically and builds a different prompt. "Stages identical" has never meant
"same input to the model", and no metric in this harness can see the difference.

**Cause 2: the seeded sampler is not reproducible across processes.** Three cases matched on stage
metrics, chunk count and prompt size and still answered differently — including one that returned
**173 characters both times with different text**, which a differing prompt cannot produce. The seed
does reach generation: `strategy=topk` logged in all 25 reports, and `LLMService.swift:722` passes
`seed: benchmarkSeed ?? config.seed` into `SamplingMode.random(top:seed:)`.

**Next run should be `--rag-validation-sampling greedy`.** Greedy takes the highest-probability
token by construction and ignores temperature, eliminating cause 2 outright and leaving cause 1
measurable alone for the first time. **A reproducible harness is worth more than any single
retrieval fix here**, because the ±1 noise floor is what blocks every other measurement.

**A latent footgun, checked and not firing on any run on record.** `benchmarkSeed` is read only
*inside* `if let benchmarkSampling` (`LLMService.swift:720-738`), so `--rag-validation-seed` without
`--rag-validation-sampling` discards the seed silently while the run still logs as configured. Every
run on disk passed `sampling: topk`, so no published figure is affected — but the flag combination
that looks most obviously correct is the one that does nothing.

### `baseline-49` — the first controlled 4.9 vs 5.0 comparison

v4.9.0 in a detached worktree with a **measurement-only backport**: the seed/sampling/temperature
pin from 5.0, two files, applied so the arm could be seeded at all. Retrieval, ranking, evidence
selection and prompt construction untouched. Same 25-case fixture, same flags (`topk`, seed 42,
temp 0.7, pool 10, top-k 3, `--pcc deny`), same machine, both built with the Xcode 27 SDK.

**Paired on the 22 cases measured in all three runs:**

| run | correct | |
| :-- | --: | --: |
| 4.9 | 6/22 | **27.3%** |
| 5.0 `passage-level-1` | 10/22 | **45.5%** |
| 5.0 `rescue-position-fix` | 11/22 | **50.0%** |

**6 cases fixed, 2 broken, net +4 to +5.**

**Correction, same day, before this was quoted anywhere.** The line above originally read "above the
measured ±1 noise floor, and the first defensible claim that 5.0 beats 4.9 on answer accuracy."
**That overstates it.** The ±1 figure is a *net* difference from a single A/A pair; the right test on
paired binary outcomes is the sign test over discordant pairs, and it was not run before the claim
was written:

| comparison | 4.9 | 5.0 | discordant | one-sided p |
| :-- | --: | --: | :-- | --: |
| vs `passage-level-1` | 6/22 | 10/22 | 6 up, 2 down | **0.1445** |
| vs `rescue-position-fix` | 6/22 | 11/22 | 6 up, 1 down | **0.0625** |

**Neither reaches p < 0.05**, so the accuracy improvement is *suggestive and consistent*, not proven.
What supports it: both point estimates favour 5.0, and two independent 5.0 runs each beat the same
4.9 arm. What would prove it: the 83-case fixture, where a split of this shape reaches significance.

**What does not depend on the sign test at all**, and is the stronger half of the case: 4.9 failed to
produce an answer on **3 of 25** cases (two 600s timeouts, one no-report) against **zero timeouts in
50 cases** of 5.0, and was slower per case on the same hardware. That is a categorical reliability
difference, not a marginal statistical one.

**Reliability, not in that table.** 4.9 failed outright on **3 of 25**: two 600s timeouts and one
that produced no report. Those are excluded from its accuracy rather than scored wrong, which is the
generous reading; counted as failures 4.9 is 6/25. The 5.0 25-case runs had **zero** timeouts. 4.9
was also slower per case, 176–351s against ~180s.

**The confound, stated rather than buried.** Both arms ran at temperature 0.7. 4.9's own default was
0.4 (`config had 0.4` logged on every case) while 5.0's shipped default *is* 0.7, so this ran 5.0 at
its real setting and 4.9 off its real setting. Pinning both is what makes the comparison attributable
to code rather than to sampling, but it is not a comparison of the two products *as shipped*. A
4.9@0.4 arm would answer that and has not been run.

### `greedy-5case` — sampling is not where the missing accuracy lives

Prompted by the observation that `InferenceConfig.ragOptimized` sets `temperature = 0.7` with the
comment `// Balanced creativity`, on a product whose promise is answers attributable to the user's
documents.

**Verified against Apple before testing.** `GenerationOptions` exposes exactly four properties —
`samplingMode`, `temperature`, `maximumResponseTokens`, and `toolCallingMode` (27+) — read from the
SDK's own `.swiftinterface`. **There is no frequency, presence or repetition penalty**, so those
three fields in `ragOptimized` are dead config that never reach the model. Apple documents
temperature as 0–1 (the harness validates 0–2) and describes low values as "more stable and
predictable" against "more creative license"; the WWDC25 deep-dive describes `.greedy` as making
output deterministic.

**Result, 5 cases, greedy vs the same 5 under `topk`:** 2/5, against 3/5 and 2/5 for the two topk
runs. Greedy matched `rescue-position-fix` on **all five** and differed from `passage-level-1` only
on `3319d565` — the one case those two topk runs already disagreed on. **No effect.**

**What the negative result buys.** The three failures are not sampling accidents: greedy takes the
highest-probability token every time and they still failed. They fail structurally — the evidence
did not arrive, or the model could not extract from what did. That is consistent with the
passage-level decomposition and it removes temperature from the list of things worth tuning for
accuracy. n=5 rules out a large effect, not a small one.

**Still worth changing the default, for a different reason.** Greedy is deterministic, so a greedy
arm has no sampling noise at all — which is the cheapest available fix for the reproducibility row,
independent of accuracy.

### **No benchmark has ever measured the shipping configuration** — found 2026-08-21

Chasing why the greedy run logged `config had 0.4` when `InferenceConfig.ragOptimized` sets 0.7.

**The real temperature chain for a Standard answer:**

| step | value | site |
| :-- | --: | :-- |
| `InferenceConfig.ragOptimized` | 0.7 | `LLMModel.swift:182`, commented `// Balanced creativity` |
| `min(config, qualityMode.temperature)` | **0.4** | `RAGService.swift:12745`, `.standard` = 0.4 |
| evidence-first / cautious prompt | 0.2 | `RAGService.swift:12740` |
| `highAccuracy` retrieval config | 0.2 | `RAGService.swift:12749` |
| retry / repair / fallback | 0.2 / 0.15 / 0.4 | `:13333`, `:13403`, `:14337` |

Every application is a `min()`, so 0.7 is a **ceiling that is immediately clamped**, never an
operating value. **A correction to a claim made earlier the same day: the app does not ship at 0.7.
Standard ships at 0.4 and several paths clamp to 0.2.** The `// Balanced creativity` comment is
misleading but the number beside it never reaches the model.

**The consequence, and it invalidates the framing of every accuracy figure in this ledger.** The
harness applies `--temperature` inside `LLMService`, at the single point an `InferenceConfig` becomes
`GenerationOptions` — which is **downstream of every clamp above**. So `--temperature 0.7` does not
reproduce the app, it **overrides the app's own 0.4 and forces a hotter setting than ships.**

| run | flags | effective temperature |
| :-- | :-- | --: |
| `passage-level-1` | `topk`, `--temperature 0.7` | 0.7 |
| `rescue-position-fix` | `topk`, `--temperature 0.7` | 0.7 |
| `baseline-49` (the 4.9 arm) | `topk`, `--temperature 0.7` | 0.7 |
| `greedy-5case` | `greedy`, no `--temperature` | 0.4, and inert under greedy |

**So 40%, 44%, 48% and 4.9's 27.3% were all measured at a temperature the app never uses.** The
4.9 vs 5.0 comparison remains valid — both arms were forced to the same 0.7, so the delta is still
attributable to code — but the absolute numbers do not describe the shipped product.

**Untested and now the highest-value cheap experiment available: `topk` at 0.4**, the actual
shipping value. If lower temperature helps at all, the shipping app is already performing better
than every number on record. That is a plausible upside nobody has measured, and it costs one run.

**Do not add `--temperature 0.7` to future runs by habit.** A run intended to describe the product
should pass no `--temperature` at all and let the clamps do their work; a run intended to compare two
builds should pin both arms to the same value and say so.

### `shipcfg-50` — the shipping number, and where the reranker's work goes to die

| run | commit | config | result |
| :-- | :-- | :-- | :-- |
| `shipcfg-50` | `67ba90a` | 83 QASPER cases, standard, **no `--temperature`** so the app's own 0.4 clamp applies | **32/83 = 38.6%**, all 83 completed, 311 min |

First run that describes the shipped product rather than one forced hotter than the app ever runs.

**Temperature, tested and not supported.** On the 25 cases shared with the 0.7 runs: 0.7 scored
11/25 and 12/25, 0.4 scored **9/25**. One case better, three worse, **sign p = 0.938**. Cooling from
0.7 to 0.4 did nothing measurable and the point estimate leans the wrong way. **Greedy (0.0) is
still untested** and remains the open version of that hypothesis.

**The largest measured loss in the pipeline, now at n=83:**

```
rerank   r@1 0.610   MRR 0.690
final    r@1 0.442   MRR 0.574
```

17 cases have gold at rank 1 after reranking and not at final; 4 gain it; **net −13**. Cases that
lose rank 1 answer correctly **4/17 (23.5%)** against **28/66 (42.4%)** for those that keep it.

**It is demotion, not deletion.** Tracing the reranker's top *chunk id* through `STAGE SOURCES`:
**14 of 17 are still in the final prompt**, just no longer first (landing positions cluster at 4);
only 3 are removed outright. So the chunk survives the budget and loses the highest-attention slot.

**Two hypotheses tested and rejected before the third:**

- **`filterBySimilarity` dropping the top chunk.** Rejected. It has no top-1 guarantee, but lost
  cases had *fewer* chunks filtered (33.0) than kept cases (39.0), and 14 of 17 top chunks survive.
- **Document-summary injection prepending.** Rejected as the main cause despite
  `contextCandidates = selectedSummaries + topDetailChunks` (`RAGService.swift:11184`) provably
  placing summaries ahead of every detail chunk. At n=83 it fires on 36 cases at **38.9%** accuracy
  against **38.3%** when it does not, and explains only 7 of the 17 losses — the same rate as in
  cases that keep rank 1. Five losses had no summaries at all.

**What survives: the cross-encoder's ranking is overwritten by a heuristic.** Before assembly,
`orderedCandidates` is re-sorted (`RAGService.swift:11975` and `:12016`) — by document order for
procedural queries, and for extractive-intent queries by
`EvidenceScoringPolicyService.extractivePriorityScore`, a keyword-and-structure score that is **not
the cross-encoder score**. QASPER is overwhelmingly extractive. Measured: the rank-1 loss rate is
**27.0% (10/37)** where that re-sort runs against **15.2% (7/46)** where it does not.

**Stated at its real strength: association, not a proven sufficient cause.** Detection of the
re-sort is a log-string proxy, and 7 cases lose rank 1 without it. At least two mechanisms are in
play. What is certain from code is that `filterBySimilarity`, the spec rescue, `ensureDocumentCoverage`,
MMR and lost-in-the-middle reordering **all preserve position 0** — verified by reading each — so the
demotion has to come from a prepend or a re-sort, and the re-sort is the one that correlates.

**The question this raises is a design one, not a bug report:** the pipeline runs a trained
cross-encoder and then replaces its ordering with a hand-written keyword heuristic on exactly the
query class the benchmark is made of. Whether that heuristic earns its place has never been measured.
The cheap test is to make it a tie-break or a bounded boost rather than a full re-sort, and re-run.

### `greedy-25-a` / `greedy-25-b` / `greedy-83-1` — the reproducibility debate, run as a controlled pair for the first time, and a bigger finding underneath it

Overnight run, 2026-08-23 into 08-24, ~8h14m wall clock, unattended. Two prerequisites went in first:
`RERANK CHUNK TEXT` added to `DebugRAGValidationHarness.buildReport` (commit `058a27b`) so
`passage_present` can eventually be scored at rerank as well as final, not just instrumented for it —
and every run below carries it, smoke-verified before the long runs started (90 chunks captured at
rerank against 7 at final on the smoke case, and the 1-in-25/6-in-83 reports without the block are
exactly the negative-control cases with no expected source, matching the documented guard clause).

**Part 1 — `greedy-25-a` vs `greedy-25-b`: a deliberate A/A pair, not a found one.** Every prior
reproducibility finding in this file was discovered by accident, comparing two runs launched for
unrelated reasons. This is the first pair launched specifically to test it: identical manifest,
identical flags, `--sampling greedy`, no `--temperature`, back-to-back, same commit.

| stage | r1 (a → b) | mrr (a → b) |
| :-- | :-- | :-- |
| vector | 0.500 → 0.500 | 0.567 → 0.567 |
| lexical (control) | 0.625 → 0.625 | 0.691 → 0.691 |
| fusion | 0.625 → 0.625 | 0.708 → 0.708 |
| boosted / candidates | 0.542 → 0.583 | 0.642 → 0.656 |
| rerank | 0.667 → 0.667 | 0.753 → 0.753 |
| final | 0.417 → 0.458 | 0.601 → 0.611 |

**Vector, lexical and fusion are bit-identical.** `compare_benchmark_runs.py`'s per-case vector r1
breakdown: 0 better, 0 worse, 24/24 unchanged — the sign test has no discordant pairs to test. This
matters beyond this pair: every reproducibility finding earlier in this file (90% vs 91% keyword hit
rate, `passage-level-1` vs `rescue-position-fix` scoring 11/24 vs 12/24) was measured under
`topk`, and blamed the divergence on embedding or vector search. Under `greedy` that stage is now
perfectly stable. That points the earlier cause back at the sampler, not retrieval — consistent with,
not yet proof of, since this is one pair.

**Two smaller, real, new sources of jitter remain**, neither of them the sampler: one case's rank
flips at `boosted`/`candidates` (which apply keyword-match and structure-aware boosts, not the
cross-encoder), and reranking absorbs it (`rerank` r1 identical) but a *different* case flips between
`rerank` and `final` instead. Both stages run before generation, so this is not sampler noise wearing
a different hat — something in the boost step and something between rerank and final still moves
under an unchanged input. Not chased further tonight; worth a look if a future A/B lands inside a
2-case margin.

**Accuracy held exactly: 9/24 → 9/24, same 9 cases both times.** That is the headline this pair was
launched to get: the residual stage-level jitter above never changed which cases the model actually
got right. Prior A/A noise floor was ±1 case at n=24 (`rescue-position-fix`/`passage-level-1`, 12 vs
11); this pair, the first deliberately designed to isolate the sampler, shows ±0. **Greedy sampling
makes this benchmark's accuracy trustworthy for A/B comparison, which it measurably was not under
`topk`.** One pair is not proof against a future divergence, but it is the cleanest evidence produced
here so far, specifically because it was designed rather than found.

**Part 2 — `greedy-83-1` vs `shipcfg-50`: not what this run was for, and the bigger number.**
`shipcfg-50` (`2201b8b`, `topk`, no `--temperature`, effective 0.4) scored 32/83 = 38.6%.
`greedy-83-1` (`058a27b`, `greedy`, no `--temperature`) scored **39/83 = 47.0%**. Between those two
commits, the *only* change touching any RAG, evaluation or harness path is this run's own 18-line
additive instrumentation (`git diff --stat 67ba90a..058a27b` over
`Services/RAG/`, `Services/Evaluation/`, `DebugRAGValidationHarness.swift`, `run_quality_matrix.py`)
— so this is a clean single-variable comparison of sampling mode, not confounded by code drift.

Paired sign test on the 83 shared cases, computed from `score.correct` in each run's
`results.jsonl` (not run by `compare_benchmark_runs.py`, which defaults to the `vector`/`r1`
breakdown and has no accuracy-column mode): **8 cases flipped wrong→right, 1 flipped right→wrong,
two-sided exact sign test p = 0.039.** That clears both p<0.05 and this repository's own stated
resolution floor for this n (6 discordant cases favoring one side).

**This was not what the run was launched to measure, and says so up front so it isn't over-read.**
`greedy-5case` (2026-08-21, n=5) found "no effect" from sampling and explicitly flagged itself as
underpowered — "n=5 rules out a large effect, not a small one." An 83-case run with real power is
the first fair test of the same hypothesis, and it leans the opposite way from the pilot: not neutral,
measurably better. **This is not a recommendation to change the shipping sampler.** Greedy has
failure modes this benchmark's extractive QASPER questions may not surface (repetition, degenerate
loops on open-ended generation), and the app's actual default was never in question here — this run
was about whether *any* comparison could be trusted, not about which sampling mode should ship. If
the shipping default is reconsidered, it deserves its own measurement, deliberately, not a footnote
inherited from a reproducibility run.

**What the new rerank-stage text unblocks and does not yet answer.** Every report in these four runs
now carries `RERANK CHUNK TEXT`, so `passage_present` can be computed at rerank as well as final —
splitting "never retrieved" from "retrieved, ranked, then cut by the budget" for the first time. No
scoring pass against that block exists yet; `results.jsonl`'s `score.passage_present` /
`passage_chunk_rank` fields are final-stage only. That is the immediate next step this unlocks, not
something this run itself measured.

**Provenance.** All four runs: `SWIFT_DETERMINISTIC_HASHING=1`, macOS Debug build from
`/private/tmp/oi-src`, `--pcc deny` (PCC unreachable from this shell regardless), `--pool-limit 10
--top-k 3`. `greedy-25-a`/`greedy-25-b`/`greedy-83-1` at commit `058a27b`, tree clean. Full chain
launched detached (`caffeinate -ims`, `nohup`, `disown`) so it survived independent of the driving
session; a prior identically-scoped attempt (`greedy-50`, 2026-08-21) was started and abandoned with
no `results.json` ever written and no note anywhere of why — not deleted, per this repo's own rule,
but worth knowing a first attempt at this exact run died silently once already.

### 2026-11-11 compute profiles, import depth (`2026-11-11-compute-profiles`)

Extraction-fidelity set (8 PDFs) and olmOCR-Bench 160 pages, once each under Balanced, Performance and Maximum on one
build (ee2ce21b). Stored text identical across the three on both sets (fidelity mean 0.944/0.966/0.966/0.975 each;
olmOCR 465 of 755 checks each). A probe confirmed Maximum was active. One run per profile, ladder order: times are not
comparable yet. Retrieval per profile not run.

### 2026-11-12 answer quality by mode, the app's own model path (`2026-11-12-0053-answer-modes`)

`scripts/bench_answer_modes.sh` at c1e4a160 (5.8), its first run: a copy patched by `scripts/sim_model_copy.py` so the
app's `AppleFoundationLLMService` answers in the iOS 27.0 Simulator (iPhone 17 Pro, read as an A18 Pro), 20 cases of
`Benchmarks/rag_eval_v1.jsonl` over the tiny research suite, graded pass/fail by Apple's Evaluations model judge
(`AnswerQualityEvaluationTests`). One case is 0.05.

| Mode | Model path | Correct | Answered | Refused | Minutes |
|---|---|---|---|---|---|
| Standard | app | 0.45 | 20 | 0 | 10 |
| Deep Think | app | 0.40 | 20 | 0 | 38 |
| Maximum | app | not measured (see below) | 3 | 17 | 19 |
| Standard | test's own model (the 2026-10-21 path, 0.3 then) | 0.50 | 20 | 0 | 7 |

**What it settled.** Deep Think does not beat Standard here: one case lower, at 3.8 times the time, as on QASPER in
August (2/8 and 3/8 against 4/7 and 5/8). The app's path and the test's own model are one case apart (0.45 and 0.50),
so the path difference the copy exists to remove did not move the score on this set. Standard at 0.50 against 0.3 on
2026-10-21 is two months of changes on the same 20 cases, one run each.

**Maximum: a test defect, not a score.** It answered 3 and then refused 17 in 0 s with "Today's 3 free Maximum answers
are used": the plan the action's gate reads (`ShortcutsPlanGate`, `EntitlementStore.currentEffectiveTier`, standard
defaults) was Free again after `make` set Pro, most likely rewritten by the host app's own entitlement store. Fixed in
the test on 2026-11-12 (Pro and a zero count before every Maximum question), and re-run alone the same night. Of the 3
it answered, one ran 347 s and came back "Needs Verification" (Gate E, semantic grounding, failed), and one planner
call overflowed ("The session's transcript exceeded the model's context size").

**Not settled.** Per-question agreement between modes (the test prints only the mean); variance (one run per mode);
whether the Simulator's model window matches the iPhone's 4,096 tokens.

**Maximum, re-run alone (`2026-11-12-0223-answer-modes`, 02044980):** 0.50, 20 answered, 0 refused, 31 minutes, a
median of about 63 s a question (1 to 98 s). 8 of the 20 answers open with "Needs Verification" (the Maximum answer
gates did not all pass). So on this set Maximum ties Standard with the test's own model (0.50), is one case above
Standard on the app's path (0.45) and two above Deep Think (0.40), at about 3 times Standard's time. The first graded
Maximum run there has been.

### 2026-11-12 Deep Think reads its cited passages; Standard citations added (`2026-11-12-deepthink-source-passages`)

`EvidenceReachBenchmarkTests` on the patched Simulator copy (`scripts/sim_model_copy.py`, iOS 27.0, window held at
4,096), uncommitted tree on 1e86b30c, slice 0 of 3 of the 158 table questions (53), each question asked in one process
twice: "before" with `RetrievalAblation.chainSourcePassages` and `.citationAttribution` off, "after" with both on.
Scored by `python3 scripts/evidence_reach.py answers` (right means the answer holds the cell's value). One case is
1.9%. The decision rule was set before the run: a change ships only if "after" is no worse than "before".

| Mode | Before | After | Per question | Other |
|---|---|---|---|---|
| Deep Think, right | 37/53 | 42/53 | 7 better, 2 worse, p=0.18 | median 80 s to 65 s; answers with no `[S#]` 5 to 1; errors 0 and 0 |
| Standard, right | 44/53 | 45/53 | 2 better, 1 worse, p=1.00 | with a citation 51 to 49; same words 0/53 |

**Corrected 2026-11-13.** The exact-text rule above counted a right value written another way as wrong ("6,259 (3.4%)" for the cell "6259 (3.4)", "4.1 to 24.7" for "4.1-24.7", "2.48 with a 95% CI of 1.11-5.55"). Rescored with `evidence_reach.holds` (the same numbers in order, at most one other number between; `OI_STRICT=1` gives the old rule): Deep Think 46 before, 45 after (0 better, 1 worse); Standard 46 and 47 (1 better, 0 worse). The Deep Think change does not raise accuracy; it keeps it at 85% while answering in 65 s against 80 s. The other misses: 4 questions whose cell never reached the model (3 tables printed as images in fbioe-12-1379574, 1 row the 2026-11-12 coverage fix restores), and on the rest a value said to be absent while in the passages (PAH, Deep Think), a raw passage returned as the answer (JAMA #5#5, Deep Think), the wrong row of JAMA's wide Table 1 (#5#2, both), a forest-plot row not read (#7#14, both).

**What it settled.** Both changes pass the rule and ship in 5.8. The Deep Think final step read 3 to 8 passages in a
prompt of about 2,100 of 4,096 tokens on 52 answers. The citation change ran on 10 streamed answers and labelled 6;
each added label names a passage holding the sentence's value (checked by hand against the saved sources), 2 of the 6
on the sentence beside the value's. The model's own citing varied more than the change did: before, 2 Standard answers
reached the missing-citation path's end without a label; after, 4 did, 3 of them citing as "(S1)", "ROW 3, S1" or
"[2]", which the app does not read (not handled; Future Backlog candidate).

**Not settled.** Slices 1 and 2 (the other 105 questions); a device run; 8,192 on the Mac; the result JSON keeps
Standard's sources but not its context text (`standardContext` is empty), so label checks used `standardSources`.
The first attempt (stopped 25 minutes in, measuring the citation code before its review fixes) is in `aborted-1405/`;
a 2-question smoke run in `smoke/`.


### 2026-11-12 Table and text fidelity, four table fixes measured one by one (`2026-11-12-tables`)

`ExtractionFidelityRecorder` on the patched Simulator copy (iOS 27.0), the 8 fidelity PDFs in
`/private/tmp/oi-fidelity/pdfs`, scored with `scripts/ingestion_unit_tests.py` against
`2026-11-08-extraction-fidelity/checks` (515 checks; baseline `after11`, 433) and number recall with
`scripts/extraction_fidelity.py --compare after11`. Rule set before the runs: keep a fix only if it loses no passing
check and no paper's number recall drops. `bash run_fidelity.sh <label> <commit>` builds that commit.

| Run | Commit | What it held | Passing | Lost | Note |
|---|---|---|---|---|---|
| `tab-d` | e9eb9992 | layout coverage (D) | 432 | 5 | fbioe number recall 0.865 to 0.973; 5 sentences out of order (oncotarget p2, p10, p11; ijms p21) |
| `tab-da` | 8f99dac1 | D, exact-order exception; region overlap (A) | 438 | 5 | A: JAMA 26 to 32 of 47 |
| `tab-all` | 3e01e901 | D placed after column detection; A; caption tables (B); Vision preference (C) | 438 | 6 | ijms back; C lost 2 PAH checks and raised PAH invented numbers 34.7 to 73.6 per 1,000; B gained nothing |
| `tab-fin` | fb548e4d | D with a three-quarters-held exception; A; B searching all words; C removed | 439 | 4 | the 4 oncotarget sentences, lines swapped in pairs, all words kept |

**What it settled.** A ships (no loss). D ships against the rule's letter: its 4 losses are line order on one paper
with every word stored, and it returns about a hundred numbers on fbioe (owner's rule 4, losing text is the worst
defect). B and C were withdrawn (de70ac6e, fb548e4d). Each open cause has a Future Backlog row.

**Not settled.** Why the oncotarget lines swap; B (Vision reads word tables as paragraphs, BL999's caption is not
text); C; the 8 checks on fbioe p8 and p11, tables that are images.

### 2026-11-13 Answer quality by mode, 5.7 against 5.8 (`2026-11-13-0014-answer-modes-5.8`, `2026-11-13-0142-answer-modes-v5.7.0`, `2026-11-13-0638-answer-modes-v5.7.0-max`)

`AnswerQualityEvaluationTests` through the app's own model service (`OI_EVAL_MODEL=app`), iOS 27.0 Simulator, 20
cases of `Benchmarks/rag_eval_v1.jsonl`, graded by Apple's Evaluations model judge, one run per mode. 5.8 is HEAD
cc8f4691 patched by `scripts/sim_model_copy.py`; 5.7 is the `v5.7.0` tag with the same four switches patched by
content (5.7's files were not yet split) and the answer test from 02044980 (5.7's own test had no mode switch). Run by
`BenchmarkRuns/2026-11-12-full-suite/overnight.sh` beside another Simulator job, so the seconds are indicative only.

| Mode | 5.7 | 5.8 | Median seconds 5.7 / 5.8 |
|---|---|---|---|
| Standard | 0.30 | 0.45 | 8 / 20.5 |
| Deep Think | 0.40 | 0.40 | 67 / 71.5 |
| Maximum | 0.25 | 0.40 | 78.5 / 79.5 |

**What it settled.** On this set 5.8 is no worse than 5.7 in any mode. Each case is 0.05, so Standard's and
Maximum's gains are three cases each and Deep Think is a tie; one run's spread is about two cases (Maximum on 5.8 gave
0.50 on 11-12 and 0.40 here).

**Not settled.** Per-question agreement (the test prints the mean only); repeat runs; the 5.7 run's first Maximum
attempt answered 3 and refused 17 (the plan reset the 11-12 fix addresses), so the figure above is the re-run with
that fix.

**Correction, 2026-11-13 afternoon: do not cite the table above.** The Evaluations model judge that graded it agreed
with a plain reading of the answers on 8 of 5.8 Deep Think's 20 (it failed answers that gave the reference word for
word and passed one that gave another token), so these means do not say which version answers better. The answers are
rescored by rule with `scripts/score_answer_eval.py` from the runs' result bundles; these three folders kept none
(bundles are kept since 7a7f3594), so 5.7 against 5.8 by rule needs a rerun of both.

### 2026-11-13 Granite against MiniLM in the app (`2026-11-12-full-suite`)

`DeepThinkRetrievalGoldenTests`, one pass, device windows, Simulator (CPU embeddings), MiniLM at 6e486015 (the
commit before the swap) against Granite at HEAD, scored by `2026-11-09-reranker-swap/scripts/score_golden.py`
(`golden-score.txt`):

| Mode, questions | hit@1 | hit@5 | MRR | rank better / worse |
|---|---|---|---|---|
| Deep Think 15, 92 | 0.402 to 0.413 | 0.511 to 0.609 | 0.461 to 0.495 | 20 / 12, p=0.215 |
| Deep Think 24, 19 | 0.421 to 0.421 | 0.579 to 0.632 | 0.498 to 0.528 | 5 / 2 |
| Maximum 15, 36 | 0.472 to 0.444 | 0.500 to 0.667 | 0.499 to 0.517 | 7 / 4 |
| Standard 20, 19 | 0.421 to 0.421 | 0.526 to 0.789 | 0.488 to 0.537 | 5 / 2 |

**What it settled.** Granite is no worse than MiniLM in the app on this set, so it ships (the rule set 2026-11-12).
**Not settled.** The 158 table questions with each embedder (`tables-score.txt`, running at the time of writing; that
comparison also differs in the 2026-11-12 table fixes); significance per mode.

**The table run, 2026-11-13.** MiniLM finished (`reach-minilm.json`, 04:12 to 08:14). Granite's run died at question
143 of 158 at 12:06, when simulator services crashed on all three Simulators booted at once on this 18 GB Mac (crash
reports for tccd, geoanalyticsd, dtdeviceinfod and PosterBoard, 12:03 to 12:06); the test saves its results only at
the end, so nothing of it was kept. To rerun alone.

### 2026-11-13 Deep Think answer-first and Maximum source passages, paired (`2026-11-13-answer-first`, `2026-11-13-maximum-passages`)

Paired runs of `EvidenceReachBenchmarkTests` (each question asked with the switch off and on in one process), 53
slice-0 table questions for `answerFirst` and 30 for `maximumSourcePassages`. **Three attempts on 2026-11-13 were
invalid and are not results:** every answer was "Here are the most relevant excerpts" (`[QuotesOnly] ... no model
call`). The fresh Simulators started the app before Apple's model was ready, so the launch picked On-Device Analysis
(Quotes only, which since 5.8 calls no model), and the launch recorded that as the person's choice
(`primaryModelUserOverride`), so nothing lifted it. That was an app defect, fixed in 98582397, 09e29487 and 7cac2076;
the first attempts' files are under `invalid-model-unavailable/`, and the 12:31 attempt's `score.txt` (44 of 53 both
ways, 0 with a citation) is excerpts scored, not answers. The benchmark now stops at once when Quotes only is
selected. Results: below, when the rerun on 7cac2076 finishes.

**Answer first, valid run (7cac2076, 13:08 to 16:34).** 0 `[QuotesOnly]` lines, 0 excerpt answers of 106.

| Deep Think, 53 questions | Right (`holds`) | Median seconds |
|---|---|---|
| `answerFirst` off | 45 | 82 |
| `answerFirst` on | 46 | 68 |

3 gained, 2 lost, p = 1.00. **Settled:** the change does not cost accuracy on these questions and is faster at the
median; kept on (rule: keep unless the right count drops). **Not settled:** a gain in accuracy (one question); other
question kinds; the seconds were taken while device builds ran beside it. The same process's Standard answers, which
the switch does not touch, were right on 49 and 47 of 53 with different words in all 53: one run's spread for Standard
is two questions. Files: `reach-before-s0.json`, `reach-after-s0.json`, `score-valid.txt` (`score.txt` there is the
12:31 excerpts run).

**Maximum source passages, valid run (e9a6cd80, 17:05 to 18:59).** 0 `[QuotesOnly]` lines, 0 excerpt answers, 0
refusals of 60.

| Maximum, 30 questions | Right (`holds`) | Median seconds |
|---|---|---|
| `maximumSourcePassages` and `answerFirst` off | 8 | 117 |
| both on | 25 | 79 |

17 gained, 0 lost, p < 0.001. **Settled:** with the top source passages in front of its final step (and the
answer-first instruction), Maximum gives the table's value on 25 of 30 where its notes alone gave it on 8; both stay
on. **Not settled:** each switch's own share for Maximum (they were off together); the other 128 table questions;
prose questions. Files: `reach-before-s0.json`, `reach-after-s0.json`, `score-valid.txt`.

### 2026-11-14 Overnight: unit suite, answer test by rule on 5.8 and 5.7, the draft-abstain switch (`2026-11-14-overnight`, `2026-11-14-0149-answer-modes`, `2026-11-14-0255-answer-modes-draftAbstainOff`, `2026-11-14-0346-answer-modes-v5.7.0`, `2026-11-14-0345-answer-modes-v5.7.0`, `2026-11-13-draft-abstain`)

One Simulator at a time, iOS 27.0, the app's own model path. 5.8 is 581a37b6; 5.7 is `v5.7.0` with its four Simulator
switches patched by content and the answer test from 02044980. Scored by rule (`scripts/score_answer_eval.py`); the
model judge's column is not used.

| 20 cases, right by rule | 5.7 | 5.8 |
|---|---|---|
| Standard | 10 | 10 |
| Deep Think | 12 | 13 |
| Maximum | 10 | 14 |

**Unit suite (5.8, unpatched):** 1,751 tests, 20 skipped, 1 failure (`ExtractedValueRelevanceTests`, an invalid
regular expression in 5.8 code, fixed the same morning and rerun green).

**Draft abstain (Deep Think):** off, 8 answers with Needs Verification (7 right, 1 wrong), 14 right; on, 3 (2 right, 1
wrong), 13 right. Kept on.

**What it settled.** On this set 5.8's Maximum answers 4 more of 20 than 5.7's; Standard is level and Deep Think one
case ahead, inside a run's spread of about two. **Not settled, and why the totals are low in both versions:** the
three lost-in-the-middle cases were asked unscoped in every run (the test's own scoping logged `scoped=0`), so at most
one can pass; five "which document mentions" cases are answered "[S1], which ..." without the file's name, which the
rule needs. `2026-11-14-0345-answer-modes-v5.7.0` is the first 5.7 attempt, stopped at once (no patched-copy marker);
`2026-11-13-draft-abstain` was stopped by a game after 7 minutes and its table questions never reached the check.

### Not runs: `household_v1` and `xcloud` (noted 2026-11-13)

`household_v1` is a fixture set (nine household documents, 17 answerable questions and 3 negative controls, its
`manifest.json`), not a run; runs that use it name it in their own entries. `xcloud` holds only `last_run.json`, the id
and number (499) of the last Xcode Cloud build a script started. Neither has results to record.

## Backfill 2026-11-12: run folders that had no entry

On 2026-11-12 35 of the run folders since 2026-10-07 had no entry here, so their results were invisible to any session that searched this file. Each entry below was drafted by Antigravity (gemini-3.8-flash-high, read-only) from the folder's own files; every one of its 336 figures was checked by script to appear in that folder, and the entries for extraction fidelity, the reranker swap and Deep Think speed were read against their READMEs and completed by hand. The folder's README stays the authority; read it before quoting a figure.

### 2026-10-07 On-device language model context window latency, cache, and recall (`2026-10-07-context-window-probe`)

The probe measured latency, cache reuse, recall, and multi-hop reasoning on an Apple M3 Pro Mac with 18 GB memory running macOS 27.0 26A428 and Xcode 27.0 27A266a using SystemLanguageModel.default.contextSize 8192 with the AFM 3 Core Advanced variant and greedy sampling. The test used 93 distinct chunks of research-paper text saved across 25 evidence listings, testing evidence targets of 800, 2,000, and 6,600 tokens with 80 response tokens. It left iPhone and iPad measurements open, noting no iPhone or iPad was measured.

Source: README.md.

### 2026-10-09 Semantic chunker execution time and memory footprint on large text (`2026-10-09-chunker-large-text`)

Execution time and memory footprint were measured on an Apple M3 Pro running macOS 27.0 after an 88.50 MB file with 92,730,215 characters froze a 5.7 development build on an iPhone 16 Pro Max. For 1,000,525 characters, execution time dropped from 13.94 s before to 6.47 s after, and for 4,000,142 characters from 148.52 s to 26.38 s. Peak memory footprint for 1,000,525 characters dropped from 107.4 MB to 22.1 MB. The change settled chunker performance on generated text, leaving verified identical outputs across 75 runs and 7,719 chunks.

Source: README.md.

### 2026-10-09 Language model session cache reuse and prewarm latency (`2026-10-09-session-cache-probe`)

Session caching and prewarming were measured on an Apple M3 Pro Mac with 18 GB memory running macOS 27.0 (26A428) with SystemLanguageModel.default contextSize 8192 on prompts of about 6,100 input tokens. A fresh session without prewarm had a time to first token of 7.64s and a total time of 8.49s with cached 0 tokens, while a second turn in the same session reached a time to first token of 3.03s and total time of 3.10s with cached 6304 tokens. Prewarm put no prompt tokens in the cache across four forms tried, and a prewarm while another session generated delayed that session first word by about 5 s. The run left open whether cache behavior differs on an iPhone or cold model.

Source: results.txt.

### 2026-10-10 Core AI embedding model throughput and input shapes (`2026-10-10-embedding-model-throughput`)

Embedding model throughput and input shapes were measured on an Apple M3 Pro running macOS 27.0 using probe.swift calling InferenceFunction.run on 420 real tokens padded to 512. Single calls processed 173.6 passages a second at 5.8 ms each, rising to 213.8 a second with 2 calls in flight, 219.0 a second with 4 calls, and 223.0 a second with 8 calls. Shapes other than [1, 512], including [1, 256] and batched inputs like [4, 512], were refused. The probe settled that the model requires fixed 512 positions, leaving open what more calls in flight yield on a phone.

Source: README.md.

### 2026-10-10 Ingestion data loss points and interface responsiveness hotspots (`2026-10-10-ingestion-and-ui-audit`)

Ingestion stages and interface responsiveness were audited through code inspection and a scratch probe on macOS 27. In the probe, text normalization deleted tabular numeric cells such as 34, 2024, and SKU10293, while garbage filtering on Greek, Chinese, or Arabic text deleted 4 of 4 lines. The UI audit identified 15 responsiveness hotspots, including 24 Published properties on RAGService and 56 on SettingsStore driving main actor updates. The audit mapped defects and potential fixes, leaving code implementations open.

Source: A-ingestion-cost-and-loss-map.md, D-ui-responsiveness.md.

### 2026-10-10 Architectural cost map and work packages for large libraries (`2026-10-10-large-library`)

No result recorded in the folder. It holds markdown analysis files and work packages including A-services-cost-map.md, C-interface-cost-map.md, and W4-per-passage-costs.md. The work mapped passage scaling hotspots across services and interfaces, including bounding spec table scans to a 5,000-passage sample for libraries over 5,000 items.

Source: W4-per-passage-costs.md.

### 2026-10-12 Documentation drift and factual claim verification for version 5.7 (`2026-10-12-docs-sync`)

Documentation drift and decision records were audited across repository documentation following 5.7 changes. The drift report checked documentation files and found about 75 statements out of date, classifying 35 as STALE and 32 as UNVERIFIED. A companion refuting review inspected 540 statements against the implementation and reported 0 WRONG and 0 UNSETTLED. The audit settled the alignment between doc statements and codebase reality without running benchmark suites.

Source: D1-doc-drift-opus.md, R1-refute-gemini.md.

### 2026-10-13 Library analysis execution time and memory on a large store (`2026-10-13-launch-analysis`)

LibraryIntelligenceCenter.analyzeLibrary was measured on an iOS 27.0 Simulator test process on an Apple M3 Pro Mac with 18 GB memory using an unoptimised build and a synthetic 144,247-passage store of 143.8 MB text. The path as it was through 5.6 on all 144,247 passages took 199.1 s with a peak memory increase of +1,054 MB, whereas the 5.7 sampling path on 3,999 passages took 6.22 s with +4 MB memory in the final commit tree. The first-question vocabulary build completed in 2.65 s on the final tree. The run settled the sampling strategy for large library analysis while noting profile timing with multiple documents was not included.

Source: README.md.

### 2026-10-14 Speech transcription latency and utterance extraction across audio formats (`2026-10-14-asset-transcriber-probe`)

Speech transcription was probed across audio and video containers using audio file input, asset input, and each-track modes. On speech.aiff, audio file input took 0.46s and asset input took 0.24s for 3 utterance(s). For speech-opus.mp4, audio file input returned OSStatus error -1, while asset input took 0.14s and each track mode took 0.15s, both extracting 3 utterance(s). On twotracks.mov, audio file input took 0.26s with 0 utterance(s), whereas each track mode took 0.22s and extracted 3 utterance(s).

Source: results.txt.

### 2026-10-15 Accessibility audit issue counts across screens with hardware HUD disabled (`2026-10-15-accessibility-audit-xray-off`)

Apple accessibility audit issues were measured on Chat, Documents, and Settings in an iOS 27.0 Simulator (iPhone 18 Pro) with Xcode 27.0 on a Debug build after commit 94c4007 with showSiliconHUD = false. In light mode with default text, the audit reported 54 issues, consisting of 28 contrast, 20 Dynamic Type, and 6 clipped text issues. In dark mode with default text, it found 44 issues, with 18 contrast, 20 Dynamic Type, and 6 clipped text issues. At the largest accessibility text size, issues totaled 35 in light mode and 31 in dark mode.

Source: README.md.

### 2026-10-15 Accessibility audit issues with default hardware HUD enabled (`2026-10-15-accessibility-audit`)

Accessibility audit issues were measured across Chat, Documents, and Settings on an iOS 27.0 Simulator (iPhone 18 Pro) running Debug build c300bf8 with Xcode 27.0. The audit reported 26 contrast issues in light mode with default text and 26 in dark mode, with zero Dynamic Type or clipped text issues recorded. At largest accessibility text, the audit reported 27 issues in light mode and 25 in dark mode. Every contrast issue except one Settings search field issue was caused by the hardware X-Ray overlay floating over the screen. An evening correction settled that switching off the overlay revealed 31 to 54 underlying screen issues.

Source: README.md, CORRECTION-2026-10-15-evening.md.

### 2026-10-15 Atlas categorization and dimensional projection execution time (`2026-10-15-atlas-main-thread`)

Atlas categorization and projection algorithms were timed on an Apple M3 Pro Mac with 18 GB memory running macOS 27.0 26A428 with Xcode 27.0 (27A266a) using Swift 6.4 compiled with -O. On 6,000 synthetic passages, categorizeContent took 3496 ms on run one and 3501 ms on run two, while findNearestTopics for 5 recent documents took 36 ms and 34 ms. For 6,000 random vectors of 512 dimensions, projection times were 227 ms for pca, 3 ms for rp, 13393 ms for umap, and 30769 ms for tsne. The probe settled why Atlas categorization and map projection were moved off the main actor in version 5.7.

Source: README.md.

### 2026-10-16 Accessibility audit issue reductions following style pass 1 (`2026-10-16-accessibility-pass-1`)

Accessibility audit issues were measured on Chat, Documents, and Settings in an iOS 27.0 Simulator on a Debug build after commit e13f664 with the hardware X-Ray off. With default text, issues dropped from 54 before to 22 after pass 1 in light mode, and from 44 before to 18 after in dark mode. At the largest accessibility text size, issues dropped from 35 before to 11 after in light mode, and from 31 before to 9 after in dark mode. Pixel contrast measurements on gray text improved from 3.4 to 5.2 to 1 on white, while .caption2 text remained reported as partially unsupported Dynamic Type.

Source: README.md.

### 2026-10-16 Accessibility audit issue reductions following layout pass 2 (`2026-10-16-accessibility-pass-2`)

Accessibility audit issues were measured on Chat, Documents, and Settings in an iOS 27.0 Simulator on a Debug build after commit 54f0f84 with pass 2 and review fixes applied. In light mode with default text, issues fell from 54 originally to 22 after pass 1 and reached 11 in the final tree. In dark mode with default text, issues decreased from 44 originally to 18 after pass 1 and reached 14 in the final tree. At largest accessibility text, issues reached 7 in light mode and 7 in dark mode. Pixel measurements confirmed that named contrast items measured 5.06 to 13.3 to 1, while .caption2 remained flagged by the audit.

Source: README.md.

### 2026-10-16 Accessibility contrast and layout across common task flows (`2026-10-16-accessibility-pass-3`)

Common user task flows including first run, seeded answers, and document import were audited on an iPhone 18 Pro Simulator running iOS 27.0 across five appearance and text size settings. Initial run t3 revealed broken words, cut buttons on the import panel, and measured contrast failures on the sources list and plans sheet. After layout and review fixes in runs t4 through t6, library rows improved from initial contrast ratios of 3.35 to 3.38 to 1 up to passing levels, with remaining items between 2.0 and 4.5 being off-screen or paused row details at 4.24 to 4.43. The audit settled common task layouts at large text sizes, leaving VoiceOver on physical devices unmeasured.

Source: README.md.

### 2026-10-17 Semantic chunker keyword tie determinism and passage overlap bounds (`2026-10-17-chunker-overlap-and-ties`)

Determinism and chunk overlap were evaluated on an Apple M3 Pro Mac running macOS 27.0 with Swift 6.4 across old (commit 37f20d6), new (commit a30dba7), and fix versions of SemanticChunker.swift. Across two unseeded processes without deterministic hashing, lines differing between runs dropped from 45 of 75 in the old version to 0 of 75 in new and fix. On the jsonl-250k text under the processor setting (overlap 50), passages dropped from 463 in old to 289 in new and 288 in fix, with median overlap falling from 64 to 50 and passages inside the one before falling from 224 to 0. The fix stopped redundant trailing overlap passages, settling deterministic chunking output.

Source: README.md.

### 2026-10-18 Core ML compute plan device allocation and inference latency (`2026-10-18-compute-plan`)

MLComputePlan device allocations and single prediction latencies were measured for EmbeddingModel and ReRankerModel on an Apple M3 Pro Mac (18 GB memory, macOS 27.0 26A428, Xcode 27.0) across four MLComputeUnits settings. For EmbeddingModel, median latency was 7.86 ms on cpuOnly (161 CPU operations), 4.78 ms on cpuAndGPU (161 GPU operations), and 6.90 ms on all (150 ANE, 11 CPU operations). For ReRankerModel, median latency was 0.69 ms on cpuOnly, 0.87 ms on cpuAndGPU, and 0.74 ms on all (55 ANE, 11 CPU operations). The probe confirmed both models compile without validation errors to Neural Engine operations under the all setting on macOS.

Source: README.md.

### 2026-10-19 Library chip drag reordering and drop target stability (`2026-10-19-library-reorder`)

Drag-and-drop reordering of library chips was evaluated in an iOS 27.0 Simulator (OI 5.7 A17 Pro, iPhone 15 Pro) using a DemoDriver automated robot to diagnose crashes and failed moves. Probing isolated crashes to glassEffectHelper inside SwiftUI container hierarchies, while dropped reordering was blocked by monolithic drop targets. Splitting the drop target into separate regions above and below the strip in reorderfix2 allowed Product Notes to move before General and persist after relaunch. In the final build across nine drag runs, seven moved and held order after relaunch without crashing.

Source: README.md.

### 2026-10-19 Metal GPU versus Accelerate vDSP vector search latency (`2026-10-19-metal-vs-vdsp-search`)

Vector search execution time was compared between CPU vDSP_mmul and GPU Metal on an Apple M3 Pro Mac with 18 GB memory running macOS 27.0 with Xcode 27.0 using 384-dimension random vectors. In the Swift array copy benchmark across 15 runs, CPU vDSP outperformed GPU Metal at 1,000 passages (0.01 ms versus 0.28 ms), 10,000 passages (0.08 ms versus 0.65 ms), 50,000 passages (0.86 ms versus 1.85 ms), and 150,000 passages (2.50 ms versus 4.74 ms). In the zero-copy page-aligned benchmark at 150,016 passages, CPU vDSP took 3.80 ms versus 5.69 ms for GPU Metal. The run settled that CPU vDSP remained faster than Metal across all tested passage counts on this Mac.

Source: README.md.

### 2026-10-19 Automated robot validation of quick actions, conversation limits, and notifications (`2026-10-19-robot-rows`)

Three roadmap items were tested in an iOS 27.0 Simulator (OI 5.7 A17 Pro, iPhone 15 Pro) on Debug build c478948 using a DemoDriver robot harness. Quick action testing verified that the icon menu lists Ask, Add Document, and Scan Document, launching Chat and the file picker. Conversation limit testing verified that reaching five active threads displayed the limit warning and maintained five conversations when queries advanced from 3 to 12. Background import testing showed notification banner delivery for a short text file in run notif4, while a 125 KB Markdown import in notif3 outlasted the 30 s background grant.

Source: README.md.

### 2026-11-04 On-device query time budget and Deep Think stage latencies (`2026-11-04-speed-research`)

Time budgets and execution stage durations were analyzed from 3,594 unique verification events and 72,266 trace lines gathered on an iPhone 16 Pro Max (A18 Pro) running app 5.8 (150) in Debug on an 8,410-passage library. Two uncontended Deep Think runs took 270.7 s and 236.2 s, giving a mean total time of 254.2 s. Five evidence sessions consumed a mean of 113.0 s (44.4% of total time), the synthesis model call took 56.4 s (22.2%), and multi-query search across 5 sub-queries took 17.1 s (6.7%). The research identified unlogged gaps of 8.5 s, 8.3 s, and 6.7 s, settling targets for Deep Think optimization.

Source: measured_budget.md.

### 2026-11-05 File splitting plan and verification protocol for large Swift files (`2026-11-05-file-split`)

An overnight refactoring plan and validation protocol were established to split large Swift files into focused extensions without adding or dropping code. The target files included ChatScreen.swift at 4,922 lines, DocumentProcessor.swift at 10,669 lines, and SettingsView.swift at 3,684 lines. The procedure mandated verifying 0 lines added and 0 lost via prove_move.py, checking overload sets, and confirming clean compilation across iOS and macOS test loops. It settled safety rules against silent rebinding and overload shadowing during large file extractions.

Source: OVERNIGHT.md.

### 2026-11-05 Golden retrieval benchmark search latencies across baseline and fix runs (`2026-11-05-golden-retrieval`)

No result recorded in the folder. It holds queries.json alongside result runs including results-base1.json and results-fix1.json. Across 71 documents, 7197 passages, and 760 searches, results-base1.json records firstPassSeconds of 716.8477289676666 and secondPassSeconds of 710.0369800329208. In comparison, results-fix1.json records firstPassSeconds of 682.9647109508514 and secondPassSeconds of 691.4023239612579.

Source: results-base1.json, results-fix1.json.

### 2026-11-06 Surgical decomposition strategy for monolithic query and parsing functions (`2026-11-06-decomposition`)

A surgical extraction plan was specified to decompose three large functions while preserving exact runtime behavior and byte-for-byte golden test outputs. Target functions were RAGService.queryInternal across 5,826 lines (lines 126-5948), RAGService.addDocument across 1,438 lines (lines 862-2299), and structured parsing functions spanning 1,232 and 420 lines. The plan required dual-pass golden recorders for the Standard pipeline, structured parsing, and ingestion enrichment prior to any source edits. The specifications settled a zero-logic-change extraction rule verified by deterministic hashing.

Source: PLAN.md.

### 2026-11-07 Optimization plan for Deep Think query latency without depth loss (`2026-11-07-deepthink-speed`)

An engineering plan targeted Deep Think query latency reductions for version 5.8 on iPhone 16 Pro Max, referencing baseline runs averaging 254 s (measured at 270.7 s and 236.2 s). Three unlogged guided-generation planner gaps of 8.5 s, 8.3 s, and 6.7 s were identified as optimization targets. Proposed changes included a 120 s planner cache estimated to save ~15 s, concurrent execution of 5 sub-queries in executeMultiQuerySearch estimated to save 7-9 s, and skipping unnecessary generic continuation checks to save 3-6 s. The plan established latency optimization goals while maintaining response depth and accuracy.

Source: PLAN.md.

### 2026-11-07 Documentation code citations and factual claim accuracy audit (`2026-11-07-docs-audit`)

A documentation audit evaluated code citations, symbol names, and behavioral claims across repository documentation against the post-decomposition working tree. The audit brief mandated checking line numbers, verifying symbol existence, confirming version statements against Docs/SHIPPED_VERSION.json, and validating internal links. Three independent reviews evaluated proposed corrections: review_a evaluated 71 proposals, review_b evaluated 154 proposals, and review_c evaluated 215 proposals. The review established verified line corrections without modifying codebase implementation.

Source: BRIEF.md, REVIEW_BRIEF.md, review_a.json, review_b.json, review_c.json.

### 2026-11-07 Unified metrics bar displayed value accuracy against pipeline reality (`2026-11-07-metrics-bar`)

Displayed metrics bar telemetry was audited against underlying code and verification journal events during a Deep Think run on an iPhone running build beb94eca. The audit found that the bar reported 1 invoked agentic tool while the journal logged 0 tool calls, and displayed five uncoordinated confidences including a 91% ring confidence, 92% synthesis row, 97% gates confidence, and 68-84% claims. The token budget displayed 3,016 output tokens without subtracting usage, and reported 20 retrieved chunks from a library holding 8,202 passages. It settled which metrics were genuine and identified dead subviews across UnifiedMetricsBar.swift across 434 lines.

Source: MAP.md.

### 2026-11-07 On-device answer responsiveness judge classification accuracy and latency (`2026-11-07-responsiveness`)

AnswerResponsivenessJudge was tested on a Mac running macOS 27 with Apple on-device models using greedy sampling over 160 test cases. Across four prompt iterations, the shipped v4 prompt achieved 56 full, 32 partial, and 7 none judgments on 95 gold questions, with a median latency of 1.65 s. On 25 invalid page range answers, v4 classified 22 as none, 2 as partial, and 1 as full. On 15 section heading answers, v4 classified 13 as none and 2 as partial. The test settled the production prompt used by Standard mode to trigger rewrites when answers fail responsiveness criteria.

Source: README.md.

### 2026-11-07 App Store Connect API automation scripts for Xcode Cloud (`2026-11-07-xcode-cloud`)

No result recorded in the folder. It holds Python automation scripts and identifiers including asc.py, start.py, run_id, and tests_workflow_id. The scripts interface with App Store Connect to dispatch build runs for Xcode Cloud workflow 77b13ba4-2ea7-4742-94ab-424586ef6ab5 on repository bec570a6-ac71-4f19-a898-060f290b33bb. Build run cf566a75-4937-48fd-a00e-0fc3a56547e2 was triggered, but no execution results or benchmark measurements are stored in the directory.

Source: start.py, run_id, tests_workflow_id.

### 2026-11-08 PDF document extraction text fidelity and number recall (`2026-11-08-extraction-fidelity`)

Extraction fidelity was measured for 8 PDFs comprising 141 pages scored against PDF text layers from pdftotext -layout. Between the baseline before run and after8, mean body number recall improved from 0.898 to 0.941, while mean body word recall rose from 0.967 to 0.972. Invented numbers dropped from 53.2 to 24.9 per 1,000, and invented words dropped from 29.2 to 22.4 per 1,000, with total extraction time increasing from 594 s to 632 s. On 515 image-derived ground-truth checks, passing checks increased from 344 (0.668) in before to 389 (0.755) in after8. The final tree of that work (after18) passed 433 of 515, with number recall 0.944, body number recall 0.966, body word recall 0.975, invented numbers 22.7 and words 20.4 per 1,000, and 641 s for all 8; olmOCR-Bench 160 pages, mean of four categories 0.539 (run-after8) to 0.611 (run-v6).

Source: README.md.

### 2026-11-08 On-device document ingestion techniques and research literature survey (`2026-11-08-ingestion-research`)

No result recorded in the folder. It holds ingestion_best_practices.md, containing a read-only literature and industry survey on on-device RAG document ingestion. The survey covers PDF lane choice, text-layer word positioning, complex page processing, chunking strategies, table extraction methods, and metadata generation. It compares current OpenIntelligence architecture against published methods and standards, outlining recommendations without changing repository code or executing runtime benchmark runs.

Source: ingestion_best_practices.md.

### 2026-11-09 Embedding and reranker model retrieval accuracy and latency bake-off (`2026-11-09-reranker-swap`)

Embedder and reranker models were evaluated on an Apple M3 Pro Mac running macOS 27 across QASPER 80 (246 questions over 80 papers with 3,912 passages) and BEIR datasets. On QASPER hybrid retrieval with app prefixes, MiniLM without a reranker achieved 37.0% top 5 accuracy, MiniLM with TinyBERT achieved 41.9%, and MiniLM with the Granite reranker achieved 48.8% in PyTorch and 48.4% in Core ML 4-bit palettized format. Core ML 4-bit Granite reranker inference took 14.4 ms for 256 tokens on the Neural Engine. The benchmark settled replacing TinyBERT with the 4-bit palettized Granite reranker in production. Embedders were measured too and not swapped: Granite small english r2 reached 39.0% top 5 against MiniLM's 37.0% (20/15, p=0.50; MRR@10 +0.039, p=0.006), BEIR nDCG@10 SciFact 0.754 against 0.655 and NFCorpus 0.373 against 0.311, and with the Granite reranker and context sentences 50.8% against 48.8% (13/8, p=0.38).

Source: README.md.

### 2026-11-10 Passage highlighting accuracy on PDF pages before and after PassageFinder (`2026-11-10-passage-highlight`)

Passage highlighting on PDF pages was evaluated across 10,029 passages in 44 PDFs before and after PassageFinder using harness_main.swift on macOS. Passages highlighted increased from 8,341 before to 9,423 in the final version, and passages covering at least 60% of target text increased from 5,852 (58.4%) to 8,920 (88.9%). The count of passages highlighted at over three times their length dropped from 773 in the first version to 2 in the final version. The run settled passage locator accuracy on Mac PDFKit, leaving scanned pages and on-device rendering unmeasured.

Source: README.md.

### 2026-11-10 Ablation audit of post-reranker retrieval heuristic rules (`2026-11-10-rule-audit`)

Post-reranker heuristic retrieval rules were ablated on an iOS 27 Simulator on commit 2313b62b plus 5.8 reranker work across QASPER (246 questions over 80 papers). The baseline configuration achieved a coverage score of 0.617, reached 54.5%, and placed gold evidence first in Deep Think 32.5% of the time and in the top five 50.0% of the time. Switching off corrective retrieval lowered coverage to 0.595 (p = 0.01), while disabling the focused window reduced coverage to 0.608 (p = 0.08). The audit settled which downstream heuristics provide measurable retrieval gains, retaining corrective retrieval and the focused window.

Source: README.md.

### 2026-11-10 Physical SoC chip package positions for motherboard HUD telemetry (`2026-11-10-xray-chip-positions`)

Hardware chip package coordinates were measured as fractions of device outlines from teardown photos fitted by screw holes using work/fit.py for MotherboardHUDView.socPlacement. Four measurement passes (A, B, C, D) adjudicated component placement across iPhone and iPad models, with iPhone 17 fitted at 0.330-0.522 horizontal and 0.177-0.291 vertical. Teardown video leads for four unmeasured devices were cataloged in gemini_video_leads_UNVERIFIED.json.txt but left out of production code per repository verification rules. The measurement settled verified physical placement for supported devices, leaving unmeasured models without an outline.

Source: README.md.

### 2026-11-14 Answer test on the final 5.8 build, by rule (`2026-11-14-1112-answer-modes`)

Build df67ec96 (an answer to "which document" names the cited file; the test passes a lost-in-the-middle case's document
to the ask action). `bash scripts/bench_answer_modes.sh standard deepThink maximum`, iOS 27 Simulator, Apple's model,
scored with `scripts/score_answer_eval.py`. `[evidence_level: measured, confidence: high for the counts; one run per mode, and retrieval is not deterministic]`

| Mode | 5.7 (v5.7.0) | 5.8 at 581a37b6 | 5.8 at df67ec96 | Minutes |
|---|---|---|---|---|
| Standard | 10 | 10 | 17 | 26 |
| Deep Think | 12 | 13 | 17 | 25 |
| Maximum | 10 | 14 | 17 | 23 |

Misses. Standard: `exact_capex`, `exact_temperature_limit`, `lost_in_middle_middle`. Deep Think: `retrieval_trial_beta`,
`missing_unreleased_battery`, `missing_confidential_price` (the last with a Needs Verification banner). Maximum:
`retrieval_scifact_delta`, `retrieval_nfcorpus_epsilon`, `missing_confidential_price` (with the banner). Not read
answer by answer. The model judge agreed with the rule on 10, 8 and 9 of 20, as before. 0 refused in any mode.
The gain from 581a37b6 is mostly the five which-document and three lost-in-the-middle cases, which the two changes
in df67ec96 address directly; part of it is therefore the test now scoping a question the way the app does.
Like for like (the 17 cases outside lost-in-the-middle, whose test scoping changed): 5.7 scored 9, 11, 9 and 5.8 at df67ec96
scored 15, 14, 14. This is the comparison the release text states.

### 2026-11-17 Deep Think's final step at an 8,192 window: the 3,200 ceiling against the window (`2026-11-17-synthesis-ceiling`)

`EvidenceReachBenchmarkTests` on the patched Simulator copy (`scripts/sim_model_copy.py`, iPhone 17 Pro, iOS 27.0,
Apple's model through the Mac's AFM 3 Core Advanced), window held at 8,192 (`OI_EVIDENCE_WINDOW`), tree a5511021 plus
the uncommitted switch, slice 0 of 3 of the table questions (53, the set of `2026-11-12-deepthink-source-passages`),
each asked twice in one process: "ceiling" as shipped, "window" with `RetrievalAblation.synthesisReadingCeiling` off.
Decision rule set before the run: the window ships only if it is no worse on right answers.

| Arm | Right | Errors | Median | Final prompt |
|---|---|---|---|---|
| ceiling (3,200) | 47/53 | 0 | 104 s | 3,384 to 3,577 tokens |
| window (5,986) | 49/53 | 0 | 96 s | above 4,000 on all 53, up to 6,308 |

Per question: 2 better, 0 worse (p=0.50). Shipped 2026-11-18 as the default (`RetrievalAblation.synthesisFullWindow`,
off restores the ceiling). Scored with `evidence_reach.py answers` against `queries-rebuilt/queries.jsonl`: macOS's
/tmp cleanup removed `/private/tmp/oi-dt-tables/queries.jsonl` and the fixtures at midnight during the run, after the
test had loaded them; the list was rebuilt with `prepare_tables`' logic from
`2026-11-08-extraction-fidelity/checks` plus `2026-11-10-rule-audit/tables/checks/KBIE_13_2100863.jsonl`, and every
one of the 53 result qids matched it. `smoke/` is the 2-question check; `failed-2259/` is a run killed at 22:59 by a
Mac reinstall's `pkill -x OpenIntelligence`, which also ended the Simulator's test host.

**Not settled.** One run per arm (retrieval is nondeterministic); no iPhone run; 4,096 windows are unchanged by
construction (1,890 free) and were not re-run.

### 2026-11-19 Maximum with and without the 2026-11-18 changes (`2026-11-18-maximum-ab`, `2026-11-19-0638-answer-modes-bind-base1-r`, `2026-11-19-0726-answer-modes-bind-fix1-r`)

The entity-binding run had Maximum at 18/20 against 19/20 before, losing exact_payload ("14.3 US gal") and
retrieval_covid_gamma. One build of `/private/tmp/oi-neg-wt`, Maximum, alternating "base" (`itemLeadInSentences`,
`entityBindingGate`, `noNamedOnly` off) and "fix". Planned four runs; stopped after one and a half to free the
machine for the 5.8 release, because the half-run had already answered both disputed questions.
`[evidence_level: measured, confidence: medium: one base run, 11 of 20 fix answers]`

| Run | Right by rule | exact_payload | retrieval_covid_gamma |
|---|---|---|---|
| base1-r (changes off) | 16/20 (lost exact_payload, lost_in_middle_middle, lost_in_middle_end, missing_unreleased_battery) | wrong | right |
| fix1-r (changes on), stopped at 11 of 20 | not scored | "1,240 lb. [S1]", right | names its source document, right |

Read: the two losses of 2026-11-18 21:43 are run-to-run variation in Maximum's final writing (the 1,240 lb table
ranked first in both), not the change; base missed exact_payload too. The change stays (5052c221).

### 2026-11-18 A "no" counts only when it denies what the claim names (`2026-11-18-no-named-only`, `2026-11-19-0620-answer-modes-bind-base-ans`, `2026-11-19-0629-answer-modes-bind-fix-ans`)

The owner's right "The similarity floor in Standard mode is 0.28 [S2]" showed "0 of 1 Verified": Gate B's negation
test read the guide's "no query expansion" as the passage saying the opposite. One build of `/private/tmp/oi-neg-wt`
(39425ef8, the entity-binding change, `ClaimCheck.resolvingNo`), each part run with `RetrievalAblation.noNamedOnly`
off ("base") and on ("fix"). iOS 27.0 Simulator, iPhone 17 Pro, Apple's model, patched copy.
`[evidence_level: measured, confidence: medium: one library's questions, one answer-test run per arm]`

| Set | Base (every "no" counts) | Fix |
|---|---|---|
| Entity set, right claims marked "says the opposite" | 4 | 0 |
| Entity set, right claims Supported | 21 | 22 |
| Entity set, answers right (2 runs) | 24/24 | 23/24 (one Maximum answer gave Deep Think's 8 variants; its Fact Check verdict was none) |
| Entity set, wrong-entity claims Supported | 0 | 1, a grading miss ("...higher than in Standard mode, which has a 0.50 threshold." is true) |
| Answer test, Standard, right by rule | 18/20 | 18/20 (won lost_in_middle_middle, lost retrieval_nfcorpus_epsilon) |
| Fact Check unit tests (7 classes, 83) | 2 failures, the new cases, as expected with the rule off | 0 failures |

The first base and fix answer tests (23:34, 23:45) and four Maximum runs stopped on the 15 GB disk guard after another
session's clean build; the reruns above started 06:20 after the queue waited on that session's build lock until 06:19.

### 2026-11-18 Entity binding: a list item's number stays with its subject (`2026-11-18-entity-binding`, `2026-11-18-1307-answer-modes-bind-before`, `2026-11-18-1555-answer-modes-bind-after`, `2026-11-18-1749-answer-modes-bind-after`)

The owner's "The similarity floor in Standard mode is 0.20 [S2]" (Maximum's value, Supported 90%, Verified). Worktree
`/private/tmp/oi-bind-wt` at f5759e4d; "before" is HEAD plus the evaluation test only, "after" the patch (sentence
extraction keeps a list item's lead, `EntityBinding` in Fact Check, the citation page's note). iOS 27.0 Simulator,
iPhone 17 Pro, Apple's model through the Mac, patched copy (`scripts/sim_model_copy.py`). `run.sh <label>` builds and
runs `EntityBindingEvaluationTests`: the three guides imported into a library of their own, 12 questions (similarity
floor, candidates per step, query variants and verification threshold, each for Standard, Deep Think and Maximum)
asked in Standard through `RAGService.query`, twice in one process, and from `before-probe` on, Fact Check on each
answer's own passages for a claim stating each mode's value (`probes`). Scored with `tools/score_entity.py`.
`[evidence_level: measured, confidence: high for the counts; retrieval and generation are not deterministic]`

| Set | Before | After |
|---|---|---|
| Entity answers right | 45/48 (four runs: `before` ×2, `before-probe` ×2) | 23/24 (`after` ×2) |
| Answers with another mode's value | 2 (Maximum given Deep Think's "8 variants", both Verified at 97%) | 0 |
| Probe, wrong value for the mode (44) | 36 Supported, 8 Partial, 0 Unsupported | 0 Supported, 0 Partial, 44 Unsupported |
| Probe, right value (22) | 18 Supported, 4 Partial | 18 Supported, 4 Partial |
| Answer test, Standard, right by rule | 18/20 | 18/20 (won `retrieval_nfcorpus_epsilon`, lost `exact_temperature_limit`: both runs answered "not specified"; before's passed on its Needs Verification note naming 45 C) |
| Answer test, Deep Think | 17/20 | 16/20 by rule, 17 read by hand (`2143-answer-modes-bind-after-2`): missing_unreleased_battery declines in its first sentence and fails the rule on an unrelated "$1,577 million" it lists after |
| Answer test, Maximum | 19/20 (74 min) | 18/20 (`2143-answer-modes-bind-after-2`, 36 min): lost exact_payload ("14.3 US gal", the 1,240 lb table ranked first) and retrieval_covid_gamma, won missing_confidential_price; one run each, paired runs in `2026-11-18-maximum-ab` |
| Table questions, Standard answers (53, `tables.sh`, paired on the after build) | 47/53 without the lead (`itemLeadInSentences` off) | 49/53 with it (2 better, 0 worse, p=0.50; with a citation 52 and 50) |

The owner's 13:24 phone trace (`phone-trace-1324.txt`) located the first layer: Standard packed chosen sentences
("Sentence extraction: 30 sentences from 4 sources", compact, focused_window), which cut "- **Standard.**" from its
"30 candidate passages, a similarity floor of 0.28"; the extractor declined (0.52 below 0.65). The Simulator logs show
the same path (`Sentence extraction: 36 sentences from 7 sources`, compact). Offline, `tools/harness` (macOS command-line
build of `EntityBinding`) replayed the check on the passages of all 72 recorded answers (`before`, `before-probe`,
`after`): 0 of 66 right-value claims flagged, 132 of 132 wrong-value claims flagged, and of the model's own 113 listed
claims with a number, its 3 wrong ones flagged and none of the other 110; a probe of 7,850
statements from `Docs/*.md` and `Docs/ai/*.md`, each read against its own passage, flagged none. A refuting review
found four false-positive shapes in the first version (a "Note:" remark, a wrapped line under the list's heading, a
general claim read against the question, a comparison naming other modes); each is a unit test now and passes.
`after-v1/` is the first after build (claim-only subject; superseded, kept); `after-aborted-1/` stopped before building; `2026-11-18-1207-`, `1547-` and `1608-answer-modes-bind-*` are runs the answer script refused for disk space, with nothing in them.
Unit tests on the after build: 147 in 11 classes (`after/unit.log`) and 42 in 6 more (`after/unit2.log`), 0 failures.

The table slice (`tables.sh`, 16:42 to 17:49) re-staged the PDFs of the 2026-11-17 set, whose `/private/tmp` copies macOS
had removed, from the owner's library copies (the PAHs paper from the app's imported copy, by title; not checked byte
for byte against the earlier fixture); "imported 5 of 7 when the call returned", the same for both arms. The internal
disk fell to 2 GB free at 15:47 (other sessions) and the after answer test waited for it; a watchdog in `answers.sh`
and `tables.sh` stops a run under 10 GB.

**Not settled.** The Deep Think and Maximum answer tests after (the decision rule needs them). One run per mode of the answer test. No iPhone run; the phone's 3B model was not reproduced word for
word by the Simulator. The lead's effect on Deep Think and Maximum alone (it changes their sentence windows too) is
inside the answer-test rows, not measured apart.

### 2026-11-20 Paired answer run "noise": the same build twice (`2026-11-20-1249-answer-modes-noise-before`, `2026-11-20-1306-answer-modes-noise-after`)

`scripts/paired_run.py pair --before HEAD --after HEAD --name noise`: before is `HEAD` (29a406bd); after is `HEAD`
(29a406bd), whose app code is that of tag `v5.8.0` (build 509). Mode: standard; 2 runs of one build, so every flip is
run-to-run noise. Each run is a scratch copy with the Simulator switches of `scripts/sim_model_copy.py` turned off, its
own build folder and its own simulator (iOS 27.0, iPhone 17 Pro), one after the other. Right and wrong by rule
(`scripts/score_answer_eval.py`), the 20 questions of the tiny research suite. First run 12 minutes, second 9.
`[evidence_level: measured, confidence: low: 2 runs of one build, one question set]`

| Mode | First run | Second run | Wrong to right | Right to wrong | Net | Reading |
|---|---|---|---|---|---|---|
| standard (app model) | 80% (16 of 20) | 90% (18 of 20) | 2: lost_in_middle_middle, lost_in_middle_end | 0: none | +10 points (+2 questions of 20) | within run-to-run noise |

Read: Standard on one build moved by 2 of 20 questions between two runs, both "lost in the middle" questions (a
token placed mid-document or at its end). So on this set a change has to move more than 2 questions, more than 10
points, before one run of each build can show it, and the two lost-in-the-middle questions cannot be used as evidence
either way from single runs. It is one pair of runs: the true spread may be wider, and it says nothing about Deep
Think or Maximum. This is also the first run made through `scripts/paired_run.py` end to end; its scratch folders
(`/private/tmp/oi-pair`) and both simulators were removed afterwards.

### 2026-11-21 Stability battery, standard: the same 20 questions under several sampling settings (`2026-11-20-1249-answer-modes-noise-before`, `2026-11-20-1306-answer-modes-noise-after`, `2026-11-21-0211-answer-modes-stab-standard-shipped-3`, `2026-11-21-0221-answer-modes-stab-standard-greedy-1`, `2026-11-21-0229-answer-modes-stab-standard-greedy-2`, `2026-11-21-0251-answer-modes-stab-standard-seeded-1`, `2026-11-21-0259-answer-modes-stab-standard-seeded-2`, `2026-11-21-0317-answer-modes-stab-standard-cool-1`, `2026-11-21-0325-answer-modes-stab-standard-cool-2`, `2026-11-21-0341-answer-modes-stab-standard-adaptive-1`, `2026-11-21-0353-answer-modes-stab-standard-adaptive-2`, `2026-11-21-0401-answer-modes-stab-standard-adaptive-3`)

`scripts/stability_battery.py`: one build, the tiny research suite's 20 questions, the app's own model service in the iOS 27.0 Simulator (a scratch copy patched by `scripts/sim_model_copy.py`). The settings are the benchmark-only sampling switches `AppleFoundationLLMService` reads; the app is unchanged. Right and wrong by rule (`scripts/score_answer_eval.py`); "word for word" compares the first 300 characters of each answer.
`[evidence_level: measured, confidence: low to medium: few runs per setting, one question set]`

| Setting | What | Runs | Each run | Mean | Questions that changed between runs | Answers word for word the same |
|---|---|---|---|---|---|---|
| shipped | as the app ships | 3 | 80% (16 of 20), 90% (18 of 20), 90% (18 of 20) | 85% (17 of 20) mean | 2: lost_in_middle_end, lost_in_middle_middle | 6% (1 of 18) |
| greedy | always the likeliest word | 2 | 75% (15 of 20), 85% (17 of 20) | 80% (16 of 20) mean | 2: exact_service_interval, retrieval_nfcorpus_epsilon | 6% (1 of 18) |
| seeded | as shipped, the random draws held fixed (seed 42) | 2 | 95% (19 of 20), 90% (18 of 20) | 90% (18 of 20) mean | 1: exact_temperature_limit | 17% (3 of 18) |
| cool | temperature 0.1 | 2 | 75% (15 of 20), 85% (17 of 20) | 80% (16 of 20) mean | 4: lost_in_middle_end, lost_in_middle_middle, missing_unreleased_battery, retrieval_nfcorpus_epsilon | 28% (5 of 18) |
| adaptive | the app's adaptive-profiles switch on | 3 | 90% (18 of 20), 90% (18 of 20), 85% (17 of 20) | 90% (18 of 20) mean | 3: exact_temperature_limit, lost_in_middle_end, missing_unreleased_battery | 0% (0 of 18) |
| hashed | greedy, Swift's hashing held fixed | 0 | not run | | | |

Read: As shipped, 2 of 20 questions changed between right and wrong across 3 runs, and 1 of 18 answers were word for word the same. That is the variation a user can meet today. With no randomness in the writing, 17 of 18 answers still differed between runs. Something before the writing varies (the passages or their order): run `--arms hashed`, then the golden harnesses, before changing any temperature. With the random draws held fixed, 15 of 18 answers still differed between runs. With no randomness in the writing the mean was 16.0 right against 17.3 (-1.3), which is not distinguishable from as shipped (runs of one setting differ by up to 2). 2 questions changed between its runs. With temperature 0.1 the mean was 16.0 right against 17.3 (-1.3), which is not distinguishable from as shipped (runs of one setting differ by up to 2). 4 questions changed between its runs. With the adaptive-profiles switch on the mean was 17.7 right against 17.3 (+0.3), which is not distinguishable from as shipped (runs of one setting differ by up to 2). 3 questions changed between its runs.

### 2026-11-21 Stability battery, deepThink: the same 20 questions under several sampling settings (`2026-11-21-0409-answer-modes-stab-deepThink-shipped-1`, `2026-11-21-0436-answer-modes-stab-deepThink-shipped-2`, `2026-11-21-0518-answer-modes-stab-deepThink-shipped-3`, `2026-11-21-0548-answer-modes-stab-deepThink-greedy-1`, `2026-11-21-0621-answer-modes-stab-deepThink-greedy-2`, `2026-11-21-0944-answer-modes-stab-deepThink-adaptive-1`, `2026-11-21-1012-answer-modes-stab-deepThink-adaptive-2`, `2026-11-21-1041-answer-modes-stab-deepThink-adaptive-3`)

`scripts/stability_battery.py`: one build, the tiny research suite's 20 questions, the app's own model service in the iOS 27.0 Simulator (a scratch copy patched by `scripts/sim_model_copy.py`). The settings are the benchmark-only sampling switches `AppleFoundationLLMService` reads; the app is unchanged. Right and wrong by rule (`scripts/score_answer_eval.py`); "word for word" compares the first 300 characters of each answer.
`[evidence_level: measured, confidence: low to medium: few runs per setting, one question set]`

| Setting | What | Runs | Each run | Mean | Questions that changed between runs | Answers word for word the same |
|---|---|---|---|---|---|---|
| shipped | as the app ships | 3 | 80% (16 of 20), 65% (13 of 20), 85% (17 of 20) | 75% (15 of 20) mean | 5: exact_temperature_limit, lost_in_middle_middle, missing_confidential_price, retrieval_nfcorpus_epsilon, retrieval_trial_beta | 6% (1 of 18) |
| greedy | always the likeliest word | 2 | 95% (19 of 20), 95% (19 of 20) | 95% (19 of 20) mean | 0 | 17% (3 of 18) |
| seeded | as shipped, the random draws held fixed (seed 42) | 0 | not run | | | |
| cool | temperature 0.1 | 0 | not run | | | |
| adaptive | the app's adaptive-profiles switch on | 3 | 80% (16 of 20), 95% (19 of 20), 80% (16 of 20) | 85% (17 of 20) mean | 5: lost_in_middle_middle, missing_confidential_price, missing_unreleased_battery, retrieval_covid_gamma, retrieval_trial_beta | 6% (1 of 18) |
| hashed | greedy, Swift's hashing held fixed | 0 | not run | | | |

Read: As shipped, 5 of 20 questions changed between right and wrong across 3 runs, and 1 of 18 answers were word for word the same. That is the variation a user can meet today. With no randomness in the writing, 15 of 18 answers still differed between runs. Something before the writing varies (the passages or their order): run `--arms hashed`, then the golden harnesses, before changing any temperature. With no randomness in the writing the mean was 19.0 right against 15.3 (+3.7), which is not distinguishable from as shipped (runs of one setting differ by up to 4). 0 questions changed between its runs. With the adaptive-profiles switch on the mean was 17.0 right against 15.3 (+1.7), which is not distinguishable from as shipped (runs of one setting differ by up to 4). 5 questions changed between its runs.

### 2026-11-21 Stability battery, maximum: the same 20 questions under several sampling settings (`2026-11-21-0658-answer-modes-stab-maximum-shipped-1`, `2026-11-21-0728-answer-modes-stab-maximum-shipped-2`, `2026-11-21-0807-answer-modes-stab-maximum-shipped-3`, `2026-11-21-0839-answer-modes-stab-maximum-greedy-1`, `2026-11-21-0905-answer-modes-stab-maximum-greedy-2`, `2026-11-21-1106-answer-modes-stab-maximum-adaptive-1`, `2026-11-21-1128-answer-modes-stab-maximum-adaptive-2`, `2026-11-21-1156-answer-modes-stab-maximum-adaptive-3`)

`scripts/stability_battery.py`: one build, the tiny research suite's 20 questions, the app's own model service in the iOS 27.0 Simulator (a scratch copy patched by `scripts/sim_model_copy.py`). The settings are the benchmark-only sampling switches `AppleFoundationLLMService` reads; the app is unchanged. Right and wrong by rule (`scripts/score_answer_eval.py`); "word for word" compares the first 300 characters of each answer.
`[evidence_level: measured, confidence: low to medium: few runs per setting, one question set]`

| Setting | What | Runs | Each run | Mean | Questions that changed between runs | Answers word for word the same |
|---|---|---|---|---|---|---|
| shipped | as the app ships | 3 | 95% (19 of 20), 85% (17 of 20), 90% (18 of 20) | 90% (18 of 20) mean | 2: exact_payload, missing_confidential_price | 11% (2 of 18) |
| greedy | always the likeliest word | 2 | 90% (18 of 20), 95% (19 of 20) | 90% (18 of 20) mean | 3: missing_unreleased_battery, retrieval_covid_gamma, retrieval_policy_alpha | 17% (3 of 18) |
| seeded | as shipped, the random draws held fixed (seed 42) | 0 | not run | | | |
| cool | temperature 0.1 | 0 | not run | | | |
| adaptive | the app's adaptive-profiles switch on | 3 | 90% (18 of 20), 95% (19 of 20), 95% (19 of 20) | 95% (19 of 20) mean | 3: exact_payload, lost_in_middle_middle, retrieval_trial_beta | 11% (2 of 18) |
| hashed | greedy, Swift's hashing held fixed | 0 | not run | | | |

Read: As shipped, 2 of 20 questions changed between right and wrong across 3 runs, and 2 of 18 answers were word for word the same. That is the variation a user can meet today. With no randomness in the writing, 15 of 18 answers still differed between runs. Something before the writing varies (the passages or their order): run `--arms hashed`, then the golden harnesses, before changing any temperature. With no randomness in the writing the mean was 18.5 right against 18.0 (+0.5), which is not distinguishable from as shipped (runs of one setting differ by up to 2). 3 questions changed between its runs. With the adaptive-profiles switch on the mean was 18.7 right against 18.0 (+0.7), which is not distinguishable from as shipped (runs of one setting differ by up to 2). 3 questions changed between its runs.

**The three batteries together (26 new runs, 2026-11-21 02:11 to 12:24, queue `~/Library/Developer/OpenIntelligence-evidence/stability-queue/queue.sh`, commit ce7adeed, 0 failed runs).**

| Mode, as shipped | Right of 20, each run | Mean | Minutes a run |
|---|---|---|---|
| Standard | 16, 18, 18 | 17.3 | 7 to 10 |
| Deep Think | 16, 13, 17 | 15.3 | 26 to 40 |
| Maximum | 19, 17, 18 | 18.0 | 28 to 38 |

**What it settled.** (1) Removing the writing's randomness does not make answers repeat in any mode: with greedy, 1 of 18, 3 of 18 and 3 of 18 answers were word for word the same. (2) In Standard no sampling setting is distinguishable from as shipped. (3) The settings reached the model: `[FM] Benchmark sampling override: strategy=greedy` in the greedy logs, and with the adaptive switch on Deep Think's steps logged 241 at 0.1 and 30 at 0.35 "from the adaptive profile" and none from the default. (4) As shipped, Deep Think's steps log 0.5 from the default on 85 of 103 and 0.3 named by the step on 18; Maximum 0.7 on 33, 0.5 on 56 and none at 0.3.

**What it found and did not settle.** Each run imports the fixtures again and the import writes a model-made summary per document, whose lengths differed between runs (649, 610 and 673 words over 6 summaries in three Standard runs), so the runs did not ask the same library; and with the same assembled context (1 passage, 1,018 input tokens) two greedy runs still wrote different words. Deep Think with greedy scored 19 and 19 against 16, 13 and 17 as shipped: a gap of 3.7 against a largest spread of 4, so not a result by the rule set before the runs, and the first number that points at its 0.5. Not measured: the same library asked twice in one process; a phone; any other question set. `--arms hashed` was not run: with the library itself differing between runs it could not have isolated hashing order.
`[evidence_level: measured, confidence: medium for the tables (two or three runs a setting, one 20-question set, Simulator); the reading of the logs is from one question in two runs]`

### 2026-11-18 Five folders from the entity-binding day that had no entry (`2026-11-18-1207-answer-modes-bind-before`, `2026-11-18-1547-answer-modes-bind-after`, `2026-11-18-1608-answer-modes-bind-after`, `2026-11-18-2143-answer-modes-bind-after-2`, `2026-11-18-held-after-5.8`)

Written 2026-11-22 from the folders' own files, to close the ledger's gap. Nothing was re-run.

| Folder | What it holds | What it found |
|---|---|---|
| `2026-11-18-1207-answer-modes-bind-before` | One progress line | No run: stopped at the disk guard, 12 GB free against the 15 it needs |
| `2026-11-18-1547-answer-modes-bind-after` | One progress line | No run: stopped at the disk guard, 2 GB free |
| `2026-11-18-1608-answer-modes-bind-after` | One progress line | No run: stopped at the disk guard, 10 GB free |
| `2026-11-18-2143-answer-modes-bind-after-2` | A complete Deep Think and Maximum run of the answer test | Deep Think 80% (16 of 20) in 32 minutes, Maximum 90% (18 of 20) in 36. The entity-binding entry above already reads this run (its "after" column); it was named there without its date prefix |
| `2026-11-18-held-after-5.8` | Two patches and a test file, not a run | The changes held back from 5.8: Standard's plan without a model call (`standard-plan-without-model.diff`) and the case-insensitive Code and Standard spec patterns (`code-patterns.diff`, `SpecificationDetectorTests.swift`). Their roadmap rows are "Standard waits on a planning model call before every question" and "The Code and Standard spec patterns read any word before a number as a code" |

**What it settled.** Nothing new. The three stopped runs are the disk running short on 2026-11-18, the day another session's build filled it.
`[evidence_level: measured for the one complete run (its SUMMARY.md); the rest is a reading of each folder's files, confidence: high]`

### 2026-11-22 Ask twice: one imported library, each question asked several times (`2026-11-22-0231-answer-modes-twice-standard-shipped`, `2026-11-22-0251-answer-modes-twice-standard-greedy`, `2026-11-22-0320-answer-modes-twice-deepThink-shipped`, `2026-11-22-0536-answer-modes-twice-deepThink-greedy`, `2026-11-22-1222-answer-modes-twice-deepThink-greedy`)

`scripts/ask_twice.py`, commit ba1dcd23: the answer test imports its six fixtures once and asks each of the 20 questions
several times in the same process (`OI_EVAL_REPEAT`); the first answer is graded and each later one is printed whole
beside it. iOS 27.0 Simulator, 5.8's app code, the app's own model service. Right and wrong by rule
(`scripts/score_answer_eval.py`'s rule) on the full answers.
`[evidence_level: measured, confidence: medium: one run a setting, one 20-question set]`

| Mode | Sampling | Asks | Right of 20, each ask | Same words every ask | Questions that changed between right and wrong |
|---|---|---|---|---|---|
| Standard | As shipped | 3 | 16, 16, 16 | 50% (10 of 20) | 0 |
| Standard | Greedy | 3 | 16, 17, 18 | 65% (13 of 20) | 2 |
| Deep Think | As shipped | 5 | 15, 16, 15, 14, 16 | 5% (1 of 20) | 6 |
| Deep Think | Greedy | 5 | 18, 17, 16, 16, 16 | 25% (5 of 20) | 4 |

`2026-11-22-0536-answer-modes-twice-deepThink-greedy` is not a result: it was cut short at 12 of 20 questions when the
session that had started the queue restarted at about 06:45. The run was made again at 12:22 from a Terminal tab.
Maximum's two runs were still waiting on disk space when this was written.

**What it settled.** Standard is steady when nothing is imported in between (16 on every ask, no question changing
sides), where separate imports gave 16, 18, 18 and 2 questions changing: most of Standard's variation comes with the
import. Deep Think varies on one unchanged library (6 questions changing sides over 5 asks). Greedy raises Deep Think by
1.4 questions on average on one library and steadies it without making it repeat.

**What it did not settle.** Why greedy answers still change within one process; whether a later ask is affected by the
earlier asks of the same question (Deep Think's greedy scores fell 18 to 16 over five asks); Maximum.


### 2026-11-23 Ask twice, Maximum (`2026-11-23-0021-answer-modes-twice-maximum-shipped`, `2026-11-23-0654-answer-modes-twice-maximum-greedy`)

The two Maximum runs of the 2026-11-22 ask-twice queue, made from the same commit (ba1dcd23) after the disk had stopped
the queue; each question asked twice in one imported library. iOS 27.0 Simulator, 5.8's app code, the app's own model
service. The greedy run waited from 01:24 to 06:54 for disk space held by other sessions and then ran with the start
floor lowered to 12 GiB (`OI_TWICE_MIN_FREE_GIB`, `OI_BENCH_MIN_FREE_GB`); free space stayed above 11 GiB.
`[evidence_level: measured, confidence: medium: one run a setting, one 20-question set]`

| Sampling | Right of 20, each ask (rule of 2026-11-22) | Same rule corrected (item 8, below) | Same words both asks | Questions that changed sides |
|---|---|---|---|---|
| As shipped | 18, 17 | 19, 19 | 25% (5 of 20) | 3 by the old rule, 2 by the corrected one |
| Greedy | 18, 18 | 18, 18 | 55% (11 of 20) | 0 |

**What it settled.** Maximum scores highest of the three modes on one library, and with greedy it repeated itself: no
question changed sides and 11 of 20 answers kept their words. Greedy's misses were the same on both asks: the payload
answered with another file's unlabelled "Primary answer" ($1,577 million) and the end document's token answered with
the middle one's (LITM-MIDDLE-42), an earlier answer carried in by conversation memory.

**What it did not settle.** Whether Maximum as shipped is lower than greedy (19, 19 against 18, 18 corrected is within
one question); a phone.

### 2026-11-23 Re-score: the test corrected (item 8), no new runs

`scripts/score_answer_eval.py`'s rule corrected (Docs/ai/plans/consistent-answers.md, "Item 8 done"): a refusal that
goes on to list other documents' values, or uses wordings the old rule did not know, is right; an answer whose first
sentence says the documents do not hold the value, and that names the expected value only later, is wrong. Applied to
the 1,360 saved answers of the 44 stability, noise and ask-twice runs to date, every changed answer read.
`[evidence_level: measured, confidence: high for the counts; the rule's judgement was checked by reading the changed answers]`

| Mode | Answers | Old rule | Corrected rule |
|---|---|---|---|
| Standard | 520 | 82% (425) | 80% (414) |
| Deep Think | 480 | 80% (383) | 85% (410) |
| Maximum | 360 | 87% (312) | 89% (322) |

The scores in the entries above stay as they were measured by the rule of their date; this entry is the corrected
reading of the same answers. The fixtures' labels and the memory change take effect only in runs made from the commit
that carries them.
