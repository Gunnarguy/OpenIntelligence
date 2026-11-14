# Current State

Updated: 2026-11-14 afternoon PT
Branch/worktree: `main`, primary checkout
Last verified commit: e71874e6

## Objective

**Ship 5.8.** The owner does one device pass on the final build (the checklist page
https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT: 5 iPhone steps, 7 Mac steps, 13 added actions), says "done", and then
gives the word to push the Xcode Cloud build and submit (tick "Reset rating when this version is released",
`Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15). Every commit carries `[ci skip]`; nothing is pushed.

## The bar the owner agreed to discuss (2026-11-14), not yet confirmed by him

1 no mode scores below 5.7; 2 unit suite green; 3 nothing found loses data, breaks an advertised feature or blocks the
build. Rows still open after his pass that do not meet 3 move to the next release with their closing condition.

## Status

| What | Result |
|---|---|
| 20-case answer test by rule, final build df67ec96 | Standard 17, Deep Think 17, Maximum 17 of 20 (5.7: 10, 12, 10). `BenchmarkRuns/2026-11-14-1112-answer-modes`, LEDGER entry written. The nine misses are not read one by one |
| Unit suite | 1,751 run overnight with one failure fixed (145187be); not rerun since. `PlanBenefitsTests` 5 of 5 on 4c96aa37 |
| Plans screen | "Free, Pro and Lifetime" table of all five paid limits (4c96aa37), tests pass, **never seen rendered** |
| Release text | audited against all 288 commits since v5.7.0 by an Antigravity job; gaps fixed in e71874e6. App Store Connect not pushed |
| Mac | build of e71874e6 in Applications |
| iPhone | **still on the 11:12 build (df67ec96)**: `devicectl` install fails with CoreDeviceError 4016, phone unreachable. The built app is at `/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app` |
| Five Simulator checks | not run. The simulator control tool was refused (access prompt unanswered); write them as UI tests or wait for access |
| Roadmap | v5.8: about 100 In Progress |

## The five Simulator checks (each closes one row)

1 row 40049a74...e0bd: after a relaunch a citation past [S12] opens its passage and Copy lists it. 2 row 3c049a74: a
library with no vectors shows the rebuild as vetoed and keeps its banner. 3 row 40649a74: a Standard answer with no
passages shows No Sources and is not Source-Locked. 4 row 40049a74...814e: "Summarize my lease" uses only the lease.
5 row 40049a74...b094: the Glossary's Private Cloud Compute entry and the metrics bar note read correctly.

## Standing approvals (owner, 2026-11-14 about 00:05)

Install builds on both devices; open the Mac app in the background when a check or repair needs it; edit
hard-boundary files when a test proves a defect there; close and move roadmap rows with evidence. Not given: pushing,
submitting, deleting his data.

## Active Constraints

- Commits `[ci skip]`, no attribution, never `git add .`, never stage `scripts/run_quality_matrix.py`.
- One Simulator benchmark and one xcodebuild at a time. Never the whole macOS unit suite.
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical.
- iCloud Sync stays off the plans screen until roadmap row 3ca49a74d54f8103b69be921f0335171 closes.

## Known and not fixed

- "Getting search ready" runs 25 to 50 s after every install (Core ML compiles again).
- Chat's passage chip sums documents' recorded counts (8,574) and not the store's (8,225).
- A tip can point at the passage chip after its anchor scrolls away.
- Image tables in PDFs. Tapping a document in Spotlight asked for a question in the Simulator (his phone step 3 decides).
- `.claude/skills/device-pass/SKILL.md` does not yet list the 13 added actions that the checklist page has.

## Exact Next Action

When the owner says the iPhone is unlocked and on the Mac's network, run
`xcrun devicectl device install app --device B1483F12-4FFD-5534-BA30-29FF48070549 /private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app`
(rebuild first if HEAD has moved past e71874e6 in app source). Then run the five Simulator checks above and close the
rows that pass.
