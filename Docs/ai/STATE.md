# Current State

Updated: 2026-11-10 about 08:30 PT (5.8 open. The reranker swap to Granite r2, the answer-floor fixes and the audit of
every rule after the reranker are committed in the commit after 2313b62b.)
Branch/worktree: `main`, primary checkout
Last verified commit: 2313b62b

## Objective

**Ship 5.8** (his words 2026-11-10: "I feel like I should ship 5.8"). The board is 5.8 and Future Backlog only. What
remains is his device pass, a Xcode Cloud build when he asks for one, and the App Store Connect submission at his word.

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
