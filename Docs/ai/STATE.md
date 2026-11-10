# Current State

Updated: 2026-11-10 about 08:30 PT (5.8 open. The reranker swap to Granite r2, the answer-floor fixes and the audit of
every rule after the reranker are committed in the commit after 2313b62b.)
Branch/worktree: `main`, primary checkout
Last verified commit: 2313b62b

## Objective

**Ship 5.8** (his words 2026-11-10: "I feel like I should ship 5.8"). The board is 5.8 and Future Backlog only. What
remains is his device pass, a Xcode Cloud build when he asks for one, and the App Store Connect submission at his word.

## Active work list, 2026-11-10 (his words: "let's do it all, surgically, I want you to remember this list and its full reason")

Approved that morning on the plan below (defaults accepted: Quotes only made real, Spotlight checked on his phone
first, localization and named profiles to Future Backlog; `BNNSVectorDatabase.swift` NOT named, so not touched).
Benchmarks (5.7 vs 5.8 head-to-head, iOS 27 structured-failure rate) are for 2026-11-11; Instruments tracing on the
phone is for the evening of 2026-11-10 when he is home. Each item: what, why, closes when.

| # | Item, Notion row | Why | Closes when |
|---|---|---|---|
| T | Table title row becomes the header (`41449a74d54f816bb701c8ba99044cd2`) | KBIE p6 header reads "<title> \| Column 2 \| Column 3", real header stored as ROW 1: column names detached at import (owner rule 4, fidelity). Cause: the PDF table parser's header check (`StructuredDocumentParser.swift`, `headerRow` in the table parser, ~line 1732) accepts a first row with one filled cell; the Office path already requires 2 | 515 page-image checks gain KBIE's 9 column checks, none lost; re-imported KBIE on his iPhone answers by column |
| 1 | Quotes only answered by Apple's model (`40049a74d54f811ea077ef82be46545e`) | Settings says no model writes and it never leaves the device; `case "on_device_analysis"` loads `AppleFoundationLLMService` (owner rule 5, honest claims) | Picking it gives extractive answers with no model call, a test proves it; Deep Think and Maximum off in that mode |
| 2 | Deep Think panel (`40f49a74d54f81b4b22bc0b52bf566c8`) | "1 reasoning sessions" during session 4; HyDE tick for a step Deep Think skips (a false claim); a purple box drawn over it; internal wording ("Tokens: 4", "0 t/s") | Count matches, ticks match stages that ran, nothing drawn over it, he finds it clear on his iPhone |
| 3 | Mac crash: overlapping saves of one library (`40e49a74d54f81099f05c28eb6c091f1`) | Guard committed `b2fe74ca` stops the crash; the cause (a self-healing rebuild's `addDocument` and an import's `persist` saving one library at once, records and mapped file disagreeing) is not established | Import during a self-healing rebuild of the same library, Simulator then his Mac, no "out of range" and no crash |
| 4 | Deep Think "didn't finish" after leaving the app (`40f49a74d54f812dbdd8fd628b622299`) | The answer lived only in memory; iOS suspended then ended the app; background generation was `rateLimited` (Apple: use non-streaming `respond` in the background) | A Deep Think answer interrupted by leaving the app finishes after return or relaunch on his iPhone |
| 5 | Chat goes white (`40f49a74d54f81eb9b32d9ec3292c817`) | Journal: `chat.disappear`/`chat.appear` three times in a second with no tab change, then the tab shows no view; recovery `checkChatStillShown` exists, cause unknown | Cause found in code and fixed; Deep Think with screen switching keeps Chat drawn on his iPhone |
| 6 | Import watchdog, 900-page PDF in background (`40049a74d54f81cba108fb04a576dc42`) | `0x8BADF00D` scene-update watchdog, main thread waiting (app CPU 2%); suspect a synchronous Vision wait (`VisionOCRThrottle.executeSyncOperation`) reached from the main actor | 900-page import, app backgrounded, no watchdog report on his iPhone |
| 7 | Instruments tracing (`3ab49a74d54f8195a1bbe3843f83be5c`) | One Time Profiler + signpost trace per answer mode | Tonight with him, phone unlocked |
| 8 | iOS 27 prompts (`3d749a74d54f81e7888fc50e668d74df`) | Structured-generation failure rate on the 27 model unrecorded | Tomorrow with the benchmarks |
| 9 | Spotlight document tap (`3ff49a74d54f81fea954d76ff336595e`) | Simulator: Top Hit runs Ask About a Document instead of opening it | Checked on his phone first; then his choice (drop the Siri link, or one App Shortcut slot in `RAGAppIntents.swift`) |
| 10, 11 | Localization (`39049a74d54f811083b1f84f2231d275`), named profiles (`3d749a74d54f810e9136cad05c15bd37`) | Need his languages / `FoundationModelRoutePolicy.swift` | Moved to Future Backlog |


**Where the list stands (2026-11-10 08:15 PT):** T, 1, 2, 3 (in-app path), 4, 5 (probe and Atlas only; cause unknown) and 6 are built,
reviewed by a refuting reviewer (2 blockers and 7 defects found, all fixed) and pass on the iOS 27 Simulator: 169 tests, 0 failures
(`/private/tmp/oi-finish/test.log`), macOS build and iPhone build succeeded. The iPhone install failed (phone unavailable, away from
home); install `/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app` tonight. Open for him: the X-Ray HUD outline
over the Deep Think panel (leave or hide), naming `BNNSVectorDatabase.swift` for the rest of item 3, item 9 on his phone.

## Status

| What | Where it stands |
|---|---|
| Reranker swap (2026-11-09) | TinyBERT replaced by IBM Granite reranker r2 (Apache 2.0, `THIRD_PARTY_NOTICES.md`), Core ML multifunction package len256/len512 built by `scripts/build_reranker_model.py`, tokenizer in `swift-transformers/.../reranker_tokenizer.bundle`. Scores min-max normalised to 0.10-0.90. First model load on his iPhone 45.5 s, shown by `RerankerSetupCard` (`RerankerSetupStatus.swift`, overlay in `ContentView.swift`). Tests `RerankerModelTests` |
| Blank Standard answer (lysine, 2026-11-09) | Fixed at the general layer: side searches go behind retrieval's top passage (`RAGService.insertingBehindTopRanked`), sniper scores capped at 0.89 (`sideSearchScoreCeiling`), degenerate answers rewritten or replaced (`isDegenerateAnswer`, `notFoundAnswer`), orphan list markers dropped (`isOrphanListMarker`), the count instruction only for "how many" (`getsCountInstruction`), the contents-page penalty exempts stored tables (`RAGEngine.isStoredTable`). On his iPhone 21:31: "Lysine ranges from 4.4-26.2 mg/g [S1]" |
| Rule audit (night 2026-11-09/10) | Every rule after the reranker switched off one at a time (`RetrievalAblation`, development builds only; `RerankScoreCache` reuses scores). Record `BenchmarkRuns/2026-11-10-rule-audit/README.md`. QASPER 246 questions: corrective retrieval helps (p=0.01), focused window probably (p=0.08), rest neutral. Tables 158 questions: Deep Think's spec sniper removed (first passage 72.2% to 75.9%, 7 better 1 worse, p=0.07); Standard keeps its sniper. Apple's model on tables: 125/158 right, 124/131 when the cell reached it. Answer-quality eval 0.45, unchanged. Not measured: compression, the multi-query blend |
| Import check (same night) | 356/433 page-image checks. A fresh KBIE import stores every row name; his phone's copy is from the 2026-11-02 code |
| His iPhone | Debug build of this working tree installed 2026-11-10 05:45 PT over Wi-Fi, **not launched** (phone locked). No Deep Think table question asked on it yet |
| Roadmap | Row `41449a74d54f81f5b46bc81beac186ae` (reranker) carries the audit results; closes when the setup card is seen after a fresh install |

## Active Constraints

- Every commit ends with `[ci skip]` until he asks for a Xcode Cloud build. App Store Connect writes and public pages only at his word.
- Hard-boundary files need him to name them. Source edits need PROCEED: IMPLEMENT. None were touched in this work.
- Never delete docs, benchmark runs, Notion rows or agent histories; commit by name; no co-author lines; leave
  `.agents/skills/`, `.codex/*` and `scripts/run_quality_matrix.py` alone (all three stay uncommitted on purpose).
- Builds from `/private/tmp/oi-src` (rsync of the repo), DerivedData outside `~/Documents`, one `xcodebuild` at a time. Disk about 14 GiB free.
- Benchmarks on the Simulator ("OI reranker bench" `8B694027-...`, "OI reach 2" `ED43943A-...`), never his library.

## Working Set

- Retrieval: `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift` (cross-encoder, penalties, cache hook),
  `RAGService+{QueryContext,QueryRetrieval,StandardRetrieval,SentenceExtraction,ToolHandler}.swift`,
  `Services/Agentic/AgenticOrchestrator+Retrieval.swift` (multi-query blend switch).
- Answers: `RAGService+{AnswerResponsiveness,AnswerFinishing,QueryAnswer}.swift`.
- Audit tools: `Services/RAG/Tuning/{RetrievalAblation,RerankScoreCache}.swift`,
  `OpenIntelligenceTests/Services/RAG/Orchestration/EvidenceReachBenchmarkTests.swift`, `scripts/evidence_reach.py`
  (prepare, prepare-tables, merge, score), run scripts in `BenchmarkRuns/2026-11-10-rule-audit/`.
- Table import (next defect): `Services/Document/Processing/TextLayerTableDetector.swift`, `StructuredDocumentParser.swift`.

## Verification (output read, 2026-11-10)

- `xcodebuild test` on iOS 27 Simulator `73F2BD6B-...` (AnswerFloor, HybridSearchService, ContextPacking,
  ResponseTailTrimming, RerankerModel) -> 43 tests, 0 failures.
- iPhone `phone_build.sh` -> BUILD SUCCEEDED; `devicectl device install app` -> installed 05:45 PT; launch refused (locked).
- `evidence_reach.py score` on qasper/ and tables/ -> as in Status; eval -> 0.45.
- `secret_scan.py` clean; `check_icloud_conflicts.sh` OK; `sync_purpose.py --check` in sync; `codemap.py check` 0 errors
  (one citation in `hybrid-retrieval-and-fusion.json` repointed to RAGEngine.swift:1589).
- The full unit suite was not run (Xcode Cloud `Tests (manual)` is the route).

## Blockers / Unknowns

- **Table title row:** when a table's title spans its first row, the header is stored as "<title> | Column 2 | Column 3"
  and the real header as ROW 1 (KBIE_13_2100863.pdf p6, 9 failed checks; probably jamapsychiatry's 14 of 21). Values
  are kept, column names are detached. Exists in every shipped version. Not filed yet; owner deciding whether it goes in 5.8.
- 27 table cells never reached the model (fbioe 10, jamapsychiatry 8, KBIE 7); likely partly the title-row defect.
- The table library's import asserted 5 of 7 successes in both slices, yet cells of all 7 PDFs were retrieved. Not traced.
- Libraries imported before 2026-11-08 may hold broken tables; re-importing is his decision.
- The embedder (MiniLM) swap was raised by him; not asked for as work. Re-embedding libraries is his decision.
- Deep Think timing on the device and the 5.8 device pass rows (skill `device-pass`).

## Exact Next Action

Ask him to unlock the iPhone, open OpenIntelligence (the 05:45 build), watch for the "Setting up search" card, and ask
one Deep Think table question; then `python3 scripts/phone_evidence.py --since "2026-11-10 05:45"`. A setup card seen and
a table answer from the right row close row `41449a74d54f81f5b46bc81beac186ae`. Then the device pass and, at his word,
a Xcode Cloud build for 5.8.
