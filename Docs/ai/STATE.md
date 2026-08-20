# Current State

Updated: 2026-08-20
Branch/worktree: main, clean, **not pushed** — `origin/main` is at `8791baa`, seventeen commits behind.
Last verified commit: a2f33d2

## Objective

**Get v5.0 shippable.** One question decides what 5.0 can contain and only the owner can answer it
(Blocker 1). Separately, **Deep Think underperforms Standard and the cause is now located**: fusion
degrades the ranking its own lexical arm earned, Standard's cross-encoder repairs it, and Deep Think
has no rerank stage to repair it with.

## Status

Six behavioural fixes shipped 2026-08-19, all on `main`, none pushed. Two benchmark runs completed
and are recorded in `BenchmarkRuns/LEDGER.md`. Nothing is running; no background tasks or monitors
are armed.

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
recovers via the cross-encoder. Deep Think has no `rerank` stage and never recovers. That is the
Deep Think gap, attributed by measurement rather than argument.

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

**Not run:** a deep-think fusion sweep; the 25-case benchmark; anything on device since 2026-08-19.

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
5. **Deep Think has no `rerank` stage.** Whether that is deliberate or an omission is unverified;
   `postfix-citations` simply shows the stage absent. Verify by reading where `RAGEngine.rerank` is
   called from `RAGService` and which quality modes reach it.
6. **A hang recurs on QASPER paper `1604.02038`**, third occurrence: 0.1% CPU for 21 minutes, then
   timeout. Two different case ids from the same paper. Cause unknown.
7. **Retrieval is ~21% reproducible.** Paired comparison plus the sign test is the only trustworthy
   readout. A single run cannot separate a change from noise.
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

**Investigate `applyKeywordMatchBoost` in `HybridSearchService.swift` (`:1102` uses `originalQuery`).**
It is the stage that destroys retrieval quality, and two benchmark runs now say so.

Across all four measured conditions it degrades the ranking fusion hands it, and **the damage scales
with the quality of its input**:

| condition | fusion MRR | boosted MRR | change |
| :-- | --: | --: | --: |
| standard vw0.7 | 0.448 | 0.442 | −0.006 |
| deep-think vw0.7 | 0.431 | 0.336 | −0.095 |
| standard vw0.3 | 0.571 | 0.405 | −0.167 |
| deep-think vw0.3 | 0.591 | 0.442 | −0.149 |

A stage that destroys more value the more value it receives is doing the wrong thing, not the right
thing badly tuned. Read what it boosts and why, then decide whether it should be weakened, gated, or
removed. Whatever the change, measure it the way the fusion weight was measured — Standard mode,
paired, with `scripts/compare_benchmark_runs.py` and its control line.

**The fusion weight question is closed. Do not reopen it.** `vector 0.7 / keyword 0.3` stays.
Weight 0.3 improves fusion substantially in both modes and the answer does not improve: Standard's
reranker erases the difference entirely, and Deep Think's `final` MRR fell 0.688 to 0.530 with
accuracy 3/8 to 2/8. Both runs are in `BenchmarkRuns/LEDGER.md`.

**Two tooling facts to carry forward.** `scripts/compare_benchmark_runs.py` pairs by `case_id` with
no mode filter, so passing it a two-mode run against a single-mode run silently compares different
modes — its control line catches this, but only if you read it. And Deep Think cannot be cleanly
A/B'd at stage level: the loop is adaptive, so changing any stage changes every later query, and
`vector` moved between two runs that could not have touched it. Deep-think `final` and accuracy are
per-case and trustworthy; its per-stage means are directional only.
