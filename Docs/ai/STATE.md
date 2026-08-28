# Current State

Updated: 2026-08-28
Branch/worktree: main (primary checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: 3d32a8b

## Objective

Make the repository's documentation and roadmap rules mechanically enforced rather than advisory,
and make "did Claude actually read that rule?" a question with an answer.

Complete and verified. The first half is committed as `3d32a8b`; the InstructionsLoaded half is
uncommitted, see Working Set.

## Status

**Shipped app, unchanged this session.** iOS 5.0 and macOS 5.0.2 are live; 5.1 is open as the
unified next version for both platforms. No Swift changed.

**Governance enforcement layer built and tested.** The rules in `AGENTS.md` rule 14 and
`.agents/rules/01-docs-and-notion-sync.md` were real, but the checks behind them were not: the
pre-commit hook accepted **any** file under `Docs/` as satisfying **any** Swift change. Four pieces
now make the obligations mechanical, and two live drift defects found while doing it are repaired.

Six pieces now make the obligations mechanical. `3d32a8b` carries four of them; the two that answer
the loading question are uncommitted.

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

7. **A path-scoped rule that never loads is indistinguishable from one that was read and ignored,
   and they have opposite fixes.** `.claude/hooks/instructions-loaded.sh` records every instruction
   file as it loads, with `load_reason` (`session_start`, `path_glob_match`, `nested_traversal`,
   `include`, `compact`), the `paths:` globs that matched, and the triggering file.
   `scripts/instructions_report.sh` reads that log against a set of changed paths and names any rule
   that should have loaded and did not. The Stop hook appends the same finding when it already has
   something to ask, and stays silent when no log exists, because an absent log means the hook was
   not registered rather than that nothing loaded. Observed firing live.
8. **Three rule files and `AGENTS.md` still sent changelog entries to `[Unreleased]`**, which the
   open-section protocol superseded. All corrected to read the preflight's
   `documentation_targets.changelog_section`.

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

Committed in `3d32a8b`: the four-piece enforcement layer and its two test suites.

Uncommitted, the InstructionsLoaded half:

| File | Why |
|---|---|
| `.claude/hooks/instructions-loaded.sh` | **New.** Registered as `InstructionsLoaded` in `.claude/settings.json` |
| `scripts/instructions_report.sh` | **New.** Reads that log; `--unloaded` is what the Stop hook calls |
| `.claude/hooks/stop-handoff.sh` | Appends the unloaded-rule finding to an existing block |
| `scripts/test_stop_handoff.sh` | Three new cases: rule missing, rule present, no log at all |
| `.claude/rules/retrieval.md`, `orchestration-and-routing.md`, `user-facing-copy.md`, `AGENTS.md` | Changelog target corrected off `[Unreleased]` |
| `.claude/rules/repo-governance.md`, `Docs/RepoOS/00_REPO_COMMAND_CENTER.md`, `01_TASK_ROUTER.md`, `change_impact_matrix.csv` | The layer is six pieces now, not four |
| `CHANGELOG.md` | One more `[General]` entry under `## 5.1` |

Read `.claude/rules/*.md` before changing any glob: `scripts/instructions_report.sh` parses that
frontmatter itself and its glob translation (`**` crosses separators, `*` does not) must keep
agreeing with how Claude Code matches.

## Verification

Commands run this session, with observed output:

- `bash scripts/test_enforce_docs_hook.sh` → **10 passed, 0 failed**
- `bash scripts/test_stop_handoff.sh` → **11 passed, 0 failed**, no scratch files left behind
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` → **29 tests, OK**
- `python3 scripts/secret_scan.py` → no sensitive tokens
- `bash scripts/check_icloud_conflicts.sh` → no iCloud damage
- Router preflight after the marker fix → `state: in_development`, `version: v5.1`,
  `last_shipped: v5.0.2`, `changelog_section: ## 5.1`
- `grep -m1 '^## [0-9]' CHANGELOG.md | awk '{print $2}'` → `5.1`, so `ci_post_clone.sh` still stamps
  the right version; its `[Unreleased]` entry count is `0`
- `notion-receipt.sh` fired **live** on the roadmap row created this session and recorded
  `database: openintelligence-roadmap`, confirming `.claude/settings.json` hot-reloads mid-session
- `instructions-loaded.sh` fired **live**: reading `HybridSearchService.swift` logged
  `path_glob_match Project .claude/rules/retrieval.md`, with the triggering file recorded

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

Commit the fifteen uncommitted files in Working Set. Nothing is staged; no Swift is involved, so the
pre-commit hook exits early.

```bash
git add CHANGELOG.md AGENTS.md Docs/ai/STATE.md Docs/RepoOS/00_REPO_COMMAND_CENTER.md Docs/RepoOS/01_TASK_ROUTER.md Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv .claude/settings.json .claude/hooks/instructions-loaded.sh .claude/hooks/stop-handoff.sh .claude/rules scripts/instructions_report.sh scripts/test_stop_handoff.sh
```

Then, for product work, take the `v5.1` roadmap row in Blockers: it is the only open row that loses
user data and it is scoped to the open release.

**The layer is unproven where it matters most.** Every test drives the scripts directly. Nothing has
yet observed the pre-commit hook refusing a real Swift commit, because no Swift has changed since it
was written. The first 5.1 code change is the real test: if the hook fires and names the right
document, it works; if it fires on something irrelevant, loosen it before it gets bypassed.
