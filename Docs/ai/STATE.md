# Current State

Updated: 2026-08-21
Branch/worktree: main, clean, **not pushed** — `origin/main` is at `8791baa`, seventeen commits behind.
Last verified commit: 7fccc1c

## Objective

**Get v5.0 shippable.** One question decides what 5.0 can contain and only the owner can answer it
(Blocker 1).

**Answer quality is now decomposed, and it is two problems of roughly equal size, not one.** As of
`passage-level-1` (2026-08-21), the answer-bearing span fails to reach the model in **10 of 24**
measurable cases, and when it does reach the model the answer is still wrong in **7 of 14**.
Retrieval and synthesis each account for about half the failures. Every prior plan assumed one of
them dominated.

## Status

All work is on `main`, none pushed. Every run is recorded in `BenchmarkRuns/LEDGER.md` (prose,
authoritative) and indexed in `BenchmarkRuns/PROGRESSION.md` (table, generated). Nothing is running;
no background tasks or monitors are armed.

**The measurement ruler changed on 2026-08-21 and this is the single most important fact for anyone
resuming.** Retrieval is now scored at passage level as well as document level. Document-level
`r@1`/`r@10` credit an entire document when any one of its chunks appears, so they read ~0.875 while
the actual answer span was missing 42% of the time. Do not tune against the document-level numbers.

## Completed this session

| commit | change |
|---|---|
| `6992f36` | `LIBRARY STATE` section in the shared pipeline trace |
| `5307fdc` | fixed the crash `6992f36` introduced (`@EnvironmentObject` for a service never in that view tree) |
| `669f4c5` | intent misrouting, source-only evidence budget, review/extraction evidence mismatch |
| `ff24b72` | citation source-list mismatch, dangling-citation detection, grounding threshold, confidence formula |

**Two of my own diagnoses were wrong and tests caught both before they shipped.** I attributed the
intent misrouting to a `words.count <= 5` fallback; the query never reached it and the real cause was
a `lookupStarters` prefix rule several branches earlier. I then set the grounding threshold to
`< 0.5`, which would still have accepted the exact `2/4` case it was written for. Write the test
before believing the diagnosis.

## The finding that redirects everything

From `BenchmarkRuns/postfix-citations`, 8 cases x both modes, `pool_limit 10`, QASPER. **Deep Think
now emits six stages where `paired-retry` emitted only `final`**, so the pipeline is finally
measurable end to end:

```
standard      lexical 0.646 → fusion 0.448 → rerank 0.750 → final 0.812   (MRR)
deep-think    lexical 0.615 → fusion 0.431 → (no rerank)  → final 0.688
```

**Fusion loses roughly 30% of the MRR its lexical arm earned, in both modes independently.** Standard
recovers via the cross-encoder. **[RETRACTED 2026-08-20]** The next sentence originally read
"Deep Think has no `rerank` stage" — false; the stage ran unrecorded. The gap is unattributed;
ledger has the retraction. Kept so the reasoning error stays visible.

Default fusion weights are `vector 0.7 / keyword 0.3`, weighting the weaker arm more than twice as
heavily as the stronger one. `RAGEngine.swift:982` already records lexical ranking the gold document
first in 60% of cases against dense's 8%.

**Accuracy moved but is not resolvable.** deep-think 2/8 → 3/8, standard 4/8 → 5/8, wall clock 94 →
58 min, timeouts 1 → 0. One case per mode is +12.5 points; the harness warns that below ~25 points
nothing resolves at this size. Directionally consistent, not proven.

## Do not re-investigate — settled

- **Query expansion degrades the lexical arm.** False. `searchWithFTS5` searches `originalQuery`
  (`HybridSearchService.swift:941,947`); expansions are a fallback only (`:967`).
- **The fusion weight can be decided in Standard mode.** False, and measured: `fusion-vw030` improved
  fusion on all four metrics at weight 0.3 (MRR +0.095, r@10 +0.143, nDCG@10 +0.109), `boosted` gave
  it back, and `rerank`/`final` were **identical to three decimals**. Standard's reranker normalises
  any fusion change out of existence. See the ledger entry.
- Retracted claims are listed at the end of `BenchmarkRuns/LEDGER.md`; read it before quoting any
  figure from anywhere.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then build with
  `-derivedDataPath` under `/private/tmp`. In place it hangs in NSFileCoordinator.
- **Nothing else builds, tests or runs while a benchmark measures.**
- **Never `pkill` on the app path** — it matches the harness, whose command line contains `--app`.
  Match `Contents/MacOS/OpenIntelligence`. A timeout kills its own child correctly; confirmed four
  times, most recently 2026-08-20.
- **Core AI does not work in the simulator**, so anything touching embeddings is device-only.
- **The benchmark ingests into the real library** and protects pre-existing documents by snapshot.
- Commit to `main`; do not branch. Do not push unless asked.

## Working Set

| File | Why |
|---|---|
| `BenchmarkRuns/LEDGER.md` | Every run, what it settled, and five places analysis was wrong. Read before trusting any figure. |
| `scripts/compare_benchmark_runs.py` | Intersects two runs by `case_id` and prints a control line. Use this rather than hand-rolling a comparison. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift:963` | `reciprocalRankFusion`, where the weights are applied. |
| `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift:208` | Where `vectorWeight: 0.7 / keywordWeight: 0.3` are defaulted. |
| `scripts/run_quality_matrix.py` | The harness. `--vector-weight` and `--resume` both work; resume skips completed cases. |
| `OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift` | Grounding threshold and confidence formula, both changed 2026-08-19. |

## Verification

Command → result, this session only:

- `xcodebuild test`, iOS 27.0 iPhone 17 Pro simulator → **256 tests, 2 skipped, 0 failures** (up from
  238). The skips are `EmbeddingProviderAgreementTests`, simulator-incapable, previously device-passed.
- `bash scripts/build_simulator_smoke.sh` → **BUILD SUCCEEDED**.
- macOS Debug build for the benchmark binary → **BUILD SUCCEEDED**, `/private/tmp/oi-mac-40`.
- `BenchmarkRuns/postfix-citations` → **16/16 complete, no timeout**, 58 min wall.
- `BenchmarkRuns/fusion-vw030` → 7 scored, 1 timeout, `results.json` written, no orphans left.
- `scripts/compare_benchmark_runs.py postfix-citations fusion-vw030` → control line reports
  `identical case for case, runs are comparable`.
- `BenchmarkRuns/fusion-vw030-deepthink` → **8/8 complete, no timeout**, ~35 min wall. Fusion MRR
  0.431 → 0.591, `final` MRR 0.688 → **0.530**, accuracy 3/8 → **2/8**.

**Not run:** the 25-case benchmark; anything on device since 2026-08-19.

## Blockers / Unknowns

1. **Which Xcode does Xcode Cloud use?** Only the owner can read it, in App Store Connect. PCC sits
   behind `#if compiler(>=6.4)`, eleven sites across six files; Xcode 27 measures as Swift 6.4. An
   Xcode 27 archive contains PCC (18 undefined symbol references to `PrivateCloudComputeLanguageModel`);
   any older Xcode omits it and every PCC request reaches `throw LLMError.modelUnavailable`.
   **Do not cite `.github/workflows/appstore.yml` — it has never executed and was deleted.**
2. **Settled:** the entitlement survives App Store distribution signing, verified by a local Xcode 27
   archive exported `method: app-store-connect`.
3. **A fresh import may still lose its vectors.** Three libraries found with documents and 0 chunks.
   `0350083` fixes the suspected cause and is unconfirmed. Needs three device imports; the protocol
   and the routing condition (`RAGService.swift:5569`, PDF-over-10MB) are on
   [the row](https://app.notion.com/3c149a74d54f81239443c15fe6ae3782).
4. **`boosted` degrades ranking in all four measured conditions**, and more the better its input.
   This is now the Exact Next Action rather than a blocker.
5. **Resolved 2026-08-20, the blocker's own instruction was followed and refuted the premise:**
   `performFullRetrievalPipeline` calls `engine.rerank` unconditionally for every agentic
   retrieval; the trace simply never recorded it, and now does. The gap moved to Exact Next
   Action item 3 as re-attribution work.
6. **A hang appears intermittently on QASPER paper `1604.02038`.** Third occurrence 2026-08-20:
   0.1% CPU for 21 minutes, then timeout. **It did not recur on the very next run of the same case**
   (`fusion-vw030-deepthink`, 234.5s, completed), so it is intermittent rather than deterministic for
   that paper. Cause unknown.
7. **Retrieval is ~21% reproducible, and the accuracy noise floor is now measured: ±1 case at
   n=24.** `rescue-position-fix` and `passage-level-1` differ only by the debug harness printing
   chunk text *after* generation — same behaviour, same config, control identical case for case —
   and scored 11/24 vs 10/24. That is an A/A comparison. **Accuracy at n=25 cannot adjudicate
   anything smaller than about a 4-case swing.** Stage metrics (`rerank`/`final` MRR, r@1) are far
   more stable and are what a change should be judged on. Paired comparison plus the sign test
   remains the only trustworthy readout.

   **Decomposed the same day into two independent causes.** Per case across those 24 pairs:
   `vector`/`lexical`/`fusion` are identical in **24/24**, every retrieval stage is identical in
   **22/24** — and yet `context_chars` matches in only **10/25** and the answer in **7/25**.
   *Cause 1:* prompt assembly diverges below the resolution of every metric here, because stage
   metrics score against gold *documents* and a different chunk order within the same documents
   scores identically. *Cause 2:* three cases matched on stage metrics, chunk count and prompt size
   and still answered differently, one returning 173 chars both times with different text — so
   Apple's seeded `SamplingMode.random(top:seed:)` is not reproducible across processes. The seed
   does reach it (`LLMService.swift:722`, `strategy=topk` logged in all 25 reports).
   **The cheapest high-value run available is the same 25 cases under
   `--rag-validation-sampling greedy`**, which removes cause 2 by construction and measures cause 1
   alone for the first time. Footgun found while checking: `benchmarkSeed` is read only inside
   `if let benchmarkSampling` (`LLMService.swift:720-738`), so `--rag-validation-seed` *without*
   `--rag-validation-sampling` silently discards the seed. No run on disk is affected; all passed
   `topk`.
8. **Two shipped engine changes have never executed on device.** `executeDirectSynthesis` still shows
   zero occurrences in every capture.
9. Known-but-unfixed, each pinned by a test asserting current behaviour so changing it is deliberate:
   a bare `what` prefix classifies as `.lookup`; `computePatterns` contains the substring `sum`, so
   `summary` and `summarize` classify as arithmetic and those two patterns are unreachable.
10. **Unfixed measurement defects** that distort any retrieval analysis, recorded on
    [the recall-gap row](https://app.notion.com/3bf49a74d54f81d593ddfe700f277f1e): `retrievalTime` is
    a hardcoded `0` on the agentic path; `timeToFirstToken` is `totalTime / stepCount`, confirmed by
    arithmetic against three captures; retrieval returns near-duplicate chunks; similarity scores
    collide on exact values (four chunks at exactly `0.7650`).

## Exact Next Action

**Emit rerank-stage chunk text from the debug harness, then re-score.** One line of harness output
splits the single biggest open number into two problems with unrelated fixes.

The gold span fails to reach the model in **10 of 24** cases. Those 10 are either *never retrieved*
(a ranking problem) or *retrieved, ranked, then cut when the prompt was assembled* (a budget and
packing problem). **They cannot be told apart from any saved run.** `STAGE SOURCES` records chunk
ids for every stage but only the final chunks carry text, so the gold span cannot be located in the
rerank set offline. `DebugRAGValidationHarness` already emits `RETRIEVED CHUNK TEXT` for the final
chunks; emitting the same block for the `rerank` stage closes it, and `passage_recall` then answers
"present at rerank, absent at final" directly.

**Why this outranks any further retrieval tuning — measured 2026-08-21, all 25 cases:**

| | value |
| :-- | :-- |
| chunks MMR selects | 30 |
| chunks that reach the prompt | **median 5** (range 4–24) |
| cases dropping 23–26 of the 30 | **20 of 25** |
| context chars used | 9,300–9,500 of ~9,540 — full |

**About 83% of what retrieval ranks never reaches the model.** The budget is the on-device 4K-token
window and it is saturated, not misconfigured: chunks average ~2,000 chars, so five fills it.
**Improving the order of anything past position ~5 cannot change an on-device answer** — which is
most of what fusion-weight and reranker tuning move, and explains why three fusion weights all
measured the same. The two things that can change an answer are getting the right chunk into the
top ~5, or packing the right *sentences* rather than whole chunks. The code already has both a
sentence-extraction path and a "needle rescue from dropped chunks" step
(`RAGService.swift:12130`); whether either fires on these cases is unmeasured.

**Do not re-open the metric itself.** Both of its assumptions were checked against code on
2026-08-21: `response.retrievedChunks` is `promptSources + rescuedChunks`
(`RAGService.swift:12193`), so `passage_present` genuinely means "reached the prompt"; and the
per-chunk truncation in `assembleContext` that would have made it over-count does not fire at this
budget (longest chunk 2,585 chars against a ~3,150 target, 0 of 25 truncated). Re-check the second
one only if the context budget shrinks — its floor is 400 chars.

### Current numbers (`BenchmarkRuns/PROGRESSION.md` has all 39 runs)

| run | mode | accuracy | final r@1 | final MRR |
| :-- | :-- | --: | --: | --: |
| `overnight-25case-nodeadlock` | standard | 10/25 | 0.417 | 0.590 |
| `overnight-25case-nodeadlock` | deep-think | 9/25 | 0.567 | 0.665 |
| `rescue-position-fix` | standard | **12/25** | **0.500** | **0.646** |
| `passage-level-1` | standard | 11/25 | 0.500 | 0.646 |

The last two rows are the same code. The 12 → 11 difference is the noise floor, not a regression.

**Passage-level decomposition** (`passage-level-1`, n=25, the first run ever scored this way):

| gold span | answer | count |
| :-- | :-- | --: |
| present | correct | 7 |
| **present** | **wrong** | **7** |
| absent | correct | 3 |
| absent | wrong | 7 |
| unmeasurable | correct | 1 |

Rank of the answer-bearing chunk when it is present: `1,1,1,2,2,3,3,4,4,4,4,4,7,9` — rank 1 in only
3 of 14. The three "absent but correct" rows are either matcher false negatives or QASPER questions
answerable from a second valid evidence span the fixture does not store; **do not build on that
column.**

### Settled, do not reopen

- **The fusion weight.** Three values measured (0.3/0.5/0.7); none moved the answer. Fusion now
  *beats* its lexical arm (0.708 vs 0.691 standard) after `89bf928`. That defect is gone.
- **The 1800s hang is not paper-specific.** It was a path-lookup deadlock, fixed in `73fff4f`;
  50 consecutive runs, zero timeouts.
- **"Deep Think has no reranker."** False, retracted 2026-08-20.
- **"40% accuracy is partly a grading artifact."** False. Of 13 retrieved-but-wrong standard cases,
  zero had soft `gold_recall >= 0.8` and eleven had `< 0.4`. The answers are genuinely wrong.

### Open, in order

1. **Rerank-stage chunk text** (above) — splits the 10 absent cases into two different problems.
2. **`final` r@1 (0.500) is still below `rerank` (0.667)** — at least one more stage drops rank-1
   chunks after reranking. The stage list between the two trace points is now enumerated:
   `filterBySimilarity` (`RAGEngine.swift:426`, order-preserving, **no top-1 guarantee** — it drops
   any chunk below the threshold including position 1), the spec-rescue insert (fixed in `a7c1945`),
   `ensureDocumentCoverage` (`RAGService.swift:17475`, **appends only, cannot displace position 1** —
   checked and cleared), and MMR. `filterBySimilarity` is the prime suspect on that reading.
3. **Summary injection is unmeasured as a cause.** It fires in 14/25 cases, prepends summaries ahead
   of every reranked chunk and takes ~25% of the token budget. Accuracy is lower when it fires
   (6/14 vs 6/11) but the case mix is confounded — `.investigate`/`.findings` get summaries *and*
   are harder. A controlled A/B with injection disabled would settle it.
4. **Maximum mode has never been benchmarked.**
5. **PCC is never exercised by any benchmark** (`--pcc deny` always), so the cloud path is entirely
   unmeasured.

### The benchmark is the shipping engine — verified 2026-08-21

Chat calls `ragService.query(...)` → `queryInternal(...)`. The harness constructs a real `RAGService`
and calls `queryWithAudit(...)` → the same `queryInternal`; `queryWithAudit` is `query` plus a
nil-checked trace recorder. Ingestion is the same `ingestDocuments(...)` the import button uses.
Differences: macOS rather than iOS, `--pcc deny`, fixed seed/temperature, storage redirect.

### Owner's queue, unchanged

1. **Build `main` to the iPhone.** Four vector-store loss fixes, the detector-repair fix and the
   ingestion deadlock fix are committed and **none has run on the device**.
2. **App Store Connect → Xcode Cloud workflow → read the Xcode version.** Decides Blocker 1 and
   whether PCC has ever shipped.
