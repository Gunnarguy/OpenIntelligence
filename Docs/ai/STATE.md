# Current State

Updated: 2026-11-20 09:45
Branch/worktree: `main`, primary checkout
Last verified commit: ccc2f840

## Objective

**Make 5.9 and later cheaper to build than 5.8 was**, by building the fixes in `Docs/ai/RETRO_5.8.md` in its order
(owner, 2026-11-20: "create a bulletproof productivity engine so that 5.9 and any version beyond this is significantly
easier to iterate on"; then "Yes, build 1 to 3"). 5.8 itself is submitted and needs nothing by hand until Apple answers.

## Status

**5.8 is waiting for review on both platforms with build 509** (from 8e148387, tag `v5.8.0`), release AFTER_APPROVAL.
Apple rejected it on 2026-11-20 at 02:51 (Guideline 3.1.2: subscriptions on sale and no Terms of Use link in the
description). The description now ends with Apple's standard EULA link on both platforms (3b35cb50) and the owner
had it resubmitted at 06:32 PT. No app code changed; build 509 is unchanged.

Retrospective fixes, of ten:

| # | Fix | State |
|---|---|---|
| 1 | Submit gate | Built: `scripts/asc_submit_gate.py`, runbook "The submit gate". |
| 2 | Phone watch | Built: `scripts/phone_watch.py`, skill `phone-watch`. Not yet run while the owner tested. |
| 3 | Which build is on the phone | Plan only: `Docs/ai/plans/build-stamp.md`. Steps 1 and 2 need no app code. |
| 4 to 10 | Lifecycle tests, one session per workstream, paired runs, design sheet, claims register, post-release watch, smaller releases | Not started. |

## Active Constraints

- No source edit under `OpenIntelligence/` without the owner's `PROCEED: IMPLEMENT`; the retrospective work so far is
  scripts, skills and docs only.
- 5.8 is unreleased: no new version heading, and do not edit `Docs/SHIPPED_VERSION.json`, the `## v5.8` heading in
  `Docs/USER_CHANGELOG.md` or `OpenIntelligence/Resources/VersionHistory.md` (the release watcher does it and pushes).
  `git fetch` and check `git rev-list --count HEAD..origin/main` before each commit.
- Submitting to Apple and starting an Xcode Cloud build are the owner's word each time. Commits carry `[ci skip]`.
- Do not stage `scripts/run_quality_matrix.py`, `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md`, the three
  `Docs/ai/codemap/*.md` files, `.agents/skills/` or `.codex/`: another session's work.

## Working Set

| File | Why |
|---|---|
| `Docs/ai/RETRO_5.8.md` | The ten gaps, their evidence, the order to build, and what is built so far. |
| `scripts/asc_submit_gate.py`, `scripts/test_asc_submit_gate.py` | Fix 1. `collect()` reads App Store Connect, `check()` is a pure function of the snapshot. |
| `scripts/phone_watch.py`, `scripts/test_phone_watch.py`, `.claude/skills/phone-watch/SKILL.md` | Fix 2. `SHOW` and `SHOW_WHEN` list the events and the only fields a line may carry. |
| `Docs/ai/plans/build-stamp.md` | Fix 3's plan: a build number per device build on the `xcodebuild` command line, then an install script with a record. |
| `Docs/ai/RUNBOOK.md` | New sections "The submit gate" and "Watching the phone while the owner tests"; step 0 in "Submitting for review through the API". |

## Verification

- `zsh -ic 'python3 scripts/asc_submit_gate.py 5.8'` -> 0 FAIL, 3 WARN, 24 PASS, 22 s (2026-11-20 09:23). WARN: two
  age-rating questions empty (`datingAndRelationships`, `sharedLocation`), and 4 What's New lines with a count and no
  percentage on each platform.
- The same snapshot with the 2026-11-19 description (`git show 3b35cb50^:fastlane/metadata/en-US/description.txt`) ->
  FAIL `terms-link` on both platforms, exit 1.
- `python3 scripts/test_asc_submit_gate.py` -> 14 passed. `python3 scripts/test_phone_watch.py` -> 7 passed.
  `python3 scripts/test_phone_evidence.py` -> passed. `python3 scripts/secret_scan.py` -> clean.
- `python3 scripts/phone_watch.py --once --since 2026-11-19T15:30` against the iPhone -> 3 lines, 6.6 s. 90 s under the
  Monitor tool with the phone idle -> no lines.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 30 passed, 1 failed:
  `test_every_task_loads_only_the_small_universal_set`, 48,493 bytes against a 40,000 limit. Not caused by this work:
  `Docs/ai/ARCHITECTURE.md` alone is 37,041 bytes.

## Blockers / Unknowns

- The every-task read set is over its limit (above). Fix by cutting `Docs/ai/ARCHITECTURE.md` back to a map that
  points at the owning docs; verify with the router test.
- The gate's age-rating warning: App Store Connect has two questions unanswered on the 5.8 record. Apple accepted the
  submission with them empty. Answering them is the owner's (App Store Connect, App Information, Age Rating).
- 5.8's age rating computes 4+ where the live 5.7 record shows 17+ (a 16+ override). This was chosen on 2026-11-06
  (`~/ASC/CHANGES-2026-11-06.md`, "the 16+ override dropped on 5.8"); the gate prints it as information.
- Whether a journal pull works while the phone is locked is not measured.

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

Wait for the owner's word on the build stamp: `Docs/ai/plans/build-stamp.md` steps 1 and 2 (a per-build number on
the device build's command line, then `scripts/install_to_phone.sh` with its install record). They touch no app code,
so they do not wait for 5.8. On his yes: add `CURRENT_PROJECT_VERSION=<commits>.<DDHHMM>` to the device build in
`Docs/ai/RUNBOOK.md` "Building to the owner's iPhone", run the plan's four checks on the first build that uses it, and
write the script.

When Apple approves 5.8 (launchd `com.gunnarguy.oi-release-watch` records it, log
`~/.agents/data/oi-release-watch/log.txt`): add the release-notes, docs-index and metadata-history lines the 5.7
commit 3face1fb carried, then file Future Backlog rows in Notion for the continuation trigger on a final list item
without a period, Apple's background rate limit, Siri scope and open-document, the DHA named-document row, Standard's
planner model call, the Mac Dock/Space behaviour of the details sheet, and the retrospective's fixes 4 to 9.
