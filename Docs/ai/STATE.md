# Current State

Updated: 2026-09-02, 19:40
Branch/worktree: main (primary checkout)
Last verified commit: a70fab8

## Objective

**5.2, the Private Cloud Compute release, is staged so that release day is attach and submit.**
5.1 is recorded as shipped on both platforms. The app is otherwise on the back burner.

## Status

**Shipped:** 5.1 on both platforms per `Docs/SHIPPED_VERSION.json`. Apple's actual state at
14:05 on 2026-09-02: macOS 5.1 `READY_FOR_SALE` (build 433, released automatically); iOS 5.1
`WAITING_FOR_REVIEW` with the same build, release type `AFTER_APPROVAL`. **The owner chose to
record iOS as shipped before approval**; `in_review.ios` in the file records the truth. Nothing
further happens to 5.1 when Apple approves it.

**5.2 is fully staged in this commit and cannot be built until Apple publishes the release Xcode
27.** The Xcode Cloud `Default` workflow is pinned by id to Xcode 26.6 (Swift 6.3). Every push to
`main` from now until release day fails in `ci_post_clone.sh` in seconds with "version 5.2
requires Swift 6.4"; that is intended. Xcode Cloud offers Xcode 27 beta 6 today
(`27A5252f`); betas cannot be submitted and the owner declined a TestFlight rehearsal.

**Release day is scripted.** `Docs/ai/RUNBOOK.md`, "Enabling Private Cloud Compute", "Release day,
in order": five steps, three of them one command each. The scheduled routine
`openintelligence-51-pcc-flip` (renamed in description to the 5.2 release routine, daily at 09:00
from now) runs steps 1 to 4 the morning Xcode 27 appears and reports; the owner runs the two
submit commands because the permission classifier blocks `fastlane submit_latest` from an agent.
After approval the routine runs step 6, the claim flip.

**Notion.** v5.1: 5 rows `Completed`, `Shipped On: iOS, macOS`. v5.2 (option added 2026-09-02):
[Private Cloud Compute ships](https://app.notion.com/p/3cf49a74d54f8185ae8ddaf991244d0a) `To Do`,
and [How It Works told iOS 26 users the app asks before sending](https://app.notion.com/p/3d049a74d54f81439d82f10955226ba0)
`Completed` in code, `Shipped On` empty until 5.2 is live. Future Backlog 73.

## Completed this cycle

- **Release guards are version-aware.** `ci_scripts/ci_post_xcodebuild.sh` Gate 1: below 5.2 fail
  on any `PrivateCloudCompute` symbol, from 5.2 fail on zero, always against a live
  `SystemLanguageModel` control. `ci_scripts/ci_post_clone.sh`: fail fast when the CHANGELOG
  version is 5.2+ and the runner's Swift is below 6.4. The `## 5.2` heading is the single switch.
- **`scripts/xcode_cloud_toolchain.rb`** lists Xcode Cloud's toolchains and repoints the workflow
  (`--set 'Xcode 27'`). API PATCH verified accepted 2026-09-02.
- **In-app copy flips on the compiler.** `DeviceCapabilities.pccRoutingCompiledIn` (RAGService)
  drives `supportsPrivateCloudCompute`, which now means "this build can route to PCC and the OS is
  27"; before, it meant "the OS has Apple Intelligence" and four screens misread it. The metrics
  bar footer, Settings PCC row and capability list, Glossary token/context/PCC/routing entries, and
  the three sample guides (`SamplePCCCopy`, seven interpolation points) all read it.
- **5.2 copy written:** `CHANGELOG.md` `## 5.2 <!-- unreleased -->` with four entries;
  `Docs/USER_CHANGELOG.md` `## v5.2 - unreleased` (byte-copied to
  `OpenIntelligence/Resources/VersionHistory.md`); `WHATS_NEW.md`; `WhatsNewStore` 5.2 sheet;
  `fastlane/metadata*/en-US/release_notes.txt` and `promotional_text.txt` (both platforms, same
  text); `description.txt` PCC sentence in present tense (per-version in ASC, so safe to push to
  the 5.2 records only).
- **5.1 cut:** `unreleased` marker off `## 5.1`; `Docs/RELEASE_NOTES.md` v5.1 section;
  `USER_CHANGELOG` dated; `SHIPPED_VERSION.json` 5.1 both, preparing 5.2.
- **Site patches held, not applied:** `Docs/Release/5.2/sites/{Fascinaiting,Gunzino,Gunnarguy-Portfolio}.patch`,
  each verified with `git apply --check` in its checkout. They flip every future-tense PCC sentence
  on the three sites; apply after 5.2 approval (routine step 6). Fascinaiting's roadmap re-synced
  today (236 rows, `shipped_on` exported, 5.1 lane now Shipped).

## Active Constraints

- **`fastlane/metadata*` now hold 5.2 copy.** Running `push_metadata version:5.1` would overwrite
  the live 5.1 listing with 5.2 text. Do not.
- **Do not repoint Xcode Cloud at a beta.** `xcode_cloud_toolchain.rb` warns; the owner declined
  the rehearsal.
- **Do not remove the `unreleased` marker from `## 5.2`** until 5.2 is live (router reads it).
- **Do not build a release on this Mac** (prerelease `BuildMachineOSBuild`, ITMS-90111).
- **The Gunnarguy-Portfolio checkout carries another session's uncommitted changes** (four
  `snapshot.html`, `Analytics.astro`). Stay out of it; apply the patch there only via the routine.
- **`fastlane/Fastfile` is unchanged**; the iOS metadata swap remains manual (RUNBOOK).

## Working Set

| File | Why it matters |
|---|---|
| `Docs/ai/RUNBOOK.md` "Enabling Private Cloud Compute" | The release-day list. Read it before doing anything on 5.2. |
| `scripts/xcode_cloud_toolchain.rb` | Step 1 and 2 of release day. |
| `ci_scripts/ci_post_clone.sh`, `ci_scripts/ci_post_xcodebuild.sh` | The guards; their messages name the fix when they fail. |
| `CHANGELOG.md` | `## 5.2 <!-- unreleased -->` first; the marker comes off when live. `next-version: 5.3`. |
| `Docs/Release/5.2/sites/*.patch` | The website flips, held. |
| `Docs/SHIPPED_CAPABILITIES.json` | `private_cloud_compute.status` flips to `shipping` at approval, not before. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | `DeviceCapabilities.pccRoutingCompiledIn`. |
| `OpenIntelligence/Features/Documents/Library/SampleDocumentManager.swift` | `SamplePCCCopy`. |

## Verification

Run 2026-09-02 evening, output read, all against the staged 5.2 tree:

- `bash scripts/build_simulator_smoke.sh` → **Simulator smoke build succeeded**.
- `xcodebuild test`, iOS 27 simulator → **392 tests, 3 skipped, 0 failures**.
- `python3 scripts/verify_doc_claims.py` → all pass. `scripts/secret_scan.py` → clean.
  `scripts/verify_capabilities.py` → all anchors present. `bash scripts/test_enforce_docs_hook.sh`
  → 10 passed.
- Guard logic dry-run: `sort -V` compare marks 5.1 and 5.1.1 as PCC-forbidden, 5.2/5.10/6.0 as
  PCC-required; release Xcode reports Swift 6.3 (fails the 5.2 clone check), Xcode-beta reports
  6.4 (passes).
- `repoos_router.py preflight` → active release `v5.2`, in_development, last shipped `v5.1`.
- `git apply --check` of each site patch in its own checkout → applies cleanly.

**Not verified:** any PCC behaviour on a 5.2 binary, because none exists yet. The compiled-in
copy branches were parsed, built (the simulator build uses Xcode-beta, Swift 6.4, so
`pccRoutingCompiledIn` was `true` there and the suite passed with it) but not read on a device.

## Blockers / Unknowns

1. **Apple has not published the release Xcode 27.** Everything waits on it. The routine checks
   daily.
2. **Xcode Cloud will fail every push until release day.** Expected; the failure message says why.
   If a 5.1 hotfix is ever needed, see the RUNBOOK caveat.
3. **PCC context window.** Glossary and Settings no longer assert a number for PCC; the app reads
   it from the SDK at runtime. Nobody has recorded what iOS 27 reports. Read it from Settings on
   the first 5.2 device install.
4. **The 5.2 What's New says "Requires iOS, iPadOS or macOS 27"** for the PCC step; on 26 the
   same binary runs fully on device. True by construction (`#available(iOS 27)` inside the
   compiled-in paths); confirm on the first 5.2 build on an iOS 26 device if one is at hand.

## Exact Next Action

**Nothing today.** The routine runs at 09:00 daily. When it reports that Xcode 27 is on Xcode
Cloud and the build is attached, run the two submit commands it prints. If the routine has not
fired by the day after Apple's iOS 27 release, run step 1 by hand:

```bash
ruby scripts/xcode_cloud_toolchain.rb
```
