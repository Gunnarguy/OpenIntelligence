# Current State

Updated: 2026-08-08
Branch/worktree: main, primary checkout
Last verified commit: 6e18a3e

## Objective

None active. Retrieval measurement is wired, correct and committed. The next arc is ingestion, which
is where the evidence now points and where nothing is measured.

## Status

18/20 on the committed fixture, `final` R@5 1.00, MRR@10 0.94, 0 hallucinations on 2 negative
controls. **That number describes 25 markdown files and nothing else.** The app claims 20 formats and
the benchmark exercises one, so PDF parsing, OCR, Office/iWork extraction and A/V transcription have
no automated coverage at all.

## Completed

- Per-stage retrieval instrumentation, 7 stages, wired from `RAGEvalRunner` through
  `queryWithAudit` to `HybridSearchService`, and emitted by the headless harness as a
  `STAGE METRICS` block plus a `STAGE SOURCES` block so any figure can be recomputed by hand.
- Seven metric defects fixed. The two that produced impossible numbers: chunk-level relevance scored
  against document-level ground truth made nDCG@5 report **2.131** on a metric bounded at 1, and a
  `min(1.0, ...)` clamp hid the same unit mismatch in recall. Also: precision now divides by `k`
  (trec_eval `P`, not `set_P`), MRR is cut at 10 so stages of different lengths compare, and
  `retrievalRecallAt5` is scored at depth 5 rather than over every retrieved chunk.
- Determinism: score ties now break on chunk id at six sites. `sorted(by:)` is unstable and several
  lists come from a `Dictionary` with per-process randomised order, so ranks moved between identical
  runs. The 27 runs in `BenchmarkRuns/` predate this and are not comparable to each other.
- Three grader defects fixed, all of which scored correct behaviour as failure: the verification
  banner "could not be strictly verified" tripped the abstention regex; "not stated" was missing from
  that regex, scoring a correct refusal on a negative control as a hallucination; and accuracy
  divided by cases that answered rather than cases attempted.
- Negative controls are no longer retrieval-scored; abstention is reported as its own count.
- Provenance per run: commit, dirty flag, dataset and corpus hashes, OS/Xcode/hardware, launch
  context, and PCC availability captured from stderr.
- `RAGService` extraction fallback: sentence extraction that matches nothing no longer discards the
  retrieved chunks. `exact_capex` had the strongest retrieval in the run (topSim 1.317, correct
  document at rank 1 in all five slots) and received **zero characters of context**, then fell back
  to direct LLM chat with no RAG at all. That fallback is the more dangerous half: it answers from
  model priors while the user believes the app is reading their documents.

## Reverted, deliberately

A rewrite of `buildSemanticTableSummary` that reordered the table summary chunk to lead with data.
The diagnosis was right — the chunk opened with "…describes table." and the model echoed it — but the
remedy made the summary a near-duplicate of the real `TABLE:` chunk, so MMR dropped the table as
redundant. Table documents lost **70%** of retrieved chunk text and one case moved from echoing the
preamble to fabricating "7 days" against a ground truth of 7,500 miles. Caught by the owner noticing
character counts in the running app, not by the benchmark, which read 16/20 before and after.

## Active Constraints

- `RetrievalTraceCollector` must stay in `Services/RAG/Retrieval/`: `OpenIntelligenceEngine`'s
  synchronized groups include `Services/RAG` but not `Services/Evaluation`. See
  [DECISIONS.md](DECISIONS.md).
- One collector per query. It is explicitly not a shared sink; retrieval runs concurrent child tasks.
- Route `retrieval_tuning_change`. `Docs/RETRIEVAL_PIPELINE.md` and a `**[Retrieval]**` CHANGELOG
  entry are part of any retrieval task, not a follow-up.

## Working Set

- `OpenIntelligence/Services/RAG/Retrieval/RetrievalTraceCollector.swift`: the collector and `Stage`.
- `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift:283-300, 1075-1090`: capture.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:8380-8445` threaded signatures,
  `:9453` the search call, `:9900` the `rerank` capture.
- `OpenIntelligence/Services/Evaluation/RAGEvalRunner.swift`: collector construction and scoring.
- `OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift`: `RetrievalStageEvaluator`.
- `Benchmarks/rag_eval_v1.jsonl`: 20 cases, 18 with `expectedCitations`, all with
  `groundTruthChunkIds: null`.

## Verification

- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**, 0 errors, codesigned. 2026-08-08.
- `xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-build`
  -> **173 tests, 0 failures**, `** TEST SUCCEEDED **`. 2026-08-08.
- That simulator UDID is confirmed present and available, so the RUNBOOK entry is verified rather
  than recorded.
- The two compiler warnings in `RAGService.swift` are at lines 1770 and 6581, outside every region
  touched here, and predate this work.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 24 of 24.
- `python3 scripts/secret_scan.py` -> clean.

## Blockers / Unknowns

**`RAGEvalRunner` has zero call sites. It is unreachable, so it cannot be run at all.**
`grep -rn RAGEvalRunner --include=*.swift OpenIntelligence/ OpenIntelligenceTests/` returns only
comments. The type is correct, built and tested, and nothing invokes it. This is the real blocker on
producing a retrieval number, and it is a missing entry point rather than missing data.

**Correction, 2026-08-08:** an earlier version of this file said a number was "blocked on corpus"
because the cited documents were not committed. That was wrong. The corpus is committed at
`Benchmarks/ResearchFixtures/tiny_research_suite/fixtures/`, 29 files, and all **18 of 18**
`expectedCitations` filenames resolve to real fixture files. `rag_eval_v1.jsonl` is generated from
that suite's `manifest.json` by `scripts/build_eval_dataset.py`, as its own header states. The
`Docs/TestDocuments/` and gitignored-PDF observations were about unrelated fixtures.

**The harness that works is a different mechanism, and it does not measure retrieval.**
`OpenIntelligence/App/DebugRAGValidationHarness.swift` runs headlessly, ingests the fixture corpus,
runs the cases and prints a text report; `scripts/run_quality_matrix.py` drives a built **macOS**
binary and parses that output. It has produced 27 runs under `BenchmarkRuns/`. The most recent,
`20260730-091821-matrix`, measured answer accuracy per quality mode, not retrieval recall, and
recorded that deep-think and maximum produced no answer on most cases headlessly.

**Unverified on device.** Everything above is simulator-verified. Foundation Models needs real
hardware with Apple Intelligence, so any quality-mode comparison from a simulator run describes
retrieval only, not generation.

## Exact Next Action

Give `RAGEvalRunner` an entry point, then run it. It has no caller, so there is nothing to invoke.

The cheapest correct route reuses what already works rather than building a second harness:
`DebugRAGValidationHarness` already runs headlessly, already ingests
`Benchmarks/ResearchFixtures/tiny_research_suite/fixtures/`, and already prints a report that
`scripts/run_quality_matrix.py` parses. Attach a `RetrievalTraceCollector` there, score it with
`RetrievalStageEvaluator`, emit a `STAGE METRICS` block beside the existing `ANSWER` block, and
teach the Python side to parse it.

Note the run needs a **macOS** Debug build, not the simulator: that is what the 27 existing runs in
`BenchmarkRuns/` used, and Foundation Models needs real hardware for generation. Retrieval stages are
measurable regardless of whether generation succeeds, which is the point of scoring them separately.

What the shape of that output tells you, which is the point of the whole exercise: if recall is
already low at `vector` and `lexical`, first-stage retrieval is the problem and no amount of
reranking will fix it. If it holds through `boosted` and drops at `candidates`, top-K truncation is
too tight. If it survives to `candidates` and drops at `rerank`, the cross-encoder is demoting the
right chunk. A single end-of-pipeline number cannot tell these apart, which is how
`retrievalRecallAt5` reporting exactly `0.0` for its entire existence went unnoticed.
