# Current State

Updated: 2026-09-23, 09:10 PT, fresh-session handoff
Branch/worktree: `main`, primary checkout, level with `origin/main`, working tree clean
Last verified commit: c250e48

## Objective

Two tracks, in this order of who acts:

1. **Ship 5.4 on build 474.** Everything an agent can do is done. The rest belongs to the owner:
   the TestFlight check of 474 on a device, an attempt at three descriptions on the App Store
   Connect web page, and the decision to submit. Do not submit until the owner says so.
2. **5.5: the Standard end-of-stream stall, streaming for Deep Think and Maximum, and a signal when
   an answer finishes off-screen.** Investigated in code, nothing implemented. Code changes wait for
   the owner's `PROCEED: IMPLEMENT`. Measuring does not change code and can start now.

Social posts run in conversation, not here (auto-memory `social-channels-and-x-premium.md`).

## Status: 5.4

- **5.3 is live** on iOS and macOS, build 464, since 2026-09-18 (`Docs/SHIPPED_VERSION.json`).
- **5.4, both platforms: `PREPARE_FOR_SUBMISSION`, release MANUAL, build 474 attached** (read GET-only
  2026-09-23 08:40 PT). What's New, description, keywords, App Review notes (1,116 characters, with
  `fastlane/review_notes/5.4.txt`) and the sale promotional text are written.
- **Build 474** = Xcode Cloud run #474 from `c73aea5`: `VALID`, `usesNonExemptEncryption=false`,
  `IN_BETA_TESTING` on both platforms. It carries every 5.4 fix. **Never submit build 469**: its
  end-of-setup plans sheet crashed the app (fixed in `a713bfc`; see `CHANGELOG.md` `## 5.4`).
- **Both Pro subscription images** are uploaded, state `PREPARE_FOR_SUBMISSION`. They are reviewed
  only if both subscriptions are included in the 5.4 submission. Win-back offers
  (`winback_annual_2026`, `winback_monthly_2026`, from 2026-09-24) need them to be promoted.
- **Three descriptions are still wrong** and the API refuses them: HTTP 409 "Cannot edit
  SubscriptionLocalization when it is in ACTIVE state" (same for Lifetime). Targets, for the web page:
  Pro Annual "Annual billing for 1,000 documents and 10 libraries.", Pro Monthly "Monthly billing for
  1,000 documents and 10 libraries.", Lifetime "Permanent Pro - 20 Libraries + Unlimited Documents".
  The app never shows these strings.
- **Owner's TestFlight check of 474**: fresh install on the free plan, "See It in Action", "Start
  Asking", the plans sheet opens and Done closes it; then Maximum mode, four questions, the fourth
  shows "Maximum mode limit reached". Closes roadmap rows
  https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9 (crash) and the Maximum cap row.
- **On submission:** set `in_review` for both platforms in `Docs/SHIPPED_VERSION.json` and push. **On
  release:** date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md`, copy it byte-for-byte to
  `OpenIntelligence/Resources/VersionHistory.md`, remove `<!-- unreleased -->` from `## 5.4` in
  `CHANGELOG.md` and open `## 5.5 <!-- unreleased -->` above it before the next source push, set
  `app_store` and `preparing`, push.
- **Scheduled:** 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale` takes the sale line
  off whichever version is live and off the three sites (runs only while the desktop app is open).

## Status: 5.5 findings (code-verified 2026-09-23; durations not measured)

- **Standard end-of-stream stall.** The blinking cursor (`MessageListV2.swift` ~280) shows while
  `isProcessing` is true (ChatScreen ~2337), which lasts until `RAGService.query` returns. After the
  last token that call awaits: a continuation when the text ends without punctuation (`LLMService`
  ~1094-1108), the checks with an answer embedding (`RAGService` ~14385-14433), and for
  extractive-first questions SourceOnly: two sequential structured model calls
  (`SourceOnlyAnswerService` ~372 draft, ~416 review) called at `RAGService` ~14654, which can
  replace the answer. Extractive-first is `.lookup`/`.tableLookup`, which any "what/which/when/where/
  who/how many…" question gets by default (confirmed in a harness log: "What file types does
  OpenIntelligence handle?" → `AnswerIntent: lookup (extractiveFirst: true)`). The pipeline's
  "Total time" is logged at ~14586, before SourceOnly, so no in-app timer covers it.
- **Short Standard answers do not really stream.** Under the 3600-token check (`RAGService`
  ~16454-16473) Standard calls `respond(generating: DirectRAGAnswer.self)` and replays the result.
  The SDK can stream `@Generable` output as `PartiallyGenerated`; `DirectRAGAnswer` declares `answer`
  first (`RAGStructuredResponse.swift` ~61).
- **Deep Think and Maximum can stream.** `LLMStreamingContext.handler` is `@TaskLocal`
  (`LLMService` ~114-122) and ChatScreen sets it only for `.standard` (~2948). Deep Think's synthesis
  (`AgenticOrchestrator` ~5689) already runs through `streamResponse`; Maximum's core call is ~7174.
  A verification loop (~3714), Maximum's refinement (~7201) or SourceOnly can replace the text.
- **Tab switches already keep the answer on iOS** (`b87123d`, 5.0.1): unstructured `Task` at ChatScreen
  ~2856; `.onDisappear` (~648, ~972) only stops the clock. Missing: any completion signal (the only
  answer haptic fires at start, ~2982), restarting the elapsed clock on return, real progress for Deep
  Think and Maximum to the iOS 26 background task (flat 62%), and a saved notice when that task
  expires (roadmap row "A long answer outlives its 30-second background grant…", Future Backlog).

## Proposed 5.5 plan (awaits `PROCEED: IMPLEMENT`; target 5.5, file roadmap rows on approval)

1. Measure the stall on macOS (Exact Next Action). 2. End the cursor and unlock input when the text
stops, show "Checking sources…" until citations attach; if the measurement confirms SourceOnly is the
cost, run it in Standard only when the checks flag the answer, and benchmark accuracy before and
after. 3. Off-screen completion: success haptic, a Chat tab badge, clock restart, real background
progress, a notice on expiry. 4. Stream Deep Think and Maximum with a "Refining…" state; make short
Standard answers truly stream. 5. Verify: suite, macOS before/after timings, TestFlight on device.

## Active Constraints

- **Guard memory on builds** (18 GB Mac; a cold build crashed it on 2026-09-20). Recipes and the
  guard loop: `Docs/ai/RUNBOOK.md` "A long build can take this Mac down". Build from `/tmp/oi-src`.
- **The iOS simulator has no Apple Intelligence here**: the DEBUG harness on the iOS 27.0 simulator
  reported "Apple Intelligence (Unavailable) … requires a physical device" and fell back to excerpts.
  Anything needing generation runs on the macOS Debug build or a device.
- **App Store Connect writes are the owner's**: the permission classifier refuses them from an agent,
  even with the owner's instruction. GET-only reads work. `fastlane submit_latest` would overwrite the
  sale promo text; submit in the App Store Connect page.
- **swift-format runs on every Swift file Claude edits** (global post-edit hook). In files with `"""`
  literals it re-indents their content; edit those by script (auto-memory
  `swift-format-hook-reindents-multiline-strings.md`).
- **Commit to `main`, no branches, no AI trailer.** Source edits need `PROCEED: IMPLEMENT`.
  `fastlane/metadata*` changes need the `### 5.4` history entry. Simulators are shared: use your own.

## Working Set

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: post-stream steps (~14385-14750).
- `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`: the two extra calls.
- `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift`: send, stream handler, completion.
- `OpenIntelligence/Features/Chat/Conversation/MessageListV2.swift`: the streaming bubble and cursor.
- `OpenIntelligence/App/DebugRAGValidationHarness.swift`: headless query flags.
- `scripts/asc_listing_extras.rb`, `scripts/asc_prepare_release.rb`: the 5.4 store writes.

## Verification (2026-09-23, output read)

- GET-only read-back 08:40 PT: both 5.4 records build 474, What's New "on its own", notes with the
  5.4 addition, sale promo; images `PREPARE_FOR_SUBMISSION`; descriptions unchanged (409).
- Xcode Cloud #474 (`c73aea5`) SUCCEEDED; build 474 `VALID` on both platforms.
- `VersionHistoryTests` 3/3 and `WhatsNewCoverageTests` 4/4 passed (iOS 27 simulator).
- Crash reproduced on build 469's Swift and gone with the fix (Debug simulator walk, 2026-09-22).
- fascinaiting.me and gunzino.me live with the corrected Private Cloud Compute sentence, HTTP 200.
- **Not verified:** any duration of the post-stream steps; anything on a device; the fix on macOS.

## Blockers / Unknowns

- How long each post-stream step takes. Settled by the measurement below.
- Whether `/private/tmp/oi-build-mac/Build/Products/Debug/OpenIntelligence.app` (built 2026-09-22
  09:35, before `a713bfc`; the pipeline code it measures is unchanged since) is sandboxed. Check with
  `codesign -d --entitlements - <app>`; if it shows a sandbox, rebuild with RUNBOOK line 206 into
  `/private/tmp/oi-mac-nosbx`, guarded.

## Exact Next Action

Measure the Standard stall on macOS with no code change. Copy `Docs/HOW_IT_WORKS.md` to
`/private/tmp/oi-timing/`, then run the app binary
(`<app>/Contents/MacOS/OpenIntelligence`) with `--rag-validation --rag-validation-query "<q>"
--rag-validation-file /private/tmp/oi-timing/HOW_IT_WORKS.md --rag-validation-storage
/private/tmp/oi-timing/mac-store --rag-validation-quality standard --rag-validation-pcc-consent deny`,
once for "What file types does OpenIntelligence handle?" and once for "Explain how OpenIntelligence
decides when to use Private Cloud Compute" (add `--rag-validation-skip-ingest` the second time).
Timestamp every stdout line on the host through a pty so output is line-buffered, allow 600 s for
the first launch's model warm-up, and read the gaps between the last generation line, `Total time`,
the `[SourceOnly]` lines and `Enhanced RAG pipeline complete`. Report the numbers to the owner with
the plan above, then wait for `PROCEED: IMPLEMENT`.
