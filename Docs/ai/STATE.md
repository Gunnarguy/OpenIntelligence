# Current State

Updated: 2026-10-21, about 07:10 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on
iPhone, iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout, level with `origin/main`
Last verified commit: 79c359c

Earlier detail is in git: `git show 1e379aa:Docs/ai/STATE.md` (late on 2026-10-20); the long record through 2026-10-10
is `Docs/Archive/STATE_record_through_2026-10-10.md`.

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
| Commits 2026-10-20 evening to 2026-10-21 morning | `1e379aa` labels number the passages an answer keeps, Copy and Shortcuts list sources, plain words on the Database tab, Device & Performance, Atlas, Siri. `fa80e71` labels in reading order; the whole-passage assembler chooses what fits before placing it (rank 2 was cut), the graph packer leaves placing to it, the needle rescue reads what was not reached; Private Cloud Compute passages in the envelope's order; Deep Think and Maximum steps take their rendered evidence to Private Cloud Compute. `0b2174b` engine badges only with Technical Details on, "Vocabulary", a trace line naming the candidates a whole-passage context kept. `cbc3e48` `AnswerQualityEvaluationTests`. `c1e3147` the unused `AppleEvaluationsBridge` deleted, `Docs/EVALS.md` corrected. `79c359c` an empty library answers without its tools. The PostDesk session's doc passes (`4bde793` to `11c07db`, `780d801`) were checked and pushed; it has nothing pending. |
| Rows closed 2026-10-21 | `40049a74d54f8113bb46eb9888627861` (label numbering), `40049a74d54f81f4b04ae5141899c808` (rank 2 cut). |
| Rows open from this work | `40049a74d54f81f3964fc8a7a0792cd5` Deep Think steps without evidence on Private Cloud Compute (fixed in `fa80e71`, closes on his device). `40049a74d54f81e0bd99fa0e5f5e4186` saved answers keep 12 passages (needs `ChatMessage.swift`). `40049a74d54f814eadbace9c62d87ef9` "Summarize my lease" put the Lisbon itinerary's flight table first, scored 0.980 (To Do). `3fe49a74d54f81ce84a1f0b59e2e1ec7` Settings jargon, last item "one title style per level" (next action). `3b549a74d54f814cbb06fa629417b657` Evaluations framework (see Blockers). |
| Open in 5.7 overall | Query the data source: Target Release v5.7, Status not Completed. What only he can do: `~/.agents/oi-robot/scripts/asks-for-gunnar-draft.md`. |
| Native Surfaces Catalogue | Version 28 at https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (118 rows, 24 seen working). Source copy: `~/.agents/data/openintelligence-5.7-closeout/Native-Surfaces-Catalogue.html`; read the live one first (`Artifact` read) in case it changed. Before publishing: `node --check` its script and count 118 ROWS. |

## Active Constraints

- **Waiting for his word (asked 2026-10-21 about 00:00):** a request with no `ModelExecutionPlan` skips the consent check
  (`RAGService.ensureCloudConsentIfNeeded` returns at once), while `FoundationModelRoutePolicy.determineRoute`'s planless
  branch can still pick Private Cloud Compute: under Hybrid when the prompt is over the device window, and every time with
  Private Cloud Compute picked in the model picker, even on Don't Allow. Planless callers: a question to a library with
  no documents, `generateDirectChatResponse`, `DocumentSummaryService` during imports (`InferenceConfig()` allows Private
  Cloud Compute by default). Proposed fix: no plan means on device, in `determineRoute`, plus tests and
  `Docs/PRIVACY_AND_ROUTING.md` and Atlas section 10. The permission check refused that edit and a message about it to
  another session (memory `route-policy-edit-refused-by-permission-check.md`); do not route around either. Also his
  call: whether a public roadmap row is filed. `Docs/PRIVACY_AND_ROUTING.md` already names the empty-library case.
- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18: `project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift` ("Must be done flawlessly"). `ChatMessage.swift`,
  `RAGAppIntents.swift`, `EntitlementStore.swift` and `KnowledgeContainer.swift`'s route were not named.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/`, `.codex/hooks*`, `.codex/config.toml` and
  `scripts/run_quality_matrix.py` (uncommitted on purpose) alone; edit Swift by script.
- Another session (PostDesk, "Demos") also commits docs in this checkout and does not push: before pushing, check every
  commit since `origin/main` for `[ci skip]`, no co-author line and docs-only paths.
- One `xcodebuild` at a time; stop only processes this session started. Don't build while World of Warcraft is open.
  `build57.sh` stops its own build when free disk falls under `GUARD_DISK_MB` (pass 1500) or free memory under 15%.

## Working Set

- Tools in `~/.agents/oi-robot/` (README inside): `~/.agents/oi-robot/scripts/build57.sh build-for-testing|test-without-building <log>
  [xcodebuild args]` (hosted tests on the test simulator), `demo_from_tree.sh <udid>` (demo copy of the working tree, Apple's
  model on), `setup_demo_device.sh`, `pvaudit.py <udid> <out> OpenIntelligenceScenes/<test>` (the robot, built in
  `/private/tmp/demodriver-pv-dd`), `answer_detail.py <udid> <since HH:MM>` (saved answers), `label_truth.py <udid>
  <since HH:MM>` (each saved label against full passage text from the app's FTS5 copy; a "doubtful" line is a lead:
  memory `label-check-needs-full-passages.md`). Pipeline examples: `~/.agents/data/openintelligence-5.7-closeout/pipelines/`.
- Robot scenes that worked on 2026-10-21: `testHouseholdStandard` (`TEST_RUNNER_OI_QSET=a`, 16 questions),
  `testHouseholdLongMode` (`TEST_RUNNER_OI_Q=<question>`, one question in the household chat), `testAuditTour` (41
  photos of every tab and Settings page), `testDatabaseTour`. `testShortcutsAskThenCopy` fails on the Shortcuts search
  field ("Neither element nor any descendant has keyboard focus") after a new demo copy; it passed once on a retry.
- Latest photos: `~/.agents/data/openintelligence-5.7-closeout/robot-2026-10-21/settings-tour/` (09 to 41 are Settings)
  and `database-tour/`.
- Simulators (check `xcrun simctl list devices` first; DeviceHub has deleted every simulator several times):
  `OI 5.7 tests` `0034D4D8-8443-4503-AE3F-57F3BB1FC89C` (hosted tests, named in `build57.sh`), `OI 5.7 A17 Pro`
  `A3DDC13D-2EAA-40E4-B562-FA5E0E4FDDC8` (demo copy `2e669de` of the tree at `0b2174b`, the household library; its trace is
  `Documents/pipeline_trace.log` in the app's container).
- `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift`: opt-in, run with
  `TEST_RUNNER_OI_MODEL_EVALS=1 GUARD_DISK_MB=1500 OI_SCRATCH=/private/tmp bash ~/.agents/oi-robot/scripts/build57.sh
  test-without-building <log> -only-testing:OpenIntelligenceTests/AnswerQualityEvaluationTests` (about 7 minutes;
  `TEST_RUNNER_OI_EVAL_TOPK=<1..12>` sets passages); the report is the `.xcevalresult` in the run's `.xcresult`.

## Verification (2026-10-21, output read)

- On `79c359c`'s tree: `build57.sh build-for-testing` -> `TEST BUILD SUCCEEDED`, no warning near the change;
  `test-without-building` -> `Executed 1338 tests, with 6 tests skipped and 0 failures` (06:51).
- `python3 scripts/verify_doc_claims.py` -> every claim matches; `python3 .claude/codemap/codemap.py check` -> 0 errors;
  `python3 scripts/secret_scan.py` -> clean.
- Robot on demo copies of the tree: `testHouseholdStandard` -> trace with 49 queries and no "were numbered differently"
  line; `testHouseholdLongMode` "Summarize my lease." -> "Whole-passage context keeps candidates [1, 3, 5, 6, 4, 2] of
  6", and a lease-versus-gym notice comparison -> "[1, 3, 5, 7, 9, 11, 12, 10, 8, 6, 4, 2] of 17"; `testAuditTour` ->
  no engine badges or Live System Monitor with Technical Details off, "Vocabulary" on the Apple Intelligence page.
- `AnswerQualityEvaluationTests` -> "imported 25 of 25 fixtures", "correct: 0.3 over 20 cases" (0.25 with 12 passages),
  passed on its 0.2 floor.

## Blockers / Unknowns

- The planless Private Cloud Compute gap (Active Constraints) waits for his word.
- Private Cloud Compute is not reachable from the iOS Simulator, so `fa80e71`'s envelope-order and Deep Think evidence
  fixes are code_verified only; his device closes row `40049a74d54f81f3964fc8a7a0792cd5`.
- For him, from the PostDesk session's canonical pass (read in code, not verified here, no rows filed): `CLAUDE.md`
  line 7 says only the final answer may reach Private Cloud Compute, while
  `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` section 8 says, from the code, that under Hybrid every synthesis
  can be planned there; and three pieces of code look unreachable (the deterministic route rule in
  `ModelExecutionPlanner.swift`, `VerificationGateService.checkRetrievalConfidence`, `muMargin`).
- The answer evaluation's 0.3 is mostly its dataset's: the five synthetic exact fixtures never say what their value
  measures ("| Primary answer | 14.3 US gal |"), and four references are bare keys. Row `3b549a74d54f814cbb06fa629417b657`
  needs reference answers for the household sample set's questions, and him opening a report in Xcode
  (`~/.agents/data/openintelligence-5.7-closeout/evals-2026-10-21/`); opening Xcode has made DeviceHub delete every
  simulator before, so copy simulator data out first.
- The answer card's own buttons from the Shortcuts app need a tap by hand (row `3f449a74d54f8193a750d1099b83a8c5`).

## Exact Next Action

Close the Settings jargon row's last item, "one title style per level" (row `3fe49a74d54f81ce84a1f0b59e2e1ec7`): list the
font each Settings page gives its card titles and section headers (in `OpenIntelligence/Features/Settings/`, each
`Text("...")` title with the `.font(` that follows), pick one style per level from the most common, apply it by script,
then build, run the suite, and photograph every Settings page with `testAuditTour` (photos 09 to 41) before closing the
row. On Device & Performance, for one, "Reading PDFs and Images" is `.caption.weight(.medium)` while "Active Device" and
"How Much the Model Reads" are drawn much larger (`robot-2026-10-21/settings-tour/24-*.png` and `25-*.png`).
