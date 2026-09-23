# Current State

Updated: 2026-09-23, 16:05 PT (every change since 5.3 is 5.4; 5.4's user-facing copy is function and performance only; the build to submit is the first Xcode Cloud build after the copy commit that follows `3ad7ed6`)
Branch/worktree: `main`, primary checkout
Last verified commit: 3ad7ed6

## Objective

Ship 5.4 with every change since 5.3, including the answer work of 2026-09-23. The owner's words
that day: 5.4 is the version that exists in App Store Connect, there is no 5.5, and every change
made since 5.3 is 5.4. The answer work was first pushed as 5.5 (`faed0d6`, Xcode Cloud build 475)
and folded back into 5.4 the same day (`Docs/ai/DECISIONS.md`, 2026-09-23).

## Status: 5.4

- 5.3 live on iOS and macOS (build 464). 5.4 on both platforms: `PREPARE_FOR_SUBMISSION`, release
  MANUAL, build 474 attached (`VALID`). **474 does not carry the answer work**, and build 476
  (`3ad7ed6`) still shows the plans and ratings items in the in-app What's New; the build to attach
  and submit is the first Xcode Cloud build after the copy commit that follows `3ad7ed6`. **Never
  submit build 469** (its setup plans sheet crashed). Build 475 is 5.5 in TestFlight and unused.
- **5.4's user-facing copy is function and performance only** (owner, 2026-09-23): the release notes
  (both `fastlane/metadata*/en-US/release_notes.txt`, identical), `WHATS_NEW.md`,
  `Docs/USER_CHANGELOG.md` + bundled copy and the in-app "5.4" entry describe the answer work and
  nothing else. Plans, paywall, rating request and Maximum cap stay in `CHANGELOG.md` only. The new
  notes reach App Store Connect with `scripts/asc_prepare_release.rb 5.4 <build> --apply` (attaches
  the build and writes What's New to both platforms), then `scripts/asc_listing_extras.rb 5.4 --apply`.
- Three subscription descriptions are still wrong and the API refuses them (HTTP 409, ACTIVE). Web
  page targets: Pro Annual "Annual billing for 1,000 documents and 10 libraries.", Pro Monthly
  "Monthly billing for 1,000 documents and 10 libraries.", Lifetime "Permanent Pro - 20 Libraries +
  Unlimited Documents". Submit both Pro subscriptions with 5.4 so their images get reviewed.
- On submission: `in_review` for both platforms in `Docs/SHIPPED_VERSION.json`, push. On release:
  date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md`, copy it byte-for-byte to
  `OpenIntelligence/Resources/VersionHistory.md`, remove `<!-- unreleased -->` from `## 5.4` in
  `CHANGELOG.md`, and only then open the next version above it; set `app_store` and `preparing`, push.
- Scheduled: 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`.

## The answer work in 5.4 (2026-09-23)

Measured on the macOS 27.0 Debug build (M3 Pro, on-device model, `Docs/HOW_IT_WORKS.md` only):
last streamed word to finished answer, Standard.

| Question | Before | After |
|---|---|---|
| What file types does OpenIntelligence handle? | 163.8 s, 19.4 s | 0.33 s |
| How many verification checks does OpenIntelligence run? | 58.3 s | 0.21 s |
| Which embedding model does OpenIntelligence use for retrieval? | 37.6 s | 0.15 s |
| Explain how OpenIntelligence decides when to use Private Cloud Compute | 0.12 s | 0.10 s |

The wait was `SourceOnlyAnswerService` (two structured model calls) on answers whose gates passed;
the 163.8 s run spent 163.5 s in the draft call and ended in a context overflow. Stream probe, after:
Deep Think "explain" text from 50.0 s of 67.7 s (before: nothing until the end), one streamed call;
Maximum from 34.6 s of 44.5 s. Details and file references: `CHANGELOG.md` `## 5.4`.

Code: Standard skips SourceOnly when gates pass (`RAGService.standardSkipsSourceOnlyCheck`); draft
limited to 1,024 tokens; `RAGService.finishAnswerNow()` / `runFinishableStage`;
`AgenticOrchestrator.execute` parks the chat handler (`LLMStreamingContext.finalAnswerHandler` /
`answerHandler`), four final-answer calls stream; `ChatScreen` checking state, one queued question,
haptic, `ChatAnswerNotice` badge, clock restart, step-driven background progress, expiry keeps text;
structured short answers stream; harness `--rag-validation-stream-probe`; gating token
`finished_early_by_person`. Copy: `CHANGELOG.md` `## 5.4`, `Docs/USER_CHANGELOG.md` + bundled copy,
`WHATS_NEW.md`, and the one "5.4" entry in `WhatsNewStore.swift` (three items, the answer work only).

Notion rows, all In Progress, `v5.4` (moved from `v5.5` on 2026-09-23 with a dated note in each):
Standard stall https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142 , off-screen signals
https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3 , streaming
https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767 . Future Backlog: sample answers "Partially
Verified" without Apple Intelligence https://app.notion.com/p/3e449a74d54f8170a3cbfb570a41d0a5 ; Deep
Think research replacing a full synthesis with a one-line answer that can be wrong
https://app.notion.com/p/3e449a74d54f813db884d9471b25bdb3 (High). The `v5.5` option stays on Target
Release with no rows.

## Active Constraints

- **No new version heading while 5.4 is unsubmitted** (`Docs/ai/DECISIONS.md`, 2026-09-23).
  `ci_post_clone.sh` stamps every Xcode Cloud build from the first numbered heading in `CHANGELOG.md`.
- **A local build calls itself 5.3 (150)** unless built with `MARKETING_VERSION=5.4`: the project
  file is stamped only in Xcode Cloud. The command-line override edits no file.
- **Guard memory on builds** (18 GB Mac): `-jobs 2`, stop at 15% free. Build from `/private/tmp/oi-src`,
  synced with rsync excluding `BenchmarkRuns/`, `.simulator-smoke.nosync/`, `Benchmarks/run/`,
  `.build` anywhere (`OpenIntelligence/swift-transformers/.build` is 150 MB and gets bundled),
  `/.device-smoke.nosync/`, `/build/`.
- **The iOS simulator does not generate**; timing and streaming run on the unsigned macOS Debug build,
  which writes `~/Library/Application Support/OpenIntelligence`. The UI test library is parked at
  `/private/tmp/oi-ui-appsupport-2026-09-23`.
- Disk: 96%, about 18 GB free. At 96% (2026-08-20) model assets were evicted.
- App Store Connect writes are the owner's. swift-format rewrites Swift files edited with Edit/Write;
  files with `"""` are edited by script. Commit to `main`, no AI trailer.

## Working Set

- `CHANGELOG.md`, `Docs/USER_CHANGELOG.md`, `OpenIntelligence/Resources/VersionHistory.md`,
  `WHATS_NEW.md`, `OpenIntelligence/Features/Onboarding/WhatsNewStore.swift`: the 5.4 copy after the fold.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: skip rule, `finishAnswerNow`, `runFinishableStage`, SourceOnly task and logs, `finalizeResponse` marker.
- `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`: draft cap and token-use log.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`: `execute` wrapper, streamed and finishable sites.
- `OpenIntelligence/Services/LLM/LLMService.swift`: `LLMStreamingContext.finalAnswerHandler`/`answerHandler`.
- `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift`: streamed direct answer.
- `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift`, `ChatComposerV2.swift`, `MessageListV2.swift`, `ChatAnswerNotice.swift`; `OpenIntelligence/App/ContentView.swift` (badge).
- `OpenIntelligenceTests/Services/RAG/Orchestration/SourceOnlyStandardGateTests.swift`, `ResponseMetadataGatingTests.swift`.

## Verification (2026-09-23, output read)

- Before the fold: full iOS suite on simulator `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6` -> 500 tests,
  0 failures, 3 skipped; macOS Debug build -> no warnings in changed files; `build_simulator_smoke.sh`
  -> succeeded.
- After the fold: `xcodebuild test` on the same simulator, `VersionHistoryTests`,
  `WhatsNewCoverageTests`, `SourceOnlyStandardGateTests`, `ResponseMetadataGatingTests` -> 12 tests,
  0 failures, TEST SUCCEEDED. `repoos_router.py preflight` -> active release `v5.4`, last shipped
  `v5.3`, changelog target `## 5.4`, Notion target `v5.4`; `test_repoos_router.py` -> OK;
  `test_enforce_docs_hook.sh` -> 16 passed; `secret_scan.py` -> clean; Notion -> `v5.4` 6 rows, `v5.5` 0.
- Accuracy A/B, QASPER 25, greedy (`BenchmarkRuns/LEDGER.md`, 2026-09-23 entry): before 6/25, after
  11/25; 0 pass-to-miss; SourceOnly replaced 0 answers in either run. The gain is not the change's.
- Xcode Cloud build 475 (`faed0d6`, 5.5) -> SUCCEEDED, `VALID` on iOS and macOS; superseded.
- A local Debug build, `MARKETING_VERSION=5.5`, was installed on the owner's iPhone 16 Pro Max over
  Wi-Fi (`devicectl device install app`, 17 s) and launched; it is replaced by a 5.4 build after the fold.
- **Not verified:** anything on a device (haptic, badge on a phone, clock restart, background expiry,
  streaming feel); the "Checking sources…"/"Refining…" label and unlocked composer in the running app.

## Blockers / Unknowns

- Owner: once the first build after the copy commit is `VALID`, run
  `zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 <build> --apply'` and then
  `zsh -ic 'ruby scripts/asc_listing_extras.rb 5.4 --apply'` (the permission classifier refused both
  from an agent earlier on 2026-09-23); whether macOS needs a tab signal other than the badge.
- Cleanup, this session's test data only: `/private/tmp/oi-ui-appsupport-2026-09-23` (the Mac UI
  test library), the simulator above (`xcrun simctl delete 6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`),
  frozen apps in `/private/tmp/oi-bench/`.

## Exact Next Action

When the first Xcode Cloud build after the copy commit is `VALID` as 5.4 on both platforms (list the
workflow's build runs, then `builds?filter[version]=<number>`), run the device checks in the "Closes
when" sections of the three v5.4 rows, on that build or on the local 5.4 Debug build on the owner's
iPhone. Close each row that passes. The owner then attaches that build to 5.4 in place of 474 and
submits.
