# 5.8 workflow retrospective, and what to build before 5.9

Written 2026-11-20 at the owner's request ("look for the gaps, look for the frustrations, look for the things that
you might've missed at first but then eventually caught"). This is about how the work was done, not what shipped;
what shipped is `Docs/USER_CHANGELOG.md`, `## v5.8`.

Method: every message the owner typed in this repository's Claude Code sessions from 2026-10-23 to 2026-11-20 was
extracted from the transcripts (859 messages, 58 sessions), 332 with a frustration, repeat or correction marker were
read, and recurring requests were counted by keyword. Keyword counts are approximate: they over-count where a word
has two meanings, and they under-count because the extraction left out messages he sent while a turn was running
(about 228 in the same dates, found on 2026-11-20 when `Docs/ai/DESIGN.md` was written from the same transcripts). Tool counts are exact, from the main session's transcript.

`[evidence_level: measured (transcript counts, git log), confidence: medium for keyword counts, exact for tool and commit counts]`

## The release in numbers

| | |
|---|---|
| Days from 5.7 live to 5.8 submitted | 28 (2026-10-22 to 2026-11-19) |
| Commits `v5.7.0..8e148387` | 397; 69 on 2026-11-07 alone (the file split) |
| Main session | one conversation, 2026-11-02 to 2026-11-20, 520 MB, 49 compactions, 688 owner messages |
| Shell commands in it | 10,219; 516 with `xcodebuild`, 141 device installs, 522 phone trace pulls, 388 commits |
| Submissions on 2026-11-19 | build 506 pulled, build 509 submitted, rejected 02:51 next morning (Guideline 3.1.2, no Terms link in the description), resubmitted 06:32 |

## Gaps, by what they cost

| # | Gap | Evidence | Fix |
|---|---|---|---|
| 1 | Nothing checked the store record before submitting. | The 3.1.2 rejection cost about 15 hours of review queue. `scripts/asc_prepare_release.rb` checks lengths only. The paywall already linked Apple's Terms; the description did not. | A submit gate: one script that reads App Store Connect and refuses to submit until every automated-review requirement holds (Terms and privacy links when subscriptions exist, lengths, build attached and processed, review notes under 4,000, screenshots per required size, age-rating answers, tag commit equals build commit). |
| 2 | The owner was the test harness for his phone. | About 40 "check trace" or "just ran" messages on 10 days; 522 trace pulls. | A phone watch: a background poll of the phone's journal and crash logs that wakes the agent on each new question, answer or crash, so it reports without being told. |
| 3 | No way to tell which build is on the phone. | About 27 "is it on my phone" or "was this the new build" messages on 13 days. The app carries no commit stamp. | Commit hash and build time in Settings, About and in every journal line; install after every green build of a Swift change when the phone is reachable; one line back saying what was installed. |
| 4 | App-lifecycle behaviour had no test. | Answers failing after leaving the app were raised 2026-11-04 and were still being fixed on submission day (about 27 messages on 9 days); 14 crash or freeze reports. The unit suite covers no backgrounding. | Scenario tests: leave during an answer, leave during an import, lock, kill and reopen, first launch after an install. Simulator on every pre-submit; the phone through Xcode 27's device interaction tools, whose description says they drive a physical device (read 2026-11-20, not yet tried on his iPhone). |
| 5 | One conversation carried the release. | 49 compactions; "I just had to compact please make sure that you understand everything"; the 4K and 8K window came up on 9 days although a memory marks it settled. | One session per workstream, started fresh from `STATE.md`. A single release page (scope, definition of done, measured numbers, open device checks) that the session brief prints. Consolidate the 120 memory files. |
| 6 | Quality work started before its baseline existed. | 2026-11-11 "youre saying none of hte changes made make this any better"; 2026-11-12 "only for this thing to basically be just as bad". `Docs/ai/MEASUREMENTS.md` still lists all 11 answer questions as Partly or Open. | A paired-run command: record the baseline, make the change, run the same set, print the difference. Retrieval sets need no Apple model, so they can run on Xcode Cloud in a manual-only test workflow (needs his approval to create). |
| 7 | UI went to his phone before he saw it. | About 35 messages on 11 days (noisy count): "tacky", "jumps around", "looks the exact same just renamed". | A design sheet from his rulings (`Docs/ai/DESIGN.md`), and before and after screenshots sent to him before any install of a UI change (Simulator, or Xcode's preview rendering). |
| 8 | Claims in the app outran the code. | 2026-11-11 "THERES FEATURES THAT DONT EXIST IN THE CODE"; about 31 accuracy questions on 15 days. `oi-claim-audit` covers removing a claim, nothing covers adding one. | A claims register: each figure or capability shown in Settings, the guide documents and the store description points at a code line or a run folder, checked in pre-commit. |
| 9 | Nothing watches the release after it ships. | The 5.8 watcher stops at go-live. Crashes reached the agent only when he pasted them. | A weekly read of Apple's crash, hang and launch data (Xcode's field-report tools), reviews and ratings. App Store Connect has webhooks since API 4.0, which need a public endpoint; polling is enough for now. |
| 10 | The release was four releases. | File split (11-05 to 11-07), model swaps (11-09 to 11-13), device and Settings pages (11-10 to 11-16), Mac redesign (11-18). | Once 1 to 4 exist, a submission is cheap, and each arc can ship by itself. His call. |

## Already fixed during 5.8, not to be rebuilt

- Overnight stalls: the `overnight` skill with a 20-minute heartbeat (2026-11-19).
- Roadmap rows as a list of 149: the `device-pass` skill, five phone steps and seven Mac steps (2026-11-04).
- Asking before every edit and push: standing approvals (2026-11-18).
- Recording a release when Apple approves it: `~/.agents/bin/oi_release_watch.py` (2026-11-19).
- Replies to the thesis student that repeated or misstated things: the `reply-check` and `thesis-student` skills.

## Order to build

1, 2, 3 first (each is under a day and removes the most repeated messages), then 4, then 5 and 6, then 7 to 9.

## Built so far

| # | Built | Where | Proof |
|---|---|---|---|
| 1 | 2026-11-20 | `scripts/asc_submit_gate.py`, `Docs/ai/RUNBOOK.md` "The submit gate" | Live 5.8: 0 FAIL, 3 WARN, 24 PASS in 22 s. The description of 2026-11-19: FAIL on both platforms. 14 tests. |
| 2 | 2026-11-20 | `scripts/phone_watch.py`, the `phone-watch` skill | One pass against the phone in 6.6 s; 1,991 events of 2026-11-19 became 39 lines with no private text; 7 tests. Not yet run while he tested. |
| 3 | 2026-11-20, steps 1 and 2 | `scripts/install_to_phone.py`, `Docs/ai/plans/build-stamp.md` | No app code: each device build gets the number `<commits>.<DDHHMM>` on the command line. Installed as 5.8 (1876.200935) = 19c36f86 in 163 s; the phone's app list read that number. Not yet seen in Settings or on a journal line (needs the app opened). 6 tests. |
| 4 | 2026-11-20 | `scripts/lifecycle_scenarios.py`, `OpenIntelligenceUITests/LifecycleScenarioUITests.swift`, the `lifecycle-check` skill | Six scenarios in the Simulator with Apple's model, judged from the journal: 6 of 6 passed twice, 10.5 minutes a run. Simulator only; the phone's background limits are not reproduced. Real use on the phone, 2026-11-19 on: answers finished 100% in front (11 of 11), 100% after leaving (11 of 11), 71% across a restart (10 of 14). 13 tests. |
| 5 | 2026-11-20 | `scripts/release_status.py`; a compaction count in `.claude/hooks/session-start.sh`; the memory index regrouped with settled facts first; `Docs/ai/ARCHITECTURE_DETAIL.md` | Status in 0.7 s from records. The hook says so from a conversation's third compaction. A memory audit found 31 contradictions between notes (five notes still said the Simulator has no model, two that the iPhone's window is 4,096): 18 stale notes now carry a dated correction, nothing deleted, 122 notes each indexed once. Three sections moved word for word out of `ARCHITECTURE.md`, so the every-task read set is 34.6 KB against its 40 KB limit (it was 48.5 KB and the test failed). |
| 6 | 2026-11-20 | `scripts/paired_run.py`, the `measure-answers` skill | Compares two runs question by question and says when a change is inside run-to-run variation; reproduces the ledger's reading of two real pairs of 2026-11-19. 56 tests. A real pair from the script: see the next line of this table when it has run. |
| 7 | 2026-11-20 | `Docs/ai/DESIGN.md`, `scripts/ui_shots.py`, the `ui-change` skill | 40 of the owner's UI rulings, each with his words and date (72 quotes checked against the transcripts by script). The shots tool photographs every main screen before and after a change and shows the changed ones side by side. 4 tests. |
| 8 | 2026-11-20 | `Docs/ai/CLAIMS.json`, `scripts/check_claims.py`, wired into the submit gate | 39 entries, 149 numbers in the store copy, 0 without evidence. No figure was wrong; four sentences around right figures were imprecise, corrected on iPhone and iPad the same day (the Mac version was already IN_REVIEW). 25 tests. |
| 9 | 2026-11-20 | `scripts/release_health.py`, launchd `com.gunnarguy.oi-release-health` (Mondays 09:15) | Reads reviews, the US rating, Apple's performance figures and diagnostics; notifies only on a change. First read: 2 reviews, 4 from 5 ratings, no performance data at this number of users. 3 tests. |
| 10 | not built | | Smaller releases are the owner's call. |
