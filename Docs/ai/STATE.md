# Current State

Updated: 2026-08-26
Branch/worktree: main
Last verified commit: 66c4f7e

## Objective

Ship v5.0. **The engineering is finished.** Both platforms are built, uploaded to App Store
Connect and valid. What remains is the owner pressing submit in App Store Connect, which is not
an agent action.

## Status

- **macOS 5.0, build 379: LIVE on the App Store.** Submitted and reviewed on 2026-08-26. It was
  archived from `35d59a2` and therefore does **not** contain the 17 changelog entries that landed
  after it. Its App Store notes did carry the full 90-entry 5.0 user-facing list, so nothing was
  withheld from Mac users; only the post-`35d59a2` work is missing from the binary.
- **iOS 5.0, build 386: uploaded, valid, NOT submitted.** Archived from `2d86273`, so it contains
  every fix including the Documents tab work. Delivery UUID
  `98973279-74b1-40ca-abe6-cf5ba51bd40a`.
- **macOS 5.0.1, build 387: uploaded, NOT submitted.** Archived from `66c4f7e`.
- **iOS 5.0.1, build 387: uploaded, unused.** A by-product of the shared version stamp (below).
  Harmless; the owner selects build 386 for the iOS 5.0 record.

## Completed this session

- `f0ed8c0` — Documents tab no longer blocks its appearance on `DocumentationCacheService`
  `statistics().count`. Measured on device at 29/44/76/393ms across four tab entries, against a
  `sinceTap` of 0–4ms; it was the only operation over 250ms in a 5,971-line capture, and the count
  gates a row that never renders because the count is zero. Five earlier attempts failed because
  each measured work occurring *after* the view had appeared. `NavigationTiming` was added to time
  from the tap, which is what isolated it.
- Library-switch instrumentation added (`ContainerPicker` marks the tap, `DocumentLibraryView`
  reports `state` and `settled`). **Never read on device.** See Blockers.
- iOS 27 safety refusals now classify through `FoundationModelErrorMapper.recoveryHint` instead of
  falling through to the generic catch and logging "Unexpected error".
- `66c4f7e` — 5.0.1 cut across CHANGELOG, USER_CHANGELOG, WHATS_NEW, RELEASE_NOTES,
  `VersionHistory.md` and `WhatsNewStore`.
- App Store copy written and character-checked (see Working Set).

## Active Constraints

- **`ci_scripts/ci_post_clone.sh` stamps BOTH platforms from one CHANGELOG heading.** The
  `MARKETING_VERSION[sdk=macosx*]` override was removed on 2026-07-30. A single commit therefore
  cannot produce iOS at one marketing version and macOS at another. This is why iOS 387 exists.
- **The 5.0 train is closed on macOS.** ASC rejected macOS build 386 with `90186` ("train version
  '5.0' is closed for new build submissions") and `90062`. Any future macOS build must exceed 5.0.
- **`ci_post_clone.sh`'s version guard cannot catch this.** It infers "already shipped" from
  whether `[Unreleased]` holds entries, and has no way to ask App Store Connect what is released.
- **`xcodebuild test` hangs repeatedly on this machine.** Two distinct causes seen this session:
  an open Xcode holding SwiftPM locks (`-list` also hangs; quit Xcode), and the
  `com.apple.DeveloperTools` cache going bad *mid-run* even when cleared as a pre-step
  (`-list` responds; no `XCBBuildService`, no CPU). Run tests under `nohup` so a session restart
  does not kill them.

## Working Set

- `OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift` — the appear task and the
  `[LibrarySwitch]` logging that has not been read.
- `OpenIntelligence/Core/Support/NavigationTiming.swift` — tap-to-appear timing.
- `.github/workflows/app-store-upload.yml` — the only working release path.
- `ci_scripts/ci_post_clone.sh` — the shared version stamp.
- App Store copy, in the session scratchpad (not in the repo, copy out if wanted):
  `asc_whatsnew_universal.txt` (3,995 chars, both platforms), `asc_macos_whatsnew.txt` (2,962,
  macOS-only delta), `asc_description_v2.txt` (3,012, restructured description),
  `asc_ios_whatsnew.txt` (3,999).

## Verification

- `xcodebuild test` -> **348 tests, 3 skipped, 0 failures, TEST SUCCEEDED** at `66c4f7e` content.
- `python3 scripts/secret_scan.py` -> no sensitive tokens.
- `scripts/check_icloud_conflicts.sh` -> no iCloud damage.
- iOS 386 and 387, macOS 387 -> released OS stamp, PCC symbols 0 against a `SystemLanguageModel`
  control of 29, `UPLOAD SUCCEEDED`.
- App Store description claims audited against code: `case abstain`,
  `case insufficientEvidence`, `VerificationGateService`, `SourceOnlyAnswerService`, local
  embedding providers, `BNNSVectorDatabase` + `HybridSearchService`, 11 App Intents,
  `localOnly`/`iCloudShared`, `RAGQualityMode` = standard/deepThink/maximum. All verified.

## Blockers / Unknowns

1. **The library-switch cost has never been measured.** The owner's original complaint was "SUPER
   slow when i tap around the documents tab going library to library". The fix that shipped
   addresses *tab appear*, which is what the capture showed; `.task` fires on tab entry only, so a
   library switch within the tab was never in that data. Instrumentation is now in builds 386/387.
   Verify by switching libraries on device and reading `[LibrarySwitch] state ... settled ...`. A
   large `settled` puts the cost in SwiftUI body evaluation, and `withAnimation` wrapping
   `containerService.setActive` in `ContainerPicker.swift` is the first thing to examine.
2. **"pychatry" is still produced and is not the bibliography bug.** Confirmed on device
   2026-08-26: `[LayoutAwareExtractor] Block 1: X=0.08-0.25, text='IN Pychatry an'`. The journal
   prints its name sideways down the page edge, OCR reads that strip badly, and the garbage becomes
   a section heading that every chunk beneath inherits. Recorded as a background task
   (`task_56cd04e5`) and deliberately NOT fixed during the release freeze. `USER_CHANGELOG` and
   `WHATS_NEW` were amended to stop claiming this half is fixed.
3. **"Maximum" names two unrelated controls** — `RAGQualityMode.maximum` and
   `GPUExecutionProfile.maximum`. Not a defect, but a user setting both would reasonably assume
   they are related. Worth a rename.

## Exact Next Action

None for an agent. The owner submits iOS 5.0 (build 386) and macOS 5.0.1 (build 387) in App Store
Connect, using the copy listed in Working Set.

When the owner next runs the app on device, ask for a capture containing `[LibrarySwitch]` and
resolve Blocker 1. That is the only open question from the reported slowness.
