# Current State

Updated: 2026-09-28 (Repo Map built; safe cleanup done: 19 stale docs down to 7; development still paused after 5.4)
Branch/worktree: `main`, primary checkout
Last verified commit: 8759404

## Objective

None active for the app. 5.4 shipped on both platforms on 2026-09-24, and the owner paused
development after it (`Docs/ai/DECISIONS.md`, 2026-09-24). The next version is 5.5, his pick; open it
only when he says to.

On 2026-09-28 he asked for the repository to be easy to navigate and to show which of its files are
still accurate, then to do the cleanup "that won't break anything". Both are done (Status). What is
left needs his word or an app release (Blockers).

## Status

- **Repo Map, done 2026-09-28.** `.claude/skills/repo-map/` surveys every tracked file at a commit,
  read-only, and rebuilds the owner's private page https://claude.ai/artifact/TJVQ32i3gjkBPvFUxcySyk
  (version 2, surveyed at `8759404`). The page gives each document a status with its evidence, lists
  the Swift files no other file names, draws the import and question flow, and lists the loose
  files git ignores. How to rebuild, and what each status means: `.claude/skills/repo-map/SKILL.md`.
  Roadmap row https://app.notion.com/p/3e949a74d54f8193a94ec70cfba90c0d (Completed, Future Backlog).
  - Committed in `8759404`, `c0a2d69` and the cleanup commit after them, **none pushed**. Until they
    are, the page's GitHub links point at `df2c5b5`.
- **Cleanup, done 2026-09-28** (documentation and tooling only):
  - Docs naming code or files that no longer exist: 19 down to 7. Corrected against the code, with
    evidence tags: `Docs/INGESTION_PIPELINE.md` (token limit as `DocumentProcessor` enforces it, not
    `BertTokenizer`), both EdgeToEdge docs (`HybridSearchService.searchWithFTS5`),
    `Docs/Engineering/FULL_SYSTEM_TRACE.md` (`OCRConfiguration.configureRequest`), the research
    reference sheet, and dated notes in `Docs/AppleIntelligenceTransitionPlan.md` and
    `Docs/Engineering/V5_EMBEDDING_ARC_LEDGER.md`. The seven left are plans, playbooks or a ledger
    that name files that were proposed and never built; the page shows each reason.
  - The survey stopped flagging correct references: a `+` in a file name, xcodebuild test
    identifiers, and names whose own sentence says they are gone. Earlier this session I said three
    docs call `BertTokenizer` current; only `Docs/INGESTION_PIPELINE.md` did, and it is fixed.
  - Six loose root files (five console logs and `default.profraw`) moved into `.attic.nosync/`, the
    attic `.gitignore` line 264 names for exactly this. Not in git before or after.
  - Roadmap row https://app.notion.com/p/3db49a74d54f81ecaec2f00491bc1239 closed: its two Stop-hook
    tests pass (11/11), and `ff7f493` names the cause.
  - Deliberately not moved: the seven top-level audit snapshots in `Docs/`. `Docs/README.md`
    records a 2026-08-17 decision that moving them breaks 48 references and the RepoOS.
- **5.4 is live on iOS and macOS**, build 478 (Xcode Cloud #478 from `c276b9a`), and closed out in
  this repository, on GitHub (`v5.4.0` is Latest), on all three websites and in Notion. The release
  procedure used is in `Docs/ai/RUNBOOK.md`, "Releasing an approved version through the API".
- **Documentation overhaul row still open:** https://app.notion.com/p/3e549a74d54f815087d7db62848adb40
  (Future Backlog, In Progress). It closes when `/context` in a fresh Claude Code session on the Mac
  shows the lighter startup load.
- **A global `codemap` skill exists** at `~/.claude/skills/codemap/`, built 2026-09-28 by another
  session for a different app (OpenResponses). It is the agent-facing feature index and graph. It
  has not been applied here. Its install step copies `codemap.py` into `scripts/`, and in this repo a
  push touching `scripts/` starts an Xcode Cloud build, which with no version open stamps 5.4 and is
  rejected. Keep the tool under `.claude/` or put `[ci skip]` in the commit message.
- Scheduled: 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`, which takes the sale line
  off the listing and the three sites. It is still needed.

## Active Constraints

- **No version is open in `CHANGELOG.md`.** Before any app-change push, open
  `## 5.5 <!-- unreleased -->` above `## 5.4` with `<!-- next-version: 5.5 -->`, and create the 5.5
  records in App Store Connect. Xcode Cloud's filter skips only `*.md`, `Docs/`, `.claude/`,
  `.agents/`, `.codex/`, `fastlane/metadata/` and `.github/`.
- `[General]` changelog entries for post-5.4 tooling wait in
  `Docs/AuditArtifacts/DocOverhaul_2026-09-24/README.md`, "CHANGELOG entries, to file when 5.5
  opens" (four entries, repo-map and the doc cleanup included). Copy them under 5.5 when it opens.
- `CLAUDE.md` forbids deleting docs. Removing a doc means moving it (`git mv`) into `Docs/Archive/`
  unless the owner lifts that rule in so many words.
- App Store Connect writes happen only at the owner's word. Guard memory on builds (18 GB Mac):
  `-jobs 2`, stop at 15% free, build from `/private/tmp/oi-src`. Commit to `main`, no branches, no AI
  trailer. Pushing to GitHub publishes to a public repository: ask first.

## Working Set

- `.claude/skills/repo-map/SKILL.md`: the rebuild command and the status rules.
- `.claude/skills/repo-map/scripts/build_map.py`: the survey; imports `scripts/verify_doc_claims.py`.
- `.claude/skills/repo-map/scripts/page_template.html`, `render.py`: the page.
- `.claude/skills/repo-map/scripts/test_build_map.py`: re-derives the survey's verdicts.
- `Docs/SHIPPED_VERSION.json`, `CHANGELOG.md`, `Docs/USER_CHANGELOG.md`,
  `OpenIntelligence/Resources/VersionHistory.md`: the release records.

## Verification (2026-09-28, output read)

- `python3 .claude/skills/repo-map/scripts/test_build_map.py` -> 9 tests OK after the cleanup
  (three added to pin the false-positive fixes). An earlier run failed on `Package.swift`'s exclude
  list naming `KeychainStorage.swift`; the test now reads only the source folders the survey reads.
- Survey after the cleanup: 265 documents: 1 mostly out of date, 6 with dead references, 20 behind
  the code, 67 whose references all resolve, 69 unchecked prose, 102 history.
- `python3 .claude/skills/repo-map/scripts/build_map.py --out "$TMPDIR/oi-repo-map/data.json"` ->
  986 tracked files, 265 documents, 365 Swift files, in 46 s. Republished as version 2.
- `python3 scripts/verify_doc_claims.py` -> 719 claims checked, all match.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 31 OK.
- `python3 scripts/secret_scan.py` -> no sensitive tokens.
- `bash scripts/test_enforce_docs_hook.sh` -> 18 passed. `bash scripts/test_stop_handoff.sh` -> 11
  passed, 0 failed.
- Not run: `bash scripts/build_simulator_smoke.sh`. No smoke DerivedData exists, so it would be a
  cold build, and nothing compiled changed. Earlier: the full iOS suite ran 500 tests, 0 failures, on
  the 5.4 code (2026-09-23).

## Blockers / Unknowns

- **Still the owner's call, or an app release's:**
  - 28 Swift files, 7,027 lines, that no other file names. Deleting them is an app change: it needs
    5.5 opened, a guarded build and the test suite. Not touched.
  - 26 study-guide files in `Docs/Audio/`: his content, no evidence they are unused. Not touched.
  - Same-name pairs: `Docs/ARCHITECTURE.md` (marked superseded, v4.1) beside
    `Docs/ai/ARCHITECTURE.md`, and a `HOW_IT_WORKS.md` at the root and in `Docs/`. The root one is
    user-facing; check the three websites' links before moving either.
  - The seven docs still flagged are plans and playbooks naming proposed files. Leave them, or mark
    each as history if he says the plan is dead.
- **Push:** every commit since `df2c5b5` is local. Pushing publishes to the public repository; do it
  only on the owner's word. Documentation and `.claude/` paths do not start an Xcode Cloud build.
- **Six `v5.4` rows close on the owner's device check**; nothing can verify them from here. When he
  says they work, set each to `Completed` with `date:Completed:start` 2026-09-24 or later:
  https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142,
  https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3,
  https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767,
  https://app.notion.com/p/3e349a74d54f81b49205d1a75f2a4b99,
  https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9,
  https://app.notion.com/p/3e149a74d54f819aba78e2b85f0e9942.
- **Evidence Threads sync may copy nothing:** the store writes `<AppSupport>/EvidenceThreads/`
  (`EvidenceThreadStore.swift:60`) and sync reads `<AppSupport>/OpenIntelligence/EvidenceThreads/`
  (`WorkspaceSyncService.swift:2739`, a hard-boundary file). Verify on a Pro build with library sync
  on.
- The three subscription descriptions in App Store Connect are still wrong. The API refuses them (409,
  ACTIVE), so they are a web-page edit, the owner's. Owner decisions carried: whether to rename
  Lifetime (a new IAP version); `.build` (856 MB) and `build/` (444 MB) at the root lack `.nosync`.

## Exact Next Action

None. The Repo Map and the safe cleanup are done and verified. There is no active objective; ask the
owner whether to push the local commits, and what to pick up next.
