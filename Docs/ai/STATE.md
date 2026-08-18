# Current State

Updated: 2026-08-18
Branch/worktree: main (nothing pushed; origin/main is still at 0990a69)
Last verified commit: 002e389

## Objective

**Fix the two defects that make retrieval quality unreadable, in this order.**

1. Deep Think discarding most of its retrieved evidence before synthesis. **Implemented this
   session, not yet device-verified.**
2. The Core AI embedding export reads the wrong output of the embedding model. **Not started.**
   Complete instructions in `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md`.

## Status

Defect 1 is implemented, built, suite-verified, and **committed as `002e389`** on branch
`fix/deep-think-evidence-truncation`. **Nothing is pushed and `main` is untouched.** That commit
also carries the five benchmark-tooling files from the previous session, which had been sitting
uncommitted and undocumented, plus every doc the path-to-doc table requires.

The behavioural claim is unproven. The agentic path has no test coverage, so a green build and a
green suite say only that the change compiles and broke nothing else. Whether Deep Think stops
asserting the evidence is absent can only be answered on hardware.

## Completed this session

- **Root cause was sharper than the previous handoff recorded.** The evidence loss was not uniform.
  `RAGService.executeFullRetrievalPipeline` ends with a Lost-in-the-Middle reorder that appends even
  ranks and inserts odd ranks at the array midpoint. Reproduced directly for n=85: the output begins
  `[1, 3, 5, 7, 9, ...]` and **rank 0 sits at index 42**. `executeSearchStepWithChunks` then renders
  only `chunks.prefix(10)`, which for that array is ranks 1 through 19 and excludes rank 0 outright.
  The highest-scoring chunk was therefore already gone before `prefix(3000)` ran. Fixing the
  character count alone would not have changed the answer.
- **`AgenticOrchestrator.assembleBudgetedEvidence`** packs from chunks rather than the pre-rendered
  string, in `similarityScore` order with array position as a deterministic tiebreak, and logs
  chunks kept, tokens used against budget, and chunks dropped. Warns when the top chunk does not fit.
  The top-ranked chunk is never dropped whole; if it alone overruns the budget it is trimmed at a
  sentence boundary.
- **`evidenceTokenBudget`** derives the budget from the real system prompt, query and output reserve
  via `FoundationModelTokenBudget`, replacing the hardcoded 3000 characters. Rationale for not using
  `DocumentProcessor.countTokens` as the previous handoff specified is in `Docs/ai/DECISIONS.md`
  under 2026-08-17.
- **`executeDirectSynthesis`** takes a new `chunks:` parameter; its three call sites pass
  `allRetrievedChunks`. It now also passes `sourceChunks:`, which it never did. This was mandatory,
  not incidental: citations resolve positionally, so reordering evidence by relevance without
  carrying that order to the response would have traded truncation for citation misattribution.
- **`executeSynthesisStep`** had two stacked cuts. The `prefix(150)` per reasoning step ran before
  the overall budget was consulted and was the more destructive of the two. Per-step allocation is
  now derived from the budget and trimmed at a sentence boundary.
- **Parent document expansion gated** in `RAGService` step 7.5. Siblings are admitted in parent-rank
  order only while projected evidence fits the on-device window. Primary matches are never gated.
- Docs updated in the same turn: `Docs/RETRIEVAL_PIPELINE.md` item 18, Atlas orchestration section,
  `Docs/ai/DECISIONS.md` 2026-08-17, and `CHANGELOG.md` under **`## 5.0`**, not `[Unreleased]`.
  **v5.0 has not shipped yet**, so `## 5.0 - 2026-08-10` is the in-progress section and new work
  belongs in it. Putting entries in `[Unreleased]` makes `ci_scripts/ci_post_clone.sh` hard-fail,
  because a non-empty `[Unreleased]` above a dated heading means CI would stamp an already-cut
  version. Note the router reports `v5.0 (shipped)`; the "shipped" half is a heuristic off the dated
  heading and is wrong. Note also the stale `<!-- next-version: 5.1 -->` marker on line 3, which the
  router reads only when `[Unreleased]` is non-empty and which misreported the target once today.

## Active Constraints

- **Never run a build, test suite, or benchmark while another benchmark is measuring.**
- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/` then build there
  with `-derivedDataPath /private/tmp/oi-dd`. Building in place hangs indefinitely in NSFileCoordinator.
- Compare benchmark runs only with `scripts/compare_benchmark_runs.py`. Raw per-run averages are not
  comparable.
- `AgenticOrchestrator.swift` and `RAGService.swift` are **not** hard-boundary files.
  `WorkspaceSyncService.swift` **is**, and its uncommitted edit was approved by name on 2026-08-17.
- The agentic path has no test coverage. Build-verified and suite-verified is not device-verified.

## Working Set

| File | Why |
|---|---|
| `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift` | The fix. `evidenceTokenBudget:1234`, `assembleBudgetedEvidence:1271`, `executeDirectSynthesis:1366`, `executeSynthesisStep:2571`. Uncommitted. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | Parent expansion gate at step 7.5, line 18119. The Lost-in-the-Middle reorder that caused the ordering defect is step 8 at line 18203. Note there is a second, unrelated "Step 7.5" (verification gates) at line 13271. Uncommitted. |
| `scripts/compile_core_ai_model.py` | The CLS-vs-mean-pooling export. Objective 2. |
| `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md` | Complete instructions for objective 2, written to be executed cold. Read it rather than re-deriving. |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift:7671` | `extractTextWithSpatialOrdering`, the PDF column defect. Blocker 4. |
| `BenchmarkRuns/LEDGER.md` | Every run, what it settled, and where past analysis was wrong. |
| 5 benchmark files (`DebugRAGValidationHarness.swift`, `OpenIntelligenceRuntimePaths.swift`, `EmbeddingService.swift`, `WorkspaceSyncService.swift`, `scripts/run_quality_matrix.py`) | Benchmark provider override and ingestion-queue guard, from the previous session. Now build-verified and suite-verified as part of this session's runs. Commit or revert deliberately. |

## Verification

Run this session, output read:

- `rsync` to `/private/tmp/oi-src`, then `xcodebuild build -scheme OpenIntelligence -destination
  "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-dd`
  → **BUILD SUCCEEDED**, exit 0. Both edited files were force-recompiled via `touch` first, so the
  pass is not an incremental no-op. No new warnings in either file.
- Same invocation with `test` → **236 tests, 0 failures**.
- Same with `-only-testing:OpenIntelligenceTests/VersionHistoryTests`, re-run after the `CHANGELOG.md`
  edit → 3 tests, 0 failures.
- `python3 scripts/secret_scan.py` → no sensitive tokens.
- `scripts/check_icloud_conflicts.sh` → no iCloud damage.
- Lost-in-the-Middle reorder extracted verbatim into a standalone Swift script and run for n=85 →
  `first 10 = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]`, `position of rank 0 = 42`, `rank 0 in prefix(10)
  = false`.

**Not run:** `bash scripts/build_simulator_smoke.sh` (the full build and suite above supersede it),
and any on-device run.

## Blockers / Unknowns

1. **The fix is unproven where it matters.** Closing this needs the device run in Exact Next Action.
   If Deep Think still asserts the evidence is absent, the cause is not truncation and ordering
   alone, and the next thing to inspect is `RAGService.extractRelevantSentences`, which runs
   downstream of everything measured (`Docs/RETRIEVAL_PIPELINE.md` item 13).
2. **Notion roadmap is current as of 2026-08-17.** The row
   [Deep Think reports the evidence is absent in the same answer that cites it](https://app.notion.com/3bf49a74d54f816f92f1f9648de38b1e)
   is now `In Progress`, with a dated note recording the established cause and why it is not
   `Completed`. It moves to `Completed` with `date:Completed:start` only after the device run below
   passes. Four sibling rows added the same day remain `To Do`, one of which
   ([Self-RAG accepted an answer that contradicts itself](https://app.notion.com/3bf49a74d54f81b8a47ef00d9037f08e))
   is blocker 3 here. Use the `notion-roadmap` skill; never answer a roadmap question from memory or
   from `Docs/ROADMAP.md`.
3. **Self-RAG verifies citation resolution, not support.** On the 2026-08-16 device trace it accepted
   Deep Think's "the documents do not provide evidence" answer to `How does dopamine affect social
   behavior?` at `relevance=70%, citations=1/1, confidence=88%`. Minimum viable check: an answer asserting absence
   while carrying resolved citations retrieved for that topic is a detectable contradiction with no
   model call.
4. **`extractTextWithSpatialOrdering` mis-tracks string offsets.** `DocumentProcessor.swift:7721`
   does `wordIndex += wordString.count + 1`, but `split(whereSeparator:)` collapses whitespace runs
   so the `+1` drifts, and `.count` is Characters against a UTF-16 `NSRange`. A guard in
   `PageComplexityAnalyzer` was written, **verified inert, and reverted**.
5. **Retrieval is 21% reproducible.** Caps confidence in any single run, including the one below.
6. **Existing libraries need re-embedding after the objective-2 export fix, and the detector cannot
   see it.** Corrected 2026-08-17: the earlier wording "nothing detects it" was wrong in detail.
   `RAGService.swift:4289` already compares stored `embeddingProviderId`/`embeddingDim` against the
   live service and, on mismatch, reconciles the record, wipes the vector store
   (`invalidateVectorStore(clearStorage: true)`, line 4304) and enqueues a re-embed. Neither the
   shipped tokenizer padding fix nor the coming pooling re-export moves either field, so the branch
   never fires for them. Fix is a fingerprint that moves (provider + dim + tokenizer config +
   pooling mode), **landed before the re-export**, not a new migration.
7. **A library with an empty vector store cannot repair itself.** `reembedDocuments:7086` excludes
   documents whose `fileURL` is in `ingestionItems`; if stale non-terminal queue entries cover them
   all, `documentsToRebuild` empties, line 7098 returns early without throwing, and
   `runPendingSelfHealingRebuilds` logs `Self-healing rebuild completed successfully` and clears the
   banner having rebuilt nothing. Verify from a capture: that line with no preceding
   `🔄 [Reembed] STARTING FULL REBUILD`. Reported from real use; deleting the library was the only
   escape.
8. **Two `prefix(3000)` sites remain, deliberately.** `AgenticOrchestrator.swift:7364`, inside
   `synthesizeClusterInsights` (function at 7307), is live but truncates a generated answer rather
   than retrieved evidence; left pending trace evidence. `AgenticOrchestrator.swift:1563`, inside
   `executeHonestSynthesis` (function at 1550), is dead code with zero callers, as is
   `truncateAtSentence` at 1524. Removal of both dead functions was deferred to a separate change by
   explicit instruction. Note `truncateAtSentence` at 1524 is unused, while the similarly named
   `truncateAtSentenceBoundary` is live and used by the fix; `RAGEngine.swift` has its own separate
   `truncateAtSentence` which is also live.

## Stage 1 diagnosis pass (2026-08-17, complete)

A read-only 21-agent pass diagnosed 10 defect rows, each diagnosis then refuted by an independent
agent. No source was edited. **Read `Docs/Engineering/V50_STAGE1_DIAGNOSIS.md` before starting any
of that work**; raw output in `Docs/AuditArtifacts/DefectDiagnosis/v50_stage1_diagnoses.json`.

Seven causes established, three refuted. What the refutations changed:

- **`fts5-bm25` is half done already.** BM25 column weighting was fixed 2026-08-06; all four sites
  pass nine aligned weights. Only trigram remains, it needs the `SQLiteFullTextService.swift` schema
  (hard boundary) to start at all, and it is unmeasurable at 21% reproducibility.
- **`candidate-cutoff` describes something that cannot happen here.** Needs ≥2,500 chunks and a
  mid/high device tier; the corpus is ~300 and all traces are 181-420. Land the instrumentation, not
  the fix.
- **`nondeterminism` cause is not established**, and `24d3b54` may already have closed it. The 21%
  figure predates that commit. Split into a well-supported Deep Think/Maximum row and an open
  Standard-mode one.
- **`pdf-columns`**: the NSRange offset bug is real and live, but its link to the row's symptom is
  not established, and the proposed fix does not compile. The likelier mechanism is
  `DocumentProcessor.swift:7743-7746` returning non-nil with columns interleaved and no log.
- **`embedding-fingerprint` and `selfheal-noop` are one edit**, not two rows. Separately implemented,
  the second overwrites the first.
- **The proposed fingerprint omits the chunker**, so Batch 4 would invalidate every vector while the
  fingerprint reads healthy — the fingerprint row's own failure mode, inside its own fix.

**All ten diagnosed rows carry their diagnosis in Notion** (added 2026-08-18), so a row opened from
the board is startable without the repo. Each append names the mechanism, the verifier's
corrections, what verifies it, and what blocks it. Only one hard-boundary approval is required by
the whole plan: `SQLiteFullTextService.swift` schema, and only for trigram.

## Exact Next Action

Install the current working tree on device and run **`How does dopamine affect social behavior?`** in
both Standard and Deep Think, then compare against the saved trace in
`Standard+DeepThink+Xcodeconsole.txt` (gitignored, local only).

This still comes first. It is unrelated to the diagnosis pass, it closes the one `In Progress` row,
and it needs nothing but the device. **Batch 0 of the diagnosis plan is the second action** and also
needs no code: re-baseline the 21% figure on current HEAD, since it predates `24d3b54`.

The new log lines are the readout. Look for `[Deep Think] DirectSynthesis evidence budget: kept N/M
chunks, X/Y tokens; dropped ...` and, from retrieval, `Parent expansion capped by budget`.

Three outcomes and what each means:

- **Deep Think answers correctly** → blocker 1 closes. Commit the tree, naming each path explicitly
  from `git status --porcelain` (never `git add .`), then start objective 2 from
  `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md`.
- **Deep Think still asserts the evidence is absent, but the log shows the top chunk was kept** →
  truncation was not the whole cause. Go to `extractRelevantSentences` per blocker 1.
- **The log warns `highest-scoring chunk did not fit the budget`** → the budget is too small for this
  corpus rather than mis-ordered. Raise the output reserve or lower `maxTokens` in
  `executeDirectSynthesis` and re-run.

Retrieval is only 21% reproducible, so run each mode twice before concluding anything from a single
trace.
