# Current State

Updated: 2026-11-14 about 00:15 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 581a37b6

## Objective

**Ship 5.8 on 2026-11-14.** The owner does one device pass (5 phone steps, 7 Mac steps, `.claude/skills/device-pass/SKILL.md`)
on the final build, says "done", and then gives the word to push the Xcode Cloud build and submit (tick "Reset rating
when this version is released", `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15). Every commit carries `[ci skip]`;
nothing is pushed.

## Running now

`bash BenchmarkRuns/2026-11-14-overnight/run.sh` (background, started about 00:10; `progress.log` there): 1 unit suite
on HEAD (`unit.log`, `unit.xcresult`), 2 the 20-case answer test in three modes on HEAD, 3 Deep Think and Standard with
`draftAbstainNeedsFailedClaim` off, 4 v5.7.0 in three modes, 5 `rule-scores.txt` (rule scores of every run's bundle).
It waits while a game runs. One Simulator at a time: three at once crashed two runs on 2026-11-13.

## Status

| What | Result |
|---|---|
| `answerFirst` (Deep Think) | measured, kept: 45 to 46 of 53, median 82 s to 68 s (`BenchmarkRuns/2026-11-13-answer-first`) |
| `maximumSourcePassages` (with `answerFirst`, Maximum) | measured, kept: 8 to 25 of 30, median 117 s to 79 s (`2026-11-13-maximum-passages`) |
| `draftAbstainNeedsFailedClaim` | not measured: the table questions never reach the check (source-only check skipped on all 32 answers); step 3 of the overnight run is its test. Keep unless right answers lose nothing and wrong ones keep their banner; else switch off before submission |
| Library 6 (owner's) | 8,225 passages on iPhone, Mac and iCloud after two wrong merge rules cut it to 4,292 and 6,843 on 2026-11-13; backup of the 16,554 original at `~/Library/Developer/OpenIntelligence-evidence/library6-backup-2026-11-13` |
| Builds on his devices | iPhone and Mac at b76dd50c (18:53); later commits are docs and ledger only |
| Roadmap | v5.8: about 105 In Progress; 44 are the agent's (tests, Simulator), the rest close from the device pass |

## Standing approvals (owner, 2026-11-14 about 00:05)

Install builds on both devices; open the Mac app in the background when a check or repair needs it (it syncs his real
library); edit hard-boundary files when a test proves a defect there; close and move roadmap rows with evidence. Not
given: pushing, submitting, deleting his data.

## Active Constraints

- Commits `[ci skip]`, no attribution, never `git add .`, never stage `scripts/run_quality_matrix.py`.
- Any rule that removes stored passages is replayed on a copy of real data before a device runs it (two were not).
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical.

## Known and not fixed

- "Getting search ready" runs 25 to 50 s after every install: Core ML compiles again; neither removing the app's own
  cache clearing nor keeping the models under the app group folder stopped it (`reranker.load`, owner's iPhone).
- Chat's passage chip sums documents' recorded counts (8,574) and not the store's (8,225).
- A tip can point at the passage chip after its anchor scrolls away.
- About 310 old passages can remain in a library rebuilt before b76dd50c, at places the new set lacks; Rebuild clears them.
- Tapping a document in Spotlight asked for a question in the Simulator (row 3ff49a74...595e); the owner's phone step 3 decides.

## Exact Next Action

When `BenchmarkRuns/2026-11-14-overnight/progress.log` says "done": read `unit.log`'s last "Executed" line and any
failures; read `rule-scores.txt`; decide `draftAbstainNeedsFailedClaim` from step 3 against step 2's Deep Think and
Standard; write the LEDGER entry for the folder and the 5.7 against 5.8 table by rule; close the agent's rows the
suite proves (the two triage tables are in the session of 2026-11-13; test names are in each row's note or the
`device-pass` skill); then build HEAD to both devices and tell the owner the pass is ready.
