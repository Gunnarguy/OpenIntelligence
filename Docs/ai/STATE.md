# Current State

Updated: 2026-10-20, about 05:30 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: 0f405ca

Earlier detail is in git: `git show 6906546:Docs/ai/STATE.md` (the night of 2026-10-19) and the copies it names; the
long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row** ("Everything into 5.7", 2026-10-18, his PROCEED: IMPLEMENT; decisions in auto
memory `everything-into-5-7.md`). On 2026-10-19 he said "just go nuts and close all of the rest of the shit out please.
like everything." A row closes on a scripted iOS 27 Simulator check when the defect is not about the phone itself;
memory, background tasks, iCloud, signing and Private Cloud Compute rows close only on his phone.

## Status

| What | Where it stands |
|---|---|
| Rows closed 2026-10-20 | 22, each with a dated note and its evidence (Notion: Status Completed, Completed 2026-10-20). Among them: the camera stack out of Release builds, the setup plans crash, the free Maximum cap, Gate E on right answers, the prompt outline, the held lookup, streaming Markdown, `$300. 00`, cut sentences, the three wrong sample answers, "1 lb", Deep Think and Maximum streaming, citation taps, the Verified badge, Fact Check asterisks and quotes, "Ask About a Document" scope, scope by vector, the Shortcuts action engine, the Spotlight result (passage path). |
| Commits 2026-10-20 | `fe4e6ac` (camera overlay geometry Debug-only: `2fae850` broke the iOS Release build), `3a9fcb8` (the detector Debug-only), `1c913bf` (Fact Check claim text, Gate E's floor detail), `37330a9` ("without" in a passage reads as the opposite only when the claim names its object; review follow-ups), `0f405ca` (Spotlight passage titles). |
| Filed 2026-10-20 | `3ff49a74d54f8151bbeefe6baf3396ec` (Future Backlog): Deep Think and Maximum bring other documents into a one-document answer (the gym's "email or front desk" told as the lease's), every gate passes, and their Fact Check reads Not checked under a green Verified. `3ff49a74d54f81fea954d76ff336595e` (v5.7): tapping a document in Spotlight asked for a Question; a passage opens it. |
| In flight at handoff | Robot scene `testTicketsLibrary` on the A17 simulator (the 8.7 MB `Support Tickets.jsonl`: cancel during a part, import again, ask about ticket 1618's QX-58 bulb). It is for the JSONL rows below. |
| Open in 5.7 | About 140 rows (query the data source: Target Release v5.7, Status not Completed). The batched list of what only he can do is `~/.agents/oi-robot/scripts/asks-for-gunnar-draft.md`. |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18 (`project.pbxproj`, `WorkspaceSyncService.swift`, `BNNSVectorDatabase.swift`,
  `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`): "Must be done flawlessly ... only if
  they're genuine full and well rounded improvements." On 2026-10-20 Claude Code's permission check refused an
  `xcodebuild` against an edited `project.pbxproj` ("Protected-Scope IaC Apply"), so the engine install-name change is
  a patch, `~/.agents/oi-robot/scripts/engine-rpath-embed.patch`, not applied; it needs his explicit word in a session.
- `RAGAppIntents.swift` was not named; its ten App Shortcut slots are all used. The Spotlight document tap waits on it.
- App Store Connect writes and public pages only at his word. Never delete docs, benchmark runs, Notion rows or agent
  histories; no co-author lines; commit by name; leave `.agents/skills/` and `.codex/hooks*` alone; edit Swift by script.
- A development build on his Mac opens his real libraries: don't launch one without asking. Never tap the plan sheet's
  purchase buttons in a simulator.
- Verify Apple API claims on developer.apple.com (`.../tutorials/data/documentation/<path>.json`) and date them.
- Every change of the night had a refuting review before or right after its commit; the first one found a claim-pairing
  blocker in `1c913bf`'s first draft. Keep doing that for regexes over claim text.

## Working Set

- Uncommitted, untested: `scripts/run_quality_matrix.py` (`--simulator <udid>` runs the headless harness in an iOS
  Simulator; needs the Debug copy `bench_build.sh` builds); the untracked test file AnswerQualityEvaluationTests.swift,
  under OpenIntelligenceTests/Services/Evaluation (Apple's Evaluations framework, opt-in with `TEST_RUNNER_OI_MODEL_EVALS=1`; compiles with no warning, never run).
- Tools: `~/.agents/oi-robot/` (README inside): the robot (`demodriver/`, an XCUITest project that drives the installed
  app by bundle id, including through AppIntentsTesting) and the scripts (`pvaudit.py`, `tracefollow.py`,
  `dump_threads.py`, `oi_prefs.sh`, `demo_from_head.sh`, `build57.sh`, `guard.inc`, `oi57-build.sh`). The live copies
  are `/private/tmp/demodriver-pv` and the session scratchpad; `/private/tmp` is cleared on a reboot.
- A17 simulator `OI 5.7 A17 Pro` `0F072FEC-D590-4651-BCA8-D5D8D01E25FC` (iPhone 15 Pro, iOS 27.0): the demo copy of
  `37330a9` (Release, Apple's model on), libraries General (the three sample guides), Product Notes, Survey, Household
  (the ten sample documents; the questions' facts are in `BenchmarkRuns/household_v1`), Tickets; a paid plan through
  the protection state `historicalPaidPurchase`. Its trace is `Documents/pipeline_trace.log` in the app's container.
- Test simulator `OI 5.7 tests` `0FBB8C16-CB05-4DF2-A018-670190834AB6`: the hosted unit tests (`build57.sh`).

## Verification (2026-10-20, output read)

- Full suite on `0f405ca`'s tree: `Executed 1272 tests, with 6 tests skipped and 0 failures` (iOS 27.0 Simulator).
- iOS Release builds for the Simulator at 01:26 and 01:36 PT: `BUILD SUCCEEDED`; `nm` on the binary finds 0 symbols of
  the ten camera and detector types, where the Debug build holds 24 to 1,430 of each.
- Robot scenes, read from `DEMO-STATE` lines, screenshots, saved conversations and the trace: `testFreshInstallPlans`,
  `testMaximumLimit`, `testHouseholdStandard` (sets a and b, 21 questions), `testHouseholdLongMode` (Deep Think and
  Maximum), `testHouseholdDetails` (twice), `testAskAboutADocumentWithTheModel`, `testActionsWithTheAppClosedAndOpen`,
  `testSpotlightOpensTheDocument`, `testSpotlightProbe` (three ways).
- `codemap.py check`: 0 errors. VersionHistory.md is byte-identical to USER_CHANGELOG.md.

## Blockers / Unknowns

- His phone (USB or in hand): the engine install-name patch's device test run; a document tapped in Spotlight; the rows
  in the asks list. Mac rows (NavigationView sheets, Services menu, menu bar ask box, Finder, Copy) need his go-ahead
  for a development build on his Mac.
- Deep Think and Maximum still mix documents on a one-document question (filed row); not started.
- Not established: whether Spotlight on a device runs Open Document when a document is tapped (the Simulator ran the
  Question prompt once and nothing once).

## Exact Next Action

Read the Tickets scene's result: `grep DEMO-STATE` in its `xcodebuild.log` (session scratchpad `tix1/`), the answer
with `python3 ~/.agents/oi-robot/scripts/dump_threads.py 0F072FEC-D590-4651-BCA8-D5D8D01E25FC 05:12`, and the trace
copy `tix1/trace.log` for "in N parts", "cancelled", "reach the embedding model's" and "[RAGEngine] Rerank ceiling".
Close what it shows of rows `3f549a74d54f8154b822e4eee927a961` (Cancel and a question from the file),
`3f449a74d54f8199b1fce61c8ff6af0d` (JSONL records), `3f549a74d54f81998d02e74ec246580e`, `3f549a74d54f81ffb2bce20895b1e7c3`
and `3ab49a74d54f81828278dbd7124eb7e4`, each against its own "Closes when". If the scratchpad is gone, run the scene
again with `pvaudit.py` from `~/.agents/oi-robot/scripts` after building the robot as its README says.
