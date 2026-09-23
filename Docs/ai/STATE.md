# Current State

Updated: 2026-09-22, evening, after the 5.4 listing was finished
Branch/worktree: `main`, primary checkout, pushed to `origin/main`
Last verified commit: 92e4817

## Objective

**Ship 5.4.** It is fully prepared in App Store Connect on both platforms and not submitted. What
stands between it and review is one check on a device and one button, both the owner's. Everything
else from the 2026-09-22 conversion plan (`Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md`) is done.

## Status

- **5.3 is live on iOS and macOS** since 2026-09-18, build 464. `Docs/SHIPPED_VERSION.json` says so.
- **5.4, in App Store Connect, both platforms, `PREPARE_FOR_SUBMISSION`, release type MANUAL:**
  build **469** attached; What's New, the buyer-first description and the keywords written from
  `fastlane/metadata/en-US/`; non-sale promotional text; four new captioned screenshots in every
  iPhone and iPad set (answer, refusal, sources, consent), all `COMPLETE`. macOS screenshots are
  still seven from 2026-06-21.
- **What 5.4 changes for users** (`CHANGELOG.md` under `## 5.4 <!-- unreleased -->`): the free
  plan's three Maximum runs a day are enforced for the first time; one rating request after the
  first verified answer; a dismissible plans screen once at the end of setup; the paywall banner
  shows the privacy label and, from 20 ratings, the store rating; What's New entries for 5.3 and 5.4.
- **Build 469 is still the right build.** Xcode Cloud #471 is running for `92e4817`, whose only
  Swift changes are the DEBUG-only screenshot scenes and hiding the sale banner in screenshot
  mode; nothing a user runs differs from 469.
- **Money and store, live:** win-back offers `6814902295` (Pro Monthly, $2.99 for 3 months) and
  `6814902418` (Pro Annual, $19.99 first year), active from 2026-09-24 for a year. The 5.3
  promotional text no longer says "33% off". All 175 Annual trial offers are deleted.

## Completed this session (2026-09-18 to 09-22)

All pushed; `git log a2d99ab..HEAD` is the full list. The ones a fresh session needs to know exist:

| Thing | Where |
|---|---|
| Conversion study: 333 downloads, 17 buyers, 5.1% install-to-paid, why | `Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md` |
| Attach a build and write listing text, both platforms, never submits | `scripts/asc_prepare_release.rb <version> <build> [--apply]` |
| Caption and upload screenshots | `scripts/compose_store_screenshots.py`, `scripts/asc_upload_screenshots.rb`; recipe in `Docs/ai/RUNBOOK.md` |
| Staged store scenes | `--screenshot-store answer\|refusal\|sources\|consent`, DEBUG only, `ChatScreen.seedStoreScene` |
| Win-back offers (already applied) | `scripts/asc_winback_offers.rb` |
| Retention message, waiting on Apple access | `scripts/asc_retention_message.rb` |
| Sale removal on 2026-09-30 | `scripts/asc_end_sale.rb`, run by scheduled task `openintelligence-end-lifetime-sale` at 09:00 PT |
| Daily X reply and post sheet | https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7 |

## Owner items, in order

1. **TestFlight check of the Maximum cap** on build 469: four questions in Maximum mode; the fourth
   must show "Maximum mode limit reached". TestFlight uses sandbox purchases, so the owner's real
   Lifetime does not carry over and the free tier applies. This closes the roadmap row "The free
   plan's three-Maximum-runs-a-day cap was displayed and sold but never enforced".
2. **Submit 5.4 for review** on both platforms in App Store Connect.
3. **Retention message:** the Apple access form was being filled on 2026-09-22; whether it was
   submitted is not recorded. When Apple's email grants access, run
   `zsh -ic 'ruby scripts/asc_retention_message.rb'`. It says plainly if access is still missing.
4. **macOS screenshots** need a Screen Recording grant on this Mac; nothing else blocks them.

## Scheduled, nobody needs to act

- **2026-09-30 09:00 PT:** the sale comes off the 5.3 listing and all three websites, verified live,
  and recorded. The task runs only while the desktop app is open, otherwise at next launch.
- **After 2026-09-29:** App Store Connect, Analytics, Acquisition, Campaigns shows downloads per X
  tag (`X_post`, `X_reply`, `X_build`, `X_halluc`, `X_pro`, `X_private`, `X_appleai`, `X_localai`,
  `X_manuals`, `X_fm`). Keep what brings downloads.

## When 5.4 goes live (release close-out, same shape as 5.3's)

Date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md` and copy it byte-for-byte to
`OpenIntelligence/Resources/VersionHistory.md` (`VersionHistoryTests` compares them); remove
`<!-- unreleased -->` from `## 5.4` in `CHANGELOG.md` and open `## 5.5 <!-- unreleased -->` above it
**before the next source push**, or `ci_post_clone.sh` stamps a shipped version and the build is
rejected (2026-07-28); set `app_store` and `preparing` in `Docs/SHIPPED_VERSION.json` and push, which
is what the three websites read. Then the roadmap row "Three releases shipped with no What's New
entry" closes when an App Store update from 5.3 shows the sheet on a device.

## Active constraints

- **Guard memory on long builds**, and never build against the iCloud checkout; both recipes are in
  `Docs/ai/RUNBOOK.md` ("A long build can take this Mac down", "Build"). Test simulator:
  `25E29FA1-6A22-4A86-AE9F-A6F48411E6D0`.
- **Commit to `main`, no branches, no AI co-author trailer.** The pre-commit hook enforces required
  docs; `fastlane/metadata*` changes need a `### <preparing version>` entry in
  `Docs/Release/APP_STORE_METADATA_HISTORY.md`.
- **Non-interactive shells read files as US-ASCII.** Any script reading store copy with `•` must
  read it as UTF-8 (`asc_prepare_release.rb` does); fastlane needs `LC_ALL=en_US.UTF-8`.
- **App Store Connect writes may be refused by the local permission classifier** as a production
  deploy. When that happens, put the change in a script with a dry run and hand the owner one command.
- **Pro subscription descriptions still say "unlimited documents and 5 libraries".** Apple returns
  409 `UNMODIFIABLE` while they are `ACTIVE`, and caps the field at 55 characters. No customer sees
  it (the app never renders it, nothing is promoted); fix it with the next subscription review.
- **Do not delete Frequency, Presence or Repetition Penalty** from Model Parameters; they feed the
  planned Mac model host (`LocalOpenAIServerLLMService.swift`). **The camera stays experimental**
  and DEBUG-gated (`Docs/ai/DECISIONS.md`, 2026-09-13). **Adaptive profiles are unmeasured**; never
  claim they improve answers.
- **Release archives come from Xcode Cloud only.** The recorded reason (a prerelease macOS stamp) no
  longer matches this host (26A428); whether a local archive would now pass is untested.

## Decisions nobody has made

The camera's release gate; the "extremely unhelpful assistant" system prompt reported on the
owner's own install (a stored setting, not a default); `.build` (841 MB) and `build/` (444 MB) at
the repo root syncing to iCloud without `.nosync`; whether a custom reasoning profile should also
steer the app's own Deep Think prompts. None is an agent's to make.

## Verification

Run 2026-09-22, output read:

- Full suite, iOS 27.0 iPhone 18 Pro, with the store scenes and `ContentView` change:
  **495 executed, 3 skipped, 0 failures**, `** TEST SUCCEEDED **`. Memory guard never fired.
- `xcodebuild build` for the iPhone 18 Pro Max simulator: `** BUILD SUCCEEDED **` in 45 s.
- macOS `xcodebuild build` at `0f6c5a0`: `** BUILD SUCCEEDED **`. Not re-run after the DEBUG-only
  screenshot change.
- App Store Connect read back: both 5.4 records `PREPARE_FOR_SUBMISSION` with build 469, What's New
  and description starting as in `fastlane/metadata/en-US/`, keywords ending `research,manual`;
  `APP_IPHONE_67`, `_65`, `_61` and `APP_IPAD_PRO_3GEN_129` each hold the four new files, `COMPLETE`.
- Xcode Cloud #470 (`4777a9f`) `SUCCEEDED`; #471 (`92e4817`) was `RUNNING` when this was written.

**Not verified:** nothing in 5.3 or 5.4 has run on a device. Six v5.3 roadmap rows and the two v5.4
rows stay `In Progress` until someone observes them there.

## Exact Next Action

Read the 5.4 state with `zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 469'` (a dry run; it
prints each platform's state). If both still read `PREPARE_FOR_SUBMISSION`, the owner has not
submitted: tell them the only steps left are the four-question Maximum check on TestFlight build 469
and the Submit button. If either reads `WAITING_FOR_REVIEW` or later, set `in_review` for that
platform in `Docs/SHIPPED_VERSION.json` and push.
