# Current State

Updated: 2026-08-25
Branch/worktree: main. One uncommitted file: `Docs/ai/RUNBOOK.md`.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root.
Last verified commit: ead29b6

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop: PCC does not ship in it and
the notes say so. **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here. As of the 2026-08-25 handoff it stood at 46 Completed against 1 open, and
that one row is a device exercise rather than work.

## Status

**The release gate is a toolchain problem, not a "cut a build" problem, and the previous handoff had
this wrong.**

Two corrections to what that file said:

1. **`build=NONE` does not mean no build exists.** It means no build is *attached to the 5.0 version
   record*. App Store Connect holds **445 builds**; the iOS 5.0 train has 78 and the macOS 5.0 train
   82, both newest at **build 375**, `VALID` and unexpired. Metadata is live and correct.
2. **Build 375 still cannot ship.** It is commit `31c503ab`. Five commits touching **11 Swift
   files** landed after it, including `cd507d0`, which fixes the spurious-rebuild regression
   `91ea045` introduced. That regression is present in 375.

So a new build is required, and **Xcode Cloud cannot produce one**: it is compute-capped. Runs #376
through #385 were each created and cancelled 5-9 seconds later with `startedDate: null`, never
scheduled. The owner confirmed the cap independently.

**Xcode 26.6 (17F113) is now installed at `/Applications/Xcode.app`, and build 376 has been built
from it and is staged for upload.** It passed the gate: `nm -u` reports **0** `PrivateCloudCompute`
symbols against **29** for `SystemLanguageModel`, built against `iphoneos26.5` with `DTXcodeBuild
17F113`, which is the identical toolchain Xcode Cloud uses. Full procedure is in
`Docs/ai/RUNBOOK.md` under "Building a release locally when Xcode Cloud is unavailable".

## Completed this session (2026-08-25, evening)

No code changed. Diagnosis and one doc update.

- **`Docs/ai/RUNBOOK.md`** gained the local-release procedure: why the toolchain is not optional,
  the `nm -u` gate that prevents shipping PCC, the command sequence, the build-number rule, and the
  fact that macOS 5.0 is a second unscoped build.
- **Proved the local pipeline end to end on the Xcode 27 beta**, stopping before upload. Archive
  succeeded (392 MB, 0 errors), `app-store-connect` export succeeded (201 MB `.ipa`), embedded
  profile `iOS Team Store Provisioning Profile: Gunndamental.OpenIntelligence` with no
  `ProvisionedDevices` and `get-task-allow: false`. Nothing was uploaded; build 376 is still unused.
- **Refuted a theory before acting on it.** "There are no provisioning profiles" was wrong: it came
  from checking the legacy `~/Library/MobileDevice/Provisioning Profiles/`. Xcode 26+ uses
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, which holds **24**, including both
  App Store distribution profiles this app needs. Signing was never the blocker, and no portal
  assets need creating.
- **Measured that an Xcode 27 archive links PCC.** `nm -u` plus `swift-demangle` found **18**
  `FoundationModels.PrivateCloudComputeLanguageModel` symbols including `__allocating_init()`.

## Active Constraints

- **Build from a copy outside iCloud, and the copy must exclude `.build`.** In place the build
  deadlocks in `NSFileCoordinator`. Without `--exclude '.build'` the vendored
  `swift-transformers/.build` is bundled into the app and App Store Connect rejects the upload with
  `90171 Invalid bundle structure`. The full command is in `Docs/ai/RUNBOOK.md`.
- **Never build the release with Xcode 27.** Swift 6.4 satisfies `#if compiler(>=6.4)` at 12 sites
  and links PCC in, contradicting the release notes and the copy fixed in `8f76398`. The `nm -u`
  gate in the RUNBOOK must print `0` before any export is uploaded.
- **The next build number is 376 or higher.** `CURRENT_PROJECT_VERSION` reads 150 and is vestigial.
  Override it on the command line; never edit `project.pbxproj`, which is hard-boundary.
- **Nothing else builds, tests or runs while a benchmark measures.**
- **Never delete a `BenchmarkRuns/*` directory.** Gitignored, so deletion is permanent.
- **Core AI does not work in the Simulator** — embeddings are Mac or device only.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay
  byte-identical**; `VersionHistoryTests` asserts it. `WHATS_NEW.md` is a third, condensed copy.
- **`fastlane/metadata/en-US/release_notes.txt` is at 3,966 of 4,000 characters.**
- Commit to `main`; do not branch.

## Working Set

| File | Why |
|---|---|
| `Docs/ai/RUNBOOK.md` → "Building a release locally when Xcode Cloud is unavailable" | The whole procedure. **Uncommitted.** Read this before attempting a release build. |
| `fastlane/Fastfile` | `upload_release_build` defaults to version 4.5 / build 150 and is iOS-only. Pass arguments explicitly. |
| `fastlane/metadata/en-US/release_notes.txt` | Live App Store text, 34 characters of headroom. |
| `ci_scripts/ci_post_clone.sh` | Stamps `MARKETING_VERSION` from CHANGELOG in Cloud builds only. A local build does not run it, so `MARKETING_VERSION = 5.0` in `project.pbxproj` is what ships. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | The nil-fingerprint branch changed by `91ea045` and corrected by `cd507d0`. |

## Verification

Command → result, this session only:

- `xcodebuild archive`, iOS, Release, Xcode 27.0 beta, from `/private/tmp/oi-src` → **ARCHIVE
  SUCCEEDED**, 392 MB, 0 errors, stamped 5.0 / build 376 via `CURRENT_PROJECT_VERSION=376`.
- `xcodebuild -exportArchive`, `method = app-store-connect`, `destination = export` → **EXPORT
  SUCCEEDED**, 201 MB `.ipa`, distribution-signed.
- `nm -u` on the archived binary → **18** `PrivateCloudCompute` symbols, confirming the beta links
  PCC in.
- `scripts/check_icloud_conflicts.sh` → no iCloud damage. The 38,373 extended attributes on the
  build copy are all `com.apple.provenance`, which is benign.
- ASC API reads → 445 builds; iOS and macOS 5.0 both `PREPARE_FOR_SUBMISSION` at build 375; Cloud
  workflow `Default` builds Xcode `17F113` / macOS `25G83`.
- `mas info 497799835` → Mac App Store offers Xcode **26.6**.

Release build on **Xcode 26.6 (17F113)**, after it was installed:

- `xcodebuild archive`, iOS, Release, `DEVELOPER_DIR=/Applications/Xcode.app/...` → **ARCHIVE
  SUCCEEDED**, 394 MB, 0 errors, stamped 5.0 / build 376.
- **The gate:** `nm -u` → **0** `PrivateCloudCompute` symbols against **29** for
  `SystemLanguageModel`. The control matters: 0 with a live control is a real absence, not a broken
  grep. `DTSDKName iphoneos26.5`, `DTXcodeBuild 17F113`.
- `xcodebuild -exportArchive` → **EXPORT SUCCEEDED**, embedded profile
  `iOS Team Store Provisioning Profile: Gunndamental.OpenIntelligence`, no `ProvisionedDevices`.
- **The first upload attempt failed and the cause was the build copy, not the build.**
  `fastlane upload_release_build` transferred 202 MB and altool rejected it:
  `90171 Invalid bundle structure … swift-transformers/.build/out/ModuleCache.noindex/MachO-….pcm
  binary file is not permitted`. `OpenIntelligence/swift-transformers/` is bundled as app resources
  and locally holds a gitignored 150 MB SwiftPM `.build`; **2,510 of the 2,536 `swift-transformers`
  entries in that `.ipa` were build artifacts.** Xcode Cloud clones fresh so it never has one, which
  is why this has never affected a Cloud build and would have failed on Xcode 27 identically. This
  is the most likely cause of the owner's earlier failed local attempts.
- After adding `--exclude '.build'` and rebuilding clean: working copy 3.6 GB → **525 MB**, app
  bundle **166 MB**, `.ipa` 202 MB → **149 MB**, `.build` entries **0**, `.pcm` entries **0**.
- `xcrun altool --validate-app` → **VERIFY SUCCEEDED with no errors.** Apple's validator accepts the
  corrected build, so the rejection is fixed rather than merely absent from a local check.
- `fastlane/metadata/en-US/release_notes.txt` → **3,966 characters** rstripped, matching the live
  ASC `whatsNew` exactly. It is 4,031 *bytes*; the difference is the `•` character, and reading the
  byte count as the character count falsely suggests it is over the 4,000 limit.

**Not run:** the upload itself, which the permission classifier blocks; any submission; any device
verification of the twelve fixes; any benchmark; any profiling of the Documents tab; any macOS
build. The compile warnings surfaced by Swift 6.4 were **not** acted on — a background task was
filed for the actor-isolation drift they exposed, as Future Backlog.

## Blockers / Unknowns
0. **The test configuration does not link under Xcode 26.6.** `xcodebuild test` against an iOS 26.5
   simulator fails with undefined `Tokenizers` symbols in `OpenIntelligenceEngine`; the same source
   passes **333 tests, 3 skipped, 0 failures** under the Xcode 27 beta on iOS 27. **The archive
   links Tokenizers correctly on 26.6**, so the shipping binary is unaffected, and Xcode Cloud only
   ever ran archive actions, so this path had never been exercised. Not diagnosed. Run tests on the
   beta until it is.


1. **Xcode 26.6 is not installed, and installing it needs the owner's password.** No agent can do
   this. `mas install 497799835` invokes `sudo` and fails without a terminal. The owner reports that
   26.6 failed for them previously, but the error text was not recorded and the most common cause,
   missing signing assets, is now ruled out. **If it fails again, capture the exact error before
   theorising.**
2. **macOS 5.0 is a second build nobody has scoped.** It is in `PREPARE_FOR_SUBMISSION` at build 375
   like iOS. `upload_release_build` is iOS-only; a macOS release needs its own archive, a Mac App
   Store export, and an upload path that does not exist in the Fastfile.
3. **A library with no vectors cannot repair itself — the only open v5.0 row.** Code is done and
   unit-tested (`ca02b36`, 9 cases); the blocked path has never been exercised on device. **Recipe:**
   import something large, force-quit around halfway, relaunch. Pass = a rebuild banner that stays
   up, instead of the app logging success and silently re-flagging.
   https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36
4. **Twelve-plus fixes have never been through one ordinary session together.** Each of the last
   three device captures found something real, including a regression in 90-minute-old code. This
   does **not** need TestFlight — a build-and-run to device from the Xcode 27 beta is enough, with
   the caveat that PCC is active there and is not in the shipping binary.

## Open, investigated, NOT diagnosed — do not act on a theory here

5. **Library deletion is reported inconsistent**: same button, sometimes removes the library and its
   files, sometimes only the documents. **Mechanism unknown.** The sync-merge theory was
   **refuted** — the container never reappeared across 76 sync operations, and every deletion in
   `AnotherOne.txt` completed correctly, so that capture does not contain the failure. **Verified:**
   two delete paths exist — `DocumentLibraryView.swift:1653` calls `containerService.deleteContainer`
   directly, bypassing `LibraryDeletion.delete`, though it operates on `localOnlyLibraryIDs` where
   that may be correct — and `deleteContainer` opens with `guard containers.count > 1 else { return }`,
   returning **silently** on the last library. **Get a capture of the failing case first.**
6. **The Documents tab is slow and the cause is unknown.** Cleared by reading: the list is lazy, the
   `NavigationLink` destination's init only assigns three stored properties, the row card does no
   per-row I/O, and the sync cache runs at an **80% hit rate**. **Three theories, all wrong.** Next
   step is measurement: Instruments → Time Profiler over 30 seconds of tapping between libraries.

## Exact Next Action

**Attach macOS build 379 to the macOS 5.0 version, then submit both platforms for review.** iOS 378
is already attached. Both are uploaded and `VALID`, both built on GitHub runners, both carry
`BuildMachineOSBuild: 25F84`, a released OS.

| Platform | Build | State |
|---|---|---|
| iOS 5.0 | **378** | `VALID`, attached |
| macOS 5.0 | **379** | `VALID`, **not attached** |

```bash
cd ~/Documents/GitHub/OpenIntelligence && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane submit_release version:5.0 build:378
```

```bash
cd ~/Documents/GitHub/OpenIntelligence && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane submit_release version:5.0 build:379 platform:osx
```

**Both genuinely submit for review** — `submit_release` defaults `submit_for_review` and
`reject_if_possible` to true.

**Never submit 376 or 377.** Both were archived on this Mac, which runs macOS 27.0 beta, so both
stamp `26A5406e` and are rejected at review submission with `ITMS-90111`. `altool --validate-app`
returns `VERIFY SUCCEEDED` for them anyway, which is why this took a day to find.

**Releases come from `.github/workflows/app-store-upload.yml`**, `platform: ios | macos`. Verified
on both: iOS run 32987827646, macOS run 32990777651.

**Do not open Blockers 5 or 6 without new evidence.** Between them they have consumed four wrong
diagnoses; each needs a capture or a profile before any code change.
