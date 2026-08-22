# Current State

Updated: 2026-08-22
Branch/worktree: main, clean, **not pushed** — `origin/main` is at `248f2f2`, 8 commits behind.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root.
Last verified commit: e7e51da

## First real device evidence since the vector-loss fixes landed (2026-08-22)

Owner captured a real console trace on his physical iPhone (`environment=device`, A18 Pro):
ingest a new PDF into a library, query it twice in Standard and once in Deep Think (all four real,
chunks retrieved, answers generated), then delete it. Deletion was clean: 197 chunks removed from
BNNS, FTS5 entry removed, document dropped from the list. Every other library in the workspace
loaded correctly at the end with stable chunk counts, nothing zeroed. Full trace at
`Deletion+Ingestion+closeandreopenapp+standard+deepthink.txt`.

**This does not close any of the three open vector-loss rows below.** Checked specifically: no
container switch happened during the ingestion window (rules out testing "switching libraries
during import"), and no app relaunch is visible in the capture itself (the once-per-process startup
markers each appear exactly once). It's real evidence the everyday cycle works; it isn't evidence
for the narrower scenarios those three rows are actually about.

One minor anomaly logged, not chased: one container loaded "0 chunks" then self-corrected to 182 on
the very next read, one line later. Not the permanent loss class from before. Worth a look if it
ever fails to self-correct.

## Objective

**Get v5.0 shippable.** The question that gated this is **answered**: Xcode Cloud builds with
Xcode 26.6, so PCC has never shipped and cannot reach the App Store until Apple ships the Xcode 27
Release Candidate. v5.0 is therefore either a correctness release without PCC, or it waits for the
RC. That is now a scope decision, not an unknown.

**Answer quality is now decomposed, and it is two problems of roughly equal size, not one.** As of
`passage-level-1` (2026-08-21), the answer-bearing span fails to reach the model in **10 of 24**
measurable cases, and when it does reach the model the answer is still wrong in **7 of 14**.
Retrieval and synthesis each account for about half the failures. Every prior plan assumed one of
them dominated.

## v5.0 was re-scoped on 2026-08-21: 25 open rows down to 11

The owner cut the release to rows that pass one of the three tests in `CLAUDE.md` — loses data,
breaks an advertised capability, or blocks shipping. **14 rows moved to `Future Backlog`.** Notion is
authoritative; this is a pointer, not a copy.

**What v5.0 now is:** three data-corruption fixes (the vector-loss family, all committed and none
verified on device), two broken importers (iWork, two-column PDFs), three infrastructure rows (the
release-toolchain lookup, the PCC entitlement, device testing), and three orchestration defects the
owner kept as judgement calls (background grant, reasoning-chain overrun, Self-RAG self-contradiction).

**What it is no longer, and this was deliberate:** the embedding EPIC and the WWDC 2026 API adoption
both moved out, and both had previously been named as top v5.0 goals. Liquid Glass moved too, which
means **v5.0 has no user-visible new feature — it is a correctness release** and should be named as
one in the changelog rather than presented as a feature drop.

**Critical path is now two owner-only tasks**, and both block work nobody else can start:
1. Read the Xcode version on the Xcode Cloud workflow in App Store Connect. Decides whether PCC has
   ever shipped and closes two rows at once.
2. Build `main` to the iPhone and re-run the delete → ingest → query → relaunch sequence. Closes or
   reopens the three data-corruption rows, which are the ones that made the app lose a document.

**Both agent-workable rows are now done and committed (`249dec0`), neither is closed:**

- **Pages/Numbers/Keynote.** Owner chose de-advertise over building an `.iwa` parser. Five outward
  claims corrected; the in-app half had already landed earlier in 5.0 and the row did not know it.
  Claim audit checked both directions: no iWork extraction API exists in the iOS 27 SDK, and the
  QuickLook-render-then-OCR workaround reaches page 1 only (`QLThumbnailGenerator` takes no page
  index). **Closes on the App Store Connect metadata push — an owner action. Until then the live
  listing still advertises iWork.**
- **Two-column PDFs.** The certain bug is fixed (`NSRange` from the `Substring` rather than a
  drifting counter, 7 new tests including one asserting the old counter *cannot* pass), plus a
  non-stable-sort defect that made ingestion itself nondeterministic at equal Y. Both silent
  fallbacks to raw `page.string` now log, as does the per-page strategy. **Left open on purpose:**
  the row's own instruction is not to close on the offset fix, and symptom attribution needs a
  device trace. A hypothesis was recorded — drifted bounds smear the X clusters, so column
  detection fails and the Y-only branch interleaves — and explicitly *not* claimed as established.

Verified this session: **268 tests, 3 skipped, 0 failures** (up from 261); `build_simulator_smoke.sh`
**BUILD SUCCEEDED**; `secret_scan` clean.

## Getting evidence off a phone: audited and fixed 2026-08-21

An audit of what a device trace can actually deliver found six defects. **The finding that closes a
long-standing question: the Xcode console is a *superset* of `pipeline_trace.log`, not a different
view.** Both come from the same `Log.log()` call; the file is then filtered to six categories while
the console is filtered to none, and `pipelineStep`/`pipelineHeader`/`section`/`box` are
console-only. Only the `▶ QUERY:` separators exist in the file and not the console. **A tethered
console capture has always been the best artifact.**

Fixed (`aac50a2`, `80cf974`):

| defect | state |
|---|---|
| `scripts/pull_trace.sh` referenced in code, never existed | written, verified against a booted simulator |
| `UIFileSharingEnabled` unset, so the log was unreachable in Files | set, under explicit approval, that key only |
| in-app share carried **zero** `Log` output, so no ingestion | ring buffer feeds it an `▶ ENGINE LOG` section |
| rotation checked only on the first log line per launch | evaluated against an in-process byte counter |
| two file handles clobbering each other's lines, ~0.2% | opened `O_APPEND` |
| chunk text truncated at 300 chars against ~2,600-char chunks | 4,000, and reports the real length |

**Release/TestFlight logging, corrected 2026-08-21 after an initial wrong reading.** It is **not** a
regression — the Release defaults date to `aeeed8a` (2026-04-16), the file's first commit, and have
not changed since May. It is also **not** permanently dark, which the first reading claimed:

- `_currentLevel` is `.error` and `_enabledCategories` is `[]` in Release. The category guard in
  `log()` runs *after* the level guard, so a categorised `.error` is dropped too — Release logs
  **nothing** by default, not "errors only".
- **Settings -> Developer ships in Release.** `DeveloperDiagnosticsHubView` is not `#if DEBUG` gated
  (`SettingsView.swift:560`) and `applyLoggingSettings()` sets `currentLevel` and
  `enabledCategories` at runtime. So TestFlight logging is opt-in, not absent.

**Two real gaps remain, and they are why turning it on is still not enough:**

1. The hub exposes only `.pipeline`, `.performance`, `.llm`, `.streaming`, `.vectorDB`. **`.ingestion`
   and `.retrieval` have no toggle**, and those are the two that matter most — both are in
   `fileLogCategories`, and ingestion is the whole reason the share was rebuilt.
2. **Nothing anywhere assigns `fileLogEnabled`.** It is `false` in Release and the hub does not
   expose it, so `pipeline_trace.log` can never be written on TestFlight at any setting.

With the ring buffer in `80cf974`, toggling the hub on in Release now populates the in-app share for
the five categories it covers. Adding the two missing toggles plus a file-log switch would make
TestFlight genuinely debuggable; that work is not done.

**Unverified on device.** Everything above was verified on the simulator and in tests. The next
device session should confirm the share now carries an `ENGINE LOG` section and that
`pipeline_trace.log` appears in Files → On My iPhone → OpenIntelligence.

## Release path, traced through git history 2026-08-21

**Xcode Cloud is genuinely connected, and there is repo-side proof beyond the hook script.**
`OpenIntelligence.xcodeproj/xcshareddata/xcodecloud/manifest.json` carries product id
`a3dfbb40-22a3-43ba-a366-64193d6d3e84`. Xcode writes that file when a product is *connected* to
Xcode Cloud; it was added 2026-06-19 and has never been modified since. **Owner confirms builds ran
within the last few days.**

| date | commit | what happened |
|---|---|---|
| 2026-06-19 | `af01758` | "Prepare for Xcode Cloud" |
| 2026-06-19 | `07bc138` | `.env.appstore` values **stripped from git** and gitignored; xcodecloud manifest added |
| 2026-06-20 | `6aa8469` | version bump "to trigger Xcode Cloud" |
| 2026-06-21 | `4a9911d` | `ci_post_clone.sh` added, syncing `MARKETING_VERSION` from `CHANGELOG.md` |
| 2026-07-01 | `b5983f4` | PCC entitlement added |
| **2026-07-01** | **`99ba85d`** | **PCC entitlement removed — "resolve Xcode Cloud export validation failure"** |
| 2026-07-15 | `c6052df` | PCC entitlement restored, inside an unrelated routing feature commit |
| 2026-07-30 | `b30f521` | `ci_post_clone.sh` unified iOS and macOS onto one version line |
| 2026-08-17 | `df6a97c` | `MARKETING_VERSION` 4.9 → 5.0, "so local builds match CI" |
| 2026-08-19 | `2f53440` | dead `appstore.yml` deleted |

**Why `.env.appstore` is useless to an agent:** `07bc138` stripped its values and gitignored it. The
file on disk today declares `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_BASE64`, `DIST_CERT_P12_BASE64`
and `DIST_CERT_PASSWORD` with **zero-length values** — a template reading "Dump your new keys here!"
So the App Store Connect API cannot be queried from here, and Blocker 1 cannot be closed by an agent
until those are filled.

**`release.yml` is not the App Store path and must not be cited as one.** It builds
`generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO` and publishes a GitHub Release via
`softprops/action-gh-release`. It last ran for `v4.8.0` on 2026-08-03 and **never ran for `v4.9.0`**
despite that tag existing. It is a compile check. This is the second dead-release-path trap in this
repo, after `appstore.yml`.

**Unwritten-down risk, surfaced by the table above.** Xcode Cloud rejected the PCC entitlement at
export validation once (2026-07-01). The entitlement went back on 2026-07-15 inside a feature
commit, and **nothing in the repo records re-verifying Xcode Cloud export afterwards.** Builds are
running now, so it is probably fine; it has simply never been stated as verified. The local
Xcode 27 archive check on 2026-08-20 exercised *local* distribution signing, not Xcode Cloud's.

**Blocker 1 is unchanged and is now a single question, not two.** Connection is established; the
open item is purely **which Xcode version the workflow uses**, which lives in App Store Connect and
nowhere in this repository. On 27, PCC exists in shipped builds. Below it, the eleven
`#if compiler(>=6.4)` sites compile out and every PCC request reaches `throw
LLMError.modelUnavailable` in the shipped app.

## Benchmark temperature does not match the app — found 2026-08-21, unresolved

`InferenceConfig.ragOptimized` sets `temperature = 0.7 // Balanced creativity`, but that is a
**ceiling**, not an operating value. `RAGService.swift:12745` applies
`min(config.temperature, qualityMode.temperature)` and `.standard` is **0.4**; the evidence-first
prompt, `highAccuracy` config, retry, repair and fallback paths clamp further to 0.2/0.15.

**The harness overrides all of it.** `--temperature` is applied in `LLMService` where
`GenerationOptions` is built, downstream of every clamp, so `--temperature 0.7` forces a hotter
setting than the app ever uses. **Every accuracy figure on record — 4.9's 27.3%, 5.0's 40/44/48% —
was measured at 0.7. The app ships 0.4.**

The 4.9 vs 5.0 delta survives, because both arms were pinned to the same 0.7 and the difference is
therefore attributable to code. The **absolute** numbers do not describe the shipped product.

**Next run should be `topk` with no `--temperature`**, so the clamps apply and the benchmark
describes the app. If cooler helps, the shipped app is already better than every recorded number.
Unmeasured, one run to find out.

Also verified against Apple's SDK the same day: `GenerationOptions` exposes exactly
`samplingMode`, `temperature`, `maximumResponseTokens`, `toolCallingMode` (27+). **The
`frequencyPenalty`, `presencePenalty` and `repetitionPenalty` fields in `ragOptimized` are dead
config** and never reach the model. Apple documents temperature as 0–1; the harness validates 0–2.

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

1. **RESOLVED 2026-08-21, from the workflow screen.** Xcode Cloud's `Default` workflow has
   **Xcode Version = "Latest Release", currently Xcode 26.6 (17F113)**, building
   `github.com/Gunnarguy/OpenIntelligence.git` on `main`. Xcode 27 appears in that dropdown **only**
   as the alias "Latest Beta or Release — Xcode 27 beta 5 (27A5237l)"; the Released Versions list
   tops out at 26.6.

   **Therefore PCC has never shipped to a single user.** Every App Store build was produced by
   Xcode 26.x, so the eleven `#if compiler(>=6.4)` sites across six files compiled out and every PCC
   request in a shipped build reaches `throw LLMError.modelUnavailable`. The entitlement being
   present and surviving distribution signing was necessary and never sufficient.

   **What is possible today, verified against Apple:** Apple permits Xcode 27 beta builds to be
   submitted "for internal and external testing" — TestFlight's two tester types — and **no Xcode 27
   Release Candidate exists** (developer.apple.com/news/releases confirms beta 5 of 2026-08-10 as
   the newest, with 26.6 RC 2 the newest RC). App Store submissions historically open at the RC:
   last cycle that was 2025-09-09 for Xcode 26. So switching the workflow to "Latest Beta or
   Release" would put PCC into a TestFlight build **now**, and could not reach the App Store until
   the 27 RC ships.

   **A scheduled surprise worth knowing about:** the workflow is pinned to an *alias*, not a
   version. The day Xcode 27 goes GA, "Latest Release" silently becomes 27, every gated site starts
   compiling in, and PCC appears in builds with no one having changed a setting. That is desirable
   only if the PCC path is ready on the day it happens.

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

**One run answers the two biggest open questions: add rerank-stage chunk text to the harness, then
run the 25 cases under `--rag-validation-sampling greedy`.** Do not run these separately.

*Greedy* removes the sampler from the picture by construction — it takes the highest-probability
token and ignores temperature — so for the first time a repeat run measures only what the pipeline
did, not what the sampler drew. That is what makes every subsequent A/B readable; the ±1 accuracy
noise floor is currently what blocks every other measurement on the board.

*Rerank-stage chunk text* splits the single biggest open number into two problems with unrelated
fixes.

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
