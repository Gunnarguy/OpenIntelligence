# Benchmark run ledger

`results.jsonl` records **what happened**. It does not record **what the run was testing, against
which commit, or what it settled**. Sixty-two run directories existed before this file with none of
that, which makes them unreadable a week later and impossible to sequence work from.

One row per run. Add the row when you launch, fill the verdict when it lands. A run with no row is
indistinguishable from a run nobody learned anything from.

`run_config.json` does **not** capture the commit or the embedding provider. Until it does, both go
in this table by hand.

---

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
BenchmarkRuns/PROGRESSION.md`) tabulates every run on disk — 44 run/mode pairs across 39 runs —
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
