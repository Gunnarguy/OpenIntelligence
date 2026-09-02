# Current State

Updated: 2026-09-02, 14:10
Branch/worktree: main (primary checkout)
Last verified commit: 9c6335f

## Objective

**Ship v5.1 to both platforms, then leave the app on the back burner for a few weeks.**

Submitted. The owner ran both `submit_latest` lanes on 2026-09-02 at about 13:50 after the agent's
attempt was blocked by the auto-mode permission classifier. Nothing is pending on anyone until
Apple reviews.

## Status

**Live on the App Store:** iOS **5.0** (approved 2026-08-27), macOS **5.0.2** (approved 2026-08-28).

**v5.1 is in review on both platforms, set to release automatically on approval.** Read back
from App Store Connect at 14:05 on 2026-09-02: iOS and macOS both `WAITING_FOR_REVIEW`,
`releaseType = AFTER_APPROVAL`, build 433 attached (iOS `7527f51b…`, macOS `5dc4c892…`), commit
`9c6335f`. No `earliestReleaseDate` is set, so approval means live.

| Platform | Version record | Screenshots on the record |
|---|---|---|
| macOS | `6783e646-64be-4c6b-92f7-11036ea1d9aa` | 7 desktop, unchanged |
| iOS | `8a5c273c-147a-46b6-975d-98756c4a2dcc` | iPhone: 8 each at 6.9" (`APP_IPHONE_67`, 1320x2868, set `38baacdb…`), 6.5" (`APP_IPHONE_65`, 1284x2778, set `869cfd6d…`) and 6.3" (`APP_IPHONE_61`, 1206x2622, set `819b8c49…`), the two smaller sets resampled and centre-cropped by 12 px and 1 px from the originals. iPad 12.9": 5, unchanged. The original 6.5" screenshot set was deleted. **App preview video** `OpenIntelligence-Ingestion-ULTRA-SHARP-30FPS.mp4` (5.4 MB, 886x1920) sits only on the 6.5" preview set `cd4bf817…`; Apple scales it to 6.9" automatically per its spec, and the 6.9" preview slot stays empty until the owner supplies the original file, which is on no indexed volume of this Mac (Spotlight by name, by 886 px width, and by portrait 1920 px movie all empty). Apple's hosted copy is a 332x720 player transcode and cannot be re-uploaded. |

**Installed on the owner's iPhone 16 Pro Max** on 2026-09-02 at 12:22: Debug build of `9c6335f` on
Xcode 26.6, stamped `MARKETING_VERSION=5.1`, zero Private Cloud Compute symbols across all six
Mach-O files, installed and launched over the wireless tunnel with `devicectl`. The 5.1 What's New
sheet should have appeared on first launch because the previous install was 5.0.

**Notion v5.1**, written 2026-09-02: 5 rows, all `Completed`, `Shipped On` empty until live. The
new row is
[the sample documents told users questions go to PCC](https://app.notion.com/p/3cf49a74d54f81ed8cc8c81aaa8eff9e).
Two rows moved to Future Backlog with dated notes: the ingestion pause control (a feature) and
[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171),
which passes the data-loss test and is **first in line for the next release** but was never started
and needs the owner to name `WorkspaceSyncService.swift`.

**`5.1 Screenshots/` at the repo root is untracked and not ignored.** Eight `IMG_*.jpeg` from the
owner's phone that are PNG data misnamed (`file` says PNG, Display P3, no alpha). `PNG/` holds
byte-identical copies with the right extension; `PNG-6.5in-1284x2778/` and `PNG-6.3in-1206x2622/`
hold the resized sets that were uploaded. Leave the whole folder out of every `git add`.

## Completed this cycle

- **Learning set, docs only, all pushed (2026-09-02).** `Docs/Engineering/FULL_SYSTEM_TRACE.md` is the
  execution trace with file:line and requested silicon per stage; `Docs/STUDY_GUIDE.md` is the course over
  the 612-term word bank; `Docs/Audio/PASS_1` to `PASS_5` is the spoken version, five passes each one level
  deeper, 76 minutes, with the word bank in `Audio/Reference_word_bank/` for lookup only. Two source
  documents live under `Docs/Research/`. One finding for Future Backlog, not yet a Notion row: the
  `SpeechAnalyzer` transcription branch never compiles (`canImport` of a module that does not exist);
  `SFSpeechRecognizer` runs instead, so nothing is broken.

- **`9c6335f`**: the three sample documents in `SampleDocumentManager.swift` rewritten from source
  (the audit and every source is in the CHANGELOG 5.1 entry and the Notion row), and `WhatsNewStore`
  given its missing 5.0.2 and 5.1 entries. Docs moved in the same commit: `CHANGELOG.md`,
  `Docs/USER_CHANGELOG.md`, `WHATS_NEW.md`, `OpenIntelligence/Resources/VersionHistory.md` (byte
  copy of `USER_CHANGELOG.md`, enforced by `VersionHistoryTests`).
- PCC in the samples is written as built, compiled out, and arriving with iOS and macOS 27, the
  same framing as the App Store description. The owner asked for it "as if working"; it was written
  accurately instead because a cited yes from the library would contradict the metrics bar under
  the same answer. If the owner reaffirms, the three sentences to change are the PCC bullet in
  "What makes OpenIntelligence different", the "Not in this build" paragraph in the PCC guide, and
  the "Where the work runs" bullet in the architecture guide.
- iOS screenshots replaced through the API; procedure now in the RUNBOOK.
- `513127c` earlier the same day: build 432 attached, roadmap triage, RUNBOOK staging note.

## Active Constraints

- **Do not remove the `unreleased` HTML comment from the `## 5.1` heading in `CHANGELOG.md` until
  5.1 is approved and live.** `repoos_router.py` reads it there. Removing it is what "cutting the
  release" means in this repository. `ci_post_clone.sh` stamps `MARKETING_VERSION` from that heading.
- **Do not build a release on this Mac.** Its beta macOS stamps a prerelease `BuildMachineOSBuild`
  that App Store ingestion rejects after a green validate. Xcode Cloud is the builder.
- **`OCRConfiguration.configureRequest` is not the live OCR path.** `StructuredDocumentParser`
  builds the `RecognizeDocumentsRequest` on OS 26+. Two commits fixed the wrong file.
- **`push_metadata` cannot pick copy per platform.** iOS is pushed by the swap-and-restore in
  `Docs/ai/RUNBOOK.md` ("iOS and macOS need different App Store release notes"). Fixing that is one
  line in `fastlane/Fastfile`, which the owner must name.
- **Screenshots are per platform and per display type.** Replacing them with `deliver` needs
  `skip_screenshots: false` and a `screenshots_path`; `push_metadata` hardcodes `skip_screenshots:
  true`. Uploading through the API directly is also fine: `appScreenshotSets` per localization.
- **Benchmark runs are archived, not on disk**, in
  `~/OpenIntelligence-BenchmarkArchive/BenchmarkRuns-2026-09-01.tar.gz`. `BenchmarkRuns/LEDGER.md`
  still indexes them.

## Working Set

| File | Why it matters |
|---|---|
| `CHANGELOG.md` | `## 5.1 <!-- unreleased -->` heading. Marker comes off when 5.1 is live, and the next heading is `5.2` per the `next-version` comment. |
| `fastlane/metadata/en-US/` | macOS copy, canonical. Matches App Store Connect as of 2026-09-02. |
| `fastlane/metadata-ios/en-US/` | iOS `release_notes.txt` and `promotional_text.txt`. Matches App Store Connect as of 2026-09-02. |
| `fastlane/Fastfile` | `submit_latest` submits with the newest processed build; it also re-pushes metadata from `fastlane/metadata/`, so the iOS swap applies to it too. |
| `Docs/ai/RUNBOOK.md` | Release section, the iOS swap, and the new "stage a build without submitting" note. |
| `Docs/SHIPPED_VERSION.json` | Per-platform shipped record. Update when 5.1 is approved. |
| `HANDOFF.md` | Cross-tool handoff. Current-state section refreshed 2026-09-02. |

## Verification

Run 2026-09-02, output read:

- `bash scripts/build_simulator_smoke.sh` → **Simulator smoke build succeeded** (second attempt;
  the first hung at the header on 1.1 GB of stale `.simulator-smoke.nosync/DerivedData`).
- `xcodebuild test` on the iOS 27 simulator `8FA2B3CE…`, DerivedData `/private/tmp/oi-build` →
  **392 tests, 3 skipped, 0 failures**. Took five attempts: four stalled at the header while
  another session's OpenManual test loop and then an idle Xcode held the SwiftPM lock.
- `python3 scripts/verify_doc_claims.py` → 162 claims, all pass. `python3 scripts/secret_scan.py` → clean.
- Device build, Xcode 26.6, `generic/platform=iOS`, `MARKETING_VERSION=5.1` → **BUILD SUCCEEDED**;
  `nm -u | grep -ci PrivateCloudCompute` → 0 on all six Mach-O files; `devicectl install` and
  `launch` succeeded.
- App Store Connect API: eight `appScreenshots` in set `38baacdb…` all `COMPLETE` at 1320x2868;
  old set `b9708d9b…` deleted with HTTP 204.

**Not verified:** the refreshed samples appearing in a library that held the old ones (the closing
condition on the Notion row); the What's New sheet actually rendering on the phone. Both are one
look at the owner's iPhone.

## Blockers / Unknowns

1. **Somewhere the owner can see says 5.1 is expected on September 16, and no search found it.**
   Not in this repo (every text type), not in `Gunzino`, `Fascinaiting`, `Gunnarguy-Portfolio`,
   `OpenIntelligence-Public` or `SocialPosting` checkouts, not in the Notion Public Roadmap, Product
   Hub or Posts pages, not in GitHub issues or releases, not in Spotlight's full-text index, and
   App Store Connect has no such field (`earliestReleaseDate` is empty). Unchecked: the live
   `gunzino.me/openintelligence` and `fascinaiting.me` pages, which may differ from their checkouts.
   The owner said to drop it. If it resurfaces, fix it at the source and note where it was.
2. **`fastlane submit_latest` is blocked for the agent** by the auto-mode classifier, twice as a
   plain command. Future submissions come from the owner's terminal unless they add a Bash
   permission rule for it in `.claude/settings.local.json`.
3. **The `SpeechAnalyzer` path never compiles** (`SpeechAnalyzerService.swift`, `#if
   canImport(SpeechAnalyzer)`, no such module in the iOS 27 SDK). Transcription works through
   `SFSpeechRecognizer`. Future Backlog, **not yet a Notion row**.
4. **`scripts/test_stop_handoff.sh` has a failing assertion.** Unrelated to shipping.

## Exact Next Action

**Nothing until Apple approves.** The app is on the back burner. When both versions read
`READY_FOR_SALE` (`GET apps/6756559175/appStoreVersions?filter[versionString]=5.1`):

1. Remove the `unreleased` HTML comment from the `## 5.1` heading in `CHANGELOG.md`. Update
   `Docs/SHIPPED_VERSION.json` for both platforms. Change `## v5.1 - unreleased` in
   `Docs/USER_CHANGELOG.md` to the approval date and copy the file byte-for-byte to
   `OpenIntelligence/Resources/VersionHistory.md` (`VersionHistoryTests` enforces this); do the same
   heading in `WHATS_NEW.md`.
2. Set `Shipped On` to `iOS, macOS` on the five v5.1 Notion rows.
3. Commit. The next release's first row is
   [Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171);
   it needs the owner to name `WorkspaceSyncService.swift` and a `v5.2` option in `Target Release`.

If Apple rejects, the record returns to `DEVELOPER_REJECTED`, which is editable; fix, push, and
re-attach the new build per the RUNBOOK staging note before resubmitting.
