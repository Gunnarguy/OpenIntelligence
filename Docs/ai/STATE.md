# Current State

Updated: 2026-09-02
Branch/worktree: main (primary checkout)
Last verified commit: 2154df3

## Objective

**Ship v5.1 to both platforms, then leave the app on the back burner for a few weeks.**

The release is staged and waiting on the owner's screenshots. Nothing else in this repository
is active until the owner returns.

## Status

**Live on the App Store:** iOS **5.0** (approved 2026-08-27), macOS **5.0.2** (approved 2026-08-28).

**v5.1 is staged in App Store Connect on both platforms, not submitted.** Verified 2026-09-02
through the App Store Connect API:

| Platform | Version record | State | Attached build | What's New matches local file |
|---|---|---|---|---|
| macOS | `6783e646-64be-4c6b-92f7-11036ea1d9aa` | PREPARE_FOR_SUBMISSION | 432 (`c0bada13-…`) | exact, `fastlane/metadata/en-US/release_notes.txt` |
| iOS | `8a5c273c-147a-46b6-975d-98756c4a2dcc` | PREPARE_FOR_SUBMISSION | 432 (`7b976362-…`) | exact, `fastlane/metadata-ios/en-US/release_notes.txt` |

Promotional text matches the local files on both platforms. Screenshots currently on the records
are the previous release's: macOS 7 desktop, iOS 9 iPhone 6.5" and 5 iPad Pro 12.9". The owner
said they may replace them and will say where the new ones are.

**Build 432 is the 5.1 binary.** Xcode Cloud run #432 built commit `845c7b9` on 2026-09-01 and
uploaded both platforms; both processed to VALID. Every commit after `845c7b9` (`4840078`,
`273b007`, `9359936`, `aea17d8`, `2154df3`) touches only `Docs/` and `HANDOFF.md`, so build 432
contains all 5.1 code. A new push to `main` triggers a new Xcode Cloud run and a build 433 that
would not be attached; that is harmless but pointless, so avoid source pushes until 5.1 is submitted.

**The ingestion changes are device-verified on the owner's Mac.** The owner ingested a large PDF
against the 5.1 code on 2026-09-02 and reported it working well. That is the owner's word, not a
trace this session read; it closes the render, idle-churn and OCR rows for release purposes.

**Notion v5.1**, written 2026-09-02: 4 rows, all `Completed`, `Shipped On` empty until live. Two
rows moved out to Future Backlog with dated notes in their bodies:

- [Ingestion has no pause control](https://app.notion.com/p/3cb49a74d54f819797e8cea0e96d62b9): a
  feature, fails all three release tests.
- [Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171):
  passes the data-loss test and is **first in line for the next release**, but was not started and
  needs the owner to name `WorkspaceSyncService.swift`. Not promised in the 5.1 release notes.

## Completed this cycle

- Build 432 attached to both 5.1 version records via `PATCH appStoreVersions/{id}/relationships/build`
  (HTTP 204 each). Script: session scratchpad `asc_attach.rb` on top of `asc_lib.rb`; the same
  JWT approach as `scripts/asc_healthcheck.rb`, reading the `APP_STORE_CONNECT_*` env from `~/.zshrc`.
- Live What's New and promotional text diffed against the local files, exact match after trailing
  newline.
- Notion: render row Completed 2026-09-02; two rows retargeted to Future Backlog.
- Earlier in the cycle, all in build 432: macOS `CGBitmapContext` render (`961f446`), restored
  progress (`7e717a1`), OCR settings on the live path (`d610183`), idle vector churn (`46aa57e`),
  macOS app icon (`0a90bfe`), `scripts/verify_doc_claims.py` (`845c7b9`).

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

- App Store Connect API `GET apps/6756559175/appStoreVersions` → 5.1 IOS and MAC_OS both
  `PREPARE_FOR_SUBMISSION`.
- `GET builds?filter[version]=432` → two builds, IOS and MAC_OS, both `VALID`, minOS 26.0.
- `GET ciProducts/c6efe188…/buildRuns` → run #432 `COMPLETE SUCCEEDED`, commit `845c7b9`.
- `PATCH appStoreVersions/{id}/relationships/build` → HTTP 204 for both; `GET …/build` read back
  the attached ids.
- What's New exact diff against local files → true on both platforms.
- `git diff --name-only 845c7b9..HEAD | grep -v '^Docs/'` → only `HANDOFF.md`.

**Not run this session:** no build, no test suite, no ingestion trace. The last suite run is
recorded in git history at `4840078` (392 tests, 3 skipped, 0 failures, 2026-09-01).

## Blockers / Unknowns

1. **Submission is waiting on the owner.** They may supply new screenshots first. If they say to
   submit without them, run the two `submit_latest` commands in the Exact Next Action.
2. **The restored-progress fix (`7e717a1`) is unverified on device.** Quit the Mac app mid-import
   and reopen; the item should show its real page count, not zero. The release notes claim this.
   Thirty seconds, optional, and the resume logic itself was never changed.
3. **The `SpeechAnalyzer` path never compiles** (`SpeechAnalyzerService.swift`, guarded by
   `#if canImport(SpeechAnalyzer)`, no such module in the iOS 27 SDK). Transcription still works
   through `SFSpeechRecognizer`. Future Backlog, **not yet a Notion row**.
4. **`scripts/test_stop_handoff.sh` has a failing assertion.** Unrelated to shipping.

## Exact Next Action

**Wait for the owner's screenshots, then submit.** In order:

1. If the owner names a screenshot directory, upload per platform and display type to the 5.1
   localizations (`0f3cc2bb-…` macOS, `3b8a2fff-…` iOS) and confirm the counts read back, then
   show the owner the counts before submitting.
2. Submit macOS, then iOS with the swap, from the repo root with the `APP_STORE_CONNECT_*` env loaded:

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

   Both lanes must report build 432. Confirm `git status` is clean afterwards.
3. When Apple approves: remove the `unreleased` marker from the `## 5.1` heading, update
   `Docs/SHIPPED_VERSION.json`, set `Shipped On` to `iOS, macOS` on the four v5.1 Notion rows, and
   commit.
