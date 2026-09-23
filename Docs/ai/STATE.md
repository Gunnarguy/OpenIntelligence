# Current State

Updated: 2026-09-22, night, after the 5.4 description correction
Branch/worktree: `main`, primary checkout, pushed to `origin/main`
Last verified commit: 3f6773e

## Objective

**Ship 5.4.** It is prepared in App Store Connect on both platforms and not submitted. Three owner
steps stand between it and review: write the corrected description to App Store Connect (one
command), the Maximum-cap check on TestFlight, and the Submit button.

A second track runs in conversation, not in the repo: **social posts for the app**, X first. See
"Social track" below; nothing in it blocks the release.

## Status

- **5.3 is live on iOS and macOS**, build 464, since 2026-09-18 (`Docs/SHIPPED_VERSION.json`).
- **5.4, both platforms, `PREPARE_FOR_SUBMISSION`, release type MANUAL, build 469 attached**, read
  from the App Store Connect API at 2026-09-22 17:53 PT. Screenshots, What's New and keywords are as
  the previous handoff left them.
- **The 5.4 description in App Store Connect still carries two false sentences.** The repo copy is
  corrected in `3f6773e` (`fastlane/metadata/en-US/description.txt`; the `metadata-ios` file is a
  symlink to it): "Nothing you import leaves your device" now ends "unless you allow it", and "The
  app shows you exactly what would be sent" now reads "shows you how much would be sent and why, and
  asks you first". The agent's `--apply` run was refused by the local permission classifier as a
  production deploy, so the owner runs it (step 1 below).
- **Xcode Cloud #471** (`92e4817`, DEBUG-only screenshot scenes) was `RUNNING` at 17:53 PT; its end
  state was not read. Build 469 stays the build to ship either way.

## Owner steps, in order

1. `cd ~/Documents/GitHub/OpenIntelligence && zsh -ic 'ruby scripts/asc_prepare_release.rb 5.4 469 --apply'`
   (re-attaches 469, rewrites What's New, description and keywords on both platforms, never submits).
2. **TestFlight check of the Maximum cap** on build 469: four questions in Maximum mode; the fourth
   must show "Maximum mode limit reached". Closes the roadmap row about the unenforced cap.
3. **Submit 5.4 for review** on both platforms.
4. Retention message: when Apple grants the API access, `zsh -ic 'ruby scripts/asc_retention_message.rb'`.
5. macOS screenshots need a Screen Recording grant on this Mac.

## The same overclaim, still elsewhere (not changed; outside the store-copy route)

"Shows exactly what would be sent" also appears in `README.md:31`, `Docs/HOW_IT_WORKS.md:44`,
`Docs/STUDY_GUIDE.md:1650` and the in-app sample guide `SampleDocumentManager.swift:59` (Swift, needs
its own route and `PROCEED: IMPLEMENT`). The live 5.3 listing keeps it until 5.4 replaces it.
`SettingsView.swift:2365` renders a Deep Think range with a floor, `max(4, maxSteps - 2)` to
`maxSteps` sessions, which `Docs/reference/LINKEDIN_POSTS.md` lists as a withdrawn claim shape.
None of these pass the release scope test on their own; they are `Future Backlog` unless pulled in.

## Social track (conversation work, not repo work)

- Channels in priority order: X (@Gunzeroni, 43 followers, X Premium bought 2026-09-22), then
  YouTube, LinkedIn, Reddit. Durable notes: auto-memory `social-channels-and-x-premium.md`.
- **Post Desk** artifact https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7, version 2 published:
  counters to 25,000 with the ~280 feed fold marked, a "What Premium changes" section linking each
  limit to its help.x.com page, and the rule that replying to your own post ends its edit window.
- Version 3 (editable replies, a 30-day lock on reusing an opening line, a guard on unfilled
  brackets, and every reply and post rewritten in the owner's voice) exists only in the session
  scratchpad and was not published at the time of writing. Rebuild from the published page if lost.
- Copy on version 2 that must not be repeated: "cites the page", "exactly which passages", "fully
  offline", the untested "300-page contract with wifi off", "Apple never shipped retrieval".
- Day-1 X baseline 2026-09-22: 21 posts, 370 impressions, 2 likes; ten replies were identical text.

## Scheduled, nobody needs to act

- **2026-09-30 09:00 PT:** scheduled task `openintelligence-end-lifetime-sale` removes the sale from
  the 5.3 listing and the three websites. Runs only while the desktop app is open.
- **After 2026-09-29:** App Store Connect, Analytics, Acquisition, Campaigns shows downloads per X
  tag (`X_post`, `X_reply`, `X_build`, `X_halluc`, `X_pro`, `X_private`, `X_appleai`, `X_localai`,
  `X_manuals`, `X_fm`).

## When 5.4 goes live (release close-out, same shape as 5.3's)

Date `## v5.4 - unreleased` in `Docs/USER_CHANGELOG.md` and copy it byte-for-byte to
`OpenIntelligence/Resources/VersionHistory.md` (`VersionHistoryTests` compares them); remove
`<!-- unreleased -->` from `## 5.4` in `CHANGELOG.md` and open `## 5.5 <!-- unreleased -->` above it
**before the next source push**, or `ci_post_clone.sh` stamps a shipped version and the build is
rejected (2026-07-28); set `app_store` and `preparing` in `Docs/SHIPPED_VERSION.json` and push, which
is what the three websites read. The roadmap row "Three releases shipped with no What's New entry"
closes when an App Store update from 5.3 shows the sheet on a device.

## Active Constraints

- **Guard memory on long builds** and never build against the iCloud checkout; recipes in
  `Docs/ai/RUNBOOK.md`. Test simulator `25E29FA1-6A22-4A86-AE9F-A6F48411E6D0`.
- **Commit to `main`, no branches, no AI co-author trailer.** `fastlane/metadata*` changes need the
  `### <preparing version>` entry in `Docs/Release/APP_STORE_METADATA_HISTORY.md` (pre-commit).
- **The description is 3,986 of 4,000 characters.** Any addition needs an equal cut.
- **The permission classifier refuses App Store Connect writes, and on 2026-09-22 also refused the
  dry run of `asc_prepare_release.rb` and reads of docs.x.com.** For a state read, use a GET-only
  query (recipe in auto-memory `app-store-connect-and-fastlane.md`); for a write, hand the owner the
  one command.
- **Non-interactive shells read files as US-ASCII**; store-copy scripts read UTF-8 explicitly.
- **Pro subscription descriptions still say "unlimited documents and 5 libraries"**; Apple returns 409
  while they are `ACTIVE`. Fix with the next subscription review.
- Do not delete Frequency, Presence or Repetition Penalty; the camera stays DEBUG-gated; adaptive
  profiles are unmeasured. Release archives come from Xcode Cloud only.

## Decisions nobody has made

The camera's release gate; the "extremely unhelpful assistant" system prompt on the owner's install;
`.build` (841 MB) and `build/` (444 MB) syncing to iCloud without `.nosync`; whether a custom
reasoning profile should steer Deep Think prompts. None is an agent's to make.

## Working Set

- `fastlane/metadata/en-US/description.txt`: the corrected 5.4 description (3,986 characters).
- `Docs/Release/APP_STORE_METADATA_HISTORY.md`: the 5.4 entry's dated correction note.
- `CHANGELOG.md`: `## 5.4`, `### Fixed`, the **[UI]** entry for the description.
- `scripts/asc_prepare_release.rb`: the write path to App Store Connect; dry run without `--apply`.

## Verification

Run 2026-09-22, output read:

- GET-only App Store Connect read, 17:53 PT: iOS and macOS 5.4 `PREPARE_FOR_SUBMISSION`, MANUAL,
  build 469; 5.3 `READY_FOR_SALE`, build 464; Xcode Cloud #471 `RUNNING`, #470 `SUCCEEDED`.
- `git commit` of `3f6773e`: the pre-commit docs hook passed; `git push`: `main...origin/main` level.
- Description length measured with Python `len()`: 3,986.
- `CloudConsentPromptView.swift:164-183` read: the sheet lists provider, model, character counts,
  passage count, payload and reason; `CloudEvidenceMinimizer` in `ModelExecutionPlanner.swift` sends
  `text`, `documentName` and `pageNumber` per passage.
- **Not verified:** nothing was built or tested this session (no Swift changed). The corrected
  description is not in App Store Connect. Nothing in 5.3 or 5.4 has been observed on a device.

## Blockers / Unknowns

- The App Store Connect write for the description needs the owner (owner step 1). Verify it landed
  by reading `appStoreVersionLocalizations` for each 5.4 version: the description's first sentence
  must end "unless you allow it".

## Exact Next Action

Read both 5.4 records' state and description with a GET-only App Store Connect query. If the
description's opening sentence does not end "unless you allow it", tell the owner owner step 1 is
still open and give the command. If it does and both records still read `PREPARE_FOR_SUBMISSION`,
the remaining owner steps are the TestFlight Maximum check and Submit. If either reads
`WAITING_FOR_REVIEW` or later, set `in_review` for that platform in `Docs/SHIPPED_VERSION.json` and
push.
