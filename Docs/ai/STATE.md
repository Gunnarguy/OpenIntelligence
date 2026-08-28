# Current State

Updated: 2026-08-27
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: 55f31cb

## Objective

None active. macOS 5.0.2 is uploaded to App Store Connect and awaiting review. The objective that
drove this session — make document import work on macOS — is complete and verified on device.

## Status

**macOS 5.0.2, build 389, uploaded 2026-08-27** (workflow run 33127559144, every gate passed).
Build 388 (run 33124470371) was uploaded earlier the same day and is **superseded**; 389 is a strict
superset. Uploading does not replace, so both sit in App Store Connect. **Submit 389.**

Working tree is clean. Nothing is staged or pending.

## Completed

Four user-facing defects, all macOS-only. iOS pickers were never on these paths.

1. **Add Documents opened nothing** (`050bbe8`). All three macOS pickers called
   `NSOpenPanel.runModal()` from a SwiftUI `.onAppear`, which fires inside a CATransaction commit
   where AppKit refuses to start a nested modal loop. It discarded the call and logged
   `Suppressing invocation of -[NSApplication runModalForWindow:]`. Now `beginSheetModal(for:)`.
2. **Finder drag-and-drop** (`050bbe8`). Never existed — `onDrop` and `dropDestination` appeared in
   no file at `f861b91`. Added over the library area, routed through the same quota → copy → review
   path as the picker. Directories are excluded deliberately.
3. **Sample documents duplicated themselves** (`e2b5eef`). `refreshStaleSamples` matched
   `storageFilename` exactly, so `-2`/`-3` copies from earlier passes were invisible to all three
   call sites and accumulated. `SampleDocumentDescriptor.matchesStoredCopy(_:)` now matches the
   numbered form; 7 regression tests pin the boundary.
4. **Library Settings rendered as a split view** (`d5be5c5`). `ContainerSettingsSheet` used
   `NavigationView`, which macOS resolves to two columns. Now `NavigationStack` plus an explicit
   macOS frame on the sheet body.

Also: App Store copy for 5.0.2 (`a3a4575`), and `SHIPPED_VERSION.json` records 5.0.1 live and
5.0.2/389 uploaded (`36b2f87`).

5. **CI was billing 4,020 minutes against a 3,000 allowance** (`55f31cb`). `ci.yml` ran one macOS
   job on every push to `main` with no path filter; GitHub bills macOS at 10x. Over the 30 runs to
   2026-08-28 that was 402 wall minutes, and ~11 of those commits changed no Swift. The capability
   guard (pure Python) moved to `ubuntu-latest` and still runs on every commit; the macOS build is
   now gated on whether anything build-relevant changed, via an ignore-list so an unrecognised path
   still builds. A `concurrency` group cancels superseded runs.

## Active Constraints

- **`app_store` in `Docs/SHIPPED_VERSION.json` stays at `5.0`** while iOS is the lagging platform.
  macOS is 5.0.1 live. The file's own ACTION note says to set it to 5.0.1, which contradicts its
  next sentence; the conservative reading is recorded in the file's `_comment`.
- **`ci_scripts/ci_post_clone.sh` stamps `MARKETING_VERSION` from the first `## <number>` heading in
  `CHANGELOG.md`** and refuses to build while `## [Unreleased]` holds any `-` or `###` line. Do not
  hand-edit `project.pbxproj` for a version bump; the macOS-specific override was removed 2026-07-30.
- **The App Store Upload workflow runs no tests.** A red suite reaches Apple unnoticed. Run
  `xcodebuild test` locally before dispatching.

## Working Set

Nothing uncommitted. Files to open if continuing this area:

| File | Why |
|---|---|
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Holds all three filed defects: the reload loop, the uncoordinated writes, the unbounded ubiquity await at line ~461 |
| `OpenIntelligence/Features/Documents/Settings/ContainerSettingsSheet.swift` | The one `NavigationView` already converted; the pattern for the other 17 |
| `OpenIntelligence/Features/Documents/Components/DocumentPicker.swift` | `ImportedFileStaging`, now the single copy-into-workspace path for every surface |
| `Docs/reference/LINKEDIN_POSTS.md` | Gitignored. Holds an unposted v5.x draft that supersedes the earlier unposted v5.0 draft |

## Verification

Commands run this session, with observed output:

- `xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-test-clean`
  → `355 tests, 3 skipped, 0 failures`, `** TEST SUCCEEDED **`
- `xcodebuild -scheme OpenIntelligence -destination "platform=macOS" -configuration Release -derivedDataPath /private/tmp/oi-mac-rel build`
  → `** BUILD SUCCEEDED **`, 0 errors
- `bash scripts/build_simulator_smoke.sh` → `Simulator smoke build succeeded`
- GitHub Actions run 33127559144 → all steps success, `Uploaded macos build 389`
- New `ci.yml` on `55f31cb` → `Capability claims` (ubuntu) succeeded; the macOS `Build` job was
  correctly triggered because the commit touched `.github/workflows/`. Path filter dry-run over the
  last 14 commits: 10 skip, 4 build, and both constructed edge cases resolve correctly
  (`OpenIntelligence/Resources/VersionHistory.md` alone builds, `Docs/USER_CHANGELOG.md` alone skips).
- **On device (owner's Mac, 2026-08-27):** capture of 43,576 lines during active use contains
  **zero** `Suppressing invocation` lines; documents imported; 12 iCloud libraries synced. The owner
  confirmed in conversation that file upload now works.

**Not verified:** that Library Settings renders correctly. Layout is exactly what a build and a test
suite cannot confirm, and screen access was unavailable. It shipped in 389 on reasoning alone.

## Blockers / Unknowns

None blocking. Three defects filed to Notion `Future Backlog`, each with a closing condition:

1. **[420 workspace reloads per import](https://app.notion.com/p/3ca49a74d54f81a6b8c1e4827a6585fa)** —
   one import produced 420 sequential `[WorkspaceReload] #n` entries; 42% of a 23,045-line capture
   was `CoreUI` window relayout, 0.5% was extraction. Verify by importing one file and counting
   `WorkspaceReload` in the console. `WorkspaceSyncService.isSyncWriteInProgress` already exists and
   is the shape of the gate needed.
2. **[17 views still use NavigationView](https://app.notion.com/p/3ca49a74d54f81eb867cf24a119af0c1)** —
   same split-view defect. Also: of 39 `.sheet(` presentations, exactly one sets a macOS frame.
3. **[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)** —
   **this one corrupts user data and has already done so.** `coordinatedMergeData` covers 4 paths,
   which had 0 conflict copies; 6 uncoordinated families had all 599. It qualifies for the active
   release under test 1; pull it forward when the next version is named.

**Needs the owner's decision — Xcode Cloud is duplicating the release build and discarding it.**
Workflow `Default` on product `c6efe188-583b-47d8-9db8-dc8e17ecc7c5`, workflow id
`E6B22BA8-D5A5-4664-941A-3EC1C3F50910`: `isEnabled: true`, branch trigger `main`,
`filesAndFoldersRule: null`, and **two ARCHIVE actions** (macOS and iOS). So every push to `main`
runs two full release archives. Since 2026-08-01 that is 52 runs and 641.9 minutes (10.7 h) against
a 25 h allowance, plus 0.7 h on OpenScan, which shares the same allowance along with OpenResponses,
OpenCone and OpenAssistant.

Nothing consumes those archives. Builds 388 and 389 both shipped through
`.github/workflows/app-store-upload.yml`, because a beta Mac stamps an unsubmittable
`BuildMachineOSBuild` — that is structural, not a config bug, so Xcode Cloud cannot produce a
submittable binary on this machine's toolchain either. Recommended action is to disable that
workflow (`PATCH ciWorkflows/E6B22BA8-D5A5-4664-941A-3EC1C3F50910`, `attributes.isEnabled=false`);
the conservative alternative is to add a `filesAndFoldersRule` so docs commits stop triggering it.
**Not done: this is a change to the owner's App Store Connect configuration and needs explicit
approval.** Query it with the ASC API using `APP_STORE_CONNECT_{API_KEY_ID,ISSUER_ID,API_KEY_PATH}`,
which are already in the environment.

Note `Docs/ai/RUNBOOK.md` contradicts itself on this: line ~488 still says "Xcode Cloud is the
builder", line ~513 says to use the Actions workflow instead. The second is correct.

**Owner's machine, repaired this session, not a code fix:** 136 files in
`~/Library/Mobile Documents/iCloud~Gunndamental~OpenIntelligence/` had `st_size > 0, st_blocks == 0`
and blocked any read forever, which had killed sync since 2026-08-10. Removing them took a full
directory copy from a 7-minute timeout to 1 second. Casualties: `deleted_containers.json` (delete
tombstones lost, so previously-deleted libraries may reappear once) and two vector index metadata
files (General and Library 7 re-indexed themselves). Two libraries are both named "Library 5"
(`FF9333D1…` populated, `0AA60E5A…` empty) from the merge.

## Exact Next Action

None. The objective is complete and verified. There is no active objective.

**Ask the owner whether to disable the Xcode Cloud `Default` workflow** (see Blockers). It is
burning a shared 25-hour allowance on archives nothing uses, and it is the only outstanding item
that costs money every time anyone pushes.

If macOS 5.0.2 clears review, set `app_store_by_platform.macos` to `"5.0.2"` in
`Docs/SHIPPED_VERSION.json` and clear `in_review`; leave `app_store` at `5.0` until iOS catches up.

Otherwise ask the user what to pick up, or take a roadmap item from the Notion database via the
`notion-roadmap` skill. The three rows above are the highest-value candidates, and defect 3 is the
only one that loses user data.
