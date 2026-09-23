# Current State

Updated: 2026-09-23, 13:58 PT (5.5 work committed to `main` and pushed on the owner's word; verified off-device)
Branch/worktree: `main`, primary checkout, clean after the 5.5 commit, pushed to `origin/main`
Last verified commit: 2e3ab4a

## Objective

Two tracks, in this order of who acts:

1. **Ship 5.4 on build 474.** Everything an agent can do is done. The owner does the TestFlight check
   of 474 on a device, tries the three descriptions on the App Store Connect web page, and decides
   to submit. Do not submit until the owner says so.
2. **Land 5.5's first changes**, implemented this session under the owner's `PROCEED: IMPLEMENT`
   (2026-09-23): the Standard end-of-stream stall, finishing an answer early with its sources,
   signals for an answer that finishes off screen, and streaming for Deep Think and Maximum.
   Committed and pushed 2026-09-23 on the owner's word; what remains is verification on a device.

## Status: 5.4 (unchanged this session)

- 5.3 live on iOS and macOS (build 464). 5.4 on both platforms: `PREPARE_FOR_SUBMISSION`, release
  MANUAL, build 474 attached (`VALID`). **Never submit build 469** (its setup plans sheet crashed).
- Three subscription descriptions are still wrong and the API refuses them (HTTP 409, ACTIVE). Web
  page targets: Pro Annual "Annual billing for 1,000 documents and 10 libraries.", Pro Monthly
  "Monthly billing for 1,000 documents and 10 libraries.", Lifetime "Permanent Pro - 20 Libraries +
  Unlimited Documents". Submit both Pro subscriptions with 5.4 so their images get reviewed.
- On submission: `in_review` for both platforms in `Docs/SHIPPED_VERSION.json`, push. On release:
  date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md`, copy it byte-for-byte to
  `OpenIntelligence/Resources/VersionHistory.md`, remove `<!-- unreleased -->` from `## 5.4` in
  `CHANGELOG.md` (5.5 is already open above it), set `app_store` and `preparing`, push.
- Scheduled: 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`.

## Completed this session (committed and pushed 2026-09-23)

Measured on the macOS 27.0 Debug build (M3 Pro, on-device model, `Docs/HOW_IT_WORKS.md` only):
last streamed word to finished answer, Standard.

| Question | Before | After |
|---|---|---|
| What file types does OpenIntelligence handle? | 163.8 s, 19.4 s | 0.33 s |
| How many verification checks does OpenIntelligence run? | 58.3 s | 0.21 s |
| Which embedding model does OpenIntelligence use for retrieval? | 37.6 s | 0.15 s |
| Explain how OpenIntelligence decides when to use Private Cloud Compute | 0.12 s | 0.10 s |

The wait was `SourceOnlyAnswerService` (two structured model calls) on answers whose gates passed;
the 163.8 s run spent 163.5 s in the draft call and ended in a context overflow. Probes: a guided
call that hits `maximumResponseTokens` throws a parse error at once (0.9 s at 30 tokens); a cancelled
`respond(generating:)` throws `CancellationError` 0.00 s after `cancel()`; `streamResponse(generating:)`
grew `answer` in 14 steps over 27 snapshots, prefix-only. Stream probe, after: Deep Think "explain"
text from 50.0 s of 67.7 s (before: nothing until the end), one streamed call; Maximum from 34.6 s of
44.5 s; a Deep Think lookup streamed a 3,779-character synthesis that research replaced 17.7 s later
with the correct "Nine verification checks run." Details and file references: `CHANGELOG.md` `## 5.5`.

Code: Standard skips SourceOnly when gates pass (`RAGService.standardSkipsSourceOnlyCheck`); draft
limited to 1,024 tokens (700 was tried and measured too tight: Deep Think drafts used 571 and 675 of
700 and one failed to parse at it; the check took 22.8 to 32.6 s and changed 0 of 3 answers); `RAGService.finishAnswerNow()` / `runFinishableStage`; `AgenticOrchestrator.execute`
parks the chat handler (`LLMStreamingContext.finalAnswerHandler`/`answerHandler`), four final-answer
calls stream; `ChatScreen` checking state, one queued question, haptic, `ChatAnswerNotice` badge, clock
restart, step-driven background progress, expiry keeps text; structured short answers stream; harness
`--rag-validation-stream-probe`; gating token `finished_early_by_person`. Docs: `CHANGELOG.md` 5.5
(opened, `next-version: 5.5`), `Docs/USER_CHANGELOG.md` + mirror, `WHATS_NEW.md`, `WhatsNewStore` 5.5,
Atlas, `Docs/PRIVACY_AND_ROUTING.md`. Adversarial review found 6 defects, all fixed before commit.

Notion: `v5.5` added to Target Release (all 262 rows kept their values; snapshot in the session
scratchpad). Rows: Standard stall https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142 ,
off-screen signals https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3 , streaming
https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767 (all In Progress, v5.5); sample answers
"Partially Verified" without Apple Intelligence https://app.notion.com/p/3e449a74d54f8170a3cbfb570a41d0a5
(To Do, Future Backlog, from the owner's observation); Deep Think research replacing a full
synthesis with a one-line answer that can be wrong https://app.notion.com/p/3e449a74d54f813db884d9471b25bdb3
(To Do, Future Backlog, High; measured: "What file types…" became "notes, warnings, exceptions, and
documents" after the synthesis said "does not explicitly").

## Active Constraints

- **`main` is 5.5 since this push.** `ci_post_clone.sh` stamps the first `## x.y` heading, now
  `## 5.5`, so every Xcode Cloud build from `main` is 5.5. Build 474 stays the 5.4 candidate; a 5.4
  rebuild would need a revert of the 5.5 heading, which is the owner's call.
- **Guard memory on builds** (18 GB Mac). Build from `/private/tmp/oi-src`, synced with rsync
  excluding `BenchmarkRuns/`, `.simulator-smoke.nosync/`, `Benchmarks/run/`, `/.build/`,
  `/.device-smoke.nosync/`, `/build/` (the last three are 2.2 GB of gitignored build output).
- **The iOS simulator does not generate**; timing and streaming run on the unsigned macOS Debug build.
  That build writes `~/Library/Application Support/OpenIntelligence` and `~/Documents/pipeline_trace.log`
  (not the sandboxed real library). The UI test library was moved to
  `/private/tmp/oi-ui-appsupport-2026-09-23` so it could not leak into the benchmark; it holds only
  this session's sample library.
- Disk: 95%, about 21 GB free. At 96% (2026-08-20) model assets were evicted.
- App Store Connect writes are the owner's. swift-format rewrites Swift files edited with Edit/Write;
  files with `"""` were edited by script. Commit to `main`, no AI trailer.

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: skip rule, `finishAnswerNow`, `runFinishableStage`, SourceOnly task and logs, `finalizeResponse` marker.
- `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`: draft cap and token-use log.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`: `execute` wrapper, streamed and finishable sites.
- `OpenIntelligence/Services/LLM/LLMService.swift`: `LLMStreamingContext.finalAnswerHandler`/`answerHandler`.
- `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelStructuredGenerator.swift`: streamed direct answer.
- `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift`, `ChatComposerV2.swift`, `MessageListV2.swift`, `ChatAnswerNotice.swift` (new); `OpenIntelligence/App/ContentView.swift` (badge).
- `OpenIntelligence/Core/Models/RAGQuery.swift`: `ResponseMetadata.appendingGatingDecision`.
- `OpenIntelligence/App/DebugRAGValidationHarness.swift`: stream probe (the hook reformatted the whole file; whitespace only).
- `OpenIntelligenceTests/Services/RAG/Orchestration/SourceOnlyStandardGateTests.swift` and `ResponseMetadataGatingTests.swift` (new).
- `BenchmarkRuns/LEDGER.md` (the A/B entry), `Docs/ai/DECISIONS.md` (why Standard skips the check), `Docs/ai/RUNBOOK.md` (the stream-probe recipe).

## Verification (2026-09-23, output read)

- Full iOS suite, `xcodebuild test`, simulator `OI 5.5 tests iPhone 18 Pro` `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`
  -> 500 tests, 0 failures, 3 skipped, TEST SUCCEEDED (final run, all code in the tree), including
  SourceOnlyStandardGateTests 3/3, ResponseMetadataGatingTests 2/2, VersionHistoryTests 3/3, WhatsNewCoverageTests 4/4.
- macOS Debug, unsigned, `/private/tmp/oi-build-mac` -> BUILD SUCCEEDED, no warnings in changed files.
- `scripts/build_simulator_smoke.sh` -> succeeded; `scripts/check_icloud_conflicts.sh` -> no damage;
  `test_repoos_router.py` 29/29; `test_enforce_docs_hook.sh` 16/16; `secret_scan.py` clean;
  `scripts/required_docs.sh` on the 28 changed paths -> every required doc is in the change set.
- Accuracy A/B, QASPER 25, greedy (`BenchmarkRuns/LEDGER.md`, 2026-09-23 entry): before 6/25, after
  11/25; 0 pass-to-miss; SourceOnly replaced 0 answers in either run. The gain is not the change's:
  7 before cases hit `SensitiveContentAnalysisML error 15`, and the 3 clean flips differed in context.
- `--rag-validation-finish-after 3`, Deep Think lookup -> answer returned 0.01 s after the request,
  SourceOnly draft cancelled, full streamed text and sources kept.
- Chat badge: drawn on the iOS 27 simulator; on macOS counted (`[ChatAnswerNotice] … unseen=1`) but
  the toolbar tabs do not draw it.
- **Not verified:** anything on a device (haptic, badge on a phone, clock restart, background expiry,
  streaming feel); the "Checking sources…"/"Refining…" label and unlocked composer in the running app
  (the sample library held the check open 0.1 s).

## Blockers / Unknowns

- Owner decision: whether macOS needs a tab signal other than the badge, which its toolbar tabs do
  not draw.
- Cleanup, this session's test data only: `/private/tmp/oi-ui-appsupport-2026-09-23` (the Mac UI
  test library), the simulator above (`xcrun simctl delete 6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`),
  frozen apps in `/private/tmp/oi-bench/`.

## Exact Next Action

When Xcode Cloud has a 5.5 build on TestFlight (check the build list for version 5.5), run the device
checks in the "Closes when" sections of the three v5.5 Notion rows linked above, and close each row
that passes (`Status` Completed, `Completed` date, `Shipped On` only once 5.5 is live). The owner's
5.4 steps above are unchanged and independent of this.
