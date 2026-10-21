# Current State

Updated: 2026-10-20, about 23:45 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on
iPhone, iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: cce1d2c

Earlier detail is in git: `git show cce1d2c:Docs/ai/STATE.md` (the evening of 2026-10-20) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row** ("Everything into 5.7", 2026-10-18, his PROCEED: IMPLEMENT; decisions in auto
memory `everything-into-5-7.md`). On 2026-10-19: "just go nuts and close all of the rest of the shit out please. like
everything." On 2026-10-20: "if it can be added, then we add it if it needs to be fixed, then we fix it ... apply the
absolute best practices using apples latest API frameworks." A row closes on a scripted iOS 27 Simulator check when the
defect is not about the phone itself; memory, background tasks, iCloud, signing and Private Cloud Compute rows close
only on his phone.

## Status

| What | Where it stands |
|---|---|
| Last commit | The one that contains this file, after `cce1d2c`: labels number the passages an answer keeps (the sentence extractor with `numberByUse`, its needle rescue, `RAGEngine.assembleContext` after a skipped near-duplicate); Copy and an answer handed to Shortcuts list what each label points at (`OpenIntelligence/Services/RAG/Citations/`); the Database tab, Device & Performance, the Atlas and the Siri card in plain words with Technical Details off. |
| Row `40049a74d54f8113bb46eb9888627861` (labels numbered differently from passages) | In Progress. The numbering is fixed and the household run logged no label past an answer's passages, but the same run showed the model putting labels on the wrong sentence (next action). |
| Row `3fe49a74d54f81ce84a1f0b59e2e1ec7` (Settings jargon) | Open. Device & Performance still shows "Adaptive Visual Ingestion" ("OCR detail, structure recovery") and "Live System Monitor" with Technical Details off (robot photo `tour/25`). |
| Native Surfaces Catalogue | Version 27 at https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (118 rows). Its "Share an answer with its sources" row does not yet say Copy and the Shortcuts item list labels; update it and republish (`node --check` the page script, count 118 ROWS first). |
| Open in 5.7 | About 128 rows (query the data source: Target Release v5.7, Status not Completed). What only he can do: `~/.agents/oi-robot/scripts/asks-for-gunnar-draft.md`. |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18 (`project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`): "Must be done flawlessly ... only if
  they're genuine full and well rounded improvements." `ChatMessage.swift`, `RAGAppIntents.swift` and
  `KnowledgeContainer.swift`'s route were not named and need his word.
- **Another session writes docs here.** The PostDesk session ("Demos") holds doc patches in `/private/tmp/oi-wt/`
  (`docs-howitworks`, `docs-ingestion`, `docs-canonical`, `docs-routing`). It applies them only after this session says
  "go", commits only its own paths with `[ci skip]` and does not push; this session pushes them with its next commit.
  Don't edit `Docs/RETRIEVAL_PIPELINE.md` or `Docs/PRIVACY_AND_ROUTING.md` without asking it first. Its code-trace
  item 15 (Standard path drops rank 2 in `assembleContext`, `RAGEngine.swift` near line 501 and `RAGService.swift`
  near line 15011) is this session's to fix.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/`, `.codex/hooks*` and `.codex/config.toml`
  (another agent's, untracked) alone; edit Swift by script.
- A development build on his Mac opens his real libraries: don't launch one without asking. Never tap the plan sheet's
  purchase buttons in a simulator.
- The Mac is shared. `build57.sh` stops its own build when free disk falls under `GUARD_DISK_MB` (3,500 MB unless set)
  or free memory under 15%. Compiling `RAGService.swift` grows swap by 4 to 6 GB, twice per build. Don't build while
  World of Warcraft is open. One `xcodebuild` at a time.

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: `extractRelevantSentencesOffMain` (labels, packing,
  `numberedLabels`), the Standard path's context assembly (search "The chunks the prompt actually labelled"), and
  `finalizeResponse` (logs a label past the answer's passages). `RAGEngine.swift` `assembleContext`.
- `OpenIntelligenceTests/Services/RAG/Orchestration/CitationLabelNumberingTests.swift` pins the numbering.
- Uncommitted on purpose: `scripts/run_quality_matrix.py` (`--simulator <udid>`, untested) and the opt-in
  `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift` (see Blockers).
- Tools in `~/.agents/oi-robot/` (README inside): the robot (`demodriver/`, live copy `/private/tmp/demodriver-pv`, built
  in `/private/tmp/demodriver-pv-dd`), `pvaudit.py`, `demo_from_tree.sh`, `build57.sh`, `builddevice.sh` (his iPhone),
  `answer_detail.py`, and `label_truth.py` (each saved label: what a tap opens, and whether another passage matches its
  sentence better).
- Simulators (DeviceHub deleted every simulator at 22:08:49 on 2026-10-20; check `xcrun simctl list devices` first):
  `OI 5.7 tests` `0034D4D8-8443-4503-AE3F-57F3BB1FC89C` (iPhone 18 Pro) runs the hosted unit tests, and `build57.sh`
  names it. `OI 5.7 A17 Pro` `A3DDC13D-2EAA-40E4-B562-FA5E0E4FDDC8` (iPhone 15 Pro) holds the demo copy of the
  committed tree (a `git stash create` snapshot, `64e1d24`) with the household library (the ten sample documents);
  its trace is `Documents/pipeline_trace.log` in the app's container.
- His iPhone has a development build of the same tree (installed 21:56 with `builddevice.sh` and `devicectl`).

## Verification (2026-10-20, output read)

- `build57.sh build-for-testing` and `test-without-building` on the test simulator, on the working tree of this commit
  -> `Executed 1333 tests`; three `AtlasLabelingTests` word-class tests failed on the new simulator before its language
  data arrived and passed on a rerun (26 of 26).
- `demo_from_tree.sh A3DDC13D-...` -> `INSTALLED demo copy of 64e1d24`; robot `testHouseholdImport`, then
  `testHouseholdStandard` (16 questions) -> the trace has all 16 queries and no "were numbered differently" line.
- Robot `testShortcutsAskThenCopy` ("How much is the pet deposit?") -> clipboard "$300.00 [S1], [S2], [S3]" with
  "Sources:" and "[S1] Juniper Flats Lease - Unit 4B.pdf, page 1"; no crash report.
- Robot `testDatabaseTour` -> section chips Overview, Intelligence, Documents, Vocabulary, Maintenance, Search (Index and
  Performance hidden with Technical Details off); `testAuditTour` -> 41 photos in the session scratchpad's `tour/`.
- `python3 ~/.agents/oi-robot/scripts/label_truth.py A3DDC13D-2EAA-40E4-B562-FA5E0E4FDDC8 22:30` -> 42 labels; 29 open
  the passage their sentence matches best, 11 doubtful, 2 open nothing ([S13] against 12 saved passages).
- `python3 scripts/secret_scan.py` -> no sensitive tokens; `python3 scripts/verify_doc_claims.py` -> 1022 claims
  match; `python3 .claude/codemap/codemap.py check` -> 0 errors; `VersionHistory.md` identical to
  `Docs/USER_CHANGELOG.md`.

## Blockers / Unknowns

- **A saved answer keeps 12 passages.** `ChatMessage.maxPersistedRetrievedChunks = 12`, so after a relaunch a label past
  [S12] opens nothing (the air fryer's E1 answer cites [S13]). `ChatMessage.swift` is a hard-boundary file he has not
  named; the fix (keep every passage the answer's labels cite) waits for his word.
- The answer card's own buttons (Think Deeper, Ask a Follow-up, a document) could not be pressed by the robot from the
  Shortcuts app; a tap by hand settles row `3f449a74d54f8193a750d1099b83a8c5`.
- `AnswerQualityEvaluationTests` (untracked) has not been run since it got its own engine and cleanup. Rerun:
  `TEST_RUNNER_OI_MODEL_EVALS=1 ... build57.sh test-without-building <log>
  -only-testing:OpenIntelligenceTests/AnswerQualityEvaluationTests`; note the result on row
  `3b549a74d54f814cbb06fa629417b657`.
- His phone: the rows in the asks list. Mac rows need his go-ahead for a development build on his Mac.

## Exact Next Action

Number the extractor's labels in the order the context reads. In `extractRelevantSentencesOffMain`, when `numberByUse`
is set, record the order sources are packed (the lead first, then each block as it is written) and return that as
`usedSourceIndices` instead of `sourcesUsed.sorted()`, so `numberedLabels` writes [S1], [S2], [S3] down the context and
`promptSources` follows the same order; leave the sorted order for callers without `numberByUse`. Add a test that the
labels in the context read 1, 2, 3 in order. Then build, run the suite, make a new demo copy, run
`testHouseholdStandard`, and compare `label_truth.py` with the 11 doubtful of 42 above before closing row `40049a74`.
