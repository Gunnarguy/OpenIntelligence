# Current State

Updated: 2026-10-20, about 20:45 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on
iPhone, iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 29d4a0b

Earlier detail is in git: `git show 1f5ad4c:Docs/ai/STATE.md` (the morning of 2026-10-20) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row** ("Everything into 5.7", 2026-10-18, his PROCEED: IMPLEMENT; decisions in auto
memory `everything-into-5-7.md`). On 2026-10-19: "just go nuts and close all of the rest of the shit out please. like
everything." On 2026-10-20, about Advanced Controls: "if it can be added, then we add it if it needs to be fixed, then
we fix it ... apply the absolute best practices using apples latest API frameworks." A row closes on a scripted iOS 27
Simulator check when the defect is not about the phone itself; memory, background tasks, iCloud, signing and Private
Cloud Compute rows close only on his phone.

## Status

| What | Where it stands |
|---|---|
| Last commit | `29d4a0b`: Library Settings' Search section (the five styles, Advanced Controls in plain words, Passages Needed acting for every library, tuning after an import leaving a chosen library alone) and answers and passages handed to Shortcuts kept a day on the device and looked up by id (`HandedOutItems`), which is what lets Copy to Clipboard take them. |
| Commits earlier 2026-10-20 | `397dbe4` (stopping an import removes the app's copy), `6d8324a` (sample-guide questions), `28b4a2c` and `325370b` (the Atlas's scene back as the default, axis and cluster names, Fact Check, passages end at a word), `b868fc0` (docs). |
| Rows closed this evening | `e8740624a2d441bead51aad44a0481f9` (Custom RAG Pipeline Configuration), `3f449a74d54f8153bac7f4996d704249` (no Shortcuts action returns a value), `3f449a74d54f8183aff0ede2d0212989` (answers, passages and conversations become items). Notes on `3f449a74d54f8193a750d1099b83a8c5` (card buttons, stays open) and `3fe49a74d54f81ce84a1f0b59e2e1ec7` (Settings jargon, stays open). |
| Native Surfaces Catalogue | Version 27 at https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (118 rows: 23 seen working, 40 built, 24 need him). Source: the session scratchpad's `Native-Surfaces-Catalogue.html`; read the live one first if that is gone. |
| Open in 5.7 | About 128 rows (query the data source: Target Release v5.7, Status not Completed). Batched list of what only he can do: `~/.agents/oi-robot/scripts/asks-for-gunnar-draft.md`. |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18 (`project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`): "Must be done flawlessly ... only if
  they're genuine full and well rounded improvements." `RAGAppIntents.swift` was not named for this work and was not
  touched. `KnowledgeContainer.swift`'s route (icloud_sync_change) needs a named approval, which is why the person's
  choice of search settings is kept in `requireExplicitCitations` (`Docs/ai/DECISIONS.md`, 2026-10-20).
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/`, `.codex/hooks*` and `.codex/config.toml`
  (another agent's, untracked) alone; edit Swift by script.
- A development build on his Mac opens his real libraries: don't launch one without asking. Never tap the plan sheet's
  purchase buttons in a simulator.
- The Mac is shared with sessions that compile (OpenPhys on 2026-10-20). `build57.sh` stops its own build when free
  disk falls under `GUARD_DISK_MB` (3,500 MB unless set) or free memory under 15%; the reason is in `<log>.guard`.
  Compiling `RAGService.swift` grows swap by 4 to 6 GB, twice per build (engine and app targets). On 2026-10-20 three
  tries at 5 GB free or less were stopped at 0.8 to 1.6 GB; with 9.8 GB free and `GUARD_DISK_MB=1500` it got through.
- A refuting review before each commit. The one before `29d4a0b` found the store's one-day promise untrue and two
  untrue lines in the Search section's first wording, all fixed before the commit.

## Working Set

- Uncommitted on purpose: `scripts/run_quality_matrix.py` (`--simulator <udid>`, untested), and the opt-in
  `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift` (see Blockers).
- `OpenIntelligence/Services/Agentic/Entities/OIAnswerEntity.swift`: `textWithSources` and `sourceList` are what another
  app or a shortcut's next step receives. `OpenIntelligence/Features/Chat/Response/AnswerShareFormatter.swift` and
  `CitationLinker.swift` resolve labels for the app's own Share; they compile in the app target only.
- Tools: `~/.agents/oi-robot/` (README inside): the robot (`demodriver/`, live copy `/private/tmp/demodriver-pv`, built in
  `/private/tmp/demodriver-pv-dd`; regenerate with `xcodegen generate` after adding a scene file, then rebuild) and the
  scripts (`pvaudit.py`, `demo_from_tree.sh`, `build57.sh`, `guard.inc`, `answer_detail.py`). Scenes added 2026-10-20:
  `OpenIntelligenceShortcutsAppScenes.swift` (the Shortcuts app in iOS 27; `TEST_RUNNER_OI_ACTION` and
  `TEST_RUNNER_OI_Q` pick the first action and its text) and `OpenIntelligenceSearchSectionScenes.swift`
  (`testSearchSection`, `testStyleHoldsBack`).
- A17 simulator `OI 5.7 A17 Pro` `CF4052DA-428C-47AE-9CF1-6A87FBF62701` (iPhone 15 Pro, iOS 27.0, made 2026-10-20 after
  the 08:27 deletion): the demo copy of `ee306c7` (a `git stash create` snapshot of the tree committed as `29d4a0b`;
  Release, Apple's model on), libraries General, Household (the ten sample documents, on Automatic), Claim check,
  Receipts, Tickets and others; "Copy to Clipboard N" shortcuts in its Shortcuts app. Its trace is
  `Documents/pipeline_trace.log` in the app's container.
- Test simulator `OI 5.7 tests` `8A7AAE8A-8FE3-42E7-BA33-8627A738865E`: the hosted unit tests (`build57.sh`). Its app was
  uninstalled and reinstalled on 2026-10-20 (Docs/ai/RUNBOOK.md, Test: "Document quota reached").

## Verification (2026-10-20, output read)

- `GUARD_DISK_MB=1500 OI_SCRATCH=/private/tmp bash ~/.agents/oi-robot/scripts/build57.sh build-for-testing <log>` on the
  tree of `29d4a0b` -> `TEST BUILD SUCCEEDED`, no warning in a file changed that day.
- `build57.sh test-without-building` on the test simulator after uninstalling its app -> `Executed 1324 tests, with 7
  tests skipped and 0 failures`. The run before it failed four import tests on a library the evaluation harness left.
- `bash ~/.agents/oi-robot/scripts/demo_from_tree.sh CF4052DA-428C-47AE-9CF1-6A87FBF62701` -> `BUILD SUCCEEDED`,
  `INSTALLED demo copy of ee306c7`.
- Robot, on that copy: `testShortcutsAskThenCopy` (Ask My Documents, "How much is the pet deposit?") -> the clipboard
  held the answer ("$300.00") with "Sources: - Juniper Flats Lease - Unit 4B.pdf, page 1"; the same scene with
  `TEST_RUNNER_OI_ACTION="Find Passages"` -> a lease passage with its source line; no BackgroundShortcutRunner crash
  report after either. `testSearchSection` -> Automatic kept after opening Advanced Controls and saving, High
  Precision kept after a save and reopen, the 70% and 5-passage hold-back reply, "$300.00" Verified on Automatic.
  `testStyleHoldsBack` -> "High Precision: 6 of 15 held back", each with one passage at 50% or more.
- `python3 scripts/secret_scan.py` -> no sensitive tokens; `python3 .claude/codemap/codemap.py check` -> 0 errors;
  `python3 scripts/verify_doc_claims.py` -> 1008 claims match; `VersionHistory.md` byte-identical to
  `Docs/USER_CHANGELOG.md`.

## Blockers / Unknowns

- The answer card's own buttons (Think Deeper, Ask a Follow-up, a document) could not be pressed by the robot from the
  Shortcuts app: the taps reached ShortcutsUI's card window and started nothing, while Done worked. A tap by hand
  (Simulator or his phone) settles row `3f449a74d54f8193a750d1099b83a8c5`.
- Apple's model wrote labels for sources it was not given: the pet-deposit answer of 2026-10-20 20:20 cites [S1], [S5]
  and [S6] against a three-source citation map (A17 trace, line "Citation map (standard, 3 sources)"), and the answer
  shows [S5] and [S6] as plain text. `AgenticOrchestrator.danglingCitations` finds such labels, and
  `RAGService.swift` (search "This logs rather than rewrites") only logs them, for Deep Think's reasoning trace, by
  the 2026-08-19 reasoning written there. No roadmap row covers a Standard answer's invented labels; filing one
  (v5.7, test 2: citations are advertised) and deciding drop or mark is open.
- `AnswerQualityEvaluationTests` (untracked) ran once: Apple's Evaluations framework and its model judge work in the
  iOS 27.0 Simulator, but the 0.15 correct was over 6 of the 25 fixtures (the shown engine held the free plan). It now
  imports with an engine of its own on a Pro plan store and removes its library at the end and any earlier one at the
  start; that version has not been compiled. Rerun: `build57.sh build-for-testing`, then
  `TEST_RUNNER_OI_MODEL_EVALS=1 ... build57.sh test-without-building <log>
  -only-testing:OpenIntelligenceTests/AnswerQualityEvaluationTests`.
- The minimum score is relative (the re-ranker rescales each question's scores to 10 to 90); making it absolute would
  be a retrieval change for the benchmark, not a settings change.
- His phone: the rows in the asks list. Mac rows need his go-ahead for a development build on his Mac.

## Exact Next Action

Make the text an answer item hands to Shortcuts and other apps name what its labels point at, the way the app's own
Share does: `OIAnswerEntity.sourceList` lists one line per label ("[S1] Juniper Flats Lease - Unit 4B.pdf, page 1")
through the resolution in `AnswerShareFormatter.sources(answer:evidence:retrievedChunks:)`. That needs the resolving
code (`CitationLinker` and the source list, not the App Store attribution) under `OpenIntelligence/Services/` so the
engine target compiles it too; check `OIEntityMappingTests` and add a case with [S1] and [S5] against two passages, then
build, run the suite, and rerun `testShortcutsAskThenCopy` on a new demo copy.
