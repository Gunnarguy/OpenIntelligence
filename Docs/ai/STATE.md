# Current State

Updated: 2026-11-20 12:20
Branch/worktree: `main`, primary checkout
Last verified commit: 56172a5b

## Objective

**Make 5.9 and later cheaper to build than 5.8 was**, by the fixes in `Docs/ai/RETRO_5.8.md` (owner, 2026-11-20:
"create a bulletproof productivity engine"; then "do all of them, now", with the condition "only if it helps you help
me ... dont want more hoops"). Nine of the ten are built; the tenth (smaller releases) is his call. 5.8 itself is
submitted and needs nothing by hand until Apple answers.

## Status

**5.8: build 509 (8e148387, tag `v5.8.0`). Mac IN_REVIEW since 2026-11-20 about 11:00 PT, iPhone and iPad
WAITING_FOR_REVIEW.** Rejected once on 2026-11-20 (Guideline 3.1.2, no Terms of Use link), fixed and resubmitted
06:32 PT. No app code has changed since the tag: `python3 scripts/release_status.py` prints "0 app files changed".

Store copy changed on 2026-11-20 while waiting for review, each at the owner's word and read back equal: promotional
text with percentages, the description as bullets with a `MEASURED IN 5.8` section, both What's New texts rewritten
for a general reader, the two new age-rating declarations answered No. The Mac's What's New could not take a later
correction (409, already IN_REVIEW); the three sentences concerned are in the 5.8 entry of
`Docs/Release/APP_STORE_METADATA_HISTORY.md` and in `Docs/ai/CLAIMS.json` notes.

| # | Fix | Tool | Skill | Proven by |
|---|---|---|---|---|
| 1 | Submit gate | `scripts/asc_submit_gate.py <version>` (through `zsh -ic`) | runbook "The submit gate" | live 5.8: 0 FAIL, 0 WARN, 26 PASS; fails the 2026-11-19 description |
| 2 | Phone watch | `scripts/phone_watch.py` under Monitor | `phone-watch` | reported his launch of 09:38 with build and commit; not yet a full testing session |
| 3 | Build number per phone build | `scripts/install_to_phone.py` | (memory) | phone shows 5.8 (1876.200935) = 19c36f86 |
| 4 | Lifecycle scenarios | `scripts/lifecycle_scenarios.py` | `lifecycle-check` | 6 of 6 passed twice, 10.5 minutes |
| 5 | Sessions and context | `scripts/release_status.py`; compaction count in the session-start hook; memory index regrouped; `Docs/ai/ARCHITECTURE_DETAIL.md` | `project-orient` | read set 34.6 KB of 40 KB (router test passes again) |
| 6 | Baseline before quality work | `scripts/paired_run.py` | `measure-answers` | reproduces two real pairs of 2026-11-19; no real pair run from the script yet |
| 7 | Show UI first | `Docs/ai/DESIGN.md`, `scripts/ui_shots.py` | `ui-change` | 40 rulings, 72 quotes checked; first shots run in progress at handoff |
| 8 | Claims register | `Docs/ai/CLAIMS.json`, `scripts/check_claims.py`, in the gate | rule `user-facing-copy` | 149 numbers, 0 without evidence |
| 9 | Release watch | `scripts/release_health.py`, launchd Mondays 09:15 | (runbook) | first read: 2 reviews, 4 from 5, no Apple performance data yet |
| 10 | Smaller releases | | | the owner's call |

## Active Constraints

- No source edit under `OpenIntelligence/` without the owner's `PROCEED: IMPLEMENT`; all of the above is scripts,
  skills, docs, one UI-test file and one hook.
- 5.8 is unreleased: no new version heading, and do not edit `Docs/SHIPPED_VERSION.json`, the `## v5.8` heading in
  `Docs/USER_CHANGELOG.md` or `OpenIntelligence/Resources/VersionHistory.md` (launchd `com.gunnarguy.oi-release-watch`
  does it and pushes). `git fetch` and check `git rev-list --count HEAD..origin/main` before each commit.
- Submitting to Apple and starting an Xcode Cloud build are the owner's word each time. Commits carry `[ci skip]`.
- The standing approvals of 2026-11-18 were for 5.8. Ask once when 5.9 work starts.
- An install to his phone that is not a fix he is waiting on gets one line to him first (2026-11-20: "im officially
  confused why you just built another version to my phone").
- `.agents/skills/`, `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks/` are other agents' machine-local mirrors:
  neither committed nor deleted, hidden from `git status` by this checkout's `info/exclude`.
- Scratch copies never include `.env*` (the scripts exclude it since 2026-11-20).

## Working Set

| File | Why |
|---|---|
| `Docs/ai/RETRO_5.8.md` | The ten gaps with their evidence, and the "Built so far" table. |
| `Docs/ai/RUNBOOK.md` | One section per tool, each added 2026-11-20. |
| `scripts/*.py` named in the table, each with `scripts/test_<name>.py` | 123 tests in eight files, none needing a simulator or network. |
| `.claude/skills/{phone-watch,lifecycle-check,ui-change,measure-answers}/SKILL.md` | When to use each tool; their descriptions load every session. |
| `Docs/ai/DESIGN.md`, `Docs/ai/CLAIMS.json`, `Docs/ai/ARCHITECTURE_DETAIL.md` | The rulings, the register, and the three sections moved out of the map. |
| `~/Library/Developer/OpenIntelligence-evidence/` | Outside the repository: the phone journal copy, install record, lifecycle and UI-shot run folders. |

## Verification

- Eight test files -> all pass: `test_asc_submit_gate` 16, `test_phone_watch` 8, `test_install_to_phone` 6,
  `test_lifecycle_scenarios` 13, `test_ui_shots` 4, `test_release_health` 3, `test_check_claims` 25, `test_paired_run` 56.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> OK (it failed at 48,493 bytes
  before the move). `python3 scripts/verify_doc_claims.py` -> 2,365 claims, all match. `python3 scripts/secret_scan.py`
  -> clean. `bash scripts/test_stop_handoff.sh` -> 11 passed.
- `zsh -ic 'python3 scripts/asc_submit_gate.py 5.8'` -> 0 FAIL, 0 WARN, 26 PASS (2026-11-20 11:44).
- `python3 scripts/lifecycle_scenarios.py` -> 6 of 6, twice. `zsh -ic 'python3 scripts/release_health.py'` -> report,
  then "Nothing new". `python3 scripts/release_status.py` -> 8 lines in 0.7 s.
- Not yet run to the end at this handoff: `python3 scripts/ui_shots.py pair --before HEAD` (the before half took
  1,168 s for 9 tests, 0 failures), and any real `paired_run.py pair`.

## Blockers / Unknowns

- One branch, `main`, locally and on GitHub; one worktree. The Mac redesign and TipKit sessions are archived; the
  tour's open items for 5.9 are on its roadmap row (40d49a74d54f81218bd0d100b44984e0).
- The memory audit of 2026-11-20 found 31 contradictions; 18 notes carry a dated correction and the rest are listed
  in this session's transcript only. The old index is at
  `~/Library/Developer/OpenIntelligence-evidence/memory-index-before-2026-11-20.md`.
- `codemap.py check` reports 4 errors and 272 warnings (citations that moved in the 5.8 file split); 5 run folders
  under `BenchmarkRuns/` have no `LEDGER.md` entry.
- `bash scripts/test_verify_doc_claims.sh` was still running after 7 minutes when this was written; the checker
  itself passes.

## Known and not fixed in the app (carried from 2026-11-19)

- Identical files under two names import as one ("Already imported"); the queue card said "Paused after app restart"
  though the app had not restarted.
- Mac: Services Ask fills the other window's field with two windows open; Finder Add on an iCloud file not downloaded
  shows nothing for about 2 minutes.
- `scripts/score_answer_eval.py` fails a right refusal that later lists any dollar amount.
- Held for after 5.8 (Future Backlog, patches in `BenchmarkRuns/2026-11-18-held-after-5.8/`): Standard's planner model
  call (2.5 to 12 s before every question), and the case-insensitive Code/Standard spec patterns.
- Search setup after an install took 55 to 99 s (embedding) and 87 to 131 s (reranker) on the iPhone at thermal state
  serious. Main-thread stalls on Chat during rebuilds (worst 1,658 ms); the fix 641c7aa9 is not yet seen on the phone.
- The app never says the phone's storage is full (Future Backlog 41b49a74d54f81eebbc3fbbee08a878d).
- Open UI asks with no answer: the Standard picker's capsule on the Mac, the colour and icon pickers, repeated
  plan-card bullets. `AtlasLabeling.titleCase` writes "Ipad & Iphone".
- Not yet seen on the phone: bcb9f12e (an answer left mid-way finishing with full evidence), 0a2e346a (Siri Ask with a
  rate limit).

## Exact Next Action

If `~/Library/Developer/OpenIntelligence-evidence/ui-shots/2026-11-20_113335/SUMMARY.txt` does not exist, the first UI
shots run did not finish: run `python3 scripts/ui_shots.py pair --before HEAD` again (same code on both sides, so it
should report no screen changed; that is the tool's noise check). Then run
`python3 scripts/paired_run.py pair --before HEAD --after HEAD` once: it proves the script end to end and gives the
number of Standard questions that flip between two runs of one build, which every later comparison needs. Add the
`BenchmarkRuns/LEDGER.md` lines it prints.

When Apple approves 5.8 (launchd `com.gunnarguy.oi-release-watch` records it, log
`~/.agents/data/oi-release-watch/log.txt`): add the release-notes, docs-index and metadata-history lines the 5.7
commit 3face1fb carried, then file Future Backlog rows in Notion for the continuation trigger on a final list item
without a period, Apple's background rate limit, Siri scope and open-document, the DHA named-document row, Standard's
planner model call, and the Mac Dock/Space behaviour of the details sheet. For 5.9, correct the Mac release notes'
three sentences and re-measure or remove the description's `MEASURED IN 5.8` section.
