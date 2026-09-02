> **Documentation status:** Measurement sections re-verified 2026-08-13 against the completed 83-case run. The framework sections below still date from v4.4 on 2026-06-30. **4.9 is the App Store version; 5.0 is being prepared.** See `Docs/SHIPPED_VERSION.json`.
> **Read this before trusting any mode comparison.** Two defects invalidated quality-mode benchmark runs made before they were fixed, and both are in the measurement path this document describes:
> 1. Until 2026-07-30 the Deep Think and Maximum reasoning chain abstained on every session, so every prior mode comparison measured Standard against a broken path (fixed in `665da0a`).
> 2. Until 4.9 the post-retrieval planner read `chunks.first`'s similarity score rather than the maximum over the set, which triggered abstentions from a number that never described the evidence (fixed in `acfbfbd`).
>
> No dataset score for Deep Think or Maximum exists that postdates both fixes. Extending this harness to report retrieval-stage metrics — recall@k, MRR, nDCG — is item 2A in `Docs/Engineering/RETRIEVAL_UPGRADE_PLAN_2026-08.md` and is the next planned work.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

# OpenIntelligence RAG Pipeline Evaluations

## Start here

**This file is the single entry point for "how good is this engine, and how do I know".** Nothing
about measurement should live anywhere else without being linked from here.

If you read one thing, read [What has actually been measured](#what-has-actually-been-measured-as-of-2026-08-12).
The short version as of 2026-08-13:

| Question | Answer |
| :--- | :--- |
| How accurate is it? | **44% exact match, 46% gold recall**, on 72 answerable external questions |
| Is that good? | Unknown. It cannot be honestly compared to published QASPER scores. See [Token-F1](#what-has-actually-been-measured-as-of-2026-08-12) |
| Where does it lose? | Retrieval truncation. The right document reaches final ranking on **75% of missed cases** |
| What is the biggest lever? | Final retrieval breadth (`--top-k`), then RRF fusion weighting, then the embedder |
| What is untested? | Deep Think, Maximum, iPhone, real user documents, 7 shipping pipeline stages |

### Where everything lives

| What | Where |
| :--- | :--- |
| Measured results, findings, caveats | **this file** |
| One committed summary per run | `Docs/AuditArtifacts/Benchmarks/` |
| Full run artifacts, per-case reports | `BenchmarkRuns/`, **gitignored**, local only |
| How to build and run a benchmark | `Docs/ai/RUNBOOK.md`, "Retrieval benchmark" |
| Current state and next action | `Docs/ai/STATE.md` |
| The 31-step pipeline being measured | `Docs/Engineering/RAG_TECHNICAL.md` |
| Quality-mode defect history | `Docs/AUDIT/QUALITY_MODE_VERIFICATION_2026-07-30.md` |
| The fixture corpora | `Benchmarks/ResearchFixtures/`, one README per pack |
| Roadmap rows for outstanding work | Notion, via the `notion-roadmap` skill |

### The scripts

```bash
python3 scripts/build_external_fixtures.py --check    # verify the external corpus, offline
python3 scripts/build_eval_dataset.py --check         # verify the JSONL matches the manifests
python3 scripts/run_quality_matrix.py --app <app> ... # run a benchmark
python3 scripts/save_benchmark_summary.py <run-dir>   # commit the result so it survives
python3 scripts/sweep_fusion_weight.py <run-dir>      # re-score other fusion weights, no run
python3 scripts/compare_runs.py <baseline> <candidate>  # paired case-by-case comparison
```

**Compare two runs paired, not as two averages.** These fixtures are a fixed ordered list, so two
runs over the same manifest answer the same questions. The useful question is not whether the mean
moved but on how many individual questions the change won and lost, which is an exact sign test on
the discordant pairs. That is the analysis that produced the only statistically meaningful retrieval
finding here, RRF fusion losing to the lexical arm 26 to 6 at p = 0.0005. Pairing also rescues an
interrupted run: 40 of 83 cases cannot be compared to an 83-case average, but is perfectly valid
against the same 40 baseline cases. `compare_runs.py` reports the cases a change **broke** before
the ones it fixed, because those are the ones worth reading.

The heading used to carry a count. It was wrong by one before this line was added, which is the
same drift that took the release-note entry count from 46 to 74 to 87 in a single day. Counts in
prose go stale; the list below them does not.

**Always run `save_benchmark_summary.py` and commit its output.** `BenchmarkRuns/` is gitignored, so
a run that is not summarised did not happen as far as the next person is concerned. That was true of
every run this project made before 2026-08-12.

### Answering a fusion-weight question without spending a run

A run costs about 4.7 hours and pins the machine. The hybrid fusion weight does not need one:
`RAGEngine.reciprocalRankFusion` is a pure function of the two arms' rank orders, the weight, and
`k = 60` (both call sites, `HybridSearchService.swift:276` and `:1075`). The harness records both
arms in rank order, so the fusion can be replayed for any weight in seconds.

```bash
python3 scripts/sweep_fusion_weight.py BenchmarkRuns/<run> --weights 0.0:1.0:0.05
```

Three things bound what that can tell you, and all three matter.

**It measures retrieval, not answers.** Accuracy cannot be recomputed offline, because generation
ran once against one selection of chunks. Use the sweep to choose a weight, then spend a single
confirming run on that weight instead of one run per candidate.

**It refuses to emit an uncalibrated curve.** Before sweeping, it replays the fusion at the weight
the run actually used and checks the result against the app's own recorded `fusion` stage twice:
the rank order chunk by chunk, and the recomputed metrics against the Swift `STAGE METRICS` row.
Below either threshold it fails loudly instead of printing numbers. This is the answer to the
objection in `run_quality_matrix.parse_stage_metrics`, which is right that a second metric
implementation drifts: this one is checked against the first on every invocation.

**Runs recorded before 2026-08-13 cannot be swept at all.** `STAGE SOURCES` emitted display names
until then, and `sourceDocument` is attached after hybrid search returns, so `vector`, `lexical`,
`fusion`, `boosted` and `candidates` all recorded `(unnamed)`. Those five stages were unverifiable
by hand for the same reason. It now emits `<chunkId>#<documentId>#<name>`: chunk identity because
fusion keys on `chunk.id`, document identity because relevance is judged per document.

`[evidence_level: code_verified, confidence: exact, evidence_source: DebugRAGValidationHarness.swift
stageMetricsLines; RAGEngine.swift:899-956; sweep_fusion_weight.py --self-test]`

### Which stage actually earns its place, measured 2026-08-14

Every stage transition tested on the **existing** `BenchmarkRuns/qasper-overnight` artifact, 72
answerable cases, paired, exact two-sided sign test on discordant pairs. **No new run was needed.**
The answer had been sitting on disk since 2026-08-12; nobody had asked the artifact this question.

| transition | better | worse | p | verdict |
| :--- | ---: | ---: | ---: | :--- |
| `lexical` -> `fusion` | 6 | 26 | **0.0005** | fusion significantly hurts |
| `fusion` -> `boosted` | 22 | 21 | 1.0000 | no effect whatsoever |
| `boosted` -> `candidates` | 0 | 0 | 1.0000 | pure truncation, reorders nothing |
| `candidates` -> `rerank` | 29 | 15 | **0.0488** | reranking significantly helps |
| `rerank` -> `final` | 16 | 25 | 0.2110 | not significant |
| `lexical` -> `final` | 16 | 21 | 0.5114 | not significant |

**This reproduces the fusion finding independently.** 26 to 6 at p = 0.0005 is the same result
recorded from the original analysis, arrived at through separate code, which is the first time any
finding here has been confirmed twice.

**The cross-encoder reranker is the only stage with demonstrated value.** It is also the stage most
often proposed for removal on latency grounds. Do not remove it.

**The structure and keyword boost stage buys nothing.** It reorders 43 of 72 cases and wins on
almost exactly half of them. Mean result count is identical either side (190.7), so it is pure
reordering, and `R@10` actually falls slightly across it, 0.792 to 0.764. It is the cleanest
deletion candidate in the pipeline, and removing it is measurable rather than a matter of taste.

**Do not read the mean MRR column and conclude `final` is losing what `rerank` gained.** Means say
0.626 to 0.549 and the paired test says p = 0.211. That conclusion was drawn and withdrawn on
2026-08-14 within the hour. Truncation is not the mechanism either: `R@10` barely moves, 0.819 to
0.806, while the list goes from 90 chunks to 8.

`[evidence_level: measured, confidence: exact, evidence_source: BenchmarkRuns/qasper-overnight
results.jsonl, 83 cases / 72 answerable; scripts/compare_runs.py exact_sign_test]`

### The optimal dense weight is zero, swept 2026-08-14

Offline fusion sweep over the completed `qasper-postfix-20260813` run, 68 of 83 cases sweepable.
Cost seconds, not the 4.7 hours a second benchmark run would have cost. Run twice, at 58 cases
mid-run and 68 at completion, and the shape and conclusion were identical both times.

**Calibration passed first:** the effective weight was recovered per case by fitting each recorded
`fusion` order, giving a median of **0.49** with a range of 0.00 to 0.62, and a median top-10 order
agreement of **100%**. That the recovered weights land inside the [0.35, 0.65] clamp is independent
confirmation that the replay models the real fusion rather than approximating it.

| dense weight | MRR@10 | R@1 | R@5 | R@10 |
| ---: | ---: | ---: | ---: | ---: |
| **0.00** | **0.6416** | 0.5735 | 0.6912 | 0.8088 |
| 0.10 | 0.6224 | 0.5441 | 0.7206 | 0.7794 |
| 0.30 | 0.6128 | 0.5294 | 0.6912 | 0.7794 |
| 0.50 | 0.5503 | 0.4706 | 0.6618 | 0.7500 |
| 0.70 | 0.4240 | 0.3382 | 0.5294 | 0.6471 |
| 1.00 | 0.2798 | 0.1765 | 0.4265 | 0.5441 |

**Monotonic.** Every increase in the dense arm's share makes retrieval worse. Moving from the app's
effective 0.49 to 0.00 takes MRR@10 from 0.550 to 0.642, a **17% relative gain**. This extends the
earlier sign-test finding from "fusion loses to lexical" to "no mixture beats lexical alone".

**32 of 68 cases calibrated below 95% order agreement** even though the median was 100%, so the
replay is not equally faithful everywhere. That is the single biggest reason to confirm this with
one real run at a pinned `--vector-weight 0.0` before changing the product default.

**Four constraints on that claim, none of them small.**

1. **Retrieval only.** Answer accuracy cannot be recomputed offline, because generation ran once
   against one selection of chunks. This picks a weight; it does not prove the answer improves.
2. **27 of 58 cases calibrated below 95% order agreement**, even though the median is 100%. The
   replay is not equally faithful everywhere, and cases where it is poor contribute noise.
3. **`w = 0.00` is a special case worth distrusting slightly.** With the dense arm contributing
   nothing, every vector-only chunk scores exactly zero and ties, which is why the tie count jumps
   to 121 there. The top ten remain lexically ordered and well defined, and the resulting MRR
   matches the `lexical` stage figure closely, which is the reassuring cross-check.
4. **It says nothing about the embedder question.** A dense arm this weak is the argument *for*
   replacing MiniLM, not against having one. Zeroing the weight banks the gain now; it does not
   settle whether a better embedder would earn its share back.

`[evidence_level: measured, confidence: high, evidence_source: scripts/sweep_fusion_weight.py over
BenchmarkRuns/qasper-postfix-20260813, 58 sweepable cases, calibration median 100% order agreement]`

### Do not do heavy file work while a run is measuring

Measured 2026-08-14, unintentionally. Per-case wall clock in one run: **461s for cases 1 to 10, 462s
for 11 to 20, then 277s for 21 to 30**, against a 209s baseline. Nothing in the code changed. What
changed is that the agent driving the session stopped making large file copies (a 315 MB library
backup and two full repository rsyncs) on a machine already syncing `~/Documents` through iCloud.

A 40% swing with no code change is larger than most retrieval work will ever produce. Two
consequences: treat per-case seconds from a run that shared its machine as unusable for comparing
code, and keep the machine otherwise idle when latency is the thing being measured. `compare_runs.py`
prints a warning next to its timing line for exactly this reason.

### Two things that will mislead you

1. **Never compare a `tiny_research_suite` number to a `qasper_external_v1` number.** The synthetic
   pack ingests only the documents a case names, so retrieval cannot fail and its stage figures are
   arithmetic. A delta between the packs measures the fixture, not the app.
2. **Never compare a stage figure from before 2026-08-11 to one after.** The ground truth changed,
   not the pipeline.

---


This document describes the formal evaluations framework implemented in OpenIntelligence. This framework is designed to validate the RAG pipeline's behavior, latency, and quality against the target quality gates defined in WWDC26.md *(that document no longer exists in this repository; noted 2026-08-27)*.

---

## Quality Gates Target Metrics

The pipeline must satisfy the following metrics during an evaluation run:

| Metric | Target | Description |
| :--- | :--- | :--- |
| **Retrieval Recall@5** | $\ge 0.85$ | Fraction of ground-truth chunks appearing in top-5 retrieval results. |
| **Citation Precision** | $\ge 0.90$ | Fraction of cited sources in generated responses that are correct. |
| **Exact-value Accuracy** | $\ge 0.95$ | Fraction of exact-value queries answered correctly. |
| **Unsupported-claim Rate** | $\le 0.05$ | Fraction of generated responses containing unsupported claims (hallucinations). |
| **Correct Abstention Rate** | $\ge 0.85$ | Fraction of out-of-scope/adversarial queries correctly abstained. |
| **Context Overflow Rate** | $\le 0.02$ | Fraction of queries that hit context window limitations. |
| **Visual OCR Evidence Use** | $\ge 0.90$ | Fraction of visual queries utilizing OCR text. |

---

## Dataset Format (`.jsonl`)

Evaluation datasets are represented as JSON Lines files, with one JSON object per test case. Comments starting with `//` and blank lines are ignored.

### Example JSONL Case

```json
{
  "id": "exact-001",
  "query": "What is the engine oil capacity?",
  "expectedAnswer": "5.1 qt",
  "category": "exact_value",
  "groundTruthChunkIds": ["chunk-abc-123"],
  "expectedCitations": ["Manual.pdf"],
  "shouldAbstain": false
}
```

---

## What has actually been measured, as of 2026-08-12
<a id="what-has-actually-been-measured-as-of-2026-08-12"></a>

This section exists because this document described a framework and recorded no results, while
`BenchmarkRuns/` is gitignored so no run survives a clone. Anyone asking "how accurate is this
engine" had nothing to read. These are the real numbers with what each one is worth.

| Measurement | Result | n | What it actually measures |
| :--- | :--- | ---: | :--- |
| Synthetic pack, 2026-08-11, standard | 18/20 correct, 0 hallucinated **(withdrawn 2026-08-21, see below)** | 20 | reading one correct document and restating it |
| QASPER external, 2026-08-19, standard | 0.410 exact-match, 77 of 83 scored | 83 | real research papers this project did not write |
| **QASPER external, 2026-08-12, standard, complete** | **34/77 correct (44%)**, 40 miss, 3 hallucinated, 6 error | 83 attempted | answering externally-authored questions against 9 distractor papers |
| Unit suite | 236 pass, 0 fail | 236 | that units behave; no end-to-end coverage of routing, gates, sync or retrieval |

### The first run that could fail: 2026-08-12, 83 cases, 4.8 hours

Full summary in `Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md`. Commit `9c634938`, clean
tree, `--pool-limit 10`, PCC denied.

| Stage | R@1 | R@5 | MRR@10 | Mean candidates |
| :--- | ---: | ---: | ---: | ---: |
| `vector` | 0.18 | 0.40 | **0.28** | 180 |
| `lexical` | 0.58 | 0.69 | **0.65** | 35 |
| `fusion` | 0.40 | 0.65 | **0.51** | 191 |
| `boosted` | 0.42 | 0.64 | 0.51 | 191 |
| `candidates` | 0.42 | 0.64 | 0.51 | 90 |
| `rerank` | 0.54 | 0.74 | **0.63** | 90 |
| `final` | 0.43 | 0.72 | 0.55 | 8 |

At n=77 the smallest resolvable difference is about 8 points, so the gaps below are real.

**1. Dense retrieval is the weakest stage by a wide margin.** `vector` MRR@10 **0.28** against
`lexical` **0.65**. MiniLM-L6-v2 is 384 dimensions and from 2021, and on this content BM25 is
carrying retrieval nearly alone. This is the measured basis for the embedder work; it did not exist
before this run.

**2. RRF fusion makes retrieval worse than BM25 alone, and this is significant.** `lexical` MRR 0.65
falls to `fusion` 0.51. Tested per-case rather than on the means: across 72 paired cases lexical beat
fusion on **26**, fusion beat lexical on **6**, 40 tied. Exact two-sided sign test on 32 discordant
pairs, **p = 0.0005**. Blending a weak dense ranking into a strong lexical one is actively costing
rank quality. That is an architectural finding, not a tuning one, and it is the most actionable
result here.

**3. The cross-encoder earns its place.** `rerank` lifts MRR from 0.51 to 0.63 and R@5 from 0.64 to
0.74. It is repairing much of the damage fusion does.

**4. The final cut loses ground.** `rerank` 0.74 R@5 to `final` 0.72, MRR 0.63 to 0.55, as the set
narrows to 8 chunks. Small, but it is the top-K truncation trading rank quality for context budget.

**5. Six cases produced nothing.** Four timed out at 600s and two returned no report. That is 7% of
the run yielding no measurement at all, and it is not yet explained.

`[evidence_level: measured, confidence: exact, evidence_source: BenchmarkRuns/qasper-overnight, summarised at Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md; sign test computed over per-case stage_metrics]`

**The 90% does not mean what it looks like.** Every case in that run was scored against an index
containing only its own answer, so retrieval was arithmetically incapable of failing. The corpus was
written by this project and the answers chosen by this project.

**The 44% was scored strictly**, by regex against the exact span two annotators agreed on, so a
correct paraphrase counts as a miss. Six cases produced no result at all and are excluded from the
denominator.

**It was assumed to be a large undercount. It is not.** Adding gold-token recall, which is blind to
phrasing and to verbosity, gives **46%** against exact match's 44% over the same 72 answerable
cases. Exact match is a floor and recall a ceiling, and the two-point gap between them means the
expected answer is genuinely absent from the response about 54% of the time. This is not a scoring
artefact, and no change to the metric will improve it.

**Token-F1 is deliberately not reported**, though it is what every published QASPER figure uses.
Implemented naively it returns 3.3 here, because F1 divides by prediction length and the median
generated answer is 59 tokens against a median gold span of 1. That also retracts a comparison made
earlier on 2026-08-12: the published numbers (Longformer 39.4, CoLT5 XL 53.9, RAPTOR+GPT-4 55.7) are
F1 over **span-extraction** output, and this app generates prose. **44% here is not on the same
scale as 39.4 there**, and the claim that this app beats that baseline was withdrawn. Comparing
properly would require constraining generation to a span, which would change the product.

### The misses are retrieval failures, not scoring artifacts

Worth recording because the opposite was assumed first and inspection disproved it. Two misses from
the smoke run, read directly:

- *"How big is the ANTISCAM dataset?"* expected `220 human-human dialogs`. Answered **"the exact
  size of the dataset is not provided in the excerpts"**. The sentence is in the paper; it never
  reached the context. Note the engine did **not** invent a number.
- *"What are the baselines outperformed by this work?"* expected `TransferTransfo`. Answered that
  the work "outperforms multiple baselines ... as stated in the abstract". It retrieved the
  **abstract** instead of the results section: enough to gesture, not enough to name.

Both failures are upstream of generation, and the completed run bears the pattern out at scale:
`vector` MRR@10 **0.28** against `lexical` **0.65** over 72 cases. Dense retrieval contributes little
on this content and BM25 carries it; when exact-term matching does not fire, the wrong passage is
what reaches the model. **This is the measured argument for the embedder work**, and it is the first
evidence this project has had for it.

### Abstention behaves differently on external questions

The synthetic pack reports abstention **2/2** correct. The completed 2026-08-12 run scored
**2/5** on externally-authored unanswerable questions: it answered three questions the paper does
not answer. A sixth abstention case errored and was not scored.

`n=5` is still small, and the earlier partial run's 0/2 was pessimistic. But the direction holds:
the synthetic controls were questions this project invented to be unanswerable, which is a far
easier test than a real reader's question that the paper happens not to answer. **Anti-hallucination
is a headline differentiator and it fails more than half the time on external unanswerable
questions.** That gap between 2/2 and 2/5 is the clearest example in this document of why a
self-authored fixture flatters the thing it measures.

### What is not measured at all

- **Accuracy on real user documents.** Everything above is self-authored or NLP papers.
- **Deep Think and Maximum.** Both failed on most cases in the 2026-07-30 matrix run; both were
  fixed the same day in `665da0a` and `b271ecf` and device-verified over four iPhone runs. **Neither
  has been benchmark-measured since.** The fix closed the defect, not the question of whether the
  extra compute buys correctness.
- **iPhone.** Every benchmark figure is from the macOS build.
- **Regression over time.** No run is committed, so there is no series to compare against.
- **Seven pipeline stages** that ship and run, listed `[UNSPECIFIED]` in `Docs/Engineering/RAG_TECHNICAL.md`.

`[evidence_level: measured, confidence: exact_for_the_numbers_stated, evidence_source: BenchmarkRuns/20260811-150328-matrix/results.json; interrupted 2026-08-12 QASPER run; per-case reports read directly for the two misses quoted]`

### An open claim that needs an audit

Two user-facing strings advertise **extractive QA**: the Standard quality-mode description
("Full pipeline with verification gates, graph context & extractive QA") and `AboutView`
("Apple Foundation Models or extractive QA"). Step 5.10 Extractive QA is disabled in code, and
`ExtractiveQAService` has no call sites outside its own file. That looks conclusive, and it is
deliberately **not** being changed here: this repository has already deleted one true claim on
exactly that reasoning. Run `oi-claim-audit` before touching either string.

## The Datasets

Two packs, measuring different things. Both are generated, not hand-written, and both are
reproducible by anyone with the repository.

| Dataset | Cases | Ground truth | Corpus per case |
| :--- | ---: | :--- | :--- |
| `Benchmarks/rag_eval_v1.jsonl` | 20 | authored in this repo | only the files the case names |
| `Benchmarks/rag_eval_qasper_v1.jsonl` | 83 | QASPER, CC BY 4.0 | a shared 40-paper pool |

**Use the QASPER pack for any question about whether a change helped.** The synthetic pack
ingests only the documents a case names, so its index contains nothing that is not the answer.
On the 2026-08-11 run that left the vector stage ranking between two and five candidates, all
of them correct, which pins `R@5` and `MRR@10` at 1.000 as a matter of arithmetic rather than
pipeline quality. It can still catch a regression, and it stays as the fast smoke pack.

The QASPER pack declares a shared `pool` in its manifest that is ingested for every case, so
each question is asked against 39 distractor papers and retrieval is able to fail. Its ground
truth also came from outside: readers wrote the questions from title and abstract alone, and
separate annotators answered them against the full text. Cases are kept only where at least
two annotators agreed, and the count is recorded per case.

`[evidence_level: run_artifact_verified, confidence: exact, evidence_source: BenchmarkRuns/20260811-150328-matrix/reports/*.txt STAGE METRICS results column; run_quality_matrix.py:391 and :720]`

Ground truth lives in the pack manifests, which the in-app validation harness already consumed
in its own schema. `scripts/build_eval_dataset.py` converts each manifest into the `RAGEvalCase`
JSONL this framework loads, so the two evaluation systems cannot drift apart:

```bash
python3 scripts/build_eval_dataset.py          # regenerate every pack
python3 scripts/build_eval_dataset.py --check  # fail if stale vs. the manifests
```

The QASPER corpus itself is rebuilt and verified separately, and `--check` needs no network:

```bash
python3 scripts/build_external_fixtures.py          # rebuild from Hugging Face
python3 scripts/build_external_fixtures.py --check  # verify against fixtures.lock.json
```

Never edit a JSONL by hand. Edit the manifest, or rebuild the pack, and regenerate.

**Figures from the two packs are not comparable.** Different corpus, different ground truth,
different difficulty; a delta between them measures the fixture rather than the app.

### Coverage

`rag_eval_v1.jsonl`, synthetic:

| Cases | Category | Exercises |
| :--- | :--- | :--- |
| 5 | `exact_value` | Precise figure lookup from tables and prose |
| 5 | `factual` (retrieval-only) | Single-document grounded recall |
| 3 | `factual` (lost-in-middle) | Answer position sensitivity: start, middle, end of context |
| 5 | `multi_document` | Two-hop synthesis across paired documents |
| 2 | `abstention` | Negative controls: the answer is genuinely absent and the app must abstain |

`rag_eval_qasper_v1.jsonl`, external:

| Cases | Category | Exercises |
| :--- | :--- | :--- |
| 55 | `exact_value` | Extractive spans from a research paper, agreed by 2+ annotators |
| 22 | `factual` (retrieval-only) | Free-form and yes/no answers grounded in one paper |
| 6 | `abstention` | Questions a majority of annotators judged unanswerable from the paper |

The original manifest category is preserved in each case's `tags`, so `lost_in_middle` and
`retrieval_only` subsets stay selectable even though both map onto `EvalCategory.factual`.

The QASPER pack has no `multi_document` cases on purpose. Every QASPER question is answered
inside a single paper, so labelling one that way would assert a second required document that
does not exist. Questions whose supporting evidence spans several sections are real
multi-chunk synthesis, which is a different property; those carry the `multi_paragraph` tag
instead, and `expected_evidence` in the manifest records the sections involved.

The two abstention cases matter most. They are the only cases that catch confident fabrication, which is the failure mode this project's verification gates exist to prevent.

### Limits

This corpus is small and synthetic. It is a regression guard, not a benchmark — it will catch a pipeline change that breaks exact-value lookup or abstention, but it will not tell you how the system performs on real documents at scale. Treat a passing run as "nothing obvious broke," not as a quality score.

---

## Execution & Report Generation

To run evaluations programmatically:

```swift
let dataset = try RAGEvalDataset.load(from: datasetURL)
let runner = RAGEvalRunner()
let results = try await runner.run(dataset: dataset, ragService: ragService)
let metrics = RAGEvalMetrics.compute(from: results)

// Generate Markdown Report
let markdownReport = RAGEvalReportWriter.generateMarkdown(
    metrics: metrics,
    results: results,
    datasetName: dataset.name
)

// Generate JSON Report for CI/CD tracking
let jsonReport = try RAGEvalReportWriter.generateJSON(metrics: metrics, results: results)
```

---

## Apple Evaluations Framework Integration

The `AppleEvaluationsBridge` class provides compatibility with Apple's command-line tools and testing suites (`fm CLI`), allowing the evaluation runs to be analyzed natively on Apple platforms.

---

## Route Evidence Gates (Phase 9)

The metrics above score **answer** quality. `RouteEvalMetrics` scores **route honesty**: whether the `ModelExecutionReceipt` chain a run produced is internally consistent and fail-closed.

These gates exist because a route claim carries privacy consequences. A receipt that reports Private Cloud Compute for an answer that never left the device — or the reverse — is worse than no telemetry at all.

### Invariants

Every receipt is checked against six invariants. All are blocking: each one, if violated, makes route telemetry actively misleading rather than merely incomplete.

| Invariant | Guarantee |
| :--- | :--- |
| `completedTargetAttested` | A receipt may only claim a route that has a `.succeeded` attempt on that same route |
| `fallbackAttributed` | If `intendedTarget != completedTarget`, `fallbackReason` is set |
| `fallbackReasonRequiresDivergence` | If `intendedTarget == completedTarget`, `fallbackReason` is `nil` |
| `quotaFailClosed` | `.limitReached`, `.unsupported`, and `.unknown` quota states all block PCC attempts |
| `attemptChainPresent` | A non-abstaining receipt records how the answer was produced |
| `actualTargetAttempted` | The attempted route appears in the attempt chain |

`.unknown` is fail-closed deliberately: unrecognized SDK quota values map to `.unknown`, and an unrecognized state is not permission.

### Promotion Gates

| Gate | Target |
| :--- | :--- |
| Receipt integrity rate | $= 1.00$ |
| Unauthorized cloud attempts | $= 0$ |
| Unattested completions | $= 0$ |
| Unexplained fallbacks | $= 0$ |
| Receipts scored | $\ge 1$ |

An empty run **fails**. Absence of receipts is not evidence of correctness.

### Execution

```swift
let metrics = RouteEvalMetrics.compute(from: receipts)
guard metrics.meetsRouteGates else { /* inspect metrics.violations */ }
print(metrics.markdownSummary)   // paste into the evidence bundle
```

Alongside the gates, the type reports completion latency by route, PCC→on-device fallback counts, and fallback-reason distribution.

### Scope

Scoring is computable from receipts alone, so identical scoring applies to simulator, physical-device, and TestFlight runs. **This makes device evidence checkable; it does not substitute for it.** Producing receipts that represent real Private Cloud Compute execution still requires a signed device — see the `Validate:` items in the Notion engineering roadmap and `Docs/AUDIT/PCC_DYNAMIC_ROUTING_TEST_MATRIX.csv`.

### Novelty counts rephrasing as new information

Measured on device 2026-08-14, Deep Think, eight sessions. Sessions 6, 7 and 8 received contexts
**byte-identical** to sessions 1, 2 and 3, because the chunk pool held only five disjoint windows and
the session loop wrapped. Novelty on those three repeated sessions was reported as **90%, 79% and
77%**.

**The wrap was fixed on 2026-08-18 in `e16a2d3`; the novelty defect it exposed was not.** Window
building now stops when the corpus is exhausted and the session loop runs
`min(maxSessions, distinctWindows)`, so identical contexts are no longer generated — a device
capture shows `Corpus exhausted after 5 distinct window(s)` and the same query dropping from 279.1s
to 80.3s. That removes the *demonstration*, not the cause: novelty is still computed from facts
extracted out of insight text rather than from the evidence shown, so a model restating the same
passage in different words would still register as new information. Do not treat this section as
closed because the repeated sessions are gone.

Novelty is computed from facts extracted out of the session's insight text, not from the evidence it
was shown, so a model restating the same passage in different words registers as new information.
Saturation, which is measured on content similarity, tracked it correctly over the same run: 0%, 0%,
18%, 27%, 32%, 44%, 61%, 70%.

This matters because `noveltyExhausted` is a stop condition in both Deep Think and Maximum, via
`lowNoveltyStreak`. A metric that cannot fall when the input repeats cannot end a chain that is
repeating. Prefer saturation as the convergence signal, which is what
`AgenticPolicyService`'s own comment already concluded from three measured runs, and treat a high
novelty figure late in a chain as unproven rather than as evidence of progress.

`[evidence_level: measured, confidence: high, evidence_source: device capture 2026-08-14, session
contexts 3329/2476/3300 repeated at sessions 6-8 with novelty 90/79/77]`


> **Withdrawn 2026-08-21.** The synthetic-pack row above is kept as history and must not be quoted as a current figure. The run behind it averaged 7 seconds per case, under the 60-second threshold at which `BenchmarkRuns/PROGRESSION.md` flags generation as almost certainly not having run, and the corpus was synthetic and authored alongside its own questions. Its stage table was also measuring the ground-truth defect corrected on 2026-08-11 rather than the pipeline. The QASPER row is the current best evidence, and `BenchmarkRuns/PROGRESSION.md` is the live record.
