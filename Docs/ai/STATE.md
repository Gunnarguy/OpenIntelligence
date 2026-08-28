# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: f9c1376

## Objective

Make the repository's documentation and roadmap rules mechanically enforced rather than advisory.
Complete and verified; **nothing is committed yet**, see Exact Next Action.

## Status

**Shipped app, unchanged this session.** iOS 5.0 and macOS 5.0.2 are live; 5.1 is open as the
unified next version for both platforms. No Swift changed.

**Governance enforcement layer built and tested.** The rules in `AGENTS.md` rule 14 and
`.agents/rules/01-docs-and-notion-sync.md` were real, but the checks behind them were not: the
pre-commit hook accepted **any** file under `Docs/` as satisfying **any** Swift change. Four pieces
now make the obligations mechanical, and two live drift defects found while doing it are repaired.

Working tree has 12 modified and 4 new files, all governance and documentation. Nothing committed.

## Completed

1. **The RepoOS router reported the open 5.1 release as `state: shipped`.** `repoos_router.py` reads
   "this section has not shipped yet" from an `unreleased` HTML comment on the heading's own line
   and nowhere else; the `## 5.1` heading carried explanatory prose on the lines below instead. It
   therefore named `[Unreleased]` as the changelog target while the heading's own comment, this file
   and `Docs/SHIPPED_VERSION.json` all said otherwise. `CLAUDE.md` tells every session to read that
   exact field. Marker added to the heading line; the router now reports
   `state: in_development, version: v5.1, last_shipped: v5.0.2`.
2. **`scripts/required_docs.sh` (new).** The single executable copy of the path-to-document table,
   the rule table unioned with the RepoOS change-impact matrix. Both enforcement points call it, so
   they cannot disagree.
3. **`scripts/enforce_docs_hook.sh` rewritten.** Fails a commit whose staged source lacks the
   documents that source requires, names them and what required them, and enforces
   `ci_post_clone.sh`'s empty-`[Unreleased]` invariant at commit time instead of at build time. Its
   architecture-tag check now examines only added bullet lines: it previously grepped every `+` line,
   so an unrelated tagged line elsewhere in the diff satisfied it.
4. **`.claude/hooks/notion-receipt.sh` (new).** `PostToolUse` on the Notion **write** tools only, so
   a query leaves no receipt. Records database, page, `Status`, `Target Release`. Where an update
   names a page rather than a database it records `database: unconfirmed` rather than implying more
   than it saw.
5. **`.claude/hooks/stop-handoff.sh` rewritten** from one check to three obligations: handoff,
   documentation, roadmap. All four original anti-loop guards are preserved. `session-start.sh` now
   records `head=` in the baseline so the Stop hook can name *which* paths a session touched.
6. **The Notion `Target Release` cache stopped at `v5.0` while `v5.1` was already live** in the
   database, in both `.claude/skills/notion-roadmap/SKILL.md` and
   `.agents/rules/01-docs-and-notion-sync.md`. Both files tell agents never to invent a value, which
   makes a stale cache worse than none. Both re-read off the live data source and re-dated.

Roadmap row, filed and closed:
[The pre-commit hook accepted any documentation file as satisfying any source change](https://app.notion.com/p/3ca49a74d54f81b3a02eeeaefbf54b5e)
— `Future Backlog`, because tooling meets none of the three tests for the active release.

## Active Constraints

- **The Xcode Cloud workflow is pinned to Xcode 26.6 (17F113) and must not go back to "Latest
  Release".** Twelve sites sit behind `#if compiler(>=6.4)`. Measured 2026-08-28: Xcode 26.6 ships
  Swift 6.3.3 so PCC compiles **out**; Xcode 27 ships Swift 6.4 so it compiles **in**, contradicting
  the App Store description, the README and the in-app copy. Xcode 27 is at beta 6, so "Latest
  Release" becomes it silently. `ci_scripts/ci_post_xcodebuild.sh` is the backstop proving the pin
  still holds — verified against a real Xcode 27 binary where it found 18 PCC symbols and exited 1.
- **`app_store` in `Docs/SHIPPED_VERSION.json` stays at `5.0`** while iOS lags. macOS is 5.0.2.
  Per-platform truth lives in `app_store_by_platform`; understating is the safe direction and is why
  that file exists.
- **Put 5.1 entries under `## 5.1`, not `## [Unreleased]`.** `ci_post_clone.sh` stamps
  `MARKETING_VERSION` from the first numbered heading and refuses to build when `[Unreleased]` holds
  entries above an uncut heading. `scripts/enforce_docs_hook.sh` now rejects it at commit time too.
- **Do not remove the `unreleased` HTML comment from the `## 5.1` heading line until 5.1 ships.** It
  is the only record in this repository that the section is open, `repoos_router.py` reads it from
  that line alone, and removing it is what "cutting the release" means.
- **`scripts/required_docs.sh` and the table in `.agents/rules/01-docs-and-notion-sync.md` are one
  fact in two files.** Change both in the same edit; the script is the copy that gets obeyed.
- **Paths in `ci_scripts/` must resolve from `$0`, not the working directory.** See Blockers.
- **No `xcodebuild test` runs in CI any more.** The Xcode Cloud TestFlight entries are post-actions,
  not test actions, and Actions is gone. Tests only run locally.

## Working Set

Sixteen uncommitted files, all governance and documentation. Open these first:

| File | Why |
|---|---|
| `scripts/required_docs.sh` | **New.** The table both enforcement points read |
| `scripts/enforce_docs_hook.sh` | Rewritten. Symlinked as `.git/hooks/pre-commit` |
| `scripts/test_enforce_docs_hook.sh` | **New.** 10 cases, real hook against a scratch git index |
| `scripts/test_stop_handoff.sh` | **New.** 8 cases, real hook against synthetic session baselines |
| `.claude/hooks/notion-receipt.sh` | **New.** Registered as `PostToolUse` in `.claude/settings.json` |
| `.claude/hooks/stop-handoff.sh` | Rewritten around three obligations |
| `.claude/hooks/session-start.sh` | Now records `head=` in the session baseline |
| `CHANGELOG.md` | Marker on the `## 5.1` heading, plus four `[General]` entries under it |
| `.agents/rules/01-docs-and-notion-sync.md` | Schema refresh and the changelog-target correction |
| `.claude/skills/notion-roadmap/SKILL.md` | Schema refresh, re-dated 2026-08-28 |
| `.claude/rules/repo-governance.md` | Describes the layer; previously said to leave the hook alone |
| `Docs/RepoOS/00_REPO_COMMAND_CENTER.md`, `01_TASK_ROUTER.md`, `change_impact_matrix.csv` | Route 15 now covers `.claude/**` and the enforcement scripts |
| `Docs/ai/STATE.md` | This file |

## Verification

Commands run this session, with observed output:

- `bash scripts/test_enforce_docs_hook.sh` → **10 passed, 0 failed**
- `bash scripts/test_stop_handoff.sh` → **8 passed, 0 failed**, no scratch files left behind
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` → **29 tests, OK**
- `python3 scripts/secret_scan.py` → no sensitive tokens
- `bash scripts/check_icloud_conflicts.sh` → no iCloud damage
- Router preflight after the marker fix → `state: in_development`, `version: v5.1`,
  `last_shipped: v5.0.2`, `changelog_section: ## 5.1`
- `grep -m1 '^## [0-9]' CHANGELOG.md | awk '{print $2}'` → `5.1`, so `ci_post_clone.sh` still stamps
  the right version; its `[Unreleased]` entry count is `0`
- `notion-receipt.sh` fired **live** on the roadmap row created this session and recorded
  `database: openintelligence-roadmap`, confirming `.claude/settings.json` hot-reloads mid-session

**Not verified: no Swift was built or tested this session.** No Swift changed, so the app is exactly
what commit `f9c1376` shipped, but that means nothing here re-confirms the app builds.

**Not verified: the Stop hook has never fired for real.** Its 8 tests drive the real script with
synthetic baselines, which is not the same as a live session ending. Its first real firing is the end
of this one.

## Blockers / Unknowns

None blocking. Three defects filed in Notion:

1. **[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)**
   — **now `v5.1`**, promoted 2026-08-28. Corrupts user data and already has: 599 conflict copies,
   136 unreadable zero-block files, 17 days of dead sync, and real chat history and vector indexes
   destroyed when the container was cleaned. `coordinatedMergeData` covers 4 paths, which had 0
   conflict copies; the 6 uncoordinated families had all 599.
2. **[420 workspace reloads per import](https://app.notion.com/p/3ca49a74d54f81a6b8c1e4827a6585fa)**
   — `Future Backlog`. Quality, not data loss.
3. **[17 views still use NavigationView](https://app.notion.com/p/3ca49a74d54f81eb867cf24a119af0c1)**
   — `Future Backlog`.

**Worth checking, unresolved:** `ci_post_clone.sh` runs
`sh ../scripts/probe_afm_advanced_canary.sh || true`. The capability guard added on the line below it
used the same CWD-relative style and failed on Xcode Cloud with exit 2 — python3's "cannot open
file" — breaking build 426. The guard now resolves from `$0` and build 427 passed, but the canary
still uses the old style **and** swallows its own failure, so it may not have run on Xcode Cloud for
some time without saying so. Verify by making it print and dropping the `|| true` for one run.

**Unexplained, did not recur:** build 424 failed with actor-isolation errors on
`HybridSearchService.stableTieBreakKey`, `analyse` and `overridesLock`, in the **macOS archive only**
— iOS archived fine in the same run. It does not reproduce locally in any combination tried (Xcode
26.6 and 27, Debug and Release, iOS and macOS), and build 427 archived both platforms cleanly. If it
returns, pull the Xcode Cloud build log rather than guessing at a fix.

## Exact Next Action

Commit the sixteen files listed in Working Set. Nothing is staged. There is no Swift in the change,
so `scripts/enforce_docs_hook.sh` exits early and will not gate it; the `[General]` CHANGELOG entries
are already written under `## 5.1`. Paths are enumerated rather than swept, per `CLAUDE.md`.

```bash
git add CHANGELOG.md Docs/ai/STATE.md Docs/RepoOS/00_REPO_COMMAND_CENTER.md Docs/RepoOS/01_TASK_ROUTER.md Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv .agents/rules/01-docs-and-notion-sync.md .claude/settings.json .claude/rules/repo-governance.md .claude/skills/notion-roadmap/SKILL.md .claude/hooks/session-start.sh .claude/hooks/stop-handoff.sh .claude/hooks/notion-receipt.sh scripts/required_docs.sh scripts/enforce_docs_hook.sh scripts/test_enforce_docs_hook.sh scripts/test_stop_handoff.sh
```

Then, if picking up product work, take the `v5.1` roadmap row in Blockers: it is the only open row
that loses user data and it is scoped to the open release.

Not done, offered and not yet chosen: four maintenance improvements found while researching current
Claude Code capability. In rough order of value — an `InstructionsLoaded` hook that logs which
instruction files actually load, a `PostCompact` hook to replace the `SessionStart(source=compact)`
replay, `permissions.deny` read rules for `build/`, `BenchmarkRuns/` and `Xrays/`, and using the
`transcript_path` the Stop hook already receives to propose `CLAUDE.md` updates. None are started.
