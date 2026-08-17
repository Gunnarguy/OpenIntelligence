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
| `tokfix` | `2753d15` | Truncation 512, padding block **removed**. | **In progress.** Token counts now vary (386 to 430) where they were a constant 128 across 3,910 prior ingestions. At n=7: rerank r@10 **0.840 to 1.000**, final r@10 **0.760 to 0.857**, but **vector r@1 flat**. Control (lexical) settled at 0.714 against a 0.600 baseline, so the runs are comparable. |

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
