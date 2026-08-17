# Benchmark run ledger

`results.jsonl` records **what happened**. It does not record **what the run was testing, against
which commit, or what it settled**. Sixty-two run directories existed before this file with none of
that, which makes them unreadable a week later and impossible to sequence work from.

One row per run. Add the row when you launch, fill the verdict when it lands. A run with no row is
indistinguishable from a run nobody learned anything from.

`run_config.json` does **not** capture the commit or the embedding provider. Until it does, both go
in this table by hand.

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

## Open, not yet run

| planned run | tests | why it matters |
| :-- | :-- | :-- |
| CoreML-provider run | Same 25 cases on `CoreMLSentenceEmbeddingProvider` instead of Core AI. | The two providers are **not** the same. Core AI runs `main.mlirb`, one input, and extracts the **CLS token**; CoreML runs the `.mlpackage`, three inputs including `attention_mask`, and does **mean pooling**. `all-MiniLM-L6-v2` is a mean-pooling model, so the Core AI path reads the wrong output of a model never trained to put meaning there. Every `vector r@1` number recorded above was produced by the Core AI path. **Until this runs, MiniLM's real quality is unknown and no embedder comparison is valid.** |
| Embedder comparison | bge-small-en-v1.5 (MIT, 384-dim, 512-trained) against a correctly-read MiniLM. | Blocked on the row above. Running it first would compare a candidate against a misconfigured incumbent. |

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
