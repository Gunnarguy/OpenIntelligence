# Current State

Updated: 2026-11-07 about 15:20 PT (5.8 open. The three giant functions are decomposed and their files split, the docs
re-checked against the code, Deep Think's sub-searches made concurrent; all committed and pushed.)
Branch/worktree: `main`, primary checkout
Last verified commit: d2417516

## Objective

**Finish 5.8 so the owner can move on to more behind the paywall** (his words 2026-11-03). The board is 5.8 and Future
Backlog only. What remains is his checks on the iPhone and Mac (the device pass), then shipping 5.8 when he says so.

## Status

| What | Where it stands |
|---|---|
| Decomposition of the three giant functions (2026-11-06 to 07, his "PROCEED: IMPLEMENT", "surgically") | **Done and pushed.** `queryInternal` 5,826 → 872 lines (80 steps), `addDocument` 1,438 → 410 (23), the PDF parser 1,652 → 17 steps; then their files split by job: `RAGService+QueryPipeline` → 6 files, `RAGService+Import` → 4, `DocumentProcessor+StructuredParsing` → 3 (`95cfe7ae`, `4b042ad6`, `227fae68`). Every step: verbatim move check, iOS Simulator + iOS device + macOS builds, golden recording identical before and after (`StandardPipelineGoldenTests` 35 items, `ImportGoldenTests` 32, `StructuredParsingGoldenTests` 13). Four Fable refuting reviews of all 80 Standard steps and the import review: no behavior change. The generation block (S6c) stays in `queryInternal` on purpose: its `#else` half is the device path no Simulator recorder can prove. Record: `BenchmarkRuns/2026-11-06-decomposition/PLAN.md`; Atlas section 22; `Docs/ai/FILE_MAP.md` |
| Cloud test suite | #492 on `650af9ba`: 1,456 / 14 / 6 on all three devices, the baseline exactly. Xcode Cloud workflow `Tests (manual)` (id `77b13ba4-2ea7-4742-94ab-424586ef6ab5`, no push trigger) created 2026-11-07: iPhone 15 Pro, iPhone 17 Pro Max, iPad mini (A17 Pro), iOS 27.0. Run #491 on `227fae68`: 1,456 passed / 14 skipped / 6 failed on both iPhones, the same 6 environment failures as before the refactor (#489, #490); the iPad had one more, a live Wikipedia download that failed TLS on the cloud machine. The macOS action was removed: the test target is `SDKROOT = iphoneos`; `XCODE_XCCONFIG_FILE` pointing at an xcconfig with `SDKROOT = macosx` fixes it (measured locally), not yet set up. Memory `xcode-cloud-is-test-compute` |
| Docs (2026-11-07) | `b20d80a8`: seven Fable auditors checked every citation, symbol and behavior claim in the reference docs; three reviewers read every fix's target (22 wrong: 17 corrected, 5 left out; 3 unsure left out); 432 applied. `verify_doc_claims` 2,091 claims, 0 failures; codemap 0 errors. Six dated audits moved to `Docs/Archive/` (118 links rewritten); `DOCUMENTATION_CONSISTENCY_AUDIT.md` and `AppleIntelligenceTransitionPlan.md` stay because the RepoOS router reads them by path. README and `Docs/README.md` rewritten as a front door. Chapter 10's false "no-documents chat keeps its tools" claim corrected with a dated note |
| Deep Think speed (his "PROCEED: IMPLEMENT" for changes 2, 3, 4, 6) | `19dfb3e2`, revised in `d2417516` after a Fable refuting review (cold vocabulary cache, 12 Core ML calls in flight): `executeMultiQuerySearch` runs the first sub-search alone, then the rest at most 2 at once, merged in query order (dt-before vs dt-after2: 57/57 multi-query identical); `skipContinuation: true` on title routing and the YES/NO intent check. Proof: `DeepThinkRetrievalGoldenTests` before vs after, 57/57 multi-query and 759/760 searches identical (the one difference was unsteady inside the before run). Dropped after reading the code, each with its reason in `BenchmarkRuns/2026-11-07-deepthink-speed/PLAN.md`: 2 (early planner changes the route receipt's reason), 6 (token counts include routed labels), 5 (he cleared `FoundationModelSessionFactory.swift`, but a prewarm during a running session measured a 5 s stall on the Mac, so it was not done). Expected about 25-30 s off 254 s with the planner cache of `9917b9d4`; **not timed on the device**. His rule, memory `deep-think-speed-never-costs-depth`: no shorter or dumber answers |
| His iPhone | Runs the Debug build of `d2417516` (everything above, including the reviewed Deep Think revision), installed over Wi-Fi 2026-11-07 16:49 PT; `devicectl device info apps` reads OpenIntelligence 5.8 (150). Debug is unoptimized for app code, as the 2026-11-04 timing builds were, so stage times compare like for like |
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

Ask him to run the device pass with the build on his iPhone: one Standard question and one import (closes the decomposition row
`41049a74d54f81f195f6e7ffd1944b9c`), then "What regulates mitochondrial quality?" in Deep Think (closes row `41049a74d54f8175a849d1f6c19f3d37`
and gives the Deep Think timing). Then pull the evidence with `python3 scripts/phone_evidence.py --since "2026-11-07 16:49"`.
