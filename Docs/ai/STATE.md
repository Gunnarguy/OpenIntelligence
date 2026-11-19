# Current State

Updated: 2026-11-19 06:50
Branch/worktree: `main`, primary checkout
Last verified commit: 5052c221

## Objective

**Ship 5.8.** The owner runs his device pass on the checklist page https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT
(12 prompts; every file they need is in iCloud Drive › "OpenIntelligence 5.8 check"; ticks now sync across devices
through the page's shared store, readable with ArtifactData collection `pass`, doc `checks`), says "done", the agent
closes rows from the logs, and only at his word starts Xcode Cloud and pushes store text; he submits. No rating reset on 5.8.

## Status

Main is at 5052c221, pushed (`[ci skip]`, no Xcode Cloud build). The iPhone runs a Debug build of that code (installed
2026-11-18 22:55 from `/private/tmp/oi-neg-wt`). The Mac's /Applications app is the Mac redesign's Debug build (branch
`mac-redesign`, a98dc001, worktree `/private/tmp/oi-mac-wt`, session local_b5d860ee), which does not yet have 5052c221;
that session rebases onto main after 5052c221 and pushes. Device-pass page: 7 ticked (prompt-0-0, 0-1, 0-2, 3-0;
mac-2-2, 3-0, 3-1). Library 11 (iCloud) on the Mac holds the six check files for the lease, Lisbon, DHA and notes prompts.

Running: the Maximum A/B for the entity-binding change, four runs alternating ablation off/on
(`/private/tmp/oi-neg-wt/BenchmarkRuns/2026-11-18-maximum-ab/chain2.sh`, labels base1-r, fix1-r, base2-r, fix2-r,
from 06:38, about 36 min each). It decides whether 5052c221's entity binding stays: the change stays only if the
two fix runs together are not below the two base runs.

## Completed on 2026-11-18 (pushed)

| Commit | What |
|---|---|
| 5934c8e8 | Library Settings no longer overflows the main thread's stack in a Debug build (`SeparatelyBuilt`); Guide library documents can't be deleted |
| b3f83ec8 | Guide library permanent (no delete, read-only settings, takes no files, restored at Documents open); "General" renamed "Library 1" once (description marker) at load and in `WorkspaceSyncService.mergeContainers`; Core ML embedder follows the app into the background (CPU and Neural Engine) and the mode switch has its own lock (fixed a 2 min 20 s background hang and a 0x8BADF00D watchdog kill on his iPhone) |
| dc6cc426 | A bold label bullet in an answer draws as a heading |
| f141eee8 | Semantic Atlas: cluster names draw again (chamfered `SCNText` draws nothing on iOS 27), no lines to nowhere, short names, label-size words, no overlap |
| 43b06f3c | Tokens per second is the final answer's writing speed, live and saved, in every mode |
| 5052c221 (2026-11-19) | A list item's number stays with its subject (sentence extraction keeps the lead, `EntityBinding` in Fact Check, citation note), and a "no" counts in Fact Check only when it denies what the claim names (`ClaimCheck.resolvingNo`); ledger entries for both |

Earlier today: 1453b194 (guide first in every row), 75bf6d3f and 46b9055a (Model Parameters), f5759e4d and e4a191cd (sync).

## Not verified on a device

The 0.28 answer was seen right on the iPhone (trace 2026-11-18 20:45), before the "no" fix; "1 of 1 Verified" for it
on the 22:55 build is not yet seen. Earlier rows: Library Settings with Technical Details on; an import resuming on
return; the Guide library locks; "Library 1" on both devices; the Atlas card; tokens per second in Deep Think.

## Standing approvals (owner, 2026-11-18)

For 5.8: hard-boundary edits with a test or trace proving the defect and a refuting review, named in the commit; push
`main` as commits land. Install builds on both devices. Still his alone: submitting, starting Xcode Cloud, outward
messages, spending money. The path rule ".claude/rules/ingestion-and-indexing.md" puts `CoreMLSentenceEmbeddingProvider`
internals out of bounds; b3f83ec8 edited them for the proven hang, and he has not yet been told that explicitly.

## Active Constraints

- Commits `[ci skip]`, no attribution lines, never `git add .`; never stage `scripts/run_quality_matrix.py` or
  `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` (another session's changes), nor the untracked `.agents/skills/` and `.codex/` files.
- One xcodebuild and one booted simulator at a time; never the whole macOS hosted suite (his real library).
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical.
- The phone trace, journal and Mac prefs hold his file names: grep them, never print them whole or commit them.
- Before any device-dependent constant, run the `scale-to-the-device` skill (read Apple's page first).

## Known and not fixed

- Identical files under two names import as one ("Already imported"), so the device pass's Kestrel prompt (the same PDF
  twice) cannot be set up as written; the queue card said "Paused after app restart" though the app had not restarted.
- Mac: Services Ask fills the other window's field with two windows open; Finder Add on an iCloud file not downloaded
  shows nothing for about 2 minutes (the Mac session lists both as follow-ups).
- The answer scorer (`scripts/score_answer_eval.py`) fails a right refusal that later lists any dollar amount.
- Held for after 5.8, Future Backlog rows, patches in `BenchmarkRuns/2026-11-18-held-after-5.8/`: Standard's planner
  model call (2.5 to 12 s before every question), and the case-insensitive Code/Standard spec patterns.

- Search setup after an install took 55 to 99 s (embedding) and 87 to 131 s (reranker) on his iPhone at thermal state serious.
- Main-thread stalls on Chat during rebuilds (worst 1,658 ms); the `@concurrent` fix (641c7aa9) is not yet seen on the
  phone. Next: `bash scripts/profile_phone.sh` while he rebuilds one library.
- The app never says the phone's storage is full (Future Backlog 41b49a74d54f81eebbc3fbbee08a878d).
- Open UI asks with no answer: the Standard picker on the Mac lacks its capsule; the colour and icon pickers; repeated plan-card bullets.
- `AtlasLabelingTests` adverb tests depend on the simulator having English word classes (skip on a fresh one).
- Axis ends title-case brand names wrong ("Ipad & Iphone", `AtlasLabeling.titleCase`).
- A label heading in a grounded answer stays 18 pt while body text scales, so at AX2 it is smaller than its bullets (as `###` headings already are); changing it needs the owner's word.
- A `CoreMLSentenceEmbeddingProvider` prediction already running when the app leaves is not covered by the background switch.

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

When `chain2.sh` finishes, score the four runs with `python3 scripts/score_answer_eval.py <run>/maximum-app.xcresult`
for each `2026-11-19-*-answer-modes-bind-{base1-r,fix1-r,base2-r,fix2-r}` folder in `/private/tmp/oi-neg-wt/BenchmarkRuns`.
If fix1+fix2 >= base1+base2, record it in `BenchmarkRuns/LEDGER.md` (copy the folders in) and keep 5052c221; if
lower, revert only the entity-binding half with `RetrievalAblation`-guided code changes, measure, commit. Then the owner
runs the remaining prompts in Library 11, and the agent reads his trace to tick them.
