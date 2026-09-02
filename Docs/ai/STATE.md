# Current State

Updated: 2026-09-02, 13:20
Branch/worktree: main (primary checkout)
Last verified commit: 9c6335f

## Objective

**Ship v5.1 to both platforms, then leave the app on the back burner for a few weeks.**

Everything the owner asked for is done except the submission itself, which waits on their word.

## Status

**Live on the App Store:** iOS **5.0** (approved 2026-08-27), macOS **5.0.2** (approved 2026-08-28).

**v5.1 is staged on both platforms, not submitted.** Both records are `PREPARE_FOR_SUBMISSION`
with copy verified exact against the repo and screenshots replaced on iOS. **Attached build: Xcode Cloud 433, commit `9c6335f`**, run #433 `COMPLETE SUCCEEDED` at 12:35 on
2026-09-02, both platforms `VALID`, attached with HTTP 204 and read back: iOS `7527f51b-28f3-422f-b8cf-7675373db901`,
macOS `5dc4c892-6719-44ea-8e27-b8976bbadd21`. Build 432 is superseded; it lacks the sample rewrite
and the What's New entries.

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

1. **Submission waits on the owner.** Nothing else blocks it.
2. **The `SpeechAnalyzer` path never compiles** (`SpeechAnalyzerService.swift`, `#if
   canImport(SpeechAnalyzer)`, no such module in the iOS 27 SDK). Transcription works through
   `SFSpeechRecognizer`. Future Backlog, **not yet a Notion row**.
3. **`scripts/test_stop_handoff.sh` has a failing assertion.** Unrelated to shipping.

## Exact Next Action

**Submit on the owner's word. Nothing else is pending.**

1. Optional: `GET appStoreVersions/{id}/build` for both records should read the build 433 ids above.
2. Submit macOS, then iOS with the metadata swap, from the repo root with the
   `APP_STORE_CONNECT_*` env loaded:

   ```bash
   fastlane submit_latest version:5.1 platform:osx
   ```

   ```bash
   M=fastlane/metadata/en-US
   cp "$M/release_notes.txt" /tmp/mac_rn.bak; cp "$M/promotional_text.txt" /tmp/mac_pt.bak
   trap 'cp /tmp/mac_rn.bak "$M/release_notes.txt"; cp /tmp/mac_pt.bak "$M/promotional_text.txt"' EXIT
   cp fastlane/metadata-ios/en-US/release_notes.txt "$M/release_notes.txt"
   cp fastlane/metadata-ios/en-US/promotional_text.txt "$M/promotional_text.txt"
   fastlane submit_latest version:5.1 platform:ios
   ```

   `submit_latest` uses `skip_screenshots: true`, so the new iOS screenshots survive it. Both lanes
   must report build 433. Confirm `git status` is clean afterwards.
3. When Apple approves: remove the `unreleased` marker from the `## 5.1` heading, update
   `Docs/SHIPPED_VERSION.json`, set `Shipped On` to `iOS, macOS` on the five v5.1 Notion rows, and
   commit.
