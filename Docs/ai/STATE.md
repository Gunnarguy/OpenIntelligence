# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: 26cf9f8

## Objective

None active. macOS 5.0.2 is live, iOS 5.0 is live, and 5.1 is open as the unified next version for
both platforms. The two objectives this session ran on — make macOS document import work, and stop
CI costing money — are both complete and verified.

## Status

**Shipped.** Read from App Store Connect 2026-08-28: iOS newest `READY_FOR_SALE` is **5.0**, macOS is
**5.0.2**. Both platforms have 5.1 records in `PREPARE_FOR_SUBMISSION`. Nothing is in review.

**Releases build on Xcode Cloud. GitHub Actions is deleted.** Xcode Cloud was always the working
release path; Actions was a stopgap after the free 25 compute hours ran out, and it then went into
paid overage itself — 4,020 billed minutes against a 3,000 allowance, because macOS runners bill at
10x and every push booted one. 100 Xcode Cloud hours were bought, so the reason for Actions is gone.
Xcode Cloud run **427: SUCCEEDED**, both platforms.

Working tree is clean.

## Completed

1. **Add Documents opened nothing on macOS** (`050bbe8`). All three macOS pickers called
   `NSOpenPanel.runModal()` from a SwiftUI `.onAppear`, inside a CATransaction commit where AppKit
   refuses to start a nested modal loop. Now `beginSheetModal(for:)`.
2. **Finder drag-and-drop** (`050bbe8`). Never existed — `onDrop` and `dropDestination` appeared in
   no file. Directories are excluded deliberately.
3. **Sample documents duplicated themselves** (`e2b5eef`). `matchesStoredCopy(_:)` recognises the
   `-2`/`-3` form at all three call sites; 7 regression tests pin the boundary.
4. **Library Settings rendered as a split view** (`d5be5c5`). `NavigationView` → `NavigationStack`.
5. **CI cost**, first by splitting `ci.yml` (`55f31cb`), then by retiring Actions entirely
   (`546df1f`).
6. **Xcode Cloud release gates** (`3afd57b`), with a path fix in `26cf9f8`.

Shipped as macOS 5.0.2 build 389. App Store copy in `a3a4575`.

## Active Constraints

- **The Xcode Cloud workflow is pinned to Xcode 26.6 (17F113) and must not go back to "Latest
  Release".** Twelve sites sit behind `#if compiler(>=6.4)`. Measured 2026-08-28: Xcode 26.6 ships
  Swift 6.3.3 so PCC compiles **out**; Xcode 27 ships Swift 6.4 so it compiles **in**, contradicting
  the App Store description, the README and the in-app copy. Xcode 27 is at beta 6, so "Latest
  Release" becomes it silently. `ci_scripts/ci_post_xcodebuild.sh` is the backstop proving the pin
  still holds — verified against a real Xcode 27 binary where it found 18 PCC symbols and exited 1.
- **`app_store` in `Docs/SHIPPED_VERSION.json` stays at `5.0`** while iOS lags. macOS is 5.0.2.
  Per-platform truth lives in `app_store_by_platform`; understating is the safe direction and is why
  that file exists.
- **Put 5.1 entries under `## 5.1`, not `## [Unreleased]`.** `ci_post_clone.sh` stamps
  `MARKETING_VERSION` from the first numbered heading and refuses to build when `[Unreleased]` holds
  entries above an uncut heading.
- **Paths in `ci_scripts/` must resolve from `$0`, not the working directory.** See Blockers.
- **No `xcodebuild test` runs in CI any more.** The Xcode Cloud TestFlight entries are post-actions,
  not test actions, and Actions is gone. Tests only run locally.

## Working Set

Nothing uncommitted. Files to open if continuing:

| File | Why |
|---|---|
| `ci_scripts/ci_post_clone.sh` | Version stamp, capability guard, and the AFM canary whose `\|\| true` hides its own failure |
| `ci_scripts/ci_post_xcodebuild.sh` | The three release gates; the PCC one is load-bearing |
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Holds all three filed defects |
| `Docs/reference/LINKEDIN_POSTS.md` | Gitignored. Final v5.0 draft ready to post, plus all six published posts archived |

## Verification

Commands run this session, with observed output:

- `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator'` on **Xcode
  26.6** → `BUILD SUCCEEDED`, 0 errors
- `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` on **26.6** →
  `BUILD SUCCEEDED`, 0 errors
- `xcodebuild build -configuration Release -destination 'platform=macOS'` on **26.6** →
  `BUILD SUCCEEDED`, 0 errors
- `xcodebuild test` (iOS 27 simulator) → `355 tests, 3 skipped, 0 failures`
- Xcode Cloud run **427** → SUCCEEDED, both Archive actions
- On device: a 43,576-line macOS capture contains **zero** `Suppressing invocation` lines, documents
  imported, 12 iCloud libraries synced; the owner confirmed import works

**Caveat on figures recorded earlier in this session:** the test run and several builds were made
with **Xcode 27 beta**, not the 26.6 that ships. They were re-run on 26.6 and passed, but any number
recorded before that re-run described a toolchain this project does not release with.

**Not verified:** Library Settings layout. Layout is exactly what a build and a test suite cannot
confirm.

## Blockers / Unknowns

None blocking. Three defects filed in Notion:

1. **[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)**
   — **now `v5.1`**, promoted 2026-08-28. Corrupts user data and already has: 599 conflict copies,
   136 unreadable zero-block files, 17 days of dead sync, and real chat history and vector indexes
   destroyed when the container was cleaned. `coordinatedMergeData` covers 4 paths, which had 0
   conflict copies; the 6 uncoordinated families had all 599.
2. **[420 workspace reloads per import](https://app.notion.com/p/3ca49a74d54f81a6b8c1e4827a6585fa)**
   — `Future Backlog`. Quality, not data loss.
3. **[17 views still use NavigationView](https://app.notion.com/p/3ca49a74d54f81eb867cf24a119af0c1)**
   — `Future Backlog`.

**Worth checking, unresolved:** `ci_post_clone.sh` runs
`sh ../scripts/probe_afm_advanced_canary.sh || true`. The capability guard added on the line below it
used the same CWD-relative style and failed on Xcode Cloud with exit 2 — python3's "cannot open
file" — breaking build 426. The guard now resolves from `$0` and build 427 passed, but the canary
still uses the old style **and** swallows its own failure, so it may not have run on Xcode Cloud for
some time without saying so. Verify by making it print and dropping the `|| true` for one run.

**Unexplained, did not recur:** build 424 failed with actor-isolation errors on
`HybridSearchService.stableTieBreakKey`, `analyse` and `overridesLock`, in the **macOS archive only**
— iOS archived fine in the same run. It does not reproduce locally in any combination tried (Xcode
26.6 and 27, Debug and Release, iOS and macOS), and build 427 archived both platforms cleanly. If it
returns, pull the Xcode Cloud build log rather than guessing at a fix.

## Exact Next Action

None. Both objectives are complete and verified, and there is no active objective.

Ask the user what to pick up, or take the `v5.1` roadmap row above: it is the only open row that
loses user data, and it is now scoped to the open release.

If 5.1 work starts, write the first entry under `## 5.1` in `CHANGELOG.md` — not `[Unreleased]` —
and leave `app_store` at `5.0` in `Docs/SHIPPED_VERSION.json` until iOS ships past it.
