# Current State

Updated: 2026-11-12 about 17:30 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 2859d9a5

## Objective

**Ship 5.8 tonight (owner, 2026-11-12), as the last update for a while.** He pulled two fixes into 5.8 and wants
everything that differs from 5.7 shown with measurements: (1) Deep Think's final step reads the passages its passes
cited, not only their notes; (2) a streamed Standard answer with no citation numbers gets them from its own passages.
Parts measured to do nothing stay unless they measurably hurt answers (his words: removal only if "actually fucking up
answers"); the 2026-11-10 rule audit found none that hurt. Then the Xcode Cloud build and submission at his word.

## Status

- **Both fixes measured and kept (2026-11-12, 17:11).** Paired run on 53 of the 158 table questions, Simulator, window
  4,096, each question off and on in one process: Deep Think right 37 to 42 (7 better, 2 worse, p=0.18), median 80 s to
  65 s, answers with no `[S#]` 5 to 1; Standard right 44 to 45 (2 better, 1 worse), the citation change labelled 6 of
  10 streamed answers, every label checked by hand against the saved sources. The decision rule (keep only if no worse)
  passes for both. Recorded in `CHANGELOG.md` 5.8 and `BenchmarkRuns/LEDGER.md`; run folder
  `BenchmarkRuns/2026-11-12-deepthink-source-passages`.
- Found in that run, not fixed: the model sometimes cites as "(S1)", "ROW 3, S1" or "[2]", which the app does not read
  (3 of the 4 Standard answers still unlabelled). Future Backlog candidate.
- The comparison page for the owner (before and after: Deep Think speed on his iPhone, import fidelity, reranker):
  https://claude.ai/artifact/8yGG3yXpwVNSTmQBMu6wfe
- **Ledger gap closed (2026-11-12):** all run folders now have a `BenchmarkRuns/LEDGER.md` entry (35 backfilled, figures
  script-checked against each folder), and `.claude/hooks/session-start.sh` prints how many folders lack one.
- **Embedder licence (owner's rule 1, open):** `all-MiniLM-L6-v2` still ships; its card lists MS MARCO (non-commercial
  terms). The owner said 2026-11-12 to swap it. Granite small english r2 was measured on the Mac 2026-11-09
  (`BenchmarkRuns/2026-11-09-reranker-swap`): 39.0% top 5 against 37.0%, MRR@10 +0.039 (p=0.006), with the Granite
  reranker 50.8% against 48.8%. Not converted to Core ML, not measured in the app; needs a re-embed migration and his
  naming of the provider files (Tier 2). Whether 5.8 waits for it: asked, not answered.
- **Reranker recompiles on most launches (found 2026-11-12):** about 30 slow loads (20 to 130 s) since 2026-11-09, most
  with no install between, and 202 compiled copies (1.47 GB) in the phone's `Library/Caches/.../com.apple.e5rt.e5bundlecache`.
  On the Mac the cache is keyed by the model's path (a copy elsewhere recompiled, 21 s; a touch did not). Proposed:
  copy the model once to a fixed path and load it there; awaiting `PROCEED: IMPLEMENT`. The new build journals
  `newInstall` on each `reranker.load`, which tells whether the bundle path changes between launches.
- Owner asked (open): run the same graded questions on the 5.7 build for a true 5.7-vs-5.8 accuracy number.
- Notion rows (In Progress, v5.8): https://app.notion.com/p/41649a74d54f812183e5efbe07508232 (Deep Think) and
  https://app.notion.com/p/41649a74d54f81b88321c757ff22dfd9 (citations); close on a device check.
- Filed Future Backlog: https://app.notion.com/p/41749a74d54f8195b436f019ac03aede (Chat's import toast counts one short
  when a large file finishes before the rest of its batch; files import fine).

## Active Constraints

- `PROCEED: IMPLEMENT` given for these two fixes (2026-11-12). Hard-boundary files untouched.
- Accuracy first; one `xcodebuild` at a time (the benchmark is one: no builds until it ends); never load his Mac while
  he games (the run script waits for a game to close).
- `scripts/run_quality_matrix.py` has a pre-existing modification that is not part of this work: never stage it.

## Working Set

- `OpenIntelligence/Services/Agentic/SessionEvidencePlan.swift`: `ChainSynthesisEvidence` (labels, ranking, choice,
  fitted notes, budget 1,890 on 4,096 and 3,200 on 8,192).
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator+ReasoningChain.swift`: Deep Think synthesis branch,
  `sourcePassagesSynthesisPrompt`, `readWindowIndices`.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService+QueryAnswer.swift`: `CitationAttribution`, called in
  `retryForMissingCitations`'s streamed branch.
- `OpenIntelligence/Services/RAG/Tuning/RetrievalAblation.swift`: the two switches.
- Tests: `SessionEvidencePlanTests.swift` (`ChainSynthesisEvidenceTests`), `CitationLabelNumberingTests.swift`
  (`CitationAttributionTests`), `EvidenceReachBenchmarkTests.swift` (path "a", streamed Standard, library check).
- `scripts/evidence_reach.py answers`: the paired scorer.
- Docs updated: `CHANGELOG.md` (two [Orchestration] entries with `MEASUREMENT_PENDING` markers to replace with the
  result), `Docs/RETRIEVAL_PIPELINE.md` item 18, Atlas chain paragraph, `Docs/PRIVACY_AND_ROUTING.md` new section.
  Not yet: codemap slice `quality-modes-and-agentic-orchestrator`, `BenchmarkRuns/LEDGER.md`.

## Verification

- `xcodebuild build-for-testing` (patched copy, iOS 27.0 simulator, `/private/tmp/oi-eval-dd`) -> exit 0.
- `test-without-building -only-testing:` ChainSynthesisEvidenceTests, SessionEvidencePlanTests,
  CitationAttributionTests, CitationLabelNumberingTests -> 38 tests, 0 failures.
- Smoke run `LIMIT=2 bash run.sh 0/1` -> answers recorded; the test itself failed on its old import assertion (5 of 7
  counted: the two PDFs over 10 MB take the streamed import and finish after the call returns; fixed in the harness).
- Not built for macOS. Not run on a device.

## Blockers / Unknowns

- `test_repoos_router.py` fails `test_every_task_loads_only_the_small_universal_set` (every-task read set 45,296 bytes against a 40,000 cap; `Docs/ai/ARCHITECTURE.md` is 34,971 of it). It already failed at 1e86b30c (43,515 bytes); trim `ARCHITECTURE.md` or move detail out of it.
- Found in passing, not fixed: `ingestDocuments`' success count leaves out PDFs over 10 MB that are still importing.
  Checked 2026-11-12 [code_verified; the benchmark's 5 of 7 is the reproduction]: the streamed PDF and text imports
  remove their queue item 2 s after Complete, so a large file that finished before the rest of its batch drops out of
  the count. Effect: Chat's "Added N documents" toast is one short; the files import and the question still waits for
  them. Not a 5.8 defect (fails all three tests); filed Future Backlog:
  https://app.notion.com/p/41749a74d54f8195b436f019ac03aede (row "Import count leaves out a large PDF that finished before the rest of its batch").
- About 66 hard-coded character cuts or budgets in the answer path (22 files under Services/Agentic, RAG/Orchestration,
  LLM); offered to the owner as one inventory after 5.8.
- Carried: reranker slow loads to classify with `newInstall`; the Core ML embedder preload is his call.

## Embedder swap plan (owner approved 2026-11-12: "Approved: CoreMLSentenceEmbeddingProvider.swift and CoreAISentenceEmbeddingProvider.swift", "PROCEED: IMPLEMENT", "everything in 5.8")

Model: `ibm-granite/granite-embedding-small-english-r2` rev 2ab6fa8e (Apache 2.0, card: no MS MARCO; 384 dims, CLS pooling,
ModernBERT BPE tokenizer). Converted by `scripts/build_embedding_model.py` (new; two functions len256/len512, CLS + L2 in
graph, palettized, refuses below cosine 0.995 against Hugging Face). Earlier fp16 builds from 2026-11-09 sit in
`/private/tmp/oi-embed/ane/granite_1x*.mlpackage`; HF cache `/Volumes/SD/Scratch/oi-embed-hf`, venv `/private/tmp/oi-embed/venv`.

What the app does today when a library's vectors came from another model (read-only map, file:line in the agent report
summarised here):
- Same provider id and 384 dims, different fingerprint: `RAGService+Storage.swift` `resolveEmbeddingContext` (~1333)
  marks it stale, overwrites the stored fingerprint with the live one, keeps searching the old vectors with new query
  vectors (cross-model, wrong), shows only an orange Documents banner; `librariesNeedingIndexRebuild` is in memory, so
  the warning is lost on relaunch. Must change for the swap.
- Different provider id or dimension: wipes the vector store and queues `enqueuePendingReembed` automatically (~1400).
- Rebuild swaps per document (`RAGService+Deletion.swift` ~738-861); iOS keeps it running with
  `BGContinuedProcessingTaskRequest`; **macOS has nothing** (no `ProcessInfo.beginActivity`, `BackgroundTaskService`
  is a stub there).
- Default provider: Core ML on iOS, **Core AI on macOS 27** (`EmbeddingService.swift` ~619). Core AI's model is
  `EmbeddingModel.bundle` (MiniLM, built with `coreai_torch`, `scripts/compile_core_ai_model.py`); no Granite Core AI
  build exists.
- Vector stores sync through iCloud (`WorkspaceSyncService+Artifacts.swift`, hard boundary): a device still on 5.7
  would read Granite vectors with MiniLM queries, and a rebuild there would sync MiniLM vectors back.
- Import checkpoint embedding cache key has no model term (`EmbeddingService.swift` ~360).
- About 20 user-facing strings say MiniLM (About, EmbeddingInfoSheet, ContainerSettingsSheet and +Search/+NerdStats,
  DocumentDetailsView, DocumentChunk, SemanticSearchView, IntelligenceModeCard, Glossary, SampleDocumentManager);
  `RebuildFalseAlarmTests` pins the MiniLM revision strings.

Steps: (1) build the model and tokenizer, check token ids against Hugging Face; (2) Core ML provider to Granite I/O
(two functions, `embedding` output, no token_type_ids, pad id from the tokenizer), new `modelRevision`/`poolingRecipe`,
fixed-path load via `RerankerModelLocation`; (3) Core AI provider: unavailable (bundle removed) and macOS default to Core
ML, so Mac libraries take the provider-change branch (wipe + automatic rebuild); (4) a model change on the same
provider takes the same wipe + automatic rebuild branch, recorded per device; (5) keep the Mac awake during a rebuild;
(6) a one-time notice that libraries are being updated for the new model; (7) strings, tests, docs; (8) measure in the
app (golden retrieval, tables) before it ships; (9) the iCloud mixed-version case: at least tell users in What's New to
update every device.

## Table checks: diagnosis (2026-11-12, read-only agent; Python copy of the detector in /private/tmp/claude-501/tables-diag/)

51 of 174 table checks fail in `BenchmarkRuns/2026-11-08-extraction-fidelity/after11`. Score with
`python3 scripts/ingestion_unit_tests.py BenchmarkRuns/2026-11-08-extraction-fidelity/checks <run> --compare BenchmarkRuns/2026-11-08-extraction-fidelity/after11 --show 60`
(the checks folder must be the full path). Four general causes, 43 checks:
- A (12, JAMA p5, p7): `TextLayerTableDetector.swift:117-122` ends a region when a line does not overlap the previous
  line; compare with the union of the region's 3-plus-cell lines. `close()` (:111-115) drops a last row's wrapped label.
  Risk: PAH p4 grew into its prose column in the Python copy.
- B (15, BL999 p3, CD004426 p31-33): tables of words fail the 25% numbers rule (:306-311), the prose rule (:36, :82-83),
  the six-short-lines limit (:136-141) and the one-cell continuation rule (:246-253). Accept a captioned ("Table N"),
  3-plus-column, left-aligned region; build rows from the label column. Dropping the numbers rule alone accepted prose.
- C (10-12, PAH p8-9, CD004426 p26/28, JAMA p6): a Vision table with 70% of the word runs' cells wins and hides its words
  from the detector (`StructuredDocumentParser.swift:889-896, 907-913`); run the detector on all words and prefer it
  where it has as many filled cells. Risk: ruled tables (ijms, BST pass 21/21).
- D (4, fbioe p12) and a loss beyond tables: the layout-text path keeps only words inside Vision blocks with confidence
  >= 0.5 (`LayoutAwareExtractor.swift:105, 277`, re-read :136-143); text-layer words outside them never reach storage
  (fbioe p12 lost 43.2, 33.6, 94.5, 0.7; reference pages p15/p16 lost 55 and 62 numbers). Add the coverage pass
  (`uncoveredBlocks`) to `extractWithLayout`, anchored like `textLayerText`.
- Not explained (8, fbioe p8, p11): tables that are images with no text layer; possible fix: OCR picture regions with no
  words under them, in tiles.
Order chosen: D first (rule 4: no lost text), then A, B, C, each checked on the 8 PDFs with the scorer and
`scripts/extraction_fidelity.py` (no regression in the 433 passing checks or number recall).

## Exact Next Action

1. Table fixes, one fidelity run each (`bash BenchmarkRuns/2026-11-12-tables/run_fidelity.sh <label> <commit>`; it waits
   while WoW or League runs, builds that commit on the patched Simulator copy, scores the 515 checks against after11 and
   number recall): `tab-d` at e9eb9992 (layout coverage, D) was queued 2026-11-12 ~20:50; then `tab-a` at a0f24355
   (region overlap, A) plus `PageTextRepairTests`. Keep a fix only if no passing check is lost and number recall does not
   drop; replace `MEASUREMENT_PENDING_LAYOUT_COVERAGE` / `MEASUREMENT_PENDING_TABLE_REGION` in `CHANGELOG.md`. Then
   causes B (captioned tables of words) and C (prefer the text-layer table over Vision's) from the diagnosis above.
2. Only after the owner says GO: `bash BenchmarkRuns/2026-11-12-full-suite/run_all.sh` (rsync the tree into
   `/private/tmp/oi-eval-src` and re-run `scripts/sim_model_copy.py` on it first). Granite ships only if no worse than
   MiniLM in the app; replace `MEASUREMENT_PENDING_EMBEDDER`.
3. Done 2026-11-12 on the owner's iPhone: Granite rebuild finished (37 documents healthy); reranker and embedder loaded
   in 1.6 s on a launch with no install; 1,793 MB of old compiled models removed.
