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
| `paired-pool10` | `025b912` | 8 cases x {deep-think, standard}, **pool_limit 10**, matching `tokfix` and `coreml-provider` exactly. | First comparable Deep Think numbers. Case 1 at **256.9s** against 1242s for the same case at pool 40, confirming cost is linear in pool size. |

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
