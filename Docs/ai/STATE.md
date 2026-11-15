# Current State

Updated: 2026-11-15 (owner's clock), written in the evening session of 2026-11-14 PT
Branch/worktree: `main`, primary checkout
Last verified commit: b33ce4c6

## Objective

**Ship 5.8, now planned for 2026-11-15.** The owner runs his device pass on the final build (checklist page
https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT, the same steps in `.claude/skills/device-pass/SKILL.md`), says
"done", the agent closes rows from the logs, and then at his word the agent pushes the Xcode Cloud build and the store
text and he submits with "Reset rating when this version is released" ticked
(`Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15). Every commit carries `[ci skip]`; nothing is pushed.

The bar discussed with him on 2026-11-14 (not formally confirmed): no mode below 5.7; unit suite green; nothing found
loses data, breaks an advertised feature or blocks the build. Open rows that fail none of those move to the next
release with their closing condition written on them.

## Settings list redesign (b33ce4c6, done 2026-11-15)

Run at the owner's request as one `claude -p` turn billed to the organization's API credit (`~/.agents/bin/ccp`,
about $2.06, 26 minutes; brief `settings-brief.md` and log `settings-run.log` in the session scratchpad). One accent
colour for every icon, system-sized rows, small headers, a one-line status under the app name. Seen in the iOS 27
Simulator at Large and at the largest accessibility size (`/private/tmp/oi-settings-after/`); the Intelligence group
went from about 835 to 670 pixels tall. Not seen: the Mac's list, dark mode, the support card at the bottom.

## Status

| What | Result |
|---|---|
| 20-case answer test by rule, build df67ec96 | 17, 17, 17 of 20; like for like (17 cases whose test scoping did not change) 15, 14, 14 against 5.7's 9, 11, 9. Stated in the splash, Version History and both store notes. `BenchmarkRuns/2026-11-14-1112-answer-modes`, LEDGER entry written |
| Table questions | Standard 47/53, Deep Think 46/53, Maximum 25/30 (8 before Maximum read source passages) |
| Unit suite | 1,751 overnight on 2026-11-14 with one failure fixed; since then only single classes run, all green |
| Five Simulator checks | done (`FiveChecksSimulatorTests`, `FiveChecksUITests`); four rows closed in Notion; the lease row (40049a74d54f814eadbace9c62d87ef9) is a line on the owner's checklist |
| Release text | audited against every commit since v5.7.0 by an Antigravity job (288 then, 307 now); gaps fixed. Store text not pushed |
| Devices | both being installed with b33ce4c6 when this was written (see the session's last message) |
| Roadmap | v5.8: about 96 In Progress; most close from the device pass |

## Done on 2026-11-14 afternoon and evening (all committed)

- Plans screen: "Free, Pro and Lifetime" table of the five paid limits (Maximum, documents, libraries, conversations per
  library, watched folders); the conversation limit is now on the cards, the Terms and the store description. iCloud
  Sync is paid and deliberately not listed until row 3ca49a74d54f8103b69be921f0335171 closes on his two-device step
  (`testICloudSyncWaitsForTheTwoDeviceCheck`).
- Rating request: made only while the scene is active, held otherwise (`askForRatingWhenInFront`); rules unchanged
  (first verified or third finished answer, once per version, 14 days apart).
- Watch a Folder: a one-line row on the Documents page (`WatchedFolderRow`, folder-and-eye glyph from two system
  symbols), its own sheet with a Mac layout.
- `SettingsStatusPanel` (the dark lit panel, up to four blocks) on Plan & Usage, Private Cloud Compute, Libraries &
  iCloud, How This Works, Siri & Shortcuts; Siri phrase rows lead with what they do.
- Mac: grouped forms so Library Settings scrolls (`macGroupedForm`); View Plans opens from a pushed Settings page; no
  focus rings (`macWithoutFocusRings`, his choice); new windows open at 70% by 75% of the screen
  (`defaultWindowPlacement`); Settings pages capped at 620 points wide (`detailColumnWidth`); the menu bar item shows
  the app icon and has a library picker (`MenuBarAsk`).
- Sync: a device skips the one-time model rebuild when the vectors iCloud brought are already the live model's
  (`StoredVectorModelCheck`, `RAGService.storedVectorsAlreadyMatchLiveModel`, journal `index.modelCheck`). Simulator:
  own vectors 1.000, foreign 0.082, threshold 0.95. The cross-device figure is not yet seen.
- Glossary's Private Cloud Compute entry states that working steps go there too when it is picked in the model picker.
- Other repos (not 5.8): OpenCone `fe9d398` and OpenResponses `a6c5507` have Apple's rating request, committed
  locally, not pushed or versioned.

## Seen and not seen

Seen on his Mac through the app's accessibility interface: Library Settings scrolling, the Watched Folder sheet, Model
Parameters, Semantic Search, Plan & Usage on Lifetime (46 documents, 8 of 20 libraries), the plans screen opening,
Device & Performance in the narrow column, the app icon in the menu bar. Not seen: focus rings gone, the 70% first
window (his Mac remembers its size), the menu bar picker panel, about eleven Mac sheets with no size of their own (list
in `CHANGELOG.md`, "Library Settings scrolls on a Mac"), paid-plan panels other than Lifetime.

## Standing approvals (owner, 2026-11-14 about 00:05)

Install builds on both devices; open the Mac app in the background; edit hard-boundary files when a test proves a
defect; close and move roadmap rows with evidence. Computer-use access to OpenIntelligence on the Mac was granted on
2026-11-14. Not given: pushing, submitting, deleting his data.

## Active Constraints

- Commits `[ci skip]`, no attribution, never `git add .`, never stage `scripts/run_quality_matrix.py`.
- One xcodebuild and one booted simulator at a time; the disk sat at 8 to 10 GB free on 2026-11-14 (floor 9 GB for a
  build; only this session's own finished eval builds were removed).
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical.
- The phone trace holds his file names: grep it, never print it whole or commit it.

## Known and not fixed

- Search setup after an install took 55 to 99 s (embedding) and 87 to 131 s (reranker) on his iPhone at thermal
  state serious; the earlier "25 to 50 s" was too low.
- 42 main-thread stalls on the Chat screen during rebuilds (median 301 ms, worst 1,658 ms). Cause not found: they line
  up with sync log lines, but that code is `nonisolated`. Next: `bash scripts/profile_phone.sh` (Time Profiler, 90 s)
  while he rebuilds one library, then read the main thread's heaviest frames. Closes no row by itself.
- Chat's passage chip sums documents' recorded counts (8,574) against the store's (8,225); a tip can point at the
  passage chip after its anchor scrolls; image tables in PDFs; the Spotlight document tap (his phone step decides).

## Commands

```bash
rsync -a --delete --exclude .build --exclude .git --exclude .git.nosync --exclude BenchmarkRuns --exclude '.claude/worktrees' ./ /private/tmp/oi-src/
```

iPhone, from `/private/tmp/oi-src`: `xcodebuild build -project OpenIntelligence.xcodeproj -scheme OpenIntelligence
-configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/oi-build -jobs 2
MARKETING_VERSION=5.8`, then `xcrun devicectl device install app --device B1483F12-4FFD-5534-BA30-29FF48070549
/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app`. Mac: the same build with
`-destination 'platform=macOS' -derivedDataPath /private/tmp/oi58-mac-dd`; quit the app
(`osascript -e 'tell application id "Gunndamental.OpenIntelligence" to quit'`), replace
`/Applications/OpenIntelligence.app` with `ditto`, then `xattr -cr`. Screens: `ui.sh <name> testShotsOfEverySettingsPage`
in the session scratchpad (writes `/private/tmp/oi-checks-shots`). Logs: `python3 scripts/phone_evidence.py --since
<local time> --json`, and the same with `--mac`.

## Exact Next Action

Confirm the iPhone and the Mac run b33ce4c6 or later (rebuild with the commands above if not), then tell the owner the
build is ready for his pass. When he says "done", pull both logs with `phone_evidence.py` since the install time,
close the rows they prove, and read `index.modelCheck` for the first cross-device similarity.
