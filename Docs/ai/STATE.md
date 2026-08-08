# Current State

Updated: 2026-08-08
Branch/worktree: main, primary checkout
Last verified commit: 408032f

## Objective

None active. The previous objective, wiring per-stage retrieval metrics into `RAGEvalRunner`, is
complete, built and tested. A candidate next objective is under Exact Next Action; it has not been
started or agreed.

## Status

The measurement chain is connected end to end and green. What does **not** exist is a measurement:
no eval run has been executed against an indexed corpus, so there is still no number for this
repository's retrieval quality. The instrument works; nothing has been measured. Those are different
claims and this repository has been burned by collapsing them before.

## Completed

- **Per-stage retrieval metrics are wired in.** Seven stages in pipeline order: `vector`, `lexical`,
  `fusion`, `boosted`, `candidates`, `rerank`, `final`.
- **The pipeline model the instrument was built against was wrong, and is corrected.**
  `RetrievalTraceCollector.Stage` assumed all six original stages were produced inside
  `HybridSearchService`, including `rerank`. That service does not rerank at all; its only mention
  of the reranker is a comment about a score cap. `RAGEngine.rerank` runs later, called from
  `RAGService`. The stages span two layers.
- **A seventh stage, `candidates`, was added**: what hybrid search hands the reranker, after top-K
  truncation and sanitising. Distinct from `boosted` because the truncation between them can drop
  the relevant chunk, and distinct from `final` because reranking reorders what survives. The
  instrument previously recorded its own output as `final`, naming a stage the pipeline had not
  reached and colliding with the real one.
- Ownership follows where the work happens: `HybridSearchService` records the first five in **both**
  search paths; `RAGService` records `rerank` after the rerank block, deliberately outside the
  `if/else` so the stage is still present when a quality mode skips the cross-encoder;
  `queryWithAudit` records `final` from the response's chunks.
- `trace:` threaded `RAGEvalRunner` -> `queryWithAudit` -> `query` -> `queryInternal` ->
  `hybridSearch.search` as a defaulted optional. No existing call site changed.
- `RAGEvalResult.stageMetrics` added as `var` with a default so the synthesised memberwise
  initialiser stays source-compatible. `RAGEvalRunner.aggregateStageMetrics(_:)` rolls up across
  cases, skipping unscored cases rather than counting them as zero.
- `Docs/RETRIEVAL_PIPELINE.md`: Mermaid updated with the capture points, and a false claim withdrawn
  in place with a dated note. It asserted evaluation was "verified against quality targets (e.g.
  Recall@5 >= 0.85) using the native Evaluations harness". That gate was never once met, and
  `AppleEvaluationsBridge.swift` imports only `Foundation` and `FoundationModels`.

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

**No retrieval number exists yet, and producing one needs a corpus.** The harness scores whatever it
retrieves, but `Benchmarks/rag_eval_v1.jsonl`'s `expectedCitations` name documents that must actually
be ingested and indexed for a run to mean anything. `Docs/TestDocuments/` is six small ingestion edge
cases and tests no answer quality, and `rag_validation_sample.json` points at a gitignored PDF.
Verify: pick a container, confirm the 18 cited filenames resolve to indexed documents in it, and only
then run the harness.

**Unverified on device.** Everything above is simulator-verified. Foundation Models needs real
hardware with Apple Intelligence, so any quality-mode comparison from a simulator run describes
retrieval only, not generation.

## Exact Next Action

Produce the first measured retrieval number, or decide explicitly not to yet.

Concretely: ingest a container whose documents cover the 18 `expectedCitations` filenames in
`Benchmarks/rag_eval_v1.jsonl`, run `RAGEvalRunner.run(dataset:ragService:)` against it, then call
`RAGEvalRunner.aggregateStageMetrics(_:)` on the results and read recall@5 per stage in pipeline
order.

What the shape of that output tells you, which is the point of the whole exercise: if recall is
already low at `vector` and `lexical`, first-stage retrieval is the problem and no amount of
reranking will fix it. If it holds through `boosted` and drops at `candidates`, top-K truncation is
too tight. If it survives to `candidates` and drops at `rerank`, the cross-encoder is demoting the
right chunk. A single end-of-pipeline number cannot tell these apart, which is how
`retrievalRecallAt5` reporting exactly `0.0` for its entire existence went unnoticed.
