# Current State

Updated: 2026-08-08
Branch/worktree: main, primary checkout
Last verified commit: 0bced4c

## Objective

None active. The retrieval measurement arc and the ingestion defect sweep are both complete,
committed and pushed. The next objective is under Exact Next Action; it has not been started.

## Status

Two things landed today and they point in opposite directions.

**Retrieval is strong and now genuinely measured.** 18/20 on the committed fixture, `final` R@5
1.00, MRR@10 0.94, 0 hallucinations on 2 negative controls. Dense retrieval returns the correct
document at rank 1 on every answerable case.

**Ingestion had five silent-corruption defects, now fixed but unmeasured.** Each let extraction do
its work and then discarded the result while reporting success. None was visible to any test,
because the benchmark corpus is 25 markdown files against 20 advertised formats.

The honest summary: the instrument is correct, retrieval is good on easy input, and the input path
customers actually use has no coverage at all.

## Completed

**Measurement — commits `493d577`, `6e18a3e`, `6e5937e`**
- Seven-stage instrumentation: `vector`, `lexical`, `fusion`, `boosted`, `candidates`, `rerank`,
  `final`. Threaded from `RAGEvalRunner` through `queryWithAudit` to `HybridSearchService`. The
  harness emits `STAGE METRICS` and `STAGE SOURCES` blocks so any figure can be recomputed by hand.
- Seven metric defects fixed. The two that produced impossible numbers: chunk-level relevance scored
  against document-level ground truth made **nDCG@5 report 2.131** on a metric bounded at 1, and a
  `min(1.0, ...)` clamp hid the same unit mismatch in recall. Precision now divides by `k`
  (`trec_eval`'s `P`, not `set_P`), MRR is cut at 10, `retrievalRecallAt5` is scored at depth 5.
- Determinism: score ties break on chunk id at six sites. `sorted(by:)` is unstable and several
  lists come from a `Dictionary` with per-process randomised order.
- Three grader defects fixed, all of which scored correct behaviour as failure.
- Provenance per run: commit, dirty flag, corpus hashes, OS/Xcode/hardware, PCC availability.
- `RAGService` extraction fallback: extraction matching nothing no longer discards the retrieved
  chunks and falls through to no-RAG chat.

**Ingestion — commits `924a910`, `0bced4c`**
- Images and camera captures no longer collapse to a single line. Both joined OCR lines with a
  space; the camera did it immediately after sorting into reading order.
- `effectiveContent` merges instead of choosing. A low-quality page that captured one table kept the
  table and discarded the recovered prose the parser had already re-OCR'd for that purpose.
- `usedStructuredParsing` reflects whether structured extraction produced anything, not just tables
  and lists. A diagram-heavy PDF was discarding every figure chunk after paying ANE time for it.
- **All three lanes now use `RecognizeDocumentsRequest`**: PDF import
  (`DocumentProcessor.swift:4335`), image import (`:7358`), camera capture
  (`CameraManager.swift:548`). Previously PDF only.
- API currency verified against Apple docs rather than assumed: `RecognizeDocumentsRequest` is
  current as of WWDC25 / iOS 26, nothing supersedes it. Remaining `VNRecognizeTextRequest` usages
  are the documented no-document fallback plus Siri paths, and are correct rather than debt.

**Reverted deliberately:** a rewrite of `buildSemanticTableSummary`. Right diagnosis, wrong remedy —
it made the summary a near-duplicate of the real `TABLE:` chunk, MMR then dropped the table as
redundant, table documents lost **70%** of retrieved text, and one case went from echoing a preamble
to fabricating "7 days" against a ground truth of 7,500 miles. The benchmark read 16/20 before and
after. It was caught only because the owner noticed character counts in the running app.

## Active Constraints

- **Do not change chunk shape without format-diverse fixtures.** See the revert above. This is the
  most important line in this file.
- Route `retrieval_tuning_change` or `ingestion_ocr_change`. `Docs/RETRIEVAL_PIPELINE.md` or
  `Docs/INGESTION_PIPELINE.md` plus a tagged `CHANGELOG.md` entry are part of the task, not a
  follow-up.
- `RetrievalTraceCollector` must stay in `Services/RAG/Retrieval/`: `OpenIntelligenceEngine`'s
  synchronized groups include `Services/RAG` but not `Services/Evaluation`.
- The benchmark needs a **macOS Debug** build and an Aqua session. PCC is unavailable from an
  agent-spawned shell, so only `--pcc deny` runs are valid there. See `Docs/ai/RUNBOOK.md`.

## Working Set

- `Docs/ai/RUNBOOK.md` — how to build and run the benchmark, with the environment traps.
- `scripts/run_quality_matrix.py` — harness driver, grader, aggregation, provenance.
- `OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift` — metric math and relevance
  judge. 29 unit tests.
- `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` — extraction dispatch;
  `extractTextFromImage` ~7319, structured PDF result ~4933.
- `OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift` — `parsePageImage`
  at 601, `effectiveContent` ~500.
- `Benchmarks/ResearchFixtures/tiny_research_suite/` — the 25 markdown fixtures and `manifest.json`.
- `BenchmarkRuns/20260808-retrieval-stages/` — the run these numbers come from.

## Verification

- `bash scripts/build_simulator_smoke.sh` -> BUILD SUCCEEDED. macOS Debug also clean.
- iOS suite -> **181 tests, 0 failures**. 2026-08-08.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 24 of 24.
- `python3 scripts/secret_scan.py` -> clean.
- Benchmark, 20 cases, standard, PCC denied -> 18/20; `final` R@5 1.00, MRR@10 0.94.
- **Not verified:** all five ingestion fixes. Correct on inspection and the build passes, but no
  automated run exercises them.

## Blockers / Unknowns

**The benchmark exercises 1 of 20 advertised formats.** Every fixture is markdown, so PDF parsing,
OCR, Office and iWork extraction and A/V transcription have no coverage. Not theoretical: today a
plausible ingestion change destroyed 70% of retrieved table text while the score held at 16/20.
Notion row: *The benchmark exercises 1 of 20 advertised formats*.

**Unknown: whether iWork and A/V extraction work at all.** `pages`, `numbers`, `key`, `mp3`, `wav`,
`mp4`, `mov` are advertised. Nobody has confirmed the extractors produce usable text rather than
failing silently or falling through to a generic reader.
Verify: ingest one file of each type and read the extracted text.

**Unknown: what 2026 offers that this pipeline lacks.** A survey of document parsing, chunking,
lexical retrieval and agentic RAG was started and killed to save budget. The chunker is still
sentence-similarity boundary detection, a 2023-era technique. `structure_type` reaches FTS5 as
`UNINDEXED`, so chunk modality is computed and then unsearchable.

**Unconfirmed:** `multi_hop_project_m5` moved 2/2 required patterns to 1/2 during the table-summary
experiment. That change was reverted, so it should be gone, but nobody re-checked after the revert.
Verify: rerun the suite and compare that case against `BenchmarkRuns/20260808-retrieval-stages`.

## Exact Next Action

Build the format-diverse ingestion fixture set. It gates every other ingestion change and it is the
only thing that would have caught today's 70% loss.

Add to `Benchmarks/` a small committed set with known-correct expected extraction, and assert on
**extraction** rather than on answers: does row/column association survive, does the character count
land within tolerance. That runs in seconds as a unit test, not as a benchmark.

| Fixture | Catches |
|---|---|
| Text-layer PDF with a table | table structure through the PDFKit path |
| Scanned PDF with a table | the OCR path and `RecognizeDocumentsRequest` |
| PDF with figures, no tables | the `usedStructuredParsing` defect fixed today |
| Partially-legible scan | the `effectiveContent` merge fixed today |
| PNG photo of a table | the image lane and the one-line collapse fixed today |
| `.docx` with a table, `.xlsx`, `.csv` | Office extraction |
| `.pages` or `.numbers` | iWork — may prove impossible, which is itself worth knowing |

Then rerun the 20-case suite to confirm no retrieval regression. **Expect that number not to move**;
it is all markdown, which is the entire point.

After that, and not before: the real evaluation corpus (WixQA MIT, QASPER CC BY 4.0,
LegalBench-RAG-mini — roughly 1,000 queries, all commercially licensed) and the FTS5
`structure_type` indexing fix. Both are Notion rows.
