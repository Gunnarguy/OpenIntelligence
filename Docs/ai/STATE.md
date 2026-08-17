# Current State

Updated: 2026-08-17
Branch/worktree: main
Last verified commit: 342447d

## Objective

**Fix the two defects that make retrieval quality unreadable, in this order.** Both are single
functions. Both are measured or code-verified, not suspected.

1. `AgenticOrchestrator.swift:1215` throws away 96% of retrieved evidence before the model sees it.
2. The Core AI embedding export reads the wrong output of the embedding model.

## Status

The embedding investigation is **finished and answered**. A 25-case benchmark settled it. The device
run that followed found three new defects, one of which is larger than anything the benchmark
measured. Nothing is half-edited; the working tree carries only benchmark tooling.

## Completed this session

- **The pooling question is settled.** `BenchmarkRuns/coreml-provider`, 25/25, paired against
  `tokfix` on 21 comparable cases: `vector r@1` **0.000 → 0.571**, 12 better and 0 worse, exact
  two-sided sign test **p = 0.0005**. The `lexical` control is identical case for case, so the runs
  are comparable. **MiniLM was never weak; it was being read at the CLS position by a model trained
  for mean pooling.** Full verdict and caveats in `BenchmarkRuns/LEDGER.md`.
- `scripts/compare_benchmark_runs.py` — pairs runs by `case_id`, names excluded cases, prints
  per-case flips and an exact sign test. Written because comparing each run against its own case set
  produced a false alarm that the control had moved.
- Three device-found defects filed in Notion, all `To Do`, `High`, `v5.0`.
- `MARKETING_VERSION` set to 5.0 so local Xcode builds stop reporting 4.9. **Not a fix** —
  `ci_scripts/ci_post_clone.sh:79` stamps the version from `CHANGELOG.md` at Xcode Cloud build time,
  so shipped builds were always correct. Only local builds were stale.

## Active Constraints

- **Never run a build, test suite, or benchmark while another benchmark is measuring.** Doing it
  cost 20 minutes of misdiagnosis on 2026-08-15 and again today.
- Compare benchmark runs only with `scripts/compare_benchmark_runs.py`. Raw per-run averages are
  not comparable.
- `AgenticOrchestrator.swift` is **not** a hard-boundary file. `FoundationModelRoutePolicy.swift`,
  `FoundationModelSessionFactory.swift`, `RAGAppIntents.swift` and `EngineSDKCompatibility.swift`
  are, and none are needed for the work below.
- The agentic path has no test coverage. Build-verified and suite-verified is not device-verified,
  and saying so is part of the change.

## Working Set

| File | Why |
|---|---|
| `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift:1215` | The truncation. Priority 1. |
| `scripts/compile_core_ai_model.py` | The CLS-vs-mean-pooling export. Priority 2. |
| `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md` | Complete instructions for priority 2, written to be executed cold. Read it rather than re-deriving. |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift:7671` | `extractTextWithSpatialOrdering`, the PDF column defect. Priority 3. |
| `BenchmarkRuns/LEDGER.md` | Every run, what it tested, what it settled, and where the analysis was wrong. |
| 5 uncommitted files | Benchmark provider override and queue guard. Build-verified, never committed. Commit or revert deliberately; do not leave them drifting. |

## Verification

- `python3 scripts/compare_benchmark_runs.py BenchmarkRuns/tokfix BenchmarkRuns/coreml-provider`
  → 21 paired, `vector r@1` 0.000 → 0.571, 12 better / 0 worse, p = 0.0005, control identical.
- `plutil -lint OpenIntelligence.xcodeproj/project.pbxproj` → OK after the version change.
- Device log `Standard+DeepThink+Xcodeconsole.txt` (gitignored, local only) → `maxTokens=421/430`,
  so **the tokenizer fix is live on device**; `coreai_sentence_embedding` ×10, so **the device runs
  the broken CLS embedder**.
- **Not run this session:** `xcodebuild test`, `scripts/build_simulator_smoke.sh`. The working tree
  has not been compiled since the version bump.

## Blockers / Unknowns

1. **Deep Think discards 96% of its evidence.** `AgenticOrchestrator.swift:1215` is
   `String(searchResults.prefix(3000))`. The device trace shows `Context expanded │ 18 → 85 chunks`
   and `85 chunks ready for synthesis`; 85 chunks is roughly 84,000 characters, cut to 3,000, with
   no log line and no guarantee the highest-ranked chunk survives. **Parent doc expansion actively
   harms Deep Think** by inflating context 4.7x immediately before a fixed-size cut. This explains
   the observed inversion: on `How does dopamine affect social behavior?` Deep Think answered "the
   documents do not provide evidence" in 202.7s while Standard, which assembled `3 chunks • 522
   words` and fit entirely inside the budget, answered correctly in 6.7s. **Ranking work is
   largely wasted until this is fixed.**
2. **Self-RAG verifies citation resolution, not support.** It accepted the above at
   `relevance=70%, citations=1/1, confidence=88%`. Real Self-RAG critiques whether each claim is
   *supported* by the cited passage. Minimum viable check: an answer asserting absence while
   carrying resolved citations retrieved for that topic is a detectable contradiction with no model
   call.
3. **`extractTextWithSpatialOrdering` mis-tracks string offsets.**
   `DocumentProcessor.swift:7720` does `wordIndex += wordString.count + 1`, but
   `split(whereSeparator:)` collapses runs of whitespace so the `+1` drifts on every double space
   and newline, and `.count` is Characters against a UTF-16 `NSRange`. `page.selection(for:)` then
   returns bounds for different text than the word being placed, so columns interleave. Confirmed
   in the device log: `direct: 2 pages (25%)`, `spatialText: 0 pages`, printed one line after the
   app announced "Multi-column layouts will be detected and read in proper order". A guard in
   `PageComplexityAnalyzer` was written, **verified inert, and reverted** — `needsVision` is false
   for `.directText` and `.spatialText` alike, so reclassifying changes nothing.
4. **Retrieval is 21% reproducible.** Unchanged. Caps confidence in any single run.
5. **Existing libraries need re-embedding** after the export fix, and nothing detects it.
   `KnowledgeContainer` persists only `embeddingProviderId` and `embeddingDim`, neither of which
   moves.

## Exact Next Action

Fix `AgenticOrchestrator.swift:1215`. Replace `String(searchResults.prefix(3000))` with a budget
computed from real token counts, filled in rank order, that **logs what it dropped**:

- Use `DocumentProcessor.countTokens` (now trustworthy — the padding defect was fixed in `2753d15`)
  rather than a chars-per-token guess.
- Fill highest-ranked chunk first and stop at the budget, so truncation removes the least relevant
  evidence rather than whatever sorts last.
- Emit one line naming how many chunks and tokens were dropped. Silent truncation across fourteen
  stages is the class of defect this pipeline keeps producing.
- Then re-run the identical device query, `How does dopamine affect social behavior?`, in both
  Standard and Deep Think, and compare against the saved trace. **Deep Think must stop asserting the
  evidence is absent.** If it still does, the cause is not truncation alone and blocker 1 stays open.

Consider whether parent doc expansion should run at all when the budget cannot hold its output.
