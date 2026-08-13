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

**This file is the single entry point for "how good is this engine, and how do we know".** Nothing
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

### The three scripts

```bash
python3 scripts/build_external_fixtures.py --check    # verify the external corpus, offline
python3 scripts/build_eval_dataset.py --check         # verify the JSONL matches the manifests
python3 scripts/run_quality_matrix.py --app <app> ... # run a benchmark
python3 scripts/save_benchmark_summary.py <run-dir>   # commit the result so it survives
```

**Always run `save_benchmark_summary.py` and commit its output.** `BenchmarkRuns/` is gitignored, so
a run that is not summarised did not happen as far as the next person is concerned. That was true of
every run this project made before 2026-08-12.

### Two things that will mislead you

1. **Never compare a `tiny_research_suite` number to a `qasper_external_v1` number.** The synthetic
   pack ingests only the documents a case names, so retrieval cannot fail and its stage figures are
   arithmetic. A delta between the packs measures the fixture, not the app.
2. **Never compare a stage figure from before 2026-08-11 to one after.** The ground truth changed,
   not the pipeline.

---


This document describes the formal evaluations framework implemented in OpenIntelligence. This framework is designed to validate the RAG pipeline's behavior, latency, and quality against the target quality gates defined in [WWDC26.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/WWDC26.md).

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
| Synthetic pack, 2026-08-11, standard | 18/20 correct, 0 hallucinated | 20 | reading one correct document and restating it |
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
