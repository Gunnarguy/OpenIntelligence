# Current State

Updated: 2026-09-24, 15:20 PT (iOS 5.4 live; macOS 5.4 in review; GitHub v5.4.0 published; two steps wait on the owner's approval)
Branch/worktree: `main`, primary checkout
Last verified commit: d80ef17

## Objective

Ship 5.4 with every change since 5.3, including the answer work of 2026-09-23. The owner's words
that day: 5.4 is the version that exists in App Store Connect, there is no 5.5, and every change
made since 5.3 is 5.4. The answer work was first pushed as 5.5 (`faed0d6`, Xcode Cloud build 475)
and folded back into 5.4 the same day (`Docs/ai/DECISIONS.md`, 2026-09-23). iOS 5.4 is live since
2026-09-24; what remains is the Mac release and its close-out.

## Status: 5.4

- **iOS 5.4 is live**, since 2026-09-24 14:32 PT, build 478 (Xcode Cloud #478 from `c276b9a`). Apple
  approved it (`PENDING_DEVELOPER_RELEASE`, release MANUAL). The Release button in App Store Connect
  would not work for the owner, so at his request it went out through the API:
  `POST /v1/appStoreVersionReleaseRequests` with
  `{"data":{"type":"appStoreVersionReleaseRequests","relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"<record id>"}}}}}`
  returned 201, and the record read `READY_FOR_SALE` with build 478 five seconds later (reference:
  developer.apple.com "Manually release an app store approved version of your app", read 2026-09-24).
- **macOS 5.4 is `IN_REVIEW`** with the same build, release MANUAL. Record
  `0e7e7d98-9878-4418-b977-3bc0b04ddf96`, submission `5a21fe94-a866-4c37-a412-a44f385f1b68`. The iOS
  record is `edac9a46-fd9c-4082-99f8-372008d20289`. Builds 474 to 477 are superseded; **never submit 469**.
- **5.4's user-facing copy is function and performance only** (owner, 2026-09-23): the release notes
  (both `fastlane/metadata*/en-US/release_notes.txt`, identical), `WHATS_NEW.md`,
  `Docs/USER_CHANGELOG.md` + bundled copy and the in-app "5.4" entry describe the answer work and
  nothing else. Plans, paywall, rating request and Maximum cap stay in `CHANGELOG.md` only. All of it
  is in the owner's voice, and the notes are on both records with build 478.
- Three subscription descriptions are still wrong and the API refuses them (HTTP 409, ACTIVE). Web
  page targets: Pro Annual "Annual billing for 1,000 documents and 10 libraries.", Pro Monthly
  "Monthly billing for 1,000 documents and 10 libraries.", Lifetime "Permanent Pro - 20 Libraries +
  Unlimited Documents". Submit both Pro subscriptions with 5.4 so their images get reviewed.
- Done at the iOS release (2026-09-24): `## v5.4 - September 24, 2026` in `Docs/USER_CHANGELOG.md` and
  the byte-identical `OpenIntelligence/Resources/VersionHistory.md`; `## 5.4` closed in `CHANGELOG.md`
  (the marker removed, no next version opened); in `Docs/SHIPPED_VERSION.json`
  `app_store_by_platform.ios` is 5.4 and `in_review` holds macOS only. `app_store` stays 5.3 until the
  Mac is live, the value that does not overclaim to a Mac visitor. Gunzino's App Store Versions check
  compares its page to the iPhone version from the iTunes lookup, so it reports drift until then.
- At the Mac release: `app_store_by_platform.macos` to 5.4 and `in_review` empty, plus `app_store` to
  5.4 if the refused step below has not already moved it. `preparing` must move off 5.4 in the same
  commit, because Fascinaiting requires it never to equal `app_store` and every value must match a
  `## <version>` heading. **The owner picked 5.5 over 5.4.1** (2026-09-24, dictated: "maybe not 5.4, I
  don't know. I guess it's a better", read as 5.5); it is not applied yet.
- **GitHub `v5.4.0` is published and Latest** since 2026-09-24 ~15:00 PT, at the owner's word, at
  `c276b9a` (the source of build 478). Its first line says iPhone and iPad have 5.4 and the Mac is in
  App Review; when the Mac goes live, edit that line (`gh release view v5.4.0 -R Gunnarguy/OpenIntelligence
  --json body -q .body`, then `gh release edit v5.4.0 -R Gunnarguy/OpenIntelligence --notes-file <file>`).
  `v5.3.0` (at `a2d99ab`, build 464) covers 5.2 and 5.3.
- **Waiting on the owner's approval.** Auto mode refused both as `[Production Deploy]` at about 15:00 PT
  on 2026-09-24, although he asked for both in chat:
  1. macOS 5.4 `releaseType` to `AFTER_APPROVAL`, so Apple releases it on approval ("go ahead and do the
     macOS one too"): `PATCH /v1/appStoreVersions/0e7e7d98-9878-4418-b977-3bc0b04ddf96` with
     `{"data":{"type":"appStoreVersions","id":"<id>","attributes":{"releaseType":"AFTER_APPROVAL"}}}`
     (reference: developer.apple.com "Modify an app store version", read 2026-09-24). If the record
     already reads `PENDING_DEVELOPER_RELEASE`, send the release request instead.
  2. Every website to 5.4 now ("just update all the websites"): in `Docs/SHIPPED_VERSION.json`
     `app_store` 5.4 and `preparing` 5.5, with `app_store_by_platform.macos` 5.3 and `in_review` macOS
     kept until the Mac is live; in `CHANGELOG.md` `## 5.5 <!-- unreleased -->` above `## 5.4 -
     September 24, 2026` and `<!-- next-version: 5.5 -->`; push. Then `gh workflow run
     openintelligence-version.yml` in Gunzino and Gunnarguy-Portfolio (both commit and deploy
     themselves) and the hand-only lines: Gunzino `openintelligence/index.html:226` and `index.html:374`
     ("Version 5.3", which `scripts/verify_content.py` fails the deploy on if left); Fascinaiting
     `index.html` (its version job only verifies): the `data-oi-version` spans at 491 and 761, the
     `data-oi-preparing` span at 746, and the timeline, where 5.4 becomes the current release with its
     highlights, 5.3 is superseded and 5.5 is in development. Run each repo's `verify-site.sh source`
     before pushing; every repo has a pre-push overlap guard.
  Until then every site says 5.3. Gunzino's App Store Versions check fails once the iTunes lookup
  reports 5.4 (it read 5.3 at 14:55 PT), and gunnarguy.me's project page shows 5.4 where it reads the
  store listing (`data/appstore.json`, refreshed by `update-stats.yml`) and 5.3 where it reads the marker.
- The Post Desk (https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7): `flags/sw:after54` set 2026-09-24,
  so the 5.4 posts are unlocked, the "It's live" quote post first; `flags/task:fix924` ticked, because
  the September 24 posts are true now that iPhone and iPad have 5.4. The desk's `posted` shows `oi54-x1`
  and `oi54-li1` on 2026-09-24.
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

- **`## 5.4` is closed and no next version is open yet.** The owner named 5.5 (see Status)
  (`Docs/ai/DECISIONS.md`, 2026-09-23). `ci_post_clone.sh` stamps every Xcode Cloud build from the
  first numbered heading in `CHANGELOG.md`, and iOS rejects any new 5.4 build now that 5.4 is live
  there, so no app change is pushed until that heading exists.
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
- App Store Connect writes happen at the owner's word (he asked for the iOS release on 2026-09-24). swift-format rewrites Swift files edited with Edit/Write;
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
- App Store Connect, 2026-09-24 14:32 PT: `POST /v1/appStoreVersionReleaseRequests` for the iOS 5.4
  record -> 201; read back `READY_FOR_SALE` (`appVersionState` `READY_FOR_DISTRIBUTION`), build 478.
  macOS 5.4 `IN_REVIEW`, build 478. Both 5.3 records `READY_FOR_SALE`, build 464, at 09:50 PT.
- **Not verified:** anything on a device (haptic, badge on a phone, clock restart, background expiry,
  streaming feel); the "Checking sources…"/"Refining…" label and unlocked composer in the running app.

## Blockers / Unknowns

- Nothing blocks the Mac release; macOS 5.4 is with Apple. The three subscription descriptions in App Store Connect are
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

Ask the owner to approve the two refused steps in the Status section (he switches this session out of
auto mode, or approves each command), then run them: the macOS 5.4 `releaseType` PATCH, and the website
move (`SHIPPED_VERSION.json` `app_store` 5.4 and `preparing` 5.5, `## 5.5` opened in `CHANGELOG.md`,
push, each site's version job and hand-only lines, each site's `verify-site.sh`). When macOS 5.4 reads
`READY_FOR_SALE`, set `app_store_by_platform.macos` to 5.4, empty `in_review`, update the GitHub
release's first line, and push. App Store Connect has no 5.5 records, so create them before the next
app-change push or its build fails at PrepareBuildForAppStoreConnect. The three v5.4 Notion rows close
only after the owner's device check.
