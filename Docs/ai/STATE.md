# Current State

Updated: 2026-08-26
Branch/worktree: main
Last verified commit: f9a99cd

## Objective

v5.0 is shipped or in review on both platforms. There is no active engineering
objective. The next one should come from the Notion roadmap, not from what anyone
last noticed.

## Status

- **macOS 5.0, build 379: LIVE on the App Store**, approved 2026-08-26. Archived from `35d59a2`,
  so it does not contain the 17 changelog entries that landed after it.
- **iOS 5.0, build 386: submitted, in review.** Archived from `2d86273`; contains everything.
- **macOS 5.0.1, build 387: submitted, in review.** Archived from `66c4f7e`.
- **iOS 5.0.1, build 387: uploaded, unused.** A by-product of the shared version stamp. Harmless.
- All three public websites corrected and pushed (see Completed).

## Completed this session

- `66c4f7e` — 5.0.1 cut. ASC closed the 5.0 train on macOS the moment 379 went live and refused
  build 386 with `90186` / `90062`.
- `1c5e31c` — README said releases come from Xcode Cloud (untrue since the compute cap) and cited
  "eleven" PCC gates when there are twelve. RUNBOOK gained the train-closure lesson. ROADMAP.md
  header reconciled from v4.9.
- `d2382e2` — `Docs/SHIPPED_VERSION.json`: platforms diverged. `app_store` deliberately held at
  `4.9` because iOS 5.0 is not approved; raising it would advertise to iOS visitors a version they
  cannot install, which is the exact failure the file exists to prevent.
- `f9a99cd` — `Docs/SHIPPED_CAPABILITIES.json` + `scripts/verify_capabilities.py`, wired into
  `ci.yml`. Both failure paths tested.
- **Notion**: the one open v5.0 row moved to `Future Backlog` (not closed; it is not closeable and
  says why). Ten rows created — 8 Completed for the 5.0.1 work, 1 In Progress (Documents tab),
  1 To Do (OCR spine banner). The stale "App Store build pins Xcode 26.5" row corrected in place.
- **Three websites**, all pushed: 19 places described Private Cloud Compute as a live capability.
  Fascinaiting's release notes claimed "native PCC shipped in v4.6", which is false. Corrected on
  `Gunzino` (6), `Fascinaiting` (9), `Gunnarguy-Portfolio` (4). Every `data-oi-version` anchor left
  intact so the version workflows keep working.

## Active Constraints

- **One CHANGELOG heading stamps both platforms.** The `MARKETING_VERSION[sdk=macosx*]` override
  was removed 2026-07-30, so one commit cannot put the platforms on different marketing versions.
- **A shipped version closes its train on that platform**, and nothing local warns you.
  `ci_post_clone.sh`'s guard infers "already shipped" from whether `[Unreleased]` holds entries and
  cannot ask App Store Connect.
- **PCC must be written in the future tense everywhere.** Enforced by `SHIPPED_CAPABILITIES.json`.
- **`xcodebuild test` hangs on this machine** in two distinct ways; see `Docs/ai/RUNBOOK.md` and
  the `running-tests` memory. Run long tests under `nohup` so a session restart cannot kill them.

## Working Set

- `Docs/SHIPPED_VERSION.json` — the one file to edit when iOS 5.0 clears review.
- `Docs/SHIPPED_CAPABILITIES.json`, `scripts/verify_capabilities.py` — the new guard.
- `OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift` — carries the unread
  `[LibrarySwitch]` instrumentation.
- App Store copy, session scratchpad, not in the repo: `asc_whatsnew_universal.txt` (3,995 chars),
  `asc_macos_whatsnew.txt` (2,962), `asc_description_v2.txt` (3,012), `asc_ios_whatsnew.txt`.

## Verification

- `xcodebuild test` -> **348 tests, 3 skipped, 0 failures** at the 5.0.1 content.
- `python3 scripts/verify_capabilities.py` -> 10/10 anchors present, 1.3s. Both failure modes
  exercised deliberately: a renamed anchor reports MISSING, a count below its floor reports the
  shortfall.
- iOS 386/387 and macOS 387 -> released OS stamp, PCC symbols 0 against a `SystemLanguageModel`
  control of 29, `UPLOAD SUCCEEDED`.
- macOS 386 -> **rejected**, `90186` train closed. This is the evidence behind the 5.0.1 cut.

## Blockers / Unknowns

1. **The library-switch cost has never been measured.** The reported complaint was "SUPER slow
   going library to library"; what shipped fixes *tab appear*, which is what the capture showed.
   `.task` fires on tab entry only. Instrumentation is in builds 386/387. Verify by switching
   libraries on device and reading `[LibrarySwitch] state ... settled ...`. A large `settled` puts
   the cost in SwiftUI body evaluation, and `withAnimation` wrapping `containerService.setActive`
   in `ContainerPicker.swift` is the first thing to examine.
2. **Retrieval is nondeterministic** — two runs of one build return different evidence for the same
   question (Notion, Retrieval, High). This **gates the embedding-benchmark arc**: no A/B is
   trustworthy until it is fixed, so doing the benchmark first wastes the work.
3. **`Docs/ROADMAP.md` body still predates v5.0.** Header reconciled only. Notion is authoritative.

## Exact Next Action

None outstanding for an agent. When iOS 5.0 clears review, set `app_store` to `"5.0"` in
`Docs/SHIPPED_VERSION.json`; all three websites follow within a day on their own crons. If macOS
5.0.1 is approved first, leave it alone — iOS is the constraint.

For the next work session, ask the owner or take a roadmap row from Notion. If the embedding arc is
chosen, fix Blocker 2 first.
