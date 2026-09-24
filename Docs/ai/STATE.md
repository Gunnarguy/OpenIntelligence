# Current State

Updated: 2026-09-24, 09:55 PT (5.4 still in review with build 478; GitHub `v5.3.0` published as Latest, `v5.4.0` held as a draft)
Branch/worktree: `main`, primary checkout
Last verified commit: 1a228a6

## Objective

Ship 5.4 with every change since 5.3, including the answer work of 2026-09-23. The owner's words
that day: 5.4 is the version that exists in App Store Connect, there is no 5.5, and every change
made since 5.3 is 5.4. The answer work was first pushed as 5.5 (`faed0d6`, Xcode Cloud build 475)
and folded back into 5.4 the same day (`Docs/ai/DECISIONS.md`, 2026-09-23).

## Status: 5.4

- **In review on both platforms, build 478** (Xcode Cloud #478 from `c276b9a`), release MANUAL: after
  approval it waits for a release. Last submitted 2026-09-23 22:03 PT, after the listing's screenshots
  were replaced (9 iPhone, 7 iPad, 6 Mac; `Docs/Release/APP_STORE_METADATA_HISTORY.md`). Read back: both
  records `WAITING_FOR_REVIEW`, build 478 `VALID`, What's New the 1,604-character notes in the owner's
  voice. Submissions: iOS `0f601c16-8a6b-4d13-937d-c5a71803f6ce`, macOS `5a21fe94-a866-4c37-a412-a44f385f1b68`.
  Earlier submissions that evening (477 at 17:17, 478 at 18:40 and 21:00) were pulled at the owner's
  direction for the voice rewrite and the screenshots. 474, 475 (5.5), 476 and 477 are superseded;
  **never submit 469**.
- **5.4's user-facing copy is function and performance only** (owner, 2026-09-23): the release notes
  (both `fastlane/metadata*/en-US/release_notes.txt`, identical), `WHATS_NEW.md`,
  `Docs/USER_CHANGELOG.md` + bundled copy and the in-app "5.4" entry describe the answer work and
  nothing else. Plans, paywall, rating request and Maximum cap stay in `CHANGELOG.md` only. All of it
  is in the owner's voice, and the notes are on both records with build 478.
- Three subscription descriptions are still wrong and the API refuses them (HTTP 409, ACTIVE). Web
  page targets: Pro Annual "Annual billing for 1,000 documents and 10 libraries.", Pro Monthly
  "Monthly billing for 1,000 documents and 10 libraries.", Lifetime "Permanent Pro - 20 Libraries +
  Unlimited Documents". Submit both Pro subscriptions with 5.4 so their images get reviewed.
- On submission: `in_review` for both platforms in `Docs/SHIPPED_VERSION.json`, push. On release:
  date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md`, copy it byte-for-byte to
  `OpenIntelligence/Resources/VersionHistory.md`, remove `<!-- unreleased -->` from `## 5.4` in
  `CHANGELOG.md`, and only then open the next version above it; set `app_store` and `preparing`, push.
  Then publish the GitHub release, and only when the owner says to (2026-09-24: "I'll tell ya when to
  do 5.4"). `v5.4.0` is a draft at `c276b9a`, the source of build 478, and its tag is already on
  origin. It covers 5.4 only: `v5.3.0` (full and Latest since 2026-09-24, at `a2d99ab`, the source of
  build 464) covers 5.2 and 5.3, without their plans and ratings sections. To publish, change the
  draft's first line from "in App Review ... It's not on the App Store yet" to live with the date
  (`gh release view v5.4.0 -R Gunnarguy/OpenIntelligence --json body -q .body` gives the text), then
  `gh release edit v5.4.0 -R Gunnarguy/OpenIntelligence --notes-file <file> --draft=false --latest`.
  If 5.4 ships from a build other than 478, the tag has to move first, and that is the owner's call.
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
`WHATS_NEW.md`, and the one "5.4" entry in `WhatsNewStore.swift` (seven items: the three answer items, then four titled "From 5.3", whose screen no one saw).

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
- Final code, `b176da2` (the build copy matched it for app, tests and project): full iOS suite ->
  500 tests, 0 failures, 3 skipped, TEST SUCCEEDED. Hook tests -> 18 passed, 0 failed.
- App Store Connect, read-only, 16:13 PT: both 5.4 records `PREPARE_FOR_SUBMISSION`, release MANUAL,
  copyright set, build 474 attached with `usesNonExemptEncryption=false`, review contact, email,
  phone and 1,116 characters of notes set, no demo account required, no open review submission;
  What's New still the plans-and-ratings text (1,239 characters); promotional text the sale line.
- App Store Connect, 2026-09-23 22:04 PT: both 5.4 records `WAITING_FOR_REVIEW`, build 478 `VALID`,
  What's New 1,604 characters; screenshot sets replaced and `COMPLETE`: `APP_IPHONE_67`, `_65`, `_61` 9
  each, `APP_IPAD_PRO_3GEN_129` 7, `APP_DESKTOP` 6.
- **Not verified:** anything on a device (haptic, badge on a phone, clock restart, background expiry,
  streaming feel); the "Checking sources…"/"Refining…" label and unlocked composer in the running app.

## Blockers / Unknowns

- Nothing blocks 5.4; it is with Apple. The three subscription descriptions in App Store Connect are
  still wrong ("unlimited documents and 5 libraries" for Pro, "10 Libraries" for Lifetime). The API
  refuses them (409, ACTIVE) and no Chrome was connected to edit the web page, so they wait for the
  next submission; targets are in the Status section above.
- Whether macOS needs a tab signal other than the badge, which its toolbar tabs do not draw.
- Cleanup, this session's test data only: `/private/tmp/oi-ui-appsupport-2026-09-23` (the Mac UI
  test library); simulators `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`, `57E0CE08-EA1A-4D02-9D74-FEBD238709ED`
  and `F798E00A-9F48-44B8-A087-45413A96783A` (shut down; `xcrun simctl delete` each); frozen apps in
  `/private/tmp/oi-bench/`; in the owner's iCloud Documents, `~/Documents/SampleDocuments` (fresh sample
  copies from the unsigned Mac build) and `~/Documents/SampleDocuments.evicted-2026-09-23` (the evicted
  copies that froze it). Nothing there is the owner's own.

## Exact Next Action

Check the two 5.4 review submissions (`GET /v1/apps/6756559175/reviewSubmissions`). On approval both
records read `PENDING_DEVELOPER_RELEASE` (release MANUAL): release when the owner says to, then do the
release close-out in the Status section (date `## v5.4` in `Docs/USER_CHANGELOG.md` and its bundled
copy, remove `<!-- unreleased -->` from `## 5.4`, set `app_store` to 5.4 and clear `in_review` in
`Docs/SHIPPED_VERSION.json`, push, then publish the `v5.4.0` GitHub draft when the owner says). On a
rejection, read the resolution center message and fix what it names. The three v5.4 Notion rows close
only after the owner's device check.
