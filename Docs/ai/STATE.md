# Current State

Updated: 2026-11-08 about 11:40 PT (5.8 open. Overnight "go 10x" pass committed in f7c1b484; the 2026-11-08 morning
ingestion-fidelity pass, measured on 8 real PDFs, is the second Status row.)
Branch/worktree: `main`, primary checkout
Last verified commit: f7c1b484

## Objective

**Finish 5.8 so the owner can move on to more behind the paywall** (his words 2026-11-03). The board is 5.8 and Future
Backlog only. What remains is his checks on the iPhone and Mac (the device pass), then shipping 5.8 when he says so.

## Status

| What | Where it stands |
|---|---|
| Overnight 2026-11-07/08 (his "PROCEED: IMPLEMENT", "go 10x", "universal, not siloed"; he named `WorkspaceSyncService+LibrarySync.swift`) | Probe: "How much DHA is recommended?" (Library 8, paper `ijms-21-03624-2.pdf`, Table 1, DHA row "1-2 g") answered "1-28" / another row's "100-200 mg/15-30 g". Fixed at the general layer, each with tests (CHANGELOG `## 5.8`, 2026-11-07/08 entries): (1) `AnswerResponsivenessJudge` (on-device guided generation: full/partial/none, measured over 160 cases on the Mac in `BenchmarkRuns/2026-11-07-responsiveness/README.md`), Standard rewrites a non-full answer once (`RAGService+AnswerResponsiveness.swift`), extracted values judged none are set aside at all five lock sites, `answers:<verdict>` in the gating string, `VerificationOutcome` reads it; (2) tables: `RAGService.withTablesForSummaries` swaps a retrieved table summary for its table in Standard and every Deep Think search (fixes existing libraries), summaries list every row, rows name their columns (`namedRowCells`; highlighter strips them, `PassageLocator.withoutImportLabels`), `isPageFurnitureLabel` and `runningLineKeys`/`isRunningElement` keep page furniture out of titles and passages, `StructuredDocumentParser.tableCaption`/`numberedTableCaption` take the table's own caption; (3) Gate C counts a value held only by another table row as unverified (`valuesFromOtherRows`); (4) details card reads the badge's outcome (`SourceFidelityStatus.FidelityLevel.from`), no-passage answers carry `no_documents`; (5) summary-detail step uses only retrieved documents' summaries; (6) determinism: ordered keyword and expansion lists, FTS ties broken by id; (7) sync moves unreferenced files to `OrphanedDocuments/` for 30 days and skips the sweep while an import runs; (8) Library Settings claims corrected after a claim audit; (9) source chips keep identity; several comments corrected. A first badge-only fix showed "1-28" Verified on his phone and was reverted the same night. (10) table cells read from the PDF text layer when it agrees with Vision (`textLayerAgrees`); (11) wide tables' key-value pairs keep their row. **Not done:** "Quotes only" really model-free (his decision, row `40049a74d54f811ea077ef82be46545e`); Deep Think's uncited 0.5 score; the 5 Hz Chat clock |
| Ingestion fidelity, 2026-11-08 morning (his "garbage in garbage out... no losses, only gains"; "absolute best practices") | Measured with `ExtractionFidelityRecorder` + `scripts/extraction_fidelity.py` on 8 PDFs (141 pages) from his Mac library, iOS 27 Simulator `ED53C10F-...` ("OI fidelity"), records and README in `BenchmarkRuns/2026-11-08-extraction-fidelity/`. Before (14d6cc67) vs after8 (this commit): body number recall 0.898 → 0.941, body word recall 0.967 → 0.972, invented numbers 53.2 → 24.9 per 1,000, all 8 imports 594 s → 632 s (6% slower, not profiled). The overnight changes first lost numbers on 7 of 8 files; fixed: running-line keys (letters vs number groups, exact repeats), body text keeps citations and DOIs, digit runs split by gap, text-layer words carried through the layout pass (they were dropped, so the DHA cell fix never ran on layout pages), the layout pass reads each Vision block from the text layer, a text layer without spaces is refused (80% word-count rule), banded edit distance, paragraph agreement by character edit distance. A refuting review found 10 defects, all fixed with tests (CHANGELOG 5.8, the 2026-11-08 [Ingestion] entries). Row `41249a74d54f816cb43ac42648d1f872` In Progress: closes when he re-imports the DHA paper on his iPhone and "How much DHA is recommended?" answers 1-2 g. Research survey (cited, ranked 10 changes): `BenchmarkRuns/2026-11-08-ingestion-research/ingestion_best_practices.md`. Probe: PDFKit `characterBounds(at:)` boxes have zero gaps between words and drift by one after a line break, so geometry-based word rebuilding needs a `CGPDFScanner` content-stream reader |
| Decomposition of the three giant functions (2026-11-06 to 07, his "PROCEED: IMPLEMENT", "surgically") | **Done and pushed.** `queryInternal` 5,826 → 872 lines (80 steps), `addDocument` 1,438 → 410 (23), the PDF parser 1,652 → 17 steps; then their files split by job: `RAGService+QueryPipeline` → 6 files, `RAGService+Import` → 4, `DocumentProcessor+StructuredParsing` → 3 (`95cfe7ae`, `4b042ad6`, `227fae68`). Every step: verbatim move check, iOS Simulator + iOS device + macOS builds, golden recording identical before and after (`StandardPipelineGoldenTests` 35 items, `ImportGoldenTests` 32, `StructuredParsingGoldenTests` 13). Four Fable refuting reviews of all 80 Standard steps and the import review: no behavior change. The generation block (S6c) stays in `queryInternal` on purpose: its `#else` half is the device path no Simulator recorder can prove. Record: `BenchmarkRuns/2026-11-06-decomposition/PLAN.md`; Atlas section 22; `Docs/ai/FILE_MAP.md` |
| Cloud test suite | #492 on `650af9ba`: 1,456 / 14 / 6 on all three devices, the baseline exactly. Xcode Cloud workflow `Tests (manual)` (id `77b13ba4-2ea7-4742-94ab-424586ef6ab5`, no push trigger) created 2026-11-07: iPhone 15 Pro, iPhone 17 Pro Max, iPad mini (A17 Pro), iOS 27.0. Run #491 on `227fae68`: 1,456 passed / 14 skipped / 6 failed on both iPhones, the same 6 environment failures as before the refactor (#489, #490); the iPad had one more, a live Wikipedia download that failed TLS on the cloud machine. The macOS action was removed: the test target is `SDKROOT = iphoneos`; `XCODE_XCCONFIG_FILE` pointing at an xcconfig with `SDKROOT = macosx` fixes it (measured locally), not yet set up. Memory `xcode-cloud-is-test-compute` |
| Docs (2026-11-07) | `b20d80a8`: seven Fable auditors checked every citation, symbol and behavior claim in the reference docs; three reviewers read every fix's target (22 wrong: 17 corrected, 5 left out; 3 unsure left out); 432 applied. `verify_doc_claims` 2,091 claims, 0 failures; codemap 0 errors. Six dated audits moved to `Docs/Archive/` (118 links rewritten); `DOCUMENTATION_CONSISTENCY_AUDIT.md` and `AppleIntelligenceTransitionPlan.md` stay because the RepoOS router reads them by path. README and `Docs/README.md` rewritten as a front door. Chapter 10's false "no-documents chat keeps its tools" claim corrected with a dated note |
| Deep Think speed (his "PROCEED: IMPLEMENT" for changes 2, 3, 4, 6) | `19dfb3e2`, revised in `d2417516` after a Fable refuting review (cold vocabulary cache, 12 Core ML calls in flight): `executeMultiQuerySearch` runs the first sub-search alone, then the rest at most 2 at once, merged in query order (dt-before vs dt-after2: 57/57 multi-query identical); `skipContinuation: true` on title routing and the YES/NO intent check. Proof: `DeepThinkRetrievalGoldenTests` before vs after, 57/57 multi-query and 759/760 searches identical (the one difference was unsteady inside the before run). Dropped after reading the code, each with its reason in `BenchmarkRuns/2026-11-07-deepthink-speed/PLAN.md`: 2 (early planner changes the route receipt's reason), 6 (token counts include routed labels), 5 (he cleared `FoundationModelSessionFactory.swift`, but a prewarm during a running session measured a 5 s stall on the Mac, so it was not done). Expected about 25-30 s off 254 s with the planner cache of `9917b9d4`; **not timed on the device**. His rule, memory `deep-think-speed-never-costs-depth`: no shorter or dumber answers |
| His iPhone | Runs the Debug build of `beb94eca`, installed over Wi-Fi 2026-11-07 17:30 PT: everything above plus Deep Think/Maximum Fact Check per claim (rows `41249a74d54f81d2bdb9d0188d5ca50a`) and iPhone portrait only (row `41249a74d54f81adbb78e79cbcbba0b3`; the built Info.plist reads `UISupportedInterfaceOrientations~iphone` = Portrait, iPad all four). Measured on his iPhone (evidence `~/Library/Developer/OpenIntelligence-evidence/2026-11-07_174017` and `_174957`): Deep Think 138.8 s and 140.4 s against 254 s mean on 2026-11-04; planner gaps 15 s to 0.3 s (`planner.reused` x2), sub-searches 17.1 s to 8.2 s with warm models (10.8 s for the first after launch, cold model loads), chain setup 12 s to 6-7 s; sessions and synthesis shorter by the model's own output length (not a code change). **Closed 2026-11-07 on his iPhone:** Fact Check row ("6 Verified", each claim SUPPORTED) and portrait row (did not rotate); `devicectl device info apps` reads OpenIntelligence 5.8 (150). Debug is unoptimized for app code, as the 2026-11-04 timing builds were, so stage times compare like for like |
| Owner's 18:00 PT import, 2026-11-07 (his "PROCEED", all three) | From his iPhone's trace (evidence `~/Library/Developer/OpenIntelligence-evidence/2026-11-07_180251`). (1) Suggested questions: every cancelled or timed-out run was saved as "no questions", and Chat wrote questions only for an empty bank. Fixed in `SuggestedQuestionsService+Bank.swift` (`fillMissingQuestions`, `documentsNeedingQuestions`, `isInterruption`; at most 3 files per refresh while the bank holds under 25), `+LLMGeneration.swift` (`interrupted: inout Bool`); test `SuggestedQuestionsFillTests`; row `41249a74d54f81e18240fb9bf9cd4b75`. (2) Import console: one color per stage (`IngestionConsoleLogRow.stageColor`); row `41249a74d54f81b9a577ce1e8c8d457b`. (3) Blank Chat after back (row `40f49a74d54f81eb9b32d9ec3292c817`, cause unknown): `ContentView.checkChatStillShown` rebuilds the Chat stack 0.7 s after Chat disappears under its own tab (at most once per 10 s) and journals `chat.blankRebuilt`; `chat.appear`/`chat.disappear` carry `NavigationProbe.summary()` (navigation depths). Then (19:04 install): the fill reads each file's own passages (`RAGService.passagesForSuggestedQuestions`) because the library's 50-passage sample left Library 7's second file (mostly reference list) with none, and it logs why it skips a file; `NavigationProbe` names each tab's depth (`tabs=chat:N,...`). Import into a new library at 19:00 PT wrote 7 + 10 questions. Still to see: Library 7's second file getting questions on the 19:04 build, the colors, and which tab holds the 4-deep stack. Decomposition row closed 2026-11-07. Then (19:52 install): a PDF's extraction reports each finished page (`parseSubBatchStructure`; the batch-start report named the last page), and `import.progress` journals each percent change; his 18:56 background import sat at 4% for 71 s and iOS ended it (battery 5%). Test `ExtractionPageProgressTests`. Waits on one import with the app left during extraction |
| Roadmap | 5.8: 8 Completed, 109 In Progress, 12 To Do (read 2026-11-07). Decomposition row `41049a74d54f81f195f6e7ffd1944b9c` In Progress: closes on his iPhone, one Standard question and one import behaving as before |
| 5.8 copy | What's New, `USER_CHANGELOG.md`, `WHATS_NEW.md`, release notes, the `### 5.8` metadata entry written earlier; **not pushed to App Store Connect** |

## Active Constraints

- Every commit ends with `[ci skip]`. He gave the word to push on 2026-11-07; App Store Connect writes and public pages only at his word.
- Hard-boundary files need him to name them (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`). Source edits need PROCEED: IMPLEMENT.
- Never delete docs, benchmark runs, Notion rows or agent histories; commit by name; no co-author lines; leave
  `.agents/skills/`, `.codex/*` and `scripts/run_quality_matrix.py` alone; edit Swift by script (the format hook).
- A row closes only on proof where the defect appears. One `xcodebuild` at a time; builds from `/private/tmp/oi58-src`.
- Golden data now lives in `~/Library/Developer/oi-decomp-golden` and `~/Library/Developer/oi-dt-golden` (`/private/tmp` gets wiped).

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService+Query{Pipeline,Preparation,Retrieval,Context,Answer,Exits}.swift`,
  `RAGService+{Import,ImportQueue,ImportEnrichment,IndexHealth}.swift`; `Services/Document/Processing/DocumentProcessor+{StructuredParsing,StructureChunks,StructureText}.swift`.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator+Retrieval.swift` (`executeMultiQuerySearch`), `+ReasoningChain.swift` (`routeChunksByTitle`).
- Golden recorders: `OpenIntelligenceTests/Services/RAG/Orchestration/{StandardPipeline,Import,DeepThinkRetrieval}GoldenTests.swift`,
  `OpenIntelligenceTests/Services/Document/Processing/StructuredParsingGoldenTests.swift`; `scripts/golden_compare.py`, `scripts/golden_retrieval.py`.
- Tooling (gitignored): `BenchmarkRuns/2026-11-06-decomposition/` (`extract_step.py` with exit/tail modes and `force_params`, `fast_batch.py`,
  `step_check.sh`, `commit_step.py`, `phase4_split.sh`), `BenchmarkRuns/2026-11-05-file-split/` (split tools; `split_type.py` now stamps the real date).

## Verification (output read, 2026-11-08)

- Fidelity runs `before` through `after8` → table in `BenchmarkRuns/2026-11-08-extraction-fidelity/README.md` (after8 as in Status).
- Full batch 11:00-11:22 PT (iPhone install 11:16) (`/private/tmp/oi-run.sh`: iPhone build + install over Wi-Fi, 31 test classes, macOS build) → device
  BUILD SUCCEEDED and installed; 271 tests, 4 skipped, 2 failures, both "not imported within a minute" while the Mac's load average
  was 89; rerun of `ShortcutsActionTests` + `WatchedFolderPathTests` alone → 23 tests, 0 failures; macOS BUILD SUCCEEDED.
- Xcode Cloud #495 on f7c1b484 (first full iOS suite) → 4,530 passed, 51 skipped, 30 failed (10 tests x 3 simulators): 2 real
  (keyword order, CSV part placement; fixed), 8 environment (no model, no English word classes, barcode reader, a skip inside
  `XCTUnwrap`, a queue wait on other tests' items; now skip or wait on their own item). Not rerun in the cloud since.
- Banded edit distance vs the full table: 20,000 random pairs at two limits → 0 mismatches. `secret_scan.py` clean; codemap 0 errors.

## Verification (output read, 2026-11-07)

- `step_check.sh` per batch → "STEP OK" for every Standard batch Q12-Q66 and E01-E14; per file split → parse-b6 == parse-f1, import-i23 == import-f2, standard-e14 == standard-f3.
- `phase4_split.sh` → 0 lines added/lost, 0 out of order, overload_check 0, widen_check 0 for all three files.
- Xcode Cloud #491 → as in Status. `python3 scripts/verify_doc_claims.py` → 2,091 claims, all match. `codemap.py check` → 0 errors.
- `golden_retrieval.py compare results-dt-before.json results-dt-after.json` → 760 searches, 1 differs (unsteady before), multi 57/57.

## Blockers / Unknowns

- Deep Think timing on the device: ask one Deep Think question on the new build, then `python3 scripts/phone_evidence.py --since <install time>`
  and compare stages with `BenchmarkRuns/2026-11-04-speed-research/measured_budget.md` section A (look for `planner.reused` and the
  multi-query span). Clean runs only (no import, rate limiting or game).
- The 109 In Progress 5.8 rows wait on the device pass (skill `device-pass`: at most 5 iPhone and 7 Mac steps).
- Future Backlog candidates not filed yet: regroup `Docs/` by reader (needs the RepoOS router paths changed, `.codex`); the Xcode Cloud macOS
  test workflow; `ShortcutsActionTests` depending on live internet; the BM25 tie flip on near-duplicate documents (`BenchmarkRuns/2026-11-06-decomposition/PLAN.md`).
- `Package.swift` must be named before `Core/Support/test_write.txt` and `WritingToolsService` can go.

## Exact Next Action

1. Ask him to re-import `ijms-21-03624-2.pdf` in Library 8 on the build installed 2026-11-08 11:16 PT and ask "How much DHA is
   recommended?"; then `python3 scripts/phone_evidence.py --since "2026-11-08 11:16"` and read the stored ROW 3 (expect "DHA |
   ... 1-2 g"), the answer and `answers:` in `answer.done`. A pass closes row `41249a74d54f816cb43ac42648d1f872`.
2. Profile the 6% import slowdown: run `ExtractionFidelityRecorder` on `BL999.pdf` alone (47 s before, 62 s now) with
   `xctrace record --template 'Time Profiler'` or timing logs around `textLayerWords(of:)`, `LayoutAwareExtractor` block reading
   and `textLayerAgreesForParagraph`.
3. Then the survey's ranked items, each measured by the fidelity recorder and the retrieval benchmark before shipping: first an
   independent ground truth (olmOCR-Bench-style per-page checks instead of `pdftotext`), then context prefixes on the streamed
   import paths and in BM25 title/section fields, the table title in every row passage; passage size vs MiniLM's 128-token
   training (re-embeds libraries: his decision); a `CGPDFScanner` text engine as its own project.
