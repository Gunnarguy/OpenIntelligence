# Current State

Updated: 2026-10-18, 20:25 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; 5.6 has been live on iPhone,
iPad and Mac since 2026-10-08; every commit since then is pushed with `[ci skip]`)
Branch/worktree: `main`, primary checkout
Last verified commit: f551871

Earlier detail is in git: `git show b19b9b5:Docs/ai/STATE.md` (the afternoon of 2026-10-18) and the copies it names;
the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7 closes every open roadmap row and carries the owner's UI cleanup.** On 2026-10-18 he chose "Everything into 5.7"
over shipping 5.7 for its Nov 9 featuring window with the backlog in 5.8; that answer was his PROCEED: IMPLEMENT for
the plan. The cleanup is his list of 2026-08-10: every tab brought to one standard, Settings aligned with more control,
a modern picker for model and mode in chat (his choice), faster tab navigation, onboarding pointers in his words saying
the app runs on the device's hardware. The decisions are in auto memory `everything-into-5-7.md`.

## Status (2026-10-18, evening)

| What | Where it stands |
|---|---|
| Today's commits | `b70eea1` an answer's heading stays out of Fact Check; `9e5a999` two Developer switches stop reverting, Deep Think's second research call applies the first call's checks; `798b3ec` the heading rule after a refuting review that ran four times over the fixes (a heading counts only when it reads as a title, a bold title with a figure only when the answer gives it again, lead-ins always; Gate B and Fact Check both use the answer's sentences when the model lists only its heading; the source-only check keeps statements and declines on title-only claim lists; `HybridSearchService`'s sort helpers are `nonisolated`). `f551871` Settings: Intelligence Mode in plain words, its technique list only what the mode uses, Siri's count, the routing menu's "(not available)" (two refuting reviews found four untrue lines in the first wording, all fixed). All pushed. |
| Roadmap | 40 Future Backlog rows moved to v5.7; 11 closed as decided. New row "Fact Check counted an answer's own heading as a claim..." (`3fe49a74d54f8149bfb1d2aee1285abc`) closed Completed the same evening on the demo-copy check (Shipped On empty: 5.7 is unreleased). About 204 rows open. New row "Settings speaks the pipeline's jargon to everyone..." (`3fe49a74d54f81ce84a1f0b59e2e1ec7`), In Progress, tracks the Settings cleanup page by page. |
| Triage of all 214 open rows | `~/.agents/data/openintelligence-5.7-closeout/triage-2026-10-18/*.jsonl`: per row state, check (simulator / unit-test / device / mac / benchmark / owner), evidence, what is missing, size. 147 built and waiting for a check (75 Simulator, 44 device). |
| UI audit | 41 screenshots and three contact sheets in `~/.agents/data/openintelligence-5.7-closeout/ui-audit-2026-10-18/`. Findings are under Blockers. |
| App Store media (not uploaded) | `~/Movies/App demos/OpenIntelligence/App Store/5.7 (2026-10-18)/`: `OpenIntelligence 5.7 App Store preview (iPhone 6.9) v2.mov` (19.5 s, 886x1920, 30 fps, silent stereo AAC; filmed 18:38 from `798b3ec`'s demo copy, Fact Check "1 Verified", no gap; plan and contact sheet beside it; sent to him) replaces the first cut, which showed the old gap; and the 21:9 header loop. Nothing goes to App Store Connect without his word. |
| His iPhone | Development build of 9c0d1dd's app code, installed 2026-10-17 23:09. |
| Waiting on him | Picker style (A tidier chips, B one combined chip, C a mode bar; mockups shown 2026-10-18); localization languages. |

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Protected files he named on 2026-10-18 for this work: `project.pbxproj`, `WorkspaceSyncService.swift`,
  `BNNSVectorDatabase.swift`, `FoundationModelRoutePolicy.swift`, `FoundationModelSessionFactory.swift`, with his
  condition "Must be done flawlessly, without fucking anything up, and only if they're genuine full and well rounded
  improvements." Every change gets a refuting review (`reviewer` agent) before commit; every review today found real
  defects, and the heading rule needed four rounds.
- App Store Connect writes and public pages only at his word; App Store Connect through `zsh -ic`.
- Never delete a doc, a benchmark run or a Notion row; no co-author lines; commit by name; leave `.agents/skills/` and
  `.codex/hooks*` alone. Edit Swift by script (the post-edit formatter rewraps whole files).
- One `xcodebuild` at a time; never edit a script while it runs; end only your own build by its process id. "The test
  runner hung before establishing connection" is a simulator hiccup: shut the simulator down and run again.
- **Disk.** The Mac's disk reached 0 bytes free on 2026-10-18 (swap 12 to 15 GB, Messages' `imagent` 4.5 GB). His
  Samsung T7 (`/Volumes/T7`, APFS) now holds build scratch: `~/.agents/bin/scratch_root.sh` prints
  `/Volumes/T7/Scratch.noindex` when it is plugged in and `/private/tmp` otherwise, and the scratchpad's build scripts
  read it as `$OI_SCRATCH`. Nothing on the T7 may be the only copy of anything (his rule: unplugging must never break
  anything). Machine facts, the iCloud exclusions and the T7 convention are in `~/.agents/MACHINE-MAP.md` (2026-10-18).
- The Simulator runs Apple's model through a demo copy: recipe in auto memory `simulator-demo-copy-pipeline.md`.
  Answers vary run to run; film or check until a clean take and read the tree in the log.

## Working Set

- Scratchpad `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad`:
  `build57.sh` (test build and test runs, simulator `3982899B-3D70-4C87-B957-D104ECDECB5F`), `smoke_guarded.sh` (the
  repository's smoke script from the build copy), `builddevice.sh`, `buildmac.sh`, `uitests.sh`, `demo_refresh.sh <udid>`
  (demo copy of HEAD: archive, PostDesk's patch from `pd/oi/`, sync, Release build, install), `oi57h-build.sh`,
  `pvrec.sh` (film a scene; `OI_Q` sets the question), `pvtry.sh`, `guard.inc` (stops only its own build on low memory
  or disk; `GUARD_DISK_MB` sets the floor).
- Hosted unit tests run from a copy of the products on the Mac's disk: `build57.sh test-without-building` rsyncs
  `$OI_SCRATCH/oi-build/Build/Products` to `/private/tmp/oi-products` and runs `-xctestrun` there, because on the T7
  the runner hung before connecting four runs in a row (2026-10-18).
- The demo simulator's settings live in the app's container plist (`xcrun simctl get_app_container <udid>
  Gunndamental.OpenIntelligence data`/Library/Preferences/...); `defaults write <bundle id>` writes a domain the app
  never reads.
- Build folders, on the T7 since 18:30: `$OI_SCRATCH/oi-src` and `oi-build` (tests), `oi57-ios-src` and `oi57-ios-dd`
  (demo copy), `demodriver-pv-dd` (the robot). A moved DerivedData does not build (its `SourcePackages` keeps the old
  absolute path: "artifact bundle info.json not found at '/tmp/oi57-ios-dd/...'"), so the moved `oi-build` and
  `oi57-ios-dd` were deleted and both rebuild from scratch on the T7.
- `/private/tmp/demodriver-pv` (the robot's scenes), `/private/tmp/democut2-pv` (preview editor),
  `/private/tmp/stage3d-pv`; simulator `OpenIntelligence 5.7 preview` `230C41D7-D64D-426E-B9E2-B0FF66BAF2ED` (five sample
  PDFs in a Local Only library "Home", lifetime tier, no keys).

## Verification (2026-10-18, output read)

- `f551871`'s tree: TEST BUILD SUCCEEDED; `Executed 1204 tests, with 6 tests skipped and 0 failures` (full suite, from
  the products copy); the smoke script succeeded. `798b3ec`'s tree: the same full suite, `Executed 146 tests, with 0
  failures` in the Fact Check and retrieval classes, and the demo-copy preview take reading "1 Verified".
- `python3 scripts/verify_doc_claims.py` -> all claims match. `python3 scripts/secret_scan.py` -> clean.
- Screenshots of every Settings page: before `~/.agents/data/openintelligence-5.7-closeout/ui-audit-2026-10-18`, after
  `ui-audit-2026-10-18-after-2`, Technical Details on `ui-audit-2026-10-18-after-2-technical-deepthink`.
- Not run: any of today's changes on a device.

## Blockers / Unknowns

- **Onboarding's model step:** the `$selectedModel` sink in `SettingsStore.setupPipelines` has no `.dropFirst()`, so
  every launch marks the model as chosen by the person and ticks onboarding's `hasAcknowledgedModelSelection`, the only
  thing that ever ticks it. Retire the step (Apple's models only, decided 2026-10-06) in the onboarding cleanup, then add
  `.dropFirst()`.
- **UI cleanup, from the audit:** Intelligence Mode's feature wall and badges (`SettingsView.modeBadges`: "98% target" is
  real, the Maximum loop stops at 0.98 confidence in `AgenticConfig.unlimited`; reword, don't delete), Apple
  Intelligence page jargon ("ADM 3"), Device & Performance internals, the Database tab (SQLite FTS5, O(log n)), the
  Atlas ("PCA projection", cluster names), the routing menu's "PCC (Requires Entitlement)"
  (`ModelStatusIndicator.swift:30`), Siri & Shortcuts' hardcoded "10 of 10 Registered" (`SettingsView.swift`,
  `siriIntegrationCard`; count it from `RAGAppShortcutsProvider`), one title style per level. Plain by default behind
  the Technical Details switch, which today hides almost nothing in Settings.
- Fact Check heading rule, known limits (CHANGELOG 5.7 entry): figures compared by value, number words not read, Title
  Case statements and lead-ins read as headings.
- 44 device rows need his iPhone; Mac rows can run on this Mac.

## Exact Next Action

Next Settings page, by the same method (claims checked against code, plain by default, Technical Details keeps the
rest, refuting review, screenshots with the robot's `OpenIntelligenceScenes/testAuditTour` through
`pvaudit.py`): the Apple Intelligence page's feature subtitles (`appleIntelligenceFeaturesCard` in
`OpenIntelligence/Features/Settings/SettingsView.swift`; every "Always On" row has code behind it, spot-checked
2026-10-18: Screen Awareness is `.appEntityIdentifier` and `.userActivity` in `ViewAnnotations.swift`, Gazetteer is
`GazetteerService`, Translation is `TranslationService`), then Device & Performance (`contextWindowCard`,
`hardwareEnvelopeSection`, `siliconNativeRAGSection` behind Technical Details). The chat picker (A, B or C) waits for
his choice.
