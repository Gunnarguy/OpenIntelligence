# Current State

Updated: 2026-09-22, 23:05 PT, after build 472 (the crash fix) went VALID
Branch/worktree: `main`, primary checkout, pushed
Last verified commit: a713bfc

## Objective

**Ship 5.4 on build 472, never build 469.** Build 469's one-time plans screen at the end of setup
crashed the app. `a713bfc` fixes it; Xcode Cloud run #472 built it and build 472 is `VALID` on both
platforms. Attach 472 to 5.4, re-check on TestFlight, then submit.

Social posts run in conversation, not here (auto-memory `social-channels-and-x-premium.md`, Post
Desk https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7); nothing in them blocks the release.

## Status

- **5.3 is live on iOS and macOS**, build 464, since 2026-09-18 (`Docs/SHIPPED_VERSION.json`).
- **5.4, both platforms: `PREPARE_FOR_SUBMISSION`, release MANUAL, build 469 still attached.** What's
  New, description (corrected, 3,986 of 4,000 characters) and keywords equal `fastlane/metadata/en-US/`
  (read back GET-only 22:02 PT).
- **Build 472**, Xcode Cloud run #472 from `a713bfc`, SUCCEEDED 23:01 PT: iOS and macOS 5.4, `VALID`,
  `usesNonExemptEncryption=false`, min OS 26.0, `IN_BETA_TESTING` (read GET-only 23:03 PT).
- **Maximum cap, simulator (Debug build of `a713bfc`, free tier):** 3, 2, 1, 0 left as each question
  is sent; stopping an answer does not refund; sends four and five blocked with "Maximum mode limit
  reached"; See Plans opens "Maximum mode is capped on Free" and Done closes it. At the limit the chip
  reads "Maximum · 0 left" and the mode menu "Maximum · Limit reached". A blocked question's text is
  cleared from the input (Future Backlog candidate). Recorded on the cap's roadmap row.
- **The crash in 469**, and its fix in `a713bfc`: the onboarding plans `.sheet` sat outside
  `.environmentObject(entitlementStore)`, and `PlanUpgradeSheet.swift:12` requires it. Fresh install,
  "See It in Action", "Start Asking", 1.5 s, then `Fatal error: No ObservableObject of type
  EntitlementStore found` (simulator, 469's Swift, 22:41 PT). Fixed, the same walk opens and closes the
  plans sheet with no crash (22:45 PT). Details in `CHANGELOG.md` `## 5.4`; roadmap row
  https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9, `In Progress` until a device run.

## Found in the sweep, not yet acted on (each is an outward write; the owner decides)

1. **App Review notes are 5.3's** (both platforms, 701 characters). Step 4 says try Maximum; nothing
   mentions the three-a-day cap, the limit dialog or the plans screen after setup. Drafted addition,
   to append after the existing text: "New in 5.4: the free plan counts Maximum runs, three a day.
   The fourth opens "Maximum mode limit reached" with Standard, Deep Think and See Plans, and the
   count resets at midnight. Pro and Lifetime have no cap, so a sandbox purchase lifts it. After the
   sample questions, a plans screen appears once and can be closed. Private Cloud Compute is Apple's,
   and the app uses it only after the consent sheet is approved."
2. **5.4's promotional text is 5.3's non-sale line**, chosen when 5.4 was expected after the sale
   (5.4 entry, `Docs/Release/APP_STORE_METADATA_HISTORY.md`). Released before 2026-09-30, 5.4 drops the
   sale line early. Either copy the live 5.3 sale line onto 5.4 (`scripts/asc_end_sale.rb` replaces
   sale text on whichever version is live on 09-30) or hold Release until 09-30.
3. **Subscription descriptions are wrong.** Pro Monthly and Pro Annual say "unlimited documents and 5
   libraries"; `QuotaPolicy.swift:9,14` says 1,000 and 10. Lifetime says "10 Libraries"; `:15` says
   20. The API refuses edits to approved subscriptions (409 UNMODIFIABLE, per
   `scripts/asc_fix_listing_copy.rb`); the App Store Connect web page is untried. The metadata
   history's 5.4 entry says they were corrected; they were not, and that line needs a dated note.
   The app never shows these strings (`PlanUpgradeSheet` reads only price and period).
4. **Neither subscription has a promotional image.** Win-back offers `winback_annual_2026` and
   `winback_monthly_2026` start 2026-09-24 set to be promoted (`USE_AUTO_GENERATED_ASSETS`); Apple
   requires an approved image for App Store promotion (StoreKit "Supporting win-back offers", read
   2026-09-22). The sheet and direct link work without it. An image goes through App Review.
5. **"the app shows exactly what would be sent"** is live on `Fascinaiting/index.html:479` and on
   `Gunzino/openintelligence/index.html:315` plus `Gunzino/src/content/pages/openintelligence.md:39`
   (those two must change identically). gunzino.me/openintelligence is the listing's marketing URL.
6. **What's New "Never twice in four months"** holds only for the automatic request; thumbs-up then
   "I love it" can call `requestReview` again (`ChatScreen.swift:912-918`). "on its own" fixes it.
7. **Settings, Version History shows "unreleased" beside the running version**
   (`VersionHistoryView.swift:89`; 5.3 shipped the same way). Fix in the 5.5 release steps.
8. **Stale media**: iPhone 6.5" preview is the 5.1 video; macOS has seven screenshots from 2026-06-21.
9. **Phased release is off** on both platforms.

Checked clean: name, subtitle, privacy URL, age rating, copyright, min OS 26.0, export compliance,
Data Not Collected label; win-back redemptions reach `Transaction.updates` (`StoreKitBillingService.swift:29, 306`);
`PlanUpgradeSheet.swift:361-389` has Restore, Terms and Privacy, which Schedule 2 section 3.8(b) asks for.

**Future Backlog candidates, not filed:** any paid purchase, Pro included, sets
`legacyProtectionState = .historicalPaidPurchase`, which `MonetizationPolicy.swift:27` counts as
protected and `EntitlementStore.swift:205` resolves to `.lifetime`, so Pro buyers keep Lifetime
limits after cancelling (hard-boundary file); the consent sheet prints `routeReason.rawValue` as
"Why PCC" (`CloudConsentPromptView.swift:182-183`); tappable citations reportedly exist only on
structured answers (subagent claim, unverified); "Save 58%" is fixed text (`PlanUpgradeSheet.swift:54`);
`SampleDocumentManager.swift:59`, `README.md:31`, `Docs/HOW_IT_WORKS.md:44` and
`Docs/STUDY_GUIDE.md:1650` still say "exactly what would be sent".

## Scheduled, nobody needs to act

- **2026-09-30 09:00 PT:** task `openintelligence-end-lifetime-sale` takes the sale off the listing
  and the three sites. Runs only while the desktop app is open.
- **After 2026-09-29:** App Store Connect, Analytics, Campaigns shows downloads per X campaign tag.

## When 5.4 goes live (release close-out, same shape as 5.3's)

Date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md` and copy it byte-for-byte to
`OpenIntelligence/Resources/VersionHistory.md` (`VersionHistoryTests` compares them); remove
`<!-- unreleased -->` from `## 5.4` in `CHANGELOG.md` and open `## 5.5 <!-- unreleased -->` above it
**before the next source push**, or `ci_post_clone.sh` stamps a shipped version and the build is
rejected; set `app_store` and `preparing` in `Docs/SHIPPED_VERSION.json` and push. On submission,
set `in_review` for both platforms and push.

## Active Constraints

- **Guard memory on long builds**; never build against the iCloud checkout. Recipes in
  `Docs/ai/RUNBOOK.md`. Incremental builds reuse `/private/tmp/oi-build` from `/tmp/oi-src`.
- **Commit to `main`, no branches, no AI co-author trailer.** `fastlane/metadata*` changes need the
  `### <preparing version>` entry in `Docs/Release/APP_STORE_METADATA_HISTORY.md` (pre-commit).
- **The permission classifier refuses App Store Connect writes** and refused the dry run of
  `asc_prepare_release.rb`. For reads write a GET-only script; for a write hand the owner the command.
- **Simulators are shared between sessions.** Use a dedicated device for any UI run.
- Non-interactive shells read files as US-ASCII; store-copy scripts read UTF-8 explicitly.
- The repo router mis-routes this fix (to App Intents, then app icon); follow CLAUDE.md's generic
  rules: CHANGELOG `### Fixed`, a Notion row, `bash scripts/build_simulator_smoke.sh`.

## Working Set

- `OpenIntelligence/App/ContentView.swift:179-185`: the fixed sheet.
- `OpenIntelligence/Features/Billing/PlanUpgradeSheet.swift:12`: the environment requirement.
- `scripts/asc_prepare_release.rb`: attaches the replacement build and rewrites the listing text.
- `CHANGELOG.md` `## 5.4`: needs a `### Fixed` entry for the crash.
- `Docs/Release/APP_STORE_METADATA_HISTORY.md`, 5.4 entry: the subscription line that did not land.

## Verification

Run 2026-09-22, output read:

- GET-only App Store Connect reads, 22:02 PT: the Status and sweep facts above.
- SwiftUI repro, `xcrun swiftc -parse-as-library`: environmentObject-then-sheet exits 133 with the
  fatal error; sheet-then-environmentObject renders and exits 0.
- `xcodebuild build`, Debug, `/tmp/oi-src` with every Swift file equal to `4cc5a78`, destination
  simulator `1B9826BB-B6E5-4B92-B15F-BD2EF11532E2`, `-derivedDataPath /private/tmp/oi-build`,
  `-jobs 2`: BUILD SUCCEEDED, 90 Swift compiles, lowest free memory 51%.
- Same build with the fix, fresh install, the same walk: sheet opens and closes, process alive, no new
  crash report, no fatal-error log line.
- Xcode Cloud run #472 (commit `a713bfc`): COMPLETE, SUCCEEDED; build 472 `VALID` on both platforms.
- **Not verified:** the unit suite (not run; no test covers this view); the fix on macOS; anything on
  a device; build 472 attached to 5.4.

## Blockers / Unknowns

- **Attaching 472 is an App Store Connect write**, which the permission classifier refuses from an
  agent; the owner runs the command below. The repro simulator was deleted after the walks.

## Exact Next Action

The owner runs `cd ~/Documents/GitHub/OpenIntelligence && zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 472 --apply'`.
Then read both 5.4 records back GET-only: each must show build 472 and `PREPARE_FOR_SUBMISSION`.
Then the owner's TestFlight check of 472 on a device: fresh install on the free plan, finish setup,
the plans screen opens and closes; four Maximum questions, the fourth shows "Maximum mode limit
reached". Then items 1 to 5 above are the owner's call, then Submit on both platforms, then set
`in_review` in `Docs/SHIPPED_VERSION.json` and push.
