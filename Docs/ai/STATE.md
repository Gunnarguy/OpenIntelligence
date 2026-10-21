# Current State

Updated: 2026-10-21, about 13:30 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on
iPhone, iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout, level with `origin/main`
Last verified commit: 15b908a plus this session's commit (the planless route fix and the Settings heading style)

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
| Rows closed 2026-10-21 | `40049a74d54f8113bb46eb9888627861` (label numbering), `40049a74d54f81f4b04ae5141899c808` (rank 2 cut), `3fe49a74d54f81ce84a1f0b59e2e1ec7` (Settings jargon, its last item: one heading style inside a card). |
| Rows open from this work | `40049a74d54f81f3964fc8a7a0792cd5` Deep Think steps without evidence on Private Cloud Compute (fixed in `fa80e71`, closes on his device). `40049a74d54f81e0bd99fa0e5f5e4186` saved answers keep 12 passages (needs `ChatMessage.swift`). `40049a74d54f814eadbace9c62d87ef9` "Summarize my lease" put the Lisbon itinerary's flight table first, scored 0.980 (To Do). `3b549a74d54f814cbb06fa629417b657` Evaluations framework (see Blockers). |
| Open in 5.7 overall | Query the data source: Target Release v5.7, Status not Completed. What only he can do: `~/.agents/oi-robot/scripts/asks-for-gunnar-draft.md`. |
| Native Surfaces Catalogue | Version 28 at https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (118 rows, 24 seen working). Source copy: `~/.agents/data/openintelligence-5.7-closeout/Native-Surfaces-Catalogue.html`; read the live one first (`Artifact` read) in case it changed. Before publishing: `node --check` its script and count 118 ROWS. |

## Active Constraints

- **Done 2026-10-21 at his word ("do consent fix first"):** a request with no `ModelExecutionPlan` now runs on the
  device (`FoundationModelRoutePolicy.determineRoute`), so nothing reaches Private Cloud Compute without the consent step.
  `PlanlessRouteTests` pins it. Not run on a device. A question to an empty library longer than the device window now
  stays on the device and may fail for length (read in code, not run). Still his call: whether a public roadmap row is
  filed for it (none was). The developer diagnostics hub's "Maximum Reasoning" row can now only read N/A.
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
  `OI 5.7 tests` `F1450853-CF0F-4E8D-87E2-F6B8F7E0241D` (made 2026-10-21 10:40, hosted tests, named in `build57.sh`; the
  Debug app is installed on it past onboarding, used for the Settings tour). The A17 `A3DDC13D-...` and the old test
  simulator were deleted at 10:31:20 with every other shut-down simulator (booted ones were kept; `~/.agents/MACHINE-MAP.md`),
  so the demo copy and household library are gone. A new simulator's first suite run fails three AtlasLabelingTests until
  it has fetched its language data (`com.apple.linguisticdata ... not entitled` in the log); the next run passes.
- `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift`: opt-in, run with
  `TEST_RUNNER_OI_MODEL_EVALS=1 GUARD_DISK_MB=1500 OI_SCRATCH=/private/tmp bash ~/.agents/oi-robot/scripts/build57.sh
  test-without-building <log> -only-testing:OpenIntelligenceTests/AnswerQualityEvaluationTests` (about 7 minutes;
  `TEST_RUNNER_OI_EVAL_TOPK=<1..12>` sets passages); the report is the `.xcevalresult` in the run's `.xcresult`.

## Verification (2026-10-21, output read)

- About 13:20, the S-row fixes (Private Cloud Compute copy, claim coverage fallback, saved answers keep cited passages,
  Find Passages clamp, Mac Vision thermal limit, real-speech test, `@rpath` install name, trace footer): full suite on the
  build before the last edits -> `Executed 1356 tests, with 8 tests skipped and 1 failure` (GlossaryTests: the new
  Private Cloud Compute entry ran 376 characters against 360); after shortening it and the reviewer's fixes,
  `build-for-testing` -> `XCODEBUILD_EXIT=0` and GlossaryTests, ClaimCoverageFallbackTests, SavedAnswerPassagesTests,
  VersionHistoryTests, SpotlightItemsTests, WhatsNewCoverageTests -> `Executed 38 tests, with 0 failures`.
  `verify_doc_claims.py`, `codemap.py check` (0 errors), `secret_scan.py` clean.
- About 11:00, on this session's tree (planless route fix, Settings headings): `build57.sh build-for-testing` ->
  `TEST BUILD SUCCEEDED`, 0 errors, no warning in the changed files; full `test-without-building` -> `Executed 1341 tests,
  with 7 tests skipped and 1 failure`, the one being VersionHistoryTests (the bundled `VersionHistory.md` had not been
  copied from `Docs/USER_CHANGELOG.md`); after copying it and rebuilding, `-only-testing` VersionHistoryTests,
  PlanlessRouteTests and AtlasLabelingTests -> `Executed 32 tests, with 0 failures`. `codemap.py check` -> 0 errors.
  `testAuditTour` on the Debug build -> 41 photos in
  `~/.agents/data/openintelligence-5.7-closeout/robot-2026-10-21/settings-tour-titles/` (16, 24, 25, 32, 33 show the
  headings). A reviewer found no consented Private Cloud Compute call that arrives without a plan, and no other planless
  Private Cloud Compute session.
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

Run the device session with him: `~/.agents/data/openintelligence-5.7-closeout/device-checklist-2026-10-21.md` sorts the 98
In Progress v5.7 rows (65 iPhone, 16 Mac, 3 App Store Connect, 3 need engineering, 11 unclear), fastest first. After each
group he does, copy the trace off the phone (`xcrun devicectl device copy from --device 00008140-001130DA1863C01C
--domain-type appDataContainer --domain-identifier Gunndamental.OpenIntelligence --source Documents/pipeline_trace.log
--destination <file>`; the phone has a development build, bundle version 150) and close the rows it proves. Rebuild to the
phone first so it carries this afternoon's commit (`~/.agents/oi-robot/scripts/builddevice.sh <log>`, then `devicectl
device install app`). Then the S-row fixes need their own closes: `SpeechTranscriptionTests` on the iPhone (skips in the
Simulator; also proves the `@rpath` install-name change), a fanless-Mac import for the thermal limit.

Decisions waiting for him: the Spotlight document tap (dropping the app item opens the document but cuts its Siri and
Apple Intelligence link; row `3ff49a74d54f81fea954d76ff336595e`); the OCR render-scale patch, deferred unmeasured to
`~/.agents/data/openintelligence-5.7-closeout/deferred-5.8/`; clearing the 519 iCloud conflict copies his phone's trace
reports; whether the research To Do rows move to Future Backlog. Store notes (iOS ones at 4,038 characters, Apple's limit
believed 4,000, unconfirmed) and the in-app What's New (one list for both platforms, 15 items, last edited 2026-10-15) are
written once, at the end, from the final changelog.
