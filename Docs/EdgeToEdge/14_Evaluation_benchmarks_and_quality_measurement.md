# Module 14. Evaluation, benchmarks, and quality measurement

Thirty-one concepts. Measuring whether any of this works, and the two lessons that made most earlier figures unusable.

## The ladder

**Like you're five.** To know if the librarian is good, you give her a test with questions you already know the answers to, and count how often she finds the right card and gives the right answer. And sometimes you hide the answer in the middle of a pile to see if she finds it there.

**Like an idiot.** There's a harness that ingests test documents, runs questions through the real engine, records what every retrieval stage returned, and scores it: did the right chunk get found, how high did it rank, was the answer right, did the app abstain when it should have. Runs are recorded in a ledger. Baselines are frozen so changes can be compared. External question sets are used because questions you write yourself are too easy.

**Like less of an idiot.** Retrieval metrics: recall at k, precision at k, mean reciprocal rank, nDCG, and stage survival (did the correct chunk make it from vector or lexical through fusion, boosts, rerank and final). Answer metrics: exact match, token F1, hallucination rate, abstention accuracy, error rate. Route metrics: invariants on the execution receipt (completed route was attempted, fallback is attributed, denied or unknown cloud fails closed). Paired comparisons and an exact sign test say whether a change is consistent or driven by outliers.

**Average Joe.** Two lessons dominate everything here. Chunk-level retrieval was once scored against document-level ground truth, so multiple chunks from one relevant document each counted as a hit and nDCG reported 2.131, above its own ceiling. And retrieval is nondeterministic: two runs of one build return different chunks for one question, so no A/B is trustworthy until that's fixed. There's a third, human lesson: twice, one real document on real hardware found what the whole synthetic suite missed.

**Dot-connector.** Evaluation is the only place the app's numbers become claims you can defend. The ledger is the only citable source for a figure. Run directories are never deleted because they're gitignored and the raw results file is the only evidence behind whatever the ledger says; three were lost once. And the evidence-level vocabulary (code-verified, test-verified, simulator-verified, device-verified, measured, inferred) exists so that "it's in the source" is never confused with "it works on a phone."

**Expert.** `RAGEvalRunner` ingests fixtures, runs queries with `RetrievalTraceCollector` attached, aggregates through `RAGEvalMetrics` and `RetrievalStageMetrics`, writes with `RAGEvalReportWriter`. Datasets: `RAGEvalDataset` with schema validation; the tiny research suite (exact lookup, missing information, multi-hop, rank retrieval, lost-in-the-middle) for fast regression; QASPER external fixtures with distractor papers to counter synthetic-fixture bias. `RouteEvalMetrics` checks completed-route attestation, fallback attribution and the fail-closed invariant against receipts. Credited relevance maps chunks to ground truth with accepted equivalence so parent expansion isn't penalised. Scripts: `run_quality_matrix.py`, `compare_benchmark_runs.py`, `sweep_fusion_weight.py`. Ledger: `BenchmarkRuns/LEDGER.md` and `PROGRESSION.md`; baselines under `Benchmarks/baselines`. Device runs through `scripts/run_device_tests.sh`.

**Expert's expert.** The benchmark harness runs the macOS Debug build and writes into the real app library unless pointed elsewhere, which polluted the owner's documents once; aim it at the simulator. A hung app process on timeout used to poison every later case because the kill pattern matched the harness's own command line. The `VersionHistoryTests` make the user changelog a build input, so a doc edit mid-run breaks the run. None of these are pipeline facts; all of them are why benchmark numbers in this repo carry provenance.

## Every concept

### Abstention accuracy (Support, verified), Answer accuracy (Support, verified), Error rate (Support, verified), Exact match (Support, verified), Hallucination rate (Support, verified), Token F1 (Support, verified)
- **Idiot:** the scorecard: right answers, right refusals, crashes, exact hits, made-up stuff, partial credit.
- **Dot-connector:** always answering and always refusing are both bad; exact match suits short lookups; F1 gives credit for right-but-reworded; hallucination rate is reported beside accuracy because aggressive answering raises one and worsens the other; errors are counted separately so infrastructure failures don't hide in quality.
- **Expert:** `RAGEvalMetrics`.

### Benchmark baseline (Support, verified) and Benchmark ledger (Support, verified)
- **Idiot:** the frozen reference, and the logbook.
- **Dot-connector:** without a baseline, plausible-looking runs hide regressions; the ledger outlives the machine.
- **Expert:** `Benchmarks/baselines`; `BenchmarkRuns/LEDGER.md`, `PROGRESSION.md`. Never delete a run directory.

### Completed-route attestation (Support, verified), Fail-closed route invariant (Support, verified), Fallback attribution invariant (Support, verified), Route invariant (Support, verified)
- **Idiot:** the badge has to be backed by a receipt.
- **Dot-connector:** a completed target must appear in the attempt chain with success; a different completed target needs a fallback reason; denied or unknown cloud never completes on PCC.
- **Expert:** `RouteEvalMetrics` over receipts in route benchmarks and tests.

### Credited relevance (Support, verified) and Stage survival (Support, verified)
- **Idiot:** did the right card make it through every stage, counting near-misses fairly.
- **Dot-connector:** chunk boundaries and parent expansion produce relevant evidence without the exact ID; a stage can keep counts while dropping the only correct item.
- **Expert:** `RetrievalStageMetrics` over `RetrievalTraceCollector` outputs in pipeline order.

### Distractor document (Support, verified), QASPER fixture (Support, verified), Synthetic fixture bias (Support, documented), Tiny research suite (Support, verified)
- **Idiot:** hard tests, with decoys, written by someone else.
- **Dot-connector:** a corpus with only the answer document measures nothing; self-authored questions flatter the engine; the tiny suite is fast regression, not accuracy estimation.
- **Expert:** `Benchmarks/ResearchFixtures/qasper_external_v1`, `tiny_research_suite`, `rag_eval_qasper_v1.jsonl`.

### Evaluation case (Support, verified), Evaluation dataset (Support, verified), Evaluation report writer (Support, verified), RAGEvalRunner (Support, verified)
- **Idiot:** one question, the collection, the report, the machine that runs them.
- **Dot-connector:** explicit ground truth over anecdotes; versioned datasets prevent cherry-picking; durable reports for later audit.
- **Expert:** `RAGEvalCase`, `RAGEvalDataset`, `RAGEvalReportWriter`, `RAGEvalRunner`.

### Evidence level (Support, documented)
- **Idiot:** how do we know this is true?
- **Dot-connector:** code-verified, test-verified, simulator-verified, device-verified, measured, inferred, unverified; source proves implementation, not runtime behaviour.
- **Expert:** attached to documentation and audit conclusions; `CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`.

### Exact sign test (Support, documented) and Paired comparison (Support, verified)
- **Idiot:** did A beat B case by case, not just on average?
- **Dot-connector:** wins, losses and ties show whether an improvement is consistent or a few outliers; the sign test needs no normality assumption.
- **Expert:** `scripts/compare_benchmark_runs.py`; `Docs/EVALS.md`.

### Mean reciprocal rank (Support, verified), Normalized discounted cumulative gain (Support, verified), Precision at k (Support, verified), Recall at k (Support, verified)
- **Idiot:** how soon the first good card shows up, how well the whole order is, how clean the top is, how much of the good stuff was found.
- **Dot-connector:** recall measures finding; precision measures not wasting context; MRR first hit; nDCG the whole ranking with graded relevance. Score chunks against chunk-level truth or you get 2.131.
- **Expert:** `RetrievalStageMetrics`, computed per stage from trace identities.

### Physical-device verification (Support, verified)
- **Idiot:** try it on a real phone.
- **Dot-connector:** Apple Intelligence, thermal, Neural Engine scheduling, PCC, background processing and memory pressure differ from the simulator; the final evidence tier.
- **Expert:** `scripts/run_device_tests.sh`; `Docs/AuditArtifacts/Implementation`.

### Quality matrix (Support, verified)
- **Idiot:** a grid of modes and settings, all scored.
- **Dot-connector:** regressions are interactions, not single settings.
- **Expert:** `scripts/run_quality_matrix.py`; results under `Docs/AuditArtifacts/Benchmarks`.
