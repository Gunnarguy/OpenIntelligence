# Current State

Updated: 2026-11-16
Branch/worktree: `main`, primary checkout
Last verified commit: 641c7aa9

## Objective

**Ship 5.8, now planned for 2026-11-15.** The owner runs his device pass on the final build (checklist page
https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT, the same steps in `.claude/skills/device-pass/SKILL.md`), says
"done", the agent closes rows from the logs, and then at his word the agent pushes the Xcode Cloud build and the store
text and he submits with "Reset rating when this version is released" ticked
(`Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15). Every commit carries `[ci skip]`; nothing is pushed.

The bar discussed with him on 2026-11-14 (not formally confirmed): no mode below 5.7; unit suite green; nothing found
loses data, breaks an advertised feature or blocks the build. Open rows that fail none of those move to the next
release with their closing condition written on them.

## UI work on 2026-11-15 and 16 (all run on the org API credit through `~/.agents/bin/ccp`, briefs and logs in the session scratchpad)

| Commit | What | Cost |
|---|---|---|
| b33ce4c6 | Settings list rows tightened (he said "looks the exact same") | $2.06 |
| 77309c88 | One type scale and card language for Settings and every Database section (spec on `DSTypography` in `Theme.swift`); lit panels as heroes; graphite icon tiles | $20.86 |
| 7b2da34e | Plans one tap from Settings, plans screen cut to usage panel, three cards, the table, quiet links | $3.27 |
| (no commit) | Read-only reviews of every Settings page and of published research on premium feel: `audit-run.log`, `premium-run.log` | $4.88 |
| adf95abb | Ten fixes he chose: Developer row Debug-only, About facts, panel and PCC page agree, rating copy, panel text at Apple's minimum, Database empty state, privacy line up, success haptic, Annual first, Intelligence Mode titles wrap | $7.17 over two runs (the first stopped while he played a game) |

Overnight 2026-11-16, four org-credit jobs in sequence (`night-*.md` briefs and `night-*.log` reports in the session
scratchpad, about $68 in all):

| Job | Commits | What |
|---|---|---|
| A | b7caf016, 9e4dc8c5 | Chat-context follow-ups to e5b26f86: every refusal kind stays out of later prompts; Siri's hand-off answer kept (edits `ChatMessage.swift` under the standing approval, test written first); a deleted library's memory file removed; Standard golden 34 of 35 unchanged. Notion row 41a49a74d54f8104a826d25ee6e6cc8b |
| B | 614ae4fa, 7c8218a3 | The type and card spec through Documents, Library Settings (12 screens to 6, developer rows behind Technical Details), sheets, Atlas, Chat chrome (bubbles untouched); no text under 11 pt there |
| C | fa81bf58 | Settings reorganised: General (Appearance plus Notifications), Model & Privacy (with the answer-route picker), Advanced as cards, one technical switch (old Plain English value not carried over, on purpose), no nested cards, Siri & Shortcuts one card, About trimmed |
| D | 746085c2 | Database sections each say what they are for; Maintenance opens on index health and recommends a repair only when a check finds a reason; Optimize renamed Reclaim Unused Space; Search tips corrected |

Screenshots: `/private/tmp/oi-premium-after/`, `/private/tmp/oi-reorg-after/`, `/private/tmp/oi-database-after/`. All seen only in
the iOS 27 Simulator. Open: the colour and icon pickers (job B skipped them); the repeated plan-card bullets (asked, no answer).

## Status

| What | Result |
|---|---|
| 20-case answer test by rule, build df67ec96 | 17, 17, 17 of 20; like for like (17 cases whose test scoping did not change) 15, 14, 14 against 5.7's 9, 11, 9. Stated in the splash, Version History and both store notes. `BenchmarkRuns/2026-11-14-1112-answer-modes`, LEDGER entry written |
| Table questions | Standard 47/53, Deep Think 46/53, Maximum 25/30 (8 before Maximum read source passages) |
| Unit suite | 1,751 overnight on 2026-11-14 with one failure fixed; since then only single classes run, all green |
| Five Simulator checks | done (`FiveChecksSimulatorTests`, `FiveChecksUITests`); four rows closed in Notion; the lease row (40049a74d54f814eadbace9c62d87ef9) is a line on the owner's checklist |
| Release text | audited against every commit since v5.7.0 by an Antigravity job (288 then, 307 now); gaps fixed. Store text not pushed |
| Devices | both run 641c7aa9 (installed 2026-11-16 about 10:00) |
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
- 42 main-thread stalls on the Chat screen during rebuilds (median 301 ms, worst 1,658 ms). Likely cause found 2026-11-16
  (641c7aa9): approachable concurrency ran the sync service's `nonisolated async` work on the main thread; the same
  thing got build 150 killed in the background (0x8BADF00D). Now `@concurrent`, test-verified; not yet seen on the phone. Next: `bash scripts/profile_phone.sh` (Time Profiler, 90 s)
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

Confirm both devices run adf95abb or later (rebuild with the commands above if not); he then runs his device pass. When he
says "done", pull both logs with `phone_evidence.py` since the install time, close the rows they prove, and read
`index.modelCheck` for the first cross-device similarity. Then, at his word only, push and submit.
