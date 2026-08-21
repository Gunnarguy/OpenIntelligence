# Current State

Updated: 2026-08-20
Branch/worktree: main, clean, **not pushed** — `origin/main` is at `8791baa`, seventeen commits behind.
Last verified commit: 89bf928

## Objective

**Get v5.0 shippable.** One question decides what 5.0 can contain and only the owner can answer it
(Blocker 1). Separately, **Deep Think underperforms Standard and the cause is open again**: the
"no reranker" attribution was retracted on 2026-08-20 — Deep Think reranks unconditionally
(`RAGService.swift:18396`); only the trace record was missing. See the ledger retraction. The
survival fix (`89bf928`) repaired the shared fusion-burial defect for both modes.

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

**FIRST, hours-later addendum: the 0-chunk phantom REPRODUCED live — `0350083` does not close the
vector-loss row.** The evening's fresh import (`FE9E86BF`, 197 searchable, answering queries) came
back after relaunch as `1 document(s) and no vector store yet`, document invisible in the UI. Two
candidate mechanisms are on [the row](https://app.notion.com/3c149a74d54f81239443c15fe6ae3782) —
deferred BNNS persist never flushed before exit, or the deleted-mid-import fallback misfiling the
store during the resurrection churn. **The one-line tell:** the next ingestion console either shows
`[BNNS] Persisted 196 chunks` (flush-timing problem; fix = persist barrier at end of ingest + a
terminal flush on scene-phase change) or it doesn't / shows it under another container's file
(fallback problem; fix = fail the ingest loudly rather than fall back to the active container).
Owner's recovery: one tap of Rebuild. **Captures overwrite `XcodeConsole.txt` — grep each new one
for `BNNS] Persisted` immediately, before it is replaced.**

**Added 2026-08-20 late, from the owner's ingestion/deletion/query capture** (before the
interleaved-fixture item below, which still stands):

- **Library deletion races its own background writers — log-proven, filed.** Tap one deletes data;
  `SelfTuning`, `Spotlight` and a metadata save then write to the dead container and resurrect it;
  tap two deletes the shell. Row (Future Backlog):
  [delete race](https://app.notion.com/3c349a74d54f81beaad5c59162e58434). A partial-resurrection
  variant is filed on the v5.0 vector-loss row as a second candidate origin for the 0-chunk
  phantoms — hypothesis, not established.
- **Case 1 of the three-import protocol effectively passed live**: fresh Yagishita import → 196
  chunks in 5.75s → immediate correct Deep Think answers. Cases 2 and 3 (mid-import switches)
  remain the owner's.
- **`ingested 196 / searchable 197` is benign** — the +1 is the RAPTOR-lite L1 summary chunk. The
  LIBRARY STATE trace warning over-fires on small positive deltas; softening its wording is a
  follow-up (no code changed tonight, builds paused). **Documents-present with 0 searchable remains
  the real signature.**
- **Open anomaly:** queried "Library 7" (`FE9E86BF`) carries the pre-re-export fingerprint
  `0ca10df0…`, impossible for a container created tonight. Most likely the import landed in an
  older shell (resurrection-adjacent). **The owner's library list (names + doc counts) settles it**;
  ask for it or for the next trace share. Sync merge-by-name is ruled out (id-keyed,
  `WorkspaceSyncService:2893`; `mergeContainer` never copies fingerprints).


**Run the interleaved-fixture test; its first run is the verdict on the PDF block builder.**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" \
  -derivedDataPath /private/tmp/oi-test-dd -skipPackagePluginValidation \
  -only-testing:OpenIntelligenceTests/LayoutReadingOrderTests
```

Context, so nobody re-derives it: the 2026-08-19 device capture showed two-column text interleaved
and fragments glued (`disserotonin`). The first diagnosis — `extractBlocksFromPDFPage` building
blocks by string-splitting `page.string` — was **refuted before any code changed**: four ordered
fixtures all passed against it, because drawing columns in order makes `page.string` ordered and
never stresses the builder. `testInterleavedContentStreamIsReorderedByGeometry` (authored, never
run) models content-stream disorder faithfully and asserts its own precondition, so its outcome is
decisive either way:

- **Fails** → the builder is convicted after all; fix is geometry-true lines via
  `PDFSelection.selectionsByLine()` on a whole-page selection, then re-run all five fixtures.
- **Passes** → the PDFKit path is exonerated end to end and the device damage entered elsewhere —
  the Vision/OCR route (the `5-HTiA` shapes point there) or a downstream merge in
  `extractWithStructuredParsing` (`DocumentProcessor.swift:3825`). Next probe: the Jaccard
  text-layer gate at `:3848` is order-insensitive by design, so a scrambled-but-real text layer
  passes validation; instrument which route each page of a suspect PDF takes.

This is part of the **WWDC26 adoption + extraction quality** arc the owner pulled back into 5.0:
the adoption row's live checklist names SpotlightSearchTool + OCRTool binding
(`FoundationModelToolRegistry.swift:426` — NOT hard-boundary, adoptable), `response.usage`
telemetry, and tools/transcript terms into the token budget (`RAGService.swift:15028,:15038`).
SQLite/FTS5 was audited read-only: WAL + busy_timeout + porter/unicode61 + weighted bm25 on the
chunks query — fundamentally sound; open tunables are the trigram index (existing row), missing
prefix indexes, and one unweighted bm25 query path (`document_pages`, `:518`). Schema is
hard-boundary; changes need the owner to name the file.

**Builds were deliberately paused 2026-08-20 evening for the owner's raid** — nothing was running
when this was written. The five fixture tests are committed; four are run-and-green, the
interleaved one is authored-only, and the commit message says exactly that.
