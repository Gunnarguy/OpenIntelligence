# Current State

Updated: 2026-11-17 22:40
Branch/worktree: `main`, primary checkout
Last verified commit: 3da70f6c

## Objective

**Ship 5.8.** The owner runs his device pass (checklist page https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT, the
same steps in `.claude/skills/device-pass/SKILL.md`), says "done", the agent closes rows from the logs, and then at his
word only the agent starts the Xcode Cloud build and pushes the store text, and he submits. **No rating reset on 5.8**
(his decision 2026-11-17, reversing 2026-11-09; `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15 and auto memory
`oi-58-rating-reset.md`). Every commit carries `[ci skip]`; nothing since 6bafcf2a is pushed.

In flight beside it: the Deep Think final-step evidence measurement (below), at his request "Measure the bigger Deep
Think evidence budget".

## Status

| What | Result |
|---|---|
| 20-case answer test by rule, build df67ec96 | 17, 17, 17 of 20; like for like 15, 14, 14 against 5.7's 9, 11, 9. `BenchmarkRuns/2026-11-14-1112-answer-modes`, LEDGER entry written |
| Table questions | Standard 47/53, Deep Think 46/53, Maximum 25/30 |
| Unit suite | full iOS suite at 6bafcf2a: 1,799 run, 33 failed (30 were the simulator's free-plan quota); after `simctl erase` and fixes the failing classes 113 run, 0 failed. Since then only single classes run |
| Release text | audited against every commit since v5.7.0; store text not pushed. Today's commits are in `CHANGELOG.md` 5.8 |
| Roadmap | v5.8: about 96 rows In Progress; most close from the device pass |

## Completed on 2026-11-17 (committed with `[ci skip]`, not pushed)

| Commit | What |
|---|---|
| 47a8f675 | Model & Privacy in Intelligence Mode's language; every pushed Settings page redraws on a setting change (`SettingsLivePage`). Privacy policy names the new heading; `scripts/privacy_policy.py` NOT run, so Gunzino's copies lag |
| 9bd8c53a, 566241c3 | Device facts checked against Apple: model name from `SystemLanguageModel.variant`, every Apple silicon Mac named, no Neural Engine claims Apple doesn't make, eligibility copy quotes Apple, A20 and M6 GPU pool |
| 1231ab96 | Settings list regrouped: Intelligence, Libraries & Plan, This Device, App, Learn, Advanced |
| 6ff765fa | Mac chat route menu: the three routes are the menu's own items (`ModelStatusIndicator`, `.pickerStyle(.inline)`) |
| e361dcd1, 0e2a5bdc | An answer streams inside its grey bubble; iOS left-edge swipe opens Evidence Threads |
| d66706f3 | Chat header counts drawn like the pickers (`StatChip` in `ChatScreen.swift`), number only, grouped |
| 3fb31070 | `AppleFoundationLLMService.continueGeneration`: continuation room from the live window (`continuationTokenRoom`) instead of 1,600 characters; a `rateLimited` pause mid-answer resumes when the app is active again (`resumeAfterPause`), else the answer ends with a "stopped early" note (`RAGService+Generation.swift`); Mac Vision concurrency from performance cores and memory, GPU cache from chip generation and Metal's working set; skill `.claude/skills/scale-to-the-device` |
| 63ad336b | Compression estimate (`RAGService+QueryContext.swift`) reads the live window; unused 4,096 constant deleted |
| 2532a0c4, 3da70f6c | The iPhone's window history and the release inference, in the skill and auto memory |

## Facts established today

- The owner's iPhone 16 Pro Max runs AFM 3 Core. Its window read 4,096 on iOS 27.0.1 through 2026-11-16 17:08 and
  8,192 on iOS 27.2.1 from 2026-11-17 08:10 (overnight update, skipped 27.1 and 27.2) [measured: MetricKit
  `metric_reports.jsonl` osVersion, `pipeline_trace.log` "Context budget: base="]. Most likely 27.2 changed it
  [inferred: 27.1 was iPhone Duo only, 27.2.1 bug fixes only]; no Apple text names it.
- His M3 Pro Mac: AFM 3 Core Advanced, 8,192, no reasoning capability; GPU cache 53 MB after 3fb31070 (was 32) [measured].
- Fix 1 seen on the Mac: continuation room 3,113 tokens, a "summarize each" answer finished across two calls [measured].
- Full Disk Access works for the agent's shell, but `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels`
  is SIP `restricted` and unreadable even so; Apple's asset catalog returns 403.

## In flight: Deep Think final-step evidence (uncommitted)

Question: the final synthesis is capped at 3,200 evidence tokens (`SessionEvidencePlan.readingCeilingTokens`, applied in
`ChainSynthesisEvidence.evidenceTokenBudget`; from
a 2026-10-07 probe of the Mac's 20B model). With an 8,192 window the window alone would allow about 5,990. Decision rule,
set before running: **the window ships only if it gets at least as many answers right as the ceiling.**

- `OpenIntelligence/Services/RAG/Tuning/RetrievalAblation.swift`: new `case synthesisReadingCeiling` (off = the window decides).
- `OpenIntelligence/Services/Agentic/SessionEvidencePlan.swift`: `ChainSynthesisEvidence.evidenceTokenBudget` returns `max(0, free)` when that switch is off.
- `OpenIntelligenceTests/Services/RAG/Orchestration/EvidenceReachBenchmarkTests.swift`: window from `OI_EVIDENCE_WINDOW` (default 4,096, so old runs stay comparable).
- `BenchmarkRuns/2026-11-17-synthesis-ceiling/run.sh` (gitignored): stages and patches the tree to `/private/tmp/oi-eval-src`
  (`scripts/sim_model_copy.py`), builds into `/private/tmp/oi-eval-dd`, makes simulator "OI answer eval" (iPhone 17 Pro,
  iOS 27.0), runs arms `ceiling:a:` and `window:a:synthesisReadingCeiling` at window 8,192 on the 53 table questions
  (slice 0/3), scores with `scripts/evidence_reach.py answers`. It waits while a game runs (timers slow 14x).
- Running: smoke (2 questions) started 22:25 into `smoke/`; a chained job starts the full run into `full.out` only if the
  smoke scored both arms. Expected done about 01:00 to 02:00 on 2026-11-18.

## Not verified on a device

The iPhone has the 3fb31070-era Debug build installed at 2026-11-17 18:54, not launched (phone locked). Not seen: the
edge swipe, the paused-answer resume (needs an answer interrupted by leaving the app), the Mac one-click route menu, the
header chips on the phone, the 53 MB cache on any M4 or later. Which build `/Applications/OpenIntelligence.app` holds was
not recorded: rebuild both from HEAD before his pass.

## Standing approvals (owner, 2026-11-14)

Install builds on both devices; open the Mac app in the background; edit hard-boundary files when a test proves a
defect; close and move roadmap rows with evidence; computer-use on OpenIntelligence. Not given: pushing, Xcode Cloud,
submitting, deleting his data.

## Active Constraints

- Commits `[ci skip]`, no attribution lines, never `git add .`; never stage `scripts/run_quality_matrix.py` or
  `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` (another session's changes), nor the untracked `.agents/skills/` and `.codex/` files.
- One xcodebuild and one booted simulator at a time; never the whole macOS hosted suite (his real library).
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical.
- The phone trace, journal and Mac prefs hold his file names: grep them, never print them whole or commit them.
- Before any device-dependent constant, run the `scale-to-the-device` skill (read Apple's page first).

## Known and not fixed

- Search setup after an install took 55 to 99 s (embedding) and 87 to 131 s (reranker) on his iPhone at thermal state serious.
- Main-thread stalls on Chat during rebuilds (worst 1,658 ms); the `@concurrent` fix (641c7aa9) is not yet seen on the
  phone. Next: `bash scripts/profile_phone.sh` while he rebuilds one library.
- The app never says the phone's storage is full (Future Backlog 41b49a74d54f81eebbc3fbbee08a878d).
- Open UI asks with no answer: the Standard picker on the Mac lacks its capsule; the colour and icon pickers; repeated plan-card bullets.
- `AtlasLabelingTests` adverb tests depend on the simulator having English word classes (skip on a fresh one).

## Commands

```bash
rsync -a --delete --exclude .build --exclude .git --exclude .git.nosync --exclude BenchmarkRuns --exclude '.claude/worktrees' ./ /private/tmp/oi-src/
```

iPhone, from `/private/tmp/oi-src`: `xcodebuild build -project OpenIntelligence.xcodeproj -scheme OpenIntelligence
-configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/oi-build -jobs 2
MARKETING_VERSION=5.8`, then `xcrun devicectl device install app --device B1483F12-4FFD-5534-BA30-29FF48070549
/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app`. Mac: the same build with
`-destination 'platform=macOS' -derivedDataPath /private/tmp/oi58-mac-dd`; quit the app with `gtimeout 20 osascript -e
'tell application id "Gunndamental.OpenIntelligence" to quit'` (pkill fallback), replace
`/Applications/OpenIntelligence.app` with `ditto`, then `xattr -cr`. Logs: `python3 scripts/phone_evidence.py --since
<install time, local> --json`, and the same with `--mac`.

## Exact Next Action

When the chained job finishes, read `BenchmarkRuns/2026-11-17-synthesis-ceiling/full.out` and `score-0of3.txt`
(right answers per arm, and the synthesis-evidence line counts showing the window arm read above 3,200). Apply the rule:
if `window` is at least `ceiling` on right answers, make the window the shipped default (remove the 3,200 cap in
`ChainSynthesisEvidence.evidenceTokenBudget`, with CHANGELOG [Orchestration] and Atlas notes); otherwise keep the cap
and commit only the switch and test changes. Either way write the LEDGER entry for that folder, commit `[ci skip]`, and
report the numbers to the owner. Then rebuild both devices from HEAD for his device pass, and on "done" pull
`phone_evidence.py --since` the install times.
