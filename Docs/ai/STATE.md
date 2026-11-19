# Current State

Updated: 2026-11-18 16:20
Branch/worktree: `main`, primary checkout
Last verified commit: 43b06f3c

## Objective

**Ship 5.8.** The owner runs his device pass on the checklist page https://claude.ai/artifact/RyYN25e7RGMAFthrKnBtNT
(12 prompts; every file they need is in iCloud Drive › "OpenIntelligence 5.8 check"; ticks now sync across devices
through the page's shared store, readable with ArtifactData collection `pass`, doc `checks`), says "done", the agent
closes rows from the logs, and only at his word starts Xcode Cloud and pushes store text; he submits. No rating reset on 5.8.

## Status

All of today's work is committed and pushed (`[ci skip]`, no Xcode Cloud build). Both devices run a Debug build of
HEAD's code (iPhone installed 16:08, Mac 16:09, 2026-11-18). Tests run today on an iOS 27 simulator, all passing:
GuideLibraryTests 7, DeletedLibraryLeftoversTests 11, EmbeddingConcurrencyIdentityTests 4, IngestionModeSwitchTests 2,
AnswerWritingSpeedTests 12, AtlasLabelingTests 29 (3 skipped), AtlasLabelSizeTests 20, MarkdownLabelBulletTests 18.
Full suite not run today.

## Completed on 2026-11-18 (pushed)

| Commit | What |
|---|---|
| 5934c8e8 | Library Settings no longer overflows the main thread's stack in a Debug build (`SeparatelyBuilt`); Guide library documents can't be deleted |
| b3f83ec8 | Guide library permanent (no delete, read-only settings, takes no files, restored at Documents open); "General" renamed "Library 1" once (description marker) at load and in `WorkspaceSyncService.mergeContainers`; Core ML embedder follows the app into the background (CPU and Neural Engine) and the mode switch has its own lock (fixed a 2 min 20 s background hang and a 0x8BADF00D watchdog kill on his iPhone) |
| dc6cc426 | A bold label bullet in an answer draws as a heading |
| f141eee8 | Semantic Atlas: cluster names draw again (chamfered `SCNText` draws nothing on iOS 27), no lines to nowhere, short names, label-size words, no overlap |
| 43b06f3c | Tokens per second is the final answer's writing speed, live and saved, in every mode |

Earlier today: 1453b194 (guide first in every row), 75bf6d3f and 46b9055a (Model Parameters), f5759e4d and e4a191cd (sync).

## Not verified on a device

All of the above. The closing checks: Library Settings with Technical Details on opens on the iPhone; an import left
in the background finishes or resumes at once on return; the Guide library shows no Delete, Add, Paste or settings
edits, and returns if missing; the first library reads "Library 1" on both devices with no sync churn; the Atlas card on
the iPhone; tokens per second during a Deep Think answer. Still open from this morning: the wrong-entity "0.20" answer
fix (agent worktree `/private/tmp/oi-bind-wt`, patch due at `/private/tmp/oi-bind.diff`, measurements in
`BenchmarkRuns/2026-11-18-entity-binding`).

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

Read the entity-binding agent's result (`/private/tmp/oi-bind.diff` and `BenchmarkRuns/2026-11-18-entity-binding`),
get a refuting review, and if Standard answers "What is the similarity floor in Standard mode?" with 0.28 in its
measurements, commit it with docs and install on both devices. Then wait for the owner's "done" on the device pass and
run `python3 scripts/phone_evidence.py --since <16:08 local, 2026-11-18> --json` (and `--mac --since 16:09`).
