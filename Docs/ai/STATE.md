# Current State

Updated: 2026-11-12 about 17:30 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 1e86b30c

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

## Exact Next Action

Build the committed tree to the owner's iPhone (device build from a copy outside `~/Documents`, `MARKETING_VERSION` 5.8,
`-derivedDataPath` outside `~/Documents`; ids in auto memory `building-to-gunnars-iphone.md`), then a macOS build.
Then, at his word, the Xcode Cloud build and submission (tick "Reset rating", `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15).
