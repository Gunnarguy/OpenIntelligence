# Current State

Updated: 2026-10-21, about 02:05 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on
iPhone, iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: fa80e71

Earlier detail is in git: `git show 1e379aa:Docs/ai/STATE.md` (late on 2026-10-20) and the copies it names; the long
record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row** ("Everything into 5.7", 2026-10-18, his PROCEED: IMPLEMENT; decisions in auto
memory `everything-into-5-7.md`). On 2026-10-19: "just go nuts and close all of the rest of the shit out please. like
everything." On 2026-10-20: "if it can be added, then we add it if it needs to be fixed, then we fix it ... apply the
absolute best practices using apples latest API frameworks." A row closes on a scripted iOS 27 Simulator check when the
defect is not about the phone itself; memory, background tasks, iCloud, signing and Private Cloud Compute rows close
only on his phone or Mac.

## Status

| What | Where it stands |
|---|---|
| Last commit | The one that contains this file, after `fa80e71`: the Execution Profile badges only with Technical Details on (they wrapped as "CP U" and "AN E"), "Vocabulary" for the Gazetteer row, and a trace line naming the candidates a whole-passage context kept (`RAGService.candidatePlaces`). |
| Before it | `fa80e71` (labels in reading order; the rank-2 fix in the assembler, the graph packer and the rescue; Private Cloud Compute envelope order; Deep Think evidence on Private Cloud Compute; two Device & Performance cards), `1e379aa`, and the PostDesk session's doc commits through `11c07db`. |
| Rows | Closed 2026-10-21: `40049a74d54f8113bb46eb9888627861` (label numbering) and `40049a74d54f81f4b04ae5141899c808` (rank 2 cut; trace lines "keeps candidates [1, 3, 5, 6, 4, 2] of 6" and "[1, 3, ..., 4, 2] of 17"). Filed: `40049a74d54f814eadbace9c62d87ef9` ("Summarize my lease" put the Lisbon itinerary's flight table first, scored 0.980; To Do). `40049a74d54f81f3964fc8a7a0792cd5` (Deep Think steps without evidence on Private Cloud Compute): In Progress, closes on his device. `40049a74d54f81e0bd99fa0e5f5e4186` (saved answers keep 12 passages): To Do, needs `ChatMessage.swift`. `3fe49a74d54f81ce84a1f0b59e2e1ec7` (Settings jargon): open; the last item is one title style per level (next action). |
| Native Surfaces Catalogue | Version 28 at https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (118 rows, 24 seen working). Source: the session scratchpad's `Native-Surfaces-Catalogue.html`; read the live one first if that is gone. |

## Active Constraints

- **Waiting for his word, asked 2026-10-21 about 00:00:** a request with no `ModelExecutionPlan` skips the consent check
  (`RAGService.ensureCloudConsentIfNeeded` returns at once) while `FoundationModelRoutePolicy.determineRoute`'s planless
  branch can still pick Private Cloud Compute: under Hybrid when the prompt is over the device window, and every time
  with Private Cloud Compute picked in the model picker, even on Don't Allow. Planless callers: a question to a library
  with no documents, `generateDirectChatResponse`, `DocumentSummaryService` during imports (`InferenceConfig()` allows
  Private Cloud Compute by default). Proposed fix: no plan means on device, in `determineRoute`. The permission check
  refused that edit and a message about it to the PostDesk session; don't route around either. Also his call: whether a
  public roadmap row is filed. `Docs/PRIVACY_AND_ROUTING.md` (PostDesk's `11c07db`, pushed) already names the empty-library
  case publicly; it does not yet say the exception covers every planless request.
- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18: `project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift` ("Must be done flawlessly"). `ChatMessage.swift`,
  `RAGAppIntents.swift` and `KnowledgeContainer.swift`'s route were not named.
- The PostDesk session ("Demos") still has a canonical docs pass to land (CANONICAL, LIMITATIONS, RAG_TECHNICAL,
  STUDY_GUIDE, EdgeToEdge, the Audio guides, Terra). It commits only its own paths with `[ci skip]` and does not push;
  check each message and push them.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/`, `.codex/hooks*`, `.codex/config.toml`, and
  `scripts/run_quality_matrix.py` (uncommitted on purpose) alone; edit Swift by script.
- One `xcodebuild` at a time; stop only processes this session started. `build57.sh` stops its own build when free
  disk falls under `GUARD_DISK_MB` or free memory under 15%.

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: `extractRelevantSentencesOffMain` (`packedOrder`,
  `numberedLabels`), `candidatesPastThePacked`, `passages(_:inTheOrderOf:)`, the Standard path (`placedForAttention`).
  `RAGEngine.swift` `assembleContext`; `ContextPackingService.swift` `pack`; `AgenticOrchestrator.swift`, the
  `.privateCloudCompute` case of a step's plan.
- Tests: `CitationLabelNumberingTests` (10 tests), `ContextPackingServiceTests` (now on the main actor).
- Tools in `~/.agents/oi-robot/scripts/`: `label_truth.py <udid> <since HH:MM>` resolves each saved label the way a tap
  does and compares it with the full passage text from a copy of the app's FTS5 database (`chunk_id` is
  `<document id>_<chunk index>`); a saved passage is cut to 600 characters and the extractor reads about 250 more on
  each side (`DocumentChunk.contextText`), so a "doubtful" line is a lead, not a verdict.
- Simulators: `OI 5.7 tests` `0034D4D8-8443-4503-AE3F-57F3BB1FC89C` (hosted tests, `build57.sh`), `OI 5.7 A17 Pro`
  `A3DDC13D-2EAA-40E4-B562-FA5E0E4FDDC8` (demo copy `64f63c9`, the household library). Check `xcrun simctl list devices`
  first; DeviceHub has deleted every simulator several times.
- Uncommitted on purpose: `scripts/run_quality_matrix.py`, the untracked `AnswerQualityEvaluationTests.swift`.

## Verification (2026-10-21, output read)

- `build57.sh build-for-testing` then `test-without-building` on the reviewed tree -> `Executed 1338 tests, with 6
  tests skipped and 0 failures` (00:29). After `ContextPackingServiceTests` moved to the main actor: `build-for-testing` -> 0 warnings in that
  file; `test-without-building -only-testing:` it and `CitationLabelNumberingTests` -> `Executed 15 tests, with 0 failures`.
- `demo_from_tree.sh A3DDC13D-...` -> `INSTALLED demo copy of 64f63c9`; robot `testHouseholdStandard` passed; the trace
  holds 49 queries and no "were numbered differently" line; `label_truth.py` -> 50 labels, 37 match, 12 doubtful, 1 past
  the 12 saved passages. Earlier runs: 42 labels with 11 doubtful (candidate-order numbering) and 36 with 10
  (reading order), all by the same measure.
- Robot `testAuditTour` -> photo `tour3/25`: "Reading PDFs and Images", no Live System Monitor, the language list.
- On the tree of this commit: `build-for-testing` -> no warning in the changed lines; the suite -> `Executed 1338 tests, with
  6 tests skipped and 0 failures` (01:43); demo copy `2e669de`; robot `testAuditTour` -> photos `tour4/25` (no engine
  badges with Technical Details off) and `tour5/19` ("Vocabulary"); `testHouseholdLongMode` with `OI_Q` -> the two trace
  lines in Rows above. `testShortcutsAskThenCopy` failed four times on the Shortcuts search field ("Neither element nor
  any descendant has keyboard focus") after a new demo copy, so a single question goes through `testHouseholdLongMode`.
- `python3 scripts/verify_doc_claims.py` -> 1346 claims match; `codemap.py check` -> 0 errors; `secret_scan.py` -> clean.
- A refuting review of the label-order and rank-2 change found a blocker (the graph packer reordered first) and six
  smaller points; each is fixed or recorded in `CHANGELOG.md` 5.7.

## Blockers / Unknowns

- The planless Private Cloud Compute gap above waits for his word.
- Private Cloud Compute is not reachable from the iOS Simulator, so the envelope-order and Deep Think evidence fixes are
  code_verified only; his device closes row `40049a74d54f81f3964fc8a7a0792cd5`.
- The answer card's own buttons from the Shortcuts app need a tap by hand (row `3f449a74d54f8193a750d1099b83a8c5`).
- `AnswerQualityEvaluationTests` has not been rerun since it got its own engine and cleanup.

## Exact Next Action

Close the Settings jargon row's last item, "one title style per level" (row `3fe49a74d54f81ce84a1f0b59e2e1ec7`): list the
font each Settings page gives its card titles and section headers (`grep -n 'Text(\"' ` with the `.font(` that follows,
in `OpenIntelligence/Features/Settings/`), pick one style per level from the most common, apply it by script, then build,
run the suite and photograph every Settings page with `testAuditTour` (photos 09 to 41) before closing the row. Device &
Performance, for one, "Reading PDFs and Images" is `.caption.weight(.medium)` while "Active Device" and "How Much the
Model Reads" are drawn much larger (photos `tour5/24`, `tour5/25`).
