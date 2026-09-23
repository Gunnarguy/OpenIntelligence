# Current State

Updated: 2026-09-23, 08:35 PT, after build 474 (every 5.4 fix) went VALID
Branch/worktree: `main`, primary checkout
Last verified commit: c73aea5

## Objective

**5.4 is prepared and deliberately not submitted.** The owner said on 2026-09-23: fix and align
everything, do not put it into review yet. What remains is one owner command (App Store Connect
writes), the owner's TestFlight check on a device, and the owner's decision to submit.

Social posts run in conversation, not here (auto-memory `social-channels-and-x-premium.md`, Post
Desk https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7); nothing in them blocks the release.

## Status

- **5.3 is live on iOS and macOS**, build 464, since 2026-09-18 (`Docs/SHIPPED_VERSION.json`).
- **5.4, both platforms: `PREPARE_FOR_SUBMISSION`, release MANUAL, build 474 attached**, What's New,
  notes and sale promo written (read GET-only 2026-09-23 08:40 PT). **Build 469 must never be submitted:** its end-of-setup plans sheet
  crashed the app (fixed in `a713bfc`; details in `CHANGELOG.md` `## 5.4`).
- **Build 474 is the one to attach**: Xcode Cloud run #474 from `c73aea5` SUCCEEDED; iOS and macOS
  5.4 build 474 `VALID`, `usesNonExemptEncryption=false`, `IN_BETA_TESTING` (read GET-only 08:33 PT).
  It carries the crash fix and the aligned in-app copy. Build 472 is superseded; run #473 was canceled.
- **Crash fix verified in the simulator** (Debug, iOS 27.0, fresh install): 469's Swift traps 1.5 s
  after "Start Asking" (`Fatal error: No ObservableObject of type EntitlementStore found`); the fixed
  build opens and closes the plans sheet. Roadmap row
  https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9, `In Progress` until a device run.
- **Maximum cap verified in the simulator:** 3, 2, 1, 0 left as each question is sent; sends four
  and five blocked with "Maximum mode limit reached". At the limit the chip reads "Maximum · 0 left"
  and the menu "Maximum · Limit reached". A blocked question's text is cleared from the input box
  (Future Backlog candidate). Recorded on the cap's roadmap row.

## The pre-submission sweep, and where each item stands

| # | Item | State |
|---|---|---|
| 1 | App Review notes were 5.3's; nothing about the cap | Done 2026-09-23: 701 to 1,116 characters, both platforms |
| 2 | 5.4 promo text is the non-sale line; a mid-sale release drops the sale | Done: sale line on both 5.4 records; `asc_end_sale.rb` removes it 09-30 |
| 3 | Pro descriptions say "unlimited documents and 5 libraries"; Lifetime says 10 libraries | Refused again: 409, "Cannot edit ... when it is in ACTIVE state". Only the web page is left to try; the app never shows these strings |
| 4 | No subscription image, so win-back offers (from 2026-09-24) cannot be promoted | Uploaded, `PREPARE_FOR_SUBMISSION`: include both subscriptions when submitting |
| 5 | Sites, docs and the in-app sample guide said the app shows "exactly what would be sent" | Done: Fascinaiting `bdff4ff2`, Gunzino `cc2912b` (both verified live); README, HOW_IT_WORKS, STUDY_GUIDE, `SampleDocumentManager.swift:59` |
| 6 | "Never twice in four months" overpromised | Done in store copy and in-app copy; in-app text ships in the next build |
| 7 | Version History shows "unreleased" beside the running version | For the 5.5 release steps: date the heading before the release build |
| 8 | iPhone 6.5" preview is the 5.1 video; macOS screenshots date from 2026-06-21 | Open; macOS captures need a Screen Recording grant |
| 9 | Phased release is off | Owner's call |

Checked clean on 2026-09-22: name, subtitle, privacy URL, age rating, copyright, min OS 26.0, export
compliance, Data Not Collected label, win-back redemption through `Transaction.updates`, Restore,
Terms and Privacy on the plans screen.

**Future Backlog candidates, not filed:** any paid purchase, Pro included, sets
`legacyProtectionState = .historicalPaidPurchase`, which `MonetizationPolicy.swift:27` counts as
protected and `EntitlementStore.swift:205` resolves to `.lifetime`, so Pro buyers keep Lifetime limits
after cancelling (hard-boundary file); the consent sheet prints `routeReason.rawValue` as "Why PCC"
(`CloudConsentPromptView.swift:182-183`); tappable citations reportedly exist only on structured
answers (subagent claim, unverified); "Save 58%" is fixed text (`PlanUpgradeSheet.swift:54`);
swift-format (the post-edit hook) re-indents multi-line string literals, so an edit to
`SampleDocumentManager.swift` must bypass it or the sample documents' text can change.

## Scheduled, nobody needs to act

- **2026-09-30 09:00 PT:** task `openintelligence-end-lifetime-sale` takes the sale off whichever
  version is live and off the three sites. Runs only while the desktop app is open.
- **After 2026-09-29:** App Store Connect, Analytics, Campaigns shows downloads per X campaign tag.

## When 5.4 is submitted, and when it goes live

On submission: set `in_review` for both platforms in `Docs/SHIPPED_VERSION.json` and push. On
release: date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md` and copy it byte-for-byte to
`OpenIntelligence/Resources/VersionHistory.md`; remove `<!-- unreleased -->` from `## 5.4` in
`CHANGELOG.md` and open `## 5.5 <!-- unreleased -->` above it **before the next source push**, or
`ci_post_clone.sh` stamps a shipped version; set `app_store` and `preparing` and push.

## Active Constraints

- **Guard memory on long builds**; never build against the iCloud checkout. Recipes in
  `Docs/ai/RUNBOOK.md`. Incremental builds reuse `/private/tmp/oi-build` from `/tmp/oi-src`.
- **Commit to `main`, no branches, no AI co-author trailer.** `fastlane/metadata*` changes need the
  `### <preparing version>` entry in `Docs/Release/APP_STORE_METADATA_HISTORY.md` (pre-commit).
- **App Store Connect writes are the owner's.** The permission classifier refused
  `asc_prepare_release.rb 5.4 472 --apply` on 2026-09-23 even with the owner's instruction. On the
  same morning `api.appstoreconnect.apple.com` dropped the TLS handshake from the agent shell for a
  while (other Apple hosts answered; Apple reported no incident); it recovered within the hour.
- **Do not use `fastlane submit_latest` for 5.4:** its `deliver` pushes `promotional_text.txt`
  (the non-sale line) over the sale line before submitting.
- **Simulators are shared between sessions.** Use a dedicated device for any UI run.
- The repo router mis-routes UI fixes; follow CLAUDE.md's generic rules.

## Working Set

- `scripts/asc_listing_extras.rb`: review notes, sale promo text, product descriptions, subscription
  images; dry run by default; never submits.
- `scripts/asc_prepare_release.rb`: attaches a build and writes What's New, description, keywords.
- `fastlane/review_notes/5.4.txt`, `fastlane/iap_images/`, `scripts/render_iap_images.swift`.
- `Docs/Release/APP_STORE_METADATA_HISTORY.md`, 5.4 entry: the 2026-09-23 corrections.

## Verification

- 2026-09-23: `VersionHistoryTests` 3 of 3 and `WhatsNewCoverageTests` 4 of 4 passed (iOS 27
  simulator, incremental build, lowest free memory 29%).
- 2026-09-23: Fascinaiting `scripts/verify-site.sh source` exit 0; Gunzino
  `scripts/extract_pages.py --check` 22 of 22 pages match.
- 2026-09-22: crash reproduced on 469's Swift and gone on `a713bfc` in the simulator; Maximum cap
  walked; Xcode Cloud #472 SUCCEEDED, build 472 `VALID`.
- 2026-09-23: `asc_listing_extras.rb 5.4` dry run against the live records resolved every lookup:
  notes 701 characters plus 413 on both platforms, the sale line to copy, all three descriptions,
  both images to upload. Sites verified live: old sentence gone, new one present, HTTP 200.
- **Not verified:** any `--apply` write (the owner's); anything on a device; the fix on macOS.

## Exact Next Action

The App Store Connect side of 5.4 is done except the refused descriptions (read back 08:40 PT). Left,
all the owner's: the TestFlight check of build 474 on a device (fresh install on the free plan,
finish setup, the plans sheet opens and closes; four Maximum questions, the fourth blocked), an
attempt at the three descriptions on the App Store Connect web page, then the decision to submit,
including both Pro subscriptions so their images are reviewed. Do not submit until the owner says so.
Separately, investigated 2026-09-23 (code reading, nothing implemented; plan awaits `PROCEED: IMPLEMENT`):
- **Standard end-of-stream stall.** The cursor lasts until `RAGService.query` returns. After the last
  token it awaits a possible continuation (`LLMService` ~1094), the checks with an answer embedding
  (~14385-14433) and, for extractive-first questions (any "what/which/when/where/who/how many…"),
  SourceOnly: two more structured model calls (`SourceOnlyAnswerService` ~372 draft, ~416 review),
  called at `RAGService` ~14654. The pipeline's "Total time" is logged before SourceOnly. Durations
  unmeasured: the simulator has no Apple Intelligence ("requires a physical device", harness run
  2026-09-23), so measure with the macOS Debug harness or on a device.
- **Deep Think and Maximum can stream.** `LLMStreamingContext.handler` is `@TaskLocal` and ChatScreen
  sets it only for `.standard` (~2948); Deep Think's synthesis already runs through `streamResponse`.
  A later verification, refinement or SourceOnly pass can replace the streamed text.
- **Tab switches already keep the answer on iOS** (`b87123d`, 5.0.1): unstructured `Task` at ChatScreen
  ~2856, `.onDisappear` only stops the clock. Missing: a completion signal (the only answer haptic
  fires at start, ~2982), the clock restart on return, real background-task progress for Deep
  Think and Maximum (flat 62%). Existing row: "A long answer outlives its 30-second background grant".
